--!strict
-- AbilityModels: the abilities' uploaded models on the client (docs/prompts/ABILITIES_PROMPT.md
-- 6.4). The server loads each one once (src/server/AbilityAssets.luau) into the
-- ReplicatedStorage folder Config.Ults.Assets.FolderName; this hands out clones. A model that
-- never arrives (not uploaded, or it failed to load) is nil, and the look falls back.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local A = Config.Ults.Assets
local W = Config.UI.AbilityFx

local AbilityModels = {}

-- Names already preloaded (each once per session).
local preloaded: { [string]: boolean } = {}

local function folder(): Instance?
	return ReplicatedStorage:FindFirstChild(A.FolderName)
end

local function cloneOf(model: Instance): Instance?
	local ok, copy = pcall(function()
		return model:Clone()
	end)
	return if ok then copy else nil
end

--- A clone of model `name` if it is here now, else nil. Never yields.
function AbilityModels.tryGet(name: string): Instance?
	local f = folder()
	local model = f and f:FindFirstChild(name)
	return if model then cloneOf(model) else nil
end

--- A clone of model `name`, waiting up to `seconds` (default Config.UI.AbilityFx.
--- ModelWaitSeconds) for the server to finish loading it; nil if it does not come. Yields:
--- call it from a spawned thread, or use tryGet in a frame loop.
function AbilityModels.get(name: string, seconds: number?): Instance?
	local budget = seconds or W.ModelWaitSeconds
	local started = os.clock()
	local f = ReplicatedStorage:WaitForChild(A.FolderName, budget)
	if f == nil then
		return nil
	end
	local model = f:WaitForChild(name, math.max(budget - (os.clock() - started), 0.01))
	return if model then cloneOf(model) else nil
end

--- Fetch the meshes and textures of every model loaded so far (each once), so an ability's
--- first use does not pop in. Called when the player sits at a table. Never blocks.
function AbilityModels.preload()
	local f = folder()
	if f == nil then
		return
	end
	local list: { Instance } = {}
	for _, model in f:GetChildren() do
		if not preloaded[model.Name] then
			preloaded[model.Name] = true
			table.insert(list, model) -- PreloadAsync fetches everything under it
		end
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
end

return AbilityModels
