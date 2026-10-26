--!strict
-- The TeamPad analytics event's bookkeeping (PadExits, designer 2026-10-26): when each real
-- player's wait on a 2v2 or 3v3 pad ends, after how long, and how.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local PadExits = H.require("Matchmaking.PadExits")
local expect = H.expect

local tests = {}

local function only(exits: { any }, userId: number): any
	for _, x in exits do
		if x.userId == userId then
			return x
		end
	end
	return nil
end

function tests.a_wait_ends_by_stepping_off_or_by_the_game_starting()
	local m = E.new(1, 2)
	local since = {}
	E.join(m, 5, "5", "5", 10, nil, 1)
	expect(#PadExits.step(since, m, 10) == 0 and since[5] == 10, "waiting from the step-on")
	E.join(m, 6, "6", "6", 12, nil, 2)
	PadExits.step(since, m, 12)
	E.remove(m, 6, 20)
	local left = PadExits.step(since, m, 20)
	expect(#left == 1 and left[1].userId == 6 and left[1].outcome == "Left")
	expect(left[1].seconds == 8 and since[6] == nil)
	E.join(m, 6, "6", "6", 21, nil, 2)
	E.join(m, 7, "7", "7", 22, nil, 1)
	E.join(m, 8, "8", "8", 23, nil, 2)
	PadExits.step(since, m, 23)
	expect(E.action(m, 5, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 24, 1))
	local started = PadExits.step(since, m, 24)
	expect(
		#started == 4 and only(started, 5).outcome == "Started" and only(started, 5).seconds == 14
	)
	expect(next(since) == nil and #PadExits.step(since, m, 30) == 0, "logged once")
end

function tests.a_found_global_search_is_global_and_never_counted_again()
	local m = E.new(1, 2)
	local since = {}
	E.join(m, 5, "5", "5", 0, nil, 1)
	E.join(m, 6, "6", "6", 1, nil, 1)
	PadExits.step(since, m, 1)
	E.setSearch(m, 2)
	E.searchFound(m, { 5, 6 }, 4)
	local gone = PadExits.step(since, m, 4)
	expect(#gone == 2 and gone[1].outcome == "Global" and gone[2].outcome == "Global")
	expect(#PadExits.step(since, m, 5) == 0 and next(since) == nil, "still seated, not again")
	E.remove(m, 5, 6)
	expect(#PadExits.step(since, m, 6) == 0, "the teleport is not a step-off")
end

function tests.a_pc_fill_one_v_ones_arenas_and_bots_are_marked_or_left_out()
	local m = E.new(1, 2)
	local since = {}
	E.join(m, 5, "5", "5", 0, nil, 1)
	E.join(m, -1, "bot", "bot", 0, nil, 2)
	PadExits.step(since, m, 0)
	expect(since[5] == 0 and since[-1] == nil, "bots never count")
	E.join(m, 6, "6", "6", 1, nil, 1)
	E.join(m, -2, "bot", "bot", 1, nil, 2)
	PadExits.step(since, m, 1)
	m.pcFill = true
	expect(E.action(m, 5, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 2, 1))
	local x = PadExits.step(since, m, 2)
	expect(#x == 2 and x[1].outcome == "PcFill")
	local duel = E.new(2, 1)
	local s2 = {}
	E.join(duel, 5, "5", "5", 0)
	PadExits.step(s2, duel, 0)
	expect(next(s2) == nil, "1v1 pads are not measured here")
	local arena = E.new(3, 2)
	arena.fixed = true
	E.join(arena, 5, "5", "5", 0, 1)
	PadExits.step(s2, arena, 0)
	expect(next(s2) == nil, "nor an arena's table")
end

return tests
