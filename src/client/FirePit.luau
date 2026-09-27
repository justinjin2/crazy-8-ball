--!strict
-- FirePit: the fire pit's fire on this client (Config.Map.FirePit): our own effect rather than
-- Roblox's stock Fire. Cel-shaded flame licks from a flipbook, rising embers, a soft glow, a
-- little smoke and a flickering light over the pit's bed; the pit's static flame mesh is hidden.
-- It burns by the day cycle: Config.Lighting's Fire intensity at DayCycle's blend (out by day,
-- lit at sunset; designer, 2026-09-26). Visual only and local; it needs no input, so it works
-- the same on phone, PC and gamepad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local M = Config.Map
local F = M.FirePit
local L = Config.Lighting

type Pit = {
	holder: BasePart,
	emitters: { { emitter: ParticleEmitter, rate: number } },
	light: PointLight,
	seed: number,
}

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

local function range(r: any): NumberRange
	if type(r) == "number" then
		return NumberRange.new(r)
	end
	return NumberRange.new(r[1], r[2])
end

-- A size over a particle's life: its range (studs) as a middle value and an envelope.
local function sizes(r: any, grow: { { number } }): NumberSequence
	local lo, hi = if type(r) == "number" then r else r[1], if type(r) == "number" then r else r[2]
	local mid, env = (lo + hi) / 2, (hi - lo) / 2
	local keys = {}
	for _, k in grow do
		table.insert(keys, NumberSequenceKeypoint.new(k[1], mid * k[2], env * k[2]))
	end
	return NumberSequence.new(keys)
end

local function fades(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

local function emitter(parent: Instance, image: string): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = image
	e.EmissionDirection = Enum.NormalId.Top
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.LightInfluence = 0
	e.Rate = 0
	e.Enabled = false
	e.Parent = parent
	return e
end

-- The effect over one placed fire pit (a Map.Props model), or nil while its meshes stream in.
local function build(model: Model): Pit?
	local opaque = model:FindFirstChild(F.Kind .. "__Opaque")
	if not (opaque and opaque:IsA("BasePart")) then
		return nil
	end
	local flame = model:FindFirstChild(F.Kind .. "__Glow")
	if flame and flame:IsA("BasePart") then
		flame.LocalTransparencyModifier = 1 -- the static flame mesh: the effect replaces it
	end
	local holder = Instance.new("Part")
	holder.Name = "FirePitFire"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.CastShadow = false
	holder.Transparency = 1
	holder.Size = Vector3.new(F.BedRadius * 2, 0.1, F.BedRadius * 2)
	local p = opaque.Position
	holder.CFrame = CFrame.new(p.X, p.Y + opaque.Size.Y / 2 - F.BedDrop + F.Lift, p.Z)
	local list: { { emitter: ParticleEmitter, rate: number } } = {}

	-- Flames: each particle loops the lick flipbook from a random frame, hovering over the bed.
	local flames = emitter(holder, F.Flames.Image)
	flames.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid8x8
	flames.FlipbookMode = Enum.ParticleFlipbookMode.Loop
	flames.FlipbookFramerate = range(F.Flames.Framerate)
	flames.FlipbookStartRandom = true
	flames.LightEmission = F.Flames.LightEmission
	flames.Lifetime = range(F.Flames.Lifetime)
	flames.Speed = range(F.Flames.Speed)
	flames.SpreadAngle = Vector2.new(6, 6)
	flames.Rotation = NumberRange.new(-12, 12)
	flames.Size = sizes(F.Flames.Size, { { 0, 0.85 }, { 0.5, 1 }, { 1, 0.9 } })
	flames.Transparency = fades({ { 0, 1 }, { 0.12, 0 }, { 0.85, 0 }, { 1, 1 } })
	flames.ZOffset = 0.4
	table.insert(list, { emitter = flames, rate = F.Flames.Rate })

	-- Embers: hot sparks rising and twinkling out.
	local embers = emitter(holder, F.Embers.Image)
	embers.LightEmission = 1
	embers.Color = ColorSequence.new(Color3.fromHex(F.Embers.Color))
	embers.Lifetime = range(F.Embers.Lifetime)
	embers.Speed = range(F.Embers.Speed)
	embers.SpreadAngle = Vector2.new(F.Embers.Spread, F.Embers.Spread)
	embers.Drag = 0.6
	embers.Size = sizes(F.Embers.Size, { { 0, 1 }, { 1, 0.4 } })
	embers.Transparency = fades({ { 0, 0 }, { 0.3, 0.35 }, { 0.5, 0 }, { 0.75, 0.45 }, { 1, 1 } })
	embers.ZOffset = 0.6
	table.insert(list, { emitter = embers, rate = F.Embers.Rate })

	-- A soft warm glow over the bed, behind the flames.
	local glow = emitter(holder, F.Glow.Image)
	glow.LightEmission = 1
	glow.Color = ColorSequence.new(Color3.fromHex(F.Glow.Color))
	glow.Lifetime = range(F.Glow.Lifetime)
	glow.Speed = NumberRange.new(0)
	glow.Size = sizes(F.Glow.Size, { { 0, 0.85 }, { 0.5, 1 }, { 1, 0.9 } })
	glow.Transparency =
		fades({ { 0, 1 }, { 0.35, F.Glow.Transparency }, { 0.7, F.Glow.Transparency }, { 1, 1 } })
	glow.ZOffset = -0.5
	table.insert(list, { emitter = glow, rate = F.Glow.Rate })

	-- A little smoke, lit by the scene, growing and thinning as it climbs.
	local smoke = emitter(holder, F.Smoke.Image)
	smoke.LightInfluence = 1
	smoke.Color = ColorSequence.new(Color3.fromHex(F.Smoke.Color))
	smoke.Lifetime = range(F.Smoke.Lifetime)
	smoke.Speed = range(F.Smoke.Speed)
	smoke.SpreadAngle = Vector2.new(10, 10)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.Size = sizes(F.Smoke.Size, { { 0, 0.35 }, { 1, 1 } })
	smoke.Transparency = fades({ { 0, 1 }, { 0.2, F.Smoke.Transparency }, { 1, 1 } })
	table.insert(list, { emitter = smoke, rate = F.Smoke.Rate })

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
		emitters = list,
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

--- `now` is os.clock(); `blend` is the day cycle's (0 day, 1 sunset; DayCycle.blend).
function FirePit.update(self: FirePit, now: number, blend: number)
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
	local day, sunset = L.Day.Fire.Intensity, L.Sunset.Fire.Intensity
	local intensity = day + (sunset - day) * blend
	local lit = intensity > 0.01
	for _, pit in pits do
		if pit.holder.Parent == nil then
			self.pits = nil -- the pit streamed out or the map was rebuilt: look again
			return
		end
		if intensity ~= self.intensity then
			for _, e in pit.emitters do
				e.emitter.Rate = e.rate * intensity
				e.emitter.Enabled = lit
			end
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
