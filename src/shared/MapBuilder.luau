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

local MapBuilder = {}

--- The model in Workspace that holds the whole map.
MapBuilder.MapName = "Map"
--- The gray-box's model inside it, replaced stage by stage by the Blender meshes.
MapBuilder.GrayBoxName = "GrayBox"

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

--- Builds Workspace.Map.GrayBox from gen_graybox.py's data: one Part per row, grouped into
--- models by the row's folder (Rooftop, Props, Near, Backdrop); clears Terrain and fills the
--- sea with water; removes Workspace.Baseplate and makes the SpawnLocation the entrance mat.
--- Returns a one-line report.
function MapBuilder.buildGrayBox(data: any): string
	local map = mapModel()
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
		local cf: CFrame
		local frame = r["local"]
		if frame then
			-- A prop part: its position is in the prop's own frame.
			cf = CFrame.new(frame[1], frame[2], frame[3])
				* CFrame.Angles(0, math.rad(frame[4]), 0)
				* CFrame.new(r.p[1], r.p[2], r.p[3])
		else
			cf = CFrame.new(r.p[1], r.p[2], r.p[3]) * CFrame.Angles(0, math.rad(r.yaw), 0)
		end
		if r.rot then
			cf = cf * CFrame.Angles(math.rad(r.rot[1]), math.rad(r.rot[2]), math.rad(r.rot[3]))
		end
		part.CFrame = cf
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

return MapBuilder
