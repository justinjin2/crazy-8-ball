--!strict
-- Guideline trace tests: initial launch ray and shared collision geometry. Swerve later
-- bends the physical path, so distant grazing-contact identity is not promised.

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

	["side-spin tracing shares the exact launch ray and preserves geometric object direction"] = function()
		local Config, Ball, _, Simulation, Aim, geometry = setup()
		local Cue = H.require("Physics.Cue")
		for _, side in { -0.5, 0.5 } do
			local shot = { angle = 0, power = 0.8, spin = { x = side, y = 0 } }
			local dx, dy = Cue.launchDirection(shot)
			local state = Simulation.newState(
				geometry,
				{ Ball.new(0, -20, 0), Ball.new(1, -20 + 8 * dx, 8 * dy) }
			)
			local trace = Aim.trace(state, shot)
			local distance = 8 - 2 * Config.Balls.RadiusInches
			H.expect(trace.contact == "ball" and trace.objectId == 1, "short direct launch-ray hit")
			H.near(trace.ghostX, -20 + distance * dx, 1e-8, "squirted ghost x")
			H.near(trace.ghostY, distance * dy, 1e-8, "squirted ghost y")
			H.near(trace.objectDirX, dx, 1e-8, "geometric object line x")
			H.near(trace.objectDirY, dy, 1e-8, "geometric object line y")
			local result = Simulation.run(state, shot)
			H.expect(
				result.firstContact == trace.objectId,
				"nearby first-contact identity survives slight swerve"
			)
		end
	end,

	["a level pure-side shot follows its squirted ray up to first contact"] = function()
		local _, Ball, _, Simulation, Aim, geometry = setup()
		local Cue = H.require("Physics.Cue")
		local shot = { angle = 0.15, power = 0.6, spin = { x = 0.5, y = 0 }, elevation = 0 }
		local dx, dy = Cue.launchDirection(shot)
		local state = Simulation.newState(
			geometry,
			{ Ball.new(0, -20, 0), Ball.new(1, -20 + 20 * dx, 20 * dy) }
		)
		local trace = Aim.trace(state, shot)
		local result = Simulation.run(state, shot)
		H.expect(
			result.firstContact == trace.objectId,
			"level pure-side shot has no swerve before contact"
		)
		H.near(
			(trace.ghostY - trace.startY) / (trace.ghostX - trace.startX),
			dy / dx,
			1e-10,
			"ray slope"
		)
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
