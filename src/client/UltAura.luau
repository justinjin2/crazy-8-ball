--!strict
-- UltAura: the JoJo-style aura round the avatar on the spin screen's stage (UltStage;
-- docs/prompts/ULTIMATES_PROMPT.md section 9.2). ParticleEmitters (ViewportFrames draw no
-- particles, which is why the stage is a real room): the AuraFlame flipbook (Grid4x4, 16
-- frames, OneShot, white and tinted) rising from the feet in a thick layer behind the body and
-- a thinner one in front, and wisps rising off the body, in the equipped ult's rarity colour
-- and growing with its rarity (Config.UI.UltScreen.Aura.Tiers): Common small and grey,
-- Uncommon green, Rare blue, Epic purple with sparks, Legendary gold with turning rays behind,
-- Mythic red over black flames with crackling arcs. A soft light in the same colour sits on the
-- body. A spin landing bursts it into the new colour (sparks thrown out, the flames running
-- hot for a moment).
--
-- Client only, built into the stage's model; every part anchored, non-colliding and invisible.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Quality = require(script.Parent.Quality)

local A = Config.UI.UltScreen.Aura
local K = Config.UI.Kit
local ART = K.Art
local RARITY: { [string]: { number } } = K.Rarity :: any
local TIERS: { [string]: any } = A.Tiers :: any

local UltAura = {}
UltAura.__index = UltAura

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function range(pair: { number }, k: number?): NumberRange
	local s = k or 1
	return NumberRange.new(pair[1] * s, pair[2] * s)
end

-- An invisible anchored part the emitters take their shape from.
local function holder(parent: Instance, name: string): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = parent
	return part
end

