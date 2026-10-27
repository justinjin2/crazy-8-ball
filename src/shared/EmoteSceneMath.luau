--!strict
-- EmoteSceneMath: the plain arithmetic behind our own emotes' scenes (src/client/EmoteScene.luau,
-- Config.EmoteMenu.Custom): where Bullseye's target stands (never over a table), whether
-- Popcorn's umbrella fits, the handful of popcorn Popcorn throws (about half of it misses), and
-- a thrown kernel's arc. Pure: no Instances and no Roblox types, so
-- tests/emote_scene_math_test.luau runs it in Lune. Visual only, so trig is fine here.

local EmoteSceneMath = {}

-- A table's box on the floor: its centre (world X, Z), its yaw as Placement keeps it (cos, sin)
-- and its half extents along its own length (hx) and width (hz), studs.
export type Box = { x: number, z: number, cos: number, sin: number, hx: number, hz: number }

-- Where Bullseye's target may stand: straight ahead of the dancer (origin ox, oz; unit
-- direction dx, dz on the floor), its face `near` to `far` studs out at full size, or shrunk
-- (down to minScale, in `steps` steps) as close as `tight` when that does not fit. `wall`: how
-- far ahead the first wall is (math.huge: none). The target reaches `back` behind its face and
-- `half` to each side at full size; it never comes within `margin` of a table's box.
export type TargetSpec = {
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	wall: number,
	boxes: { Box },
	near: number,
	far: number,
	tight: number,
	back: number,
	half: number,
	margin: number,
	minScale: number,
	steps: number,
}

-- A kernel of a handful: whether it misses the mouth, which mesh (1 or 2), where it lands on
-- the face or mouth across and up (-1 to 1 each), how much later than the first it leaves the
-- hand (0 to 1, a share of the spread), its spin (degrees) and its bounce off the face
-- (sideways -1 to 1, how hard 0 to 1).
export type Kernel = {
	miss: boolean,
	kind: number,
	side: number,
	lift: number,
	lag: number,
	spin: { number },
	sideways: number,
	hard: number,
}

