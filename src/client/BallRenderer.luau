--!strict
-- BallRenderer: keeps one Part per ball and moves it to wherever the simulation says.
-- Rolling rotation is derived from movement for looks only; it never feeds back into physics.
-- Solids are coloured spheres. Stripes are white spheres with a tinted band decal on the
-- four side faces. Every numbered ball gets a number decal on its front and back faces.
-- Without decal ids (Config.Balls.Decals) stripes fall back to their plain colour.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local UP = Vector3.new(0, 1, 0)
local WHITE = Color3.fromRGB(245, 242, 232)

local BallRenderer = {}
BallRenderer.__index = BallRenderer

export type BallRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		parts: { [number]: Part },
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

function BallRenderer.new(parent: Instance): BallRenderer
	local folder = Instance.new("Folder")
	folder.Name = "Balls"
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		parts = {},
		rotations = {},
		lastPositions = {},
		sunk = {},
	}, BallRenderer)
	return self
end

function BallRenderer.ensure(self: BallRenderer, id: number): Part
	local existing = self.parts[id]
	if existing then
		return existing
	end
	local diameter = TableBuilder.studs(Config.Balls.RadiusInches * 2)
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
function BallRenderer.place(self: BallRenderer, id: number, xIn: number, yIn: number)
	if self.sunk[id] then
		return
	end
	local part = self:ensure(id)
	local pos = TableBuilder.toWorld(xIn, yIn, Config.Balls.RadiusInches)
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

--- Animate a ball dropping into a pocket, then hide it.
function BallRenderer.sink(self: BallRenderer, id: number, pocketXIn: number, pocketYIn: number)
	local part = self:ensure(id)
	self.sunk[id] = true
	local target = TableBuilder.toWorld(pocketXIn, pocketYIn, -Config.Balls.RadiusInches * 3)
	local tween = TweenService:Create(
		part,
		TweenInfo.new(
			Config.Effects.SinkDropSeconds,
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.In
		),
		{ CFrame = CFrame.new(target) * self.rotations[id], Transparency = 1 }
	)
	tween:Play()
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
