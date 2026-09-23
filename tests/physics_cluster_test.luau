--!strict
-- Simultaneous soft contact (Physics/Cluster.luau): a contact that involves a ball already
-- touching a third ball is integrated as Hertz spheres, everything else stays pairwise.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local Cluster = H.require("Physics.Cluster")
	local Rack = H.require("Physics.Rack")
	local Simulation = H.require("Physics.Simulation")
	local TableGeometry = H.require("Physics.Table")
	return Config, Ball, Cluster, Rack, Simulation, TableGeometry
end

-- Cloth off, so a contact's own momentum and energy bookkeeping can be checked exactly.
-- Restores every setting even when the check fails.
local function withoutCloth(Config, callback: () -> ())
	local P = Config.Physics
	local sliding, rolling, spin = P.SlidingFriction, P.RollingFriction, P.SideSpinDecel
	local rest, epsilon = P.RestSpeed, P.SlideEpsilon
	P.SlidingFriction, P.RollingFriction, P.SideSpinDecel = 0, 0, 0
	P.RestSpeed, P.SlideEpsilon = 0, 0
	local ok, err = pcall(callback)
	P.SlidingFriction, P.RollingFriction, P.SideSpinDecel = sliding, rolling, spin
	P.RestSpeed, P.SlideEpsilon = rest, epsilon
	if not ok then
		error(err)
	end
end

-- The real break: cue ball on the break line, full power, straight, with the server's
-- quantised strike, settled exactly as the server settles it.
local function realBreak(seed: number)
	local Config, _, _, Rack, Simulation, TableGeometry = setup()
	local ShotInput = H.require("ShotInput")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local state = Simulation.newState(geometry, Rack.newGame(geometry, seed))
	state.balls[1].x = Config.Multiplayer.BreakLineX
	local shot = assert(ShotInput.validate({ angle = 0, power = 1 }, nil))
	local strike = Simulation.strike(state, shot)
	ShotInput.quantiseSeed(state.balls[1])
	return Simulation.settle(state, { strike })
end

local function groupEnergy(Ball, balls, radius: number): number
	local total = 0
	for _, b in balls do
		total += Ball.kineticEnergy(b, radius)
	end
	return total
end

