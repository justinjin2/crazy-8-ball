--!strict
-- Black Flash (docs/prompts/ABILITIES_PROMPT.md 7.11): the first ball hit, whoever's, leaves
-- the table and counts as pocketed for its owner (the 8 by the 8's rules); the blast nudges the
-- balls round it toward their pockets, the opponent's at half, never the 8 or the cue ball,
-- within the caps; the cue ball bounces back and never scratches for it; the client's replay
-- matches the server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Judge = H.require("Rules.ShotJudge")

local geometry = V.geometry
local C = Config.Ults.BlackFlash
local R = Config.Balls.RadiusInches
local DT = Config.Physics.FixedStep

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
	Simulation.armEffect(sim, "BlackFlash", targets, eightPocket, { OppTargets = opp })
	return sim
end

local function roll(sim: any, id: number, vx: number, vy: number)
	local b = assert(Simulation.findBall(sim, id), "ball " .. id)
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
end

-- Run to rest and judge it as the server does (solids shoot; `called` for the 8).
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

function tests.your_ball_shattered_counts_as_your_pot()
	local balls = table_({ { 0, -20, 0 }, { 3, -10, 0 }, { 9, 30, 15 }, { 8, 30, -15 } })
	local sim = armed(balls, { 3 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	check(Simulation.findBall(sim, 3).pocketed, "the 3 gone")
	check(table.find(verdict.pockets, 3) ~= nil, "counted as pocketed")
	check(verdict.foul == nil and verdict.winner == nil, "a legal shot: " .. tostring(verdict.foul))
	check(#ultEvents(outcome.events, "flash") == 1, "one flash")
end

function tests.the_cue_ball_launches_at_three_times_the_speed()
	-- The designer, 2026-09-30: after the first step the cue ball moves LaunchSpeedScale times
	-- as fast as the same shot without the ability (friction over one step is far smaller).
	local balls = table_({ { 0, -40, 0 }, { 3, 40, 20 } })
	local plain = Simulation.newState(geometry, Ball.cloneList(balls))
	roll(plain, 0, 60, 0)
	Simulation.step(plain, DT, {})
	local sim = armed(balls, { 3 }, {})
	roll(sim, 0, 60, 0)
	Simulation.step(sim, DT, {})
	local slow = Simulation.findBall(plain, 0).vx
	local fast = Simulation.findBall(sim, 0).vx
	check(math.abs(fast / slow - C.LaunchSpeedScale) < 0.02, ("launch x%.3f"):format(fast / slow))
	-- Only once: the next step does not multiply again.
	Simulation.step(sim, DT, {})
	check(Simulation.findBall(sim, 0).vx <= fast, "not boosted twice")
end

function tests.the_opponents_ball_shattered_counts_for_them_and_is_a_foul()
	local balls = table_({ { 0, -20, 0 }, { 9, -10, 0 }, { 3, 30, 15 }, { 8, 30, -15 } })
	local sim = armed(balls, { 3 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS)
	check(Simulation.findBall(sim, 9).pocketed, "the 9 gone")
	check(table.find(verdict.pockets, 9) ~= nil, "counted as pocketed")
	check(verdict.foul == "WrongContact", "a foul: " .. tostring(verdict.foul))
end

function tests.an_early_8_shattered_loses()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 3, 30, 15 }, { 9, 30, -15 } })
	local sim = armed(balls, { 3 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS)
	check(verdict.winner == 2, "the opponent wins: " .. tostring(verdict.reason))
end

function tests.the_legal_8_shattered_wins()
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 }, { 9, 30, -15 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS, 3)
	check(
		verdict.winner == 1 and verdict.reason == "LegalEight",
		"a win: " .. tostring(verdict.reason)
	)
end

function tests.the_blast_nudges_yours_full_theirs_half_never_the_8()
	-- The 1 is shattered at (-10, 0); the 2 and the 10 sit the same distance from it; the 8
	-- beside them. All at rest.
	local balls = table_({
		{ 0, -20, 0 },
		{ 1, -10, 0 },
		{ 2, -10, 8 },
		{ 10, -10, -8 },
		{ 8, -2, 0 },
	})
	local sim = armed(balls, { 1, 2 }, { 10 })
	roll(sim, 0, 60, 0)
	local events = {}
	for _ = 1, 2000 do
		Simulation.step(sim, DT, events)
		if #ultEvents(events, "flash") > 0 then
			break
		end
	end
	local nudges = ultEvents(events, "nudge")
	local byBall = {}
	for _, ev in nudges do
		byBall[ev.ball] = ev.value
	end
	check(byBall[2] == 1, "the 2 at full")
	check(byBall[10] == Config.Ults.Shared.OpponentFactor, "the 10 at half")
	check(byBall[8] == nil and byBall[0] == nil, "never the 8 or the cue ball")
	local b8 = assert(Simulation.findBall(sim, 8), "8")
	check(b8.vx == 0 and b8.vy == 0, "the 8 not moved")
end

function tests.the_reach_is_capped()
	local S = Config.Ults.Shared
	check(C.RadiusInches <= S.MaxReachShare * 2 * geometry.halfLength + 1e-9, "reach capped")
end

function tests.nothing_out_of_reach_moves()
	local balls = table_({ { 0, -20, 0 }, { 1, -10, 0 }, { 2, -10 + C.RadiusInches + 3, 12 } })
	local sim = armed(balls, { 1, 2 }, {})
	roll(sim, 0, 60, 0)
	local events = {}
	for _ = 1, 2000 do
		Simulation.step(sim, DT, events)
		if #ultEvents(events, "flash") > 0 then
			break
		end
	end
	check(#ultEvents(events, "nudge") == 0, "no nudge")
end

function tests.the_caps_hold()
	-- Six of yours and four of theirs round the shattered 1.
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
	roll(sim, 0, 60, 0)
	local events = {}
	for _ = 1, 2000 do
		Simulation.step(sim, DT, events)
		if #ultEvents(events, "flash") > 0 then
			break
		end
	end
	local mine, theirs = 0, 0
	for _, ev in ultEvents(events, "nudge") do
		if ev.value == 1 then
			mine += 1
		else
			theirs += 1
		end
	end
	check(mine == Config.Ults.BlackFlash.MaxOwn - 1, "yours: the shattered one and " .. mine)
	check(theirs == Config.Ults.BlackFlash.MaxOpp, "theirs: " .. theirs)
end

function tests.the_cue_ball_bounces_back_and_never_scratches()
	-- A cue ball bouncing back toward the bottom-left corner stops short of it.
	local r = V.rng(9)
	local scratches, flashes = 0, 0
	for _, ts in V.states(80, 51) do
		local plan = V.shots(ts, 1)[1]
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, V.noisy(plan, 2, V.gauss(r), V.gauss(r)))
		Simulation.armEffect(sim, "BlackFlash", V.ownIds(ts), nil, { OppTargets = {} })
		local outcome = Simulation.settle(sim, { strike })
		if #ultEvents(outcome.events, "flash") == 0 then
			continue
		end
		flashes += 1
		-- The cue ball's drop before any other ball touched it after the flash: the blast's.
		local flashT = ultEvents(outcome.events, "flash")[1].t
		local touched = false
		for _, ev in outcome.events do
			if ev.t > flashT and ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				touched = true
			end
			if ev.type == "pocket" and ev.ball == 0 and not touched then
				scratches += 1
			end
		end
	end
	check(flashes >= 60, "enough flashes: " .. flashes)
	check(scratches == 0, "no scratch from the bounce: " .. scratches)
	-- And the bounce itself: straight back, about BounceInches.
	local balls = table_({ { 0, -20, 0 }, { 1, -10, 0 } })
	local sim = armed(balls, { 1 }, {})
	roll(sim, 0, 60, 0)
	Simulation.settle(sim, {})
	local cue = assert(Simulation.findBall(sim, 0), "cue")
	check(cue.x < -10 - 2 * R and math.abs(cue.y) < 1e-6, ("bounced back: %.2f"):format(cue.x))
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 47)
	local r = V.rng(10)
	local compared = 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local ids = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "BlackFlash", ids, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "BlackFlash", ids, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "cue"))
		for _ = 1, 40000 do
			if Simulation.isAtRest(replay) then
				break
			end
			Simulation.step(replay, DT, {})
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
