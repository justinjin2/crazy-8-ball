--!strict
-- FxMath: the plain arithmetic behind the ability looks (src/client/AbilityFx.luau, ScreenFx,
-- SoundSheet; docs/prompts/ABILITIES_PROMPT.md 5): fade envelopes, a light's flare, the arcs a
-- ring on the cloth is drawn from, clipping them to the cloth, and flipbook frames. Pure: no
-- Instances and no Roblox types, so tests/fx_math_test.luau runs it in Lune. Visual only (it
-- never touches the simulation), so trig is fine here.

local FxMath = {}

-- 0..1 eased at both ends (smoothstep), clamped.
function FxMath.smooth(t: number): number
	local x = math.clamp(t, 0, 1)
	return x * x * (3 - 2 * x)
end

--- The weight (0..1) of an effect `t` seconds after it began that fades in over `fadeIn`,
--- holds for `hold` (math.huge: until released) and fades out over `fadeOut`, each ramp eased.
--- 0 before it begins and once it has faded out.
function FxMath.envelope(t: number, fadeIn: number, hold: number, fadeOut: number): number
	if t < 0 then
		return 0
	end
	if t < fadeIn then
		return FxMath.smooth(t / fadeIn)
	end
	t -= fadeIn
	if t < hold then
		return 1
	end
	t -= hold
	if t < fadeOut then
		return 1 - FxMath.smooth(t / fadeOut)
	end
	return 0
end

--- True once an envelope has run its whole course (it can be dropped).
function FxMath.envelopeDone(t: number, fadeIn: number, hold: number, fadeOut: number): boolean
	return t >= fadeIn + hold + fadeOut
end

--- The weight of an effect released early: it was at `from` when let go and fades to 0 over
--- `fadeOut`, `since` seconds ago.
function FxMath.released(from: number, since: number, fadeOut: number): number
	if fadeOut <= 0 then
		return 0
	end
	return from * (1 - FxMath.smooth(since / fadeOut))
end

--- A flare that peaks fast and dies away: up to 1 over the first `riseShare` of `seconds`
--- (eased), then down to 0 by `seconds` (quadratic, quick at first). 0 outside 0..seconds.
function FxMath.flare(t: number, seconds: number, riseShare: number): number
	if t < 0 or seconds <= 0 or t >= seconds then
		return 0
	end
	local rise = seconds * math.clamp(riseShare, 0, 1)
	if t < rise then
		return FxMath.smooth(t / rise)
	end
	local u = (t - rise) / math.max(seconds - rise, 1e-6)
	return (1 - u) * (1 - u)
end

--- A shake's strength `t` into `seconds`: full at once, easing to 0 (quadratic).
function FxMath.decay(t: number, seconds: number): number
	if t < 0 or seconds <= 0 or t >= seconds then
		return 0
	end
	local u = 1 - t / seconds
	return u * u
end

export type Arc = { from: number, to: number } -- angles in radians, from < to

--- The arcs a ring is drawn from: `segments` equal pieces round the circle starting at
--- `phase`, each covering `drawShare` of its piece (1 = a solid ring, less = dashes with gaps),
--- centred in its piece.
function FxMath.ringArcs(segments: number, drawShare: number, phase: number): { Arc }
	local n = math.max(1, math.floor(segments))
	local share = math.clamp(drawShare, 0, 1)
	local piece = 2 * math.pi / n
	local gap = piece * (1 - share) / 2
	local arcs: { Arc } = {}
	for i = 0, n - 1 do
		local a = phase + i * piece + gap
		table.insert(arcs, { from = a, to = a + piece * share })
	end
	return arcs
end

--- The length of each Bezier handle that draws an arc of `sweep` radians on a circle of
--- `radius` (4/3 tan(sweep / 4) r; a quarter circle is about 0.5523 r).
function FxMath.arcHandle(radius: number, sweep: number): number
	return 4 / 3 * math.tan(sweep / 4) * radius
end

--- True when (x, y) lies on the cloth: inside the playing area's half length and half width
--- (inches, the table's own frame, centre at 0, 0).
function FxMath.onCloth(x: number, y: number, halfLength: number, halfWidth: number): boolean
	return math.abs(x) <= halfLength and math.abs(y) <= halfWidth
end

--- The arcs of a ring of `radius` round (cx, cy) whose middles are on the cloth (the rest
--- would be drawn over the cushions or off the table).
function FxMath.clipArcs(
	arcs: { Arc },
	cx: number,
	cy: number,
	radius: number,
	halfLength: number,
	halfWidth: number
): { Arc }
	local kept: { Arc } = {}
	for _, arc in arcs do
		local mid = (arc.from + arc.to) / 2
		if
			FxMath.onCloth(
				cx + radius * math.cos(mid),
				cy + radius * math.sin(mid),
				halfLength,
				halfWidth
			)
		then
			table.insert(kept, arc)
		end
	end
	return kept
end

--- True when (dx, dy) is within `radius` (the involvement rule's distance, and a ball in a
--- ring's reach).
function FxMath.within(dx: number, dy: number, radius: number): boolean
	return dx * dx + dy * dy <= radius * radius
end

--- The flipbook frame (0-based) `t` seconds in at `fps` over `frames` frames: looping, or held
--- on the last frame once it has played through.
function FxMath.flipFrame(t: number, fps: number, frames: number, loop: boolean): number
	local n = math.max(1, math.floor(frames))
	local i = math.floor(math.max(t, 0) * math.max(fps, 0))
	if loop then
		return i % n
	end
	return math.min(i, n - 1)
end

--- A frame's column and row (0-based) on a sheet `cols` wide, read left to right, top down.
function FxMath.flipCell(frame: number, cols: number): (number, number)
	local c = math.max(1, math.floor(cols))
	return frame % c, math.floor(frame / c)
end

return FxMath
