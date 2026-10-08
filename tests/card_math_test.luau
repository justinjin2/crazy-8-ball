--!strict
-- CardMath and Config.UI.CueCard: every rarity and tier has a whole look, the scroll windows
-- stay inside their pictures, the loops start and end where they should, and a cue's sparkles
-- sit in the same places every time.

local H = require("./harness")

local function load()
	return H.require("CardMath"), H.require("Config")
end

local function isHex(value: any): boolean
	return type(value) == "string" and string.match(value, "^#%x%x%x%x%x%x$") ~= nil
end

-- Every look's fields have the right shapes (Config.UI.CueCard.Looks' comment).
local function checkLook(name: string, look: any)
	H.expect(type(look.Fill) == "table" and #look.Fill >= 2, name .. ": Fill")
	H.expect(type(look.FillAt) == "table" and #look.FillAt == #look.Fill, name .. ": FillAt")
	local last = -1
	for i, c in look.Fill do
		H.expect(isHex(c), name .. ": Fill colour")
		H.expect(look.FillAt[i] > last, name .. ": FillAt rises")
		last = look.FillAt[i]
	end
	H.expect(look.FillAt[1] == 0 and look.FillAt[#look.FillAt] == 1, name .. ": Fill from 0 to 1")
	for _, key in { "Edge", "Chance", "Balls" } do
		H.expect(isHex(look[key]), name .. ": " .. key)
	end
	if look.Centre ~= nil then
		H.expect(isHex(look.Centre), name .. ": Centre")
	end
	if look.Flow then
		H.expect(#look.Flow >= 2, name .. ": Flow colours")
		for _, c in look.Flow do
			H.expect(isHex(c), name .. ": Flow colour")
		end
	else
		H.expect(#look.Bar == 2 and isHex(look.Bar[1]) and isHex(look.Bar[2]), name .. ": Bar")
	end
	local function strong(part: any): boolean
		return type(part.Strength) == "number" and part.Strength > 0 and part.Strength <= 1
	end
	if look.Glow then
		H.expect(isHex(look.Glow.Color) and strong(look.Glow), name .. ": Glow")
	end
	if look.Rays then
		H.expect(
			isHex(look.Rays.Color) and strong(look.Rays) and look.Rays.Seconds > 0,
			name .. ": Rays"
		)
	end
	if look.Shine then
		H.expect(look.Shine.Seconds > 0 and strong(look.Shine), name .. ": Shine")
	end
	if look.Sparks then
		H.expect(look.Sparks.Count >= 1 and #look.Sparks.Colors >= 1, name .. ": Sparks")
		for _, c in look.Sparks.Colors do
			H.expect(isHex(c), name .. ": Sparks colour")
		end
	end
	if look.Embers then
		H.expect(look.Embers.Count >= 1 and isHex(look.Embers.Color), name .. ": Embers")
	end
	if look.EdgeSpin then
		H.expect(#look.EdgeSpin.Colors >= 2 and look.EdgeSpin.Seconds > 0, name .. ": EdgeSpin")
		for _, c in look.EdgeSpin.Colors do
			H.expect(isHex(c), name .. ": EdgeSpin colour")
		end
	end
	if look.EdgeGlow then
		H.expect(isHex(look.EdgeGlow.Color) and strong(look.EdgeGlow), name .. ": EdgeGlow")
	end
	-- The budget: at most this many moving labels on one card (UI_STYLE's ~100 for a screen,
	-- and only the cards on screen move).
	local moving = (if look.Sparks then look.Sparks.Count else 0)
		+ (if look.Embers then look.Embers.Count else 0)
		+ (look.Stars or 0)
	H.expect(moving <= 14, name .. ": at most 14 sparkles, embers and stars")
end

return {
	["every rarity and tier has a whole look, and the locked veil is set"] = function()
		local _, Config = load()
		local CC = Config.UI.CueCard
		local rarities = table.clone(Config.BlockOdds.Rarities)
		table.insert(rarities, "Unique")
		table.insert(rarities, "Exclusive")
		for _, rarity in rarities do
			local look = (CC.Looks :: any)[rarity]
			H.expect(look ~= nil, "no look for " .. rarity)
			checkLook(rarity, look)
		end
		for _, tier in Config.Ranks.Tiers do
			local look = (CC.Tiers :: any)[tier]
			H.expect(look ~= nil, "no look for the " .. tier .. " tier")
			checkLook(tier, look)
			-- Its badge: the tier's first division (Reyes has one).
			local key = if tier == "Reyes" then "reyes" else string.lower(tier) .. "_1"
			H.expect(Config.UI.Ranks.Badges[key] ~= nil, tier .. ": a badge")
		end
		for _, id in { CC.Images.Balls, CC.Images.ScanLines } do
			H.expect(string.match(id, "^rbxassetid://%d+$") ~= nil, "an image id")
		end
		-- The never-found card: a light veil that leaves the colours showing, the padlock on the
		-- card.
		local locked = CC.Locked
		H.expect(isHex(locked.VeilColor), "Locked: VeilColor")
		H.expect(
			locked.VeilTransparency > 0.2 and locked.VeilTransparency < 0.8,
			"Locked: a see-through veil"
		)
		H.expect(
			locked.LockUnits > 0 and locked.LockUnits < CC.Units[1],
			"Locked: the padlock fits the card"
		)
		for _, v in locked.LockAt do
			H.expect(v > 0 and v < 1, "Locked: the padlock on the card")
		end
		H.expect((CC.Looks :: any).Silhouette == nil, "the silhouette look is gone")
	end,

	["lookKey: tiers for rank cues, Common for the rest"] = function()
		local C = load()
		H.expect(select(1, C.lookKey("Ranked", "Gold")) == "Gold", "a rank cue wears its tier")
		H.expect(select(2, C.lookKey("Ranked", "Reyes")) == true, "and it is a tier")
		H.expect(C.lookKey("Legendary") == "Legendary", "a rarity")
		H.expect(C.lookKey("Default") == "Common", "no look of its own")
		H.expect(C.lookKey("Ranked") == "Common", "Ranked with no tier")
		H.expect(C.look("Gold").Edge == "#FFC428", "a tier's look")
		H.expect(C.look("Nope").Edge == C.look("Common").Edge, "Common for anything else")
	end,

	["the 8-balls' window stays inside its sheet and drifts one period every Seconds"] = function()
		local C, Config = load()
		local B = Config.UI.CueCard.Motion.Balls
		for _, w in { 40, 84, 100, 118, 150, 240, 320, 460 } do
			for _, aspect in { 1, 190 / 150, 1.5 } do
				local h = w * aspect
				for i = 0, 60 do
					local t = i * B.Seconds / 17
					local sx, sy, o = C.ballsWindow(t, w, h, 0.3)
					H.expect(o >= 0 and o < B.PeriodTexels, "offset inside one period")
					H.expect(o + sx <= B.SheetTexels and o + sy <= B.SheetTexels, "window inside")
					H.expect(sx > 0 and sy > 0, "a window")
				end
			end
		end
		-- The balls are the same size on every card: the window is a fixed share of the tile.
		local a = C.ballsWindow(0, 100, 127, 0)
		local b = C.ballsWindow(0, 300, 380, 0)
		H.near(a, b, 1e-6, "the same balls on a small and a big card")
		local _, _, o1 = C.ballsWindow(1, 150, 190, 0)
		local _, _, o2 = C.ballsWindow(1 + B.Seconds, 150, 190, 0)
		H.near(o1, o2, 1e-6, "one period every Seconds")
	end,

	["the scan lines' window stays inside its strip and wraps at a line"] = function()
		local C, Config = load()
		local S = Config.UI.CueCard.Motion.Scan
		for _, w in { 84, 150, 320 } do
			for i = 0, 40 do
				local sy, o = C.scanWindow(i * 0.37, w, w * 190 / 150)
				H.expect(o >= 0 and o < S.PeriodTexels, "offset inside a line period")
				H.expect(o + sy <= S.StripTexels[2], "window inside the strip")
			end
		end
	end,

	["twinkles, embers, shines and breaths start and end where they should"] = function()
		local C, Config = load()
		local M = Config.UI.CueCard.Motion
		local scale, strength = C.twinkle(0, 2, 0)
		H.near(scale, 0, 1e-9, "a twinkle starts gone")
		H.near(strength, 0, 1e-9, "unseen")
		scale, strength = C.twinkle(0.9, 2, 0) -- 45%
		H.near(scale, 1, 1e-9, "full at 45%")
		H.near(strength, 1, 1e-9, "bright at 45%")
		scale = C.twinkle(1.9999, 2, 0)
		H.expect(scale < 0.01, "gone at the end")
		for i = 0, 100 do
			local s, a = C.twinkle(i * 0.031, 2, 0.4)
			H.expect(s >= 0 and s <= 1 and a >= 0 and a <= 1, "inside 0..1")
		end

		local rise, glow = C.ember(0, 3, 0)
		H.near(rise, 0, 1e-9, "an ember starts at the bottom")
		H.near(glow, 0, 1e-9, "unseen")
		local _, full = C.ember(3 * M.Embers.FadeIn, 3, 0)
		H.near(full, 1, 1e-6, "bright once faded in")
		local top, out = C.ember(2.9999, 3, 0)
		H.expect(top > 0.99 and out < 0.01, "gone at the top")

		H.expect(C.shine(0, 4, 0) ~= nil, "a shine sweeps at the start of its loop")
		H.near(C.shine(0, 4, 0) :: number, -M.Shine.Travel, 1e-9, "from off the left")
		H.expect(C.shine(4 * M.Shine.SweepShare + 0.01, 4, 0) == nil, "then rests")

		H.near(C.breath(0, 2.6, 0, 0.45), 0.45, 1e-9, "a breath starts low")
		H.near(C.breath(1.3, 2.6, 0, 0.45), 1, 1e-9, "full halfway")
		H.near(C.turn(8, 32, 0), 90, 1e-9, "a quarter turn in a quarter of its time")
		H.near(C.sheen(0, 6, 0), -M.Sheen.Travel, 1e-9, "the sheen starts at one side")
		H.near(C.sheen(6, 6, 0), M.Sheen.Travel, 1e-9, "and reaches the other")
	end,

	["the glitch shows only in its steps"] = function()
		local C, Config = load()
		local G = Config.UI.CueCard.Motion.Glitch
		H.expect(C.glitch(0, 0) == nil, "no glitch at the start")
		H.expect(C.glitch(G.Seconds * 0.5, 0) == nil, "nor halfway")
		local step = C.glitch(G.Seconds * 0.915, 0)
		H.expect(step ~= nil and step.At == 0.91, "the first step")
		H.expect(C.glitch(G.Seconds * 0.98, 0) == nil, "over before the loop ends")
	end,

	["a cue's sparkles sit in the same places every time, inside their area"] = function()
		local C, Config = load()
		local S = Config.UI.CueCard.Motion.Sparks
		local a = C.scatter(C.random(C.seed("PhoenixCue")), 6, S.Area, S.Units, S.Seconds)
		local b = C.scatter(C.random(C.seed("PhoenixCue")), 6, S.Area, S.Units, S.Seconds)
		local c = C.scatter(C.random(C.seed("ChromaCue")), 6, S.Area, S.Units, S.Seconds)
		H.expect(#a == 6, "six spots")
		local differs = false
		for i, spot in a do
			H.expect(spot.x == b[i].x and spot.y == b[i].y, "the same every time")
			differs = differs or spot.x ~= c[i].x
			H.expect(spot.x >= S.Area[1] and spot.x <= S.Area[3], "inside across")
			H.expect(spot.y >= S.Area[2] and spot.y <= S.Area[4], "inside down")
			H.expect(spot.units >= S.Units[1] and spot.units <= S.Units[2], "a size in range")
			H.expect(
				spot.seconds >= S.Seconds[1] and spot.seconds <= S.Seconds[2],
				"a loop in range"
			)
			H.expect(spot.phase >= 0 and spot.phase < 1, "a phase")
		end
		H.expect(differs, "another cue's sparkles sit elsewhere")
		H.expect(C.seed("") >= 1, "an empty id still seeds")
	end,

	["a flowing bar's colours go round seamlessly"] = function()
		local C, Config = load()
		local F = Config.UI.CueCard.Motion.BarFlow
		local colors = Config.UI.CueCard.Looks.Mythic.Flow
		local keys = C.flow(colors, 0, 0, F.Points)
		H.expect(#keys == F.Points and keys[1][1] == 0 and keys[#keys][1] == 1, "keypoints 0 to 1")
		local r, g, b = C.rgb(colors[1])
		H.near(keys[1][2], r, 1e-9, "starts on the first colour")
		H.near(keys[1][3], g, 1e-9, "starts on the first colour")
		H.near(keys[1][4], b, 1e-9, "starts on the first colour")
		-- One whole round later it shows the same colours.
		local later = C.flow(colors, #colors / F.Speed, 0, F.Points)
		for i, key in keys do
			for j = 2, 4 do
				H.near(later[i][j], key[j], 1e-6, "the same after a whole round")
			end
		end
		for _, key in C.flow(colors, 1.234, 0.5, F.Points) do
			for j = 2, 4 do
				H.expect(key[j] >= 0 and key[j] <= 1, "a colour share")
			end
		end
	end,
}
