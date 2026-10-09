--!strict
-- SteelBallFx: what Steel Ball looks and sounds like (the abilities rework, designer
-- 2026-10-08: "actually steel shiny and glossy", spinning up "like a fidget spinner", the
-- golden ratio "in yellow outline" at the hit, every guided ball "spinning incredibly fast").
-- The guiding is physics (Ults/Effects/SteelBall); this only draws it, off the replay's events
-- and its state.fx.steel (the guided balls' paths), so everyone sees it together. Numbers in
-- Config.UI.SteelBallFx, the sounds in Config.Ults.Audio (Steel*), the streak ring, burst and
-- sparkle images in Config.Ults.Assets.Images (SteelSpinBlur, SteelBurst, SteelSparkle).
--
--   * Armed (from the arming moment until the shot): the cue ball is Gyro's green steel ball
--     (designer 2026-10-09: the reference's hexagon plate, dome, ribs and engraved swirls,
--     glossy metal: ReplicatedStorage[Config.Ults.Assets.LooksFolder].SteelBall, built by
--     tools/build_ability_looks.luau; a green mirror without it). It spins up about the
--     upright: slowly, then faster and faster over SpinUpSeconds with a rising whine, until
--     it smears into a ring of streaks; then it hums at full spin.
--   * The shot: it rolls on spinning, the streaks round it and a white-gold trail behind, a
--     clank on each contact. The first hit: the activation's clip again, and the golden ratio
--     draws itself in glowing yellow lines on the cloth (the golden rectangle, its squares and
--     the spiral), the spiral's eye on the contact and its tail toward the cue ball, with a
--     hum; gold sparkles and a small shake.
--   * Every ball it sends ("guide") spins hard about the upright in its own streak ring, a
--     yellow guide line drawn ahead of it to its pocket (or to where a lined-up ball stops);
--     each guided pot, a gold burst ring, sparkles and a twinkle at the pocket.
--   * After it: everything fades out and the cue ball is itself again.
-- Every table's parts hang off its AbilityFx anchor and go with it (kit.onRelease) or with
-- clear().

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ults = Shared:WaitForChild("Ults")
local Catalog = require(Ults:WaitForChild("Catalog"))

local F = Config.UI.SteelBallFx
local A = Config.Ults.Audio
local IMAGES = Config.Ults.Assets.Images :: any

local EFFECT = "SteelBall"
local TAU = 2 * math.pi
local PHI = (1 + math.sqrt(5)) / 2
-- A cubic Bezier's handle for a quarter circle of radius 1 (how a beam draws an arc).
local QUARTER_HANDLE = 0.5523

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ballWidth(): number
	return Config.Balls.RenderRadiusInches * 2 * Config.Table.StudsPerInch
end

local function approach(level: number, target: number, dt: number, seconds: number): number
	local step = dt / math.max(seconds, 1e-3)
	if level < target then
		return math.min(target, level + step)
	end
	return math.max(target, level - step)
end

local function easeOut(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) * (1 - u)
end

--------------------------------------------------------------------------------------------
-- The golden ratio diagram, in its own units: the golden rectangle 0..PHI across and 0..1 up,
-- the biggest square on the left, then each next square clockwise (top, right, bottom, left
-- again); the spiral is one quarter circle a square, from the bottom-left corner clockwise
-- into the eye. Built once.
--------------------------------------------------------------------------------------------

type Line = { x0: number, y0: number, x1: number, y1: number }
type Arc = { cx: number, cy: number, r: number, a0: number } -- from angle a0 to a0 - 90 deg

local function goldenDiagram(squares: number): ({ Line }, { Line }, { Arc }, Vector2)
	local outline: { Line } = {
		{ x0 = 0, y0 = 0, x1 = 0, y1 = 1 },
		{ x0 = 0, y0 = 1, x1 = PHI, y1 = 1 },
		{ x0 = PHI, y0 = 1, x1 = PHI, y1 = 0 },
		{ x0 = PHI, y0 = 0, x1 = 0, y1 = 0 },
	}
	local dividers: { Line } = {}
	local arcs: { Arc } = {}
	-- The part of the rectangle not yet squared.
	local x0, y0, w, h = 0, 0, PHI, 1
	for k = 0, squares - 1 do
		local side = k % 4
		local s = math.min(w, h)
		if side == 0 then -- on the left; the arc's centre at the square's bottom right
			table.insert(arcs, { cx = x0 + s, cy = y0, r = s, a0 = math.pi })
			table.insert(dividers, { x0 = x0 + s, y0 = y0, x1 = x0 + s, y1 = y0 + h })
			x0, w = x0 + s, w - s
		elseif side == 1 then -- on top; the centre at its bottom left
			table.insert(arcs, { cx = x0, cy = y0 + h - s, r = s, a0 = math.pi / 2 })
			table.insert(dividers, { x0 = x0, y0 = y0 + h - s, x1 = x0 + w, y1 = y0 + h - s })
			h -= s
		elseif side == 2 then -- on the right; the centre at its top left
			table.insert(arcs, { cx = x0 + w - s, cy = y0 + s, r = s, a0 = 0 })
			table.insert(dividers, { x0 = x0 + w - s, y0 = y0, x1 = x0 + w - s, y1 = y0 + h })
			w -= s
		else -- at the bottom; the centre at its top right
			table.insert(arcs, { cx = x0 + w, cy = y0 + s, r = s, a0 = -math.pi / 2 })
			table.insert(dividers, { x0 = x0, y0 = y0 + s, x1 = x0 + w, y1 = y0 + s })
			y0, h = y0 + s, h - s
		end
	end
	return outline, dividers, arcs, Vector2.new(x0 + w / 2, y0 + h / 2)
end

local OUTLINE, DIVIDERS, ARCS, EYE = goldenDiagram(F.SpiralSquares)

--------------------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------------------

-- One line of a drawing: a bright core over a wider glow, hidden until the pen reaches it
-- (from..to, seconds into the drawing).
type Stroke = { core: Beam, glow: Beam, from: number, to: number }
type Drawing = { strokes: { Stroke }, holders: { Attachment }, born: number }
type Guide = {
	strokes: { Stroke },
	holders: { Attachment },
	born: number,
	ballId: number,
	fading: number?,
}
-- A guided ball spinning: its turn about the upright on top of the renderer's (the
-- renderer's own frame kept, so nothing piles up), and its streak ring.
type Spinner = {
	angle: number,
	blurAngle: number,
	level: number,
	blur: Part,
	decals: { Decal },
	base: CFrame?,
	written: CFrame?,
}
type Burst = { part: Part, decal: Decal, born: number }

type TableFx = {
	anchor: BasePart,
	chrome: BasePart,
	blur: Part,
	blurDecals: { Decal },
	light: PointLight,
	lightPart: Part,
	trail: Trail,
	trailTop: Attachment,
	trailBottom: Attachment,
	whirr: Sound?,
	faded: { [BasePart]: boolean },
	look: number, -- the steel look's strength, 0..1
	moving: number, -- the rolling look's strength (trail, louder whirr), 0..1
	spinRevs: number, -- the cue ball's spin now, turns a second
	spinAngle: number, -- the chrome's drawn turn about the upright
	blurAngle: number,
	armedKey: number?, -- the armed ult (its at) whose spin-up this is
	spinFrom: number, -- os.clock() the spin-up started
	stillFor: number, -- seconds the shot's cue ball has been still
	clock: number, -- the replay's own time here (slows with /slowmo)
	lastClank: number,
	hitYet: boolean, -- the cue ball has hit a ball this shot (the first plays SteelCall)
	shotSeq: number,
	guided: { [number]: boolean }, -- balls guided in this shot (a pot of one bursts)
	drawings: { Drawing },
	guides: { Guide },
	spinners: { [number]: Spinner },
	bursts: { Burst },
}

export type SteelBallFx = {
	hub: any,
	kit: any,
	tables: { [number]: TableFx },
	consumed: { [number]: number },
}

local SteelBallFx = {}
SteelBallFx.__index = SteelBallFx

--------------------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------------------

-- Make `part` see-through by `amount` (0 solid) without touching its Transparency, which
-- BallRenderer owns; remembered so it is put back.
local function fade(fx: TableFx, part: BasePart?, amount: number)
	if part == nil then
		return
	end
	part.LocalTransparencyModifier = amount
	if amount > 0 then
		fx.faded[part] = true
	else
		fx.faded[part] = nil
	end
end

local function unfadeAll(fx: TableFx)
	for part in fx.faded do
		if part.Parent then
			part.LocalTransparencyModifier = 0
		end
	end
	table.clear(fx.faded)
end

-- A flat ring of motion streaks (the spin blur image on both faces), hidden.
local function streakRing(self: SteelBallFx, id: number, name: string): (Part, { Decal })
	local part = self.kit.part(id, name, { Size = Vector3.new(0.01, 0.002, 0.01) })
	local decals: { Decal } = {}
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local d = Instance.new("Decal")
		d.Face = face
		d.Texture = IMAGES.SteelSpinBlur
		d.Color3 = rgb(F.BlurColor)
		d.Transparency = 1
		d.Parent = part
		table.insert(decals, d)
	end
	return part, decals
end

local function setRing(
	part: Part,
	decals: { Decal },
	at: Vector3,
	angle: number,
	width: number,
	alpha: number
)
	part.Size = Vector3.new(width, 0.002, width)
	part.CFrame = CFrame.new(at) * CFrame.Angles(0, angle, 0)
	for _, d in decals do
		d.Transparency = alpha
	end
end

local function create(self: SteelBallFx, id: number): TableFx
	local kit = self.kit
	local anchor = kit.anchor(id)
	local looks = ReplicatedStorage:FindFirstChild(Config.Ults.Assets.LooksFolder)
	local template = looks and looks:FindFirstChild(EFFECT)
	local chrome: BasePart
	if template and template:IsA("BasePart") then
		chrome = template:Clone()
		chrome.Name = "SteelChrome"
		chrome.Transparency = 1
		chrome.Size = Vector3.one * ballWidth()
		chrome.Parent = anchor
	else
		chrome = kit.part(id, "SteelChrome", {
			Shape = Enum.PartType.Ball,
			Material = Enum.Material.SmoothPlastic,
			Color = rgb(F.ChromeColor),
			Reflectance = F.ChromeReflectance,
			Size = Vector3.one * ballWidth(),
		})
	end
	local blur, blurDecals = streakRing(self, id, "SteelStreaks")
	local lightPart = kit.part(id, "SteelLight", { Transparency = 1 })
	local light = kit.light(lightPart, {
		Color = rgb(F.LightColor),
		Brightness = 0,
		Range = ballWidth() * F.LightRangeBallWidths,
	})
	local top = kit.attachment(id, "SteelTrailTop")
	local bottom = kit.attachment(id, "SteelTrailBottom")
	local trail = Instance.new("Trail")
	trail.Name = "SteelTrail"
	trail.Attachment0 = top
	trail.Attachment1 = bottom
	trail.Color = ColorSequence.new(rgb(F.TrailColor), rgb(F.GoldColor))
	trail.Lifetime = F.TrailSeconds
	trail.MinLength = 0
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Transparency = NumberSequence.new(F.TrailTransparency, 1)
	trail.WidthScale = NumberSequence.new(1, 0.1)
	trail.Enabled = false
	trail.Parent = anchor
	local fx: TableFx = {
		anchor = anchor,
		chrome = chrome,
		blur = blur,
		blurDecals = blurDecals,
		light = light,
		lightPart = lightPart,
		trail = trail,
		trailTop = top,
		trailBottom = bottom,
		whirr = nil,
		faded = {},
		look = 0,
		moving = 0,
		spinRevs = 0,
		spinAngle = 0,
		blurAngle = 0,
		armedKey = nil,
		spinFrom = -math.huge,
		stillFor = 0,
		clock = 0,
		lastClank = -math.huge,
		hitYet = false,
		shotSeq = -1,
		guided = {},
		drawings = {},
		guides = {},
		spinners = {},
		bursts = {},
	}
	self.tables[id] = fx
	return fx
end

-- A sound at `at` (world) for the table.
local function playAt(self: SteelBallFx, id: number, clip: any, at: Vector3, opts: any?): Sound?
	local kit = self.kit
	local holder = kit.attachment(id, "SteelSound", at)
	local sound = kit.sound.library(clip, holder, opts)
	if not (opts and opts.looped) then
		kit.later(id, 5, function()
			holder:Destroy()
		end)
	end
	return sound
end

local function stopWhirr(fx: TableFx)
	local s = fx.whirr
	if s then
		fx.whirr = nil
		local holder = s.Parent
		s:Stop()
		s:Destroy()
		if holder then
			holder:Destroy()
		end
	end
end

-- Sparkles and a burst light at `at`.
local function sparkle(self: SteelBallFx, id: number, at: Vector3, count: number)
	local kit = self.kit
	local holder = kit.attachment(id, "SteelSparkles", at)
	local e = kit.particles(holder, {
		Texture = IMAGES.SteelSparkle,
		Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(F.GoldColor)),
		Size = NumberSequence.new(ballWidth() * F.SparkleBallWidths, 0),
		SpreadAngle = Vector2.new(80, 80),
		Speed = NumberRange.new(0.6, 1.8),
		Drag = 3,
		Lifetime = NumberRange.new(0.3, 0.7),
		Rotation = NumberRange.new(0, 90),
		EmissionDirection = Enum.NormalId.Top,
	})
	e:Emit(count)
	kit.later(id, 1.2, function()
		holder:Destroy()
	end)
	kit.burstLight(
		at + Vector3.yAxis * ballWidth(),
		rgb(F.GoldColor),
		ballWidth() * 6,
		F.FlashBrightness,
		F.FlashSeconds
	)
