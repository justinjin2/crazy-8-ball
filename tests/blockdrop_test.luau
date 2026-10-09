--!strict
-- BlockDrop (Progression/BlockDrop): the Mystery block's tier weights and pity, the first
-- win's Rare block, the per-drop chances the cue cards show, the presses' path and the daily
-- win track (economy v4 plan, 2026-10-08, sections 3 and 5), and whether a win gives a block
-- at all (the anti-farm rules, ECONOMY 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.BlockDrop"), H.require("Config")
end

-- The v4 plan's tier weights out of 1,000,000 (section 3.1).
local WEIGHTS = {
	Standard = 500000,
	Uncommon = 400000,
	Rare = 95200,
	Epic = 4200,
	Legendary = 500,
	Mythic = 100,
}

-- The v4 plan's chance per Mystery block of each rarity, in percent (as the plan prints them).
local PER_DROP = {
	Common = 52.25,
	Uncommon = 40.5736,
	Rare = 6.79586,
	Epic = 0.32688,
	Legendary = 0.046268,
	Mythic = 0.0066328,
	Secret = 0.0007592,
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
		trackToday = 0,
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
		H.expect(D.PityRare == 10 and D.PityEpic == 100 and D.FirstWin == "Rare", "pity, first")
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
		H.expect(BlockDrop.rarityPercent("Epic") > 0.32, "Epic")
		H.expect(BlockDrop.rarityPercent("Nope") == 0, "unknown rarity")
		local secret = BlockDrop.rarityOdds()[7]
		H.expect(secret.rarity == "Secret" and secret.display == "0.0008%", secret.display)
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

	["pity: the 100th drop without an Epic is an Epic block, never more"] = function()
		local BlockDrop = load()
		local pity = { SinceRare = 0, SinceEpic = 98, Total = 98 }
		local tier
		tier, pity = BlockDrop.roll(pity, lowest)
		H.expect(tier == "Standard" and pity.SinceEpic == 99, "the 99th rolls")
		tier, pity = BlockDrop.roll(pity, lowest)
		H.expect(tier == "Epic", "the 100th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 0, "an Epic resets both")
		-- Both due at once: Epic wins.
		tier = BlockDrop.roll({ SinceRare = 9, SinceEpic = 99, Total = 200 }, lowest)
		H.expect(tier == "Epic", "Epic over Rare")
		-- A higher roll is never lowered by pity.
		local top = BlockDrop.roll({ SinceRare = 9, SinceEpic = 99, Total = 200 }, function(n)
			return n
		end)
		H.expect(top == "Mythic", "the top roll stays")
		-- A natural Rare or better before the limit resets the count.
		local _, after = BlockDrop.roll({ SinceRare = 5, SinceEpic = 5, Total = 5 }, function(_n)
			return 950000 -- inside Rare's weight (900,001..995,200)
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
		H.expect(left.rare == 10 and left.epic == 100, "pity left")
		local some = BlockDrop.pityLeft({ SinceRare = 4, SinceEpic = 4, Total = 4 })
		H.expect(some.rare == 6 and some.epic == 96, "counted down")
		for i, tier in { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } do
			H.expect(BlockDrop.rank(tier) == i, tier)
		end
		H.expect(BlockDrop.rank("Nope") == 0 and BlockDrop.rank(nil) == 0, "unknown")
		local broken = BlockDrop.readPity({ SinceRare = -2, SinceEpic = 0 / 0, Total = "x" })
		H.expect(broken.SinceRare == 0 and broken.SinceEpic == 0 and broken.Total == 0, "broken")
		H.expect(BlockDrop.readPity(nil).Total == 0, "missing")
	end,

	["drop: the daily win track gives its 10 steps' blocks, then money and XP only"] = function()
		local BlockDrop, Config = load()
		local plan = "Rare Mystery Mystery Uncommon Mystery Mystery Rare Mystery Mystery Epic"
		H.expect(table.concat(Config.BlockOdds.Drop.WinTrack, " ") == plan, "the plan's track")
		H.expect(BlockDrop.trackSteps() == 10, "10 steps")
		local got = {}
		for given = 0, 9 do
			local drops, kind = BlockDrop.dropFor(ctx({ trackToday = given }))
			H.expect(drops, "step " .. given + 1)
			table.insert(got, kind)
		end
		H.expect(table.concat(got, " ") == plan, table.concat(got, " "))
		H.expect(not (BlockDrop.dropFor(ctx({ trackToday = 10 }))), "win 11: no block")
		H.expect(not (BlockDrop.dropFor(ctx({ trackToday = 99 }))), "and later")
		H.expect(BlockDrop.trackKind(11) == nil, "past the track")
		for _, overrides in { { loserRealMatches = 5 }, { dropsFromOpponentToday = 2 } } do
			local drops, kind = BlockDrop.dropFor(ctx(overrides))
			H.expect(drops and kind == "Rare", "the first step")
		end
	end,

	["drop: the first win ever is the Rare block, under the same anti-farm rules"] = function()
		local BlockDrop, Config = load()
		local drops, forced = BlockDrop.dropFor(ctx({ firstWinEver = true }))
		H.expect(drops and forced == Config.BlockOdds.Drop.FirstWin, "the first win's block")
		H.expect(forced == "Rare", "a Rare block")
		local _, later = BlockDrop.dropFor(ctx({ firstWinEver = true, trackToday = 1 }))
		H.expect(later == "Rare", "still the Rare block on a later step")
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

	["upgrade path: five presses from Standard, climbs only, ending on the roll"] = function()
		local BlockDrop, Config = load()
		local order = Config.BlockOdds.Order
		local clicks = Config.BlockOdds.Drop.Upgrade.Clicks
		H.expect(clicks == 5, "the v4 plan's five presses")
		local rng = seeded(4242)
		for _, final in order do
			local climbs = BlockDrop.rank(final) - 1
			for _ = 1, 300 do
				local path = BlockDrop.path(final, rng)
				H.expect(#path == clicks, "five tiers")
				H.expect(path[#path] == final, "ends on the roll")
				local up = BlockDrop.rank(path[1]) - 1
				H.expect(up == 0 or up == 1, "the first press lifts Standard at most once")
				for i = 2, #path do
					local step = BlockDrop.rank(path[i]) - BlockDrop.rank(path[i - 1])
					H.expect(step == 0 or step == 1, "stays or goes up one")
					up += step
				end
				H.expect(up == climbs, "climbs exactly once per tier above Standard")
			end
		end
		H.expect(
			table.concat(BlockDrop.path("Mythic", rng), ",")
				== "Uncommon,Rare,Epic,Legendary,Mythic",
			"a Mythic climbs on every press"
		)
		H.expect(
			table.concat(BlockDrop.path("Standard", rng), ",")
				== "Standard,Standard,Standard,Standard,Standard",
			"a Standard never moves"
		)
	end,

	["upgrade path: every choice of climbing presses is equally likely"] = function()
		local BlockDrop = load()
		local rng = seeded(99)
		-- A Rare climbs on 2 of the 5 presses: 10 ways, each about 1 in 10.
		local seen: { [string]: number } = {}
		local n = 50000
		for _ = 1, n do
			local key = table.concat(BlockDrop.path("Rare", rng), ",")
			seen[key] = (seen[key] or 0) + 1
		end
		local ways = 0
		for _, count in seen do
			ways += 1
			local tolerance = 4 * math.sqrt(n * 0.1 * 0.9)
			H.expect(
				math.abs(count - n / 10) <= tolerance,
				("%d, expected %d"):format(count, n / 10)
			)
		end
		H.expect(ways == 10, "10 ways: " .. ways)
		-- An Uncommon climbs on the last press about 1 time in 5.
		local last = 0
		for _ = 1, n do
			local path = BlockDrop.path("Uncommon", rng)
			if path[4] == "Standard" then
				last += 1
			end
		end
		H.expect(math.abs(last - n / 5) <= 4 * math.sqrt(n * 0.2 * 0.8), "the last press")
	end,

	["the Mystery block's cues: each one's chance, equal within a rarity, adding to 100"] = function()
		local BlockDrop = load()
		for _, floor in { nil, "Rare", "Epic" } :: { string? } do
			local label = tostring(floor)
			local chances = BlockDrop.cueChances(floor)
			local rarities: { [string]: number } = {}
			for _, entry in BlockDrop.rarityOdds(floor) do
				rarities[entry.rarity] = entry.percent
			end
			local total, seen = 0, {}
			for _, group in BlockDrop.cueGroups(floor) do
				total += group.percent
				local want = rarities[group.rarity] or -1
				H.expect(
					math.abs(group.percent - want) <= want * 1e-9,
					("%s %s: %s, rarityOdds %s"):format(label, group.rarity, group.percent, want)
				)
				for _, cue in group.cues do
					H.expect(not seen[cue], label .. ": " .. cue .. " twice")
					seen[cue] = true
					-- "each" is true of every cue in the group (the list shows one value).
					local chance = chances[cue] or 0
					H.expect(
						math.abs(chance - group.each) <= group.each * 1e-9,
						("%s %s: %s, not each %s"):format(label, cue, chance, group.each)
					)
				end
			end
			H.expect(math.abs(total - 100) < 1e-9, ("%s: adds to %s"):format(label, total))
			for cue in chances do
				H.expect(seen[cue], label .. ": " .. cue .. " missing")
			end
		end
	end,

	["pity's live floor: the guaranteed tier and the odds the screen shows then"] = function()
		local BlockDrop, Config = load()
		local D = Config.BlockOdds.Drop
		H.expect(BlockDrop.floorOf({ rare = 1, epic = 50 }) == "Rare", "Rare due")
		H.expect(BlockDrop.floorOf({ rare = 1, epic = 1 }) == "Epic", "both due: Epic")
		H.expect(BlockDrop.floorOf({ rare = 4, epic = 1 }) == "Epic", "Epic due")
		H.expect(BlockDrop.floorOf({ rare = 4, epic = 40 }) == nil, "none due")
		H.expect(BlockDrop.floorOf(nil) == nil and BlockDrop.floorOf("x") == nil, "broken: none")
		-- The floor agrees with pityLeft and the roll: one drop before each guarantee.
		local function left(sinceRare: number, sinceEpic: number)
			return BlockDrop.pityLeft({ SinceRare = sinceRare, SinceEpic = sinceEpic, Total = 0 })
		end
		H.expect(BlockDrop.floorOf(left(D.PityRare - 1, 0)) == "Rare", "the 10th is Rare")
		H.expect(BlockDrop.floorOf(left(D.PityRare - 2, 0)) == nil, "the 9th is not")
		H.expect(BlockDrop.floorOf(left(0, D.PityEpic - 1)) == "Epic", "the 100th is Epic")
		local function percents(floor: string?): { [string]: number }
			local out, total = {}, 0
			for _, tier in BlockDrop.tiers(floor) do
				out[tier.tier] = tier.percent
				total += tier.percent
			end
			H.near(total, 100, 1e-9, "adds to 100")
			return out
		end
		local epic = percents("Epic")
		H.expect(
			epic.Standard == nil and epic.Uncommon == nil and epic.Rare == nil,
			"under Epic: gone"
		)
		H.near(epic.Epic, 99.94, 1e-9, "Epic takes the tiers under it")
		H.near(epic.Legendary, 0.05, 1e-9, "Legendary as before")
		H.near(epic.Mythic, 0.01, 1e-9, "Mythic as before")
		local rare = percents("Rare")
		H.near(rare.Rare, 99.52, 1e-9, "Rare takes Standard and Uncommon")
		H.near(rare.Epic, 0.42, 1e-9, "Epic as before")
		local plain = percents(nil)
		H.near(plain.Standard, 50, 1e-9, "no floor: the weights")
		-- The rolls under each floor land on those odds.
		local rng = seeded(31)
		local n = 200000
		local counts: { [string]: number } = {}
		for _ = 1, n do
			local tier =
				BlockDrop.roll({ SinceRare = 0, SinceEpic = D.PityEpic - 1, Total = 0 }, rng)
			counts[tier] = (counts[tier] or 0) + 1
		end
		for tier, percent in epic do
			local p = percent / 100
			H.expect(
				math.abs((counts[tier] or 0) - n * p) <= 4 * math.sqrt(n * p * (1 - p)) + 1,
				tier .. " under the Epic floor"
			)
		end
		-- The rarities under a floor still add to 100 and never give a Common.
		local total = 0
		for _, row in BlockDrop.rarityOdds("Epic") do
			H.expect(row.rarity ~= "Common" and row.rarity ~= "Uncommon", "no " .. row.rarity)
			total += row.percent
		end
		H.near(total, 100, 1e-9, "rarities under the Epic floor")
	end,

	["upgrade path: the first press's odds follow the weights"] = function()
		local BlockDrop, Config = load()
		local C = Config.BlockOdds
		local first = BlockDrop.firstOdds()
		local sum = 0
		for _, tier in C.Order do
			H.expect(first[tier] >= 0, tier .. " is not negative")
			sum += first[tier]
		end
		H.expect(math.abs(sum - 1) < 1e-9, "the first press's odds add to 1")
		-- Uncommon: each final tier's weight times its climbs / 5.
		local up = 0
		for _, tier in C.Order do
			up += C.Drop.Weights[tier] / C.OddsTotal * (BlockDrop.rank(tier) - 1) / 5
		end
		H.near(first.Uncommon, up, 1e-12, "Uncommon")
		H.expect(first.Rare == 0 and first.Mythic == 0, "the first press only lifts to Uncommon")
		H.expect(first.Standard > 0.8, "mostly Standard after the first press")
	end,
}
