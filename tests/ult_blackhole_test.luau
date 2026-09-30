--!strict
-- Black Hole (docs/prompts/ABILITIES_PROMPT.md 7.12): at the cue ball's first contact a hole
-- opens and drags in the shooter's balls within its reach and the opponent's within half of
-- it, at most 3 and 2, closest first, never the cue ball or an early 8; each is swallowed and
-- counted as pocketed for its owner; the cue ball is pushed away and never scratches for it;
-- the client's replay matches the server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Judge = H.require("Rules.ShotJudge")

local geometry = V.geometry
local C = Config.Ults.BlackHole
local S = Config.Ults.Shared
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
	Simulation.armEffect(sim, "BlackHole", targets, eightPocket, { OppTargets = opp })
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

local function ids(events: { any }): { [number]: boolean }
	local out = {}
	for _, ev in events do
		out[ev.ball] = true
	end
	return out
end

local SOLIDS = { "solids", "stripes" }

local tests = {}

function tests.the_reach_is_capped()
	check(C.RadiusInches <= S.MaxReachShare * 2 * geometry.halfLength + 1e-9, "reach capped")
end

function tests.yours_in_reach_and_theirs_in_half_are_swallowed()
	-- The cue ball hits the 1 at (-10, 0): the hole opens at (-10 - R, 0). The 2 sits 15 in
	-- from it (inside the reach), the 9 at 6 in (inside half), the 10 at 15 in (outside half),
	-- the 8 at 4 in (never), the 3 far away.
	local hx = -10 - R
	local balls = table_({
		{ 0, -20, 0 },
		{ 1, -10, 0 },
		{ 2, hx, 15 },
		{ 9, hx, -6 },
		{ 10, hx + 15, -1 },
		{ 8, hx - 1, 4 },
		{ 3, 40, 20 },
	})
	local sim = armed(balls, { 1, 2, 3 }, { 9, 10 })
	roll(sim, 0, 40, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local gone = ids(ultEvents(outcome.events, "swallow"))
	check(gone[1] and gone[2] and gone[9], "the 1, 2 and 9 swallowed")
	check(not gone[10] and not gone[8] and not gone[3] and not gone[0], "not the 10, 8, 3 or cue")
	for _, id in { 1, 2, 9 } do
		check(Simulation.findBall(sim, id).pocketed, id .. " off the table")
		check(table.find(verdict.pockets, id) ~= nil, id .. " counted as pocketed")
	end
	check(not Simulation.findBall(sim, 0).pocketed, "the cue ball stays")
	check(not Simulation.findBall(sim, 8).pocketed, "the 8 stays")
	check(verdict.foul == nil and verdict.winner == nil, "legal: " .. tostring(verdict.foul))
	check(#ultEvents(outcome.events, "open") == 1, "one hole")
end

function tests.a_wrong_first_ball_is_a_foul_and_the_hole_still_opens()
	local balls = table_({ { 0, -20, 0 }, { 9, -10, 0 }, { 2, -10, 10 }, { 8, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 40, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local gone = ids(ultEvents(outcome.events, "swallow"))
	check(gone[9] and gone[2], "both swallowed")
	check(verdict.foul == "WrongContact", "a foul: " .. tostring(verdict.foul))
end

function tests.an_early_8_hit_first_is_never_pulled()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 2, -10, 8 }, { 9, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 40, 0)
	local _, outcome = judged(sim, balls, SOLIDS)
	local gone = ids(ultEvents(outcome.events, "swallow"))
	check(not gone[8] and gone[2], "the 2, never the 8")
end

function tests.the_legal_8_is_swallowed_and_wins()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 40, 0)
	local verdict = judged(sim, balls, SOLIDS, 3)
	check(
		verdict.winner == 1 and verdict.reason == "LegalEight",
		"a win: " .. tostring(verdict.reason)
	)
end

function tests.the_caps_hold_closest_first()
	-- Six of yours and four of theirs close round the 1.
	local spots = { { 0, -20, 0 }, { 1, 0, 0 } }
	local own, opp = { 1 }, {}
	for k, id in { 2, 3, 4, 5, 6, 7 } do
		table.insert(spots, { id, -6 + 3 * k, 6 })
		table.insert(own, id)
	end
	for k, id in { 9, 10, 11, 12 } do
		table.insert(spots, { id, -6 + 3 * k, -6 })
		table.insert(opp, id)
	end
	local sim = armed(table_(spots), own, opp)
	roll(sim, 0, 40, 0)
	local outcome = Simulation.settle(sim, {})
	local mine, theirs = 0, 0
	for _, ev in ultEvents(outcome.events, "swallow") do
		if ev.value == 1 then
			mine += 1
		else
			theirs += 1
		end
	end
	check(mine == Config.Ults.BlackHole.MaxOwn, "yours: " .. mine)
	check(theirs == Config.Ults.BlackHole.MaxOpp, "theirs: " .. theirs)
end

function tests.every_caught_ball_is_swallowed_and_the_cue_ball_never_scratches_for_it()
	local r = V.rng(9)
	local scratches, opened, caught, swallowed = 0, 0, 0, 0
	for _, ts in V.states(80, 61) do
		local plan = V.shots(ts, 1)[1]
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, V.noisy(plan, 2, V.gauss(r), V.gauss(r)))
		Simulation.armEffect(sim, "BlackHole", V.ownIds(ts), nil, { OppTargets = {} })
		local outcome = Simulation.settle(sim, { strike })
		local opens = ultEvents(outcome.events, "open")
		if #opens == 0 then
			continue
		end
		opened += 1
		caught += #ultEvents(outcome.events, "pull")
		swallowed += #ultEvents(outcome.events, "swallow")
		-- A cue ball drop before anything else touched it after the hole opened: the push's.
		local touched = false
		for _, ev in outcome.events do
			if ev.t > opens[1].t and ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				touched = true
			end
			if ev.type == "pocket" and ev.ball == 0 and not touched then
				scratches += 1
			end
		end
	end
	check(opened >= 60, "enough holes: " .. opened)
	check(
		caught > 0 and swallowed == caught,
		("every caught ball swallowed: %d of %d"):format(swallowed, caught)
	)
	check(scratches == 0, "no scratch from the push: " .. scratches)
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 47)
	local r = V.rng(10)
	local compared = 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local own = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "BlackHole", own, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "BlackHole", own, nil, { OppTargets = {} })
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
end

return tests
