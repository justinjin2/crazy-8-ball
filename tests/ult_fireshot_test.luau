--!strict
-- Fire Shot (the designer's third rework round, 2026-10-08: Super Bounce reworked, the
-- starter): the cue ball leaves the cue at Config.Ults.FireShot.LaunchSpeedScale times the
-- stroke's speed along the cloth (its spin with it, its hop kept), once; nothing else moves
-- differently; the client's replay matches the settle. It is the starter, the tutorial's spin
-- lands on it, and a saved Super Bounce becomes it.

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
end

return tests
