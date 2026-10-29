--!strict
-- A menu theme's moving pieces (MenuThemeMath, Config.UI.Menu.Themes; the Halloween menu's
-- "Haunted night", designer 2026-10-29): the bats cross the header band and come back in from
-- off its sides (never popping in view), their wings beat; the stars stay in the band, fade at
-- its sides as they wrap and twinkle; Lower effects shows fewer; Reduce Motion holds them still;
-- the same moment always draws the same (no random, no clock).

local H = require("./harness")

local function load()
	local Config = H.require("Config")
	return H.require("MenuThemeMath"), Config.UI.Menu.Themes.HauntedNight
end

return {
	["the theme has its pictures and its numbers"] = function()
		local _, T = load()
		for _, key in { "Moon", "Bat", "Star", "Edge" } do
			H.expect(string.sub(T.Images[key], 1, 13) == "rbxassetid://", key .. " has a picture")
		end
		H.expect(
			T.Bats.Low <= T.Bats.Count and T.Stars.Low <= T.Stars.Count,
			"Lower effects shows fewer"
		)
		H.expect(T.LowFps > 0, "a Lower effects step rate")
		H.expect(T.Bats.FlapLow > 0 and T.Bats.FlapLow < 1, "the wings never fold flat")
	end,

	["bats cross the band and turn back in off its sides"] = function()
		local Math, T = load()
		local B = T.Bats
		for index = 1, B.Count do
			local lastX: number? = nil
			for step = 0, 2400 do
				local clock = step * 0.05
				local b = Math.bat(T, index, clock)
				H.expect(b.x >= -B.Margin - 1e-9 and b.x <= 1 + B.Margin + 1e-9, "inside its path")
				H.expect(b.y >= 0 and b.y <= 1, ("bat %d in the band: %.3f"):format(index, b.y))
				H.expect(
					b.flap >= B.FlapLow - 1e-9 and b.flap <= 1 + 1e-9,
					"its wings beat in range"
				)
				H.expect(math.abs(b.rotation) <= B.Tilt + 1e-9, "it tilts a little")
				if lastX then
					local jump = math.abs(b.x - lastX)
					if jump > 0.5 then
						-- It wraps round only while off the band, both before and after.
						H.expect(
							(lastX < 0 or lastX > 1) and (b.x < 0 or b.x > 1),
							"a bat comes back in from off the side, never pops in view"
						)
					end
				end
				lastX = b.x
			end
		end
		local right, left = Math.bat(T, 1, 1), Math.bat(T, 1, 2)
		local right2, left2 = Math.bat(T, 2, 1), Math.bat(T, 2, 2)
		H.expect(left.x > right.x and left2.x < right2.x, "every other bat flies the other way")
	end,

	["stars stay in the band, fade at its sides and twinkle"] = function()
		local Math, T = load()
		local S = T.Stars
		for index = 1, S.Count do
			local faint, strong = 0, 1
			for step = 0, 800 do
				local s = Math.star(T, index, step * 0.1)
				H.expect(s.x >= 0 and s.x < 1, "across the band")
				H.expect(s.y >= S.Y[1] - 1e-9 and s.y <= S.Y[2] + 1e-9, "down the band")
				H.expect(
					s.transparency >= S.Alpha[1] - 1e-9 and s.transparency <= 1,
					"never stronger than Alpha"
				)
				H.expect(s.tint >= 1 and s.tint <= #S.Tints, "one of its tints")
				if s.x < 0.002 or s.x > 0.998 then
					H.expect(s.transparency > 0.95, "all but gone at the side it wraps round")
				end
				faint = math.max(faint, s.transparency)
				strong = math.min(strong, s.transparency)
			end
			H.expect(
				faint - strong > 0.3,
				("star %d twinkles: %.2f..%.2f"):format(index, strong, faint)
			)
		end
	end,

	["Lower effects shows fewer; Reduce Motion holds still; the same moment draws the same"] = function()
		local Math, T = load()
		H.expect(Math.count(T.Bats, true) == T.Bats.Low, "Lower effects: the Low bats")
		H.expect(Math.count(T.Stars, false) == T.Stars.Count, "the full stars otherwise")
		local a, b = Math.bat(T, 2, 0, true), Math.bat(T, 2, 37.5, true)
		H.expect(
			a.x == b.x and a.y == b.y and a.flap == 1 and a.rotation == 0,
			"a still bat, wings open"
		)
		local s1, s2 = Math.star(T, 3, 0, true), Math.star(T, 3, 99, true)
		H.expect(s1.x == s2.x and s1.transparency == s2.transparency, "a still star")
		H.expect(
			Math.breath(T.Moon.Alpha, T.Moon.Seconds, 12.3, true) == T.Moon.Alpha[1],
			"a still moon"
		)
		local x1, x2 = Math.bat(T, 1, 7.25), Math.bat(T, 1, 7.25)
		H.expect(x1.x == x2.x and x1.flap == x2.flap, "deterministic")
		H.expect(
			Math.draw(4, 2) == Math.draw(4, 2) and Math.draw(4, 2) ~= Math.draw(5, 2),
			"its draws"
		)
		local lo, hi = math.huge, -math.huge
		for step = 0, 200 do
			local v = Math.breath(T.Edge.Alpha, T.Edge.Seconds, step * 0.05)
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		H.expect(
			lo >= T.Edge.Alpha[1] - 1e-9 and hi <= T.Edge.Alpha[2] + 1e-9,
			"a glow breathes in its range"
		)
	end,
}
