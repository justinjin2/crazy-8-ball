--!strict
-- CuePreviewMath: the Cue Preview's pure maths (R7; hw-gui lane): where every piece of the panel
-- goes, a camera that puts the stage's focus at the WINDOW's centre (not the screen's), and the
-- stroke -> roll -> pocket -> finisher loop as a timeline. No Instances and no Roblox types
-- (vectors are { x, y, z } tables), so tests/cue_preview_math_test.luau runs it in Lune.
--
-- The panel (mock PREV1_cue_preview): a header band across the top (the title, the red X), the
-- window on the left (a transparent hole the real 3D view shows through), the info sheet on the
-- right (the name, the rarity pill, the note, the three tabs in a row, EQUIP). Rects are
-- { x, y, w, h } in the menu screen's pixels (under Roblox's top bar).
--
-- Also the decisions with no Instance in them: which cues may open it (allowed), the tab it
-- opens on (tabOf), how high and wide a skin's pocket finisher reaches and how long it lasts
-- (finisherReach), how long a cue is as drawn (cueSpan: a body past the butt, its 3D piece) and
-- the camera distance that keeps a set of points in the window all round the orbit
-- (fitDistance).
local Config = require(script.Parent.Config)

local C = Config.UI.CuePreview
local L = C.Layout
local F = C.Fit

export type Rect = { x: number, y: number, w: number, h: number }
export type Vec = { x: number, y: number, z: number }
-- A finisher's reach: `top` studs over the pocket, `radius` out from it, `seconds` long.
export type Reach = { top: number, radius: number, seconds: number }
-- A cue as drawn, along it from its tip (studs): `from` (below 0: past the tip) to `to` (the
-- butt, or a body reaching past it), and `across`, the farthest anything sits off its axis.
export type Span = { from: number, to: number, across: number }

export type Panel = {
	panel: Rect,
	header: Rect,
	title: Rect,
	close: Rect,
	window: Rect,
	sheet: Rect,
	name: Rect,
	pill: Rect,
	note: Rect,
	tabs: { Rect }, -- MODEL, TRAIL, FINISHER
	equip: Rect,
	hint: Rect, -- "Drag to rotate", along the window's foot
	short: boolean,
}

local CuePreviewMath = {}

--- The tabs, in their row's order.
CuePreviewMath.Tabs = { "Model", "Trail", "Finisher" }

local function round(x: number): number
	return math.floor(x + 0.5)
end

