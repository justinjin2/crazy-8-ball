--!strict
-- Vec: tiny 2D vector helpers on plain numbers. No Roblox types, so it runs in Lune.
-- Hot loops in Simulation work on raw fields instead; this is for readability elsewhere.

local Vec = {}

export type Vec = { x: number, y: number }

function Vec.new(x: number, y: number): Vec
	return { x = x, y = y }
end

function Vec.fromAngle(angle: number, length: number?): Vec
	local len = length or 1
	return { x = math.cos(angle) * len, y = math.sin(angle) * len }
end

function Vec.add(a: Vec, b: Vec): Vec
	return { x = a.x + b.x, y = a.y + b.y }
end

function Vec.sub(a: Vec, b: Vec): Vec
	return { x = a.x - b.x, y = a.y - b.y }
end

function Vec.scale(a: Vec, s: number): Vec
	return { x = a.x * s, y = a.y * s }
end

function Vec.dot(a: Vec, b: Vec): number
	return a.x * b.x + a.y * b.y
end

function Vec.length(a: Vec): number
	return math.sqrt(a.x * a.x + a.y * a.y)
end

function Vec.normalize(a: Vec): Vec
	local len = Vec.length(a)
	if len < 1e-12 then
		return { x = 0, y = 0 }
	end
	return { x = a.x / len, y = a.y / len }
end

--- Rotate 90 degrees counter-clockwise (z-hat cross a).
function Vec.perp(a: Vec): Vec
	return { x = -a.y, y = a.x }
end

function Vec.angle(a: Vec): number
	return math.atan2(a.y, a.x)
end

return Vec
