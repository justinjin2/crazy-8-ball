--!strict
-- Ball: plain data for one ball in the simulation. Positions in inches, velocities in
-- inches per second, angular velocity in radians per second.
--
-- Axes: x runs along the table length, y across the width, z points up out of the cloth.
--   wx, wy  = "roll" spin (top spin / back spin live here, perpendicular to travel)
--   wz      = side spin (english), positive = counter-clockwise seen from above
-- Ball id 0 is always the cue ball. 1-7 solids, 8 the eight, 9-15 stripes.

local Ball = {}

export type Ball = {
	id: number,
	x: number,
	y: number,
	vx: number,
	vy: number,
	wx: number,
	wy: number,
	wz: number,
	pocketed: boolean,
}

function Ball.new(id: number, x: number, y: number): Ball
	return {
		id = id,
		x = x,
		y = y,
		vx = 0,
		vy = 0,
		wx = 0,
		wy = 0,
		wz = 0,
		pocketed = false,
	}
end

function Ball.clone(b: Ball): Ball
	return {
		id = b.id,
		x = b.x,
		y = b.y,
		vx = b.vx,
		vy = b.vy,
		wx = b.wx,
		wy = b.wy,
		wz = b.wz,
		pocketed = b.pocketed,
	}
end

function Ball.cloneList(list: { Ball }): { Ball }
	local out = table.create(#list)
	for i, b in list do
		out[i] = Ball.clone(b)
	end
	return out
end

function Ball.speed(b: Ball): number
	return math.sqrt(b.vx * b.vx + b.vy * b.vy)
end

--- True when the ball is moving or spinning at all.
function Ball.isMoving(b: Ball): boolean
	if b.pocketed then
		return false
	end
	return b.vx ~= 0 or b.vy ~= 0 or b.wx ~= 0 or b.wy ~= 0 or b.wz ~= 0
end

function Ball.stop(b: Ball)
	b.vx, b.vy, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0
end

--- Kinetic energy for a unit mass: translational plus rotational (solid sphere, I = 2/5 R^2).
function Ball.kineticEnergy(b: Ball, radius: number): number
	if b.pocketed then
		return 0
	end
	local linear = 0.5 * (b.vx * b.vx + b.vy * b.vy)
	local inertia = 0.4 * radius * radius
	local rotational = 0.5 * inertia * (b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
	return linear + rotational
end

return Ball
