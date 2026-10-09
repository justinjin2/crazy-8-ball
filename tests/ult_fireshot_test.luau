--!strict
-- Fire Shot (the designer's third rework round, 2026-10-08: Super Bounce reworked, the
-- starter): the cue ball leaves the cue at Config.Ults.FireShot.LaunchSpeedScale times the
-- stroke's speed along the cloth (its spin with it, its hop kept), once; nothing else moves
-- differently; the client's replay matches the settle; the look's "turn" and "down" events mark
-- where the cue ball bends and lands. It is the starter, the tutorial's spin lands on it, a
-- saved Super Bounce becomes it, and the aim draws its full lines (physics_aim_test).

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Catalog = H.require("Ults.Catalog")
local FireShot = H.require("Ults.Effects.FireShot")

local geometry = V.geometry
local K = Config.Ults.FireShot.LaunchSpeedScale

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local tests = {}

function tests.the_launch_is_scaled_once_along_the_cloth_with_the_spin()
	local state = Simulation.newState(geometry, { Ball.new(0, -30, 0), Ball.new(1, 10, 5) })
	Simulation.strike(state, { angle = 0.2, power = 0.6, spin = { x = 0.3, y = -0.4 } })
	local cue = Simulation.findBall(state, 0)
	cue.vz = 7 -- a little hop, to see it kept
	local vx, vy, vz, wx, wy, wz = cue.vx, cue.vy, cue.vz, cue.wx, cue.wy, cue.wz
	state.fx = {}
	FireShot.step(state, Config.Physics.FixedStep)
	check(cue.vx == vx * K and cue.vy == vy * K, "twice as fast along the cloth")
	check(cue.vz == vz, "the hop kept")
	check(cue.wx == wx * K and cue.wy == wy * K and cue.wz == wz * K, "the spin with it")
	FireShot.step(state, Config.Physics.FixedStep)
	check(cue.vx == vx * K, "once only")
	local one = Simulation.findBall(state, 1)
	check(one.vx == 0 and one.vy == 0, "no other ball moves")
end

function tests.an_armed_shot_runs_further_than_the_same_stroke_plain()
	local balls = { Ball.new(0, -40, 0) }
	local function distance(armed: boolean): (number, number)
		local sim = Simulation.newState(geometry, Ball.cloneList(balls))
		local strike = Simulation.strike(sim, { angle = 0.35, power = 0.3 })
		if armed then
			Simulation.armEffect(sim, "FireShot", {}, nil)
		end
		local outcome = Simulation.settle(sim, { strike })
		local rails = 0
		for _, ev in outcome.events do
			if ev.type == "railHit" then
				rails += 1
			end
		end
		return sim.time, rails
	end
	local plainTime, plainRails = distance(false)
	local fireTime, fireRails = distance(true)
	check(fireRails > plainRails, ("more cushions: %d vs %d"):format(fireRails, plainRails))
	check(fireTime > plainTime, "rolls longer")
end

