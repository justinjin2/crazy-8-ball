--!strict
-- MapMotion: the map's ambient motion as pure functions of time (no Instances, no clock of its
-- own), so every client computes the same thing from the server's clock and the Lune tests
-- can check it. For now the sailboats (Config.Map.Near.Boat): each drifts round a long slow
-- ellipse at sea, heading along it, bobbing and rocking a little on the swell.

local MapMotion = {}

export type Path = {
	Centre: { number },
	Radius: { number },
	Seconds: number,
	Phase: number,
	Direction: number,
}

export type Pose = {
	x: number,
	y: number,
	z: number,
	yaw: number, -- radians about +Y: the bow (the boat's +Z) along the heading
	pitch: number, -- radians about the boat's X
	roll: number, -- radians about the boat's Z
}

--- Where boat `path` is at time `t` (seconds; any origin, e.g. workspace:GetServerTimeNow()),
--- with the swell settings `boat` (Config.Map.Near.Boat).
function MapMotion.boatPose(path: Path, t: number, boat: any): Pose
	local turn = 2 * math.pi
	local angle = turn * (path.Phase + path.Direction * t / path.Seconds)
	local a, b = path.Radius[1], path.Radius[2]
	local c, s = math.cos(angle), math.sin(angle)
	-- The heading: d(position)/d(angle), times the direction of travel.
	local vx, vz = -a * s * path.Direction, b * c * path.Direction
	-- Each boat's swell runs off its own phase, so they never rock in step.
	local offset = path.Phase * 17.0
	return {
		x = path.Centre[1] + a * c,
		y = boat.SeaY + boat.BobHeight * math.sin(turn * (t + offset) / boat.BobSeconds),
		z = path.Centre[2] + b * s,
		yaw = math.atan2(vx, vz),
		pitch = math.rad(boat.PitchDegrees) * math.sin(turn * (t + offset) / boat.PitchSeconds),
		roll = math.rad(boat.RollDegrees) * math.sin(turn * (t + offset) / boat.RollSeconds),
	}
end

--- The fastest boat `path` ever moves (studs a second), for the tests and the budget check.
function MapMotion.topSpeed(path: Path): number
	return 2 * math.pi * math.max(path.Radius[1], path.Radius[2]) / path.Seconds
end

return MapMotion
