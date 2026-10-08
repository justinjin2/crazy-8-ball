--!strict
-- StageMath: the pure maths of lively screens (docs/prompts/SHOP_LIVELY_PROMPT.md sections 3 and
-- 4), in plain numbers so Lune can check it: Roblox's easing curves, the reveal curves (pop,
-- unroll, slam, drop, grow, fade), a screen's open schedule from Config (Config.UI.Shop.Open),
-- flipbook frames, the smooth-motion windows of gate 1 (a scroll inside a 2 x 2 tile, a float
-- split into whole pixels and a fraction, a breathe inside a clear border) and the time-left
-- text. client/Stage and UIAnim put these numbers on Instances. Seconds; shares 0..1.
local StageMath = {}

local function clamp01(p: number): number
	return math.clamp(p, 0, 1)
end

local function bounceOut(p: number): number
	local n, d = 7.5625, 2.75
	if p < 1 / d then
		return n * p * p
	elseif p < 2 / d then
		p -= 1.5 / d
		return n * p * p + 0.75
	elseif p < 2.5 / d then
		p -= 2.25 / d
		return n * p * p + 0.9375
	end
	p -= 2.625 / d
	return n * p * p + 0.984375
end

-- Each style's "In" curve, as TweenService's (Back with s = 1.70158).
local IN: { [string]: (number) -> number } = {
	Linear = function(p)
		return p
	end,
	Sine = function(p)
		return 1 - math.cos(p * math.pi / 2)
	end,
	Quad = function(p)
		return p * p
	end,
	Cubic = function(p)
		return p * p * p
	end,
	Quart = function(p)
		return p ^ 4
	end,
	Quint = function(p)
		return p ^ 5
	end,
	Exponential = function(p)
		return if p == 0 then 0 else 2 ^ (10 * p - 10)
	end,
	Circular = function(p)
		return 1 - math.sqrt(1 - p * p)
	end,
	Back = function(p)
		return p * p * (2.70158 * p - 1.70158)
	end,
	Elastic = function(p)
		if p == 0 or p == 1 then
			return p
		end
		return -(2 ^ (10 * p - 10)) * math.sin((p * 10 - 10.75) * (2 * math.pi / 3))
	end,
	Bounce = function(p)
		return 1 - bounceOut(1 - p)
	end,
}

--- `style` (an Enum.EasingStyle name) in `direction` ("In", "Out" or "InOut") at `p` (0..1).
function StageMath.ease(style: string, direction: string, p: number): number
	local f = IN[style] or IN.Linear
	p = clamp01(p)
	if direction == "In" then
		return f(p)
	elseif direction == "Out" then
		return 1 - f(1 - p)
	end
	return if p < 0.5 then f(p * 2) / 2 else 1 - f((1 - p) * 2) / 2
end

--- CSS's cubic-bezier(x1, y1, x2, y2) timing at `p` (0..1): the curve's height where its x is
--- `p` (the concept pages ease with these; the CUES strike keeps their feel exactly). x1 and x2
--- are in 0..1, so x rises with the curve and a bisection finds it.
function StageMath.bezier(x1: number, y1: number, x2: number, y2: number, p: number): number
	p = clamp01(p)
	if p == 0 or p == 1 then
		return p
	end
	local function at(a: number, b: number, s: number): number
		local u = 1 - s
		return 3 * u * u * s * a + 3 * u * s * s * b + s * s * s
	end
	local lo, hi = 0, 1
	for _ = 1, 32 do
		local mid = (lo + hi) / 2
		if at(x1, x2, mid) < p then
			lo = mid
		else
			hi = mid
		end
	end
	return at(y1, y2, (lo + hi) / 2)
end

