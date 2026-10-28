--!strict
-- MapProps (Halloween 2026, hw-map lane): the Haunted Rooftop's props while Live
-- (Config.HalloweenMap.Props; HW_MAP_PROMPT 2.5). The palms, fern planters and planter beds
-- under workspace.Map are put away (moved to ServerStorage, never destroyed; Rules.hideList
-- never takes a portal's); a dead tree grows from each palm's pot, scaled to the palm and
-- leaning toward the roof's middle; each planter becomes a spooky one of the same footprint
-- (a dark box in its pot's place, its dressing mesh on top); and the free placements go up
-- (string lights on the pergola, cobwebs in its corners, pumpkins at the throne's lanterns).
-- Everything is built once, at the first Live, from the map as it stands, into a ServerStorage
-- holder, so Live and Ended only move it. While the event's meshes are not loaded nothing is
-- hidden (today's map stays). Every piece touches nothing; each prop streams whole (Atomic).
-- EventMap runs it as its "Props" part (the lobby only).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local Once = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Once"))
local Assets = require(script.Parent:WaitForChild("Assets"))

local P = Config.HalloweenMap.Props

local MapProps = {}

local built: Folder? = nil
local hiddenHolder: Folder? = nil
local hidden: { { inst: Instance, parent: Instance } } = {}
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[HalloweenMap] " .. message)
	end
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- A prop piece touches nothing, is never hit by a ray and casts no shadow.
local function quiet(part: BasePart)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
end

-- A copy of prop `name` scaled by `scale`, stretched `stretch` times along its own X (a string
-- of lights spanning its two ends), its origin at `at`; nil (warned once) while not loaded.
local function copy(name: string, at: CFrame, scale: number, stretch: number?): Model?
	local model = Assets.clone(name)
	if model == nil then
		warnOnce(name, ("the event's %s mesh is not loaded: left out"):format(name))
		return nil
	end
	if stretch and stretch ~= 1 then
		-- The template's pieces sit unturned round its pivot, so a stretch is per piece.
		local pivot = model:GetPivot()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(d.CFrame)
				d.Size = Vector3.new(d.Size.X * stretch, d.Size.Y, d.Size.Z)
				d.CFrame = pivot * CFrame.new(offset.X * stretch, offset.Y, offset.Z)
			end
		end
	end
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(at)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			quiet(d)
		end
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

-- The map's visual Models that Props.Hide takes (never a portal's).
local function toHide(map: Instance): { Instance }
	local models: { Instance } = {}
	local names: { string } = {}
	for _, inst in map:GetDescendants() do
		if inst:IsA("Model") then
			table.insert(models, inst)
			table.insert(names, inst.Name)
		end
	end
	local taken: { [string]: boolean } = {}
	for _, name in Rules.hideList(names, P.Hide) do
		taken[name] = true
	end
	local out: { Instance } = {}
	for _, inst in models do
		if taken[inst.Name] then
			table.insert(out, inst)
		end
	end
	return out
end

-- A palm's dead tree: in its nearest pot, the palm's height share, leaning to the middle.
local function addTree(into: Folder, palm: Model, pots: { Model }, lean: Vector3, height: number)
	local T = P.Trees
	local _, palmSize = palm:GetBoundingBox()
	local at = palm:GetPivot().Position
	local pot: Model? = nil
	local best = math.huge
	for _, candidate in pots do
		local p = candidate:GetPivot().Position
		local d = Vector2.new(p.X - at.X, p.Z - at.Z).Magnitude
		if d < best then
			pot, best = candidate, d
		end
	end
	if pot == nil then
		warnOnce("pot", "a palm has no pot near it: no dead tree there")
		return
	end
	local potAt, potSize = pot:GetBoundingBox()
	local foot = Vector3.new(potAt.X, potAt.Y + potSize.Y / 2 - T.FootBelowPotTop, potAt.Z)
	local scale = math.clamp(palmSize.Y * T.HeightShare / height, T.MinScale, T.MaxScale)
	local id = tonumber(palm.Name:match("(%d+)$")) or 0
	local yaw = Rules.treeYaw(foot.X, foot.Z, lean.X, lean.Z, T.YawJitter, id)
	local tree = copy(T.Prop, CFrame.new(foot) * CFrame.Angles(0, yaw, 0), scale)
	if tree then
		tree.Name = "DeadTree_" .. id
		tree.Parent = into
	end
end

-- A planter's spooky twin: a dark box in its pot's place and its dressing on top, the
-- pumpkins (the dressing's -Z) turned to the roof's middle.
local function addPlanter(into: Folder, planter: Model)
	local dressing = nil
	for _, row in P.Planters.Dressings do
		if planter.Name:match(row.Match) then
			dressing = row
			break
		end
	end
	if dressing == nil then
		return
	end
	local pot: BasePart? = nil
	for _, d in planter:GetDescendants() do
		if d:IsA("BasePart") and d.Name:match(P.Planters.Pot) then
			pot = d
			break
		end
	end
	if pot == nil then
		warnOnce("planterPot", ("%s has no pot part: left as it is"):format(planter.Name))
		return
	end
	local model = Instance.new("Model")
	model.Name = "Spooky" .. planter.Name
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local box = Instance.new("Part")
	box.Name = "Box"
	box.Size = pot.Size
	box.CFrame = pot.CFrame
	box.Color = rgb(P.Planters.Color)
	box.Material = (Enum.Material :: any)[P.Planters.Material]
	box.TopSurface = Enum.SurfaceType.Smooth
	box.BottomSurface = Enum.SurfaceType.Smooth
	quiet(box)
	box.CastShadow = true
	box.Parent = model
	local top = pot.CFrame * CFrame.new(0, pot.Size.Y / 2, 0)
	if top.LookVector:Dot(Vector3.new(-top.X, 0, -top.Z)) < 0 then
		top *= CFrame.Angles(0, math.pi, 0)
	end
	local dress = copy(dressing.Prop, top, pot.Size.X / dressing.Width)
	if dress then
		dress.Parent = model
	end
	model.Parent = into
end

-- A string of lights hung from `row.From` to `row.To` (the mesh stretched along its length).
local function addStrand(into: Folder, row: any, index: number)
	local template = Assets.clone(P.StrandProp)
	if template == nil then
		warnOnce(P.StrandProp, ("the event's %s mesh is not loaded: left out"):format(P.StrandProp))
		return
	end
	local _, size = template:GetBoundingBox()
	template:Destroy()
	local a = Vector3.new(row.From[1], row.From[2], row.From[3])
	local b = Vector3.new(row.To[1], row.To[2], row.To[3])
	local along = (b - a).Unit
	local at = CFrame.fromMatrix((a + b) / 2, along, Vector3.yAxis, along:Cross(Vector3.yAxis))
	local model = copy(P.StrandProp, at, 1, (b - a).Magnitude / size.X)
	if model then
		if row.Glow then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Name == "Glow" then
					d.Color = rgb(row.Glow)
				end
			end
		end
		model.Name = ("Strand_%02d"):format(index)
		model.Parent = into
	end
end

-- One other placement: a prop's origin at At, turned Yaw degrees, scaled.
local function addPlaced(into: Folder, row: any, index: number)
	local at = CFrame.new(row.At[1], row.At[2], row.At[3])
		* CFrame.Angles(0, math.rad(row.Yaw or 0), 0)
	local model = copy(row.Prop, at, row.Scale or 1)
	if model then
		model.Name = ("%s_%02d"):format(row.Prop, index)
		model.Parent = into
	end
end

-- The one build (Once): a second caller during the mesh wait waits for this build; a build
-- that found no meshes or no map is tried again at the next call.
local propsBuild = Once.new(function(): boolean
	if not Assets.wait() then
		warnOnce(
			"assets",
			"the event's meshes did not load: the rooftop keeps its palms and planters"
		)
		return false
	end
	local map = workspace:FindFirstChild(Config.Map.Name)
	if map == nil then
		return false
	end
	local folder = Instance.new("Folder")
	folder.Name = P.Holder
	local pots: { Model } = {}
	for _, inst in map:GetDescendants() do
		if inst:IsA("Model") and inst.Name:match(P.Trees.Pots) then
			table.insert(pots, inst)
		end
	end
	-- The tree mesh's lean (its crown's offset from its foot) and height, at scale 1.
	local lean, height = Vector3.zero, 1
	local template = Assets.clone(P.Trees.Prop)
	if template then
		local centre, size = template:GetBoundingBox()
		lean = centre.Position - template:GetPivot().Position
		height = size.Y
		template:Destroy()
	end
	for _, inst in toHide(map) do
		local ok, err = pcall(function()
			if inst:IsA("Model") and inst.Name:match(P.Trees.Replaces) then
				addTree(folder, inst, pots, lean, height)
			elseif inst:IsA("Model") then
				addPlanter(folder, inst)
			end
		end)
		if not ok then
			warnOnce("build", ("a prop for %s failed: %s"):format(inst.Name, tostring(err)))
		end
	end
	for i, row in P.Strands do
		local ok, err = pcall(function()
			addStrand(folder, row, i)
		end)
		if not ok then
			warnOnce("strand", "a string of lights failed: " .. tostring(err))
		end
	end
	for i, row in P.Place do
		local ok, err = pcall(function()
			addPlaced(folder, row, i)
		end)
		if not ok then
			warnOnce("place", ("a placed %s failed: %s"):format(tostring(row.Prop), tostring(err)))
		end
	end
	folder.Parent = ServerStorage
	built = folder
	return true
end)

-- Whether the props should show: on sets it, off clears it, so an off during the build's wait
-- wins over the on still waiting.
local wanted = false

--- Build the props once (yields for the meshes, up to Assets.WaitSeconds). True when built.
function MapProps.prepare(): boolean
	return propsBuild:run()
end

local function hideMap()
	local map = workspace:FindFirstChild(Config.Map.Name)
	if map == nil then
		return
	end
	if hiddenHolder == nil then
		local f = Instance.new("Folder")
		f.Name = "HalloweenHidden"
		f.Parent = ServerStorage
		hiddenHolder = f
	end
	for _, inst in toHide(map) do
		if inst.Parent then
			table.insert(hidden, { inst = inst, parent = inst.Parent :: Instance })
			inst.Parent = hiddenHolder
		end
	end
end

local function showMap()
	for i = #hidden, 1, -1 do
		local h = hidden[i]
		if h.parent.Parent ~= nil then
			h.inst.Parent = h.parent
		end
	end
	table.clear(hidden)
end

--- The props as an EventMap part (on while Live, when Props.Enabled; the lobby only).
function MapProps.part(): any
	return {
		name = "Props",
		enabled = function(): boolean
			return P.Enabled
		end,
		on = function()
			wanted = true
			if MapProps.prepare() and wanted then
				hideMap()
				local folder = built :: Folder
				folder.Parent = workspace
			end
		end,
		off = function()
			wanted = false
			if built then
				built.Parent = ServerStorage
			end
			showMap()
		end,
	}
end

return MapProps
