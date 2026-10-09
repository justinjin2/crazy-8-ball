--!strict
-- Guideline trace tests: launch ray and shared collision geometry. With side spin not
-- bending the path (Config.Cue.SideSpinBendsPath off) the trace is exact for any spin,
-- even to a distant ball.

local H = require("./harness")

local function setup()
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Simulation = H.require("Physics.Simulation")
	local Aim = H.require("Physics.Aim")
	return Config, Ball, TableGeometry, Simulation, Aim, TableGeometry.build({ pocketsOpen = true })
end

return {
	["straight shot: ghost ball touches the object ball, cue ball stops"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 0) })
		local t = Aim.trace(state, 0)
		H.expect(t.contact == "ball" and t.objectId == 1, "should hit the 1 ball")
		H.near(t.ghostX, -2 * R, 1e-6, "ghost x")
		H.near(t.ghostY, 0, 1e-6, "ghost y")
		H.near(t.objectDirX, 1, 1e-6, "object heads straight on")
		H.expect(t.cueDirX == 0 and t.cueDirY == 0, "straight hit leaves no cue ball direction")
	end,

	["cut shot: object direction follows the line of centres, cue ball goes along the tangent"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local state = Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 1.0) })
		local t = Aim.trace(state, 0)
		H.expect(t.contact == "ball", "should hit the ball")
		H.expect(t.objectDirY > 0.3 and t.objectDirX > 0.8, "object ball should be cut upwards")
		local dot = t.objectDirX * t.cueDirX + t.objectDirY * t.cueDirY
		H.near(dot, 0, 1e-6, "cue direction is perpendicular to the object direction")
		H.expect(t.cueDirY < 0, "cue ball deflects the other way")
	end,

	["rail shot: contact on the foot rail with mirrored direction"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(geometry, { Ball.new(0, 0, 0) })
		local t = Aim.trace(state, 0.3)
		H.expect(t.contact == "rail", "should hit a rail")
		H.near(t.ghostX, geometry.halfLength - R, 1e-6, "ghost sits against the foot rail")
		H.near(t.cueDirX, -math.cos(0.3), 1e-6, "x mirrored")
		H.near(t.cueDirY, math.sin(0.3), 1e-6, "y kept")
	end,

	["the trace predicts the same first contact as the simulation"] = function()
		local _, _, _, Simulation, Aim, geometry = setup()
		local Rack = H.require("Physics.Rack")
		local state = Simulation.newState(geometry, Rack.newGame(geometry))
		for _, angle in { 0.02, -0.03, 0.15, 0.5 } do
			local t = Aim.trace(state, angle)
			local result = Simulation.run(state, { angle = angle, power = 0.5 })
			if t.contact == "ball" then
				H.expect(
					result.firstContact == t.objectId,
					("angle %.2f: trace said ball %d, simulation hit %s"):format(
						angle,
						t.objectId or -1,
						tostring(result.firstContact)
					)
				)
			else
				H.expect(
					result.events[2] and result.events[2].type == "railHit",
					("angle %.2f: trace said rail, simulation disagreed"):format(angle)
				)
			end
		end
	end,

	["side-spin tracing uses the exact aim and preserves geometric object direction"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local Cue = H.require("Physics.Cue")
		for _, side in { -0.5, 0.5 } do
			local shot = { angle = 0.3, power = 0.8, spin = { x = side, y = 0 } }
			local dx, dy = Cue.launchDirection(shot)
			H.expect(dx == math.cos(0.3) and dy == math.sin(0.3), "side spin does not move the aim")
			local state = Simulation.newState(
				geometry,
				{ Ball.new(0, -20, 0), Ball.new(1, -20 + 8 * dx, 8 * dy) }
			)
			local trace = Aim.trace(state, shot)
			local distance = 8 - 2 * Config.Balls.RadiusInches
			H.expect(trace.contact == "ball" and trace.objectId == 1, "short direct hit")
			H.near(trace.ghostX, -20 + distance * dx, 1e-8, "ghost x on the aim")
			H.near(trace.ghostY, distance * dy, 1e-8, "ghost y on the aim")
			H.near(trace.objectDirX, dx, 1e-8, "geometric object line x")
			H.near(trace.objectDirY, dy, 1e-8, "geometric object line y")
			local result = Simulation.run(state, shot)
			H.expect(result.firstContact == trace.objectId, "the simulation hits the traced ball")
		end
	end,

	["side spin with draw or follow meets a distant ball exactly at the no-spin ghost"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local Collision = H.require("Physics.Collision")
		local R = Config.Balls.RadiusInches
		local angle = 0.15
		local c, s = math.cos(angle), math.sin(angle)
		-- 45 inches down the aim, nudged off it for a cut so any bend would miss the ghost.
		local objectX = -30 + 45 * c - 0.8 * R * s
		local objectY = 45 * s + 0.8 * R * c
		local function layout()
			return Simulation.newState(
				geometry,
				{ Ball.new(0, -30, 0), Ball.new(1, objectX, objectY) }
			)
		end
		local plain = Aim.trace(layout(), angle)
		H.expect(plain.contact == "ball" and plain.objectId == 1, "the plain aim hits the 1 ball")
		for _, spin in
			{ { 0.5, 0 }, { -0.5, 0 }, { 0.4, 0.3 }, { 0.4, -0.3 }, { -0.4, 0.3 }, { -0.4, -0.3 } }
		do
			local shot = { angle = angle, power = 0.6, spin = { x = spin[1], y = spin[2] } }
			local label = ("spin %.1f, %.1f"):format(spin[1], spin[2])
			local state = layout()
			local trace = Aim.trace(state, shot)
			H.expect(
				trace.ghostX == plain.ghostX and trace.ghostY == plain.ghostY,
				label .. ": spin does not move the ghost"
			)
			-- Step the real shot to the step before first contact: the cue ball must still be
			-- on the aim line, and continuing its heading must touch the object at the ghost.
			local cue = Simulation.findBall(state, 0) :: any
			Simulation.strike(state, shot)
			local hitId: number? = nil
			local lastX, lastY, lastVx, lastVy = cue.x, cue.y, cue.vx, cue.vy
			for _ = 1, 4800 do
				lastX, lastY, lastVx, lastVy = cue.x, cue.y, cue.vx, cue.vy
				local events = {}
				Simulation.step(state, Config.Physics.FixedStep, events)
				for _, event in events do
					if event.type == "ballHit" or event.type == "railHit" then
						hitId = event.other or -1
					end
				end
				if hitId then
					break
				end
				H.near(-(cue.x + 30) * s + cue.y * c, 0, 1e-9, label .. ": on the aim line")
			end
			H.expect(hitId == trace.objectId, label .. ": the simulation hits the traced ball")
			local speed = math.sqrt(lastVx * lastVx + lastVy * lastVy)
			local ux, uy = lastVx / speed, lastVy / speed
			H.near(ux, c, 1e-9, label .. ": heading x is the aim")
			H.near(uy, s, 1e-9, label .. ": heading y is the aim")
			local t = Collision.circleTOI(lastX, lastY, ux, uy, objectX, objectY, 0, 0, R, 1e6)
			H.expect(t ~= nil, label .. ": still heading into the object ball")
			H.near(
				lastX + ux * (t :: number),
				trace.ghostX,
				1e-6,
				label .. ": contact x is the ghost"
			)
			H.near(
				lastY + uy * (t :: number),
				trace.ghostY,
				1e-6,
				label .. ": contact y is the ghost"
			)
		end
	end,

	["guideline shares: full hit, thin cut and rail follow cos and sin of the cut angle"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		local straight =
			Aim.trace(Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 0) }), 0)
		H.near(straight.objectShare, 1, 1e-9, "a full hit sends the object ball the full line")
		H.near(straight.cueShare, 0, 1e-9, "and leaves the cue ball no deflection line")
		-- Offset the object ball so the line of centres sits 30 degrees off the aim.
		local cut = math.rad(30)
		local offset = 2 * R * math.sin(cut)
		local t = Aim.trace(
			Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, offset) }),
			0
		)
		H.near(t.objectShare, math.cos(cut), 1e-6, "object share is cos(cut)")
		H.near(t.cueShare, math.sin(cut), 1e-6, "cue share is sin(cut)")
		H.near(t.objectShare ^ 2 + t.cueShare ^ 2, 1, 1e-6, "the two shares split the speed")
		local thin = Aim.trace(
			Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 2 * R * 0.97) }),
			0
		)
		H.expect(thin.objectShare < 0.3 and thin.cueShare > 0.95, "a thin cut flips the lengths")
		local rail =
			Aim.trace(Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 20) }), 0)
		H.expect(rail.contact == "rail" and rail.objectShare == 0 and rail.cueShare == 1)
	end,

	["a jump shot's trace skips the ball it clears and matches the simulation"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local function layout()
			return Simulation.newState(
				geometry,
				{ Ball.new(0, -30, 0), Ball.new(1, -18, 0), Ball.new(2, 0, 0) }
			)
		end
		for _, case in
			{
				{ power = 0.65, elevation = 45 },
				{ power = 0.8, elevation = 45 },
				{ power = 0.9, elevation = 60 },
				{ power = 0.6, elevation = 60 },
				{ power = 0.4, elevation = 45 },
				{ power = 0.3, elevation = 30 },
				{ power = 0.65 },
			}
		do
			local shot = { angle = 0, power = case.power, elevation = case.elevation }
			local trace = Aim.trace(layout(), shot)
			local result = Simulation.runHeadless(layout(), shot)
			-- The first thing the cue ball meets in the simulation: a ball, a cushion, or the
			-- floor. The guideline shows exactly that.
			local kind, id = "none", nil
			for _, ev in result.events do
				if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
					kind, id = "ball", if ev.ball == 0 then ev.other else ev.ball
					break
				elseif ev.type == "railHit" and ev.ball == 0 then
					kind = "rail"
					break
				elseif ev.type == "offTable" and ev.ball == 0 then
					kind = "off"
					break
				end
			end
			H.expect(
				trace.contact == kind and trace.objectId == id,
				("power %.2f at %s degrees: traced %s %s, simulated %s %s"):format(
					case.power,
					tostring(case.elevation),
					trace.contact,
					tostring(trace.objectId),
					kind,
					tostring(id)
				)
			)
			if id == 2 then
				H.expect(#trace.landings >= 1 or trace.airborne, "a jump shows where it comes down")
			end
		end
	end,

	["a jump that would fly over a cushion is traced as off the table"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local state = Simulation.newState(geometry, { Ball.new(0, -30, 0) })
		local shot = { angle = 0, power = 1, elevation = 60 }
		local trace = Aim.trace(state, shot)
		local result = Simulation.runHeadless(state, shot)
		H.expect(trace.contact == "off" and trace.airborne, "traced off the table")
		H.expect(result.finalBalls[1].offTable, "and it does fly off")
	end,

	["a jump's hops chain from the cue ball to each landing and clear the ball jumped"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local g = Config.Physics.Gravity
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(
			geometry,
			{ Ball.new(0, -30, 0), Ball.new(1, -18, 0), Ball.new(2, 0, 0) }
		)
		local trace = Aim.trace(state, { angle = 0, power = 0.8, elevation = 45 })
		H.expect(#trace.hops >= 1, "a raised hard shot has hops")
		local first = trace.hops[1]
		H.expect(first.x == -30 and first.y == 0, "the first hop starts at the cue ball")
		local function ends(hop: any): (number, number, number)
			local t = hop.seconds
			return hop.x + hop.vx * t, hop.y + hop.vy * t, hop.z + hop.vz * t - 0.5 * g * t * t
		end
		for i, hop in trace.hops do
			local x, y, z = ends(hop)
			local nextHop = trace.hops[i + 1]
			if nextHop then
				H.expect(
					math.abs(x - nextHop.x) < 1e-6 and math.abs(y - nextHop.y) < 1e-6,
					"hop " .. i .. " ends where the next starts"
				)
			end
			local landing = trace.landings[i]
			if landing then
				H.expect(
					math.abs(x - landing.x) < 1e-6 and math.abs(z) < 1e-6,
					"hop " .. i .. " ends on the cloth at its landing"
				)
			end
		end
		-- Over ball 1 (x = -18) the cue ball's bottom is above the other ball's top.
		local hop = first
		local t = (-18 - hop.x) / hop.vx
		if t > 0 and t < hop.seconds then
			local z = hop.z + hop.vz * t - 0.5 * g * t * t
			H.expect(z > 2 * R - 1e-6, ("clears ball 1 (bottom %.2f in)"):format(z))
		end
	end,

	["a flat shot has no hops"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local state = Simulation.newState(geometry, { Ball.new(0, -30, 0), Ball.new(1, 0, 0) })
		local trace = Aim.trace(state, { angle = 0, power = 0.8 })
		H.expect(#trace.hops == 0, "no hops on the cloth")
	end,

	["a launch ability's scale stretches a jump's flight along the cloth, not its height"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local state = Simulation.newState(geometry, { Ball.new(0, -40, 0) })
		local shot = { angle = 0, power = 0.8, elevation = 45 }
		local plain = Aim.trace(state, shot)
		local fire = Aim.trace(state, shot, 2)
		local a, b = plain.hops[1], fire.hops[1]
		H.expect(a ~= nil and b ~= nil, "both leave the cloth")
		H.expect(b.vx == 2 * a.vx and b.vy == 2 * a.vy, "twice the speed along the cloth")
		H.expect(b.vz == a.vz and b.seconds == a.seconds, "the same hop")
		H.expect(fire.landings[1].x > plain.landings[1].x + 1, "it lands further on")
	end,

	["bounce trace: mirrored off a cushion, angle in = angle out"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(geometry, { Ball.new(0, 0, 0) })
		local a = 0.3
		local bt = Aim.bounceTrace(state, { angle = a, power = 0.5 }, 300, 12)
		H.expect(#bt.points >= 3 and bt.bounces >= 1, "bounces on")
		local p1, p2, p3 = bt.points[1], bt.points[2], bt.points[3]
		H.near(p1.x, 0, 1e-9, "starts at the cue ball")
		H.near(p2.x, geometry.halfLength - R, 1e-6, "against the foot cushion")
		H.near(p2.y, (geometry.halfLength - R) * math.tan(a), 1e-6, "on the aim line")
		local dx, dy = p3.x - p2.x, p3.y - p2.y
		local len = math.sqrt(dx * dx + dy * dy)
		H.near(dx / len, -math.cos(a), 1e-6, "x mirrored")
		H.near(dy / len, math.sin(a), 1e-6, "y kept")
	end,

	["bounce trace: straight at a ball it ends there, as the plain trace"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local state = Simulation.newState(geometry, { Ball.new(0, -20, 0), Ball.new(1, 0, 1) })
		local t = Aim.trace(state, 0)
		local bt = Aim.bounceTrace(state, { angle = 0, power = 0.5 }, 300, 12)
		H.expect(bt.ending == "ball" and bt.objectId == 1 and bt.bounces == 0, "the 1, first")
		H.expect(#bt.points == 2, "one leg")
		H.near(bt.points[2].x, t.ghostX, 1e-9, "ghost x")
		H.near(bt.points[2].y, t.ghostY, 1e-9, "ghost y")
		H.near(bt.objectDirX, t.objectDirX, 1e-9, "object line x")
		H.near(bt.objectDirY, t.objectDirY, 1e-9, "object line y")
		H.near(bt.cueDirY, t.cueDirY, 1e-9, "cue ball's line")
	end,

	["bounce trace: a kick off the side cushion meets the ball behind it"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		-- Aimed at the 1's mirror image in the top cushion line: a full hit after one bounce.
		local wall = geometry.halfWidth - R
		local state = Simulation.newState(geometry, { Ball.new(0, -40, 0), Ball.new(1, 20, 0) })
		local angle = math.atan2(2 * wall, 60)
		local bt = Aim.bounceTrace(state, { angle = angle, power = 0.5 }, 300, 12)
		H.expect(bt.ending == "ball" and bt.objectId == 1, "the 1: " .. bt.ending)
		H.expect(bt.bounces == 1 and #bt.points == 3, "one cushion on the way")
		H.near(bt.points[2].y, wall, 1e-6, "off the top cushion")
		H.near(bt.points[2].x, -10, 1e-6, "halfway along")
		-- A full hit: the 1 heads on along the cue ball's line after the bounce.
		local hx, hy = 30, -wall
		local hl = math.sqrt(hx * hx + hy * hy)
		H.near(bt.objectDirX, hx / hl, 1e-6, "object line x")
		H.near(bt.objectDirY, hy / hl, 1e-6, "object line y")
	end,

	["bounce trace: straight down a corner pocket's middle, it ends in the pocket"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local corner = geometry.pockets[3] -- top right
		local state = Simulation.newState(geometry, { Ball.new(0, corner.x - 20, corner.y - 20) })
		local bt = Aim.bounceTrace(state, { angle = math.pi / 4, power = 0.5 }, 300, 12)
		H.expect(bt.ending == "pocket" and bt.pocket == corner.id, "in the corner: " .. bt.ending)
		H.expect(bt.bounces == 0 and #bt.points == 2, "no cushion on the way")
		local last = bt.points[2]
		local d = math.sqrt((last.x - corner.x) ^ 2 + (last.y - corner.y) ^ 2)
		H.near(d, corner.radius, 1e-6, "ends on the rim")
	end,

	["bounce trace: the length and bounce caps end the line"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local R = Config.Balls.RadiusInches
		local state = Simulation.newState(geometry, { Ball.new(0, 0, 0) })
		local short = Aim.bounceTrace(state, { angle = 0.3, power = 0.5 }, 30, 12)
		H.expect(short.ending == "limit" and short.bounces == 0, "the length cap first")
		local p = short.points[2]
		H.near(math.sqrt(p.x * p.x + p.y * p.y), 30, 1e-9, "30 in long")
		local two = Aim.bounceTrace(state, { angle = 0.3, power = 0.5 }, 1000, 2)
		H.expect(two.ending == "limit" and two.bounces == 2, "two cushions: " .. two.ending)
		H.expect(#two.points == 4, "ends at the third cushion")
		H.near(math.abs(two.points[4].x), geometry.halfLength - R, 1e-6, "on the far cushion")
	end,

	["bounce trace: a jump that meets a ball in the air ends there"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local shot = { angle = 0, power = 0.6, elevation = 45 }
		local state = Simulation.newState(geometry, { Ball.new(0, -40, 0), Ball.new(1, -30, 0) })
		local bt = Aim.bounceTrace(state, shot, 300, 12)
		H.expect(bt.flight ~= nil and (bt.flight :: any).airborne, "met in the air")
		H.expect(bt.ending == "air" and bt.objectId == 1, "ends at the 1: " .. bt.ending)
		H.expect(#bt.points == 0, "never rolls")
	end,

	["bounce trace: a jump over nothing rolls on from its last touchdown"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local shot = { angle = 0.2, power = 0.6, elevation = 45 }
		local state = Simulation.newState(geometry, { Ball.new(0, -40, 0) })
		local t = Aim.trace(state, shot)
		local bt = Aim.bounceTrace(state, shot, 300, 12)
		H.expect(#t.landings >= 1 and not t.airborne, "it lands")
		local land = t.landings[#t.landings]
		H.near(bt.points[1].x, land.x, 1e-9, "from the last touchdown, x")
		H.near(bt.points[1].y, land.y, 1e-9, "from the last touchdown, y")
		H.expect(#bt.points >= 2 and bt.bounces >= 1, "then on off the cushions")
	end,
}
