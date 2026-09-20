--!strict
-- BallRenderer: keeps one part per ball and moves it to wherever the simulation says.
--
-- Rotation comes from the simulation's own angular velocity, never from how far the ball
-- moved. That distinction is the whole point: the physics models a SLIDING phase (spin and
-- velocity disagree, which is why a firmly struck cue ball skids before it rolls) and a
-- separate ROLLING phase. Deriving rotation from displacement draws every ball as if it
-- were rolling perfectly from the instant it left the cue, hides side spin completely, and
-- spins balls wildly as they drop into a pocket (the fall is displacement too).
--
-- Preferred look: a real sphere MeshPart (template copied to ReplicatedStorage.Assets by the
-- server) with one baked texture per ball (Config.Balls.Textures). Fallback when the template
-- or a texture is missing: a Ball Part, solids coloured, stripes white with a tinted band
-- decal on the four side faces, number decals front and back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Ball = require(Shared:WaitForChild("Physics"):WaitForChild("Ball"))

local WHITE = Color3.fromRGB(245, 242, 232)

local BallRenderer = {}
BallRenderer.__index = BallRenderer

export type BallRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		placement: Placement.Placement,
		yaw: CFrame,
		parts: { [number]: BasePart },
		rotations: { [number]: CFrame },
		spinSteps: { [number]: number },
		sunk: { [number]: boolean },
	},
	BallRenderer
))

local function ballColor(id: number): Color3
	local colors = Config.Balls.Colors
	local rgb = colors[id]
	if rgb == nil and id >= 9 then
		rgb = colors[id - 8]
	end
	rgb = rgb or { 255, 255, 255 }
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function addDecal(part: Part, face: Enum.NormalId, texture: string, color: Color3?)
	local decal = Instance.new("Decal")
	decal.Face = face
	decal.Texture = texture
	if color then
		decal.Color3 = color
	end
	decal.Parent = part
end

function BallRenderer.new(parent: Instance, p: Placement.Placement, id: number): BallRenderer
	local folder = Instance.new("Folder")
	-- One folder per table, named by table id: twelve folders all called "Balls" would be
	-- unreadable in the explorer once the lounge is built.
	folder.Name = ("Balls_%02d"):format(id)
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		placement = p,
		yaw = TableBuilder.yawCFrame(p),
		parts = {},
		rotations = {},
		spinSteps = {},
		sunk = {},
	}, BallRenderer)
	return self
end

--- Point this renderer at a different table. The parts are kept and moved rather than
--- rebuilt: walking past a row of tables would otherwise destroy and recreate sixteen
--- MeshParts each time, which is exactly the hitch this pooling exists to avoid.
function BallRenderer.rebind(self: BallRenderer, p: Placement.Placement, id: number)
	self.placement = p
	self.yaw = TableBuilder.yawCFrame(p)
	self.folder.Name = ("Balls_%02d"):format(id)
	-- A ball must not carry the last table's tumble or its pocketed state across.
	for ballId in self.rotations do
		self.rotations[ballId] = CFrame.identity
		self.spinSteps[ballId] = 0
	end
	self.sunk = {}
end

-- The imported sphere mesh, if the place has it and the server published it.
local function meshTemplate(): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local template = assets and assets:FindFirstChild(Config.Balls.MeshTemplate)
	if template and template:IsA("MeshPart") then
		return template
	end
	return nil
end

