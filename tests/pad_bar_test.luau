--!strict
-- The matchmaking bar above the hotbar (designer, 2026-10-07): what it says, when Play Global
-- shows (at once on a step-on, friends here or not: 2026-10-09), team tables needing a whole
-- side, the search's time and X, when the server sends "<name> needs an opponent!" by itself,
-- and when the spawn pill offers Play Global (nobody else free).
local H = require("./harness")
local PadBar = H.require("Matchmaking.PadBar")
local Config = H.require("Config")
local expect = H.expect

local B = Config.UI.MatchBar
local NONE = { searchAt = -math.huge, cancelledAt = -math.huge }

local function pad(teamSize: number, users: { number }, hostId: number?): any
	local seats = {}
	for _, id in users do
		table.insert(seats, { userId = id, connected = true })
	end
	return { teamSize = teamSize, seats = seats, hostId = hostId or users[1], phase = "Waiting" }
end

local tests = {}

function tests.play_global_shows_the_moment_the_host_steps_on()
	expect(B.PromptAloneSeconds == nil and B.PromptFriendsSeconds == nil, "no wait left")
	expect(PadBar.view(pad(1, { 1 }), 1, 100, NONE).showGlobal, "at once")
end

function tests.the_waiting_line_and_count()
	local v = PadBar.view(pad(1, { 1 }), 1, 100, NONE)
	expect(v.line == "Waiting" and v.count == 1 and v.capacity == 2 and v.isHost)
	local team = PadBar.view(pad(2, { 1, 2 }), 1, 100, NONE)
	expect(team.line == "WaitingPlayers" and team.count == 2 and team.capacity == 4)
	local dropped = pad(2, { 1, 2 })
	dropped.seats[2].connected = false
	expect(PadBar.count(dropped) == 1, "a dropped seat is not counted")
end

function tests.only_the_host_gets_play_global()
	local s = pad(2, { 1, 2 })
	expect(PadBar.view(s, 1, 200, NONE).showGlobal, "the host")
	local guest = PadBar.view(s, 2, 200, NONE)
	expect(not guest.showGlobal and not guest.isHost and guest.line == "WaitingPlayers", "a guest")
end

function tests.a_team_table_needs_a_whole_side_first()
	local v = PadBar.view(pad(2, { 1 }), 1, 200, NONE)
	expect(v.needsSide and not v.showGlobal, "2v2 with one on")
	local three = PadBar.view(pad(3, { 1, 2 }), 1, 200, NONE)
	expect(three.needsSide and not three.showGlobal, "3v3 with two on")
	local side = PadBar.view(pad(3, { 1, 2, 3 }), 1, 200, NONE)
	expect(not side.needsSide and side.showGlobal, "3v3 with a whole side")
end

function tests.a_full_pad_counts_down()
	local s = pad(1, { 1, 2 })
	s.startsAt = 102.2
	local v = PadBar.view(s, 1, 100, NONE)
	expect(v.line == "Starting" and v.startsIn == 3 and not v.showGlobal)
	local guest = PadBar.view(s, 2, 102.1, NONE)
	expect(guest.startsIn == 1, "never below 1")
	local full = pad(1, { 1, 2 })
	expect(not PadBar.view(full, 1, 200, NONE).showGlobal, "no room, no search")
end

function tests.searching_shows_the_time_and_the_x()
	local s = pad(1, { 1 })
	s.search = { at = 100, users = { 1 } }
	local v = PadBar.view(s, 1, 107.6, NONE)
	expect(v.line == "Searching" and v.waited == 7 and v.showCancel and not v.showGlobal)
	expect(PadBar.clock(v.waited :: number) == "0:07")
	expect(PadBar.clock(75) == "1:15")
	s.search.found = true
	local found = PadBar.view(s, 1, 109, NONE)
	expect(found.line == "Found" and not found.showCancel, "found: no X")
end

function tests.a_press_shows_at_once_and_an_x_hides_it()
	local s = pad(1, { 1 })
	local pressed = { searchAt = 100, cancelledAt = -math.huge }
	expect(PadBar.view(s, 1, 100.5, pressed).line == "Searching", "before the server says")
	expect(PadBar.view(s, 1, 103, pressed).line == "Waiting", "a lost press lets go")
	s.search = { at = 100, users = { 1 } }
	local cancelled = { searchAt = 100, cancelledAt = 104 }
	expect(PadBar.view(s, 1, 104.5, cancelled).line == "Waiting", "an X on its way")
	s.search.found = true
	expect(PadBar.view(s, 1, 104.5, cancelled).line == "Found", "too late: found")
