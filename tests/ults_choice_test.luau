--!strict
-- The global queue's Ults: On / Off (designer, 2026-09-28): the server's checks before it
-- takes the host's toggle (SetQueueUlts) or the No-ults fallback's Yes (SearchWithUlts),
-- on the pure engine table TableService drives (the host card uses the same checks on the
-- snapshot). TableService adds: the pad not starting a search, a search it owns still
-- waiting, and the save through PlayerData.setQueueUlts (a boolean only).
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local UltsChoice = H.require("Matchmaking.UltsChoice")
local Config = H.require("Config")
local G = Config.GlobalQueue
local expect = H.expect

local function pad(): any
	local m = E.new(1, 1)
	expect(E.join(m, 5, "a", "a", 0))
	expect(E.join(m, 6, "b", "b", 0.5))
	return m
end

local tests = {}

function tests.only_the_waiting_pads_host_sets_it_with_a_boolean()
	local m = pad()
	expect(m.hostId == 5)
	expect(UltsChoice.canSet(m, 5, false) and UltsChoice.canSet(m, 5, true), "the host")
	expect(not UltsChoice.canSet(m, 6, false), "not a guest on the pad")
	expect(not UltsChoice.canSet(m, 99, false), "not someone off the pad")
	for _, bad in { "false", 0, 1, {}, nil :: any } do
		expect(not UltsChoice.canSet(m, 5, bad), "not " .. tostring(bad))
	end
	expect(UltsChoice.canSet(E.snapshot(m), 5, false), "the snapshot answers the same")
	E.setSearch(m, 1)
	expect(not UltsChoice.canSet(m, 5, true), "not while the pad searches")
	E.clearSearch(m)
	expect(UltsChoice.canSet(m, 5, true))
	expect(E.action(m, 5, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 2, 1))
	expect(m.phase ~= "Waiting")
	expect(not UltsChoice.canSet(m, 5, true), "not once the game started")
	local arena = E.new(1, 1)
	arena.fixed = true
	E.join(arena, 5, "a", "a", 0, 1)
	expect(not UltsChoice.canSet(arena, arena.hostId, true), "an arena has no card")
	expect(not UltsChoice.canSet(nil, 5, true))
end

function tests.the_fallback_waits_for_a_no_ults_search_of_30_seconds()
	local m = E.new(1, 1)
	E.join(m, 5, "a", "a", 0)
	expect(not UltsChoice.canFallback(m, 5, false, 100), "no search")
	E.setSearch(m, 10)
	local at = 10 + G.NoUltsFallbackSeconds
	expect(not UltsChoice.canFallback(m, 5, false, at - 0.1), "not before 30 s")
	expect(UltsChoice.canFallback(m, 5, false, at), "at 30 s")
	expect(UltsChoice.canFallback(E.snapshot(m), 5, false, at), "the card shows it then")
	expect(
		UltsChoice.canFallback(m, 5, false, at - G.FallbackSlackSeconds, G.FallbackSlackSeconds),
		"the server takes it a little early"
	)
	expect(not UltsChoice.canFallback(m, 5, true, at + 60), "an ults-on search has none")
	expect(not UltsChoice.canFallback(m, 5, nil, at + 60), "a pool it doesn't know: none")
	expect(not UltsChoice.canFallback(m, 6, false, at), "the host's alone")
	E.searchFound(m, { 5 }, at)
	expect(not UltsChoice.canFallback(m, 5, false, at + 1), "not once matched")
	E.clearSearch(m)
	expect(not UltsChoice.canFallback(m, 5, false, at + 1), "not once it stopped")
end

function tests.the_arena_keeps_no_ults_through_the_rematch()
	-- ArenaService sets settings.abilities from the list; the rematch keeps it.
	local m = E.new(1, 1)
	m.fixed = true
	E.join(m, 1, "a", "a", 0, 1)
	E.join(m, 2, "b", "b", 0, 2)
	m.settings.abilities = false
	expect(E.startFixed(m, 1, 1))
	expect(E.snapshot(m).settings.abilities == false, "the snapshot carries it (NO ULTS pill)")
	E.advance(m, m.deadline) -- the coin
	expect(
		E.action(m, 2, { kind = "Surrender", epoch = m.epoch, turnId = m.turnId }, m.phaseStartedAt)
	)
	expect(m.phase == "Result" and m.rematch ~= nil)
	local epoch = m.epoch
	for _, id in { 1, 2 } do
		expect(
			E.action(
				m,
				id,
				{ kind = "Rematch", epoch = m.epoch, turnId = m.turnId },
				m.phaseStartedAt
			)
		)
	end
	E.advance(m, m.phaseStartedAt + 0.1)
	expect(m.epoch == epoch + 1 and m.phase ~= "Result", "the rematch began")
	expect(m.settings.abilities == false, "and it keeps No ults")
	expect(UltsChoice.pool(nil) and UltsChoice.pool(true) and not UltsChoice.pool(false))
end

return tests
