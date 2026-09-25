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
-- A contact between two balls is one instantaneous impulse. A contact that involves a ball
-- already touching a third (a rack, balls frozen together) is handed to Cluster, which
-- squashes the whole group together as soft spheres for the fraction of a millisecond the
-- contact lasts; see Cluster.luau for why, and Simulation.step for how that fits in.
--
-- A ball knocked off the cloth (a jump shot, a hard break's hop) flies under gravity and
-- bounces on the slate (see Flight.luau). While any ball is in the air, steps are cut to
-- AirStepSeconds and contacts with it are found in 3-D. A ball that flies over a cushion
-- is off the table: it leaves play like a pocketed ball, with an `offTable` event.
--
-- Units: inches, seconds, radians. Mass is 1 for every ball (only ratios matter).

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)
local Cluster = require(script.Parent.Cluster)
local Collision = require(script.Parent.Collision)
local Cue = require(script.Parent.Cue)
local Flight = require(script.Parent.Flight)
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
	type: "cueStrike" | "railHit" | "ballHit" | "pocket" | "land" | "offTable",
	ball: number, -- ball id
	other: number?, -- other ball id for ballHit, pocket id for pocket
	speed: number, -- impact speed along the contact normal (in/s); land: speed coming down
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
		total += Ball.kineticEnergy(b, R, Config.Physics.Gravity)
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

