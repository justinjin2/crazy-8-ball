--!strict
-- Checks the day and sunset cycle (src/shared/LightCycle.luau, Config.Lighting): the timing of
-- the cycle, the smooth fades, the mixing of the two light states, the sun's path and the haze
-- that hides the sky's swap.

local H = require("./harness")

local function isHex(v: any): boolean
	return type(v) == "string" and v:match("^#%x%x%x%x%x%x$") ~= nil
end

-- The same keys and kinds of value in two blocks, recursively.
local function sameShape(a: { [string]: any }, b: { [string]: any }, where: string)
	for key, va in a do
		local vb = b[key]
		H.expect(vb ~= nil, ("%s.%s is in Day but not Sunset"):format(where, key))
		H.expect(type(va) == type(vb), ("%s.%s: Day and Sunset differ in kind"):format(where, key))
		if type(va) == "table" then
			sameShape(va, vb, where .. "." .. key)
		elseif type(va) == "string" then
			H.expect(
				isHex(va) == isHex(vb),
				("%s.%s: a colour in one state only"):format(where, key)
			)
		end
	end
	for key in b do
		H.expect(a[key] ~= nil, ("%s.%s is in Sunset but not Day"):format(where, key))
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
	["the cycle is a day, a fade, a sunset and a fade, and runs at its real speed"] = function()
		local LC = H.require("LightCycle")
		local C = H.require("Config").Lighting.Cycle
		H.expect(C.Speed == 1, "Cycle.Speed is test only: put it back to 1 before committing")
		H.expect(LC.period(C) == C.Day + 2 * C.Fade + C.Sunset, "the period")
		H.expect(C.Rate > 0 and C.Look > 0, "a rate and a look interval")
	end,

	["the blend holds through the day and the sunset and eases between them"] = function()
		local LC = H.require("LightCycle")
		local C = { Day = 600, Fade = 60, Sunset = 300, Speed = 1, Rate = 12, Look = 2 }
		H.near(LC.blend(0, C), 0, 0)
		H.near(LC.blend(599.9, C), 0, 0)
		H.near(LC.blend(630, C), 0.5, 1e-9, "half way through the fade in")
		H.near(LC.blend(660, C), 1, 0)
		H.near(LC.blend(959.9, C), 1, 0)
		H.near(LC.blend(990, C), 0.5, 1e-9, "half way through the fade out")
		H.near(LC.blend(1020, C), 0, 0, "the next day")
		-- The same moment of any cycle, and before time 0, gives the same blend.
		for _, t in { 0, 37.5, 615, 700, 1000 } do
			H.near(LC.blend(t + 1020 * 1700000, C), LC.blend(t, C), 1e-6, "cycle " .. t)
			H.near(LC.blend(t - 1020 * 3, C), LC.blend(t, C), 1e-9, "before zero " .. t)
		end
		-- Smooth: at 0.5 s steps it never jumps more than the steepest ease allows.
		local prev = LC.blend(0, C)
		for i = 1, 2040 * 2 do
			local b = LC.blend(i * 0.5, C)
			H.expect(b >= 0 and b <= 1, "in 0..1")
			H.expect(
				math.abs(b - prev) <= 1.5 * 0.5 / C.Fade + 1e-9,
				("a jump at %.1f s"):format(i * 0.5)
			)
			prev = b
		end
	end,

	["the developer commands fade toward the day or the sunset from the light shown now"] = function()
		local LC = H.require("LightCycle")
		local C = H.require("Config").Lighting.Cycle
		-- Every moment of a cycle, under two different earlier offsets.
		for _, offset in { 0, 333.3 } do
			for s = 0, 1019, 7 do
				local t = 1790460000 + s
				local before = LC.blend(t + offset, C)
				for _, hold in { "Sunset", "Day" } do
					local o = LC.offsetToward(t, offset, C, hold)
					local goal = if hold == "Sunset" then 1 else 0
					H.expect(o >= 0 and o < LC.period(C), "an offset within one cycle")
					H.near(LC.blend(t + o, C), before, 1e-9, ("no jump: %s at %d"):format(hold, s))
					-- Asking again changes nothing.
					H.near(LC.offsetToward(t, o, C, hold), o, 1e-9, "asking twice")
					-- Away from the goal, the light moves only toward it and is there within a
					-- fade. (Already holding the goal, the cycle simply runs on.)
					if before ~= goal then
						local next = LC.blend(t + o + 1, C)
						H.expect(
							math.abs(goal - next) <= math.abs(goal - before) + 1e-9,
							"toward the goal"
						)
						local later = LC.blend(t + o + C.Fade, C)
						H.near(later, goal, 1e-9, ("%s within a fade from %d"):format(hold, s))
					end
				end
			end
		end
		H.expect(
			type(C.OffsetAttribute) == "string" and C.OffsetAttribute ~= "",
			"an attribute name"
		)
		local D = H.require("Config").Debug.Commands
		H.expect(D.Day:sub(1, 1) == "/" and D.Sunset:sub(1, 1) == "/", "chat commands start with /")
	end,

	["Day and Sunset have the same keys, and the ends of the blend are the two states"] = function()
		local LC = H.require("LightCycle")
		local L = H.require("Config").Lighting
		sameShape(L.Day, L.Sunset, "Lighting")
		matches(LC.state(0, L), L.Day, "blend 0")
		matches(LC.state(1, L), L.Sunset, "blend 1")
		local first, last = L.SunPath[1], L.SunPath[#L.SunPath]
		local s0, s1 = LC.state(0, L), LC.state(1, L)
		H.near(s0.GeographicLatitude, first.GeographicLatitude, 1e-9, "the day sun")
		H.near(s1.ClockTime, last.ClockTime, 1e-9, "the sunset sun")
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
		H.expect(
			path[#path].Blend <= L.SkySwaps[#L.SkySwaps],
			"the sun is at the sunset glow when the sunset sky shows"
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
}
