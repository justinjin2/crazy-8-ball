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

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Collision = require(script.Parent.Collision)
local Cue = require(script.Parent.Cue)
local Flight = require(script.Parent.Flight)
local Simulation = require(script.Parent.Simulation)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type State = Simulation.State

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

function Aim.trace(state: State, shotOrAngle: Cue.Shot | number): Trace
	local R = Config.Balls.RadiusInches
	local cue = Simulation.findBall(state, 0)
	local shot: Cue.Shot = if type(shotOrAngle) == "number"
		then { angle = shotOrAngle, power = 0 }
		else shotOrAngle
	local dx, dy = Cue.launchDirection(shot)
	local trace: Trace = {
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
	}
	if cue == nil or cue.pocketed then
		return trace
	end
	trace.startX, trace.startY = cue.x, cue.y

	-- A jump: trace the hops first, then carry on flat from where it settles.
	local fromX, fromY = cue.x, cue.y
	if shot.elevation and shot.elevation > Config.Cue.CueElevationDegrees then
		local probe = Ball.clone(cue)
		Cue.strike(probe, shot)
		if Flight.isAirborne(probe) then
			if traceFlight(state, probe, trace) then
				trace.distance = math.sqrt((trace.ghostX - cue.x) ^ 2 + (trace.ghostY - cue.y) ^ 2)
				return trace
			end
			fromX, fromY = probe.x, probe.y
		end
	end

	-- Unit velocity along the aim: impact "time" equals distance in inches.
	local bestT = FAR
	local hitBall: Ball? = nil
	local railNx, railNy = 0, 0
	for _, b in state.balls do
		if b.id == 0 or b.pocketed then
			continue
		end
		local t = Collision.circleTOI(fromX, fromY, dx, dy, b.x, b.y, 0, 0, R, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = b
		end
	end
	for _, seg in state.geometry.segments do
		local t = Collision.segmentTOI(fromX, fromY, dx, dy, R, seg, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = nil
			railNx, railNy = seg.nx, seg.ny
		end
	end
	for _, pt in state.geometry.points do
		local t, nx, ny = Collision.pointTOI(fromX, fromY, dx, dy, R, pt.x, pt.y, pt.radius, bestT)
		if t and t < bestT then
			bestT = t
			hitBall = nil
			railNx, railNy = nx, ny
		end
	end

	if bestT >= FAR then
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

return Aim
