--!strict
-- Flight: a ball off the cloth. Jump shots, a hard break's hop and a ball knocked into the air.
--
-- A ball is AIRBORNE while its centre is above its resting height (z > 0) or it is moving up.
-- In the air it flies a parabola: no cloth friction, spin kept, gravity on z. It comes down
-- on the slate and either bounces (the slate's restitution) or, if the bounce would be
-- smaller than MinHopSpeed, the cloth swallows it and the ball is back on the table.
--
-- The slate is also what makes a jump shot: an elevated cue drives the ball down into it and
-- it rebounds (see Cue.strike). Everything lands through Flight.slate, so the cue, a landing
-- and a ball pushed down by another ball all bounce by the same rule.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)

type Ball = Ball.Ball

local Flight = {}

--- True while the ball is in the air (never for a pocketed or off-table ball).
function Flight.isAirborne(b: Ball): boolean
	return not b.pocketed and (b.z > 0 or b.vz > 0)
end

--- Time until a ball at height z moving up at vz comes back down to the cloth.
function Flight.landingTime(z: number, vz: number): number
	local g = Config.Physics.Gravity
	return (vz + math.sqrt(math.max(0, vz * vz + 2 * g * math.max(z, 0)))) / g
end

--- Fly an airborne ball for up to h seconds. Returns the time flown: less than h when it
--- touched the cloth, in which case it is left exactly at z = 0 still moving down.
function Flight.fly(b: Ball, h: number): number
	local g = Config.Physics.Gravity
	local land = Flight.landingTime(b.z, b.vz)
	local dt = math.min(land, h)
	b.x += b.vx * dt
	b.y += b.vy * dt
	if land <= h then
		b.vz -= g * land
		b.z = 0
	else
		b.z = math.max(0, b.z + b.vz * dt - 0.5 * g * dt * dt)
		b.vz -= g * dt
	end
	return dt
end

--- Seconds until a ball that left the table at height z, moving up at vz, reaches the floor
--- a cloth's height below (Config.Table.SurfaceHeightInches). The renderer draws that fall
--- and the server waits for it before calling the foul.
function Flight.floorTime(z: number, vz: number): number
	local g = Config.Physics.Gravity
	local drop = math.max(z, 0) + Config.Table.SurfaceHeightInches
	return (vz + math.sqrt(math.max(0, vz * vz + 2 * g * drop))) / g
end

--- The slate pushes back on a ball driven into it at `downSpeed` (in/s, positive). The ball
--- rebounds at SlateRestitution (or `restitution`) times that, less ClothHopLossSpeed (and
--- `friction` replaces SlateFriction),
--- with Coulomb friction at the contact changing its skid and spin like a short slide on the
--- cloth. A rebound under MinHopSpeed is swallowed and the ball stays on the table; then,
--- unless `always` is set (a real landing), nothing else changes either, so every ordinary
--- shot plays exactly as it did before jumps existed. Returns true if the ball is in the air.
function Flight.slate(
	b: Ball,
	downSpeed: number,
	always: boolean,
	restitution: number?,
	friction: number?
): boolean
	local P = Config.Physics
	local e = restitution or P.SlateRestitution
	local up = e * downSpeed - P.ClothHopLossSpeed
	local hops = up >= P.MinHopSpeed
	b.z = 0
	b.vz = 0
	if not hops and not always then
		return false
	end
	local R = Config.Balls.RadiusInches
	-- The slate's push: stopping the fall, plus the rebound it sends back up.
	local normalImpulse = downSpeed + (if hops then up else 0)
	local ux, uy = b.vx - R * b.wy, b.vy + R * b.wx
	local u = math.sqrt(ux * ux + uy * uy)
	if u > P.SlideEpsilon then
		-- Unit mass, solid sphere: contact inverse mass 1 + 5/2, as in cloth sliding.
		local impulse = math.min(u / 3.5, (friction or P.SlateFriction) * normalImpulse)
		local uhx, uhy = ux / u, uy / u
		b.vx -= impulse * uhx
		b.vy -= impulse * uhy
		b.wx -= 2.5 * impulse * uhy / R
		b.wy += 2.5 * impulse * uhx / R
	end
	if hops then
		b.vz = up
	end
	return hops
end

return Flight
