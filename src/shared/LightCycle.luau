--!strict
-- LightCycle: the map's day and sunset cycle as pure numbers (Config.Lighting; the rooftop
-- brief, Stage 7). blend(t) says how far into sunset the world is at a moment of the server's
-- clock (0 Day, 1 Sunset); state(blend) mixes the Day and Sunset presets into the whole light
-- state for that moment. Pure Luau (no Instances, no Color3, no clocks): Lune tests it, and every
-- client computes the same state from the same server time with nothing sent over the network.
-- MapLighting puts a state onto the place; DayCycle drives it on each client.

local LightCycle = {}

export type Cycle = {
	Day: number,
	Fade: number,
	Sunset: number,
	Speed: number,
	Rate: number,
	Look: number,
}

export type SunKey = { Blend: number, GeographicLatitude: number, ClockTime: number }

-- One whole cycle in seconds: the day, a fade, the sunset and the fade back.
function LightCycle.period(cycle: Cycle): number
	return cycle.Day + cycle.Fade + cycle.Sunset + cycle.Fade
end

-- Smoothstep: a fade starts and ends gently.
local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

--- How far into sunset the world is at time t (seconds; the caller scales the server's clock
--- by Cycle.Speed): 0 through the day, easing up to 1 over the fade, 1 through the sunset and
--- easing back down. The cycle starts at t = 0, so the same t gives the same answer everywhere.
function LightCycle.blend(t: number, cycle: Cycle): number
	local s = t % LightCycle.period(cycle) -- floored: in [0, period) for any t
	if s < cycle.Day then
		return 0
	end
	s -= cycle.Day
	if s < cycle.Fade then
		return ease(s / cycle.Fade)
	end
	s -= cycle.Fade
	if s < cycle.Sunset then
		return 1
	end
	s -= cycle.Sunset
	return 1 - ease(s / cycle.Fade)
end

--- A new offset (scaled seconds, added to the scaled clock) that sends the cycle toward a hold,
--- "Day" or "Sunset", through its fade, from the light it shows now: t is the scaled clock and
--- offset the one in use. Holding the other state, the fade starts at once; half way through
--- the fade back, it turns round at the same blend; already on its way, nothing changes. The
--- cycle runs on from there. A developer's chat command sets it (DevCommands), so every client
--- moves together.
function LightCycle.offsetToward(t: number, offset: number, cycle: Cycle, hold: string): number
	local period = LightCycle.period(cycle)
	local s = (t + offset) % period
	local fadeIn, sunset = cycle.Day, cycle.Day + cycle.Fade
	local fadeOut = sunset + cycle.Sunset
	local target = s
	if hold == "Sunset" then
		if s < fadeIn then
			target = fadeIn -- from the day hold: the fade in starts now
		elseif s >= fadeOut then
			target = fadeIn + (period - s) -- mid fade out: the same blend on the fade in
		end
	else
		if s >= sunset and s < fadeOut then
			target = fadeOut -- from the sunset hold: the fade out starts now
		elseif s >= fadeIn and s < sunset then
			target = fadeOut + (sunset - s) -- mid fade in: the same blend on the fade out
		end
	end
	return (offset + target - s) % period
end

--- The sun at a blend: GeographicLatitude and ClockTime along the SunPath keyframes (by Blend,
--- rising), straight between them and held past the ends.
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

--- The whole light state at a blend (Config.Lighting's Day and Sunset keys, plus the sun's
--- GeographicLatitude and ClockTime from SunPath). Half way, DuskWarm warms it. The sky's images are Day's, DuskSky's or
--- Sunset's (skyStage). Round each swap, where they change in one frame, SwapHaze thickens the
--- Atmosphere and dims the sky's light on the scene so the change hides in a passing haze.
function LightCycle.state(blend: number, lighting: any): { [string]: any }
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
