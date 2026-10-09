--!strict
-- Aim: a dry trace along the cue ball's launch direction (Cue.launchDirection), with the
-- collision geometry shared with the simulation. While Config.Cue.SideSpinBendsPath is off
-- side spin neither squirts nor swerves, so the launch is the aim and the path to first
-- contact is straight: the trace is exact for any spin. Throw after contact is not traced.
--
-- A shot that leaves the cloth (a raised cue with enough power) is traced through its hops
-- with the same strike and slate bounce as the simulation (Cue.strike, Flight): each arc is
-- walked in short steps for a ball it meets in the air, a cushion it hits, or a cushion it
-- flies over ("off"). Balls it clears are ignored, and every touchdown is listed so the
-- guideline can mark it. From the last touchdown the flat trace takes over.
--
-- A launch ability (Black Flash, Fire Shot: Config.Ults.<id>.LaunchSpeedScale) multiplies the
-- cue ball's motion along the cloth and its spin before it moves; `launchScale` traces a jump
-- the same way. Aim.bounceTrace is Fire Shot's line: the same path on, mirrored off every
-- cushion to the first ball or a pocket.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Collision = require(script.Parent.Collision)
local Cue = require(script.Parent.Cue)
local Flight = require(script.Parent.Flight)
local Simulation = require(script.Parent.Simulation)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type State = Simulation.State
type Pocket = TableGeometry.Pocket

local Aim = {}

export type Trace = {
	contact: "ball" | "rail" | "off" | "none", -- off: flies over a cushion, off the table
	-- Cue ball start and the ghost position (where its centre is at first contact).
	startX: number,
	startY: number,
	ghostX: number,
	ghostY: number,
	distance: number,
	-- For a ball contact: which ball and where it will head.
	objectId: number?,
	objectDirX: number,
	objectDirY: number,
	-- Where the cue ball heads after contact (tangent line for a ball, reflection for a rail).
	-- Zero length for a dead-straight ball hit (stop shot).
	cueDirX: number,
	cueDirY: number,
	-- How much of the cue ball's speed each ball carries away from a ball contact, 0..1: the
	-- object ball takes cos(cut angle) along the line of centres, the cue ball sin(cut angle)
	-- along the tangent line. A full hit is (1, 0), a thin cut close to (0, 1). The guideline
	-- scales its two short lines by these, as the classic phone pool games do. A rail
	-- contact is (0, 1): the cue ball keeps its speed.
	objectShare: number,
	cueShare: number,
	-- Where the cue ball comes down on the way (a jump shot), in order. Empty on the cloth.
	landings: { { x: number, y: number } },
	airborne: boolean, -- the contact above happens in the air
	-- Each arc of a jump shot, in order: where it starts (z is the height off the cloth) and
	-- how it moves, and how long it flies (to its touchdown, or to the contact in the air).
	-- Position at t: x + vx t, y + vy t, z + vz t - g t^2 / 2. Empty on the cloth.
	hops: { Hop },
}

export type Hop = {
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number,
	vz: number,
	seconds: number,
}

-- Fire Shot's aim line (Aim.bounceTrace).
export type BounceTrace = {
	-- The cue ball's path on the cloth: where it starts rolling (a jump shot's last touchdown),
	-- then each cushion bounce, then where the line ends. Empty when it never rolls (a jump
	-- that meets something in the air, or no cue ball).
	points: { { x: number, y: number } },
	-- "ball": it meets a ball (the last point is the ghost); "pocket": its centre drops into
	-- one; "limit": the length or bounce cap; "air": a jump that meets a ball or a cushion,
	-- or flies off, before it lands; "none": no cue ball.
	ending: "ball" | "pocket" | "limit" | "air" | "none",
	bounces: number, -- cushions on the way
	-- For "ball" (and "air" on a ball): which ball, where it heads and where the cue ball heads
	-- after, as Aim.trace gives them.
	objectId: number?,
	objectDirX: number,
	objectDirY: number,
	cueDirX: number,
	cueDirY: number,
	pocket: number?, -- for "pocket": its id
	flight: Trace?, -- a jump shot's flight (Aim.trace's hops and landings), else nil
}

local FAR = 1e6
-- Step along an arc (inches of travel) and the bisection that pins a contact down.
local ARC_STEP_INCHES = 0.1
local ARC_BISECTIONS = 16
local MAX_HOPS = 8

