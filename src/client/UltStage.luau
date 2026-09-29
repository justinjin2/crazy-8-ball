--!strict
-- UltStage: the spin screen's hidden stage (docs/prompts/ULTIMATES_PROMPT.md section 9.2).
-- ViewportFrames draw no particles, so the avatar and its aura stand in a real room built at
-- runtime far above and away from the map (Config.UI.UltScreen.Stage.Origin): a dark room with
-- a soft key light and a cool fill, a slowly swirling dark backdrop (the cutscene's swirl art,
-- two layers scrolling opposite ways and a faint third in the aura's colour) and a soft glow on
-- the floor. It exists only while the screen is open (parented to nil otherwise), so nothing on
-- the map ever sees it. Everything is client-side, anchored and non-colliding.
--
-- Opening cuts the camera there (Scriptable, driven every frame, with a slow drift) and closing
-- puts it back exactly as it was (its type, subject, field of view, CFrame and focus), unless
-- the match camera has taken it meanwhile (Camera.isLocked), which then keeps it.
--
-- The avatar is a client clone of the player's character (Archivable set for the clone and put
-- back; scripts, sounds and name tags removed; the root anchored, the rest held by its joints)
-- facing the camera and playing the character's own idle (from its Animate script, else
-- Roblox's default R15 or R6 idle). The aura is UltAura.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Camera = require(script.Parent.Camera)
local UltAura = require(script.Parent.UltAura)

local ST = Config.UI.UltScreen.Stage
local K = Config.UI.Kit
local RARITY: { [string]: { number } } = K.Rarity :: any
local TIERS: { [string]: any } = Config.UI.UltScreen.Aura.Tiers :: any
local RENDER_NAME = "8ballUltStage"

-- Things a clone must not keep: a script would run, a sound would play, a tag would float.
local STRIP: { [string]: boolean } = {
	Sound = true,
	BillboardGui = true,
	ForceField = true,
	ProximityPrompt = true,
	ClickDetector = true,
}

local UltStage = {}
UltStage.__index = UltStage

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function origin(): Vector3
	local o: { number } = ST.Origin
	return Vector3.new(o[1], o[2], o[3])
end

-- An anchored, non-colliding room part.
local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	colour: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = colour
	part.Size = size
	part.CFrame = cframe
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function swirl(
	parent: Instance,
	name: string,
	tile: number,
	colour: Color3,
	fade: number
): Texture
	local texture = Instance.new("Texture")
	texture.Name = name
	texture.Texture = K.Art.UltBackdrop
	texture.Face = Enum.NormalId.Back -- the wall's side facing the camera (+Z)
	texture.StudsPerTileU = tile
	texture.StudsPerTileV = tile
	texture.Color3 = colour
	texture.Transparency = fade
	texture.Parent = parent
	return texture
end

--- The stage, not built until first opened.
function UltStage.new(): any
	local self: any = setmetatable({}, UltStage)
	self.opened = false
	self.model = nil :: Model?
	self.avatar = nil :: Model?
	self.root = nil :: BasePart?
	self.aura = nil :: any
	self.track = nil :: AnimationTrack?
	self.saved = nil :: any
	self.rarity = "Common"
	self.clock = 0
	self.focus = Vector3.zero
	self.distance = 12
	self.bounceTween = nil :: Tween?
	return self
end

