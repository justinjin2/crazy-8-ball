--!strict
-- PadMath (src/shared/PadMath.luau): the controller's power level (A up, Y down, a straight
-- line at one rate), the stick picking the 8's pocket from the table's middle, and the D-pad's
-- step to the pocket that way.

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

function tests.stickPicksThePocketThatWay()
	local function pick(sx: number, sy: number): number?
		return PadMath.pocketToward(POCKETS, 500, 300, sx, sy, 0.3)
	end
	check(pick(0, 1) == 2, "up is the top middle")
	check(pick(0, -1) == 5, "down is the bottom middle")
	check(pick(1, 1) == 3, "up and right is the top right corner")
	check(pick(-1, -1) == 6, "down and left is the bottom left corner")
	check(pick(-1, 0.4) == 1, "mostly left, a little up: top left")
	check(pick(1, -0.4) == 4, "mostly right, a little down: bottom right")
end

function tests.stickInsideTheDeadZonePicksNothing()
	check(PadMath.pocketToward(POCKETS, 500, 300, 0.1, 0.2, 0.3) == nil, "a resting stick")
	check(PadMath.pocketToward({}, 500, 300, 1, 0, 0.3) == nil, "no pockets on screen")
end

function tests.dpadStepsToTheNearestPocketThatWay()
	check(PadMath.stepToward(POCKETS, 1, 1, 0, 0.5) == 2, "right from top left: top middle")
	check(PadMath.stepToward(POCKETS, 2, 1, 0, 0.5) == 3, "right again: top right")
	check(PadMath.stepToward(POCKETS, 3, 0, 1, 0.5) == 4, "down from top right: bottom right")
	check(PadMath.stepToward(POCKETS, 4, -1, 0, 0.5) == 5, "left from bottom right: bottom middle")
	check(PadMath.stepToward(POCKETS, 3, 1, 0, 0.5) == 3, "nothing further right: it stays")
	check(PadMath.stepToward(POCKETS, 9, 1, 0, 0.5) == 9, "an unknown pocket stays put")
end

return tests
