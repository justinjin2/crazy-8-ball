--!strict
-- PadMath (src/shared/PadMath.luau): the controller's power level (A up, Y down, a straight
-- line at one rate) and the D-pad walking the 8's pockets as rows.

local H = require("./harness")

local PadMath = H.require("PadMath")

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

-- Six pockets as the top-down view draws them: corners and sides of a 400 x 200 table centred
-- on (500, 300) (screen pixels, y down).
local POCKETS: { PadMath.Point } = {
	{ id = 1, x = 300, y = 200 }, -- top left
	{ id = 2, x = 500, y = 190 }, -- top middle
	{ id = 3, x = 700, y = 200 }, -- top right
	{ id = 4, x = 700, y = 400 }, -- bottom right
	{ id = 5, x = 500, y = 410 }, -- bottom middle
	{ id = 6, x = 300, y = 400 }, -- bottom left
}

local tests = {}

function tests.powerRisesAndFallsInAStraightLine()
	local level = 0
	for _ = 1, 10 do
		level = PadMath.stepPower(level, true, false, 0.05, 1)
	end
	check(near(level, 0.5), "half a second of A is half the bar: " .. level)
	level = PadMath.stepPower(level, true, false, 0.25, 1)
	check(near(level, 0.75), "the same rate the whole way: " .. level)
	level = PadMath.stepPower(level, false, true, 0.5, 1)
	check(near(level, 0.25), "Y takes it back at the same rate: " .. level)
end

function tests.powerStaysInsideTheBar()
	check(PadMath.stepPower(0.9, true, false, 1, 1) == 1, "never past full")
	check(PadMath.stepPower(0.1, false, true, 1, 1) == 0, "never under empty")
	check(PadMath.stepPower(0.4, true, true, 1, 1) == 0.4, "both held: it stays")
	check(PadMath.stepPower(0.4, false, false, 1, 1) == 0.4, "neither: it stays")
	check(PadMath.stepPower(0.4, true, false, 0, 1) == 0.4, "no time, no change")
end

-- The rows as ids, for the checks below.
local function ids(rows: { { PadMath.Point } }): string
	local out = {}
	for _, row in rows do
		local line = {}
		for _, point in row do
			table.insert(line, tostring(point.id))
		end
		table.insert(out, table.concat(line, ","))
	end
	return table.concat(out, "/")
end

function tests.pocketsMakeTwoRowsOfThreeOnAWideTable()
	check(ids(PadMath.pocketRows(POCKETS)) == "1,2,3/6,5,4", ids(PadMath.pocketRows(POCKETS)))
	-- The table turned round on screen: the rows still read top to bottom, left to right.
	local flipped: { PadMath.Point } = {}
	for _, point in POCKETS do
		table.insert(flipped, { id = point.id, x = 1000 - point.x, y = 600 - point.y })
	end
	check(ids(PadMath.pocketRows(flipped)) == "4,5,6/3,2,1", ids(PadMath.pocketRows(flipped)))
	check(#PadMath.pocketRows({}) == 0, "no pockets on screen, no rows")
end

function tests.aTallTableMakesThreeRowsOfTwo()
	local tall: { PadMath.Point } = {}
	for _, point in POCKETS do
		table.insert(tall, { id = point.id, x = point.y, y = point.x })
	end
	check(ids(PadMath.pocketRows(tall)) == "1,6/2,5/3,4", ids(PadMath.pocketRows(tall)))
end

function tests.dpadWalksTheRowsAndStopsAtTheEnds()
	local rows = PadMath.pocketRows(POCKETS)
	check(PadMath.rowStep(rows, 1, 1, 0) == 2, "right from top left: top middle")
	check(PadMath.rowStep(rows, 2, 1, 0) == 3, "right again: top right")
	check(PadMath.rowStep(rows, 3, 1, 0) == 3, "the end of the row: it stays")
	check(PadMath.rowStep(rows, 1, -1, 0) == 1, "nothing left of top left: it stays")
	check(PadMath.rowStep(rows, 3, 0, 1) == 4, "down from top right: bottom right")
	check(PadMath.rowStep(rows, 2, 0, 1) == 5, "down from top middle: bottom middle")
	check(PadMath.rowStep(rows, 5, 0, 1) == 5, "nothing under the bottom row: it stays")
	check(PadMath.rowStep(rows, 6, 0, -1) == 1, "up from bottom left: top left")
	check(PadMath.rowStep(rows, 4, -1, 0) == 5, "left from bottom right: bottom middle")
	check(PadMath.rowStep(rows, 9, 1, 0) == 1, "an unknown pocket starts at the top left")
	check(PadMath.rowStep({}, 3, 1, 0) == 3, "no rows: it stays")
end

return tests