-- A ball that has flown over a cushion is out of play: it counts as pocketed, in no pocket,
-- and keeps the velocity it left with so the renderer can carry on its flight to the floor.
local function leaveTable(b: Ball, events: { Event }?, time: number)
	b.pocketed = true
	b.offTable = true
	b.falling = false
	b.pocket = nil
	b.tip = nil
	if events then
		table.insert(events, {
			t = time,
			type = "offTable",
			ball = b.id,
			speed = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz),
		})
	end
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
	if b.z > 0 or b.vz > 0 then -- in the air (Flight.isAirborne, inlined: this is hot)
		local flown = Flight.fly(b, h)
		if flown >= h then
			return
		end
		-- Touched down, h - flown before the end of this interval.
		local landedAt = time - (h - flown)
		if TableGeometry.openingAt(geometry, b.x, b.y) then
			-- Nothing under it: it drops in (capturePockets takes it, still moving down).
			return
		end
		if not TableGeometry.containsCenter(geometry, b.x, b.y, Config.Balls.RadiusInches) then
			leaveTable(b, events, landedAt) -- came down on the rail, not the cloth
			return
		end
		local down = -b.vz
		Flight.slate(b, down, true)
		if events then
			table.insert(events, { t = landedAt, type = "land", ball = b.id, speed = down })
		end
		integrateBall(b, h - flown, geometry, events, time)
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
--
-- A ball on the cloth is held down by the slate through the contact (Han's assumption), so
-- its vertical translation is discarded. A ball in the air lower than the cushion top meets
-- it the same way and keeps its own vertical speed: it rebounds off the rubber, it is not
-- launched by it. (A version that kept the tilted normal's vertical part threw balls 4-11 ft
-- up and could freeze one rising past the nose; the 2026-09-24 fuzz found both.) Higher
-- than the cushion top it never touches it: see checkOffTable.
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

-- The same contact when a ball is in the air: the normal runs centre to centre in 3-D and
-- the friction impulse keeps its vertical part. A ball coming down on top of another pushes
-- it into the slate, which holds it, and is itself thrown back up.
local function resolveBalls3D(a: Ball, b: Ball): number
	local R = Config.Balls.RadiusInches
	local e = Config.Physics.BallRestitution
	local aDown, bDown = not Flight.isAirborne(a), not Flight.isAirborne(b)
	local nx, ny, nz = b.x - a.x, b.y - a.y, b.z - a.z
	local len = math.sqrt(nx * nx + ny * ny + nz * nz)
	if len < 1e-12 then
		return 0
	end
	nx, ny, nz = nx / len, ny / len, nz / len
	local relVn = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny + (a.vz - b.vz) * nz
	if relVn <= 0 then
		return 0
	end
	-- A ball settling onto the top of another cannot balance there: rather than bounce on
	-- it forever in ever smaller hops, a slow contact from above is dead and sends the top
	-- ball off the side it leans to (straight down: a fixed side, so replays agree), paid
	-- for out of the energy the dead contact loses, so none is ever created.
	local P = Config.Physics
	local g = P.Gravity
	local perch: Ball? = nil
	local slideX, slideY = 0, 0
	local energyBefore = Ball.kineticEnergy(a, R, g) + Ball.kineticEnergy(b, R, g)
	if math.abs(nz) > 0.5 and relVn < P.PerchSpeed then
		local sign = if nz < 0 then -1 else 1
		perch = if nz < 0 then a else b
		slideX, slideY = sign * nx, sign * ny
		local h = math.sqrt(slideX * slideX + slideY * slideY)
		if h < 1e-6 then
			slideX, slideY, h = 1, 0, 1
		end
		slideX, slideY = slideX / h * P.PerchSlideSpeed, slideY / h * P.PerchSlideSpeed
		e = 0
	end
	local j = (1 + e) * relVn / 2
	a.vx -= j * nx
	a.vy -= j * ny
	a.vz -= j * nz
	b.vx += j * nx
	b.vy += j * ny
	b.vz += j * nz

	-- Surface slip at the contact: relative velocity plus R (wa + wb) x n, tangential part.
	local swx, swy, swz = a.wx + b.wx, a.wy + b.wy, a.wz + b.wz
	local sx = a.vx - b.vx + R * (swy * nz - swz * ny)
	local sy = a.vy - b.vy + R * (swz * nx - swx * nz)
	local sz = a.vz - b.vz + R * (swx * ny - swy * nx)
	local sn = sx * nx + sy * ny + sz * nz
	sx, sy, sz = sx - sn * nx, sy - sn * ny, sz - sn * nz
	local slip = math.sqrt(sx * sx + sy * sy + sz * sz)
	if slip > Config.Physics.BallSlipEpsilon then
		-- Contact inverse mass 7, as in Cluster.frictionImpulse.
		local impulse = math.min(Cluster.ballFriction(slip) * j, slip / 7)
		local tx, ty, tz = sx / slip, sy / slip, sz / slip
		a.vx -= impulse * tx
		a.vy -= impulse * ty
		a.vz -= impulse * tz
		b.vx += impulse * tx
		b.vy += impulse * ty
		b.vz += impulse * tz
		-- Both torques have the same sign: opposite forces at opposite contact arms.
		local k = -2.5 * impulse / R
		local dwx, dwy, dwz =
			k * (ny * tz - nz * ty), k * (nz * tx - nx * tz), k * (nx * ty - ny * tx)
		a.wx += dwx
		a.wy += dwy
		a.wz += dwz
		b.wx += dwx
		b.wy += dwy
		b.wz += dwz
	end
	-- A ball on the cloth stays there, as in the planar model: the slate holds it against the
	-- push down, and the friction's vertical part only turns it. Only the flyer flies.
	if aDown then
		a.vz = 0
	end
	if bDown then
		b.vz = 0
	end
	if perch then
		-- The largest share of the slide the contact's loss can pay for (bisection: exact
		-- arithmetic only, so every machine lands on the same number).
		local vx, vy = perch.vx, perch.vy
		local function after(k: number): number
			perch.vx, perch.vy = vx + slideX * k, vy + slideY * k
			return Ball.kineticEnergy(a, R, g) + Ball.kineticEnergy(b, R, g)
		end
		local lo, hi = 0, 1
		if after(1) > energyBefore then
			for _ = 1, 20 do
				local mid = (lo + hi) / 2
				if after(mid) > energyBefore then
					hi = mid
				else
					lo = mid
				end
			end
			after(lo)
		end
		-- Rolling off another ball's top touches it every step: not a hit anyone hears.
		return 0
	end
	return relVn
end

