--!strict
-- Checks the day, sunset and night cycle (src/shared/LightCycle.luau, Config.Lighting): the
-- timing of the cycle, the smooth fades, the developer holds, the mixing of the light states,
-- the sun's path and the haze that hides the sky's swap.

local H = require("./harness")

local function isHex(v: any): boolean
	return type(v) == "string" and v:match("^#%x%x%x%x%x%x$") ~= nil
end

-- The same keys and kinds of value in two blocks, recursively (b is named other).
local function sameShape(a: { [string]: any }, b: { [string]: any }, where: string, other: string)
	for key, va in a do
		local vb = b[key]
		H.expect(vb ~= nil, ("%s.%s is in Day but not %s"):format(where, key, other))
		H.expect(
			type(va) == type(vb),
			("%s.%s: Day and %s differ in kind"):format(where, key, other)
		)
		if type(va) == "table" then
			sameShape(va, vb, where .. "." .. key, other)
		elseif type(va) == "string" then
			H.expect(
				isHex(va) == isHex(vb),
				("%s.%s: a colour in one state only"):format(where, key)
			)
		end
	end
	for key in b do
		H.expect(a[key] ~= nil, ("%s.%s is in %s but not Day"):format(where, key, other))
	end
end

-- Every number and colour of state equals preset's (colours exactly, numbers to 1e-9).
local function matches(state: { [string]: any }, preset: { [string]: any }, where: string)
	for key, v in preset do
		if type(v) == "table" then
			matches(state[key], v, where .. "." .. key)
		elseif type(v) == "number" then
			H.near(state[key], v, 1e-9, where .. "." .. key)
		else
			H.expect(
				state[key] == v,
				("%s.%s: %s, not %s"):format(where, key, tostring(state[key]), tostring(v))
			)
		end
	end
end