end

-- A gold burst ring growing flat on the cloth at `at` (world).
local function burst(self: SteelBallFx, id: number, fx: TableFx, at: Vector3)
	local part = self.kit.part(id, "SteelBurst", {
		Size = Vector3.new(0.01, 0.02, 0.01),
		CFrame = CFrame.new(at),
	})
	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Top
	decal.Texture = IMAGES.SteelBurst
	decal.Parent = part
	table.insert(fx.bursts, { part = part, decal = decal, born = fx.clock })
end

local function stepBursts(fx: TableFx)
	local keep = {}
	for _, b in fx.bursts do
		local u = (fx.clock - b.born) / F.BurstSeconds
		if u >= 1 or b.part.Parent == nil then
			b.part:Destroy()
			continue
		end
		local s = ballWidth() * F.BurstBallWidths * (0.2 + 0.8 * easeOut(u))
		b.part.Size = Vector3.new(s, 0.02, s)
		b.decal.Transparency = F.BurstTransparency + (1 - F.BurstTransparency) * u * u
		table.insert(keep, b)
	end
	fx.bursts = keep
end

--------------------------------------------------------------------------------------------
-- Drawn lines (the golden ratio, the guide lines)
--------------------------------------------------------------------------------------------

-- A stroke from `a` to `b` (world, flat on the cloth): straight, or a quarter circle when
-- given the tangents there (`ta`, `tb`, the way the pen runs) and its radius in studs.
local function stroke(
	self: SteelBallFx,
	id: number,
	holders: { Attachment },
	a: Vector3,
	b: Vector3,
	widths: { number },
	from: number,
	to: number,
	ta: Vector3?,
	tb: Vector3?,
	radius: number?
): Stroke
	local kit = self.kit
	local run = b - a
	local along = if run.Magnitude > 1e-6 then run.Unit else Vector3.xAxis
	local t0 = ta or along
	local t1 = tb or along
	-- A beam bends toward its attachments' X axes: each along the pen's way.
	local a0 = kit.attachment(id, "SteelInk", CFrame.fromMatrix(a, t0, Vector3.yAxis))
	local a1 = kit.attachment(id, "SteelInk", CFrame.fromMatrix(b, t1, Vector3.yAxis))
	table.insert(holders, a0)
	table.insert(holders, a1)
	local curve = if radius then radius * QUARTER_HANDLE else 0
	local function beam(width: number, color: { number }): Beam
		return kit.beam(a0, a1, {
			Width0 = width,
			Width1 = width,
			Color = ColorSequence.new(rgb(color)),
			Transparency = NumberSequence.new(1),
			Segments = F.InkSegments,
			CurveSize0 = curve,
			CurveSize1 = curve,
			-- Painted, not added: a glowing yellow over the cyan cloth sums to white.
			LightEmission = F.InkLightEmission,
		})
	end
	local glow = beam(widths[2], F.InkGlowColor)
	local core = beam(widths[1], F.InkCoreColor)
	return { core = core, glow = glow, from = from, to = to }
