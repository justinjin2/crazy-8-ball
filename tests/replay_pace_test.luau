--!strict
-- A late shot replay catches up gently instead of jumping ahead (ReplayPace; 2026-10-12, a
-- tester's "the balls teleport, you can't see the ball hit").
local H = require("./harness")
local ReplayPace = H.require("ReplayPace")
local O = H.require("Config").Multiplayer.ReplayCatchUp
local expect = H.expect
local tests = {}

function tests.a_small_lag_starts_at_the_strike_not_ahead_of_it()
	-- 0.15 s late used to start 0.15 s in: a full-power break's cue ball was drawn first
	-- some 66 in down the table, past the rack.
	local elapsed, lag = ReplayPace.start(0.15, O)
	expect(elapsed == 0, "starts at the strike")
	H.near(lag, 0.15, 1e-9, "owes the whole lag")
end

function tests.a_big_lag_skips_down_to_the_most_it_catches_up()
	local elapsed, lag = ReplayPace.start(3, O)
	H.near(lag, O.MaxLagSeconds, 1e-9, "keeps MaxLagSeconds to catch up")
	H.near(elapsed + lag, 3, 1e-9, "skips the rest")
	local e0, l0 = ReplayPace.start(-0.02, O)
	expect(e0 == 0 and l0 == 0, "a clock a hair ahead owes nothing")
end

function tests.it_runs_rate_fast_until_level_with_the_server_then_normal()
	local frame = 1 / 60
	local elapsed, lag = ReplayPace.start(0.2, O)
	local wall, maxFrame = 0, 0
	while lag > 0 and wall < 10 do
		local played
		played, lag = ReplayPace.advance(frame, lag, O)
		elapsed += played
		wall += frame
		maxFrame = math.max(maxFrame, played)
	end
	-- Level with the server: the shot time shown is the wall time since arrival + the lag.
	H.near(elapsed, wall + 0.2, 1e-9, "caught up exactly")
	H.near(wall, 0.2 / (O.Rate - 1), frame + 1e-9, "in lag / (Rate - 1) seconds")
	expect(maxFrame <= frame * O.Rate + 1e-12, "never more than Rate fast in a frame")
	local played, left = ReplayPace.advance(frame, 0, O)
	expect(played == frame and left == 0, "then normal speed")
end

function tests.a_slow_motion_moment_slows_the_catch_up_too()
	local played, left = ReplayPace.advance(0, 0.3, O)
	expect(played == 0 and left == 0.3, "a frozen moment owes it on")
	local slow = (1 / 60) * 0.2
	played, left = ReplayPace.advance(slow, 0.3, O)
	H.near(played, slow * O.Rate, 1e-12, "scaled with the moment")
	H.near(left, 0.3 - slow * (O.Rate - 1), 1e-12)
end

function tests.zero_max_lag_is_the_old_jump_ahead()
	local elapsed, lag = ReplayPace.start(0.25, { MaxLagSeconds = 0, Rate = O.Rate })
	expect(elapsed == 0.25 and lag == 0)
end

return tests
