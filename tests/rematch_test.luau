--!strict
-- Rematch and the series (designer, 2026-09-28), an arena's fixed teams, and the pad's
-- global search, on the pure engine TableService drives.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local M = H.require("Config").Multiplayer
local expect = H.expect

-- A pad of `size` a side: user team * 10 + slot steps on, alternating teams, so 11 hosts.
local function queue(size: number): any
	local m = E.new(1, size)
	for slot = 1, size do
		for team = 1, 2 do
			local user = team * 10 + slot
			expect(E.join(m, user, tostring(user), tostring(user), slot - 1))
		end
	end
	return m
end
local function expire(m: any)
	expect(m.deadline ~= nil, "a deadline in " .. m.phase)
	E.advance(m, m.deadline)
end
local function act(m: any, user: number, kind: string, extra: any?, at: number?): boolean
	local request = extra or {}
	request.kind, request.tableId, request.epoch, request.turnId = kind, m.id, m.epoch, m.turnId
	return E.action(m, user, request, at or m.phaseStartedAt)
end
-- Started and through the coin (the coin's team `coin` breaks), at the break's introduction.
local function started(size: number, coin: number?): any
	local m = queue(size)
	expect(
		E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, coin or 1)
	)
	expire(m) -- the coin flip
	expect(m.phase == "Intro")
	return m
end
-- Team `team` gives up (1v1 at once; teams by a unanimous vote).
local function concede(m: any, team: number)
	local first = team * 10 + 1
	expect(act(m, first, "Surrender"))
	if m.teamSize > 1 then
		for slot = 2, m.teamSize do
			expect(act(m, team * 10 + slot, "Vote", { yes = true }))
		end
	end
	expect(m.phase == "Result", "the game ended")
end

local tests = {}