function BallRenderer.ensure(self: BallRenderer, id: number): BasePart
	local existing = self.parts[id]
	if existing then
		return existing
	end
	local diameter = TableBuilder.studs(Config.Balls.RadiusInches * 2)
	local textureId = Config.Balls.Textures[id] or ""
	local template = meshTemplate()
	if template and textureId ~= "" then
		local mesh = template:Clone()
		mesh.Name = if id == 0 then "CueBall" else ("Ball" .. id)
		mesh.Size = Vector3.new(diameter, diameter, diameter)
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CastShadow = true
		mesh.Material = (Enum.Material :: any)[Config.Look.BallMaterial]
		mesh.Reflectance = Config.Balls.Reflectance
		mesh.Color = Color3.new(1, 1, 1)
		mesh.TextureID = textureId
		mesh.Transparency = 0
		mesh.Parent = self.folder
		self.parts[id] = mesh
		self.rotations[id] = CFrame.identity
		return mesh
	end
	local part = Instance.new("Part")
	part.Name = if id == 0 then "CueBall" else ("Ball" .. id)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = true
	part.Material = (Enum.Material :: any)[Config.Look.BallMaterial]
	part.Reflectance = Config.Balls.Reflectance

	local decals = Config.Balls.Decals
	local isStripe = id >= 9
	local color = ballColor(id)
	if isStripe and decals.StripeBand ~= "" then
		part.Color = WHITE
		for _, face in
			{ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
		do
			addDecal(part, face, decals.StripeBand, color)
		end
	else
		part.Color = color
	end
	local numberId = decals.Numbers[id]
	if id > 0 and numberId and numberId ~= "" then
		addDecal(part, Enum.NormalId.Front, numberId)
		addDecal(part, Enum.NormalId.Back, numberId)
	end

	part.Parent = self.folder
	self.parts[id] = part
	self.rotations[id] = CFrame.identity
	return part
end

--- Place ball `id` at physics coordinates (inches) without turning it. zIn is the height
--- relative to the cloth (negative while dropping into a pocket).
function BallRenderer.place(self: BallRenderer, id: number, xIn: number, yIn: number, zIn: number?)
	if self.sunk[id] then
		return
	end
	local part = self:ensure(id)
	local pos =
		TableBuilder.toWorld(self.placement, xIn, yIn, Config.Balls.RadiusInches + (zIn or 0))
	part.CFrame = CFrame.new(pos) * self.rotations[id]
end

-- Thousands of CFrame multiplications drift off orthonormal, which shears the ball. Every
-- so often, rebuild the rotation from two re-squared axes.
local function renormalise(rot: CFrame): CFrame
	local right = rot.RightVector.Unit
	local up = rot.UpVector
	up = (up - right * up:Dot(right)).Unit
	return CFrame.fromMatrix(Vector3.zero, right, up)
end

--- Move and turn ball `b` for a frame of `dt` seconds. The turn comes from the ball's
--- angular velocity, so a skidding ball barely rotates and a ball with side spin turns on
--- the spot, exactly as the simulation says.
function BallRenderer.step(self: BallRenderer, b: Ball.Ball, dt: number)
	if self.sunk[b.id] then
		return
	end
	local part = self:ensure(b.id)
	local pos = TableBuilder.toWorld(self.placement, b.x, b.y, Config.Balls.RadiusInches + b.z)
	local rot = self.rotations[b.id]
	-- Physics (x, y, z) maps to world (X, -Z, Y). That map is a proper rotation, so angular
	-- velocity (a pseudovector) transforms exactly like a vector; then the table's own yaw
	-- turns it the rest of the way into world space. Miss the yaw and every ball on a
	-- turned table rolls sideways.
	local w = self.yaw:VectorToWorldSpace(Vector3.new(b.wx, b.wz, -b.wy))
	local rate = w.Magnitude
	if rate > 1e-6 and dt > 0 then
		rot = CFrame.fromAxisAngle(w / rate, rate * dt) * rot
		local n = (self.spinSteps[b.id] or 0) + 1
		if n >= Config.Balls.RotationRenormaliseSteps then
			n = 0
			rot = renormalise(rot)
		end
		self.spinSteps[b.id] = n
		self.rotations[b.id] = rot
	end
	part.CFrame = CFrame.new(pos) * rot
end

--- Hide a ball that has finished dropping into a pocket.
function BallRenderer.sink(self: BallRenderer, id: number)
	local part = self:ensure(id)
	self.sunk[id] = true
	part.Transparency = 1
end

--- Bring a ball back onto the table (cue ball after a scratch, or a new rack). The ball
--- comes back upright: a fresh rack should not inherit the last game's tumbling.
function BallRenderer.restore(self: BallRenderer, id: number, xIn: number, yIn: number)
	local part = self:ensure(id)
	self.sunk[id] = nil
	self.rotations[id] = CFrame.identity
	self.spinSteps[id] = 0
	part.Transparency = 0
	self:place(id, xIn, yIn)
end

function BallRenderer.setVisible(self: BallRenderer, id: number, visible: boolean)
	local part = self:ensure(id)
	if visible then
		self.sunk[id] = nil
		part.Transparency = 0
	else
		self.sunk[id] = true
		part.Transparency = 1
	end
end

return BallRenderer
