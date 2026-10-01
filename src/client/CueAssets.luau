--!strict
-- CueAssets: load a cue's look before it is shown (designer, 2026-10-01: a cue switched in must
-- appear as itself, never as the old cue being retextured on screen). Every skin shares one
-- mesh, so a repaint only swaps the maps; until they are downloaded the stick shows the wrong
-- pictures. A cue is "ready" once everything its stick draws has been fetched:
--   * its skin template (ReplicatedStorage.CueSkins.<id>: the SurfaceAppearance and its moving
--     surface's Frames) and its 3D piece's template (ReplicatedStorage.CuePieces.<piece>);
--   * every image its row names (maps, frames, aura and moving-surface textures) and the
--     effect roles' default textures.
-- One PreloadAsync per cue, once per session. After Config.CueSkins.PreloadTimeoutSeconds a
-- cue counts as ready anyway, so a slow asset never keeps it hidden. A cue drawn with bands
-- (no template) is ready at once.
--
-- CueStickBuilder holds a stick hidden until its new cue is ready (setLoader, from Main), and
-- BackCue puts a cue on a back only when ready.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueSkins = require(Shared:WaitForChild("CueSkins"))
local Textures = require(Shared:WaitForChild("CueSkins"):WaitForChild("Textures"))

local CueAssets = {}

local state: { [string]: "loading" | "ready" } = {}
local waiters: { [string]: { () -> () } } = {}

local function template(id: string): Instance?
	local folder = ReplicatedStorage:FindFirstChild(Config.Cue.MeshSkinsFolder)
	return folder and folder:FindFirstChild(id)
end

-- Every "rbxassetid://..." string anywhere in a row's table.
local function collect(value: any, out: { string }, seen: { [string]: boolean })
	if type(value) == "string" then
		if value:match("^rbxassetid://%d+$") and not seen[value] then
			seen[value] = true
			table.insert(out, value)
		end
	elseif type(value) == "table" then
		for _, v in value do
			collect(v, out, seen)
		end
	end
end

-- What the stick draws for cue `id`: its templates and its images.
local function contents(id: string): { any }
	local list: { any } = {}
	local skin = template(id)
	if skin then
		table.insert(list, skin) -- PreloadAsync fetches everything under it
	end
	local row = CueSkins.get(id)
	if row then
		local pieces = ReplicatedStorage:FindFirstChild(Config.CueSkins.PiecesFolder)
		local piece = row.Piece and pieces and pieces:FindFirstChild(row.Piece)
		if piece then
			table.insert(list, piece)
		end
		local ids: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, key in { "Maps", "Frames", "Aura", "Moving" } do
			collect(row[key], ids, seen)
		end
		collect(Textures, ids, seen)
		for _, s in ids do
			table.insert(list, s)
		end
	end
	return list
end

local function finish(id: string)
	if state[id] == "ready" then
		return
	end
	state[id] = "ready"
	local list = waiters[id]
	waiters[id] = nil
	if list then
		for _, fn in list do
			task.spawn(fn)
		end
	end
end

--- True when cue `id` can be shown fully loaded now (a band cue always can).
function CueAssets.ready(id: string): boolean
	return state[id] == "ready" or template(id) == nil
end

--- Start fetching cue `id` (once; later calls do nothing). Never blocks.
function CueAssets.preload(id: string)
	if state[id] ~= nil then
		return
	end
	if template(id) == nil then
		state[id] = "ready"
		return
	end
	state[id] = "loading"
	task.delay(Config.CueSkins.PreloadTimeoutSeconds, finish, id)
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(contents(id))
		end)
		finish(id)
	end)
end

--- Call `fn` once cue `id` is ready: now when it already is, else when its fetch finishes
--- (started here if needed).
function CueAssets.whenReady(id: string, fn: () -> ())
	if CueAssets.ready(id) then
		fn()
		return
	end
	local list = waiters[id] or {}
	waiters[id] = list
	table.insert(list, fn)
	CueAssets.preload(id)
end

return CueAssets
