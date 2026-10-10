--!strict
-- PadMath: the pure helpers behind the controller's shot and the 8's pocket call
-- (src/client/Input.luau, src/client/MatchTargets.luau; designer, 2026-10-10). No Instances, no
-- clocks, no randomness; every list is walked in array order.
--
-- * The shot's power level: A held raises it and Y held lowers it, both at one steady rate (a
--   straight line, full in FillSeconds), clamped to 0..1. R2 shoots whatever it shows.
-- * Calling the 8: the left stick points from the table's middle on screen and the pocket that
--   way is picked; the D-pad steps to the nearest pocket that way from the one picked.

local PadMath = {}

-- A pocket on screen: its id and where it is drawn (pixels, y grows down).
export type Point = { id: number, x: number, y: number }

--- The power level after `dt` seconds with A (`up`) and Y (`down`) held: it moves dt /
--- fillSeconds each way; both held, or neither, leaves it. Always within 0..1.
function PadMath.stepPower(
	level: number,
	up: boolean,
	down: boolean,
	dt: number,
	fillSeconds: number
): number
	local direction = (if up then 1 else 0) - (if down then 1 else 0)
	if direction == 0 or dt <= 0 then
		return math.clamp(level, 0, 1)
	end
	return math.clamp(level + direction * dt / math.max(fillSeconds, 1e-3), 0, 1)
end

--- The pocket the stick points at: (sx, sy) is the stick (+y up), (cx, cy) the table's middle
--- on screen. The pocket whose direction from the middle is closest to the stick's wins (an
--- exact tie goes to the earlier one). Nil while the stick is inside `deadZone`.
function PadMath.pocketToward(
	points: { Point },
	cx: number,
	cy: number,
	sx: number,
	sy: number,
	deadZone: number
): number?
	local length = math.sqrt(sx * sx + sy * sy)
	if length <= deadZone then
		return nil
	end
	-- Screen y grows down, the stick's grows up.
	local dx, dy = sx / length, -sy / length
	local best: number? = nil
	local bestDot = -math.huge
	for _, point in points do
		local ox, oy = point.x - cx, point.y - cy
		local distance = math.sqrt(ox * ox + oy * oy)
		if distance > 1e-6 then
			local dot = (ox * dx + oy * dy) / distance
			if dot > bestDot + 1e-9 then
				best, bestDot = point.id, dot
			end
		end
	end
	return best
end

--- From pocket `fromId`, the nearest pocket that way on screen ((dx, dy) in screen pixels' axes,
--- y down): within about 63 degrees of the push, nearest first, a straight line preferred
--- (`acrossWeight` per pixel off the line). Stays on `fromId` when there is none that way.
function PadMath.stepToward(
	points: { Point },
	fromId: number,
	dx: number,
	dy: number,
	acrossWeight: number
): number
	local from: Point? = nil
	for _, point in points do
		if point.id == fromId then
			from = point
		end
	end
	if from == nil then
		return fromId
	end
	local best, bestScore = fromId, math.huge
	for _, to in points do
		if to.id ~= fromId then
			local ox, oy = to.x - from.x, to.y - from.y
			local along = ox * dx + oy * dy
			local across = math.abs(ox * dy - oy * dx)
			if along > 0 and across <= along * 2 then
				local score = along + across * acrossWeight
				if score < bestScore then
					best, bestScore = to.id, score
				end
			end
		end
	end
	return best
end

return PadMath
