--!strict
-- TableBuilder: builds the visible pool table out of Parts from the same Config numbers
-- the physics uses, so the cushions you see are exactly the cushions the balls bounce off.
-- This module touches Instances, so it lives outside Physics and is not run in tests.

local Config = require(script.Parent.Config)
local TableGeometry = require(script.Parent.Physics.Table)

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

	-- Rails: one block per physics cushion segment, so the visible cushion faces are exactly
	-- the lines the balls bounce off, and the gaps between them are exactly the pocket mouths.
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local railY = (surfaceY - bed + (railH + bed) / 2) * s
	for _, seg in geometry.segments do
		local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
		local segLen = math.sqrt(dx * dx + dy * dy)
		-- Midpoint pushed outward (away from the inward normal) by half the rail width.
		local mx = (seg.ax + seg.bx) / 2 - seg.nx * railW / 2
		local my = (seg.ay + seg.by) / 2 - seg.ny * railW / 2
		local alongX = math.abs(dx) > math.abs(dy)
		-- Rails along the length reach out to the outer corner of the table; short rails stay
		-- within the width. Both get their outer end extended past the mouth cut so the frame
		-- reads as one piece around each pocket.
		local size = if alongX
			then Vector3.new(segLen * s, (railH + bed) * s, railW * s)
			else Vector3.new(railW * s, (railH + bed) * s, segLen * s)
		makePart(
			"Rail_" .. seg.name,
			size,
			origin + Vector3.new(mx * s, railY, -my * s),
			L.RailColor,
			L.RailMaterial,
			model
		)
	end

	-- Pocket liners: dark cylinders from the apron up to just above the cloth. The sinking
	-- animation drops the ball through them.
	local linerH = bed + 0.3
	for _, pocket in geometry.pockets do
		local liner = Instance.new("Part")
		liner.Name = "Pocket" .. pocket.id
		liner.Shape = Enum.PartType.Cylinder
		liner.Anchored = true
		liner.CanCollide = false
		liner.CastShadow = false
		liner.Material = Enum.Material.SmoothPlastic
		liner.Color = Color3.fromRGB(L.PocketColor[1], L.PocketColor[2], L.PocketColor[3])
		-- Cylinders point along their X axis; stand it up.
		liner.Size = Vector3.new(linerH * s, pocket.radius * 2 * s, pocket.radius * 2 * s)
		liner.CFrame = CFrame.new(
			origin + Vector3.new(pocket.x * s, (surfaceY - bed + linerH / 2) * s, -pocket.y * s)
		) * CFrame.Angles(0, 0, math.rad(90))
		liner.Parent = model
	end

	-- Corner blocks: fill the frame behind each corner pocket so the apron corner is not bare.
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			local c = (T.CornerMouthInches + 2 * T.JawRadiusInches) / math.sqrt(2)
			local blockSize = Vector3.new((c + railW) * s, (railH + bed) * s, railW * s)
			-- Along the long rail, from the mouth cut to the outer corner.
			makePart(
				"CornerLong",
				blockSize,
				origin
					+ Vector3.new(
						sx * (length / 2 + railW - (c + railW) / 2) * s,
						railY,
						-sy * (width / 2 + railW / 2) * s
					),
				L.RailColor,
				L.RailMaterial,
				model
			)
			local blockSize2 = Vector3.new(railW * s, (railH + bed) * s, c * s)
			makePart(
				"CornerShort",
				blockSize2,
				origin
					+ Vector3.new(
						sx * (length / 2 + railW / 2) * s,
						railY,
						-sy * (width / 2 - c / 2) * s
					),
				L.RailColor,
				L.RailMaterial,
				model
			)
		end
	end

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
