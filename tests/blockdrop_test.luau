--!strict
-- BlockDrop (Progression/BlockDrop): the Mystery block's tier weights and pity, the first
-- win's Rare block, the per-drop chances the cue cards show (the approved economy plan,
-- 2026-10-02, section 2) and whether a win drops a block at all (plan sections 1-2, 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.BlockDrop"), H.require("Config")
end

-- The plan's tier weights out of 1,000,000.
local WEIGHTS = {
	Standard = 680000,
	Uncommon = 250000,
	Rare = 67000,
	Epic = 2800,
	Legendary = 196,
	Mythic = 4,
}

-- The plan's chance per Mystery block of each rarity, in percent (as the plan prints them).
local PER_DROP = {
	Common = 61,
	Uncommon = 33.83,
	Rare = 5.0423,
	Epic = 0.10872,
	Legendary = 0.016644,
	Mythic = 0.0021197,
	Secret = 0.0002163,
}

-- A seeded xorshift32: rng(n) -> a whole number in 1..n, the same sequence every run.
local function seeded(seed: number): (number) -> number
	local state = seed
	return function(n: number): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return math.floor(state / 4294967296 * n) + 1
	end
end

local function fresh(): any
	return { SinceRare = 0, SinceEpic = 0, Total = 0 }
end

-- An rng that always lands on Standard (the first weight).
local function lowest(_n: number): number
	return 1
end

-- A settled real 1v1 win by a veteran player, overridden per test.
local function ctx(overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		real = true,
		solo = false,
		won = true,
		pcLimited = false,
		pcDropsToday = 0,
		farmAllows = true,
		dropsFromOpponentToday = 0,
		loserRealMatches = 100,
		firstWinEver = false,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

return {
	["the weights are the plan's and add to 1,000,000"] = function()
		local BlockDrop, Config = load()
		H.expect(#BlockDrop.validate() == 0, table.concat(BlockDrop.validate(), "; "))
		local total = 0
		for _, entry in BlockDrop.tiers() do
			H.expect(entry.weight == WEIGHTS[entry.tier], entry.tier)
			H.near(entry.percent, WEIGHTS[entry.tier] / 10000, 1e-9, entry.tier .. " percent")
			total += entry.weight
		end
		H.expect(total == Config.BlockOdds.OddsTotal, "adds to OddsTotal")
		H.expect(#BlockDrop.tiers() == 6, "six tiers")
		local D = Config.BlockOdds.Drop
		H.expect(D.PityRare == 10 and D.PityEpic == 150 and D.FirstWin == "Rare", "pity, first")
	end,

	["each rarity's chance per drop matches the plan"] = function()
		local BlockDrop = load()
		local total = 0
		for _, entry in BlockDrop.rarityOdds() do
			local plan = PER_DROP[entry.rarity]
			H.near(entry.percent, plan, 0.0001, entry.rarity)
			total += entry.percent
		end
		H.near(total, 100, 1e-9, "the chances add to 100")
		H.expect(BlockDrop.rarityPercent("Epic") > 0.108, "Epic")
		H.expect(BlockDrop.rarityPercent("Nope") == 0, "unknown rarity")
		local secret = BlockDrop.rarityOdds()[7]
		H.expect(secret.rarity == "Secret" and secret.display == "0.00022%", secret.display)
		-- The 8-ball reveal's climbs and payload went with the cases (2026-10-04).
		for _, gone in { "climbs", "climbChances", "payload" } do
			H.expect((BlockDrop :: any)[gone] == nil, gone .. " is gone")
		end
	end,

	["a million seeded drops land on each weight (pity aside)"] = function()
		local BlockDrop, Config = load()
		local N = 1000000
		local rng = seeded(0x2545F491)
		local counts: { [string]: number } = {}
		-- Roll with no pity history each time, so the weights alone decide.
		for _ = 1, N do
			local tier = BlockDrop.roll(fresh(), rng)
			counts[tier] = (counts[tier] or 0) + 1
		end
		for tier, weight in WEIGHTS do
			local p = weight / Config.BlockOdds.OddsTotal
			local expected = N * p
			local tolerance = 4 * math.sqrt(N * p * (1 - p)) + 1
			local got = counts[tier] or 0
			H.expect(
				math.abs(got - expected) <= tolerance,
				("%s: %d, expected %.1f +- %.1f"):format(tier, got, expected, tolerance)
			)
		end
	end,

	["pity: the 10th drop without a Rare is a Rare block"] = function()
		local BlockDrop = load()
		local pity = fresh()
		for i = 1, 9 do
			local tier
			tier, pity = BlockDrop.roll(pity, lowest)
			H.expect(tier == "Standard", "drop " .. i)
		end
		H.expect(pity.SinceRare == 9 and pity.SinceEpic == 9 and pity.Total == 9, "counted")
		H.expect(BlockDrop.pityLeft(pity).rare == 1, "the next one is guaranteed")
		local tier
		tier, pity = BlockDrop.roll(pity, lowest)
		H.expect(tier == "Rare", "the 10th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 10, "a Rare resets only its count")
		H.expect(BlockDrop.pityLeft(pity).rare == 10, "10 to go again")
	end,

	["pity: the 150th drop without an Epic is an Epic block, never more"] = function()
		local BlockDrop = load()
		local pity = { SinceRare = 0, SinceEpic = 148, Total = 148 }
		local tier
		tier, pity = BlockDrop.roll(pity, lowest)
		H.expect(tier == "Standard" and pity.SinceEpic == 149, "the 149th rolls")
		tier, pity = BlockDrop.roll(pity, lowest)
		H.expect(tier == "Epic", "the 150th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 0, "an Epic resets both")
		-- Both due at once: Epic wins.
		tier = BlockDrop.roll({ SinceRare = 9, SinceEpic = 149, Total = 200 }, lowest)
		H.expect(tier == "Epic", "Epic over Rare")
		-- A higher roll is never lowered by pity.
		local top = BlockDrop.roll({ SinceRare = 9, SinceEpic = 149, Total = 200 }, function(n)
			return n
		end)
		H.expect(top == "Mythic", "the top roll stays")
		-- A natural Rare or better before the limit resets the count.
		local _, after = BlockDrop.roll({ SinceRare = 5, SinceEpic = 5, Total = 5 }, function(_n)
			return 950000 -- inside Rare's weight (929,044..995,710)
		end)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 6, "a natural Rare")
	end,

	["the first win's forced Rare skips the roll and still counts"] = function()
		local BlockDrop = load()
		local tier, pity = BlockDrop.roll(fresh(), function(_n: number): number
			error("no roll for a forced drop")
		end, "Rare")
		H.expect(tier == "Rare" and pity.SinceRare == 0 and pity.SinceEpic == 1, "forced")
		H.expect(pity.Total == 1, "counted")
		H.expect(not pcall(BlockDrop.roll, fresh(), lowest, "Nope"), "an unknown tier")
		H.expect(not pcall(BlockDrop.roll, fresh(), function(n: number): number
			return n + 1
		end), "an rng out of range")
	end,

	["pity left, the ladder's ranks and a broken pity table"] = function()
		local BlockDrop = load()
		local left = BlockDrop.pityLeft({ SinceRare = 0, SinceEpic = 0, Total = 3 })
		H.expect(left.rare == 10 and left.epic == 150, "pity left")
		local some = BlockDrop.pityLeft({ SinceRare = 4, SinceEpic = 4, Total = 4 })
		H.expect(some.rare == 6 and some.epic == 146, "counted down")
		for i, tier in { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
			H.expect(BlockDrop.rank(tier) == i, tier)
		end
		H.expect(BlockDrop.rank("Nope") == 0 and BlockDrop.rank(nil) == 0, "unknown")
		local broken = BlockDrop.readPity({ SinceRare = -2, SinceEpic = 0 / 0, Total = "x" })
		H.expect(broken.SinceRare == 0 and broken.SinceEpic == 0 and broken.Total == 0, "broken")
		H.expect(BlockDrop.readPity(nil).Total == 0, "missing")
	end,

	["drop: every real win drops one, forever"] = function()
		local BlockDrop = load()
		for _, overrides in { {}, { loserRealMatches = 5 }, { dropsFromOpponentToday = 2 } } do
			local drops, forced = BlockDrop.dropFor(ctx(overrides))
			H.expect(drops and forced == nil, "the usual Mystery block")
		end
	end,

	["drop: the first win ever is the Rare block, under the same anti-farm rules"] = function()
		local BlockDrop, Config = load()
		local drops, forced = BlockDrop.dropFor(ctx({ firstWinEver = true }))
		H.expect(drops and forced == Config.BlockOdds.Drop.FirstWin, "the first win's block")
		H.expect(forced == "Rare", "a Rare block")
		drops = BlockDrop.dropFor(ctx({ firstWinEver = true, loserRealMatches = 4 }))
		H.expect(not drops, "a first win against a new account drops nothing")
		drops = BlockDrop.dropFor(ctx({ firstWinEver = true, farmAllows = false }))
		H.expect(not drops, "nor on a farm row")
	end,

	["drop: never for solo, a loss or a match that was not real"] = function()
		local BlockDrop = load()
		for _, overrides in { { solo = true }, { won = false }, { real = false } } do
			H.expect(not (BlockDrop.dropFor(ctx(overrides))), "no drop")
		end
	end,

	["drop: the anti-farm rules (matches 6-10, 3 a day from one account, 5 real matches)"] = function()
		local BlockDrop, Config = load()
		local E = Config.Economy
		H.expect(E.DropsPerOpponent == 3 and E.DropLoserMinMatches == 5, "the plan's numbers")
		H.expect(not (BlockDrop.dropFor(ctx({ farmAllows = false }))), "a row with no drop")
		H.expect(
			not (BlockDrop.dropFor(ctx({ dropsFromOpponentToday = E.DropsPerOpponent }))),
			"3 from one account"
		)
		H.expect(
			not (BlockDrop.dropFor(ctx({ loserRealMatches = E.DropLoserMinMatches - 1 }))),
			"a loser with too few real matches"
		)
	end,

	["drop: Play against PC drops only for the first 10 PC wins of a day"] = function()
		local BlockDrop, Config = load()
		local cap = Config.Economy.PcDropsPerDay
		H.expect(cap == 10, "the plan's 10")
		H.expect(BlockDrop.dropFor(ctx({ pcLimited = true, pcDropsToday = cap - 1 })), "the 10th")
		H.expect(not (BlockDrop.dropFor(ctx({ pcLimited = true, pcDropsToday = cap }))), "the 11th")
		H.expect(BlockDrop.dropFor(ctx({ pcLimited = false, pcDropsToday = 99 })), "people: no cap")
	end,
}
