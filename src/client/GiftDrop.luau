--!strict
-- GiftDrop: the Gift block falling from the sky (designer, 2026-10-07; the Roblox menu,
-- 2026-10-10; the server decides, GiftDropService).
--
-- The player opening Roblox's own menu (Escape, the menu button, a controller's Start: about
-- to leave) is told to the server ({ menu = true }): the first time after the tutorial earns
-- the Gift and drops it at once, behind the menu, a reason to stay. A Gift not picked up falls
-- again on the next visit.
--
-- When the server sends { at = CFrame } (and none of our menus, popups or reels is up:
-- setBusy): black letterbox bars slide in with "Wait... what is this?" big at the top, just
-- under the top bar (like the tutorial's line), the rest of the HUD steps aside and the player
-- stands still. The camera, behind the player, looks up at the sky:
-- the Gift streaks down on a slant with a glowing gold trail, sparks and a glint, spinning, and
-- crashes at `at` with a white flash, a camera shake, a shockwave ring and bursts of dust and
-- gold confetti, bouncing as it lands. The line gives way to the title in the bottom bar; the camera holds
-- on the block, then blends back, the bars slide away and everything comes back. The block
-- (only on this screen) idles there with a Pick up prompt (hold E, the gamepad's X, or touch);
-- the server checks and adds it to the hotbar, and it shrinks away in a puff. Tuning in
-- Config.LuckyBlocks.GiftDrop.
--
-- The Sky Lucky Block (economy v6, designer 2026-10-10: "reuse the Gift cutscene") falls the
-- same way: its server (SkyDropService) sends { at, kind = "Sky" } on the SkyDrop remote, and
-- its pick up answers there. Each kind has its own block on the floor (a Gift and a Sky block
-- can both wait there), its own words (Strings.LuckyBlocks.Drops) and its own remote.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local HudParts = require(script.Parent.HudParts)
local Letterbox = require(script.Parent.Letterbox)
local UIAnim = require(script.Parent.UIAnim)

local L = Config.LuckyBlocks
local G = L.GiftDrop
local W = Strings.LuckyBlocks
local RENDER = "GiftDropCamera"
-- The remote each falling kind answers on (its server: GiftDropService, SkyDropService).
local REMOTES: { [string]: string } = { Gift = "GiftDrop", Sky = "SkyDrop" }

local GiftDrop = {}

type Drop = {
	kind: string,
	model: Model,
	part: BasePart,
	scale: number,
	at: CFrame,
	prompt: ProximityPrompt?,
	idle: AnimationTrack?,
}

local current: { [string]: Drop } = {} -- the block on the floor, by kind
local playing = false
local started = false
local waiting: { [string]: boolean } = {} -- a drop of that kind waits for the screen to be free
local busy: () -> boolean = function()
	return false
end
local shake = Random.new()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function smoother(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * t * (t * (t * 6 - 15) + 10)
end

---------------------------------------------------------------------------------------------
-- The block
---------------------------------------------------------------------------------------------

-- The Gift's template, scaled so its block is SizeStuds, made the way the floor's blocks are
-- (LuckyBlockService.makeModel): anchored, touching nothing, its pulsing glow off (its timer
-- is still running), its other particles and light on.
local function makeBlock(kind: string): Model?
	local row = L.Kinds[kind]
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local source = folder and folder:FindFirstChild(row.Model)
	if not (source and source:IsA("Model")) then
		warn("[8ball] GiftDrop: no model " .. tostring(row.Model))
		return nil
	end
	local model = source:Clone()
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		local edge = G.SizeStuds * ((row :: any).SizeMultiplier or 1)
		model:ScaleTo(model:GetScale() * edge / longest)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			if d:FindFirstChildOfClass("SurfaceAppearance") then
				d.Color = Color3.new(1, 1, 1)
			end
		elseif d:IsA("SurfaceAppearance") then
			d.EmissiveStrength = (row :: any).EmissiveStrength or L.Look.EmissiveStrength
		elseif d:IsA("Light") then
			d.Brightness = L.Look.LightBrightness
			local ranged: any = d
			ranged.Range = L.Look.LightRangeStuds
		elseif d:IsA("ParticleEmitter") then
			d.LightInfluence = L.Look.ParticleLightInfluence
			if d.Texture == L.Look.PulseTexture then
				d.Enabled = false
			end
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model.Name = "GiftDrop"
	return model
end

local function playIdle(drop: Drop)
	local row = L.Kinds[drop.kind]
	local id = (row :: any).Idle or L.Anim.BlockIdle
	local controller = drop.model:FindFirstChildOfClass("AnimationController")
	local animator = controller and controller:FindFirstChildOfClass("Animator")
	if animator == nil or id == "" then
		return
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	local ok, track = pcall(function()
		return (animator :: Animator):LoadAnimation(animation)
	end)
	if ok then
		track.Looped = true
		track:Play(0.3)
		drop.idle = track
	end
end

local function clear(kind: string)
	local drop = current[kind]
	current[kind] = nil
	if drop then
		drop.model:Destroy()
	end
end

---------------------------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------------------------

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.LightEmission = 1
	for key, value in props do
		(e :: any)[key] = value
	end
	e.Parent = parent
	return e
end

local function trailColors(): ColorSequence
	local c = G.TrailColors
	return ColorSequence.new(rgb(c[1]), rgb(c[2]))
end

-- The comet that carries the trail, sparks and glint down the sky (it does not spin, so the
-- trail stays flat). Returns it and its emitters.
local function makeComet(side: Vector3): (Part, { ParticleEmitter })
	local comet = Instance.new("Part")
	comet.Name = "GiftComet"
	comet.Anchored = true
	comet.CanCollide = false
	comet.CanTouch = false
	comet.CanQuery = false
	comet.Transparency = 1
	comet.Size = Vector3.one
	local a0 = Instance.new("Attachment")
	a0.Position = side * (G.TrailWidthStuds / 2)
	a0.Parent = comet
	local a1 = Instance.new("Attachment")
	a1.Position = -side * (G.TrailWidthStuds / 2)
	a1.Parent = comet
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = G.TrailSeconds
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = trailColors()
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	trail.Parent = comet
	local centre = Instance.new("Attachment")
	centre.Parent = comet
	local gold = rgb(G.TrailColors[1])
	local sparks = emitter(centre, {
		Texture = G.Sprites.Twinkle,
		Rate = 70,
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Color = ColorSequence.new(Color3.new(1, 1, 1), gold),
		Rotation = NumberRange.new(0, 360),
	})
	local embers = emitter(centre, {
		Texture = G.Sprites.Ember,
		Rate = 40,
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(0, 2),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 3),
			NumberSequenceKeypoint.new(1, 0.5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(gold),
	})
	local glint = Instance.new("BillboardGui")
	glint.Name = "Glint"
	glint.Size = UDim2.fromScale(G.GlowStuds, G.GlowStuds)
	glint.LightInfluence = 0
	glint.Adornee = comet
	local glow = Instance.new("ImageLabel")
	glow.BackgroundTransparency = 1
	glow.Size = UDim2.fromScale(1, 1)
	glow.Image = Config.UI.Kit.Art.SoftGlow
	glow.ImageColor3 = gold
	glow.Parent = glint
	glint.Parent = comet
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Brightness = 4
	light.Range = 18
	light.Parent = comet
	return comet, { sparks, embers }
end

-- The crash: a shockwave ring, dust and confetti bursts and a flash of light, all at `at`.
local function crash(at: CFrame)
	local ring = Instance.new("Part")
	ring.Name = "GiftShockwave"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanTouch = false
	ring.CanQuery = false
	ring.Material = Enum.Material.Neon
	ring.Color = rgb(G.TrailColors[1])
	ring.Transparency = 0.2
	ring.Size = Vector3.new(0.2, 1, 1)
	ring.CFrame = CFrame.new(at.Position + Vector3.new(0, 0.15, 0))
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	TweenService:Create(
		ring,
		TweenInfo.new(G.RingSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, G.RingStuds, G.RingStuds), Transparency = 1 }
	):Play()
	task.delay(G.RingSeconds, function()
		ring:Destroy()
	end)

	local burst = Instance.new("Part")
	burst.Name = "GiftCrash"
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanTouch = false
	burst.CanQuery = false
	burst.Transparency = 1
	burst.Size = Vector3.one
	burst.CFrame = CFrame.new(at.Position + Vector3.new(0, 0.5, 0))
	local point = Instance.new("Attachment")
	point.Parent = burst
	local dust = emitter(point, {
		Texture = G.Sprites.Puff,
		Enabled = false,
		LightEmission = 0.2,
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(90, 8),
		Acceleration = Vector3.new(0, 4, 0),
		Drag = 4,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2),
			NumberSequenceKeypoint.new(1, 5),
		}),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Color = ColorSequence.new(Color3.fromRGB(255, 246, 225)),
		Rotation = NumberRange.new(0, 360),
	})
	local confetti = emitter(point, {
		Texture = G.Sprites.Confetti,
		Enabled = false,
		LightEmission = 0.4,
		Lifetime = NumberRange.new(1.2, 2),
		Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, -40, 0),
		Drag = 1.5,
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(0.7),
		RotSpeed = NumberRange.new(-300, 300),
		Rotation = NumberRange.new(0, 360),
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 214, 92)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 180, 60)),
		}),
	})
	local sparkle = emitter(point, {
		Texture = G.Sprites.Twinkle,
		Enabled = false,
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(10, 22),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.4),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Color = ColorSequence.new(rgb(G.TrailColors[1])),
	})
	local light = Instance.new("PointLight")
	light.Color = rgb(G.TrailColors[1])
	light.Brightness = 8
	light.Range = 24
	light.Parent = burst
	burst.Parent = workspace
	dust:Emit(G.DustBurst)
	confetti:Emit(G.SparkleBurst)
	sparkle:Emit(math.floor(G.SparkleBurst / 2))
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	task.delay(3, function()
		burst:Destroy()
	end)
