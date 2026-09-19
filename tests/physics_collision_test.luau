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

local function runBreak(Simulation, Rack, geometry, angle: number)
	local state = Simulation.newState(geometry, Rack.newGame(geometry))
	return state, Simulation.run(state, { angle = angle, power = 1 })
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
		local Config, _, TableGeometry, Simulation, Rack, geometry = setup()
		local R = Config.Balls.RadiusInches
		for _, angle in { 0, 0.004, -0.01 } do
			local state, result = runBreak(Simulation, Rack, geometry, angle)
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
		-- Object ball 14 in from the top-right corner pocket along the diagonal, cue ball 10 in
		-- behind it. The object ball drops, so it can never come back and disturb the cue ball.
		local dirX, dirY = 1 / math.sqrt(2), 1 / math.sqrt(2)
		local ox, oy = geometry.halfLength - 10, geometry.halfWidth - 10
		local function shoot(spinY: number): (number, boolean)
			local state = Simulation.newState(
				geometry,
				{ Ball.new(0, ox - 10 * dirX, oy - 10 * dirY), Ball.new(1, ox, oy) }
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
