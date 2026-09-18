--!strict
-- Table: the collision geometry of the playing surface, built from Config numbers.
--
-- Coordinates: origin at the table centre, x along the length (head rail at -x, foot rail
-- at +x), y across the width. All values in inches.
--
-- Rails are line segments with an inward-facing normal. Points are small fixed circles
-- (pocket jaws, or rail corners) that a ball can clip. Pockets are capture circles.
-- Milestone 1 builds a closed table (four full rails, no pockets). Milestone 2 opens the
-- pocket mouths.

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

export type Pocket = { id: number, x: number, y: number, radius: number }

export type Geometry = {
	halfLength: number,
	halfWidth: number,
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

function TableGeometry.build(options: BuildOptions?): Geometry
	local T = Config.Table
	local hl = T.LengthInches / 2
	local hw = T.WidthInches / 2
	local pocketsOpen = if options and options.pocketsOpen ~= nil
		then options.pocketsOpen
		else false

	local geometry: Geometry = {
		halfLength = hl,
		halfWidth = hw,
		segments = {},
		points = {},
		pockets = {},
	}

	if not pocketsOpen then
		-- Closed table: four rails meeting at sharp corners.
		geometry.segments = {
			segment(-hl, hw, hl, hw, 0, -1, "top"),
			segment(-hl, -hw, hl, -hw, 0, 1, "bottom"),
			segment(hl, -hw, hl, hw, -1, 0, "foot"),
			segment(-hl, -hw, -hl, hw, 1, 0, "head"),
		}
		-- Corners as zero-radius points so a ball aimed exactly into a corner still resolves.
		geometry.points = {
			{ x = -hl, y = -hw, radius = 0, name = "corner" },
			{ x = hl, y = -hw, radius = 0, name = "corner" },
			{ x = hl, y = hw, radius = 0, name = "corner" },
			{ x = -hl, y = hw, radius = 0, name = "corner" },
		}
		return geometry
	end

	error("open pockets are built in milestone 2")
end

--- True if a ball centre at (x, y) is on the cloth (rails not counted).
function TableGeometry.containsCenter(
	geometry: Geometry,
	x: number,
	y: number,
	radius: number,
	slop: number?
): boolean
	local s = slop or 0
	return x >= -geometry.halfLength + radius - s
		and x <= geometry.halfLength - radius + s
		and y >= -geometry.halfWidth + radius - s
		and y <= geometry.halfWidth - radius + s
end

return TableGeometry
