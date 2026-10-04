--!strict
-- CaseDrop (Progression/CaseDrop): the Case Drop's weights, pity, the first win's Rare Case,
-- the reveal's climbs, and the per-drop chances the cue cards show, against the approved
-- economy plan (2026-10-02, section 2).

local H = require("./harness")

local function load()
	return H.require("Progression.CaseDrop"), H.require("Config")
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

-- The plan's chance per Case Drop of each rarity, in percent (as the plan prints them).
local PER_DROP = {
	Common = 61,
	Uncommon = 33.83,
	Rare = 5.0423,
	Epic = 0.10872,
	Legendary = 0.016644,
	Mythic = 0.0021197,
	Secret = 0.0002163,
}

-- The plan's chance each reveal step climbs (the lucky-block weights, 2026-10-04).
local CLIMBS = { 32, 21.875, 4.2857, 6.6667, 2 }

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

return {
	["the weights are the plan's and add to 1,000,000"] = function()
		local CaseDrop, Config = load()
		H.expect(#CaseDrop.validate() == 0, table.concat(CaseDrop.validate(), "; "))
		local total = 0
		for _, entry in CaseDrop.tiers() do
			H.expect(entry.weight == WEIGHTS[entry.tier], entry.tier)
			H.near(entry.percent, WEIGHTS[entry.tier] / 10000, 1e-9, entry.tier .. " percent")
			total += entry.weight
		end
		H.expect(total == Config.Cases.OddsTotal, "adds to OddsTotal")
		H.expect(#CaseDrop.tiers() == 6, "six tiers")
		local D = Config.Cases.Drop
		H.expect(D.PityRare == 10 and D.PityEpic == 150 and D.FirstWin == "Rare", "pity, first")
	end,

	["each rarity's chance per drop and each climb match the plan"] = function()
		local CaseDrop = load()
		local total = 0
		for _, entry in CaseDrop.rarityOdds() do
			local plan = PER_DROP[entry.rarity]
			H.near(entry.percent, plan, 0.0001, entry.rarity)
			total += entry.percent
		end
		H.near(total, 100, 1e-9, "the chances add to 100")
		H.expect(CaseDrop.rarityPercent("Epic") > 0.108, "Epic")
		H.expect(CaseDrop.rarityPercent("Nope") == 0, "unknown rarity")
		local secret = CaseDrop.rarityOdds()[7]
		H.expect(secret.rarity == "Secret" and secret.display == "0.00022%", secret.display)
		local climbs = CaseDrop.climbChances()
		H.expect(#climbs == 5, "five steps")
		for i, step in climbs do
			H.near(step.percent, CLIMBS[i], 0.0006, step.from .. " -> " .. step.to)
		end
		H.expect(climbs[1].from == "Standard" and climbs[5].to == "Mythic", "the ends")
	end,

	["a million seeded drops land on each weight (pity aside)"] = function()
		local CaseDrop, Config = load()
		local N = 1000000
		local rng = seeded(0x2545F491)
		local counts: { [string]: number } = {}
		-- Roll with no pity history each time, so the weights alone decide.
		for _ = 1, N do
			local tier = CaseDrop.roll(fresh(), rng)
			counts[tier] = (counts[tier] or 0) + 1
		end
		for tier, weight in WEIGHTS do
			local p = weight / Config.Cases.OddsTotal
			local expected = N * p
			local tolerance = 4 * math.sqrt(N * p * (1 - p)) + 1
			local got = counts[tier] or 0
			H.expect(
				math.abs(got - expected) <= tolerance,
				("%s: %d, expected %.1f +- %.1f"):format(tier, got, expected, tolerance)
			)
		end
	end,

	["pity: the 10th drop without a Rare is a Rare Case"] = function()
		local CaseDrop = load()
		local pity = fresh()
		for i = 1, 9 do
			local tier
			tier, pity = CaseDrop.roll(pity, lowest)
			H.expect(tier == "Standard", "drop " .. i)
		end
		H.expect(pity.SinceRare == 9 and pity.SinceEpic == 9 and pity.Total == 9, "counted")
		H.expect(CaseDrop.pityLeft(pity).rare == 1, "the next one is guaranteed")
		local tier
		tier, pity = CaseDrop.roll(pity, lowest)
		H.expect(tier == "Rare", "the 10th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 10, "a Rare resets only its count")
		H.expect(CaseDrop.pityLeft(pity).rare == 10, "10 to go again")
	end,

	["pity: the 150th drop without an Epic is an Epic Case, never more"] = function()
		local CaseDrop = load()
		local pity = { SinceRare = 0, SinceEpic = 148, Total = 148 }
		local tier
		tier, pity = CaseDrop.roll(pity, lowest)
		H.expect(tier == "Standard" and pity.SinceEpic == 149, "the 149th rolls")
		tier, pity = CaseDrop.roll(pity, lowest)
		H.expect(tier == "Epic", "the 150th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 0, "an Epic resets both")
		-- Both due at once: Epic wins.
		tier = CaseDrop.roll({ SinceRare = 9, SinceEpic = 149, Total = 200 }, lowest)
		H.expect(tier == "Epic", "Epic over Rare")
		-- A higher roll is never lowered by pity.
		local top = CaseDrop.roll({ SinceRare = 9, SinceEpic = 149, Total = 200 }, function(n)
			return n
		end)
		H.expect(top == "Mythic", "the top roll stays")
		-- A natural Rare or better before the limit resets the count.
		local _, after = CaseDrop.roll({ SinceRare = 5, SinceEpic = 5, Total = 5 }, function(_n)
			return 950000 -- inside Rare's weight (929,044..995,710)
		end)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 6, "a natural Rare")
	end,

	["the first win's forced Rare skips the roll and still counts"] = function()
		local CaseDrop = load()
		local tier, pity = CaseDrop.roll(fresh(), function(_n: number): number
			error("no roll for a forced drop")
		end, "Rare")
		H.expect(tier == "Rare" and pity.SinceRare == 0 and pity.SinceEpic == 1, "forced")
		H.expect(pity.Total == 1, "counted")
		H.expect(not pcall(CaseDrop.roll, fresh(), lowest, "Nope"), "an unknown tier")
		H.expect(not pcall(CaseDrop.roll, fresh(), function(n: number): number
			return n + 1
		end), "an rng out of range")
	end,

	["the payload: tier, climbs, readyAt, instant and pity left"] = function()
		local CaseDrop = load()
		local p =
			CaseDrop.payload("Win", "Epic", 1800000000, { SinceRare = 0, SinceEpic = 0, Total = 3 })
		H.expect(p.source == "Win" and p.tier == "Epic" and p.climbs == 3, "climbs")
		H.expect(p.readyAt == 1800000000 and not p.instant, "timed")
		H.expect(p.pity.rare == 10 and p.pity.epic == 150, "pity left")
		local q =
			CaseDrop.payload("Mystery", "Standard", 0, { SinceRare = 4, SinceEpic = 4, Total = 4 })
		H.expect(q.climbs == 0 and q.instant and q.pity.rare == 6 and q.pity.epic == 146, "instant")
		for i, tier in { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
			H.expect(CaseDrop.climbs(tier) == i - 1 and CaseDrop.rank(tier) == i, tier)
		end
		H.expect(CaseDrop.climbs("Nope") == 0 and CaseDrop.rank("Nope") == 0, "unknown")
		local broken = CaseDrop.readPity({ SinceRare = -2, SinceEpic = 0 / 0, Total = "x" })
		H.expect(broken.SinceRare == 0 and broken.SinceEpic == 0 and broken.Total == 0, "broken")
		H.expect(CaseDrop.readPity(nil).Total == 0, "missing")
	end,
}
