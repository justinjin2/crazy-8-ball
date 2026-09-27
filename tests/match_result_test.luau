--!strict
-- The match result carries what the rank and money rules need (Ranking): the team that
-- forfeited, and the server-tracked match time from the break for the one-minute mark.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local CoinSeconds = H.require("Config").Multiplayer.CoinSeconds

-- A started 1v1: A (11) against B (21), the introduction opening at 7.6.
local function started()
	local t = E.new(1, 1)
	H.expect(E.join(t, 11, "A", "A", 0))
	H.expect(E.join(t, 21, "B", "B", 0))
	H.expect(
		E.action(
			t,
			11,
			{ kind = "Start", epoch = t.epoch, turnId = t.turnId },
			7.6 - CoinSeconds,
			1
		)
	)
	E.advance(t, 7.6)
	return t
end

local function surrender(t: any, userId: number, now: number)
	H.expect(E.action(t, userId, { kind = "Surrender", epoch = t.epoch, turnId = t.turnId }, now))
end

return {
	["a surrender names the team that gave up"] = function()
		local t = started()
		surrender(t, 11, 9)
		H.expect(t.phase == "Result" and t.result.winner == 2 and t.result.forfeit == 1)
	end,
	["no break taken: the match time is zero"] = function()
		local t = started()
		surrender(t, 21, 30)
		H.expect(t.result.seconds == 0 and t.result.forfeit == 2)
	end,
	["the match time runs from the break"] = function()
		local t = started()
		t.brokeAt = 10 -- the first accepted shot
		surrender(t, 11, 85)
		H.expect(t.result.seconds == 75, "75 s from the break")
	end,
	["a finished game clears the break time"] = function()
		local t = started()
		t.brokeAt = 10
		surrender(t, 11, 20)
		E.advance(t, t.deadline, 5)
		H.expect(t.phase == "Waiting" and t.brokeAt == nil)
	end,
	["a left team is not a forfeit team (the leaver was charged on leaving)"] = function()
		local t = started()
		H.expect(E.remove(t, 21, 12))
		H.expect(t.result.reason == "EmptyTeam" and t.result.winner == 1)
		H.expect(t.result.forfeit == nil)
	end,
}