-- A value along keys { at (seconds), value, curve (to the next key; nil: a straight line) }
-- at `t`: the first key's value before it, the last's after it.
local function track(keys: { { any } }, t: number): number
	local first = keys[1]
	if t <= first[1] then
		return first[2]
	end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t < b[1] then
			local span = b[1] - a[1]
			local p = if span > 0 then (t - a[1]) / span else 1
			local c = a[3]
			local e = if c then StageMath.bezier(c[1], c[2], c[3], c[4], p) else p
			return a[2] + (b[2] - a[2]) * e
		end
	end
	return keys[#keys][2]
end

export type StrikePose = {
	cue: number, -- the cue's offset along Strike.Direction, a share of the icon's side
	ball: number, -- the ball's offset along it from BallAt
	ballScale: number,
	ballShown: number, -- 0 (hidden) .. 1 (whole)
	spark: number, -- the spark's scale, of its full size (SparkShare x the hit's Spark)
	sparkTurn: number, -- degrees
	sparkShown: number, -- 0 .. 1
}

--- The CUES tile's strike (Config.UI.Menu.Column.Strike `S`; `hit` its Hover or Press) at `t`
--- seconds from its start: the ball pops in by the tip while the cue draws back, the cue aims,
--- snaps to the ball, follows through and slides home; the ball flies along the cue's line,
--- fading at the end of its run; a spark grows and turns at the hit, then fades. Outside
--- 0..Seconds only the cue shows, at rest.
function StageMath.strikePose(S: any, hit: any, t: number): StrikePose
	local C = S.Curves
	if t <= 0 or t >= hit.Seconds then
		return {
			cue = 0,
			ball = 0,
			ballScale = 0,
			ballShown = 0,
			spark = 0,
			sparkTurn = 0,
			sparkShown = 0,
		}
	end
	local through = S.Contact + hit.Through
	local cue = track({
		{ 0, 0, C.Draw },
		{ hit.Pulled, hit.Pull, C.Aim },
		{ hit.Hit - S.AimSeconds, hit.Pull + hit.Aim, C.Snap },
		{ hit.Hit, S.Contact, C.Through },
		{ hit.Hit + S.ThroughSeconds, through },
		{ hit.Gone - S.ReturnLead, through, C.Home },
		{ hit.Seconds, 0 },
	}, t)
	local peakAt = hit.PopFrom + (hit.PopTo - hit.PopFrom) * S.PopPeakShare
	local ballScale = track({
		{ hit.PopFrom, 0, C.Pop },
		{ peakAt, S.PopOvershoot, C.Settle },
		{ hit.PopTo, 1 },
		{ hit.Hit, 1, C.Fly },
		{ hit.FadeFrom, S.FlyScale },
		{ hit.Gone, S.EndScale },
	}, t)
	local ballShown = if t >= hit.Gone
		then 0
		else track({
			{ hit.PopFrom, 0, C.Pop },
			{ peakAt, 1 },
			{ hit.FadeFrom, 1 },
			{ hit.Gone, 0 },
		}, t)
	local ball = track({
		{ hit.Hit, 0, C.Fly },
		{ hit.FadeFrom, hit.Travel * S.FlyShare },
		{ hit.Gone, hit.Travel },
	}, t)
	local grown = hit.Hit + S.SparkGrowSeconds
	local sparkEnd = grown + S.SparkFadeSeconds
	local spark, sparkTurn, sparkShown = 0, 0, 0
	if t > hit.Hit and t < sparkEnd then
		spark = track({ { hit.Hit, 0, C.Pop }, { grown, 1 }, { sparkEnd, S.SparkEndScale } }, t)
		sparkTurn = track(
			{ { hit.Hit, 0, C.Pop }, { grown, S.SparkTurn }, { sparkEnd, 2 * S.SparkTurn } },
			t
		)
		sparkShown = track({ { hit.Hit, 0, C.Pop }, { grown, 1 }, { sparkEnd, 0 } }, t)
	end
	return {
		cue = cue,
		ball = ball,
		ballScale = ballScale,
		ballShown = ballShown,
		spark = spark,
		sparkTurn = sparkTurn,
		sparkShown = sparkShown,
	}
end

