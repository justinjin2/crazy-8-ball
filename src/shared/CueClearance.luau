--!strict
-- CueClearance: how steeply the DRAWN cue has to tilt so it clears the rail and the balls.
--
-- VISUAL ONLY. The pitch this returns is for drawing the cue and posing the shooter, and must
-- never be passed to fire(), Aim.trace or ShotInput: the physics elevation is fixed at
-- Config.Cue.CueElevationDegrees, and the server rejects any other elevation anyway, so a
-- leak would fail loudly rather than change a shot.
--
-- A cue ball near a cushion would otherwise have the drawn cue running through the rail, and
-- one with a ball close behind it would have the cue through that ball. Real players raise
-- the butt; so does this, by the least amount that keeps the drawn cue's SURFACE (the
-- CueShape envelope, not just its axis) the configured gap clear of both, anywhere the cue
-- can be during the wind-up.
--
-- Units are table INCHES: x/y as in the physics, heights above the cloth. The cue axis leaves
-- the strike point on the rendered ball (CueShape.strikeOffset) and rises at the pitch;
-- distances along it (s) are from that strike point, so the tip sits at s = gap and the
-- butt at gap + length. The drawn cue covers s from the resting gap to the full wind-up gap
-- plus its length.
--
-- The rail is taken as one rectangle at the cushion noses, continuous across the pocket
-- mouths, with its top at Config.Table.RailTopInches (raised near pocket castings). That is
-- conservative at a mouth and tight everywhere else.

local Config = require(script.Parent.Config)
local CueShape = require(script.Parent.CueShape)
local Placement = require(script.Parent.Placement)
local TableGeometry = require(script.Parent.Physics.Table)

type Geometry = TableGeometry.Geometry

local CueClearance = {}

export type Query = {
	cueX: number, -- cue ball centre, table inches
	cueY: number,
	angle: number, -- aim angle (radians), the physics convention
	spinX: number?, -- strike offset in ball radii (default 0, 0)
	spinY: number?,
	restGapInches: number?, -- tip to ball at rest (default Config.Cue.CueRestGapInches)
	fullGapInches: number?, -- tip to ball at a full wind-up (default rest + CuePullBackStuds)
	cueLengthStuds: number?, -- default Config.Cue.CueLengthStuds
}

export type Limit = "floor" | "rail" | "ball" | "ballSegment" | "cap"

export type Result = {
	degrees: number, -- the drawn pitch
	railDegrees: number, -- what the rail alone needs
	-- What set it: nothing ("floor", the physics elevation), the rail, a ball along the whole
	-- stroke ("ball"), a ball only the drawn cue could clear ("ballSegment", when the stroke
	-- line itself is blocked, like a ball frozen behind), or the cap.
	limit: Limit,
	blockingBall: number?, -- the ball that raised it, for "ball" and "ballSegment"
}

-- Everything a query needs, worked out once.
type Setup = {
	px: number, -- strike point on the rendered ball
	py: number,
	pz: number, -- its height above the cloth
	bx: number, -- unit direction from the ball back along the cue (plan)
	by: number,
	gR: number, -- resting gap
	gEnd: number, -- far end of everything the drawn cue covers: full gap + length
	L: number, -- cue length, studs
	rMax: number, -- widest the cue gets (inches)
	-- The resting cue's radius (inches) at its piece ends, from the tip (knotS[1] = gR) to the
	-- butt, as distances along the axis. CueShape's envelope runs linearly between them.
	knotS: { number },
	knotR: { number },
}

local function setupFor(q: Query): Setup
	local C = Config.Cue
	local s = Config.Table.StudsPerInch
	local back, right, up = CueShape.strikeOffset(q.spinX or 0, q.spinY or 0)
	local ax, ay = math.cos(q.angle), math.sin(q.angle)
	local L = q.cueLengthStuds or C.CueLengthStuds
	local gR = q.restGapInches or C.CueRestGapInches
	local gFull = q.fullGapInches or (gR + C.CuePullBackStuds / s)
	local knotS, knotR = { gR }, { CueShape.radiusAt(0, L) / s }
	for _, piece in CueShape.pieces(L) do
		table.insert(knotS, gR + piece.to / s)
		table.insert(knotR, CueShape.radiusAt(piece.to, L) / s)
	end
	return {
		-- The aim's right in table space is (ay, -ax).
		px = q.cueX - ax * back + ay * right,
		py = q.cueY - ay * back - ax * right,
		pz = Config.Balls.RenderRadiusInches + up,
		bx = -ax,
		by = -ay,
		gR = gR,
		gEnd = math.max(gFull, gR) + L / s,
		L = L,
		rMax = CueShape.radiusAtInches(math.huge, L),
		knotS = knotS,
		knotR = knotR,
	}
end

