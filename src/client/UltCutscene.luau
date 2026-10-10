--!strict
-- UltCutscene: the ~0.8 s manga panel an ult's activation plays for everyone in the match
-- (docs/prompts/ULTIMATES_PROMPT.md 7.2, reference 10, UI_STYLE 11). Numbers in
-- Config.UI.UltCutscene; words in Strings.Ults.Cutscene and Strings.Ults.Names.
--
-- It watches every table's snapshot. `ults.armed` with an `at` newer than the last one seen
-- at that table is a new activation: the panel plays if this player is in that match (seated
-- there; ScreenFx.involved) and it is still fresh (server time
-- minus `armed.at` under Config.Ults.CutsceneSeconds), so a late join never plays it and a
-- repeated snapshot never plays it twice. A client that hears late starts part-way in, on the
-- server's clock. At `armed.readyAt` (the arming moment, about 1 s after the panel has gone)
-- it tells its onArming listeners, so the ult's own look (through AbilityFx) can play its arming.
--
-- The panel: a white, ink-outlined band tilted TiltDegrees across the middle, HeightShare of
-- the screen tall and wider than the screen. Inside, the kit's white with a thick line in the
-- ult's rarity colour round it and a soft glow of that colour behind the avatar (the designer,
-- 2026-09-28; BackdropArt brings back the old dark swirl), a few speed lines in that colour,
-- and the activating player's avatar: a client clone of their character, re-posed to its rest
-- pose (the table's shooter is bent over the cue), in a ViewportFrame with a slow
-- push-in. "ULTIMATE" sits over the top edge at the left, the ult's name over the bottom edge
-- at the right, and the ult's icon stamps in beside the avatar (ABILITIES_PROMPT 5.1) with a
-- burst of its rarity colour. It slams in, holds, shrinks to a thin line and snaps away.
--
-- It never takes input: its own ScreenGui, nothing Active or Modal, no dim (UI_STYLE 2). The
-- game has no reduced-motion or mute setting yet, so it always plays in full.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent:WaitForChild("HudParts"))
local Letterbox = require(script.Parent:WaitForChild("Letterbox"))
local UIAnim = require(script.Parent:WaitForChild("UIAnim"))
local ScreenFx = require(script.Parent:WaitForChild("ScreenFx"))
local People = require(script.Parent:WaitForChild("People"))

local C = Config.UI.UltCutscene
local U = Config.Ults
local K = Config.UI.Kit

local player = Players.LocalPlayer

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smooth(t: number): number
	local x = clamp01(t)
	return x * x * (3 - 2 * x)
end

local function quadIn(t: number): number
	local x = clamp01(t)
	return x * x
end

-- The armed ult as the snapshot carries it (src/shared/Ults/Match.luau).
export type Armed = {
	by: number,
	id: string,
	stage: string,
	at: number,
	readyAt: number,
	seq: number,
	practice: boolean?,
}

type Line = { frame: Frame, y: number, length: number, start: number, speed: number }

type Play = {
	tableId: number,
	avatar: Model, -- the activator's copy (handed back to the cache when it ends)
	avatarBy: number,
	mine: boolean, -- the local player is seated at that table
	started: number, -- os.clock() at elapsed 0
	root: Frame,
	panel: Frame,
	panelScale: UIScale,
	inner: Frame,
	backdrop: ImageLabel?,
	lines: { Line },
	title: TextLabel,
	name: TextLabel,
	titleScale: UIScale,
	nameScale: UIScale,
	icon: ImageLabel?, -- the ult's icon, stamped in beside the avatar (nil when it has none)
	iconScale: UIScale?,
	glow: ImageLabel?, -- the burst of rarity colour behind it
	iconPx: number,
	words: Frame, -- a clear twin of the panel over the avatar, holding the words
	wordsScale: UIScale,
	window: Frame, -- the avatar's upright window inside the band (clips the viewport)
	windowScale: UIScale,
	windowW: number,
	windowX: number, -- its centre, in pixels right of the panel's centre along the band
	viewport: ViewportFrame,
	camera: Camera,
	focus: Vector3,
	distance: number,
	visibleHeight: number,
	-- layout, in pixels
	screenW: number,
	panelW: number,
	panelH: number,
	border: number,
	innerW: number,
	innerH: number,
	cropW: number,
	eyeShare: number, -- where across the inner frame the calm eye should sit (0-1)
	connection: RBXScriptConnection?,
}

local UltCutscene = {}
UltCutscene.__index = UltCutscene

export type UltCutscene = typeof(setmetatable(
	{} :: {
		hub: any,
		-- tableId -> the newest armed.at seen there (server seconds)
		seen: { [number]: number },
		armingListeners: { (number, Armed) -> () },
	},
	UltCutscene
))

---------------------------------------------------------------------------------------------
-- The screen and the sound (shared by every play, made once)
---------------------------------------------------------------------------------------------

