--!strict
-- SkyAurora: the gold aurora after a Legendary pull (designer, 2026-10-05). Curtains of gold
-- light hang in the sky, folding slowly as their rays drift; streaks of light shoot across the
-- sky and gold sparkles drift all round; the world dims a touch so it all glows. Everyone in
-- the server sees it: the opener from their card (PullCutscene), everyone else when the
-- opener's card shows (the server's "Aurora" banner). It is built round the local camera and
-- follows it, so it is overhead wherever the player is (a match too), and it never touches the
-- map: our own parts and our own ColorCorrection, gone when it ends. The opener's is held: it
-- stays while their card shows, with a very faint ambience under it, and lingers a few seconds
-- after they close the card (release) while the ambience plays on a moment and tapers away.
-- Everyone else's runs a fixed time. A second pull while it shows starts it over. Tuning in
-- Config.Cutscenes.Aurora (art in Config.Cutscenes.Art).
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Quality = require(script.Parent.Quality)
local UISound = require(script.Parent.UISound)

local A = Config.Cutscenes.Aurora
local ART = Config.Cutscenes.Art
local KIT = Config.UI.Kit.Art
local WHITE = Color3.new(1, 1, 1)

local SkyAurora = {}

type Curtain = { beam: Beam, a0: Attachment, a1: Attachment, phase: number, brightness: number }

type Show = {
	born: number,
	ends: number, -- os.clock() it is gone by (math.huge while held)
	sound: string?, -- its ambience (Config.Audio.Ui key), the opener's only
	model: Model,
	anchor: Part,
	curtains: { Curtain },
	emitters: { { emitter: ParticleEmitter, rate: number } },
	cc: ColorCorrectionEffect,
	connection: RBXScriptConnection?,
}

local show: Show? = nil

