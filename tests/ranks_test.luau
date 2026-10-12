--!strict
-- Ranks: total XP to rank and back, match XP, the opponent gap, the streak boost, peaks and
-- rank-up rewards. Every expected number is written out from docs/ECONOMY.md section 2 (not read
-- from Config), so these tests check Config against the document.

local H = require("./harness")

local function load()
	return H.require("Progression.Ranks"), H.require("Config")
end

-- A rated save at a rank, with its peak there unless one is given.
local function saveAt(
	Ranks: any,
	tier: string,
	division: number?,
	into: number?,
	peak: number?
): any
	local index = Ranks.indexOf(tier, division)
	return {
		RankXp = Ranks.toXp(tier, division, into),
		PeakDivision = peak or index,
		RatedMatches = 10,
	}
end

local function unranked(): any
	return { RankXp = 0, PeakDivision = 0, RatedMatches = 0 }
end

-- The save a result leaves (what the server would write back).
local function nextSave(result: any): any
	return {
		RankXp = result.xpAfter,
		PeakDivision = result.peakAfter,
		RatedMatches = result.ratedMatches,
	}
end

-- A plain match context: a Classic match against an equal person.
local function ctx(outcome: string, overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		outcome = outcome,
		opponent = "Player",
		forfeit = false,
		mode = "Classic",
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

local function expectRank(rank: any, tier: string, division: number, into: number, label: string)
	H.expect(
		rank.tier == tier and rank.division == division and rank.xpInDivision == into,
		("%s: expected %s %d +%d, got %s %d +%d"):format(
			label,
			tier,
			division,
			into,
			tostring(rank.tier),
			rank.division,
			rank.xpInDivision
		)
	)
end

local function sameValue(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not sameValue(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function isWhole(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n == n
end

-- The XP a match gives a player at `tier` division II (so the gap has room both ways).
local function xpAt(Ranks: any, tier: string, context: any): number
	local rank = Ranks.fromXp(Ranks.toXp(tier, 2, 0), true)
	return (Ranks.matchXp(rank, context))
end

local TIERS = {
	"Bronze",
	"Silver",
	"Gold",
	"Platinum",
	"Diamond",
	"Expert",
	"Veteran",
	"Master",
	"Grandmaster",
}
local ALL_TIERS = table.clone(TIERS)
table.insert(ALL_TIERS, "Reyes")

return {
	["46 divisions and names round trip"] = function()
		local Ranks, Config = load()
		H.expect(Ranks.count() == 46, "46 divisions, got " .. Ranks.count())
		H.expect(Ranks.count() == (#Config.Ranks.Tiers - 1) * Config.Ranks.DivisionsPerTier + 1)
		for index = 0, Ranks.count() do
			local tier, division = Ranks.at(index)
			H.expect(Ranks.indexOf(tier, division) == index, "round trip at " .. index)
		end
		H.expect(select(1, Ranks.at(0)) == "Unranked" and select(2, Ranks.at(0)) == 0)
		H.expect(select(1, Ranks.at(1)) == "Bronze" and select(2, Ranks.at(1)) == 1)
		H.expect(select(1, Ranks.at(5)) == "Bronze" and select(2, Ranks.at(5)) == 5)
		H.expect(select(1, Ranks.at(6)) == "Silver" and select(2, Ranks.at(6)) == 1)
		H.expect(select(1, Ranks.at(45)) == "Grandmaster" and select(2, Ranks.at(45)) == 5)
		H.expect(select(1, Ranks.at(46)) == "Reyes" and select(2, Ranks.at(46)) == 1)
	end,

	["tier names are case-insensitive and bad ones are nil"] = function()
		local Ranks = load()
		H.expect(Ranks.indexOf("gold", 3) == 13, "gold 3")
		H.expect(Ranks.indexOf("GOLD", 3) == 13, "GOLD 3")
		H.expect(Ranks.indexOf("Gold") == 11, "division defaults to I")
		H.expect(Ranks.indexOf("reyes") == 46 and Ranks.indexOf("Reyes", 4) == 46, "Reyes")
		H.expect(Ranks.indexOf("unranked") == 0 and Ranks.indexOf("UNRANKED", 3) == 0)
		H.expect(Ranks.indexOf("golden") == nil, "unknown tier")
		H.expect(Ranks.indexOf("") == nil, "empty")
		H.expect(Ranks.indexOf(nil :: any) == nil, "nil tier")
		H.expect(Ranks.indexOf("gold", 0) == nil and Ranks.indexOf("gold", 6) == nil)
		H.expect(Ranks.indexOf("gold", 2.5) == nil, "fractional division")
		H.expect(Ranks.tierIndex("bronze") == 1 and Ranks.tierIndex("Reyes") == 10)
		H.expect(Ranks.tierIndex("Unranked") == 0 and Ranks.tierIndex("nope") == nil)
	end,

	-- ECONOMY 2 "The ladder" (designer, 2026-10-11): every division's width and the fixed starts.
	["the ladder is ECONOMY 2's: Grandmaster I at 143,600, Reyes at 363,600"] = function()
		local Ranks = load()
		local widths: { [string]: { number } } = {
			Bronze = { 200, 200, 300, 400, 500 },
			Silver = { 200, 300, 400, 500, 600 },
			Gold = { 300, 400, 500, 600, 700 },
			Platinum = { 500, 700, 900, 1100, 1300 },
			Diamond = { 800, 1200, 1600, 2000, 2400 },
			Expert = { 2000, 3000, 4000, 5000, 6000 },
			Veteran = { 5000, 6000, 7000, 8000, 9000 },
			Master = { 8000, 11000, 14000, 17000, 20000 },
			Grandmaster = { 18000, 30000, 44000, 58000, 70000 },
		}
		local tierTotals: { [string]: number } = {
			Bronze = 1600,
			Silver = 2000,
			Gold = 2500,
			Platinum = 4500,
			Diamond = 8000,
			Expert = 20000,
			Veteran = 35000,
			Master = 70000,
			Grandmaster = 220000,
		}
		local start = 0
		for _, tier in TIERS do
			H.expect(Ranks.startXp(Ranks.indexOf(tier, 1)) == start, tier .. " I start")
			local sum = 0
			for division = 1, 5 do
				local index = Ranks.indexOf(tier, division)
				local want = widths[tier][division]
				H.expect(
					Ranks.width(index) == want,
					("%s %d: width %s, expected %d"):format(
						tier,
						division,
						tostring(Ranks.width(index)),
						want
					)
				)
				H.expect(Ranks.startXp(index) == start + sum, tier .. " start " .. division)
				sum += want
			end
			H.expect(sum == tierTotals[tier], tier .. " total")
			start += sum
		end
		H.expect(Ranks.startXp(Ranks.indexOf("Grandmaster", 1)) == 143600, "Grandmaster I")
		H.expect(Ranks.startXp(Ranks.indexOf("Reyes")) == 363600, "Reyes")
		H.expect(start == 363600)
		-- The tier starts ECONOMY quotes elsewhere, in wins of 100 XP (the first win is at 0).
		H.expect(Ranks.startXp(Ranks.indexOf("Silver")) == 1600, "Silver I: 16 wins")
		H.expect(Ranks.startXp(Ranks.indexOf("Gold")) == 3600, "Gold I: 36 wins")
		H.expect(Ranks.startXp(Ranks.indexOf("Platinum")) == 6100, "Platinum I: 61 wins")
		H.expect(Ranks.startXp(Ranks.indexOf("Diamond")) == 10600)
		H.expect(Ranks.startXp(Ranks.indexOf("Expert")) == 18600)
		-- The first win lands in Bronze I one win from Bronze II; then 2, 3, 4, 5 wins.
		H.expect(Ranks.width(1) - 100 == 100, "one win from Bronze II after the first")
		-- Bronze to Gold: a win more each division, each tier starting a win above the last.
		for t = 1, 3 do
			for division = 1, 5 do
				local index = (t - 1) * 5 + division
				if index > 1 then
					H.expect(
						Ranks.width(index) == (t + division - 1) * 100,
						"a win more at " .. index
					)
				end
			end
		end
		-- Every tier: its steps grow (Bronze from II: Bronze I also holds the first win), it
		-- starts lower than the last tier ended (a quick first rank-up), and it is longer than
		-- the tier below.
		local lastTotal = 0
		for t, tier in TIERS do
			local first = Ranks.indexOf(tier, 1) :: number
			for division = if t == 1 then 3 else 2, 5 do
				H.expect(
					(Ranks.width(first + division - 1) :: number)
						> Ranks.width(first + division - 2) :: number,
					tier .. " grows at " .. division
				)
			end
			if t > 1 then
				H.expect(
					(Ranks.width(first) :: number) < (Ranks.width(first - 1) :: number),
					tier .. " I starts lower than the tier below ended"
				)
			end
			H.expect(tierTotals[tier] > lastTotal, tier .. " is longer than the tier below")
			-- Fast to Gold, then slowing (designer, 2026-10-11): from Platinum each tier costs
			-- about twice the last.
			if t >= 4 then
				H.expect(tierTotals[tier] >= lastTotal * 1.75, tier .. " is about twice the last")
			end
			lastTotal = tierTotals[tier]
		end
	end,

	-- The 2026-10-11 switch moved nobody down: every division to Grandmaster IV starts at or
	-- below where the 2026-10-02 ladder had it, so any save's XP is in the same division or a
	-- higher one. Only Grandmaster V and Reyes start later, at 285,500 XP and more on the old
	-- ladder, far past any save at the switch (the top one had 2,792 XP, two days after launch).
	["the new ladder never puts a save in a lower division than the old one"] = function()
		local Ranks = load()
		local old: { [string]: { number } } = {
			Bronze = { 300, 300, 400, 500, 600 },
			Silver = { 700, 800, 900, 1000, 1100 },
			Gold = { 1200, 1300, 1400, 1500, 1600 },
			Platinum = { 1700, 1800, 1900, 2000, 2200 },
			Diamond = { 2500, 2800, 3200, 3600, 4000 },
			Expert = { 4500, 5000, 5600, 6200, 6900 },
			Veteran = { 7700, 8800, 10000, 11300, 12700 },
			Master = { 14300, 15700, 17000, 18000, 19500 },
			Grandmaster = { 20000, 20500, 21000, 21500, 22000 },
		}
		local oldStarts: { number } = {}
		local x = 0
		for _, tier in TIERS do
			for _, w in old[tier] do
				table.insert(oldStarts, x)
				x += w
			end
		end
		table.insert(oldStarts, x) -- Reyes, 307,500
		H.expect(#oldStarts == Ranks.count())
		local grandmaster5 = Ranks.indexOf("Grandmaster", 5) :: number
		for index = 1, Ranks.count() do
			if index < grandmaster5 then
				H.expect(Ranks.startXp(index) <= oldStarts[index], "starts no later at " .. index)
			else
				H.expect(oldStarts[index] >= 285500, "only the top two start later")
			end
		end
		-- Every save on the live boards on 2026-10-11 (their XP), old division to new.
		local function oldIndex(xp: number): number
			local k = 1
			for i, s in oldStarts do
				if xp >= s then
					k = i
				end
			end
			return k
		end
		for xp = 0, 3000, 5 do
			H.expect(Ranks.fromXp(xp, true).index >= oldIndex(xp), "never lower at " .. xp)
		end
		H.expect(Ranks.name(Ranks.fromXp(2792, true)) == "Silver 4", "the top player: Silver 4")
		H.expect(Ranks.name(Ranks.fromXp(100, true)) == "Bronze 1", "one win: still Bronze 1")
		H.expect(Ranks.name(Ranks.fromXp(200, true)) == "Bronze 2", "two wins: Bronze 2")
	end,

	-- The tutorial's first game is against a bot wearing Silver (Config.Bots.Tutorial.FirstTier):
	-- beating it gives 145 to 150 XP, which must land in Bronze I one win from Bronze II (ONE
	-- MORE WIN! under the bar), never straight in Bronze II.
	["the tutorial's first win lands in Bronze I, one win from Bronze II"] = function()
		local Ranks = load()
		for division = 1, 5 do
			local silver = Ranks.indexOf("Silver", division)
			local first = Ranks.applyMatch(unranked(), ctx("Win", { opponentIndex = silver }))
			H.expect(first.after.tier == "Bronze" and first.after.division == 1, "Bronze I")
			H.expect(first.xpAfter >= 140 and first.xpAfter <= 150, "145-150 XP: " .. first.xpAfter)
			local next = Ranks.applyMatch(nextSave(first), ctx("Win"))
			H.expect(next.after.tier == "Bronze" and next.after.division == 2, "one more win")
		end
	end,

	["catchUpPeak raises a peak to its XP's division and never lowers one"] = function()
		local Ranks = load()
		-- The top player on 2026-10-11: Silver I (6) on the old ladder, Silver IV (9) now.
		H.expect(Ranks.catchUpPeak({ RankXp = 2792, PeakDivision = 6, RatedMatches = 30 }) == 9)
		-- One win: Bronze I either way, nothing to catch up.
		H.expect(Ranks.catchUpPeak({ RankXp = 100, PeakDivision = 1, RatedMatches = 1 }) == 1)
		-- Two wins: Bronze II now.
		H.expect(Ranks.catchUpPeak({ RankXp = 200, PeakDivision = 1, RatedMatches = 2 }) == 2)
		-- A peak above the XP's division stays (never lowered).
		H.expect(Ranks.catchUpPeak({ RankXp = 0, PeakDivision = 11, RatedMatches = 1 }) == 11)
		-- Unrated: Unranked whatever the XP; its peak stays.
		H.expect(Ranks.catchUpPeak({ RankXp = 9000, PeakDivision = 0, RatedMatches = 0 }) == 0)
		H.expect(Ranks.catchUpPeak({ RankXp = 9000, PeakDivision = 3, RatedMatches = 0 }) == 3)
		-- A save at its peak already, and bad values, change nothing and never crash.
		H.expect(
			Ranks.catchUpPeak({ RankXp = 363600, PeakDivision = 46, RatedMatches = 900 }) == 46
		)
		H.expect(Ranks.catchUpPeak(nil :: any) == 0)
		H.expect(Ranks.catchUpPeak({ RankXp = 0 / 0, PeakDivision = -4, RatedMatches = 1 }) == 1)
		H.expect(
			Ranks.catchUpPeak({ RankXp = math.huge, PeakDivision = 999, RatedMatches = 1 }) == 46
		)
		-- Idempotent: a caught-up save catches up to the same peak again.
		local save = { RankXp = 5000, PeakDivision = 2, RatedMatches = 40 }
		save.PeakDivision = Ranks.catchUpPeak(save)
		H.expect(save.PeakDivision == Ranks.fromXp(5000, true).index)
		H.expect(Ranks.catchUpPeak(save) == save.PeakDivision)
	end,

	["fromXp finds the division at every boundary"] = function()
		local Ranks = load()
		expectRank(Ranks.fromXp(0, true), "Bronze", 1, 0, "0")
		expectRank(Ranks.fromXp(199, true), "Bronze", 1, 199, "199")
		expectRank(Ranks.fromXp(200, true), "Bronze", 2, 0, "200")
		expectRank(Ranks.fromXp(1599, true), "Bronze", 5, 499, "1599")
		expectRank(Ranks.fromXp(1600, true), "Silver", 1, 0, "1600")
		expectRank(Ranks.fromXp(10600, true), "Diamond", 1, 0, "10600")
		expectRank(Ranks.fromXp(363599, true), "Grandmaster", 5, 69999, "Grandmaster V top")
		local reyes = Ranks.fromXp(363600, true)
		expectRank(reyes, "Reyes", 1, 0, "363600")
		H.expect(reyes.index == 46 and reyes.width == nil, "Reyes has no top")
		local huge = Ranks.fromXp(123456789, true)
		expectRank(huge, "Reyes", 1, 123456789 - 363600, "huge")
		H.expect(huge.width == nil)
		local gold3 = Ranks.fromXp(4400, true)
		H.expect(gold3.width == 500 and gold3.index == 13 and gold3.xpInDivision == 100)
		local none = Ranks.fromXp(9000, false)
		H.expect(none.tier == "Unranked" and none.index == 0 and none.division == 0)
		H.expect(none.xpInDivision == 0 and none.width == nil, "unrated is Unranked")
	end,

	["startXp width and toXp"] = function()
		local Ranks = load()
		H.expect(Ranks.startXp(0) == 0 and Ranks.startXp(1) == 0 and Ranks.startXp(2) == 200)
		H.expect(Ranks.startXp(46) == 363600)
		H.expect(Ranks.width(0) == nil and Ranks.width(46) == nil and Ranks.width(1) == 200)
		H.expect(Ranks.toXp("gold", 3, 320) == 4300 + 320, "Gold III 320")
		H.expect(Ranks.toXp("gold", 3, 5000) == 4300 + 499, "clamped into the division")
		H.expect(Ranks.toXp("gold", 3, -5) == 4300, "negative into is 0")
		H.expect(Ranks.toXp("reyes", nil, 99999) == 363600 + 99999, "Reyes unbounded")
		H.expect(Ranks.toXp("unranked") == 0 and Ranks.toXp("golden") == nil)
		for index = 1, Ranks.count() do
			local tier, division = Ranks.at(index)
			local rank = Ranks.fromXp(Ranks.toXp(tier, division, 7), true)
			H.expect(rank.index == index and rank.xpInDivision == 7, "toXp/fromXp at " .. index)
		end
	end,

	["display names and badge keys"] = function()
		local Ranks = load()
		H.expect(Ranks.name(Ranks.fromXp(4300, true)) == "Gold 3", "Gold 3, never Roman")
		H.expect(Ranks.name(Ranks.fromXp(363600, true)) == "Reyes", "Reyes")
		H.expect(Ranks.name(Ranks.fromXp(0, false)) == "Unranked", "Unranked")
		H.expect(Ranks.name(Ranks.fromXp(0, true)) == "Bronze 1", "Bronze 1")
		H.expect(Ranks.name(Ranks.fromXp(363599, true)) == "Grandmaster 5")
		H.expect(Ranks.tierName("gold") == "Gold" and Ranks.tierName("unranked") == "Unranked")
		H.expect(Ranks.badgeKey("Gold", 3) == "gold_3", "gold_3")
		H.expect(Ranks.badgeKey("reyes", 1) == "reyes", "reyes")
		H.expect(Ranks.badgeKey("Unranked", 0) == "unranked", "unranked")
		H.expect(Ranks.badgeKey("Grandmaster", 5) == "grandmaster_5")
		H.expect(Ranks.badgeKey("nonsense", 2) == "unranked", "unknown tier")
	end,

	["round half to even, as ECONOMY's table was made"] = function()
		local Ranks = load()
		local r = Ranks.roundHalfEven
		H.expect(r(312.5) == 312 and r(37.5) == 38 and r(112.5) == 112 and r(62.5) == 62)
		H.expect(r(0.5) == 0 and r(1.5) == 2 and r(2.5) == 2 and r(93.75) == 94)
		H.expect(r(312.49) == 312 and r(312.51) == 313 and r(90) == 90 and r(0) == 0)
		H.expect(r(312.5 + 1e-12) == 312 and r(37.5 - 1e-12) == 38, "float noise is a tie")
	end,

	-- ECONOMY 4.2, "XP for a win and a loss against an equal opponent": every cell. A win is
	-- 100 at every tier, x1.5 Difficult, x2 Challenger; from Expert a Classic win fades (x0.5
	-- Expert, x0.4 Veteran, x0.3 Master, x0.25 Grandmaster and Reyes). A loss is 0.
	["match XP is ECONOMY 4.2's table, every tier, mode and result"] = function()
		local Ranks = load()
		local checked = 0
		local modes = { Classic = 100, Difficult = 150, Challenger = 200 }
		local classicWin: { [string]: number } =
			{ Expert = 50, Veteran = 40, Master = 30, Grandmaster = 25, Reyes = 25 }
		for _, tier in ALL_TIERS do
			local rank = Ranks.fromXp(Ranks.toXp(tier, 1, 10), true)
			for _, mode in { "Classic", "Difficult", "Challenger" } do
				for _, outcome in { "Win", "Loss" } do
					local want = if outcome ~= "Win"
						then 0
						elseif mode == "Classic" then classicWin[tier] or 100
						else modes[mode]
					local got = Ranks.matchXp(rank, ctx(outcome, { mode = mode }))
					H.expect(
						got == want,
						("%s %s %s: %s XP, expected %d"):format(
							tier,
							mode,
							outcome,
							tostring(got),
							want
						)
					)
					checked += 1
				end
			end
		end
		H.expect(checked == 60, "every cell")
		-- Unranked plays by Bronze's row; a missing mode is Classic; an unknown mode too.
		local none = Ranks.fromXp(0, false)
		H.expect(Ranks.matchXp(none, ctx("Loss")) == 0, "Unranked: a loss gives nothing")
		H.expect(Ranks.matchXp(none, ctx("Win", { mode = "Difficult" })) == 150)
		local diamond = Ranks.fromXp(Ranks.toXp("Diamond", 1), true)
		local noMode = { outcome = "Win", opponent = "Player" }
		H.expect(Ranks.matchXp(diamond, noMode) == 100, "default Classic")
		H.expect(Ranks.matchXp(diamond, ctx("Win", { mode = "Hard" })) == 100, "unknown mode")
		-- The HUD's wins-to-go asks with no mode: from Expert that is the faded Classic win.
		local expert = Ranks.fromXp(Ranks.toXp("Expert", 1), true)
		local faded, fb = Ranks.matchXp(expert, noMode)
		H.expect(faded == 50 and fb.fade == 0.5, "Expert Classic: 50")
	end,

	-- ECONOMY 4.4's table: every cell, both halves, within 0.005.
	["the opponent gap factor is ECONOMY 4.4's table"] = function()
		local Ranks = load()
		local gaps = { 15, 10, 8, 5, 3, 1, 0, -1, -3, -5 }
		local gentle = { 0.30, 0.30, 0.35, 0.55, 0.72, 0.90, 1, 1.10, 1.28, 1.45 }
		local strict = { 0.10, 0.11, 0.18, 0.38, 0.59, 0.86, 1, 1.14, 1.41, 1.50 }
		for i, gap in gaps do
			-- Bronze to Diamond: me at Platinum I (16) or Diamond V (25), both below Expert I,
			-- and the opponent on the ladder for every gap.
			for _, mine in { 16, 25 } do
				H.near(Ranks.gapFactor(mine, mine - gap), gentle[i], 0.005, "gentle gap " .. gap)
			end
			-- Expert and up: me at Expert I (26) or Master I (41).
			for _, mine in { 26, 41 } do
				H.near(Ranks.gapFactor(mine, mine - gap), strict[i], 0.005, "strict gap " .. gap)
			end
		end
		-- Exactly 1 against an equal (nil) opponent, and clamped at both ends.
		H.expect(Ranks.gapFactor(12, nil) == 1 and Ranks.gapFactor(40, 40) == 1)
		H.expect(Ranks.gapFactor(25, 1) == 0.3 and Ranks.gapFactor(45, 1) == 0.1, "floors")
		H.expect(Ranks.gapFactor(1, 46) == 1.5 and Ranks.gapFactor(26, 46) == 1.5, "Max")
		-- Unranked counts as Bronze I on both sides; a team's average may be fractional.
		H.expect(Ranks.gapFactor(0, 1) == 1 and Ranks.gapFactor(1, 0) == 1)
		H.expect(Ranks.gapFactor(0, 0) == 1)
		local half = Ranks.gapFactor(12, 11.5)
		H.expect(half < 1 and half > Ranks.gapFactor(12, 11), "a fractional team average")
		H.expect(Ranks.gapFactor(12, 0 / 0) == 1, "NaN is an equal opponent")
	end,

	["the gap scales wins, and a loss stays 0"] = function()
		local Ranks = load()
		local silver = Ranks.fromXp(Ranks.toXp("Silver", 5), true) -- index 10
		-- Beating a player 5 divisions below: 100 x 0.554 = 55.4 -> 55.
		local xp, b = Ranks.matchXp(silver, ctx("Win", { opponentIndex = 5 }))
		H.near(b.gap, 0.554, 0.001, "gap in the breakdown")
		H.expect(xp == 55, "a win over a weaker player, got " .. xp)
		-- Beating a stronger one pays more: 100 x 1.446 = 144.6 -> 145.
		H.expect(Ranks.matchXp(silver, ctx("Win", { opponentIndex = 15 })) == 145, "x1.446")
		-- A loss is 0 either way, its gap capped at 1.
		local lossUp, lb = Ranks.matchXp(silver, ctx("Loss", { opponentIndex = 15 }))
		H.expect(lossUp == 0 and lb.gap == 1, "a loss never gets more than x1")
		H.expect(Ranks.matchXp(silver, ctx("Loss", { opponentIndex = 1 })) == 0)
		-- From Expert the strict scale: Expert I beating Diamond I (5 lower): Classic 100 x 0.5
		-- (the fade) x 0.383 = 19.2 -> 19, Challenger 200 x 0.383 = 76.7 -> 77.
		local expert = Ranks.fromXp(Ranks.toXp("Expert", 1), true)
		H.expect(Ranks.matchXp(expert, ctx("Win", { opponentIndex = 21 })) == 19)
		H.expect(
			Ranks.matchXp(expert, ctx("Win", { mode = "Challenger", opponentIndex = 21 })) == 77
		)
	end,

	-- Economy v6 (designer, 2026-10-10): PC is practice, worth no rank XP at any rank.
	["PC XP: none, below Expert or from it"] = function()
		local Ranks = load()
		local pc = { opponent = "PC" }
		H.expect(xpAt(Ranks, "Bronze", ctx("Win", pc)) == 0)
		H.expect(xpAt(Ranks, "Bronze", ctx("Loss", pc)) == 0)
		local diamond5 = Ranks.fromXp(Ranks.toXp("Diamond", 5), true)
		local _, low = Ranks.matchXp(diamond5, ctx("Win", pc))
		H.expect(low.pc == 0)
		H.expect(xpAt(Ranks, "Expert", ctx("Win", { opponent = "PC", mode = "Challenger" })) == 0)
		local _, high = Ranks.matchXp(Ranks.fromXp(Ranks.toXp("Reyes"), true), ctx("Win", pc))
		H.expect(high.pc == 0)
	end,

	["boosts: only the win streak, +25% on a win against people"] = function()
		local Ranks = load()
		local bronze = Ranks.fromXp(Ranks.toXp("Bronze", 2), true)
		-- The streak: 100 x 1.25 = 125.
		local streak, sb = Ranks.matchXp(bronze, ctx("Win", { boosts = { streak = true } }))
		H.expect(streak == 125 and #sb.boosts == 1, "x1.25, got " .. streak)
		H.expect(sb.boosts[1].kind == "Streak" and sb.boosts[1].share == 0.25)
		H.expect(sb.boostTotal == 0.25)
		-- The old Rookie, VIP and first-win flags do nothing (removed 2026-10-02).
		local old = { rookie = true, vip = true, firstWin = true }
		local plain, pb = Ranks.matchXp(bronze, ctx("Win", { boosts = old }))
		H.expect(plain == 100 and #pb.boosts == 0 and pb.boostTotal == 0, "no old boosts")
		-- A loss is 0 whatever the boosts; against PC the streak does not count.
		local all = { rookie = true, vip = true, firstWin = true, streak = true }
		local lx, lb = Ranks.matchXp(bronze, ctx("Loss", { boosts = all }))
		H.expect(lx == 0 and #lb.boosts == 0, "loss boosts")
		local pcx, pcb = Ranks.matchXp(bronze, ctx("Win", { opponent = "PC", boosts = all }))
		H.expect(#pcb.boosts == 0 and pcx == 0, "PC: no streak, no XP")
		-- The top: Expert Challenger on a streak: 200 x 1.25 = 250.
		H.expect(xpAt(Ranks, "Expert", ctx("Win", { mode = "Challenger", boosts = all })) == 250)
	end,

	["anti-farm XP, draws, forfeits and other opponents give what they should"] = function()
		local Ranks = load()
		local gold = Ranks.fromXp(Ranks.toXp("Gold", 2), true)
		-- ECONOMY 3.6: matches 6-10 half the XP, from 11 none.
		H.expect(Ranks.matchXp(gold, ctx("Win", { farm = 0.5 })) == 50)
		H.expect(Ranks.matchXp(gold, ctx("Loss", { farm = 0.5 })) == 0)
		local zero, zb = Ranks.matchXp(gold, ctx("Win", { farm = 0 }))
		H.expect(zero == 0 and zb.farm == 0 and zb.base == 100)
		H.expect(Ranks.matchXp(gold, ctx("Win", { farm = -3 })) == 0, "a bad farm never pays more")
		-- Forfeits and draws give nothing, with a neutral breakdown.
		local f, fb = Ranks.matchXp(gold, ctx("Loss", { forfeit = true }))
		H.expect(f == 0 and fb.base == 0 and #fb.boosts == 0 and fb.boostTotal == 0)
		H.expect(Ranks.matchXp(gold, ctx("Win", { forfeit = true })) == 0, "never a win")
		local vip = { boosts = { vip = true, rookie = true } }
		H.expect(Ranks.matchXp(gold, ctx("Draw", vip)) == 0, "a draw")
		H.expect(Ranks.matchXp(gold, ctx("Whatever")) == 0, "unknown outcome")
		H.expect(Ranks.matchXp(gold, ctx("Win", { opponent = "Tutorial" })) == 0, "tutorial")
		H.expect(Ranks.matchXp(gold, ctx("Win", { opponent = "Solo" })) == 0, "solo")
		H.expect(Ranks.matchXp(gold, nil :: any) == 0, "no context")
		-- Never negative anywhere on the ladder.
		for index = 0, Ranks.count() do
			local rank = Ranks.fromXp(Ranks.startXp(index), index > 0)
			for _, outcome in { "Win", "Loss", "Draw" } do
				for _, opponent in { "Player", "PC" } do
					local xp = Ranks.matchXp(rank, ctx(outcome, { opponent = opponent }))
					H.expect(xp >= 0 and isWhole(xp), "never negative at " .. index)
				end
			end
		end
	end,

	["XP is never lost: a loss or a forfeit never moves a rank down"] = function()
		local Ranks = load()
		for index = 1, Ranks.count() do
			local tier, division = Ranks.at(index)
			local save = saveAt(Ranks, tier, division, 0)
			for _, context in { ctx("Loss"), ctx("Loss", { forfeit = true }), ctx("Draw") } do
				local result = Ranks.applyMatch(save, context)
				H.expect(result.delta >= 0 and result.after.index >= index, "held at " .. index)
				H.expect(result.demoted == nil, "no demoted field")
			end
		end
		-- The /xp command takes only gains.
		local save = saveAt(Ranks, "Master", 3, 100)
		for _, delta in { -5000, 0, -0.5, 0 / 0 } do
			local r = Ranks.applyXp(save, delta)
			H.expect(
				r.delta == 0 and r.xpAfter == save.RankXp and not r.promoted,
				"applyXp " .. delta
			)
			H.expect(r.ratedMatches == 10 and #r.rewards == 0)
		end
		local none = Ranks.applyXp(unranked(), -300)
		H.expect(none.after.tier == "Unranked" and none.ratedMatches == 0 and none.delta == 0)
	end,

	["wins climb the ladder all the way to Reyes"] = function()
		local Ranks = load()
		-- Challenger wins from Bronze I: every division is passed and its reward paid once.
		local save = saveAt(Ranks, "Bronze", 1, 0)
		local wins, paid = 0, 0
		local seen: { [number]: boolean } = {}
		local challenger = ctx("Win", { mode = "Challenger" })
		while save.RankXp < Ranks.startXp(Ranks.count()) do
			local result = Ranks.applyMatch(save, challenger)
			wins += 1
			H.expect(result.delta > 0 and result.after.index >= result.before.index)
			for _, reward in result.rewards do
				H.expect(not seen[reward.index], "paid twice: " .. reward.index)
				seen[reward.index] = true
				paid += 1
			end
			save = nextSave(result)
		end
		H.expect(paid == 45, "every division above Bronze I paid once, got " .. paid)
		H.expect(wins == 1818, "363,600 / 200 = 1,818 Challenger wins, got " .. wins)
		local top = Ranks.applyMatch(save, challenger)
		H.expect(top.after.tier == "Reyes" and top.delta == 200, "Reyes keeps going")
	end,

	-- Every row of the rank rewards table (the money resized with the 2026-10-11 ladder; the
	-- blocks and cues are economy v6's).
	["rank rewards are ECONOMY 2's table"] = function()
		local Ranks = load()
		local steps: { [string]: number } = {
			Bronze = 1000,
			Silver = 1250,
			Gold = 1500,
			Platinum = 2000,
			Diamond = 3000,
			Expert = 5000,
			Veteran = 10000,
			Master = 20000,
			Grandmaster = 50000,
		}
		-- { money, blocks, cue } (Bronze's block is an Uncommon one, economy v6)
		local firsts: { [string]: { any } } = {
			Bronze = { 2500, { Uncommon = 1 }, "BronzeCue" },
			Silver = { 4000, { Rare = 1 }, "SilverCue" },
			Gold = { 6000, { Rare = 1 }, "GoldCue" },
			Platinum = { 7500, { Epic = 1 }, "PlatinumCue" },
			Diamond = { 10000, { Epic = 1 }, "DiamondCue" },
			Expert = { 15000, { Legendary = 1 }, "ExpertCue" },
			Veteran = { 30000, { Legendary = 1 }, "VeteranCue" },
			Master = { 50000, { Legendary = 2 }, "MasterCue" },
			Grandmaster = { 100000, { Mythic = 1 }, "GrandmasterCue" },
			Reyes = { 1000000, { Mythic = 2 }, "ReyesCue" },
		}
		for _, tier in ALL_TIERS do
			local want = firsts[tier]
			local first = Ranks.rewardFor(Ranks.indexOf(tier, 1))
			H.expect(first.money == want[1], tier .. " I money " .. first.money)
			H.expect(sameValue(first.blocks, want[2]), tier .. " I blocks")
			H.expect(first.cue == want[3], tier .. " I cue " .. tostring(first.cue))
			if tier ~= "Reyes" then
				for division = 2, 5 do
					local step = Ranks.rewardFor(Ranks.indexOf(tier, division))
					H.expect(step.money == steps[tier], ("%s %d money"):format(tier, division))
					H.expect(
						next(step.blocks) == nil and step.cue == nil,
						tier .. " step: money only"
					)
				end
			end
		end
		local none = Ranks.rewardFor(0)
		H.expect(none.money == 0 and next(none.blocks) == nil and none.cue == nil, "Unranked")
		-- Callers get copies.
		local silver = Ranks.indexOf("Silver", 1)
		local a = Ranks.rewardFor(silver)
		a.blocks.Rare = 99
		H.expect(Ranks.rewardFor(silver).blocks.Rare == 1, "rewardFor hands out copies")
		-- Everything from Unranked to Reyes: ECONOMY's money column added up.
		local all = Ranks.rewardsBetween(0, 46)
		H.expect(#all == 46)
		local total = 0
		for _, r in all do
			total += r.money
		end
		local steps4 = (1000 + 1250 + 1500 + 2000 + 3000 + 5000 + 10000 + 20000 + 50000) * 4
		local firstSum = 2500
			+ 4000
			+ 6000
			+ 7500
			+ 10000
			+ 15000
			+ 30000
			+ 50000
			+ 100000
			+ 1000000
		H.expect(total == steps4 + firstSum, "all the rank money")
		H.expect(#Ranks.rewardsBetween(10, 10) == 0 and #Ranks.rewardsBetween(12, 3) == 0)
	end,

	["an Unranked player's first win makes them Bronze I, from 0 XP"] = function()
		local Ranks = load()
		-- A first win (100) is Bronze I, half way: one more win to Bronze II.
		local win = Ranks.applyMatch(unranked(), ctx("Win"))
		H.expect(win.before.tier == "Unranked" and win.before.index == 0)
		expectRank(win.after, "Bronze", 1, 100, "first win")
		H.expect(win.ratedMatches == 1 and win.xpBefore == 0 and win.xpAfter == 100)
		H.expect(#win.rewards == 1 and win.rewards[1].index == 1)
		H.expect(win.rewards[1].money == 2500 and win.rewards[1].cue == "BronzeCue")
		H.expect(win.rewardTotal == 2500 and win.peakAfter == 1)
		H.expect(sameValue(win.rewardBlocks, { Uncommon = 1 }), "Bronze's one block")
		H.expect(sameValue(win.rewardCues, { "BronzeCue" }))
		H.expect(win.newTier and win.promoted, "Unranked to Bronze is new")
		-- One more win: Bronze II and its step money; two more: Bronze III.
		local w2 = Ranks.applyMatch(nextSave(win), ctx("Win"))
		expectRank(w2.after, "Bronze", 2, 0, "second win")
		H.expect(w2.promoted and w2.rewardTotal == 1000, "Bronze II pays its step")
		local w3 = Ranks.applyMatch(nextSave(w2), ctx("Win"))
		local w4 = Ranks.applyMatch(nextSave(w3), ctx("Win"))
		expectRank(w3.after, "Bronze", 2, 100, "third win")
		expectRank(w4.after, "Bronze", 3, 0, "fourth win")
		-- A win against PC gives no XP since economy v6: still Unranked.
		local pc = Ranks.applyMatch(unranked(), ctx("Win", { opponent = "PC" }))
		H.expect(pc.after.tier == "Unranked" and pc.xpAfter == 0, "first PC win: Unranked")
		H.expect(pc.ratedMatches == 0 and not pc.newTier and pc.rewardTotal == 0, "PC: uncounted")
		-- A loss, a forfeit, the tutorial, or a win the anti-farm rule gives no XP leave the
		-- player Unranked and uncounted.
		for label, context in
			{
				loss = ctx("Loss"),
				forfeit = ctx("Loss", { forfeit = true }),
				tutorial = ctx("Win", { opponent = "Tutorial" }),
				farmed = ctx("Win", { farm = 0 }),
			}
		do
			local r = Ranks.applyMatch(unranked(), context)
			H.expect(r.after.tier == "Unranked" and r.after.index == 0, label .. ": Unranked")
			H.expect(r.ratedMatches == 0 and r.xpAfter == 0, label .. ": uncounted")
			H.expect(not r.promoted and not r.newTier and r.rewardTotal == 0, label .. ": no pay")
			H.expect(r.peakAfter == 0, label .. ": no peak")
		end
		-- An unrated save counts as 0 XP whatever it says.
		local odd =
			Ranks.applyMatch({ RankXp = 7000, PeakDivision = 0, RatedMatches = 0 }, ctx("Win"))
		H.expect(odd.xpBefore == 0 and odd.xpAfter == 100)
		-- A reset save (rank XP 0, its old peak kept) is paid nothing again below that peak.
		local reset =
			Ranks.applyMatch({ RankXp = 0, PeakDivision = 11, RatedMatches = 0 }, ctx("Win"))
		expectRank(reset.after, "Bronze", 1, 100, "reset save's first win")
		H.expect(#reset.rewards == 0 and reset.rewardTotal == 0 and reset.peakAfter == 11)
		-- The second match is ordinary, a loss counted.
		local second = Ranks.applyMatch(nextSave(win), ctx("Loss"))
		H.expect(second.ratedMatches == 2 and #second.rewards == 0 and not second.newTier)
		H.expect(second.delta == 0, "a loss gives nothing")
	end,

	["rank rewards are paid once per division, blocks and cues merged"] = function()
		local Ranks = load()
		-- Gold V to Platinum I: a tier's money, its Epic block and its cue.
		local r1 = Ranks.applyMatch(saveAt(Ranks, "Gold", 5, 650), ctx("Win"))
		expectRank(r1.after, "Platinum", 1, 50, "Gold V win")
		H.expect(#r1.rewards == 1 and r1.rewards[1].index == 16 and r1.rewards[1].money == 7500)
		H.expect(r1.rewardTotal == 7500 and r1.newTier and r1.promoted)
		H.expect(
			sameValue(r1.rewardBlocks, { Epic = 1 }) and sameValue(r1.rewardCues, { "PlatinumCue" })
		)
		-- Gold IV to V is a step: money only.
		local r2 = Ranks.applyMatch(saveAt(Ranks, "Gold", 4, 550), ctx("Win"))
		H.expect(r2.rewardTotal == 1500 and r2.promoted and not r2.newTier)
		H.expect(next(r2.rewardBlocks) == nil and #r2.rewardCues == 0)
		-- A jump from Bronze II to Gold II pays everything passed, in order, merged.
		local jump = Ranks.applyXp(saveAt(Ranks, "Bronze", 2, 0), 3900 - 200)
		expectRank(jump.after, "Gold", 2, 0, "jump")
		local indexes = {}
		for _, r in jump.rewards do
			table.insert(indexes, r.index)
		end
		H.expect(sameValue(indexes, { 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }), "bottom first")
		H.expect(jump.rewardTotal == 1000 * 3 + 4000 + 1250 * 4 + 6000 + 1500, "the money")
		H.expect(sameValue(jump.rewardBlocks, { Rare = 2 }), "Silver's Rare + Gold's")
		H.expect(sameValue(jump.rewardCues, { "SilverCue", "GoldCue" }), "cues bottom first")
		-- Below an old peak (a bad save's) pays nothing until past it.
		local save = saveAt(Ranks, "Expert", 1, 0, 27)
		local up = Ranks.applyXp(save, 2000)
		H.expect(up.promoted and up.after.index == 27 and #up.rewards == 0 and up.rewardTotal == 0)
		H.expect(up.peakBefore == 27 and up.peakAfter == 27)
		local past = Ranks.applyXp(nextSave(up), 3000)
		H.expect(#past.rewards == 1 and past.rewards[1].index == 28 and past.rewardTotal == 5000)
		-- The whole ladder at once: every tier's blocks.
		local everything = Ranks.applyXp(unranked(), 363600)
		H.expect(everything.after.tier == "Reyes" and #everything.rewards == 46)
		H.expect(sameValue(everything.rewardBlocks, {
			Uncommon = 1,
			Rare = 1 + 1,
			Epic = 1 + 1,
			Legendary = 1 + 1 + 2,
			Mythic = 1 + 2,
		}))
		H.expect(#everything.rewardCues == 10 and everything.rewardCues[10] == "ReyesCue")
	end,

	["difficulty unlocks: Difficult from Gold I, Challenger from Diamond I"] = function()
		local Ranks = load()
		local function at(tier: string, division: number?): any
			return Ranks.fromXp(Ranks.toXp(tier, division) :: number, tier ~= "Unranked")
		end
		H.expect(Ranks.canHost(at("Unranked"), "Classic"), "Classic always")
		H.expect(not Ranks.canHost(at("Unranked"), "Difficult"))
		H.expect(not Ranks.canHost(at("Silver", 5), "Difficult"), "Silver V: not yet")
		H.expect(Ranks.canHost(at("Gold", 1), "Difficult"), "Gold I")
		H.expect(not Ranks.canHost(at("Silver", 5), "Challenger"), "Challenger: Silver V not yet")
		H.expect(Ranks.canHost(at("Gold", 1), "Challenger"), "Challenger from Gold I")
		H.expect(Ranks.unlockName("Challenger") == "Gold 1", "shown as Gold 1")
		H.expect(Ranks.unlockName("Classic") == nil, "Classic needs nothing")
		H.expect(Ranks.canHost(at("Reyes"), "Challenger") and Ranks.canHost(at("Reyes"), "Classic"))
		H.expect(not Ranks.canHost(at("Reyes"), "Impossible"), "unknown difficulty")
		H.expect(
			not Ranks.canHost(nil :: any, "Difficult") and Ranks.canHost(nil :: any, "Classic")
		)
	end,

	["results carry the breakdown and are whole numbers; inputs are never changed"] = function()
		local Ranks = load()
		local save = saveAt(Ranks, "Diamond", 4, 333)
		local copy = table.clone(save)
		local context = ctx("Win", { mode = "Difficult", boosts = { streak = true } })
		local contextCopy = table.clone(context)
		local result = Ranks.applyMatch(save, context)
		H.expect(sameValue(save, copy), "applyMatch leaves the save alone")
		H.expect(sameValue(context, contextCopy), "and the context")
		H.expect(result.delta == 188, "150 x 1.25 = 187.5 -> 188")
		local b = result.breakdown
		H.expect(b.base == 100 and b.mode == 1.5 and b.fade == 1 and b.gap == 1 and b.pc == 1)
		H.expect(
			b.farm == 1 and b.boostTotal == 0.25 and #b.boosts == 1 and b.boosts[1].kind == "Streak"
		)
		Ranks.applyXp(save, 9999)
		H.expect(sameValue(save, copy), "applyXp leaves the save alone")
		H.expect(Ranks.applyXp(save, 10).breakdown == nil, "applyXp is not a match")
		for _, key in
			{
				"xpBefore",
				"xpAfter",
				"delta",
				"peakBefore",
				"peakAfter",
				"ratedMatches",
				"rewardTotal",
			}
		do
			H.expect(isWhole(result[key]), key .. " is whole")
		end
		for _, entry in Ranks.list() do
			H.expect(isWhole(entry.startXp) and isWhole(entry.reward), "list entry " .. entry.index)
		end
		H.expect(isWhole(Ranks.applyXp(save, 12.7).delta), "fractional delta")
	end,

	["garbage input does not crash"] = function()
		local Ranks = load()
		local nan = 0 / 0
		expectRank(Ranks.fromXp(nan, true), "Bronze", 1, 0, "NaN")
		expectRank(Ranks.fromXp(-50, true), "Bronze", 1, 0, "negative")
		expectRank(Ranks.fromXp(math.huge, true), "Bronze", 1, 0, "inf")
		expectRank(Ranks.fromXp(250.9, true), "Bronze", 2, 50, "fraction floors")
		local r = Ranks.applyMatch(
			{ RankXp = nan, PeakDivision = -3, RatedMatches = math.huge } :: any,
			ctx("Win")
		)
		H.expect(r.xpAfter == 100 and r.ratedMatches == 1, "bad save treated as fresh")
		local r2 = Ranks.applyMatch({} :: any, ctx("Loss"))
		H.expect(r2.xpAfter == 0 and r2.ratedMatches == 0, "a first loss: still Unranked")
		local r3 = Ranks.applyXp({ RankXp = 5000, PeakDivision = 999, RatedMatches = 3 }, nan)
		H.expect(r3.delta == 0 and r3.peakAfter == 46, "peak clamped to the top")
		local r4 = Ranks.applyXp(saveAt(Ranks, "Reyes", nil, 0), 1e15)
		H.expect(r4.xpAfter <= 1e9, "capped at the save's RankXpCap")
		local r5 = Ranks.applyMatch(saveAt(Ranks, "Gold", 2), { outcome = "Win" } :: any)
		H.expect(r5.delta == 0 and r5.ratedMatches == 11, "no opponent: counted, no XP")
		H.expect(select(1, Ranks.at(-4)) == "Unranked" and select(1, Ranks.at(999)) == "Reyes")
		H.expect(Ranks.name({} :: any) == "Unranked")
		H.expect(Ranks.matchXp(nil :: any, ctx("Win")) == 100, "no rank plays as Bronze")
	end,

	["roadmap list"] = function()
		local Ranks = load()
		local list = Ranks.list()
		H.expect(#list == 46)
		for i, entry in list do
			local tier, division = Ranks.at(i)
			H.expect(entry.index == i and entry.tier == tier and entry.division == division)
			H.expect(entry.startXp == Ranks.startXp(i) and entry.width == Ranks.width(i))
			local reward = Ranks.rewardFor(i)
			H.expect(entry.reward == reward.money and entry.cue == reward.cue)
			H.expect(sameValue(entry.blocks, reward.blocks))
		end
		H.expect(list[46].width == nil and list[46].reward == 1000000 and list[16].reward == 7500)
		H.expect(Ranks.rulesLine == nil and Ranks.floorXp == nil, "the loss rules are gone")
	end,

	["same inputs give the same outputs"] = function()
		local Ranks = load()
		local save = saveAt(Ranks, "Veteran", 2, 40, 33)
		for _, context in
			{
				ctx("Win", { boosts = { vip = true, streak = true }, opponentIndex = 30.5 }),
				ctx("Loss", { opponent = "PC", forfeit = true }),
				ctx("Draw"),
			}
		do
			local a = Ranks.applyMatch(save, context)
			local b = Ranks.applyMatch(save, context)
			H.expect(sameValue(a, b), "applyMatch " .. context.outcome)
		end
		H.expect(sameValue(Ranks.applyXp(save, 7777), Ranks.applyXp(save, 7777)), "applyXp")
		H.expect(sameValue(Ranks.list(), Ranks.list()))
	end,

	["a win streak counts real wins and any loss ends it"] = function()
		local Ranks = load()
		local streak = 0
		streak = Ranks.nextStreak(streak, "Win", true)
		H.expect(streak == 1, "the first win shows 1")
		streak = Ranks.nextStreak(streak, "Win", true)
		streak = Ranks.nextStreak(streak, "Win", true)
		H.expect(streak == 3, "and keeps going")
		H.expect(
			Ranks.nextStreak(streak, "Win", false) == 3,
			"a win that does not count (a quick forfeit) leaves it"
		)
		H.expect(Ranks.nextStreak(streak, "Draw", true) == 3, "a draw leaves it")
		H.expect(Ranks.nextStreak(streak, "Loss", false) == 0, "a forfeit loss ends it")
		H.expect(Ranks.nextStreak(streak, "Loss", true) == 0, "any loss ends it")
	end,
}
