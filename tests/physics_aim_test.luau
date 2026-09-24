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
}