local gui: ScreenGui? = nil
local activate: Sound? = nil
local current: Play? = nil

local function ensureGui(): ScreenGui
	if gui and gui.Parent then
		return gui
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "UltCutscene"
	screen.ResetOnSpawn = false
	-- The whole screen, Roblox's top bar and a phone's notch and corners included: the band
	-- runs edge to edge (designer, 2026-10-10: on an iPhone it stopped short of the sides).
	Letterbox.screen(screen)
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local hud = player:WaitForChild("PlayerGui"):FindFirstChild("PoolHud")
	local base = if hud and hud:IsA("ScreenGui") then hud.DisplayOrder else 0
	screen.DisplayOrder = base + C.DisplayOrderAbove
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

local function ensureSound(): Sound?
	local A = U.Audio.Activate
	if A.Id == "" then
		return nil
	end
	if activate and activate.Parent then
		return activate
	end
	local sound = Instance.new("Sound")
	sound.Name = "UltActivate"
	sound.SoundId = A.Id
	sound.Volume = A.Volume
	sound.Parent = SoundService
	activate = sound
	return sound
end

local preloaded = false
local function preload()
	if preloaded then
		return
	end
	preloaded = true
	local list: { any } = {}
	local sound = ensureSound()
	if sound then
		table.insert(list, sound)
	end
	if C.BackdropArt and K.Art.UltBackdrop ~= "" then
		table.insert(list, K.Art.UltBackdrop)
	end
	-- Every ult's icon (the cutscene, the armed pills, the spin screen and the top bar all
	-- show them) and the glow behind the stamp.
	for _, id in Catalog.list() do
		local icon = Catalog.icon(id)
		if icon ~= "" then
			table.insert(list, icon)
		end
	end
	if K.Art.SoftGlow ~= "" then
		table.insert(list, K.Art.SoftGlow)
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

---------------------------------------------------------------------------------------------
-- The avatar
---------------------------------------------------------------------------------------------

local STRIP: { [string]: boolean } = {
	Sound = true,
	BillboardGui = true,
	SurfaceGui = true,
	Highlight = true,
	ProximityPrompt = true,
	ForceField = true,
}

-- Parts joined to `part`, each with how the other sits relative to it (other = part * rel).
type Edge = { other: BasePart, rel: CFrame }

local function link(edges: { [BasePart]: { Edge } }, a: BasePart?, b: BasePart?, rel: CFrame)
	if a == nil or b == nil or a == b then
		return
	end
	local fromA = edges[a] or {}
	edges[a] = fromA
	table.insert(fromA, { other = b, rel = rel })
	local fromB = edges[b] or {}
	edges[b] = fromB
	table.insert(fromB, { other = a, rel = rel:Inverse() })
end

local function attachmentPart(a: any): BasePart?
	if a and a:IsA("Attachment") and a.Parent and a.Parent:IsA("BasePart") then
		return a.Parent
	end
	return nil
end

-- Put every part of `model` back in its rest pose around `rootCFrame`: the table's pose moves
-- anchored parts and never drives the joints (AvatarPose), so the joints' own offsets are the
-- rest pose. Rigid joints keep the relation they have now (hats stay on heads).
local function restPose(model: Model, root: BasePart, rootCFrame: CFrame)
	local edges: { [BasePart]: { Edge } } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") then
			local j = d :: JointInstance
			link(edges, j.Part0, j.Part1, j.C0 * j.C1:Inverse())
		elseif d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
			local c = d :: any
			local a0, a1 = c.Attachment0, c.Attachment1
			local p0, p1 = attachmentPart(a0), attachmentPart(a1)
			if p0 and p1 then
				link(edges, p0, p1, a0.CFrame * a1.CFrame:Inverse())
			end
		elseif d:IsA("WeldConstraint") then
			local w = d :: WeldConstraint
			local p0, p1 = w.Part0, w.Part1
			if p0 and p1 then
				link(edges, p0, p1, p0.CFrame:ToObjectSpace(p1.CFrame))
			end
		end
	end
	local placed: { [BasePart]: CFrame } = { [root] = rootCFrame }
	local done: { [BasePart]: boolean } = { [root] = true }
	local queue: { BasePart } = { root }
	local head = 1
	while head <= #queue do
		local part = queue[head]
		head += 1
		local list = edges[part]
		if list then
			for _, edge in list do
				if not done[edge.other] then
					done[edge.other] = true
					placed[edge.other] = placed[part] * edge.rel
					table.insert(queue, edge.other)
				end
			end
		end
	end
	-- Anything not joined to the root keeps its place relative to the root.
	local rootWas = root.CFrame
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			part.Anchored = true
			part.CFrame = placed[part] or rootCFrame * rootWas:ToObjectSpace(part.CFrame)
		end
	end
end