return {
	["the cycle is a day, a sunset, a night and a dawn with fades, at its real speed"] = function()
		local LC = H.require("LightCycle")
		local C = H.require("Config").Lighting.Cycle
		H.expect(C.Speed == 1, "Cycle.Speed is test only: put it back to 1 before committing")
		H.expect(LC.period(C) == C.Day + C.Sunset + C.Night + C.Dawn + 4 * C.Fade, "the period")
		H.expect(C.Rate > 0 and C.Look > 0, "a rate and a look interval")
	end,

	["the blend holds through the day, sunset, night and dawn and eases between them"] = function()
		local LC = H.require("LightCycle")
		local C = {
			Day = 600,
			Fade = 60,
			Sunset = 300,
			Night = 300,
			Dawn = 30,
			Speed = 1,
			Rate = 12,
			Look = 2,
		}
		local P = LC.period(C)
		H.expect(P == 1470, "the period")
		H.near(LC.blend(0, C), 0, 0)
		H.near(LC.blend(599.9, C), 0, 0)
		H.near(LC.blend(630, C), 0.5, 1e-9, "half way through the fade to sunset")
		H.near(LC.blend(660, C), 1, 0)
		H.near(LC.blend(959.9, C), 1, 0)
		H.near(LC.blend(990, C), 1.5, 1e-9, "half way through the fade to night")
		H.near(LC.blend(1020, C), 2, 0, "night")
		H.near(LC.blend(1319.9, C), 2, 0, "still night")
		H.near(LC.blend(1350, C), 1.5, 1e-9, "half way through the fade to dawn")
		H.near(LC.blend(1380, C), 1, 0, "dawn")
		H.near(LC.blend(1409.9, C), 1, 0, "still dawn")
		H.near(LC.blend(1440, C), 0.5, 1e-9, "half way through the fade to day")
		H.near(LC.blend(1470, C), 0, 0, "the next day")
		-- The same moment of any cycle, and before time 0, gives the same blend.
		for _, t in { 0, 37.5, 615, 700, 1000, 1200, 1400 } do
			H.near(LC.blend(t + P * 1200000, C), LC.blend(t, C), 1e-5, "cycle " .. t)
			H.near(LC.blend(t - P * 3, C), LC.blend(t, C), 1e-9, "before zero " .. t)
		end
		-- Smooth: at 0.5 s steps it never jumps more than the steepest ease allows.
		local prev = LC.blend(0, C)
		for i = 1, P * 4 do
			local b = LC.blend(i * 0.5, C)
			H.expect(b >= 0 and b <= 2, "in 0..2")
			H.expect(
				math.abs(b - prev) <= 1.5 * 0.5 / C.Fade + 1e-9,
				("a jump at %.1f s"):format(i * 0.5)
			)
			prev = b
		end
	end,

	["the developer holds fade from the light shown now, hold, and ease back into the cycle"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		local C = L.Cycle
		H.expect(LC.readHold(1, nil, 5) == nil, "no hold without From")
		H.expect(LC.readHold(nil, 0.3, 5).Goal == nil, "a hold back to the cycle")
		local P = LC.period(C)
		for s = 0, P - 1, 13 do
			local t = 1790460000 + s
			for _, goal in { 0, 1, 2 } do
				-- Typed under no hold, and again while a fade runs: never a jump.
				local before = LC.shown(t, C, nil)
				local hold = { From = before, At = t, Goal = goal }
				H.near(LC.shown(t, C, hold), before, 1e-9, ("no jump to %d at %d"):format(goal, s))
				local seconds = C.Fade * math.max(1, math.abs(goal - before))
				H.near(LC.shown(t + seconds, C, hold), goal, 1e-9, "there after its fades")
				H.near(LC.shown(t + seconds + 5000, C, hold), goal, 1e-9, "and held")
				local mid = LC.shown(t + 10, C, hold)
				H.expect(
					math.abs(goal - mid) <= math.abs(goal - before) + 1e-9,
					"only toward the goal"
				)
				local again = { From = mid, At = t + 10, Goal = 2 - goal }
				H.near(LC.shown(t + 10, C, again), mid, 1e-9, "a second command from mid fade")
				-- /cycle: from the held light back into the running cycle within two fades (one
				-- per preset passed, night to day at most two).
				local back = { From = goal, At = t + 500, Goal = nil }
				H.near(LC.shown(t + 500, C, back), goal, 1e-9, "no jump back")
				H.near(
					LC.shown(t + 500 + 2 * C.Fade, C, back),
					LC.blend(t + 500 + 2 * C.Fade, C),
					1e-9,
					"running again"
				)
			end
		end
		for name, blend in C.Holds do
			H.expect(L[name] ~= nil and LC.PRESETS[blend + 1] == name, name .. " is its preset")
		end
		H.expect(type(C.OffsetAttribute) == "string" and C.OffsetAttribute ~= "", "an attribute")
		local D = H.require("Config").Debug.Commands
		for _, name in { "Day", "Sunset", "Night", "Cycle" } do
			H.expect(D[name]:sub(1, 1) == "/", name .. ": chat commands start with /")
		end
	end,

	["Day, Sunset and Night have the same keys, and blends 0, 1 and 2 are the states"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		sameShape(L.Day, L.Sunset, "Lighting", "Sunset")
		sameShape(L.Day, L.Night, "Lighting", "Night")
		matches(LC.state(0, L), L.Day, "blend 0")
		matches(LC.state(1, L), L.Sunset, "blend 1")
		matches(LC.state(2, L), L.Night, "blend 2")
		local first, last = L.SunPath[1], L.SunPath[#L.SunPath]
		local s0, s2 = LC.state(0, L), LC.state(2, L)
		H.near(s0.GeographicLatitude, first.GeographicLatitude, 1e-9, "the day sun")
		H.near(s2.ClockTime, last.ClockTime, 1e-9, "the night's moon")
		-- Half way to night: numbers half way, and the sky Night's (the same faces as sunset's).
		local mid = LC.state(1.5, L)
		H.near(mid.Brightness, (L.Sunset.Brightness + L.Night.Brightness) / 2, 1e-9, "half way")
		for key, id in L.Night.Sky do
			if key:match("^Skybox") then
				H.expect(L.Sunset.Sky[key] == id, key .. ": night keeps the sunset's faces")
			end
		end
	end,

	["colours mix per channel and the sky's images change only at the swap"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		H.expect(LC.mixHex("#000000", "#FF8040", 0) == "#000000", "mix at 0")
		H.expect(LC.mixHex("#000000", "#FF8040", 1) == "#FF8040", "mix at 1")
		H.expect(LC.mixHex("#000000", "#FF8040", 0.5) == "#804020", "mix half way")
		local first, second = L.SkySwaps[1], L.SkySwaps[2]
		H.expect(#L.SkySwaps == 2 and first < second, "two swaps, in order")
		local function sky(blend: number): { [string]: any }
			return LC.state(blend, L).Sky
		end
		for key, id in L.Day.Sky do
			if key:match("^Skybox") then
				H.expect(sky(first - 1e-6)[key] == id, key .. ": Day's until the first swap")
				H.expect(
					sky(first)[key] == L.DuskSky[key],
					key .. ": the dusk sky's from the first"
				)
				H.expect(
					sky(second - 1e-6)[key] == L.DuskSky[key],
					key .. ": the dusk sky's until the second"
				)
				H.expect(sky(second)[key] == L.Sunset.Sky[key], key .. ": Sunset's from the second")
			end
		end
		for key in L.DuskSky do
			H.expect(L.Day.Sky[key] ~= nil, "DuskSky." .. key .. " is a sky face")
		end
	end,

	["the sun's path rises through the blend and arrives by the swap"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		local path = L.SunPath
		H.expect(#path >= 2 and path[1].Blend == 0, "the path starts at the day")
		for i = 2, #path do
			H.expect(path[i].Blend > path[i - 1].Blend, "keyframes in order")
		end
		H.expect(path[#path].Blend == 2, "the path ends at the night")
		local swapLat, swapClock = LC.sun(L.SkySwaps[#L.SkySwaps], path)
		local setLat, setClock = LC.sun(1, path)
		H.expect(
			swapLat == setLat and swapClock == setClock,
			"the sun is at the sunset glow when the sunset sky shows, and holds there"
		)
		local lat, clock = LC.sun(0.25, path)
		local a, b = path[1], path[2]
		local w = (0.25 - a.Blend) / (b.Blend - a.Blend)
		H.near(
			lat,
			a.GeographicLatitude + (b.GeographicLatitude - a.GeographicLatitude) * w,
			1e-9,
			"between keyframes"
		)
		H.near(clock, a.ClockTime + (b.ClockTime - a.ClockTime) * w, 1e-9, "between keyframes")
	end,

	["the dusk warmth names real colours and is gone at the two ends"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		local W = L.DuskWarm
		H.expect(W.Width <= 0.5, "no warmth at either end")
		for path in W.Colours do
			local block, key = path:match("^(%w+)%.(%w+)$")
			local day = if block then L.Day[block][key] else L.Day[path]
			H.expect(
				type(day) == "string" and day:match("^#%x%x%x%x%x%x$") ~= nil,
				path .. " is a colour of the states"
			)
		end
		local mid = LC.state(0.5, L)
		H.expect(
			mid.OutdoorAmbient ~= LC.mixHex(L.Day.OutdoorAmbient, L.Sunset.OutdoorAmbient, 0.5),
			"warmer half way"
		)
	end,

	["the swap haze peaks at the swap and is gone beyond its width"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		local S = L.SwapHaze
		for _, at in L.SkySwaps do
			H.near(LC.swapBump(at, L), 1, 1e-9, "the peak")
			H.near(LC.swapBump(at + S.Width, L), 0, 1e-9, "gone at the width")
		end
		H.near(
			LC.swapBump((L.SkySwaps[1] + L.SkySwaps[2]) / 2, L),
			0,
			1e-9,
			"clear between the swaps"
		)
		H.near(LC.swapBump(0, L), 0, 0, "none by day")
		H.near(LC.swapBump(1, L), 0, 0, "none at sunset")
		local swap = L.SkySwaps[1]
		local at = LC.state(swap, L)
		local base = L.Day.Atmosphere.Density
			+ (L.Sunset.Atmosphere.Density - L.Day.Atmosphere.Density) * swap
		H.near(at.Atmosphere.Density, base + S.Density, 1e-9, "the haze at the swap")
		-- The mix leaves Config's own tables alone.
		H.near(L.Day.Atmosphere.Density, H.require("Config").Lighting.Day.Atmosphere.Density, 0)
	end,
	["an arena's offset starts the day now and it runs on from there"] = function()
		local LC = H.require("LightCycle")
		local C = H.require("Config").Lighting.Cycle
		for _, t in { 0, 123.4, 950, 1e9 + 0.5 } do
			local offset = LC.offsetToDayStart(t, C)
			H.expect(offset >= 0 and offset < LC.period(C), "one period at most")
			H.near((t + offset) % LC.period(C), 0, 1e-6, "the day's first second")
			H.expect(LC.blend(t + offset + C.Day - 1, C) == 0, "a whole day ahead")
			H.expect(LC.blend(t + offset + C.Day + C.Fade, C) == 1, "then sunset as usual")
			H.expect(LC.blend(t + offset + C.Day + 2 * C.Fade + C.Sunset, C) == 2, "then night")
		end
	end,
}
