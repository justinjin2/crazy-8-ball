--!strict
-- HalloweenMap.Assets (Halloween 2026, hw-map lane): the event's meshes. One uploaded Model
-- (assets/halloween/map/gen_props.py's .glb: every prop, one palette texture) is loaded once
-- on the server with InsertService (the place and the asset are both the group's; the
-- AbilityAssets pattern), split into one template Model per prop ("Pumpkin", "DeadTree", ...)
-- with its pivot at the prop's own origin, and put in ReplicatedStorage[Config.HalloweenMap
-- .Assets.Folder] for the server's builders and the clients (the candy). Pieces named "*.Glow"
-- become Neon in their prop's Glow colour. Every piece touches nothing and casts no shadow.
-- A load that keeps failing is warned about; every user of a template has a fallback shape.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local A = Config.HalloweenMap.Assets

local Assets = {}

local folder: Folder? = nil
local state: "Idle" | "Loading" | "Ready" | "Failed" = "Idle"
local ready = Instance.new("BindableEvent")

local function holder(): Folder
	if folder == nil then
		local existing = ReplicatedStorage:FindFirstChild(A.Folder)
		if existing and existing:IsA("Folder") then
			folder = existing
		else
			local f = Instance.new("Folder")
			f.Name = A.Folder
			f.Parent = ReplicatedStorage
			folder = f
		end
	end
	return folder :: Folder
end

-- Split the loaded model into a template per prop.
local function build(loaded: Instance)
	local target = holder()
	local props: { [string]: Model } = {}
	for _, d in loaded:GetDescendants() do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") then
			d:Destroy()
		end
	end
	for _, part in loaded:GetDescendants() do
		if not part:IsA("BasePart") then
			continue
		end
		local prop, piece = part.Name:match("^([%w]+)%.([%w]+)$")
		if prop == nil or A.Origins[prop] == nil then
			continue
		end
		local model = props[prop]
		if not props[prop] then
			model = Instance.new("Model")
			model.Name = prop
			-- The .glb's origin for this prop (Blender +X arrives as Roblox -X).
			model.WorldPivot = CFrame.new(-A.Origins[prop], 0, 0)
			props[prop] = model
		end
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		part.Name = piece :: string
		if piece == "Glow" then
			local c = A.Glow[prop] or { 255, 190, 60 }
			part.Material = Enum.Material.Neon
			part.Color = Color3.fromRGB(c[1], c[2], c[3])
			if part:IsA("MeshPart") then
				part.TextureID = ""
			end
		end
		part.Parent = model
	end
	for name, model in props do
		local old = target:FindFirstChild(name)
		if old then
			old:Destroy()
		end
		model.Parent = target
	end
end

--- Load the meshes (once, on the server; in the background).
function Assets.start()
	if state ~= "Idle" or A.Model <= 0 then
		return
	end
	state = "Loading"
	task.spawn(function()
		local lastError = "?"
		for attempt = 1, math.max(A.LoadRetries, 1) do
			local ok, result = pcall(InsertService.LoadAsset, InsertService, A.Model)
			if ok and result then
				local built, err = pcall(function()
					build(result)
				end)
				result:Destroy()
				if built then
					state = "Ready"
					ready:Fire()
					return
				end
				lastError = tostring(err)
			else
				lastError = tostring(result)
			end
			if attempt < A.LoadRetries then
				task.wait(A.LoadRetrySeconds)
			end
		end
		state = "Failed"
		ready:Fire()
		warn(
			("[HalloweenMap] the event's meshes (asset %d) did not load: %s; fallback shapes"):format(
				A.Model,
				lastError
			)
		)
	end)
end

--- Wait (up to Assets.WaitSeconds) for the meshes; true once they are ready.
function Assets.wait(): boolean
	if state == "Loading" then
		local done = false
		local conn = ready.Event:Connect(function()
			done = true
		end)
		local deadline = os.clock() + A.WaitSeconds
		while not done and os.clock() < deadline do
			task.wait(0.1)
		end
		conn:Disconnect()
	end
	return state == "Ready"
end

--- A fresh copy of prop `name`'s template (pivot at its origin), or nil while the meshes are
--- not loaded (the caller builds its fallback).
function Assets.clone(name: string): Model?
	if state ~= "Ready" then
		return nil
	end
	local template = holder():FindFirstChild(name)
	return if template and template:IsA("Model") then template:Clone() else nil
end

--- A prop's copy scaled by `scale` and placed with its origin at `at`, parented to `parent`.
function Assets.place(name: string, at: CFrame, scale: number?, parent: Instance?): Model?
	local model = Assets.clone(name)
	if model == nil then
		return nil
	end
	if scale and scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(at)
	model.Parent = parent
	return model
end

return Assets
