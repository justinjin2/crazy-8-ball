--!strict
-- Pockets: where the opening is, and what a ball does once its centre crosses the rim.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Simulation = H.require("Physics.Simulation")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	return Config, Ball, TableGeometry, Simulation, geometry
end

-- One ball, placed by hand, stepped to rest. Returns the ball, the events and the time taken.
local function runOne(
	Config,
	Ball,
	Simulation,
	geometry,
	x: number,
	y: number,
	vx: number,
	vy: number,
	wz: number?
)
	local b = Ball.new(1, x, y)
	b.vx, b.vy = vx, vy
	local R = Config.Balls.RadiusInches
	b.wx, b.wy = -vy / R, vx / R -- rolling, like a ball that got there under its own steam
	b.wz = wz or 0
	local state = Simulation.newState(geometry, { b })
	local events = {}
	local dt = Config.Physics.FixedStep
	local maxSteps = math.floor(Config.Physics.MaxShotSeconds / dt)
	local steps = 0
	while not Simulation.isAtRest(state) and steps < maxSteps do
		Simulation.step(state, dt, events)
		steps += 1
	end
	return b, events, state.time, steps
end

-- The two cushion noses either side of a pocket's mouth, from the geometry itself.
local function mouthNoses(Config, geometry, pocketName: string)
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local T = Config.Table
	if pocketName == "topLeft" then
		local c = T.CornerMouthInches / math.sqrt(2)
		return { x = -hl + c, y = hw }, { x = -hl, y = hw - c }
	end
	local sm = T.SideMouthInches / 2
	return { x = -sm, y = hw }, { x = sm, y = hw }
end

local function pocketByName(geometry, name: string)
	for _, p in geometry.pockets do
		if p.name == name then
			return p
		end
	end
	error("no pocket named " .. name)
end

local function pocketEvents(events, ballId: number)
	local out = {}
	for _, ev in events do
		if ev.type == "pocket" and ev.ball == ballId then
			table.insert(out, ev)
		end
	end
	return out
end

