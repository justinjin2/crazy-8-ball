--!strict
-- MapBuilder: builds and prepares the rooftop hub map in Edit mode (the brief is
-- docs/prompts/ROOFTOP_MAP_PROMPT.md, the spec assets/map/Spec.md). Nothing in the running
-- game requires it: it is run from the command bar or the MCP execute_luau tool, like
-- TableBuilder.prepareImport, and what it builds is saved in the place. Every function is safe
-- to run twice.
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
-- Stage 2 imports the architecture (assets/map/fbx/Rooftop.fbx, 3D Importer; the steps are in
-- assets/map/Readme.md) and prepares it:
--
--   local Server, Shared = game.ServerScriptService.Server, game.ReplicatedStorage.Shared
--   print(require(Shared.MapBuilder:Clone()).prepareImport(
--       require(Shared.Config:Clone()).Map, require(Server.MapData.GrayBox:Clone())))

local MapBuilder = {}

--- Each gray-box part carries its row's role (gen_graybox.py) in this attribute: "floor"
--- (becomes the tiled floor), "collide" (becomes an invisible wall or step) or "arch" (replaced
--- by the architecture meshes).
MapBuilder.RoleAttribute = "MapRole"
local REPLACED = { floor = true, collide = true, arch = true }

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
--- With `spec` (Config.Map) and the architecture already imported, the rows it replaced
--- (the roles floor, collide and arch) are left out. Returns a one-line report.
function MapBuilder.buildGrayBox(data: any, spec: any?): string
	local map = mapModel()
	local imported = spec ~= nil and map:FindFirstChild(spec.Architecture) ~= nil
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
		if imported and r.role and REPLACED[r.role] then
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
		if r.role then
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

	-- The sea: Terrain water to the right of the coast and behind the tower (the city carries
	-- on behind it on the left, beyond cityBackX), 4 studs deep.
	-- The map's only Terrain is this sea, so it is cleared and refilled.
	local w = data.water
	local terrain = workspace.Terrain
	terrain:Clear()
	local function fill(x0: number, z0: number, x1: number, z1: number)
		terrain:FillBlock(
			CFrame.new((x0 + x1) / 2, w.seaY - 2, (z0 + z1) / 2),
			Vector3.new(x1 - x0, 4, z1 - z0),
			Enum.Material.Water
		)
	end
	fill(w.coastX, -w.reach, w.reach, w.reach)
	fill(w.cityBackX, -w.reach, w.coastX, w.coastZ)

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

