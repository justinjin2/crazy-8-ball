--!strict
-- AuraQuiet: which cues run a quieter aura in a match (the shooter's; on your turn, every cue
-- at your table; never while the table waits or shows its result).

local H = require("./harness")

local ME, THEM, OTHER_A, OTHER_B = 1, 2, 3, 4

local function tables(phase: string, shooter: number): { [number]: any }
	return {
		[1] = { phase = phase, shooter = shooter, seats = { { userId = ME }, { userId = THEM } } },
		[2] = {
			phase = "Aiming",
			shooter = OTHER_A,
			seats = { { userId = OTHER_A }, { userId = OTHER_B } },
		},
	}
end

return {
	["on my turn my cue and my opponent's are quiet"] = function()
		local Q = H.require("AuraQuiet")
		local s = tables("Aiming", ME)
		H.expect(Q.quiet(ME, ME, s) == true, "me shooting")
		H.expect(Q.quiet(THEM, ME, s) == true, "opponent on my turn")
	end,
	["on their turn the shooter is quiet and my waiting cue is full"] = function()
		local Q = H.require("AuraQuiet")
		local s = tables("Resolving", THEM)
		H.expect(Q.quiet(THEM, ME, s) == true, "opponent shooting")
		H.expect(Q.quiet(ME, ME, s) == false, "me waiting")
	end,
	["another table: its shooter is quiet, its waiting player full"] = function()
		local Q = H.require("AuraQuiet")
		local s = tables("Aiming", ME)
		H.expect(Q.quiet(OTHER_A, ME, s) == true, "other table's shooter")
		H.expect(Q.quiet(OTHER_B, ME, s) == false, "other table's waiting player")
	end,
	["the engulfing aura goes while a shot is in flight at my table, whoever shot"] = function()
		local Q = H.require("AuraQuiet")
		H.expect(Q.carrierQuiet(ME, tables("Resolving", THEM)) == true, "watching their shot")
		H.expect(Q.carrierQuiet(THEM, tables("Resolving", THEM)) == true, "the shooter's own")
		H.expect(Q.carrierQuiet(ME, tables("Resolving", ME)) == true, "my own shot rolling")
		H.expect(Q.carrierQuiet(ME, tables("Frozen", THEM)) == true, "Time Stop")
		H.expect(Q.carrierQuiet(ME, tables("Rewinding", THEM)) == true, "a rewind")
	end,
	["the engulfing aura is back between shots and off the table"] = function()
		local Q = H.require("AuraQuiet")
		H.expect(Q.carrierQuiet(ME, tables("Aiming", THEM)) == false, "they line up")
		H.expect(Q.carrierQuiet(ME, tables("Placement", THEM)) == false, "ball in hand")
		H.expect(Q.carrierQuiet(ME, tables("Foul", THEM)) == false, "the foul card")
		H.expect(Q.carrierQuiet(ME, tables("Waiting", ME)) == false, "no match")
		H.expect(Q.carrierQuiet(ME, tables("Result", ME)) == false, "the result")
		H.expect(Q.carrierQuiet(OTHER_A, tables("Resolving", THEM)) == false, "another table")
		H.expect(Q.carrierQuiet(99, tables("Resolving", THEM)) == false, "not seated")
	end,
	["no match in play: full"] = function()
		local Q = H.require("AuraQuiet")
		H.expect(Q.quiet(ME, ME, tables("Waiting", ME)) == false, "waiting for players")
		H.expect(Q.quiet(THEM, ME, tables("Result", ME)) == false, "result screen")
		H.expect(Q.quiet(99, ME, tables("Aiming", ME)) == false, "not seated anywhere")
	end,
}