local function rgb(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local function smooth(u: number): number
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function ghost(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = size
	part.Parent = parent
	return part
end

local function fade(share: number): NumberSequence
	local t = 1 - (1 - A.Transparency) * share
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, t),
		NumberSequenceKeypoint.new(0.8, t),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function finish(s: Show)
	if s.sound and s.ends == math.huge then
		UISound.fadeOut(s.sound, 0, 0.3) -- replaced while still held
	end
	if s.connection then
		s.connection:Disconnect()
		s.connection = nil
	end
	s.model:Destroy()
	s.cc:Destroy()
	if show == s then
		show = nil
	end
end

local function build(): Show
	local model = Instance.new("Model")
	model.Name = "SkyAurora"
	model.Parent = workspace
	local anchor = ghost("Anchor", Vector3.one, model)
	local random = Random.new()
	local colours = {}
	for _, c in A.Colours do
		table.insert(colours, rgb(c))
	end

	-- The curtains: chords of a circle round the camera, each a pair of beams (a bright
	-- band and a fainter, wider one above it), spread all the way round with a little jitter.
	local curtains: { Curtain } = {}
	local count = math.max(3, math.floor(A.Curtains * Quality.rate() + 0.5))
	for i = 1, count do
		local angle = math.rad(360 * i / count + random:NextNumber(-15, 15))
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local along = Vector3.new(-out.Z, 0, out.X)
		for layer = 1, 2 do
			local distance = A.DistanceStuds * random:NextNumber(0.85, 1.15)
			local height = A.HeightStuds * random:NextNumber(0.9, 1.1)
				+ (layer - 1) * A.WidthStuds * 0.35
			local middle = out * distance + Vector3.new(0, height, 0)
			local half = A.LengthStuds / 2 * random:NextNumber(0.8, 1.1)
			-- The beams fold along their attachments' X axis: toward and away from the camera,
			-- so a curtain keeps hanging straight down as it folds.
			local axis = out
			local function attach(at: Vector3): Attachment
				local a = Instance.new("Attachment")
				a.CFrame = CFrame.fromMatrix(at, axis, Vector3.yAxis)
				a.Parent = anchor
				return a
			end
			local a0 = attach(middle - along * half)
			local a1 = attach(middle + along * half)
			local beam = Instance.new("Beam")
			beam.Name = "Curtain"
			beam.Attachment0 = a0
			beam.Attachment1 = a1
			beam.Texture = ART.AuroraCurtain
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = A.LengthStuds / random:NextNumber(1.5, 2.5)
			beam.TextureSpeed = A.TextureSpeed * (if random:NextNumber() < 0.5 then -1 else 1)
			local c0 = colours[random:NextInteger(1, #colours)]
			local c1 = colours[random:NextInteger(1, #colours)]
			beam.Color = ColorSequence.new(c0, c1)
			beam.LightEmission = 1
			beam.LightInfluence = 0
			beam.FaceCamera = true
			beam.Width0 = A.WidthStuds * (if layer == 1 then 1 else 1.4)
			beam.Width1 = beam.Width0 * random:NextNumber(0.7, 1.1)
			beam.Segments = 40
			beam.Transparency = fade(0)
			beam.Parent = anchor
			table.insert(curtains, {
				beam = beam,
				a0 = a0,
				a1 = a1,
				phase = random:NextNumber(0, math.pi * 2),
				brightness = if layer == 1 then 1 else 0.55,
			})
		end
	end

	local emitters = {}
	-- Streaks of light shooting across the sky: a wide sheet high up throws them sideways and
	-- down, each stretched along its path.
	local sky =
		ghost("Streaks", Vector3.new(A.DistanceStuds * 2.4, 1, A.DistanceStuds * 2.4), model)
	local streaks = Instance.new("ParticleEmitter")
	streaks.Name = "Streaks"
	streaks.Texture = ART.LightStreak
	streaks.Color = ColorSequence.new(colours[3] or WHITE, colours[1])
	streaks.LightEmission = 1
	streaks.LightInfluence = 0
	streaks.Orientation = Enum.ParticleOrientation.VelocityParallel
	streaks.EmissionDirection = Enum.NormalId.Bottom
	streaks.SpreadAngle = Vector2.new(70, 70)
	streaks.Speed = NumberRange.new(140, 220)
	streaks.Lifetime = NumberRange.new(0.7, 1.2)
	streaks.Size = NumberSequence.new(5)
	streaks.Squash = NumberSequence.new(2.5)
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.Rate = 0
	streaks.Parent = sky
	table.insert(emitters, { emitter = streaks, rate = A.StreaksPerSecond })
	-- Gold sparkles drifting all round the player, twinkling.
	local air = ghost("Sparkles", Vector3.new(160, 60, 160), model)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Name = "Sparkles"
	sparkles.Texture = KIT.Spark
	sparkles.Color = ColorSequence.new(colours[3] or WHITE, colours[1])
	sparkles.LightEmission = 1
	sparkles.LightInfluence = 0
	sparkles.Speed = NumberRange.new(0.5, 2)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Acceleration = Vector3.new(0, 0.6, 0)
	sparkles.Lifetime = NumberRange.new(2, 4)
	sparkles.Rotation = NumberRange.new(0, 360)
	sparkles.RotSpeed = NumberRange.new(-60, 60)
	sparkles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1.1),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.25, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.75, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkles.Rate = 0
	sparkles.Parent = air
	table.insert(emitters, { emitter = sparkles, rate = A.SparklesPerSecond })

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SkyAuroraGrade"
	cc.Parent = Lighting
	return {
		born = os.clock(),
		ends = os.clock() + A.Seconds,
		sound = nil,
		model = model,
		anchor = anchor,
		curtains = curtains,
		emitters = emitters,
		cc = cc,
		connection = nil,
	}
end

local function step(s: Show)
	local now = os.clock()
	local t = now - s.born
	if s.ends == math.huge and t >= A.HeldMaxSeconds then
		SkyAurora.release()
	end
	if now >= s.ends or not s.model.Parent then
		finish(s)
		return
	end
	local share = smooth(t / A.InSeconds) * smooth((s.ends - now) / A.OutSeconds)
	-- Round the camera, never turning with it.
	local eye = workspace.CurrentCamera.CFrame.Position
	s.anchor.CFrame = CFrame.new(eye)
	local streaks = s.model:FindFirstChild("Streaks") :: Part?
	if streaks then
		streaks.CFrame = CFrame.new(eye + Vector3.new(0, A.HeightStuds * 0.9, 0))
	end
	local air = s.model:FindFirstChild("Sparkles") :: Part?
	if air then
		air.CFrame = CFrame.new(eye + Vector3.new(0, 18, 0))
	end
	for _, c in s.curtains do
		local wave = math.sin(t * A.WaveSpeed * math.pi * 2 + c.phase) * A.WaveStuds
		c.beam.CurveSize0 = wave
		c.beam.CurveSize1 = -wave * 0.7
		c.beam.Transparency = fade(share * c.brightness)
	end
	local rate = Quality.rate()
	for _, entry in s.emitters do
		entry.emitter.Rate = entry.rate * rate * share
	end
	s.cc.Brightness = A.Darken * share
	s.cc.TintColor = WHITE:Lerp(rgb(A.Colours[1]), A.TintShare * share)
end

--- The gold aurora, from now. `held` (the opener's): it stays until release(), with the
--- `sound` ambience (a Config.Audio.Ui key) under it. Everyone else's (not held) runs
--- Aurora.Seconds, and never cuts short a held one that is showing. Otherwise a second call
--- while it shows starts it over.
function SkyAurora.play(held: boolean?, sound: string?)
	local old = show
	if old then
		if old.ends == math.huge and not held then
			return
		end
		finish(old)
	end
	local s = build()
	if held then
		s.ends = math.huge
		s.sound = sound
		if sound then
			UISound.play(sound)
		end
	end
	show = s
	s.connection = RunService.Heartbeat:Connect(function()
		local ok, err = pcall(function()
			step(s)
		end)
		if not ok then
			warn("[8ball] SkyAurora: " .. tostring(err))
			finish(s)
		end
	end)
end

--- The opener's card closed: a held aurora lingers Aurora.LingerSeconds (its fade out
--- included), its ambience plays on Aurora.SoundTailSeconds and tapers away. Safe to call
--- when nothing is held.
function SkyAurora.release()
	local s = show
	if not s or s.ends ~= math.huge then
		return
	end
	s.ends = os.clock() + math.max(A.LingerSeconds, A.OutSeconds)
	if s.sound then
		UISound.fadeOut(s.sound, A.SoundTailSeconds, A.SoundFadeSeconds)
	end
end

--- Whether it shows now.
function SkyAurora.isShowing(): boolean
	return show ~= nil
end

return SkyAurora
