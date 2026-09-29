--!strict
-- MagnetFx: what Magnet looks and sounds like (docs/prompts/ULTIMATES_PROMPT.md 7.3). The
-- physics is src/shared/Ults/Effects/Magnet.luau; this only draws it. Numbers in
-- Config.UI.MagnetFx, sounds in Config.Ults.Audio, art in Config.UI.Kit.Art (every image
-- falls back to plain Beams or Roblox's own particle when its id is still "").
--
-- Armed (from `armed.readyAt` while a table's snapshot has Magnet armed, until the shot goes):
-- a low hum loops at the cue ball (3D, quiet); two thin rings, red N and blue S, circle the
-- cue ball, each tilted and precessing the opposite way with a bead running round it; faint
-- field arcs loop from one side of the ball to the other, flickering. The arming moment
-- (arming(), called by UltCutscene at readyAt) snaps the rings in from wide with a zap and a
-- few sparks. Everyone near the table sees it: it reads only the table's snapshot.
--
-- The ult shot (the replay carries overrides.Effect == "Magnet"): each frame,
-- Magnet.activePulls on the replay's own state says which balls are in a capture zone. Each
-- such pocket gets a pulsing ring on the cloth; a curved field-line beam runs from the pocket
-- to the ball, flowing toward the pocket; the ball glows blue and crackles; the hum rises in
-- pitch. A pulled ball's drop gets a clunk-zap and a burst of sparks at the pocket. The rings
-- fade as the shot starts and everything fades when it ends.
--
-- Only tables whose balls are drawn get anything (Hub's renderer pool); a table that stops
-- being drawn loses its effects at once. Everything hangs off one invisible anchored part per
-- table, destroyed when the table's effects are done, so nothing leaks across shots or tables.
-- Randomness here is visual only (the arcs' flicker).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local UIAnim = require(script.Parent:WaitForChild("UIAnim"))

local F = Config.UI.MagnetFx
local A = Config.Ults.Audio
local ART = Config.UI.Kit.Art

-- Magnet.activePulls, if the module is there (guarded so a missing or broken physics module
-- only costs the pull visuals, never the client).
type Pull = { ball: number, pocket: number, strength: number }
local activePulls: ((any) -> { Pull })? = nil
do
	local ok, found = pcall(function()
		local ults = Shared:FindFirstChild("Ults")
		local effects = ults and ults:FindFirstChild("Effects")
		local module = effects and effects:FindFirstChild("Magnet")
		return if module and module:IsA("ModuleScript") then (require :: any)(module) else nil
	end)
	if ok and type(found) == "table" and type(found.activePulls) == "function" then
		activePulls = found.activePulls
	end
end

-- 4/3 tan(pi/8): a cubic Bezier's handle for a quarter circle of radius 1.
local KAPPA = 0.5523
local TAU = 2 * math.pi
local FALLBACK_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A frame at `pos` whose X (an attachment's Axis, which a Beam's curve follows) is `x`.
local function along(pos: Vector3, x: Vector3): CFrame
	local ref = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(ref).Unit
	return CFrame.fromMatrix(pos, x, z:Cross(x).Unit)
end

type Ring = { atts: { Attachment }, beams: { Beam }, bead: Part? }

type Arc = { a0: Attachment, a1: Attachment, beam: Beam, alpha: number, nextFlicker: number }

type PullFx = {
	ballAt: Attachment,
	ends: { Attachment }, -- the pocket end of each beam (its own axis, for its own bow)
	starts: { Attachment }, -- the ball end of each beam
	beams: { Beam },
	light: PointLight,
	glow: ImageLabel?,
	crackle: Sound?,
	level: number,
	target: number,
	pocket: number,
}

type PocketFx = {
	plate: Part?,
	image: ImageLabel?,
	ring: Ring?, -- the no-art fallback: a beam circle
	level: number,
	target: number,
	started: number,
}

type TableFx = {
	anchor: Part,
	cue: Attachment,
	hum: Sound?,
	arm: Sound?,
	rings: { Ring },
	arcs: { Arc },
	look: number,
	snapAt: number?,
	snapFor: number?, -- the armed.at the snap was for
	pulls: { [number]: PullFx },
	pockets: { [number]: PocketFx },
	pulled: { [number]: boolean }, -- balls pulled on this shot
	shotSeq: number?,
	shot: number, -- 0-1: the ult shot's effects, fading out once it ends
	pitchMix: number,
	sparkAt: Attachment,
	sparks: ParticleEmitter,
	keepUntil: number, -- os.clock(): something (a spark, a drop sound) still needs the anchor
}

local MagnetFx = {}
MagnetFx.__index = MagnetFx

export type MagnetFx = typeof(setmetatable(
	{} :: {
		hub: any,
		parent: Instance,
		tables: { [number]: TableFx },
		consumed: { [number]: number }, -- tableId -> the armed.at a Magnet shot has spent
		random: Random,
	},
	MagnetFx
))

---------------------------------------------------------------------------------------------
-- Instances
---------------------------------------------------------------------------------------------

local function newSound(parent: Instance, clip: any, looped: boolean): Sound?
	if clip == nil or clip.Id == "" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.SoundId = clip.Id
	sound.Volume = clip.Volume
	sound.Looped = looped
	sound.RollOffMinDistance = Config.Audio.RollOffMinStuds
	sound.RollOffMaxDistance = Config.Audio.RollOffMaxStuds
	sound.RollOffMode = (Enum.RollOffMode :: any)[Config.Audio.RollOffMode]
	sound.PlayOnRemove = false
	sound.Parent = parent
	return sound
end

-- Play a one-shot from its StartOffset (Play() resumes from the last TimePosition written).
local function fire(sound: Sound?, offset: number?)
	if sound then
		sound:Stop()
		sound.TimePosition = offset or 0
		sound:Play()
	end
end

local function newBeam(
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	color: Color3,
	width: number
): Beam
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = width
	beam.Width1 = width
	beam.FaceCamera = true
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Segments = F.BeamSegments
	beam.Transparency = NumberSequence.new(1)
	beam.Parent = parent
	return beam
end

local function newAttachment(anchor: BasePart, name: string): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Parent = anchor
	return a
end

-- A circle of four Bezier quarter-beams (and a bead running round it, if asked).
local function newRing(
	anchor: BasePart,
	name: string,
	color: Color3,
	width: number,
	bead: boolean
): Ring
	local atts, beams = {}, {}
	for k = 1, 4 do
		atts[k] = newAttachment(anchor, name .. k)
	end
	for k = 1, 4 do
		beams[k] = newBeam(anchor, atts[k], atts[k % 4 + 1], color, width)
	end
	local ball: Part? = nil
	if bead then
		local part = Instance.new("Part")
		part.Name = name .. "Bead"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.one * F.BeadStuds
		part.Material = Enum.Material.Neon
		part.Color = color
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Parent = anchor
		ball = part
	end
	return { atts = atts, beams = beams, bead = ball }
end

-- Lay `ring` round `center` in the plane square to `normal`, turned by `spin`. Returns the
-- plane's two axes (for placing the bead).
local function placeRing(
	ring: Ring,
	center: Vector3,
	normal: Vector3,
	radius: number,
	spin: number,
	transparency: number
): (Vector3, Vector3)
	local ref = if math.abs(normal.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local u = normal:Cross(ref).Unit
	local v = normal:Cross(u).Unit
	for k = 1, 4 do
		local theta = spin + (k - 1) * math.pi / 2
		local c, s = math.cos(theta), math.sin(theta)
		local tangent = v * c - u * s
		ring.atts[k].CFrame = CFrame.fromMatrix(center + (u * c + v * s) * radius, tangent, normal)
	end
	local seq = NumberSequence.new(transparency)
	for _, beam in ring.beams do
		beam.CurveSize0 = KAPPA * radius
		beam.CurveSize1 = KAPPA * radius
		beam.Transparency = seq
	end
	return u, v
end

local function hideRing(ring: Ring)
	local seq = NumberSequence.new(1)
	for _, beam in ring.beams do
		beam.Transparency = seq
	end
	if ring.bead then
		ring.bead.Transparency = 1
	end
end

local function textureBeam(beam: Beam, length: number, speed: number)
	if ART.FieldLines ~= "" then
		beam.Texture = ART.FieldLines
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = length
		beam.TextureSpeed = speed
	end
end

local function create(self: MagnetFx, id: number): TableFx
	local anchor = Instance.new("Part")
	anchor.Name = ("MagnetFx_%02d"):format(id)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.identity -- so every attachment's CFrame is its world CFrame
	anchor.Parent = self.parent

	local cue = newAttachment(anchor, "Cue")
	local hum = newSound(cue, A.MagnetHum, true)
	if hum then
		hum.Volume = 0
		hum.PlaybackSpeed = A.MagnetHum.Pitch
		hum:Play()
	end

	local rings = {
		newRing(anchor, "North", rgb(F.NorthColor), F.RingWidthStuds, true),
		newRing(anchor, "South", rgb(F.SouthColor), F.RingWidthStuds, true),
	}
	local arcs: { Arc } = {}
	for i = 1, #F.ArcAngles do
		local a0 = newAttachment(anchor, "ArcN" .. i)
		local a1 = newAttachment(anchor, "ArcS" .. i)
		local beam = newBeam(anchor, a0, a1, rgb(F.FieldColor), F.ArcWidthStuds)
		textureBeam(beam, F.ArcTextureLengthStuds, F.ArcTextureSpeed)
		table.insert(arcs, { a0 = a0, a1 = a1, beam = beam, alpha = 1, nextFlicker = 0 })
	end

	local sparkAt = newAttachment(anchor, "Sparks")
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = if ART.Spark ~= "" then ART.Spark else FALLBACK_SPARK
	sparks.Color = ColorSequence.new(rgb(F.SparkColor))
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, F.SparkSizeStuds),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Lifetime = NumberRange.new(F.SparkLifetime[1], F.SparkLifetime[2])
	sparks.Speed = NumberRange.new(F.SparkSpeed[1], F.SparkSpeed[2])
	sparks.SpreadAngle = Vector2.new(F.SparkSpreadDegrees, F.SparkSpreadDegrees)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -F.SparkGravity, 0)
	sparks.Drag = F.SparkDrag
	sparks.Rotation = NumberRange.new(0, 360)
	sparks.RotSpeed = NumberRange.new(-180, 180)
	sparks.Rate = 0
	sparks.Enabled = false
	sparks.Parent = sparkAt

	local fx: TableFx = {
		anchor = anchor,
		cue = cue,
		hum = hum,
		arm = newSound(cue, A.MagnetArm, false),
		rings = rings,
		arcs = arcs,
		look = 0,
		snapAt = nil,
		snapFor = nil,
		pulls = {},
		pockets = {},
		pulled = {},
		shotSeq = nil,
		shot = 0,
		pitchMix = 0,
		sparkAt = sparkAt,
		sparks = sparks,
		keepUntil = 0,
	}
	self.tables[id] = fx
	return fx
end

local function destroy(self: MagnetFx, id: number)
	local fx = self.tables[id]
	if fx then
		self.tables[id] = nil
		fx.anchor:Destroy()
	end
end

local function newPull(fx: TableFx, ball: number): PullFx
	local anchor = fx.anchor
	local ballAt = newAttachment(anchor, "Pulled" .. ball)
	local starts, ends, beams = {}, {}, {}
	for i = 1, 2 do
		starts[i] = newAttachment(anchor, ("Pull%d_%d_Ball"):format(ball, i))
		ends[i] = newAttachment(anchor, ("Pull%d_%d_Pocket"):format(ball, i))
		local beam = newBeam(anchor, starts[i], ends[i], rgb(F.GlowColor), F.BeamWidthStuds[1])
		beam.Width1 = F.BeamWidthStuds[2]
		textureBeam(beam, F.BeamTextureLengthStuds, F.BeamTextureSpeed)
		beams[i] = beam
	end
	local light = Instance.new("PointLight")
	light.Color = rgb(F.GlowColor)
	light.Range = F.GlowRangeStuds
	light.Brightness = 0
	light.Shadows = false
	light.Parent = ballAt
	local glow: ImageLabel? = nil
	if ART.SoftGlow ~= "" then
		local board = Instance.new("BillboardGui")
		local size = TableBuilder.studs(Config.Balls.RenderRadiusInches * 2) * F.GlowBallWidths
		board.Size = UDim2.fromScale(size, size)
		board.LightInfluence = 0
		board.AlwaysOnTop = false
		board.ResetOnSpawn = false
		board.Parent = ballAt
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = ART.SoftGlow
		image.ImageColor3 = rgb(F.GlowColor)
		image.ImageTransparency = 1
		image.Parent = board
		glow = image
	end
	local crackle = newSound(ballAt, A.MagnetPull, true)
	if crackle then
		crackle.Volume = 0
		crackle:Play()
	end
	local pull: PullFx = {
		ballAt = ballAt,
		ends = ends,
		starts = starts,
		beams = beams,
		light = light,
		glow = glow,
		crackle = crackle,
		level = 0,
		target = 0,
		pocket = 0,
	}
	fx.pulls[ball] = pull
	return pull
end

local function dropPull(pull: PullFx)
	pull.ballAt:Destroy()
	for i = 1, #pull.beams do
		pull.beams[i]:Destroy()
		pull.starts[i]:Destroy()
		pull.ends[i]:Destroy()
	end
end

local function newPocket(fx: TableFx, pocket: number): PocketFx
	local p: PocketFx =
		{ plate = nil, image = nil, ring = nil, level = 0, target = 0, started = os.clock() }
	if ART.RingGlow ~= "" then
		local plate = Instance.new("Part")
		plate.Name = "PocketRing" .. pocket
		plate.Anchored = true
		plate.CanCollide = false
		plate.CanQuery = false
		plate.CanTouch = false
		plate.CastShadow = false
		plate.Transparency = 1
		plate.Size = Vector3.new(1, 0.02, 1)
		plate.Parent = fx.anchor
		local surface = Instance.new("SurfaceGui")
		surface.Face = Enum.NormalId.Top
		surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		surface.PixelsPerStud = F.PocketPixelsPerStud
		surface.LightInfluence = 0
		surface.Brightness = F.PocketBrightness
		surface.AlwaysOnTop = false
		surface.ResetOnSpawn = false
		surface.Parent = plate
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = ART.RingGlow
		image.ImageColor3 = rgb(F.GlowColor)
		image.ImageTransparency = 1
		image.Parent = surface
		p.plate, p.image = plate, image
	else
		p.ring = newRing(
			fx.anchor,
			"PocketRing" .. pocket,
			rgb(F.GlowColor),
			F.PocketRingWidthStuds,
			false
		)
	end
	fx.pockets[pocket] = p
	return p
end

local function dropPocket(p: PocketFx)
	if p.plate then
		p.plate:Destroy()
	end
	local ring = p.ring
	if ring then
		for k = 1, 4 do
			ring.beams[k]:Destroy()
			ring.atts[k]:Destroy()
		end
	end
end

---------------------------------------------------------------------------------------------
-- Per frame
---------------------------------------------------------------------------------------------

local function magnetArmed(snapshot: any): any
	local ults = snapshot and snapshot.ults
	local armed = if type(ults) == "table" then ults.armed else nil
	if type(armed) ~= "table" or type(armed.at) ~= "number" then
		return nil
	end
	local ult = Catalog.get(armed.id)
	return if ult and ult.Effect == "Magnet" then armed else nil
end

local function ballWorld(m: any, b: any): Vector3
	return TableBuilder.toWorld(m.placement, b.x, b.y, Config.Balls.RenderRadiusInches + b.z)
end

local function ballOf(m: any, id: number): any
	for _, b in m.state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

local function pocketOf(m: any, id: number): any
	for _, p in m.state.geometry.pockets do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function stepLook(self: MagnetFx, fx: TableFx, m: any, t: number)
	local cue = m:findCueBall()
	if cue == nil then
		return
	end
	local center = ballWorld(m, cue)
	fx.cue.CFrame = CFrame.new(center)
	if fx.look <= 0.001 then
		for _, ring in fx.rings do
			hideRing(ring)
		end
		for _, arc in fx.arcs do
			arc.beam.Transparency = NumberSequence.new(1)
		end
		return
	end
	local ballR = TableBuilder.studs(Config.Balls.RenderRadiusInches)
	local scale = 1
	if fx.snapAt then
		local u = (os.clock() - fx.snapAt) / F.SnapSeconds
		if u < 1 then
			scale = lerp(F.SnapFromScale, 1, UIAnim.backOut(u))
		end
	end
	local radius = ballR * F.RingRadiusBalls * scale
	local tilt = math.rad(F.RingTiltDegrees)
	local ringAlpha = 1 - (1 - F.RingTransparency) * fx.look
	for i, ring in fx.rings do
		local sign = if i == 1 then 1 else -1
		local phi = sign * TAU * t / F.RingTurnSeconds + (i - 1) * math.pi
		local normal = Vector3.new(
			math.sin(tilt) * math.cos(phi),
			math.cos(tilt),
			math.sin(tilt) * math.sin(phi)
		)
		local u, v = placeRing(ring, center, normal, radius, 0, ringAlpha)
		local bead = ring.bead
		if bead then
			local theta = sign * TAU * t / F.BeadSeconds
			bead.CFrame = CFrame.new(center + (u * math.cos(theta) + v * math.sin(theta)) * radius)
			bead.Transparency = ringAlpha
		end
	end
	-- The field: a dipole across the ball, turning slowly, its lines looping over the top.
	local psi = TAU * t / F.ArcTurnSeconds
	local axis = Vector3.new(math.cos(psi), 0, math.sin(psi))
	local side = Vector3.new(-axis.Z, 0, axis.X)
	local spread = math.rad(F.ArcSpreadDegrees)
	local reach = F.ArcReachStuds * scale
	for i, arc in fx.arcs do
		local beta = math.rad(F.ArcAngles[i])
		local out = side * math.cos(beta) + Vector3.yAxis * math.sin(beta)
		arc.a0.CFrame =
			along(center + axis * ballR, (axis * math.cos(spread) + out * math.sin(spread)).Unit)
		arc.a1.CFrame =
			along(center - axis * ballR, (axis * math.cos(spread) - out * math.sin(spread)).Unit)
		arc.beam.CurveSize0 = reach
		arc.beam.CurveSize1 = reach
		if t >= arc.nextFlicker then
			arc.alpha = self.random:NextNumber(F.ArcTransparency[1], F.ArcTransparency[2])
			arc.nextFlicker = t + F.ArcFlickerSeconds * self.random:NextNumber(0.5, 1.5)
		end
		arc.beam.Transparency = NumberSequence.new(1 - (1 - arc.alpha) * fx.look)
	end
end

local function stepPulls(fx: TableFx, m: any, magnetShot: boolean, dt: number, t: number)
	for _, pull in fx.pulls do
		pull.target = 0
	end
	if magnetShot and activePulls then
		local ok, list = pcall(activePulls :: any, m.state)
		if ok and type(list) == "table" then
			for _, p in list :: { Pull } do
				local pull = fx.pulls[p.ball] or newPull(fx, p.ball)
				pull.target = math.clamp(p.strength, 0, 1)
				pull.pocket = p.pocket
				fx.pulled[p.ball] = true
			end
		end
	end
	for _, pocket in fx.pockets do
		pocket.target = 0
	end
	local strongest = 0
	for id, pull in fx.pulls do
		-- Rises quickly, lets go a little slower.
		local seconds = if pull.target > pull.level then F.PullRiseSeconds else F.PullFadeSeconds
		pull.level = approach(pull.level, pull.target, dt, seconds)
		local b = ballOf(m, id)
		local pocket = pocketOf(m, pull.pocket)
		if (pull.level <= 0.005 and pull.target == 0) or b == nil or pocket == nil then
			dropPull(pull)
			fx.pulls[id] = nil
			continue
		end
		strongest = math.max(strongest, pull.level)
		local p = fx.pockets[pull.pocket] or newPocket(fx, pull.pocket)
		p.target = math.max(p.target, pull.level)

		local from = ballWorld(m, b)
		local to =
			TableBuilder.toWorld(m.placement, pocket.x, pocket.y, Config.Balls.RenderRadiusInches)
		pull.ballAt.CFrame = CFrame.new(from)
		local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local dist = flat.Magnitude
		local dir = if dist > 1e-4 then flat / dist else Vector3.xAxis
		for i, beam in pull.beams do
			local sign = if i == 1 then 1 else -1
			local bow = (
				dir:Cross(Vector3.yAxis) * sign * F.BeamBowSide + Vector3.yAxis * F.BeamBowUp
			).Unit
			pull.starts[i].CFrame = along(from, bow)
			pull.ends[i].CFrame = along(to, -bow)
			local curve = dist * F.BeamBowShare * (if i == 1 then 1 else F.SecondBeamBowScale)
			beam.CurveSize0 = curve
			beam.CurveSize1 = curve
			local base = if i == 1 then F.BeamTransparency else F.SecondBeamTransparency
			beam.Transparency = NumberSequence.new(1 - (1 - base) * pull.level)
		end
		pull.light.Brightness = F.GlowBrightness * pull.level
		if pull.glow then
			local flicker = 1 + F.GlowPulseShare * math.sin(TAU * t / F.GlowPulseSeconds)
			pull.glow.ImageTransparency = 1
				- math.clamp(pull.level * flicker, 0, 1) * (1 - F.GlowTransparency)
		end
		if pull.crackle then
			pull.crackle.Volume = A.MagnetPull.Volume * pull.level
		end
	end
	for id, p in fx.pockets do
		p.level = approach(p.level, p.target, dt, F.PullFadeSeconds)
		local pocket = pocketOf(m, id)
		if (p.level <= 0.005 and p.target == 0) or pocket == nil then
			dropPocket(p)
			fx.pockets[id] = nil
			continue
		end
		local wave = math.sin(TAU * (os.clock() - p.started) / F.PocketPulseSeconds)
		local d = TableBuilder.studs(pocket.radius * 2)
			* F.PocketRingScale
			* (1 + F.PocketPulseScale * wave)
		local at = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.PocketLiftInches)
		local alpha = 1
			- (1 - F.PocketTransparency) * p.level * (1 - F.PocketPulseFade * (wave + 1) / 2)
		if p.plate and p.image then
			p.plate.Size = Vector3.new(d, 0.02, d)
			p.plate.CFrame = CFrame.new(at)
			p.image.ImageTransparency = alpha
		elseif p.ring then
			placeRing(p.ring, at, Vector3.yAxis, d / 2, 0, alpha)
		end
	end
	return strongest
end

--- A pocket event at table `id`: a pulled ball's drop gets the clunk-zap and the sparks.
local function onPocket(self: MagnetFx, id: number, m: any, ev: any)
	local fx = self.tables[id]
	if fx == nil or not fx.pulled[ev.ball] or m.state.time - ev.t > F.FreshSeconds then
		return
	end
	local pocket = pocketOf(m, ev.other)
	if pocket == nil then
		return
	end
	local at = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.PocketLiftInches)
	local spot = newAttachment(fx.anchor, "Drop")
	spot.CFrame = CFrame.new(at)
	fire(newSound(spot, A.MagnetClunk, false))
	fire(newSound(spot, A.MagnetZap, false))
	task.delay(F.DropSoundSeconds, function()
		spot:Destroy()
	end)
	fx.sparkAt.CFrame = CFrame.new(at)
	fx.sparks:Emit(F.SparkCount)
	fx.keepUntil =
		math.max(fx.keepUntil, os.clock() + math.max(F.SparkLifetime[2], F.DropSoundSeconds))
end

--- Start drawing Magnet for every table `hub` (src/client/Hub.luau) holds, under `parent`.
--- Call update(dt) every frame after hub:update(dt), and arming() at each arming moment.
function MagnetFx.start(hub: any, parent: Instance): MagnetFx
	local self = setmetatable({
		hub = hub,
		parent = parent,
		tables = {},
		consumed = {},
		random = Random.new(),
	}, MagnetFx)
	for id, m in hub.matches do
		m:onEvent(function(ev, _index)
			if ev.type == "pocket" then
				onPocket(self, id, m, ev)
			end
		end)
	end
	-- Fetch the sounds and images now, so the first arming is not silent.
	task.spawn(function()
		local list: { any } = {}
		local clips: { any } =
			{ A.MagnetHum, A.MagnetPull, A.MagnetClunk, A.MagnetZap, A.MagnetArm }
		for _, clip in clips do
			if clip.Id ~= "" then
				local sound = Instance.new("Sound")
				sound.SoundId = clip.Id
				table.insert(list, sound)
			end
		end
		for _, key in { "FieldLines", "RingGlow", "Spark", "SoftGlow" } do
			local id = (ART :: any)[key]
			if type(id) == "string" and id ~= "" then
				table.insert(list, id)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
	return self
end

--- The arming moment at table `tableId` (UltCutscene's onArming, at armed.readyAt): for a
--- Magnet, the rings snap onto the cue ball with a zap and a few sparks.
function MagnetFx.arming(self: MagnetFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= "Magnet" or m == nil or m.renderer == nil then
		return
	end
	local fx = self.tables[tableId] or create(self, tableId)
	fx.snapAt = os.clock()
	fx.snapFor = armed.at
	local cue = m:findCueBall()
	if cue then
		local at = ballWorld(m, cue)
		fx.cue.CFrame = CFrame.new(at)
		fx.sparkAt.CFrame = CFrame.new(at)
		fx.sparks:Emit(F.ArmSparkCount)
	end
	fire(fx.arm, A.MagnetArm.StartOffset)
	fx.keepUntil = math.max(fx.keepUntil, os.clock() + F.SparkLifetime[2])
end

--- Every frame, after hub:update(dt) has stepped the replays.
function MagnetFx.update(self: MagnetFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	for id, m in self.hub.matches do
		local fx = self.tables[id]
		if m.renderer == nil then
			if fx then
				destroy(self, id) -- not drawn: nothing to see, nothing kept
			end
			continue
		end
		local armed = magnetArmed(self.hub.snapshots[id])
		local overrides = m.state.overrides
		local magnetShot = m.shot ~= nil and overrides ~= nil and overrides.Effect == "Magnet"
		if magnetShot and armed then
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local wantLook = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (
				armed.stage == "Armed"
				or now >= (armed.readyAt or math.huge)
				or (fx ~= nil and fx.snapFor == armed.at)
			)
		if fx == nil then
			if not (wantLook or magnetShot) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		if magnetShot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			table.clear(live.pulled)
		end
		live.look = approach(live.look, if wantLook then 1 else 0, dt, F.LookFadeSeconds)
		live.shot = approach(live.shot, if magnetShot then 1 else 0, dt, F.EndFadeSeconds)
		stepLook(self, live, m, t)
		local strongest = stepPulls(live, m, magnetShot, dt, t)
		live.pitchMix = approach(live.pitchMix, strongest, dt, F.PitchEaseSeconds)
		local hum = live.hum
		if hum then
			hum.Volume = A.MagnetHum.Volume * math.max(live.look, live.shot)
			hum.PlaybackSpeed = lerp(A.MagnetHum.Pitch, A.MagnetHum.PullPitch, live.pitchMix)
		end
		if
			not wantLook
			and not magnetShot
			and live.look <= 0.001
			and live.shot <= 0.001
			and next(live.pulls) == nil
			and next(live.pockets) == nil
			and t >= live.keepUntil
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function MagnetFx.clear(self: MagnetFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return MagnetFx