--- A pop's scale at `p`: from PopFrom up past PopPeak (Quad Out, peaking at PopPeakAt), then
--- settling at 1 (Sine InOut).
function StageMath.popScale(p: number, M: any): number
	if p <= 0 then
		return M.PopFrom
	end
	if p >= 1 then
		return 1
	end
	local k = M.PopPeakAt
	if p < k then
		return M.PopFrom + (M.PopPeak - M.PopFrom) * StageMath.ease("Quad", "Out", p / k)
	end
	return M.PopPeak + (1 - M.PopPeak) * StageMath.ease("Sine", "InOut", (p - k) / (1 - k))
end

--- A panel's height share while it unrolls from a bar: out past full (UnrollOvershoot) by
--- UnrollPeakAt (Quart Out), then settling at 1.
function StageMath.unrollShare(p: number, M: any): number
	if p <= 0 then
		return 0
	end
	if p >= 1 then
		return 1
	end
	local k = M.UnrollPeakAt
	if p < k then
		return M.UnrollOvershoot * StageMath.ease("Quart", "Out", p / k)
	end
	return M.UnrollOvershoot
		+ (1 - M.UnrollOvershoot) * StageMath.ease("Sine", "InOut", (p - k) / (1 - k))
end

--- A slam's scale: from SlamFrom down to 1 (Quad In) by SlamLandAt, then one small bulge.
function StageMath.slamScale(p: number, M: any): number
	p = clamp01(p)
	local k = M.SlamLandAt
	if p < k then
		return M.SlamFrom + (1 - M.SlamFrom) * StageMath.ease("Quad", "In", p / k)
	end
	local q = (p - k) / (1 - k)
	return 1 + M.SlamBounce * math.sin(q * math.pi) * (1 - q)
end

--- A drop's height above its place, as a share of the fall (1 at the start, 0 landed, with
--- Bounce Out's little hops).
function StageMath.dropShare(p: number): number
	return 1 - StageMath.ease("Bounce", "Out", p)
end

--- A grow (a background opening from its centre, lines growing outward): Quart Out.
function StageMath.growShare(p: number): number
	return StageMath.ease("Quart", "Out", p)
end

--- A close: the panel's height share folding to a line (Quad In) as everything fades.
function StageMath.closeShare(p: number): number
	return 1 - StageMath.ease("Quad", "In", p)
end

export type Entry = {
	id: string,
	kind: string,
	at: number,
	length: number,
	burst: string?,
	badgeOf: string?, -- a NEW badge: the tab it belongs to
}

--- A kind's own length (Config.UI.Motion), when a step gives none.
function StageMath.lengthOf(kind: string, M: any): number
	if kind == "Unroll" then
		return M.UnrollSeconds
	elseif kind == "Grow" then
		return M.GrowSeconds
	elseif kind == "Fade" then
		return M.FadeSeconds
	end
	return M.PopSeconds
end

--- A screen's open schedule from its steps (Config.UI.Shop.Open): one entry per piece, its
--- start scaled by `openSeconds` / the steps' own OpenSeconds, staggered within its step.
--- Returns the entries sorted by start, and when the last piece lands.
function StageMath.schedule(open: any, M: any, openSeconds: number?): ({ Entry }, number)
	local k = (openSeconds or open.OpenSeconds) / open.OpenSeconds
	local list: { Entry } = {}
	for _, step in open.Steps do
		local length = step.Length or StageMath.lengthOf(step.Kind, M)
		local gap = M.Stagger * (step.Stagger or 1)
		for i, id in step.Ids do
			local at = step.At * k + (i - 1) * gap
			table.insert(
				list,
				{ id = id, kind = step.Kind, at = at, length = length, burst = step.Burst }
			)
			if step.Badge then
				table.insert(list, {
					id = id .. "Badge",
					kind = "Pop",
					at = at + (step.BadgeAfter or 0),
					length = M.PopSeconds,
					badgeOf = id,
				})
			end
		end
	end
	table.sort(list, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.id < b.id
	end)
	local finish = 0
	for _, e in list do
		finish = math.max(finish, e.at + e.length)
	end
	return list, finish
end

export type State = {
	alpha: number, -- 0 hidden .. 1 shown
	scale: number, -- UIScale (Pop, Slam, Grow) or the height share (Unroll)
	drop: number, -- Drop: share of the fall still to go
	progress: number, -- 0..1 through its reveal
	landed: boolean, -- its reveal is over: its idle loop may start
}

