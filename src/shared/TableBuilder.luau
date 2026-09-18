--!strict
-- TableBuilder: builds the visible pool table out of Parts from the same Config numbers
-- the physics uses, so the cushions you see are exactly the cushions the balls bounce off.
-- This module touches Instances, so it lives outside Physics and is not run in tests.

local Config = require(script.Parent.Config)

local TableBuilder = {}

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

--- World-space position for a physics point (inches) at a height above the cloth (inches).
function TableBuilder.toWorld(xIn: number, yIn: number, heightIn: number): Vector3
	local s = Config.Table.StudsPerInch
	local o = Config.World.TableOrigin
	return Vector3.new(
		o.X + xIn * s,
		o.Y + (Config.Table.SurfaceHeightInches + heightIn) * s,
		o.Z - yIn * s
	)
end

--- Studs for an inch length.
function TableBuilder.studs(inches: number): number
	return inches * Config.Table.StudsPerInch
end

local function makePart(
	name: string,
	size: Vector3,
	position: Vector3,
	rgb: { number },
	mat: string,
	parent: Instance
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = true
	part.CastShadow = true
	part.Size = size
	part.Position = position
	part.Color = color(rgb)
	part.Material = material(mat)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

--- Build the table model under `parent`. Returns the model.
function TableBuilder.build(parent: Instance): Model
	local T = Config.Table
	local L = Config.Look
	local s = T.StudsPerInch
	local o = Config.World.TableOrigin
	local origin = Vector3.new(o.X, o.Y, o.Z)

	local model = Instance.new("Model")
	model.Name = "PoolTable"

	local length = T.LengthInches
	local width = T.WidthInches
	local railW = T.RailWidthInches
	local railH = T.RailHeightInches
	local bed = T.BedThicknessInches
	local surfaceY = T.SurfaceHeightInches
	local apronH = 7

	-- Cloth bed: top face is the playing surface.
	makePart(
		"Bed",
		Vector3.new(length * s, bed * s, width * s),
		origin + Vector3.new(0, (surfaceY - bed / 2) * s, 0),
		L.FeltColor,
		L.FeltMaterial,
		model
	)

	-- Wooden apron under the bed and rails.
	makePart(
		"Apron",
		Vector3.new((length + 2 * railW) * s, apronH * s, (width + 2 * railW) * s),
		origin + Vector3.new(0, (surfaceY - bed - apronH / 2) * s, 0),
		L.FrameColor,
		L.FrameMaterial,
		model
	)

	-- Rails. Inner faces sit exactly on the physics cushion lines (x = +-L/2, y = +-W/2).
	local railY = (surfaceY - bed + (railH + bed) / 2) * s
	local railSizeLong = Vector3.new((length + 2 * railW) * s, (railH + bed) * s, railW * s)
	local railSizeShort = Vector3.new(railW * s, (railH + bed) * s, width * s)
	-- Physics +y is world -Z.
	makePart(
		"RailTop",
		railSizeLong,
		origin + Vector3.new(0, railY, -(width / 2 + railW / 2) * s),
		L.RailColor,
		L.RailMaterial,
		model
	)
	makePart(
		"RailBottom",
		railSizeLong,
		origin + Vector3.new(0, railY, (width / 2 + railW / 2) * s),
		L.RailColor,
		L.RailMaterial,
		model
	)
	makePart(
		"RailFoot",
		railSizeShort,
		origin + Vector3.new((length / 2 + railW / 2) * s, railY, 0),
		L.RailColor,
		L.RailMaterial,
		model
	)
	makePart(
		"RailHead",
		railSizeShort,
		origin + Vector3.new(-(length / 2 + railW / 2) * s, railY, 0),
		L.RailColor,
		L.RailMaterial,
		model
	)

	-- Legs.
	local legH = surfaceY - bed - apronH
	local legSize = Vector3.new(5 * s, legH * s, 5 * s)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			makePart(
				"Leg",
				legSize,
				origin
					+ Vector3.new(sx * (length / 2 - 8) * s, legH / 2 * s, sz * (width / 2 - 4) * s),
				L.FrameColor,
				L.FrameMaterial,
				model
			)
		end
	end

	model.Parent = parent
	return model
end

return TableBuilder
