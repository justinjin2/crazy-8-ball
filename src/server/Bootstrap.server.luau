--!strict
-- Server bootstrap. For the solo MVP the server only builds the table; later it becomes
-- the shot authority (validates inputs, runs Simulation, broadcasts results).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local ServerStorage = game:GetService("ServerStorage")

if workspace:FindFirstChild("PoolTable") then
	workspace.PoolTable:Destroy()
end
TableBuilder.build(workspace)

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
	holder.CFrame = CFrame.new(TableBuilder.toWorld(0, 0, L.HeightInches))
	local light = Instance.new("SpotLight")
	light.Face = Enum.NormalId.Bottom
	light.Angle = L.Angle
	light.Brightness = L.Brightness
	light.Range = L.RangeStuds
	light.Color = Color3.fromRGB(L.Color[1], L.Color[2], L.Color[3])
	light.Shadows = true
	light.Parent = holder
	holder.Parent = workspace:FindFirstChild("PoolTable") or workspace
end

print(
	("[8ball] server ready. Table %dx%d in, %.2f studs/in"):format(
		Config.Table.LengthInches,
		Config.Table.WidthInches,
		Config.Table.StudsPerInch
	)
)
