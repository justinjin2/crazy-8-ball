--!strict
-- ShooterStance: where the shooter stands (or sits, or kneels) for a shot and how they reach
-- the cue, as pure geometry. The client poses the body from it and the server places the
-- anchored root with the very same function, so the two agree about where a player shot from.
--
-- Units are TABLE STUDS: x and y along the table's length and width from its centre
-- (physics inches times StudsPerInch), heights above the FLOOR the table stands on (the
-- cloth is at Config.Table.SurfaceHeightStuds). Angles use the physics aim convention, so
-- Placement.aimVector(p, stance.yaw) is the facing in the world and
-- Placement.fromTableStuds turns any point here into a world position.
--
-- The shooter is right-handed: the right hand holds the cue and the left makes the bridge. The
-- cue is always its own length (no extension) and there is no mechanical bridge: every shot is
-- reached by where the body goes and how it leans (designer, 2026-09-25).
--
-- How a stance is found:
--   1. The drawn cue's axis leaves the strike point on the rendered ball and rises at the
--      visual pitch (CueClearance), exactly as CueStickBuilder draws it.
--   2. The stretches of that axis the hands may use: the grip window (the cue's back part), and
--      the bridge runs, the parts of the cue line over the cloth or the rail top (never a
--      pocket) where the cue sits low enough over the surface for a hand bridge under it.
--   3. A search over SUPPORTS, cheapest first: standing on the floor (a plain stance, then
--      leaning further in, the back foot lifting), the hips up on the rail, then kneeling on
--      the table. The first support with any stance that reaches wins, so the body only climbs
--      when it has to. Within a support every SIDE is tried (Config.Stance.Sides: the classic
--      open stance with the chin over the cue, the cue by the right hip, the body square to it
--      reaching across), each at the least lean from the support's range that lets the right
--      shoulder reach the grip window and the left shoulder a bridge run. The body is not tied
--      to the cue line: it stands wherever those two reaches meet the support's region, as
--      near the natural grip-behind-the-hip distance as it can. The cheapest candidate wins
--      (Config.Stance.Costs), the one used last frame (the Memory) a little cheaper, so it
--      does not flip between two near-equal stances.
--   4. The torso and head must clear the rail, the cloth and the balls on it, and the cue must
--      pass clear of the torso and head. A candidate that fails is not used.
--   5. The grip and bridge hands' places on the cue at the chosen spot, and the pull.
--
-- For a given lean the feasible spots along a side's line are intervals, found in closed form
-- (a shoulder moving along the cue direction against a segment, or a run, of the cue), so the
-- whole search is a few dozen evaluations of arithmetic. Deterministic: the same input (the
-- Memory included) always gives the same stance.

local Config = require(script.Parent.Config)
local CueShape = require(script.Parent.CueShape)
local Placement = require(script.Parent.Placement)

local ShooterStance = {}

-- A tuning aid: set to a function to hear why each candidate was turned down (tests and the
-- Studio preview only; nil in the game, where it costs nothing).
ShooterStance.trace = nil :: ((tier: string, side: string, why: string) -> ())?

-- Measured from the rest rig (AvatarPose.measureBody), studs; heights above the floor.
export type Body = {
	RootHeight: number, -- root centre
	WaistHeight: number, -- the hip line the torso leans about
	ShoulderHeight: number, -- shoulder pivots, standing
	ShoulderHalfWidth: number, -- centre line to either shoulder pivot
	ArmReach: number, -- shoulder pivot to the grip point, arm straight
	HalfWidth: number, -- the body's footprint, across the shoulders
	HalfDepth: number, -- ...and front to back
	HipHeight: number, -- the hip (leg) pivots, standing
	ThighLength: number, -- hip pivot to knee pivot (R6: the whole rigid leg)
}

-- The table's surroundings, table studs (ShooterStance.area).
export type Area = {
	clothHx: number, -- cushion noses
	clothHy: number,
	railHx: number, -- outer edge of the rail
	railHy: number,
	barrierHx: number, -- the invisible wall around the table
	barrierHy: number,
	fenceHx: number, -- inner faces of the match fence: half extents of a box...
	fenceHy: number,
	fenceCx: number, -- ...centred this far along the table's length (negative: toward the head)
	clothZ: number, -- cloth height above the floor
	railTopZ: number, -- rail top height above the floor
	releaseClearance: number, -- the idle spot stays at least this far outside the barrier
	pockets: { { x: number, y: number, r: number } }, -- no bridge within these circles
}

-- What the body stands on: the floor ("stand" at the natural lean, "lean" further in), the
-- rail ("rail": the hips up on the rail top) or the cloth ("table": kneeling).
export type Mode = "stand" | "lean" | "rail" | "table"

-- Threaded from one frame's stance into the next, for hysteresis.
export type Memory = { mode: Mode, side: string, onRail: boolean }

export type Input = {
	ballXIn: number, -- cue ball centre, table inches
	ballYIn: number,
	angle: number, -- aim angle, radians
	spinX: number?, -- strike offset, ball radii (default 0)
	spinY: number?,
	pitchDegrees: number, -- the drawn cue's pitch (CueClearance), clamped to the visual range
	pull: number, -- wind-up 0..1
	cueLengthStuds: number?, -- default Config.Cue.CueLengthStuds
	body: Body,
	area: Area,
	memory: Memory?,
}

export type Point = { x: number, y: number, z: number }

-- The off hand's bridge, always under the cue.
export type HandBridge = {
	x: number, -- under the cue
	y: number,
	cueZ: number, -- the cue's axis height there
	surfaceZ: number, -- the cloth, or the rail top when bridging on the rail
	handZ: number, -- where the hand's target sits: just above the surface, or raised under a
	-- steep cue that no bridge on the surface reaches (raised)
	onRail: boolean,
	raised: boolean,
	alongStuds: number, -- from the strike point along the cue's axis
}

export type Stance = {
	mode: Mode,
	side: string, -- Config.Stance.Sides[i].Name
	rootX: number, -- the root's centre, table studs
	rootY: number,
	rootZ: number, -- above the floor: RootHeight on the floor, higher on the rail or table
	yaw: number, -- facing, aim-angle convention
	-- 0..1 through the support's lean range (the Config.Avatar.Profiles pairs): stand is
	-- always 0, lean runs from the natural lean to the most.
	lean: number,
	torsoDegrees: number, -- torso lean from vertical
	twistDegrees: number, -- the facing, this far right of the aim
	supportZ: number, -- what the legs rest on: 0 (floor), the rail top or the cloth
	-- On the rail, where the hanging (right) foot reaches for the floor, outside the rail.
	hangX: number,
	hangY: number,
	pitchDegrees: number, -- the drawn pitch used (clamped)
	cueGapStuds: number, -- tip to strike point along the axis, with the pull
	pullLimit: number, -- the drawn wind-up is scaled by this so the tip never passes the bridge
	grip: Point, -- the grip hand, on the cue's axis, moving with the pull
	gripFromTipStuds: number, -- along the cue from the tip at rest
	gripReachable: boolean, -- the right arm reaches the grip (false only if nothing reached)
	bridgeReachable: boolean, -- the left arm reaches the bridge (likewise)
	handBridge: HandBridge,
	idleX: number, -- where the shooter stands once the shot is away (ShooterStance.idle)
	idleY: number,
	idleZ: number, -- the root's height there: standing on the floor (RootHeight)
	memory: Memory,
}

type Side = { Name: string, TwistDegrees: number, ChinSideStuds: number, Cost: number }
type Run = { s1: number, s2: number, z: number, onRail: boolean, raised: boolean }

local INF = math.huge

local function distance(ax: number, ay: number, az: number, bx: number, by: number, bz: number)
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Where a ray from (ox, oy) along the unit (dx, dy) is inside the box of half extents
-- (hx, hy): the distances it enters and leaves, from 0 on (enter > leave when it never is).
local function slab(o: number, d: number, half: number, enter: number, leave: number)
	if math.abs(d) < 1e-12 then
		if math.abs(o) >= half then
			return 1, 0 -- parallel to this pair of edges and outside them: never inside
		end
		return enter, leave
	end
	local t1, t2 = (-half - o) / d, (half - o) / d
	return math.max(enter, math.min(t1, t2)), math.min(leave, math.max(t1, t2))
end

local function rayInside(
	ox: number,
	oy: number,
	dx: number,
	dy: number,
	hx: number,
	hy: number
): (number, number)
	local enter, leave = slab(ox, dx, hx, 0, INF)
	return slab(oy, dy, hy, enter, leave)
end

-- Intervals are kept as flat arrays {lo1, hi1, lo2, hi2, ...}, sorted and disjoint.

-- `list` without [lo, hi] cut out of it, into `out`.
local function subtract(list: { number }, lo: number, hi: number, out: { number })
	table.clear(out)
	for i = 1, #list, 2 do
		local a, b = list[i], list[i + 1]
		if hi <= a or lo >= b then
			table.insert(out, a)
			table.insert(out, b)
		else
			if lo > a then
				table.insert(out, a)
				table.insert(out, lo)
			end
			if hi < b then
				table.insert(out, hi)
				table.insert(out, b)
			end
		end
	end
end

-- The part of `list` inside [lo, hi], into `out`.
local function clip(list: { number }, lo: number, hi: number, out: { number })
	table.clear(out)
	for i = 1, #list, 2 do
		local a, b = math.max(list[i], lo), math.min(list[i + 1], hi)
		if a <= b then
			table.insert(out, a)
			table.insert(out, b)
		end
	end
end

-- The intersection of two interval lists, into `out`.
local function intersect(a: { number }, b: { number }, out: { number })
	table.clear(out)
	local i, j = 1, 1
	while i <= #a and j <= #b do
		local lo, hi = math.max(a[i], b[j]), math.min(a[i + 1], b[j + 1])
		if lo <= hi then
			table.insert(out, lo)
			table.insert(out, hi)
		end
		if a[i + 1] < b[j + 1] then
			i += 2
		else
			j += 2
		end
	end
end

-- The union of loose intervals (in any order, overlapping), into `out`, sorted and disjoint.
local function union(loose: { number }, out: { number })
	table.clear(out)
	local n = #loose // 2
	local order = table.create(n, 0)
	for k = 1, n do
		order[k] = k
	end
	table.sort(order, function(p, q)
		local a, b = loose[2 * p - 1], loose[2 * q - 1]
		if a ~= b then
			return a < b
		end
		return p < q
	end)
	for _, k in order do
		local lo, hi = loose[2 * k - 1], loose[2 * k]
		local m = #out
		if m > 0 and lo <= out[m] then
			out[m] = math.max(out[m], hi)
		else
			table.insert(out, lo)
			table.insert(out, hi)
		end
	end
end

-- The value in `list` nearest `want` (ties to the lower); nil if the list is empty.
local function nearest(list: { number }, want: number): number?
	local best: number? = nil
	local gap = INF
	for i = 1, #list, 2 do
		local v = math.clamp(want, list[i], list[i + 1])
		local d = math.abs(v - want)
		if d < gap then
			best, gap = v, d
		end
	end
	return best
end

--- The surroundings of a table whose match has `teamSize` players a side.
function ShooterStance.area(teamSize: number): Area
	local T = Config.Table
	local s = T.StudsPerInch
	local barrierHx, barrierHy = Placement.barrierHalfExtents()
	local fenceHx, fenceHy, fenceCx = Placement.fenceHalfExtents(teamSize)
	local hx, hy = T.LengthInches / 2 * s, T.WidthInches / 2 * s
	local margin = Config.Stance.PocketBridgeMarginStuds
	local corner = T.CornerMouthInches / 2 * s + margin
	local side = T.SideMouthInches / 2 * s + margin
	return {
		clothHx = hx,
		clothHy = hy,
		railHx = (T.LengthInches / 2 + T.RailWidthInches) * s,
		railHy = (T.WidthInches / 2 + T.RailWidthInches) * s,
		barrierHx = barrierHx,
		barrierHy = barrierHy,
		fenceHx = fenceHx,
		fenceHy = fenceHy,
		fenceCx = fenceCx,
		clothZ = T.SurfaceHeightStuds,
		railTopZ = T.SurfaceHeightStuds + T.RailTopInches * s,
		releaseClearance = Config.Multiplayer.Barrier.ReleaseClearanceStuds,
		pockets = {
			{ x = -hx, y = -hy, r = corner },
			{ x = hx, y = -hy, r = corner },
			{ x = -hx, y = hy, r = corner },
			{ x = hx, y = hy, r = corner },
			{ x = 0, y = -hy, r = side },
			{ x = 0, y = hy, r = side },
		},
	}
end

--- The height of the hip pivots above the floor in `mode` (the floor's own when standing).
function ShooterStance.hipHeight(mode: Mode, body: Body, area: Area): number
	local S = Config.Stance
	if mode == "rail" then
		return area.railTopZ + S.Rail.WaistAboveStuds - (body.WaistHeight - body.HipHeight)
	elseif mode == "table" then
		return area.clothZ
			+ S.Table.KneeRestStuds
			+ body.ThighLength * math.cos(math.rad(S.Table.ThighBackDegrees))
	end
	return body.HipHeight
end

--- The stance for one frame. Deterministic: the same input always gives the same stance.
function ShooterStance.solve(q: Input): Stance
	local S = Config.Stance
	local C = Config.Cue
	local K = S.Clearance
	local s = Config.Table.StudsPerInch
	local body, area, memory = q.body, q.area, q.memory
	local L = q.cueLengthStuds or C.CueLengthStuds

	-- 1. The cue's axis: from the strike point P back along b, rising at the pitch.
	local pitchDegrees = math.clamp(
		q.pitchDegrees,
		C.CueElevationDegrees,
		math.max(C.VisualPitchMaxDegrees, C.MaxElevationDegrees)
	)
	local theta = math.rad(pitchDegrees)
	local c, sn = math.cos(theta), math.sin(theta)
	local ax, ay = math.cos(q.angle), math.sin(q.angle)
	local bx, by = -ax, -ay
	local lx, ly = -ay, ax -- the aim's left
	local back, right, up = CueShape.strikeOffset(q.spinX or 0, q.spinY or 0)
	back, right, up = back * s, right * s, up * s
	local px = q.ballXIn * s - ax * back + ay * right
	local py = q.ballYIn * s - ay * back - ax * right
	local pz = area.clothZ + Config.Balls.RenderRadiusInches * s + up
	local function axisAt(along: number): (number, number, number)
		return px + bx * along * c, py + by * along * c, pz + along * sn
	end
	local gR = C.CueRestGapInches * s
	local gF = gR + C.CuePullBackStuds

	-- 2a. The grip window, and where the grip hand naturally is: just behind the hip, never
	-- more than GripAboveShoulderStuds above the shoulder (a steep cue chokes up instead).
	local steep = math.clamp(
		(pitchDegrees - C.CueElevationDegrees) / (S.SteepGripDegrees - C.CueElevationDegrees),
		0,
		1
	)
	local minFraction = S.GripMinFromTipFraction
		+ (S.SteepGripMinFromTipFraction - S.GripMinFromTipFraction) * steep
	local sLo = gR + minFraction * L
	local sHi = gR + L - S.GripButtEndStuds
	local sCap = if sn > 1e-6
		then (body.ShoulderHeight + S.GripAboveShoulderStuds - pz) / sn
		else INF
	local sGrip0 = math.min(gR + L * (1 - S.GripFromButtFraction), math.max(sLo, sCap))
	local uPref = sGrip0 * c - S.GripBehindRootStuds

	-- 2b. The bridge runs: along-axis stretches over the cloth (clear of the cushion, or right
	-- against it when nothing else is left) or the rail top (clear of both its edges), never over a pocket, between the resting tip's
	-- clearance and MaxBridgeInches, where the cue is at least BridgeMinRiseStuds and at most
	-- BridgeMaxRiseStuds above the surface. Only a cue too steep for any of that (a jump shot
	-- with the ball far in) gets RAISED runs instead: the hand stands up under the cue.
	local tipClear = S.BridgeTipClearInches * s
	local sPrefB = math.max(S.BridgeFromBallInches * s - back, gF + tipClear)
	local sMinB = gR + tipClear
	local sMaxB = math.max(sPrefB, S.MaxBridgeInches * s - back)
	local runs: { Run } = {}
	do
		local railInset = S.RailBridgeInsetInches * s
		local scratch, out = {}, {}
		-- Plan distance t along the cue line, as along-axis s = t / c.
		local function surfaceRuns(list: { number }, z: number, onRail: boolean, raised: boolean)
			-- Pockets out.
			local cur = table.clone(list)
			for _, pocket in area.pockets do
				local ox, oy = px - pocket.x, py - pocket.y
				local proj = ox * bx + oy * by
				local disc = proj * proj - (ox * ox + oy * oy - pocket.r * pocket.r)
				if disc > 0 then
					local root = math.sqrt(disc)
					subtract(cur, (-proj - root) / c, (-proj + root) / c, out)
					cur, out = out, cur
				end
			end
			-- The cue's height over the surface.
			local lo, hi = sMinB, sMaxB
			if sn > 1e-9 then
				local sRiseLo = (z + S.BridgeMinRiseStuds - pz) / sn
				local sRiseHi = (z + S.BridgeMaxRiseStuds - pz) / sn
				if raised then
					lo = math.max(lo, sRiseHi) -- the hand, MaxRise under the cue, is off the surface
				else
					lo, hi = math.max(lo, sRiseLo), math.min(hi, sRiseHi)
				end
			elseif pz - z < S.BridgeMinRiseStuds then
				return
			end
			clip(cur, lo, hi, scratch)
			for i = 1, #scratch, 2 do
				table.insert(runs, {
					s1 = scratch[i],
					s2 = scratch[i + 1],
					z = z,
					onRail = onRail,
					raised = raised,
				})
			end
		end
		local function build(raised: boolean, cushion: number)
			local e1, e2 = rayInside(px, py, bx, by, area.clothHx - cushion, area.clothHy - cushion)
			if e1 <= e2 then
				surfaceRuns({ e1 / c, e2 / c }, area.clothZ, false, raised)
			end
			local o1, o2 =
				rayInside(px, py, bx, by, area.railHx - railInset, area.railHy - railInset)
			if o1 <= o2 then
				local list = { o1 / c, o2 / c }
				local n1, n2 =
					rayInside(px, py, bx, by, area.clothHx + railInset, area.clothHy + railInset)
				if n1 <= n2 then
					subtract(list, n1 / c, n2 / c, out)
					list = table.clone(out)
				end
				surfaceRuns(list, area.railTopZ, true, raised)
			end
		end
		-- A ball frozen to a cushion with the cue along it leaves no cloth clear of the cushion:
		-- then the hand goes right against it.
		build(false, S.BridgeCushionInsetInches * s)
		if #runs == 0 then
			build(false, S.BridgeFrozenInsetInches * s)
		end
		if #runs == 0 then
			build(true, S.BridgeFrozenInsetInches * s)
		end
	end
	-- The hand's target height at `along` on a run: just above the surface, or for a raised
	-- run, up under the cue.
	local function handZ(run: Run, along: number): number
		if run.raised then
			return pz + along * sn - S.BridgeMaxRiseStuds + S.BridgeHandHeightStuds
		end
		return run.z + S.BridgeHandHeightStuds
	end

	-- 3. The regions each support allows the root in, and the fence, along a line.
	local foot = math.sqrt(body.HalfDepth * body.HalfDepth + body.HalfWidth * body.HalfWidth)
	local fenceX = area.fenceHx - foot - S.FenceMarginStuds
	local fenceY = area.fenceHy - foot - S.FenceMarginStuds
	local R, Tb = S.Rail, S.Table
	-- The root's pieces along the ray from (ox, oy) along b (u from UMinStuds on).
	local function region(mode: Mode, ox: number, oy: number, into: { number })
		table.clear(into)
		local uMin = S.UMinStuds
		local f1, f2 = rayInside(ox - area.fenceCx, oy, bx, by, fenceX, fenceY)
		if f1 > f2 then
			return
		end
		local lo, hi = math.max(uMin, f1), f2
		if lo > hi then
			return
		end
		local tmp = {}
		if mode == "stand" or mode == "lean" then
			local gap = S.FloorGapStuds
			local e1, e2 = rayInside(ox, oy, bx, by, area.railHx + gap, area.railHy + gap)
			tmp = { lo, hi }
			if e1 <= e2 then
				subtract({ lo, hi }, e1, e2, tmp)
			end
		elseif mode == "rail" then
			-- Between InStuds inside the rail's outer edge and OutStuds outside it.
			local i1, i2 =
				rayInside(ox, oy, bx, by, area.railHx + R.OutStuds, area.railHy + R.OutStuds)
			if i1 <= i2 then
				local band = { math.max(lo, i1), math.min(hi, i2) }
				if band[1] <= band[2] then
					local n1, n2 =
						rayInside(ox, oy, bx, by, area.railHx - R.InStuds, area.railHy - R.InStuds)
					if n1 <= n2 then
						subtract(band, n1, n2, tmp)
					else
						tmp = band
					end
				end
			end
		else
			local k = Tb.KneelInsetStuds
			local t1, t2 = rayInside(ox, oy, bx, by, area.clothHx - k, area.clothHy - k)
			if t1 <= t2 then
				tmp = { math.max(lo, t1), math.min(hi, t2) }
				if tmp[1] > tmp[2] then
					tmp = {}
				end
			end
		end
		for _, v in tmp do
			table.insert(into, v)
		end
	end

	-- What a surface under a plan point asks of anything leaning over it.
	local function surfaceAt(x: number, y: number): number
		if math.abs(x) <= area.clothHx and math.abs(y) <= area.clothHy then
			return area.clothZ + K.ClothStuds
		elseif math.abs(x) <= area.railHx and math.abs(y) <= area.railHy then
			return area.railTopZ + K.RailStuds
		end
		return -INF
	end
	-- The cue's nearest approach to a point (the drawn cue, tip at rest to butt).
	local function cueDistance(x: number, y: number, z: number): number
		local wx, wy, wz = x - px, y - py, z - pz
		local along = math.clamp((wx * bx + wy * by) * c + wz * sn, gR, gR + L)
		local qx, qy, qz = axisAt(along)
		return distance(x, y, z, qx, qy, qz)
	end

	-- 4. One candidate: support `mode`, side `side`, torso lean `a` (radians from vertical).
	-- Fills `feasible` with the root's allowed u (distance back along the cue from the strike
	-- point, on the side's line) and returns the body's frame at u = 0.
	local T = math.max(body.ShoulderHeight - body.WaistHeight, 1e-3)
	local shw = body.ShoulderHalfWidth
	local reachGrip = body.ArmReach * S.ArmMaxFraction
	local regionScratch, gripScratch, bridgeLoose, bridgeList = {}, {}, {}, {}
	type Frame = {
		mode: Mode,
		side: Side,
		a: number,
		lambda: number,
		yaw: number,
		fx: number,
		fy: number,
		blx: number,
		bly: number,
		ox: number, -- the root at u = 0
		oy: number,
		waistZ: number,
		k: number, -- the shoulders' reach ahead of the waist, plan
		cz: number, -- the shoulders' height
		reachBridge: number,
	}
	local function frameFor(mode: Mode, side: Side, a: number, lambda: number): Frame
		local psi = math.rad(side.TwistDegrees)
		local yaw = q.angle - psi
		local fx, fy = math.cos(yaw), math.sin(yaw)
		local k = T * math.sin(a)
		-- The chin (the shoulders' centre) sits ChinSideStuds left of the cue.
		local v = side.ChinSideStuds + k * math.sin(psi)
		local hip = ShooterStance.hipHeight(if mode == "lean" then "stand" else mode, body, area)
		local waistZ = body.WaistHeight + (hip - body.HipHeight)
		local natural = if mode == "stand" or mode == "lean"
			then S.ArmNaturalFraction + (S.ArmMaxFraction - S.ArmNaturalFraction) * lambda
			else S.ArmMaxFraction
		return {
			mode = mode,
			side = side,
			a = a,
			lambda = lambda,
			yaw = yaw,
			fx = fx,
			fy = fy,
			blx = -fy,
			bly = fx,
			ox = px + lx * v,
			oy = py + ly * v,
			waistZ = waistZ,
			k = k,
			cz = waistZ + T * math.cos(a),
			reachBridge = body.ArmReach * natural,
		}
	end
	-- A shoulder at plan offset (wb along b, wl along l) from the strike point at u = 0, height
	-- cz, moving back along b with u, against the line s -> (P + b s c, z0 + rise s) for s in
	-- [lo, hi]: the u for which it comes within r of some point of it. One interval, exactly:
	-- the union over s of [s c - wb - h(s), s c - wb + h(s)], its ends at the stretch's ends or
	-- where the slope is 0.
	local function lineRange(
		wb: number,
		wl: number,
		d0: number, -- cz - z0
		r: number,
		lo: number,
		hi: number,
		rise: number
	): (number, number)
		local rho2 = r * r - wl * wl
		if rho2 < 0 then
			return 1, 0
		end
		local rho = math.sqrt(rho2)
		if rise > 1e-9 then
			lo, hi = math.max(lo, (d0 - rho) / rise), math.min(hi, (d0 + rho) / rise)
		elseif math.abs(d0) > rho then
			return 1, 0
		end
		if lo > hi then
			return 1, 0
		end
		local function h(along: number): number
			local x = d0 - along * rise
			return math.sqrt(math.max(0, rho2 - x * x))
		end
		local low = math.min(lo * c - h(lo), hi * c - h(hi))
		local high = math.max(lo * c + h(lo), hi * c + h(hi))
		if rise > 1e-9 then
			local x = c * rho / math.sqrt(c * c + rise * rise)
			local s1 = (d0 - x) / rise
			if s1 > lo and s1 < hi then
				low = math.min(low, s1 * c - h(s1))
			end
			local s2 = (d0 + x) / rise
			if s2 > lo and s2 < hi then
				high = math.max(high, s2 * c + h(s2))
			end
		end
		return low - wb, high - wb
	end
	-- The stretch [lo, hi] of s on that line within r of the point (x, y, z), exactly (lo > hi:
	-- none).
	local function lineWindow(
		x: number,
		y: number,
		z: number,
		z0: number,
		rise: number,
		r: number
	): (number, number)
		local wx, wy, wz = x - px, y - py, z - z0
		local vx, vy, vz = bx * c, by * c, rise
		local vv = vx * vx + vy * vy + vz * vz
		local wv = wx * vx + wy * vy + wz * vz
		local disc = wv * wv - vv * (wx * wx + wy * wy + wz * wz - r * r)
		if disc < 0 then
			return 1, 0
		end
		local root = math.sqrt(disc)
		return (wv - root) / vv, (wv + root) / vv
	end
	-- A run's hand line: its height at s = 0 and its rise per unit s (flat on the surface, or
	-- a raised run's, a steady BridgeMaxRiseStuds under the cue).
	local function handLine(run: Run): (number, number)
		if run.raised then
			return pz - S.BridgeMaxRiseStuds + S.BridgeHandHeightStuds, sn
		end
		return run.z + S.BridgeHandHeightStuds, 0
	end
	-- The u for which the right shoulder reaches the grip window.
	local function gripRange(fr: Frame): (number, number)
		local rsx = fr.ox + fr.fx * fr.k - fr.blx * shw
		local rsy = fr.oy + fr.fy * fr.k - fr.bly * shw
		local wx, wy = rsx - px, rsy - py
		return lineRange(wx * bx + wy * by, wx * lx + wy * ly, fr.cz - pz, reachGrip, sLo, sHi, sn)
	end
	-- The u for which the left shoulder reaches a bridge run, into bridgeList.
	local function bridgeRanges(fr: Frame)
		table.clear(bridgeLoose)
		local lsx = fr.ox + fr.fx * fr.k + fr.blx * shw
		local lsy = fr.oy + fr.fy * fr.k + fr.bly * shw
		local wx, wy = lsx - px, lsy - py
		local wb, wl = wx * bx + wy * by, wx * lx + wy * ly
		for _, run in runs do
			local z0, rise = handLine(run)
			local lo, hi = lineRange(wb, wl, fr.cz - z0, fr.reachBridge, run.s1, run.s2, rise)
			if lo <= hi then
				table.insert(bridgeLoose, lo)
				table.insert(bridgeLoose, hi)
			end
		end
		union(bridgeLoose, bridgeList)
	end
	-- Fills `into` with the feasible u of this frame; returns whether there are any.
	local function feasible(fr: Frame, into: { number }): boolean
		region(fr.mode, fr.ox, fr.oy, regionScratch)
		if #regionScratch == 0 then
			table.clear(into)
			return false
		end
		local g1, g2 = gripRange(fr)
		if g1 > g2 then
			table.clear(into)
			return false
		end
		clip(regionScratch, g1, g2, gripScratch)
		if #gripScratch == 0 then
			table.clear(into)
			return false
		end
		bridgeRanges(fr)
		intersect(gripScratch, bridgeList, into)
		return #into > 0
	end

	-- Which of feasible()'s tests turns a frame down (for ShooterStance.trace).
	local function whyNot(fr: Frame): string
		region(fr.mode, fr.ox, fr.oy, regionScratch)
		if #regionScratch == 0 then
			return "no room for the root on this line"
		end
		local g1, g2 = gripRange(fr)
		if g1 > g2 then
			return "the grip is out of reach anywhere"
		end
		clip(regionScratch, g1, g2, gripScratch)
		if #gripScratch == 0 then
			return ("the grip is out of reach where the root may be (grip %.2f..%.2f, root %s)"):format(
				g1,
				g2,
				table.concat(regionScratch, " ")
			)
		end
		bridgeRanges(fr)
		if #bridgeList == 0 then
			return "no bridge run in reach anywhere (" .. #runs .. " runs)"
		end
		return ("the grip and the bridge never overlap (grip %s, bridge %s)"):format(
			table.concat(gripScratch, " "),
			table.concat(bridgeList, " ")
		)
	end

	-- The torso and head at a spot clear the table and the cue.
	local function clear(fr: Frame, u: number): boolean
		local rx, ry = fr.ox + bx * u, fr.oy + by * u
		for _, t in K.TorsoFractions do
			local x, y = rx + fr.fx * fr.k * t, ry + fr.fy * fr.k * t
			local z = fr.waistZ + (fr.cz - fr.waistZ) * t
			if z - K.TorsoHalfThicknessStuds < surfaceAt(x, y) then
				return false
			end
			if cueDistance(x, y, z) < K.CueTorsoStuds then
				return false
			end
		end
		local sa, ca = math.sin(fr.a), math.cos(fr.a)
		local hx = rx + fr.fx * (fr.k + K.HeadAboveShouldersStuds * sa)
		local hy = ry + fr.fy * (fr.k + K.HeadAboveShouldersStuds * sa)
		local hz = fr.cz + K.HeadAboveShouldersStuds * ca
		if hz - K.HeadRadiusStuds < surfaceAt(hx, hy) then
			return false
		end
		return cueDistance(hx, hy, hz) >= K.CueHeadStuds
	end

	-- 5. The search.
	local leanNat = math.rad(
		math.max(
			S.LeanMinDegrees,
			S.LeanNaturalDegrees
				- S.LeanUprightPerPitchDegree * (pitchDegrees - C.CueElevationDegrees)
		)
	)
	local ranges: { [string]: { number } } = {
		stand = { leanNat, math.max(leanNat, math.rad(S.LeanMaxDegrees)) },
		rail = {
			math.min(math.rad(R.LeanMinDegrees), leanNat),
			math.rad(R.LeanMaxDegrees),
		},
		table = {
			math.min(math.rad(Tb.LeanMinDegrees), leanNat),
			math.rad(Tb.LeanMaxDegrees),
		},
	}
	local costs = S.Costs
	local sides = (S.Sides :: any) :: { Side }
	type Pick = { fr: Frame, u: number, cost: number }
	local best: Pick? = nil
	local spots = {}
	for _, tier in { "stand", "rail", "table" } do
		local lo, hi = ranges[tier][1], ranges[tier][2]
		for _, side in sides do
			-- A side whose own cost, less the memory's discount, cannot beat the best so far is
			-- not worth solving.
			if best and side.Cost - costs.Sticky >= best.cost then
				continue
			end
			local function at(a: number): Frame
				local mode: Mode = tier :: Mode
				local lambda = 0
				if tier == "stand" then
					lambda = if hi > lo then (a - lo) / (hi - lo) else 0
					if lambda > 1e-6 then
						mode = "lean"
					end
				elseif hi > lo then
					lambda = (a - lo) / (hi - lo)
				end
				return frameFor(mode, side, a, lambda)
			end
			local fr = at(lo)
			if not feasible(fr, spots) then
				if not feasible(at(hi), spots) then
					if ShooterStance.trace then
						ShooterStance.trace(tier, side.Name, whyNot(at(hi)))
					end
					continue
				end
				local a0, a1 = lo, hi
				for _ = 1, S.LeanBisections do
					local mid = (a0 + a1) / 2
					if feasible(at(mid), spots) then
						a1 = mid
					else
						a0 = mid
					end
				end
				fr = at(a1)
				feasible(fr, spots)
			end
			-- The least lean, or a little more when that lets the root stand nearer its natural
			-- distance (a spot the least lean only just reaches can be far from it): the cheapest
			-- of a few leans on from the least, that clears the table.
			local sticky = 0
			if memory and memory.side == side.Name then
				local same = memory.mode == fr.mode
					or (memory.mode == "stand" or memory.mode == "lean")
						and (fr.mode == "stand" or fr.mode == "lean")
				if same then
					sticky = costs.Sticky
				end
			end
			local chosen: Frame? = nil
			local u, cost = 0, INF
			for _, extra in S.ExtraLeanDegrees do
				local a = fr.a + math.rad(extra)
				if
					a > hi + 1e-12 or (extra > 0 and math.abs(u - uPref) <= S.ExtraLeanFromStuds)
				then
					break
				end
				local f = if extra == 0 then fr else at(a)
				if extra ~= 0 and not feasible(f, spots) then
					continue
				end
				local v = nearest(spots, uPref)
				if v == nil or not clear(f, v) then
					continue
				end
				local c2 = side.Cost
					+ math.deg(f.a - lo) / costs.LeanDegrees
					+ math.abs(v - uPref) * costs.PerStudFromNatural
					- sticky
				if c2 < cost then
					chosen, u, cost = f, v, c2
				end
			end
			if chosen == nil then
				if ShooterStance.trace then
					ShooterStance.trace(tier, side.Name, "clearance")
				end
				continue
			end
			fr = chosen
			if best == nil or cost < best.cost then
				best = { fr = fr, u = u, cost = cost }
			end
		end
		if best then
			break
		end
	end
	local reached = best ~= nil
	-- Nothing reached (only a steep jump cue by a cushion, for a small body): stand naturally
	-- on the floor as near the natural distance as it allows, the hands as near as they get.
	local pick: Pick = best
		or (function(): Pick
			local fr = frameFor("stand", sides[1], ranges.stand[1], 0)
			region("stand", fr.ox, fr.oy, spots)
			return { fr = fr, u = nearest(spots, uPref) or uPref, cost = INF }
		end)()
	local fr, u = pick.fr, pick.u
	local rx, ry = fr.ox + bx * u, fr.oy + by * u
	local mode: Mode = fr.mode

	-- 6. The hands at the chosen spot. The grip just behind the hip, within the arm's reach.
	local rsx = rx + fr.fx * fr.k - fr.blx * shw
	local rsy = ry + fr.fy * fr.k - fr.bly * shw
	local gripAlong = math.clamp((u + S.GripBehindRootStuds) / c, sLo, math.max(sLo, sHi))
	do
		local wx, wy, wz = rsx - px, rsy - py, fr.cz - pz
		local s0 = (wx * bx + wy * by) * c + wz * sn
		local perp2 = wx * wx + wy * wy + wz * wz - s0 * s0
		-- The stretch of the cue within reach (at the edge of reach, as the least lean leaves it,
		-- rounding can put it a hair outside: then the nearest point).
		local h2 = reachGrip * reachGrip - perp2
		local lo, hi = 1, 0
		if h2 >= 0 then
			local h = math.sqrt(h2)
			lo, hi = math.max(sLo, s0 - h), math.min(sHi, s0 + h)
		end
		if lo <= hi then
			gripAlong = math.clamp(gripAlong, lo, hi)
		else
			gripAlong = math.clamp(s0, sLo, sHi)
		end
	end
	local gx0, gy0, gz0 = axisAt(gripAlong)
	local gripReachable = reached and distance(gx0, gy0, gz0, rsx, rsy, fr.cz) <= reachGrip + 1e-6

	-- The bridge: the reachable point on a run nearest the preferred one, the rail's own runs
	-- a little preferred while the hand was on the rail last frame.
	local lsx = rx + fr.fx * fr.k + fr.blx * shw
	local lsy = ry + fr.fy * fr.k + fr.bly * shw
	local bridgeRun: Run? = nil
	local bridgeAlong = sPrefB
	local bridgeReachable = false
	do
		local r = fr.reachBridge + 1e-6
		local bestScore = INF
		local wasRail = memory ~= nil and memory.onRail
		for _, run in runs do
			-- Along this run, the stretch within reach.
			local z0, rise = handLine(run)
			local w1, w2 = lineWindow(lsx, lsy, fr.cz, z0, rise, r)
			local lo, hi = math.max(run.s1, w1), math.min(run.s2, w2)
			local within = lo <= hi
			local along
			if within then
				along = math.clamp(sPrefB, lo, hi)
			else
				-- Out of reach: the run's point nearest the shoulder.
				local s0 = (w1 + w2) / 2
				along = math.clamp(if w1 <= w2 then s0 else sPrefB, run.s1, run.s2)
			end
			local score = math.abs(along - sPrefB) + (if within then 0 else 1e3)
			if run.onRail ~= wasRail then
				score += S.BridgeRailHysteresisInches * s
			end
			if score < bestScore then
				bestScore, bridgeRun, bridgeAlong, bridgeReachable = score, run, along, within
			end
		end
	end
	local bxp, byp, cueZ = axisAt(bridgeAlong)
	local handBridge: HandBridge
	if bridgeRun then
		handBridge = {
			x = bxp,
			y = byp,
			cueZ = cueZ,
			surfaceZ = bridgeRun.z,
			handZ = handZ(bridgeRun, bridgeAlong),
			onRail = bridgeRun.onRail,
			raised = bridgeRun.raised or cueZ - bridgeRun.z > S.BridgeMaxRiseStuds + 1e-6,
			alongStuds = bridgeAlong,
		}
	else
		-- No surface under the cue at all (never on a real table): the hand under the cue.
		handBridge = {
			x = bxp,
			y = byp,
			cueZ = cueZ,
			surfaceZ = area.clothZ,
			handZ = cueZ - S.BridgeMinRiseStuds,
			onRail = false,
			raised = true,
			alongStuds = bridgeAlong,
		}
	end
	bridgeReachable = bridgeReachable and reached

	-- A bridge nearer the ball than a full wind-up needs scales the drawn wind-up down so the
	-- tip never passes it. Cosmetic: the shot's power is never touched.
	local pullLimit = 1
	if S.LimitPullAtBridge then
		pullLimit = math.clamp((bridgeAlong - tipClear - gR) / C.CuePullBackStuds, 0, 1)
	end

	-- 7. The pull: the root never moves with it; the cue and the grip hand slide back along
	-- the axis together.
	local gap = gR + math.clamp(q.pull, 0, 1) * pullLimit * C.CuePullBackStuds
	local gx, gy, gz = axisAt(gap + (gripAlong - gR))

	-- The hanging foot on the rail: straight out past the rail's nearest outer edge.
	local hangX, hangY = rx, ry
	if mode == "rail" then
		local dx, dy = area.railHx - math.abs(rx), area.railHy - math.abs(ry)
		if dx < dy then
			hangX = (if rx < 0 then -1 else 1) * (area.railHx + R.HangOutStuds)
		else
			hangY = (if ry < 0 then -1 else 1) * (area.railHy + R.HangOutStuds)
		end
	end

	-- The idle spot: this one when it is on the floor clear of the barrier (by the release
	-- clearance, or the body's footprint at any facing), else straight out through the
	-- nearest side, and inside the fence.
	local grow = math.max(foot, area.releaseClearance) + S.SlopStuds
	local ix, iy = rx, ry
	do
		local hx, hy = area.barrierHx + grow, area.barrierHy + grow
		if math.abs(ix) < hx and math.abs(iy) < hy then
			if hx - math.abs(ix) < hy - math.abs(iy) then
				ix = (if ix < 0 then -1 else 1) * hx
			else
				iy = (if iy < 0 then -1 else 1) * hy
			end
		end
		-- Inside the fence (its box sits fenceCx along the table), unless that is inside the
		-- barrier, which always wins.
		local cx = area.fenceCx
		ix = math.clamp(ix, math.min(cx - fenceX, -hx), math.max(cx + fenceX, hx))
		iy = math.clamp(iy, -math.max(fenceY, hy), math.max(fenceY, hy))
	end

	local hipMode: Mode = if mode == "lean" then "stand" else mode
	local lift = ShooterStance.hipHeight(hipMode, body, area) - body.HipHeight
	return {
		mode = mode,
		side = fr.side.Name,
		rootX = rx,
		rootY = ry,
		rootZ = body.RootHeight + lift,
		yaw = fr.yaw,
		lean = if mode == "stand" then 0 else math.clamp(fr.lambda, 0, 1),
		torsoDegrees = math.deg(fr.a),
		twistDegrees = fr.side.TwistDegrees,
		supportZ = if mode == "rail"
			then area.railTopZ
			elseif mode == "table" then area.clothZ
			else 0,
		hangX = hangX,
		hangY = hangY,
		pitchDegrees = pitchDegrees,
		cueGapStuds = gap,
		pullLimit = pullLimit,
		grip = { x = gx, y = gy, z = gz },
		gripFromTipStuds = gripAlong - gR,
		gripReachable = gripReachable,
		bridgeReachable = bridgeReachable,
		handBridge = handBridge,
		idleX = ix,
		idleY = iy,
		idleZ = body.RootHeight,
		memory = { mode = mode, side = fr.side.Name, onRail = handBridge.onRail },
	}
end

--- Where the shooter stands once the shot is away: on the floor clear of the barrier (the
--- same spot when they shot standing), facing the table centre. Returns the root (x, y in
--- table studs, z above the floor) and the yaw (aim convention).
function ShooterStance.idle(st: Stance): (number, number, number, number)
	local x, y = st.idleX, st.idleY
	local yaw = if x * x + y * y > 1e-12 then math.atan2(-y, -x) else st.yaw
	return x, y, st.idleZ, yaw
end

return ShooterStance
