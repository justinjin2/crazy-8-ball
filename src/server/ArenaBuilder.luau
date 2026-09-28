--!strict
-- ArenaBuilder: the arena's room (designer, 2026-09-28, after the reference: one table on a
-- dark carpet inside a low wall with a glowing green strip, two armchairs, two broadcast
-- cameras, one lamp over the table). A PLACEHOLDER built from parts at run time; when the art
-- exists it goes in ServerStorage as a Model named ArenaMap (floor at Y = 0, the table spot
-- at the origin) and is used instead. Numbers: Config.Arena.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local A = Config.Arena
local R = A.Room
local ArenaBuilder = {}
ArenaBuilder.FolderName = "Arena"
ArenaBuilder.TemplateName = "ArenaMap"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: { number },
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = rgb(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

--- Take away everything the rooftop brought: the map, the sea, the sky and its effects, the
--- entrance spawn. The table models in ServerStorage stay (the arena's table uses them).
function ArenaBuilder.clearHub()
	local map = workspace:FindFirstChild(Config.Map.Name)
	if map then
		map:Destroy()
	end
	workspace.Terrain:Clear()
	for _, child in workspace:GetChildren() do
		if child:IsA("SpawnLocation") then
			child:Destroy()
		end
	end
	for _, child in Lighting:GetChildren() do
		if
			child:IsA("Sky")
			or child:IsA("Atmosphere")
			or child:IsA("PostEffect")
			or child:IsA("Clouds")
		then
			child:Destroy()
		end
	end
	local L = A.Lighting
	Lighting.ClockTime = L.ClockTime
	Lighting.Brightness = L.Brightness
	Lighting.Ambient = rgb(L.Ambient)
	Lighting.OutdoorAmbient = rgb(L.OutdoorAmbient)
	Lighting.EnvironmentDiffuseScale = 0
	Lighting.EnvironmentSpecularScale = 0.3
	Lighting.GlobalShadows = true
	Lighting.FogEnd = 100000
end

-- One straight run of the low wall from (x0, z0) to (x1, z1), with its glowing strip on top
-- and a lit board on its inside face.
local function wall(
	folder: Instance,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	boards: boolean
)
	local a, b = Vector3.new(x0, 0, z0), Vector3.new(x1, 0, z1)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local mid = (a + b) / 2
	local look = CFrame.lookAt(mid, b)
	local body = part(
		folder,
		"Wall",
		Vector3.new(R.WallThickness, R.WallHeight, length + R.WallThickness * 0.5),
		look * CFrame.new(0, R.WallHeight / 2, 0),
		R.WallColor,
		Enum.Material.Metal
	)
	body.CastShadow = false
	local strip = part(
		folder,
		"Strip",
		Vector3.new(R.WallThickness * 0.6, R.StripHeight, length + R.WallThickness * 0.5),
		look * CFrame.new(0, R.WallHeight + R.StripHeight / 2, 0),
		R.StripColor,
		Enum.Material.Neon
	)
	strip.CastShadow = false
	if boards then
		-- Inside means toward the room's centre (the origin).
		local side = if (look.RightVector):Dot(-mid) > 0 then 1 else -1
		local board = part(
			folder,
			"Board",
			Vector3.new(0.1, R.WallHeight * 0.45, length * 0.8),
			look * CFrame.new(side * (R.WallThickness / 2 + 0.05), R.WallHeight * 0.62, 0),
			R.PanelColor,
			Enum.Material.Neon
		)
		board.Transparency = 0.35
		board.CastShadow = false
	end
end

local function chair(folder: Instance, x: number, z: number, yaw: number)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = Instance.new("Model")
	model.Name = "Armchair"
	model.Parent = folder
	local c = A.ChairColor
	part(
		model,
		"Seat",
		Vector3.new(3.6, 1.6, 3.2),
		base * CFrame.new(0, 0.8, 0),
		c,
		Enum.Material.Fabric
	)
	part(
		model,
		"Back",
		Vector3.new(3.6, 3.2, 0.8),
		base * CFrame.new(0, 2.2, 1.2),
		c,
		Enum.Material.Fabric
	)
	part(
		model,
		"ArmL",
		Vector3.new(0.7, 2.2, 3.2),
		base * CFrame.new(-1.8, 1.1, 0),
		c,
		Enum.Material.Fabric
	)
	part(
		model,
		"ArmR",
		Vector3.new(0.7, 2.2, 3.2),
		base * CFrame.new(1.8, 1.1, 0),
		c,
		Enum.Material.Fabric
	)
end

local function camera(folder: Instance, x: number, z: number, yaw: number)
	local base = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yaw), 0)
	local model = Instance.new("Model")
	model.Name = "BroadcastCamera"
	model.Parent = folder
	local dark = { 20, 20, 22 }
	for i = 0, 2 do
		local angle = i * math.pi * 2 / 3
		local foot = base * CFrame.new(math.cos(angle) * 1.4, 0, math.sin(angle) * 1.4)
		local top = base * CFrame.new(0, 3.2, 0)
		local mid = (foot.Position + top.Position) / 2
		local leg = part(
			model,
			"Leg",
			Vector3.new(0.18, 0.18, (top.Position - foot.Position).Magnitude),
			CFrame.lookAt(mid, top.Position),
			dark,
			Enum.Material.Metal
		)
		leg.CastShadow = false
	end
	part(
		model,
		"Pole",
		Vector3.new(0.3, 1.2, 0.3),
		base * CFrame.new(0, 3.8, 0),
		dark,
		Enum.Material.Metal
	)
	part(
		model,
		"Body",
		Vector3.new(1.2, 1.1, 2.4),
		base * CFrame.new(0, 4.9, 0),
		dark,
		Enum.Material.Metal
	)
	local lens = part(
		model,
		"Lens",
		Vector3.new(0.9, 0.9, 1.1),
		base * CFrame.new(0, 4.9, -1.6),
		{ 8, 8, 10 },
		Enum.Material.Glass
	)
	lens.Shape = Enum.PartType.Cylinder
	lens.CFrame = lens.CFrame * CFrame.Angles(0, math.rad(90), 0)
