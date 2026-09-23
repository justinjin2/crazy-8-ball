--!strict
-- Placement: where one table stands in the world, and the conversion between that table's
-- own physics coordinates and Roblox world space. Pure Luau: plain numbers in, plain numbers
-- out, no Roblox types, so it runs in Lune and on the server and is covered by tests.
--
-- Axes. Physics x runs along the table length (head rail negative, foot rail positive), y
-- across the width, z up out of the cloth; the units are inches. World units are studs.
-- A table at yaw 0 maps physics x -> world +X, y -> world -Z, z -> world +Y. Yaw turns the
-- table about world +Y exactly the way Roblox does (CFrame.Angles(0, yaw, 0)), so at yaw 90
-- the length runs along world -Z and the width along world -X.
--
-- Why this is its own pure module rather than a few lines inside TableBuilder: a pool table
-- is symmetric end to end, so yaw +90 and yaw -90 produce tables that LOOK identical but
-- mirror the playfield. A sign error there would silently mirror the guideline with nothing
-- on screen to give it away. Pure numbers mean tests/placement_test.luau can prove it.

local Config = require(script.Parent.Config)

local Placement = {}

export type Placement = {
	-- World studs of the table centre at FLOOR level. toWorld adds the cloth height on top,
	-- so this is the tier the table stands on, not the playing surface.
	x: number,
	y: number,
	z: number,
	yaw: number, -- radians about world +Y
	cos: number,
	sin: number,
}

function Placement.new(x: number, y: number, z: number, yawDegrees: number): Placement
	local yaw = math.rad(yawDegrees)
	return {
		x = x,
		y = y,
		z = z,
		yaw = yaw,
		cos = math.cos(yaw),
		sin = math.sin(yaw),
	}
end

