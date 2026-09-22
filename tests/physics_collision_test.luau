--!strict
-- Milestone 2 physics tests: ball-ball collisions, pockets, the rack and the break.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Simulation = H.require("Physics.Simulation")
	local Rack = H.require("Physics.Rack")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	return Config, Ball, TableGeometry, Simulation, Rack, geometry
end

-- Remove cloth impulses only while measuring a single ball contact. Restore every shared
-- setting even when a benchmark fails, so later suites still exercise the real table.
local function withoutCloth(Config, callback: () -> ())
	local P = Config.Physics
	local sliding, rolling, spin = P.SlidingFriction, P.RollingFriction, P.SideSpinDecel
	local rest, epsilon, friction = P.RestSpeed, P.SlideEpsilon, P.BallFrictionTable
	P.SlidingFriction, P.RollingFriction, P.SideSpinDecel = 0, 0, 0
	P.RestSpeed, P.SlideEpsilon = 0, 0
	local ok, err = pcall(callback)
	P.SlidingFriction, P.RollingFriction, P.SideSpinDecel = sliding, rolling, spin
	P.RestSpeed, P.SlideEpsilon, P.BallFrictionTable = rest, epsilon, friction
	if not ok then
		error(err)
	end
end

local function contactPair(Ball, Simulation, geometry, radius: number, angle: number)
	local a = Ball.new(0, 0, 0)
	-- A negligible overlap guarantees a zero-time hit despite trig rounding; pushOut
	-- restores the separation before the public step resolves the collision.
	local separation = 2 * radius - 1e-8
	local b = Ball.new(1, separation * math.cos(angle), separation * math.sin(angle))
	return Simulation.newState(geometry, { a, b }), a, b
end

