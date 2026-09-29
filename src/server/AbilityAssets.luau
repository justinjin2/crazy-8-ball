--!strict
-- AbilityAssets: loads the abilities' uploaded models once per server (docs/prompts/
-- ABILITIES_PROMPT.md 6.4). Each `Config.Ults.Assets.Models[name] = assetId` above 0 is fetched
-- with InsertService:LoadAsset (on the server: the place and the assets are both the group's),
-- retried Config.Ults.Assets.LoadRetries times LoadRetrySeconds apart, and the model inside is
-- named `name` and put in the ReplicatedStorage folder Config.Ults.Assets.FolderName for the
-- clients to clone (src/client/AbilityModels.luau). Scripts inside a loaded asset are removed.
-- One that still fails is warned about by name; its ability works anyway and its look falls
-- back to what it builds without the mesh.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local A = Config.Ults.Assets

local AbilityAssets = {}

local folder: Folder? = nil

local function load(target: Folder, name: string, id: number)
	local lastError = "?"
	for attempt = 1, math.max(A.LoadRetries, 1) do
		local ok, result = pcall(InsertService.LoadAsset, InsertService, id)
		if ok and result then
			local container = result :: Model
			local children = container:GetChildren()
			local model: Instance = if #children == 1 then children[1] else container
			for _, d in model:GetDescendants() do
				if d:IsA("BaseScript") or d:IsA("ModuleScript") then
					d:Destroy()
				end
			end
			local old = target:FindFirstChild(name)
			if old then
				old:Destroy()
			end
			model.Name = name
			model.Parent = target
			if model ~= container then
				container:Destroy()
			end
			return
		end
		lastError = tostring(result)
		if attempt < A.LoadRetries then
			task.wait(A.LoadRetrySeconds)
		end
	end
	warn(
		("[8ball] ability model %q (asset %d) did not load after %d tries: %s. Its look falls back."):format(
			name,
			id,
			A.LoadRetries,
			lastError
		)
	)
end

--- Make the folder and start loading every model in Config (each on its own thread, so the
--- server's start never waits on the network).
function AbilityAssets.start()
	local existing = ReplicatedStorage:FindFirstChild(A.FolderName)
	local target: Folder
	if existing and existing:IsA("Folder") then
		target = existing
	else
		target = Instance.new("Folder")
		target.Name = A.FolderName
		target.Parent = ReplicatedStorage
	end
	folder = target
	-- In name order, so the log reads the same every start.
	local names: { string } = {}
	for name, id in A.Models do
		if type(id) == "number" and id > 0 then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in names do
		task.spawn(load, target, name, A.Models[name])
	end
end

--- The folder the models go in (nil before start).
function AbilityAssets.folder(): Folder?
	return folder
end

return AbilityAssets