end

function tests.the_server_asks_for_an_opponent_not_too_often()
	local base = {
		isHost = true,
		count = 1,
		capacity = 2,
		searching = false,
		lastAt = nil,
		now = 100,
	}
	expect(PadBar.autoRequest(base), "a host alone")
	local function with(change: { [string]: any }): boolean
		local args = table.clone(base)
		for k, v in change do
			args[k] = v
		end
		return PadBar.autoRequest(args :: any)
	end
	expect(not with({ isHost = false }), "a guest never asks")
	expect(not with({ count = 2 }), "a full pad")
	expect(not with({ searching = true }), "a search runs")
	local cooldown = Config.Multiplayer.Queue.AutoRequestCooldownSeconds
	expect(not with({ lastAt = 100 - cooldown + 1 }), "stepped off and on again too soon")
	expect(with({ lastAt = 100 - cooldown }), "after the cooldown")
end

function tests.the_pads_x_hides_play_global_until_the_next_step_on()
	local s = pad(1, { 1 })
	expect(not PadBar.view(s, 1, 200, NONE, true).showGlobal, "dismissed")
	expect(PadBar.view(s, 1, 200, NONE, false).showGlobal, "a new step-on")
end

function tests.the_spawn_pill_shows_with_nobody_free_in_a_public_lobby_only()
	local base = {
		nobodyFree = true,
		publicLobby = true,
		tutorial = false,
		onPad = false,
		dismissed = false,
		since = nil,
		now = 100,
		searching = false,
	}
	local function with(change: { [string]: any }): boolean
		local args = table.clone(base)
		for k, v in change do
			args[k] = v
		end
		return PadBar.spawnPill(args :: any)
	end
	expect(with({}), "alone on spawn")
	expect(not with({ publicLobby = false }), "a private server: never")
	expect(not with({ tutorial = true }), "the tutorial first")
	expect(not with({ nobodyFree = false }), "someone is free")
	expect(not with({ onPad = true }), "on a pad the bar takes over")
	expect(not with({ dismissed = true }), "its X")
	local seconds = Config.UI.MatchBar.SpawnPillSeconds
	expect(seconds == 20, "the designer's 20 s")
	expect(with({ since = 100 - seconds + 0.5 }), "still up")
	expect(not with({ since = 100 - seconds }), "gone after 20 s")
	expect(
		with({ since = 0, nobodyFree = false, onPad = true, searching = true }),
		"a search it started keeps it up"
	)
	expect(with({ soft = true, nobodyFree = false, since = 0 }), "the soft part: up until pressed")
	expect(not with({ soft = true, dismissed = true }), "the soft part: its X still")
	expect(not with({ soft = true, onPad = true }), "the soft part: the pad's bar on a pad")
	expect(
		not with({ soft = true, publicLobby = false }),
		"the soft part: never in a private server"
	)
end

function tests.nobody_free_when_alone_or_everyone_else_is_busy()
	local inGame = pad(1, { 2, 3 })
	inGame.phase = "Aiming"
	local waiting = pad(1, { 4 })
	local full = pad(1, { 5, 6 })
	local snapshots = { [1] = inGame, [2] = waiting, [3] = full }
	expect(PadBar.nobodyFree({}, snapshots), "alone in the server")
	expect(PadBar.nobodyFree({ 2, 3 }, snapshots), "everyone else in a game")
	expect(PadBar.nobodyFree({ 2, 5, 6 }, snapshots), "or on a full pad")
	expect(not PadBar.nobodyFree({ 2, 4 }, snapshots), "one waits on a pad with room: free")
	expect(not PadBar.nobodyFree({ 2, 7 }, snapshots), "one walks the lobby: free")
	inGame.seats[1].connected = false
	expect(not PadBar.nobodyFree({ 2 }, snapshots), "a dropped seat is not busy")
	local result = pad(1, { 8, 9 })
	result.phase = "Result"
	expect(PadBar.nobodyFree({ 8 }, { result }), "on the result screen")
end

return tests