local function collide(Simulation, state): number
	local events = {}
	Simulation.step(state, 1e-7, events)
	H.expect(#events == 1 and events[1].type == "ballHit", "expected one isolated ball contact")
	return events[1].speed
end

local function minSeparation(positions: { number }, pocketedFlags: { boolean }): number
	local n = #positions / 3
	local best = math.huge
	for i = 1, n do
		if pocketedFlags[i] then
			continue
		end
		for j = i + 1, n do
			if pocketedFlags[j] then
				continue
			end
			local dx = positions[3 * i - 2] - positions[3 * j - 2]
			local dy = positions[3 * i - 1] - positions[3 * j - 1]
			local d = math.sqrt(dx * dx + dy * dy)
			if d < best then
				best = d
			end
		end
	end
	return best
end

local function runBreak(Ball, Simulation, Rack, geometry, angle: number)
	local state = Simulation.newState(geometry, Rack.newGame(geometry))
	local stop = Ball.stop
	local forcedStops = 0
	Ball.stop = function(ball)
		if not ball.pocketed then
			forcedStops += 1
		end
		stop(ball)
	end
	local ok, result = pcall(Simulation.run, state, { angle = angle, power = 1 })
	Ball.stop = stop
	if not ok then
		error(result)
	end
	H.expect(forcedStops == 0, "break used a wedge, event-budget or shot-duration stop")
	return state, result
end

-- Pocketed balls jump to their pocket, so exclude them from separation checks by tracking
-- pocket events in time order.
local function pocketedByFrame(result, ballCount: number): { { boolean } }
	local flags = table.create(ballCount, false)
	local out = {}
	local eventIndex = 1
	for f, frame in result.frames do
		while eventIndex <= #result.events and result.events[eventIndex].t <= frame.t do
			local ev = result.events[eventIndex]
			if ev.type == "pocket" then
				flags[ev.ball + 1] = true
			end
			eventIndex += 1
		end
		out[f] = table.clone(flags)
	end
	return out
end

return {
	["a 100 in/s full hit preserves the measured 0.95 restitution"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			local state, cue, object =
				contactPair(Ball, Simulation, geometry, Config.Balls.RadiusInches, 0)
			cue.vx = 100
			H.near(collide(Simulation, state), 100, 1e-9, "event reports incoming normal speed")
			H.near(cue.vx, 2.5, 1e-9, "cue residual speed")
			H.near(object.vx, 97.5, 1e-9, "object speed")
			H.near(cue.wz + object.wz, 0, 1e-9, "a full stun hit creates no side spin")
		end)
	end,

	["a half-ball stun cut throws according to the configured contact friction"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			local function shoot(): number
				local state, cue, object =
					contactPair(Ball, Simulation, geometry, Config.Balls.RadiusInches, math.rad(30))
				cue.vx = 40
				H.near(collide(Simulation, state), 20 * math.sqrt(3), 1e-9, "normal contact speed")
				H.expect(
					cue.wz > 0 and object.wz > 0,
					"friction gives both balls the same side-spin sign"
				)
				return math.deg(math.atan2(object.vy, object.vx))
			end
			-- The speed-dependent table gives mu(20)=0.072. The research's 26.57-degree
			-- benchmark instead assumes constant mu=0.06; keep both known answers.
			H.near(shoot(), 25.881810296, 1e-7, "measured friction table throw")
			Config.Physics.BallFrictionTable = {
				{ Speed = 0, Friction = 0.06 },
				{ Speed = 200, Friction = 0.06 },
			}
			H.near(shoot(), 26.566369638, 1e-7, "constant 0.06 reference throw")
		end)
	end,

	["contact friction interpolates by slip speed and clamps beyond the table"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			for _, sample in
				{
					{ 10, 0.095 },
					{ 20, 0.072 },
					{ 60, 0.034 },
					{ 160, 0.012 },
					{ 200, 0.010 },
					{ 240, 0.010 },
				}
			do
				local state, cue, object =
					contactPair(Ball, Simulation, geometry, Config.Balls.RadiusInches, 0)
				cue.vx, cue.vy = 10, sample[1]
				collide(Simulation, state)
				H.near(
					object.vy / object.vx,
					sample[2],
					1e-9,
					"throw tangent equals interpolated mu"
				)
			end
		end)
	end,

	["gearing outside english removes half-ball throw"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			local R = Config.Balls.RadiusInches
			local state, cue, object = contactPair(Ball, Simulation, geometry, R, math.rad(30))
			cue.vx, cue.wz = 40, 20 / R
			collide(Simulation, state)
			H.near(math.deg(math.atan2(object.vy, object.vx)), 30, 1e-9, "gearing object direction")
			H.near(cue.wz, 20 / R, 1e-9, "no tangential impulse on the cue")
			H.near(object.wz, 0, 1e-9, "no spin transferred without contact slip")
		end)
	end,

	["a full hit transfers backspin with the five-fourteenths sticking limit"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			local R = Config.Balls.RadiusInches
			for _, incomingSpin in { 100 / R, 1 / R } do
				local state, cue, object = contactPair(Ball, Simulation, geometry, R, 0)
				cue.vx, cue.wy = 100, incomingSpin
				collide(Simulation, state)
				H.expect(object.wy < 0, "forward cue spin must transfer object backspin")
				H.expect(-object.wy <= 5 / 14 * incomingSpin + 1e-9, "spin transfer exceeds 5/14")
				H.near(
					cue.wy - incomingSpin,
					object.wy,
					1e-9,
					"both balls receive equal angular impulses"
				)
				H.expect(cue.vz == 0 and object.vz == 0, "contact preserves planar translation")
				if incomingSpin == 1 / R then
					H.near(object.wy, -5 / (14 * R), 1e-9, "low slip reaches the sticking cap")
				end
			end
		end)
	end,

	["20000 deterministic contact pairs dissipate energy without reversing slip"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		withoutCloth(Config, function()
			local R = Config.Balls.RadiusInches
			local seed = 872341
			local function random(): number
				seed = (seed * 48271) % 2147483647
				return seed / 2147483647
			end
			for index = 1, 20000 do
				local angle = 2 * math.pi * random()
				local nx, ny = math.cos(angle), math.sin(angle)
				local tx, ty = -ny, nx
				local state, a, b = contactPair(Ball, Simulation, geometry, R, angle)
				local scale = if index % 3 == 0 then 0.01 elseif index % 3 == 1 then 10 else 528
				local normal, tangent = scale * (0.01 + random()), scale * (2 * random() - 1)
				local mx, my = scale * (random() - 0.5), scale * (random() - 0.5)
				a.vx, a.vy =
					mx + (normal * nx + tangent * tx) / 2, my + (normal * ny + tangent * ty) / 2
				b.vx, b.vy =
					mx - (normal * nx + tangent * tx) / 2, my - (normal * ny + tangent * ty) / 2
				for _, ball in { a, b } do
					ball.wx, ball.wy, ball.wz =
						scale * (2 * random() - 1) / R,
						scale * (2 * random() - 1) / R,
						scale * (2 * random() - 1) / R
				end
				local beforeA, beforeB = Ball.clone(a), Ball.clone(b)
				local beforeEnergy = Simulation.energy(state)
				local beforeT = tangent + R * (a.wz + b.wz)
				local beforeZ = R * ((a.wx + b.wx) * ny - (a.wy + b.wy) * nx)
				H.near(collide(Simulation, state), normal, 1e-8, "incoming contact speed")
				local energy = Simulation.energy(state)
				H.expect(
					energy <= beforeEnergy + 1e-9 * math.max(beforeEnergy, 1),
					("energy rose on pair %d"):format(index)
				)
				H.near(a.vx + b.vx, 2 * mx, 1e-8, "x momentum")
				H.near(a.vy + b.vy, 2 * my, 1e-8, "y momentum")
				H.near(
					(a.vx - b.vx) * nx + (a.vy - b.vy) * ny,
					-0.95 * normal,
					1e-8,
					"normal restitution"
				)
				local dwx, dwy, dwz = a.wx - beforeA.wx, a.wy - beforeA.wy, a.wz - beforeA.wz
				H.near(dwx, b.wx - beforeB.wx, 1e-8, "equal x angular impulses")
				H.near(dwy, b.wy - beforeB.wy, 1e-8, "equal y angular impulses")
				H.near(dwz, b.wz - beforeB.wz, 1e-8, "equal z angular impulses")
				H.near(dwx * nx + dwy * ny, 0, 1e-8, "contact cannot torque around its normal")
				local jt = (a.vx - beforeA.vx) * tx + (a.vy - beforeA.vy) * ty
				H.near(dwz, 2.5 * jt / R, 1e-8, "side-spin torque follows the impulse")
				local afterT = (a.vx - b.vx) * tx + (a.vy - b.vy) * ty + R * (a.wz + b.wz)
				local afterZ = R * ((a.wx + b.wx) * ny - (a.wy + b.wy) * nx)
				for _, slip in { { beforeT, afterT }, { beforeZ, afterZ } } do
					H.expect(
						math.abs(slip[2]) <= math.abs(slip[1]) + 1e-8,
						"friction increased contact slip"
					)
					H.expect(slip[1] * slip[2] >= -1e-7, "friction reversed contact slip")
				end
				H.expect(a.vz == 0 and b.vz == 0, "vertical impulse must not launch a ball")
			end
		end)
	end,

	["the rack is legal: 16 balls, none overlapping, apex on the foot spot"] = function()
		local Config, _, TableGeometry, _, Rack, geometry = setup()
		local balls = Rack.newGame(geometry)
		H.expect(#balls == 16, "expected 16 balls")
		local positions, flags = {}, {}
		for i, b in balls do
			positions[3 * i - 2], positions[3 * i - 1], positions[3 * i] = b.x, b.y, 0
			flags[i] = false
		end
		H.expect(
			minSeparation(positions, flags) >= 2 * Config.Balls.RadiusInches,
			"racked balls overlap"
		)
		local fx, fy = TableGeometry.footSpot(geometry)
		local one = balls[2]
		H.expect(one.id == 1 and one.x == fx and one.y == fy, "the 1 ball is not on the foot spot")
	end,

	["a full-power break scatters the rack and nothing tunnels"] = function()
		local Config, Ball, TableGeometry, Simulation, Rack, geometry = setup()
		local R = Config.Balls.RadiusInches
		for _, angle in { 0, 0.004, -0.01 } do
			local state, result = runBreak(Ball, Simulation, Rack, geometry, angle)
			H.expect(not result.capped, "break never came to rest")
			local flagsByFrame = pocketedByFrame(result, #state.balls)
			for f, frame in result.frames do
				local sep = minSeparation(frame.positions, flagsByFrame[f])
				H.expect(
					sep >= 2 * R - 1e-3,
					("balls overlapped by %.4f in at frame %d (t=%.3f) angle %.3f"):format(
						2 * R - sep,
						f,
						frame.t,
						angle
					)
				)
				for i = 1, #state.balls do
					if not flagsByFrame[f][i] then
						local x, y = frame.positions[3 * i - 2], frame.positions[3 * i - 1]
						H.expect(
							TableGeometry.containsCenter(
								geometry,
								x,
								y,
								Config.Balls.RadiusInches + 1e-3
							),
							("ball %d left the table at (%.2f, %.2f) frame %d"):format(
								i - 1,
								x,
								y,
								f
							)
						)
					end
				end
			end
			local moved = 0
			for i, b in state.balls do
				local fb = result.finalBalls[i]
				local dx, dy = fb.x - b.x, fb.y - b.y
				if fb.pocketed or math.sqrt(dx * dx + dy * dy) > 2 * R then
					moved += 1
				end
			end
			H.expect(
				moved >= 13,
				("only %d of 16 balls moved on the break (angle %.3f)"):format(moved, angle)
			)
			local hits = 0
			for _, ev in result.events do
				if ev.type == "ballHit" then
					hits += 1
				end
			end
			H.expect(hits >= 20, ("only %d ball-ball hits on the break"):format(hits))
		end
	end,

	["energy never increases during a break"] = function()
		local Config, _, _, Simulation, Rack, geometry = setup()
		local Cue = H.require("Physics.Cue")
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		Cue.strike(state.balls[1], { angle = 0.002, power = 1 })
		local last = Simulation.energy(state)
		local dt = Config.Physics.FixedStep
		local steps = 0
		while not Simulation.isAtRest(state) and steps < 240 * Config.Physics.MaxShotSeconds do
			Simulation.step(state, dt, nil)
			steps += 1
			local now = Simulation.energy(state)
			H.expect(
				now <= last + 1e-6 * math.max(last, 1),
				("energy rose from %.3f to %.3f at step %d"):format(last, now, steps)
			)
			last = now
		end
	end,

	["stop shot: no spin stops dead, top spin follows, back spin draws back"] = function()
		local _, Ball, _, Simulation, _, geometry = setup()
		-- Object ball 14 in from the top-right corner pocket along the diagonal, cue ball 6 in
		-- behind it. A close hit preserves enough backspin after cloth loss and ball-to-ball
		-- spin transfer to test a strong draw. The pocketed object cannot disturb the cue later.
		local dirX, dirY = 1 / math.sqrt(2), 1 / math.sqrt(2)
		local ox, oy = geometry.halfLength - 10, geometry.halfWidth - 10
		local function shoot(spinY: number): (number, boolean)
			local state = Simulation.newState(
				geometry,
				{ Ball.new(0, ox - 6 * dirX, oy - 6 * dirY), Ball.new(1, ox, oy) }
			)
			local result = Simulation.run(
				state,
				{ angle = math.atan2(dirY, dirX), power = 0.25, spin = { x = 0, y = spinY } }
			)
			H.expect(result.firstContact == 1, "cue ball should hit the 1 ball first")
			local cue = result.finalBalls[1]
			-- Distance travelled past the contact point, measured along the shot direction.
			local along = (cue.x - ox) * dirX + (cue.y - oy) * dirY
			return along, result.finalBalls[2].pocketed
		end
		local stun, objectPocketed = shoot(0)
		H.expect(objectPocketed, "object ball should drop into the corner pocket")
		H.expect(
			math.abs(stun) < 8,
			("stun shot cue ball should stop near contact, travelled %.2f"):format(stun)
		)
		local follow = shoot(0.45)
		H.expect(
			follow > stun + 3,
			("top spin should follow through: %.2f vs stun %.2f"):format(follow, stun)
		)
		local draw = shoot(-0.45)
		H.expect(
			draw < stun - 3,
			("back spin should draw back: %.2f vs stun %.2f"):format(draw, stun)
		)
	end,

	["a ball rolled into a corner pocket drops, and stays out of play"] = function()
		local _, Ball, _, Simulation, _, geometry = setup()
		local state = Simulation.newState(
			geometry,
			{ Ball.new(0, geometry.halfLength - 10, geometry.halfWidth - 10) }
		)
		local result = Simulation.run(state, { angle = math.atan2(10, 10), power = 0.25 })
		local pocketEvent = nil
		for _, ev in result.events do
			if ev.type == "pocket" then
				pocketEvent = ev
			end
		end
		H.expect(pocketEvent ~= nil, "cue ball never dropped into the top-right corner pocket")
		H.expect(pocketEvent and pocketEvent.other == 3, "wrong pocket id")
		H.expect(result.finalBalls[1].pocketed, "final state should mark the ball pocketed")
		H.expect(not result.finalBalls[1].falling, "the drop should finish before the shot ends")
		-- The drop is physical: between consecutive frames the ball never jumps, and its
		-- height goes down smoothly from 0 to the drop depth.
		local Config = H.require("Config")
		local biggestJump, sawDrop, lastZ = 0, false, 0
		for f = 2, #result.frames do
			local a, b = result.frames[f - 1].positions, result.frames[f].positions
			local jump = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
			if jump > biggestJump then
				biggestJump = jump
			end
			H.expect(b[3] <= lastZ + 1e-9, "ball rose while dropping")
			lastZ = b[3]
			if b[3] < -1 then
				sawDrop = true
			end
		end
		H.expect(
			sawDrop and lastZ <= -Config.Table.PocketDropDepthInches + 1e-6,
			"ball never dropped to the bottom"
		)
		H.expect(
			biggestJump < 1.5,
			("ball jumped %.2f in between frames (teleport)"):format(biggestJump)
		)
	end,

	["a ball rolling along the rail passes the side pocket and drops in the corner"] = function()
		local Config, Ball, _, Simulation, _, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state =
			Simulation.newState(geometry, { Ball.new(0, -30, geometry.halfWidth - R - 0.02) })
		local result = Simulation.run(state, { angle = 0, power = 0.4 })
		local pocketId = nil
		for _, ev in result.events do
			if ev.type == "pocket" then
				pocketId = ev.other
			end
		end
		H.expect(pocketId ~= 2, "rail-hugging ball fell into the side pocket")
		H.expect(
			pocketId == 3,
			("ball should end in the top-right corner pocket, got %s"):format(tostring(pocketId))
		)
	end,

	["balls never overlap at rest after many shots"] = function()
		local Config, _, _, Simulation, Rack, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		local angles = { 0.001, 1.2, 2.5, 4.0, 5.5, 0.7, 3.3 }
		for _, angle in angles do
			local cue = Simulation.findBall(state, 0)
			if cue == nil or cue.pocketed then
				break
			end
			local result = Simulation.run(state, { angle = angle, power = 0.8 })
			state.balls = result.finalBalls
			local positions, flags = {}, {}
			for i, b in state.balls do
				positions[3 * i - 2], positions[3 * i - 1], positions[3 * i] = b.x, b.y, b.z
				flags[i] = b.pocketed
			end
			H.expect(
				minSeparation(positions, flags) >= 2 * R - 1e-6,
				("balls overlap at rest after shot angle %.1f"):format(angle)
			)
		end
	end,
}
