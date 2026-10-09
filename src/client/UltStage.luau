--!strict
-- UltStage: the spin screen's stage (docs/prompts/ULTIMATES_PROMPT.md section 9.2). The
-- backdrop is the real world where the player stands (the designer, 2026-09-28): the avatar
-- is shown in place, in its idle and its rarity aura, and the camera looks at it from the
-- clearest side, so the lobby (or wherever they are) is the background.
--
-- The avatar is the player's real character (Stage.Live; designer, 2026-10-08: "the character
-- view is the actual character"). Opening stops it (its walk speed and jump at 0, as
-- PullCutscene holds it, and its run cut), but a jump or a fall goes on:
-- the camera follows the real character down and the stage waits up to SettleSeconds for it to
-- land. Then it turns to the camera, its root is anchored on this client so nothing nudges it,
-- and its own Animate script plays the idle; closing gives everything back. Its cue and
-- anything it carries are simply there, as in the world. With Live off, the old way: a client
-- clone (Archivable set for the clone and put back; scripts, sounds and name tags removed; the
-- root anchored, the rest held by its joints) standing on the ground under the player, playing
-- the character's idle (from its Animate script, else Roblox's default R15 or R6 idle), with
-- the real character hidden. Every other player's character and every name plate (the
-- player's own too) are hidden on this client only (LocalTransparencyModifier and Enabled,
-- kept up every HideRefreshSeconds for anyone who respawns or joins) and all put back on
-- close. The aura is UltAura, with a soft glow on the ground under it and two small lights on
-- the avatar.
--
-- The camera's side: where the player's camera already is first (so the background is what
-- they were looking at), then turning further round each way
-- (ViewTries directions), the first whose line from the avatar to the camera is clear of the
-- world; boxed in on every side, the one with the most room, pulled in to fit.
--
-- Opening flies the camera there fast and smoothly (FlySeconds; Reduce Motion cuts), then drives
-- it every frame (Scriptable, with a slow drift); closing
-- puts it back exactly as it was (its type, subject, field of view, CFrame and focus), unless
-- the match camera has taken it meanwhile (Camera.isLocked), which then keeps it. Everything
-- built is client-side, anchored and non-colliding, and removed on close.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Camera = require(script.Parent.Camera)
local UIAnim = require(script.Parent.UIAnim)
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

