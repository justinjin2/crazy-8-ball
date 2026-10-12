--!strict
-- PadMath: the pure helpers behind the controller's shot and the 8's pocket call
-- (src/client/Input.luau, src/client/MatchTargets.luau; designer, 2026-10-10). No Instances, no
-- clocks, no randomness; every list is walked in array order.
--
-- * The shot's power level: A held raises it and Y held lowers it, both at one steady rate (a
--   straight line, full in FillSeconds), clamped to 0..1. R2 shoots whatever it shows.
-- * Calling the 8: the D-pad walks the pockets on screen as rows (pocketRows, rowStep).

local PadMath = {}

-- A pocket on screen: its id and where it is drawn (pixels, y grows down).
export type Point = { id: number, x: number, y: number }

--- The power level after `dt` seconds with A (`up`) and Y (`down`) held: it moves dt /
--- fillSeconds each way; both held, or neither, leaves it. Always within 0..1.
function PadMath.stepPower(
	level: number,
	up: boolean,
	down: boolean,
	dt: number,
	fillSeconds: number
): number
	local direction = (if up then 1 else 0) - (if down then 1 else 0)
	if direction == 0 or dt <= 0 then
		return math.clamp(level, 0, 1)
	end
	return math.clamp(level + direction * dt / math.max(fillSeconds, 1e-3), 0, 1)
end

-- Before `b` in a row's order: smaller `axis` first, an exact tie by id.
local function before(a: Point, b: Point, axis: string): boolean
	local av, bv = (a :: any)[axis], (b :: any)[axis]
	if av ~= bv then
		return av < bv
	end
	return a.id < b.id
end

--- The pockets on screen as rows for the D-pad (designer, 2026-10-11: "going dpad right makes
--- it go right but at the end of the table it doesnt continue, go dpaddown to go to the second
--- row"): spread wider than tall (the top-down view always is), two rows of three; else three
--- rows of two. Rows run top to bottom, each left to right.
function PadMath.pocketRows(points: { Point }): { { Point } }
	local count = #points
	if count == 0 then
		return {}
	end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	for _, point in points do
		minX, maxX = math.min(minX, point.x), math.max(maxX, point.x)
		minY, maxY = math.min(minY, point.y), math.max(maxY, point.y)
	end
	local perRow = if maxX - minX >= maxY - minY then math.ceil(count / 2) else 2
	local sorted = table.clone(points)
	table.sort(sorted, function(a: Point, b: Point): boolean
		return before(a, b, "y")
	end)
	local rows: { { Point } } = {}
	for i, point in sorted do
		local r = (i - 1) // perRow + 1
		rows[r] = rows[r] or {}
		table.insert(rows[r], point)
	end
	for _, row in rows do
		table.sort(row, function(a: Point, b: Point): boolean
			return before(a, b, "x")
		end)
	end
	return rows
end

--- From pocket `fromId`, one D-pad step (dx, dy: -1, 0 or 1, y down) through `rows`: along the
--- row or to the row above or below in the same column, stopping at the edges (no wrap). An id
--- not in the rows starts at the top left; no rows leaves `fromId`.
function PadMath.rowStep(rows: { { Point } }, fromId: number, dx: number, dy: number): number
	if #rows == 0 then
		return fromId
	end
	for r, row in rows do
		for c, point in row do
			if point.id == fromId then
				local toRow = math.clamp(r + dy, 1, #rows)
				local to = rows[toRow]
				return to[math.clamp(c + (if toRow == r then dx else 0), 1, #to)].id
			end
		end
	end
	return rows[1][1].id
end

return PadMath
