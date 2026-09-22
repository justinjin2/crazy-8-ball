--!strict
-- Simulation: the pool physics. Pure Luau, fixed timestep, deterministic.
--
-- Each fixed step is processed event by event: find the earliest time of impact among all
-- moving balls, advance everyone exactly to it, resolve that one contact, repeat until the
-- step is used up. Because impact times are exact, nothing can tunnel however fast it goes.
--
-- Between impacts a ball either SLIDES (contact point moving over the cloth, kinetic
-- friction acts on both velocity and spin until they agree) or ROLLS (rolling resistance
-- only, spin locked to velocity). Both are integrated in closed form, so no energy is
-- invented by the integrator.
--
-- Units: inches, seconds, radians. Mass is 1 for every ball (only ratios matter).

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Collision = require(script.Parent.Collision)
local Cue = require(script.Parent.Cue)
local TableGeometry = require(script.Parent.Table)

type Ball = Ball.Ball
type Geometry = TableGeometry.Geometry
type Shot = Cue.Shot

local Simulation = {}

export type Overrides = {
	RailRestitution: number?,
	RailFriction: number?,
}

export type State = {
	geometry: Geometry,
	balls: { Ball },
	time: number,
	overrides: Overrides?, -- copied server-authorized material for this shot only
}

export type Event = {
	t: number,
	type: "cueStrike" | "railHit" | "ballHit" | "pocket",
	ball: number, -- ball id
	other: number?, -- other ball id for ballHit, pocket id for pocket
	speed: number, -- impact speed along the contact normal (in/s)
}

export type Frame = {
	t: number,
	positions: { number }, -- x1, y1, z1, x2, y2, z2 ... in state.balls order (z < 0 while dropping into a pocket)
}

-- What a shot did. The server and the rules only ever need this much; `frames` is the
-- optional recording on top (see ShotResult), and it is expensive: 16 balls at 240 Hz for a
-- ten second shot is well over a megabyte, so nothing asks for it unless it replays it.
export type ShotOutcome = {
	events: { Event },
	finalBalls: { Ball },
	firstContact: number?, -- id of the first ball the cue ball touched
	duration: number,
	steps: number,
	capped: boolean, -- true if MaxShotSeconds stopped the shot early
	overrides: Overrides?, -- retained for replay after the state's copy is cleared
}

export type ShotResult = ShotOutcome & { frames: { Frame } }

---------------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------------

function Simulation.newState(geometry: Geometry, balls: { Ball }): State
	return { geometry = geometry, balls = balls, time = 0 }
end

function Simulation.cloneState(state: State): State
	return {
		geometry = state.geometry,
		balls = Ball.cloneList(state.balls),
		time = state.time,
		overrides = if state.overrides then table.clone(state.overrides) else nil,
	}
end

--- True when no shot motion remains; residual side spin alone does not count. This query
--- never clears spin: it can still affect a collision while another ball is moving.
--- A ball sitting still over an opening is NOT at rest: it
--- has nothing under it, so it still has to tip in. Without this a shot could end with a ball
--- balanced over the hole, which is the thing that made hangers permanent.
function Simulation.isAtRest(state: State): boolean
	for _, b in state.balls do
		if Ball.isMoving(b) then
			return false
		end
		if not b.pocketed and TableGeometry.pocketAt(state.geometry, b.x, b.y) ~= nil then
			return false
		end
	end
	return true
end

function Simulation.energy(state: State): number
	local R = Config.Balls.RadiusInches
	local total = 0
	for _, b in state.balls do
		total += Ball.kineticEnergy(b, R)
	end
	return total
end

function Simulation.findBall(state: State, id: number): Ball?
	for _, b in state.balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Free motion between impacts (closed form)
---------------------------------------------------------------------------------------------