-- Equal-mass contact with restitution, throw and spin transfer (TP A.14 / pooltool).
-- Keep vertical contact slip for the angular impulse, then discard vertical translation:
-- balls stay on the cloth, but rolling into another ball can give it backspin.
local function resolveBalls(a: Ball, b: Ball): number
	if a.z > 0 or a.vz > 0 or b.z > 0 or b.vz > 0 then -- either in the air
		return resolveBalls3D(a, b)
	end
	local e = Config.Physics.BallRestitution
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

	-- Contact friction: throw and spin transfer (shared with Cluster's soft contact).
	local along, vertical = Cluster.frictionImpulse(
		a.vx - b.vx,
		a.vy - b.vy,
		a.wx + b.wx,
		a.wy + b.wy,
		a.wz + b.wz,
		nx,
		ny,
		j
	)
	if along ~= 0 or vertical ~= 0 then
		local R = Config.Balls.RadiusInches
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
		-- A ball in the air lower than the cushion top over an opening meets the back of the
		-- pocket and goes down it, as a hard flat shot's hop into a pocket must. Higher, it
		-- flies over (and may still come down into it).
		local flying = b.z > 0 or b.vz > 0 -- Flight.isAirborne, inlined: this is hot
		if flying and b.z >= Config.Table.CushionHeightInches then
			continue
		end
		local pocket = if flying
			then TableGeometry.openingAt(state.geometry, b.x, b.y)
			else TableGeometry.pocketAt(state.geometry, b.x, b.y)
		if pocket == nil then
			continue
		end
		b.pocketed = true
		b.falling = true
		b.pocket = pocket.id
		b.wz = 0 -- side spin has nothing to bite on once the ball is off the cloth
		if flying then
			b.wx, b.wy = 0, 0
			if events then
				table.insert(events, {
					t = state.time,
					type = "pocket",
					ball = b.id,
					other = pocket.id,
					speed = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz),
				})
			end
			continue
		end

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

--- Whether a ball centred at (x, y) overlaps a cushion face or a jaw, in plan. Aim.trace uses
--- it to find where a low flight meets a cushion.
function Simulation.touchesCushion(geometry: Geometry, x: number, y: number): boolean
	local R = Config.Balls.RadiusInches
	for _, seg in geometry.segments do
		local d = (x - seg.ax) * seg.nx + (y - seg.ay) * seg.ny
		if d < R and d > -R then
			local ex, ey = seg.bx - seg.ax, seg.by - seg.ay
			local along = ((x - seg.ax) * ex + (y - seg.ay) * ey) / (ex * ex + ey * ey)
			if along >= 0 and along <= 1 then
				return true
			end
		end
	end
	for _, pt in geometry.points do
		local dx, dy = x - pt.x, y - pt.y
		local reach = R + pt.radius
		if dx * dx + dy * dy < reach * reach then
			return true
		end
	end
	return false
end

--- Whether a ball in the air at (x, y, z) moving (vx, vy) is going over a cushion: a radius
--- past the cushion line (out over the rail) anywhere but the hole itself, or higher than
--- the cushion top, over a real cushion face or jaw and moving outward across it. The mouth
--- in front of a pocket has no cushion, so a ball flying into it may still drop in.
--- Aim.trace asks the same question for the guideline.
function Simulation.goesOver(
	geometry: Geometry,
	x: number,
	y: number,
	z: number,
	vx: number,
	vy: number
): boolean
	local R = Config.Balls.RadiusInches
	if TableGeometry.openingAt(geometry, x, y) then
		return false
	end
	if not TableGeometry.containsCenter(geometry, x, y, R) then
		return true
	end
	if z < Config.Table.CushionHeightInches then
		return false
	end
	for _, seg in geometry.segments do
		local d = (x - seg.ax) * seg.nx + (y - seg.ay) * seg.ny
		if d < R and d > -R and vx * seg.nx + vy * seg.ny < 0 then
			local ex, ey = seg.bx - seg.ax, seg.by - seg.ay
			local along = ((x - seg.ax) * ex + (y - seg.ay) * ey) / (ex * ex + ey * ey)
			if along >= 0 and along <= 1 then
				return true
			end
		end
	end
	for _, pt in geometry.points do
		local dx, dy = x - pt.x, y - pt.y
		local reach = R + pt.radius
		if dx * dx + dy * dy < reach * reach and dx * vx + dy * vy < 0 then
			return true
		end
	end
	return false
end

-- A ball in the air going over a cushion is off the table (see goesOver). Lower than the
-- cushion top it would have hit the cushion instead (findEarliestHit).
local function checkOffTable(state: State, events: { Event }?)
	for _, b in state.balls do
		if
			Flight.isAirborne(b)
			and Simulation.goesOver(state.geometry, b.x, b.y, b.z, b.vx, b.vy)
		then
			leaveTable(b, events, state.time)
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

