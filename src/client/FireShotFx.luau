--!strict
-- FireShotFx: what Fire Shot looks and sounds like (the designer's third rework round,
-- 2026-10-08: Super Bounce reworked into the starter ability). The physics is the launch and
-- the corners (src/shared/Ults/Effects/FireShot.luau: twice the speed off the cue, and `ult`
-- events "turn" where the cue ball meets a cushion or a ball and "down" where it lands from a
-- hop); the white guideline draws the full lines itself (Aim.fullLines). This only draws and
-- plays the rest. Numbers in
-- Config.UI.FireShotFx, the sounds in Config.Ults.Audio (Fire*), the scorch images from
-- tools/gen_fireshot_art.py.
--
--   * The ignition (the arming moment; everyone at the table): flames and sparks burst off
--     the cue ball with a flash of firelight and a whoosh, and it catches fire.
--   * Engulfed (armed until the shot, then until the cue ball stops): flames lick up off the
--     ball (two flame flipbooks), embers rise, dark smoke curls above it, a warm glow and a
--     see-through Neon shell breathe with a flickering firelight, and a crackle loops.
--   * The aim (the local shooter only, look:aiming): the white guideline draws every line,
--     and the object ball's and the cue ball's run on until they touch the next cushion, ball
--     or pocket (Guideline.show's `full`; the designer: "to the next edge of a table"). Under
--     each of its three lines a river of fire flows the way it goes (a flat textured Beam,
--     hot orange where the line starts and deeper red where it ends); the two after the
--     first ball go when the guideline draws its red cross instead.
--   * The strike: a burst of fire and sparks off the ball, a big flash, a roar, and for the
--     table's players a field-of-view punch and a little shake.
--   * In flight: the flames are streamed along the ball's path every frame (a fast ball
--     leaves an unbroken stream, not clumps), a burning ribbon with a hot core trails it (the
--     cue skin's own trail hidden meanwhile), and every cushion and ball it hits throws sparks
--     and a puff of flame with a flash and a sizzle.
--   * Out (at rest, down a pocket, off the table): the flames die down with a puff of smoke
--     and a sizzle.
--   * Scorch marks (everyone at the table): a char line burnt into the cloth where the ball
--     rolled (straight pieces, bending exactly at the "turn" events), a splat under the strike
--     and at every hit and landing, glowing hot right behind the ball and cooling down its
--     length. Never drawn while the ball is in the air. They stay until the shooter's next
--     turn (the designer's answer): through the other side's turn, gone when the table comes
--     back to the shooter's side (a run of their own keeps them; in Solo, until their next
--     shot) or at a new game, fading out. The table's anchor is held (kit.anchor) meanwhile.
-- Each table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or clear().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Physics = Shared:WaitForChild("Physics")
local Aim = require(Physics:WaitForChild("Aim"))
local Ball = require(Physics:WaitForChild("Ball"))
local Judge = require(Shared:WaitForChild("Rules"):WaitForChild("ShotJudge"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))
local CueVfx = require(script.Parent:WaitForChild("CueVfx"))
local Quality = require(script.Parent:WaitForChild("Quality"))

local F = Config.UI.FireShotFx
local A = Config.Ults.Audio
local ART = Config.UI.Kit.Art

local EFFECT = "FireShot"
local TAU = 2 * math.pi
-- Each splat is turned by the golden angle from the last, so no two lie alike.
local GOLDEN = math.rad(137.5)
local COS_TURN = math.cos(math.rad(F.ScorchTurnDegrees))

local SHAPES: { [string]: Enum.ParticleEmitterShape } = {
	Box = Enum.ParticleEmitterShape.Box,
	Sphere = Enum.ParticleEmitterShape.Sphere,
	Cylinder = Enum.ParticleEmitterShape.Cylinder,
	Disc = Enum.ParticleEmitterShape.Disc,
}
local STYLES: { [string]: Enum.ParticleEmitterShapeStyle } = {
	Volume = Enum.ParticleEmitterShapeStyle.Volume,
	Surface = Enum.ParticleEmitterShapeStyle.Surface,
}

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

local function quantise(value: number, step: number): number
	return math.floor(value / step + 0.5)
end

local function colorSeq(list: { { number } }): ColorSequence
	local keys = {}
	local n = #list
	for i, c in list do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / math.max(n - 1, 1), rgb(c)))
	end
	return ColorSequence.new(keys)
end

local function ballWidth(): number
	return TableBuilder.studs(Config.Balls.RenderRadiusInches * 2)
end

-- The firelight's flicker (FirePit's): about 1, never below 0.
local function flicker(t: number, seed: number): number
	local s = F.FlickerSpeed
	local n = math.noise(t * s, seed) + 0.35 * math.noise(t * s * 2.7, seed + 7.7)
	return math.max(0, 1 + F.Flicker * n)
end

-- A count of particles scaled by Lower effects (and `weight`), never below one.
local function count(n: number, weight: number?): number
	return math.max(1, math.floor(n * (weight or 1) * Quality.rate() + 0.5))
end

-- A row's colour keys, { time, r, g, b } each (Config is strict: no "#hex" in a number list).
local function keyColors(keys: { { number } }): ColorSequence
	local list = {}
	for _, k in keys do
		table.insert(list, ColorSequenceKeypoint.new(k[1], Color3.fromRGB(k[2], k[3], k[4])))
	end
	return ColorSequence.new(list)
end

-- A particle emitter from a CueVfx row, its shape too (Sphere, Surface: off the host's
-- surface), under `parent`.
local function emitter(row: any, parent: Instance): ParticleEmitter
	local plain = table.clone(row)
	plain.Color = nil
	local e = CueVfx.emitter(plain, { frame = "world" })
	if row.Color then
		e.Color = keyColors(row.Color)
	end
	if row.Shape then
		e.Shape = SHAPES[row.Shape] or Enum.ParticleEmitterShape.Box
		e.ShapeStyle = STYLES[row.ShapeStyle or "Volume"] or Enum.ParticleEmitterShapeStyle.Volume
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	end
	e.Enabled = true -- a rate of 0 emits nothing until told to (Emit)
	e.Parent = parent
	return e
end

