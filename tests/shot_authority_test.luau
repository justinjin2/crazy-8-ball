--!strict
-- The two properties the server's shot path depends on, both of which were broken and are
-- invisible from a single Studio playthrough.
--
-- 1. A client replays from the QUANTISED seed the server puts on the wire. If the server
--    integrates the unrounded strike instead, it computes an answer no client can
--    reproduce, and every shot ends with the balls jumping somewhere else.
-- 2. A pocketed cue ball has to be put back. A state whose cue ball is pocketed cannot be
--    struck again, so without a respot the table is finished for the life of the server.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Simulation = H.require("Physics.Simulation")
	local Rack = H.require("Physics.Rack")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	return Config, Ball, Simulation, Rack, geometry
end

-- Exactly what src/server/ShotService.luau does, including the rounding.
local PLACES = 1e6
local function quantise(v: number): number
	return math.floor(v * PLACES + 0.5) / PLACES
end

return {
	["the server runs the same numbers it sends, so a replay lands where it says"] = function()
		local _, _, Simulation, Rack, geometry = setup()
		local worst, diverged, pocketMismatch = 0, 0, 0
		local shots = 0

		for _, angle in { 0, 0.011, 0.027, -0.019, 0.043 } do
			for _, power in { 0.35, 0.6, 0.85, 1.0 } do
				shots += 1
				local state = Simulation.newState(geometry, Rack.newGame(geometry))
				local shot = { angle = angle, power = power }

				-- The server: strike, round the seed IN PLACE, then run that state.
				local sim = Simulation.cloneState(state)
				local strike = Simulation.strike(sim, shot)
				local cue = Simulation.findBall(sim, 0)
				cue.vx, cue.vy = quantise(cue.vx), quantise(cue.vy)
				cue.wx, cue.wy, cue.wz = quantise(cue.wx), quantise(cue.wy), quantise(cue.wz)
				local seed = { vx = cue.vx, vy = cue.vy, wx = cue.wx, wy = cue.wy, wz = cue.wz }
				local server = Simulation.settle(sim, { strike })

				-- A client: take the seed off the wire and step from it. It never strikes.
				local mine = Simulation.cloneState(state)
				local myCue = Simulation.findBall(mine, 0)
				myCue.vx, myCue.vy = seed.vx, seed.vy
				myCue.wx, myCue.wy, myCue.wz = seed.wx, seed.wy, seed.wz
				mine.time = 0
				local client = Simulation.settle(mine, {})

				for i, b in server.finalBalls do
					local c = client.finalBalls[i]
					local d = math.sqrt((b.x - c.x) ^ 2 + (b.y - c.y) ^ 2)
					worst = math.max(worst, d)
					if d > 0.001 then
						diverged += 1
					end
					if b.pocketed ~= c.pocketed then
						pocketMismatch += 1
					end
				end
				H.expect(
					Simulation.checksum(server.finalBalls) == Simulation.checksum(client.finalBalls),
					("shot %d (angle %.3f power %.2f): client replay does not match the server"):format(
						shots,
						angle,
						power
					)
				)
			end
		end
		H.expect(
			diverged == 0,
			("%d balls ended somewhere else, worst %.4f in"):format(diverged, worst)
		)
		H.expect(
			pocketMismatch == 0,
			("%d balls disagreed about being pocketed"):format(pocketMismatch)
		)
	end,

	["a pocketed cue ball is put back on the head spot"] = function()
		local _, Ball, Simulation, Rack, geometry = setup()
		local TableGeometry = H.require("Physics.Table")
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		local cue = Simulation.findBall(state, 0)

		H.expect(Simulation.respotCueBall(state) == false, "a cue ball on the table is left alone")

		cue.pocketed = true
		cue.falling = true
		cue.pocket = 3
		cue.z = -5
		cue.vx, cue.vy = 40, -12
		H.expect(Simulation.respotCueBall(state) == true, "a pocketed cue ball is respotted")

		local back = Simulation.findBall(state, 0)
		local hx, hy = TableGeometry.headSpot(geometry)
		H.expect(back.pocketed == false, "no longer pocketed")
		H.expect(back.falling == false, "no longer falling")
		H.expect(back.pocket == nil, "no longer owned by a pocket")
		H.near(back.z, 0, 1e-12, "back on the cloth")
		H.near(back.x, hx, 1e-12, "on the head spot, x")
		H.near(back.y, hy, 1e-12, "on the head spot, y")
		H.near(Ball.speed(back), 0, 1e-12, "and stationary")
	end,

	["a scratched table can be struck again"] = function()
		local _, _, Simulation, Rack, geometry = setup()
		local state = Simulation.newState(geometry, Rack.newGame(geometry))

		-- Pot the cue ball the way a scratch does.
		local cue = Simulation.findBall(state, 0)
		cue.pocketed = true
		cue.falling = false
		cue.z = -5

		-- Without a respot this is what the server hits on the very next shot.
		local ok = pcall(function()
			Simulation.strike(Simulation.cloneState(state), { angle = 0, power = 0.5 })
		end)
		H.expect(ok == false, "striking a state with no cue ball must fail loudly")

		-- With one, the table carries on.
		Simulation.respotCueBall(state)
		local after = pcall(function()
			local sim = Simulation.cloneState(state)
			local strike = Simulation.strike(sim, { angle = 0, power = 0.5 })
			return Simulation.settle(sim, { strike })
		end)
		H.expect(after == true, "after a respot the next shot runs")
	end,
}
