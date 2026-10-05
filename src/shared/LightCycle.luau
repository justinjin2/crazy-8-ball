--!strict
-- LightCycle: the map's day, sunset and night cycle as pure numbers (Config.Lighting; the
-- rooftop brief, Stage 7; night added 2026-10-05). blend(t) says where the world is at a moment
-- of the server's clock (0 Day, 1 Sunset, 2 Night, fractions in between); state(blend) mixes
-- the neighbouring presets into the whole light state for that moment. Pure Luau (no Instances,
-- no Color3, no clocks): Lune tests it, and every client computes the same state from the same
-- server time with nothing sent over the network. MapLighting puts a state onto the place;
-- DayCycle drives it on each client.

local LightCycle = {}

export type Cycle = {
	Day: number,
	Fade: number,
	Sunset: number,
	Night: number,
	Dawn: number,
	Speed: number,
	Rate: number,
	Look: number,
}

export type SunKey = { Blend: number, GeographicLatitude: number, ClockTime: number }

-- A developer's hold (DevCommands): the blend shown when it was set (From), the scaled clock
-- then (At), and the blend it eases to and stays at (Goal), or none to ease back into the cycle.
export type Hold = { From: number, At: number, Goal: number? }

-- The presets by blend: 0 Day, 1 Sunset, 2 Night (Config.Lighting's keys).
LightCycle.PRESETS = { "Day", "Sunset", "Night" }

-- The cycle's stretches in order, as { seconds, from blend, to blend }: a hold where the two
-- match, a fade where they differ. Night goes back to day through a short dawn (the sunset's
-- light), so every fade is between neighbouring presets.
local function stretches(cycle: Cycle): { { number } }
	return {
		{ cycle.Day, 0, 0 },
		{ cycle.Fade, 0, 1 },
		{ cycle.Sunset, 1, 1 },
		{ cycle.Fade, 1, 2 },
		{ cycle.Night, 2, 2 },
		{ cycle.Fade, 2, 1 },
		{ cycle.Dawn, 1, 1 },
		{ cycle.Fade, 1, 0 },
	}
end

-- One whole cycle in seconds: the day, the sunset, the night, the dawn and the four fades.
function LightCycle.period(cycle: Cycle): number
	return cycle.Day + cycle.Sunset + cycle.Night + cycle.Dawn + 4 * cycle.Fade
end

-- Smoothstep: a fade starts and ends gently.
local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

--- Where the world is at time t (seconds; the caller scales the server's clock by
--- Cycle.Speed): 0 through the day, 1 through the sunset and the dawn, 2 through the night,
--- easing between them over each fade. The cycle starts at t = 0, so the same t gives the same
--- answer everywhere.
function LightCycle.blend(t: number, cycle: Cycle): number
	local s = t % LightCycle.period(cycle) -- floored: in [0, period) for any t
	for _, stretch in stretches(cycle) do
		local seconds, from, to = stretch[1], stretch[2], stretch[3]
		if s < seconds then
			return if from == to then from else from + (to - from) * ease(s / seconds)
		end
		s -= seconds
	end
	return 0 -- s rounded up to the period: the next day
end

--- A hold from a developer command's workspace attributes (Config.Lighting.Cycle.Hold), or
--- nil when none is set (the cycle runs).
function LightCycle.readHold(goal: any, from: any, at: any): Hold?
	if type(from) ~= "number" or type(at) ~= "number" then
		return nil
	end
	return { From = from, At = at, Goal = if type(goal) == "number" then goal else nil }
end

--- The blend shown at t: the cycle's, or under a hold, From easing to Goal over one Fade per
--- preset passed (so day to night passes through the sunset) and staying there; a hold with
--- no Goal eases from From back into the running cycle the same way.
function LightCycle.shown(t: number, cycle: Cycle, hold: Hold?): number
	local running = LightCycle.blend(t, cycle)
	if hold == nil then
		return running
	end
	local goal = if hold.Goal ~= nil then hold.Goal else running
	local seconds = cycle.Fade * math.max(1, math.abs(goal - hold.From))
	local k = math.clamp((t - hold.At) / seconds, 0, 1)
	return hold.From + (goal - hold.From) * ease(k)
end

--- The offset (scaled seconds, added to the scaled clock t) that puts the cycle at the very
--- start of its day now: an arena opens in daylight with the whole day ahead (designer,
--- 2026-09-28), then runs on like the lobby.
function LightCycle.offsetToDayStart(t: number, cycle: Cycle): number
	local period = LightCycle.period(cycle)
	return (period - t % period) % period
end

--- The sun at a blend: GeographicLatitude and ClockTime along the SunPath keyframes (by Blend,
--- rising, 0 to 2), straight between them and held past the ends.
function LightCycle.sun(blend: number, path: { SunKey }): (number, number)
	local first, last = path[1], path[#path]
	if blend <= first.Blend then
		return first.GeographicLatitude, first.ClockTime
	end
	for i = 2, #path do
		local a, b = path[i - 1], path[i]
		if blend <= b.Blend then
			local w = (blend - a.Blend) / (b.Blend - a.Blend)
			return a.GeographicLatitude + (b.GeographicLatitude - a.GeographicLatitude) * w,
				a.ClockTime + (b.ClockTime - a.ClockTime) * w
		end
	end
	return last.GeographicLatitude, last.ClockTime
end

--- The swap bump: 1 at each of SkySwaps, easing to 0 by Width either side of it.
function LightCycle.swapBump(blend: number, lighting: any): number
	local bump = 0
	for _, at in lighting.SkySwaps do
		local d = math.abs(blend - at) / lighting.SwapHaze.Width
		if d < 1 then
			bump = math.max(bump, ease(1 - d))
		end
	end
	return bump
end

--- Which sky shows at a blend: 0 Day's, 1 DuskSky, 2 Sunset's (how many swaps are passed).
function LightCycle.skyStage(blend: number, lighting: any): number
	local stage = 0
	for _, at in lighting.SkySwaps do
		if blend >= at then
			stage += 1
		end
	end
	return stage
end

local function isHex(value: any): boolean
	return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

--- A hex colour a share w of the way from a to b, each channel rounded ("#RRGGBB").
function LightCycle.mixHex(a: string, b: string, w: number): string
	local out = {}
	for i = 0, 2 do
		local ca = tonumber(a:sub(2 + i * 2, 3 + i * 2), 16) :: number
		local cb = tonumber(b:sub(2 + i * 2, 3 + i * 2), 16) :: number
		out[i + 1] = math.floor(ca + (cb - ca) * w + 0.5)
	end
	return ("#%02X%02X%02X"):format(out[1], out[2], out[3])
end

-- Day and Sunset mixed: numbers and hex colours a share w of the way, blocks recursed, and
-- anything else (the sky's image ids) Day's before the swap and Sunset's from it.
local function mix(
	a: { [string]: any },
	b: { [string]: any },
	w: number,
	swapped: boolean
): { [string]: any }
	local out: { [string]: any } = {}
	for key, va in a do
		local vb = b[key]
		if type(va) == "table" then
			out[key] = mix(va, vb, w, swapped)
		elseif type(va) == "number" then
			out[key] = va + (vb - va) * w
		elseif isHex(va) and isHex(vb) then
			out[key] = LightCycle.mixHex(va, vb, w)
		else
			out[key] = if swapped then vb else va
		end
	end
	return out
end

--- The whole light state at a blend (Config.Lighting's preset keys, plus the sun's
--- GeographicLatitude and ClockTime from SunPath). From 1 to 2 it is Sunset mixed toward Night
--- (the sky's images and other non-numbers Night's from half way). From 0 to 1: half way,
--- DuskWarm warms it. The sky's images are Day's, DuskSky's or Sunset's (skyStage). Round each
--- swap, where they change in one frame, SwapHaze thickens the Atmosphere and dims the sky's
--- light on the scene so the change hides in a passing haze.
function LightCycle.state(blend: number, lighting: any): { [string]: any }
	if blend > 1 then
		local w = math.min(blend, 2) - 1
		local night = mix(lighting.Sunset, lighting.Night, w, w >= 0.5)
		night.GeographicLatitude, night.ClockTime = LightCycle.sun(blend, lighting.SunPath)
		return night
	end
	local stage = LightCycle.skyStage(blend, lighting)
	local out = mix(lighting.Day, lighting.Sunset, blend, stage >= #lighting.SkySwaps)
	if stage > 0 and stage < #lighting.SkySwaps then
		for key, id in lighting.DuskSky do
			out.Sky[key] = id
		end
	end
	out.GeographicLatitude, out.ClockTime = LightCycle.sun(blend, lighting.SunPath)
	local warm = lighting.DuskWarm
	local d = math.abs(blend - 0.5) / warm.Width
	if d < 1 then
		local w = ease(1 - d) * warm.Amount
		for path, colour in warm.Colours do
			local block, key = path:match("^(%w+)%.(%w+)$")
			local target = if block then out[block] else out
			local name = key or path
			target[name] = LightCycle.mixHex(target[name], colour, w)
		end
	end
	local bump = LightCycle.swapBump(blend, lighting)
	if bump > 0 then
		local S = lighting.SwapHaze
		out.Atmosphere.Density += S.Density * bump
		out.Atmosphere.Haze += S.Haze * bump
		out.EnvironmentDiffuseScale *= 1 - S.Environment * bump
		out.EnvironmentSpecularScale *= 1 - S.Environment * bump
	end
	return out
end

return LightCycle
