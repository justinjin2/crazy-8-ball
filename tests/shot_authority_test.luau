--!strict
-- Shot authority: validate exactly the inputs the server uses, then replay its quantised
-- spin seed and per-shot material. A scratched cue ball must also be playable again.
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

return {
	["shot validation rejects malformed and nonfinite requests before physics"] = function()
		local Config = H.require("Config")
		local ShotInput = H.require("ShotInput")
		local function rejected(payload, label: string)
			local shot, reason = ShotInput.validate(payload)
			H.expect(shot == nil and reason ~= nil, label .. " must be rejected")
		end
		rejected(nil, "missing payload")
		rejected(false, "boolean payload")
		rejected({}, "missing shot values")
		for _, field in { "angle", "power", "elevation" } do
			for _, value in { 0 / 0, math.huge, -math.huge, "0.5", false, {} } do
				local payload = { angle = 0, power = 0.5 }
				payload[field] = value
				rejected(payload, field .. " value " .. tostring(value))
			end
		end
		for _, value in { Config.Input.MinPowerToShoot - 0.001, 1.001 } do
			rejected({ angle = 0, power = value }, "power outside allowed range")
		end
		for _, spin in
			{
				false,
				1,
				"spin",
				{},
				{ x = 0 },
				{ y = 0 },
				{ x = 0, y = 0 / 0 },
				{ x = math.huge, y = 0 },
				{ x = 0, y = -math.huge },
			}
		do
			rejected({ angle = 0, power = 0.5, spin = spin }, "malformed spin")
		end
		rejected({ angle = 0, power = 0.5, elevation = 0 }, "elevation below the default")
		rejected(
			{ angle = 0, power = 0.5, elevation = Config.Cue.MaxElevationDegrees + 0.5 },
			"elevation above the maximum"
		)
		rejected({ angle = 0, power = 0.5, overrides = {} }, "even empty forged material")
		rejected(
			{ angle = 0, power = 0.5, overrides = { RailRestitution = 1, RailFriction = 0 } },
			"forged material values"
		)
		for _, value in { math.huge, -math.huge, 0 / 0, "1" } do
			H.expect(not ShotInput.isFinite(value), "the server's table-id finite guard")
		end
	end,

	["validated shots normalize angle clamp the spin disc and round elevation"] = function()
		local Config = H.require("Config")
		local ShotInput = H.require("ShotInput")
		local payload =
			{ angle = -math.pi, power = Config.Input.MinPowerToShoot, spin = { x = 3, y = -4 } }
		local shot = ShotInput.validate(payload)
		H.expect(shot ~= nil, "finite shot accepted")
		H.near(shot.angle, math.pi, 1e-12, "normalized angle")
		H.near(shot.spin.x, 0.3, 1e-12, "clamped side")
		H.near(shot.spin.y, -0.4, 1e-12, "clamped draw")
		H.expect(shot.elevation == Config.Cue.CueElevationDegrees, "default elevation")
		local raised = ShotInput.validate({ angle = 0, power = 0.5, elevation = 44.6 })
		H.expect(raised ~= nil and raised.elevation == 45, "elevation rounds to a whole step")
		local top = ShotInput.validate({
			angle = 0,
			power = 0.5,
			elevation = Config.Cue.MaxElevationDegrees,
		})
		H.expect(top.elevation == Config.Cue.MaxElevationDegrees, "maximum elevation accepted")
		H.expect(
			payload.spin.x == 3 and payload.spin.y == -4,
			"validation does not mutate the request"
		)
		local default = ShotInput.validate({ angle = 0, power = 1 })
		H.expect(default.spin.x == 0 and default.spin.y == 0, "legacy payload defaults to centre")
		local huge = ShotInput.validate({
			angle = 1e308,
			power = 0.5,
			spin = { x = 1e308, y = -1e308 },
			elevation = Config.Cue.CueElevationDegrees,
		})
		H.expect(huge ~= nil and ShotInput.isFinite(huge.angle), "finite huge angle normalizes")
		H.near(
			huge.spin.x,
			Config.Cue.MaxSpinOffset / math.sqrt(2),
			1e-12,
			"huge finite spin retains direction"
		)
		H.near(huge.spin.y, -huge.spin.x, 1e-12, "huge finite spin remains symmetric")
	end,

	["ability ids need external server authorization and a known material"] = function()
		local ShotInput = H.require("ShotInput")
		local payload = { angle = 0, power = 0.5, ability = "SuperBounce" }
		H.expect(ShotInput.validate(payload) == nil, "production has no authorized abilities yet")
		H.expect(
			ShotInput.validate(payload, "OtherAbility") == nil,
			"a different authorization cannot be used"
		)
		local valid = ShotInput.validate(payload, "SuperBounce")
		H.expect(
			valid ~= nil and valid.ability == "SuperBounce",
			"explicit development authorization"
		)
		H.expect(
			ShotInput.validate({ angle = 0, power = 0.5, ability = "Unknown" }, "Unknown") == nil,
			"unknown catalog id"
		)
		H.expect(
			ShotInput.validate(
				{ angle = 0, power = 0.5, ability = { RailRestitution = 1 } },
				"SuperBounce"
			) == nil,
			"ability cannot carry arbitrary coefficients"
		)
	end,

	["the server runs the same numbers it sends, so a replay lands where it says"] = function()
		local _, _, Simulation, Rack, geometry = setup()
		local ShotInput = H.require("ShotInput")
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
				local seed = ShotInput.quantiseSeed(cue)
				local server = Simulation.settle(sim, { strike })

				-- A client: take the seed off the wire and step from it. It never strikes.
				local mine = Simulation.cloneState(state)
				local myCue = Simulation.findBall(mine, 0)
				myCue.vx, myCue.vy, myCue.vz = seed.vx, seed.vy, seed.vz
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

	["the three requested spins survive validation quantization and exact replay"] = function()
		local Config, _, Simulation, Rack, geometry = setup()
		local ShotInput = H.require("ShotInput")
		for _, spin in { { x = 0.5, y = 0 }, { x = 0, y = 0.45 }, { x = -0.3, y = -0.4 } } do
			local shot = ShotInput.validate({
				angle = 0.027,
				power = 0.6,
				spin = spin,
				elevation = Config.Cue.CueElevationDegrees,
			})
			H.expect(shot ~= nil, "spin request accepted")
			H.near(shot.spin.x, spin.x, 1e-12, "side survives validation")
			H.near(shot.spin.y, spin.y, 1e-12, "vertical survives validation")
			local state = Simulation.newState(geometry, Rack.newGame(geometry))
			local sim = Simulation.cloneState(state)
			local strike = Simulation.strike(sim, shot)
			local cue = Simulation.findBall(sim, 0)
			local before =
				{ vx = cue.vx, vy = cue.vy, vz = cue.vz, wx = cue.wx, wy = cue.wy, wz = cue.wz }
			local seed = ShotInput.quantiseSeed(cue)
			for _, field in { "vx", "vy", "vz", "wx", "wy", "wz" } do
				H.near(
					seed[field],
					before[field],
					0.5 / Config.Physics.SeedPlaces + 1e-12,
					"seed precision " .. field
				)
				H.expect(seed[field] == cue[field], "server integrates the transmitted " .. field)
			end
			H.expect(
				math.abs(seed.wx) + math.abs(seed.wy) + math.abs(seed.wz) > 0,
				"nonzero seed spin"
			)
			local server = Simulation.settle(sim, { strike })
			local clientState = Simulation.cloneState(state)
			local clientCue = Simulation.findBall(clientState, 0)
			clientCue.vx, clientCue.vy, clientCue.vz = seed.vx, seed.vy, seed.vz
			clientCue.wx, clientCue.wy, clientCue.wz = seed.wx, seed.wy, seed.wz
			local client = Simulation.settle(clientState, {})
			H.expect(
				Simulation.checksum(server.finalBalls) == Simulation.checksum(client.finalBalls),
				"spin replay checksum"
			)
			for i, ball in server.finalBalls do
				local other = client.finalBalls[i]
				H.expect(
					ball.x == other.x
						and ball.y == other.y
						and ball.z == other.z
						and ball.pocketed == other.pocketed,
					"same-machine spin replay is bit-identical"
				)
			end
		end
	end,

	["authorized shot materials replay exactly and clear before the next shot"] = function()
		local Config, Ball, Simulation = setup()
		local ShotInput = H.require("ShotInput")
		local geometry = H.require("Physics.Table").build({ pocketsOpen = false })
		local state = Simulation.newState(geometry, { Ball.new(0, -20, -5) })
		local shot = ShotInput.validate(
			{ angle = 0.25, power = 0.6, spin = { x = 0.3, y = 0.4 }, ability = "SuperBounce" },
			"SuperBounce"
		)
		local sim = Simulation.cloneState(state)
		local strike = Simulation.strike(sim, shot)
		H.expect(
			sim.overrides.RailRestitution == 1 and sim.overrides.RailFriction == 0,
			"catalog material installed"
		)
		H.expect(
			sim.overrides ~= Config.Physics.ShotMaterials.SuperBounce,
			"shot owns a copy of catalog data"
		)
		local clone = Simulation.cloneState(sim)
		H.expect(
			clone.overrides ~= sim.overrides and clone.overrides.RailFriction == 0,
			"clone owns its material copy"
		)
		local seed = ShotInput.quantiseSeed(Simulation.findBall(sim, 0))
		local server = Simulation.settle(sim, { strike })
		H.expect(sim.overrides == nil, "settle clears live material")
		H.expect(
			server.overrides.RailRestitution == 1 and server.overrides.RailFriction == 0,
			"outcome retains replay material"
		)
		local clientState = Simulation.cloneState(state)
		clientState.overrides = table.clone(server.overrides)
		local clientCue = Simulation.findBall(clientState, 0)
		clientCue.vx, clientCue.vy, clientCue.vz = seed.vx, seed.vy, seed.vz
		clientCue.wx, clientCue.wy, clientCue.wz = seed.wx, seed.wy, seed.wz
		local client = Simulation.settle(clientState, {})
		H.expect(
			Simulation.checksum(server.finalBalls) == Simulation.checksum(client.finalBalls),
			"material replay checksum"
		)
		local final, replayed = server.finalBalls[1], client.finalBalls[1]
		H.expect(
			final.x == replayed.x
				and final.y == replayed.y
				and final.z == replayed.z
				and server.duration == client.duration,
			"material replay is bit-identical on this machine"
		)
		H.expect(clientState.overrides == nil, "client settle clears material")
		local ordinary = Simulation.runHeadless(
			state,
			{ angle = 0.25, power = 0.6, spin = { x = 0.3, y = 0.4 } }
		)
		H.expect(
			Simulation.checksum(server.finalBalls) ~= Simulation.checksum(ordinary.finalBalls),
			"material changes the rail result"
		)
		-- Also clear a stale override at strike time, even if a prior replay was interrupted.
		sim.overrides = table.clone(server.overrides)
		Simulation.strike(sim, { angle = 0.5, power = 0.3 })
		H.expect(sim.overrides == nil, "ordinary next shot resets previous material")
		local nextShot = Simulation.settle(sim)
		H.expect(nextShot.overrides == nil, "next outcome has no previous material")
		local recorded = Simulation.run(state, shot)
		H.expect(recorded.overrides.RailRestitution == 1, "frame-recorded runs retain material too")
		H.expect(state.overrides == nil, "run leaves its input unchanged")
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