-- A captured ball keeps its momentum, falls under gravity, gets funnelled towards the pocket
-- centre and slowed by the liner, and stops a set depth down. Purely for a believable drop;
-- rules already count it as pocketed.
local function integrateFalling(b: Ball, h: number, pocket: TableGeometry.Pocket?)
	local P = Config.Physics
	local T = Config.Table
	b.vz -= P.Gravity * h
	b.z += b.vz * h
	if pocket then
		local dx, dy = b.x - pocket.x, b.y - pocket.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist > 1e-6 then
			local nx, ny = dx / dist, dy / dist
			b.vx -= nx * T.PocketFunnelAccel * h
			b.vy -= ny * T.PocketFunnelAccel * h
		end
	end
	local decay = math.max(0, 1 - T.PocketDragPerSecond * h)
	b.vx *= decay
	b.vy *= decay
	b.x += b.vx * h
	b.y += b.vy * h
	if pocket then
		local dx, dy = b.x - pocket.x, b.y - pocket.y
		local dist = math.sqrt(dx * dx + dy * dy)
		-- The ball's SURFACE rides the liner, not its centre, so the wall is a ball radius
		-- inside the opening. Clamping the centre to the rim instead let half the ball hang
		-- through the leather on the way down.
		local wall = math.max(pocket.radius - Config.Balls.RadiusInches, 0)
		if dist > wall and dist > 1e-6 then
			local nx, ny = dx / dist, dy / dist
			b.x = pocket.x + nx * wall
			b.y = pocket.y + ny * wall
			local vn = b.vx * nx + b.vy * ny
			if vn > 0 then
				b.vx -= (1 + T.PocketWallRestitution) * vn * nx
				b.vy -= (1 + T.PocketWallRestitution) * vn * ny
			end
		end
	end
	if b.z <= -T.PocketDropDepthInches then
		b.z = -T.PocketDropDepthInches
		Ball.stop(b)
		b.falling = false
		b.tip = nil
	end
end

-- The tip. Once a ball's centre is inside the opening rim there is nothing under it, so it
-- topples about the rim point it crossed: a solid sphere pivoting on an edge, which is the
-- textbook problem. With I about the pivot = 7/5 m R^2, gravity gives
--
--     alpha = (5 g / 7 R) * sin(theta),  theta measured off vertical above the pivot
--
-- and the ball leaves the lip the moment the edge stops pushing on it, N = 0, which is
-- R * omega^2 >= g * cos(theta). A ball that just trickles over hangs and takes about a
-- third of a second to go; a ball arriving at 50 in/s or more separates on the first test,
-- so fast pocketing is untouched. Returns the event once the ball is away.
local function integrateTip(b: Ball, h: number, pocket: TableGeometry.Pocket?, time: number): Event?
	local tip = b.tip
	if tip == nil then
		return nil
	end
	local R = Config.Balls.RadiusInches
	local g = Config.Physics.Gravity

	-- Whatever sideways speed the ball arrived with stays in vx, vy and carries the pivot
	-- along the rim, so a ball cutting across the mouth does not lose its drift.
	tip.px += b.vx * h
	tip.py += b.vy * h
	tip.omega += 5 * g / (7 * R) * math.sin(tip.theta) * h
	tip.theta += tip.omega * h

	local sin, cos = math.sin(tip.theta), math.cos(tip.theta)
	b.x = tip.px + R * sin * tip.nx
	b.y = tip.py + R * sin * tip.ny
	b.z = R * (cos - 1)
	-- Rolling over the lip: the ball turns about the horizontal axis across its direction of
	-- travel at the pivot rate, so it visibly rolls in rather than sliding.
	b.wx = -tip.ny * tip.omega
	b.wy = tip.nx * tip.omega

	if R * tip.omega * tip.omega < g * cos and tip.theta < math.pi / 2 then
		return nil
	end
	-- Away. Hand the pivot's velocity to the free-fall integrator and let the liner have it.
	local edge = R * tip.omega
	b.vx += tip.nx * edge * cos
	b.vy += tip.ny * edge * cos
	b.vz = -edge * sin
	b.tip = nil
	if pocket then
		b.pocket = pocket.id
	end
	return {
		t = time,
		type = "pocket",
		ball = b.id,
		other = if pocket then pocket.id else nil,
		speed = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz),
	}