-- A plain ink figure for an activator with no character (a pretend QA player).
local function silhouette(): Model
	local model = Instance.new("Model")
	model.Name = "Silhouette"
	local color = rgb(C.SilhouetteColor)
	local function block(name: string, size: Vector3, at: Vector3, ball: boolean?): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Shape = if ball then Enum.PartType.Ball else Enum.PartType.Block
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CFrame = CFrame.new(at)
		part.Parent = model
		return part
	end
	local root = block("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero)
	root.Transparency = 1
	block("Torso", Vector3.new(2, 2, 1), Vector3.new(0, 0.6, 0))
	block("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 2.3, 0), true)
	block("LeftArm", Vector3.new(0.9, 2, 0.9), Vector3.new(-1.5, 0.6, 0))
	block("RightArm", Vector3.new(0.9, 2, 0.9), Vector3.new(1.5, 0.6, 0))
	model.PrimaryPart = root
	return model
end

-- A copy of `userId`'s character in its rest pose, root at the origin turned AvatarYawDegrees,
-- or the silhouette. Scripts and sounds are stripped: a LocalScript cloned into PlayerGui
-- would run, and a playing Sound would play.
local function avatarModel(userId: number): Model
	local who = People.owner(userId) -- a player or a bot (the Bots lane)
	local character = who and who.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local rootCFrame = CFrame.Angles(0, math.rad(C.AvatarYawDegrees), 0)
	if character and root and root:IsA("BasePart") then
		local was = character.Archivable
		character.Archivable = true
		local ok, copy = pcall(function()
			return character:Clone()
		end)
		character.Archivable = was
		if ok and copy then
			local model = copy :: Model
			for _, d in model:GetDescendants() do
				if d:IsA("BaseScript") or STRIP[d.ClassName] then
					d:Destroy()
				end
			end
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			local copyRoot = model:FindFirstChild("HumanoidRootPart")
			if copyRoot and copyRoot:IsA("BasePart") then
				restPose(model, copyRoot, rootCFrame)
				copyRoot.Transparency = 1
				return model
			end
			model:Destroy()
		end
	end
	local model = silhouette()
	model:PivotTo(rootCFrame)
	return model
end

-- Each seated player's copy, made ahead (warm) so an activation does not clone a whole
-- character in the frame it starts: that hitch made the ult feel slow on a phone (designer,
-- 2026-10-10). Kept with the character it was copied from; a new character makes a new copy.
local cached: { [number]: { character: Model?, model: Model } } = {}
local warming: { [number]: boolean } = {}

local function characterOf(userId: number): Model?
	local who = People.owner(userId)
	return who and who.Character or nil
end

-- The cached copy of `userId`'s character when it is still current, else a fresh one.
local function takeAvatar(userId: number): Model
	local entry = cached[userId]
	cached[userId] = nil
	if entry and entry.character == characterOf(userId) and entry.model.Parent == nil then
		return entry.model
	end
	if entry then
		entry.model:Destroy()
	end
	return avatarModel(userId)
end

-- Keep `model` (taken out of its viewport) for `userId`'s next activation.
local function giveBack(userId: number, model: Model)
	model.Parent = nil
	local old = cached[userId]
	if old and old.model ~= model then
		old.model:Destroy()
	end
	cached[userId] = { character = characterOf(userId), model = model }
end

-- Make `userId`'s copy a frame later, unless a current one is kept.
local function warm(userId: number)
	local entry = cached[userId]
	if warming[userId] or (entry and entry.character == characterOf(userId)) then
		return
	end
	warming[userId] = true
	task.defer(function()
		warming[userId] = nil
		local character = characterOf(userId)
		if character == nil then
			return
		end
		local now = cached[userId]
		if now and now.character == character then
			return
		end
		if now then
			now.model:Destroy()
		end
		cached[userId] = { character = character, model = avatarModel(userId) }
	end)
end

-- Where the camera looks and how much it must show: the upper body (waist to the top of the head
-- or its hat) fits FrameMargin of a window `aspect` wide per unit of height, its waist near the
-- window's bottom edge.
local function frameAvatar(model: Model, aspect: number): (Vector3, number)
	local root = model:FindFirstChild("HumanoidRootPart")
	local headPart = model:FindFirstChild("Head")
	local waist = if root and root:IsA("BasePart") then root.Position.Y else 0
	local top = waist + 3
	local box, boxSize = model:GetBoundingBox()
	if headPart and headPart:IsA("BasePart") then
		-- The head's top, or a hat's (an accessory counts in the bounding box), up to a point.
		local headTop = headPart.Position.Y + headPart.Size.Y / 2
		local hatTop = box.Position.Y + boxSize.Y / 2
		top = math.clamp(hatTop, headTop, headTop + headPart.Size.Y * C.HatMaxHeads)
	end
	local height = math.max(top - waist, 0.5)
	-- Wide hats and arms: fit the width too (the box is turned with the model, near enough).
	local width = math.max(boxSize.X, boxSize.Z)
	local visible = math.max(height, width / math.max(aspect, 0.1)) * C.FrameMargin
	local focus = Vector3.new(0, waist + visible / 2 + C.FocusUpShare * height, 0)
	return focus, visible
end

---------------------------------------------------------------------------------------------
-- Building the panel
---------------------------------------------------------------------------------------------

local function bigText(parent: Instance, name: string, text: string, heightPx: number): TextLabel
	local label = HudParts.text(parent, name, heightPx, text)
	label.Active = false
	local outline = label:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline.Thickness = math.max(C.OutlineMinPx, math.floor(heightPx * C.OutlineShare + 0.5))
	end
	return label
end

local function build(tableId: number, mine: boolean, armed: Armed, elapsed: number): Play
	local screen = ensureGui()
	local size = screen.AbsoluteSize
	local camera = workspace.CurrentCamera
	if (size.X < 2 or size.Y < 2) and camera then
		size = camera.ViewportSize
	end
	local W, H = math.max(size.X, 320), math.max(size.Y, 240)
	local panelH = math.floor(H * C.HeightShare)
	local panelW = math.floor(W * C.WidthShare + panelH)
	local border = math.max(C.BorderMinPx, math.floor(panelH * C.BorderShare + 0.5))
	local ink = math.max(C.InkMinPx, math.floor(panelH * C.InkShare + 0.5))
	local innerW, innerH = panelW - 2 * border, panelH - 2 * border

	local rarity = Catalog.rarity(armed.id) or "Common"
	local tint = rgb(K.Rarity[rarity] or K.Rarity.Default)

	local root = Instance.new("Frame")
	root.Name = "Cutscene"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = screen

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, C.CenterYShare)
	panel.Size = UDim2.fromOffset(panelW, panelH)
	panel.Rotation = C.TiltDegrees
	panel.BackgroundColor3 = Color3.new(1, 1, 1)
	panel.BorderSizePixel = 0
	panel.Active = false
	panel.Parent = root
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = rgb(K.Colors.Ink)
	edge.Thickness = ink
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = panel
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Position = UDim2.fromOffset(border, border)
	inner.Size = UDim2.new(1, -2 * border, 1, -2 * border)
	inner.BackgroundColor3 = rgb(C.InnerColor)
	inner.BorderSizePixel = 0
	inner.Active = false
	inner.ZIndex = 1
	inner.Parent = panel
	local innerEdge = Instance.new("UIStroke")
	innerEdge.Color = if C.BackdropArt then rgb(K.Colors.Ink) else tint
	innerEdge.Thickness = if C.BackdropArt
		then math.max(1, math.floor(ink * C.InnerInkShare + 0.5))
		else math.max(2, math.floor(ink * C.RarityEdgeShare + 0.5))
	innerEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerEdge.Parent = inner

	-- Where the calm eye of the swirl should sit: behind the avatar.
	local eyeShare = 0.5 + (C.AvatarScreenX - 0.5) * W / innerW
	local cropW = math.min(C.BackdropCropWidthPx, C.ArtSizePx)
	local backdrop: ImageLabel? = nil
	if C.BackdropArt and K.Art.UltBackdrop ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Backdrop"
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = K.Art.UltBackdrop
		image.ImageColor3 = tint:Lerp(Color3.new(1, 1, 1), C.BackdropWhiteShare)
		image.ScaleType = Enum.ScaleType.Stretch
		image.Active = false
		image.ZIndex = 1
		image.Parent = inner
		backdrop = image
	else
		-- The kit's white, with a soft glow of the rarity colour behind the avatar.
		local glow = Instance.new("UIGradient")
		local mid = clamp01(eyeShare)
		local base = rgb(C.InnerColor)
		glow.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, base),
			ColorSequenceKeypoint.new(
				math.clamp(mid, 0.01, 0.99),
				tint:Lerp(Color3.new(1, 1, 1), C.GlowWhiteShare)
			),
			ColorSequenceKeypoint.new(1, base),
		})
		glow.Parent = inner
	end

	-- Speed lines: thin white streaks racing right to left behind the avatar, cut to the frame
	-- by hand (a rotated frame cannot clip).
	local lines: { Line } = {}
	local random = Random.new(math.floor(armed.at * 1000) % 2147483647)
	for i = 1, C.SpeedLines do
		local frame = Instance.new("Frame")
		frame.Name = "Speed" .. i
		frame.BackgroundColor3 = if C.BackdropArt
			then Color3.new(1, 1, 1)
			else tint:Lerp(Color3.new(1, 1, 1), C.SpeedLineWhiteShare)
		frame.BackgroundTransparency = C.SpeedLineTransparency
		frame.BorderSizePixel = 0
		frame.Active = false
		frame.ZIndex = 2
		local thick = math.max(
			1,
			math.floor(
				innerH * random:NextNumber(C.SpeedLineHeightShare[1], C.SpeedLineHeightShare[2])
			)
		)
		frame.AnchorPoint = Vector2.new(0, 0.5)
		frame.Size = UDim2.fromOffset(0, thick)
		frame.Visible = false
		frame.Parent = inner
		table.insert(lines, {
			frame = frame,
			y = random:NextNumber(0.08, 0.92), -- a share of the frame's height
			length = W * random:NextNumber(C.SpeedLineLengthShare[1], C.SpeedLineLengthShare[2]),
			start = (i - 1) / C.SpeedLines * C.SpeedLineStaggerSeconds,
			speed = W * C.SpeedLineScreensPerSecond * random:NextNumber(0.8, 1.2),
		})
	end

	-- The avatar's window: upright (a ViewportFrame neither rotates nor clips under the tilted
	-- panel), over the panel, the largest box that fits inside the band's picture there.
	local tiltRad = math.rad(C.TiltDegrees)
	local windowW = math.floor(innerH * C.AvatarWindowShare)
	local windowX = (C.AvatarScreenX - 0.5) * W
	local window = Instance.new("Frame")
	window.Name = "AvatarWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.Active = false
	window.ZIndex = 2
	window.Parent = root
	local windowScale = Instance.new("UIScale")
	windowScale.Parent = window
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Avatar"
	viewport.AnchorPoint = Vector2.new(0.5, 0.5)
	viewport.Position = UDim2.fromScale(0.5, 0.5)
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromOffset(
		windowW,
		math.max(1, (innerH - windowW * math.abs(math.sin(tiltRad))) / math.cos(tiltRad))
	)
	viewport.Ambient = rgb(C.Ambient)
	viewport.LightColor = rgb(C.LightColor)
	viewport.LightDirection =
		Vector3.new(C.LightDirection[1], C.LightDirection[2], C.LightDirection[3])
	viewport.Active = false
	viewport.Parent = window
	if not C.BackdropArt then
		-- On the white picture the bust would end in a hard line: its bottom fades out.
		local fadeFrom = 1 - C.AvatarFadeShare
		local ramp = Instance.new("UIGradient")
		ramp.Rotation = 90
		ramp.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(fadeFrom, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		ramp.Parent = viewport
	end
	local viewCamera = Instance.new("Camera")
	viewCamera.FieldOfView = C.FieldOfView
	viewCamera.Parent = viewport
	viewport.CurrentCamera = viewCamera
	local model = takeAvatar(armed.by)
	model.Parent = viewport
	local focus, visibleHeight =
		frameAvatar(model, viewport.Size.X.Offset / math.max(viewport.Size.Y.Offset, 1))
	local distance = visibleHeight / 2 / math.tan(math.rad(C.FieldOfView / 2))

	-- The words: over the top edge at the left of the screen, over the bottom edge at the right,
	-- on a clear twin of the panel laid over the avatar's window.
	local words = Instance.new("Frame")
	words.Name = "Words"
	words.AnchorPoint = panel.AnchorPoint
	words.Rotation = panel.Rotation
	words.BackgroundTransparency = 1
	words.Active = false
	words.ZIndex = 3
	words.Parent = root
	local wordsScale = Instance.new("UIScale")
	wordsScale.Parent = words
	local visibleLeft = (panelW - W) / 2
	local titlePx = math.max(C.TextMinPx, math.floor(panelH * C.TitleHeightShare))
	local title = bigText(words, "Title", Strings.Ults.Cutscene.Title, titlePx)
	title.AnchorPoint = Vector2.new(0, C.EdgeAnchor)
	title.Position = UDim2.fromOffset(visibleLeft + W * C.TitleInsetShare, border / 2)
	title.Size = UDim2.fromOffset(W * C.TitleWidthShare, titlePx)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 5
	local titleScale = Instance.new("UIScale")
	titleScale.Parent = title

	local namePx = math.max(C.TextMinPx, math.floor(panelH * C.NameHeightShare))
	local name = bigText(words, "UltName", Catalog.name(armed.id), namePx)
	name.AnchorPoint = Vector2.new(1, 1 - C.EdgeAnchor)
	-- By scale on Y, so it rides the bottom edge as the band squeezes.
	name.Position = UDim2.new(0, visibleLeft + W * (1 - C.NameInsetShare), 1, -border / 2)
	name.Size = UDim2.fromOffset(W * C.NameWidthShare, namePx)
	name.TextXAlignment = Enum.TextXAlignment.Right
	name.ZIndex = 5
	local nameScale = Instance.new("UIScale")
	nameScale.Parent = name
	-- GUI lane (step 13): the words jolt as they land and the name flares gold.
	task.delay(C.WordsJoltSeconds, function()
		if name.Parent then
			UIAnim.glowBurst(name, HudParts.tone("Gold"))
			UIAnim.shake(title, "Jolt")
		end
	end)

	-- The icon beside the avatar, on the words' twin so it rides the band's tilt and squeeze;
	-- render stamps it in and bursts the glow.
	local iconPx = math.floor(innerH * C.IconShare)
	local iconX = panelW / 2 + windowX + windowW * C.IconFromAvatarShare
	local image = Catalog.icon(armed.id)
	local icon: ImageLabel? = nil
	local iconScale: UIScale? = nil
	local glow: ImageLabel? = nil
	if image ~= "" then
		local stamp = Instance.new("ImageLabel")
		stamp.Name = "Icon"
		stamp.AnchorPoint = Vector2.new(0.5, 0.5)
		stamp.Position = UDim2.new(0, iconX, C.IconYShare, 0)
		stamp.Size = UDim2.fromOffset(iconPx, iconPx)
		stamp.BackgroundTransparency = 1
		stamp.ScaleType = Enum.ScaleType.Fit
		stamp.Image = image
		stamp.Active = false
		stamp.Visible = false
		stamp.ZIndex = 4
		stamp.Parent = words
		local scale = Instance.new("UIScale")
		scale.Parent = stamp
		icon, iconScale = stamp, scale
		if K.Art.SoftGlow ~= "" then
			local burst = Instance.new("ImageLabel")
			burst.Name = "IconGlow"
			burst.AnchorPoint = Vector2.new(0.5, 0.5)
			burst.Position = stamp.Position
			burst.BackgroundTransparency = 1
			burst.ScaleType = Enum.ScaleType.Fit
			burst.Image = K.Art.SoftGlow
			burst.ImageColor3 = tint:Lerp(Color3.new(1, 1, 1), C.IconGlowWhiteShare)
			burst.Active = false
			burst.Visible = false
			burst.ZIndex = 3
			burst.Parent = words
			glow = burst
		end
	end

	return {
		tableId = tableId,
		avatar = model,
		avatarBy = armed.by,
		mine = mine,
		started = os.clock() - elapsed,
		root = root,
		panel = panel,
		panelScale = panelScale,
		inner = inner,
		backdrop = backdrop,
		lines = lines,
		title = title,
		name = name,
		titleScale = titleScale,
		nameScale = nameScale,
		icon = icon,
		iconScale = iconScale,
		glow = glow,
		iconPx = iconPx,
		words = words,
		wordsScale = wordsScale,
		window = window,
		windowScale = windowScale,
		windowW = windowW,
		windowX = windowX,
		viewport = viewport,
		camera = viewCamera,
		focus = focus,
		distance = distance,
		visibleHeight = visibleHeight,
		screenW = W,
		panelW = panelW,
		panelH = panelH,
		border = border,
		innerW = innerW,
		innerH = innerH,
		cropW = cropW,
		eyeShare = eyeShare,
		connection = nil,
	}
end

---------------------------------------------------------------------------------------------
-- Playing it
---------------------------------------------------------------------------------------------

local function stop(play: Play)
	if play.connection then
		play.connection:Disconnect()
		play.connection = nil
	end
	if play.avatar.Parent then
		giveBack(play.avatarBy, play.avatar)
	end
	play.root:Destroy()
	if current == play then
		current = nil
	end
end

-- The total length: the shrink and the snap end it.
local function length(): number
	return math.min(U.CutsceneSeconds, C.ShrinkStartSeconds + C.ShrinkSeconds + C.SnapSeconds)
end

local function render(play: Play, t: number)
	-- The slam: in from the right along the tilt, a little large, overshooting as it lands.
	local slam = UIAnim.backOut(t / C.SlamSeconds)
	local tilt = math.rad(C.TiltDegrees)
	local away = (1 - slam) * play.screenW * C.SlideFromShare
	play.panel.Position =
		UDim2.new(0.5, away * math.cos(tilt), C.CenterYShare, away * math.sin(tilt))
	play.panelScale.Scale = lerp(C.SlamFromScale, 1, clamp01(slam))

	-- The words pop in just after the slam and fade as the panel shrinks.
	local pop = UIAnim.backOut((t - C.TextDelaySeconds) / C.TextPopSeconds)
	local shown = t >= C.TextDelaySeconds
	local shrink = clamp01((t - C.ShrinkStartSeconds) / C.ShrinkSeconds)
	local fade = clamp01(shrink * 2)
	local function word(label: TextLabel, scale: UIScale)
		label.Visible = shown and fade < 1
		scale.Scale = math.max(0.01, lerp(C.TextFromScale, 1, pop))
		HudParts.setTextTransparency(label, fade)
	end
	word(play.title, play.titleScale)
	word(play.name, play.nameScale)

	-- The push-in: the camera eases closer, keeping the avatar where it stands on screen.
	local push = smooth((t - C.PushStartSeconds) / (C.PushEndSeconds - C.PushStartSeconds))
	local distance = play.distance * lerp(1, C.PushInScale, push)
	play.camera.CFrame = CFrame.lookAt(play.focus - Vector3.zAxis * distance, play.focus)

	-- The backdrop drifts and slowly closes in on the calm eye.
	local backdrop = play.backdrop
	if backdrop then
		local art = C.ArtSizePx
		local cropW = play.cropW * (1 - C.BackdropZoomShare * push)
		local cropH = math.min(
			cropW * play.innerH / math.max(play.innerW, 1),
			C.StripRows[2] - C.StripRows[1]
		)
		local x = C.EyePx[1] - play.eyeShare * cropW + C.BackdropDriftPxPerSecond * t
		local y = C.EyePx[2] - cropH / 2
		backdrop.ImageRectSize = Vector2.new(cropW, cropH)
		backdrop.ImageRectOffset =
			Vector2.new(math.clamp(x, 0, art - cropW), math.clamp(y, 0, art - cropH))
	end

	-- Speed lines, clipped to the frame by hand.
	for _, line in play.lines do
		local run = t - line.start
		local x = play.innerW - run * line.speed
		local left, right = math.max(x, 0), math.min(x + line.length, play.innerW)
		local visible = run >= 0 and right - left > 1 and play.innerH > 4
		line.frame.Visible = visible
		if visible then
			line.frame.Position = UDim2.new(0, left, line.y, 0)
			line.frame.Size = UDim2.fromOffset(right - left, line.frame.Size.Y.Offset)
		end
	end

	-- The exit: the band squeezes to a thin line, then the line snaps shut to nothing.
	local height = lerp(play.panelH, C.LineHeightPx, quadIn(shrink))
	local snap = clamp01((t - C.ShrinkStartSeconds - C.ShrinkSeconds) / C.SnapSeconds)
	local width = play.panelW * (1 - quadIn(snap))
	play.panel.Size = UDim2.fromOffset(width, height)
	play.inner.Visible = height > 2 * play.border + 2
	play.words.Position, play.words.Size = play.panel.Position, play.panel.Size
	play.wordsScale.Scale = play.panelScale.Scale

	-- The avatar's window rides the band: its centre on the band's middle line, as tall as fits
	-- inside the picture's tilted edges, squeezing and snapping shut with it.
	local scale = play.panelScale.Scale
	local innerNow = height - 2 * play.border
	local windowW = math.min(play.windowW, math.max(width - 2 * play.border, 0))
	local windowH = (innerNow - windowW * math.abs(math.sin(tilt))) / math.cos(tilt)
	local along = play.windowX * scale * width / play.panelW
	play.window.Position = play.panel.Position
		+ UDim2.fromOffset(along * math.cos(tilt), along * math.sin(tilt))
	play.window.Size = UDim2.fromOffset(windowW, math.max(windowH, 0))
	play.windowScale.Scale = scale
	play.window.Visible = play.inner.Visible and windowH > 1 and windowW > 1

	-- The icon stamps in as the slam lands (large, overshooting to rest), with a burst of the
	-- rarity colour behind it, then squeezes and fades with the words as the band shrinks.
	local icon, iconScale = play.icon, play.iconScale
	if icon and iconScale then
		local k = (t - C.IconDelaySeconds) / C.IconPopSeconds
		local squeeze = height / play.panelH
		icon.Visible = k >= 0 and fade < 1 and play.inner.Visible
		iconScale.Scale = math.max(0.01, lerp(C.IconFromScale, 1, UIAnim.backOut(k)) * squeeze)
		icon.ImageTransparency = fade
	end
	local glow = play.glow
	if glow then
		local g = (t - C.IconDelaySeconds) / C.IconGlowSeconds
		glow.Visible = g >= 0 and g < 1 and play.inner.Visible
		local size = play.iconPx
			* lerp(C.IconGlowFromScale, C.IconGlowToScale, UIAnim.quadOut(g))
			* height
			/ play.panelH
		glow.Size = UDim2.fromOffset(size, size)
		glow.ImageTransparency = lerp(C.IconGlowTransparency, 1, clamp01(g))
	end
end

-- Studio look checks only: the panel held still at this many seconds in (the player's
-- UltCutscenePreview attribute, "<ultId>@<seconds>"), so a screen capture can catch it.
local holdAt: number? = nil

local function begin(tableId: number, mine: boolean, armed: Armed, elapsed: number)
	local previous = current
	if previous then
		-- One at a time: your own table's ult beats one at a table you are only watching.
		if previous.mine and not mine then
			return
		end
		stop(previous)
	end
	preload()
	local play = build(tableId, mine, armed, math.max(elapsed, 0))
	current = play
	local sound = ensureSound()
	if sound then
		-- Play() resumes from the last TimePosition written (STUDIO_NOTES "Audio"), so it is
		-- set every time: past the clip's silent lead, plus however late this client is.
		sound:Stop()
		sound.TimePosition = U.Audio.Activate.StartOffset + math.max(elapsed, 0)
		sound:Play()
	end
	local total = length()
	render(play, os.clock() - play.started)
	play.connection = RunService.RenderStepped:Connect(function()
		local t = holdAt or os.clock() - play.started
		if t >= total and holdAt == nil then
			stop(play)
			return
		end
		render(play, t)
	end)
end

---------------------------------------------------------------------------------------------
-- Watching the tables
---------------------------------------------------------------------------------------------

-- In the match: seated at the table, or standing close enough to watch it (ScreenFx.involved,
-- the one rule the table-wide screen effects use too).
local function involved(self: UltCutscene, snapshot: any): boolean
	return ScreenFx.involved(self.hub, snapshot.id, snapshot)
end

local function armedOf(snapshot: any): Armed?
	local ults = snapshot and snapshot.ults
	local armed = if type(ults) == "table" then ults.armed else nil
	if
		type(armed) ~= "table"
		or type(armed.at) ~= "number"
		or type(armed.id) ~= "string"
		or type(armed.by) ~= "number"
	then
		return nil
	end
	return armed :: Armed
end

local function fireArming(self: UltCutscene, tableId: number, armed: Armed)
	-- Still the same activation (a new game or rack in between would have replaced it).
	local now = armedOf(self.hub.snapshots[tableId])
	if now == nil or now.at ~= armed.at then
		return
	end
	for _, listener in self.armingListeners do
		task.spawn(listener, tableId, now)
	end
end

local function onSnapshot(self: UltCutscene, snapshot: any)
	if type(snapshot) ~= "table" or type(snapshot.id) ~= "number" then
		return
	end
	-- The seated players' copies, made ahead while this player is in that match.
	if type(snapshot.seats) == "table" and involved(self, snapshot) then
		for _, seat in snapshot.seats do
			if type(seat) == "table" and type(seat.userId) == "number" then
				warm(seat.userId)
			end
		end
	end
	local armed = armedOf(snapshot)
	if armed == nil then
		return
	end
	local last = self.seen[snapshot.id]
	if last and armed.at <= last then
		return
	end
	self.seen[snapshot.id] = armed.at
	local now = workspace:GetServerTimeNow()
	local elapsed = now - armed.at
	local readyAt = if type(armed.readyAt) == "number"
		then armed.readyAt
		else armed.at + U.CutsceneSeconds + U.ArmDelaySeconds
	if now < readyAt + C.ArmGraceSeconds then
		task.delay(math.max(readyAt - now, 0), fireArming, self, snapshot.id, armed)
	end
	-- Look Over There! has no panel (and so no activation sound): nobody may be warned.
	local row = Catalog.get(armed.id)
	if elapsed < U.CutsceneSeconds and involved(self, snapshot) and not (row and row.Sneak) then
		begin(snapshot.id, self.hub.mySeat == snapshot.id, armed, elapsed)
	end
end

--- Start watching `hub` (src/client/Hub.luau) for activations. Returns the cutscene; its
--- onArming listeners run at each activation's readyAt.
function UltCutscene.start(hub: any): UltCutscene
	local self = setmetatable({
		hub = hub,
		seen = {},
		armingListeners = {},
	}, UltCutscene)
	preload()
	-- Snapshots already here count as seen (and a fresh one still plays).
	for _, snapshot in hub.snapshots do
		onSnapshot(self, snapshot)
	end
	hub:onSnapshot(function(snapshot)
		onSnapshot(self, snapshot)
	end)
	if RunService:IsStudio() then
		-- Look checks: set the player's UltCutscenePreview attribute to "<ultId>@<seconds>" to
		-- play that ult's panel held at that moment ("<ultId>" plays it through); "" ends it.
		player:GetAttributeChangedSignal("UltCutscenePreview"):Connect(function()
			local value = player:GetAttribute("UltCutscenePreview")
			local id, at = nil, nil
			if type(value) == "string" then
				id, at = value:match("^(%w+)@?([%d%.]*)$")
			end
			if id then
				holdAt = tonumber(at)
				UltCutscene.preview(id)
			else
				holdAt = nil
				if current then
					stop(current)
				end
			end
		end)
	end
	return self
end

--- Call `listener(tableId, armed)` at the arming moment (armed.readyAt) of every fresh
--- activation at any table, whether or not this player saw the panel.
function UltCutscene.onArming(self: UltCutscene, listener: (number, Armed) -> ())
	table.insert(self.armingListeners, listener)
end

--- True while a panel is on screen.
function UltCutscene.isPlaying(_self: UltCutscene): boolean
	return current ~= nil
end

--- Play the panel now for `ultId` and `userId` (default: the local player), with no table: a
--- preview for Studio checks.
function UltCutscene.preview(ultId: string?, userId: number?)
	begin(0, true, {
		by = userId or player.UserId,
		id = ultId or U.Default,
		stage = "Arming",
		at = workspace:GetServerTimeNow(),
		readyAt = workspace:GetServerTimeNow() + U.CutsceneSeconds + U.ArmDelaySeconds,
		seq = 0,
		practice = true,
	}, 0)
end

return UltCutscene
