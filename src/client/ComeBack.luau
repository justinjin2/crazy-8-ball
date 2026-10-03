--!strict
-- ComeBack: keeping players (GUI lane, designer 2026-10-03, C15, D3).
--   * (Off for now: Config.UI.ComeBack.ShowOnLeave; designer 2026-10-03.)
--   * Every time Roblox's menu opens or the window loses focus: a big "COME BACK TOMORROW FOR"
--     over tomorrow's login reward (its pictures in a gold ring with turning rays, and the
--     reward in words under it), in the middle of the screen. It stays while the player is
--     away and goes LingerSeconds after they are back. Nothing when tomorrow's reward is not
--     known yet.
--   * The first time ever, the server gifts a Rare Case on its normal timer (RewardRequest
--     "ClaimLeaveGift", once per save: Flags.LeaveGift). When the player comes back, through
--     the popup queue (never in a match): the case falls out of the sky in front of them, the
--     camera looks up at it and follows it down as it crashes (a gold ring on the floor,
--     sparkles, a shake), and big words say it is theirs and when it opens. The camera comes
--     back exactly as it was. Once seen (Seen "LeaveGift"), a tap skips it.
-- Sizes in Config.UI.ComeBack and Config.Cutscenes.LeaveGift, words in Strings.ComeBack.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Cases = require(Shared:WaitForChild("Progression"):WaitForChild("Cases"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Popups = require(script.Parent.Popups)
local RewardChips = require(script.Parent.RewardChips)
local RewardsParts = require(script.Parent.RewardsParts)
local Seen = require(script.Parent.Seen)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local U = Config.UI.ComeBack
local G = Config.Cutscenes.LeaveGift
local K = Config.UI.Kit
local W = Strings.ComeBack
local RENDER_NAME = "ComeBackGift"
local SEEN_KIND = "LeaveGift"
local BASE_HEIGHT = 1080

local ComeBack = {}

local started = false
local playing = false -- the gift's scene is up

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

-- "1 hour", "6 hours", "30 minutes".
local function duration(seconds: number): string
	if seconds >= 3600 then
		local hours = math.floor(seconds / 3600 + 0.5)
		return if hours == 1 then W.Hour else W.Hours:format(hours)
	end
	return W.Minutes:format(math.max(1, math.floor(seconds / 60 + 0.5)))
end

local function caseName(caseId: string): string
	local names: { [string]: string } = Strings.Items.Cases :: any
	return names[caseId] or caseId
end

--------------------------------------------------------------------------------------------
-- The gift's scene
--------------------------------------------------------------------------------------------

-- Plays the gift's scene; `done` runs once the camera is back.
local function playGift(gui: ScreenGui, caseId: string, done: () -> ())
	playing = true
	local me = Players.LocalPlayer
	local character = me and me.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	local folder = Instance.new("Folder")
	folder.Name = "LeaveGift"
	folder.Parent = workspace
	local words = HudParts.frame(gui, "Gift")
	words.AnchorPoint = Vector2.new(0.5, 0)
	words.Position = UDim2.fromScale(0.5, 0.12)
	words.Size = UDim2.fromOffset(U.WidthPx, U.GiftTitlePx + 2 * U.GiftLinePx + 40)
	words.Visible = false
	local scale = Instance.new("UIScale")
	scale.Scale = math.max(U.MinScale, math.min(1, gui.AbsoluteSize.Y / BASE_HEIGHT * 1.4))
	scale.Parent = words
	local title = HudParts.text(words, "Title", U.GiftTitlePx, W.Gifted, HudParts.color(G.Gold))
	title.Size = UDim2.new(1, 0, 0, U.GiftTitlePx + 8)
	title.TextWrapped = false
	local line = HudParts.text(
		words,
		"Line",
		U.GiftLinePx,
		W.GiftLine:format(caseName(caseId), duration(Cases.timer(caseId)))
	)
	line.Position = UDim2.fromOffset(0, U.GiftTitlePx + 14)
	line.Size = UDim2.new(1, 0, 0, U.GiftLinePx + 6)
	local where = HudParts.text(words, "Where", U.GiftLinePx - 6, W.GiftWhere)
	where.Position = UDim2.fromOffset(0, U.GiftTitlePx + U.GiftLinePx + 24)
	where.Size = UDim2.new(1, 0, 0, U.GiftLinePx)

	local finished = false
	local saved = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		fov = cam.FieldOfView,
	}
	local skipConnection: RBXScriptConnection? = nil
	local function finish()
		if finished then
			return
		end
		finished = true
		RunService:UnbindFromRenderStep(RENDER_NAME)
		if skipConnection then
			skipConnection:Disconnect()
		end
		folder:Destroy()
		words:Destroy()
		local c = workspace.CurrentCamera
		c.CameraType = if saved.kind == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else saved.kind
		if saved.subject and saved.subject.Parent then
			c.CameraSubject = saved.subject
		end
		c.FieldOfView = saved.fov
		Seen.mark(SEEN_KIND)
		playing = false
		task.spawn(done)
	end

	local function showWords()
		words.Visible = true
		UIAnim.slam(title, HudParts.color(G.Gold))
		UIAnim.shake(title)
		UISound.play("Claim")
	end

	if not (root and root:IsA("BasePart")) then
		-- No body to film: the words alone.
		showWords()
		task.delay(G.HoldSeconds, finish)
		return
	end

	-- Where: in front of the player, on the floor there.
	local flat = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	flat = if flat.Magnitude < 1e-3 then Vector3.new(0, 0, -1) else flat.Unit
	local feet = root.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character :: Instance, folder }
	local ahead = feet + flat * G.AheadStuds
	local hit = workspace:Raycast(ahead + Vector3.yAxis * 10, Vector3.new(0, -40, 0), params)
	local land = if hit then hit.Position else Vector3.new(ahead.X, feet.Y - 3, ahead.Z)
	local sky = land + Vector3.yAxis * G.SkyStuds
	local side = flat:Cross(Vector3.yAxis)
	local camAt = feet
		- flat * G.CameraBackStuds
		+ side * G.CameraSideStuds
		+ Vector3.yAxis * G.CameraUpStuds

	-- The case: its picture standing in the world, with a gold trail.
	local case = Instance.new("Part")
	case.Name = "Case"
	case.Anchored = true
	case.CanCollide = false
	case.CanQuery = false
	case.CanTouch = false
	case.Transparency = 1
	case.Size = Vector3.new(1, 1, 1)
	case.CFrame = CFrame.new(sky)
	case.Parent = folder
	local board = Instance.new("BillboardGui")
	board.Size = UDim2.fromScale(G.CaseStuds, G.CaseStuds)
	board.LightInfluence = 0
	board.Parent = case
	local picture = Instance.new("ImageLabel")
	picture.BackgroundTransparency = 1
	picture.Size = UDim2.fromScale(1, 1)
	picture.ScaleType = Enum.ScaleType.Fit
	picture.Image = K.Icons[RewardChips.caseIcon(caseId)] or ""
	picture.Parent = board
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1, 0)
	a0.Parent = case
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1, 0)
	a1.Parent = case
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(HudParts.color(G.Gold))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.Parent = case

	local started = os.clock()
	local crashed = false
	local lookAt = sky
	local shakeUntil = 0
	local function crash()
		crashed = true
		case.CFrame = CFrame.new(land + Vector3.yAxis * (G.CaseStuds / 2))
		-- The ring on the floor.
		local ring = Instance.new("Part")
		ring.Name = "Shock"
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.Shape = Enum.PartType.Cylinder
		ring.Material = Enum.Material.Neon
		ring.Color = HudParts.color(G.Gold)
		ring.Size = Vector3.new(0.2, 1, 1)
		ring.CFrame = CFrame.new(land + Vector3.yAxis * 0.1) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = folder
		TweenService:Create(ring, TweenInfo.new(G.ShockSeconds, Enum.EasingStyle.Quad), {
			Size = Vector3.new(0.2, G.ShockStuds, G.ShockStuds),
			Transparency = 1,
		}):Play()
		-- Sparkles thrown up.
		local dust = Instance.new("ParticleEmitter")
		dust.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		dust.Color = ColorSequence.new(HudParts.color(G.Gold))
		dust.LightEmission = 1
		dust.Speed = NumberRange.new(10, 22)
		dust.SpreadAngle = Vector2.new(70, 70)
		dust.Lifetime = NumberRange.new(0.6, 1.1)
		dust.Acceleration = Vector3.new(0, -30, 0)
		dust.Size = NumberSequence.new(0.8, 0)
		dust.EmissionDirection = Enum.NormalId.Top
		dust.Rate = 0
		dust.Parent = ring
		dust:Emit(G.DustCount)
		UISound.play("Shockwave")
		shakeUntil = os.clock() + G.ShakeSeconds
		showWords()
		task.delay(G.HoldSeconds, finish)
	end

	RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Camera.Value + 10, function()
		if finished then
			return
		end
		local c = workspace.CurrentCamera
		c.CameraType = Enum.CameraType.Scriptable
		local t = os.clock() - started
		if not crashed then
			if t < G.LookUpSeconds then
				-- Looking up from the player toward the case in the sky.
				local from = land + Vector3.yAxis * 2
				lookAt = from:Lerp(sky, smooth(t / G.LookUpSeconds))
			else
				-- The fall, faster and faster; the camera follows it down.
				local f = math.clamp((t - G.LookUpSeconds) / G.FallSeconds, 0, 1)
				local at = sky:Lerp(land + Vector3.yAxis * (G.CaseStuds / 2), f * f)
				case.CFrame = CFrame.new(at)
				lookAt = at
				if f >= 1 then
					crash()
				end
			end
		end
		local shake = Vector3.zero
		if os.clock() < shakeUntil then
			local k = G.ShakeStuds * (shakeUntil - os.clock()) / G.ShakeSeconds
			shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				* 2
				* k
		end
		c.CFrame = CFrame.lookAt(camAt + shake, lookAt)
	end)

	if Seen.get(SEEN_KIND) then
		skipConnection = UserInputService.InputBegan:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if
				kind == Enum.UserInputType.MouseButton1
				or kind == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA
			then
				finish()
			end
		end)
	end
