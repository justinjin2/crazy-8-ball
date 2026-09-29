--!strict
-- MagnetFx: what Magnet looks and sounds like (docs/prompts/ABILITIES_PROMPT.md 7.1, reference
-- 01: a flat blue textbook dipole, arrows on every line). The physics is
-- src/shared/Ults/Effects/Magnet.luau; this only draws it. Numbers in Config.UI.MagnetFx,
-- sounds in Config.Ults.Audio, art in Config.UI.Kit.Art. The field-line meshes are the
-- Blender set tools/blender/abilities/magnet.py (Config.Ults.Assets.Models.MagnetField:
-- FieldArcs, FieldFlares, FieldRing, Chevron and PoleCaps, cloned per table from a pool); the
-- pocket lines are Beams tiled with Config.Ults.Assets.Images.MagnetFieldBeam.
--
-- Armed (from `armed.readyAt` while a table's snapshot has Magnet armed, until the shot goes):
-- a low hum loops at the cue ball (3D, quiet). The cue ball becomes a little dipole: red N and
-- blue S caps on it, N along the shooter's aim (the aim stream every client hears, eased; a
-- slow turn when none is heard), and the field arcs lying flat on the cloth round it, three
-- nested loops each side from N to S, with small chevrons flowing along every loop toward S.
-- Two thin rings, red and blue, still circle the ball, faint now, each tilted and precessing
-- the opposite way with a bead running round it. The arming moment (arming(), called by
-- UltCutscene at readyAt) snaps the arcs and caps in from small and the rings in from wide,
-- with a zap and a few sparks. Everyone near the table sees it: it reads only the table's
-- snapshot and aim stream.
--
-- The ult shot (the replay carries overrides.Effect == "Magnet"): each ball Magnet may pull
-- (Magnet.factor: the shooter's at 1, the opponent's at OpponentFactor) charges the moment it
-- starts moving: a zap, a spark burst, and a burst of field lines out of it (the arcs and a
-- fan of flared lines out of each pole, flat on the cloth, growing and fading), and it takes
-- on red and blue caps for the rest of the shot, N toward where it is rolling. Each frame,
-- Magnet.activePulls on the replay's own state says which balls are in a capture zone: three
-- field lines lie on the cloth from the ball to the pocket (one straight, two bowing out
-- either side), arrows flowing toward the pocket, brighter the stronger the pull; the pocket
-- shows a fan of flared lines at its mouth and a vortex of motes drawn into its centre; the
-- ball glows blue and crackles; the hum rises in pitch; bright dust streams off the ball into
-- the pocket. A pulled ball's drop snaps its lines in onto the pocket, plays a clunk-zap with
-- a burst of sparks, and sends a ring of chasing arrows out across the cloth. The opponent's
-- balls get all of it, visibly fainter (OpponentOpacityShare). The armed look fades as the
-- shot starts and everything fades when it ends.
--
-- Before the model has arrived (or if it never does) the look falls back to Beams only: the
-- armed field is three flickering beam arcs, a charged ball gets small red and blue rings
-- circling it instead of caps, the pocket a glowing ring instead of the fan, and the drop no
-- shockwave. The pocket lines are Beams either way.
--
-- Only tables whose balls are drawn get anything (Hub's renderer pool); a table that stops
-- being drawn loses its effects at once. Everything hangs off one invisible anchored part per
-- table (the mesh clones too, kept in a per-table pool and hidden when unused), destroyed
-- when the table's effects are done, so nothing leaks across shots or tables. No frame makes
-- an Instance: only an arming, a charge, a new pull or pocket, or a drop does. Randomness here
-- is visual only (the fallback arcs' flicker).

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
local LINE_TILE: string = Config.Ults.Assets.Images.MagnetFieldBeam or ""

-- Magnet.activePulls, mouthPoint and factor, if the module is there (guarded so a missing or
-- broken physics module only costs the pull visuals and the preview's zones, never the
-- client).
type Pull = { ball: number, pocket: number, strength: number, factor: number? }
local activePulls: ((any) -> { Pull })? = nil
local mouthPoint: ((any, any) -> (number, number))? = nil
local factorOf: ((any, number) -> number)? = nil
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
	if ok and type(found) == "table" and type(found.mouthPoint) == "function" then
		mouthPoint = found.mouthPoint
	end
	if ok and type(found) == "table" and type(found.factor) == "function" then
		factorOf = found.factor
	end
end

-- 4/3 tan(pi/8): a cubic Bezier's handle for a quarter circle of radius 1.
local KAPPA = 0.5523
local TAU = 2 * math.pi
local FALLBACK_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- The Blender set (tools/blender/abilities/magnet.py), one model of five MeshParts at unit
-- size, all lying in the part's local XZ plane (Blender +X arrives as local -X, +Y as +Z, +Z
-- as +Y: docs/STUDIO_NOTES.md). So FieldArcs has N at local -X and S at +X with its loops
-- along +-Z, its centre the dipole's middle; FieldFlares' lines leave their pole at the +X
-- face and fan toward -X; PoleCaps has N (red) on -X; Chevron points along -X; FieldRing is a
-- unit circle round its centre.
local MODEL = "MagnetField"
local PIECES = { "FieldArcs", "FieldFlares", "FieldRing", "Chevron", "PoleCaps" }
-- FieldArcs' loops at unit size (magnet.py's loop_points): the loop of height h runs through
-- Blender (cos a * (LOOP_BASE + LOOP_GROW * h), sin a * h) for a from LOOP_GAP to
-- pi - LOOP_GAP (N end first), once above the axis and once mirrored below it.
local LOOP_HEIGHTS = { 0.55, 1.0, 1.5 }
local LOOP_BASE = 0.55
local LOOP_GROW = 0.45
local LOOP_GAP = 0.22

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

-- An angle eased toward `target` the short way round, with time constant `seconds`.
local function easeAngle(angle: number, target: number, dt: number, seconds: number): number
	local delta = (target - angle + math.pi) % TAU - math.pi
	return angle + delta * (1 - math.exp(-dt / math.max(seconds, 1e-3)))
