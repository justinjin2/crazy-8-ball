--!strict
-- MapBuilder: builds and prepares the rooftop hub map in Edit mode (the brief is
-- docs/prompts/ROOFTOP_MAP_PROMPT.md, the spec assets/map/Spec.md). Nothing in the running
-- game requires it: it is run from the command bar or the MCP execute_luau tool, like
-- TableBuilder.prepareImport, and what it builds is saved in the place. Every function is safe
-- to run twice. Every step in assets/map/Readme.md.
--
-- Stage 1 builds a gray-box from data that assets/map/gen_graybox.py writes to
-- src/server/MapData/GrayBox.json (Rojo syncs it to ServerScriptService.Server.MapData):
--
--   local Server = game.ServerScriptService.Server
--   print(require(game.ReplicatedStorage.Shared.MapBuilder:Clone()).buildGrayBox(
--       require(Server.MapData.GrayBox:Clone())))
--
-- The :Clone() calls read what is on disk now: Edit-mode requires are cached (STUDIO_NOTES).
--
-- Stage 2 imports the architecture (assets/map/fbx/Rooftop.fbx) and prepares it; Stage 3 the
-- props (assets/map/fbx/Props.fbx):
--
--   local Server, Shared = game.ServerScriptService.Server, game.ReplicatedStorage.Shared
--   local MB, spec = require(Shared.MapBuilder:Clone()), require(Shared.Config:Clone()).Map
--   local data = require(Server.MapData.GrayBox:Clone())
--   print(MB.prepareImport(spec, data))
--   print(MB.prepareProps(spec, data))

local MapBuilder = {}

--- Each gray-box part carries its row's group ("arch", "props", "near" or "mid") and role ("floor",
--- "collide" or "visual") as attributes (gen_graybox.py). Once a group's meshes are imported,
--- its visual parts go, its floor and collide parts become the tiled floor and invisible
--- walls in Map.Collision, and the rest of the gray-box stays.
MapBuilder.GroupAttribute = "MapGroup"
MapBuilder.RoleAttribute = "MapRole"

--- The model in Workspace that holds the whole map.
MapBuilder.MapName = "Map"
--- The gray-box's model inside it, replaced stage by stage by the Blender meshes.
MapBuilder.GrayBoxName = "GrayBox"

local function sortedKeys(t: { [string]: any }): { string }
	local keys = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function mapModel(): Model
	local map = workspace:FindFirstChild(MapBuilder.MapName)
	if map and map:IsA("Model") then
		return map
	end
	local made = Instance.new("Model")
	made.Name = MapBuilder.MapName
	made.Parent = workspace
	return made
end

-- Which groups already have their real meshes in the map.
local function importedGroups(map: Model, spec: any?): { [string]: boolean }
	if spec == nil then
		return {}
	end
	local placed = map:FindFirstChild(spec.Props.Placed)
	return {
		arch = map:FindFirstChild(spec.Architecture) ~= nil,
		props = placed ~= nil and #placed:GetChildren() > 0,
		near = spec.Near ~= nil and map:FindFirstChild(spec.Near.Import) ~= nil,
		mid = spec.Backdrop ~= nil and map:FindFirstChild(spec.Backdrop.Import) ~= nil,
	}
end

-- The sea: Terrain water in data.water's rectangles, data.water.depth deep under its surface.
-- The map's only Terrain is this sea, so it is cleared and refilled.
local function fillWater(data: any)
	local w = data.water
	local terrain = workspace.Terrain
	terrain:Clear()
	for _, r in w.fills do
		terrain:FillBlock(
			CFrame.new((r[1] + r[3]) / 2, w.seaY - w.depth / 2, (r[2] + r[4]) / 2),
			Vector3.new(r[3] - r[1], w.depth, r[4] - r[2]),
			Enum.Material.Water
		)
	end
end

-- Remove the gray-box parts of one group (its real meshes are in). Returns how many.
local function removeGrayBox(map: Model, groupName: string): number
	local removed = 0
	local box = map:FindFirstChild(MapBuilder.GrayBoxName)
	if box then
		for _, d in box:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute(MapBuilder.GroupAttribute) == groupName then
				d:Destroy()
				removed += 1
			end
		end
	end
	return removed
end

