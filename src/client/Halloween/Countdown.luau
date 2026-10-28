--!strict
-- Countdown: the Halloween event's countdown and its start (hw-core; R1.6). From 18:30 to 19:00
-- EDT (Config.Halloween.CountdownAt to StartsAt, the event's clock) a player the event may show
-- to (HwOn) sees an Ink pill at the top middle (SkyBanner's look) with the Candy icon and
-- "HALLOWEEN EVENT IN 29:59", while the lobby is quiet (Progression.quiet: never in a match or
-- over a menu or popup). It sits in the Banner's spot under Roblox's top bar and moves below
-- the Banner, the global queue's card and the tutorial's quest line while they show; SkyBanner
-- and the Players list keep to the top right. At 19:00 sharp it says "THE HALLOWEEN EVENT HAS
-- STARTED!" in gold for StartedSeconds with a burst (the HALLOWEEN tile waits for it, then pops
-- in with NEW: EventButton reads Countdown.holding); a player busy at 19:00 gets it the moment
-- the lobby goes quiet, within StartedWindowSeconds, else not at all. No menu opens by itself.
-- While Live with the timed Pumpkin King (Config.HalloweenMap.Boss.Mode "Timed"; designer
-- 2026-10-28) the same pill, with the crown, counts to his next visit ("PUMPKIN KING IN 14:22")
-- and then, in gold, to its end ("PUMPKIN KING IS HERE! 9:41"); hidden in Throne mode. A tap,
-- or A on it as a controller stop (HubCorners.padStops), shows the guide to him (the tutorial
-- arrow's chevrons in one beam from the body, its arrowhead over him) until the player is near
-- him, taps again, or GuideSeconds pass. One 1 s clock, never per frame.
local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local GuiQA = require(script.Parent.Parent.GuiQA)
local HudParts = require(script.Parent.Parent.HudParts)
local UIAnim = require(script.Parent.Parent.UIAnim)
local UISound = require(script.Parent.Parent.UISound)
local State = require(script.Parent.State)

local H = Config.Halloween
local U = Config.UI.Halloween.Countdown
local B = Config.UI.Menu.Banner
local SKY = Config.UI.SkyBanner
local KING = Config.UI.Halloween.King
local ARROW = Config.Tutorial.Arrow
local CROWN: string = Config.UI.Kit.Icons.Crown or H.CandyIcon -- the King's timer's icon
local W = Strings.Halloween
local SHORT = Config.Multiplayer.Style.ShortHeight
local BIG = Vector2.new(10000, 1000)

local Countdown = {}

local startedUntil = 0 -- os.clock() until which the start message shows
local kingTap: TextButton? = nil -- the King's timer as a button (built with the pill)

-- The map lane's HalloweenMap/Rules (the King's schedule), read once; false without it.
local mapRules: any = nil
local function rules(): any?
	if mapRules == nil then
		local ok, module = pcall(function(): any
			local folder = Shared:FindFirstChild("HalloweenMap")
			local found = folder and folder:FindFirstChild("Rules")
			return if found and found:IsA("ModuleScript") then require(found) :: any else nil
		end)
		mapRules = if ok and type(module) == "table" then module else false
	end
	return if mapRules then mapRules else nil
end

-- Whether the map lane's King runs at all (BossService starts only with both switches on).
local function kingOn(): boolean
	local HM = (Config :: any).HalloweenMap
	return type(HM) == "table"
		and HM.Enabled == true
		and type(HM.Boss) == "table"
		and HM.Boss.Enabled == true
end

-- The King's timer at `now` (nil outside Timed mode, with the King switched off, or when his
-- next visit would start after the event's end), and whether he is here.
local function kingLine(now: number): (string?, boolean)
	local R = rules()
	if R == nil or not kingOn() or not R.kingTimed() then
		return nil, false
	end
	local start, finish = R.kingWindow(now)
	if start <= now then
		return W.KingHere:format(Event.clock(finish - now)), true
	end
	if start >= H.EndsAt then
		return nil, false
	end
	return W.KingIn:format(Event.clock(start - now)), false
end

-- Where the guide points: over the head of his figure nearest his stage (the map lane's tag),
-- else over the stage's pivot (between visits, or his figure not streamed in).
local function kingSpot(): Vector3
	local pivot = Config.HalloweenMap.Boss.Timed.Pivot
	local stage = Vector3.new(pivot[1], pivot[2], pivot[3])
	local best: Vector3? = nil
	local bestGap = math.huge
	for _, model in CollectionService:GetTagged(KING.Tag) do
		if model:IsA("Model") and model:IsDescendantOf(workspace) then
			local frame, size = model:GetBoundingBox()
			local top = frame.Position + Vector3.new(0, size.Y / 2, 0)
			local gap = (top - stage).Magnitude
			if gap < bestGap then
				best, bestGap = top, gap
			end
		end
	end
	return best or stage + Vector3.new(0, KING.SpotStuds, 0)
end

local function body(): BasePart?
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- The guide to the King, built on the first tap and then reused: a still, invisible point over
-- him, the tutorial arrow's chevrons in one beam from it to the body (the engine draws and
-- scrolls it) and its arrowhead bobbing over him (a looping tween): no per-frame script.
type Guide = { point: Part, beam: Beam, body: Attachment, head: BillboardGui, bob: Tween }
local guide: Guide? = nil
local guideUntil = 0 -- os.clock() the guide goes off by itself; 0: off
local guideShown = false

local function buildGuide(): Guide
	local point = Instance.new("Part")
	point.Name = "KingGuide"
	point.Anchored = true
	point.CanCollide = false
	point.CanQuery = false
	point.CanTouch = false
	point.CastShadow = false
	point.Transparency = 1
	point.Size = Vector3.one * 0.2
	point.Parent = workspace
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.Parent = point
	local hold = Instance.new("Attachment")
	hold.Name = "KingGuideBody"
	local beam = Instance.new("Beam")
	beam.Attachment0 = tip -- the texture's top points at Attachment0: the chevrons point at him
	beam.Attachment1 = hold
	beam.Texture = ARROW.Chevron
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = ARROW.ChevronStuds
	beam.TextureSpeed = KING.FlowPerSecond
	beam.FaceCamera = true
	beam.LightInfluence = 0
	beam.LightEmission = 0
	beam.Segments = 10 -- the fade at the body needs the points (one segment fades it all)
	beam.Width0 = ARROW.WidthStuds
	beam.Width1 = ARROW.WidthStuds
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1 - KING.FadeShare, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	beam.Enabled = false
	beam.Parent = point
	local head = Instance.new("BillboardGui")
	head.Name = "KingGuideHead"
	head.Adornee = point
	head.AlwaysOnTop = false -- in the scene like the table signs (an always-on-top one did not draw)
	head.LightInfluence = 0
	head.Size = UDim2.fromOffset(KING.HeadPx, KING.HeadPx) -- pixels: seen across the roof
	head.StudsOffset = Vector3.new(0, KING.HeadLiftStuds, 0)
	head.SizeOffset = Vector2.new(0, 0.5) -- its tip on the point
	head.Enabled = false
	head.Parent = point
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = ARROW.Head
	image.ScaleType = Enum.ScaleType.Fit
	image.Rotation = 180 -- the image points up: down at him
	image.Parent = head
	local bob = TweenService:Create(
		head,
		TweenInfo.new(
			KING.HeadBobSeconds / 2,
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut,
			-1,
			true
		),
		{ SizeOffset = Vector2.new(0, 0.5 + KING.HeadBobShare) }
	)
	return { point = point, beam = beam, body = hold, head = head, bob = bob }
end

local function showGuide(on: boolean)
	local g = guide
	if g == nil or on == guideShown then
		return
	end
	guideShown = on
	g.beam.Enabled = on
	g.head.Enabled = on
	if on then
		g.bob:Play()
	else
		g.bob:Pause()
	end
end

-- The guide, each second and on a tap: on the King and the body; off for good on arrival,
-- after GuideSeconds or with the King's timer gone (`up`: Live, Timed), hidden while the
-- lobby is busy (`free`).
local function stepGuide(up: boolean, free: boolean)
	local g = guide
	if g == nil or guideUntil == 0 then
		showGuide(false)
		return
	end
	if not up or os.clock() > guideUntil then
		guideUntil = 0
		showGuide(false)
		return
	end
	local root = body()
	if root == nil or not free then
		showGuide(false)
		return
	end
	local spot = kingSpot()
	if (g.point.Position - spot).Magnitude > 0.5 then
		g.point.CFrame = CFrame.new(spot)
	end
	if
		Vector3.new(spot.X - root.Position.X, 0, spot.Z - root.Position.Z).Magnitude
		< KING.ArriveStuds
	then
		guideUntil = 0
		showGuide(false)
		return
	end
	if g.body.Parent ~= root then
		-- A new character: the old one took the attachment with it.
		g.body:Destroy()
		local hold = Instance.new("Attachment")
		hold.Name = "KingGuideBody"
		hold.Position = Vector3.new(0, KING.BodyLiftStuds, 0)
		hold.Parent = root
		g.body = hold
		g.beam.Attachment1 = hold
	end
	showGuide(true)
end

-- Progression, read late (it builds this module).
local function quiet(): boolean
	local ok, P = pcall(require, script.Parent.Parent.Progression)
	return ok and type(P) == "table" and P.quiet() == true
end

-- Whether a GuiObject shows (it and every holder visible, its ScreenGui on).
local function shows(object: Instance?): boolean
	if object == nil or not object:IsA("GuiObject") or object.AbsoluteSize.Y <= 0 then
		return false
	end
	local at: Instance? = object
	while at and not at:IsA("PlayerGui") do
		if (at:IsA("GuiObject") and not at.Visible) or (at:IsA("ScreenGui") and not at.Enabled) then
			return false
		end
		at = at.Parent
	end
	return true
end

--- Whether the start message is up (the tile waits for it).
function Countdown.holding(): boolean
	return os.clock() < startedUntil
end

--- The King's timer as a controller stop (HubCorners.padStops; visible only while it shows).
function Countdown.padStop(): GuiObject?
	return kingTap
end

--- Built once by Progression in the HUD's screen (its origin is under Roblox's top bar).
function Countdown.new(screen: ScreenGui)
	local pill = HudParts.pill(screen, "HalloweenCountdown", HudParts.tone("Ink"))
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.BackgroundTransparency = SKY.BackTransparency
	pill.Visible = false
	pill.ZIndex = U.ZIndex
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = H.CandyIcon
	icon.ZIndex = U.ZIndex + 1
	icon.Parent = pill
	local text = HudParts.text(pill, "Words", U.TextPx, "")
	text.TextWrapped = false
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.AutoLocalize = false
	text.ZIndex = U.ZIndex + 1
	-- The King's timer is a button: its tap area at least MinHitPx tall, centred on the pill.
	local tap = Instance.new("TextButton")
	tap.Name = "KingTap"
	tap.Text = ""
	tap.AutoButtonColor = false
	tap.BackgroundTransparency = 1
	tap.Selectable = false -- HubCorners makes it a pad stop while the pad is in the corners
	tap.AnchorPoint = Vector2.new(0.5, 0.5)
	tap.Position = UDim2.fromScale(0.5, 0.5)
	tap.Size = UDim2.fromScale(1, 1)
	tap.Visible = false
	tap.ZIndex = U.ZIndex + 2
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(0, KING.MinHitPx)
	least.Parent = tap
	tap.Parent = pill
	kingTap = tap

	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	-- What it keeps under: the Banner's strip, the global queue's card, the tutorial's quest.
	local function obstacles(): { Instance? }
		local soft = playerGui and playerGui:FindFirstChild("TutorialSoftGui")
		return {
			screen:FindFirstChild("Banner"),
			screen:FindFirstChild("QueueStatus"),
			soft and soft:FindFirstChild("Quest"),
		}
	end

	local function place(words: string, gold: boolean, image: string)
		local short = screen.AbsoluteSize.Y < SHORT
		local px = if short then U.ShortTextPx else U.TextPx
		local h = px + 2 * U.PadPx
		local iconPx = math.floor(h * U.IconShare)
		local textW = math.ceil(
			TextService:GetTextSize(words, px, HudParts.measureFont(text), BIG).X
		) + 4
		local w = U.PadPx + iconPx + U.GapPx + textW + U.PadPx
		local origin = screen.AbsolutePosition
		local left = (screen.AbsoluteSize.X - w) / 2
		local top = B.TopPx
		for _, other in obstacles() do
			if shows(other) then
				local o = other :: GuiObject
				local x0 = o.AbsolutePosition.X - origin.X
				local x1 = x0 + o.AbsoluteSize.X
				local bottom = o.AbsolutePosition.Y + o.AbsoluteSize.Y - origin.Y
				if x1 > left and x0 < left + w and bottom + U.GapBelowPx > top then
					top = bottom + U.GapBelowPx
				end
			end
		end
		text.Text = words
		text.TextColor3 = if gold then HudParts.tone("Gold") else HudParts.tone("White")
		icon.Image = image
		HudParts.setTextSize(text, px)
		pill.Position = UDim2.new(0.5, 0, 0, top)
		pill.Size = UDim2.fromOffset(w, h)
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
		icon.Position = UDim2.fromOffset(U.PadPx, math.floor((h - iconPx) / 2))
		text.Position = UDim2.fromOffset(U.PadPx + iconPx + U.GapPx, 0)
		text.Size = UDim2.fromOffset(textW, h)
	end

	local pendingStart = false -- 19:00 passed while counting down; the message waits for quiet
	local wasCounting = false
	local kingUp = false -- the King's timer runs (Live, Timed), shown or not
	local kingHere = false
	local lastFree = false
	local function showTap(on: boolean)
		tap.Visible = on
		if not on and GuiService.SelectedObject == tap then
			GuiService.SelectedObject = nil
		end
	end
	-- A press: the guide on, or off when it is on.
	local function press(): boolean
		if not (tap.Visible and pill.Visible) then
			return false
		end
		UISound.play("Click")
		if guideUntil > 0 then
			guideUntil = 0
		else
			guide = guide or buildGuide()
			guideUntil = os.clock() + KING.GuideSeconds
		end
		stepGuide(kingUp, lastFree)
		return true
	end
	tap.Activated:Connect(press)
	-- Studio QA: GuiQA:Invoke("hwKing") presses the King's timer; (pressed, guide shown).
	GuiQA.add("hwKing", function(): (boolean, boolean)
		return press(), guideShown
	end)
	local function tick()
		local now = Clock.now()
		local phase = State.phase()
		if phase == "Countdown" then
			wasCounting = true
		elseif phase == "Live" and wasCounting then
			wasCounting = false
			pendingStart = now - H.StartsAt <= U.StartedWindowSeconds
		end
		if pendingStart and now - H.StartsAt > U.StartedWindowSeconds then
			pendingStart = false
		end
		local free = quiet()
		if pendingStart and free then
			pendingStart = false
			startedUntil = os.clock() + U.StartedSeconds
			place(W.Started, true, H.CandyIcon)
			showTap(false)
			pill.Visible = true
			UIAnim.popIn(pill)
			UIAnim.slam(text, HudParts.tone("Gold"), { burst = true })
			UIAnim.glowBurst(pill, HudParts.tone("Gold"), 0.8)
			return
		end
		if Countdown.holding() then
			pill.Visible = free
			return
		end
		local words: string?, gold, image = nil, false, H.CandyIcon
		if phase == "Countdown" then
			words = W.Countdown:format(Event.clock(Event.startsIn(now)))
		elseif phase == "Live" then
			local line, here = kingLine(now)
			kingUp = line ~= nil
			if line and here and not kingHere and pill.Visible and free then
				UIAnim.slam(text, HudParts.tone("Gold"), { burst = true }) -- he has come
			end
			kingHere = here
			words, gold, image = line, here, CROWN
		end
		if phase ~= "Live" then
			kingUp = false
		end
		lastFree = free
		if words and free then
			place(words, gold, image)
			if not pill.Visible then
				pill.Visible = true
				UIAnim.popIn(pill)
			end
		else
			pill.Visible = false
		end
		showTap(kingUp and pill.Visible)
		stepGuide(kingUp, free)
	end
	task.spawn(function()
		while screen.Parent ~= nil do
			local ok, err = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn("[8ball] Halloween countdown: " .. tostring(err))
			end
			task.wait(1)
		end
	end)
end

return Countdown
