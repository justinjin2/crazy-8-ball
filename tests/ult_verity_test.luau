--!strict
-- Verity (the abilities rework, 2026-10-08): the first ball hit is thrown off the table
-- (counted as pocketed for its owner); an early 8 is refused; Verity grabs, then sprints along
-- the shot's line kicking balls (yours into pockets first, the 8 never), stops short of the
-- cushions and pockets and lands clear of every ball; the client's replay matches the settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Judge = H.require("Rules.ShotJudge")

local geometry = V.geometry
local C = Config.Ults.Verity
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
	Simulation.armEffect(sim, "Verity", targets, eightPocket, { OppTargets = opp })
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

function tests.the_first_ball_is_thrown_and_counted_and_the_turn_kept()
	local balls = table_({ { 0, -30, 0 }, { 1, -20, 0 }, { 2, 30, 18 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1, 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local grab = ultEvents(outcome.events, "grab")
	check(#grab == 1 and grab[1].ball == 1 and grab[1].value == 1, "the 1 thrown")
	check(Simulation.findBall(sim, 1).pocketed, "off the table")
	check(table.find(verdict.pockets, 1) ~= nil, "counted as pocketed")
	check(verdict.foul == nil and verdict.keep, "legal, the turn kept: " .. tostring(verdict.foul))
	check(
		#ultEvents(outcome.events, "run") == 1 and #ultEvents(outcome.events, "land") == 1,
		"ran, landed"
	)
end

function tests.an_opponents_ball_first_is_thrown_for_them_and_is_a_foul()
	local balls = table_({ { 0, -30, 0 }, { 9, -20, 0 }, { 2, 30, 18 }, { 8, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local grab = ultEvents(outcome.events, "grab")
	check(#grab == 1 and grab[1].ball == 9 and grab[1].value == 0, "the 9 thrown")
	check(verdict.foul == "WrongContact", "a foul: " .. tostring(verdict.foul))
end

function tests.an_early_8_is_refused_and_nothing_else_happens()
	local balls = table_({ { 0, -30, 0 }, { 8, -20, 0 }, { 2, 30, 18 }, { 9, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local _, outcome = judged(sim, balls, SOLIDS)
	check(#ultEvents(outcome.events, "refuse") == 1, "refused")
	check(
		#ultEvents(outcome.events, "grab") == 0 and #ultEvents(outcome.events, "run") == 0,
		"no throw, no run"
	)
	check(not Simulation.findBall(sim, 8).pocketed, "the 8 stays")
end

function tests.the_legal_8_is_thrown_and_wins()
	local balls = table_({ { 0, -30, 0 }, { 8, -20, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS, 3)
	check(
		verdict.winner == 1 and verdict.reason == "LegalEight",
		"a win: " .. tostring(verdict.reason)
	)
end

function tests.she_grabs_first_then_runs_along_the_shot_line()
	local balls = table_({ { 0, -30, 0 }, { 1, -20, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	local grab = ultEvents(outcome.events, "grab")[1]
	local run = ultEvents(outcome.events, "run")[1]
	local landed = ultEvents(outcome.events, "land")[1]
	check(grab and run and landed, "grab, run, land")
	check(run.t - grab.t >= C.GrabShotSeconds - 1e-6, "the grab comes first")
	check(math.abs(landed.y) < 1e-6 and landed.x > run.x + 10, "she ran forward along the line")
	local cue = Simulation.findBall(sim, 0)
	check(not cue.pocketed, "the cue ball is never lost")
	check(
		math.abs(cue.x) <= geometry.halfLength - R and math.abs(cue.y) <= geometry.halfWidth - R,
		"on the cloth"
	)
	local ran = math.sqrt((landed.x - run.x) ^ 2 + (landed.y - run.y) ^ 2)
	check(ran <= C.RunInches + 1, "no longer than the run: " .. ran)
end

function tests.she_stops_short_of_the_cushion()
	-- Aimed straight at the foot cushion from close: she must stop before it.
	local balls = table_({ { 0, 20, 0 }, { 1, 26, 0 }, { 9, -40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 60, 0)
	Simulation.settle(sim, {})
	local cue = Simulation.findBall(sim, 0)
	check(not cue.pocketed, "the cue ball stays")
	check(
		cue.x <= geometry.halfLength - R - C.EdgeMarginInches + 1e-6,
		"short of the cushion: " .. cue.x
	)
end

function tests.balls_in_her_path_are_kicked_and_yours_aimed_into_pockets()
	-- A row of balls on her line: two of yours (aimed), one of theirs (booted), the 8 (never).
	local balls = table_({
		{ 0, -40, 0 },
		{ 1, -30, 0 },
		{ 2, -10, 1 },
		{ 10, 0, -1 },
		{ 8, 10, 0.5 },
		{ 3, 20, -1 },
		{ 4, 25, 1 },
	})
	local sim = armed(balls, { 1, 2, 3, 4 }, { 10 })
	roll(sim, 0, 60, 0)
	local _, outcome = judged(sim, balls, SOLIDS)
	local kicks = ultEvents(outcome.events, "kick")
	local kicked: { [number]: any } = {}
	local aimed = 0
	for _, ev in kicks do
		kicked[ev.ball] = ev
		if ev.value == 1 then
			aimed += 1
		end
	end
	check(kicked[2] and kicked[10], "the 2 and the 10 kicked")
	check(kicked[8] == nil, "never the 8")
	check(aimed <= C.MaxAimed, "at most MaxAimed aimed: " .. aimed)
	check(kicked[10].value == 0, "theirs booted, never aimed")
end

function tests.she_lands_clear_of_every_ball()
	local r = V.rng(5)
	local landings = 0
	for _, ts in V.states(40, 77) do
		local plan = V.shots(ts, 1)[1]
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, V.noisy(plan, 2, V.gauss(r), V.gauss(r)))
		Simulation.armEffect(sim, "Verity", V.ownIds(ts), nil, { OppTargets = {} })
		local outcome = Simulation.settle(sim, { strike })
		if #ultEvents(outcome.events, "land") == 0 then
			continue
		end
		landings += 1
		local cue = Simulation.findBall(sim, 0)
		check(not cue.pocketed, "the cue ball stays")
		for _, b in sim.balls do
			if b.id ~= 0 and not b.pocketed then
				local d = math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
				check(d >= 2 * R - 0.05, "overlapping ball " .. b.id .. ": " .. d)
			end
		end
	end
	check(landings >= 25, "enough landings: " .. landings)
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 59)
	local r = V.rng(12)
	local compared = 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local own = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "Verity", own, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "Verity", own, nil, { OppTargets = {} })
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