--- A repeatable stream of numbers in [0, 1) from `seed` (a 32-bit linear congruential
--- generator: the same seed gives the same handful on every client).
function EmoteSceneMath.rng(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 4294967296
	return function(): number
		state = (1664525 * state + 1013904223) % 4294967296
		return state / 4294967296
	end
end

-- A world offset (x, z) from a box's centre in the box's own axes.
local function toBox(box: Box, x: number, z: number): (number, number)
	return x * box.cos - z * box.sin, x * box.sin + z * box.cos
end

--- How far a ray from (ox, oz) along the unit direction (dx, dz) runs before it enters `box`
--- grown by `grow` on every side: 0 if it starts inside, math.huge if it never does.
function EmoteSceneMath.boxEnter(
	ox: number,
	oz: number,
	dx: number,
	dz: number,
	box: Box,
	grow: number
): number
	local lx, lz = toBox(box, ox - box.x, oz - box.z)
	local ux, uz = toBox(box, dx, dz)
	local enter, leave = 0, math.huge
	for _, axis in { { lx, ux, box.hx + grow }, { lz, uz, box.hz + grow } } do
		local p, u, h = axis[1], axis[2], axis[3]
		if math.abs(u) < 1e-9 then
			if math.abs(p) > h then
				return math.huge -- running alongside, outside
			end
		else
			local t1, t2 = (-h - p) / u, (h - p) / u
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			enter = math.max(enter, t1)
			leave = math.min(leave, t2)
			if enter > leave then
				return math.huge
			end
		end
	end
	return enter
end

--- How far the point (x, z) is from `box` (0 inside or on it).
function EmoteSceneMath.boxDistance(x: number, z: number, box: Box): number
	local lx, lz = toBox(box, x - box.x, z - box.z)
	local ox = math.max(math.abs(lx) - box.hx, 0)
	local oz = math.max(math.abs(lz) - box.hz, 0)
	return math.sqrt(ox * ox + oz * oz)
end

--- Whether a circle at (x, z) of `radius` keeps `margin` off every box (Popcorn's umbrella).
function EmoteSceneMath.clearOf(
	boxes: { Box },
	x: number,
	z: number,
	radius: number,
	margin: number
): boolean
	for _, box in boxes do
		if EmoteSceneMath.boxDistance(x, z, box) < radius + margin then
			return false
		end
	end
	return true
end

--- Where Bullseye's target stands: (distance of its face straight ahead, scale), or nil when
--- only a spot over a table would fit (then there is no target; a wall never stops it: in the
--- worst case it stands at `tight`, as small as it gets).
function EmoteSceneMath.targetSpot(spec: TargetSpec): (number?, number)
	-- The farthest its face may stand at scale s: its back clear of the wall and of the tables.
	local function tables(s: number): number
		local limit = math.huge
		for _, box in spec.boxes do
			local enter = EmoteSceneMath.boxEnter(
				spec.ox,
				spec.oz,
				spec.dx,
				spec.dz,
				box,
				spec.half * s + spec.margin
			)
			limit = math.min(limit, enter - spec.back * s)
		end
		return limit
	end
	local function reach(s: number): number
		return math.min(spec.wall - spec.back * s, tables(s))
	end
	local full = reach(1)
	if full >= spec.near then
		return math.min(full, spec.far), 1
	end
	local steps = math.max(spec.steps, 1)
	for i = 1, steps do
		local s = 1 - (1 - spec.minScale) * i / steps
		local d = reach(s)
		if d >= spec.tight then
			return math.min(d, spec.far), s
		end
	end
	if tables(spec.minScale) < spec.tight then
		return nil, spec.minScale
	end
	return spec.tight, spec.minScale
end

--- One handful of `count` kernels from `seed`: round(count * missShare) of them miss (which
--- ones is shuffled), the rest go in the mouth.
function EmoteSceneMath.handful(seed: number, count: number, missShare: number): { Kernel }
	local roll = EmoteSceneMath.rng(seed)
	local misses = math.floor(count * math.clamp(missShare, 0, 1) + 0.5)
	local flags: { boolean } = {}
	for i = 1, count do
		flags[i] = i <= misses
	end
	for i = count, 2, -1 do
		local j = 1 + math.floor(roll() * i)
		flags[i], flags[j] = flags[j], flags[i]
	end
	local out: { Kernel } = {}
	for i = 1, count do
		table.insert(out, {
			miss = flags[i],
			kind = if roll() < 0.5 then 1 else 2,
			side = roll() * 2 - 1,
			lift = roll() * 2 - 1,
			lag = roll(),
			spin = { roll() * 360, roll() * 360, roll() * 360 },
			sideways = roll() * 2 - 1,
			hard = roll(),
		})
	end
	return out
end

--- The launch velocity that carries a thrown thing from (x0, y0, z0) to (x1, y1, z1) in
--- `seconds` under `gravity` (studs/s^2, pulling down).
function EmoteSceneMath.launch(
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	seconds: number,
	gravity: number
): (number, number, number)
	local t = math.max(seconds, 1e-3)
	return (x1 - x0) / t, (y1 - y0) / t + 0.5 * gravity * t, (z1 - z0) / t
end

--- How long something thrown up at `vy` takes to fall `drop` studs below where it started.
function EmoteSceneMath.fallTime(drop: number, vy: number, gravity: number): number
	local g = math.max(gravity, 1e-3)
	return (vy + math.sqrt(math.max(vy * vy + 2 * g * drop, 0))) / g
end

--- Where something launched at (vx, vy, vz) is `t` seconds later, from the start.
function EmoteSceneMath.arc(
	vx: number,
	vy: number,
	vz: number,
	gravity: number,
	t: number
): (number, number, number)
	return vx * t, vy * t - 0.5 * gravity * t * t, vz * t
end

return EmoteSceneMath
