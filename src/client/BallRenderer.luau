--!strict
-- BallRenderer: keeps one Part per ball and moves it to wherever the simulation says.
-- Rolling rotation is derived from movement for looks only; it never feeds back into physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local UP = Vector3.new(0, 1, 0)

local BallRenderer = {}
BallRenderer.__index = BallRenderer

export type BallRenderer = typeof(setmetatable(
	{} :: {
		folder: Folder,
		parts: { [number]: Part },
		rotations: { [number]: CFrame },
		lastPositions: { [number]: Vector3 },
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

function BallRenderer.new(parent: Instance): BallRenderer
	local folder = Instance.new("Folder")
	folder.Name = "Balls"
	folder.Parent = parent
	local self = setmetatable({
		folder = folder,
		parts = {},
		rotations = {},
		lastPositions = {},
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
	part.Color = ballColor(id)
	part.Parent = self.folder
	self.parts[id] = part
	self.rotations[id] = CFrame.identity
	return part
end

--- Place ball `id` at physics coordinates (inches), rolling it by the distance moved.
function BallRenderer.place(self: BallRenderer, id: number, xIn: number, yIn: number)
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

--- Show or hide a ball (pocketed balls are hidden until milestone 2 animates the drop).
function BallRenderer.setVisible(self: BallRenderer, id: number, visible: boolean)
	local part = self:ensure(id)
	part.Transparency = if visible then 0 else 1
end

return BallRenderer