-- `skip`, when given, holds balls that sit this search out entirely (see Simulation.step).
local function findEarliestHit(
	state: State,
	maxT: number,
	skip: { [Ball]: boolean }?,
	anyAir: boolean
): Hit?
	local R = Config.Balls.RadiusInches
	local geometry = state.geometry
	local balls = state.balls
	local best: Hit? = nil
	local bestT = maxT

	local clear = Config.Table.CushionHeightInches
	for i, a in balls do
		if a.pocketed or (skip and skip[a]) then
			continue
		end
		local flying = anyAir and Flight.isAirborne(a)
		local moving = a.vx ~= 0 or a.vy ~= 0 or flying
		-- Broad phase: a ball that cannot reach the cushion line this step skips every rail
		-- and jaw test (facings and jaws all lie on or beyond the cushion line). A ball flying
		-- higher than the cushion passes over all of them.
		local reach = math.sqrt(a.vx * a.vx + a.vy * a.vy) * maxT + R
		local nearRail = math.abs(a.x) + reach >= geometry.halfLength
			or math.abs(a.y) + reach >= geometry.halfWidth
		if moving and nearRail and a.z < clear then
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
			if b.pocketed or (skip and skip[b]) then
				continue
			end
			if not moving and b.vx == 0 and b.vy == 0 and not anyAir then
				continue
			end
			local bFlying = anyAir and Flight.isAirborne(b)
			if not moving and b.vx == 0 and b.vy == 0 and not bFlying then
				continue
			end
			local t: number?
			if flying or bFlying then
				-- z moves in a parabola; over one AirStepSeconds window it is straight to well
				-- under a thousandth of an inch, and pushOut takes up the rest.
				t = Collision.sphereTOI(
					a.x,
					a.y,
					a.z,
					a.vx,
					a.vy,
					a.vz,
					b.x,
					b.y,
					b.z,
					b.vx,
					b.vy,
					b.vz,
					R,
					bestT
				)
			else
				t = Collision.circleTOI(a.x, a.y, a.vx, a.vy, b.x, b.y, b.vx, b.vy, R, bestT)
			end
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
	elseif hit.kind == "ball" and hit.b and (Flight.isAirborne(a) or Flight.isAirborne(hit.b)) then
		-- In the air: separate along the 3-D line of centres, moving only balls that are off
		-- the cloth (the slate holds the other one up). Separating in plan only wedged a ball
		-- coming down into a rack; lifting one adds height energy, so it is paid for out of
		-- that ball's own speed.
		local b = hit.b
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
		local want = 2 * R + slop
		if dist > 1e-12 and dist < want then
			local aFree, bFree = Flight.isAirborne(a), Flight.isAirborne(b)
			local nx, ny, nz = dx / dist, dy / dist, dz / dist
			local aShare = if aFree and bFree then 0.5 elseif aFree then 1 else 0
			local push = want - dist
			local function move(ball: Ball, sign: number, share: number)
				if share <= 0 then
					return
				end
				local z0 = ball.z
				ball.x += sign * nx * push * share
				ball.y += sign * ny * push * share
				ball.z = math.max(0, ball.z + sign * nz * push * share)
				local lift = ball.z - z0
				if lift > 0 then
					local g = Config.Physics.Gravity
					local kinetic = 0.5
						* (ball.vx * ball.vx + ball.vy * ball.vy + ball.vz * ball.vz)
					if kinetic > 0 then
						local scale = math.sqrt(math.max(0, kinetic - g * lift) / kinetic)
						ball.vx *= scale
						ball.vy *= scale
						ball.vz *= scale
					end
				end
			end
			move(a, -1, aShare)
			move(b, 1, 1 - aShare)
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