end

-- How much of a stroke the pen has drawn by `t` (0..1).
local function drawn(s: Stroke, t: number): number
	if s.to <= s.from then
		return if t >= s.from then 1 else 0
	end
	return math.clamp((t - s.from) / (s.to - s.from), 0, 1)
end

-- Show beam `beam` drawn up to `p` (0..1 along it), at see-through `alpha` where drawn.
local function ink(beam: Beam, p: number, alpha: number)
	if p <= 0 or alpha >= 1 then
		beam.Transparency = NumberSequence.new(1)
	elseif p >= 0.97 then
		beam.Transparency = NumberSequence.new(alpha)
	else
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, alpha),
			NumberSequenceKeypoint.new(p, alpha),
			NumberSequenceKeypoint.new(p + 0.02, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
end

local function showStrokes(strokes: { Stroke }, t: number, shown: number)
	for _, s in strokes do
		local p = drawn(s, t)
		ink(s.core, p, 1 - shown)
		ink(s.glow, p, 1 - (1 - F.InkGlowTransparency) * shown)
	end
end

-- The beams hang off the anchor beside their attachments: both go.
local function drop(strokes: { Stroke }, holders: { Attachment })
	for _, s in strokes do
		s.core:Destroy()
		s.glow:Destroy()
	end
	for _, h in holders do
		h:Destroy()
	end
	table.clear(strokes)
	table.clear(holders)
end

-- The golden ratio drawn flat on the cloth: the spiral's eye at `contact` (world), its tail
-- toward `back` (flat, unit: where the cue ball came from).
local function drawGolden(
	self: SteelBallFx,
	id: number,
	fx: TableFx,
	contact: Vector3,
	back: Vector3
)
	local size = ballWidth() * F.SpiralBallWidths -- the rectangle's height
	-- The diagram's axes on the cloth: turned so its tail (0, 0) lies along `back`.
	local tail = Vector2.new(-EYE.X, -EYE.Y).Unit
	local side = Vector3.new(0, 1, 0):Cross(back)
	local u = back * tail.X - side * tail.Y
	local v = back * tail.Y + side * tail.X
	local function at(x: number, y: number): Vector3
		return contact + (u * (x - EYE.X) + v * (y - EYE.Y)) * size
	end
	local function dir(x: number, y: number): Vector3
		return u * x + v * y
	end
	local holders: { Attachment } = {}
	local strokes: { Stroke } = {}
	local squareWidths = { F.SquareCoreStuds, F.SquareGlowStuds }
	local spiralWidths = { F.SpiralCoreStuds, F.SpiralGlowStuds }
	for _, l in OUTLINE do
		table.insert(
			strokes,
			stroke(
				self,
				id,
				holders,
				at(l.x0, l.y0),
				at(l.x1, l.y1),
				squareWidths,
				0,
				F.OutlineDrawSeconds
			)
		)
	end
	-- The pen keeps one speed along the spiral; each square's divider draws with its arc.
	local total = 0
	for _, arc in ARCS do
		total += arc.r
	end
	local done = 0
	for k, arc in ARCS do
		local from = F.SpiralDrawSeconds * done / total
		done += arc.r
		local to = F.SpiralDrawSeconds * done / total
		local a1 = arc.a0 - math.pi / 2
		local p0 = at(arc.cx + arc.r * math.cos(arc.a0), arc.cy + arc.r * math.sin(arc.a0))
		local p1 = at(arc.cx + arc.r * math.cos(a1), arc.cy + arc.r * math.sin(a1))
		-- Clockwise: the way along at angle a is (sin a, -cos a).
		local t0 = dir(math.sin(arc.a0), -math.cos(arc.a0))
		local t1 = dir(math.sin(a1), -math.cos(a1))
		table.insert(
			strokes,
			stroke(self, id, holders, p0, p1, spiralWidths, from, to, t0, t1, arc.r * size)
		)
		local l = DIVIDERS[k]
		table.insert(
			strokes,
			stroke(self, id, holders, at(l.x0, l.y0), at(l.x1, l.y1), squareWidths, from, to)
		)
	end
	table.insert(fx.drawings, { strokes = strokes, holders = holders, born = fx.clock })
end

local function stepDrawings(fx: TableFx)
	local keep = {}
	for _, d in fx.drawings do
		local t = fx.clock - d.born
		local holdEnd = F.SpiralDrawSeconds + F.SpiralHoldSeconds
		local shown = 1 - math.clamp((t - holdEnd) / F.SpiralFadeSeconds, 0, 1)
		if shown <= 0 then
			drop(d.strokes, d.holders)
			continue
		end
		showStrokes(d.strokes, t, shown)
		table.insert(keep, d)
	end
	fx.drawings = keep
end

-- The world points of a guided ball's path from where it is: its steered waypoints (a guided
-- pot) or the straight run to where it stops (a line-up).
local function pathPoints(self: SteelBallFx, m: any, ball: any, ev: any): { Vector3 }
	local kit = self.kit
	local lift = F.GuideLiftInches
	local points = { kit.tableWorld(m, ball.x, ball.y, lift) }
	local steel = m.state.fx and m.state.fx.steel
	if ev.value == 1 and steel then
		for _, g in steel.guided do
			if g.id == ball.id then
				local path = g.path
				for k = g.wp, #path // 2 do
					table.insert(points, kit.tableWorld(m, path[2 * k - 1], path[2 * k], lift))
				end
				return points
			end
		end
	end
	-- Lined up (or no path found): straight on to where rolling friction stops it.
	local v2 = ball.vx * ball.vx + ball.vy * ball.vy
	if v2 > 1e-6 then
		local v = math.sqrt(v2)
		local roll = v2 / (2 * Config.Physics.RollingFriction * Config.Physics.Gravity)
		table.insert(
			points,
			kit.tableWorld(m, ball.x + ball.vx / v * roll, ball.y + ball.vy / v * roll, lift)
		)
	elseif ev.x and ev.y then
		table.insert(points, kit.tableWorld(m, ev.x, ev.y, lift))
	end
	return points