end

---------------------------------------------------------------------------------------------
-- The screen: bars, title, flash, the HUD stepping aside
---------------------------------------------------------------------------------------------

type Screen = {
	gui: ScreenGui,
	bars: { Frame },
	flash: Frame,
	wonder: TextLabel,
	title: TextLabel,
	sub: TextLabel,
	hidden: { ScreenGui },
}

local function makeScreen(kind: string): Screen?
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	-- Everything else of ours steps aside (it comes back after).
	local hidden: { ScreenGui } = {}
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("ScreenGui") and gui.Enabled then
			gui.Enabled = false
			table.insert(hidden, gui)
		end
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "GiftDropScene"
	gui.ResetOnSpawn = false
	Letterbox.screen(gui)
	gui.DisplayOrder = Config.Cutscenes.DisplayOrder
	local bars = {}
	for i, edge in { 0, 1 } do
		local bar = Instance.new("Frame")
		bar.Name = "Bar"
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.AnchorPoint = Vector2.new(0, edge)
		bar.Position = UDim2.fromScale(0, edge)
		bar.Size = UDim2.fromScale(1, 0)
		bar.ZIndex = 2
		bar.Parent = gui
		bars[i] = bar
	end
	local flash = Instance.new("Frame")
	flash.Name = "Flash"
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 1
	flash.Parent = gui
	-- While it falls, a line in the bottom bar (designer, 2026-10-10); the title replaces it at
	-- the crash.
	-- Big, at the top just under the top bar, like the tutorial's line (designer, 2026-10-10).
	local camera = workspace.CurrentCamera
	local phone = camera ~= nil and camera.ViewportSize.Y < Config.Multiplayer.Style.ShortHeight
	local wonderPx = if phone then G.WonderPhoneTextPx else G.WonderTextPx
	local wonder = HudParts.text(gui, "Wonder", wonderPx, W.GiftWonder)
	wonder.AnchorPoint = Vector2.new(0.5, 0)
	wonder.Position = UDim2.new(0.5, 0, 0, Letterbox.px(G.BarsShare) + G.WonderGapPx)
	wonder.Size = UDim2.new(0.9, 0, 0, math.ceil(wonderPx * 1.3))
	wonder.TextTransparency = 1
	wonder.ZIndex = 3
	-- The title sits in the bottom bar.
	local words = (W.Drops :: any)[kind] or W.Drops.Gift
	local title = HudParts.text(bars[2], "Title", 30, words.Title)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.38)
	title.Size = UDim2.new(1, -32, 0.4, 0)
	title.TextScaled = true
	title.TextColor3 = rgb(G.TrailColors[1])
	title.TextTransparency = 1
	title.ZIndex = 3
	local sub = HudParts.text(bars[2], "Sub", 20, words.Sub)
	sub.AnchorPoint = Vector2.new(0.5, 0.5)
	sub.Position = UDim2.fromScale(0.5, 0.75)
	sub.Size = UDim2.new(1, -32, 0.25, 0)
	sub.TextScaled = true
	sub.TextTransparency = 1
	sub.ZIndex = 3
	for _, label in { wonder, title, sub } do
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Transparency = 1
		end
	end
	gui.Parent = playerGui
	return {
		gui = gui,
		bars = bars,
		flash = flash,
		wonder = wonder,
		title = title,
		sub = sub,
		hidden = hidden,
	}
