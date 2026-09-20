--!strict
-- TableBuilder: builds the visible pool table out of Parts from the same Config numbers
-- the physics uses, so the cushions you see are exactly the cushions the balls bounce off.
-- This module touches Instances, so it lives outside Physics and is not run in tests.
--
-- Layout, from the outside in: a wooden frame ring at rail-top height, the rubber cushion
-- strips (one per physics segment, inner face on the cushion line, lower than the frame),
-- the cloth bed inside, and six dark pocket liners cut through the frame at the mouths.

local Config = require(script.Parent.Config)
local Placement = require(script.Parent.Placement)
local TableGeometry = require(script.Parent.Physics.Table)

local TableBuilder = {}

export type Placement = Placement.Placement

--- Folder in Workspace that holds every server-built table model.
TableBuilder.FolderName = "Tables"

--- Instance name for table `id`: Table_01 ... Table_12.
function TableBuilder.modelName(id: number): string
	return ("Table_%02d"):format(id)
end

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function material(name: string): Enum.Material
	return (Enum.Material :: any)[name]
end

--- World-space position for a physics point (inches) on table `p` at a height above the
--- cloth (inches). The maths lives in Placement (pure, tested); this only makes a Vector3.
function TableBuilder.toWorld(p: Placement, xIn: number, yIn: number, heightIn: number): Vector3
	return Vector3.new(Placement.toWorld(p, xIn, yIn, heightIn))
end

--- Physics coordinates (inches) on table `p` for a world position.
function TableBuilder.toTable(p: Placement, world: Vector3): (number, number)
	return Placement.toTable(p, world.X, world.Z)
end

--- World-space aim direction on table `p` for a physics aim angle.
function TableBuilder.aimDirection(p: Placement, angle: number): Vector3
	return Vector3.new(Placement.aimVector(p, angle))
end

--- The CFrame that turns table-space offsets into world ones (no translation): used for
--- rotating parts and angular velocity onto the table.
function TableBuilder.yawCFrame(p: Placement): CFrame
	return CFrame.Angles(0, p.yaw, 0)
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

--- Name of the cloth MaterialVariant to use, or "" for the plain built-in material.
---
--- Game scripts are not allowed to write material maps (plugin-only), so the variant must
--- already exist in MaterialService in the saved place. `TableBuilder.createClothMaterial()`
--- (re)creates it from the Config map ids when run from the Studio command bar or by the
--- assistant in Edit mode; save the place afterwards so it ships with the game.
function TableBuilder.ensureClothMaterial(): string
	local L = Config.Look
	if L.FeltMaterialVariant == "" then
		return ""
	end
	local existing = game:GetService("MaterialService"):FindFirstChild(L.FeltMaterialVariant)
	if existing and existing:IsA("MaterialVariant") then
		return existing.Name
	end
	-- Not in the place: try to make it (works in Edit mode / plugins only).
	local ok = pcall(TableBuilder.createClothMaterial)
	if ok then
		return L.FeltMaterialVariant
	end
	warn(
		"[8ball] cloth MaterialVariant '"
			.. L.FeltMaterialVariant
			.. "' is missing from MaterialService; using plain "
			.. L.FeltMaterial
	)
	return ""
end

--- Create or refresh the cloth MaterialVariant from Config. Edit mode / plugin context only.
function TableBuilder.createClothMaterial(): MaterialVariant
	local L = Config.Look
	local MaterialService = game:GetService("MaterialService")
	local existing = MaterialService:FindFirstChild(L.FeltMaterialVariant)
	local variant: MaterialVariant
	if existing and existing:IsA("MaterialVariant") then
		variant = existing
	else
		variant = Instance.new("MaterialVariant")
		variant.Name = L.FeltMaterialVariant
		variant.BaseMaterial = material(L.FeltMaterial)
	end
	variant.ColorMap = L.FeltMaps.Color
	variant.NormalMap = L.FeltMaps.Normal
	variant.RoughnessMap = L.FeltMaps.Roughness
	variant.MetalnessMap = L.FeltMaps.Metalness
	variant.StudsPerTile = L.FeltStudsPerTile
	variant.Parent = MaterialService
	return variant
end

--- The imported table model template, if the place has one.
function TableBuilder.findModelTemplate(): Model?
	local ServerStorage = game:GetService("ServerStorage")
	local found = ServerStorage:FindFirstChild(Config.TableModel.Name)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