-- A gray-box row's CFrame: world, or in its prop's own frame, plus an extra turn.
local function rowCFrame(r: any): CFrame
	local cf: CFrame
	local frame = r["local"]
	if frame then
		cf = CFrame.new(frame[1], frame[2], frame[3])
			* CFrame.Angles(0, math.rad(frame[4]), 0)
			* CFrame.new(r.p[1], r.p[2], r.p[3])
	else
		cf = CFrame.new(r.p[1], r.p[2], r.p[3]) * CFrame.Angles(0, math.rad(r.yaw), 0)
	end
	if r.rot then
		cf = cf * CFrame.Angles(math.rad(r.rot[1]), math.rad(r.rot[2]), math.rad(r.rot[3]))
	end
	return cf
end

--- Builds Workspace.Map.GrayBox from gen_graybox.py's data: one Part per row, grouped into
--- models by the row's folder (Rooftop, Props, Near, Backdrop); clears Terrain and fills the
--- sea with water; removes Workspace.Baseplate and makes the SpawnLocation the entrance mat.
--- With `spec` (Config.Map), the rows of a group whose meshes are already imported are left
--- out. Returns a one-line report.
function MapBuilder.buildGrayBox(data: any, spec: any?): string
	local map = mapModel()
	local imported = importedGroups(map, spec)
	local old = map:FindFirstChild(MapBuilder.GrayBoxName)
	if old then
		old:Destroy()
	end
	local box = Instance.new("Model")
	box.Name = MapBuilder.GrayBoxName
	local groups: { [string]: Model } = {}
	local function group(name: string): Model
		local found = groups[name]
		if found then
			return found
		end
		local made = Instance.new("Model")
		made.Name = name
		made.Parent = box
		groups[name] = made
		return made
	end

	local count = 0
	for _, r in data.rows do
		if r.g and imported[r.g] then
			continue
		end
		local part = Instance.new("Part")
		part.Name = r.n
		part.Shape = (Enum.PartType :: any)[r.s]
		part.Anchored = true
		part.CanCollide = r.k
		part.CanQuery = r.k
		part.CanTouch = false
		part.CastShadow = not r.ns and r.t < 0.5 and r.m ~= "Neon"
		part.Material = (Enum.Material :: any)[r.m]
		part.Transparency = r.t
		part.Color = Color3.fromHex(r.c)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(r.size[1], r.size[2], r.size[3])
		part.CFrame = rowCFrame(r)
		if r.g then
			part:SetAttribute(MapBuilder.GroupAttribute, r.g)
			part:SetAttribute(MapBuilder.RoleAttribute, r.role)
		end
		part.Parent = group(r.f)
		count += 1
	end
	-- The far world must never stream out (StreamingEnabled): the backdrop is kilometres off,
	-- well past the streaming radius.
	for _, name in { "Near", "Backdrop" } do
		local model = box:FindFirstChild(name)
		if model and model:IsA("Model") then
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end
	end
	box.Parent = map

	fillWater(data)

	local base = workspace:FindFirstChild("Baseplate")
	if base then
		base:Destroy()
	end
	-- The spawn is the art's entrance mat: a thin dark slab on the floor, no decal.
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then
		spawn.Size = Vector3.new(data.spawnSize[1], data.spawnSize[2], data.spawnSize[3])
		spawn.CFrame = CFrame.new(data.spawn[1], data.spawn[2], data.spawn[3])
		spawn.Color = Color3.fromHex(data.spawnColour)
		spawn.Material = Enum.Material.SmoothPlastic
		spawn.TopSurface = Enum.SurfaceType.Smooth
		for _, child in spawn:GetChildren() do
			if child:IsA("Decal") then
				child:Destroy()
			end
		end
	end
	return ("GrayBox: %d parts"):format(count)
end