end

-- Fades bar words in or out (their outlines with them).
local function fade(labels: { TextLabel }, on: boolean)
	local info = TweenInfo.new(0.35)
	for _, label in labels do
		TweenService:Create(label, info, { TextTransparency = if on then 0 else 1 }):Play()
		local stroke = label:FindFirstChildOfClass("UIStroke")
		if stroke then
			TweenService:Create(stroke, info, { Transparency = if on then 0 else 1 }):Play()
		end
	end
end

-- The title and the line under it.
local function showText(screen: Screen, on: boolean)
	fade({ screen.title, screen.sub }, on)
end

local function barsTo(screen: Screen, share: number)
	for _, bar in screen.bars do
		TweenService:Create(
			bar,
			TweenInfo.new(G.BarsSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = if share > 0 then Letterbox.size(share) else UDim2.fromScale(1, 0) }
		):Play()
	end
end

-- The player stands still through the scene (like the pull cutscenes).
local function holdCharacter(): { [string]: any }?
	local player = Players.LocalPlayer
	local body = player and player.Character
	local humanoid = body and body:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end
	local held = {
		humanoid = humanoid,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		AutoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	humanoid:Move(Vector3.zero)
	return held
end

local function releaseCharacter(held: { [string]: any }?)
	local humanoid = held and held.humanoid
	if not humanoid or not humanoid.Parent then
		return
	end
	for key, value in held :: { [string]: any } do
		if key ~= "humanoid" then
			humanoid[key] = value
		end
	end
end

---------------------------------------------------------------------------------------------
-- The pick up
---------------------------------------------------------------------------------------------

local function addPrompt(drop: Drop)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GiftPickUp"
	prompt.ActionText = W.GiftPickUp
	prompt.ObjectText = W.Names[drop.kind] or ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = G.PromptHoldSeconds
	prompt.MaxActivationDistance = G.PickupStuds - 2
	prompt.RequiresLineOfSight = false
	prompt.ClickablePrompt = true
	prompt.Triggered:Connect(function()
		prompt.Enabled = false
		Net.get(REMOTES[drop.kind] or "GiftDrop"):FireServer()
	end)
	local anchor = Instance.new("Attachment")
	anchor.Name = "GiftPickUpAnchor"
	anchor.Position =
		drop.part.CFrame:PointToObjectSpace(drop.at.Position + Vector3.new(0, G.SizeStuds * 0.8, 0))
	anchor.Parent = drop.part
	prompt.Parent = anchor
	drop.prompt = prompt
end

-- The server's answer: picked up (it shrinks away in a puff), or not (the prompt again).
local function answered(kind: string, payload: { [string]: any })
	local drop = current[kind]
	if drop == nil then
		return
	end
	if payload.picked ~= true then
		if drop.prompt then
			drop.prompt.Enabled = true
		end
		return
	end
	current[kind] = nil
	if drop.prompt then
		drop.prompt:Destroy()
	end
	local puff = Instance.new("Part")
	puff.Anchored = true
	puff.CanCollide = false
	puff.CanQuery = false
	puff.CanTouch = false
	puff.Transparency = 1
	puff.Size = Vector3.one
	puff.CFrame = CFrame.new(drop.at.Position + Vector3.new(0, G.SizeStuds / 2, 0))
	local point = Instance.new("Attachment")
	point.Parent = puff
	local sparkle = emitter(point, {
		Texture = G.Sprites.Twinkle,
		Enabled = false,
		Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(6, 14),
		SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.2),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Color = ColorSequence.new(rgb(G.TrailColors[1])),
	})
	puff.Parent = workspace
	sparkle:Emit(30)
	task.delay(1.5, function()
		puff:Destroy()
	end)
	local model = drop.model
	local scale = drop.scale
	local start = os.clock()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local u = math.clamp((os.clock() - start) / G.PickupSeconds, 0, 1)
		if u >= 1 or model.Parent == nil then
			if connection then
				connection:Disconnect()
			end
			model:Destroy()
			return
		end
		model:ScaleTo(scale * math.max(0.02, 1 - u * u))
		model:PivotTo(drop.at * CFrame.new(0, u * G.SizeStuds, 0))
	end)
