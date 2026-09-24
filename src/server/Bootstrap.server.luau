--!strict
-- Server bootstrap. Builds the tables, wires up the pads and the shot authority, and
-- publishes the assets the client cannot reach on its own.
--
-- Config.Lounge.Enabled decides whether this is a lounge or a bare baseplate with a table
-- on it for testing the shot. Everything below the lounge block is the same either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LoungeBuilder = require(Shared:WaitForChild("LoungeBuilder"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
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

-- The lounge lives in the place: its meshes, textures and materials are all things a game
-- script may not create. With it switched off none of that is expected to be there.
if Config.Lounge.Enabled and not LoungeBuilder.isImported(workspace) then
	warn(
		"[8ball] Config.Lounge.Enabled is true but no lounge is imported. Import the six "
			.. "FBX packages from assets/lounge/exports, run LoungeBuilder.setUp(workspace) "
			.. "in Edit mode, and save the place. The tables below are still built."
	)
end

-- Arrive facing all three mode queues; the baseplate and stored lounge are retained.
if not Config.Lounge.Enabled then
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then
		local p = Config.Multiplayer.Spawn
		spawn.CFrame = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, math.rad(p.YawDegrees), 0)
	end
end

-- Every table lives under one folder, named by id, so twelve of them can be told apart.
local existing = workspace:FindFirstChild(TableBuilder.FolderName)
if existing then
	existing:Destroy()
end
local tables = Instance.new("Folder")
tables.Name = TableBuilder.FolderName
tables.Parent = workspace

-- Only the first TableCount of them: twelve for the lounge, one for a testing baseplate.
local built = 0
local wanted = Placement.tableCount()
for _, row in Config.Lounge.Tables do
	if row.id <= wanted then
		local placement = Placement.forTable(row.id)
		if placement then
			TableBuilder.build(tables, placement, row.id)
			built += 1
		end
	end
end

-- Seats on the sofas and chairs. Unlike the lounge meshes these are plain Seat parts, which
-- a script may create, so they are built fresh from Config every run rather than living in
-- the place file and drifting out of step with it. No lounge, no sofas.
local lounge = workspace:FindFirstChild(LoungeBuilder.ModelName)
local seated = 0
if Config.Lounge.Enabled and lounge and lounge:IsA("Model") then
	seated = LoungeBuilder.buildSeats(lounge)
end

-- The floor pads and the seat state behind them, then the shot authority: the client sends
-- inputs, this decides what actually happened.
TableService.start(workspace)
ShotService.start()

-- No per-table light any more. One shadow-casting SpotLight was fine above a single table
-- and is the most expensive thing twelve tables could carry. The lounge's own pendant
-- SurfaceLights (shadows off, one per table) plus the sun do the work instead; see
-- Config.Lounge.Pendant and LoungeBuilder.buildPendants.

print(
	("[8ball] server ready. %s, %d tables with pads, %d seats, %dx%d in, %.2f studs/in"):format(
		if Config.Lounge.Enabled then "lounge" else "baseplate",
		built,
		seated,
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
