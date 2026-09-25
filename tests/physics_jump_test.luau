--!strict
-- Jump shots (Physics/Flight.luau): balls in the air, the slate bounce, clearing a ball,
-- flying off the table, and the designer's rule that ordinary shots almost never leave the
-- cloth (2026-09-24).

local H = require("./harness")

local function setup()
	return H.require("Config"),
		H.require("Physics.Ball"),
		H.require("Physics.Table"),
		H.require("Physics.Simulation"),
		H.require("Physics.Cue")
end

local function events(result, kind: string, id: number?): { any }
	local out = {}
	for _, ev in result.events do
		if ev.type == kind and (id == nil or ev.ball == id) then
			table.insert(out, ev)
		end
	end
	return out
end

-- Cue ball at -30, a blocking ball 12 in ahead, the target 30 in ahead, all on the long axis.
local function jumpLayout(Ball, Simulation, geometry)
	return Simulation.newState(
		geometry,
		{ Ball.new(0, -30, 0), Ball.new(1, -18, 0), Ball.new(2, 0, 0) }
	)
end

return {
	["a ball in the air flies a parabola and lands where gravity says"] = function()
		local Config, Ball, TableGeometry, Simulation = setup()
		local g = Config.Physics.Gravity
		local geometry = TableGeometry.build({ pocketsOpen = false })
		local b = Ball.new(0, -20, 0)
		b.vx, b.vz = 30, 40
		b.wy = b.vx / Config.Balls.RadiusInches -- rolling spin, so the landing does not skid
		local state = Simulation.newState(geometry, { b })
		local peak = 0
		local landed: number? = nil
		local log = {}
		while landed == nil and state.time < 1 do
			Simulation.step(state, Config.Physics.FixedStep, log)
			peak = math.max(peak, b.z)
			for _, ev in log do
				if ev.type == "land" then
					landed = ev.t
				end
			end
		end
		H.near(peak, 40 * 40 / (2 * g), 0.01, "peak height")
		H.near(landed or -1, 2 * 40 / g, 1e-9, "flight time")
		H.near(
			events({ events = log }, "land")[1].speed,
			40,
			1e-6,
			"comes down as fast as it went up"
		)
	end,

	["bounces lose height each time and the ball settles on the cloth"] = function()
		local Config, Ball, TableGeometry, Simulation = setup()
		local geometry = TableGeometry.build({ pocketsOpen = false })
		local state = Simulation.newState(geometry, { Ball.new(0, 0, 0) })
		state.balls[1].z = 10
		local log = {}
		local steps = 0
		while not Simulation.isAtRest(state) and steps < 2400 do
			Simulation.step(state, Config.Physics.FixedStep, log)
			steps += 1
		end
		local lands = events({ events = log }, "land")
		H.expect(#lands >= 2, "a 10 in drop bounces at least once")
		for i = 2, #lands do
			H.expect(lands[i].speed < lands[i - 1].speed, "each bounce is lower")
		end
		local final = state.balls[1]
		H.expect(final.z == 0 and final.vz == 0 and Simulation.isAtRest(state), "settled")
	end,

	["a raised cue jumps the cue ball over a blocking ball onto the one behind"] = function()
		local _, Ball, TableGeometry, Simulation = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local state = jumpLayout(Ball, Simulation, geometry)
		local result = Simulation.run(state, { angle = 0, power = 0.65, elevation = 45 })
		H.expect(result.firstContact == 2, "cleared the 1 and hit the 2 first")
		H.expect(#events(result, "offTable") == 0, "nothing left the table")
		local blocker = Simulation.findBall({ balls = result.finalBalls } :: any, 1)
		H.expect(blocker and blocker.x == -18 and blocker.y == 0, "the blocker was never touched")
		-- The same shot at the default angle just hits the blocker.
		local flat = Simulation.run(state, { angle = 0, power = 0.65 })
		H.expect(flat.firstContact == 1, "a level cue hits the blocker")
	end,

	["a steep hard shot sends the cue ball off the table"] = function()
		local _, Ball, TableGeometry, Simulation = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local state = jumpLayout(Ball, Simulation, geometry)
		local result = Simulation.run(state, { angle = 0, power = 1, elevation = 60 })
		local off = events(result, "offTable", 0)
		H.expect(#off == 1, "one offTable event for the cue ball")
		local cue = result.finalBalls[1]
		H.expect(cue.offTable and cue.pocketed and cue.pocket == nil, "out of play, in no pocket")
		H.expect(#events(result, "pocket", 0) == 0, "not counted as a pocket")
		H.expect(not result.capped and Simulation.isAtRest({
			geometry = geometry,
			balls = result.finalBalls,
			time = 0,
		} :: any), "the shot ends")
	end,

	["a ball coming down over an opening drops into the pocket"] = function()
		local Config, Ball, TableGeometry, Simulation = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local pocket = geometry.pockets[1]
		local b = Ball.new(3, pocket.x, pocket.y)
		b.z = 3
		local state = Simulation.newState(geometry, { Ball.new(0, 0, 0), b })
		local log = {}
		for _ = 1, 480 do
			Simulation.step(state, Config.Physics.FixedStep, log)
		end
		H.expect(b.pocketed and not b.offTable and b.pocket == pocket.id, "pocketed")
		H.expect(#events({ events = log }, "pocket", 3) == 1, "one pocket event")
	end,

	["an ordinary shot never leaves the cloth"] = function()
		local Config, Ball, _, _, Cue = setup()
		for _, power in { 0.1, 0.3, 0.5, 0.7, 0.85 } do
			for _, spin in { { 0, 0 }, { 0.5, 0 }, { 0, 0.5 }, { 0, -0.5 }, { -0.35, 0.35 } } do
				local b = Ball.new(0, 0, 0)
				Cue.strike(b, { angle = 1.3, power = power, spin = { x = spin[1], y = spin[2] } })
				H.expect(b.vz == 0 and b.z == 0, ("power %.2f stays down"):format(power))
			end
		end
		-- The very top of the bar hops a whisker: well under a tenth of an inch.
		local b = Ball.new(0, 0, 0)
		Cue.strike(b, { angle = 0, power = 1 })
		local hop = b.vz * b.vz / (2 * Config.Physics.Gravity)
		H.expect(b.vz > 0 and hop < 0.1, ("full power hops %.3f in"):format(hop))
	end,

	["a raised cue at low power stays down and keeps the level-cue spin"] = function()
		local Config, Ball, _, _, Cue = setup()
		local level, raised = Ball.new(0, 0, 0), Ball.new(0, 0, 0)
		Cue.strike(level, { angle = 0, power = 0.2, spin = { x = 0, y = 0.3 } })
		Cue.strike(raised, { angle = 0, power = 0.2, spin = { x = 0, y = 0.3 }, elevation = 30 })
		H.expect(raised.vz == 0, "too soft to jump")
		H.expect(
			math.sign(raised.wy) == math.sign(level.wy),
			"top spin stays top spin with the butt raised"
		)
		H.expect(raised.vx < level.vx, "a raised cue drives less of the stroke forward")
		H.expect(Config.Cue.MaxElevationDegrees >= 45, "the slider reaches jump angles")
	end,

	["object balls never leave the cloth, even when a jumping ball lands on them"] = function()
		local Config, Ball, TableGeometry, Simulation = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		for _, power in { 0.55, 0.6, 0.7, 0.8 } do
			for _, elevation in { 30, 45, 60 } do
				local state = jumpLayout(Ball, Simulation, geometry)
				local result =
					Simulation.run(state, { angle = 0, power = power, elevation = elevation })
				for _, frame in result.frames do
					for i = 2, #state.balls do
						H.expect(frame.positions[3 * i] <= 0, "object ball in the air")
					end
				end
				for _, ev in result.events do
					H.expect(ev.type ~= "offTable" or ev.ball == 0, "only the cue ball flies off")
				end
			end
		end
		H.expect(Config.Physics.ClothHopLossSpeed > 0)
	end,

	["jump shots never gain energy and replay exactly"] = function()
		local Config, Ball, TableGeometry, Simulation = setup()
		local ShotInput = H.require("ShotInput")
		local geometry = TableGeometry.build({ pocketsOpen = true })
		for _, shot in
			{
				{ angle = 0, power = 0.65, elevation = 45 },
				{ angle = 0.2, power = 0.8, elevation = 60, spin = { x = 0.3, y = -0.2 } },
				{ angle = -0.1, power = 1 },
			}
		do
			local state = jumpLayout(Ball, Simulation, geometry)
			local sim = Simulation.cloneState(state)
			local strike = Simulation.strike(sim, shot)
			local seed = ShotInput.quantiseSeed(Simulation.findBall(sim, 0) :: any)
			local before = Simulation.energy(sim)
			local steps = 0
			while not Simulation.isAtRest(sim) and steps < 4000 do
				Simulation.step(sim, Config.Physics.FixedStep)
				local now = Simulation.energy(sim)
				H.expect(now <= before + 1e-6, ("energy rose by %.6f"):format(now - before))
				before = now
				steps += 1
			end
			local server = Simulation.settle(Simulation.cloneState(sim), { strike })
			-- A client starts from the wire seed and steps; it must land on the same checksum.
			local mine = Simulation.cloneState(state)
			local cue = Simulation.findBall(mine, 0) :: any
			cue.vx, cue.vy, cue.vz = seed.vx, seed.vy, seed.vz
			cue.wx, cue.wy, cue.wz = seed.wx, seed.wy, seed.wz
			local client = Simulation.settle(mine, {})
			H.expect(
				Simulation.checksum(server.finalBalls) == Simulation.checksum(client.finalBalls),
				"client replay matches"
			)
		end
	end,

	["hard flat shots rarely pop the cue ball off the table"] = function()
		local _, _, TableGeometry, Simulation = setup()
		local Rack = H.require("Physics.Rack")
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local shots, off, objectAir = 0, 0, 0
		for seed = 1, 12 do
			local broke = Simulation.runHeadless(
				Simulation.newState(geometry, Rack.newGame(geometry, seed)),
				{ angle = 0, power = 0.6 }
			)
			local after = Simulation.newState(geometry, broke.finalBalls)
			local cue = Simulation.findBall(after, 0)
			if cue == nil or cue.pocketed then
				continue
			end
			-- Full power straight at the nearest three balls: the likeliest way to pop it.
			local targets = {}
			for _, b in after.balls do
				if b.id ~= 0 and not b.pocketed then
					table.insert(targets, { b = b, d = (b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2 })
				end
			end
			table.sort(targets, function(a, b)
				return a.d < b.d
			end)
			for k = 1, math.min(3, #targets) do
				local t = targets[k].b
				local result = Simulation.runHeadless(
					after,
					{ angle = math.atan2(t.y - cue.y, t.x - cue.x), power = 1 }
				)
				shots += 1
				for _, b in result.finalBalls do
					if b.offTable then
						if b.id == 0 then
							off += 1
						else
							objectAir += 1
						end
					end
				end
			end
		end
		H.expect(objectAir == 0, "object balls never fly off")
		H.expect(
			off <= math.ceil(shots * 0.1),
			("%d of %d full-power flat shots sent the cue ball off"):format(off, shots)
		)
	end,
}
