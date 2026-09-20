--!strict
-- Server bootstrap. For the solo MVP the server only builds the table; later it becomes
-- the shot authority (validates inputs, runs Simulation, broadcasts results).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local ServerStorage = game:GetService("ServerStorage")

-- Every table lives under one folder, named by id. Roadmap 1.5d builds all twelve; for now
-- only Config.Lounge.ActiveTableId is built, in its real lounge position and yaw.
local existing = workspace:FindFirstChild(TableBuilder.FolderName)
if existing then
	existing:Destroy()
end
local tables = Instance.new("Folder")
tables.Name = TableBuilder.FolderName
tables.Parent = workspace

local activeId = Config.Lounge.ActiveTableId
local placement = assert(Placement.forTable(activeId), "Config.Lounge.ActiveTableId names no table")
TableBuilder.build(tables, placement, activeId)

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

-- One shadow-casting light over the table so the balls get contact shadows.
local L = Config.Look.TableLight
if L.Enabled then
	local holder = Instance.new("Part")
	holder.Name = "TableLight"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.5, 0.5, 0.5)
	holder.CFrame = CFrame.new(TableBuilder.toWorld(placement, 0, 0, L.HeightInches))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = L.Angle
	light.Brightness = L.Brightness
	light.Range = L.RangeStuds
	light.Color = Color3.fromRGB(L.Color[1], L.Color[2], L.Color[3])
	light.Shadows = true
	light.Parent = holder
	holder.Parent = tables:FindFirstChild(TableBuilder.modelName(activeId)) or workspace
end

print(
	("[8ball] server ready. Table %dx%d in, %.2f studs/in"):format(
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