-- Triangles in a mesh, read through an EditableMesh (Edit mode, the user's own meshes).
local function triangleCount(mesh: MeshPart): number?
	local ok, result = pcall(function()
		local editable = game:GetService("AssetService"):CreateEditableMeshAsync(mesh.MeshContent)
		local count = #editable:GetFaces()
		editable:Destroy()
		return count
	end)
	return if ok then result else nil
end

-- Find a fresh import (in Workspace) or the one kept from an earlier run (`keptIn`), flatten
-- it, and put it back where Blender built it from its three anchor cubes (then delete them).
-- Returns the model, or nil when there is neither.
local function takeImport(name: string, keptIn: Instance, anchors: any, say: (string) -> ()): Model?
	local fresh = workspace:FindFirstChild(name)
	local previous = keptIn:FindFirstChild(name)
	if fresh and fresh:IsA("Model") and previous and previous ~= fresh then
		previous:Destroy()
		say(("Replaced the previous %s import."):format(name))
	end
	local found = if fresh and fresh:IsA("Model") then fresh else previous
	if not (found and found:IsA("Model")) then
		return nil
	end
	local model: Model = found
	for _, d in model:GetDescendants() do
		if d:IsA("MeshPart") and d.Parent ~= model then
			d.Parent = model
		end
	end
	for _, child in model:GetChildren() do
		if not child:IsA("BasePart") then
			child:Destroy()
		end
	end
	local A = anchors
	local o, x, z = model:FindFirstChild(A.O), model:FindFirstChild(A.X), model:FindFirstChild(A.Z)
	if o and x and z then
		local po = (o :: BasePart).Position
		local vx, vz = (x :: BasePart).Position - po, (z :: BasePart).Position - po
		local scale = (vx.Magnitude + vz.Magnitude) / (2 * A.Spacing)
		if math.abs(scale - 1) > 0.01 then
			say(
				("PROBLEM: %s's anchors are %.3f times as far apart as they should be: re-import with Scale Unit: Stud and scale 1."):format(
					name,
					scale
				)
			)
		end
		local ax, az = vx.Unit, vz.Unit
		local current = CFrame.fromMatrix(po, ax, az:Cross(ax), az)
		local fix = current:Inverse()
		for _, part in model:GetChildren() do
			if part:IsA("BasePart") then
				part.CFrame = fix * part.CFrame
			end
		end
		say(
			("%s placed by its anchors: moved %.2f studs, turned %.1f degrees."):format(
				name,
				po.Magnitude,
				math.deg(math.atan2(-ax.Z, ax.X))
			)
		)
		o:Destroy()
		x:Destroy()
		z:Destroy()
	end
	model.WorldPivot = CFrame.identity
	model.Name = name
	model.Parent = keptIn
	return model
end

-- Set a mesh up as a visual only (anchored, never colliding, automatic LOD), dressed in a map
-- set's SurfaceAppearance or a flat colour. Returns false when its images are not uploaded yet.
local function dress(
	part: MeshPart,
	spec: any,
	mapsName: string?,
	alphaMode: string?,
	colour: string?,
	castShadow: boolean,
	say: (string) -> ()
): boolean
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = castShadow
	part.RenderFidelity = Enum.RenderFidelity.Automatic
	part.CollisionFidelity = Enum.CollisionFidelity.Box
	part.TextureID = ""
	for _, old in part:GetChildren() do
		if old:IsA("SurfaceAppearance") then
			old:Destroy()
		end
	end
	part.Material = Enum.Material.SmoothPlastic
	if mapsName then
		local maps = spec.Maps[mapsName]
		if maps == nil then
			say(
				("PROBLEM: %s names the map set %s, which Config.Map.Maps does not have."):format(
					part.Name,
					mapsName
				)
			)
			return false
		elseif maps.Color == "" then
			if alphaMode then
				part.Transparency = 1 -- bare, an overlay would draw as a solid grey sheet
			end
			return false
		end
		local sa = Instance.new("SurfaceAppearance")
		sa.ColorMap = maps.Color
		if maps.Normal and maps.Normal ~= "" then
			sa.NormalMap = maps.Normal
		end
		if maps.Roughness and maps.Roughness ~= "" then
			sa.RoughnessMap = maps.Roughness
		end
		sa.AlphaMode = (Enum.AlphaMode :: any)[alphaMode or "Overlay"]
		sa.Parent = part
	elseif colour then
		part.Color = Color3.fromHex(colour)
	end
	return true
end

-- Map.Collision.<Group> from the gray-box data's floor and collide rows of one group (the
-- floor tiled and visible, the rest invisible), and the gray-box parts of that group removed.
-- Returns a report line.
local function buildCollision(map: Model, spec: any, data: any, groupName: string): string
	local existing = map:FindFirstChild(spec.CollisionName)
	local collision: Instance
	if existing and existing:IsA("Model") then
		collision = existing
	else
		if existing then
			existing:Destroy()
		end
		local made = Instance.new("Model")
		made.Name = spec.CollisionName
		made.Parent = map
		collision = made
	end
	-- Before Stage 3 the collision parts sat straight in the model: clear those.
	for _, child in collision:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end
	local folderName = groupName:sub(1, 1):upper() .. groupName:sub(2)
	local old = collision:FindFirstChild(folderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Model")
	folder.Name = folderName
	local F = spec.Floor
	local floors, walls = 0, 0
	for _, r in data.rows do
		if r.g ~= groupName or (r.role ~= "floor" and r.role ~= "collide") then
			continue
		end
		local part = Instance.new("Part")
		part.Name = r.n
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CastShadow = false
		part.Shape = (Enum.PartType :: any)[r.s]
		part.Size = Vector3.new(r.size[1], r.size[2], r.size[3])
		part.CFrame = rowCFrame(r)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if r.role == "floor" then
			part.Material = (Enum.Material :: any)[F.BaseMaterial]
			part.MaterialVariant = F.Variant
			part.Color = Color3.fromHex(F.Tint)
			part.CanQuery = true
			floors += 1
		else
			part.Transparency = 1
			-- Tall invisible walls stay out of raycasts (the camera); steps stay in.
			part.CanQuery = not (r.n:find("SafetyWall") or r.n:find("Glass"))
			walls += 1
		end
		part.Parent = folder
	end
	folder.Parent = collision
	local removed = removeGrayBox(map, groupName)
	return ("Collision.%s: %d floor parts, %d invisible parts; removed %d gray-box parts."):format(
		folderName,
		floors,
		walls,
		removed
	)
end

--- Edit mode only (MeshPart and MaterialVariant maps are plugin-only writes): turn a fresh
--- import of the architecture (Config.Map.Architecture) into the map. Safe to run twice.
---  1. Takes the imported model (Workspace, or the map's from an earlier run), flattens it
---     and places it by its anchor cubes.
---  2. Sets up each mesh (Config.Map.Meshes): anchored, never colliding, shadows, automatic
---     LOD, a SurfaceAppearance from Maps or a flat colour.
---  3. Makes the floor's MaterialVariant (Config.Map.Floor).
---  4. Builds Map.Collision.Arch from the gray-box data and removes the gray-box parts of the
---     architecture.
---  5. Counts triangles against Config.Map.TriangleCaps.
--- Returns a report; anything wrong is a line starting "PROBLEM:".
function MapBuilder.prepareImport(spec: any, data: any): string
	if game:GetService("RunService"):IsRunning() then
		error("MapBuilder.prepareImport runs in Edit mode only; stop the play session first")
	end
	local lines: { string } = {}
	local function say(line: string)
		table.insert(lines, line)
	end
	local map = mapModel()
	local model = takeImport(spec.Architecture, map, spec.Anchors, say)
	if model == nil then
		return ("No Model named %s in Workspace. Import assets/map/fbx/Rooftop.fbx with the 3D Importer (assets/map/Readme.md) and run this again."):format(
			spec.Architecture
		)
	end
	assert(model, "the architecture model")

	for _, child in model:GetChildren() do
		if child:IsA("MeshPart") and spec.Meshes[child.Name] == nil then
			say(("PROBLEM: %s is not in Config.Map.Meshes."):format(child.Name))
		end
	end
	local total = 0
	local counted = true
	for _, name in sortedKeys(spec.Meshes) do
		local ms = spec.Meshes[name]
		local part = model:FindFirstChild(name)
		if not (part and part:IsA("MeshPart")) then
			say(("PROBLEM: the model has no mesh %s."):format(name))
			continue
		end
		part.Transparency = ms.Transparency or 0
		if not dress(part, spec, ms.Maps, ms.AlphaMode, ms.Color, ms.CastShadow, say) then
			say(("%s: no image uploaded yet for %s."):format(name, tostring(ms.Maps)))
		end
		local tris = triangleCount(part)
		if tris then
			total += tris
		else
			counted = false
		end
	end
	local cap = spec.TriangleCaps[spec.Architecture]
	if counted then
		say(("%d triangles (cap %d)."):format(total, cap))
		if total > cap then
			say(("PROBLEM: %d triangles is over the cap of %d."):format(total, cap))
		end
	else
		say("Could not read every mesh's triangles (EditableMesh).")
	end

	-- The floor's MaterialVariant.
	local F = spec.Floor
	local MaterialService = game:GetService("MaterialService")
	local oldVariant = MaterialService:FindFirstChild(F.Variant)
	if oldVariant then
		oldVariant:Destroy()
	end
	local variant = Instance.new("MaterialVariant")
	variant.Name = F.Variant
	variant.BaseMaterial = (Enum.Material :: any)[F.BaseMaterial]
	variant.StudsPerTile = F.StudsPerTile
	variant.MaterialPattern = Enum.MaterialPattern.Regular
	if F.Color ~= "" then
		variant.ColorMap = F.Color
	else
		say("Floor: no colour map uploaded yet.")
	end
	if F.Normal ~= "" then
		variant.NormalMap = F.Normal
	end
	variant.Parent = MaterialService

	say(buildCollision(map, spec, data, "arch"))
	return table.concat(lines, "\n")
end

--- Edit mode only: turn a fresh import of the props (Config.Map.Props.Import) into templates
--- and place them. Safe to run twice.
---  1. Takes the imported model (Workspace, or ServerStorage's templates from an earlier run),
---     flattens it, places it by its anchors and keeps it as ServerStorage.<Templates>.
---  2. Dresses each template mesh by its group (<Kind>__Opaque, __Foliage, __Glow) and kind.
---  3. Rebuilds Map.<Placed>: one model per placement in the gray-box data, each a clone of
---     its kind's meshes turned and scaled into place.
---  4. Rebuilds Map.<Seats> (invisible Seat parts) and the PointLights.
---  5. Builds Map.Collision.Props from the gray-box data and removes the gray-box props.
---  6. Checks triangles, MeshParts and lights against their budgets.
--- Returns a report; anything wrong is a line starting "PROBLEM:".
function MapBuilder.prepareProps(spec: any, data: any): string
	if game:GetService("RunService"):IsRunning() then
		error("MapBuilder.prepareProps runs in Edit mode only; stop the play session first")
	end
	local lines: { string } = {}
	local function say(line: string)
		table.insert(lines, line)
	end
	local P = spec.Props
	local map = mapModel()
	local ServerStorage = game:GetService("ServerStorage")
	-- The templates live in ServerStorage under the Templates name; a fresh import is renamed.
	local fresh = workspace:FindFirstChild(P.Import)
	if fresh and fresh:IsA("Model") then
		fresh.Name = P.Templates
		fresh.Parent = workspace
	end
	local templates = takeImport(P.Templates, ServerStorage, spec.Anchors, say)
	if templates == nil then
		return ("No Model named %s in Workspace. Import assets/map/fbx/Props.fbx with the 3D Importer (assets/map/Readme.md) and run this again."):format(
			P.Import
		)
	end
	assert(templates, "the props templates")

	-- 2. The template meshes, by kind.
	local byKind: { [string]: { MeshPart } } = {}
	local trisByKind: { [string]: number } = {}
	local counted = true
	local bare = 0
	for _, part in templates:GetChildren() do
		if not part:IsA("MeshPart") then
			continue
		end
		local kind, groupName = part.Name:match("^(.-)__(.+)$")
		local ks = kind and P.Kinds[kind]
		local gs = groupName and P.Groups[groupName]
		if not (kind and ks and gs) then
			say(("PROBLEM: %s is not a <Kind>__<Group> in Config.Map.Props."):format(part.Name))
			continue
		end
		local shadow = ks.CastShadow and groupName == "Opaque"
		part.Transparency = 0
		if not dress(part, spec, gs.Maps, gs.AlphaMode, ks.Glow, shadow, say) then
			bare += 1
		end
		if gs.Material then
			part.Material = (Enum.Material :: any)[gs.Material]
		end
		byKind[kind] = byKind[kind] or {}
		table.insert(byKind[kind], part)
		local tris = triangleCount(part)
		if tris then
			trisByKind[kind] = (trisByKind[kind] or 0) + tris
		else
			counted = false
		end
	end
	if bare > 0 then
		say(
			("%d template meshes have no images uploaded yet (Config.Map.Maps.Props, Plants)."):format(
				bare
			)
		)
	end

	-- 3. Place: a clone of the kind's meshes at every placement.
	local oldPlaced = map:FindFirstChild(P.Placed)
	if oldPlaced then
		oldPlaced:Destroy()
	end
	local placed = Instance.new("Model")
	placed.Name = P.Placed
	local meshParts, total = 0, 0
	local counts: { [string]: number } = {}
	for i, p in data.placements do
		local parts = byKind[p.kind]
		if not parts then
			say(("PROBLEM: no template for %s (placement %d)."):format(p.kind, i))
			continue
		end
		local at = CFrame.new(p.cf[1], p.cf[2], p.cf[3]) * CFrame.Angles(0, math.rad(p.cf[4]), 0)
		local s = p.scale or 1
		local model = Instance.new("Model")
		model.Name = ("%s_%02d"):format(p.kind, i)
		for _, t in parts do
			local clone = t:Clone()
			clone.Size = t.Size * s
			clone.CFrame = at * CFrame.new(t.Position * s) * t.CFrame.Rotation
			clone.Parent = model
			meshParts += 1
		end
		model.Parent = placed
		counts[p.kind] = (counts[p.kind] or 0) + 1
		total += trisByKind[p.kind] or 0
	end
	placed.Parent = map

	-- 4. Seats and lights.
	local oldSeats = map:FindFirstChild(P.Seats)
	if oldSeats then
		oldSeats:Destroy()
	end
	local seats = Instance.new("Folder")
	seats.Name = P.Seats
	for i, seat in data.seats do
		local part = Instance.new("Seat")
		part.Name = ("Seat_%02d"):format(i)
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = true
		part.CanQuery = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = Vector3.new(P.SeatSize[1], P.SeatSize[2], P.SeatSize[3])
		-- A seated character faces the seat's LookVector (-Z), so turn it half round from yaw.
		part.CFrame = CFrame.new(seat.p[1], seat.p[2] + P.SeatSize[2] / 2, seat.p[3])
			* CFrame.Angles(0, math.rad(seat.yaw + 180), 0)
		part.Parent = seats
	end
	seats.Parent = map
	local L = P.Light
	for i, light in data.lights do
		local holder = Instance.new("Part")
		holder.Name = ("Light_%02d"):format(i)
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanTouch = false
		holder.CanQuery = false
		holder.CastShadow = false
		holder.Transparency = 1
		holder.Size = Vector3.new(0.2, 0.2, 0.2)
		holder.CFrame = CFrame.new(light.p[1], light.p[2], light.p[3])
		local point = Instance.new("PointLight")
		point.Range = L.Range
		point.Brightness = L.Brightness
		point.Color = Color3.fromHex(L.Color)
		point.Shadows = false
		point.Parent = holder
		holder.Parent = placed
	end

	-- 5. Collision.
	say(buildCollision(map, spec, data, "props"))

	-- 6. Budgets.
	local kinds = sortedKeys(counts)
	local parts = {}
	for _, kind in kinds do
		table.insert(parts, ("%s %d"):format(kind, counts[kind]))
	end
	say(("Placed %d props (%s)."):format(#data.placements, table.concat(parts, ", ")))
	local cap = spec.TriangleCaps.Props
	if counted then
		say(("%d triangles over every placement (cap %d)."):format(total, cap))
		if total > cap then
			say(("PROBLEM: %d triangles is over the cap of %d."):format(total, cap))
		end
	else
		say("Could not read every template's triangles (EditableMesh).")
	end
	local rooftop = map:FindFirstChild(spec.Architecture)
	local archParts = if rooftop then #rooftop:GetChildren() else 0
	say(
		("%d MeshParts with the architecture's %d (budget %d); %d seats; %d lights."):format(
			meshParts,
			archParts,
			spec.MeshPartBudget,
			#data.seats,
			#data.lights
		)
	)
	if meshParts + archParts > spec.MeshPartBudget then
		say(
			("PROBLEM: %d MeshParts is over the budget of %d."):format(
				meshParts + archParts,
				spec.MeshPartBudget
			)
		)
	end
	if #data.lights > spec.LightBudget then
		say(("PROBLEM: %d lights is over the budget of %d."):format(#data.lights, spec.LightBudget))
	end
	return table.concat(lines, "\n")
end

-- Dress every MeshPart of an imported model from its Config row (rowFor(name) -> row or nil):
-- anchored, never colliding, the row's map set and alpha, shadows only where CastShadow,
-- RenderFidelity Performance (or the row's Fidelity). `expected` lists rows that must each
-- have a mesh of that exact name (nil when rows match many meshes by prefix). Returns the
-- triangles, whether every mesh could be counted, and the MeshParts dressed.
local function dressRows(
	spec: any,
	model: Model,
	rowFor: (string) -> any,
	expected: { string }?,
	what: string,
	say: (string) -> ()
): (number, boolean, number)
	local total, counted, parts = 0, true, 0
	for _, child in model:GetChildren() do
		if not child:IsA("MeshPart") then
			continue
		end
		local row = rowFor(child.Name)
		if row == nil then
			say(("PROBLEM: %s has no row in Config.Map.%s."):format(child.Name, what))
			continue
		end
		if not dress(child, spec, row.Maps, row.AlphaMode, nil, row.CastShadow == true, say) then
			say(("%s: no image uploaded yet for %s."):format(child.Name, row.Maps))
		end
		child.RenderFidelity = (Enum.RenderFidelity :: any)[row.Fidelity or "Performance"]
		parts += 1
		local tris = triangleCount(child)
		if tris then
			total += tris
		else
			counted = false
		end
	end
	local names: { string } = expected or {}
	for _, name in names do
		local part = model:FindFirstChild(name)
		if not (part and part:IsA("MeshPart")) then
			say(("PROBLEM: the %s has no mesh %s."):format(what, name))
		end
	end
	return total, counted, parts
end

-- The triangle report for one group against its cap.
local function triangleReport(
	total: number,
	counted: boolean,
	cap: number,
	what: string,
	say: (string) -> ()
)
	if counted then
		say(("%d triangles in the %s (cap %d)."):format(total, what, cap))
		if total > cap then
			say(("PROBLEM: %d triangles is over the cap of %d."):format(total, cap))
		end
	else
		say("Could not read every mesh's triangles (EditableMesh).")
	end
end

-- The backdrop's MeshParts (the near world's and the mid backdrop's together) against their
-- budget (the brief: about 30).
local function backdropBudget(map: Model, spec: any, say: (string) -> ())
	local count = 0
	for _, name in { spec.Near.Import, spec.Backdrop.Import } do
		local model = map:FindFirstChild(name)
		if model then
			for _, d in model:GetDescendants() do
				if d:IsA("MeshPart") then
					count += 1
				end
			end
		end
	end
	say(
		("%d MeshParts in the near world and the backdrop (budget %d)."):format(
			count,
			spec.BackdropMeshPartBudget
		)
	)
	if count > spec.BackdropMeshPartBudget then
		say(
			("PROBLEM: %d MeshParts is over the backdrop budget of %d."):format(
				count,
				spec.BackdropMeshPartBudget
			)
		)
	end
end

--- Edit mode only: turn a fresh import of the near world (Config.Map.Near, fbx/Near.fbx) into
--- the map. Safe to run twice.
---  1. Takes the imported model (Workspace, or the map's own from an earlier run), flattens it
---     and places it by its anchor cubes, as Map.<Import>.
---  2. Dresses each mesh (Config.Map.Near.Meshes): anchored, never colliding, no shadows (or
---     the row's CastShadow), RenderFidelity Performance (or the row's Fidelity), its map set.
---  3. Keeps the Boat mesh as the template in ServerStorage.<Templates> and clones it once per
---     path into Map.<Import>.<Folder>, each with its BoatIndex and BoatOffset attributes (the
---     client drifts them: MapAmbience), at its pose at time 0 when `motion` (MapMotion) is
---     given, else at its path's centre.
---  4. Removes the gray-box's near rows, refills the water, and makes the model Persistent.
---  5. Counts triangles against TriangleCaps.Near and MeshParts against the backdrop budget.
--- Returns a report; anything wrong is a line starting "PROBLEM:".
function MapBuilder.prepareNear(spec: any, data: any, motion: any?): string
	if game:GetService("RunService"):IsRunning() then
		error("MapBuilder.prepareNear runs in Edit mode only; stop the play session first")
	end
	local lines: { string } = {}
	local function say(line: string)
		table.insert(lines, line)
	end
	local map = mapModel()
	local N = spec.Near
	-- The previous run's boats go first: takeImport flattens a model's MeshParts, which would
	-- pull them out of their folder as strays.
	local previous = map:FindFirstChild(N.Import)
	if previous then
		for _, d in previous:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("BoatIndex") ~= nil then
				d:Destroy()
			end
		end
	end
	local model = takeImport(N.Import, map, spec.Anchors, say)
	if model == nil then
		return ("No Model named %s in Workspace. Import assets/map/fbx/Near.fbx with the 3D Importer (assets/map/Readme.md) and run this again."):format(
			N.Import
		)
	end
	assert(model, "the near world's model")

	-- The boat template, kept out of the world.
	local B = N.Boat
	local store = game:GetService("ServerStorage")
	local templates = store:FindFirstChild(B.Templates)
	if not templates then
		local made = Instance.new("Folder")
		made.Name = B.Templates
		made.Parent = store
		templates = made
	end
	assert(templates, "the templates folder")
	local fresh = model:FindFirstChild(B.Mesh)
	if fresh and fresh:IsA("MeshPart") then
		local old = templates:FindFirstChild(B.Mesh)
		if old and old ~= fresh then
			old:Destroy()
		end
		fresh.Parent = templates
	end
	local template = templates:FindFirstChild(B.Mesh)

	-- The meshes.
	local total, counted = dressRows(spec, model, function(name: string): any
		return N.Meshes[name]
	end, sortedKeys(N.Meshes), "Near", say)

	-- The boats.
	local old = model:FindFirstChild(B.Folder)
	if old then
		old:Destroy()
	end
	if template and template:IsA("MeshPart") then
		dress(template, spec, "Near", nil, nil, false, say)
		template.RenderFidelity = Enum.RenderFidelity.Performance
		local tris = triangleCount(template)
		if tris then
			total += tris * #B.Paths
		end
		local folder = Instance.new("Model")
		folder.Name = B.Folder
		local scale = B.Scale or 1
		local offset = CFrame.new(template.Position * scale) * template.CFrame.Rotation
		for i, path in B.Paths do
			local start: CFrame
			if motion then
				local p = motion.boatPose(path, 0, B)
				start = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, p.yaw, 0)
			else
				start = CFrame.new(path.Centre[1], B.SeaY, path.Centre[2])
			end
			local boat = template:Clone()
			boat.Size = template.Size * scale
			boat.Name = ("Boat%02d"):format(i)
			boat:SetAttribute("BoatIndex", i)
			boat:SetAttribute("BoatOffset", offset)
			boat.CFrame = start * offset
			boat.Parent = folder
		end
		folder.Parent = model
	else
		say(
			("PROBLEM: no %s mesh in the import or in ServerStorage.%s."):format(
				B.Mesh,
				B.Templates
			)
		)
	end

	say(("Removed %d gray-box parts of the near world."):format(removeGrayBox(map, "near")))
	fillWater(data)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent

	triangleReport(total, counted, spec.TriangleCaps[N.Import], "near world, with the boats", say)
	backdropBudget(map, spec, say)
	return table.concat(lines, "\n")
end

--- Edit mode only: turn a fresh import of the mid backdrop (Config.Map.Backdrop,
--- fbx/Backdrop.fbx: the skyline's and the islands' chunks) into Map.<Import>. Safe to run
--- twice. Places it by its anchor cubes, dresses each chunk by its name's prefix (Skyline_m2_0
--- takes the Skyline row), makes it Persistent, and removes the gray-box's mid-city rows.
--- `_data` (the gray-box data) is taken for the same call shape as the others; unused yet.
--- Returns a report; anything wrong is a line starting "PROBLEM:".
function MapBuilder.prepareBackdrop(spec: any, _data: any): string
	if game:GetService("RunService"):IsRunning() then
		error("MapBuilder.prepareBackdrop runs in Edit mode only; stop the play session first")
	end
	local lines: { string } = {}
	local function say(line: string)
		table.insert(lines, line)
	end
	local map = mapModel()
	local Bk = spec.Backdrop
	local model = takeImport(Bk.Import, map, spec.Anchors, say)
	if model == nil then
		return ("No Model named %s in Workspace. Import assets/map/fbx/Backdrop.fbx with the 3D Importer (assets/map/Readme.md) and run this again."):format(
			Bk.Import
		)
	end
	assert(model, "the backdrop's model")
	local total, counted = dressRows(spec, model, function(name: string): any
		return Bk.Meshes[name:match("^(%a+)_") or name]
	end, nil, "Backdrop", say)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	say(("Removed %d gray-box parts of the mid city."):format(removeGrayBox(map, "mid")))
	triangleReport(total, counted, spec.TriangleCaps[Bk.Import], "backdrop", say)
	backdropBudget(map, spec, say)
	return table.concat(lines, "\n")
end

-- Write a preset block's values onto an instance: hex strings become colours, asset ids stay
-- strings, numbers and booleans go as they are. Nested tables are the caller's.
local function applyValues(target: Instance, values: { [string]: any })
	for key, value in values do
		if type(value) == "table" then
			continue
		elseif type(value) == "string" and value:sub(1, 1) == "#" then
			(target :: any)[key] = Color3.fromHex(value)
		else
			(target :: any)[key] = value
		end
	end
end

--- Edit mode: apply a lighting preset (Config.Lighting.Day) for captures and so the place is
--- saved lit that way: Lighting's own values, its Atmosphere, its Sky (the place's own one,
--- updated; two Skies clash) and the Terrain's water. Returns a one-line report.
function MapBuilder.applyLighting(preset: any): string
	local Lighting = game:GetService("Lighting")
	applyValues(Lighting, preset)
	local atmosphere = Lighting:FindFirstChildWhichIsA("Atmosphere") or Instance.new("Atmosphere")
	applyValues(atmosphere, preset.Atmosphere)
	atmosphere.Parent = Lighting
	if preset.Sky then
		local sky = Lighting:FindFirstChildWhichIsA("Sky") or Instance.new("Sky")
		applyValues(sky, preset.Sky)
		sky.Parent = Lighting
	end
	if preset.Water then
		applyValues(workspace.Terrain, preset.Water)
	end
	return ("Lighting: clock %.2f, latitude %d, brightness %.2f; sky %s, water %s."):format(
		Lighting.ClockTime,
		Lighting.GeographicLatitude,
		Lighting.Brightness,
		if preset.Sky then "set" else "unchanged",
		if preset.Water then "set" else "unchanged"
	)
end

return MapBuilder
