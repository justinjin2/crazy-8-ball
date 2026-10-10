--!strict
-- PullMath: the plain arithmetic behind the Mythic and Secret pull cutscenes (PullMythic,
-- PullSecret; docs/prompts/PULL_CUTSCENES_V2.md): bullet time's warped clock, a racing
-- heartbeat's beats, the lights dying one by one down a hall, a dolly zoom's field of view,
-- a homing curve's ease and a glitch's on/off pattern. Pure: no Instances and no Roblox types,
-- so tests/pull_math_test.luau runs it in Lune. Visual only (never the simulation).

local PullMath = {}

--- The world clock under a slow-motion window. Real time `t` runs at full speed until
--- `from`, eases down (linearly, over `ramp` seconds) to `speed` of normal, holds there, and
--- eases back up to full speed by `to`. Returns the world time: `t` itself before the window,
--- and behind `t` by the time the slow part swallowed after it. `ramp` is clamped to half the
--- window.
function PullMath.warp(t: number, from: number, to: number, speed: number, ramp: number): number
	if t <= from or to <= from then
		return t
	end
	local r = math.clamp(ramp, 0, (to - from) / 2)
	local slow = 1 - speed
	-- The world time gained over each piece, in order.
	local downEnd = from + r
	local upFrom = to - r
	if t <= downEnd then
		local x = t - from
		return from + x - (if r > 0 then slow * x * x / (2 * r) else 0)
	end
	local w = from + r - slow * r / 2 -- the whole ramp down
	if t <= upFrom then
		return w + (t - downEnd) * speed
	end
	w += (upFrom - downEnd) * speed
	if t <= to then
		local x = t - upFrom
		return w + speed * x + (if r > 0 then slow * x * x / (2 * r) else 0)
	end
	w += speed * r + slow * r / 2 -- the whole ramp up
	return w + (t - to)
end

--- The speed of the warped clock at `t` (1 = normal), as warp() runs it.
function PullMath.warpSpeed(
	t: number,
	from: number,
	to: number,
	speed: number,
	ramp: number
): number
	if t <= from or t >= to or to <= from then
		return 1
	end
	local r = math.clamp(ramp, 0, (to - from) / 2)
	if r > 0 and t < from + r then
		return 1 - (1 - speed) * (t - from) / r
	elseif r > 0 and t > to - r then
		return speed + (1 - speed) * (t - (to - r)) / r
	end
	return speed
end

--- Heartbeat times from `from` to `to` (both included when a beat lands on them), the gap
--- between beats shrinking evenly from `firstGap` to `lastGap` as the beats go by: a heart
--- racing. Gaps are never below 0.05 s.
function PullMath.beats(from: number, to: number, firstGap: number, lastGap: number): { number }
	local out = {}
	local t = from
	local span = math.max(to - from, 1e-6)
	while t <= to + 1e-9 do
		table.insert(out, t)
		local u = math.clamp((t - from) / span, 0, 1)
		t += math.max(0.05, firstGap + (lastGap - firstGap) * u)
		if #out > 1000 then
			break
		end
	end
	return out
end

--- When each of `count` lights dies, the first (the farthest) at `from` and the last at
--- `to`: the gaps shrink as the dark comes closer (`power` > 1 speeds it up more; 1 is even).
function PullMath.lightsOut(count: number, from: number, to: number, power: number): { number }
	local out = {}
	for i = 1, count do
		local u = if count > 1 then (i - 1) / (count - 1) else 1
		table.insert(out, from + (to - from) * (1 - (1 - u) ^ math.max(power, 1e-3)))
	end
	return out
end

--- A dolly zoom's field of view (degrees) at `distance` from the subject: the angle at which
--- the subject keeps the size it had at `startDistance` with `startFov`, clamped to
--- [`minFov`, `maxFov`]. Moving in widens it, so the hall behind stretches away.
function PullMath.dollyFov(
	distance: number,
	startDistance: number,
	startFov: number,
	minFov: number,
	maxFov: number
): number
	local k = math.tan(math.rad(startFov) / 2) * startDistance
	local fov = math.deg(2 * math.atan(k / math.max(distance, 1e-3)))
	return math.clamp(fov, minFov, maxFov)
end

--- 0..1 along a homing flight that starts slow and arrives fast (an object pulled in):
--- `u` (0..1) raised to `power`.
function PullMath.homing(u: number, power: number): number
	return math.clamp(u, 0, 1) ^ math.max(power, 1e-3)
end

--- Whether a glitch is on at `t`: the timeline is cut into slots of `slot` seconds, and a slot
--- is on when its hash (from `seed`) falls under `chance` (0..1). The same t and seed always
--- answer the same, so a held frame does not flicker.
function PullMath.glitchOn(t: number, slot: number, chance: number, seed: number): boolean
	local n = math.floor(t / math.max(slot, 1e-3))
	return PullMath.hash(n, seed) < chance
end

--- A repeatable number in 0..1 from an integer `n` and a `seed`: a few rounds of the
--- Park-Miller generator (every product stays exact in a double).
function PullMath.hash(n: number, seed: number): number
	local m = 2147483647
	local x = (math.floor(n) % m * 7919 + math.floor(seed) % m * 104729 + 1) % m
	for _ = 1, 3 do
		x = (x * 48271) % m
	end
	return (x - 1) / (m - 1)
end

return PullMath