end

-- A guided ball's line ahead of it, drawn at one speed along its legs.
local function layGuide(
	self: SteelBallFx,
	id: number,
	fx: TableFx,
	ballId: number,
	points: { Vector3 }
)
	local total = 0
	for k = 1, #points - 1 do
		total += (points[k + 1] - points[k]).Magnitude
	end
	if total < 1e-3 then
		return
	end
	local holders: { Attachment } = {}
	local strokes: { Stroke } = {}
	local widths = { F.GuideCoreStuds, F.GuideGlowStuds }
	local done = 0
	for k = 1, #points - 1 do
		local a, b = points[k], points[k + 1]
		local len = (b - a).Magnitude
		if len < 1e-3 then
			continue
		end
		local from = F.GuideDrawSeconds * done / total
		done += len
		table.insert(
			strokes,
			stroke(self, id, holders, a, b, widths, from, F.GuideDrawSeconds * done / total)
		)
	end
	table.insert(fx.guides, {
		strokes = strokes,
		holders = holders,
		born = fx.clock,
		ballId = ballId,
		fading = nil,
	})
end

local function stepGuides(self: SteelBallFx, fx: TableFx, m: any)
	local keep = {}
	for _, g in fx.guides do
		local ball = self.kit.ballOf(m, g.ballId)
		local gone = ball == nil
			or ball.pocketed
			or (ball.vx * ball.vx + ball.vy * ball.vy) < 1
			or fx.clock - g.born > F.GuideMaxSeconds
		if gone and g.fading == nil then
			g.fading = fx.clock
		end
		local shown = 1
		if g.fading then
			shown = 1 - math.clamp((fx.clock - g.fading) / F.GuideFadeSeconds, 0, 1)
		end
		if shown <= 0 then
			drop(g.strokes, g.holders)
			continue
		end
		showStrokes(g.strokes, fx.clock - g.born, shown)
		table.insert(keep, g)
	end
	fx.guides = keep
