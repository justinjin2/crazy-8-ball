--!strict
-- Ball: plain data for one ball in the simulation. Positions in inches, velocities in
-- inches per second, angular velocity in radians per second.
--
-- Axes: x runs along the table length, y across the width, z points up out of the cloth.
--   wx, wy  = "roll" spin (top spin / back spin live here, perpendicular to travel)
--   wz      = side spin (english), positive = counter-clockwise seen from above
-- Ball id 0 is always the cue ball. 1-7 solids, 8 the eight, 9-15 stripes.

local Ball = {}

-- A ball part-way over a pocket lip, pivoting about the rim point it crossed. `px, py` is
-- that rim point (it drifts with whatever sideways speed the ball arrived with), `nx, ny` is
-- the fixed unit direction from it towards the pocket centre, `theta` is the angle of the
-- ball's centre off vertical above the pivot and `omega` its rate.
export type Tip = {
	px: number,
	py: number,
	nx: number,
	ny: number,
	theta: number,
	omega: number,
}

export type Ball = {
	id: number,
	x: number,
	y: number,
	z: number, -- height of the centre above its resting height on the cloth (0 on the table, negative while dropping into a pocket)
	vx: number,
	vy: number,
	vz: number,
	wx: number,
	wy: number,
	wz: number,
	pocketed: boolean, -- captured by a pocket, or off the table (rules use this)
	offTable: boolean, -- flew off the table (always also pocketed, with no pocket)
	falling: boolean, -- still dropping into the pocket (animation still running)
	pocket: number?, -- pocket id once captured
	tip: Tip?, -- set while the ball is still toppling over the lip, before it drops free
}

function Ball.new(id: number, x: number, y: number): Ball
	return {
		id = id,
		x = x,
		y = y,
		z = 0,
		vx = 0,
		vy = 0,
		vz = 0,
		wx = 0,
		wy = 0,
		wz = 0,
		pocketed = false,
		offTable = false,
		falling = false,
		pocket = nil,
		tip = nil,
	}
end

function Ball.clone(b: Ball): Ball
	return {
		id = b.id,
		x = b.x,
		y = b.y,
		z = b.z,
		vx = b.vx,
		vy = b.vy,
		vz = b.vz,
		wx = b.wx,
		wy = b.wy,
		wz = b.wz,
		pocketed = b.pocketed,
		offTable = b.offTable,
		falling = b.falling,
		pocket = b.pocket,
		tip = if b.tip then table.clone(b.tip) else nil,
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

--- True while motion can affect the shot (including a pocket drop and a ball in the air).
--- Horizontal spin can restart translation through cloth friction; side spin alone does not
--- keep a shot open.
function Ball.isMoving(b: Ball): boolean
	if b.pocketed then
		return b.falling
	end
	return b.vx ~= 0 or b.vy ~= 0 or b.wx ~= 0 or b.wy ~= 0 or b.z > 0 or b.vz ~= 0
end

function Ball.stop(b: Ball)
	b.vx, b.vy, b.vz, b.wx, b.wy, b.wz = 0, 0, 0, 0, 0, 0
end

--- Mechanical energy for a unit mass: translational plus rotational (solid sphere,
--- I = 2/5 R^2), plus height above the cloth for a ball in the air (zero on the table).
function Ball.kineticEnergy(b: Ball, radius: number, gravity: number?): number
	if b.pocketed then
		return 0
	end
	local linear = 0.5 * (b.vx * b.vx + b.vy * b.vy + b.vz * b.vz) + (gravity or 0) * b.z
	local inertia = 0.4 * radius * radius
	local rotational = 0.5 * inertia * (b.wx * b.wx + b.wy * b.wy + b.wz * b.wz)
	return linear + rotational
end

return Ball
