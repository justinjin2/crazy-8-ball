--!strict
-- BallRenderer: keeps one part per ball and moves it to wherever the simulation says.
-- Rolling rotation is derived from movement for looks only; it never feeds back into physics.
-- Preferred look: a real sphere MeshPart (template copied to ReplicatedStorage.Assets by the
-- server) with one baked texture per ball (Config.Balls.Textures). Fallback when the template
-- or a texture is missing: a Ball Part, solids coloured, stripes white with a tinted band
-- decal on the four side faces, number decals front and back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.fromRGB(245, 242, 232)

local BallRenderer = {}
BallRenderer.__index = BallRenderer

export type BallRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		placement: Placement.Placement,
		parts: { [number]: BasePart },
		rotations: { [number]: CFrame },
		lastPositions: { [number]: Vector3 },
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
		parts = {},
		rotations = {},
		lastPositions = {},
		sunk = {},
	}, BallRenderer)
	return self
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

--- Place ball `id` at physics coordinates (inches), rolling it by the distance moved.
--- zIn is the height relative to the cloth (negative while dropping into a pocket).
function BallRenderer.place(self: BallRenderer, id: number, xIn: number, yIn: number, zIn: number?)
	if self.sunk[id] then
		return
	end
	local part = self:ensure(id)
	local pos =
		TableBuilder.toWorld(self.placement, xIn, yIn, Config.Balls.RadiusInches + (zIn or 0))
	local last = self.lastPositions[id]
	local rot = self.rotations[id]
	if last then
		local delta = pos - last
		local dist = delta.Magnitude
		if dist > 1e-6 then
			local axis = UP:Cross(delta.Unit)
			if axis.Magnitude > 1e-6 then
				local angle = dist / TableBuilder.studs(Config.Balls.RadiusInches)
				rot = CFrame.fromAxisAngle(axis.Unit, angle) * rot
				self.rotations[id] = rot
			end
		end
	end
	self.lastPositions[id] = pos
	part.CFrame = CFrame.new(pos) * rot
end

--- Hide a ball that has finished dropping into a pocket.
function BallRenderer.sink(self: BallRenderer, id: number)
	local part = self:ensure(id)
	self.sunk[id] = true
	part.Transparency = 1
end

--- Bring a ball back onto the table (cue ball after a scratch, or a new rack).
function BallRenderer.restore(self: BallRenderer, id: number, xIn: number, yIn: number)
	local part = self:ensure(id)
	self.sunk[id] = nil
	self.lastPositions[id] = nil
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
