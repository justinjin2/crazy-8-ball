--!strict
-- FirePit: the fire pit's fire on this client (Config.Map.FirePit): Roblox's own Fire over the
-- pit's bed and a flickering warm light, and the pit's static flame mesh hidden. It burns by
-- the day cycle: Config.Lighting's Fire intensity in DayCycle's light (out by day, lit at
-- sunset; designer, 2026-09-26). Visual only and local; it needs no input, so it works the
-- same on phone, PC and gamepad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Map
local F = M.FirePit
local L = Config.Lighting

type Pit = { holder: BasePart, fire: Fire, light: PointLight, seed: number }

local FirePit = {}
FirePit.__index = FirePit

export type FirePit = typeof(setmetatable(
	{} :: { pits: { Pit }?, nextLook: number, intensity: number? },
	FirePit
))

function FirePit.new(): FirePit
	return setmetatable(
		{ pits = nil :: { Pit }?, nextLook = 0, intensity = nil :: number? },
		FirePit
	)
end

-- The fire over one placed fire pit (a Map.Props model), or nil while its meshes stream in.
local function build(model: Model): Pit?
	local opaque = model:FindFirstChild(F.Kind .. "__Opaque")
	if not (opaque and opaque:IsA("BasePart")) then
		return nil
	end
	local flame = model:FindFirstChild(F.Kind .. "__Glow")
	if flame and flame:IsA("BasePart") then
		flame.LocalTransparencyModifier = 1 -- the static flame mesh: the Fire replaces it
	end
	local holder = Instance.new("Part")
	holder.Name = "FirePitFire"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(1, 0.2, 1)
	local p = opaque.Position
	holder.CFrame = CFrame.new(p.X, p.Y + opaque.Size.Y / 2 - F.BedDrop, p.Z)

	local fire = Instance.new("Fire")
	fire.Size = F.Fire.Size
	fire.Heat = F.Fire.Heat
	fire.Color = Color3.fromHex(F.Fire.Color)
	fire.SecondaryColor = Color3.fromHex(F.Fire.SecondaryColor)
	fire.Enabled = false
	fire.Parent = holder

	local light = Instance.new("PointLight")
	light.Color = Color3.fromHex(F.Light.Color)
	light.Range = F.Light.Range
	light.Brightness = 0
	light.Shadows = false
	light.Enabled = false
	light.Parent = holder

	holder.Parent = model -- goes with the pit if it streams out
	local pit: Pit = {
		holder = holder :: BasePart,
		fire = fire,
		light = light,
		seed = (p.X * 7.31 + p.Z * 3.17) % 100,
	}
	return pit
end

-- The placed fire pits in Map.Props (props stream in, so they may arrive late).
local function findPits(): { Pit }?
	local map = workspace:FindFirstChild(M.Name)
	local props = map and map:FindFirstChild(M.Props.Placed)
	if not props then
		return nil
	end
	local pits: { Pit } = {}
	for _, model in props:GetChildren() do
		if model:IsA("Model") and model.Name:match("^" .. F.Kind .. "_%d+$") then
			local pit = build(model)
			if pit then
				table.insert(pits, pit)
			end
		end
	end
	return if #pits > 0 then pits else nil
end

--- `now` is os.clock(); `intensity` is the fire's in the day cycle's light (DayCycle.fire).
function FirePit.update(self: FirePit, now: number, intensity: number)
	local pits = self.pits
	if pits == nil then
		if now < self.nextLook then
			return
		end
		self.nextLook = now + L.Cycle.Look
		pits = findPits()
		self.pits = pits
		self.intensity = nil
		if pits == nil then
			return
		end
	end
	assert(pits, "found above")
	local lit = intensity > 0.01
	for _, pit in pits do
		if pit.holder.Parent == nil then
			self.pits = nil -- the pit streamed out or the map was rebuilt: look again
			return
		end
		if intensity ~= self.intensity then
			pit.fire.Enabled = lit
			pit.fire.Size = math.max(2, F.Fire.Size * intensity) -- Roblox's Fire is at least 2
			pit.light.Enabled = lit
		end
		if lit then
			local s = F.Light.FlickerSpeed
			local n = math.noise(now * s, pit.seed)
				+ 0.35 * math.noise(now * s * 2.7, pit.seed + 7.7)
			pit.light.Brightness = F.Light.Brightness
				* intensity
				* math.max(0, 1 + F.Light.Flicker * n)
		end
	end
	self.intensity = intensity
end

return FirePit
