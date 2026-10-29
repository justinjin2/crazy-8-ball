--!nocheck
-- Build the cue skins' Edit-mode templates in the open place, from the generated CueSkins data
-- (src/shared/CueSkins, synced by Rojo). Run in Studio's Edit mode (Studio MCP execute_luau,
-- or the command bar) after `python3 tools/cue_skins_data.py`; it is what a game script cannot
-- do (a SurfaceAppearance's maps, a MeshPart's mesh), so the results live in the place:
--
--   ReplicatedStorage.CueSkins.<CatalogId>   a copy of Classic's template (the shared cue mesh,
--                                            pivot on the tip) wearing the skin's maps, plus a
--                                            Frames folder of SurfaceAppearances F1..Fn for a
--                                            Legendary's moving surface
--   ReplicatedStorage.CuePieces.<piece>      one MeshPart per rigid part and one Model per
--                                            skinned file, loaded from their uploaded ids and
--                                            dressed (Material, Color, Transparency,
--                                            Reflectance, SurfaceAppearance)
--
-- Classic's own template is never touched. Set ONLY to rebuild a few skins (the live place:
-- one failed LoadAsset in a full run would break a shipped cue), or ALL for the old full
-- rebuild. Returns a report.

local ONLY = nil -- e.g. { "JackOLanternCue", "PitchforkCue" }: rebuild only these skins'
-- templates and the pieces they use (Piece, Carrier, Body, Pocket.Piece); nothing else is touched
local ALL = false -- true: the old full rebuild (never on the live place)

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Studio's Edit mode keeps a module's first require for the session, so a module Rojo has
-- since changed would load stale: require a fresh clone (next to it, for its own requires).
-- The clones stay until the end: CueSkins loads its rows from its own children lazily.
local clones = {}
local function fresh(module)
	local copy = module:Clone()
	copy.Name = module.Name .. "_Fresh"
	copy.Parent = module.Parent
	table.insert(clones, copy)
	local ok, result = pcall(require, copy)
	assert(ok, result)
	return result
end
local Config = fresh(Shared.Config)
local CueSkins = fresh(Shared.CueSkins)

local report = {}
local function note(s)
	table.insert(report, s)
end

-- The skins this run touches: every one (ALL), or the ONLY list (an id with no row, a draft or
-- a cut skin, is noted and skipped so a typo never passes silently); neither set refuses.
if ONLY == nil and not ALL then
	for _, copy in clones do
		copy:Destroy()
	end
	error(
		"build_cue_templates: set ONLY = { <catalog ids> } to rebuild only those skins' templates "
			.. "and the pieces they use, or ALL = true for the full rebuild (never on the live place)"
	)
end
local wanted: { [string]: boolean }? = nil
if not ALL then
	wanted = {}
	for _, id in ONLY :: { string } do
		if CueSkins.has(id) then
			wanted[id] = true
		else
			note(("only: %s has no skin row (draft, cut or a typo): skipped"):format(tostring(id)))
		end
	end
end
local function included(id: string): boolean
	return wanted == nil or wanted[id] == true
end

local MAP_KEYS = {
	Color = "ColorMapContent",
	Normal = "NormalMapContent",
	Roughness = "RoughnessMapContent",
	Metalness = "MetalnessMapContent",
	Emissive = "EmissiveMaskContent",
}

local function color(c)
	if type(c) == "string" then
		return Color3.fromHex(c)
	end
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function surfaceAppearance(maps, surface)
	local sa = Instance.new("SurfaceAppearance")
	for key, prop in MAP_KEYS do
		local id = maps[key]
		if id and id ~= "" then
			sa[prop] = Content.fromUri(id)
		end
	end
	surface = surface or {}
	if maps.Emissive and maps.Emissive ~= "" then
		sa.EmissiveStrength = surface.EmissiveStrength or 1
		sa.EmissiveTint = color(surface.EmissiveTint or "#FFFFFF")
	end
	if surface.Color then
		sa.Color = color(surface.Color)
	end
	-- A hologram (the Unique cues, 2026-10-04): the colour map's alpha is the transparency.
	if surface.AlphaMode then
		sa.AlphaMode = (Enum.AlphaMode :: any)[surface.AlphaMode]
	end
	return sa
end

local folder = ReplicatedStorage:FindFirstChild(Config.Cue.MeshSkinsFolder)
local classic = folder and folder:FindFirstChild("Classic")
assert(
	classic and classic.PrimaryPart,
	"needs ReplicatedStorage.CueSkins.Classic (the cue mesh run's template)"
)

-- Skins
local before = #folder:GetChildren()
local built, missing = 0, {}
for _, id in CueSkins.ids() do
	if id ~= "Classic" and included(id) then
		local row = CueSkins.get(id)
		local old = folder:FindFirstChild(id)
		if old then
			old:Destroy()
		end
		if row.Maps.Color == "" then
			table.insert(missing, id)
			continue
		end
		local model = classic:Clone()
		model.Name = id
		local part = model.PrimaryPart
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		surfaceAppearance(row.Maps, row.Surface).Parent = part
		if row.Frames then
			local frames = Instance.new("Folder")
			frames.Name = "Frames"
			for i = 2, #row.Frames.Maps do
				local maps = table.clone(row.Maps)
				for key, value in row.Frames.Maps[i] do
					maps[key] = value
				end
				local sa = surfaceAppearance(maps, row.Surface)
				sa.Name = "F" .. (i - 1)
				sa.Parent = frames
			end
			frames.Parent = model
		end
		model.Parent = folder
		built += 1
	end
