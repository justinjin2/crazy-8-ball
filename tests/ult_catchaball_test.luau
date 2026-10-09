--!strict
-- Catch-a-Ball (the abilities rework, 2026-10-08): the first ball the cue ball hits is caught
-- (counted as pocketed for its owner, an opponent's included); the 8 breaks free off the legal
-- 8 shot; the cue ball stops dead at the contact; the moment holds; then (Epic, the designer's
-- second round) it hops to your nearest ball in reach and catches that too; the client's
-- replay matches the server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Judge = H.require("Rules.ShotJudge")

local geometry = V.geometry
local C = Config.Ults.CatchABall
local R = Config.Balls.RadiusInches

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function table_(spots: { { number } }): { any }
	local balls = {}
	for _, s in spots do
		table.insert(balls, Ball.new(s[1], s[2], s[3]))
	end
	return balls
end

local function armed(
	balls: { any },
	targets: { number },
	opp: { number },
	eightPocket: number?
): any
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.armEffect(sim, "CatchABall", targets, eightPocket, { OppTargets = opp })
	return sim
end

local function roll(sim: any, id: number, vx: number, vy: number)
	local b = assert(Simulation.findBall(sim, id), "ball " .. id)
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
end

local function judged(sim: any, before: { any }, groups: { any }, called: number?): (any, any)
	local outcome = Simulation.settle(sim, {})
	return Judge.resolve(before, outcome, groups, 1, false, called, true), outcome
end

local function ultEvents(events: { any }, kind: string): { any }
	local out = {}
	for _, ev in events do
		if ev.type == "ult" and ev.kind == kind then
			table.insert(out, ev)
		end
	end
	return out
end

local SOLIDS = { "solids", "stripes" }

local tests = {}

function tests.your_first_ball_is_caught_and_counted_and_the_cue_ball_stops_there()
	local balls = table_({ { 0, -20, 0 }, { 1, -10, 0 }, { 2, 30, 10 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1, 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local catch = ultEvents(outcome.events, "catch")
	check(#catch == 1 and catch[1].ball == 1 and catch[1].value == 1, "the 1 caught")
	check(Simulation.findBall(sim, 1).pocketed, "off the table")
	check(table.find(verdict.pockets, 1) ~= nil, "counted as pocketed")
	check(verdict.foul == nil and verdict.keep, "legal, the turn kept: " .. tostring(verdict.foul))
	local cue = Simulation.findBall(sim, 0)
	check(not cue.pocketed, "the cue ball stays")
	check(
		math.abs(cue.x - (-10 - 2 * R)) < 0.2 and math.abs(cue.y) < 1e-6,
		"stopped at the contact"
	)
	check(not Simulation.findBall(sim, 2).pocketed, "the 2 untouched")
end

function tests.an_opponents_ball_first_is_caught_for_them_and_is_a_foul()
	local balls = table_({ { 0, -20, 0 }, { 9, -10, 0 }, { 2, 30, 10 }, { 8, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local catch = ultEvents(outcome.events, "catch")
	check(#catch == 1 and catch[1].ball == 9 and catch[1].value == 0, "the 9 caught")
	check(Simulation.findBall(sim, 9).pocketed, "gone")
	check(verdict.foul == "WrongContact", "a foul: " .. tostring(verdict.foul))
end

function tests.an_early_8_breaks_free()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 2, 30, 10 }, { 9, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local _, outcome = judged(sim, balls, SOLIDS)
	check(#ultEvents(outcome.events, "catch") == 0, "nothing caught")
	check(#ultEvents(outcome.events, "breakfree") == 1, "it breaks free")
	check(#ultEvents(outcome.events, "slow") == 0, "no hold")
	local eight = Simulation.findBall(sim, 8)
	check(eight.x > -10 + 1, "the 8 was struck as normal")
end

function tests.the_legal_8_is_caught_and_wins()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS, 3)
	check(
		verdict.winner == 1 and verdict.reason == "LegalEight",
		"a win: " .. tostring(verdict.reason)
	)
end

function tests.the_moment_holds_at_the_catch()
	local balls = table_({ { 0, -20, 0 }, { 1, -10, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	local catch = ultEvents(outcome.events, "catch")[1]
	local slow = ultEvents(outcome.events, "slow")[1]
	check(catch and slow and slow.t == catch.t and slow.x == C.HoldShotSeconds, "the hold")
	check(math.abs((outcome.extraSeconds or 0) - C.HoldSeconds) < 1e-9, "the wall time added")
end

function tests.the_hit_never_shoves_the_cluster_and_the_hop_takes_the_nearest()
	-- A rack's corner: the cue ball drives into a cluster; the first is caught and the rest are
	-- left exactly where they were (the catch stops the cue); then the hop takes the nearest of
	-- yours, the 2, and the 3 never moves.
	local balls = table_({
		{ 0, -30, 0 },
		{ 1, 0, 0 },
		{ 2, 2 * R + 0.01, 0 },
		{ 3, 2 * R + 0.01, 2 * R + 0.01 },
		{ 9, 40, -20 },
	})
	local sim = armed(balls, { 1, 2, 3 }, { 9 })
	roll(sim, 0, 300, 0)
	local outcome = Simulation.settle(sim, {})
	local catches = ultEvents(outcome.events, "catch")
	check(#catches == 2 and catches[1].ball == 1 and catches[2].ball == 2, "the 1, then the 2")
	check(Simulation.findBall(sim, 1).pocketed and Simulation.findBall(sim, 2).pocketed, "both off")
	local three = Simulation.findBall(sim, 3)
	check(
		not three.pocketed and three.x == 2 * R + 0.01 and three.y == 2 * R + 0.01,
		"the 3 never moved"
	)
end

function tests.after_the_first_catch_it_hops_to_your_nearest_ball_and_catches_it_too()
	-- The 9 (theirs) is nearer, the 3 (yours) out of reach: the 2 is the one.
	local balls = table_({
		{ 0, -20, 0 },
		{ 1, -10, 0 },
		{ 2, -6, 5 },
		{ 3, 5, -15 },
		{ 9, -12, 5 },
	})
	local sim = armed(balls, { 1, 2, 3 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local catches = ultEvents(outcome.events, "catch")
	local hop = ultEvents(outcome.events, "hop")
	check(
		#hop == 1 and hop[1].ball == 2 and hop[1].t == catches[1].t,
		"the hop to the 2, told at once"
	)
	check(#catches == 2 and catches[2].ball == 2 and catches[2].other == 2, "the 2 caught second")
	check(catches[1].other == 1 and catches[2].value == 1, "first and second, yours")
	-- After the first hold, then the slide (about 8 in at HopSpeed).
	local slide = math.sqrt((-6 - (-10 - 2 * R)) ^ 2 + 5 ^ 2) / C.HopSpeed
	check(
		catches[2].t >= catches[1].t + C.HoldShotSeconds + slide - 0.02,
		"after the hold and the slide"
	)
	check(table.find(verdict.pockets, 1) and table.find(verdict.pockets, 2), "both count")
	check(verdict.foul == nil and verdict.keep, "legal, the turn kept: " .. tostring(verdict.foul))
	local cue = Simulation.findBall(sim, 0)
	check(cue.x == -6 and cue.y == 5 and not cue.pocketed, "the catch ball sits on the 2's spot")
	check(not Simulation.findBall(sim, 9).pocketed, "it passed the 9 by")
	check(not Simulation.findBall(sim, 3).pocketed, "the 3 stays")
	local slows = ultEvents(outcome.events, "slow")
	check(#slows == 2 and slows[2].t == catches[2].t, "a hold for each catch")
	local extra = C.HoldSeconds + C.SecondHoldSeconds
	check(math.abs((outcome.extraSeconds or 0) - extra) < 1e-9, "both holds' wall time added")
end

function tests.no_second_catch_without_one_of_yours_in_reach()
	local balls = table_({ { 0, -20, 0 }, { 1, -10, 0 }, { 2, 30, 10 }, { 9, -8, 6 } })
	local sim = armed(balls, { 1, 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	check(#ultEvents(outcome.events, "catch") == 1, "one catch")
	check(#ultEvents(outcome.events, "hop") == 0, "no hop")
	check(not Simulation.findBall(sim, 2).pocketed and not Simulation.findBall(sim, 9).pocketed)
end

function tests.the_hop_never_crosses_a_pocket()
	-- Along the top cushion: the 2 is nearer, but the way to it passes the side pocket's mouth;
	-- the 3, a little farther straight across the cloth, is taken instead.
	local y = geometry.halfWidth - 1.3
	local spot = -2.25 - 2 * R -- where the cue ball touches the 1
	local balls = table_({
		{ 0, -20, y },
		{ 1, -2.25, y },
		{ 2, 4, y },
		{ 3, spot, y - 8.8 },
		{ 9, 40, -20 },
	})
	check(4 - spot < 8.8 and 8.8 < C.HopReachInches, "both in reach, the 2 nearer")
	local sim = armed(balls, { 1, 2, 3 }, { 9 })
	roll(sim, 0, 40, 0)
	local outcome = Simulation.settle(sim, {})
	local catches = ultEvents(outcome.events, "catch")
	check(#catches == 2 and catches[2].ball == 3, "the 3, not the 2")
	check(not Simulation.findBall(sim, 0).pocketed, "the catch ball stays up")
end

function tests.no_hop_after_the_legal_8()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 9, -5, 6 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	check(#ultEvents(outcome.events, "catch") == 1, "the 8 caught")
	check(#ultEvents(outcome.events, "hop") == 0, "no hop: the game is won")
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 53)
	local r = V.rng(11)
	local compared, caught = 0, 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local own = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "CatchABall", own, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		if #ultEvents(outcome.events, "catch") > 0 then
			caught += 1
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "CatchABall", own, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "cue"))
		for _ = 1, 40000 do
			if Simulation.isAtRest(replay) then
				break
			end
			Simulation.step(replay, Config.Physics.FixedStep, {})
		end
		Simulation.finishShot(replay, {})
		for i, b in sim.balls do
			local c = replay.balls[i]
			check(
				b.x == c.x and b.y == c.y and b.pocketed == c.pocketed,
				"ball " .. b.id .. " matches"
			)
		end
		compared += 1
	end
	check(compared >= 10, "enough shots compared: " .. compared)
	check(caught >= 8, "most shots catch: " .. caught)
end

return tests