--- Whether the preview may open on cue `id` under the switches `cfg` (Config.UI.CuePreview):
--- every cue while Enabled; with Enabled off, only the cues Event.Cues lists while
--- Event.Enabled (the Halloween cards' PREVIEW, designer 2026-10-29). Whether `id` is a
--- catalog cue is the caller's to check.
function CuePreviewMath.allowed(cfg: any, id: any): boolean
	if type(id) ~= "string" or type(cfg) ~= "table" then
		return false
	end
	if cfg.Enabled == true then
		return true
	end
	local event = cfg.Event
	return type(event) == "table"
		and event.Enabled == true
		and type(event.Cues) == "table"
		and table.find(event.Cues, id) ~= nil
end

--- The tab to open on: `name` when it is one ("Model", "Trail", "Finisher"), else MODEL.
function CuePreviewMath.tabOf(name: any): string
	return if type(name) == "string" and table.find(CuePreviewMath.Tabs, name)
		then name
		else "Model"
end

--- Every rect of the panel on a screen of `w` x `h` pixels.
function CuePreviewMath.panel(screen: { w: number, h: number }): Panel
	local short = screen.h < Config.Multiplayer.Style.ShortHeight
	local w = math.min(round(screen.w * L.WidthShare), L.MaxWidthPx)
	local h = math.min(round(screen.h * L.HeightShare), round(w * L.MaxAspect))
	local x = round((screen.w - w) / 2)
	local y = round((screen.h - h) / 2)
	local headerH = if short then L.ShortHeaderPx else L.HeaderPx
	local pad = if short then L.ShortPadPx else L.PadPx
	local gap = if short then L.ShortGapPx else L.GapPx
	local closePx = headerH - 2 * L.CloseInsetPx
	local header = { x = x, y = y, w = w, h = headerH }
	local close =
		{ x = x + w - L.CloseInsetPx - closePx, y = y + L.CloseInsetPx, w = closePx, h = closePx }
	local title = { x = x + pad, y = y, w = close.x - gap - (x + pad), h = headerH }
	local bodyY = y + headerH + pad
	local bodyH = h - headerH - 2 * pad
	local share = if short then C.ShortWindowShare else C.WindowShare
	local windowW = round((w - 2 * pad - gap) * share)
	local window = { x = x + pad, y = bodyY, w = windowW, h = bodyH }
	local sheetX = window.x + windowW + gap
	local sheet = { x = sheetX, y = bodyY, w = x + w - pad - sheetX, h = bodyH }
	-- The sheet, top down: name, pill, note; EQUIP at the foot; the tabs just over it.
	local inner = sheet.w - 2 * L.SheetPadPx
	local sx = sheet.x + L.SheetPadPx
	local nameH = if short then L.ShortNamePx else L.NamePx
	local pillH = if short then L.ShortPillPx else L.PillPx
	local noteH = if short then L.ShortNotePx else L.NotePx
	local hitH = math.max(C.MinHitPx, if short then L.ShortButtonPx else L.ButtonPx)
	local sy = sheet.y + L.SheetPadPx
	local name = { x = sx, y = sy, w = inner, h = nameH }
	sy += nameH + gap
	local pillW = math.min(inner, round(pillH * L.PillAspect))
	local pill = { x = sx, y = sy, w = pillW, h = pillH }
	sy += pillH + gap
	local note = { x = sx, y = sy, w = inner, h = noteH }
	local equip = { x = sx, y = sheet.y + sheet.h - L.SheetPadPx - hitH, w = inner, h = hitH }
	local tabsY = equip.y - gap - hitH
	local tabW = (inner - 2 * L.TabGapPx) / 3
	local tabs = {}
	for i = 1, 3 do
		table.insert(tabs, {
			x = round(sx + (i - 1) * (tabW + L.TabGapPx)),
			y = tabsY,
			w = math.floor(tabW),
			h = hitH,
		})
	end
	local hintH = if short then L.ShortHintPx else L.HintPx
	local hint =
		{ x = window.x, y = window.y + window.h - hintH - L.HintInsetPx, w = window.w, h = hintH }
	return {
		panel = { x = x, y = y, w = w, h = h },
		header = header,
		title = title,
		close = close,
		window = window,
		sheet = sheet,
		name = name,
		pill = pill,
		note = note,
		tabs = tabs,
		equip = equip,
		hint = hint,
		short = short,
	}
end

local function add(a: Vec, b: Vec): Vec
	return { x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }
end
local function scale(a: Vec, k: number): Vec
	return { x = a.x * k, y = a.y * k, z = a.z * k }
end
local function cross(a: Vec, b: Vec): Vec
	return { x = a.y * b.z - a.z * b.y, y = a.z * b.x - a.x * b.z, z = a.x * b.y - a.y * b.x }
end
local function unit(a: Vec): Vec
	local m = math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
	return if m > 0 then scale(a, 1 / m) else { x = 0, y = 0, z = -1 }
end

--- The camera's basis looking from `eye` to `target`: right, up, forward (Roblox's: Y up).
function CuePreviewMath.basis(eye: Vec, target: Vec): (Vec, Vec, Vec)
	local forward = unit(add(target, scale(eye, -1)))
	local right = unit(cross(forward, { x = 0, y = 1, z = 0 }))
	local up = cross(right, forward)
	return right, up, forward
end