--- Place a clone of the imported model at table `p` and set its collisions. Joining is the
--- floor pad's job now (src/server/TableService.luau), so no prompt is attached.
function TableBuilder.buildFromModel(
	template: Model,
	parent: Instance,
	p: Placement,
	id: number
): Model
	local model = template:Clone()
	model.Name = TableBuilder.modelName(id)
	model.Parent = parent
	-- The importer keeps the pivot at the scene origin, which the Blender package puts at
	-- the table centre on the floor, so moving the pivot moves the whole table correctly.
	for name, spec in Config.TableModel.Meshes do
		local mesh = model:FindFirstChild(name)
		if mesh and mesh:IsA("BasePart") then
			mesh.Anchored = true
			mesh.CanCollide = spec.CanCollide
			mesh.CanQuery = spec.CanCollide
		else
			warn("[8ball] table model is missing mesh '" .. name .. "'")
		end
	end
	-- The Blender package authors the table with its long axis along X; the lounge stands
	-- every table turned by its yaw, so the pivot carries the rotation too.
	model:PivotTo(CFrame.new(p.x, p.y, p.z) * TableBuilder.yawCFrame(p))
	return model
end

--- Edit-mode helper: put SurfaceAppearances with the Config texture ids on the template and
--- bake the collision shapes (both are plugin-only writes, so they live in the saved place).
function TableBuilder.applyModelTextures(template: Model): number
	local applied = 0
	for name, spec in Config.TableModel.Meshes do
		local mesh = template:FindFirstChild(name)
		if mesh and mesh:IsA("MeshPart") and spec.Collision then
			mesh.CollisionFidelity = (Enum.CollisionFidelity :: any)[spec.Collision]
		end
	end
	for name, maps in Config.TableModel.Textures do
		local mesh = template:FindFirstChild(name)
		if mesh and mesh:IsA("MeshPart") then
			local sa = mesh:FindFirstChildOfClass("SurfaceAppearance")
				or Instance.new("SurfaceAppearance")
			sa.ColorMap = maps.Color
			sa.NormalMap = maps.Normal
			sa.RoughnessMap = maps.Roughness
			sa.MetalnessMap = maps.Metalness
			sa.AlphaMode = Enum.AlphaMode.Overlay
			sa.Parent = mesh
			applied += 1
		end
	end
	return applied
end

--- Build the visible table for `id` at placement `p` under `parent`: the imported model when
--- the place has one, otherwise the parts-and-solid-modelling build. Returns the model.
function TableBuilder.build(parent: Instance, p: Placement, id: number): Model
	local template = TableBuilder.findModelTemplate()
	if template then
		return TableBuilder.buildFromModel(template, parent, p, id)
	end
	return TableBuilder.buildFromParts(parent, p, id)
end

