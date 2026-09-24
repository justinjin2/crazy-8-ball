--!strict
-- ShooterStance: where the shooter stands for a shot and how they reach the cue, as pure
-- geometry. The client poses the body from it and the server places the anchored root with
-- the very same function, so the two can never disagree about where a player shot from.
--
-- Units are TABLE STUDS: x and y along the table's length and width from its centre
-- (physics inches times StudsPerInch), heights above the FLOOR the table stands on (the
-- cloth is at Config.Table.SurfaceHeightStuds). Angles use the physics aim convention, so
-- Placement.aimVector(p, stance.yaw) is the facing in the world and
-- Placement.fromTableStuds turns any point here into a world position.
--
-- The shooter is right-handed: the right hand holds the cue and the left makes the bridge.
--
-- How a stance is found:
--   1. The drawn cue's axis leaves the strike point on the rendered ball and rises at the
--      visual pitch (CueClearance), exactly as CueStickBuilder draws it.
--   2. The body stands open, turned TwistDegrees right of the cue line, and far enough to
--      the cue's left that leaning in at the natural angle puts the chin over it.
--   3. The root backs off along the cue line to the natural distance (grip behind the hip,
--      bridge hand within comfortable reach) and then, if that is not far enough, to where
--      the root is at least the release clearance outside the barrier and the body's
--      footprint, at any facing, is clear of it (so turning to face the table after the shot
--      never swings it into the barrier). The fence caps it, but the barrier always wins. The
--      root never depends on the mode or on the Memory, so it does not jump when the pose
--      changes, and the server solving afresh puts it exactly where the client posed it; it
--      moves smoothly as the aim turns.
--   4. The mode is what reaches: a hand bridge standing, a hand bridge leaning further in,
--      the rake ("bridge"), or the rake with an automatic cue extension ("extension") when
--      even the rake's cue cannot reach the grip hand. Each boundary has hysteresis through
--      the Memory threaded from the last frame. A steep cue passing above the grip arm's
--      reach stands the torso up (Stance.UprightWhenGripOutOfReach).
--
-- The rake's contract with BridgeBuilder (Config.Bridge is the model's geometry): the cue
-- rests in the chosen notch at (headX, headY, headZ), headZ being that notch's rest height
-- with the head standing on the cloth; the model's shaft starts at that notch's shaft
-- attachment (the bridge frame's (0, ShaftAxisYStuds), which is (-X, ShaftAxisYStuds - Y)
-- from the notch, +X being the aim's right) and BridgeBuilder turns the model about the notch
-- so the shaft passes through (holdX, holdY, holdZ), where the off hand holds it. The rail
-- clearance of the shaft is worked out on that line before the small turn about the notch,
-- which moves the attachment almost only along the shaft itself. A shaft too short to reach
-- the hand gets extensionStuds more of it past its butt, which BridgeBuilder draws.

local Config = require(script.Parent.Config)
local CueShape = require(script.Parent.CueShape)
local Placement = require(script.Parent.Placement)

local ShooterStance = {}

-- Measured from the rest rig (AvatarPose.measureBody), studs; heights above the floor.
export type Body = {
	RootHeight: number, -- root centre
	WaistHeight: number, -- the hip line the torso leans about
	ShoulderHeight: number, -- shoulder pivots, standing
	ShoulderHalfWidth: number, -- centre line to either shoulder pivot
	ArmReach: number, -- shoulder pivot to the grip point, arm straight
	HalfWidth: number, -- the body's footprint, across the shoulders
	HalfDepth: number, -- ...and front to back
}

-- The table's surroundings, table studs (ShooterStance.area).
export type Area = {
	clothHx: number, -- cushion noses
	clothHy: number,
	railHx: number, -- outer edge of the rail
	railHy: number,
	barrierHx: number, -- the invisible wall around the table
	barrierHy: number,
	fenceHx: number, -- inner faces of the match fence
	fenceHy: number,
	clothZ: number, -- cloth height above the floor
	railTopZ: number, -- rail top height above the floor
	releaseClearance: number, -- the root stays at least this far outside the barrier
}

export type Mode = "stand" | "lean" | "bridge" | "extension"

-- Threaded from one frame's stance into the next, for hysteresis.
export type Memory = { mode: Mode, extensionStuds: number, onRail: boolean }

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

-- The off hand's bridge, in stand and lean.
export type HandBridge = {
	x: number, -- under the cue
	y: number,
	cueZ: number, -- the cue's axis height there
	surfaceZ: number, -- the cloth, or the rail top when bridging on the rail
	onRail: boolean,
}

-- The mechanical bridge, in bridge and extension. See the header for the contract.
export type Rake = {
	headX: number, -- where the cue rests in the notch, on the cue line
	headY: number,
	headZ: number, -- that notch's rest height with the head on the cloth
	notch: string, -- Config.Bridge.Notches[i].Name
	holdX: number, -- where the off hand holds the shaft
	holdY: number,
	holdZ: number,
	length: number, -- shaft attachment to the hand, plus the handle beyond it
	-- The cue's height minus the notch's where no notch fits within NotchToleranceStuds
	-- (positive: the cue floats above the notch); 0 when it rests in one.
	hover: number,
	cueZ: number, -- the cue's axis height over the head (within the tolerance of headZ, or hover)
	-- The shaft's automatic extension past its butt (studs, whole LengthStepStuds): 0 while
	-- the shaft itself reaches the hand, else the least that does, up to Rake.MaxExtensionStuds.
	extensionStuds: number,
	-- How far the hold had to slide toward the head because even the longest extension does
	-- not reach where the hand wanted it; 0 normally.
	slideStuds: number,
	holdReachable: boolean, -- the off hand can reach the hold
	-- The head stands on the cloth: the notch and the head's centre line (where the shaft
	-- attaches) HeadInsetInches clear of the cushions. False only when the cloth behind the
	-- ball is too short even for the resting tip; headZ is then still the cloth's, and the
	-- shaft's rail clearance is not promised.
	onCloth: boolean,
}