end

local function integrateBall(
	b: Ball,
	h: number,
	geometry: Geometry,
	events: { Event }?,
	time: number
)
	if b.pocketed then
		local pocket = if b.pocket then geometry.pockets[b.pocket] else nil
		if b.tip then
			local ev = integrateTip(b, h, pocket, time)
			if ev and events then
				table.insert(events, ev)
			end
		elseif b.falling then
			integrateFalling(b, h, pocket)
		end
		return
	end
	local P = Config.Physics
	local R = Config.Balls.RadiusInches
	local g = P.Gravity

	local remaining = h

	-- Contact point velocity relative to the cloth. Zero means the ball is rolling.
	local ux = b.vx - R * b.wy
	local uy = b.vy + R * b.wx
	local u = math.sqrt(ux * ux + uy * uy)

	if u > P.SlideEpsilon then
		-- Sliding. u shrinks linearly at 3.5 * mu * g along a fixed direction, so the
		-- motion over the slide interval is exact constant-acceleration kinematics.
		local uhx, uhy = ux / u, uy / u
		local slideTime = u / (3.5 * P.SlidingFriction * g)
		local dt = math.min(slideTime, remaining)
		local a = -P.SlidingFriction * g
		local alpha = 2.5 * P.SlidingFriction * g / R

		b.x += b.vx * dt + 0.5 * a * uhx * dt * dt
		b.y += b.vy * dt + 0.5 * a * uhy * dt * dt
		b.vx += a * uhx * dt
		b.vy += a * uhy * dt
		b.wx += -alpha * uhy * dt
		b.wy += alpha * uhx * dt
		remaining -= dt

		if slideTime <= h then
			-- Reached pure rolling inside this interval: lock spin to velocity exactly.
			b.wx = -b.vy / R
			b.wy = b.vx / R
		end
	end

	if remaining > 0 then
		-- Rolling. Rolling resistance slows the ball along its direction of travel.
		local v = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		if v > 0 then
			local decel = P.RollingFriction * g
			local stopTime = v / decel
			local dt = math.min(stopTime, remaining)
			local dhx, dhy = b.vx / v, b.vy / v
			b.x += b.vx * dt - 0.5 * decel * dhx * dt * dt
			b.y += b.vy * dt - 0.5 * decel * dhy * dt * dt
			if stopTime <= remaining then
				b.vx, b.vy = 0, 0
			else
				b.vx -= decel * dhx * dt
				b.vy -= decel * dhy * dt
			end
		end
		b.wx = -b.vy / R
		b.wy = b.vx / R
	end

	-- Side spin decays on its own (friction torque about the vertical axis).
	if b.wz ~= 0 then
		b.wz -= math.sign(b.wz) * math.min(math.abs(b.wz), P.SideSpinDecel * h)
	end

	-- Stop translation independently of side spin. Preserve english until the WHOLE shot
	-- ends, since another moving ball may still collide with this one.
	local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	if speed < P.RestSpeed then
		local uAfter = math.sqrt((b.vx - R * b.wy) ^ 2 + (b.vy + R * b.wx) ^ 2)
		if uAfter < P.SlideEpsilon then
			b.vx, b.vy, b.wx, b.wy = 0, 0, 0, 0
		end
	end
end

---------------------------------------------------------------------------------------------
-- Contact resolution
---------------------------------------------------------------------------------------------

