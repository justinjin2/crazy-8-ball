--!strict
-- How a ball TURNS, as opposed to where it goes.
--
-- These guard the contract BallRenderer depends on. The renderer used to fake rotation from
-- how far a ball had moved (angle = distance / radius), which draws every ball as a perfect
-- no-slip roll. The simulation does not work that way: a firmly struck ball skids first,
-- and side spin turns a ball that is not travelling at all. The renderer now integrates
-- these angular velocities directly, so if the numbers below ever stop meaning what they
-- mean here, the balls on screen start lying about what the physics did.
--
-- Conventions (Ball.luau): rolling along +x means vx = R*wy; along +y, vy = -R*wx;
-- wz is side spin about the vertical.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Simulation = H.require("Physics.Simulation")
	local geometry = TableGeometry.build({ pocketsOpen = false })
	return Config, Ball, TableGeometry, Simulation, geometry
end

local function cueOnly(Ball, Simulation, geometry, x: number, y: number)
	return Simulation.newState(geometry, { Ball.new(0, x, y) })
end

return {
	["a skidding ball turns far less than a rolling one would"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		local dt = Config.Physics.FixedStep
		-- Start against the head rail so the whole skid happens before the far cushion: a
		-- rail bounce mid-skid reverses vx and the comparison below becomes meaningless.
		local state = cueOnly(Ball, Simulation, geometry, -geometry.halfLength + 2, 0)
		local b = state.balls[1]
		b.vx = 120 -- dead centre: no spin at all, so it must skid first

		local turn, travel = 0, 0
		local skidTurn: number?, skidTravel: number? = nil, nil
		local steps = 0
		local events = {}
		while not Simulation.isAtRest(state) and steps < 4000 do
			Simulation.step(state, dt, events)
			steps += 1
			turn += b.wy * dt
			travel += math.sqrt(b.vx * b.vx + b.vy * b.vy) * dt
			if skidTurn == nil and math.abs(b.vx - R * b.wy) < 1e-3 then
				skidTurn, skidTravel = turn, travel
				break
			end
		end

		H.expect(skidTurn ~= nil, "the ball should reach pure rolling")
		H.expect(#events == 0, "the skid must finish before the ball reaches a cushion")
		-- Theory: sliding ends at 5/7 of the launch speed, by which point the ball has
		-- turned 5/12 of what a no-slip roll over the same ground would have.
		local asIfRolling = (skidTravel :: number) / R
		local actual = skidTurn :: number
		H.expect(
			actual < asIfRolling * 0.75,
			("skid turned %.2f rad; a faked no-slip roll would have turned %.2f"):format(
				actual,
				asIfRolling
			)
		)
		H.near(actual / asIfRolling, 5 / 12, 0.08, "skid turn as a fraction of a rolling turn")
	end,

	["once rolling, the turn rate matches the travel rate exactly"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		local dt = Config.Physics.FixedStep
		local state = cueOnly(Ball, Simulation, geometry, -geometry.halfLength + 10, 0)
		local b = state.balls[1]
		b.vx = 120

		local checked = 0
		local steps = 0
		while not Simulation.isAtRest(state) and steps < 4000 do
			Simulation.step(state, dt, nil)
			steps += 1
			-- Once the contact point has stopped sliding the two must agree, because that
			-- is what "rolling" means.
			if math.abs(b.vx - R * b.wy) < 1e-6 and b.vx > 10 then
				H.near(R * b.wy, b.vx, 1e-6, "rolling: R*wy equals vx")
				checked += 1
			end
		end
		H.expect(checked > 50, ("expected a long rolling phase, saw %d steps"):format(checked))
	end,

	["a ball with only side spin turns on the spot and winds down"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local dt = Config.Physics.FixedStep
		local state = cueOnly(Ball, Simulation, geometry, 0, 0)
		local b = state.balls[1]
		b.wz = 60 -- english, no velocity at all
		local x0, y0 = b.x, b.y

		H.expect(Ball.isMoving(b), "a spinning ball counts as moving")
		local steps = 0
		local lastWz = math.abs(b.wz)
		while not Simulation.isAtRest(state) and steps < 4000 do
			Simulation.step(state, dt, nil)
			steps += 1
			local now = math.abs(b.wz)
			H.expect(now <= lastWz + 1e-9, "side spin never speeds up on its own")
			lastWz = now
		end
		H.near(b.x, x0, 1e-9, "side spin alone does not move the ball in x")
		H.near(b.y, y0, 1e-9, "side spin alone does not move the ball in y")
		H.near(b.wz, 0, 1e-9, "side spin decays to nothing")
	end,

	["top spin and back spin turn the ball opposite ways off the cue"] = function()
		local _, Ball, _, Simulation, geometry = setup()
		local Cue = H.require("Physics.Cue")
		local function struck(topSpin: number): number
			local state = cueOnly(Ball, Simulation, geometry, -geometry.halfLength + 10, 0)
			local b = state.balls[1]
			Cue.strike(b, { angle = 0, power = 0.5, spin = { x = 0, y = topSpin } })
			return b.wy
		end
		local top, back, dead = struck(0.4), struck(-0.4), struck(0)
		H.near(dead, 0, 1e-12, "a centre hit imparts no roll spin")
		H.expect(top > 0, "top spin rolls the ball forward along +x")
		H.expect(back < 0, "back spin rolls it backward")
		H.near(top, -back, 1e-9, "equal offsets give equal and opposite spin")
	end,

	["runHeadless gives the same outcome as run, without the frames"] = function()
		local Config, _, _, Simulation, geometry = setup()
		local Rack = H.require("Physics.Rack")
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		local shot = { angle = 0.03, power = 0.9 }
		local full = Simulation.run(state, shot)
		local lean = Simulation.runHeadless(state, shot)
		H.expect(#full.frames > 100, "run records frames")
		H.expect((lean :: any).frames == nil, "runHeadless records none")
		H.near(lean.duration, full.duration, 1e-12, "same duration")
		H.expect(lean.steps == full.steps, "same number of steps")
		H.expect(#lean.events == #full.events, "same events")
		for i, b in full.finalBalls do
			H.near(lean.finalBalls[i].x, b.x, 1e-12, "same final x")
			H.near(lean.finalBalls[i].y, b.y, 1e-12, "same final y")
			H.near(lean.finalBalls[i].wz, b.wz, 1e-12, "same final side spin")
		end
		-- Config is referenced so the harness loads it the same way the others do.
		H.expect(Config.Physics.FixedStep > 0, "fixed step is set")
	end,
}