end

--------------------------------------------------------------------------------------------
-- Spinning balls
--------------------------------------------------------------------------------------------

local function startSpinner(self: SteelBallFx, id: number, fx: TableFx, ballId: number)
	if fx.spinners[ballId] then
		fx.spinners[ballId].level = math.max(fx.spinners[ballId].level, 0.01)
		return
	end
	local blur, decals = streakRing(self, id, "SteelBallStreaks" .. ballId)
	fx.spinners[ballId] = {
		angle = 0,
		blurAngle = 0,
		level = 0.01,
		blur = blur,
		decals = decals,
		base = nil,
		written = nil,
	}
end

-- Put a spun ball back to the renderer's own turn, if ours is still the one shown.
local function unspin(self: SteelBallFx, id: number, ballId: number, sp: Spinner)
	local part = self.kit.ballPart(id, ballId)
	if part and sp.written and sp.base and part.CFrame == sp.written then
		part.CFrame = sp.base
	end
	sp.blur:Destroy()
end

local function stepSpinners(self: SteelBallFx, id: number, fx: TableFx, m: any, dt: number)
	local kit = self.kit
	for ballId, sp in fx.spinners do
		local ball = kit.ballOf(m, ballId)
		local part = kit.ballPart(id, ballId)
		local down = ball == nil or ball.pocketed
		local speed = if ball then math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy) else 0
		local going = not down and speed > F.GuidedStillInchesPerSecond
		sp.level = approach(
			sp.level,
			if going then 1 else 0,
			dt,
			if going then F.GuidedSpinInSeconds else F.GuidedSpinDownSeconds
		)
		if down or sp.level <= 0 or part == nil then
			unspin(self, id, ballId, sp)
			fx.spinners[ballId] = nil
			continue
		end
		local p = part :: BasePart
		sp.angle += TAU * F.GuidedSpinRevs * sp.level * dt
		sp.blurAngle += TAU * F.BlurMaxRevs * sp.level * dt
		-- The renderer's frame this frame (it writes only when it moves the ball), then ours.
		if sp.written == nil or p.CFrame ~= sp.written then
			sp.base = p.CFrame
		end
		local base = sp.base :: CFrame
		local cf = CFrame.new(base.Position) * CFrame.Angles(0, sp.angle, 0) * base.Rotation
		p.CFrame = cf
		sp.written = cf
		setRing(
			sp.blur,
			sp.decals,
			base.Position,
			sp.blurAngle,
			p.Size.X * F.GuidedBlurBallWidths,
			1 - (1 - F.BlurTransparency) * sp.level
		)
	end