return {
	---------------------------------------------------------------------------------------
	-- Geometry: the opening is built from the mouth
	---------------------------------------------------------------------------------------

	["corner rims leave a flat shelf and side rims stay tangent to the mouth"] = function()
		local Config, _, _, _, geometry = setup()
		H.near(
			Config.Table.PocketOpeningMouthFraction,
			1,
			1e-9,
			"this test states the tangency rule, which only holds at fraction 1"
		)
		for _, name in { "topLeft", "topSide" } do
			local p = pocketByName(geometry, name)
			local a, b = mouthNoses(Config, geometry, name)
			-- Distance from the opening centre to the infinite line through the two noses.
			local ex, ey = b.x - a.x, b.y - a.y
			local len = math.sqrt(ex * ex + ey * ey)
			local dist = math.abs((p.x - a.x) * ey - (p.y - a.y) * ex) / len
			local shelf = if name == "topLeft" then Config.Table.CornerShelfInches else 0
			H.near(
				dist,
				p.radius + shelf,
				1e-9,
				("%s: centre sits %.4f from the mouth line, rim is %.4f"):format(
					name,
					dist,
					p.radius
				)
			)
		end
	end,

	["all corner openings move one shelf depth along their mouth bisector"] = function()
		local Config, _, _, _, geometry = setup()
		local offset = Config.Table.CornerShelfInches / math.sqrt(2)
		for _, name in { "topLeft", "topRight", "bottomRight", "bottomLeft" } do
			local p = pocketByName(geometry, name)
			H.near(math.abs(p.x), geometry.halfLength + offset, 1e-9, "corner opening x")
			H.near(math.abs(p.y), geometry.halfWidth + offset, 1e-9, "corner opening y")
			H.near(p.radius, Config.Table.CornerMouthInches / 2, 1e-9, "corner opening radius")
		end
	end,

	["corner facings reach the shifted rim without a gap behind the jaws"] = function()
		local _, _, _, _, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		local found = 0
		for _, pt in geometry.points do
			if pt.name:match("Corner.*Jaw$") and pt.x < 0 and pt.y > 0 then
				local dx, dy = pt.x - p.x, pt.y - p.y
				local dist = math.sqrt(dx * dx + dy * dy)
				found += 1
				H.near(dist, p.radius, 1e-9, "corner jaw must end at the opening rim")
			end
		end
		H.expect(found == 2, ("expected both corner jaws on the rim, found %d"):format(found))
	end,

	["the escape safety net leaves room for the shifted corner openings"] = function()
		local Config, _, TableGeometry, _, geometry = setup()
		local oldLimit = Config.Table.PocketShelfBallRadii * Config.Balls.RadiusInches
		local offset = Config.Table.CornerShelfInches / math.sqrt(2)
		H.expect(
			TableGeometry.pocketAt(geometry, geometry.halfLength + oldLimit + offset / 2, 0) == nil,
			"the escape guard fired before the shifted corner allowance"
		)
		H.expect(
			TableGeometry.pocketAt(geometry, geometry.halfLength + oldLimit + offset + 0.01, 0)
				~= nil,
			"the escape safety net no longer catches balls outside the extended table"
		)
	end,

	["the rim never eats into a playing cushion"] = function()
		local Config, _, _, _, geometry = setup()
		local R = Config.Balls.RadiusInches
		for _, p in geometry.pockets do
			for _, seg in geometry.segments do
				-- Only the long straight rails, not the short angled facings at the mouths.
				local len = math.sqrt((seg.bx - seg.ax) ^ 2 + (seg.by - seg.ay) ^ 2)
				if len > R * 2 then
					-- Closest point on the rail segment to the opening centre.
					local ex, ey = (seg.bx - seg.ax) / len, (seg.by - seg.ay) / len
					local t = math.clamp((p.x - seg.ax) * ex + (p.y - seg.ay) * ey, 0, len)
					local cx, cy = seg.ax + ex * t, seg.ay + ey * t
					local dist = math.sqrt((p.x - cx) ^ 2 + (p.y - cy) ^ 2)
					H.expect(
						dist >= p.radius - 1e-9,
						("%s opening (r %.3f) cuts %.3f into rail %s"):format(
							p.name,
							p.radius,
							p.radius - dist,
							seg.name
						)
					)
				end
			end
		end
	end,

	---------------------------------------------------------------------------------------
	-- The tip
	---------------------------------------------------------------------------------------

	["a soft ball can cross the corner mouth and stop on the flat shelf"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		local shelf = Config.Table.CornerShelfInches
		local d = (p.radius + shelf * 0.75) / math.sqrt(2)
		-- Start a quarter of the way across the shelf; rolling resistance should stop it
		-- another half-shelf later, before the actual hole. A stopped shelf ball is supported.
		local decel = Config.Physics.RollingFriction * Config.Physics.Gravity
		local v = math.sqrt(2 * decel * shelf * 0.5) / math.sqrt(2)
		local b, events = runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, -v, v)
		local dist = math.sqrt((b.x - p.x) ^ 2 + (b.y - p.y) ^ 2)
		H.expect(not b.pocketed, "a supported ball was pulled across the flat shelf")
		H.expect(
			dist > p.radius and dist < p.radius + shelf * 0.5,
			"the ball did not cross the shelf"
		)
		H.expect(#pocketEvents(events, 1) == 0, "a flat shelf hanger fired a pocket event")
	end,

	["a ball left at rest just inside the rim tips in on its own"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		-- Dead stop, centre 0.05 in inside the rim, on the diagonal into the pocket.
		local d = (p.radius - 0.05) / math.sqrt(2)
		local b, events, elapsed =
			runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, 0, 0)
		H.expect(b.pocketed, "a ball overhanging the rim at rest never fell in")
		H.near(b.z, -Config.Table.PocketDropDepthInches, 1e-6, "it did not finish the drop")
		H.expect(
			elapsed > 0.15 and elapsed < 0.9,
			("the tip took %.3f s; it should read as a topple, not a snap"):format(elapsed)
		)
		H.expect(#pocketEvents(events, 1) == 1, "expected exactly one pocket event")
	end,

	["a ball left at rest just outside the rim stays on the table"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		local d = (p.radius + 0.05) / math.sqrt(2)
		local b, events = runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, 0, 0)
		H.expect(not b.pocketed, "a ball still supported by the shelf was taken anyway")
		H.expect(#pocketEvents(events, 1) == 0, "it fired a pocket event")
	end,

	["a hanger leaves the lip fast enough to be heard"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		local d = (p.radius - 0.01) / math.sqrt(2)
		local _, events = runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, 0, 0)
		local drops = pocketEvents(events, 1)
		H.expect(#drops == 1, "expected exactly one pocket event")
		-- Gravity alone gets it to about 17 in/s coming off the lip. Firing the event when
		-- the ball CROSSES the rim instead would report ~0 and the drop would be silent.
		H.expect(
			drops[1].speed > 8,
			("a hanger dropped at %.2f in/s, too quiet to hear"):format(drops[1].speed)
		)
	end,

	["a firmly struck ball is gone at once, exactly as before"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		-- Approaching down the diagonal at 150 in/s, starting a little outside the rim.
		local d = (p.radius + 1.0) / math.sqrt(2)
		local v = 150 / math.sqrt(2)
		local b, events = runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, -v, v)
		H.expect(b.pocketed, "a ball driven into the pocket was not taken")
		local drops = pocketEvents(events, 1)
		H.expect(#drops == 1, "expected exactly one pocket event")
		H.expect(
			drops[1].t < 4 * Config.Physics.FixedStep,
			("a fast ball spent %.4f s on the lip; it should not linger"):format(drops[1].t)
		)
		H.expect(drops[1].speed > 100, ("a fast drop reported %.1f in/s"):format(drops[1].speed))
	end,

	["a ball rolling along the rail into a corner goes in"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		-- Touching the top cushion, heading for the top-left corner. The extended facings
		-- must still admit it even though the opening moved back behind a flat shelf.
		local b, events = runOne(
			Config,
			Ball,
			Simulation,
			geometry,
			-geometry.halfLength + 20,
			geometry.halfWidth - R,
			-60,
			0
		)
		H.expect(b.pocketed, "a rail-hugging ball was not pocketed")
		H.expect(b.pocket == pocketByName(geometry, "topLeft").id, "it went to the wrong pocket")
		H.expect(#pocketEvents(events, 1) == 1, "expected exactly one pocket event")
	end,

	["a dropping ball's surface rides the liner instead of passing through it"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local R = Config.Balls.RadiusInches
		local p = pocketByName(geometry, "topLeft")
		local d = (p.radius - 0.01) / math.sqrt(2)
		-- Thrown hard across the mouth, so the drop slams into the far side of the liner.
		local b = Ball.new(1, p.x + d, p.y - d)
		b.vx, b.vy = -120, 40
		local state = Simulation.newState(geometry, { b })
		local dt = Config.Physics.FixedStep
		local steps = 0
		local worst = 0
		while not Simulation.isAtRest(state) and steps < 4000 do
			-- Only steps the ball spent entirely in free fall. The step it crosses the rim on
			-- and the step it comes off the lip on both legitimately leave it proud of the
			-- rim: rolling over an edge is exactly that.
			local wasFalling = b.falling and b.tip == nil
			Simulation.step(state, dt, nil)
			steps += 1
			if wasFalling and b.falling and b.tip == nil then
				local dist = math.sqrt((b.x - p.x) ^ 2 + (b.y - p.y) ^ 2)
				worst = math.max(worst, dist + R)
			end
		end
		H.expect(b.pocketed, "the ball never dropped")
		H.expect(
			worst <= p.radius + 1e-6,
			("the ball poked %.3f in through the leather on the way down"):format(worst - p.radius)
		)
	end,

	["corner entry sweep never leaks past a jaw or strands a ball over the hole"] = function()
		local Config, Ball, TableGeometry, Simulation, geometry = setup()
		-- Observe every capture, including captures inside an event substep. A safety-net
		-- capture would hide a missing piece of jaw geometry, so require the real hole.
		local pocketAt = TableGeometry.pocketAt
		TableGeometry.pocketAt = function(g, x: number, y: number)
			local p = pocketAt(g, x, y)
			if p then
				local distSquared = (x - p.x) ^ 2 + (y - p.y) ^ 2
				H.expect(
					distSquared <= p.radius ^ 2 + 1e-8,
					"a corner shot escaped into the safety net"
				)
			end
			return p
		end
		local ok, err = pcall(function()
			local maxSteps = math.floor(Config.Physics.MaxShotSeconds / Config.Physics.FixedStep)
			local pocketed, returned = 0, 0
			for _, degrees in { 123, 127, 131, 135, 139, 143, 147 } do
				for _, speed in { 10, 40, 150, 528 } do
					for _, spin in { -80, 0, 80 } do
						local angle = math.rad(degrees)
						local b, _, _, steps = runOne(
							Config,
							Ball,
							Simulation,
							geometry,
							-geometry.halfLength + 10,
							geometry.halfWidth - 10,
							speed * math.cos(angle),
							speed * math.sin(angle),
							spin
						)
						H.expect(steps < maxSteps, "a corner shot never settled")
						if b.pocketed then
							pocketed += 1
						else
							returned += 1
							H.expect(
								pocketAt(geometry, b.x, b.y) == nil,
								"a stopped ball still hangs over the hole"
							)
						end
					end
				end
			end
			H.expect(pocketed > 0 and returned > 0, "the sweep must cover both entries and misses")
		end)
		TableGeometry.pocketAt = pocketAt
		if not ok then
			error(err)
		end
	end,

	---------------------------------------------------------------------------------------
	-- Determinism
	---------------------------------------------------------------------------------------

	["a tip runs the same numbers twice"] = function()
		local Config, Ball, _, Simulation, geometry = setup()
		local p = pocketByName(geometry, "topLeft")
		local d = (p.radius - 0.02) / math.sqrt(2)
		local function once()
			local b = runOne(Config, Ball, Simulation, geometry, p.x + d, p.y - d, 0, 0)
			return Simulation.checksum({ b })
		end
		H.expect(once() == once(), "two runs of the same tip disagreed")
	end,

	["a whole shot with pockets open replays identically"] = function()
		local _, _, _, Simulation, geometry = setup()
		local Rack = H.require("Physics.Rack")
		local function once()
			local state = Simulation.newState(geometry, Rack.newGame(geometry))
			local result = Simulation.run(state, { angle = 0.04, power = 1 })
			return Simulation.checksum(result.finalBalls), #result.events
		end
		local a1, e1 = once()
		local a2, e2 = once()
		H.expect(a1 == a2 and e1 == e2, "two runs of the same break disagreed")
	end,
}
