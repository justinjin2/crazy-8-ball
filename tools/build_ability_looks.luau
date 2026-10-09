--!nocheck
-- Build the abilities' Edit-mode looks in the open place: what a game script cannot make (a
-- SurfaceAppearance's maps), so the results live in the place and are saved with it. Run in
-- Studio's Edit mode (Studio MCP execute_luau, or the command bar) after the uploads:
--
--   ReplicatedStorage.<Config.Ults.Assets.LooksFolder>.SteelBall
--       the sphere of Config.UI.SteelBallFx.Shell (tools/blender/abilities/steelball_v2.py)
--       wearing a SurfaceAppearance of Config.UI.SteelBallFx.Maps: the green steel ball
--
-- Running it again rebuilds every look, so it is safe to repeat. Returns a report.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
-- Studio's Edit mode keeps a module's first require for the session: require a fresh clone.
local copy = Shared.Config:Clone()
copy.Name = "Config_Fresh"
copy.Parent = Shared
local ok, Config = pcall(require, copy)
copy:Destroy()
assert(ok, Config)

local MAP_KEYS = {
	Color = "ColorMapContent",
	Normal = "NormalMapContent",
	Roughness = "RoughnessMapContent",
	Metalness = "MetalnessMapContent",
}

local report = {}

local folder = ReplicatedStorage:FindFirstChild(Config.Ults.Assets.LooksFolder)
if folder == nil then
	folder = Instance.new("Folder")
	folder.Name = Config.Ults.Assets.LooksFolder
	folder.Parent = ReplicatedStorage
end

-- The first MeshPart in an uploaded Model asset.
local function meshOf(assetId)
	local model = InsertService:LoadAsset(assetId)
	local mesh = model:FindFirstChildWhichIsA("MeshPart", true)
	assert(mesh, "no MeshPart in " .. assetId)
	mesh.Parent = nil
	model:Destroy()
	return mesh
end

local function look(name, assetId, maps)
	local mesh = meshOf(assetId)
	for _, child in mesh:GetChildren() do
		child:Destroy()
	end
	mesh.Name = name
	mesh.TextureID = ""
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	mesh.CastShadow = false
	local sa = Instance.new("SurfaceAppearance")
	for key, prop in MAP_KEYS do
		sa[prop] = Content.fromUri(maps[key])
	end
	sa.Parent = mesh
	local old = folder:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	mesh.Parent = folder
	table.insert(report, ("%s: mesh %s, size %s"):format(name, mesh.MeshId, tostring(mesh.Size)))
end

local F = Config.UI.SteelBallFx
look("SteelBall", F.Shell, F.Maps)

return table.concat(report, "\n")
