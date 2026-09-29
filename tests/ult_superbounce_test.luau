--!strict
-- Super Bounce (docs/prompts/ABILITIES_PROMPT.md 7.3): the cue ball's own bouncy material for
-- the shot's first seconds, armed the way the server arms it (Match.shotOverrides, which asks
-- Arming.extras). Only the cue ball changes, normal friction returns after the cap, and no
-- ball ever tunnels through a cushion at the new speeds.

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

-- One shot as the server runs it, with or without the ability. Returns the settled state,
-- the outcome and the cue ball's cushion hits.
local function shoot(balls: { any }, payload: any, on: boolean): (any, any, number)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "a valid shot"))
	if on then
		Simulation.armEffect(sim, "SuperBounce", {}, nil, bounce())
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
			local sim, outcome = shoot(ts.balls, payload, true)
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

return tests