end

--------------------------------------------------------------------------------------------
-- The cue ball
--------------------------------------------------------------------------------------------

-- Place the steel ball and its streaks on the cue ball's drawn part.
local function placeChrome(fx: TableFx, part: BasePart, dt: number)
	local revs = fx.spinRevs
	-- Drawn turning no faster than the eye follows; past that the streaks carry it. Every spin
	-- turns counter-clockwise seen from above, the way the streak image's comets lead.
	fx.spinAngle += TAU * math.min(revs, F.DrawnMaxRevs) * dt
	fx.blurAngle += TAU * math.min(revs, F.BlurMaxRevs) * dt
	local blurShare = math.clamp((revs - F.BlurFromRevs) / (F.BlurFullRevs - F.BlurFromRevs), 0, 1)
	local d = part.Size.X * F.ChromeScale
	local frame = CFrame.new(part.Position)
		* CFrame.Angles(0, fx.spinAngle, 0)
		* part.CFrame.Rotation
	local trans = 1 - fx.look
	fx.chrome.Size = Vector3.one * d
	fx.chrome.CFrame = frame
	fx.chrome.Transparency = trans
	setRing(
		fx.blur,
		fx.blurDecals,
		part.Position,
		fx.blurAngle,
		part.Size.X * F.BlurBallWidths,
		1 - (1 - F.BlurTransparency) * blurShare * fx.look
	)
end

local function hideChrome(fx: TableFx)
	fx.chrome.Transparency = 1
	for _, d in fx.blurDecals do
		d.Transparency = 1
	end
end

local function destroy(self: SteelBallFx, id: number)
	local fx = self.tables[id]
	if fx == nil then
		return
	end
	self.tables[id] = nil
	unfadeAll(fx)
	stopWhirr(fx)
	for ballId, sp in fx.spinners do
		unspin(self, id, ballId, sp)
	end
	for _, d in fx.drawings do
		drop(d.strokes, d.holders)
	end
	for _, g in fx.guides do
		drop(g.strokes, g.holders)
	end
	for _, b in fx.bursts do
		b.part:Destroy()
	end
	fx.chrome:Destroy()
	fx.blur:Destroy()
	fx.lightPart:Destroy()
	fx.trail:Destroy()
	fx.trailTop:Destroy()
	fx.trailBottom:Destroy()
end

