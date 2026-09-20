--!strict
-- Server bootstrap. Builds the twelve lounge tables and publishes the assets the client
-- cannot reach on its own. Roadmap 1.5f makes it the shot authority as well (validating
-- inputs, running Simulation, broadcasting results).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LoungeBuilder = require(Shared:WaitForChild("LoungeBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

-- The lounge itself lives in the place: its meshes, textures and materials are all things
-- a game script may not create. LoungeBuilder.setUp assembles it in Edit mode; this only
-- says so if that was never done.
if not LoungeBuilder.isImported(workspace) then
	warn(
		"[8ball] no imported lounge in Workspace. Import the six FBX packages from "
			.. "assets/lounge/exports, run LoungeBuilder.setUp(workspace) in Edit mode, and "
			.. "save the place. The tables below are still built."
	)
end

-- Every table lives under one folder, named by id, so twelve of them can be told apart.
local existing = workspace:FindFirstChild(TableBuilder.FolderName)
if existing then
	existing:Destroy()
end
local tables = Instance.new("Folder")
tables.Name = TableBuilder.FolderName
tables.Parent = workspace

local built = 0
for _, row in Config.Lounge.Tables do
	local placement = Placement.forTable(row.id)
	if placement then
		TableBuilder.build(tables, placement, row.id)
		built += 1
	end
end

-- Publish the imported ball mesh to clients (MeshId is plugin-only, so it lives in the place).
local assets = ReplicatedStorage:FindFirstChild("Assets") or Instance.new("Folder")
assets.Name = "Assets"
assets.Parent = ReplicatedStorage
local ballMesh = ServerStorage:FindFirstChild(Config.Balls.MeshTemplate)
if ballMesh and ballMesh:IsA("MeshPart") then
	local old = assets:FindFirstChild(ballMesh.Name)
	if old then
		old:Destroy()
	end
	ballMesh:Clone().Parent = assets
else
	warn(
		("[8ball] no ServerStorage.%s: balls use the decal fallback"):format(
			Config.Balls.MeshTemplate
		)
	)
end

-- No per-table light any more. One shadow-casting SpotLight was fine above a single table
-- and is the most expensive thing twelve tables could carry. The lounge's own pendant
-- SurfaceLights (shadows off, one per table) plus the sun do the work instead; see
-- Config.Lounge.Pendant and LoungeBuilder.buildPendants.

print(
	("[8ball] server ready. %d tables, %dx%d in each, %.2f studs/in"):format(
		built,
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