-- The object ball's and the cue ball's directions after a contact, from the line of centres
-- in plan (a contact in the air is drawn on the cloth like any other).
local function ballContact(trace: Trace, hitBall: Ball, dx: number, dy: number)
	trace.contact = "ball"
	trace.objectId = hitBall.id
	local nx, ny = hitBall.x - trace.ghostX, hitBall.y - trace.ghostY
	local len = math.sqrt(nx * nx + ny * ny)
	if len > 1e-9 then
		nx, ny = nx / len, ny / len
	end
	trace.objectDirX, trace.objectDirY = nx, ny
	-- Cue ball keeps the component of its motion perpendicular to the line of centres.
	local along = dx * nx + dy * ny
	local tx, ty = dx - along * nx, dy - along * ny
	local tlen = math.sqrt(tx * tx + ty * ty)
	if tlen < 1e-3 then
		trace.cueDirX, trace.cueDirY = 0, 0
	else
		trace.cueDirX, trace.cueDirY = tx / tlen, ty / tlen
	end
	trace.objectShare = math.clamp(along, 0, 1)
	trace.cueShare = if tlen < 1e-3 then 0 else math.min(tlen, 1)
end

local function railContact(trace: Trace, railNx: number, railNy: number, dx: number, dy: number)
	trace.contact = "rail"
	local along = dx * railNx + dy * railNy
	trace.cueDirX = dx - 2 * along * railNx
	trace.cueDirY = dy - 2 * along * railNy
	trace.cueShare = 1
end

-- Walk the cue ball's hops. Returns true if something was met in the air (the trace is
-- then complete); otherwise `probe` is left on the cloth where it settles, for the flat
-- trace to carry on from.
local function traceFlight(state: State, probe: Ball, trace: Trace): boolean
	local R = Config.Balls.RadiusInches
	local g = Config.Physics.Gravity
	local clear = Config.Table.CushionHeightInches
	local geometry = state.geometry
	for _ = 1, MAX_HOPS do
		local speed = math.sqrt(probe.vx * probe.vx + probe.vy * probe.vy)
		local flight = Flight.landingTime(probe.z, probe.vz)
		local x0, y0, z0, vz0 = probe.x, probe.y, probe.z, probe.vz
		local function at(t: number): (number, number, number)
			return x0 + probe.vx * t, y0 + probe.vy * t, z0 + vz0 * t - 0.5 * g * t * t
		end
		local hop: Hop =
			{ x = x0, y = y0, z = z0, vx = probe.vx, vy = probe.vy, vz = vz0, seconds = flight }
		table.insert(trace.hops, hop)
		-- What the ball meets at time t: a ball (3-D overlap), a cushion below its top, or
		-- the cushion line crossed above it.
		local function meets(t: number): (string?, Ball?)
			local x, y, z = at(t)
			for _, b in state.balls do
				if b.id ~= 0 and not b.pocketed then
					local ddx, ddy, ddz = b.x - x, b.y - y, b.z - z
					if ddx * ddx + ddy * ddy + ddz * ddz < 4 * R * R then
						return "ball", b
					end
				end
			end
			-- The simulation's own rule for going over a cushion (Simulation.goesOver).
			if Simulation.goesOver(geometry, x, y, z, probe.vx, probe.vy) then
				return "off", nil
			end
			if z < clear and Simulation.touchesCushion(geometry, x, y) then
				return "rail", nil
			end
			return nil, nil
		end
		local step = if speed > 1e-6 then ARC_STEP_INCHES / speed else flight
		local t0 = 0
		local t = math.min(step, flight)
		while true do
			local kind = meets(t)
			if kind then
				-- Pin the first touch down between the last clear step and this one.
				local lo, hi = t0, t
				for _ = 1, ARC_BISECTIONS do
					local mid = (lo + hi) / 2
					if meets(mid) then
						hi = mid
					else
						lo = mid
					end
				end
				local hitKind, hitBall = meets(hi)
				hop.seconds = hi
				local x, y = at(hi)
				trace.ghostX, trace.ghostY = x, y
				trace.airborne = true
				local dx, dy = probe.vx / speed, probe.vy / speed
				if hitKind == "ball" and hitBall then
					ballContact(trace, hitBall, dx, dy)
				elseif hitKind == "off" then
					trace.contact = "off"
				else
					-- The nearest cushion line's inward normal.
					local nx, ny = 0, 0
					if math.abs(x) - geometry.halfLength > math.abs(y) - geometry.halfWidth then
						nx = -math.sign(x)
					else
						ny = -math.sign(y)
					end
					railContact(trace, nx, ny, dx, dy)
				end
				return true
			end
			if t >= flight then
				break
			end
			t0 = t
			t = math.min(t + step, flight)
		end
		-- Touchdown: bounce by the simulation's own rule, or settle and hand over.
		probe.x, probe.y = at(flight)
		table.insert(trace.landings, { x = probe.x, y = probe.y })
		local down = g * flight - vz0
		probe.z, probe.vz = 0, -down
		if TableGeometry.openingAt(geometry, probe.x, probe.y) then
			return false
		end
		if not Flight.slate(probe, down, true) then
			return false
		end
	end
	return false