end

--------------------------------------------------------------------------------------------
-- The message
--------------------------------------------------------------------------------------------

--- Start listening for Roblox's menu and the window (Progression, once). `screen` is the HUD's
--- ScreenGui; `source` gives tomorrow's login reward table (RewardState.next) or nil.
function ComeBack.start(screen: ScreenGui, source: () -> any?)
	if started then
		return
	end
	started = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "ComeBack"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = U.DisplayOrder
	gui.Parent = screen.Parent

	local root = HudParts.frame(gui, "Message")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(U.WidthPx, U.HeightPx)
	root.Visible = false
	local fit = Instance.new("UIScale")
	fit.Parent = root
	local ringTop = U.TitlePx + 30
	local rays = HudParts.icon(root, "Rays", "Rays")
	rays.Image = K.Art.Rays
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.Position = UDim2.fromOffset(U.WidthPx / 2, ringTop + U.RingPx / 2)
	rays.Size = UDim2.fromOffset(U.RingPx * U.RaysShare, U.RingPx * U.RaysShare)
	rays.ImageColor3 = HudParts.color(K.Numbers.Money)
	rays.ZIndex = 1
	local ring = HudParts.frame(root, "Ring")
	ring.AnchorPoint = Vector2.new(0.5, 0)
	ring.Position = UDim2.fromOffset(U.WidthPx / 2, ringTop)
	ring.Size = UDim2.fromOffset(U.RingPx, U.RingPx)
	ring.BackgroundTransparency = 0
	ring.BackgroundColor3 = HudParts.tone("White")
	ring.ZIndex = 2
	HudParts.corner(ring, 999)
	local edge = Instance.new("UIStroke")
	edge.Color = HudParts.color(K.Numbers.Money)
	edge.Thickness = U.RingStrokePx
	edge.Parent = ring
	local ink = Instance.new("UIStroke")
	ink.Name = "Ink"
	ink.Color = HudParts.tone("Ink")
	ink.Thickness = 3
	ink.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ink.Parent = ring
	local pictures = RewardsParts.newPictures(ring, "Pictures", 3)
	pictures.root.Position = UDim2.fromScale(0.5, 0.5)
	local title = HudParts.text(root, "Title", U.TitlePx, W.Title, HudParts.color(K.Numbers.Money))
	title.Size = UDim2.new(1, 0, 0, U.TitlePx + 10)
	title.TextWrapped = false
	title.ZIndex = 3
	local line = HudParts.text(root, "Line", U.LinePx, "")
	line.Position = UDim2.fromOffset(0, ringTop + U.RingPx + 16)
	line.Size = UDim2.new(1, 0, 0, U.LinePx + 8)
	line.ZIndex = 3

	local away = false
	local token = 0
	local loops: { UIAnim.Handle } = {}
	local asked = false
	local giftReady: string? = nil

	local function stopLoops()
		for _, h in loops do
			h.stop()
		end
		table.clear(loops)
	end

	local function hide()
		if root.Visible then
			stopLoops()
			UIAnim.popOut(root)
		end
	end

	-- The gift's scene waits for the hub (the popup queue), after the message.
	local function queueGift()
		local caseId = giftReady
		if not caseId or away then
			return
		end
		giftReady = nil
		Popups.push({
			id = "LeaveGift",
			show = function(done: () -> ())
				playGift(gui, caseId, done)
			end,
		})
	end

	local function show(): boolean
		local ok, upcoming = pcall(source)
		if not ok or type(upcoming) ~= "table" or upcoming.tomorrow == false then
			return false
		end
		local reward = RewardsParts.reward(upcoming.reward)
		if RewardsParts.isEmpty(reward) then
			return false
		end
		RewardsParts.setPictures(pictures, reward)
		RewardsParts.layoutPictures(pictures, U.PicturePx, U.RingPx * 0.8, 22)
		line.Text = RewardsParts.summary(reward)
		local h = gui.AbsoluteSize.Y
		fit.Scale = math.max(U.MinScale, math.min(1, h / BASE_HEIGHT * 1.25))
		root.Visible = true
		UIAnim.popIn(root)
		stopLoops()
		table.insert(loops, UIAnim.spin(rays, U.RaysDegreesPerSecond))
		table.insert(loops, UIAnim.shake(title))
		table.insert(loops, UIAnim.pulse(ring))
		return true
	end

	local function trigger()
		away = true
		token += 1
		if U.ShowOnLeave and not root.Visible then
			show()
		end
		-- The first time ever: the gift (the server says no after the first).
		if not asked then
			asked = true
			task.spawn(function()
				local reply = ItemState.request("RewardRequest", "ClaimLeaveGift")
				if type(reply) == "table" and reply.ok == true then
					giftReady = Config.Social.LeaveGift.Case
					queueGift()
				end
			end)
		end
	end

	local function back()
		away = false
		token += 1
		local mine = token
		task.delay(U.LingerSeconds, function()
			if mine == token and not away then
				hide()
				queueGift()
			end
		end)
	end

	GuiService.MenuOpened:Connect(trigger)
	GuiService.MenuClosed:Connect(back)
	UserInputService.WindowFocusReleased:Connect(trigger)
	UserInputService.WindowFocused:Connect(back)
	-- Studio checks: GuiQA "comeBack" ("away" or "back") plays the menu opening or closing;
	-- "leaveGift" (caseId) plays the gift's scene without the server.
	GuiQA.add("comeBack", function(state: string)
		if state == "away" then
			trigger()
		else
			back()
		end
		return true
	end)
	GuiQA.add("leaveGift", function(caseId: string?)
		giftReady = caseId or Config.Social.LeaveGift.Case
		queueGift()
		return true
	end)
end

--- Whether the gift's scene is up (Progression hides the HUD meanwhile).
function ComeBack.isPlaying(): boolean
	return playing
end

return ComeBack