function tests.a_two_sided_game_offers_a_rematch_and_counts_in_the_series()
	local m = started(1)
	concede(m, 2)
	expect(m.rematch ~= nil, "a rematch is on offer")
	expect(m.deadline - m.phaseStartedAt == M.RematchSeconds, "for the rematch window")
	expect(m.series.games == 1 and m.series.wins[1] == 1 and m.series.wins[2] == 0)
	local snap = E.snapshot(m)
	expect(snap.series.wins[1] == 1 and #snap.rematch.yes == 0)
end

function tests.everyone_saying_yes_plays_again_the_other_side_breaking()
	local m = started(1, 1)
	expect(m.series.breaker == 1 and m.activeTeam == 1)
	local epoch, seats = m.epoch, #m.seats
	concede(m, 1)
	expect(act(m, 11, "Rematch"))
	expect(not act(m, 11, "Rematch"), "one vote each")
	E.advance(m, m.phaseStartedAt + 1)
	expect(m.phase == "Result", "waits for the other")
	expect(#E.snapshot(m).rematch.yes == 1)
	expect(act(m, 21, "Rematch"))
	E.advance(m, m.phaseStartedAt + 2, 777)
	expect(m.phase == "Intro", "straight to the break, no coin")
	expect(m.epoch == epoch + 1 and #m.seats == seats, "a new game, the same players")
	expect(m.coin == nil and m.result == nil and m.brokeAt == nil and m.rematch == nil)
	expect(
		m.activeTeam == 2 and m.breakShot and m.ballInHand,
		"the other side breaks with ball in hand"
	)
	expect(m.rackSeed ~= nil and m.series.games == 1 and m.series.wins[2] == 1)
	for _, s in m.seats do
		expect(s.team == (if s.userId == 11 then 1 else 2), "teams kept")
	end
	-- Game two: team 1 wins; the series is 1-1 and team 1 breaks game three.
	concede(m, 2)
	expect(m.series.games == 2 and m.series.wins[1] == 1 and m.series.wins[2] == 1)
	act(m, 11, "Rematch")
	act(m, 21, "Rematch")
	E.advance(m, m.phaseStartedAt + 1)
	expect(m.activeTeam == 1, "breaks alternate")
end

function tests.one_no_frees_the_table_at_once()
	local m = started(1)
	concede(m, 2)
	expect(act(m, 11, "Rematch"))
	expect(act(m, 21, "Decline"))
	expect(not act(m, 21, "Rematch"), "no after no")
	E.advance(m, m.phaseStartedAt + 0.1)
	expect(m.phase == "Waiting" and #m.seats == 0 and m.series == nil, "freed, the series over")
end

function tests.the_window_running_out_frees_the_table()
	local m = started(1)
	concede(m, 2)
	act(m, 11, "Rematch")
	expire(m)
	expect(m.phase == "Waiting" and #m.seats == 0)
end

function tests.a_leaver_after_the_game_ends_the_rematch()
	local m = started(1)
	concede(m, 2)
	act(m, 11, "Rematch")
	E.remove(m, 21, m.phaseStartedAt + 1)
	expect(m.rematch.declined == 21 and m.deadline == m.phaseStartedAt + 1)
	E.advance(m, m.deadline)
	expect(m.phase == "Waiting")
end

function tests.a_team_rematch_needs_all_four()
	local m = started(2)
	concede(m, 1)
	for _, u in { 11, 12, 21 } do
		expect(act(m, u, "Rematch"))
	end
	E.advance(m, m.phaseStartedAt + 1)
	expect(m.phase == "Result")
	expect(act(m, 22, "Rematch"))
	E.advance(m, m.phaseStartedAt + 1)
	expect(m.phase == "Intro" and #m.seats == 4)
end

function tests.votes_only_from_players_in_a_finished_game()
	local m = started(1)
	expect(not act(m, 11, "Rematch"), "not during a game")
	concede(m, 2)
	expect(not act(m, 99, "Rematch"), "not a player")
end

function tests.solo_has_no_rematch()
	local m = E.new(1, 1)
	E.join(m, 5, "a", "a", 0)
	expect(act(m, 5, "StartSolo"))
	expect(act(m, 5, "Surrender"))
	expect(m.phase == "Result" and m.rematch == nil and m.series == nil)
	expect(m.deadline - m.phaseStartedAt == M.ResultSeconds)
end

function tests.an_arena_table_keeps_the_queues_teams()
	local m = E.new(1, 2)
	m.fixed = true
	expect(not E.join(m, 1, "a", "a", 0), "an arena seat needs its team")
	expect(E.join(m, 1, "a", "a", 0, 1))
	expect(E.join(m, 2, "b", "b", 0, 1), "teammates arrive together")
	expect(not E.join(m, 3, "c", "c", 0, 1), "a side holds teamSize")
	expect(not E.startFixed(m, 1, 1), "not until both sides have someone")
	expect(E.join(m, 3, "c", "c", 1, 2))
	expect(E.startsAt(m) == nil, "no pad countdown in an arena")
	expect(not act(m, 1, "RequestOpponent"), "no queue menu either")
	expect(E.startFixed(m, 2, 2))
	expect(m.phase == "CoinFlip" and m.coin.winnerTeam == 2)
	local teams = {}
	for _, s in m.seats do
		teams[s.userId] = s.team
	end
	expect(teams[1] == 1 and teams[2] == 1 and teams[3] == 2, "not by arrival order")
	expire(m)
	expect(act(m, 3, "Surrender"))
	E.advance(m, m.phaseStartedAt + 0.1) -- a one-player side's vote is unanimous at once
	expect(m.phase == "Result" and m.rematch ~= nil, "short-handed sides may still rematch")
	expire(m)
	expect(m.phase == "Waiting" and m.fixed, "still an arena table after it frees")
end

function tests.a_global_search_takes_a_whole_side_from_the_pad()
	local one = E.new(1, 1)
	E.join(one, 5, "a", "a", 0)
	expect(E.canSearch(one, 5), "1v1 alone")
	local two = E.new(2, 2)
	E.join(two, 5, "a", "a", 0)
	expect(not E.canSearch(two, 5), "2v2 needs two")
	E.join(two, 6, "b", "b", 1)
	expect(not E.canSearch(two, 6), "the host only")
	expect(E.canSearch(two, 5))
	E.join(two, 7, "c", "c", 2)
	expect(E.canSearch(two, 5), "three on a 2v2 pad")
	local users = E.setSearch(two, 3)
	expect(#users == 2 and users[1] == 5 and users[2] == 6, "the first two by arrival")
	expect(not E.canSearch(two, 5), "one search at a time")
	expect(E.snapshot(two).search.at == 3)
	E.remove(two, 7, 4)
	expect(two.search ~= nil, "the one left over may go")
	E.remove(two, 6, 5)
	expect(two.search == nil, "a party member off the pad ends it")
end

function tests.a_searching_pad_neither_plays_solo_nor_requests()
	local m = E.new(1, 1)
	E.join(m, 5, "a", "a", 0)
	E.setSearch(m, 1)
	expect(not act(m, 5, "StartSolo"), "no solo while searching")
	expect(not act(m, 5, "RequestOpponent"), "no request while searching")
	E.clearSearch(m)
	expect(act(m, 5, "RequestOpponent"), "both again once it stops")
end

function tests.a_found_search_holds_the_pad_and_a_start_clears_one()
	local m = E.new(1, 1)
	E.join(m, 5, "a", "a", 0)
	E.setSearch(m, 1)
	E.join(m, 6, "b", "b", 2)
	expect(E.startsAt(m) ~= nil, "a full pad still plays locally while searching")
	E.searchFound(m, { 5 }, 2.5)
	expect(E.startsAt(m) == nil, "but not once the search found a match")
	E.clearSearch(m)
	E.advance(m, 2 + M.Queue.ReadyGraceSeconds)
	expect(m.phase == "CoinFlip" and m.search == nil, "the local game, the search gone")
end

return tests