end

local function newTrace(dx: number, dy: number): Trace
	return {
		contact = "none",
		startX = 0,
		startY = 0,
		ghostX = 0,
		ghostY = 0,
		distance = 0,
		objectId = nil,
		objectDirX = 0,
		objectDirY = 0,
		cueDirX = dx,
		cueDirY = dy,
		objectShare = 0,
		cueShare = 0,
		landings = {},
		airborne = false,
		hops = {},
	}
end

-- A jump: the hops are traced into `trace` first. Returns true when something is met in the
-- air (the trace is then complete), else where the cue ball rolls on from (its spot when the
-- shot never leaves the cloth).
local function traceJump(
	state: State,
	cue: Ball,
	shot: Cue.Shot,
	launchScale: number?,
	trace: Trace
): (boolean, number, number)
	if shot.elevation and shot.elevation > Config.Cue.CueElevationDegrees then
		local probe = Ball.clone(cue)
		Cue.strike(probe, shot)
		if launchScale and launchScale ~= 1 then
			-- As the launch abilities do before the first step: along the cloth and the spin,
			-- not the hop (Effects/BlackFlash, Effects/FireShot).
			probe.vx, probe.vy = probe.vx * launchScale, probe.vy * launchScale
			probe.wx, probe.wy = probe.wx * launchScale, probe.wy * launchScale
			probe.wz *= launchScale
		end
		if Flight.isAirborne(probe) then
			if traceFlight(state, probe, trace) then
				return true, 0, 0
			end
			return false, probe.x, probe.y
		end
	end
	return false, cue.x, cue.y
end

-- The first thing a ball centred at (fromX, fromY), rolling along the unit (dx, dy), meets on
-- the cloth within `maxT` inches: a ball, a cushion face or a jaw (its inward normal), or, when
-- `pockets` is set, a pocket its centre drops into (TableGeometry.pocketAt's rule: the centre
-- inside the rim). Returns the distance (nil: nothing), the ball, the normal and the pocket.
local function firstContact(
	state: State,
	fromX: number,
	fromY: number,
	dx: number,
	dy: number,
	maxT: number,
	pockets: boolean
): (number?, Ball?, number, number, Pocket?)
	local R = Config.Balls.RadiusInches
	-- Unit velocity along the aim: impact "time" equals distance in inches.
	local bestT = maxT
	local found = false
	local hitBall: Ball? = nil
	local hitPocket: Pocket? = nil
	local railNx, railNy = 0, 0
	for _, b in state.balls do
		if b.id == 0 or b.pocketed then
			continue
		end
		local t = Collision.circleTOI(fromX, fromY, dx, dy, b.x, b.y, 0, 0, R, bestT)
		if t and t < bestT then
			bestT, found = t, true
			hitBall = b
		end
	end
	for _, seg in state.geometry.segments do
		local t = Collision.segmentTOI(fromX, fromY, dx, dy, R, seg, bestT)
		if t and t < bestT then
			bestT, found = t, true
			hitBall = nil
			railNx, railNy = seg.nx, seg.ny
		end
	end
	for _, pt in state.geometry.points do
		local t, nx, ny = Collision.pointTOI(fromX, fromY, dx, dy, R, pt.x, pt.y, pt.radius, bestT)
		if t and t < bestT then
			bestT, found = t, true
			hitBall = nil
			railNx, railNy = nx, ny
		end
	end
	if pockets and state.geometry.pocketsOpen then
		for _, p in state.geometry.pockets do
			local t = Collision.pointTOI(fromX, fromY, dx, dy, 0, p.x, p.y, p.radius, bestT)
			if t and t < bestT then
				bestT, found = t, true
				hitBall = nil
				hitPocket = p
			end
		end
	end
	if not found then
		return nil, nil, 0, 0, nil
	end
	return bestT, hitBall, railNx, railNy, hitPocket