end
if wanted then
	-- Everything that was in the folder and is not one of the rebuilt ids is untouched.
	local untouched = 0
	for _, model in folder:GetChildren() do
		if not wanted[model.Name] then
			untouched += 1
		end
	end
	note(
		("only: %d skins rebuilt; %d other templates untouched (%d before)%s"):format(
			built,
			untouched,
			before,
			if #missing > 0 then "; no maps yet: " .. table.concat(missing, ", ") else ""
		)
	)
else
	note(
		("skins: %d templates built%s"):format(
			built,
			if #missing > 0 then "; no maps yet: " .. table.concat(missing, ", ") else ""
		)
	)
end

-- Pieces
local pieces = ReplicatedStorage:FindFirstChild(Config.CueSkins.PiecesFolder)
if pieces == nil then
	pieces = Instance.new("Folder")
	pieces.Name = Config.CueSkins.PiecesFolder
	pieces.Parent = ReplicatedStorage
end

local function load(assetId)
	local ok, model = pcall(InsertService.LoadAsset, InsertService, tonumber(assetId))
	if not ok then
		return nil, tostring(model)
	end
	return model
end

local function dress(part, spec)
	part.Material = (Enum.Material :: any)[spec.Material or "SmoothPlastic"]
		or Enum.Material.SmoothPlastic
	part.Color = color(spec.Color or "#FFFFFF")
	part.Transparency = spec.Transparency or 0
	part.Reflectance = spec.Reflectance or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	for _, child in part:GetChildren() do
		if child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	local sa = spec.SurfaceAppearance
	if sa then
		local look = surfaceAppearance({
			Color = sa.ColorMap,
			Normal = sa.NormalMap,
			Emissive = sa.EmissiveMask,
			-- opt-in (the Pitchfork Cue's lacquer, 2026-10-28): older pieces carry generated
			-- roughness maps this never applied (Infernal's skull), so their look stays put
			Roughness = if sa.UseRoughness then sa.RoughnessMap else nil,
		}, { EmissiveStrength = sa.EmissiveStrength, EmissiveTint = sa.EmissiveTint })
		look.AlphaMode = (Enum.AlphaMode :: any)[sa.AlphaMode or "Overlay"]
		look.Parent = part
		part.TextureID = ""
	end
end

local pieceIds = {}
for _, id in CueSkins.ids() do
	local row = CueSkins.get(id)
	if included(id) then
		if row.Piece then
			pieceIds[row.Piece] = true
		end
		if row.Carrier then
			pieceIds[row.Carrier] = true -- the piece worn by the carrying player (a Secret's engulfing aura)
		end
		if row.Body then
			pieceIds[row.Body] = true -- the cue's own model (Halloween 2026)
		end
		if row.Pocket and row.Pocket.Piece then
			pieceIds[row.Pocket.Piece.Piece] = true
		end
	end
end
local sorted = {}
for id in pieceIds do
	table.insert(sorted, id)
end
table.sort(sorted)

for _, pid in sorted do
	local row = CueSkins.piece(pid)
	local old = pieces:FindFirstChild(pid)
	if old then
		old:Destroy()
	end
	local out = Instance.new("Folder")
	out.Name = pid
	local problems = {}
	-- Rigid parts: one uploaded model of named MeshParts.
	local rigidSource = nil
	if row.Rigid and row.Rigid ~= "" then
		local m, err = load(row.Rigid)
		rigidSource = m
		if m == nil then
			table.insert(problems, "rigid " .. tostring(err))
		end
	elseif row.Rigid ~= nil then
		table.insert(problems, "rigid not uploaded")
	end
	local loaded = {}
	for name, assetId in row.Models do
		if assetId == "" then
			table.insert(problems, name .. " not uploaded")
		else
			local m, err = load(assetId)
			if m then
				loaded[name] = m
			else
				table.insert(problems, name .. " " .. tostring(err))
			end
		end
	end
	local done = {}
	for _, spec in row.Parts do
		if spec.Model then
			local m = loaded[spec.Model]
			if m and not done[spec.Model] then
				done[spec.Model] = true
				-- The importer wraps the rig in a Model named after the file: keep that Model.
				local rig = m:FindFirstChildWhichIsA("Model") or m
				rig.Name = spec.Model
				for _, d in rig:GetDescendants() do
					if
						d:IsA("AnimationController")
						or (d:IsA("Folder") and d.Name == "InitialPoses")
					then
						d:Destroy()
					end
				end
				rig.Parent = out
			end
			local rig = out:FindFirstChild(spec.Model)
			local mesh = rig and rig:FindFirstChild(spec.Mesh or spec.Name, true)
			if mesh and mesh:IsA("BasePart") then
				dress(mesh, spec)
				mesh.Name = spec.Name
				mesh.Anchored = false
			elseif rig then
				table.insert(problems, "no mesh " .. tostring(spec.Mesh))
			end
		elseif rigidSource then
			local mesh = rigidSource:FindFirstChild(spec.Name, true)
			if mesh and mesh:IsA("BasePart") then
				dress(mesh, spec)
				mesh.Parent = out
			else
				table.insert(problems, "no part " .. spec.Name)
			end
		end
	end
	for _, m in loaded do
		if m.Parent == nil then
			m:Destroy()
		end
	end
	if rigidSource then
		rigidSource:Destroy()
	end
	out.Parent = pieces
	note(
		("piece %s: %d children%s"):format(
			pid,
			#out:GetChildren(),
			if #problems > 0 then " | " .. table.concat(problems, "; ") else ""
		)
	)
end

if wanted then
	local untouched = 0
	for _, child in pieces:GetChildren() do
		if not pieceIds[child.Name] then
			untouched += 1
		end
	end
	note(("only: %d pieces rebuilt; %d other pieces untouched"):format(#sorted, untouched))
end

for _, copy in clones do
	copy:Destroy()
end
return table.concat(report, "\n")