-- A flipbook flame emitter (the tier fills in its colour, size and rate).
local function flames(parent: Part, name: string, zOffset: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	e.Texture = ART.AuraFlame
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.EmissionDirection = Enum.NormalId.Top
	e.Lifetime = range(A.LifetimeSeconds)
	e.SpreadAngle = Vector2.new(10, 10)
	e.Rotation = NumberRange.new(-12, 12)
	e.RotSpeed = NumberRange.new(-20, 20)
	e.LightEmission = A.LightEmission
	e.LightInfluence = 0
	e.Brightness = A.Brightness
	e.ZOffset = zOffset
	e.Drag = 1
	e.Rate = 0
	e.Parent = parent
	return e
end

--- The aura for an avatar standing with its feet at `feet` (the floor under it, facing the
--- camera), `bodyHeight` studs tall, built into `parent`. Call set(rarity) to light it.
function UltAura.new(parent: Instance, feet: CFrame, bodyHeight: number): any
	local self: any = setmetatable({}, UltAura)
	self.feetCFrame = feet
	self.bodyHeight = math.max(2, bodyHeight)
	self.rarity = nil :: string?
	self.alive = true
	self.boostToken = 0
	self.rng = Random.new()
	self.arcsOn = false
	self.arcClock = 0

	local folder = Instance.new("Folder")
	folder.Name = "Aura"
	folder.Parent = parent
	self.folder = folder
	local feetPart = holder(folder, "Feet")
	local bodyPart = holder(folder, "Body")
	self.feetPart, self.bodyPart = feetPart, bodyPart

	self.back = flames(feetPart, "Back", A.BackZOffset)
	self.front = flames(feetPart, "Front", A.FrontZOffset)
	self.wisps = flames(bodyPart, "Wisps", A.BackZOffset)
	self.wisps.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	self.dark = flames(feetPart, "Dark", A.BackZOffset - 0.4)
	self.dark.LightEmission = 0
	self.dark.Brightness = 1

	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = ART.Spark
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.SpreadAngle = Vector2.new(60, 60)
	sparks.Speed = range(A.SparkSpeed)
	sparks.Lifetime = range(A.SparkLifetimeSeconds)
	sparks.Acceleration = Vector3.new(0, -6, 0)
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Brightness = 3
	sparks.ZOffset = 0.8
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, A.SparkSizeStuds),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Rate = 0
	sparks.Parent = bodyPart
	self.sparks = sparks

	local rays = Instance.new("ParticleEmitter")
	rays.Name = "Rays"
	rays.Texture = ART.Rays
	rays.Shape = Enum.ParticleEmitterShape.Box
	rays.EmissionDirection = Enum.NormalId.Top
	rays.Speed = NumberRange.new(0)
	rays.Lifetime = NumberRange.new(A.RaysLifetimeSeconds)
	rays.Rotation = NumberRange.new(0, 360)
	rays.RotSpeed = NumberRange.new(A.RaysRotSpeed)
	rays.LightEmission = 1
	rays.LightInfluence = 0
	rays.ZOffset = -4
	rays.LockedToPart = true
	rays.Size = NumberSequence.new(A.RaysSizeStuds)
	rays.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, A.RaysTransparency),
		NumberSequenceKeypoint.new(0.75, A.RaysTransparency),
		NumberSequenceKeypoint.new(1, 1),
	})
	rays.Rate = 0
	local raysHolder = holder(folder, "RaysAt")
	raysHolder.Size = Vector3.new(0.1, 0.1, 0.1)
	rays.Parent = raysHolder
	self.rays, self.raysHolder = rays, raysHolder

	local burst = Instance.new("ParticleEmitter")
	burst.Name = "Burst"
	burst.Texture = ART.Spark
	burst.Shape = Enum.ParticleEmitterShape.Sphere
	burst.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	burst.Speed = range(A.BurstSpeed)
	burst.Lifetime = range(A.SparkLifetimeSeconds, 1.3)
	burst.Drag = 3
	burst.RotSpeed = NumberRange.new(-240, 240)
	burst.LightEmission = 1
	burst.LightInfluence = 0
	burst.Brightness = 3
	burst.ZOffset = 1
	burst.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, A.SparkSizeStuds * 2),
		NumberSequenceKeypoint.new(1, 0),
	})
	burst.Enabled = false
	burst.Parent = bodyPart
	self.burstEmitter = burst

	local light = Instance.new("PointLight")
	light.Name = "Glow"
	light.Range = A.LightRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = bodyPart
	self.light = light

	-- The arcs: zig-zags of beams between chained attachments, re-drawn every ArcEverySeconds.
	local arcHolder = holder(folder, "Arcs")
	self.arcHolder = arcHolder
	self.arcs = {} :: { { attachments: { Attachment }, beams: { Beam } } }
	for _ = 1, A.ArcCount do
		local attachments: { Attachment } = {}
		local beams: { Beam } = {}
		for i = 1, A.ArcPoints do
			local attachment = Instance.new("Attachment")
			attachment.Parent = arcHolder
			attachments[i] = attachment
			if i > 1 then
				local beam = Instance.new("Beam")
				beam.Attachment0 = attachments[i - 1]
				beam.Attachment1 = attachment
				beam.Width0 = A.ArcWidthStuds
				beam.Width1 = A.ArcWidthStuds
				beam.FaceCamera = true
				beam.LightEmission = 1
				beam.LightInfluence = 0
				beam.Segments = 1
				beam.Color = ColorSequence.new(rgb(A.ArcColor))
				beam.Transparency = NumberSequence.new(0)
				beam.Enabled = false
				beam.Parent = arcHolder
				table.insert(beams, beam)
			end
		end
		table.insert(self.arcs, { attachments = attachments, beams = beams })
	end
	self.arcLoop = nil :: RBXScriptConnection?

	self:place()
	return self
end

-- Size and place the holders for the current tier's scale.
function UltAura.place(self: any, scale: number?)
	local k = scale or 1
	local feet: CFrame = self.feetCFrame
	local h: number = self.bodyHeight
	local width = A.FeetWidth * k
	self.feetPart.Size = Vector3.new(width, 0.2, width * 0.6)
	self.feetPart.CFrame = feet * CFrame.new(0, 0.1, 0)
	self.bodyPart.Size = Vector3.new(A.BodyWidth * k, h * 0.8, A.BodyDepth * k)
	self.bodyPart.CFrame = feet * CFrame.new(0, h * 0.5, 0)
	self.raysHolder.CFrame = feet * CFrame.new(0, h * 0.62, -0.6)
	self.arcHolder.CFrame = feet * CFrame.new(0, h * 0.5, 0)
end

-- The flames' size, fade and colour for a tier.
local function paintFlames(e: ParticleEmitter, colour: Color3, size: number, fade: number)
	e.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.35), colour)
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size * 0.55),
		NumberSequenceKeypoint.new(0.4, size),
		NumberSequenceKeypoint.new(1, size * 0.3),
	})
	local t = math.clamp(fade, 0, 0.95)
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, t),
		NumberSequenceKeypoint.new(0.7, math.min(0.98, t + 0.2)),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- The emitters' rates for a tier, times `boost` (a burst runs them hotter for a moment).