-- The room, built once and kept (parented to nil while closed).
function UltStage.build(self: any): Model
	local existing = self.model
	if existing then
		return existing
	end
	local o = origin()
	local model = Instance.new("Model")
	model.Name = "UltStage"
	local w, d, h = ST.RoomWidth, ST.RoomDepth, ST.RoomHeight
	local wall = rgb(ST.WallColor)
	local floor = block(
		model,
		"Floor",
		Vector3.new(w, 1, d),
		CFrame.new(o - Vector3.new(0, 0.5, 0)),
		rgb(ST.FloorColor)
	)
	floor.Reflectance = ST.FloorReflectance
	block(model, "Ceiling", Vector3.new(w, 1, d), CFrame.new(o + Vector3.new(0, h + 0.5, 0)), wall)
	block(
		model,
		"Left",
		Vector3.new(1, h, d),
		CFrame.new(o + Vector3.new(-w / 2 - 0.5, h / 2, 0)),
		wall
	)
	block(
		model,
		"Right",
		Vector3.new(1, h, d),
		CFrame.new(o + Vector3.new(w / 2 + 0.5, h / 2, 0)),
		wall
	)
	block(
		model,
		"Front",
		Vector3.new(w, h, 1),
		CFrame.new(o + Vector3.new(0, h / 2, d / 2 + 0.5)),
		wall
	)
	-- The backdrop: the wall behind the avatar, with the swirl on the side facing the camera.
	local back = block(
		model,
		"Backdrop",
		Vector3.new(w, h, 1),
		CFrame.new(o + Vector3.new(0, h / 2, -ST.BackdropDistance - 0.5)),
		rgb(ST.BackdropColor)
	)
	local tiles: { number } = ST.SwirlTileStuds
	self.swirlA = swirl(back, "SwirlA", tiles[1], rgb(ST.SwirlColor), ST.SwirlTransparency)
	self.swirlB = swirl(back, "SwirlB", tiles[2], rgb(ST.SwirlColor), ST.SwirlTransparency)
	self.tint = swirl(back, "Tint", tiles[1] * 1.5, rgb(RARITY.Common), ST.TintTransparency)
	-- The glow on the floor under the avatar.
	local glowPart = block(
		model,
		"FloorGlow",
		Vector3.new(ST.FloorGlowStuds, 0.05, ST.FloorGlowStuds),
		CFrame.new(o + Vector3.new(0, 0.03, 0)),
		wall
	)
	glowPart.Transparency = 1
	glowPart.CastShadow = false
	local glow = Instance.new("Decal")
	glow.Name = "Glow"
	glow.Face = Enum.NormalId.Top
	glow.Texture = K.Art.SoftGlow
	glow.Transparency = ST.FloorGlowTransparency
	glow.Parent = glowPart
	self.floorGlow = glow
	-- The lights: a soft warm key from the front right, a cool fill from the front left.
	local keyCfg = ST.KeyLight
	local keyAt = o + Vector3.new(keyCfg.Offset[1], keyCfg.Offset[2], keyCfg.Offset[3])
	local keyPart = block(
		model,
		"KeyLight",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.lookAt(keyAt, o + Vector3.new(0, 3, 0)),
		wall
	)
	keyPart.Transparency = 1
	keyPart.CastShadow = false
	local key = Instance.new("SpotLight")
	key.Face = Enum.NormalId.Front
	key.Brightness = keyCfg.Brightness
	key.Range = keyCfg.Range
	key.Angle = keyCfg.Angle
	key.Color = rgb(keyCfg.Color)
	key.Shadows = true
	key.Parent = keyPart
	local fillCfg = ST.FillLight
	local fillAt = o + Vector3.new(fillCfg.Offset[1], fillCfg.Offset[2], fillCfg.Offset[3])
	local fillPart = block(model, "FillLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(fillAt), wall)
	fillPart.Transparency = 1
	fillPart.CastShadow = false
	local fill = Instance.new("PointLight")
	fill.Brightness = fillCfg.Brightness
	fill.Range = fillCfg.Range
	fill.Color = rgb(fillCfg.Color)
	fill.Shadows = false
	fill.Parent = fillPart
	self.model = model
	return model
end

-- The idle animation's id from a character's Animate script, or nil.
local function idleFrom(character: Instance): string?
	local animate = character:FindFirstChild("Animate")
	local idle = animate and animate:FindFirstChild("idle")
	if not idle then
		return nil
	end
	local best: Animation? = nil
	for _, child in idle:GetChildren() do
		if child:IsA("Animation") and child.AnimationId ~= "" then
			if best == nil or child.Name < best.Name then
				best = child
			end
		end
	end
	return if best then best.AnimationId else nil
end

-- A clone of the player's character standing on the floor facing the camera, playing its
-- idle; nil when there is no character to copy.
function UltStage.cloneAvatar(self: any, parent: Instance): (Model?, number)
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not root or not root:IsA("BasePart") then
		return nil, 5
	end
	local was = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = was
	if not ok or not copy then
		return nil, 5
	end
	local model = copy :: Model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local idleId = idleFrom(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or STRIP[d.ClassName] then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
	local copyRoot = model:FindFirstChild("HumanoidRootPart")
	if not copyRoot or not copyRoot:IsA("BasePart") then
		model:Destroy()
		return nil, 5
	end
	copyRoot.Anchored = true
	model.PrimaryPart = copyRoot
	local floorY = origin().Y
	local rootY = floorY + copyRoot.Size.Y / 2 + 2
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		pcall(function()
			humanoid.EvaluateStateMachine = false
		end)
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local leg = model:FindFirstChild("Left Leg")
			local legHeight = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
			rootY = floorY + legHeight + copyRoot.Size.Y / 2
			idleId = idleId or ST.IdleR6
		else
			rootY = floorY + humanoid.HipHeight + copyRoot.Size.Y / 2
			idleId = idleId or ST.IdleR15
		end
	end
	local at = Vector3.new(origin().X, rootY, origin().Z)
	model:PivotTo(CFrame.lookAt(at, at + Vector3.new(0, 0, 1)))
	model.Parent = parent
	local head = model:FindFirstChild("Head")
	local height = if head and head:IsA("BasePart")
		then head.Position.Y + head.Size.Y / 2 - floorY
		else rootY - floorY + 2.5
	self.root = copyRoot
	self.rootCFrame = copyRoot.CFrame
	if humanoid and idleId then
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if not animator then
			local made = Instance.new("Animator")
			made.Parent = humanoid
			animator = made
		end
		local animation = Instance.new("Animation")
		animation.AnimationId = idleId
		local loaded, track = pcall(function()
			return (animator :: Animator):LoadAnimation(animation)
		end)
		if loaded and track then
			track.Looped = true
			track:Play(0)
			self.track = track
		end
	end
	return model, math.max(2, height)
end

-- Where the camera stands and looks for an avatar `height` studs tall.
function UltStage.frame(self: any, height: number)
	local o = origin()
	self.focus = o + Vector3.new(0, height * (0.5 + ST.LookUpShare), 0)
	local half = math.tan(math.rad(ST.FieldOfView) / 2)
	self.distance = (height / ST.FillShare) / 2 / half
end

--- Build the room (once), put the avatar and its aura in it, and cut the camera there.
function UltStage.open(self: any, rarity: string?)
	if self.opened then
		return
	end
	self.opened = true
	local model = self:build()
	model.Parent = workspace
	local avatar, height = self:cloneAvatar(model)
	self.avatar = avatar
	self:frame(height)
	local o = origin()
	self.aura = UltAura.new(model, CFrame.new(o), height)
	self.aura:set(rarity or self.rarity, false)
	self:setRarity(rarity or self.rarity, false)
	local cam = workspace.CurrentCamera
	self.saved = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
	}
	cam.CameraType = Enum.CameraType.Scriptable
	self.clock = 0
	RunService:BindToRenderStep(
		RENDER_NAME,
		Enum.RenderPriority.Camera.Value + 2,
		function(dt: number)
			self:step(dt)
		end
	)
	self:step(0)
end

-- Every frame while open: the camera (with its slow drift) and the swirl.
function UltStage.step(self: any, dt: number)
	self.clock += dt
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local phase = self.clock / ST.SwaySeconds * math.pi * 2
	local drift = Vector3.new(math.sin(phase), math.sin(phase * 0.7) * 0.5, 0) * ST.SwayStuds
	local focus: Vector3 = self.focus
	local eye = focus + Vector3.new(0, 0, self.distance) + drift
	cam.FieldOfView = ST.FieldOfView
	cam.CFrame = CFrame.lookAt(eye, focus)
	cam.Focus = CFrame.new(focus)
	local speed: { number } = ST.SwirlSpeed
	local tiles: { number } = ST.SwirlTileStuds
	if self.swirlA then
		self.swirlA.OffsetStudsU = (self.clock * speed[1]) % tiles[1]
		self.swirlA.OffsetStudsV = (self.clock * speed[1] * 0.4) % tiles[1]
	end
	if self.swirlB then
		self.swirlB.OffsetStudsU = (self.clock * speed[2]) % tiles[2]
		self.swirlB.OffsetStudsV = (self.clock * speed[2] * -0.3) % tiles[2]
	end
end

--- Light the aura (and the floor glow and the backdrop's tint) in a rarity's colour; `burst`
--- for a spin landing.
function UltStage.setRarity(self: any, rarity: string?, burst: boolean?)
	local key = if rarity and TIERS[rarity] then rarity else "Common"
	self.rarity = key
	if not self.opened then
		return
	end
	-- The same colour again (a redraw) leaves a burst running.
	if self.aura and (burst or self.aura.rarity ~= key) then
		self.aura:set(key, burst)
	end
	local tier = TIERS[key]
	local colour = if tier.Color then rgb(tier.Color) else rgb(RARITY[key] or RARITY.Default)
	if self.floorGlow then
		self.floorGlow.Color3 = colour
	end
	if self.tint then
		self.tint.Color3 = colour
	end
end

--- The avatar's small hop as a spin lands.
function UltStage.bounce(self: any)
	local root: BasePart? = self.root
	if not self.opened or not root or not root.Parent then
		return
	end
	if self.bounceTween then
		self.bounceTween:Cancel()
	end
	local base: CFrame = self.rootCFrame
	root.CFrame = base
	local tween = TweenService:Create(
		root,
		TweenInfo.new(ST.BounceSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true),
		{ CFrame = base + Vector3.new(0, ST.BounceStuds, 0) }
	)
	self.bounceTween = tween
	tween:Play()
end

function UltStage.isOpen(self: any): boolean
	return self.opened
end

--- Put the camera back exactly as it was and take the room away.
function UltStage.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
	if self.bounceTween then
		self.bounceTween:Cancel()
		self.bounceTween = nil
	end
	local saved = self.saved
	self.saved = nil
	local cam = workspace.CurrentCamera
	if saved and not Camera.isLocked() then
		cam.CameraType = saved.kind
		cam.CameraSubject = saved.subject
		cam.FieldOfView = saved.fov
		cam.CFrame = saved.cframe
		cam.Focus = saved.focus
	end
	if self.track then
		self.track:Stop(0)
		self.track = nil
	end
	if self.aura then
		self.aura:destroy()
		self.aura = nil
	end
	if self.avatar then
		self.avatar:Destroy()
		self.avatar = nil
	end
	self.root = nil
	if self.model then
		self.model.Parent = nil
	end
end

return UltStage