--- Build the table from Parts and solid modelling (the pre-model fallback). Everything is
--- laid out around a zero origin with no yaw and the finished model is pivoted into place,
--- so the hundreds of offsets below stay readable.
function TableBuilder.buildFromParts(parent: Instance, p: Placement, id: number): Model
	local T = Config.Table
	local L = Config.Look
	local s = T.StudsPerInch
	local origin = Vector3.zero

	local model = Instance.new("Model")
	model.Name = TableBuilder.modelName(id)
	model.Parent = parent -- solid modelling below needs the parts to be in the world already
	local clothVariant = TableBuilder.ensureClothMaterial()

	local length = T.LengthInches
	local width = T.WidthInches
	local railW = T.RailWidthInches
	local railH = T.RailHeightInches
	local cushionW = T.CushionWidthInches
	local cushionH = T.CushionHeightInches
	local bed = T.BedThicknessInches
	local surfaceY = T.SurfaceHeightInches
	local apronH = 7

	-- Cloth bed: top face is the playing surface.
	local bedPart = makePart(
		"Bed",
		Vector3.new((length + 2 * cushionW) * s, bed * s, (width + 2 * cushionW) * s),
		origin + Vector3.new(0, (surfaceY - bed / 2) * s, 0),
		L.FeltColor,
		L.FeltMaterial,
		model
	)
	if clothVariant ~= "" then
		bedPart.MaterialVariant = clothVariant
	end

	-- Frame: four wooden boxes from below the bed up to the rail top. The pocket liners sit
	-- on top of the wood as matte dark discs, which reads as holes from the play views.
	local frameBottom = surfaceY - bed - apronH
	local frameTop = surfaceY + railH
	local frameH = frameTop - frameBottom
	local frameY = (frameBottom + frameH / 2) * s
	local ringW = railW - cushionW -- the frame starts where the cushion strip ends
	local outerL = length + 2 * railW
	local outerW = width + 2 * railW
	local geometry = TableGeometry.build({ pocketsOpen = true })
	for _, sz in { -1, 1 } do
		makePart(
			"FrameLong",
			Vector3.new(outerL * s, frameH * s, ringW * s),
			origin + Vector3.new(0, frameY, sz * (width / 2 + cushionW + ringW / 2) * s),
			L.RailColor,
			L.RailMaterial,
			model
		)
	end
	for _, sx in { -1, 1 } do
		makePart(
			"FrameShort",
			Vector3.new(ringW * s, frameH * s, (width + 2 * cushionW) * s),
			origin + Vector3.new(sx * (length / 2 + cushionW + ringW / 2) * s, frameY, 0),
			L.RailColor,
			L.RailMaterial,
			model
		)
	end
	-- Dark apron under the whole frame so nothing shows through from below.
	makePart(
		"Apron",
		Vector3.new(outerL * s, apronH * s, outerW * s),
		origin + Vector3.new(0, (frameBottom + apronH / 2) * s, 0),
		L.FrameColor,
		L.FrameMaterial,
		model
	)

	-- Cushions: one strip per physics segment (rails and the angled jaw facings). The inner
	-- face lies exactly on the segment line the balls bounce off; the strip is as tall as
	-- the wooden rail and tucks under it so cloth and wood meet flush.
	local cushionDepth = cushionW + T.CushionOverlapInches
	local cushionY = (surfaceY + cushionH / 2) * s
	for _, seg in geometry.segments do
		local dx, dy = seg.bx - seg.ax, seg.by - seg.ay
		local segLen = math.sqrt(dx * dx + dy * dy)
		local mx = (seg.ax + seg.bx) / 2 - seg.nx * cushionDepth / 2
		local my = (seg.ay + seg.by) / 2 - seg.ny * cushionDepth / 2
		local part = makePart(
			"Cushion_" .. seg.name,
			Vector3.new(segLen * s, cushionH * s, cushionDepth * s),
			origin + Vector3.new(mx * s, cushionY, -my * s),
			L.CushionColor,
			L.FeltMaterial,
			model
		)
		-- Physics y is world -Z, so a segment angle of a (physics) is a rotation of +a about Y.
		part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, math.atan2(dy, dx), 0)
		part.CanCollide = false
		if clothVariant ~= "" then
			part.MaterialVariant = clothVariant
		end
	end

	-- Pocket holes. Solid modelling cuts a cylinder through the cloth bed and the frame at
	-- each pocket so you look down into a dark shaft, like a real pocket. If the cut fails
	-- (solid modelling can refuse odd shapes), the dark discs are kept as a fallback.
	local holeR = {}
	local cutters: { BasePart } = {}
	local shaftTop = surfaceY + railH + 1
	local shaftBottom = surfaceY - L.PocketShaftDepthInches
	for _, pocket in geometry.pockets do
		local r = pocket.radius + L.PocketLinerExtraInches
		holeR[pocket.id] = r
		local cutter = Instance.new("Part")
		cutter.Name = "Cutter" .. pocket.id
		cutter.Shape = Enum.PartType.Cylinder
		cutter.Anchored = true
		cutter.CanCollide = false
		cutter.Size = Vector3.new((shaftTop - shaftBottom + 2) * s, r * 2 * s, r * 2 * s)
		cutter.CFrame = CFrame.new(
			origin + Vector3.new(pocket.x * s, ((shaftTop + shaftBottom) / 2) * s, -pocket.y * s)
		) * CFrame.Angles(0, 0, math.rad(90))
		cutter.Parent = model
		table.insert(cutters, cutter)
	end
	local function cutHoles(part: BasePart)
		local ok, result = pcall(function()
			return part:SubtractAsync(
				cutters,
				Enum.CollisionFidelity.Box,
				Enum.RenderFidelity.Precise
			)
		end)
		if ok and result then
			result.Name = part.Name
			result.Anchored = true
			result.CanCollide = part.CanCollide
			result.UsePartColor = true
			result.Color = part.Color
			result.Material = part.Material
			if part:IsA("Part") and part.MaterialVariant ~= "" then
				result.MaterialVariant = part.MaterialVariant
			end
			result.Parent = model
			part:Destroy()
			return true
		end
		warn("[8ball] pocket cut failed on " .. part.Name .. ": " .. tostring(result))
		return false
	end
	local cutOk = true
	for _, name in { "Bed", "FrameLong", "FrameShort" } do
		for _, part in model:GetChildren() do
			if part.Name == name and part:IsA("Part") then
				cutOk = cutHoles(part) and cutOk
			end
		end
	end
	for _, cutter in cutters do
		cutter:Destroy()
	end

	-- Pocket castings. On a real table a leather U sits on the rail around the outer half
	-- of each hole (open towards the cloth) and lines the hole wall down to the cloth, so
	-- the ball never drops past bare wood. Built with solid modelling: an annulus minus a
	-- box over the inner half. Falls back to nothing if a cut is refused.
	local function subtract(part: BasePart, cutterParts: { BasePart }): BasePart?
		local ok, result = pcall(function()
			return part:SubtractAsync(
				cutterParts,
				Enum.CollisionFidelity.Box,
				Enum.RenderFidelity.Precise
			)
		end)
		for _, cutter in cutterParts do
			cutter:Destroy()
		end
		if ok and result then
			result.Name = part.Name
			result.Anchored = true
			result.CanCollide = false
			result.UsePartColor = true
			result.Color = part.Color
			result.Material = part.Material
			result.Parent = model
			part:Destroy()
			return result
		end
		part:Destroy()
		return nil
	end
	local function verticalCylinder(
		name: string,
		x: number,
		y: number,
		top: number,
		bottom: number,
		radius: number
	): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Shape = Enum.PartType.Cylinder
		part.Anchored = true
		part.CanCollide = false
		part.CastShadow = false
		part.Material = material(L.PocketMaterial)
		part.Color = color(L.PocketColor)
		part.Size = Vector3.new((top - bottom) * s, radius * 2 * s, radius * 2 * s)
		part.CFrame = CFrame.new(origin + Vector3.new(x * s, ((top + bottom) / 2) * s, -y * s))
			* CFrame.Angles(0, 0, math.rad(90))
		part.Parent = model
		return part
	end
	-- Box covering the half-space on the table side of the pocket (used to open the U).
	local function innerHalfBox(pocket, top: number, bottom: number): Part
		local ix, iy = -pocket.x, -pocket.y -- towards the table centre
		local len = math.sqrt(ix * ix + iy * iy)
		ix, iy = ix / len, iy / len
		local box = Instance.new("Part")
		box.Anchored = true
		box.CanCollide = false
		local depth = 40
		box.Size = Vector3.new(depth * s, (top - bottom + 2) * s, depth * s)
		local cx, cy = pocket.x + ix * depth / 2, pocket.y + iy * depth / 2
		-- Physics y is world -Z; a direction angle a in physics is +a about Y in world.
		box.CFrame = CFrame.new(origin + Vector3.new(cx * s, ((top + bottom) / 2) * s, -cy * s))
			* CFrame.Angles(0, math.atan2(iy, ix), 0)
		box.Parent = model
		return box
	end
	if cutOk then
		for _, pocket in geometry.pockets do
			local r = holeR[pocket.id]
			-- Leather U on the rail top around the outer half of the hole.
			local ringTop = frameTop + L.PocketRingHeightInches
			local ring = verticalCylinder(
				"PocketRing" .. pocket.id,
				pocket.x,
				pocket.y,
				ringTop,
				frameTop - 0.02,
				r + L.PocketRingWidthInches
			)
			subtract(ring, {
				verticalCylinder("Cut", pocket.x, pocket.y, ringTop + 1, frameTop - 1, r),
				innerHalfBox(pocket, ringTop, frameTop),
			})
			-- Leather lining of the outer hole wall, from just under the cloth up to the rail.
			local wallTop = frameTop + 0.01
			local wallBottom = surfaceY - 0.3
			local wall = verticalCylinder(
				"PocketWall" .. pocket.id,
				pocket.x,
				pocket.y,
				wallTop,
				wallBottom,
				r + 0.02
			)
			subtract(wall, {
				verticalCylinder(
					"Cut",
					pocket.x,
					pocket.y,
					wallTop + 1,
					wallBottom - 1,
					r - L.PocketWallThicknessInches
				),
				innerHalfBox(pocket, wallTop, wallBottom),
			})
			-- Full leather tube for the throat below the cloth, down to the shaft floor, so no
			-- bare wood shows inside the drop.
			local throatTop = wallBottom + 0.05
			local throatBottom = shaftBottom + 0.4
			local throat = verticalCylinder(
				"PocketThroat" .. pocket.id,
				pocket.x,
				pocket.y,
				throatTop,
				throatBottom,
				r + 0.02
			)
			subtract(throat, {
				verticalCylinder(
					"Cut",
					pocket.x,
					pocket.y,
					throatTop + 1,
					throatBottom - 1,
					r - L.PocketWallThicknessInches
				),
			})
		end
	end

	-- Shaft: a matte near-black cylinder well below the cloth so the hole reads as depth.
	for _, pocket in geometry.pockets do
		local r = holeR[pocket.id] - 0.05
		local top = if cutOk then shaftBottom + 0.5 else surfaceY + railH + 0.02
		local bottom = shaftBottom
		local shaft = verticalCylinder("Pocket" .. pocket.id, pocket.x, pocket.y, top, bottom, r)
		shaft.Material = material(L.ShaftMaterial)
		shaft.Color = color(L.ShaftColor)
	end

	-- Legs.
	local legH = frameBottom
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

	-- Everything above was built around zero; put the finished table where it belongs.
	model:PivotTo(CFrame.new(p.x, p.y, p.z) * TableBuilder.yawCFrame(p))
	return model
end

return TableBuilder
