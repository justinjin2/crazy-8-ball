--!strict
-- Catch-a-Ball (the abilities rework, 2026-10-08): the first ball the cue ball hits is caught
-- (counted as pocketed for its owner, an opponent's included); the 8 breaks free off the legal
-- 8 shot; the cue ball stops dead at the contact; the moment holds; the client's replay
-- matches the server's settle.

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

function tests.only_one_ball_is_caught_however_hard_the_hit()
	-- A rack's corner: the cue ball drives into a cluster; only the first is caught, the rest
	-- are left exactly where they were (nothing else was touched: the catch stops the cue).
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
	check(#ultEvents(outcome.events, "catch") == 1, "one catch")
	check(Simulation.findBall(sim, 1).pocketed, "the 1 caught")
	local two = Simulation.findBall(sim, 2)
	check(not two.pocketed and two.x == 2 * R + 0.01 and two.y == 0, "the 2 never moved")
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
