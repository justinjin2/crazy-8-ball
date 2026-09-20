--!strict
local H = require("./harness")

local function run()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Rack = H.require("Physics.Rack")
	local Simulation = H.require("Physics.Simulation")
	local geometry = TableGeometry.build({ pocketsOpen = true })

	local SEED_PLACES = 1e6
	local function quantise(v: number): number
		return math.floor(v * SEED_PLACES + 0.5) / SEED_PLACES
	end

	local worst, worstShot = 0, ""
	local mismatches, diverged, total = 0, 0, 0
	local P = Config.Physics
	for i = 0, 40 do
		local angle = -0.09 + i * 0.0045
		for _, power in { 1.0, 0.85, 0.6 } do
			total += 1
			local shot = { angle = angle, power = power }
			-- server
			local state = Simulation.newState(geometry, Rack.newGame(geometry))
			local seedState = Simulation.cloneState(state)
			Simulation.strike(seedState, shot)
			local cue = Simulation.findBall(seedState, 0)
			local seed = {
				vx = quantise(cue.vx), vy = quantise(cue.vy),
				wx = quantise(cue.wx), wy = quantise(cue.wy), wz = quantise(cue.wz),
			}
			local outcome = Simulation.runHeadless(state, shot)

			-- client: replay from the quantised seed
			local c = Simulation.newState(geometry, Rack.newGame(geometry))
			local ccue = Simulation.findBall(c, 0)
			ccue.vx, ccue.vy = seed.vx, seed.vy
			ccue.wx, ccue.wy, ccue.wz = seed.wx, seed.wy, seed.wz
			c.time = 0
			local steps, maxSteps = 0, math.floor(P.MaxShotSeconds / P.FixedStep)
			while not Simulation.isAtRest(c) and steps < maxSteps do
				Simulation.step(c, P.FixedStep, nil)
				steps += 1
			end

			local d = 0
			local pocketDiff = false
			for j, b in c.balls do
				local s = outcome.finalBalls[j]
				local dx, dy = b.x - s.x, b.y - s.y
				d = math.max(d, math.sqrt(dx * dx + dy * dy))
				if b.pocketed ~= s.pocketed then
					pocketDiff = true
				end
			end
			if d > 0.001 then
				diverged += 1
			end
			if pocketDiff then
				mismatches += 1
			end
			if d > worst then
				worst = d
				worstShot = ("angle %.4f power %.2f"):format(angle, power)
			end
		end
	end
	print(("seed-drift: %d shots, %d diverged >0.001in, %d pocket mismatches, worst %.4f in (%s)")
		:format(total, diverged, mismatches, worst, worstShot))
end

return { seed_drift = run }
