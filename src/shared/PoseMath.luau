--!strict
-- PoseMath: the maths of posing a shooter, as plain numbers so Lune can test it. No tables
-- are built: vectors go in and come out as separate numbers, because the poser calls these
-- for every limb of every posed character every frame.
--
--   twoBone     an arm or a leg (two bones) reaching for a target, the joint bending toward
--               a hint, with a soft limit so a nearly straight limb never pops
--   lineSphere  where along a line a limb of fixed reach can touch it, so a hand that cannot
--               reach its spot slides ALONG the cue instead of leaving it
--   strokeGap   the cue's tip gap through a stroke: accelerate in, rest on the ball until the
--               replay shows it moving, follow through, hold
--   transition  the poser's state machine (rest, aim, stroke, idle)
--   alpha       frame-rate independent smoothing

local PoseMath = {}

export type State = "rest" | "aim" | "stroke" | "idle"
-- What the driver wants this frame. "strike" starts a stroke from aim; "cancel" (the shot
-- was turned down) goes back to aim from a stroke.
export type Want = "rest" | "idle" | "aim" | "strike" | "cancel"

--- A two-bone chain from S toward T with bone lengths l1 and l2, the middle joint bending
--- toward the hint direction (px, py, pz), any length. `soft` in (0, 1]: the reach starts
--- easing in at soft * (l1 + l2), so the limb straightens smoothly instead of snapping.
--- Returns the middle joint E, the chain's end, and whether T is within the chain's length.
--- The end always lies on the S -> T line.
function PoseMath.twoBone(
	sx: number,
	sy: number,
	sz: number,
	tx: number,
	ty: number,
	tz: number,
	px: number,
	py: number,
	pz: number,
	l1: number,
	l2: number,
	soft: number
): (number, number, number, number, number, number, boolean)
	local dx, dy, dz = tx - sx, ty - sy, tz - sz
	local d = math.sqrt(dx * dx + dy * dy + dz * dz)
	local ux: number, uy: number, uz: number
	if d < 1e-6 then
		-- No direction to reach in: fold away from the hint.
		local h = math.sqrt(px * px + py * py + pz * pz)
		if h < 1e-9 then
			ux, uy, uz = 0, -1, 0
		else
			ux, uy, uz = -px / h, -py / h, -pz / h
		end
	else
		ux, uy, uz = dx / d, dy / d, dz / d
	end
	local dmax = (l1 + l2) * (1 - 1e-4)
	local dmin = math.abs(l1 - l2) + 1e-4
	local ds = math.clamp(soft, 0, 1) * dmax
	local dc = d
	if d > ds then
		local band = dmax - ds
		dc = if band > 1e-9 then ds + band * (1 - math.exp(-(d - ds) / band)) else dmax
	end
	dc = math.clamp(dc, dmin, math.max(dmin, dmax))
	-- The bend direction: the hint with its component along the reach removed.
	local along = px * ux + py * uy + pz * uz
	local qx, qy, qz = px - ux * along, py - uy * along, pz - uz * along
	local q = math.sqrt(qx * qx + qy * qy + qz * qz)
	if q < 1e-6 then
		-- Hint parallel to the reach (or none): any perpendicular will do; pick one that is
		-- stable, off the axis the reach is least aligned with.
		if math.abs(ux) < 0.9 then
			qx, qy, qz = 0, uz, -uy -- u x (1, 0, 0)
		else
			qx, qy, qz = -uz, 0, ux -- u x (0, 1, 0)
		end
		q = math.sqrt(qx * qx + qy * qy + qz * qz)
	end
	qx, qy, qz = qx / q, qy / q, qz / q
	local cosA = math.clamp((l1 * l1 + dc * dc - l2 * l2) / (2 * l1 * dc), -1, 1)
	local sinA = math.sqrt(math.max(0, 1 - cosA * cosA))
	return sx + (ux * cosA + qx * sinA) * l1,
		sy + (uy * cosA + qy * sinA) * l1,
		sz + (uz * cosA + qz * sinA) * l1,
		sx + ux * dc,
		sy + uy * dc,
		sz + uz * dc,
		d <= dmax
