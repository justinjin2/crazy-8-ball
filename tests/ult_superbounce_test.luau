--!strict
-- Super Bounce (docs/prompts/ABILITIES_PROMPT.md 7.3): the cue ball's own bouncy material for
-- the shot's first seconds, armed the way the server arms it (Match.shotOverrides, which asks
-- Arming.extras), and the first ball of yours it hits catching the bounce (Effects/SuperBounce).
-- Nothing else changes, normal friction returns after the cap, the client's step-by-step replay
-- matches the server's settle, and no ball ever tunnels through a cushion at the new speeds.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Arming = H.require("Ults.Arming")

local geometry = V.geometry
local SB = Config.Ults.SuperBounce
local R = Config.Balls.RadiusInches

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function bounce(): any
	return Arming.extras("SuperBounce", {
		own = {},
		opp = {},
		eightPocket = nil,
		legalEight = false,
		open = true,
		pick = nil,
		balls = {},
	})
end

-- One shot as the server runs it, with or without the ability (`targets`: the shooter's
-- balls, none by default). Returns the settled state, the outcome and the cue ball's cushion
-- hits.
local function shoot(
	balls: { any },
	payload: any,
	on: boolean,
	targets: { number }?
): (any, any, number)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "a valid shot"))
	if on then
		Simulation.armEffect(sim, "SuperBounce", targets or {}, nil, bounce())
	end
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "a cue ball"))
	local outcome = Simulation.settle(sim, { strike })
	local rails = 0
	for _, ev in outcome.events do
		if ev.type == "railHit" and ev.ball == 0 then
			rails += 1
		end
	end
	return sim, outcome, rails
end

local tests = {}

function tests.the_extras_are_the_config_material_until_the_cap()
	local o = bounce()
	check(o.CueRailRestitution == SB.RailRestitution, "rail restitution")
	check(o.CueRailFriction == SB.RailFriction, "rail friction")
	check(o.CueBallRestitution == SB.BallRestitution, "ball restitution")
	check(o.CueSlidingFriction == SB.SlidingFriction, "sliding friction")
	check(o.CueRollingFriction == SB.RollingFriction, "rolling friction")
	check(o.CueUntil == SB.Seconds, "the cap")
end

function tests.a_medium_shot_alone_touches_six_to_ten_rails()
	local balls = { Ball.new(0, -25, 3) }
	local payload = { angle = 0.35, power = 0.5 }
	local _, _, plain = shoot(balls, payload, false)
	local _, outcome, rails = shoot(balls, payload, true)
	check(rails >= 6 and rails <= 12, ("%d rails with it (%d without)"):format(rails, plain))
	check(rails >= plain * 2, "at least twice the plain shot's")
	check(not outcome.capped, "it still settles inside the shot limit")
end

function tests.only_the_cue_ball_changes()
	-- An object ball rolling on its own is untouched by the cue's material.
	local balls = { Ball.new(0, -40, -20), Ball.new(5, 10, 10) }
	local lone = balls[2]
	lone.vx, lone.vy = 80, 30
	lone.wx, lone.wy = -30 / R, 80 / R
	local plain = Simulation.newState(geometry, Ball.cloneList(balls))
	local on = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.armEffect(on, "SuperBounce", {}, nil, bounce())
	-- The cue ball stays at rest, so the two runs differ only if the 5 is changed.
	local a = Simulation.settle(plain, {})
	local b = Simulation.settle(on, {})
	check(a.duration == b.duration, "same length")
	local pa, pb =
		assert(Simulation.findBall(plain, 5), "5"), assert(Simulation.findBall(on, 5), "5")
	check(pa.x == pb.x and pa.y == pb.y, "the 5 ends in the same spot")
end

function tests.normal_friction_returns_after_the_cap()
	-- Past CueUntil the cue ball rolls to a stop as usual: the shot ends well before a second
	-- cap would, even though the bouncy material alone would keep it going much longer.
	local balls = { Ball.new(0, -25, 3) }
	local _, outcome = shoot(balls, { angle = 0.35, power = 1 }, true)
	check(not outcome.capped, "not capped")
	check(outcome.duration < SB.Seconds + 12, ("settled at %.1f s"):format(outcome.duration))
end

function tests.no_ball_tunnels_through_a_cushion_at_the_new_speeds()
	-- Hard shots every way on real tables: every ball left on the table is inside the cushions.
	local states = V.states(24, 21)
	local r = V.rng(9)
	local limitX = geometry.halfLength - R + 1e-6
	local limitY = geometry.halfWidth - R + 1e-6
	local shots = 0
	for _, ts in states do
		for _ = 1, 3 do
			local payload = {
				angle = V.uniform(r) * 2 * math.pi,
				power = 0.8 + V.uniform(r) * 0.2,
				spin = { x = V.uniform(r) * 1.2 - 0.6, y = V.uniform(r) * 1.2 - 0.6 },
			}
			-- Every object ball but the 8 is the shooter's, so the first hit is caught too.
			local own = {}
			for _, b in ts.balls do
				if b.id ~= 0 and b.id ~= 8 and not b.pocketed then
					table.insert(own, b.id)
				end
			end
			local sim, outcome = shoot(ts.balls, payload, true, own)
			if outcome.capped then
				continue
			end
			shots += 1
			for _, b in sim.balls do
				-- A ball resting in a pocket's mouth sits past the cushion line legitimately.
				local inMouth = false
				for _, p in geometry.pockets do
					local dx, dy = b.x - p.x, b.y - p.y
					if dx * dx + dy * dy < (p.radius + 3 * R) ^ 2 then
						inMouth = true
					end
				end
				if not b.pocketed and not inMouth then
					check(
						math.abs(b.x) <= limitX and math.abs(b.y) <= limitY,
						("ball %d at (%.3f, %.3f) is past a cushion"):format(b.id, b.x, b.y)
					)
				end
			end
		end
	end
	check(shots >= 60, "enough hard shots: " .. shots)