-- The look's scorch line bends at the "turn" events: one for each cushion and ball the cue
-- ball meets, in order, at its centre then.
function tests.the_turns_mark_where_the_cue_ball_bends()
	local R = Config.Balls.RadiusInches
	local function turnsOf(balls: { any }, shot: any): ({ any }, { any })
		local sim = Simulation.newState(geometry, balls)
		local strike = Simulation.strike(sim, shot)
		Simulation.armEffect(sim, "FireShot", {}, nil)
		local outcome = Simulation.settle(sim, { strike })
		local turns, hits = {}, {}
		for _, ev in outcome.events do
			if ev.type == "ult" and ev.kind == "turn" then
				table.insert(turns, ev)
			elseif
				(ev.type == "railHit" and ev.ball == 0)
				or (ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0))
			then
				table.insert(hits, ev)
			end
		end
		return turns, hits
	end

	-- Straight into a ball: the turn is where the two touch, two radii short of it.
	local turns, hits = turnsOf({ Ball.new(0, -30, 0), Ball.new(1, 0, 0) }, {
		angle = 0,
		power = 0.4,
	})
	check(#turns == #hits and #turns >= 1, ("a turn a hit: %d, %d"):format(#turns, #hits))
	local first = turns[1]
	check(first.other == 1 and first.ball == 0, "the cue ball meets ball 1")
	check(math.abs(first.x - -2 * R) < 0.02 and math.abs(first.y) < 0.02, "where they touch")
	check(first.value and first.value > 0, "with the impact speed")

	-- Round the table off the cushions: each turn is the rail hit's own spot, a ball's radius
	-- off a cushion.
	local g = geometry
	turns, hits = turnsOf({ Ball.new(0, -30, 0) }, { angle = 0.35, power = 0.5 })
	check(#turns == #hits and #turns >= 3, ("cushions: %d turns, %d hits"):format(#turns, #hits))
	local onCushion = 0
	for i, turn in turns do
		local hit = hits[i]
		check(turn.other == nil, "a cushion has no ball")
		check(turn.x == hit.x and turn.y == hit.y, "the rail hit's spot")
		if
			math.abs(math.abs(turn.x) - (g.halfLength - R)) < 0.05
			or math.abs(math.abs(turn.y) - (g.halfWidth - R)) < 0.05
		then
			onCushion += 1
		end
	end
	check(onCushion >= #turns - 1, "a ball's radius off a cushion (a jaw aside)")
end

-- A jump: "down" where the cue ball comes back onto the cloth (the burn starts again there),
-- on its line, one for each landing.
function tests.the_landings_mark_where_the_burn_starts_again()
	local sim = Simulation.newState(geometry, { Ball.new(0, -30, 0) })
	local strike = Simulation.strike(sim, { angle = 0, power = 0.65, elevation = 45 })
	Simulation.armEffect(sim, "FireShot", {}, nil)
	local outcome = Simulation.settle(sim, { strike })
	local downs, lands = {}, 0
	for _, ev in outcome.events do
		if ev.type == "ult" and ev.kind == "down" then
			table.insert(downs, ev)
		elseif ev.type == "land" and ev.ball == 0 then
			lands += 1
		end
	end
	check(#downs == lands and lands >= 1, ("a down a landing: %d, %d"):format(#downs, lands))
	local last = -30
	for _, down in downs do
		check(math.abs(down.y) < 0.02, "on the line of the shot")
		check(down.x > last, "further along each time")
		last = down.x
	end
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 61)
	local r = V.rng(14)
	local compared = 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local own = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "FireShot", own, nil)
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "FireShot", own, nil)
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

function tests.it_is_the_common_starter_and_takes_super_bounces_place()
	local row = Catalog.get("FireShot")
	check(row and row.Built and row.Effect == "FireShot", "built, with its effect")
	check(Catalog.rarity("FireShot") == "Common", "Common")
	check(Config.Ults.Default == "FireShot", "the starter")
	check(Config.Tutorial.SpinUlt == "FireShot", "the tutorial's spin lands on it")
	check(Catalog.retired("SuperBounce") == "FireShot", "a saved Super Bounce becomes it")
	check(Catalog.get("SuperBounce") == nil, "Super Bounce is gone")
	check(Catalog.retired("Ghost") == "Magnet", "Ghost still becomes Magnet")
end

function tests.the_aim_knows_the_launch_abilities()
	check(Catalog.launchScale("FireShot") == K, "Fire Shot")
	check(
		Catalog.launchScale("BlackFlash") == Config.Ults.BlackFlash.LaunchSpeedScale,
		"Black Flash"
	)
	check(Catalog.launchScale("Magnet") == nil and Catalog.launchScale(nil) == nil, "no other")
	-- Its longer lines (the designer: "to the next edge of a table"); no other ult has them.
	check(Catalog.fullLines("FireShot"), "Fire Shot draws the full lines")
	check(not Catalog.fullLines("BlackFlash") and not Catalog.fullLines(nil), "nothing else")
end

return tests