--- The height (inches above the cloth) the cue must clear where a ray from (xIn, yIn) along
--- (dirX, dirY) crosses the rail: the rail top, raised toward the pocket casting height when
--- any part of that crossing passes within PocketCastingReachInches of a pocket centre.
--- Taking the highest point of the whole crossing is conservative, and continuous as the
--- ray turns.
function CueClearance.railTopAt(
	geometry: Geometry,
	xIn: number,
	yIn: number,
	dirX: number,
	dirY: number
): number
	local T = Config.Table
	local length = math.sqrt(dirX * dirX + dirY * dirY)
	if length < 1e-12 then
		return T.RailTopInches
	end
	local dx, dy = dirX / length, dirY / length
	local tOut = Placement.rayExit(
		xIn,
		yIn,
		dx,
		dy,
		geometry.halfLength + T.RailWidthInches,
		geometry.halfWidth + T.RailWidthInches
	)
	local nearest = math.huge
	for _, pocket in geometry.pockets do
		-- Distance from the pocket centre to the segment of the ray inside the rail.
		local t = math.clamp((pocket.x - xIn) * dx + (pocket.y - yIn) * dy, 0, tOut)
		local ex, ey = xIn + dx * t - pocket.x, yIn + dy * t - pocket.y
		nearest = math.min(nearest, math.sqrt(ex * ex + ey * ey))
	end
	local w = math.clamp(
		(T.PocketCastingReachInches - nearest) / math.max(T.PocketCastingBlendInches, 1e-6),
		0,
		1
	)
	return T.RailTopInches + (T.PocketCastingTopInches - T.RailTopInches) * w
end

-- The first s (from the resting tip on) where the cue's radius there plus `k` * s reaches
-- `need`, or math.huge if it never does. The radius is linear between the knots and stays
-- at its widest past the butt, so this is exact.
local function firstReach(u: Setup, k: number, need: number): number
	local s0 = u.knotS[1]
	local f0 = u.knotR[1] + k * s0
	if f0 >= need then
		return s0
	end
	for i = 2, #u.knotS do
		local s1 = u.knotS[i]
		local f1 = u.knotR[i] + k * s1
		if f1 >= need then
			return s0 + (s1 - s0) * (need - f0) / (f1 - f0)
		end
		s0, f0 = s1, f1
	end
	if u.rMax + k * s0 >= need then
		return s0
	end
	return if k > 0 then (need - u.rMax) / k else math.huge
end

-- Does the drawn cue clear the rail at pitch `theta`? The cue's side first reaches the rail
-- at the first s where its axis comes within the cue's radius THERE of a cushion line, and
-- the cue's underside at that s, r / cos(theta) below the axis, has to be the clearance
-- above the rail top. Finding that s along the cue, rather than from where the bare axis
-- crosses, is what covers a cue running almost along a cushion: its side reaches the rail
-- long before its axis does. Beyond the first reach the cue only rises, faster than it
-- widens, so that is the tightest point.
--
-- The axis heads toward one cushion of each pair, closing on it by c * |b| per unit of s;
-- the other it is taken to stay level with (it really draws away), which errs toward a
-- higher cue. Then a steeper cue reaches the rail no sooner, so the answer only turns from
-- false to true as the pitch rises, which the bisection in pitch() relies on.
local function railOK(geometry: Geometry, u: Setup, theta: number): boolean
	local c, sn = math.cos(theta), math.sin(theta)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local first = math.min(
		firstReach(u, math.max(u.bx, 0) * c, hl - u.px),
		firstReach(u, math.max(-u.bx, 0) * c, hl + u.px),
		firstReach(u, math.max(u.by, 0) * c, hw - u.py),
		firstReach(u, math.max(-u.by, 0) * c, hw + u.py)
	)
	if first > u.gEnd then
		return true -- the whole drawn cue ends before its side reaches the rail
	end
	local r = CueShape.radiusAtInches(first - u.gR, u.L)
	-- The rail top from where the widest cue could first reach the rail, whatever the pitch:
	-- never later than the real reach, so the casting height is never missed, and the same
	-- at every pitch.
	local tFrom = Placement.rayExit(u.px, u.py, u.bx, u.by, hl - u.rMax, hw - u.rMax)
	local top =
		CueClearance.railTopAt(geometry, u.px + u.bx * tFrom, u.py + u.by * tFrom, u.bx, u.by)
	return u.pz + first * sn - r / c >= top + Config.Cue.VisualRailClearanceInches
end

