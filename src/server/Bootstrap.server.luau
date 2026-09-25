--!strict
-- Server bootstrap. Dresses the hub map, builds the tables, wires up the pads and the shot
-- authority, and publishes the assets the client cannot reach on its own.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local HubService = require(script.Parent:WaitForChild("HubService"))
local ShotService = require(script.Parent:WaitForChild("ShotService"))
local TableService = require(script.Parent:WaitForChild("TableService"))

-- Remotes first: TableService and every client look them up by name.
Net.build()

-- Then the imported meshes the clients need (a MeshId is plugin-only, so they live in the
-- place, in ServerStorage), published to ReplicatedStorage.Assets before anything else so they
-- are there when a client first asks. Each is checked for the class its user expects; a
-- missing one says what the game falls back to.
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local function publish(name: string, class: string, missing: string)
	local found = ServerStorage:FindFirstChild(name)
	if found and found:IsA(class) then
		local old = assets:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		found:Clone().Parent = assets
	else
		warn(("[8ball] no ServerStorage.%s: %s"):format(name, missing))
	end
end
publish(Config.Balls.MeshTemplate, "MeshPart", "balls use the decal fallback")
publish(Config.Bridge.Template, "Model", "the bridge uses the parts fallback")

-- The hub's props, seats, lights and collision (the map's meshes are in the place).
HubService.start()

-- Arrive on the balcony prow, looking out over the club.
local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
if spawn then
	local p = Config.Multiplayer.Spawn
	spawn.CFrame = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, math.rad(p.YawDegrees), 0)
end

-- Every table lives under one folder, named by id, so sixteen of them can be told apart.
local existing = workspace:FindFirstChild(TableBuilder.FolderName)
if existing then
	existing:Destroy()
end
local tables = Instance.new("Folder")
tables.Name = TableBuilder.FolderName
tables.Parent = workspace

-- Only the first TableCount of them: sixteen for the full hub, a few on the testing baseplate.
local built = 0
local wanted = Placement.tableCount()
for _, row in Config.Hub.Tables do
	if row.id <= wanted then
		local placement = Placement.forTable(row.id)
		if placement then
			TableBuilder.build(tables, placement, row.id)
			built += 1
		end
	end
end

-- The floor pads and the seat state behind them, then the shot authority: the client sends
-- inputs, this decides what actually happened.
TableService.start(workspace)
ShotService.start()

print(
	("[8ball] server ready. %d tables with pads, %dx%d in, %.2f studs/in"):format(
		built,
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