end

function Aim.trace(state: State, shotOrAngle: Cue.Shot | number, launchScale: number?): Trace
	local cue = Simulation.findBall(state, 0)
	local shot: Cue.Shot = if type(shotOrAngle) == "number"
		then { angle = shotOrAngle, power = 0 }
		else shotOrAngle
	local dx, dy = Cue.launchDirection(shot)
	local trace = newTrace(dx, dy)
	if cue == nil or cue.pocketed then
		return trace
	end
	trace.startX, trace.startY = cue.x, cue.y

	-- A jump: trace the hops first, then carry on flat from where it settles.
	local met, fromX, fromY = traceJump(state, cue, shot, launchScale, trace)
	if met then
		trace.distance = math.sqrt((trace.ghostX - cue.x) ^ 2 + (trace.ghostY - cue.y) ^ 2)
		return trace
	end

	local bestT, hitBall, railNx, railNy = firstContact(state, fromX, fromY, dx, dy, FAR, false)
	if bestT == nil then
		return trace
	end
	trace.ghostX = fromX + dx * bestT
	trace.ghostY = fromY + dy * bestT
	trace.distance = math.sqrt((trace.ghostX - cue.x) ^ 2 + (trace.ghostY - cue.y) ^ 2)

	if hitBall then
		ballContact(trace, hitBall, dx, dy)
	else
		railContact(trace, railNx, railNy, dx, dy)
	end
	return trace
end

--- Fire Shot's aim line: the cue ball's path on the cloth from where it starts rolling, on in a
--- straight line and mirrored off every cushion (angle in, angle out: no spin, no friction,
--- no speed), until it meets a ball (the ghost, and the object ball's line, as Aim.trace) or
--- its centre drops into a pocket, at most `maxInches` long and `maxBounces` cushions. It
--- never says where anything stops. A jump shot's flight is traced first (with
--- `launchScale`, as Aim.trace); one that meets something before it lands ends the line there.
function Aim.bounceTrace(
	state: State,
	shot: Cue.Shot,
	maxInches: number,
	maxBounces: number,
	launchScale: number?
): BounceTrace
	local cue = Simulation.findBall(state, 0)
	local dx, dy = Cue.launchDirection(shot)
	local out: BounceTrace = {
		points = {},
		ending = "none",
		bounces = 0,
		objectId = nil,
		objectDirX = 0,
		objectDirY = 0,
		cueDirX = 0,
		cueDirY = 0,
		pocket = nil,
		flight = nil,
	}
	if cue == nil or cue.pocketed then
		return out
	end
	local flight = newTrace(dx, dy)
	flight.startX, flight.startY = cue.x, cue.y
	local met, x, y = traceJump(state, cue, shot, launchScale, flight)
	if #flight.hops > 0 then
		out.flight = flight
	end
	if met then
		out.ending = "air"
		if flight.contact == "ball" then
			out.objectId = flight.objectId
			out.objectDirX, out.objectDirY = flight.objectDirX, flight.objectDirY
			out.cueDirX, out.cueDirY = flight.cueDirX, flight.cueDirY
		end
		return out
	end
	table.insert(out.points, { x = x, y = y })
	local left = maxInches
	while true do
		local t, hitBall, nx, ny, pocket = firstContact(state, x, y, dx, dy, left, true)
		if t == nil then
			-- Nothing within the cap: the line runs out here.
			x, y = x + dx * left, y + dy * left
			table.insert(out.points, { x = x, y = y })
			out.ending = "limit"
			return out
		end
		x, y = x + dx * t, y + dy * t
		left -= t
		table.insert(out.points, { x = x, y = y })
		if hitBall then
			local contact = newTrace(dx, dy)
			contact.ghostX, contact.ghostY = x, y
			ballContact(contact, hitBall, dx, dy)
			out.ending = "ball"
			out.objectId = contact.objectId
			out.objectDirX, out.objectDirY = contact.objectDirX, contact.objectDirY
			out.cueDirX, out.cueDirY = contact.cueDirX, contact.cueDirY
			return out
		end
		if pocket then
			out.ending = "pocket"
			out.pocket = pocket.id
			return out
		end
		if out.bounces >= maxBounces or left <= 0 then
			out.ending = "limit"
			return out
		end
		out.bounces += 1
		local along = dx * nx + dy * ny
		dx, dy = dx - 2 * along * nx, dy - 2 * along * ny
	end
end

return Aim