end

---------------------------------------------------------------------------------------------
-- The scene
---------------------------------------------------------------------------------------------

local function play(at: CFrame, kind: string)
	if playing then
		return
	end
	clear(kind)
	local model = makeBlock(kind)
	local player = Players.LocalPlayer
	local root = player and player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if model == nil or not (root and root:IsA("BasePart")) then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if part == nil then
		model:Destroy()
		return
	end
	playing = true
	local drop: Drop = {
		kind = kind,
		model = model,
		part = part :: BasePart,
		scale = model:GetScale(),
		at = at,
		prompt = nil,
		idle = nil,
	}
	current[kind] = drop
	local screen = makeScreen(kind)
	local held = holdCharacter()
	local cam = workspace.CurrentCamera
	local ownType = cam.CameraType
	local ownCFrame = cam.CFrame

	-- The path: from high over to one side, down onto the spot (speeding up), spinning.
	local half = G.SizeStuds / 2
	local landCentre = at.Position + Vector3.new(0, half, 0)
	local side = at.RightVector
	local startCentre = landCentre + side * G.DropSideStuds + Vector3.new(0, G.DropHeightStuds, 0)
	local comet, emitters = makeComet(side)
	comet.CFrame = CFrame.new(startCentre)
	comet.Parent = workspace
	model:PivotTo(CFrame.new(startCentre) * at.Rotation * CFrame.new(0, -half, 0))
	model.Parent = workspace

	-- The camera: behind the player, a little up, looking at the block.
	local flat = (at.Position - root.Position) * Vector3.new(1, 0, 1)
	local toward = if flat.Magnitude > 1e-3 then flat.Unit else -at.LookVector
	local head = root.Position + Vector3.new(0, 2, 0)
	local wanted = root.Position
		- toward * G.CameraBackStuds
		- side * G.CameraSideStuds
		+ Vector3.new(0, G.CameraUpStuds, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Model, model, comet }
	local blocked = workspace:Raycast(head, wanted - head, params)
	local camAt = if blocked then blocked.Position + (head - wanted).Unit * 0.5 else wanted
	local lookAt = startCentre
	cam.CameraType = Enum.CameraType.Scriptable
	if screen then
		barsTo(screen, G.BarsShare)
		fade({ screen.wonder }, true)
		UIAnim.popIn(screen.wonder)
	end

	local begin = os.clock()
	local landed = false
	local crashAt = math.huge
	local spin = 2 * math.pi * G.SpinTurns
	local axis = side:Cross(Vector3.yAxis)
	RunService:BindToRenderStep(RENDER, Enum.RenderPriority.Camera.Value + 5, function(dt: number)
		local t = os.clock() - begin
		local u = math.clamp(t / G.FallSeconds, 0, 1)
		local centre = startCentre:Lerp(landCentre, u * u)
		if not landed then
			comet.CFrame = CFrame.new(centre)
			model:PivotTo(
				CFrame.new(centre)
					* CFrame.fromAxisAngle(axis, spin * (1 - u))
					* at.Rotation
					* CFrame.new(0, -half, 0)
			)
			if u >= 1 then
				landed = true
				crashAt = os.clock()
				model:PivotTo(at)
				for _, e in emitters do
					e.Enabled = false
				end
				crash(at)
				if screen then
					screen.flash.BackgroundTransparency = 0.15
					TweenService:Create(
						screen.flash,
						TweenInfo.new(G.FlashSeconds),
						{ BackgroundTransparency = 1 }
					):Play()
					fade({ screen.wonder }, false)
					showText(screen, true)
				end
			end
		else
			-- The bounce: a quick squash up and settle.
			local since = os.clock() - crashAt
			local bounce = math.max(0, 1 - since / 0.4)
			model:ScaleTo(drop.scale * (1 + 0.12 * bounce * math.sin(since * 30)))
			model:PivotTo(at)
		end
		-- Follow the block (eased), then shake at the crash.
		local target = if landed then landCentre else centre
		lookAt = lookAt:Lerp(target, math.clamp(dt * 8, 0, 1))
		local view = CFrame.lookAt(camAt, lookAt)
		local since = os.clock() - crashAt
		if since >= 0 and since < G.ShakeSeconds then
			local k = G.ShakeStuds * (1 - since / G.ShakeSeconds)
			view *= CFrame.new(shake:NextNumber(-k, k), shake:NextNumber(-k, k), 0)
		end
		cam.CFrame = view
	end)

	task.spawn(function()
		task.wait(G.FallSeconds + G.HoldSeconds)
		RunService:UnbindFromRenderStep(RENDER)
		comet:Destroy()
		model:ScaleTo(drop.scale)
		model:PivotTo(at)
		playIdle(drop)
		-- Back to the player's own view.
		local from = cam.CFrame
		local start = os.clock()
		local barsOut = false
		if screen then
			showText(screen, false)
		end
		while true do
			if screen and not barsOut and os.clock() - start >= 0.3 then
				barsOut = true -- the title fades first, then the bars go
				barsTo(screen, 0)
			end
			local u = (os.clock() - start) / G.BackSeconds
			if u >= 1 then
				break
			end
			cam.CFrame = from:Lerp(ownCFrame, smoother(u))
			RunService.RenderStepped:Wait()
		end
		cam.CFrame = ownCFrame
		cam.CameraType = if ownType == Enum.CameraType.Scriptable
			then Enum.CameraType.Custom
			else ownType
		releaseCharacter(held)
		if screen then
			for _, gui in screen.hidden do
				if gui.Parent then
					gui.Enabled = true
				end
			end
			screen.gui:Destroy()
		end
		playing = false
		if current[kind] == drop then
			addPrompt(drop)
		end
	end)