-- The replay's events for a Steel Ball shot at this table.
local function onEvent(self: SteelBallFx, id: number, fx: TableFx, m: any, ev: any)
	local kit = self.kit
	local quiet = m.state.time - ev.t > F.FreshSeconds
	if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
		local cue = kit.ballOf(m, 0)
		local first = not fx.hitYet
		fx.hitYet = true
		if cue and not quiet and first then
			-- The first hit: the activation's clip again (the designer, 2026-09-30).
			fx.lastClank = fx.clock
			playAt(self, id, A.SteelCall, kit.ballWorld(m, cue))
		elseif cue and not quiet and fx.clock - fx.lastClank > F.ClankGapSeconds then
			fx.lastClank = fx.clock
			playAt(self, id, A.SteelClank, kit.ballWorld(m, cue), {
				volume = math.clamp(0.5 + (ev.speed or 0) / F.ClankFullSpeed, 0.5, 1.4),
			})
		end
	elseif ev.type == "pocket" and fx.guided[ev.ball] then
		fx.guided[ev.ball] = nil
		local pocket = kit.pocketOf(m, ev.other)
		local at = if pocket then kit.tableWorld(m, pocket.x, pocket.y, F.GuideLiftInches) else nil
		if at then
			burst(self, id, fx, at)
			sparkle(self, id, at, F.PotSparks)
			if not quiet then
				playAt(self, id, A.SteelPot, at)
			end
		end
	elseif ev.type == "ult" then
		local ball = kit.ballOf(m, ev.ball)
		if ev.kind == "steel" and ball then
			local at = kit.ballWorld(m, ball)
			sparkle(self, id, at, F.SteelSparks)
			-- The golden ratio: its eye where the two met, its tail back toward the cue ball.
			local cue = kit.ballOf(m, 0)
			local cx, cy = ball.x, ball.y
			local back = Vector3.xAxis
			if cue then
				cx, cy = (ball.x + cue.x) / 2, (ball.y + cue.y) / 2
				local here = kit.tableWorld(m, ball.x, ball.y, 0)
				local there = kit.tableWorld(m, cue.x, cue.y, 0)
				local flat = Vector3.new(there.X - here.X, 0, there.Z - here.Z)
				if flat.Magnitude > 1e-6 then
					back = flat.Unit
				end
			end
			if not quiet then
				drawGolden(self, id, fx, kit.tableWorld(m, cx, cy, F.SpiralLiftInches), back)
				playAt(self, id, A.SteelSpiral, at)
				if kit.screen.involved(self.hub, id) then
					kit.screen.shake(id, F.ShakeStuds, F.ShakeSeconds)
				end
			end
		elseif ev.kind == "guide" and ball then
			if ev.value == 1 then
				fx.guided[ev.ball] = true
			end
			startSpinner(self, id, fx, ev.ball)
			layGuide(self, id, fx, ev.ball, pathPoints(self, m, ball, ev))
		end
	end
end

--- Start the look for the tables `hub` holds; `kit` is AbilityFx's.
function SteelBallFx.start(hub: any, _parent: Instance, kit: any): SteelBallFx
	local self: SteelBallFx = setmetatable({
		hub = hub,
		kit = kit,
		tables = {},
		consumed = {},
	}, SteelBallFx) :: any
	kit.onRelease(function(tableId: number)
		local fx = self.tables[tableId]
		if fx then
			unfadeAll(fx) -- the balls are not under the anchor: put them back
			for ballId, sp in fx.spinners do
				unspin(self, tableId, ballId, sp)
			end
			stopWhirr(fx)
		end
		self.tables[tableId] = nil -- its parts went with the anchor
	end)
	kit.allEvents(function(tableId: number, m: any, ev: any, _index: number)
		if not kit.isShotOf(m, EFFECT) or m.renderer == nil then
			return
		end
		local fx = self.tables[tableId]
		if fx == nil or fx.shotSeq ~= m.seq then
			return -- the update below has not met this shot yet
		end
		onEvent(self, tableId, fx, m, ev)
	end)
	task.spawn(function()
		local list: { Instance } = {}
		for _, clip in
			{ A.SteelCall, A.SteelWhirr, A.SteelClank, A.SteelPot, A.SteelSpinUp, A.SteelSpiral }
		do
			local sound = Instance.new("Sound")
			sound.SoundId = clip.Id
			table.insert(list, sound)
		end
		for _, key in { "SteelSpinBlur", "SteelBurst", "SteelSparkle" } do
			local decal = Instance.new("Decal")
			decal.Texture = IMAGES[key]
			table.insert(list, decal)
		end
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, item in list do
			item:Destroy()
		end
	end)
	return self
end

--- The arming moment at table `tableId`: the activation's clip and a gold sparkle.
function SteelBallFx.arming(self: SteelBallFx, tableId: number, armed: any)
	local ult = Catalog.get(armed and armed.id)
	local m = self.hub:matchFor(tableId)
	if ult == nil or ult.Effect ~= EFFECT or m == nil or m.renderer == nil then
		return
	end
	local cue = m:findCueBall()
	if cue == nil then
		return
	end
	local at = self.kit.ballWorld(m, cue)
	playAt(self, tableId, A.SteelCall, at)
	sparkle(self, tableId, at, F.ArmSparks)
end

