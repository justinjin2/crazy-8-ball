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
	elevation: number?, -- degrees above the cloth; internal/test override, bounded by Config
	ability: string?, -- server-authorized catalog id; Simulation resolves per-shot material
}

--- Horizontal centre-hit ball speed at the configured elevation, retained for UI/audio.
function Cue.speedForPower(power: number): number
	local C = Config.Cue
	local p = math.clamp(power, 0, 1)
	return C.MinSpeed + (C.MaxSpeed - C.MinSpeed) * (p ^ C.PowerCurve)
end

--- The power bar controls cue-stick speed; off-centre strikes give less ball speed.
function Cue.stickSpeedForPower(power: number): number
	local C = Config.Cue
	return C.MinStickSpeed
		+ (C.MaxStickSpeed - C.MinStickSpeed) * math.clamp(power, 0, 1) ^ C.PowerCurve
end

--- Free-path travel bound to rest, including draw/follow and swerve. Angular velocity is in the
--- launch frame: +x is initial travel, +y is left. Project table-frame spin before calling.
--- Exact for straight travel without reversal; conservative for a curved sliding path.
function Cue.rollOutDistance(speed: number, wx: number?, wy: number?): number
	if speed < 0 then
		return 0
	end
	local P = Config.Physics
	local R = Config.Balls.RadiusInches
	local ux, uy = speed - R * (wy or 0), R * (wx or 0)
	local slip = math.sqrt(ux * ux + uy * uy)
	if slip <= P.SlideEpsilon then
		return speed * speed / (2 * P.RollingFriction * P.Gravity)
	end
	local decel = P.SlidingFriction * P.Gravity
	local slideTime = slip / (3.5 * decel)
	local rollingX, rollingY = speed - ux / 3.5, -uy / 3.5
	local rollingSpeed = math.sqrt(rollingX * rollingX + rollingY * rollingY)
	-- Velocity changes linearly while sliding. Convexity of its magnitude bounds the
	-- travelled arc by this trapezoid, with equality for straight, non-reversing travel.
	local sliding = 0.5 * (speed + rollingSpeed) * slideTime
	local rolling = (rollingX * rollingX + rollingY * rollingY)
		/ (2 * P.RollingFriction * P.Gravity)
	return sliding + rolling
end

--- Clamp a spin offset to the miscue limit (a disc of radius MaxSpinOffset).
function Cue.clampSpin(sx: number, sy: number): (number, number)
	local limit = Config.Cue.MaxSpinOffset
	-- Scale before squaring: the server accepts finite numbers and even finite inputs
	-- can overflow sx*sx. Preserve their direction when clamping very large offsets.
	local scale = math.max(math.abs(sx), math.abs(sy))
	if scale == 0 then
		return 0, 0
	end
	local nx, ny = sx / scale, sy / scale
	local len = math.sqrt(nx * nx + ny * ny)
	if scale > limit / len then
		return nx / len * limit, ny / len * limit
	end
	return sx, sy
end

--- Unit launch direction with squirt opposite the tip offset (TP A.31). Positive x spin
--- is the player's right, so its launch deflection is left: positive table-plane angle.
function Cue.launchDirection(shot: Shot): (number, number)
	local sx = 0
	if shot.spin then
		sx = Cue.clampSpin(shot.spin.x, shot.spin.y)
	end
	local remaining = 1 - sx * sx
	local squirt =
		math.atan2(2.5 * sx * math.sqrt(remaining), 1 + Config.Cue.EndmassRatio + 2.5 * remaining)
	local angle = shot.angle + squirt
	return math.cos(angle), math.sin(angle)
end

--- Apply the strike to the cue ball in place. Returns the speed given.
function Cue.strike(cueBall: Ball, shot: Shot): number
	local C = Config.Cue
	local R = Config.Balls.RadiusInches
	local sx, sy = 0, 0
	if shot.spin then
		sx, sy = Cue.clampSpin(shot.spin.x, shot.spin.y)
	end
	local theta =
		math.rad(math.clamp(shot.elevation or C.CueElevationDegrees, 0, C.MaxElevationDegrees))
	local cos, sin = math.cos(theta), math.sin(theta)
	local c = math.sqrt(1 - sx * sx - sy * sy)
	local verticalLever = sy * cos - c * sin
	local massRatio = Config.Balls.MassOunces / C.StickMassOunces
	local K = 1 + massRatio + 2.5 * (sx * sx + verticalLever * verticalLever)
	-- TP A.30 equations 19/23: inelastic energy efficiency, calibrated by tip COR at
	-- centre ball. Pooltool supplies the elevated-cue lever arms. No vertical flight here.
	local e = C.TipRestitution
	local eta = ((1 - massRatio * e) ^ 2 + massRatio * (1 + e) ^ 2) / (1 + massRatio) ^ 2
	local radicand = 1 - (1 - eta) / massRatio * K
	local impulsePerMass = Cue.stickSpeedForPower(shot.power)
		* (1 + math.sqrt(math.max(0, radicand)))
		/ K
	local speed = impulsePerMass * cos
	local launchX, launchY = Cue.launchDirection(shot)
	cueBall.vx, cueBall.vy, cueBall.vz = launchX * speed, launchY * speed, 0
	local dx, dy = math.cos(shot.angle), math.sin(shot.angle)
	local angular = 2.5 * impulsePerMass / R
	-- r cross J, in forward/left/up axes. Rotate spin by the stick's direction, not the
	-- squirted launch: their mismatch and the tilted side-spin axis produce real swerve.
	local forwardSpin, leftSpin = angular * sx * sin, angular * verticalLever
	cueBall.wx = dx * forwardSpin - dy * leftSpin
	cueBall.wy = dy * forwardSpin + dx * leftSpin
	cueBall.wz = angular * sx * cos
	return speed
end

return Cue