export type Stance = {
	mode: Mode,
	rootX: number, -- the root's centre, table studs
	rootY: number,
	rootZ: number, -- above the floor (the body's RootHeight)
	yaw: number, -- facing, aim-angle convention
	lean: number, -- 0..1 in stand/lean: how far past the natural lean toward the most (0 otherwise)
	torsoDegrees: number, -- torso lean from vertical
	-- How much further back than natural the barrier put the root (negative when the fence
	-- holds it closer).
	overhangStuds: number,
	fenceClamped: boolean, -- the fence held the root in (the barrier still wins)
	pitchDegrees: number, -- the drawn pitch used (clamped)
	cueGapStuds: number, -- tip to strike point along the axis, with the pull
	extensionStuds: number, -- 0 unless mode is "extension"
	-- How far past the cue's butt the grip hand is (negative: spare). -math.huge when the cue
	-- passes out of the grip arm's reach altogether (a steep cue far above), which no
	-- extension can fix: then gripReachable is false.
	shortfallStuds: number,
	pullLimit: number, -- the drawn wind-up is scaled by this so the tip never passes the bridge
	grip: Point, -- the grip hand, on the cue's axis, moving with the pull
	gripFromTipStuds: number, -- along the cue from the tip at rest (can be past the butt)
	gripReachable: boolean, -- the grip arm reaches it (false at MaxExtensionStuds)
	handBridge: HandBridge?,
	rake: Rake?,
	memory: Memory,
}

type Notch = { Name: string, X: number, Y: number }

local function boxDistance(x: number, y: number, hx: number, hy: number): number
	local ex, ey = math.max(0, math.abs(x) - hx), math.max(0, math.abs(y) - hy)
	return math.sqrt(ex * ex + ey * ey)
end

-- Where a ray from (ox, oy) along (dx, dy) is inside the box of half extents (hx, hy): the
-- distances it enters and leaves, from 0 on (enter > leave when it never is). The rake's
-- head needs this rather than Placement.rayExit, because the strike point of a ball frozen
-- to a cushion can start inside the cushion's inset and still head into the table.
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
	local enter, leave = slab(ox, dx, hx, 0, math.huge)
	return slab(oy, dy, hy, enter, leave)
end

local function distance(ax: number, ay: number, az: number, bx: number, by: number, bz: number)
	local dx, dy, dz = ax - bx, ay - by, az - bz
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- The surroundings of a table whose match has `teamSize` players a side.
function ShooterStance.area(teamSize: number): Area
	local T = Config.Table
	local s = T.StudsPerInch
	local barrierHx, barrierHy = Placement.barrierHalfExtents()
	local fenceHx, fenceHy = Placement.fenceHalfExtents(teamSize)
	return {
		clothHx = T.LengthInches / 2 * s,
		clothHy = T.WidthInches / 2 * s,
		railHx = (T.LengthInches / 2 + T.RailWidthInches) * s,
		railHy = (T.WidthInches / 2 + T.RailWidthInches) * s,
		barrierHx = barrierHx,
		barrierHy = barrierHy,
		fenceHx = fenceHx,
		fenceHy = fenceHy,
		clothZ = T.SurfaceHeightStuds,
		railTopZ = T.SurfaceHeightStuds + T.RailTopInches * s,
		releaseClearance = Config.Multiplayer.Barrier.ReleaseClearanceStuds,
	}
end

--- The stance for one frame. Deterministic: the same input always gives the same stance.
function ShooterStance.solve(q: Input): Stance
	local S = Config.Stance
	local C = Config.Cue
	local s = Config.Table.StudsPerInch
	local body, area, memory = q.body, q.area, q.memory
	local remembered: Mode? = if memory then memory.mode else nil
	local L = q.cueLengthStuds or C.CueLengthStuds

	-- 1. The cue's axis: from the strike point P back along b, rising at the pitch.
	local pitchDegrees = math.clamp(q.pitchDegrees, C.CueElevationDegrees, C.VisualPitchMaxDegrees)
	local theta = math.rad(pitchDegrees)
	local c, sn = math.cos(theta), math.sin(theta)
	local tn = sn / c
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

	-- 2. The body's frame, and how far left of the cue line the root stands so the chin
	-- ends up over the cue at the natural lean (body only: the same whatever the shot).
	local psi = math.rad(S.TwistDegrees)
	local yaw = q.angle - psi
	local fx, fy = math.cos(yaw), math.sin(yaw) -- facing
	local blx, bly = -fy, fx -- the body's left
	local T = math.max(body.ShoulderHeight - body.WaistHeight, 1e-3)
	local shw = body.ShoulderHalfWidth
	local leanMax = math.rad(S.LeanMaxDegrees)
	-- The most the torso may lean before the shoulders dip toward the rail top.
	local aRail = math.acos(
		math.clamp((area.railTopZ + S.RailShoulderClearanceStuds - body.WaistHeight) / T, -1, 1)
	)
	local side = T * math.sin(math.min(math.rad(S.LeanNaturalDegrees), aRail)) * math.sin(psi)
		+ S.ChinSideStuds
	local aLo0 = math.rad(
		math.max(
			S.LeanMinDegrees,
			S.LeanNaturalDegrees
				- S.LeanUprightPerPitchDegree * (pitchDegrees - C.CueElevationDegrees)
		)
	)

	-- 3. The hand bridge's point on the cue line (plan distance dB from P), on the cloth or,
	-- near the cushion, on the rail.
	local tNose = Placement.rayExit(px, py, bx, by, area.clothHx, area.clothHy)
	local tOuter = Placement.rayExit(px, py, bx, by, area.railHx, area.railHy)
	local tipClear = S.BridgeTipClearInches * s
	local dCloth = math.max(S.BridgeFromBallInches * s - back, gF + tipClear) * c
	local dB = dCloth
	local threshold = tNose
		- S.BridgeCushionInsetInches * s
		- (if memory and memory.onRail then S.BridgeRailHysteresisInches * s else 0)
	local onRail = dB > threshold
	local surface = area.clothZ
	local railInset = S.RailBridgeInsetInches * s
	local railFar = math.max(tNose + railInset, tOuter - railInset) -- the rail bridge's limits
	if onRail then
		dB = math.clamp(dB, tNose + railInset, railFar)
		surface = area.railTopZ
	end
	local function limitPull(bridgeAlong: number): number
		if not S.LimitPullAtBridge then
			return 1
		end
		return math.clamp((bridgeAlong - tipClear - gR) / C.CuePullBackStuds, 0, 1)
	end
	local pullLimit = limitPull(dB / c)

	-- 4. The natural distance from P back to the root: the grip just behind the hip, unless
	-- the bridge hand's comfortable reach wants the body closer. That reach is measured to a
	-- bridge placed without the rail choice, which has hysteresis (the Memory): the root must
	-- not depend on the Memory, nor jump when the choice flips. So it is the cloth bridge's
	-- distance, but never past where a rail bridge stops short of the rail's outer edge, at
	-- the cloth's height; both move smoothly with the aim. Whether the hand reaches the bridge
	-- where it really is, rail or cloth, is step 6.
	local sLo = gR + S.GripMinFromTipFraction * L
	local sCap = if sn > 1e-6
		then (body.ShoulderHeight + S.GripAboveShoulderStuds - pz) / sn
		else math.huge
	local sGrip0 = math.min(gR + L * (1 - S.GripFromButtFraction), math.max(sLo, sCap))
	local aN = math.min(aLo0, aRail)
	local forward = shw * math.sin(psi) + T * math.sin(aN) * math.cos(psi)
	local across = side + shw * math.cos(psi) - T * math.sin(aN) * math.sin(psi)
	local drop = body.WaistHeight + T * math.cos(aN) - (area.clothZ + S.BridgeHandHeightStuds)
	local comfortable = body.ArmReach * S.ArmNaturalFraction
	local F0 = forward
		+ math.sqrt(math.max(0, comfortable * comfortable - across * across - drop * drop))
	local dNat = math.min(sGrip0 * c - S.GripBehindRootStuds, math.min(dCloth, railFar) + F0)

	-- 5. The barrier and the fence, for the body's footprint at ANY facing: its half diagonal,
	-- so turning on the spot (ShooterStance.idle) never swings it into either.
	local foot = math.sqrt(body.HalfDepth * body.HalfDepth + body.HalfWidth * body.HalfWidth)
	local grow = math.max(foot, area.releaseClearance)
	local ox, oy = px + lx * side, py + ly * side
	local dExit = Placement.rayExit(ox, oy, bx, by, area.barrierHx + grow, area.barrierHy + grow)
		+ S.SlopStuds
	local dFence = Placement.rayExit(
		ox,
		oy,
		bx,
		by,
		area.fenceHx - foot - S.FenceMarginStuds,
		area.fenceHy - foot - S.FenceMarginStuds
	)
	local d = math.max(dNat, dExit)
	local fenceClamped = false
	if d > dFence then
		d = math.max(dFence, dExit)
		fenceClamped = true
	end
	local rx, ry = ox + bx * d, oy + by * d

	-- 6. Can the off hand reach the hand bridge, standing or leaning further in?
	local nearRail = boxDistance(rx, ry, area.railHx, area.railHy) < T * math.sin(leanMax) + shw
	local cap = if nearRail then aRail else leanMax
	local aLo = math.min(aLo0, cap)
	local function tilt(lambda: number): number
		return math.min(aLo + lambda * (leanMax - aLo), cap)
	end
	local hx, hy, hz = px + bx * dB, py + by * dB, surface + S.BridgeHandHeightStuds
	local slack = if remembered == "bridge" or remembered == "extension"
		then S.ModeHysteresisStuds
		else 0
	-- Does the left shoulder, with the torso leaning `a` from vertical, reach the bridge?
	local function bridgeWithin(a: number, reach: number): boolean
		local k = T * math.sin(a)
		return distance(
			rx + fx * k + blx * shw,
			ry + fy * k + bly * shw,
			body.WaistHeight + T * math.cos(a),
			hx,
			hy,
			hz
		) <= reach - slack
	end
	local function handReaches(lambda: number): boolean
		return bridgeWithin(
			tilt(lambda),
			body.ArmReach
				* (S.ArmNaturalFraction + (S.ArmMaxFraction - S.ArmNaturalFraction) * lambda)
		)
	end
	local mode: Mode = "bridge"
	local lambda = 0
	if handReaches(0) then
		mode = "stand"
	elseif handReaches(1) then
		mode = "lean"
		local lo, hi = 0, 1
		for _ = 1, S.LeanBisections do
			local mid = (lo + hi) / 2
			if handReaches(mid) then
				hi = mid
			else
				lo = mid
			end
		end
		lambda = hi
	end

	-- 7. The grip: where the right hand can hold the cue, and whether the butt is long enough.
	local reach = body.ArmReach * S.ArmMaxFraction
	local sHi0 = gR + L - S.GripButtEndStuds
	local sPref =
		math.clamp((d + S.GripBehindRootStuds) / c, sLo, math.max(sLo, math.min(sHi0, sCap)))
	local torso, shx, shy, shz, sSh, rho, shortfall = 0, 0, 0, 0, 0, 0, 0
	-- The right shoulder with the torso leaning `a` from vertical, and where the cue passes it.
	local function shoulderAt(a: number)
		torso = a
		local k = T * math.sin(a)
		shx, shy = rx + fx * k - blx * shw, ry + fy * k - bly * shw -- the right shoulder
		shz = body.WaistHeight + T * math.cos(a)
		local wx, wy, wz = shx - px, shy - py, shz - pz
		sSh = (wx * bx + wy * by) * c + wz * sn -- its nearest point along the axis
		rho = math.sqrt(math.max(0, wx * wx + wy * wy + wz * wz - sSh * sSh))
		shortfall = if rho <= reach
			then (sSh - math.sqrt(reach * reach - rho * rho)) - sHi0
			else -math.huge
	end
	local function leanOf(m: Mode): number
		return if m == "bridge" then math.min(math.rad(S.Rake.LeanDegrees), cap) else tilt(lambda)
	end
	local margin = S.ExtensionMarginStuds
	local function needsExtension(): boolean
		return if remembered == "extension" then shortfall + margin > 0 else shortfall > 0
	end
	local function fromShoulder(along: number): number
		local gx, gy, gz = axisAt(along)
		return distance(gx, gy, gz, shx, shy, shz)
	end
	-- The grip in mode `m` with the torso at `a` (nil: the mode's own lean). A hand bridge
	-- whose cue is too short for the grip hand becomes the rake, and the rake's cue gets the
	-- extension. Returns the mode, the extension, the grip along the cue from the strike point
	-- and whether the hand reaches it.
	local function gripWith(m: Mode, a: number?): (Mode, number, number, boolean)
		shoulderAt(a or leanOf(m))
		if (m == "stand" or m == "lean") and needsExtension() then
			m = "bridge"
			shoulderAt(a or leanOf(m))
		end
		local E = 0
		if m == "bridge" and needsExtension() then
			E = math.min(shortfall + margin, S.MaxExtensionStuds)
			m = "extension"
		end
		local sHi = sHi0 + E
		local w = if rho <= reach then math.sqrt(reach * reach - rho * rho) else 0
		local windowLo, windowHi = math.max(sLo, sSh - w), math.min(sHi, sSh + w)
		local along
		if fromShoulder(sPref) <= reach then
			along = sPref
		elseif rho <= reach and windowLo <= windowHi then
			along = math.clamp(sPref, windowLo, windowHi)
		else
			along = math.clamp(sSh, sLo, sHi)
		end
		return m, E, along, fromShoulder(along) <= reach + 1e-9 and E < S.MaxExtensionStuds
	end
	local handMode: Mode = mode
	local chosen: Mode, E, sGrip, gripReachable = gripWith(handMode, nil)
	mode = chosen
	-- A steep cue passing above the grip arm's reach at this lean: try the torso upright, the
	-- highest shoulder, and keep whichever shoulder is nearer the cue line. Upright, the off
	-- hand may no longer reach its hand bridge even fully stretched; then it takes the rake,
	-- but only when that puts the grip hand on the cue: swapping a hand bridge for the rake
	-- and still missing the grip is worse than the lean (and would bring the rake out for a
	-- ball at the shooter's own cushion, between two hand bridges). The root stays where it
	-- is: it never depends on the mode or the torso.
	if not gripReachable and S.UprightWhenGripOutOfReach then
		local leaning, raking = rho, mode == "bridge" or mode == "extension"
		local upright: Mode = "bridge"
		if handMode ~= "bridge" and bridgeWithin(0, body.ArmReach * S.ArmMaxFraction) then
			upright = "stand"
		end
		local m: Mode, e, along, reached = gripWith(upright, 0)
		if rho < leaning and (reached or raking == (m == "bridge" or m == "extension")) then
			mode, E, sGrip, gripReachable = m, e, along, reached
			lambda = 0
		else
			mode, E, sGrip, gripReachable = gripWith(handMode, nil) -- back to the lean
		end
	end

	-- 8. The rake: its head, the notch, and where the off hand holds it. Before the pull,
	-- because a head that cannot sit clear of a full wind-up limits it.
	local rake: Rake? = nil
	if mode == "bridge" or mode == "extension" then
		local B, K = Config.Bridge, S.Rake
		-- Plan distances from P to the head: at the default spot or, further back, clear of the
		-- tip at a full wind-up (with a 1.3 stud wind-up that always wins). A raised cue is
		-- above every notch there, so the head comes in toward the ball until a notch meets
		-- it, but never onto the resting tip; the drawn wind-up is then cut short (pullLimit)
		-- so the tip never reaches the head. The head also stands on the cloth: both the notch
		-- the cue rests in and the head's centre line (where the shaft attaches, X to the
		-- cue's left) at least HeadInsetInches in from every cushion. Cloth behind the ball too
		-- short even for the resting tip (a ball near a cushion, the shot glancing away along
		-- it) leaves the head off the cloth, and says so.
		local full = (gF + tipClear) * c
		local restTip = (gR + tipClear) * c
		local preferred = B.DistanceBehindBallStuds - back
		local inset = K.HeadInsetInches * s
		local clothX, clothY = area.clothHx - inset, area.clothHy - inset
		local restIn, restOut = rayInside(px, py, bx, by, clothX, clothY)
		-- Each notch in turn; the best stands on the cloth, then rests the cue within the
		-- tolerance (as far back as it can, cutting the wind-up least), else comes nearest the
		-- cue's height (the least hover).
		local best: Notch? = nil
		local bestH, bestErr, bestFits, bestOnCloth = 0, 0, false, false
		for _, notch in ipairs(B.Notches) do
			local centreIn, centreOut =
				rayInside(px + lx * notch.X, py + ly * notch.X, bx, by, clothX, clothY)
			local enter, leave = math.max(restIn, centreIn), math.min(restOut, centreOut)
			local lo = math.max(restTip, enter)
			local hi = math.max(math.min(math.max(full, preferred), leave), lo)
			local onCloth = lo <= leave + 1e-9
			local z = area.clothZ + B.PivotHeightStuds + notch.Y
			-- The cue meets this notch exactly at `exact`, and rests in it within `band` of that.
			local exact = (z - pz) / tn
			local band = K.NotchToleranceStuds / tn
			local furthest = math.min(hi, exact + band)
			local fits = furthest >= math.max(lo, exact - band)
			local h = if fits then furthest else math.clamp(exact, lo, hi)
			local err = pz + h * tn - z
			local better
			if best == nil or onCloth ~= bestOnCloth then
				better = best == nil or onCloth
			elseif fits ~= bestFits then
				better = fits
			elseif fits and math.abs(h - bestH) > 1e-9 then
				better = h > bestH
			else
				better = math.abs(err) < math.abs(bestErr)
			end
			if better then
				best, bestH, bestErr, bestFits, bestOnCloth = notch, h, err, fits, onCloth
			end
		end
		local notch = assert(best, "Config.Bridge.Notches is empty")
		local h = bestH
		pullLimit = limitPull(h / c)
		local headX, headY = px + bx * h, py + by * h
		local headZ = area.clothZ + B.PivotHeightStuds + notch.Y
		-- The shaft attachment: the bridge's +X is the aim's right, (ay, -ax).
		local attachX, attachY = headX - notch.X * ay, headY + notch.X * ax
		local attachZ = headZ + B.ShaftAxisYStuds - notch.Y
		local holdX = rx + fx * K.HoldForwardStuds + blx * shw
		local holdY = ry + fy * K.HoldForwardStuds + bly * shw
		local holdZ = body.ShoulderHeight - K.HoldBelowShoulderStuds
		-- Raise the hand until the shaft's underside clears the rail top where it first
		-- crosses it (the shaft grown by its radius, as the cue is in CueClearance). The shaft
		-- rises toward the hand, so the first crossing is the lowest. A head off the cloth is
		-- already at the cushion, where no hand height can help.
		local vx, vy = holdX - attachX, holdY - attachY
		local run = math.sqrt(vx * vx + vy * vy)
		if run > 1e-6 and bestOnCloth then
			local r = B.ShaftButtRadiusStuds
			local tIn = Placement.rayExit(
				attachX,
				attachY,
				vx / run,
				vy / run,
				area.clothHx - r,
				area.clothHy - r
			)
			if tIn < run and tIn > r then
				-- The least slope k with attachZ + k*tIn - r*sqrt(1 + k^2) at the clearance.
				local D = area.railTopZ + K.RailClearanceInches * s - attachZ
				local k = (tIn * D + r * math.sqrt(math.max(0, tIn * tIn + D * D - r * r)))
					/ (tIn * tIn - r * r)
				holdZ = math.max(holdZ, attachZ + k * run)
			end
		end
		-- The hand holds the shaft where the body wants it. A shaft too short to get there
		-- (a far ball, the body back at the near rail) gets an extension past its butt, like
		-- the cue's: the least whole number of LengthStepStuds that leaves the handle showing
		-- beyond the hand, up to Rake.MaxExtensionStuds. Only past that does the hand slide in
		-- toward the head.
		local shaftEnd = B.ShaftStartStuds + B.ShaftLengthStuds
		local hx3, hy3, hz3 = holdX - attachX, holdY - attachY, holdZ - attachZ
		local held = math.sqrt(hx3 * hx3 + hy3 * hy3 + hz3 * hz3)
		local need = held + K.HandleBeyondHandStuds - shaftEnd
		local extension = 0
		if need > 0 then
			local step = C.Extension.LengthStepStuds
			extension =
				math.min(math.max(1, math.ceil(need / step - 1e-9)) * step, K.MaxExtensionStuds)
		end
		local most = shaftEnd + extension - K.HandleBeyondHandStuds
		local slide = 0
		if held > most + 1e-9 then
			local k = most / held
			holdX, holdY, holdZ = attachX + hx3 * k, attachY + hy3 * k, attachZ + hz3 * k
			slide, held = held - most, most
		end
		local k = T * math.sin(torso)
		local leftShoulder = distance(
			rx + fx * k + blx * shw,
			ry + fy * k + bly * shw,
			body.WaistHeight + T * math.cos(torso),
			holdX,
			holdY,
			holdZ
		)
		rake = {
			headX = headX,
			headY = headY,
			headZ = headZ,
			notch = notch.Name,
			holdX = holdX,
			holdY = holdY,
			holdZ = holdZ,
			length = held + K.HandleBeyondHandStuds,
			hover = if bestFits then 0 else bestErr,
			cueZ = pz + h * tn,
			extensionStuds = extension,
			slideStuds = slide,
			holdReachable = leftShoulder <= reach + 1e-9,
			onCloth = bestOnCloth,
		}
	end

	-- 9. The pull: the root never moves with it; the cue and the grip hand slide back along
	-- the axis together.
	local gap = gR + math.clamp(q.pull, 0, 1) * pullLimit * C.CuePullBackStuds
	local gx, gy, gz = axisAt(gap + (sGrip - gR))

	return {
		mode = mode,
		rootX = rx,
		rootY = ry,
		rootZ = body.RootHeight,
		yaw = yaw,
		lean = if mode == "stand" or mode == "lean" then lambda else 0,
		torsoDegrees = math.deg(torso),
		overhangStuds = d - dNat,
		fenceClamped = fenceClamped,
		pitchDegrees = pitchDegrees,
		cueGapStuds = gap,
		extensionStuds = E,
		shortfallStuds = shortfall,
		pullLimit = pullLimit,
		grip = { x = gx, y = gy, z = gz },
		gripFromTipStuds = sGrip - gR,
		gripReachable = gripReachable,
		handBridge = if mode == "stand" or mode == "lean"
			then { x = hx, y = hy, cueZ = pz + dB * tn, surfaceZ = surface, onRail = onRail }
			else nil,
		rake = rake,
		memory = { mode = mode, extensionStuds = E, onRail = onRail },
	}
end

--- Where the shooter stands once the shot is away: the same spot, facing the table centre.
--- Returns the root (x, y in table studs, z above the floor) and the yaw (aim convention).
function ShooterStance.idle(st: Stance): (number, number, number, number)
	local x, y = st.rootX, st.rootY
	local yaw = if x * x + y * y > 1e-12 then math.atan2(-y, -x) else st.yaw
	return x, y, st.rootZ, yaw
end

return ShooterStance
