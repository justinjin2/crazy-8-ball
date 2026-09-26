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

--- The swap bump: 1 at SkySwap, easing to 0 by Width either side of it.
function LightCycle.swapBump(blend: number, lighting: any): number
	local d = math.abs(blend - lighting.SkySwap) / lighting.SwapHaze.Width
	if d >= 1 then
		return 0
	end
	return ease(1 - d)
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
--- GeographicLatitude and ClockTime from SunPath). Around SkySwap, where the sky's images change
--- in one frame, SwapHaze thickens the Atmosphere and dims the sky's light on the scene so the
--- change hides in a passing haze.
function LightCycle.state(blend: number, lighting: any): { [string]: any }
	local out = mix(lighting.Day, lighting.Sunset, blend, blend >= lighting.SkySwap)
	out.GeographicLatitude, out.ClockTime = LightCycle.sun(blend, lighting.SunPath)
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
