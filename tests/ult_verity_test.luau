--!strict
-- Verity (the abilities rework; evil since the designer's second round, 2026-10-08): the first
-- ball hit is eaten (counted as pocketed for its owner); an early 8 is refused; she chews in
-- place, shoving her neighbours clear as she swells, then rolls along the shot's line eating up
-- to MaxEaten more of yours and bumping the rest aside, hopping over the 8; she stops before
-- the cushions and pockets and lands clear of every ball; the client's replay matches the
-- settle.

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

local function byBall(events: { any }): { [number]: any }
	local out = {}
	for _, ev in events do
		out[ev.ball] = ev
	end
	return out
end

local SOLIDS = { "solids", "stripes" }

local tests = {}

function tests.the_first_ball_is_eaten_and_counted_and_the_turn_kept()
	local balls = table_({ { 0, -30, 0 }, { 1, -20, 0 }, { 2, 30, 18 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1, 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local eat = ultEvents(outcome.events, "eat")
	check(#eat == 1 and eat[1].ball == 1 and eat[1].value == 1 and eat[1].other == 1, "the 1 eaten")
	check(Simulation.findBall(sim, 1).pocketed, "gone")
	check(table.find(verdict.pockets, 1) ~= nil, "counted as pocketed")
	check(verdict.foul == nil and verdict.keep, "legal, the turn kept: " .. tostring(verdict.foul))
	check(
		#ultEvents(outcome.events, "roll") == 1 and #ultEvents(outcome.events, "land") == 1,
		"rolled, landed"
	)
end

function tests.an_opponents_ball_first_is_eaten_for_them_and_is_a_foul()
	local balls = table_({ { 0, -30, 0 }, { 9, -20, 0 }, { 2, 30, 18 }, { 8, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local eat = ultEvents(outcome.events, "eat")
	check(#eat == 1 and eat[1].ball == 9 and eat[1].value == 0, "the 9 eaten")
	check(verdict.foul == "WrongContact", "a foul: " .. tostring(verdict.foul))
end

function tests.an_early_8_is_refused_and_nothing_else_happens()
	local balls = table_({ { 0, -30, 0 }, { 8, -20, 0 }, { 2, 30, 18 }, { 9, 40, -20 } })
	local sim = armed(balls, { 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local _, outcome = judged(sim, balls, SOLIDS)
	check(#ultEvents(outcome.events, "refuse") == 1, "refused")
	check(
		#ultEvents(outcome.events, "eat") == 0 and #ultEvents(outcome.events, "roll") == 0,
		"no eat, no roll"
	)
	check(not Simulation.findBall(sim, 8).pocketed, "the 8 stays")
end

function tests.the_legal_8_is_eaten_and_wins()
	local balls = table_({ { 0, -30, 0 }, { 8, -20, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 8 }, { 9 }, 3)
	roll(sim, 0, 60, 0)
	local verdict = judged(sim, balls, SOLIDS, 3)
	check(
		verdict.winner == 1 and verdict.reason == "LegalEight",
		"a win: " .. tostring(verdict.reason)
	)
end

function tests.she_chews_in_place_then_rolls_along_the_shot_line()
	local balls = table_({ { 0, -30, 0 }, { 1, -20, 0 }, { 9, 40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	local eat = ultEvents(outcome.events, "eat")[1]
	local rolled = ultEvents(outcome.events, "roll")[1]
	local landed = ultEvents(outcome.events, "land")[1]
	check(eat and rolled and landed, "eat, roll, land")
	check(math.abs(rolled.t - eat.t - C.EatShotSeconds) < 0.01, "the chew comes first")
	-- She ate where the cue ball touched the 1 (two radii short of it) and stayed there.
	check(math.abs(rolled.x - (-20 - 2 * R)) < 0.3 and rolled.y == 0, "chewed in place")
	check(
		math.abs(landed.y) < 1e-6 and landed.x > rolled.x + 10,
		"she rolled forward along the line"
	)
	local cue = Simulation.findBall(sim, 0)
	check(not cue.pocketed, "the cue ball is never lost")
	check(
		math.abs(cue.x) <= geometry.halfLength - R and math.abs(cue.y) <= geometry.halfWidth - R,
		"on the cloth"
	)
	local went = math.sqrt((landed.x - rolled.x) ^ 2 + (landed.y - rolled.y) ^ 2)
	check(went <= C.RollInches + 1, "no longer than the roll: " .. went)
end

function tests.her_body_stops_short_of_the_cushion()
	-- Aimed straight at the foot cushion: her swollen body must stop before it.
	local balls = table_({ { 0, 10, 0 }, { 1, 16, 0 }, { 9, -40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	local landed = ultEvents(outcome.events, "land")[1]
	check(landed ~= nil, "landed")
	local most = geometry.halfLength - C.BodyRadiusInches - C.EdgeMarginInches
	check(landed.x <= most + 1e-6, "her body short of the cushion: " .. landed.x)
	check(not Simulation.findBall(sim, 0).pocketed, "the cue ball stays")
end

function tests.she_eats_up_to_two_more_of_yours_on_the_roll_and_bumps_the_rest()
	-- A row on her line: the 1 (her first bite), the 2, the 10 (theirs), the 8, the 3 and the
	-- 4 (yours, past her fill).
	local balls = table_({
		{ 0, -40, 0 },
		{ 1, -30, 0 },
		{ 2, -12, 1 },
		{ 10, -2, -1 },
		{ 8, 8, 2 },
		{ 3, 16, -1 },
		{ 4, 24, 1 },
	})
	local sim = armed(balls, { 1, 2, 3, 4 }, { 10 })
	roll(sim, 0, 60, 0)
	local verdict, outcome = judged(sim, balls, SOLIDS)
	local eaten = byBall(ultEvents(outcome.events, "eat"))
	local bumped = byBall(ultEvents(outcome.events, "bump"))
	local hopped = byBall(ultEvents(outcome.events, "hop"))
	check(eaten[1] and eaten[2] and eaten[3], "the 1, 2 and 3 eaten")
	check(eaten[2].other == 2 and eaten[3].other == 3, "counted in order")
	check(eaten[4] == nil and bumped[4], "the 4 bumped: she is full")
	check(eaten[10] == nil and bumped[10], "theirs bumped, never eaten")
	check(hopped[8] and eaten[8] == nil and bumped[8] == nil, "she hops over the 8")
	check(not Simulation.findBall(sim, 8).pocketed, "the 8 stays up")
	for _, id in { 1, 2, 3 } do
		check(table.find(verdict.pockets, id) ~= nil, "the " .. id .. " counts as pocketed")
	end
end

function tests.she_shoves_her_neighbours_clear_as_she_swells()
	-- The 9 sits beside where she bites the 1: inside her swollen body, so it is shoved out.
	local hit = -20 - 2 * R -- where the cue ball touches the 1
	local balls = table_({ { 0, -30, 0 }, { 1, -20, 0 }, { 9, hit, 3.5 }, { 2, 40, -20 } })
	local sim = armed(balls, { 1, 2 }, { 9 })
	roll(sim, 0, 60, 0)
	local outcome = Simulation.settle(sim, {})
	local shoved = byBall(ultEvents(outcome.events, "shove"))
	check(shoved[9] ~= nil, "the 9 shoved")
	local nine = Simulation.findBall(sim, 9)
	local d = math.sqrt((nine.x - hit) ^ 2 + nine.y ^ 2)
	check(d >= C.BodyRadiusInches + R - 0.05, "clear of her body: " .. d)
	check(d <= C.BodyRadiusInches + R + C.ShoveGapInches + 0.5, "only just: " .. d)
	check(nine.y > 3.5, "outward")
	check(byBall(ultEvents(outcome.events, "eat"))[9] == nil, "never eaten: not yours")
end

function tests.the_8_is_never_shoved_toward_a_pocket()
	-- The 8 just off the top side pocket; she bites the 1 beside it, so her swell would push
	-- the 8 toward the pocket: it stays put (a hop), and she hops it again as she rolls off.
	local side = geometry.pockets[2]
	local y8 = side.y - (side.radius + 2 * R - 0.3)
	local balls =
		table_({ { 0, -14, y8 - 2.4 }, { 1, 1, y8 - 2.4 }, { 8, 0, y8 }, { 9, -40, -20 } })
	local sim = armed(balls, { 1 }, { 9 })
	roll(sim, 0, 40, 0)
	local outcome = Simulation.settle(sim, {})
	check(byBall(ultEvents(outcome.events, "eat"))[1] ~= nil, "the 1 eaten")
	check(byBall(ultEvents(outcome.events, "shove"))[8] == nil, "the 8 not shoved")
	check(byBall(ultEvents(outcome.events, "hop"))[8] ~= nil, "hopped")
	local eight = Simulation.findBall(sim, 8)
	check(not eight.pocketed and eight.x == 0 and eight.y == y8, "the 8 never moved")
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