function UltAura.setRates(self: any, tier: any, boost: number)
	boost *= Quality.rate() -- Lower effects (Settings, GUI lane)
	local rate = tier.Rate * boost
	self.back.Rate = rate
	self.front.Rate = rate * A.FrontShare
	self.wisps.Rate = rate * 0.5
	self.dark.Rate = if tier.Dark then rate * 0.7 else 0
	self.sparks.Rate = (tier.Sparks or 0) * boost
	self.rays.Rate = if tier.Rays then A.RaysRate else 0
end

--- Light the aura in a rarity's colour and size. `burst` throws sparks out and runs it hot for
--- a moment (a spin landing).
function UltAura.set(self: any, rarity: string?, burst: boolean?)
	if not self.alive then
		return
	end
	local key = if rarity and TIERS[rarity] then rarity else "Common"
	local tier = TIERS[key]
	local colour = if tier.Color then rgb(tier.Color) else rgb(RARITY[key] or RARITY.Default)
	local k = tier.Scale
	self.rarity = key
	self:place(k)
	local size = A.SizeStuds * k
	local rise = range(A.RiseSpeed, k)
	for _, e in { self.back, self.front, self.wisps, self.dark } do
		e.Speed = rise
		e.Acceleration = Vector3.new(0, A.RiseAcceleration * k, 0)
	end
	paintFlames(self.back, colour, size, tier.Transparency)
	paintFlames(self.front, colour, size * 0.8, tier.Transparency + A.FrontTransparencyAdd)
	paintFlames(self.wisps, colour, size * 0.6, tier.Transparency + 0.15)
	if tier.Dark then
		local dark = rgb(tier.Dark)
		paintFlames(self.dark, dark, size * 1.15, 0.2)
		self.dark.Color = ColorSequence.new(dark)
	end
	self.sparks.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.5))
	self.rays.Color = ColorSequence.new(colour)
	self.light.Color = colour
	self:setRates(tier, 1)
	self:setArcs(tier.Arcs == true)
	self.boostToken += 1
	if burst then
		local token = self.boostToken
		self.burstEmitter.Color = ColorSequence.new(colour:Lerp(Color3.new(1, 1, 1), 0.4), colour)
		self.burstEmitter:Emit(A.BurstCount)
		self.back:Emit(math.floor(tier.Rate))
		self:setRates(tier, A.BoostRate)
		self.light.Brightness = tier.Light * A.BoostLight
		TweenService:Create(
			self.light,
			TweenInfo.new(A.BoostSeconds, Enum.EasingStyle.Quad),
			{ Brightness = tier.Light }
		):Play()
		task.delay(A.BoostSeconds, function()
			if self.alive and self.boostToken == token then
				self:setRates(tier, 1)
			end
		end)
	else
		self.light.Brightness = tier.Light
	end
end

-- Mythic's crackling arcs: zig-zags jumping round the body.
function UltAura.setArcs(self: any, on: boolean)
	if on == self.arcsOn then
		return
	end
	self.arcsOn = on
	if not on then
		if self.arcLoop then
			self.arcLoop:Disconnect()
			self.arcLoop = nil
		end
		for _, arc in self.arcs do
			for _, beam in arc.beams do
				beam.Enabled = false
			end
		end
		return
	end
	self.arcLoop = RunService.Heartbeat:Connect(function(dt: number)
		self.arcClock += dt
		if self.arcClock < A.ArcEverySeconds then
			return
		end
		self.arcClock = 0
		self:jumpArcs()
	end)
end

function UltAura.jumpArcs(self: any)
	local rng: Random = self.rng
	local h: number = self.bodyHeight
	local tier = TIERS[self.rarity or "Common"]
	local k = tier.Scale
	local jitter = A.ArcJitterStuds
	for _, arc in self.arcs do
		local shown = rng:NextNumber() > 0.3
		-- Start somewhere on the body's outline, then zig-zag outwards and up.
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = A.BodyWidth * k * 0.5
		local point = Vector3.new(
			math.cos(angle) * radius,
			rng:NextNumber(-h * 0.4, h * 0.4),
			math.sin(angle) * radius * 0.6
		)
		local out = Vector3.new(math.cos(angle), 0.3, math.sin(angle) * 0.6).Unit
		for i, attachment in arc.attachments do
			attachment.Position = point
			if i < #arc.attachments then
				point += out * jitter + Vector3.new(
					rng:NextNumber(-jitter, jitter),
					rng:NextNumber(-jitter, jitter),
					rng:NextNumber(-jitter, jitter) * 0.5
				)
			end
		end
		for _, beam in arc.beams do
			beam.Enabled = shown
		end
	end
end

function UltAura.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self:setArcs(false)
	self.folder:Destroy()
end

return UltAura