--- Every frame, after the hub has stepped the replays.
function SteelBallFx.update(self: SteelBallFx, dt: number)
	local now = workspace:GetServerTimeNow()
	local kit = self.kit
	for id, m in self.hub.matches do
		local fx = self.tables[id]
		if m.renderer == nil then
			if fx then
				destroy(self, id)
			end
			continue
		end
		local armed = kit.armedOf(self.hub.snapshots[id], EFFECT)
		local shot = kit.isShotOf(m, EFFECT)
		if shot and armed then
			self.consumed[id] = armed.at -- this shot spends it: the armed look never returns
		end
		local cue = m:findCueBall()
		local wantArmed = armed ~= nil
			and self.consumed[id] ~= armed.at
			and not m:isBusy()
			and (armed.stage == "Armed" or now >= (armed.readyAt or math.huge))
		local steel = wantArmed or (shot and cue ~= nil and not cue.pocketed)
		if fx == nil then
			if not steel then
				continue
			end
			fx = create(self, id)
		end
		local live = fx :: TableFx
		live.clock += dt * (if type(m.timeScale) == "number" then m.timeScale else 1)
		if shot and live.shotSeq ~= m.seq then
			live.shotSeq = m.seq
			live.hitYet = false
			live.stillFor = 0
			table.clear(live.guided)
		end
		live.look = approach(
			live.look,
			if steel then 1 else 0,
			dt,
			if steel then F.FadeInSeconds else F.FadeOutSeconds
		)
		local part = kit.ballPart(id, 0)
		fade(live, part, live.look)

		-- The rolling: how fast the cue ball goes now.
		local speed = 0
		if shot and cue and not cue.pocketed then
			local here = kit.tableWorld(m, cue.x, cue.y, 0)
			local ahead = kit.tableWorld(m, cue.x + cue.vx, cue.y + cue.vy, 0)
			speed = (ahead - here).Magnitude
				* (if type(m.timeScale) == "number" then m.timeScale else 1)
		end
		local rolling = speed > kit.studs(F.RollingInchesPerSecond)
		live.moving = approach(live.moving, if rolling then 1 else 0, dt, F.MovingFadeSeconds)

		-- The spin: up from the look's first armed frame (a late look starts at full spin), held
		-- through the shot while it rolls, then easing off.
		if wantArmed and armed and live.armedKey ~= armed.at then
			live.armedKey = armed.at
			local late = now - (armed.readyAt or now) > F.SpinUpSeconds
			live.spinFrom = if late then os.clock() - F.SpinUpSeconds else os.clock()
			if not late and part then
				playAt(self, id, A.SteelSpinUp, part.Position)
			end
		end
		if wantArmed then
			local u = math.clamp((os.clock() - live.spinFrom) / F.SpinUpSeconds, 0, 1)
			live.spinRevs = F.ArmedSpinRevs * u * u
		elseif shot then
			live.stillFor = if rolling then 0 else live.stillFor + dt
			live.spinRevs = F.ArmedSpinRevs
				* (1 - math.clamp(live.stillFor / F.SpinDownSeconds, 0, 1))
		else
			live.spinRevs = approach(live.spinRevs, 0, dt, F.SpinDownSeconds / F.ArmedSpinRevs)
		end

		if part and live.look > 0.001 then
			placeChrome(live, part, dt)
			live.lightPart.CFrame = CFrame.new(part.Position + Vector3.yAxis * ballWidth())
			live.light.Brightness = F.LightBrightness * live.look
			local h = ballWidth() * F.TrailBallWidths / 2
			live.trailTop.WorldPosition = part.Position + Vector3.yAxis * h
			live.trailBottom.WorldPosition = part.Position - Vector3.yAxis * h
		else
			hideChrome(live)
			live.light.Brightness = 0
		end
		live.trail.Enabled = rolling and part ~= nil and live.look > 0.5

		-- The hum: a spinning top's while it spins armed, louder and higher as it rolls (a quiet
		-- replay catch-up plays none).
		local spinShare = math.clamp(live.spinRevs / F.ArmedSpinRevs, 0, 1)
		local share = math.clamp(speed / kit.studs(F.WhirrFullInchesPerSecond), 0, 1)
		local hum = if wantArmed then F.ArmedHumShare * spinShare else 0
		if shot and live.moving > 0.05 then
			hum = math.max(hum, live.moving * (0.4 + 0.6 * share))
		end
		hum *= live.look
		if hum > 0.01 and live.whirr == nil and part then
			live.whirr =
				playAt(self, id, A.SteelWhirr, part.Position, { looped = true, volume = 0 })
		elseif hum <= 0.01 then
			stopWhirr(live)
		end
		local w = live.whirr
		if w and part then
			local holder = w.Parent
			if holder and holder:IsA("Attachment") then
				holder.WorldPosition = part.Position
			end
			w.Volume = A.SteelWhirr.Volume * hum
			w.PlaybackSpeed = (A.SteelWhirr.Pitch or 1) * (0.6 + 0.4 * spinShare + 0.3 * share)
		end

		stepSpinners(self, id, live, m, dt)
		stepDrawings(live)
		stepGuides(self, live, m)
		stepBursts(live)
		local busy = #live.drawings > 0
			or #live.guides > 0
			or #live.bursts > 0
			or next(live.spinners) ~= nil
		if not steel and live.look <= 0.001 and not busy then
			destroy(self, id)
		end
	end
end

--- Remove every effect at once.
function SteelBallFx.clear(self: SteelBallFx)
	for id in self.tables do
		destroy(self, id)
	end
end

return SteelBallFx