--- A camera orbiting `focus` at `distance`, `yaw` and `pitch` degrees, that shows `focus` at
--- `at` (viewport pixels: the window's centre) instead of the viewport's centre: the camera
--- slides sideways in its own plane, so the view keeps its angle. `fovDeg` is the vertical
--- field of view (Roblox's). Returns the eye and the point it looks at.
function CuePreviewMath.camera(
	focus: Vec,
	yaw: number,
	pitch: number,
	distance: number,
	fovDeg: number,
	viewport: { w: number, h: number },
	at: { x: number, y: number }
): (Vec, Vec)
	local yawR, pitchR = math.rad(yaw), math.rad(pitch)
	local dir = {
		x = math.cos(pitchR) * math.sin(yawR),
		y = math.sin(pitchR),
		z = math.cos(pitchR) * math.cos(yawR),
	}
	local eye = add(focus, scale(dir, distance))
	local right, up = CuePreviewMath.basis(eye, focus)
	-- World units per pixel at the focus's depth.
	local perPx = 2 * distance * math.tan(math.rad(fovDeg) / 2) / viewport.h
	local dx = at.x - viewport.w / 2
	local dy = at.y - viewport.h / 2
	local shift = add(scale(right, -dx * perPx), scale(up, dy * perPx))
	return add(eye, shift), add(focus, shift)
end

--- Where world point `p` lands on the viewport (pixels) for a camera at `eye` looking at
--- `target` (the pinhole model Roblox uses), and its depth.
function CuePreviewMath.project(
	p: Vec,
	eye: Vec,
	target: Vec,
	fovDeg: number,
	viewport: { w: number, h: number }
): ({ x: number, y: number }, number)
	local right, up, forward = CuePreviewMath.basis(eye, target)
	local d = add(p, scale(eye, -1))
	local depth = d.x * forward.x + d.y * forward.y + d.z * forward.z
	local k = viewport.h / (2 * math.tan(math.rad(fovDeg) / 2))
	local sx = (d.x * right.x + d.y * right.y + d.z * right.z) / depth * k
	local sy = (d.x * up.x + d.y * up.y + d.z * up.z) / depth * k
	return { x = viewport.w / 2 + sx, y = viewport.h / 2 - sy }, depth
end

export type Phase = { name: string, from: number, to: number }

--- One loop of a tab, as named phases with their start and end seconds. TRAIL: back, hit,
--- roll, drop, finisher, gap. FINISHER: the last FinisherRollShare of the roll, drop, finisher,
--- gap. `finisherSeconds`: the cue's finisher length (nil: FinisherHoldSeconds).
function CuePreviewMath.timeline(tab: string, finisherSeconds: number?): { Phase }
	local hold = if type(finisherSeconds) == "number" and finisherSeconds > 0
		then finisherSeconds
		else C.FinisherHoldSeconds
	local steps: { { any } }
	if tab == "Finisher" then
		steps = {
			{ "roll", C.RollSeconds * C.FinisherRollShare },
			{ "drop", C.DropSeconds },
			{ "finisher", hold },
			{ "gap", C.GapSeconds },
		}
	else
		steps = {
			{ "back", C.StrokeBackSeconds },
			{ "hit", C.StrokeHitSeconds },
			{ "roll", C.RollSeconds },
			{ "drop", C.DropSeconds },
			{ "finisher", hold },
			{ "gap", C.GapSeconds },
		}
	end
	local out: { Phase } = {}
	local t = 0
	for _, step in steps do
		table.insert(out, { name = step[1], from = t, to = t + step[2] })
		t += step[2]
	end
	return out
end

--- The phase at `t` seconds into a loop (wrapped), and how far through it (0..1).
function CuePreviewMath.phaseAt(timeline: { Phase }, t: number): (string, number)
	local total = timeline[#timeline].to
	local at = if total > 0 then t % total else 0
	for _, phase in timeline do
		if at < phase.to then
			local span = phase.to - phase.from
			return phase.name, if span > 0 then (at - phase.from) / span else 1
		end
	end
	local last = timeline[#timeline]
	return last.name, 1
end

--- How far the roll has gone (0..1 of the whole roll) at a roll phase's `progress`, for a tab:
--- FINISHER rolls only its last FinisherRollShare.
function CuePreviewMath.rollShare(tab: string, progress: number): number
	local p = math.clamp(progress, 0, 1)
	if tab == "Finisher" then
		return 1 - C.FinisherRollShare + C.FinisherRollShare * p
	end
	return p
end

--- An ease-out for the roll (the ball slows into the pocket).
function CuePreviewMath.easeOut(t: number): number
	local x = math.clamp(t, 0, 1)
	return 1 - (1 - x) * (1 - x)
end

local function smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

--- TRAIL's camera between its two framings, 0 (the stroke and the roll) to 1 (the finisher
--- over the pocket), at `progress` (0..1) through the loop's phase `phase`: it eases over as
--- the ball nears the pocket (from Fit.FollowFrom of the roll's time), holds on the finisher
--- and eases back during the gap, before the next stroke.
function CuePreviewMath.follow(phase: string?, progress: number?): number
	local p = if type(progress) == "number" then progress else 0
	if phase == "roll" then
		return smooth((p - F.FollowFrom) / (1 - F.FollowFrom))
	elseif phase == "drop" or phase == "finisher" then
		return 1
	elseif phase == "gap" then
		return 1 - smooth(p)
	end
	return 0
end

--- The auto-turn and drag: the next yaw and spin after `dt` seconds. `spin` (degrees a second)
--- decays by SpinDecay; with no spin left and the idle wait over, it turns at TurnDegPerSecond.
--- `still` (Reduce Motion): the view never turns on its own, no auto-turn and no flick's spin
--- (a drag or the stick still turn it, through their own code).
function CuePreviewMath.turn(
	yaw: number,
	spin: number,
	idle: number,
	dt: number,
	still: boolean?
): (number, number)
	if still then
		return yaw % 360, 0
	end
	local decayed = spin * math.exp(-C.SpinDecay * dt)
	if math.abs(decayed) < 1 then
		decayed = 0
	end
	local auto = if idle >= C.IdleResumeSeconds and decayed == 0 then C.TurnDegPerSecond else 0
	return (yaw + (decayed + auto) * dt) % 360, decayed
end

--- A drag's new pitch, clamped to PitchMinDeg..PitchMaxDeg.
function CuePreviewMath.pitch(pitch: number, deltaDeg: number): number
	return math.clamp(pitch + deltaDeg, C.PitchMinDeg, C.PitchMaxDeg)
end

-- The largest value a skin row's number, range ({ min, max }) or keypoint list ({ { t, v } })
-- reaches; `default` when it is none of them.
local function largest(v: any, default: number): number
	if type(v) == "number" then
		return v
	end
	if type(v) ~= "table" then
		return default
	end
	local best: number? = nil
	for _, k in v do
		local x = if type(k) == "table" then k[2] else k
		if type(x) == "number" then
			best = if best then math.max(best, x) else x
		end
	end
	return best or default
end

--- How high a particle fired straight up climbs (studs) at `speed` studs a second, with Roblox's
--- Drag `drag` (its speed halves every 1/drag seconds) and an upward acceleration `lift`, over
--- `life` seconds: its highest point. Stepped at 30 a second (deterministic).
function CuePreviewMath.climb(speed: number, drag: number, lift: number, life: number): number
	local dt = 1 / 30
	local decay = 2 ^ (-math.max(drag, 0) * dt)
	local v, y, peak = speed, 0, 0
	for _ = 1, math.ceil(math.clamp(life, 0, F.MaxLifeSeconds) / dt) do
		v = v * decay + lift * dt
		y += v * dt
		peak = math.max(peak, y)
	end
	return peak
end

--- How far a skin's pocket finisher reaches (CueSkins row's Pocket: Layers, Rings, Piece):
--- `top` studs over the pocket and `radius` out from it, clamped to Fit.TopStuds and
--- Fit.RadiusStuds, and how many `seconds` it lasts (0 with no finisher). `piece` is the row of
--- its 3D creature (CueSkins.piece of Pocket.Piece.Piece), or nil. Rough on purpose, and only
--- from the data, so a rebuilt finisher frames itself: a layer's sprites at its host's height
--- (SpriteShare of their largest size), a narrow fountain carried up by its speed, drag and
--- lift (ClimbShare of the climb: its particles fade near the top); the creature at its rise,
--- grown to its largest scale.
function CuePreviewMath.finisherReach(pocket: any?, piece: any?): Reach
	local top, radius, seconds = 0, 0, 0
	if type(pocket) == "table" then
		for _, layer in pocket.Layers or {} do
			local host = layer.Host or {}
			local o = host.Offset or { 0, 0, 0 }
			local life = math.min(largest(layer.Lifetime, 1), F.MaxLifeSeconds)
			seconds = math.max(seconds, (layer.Delay or 0) + life)
			local half = largest(layer.Size, 1) * F.SpriteShare / 2
			local rise = 0
			local spread = largest(layer.SpreadAngle, 0)
			local fountain = (layer.EmissionDirection or "Top") == "Top"
				and spread < F.FountainDegrees
				and largest(layer.Size, 1) >= F.SparkStuds -- sparks fly high but read small
			if fountain then
				local acc = layer.Acceleration
				local lift = if type(acc) == "table" then acc[2] or 0 else 0
				rise = CuePreviewMath.climb(largest(layer.Speed, 1), layer.Drag or 0, lift, life)
					* F.ClimbShare
			end
			top = math.max(top, (o[2] or 0) + rise + half)
			local out = math.sqrt((o[1] or 0) ^ 2 + (o[3] or 0) ^ 2) + (host.Size or 0) / 2 + half
			radius = math.max(radius, out)
		end
		for _, ring in pocket.Rings or {} do
			seconds = math.max(seconds, (ring.Delay or 0) + (ring.Seconds or 0.45))
		end
		local p = pocket.Piece
		if type(p) == "table" then
			seconds = math.max(seconds, (p.Delay or 0.1) + (p.Seconds or 1.3))
			if type(piece) == "table" then
				local high, wide = 0, 0
				for _, part in piece.Parts or {} do
					local po, ps = part.Offset, part.Size
					if type(po) == "table" and type(ps) == "table" then
						high = math.max(high, po[2] + ps[2] / 2)
						wide = math.max(
							wide,
							math.sqrt(po[1] ^ 2 + po[3] ^ 2) + math.max(ps[1], ps[3]) / 2
						)
					end
				end
				local grown = largest(p.Scale, 1.05)
				top = math.max(top, largest(p.Rise, 0.4) + high * grown)
				radius = math.max(radius, wide * grown)
			end
		end
	end
	return {
		top = math.clamp(top, F.TopStuds[1], F.TopStuds[2]),
		radius = math.clamp(radius, F.RadiusStuds[1], F.RadiusStuds[2]),
		seconds = seconds,
	}
end

--- How long the loop holds a finisher of `seconds` (finisherReach): its own length, never
--- shorter than FinisherHoldSeconds (the game's pace for a plain burst), at most
--- FinisherMaxSeconds.
function CuePreviewMath.holdSeconds(seconds: number?): number
	local s = if type(seconds) == "number" then seconds else 0
	return math.clamp(s, C.FinisherHoldSeconds, C.FinisherMaxSeconds)
end

--- A cue as drawn (Span, studs along it from the tip): the shared stick of `length`
--- (Config.Cue.CueLengthStuds) and the CueSkins.piece `rows` drawn on it in the cue frame (its
--- body, its 3D piece), whose parts sit at Offset in the cue mesh's frame (the tip at
--- +length/2, the butt at -length/2, Z along the cue) and are Size big. Rows in another frame (a
--- pocket creature) are skipped.
function CuePreviewMath.cueSpan(length: number, rows: { any }): Span
	local half = length / 2
	local front, back, across = half, -half, 0
	for _, row in rows do
		if type(row) == "table" and (row.Frame == nil or row.Frame == "cue") then
			for _, part in row.Parts or {} do
				local o, s = part.Offset, part.Size
				if type(o) == "table" and type(s) == "table" then
					front = math.max(front, o[3] + s[3] / 2)
					back = math.min(back, o[3] - s[3] / 2)
					across =
						math.max(across, math.sqrt(o[1] ^ 2 + o[2] ^ 2) + math.max(s[1], s[2]) / 2)
				end
			end
		end
	end
	return { from = half - front, to = half - back, across = math.max(across, F.CueAcrossStuds) }
end

local function dot(a: Vec, b: Vec): number
	return a.x * b.x + a.y * b.y + a.z * b.z
end

--- The least distance for CuePreviewMath.camera (same `focus`, `pitch`, `fovDeg`, `viewport`
--- and window centre `at`) at which every one of `points` shows inside the window, `half` its
--- half size in pixels (any margin already taken off), at every yaw of the orbit checked every
--- `yawStep` degrees. Closed form per point, the camera's sideways slide included (a point
--- nearer or farther than the focus shifts against the off-centre window), so it is cheap to
--- run whenever the tab, the cue or the screen changes. Never under Fit.NearStuds in front of
--- any point.
function CuePreviewMath.fitDistance(
	points: { Vec },
	focus: Vec,
	pitch: number,
	fovDeg: number,
	viewport: { w: number, h: number },
	at: { x: number, y: number },
	half: { w: number, h: number },
	yawStep: number
): number
	local k = viewport.h / (2 * math.tan(math.rad(fovDeg) / 2))
	local dx = at.x - viewport.w / 2
	local dy = at.y - viewport.h / 2
	local hw, hh = math.max(half.w, 1), math.max(half.h, 1)
	local pitchR = math.rad(pitch)
	local step = math.max(yawStep, 1)
	local best = 0
	local yaw = 0
	while yaw < 360 do
		local yawR = math.rad(yaw)
		local dir = {
			x = math.cos(pitchR) * math.sin(yawR),
			y = math.sin(pitchR),
			z = math.cos(pitchR) * math.cos(yawR),
		}
		local right, up, forward = CuePreviewMath.basis(add(focus, dir), focus)
		for _, p in points do
			local q = add(p, scale(focus, -1))
			local x, y, z = dot(q, right), dot(q, up), dot(q, forward)
			local need = math.max(math.abs(x * k - dx * z) / hw, math.abs(y * k + dy * z) / hh) - z
			best = math.max(best, need, F.NearStuds - z)
		end
		yaw += step
	end
	return best
end

return CuePreviewMath
