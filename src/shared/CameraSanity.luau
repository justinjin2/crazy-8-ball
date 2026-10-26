--!strict
-- CameraSanity: can Roblox's camera script read this camera pose, and a readable one near it
-- (src/client/CameraGuard). Pure: plain numbers, no Instances, so it runs in Lune
-- (tests/camera_sanity_test.luau).
--
-- Roblox's camera script builds each frame from the camera's last look direction: BaseCamera:682
-- clamps the pitch between bounds made from math.asin(LookVector.Y). A pose looking straight
-- down whose rotation is a hair off orthonormal has LookVector.Y = -1.0000002, math.asin gives
-- NaN, the clamp throws, the frame never writes a new CFrame, and so it throws again every frame
-- after: the view is frozen for good and the error report counts one error a frame (2026-10-25:
-- 75K a day; one stuck player made a 100K spike in half an hour). The table camera's overhead
-- view (calling a pocket for the 8) looks straight down, and easing into it leaves about a third
-- of its frames past vertical (measured in Studio, 48,400 poses). Roblox refuses a NaN CFrame
-- on the camera, so past vertical is the case that reaches it.

local CameraSanity = {}

--- A real number: not NaN and not infinite.
function CameraSanity.finite(x: number): boolean
	return math.abs(x) < math.huge
end

--- Three real numbers.
function CameraSanity.finite3(x: number, y: number, z: number): boolean
	return CameraSanity.finite(x) and CameraSanity.finite(y) and CameraSanity.finite(z)
end

--- A look direction Roblox's camera can take: real numbers, and math.asin of its height is real.
function CameraSanity.lookOk(x: number, y: number, z: number): boolean
	return CameraSanity.finite3(x, y, z) and math.abs(y) <= 1
end

--- A look direction just off vertical for a camera whose look (height `y`) is past it, with
--- the same heading: the screen's up (ux, uz) is the way ahead for a camera looking down, and
--- its down for one looking up. `maxHeight` is how far toward vertical it may stay (the sine
--- of the pitch, under 1). A heading with no length (or none) looks down -Z, Roblox's default.
function CameraSanity.tilted(
	y: number,
	ux: number,
	uz: number,
	maxHeight: number
): (number, number, number)
	local sign = if y < 0 then -1 else 1
	local fx, fz = -sign * ux, -sign * uz
	local length = math.sqrt(fx * fx + fz * fz)
	if not CameraSanity.finite(length) or length < 1e-3 then
		fx, fz, length = 0, -1, 1
	end
	local flat = math.sqrt(1 - maxHeight * maxHeight)
	return fx / length * flat, sign * maxHeight, fz / length * flat
end

return CameraSanity
