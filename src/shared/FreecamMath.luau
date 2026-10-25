--!strict
-- FreecamMath: the lobby freecam's maths (designer, 2026-10-25: a free camera to film friends).
-- Pure: plain numbers, no Instances, so it runs in Lune (tests/freecam_math_test.luau).
--
-- The camera flies where it looks (a phone's thumbstick alone climbs by looking up) and stays
-- inside the rooftop: the union of Config.Freecam.Boxes, each pulled WallInsetStuds in from its
-- walls, below the safety walls' tops, so it can never pass a wall or rise to see the city.
-- Angles follow CFrame.fromOrientation(pitch, yaw, 0): yaw 0 looks down -Z, pitch up is +.

export type Box = {
	MinX: number,
	MaxX: number,
	MinZ: number,
	MaxZ: number,
	MinY: number,
	MaxY: number,
}

export type Bounds = { Boxes: { Box }, WallInsetStuds: number }

export type State = { x: number, y: number, z: number, yaw: number, pitch: number }

export type Input = {
	lookX: number, -- radians to turn right this step
	lookY: number, -- radians to tilt up this step
	moveX: number, -- right (-1..1), as ControlModule's move vector
	moveZ: number, -- back (-1..1): forward is -1, as ControlModule's move vector
	rise: number, -- up (-1..1)
	fast: boolean,
}

export type Tuning = {
	SpeedStuds: number,
	FastSpeedStuds: number,
	VerticalSpeedStuds: number,
	PitchLimitDegrees: number,
}

local FreecamMath = {}

local function clampBox(x: number, y: number, z: number, box: Box, inset: number)
	local minX, maxX = box.MinX + inset, box.MaxX - inset
	local minZ, maxZ = box.MinZ + inset, box.MaxZ - inset
	return math.clamp(x, minX, math.max(minX, maxX)),
		math.clamp(y, box.MinY, math.max(box.MinY, box.MaxY)),
		math.clamp(z, minZ, math.max(minZ, maxZ))
end

--- The point inside the bounds nearest to (x, y, z): itself when it is already inside a box;
--- otherwise the nearest point of the nearest box, so a push into a wall slides along it.
function FreecamMath.clamp(
	x: number,
	y: number,
	z: number,
	bounds: Bounds
): (number, number, number)
	local bestX, bestY, bestZ = x, y, z
	local best = math.huge
	for _, box in bounds.Boxes do
		local cx, cy, cz = clampBox(x, y, z, box, bounds.WallInsetStuds)
		local d = (cx - x) ^ 2 + (cy - y) ^ 2 + (cz - z) ^ 2
		if d < best then
			best = d
			bestX, bestY, bestZ = cx, cy, cz
		end
	end
	return bestX, bestY, bestZ
end

--- The camera's look direction for a yaw and pitch (a unit vector).
function FreecamMath.look(yaw: number, pitch: number): (number, number, number)
	local c = math.cos(pitch)
	return -math.sin(yaw) * c, math.sin(pitch), -math.cos(yaw) * c
end

--- The state `dt` seconds on: turned by the look input, the pitch held inside the limit, moved
--- toward where it looks (right, forward, up), then kept inside the bounds.
function FreecamMath.step(
	state: State,
	input: Input,
	dt: number,
	tuning: Tuning,
	bounds: Bounds
): State
	local limit = math.rad(tuning.PitchLimitDegrees)
	local yaw = state.yaw - input.lookX
	local pitch = math.clamp(state.pitch + input.lookY, -limit, limit)
	-- The flat move (a stick part-way moves part speed, never faster than full).
	local mx, mz = input.moveX, input.moveZ
	local size = math.sqrt(mx * mx + mz * mz)
	if size > 1 then
		mx, mz = mx / size, mz / size
	end
	local speed = if input.fast then tuning.FastSpeedStuds else tuning.SpeedStuds
	local fx, fy, fz = FreecamMath.look(yaw, pitch)
	local rx, rz = math.cos(yaw), -math.sin(yaw)
	local forward = -mz
	local rise = math.clamp(input.rise, -1, 1)
	local x = state.x + (rx * mx + fx * forward) * speed * dt
	local y = state.y + fy * forward * speed * dt + rise * tuning.VerticalSpeedStuds * dt
	local z = state.z + (rz * mx + fz * forward) * speed * dt
	x, y, z = FreecamMath.clamp(x, y, z, bounds)
	return { x = x, y = y, z = z, yaw = yaw, pitch = pitch }
end

return FreecamMath