return {
	["an isolated soft pair restitutes at BallRestitution at every speed"] = function()
		local Config, Ball, Cluster = setup()
		local R = Config.Balls.RadiusInches
		local stiffness, damping = Cluster.material()
		H.expect(stiffness > 0 and damping > 0, "the soft contact needs a spring and damping")
		for _, speed in { 1, 10, 100, 300, 528 } do
			local a, b = Ball.new(0, 0, 0), Ball.new(1, 2 * R, 0)
			a.vx = speed
			local duration = Cluster.resolve({ a, b }, a, b, 0, nil)
			H.near((b.vx - a.vx) / speed, Config.Physics.BallRestitution, 1e-3, "restitution")
			H.near(a.vx + b.vx, speed, 1e-9 * speed, "momentum")
			H.expect(
				duration > 50e-6 and duration < Config.Physics.SoftContactMaxSeconds,
				("contact at %d in/s lasted %.0f us"):format(speed, duration * 1e6)
			)
		end
	end,

	["a simple two-ball shot is bit-identical to the pairwise model"] = function()
		local _, Ball, _, _, Simulation, TableGeometry = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		-- Captured with the pairwise-only engine immediately before soft contact landed.
		-- Two balls alone never touch a third, so nothing here may change by a single bit.
		local cases = {
			{
				balls = { { 0, -20, -4 }, { 1, -12, -3 } },
				shot = { angle = 0.05, power = 0.5, spin = { x = 0.3, y = -0.2 } },
				events = 4,
				duration = "6.9708333333332577",
				final = {
					{ "-20.5414005456444", "-20.100113740971413" },
					{ "-13.248374032309016", "18.448519495857241" },
				},
			},
			{
				balls = { { 0, -30, 0 }, { 1, 0, 0.6 } },
				shot = { angle = 0, power = 0.9, spin = { x = 0, y = 0.4 } },
				events = 13,
				duration = "9.1999999999997968",
				final = {
					{ "4.5259296199262966", "4.0432016991160094" },
					{ "46.823463977123019", "-12.434166712955957" },
				},
			},
		}
		for index, case in cases do
			local balls = {}
			for _, row in case.balls do
				table.insert(balls, Ball.new(row[1], row[2], row[3]))
			end
			local result = Simulation.runHeadless(Simulation.newState(geometry, balls), case.shot)
			H.expect(#result.events == case.events, "case " .. index .. " event count")
			H.expect(result.duration == tonumber(case.duration), "case " .. index .. " duration")
			for i, b in result.finalBalls do
				H.expect(
					b.x == tonumber(case.final[i][1]) and b.y == tonumber(case.final[i][2]),
					("case %d ball %d moved to %.17g, %.17g"):format(index, b.id, b.x, b.y)
				)
			end
		end
	end,

	["a three-ball touching line passes the hit through like a cradle"] = function()
		local Config, Ball, _, _, Simulation, TableGeometry = setup()
		local geometry = TableGeometry.build({ pocketsOpen = false })
		local R = Config.Balls.RadiusInches
		withoutCloth(Config, function()
			for _, gap in { 0, Config.Physics.ContactSlop } do
				local b = Ball.new(1, 0, 0)
				local c = Ball.new(2, 2 * R + gap, 0)
				local a = Ball.new(0, -2 * R - 0.5, 0)
				a.vx = 100
				local state = Simulation.newState(geometry, { a, b, c })
				local before = Simulation.energy(state)
				local events = {}
				for _ = 1, 3 do
					Simulation.step(state, Config.Physics.FixedStep, events)
				end
				H.near(a.vx + b.vx + c.vx, 100, 1e-9, "momentum along the line")
				H.expect(a.vy == 0 and b.vy == 0 and c.vy == 0, "a straight line stays straight")
				H.expect(Simulation.energy(state) <= before, "energy rose")
				-- Hertz contacts are not a perfect cradle: the far ball takes nearly all of
				-- it and the first two are left with a few in/s.
				H.expect(c.vx > 90, ("far ball left at %.2f in/s"):format(c.vx))
				H.expect(math.abs(a.vx) < 10 and math.abs(b.vx) < 15, "near balls keep too much")
				H.expect(a.x < b.x and b.x < c.x, "balls passed through each other")
				H.expect(b.x - a.x >= 2 * R and c.x - b.x >= 2 * R, "balls overlap afterwards")
				H.expect(
					#events == 2 and events[1].ball == 0 and events[1].other == 1,
					"the struck pair reports first"
				)
				H.near(events[1].speed, 100, 1e-9, "impact speed of the struck pair")
				H.expect(
					events[2].ball == 1 and events[2].other == 2 and events[2].speed > 30,
					"the pressed pair reports once, with the speed it closed at"
				)
				H.expect(events[2].t >= events[1].t, "events in time order")
			end
		end)
	end,

	["energy never increases through a soft phase and momentum is kept"] = function()
		local Config, Ball, Cluster, Rack, _, TableGeometry = setup()
		local R = Config.Balls.RadiusInches
		local geometry = TableGeometry.build({ pocketsOpen = true })
		for _, spin in { 0, 1, -1 } do
			local balls = Rack.newGame(geometry, 3)
			local cue, apex = balls[1], balls[2]
			cue.x, cue.y = apex.x - 2 * R, apex.y
			cue.vx, cue.vy = 520, 3
			cue.wy = spin * cue.vx / R -- stun, rolling, or full draw
			cue.wz = 20
			local members = assert(Cluster.gather(balls, cue, apex, geometry, nil))
			H.expect(#members == 16, "the whole rack joins the phase")
			local before = groupEnergy(Ball, balls, R)
			local px, py = 0, 0
			for _, b in balls do
				px += b.vx
				py += b.vy
			end
			local reported = 0
			Cluster.resolve(members, cue, apex, 0, function()
				reported += 1
			end)
			local qx, qy = 0, 0
			for _, b in balls do
				qx += b.vx
				qy += b.vy
			end
			H.expect(groupEnergy(Ball, balls, R) <= before, "a soft phase added energy")
			H.near(qx, px, 1e-9 * 520, "momentum x")
			H.near(qy, py, 1e-9 * 520, "momentum y")
			H.expect(reported >= 20, "every touching pair reports")
			for i, a in balls do
				for j = i + 1, #balls do
					local b = balls[j]
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
					H.expect(d >= 2 * R - 1e-9, "balls left overlapping")
				end
			end
		end
	end,

	["a stun cue ball gives the rack nearly all its speed"] = function()
		local Config, _, Cluster, Rack, _, TableGeometry = setup()
		local R = Config.Balls.RadiusInches
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local balls = Rack.newGame(geometry, 1)
		local cue, apex = balls[1], balls[2]
		cue.x, cue.y, cue.vx = apex.x - 2 * R, apex.y, 500
		local members = assert(Cluster.gather(balls, cue, apex, geometry, nil))
		Cluster.resolve(members, cue, apex, 0, nil)
		-- A tight rack is heavier than one ball, so the cue ball comes back a little; it
		-- must not keep going, and must not come back hard.
		H.expect(
			cue.vx < 0 and cue.vx > -0.2 * 500,
			("stun cue ball left the rack at %.1f in/s"):format(cue.vx)
		)
		H.expect(math.abs(cue.vy) < 1, "a straight hit stays straight")
	end,

	["a cluster near a cushion keeps the pairwise model"] = function()
		local Config, Ball, Cluster, _, _, TableGeometry = setup()
		local R = Config.Balls.RadiusInches
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local y = geometry.halfWidth - R - 0.5
		local a, b, c = Ball.new(0, -10, y), Ball.new(1, 0, y), Ball.new(2, 2 * R, y)
		a.x, a.vx = -2 * R, 200
		H.expect(Cluster.touchesAnother({ a, b, c }, a, b, nil), "b touches c")
		H.expect(
			Cluster.gather({ a, b, c }, a, b, geometry, nil) == nil,
			"a group that could reach the cushion must fall back to pairwise"
		)
		local far = Ball.new(3, 0, 0)
		H.expect(
			not Cluster.touchesAnother({ a, b, far }, a, b, nil),
			"a ball well clear does not make the contact soft"
		)
	end,

	["the first contact on a straight break is the apex"] = function()
		for seed = 1, 4 do
			local outcome = realBreak(seed)
			H.expect(outcome.firstContact == 1, "seed " .. seed .. ": first contact is not the 1")
			local first = outcome.events[2]
			H.expect(
				first.type == "ballHit" and first.ball == 0 and first.other == 1,
				"seed " .. seed .. ": the event after the strike is cue ball on the apex"
			)
			local last = -1
			local pairsAtImpact = 0
			for _, ev in outcome.events do
				H.expect(ev.t >= last, "seed " .. seed .. ": events out of time order")
				last = ev.t
				if ev.type == "ballHit" and ev.t - first.t < 0.001 then
					pairsAtImpact += 1
				end
			end
			H.expect(
				pairsAtImpact >= 20,
				("seed %d: only %d contacts in the first millisecond"):format(seed, pairsAtImpact)
			)
		end
	end,

	["the break spreads the rack across seeds"] = function()
		local Config = setup()
		-- Pairwise-only engine over these seeds: 0 pocketed, 6.8 distinct object balls to a
		-- rail, 11.2 left in the foot quarter. Soft contact measured 0.64, 12.5 and 3.2.
		local seeds, pocketed, railBalls, footQuarter = 11, 0, 0, 0
		for seed = 1, seeds do
			local outcome = realBreak(seed)
			H.expect(not outcome.capped, "seed " .. seed .. " never settled")
			local seen: { [number]: boolean } = {}
			for _, ev in outcome.events do
				if ev.type == "railHit" and ev.ball ~= 0 then
					seen[ev.ball] = true
				elseif ev.type == "pocket" and ev.ball ~= 0 then
					pocketed += 1
				end
			end
			for id = 1, 15 do
				if seen[id] then
					railBalls += 1
				end
			end
			for _, b in outcome.finalBalls do
				if b.id ~= 0 and not b.pocketed and b.x > Config.Table.LengthInches / 4 then
					footQuarter += 1
				end
			end
		end
		H.expect(
			railBalls / seeds >= 10,
			("mean %.1f distinct balls reached a rail"):format(railBalls / seeds)
		)
		H.expect(
			footQuarter / seeds <= 6,
			("mean %.1f balls left in the foot quarter"):format(footQuarter / seeds)
		)
		H.expect(pocketed >= 3, ("only %d balls pocketed over %d breaks"):format(pocketed, seeds))
	end,

	["soft breaks are deterministic and the replay stepping matches the server"] = function()
		local Config, _, _, Rack, Simulation, TableGeometry = setup()
		local geometry = TableGeometry.build({ pocketsOpen = true })
		local shot = { angle = 0.002, power = 1 }
		local function fresh()
			return Simulation.newState(geometry, Rack.newGame(geometry, 5))
		end
		local recorded = Simulation.run(fresh(), shot)
		local headless = Simulation.runHeadless(fresh(), shot)
		-- A client replay: strike, then one fixed step per loop until at rest.
		local client = fresh()
		local events = { Simulation.strike(client, shot) }
		local steps = 0
		while not Simulation.isAtRest(client) do
			Simulation.step(client, Config.Physics.FixedStep, events)
			steps += 1
		end
		H.expect(steps == recorded.steps, "replay took a different number of steps")
		H.expect(
			#events == #recorded.events and #events == #headless.events,
			"replay event counts differ"
		)
		for i, ev in recorded.events do
			local a, b = headless.events[i], events[i]
			H.expect(
				ev.t == a.t and ev.t == b.t and ev.speed == a.speed and ev.speed == b.speed,
				"event " .. i .. " differs"
			)
			H.expect(ev.ball == b.ball and ev.other == b.other and ev.type == b.type)
		end
		for i, ball in recorded.finalBalls do
			local a, b = headless.finalBalls[i], client.balls[i]
			H.expect(ball.x == a.x and ball.y == a.y and ball.x == b.x and ball.y == b.y)
			H.expect(ball.pocketed == a.pocketed and ball.pocketed == b.pocketed)
		end
	end,
}
