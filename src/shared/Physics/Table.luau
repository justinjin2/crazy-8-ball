--!strict
-- Table: the collision geometry of the playing surface, built from Config numbers.
--
-- Coordinates: origin at the table centre, x along the length (head rail at -x, foot rail
-- at +x), y across the width. All values in inches.
--
-- Rails are line segments with an inward-facing normal. They stop short of every pocket,
-- leaving a mouth. Points are small fixed circles (the jaws at each rail end, or sharp
-- corners on a closed table). Pockets are capture circles sitting just beyond the cushion
-- line; a ball is also pocketed the moment its centre crosses the cushion line, since the
-- only way past that line is through a mouth.

local Config = require(script.Parent.Parent.Config)

local TableGeometry = {}

export type Segment = {
	ax: number,
	ay: number,
	bx: number,
	by: number,
	nx: number, -- inward normal (unit)
	ny: number,
	name: string,
}

export type Point = { x: number, y: number, radius: number, name: string }

export type Pocket = { id: number, x: number, y: number, radius: number, name: string }

export type Geometry = {
	halfLength: number,
	halfWidth: number,
	pocketsOpen: boolean,
	segments: { Segment },
	points: { Point },
	pockets: { Pocket },
}

export type BuildOptions = { pocketsOpen: boolean? }

local function segment(
	ax: number,
	ay: number,
	bx: number,
	by: number,
	nx: number,
	ny: number,
	name: string
): Segment
	return { ax = ax, ay = ay, bx = bx, by = by, nx = nx, ny = ny, name = name }
end

local function point(x: number, y: number, radius: number, name: string): Point
	return { x = x, y = y, radius = radius, name = name }
end

local function buildClosed(geometry: Geometry)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	geometry.segments = {
		segment(-hl, hw, hl, hw, 0, -1, "top"),
		segment(-hl, -hw, hl, -hw, 0, 1, "bottom"),
		segment(hl, -hw, hl, hw, -1, 0, "foot"),
		segment(-hl, -hw, -hl, hw, 1, 0, "head"),
	}
	geometry.points = {
		point(-hl, -hw, 0, "corner"),
		point(hl, -hw, 0, "corner"),
		point(hl, hw, 0, "corner"),
		point(-hl, hw, 0, "corner"),
	}
end

local function buildOpen(geometry: Geometry)
	local T = Config.Table
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local jr = T.JawRadiusInches
	-- Jaw circles sit just outside the cushion line so a ball rolling along a rail brushes
	-- past them instead of being kicked by them.
	local jawOut = jr + 0.05
	-- Corner mouths cut the rails back by c along each rail; the gap between the two jaw
	-- circles across the diagonal equals CornerMouthInches.
	local c = (T.CornerMouthInches + 2 * jr) / math.sqrt(2)
	-- Side mouths: half the gap between jaw circles plus the jaw radius.
	local sm = T.SideMouthInches / 2 + jr

	geometry.segments = {
		segment(-hl + c, hw, -sm, hw, 0, -1, "topLeft"),
		segment(sm, hw, hl - c, hw, 0, -1, "topRight"),
		segment(-hl + c, -hw, -sm, -hw, 0, 1, "bottomLeft"),
		segment(sm, -hw, hl - c, -hw, 0, 1, "bottomRight"),
		segment(hl, -hw + c, hl, hw - c, -1, 0, "foot"),
		segment(-hl, -hw + c, -hl, hw - c, 1, 0, "head"),
	}

	geometry.points = {
		-- top rail ends
		point(-hl + c, hw + jawOut, jr, "jaw"),
		point(-sm, hw + jawOut, jr, "jaw"),
		point(sm, hw + jawOut, jr, "jaw"),
		point(hl - c, hw + jawOut, jr, "jaw"),
		-- bottom rail ends
		point(-hl + c, -hw - jawOut, jr, "jaw"),
		point(-sm, -hw - jawOut, jr, "jaw"),
		point(sm, -hw - jawOut, jr, "jaw"),
		point(hl - c, -hw - jawOut, jr, "jaw"),
		-- foot rail ends
		point(hl + jawOut, -hw + c, jr, "jaw"),
		point(hl + jawOut, hw - c, jr, "jaw"),
		-- head rail ends
		point(-hl - jawOut, -hw + c, jr, "jaw"),
		point(-hl - jawOut, hw - c, jr, "jaw"),
	}

	local ci = T.CornerPocketInsetInches / math.sqrt(2)
	local cr = T.CornerPocketRadiusInches
	local si = T.SidePocketInsetInches
	local sr = T.SidePocketRadiusInches
	geometry.pockets = {
		{ id = 1, x = -hl - ci, y = hw + ci, radius = cr, name = "topLeft" },
		{ id = 2, x = 0, y = hw + si, radius = sr, name = "topSide" },
		{ id = 3, x = hl + ci, y = hw + ci, radius = cr, name = "topRight" },
		{ id = 4, x = hl + ci, y = -hw - ci, radius = cr, name = "bottomRight" },
		{ id = 5, x = 0, y = -hw - si, radius = sr, name = "bottomSide" },
		{ id = 6, x = -hl - ci, y = -hw - ci, radius = cr, name = "bottomLeft" },
	}
end

function TableGeometry.build(options: BuildOptions?): Geometry
	local T = Config.Table
	local pocketsOpen = if options and options.pocketsOpen ~= nil then options.pocketsOpen else true
	local geometry: Geometry = {
		halfLength = T.LengthInches / 2,
		halfWidth = T.WidthInches / 2,
		pocketsOpen = pocketsOpen,
		segments = {},
		points = {},
		pockets = {},
	}
	if pocketsOpen then
		buildOpen(geometry)
	else
		buildClosed(geometry)
	end
	return geometry
end

--- True if a ball centre is inside the cushion lines (pocket mouths count as inside).
function TableGeometry.containsCenter(
	geometry: Geometry,
	x: number,
	y: number,
	slop: number?
): boolean
	local s = slop or 0
	return math.abs(x) <= geometry.halfLength + s and math.abs(y) <= geometry.halfWidth + s
end

--- The pocket that captures a ball centred at (x, y), or nil.
function TableGeometry.pocketAt(geometry: Geometry, x: number, y: number): Pocket?
	if not geometry.pocketsOpen then
		return nil
	end
	local nearest: Pocket? = nil
	local nearestDist = math.huge
	for _, p in geometry.pockets do
		local dx, dy = x - p.x, y - p.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= p.radius then
			return p
		end
		if dist < nearestDist then
			nearestDist = dist
			nearest = p
		end
	end
	-- Past the cushion line means it went through a mouth: give it to the nearest pocket.
	if not TableGeometry.containsCenter(geometry, x, y, 0) then
		return nearest
	end
	return nil
end

--- The head spot (cue ball start) and foot spot (rack apex), in inches.
function TableGeometry.headSpot(geometry: Geometry): (number, number)
	return -geometry.halfLength + Config.Table.HeadStringFraction * geometry.halfLength * 2, 0
end

function TableGeometry.footSpot(geometry: Geometry): (number, number)
	return geometry.halfLength - Config.Table.FootSpotFraction * geometry.halfLength * 2, 0
end

return TableGeometry