--- A piece's look at `t` seconds into the open. With `reduced` (Reduce Motion) pieces only fade
--- in, over ReducedFadeSeconds, starting at half their planned time.
function StageMath.pieceState(e: Entry, t: number, M: any, reduced: boolean?): State
	local p = (t - e.at) / e.length
	if reduced then
		local a = clamp01((t - e.at * 0.5) / M.ReducedFadeSeconds)
		return { alpha = a, scale = 1, drop = 0, progress = a, landed = a >= 1 }
	end
	if p <= 0 then
		local start = if e.kind == "Unroll" or e.kind == "Grow"
			then 0
			elseif e.kind == "Slam" then M.SlamFrom
			else M.PopFrom
		return { alpha = 0, scale = start, drop = 1, progress = 0, landed = false }
	end
	local alpha = if e.kind == "Unroll"
		then 1
		else clamp01((t - e.at) / math.min(M.FadeSeconds, e.length))
	local scale, drop = 1, 0
	if e.kind == "Pop" then
		scale = StageMath.popScale(p, M)
	elseif e.kind == "Slam" then
		scale = StageMath.slamScale(p, M)
	elseif e.kind == "Grow" then
		scale = StageMath.growShare(p)
	elseif e.kind == "Unroll" then
		scale = StageMath.unrollShare(p, M)
	elseif e.kind == "Drop" then
		drop = StageMath.dropShare(p)
	end
	return { alpha = alpha, scale = scale, drop = drop, progress = clamp01(p), landed = p >= 1 }
end

--- A flipbook's frame at `t` seconds after it started: 0-based, or nil once a one-shot is over.
function StageMath.flipFrame(t: number, fps: number, frames: number, loop: boolean): number?
	if t < 0 then
		return nil
	end
	local i = math.floor(t * fps)
	if loop then
		return i % frames
	end
	return if i < frames then i else nil
end

--- Where frame `i` (0-based) sits on a sheet of `columns`, in texels: the ImageRectOffset.
function StageMath.flipOffset(
	i: number,
	columns: number,
	frameWidth: number,
	frameHeight: number
): (number, number)
	return (i % columns) * frameWidth, (i // columns) * frameHeight
end

--- A scroll inside a seamless 2 x 2 tile (gate 1): the window's offset in texels along one axis
--- after `t` seconds at `pxPerSecond` screen pixels, `texelsPerPx` texels each; wraps at one
--- period so the window never leaves the 2 x 2 picture.
function StageMath.scrollOffset(
	t: number,
	pxPerSecond: number,
	texelsPerPx: number,
	period: number
): number
	return (t * pxPerSecond * texelsPerPx) % period
end

--- A float (gate 1): `dy` pixels as a whole-pixel Position move and the fraction left over,
--- which the picture moves inside its label (in texels: fraction x texelsPerPx).
function StageMath.floatSplit(dy: number): (number, number)
	local whole = math.floor(dy + 0.5)
	return whole, dy - whole
end

--- A breathe (gate 1): the ImageRectSize and ImageRectOffset (texels, square picture) that show
--- the picture `scale` times bigger, the window kept inside the clear `border`.
function StageMath.breatheRect(imageSize: number, border: number, scale: number): (number, number)
	local size = (imageSize - border) / scale
	return size, (imageSize - size) / 2
end

--- Time left as the card shows it: "20d 23h", in the last day "23h 59m", in the last hour
--- "59:59". `words` holds the patterns (Strings.Menus.Shop.Featured: Days, Hours, Minutes).
function StageMath.timeLeft(seconds: number, words: any): string
	local s = math.max(0, math.floor(seconds))
	if s >= 86400 then
		return string.format(words.Days, s // 86400, (s % 86400) // 3600)
	elseif s >= 3600 then
		return string.format(words.Hours, s // 3600, (s % 3600) // 60)
	end
	return string.format(words.Minutes, s // 60, s % 60)
end

return StageMath