end

--- The parameter t on the line O + D t where the point is exactly r from C, choosing the
--- one nearest `tPref` and keeping it within [tMin, tMax]; `exact` is false when that
--- needed clamping or the line never comes within r (then the closest approach, clamped).
function PoseMath.lineSphere(
	ox: number,
	oy: number,
	oz: number,
	dx: number,
	dy: number,
	dz: number,
	cx: number,
	cy: number,
	cz: number,
	r: number,
	tPref: number,
	tMin: number,
	tMax: number
): (number, boolean)
	local a = dx * dx + dy * dy + dz * dz
	if a < 1e-12 then
		return math.clamp(tPref, tMin, tMax), false
	end
	local wx, wy, wz = ox - cx, oy - cy, oz - cz
	local b = dx * wx + dy * wy + dz * wz
	local c = wx * wx + wy * wy + wz * wz - r * r
	local disc = b * b - a * c
	if disc < 0 then
		local t = -b / a
		return math.clamp(t, tMin, tMax), false
	end
	local root = math.sqrt(disc)
	local t1, t2 = (-b - root) / a, (-b + root) / a
	local t = if math.abs(t1 - tPref) <= math.abs(t2 - tPref) then t1 else t2
	local clamped = math.clamp(t, tMin, tMax)
	if clamped ~= t then
		-- The nearer root is out of range: the other may be in it.
		local other = if t == t1 then t2 else t1
		if other >= tMin and other <= tMax then
			return other, true
		end
	end
	return clamped, clamped == t
end

--- The cue's gap (studs from the ball's surface; 0 is contact, negative is past it, the
--- follow-through) `t` seconds into a stroke that starts from `fromGap`. The tip accelerates
--- in over `strokeSec`, then rests on the ball until the replay has it moving (`movingAt`,
--- stroke seconds, nil until then; given up after `maxWait`), then follows through by
--- `followGap` over `followSec` and holds there for `holdSec`. `done` ends the stroke.
function PoseMath.strokeGap(
	t: number,
	fromGap: number,
	strokeSec: number,
	movingAt: number?,
	followGap: number,
	followSec: number,
	holdSec: number,
	maxWait: number
): (number, boolean)
	if t < strokeSec then
		local k = math.max(t, 0) / strokeSec
		return fromGap * (1 - k * k), false
	end
	if movingAt == nil then
		return 0, t >= strokeSec + maxWait
	end
	local start = math.max(movingAt, strokeSec)
	local u = math.max(0, t - start) / math.max(followSec, 1e-6)
	if u < 1 then
		return -followGap * (1 - (1 - u) * (1 - u)), false
	end
	return -followGap, (t - start - followSec) >= holdSec
end

--- The poser's next state. A stroke plays out whatever is wanted (the ball has been struck)
--- until it is done, then idles; only "rest" (the shooter left, the turn is over) or
--- "cancel" (the server turned the shot down) cut it short.
function PoseMath.transition(state: State, want: Want, strokeDone: boolean): State
	if want == "rest" then
		return "rest"
	end
	if state == "stroke" then
		if want == "cancel" then
			return "aim"
		end
		return if strokeDone then "idle" else "stroke"
	end
	if want == "strike" then
		return if state == "aim" then "stroke" else state
	end
	if want == "aim" then
		return "aim"
	end
	if want == "idle" then
		return if state == "aim" then "idle" else state
	end
	return state -- "cancel" with nothing to cancel
end

--- The share of the way to a target to move this frame, for smoothing that settles in about
--- `seconds` whatever the frame rate.
function PoseMath.alpha(dt: number, seconds: number): number
	return 1 - math.exp(-dt / math.max(seconds, 1e-3))
end

return PoseMath
