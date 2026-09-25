--!strict
-- Collision: exact time-of-impact tests for circles (and spheres) moving at constant velocity.
-- Every test returns the impact time in [0, maxT] or nil, plus the contact normal
-- pointing from the obstacle INTO the ball (the direction to push the ball out).
-- Nothing here changes state; Simulation resolves the hits.

local Collision = {}

type Segment = { ax: number, ay: number, bx: number, by: number, nx: number, ny: number }

--- Moving circle against the flat face of a segment (end caps are handled by pointTOI).
function Collision.segmentTOI(
	px: number,
	py: number,
	vx: number,
	vy: number,
	r: number,
	seg: Segment,
	maxT: number
): number?
	local vn = vx * seg.nx + vy * seg.ny
	if vn >= 0 then
		return nil -- moving away from, or parallel to, the face
	end
	local d = (px - seg.ax) * seg.nx + (py - seg.ay) * seg.ny
	if d < 0 then
		-- Centre is behind this face. Impact times are exact and push-out keeps balls in
		-- front of every face they touch, so this can only be a face whose back side the
		-- ball is legitimately passing (e.g. a jaw facing seen from the rail side).
		return nil
	end
	local t = if d <= r then 0 else (d - r) / -vn
	if t > maxT then
		return nil
	end
	-- The contact point must land within the segment span.
	local cx = px + vx * t - r * seg.nx
	local cy = py + vy * t - r * seg.ny
	local ex, ey = seg.bx - seg.ax, seg.by - seg.ay
	local s = ((cx - seg.ax) * ex + (cy - seg.ay) * ey) / (ex * ex + ey * ey)
	if s < 0 or s > 1 then
		return nil
	end
	return t
end

--- Moving circle against a fixed circle (radius qr, zero for a sharp corner).
--- Returns t, nx, ny.
function Collision.pointTOI(
	px: number,
	py: number,
	vx: number,
	vy: number,
	r: number,
	qx: number,
	qy: number,
	qr: number,
	maxT: number
): (number?, number, number)
	local dx, dy = px - qx, py - qy
	local b = 2 * (dx * vx + dy * vy)
	if b >= 0 then
		return nil, 0, 0 -- separating
	end
	local a = vx * vx + vy * vy
	if a <= 0 then
		return nil, 0, 0
	end
	local rr = r + qr
	local c = dx * dx + dy * dy - rr * rr
	local t: number
	if c <= 0 then
		t = 0
	else
		local disc = b * b - 4 * a * c
		if disc < 0 then
			return nil, 0, 0
		end
		t = (-b - math.sqrt(disc)) / (2 * a)
	end
	if t > maxT then
		return nil, 0, 0
	end
	local nx, ny = px + vx * t - qx, py + vy * t - qy
	local len = math.sqrt(nx * nx + ny * ny)
	if len < 1e-12 then
		return nil, 0, 0
	end
	return t, nx / len, ny / len
end

--- Two moving circles of equal radius r. Returns t or nil.
function Collision.circleTOI(
	ax: number,
	ay: number,
	avx: number,
	avy: number,
	bx: number,
	by: number,
	bvx: number,
	bvy: number,
	r: number,
	maxT: number
): number?
	local dx, dy = ax - bx, ay - by
	local dvx, dvy = avx - bvx, avy - bvy
	local b = 2 * (dx * dvx + dy * dvy)
	if b >= 0 then
		return nil -- separating
	end
	local a = dvx * dvx + dvy * dvy
	if a <= 0 then
		return nil
	end
	local rr = 2 * r
	local c = dx * dx + dy * dy - rr * rr
	local t: number
	if c <= 0 then
		t = 0
	else
		local disc = b * b - 4 * a * c
		if disc < 0 then
			return nil
		end
		t = (-b - math.sqrt(disc)) / (2 * a)
	end
	if t > maxT then
		return nil
	end
	return t
end

--- Two equal spheres of radius r moving at constant 3-D velocity (a ball in the air against
--- another ball; Simulation keeps the step short enough that gravity's curve is negligible).
--- Returns t or nil.
function Collision.sphereTOI(
	ax: number,
	ay: number,
	az: number,
	avx: number,
	avy: number,
	avz: number,
	bx: number,
	by: number,
	bz: number,
	bvx: number,
	bvy: number,
	bvz: number,
	r: number,
	maxT: number
): number?
	local dx, dy, dz = ax - bx, ay - by, az - bz
	local dvx, dvy, dvz = avx - bvx, avy - bvy, avz - bvz
	local b = 2 * (dx * dvx + dy * dvy + dz * dvz)
	if b >= 0 then
		return nil -- separating
	end
	local a = dvx * dvx + dvy * dvy + dvz * dvz
	if a <= 0 then
		return nil
	end
	local rr = 2 * r
	local c = dx * dx + dy * dy + dz * dz - rr * rr
	local t: number
	if c <= 0 then
		t = 0
	else
		local disc = b * b - 4 * a * c
		if disc < 0 then
			return nil
		end
		t = (-b - math.sqrt(disc)) / (2 * a)
	end
	if t > maxT then
		return nil
	end
	return t
end

return Collision