end

-- Plays the drop once nothing else holds the screen (a menu, a popup, a reel: setBusy) and no
-- other drop is falling; one waiting drop per kind.
local function playWhenFree(at: CFrame, kind: string)
	if waiting[kind] then
		return
	end
	waiting[kind] = true
	task.spawn(function()
		while busy() or playing do
			task.wait(0.25)
		end
		waiting[kind] = nil
		play(at, kind)
	end)
end

--- What keeps the drop waiting (Main: a menu, a popup, the result screen or a reel is up).
function GiftDrop.setBusy(fn: () -> boolean)
	busy = fn
end

function GiftDrop.start()
	if started then
		return
	end
	started = true
	for kind, remote in REMOTES do
		Net.get(remote).OnClientEvent:Connect(function(payload: any)
			if type(payload) ~= "table" then
				return
			end
			if typeof(payload.at) == "CFrame" then
				playWhenFree(payload.at, kind)
			elseif payload.picked ~= nil then
				answered(kind, payload)
			end
		end)
	end
	-- Roblox's menu opened (Escape, the menu button, a controller's Start): the player may be
	-- leaving. The server decides whether this earns the Gift (the first time after the
	-- tutorial). Never more often than it listens.
	local lastMenu = -math.huge
	GuiService.MenuOpened:Connect(function()
		local now = os.clock()
		if now - lastMenu < G.MenuCooldownSeconds then
			return
		end
		lastMenu = now
		Net.get("GiftDrop"):FireServer({ menu = true })
	end)
end

return GiftDrop