end

--- Build the room (or the designer's ArenaMap) under a fresh Workspace.Arena. Returns it.
function ArenaBuilder.build(): Instance
	local old = workspace:FindFirstChild(ArenaBuilder.FolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = ArenaBuilder.FolderName
	local template = ServerStorage:FindFirstChild(ArenaBuilder.TemplateName)
	if template and template:IsA("Model") then
		template:Clone().Parent = folder
	else
		-- The floor: a dark carpet, its top at Y = 0 where the table stands.
		local floor = part(
			folder,
			"Floor",
			Vector3.new(
				2 * (R.HalfLength + R.WallThickness),
				R.FloorThickness,
				2 * (R.HalfWidth + R.WallThickness)
			),
			CFrame.new(0, -R.FloorThickness / 2, 0),
			R.FloorColor,
			Enum.Material.Fabric
		)
		pcall(function()
			floor.Material = (Enum.Material :: any).Carpet
		end)
		-- The low wall: four straight runs and four rounded corners.
		local hx, hz, r = R.HalfLength, R.HalfWidth, R.CornerRadius
		wall(folder, -hx + r, -hz, hx - r, -hz, true)
		wall(folder, -hx + r, hz, hx - r, hz, true)
		wall(folder, -hx, -hz + r, -hx, hz - r, true)
		wall(folder, hx, -hz + r, hx, hz - r, true)
		local steps = 5
		for _, corner in
			{
				{ hx - r, hz - r, 0 },
				{ -hx + r, hz - r, 90 },
				{ -hx + r, -hz + r, 180 },
				{ hx - r, -hz + r, 270 },
			}
		do
			for i = 0, steps - 1 do
				local a0 = math.rad(corner[3] + 90 * i / steps)
				local a1 = math.rad(corner[3] + 90 * (i + 1) / steps)
				wall(
					folder,
					corner[1] + r * math.cos(a0),
					corner[2] + r * math.sin(a0),
					corner[1] + r * math.cos(a1),
					corner[2] + r * math.sin(a1),
					false
				)
			end
		end
		for _, c in A.Chairs do
			chair(folder, c.X, c.Z, c.Yaw)
		end
		for _, c in A.Cameras do
			camera(folder, c.X, c.Z, c.Yaw)
		end
	end
	-- The lamp over the table, the room's only strong light.
	local L = A.Lighting.Lamp
	local lamp = Instance.new("Part")
	lamp.Name = "Lamp"
	lamp.Anchored = true
	lamp.CanCollide = false
	lamp.CanQuery = false
	lamp.CanTouch = false
	lamp.Transparency = 1
	lamp.Size = Vector3.new(1, 1, 1)
	lamp.CFrame = CFrame.new(A.Table.X, A.Table.Y + L.Height, A.Table.Z)
	lamp.Parent = folder
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Brightness = L.Brightness
	spot.Range = L.Range
	spot.Angle = L.Angle
	spot.Color = rgb(L.Color)
	spot.Shadows = true
	spot.Parent = lamp
	-- Arrive in front of the table, facing it.
	local S = A.Spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ArenaSpawn"
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = CFrame.new(S.X, 0.1, S.Z) * CFrame.Angles(0, math.rad(S.Yaw), 0)
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	spawn.Parent = folder
	folder.Parent = workspace
	return folder
end

return ArenaBuilder
