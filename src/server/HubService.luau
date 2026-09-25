--!strict
-- HubService: dresses the hub map at server start from src/shared/HubLayout.luau (generated
-- from assets/hub/Markers.json). The imported meshes (walls, floors, furniture, glow, glass,
-- screens, skyline) are already in the place under workspace.<Config.HubMap.Folder>; this adds
-- what the package keeps as data:
--   Props      every prop copy, cloned from ServerStorage.<PropLibrary> (Roblox clones share
--              the mesh, so repeated props cost little), tinted per placement;
--   Seats      an invisible Seat under every sittable spot, with a Sit prompt (touching a
--              seat never sits you, so walking past a row of armchairs never grabs you);
--   Lights     the thirty lights (sixteen table pendants plus the room);
--   Collision  plain invisible boxes and the stair ramp: the imported meshes never collide.
-- Server-side and anchored, so it replicates (and streams) to every client like the map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HubLayout = require(Shared:WaitForChild("HubLayout"))
local Strings = require(Shared:WaitForChild("Strings"))

local H = Config.HubMap

local HubService = {}

local function hex(h: string): Color3
	return Color3.fromRGB(
		tonumber(h:sub(2, 3), 16) :: number,
		tonumber(h:sub(4, 5), 16) :: number,
		tonumber(h:sub(6, 7), 16) :: number
	)
end

local function folderIn(parent: Instance, name: string): Folder
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function quiet(p: BasePart)
	p.Anchored = true
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
end

-- Every copy of every prop. A master's own CFrame is its offset from the library origin, so a
-- copy is the placement's frame times that; scale (the podium's plinths, the towers) stretches
-- both the offset and the size. The masters are turned a half turn about Y by the importer,
-- which keeps each local axis on a world axis, so the scale applies axis for axis.
local function buildProps(parent: Instance, library: Instance)
	local folder = folderIn(parent, "Props")
	local masters: { [string]: { BasePart } } = {}
	for name, spec in HubLayout.Masters do
		local parts = {}
		for _, partName in spec.parts do
			local part = library:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") then
				table.insert(parts, part)
			else
				warn(("[8ball] hub prop %s: no %s in the prop library"):format(name, partName))
			end
		end
		masters[name] = parts
	end
	local made = 0
	for _, p in HubLayout.Placements do
		local spec = HubLayout.Masters[p.prop]
		local parts = masters[p.prop]
		if not spec or not parts then
			continue
		end
		local base = CFrame.new(p.x, p.y, p.z) * CFrame.Angles(0, math.rad(p.yaw), 0)
		local scale = Vector3.new(p.sx, p.sy, p.sz)
		local holder: Instance = folder
		if p.name then -- a pendant: one Model per table, so the client can hide it as a whole
			local model = Instance.new("Model")
			model.Name = p.name
			model.Parent = folder
			holder = model
		end
		for _, master in parts do
			local copy = master:Clone()
			local rel = master.CFrame
			if scale ~= Vector3.one then
				rel = CFrame.new(rel.Position * scale) * rel.Rotation
				copy.Size = master.Size * scale
			end
			copy.CFrame = base * rel
			copy.Anchored = true
			if p.tint and (spec.tint or p.prop:sub(1, 6) == "Tower_") then
				local look = copy:FindFirstChildOfClass("SurfaceAppearance")
				if look and (not spec.tint or master.Name:find("_Fabric")) then
					look.Color = hex(p.tint)
				end
			end
			copy.Parent = holder
		end
		made += 1
	end
	return made
end