-- An anchored, invisible, non-colliding holder part.
local function holder(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = cframe
	part.Parent = parent
	return part
end

--- The stage, not built until opened.
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
	self.facing = Vector3.new(0, 0, 1) -- from the avatar toward the camera, flat
	self.distance = 12
	self.bounceTween = nil :: Tween?
	self.hidden = {} :: { [Instance]: number } -- part or decal: its LocalTransparencyModifier
	self.hiddenGuis = {} :: { [LayerCollector]: boolean } -- plate: its Enabled
	self.hideClock = 0
	self.live = nil :: any -- the live stage's character and what to give back (Stage.Live)
	self.settled = true
	self.settleClock = 0
	return self
end

-- A ray that sees only the world: never a character, nor the stage itself.
local function worldParams(self: any): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(skip, player.Character)
		end
	end
	if self.model then
		table.insert(skip, self.model)
	end
	params.FilterDescendantsInstances = skip
	params.IgnoreWater = true
	return params
end

-- Where the character stands: the ground under its root (or its feet by its size), and its
-- flat facing.
local function standing(self: any, root: BasePart, humanoid: Humanoid?): (Vector3, Vector3)
	local at = root.Position
	local drop = root.Size.Y / 2 + (if humanoid then humanoid.HipHeight else 2) + 0.5
	local hit =
		workspace:Raycast(at, Vector3.new(0, -(drop + ST.GroundSearchStuds), 0), worldParams(self))
	local ground = if hit then hit.Position.Y else at.Y - drop + 0.5
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return Vector3.new(at.X, ground, at.Z), flat.Unit
end

-- The side the camera looks from, and how far it can stand: the facing first, then turning
-- further round each way; the first clear line wins, else the one with the most room.
function UltStage.pickView(
	self: any,
	focus: Vector3,
	facing: Vector3,
	want: number
): (Vector3, number)
	local params = worldParams(self)
	local tries: number = ST.ViewTries
	local reach = want + ST.ClearanceStuds
	local bestDir, bestRoom = facing, -1
	for i = 0, tries - 1 do
		-- 0, +1, -1, +2, -2, ... steps of a full turn / tries.
		local k = math.ceil(i / 2) * (if i % 2 == 1 then 1 else -1)
		local angle = k * (math.pi * 2 / tries)
		local dir = (CFrame.fromAxisAngle(Vector3.yAxis, angle) :: CFrame):VectorToWorldSpace(
			facing
		)
		local offset = dir * reach + Vector3.new(0, 0, 0)
		local hit = workspace:Raycast(focus, offset, params)
		if hit == nil then
			return dir, want
		end
		local room = (hit.Position - focus).Magnitude
		if room > bestRoom then
			bestDir, bestRoom = dir, room
		end
	end
	return bestDir, math.max(ST.MinCameraStuds, bestRoom - ST.ClearanceStuds)
end

-- Hide one character (parts and decals) on this client, remembering what to put back.
local function hideCharacter(self: any, character: Model)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local item = d :: any
			if self.hidden[item] == nil then
				self.hidden[item] = item.LocalTransparencyModifier
			end
			item.LocalTransparencyModifier = 1
		end
	end
end

-- Every player's character (the clone stands in for this one; a live stage keeps it) and
-- every plate over them.
function UltStage.hidePlayers(self: any)
	local characters: { Model } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		if character then
			table.insert(characters, character)
			if not (self.live and character == self.live.character) then
				hideCharacter(self, character)
			end
		end
	end
	local playerGui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end
	for _, gui in playerGui:GetChildren() do
		if gui:IsA("BillboardGui") and gui.Adornee then
			for _, character in characters do
				if gui.Adornee:IsDescendantOf(character) then
					if self.hiddenGuis[gui] == nil then
						self.hiddenGuis[gui] = gui.Enabled
					end
					gui.Enabled = false
					break
				end
			end
		end
	end
end

function UltStage.showPlayers(self: any)
	for d, was in self.hidden do
		if d.Parent then
			(d :: any).LocalTransparencyModifier = was
		end
	end
	for gui, was in self.hiddenGuis do
		if gui.Parent then
			gui.Enabled = was
		end
	end
	self.hidden = {}
	self.hiddenGuis = {}
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

-- How far a character's root stands above its feet.
local function rootAbove(root: BasePart, humanoid: Humanoid?): number
	local legs = 2
	if humanoid then
		if humanoid.RigType == Enum.HumanoidRigType.R6 then
			local leg = root.Parent and root.Parent:FindFirstChild("Left Leg")
			legs = if leg and leg:IsA("BasePart") then leg.Size.Y else 2
		else
			legs = humanoid.HipHeight
		end
	end
	return root.Size.Y / 2 + legs
end

-- Where a character's feet are now (in the air too): under its root by its legs.
local function feetOf(root: BasePart, humanoid: Humanoid?): Vector3
	return root.Position - Vector3.new(0, rootAbove(root, humanoid), 0)
end

-- A character's height from its feet to the top of its head.
local function heightOf(character: Model, feetY: number, fallback: number): number
	local head = character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return math.max(2, head.Position.Y + head.Size.Y / 2 - feetY)
	end
	return fallback
end

-- On the ground: the humanoid stands on something (a seat counts).
local function landed(humanoid: Humanoid?): boolean
	if not humanoid then
		return true
	end
	return humanoid.SeatPart ~= nil or humanoid.FloorMaterial ~= Enum.Material.Air
end

-- The live stage's camera target while the character is still coming down: its feet now.
function UltStage.followLive(self: any)
	local live = self.live
	local root: BasePart = live.root
	if not root.Parent then
		return
	end
	local feet = feetOf(root, live.humanoid)
	self:frame(feet, heightOf(live.character, feet.Y, live.height))
end

-- The live stage once the character is down (or the wait is over): it turns to the camera and
-- holds still (anchored on this client), and the aura, the glow and the lights go round it.
function UltStage.settleLive(self: any)
	self.settled = true
	local live = self.live
	local root: BasePart = live.root
	local humanoid: Humanoid? = live.humanoid
	if not root.Parent or not self.model then
		return
	end
	local toward: Vector3 = self.facing
	local seated = humanoid ~= nil and humanoid.SeatPart ~= nil
	if not seated and landed(humanoid) then
		if humanoid then
			humanoid.AutoRotate = false
		end
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		-- Held at its standing height on the ground under it: a landing's dip (the hips sink
		-- for a moment as it touches down) is not frozen in.
		local ground = standing(self, root, humanoid)
		local at =
			Vector3.new(root.Position.X, ground.Y + rootAbove(root, humanoid), root.Position.Z)
		root.CFrame = CFrame.lookAt(at, at + toward)
		root.Anchored = true
		live.held = true
	end
	self.root = root
	self.rootCFrame = root.CFrame
	local feet = feetOf(root, humanoid)
	local height = heightOf(live.character, feet.Y, live.height)
	self:frame(feet, height)
	self:dress(self.model, feet, toward)
	self.aura = UltAura.new(self.model, CFrame.lookAt(feet, feet - toward), height)
	self.aura:set(self.rarity, false)
	self:setRarity(self.rarity, false)
