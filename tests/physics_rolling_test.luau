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

	["side spin winds down in 1322 steps at either radius without keeping the shot busy"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local dt = Config.Physics.FixedStep
		local oldRadius = Config.Balls.RadiusInches
		-- Always restore shared Config, including when an assertion fails.
		local ok, err = pcall(function()
			for _, radius in { 1.125, 1.3 } do
				Config.Balls.RadiusInches = radius
				for _, sign in { -1, 1 } do
					local state = cueOnly(Ball, Simulation, geometry, 0, 0)
					local b = state.balls[1]
					b.wz = sign * 60
					H.expect(not Ball.isMoving(b), "side spin alone does not keep a shot busy")
					H.expect(
						Simulation.isAtRest(state),
						"pure side spin is at rest for shot timing"
					)
					H.expect(b.wz == sign * 60, "checking rest must not erase physical spin")
					-- Keep integrating explicitly: other balls may still be moving even when
					-- this one only spins. 60/10.9 = 5.5046 s, rounded up at 240 Hz.
					for step = 1, 1322 do
						Simulation.step(state, dt, nil)
						local expected = sign * math.max(60 - 10.9 * step * dt, 0)
						H.near(
							b.wz,
							expected,
							1e-9,
							"side spin follows constant angular deceleration"
						)
						if step < 1322 then
							H.expect(b.wz * sign > 0, "spin must not snap to zero before step 1322")
						end
					end
					H.expect(b.wz == 0, "side spin reaches exactly zero on step 1322")
					H.expect(b.x == 0 and b.y == 0, "side spin alone never moves the centre")
				end
			end
		end)
		Config.Balls.RadiusInches = oldRadius
		if not ok then
			error(err)
		end
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

	["the checksum matches for the same shot and differs for a different one"] = function()
		local _, Ball, _, Simulation, geometry = setup()
		local Rack = H.require("Physics.Rack")
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		local a = Simulation.runHeadless(state, { angle = 0.03, power = 0.9 })
		local b = Simulation.runHeadless(state, { angle = 0.03, power = 0.9 })
		local c = Simulation.runHeadless(state, { angle = 0.031, power = 0.9 })
		-- This is what the server and every client compare after a shot: same inputs, same
		-- fingerprint, or somebody has diverged.
		H.expect(
			Simulation.checksum(a.finalBalls) == Simulation.checksum(b.finalBalls),
			"the same shot must fingerprint the same"
		)
		H.expect(
			Simulation.checksum(a.finalBalls) ~= Simulation.checksum(c.finalBalls),
			"a different shot must fingerprint differently"
		)
		-- A hair of noise below the quantisation must not change it; a real move must.
		local nudged = Ball.cloneList(a.finalBalls)
		nudged[1].x += 1e-6
		H.expect(
			Simulation.checksum(nudged) == Simulation.checksum(a.finalBalls),
			"float noise must not trip the check"
		)
		nudged[1].x += 0.5
		H.expect(
			Simulation.checksum(nudged) ~= Simulation.checksum(a.finalBalls),
			"a ball half an inch out must trip it"
		)
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
