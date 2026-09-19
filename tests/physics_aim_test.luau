--!strict
-- Guideline trace tests: the predicted first contact must match the simulation.

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
}
