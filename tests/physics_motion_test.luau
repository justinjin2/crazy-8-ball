--!strict
-- Milestone 1 physics tests: one ball on a closed table.

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

-- Step a state manually and hand every step to a callback. Returns the number of steps.
local function stepUntilRest(Config, Simulation, state, onStep: ((number) -> ())?): number
	local dt = Config.Physics.FixedStep
	local maxSteps = math.floor(Config.Physics.MaxShotSeconds / dt)
	local steps = 0
	while not Simulation.isAtRest(state) and steps < maxSteps do
		Simulation.step(state, dt, nil)
		steps += 1
		if onStep then
			onStep(steps)
		end
	end
	return steps
end

return {
	["a struck ball slows down, stops, and stays on the table"] = function()
		local Config, Ball, TableGeometry, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		local angles = { 0, 0.3, 1.1, 2.4, 3.9, 5.2 }
		for _, angle in angles do
			for _, power in { 0.2, 0.6, 1.0 } do
				local state = cueOnly(Ball, Simulation, geometry, -25, 0)
				local result = Simulation.run(state, { angle = angle, power = power })
				H.expect(
					not result.capped,
					("shot angle %.1f power %.1f never came to rest"):format(angle, power)
				)
				for _, frame in result.frames do
					local x, y = frame.positions[1], frame.positions[2]
					H.expect(
						TableGeometry.containsCenter(geometry, x, y, R, 1e-3),
						("ball left the table at (%.3f, %.3f) angle %.1f power %.1f"):format(
							x,
							y,
							angle,
							power
						)
					)
				end
				local final = result.finalBalls[1]
				H.expect(final.vx == 0 and final.vy == 0, "final velocity is not zero")
				H.expect(result.duration > 0.5, "the ball stopped suspiciously fast")
			end
		end
	end,

	["energy never increases between steps"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local Cue = H.require("Physics.Cue")
		for _, angle in { 0.15, 0.8, 2.0, 2.9, 4.1 } do
			for _, spin in
				{ { x = 0, y = 0 }, { x = 0.4, y = 0 }, { x = 0, y = 0.4 }, { x = -0.3, y = -0.4 } }
			do
				local state = cueOnly(Ball, Simulation, geometry, -25, 3)
				Cue.strike(state.balls[1], { angle = angle, power = 1, spin = spin })
				local last = Simulation.energy(state)
				stepUntilRest(Config, Simulation, state, function(step)
					local now = Simulation.energy(state)
					H.expect(
						now <= last + 1e-6 * math.max(last, 1),
						("energy rose from %.4f to %.4f at step %d (angle %.2f, spin %.1f/%.1f)"):format(
							last,
							now,
							step,
							angle,
							spin.x,
							spin.y
						)
					)
					last = now
				end)
			end
		end
	end,

	["a rail bounce mirrors the direction and loses speed"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local state = cueOnly(Ball, Simulation, geometry, 0, 0)
		local b = state.balls[1]
		b.vx, b.vy = 150, 0
		b.wy = b.vx / Config.Balls.RadiusInches -- rolling, no side spin
		local bounced = false
		stepUntilRest(Config, Simulation, state, function()
			if not bounced and b.vx < 0 then
				bounced = true
				H.near(b.vy, 0, 1e-6, "straight bounce should stay straight")
				H.expect(-b.vx < 150, "rebound must be slower than approach")
				H.expect(-b.vx > 150 * 0.5, "rebound lost far too much speed")
				H.expect(
					b.x < geometry.halfLength - Config.Balls.RadiusInches + 1e-3,
					"ball is inside the rail"
				)
			end
		end)
		H.expect(bounced, "ball never bounced off the foot rail")
	end,

	["sliding turns into rolling before the ball stops"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = cueOnly(Ball, Simulation, geometry, -40, 0)
		local b = state.balls[1]
		b.vx = 120 -- struck dead centre: no spin at all, so it must slide first
		local u0 = math.abs(b.vx - R * b.wy)
		H.expect(u0 > 1, "test setup: ball should start sliding")
		local rolledWhileMoving = false
		stepUntilRest(Config, Simulation, state, function()
			local u = math.sqrt((b.vx - R * b.wy) ^ 2 + (b.vy + R * b.wx) ^ 2)
			if u < 1e-3 and math.abs(b.vx) > 20 then
				rolledWhileMoving = true
			end
		end)
		H.expect(rolledWhileMoving, "ball never reached pure rolling while still moving")
	end,

	["the same shot always gives the same result"] = function()
		local _, Ball, _, Simulation, geometry = setup()
		local shot = { angle = 0.7, power = 0.9, spin = { x = 0.2, y = -0.3 } }
		local a = Simulation.run(cueOnly(Ball, Simulation, geometry, -25, 0), shot)
		local b = Simulation.run(cueOnly(Ball, Simulation, geometry, -25, 0), shot)
		H.expect(#a.frames == #b.frames, "frame counts differ")
		H.expect(
			a.finalBalls[1].x == b.finalBalls[1].x and a.finalBalls[1].y == b.finalBalls[1].y,
			"final positions differ"
		)
		H.expect(#a.events == #b.events, "event counts differ")
	end,

	["a ball at rest stays exactly at rest"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local state = cueOnly(Ball, Simulation, geometry, 10, -5)
		for _ = 1, 50 do
			Simulation.step(state, Config.Physics.FixedStep, nil)
		end
		local b = state.balls[1]
		H.expect(b.x == 10 and b.y == -5 and not Ball.isMoving(b), "resting ball drifted")
	end,

	["the input state is not modified by run"] = function()
		local _, Ball, _, Simulation, geometry = setup()
		local state = cueOnly(Ball, Simulation, geometry, -25, 0)
		Simulation.run(state, { angle = 0.2, power = 0.5 })
		local b = state.balls[1]
		H.expect(b.x == -25 and b.y == 0 and b.vx == 0, "Simulation.run mutated its input")
	end,
}