end

-- Open the live stage on the player's real character (Stage.Live).
function UltStage.openLive(self: any, character: Model, root: BasePart)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	self.live = {
		character = character,
		root = root,
		humanoid = humanoid,
		anchored = root.Anchored,
		-- The humanoid's own values, put back on close (as PullCutscene and GiftDrop hold it).
		saved = if humanoid
			then {
				WalkSpeed = humanoid.WalkSpeed,
				JumpPower = humanoid.JumpPower,
				JumpHeight = humanoid.JumpHeight,
				AutoRotate = humanoid.AutoRotate,
			}
			else nil,
		held = false,
		height = 5,
	}
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid:Move(Vector3.zero)
	end
	-- The run stops; a jump or a fall goes on (the camera follows it down).
	local v = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	-- The camera's own side first, so the background is what the player was looking at.
	local cam = workspace.CurrentCamera
	local look = cam.CFrame.LookVector
	local back = Vector3.new(-look.X, 0, -look.Z)
	local facing = if back.Magnitude > 1e-3 then back.Unit else Vector3.new(0, 0, 1)
	local feet = feetOf(root, humanoid)
	local height = heightOf(character, feet.Y, 5)
	self.live.height = height
	local want = self:frame(feet, height)
	local toward, distance = self:pickView(self.focus, facing, want)
	self.facing = toward
	self.distance = distance
	self.settled = false
	self.settleClock = 0
end

-- Give the live stage's character back: unanchored, walking, jumping and turning again.
function UltStage.closeLive(self: any)
	local live = self.live
	self.live = nil
	if not live then
		return
	end
	local root: BasePart = live.root
	if root.Parent and live.held then
		root.Anchored = live.anchored
	end
	local humanoid: Humanoid? = live.humanoid
	if humanoid and humanoid.Parent and live.saved then
		for key, value in live.saved do
			(humanoid :: any)[key] = value
		end
	end
end

-- A clone of the player's character standing on `ground`, facing `facing` (flat), playing its
-- idle; nil when there is no character to copy.
function UltStage.cloneAvatar(
	self: any,
	parent: Instance,
	ground: Vector3,
	facing: Vector3
): (Model?, number)
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
		elseif d:IsA("Decal") then
			d.LocalTransparencyModifier = 0
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
	local floorY = ground.Y
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
	local at = Vector3.new(ground.X, rootY, ground.Z)
	model:PivotTo(CFrame.lookAt(at, at + facing))
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