-- A ball hopping a fraction of an inch as it hits a group (a hard break) meets the first ball
-- above its centre. The group's contact is still soft, and soft contact is planar, so the
-- flyer is laid in the plane for the phase: moved back along the line of centres to just
-- touching (at most a few hundredths of an inch; SoftContactMaxHopInches bounds it).
-- Afterwards liftFlyer turns the momentum it handed over into the vertical kick the tilted
-- contact gives it (the struck ball's share goes into the slate), and takes the kick's energy
-- out of the group so nothing is created.
type Lift = {
	flyer: Ball,
	group: { Ball },
	nx: number,
	ny: number,
	tilt: number,
	vx: number,
	vy: number,
	energy: number,
}

local function layFlat(flyer: Ball, other: Ball, group: { Ball }): Lift
	local R = Config.Balls.RadiusInches
	local g = Config.Physics.Gravity
	local dx, dy, dz = other.x - flyer.x, other.y - flyer.y, other.z - flyer.z
	local horizontal = math.sqrt(dx * dx + dy * dy)
	local nx, ny =
		if horizontal > 1e-12 then dx / horizontal else 1,
		if horizontal > 1e-12 then dy / horizontal else 0
	local want = 2 * R + Config.Physics.ContactSlop
	if horizontal < want then
		flyer.x -= nx * (want - horizontal)
		flyer.y -= ny * (want - horizontal)
	end
	local energy = 0
	for _, m in group do
		energy += Ball.kineticEnergy(m, R, g)
	end
	-- Slope of the true contact normal: rise over run at the moment of touch.
	local run = math.sqrt(math.max(4 * R * R - dz * dz, 1e-12))
	return {
		flyer = flyer,
		group = group,
		nx = nx,
		ny = ny,
		tilt = -dz / run,
		vx = flyer.vx,
		vy = flyer.vy,
		energy = energy,
	}
end

local function liftFlyer(lift: Lift)
	local R = Config.Balls.RadiusInches
	local g = Config.Physics.Gravity
	local flyer = lift.flyer
	local handed = (lift.vx - flyer.vx) * lift.nx + (lift.vy - flyer.vy) * lift.ny
	if handed <= 0 then
		return
	end
	-- Only the ball in the air takes the vertical part: the slate holds the struck ball down.
	flyer.vz += lift.tilt * handed
	if flyer.z <= 0 and flyer.vz < 0 then
		flyer.vz = 0
	end
	-- Pay for the kick out of the group's horizontal motion if the phase's own losses did
	-- not already cover it.
	local horizontal, vertical = 0, 0
	for _, m in lift.group do
		local total = Ball.kineticEnergy(m, R, g)
		local up = 0.5 * m.vz * m.vz + g * m.z
		horizontal += total - up
		vertical += up
	end
	if horizontal > 0 and horizontal + vertical > lift.energy then
		local scale = math.sqrt(math.max(0, lift.energy - vertical) / horizontal)
		for _, m in lift.group do
			m.vx *= scale
			m.vy *= scale
			m.wx *= scale
			m.wy *= scale
			m.wz *= scale
		end
	end
end

-- Merge two event lists that are each in time order, the first list winning ties.
local function mergeEvents(into: { Event }, first: { Event }, second: { Event })
	local i, j = 1, 1
	while i <= #first or j <= #second do
		if j > #second or (i <= #first and first[i].t <= second[j].t) then
			table.insert(into, first[i])
			i += 1
		else
			table.insert(into, second[j])
			j += 1
		end
	end
end

-- Advance everything not in `skip` by `span` seconds, event by event. Returns the time left
-- over, which is negative when a soft phase ran past the end of the span.
--
-- A ball-ball contact that touches a third ball runs as one atomic soft phase (Cluster):
-- the group is integrated through the whole contact from the moment of impact, then every
-- other ball is brought up to the same time by this same loop with the group held out of
-- it. Cluster.gather guarantees nothing outside the group can reach it, or a cushion, in
-- that time, so the two halves cannot interact. The catch-up resolves contacts pairwise
-- (allowSoft false): two separate clusters struck within the same millisecond are rare
-- enough not to need nesting.
local function advance(
	state: State,
	span: number,
	events: { Event }?,
	skip: { [Ball]: boolean }?,
	allowSoft: boolean
): number
	local P = Config.Physics
	local remaining = span
	local iterations = 0
	-- Zero-time hits per ball this step. A ball wedged between two surfaces would bounce
	-- between them forever at t = 0; after a few dozen such hits it is stopped instead.
	local instantHits: { [Ball]: number } = {}

	while remaining > 1e-9 and iterations < P.MaxEventsPerStep do
		iterations += 1
		-- Anything in the air shortens the search window (see findEarliestHit).
		local window = remaining
		local anyAir = false
		for _, b in state.balls do
			-- Flight.isAirborne, inlined: this runs for every ball on every event.
			if not b.pocketed and (b.z > 0 or b.vz > 0) and not (skip and skip[b]) then
				window = math.min(remaining, P.AirStepSeconds)
				anyAir = true
				break
			end
		end
		local hit = findEarliestHit(state, window, skip, anyAir)
		local advanceBy = if hit then hit.t else window

		for _, b in state.balls do
			if skip == nil or not skip[b] then
				integrateBall(b, advanceBy, state.geometry, events, state.time + advanceBy)
			end
		end
		state.time += advanceBy
		remaining -= advanceBy
		capturePockets(state, events)
		if anyAir then
			checkOffTable(state, events)
		end

		if hit and not hit.a.pocketed and not (hit.b and hit.b.pocketed) then
			local soft: { Ball }? = nil
			local b = hit.b
			-- A ball hopping low into a group (a hard break's cue ball) still breaks it as soft
			-- contact; see liftFlyer. Higher, or two in the air, is the pairwise 3-D model.
			local flyer: Ball? = nil
			if b and Flight.isAirborne(hit.a) ~= Flight.isAirborne(b) then
				flyer = if Flight.isAirborne(hit.a) then hit.a else b
			end
			if
				allowSoft
				and hit.kind == "ball"
				and b
				and not (Flight.isAirborne(hit.a) and Flight.isAirborne(b))
				and (flyer == nil or math.abs(hit.a.z - b.z) <= P.SoftContactMaxHopInches)
				and Cluster.touchesAnother(state.balls, hit.a, b, skip)
			then
				soft = Cluster.gather(state.balls, hit.a, b, state.geometry, skip, flyer)
			end
			if soft and b then
				local lift = if flyer
					then layFlat(flyer, if flyer == hit.a then b else hit.a, soft)
					else nil
				-- The impact that started it is reported exactly as a pairwise hit would be.
				local relVn = 0
				local dx, dy = b.x - hit.a.x, b.y - hit.a.y
				local len = math.sqrt(dx * dx + dy * dy)
				if len > 1e-12 then
					relVn = ((hit.a.vx - b.vx) * dx + (hit.a.vy - b.vy) * dy) / len
				end
				if events and relVn > 0 then
					table.insert(events, {
						t = state.time,
						type = "ballHit",
						ball = hit.a.id,
						other = b.id,
						speed = relVn,
					})
				end
				local phaseEvents: { Event } = {}
				local emit: Cluster.Emit? = nil
				if events then
					emit = function(first: Ball, second: Ball, t: number, speed: number)
						table.insert(phaseEvents, {
							t = t,
							type = "ballHit",
							ball = first.id,
							other = second.id,
							speed = speed,
						})
					end
				end
				local duration = Cluster.resolve(soft, hit.a, b, state.time, emit)
				if lift then
					liftFlyer(lift)
				end

				-- Bring every other ball up to the end of the phase.
				local group: { [Ball]: boolean } = {}
				for _, m in soft do
					group[m] = true
				end
				local catchUp: { Event }? = if events then {} else nil
				advance(state, duration, catchUp, group, false)
				if events and catchUp then
					mergeEvents(events, phaseEvents, catchUp)
				end
				remaining -= duration
			else
				pushOut(hit)
				local speed: number
				local eventType: "railHit" | "ballHit"
				local other: number? = nil
				if hit.kind == "ball" and b then
					speed = resolveBalls(hit.a, b)
					eventType = "ballHit"
					other = b.id
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
			end
			if hit.t <= P.InstantHitSeconds then
				local n = (instantHits[hit.a] or 0) + 1
				instantHits[hit.a] = n
				if n >= P.MaxInstantHits then
					Ball.stop(hit.a) -- wedged: it is not going anywhere
					if b then
						Ball.stop(b)
					end
				end
			end
			if iterations >= P.MaxEventsPerStep then
				-- Budget exhausted: whatever is still colliding is stuck. Stop it rather than
				-- burning the whole shot on it.
				Ball.stop(hit.a)
				if b then
					Ball.stop(b)
				end
			end
		end
	end
	return remaining
end

--- Advance the simulation by one fixed step, appending any contact events.
---
--- A soft cluster contact (see Cluster) is resolved atomically, so a step in which one
--- starts close to its end runs on to the moment it lets go: state.time can end up to
--- SoftContactMaxSeconds past the step, and the next step simply starts from there. The
--- server's settle and a client's frame-by-frame replay both call this with the same fixed
--- step from the same strike, so they overrun at exactly the same places.
function Simulation.step(state: State, dt: number, events: { Event }?)
	advance(state, dt, events, nil, true)
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
	cue.offTable = false
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