--- How many tables this build actually stands up: twelve in the lounge, one on a testing
--- baseplate. Everything that iterates tables goes through this so the server, the pads and
--- the client cannot disagree about how many there are.
function Placement.tableCount(): number
	return math.clamp(Config.Lounge.TableCount, 1, #Config.Lounge.Tables)
end

--- The placement for table `id` in Config.Lounge.Tables (1-12), or nil if there is no such
--- table. Results are built once and reused.
local cache: { [number]: Placement } = {}
function Placement.forTable(id: number): Placement?
	local cached = cache[id]
	if cached then
		return cached
	end
	for _, row in Config.Lounge.Tables do
		if row.id == id then
			local made = Placement.new(row.X, row.Y, row.Z, row.YawDegrees)
			cache[id] = made
			return made
		end
	end
	return nil
end

--- World position (studs) for a physics point (inches) at `heightIn` above the cloth.
--- Returns three numbers so this module never has to name a Roblox type; callers that want
--- a Vector3 wrap it (see TableBuilder.toWorld).
function Placement.toWorld(
	p: Placement,
	xIn: number,
	yIn: number,
	heightIn: number
): (number, number, number)
	local s = Config.Table.StudsPerInch
	return p.x + s * (xIn * p.cos - yIn * p.sin),
		p.y + (Config.Table.SurfaceHeightInches + heightIn) * s,
		p.z - s * (xIn * p.sin + yIn * p.cos)
end

--- Physics coordinates (inches) for a world position (studs). The height is ignored: this
--- is the inverse of toWorld's x and z only.
function Placement.toTable(p: Placement, worldX: number, worldZ: number): (number, number)
	local s = Config.Table.StudsPerInch
	local dx = (worldX - p.x) / s
	local dz = (worldZ - p.z) / s
	return dx * p.cos - dz * p.sin, -dx * p.sin - dz * p.cos
end

--- Turn a direction in table space into a world direction. Origin and scale play no part,
--- so a unit vector in stays a unit vector out.
--- Half extents, in studs along the table's own length and width, of the invisible wall
--- around a table: the table with its rails plus Multiplayer.Barrier.MarginStuds.
function Placement.barrierHalfExtents(): (number, number)
	local T, B = Config.Table, Config.Multiplayer.Barrier
	local s = T.StudsPerInch
	return (T.LengthInches / 2 + T.RailWidthInches) * s + B.MarginStuds,
		(T.WidthInches / 2 + T.RailWidthInches) * s + B.MarginStuds
end

--- If a world point is inside the barrier (grown by `clearance` studs), the nearest world
--- point that is `clearance` clear of it; otherwise nil. Used to step a character that was
--- posed against the rail back out before it is handed back to physics.
function Placement.outsideBarrier(
	p: Placement,
	worldX: number,
	worldZ: number,
	clearance: number
): (number?, number?)
	local s = Config.Table.StudsPerInch
	local hx, hy = Placement.barrierHalfExtents()
	hx, hy = hx + clearance, hy + clearance
	local x, y = Placement.toTable(p, worldX, worldZ)
	x, y = x * s, y * s -- studs along the table's axes
	if math.abs(x) >= hx or math.abs(y) >= hy then
		return nil, nil
	end
	-- Leave through whichever side is nearest.
	if hx - math.abs(x) < hy - math.abs(y) then
		x = if x < 0 then -hx else hx
	else
		y = if y < 0 then -hy else hy
	end
	local wx, _, wz = Placement.toWorld(p, x / s, y / s, 0)
	return wx, wz
end

function Placement.dirToWorld(p: Placement, xIn: number, yIn: number): (number, number)
	return xIn * p.cos - yIn * p.sin, -(xIn * p.sin + yIn * p.cos)
end

--- Turn a world direction into a table-space direction (the inverse of dirToWorld).
function Placement.dirToTable(p: Placement, worldX: number, worldZ: number): (number, number)
	return worldX * p.cos - worldZ * p.sin, -(worldX * p.sin + worldZ * p.cos)
end

local function unit(x: number, y: number): (number, number)
	local length = math.sqrt(x * x + y * y)
	if length < 1e-9 then
		return 0, 0
	end
	return x / length, y / length
end

-- The sign of `primary` when it is big enough to trust, else of `fallback`.
local function toward(primary: number, fallback: number): number
	local v = if math.abs(primary) >= Config.Multiplayer.BreakAxisMinComponent
		then primary
		else fallback
	return if v < 0 then -1 else 1
end

--- Map a camera-relative move to a table-space delta, so an arrow or a stick moves the cue
--- ball the way it looks on screen from any camera. rightX/Z and forwardX/Z are the camera's
--- right and forward vectors in world space (height ignored); sx/sy are the screen move, +x
--- right and +y up (away from the camera), in the same units as the result. With
--- `lateralOnly` (the break) the ball may only slide along the head string: the result is
--- (0, along). A `discrete` move (an arrow press) never goes dead, whichever way the line
--- runs on screen; an analog move (the stick) is its plain projection onto the line, so the
--- response stays smooth as the stick sweeps round.
function Placement.screenDelta(
	p: Placement,
	rightX: number,
	rightZ: number,
	forwardX: number,
	forwardZ: number,
	sx: number,
	sy: number,
	lateralOnly: boolean?,
	discrete: boolean?
): (number, number)
	local rx, ry = unit(Placement.dirToTable(p, rightX, rightZ))
	local fx, fy = unit(Placement.dirToTable(p, forwardX, forwardZ))
	if not lateralOnly then
		return rx * sx + fx * sy, ry * sx + fy * sy
	end
	local along = ry * sx + fy * sy
	if not discrete then
		return 0, along
	end
	-- A single-axis arrow is a full step along the line: toward whichever end the press
	-- points at, or, when the line runs nearly square to that axis on screen, toward the end
	-- the other axis points at.
	if sy == 0 then
		along = toward(ry, fy) * sx
	elseif sx == 0 then
		along = toward(fy, ry) * sy
	end
	return 0, along
end

--- The world-space aim direction for a physics aim angle, as (x, y, z) with y always 0.
--- Equivalent to dirToWorld(p, cos(angle), sin(angle)), written out because it collapses to
--- a single rotation by angle + yaw.
function Placement.aimVector(p: Placement, angle: number): (number, number, number)
	local a = angle + p.yaw
	return math.cos(a), 0, -math.sin(a)
end

--- The physics aim angle for a world direction: the inverse of aimVector.
function Placement.aimAngle(p: Placement, worldX: number, worldZ: number): number
	return (math.atan2(-worldZ, worldX) - p.yaw) % (2 * math.pi)
end

return Placement
