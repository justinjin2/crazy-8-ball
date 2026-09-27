--!strict
-- Ranks: total XP to rank and back, match XP, the tier floor, peaks and rank-up money.

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

	["fromXp finds the division at every boundary"] = function()
		local Ranks = load()
		expectRank(Ranks.fromXp(0, true), "Bronze", 1, 0, "0")
		expectRank(Ranks.fromXp(999, true), "Bronze", 1, 999, "999")
		expectRank(Ranks.fromXp(1000, true), "Bronze", 2, 0, "1000")
		expectRank(Ranks.fromXp(4999, true), "Bronze", 5, 999, "4999")
		expectRank(Ranks.fromXp(5000, true), "Silver", 1, 0, "5000")
		expectRank(Ranks.fromXp(44999, true), "Grandmaster", 5, 999, "44999")
		local reyes = Ranks.fromXp(45000, true)
		expectRank(reyes, "Reyes", 1, 0, "45000")
		H.expect(reyes.index == 46 and reyes.width == nil, "Reyes has no top")
		local huge = Ranks.fromXp(123456789, true)
		expectRank(huge, "Reyes", 1, 123456789 - 45000, "huge")
		H.expect(huge.width == nil)
		H.expect(Ranks.fromXp(2500, true).width == 1000 and Ranks.fromXp(2500, true).index == 3)
		local none = Ranks.fromXp(9000, false)
		H.expect(none.tier == "Unranked" and none.index == 0 and none.division == 0)
		H.expect(none.xpInDivision == 0 and none.width == nil, "unrated is Unranked")
	end,

	["startXp width and toXp"] = function()
		local Ranks = load()
		H.expect(Ranks.startXp(0) == 0 and Ranks.startXp(1) == 0 and Ranks.startXp(2) == 1000)
		H.expect(Ranks.startXp(46) == 45000)
		H.expect(Ranks.width(0) == nil and Ranks.width(46) == nil and Ranks.width(1) == 1000)
		H.expect(Ranks.toXp("gold", 3, 520) == 12520, "Gold III 520")
		H.expect(Ranks.toXp("gold", 3, 5000) == 12999, "clamped into the division")
		H.expect(Ranks.toXp("gold", 3, -5) == 12000, "negative into is 0")
		H.expect(Ranks.toXp("reyes", nil, 99999) == 45000 + 99999, "Reyes unbounded")
		H.expect(Ranks.toXp("unranked") == 0 and Ranks.toXp("golden") == nil)
		for index = 1, Ranks.count() do
			local tier, division = Ranks.at(index)
			local rank = Ranks.fromXp(Ranks.toXp(tier, division, 7), true)
			H.expect(rank.index == index and rank.xpInDivision == 7, "toXp/fromXp at " .. index)
		end
	end,

	["display names and badge keys"] = function()
		local Ranks = load()
		H.expect(Ranks.name(Ranks.fromXp(12000, true)) == "Gold III", "Gold III")
		H.expect(Ranks.name(Ranks.fromXp(45000, true)) == "Reyes", "Reyes")
		H.expect(Ranks.name(Ranks.fromXp(0, false)) == "Unranked", "Unranked")
		H.expect(Ranks.name(Ranks.fromXp(0, true)) == "Bronze I", "Bronze I")
		H.expect(Ranks.name(Ranks.fromXp(44999, true)) == "Grandmaster V")
		H.expect(Ranks.tierName("gold") == "Gold" and Ranks.tierName("unranked") == "Unranked")
		H.expect(Ranks.badgeKey("Gold", 3) == "gold_3", "gold_3")
		H.expect(Ranks.badgeKey("reyes", 1) == "reyes", "reyes")
		H.expect(Ranks.badgeKey("Unranked", 0) == "unranked", "unranked")
		H.expect(Ranks.badgeKey("Grandmaster", 5) == "grandmaster_5")
		H.expect(Ranks.badgeKey("nonsense", 2) == "unranked", "unknown tier")
	end,

	["four wins climb a division, all the way to Reyes"] = function()
		local Ranks = load()
		local save = saveAt(Ranks, "Bronze", 1, 0)
		local wins = 0
		while save.RankXp < Ranks.startXp(Ranks.count()) do
			local before = Ranks.fromXp(save.RankXp, true)
			local result = Ranks.applyMatch(save, "Win", "Player", false)
			wins += 1
			H.expect(result.delta == 250, "a win is +250")
			H.expect(result.promoted == (wins % 4 == 0), "promoted on every fourth win")
			H.expect(result.after.index == before.index + (if wins % 4 == 0 then 1 else 0))
			save = nextSave(result)
		end
		H.expect(wins == 45 * 4, "180 wins from Bronze I to Reyes, got " .. wins)
		local top = Ranks.applyMatch(save, "Win", "Player", false)
		H.expect(top.after.tier == "Reyes" and top.after.xpInDivision == 250, "Reyes keeps going")
	end,

	["loss XP by tier, draws and forfeits"] = function()
		local Ranks = load()
		local function lossAt(tier: string, forfeit: boolean): number
			return Ranks.matchXp(
				Ranks.fromXp(Ranks.toXp(tier, 2, 500), true),
				"Loss",
				"Player",
				forfeit
			)
		end
		for _, tier in { "Bronze", "Silver", "Gold" } do
			H.expect(lossAt(tier, false) == 50, tier .. " loss +50")
			H.expect(lossAt(tier, true) == 0, tier .. " forfeit 0, never +50")
		end
		for _, tier in { "Platinum", "Diamond" } do
			H.expect(lossAt(tier, false) == 0 and lossAt(tier, true) == 0, tier .. " loss 0")
		end
		for _, tier in { "Expert", "Veteran", "Master", "Grandmaster", "Reyes" } do
			H.expect(lossAt(tier, false) == -150, tier .. " loss -150")
			H.expect(lossAt(tier, true) == -150, tier .. " forfeit -150")
		end
		local gold = Ranks.fromXp(12000, true)
		H.expect(Ranks.matchXp(gold, "Draw", "Player", false) == 0, "draw")
		H.expect(Ranks.matchXp(gold, "Whatever", "Player", false) == 0, "unknown outcome")
		H.expect(Ranks.matchXp(gold, "Win", "Player", true) == 0, "a forfeit is never a win")
		local unrankedRank = Ranks.fromXp(0, false)
		H.expect(Ranks.matchXp(unrankedRank, "Loss", "Player", false) == 50, "Unranked: Bronze")
		local result = Ranks.applyMatch(saveAt(Ranks, "Gold", 2, 500), "Loss", "Player", false)
		H.expect(result.delta == 50 and result.after.xpInDivision == 550, "a Gold loss applied")
		local diamond = Ranks.applyMatch(saveAt(Ranks, "Diamond", 1, 0), "Loss", "Player", false)
		H.expect(diamond.delta == 0 and not diamond.demoted, "Diamond loses nothing")
	end,

	["a PC win is half"] = function()
		local Ranks = load()
		local rank = Ranks.fromXp(12000, true)
		H.expect(Ranks.matchXp(rank, "Win", "PC", false) == 125, "PC win 125")
		H.expect(Ranks.matchXp(rank, "Win", "Player", false) == 250, "Player win 250")
		H.expect(Ranks.matchXp(Ranks.fromXp(31000, true), "Loss", "PC", false) == -150)
		local result = Ranks.applyMatch(saveAt(Ranks, "Bronze", 1, 0), "Win", "PC", false)
		H.expect(result.xpAfter == 125)
	end,

	["losses above Diamond stop at division I of the tier"] = function()
		local Ranks = load()
		-- Master III, 100 XP in: a loss drops to Master II.
		local r1 = Ranks.applyMatch(saveAt(Ranks, "Master", 3, 100), "Loss", "Player", false)
		expectRank(r1.after, "Master", 2, 950, "Master III loss")
		H.expect(r1.demoted and not r1.promoted and r1.delta == -150)
		H.expect(r1.peakAfter == r1.peakBefore and #r1.rewards == 0, "no reward for falling")
		-- Master I, 100 XP in: only down to Master I 0.
		local r2 = Ranks.applyMatch(saveAt(Ranks, "Master", 1, 100), "Loss", "Player", false)
		expectRank(r2.after, "Master", 1, 0, "Master I floor")
		H.expect(r2.delta == -100 and not r2.demoted)
		-- Many losses from Master III never reach Veteran.
		local save = saveAt(Ranks, "Master", 3, 100)
		for _ = 1, 40 do
			save = nextSave(Ranks.applyMatch(save, "Loss", "Player", true))
		end
		H.expect(save.RankXp == Ranks.toXp("Master", 1, 0), "held at Master I 0")
		H.expect(Ranks.floorXp(save.RankXp) == save.RankXp)
		-- Expert I at 0 stays put.
		local r3 = Ranks.applyMatch(saveAt(Ranks, "Expert", 1, 0), "Loss", "Player", false)
		expectRank(r3.after, "Expert", 1, 0, "Expert I 0")
		H.expect(r3.delta == 0 and not r3.demoted and not r3.promoted)
		H.expect(Ranks.floorXp(Ranks.toXp("Gold", 4, 300)) == Ranks.toXp("Gold", 1, 0))
		H.expect(Ranks.floorXp(123456789) == 45000, "Reyes' floor is its start")
	end,

	["an Unranked player's first match makes them Bronze I"] = function()
		local Ranks = load()
		local win = Ranks.applyMatch(unranked(), "Win", "Player", false)
		H.expect(win.before.tier == "Unranked" and win.before.index == 0)
		expectRank(win.after, "Bronze", 1, 250, "first win")
		H.expect(win.ratedMatches == 1 and win.xpBefore == 0 and win.xpAfter == 250)
		H.expect(#win.rewards == 1 and win.rewards[1].index == 1 and win.rewards[1].amount == 100)
		H.expect(win.rewardTotal == 100 and win.peakAfter == 1)
		H.expect(win.newTier and win.promoted and not win.demoted, "Unranked to Bronze is new")
		local loss = Ranks.applyMatch(unranked(), "Loss", "Player", false)
		expectRank(loss.after, "Bronze", 1, 50, "first loss")
		H.expect(loss.ratedMatches == 1 and loss.newTier and loss.rewardTotal == 100)
		local forfeit = Ranks.applyMatch(unranked(), "Loss", "Player", true)
		expectRank(forfeit.after, "Bronze", 1, 0, "first forfeit")
		H.expect(forfeit.ratedMatches == 1 and forfeit.promoted)
		-- An unrated save counts as 0 XP whatever it says.
		local odd = Ranks.applyMatch(
			{ RankXp = 7000, PeakDivision = 0, RatedMatches = 0 },
			"Win",
			"Player",
			false
		)
		H.expect(odd.xpBefore == 0 and odd.xpAfter == 250)
		-- The second match is ordinary.
		local second = Ranks.applyMatch(nextSave(win), "Win", "Player", false)
		H.expect(second.ratedMatches == 2 and #second.rewards == 0 and not second.newTier)
	end,

	["rank-up money is paid once per division"] = function()
		local Ranks = load()
		-- Gold V to Platinum I.
		local r1 = Ranks.applyMatch(saveAt(Ranks, "Gold", 5, 999), "Win", "Player", false)
		expectRank(r1.after, "Platinum", 1, 249, "Gold V win")
		H.expect(#r1.rewards == 1 and r1.rewards[1].index == 16 and r1.rewards[1].amount == 1000)
		H.expect(r1.rewardTotal == 1000 and r1.newTier and r1.promoted)
		-- Gold IV to V is a step.
		local r2 = Ranks.applyMatch(saveAt(Ranks, "Gold", 4, 800), "Win", "Player", false)
		H.expect(r2.rewardTotal == 200 and r2.promoted and not r2.newTier)
		-- A jump from Bronze II to Silver II pays everything passed, in order.
		local jump = Ranks.applyXp(saveAt(Ranks, "Bronze", 2, 0), 5000)
		expectRank(jump.after, "Silver", 2, 0, "jump")
		local expected = {
			{ index = 3, amount = 100 },
			{ index = 4, amount = 100 },
			{ index = 5, amount = 100 },
			{ index = 6, amount = 500 },
			{ index = 7, amount = 150 },
		}
		H.expect(sameValue(jump.rewards, expected), "Bronze III to Silver II, bottom first")
		H.expect(jump.rewardTotal == 950 and jump.newTier)
		-- Falling and climbing back pays nothing: the peak stays.
		local save = saveAt(Ranks, "Expert", 2, 0)
		local down = Ranks.applyMatch(save, "Loss", "Player", false)
		H.expect(down.demoted and down.peakAfter == 27, "Expert II peak kept")
		local up = Ranks.applyMatch(nextSave(down), "Win", "Player", false)
		H.expect(up.promoted and up.after.index == 27 and #up.rewards == 0 and up.rewardTotal == 0)
		H.expect(up.peakBefore == 27 and up.peakAfter == 27)
		-- Past the old peak pays again.
		local past = Ranks.applyXp(nextSave(up), 1000)
		H.expect(#past.rewards == 1 and past.rewards[1].index == 28 and past.rewardTotal == 600)
		-- The table itself.
		H.expect(
			Ranks.rewardFor(0) == 0 and Ranks.rewardFor(1) == 100 and Ranks.rewardFor(46) == 25000
		)
		H.expect(
			Ranks.rewardFor(2) == 100
				and Ranks.rewardFor(41) == 7500
				and Ranks.rewardFor(45) == 1500
		)
		H.expect(#Ranks.rewardsBetween(10, 10) == 0 and #Ranks.rewardsBetween(12, 3) == 0)
		H.expect(#Ranks.rewardsBetween(0, 46) == 46)
	end,

	["applyXp: losses through the floor, gains across tiers"] = function()
		local Ranks = load()
		local down = Ranks.applyXp(saveAt(Ranks, "Master", 3, 100), -5000)
		expectRank(down.after, "Master", 1, 0, "applyXp floor")
		H.expect(down.delta == -2100 and down.demoted and down.ratedMatches == 10)
		local low = Ranks.applyXp(saveAt(Ranks, "Bronze", 3, 10), -99999)
		expectRank(low.after, "Bronze", 1, 0, "Bronze floor is 0")
		local up = Ranks.applyXp(saveAt(Ranks, "Gold", 5, 500), 1600)
		expectRank(up.after, "Platinum", 2, 100, "applyXp across a tier")
		H.expect(up.newTier and up.rewardTotal == 1000 + 300 and up.ratedMatches == 10)
		-- A gain on an Unranked save makes it rated at Bronze I first; a loss does nothing.
		local first = Ranks.applyXp(unranked(), 1200)
		expectRank(first.after, "Bronze", 2, 200, "Unranked gain")
		H.expect(first.ratedMatches == 1 and first.rewardTotal == 200 and first.newTier)
		local none = Ranks.applyXp(unranked(), -300)
		H.expect(none.after.tier == "Unranked" and none.ratedMatches == 0 and none.delta == 0)
		H.expect(#none.rewards == 0 and not none.promoted and not none.demoted)
		local zero = Ranks.applyXp(saveAt(Ranks, "Gold", 2, 10), 0)
		H.expect(zero.delta == 0 and zero.xpAfter == zero.xpBefore)
	end,

	["results are whole numbers and inputs are never changed"] = function()
		local Ranks = load()
		local save = saveAt(Ranks, "Diamond", 4, 333)
		local copy = table.clone(save)
		local result = Ranks.applyMatch(save, "Win", "PC", false)
		H.expect(sameValue(save, copy), "applyMatch leaves the save alone")
		Ranks.applyXp(save, -9999)
		H.expect(sameValue(save, copy), "applyXp leaves the save alone")
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
		expectRank(Ranks.fromXp(1500.9, true), "Bronze", 2, 500, "fraction floors")
		local r = Ranks.applyMatch(
			{ RankXp = nan, PeakDivision = -3, RatedMatches = math.huge } :: any,
			"Win",
			"Player",
			false
		)
		H.expect(r.xpAfter == 250 and r.ratedMatches == 1, "bad save treated as fresh")
		local r2 = Ranks.applyMatch({} :: any, "Loss", "Player", false)
		H.expect(r2.xpAfter == 50 and r2.ratedMatches == 1)
		local r3 = Ranks.applyXp({ RankXp = 5000, PeakDivision = 999, RatedMatches = 3 }, nan)
		H.expect(r3.delta == 0 and r3.peakAfter == 46, "peak clamped to the top")
		local r4 = Ranks.applyXp(saveAt(Ranks, "Reyes", nil, 0), 1e15)
		H.expect(r4.xpAfter <= 1e9, "capped at the save's RankXpCap")
		H.expect(select(1, Ranks.at(-4)) == "Unranked" and select(1, Ranks.at(999)) == "Reyes")
		H.expect(Ranks.name({} :: any) == "Unranked")
	end,

	["roadmap list and rules line"] = function()
		local Ranks = load()
		local list = Ranks.list()
		H.expect(#list == 46)
		for i, entry in list do
			local tier, division = Ranks.at(i)
			H.expect(entry.index == i and entry.tier == tier and entry.division == division)
			H.expect(entry.startXp == Ranks.startXp(i) and entry.width == Ranks.width(i))
			H.expect(entry.reward == Ranks.rewardFor(i))
		end
		H.expect(list[46].width == nil and list[46].reward == 25000 and list[16].reward == 1000)
		local line = Ranks.rulesLine()
		H.expect(line.win == 250 and line.lowLoss == 50 and line.highLoss == -150)
		H.expect(sameValue(line.lossTiersLow, { "Bronze", "Silver", "Gold" }))
		H.expect(sameValue(line.freeTiers, { "Platinum", "Diamond" }))
		H.expect(
			sameValue(line.loseTiers, { "Expert", "Veteran", "Master", "Grandmaster", "Reyes" })
		)
	end,

	["same inputs give the same outputs"] = function()
		local Ranks = load()
		local save = saveAt(Ranks, "Veteran", 2, 40, 33)
		for _, args in
			{ { "Win", "Player", false }, { "Loss", "PC", true }, { "Draw", "Player", false } }
		do
			local a = Ranks.applyMatch(save, args[1], args[2], args[3])
			local b = Ranks.applyMatch(save, args[1], args[2], args[3])
			H.expect(sameValue(a, b), "applyMatch " .. args[1])
		end
		H.expect(sameValue(Ranks.applyXp(save, 7777), Ranks.applyXp(save, 7777)), "applyXp")
		H.expect(
			sameValue(Ranks.list(), Ranks.list())
				and sameValue(Ranks.rulesLine(), Ranks.rulesLine())
		)
	end,
}
