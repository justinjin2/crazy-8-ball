--!strict
-- Ranks: total XP to rank and back, match XP, the opponent gap, boosts, peaks and rank-up
-- rewards. Every expected number is written out from docs/ECONOMY.md section 4 (not read
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

	-- ECONOMY 4.2 "The ladder": every division's width, and 4.6's fixed starts.
	["the ladder is ECONOMY 4.2's: Grandmaster I at 1,057,500, Reyes at 2,352,500"] = function()
		local Ranks = load()
		local widths: { [string]: { number } } = {
			Bronze = { 250, 250, 250, 250, 250 },
			Silver = { 350, 350, 350, 350, 350 },
			Gold = { 800, 800, 800, 800, 800 },
			Platinum = { 1200, 1200, 1200, 1200, 1200 },
			Diamond = { 8000, 9500, 11000, 13000, 15000 },
			Expert = { 17500, 20500, 24000, 28000, 33000 },
			Veteran = { 38000, 45000, 53000, 62000, 72000 },
			Master = { 85000, 100000, 115000, 135000, 160000 },
			Grandmaster = { 185000, 215000, 255000, 295000, 345000 },
		}
		local tierTotals: { [string]: number } = {
			Bronze = 1250,
			Silver = 1750,
			Gold = 4000,
			Platinum = 6000,
			Diamond = 56500,
			Expert = 123000,
			Veteran = 270000,
			Master = 595000,
			Grandmaster = 1295000,
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
		H.expect(Ranks.startXp(Ranks.indexOf("Grandmaster", 1)) == 1057500, "Grandmaster I")
		H.expect(Ranks.startXp(Ranks.indexOf("Reyes")) == 2352500, "Reyes")
		H.expect(start == 2352500)
		-- The tier starts ECONOMY quotes elsewhere.
		H.expect(Ranks.startXp(Ranks.indexOf("Silver")) == 1250)
		H.expect(Ranks.startXp(Ranks.indexOf("Diamond")) == 13000)
		H.expect(Ranks.startXp(Ranks.indexOf("Expert")) == 69500)
	end,

	["fromXp finds the division at every boundary"] = function()
		local Ranks = load()
		expectRank(Ranks.fromXp(0, true), "Bronze", 1, 0, "0")
		expectRank(Ranks.fromXp(249, true), "Bronze", 1, 249, "249")
		expectRank(Ranks.fromXp(250, true), "Bronze", 2, 0, "250")
		expectRank(Ranks.fromXp(1249, true), "Bronze", 5, 249, "1249")
		expectRank(Ranks.fromXp(1250, true), "Silver", 1, 0, "1250")
		expectRank(Ranks.fromXp(13000, true), "Diamond", 1, 0, "13000")
		expectRank(Ranks.fromXp(2352499, true), "Grandmaster", 5, 344999, "Grandmaster V top")
		local reyes = Ranks.fromXp(2352500, true)
		expectRank(reyes, "Reyes", 1, 0, "2352500")
		H.expect(reyes.index == 46 and reyes.width == nil, "Reyes has no top")
		local huge = Ranks.fromXp(123456789, true)
		expectRank(huge, "Reyes", 1, 123456789 - 2352500, "huge")
		H.expect(huge.width == nil)
		local gold3 = Ranks.fromXp(4700, true)
		H.expect(gold3.width == 800 and gold3.index == 13 and gold3.xpInDivision == 100)
		local none = Ranks.fromXp(9000, false)
		H.expect(none.tier == "Unranked" and none.index == 0 and none.division == 0)
		H.expect(none.xpInDivision == 0 and none.width == nil, "unrated is Unranked")
	end,

	["startXp width and toXp"] = function()
		local Ranks = load()
		H.expect(Ranks.startXp(0) == 0 and Ranks.startXp(1) == 0 and Ranks.startXp(2) == 250)
		H.expect(Ranks.startXp(46) == 2352500)
		H.expect(Ranks.width(0) == nil and Ranks.width(46) == nil and Ranks.width(1) == 250)
		H.expect(Ranks.toXp("gold", 3, 520) == 4600 + 520, "Gold III 520")
		H.expect(Ranks.toXp("gold", 3, 5000) == 4600 + 799, "clamped into the division")
		H.expect(Ranks.toXp("gold", 3, -5) == 4600, "negative into is 0")
		H.expect(Ranks.toXp("reyes", nil, 99999) == 2352500 + 99999, "Reyes unbounded")
		H.expect(Ranks.toXp("unranked") == 0 and Ranks.toXp("golden") == nil)
		for index = 1, Ranks.count() do
			local tier, division = Ranks.at(index)
			local rank = Ranks.fromXp(Ranks.toXp(tier, division, 7), true)
			H.expect(rank.index == index and rank.xpInDivision == 7, "toXp/fromXp at " .. index)
		end
	end,

	["display names and badge keys"] = function()
		local Ranks = load()
		H.expect(Ranks.name(Ranks.fromXp(4600, true)) == "Gold III", "Gold III")
		H.expect(Ranks.name(Ranks.fromXp(2352500, true)) == "Reyes", "Reyes")
		H.expect(Ranks.name(Ranks.fromXp(0, false)) == "Unranked", "Unranked")
		H.expect(Ranks.name(Ranks.fromXp(0, true)) == "Bronze I", "Bronze I")
		H.expect(Ranks.name(Ranks.fromXp(2352499, true)) == "Grandmaster V")
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

	-- ECONOMY 4.2, "XP for a win and a loss against an equal opponent": every cell.
	["match XP is ECONOMY 4.2's table, every tier, mode and result"] = function()
		local Ranks = load()
		-- Tier -> { Classic win, loss, Difficult win, loss, Challenger win, loss }.
		local table42: { [string]: { number } } = {
			Bronze = { 250, 100, 312, 125, 375, 150 },
			Silver = { 250, 75, 312, 94, 375, 112 },
			Gold = { 250, 50, 312, 62, 375, 75 },
			Platinum = { 250, 25, 312, 31, 375, 38 },
			Diamond = { 125, 0, 312, 0, 375, 0 },
			Expert = { 90, 0, 562, 0, 675, 0 },
			Veteran = { 90, 0, 562, 0, 675, 0 },
			Master = { 90, 0, 562, 0, 675, 0 },
			Grandmaster = { 90, 0, 562, 0, 675, 0 },
			Reyes = { 90, 0, 562, 0, 675, 0 },
		}
		local modes = { "Classic", "Difficult", "Challenger" }
		local checked = 0
		for _, tier in ALL_TIERS do
			local rank = Ranks.fromXp(Ranks.toXp(tier, 1, 10), true)
			for m, mode in modes do
				for r, outcome in { "Win", "Loss" } do
					local want = table42[tier][(m - 1) * 2 + r]
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
		H.expect(Ranks.matchXp(none, ctx("Loss")) == 100, "Unranked loses like Bronze")
		H.expect(Ranks.matchXp(none, ctx("Win", { mode = "Difficult" })) == 312)
		local diamond = Ranks.fromXp(Ranks.toXp("Diamond", 1), true)
		local noMode = { outcome = "Win", opponent = "Player" }
		H.expect(Ranks.matchXp(diamond, noMode) == 125, "default Classic")
		H.expect(Ranks.matchXp(diamond, ctx("Win", { mode = "Hard" })) == 125, "unknown mode")
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

	["the gap scales wins, and a loss's small XP at most x1"] = function()
		local Ranks = load()
		local silver = Ranks.fromXp(Ranks.toXp("Silver", 5), true) -- index 10
		-- Beating a player 5 divisions below: 250 x 0.554 = 138.49 -> 138.
		local xp, b = Ranks.matchXp(silver, ctx("Win", { opponentIndex = 5 }))
		H.near(b.gap, 0.554, 0.001, "gap in the breakdown")
		H.expect(xp == 138, "a win over a weaker player, got " .. xp)
		-- Beating a stronger one pays more; losing to one gives the plain loss (capped at 1).
		H.expect(Ranks.matchXp(silver, ctx("Win", { opponentIndex = 15 })) == 362, "x1.446")
		local lossUp, lb = Ranks.matchXp(silver, ctx("Loss", { opponentIndex = 15 }))
		H.expect(lossUp == 75 and lb.gap == 1, "a loss never gets more than x1")
		-- Losing to a much weaker player gives less: 9 below, 75 x 0.302 = 22.66 -> 23; at the
		-- floor, Platinum V losing to Bronze I: 25 x 0.3 = 7.5 -> 8.
		H.expect(Ranks.matchXp(silver, ctx("Loss", { opponentIndex = 1 })) == 23)
		local platinum = Ranks.fromXp(Ranks.toXp("Platinum", 5), true)
		H.expect(Ranks.matchXp(platinum, ctx("Loss", { opponentIndex = 1 })) == 8)
		-- From Expert the strict scale: Expert I beating Diamond I (5 lower): 90 x 0.383.
		local expert = Ranks.fromXp(Ranks.toXp("Expert", 1), true)
		H.expect(Ranks.matchXp(expert, ctx("Win", { opponentIndex = 21 })) == 35)
		H.expect(
			Ranks.matchXp(expert, ctx("Win", { mode = "Challenger", opponentIndex = 21 })) == 259
		)
	end,

	["PC XP: x0.75 to Diamond, x0.5 from Expert"] = function()
		local Ranks = load()
		local pc = { opponent = "PC" }
		-- 250 x 0.75 = 187.5 -> 188; a loss 100 x 0.75 = 75.
		H.expect(xpAt(Ranks, "Bronze", ctx("Win", pc)) == 188)
		H.expect(xpAt(Ranks, "Bronze", ctx("Loss", pc)) == 75)
		-- Diamond Classic: 125 x 0.75 = 93.75 -> 94; Diamond V is still the Low share.
		H.expect(xpAt(Ranks, "Diamond", ctx("Win", pc)) == 94)
		local diamond5 = Ranks.fromXp(Ranks.toXp("Diamond", 5), true)
		local _, low = Ranks.matchXp(diamond5, ctx("Win", pc))
		H.expect(low.pc == 0.75)
		-- Expert: Classic 90 x 0.5 = 45, Challenger 675 x 0.5 = 337.5 -> 338.
		H.expect(xpAt(Ranks, "Expert", ctx("Win", pc)) == 45)
		H.expect(xpAt(Ranks, "Expert", ctx("Win", { opponent = "PC", mode = "Challenger" })) == 338)
		local _, high = Ranks.matchXp(Ranks.fromXp(Ranks.toXp("Reyes"), true), ctx("Win", pc))
		H.expect(high.pc == 0.5)
	end,

	["boosts add: a new VIP's first win of the day is x3.5"] = function()
		local Ranks = load()
		local bronze = Ranks.fromXp(Ranks.toXp("Bronze", 2), true)
		local all = { rookie = true, vip = true, firstWin = true }
		local xp, b = Ranks.matchXp(bronze, ctx("Win", { boosts = all }))
		H.expect(xp == 875, "250 x 3.5, got " .. xp)
		H.expect(b.boostTotal == 2.5, "1 + 0.5 + 1")
		H.expect(#b.boosts == 3 and b.boosts[1].kind == "Rookie" and b.boosts[1].share == 1)
		H.expect(b.boosts[2].kind == "Vip" and b.boosts[2].share == 0.5)
		H.expect(b.boosts[3].kind == "FirstWin" and b.boosts[3].share == 1)
		-- The Rookie Boost alone is x2 ("ROOKIE x2"); with VIP x2.5 (ECONOMY 2).
		H.expect(Ranks.matchXp(bronze, ctx("Win", { boosts = { rookie = true } })) == 500)
		H.expect(
			Ranks.matchXp(bronze, ctx("Win", { boosts = { rookie = true, vip = true } })) == 625
		)
		-- The streak: +25% on a win against people. 250 x 1.25 = 312.5 -> 312.
		local streak, sb = Ranks.matchXp(bronze, ctx("Win", { boosts = { streak = true } }))
		H.expect(streak == 312 and sb.boosts[1].kind == "Streak" and sb.boosts[1].share == 0.25)
		-- Every boost at once, in order.
		local four = { rookie = true, vip = true, firstWin = true, streak = true }
		local x4, b4 = Ranks.matchXp(bronze, ctx("Win", { boosts = four }))
		H.expect(x4 == 938 and #b4.boosts == 4 and b4.boosts[4].kind == "Streak", "x3.75")
		-- A loss keeps Rookie and VIP but never FirstWin or Streak: 100 x 2.5.
		local lx, lb = Ranks.matchXp(bronze, ctx("Loss", { boosts = four }))
		H.expect(lx == 250 and #lb.boosts == 2 and lb.boostTotal == 1.5, "loss boosts")
		-- Against PC the streak does not count (people only); the first win does.
		local pcx, pcb = Ranks.matchXp(bronze, ctx("Win", { opponent = "PC", boosts = four }))
		H.expect(#pcb.boosts == 3 and pcx == 656, "187.5 x 3.5 = 656.25")
		-- From Diamond a loss is 0 whatever the boosts.
		H.expect(xpAt(Ranks, "Diamond", ctx("Loss", { boosts = four })) == 0)
		-- The top: Expert Challenger with every boost: 675 x 3.75 = 2531.25.
		H.expect(xpAt(Ranks, "Expert", ctx("Win", { mode = "Challenger", boosts = four })) == 2531)
	end,

	["anti-farm XP, draws, forfeits and other opponents give what they should"] = function()
		local Ranks = load()
		local gold = Ranks.fromXp(Ranks.toXp("Gold", 2), true)
		-- ECONOMY 3.6: matches 6-10 half the XP, from 11 none.
		H.expect(Ranks.matchXp(gold, ctx("Win", { farm = 0.5 })) == 125)
		H.expect(Ranks.matchXp(gold, ctx("Loss", { farm = 0.5 })) == 25)
		local zero, zb = Ranks.matchXp(gold, ctx("Win", { farm = 0 }))
		H.expect(zero == 0 and zb.farm == 0 and zb.base == 250)
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
		H.expect(wins > 3000 and wins < 4000, "about 3,500 Challenger wins, got " .. wins)
		local top = Ranks.applyMatch(save, challenger)
		H.expect(top.after.tier == "Reyes" and top.delta == 675, "Reyes keeps going")
	end,

	-- ECONOMY 4.8: every row of the rewards table.
	["rank rewards are ECONOMY 4.8's table"] = function()
		local Ranks = load()
		local steps: { [string]: number } = {
			Bronze = 50,
			Silver = 75,
			Gold = 150,
			Platinum = 250,
			Diamond = 1500,
			Expert = 3000,
			Veteran = 5000,
			Master = 8000,
			Grandmaster = 15000,
		}
		local firsts: { [string]: { any } } = {
			Bronze = { 100, "Standard", 2, "BronzeCue" },
			Silver = { 300, "Rare", 1, "SilverCue" },
			Gold = { 600, "Rare", 2, "GoldCue" },
			Platinum = { 1200, "Epic", 1, "PlatinumCue" },
			Diamond = { 3000, "Epic", 2, "DiamondCue" },
			Expert = { 10000, "Legendary", 2, "ExpertCue" },
			Veteran = { 15000, "Legendary", 3, "VeteranCue" },
			Master = { 25000, "Legendary", 5, "MasterCue" },
			Grandmaster = { 50000, "Legendary", 10, "GrandmasterCue" },
			Reyes = { 150000, "Legendary", 25, "ReyesCue" },
		}
		for _, tier in ALL_TIERS do
			local want = firsts[tier]
			local first = Ranks.rewardFor(Ranks.indexOf(tier, 1))
			H.expect(first.money == want[1], tier .. " I money " .. first.money)
			H.expect(sameValue(first.cases, { [want[2]] = want[3] }), tier .. " I cases")
			H.expect(first.cue == want[4], tier .. " I cue " .. tostring(first.cue))
			if tier ~= "Reyes" then
				for division = 2, 5 do
					local step = Ranks.rewardFor(Ranks.indexOf(tier, division))
					H.expect(step.money == steps[tier], ("%s %d money"):format(tier, division))
					H.expect(
						next(step.cases) == nil and step.cue == nil,
						tier .. " step: money only"
					)
				end
			end
		end
		local none = Ranks.rewardFor(0)
		H.expect(none.money == 0 and next(none.cases) == nil and none.cue == nil, "Unranked")
		-- Callers get copies.
		local a = Ranks.rewardFor(1)
		a.cases.Standard = 99
		H.expect(Ranks.rewardFor(1).cases.Standard == 2, "rewardFor hands out copies")
		-- Everything from Unranked to Reyes: ECONOMY's money column added up.
		local all = Ranks.rewardsBetween(0, 46)
		H.expect(#all == 46)
		local total = 0
		for _, r in all do
			total += r.money
		end
		local steps4 = (50 + 75 + 150 + 250 + 1500 + 3000 + 5000 + 8000 + 15000) * 4
		local firstSum = 100 + 300 + 600 + 1200 + 3000 + 10000 + 15000 + 25000 + 50000 + 150000
		H.expect(total == steps4 + firstSum, "all the rank money")
		H.expect(#Ranks.rewardsBetween(10, 10) == 0 and #Ranks.rewardsBetween(12, 3) == 0)
	end,

	["an Unranked player's first match makes them rated, from 0 XP"] = function()
		local Ranks = load()
		-- A first win (250) passes Bronze I into Bronze II and pays both.
		local win = Ranks.applyMatch(unranked(), ctx("Win"))
		H.expect(win.before.tier == "Unranked" and win.before.index == 0)
		expectRank(win.after, "Bronze", 2, 0, "first win")
		H.expect(win.ratedMatches == 1 and win.xpBefore == 0 and win.xpAfter == 250)
		H.expect(#win.rewards == 2 and win.rewards[1].index == 1 and win.rewards[2].index == 2)
		H.expect(win.rewards[1].money == 100 and win.rewards[1].cue == "BronzeCue")
		H.expect(win.rewardTotal == 150 and win.peakAfter == 2)
		H.expect(
			sameValue(win.rewardCases, { Standard = 2 })
				and sameValue(win.rewardCues, { "BronzeCue" })
		)
		H.expect(win.newTier and win.promoted, "Unranked to Bronze is new")
		-- The tutorial (ECONOMY 3.2) gives no XP: it places the player at Bronze I.
		local tutorial = Ranks.applyMatch(unranked(), ctx("Win", { opponent = "Tutorial" }))
		expectRank(tutorial.after, "Bronze", 1, 0, "tutorial")
		H.expect(tutorial.ratedMatches == 1 and tutorial.rewardTotal == 100 and tutorial.newTier)
		local loss = Ranks.applyMatch(unranked(), ctx("Loss"))
		expectRank(loss.after, "Bronze", 1, 100, "first loss")
		H.expect(loss.ratedMatches == 1 and loss.newTier and loss.rewardTotal == 100)
		local forfeit = Ranks.applyMatch(unranked(), ctx("Loss", { forfeit = true }))
		expectRank(forfeit.after, "Bronze", 1, 0, "first forfeit")
		H.expect(forfeit.ratedMatches == 1 and forfeit.promoted)
		-- An unrated save counts as 0 XP whatever it says.
		local odd =
			Ranks.applyMatch({ RankXp = 7000, PeakDivision = 0, RatedMatches = 0 }, ctx("Win"))
		H.expect(odd.xpBefore == 0 and odd.xpAfter == 250)
		-- The second match is ordinary.
		local second = Ranks.applyMatch(nextSave(win), ctx("Loss"))
		H.expect(second.ratedMatches == 2 and #second.rewards == 0 and not second.newTier)
	end,

	["rank rewards are paid once per division, cases and cues merged"] = function()
		local Ranks = load()
		-- Gold V to Platinum I: a tier's money, its Epic Case and its cue.
		local r1 = Ranks.applyMatch(saveAt(Ranks, "Gold", 5, 700), ctx("Win"))
		expectRank(r1.after, "Platinum", 1, 150, "Gold V win")
		H.expect(#r1.rewards == 1 and r1.rewards[1].index == 16 and r1.rewards[1].money == 1200)
		H.expect(r1.rewardTotal == 1200 and r1.newTier and r1.promoted)
		H.expect(
			sameValue(r1.rewardCases, { Epic = 1 }) and sameValue(r1.rewardCues, { "PlatinumCue" })
		)
		-- Gold IV to V is a step: money only.
		local r2 = Ranks.applyMatch(saveAt(Ranks, "Gold", 4, 600), ctx("Win"))
		H.expect(r2.rewardTotal == 150 and r2.promoted and not r2.newTier)
		H.expect(next(r2.rewardCases) == nil and #r2.rewardCues == 0)
		-- A jump from Bronze II to Gold II pays everything passed, in order, merged.
		local jump = Ranks.applyXp(saveAt(Ranks, "Bronze", 2, 0), 3800 - 250)
		expectRank(jump.after, "Gold", 2, 0, "jump")
		local indexes = {}
		for _, r in jump.rewards do
			table.insert(indexes, r.index)
		end
		H.expect(sameValue(indexes, { 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 }), "bottom first")
		H.expect(jump.rewardTotal == 50 * 3 + 300 + 75 * 4 + 600 + 150, "the money")
		H.expect(sameValue(jump.rewardCases, { Rare = 3 }), "Silver's Rare + Gold's two")
		H.expect(sameValue(jump.rewardCues, { "SilverCue", "GoldCue" }), "cues bottom first")
		-- Below an old peak (a bad save's) pays nothing until past it.
		local save = saveAt(Ranks, "Expert", 1, 0, 27)
		local up = Ranks.applyXp(save, 17500)
		H.expect(up.promoted and up.after.index == 27 and #up.rewards == 0 and up.rewardTotal == 0)
		H.expect(up.peakBefore == 27 and up.peakAfter == 27)
		local past = Ranks.applyXp(nextSave(up), 20500)
		H.expect(#past.rewards == 1 and past.rewards[1].index == 28 and past.rewardTotal == 3000)
		-- The whole ladder at once: 45 tiers' worth of cases.
		local everything = Ranks.applyXp(unranked(), 2352500)
		H.expect(everything.after.tier == "Reyes" and #everything.rewards == 46)
		H.expect(
			sameValue(
				everything.rewardCases,
				{ Standard = 2, Rare = 3, Epic = 3, Legendary = 2 + 3 + 5 + 10 + 25 }
			)
		)
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
		H.expect(not Ranks.canHost(at("Platinum", 5), "Challenger"), "Platinum V: not yet")
		H.expect(Ranks.canHost(at("Diamond", 1), "Challenger"), "Diamond I")
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
		local context = ctx("Win", { mode = "Difficult", boosts = { vip = true } })
		local contextCopy = table.clone(context)
		local result = Ranks.applyMatch(save, context)
		H.expect(sameValue(save, copy), "applyMatch leaves the save alone")
		H.expect(sameValue(context, contextCopy), "and the context")
		H.expect(result.delta == 469, "312.5 x 1.5 = 468.75")
		local b = result.breakdown
		H.expect(b.base == 250 and b.mode == 1.25 and b.fade == 1 and b.gap == 1 and b.pc == 1)
		H.expect(
			b.farm == 1 and b.boostTotal == 0.5 and #b.boosts == 1 and b.boosts[1].kind == "Vip"
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
		expectRank(Ranks.fromXp(300.9, true), "Bronze", 2, 50, "fraction floors")
		local r = Ranks.applyMatch(
			{ RankXp = nan, PeakDivision = -3, RatedMatches = math.huge } :: any,
			ctx("Win")
		)
		H.expect(r.xpAfter == 250 and r.ratedMatches == 1, "bad save treated as fresh")
		local r2 = Ranks.applyMatch({} :: any, ctx("Loss"))
		H.expect(r2.xpAfter == 100 and r2.ratedMatches == 1)
		local r3 = Ranks.applyXp({ RankXp = 5000, PeakDivision = 999, RatedMatches = 3 }, nan)
		H.expect(r3.delta == 0 and r3.peakAfter == 46, "peak clamped to the top")
		local r4 = Ranks.applyXp(saveAt(Ranks, "Reyes", nil, 0), 1e15)
		H.expect(r4.xpAfter <= 1e9, "capped at the save's RankXpCap")
		local r5 = Ranks.applyMatch(saveAt(Ranks, "Gold", 2), { outcome = "Win" } :: any)
		H.expect(r5.delta == 0 and r5.ratedMatches == 11, "no opponent: counted, no XP")
		H.expect(select(1, Ranks.at(-4)) == "Unranked" and select(1, Ranks.at(999)) == "Reyes")
		H.expect(Ranks.name({} :: any) == "Unranked")
		H.expect(Ranks.matchXp(nil :: any, ctx("Win")) == 250, "no rank plays as Bronze")
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
			H.expect(sameValue(entry.cases, reward.cases))
		end
		H.expect(list[46].width == nil and list[46].reward == 150000 and list[16].reward == 1200)
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
