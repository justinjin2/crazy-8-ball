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
	["no match in play: full"] = function()
		local Q = H.require("AuraQuiet")
		H.expect(Q.quiet(ME, ME, tables("Waiting", ME)) == false, "waiting for players")
		H.expect(Q.quiet(THEM, ME, tables("Result", ME)) == false, "result screen")
		H.expect(Q.quiet(99, ME, tables("Aiming", ME)) == false, "not seated anywhere")
	end,
}