-- Does the cue clear every ball at pitch `theta`? `sStart` is where the checked stretch of
-- axis begins: 0 is the whole line the tip travels in the stroke (the ideal), gR only the
-- cue as drawn. Returns the first ball in the way.
local function ballsOK(balls: { any }, u: Setup, theta: number, sStart: number): (boolean, number?)
	local c, sn = math.cos(theta), math.sin(theta)
	local Rr = Config.Balls.RenderRadiusInches
	local m = Config.Cue.VisualBallClearanceInches
	local reach = Rr + u.rMax + m
	for _, ball in ipairs(balls) do
		if ball.id ~= 0 and not ball.pocketed then
			local rx, ry = ball.x - u.px, ball.y - u.py
			local t = rx * u.bx + ry * u.by -- along the cue, in plan
			local e = rx * u.by - ry * u.bx -- across it
			if math.abs(e) < reach and t < u.gEnd + reach then
				local dZ = Rr + (ball.z or 0) - u.pz
				-- The nearest point of the axis to the ball's centre, within the checked stretch.
				local s = math.clamp(t * c + dZ * sn, sStart, u.gEnd)
				local along, lift = s * c - t, s * sn - dZ
				-- The cue within a ball radius either side of that point can be the part that
				-- touches, so take the envelope that far toward the butt.
				local r = CueShape.radiusAtInches(math.max(0, s - u.gR) + Rr, u.L)
				local need = Rr + r + m
				if along * along + lift * lift + e * e < need * need then
					return false, ball.id
				end
			end
		end
	end
	return true, nil
end

-- Bisect a predicate that is false at `lo` and true at `hi`; returns a pitch where it holds.
local function bisect(ok: (number) -> boolean, lo: number, hi: number): number
	for _ = 1, Config.Cue.VisualPitchBisections do
		local mid = (lo + hi) / 2
		if ok(mid) then
			hi = mid
		else
			lo = mid
		end
	end
	return hi
end

--- The least pitch (degrees) that keeps the drawn cue clear of the rail and of `balls` (the
--- physics balls: id, x, y, z, pocketed; the cue ball, id 0, is skipped), between
--- CueElevationDegrees and VisualPitchMaxDegrees. See the module header: VISUAL ONLY.
function CueClearance.pitch(geometry: Geometry, balls: { any }, q: Query): Result
	local C = Config.Cue
	local u = setupFor(q)
	local lo, cap = math.rad(C.CueElevationDegrees), math.rad(C.VisualPitchMaxDegrees)
	local function rail(theta: number): boolean
		return railOK(geometry, u, theta)
	end

	local theta, limit: Limit = lo, "floor"
	if not rail(lo) then
		if rail(cap) then
			theta, limit = bisect(rail, lo, cap), "rail"
		else
			theta, limit = cap, "cap"
		end
	end
	local railTheta = theta

	local step = math.rad(C.VisualPitchScanStepDegrees)
	for _, sStart in { 0, u.gR } do
		local ok, blocking = ballsOK(balls, u, railTheta, sStart)
		if ok then
			return {
				degrees = math.deg(railTheta),
				railDegrees = math.deg(railTheta),
				limit = limit,
				blockingBall = nil,
			}
		end
		-- A ball blocks a band of pitches; scan up past it, then pin the edge down.
		local below = railTheta
		while below < cap do
			local above = math.min(below + step, cap)
			if ballsOK(balls, u, above, sStart) then
				local found = bisect(function(x: number): boolean
					return (ballsOK(balls, u, x, sStart))
				end, below, above)
				return {
					degrees = math.deg(found),
					railDegrees = math.deg(railTheta),
					limit = if sStart == 0 then "ball" else "ballSegment",
					blockingBall = blocking,
				}
			end
			below = above
		end
	end
	return {
		degrees = C.VisualPitchMaxDegrees,
		railDegrees = math.deg(railTheta),
		limit = "cap",
		blockingBall = nil,
	}
end

--- Whether the drawn cue at `degrees` clears the rail and the balls, and if not, what is in
--- the way ("rail" or "ball"). `fromTip` checks the whole stroke line from the ball (the
--- ideal); otherwise only the cue as drawn from its resting tip back. For tests and checks.
function CueClearance.isClear(
	geometry: Geometry,
	balls: { any },
	q: Query,
	degrees: number,
	fromTip: boolean
): (boolean, string?)
	local u = setupFor(q)
	local theta = math.rad(degrees)
	if not railOK(geometry, u, theta) then
		return false, "rail"
	end
	if not ballsOK(balls, u, theta, if fromTip then 0 else u.gR) then
		return false, "ball"
	end
	return true, nil
end

--- Ease a shown pitch toward its target over `dt` seconds: quickly up (a cue must not dip
--- into a rail while it turns), slowly down (so it does not bob).
function CueClearance.ease(current: number, target: number, dt: number): number
	local C = Config.Cue
	local seconds = if target > current then C.VisualPitchRiseSeconds else C.VisualPitchFallSeconds
	return current + (target - current) * (1 - math.exp(-dt / math.max(seconds, 1e-3)))
end

return CueClearance
