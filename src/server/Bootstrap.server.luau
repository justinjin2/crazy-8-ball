--!strict
-- Server bootstrap. Builds the tables, wires up the queue pads and the shot authority, and
-- publishes the assets the client cannot reach on its own. The tables stand on the rooftop
-- map (Workspace.Map, built in Edit mode; Config.Hub and assets/map/Spec.md).
--
-- A global-queue arena (designer, 2026-09-28) is a reserved server of this same place: it is
-- told apart first thing (ArenaService.detect), takes the rooftop away before any player
-- arrives, and stands up one table for its match instead of the sixteen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local DevCommands = require(script.Parent:WaitForChild("DevCommands"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local Ranking = require(script.Parent:WaitForChild("Ranking"))
local ShotService = require(script.Parent:WaitForChild("ShotService"))
local TableService = require(script.Parent:WaitForChild("TableService"))
local GlobalQueue = require(script.Parent:WaitForChild("GlobalQueue"))
local ArenaService = require(script.Parent:WaitForChild("ArenaService"))

-- An arena? Decided before anything is built, and the rooftop gone before anyone arrives.
local isArena, matchId = ArenaService.detect()
if isArena then
	ArenaService.prepare()
else
	workspace:SetAttribute(ArenaService.ModeAttribute, "Hub")
end

-- Remotes first: TableService and every client look them up by name.
Net.build()

-- Saves next, so each player's save starts loading the moment they arrive (and its
-- PlayerRemoving is connected before TableService's).
PlayerData.start()
Ranking.start() -- a shutdown voids running matches instead of forfeiting everyone

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

-- Players walk at Config.Hub.WalkSpeed: every player who joins, and anyone already here. (The
-- camera's zoom is Roblox's own: the designer dropped the cap, 2026-09-26.)
local Players = game:GetService("Players")
game:GetService("StarterPlayer").CharacterWalkSpeed = Config.Hub.WalkSpeed
for _, player in Players:GetPlayers() do
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = Config.Hub.WalkSpeed
	end
end

-- Arrive in front of the tables, facing them (the arena has its own spawn).
local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation")
if spawn and not isArena then
	local p = Config.Multiplayer.Spawn
	spawn.CFrame = CFrame.new(p.X, p.Y, p.Z) * CFrame.Angles(0, math.rad(p.YawDegrees), 0)
end

-- The arena's one table, once its player list says how many play a side. With no list
-- there is no match here: everyone who arrives goes back to the lobby.
local record = nil
if isArena then
	record = ArenaService.loadRecord(matchId :: string)
	if not record then
		GlobalQueue.start()
		local function away(p: Player)
			GlobalQueue.sendHome({ p }, {})
		end
		Players.PlayerAdded:Connect(away)
		for _, p in Players:GetPlayers() do
			away(p)
		end
		return
	end
	local row: any = table.clone(Config.Arena.Table)
	row.teamSize = record.mode
	Placement.setLayout({ row })
	workspace:SetAttribute(ArenaService.TeamSizeAttribute, record.mode)
end

-- Every table lives under one folder, named by id, so sixteen of them can be told apart.
local existing = workspace:FindFirstChild(TableBuilder.FolderName)
if existing then
	existing:Destroy()
end
local tables = Instance.new("Folder")
tables.Name = TableBuilder.FolderName
tables.Parent = workspace

-- Only the first TableCount of them (the arena: its one).
local built = 0
for _, row in Placement.rows() do
	local placement = Placement.forTable(row.id)
	if placement then
		TableBuilder.build(tables, placement, row.id)
		built += 1
	end
end

-- The queue pads and the seat state behind them, then the shot authority: the client sends
-- inputs, this decides what actually happened.
TableService.start(workspace, if isArena then "Arena" else "Hub")
ShotService.start()
DevCommands.start() -- /day and /sunset, for the developer only
GlobalQueue.start() -- every server takes its turn pairing the global queue
if isArena then
	ArenaService.start(record)
end

print(
	("[8ball] server ready (%s). %d tables, %dx%d in, %.2f studs/in"):format(
		if isArena then "arena" else "lobby",
		built,
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