local function flatPart(name: string, parent: Instance, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Transparency = 1
	part.Size = Vector3.new(0.05, F.ScorchThicknessStuds, 1)
	part.Parent = parent
	return part
end

-- Lay `part` flat from `a` to `b` (world), `width` wide and `extend` longer at each end (so
-- neighbouring pieces meet at a bend), its front (-Z) toward `a`: a texture on its top tiles
-- from the start and stays put as the piece grows at `b`.
local function lay(
	part: BasePart,
	a: Vector3,
	b: Vector3,
	width: number,
	thickness: number,
	extend: number
): boolean
	local len = (b - a).Magnitude
	if len < 1e-4 then
		return false
	end
	local size = Vector3.new(width, thickness, len + 2 * extend)
	if part.Size ~= size then
		part.Size = size
	end
	part.CFrame = CFrame.lookAt((a + b) / 2, a)
	return true
end

-- The same between two spots (inches) on table `m`'s cloth, `lift` inches up.
local function layOn(
	part: BasePart,
	m: any,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	width: number,
	lift: number,
	thickness: number
): boolean
	local a = TableBuilder.toWorld(m.placement, ax, ay, lift)
	local b = TableBuilder.toWorld(m.placement, bx, by, lift)
	return lay(part, a, b, width, thickness, width * 0.5)
end

-- The inward normal (into the table) of the cushion a ball centred at (x, y) just hit: the
-- nearer of the rails.
local function railNormal(m: any, x: number, y: number): (number, number)
	local g = m.state.geometry
	if g.halfLength - math.abs(x) < g.halfWidth - math.abs(y) then
		return if x > 0 then -1 else 1, 0
	end
	return 0, if y > 0 then -1 else 1
end

-- The team of the player `userId` at the table (the snapshot's seats), or nil.
local function teamOf(snapshot: any, userId: number): number?
	local seats = if type(snapshot) == "table" then snapshot.seats else nil
	if type(seats) ~= "table" then
		return nil
	end
	for _, s in seats do
		if type(s) == "table" and s.userId == userId and type(s.team) == "number" then
			return s.team
		end
	end
	return nil
end

-- Whether ball `id` is a fair first target for the shooter now (Main's rule for the
-- guideline's red cross): any ball on the break or in stopped time, else their group's.
local function fairTarget(snapshot: any, m: any, id: number?): boolean
	if id == nil or type(snapshot) ~= "table" then
		return true
	end
	if snapshot.breakShot or snapshot.phase == "Frozen" then
		return true
	end
	local groups = snapshot.groups
	local group = if type(groups) == "table" then groups[snapshot.activeTeam] else nil
	return Judge.legalTarget(m.state.balls, group, id)
end

---------------------------------------------------------------------------------------------
-- Types
---------------------------------------------------------------------------------------------

-- The fire on the cue ball: everything that follows it.
type Engulf = {
	host: Part, -- the invisible ball the emitters sit on
	flames: ParticleEmitter,
	licks: ParticleEmitter,
	embers: ParticleEmitter,
	smoke: ParticleEmitter,
	burst: ParticleEmitter, -- thrown out by a burst (Emit only)
	sparks: ParticleEmitter, -- likewise
	glow: ImageLabel,
	shell: Part?,
	light: PointLight,
	loop: Sound?,
	trail: Trail,
	core: Trail,
	ends: { Attachment }, -- the ribbon's two ends, then the core's
	last: Vector3?, -- where the ball was drawn last frame (the stream's start)
	across: Vector3, -- across its travel, level
	seed: number,
}

-- One straight run of the burn line (inches on the table), its heading from its first stretch.
type Piece = {
	part: Part,
	texture: Texture,
	ax: number,
	ay: number,
	bx: number,
	by: number,
	dx: number,
	dy: number,
	born: number, -- fx.clock
	shown: number, -- the transparency last set
}

type Splat = { part: Part, decal: Decal, born: number, shown: number }

-- A glowing stretch of fresh burn (a strip) or a splat's flash (a disc), cooling.
type Ember = { part: Part, born: number, seconds: number, disc: boolean }

-- One shot's scorch marks.
type Burn = {
	epoch: number,
	seq: number,
	team: number?,
	solo: boolean,
	sawOther: boolean, -- the other side has had the table since
	pieces: { Piece },
	splats: { Splat },
	open: Piece?, -- the piece still growing
	lastX: number?, -- the line's last point (nil: not on the cloth)
	lastY: number?,
	live: Ember?, -- the hot stretch from the last cut to the ball
	emberX: number,
	emberY: number,
	growing: boolean, -- its shot is still running
	expireAt: number?, -- fx.clock its fade began
	made: number, -- pieces and splats, against MaxScorchPieces
}

-- A "turn" or "down" event waiting for the frame's update (the shot it belongs to).
type Turn = { kind: "turn" | "down", x: number, y: number, seq: number }

-- A river of fire under one of the guideline's lines: a flat Beam between two attachments on
-- the line's holder.
type River = { a0: Attachment, a1: Attachment, beam: Beam }

-- The local shooter's aim at a table: a river under the guideline's aim, one under the object
-- ball's line and one under the cue ball's.
type Line = {
	folder: Folder,
	holder: Part, -- the rivers' attachments (at the origin: their CFrames are world CFrames)
	aim: River,
	object: River,
	cue: River,
	key: string?,
	visible: boolean,
}

type TableFx = {
	anchor: BasePart,
	-- The look's clock: wall time at the developer's /slowmo (m.timeScale), stopped with the
	-- replay by /hold (a still to capture). The marks appear, glow and fade on it.
	clock: number,
	engulf: Engulf?,
	level: number, -- the flames, 0..1
	shotSeq: number, -- the last Fire Shot seen here
	out: boolean, -- that shot's flames are out (the smoke and the sizzle played)
	lastHit: number, -- os.clock() of the last hit's sizzle
	turns: { Turn },
	burns: { Burn },
	burn: Burn?, -- the running shot's
	embers: { Ember },
	spare: { Part }, -- cooled ember strips to reuse
	spareDiscs: { Part },
	hidden: BasePart?, -- the cue ball part whose skin trail is hidden
	line: Line?,
}

local FireShotFx = {}
FireShotFx.__index = FireShotFx

export type FireShotFx = typeof(setmetatable(
	{} :: {
		hub: any,
		kit: any,
		tables: { [number]: TableFx },
		consumed: { [number]: number }, -- the armed ult's `at` once its shot ran
		teams: { [number]: number }, -- the arming shooter's team, while seen
	},
	FireShotFx
))

---------------------------------------------------------------------------------------------
-- The fire on the ball
---------------------------------------------------------------------------------------------

local function newTrail(
	name: string,
	a0: Attachment,
	a1: Attachment,
	parent: Instance,
	texture: string?
): Trail
	local trail = Instance.new("Trail")
	trail.Name = name
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	if texture then
		trail.Texture = texture
		trail.TextureMode = Enum.TextureMode.Wrap
		trail.TextureLength = F.TrailTextureLength
	end
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Enabled = false
	trail.Parent = parent
	return trail
end

local function newEngulf(self: FireShotFx, id: number, fx: TableFx): Engulf
	local kit = self.kit
	local w = ballWidth()
	local host = kit.part(id, "FireHost", {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * w * F.HostBallWidths,
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "FireGlow"
	billboard.Size = UDim2.fromScale(w * F.GlowBallWidths, w * F.GlowBallWidths)
	billboard.LightInfluence = 0
	billboard.Parent = host
	local image = Instance.new("ImageLabel")
	image.BackgroundTransparency = 1
	image.Size = UDim2.fromScale(1, 1)
	image.Image = ART.SoftGlow
	image.ImageColor3 = rgb(F.GlowColor)
	image.ImageTransparency = 1
	image.Parent = billboard
	local shell: Part? = nil
	if F.ShellBallWidths > 0 then
		shell = kit.part(id, "FireShell", {
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.Neon,
			Color = rgb(F.ShellColor),
			Size = Vector3.one * w * F.ShellBallWidths,
		})
	end
	local ends: { Attachment } = {}
	for _, name in { "FireTrailA", "FireTrailB", "FireCoreA", "FireCoreB" } do
		table.insert(ends, kit.attachment(id, name))
	end
	local trail = newTrail("FireTrail", ends[1], ends[2], fx.anchor, F.TrailTexture)
	trail.Lifetime = F.TrailSeconds
	trail.Brightness = F.TrailBrightness
	trail.Color = colorSeq(F.TrailColors)
	trail.Transparency = CueVfx.numberSeq(F.TrailTransparency)
	trail.WidthScale = NumberSequence.new(1, F.TrailTailWidth)
	local core = newTrail("FireCore", ends[3], ends[4], fx.anchor, nil)
	core.Lifetime = F.CoreSeconds
	core.Brightness = F.TrailBrightness
	core.Color = colorSeq(F.CoreColors)
	core.Transparency = NumberSequence.new(0.1, 1)
	core.WidthScale = NumberSequence.new(1, F.TrailTailWidth)
	local light = kit.light(host, {
		Color = rgb(F.LightColor),
		Range = F.LightRangeStuds,
		Brightness = 0,
	})
	local burst = emitter(F.BurstFlames, host)
	local sparks = emitter(F.Sparks, host)
	return {
		host = host,
		flames = emitter(F.Flames, host),
		licks = emitter(F.Licks, host),
		embers = emitter(F.Embers, host),
		smoke = emitter(F.Smoke, host),
		burst = burst,
		sparks = sparks,
		glow = image,
		shell = shell,
		light = light,
		loop = nil,
		trail = trail,
		core = core,
		ends = ends,
		last = nil,
		across = Vector3.xAxis,
		seed = id * 13.37,
	}
end

local function dropEngulf(fx: TableFx)
	local e = fx.engulf
	if e == nil then
		return
	end
	fx.engulf = nil
	if e.loop then
		e.loop:Destroy()
	end
	e.trail:Destroy()
	e.core:Destroy()
	for _, a in e.ends do
		a:Destroy()
	end
	if e.shell then
		e.shell:Destroy()
	end
	e.host:Destroy() -- its emitters, glow and light with it
end

local function setRates(e: Engulf, level: number)
	local q = Quality.rate() * level
	e.flames.Rate = F.Flames.Rate * q
	e.licks.Rate = F.Licks.Rate * q
	e.embers.Rate = F.Embers.Rate * q
	e.smoke.Rate = F.Smoke.Rate * q
end

-- Flames and sparks thrown off at `at` (world), and a flash of firelight there.
local function burst(
	self: FireShotFx,
	e: Engulf,
	at: Vector3,
	flames: number,
	sparks: number,
	brightness: number,
	range: number,
	seconds: number
)
	local back = e.host.CFrame
	e.host.CFrame = CFrame.new(at)
	e.burst:Emit(count(flames))
	e.sparks:Emit(count(sparks))
	e.host.CFrame = back
	self.kit.burstLight(at, rgb(F.LightColor), range, brightness, seconds)
end

-- A one-shot clip at `at` (world), its holder let go once it has played.
local function sting(self: FireShotFx, id: number, clip: any, at: Vector3, volume: number?)
	local kit = self.kit
	local holder = kit.attachment(id, "FireSound", at)
	kit.sound.library(clip, holder, { volume = volume })
	kit.later(id, F.HolderSeconds, function()
		holder:Destroy()
	end)
end

-- Flames along the frame's path from `from` to `to` (world): a fast ball leaves an unbroken
-- stream instead of a clump where each frame drew it.
local function stream(e: Engulf, from: Vector3, to: Vector3)
	local n = math.floor((to - from).Magnitude / F.StreamSpacingStuds)
	if n < 2 then
		return
	end
	n = math.min(n, math.max(1, math.floor(F.StreamMaxPerFrame * Quality.rate())))
	for i = 1, n do
		e.host.CFrame = CFrame.new(from:Lerp(to, (i - 0.5) / n))
		e.flames:Emit(1)
		if i % F.StreamLickEvery == 0 then
			e.licks:Emit(1)
		end
	end
end

-- The ribbons across the drawn ball, level, while `on`.
local function placeTrails(e: Engulf, at: Vector3, on: boolean)
	if on then
		local last = e.last
		if last then
			local travel = Vector3.new(at.X - last.X, 0, at.Z - last.Z)
			if travel.Magnitude > 1e-3 then
				e.across = travel.Unit:Cross(Vector3.yAxis)
			end
		end
		local half = ballWidth() * F.TrailBallWidths * 0.5
		e.ends[1].WorldPosition = at - e.across * half
		e.ends[2].WorldPosition = at + e.across * half
		e.ends[3].WorldPosition = at - e.across * half * F.CoreShare
		e.ends[4].WorldPosition = at + e.across * half * F.CoreShare
	end
	if e.trail.Enabled ~= on then
		if on then
			e.trail:Clear()
			e.core:Clear()
		end
		e.trail.Enabled = on
		e.core.Enabled = on
	end
end

-- The fire on the drawn cue ball at `level`; `moving`: it is burning its way across the table
-- (the stream and the ribbons).
local function placeEngulf(
	self: FireShotFx,
	e: Engulf,
	part: BasePart?,
	level: number,
	t: number,
	moving: boolean
)
	if part == nil or level <= 0.001 then
		setRates(e, 0)
		e.glow.ImageTransparency = 1
		if e.shell then
			e.shell.Transparency = 1
		end
		e.light.Brightness = 0
		if e.loop then
			e.loop:Destroy()
			e.loop = nil
		end
		placeTrails(e, e.host.Position, false)
		e.last = nil
		return
	end
	local at = part.Position
	local last = e.last
	if moving and last and (at - last).Magnitude < F.StreamMaxGapStuds then
		stream(e, last, at)
	end
	placeTrails(e, at, moving)
	e.host.CFrame = CFrame.new(at)
	e.last = at
	setRates(e, level)
	local f = flicker(t, e.seed)
	e.glow.ImageTransparency = 1
		- (1 - F.GlowTransparency) * level * math.clamp(0.8 + 0.2 * f, 0, 1)
	if e.shell then
		e.shell.CFrame = CFrame.new(at)
		e.shell.Transparency = 1
			- (1 - F.ShellTransparency) * level * math.clamp(0.75 + 0.25 * f, 0, 1)
	end
	e.light.Brightness = F.LightBrightness * level * f
	if e.loop == nil then
		e.loop = self.kit.sound.library(A.FireLoop, e.host, { looped = true, volume = 0 })
	end
	local loop = e.loop
	if loop then
		loop.Volume = (A.FireLoop.Volume or 1) * level
	end
end

---------------------------------------------------------------------------------------------
-- Scorch marks
---------------------------------------------------------------------------------------------

local function scorchWidth(): number
	return TableBuilder.studs(F.ScorchWidthInches)
end

local function layPiece(m: any, piece: Piece)
	local w = scorchWidth()
	layOn(
		piece.part,
		m,
		piece.ax,
		piece.ay,
		piece.bx,
		piece.by,
		w,
		F.ScorchLiftInches,
		F.ScorchThicknessStuds
	)
end

local function newPiece(
	self: FireShotFx,
	id: number,
	fx: TableFx,
	burn: Burn,
	m: any,
	ax: number,
	ay: number,
	bx: number,
	by: number
): Piece?
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy)
	if burn.made >= F.MaxScorchPieces or len < 1e-6 then
		return nil
	end
	burn.made += 1
	local part = self.kit.part(id, "Scorch")
	local w = scorchWidth()
	local texture = Instance.new("Texture")
	texture.Name = "Burn"
	texture.Face = Enum.NormalId.Top
	texture.Texture = F.ScorchStripTexture
	texture.Color3 = rgb(F.ScorchColor)
	texture.StudsPerTileU = w
	texture.StudsPerTileV = w * F.ScorchTileWidths
	texture.Transparency = 1
	texture.Parent = part
	local piece: Piece = {
		part = part,
		texture = texture,
		ax = ax,
		ay = ay,
		bx = bx,
		by = by,
		dx = dx / len,
		dy = dy / len,
		born = fx.clock,
		shown = 1,
	}
	layPiece(m, piece)
	table.insert(burn.pieces, piece)
	return piece
end

-- An ember strip (Neon) or a splat's flash (a flat Neon disc), reused when one has cooled.
local function emberPart(fx: TableFx, disc: boolean): Part
	local part = table.remove(if disc then fx.spareDiscs else fx.spare)
	if part then
		return part
	end
	local fresh = flatPart(if disc then "SplatFlash" else "Ember", fx.anchor, rgb(F.EmberHotColor))
	if disc then
		fresh.Shape = Enum.PartType.Cylinder
	end
	return fresh
end

local function newSplat(
	self: FireShotFx,
	id: number,
	fx: TableFx,
	burn: Burn,
	m: any,
	x: number,
	y: number,
	scale: number
)
	if burn.made >= F.MaxScorchPieces then
		return
	end
	burn.made += 1
	local d = TableBuilder.studs(F.SplatInches * scale)
	local turn = CFrame.Angles(0, GOLDEN * (#burn.splats + burn.seq), 0)
	local part = self.kit.part(id, "ScorchSplat", {
		Size = Vector3.new(d, F.ScorchThicknessStuds, d),
		CFrame = CFrame.new(TableBuilder.toWorld(m.placement, x, y, F.SplatLiftInches)) * turn,
	})
	local decal = Instance.new("Decal")
	decal.Name = "Burn"
	decal.Face = Enum.NormalId.Top
	decal.Texture = F.ScorchSplatTexture
	decal.Color3 = rgb(F.ScorchColor)
	decal.Transparency = 1
	decal.Parent = part
	table.insert(burn.splats, { part = part, decal = decal, born = fx.clock, shown = 1 })
	-- Its flash: a hot disc that cools away (a cylinder lies along X: stood on its side).
	local flash = emberPart(fx, true)
	local fd = d * F.SplatEmberShare
	flash.Size = Vector3.new(F.ScorchThicknessStuds, fd, fd)
	flash.CFrame = CFrame.new(TableBuilder.toWorld(m.placement, x, y, F.EmberLiftInches))
		* CFrame.Angles(0, 0, math.pi / 2)
	flash.Color = rgb(F.EmberHotColor)
	flash.Transparency = F.EmberTransparency
	table.insert(
		fx.embers,
		{ part = flash, born = fx.clock, seconds = F.SplatEmberSeconds, disc = true }
	)
end

-- Lay the live ember (the hot stretch from the last cut to the ball).
local function layLive(fx: TableFx, burn: Burn, m: any, x: number, y: number)
	local live = burn.live
	if live == nil then
		local fresh: Ember =
			{ part = emberPart(fx, false), born = 0, seconds = F.EmberSeconds, disc = false }
		burn.live = fresh
		live = fresh
	end
	local part = (live :: Ember).part
	local w = scorchWidth() * F.EmberWidthShare
	if
		layOn(part, m, burn.emberX, burn.emberY, x, y, w, F.EmberLiftInches, F.ScorchThicknessStuds)
	then
		part.Color = rgb(F.EmberHotColor)
		part.Transparency = F.EmberTransparency
	end
end

-- Cut the live ember at the line's last point: it starts cooling, a new one runs on from here.
local function cutEmber(fx: TableFx, burn: Burn)
	local live = burn.live
	if live then
		burn.live = nil
		live.born = fx.clock
		table.insert(fx.embers, live)
	end
	if burn.lastX and burn.lastY then
		burn.emberX, burn.emberY = burn.lastX :: number, burn.lastY :: number
	end
end

-- The line breaks here (in the air, down a pocket, the shot over).
local function breakLine(fx: TableFx, burn: Burn)
	cutEmber(fx, burn)
	burn.open = nil
	burn.lastX, burn.lastY = nil, nil
end

-- The burn line reaches (x, y): the open piece grows to it while the heading holds, else a new
-- piece starts from the last point; `corner`: the ball bent here (a cushion or a ball).
local function addPoint(
	self: FireShotFx,
	id: number,
	fx: TableFx,
	burn: Burn,
	m: any,
	x: number,
	y: number,
	corner: boolean
)
	local lx, ly = burn.lastX, burn.lastY
	if lx == nil or ly == nil then
		burn.lastX, burn.lastY = x, y
		burn.emberX, burn.emberY = x, y
		return
	end
	local dx, dy = x - lx, y - ly
	local len = math.sqrt(dx * dx + dy * dy)
	if len < F.ScorchMinStepInches then
		return
	end
	local ux, uy = dx / len, dy / len
	local open = burn.open
	if open and open.dx * ux + open.dy * uy >= COS_TURN then
		open.bx, open.by = x, y
		layPiece(m, open)
	else
		cutEmber(fx, burn)
		burn.open = newPiece(self, id, fx, burn, m, lx, ly, x, y)
	end
	burn.lastX, burn.lastY = x, y
	layLive(fx, burn, m, x, y)
	local ex, ey = x - burn.emberX, y - burn.emberY
	if corner or ex * ex + ey * ey >= F.EmberSegmentInches * F.EmberSegmentInches then
		cutEmber(fx, burn)
	end
end

local function dropBurn(burn: Burn)
	for _, piece in burn.pieces do
		piece.part:Destroy()
	end
	for _, splat in burn.splats do
		splat.part:Destroy()
	end
	if burn.live then
		burn.live.part:Destroy()
		burn.live = nil
	end
	table.clear(burn.pieces)
	table.clear(burn.splats)
end

-- The running shot's burn stops growing.
local function finishBurn(fx: TableFx)
	local burn = fx.burn
	if burn then
		fx.burn = nil
		burn.growing = false
		breakLine(fx, burn)
	end
end

local function startBurn(self: FireShotFx, id: number, fx: TableFx, m: any, snapshot: any)
	finishBurn(fx)
	local team = self.teams[id]
	if team == nil and type(snapshot) == "table" and type(snapshot.activeTeam) == "number" then
		team = snapshot.activeTeam
	end
	local burn: Burn = {
		epoch = m.epoch or 0,
		seq = m.seq or 0,
		team = team,
		solo = type(snapshot) == "table" and snapshot.solo ~= nil,
		sawOther = false,
		pieces = {},
		splats = {},
		open = nil,
		lastX = nil,
		lastY = nil,
		live = nil,
		emberX = 0,
		emberY = 0,
		growing = true,
		expireAt = nil,
		made = 0,
	}
	table.insert(fx.burns, burn)
	fx.burn = burn
	local start = m.shot and m.shot.cueStart
	if start then
		burn.lastX, burn.lastY = start[1], start[2]
		burn.emberX, burn.emberY = start[1], start[2]
		newSplat(self, id, fx, burn, m, start[1], start[2], F.StrikeSplatScale)
	end
	-- At most MaxBurns shots' marks: the oldest still down fades now.
	local kept = 0
	local t = fx.clock
	for i = #fx.burns, 1, -1 do
		local b = fx.burns[i]
		if b.expireAt == nil then
			kept += 1
			if kept > F.MaxBurns then
				b.expireAt = t
			end
		end
	end
end

-- This frame's corners, then where the cue ball is now.
local function stepPath(self: FireShotFx, id: number, fx: TableFx, m: any, cue: any)
	local burn = fx.burn
	if burn == nil then
		table.clear(fx.turns)
		return
	end
	for _, turn in fx.turns do
		if turn.seq ~= burn.seq then
			continue
		end
		if turn.kind == "down" then
			breakLine(fx, burn)
			burn.lastX, burn.lastY = turn.x, turn.y
			burn.emberX, burn.emberY = turn.x, turn.y
			newSplat(self, id, fx, burn, m, turn.x, turn.y, F.DownSplatScale)
		else
			addPoint(self, id, fx, burn, m, turn.x, turn.y, true)
			newSplat(self, id, fx, burn, m, turn.x, turn.y, F.HitSplatScale)
		end
	end
	table.clear(fx.turns)
	-- No burn down a pocket, off the table or in the air.
	if cue == nil or cue.pocketed or cue.offTable or (cue.z or 0) > F.AirInches then
		breakLine(fx, burn)
	else
		addPoint(self, id, fx, burn, m, cue.x, cue.y, false)
	end
end

-- Each burn's lifetime (until the shooter's next turn), its fade in and out, and the embers'
-- cooling. The table's anchor is held while any burn is down.
local function stepBurns(
	self: FireShotFx,
	id: number,
	fx: TableFx,
	m: any,
	snapshot: any,
	t: number
)
	for i = #fx.burns, 1, -1 do
		local burn = fx.burns[i]
		if burn.expireAt == nil and not burn.growing then
			local gone = type(snapshot) ~= "table"
				or (snapshot.epoch ~= nil and snapshot.epoch ~= burn.epoch)
			if not gone then
				if burn.solo then
					gone = m.seq ~= burn.seq -- Solo: until their next shot
				elseif burn.team ~= nil then
					if snapshot.activeTeam ~= burn.team then
						burn.sawOther = true
					elseif burn.sawOther then
						gone = true -- the table is back on the shooter's side
					end
				end
			end
			if gone then
				burn.expireAt = t
			end
		end
		local fade = if burn.expireAt
			then math.clamp((t - burn.expireAt) / F.ExpireSeconds, 0, 1)
			else 0
		if fade >= 1 then
			dropBurn(burn)
			table.remove(fx.burns, i)
			continue
		end
		local keep = 1 - fade
		for _, piece in burn.pieces do
			local seen = math.clamp((t - piece.born) / F.ScorchAppearSeconds, 0, 1) * keep
			local transparency = 1 - (1 - F.ScorchTransparency) * seen
			if math.abs(transparency - piece.shown) > 1e-3 then
				piece.shown = transparency
				piece.texture.Transparency = transparency
			end
		end
		for _, splat in burn.splats do
			local seen = math.clamp((t - splat.born) / F.ScorchAppearSeconds, 0, 1) * keep
			local transparency = 1 - (1 - F.ScorchTransparency) * seen
			if math.abs(transparency - splat.shown) > 1e-3 then
				splat.shown = transparency
				splat.decal.Transparency = transparency
			end
		end
	end
	local hot, cool = rgb(F.EmberHotColor), rgb(F.EmberCoolColor)
	for i = #fx.embers, 1, -1 do
		local ember = fx.embers[i]
		local u = (t - ember.born) / ember.seconds
		if u >= 1 then
			ember.part.Transparency = 1
			table.insert(if ember.disc then fx.spareDiscs else fx.spare, ember.part)
			table.remove(fx.embers, i)
		else
			ember.part.Color = hot:Lerp(cool, math.min(1, u * 1.5))
			ember.part.Transparency = F.EmberTransparency + (1 - F.EmberTransparency) * u * u
		end
	end
	if #fx.burns > 0 or #fx.embers > 0 then
		self.kit.anchor(id) -- held while marks are down
	end
end

---------------------------------------------------------------------------------------------
-- The aim line (the local shooter's)
---------------------------------------------------------------------------------------------

local function newRiver(holder: Part, name: string): River
	local a0 = Instance.new("Attachment")
	a0.Name = name .. "From"
	a0.Parent = holder
	local a1 = Instance.new("Attachment")
	a1.Name = name .. "To"
	a1.Parent = holder
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Texture = F.RiverTexture
	beam.TextureMode = Enum.TextureMode.Wrap
	beam.TextureLength = F.RiverTextureLength
	beam.TextureSpeed = F.RiverTextureSpeed
	beam.Width0 = F.RiverWidthStuds
	beam.Width1 = F.RiverWidthStuds
	beam.FaceCamera = false
	beam.Segments = 1
	beam.LightEmission = F.RiverLightEmission
	beam.LightInfluence = 0
	beam.Brightness = F.RiverBrightness
	-- Hot where the line starts, deeper and thinner where it goes.
	beam.Color = ColorSequence.new(rgb(F.RiverColor), rgb(F.RiverFarColor))
	beam.Transparency = NumberSequence.new(F.RiverTransparency, F.RiverFarTransparency)
	beam.Enabled = false
	beam.Parent = holder
	return { a0 = a0, a1 = a1, beam = beam }
end

local function newLine(fx: TableFx): Line
	local folder = Instance.new("Folder")
	folder.Name = "FireShotLine"
	folder.Parent = fx.anchor
	local holder = flatPart("RiverHolder", folder, Color3.new(1, 1, 1))
	holder.Size = Vector3.one * 0.1
	holder.CFrame = CFrame.identity
	return {
		folder = folder,
		holder = holder,
		aim = newRiver(holder, "AimRiver"),
		object = newRiver(holder, "ObjectRiver"),
		cue = newRiver(holder, "CueRiver"),
		key = nil,
		visible = false,
	}
end

-- Lay `river` flat on table `m` from (x0, y0) to (x1, y1) (table inches), flowing that way;
-- hidden when shorter than the guideline's shortest line.
local function layRiver(river: River, m: any, x0: number, y0: number, x1: number, y1: number)
	local dx, dy = x1 - x0, y1 - y0
	local min = Config.Guideline.MinStubInches
	if dx * dx + dy * dy < min * min then
		river.beam.Enabled = false
		return
	end
	local a0 = TableBuilder.toWorld(m.placement, x0, y0, F.RiverLiftInches)
	local a1 = TableBuilder.toWorld(m.placement, x1, y1, F.RiverLiftInches)
	local across = (a1 - a0).Unit:Cross(Vector3.yAxis)
	-- A flat beam: its width runs along each attachment's Y, laid level across the line.
	river.a0.CFrame = CFrame.fromMatrix(a0, Vector3.yAxis, across)
	river.a1.CFrame = CFrame.fromMatrix(a1, Vector3.yAxis, across)
	river.beam.Enabled = true
end

local function hideLine(line: Line)
	line.key = nil
	if line.visible then
		line.visible = false
		line.aim.beam.Enabled = false
		line.object.beam.Enabled = false
		line.cue.beam.Enabled = false
	end
end

-- The rivers under the guideline's lines for `trace` (Aim.trace) and `full` (Aim.fullLines)
-- on table `m`, where Guideline.show draws them: the aim from the cue ball's front edge (where
-- a jump settles) to the ghost ring's near edge, none for a contact in the air; the object
-- ball's line from its far edge, and the cue ball's from the ring's edge, each on until it
-- touches what it meets. `invalid` (a ball that is not a fair first target): the aim's only,
-- as the guideline then draws its red cross instead of the two lines.
local function drawLine(line: Line, m: any, trace: Aim.Trace, full: Aim.FullLines, invalid: boolean)
	local R = Config.Balls.RadiusInches
	local ringR = Config.Balls.RenderRadiusInches * Config.Guideline.RingScale
	local gx, gy = trace.ghostX, trace.ghostY
	local fromX, fromY = trace.startX, trace.startY
	local hops = trace.hops
	if #hops > 0 then
		local last = hops[#hops]
		fromX, fromY = last.x + last.vx * last.seconds, last.y + last.vy * last.seconds
	end
	local dx, dy = gx - fromX, gy - fromY
	local len = math.sqrt(dx * dx + dy * dy)
	if trace.contact == "none" or (#hops > 0 and trace.airborne) or len <= R + ringR then
		line.aim.beam.Enabled = false
	else
		local ux, uy = dx / len, dy / len
		layRiver(line.aim, m, fromX + ux * R, fromY + uy * R, gx - ux * ringR, gy - uy * ringR)
	end
	local object = if invalid or trace.contact ~= "ball" then nil else full.object
	if object then
		local ux, uy = trace.objectDirX, trace.objectDirY
		local start, stop = 2 * R + ringR, 2 * R + object + R
		layRiver(line.object, m, gx + ux * start, gy + uy * start, gx + ux * stop, gy + uy * stop)
	else
		line.object.beam.Enabled = false
	end
	local cue = if invalid then nil else full.cue
	if cue then
		local ux, uy = trace.cueDirX, trace.cueDirY
		layRiver(
			line.cue,
			m,
			gx + ux * ringR,
			gy + uy * ringR,
			gx + ux * (cue + R),
			gy + uy * (cue + R)
		)
	else
		line.cue.beam.Enabled = false
	end
	line.visible = true
end

-- A fingerprint of where the balls stand (and which are down): a moved or potted ball is a
-- new line (Eagle's Eye's).
local function ballsKey(m: any): number
	local sum = 0
	for _, b in m.state.balls do
		local q = if b.pocketed
			then -1 - b.id
			else quantise(b.x, F.BallKeyInches) * 7919 + quantise(b.y, F.BallKeyInches)
		sum = (sum * 31 + q + b.id) % 1000000007
	end
	return sum
end

---------------------------------------------------------------------------------------------
-- Per table
---------------------------------------------------------------------------------------------

local function create(self: FireShotFx, id: number): TableFx
	local fx: TableFx = {
		anchor = self.kit.anchor(id),
		clock = 0,
		engulf = nil,
		level = 0,
		shotSeq = -1,
		out = true,
		lastHit = -math.huge,
		turns = {},
		burns = {},
		burn = nil,
		embers = {},
		spare = {},
		spareDiscs = {},
		hidden = nil,
		line = nil,
	}
	self.tables[id] = fx
	return fx
end

-- Show the cue skin's own trail again.
local function unhide(fx: TableFx)
	local part = fx.hidden
	if part then
		fx.hidden = nil
		if part.Parent then
			part:SetAttribute("HideTrail", nil)
		end
	end
end

local function destroy(self: FireShotFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unhide(fx)
	dropEngulf(fx)
	for _, burn in fx.burns do
		dropBurn(burn)
	end
	for _, ember in fx.embers do
		ember.part:Destroy()
	end
	for _, part in fx.spare do
		part:Destroy()
	end
	for _, part in fx.spareDiscs do
		part:Destroy()
	end
	if fx.line then
		fx.line.folder:Destroy()
	end
end

-- The strike: a burst off the ball, a flash, the roar, and the players' punch and shake.
local function strike(self: FireShotFx, id: number, fx: TableFx, m: any)
	local kit = self.kit
	local e = fx.engulf or newEngulf(self, id, fx)
	fx.engulf = e
	fx.level = math.max(fx.level, F.StrikeLevel)
	local part = kit.ballPart(id, 0)
	if part then
		part:SetAttribute("HideTrail", true) -- the burning ribbon instead (Effects.updateTrail)
		fx.hidden = part
	end
	local start = m.shot and m.shot.cueStart
	if start == nil then
		return
	end
	local at = kit.tableWorld(m, start[1], start[2], Config.Balls.RenderRadiusInches)
	e.last = at -- the stream runs from the strike
	if m.state.time > F.FreshSeconds then
		return -- a late join's catch-up: no bang
	end
	burst(
		self,
		e,
		at,
		F.StrikeFlames,
		F.StrikeSparks,
		F.StrikeLightBrightness,
		F.StrikeLightRangeStuds,
		F.StrikeLightSeconds
	)
	sting(self, id, A.FireLaunch, at)
	kit.screen.fovPunch(id, F.StrikeFovDegrees, F.StrikeFovSeconds)
	kit.screen.shake(id, F.StrikeShakeStuds, F.StrikeShakeSeconds)
end

-- The flames go out: a puff of smoke and a sizzle where the ball is.
local function putOut(self: FireShotFx, id: number, fx: TableFx, m: any, cue: any)
	fx.out = true
	finishBurn(fx)
	local e = fx.engulf
	local part = self.kit.ballPart(id, 0)
	local at = if part then part.Position elseif cue then self.kit.ballWorld(m, cue) else nil
	if e == nil or at == nil then
		return
	end
	local back = e.host.CFrame
	e.host.CFrame = CFrame.new(at :: Vector3)
	e.smoke:Emit(count(F.OutSmoke))
	e.host.CFrame = back
	sting(self, id, A.FireOut, at :: Vector3)
end

-- A replay event: the shot's corners (kept for the frame's update), and at each fresh hit the
-- sparks, the puff, the flash and the sizzle.
local function onEvent(self: FireShotFx, id: number, m: any, ev: any)
	if ev.type ~= "ult" or (ev.kind ~= "turn" and ev.kind ~= "down") then
		return
	end
	if not self.kit.isShotOf(m, EFFECT) or type(ev.x) ~= "number" or type(ev.y) ~= "number" then
		return
	end
	local fx = self.tables[id] or create(self, id)
	table.insert(fx.turns, { kind = ev.kind, x = ev.x, y = ev.y, seq = m.seq })
	local e = fx.engulf
	if
		ev.kind ~= "turn"
		or e == nil
		or m.renderer == nil
		or m.state.time - ev.t > F.FreshSeconds
	then
		return
	end
	-- Where it touched: the cushion's face, or between the two balls.
	local R = Config.Balls.RadiusInches
	local cx, cy = ev.x, ev.y
	if type(ev.other) == "number" then
		local other = self.kit.ballOf(m, ev.other)
		if other then
			local dx, dy = other.x - ev.x, other.y - ev.y
			local len = math.sqrt(dx * dx + dy * dy)
			if len > 1e-6 then
				cx, cy = ev.x + dx / len * R, ev.y + dy / len * R
			end
		end
	else
		local nx, ny = railNormal(m, ev.x, ev.y)
		cx, cy = ev.x - nx * R, ev.y - ny * R
	end
	local weight = math.clamp((ev.value or 0) / F.FullSpeed, F.MinWeight, 1)
	local at = self.kit.tableWorld(m, cx, cy, Config.Balls.RenderRadiusInches)
	burst(
		self,
		e,
		at,
		F.HitFlames * weight,
		F.HitSparks * weight,
		F.HitLightBrightness * weight,
		F.HitLightRangeStuds,
		F.HitLightSeconds
	)
	local t = os.clock()
	if t - fx.lastHit >= F.HitGapSeconds then
		fx.lastHit = t
		sting(self, id, A.FireHit, at, weight)
	end
end

---------------------------------------------------------------------------------------------
-- The look
---------------------------------------------------------------------------------------------

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function FireShotFx.start(hub: any, _parent: Instance, kit: any): FireShotFx
	local self = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
		teams = {},
	}, FireShotFx)
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			self.tables[tableId] = nil -- its parts went with the anchor
			unhide(fx)
		end
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		onEvent(self, tableId, m, ev)
	end)
	-- Fetch the sounds and the art now, so the first ignition is not silent or blank.
	task.spawn(function()
		local list: { any } = {}
		for _, clip in { A.FireIgnite, A.FireLoop, A.FireLaunch, A.FireHit, A.FireOut } do
			if clip.Id ~= "" then
				local sound = Instance.new("Sound")
				sound.SoundId = clip.Id
				table.insert(list, sound)
			end
		end
		for _, id in
			{
				F.ScorchStripTexture,
				F.ScorchSplatTexture,
				F.RiverTexture,
				F.TrailTexture,
				F.Flames.Texture,
				F.Licks.Texture,
				F.Smoke.Texture,
				F.Embers.Texture,
			}
		do
			table.insert(list, id)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			if typeof(item) == "Instance" then
				item:Destroy()
			end
		end
	end)
	return self
end

--- The arming moment at table `tableId` (UltCutscene's onArming, at armed.readyAt): the cue
--- ball catches fire with a burst, a flash and a whoosh.
function FireShotFx.arming(self: FireShotFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local cue = m:findCueBall()
	if cue == nil or cue.pocketed then
		return
	end
	local fx = self.tables[tableId] or create(self, tableId)
	local e = fx.engulf or newEngulf(self, tableId, fx)
	fx.engulf = e
	local at = self.kit.ballWorld(m, cue)
	e.host.CFrame = CFrame.new(at)
	e.last = nil
	fx.level = math.max(fx.level, F.IgniteLevel)
	burst(
		self,
		e,
		at,
		F.IgniteFlames,
		F.IgniteSparks,
		F.IgniteLightBrightness,
		F.IgniteLightRangeStuds,
		F.IgniteLightSeconds
	)
	sting(self, tableId, A.FireIgnite, at)
end

--- The local shooter's aim at their own table while Fire Shot is armed (AbilityFx's aiming
--- hook): the rivers of fire under the guideline's full lines; `shot` nil hides them.
function FireShotFx.aiming(self: FireShotFx, tableId: number, armed: any, shot: any?, m: any)
	local fx: TableFx? = self.tables[tableId]
	if fx and fx.anchor.Parent == nil then
		self.tables[tableId] = nil
		fx = nil
	end
	if shot == nil or m == nil or m.renderer == nil or m:isBusy() then
		if fx and fx.line then
			hideLine(fx.line)
		end
		return
	end
	local live = fx or create(self, tableId)
	self.kit.anchor(tableId) -- kept while aiming
	local line = live.line or newLine(live)
	live.line = line
	-- The guideline's own trace (Main's refreshAim): the pull, at least the shortest stroke.
	local power = math.max(
		if type(shot.power) == "number" then shot.power else 0,
		Config.Input.MinPowerToShoot
	)
	local spin = shot.spin or { x = 0, y = 0 }
	local elevation = shot.elevation or 0
	local key = ("%d|%d|%d|%d|%d|%d|%d|%d"):format(
		quantise(shot.angle % TAU, F.AngleStep),
		quantise(elevation, Config.Cue.ElevationStepDegrees),
		quantise(power, F.PowerStep),
		quantise(spin.x, F.SpinStep),
		quantise(spin.y, F.SpinStep),
		m.epoch or 0,
		m.seq or 0,
		ballsKey(m)
	)
	if key == line.key then
		return
	end
	line.key = key
	local trace = Aim.trace(m.state, {
		angle = shot.angle,
		power = power,
		spin = { x = spin.x, y = spin.y },
		elevation = shot.elevation,
	}, Catalog.launchScale(armed and armed.id))
	local invalid = trace.contact == "ball"
		and not fairTarget(self.hub.snapshots[tableId], m, trace.objectId)
	drawLine(line, m, trace, Aim.fullLines(m.state, trace), invalid)
end

--- Every frame, after the hub has stepped the replays.
function FireShotFx.update(self: FireShotFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local t = os.clock()
	local kit = self.kit
	for id, m in self.hub.matches do
		local fx: TableFx? = self.tables[id]
		if fx and fx.anchor.Parent == nil then
			self.tables[id] = nil
			fx = nil
		end
		if m.renderer == nil then
			if fx then
				destroy(self, id)
			end
			continue
		end
		local snapshot = self.hub.snapshots[id]
		local armed = kit.armedOf(snapshot, EFFECT)
		if armed then
			local team = teamOf(snapshot, armed.by)
			if team then
				self.teams[id] = team
			end
		end
		local shot = kit.isShotOf(m, EFFECT)
		if shot and armed then
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		if fx == nil then
			if not (wantArmed or shot) then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		local scale = if type(m.timeScale) == "number" then m.timeScale else 1
		local held = m.holdAt ~= nil and m.state.time >= m.holdAt
		live.clock += if held then 0 else dt * scale
		local cue = m:findCueBall()

		-- A new Fire Shot: the strike, and its burn begins.
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.out = false
			startBurn(self, id, live, m, snapshot)
			strike(self, id, live, m)
		end
		if live.burn then
			stepPath(self, id, live, m, cue)
		else
			table.clear(live.turns)
		end

		-- Burning while its shot runs and it moves; out at rest, down a pocket or off the table.
		local burning = false
		local speed = 0
		if live.shotSeq == m.seq and not live.out then
			local down = cue == nil or cue.pocketed or cue.offTable
			if cue then
				speed = math.sqrt(cue.vx * cue.vx + cue.vy * cue.vy + cue.vz * cue.vz)
			end
			if not shot or down or not Ball.isMoving(cue) then
				putOut(self, id, live, m, cue)
			else
				burning = true
			end
		end
		if not shot and live.hidden then
			unhide(live)
		end

		local target = if wantArmed or burning then 1 else 0
		local seconds = if target > live.level
			then F.IgniteSeconds
			elseif cue and cue.pocketed then F.DrownSeconds
			else F.DieSeconds
		live.level = approach(live.level, target, dt, seconds)
		local e = live.engulf
		if e == nil and live.level > 0.001 then
			e = newEngulf(self, id, live)
			live.engulf = e
		end
		if e then
			local moving = burning and speed > F.TrailMinSpeed
			placeEngulf(self, e, kit.ballPart(id, 0), live.level, t, moving)
			if live.level <= 0.001 and target == 0 and not e.trail.Enabled then
				dropEngulf(live)
			end
		end

		stepBurns(self, id, live, m, snapshot, live.clock)
		if
			live.engulf == nil
			and #live.burns == 0
			and #live.embers == 0
			and not shot
			and not wantArmed
			and not (live.line and live.line.visible)
		then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function FireShotFx.clear(self: FireShotFx)
	local ids: { number } = {}
	for id in self.tables do
		table.insert(ids, id)
	end
	for _, id in ids do
		destroy(self, id)
	end
end

return FireShotFx