-- Where the camera looks for an avatar `height` studs tall standing on `ground`, and how far
-- back it would like to stand.
function UltStage.frame(self: any, ground: Vector3, height: number): number
	self.focus = ground + Vector3.new(0, height * (0.5 + ST.LookUpShare), 0)
	local half = math.tan(math.rad(ST.FieldOfView) / 2)
	return (height / ST.FillShare) / 2 / half
end

-- The glow on the ground and the two lights, placed for the camera's side: offsets are in the
-- avatar's frame (x right, y up, z toward the camera).
function UltStage.dress(self: any, model: Model, ground: Vector3, toward: Vector3)
	local frame = CFrame.lookAt(ground, ground - toward) -- +Z toward the camera
	local glowPart = holder(
		model,
		"FloorGlow",
		Vector3.new(ST.FloorGlowStuds, 0.05, ST.FloorGlowStuds),
		frame * CFrame.new(0, 0.03, 0)
	)
	local glow = Instance.new("Decal")
	glow.Name = "Glow"
	glow.Face = Enum.NormalId.Top
	glow.Texture = K.Art.SoftGlow
	glow.Transparency = ST.FloorGlowTransparency
	glow.Parent = glowPart
	self.floorGlow = glow
	local keyCfg = ST.KeyLight
	local keyAt = frame * Vector3.new(keyCfg.Offset[1], keyCfg.Offset[2], keyCfg.Offset[3])
	local keyPart = holder(
		model,
		"KeyLight",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.lookAt(keyAt, ground + Vector3.new(0, 3, 0))
	)
	local key = Instance.new("SpotLight")
	key.Face = Enum.NormalId.Front
	key.Brightness = keyCfg.Brightness
	key.Range = keyCfg.Range
	key.Angle = keyCfg.Angle
	key.Color = rgb(keyCfg.Color)
	key.Shadows = false
	key.Parent = keyPart
	local fillCfg = ST.FillLight
	local fillAt = frame * Vector3.new(fillCfg.Offset[1], fillCfg.Offset[2], fillCfg.Offset[3])
	local fillPart = holder(model, "FillLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(fillAt))
	local fill = Instance.new("PointLight")
	fill.Brightness = fillCfg.Brightness
	fill.Range = fillCfg.Range
	fill.Color = rgb(fillCfg.Color)
	fill.Shadows = false
	fill.Parent = fillPart
end

--- Stand the avatar where the player is, hide the players, and cut the camera to it. Without a
--- character (still loading) the screen opens over the world as the camera sees it.
function UltStage.open(self: any, rarity: string?)
	if self.opened then
		return
	end
	self.opened = true
	local model = Instance.new("Model")
	model.Name = "UltStage"
	model.Parent = workspace
	self.model = model
	local player = Players.LocalPlayer
	local character = player and player.Character
	local realRoot = character and character:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	self.saved = {
		kind = cam.CameraType,
		subject = cam.CameraSubject,
		cframe = cam.CFrame,
		focus = cam.Focus,
		fov = cam.FieldOfView,
	}
	self.hidden = {}
	self.hiddenGuis = {}
	if ST.Live and character and realRoot and realRoot:IsA("BasePart") then
		self:openLive(character, realRoot)
	elseif character and realRoot and realRoot:IsA("BasePart") then
		local ground, facing = standing(self, realRoot, character:FindFirstChildOfClass("Humanoid"))
		-- The camera's own side first, so the background is what the player was looking at.
		local look = cam.CFrame.LookVector
		local back = Vector3.new(-look.X, 0, -look.Z)
		if back.Magnitude > 1e-3 then
			facing = back.Unit
		end
		local avatar, height = self:cloneAvatar(model, ground, facing)
		self.avatar = avatar
		local want = self:frame(ground, height)
		local toward, distance = self:pickView(self.focus, facing, want)
		self.facing = toward
		self.distance = distance
		if avatar and self.root then
			local at = self.root.Position
			avatar:PivotTo(CFrame.lookAt(at, at + toward))
			self.rootCFrame = self.root.CFrame
		end
		self:dress(model, ground, toward)
		self.aura = UltAura.new(model, CFrame.lookAt(ground, ground - toward), height)
		self.aura:set(rarity or self.rarity, false)
	else
		self.focus = cam.Focus.Position
		self.facing = -cam.CFrame.LookVector
		self.distance = (cam.CFrame.Position - self.focus).Magnitude
	end
	if ST.HidePlayers then
		self:hidePlayers()
	end
	self:setRarity(rarity or self.rarity, false)
	cam.CameraType = Enum.CameraType.Scriptable
	-- The fly in starts where the player's camera was.
	self.fly = if UIAnim.reduced()
		then nil
		else { clock = 0, from = self.saved.cframe, fov = self.saved.fov }
	self.clock = 0
	self.hideClock = 0
	RunService:BindToRenderStep(
		RENDER_NAME,
		Enum.RenderPriority.Camera.Value + 2,
		function(dt: number)
			self:step(dt)
		end
	)
	self:step(0)
end

-- Every frame while open: the camera (with its slow drift), and the players kept hidden.
function UltStage.step(self: any, dt: number)
	self.clock += dt
	self.hideClock += dt
	if ST.HidePlayers then
		-- The camera scripts set the character's own transparency every frame; this runs after
		-- them. A full pass now and then catches anyone who respawned or joined.
		if self.hideClock >= ST.HideRefreshSeconds then
			self.hideClock = 0
			self:hidePlayers()
		else
			for d in self.hidden do
				(d :: any).LocalTransparencyModifier = 1
			end
		end
	end
	if self.live and not self.settled then
		self.settleClock += dt
		if landed(self.live.humanoid) or self.settleClock >= ST.SettleSeconds then
			self:settleLive()
		else
			self:followLive()
		end
	end
	local cam = workspace.CurrentCamera
	if cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local phase = self.clock / ST.SwaySeconds * math.pi * 2
	local toward: Vector3 = self.facing
	local right = toward:Cross(Vector3.yAxis)
	local drift = (right * math.sin(phase) + Vector3.yAxis * math.sin(phase * 0.7) * 0.5)
		* ST.SwayStuds
	local focus: Vector3 = self.focus
	local eye = focus + toward * self.distance + drift
	local view = CFrame.lookAt(eye, focus)
	local fov = ST.FieldOfView
	local fly = self.fly
	if fly then
		-- Flying in: from the old camera to the view (which may still be moving: a fall).
		fly.clock += dt
		local t = math.clamp(fly.clock / ST.FlySeconds, 0, 1)
		local e = 1 - (1 - t) ^ ST.FlyPower
		view = (fly.from :: CFrame):Lerp(view, e)
		fov = fly.fov + (fov - fly.fov) * e
		if t >= 1 then
			self.fly = nil
		end
	end
	cam.FieldOfView = fov
	cam.CFrame = view
	cam.Focus = CFrame.new(focus)
end

--- Light the aura (and the glow on the ground) in a rarity's colour; `burst`
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
end

--- The avatar's small hop as a spin lands.
function UltStage.bounce(self: any)
	local root: BasePart? = self.root
	if not self.opened or not root or not root.Parent then
		return
	end
	if self.live and not self.live.held then
		return -- a live character not held still (seated, or still falling) keeps its physics
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

--- Put the camera back exactly as it was, take the stage away and show the players again.
function UltStage.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	RunService:UnbindFromRenderStep(RENDER_NAME)
	if self.bounceTween then
		self.bounceTween:Cancel()
		self.bounceTween = nil
		if self.live and self.live.held and self.root and self.rootCFrame then
			self.root.CFrame = self.rootCFrame
		end
	end
	self:closeLive()
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
	self.floorGlow = nil
	if self.model then
		self.model:Destroy()
		self.model = nil
	end
	self:showPlayers()
end

return UltStage