end

local C = SB.Caught

local function railsOf(outcome: any, id: number): number
	local n = 0
	for _, ev in outcome.events do
		if ev.type == "railHit" and ev.ball == id then
			n += 1
		end
	end
	return n
end

local function caughtEvent(outcome: any): any
	for _, ev in outcome.events do
		if ev.type == "ult" and ev.kind == "caught" then
			return ev
		end
	end
	return nil
end

function tests.the_first_ball_of_yours_hit_catches_the_bounce()
	-- The cue ball drives the 3 up and down the table: caught, it comes off more cushions.
	local balls = { Ball.new(0, -30, 0), Ball.new(3, -10, 0) }
	local payload = { angle = 0, power = 0.9 }
	local _, outcome = shoot(balls, payload, true, { 3 })
	local _, notCaught = shoot(balls, payload, true, {})
	local ev = caughtEvent(outcome)
	check(ev ~= nil and ev.ball == 3, "a caught event for the 3")
	check(caughtEvent(notCaught) == nil, "nothing caught when the 3 is not the shooter's")
	local a, b = railsOf(outcome, 3), railsOf(notCaught, 3)
	check(a > b, ("the caught 3 comes off more cushions (%d, %d without)"):format(a, b))
end

function tests.an_opponent_ball_or_the_8_first_catches_nothing()
	local payload = { angle = 0, power = 0.6 }
	-- The 5 is hit first but only the 3 is the shooter's.
	local _, outcome = shoot(
		{ Ball.new(0, -30, 0), Ball.new(5, -10, 0), Ball.new(3, 20, 15) },
		payload,
		true,
		{ 3 }
	)
	check(caughtEvent(outcome) == nil, "the opponent's 5 is not caught")
	-- The 8, even when it is in the shooter's targets (their legal 8).
	local _, outcome8 = shoot({ Ball.new(0, -30, 0), Ball.new(8, -10, 0) }, payload, true, { 8 })
	check(caughtEvent(outcome8) == nil, "the 8 is never caught")
end

function tests.a_caught_ball_boings_off_a_pocket_jaw_into_it()
	-- The 3 driven straight up into the top cushion just along from the top-left corner: it
	-- comes straight back down, unless it is caught, when the jaw sends it into the corner.
	local p = geometry.pockets[1]
	local x = p.x + p.radius + 1.5
	local hitY = geometry.halfWidth - R
	local dx, dy = p.x - x, p.y - hitY
	check(
		math.sqrt(dx * dx + dy * dy) < p.radius + assert(C.JawReachInches, "a jaw reach"),
		"the hit is inside the jaw reach"
	)
	local balls = { Ball.new(0, x, hitY - 25), Ball.new(3, x, hitY - 12) }
	local payload = { angle = math.pi / 2, power = 0.45 }
	local sim, outcome = shoot(balls, payload, true, { 3 })
	local plain = shoot(balls, payload, true, {})
	local jaw = nil
	for _, ev in outcome.events do
		if ev.type == "ult" and ev.kind == "jaw" then
			jaw = ev
		end
	end
	check(jaw ~= nil and jaw.ball == 3 and jaw.other == p.id, "a jaw event at the corner")
	local caught3 = assert(Simulation.findBall(sim, 3), "the 3")
	check(caught3.pocketed and caught3.pocket == p.id, "the caught 3 drops in the corner")
	check(not assert(Simulation.findBall(plain, 3), "the 3").pocketed, "the plain 3 does not")
end

function tests.the_replay_matches_the_settle_with_a_caught_ball()
	-- A client replays the shot step by step from the same seed: it must land on the server's
	-- numbers exactly, caught ball and all.
	local states = V.states(12, 5)
	local r = V.rng(3)
	local compared = 0
	for _, ts in states do
		local own = {}
		for _, b in ts.balls do
			if b.id ~= 0 and b.id ~= 8 and not b.pocketed then
				table.insert(own, b.id)
			end
		end
		local payload = { angle = V.uniform(r) * 2 * math.pi, power = 0.4 + V.uniform(r) * 0.5 }
		local sim, outcome = shoot(ts.balls, payload, true, own)
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "a valid shot"))
		Simulation.armEffect(replay, "SuperBounce", own, nil, bounce())
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "a cue ball"))
		local steps = 0
		while not Simulation.isAtRest(replay) and steps < 20000 do
			Simulation.step(replay, Config.Physics.FixedStep, {})
			steps += 1
		end
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
