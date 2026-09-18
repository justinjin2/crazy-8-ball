--!strict
-- Cue: turns shot inputs (angle, power, spin offset) into the cue ball's initial state.
-- This is the only place a player's inputs touch the simulation.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Ball)

type Ball = Ball.Ball

local Cue = {}

export type Shot = {
	angle: number, -- radians, 0 = towards +x (the foot rail), counter-clockwise positive
	power: number, -- 0..1
	spin: { x: number, y: number }?, -- strike offset in ball radii: x = side (right +), y = top (+) / back (-)
}

--- Cue ball speed for a power value in 0..1.
function Cue.speedForPower(power: number): number
	local C = Config.Cue
	local p = math.clamp(power, 0, 1)
	return C.MinSpeed + (C.MaxSpeed - C.MinSpeed) * (p ^ C.PowerCurve)
end

--- Clamp a spin offset to the miscue limit (a disc of radius MaxSpinOffset).
function Cue.clampSpin(sx: number, sy: number): (number, number)
	local limit = Config.Cue.MaxSpinOffset
	local len = math.sqrt(sx * sx + sy * sy)
	if len > limit then
		return sx / len * limit, sy / len * limit
	end
	return sx, sy
end

--- Apply the strike to the cue ball in place. Returns the speed given.
function Cue.strike(cueBall: Ball, shot: Shot): number
	local R = Config.Balls.RadiusInches
	local speed = Cue.speedForPower(shot.power)
	local dx, dy = math.cos(shot.angle), math.sin(shot.angle)

	cueBall.vx = dx * speed
	cueBall.vy = dy * speed

	local sx, sy = 0, 0
	if shot.spin then
		sx, sy = Cue.clampSpin(shot.spin.x, shot.spin.y)
	end
	local k = Config.Cue.SpinFactor * speed / R
	-- Top spin (+sy) spins the ball the way it would roll forward: axis = z-hat cross d-hat.
	cueBall.wx = -dy * k * sy
	cueBall.wy = dx * k * sy
	-- Side spin: hitting the right of the ball turns it counter-clockwise seen from above.
	cueBall.wz = k * sx
	return speed
end

return Cue