end

-- How much of its opacity a ball's look keeps: all for the shooter's, less for the
-- opponent's (pulled at OpponentFactor), so theirs reads as the weaker effect.
local function weight(factor: number): number
	return if factor < 1 then F.OpponentOpacityShare else 1
end

-- A frame at `pos` whose X (an attachment's Axis, which a Beam's curve follows) is `x`.
local function along(pos: Vector3, x: Vector3): CFrame
	local ref = if math.abs(x.Y) < 0.95 then Vector3.yAxis else Vector3.xAxis
	local z = x:Cross(ref).Unit
	return CFrame.fromMatrix(pos, x, z:Cross(x).Unit)
end

-- A field line's end: X (the curve) along the flat `x`, and, for a flat line, its Y (the way
-- the ribbon faces) straight up, so it lies on the cloth.
local function lineFrame(pos: Vector3, x: Vector3): CFrame
	if F.LinesFaceCamera then
		return along(pos, x)
	end
	return CFrame.fromMatrix(pos, x, Vector3.yAxis)
end

-- The flat world direction of a table angle (radians, the physics' aim convention).
local function flatDir(m: any, angle: number): Vector3
	local d = TableBuilder.aimDirection(m.placement, angle)
	local flat = Vector3.new(d.X, 0, d.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else Vector3.xAxis
end

type Ring = { atts: { Attachment }, beams: { Beam }, bead: Part? }

type Arc = { a0: Attachment, a1: Attachment, beam: Beam, alpha: number, nextFlicker: number }

-- The armed cue ball's meshes: its caps, the arcs round it and the chevrons on the loops.
type ArmedMesh = { arcs: MeshPart, caps: MeshPart, chevrons: { MeshPart } }

type ChargeFx = {
	at: Attachment,
	rings: { Ring }, -- the no-model fallback: red and blue rings circling it
	caps: MeshPart?, -- its red and blue poles
	angle: number, -- where its N points (table radians), eased after its travel
	factor: number, -- Magnet.factor: 1 the shooter's, OpponentFactor the opponent's
	light: PointLight,
	since: number, -- os.clock() it charged (the snap)
	level: number,
}

-- The field lines bursting out of a ball as it charges.
type Burst = {
	arcs: MeshPart,
	flares: { MeshPart }, -- out of N, out of S
	ball: number,
	angle: number, -- N (table radians): the way it was sent
	at: Vector3, -- its spot on the cloth, followed while the ball is there
	started: number,
	factor: number,
}

-- The drop's shockwave: a ring of chasing arrows spreading over the cloth from the pocket.
type Wave = { part: MeshPart, at: Vector3, radius: number, started: number, factor: number }

type PullFx = {
	ballAt: Attachment,
	dustAt: Attachment, -- faces the pocket: the dust flows along it
	dust: ParticleEmitter,
	ends: { Attachment }, -- the pocket end of each line (its own axis, for its own bow)
	starts: { Attachment }, -- the ball end of each line
	beams: { Beam }, -- the straight line, then the two bowing out either side
	light: PointLight,
	glow: ImageLabel?,
	crackle: Sound?,
	level: number, -- eased toward the pull's strength
	on: number, -- 0-1: pulled at all (in fast, out slowly)
	target: number,
	pocket: number,
	factor: number,
	foot: Vector3, -- where the lines leave the ball, on the cloth
	snapAt: number?, -- os.clock() the drop started snapping the lines in...
	snapFrom: Vector3, -- ...and where their ball end was then
}

type PocketFx = {
	flares: MeshPart?, -- the fan of flared lines at the mouth
	plate: Part?, -- the no-model fallback: a glowing ring on the cloth...
	image: ImageLabel?,
	ring: Ring?, -- ...or, with no ring art either, a beam circle
	vortexPart: Part, -- its shape is the vortex the motes are drawn in from
	vortex: ParticleEmitter,
	level: number,
	target: number,
	factor: number, -- the strongest pulled ball's factor, for its weight
	frameFactor: number,
	started: number,
}

type TableFx = {
	anchor: Part,
	cue: Attachment,
	hum: Sound?,
	arm: Sound?,
	rings: { Ring },
	arcs: { Arc }, -- the no-model fallback's field
	armedMesh: ArmedMesh?,
	spare: { [string]: { MeshPart } }, -- mesh clones not in use, by piece
	pole: number, -- the armed N (table radians), eased after the aim
	poleHeard: boolean, -- an aim has set it (the first one is taken at once)
	look: number,
	snapAt: number?,
	snapFor: number?, -- the armed.at the snap was for
	pulls: { [number]: PullFx },
	pockets: { [number]: PocketFx },
	pulled: { [number]: number }, -- balls pulled on this shot, and their factor
	charged: { [number]: ChargeFx }, -- balls charged on this shot
	bursts: { Burst },
	waves: { Wave },
	shotSeq: number?,
	shot: number, -- 0-1: the ult shot's effects, fading out once it ends
	pitchMix: number,
	sparkAt: Attachment,
	sparks: ParticleEmitter,
	keepUntil: number, -- os.clock(): something (a spark, a drop sound) still needs the anchor
}

-- The loaded meshes: one hidden template per piece and its unit size.
type Meshes = { parts: { [string]: MeshPart }, sizes: { [string]: Vector3 } }

local MagnetFx = {}
MagnetFx.__index = MagnetFx

export type MagnetFx = typeof(setmetatable(
	{} :: {
		hub: any,
		parent: Instance,
		models: any?, -- the kit's AbilityModels
		meshes: Meshes?,
		meshesFailed: boolean, -- the model came without every piece: stay on the fallback
		nextMeshCheck: number,
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

local function dropRing(ring: Ring)
	for k = 1, 4 do
		ring.beams[k]:Destroy()
		ring.atts[k]:Destroy()
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

-- One pocket-to-ball field line: the reference's blue, tiled with the arrow (pointing along
-- +U, from Attachment0 at the ball toward Attachment1 at the pocket) and flowing that way.
local function newLine(parent: Instance, a0: Attachment, a1: Attachment): Beam
	local beam = newBeam(parent, a0, a1, rgb(F.LineColor), F.LineWidthStuds)
	beam.FaceCamera = F.LinesFaceCamera
	beam.LightEmission = F.LineLightEmission
	if LINE_TILE ~= "" then
		beam.Texture = LINE_TILE
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = F.LineTextureLengthStuds
		beam.TextureSpeed = F.LineTextureSpeed
	else
		textureBeam(beam, F.LineTextureLengthStuds, F.LineTextureSpeed)
	end
	return beam
end

-- Bright motes in the pull's colour, shrinking away over `lifetime`; off until given a rate.
local function newMotes(parent: Instance, size: number, lifetime: number): ParticleEmitter
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = if ART.Spark ~= "" then ART.Spark else FALLBACK_SPARK
	motes.Color = ColorSequence.new(rgb(F.SparkColor), rgb(F.GlowColor))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(0.2, 0),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	motes.Lifetime = NumberRange.new(lifetime)
	motes.Rotation = NumberRange.new(0, 360)
	motes.Rate = 0
	motes.Parent = parent
	return motes
end

---------------------------------------------------------------------------------------------
-- The meshes: templates from the loaded model, clones pooled per table
---------------------------------------------------------------------------------------------

-- The templates, once the model is here with every piece (checked at most once a second while
-- it is not). nil means draw the fallback.
local function meshesOf(self: MagnetFx): Meshes?
	if self.meshes or self.meshesFailed or self.models == nil then
		return self.meshes
	end
	local now = os.clock()
	if now < self.nextMeshCheck then
		return nil
	end
	self.nextMeshCheck = now + F.ModelCheckSeconds
	local ok, model = pcall((self.models :: any).tryGet, MODEL)
	if not ok or model == nil then
		return nil
	end
	local parts: { [string]: MeshPart } = {}
	local sizes: { [string]: Vector3 } = {}
	for _, name in PIECES do
		local part = (model :: Instance):FindFirstChild(name, true)
		if part == nil or not part:IsA("MeshPart") then
			self.meshesFailed = true
			warn(
				("[8ball] MagnetFx: the %s model has no %s; Magnet keeps its Beam look"):format(
					MODEL,
					name
				)
			)
			return nil
		end
		local mesh = part :: MeshPart
		mesh.Anchored = true
		mesh.CanCollide = false
		mesh.CanQuery = false
		mesh.CanTouch = false
		mesh.CastShadow = false
		mesh.Massless = true
		mesh.Transparency = 1
		if table.find(F.FlatPieces, name) then
			-- The baked pale blue washes out to white on the lit cloth: a flat colour instead.
			mesh.TextureID = ""
			mesh.Color = rgb(F.FieldMeshColor)
			mesh.Material = Enum.Material.SmoothPlastic
		end
		parts[name] = mesh
		sizes[name] = mesh.Size
	end
	self.meshes = { parts = parts, sizes = sizes }
	return self.meshes
end

-- A clone of piece `name` under the table's anchor (a spare one if there is one), hidden.
local function takeMesh(self: MagnetFx, fx: TableFx, name: string): MeshPart?
	local spare = fx.spare[name]
	if spare and #spare > 0 then
		return table.remove(spare)
	end
	local meshes = self.meshes
	local template = meshes and meshes.parts[name]
	if template == nil then
		return nil
	end
	local part = template:Clone()
	part.Parent = fx.anchor
	return part
end

-- Hide a clone and keep it for the next use at this table.
local function giveMesh(fx: TableFx, part: MeshPart?)
	if part == nil then
		return
	end
	part.Transparency = 1
	local spare = fx.spare[part.Name]
	if spare == nil then
		spare = {}
		fx.spare[part.Name] = spare
	end
	table.insert(spare :: { MeshPart }, part)
end

-- Size a clone only when it changes (a MeshPart resize is not free).
local function resize(part: MeshPart, size: Vector3)
	if part.Size ~= size then
		part.Size = size
	end
end

-- FieldArcs' scale (a multiple of its unit size) for a ball: its inner loops pass
-- ArcsInnerRadiusBalls ball radii from the ball's centre.
local function arcsScale(): number
	return TableBuilder.studs(Config.Balls.RenderRadiusInches)
		* F.ArcsInnerRadiusBalls
		/ LOOP_HEIGHTS[1]
end

-- A flat piece's frame: lying on the cloth `lift` studs up at `floor`, its local -X along `d`.
local function flatFrame(floor: Vector3, size: Vector3, d: Vector3): CFrame
	return CFrame.fromMatrix(floor + Vector3.yAxis * (size.Y / 2), -d, Vector3.yAxis)
end

---------------------------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------------------------

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
		armedMesh = nil,
		spare = {},
		pole = 0,
		poleHeard = false,
		look = 0,
		snapAt = nil,
		snapFor = nil,
		pulls = {},
		pockets = {},
		pulled = {},
		charged = {},
		bursts = {},
		waves = {},
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
	for i = 1, 3 do
		starts[i] = newAttachment(anchor, ("Pull%d_%d_Ball"):format(ball, i))
		ends[i] = newAttachment(anchor, ("Pull%d_%d_Pocket"):format(ball, i))
		beams[i] = newLine(anchor, starts[i], ends[i])
	end
	local dustAt = newAttachment(anchor, "Dust" .. ball)
	local dust = newMotes(dustAt, F.DustSizeStuds, F.DustLifetime)
	dust.EmissionDirection = Enum.NormalId.Front
	dust.SpreadAngle = Vector2.new(F.DustSpreadDegrees, F.DustSpreadDegrees)
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
		dustAt = dustAt,
		dust = dust,
		ends = ends,
		starts = starts,
		beams = beams,
		light = light,
		glow = glow,
		crackle = crackle,
		level = 0,
		on = 0,
		target = 0,
		pocket = 0,
		factor = 1,
		foot = Vector3.zero,
		snapAt = nil,
		snapFrom = Vector3.zero,
	}
	fx.pulls[ball] = pull
	return pull
end

local function dropPull(pull: PullFx)
	pull.ballAt:Destroy()
	pull.dustAt:Destroy()
	for i = 1, #pull.beams do
		pull.beams[i]:Destroy()
		pull.starts[i]:Destroy()
		pull.ends[i]:Destroy()
	end
end

local function newPocket(self: MagnetFx, fx: TableFx, pocket: number): PocketFx
	-- The vortex: motes born on a squat sphere round the pocket, drawn in to its centre.
	local vortexPart = Instance.new("Part")
	vortexPart.Name = "Vortex" .. pocket
	vortexPart.Anchored = true
	vortexPart.CanCollide = false
	vortexPart.CanQuery = false
	vortexPart.CanTouch = false
	vortexPart.CastShadow = false
	vortexPart.Transparency = 1
	vortexPart.Size = Vector3.one * 0.2
	vortexPart.Parent = fx.anchor
	local vortex = newMotes(vortexPart, F.VortexSizeStuds, F.VortexLifetime)
	vortex.Shape = Enum.ParticleEmitterShape.Sphere
	vortex.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	vortex.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	local p: PocketFx = {
		flares = nil,
		plate = nil,
		image = nil,
		ring = nil,
		vortexPart = vortexPart,
		vortex = vortex,
		level = 0,
		target = 0,
		factor = 1,
		frameFactor = 0,
		started = os.clock(),
	}
	if meshesOf(self) then
		p.flares = takeMesh(self, fx, "FieldFlares")
	elseif ART.RingGlow ~= "" then
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

local function dropPocket(fx: TableFx, p: PocketFx)
	p.vortexPart:Destroy()
	giveMesh(fx, p.flares)
	if p.plate then
		p.plate:Destroy()
	end
	if p.ring then
		dropRing(p.ring)
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

-- The aim the table's shooter is lining up (table radians) off the aim stream, which the
-- server sends every client (the shooter too), or nil when none is heard.
local function aimAngle(self: MagnetFx, id: number, snapshot: any): number?
	local aims = self.hub.aims
	local aim = if type(aims) == "table" then aims[id] else nil
	if
		type(aim) == "table"
		and type(aim.angle) == "number"
		and type(snapshot) == "table"
		and aim.by == snapshot.shooter
	then
		return aim.angle
	end
	return nil
end

local function armedMeshOf(self: MagnetFx, fx: TableFx): ArmedMesh?
	if fx.armedMesh == nil then
		local arcs = takeMesh(self, fx, "FieldArcs")
		local caps = takeMesh(self, fx, "PoleCaps")
		if arcs == nil or caps == nil then
			giveMesh(fx, arcs)
			giveMesh(fx, caps)
			return nil
		end
		local chevrons: { MeshPart } = {}
		for _ = 1, #LOOP_HEIGHTS * 2 * F.ChevronsPerLoop do
			local chevron = takeMesh(self, fx, "Chevron")
			if chevron then
				table.insert(chevrons, chevron)
			end
		end
		fx.armedMesh = { arcs = arcs, caps = caps, chevrons = chevrons }
	end
	return fx.armedMesh
end

local function hideArmedMesh(fx: TableFx)
	local set = fx.armedMesh
	if set then
		set.arcs.Transparency = 1
		set.caps.Transparency = 1
		for _, chevron in set.chevrons do
			chevron.Transparency = 1
		end
	end
end

-- The armed dipole: caps on the cue ball, the arcs flat round it and the chevrons flowing
-- along each loop from N to S (in the arcs' own frame, the loops' own formula).
local function placeArmedMesh(
	self: MagnetFx,
	set: ArmedMesh,
	m: any,
	cue: any,
	center: Vector3,
	d: Vector3,
	snap: number,
	look: number,
	t: number
)
	local sizes = (self.meshes :: Meshes).sizes
	local k = arcsScale() * snap
	local arcsSize = sizes.FieldArcs * k
	local floor = TableBuilder.toWorld(m.placement, cue.x, cue.y, F.MeshLiftInches)
	local arcsFrame = flatFrame(floor, arcsSize, d)
	resize(set.arcs, arcsSize)
	set.arcs.CFrame = arcsFrame
	set.arcs.Transparency = 1 - (1 - F.ArcsTransparency) * look

	local capR = TableBuilder.studs(Config.Balls.RenderRadiusInches) * F.CapsRadiusBalls * snap
	resize(set.caps, sizes.PoleCaps * capR)
	set.caps.CFrame = CFrame.fromMatrix(center, -d, Vector3.yAxis)
	set.caps.Transparency = 1 - (1 - F.CapsTransparency) * look

	local chevronSize = sizes.Chevron * (k * F.ChevronShare)
	local perLoop = F.ChevronsPerLoop
	local i = 0
	for loop = 1, #LOOP_HEIGHTS * 2 do
		local h = LOOP_HEIGHTS[(loop - 1) % #LOOP_HEIGHTS + 1]
		local side = if loop <= #LOOP_HEIGHTS then 1 else -1
		local reach = LOOP_BASE + LOOP_GROW * h
		for c = 1, perLoop do
			i += 1
			if i > #set.chevrons then
				return
			end
			local chevron = set.chevrons[i]
			local u = (t / F.ChevronLapSeconds + (c - 1) / perLoop + loop * F.ChevronStagger) % 1
			local a = LOOP_GAP + (math.pi - 2 * LOOP_GAP) * u
			-- Blender (x, y) -> local (-x, 0, y): N's foot (a small) is at local -X.
			local p = Vector3.new(-math.cos(a) * reach, 0, side * math.sin(a) * h) * k
			local toward = Vector3.new(math.sin(a) * reach, 0, side * math.cos(a) * h).Unit
			resize(chevron, chevronSize)
			-- The chevron points along its local -X: along the loop, on toward S.
			chevron.CFrame = arcsFrame * CFrame.fromMatrix(p, -toward, Vector3.yAxis)
			local ends = math.min(1, u / F.ChevronFadeShare, (1 - u) / F.ChevronFadeShare)
			chevron.Transparency = 1 - (1 - F.ChevronTransparency) * look * ends
		end
	end
end

local function stepLook(
	self: MagnetFx,
	fx: TableFx,
	id: number,
	m: any,
	snapshot: any,
	dt: number,
	t: number
)
	local cue = m:findCueBall()
	if cue == nil then
		return
	end
	local center = ballWorld(m, cue)
	fx.cue.CFrame = CFrame.new(center)
	-- N follows the shooter's aim (every client hears it), eased; with none heard, a slow turn.
	local aim = aimAngle(self, id, snapshot)
	if aim and not fx.poleHeard then
		fx.pole, fx.poleHeard = aim, true
	elseif aim then
		fx.pole = easeAngle(fx.pole, aim, dt, F.PoleEaseSeconds)
	elseif fx.look > 0.001 and not m:isBusy() then
		fx.pole += TAU * dt / F.ArcTurnSeconds
	end
	if fx.look <= 0.001 then
		for _, ring in fx.rings do
			hideRing(ring)
		end
		for _, arc in fx.arcs do
			arc.beam.Transparency = NumberSequence.new(1)
		end
		hideArmedMesh(fx)
		return
	end
	local ballR = TableBuilder.studs(Config.Balls.RenderRadiusInches)
	local scale, meshScale = 1, 1
	if fx.snapAt then
		local u = (os.clock() - fx.snapAt) / F.SnapSeconds
		if u < 1 then
			scale = lerp(F.SnapFromScale, 1, UIAnim.backOut(u))
			meshScale = lerp(F.MeshSnapFromScale, 1, UIAnim.backOut(u))
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
	local axis = flatDir(m, fx.pole)
	local set = if meshesOf(self) then armedMeshOf(self, fx) else nil
	if set then
		for _, arc in fx.arcs do
			arc.beam.Transparency = NumberSequence.new(1)
		end
		placeArmedMesh(self, set, m, cue, center, axis, meshScale, fx.look, t)
		return
	end
	-- The fallback field: a dipole across the ball (N along the aim), its lines looping over
	-- the top, flickering.
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

-- The pocket's fan of flared lines: leaving the middle of its mouth, fanning out over the
-- table.
local function placeFlares(self: MagnetFx, p: PocketFx, m: any, pocket: any, wave: number)
	local flares = p.flares
	if flares == nil then
		return
	end
	local mx, my = pocket.x, pocket.y
	if mouthPoint then
		local ok, x, y = pcall(mouthPoint :: any, m.state.geometry, pocket)
		if ok and type(x) == "number" and type(y) == "number" then
			mx, my = x, y
		end
	end
	local centre = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.MeshLiftInches)
	local mouth = TableBuilder.toWorld(m.placement, mx, my, F.MeshLiftInches)
	local out = mouth - centre
	if out.Magnitude < 1e-3 then
		out = TableBuilder.toWorld(m.placement, 0, 0, F.MeshLiftInches) - centre
	end
	local f = Vector3.new(out.X, 0, out.Z).Unit
	local k = TableBuilder.studs(pocket.radius)
		* F.PocketFlareScale
		* (1 + F.PocketPulseScale * wave)
	local size = (self.meshes :: Meshes).sizes.FieldFlares * k
	resize(flares, size)
	-- The lines leave their pole at the +X face: put that face on the mouth.
	flares.CFrame = flatFrame(mouth + f * (size.X / 2), size, f)
	flares.Transparency = 1 - (1 - F.PocketFlareTransparency) * p.level * weight(p.factor)
end

local function stepPulls(
	self: MagnetFx,
	fx: TableFx,
	m: any,
	magnetShot: boolean,
	dt: number,
	t: number
)
	for _, pull in fx.pulls do
		pull.target = 0
	end
	if magnetShot and activePulls then
		local ok, list = pcall(activePulls :: any, m.state)
		if ok and type(list) == "table" then
			for _, p in list :: { Pull } do
				local pull = fx.pulls[p.ball] or newPull(fx, p.ball)
				if pull.snapAt then
					continue -- already dropped: its lines are snapping in
				end
				pull.target = math.clamp(p.strength, 0, 1)
				pull.pocket = p.pocket
				pull.factor = if type(p.factor) == "number" then p.factor else 1
				fx.pulled[p.ball] = pull.factor
			end
		end
	end
	for _, pocket in fx.pockets do
		pocket.target = 0
		pocket.frameFactor = 0
	end
	local strongest = 0
	for id, pull in fx.pulls do
		-- Rises quickly, lets go a little slower.
		local seconds = if pull.target > pull.level then F.PullRiseSeconds else F.PullFadeSeconds
		pull.level = approach(pull.level, pull.target, dt, seconds)
		local wanted = if pull.target > 0 then 1 else 0
		pull.on = approach(
			pull.on,
			wanted,
			dt,
			if wanted > pull.on then F.PullRiseSeconds else F.PullFadeSeconds
		)
		local b = ballOf(m, id)
		local pocket = pocketOf(m, pull.pocket)
		local snapped = if pull.snapAt then (t - pull.snapAt) / F.SnapInSeconds else 0
		if (pull.on <= 0.005 and pull.target == 0) or snapped >= 1 or b == nil or pocket == nil then
			dropPull(pull)
			fx.pulls[id] = nil
			continue
		end
		strongest = math.max(strongest, pull.level)
		local p = fx.pockets[pull.pocket] or newPocket(self, fx, pull.pocket)
		p.target = math.max(p.target, pull.on)
		p.frameFactor = math.max(p.frameFactor, pull.factor)

		local to = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.LineLiftInches)
		local from = ballWorld(m, b)
		if pull.snapAt then
			-- The drop: the lines' ball end rushes into the pocket.
			pull.foot = pull.snapFrom:Lerp(to, snapped * snapped)
			from = pull.ballAt.WorldPosition
		else
			pull.foot = TableBuilder.toWorld(m.placement, b.x, b.y, F.LineLiftInches)
		end
		local foot = pull.foot
		pull.ballAt.CFrame = CFrame.new(from)
		local flat = Vector3.new(to.X - foot.X, 0, to.Z - foot.Z)
		local dist = flat.Magnitude
		local dir = if dist > 1e-4 then flat / dist else Vector3.xAxis
		local side = dir:Cross(Vector3.yAxis)
		local opacity = pull.on
			* (F.LineMinShare + (1 - F.LineMinShare) * pull.level)
			* weight(pull.factor)
		for i, beam in pull.beams do
			if i == 1 then
				pull.starts[i].CFrame = lineFrame(foot, dir)
				pull.ends[i].CFrame = lineFrame(to, dir)
				beam.CurveSize0 = 0
				beam.CurveSize1 = 0
			else
				-- Both handles to the same side, so it bows out in an arc like the reference's.
				local sign = if i == 2 then 1 else -1
				pull.starts[i].CFrame = lineFrame(foot, side * sign)
				pull.ends[i].CFrame = lineFrame(to, -side * sign)
				beam.CurveSize0 = dist * F.LineBowShare
				beam.CurveSize1 = dist * F.LineBowShare
			end
			local base = if i == 1 then F.LineTransparency else F.SideLineTransparency
			beam.Transparency = NumberSequence.new(1 - (1 - base) * opacity)
		end
		local held = if pull.snapAt then 1 - snapped else 1
		-- The dust leaves the ball toward the pocket, fast enough to reach it as it fades.
		pull.dustAt.CFrame = CFrame.lookAt(from, to)
		pull.dust.Speed = NumberRange.new((to - from).Magnitude / F.DustLifetime)
		pull.dust.Rate = if pull.snapAt then 0 else F.DustRate * pull.level
		pull.light.Brightness = F.GlowBrightness * pull.level * held
		if pull.glow then
			local flicker = 1 + F.GlowPulseShare * math.sin(TAU * t / F.GlowPulseSeconds)
			pull.glow.ImageTransparency = 1
				- math.clamp(pull.level * flicker * held, 0, 1) * (1 - F.GlowTransparency)
		end
		if pull.crackle then
			pull.crackle.Volume = A.MagnetPull.Volume * pull.level * held
		end
	end
	for id, p in fx.pockets do
		p.level = approach(p.level, p.target, dt, F.PullFadeSeconds)
		if p.frameFactor > 0 then
			p.factor = p.frameFactor
		end
		local pocket = pocketOf(m, id)
		if (p.level <= 0.005 and p.target == 0) or pocket == nil then
			dropPocket(fx, p)
			fx.pockets[id] = nil
			continue
		end
		local wave = math.sin(TAU * (os.clock() - p.started) / F.PocketPulseSeconds)
		local d = TableBuilder.studs(pocket.radius * 2)
			* F.PocketRingScale
			* (1 + F.PocketPulseScale * wave)
		local at = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.PocketLiftInches)
		local alpha = 1
			- (1 - F.PocketTransparency)
				* p.level
				* weight(p.factor)
				* (1 - F.PocketPulseFade * (wave + 1) / 2)
		local vortexW = TableBuilder.studs(pocket.radius * 2) * F.VortexScale
		p.vortexPart.Size = Vector3.new(vortexW, vortexW * F.VortexHeightShare, vortexW)
		p.vortexPart.CFrame = CFrame.new(at)
		p.vortex.Speed = NumberRange.new(vortexW / 2 / F.VortexLifetime)
		p.vortex.Rate = F.VortexRate * p.level
		if p.flares then
			placeFlares(self, p, m, pocket, wave)
		elseif p.plate and p.image then
			p.plate.Size = Vector3.new(d, 0.02, d)
			p.plate.CFrame = CFrame.new(at)
			p.image.ImageTransparency = alpha
		elseif p.ring then
			placeRing(p.ring, at, Vector3.yAxis, d / 2, 0, alpha)
		end
	end
	return strongest
end

local function dropCharge(fx: TableFx, c: ChargeFx)
	c.at:Destroy()
	giveMesh(fx, c.caps)
	for _, ring in c.rings do
		dropRing(ring)
	end
end

-- How strongly the shot may pull ball `id` (Magnet.factor: 1 the shooter's, OpponentFactor
-- the opponent's, 0 not at all). Without the physics module, overrides.Targets at 1 (the 8
-- only with a called pocket).
local function factorFor(state: any, id: number): number
	if factorOf then
		local ok, factor = pcall(factorOf :: any, state, id)
		return if ok and type(factor) == "number" then factor else 0
	end
	local o = state.overrides
	if id == 0 or o == nil or o.Targets == nil or (id == 8 and o.EightPocket == nil) then
		return 0
	end
	return if table.find(o.Targets, id) ~= nil then 1 else 0
end

-- A charging ball's burst of field lines (the arcs and a fan out of each pole), N along
-- `angle`.
local function spawnBurst(
	self: MagnetFx,
	fx: TableFx,
	m: any,
	b: any,
	angle: number,
	factor: number
)
	local arcs = takeMesh(self, fx, "FieldArcs")
	local north = takeMesh(self, fx, "FieldFlares")
	local south = takeMesh(self, fx, "FieldFlares")
	if arcs == nil or north == nil or south == nil then
		giveMesh(fx, arcs)
		giveMesh(fx, north)
		giveMesh(fx, south)
		return
	end
	local t = os.clock()
	table.insert(fx.bursts, {
		arcs = arcs,
		flares = { north, south },
		ball = b.id,
		angle = angle,
		at = TableBuilder.toWorld(m.placement, b.x, b.y, F.MeshLiftInches),
		started = t,
		factor = factor,
	})
	fx.keepUntil = math.max(fx.keepUntil, t + F.BurstSeconds)
end

local function stepBursts(self: MagnetFx, fx: TableFx, m: any, t: number)
	local meshes = self.meshes
	for i = #fx.bursts, 1, -1 do
		local burst = fx.bursts[i]
		local u = (t - burst.started) / F.BurstSeconds
		if u >= 1 or meshes == nil then
			table.remove(fx.bursts, i)
			giveMesh(fx, burst.arcs)
			for _, flare in burst.flares do
				giveMesh(fx, flare)
			end
			continue
		end
		local b = ballOf(m, burst.ball)
		if b and not b.pocketed then
			burst.at = TableBuilder.toWorld(m.placement, b.x, b.y, F.MeshLiftInches)
		end
		local k = arcsScale() * lerp(F.BurstFromScale, F.BurstToScale, UIAnim.quadOut(u))
		local alpha = 1 - (1 - F.BurstTransparency) * (1 - u) * weight(burst.factor)
		local d = flatDir(m, burst.angle)
		local arcsSize = (meshes :: Meshes).sizes.FieldArcs * k
		resize(burst.arcs, arcsSize)
		burst.arcs.CFrame = flatFrame(burst.at, arcsSize, d)
		burst.arcs.Transparency = alpha
		local flareSize = (meshes :: Meshes).sizes.FieldFlares * k
		for j, flare in burst.flares do
			-- Out of N (along d) and out of S (against it), leaving where the inner loops do.
			local out = if j == 1 then d else -d
			local pole = burst.at + out * (F.BurstFlareStart * k)
			resize(flare, flareSize)
			flare.CFrame = flatFrame(pole + out * (flareSize.X / 2), flareSize, out)
			flare.Transparency = alpha
		end
	end
end

-- The drop's shockwave: a ring of chasing arrows spreading out from the pocket.
local function spawnWave(self: MagnetFx, fx: TableFx, m: any, pocket: any, factor: number)
	if meshesOf(self) == nil then
		return
	end
	local part = takeMesh(self, fx, "FieldRing")
	if part == nil then
		return
	end
	local t = os.clock()
	table.insert(fx.waves, {
		part = part,
		at = TableBuilder.toWorld(m.placement, pocket.x, pocket.y, F.WaveLiftInches),
		radius = TableBuilder.studs(pocket.radius),
		started = t,
		factor = factor,
	})
	fx.keepUntil = math.max(fx.keepUntil, t + F.WaveSeconds)
end

local function stepWaves(self: MagnetFx, fx: TableFx, t: number)
	local meshes = self.meshes
	for i = #fx.waves, 1, -1 do
		local wave = fx.waves[i]
		local u = (t - wave.started) / F.WaveSeconds
		if u >= 1 or meshes == nil then
			table.remove(fx.waves, i)
			giveMesh(fx, wave.part)
			continue
		end
		-- FieldRing is a unit circle: its scale is its radius in studs.
		local r = wave.radius * lerp(F.WaveFromRadii, F.WaveToRadii, UIAnim.quadOut(u))
		local size = (meshes :: Meshes).sizes.FieldRing * r
		resize(wave.part, size)
		wave.part.CFrame = CFrame.new(wave.at + Vector3.yAxis * (size.Y / 2))
			* CFrame.Angles(0, math.rad(F.WaveSpinDegrees) * u, 0)
		wave.part.Transparency = 1 - (1 - F.WaveTransparency) * (1 - u) * weight(wave.factor)
	end
end

-- Charge each ball Magnet may pull the moment it is hit (it starts moving), and keep its
-- poles on it (or, with no model, its rings circling it).
local function stepCharges(
	self: MagnetFx,
	fx: TableFx,
	m: any,
	magnetShot: boolean,
	dt: number,
	t: number
)
	local minSpeed2 = F.ChargeMinSpeed * F.ChargeMinSpeed
	if magnetShot then
		for _, b in m.state.balls do
			if
				fx.charged[b.id] == nil
				and not b.pocketed
				and b.vx * b.vx + b.vy * b.vy > minSpeed2
			then
				local factor = factorFor(m.state, b.id)
				if factor <= 0 then
					continue
				end
				local at = newAttachment(fx.anchor, "Charged" .. b.id)
				local center = ballWorld(m, b)
				at.CFrame = CFrame.new(center)
				local light = Instance.new("PointLight")
				light.Color = rgb(F.GlowColor)
				light.Range = F.ChargeGlowRangeStuds
				light.Brightness = 0
				light.Shadows = false
				light.Parent = at
				local angle = math.atan2(b.vy, b.vx)
				local caps = if meshesOf(self) then takeMesh(self, fx, "PoleCaps") else nil
				local rings: { Ring } = {}
				if caps then
					spawnBurst(self, fx, m, b, angle, factor)
				else
					rings = {
						newRing(
							fx.anchor,
							"ChargeN" .. b.id,
							rgb(F.NorthColor),
							F.ChargeRingWidthStuds,
							false
						),
						newRing(
							fx.anchor,
							"ChargeS" .. b.id,
							rgb(F.SouthColor),
							F.ChargeRingWidthStuds,
							false
						),
					}
				end
				fx.charged[b.id] = {
					at = at,
					rings = rings,
					caps = caps,
					angle = angle,
					factor = factor,
					light = light,
					since = t,
					level = 1,
				}
				local zap = newSound(at, A.MagnetZap, false)
				if zap then
					zap.Volume = A.MagnetZap.Volume * F.ChargeZapShare * weight(factor)
					fire(zap)
				end
				fx.sparkAt.CFrame = CFrame.new(center)
				fx.sparks:Emit(math.max(1, math.round(F.ChargeSparkCount * weight(factor))))
				fx.keepUntil = math.max(fx.keepUntil, t + F.SparkLifetime[2])
			end
		end
	end
	local ballR = TableBuilder.studs(Config.Balls.RenderRadiusInches)
	local tilt = math.rad(F.RingTiltDegrees)
	for id, c in fx.charged do
		local b = ballOf(m, id)
		local target = if b and not b.pocketed then fx.shot else 0
		c.level = approach(c.level, target, dt, F.PullFadeSeconds)
		if c.level <= 0.005 or b == nil then
			dropCharge(fx, c)
			fx.charged[id] = nil
			continue
		end
		local center = ballWorld(m, b)
		c.at.CFrame = CFrame.new(center)
		c.light.Brightness = F.ChargeGlowBrightness * c.level * weight(c.factor)
		local u = (t - c.since) / F.SnapSeconds
		local caps, meshes = c.caps, self.meshes
		if caps and meshes then
			-- N toward where it rolls (held once it stops).
			if b.vx * b.vx + b.vy * b.vy > minSpeed2 then
				c.angle = easeAngle(c.angle, math.atan2(b.vy, b.vx), dt, F.CapsTurnSeconds)
			end
			local snap = if u < 1 then lerp(F.MeshSnapFromScale, 1, UIAnim.backOut(u)) else 1
			resize(caps, meshes.sizes.PoleCaps * (ballR * F.CapsRadiusBalls * snap))
			caps.CFrame = CFrame.fromMatrix(center, -flatDir(m, c.angle), Vector3.yAxis)
			caps.Transparency = 1 - (1 - F.CapsTransparency) * c.level * weight(c.factor)
			continue
		end
		local scale = if u < 1 then lerp(F.ChargeSnapFromScale, 1, UIAnim.backOut(u)) else 1
		local alpha = 1 - (1 - F.ChargeRingTransparency) * c.level * weight(c.factor)
		for i, ring in c.rings do
			local sign = if i == 1 then 1 else -1
			local phi = sign * TAU * t / F.ChargeTurnSeconds + (i - 1) * math.pi
			local normal = Vector3.new(
				math.sin(tilt) * math.cos(phi),
				math.cos(tilt),
				math.sin(tilt) * math.sin(phi)
			)
			placeRing(ring, center, normal, ballR * F.ChargeRingRadiusBalls * scale, 0, alpha)
		end
	end
end

--- A pocket event at table `id`: a pulled ball's drop snaps its lines in, gets the clunk-zap
--- and the sparks, and sends the shockwave out.
local function onPocket(self: MagnetFx, id: number, m: any, ev: any)
	local fx = self.tables[id]
	local factor = fx and fx.pulled[ev.ball]
	if fx == nil or factor == nil or m.state.time - ev.t > F.FreshSeconds then
		return
	end
	local pocket = pocketOf(m, ev.other)
	if pocket == nil then
		return
	end
	local t = os.clock()
	local pull = fx.pulls[ev.ball]
	if pull and pull.snapAt == nil then
		pull.snapAt, pull.snapFrom = t, pull.foot
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
	spawnWave(self, fx, m, pocket, factor)
	fx.keepUntil = math.max(fx.keepUntil, t + math.max(F.SparkLifetime[2], F.DropSoundSeconds))
end

--- Start drawing Magnet for every table `hub` (src/client/Hub.luau) holds, under `parent`.
--- Call update(dt) every frame after hub:update(dt), and arming() at each arming moment.
--- AbilityFx starts it and passes its kit third: Magnet builds its own parts and takes only
--- the kit's AbilityModels (the field-line meshes) from it.
function MagnetFx.start(hub: any, parent: Instance, kit: any?): MagnetFx
	local self = setmetatable({
		hub = hub,
		parent = parent,
		models = if type(kit) == "table" then kit.models else nil,
		meshes = nil,
		meshesFailed = false,
		nextMeshCheck = 0,
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
	-- Fetch the sounds and images now, so the first arming is not silent. (The meshes and
	-- their texture are AbilityModels.preload's, at the seat and the arming.)
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
		if LINE_TILE ~= "" then
			table.insert(list, LINE_TILE)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
	end)
	return self
end

--- The arming moment at table `tableId` (UltCutscene's onArming, at armed.readyAt): for a
--- Magnet, the arcs and caps snap onto the cue ball from small (the rings from wide) with a
--- zap and a few sparks.
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
		local snapshot = self.hub.snapshots[id]
		local armed = magnetArmed(snapshot)
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
			for ball, c in live.charged do
				dropCharge(live, c)
				live.charged[ball] = nil
			end
		end
		live.look = approach(live.look, if wantLook then 1 else 0, dt, F.LookFadeSeconds)
		live.shot = approach(live.shot, if magnetShot then 1 else 0, dt, F.EndFadeSeconds)
		stepLook(self, live, id, m, snapshot, dt, t)
		local strongest = stepPulls(self, live, m, magnetShot, dt, t)
		stepCharges(self, live, m, magnetShot, dt, t)
		stepBursts(self, live, m, t)
		stepWaves(self, live, t)
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
			and next(live.charged) == nil
			and #live.bursts == 0
			and #live.waves == 0
			and t >= live.keepUntil
		then
			destroy(self, id)
		end
	end
end

--- The reach preview's zones while Magnet is armed and its shooter aims (ABILITIES_PROMPT
--- 5.7, drawn by AbilityFx): each pocket's pull zone, ZoneBallWidths ball diameters round the
--- middle of its mouth (Effects/Magnet's own rule). The opponent's balls feel it at half the
--- pull in the same zone, so their red ring uses the same radius.
function MagnetFx.zones(_self: MagnetFx, _tableId: number, _armed: any, m: any): { any }?
	local point = mouthPoint
	if point == nil then
		return nil
	end
	local r = Config.Ults.Magnet.ZoneBallWidths * 2 * Config.Balls.RadiusInches
	local zones = {}
	for _, pocket in m.state.geometry.pockets do
		local x, y = point(m.state.geometry, pocket)
		table.insert(zones, { x = x, y = y, r = r })
	end
	return zones
end

--- Remove every effect at once.
function MagnetFx.clear(self: MagnetFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return MagnetFx