-- Contact restitution depends on the incoming speed perpendicular to the cushion.
local function railRestitution(speed: number): number
	local points = Config.Physics.RailRestitutionBySpeed
	if #points == 0 then
		return Config.Physics.RailRestitution
	end
	if speed <= points[1].Speed then
		return points[1].Restitution
	end
	for i = 2, #points do
		local upper = points[i]
		if speed <= upper.Speed then
			local lower = points[i - 1]
			local fraction = (speed - lower.Speed) / (upper.Speed - lower.Speed)
			return lower.Restitution + fraction * (upper.Restitution - lower.Restitution)
		end
	end
	return points[#points].Restitution
end

-- Han 2005, as corrected in pooltool's han_2005/model.py. Work in an inward-facing
-- cushion frame (n, t = z cross n, z); the true normal is (cos(theta), 0, -sin(theta)).
-- Its line of action passes through the centre, so only tangential impulses create torque.
local function resolveRail(b: Ball, nx: number, ny: number, e: number, mu: number): number
	local R = Config.Balls.RadiusInches
	local sinTheta = Config.Physics.CushionNoseHeightInches / R - 1
	local cosTheta = math.sqrt(1 - sinTheta * sinTheta)
	local tx, ty = -ny, nx
	local vn = b.vx * nx + b.vy * ny
	if vn >= 0 then
		return 0
	end
	local vt = b.vx * tx + b.vy * ty
	local wn = b.wx * nx + b.wy * ny
	local wt = b.wx * tx + b.wy * ty
	local wz = b.wz
	local speedIn = -vn

	-- Surface slip on both true contact tangents: along the rail and up its tilted face.
	local slipAlong = vt - R * (cosTheta * wz + sinTheta * wn)
	local slipTilt = sinTheta * vn + R * wt
	local slipSpeed = math.sqrt(slipAlong * slipAlong + slipTilt * slipTilt)
	local normalImpulse = (1 + e) * cosTheta * speedIn
	local along, tilt = 0, 0
	if slipSpeed > 0 then
		-- Unit mass, solid sphere: inverse tangential contact mass = 1 + 5/2.
		-- Reaching slipSpeed / 3.5 sticks; otherwise the full Coulomb cone limits sliding.
		local impulse = math.min(slipSpeed / 3.5, mu * normalImpulse)
		along = -impulse * slipAlong / slipSpeed
		tilt = -impulse * slipTilt / slipSpeed
	end

	-- Apply the full contact impulse/torque, then discard vertical translation. The
	-- normal impulse has no torque: its two apparent angular contributions cancel.
	vn += normalImpulse * cosTheta + tilt * sinTheta
	vt += along
	wn -= 2.5 * sinTheta * along / R
	wt += 2.5 * tilt / R
	wz -= 2.5 * cosTheta * along / R

	-- The configured restitution/friction cone always sends the centre outward. For a
	-- more extreme future override, enforce the planar rail constraint without adding
	-- energy: reflecting a residual inward component preserves its squared magnitude.
	vn = math.abs(vn)
	b.vx = vn * nx + vt * tx
	b.vy = vn * ny + vt * ty
	b.wx = wn * nx + wt * tx
	b.wy = wn * ny + wt * ty
	b.wz = wz
	return speedIn
end

-- Ordered piecewise-linear contact friction, clamped to the tabulated endpoint values.
local function ballFriction(slipSpeed: number): number
	local points = Config.Physics.BallFrictionTable
	if slipSpeed <= points[1].Speed then
		return points[1].Friction
	end
	for i = 2, #points do
		local upper = points[i]
		if slipSpeed <= upper.Speed then
			local lower = points[i - 1]
			local fraction = (slipSpeed - lower.Speed) / (upper.Speed - lower.Speed)
			return lower.Friction + fraction * (upper.Friction - lower.Friction)
		end
	end
	return points[#points].Friction
end

-- Equal-mass contact with restitution, throw and spin transfer (TP A.14 / pooltool).
-- Keep vertical contact slip for the angular impulse, then discard vertical translation:
-- balls stay on the cloth, but rolling into another ball can give it backspin.
local function resolveBalls(a: Ball, b: Ball): number
	local e = Config.Physics.BallRestitution
	local R = Config.Balls.RadiusInches
	local nx, ny = b.x - a.x, b.y - a.y
	local len = math.sqrt(nx * nx + ny * ny)
	if len < 1e-12 then
		return 0
	end
	nx, ny = nx / len, ny / len
	local relVn = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if relVn <= 0 then
		return 0
	end
	local j = (1 + e) * relVn / 2
	a.vx -= j * nx
	a.vy -= j * ny
	b.vx += j * nx
	b.vy += j * ny

	-- Tangent t = (-ny, nx, 0); the other contact tangent is vertical. The normal
	-- impulse above cannot change either component of this relative surface velocity.
	local slipAlong = -(a.vx - b.vx) * ny + (a.vy - b.vy) * nx + R * (a.wz + b.wz)
	local slipVertical = R * ((a.wx + b.wx) * ny - (a.wy + b.wy) * nx)
	local slipSpeed = math.sqrt(slipAlong * slipAlong + slipVertical * slipVertical)
	if slipSpeed > Config.Physics.BallSlipEpsilon then
		-- Unit masses and I = 0.4 R^2 give contact inverse mass 7. The cap prevents
		-- slip reversing during impact and limits head-on spin transfer to 5/14.
		local impulse = math.min(ballFriction(slipSpeed) * j, slipSpeed / 7)
		local along = -impulse * slipAlong / slipSpeed
		local vertical = -impulse * slipVertical / slipSpeed
		local jx, jy = -ny * along, nx * along
		a.vx += jx
		a.vy += jy
		b.vx -= jx
		b.vy -= jy
		-- Both torques have the same sign: opposite forces at opposite contact arms.
		local dwx, dwy, dwz = 2.5 * ny * vertical / R, -2.5 * nx * vertical / R, 2.5 * along / R
		a.wx += dwx
		a.wy += dwy
		a.wz += dwz
		b.wx += dwx
		b.wy += dwy
		b.wz += dwz
	end
	return relVn
end

-- A ball whose centre has crossed an opening rim leaves the table for good. It does not drop
-- from here: it starts toppling over the lip (see integrateTip), and the pocket event is
-- fired when it comes off the lip, which is the moment it is really gone and the only moment
-- that carries an honest speed for the sound.
--
-- Balls that have STOPPED are checked too. They used to be skipped, so a ball that ran out of
-- steam while hanging over the hole sat there for the rest of the game.
local function capturePockets(state: State, events: { Event }?)
	local R = Config.Balls.RadiusInches
	local g = Config.Physics.Gravity
	local minTheta = math.rad(Config.Table.PocketTipMinDegrees)
	for _, b in state.balls do
		if b.pocketed then
			continue
		end
		local pocket = TableGeometry.pocketAt(state.geometry, b.x, b.y)
		if pocket == nil then
			continue
		end
		b.pocketed = true
		b.falling = true
		b.pocket = pocket.id
		b.wz = 0 -- side spin has nothing to bite on once the ball is off the cloth

		-- The rim point the ball crossed, and the direction from it into the pocket.
		local dx, dy = b.x - pocket.x, b.y - pocket.y
		local dist = math.sqrt(dx * dx + dy * dy)
		local overhang = (pocket.radius - dist) / R
		if dist > 1e-6 and overhang < 1 then
			local ux, uy = dx / dist, dy / dist
			local nx, ny = -ux, -uy -- from the rim towards the pocket centre
			local theta = math.max(math.asin(overhang), minTheta)
			-- The inward part of the velocity drives the pivot; the sideways part stays in
			-- vx, vy and carries the pivot along with it.
			local vIn = math.max(b.vx * nx + b.vy * ny, 0)
			local omega = vIn / (R * math.cos(theta))
			-- Only worth pivoting while the lip is still pushing back. A ball arriving fast,
			-- or one already most of the way over, is off the lip the instant it gets there,
			-- so it skips straight to the drop with its velocity untouched - which is exactly
			-- what pocketing used to do, so nothing about a firmly struck ball changes.
			if R * omega * omega < g * math.cos(theta) then
				b.vx -= vIn * nx
				b.vy -= vIn * ny
				b.tip = {
					px = pocket.x + ux * pocket.radius,
					py = pocket.y + uy * pocket.radius,
					nx = nx,
					ny = ny,
					theta = theta,
					omega = omega,
				}
				continue
			end
		end
		b.wx, b.wy = 0, 0
		if events then
			table.insert(events, {
				t = state.time,
				type = "pocket",
				ball = b.id,
				other = pocket.id,
				speed = Ball.speed(b),
			})
		end
	end
end

---------------------------------------------------------------------------------------------
-- Stepping
---------------------------------------------------------------------------------------------

type Hit = {
	kind: "rail" | "point" | "ball",
	t: number,
	a: Ball,
	b: Ball?,
	nx: number,
	ny: number,
	seg: TableGeometry.Segment?,
}

local function findEarliestHit(state: State, maxT: number): Hit?
	local R = Config.Balls.RadiusInches
	local geometry = state.geometry
	local balls = state.balls
	local best: Hit? = nil
	local bestT = maxT

	for i, a in balls do
		if a.pocketed then
			continue
		end
		local moving = a.vx ~= 0 or a.vy ~= 0
		-- Broad phase: a ball that cannot reach the cushion line this step skips every rail
		-- and jaw test (facings and jaws all lie on or beyond the cushion line).
		local reach = math.sqrt(a.vx * a.vx + a.vy * a.vy) * maxT + R
		local nearRail = math.abs(a.x) + reach >= geometry.halfLength
			or math.abs(a.y) + reach >= geometry.halfWidth
		if moving and nearRail then
			for _, seg in geometry.segments do
				local t = Collision.segmentTOI(a.x, a.y, a.vx, a.vy, R, seg, bestT)
				if t and t < bestT then
					bestT = t
					best = { kind = "rail", t = t, a = a, nx = seg.nx, ny = seg.ny, seg = seg }
				end
			end
			for _, pt in geometry.points do
				local t, nx, ny =
					Collision.pointTOI(a.x, a.y, a.vx, a.vy, R, pt.x, pt.y, pt.radius, bestT)
				if t and t < bestT then
					bestT = t
					best = { kind = "point", t = t, a = a, nx = nx, ny = ny }
				end
			end
		end
		for j = i + 1, #balls do
			local b = balls[j]
			if b.pocketed then
				continue
			end
			if not moving and b.vx == 0 and b.vy == 0 then
				continue
			end
			local t = Collision.circleTOI(a.x, a.y, a.vx, a.vy, b.x, b.y, b.vx, b.vy, R, bestT)
			if t and t < bestT then
				bestT = t
				best = { kind = "ball", t = t, a = a, b = b, nx = 0, ny = 0 }
			end
		end
	end
	return best
end

local function pushOut(hit: Hit)
	local R = Config.Balls.RadiusInches
	local slop = Config.Physics.ContactSlop
	local a = hit.a
	if hit.kind == "rail" and hit.seg then
		local seg = hit.seg
		local d = (a.x - seg.ax) * seg.nx + (a.y - seg.ay) * seg.ny
		if d < R + slop then
			a.x += (R + slop - d) * seg.nx
			a.y += (R + slop - d) * seg.ny
		end
	elseif hit.kind == "ball" and hit.b then
		local b = hit.b
		local dx, dy = b.x - a.x, b.y - a.y
		local dist = math.sqrt(dx * dx + dy * dy)
		local want = 2 * R + slop
		if dist > 1e-12 and dist < want then
			local push = (want - dist) / 2
			local nx, ny = dx / dist, dy / dist
			a.x -= nx * push
			a.y -= ny * push
			b.x += nx * push
			b.y += ny * push
		end
	end
end

--- Advance the simulation by one fixed step, appending any contact events.
function Simulation.step(state: State, dt: number, events: { Event }?)
	local P = Config.Physics
	local remaining = dt
	local iterations = 0
	-- Zero-time hits per ball this step. A ball wedged between two surfaces would bounce
	-- between them forever at t = 0; after a few dozen such hits it is stopped instead.
	local instantHits: { [Ball]: number } = {}

	while remaining > 1e-9 and iterations < P.MaxEventsPerStep do
		iterations += 1
		local hit = findEarliestHit(state, remaining)
		local advance = if hit then hit.t else remaining

		for _, b in state.balls do
			integrateBall(b, advance, state.geometry, events, state.time + advance)
		end
		state.time += advance
		remaining -= advance
		capturePockets(state, events)

		if hit and not hit.a.pocketed and not (hit.b and hit.b.pocketed) then
			pushOut(hit)
			local speed: number
			local eventType: "railHit" | "ballHit"
			local other: number? = nil
			if hit.kind == "ball" and hit.b then
				speed = resolveBalls(hit.a, hit.b)
				eventType = "ballHit"
				other = hit.b.id
			else
				local normalSpeed = -(hit.a.vx * hit.nx + hit.a.vy * hit.ny)
				local material = state.overrides
				local e = if material and material.RailRestitution ~= nil
					then material.RailRestitution
					else railRestitution(normalSpeed)
				local mu = if material and material.RailFriction ~= nil
					then material.RailFriction
					else P.RailFriction
				speed = resolveRail(hit.a, hit.nx, hit.ny, e, mu)
				eventType = "railHit"
			end
			if events and speed > 0 then
				table.insert(events, {
					t = state.time,
					type = eventType,
					ball = hit.a.id,
					other = other,
					speed = speed,
				})
			end
			if hit.t <= P.InstantHitSeconds then
				local n = (instantHits[hit.a] or 0) + 1
				instantHits[hit.a] = n
				if n >= P.MaxInstantHits then
					Ball.stop(hit.a) -- wedged: it is not going anywhere
					if hit.b then
						Ball.stop(hit.b)
					end
				end
			end
			if iterations >= P.MaxEventsPerStep then
				-- Budget exhausted: whatever is still colliding is stuck. Stop it rather than
				-- burning the whole shot on it.
				Ball.stop(hit.a)
				if hit.b then
					Ball.stop(hit.b)
				end
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Whole shot
---------------------------------------------------------------------------------------------

local function captureFrame(state: State): Frame
	local positions = table.create(#state.balls * 3)
	for i, b in state.balls do
		positions[3 * i - 2] = b.x
		positions[3 * i - 1] = b.y
		positions[3 * i] = b.z
	end
	return { t = state.time, positions = positions }
end

--- A deterministic fingerprint of where every ball ended up, used to prove that a client's
--- replay of a shot matched the server's run of it. Positions are quantised to a thousandth
--- of an inch first, so the last bit or two of floating point noise does not trip it, and
--- the mix is plain integer arithmetic (FNV-1a) so it is identical on every machine.
---
--- Balls are hashed in list order, which Rack.newGame sorts by id, so the order is
--- canonical rather than whatever the table happened to iterate.
function Simulation.checksum(balls: { Ball }): number
	local h = 2166136261
	local function mix(value: number)
		-- Quantise, then fold into an unsigned 32-bit range before mixing.
		local q = math.floor(value * 1000 + 0.5) % 4294967296
		h = bit32.bxor(h, q)
		h = (h * 16777619) % 4294967296
	end
	for _, b in balls do
		mix(b.x)
		mix(b.y)
		mix(b.z)
		mix(if b.pocketed then 1 else 0)
	end
	return h
end

--- Strike the cue ball of a state that is about to be stepped, returning the opening event.
--- Split out of run so a client can start a shot and step it forward itself instead of
--- simulating the whole thing up front (see src/client/Match.luau).
function Simulation.strike(state: State, shot: Shot): Event
	local cueBall = Simulation.findBall(state, 0)
	if cueBall == nil or cueBall.pocketed then
		error("Simulation.strike: no cue ball on the table")
	end
	state.time = 0
	local material = if shot.ability then Config.Physics.ShotMaterials[shot.ability] else nil
	state.overrides = if material then table.clone(material) else nil
	local speed = Cue.strike(cueBall, shot)
	return { t = 0, type = "cueStrike", ball = 0, speed = speed }
end

--- The id of the first ball the cue ball touched, if any.
function Simulation.firstContact(events: { Event }): number?
	for _, ev in events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			return if ev.ball == 0 then ev.other else ev.ball
		end
	end
	return nil
end

--- Put the cue ball back on the head spot if it is off the table.
---
--- Until the rules land (Roadmap 2.1) a scratch has no other consequence, and something has
--- to do this or the table is finished: a state whose cue ball is pocketed cannot be struck
--- again, so every later shot on that table fails.
function Simulation.respotCueBall(state: State): boolean
	local cue = Simulation.findBall(state, 0)
	if cue == nil or not cue.pocketed then
		return false
	end
	cue.pocketed = false
	cue.falling = false
	cue.pocket = nil
	cue.tip = nil
	cue.z = 0
	Ball.stop(cue)
	cue.x, cue.y = TableGeometry.headSpot(state.geometry)
	return true
end

-- Step an already-struck state to rest, IN PLACE. Split out of simulate so a caller that
-- has struck the ball itself (the server, which quantises the strike before integrating
-- it) can run exactly the same loop rather than striking a second time.
local function settleInto(sim: State, events: { Event }, frames: { Frame }?): ShotOutcome
	local P = Config.Physics
	local overrides = if sim.overrides then table.clone(sim.overrides) else nil
	local steps = 0
	local maxSteps = math.floor(P.MaxShotSeconds / P.FixedStep)
	local capped = false
	while not Simulation.isAtRest(sim) do
		if steps >= maxSteps then
			capped = true
			for _, b in sim.balls do
				Ball.stop(b)
				b.falling = false
				b.tip = nil
			end
			break
		end
		Simulation.step(sim, P.FixedStep, events)
		if frames then
			table.insert(frames, captureFrame(sim))
		end
		steps += 1
	end

	-- All translation, sliding and pocket animation has finished. Do not carry residual
	-- english into the next shot. Client replays do the same in Match.reconcile.
	for _, b in sim.balls do
		b.wz = 0
	end
	sim.overrides = nil

	return {
		events = events,
		finalBalls = Ball.cloneList(sim.balls),
		firstContact = Simulation.firstContact(events),
		duration = sim.time,
		steps = steps,
		capped = capped,
		overrides = overrides,
	}
end

--- Run an already-struck state to rest. The state is stepped in place, so the caller owns
--- it; `events` should already hold the opening cueStrike event.
function Simulation.settle(state: State, events: { Event }?): ShotOutcome
	return settleInto(state, events or {}, nil)
end

-- Strike a copy and run it. `frames`, when given, is filled as the shot goes.
local function simulate(state: State, shot: Shot, frames: { Frame }?): ShotOutcome
	local sim = Simulation.cloneState(state)
	local events: { Event } = { Simulation.strike(sim, shot) }
	if frames then
		table.insert(frames, captureFrame(sim))
	end
	return settleInto(sim, events, frames)
end

--- Run a complete shot and record every frame of it. The input state is not modified.
--- Recording costs real memory, so prefer runHeadless unless the frames are wanted.
function Simulation.run(state: State, shot: Shot): ShotResult
	local frames: { Frame } = {}
	local outcome = simulate(state, shot, frames)
	return {
		frames = frames,
		events = outcome.events,
		finalBalls = outcome.finalBalls,
		firstContact = outcome.firstContact,
		duration = outcome.duration,
		steps = outcome.steps,
		capped = outcome.capped,
		overrides = outcome.overrides,
	}
end

--- Run a complete shot without recording frames: what the server needs to validate a shot
--- and tell everyone what happened.
function Simulation.runHeadless(state: State, shot: Shot): ShotOutcome
	return simulate(state, shot, nil)
end

return Simulation
