--!strict
-- PullMythic: the Mythic pull cutscene, "Starfall" (designer 2026-10-10: the sky turns dark,
-- streaks of stars, the shooting stars combine and hit the player; directed by Claude,
-- docs/prompts/PULL_CUTSCENES_V2.md). A film behind black bars, on the designer's "Transition
-- Logo Reveal" from the black:
--   1. Nightfall (the track's first hit cuts in): low and wide in front of the player, the day
--      falls to night in a second and a half while the world round them dissolves away (for
--      them alone: only they, the bare ground and the sky are left), a pastel Milky Way and
--      nebulae come out over the stars, the first shooting stars cross.
--   2. Wonder: over the shoulder looking up, shooting stars streak across the sky one after
--      another; on the track's shimmer they bend toward one point high above the player and
--      wind in, the light sucked out with the track's breath.
--   3. The newborn star (the reveal hit): low, looking up past the player as the stars fuse into
--      one rainbow star that pulses with the hits.
--   4. The fall: it drops as a rainbow comet and hits the player on the track's last sub hit:
--      glare, a nova, a shockwave over the roof, sparks and shards, a heavy shake.
--   5. Bullet time: the world almost stops (particles, the nova, the shake) while the camera
--      circles the frozen burst.
--   6. Forging: time runs again, the light falls into one point beside the player and the
--      real cue forms there from white light (its own mesh, surface, aura and 3D piece; pure
--      light if its look is not loaded), a celestial sigil lighting under them; the "Robo Rise"
--      builds while the camera circles cue and player and the starlight swirls ever faster;
--      the cue flares and the screen goes white on the rise's stop with the Cinematic Hit.
-- Everything is our own instances in the scene's model, or values PullKit.hold puts back.
-- Tuning in Config.Cutscenes.Mythic.
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PullMath = require(Shared:WaitForChild("PullMath"))
local PullKit = require(script.Parent.PullKit)
local Quality = require(script.Parent.Quality)
local UISound = require(script.Parent.UISound)

type Scene = PullKit.Scene

local CS = Config.Cutscenes
local M = CS.Mythic
local K = Config.UI.Kit.Art
local ART = CS.Art
local rgb, smooth, between, key = PullKit.rgb, PullKit.smooth, PullKit.between, PullKit.key
local WHITE = PullKit.WHITE
local UP = Vector3.yAxis

local PullMythic = {}

--- When the white flash starts, from the end of the fade to black.
function PullMythic.flashAt(): number
	return M.FlashAt
end

-- The palette: the Mythic shimmer (cyan, lilac, pink, white) and the scene's extra pastels.
local function palette(): { Color3 }
	local out = {}
	for _, values in M.Palette do
		table.insert(out, rgb(values))
	end
	return out
end

--------------------------------------------------------------------------------------------
-- Building (the first frame, while the screen is still black)
--------------------------------------------------------------------------------------------

local function attachTo(rig: BasePart, at: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Parent = rig
	a.WorldPosition = at
	return a
end

local function trail(
	rig: BasePart,
	a0: Attachment,
	a1: Attachment,
	colour: ColorSequence,
	seconds: number
): Trail
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = colour
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Brightness = 3
	t.FaceCamera = true
	t.Lifetime = seconds
	t.MinLength = 0
	t.Transparency = NumberSequence.new({ key(0, 0), key(0.35, 0.25), key(1, 1) })
	t.WidthScale = NumberSequence.new({ key(0, 1), key(1, 0.15) })
	t.Enabled = false
	t.Parent = rig
	return t
end

local function rainbow(colours: { Color3 }): ColorSequence
	local keys = {}
	for i, c in colours do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(#colours - 1, 1), c))
	end
	return ColorSequence.new(keys)
end

-- The shooting stars' flights: each starts across the sky in front of the player, streaks
-- sideways and a little down, then (from TurnAt) homes on the point in a shrinking spiral.
local function planStars(s: Scene, colours: { Color3 }, rig: BasePart)
	local S = M.Shooting
	local p = s.parts
	local feet: Vector3, facing: Vector3, right: Vector3 = p.feet, p.facing, p.right
	local count = math.max(S.Min, math.floor(S.Count * Quality.rate()))
	local stars = {}
	for i = 1, count do
		local r = s.random
		-- Spread over the sky ahead, alternating sides so they cross the view both ways.
		local side = if i % 2 == 0 then 1 else -1
		local yaw = math.rad(r:NextNumber(S.YawDegrees[1], S.YawDegrees[2])) * side
		if i == 1 then
			yaw += math.pi -- the first crosses the sky behind the player, where shot 1 looks
		end
		local dir = facing * math.cos(yaw) + right * math.sin(yaw)
		local distance = r:NextNumber(S.Distance[1], S.Distance[2])
		local start = feet + dir * distance + UP * r:NextNumber(S.Height[1], S.Height[2])
		-- Across the view (toward the other side), dipping.
		local across = (-right * side + facing * r:NextNumber(-0.25, 0.25)).Unit
		local velocity = (across - UP * r:NextNumber(S.Dip[1], S.Dip[2])).Unit
			* r:NextNumber(S.Speed[1], S.Speed[2])
		local colour = colours[(i - 1) % #colours + 1]
		local a0, a1 = attachTo(rig, start), attachTo(rig, start)
		local width = r:NextNumber(S.TrailStuds[1], S.TrailStuds[2])
		local streak = trail(rig, a0, a1, ColorSequence.new(WHITE, colour), S.TrailSeconds)
		local head = attachTo(rig, start)
		local glow, glowImage =
			PullKit.billboard(head, "Head", K.SoftGlow, WHITE:Lerp(colour, 0.35), S.HeadStuds, 1, 2)
		local dust = PullKit.emitter(head, "Dust", K.Spark, WHITE, colour)
		dust.Lifetime = NumberRange.new(0.5, 1.1)
		dust.Size = NumberSequence.new({ key(0, 0), key(0.2, 2.2, 1), key(1, 0) })
		dust.Speed = NumberRange.new(0, 3)
		dust.SpreadAngle = Vector2.new(180, 180)
		dust.Transparency = NumberSequence.new({ key(0, 0.2), key(1, 1) })
		stars[i] = {
			index = i,
			startAt = S.From + (i - 1) * S.Every + r:NextNumber(0, S.Every * 0.4),
			turnAt = M.TurnAt + (i - 1) * S.TurnStagger,
			start = start,
			velocity = velocity,
			width = width,
			colour = colour,
			a0 = a0,
			a1 = a1,
			head = head,
			streak = streak,
			glow = glow,
			glowImage = glowImage,
			dust = dust,
			spin = r:NextNumber(0, math.pi * 2),
			whooshed = false,
			from = nil :: Vector3?, -- where its homing began (filled in at turnAt)
		}
	end
	p.stars = stars
end

local function build(s: Scene)
	local p = s.parts
	PullKit.takeCamera(s)
	local cam = workspace.CurrentCamera
	local root, standing = PullKit.character()
	local feet: Vector3 = standing or (cam.Focus.Position - Vector3.new(0, 3, 0))
	local look = if root then root.CFrame.LookVector else cam.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	facing = if facing.Magnitude > 1e-3 then facing.Unit else Vector3.new(0, 0, -1)
	p.feet = feet
	p.facing = facing
	p.right = facing:Cross(UP)
	p.chest = feet + UP * M.ChestStuds
	p.point = feet + UP * M.PointHeightStuds + facing * M.PointAheadStuds
	p.cueMiddle = feet
		+ facing * M.Forge.CueAheadStuds
		+ p.right * M.Forge.CueSideStuds
		+ UP * M.Forge.CueHeightStuds
	p.params = PullKit.rayParams(s)
	-- The world round the player falls away into the night (for them alone).
	PullKit.clearWorld(s, feet, M.Clear.RadiusStuds, M.Clear.GroundStuds)
	local colours = palette()
	p.colours = colours
	local q = Quality.rate()

	-- The screen: bars (in from the black), the impact's glare.
	PullKit.bars(s, M.BarsShare, 5)
	PullKit.setBars(s, 1)
	p.glare = PullKit.fullFrame(s.veilRoot, "Glare", rgb(M.Impact.GlareColour), 4)

	local rig = PullKit.ghostPart(s, "Rig", Vector3.one, feet)
	p.rig = rig

	-- The cosmos over the roof: the Milky Way's arch, nebulae, big twinkling stars.
	local W = M.MilkyWay
	-- Over the player from the horizon ahead to the one behind, turned a little, so the
	-- shots looking back at them and the ones looking ahead both see it.
	local bandYaw = math.rad(W.YawDegrees)
	local along = (facing * math.cos(bandYaw) + p.right * math.sin(bandYaw)).Unit
	local m0 = attachTo(
		rig,
		feet + along * W.LengthStuds / 2 + UP * W.EndHeightStuds + facing * W.AheadStuds
	)
	local m1 = attachTo(
		rig,
		feet - along * W.LengthStuds / 2 + UP * W.EndHeightStuds + facing * W.AheadStuds
	)
	-- Their axes up, so the curve arches the band over the sky (Beam control points ride the axes).
	for _, a in { m0, m1 } do
		a.WorldCFrame = CFrame.fromMatrix(a.WorldPosition, UP, along:Cross(UP))
	end
	local band = Instance.new("Beam")
	band.Name = "MilkyWay"
	band.Attachment0 = m0
	band.Attachment1 = m1
	band.Texture = ART.MilkyWay
	band.TextureMode = Enum.TextureMode.Stretch
	band.TextureLength = 1
	band.Color = ColorSequence.new(WHITE)
	band.LightEmission = 1
	band.LightInfluence = 0
	band.Brightness = W.Brightness
	band.FaceCamera = true
	band.Segments = 48
	band.CurveSize0 = W.CurveStuds
	band.CurveSize1 = -W.CurveStuds
	band.Width0 = W.WidthStuds
	band.Width1 = W.WidthStuds
	band.Transparency = NumberSequence.new(1)
	band.Parent = rig
	p.band = band

	local N = M.Nebulae
	local nebulae = {}
	for i = 1, N.Count do
		local yaw = math.rad(
			N.YawDegrees[1]
				+ (N.YawDegrees[2] - N.YawDegrees[1]) * (i - 1) / math.max(N.Count - 1, 1)
		) + s.random:NextNumber(-0.12, 0.12)
		local pitch = math.rad(s.random:NextNumber(N.PitchDegrees[1], N.PitchDegrees[2]))
		local dir = (facing * math.cos(yaw) + p.right * math.sin(yaw)) * math.cos(pitch)
			+ UP * math.sin(pitch)
		local at = attachTo(rig, feet + dir * N.DistanceStuds)
		local size = s.random:NextNumber(N.SizeStuds[1], N.SizeStuds[2])
		local art = if i % 2 == 0 then ART.NebulaA else ART.NebulaB
		local board, image = PullKit.billboard(at, "Nebula", art, WHITE, size)
		nebulae[i] = { board = board, image = image, turn = s.random:NextNumber(0, 360) }
	end
	p.nebulae = nebulae

	local SS = M.SkyStars
	local sky = PullKit.ghostPart(
		s,
		"SkyStars",
		Vector3.new(SS.SpreadStuds, SS.TopStuds - SS.BottomStuds, SS.SpreadStuds),
		feet + UP * (SS.BottomStuds + SS.TopStuds) / 2 + facing * SS.AheadStuds
	)
	local skyStars = {}
	for i, c in { colours[1], colours[2], colours[3], WHITE } do
		local e = PullKit.emitter(sky, "Stars" .. i, K.Spark, WHITE:Lerp(c, 0.6), c)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Lifetime = NumberRange.new(SS.LifetimeSeconds)
		e.Size = NumberSequence.new({
			key(0, SS.SizeStuds, SS.SizeStuds * 0.6),
			key(1, SS.SizeStuds, SS.SizeStuds * 0.6),
		})
		e.Transparency = NumberSequence.new({
			key(0, 1),
			key(0.06, 0.15, 0.1),
			key(0.2, 0.45, 0.3),
			key(0.35, 0.1, 0.1),
			key(0.5, 0.5, 0.3),
			key(0.65, 0.15, 0.1),
			key(0.8, 0.5, 0.3),
			key(1, 1),
		})
		e.RotSpeed = NumberRange.new(-20, 20)
		skyStars[i] = e
	end
	p.skyStars = skyStars
	p.skyStarCount = math.max(40, math.floor(SS.Count * q))

	-- The shooting stars.
	planStars(s, colours, rig)

	-- Light streaming into the point before the fusion.
	local shell = PullKit.ghostPart(s, "Gather", Vector3.one * M.Star.GatherStuds, p.point)
	shell.Shape = Enum.PartType.Ball
	local gather = PullKit.emitter(shell, "Gather", K.Spark, WHITE, colours[2])
	gather.Shape = Enum.ParticleEmitterShape.Sphere
	gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	gather.Speed = NumberRange.new(M.Star.GatherStuds / 2 / 0.6)
	gather.Lifetime = NumberRange.new(0.6)
	gather.Orientation = Enum.ParticleOrientation.VelocityParallel
	gather.Squash = NumberSequence.new(1.6)
	gather.Size = NumberSequence.new({ key(0, 1.5), key(1, 3) })
	gather.Transparency = NumberSequence.new({ key(0, 1), key(0.3, 0), key(1, 0.3) })
	p.gather = gather

	-- The newborn star: a hot core, two turning flares, rays, a light; it falls as a comet.
	local star = attachTo(rig, p.point)
	p.star = star
	p.starRays = select(
		2,
		PullKit.billboard(
			star,
			"Rays",
			K.Rays,
			colours[2]:Lerp(WHITE, 0.35),
			M.Star.RaysStuds,
			1,
			1.2
		)
	)
	p.starFlare = select(
		2,
		PullKit.billboard(star, "Flare", ART.StarFlare, colours[1], M.Star.FlareStuds, 2, 2)
	)
	p.starFlare2 = select(
		2,
		PullKit.billboard(star, "Flare2", ART.StarFlare, colours[3], M.Star.FlareStuds * 0.7, 3, 2)
	)
	p.starCore = select(2, PullKit.billboard(star, "Core", K.SoftGlow, WHITE, M.Star.Studs, 4, 2.5))
	local starLight = Instance.new("PointLight")
	starLight.Range = M.Star.LightRange
	starLight.Brightness = 0
	starLight.Shadows = false
	starLight.Parent = star
	p.starLight = starLight
	local cometA, cometB = attachTo(rig, p.point), attachTo(rig, p.point)
	p.cometA, p.cometB = cometA, cometB
	p.comet = trail(
		rig,
		cometA,
		cometB,
		rainbow({ WHITE, colours[1], colours[2], colours[3] }),
		M.Fall.TrailSeconds
	)
	-- The ring that bursts through the sky at the fusion, and the pulses after.
	p.skyRing = { PullKit.billboard(star, "SkyRing", K.RingGlow, WHITE, 1, 0) }
	p.pulseRing = { PullKit.billboard(star, "PulseRing", K.RingGlow, colours[3], 1, 0) }

	-- The hit: a nova shell, its hot core, a shockwave over the roof, a pillar of light, sparks
	-- and shards thrown out (they hang in bullet time).
	local nova = PullKit.ghostPart(s, "Nova", Vector3.one, p.chest)
	nova.Shape = Enum.PartType.Ball
	nova.Material = Enum.Material.ForceField
	nova.Color = colours[2]
	p.nova = nova
	local core = PullKit.ghostPart(s, "NovaCore", Vector3.one, p.chest)
	core.Shape = Enum.PartType.Ball
	core.Material = Enum.Material.Neon
	core.Color = WHITE
	p.novaCore = core
	p.shock, p.shockArt = PullKit.glowArt(s, "Shock", K.RingGlow, colours[1], feet + UP * 0.08, 1.5)
	p.shock2, p.shock2Art =
		PullKit.glowArt(s, "Shock2", K.RingGlow, colours[3], feet + UP * 0.1, 1.5)
	local impact = attachTo(rig, p.chest)
	p.impact = impact
	local sparks = PullKit.emitter(impact, "Sparks", K.Spark, WHITE, colours[2])
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Speed = NumberRange.new(35, 85)
	sparks.Drag = 1.4
	sparks.Acceleration = Vector3.new(0, -30, 0)
	sparks.Lifetime = NumberRange.new(1.1, 1.9)
	sparks.Orientation = Enum.ParticleOrientation.VelocityParallel
	sparks.Squash = NumberSequence.new(1.8)
	sparks.Size = NumberSequence.new({ key(0, 1), key(1, 0) })
	local shards = PullKit.emitter(impact, "Shards", ART.LightShard, WHITE, colours[1])
	shards.SpreadAngle = Vector2.new(180, 180)
	shards.Speed = NumberRange.new(28, 70)
	shards.Drag = 1.1
	shards.Lifetime = NumberRange.new(1.4, 2.4)
	shards.Orientation = Enum.ParticleOrientation.VelocityParallel
	shards.Size = NumberSequence.new({ key(0, 1.8, 0.6), key(1, 0.5) })
	shards.Transparency = NumberSequence.new({ key(0, 0.2), key(0.8, 0.35), key(1, 1) })
	local burst = PullKit.emitter(impact, "Burst", K.SoftGlow, WHITE, colours[2])
	burst.Lifetime = NumberRange.new(0.5, 0.7)
	burst.Size = NumberSequence.new({ key(0, 6), key(1, 20) })
	burst.Transparency = NumberSequence.new(0.35, 1)
	local rays = PullKit.emitter(impact, "Rays", K.Rays, colours[3], colours[1])
	rays.Lifetime = NumberRange.new(0.6)
	rays.RotSpeed = NumberRange.new(-80, 80)
	rays.Size = NumberSequence.new({ key(0, 12), key(1, 34) })
	rays.Transparency = NumberSequence.new(0.3, 1)
	p.sparks, p.shards, p.burst, p.rays = sparks, shards, burst, rays
	local flare = Instance.new("PointLight")
	flare.Range = 30
	flare.Brightness = 0
	flare.Shadows = false
	flare.Parent = impact
	p.flare = flare
	local pillarA = attachTo(rig, feet)
	local pillarB = attachTo(rig, feet + UP * M.Impact.PillarStuds)
	local pillar = Instance.new("Beam")
	pillar.Attachment0 = pillarA
	pillar.Attachment1 = pillarB
	pillar.Texture = ART.BeamSoft
	pillar.Color = rainbow({ WHITE, colours[1], colours[2], colours[3] })
	pillar.LightEmission = 1
	pillar.LightInfluence = 0
	pillar.Brightness = 3
	pillar.FaceCamera = true
	pillar.Segments = 1
	pillar.Transparency = NumberSequence.new({ key(0, 0.25), key(0.6, 0.7), key(1, 1) })
	pillar.Enabled = false
	pillar.Parent = rig
	p.pillar = pillar

	-- The forge: light falling into the point beside the player, the white-hot glow the cue
	-- forms in (and the star the light stays as when the cue is not loaded), the sigil, the
	-- starlight orbiting the cue, rising motes.
	local forge = attachTo(rig, p.cueMiddle)
	p.forge = forge
	local inShell = PullKit.ghostPart(s, "Implode", Vector3.one * M.Forge.ImplodeStuds, p.cueMiddle)
	inShell.Shape = Enum.PartType.Ball
	local implode = PullKit.emitter(inShell, "Implode", K.Spark, WHITE, colours[1])
	implode.Shape = Enum.ParticleEmitterShape.Sphere
	implode.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	implode.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	implode.Speed = NumberRange.new(M.Forge.ImplodeStuds / 2 / 0.4)
	implode.Lifetime = NumberRange.new(0.4)
	implode.Orientation = Enum.ParticleOrientation.VelocityParallel
	implode.Squash = NumberSequence.new(2)
	implode.Size = NumberSequence.new({ key(0, 1.2), key(1, 0.4) })
	implode.Transparency = NumberSequence.new({ key(0, 1), key(0.25, 0), key(1, 0) })
	p.implode = implode
	p.forgeGlow = select(2, PullKit.billboard(forge, "ForgeGlow", K.SoftGlow, WHITE, 1, 3))
	p.forgeFlare =
		select(2, PullKit.billboard(forge, "ForgeFlare", ART.StarFlare, colours[2], 1, 2))
	p.forgeRays = select(2, PullKit.billboard(forge, "ForgeRays", K.Rays, colours[1], 1, 1))
	local forgeLight = Instance.new("PointLight")
	forgeLight.Range = 14
	forgeLight.Brightness = 0
	forgeLight.Shadows = false
	forgeLight.Parent = forge
	p.forgeLight = forgeLight
	local born = PullKit.emitter(forge, "Born", K.Spark, WHITE, colours[3])
	born.SpreadAngle = Vector2.new(180, 180)
	born.Speed = NumberRange.new(8, 22)
	born.Drag = 2
	born.Lifetime = NumberRange.new(0.6, 1.2)
	born.Size = NumberSequence.new({ key(0, 1.2), key(1, 0) })
	p.born = born
	local sigilAt = (feet + p.cueMiddle - UP * M.Forge.CueHeightStuds) / 2 + UP * 0.12
	p.sigil, p.sigilArt = PullKit.glowArt(s, "Sigil", ART.Sigil, colours[2], sigilAt, 1.6)
	p.sigilAt = sigilAt
	local orbiters = {}
	for i = 1, M.Forge.Orbiters do
		local a0, a1 = attachTo(rig, p.cueMiddle), attachTo(rig, p.cueMiddle)
		local colour = colours[(i - 1) % #colours + 1]
		orbiters[i] = {
			a0 = a0,
			a1 = a1,
			trail = trail(rig, a0, a1, ColorSequence.new(WHITE, colour), M.Forge.OrbitTrailSeconds),
			tilt = math.rad(
				M.Forge.OrbitTiltDegrees * (if i % 2 == 0 then 1 else -1) + (i - 1) * 25
			),
			phase = (i - 1) / M.Forge.Orbiters * math.pi * 2,
		}
	end
	p.orbiters = orbiters
	local moteBox = PullKit.ghostPart(s, "Motes", Vector3.new(16, 2, 16), sigilAt + UP)
	local motes = PullKit.emitter(moteBox, "Motes", K.Spark, WHITE, colours[1])
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Speed = NumberRange.new(2, 6)
	motes.Lifetime = NumberRange.new(1.2, 2.2)
	motes.RotSpeed = NumberRange.new(-90, 90)
	motes.Size = NumberSequence.new({ key(0, 0), key(0.3, 0.42), key(1, 0) })
	p.motes = motes

	-- The world's grade, light, sky and bloom are held so the end puts them back.
	local mapSky = Lighting:FindFirstChildOfClass("Sky")
	PullKit.hold(s, mapSky, { "StarCount", "CelestialBodiesShown" })
	PullKit.hold(s, Lighting, { "EnvironmentDiffuseScale", "EnvironmentSpecularScale" })
	PullKit.hold(
		s,
		Lighting:FindFirstChildOfClass("Atmosphere"),
		{ "Density", "Haze", "Glare", "Color", "Decay" }
	)
	PullKit.hold(
		s,
		Lighting:FindFirstChildOfClass("BloomEffect"),
		{ "Intensity", "Threshold", "Size" }
	)
	PullKit.hold(s, Lighting:FindFirstChildOfClass("DepthOfFieldEffect"), {
		"Enabled",
		"FarIntensity",
		"FocusDistance",
		"InFocusRadius",
		"NearIntensity",
	})
	if mapSky then
		mapSky.StarCount = M.Night.Stars
		mapSky.CelestialBodiesShown = false -- no sun racing across the sky as the clock spins
	end
	-- The night's clock: back through the small hours from a morning, on past dusk from an
	-- afternoon, never through noon.
	local clock0: number = s.lighting.ClockTime
	p.clock0 = clock0
	p.clockTo = if clock0 >= 12 then M.Night.ClockTime + 24 else M.Night.ClockTime
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	p.bloom0 = if bloom then { bloom.Intensity, bloom.Threshold, bloom.Size } else nil
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	p.atmo0 = if atmosphere then { atmosphere.Color, atmosphere.Decay } else nil
	p.bullet = 1 -- the particles' time scale now
end

--------------------------------------------------------------------------------------------
-- Each frame
--------------------------------------------------------------------------------------------

-- Nightfall: the clock runs to midnight (the painted sky dims and the stars come out), the
-- light turns indigo and the bloom opens; the cosmos fades in over it.
local function stepNight(s: Scene, t: number)
	local N = M.Night
	local p = s.parts
	local k = between(t, M.HitAt, M.HitAt + M.NightSeconds)
	PullKit.fadeWorld(s, between(t, M.HitAt + M.Clear.From, M.HitAt + M.Clear.To), M.Clear.Share)
	local saved = s.lighting
	-- Back through the small hours: from the day's clock down to midnight.
	local from: number, to: number = p.clock0, p.clockTo
	Lighting.ClockTime = (from + (to - from) * k) % 24
	Lighting.Brightness = saved.Brightness + (N.Brightness - saved.Brightness) * k
	Lighting.OutdoorAmbient = (saved.OutdoorAmbient :: Color3):Lerp(rgb(N.OutdoorAmbient), k)
	Lighting.Ambient = (saved.Ambient :: Color3):Lerp(rgb(N.Ambient), k)
	Lighting.ExposureCompensation = saved.ExposureCompensation
		+ (N.Exposure - saved.ExposureCompensation) * k
	Lighting.EnvironmentDiffuseScale = N.EnvDiffuse
	Lighting.EnvironmentSpecularScale = N.EnvSpecular
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and s.atmosphere then
		atmosphere.Density = (s.atmosphere.Density :: number) * (1 - k) + N.AtmosphereDensity * k
		atmosphere.Haze = (s.atmosphere.Haze :: number) * (1 - k)
		atmosphere.Glare = (s.atmosphere.Glare :: number) * (1 - k)
	end
	local atmo0 = p.atmo0
	if atmosphere and atmo0 then
		atmosphere.Color = (atmo0[1] :: Color3):Lerp(rgb(N.AtmosphereColour), k)
		atmosphere.Decay = (atmo0[2] :: Color3):Lerp(rgb(N.AtmosphereDecay), k)
	end
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	local bloom0 = p.bloom0
	if bloom and bloom0 then
		bloom.Intensity = bloom0[1] + (N.BloomIntensity - bloom0[1]) * k
		bloom.Threshold = bloom0[2] + (N.BloomThreshold - bloom0[2]) * k
		bloom.Size = math.floor(bloom0[3] + (N.BloomSize - bloom0[3]) * k)
	end
	-- The grade: the night's lavender, deeper while time stands still.
	local still = PullMath.warpSpeed(t, M.SlowFrom, M.SlowTo, M.SlowSpeed, M.SlowRampSeconds)
	local frozen = 1 - (still - M.SlowSpeed) / (1 - M.SlowSpeed)
	s.cc.TintColor = WHITE:Lerp(rgb(N.Tint), k)
		:Lerp(rgb(M.Bullet.Tint), frozen * M.Bullet.TintShare)
	s.cc.Contrast = N.Contrast * k + M.Bullet.Contrast * frozen
	s.cc.Saturation = N.Saturation * k + M.Bullet.Saturation * frozen

	-- The cosmos.
	local c = between(t, M.HitAt + M.Cosmos.InFrom, M.HitAt + M.Cosmos.InTo)
	local W = M.MilkyWay
	local band: Beam = p.band
	band.Transparency = NumberSequence.new({
		key(0, 1),
		key(0.12, 1 - (1 - W.Transparency) * c),
		key(0.88, 1 - (1 - W.Transparency) * c),
		key(1, 1),
	})
	for i, nebula in p.nebulae do
		local image: ImageLabel = nebula.image
		image.ImageTransparency = 1 - (1 - M.Nebulae.Transparency) * c
		image.Rotation = nebula.turn + t * M.Nebulae.TurnDegrees * (if i % 2 == 0 then 1 else -1)
	end
	if t >= M.HitAt + M.Cosmos.InFrom and not s.fired.skyStars then
		s.fired.skyStars = true
		local each = math.floor(p.skyStarCount / #p.skyStars)
		for _, e: ParticleEmitter in p.skyStars do
			e:Emit(each)
		end
	end
end

-- Where shooting star `star` is at `t` (nil before it starts), and whether it is homing.
local function starAt(s: Scene, star: any, t: number): (Vector3?, number)
	if t < star.startAt then
		return nil, 0
	end
	local S = M.Shooting
	local free = star.start + star.velocity * (t - star.startAt)
	if t < star.turnAt then
		return free, 0
	end
	local p = s.parts
	if star.from == nil then
		star.from = star.start + star.velocity * (star.turnAt - star.startAt)
	end
	local from: Vector3 = star.from
	local arrive = M.FuseAt - S.ArriveEarlySeconds
	local u = math.clamp((t - star.turnAt) / math.max(arrive - star.turnAt, 0.05), 0, 1)
	local h = PullMath.homing(u, S.HomePower)
	-- A cubic curve that leaves along its flight and comes into the point, plus a spiral
	-- shrinking to nothing as it arrives.
	local point: Vector3 = p.point
	local out = star.velocity.Unit * (point - from).Magnitude * S.CarryShare
	local into = (point - from).Unit * (point - from).Magnitude * 0.3
	local c1 = from + out
	local c2 = point - into
	local a = 1 - h
	local curve = from * (a * a * a)
		+ c1 * (3 * a * a * h)
		+ c2 * (3 * a * h * h)
		+ point * (h * h * h)
	local axis = (point - from).Unit
	local e1 = axis:Cross(UP)
	e1 = if e1.Magnitude > 1e-3 then e1.Unit else Vector3.xAxis
	local e2 = axis:Cross(e1).Unit
	local phi = star.spin + math.pi * 2 * S.SpiralTurns * h
	local radius = S.SpiralStuds * (1 - h) ^ 1.5 * math.min(1, h * 6)
	return curve + (e1 * math.cos(phi) + e2 * math.sin(phi)) * radius, h
end

local function stepStars(s: Scene, t: number)
	local S = M.Shooting
	local p = s.parts
	local eye = workspace.CurrentCamera.CFrame.Position
	local fused = t >= M.FuseAt
	for _, star in p.stars do
		local at, h = starAt(s, star, t)
		local flying = at ~= nil and not fused
		star.streak.Enabled = flying
		star.dust.Rate = if flying then S.DustRate * Quality.rate() else 0
		local glowImage: ImageLabel = star.glowImage
		if not flying or at == nil then
			glowImage.ImageTransparency = 1
			continue
		end
		local position = at :: Vector3
		-- Far away a streak is drawn wider, so it reads at any distance.
		local distance = (position - eye).Magnitude
		local width = math.clamp(distance * S.WidthPerStud, S.MinWidthStuds, star.width)
			* (1 + h * 0.6)
		local camRight = workspace.CurrentCamera.CFrame.RightVector
		star.a0.WorldPosition = position + camRight * width / 2
		star.a1.WorldPosition = position - camRight * width / 2
		star.head.WorldPosition = position
		local fadeIn = between(t, star.startAt, star.startAt + 0.15)
		glowImage.ImageTransparency = 1 - fadeIn * (0.15 + 0.85 * (1 - h * 0.3))
		local board: BillboardGui = star.glow
		local size = math.max(S.HeadStuds, distance * S.HeadPerStud) * (1 + h)
		board.Size = UDim2.fromScale(size, size)
		if not star.whooshed and t >= star.startAt then
			star.whooshed = true
			if star.index % M.WhooshEvery == 1 % M.WhooshEvery then
				UISound.play(M.Sounds.Whoosh, s.random:NextNumber(0.9, 1.12))
			end
		end
	end
	-- Light streams into the point as they arrive.
	p.gather.Rate = if t >= M.TurnAt + 0.4 and not fused
		then M.Star.GatherRate * Quality.rate()
		else 0
	if t >= M.GatherSoundAt and not s.fired.gather then
		s.fired.gather = true
		UISound.play(M.Sounds.Gather)
	end
end

-- The newborn star at the point, then its fall as a comet to the player's chest.
local function stepStar(s: Scene, t: number)
	local St = M.Star
	local p = s.parts
	local colours: { Color3 } = p.colours
	local born = t >= M.FuseAt
	local hit = t >= M.ImpactAt
	local shown = born and not hit
	local since = t - M.FuseAt
	-- Its place: at the point, or falling to the chest.
	local fall = math.clamp((t - M.FallAt) / (M.ImpactAt - M.FallAt), 0, 1)
	local at = (p.point :: Vector3):Lerp(p.chest, PullMath.homing(fall, M.Fall.Power))
	p.star.WorldPosition = at
	-- Its size: it bursts out, pulses on the hits, and tightens into a comet head as it falls.
	local pulse = 1
	for _, beat in St.PulseAt do
		pulse += St.PulseScale * math.exp(-math.max(0, t - beat) * 9) * (if t >= beat then 1 else 0)
	end
	local grow = smooth(since / 0.18) * (1 + 0.6 * math.exp(-math.max(since, 0) * 6))
	local tighten = 1 - 0.55 * smooth(fall)
	local scale = grow * pulse * tighten
	local function size(image: ImageLabel, studs: number, transparency: number)
		image.ImageTransparency = if shown then transparency else 1
		local board = image.Parent :: BillboardGui
		board.Size = UDim2.fromScale(studs * scale, studs * scale)
	end
	local tint = PullKit.cycle(colours, t, St.CycleSeconds)
	p.starFlare.ImageColor3 = tint
	p.starFlare2.ImageColor3 = PullKit.cycle(colours, t + St.CycleSeconds / 2, St.CycleSeconds)
	p.starRays.ImageColor3 = tint
	p.starFlare.Rotation = since * St.SpinDegrees
	p.starFlare2.Rotation = -since * St.SpinDegrees * 0.7 + 22.5
	p.starRays.Rotation = since * St.SpinDegrees * 0.25
	size(p.starCore, St.Studs, 0)
	size(p.starFlare, St.FlareStuds, 0.05)
	size(p.starFlare2, St.FlareStuds * 0.7, 0.15)
	size(p.starRays, St.RaysStuds, 0.5)
	local light: PointLight = p.starLight
	light.Color = tint
	light.Brightness = if shown then St.Light * grow * pulse else 0
	-- The ring through the sky at the fusion, and a smaller one on each hit after it.
	local ringBoard: BillboardGui, ringImage: ImageLabel = p.skyRing[1], p.skyRing[2]
	local r = math.clamp(since / St.RingSeconds, 0, 1)
	ringImage.ImageTransparency = if born and r < 1 then 0.1 + 0.9 * r else 1
	local ringSize = St.RingStuds * (1 - (1 - r) ^ 3)
	ringBoard.Size = UDim2.fromScale(ringSize, ringSize)
	local pulseBoard: BillboardGui, pulseImage: ImageLabel = p.pulseRing[1], p.pulseRing[2]
	pulseImage.ImageTransparency = 1
	for _, beat in St.PulseAt do
		local u = (t - beat) / 0.45
		if u >= 0 and u <= 1 then
			pulseImage.ImageTransparency = 0.2 + 0.8 * u
			local px = St.RingStuds * 0.45 * (1 - (1 - u) ^ 2)
			pulseBoard.Size = UDim2.fromScale(px, px)
		end
	end
	-- The comet's rainbow trail on the way down.
	local falling = t >= M.FallAt and not hit
	local comet: Trail = p.comet
	comet.Enabled = falling
	if falling then
		local camRight = workspace.CurrentCamera.CFrame.RightVector
		local width = M.Fall.TrailStuds
		p.cometA.WorldPosition = at + camRight * width / 2
		p.cometB.WorldPosition = at - camRight * width / 2
	end
end

-- Slows (or restores) every emitter of the scene to the bullet clock's speed.
local function timeScale(s: Scene, speed: number)
	local p = s.parts
	if math.abs((p.bullet or 1) - speed) < 1e-3 then
		return
	end
	p.bullet = speed
	for _, d in s.model:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			d.TimeScale = math.clamp(speed, 0, 1)
		end
	end
end

-- The hit and bullet time: everything here runs on the warped world clock `w`.
local function stepImpact(s: Scene, t: number, w: number)
	local I = M.Impact
	local p = s.parts
	local colours: { Color3 } = p.colours
	local hit = t >= M.ImpactAt
	local after = w - M.ImpactAt
	local forging = t >= M.ForgeAt
	if hit and not s.fired.impact then
		s.fired.impact = true
		local q = Quality.rate()
		p.sparks:Emit(math.floor(I.Sparks * q))
		p.shards:Emit(math.floor(I.Shards * q))
		p.burst:Emit(3)
		p.rays:Emit(2)
		UISound.play(M.Sounds.Boom)
	end
	if t >= M.SlowSoundAt and not s.fired.slow then
		s.fired.slow = true
		UISound.play(M.Sounds.Slow)
	end
	timeScale(s, PullMath.warpSpeed(t, M.SlowFrom, M.SlowTo, M.SlowSpeed, M.SlowRampSeconds))
	-- The glare floods the screen, then clears.
	local glare = if hit then math.exp(-math.max(t - M.ImpactAt, 0) / I.GlareSeconds) else 0
	p.glare.BackgroundTransparency = 1 - I.Glare * glare
	-- The nova: out from the chest, slowing almost to a stop in bullet time; it falls back
	-- into the forge point when time runs again.
	local nova: Part = p.nova
	local core: Part = p.novaCore
	if hit and not forging then
		local k = math.clamp(after / I.NovaSeconds, 0, 1)
		local size = 2 + (I.NovaStuds - 2) * (1 - (1 - k) ^ 3)
		nova.Size = Vector3.one * size
		nova.Transparency = 0.15 + 0.85 * k ^ 1.5
		nova.Color = PullKit.cycle(colours, w, 1.2)
		nova.CFrame = CFrame.new(p.chest)
		local c = math.clamp(after / I.CoreSeconds, 0, 1)
		core.Size = Vector3.one * (2 + 5 * c)
		core.Transparency = c ^ 0.6
		core.CFrame = CFrame.new(p.chest)
	elseif forging then
		local k = math.clamp((t - M.ForgeAt) / I.ImplodeSeconds, 0, 1)
		local size = (I.NovaStuds * 0.55) * (1 - k ^ 2)
		nova.Size = Vector3.one * math.max(size, 0.1)
		nova.Transparency = if k < 1 then 0.35 + 0.65 * k else 1
		nova.CFrame = CFrame.new(p.cueMiddle)
		core.Transparency = 1
	else
		nova.Transparency = 1
		core.Transparency = 1
	end
	-- The shockwaves out over the roof.
	for i, pair in { { p.shock, p.shockArt }, { p.shock2, p.shock2Art } } do
		local part: Part, art: ImageLabel = pair[1], pair[2]
		local k = math.clamp((after - (i - 1) * 0.08) / I.ShockSeconds, 0, 1)
		local size = 4 + (I.ShockStuds * (1 - (i - 1) * 0.3) - 4) * (1 - (1 - k) ^ 3)
		part.Size = Vector3.new(size, 0.05, size)
		art.ImageTransparency = if hit and k < 1 and not forging then 0.35 + 0.65 * k else 1
	end
	-- The pillar of light up from the player.
	local pillar: Beam = p.pillar
	local pk = math.clamp(after / I.PillarSeconds, 0, 1)
	pillar.Enabled = hit and pk < 1 and not forging
	pillar.Width0 = I.PillarWidthStuds * (1 - pk)
	pillar.Width1 = I.PillarWidthStuds * 0.5 * (1 - pk)
	local flare: PointLight = p.flare
	flare.Color = PullKit.cycle(colours, w, 1)
	-- (its light dies on real time: the ground is not left glaring through bullet time)
	flare.Brightness = if hit and not forging
		then I.Light * math.exp(-math.max(t - M.ImpactAt, 0) * 4)
		else 0
	-- Time runs again: what hung in the air falls into the forge point.
	if forging and not s.fired.unfreeze then
		s.fired.unfreeze = true
		p.sparks:Clear()
		p.shards:Clear()
		p.burst:Clear()
		p.rays:Clear()
	end
end

-- The forge and the hero shot: the cue forms in the light, the sigil lights, the starlight
-- swirls round it ever faster with the rise, and it flares into the white.
local function stepForge(s: Scene, t: number, dt: number, cueId: string)
	local F = M.Forge
	local p = s.parts
	local colours: { Color3 } = p.colours
	local q = Quality.rate()
	local forging = t >= M.ForgeAt
	local riseK = between(t, M.CueAt, M.FlashAt)
	-- The light falls in, the point grows white-hot, the cue forms behind it.
	p.implode.Rate = if forging and t < M.CueAt + 0.1 then F.ImplodeRate * q else 0
	local glowIn = between(t, M.ForgeAt, M.CueAt)
	local glowOut = between(t, M.CueAt, M.CueAt + F.RevealSeconds)
	local flareUp = between(t, M.FlashAt - F.FlareSeconds, M.FlashAt)
	if t >= M.CueAt and not s.fired.cue then
		s.fired.cue = true
		p.cue = PullKit.showCue(s, cueId, PullKit.uprightTip(p.cueMiddle, 0))
		p.born:Emit(math.floor(F.BornSparks * q))
	end
	local hasCue = p.cue ~= nil
	-- Without the cue the light stays as a turning rainbow star: the moment is pure light.
	local starStay = if hasCue then 0 else between(t, M.CueAt, M.CueAt + 0.3)
	local glow = if forging then glowIn * (1 - glowOut) else 0
	glow = math.max(glow, flareUp, starStay * 0.55)
	local function show(image: ImageLabel, studs: number, transparency: number, amount: number)
		image.ImageTransparency = if amount > 0.001
			then 1 - (1 - transparency) * math.min(amount, 1)
			else 1
		local board = image.Parent :: BillboardGui
		local px = studs * math.max(amount, 0.05)
		board.Size = UDim2.fromScale(px, px)
	end
	local flareGrow = 1 + F.FlareGrow * flareUp * flareUp
	show(p.forgeGlow, F.GlowStuds * flareGrow, 0, glow)
	show(p.forgeFlare, F.GlowStuds * 1.6 * flareGrow, 0.1, math.max(glow * 0.7, starStay))
	show(
		p.forgeRays,
		F.GlowStuds * 2.6 * flareGrow,
		0.5,
		math.max(glow * 0.5, starStay * 0.8, riseK * 0.35)
	)
	p.forgeFlare.Rotation = t * 60
	p.forgeRays.Rotation = -t * 20
	p.forgeFlare.ImageColor3 = PullKit.cycle(colours, t, 1.6)
	p.forgeRays.ImageColor3 = PullKit.cycle(colours, t + 0.8, 1.6)
	local light: PointLight = p.forgeLight
	light.Color = PullKit.cycle(colours, t, 2)
	light.Brightness = if forging then F.Light * (0.4 + glow + riseK) else 0
	-- The cue turns and bobs, faster as the rise climbs.
	if hasCue then
		p.cueSpin = (p.cueSpin or 0) + (F.SpinPerSecond + F.SpinRise * riseK * riseK) * dt
		local bob = math.sin(t * 2.1) * F.BobStuds
		PullKit.placeCue(p.cue, PullKit.uprightTip(p.cueMiddle + UP * bob, p.cueSpin))
	end
	-- The sigil lights under them and turns, faster with the rise.
	local sigilIn = between(t, M.CueAt - 0.2, M.CueAt + 0.6)
	local sigil: Part = p.sigil
	local studs = F.SigilStuds * (0.6 + 0.4 * sigilIn)
	sigil.Size = Vector3.new(studs, 0.05, studs)
	p.sigilTurn = (p.sigilTurn or 0) + (F.SigilTurn + F.SigilTurnRise * riseK * riseK) * dt
	sigil.CFrame = CFrame.new(p.sigilAt) * CFrame.Angles(0, p.sigilTurn, 0)
	p.sigilArt.ImageTransparency = 1 - sigilIn * (0.75 + 0.25 * math.sin(t * 5))
	p.sigilArt.ImageColor3 = PullKit.cycle(colours, t, 3)
	-- Starlight orbiting the cue.
	local orbiting = t >= M.CueAt
	for i, o in p.orbiters do
		o.trail.Enabled = orbiting
		if orbiting then
			local speed = F.OrbitPerSecond * (1 + F.OrbitRise * riseK * riseK)
			o.angle = (o.angle or o.phase) + speed * dt
			local r = F.OrbitStuds * (1 - 0.25 * riseK)
			local ring = CFrame.new(p.cueMiddle) * CFrame.Angles(o.tilt, i * 1.3, 0)
			local at = ring * Vector3.new(math.cos(o.angle) * r, 0, math.sin(o.angle) * r)
			local camRight = workspace.CurrentCamera.CFrame.RightVector
			o.a0.WorldPosition = at + camRight * 0.12
			o.a1.WorldPosition = at - camRight * 0.12
		end
	end
	-- Motes rising off the sigil, more with the rise.
	p.motes.Rate = if orbiting then (F.MoteRate + F.MoteRise * riseK) * q else 0
end

-- The camera, shot by shot (see the header).
local function stepCamera(s: Scene, t: number, w: number)
	local Sh = M.Shots
	local p = s.parts
	local feet: Vector3, facing: Vector3, right: Vector3 = p.feet, p.facing, p.right
	local cam = workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local eye: Vector3, focus: Vector3, fov: number
	local handheld = 0
	if t < Sh.Wonder.At then
		local S1 = Sh.Night
		local k = smooth((t - M.HitAt) / (Sh.Wonder.At - M.HitAt))
		local studs = S1.FromStuds + (S1.ToStuds - S1.FromStuds) * k
		focus = feet + UP * (S1.LookHeightStuds + S1.LookRiseStuds * k)
		eye = PullKit.clampEye(
			s,
			feet + UP * 2,
			feet + facing * studs + right * S1.SideStuds + UP * S1.HeightStuds
		)
		fov = S1.FieldOfView
		handheld = S1.Handheld
	elseif t < Sh.Star.At then
		local S2 = Sh.Wonder
		local k = smooth((t - S2.At) / (Sh.Star.At - S2.At))
		local up = between(t, M.TurnAt, M.FuseAt)
		eye = PullKit.clampEye(
			s,
			feet + UP * 3,
			feet
				- facing * (S2.BackStuds - S2.PushStuds * k)
				+ right * S2.SideStuds
				+ UP * S2.HeightStuds
		)
		local sky = feet + facing * S2.LookAheadStuds + UP * S2.LookHeightStuds
		focus = sky:Lerp(p.point, up * S2.ToPointShare)
		fov = S2.FieldOfView - S2.Narrow * up
		handheld = S2.Handheld
	elseif t < Sh.Fall.At then
		local S3 = Sh.Star
		local k = smooth((t - S3.At) / (Sh.Fall.At - S3.At))
		-- Low behind the player's other shoulder, looking up past them at the newborn star.
		eye = PullKit.clampEye(
			s,
			feet + UP * 2,
			feet
				- facing * (S3.Studs - S3.PushStuds * k)
				+ right * S3.SideStuds
				+ UP * S3.HeightStuds
		)
		local point: Vector3 = p.point
		local toFeet = Vector3.new(feet.X - eye.X, 0, feet.Z - eye.Z)
		local toPoint = Vector3.new(point.X - eye.X, 0, point.Z - eye.Z)
		local low = math.atan2(feet.Y + 3.5 - eye.Y, math.max(toFeet.Magnitude, 0.5))
		local high = math.atan2(point.Y - eye.Y, math.max(toPoint.Magnitude, 0.5))
		local tilt = low + (high - low) * S3.TiltShare
		local toward = if toPoint.Magnitude > 1e-3 then toPoint.Unit else facing
		focus = eye + toward * math.cos(tilt) + UP * math.sin(tilt)
		fov = S3.FieldOfView - 8 * math.exp(-math.max(t - M.FuseAt, 0) * 8)
	elseif t < Sh.Bullet.At then
		local S4 = Sh.Fall
		local a = math.rad(S4.Degrees)
		local dir = facing * math.cos(a) + right * math.sin(a)
		eye = PullKit.clampEye(s, feet + UP * 3, feet + dir * S4.Studs + UP * S4.HeightStuds)
		-- Wide and still from the side: the player small below, the star high above; the
		-- comet crosses the whole picture.
		local chest: Vector3 = p.chest
		focus = chest:Lerp(p.point, S4.FollowShare)
		fov = S4.FieldOfView
	elseif t < Sh.Forge.At then
		local S5 = Sh.Bullet
		local k = smooth((t - S5.At) / (Sh.Forge.At - S5.At))
		local a = math.rad(S5.FromDegrees + (S5.ToDegrees - S5.FromDegrees) * k)
		local dir = facing * math.cos(a) + right * math.sin(a)
		local studs = S5.FromStuds + (S5.ToStuds - S5.FromStuds) * k
		eye = PullKit.clampEye(
			s,
			feet + UP * 3,
			feet + dir * studs + UP * (S5.FromHeight + (S5.ToHeight - S5.FromHeight) * k)
		)
		focus = p.chest
		fov = S5.FieldOfView
	else
		local S6 = Sh.Forge
		local k = smooth((t - S6.At) / (M.FlashAt - S6.At))
		local a = math.rad(S6.FromDegrees + (S6.ToDegrees - S6.FromDegrees) * k)
		local dir = facing * math.cos(a) + right * math.sin(a)
		local rush = between(t, M.FlashAt - S6.RushSeconds, M.FlashAt)
		local studs = S6.FromStuds + (S6.ToStuds - S6.FromStuds) * k
		studs += (S6.RushStuds - studs) * rush * rush
		-- Round a point between the player and the cue (both in the picture), then into the cue.
		local middle: Vector3 = p.cueMiddle
		local pivot = (p.chest :: Vector3):Lerp(middle, S6.PivotShare):Lerp(middle, rush)
		eye = PullKit.clampEye(
			s,
			pivot,
			pivot + dir * studs + UP * (S6.FromHeight + (S6.ToHeight - S6.FromHeight) * k)
		)
		focus = pivot + UP * S6.LookAboveStuds * (1 - rush)
		fov = S6.FromFov + (S6.ToFov - S6.FromFov) * k - S6.RushFov * rush
		handheld = S6.Handheld * (1 + 2 * rush)
	end
	local frame = CFrame.lookAt(eye, focus)
	-- A slow handheld drift; the hit's jolt and heavy shake on the warped clock (so bullet time
	-- slows it too), and the rush's shake at the end.
	local I = M.Impact
	local amount, kick = handheld, 0
	if t >= M.ImpactAt and t < M.ForgeAt then
		local after = w - M.ImpactAt
		amount += I.ShakeStuds * math.max(0, 1 - after / I.ShakeSeconds) ^ 2
		local k = after * 14
		kick = I.KickStuds * k * math.exp(1 - k)
		fov -= I.PunchFov * math.exp(-math.max(t - M.ImpactAt, 0) * 6)
	end
	frame = PullKit.shake(
		frame,
		w,
		amount,
		kick,
		I.ShakeHz,
		I.ShakeRollDegrees * math.min(amount / I.ShakeStuds, 1)
	)
	cam.FieldOfView = math.clamp(fov, 20, 110)
	cam.CFrame = frame
	cam.Focus = CFrame.new(focus)
	-- A shallow focus on whatever the shot is about (none in the sky shots).
	local dof = Lighting:FindFirstChildOfClass("DepthOfFieldEffect")
	if dof then
		local onSubject = t >= Sh.Fall.At
		dof.Enabled = true
		dof.FocusDistance = (focus - eye).Magnitude
		dof.InFocusRadius = M.Focus.RadiusStuds
		dof.FarIntensity = if onSubject then M.Focus.Far else 0
		dof.NearIntensity = 0
	end
end

--- One frame of the scene at `t` seconds (from the end of the fade to black).
function PullMythic.step(s: Scene, t: number)
	if not s.parts.feet then
		PullKit.collectSounds(s) -- before its own track starts, so the track is not among them
		PullKit.spareSounds(s, { M.Sounds.Logo, M.Sounds.Rise, M.Sounds.Ambience })
		build(s)
		UISound.play(M.Sounds.Logo)
	end
	local p = s.parts
	-- The film keeps to the track's own clock (like the Legendary): a late-loading sound
	-- cannot put the cut-in, the fusion and the hit out of step with it.
	local position, playing = UISound.position(M.Sounds.Logo)
	if playing and position > 0.05 and position < 1 then
		p.lag = math.clamp(t - position, 0, 0.5)
	end
	t -= p.lag or 0
	-- Everything else in the world goes quiet under the film.
	PullKit.quietSounds(s, 1 - between(t, 0, M.QuietSeconds))
	local w = PullMath.warp(t, M.SlowFrom, M.SlowTo, M.SlowSpeed, M.SlowRampSeconds)
	local dt = math.clamp(t - (p.lastT or t), 0, 0.1)
	p.lastT = t
	-- The black until the track's first hit: then a hard cut in.
	s.black.BackgroundTransparency = if t < M.HitAt then 0 else 1
	stepNight(s, t)
	stepStars(s, t)
	stepStar(s, t)
	stepImpact(s, t, w)
	stepForge(s, t, dt, s.cueId)
	stepCamera(s, t, w)
	local riseAt = M.FlashAt - M.RiseStopSeconds
	if t >= riseAt and not s.fired.rise then
		s.fired.rise = true
		UISound.play(M.Sounds.Rise)
	end
	if t >= M.FlashAt and not s.fired.finale then
		s.fired.finale = true
		UISound.play(M.Sounds.Finale)
	end
	s.white.BackgroundTransparency = 1 - math.clamp((t - M.FlashAt) / M.FlashInSeconds, 0, 1)
end

--- The card is showing (played out, skipped or stopped): a cut-short scene's sounds stop with
--- it; the very faint ambience starts under the card (PullCutscene.cardClosed tapers it).
function PullMythic.reveal(s: Scene)
	if not s.fired.finale then
		for _, sound in
			{ M.Sounds.Logo, M.Sounds.Rise, M.Sounds.Gather, M.Sounds.Slow, M.Sounds.Boom }
		do
			UISound.stop(sound)
		end
	end
	UISound.play(M.Sounds.Ambience)
end

--- The images and sounds to load before a Mythic pull (from its reel).
function PullMythic.assets(): { string }
	return {
		ART.MilkyWay,
		ART.NebulaA,
		ART.NebulaB,
		ART.Sigil,
		ART.LightShard,
		ART.StarFlare,
		ART.BeamSoft,
		K.SoftGlow,
		K.Spark,
		K.Rays,
		K.RingGlow,
	}
end

return PullMythic
