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
	local f = T.FacingLengthInches
	-- Corner mouths cut the rails back by c along each rail so the gap between the two
	-- cushion noses across the diagonal equals CornerMouthInches.
	local c = T.CornerMouthInches / math.sqrt(2)
	-- Side mouths: half the gap between the cushion noses.
	local sm = T.SideMouthInches / 2

	local cornerA = math.rad(T.CornerFacingDegrees)
	local sideA = math.rad(T.SideFacingDegrees)

	-- A rail piece plus its two angled facings. `sx, sy` mirror the geometry into each
	-- quadrant. Each facing runs from the cushion nose outward, away from the table, and
	-- its normal faces the pocket throat so a ball can hit it and rattle.
	local function addFacing(
		ax: number,
		ay: number,
		dx: number,
		dy: number,
		nx: number,
		ny: number,
		name: string
	)
		local bx, by = ax + dx * f, ay + dy * f
		table.insert(geometry.segments, segment(ax, ay, bx, by, nx, ny, name))
		table.insert(geometry.points, point(ax, ay, 0, name .. "Nose"))
		table.insert(geometry.points, point(bx, by, jr, name .. "Jaw"))
	end

	for _, sy in { 1, -1 } do
		-- Long rails (top for sy = 1, bottom for sy = -1), split at the side pocket.
		local rn = -sy -- inward normal y
		local yName = if sy > 0 then "top" else "bottom"
		table.insert(
			geometry.segments,
			segment(-hl + c, sy * hw, -sm, sy * hw, 0, rn, yName .. "Left")
		)
		table.insert(
			geometry.segments,
			segment(sm, sy * hw, hl - c, sy * hw, 0, rn, yName .. "Right")
		)
		-- Side pocket facings: nearly straight out, tilted away from the mouth centre.
		addFacing(
			-sm,
			sy * hw,
			-math.sin(sideA),
			sy * math.cos(sideA),
			math.cos(sideA),
			sy * math.sin(sideA),
			yName .. "SideL"
		)
		addFacing(
			sm,
			sy * hw,
			math.sin(sideA),
			sy * math.cos(sideA),
			-math.cos(sideA),
			sy * math.sin(sideA),
			yName .. "SideR"
		)
		for _, sx in { 1, -1 } do
			-- Corner facing off the long rail: goes outward (away from the table) and towards
			-- the corner at CornerFacingDegrees off the rail line.
			addFacing(
				sx * (hl - c),
				sy * hw,
				sx * math.cos(cornerA),
				sy * math.sin(cornerA),
				sx * math.sin(cornerA),
				-sy * math.cos(cornerA),
				yName .. "Corner" .. (if sx > 0 then "R" else "L")
			)
		end
	end
	for _, sx in { 1, -1 } do
		-- Short rails (foot for sx = 1, head for sx = -1).
		local rn = -sx
		local xName = if sx > 0 then "foot" else "head"
		table.insert(geometry.segments, segment(sx * hl, -hw + c, sx * hl, hw - c, rn, 0, xName))
		for _, sy in { 1, -1 } do
			addFacing(
				sx * hl,
				sy * (hw - c),
				sx * math.sin(cornerA),
				sy * math.cos(cornerA),
				-sx * math.cos(cornerA),
				sy * math.sin(cornerA),
				xName .. "Corner" .. (if sy > 0 then "T" else "B")
			)
		end
	end

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
	-- Well past the cushion line means it is over the shelf of a mouth: nearest pocket.
	local shelf = Config.Table.PocketShelfBallRadii * Config.Balls.RadiusInches
	if not TableGeometry.containsCenter(geometry, x, y, shelf) then
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