--- Edit mode only (MeshPart and MaterialVariant maps are plugin-only writes): turn a fresh
--- import of the architecture (Config.Map.Architecture) into the map. Safe to run twice.
---  1. Finds the imported model in Workspace or the map and flattens it.
---  2. Puts it back where Blender built it, from the three anchor cubes, then deletes them.
---  3. Sets up each mesh (Config.Map.Meshes): anchored, never colliding, shadows, automatic
---     LOD, a SurfaceAppearance from Maps or a flat colour.
---  4. Makes the floor's MaterialVariant (Config.Map.Floor).
---  5. Builds Map.Collision from the gray-box data's floor and collide rows (the floor tiled
---     and visible, the rest invisible) and removes the gray-box parts they replace.
---  6. Counts triangles against Config.Map.TriangleCaps.
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
	local found = map:FindFirstChild(spec.Architecture)
		or workspace:FindFirstChild(spec.Architecture)
	if not (found and found:IsA("Model")) then
		return ("No Model named %s in Workspace. Import assets/map/fbx/Rooftop.fbx with the 3D Importer (assets/map/Readme.md) and run this again."):format(
			spec.Architecture
		)
	end
	local model: Model = found

	-- 1. Flatten: every MeshPart straight under the model, no empty containers.
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

	-- 2. Place by the anchors: the frame they span now is moved onto the world's.
	local A = spec.Anchors
	local o, x, z = model:FindFirstChild(A.O), model:FindFirstChild(A.X), model:FindFirstChild(A.Z)
	if o and x and z then
		local po = (o :: BasePart).Position
		local vx, vz = (x :: BasePart).Position - po, (z :: BasePart).Position - po
		local scale = (vx.Magnitude + vz.Magnitude) / (2 * A.Spacing)
		if math.abs(scale - 1) > 0.01 then
			say(
				("PROBLEM: the anchors are %.3f times as far apart as they should be: re-import with Scale Unit: Stud and scale 1."):format(
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
		local turned = math.deg(math.atan2(-ax.Z, ax.X))
		say(
			("Placed by the anchors: moved %.2f studs, turned %.1f degrees."):format(
				po.Magnitude,
				turned
			)
		)
		o:Destroy()
		x:Destroy()
		z:Destroy()
	else
		say("No anchors (already placed on an earlier run).")
	end
	model.WorldPivot = CFrame.identity
	model.Name = spec.Architecture
	model.Parent = map

	-- 3. The meshes.
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
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = ms.CastShadow
		part.RenderFidelity = Enum.RenderFidelity.Automatic
		part.CollisionFidelity = Enum.CollisionFidelity.Box
		part.TextureID = ""
		for _, old in part:GetChildren() do
			if old:IsA("SurfaceAppearance") then
				old:Destroy()
			end
		end
		part.Material = Enum.Material.SmoothPlastic
		part.Transparency = ms.Transparency or 0
		if ms.Maps then
			local maps = spec.Maps[ms.Maps]
			if maps == nil then
				say(
					("PROBLEM: %s names the map set %s, which Config.Map.Maps does not have."):format(
						name,
						ms.Maps
					)
				)
			elseif maps.Color == "" then
				say(("%s: no image uploaded yet for %s."):format(name, ms.Maps))
				if ms.AlphaMode then
					part.Transparency = 1 -- bare, an overlay would draw as a solid grey sheet
				end
			else
				local sa = Instance.new("SurfaceAppearance")
				sa.ColorMap = maps.Color
				if maps.Normal and maps.Normal ~= "" then
					sa.NormalMap = maps.Normal
				end
				if maps.Roughness and maps.Roughness ~= "" then
					sa.RoughnessMap = maps.Roughness
				end
				sa.AlphaMode = (Enum.AlphaMode :: any)[ms.AlphaMode or "Overlay"]
				sa.Parent = part
			end
		elseif ms.Color then
			part.Color = Color3.fromHex(ms.Color)
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

	-- 4. The floor's MaterialVariant.
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

	-- 5. Collision and the floor, from the gray-box data; the gray-box parts they replace go.
	local oldCollision = map:FindFirstChild(spec.CollisionName)
	if oldCollision then
		oldCollision:Destroy()
	end
	local collision = Instance.new("Model")
	collision.Name = spec.CollisionName
	local floors, walls = 0, 0
	for _, r in data.rows do
		if r.role ~= "floor" and r.role ~= "collide" then
			continue
		end
		local part = Instance.new("Part")
		part.Name = r.n
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		part.CastShadow = false
		part.Size = Vector3.new(r.size[1], r.size[2], r.size[3])
		part.CFrame = rowCFrame(r)
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if r.role == "floor" then
			part.Material = variant.BaseMaterial
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
		part.Parent = collision
	end
	collision.Parent = map
	local removed = 0
	local box = map:FindFirstChild(MapBuilder.GrayBoxName)
	if box then
		for _, d in box:GetDescendants() do
			if d:IsA("BasePart") and REPLACED[d:GetAttribute(MapBuilder.RoleAttribute) or ""] then
				d:Destroy()
				removed += 1
			end
		end
	end
	say(
		("Collision: %d floor parts, %d invisible parts; removed %d gray-box parts."):format(
			floors,
			walls,
			removed
		)
	)
	return table.concat(lines, "\n")
end

return MapBuilder