-- Sitting is a prompt, not a touch: rows of armchairs line every walkway.
local function buildSeats(parent: Instance)
	local folder = folderIn(parent, "Seats")
	local size = Vector3.new(H.SeatSize[1], H.SeatSize[2], H.SeatSize[3])
	for i, s in HubLayout.Seats do
		local seat = Instance.new("Seat")
		seat.Name = ("Seat_%03d"):format(i)
		quiet(seat)
		seat.CanCollide = false
		seat.Size = size
		seat.CFrame = CFrame.new(s.x, s.y - H.SeatDrop, s.z) * CFrame.Angles(0, math.rad(s.yaw), 0)
		seat.Parent = folder
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = Strings.Hub.Sit
		prompt.MaxActivationDistance = H.SitDistance
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = 0
		prompt.Parent = seat
		prompt.Triggered:Connect(function(player: Player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 and not seat.Occupant and not humanoid.Sit then
				seat:Sit(humanoid)
			end
		end)
		-- A taken seat hides its prompt from everyone.
		seat:GetPropertyChangedSignal("Occupant"):Connect(function()
			prompt.Enabled = seat.Occupant == nil
		end)
	end
end

local function buildLights(parent: Instance)
	local folder = folderIn(parent, "Lights")
	for _, l in HubLayout.Lights do
		local part = Instance.new("Part")
		part.Name = l.name
		quiet(part)
		part.CanCollide = false
		local t = H.LightThickness
		part.Size = if l.kind == "SurfaceLight"
			then Vector3.new(l.w, t, l.d)
			else Vector3.new(t, t, t)
		-- Every light in the hub points down or has no direction, so the part lies flat and
		-- a SurfaceLight or SpotLight shines from its Bottom face.
		part.CFrame = CFrame.new(l.x, l.y, l.z)
		local light: Light
		if l.kind == "SurfaceLight" then
			local sl = Instance.new("SurfaceLight")
			sl.Face = Enum.NormalId.Bottom
			sl.Angle = l.angle
			light = sl
		elseif l.kind == "SpotLight" then
			local sp = Instance.new("SpotLight")
			sp.Face = Enum.NormalId.Bottom
			sp.Angle = l.angle
			light = sp
		else
			light = Instance.new("PointLight")
		end
		light.Brightness = l.brightness;
		(light :: any).Range = l.range
		light.Color = hex(l.colour)
		light.Shadows = l.shadows
		light.Parent = part
		part.Parent = folder
	end
end

-- The wedge rises towards its own +Z (its back); turn it to rise the way the data says.
local RISE_YAW = { ["+Z"] = 0, ["-Z"] = 180, ["+X"] = 90, ["-X"] = -90 }

local function buildCollision(parent: Instance)
	local folder = folderIn(parent, "Collision")
	for _, b in HubLayout.Collision do
		local part: BasePart
		local yaw = 0
		if b.shape == "Wedge" then
			part = Instance.new("WedgePart")
			yaw = RISE_YAW[b.rises or "+Z"] or 0
		else
			part = Instance.new("Part")
		end
		part.Name = b.name
		quiet(part)
		part.CanCollide = true
		if yaw == 90 or yaw == -90 then
			part.Size = Vector3.new(b.sz, b.sy, b.sx)
		else
			part.Size = Vector3.new(b.sx, b.sy, b.sz)
		end
		part.CFrame = CFrame.new(b.x, b.y, b.z) * CFrame.Angles(0, math.rad(yaw), 0)
		part.Parent = folder
	end
end

--- Build the data-driven half of the hub. Safe to call once at server start; without the
--- imported map (a bare test place) it warns and builds nothing.
function HubService.start()
	local map = workspace:FindFirstChild(H.Folder)
	if not map then
		warn(("[8ball] no workspace.%s: the hub map is not in this place"):format(H.Folder))
		return
	end
	local library = ServerStorage:FindFirstChild(H.PropLibrary)
	local props = 0
	if library then
		props = buildProps(map, library)
	else
		warn(("[8ball] no ServerStorage.%s: the hub has no props"):format(H.PropLibrary))
	end
	buildSeats(map)
	buildLights(map)
	buildCollision(map)
	print(
		("[8ball] hub dressed: %d props, %d seats, %d lights, %d collision boxes"):format(
			props,
			#HubLayout.Seats,
			#HubLayout.Lights,
			#HubLayout.Collision
		)
	)
end

return HubService
