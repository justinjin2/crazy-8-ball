--!strict
-- BlockDrop (Progression/BlockDrop): the climb (economy v5 plan, 2026-10-09, section 3): one
-- ladder for every block, the Grand Opening Luck, the Mystery block's pity with its head start,
-- every block's odds lists, the climb screen's path from any start, the "1 in N", and the daily
-- win track with its money steps (section 4), and whether a win moves it at all (the anti-farm
-- rules, ECONOMY 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.BlockDrop"), H.require("Config")
end

-- The plan's ladder (3.2) in parts of a million, and the launch's two steps.
local STEPS = {
	Standard = 500000,
	Uncommon = 350000,
	Rare = 180000,
	Epic = 100000,
	Legendary = 150000,
	Mythic = 25000,
}
local LUCK = { Rare = 270000, Epic = 150000 }

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- The plan's tables 3.3 and 3.4: each block's rarities in percent, as the plan prints them (to
-- 7 decimals at most, so within half a last digit; they are exact products of the steps).
local PLAN = {
	Standard = { 50, 32.5, 14.35, 2.835, 0.26775, 0.0460688, 0.00118125 },
	Uncommon = { 0, 65, 28.7, 5.67, 0.5355, 0.0921375, 0.0023625 },
	Rare = { 0, 0, 82, 16.2, 1.53, 0.26325, 0.00675 },
	Epic = { 0, 0, 0, 90, 8.5, 1.4625, 0.0375 },
	Legendary = { 0, 0, 0, 0, 85, 14.625, 0.375 },
	Mythic = { 0, 0, 0, 0, 0, 97.5, 2.5 },
}
local PLAN_LUCK = {
	Standard = { 50, 32.5, 12.775, 4.01625, 0.6024375, 0.1036547, 0.0026578 },
	Uncommon = { 0, 65, 25.55, 8.0325, 1.204875, 0.2073094, 0.0053156 },
	Rare = { 0, 0, 73, 22.95, 3.4425, 0.5923125, 0.0151875 },
	Epic = { 0, 0, 0, 85, 12.75, 2.19375, 0.05625 },
	Legendary = { 0, 0, 0, 0, 85, 14.625, 0.375 },
	Mythic = { 0, 0, 0, 0, 0, 97.5, 2.5 },
}
-- The plan's "or better" table (3.3) as 1 in N, rounded as it prints them: Epic+, Legendary+,
-- Mythic+, the Secret.
local ONE_IN = {
	Standard = { 32, 317, 2116, 84656 },
	Uncommon = { 16, 159, 1058, 42328 },
	Rare = { 5.6, 56, 370, 14815 },
	Epic = { 1, 10, 67, 2667 },
	Legendary = { 1, 1, 6.7, 267 },
	Mythic = { 1, 1, 1, 40 },
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

-- An rng that never climbs (the top of every draw).
local function never(n: number): number
	return n
end

-- An rng that always climbs (the bottom of every draw).
local function always(_n: number): number
	return 1
end

-- 1 in N as the plan prints it: a whole number from 10 up, one decimal under 10.
local function printed(percent: number): number
	local n = 100 / percent
	if n >= 10 then
		return math.floor(n + 0.5)
	end
	return math.floor(n * 10 + 0.5) / 10
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

-- Sets the Grand Opening deal's StartsAt for `f`, then puts it back.
local function withStart(Config: any, startsAt: number, f: () -> ())
	local deal = Config.Shop.Deals.GrandOpening
	local was = deal.StartsAt
	deal.StartsAt = startsAt
	local ok, err = pcall(f)
	deal.StartsAt = was
	if not ok then
		error(err, 0)
	end
end

return {
	["the ladder is the plan's: six steps, the Secret on top, the launch's two steps"] = function()
		local BlockDrop, Config = load()
		H.expect(#BlockDrop.validate() == 0, table.concat(BlockDrop.validate(), "; "))
		local CL = Config.BlockOdds.Climb
		H.expect(
			table.concat(CL.Tiers, " ") == "Standard Uncommon Rare Epic Legendary Mythic Secret",
			"seven tiers"
		)
		for tier, parts in STEPS do
			H.expect(CL.Steps[tier] == parts, tier)
			H.expect(BlockDrop.stepParts(tier) == parts, tier .. " step")
			H.expect(BlockDrop.stepParts(tier, true) == (LUCK[tier] or parts), tier .. " luck")
		end
		H.expect(BlockDrop.stepParts("Secret") == 0, "nothing above the Secret")
		H.expect(CL.Luck.Steps.Rare == 270000 and CL.Luck.Steps.Epic == 150000, "launch steps")
		H.expect(CL.Luck.With == "GrandOpening" and CL.Luck.Seconds == 30 * 86400, "30 days")
		for i, tier in CL.Tiers do
			H.expect(BlockDrop.rank(tier) == i, tier .. " rank")
			H.expect(BlockDrop.rarityOf(tier) == RARITIES[i], tier .. " rarity")
		end
		H.expect(BlockDrop.rank("Nope") == 0 and BlockDrop.rank(nil) == 0, "unknown")
		H.expect(BlockDrop.isBlockTier("Mythic") and not BlockDrop.isBlockTier("Secret"), "blocks")
		local D = Config.BlockOdds.Drop
		H.expect(D.PityRare == 10 and D.PityEpic == 40 and D.FirstWin == "Rare", "pity, first")
		H.expect(D.Upgrade.Clicks == 4, "four presses")
		H.expect((D :: any).Weights == nil and (D.Upgrade :: any).Chances == nil, "v4's tables go")
	end,

	["every block's odds are the plan's table 3.3, exactly"] = function()
		local BlockDrop = load()
		for start, row in PLAN do
			local got: { [string]: number } = {}
			local total = 0
			for _, entry in BlockDrop.rarityOdds(nil, { start = start }) do
				got[entry.rarity] = entry.percent
				total += entry.percent
			end
			H.near(total, 100, 1e-9, start .. " adds to 100")
			for i, rarity in RARITIES do
				H.near(got[rarity] or 0, row[i], 6e-8, start .. " " .. rarity)
			end
			-- The tier list says the same, tier by tier.
			for _, tier in BlockDrop.tiers(nil, { start = start }) do
				H.near(tier.percent, got[BlockDrop.rarityOf(tier.tier) :: string], 1e-12, tier.tier)
				H.near(tier.weight, tier.percent * 10000, 1e-6, tier.tier .. " weight")
			end
		end
		-- The Mystery block's list is the Standard start's.
		local mystery = BlockDrop.rarityOdds()
		H.near(mystery[1].percent, 50, 1e-12, "Mystery Common")
		H.near(mystery[7].percent, 0.00118125, 1e-15, "Mystery Secret")
		H.expect(mystery[7].display == "0.001%", mystery[7].display)
	end,

	["the Grand Opening Luck's odds are the plan's table 3.4, exactly"] = function()
		local BlockDrop = load()
		for start, row in PLAN_LUCK do
			local got: { [string]: number } = {}
			for _, entry in BlockDrop.rarityOdds(nil, { start = start, luck = true }) do
				got[entry.rarity] = entry.percent
			end
			for i, rarity in RARITIES do
				H.near(got[rarity] or 0, row[i], 6e-8, start .. " " .. rarity .. " (luck)")
			end
		end
		-- A Mystery during the luck (plan 3.4): Epic+ 4.725% (1 in 21), Legendary+ 0.70875%
		-- (1 in 141), Mythic+ 1 in 941, the Secret 1 in 37,625.
		local c = BlockDrop.chances(nil, { luck = true })
		local epicUp = c.Epic + c.Legendary + c.Mythic + c.Secret
		local legUp = c.Legendary + c.Mythic + c.Secret
		H.near(epicUp * 100, 4.725, 1e-12, "Epic+")
		H.near(legUp * 100, 0.70875, 1e-12, "Legendary+")
		H.expect(printed(epicUp * 100) == 21 and printed(legUp * 100) == 141, "1 in 21, 141")
		H.expect(printed((c.Mythic + c.Secret) * 100) == 941, "1 in 941")
		H.expect(printed(c.Secret * 100) == 37625, "1 in 37,625")
	end,

	["the 'or better' chances are the plan's (3.3)"] = function()
		local BlockDrop = load()
		for start, want in ONE_IN do
			local c = BlockDrop.chances(nil, { start = start })
			local function sum(tiers: { string }): number
				local total = 0
				for _, tier in tiers do
					total += c[tier] or 0
				end
				return total * 100
			end
			local up = {
				sum({ "Epic", "Legendary", "Mythic", "Secret" }),
				sum({ "Legendary", "Mythic", "Secret" }),
				sum({ "Mythic", "Secret" }),
				sum({ "Secret" }),
			}
			for i, n in want do
				H.expect(
					printed(up[i]) == n,
					("%s #%d: 1 in %s, not %s"):format(start, i, printed(up[i]), n)
				)
			end
		end
		local c = BlockDrop.chances()
		H.near((c.Epic + c.Legendary + c.Mythic + c.Secret) * 100, 3.15, 1e-12, "Mystery Epic+")
		H.near((c.Legendary + c.Mythic + c.Secret) * 100, 0.315, 1e-12, "Mystery Legendary+")
		H.near((c.Mythic + c.Secret) * 100, 0.04725, 1e-12, "Mystery Mythic+")
	end,

	["each step is one draw at or under its chance; the climb stops at the first miss"] = function()
		local BlockDrop = load()
		-- A draw equal to the step's parts climbs; the top of the next draw stops it.
		for tier, parts in STEPS do
			local next = BlockDrop.ladder()[BlockDrop.rank(tier) + 1]
			local draws = { parts }
			local i = 0
			local final = BlockDrop.climbRoll(tier, function(n: number): number
				i += 1
				H.expect(n == 1000000, "a draw out of a million")
				return draws[i] or n
			end)
			H.expect(final == next, tier .. ": climbs one, then stops at " .. final)
		end
		for tier, parts in STEPS do
			H.expect(BlockDrop.climbRoll(tier, function(_n: number): number
				return parts + 1
			end) == tier, tier .. ": one over its chance stays")
		end
		-- The launch's steps change exactly those two draws.
		local final = BlockDrop.climbRoll("Rare", function(_n: number): number
			return 270000
		end, false)
		H.expect(final == "Rare", "270,000 misses Rare's 18%")
		final = BlockDrop.climbRoll(
			"Rare",
			(function()
				local i = 0
				return function(n: number): number
					i += 1
					return if i == 1 then 270000 else n
				end
			end)(),
			true
		)
		H.expect(final == "Epic", "270,000 climbs under the luck")
		H.expect(BlockDrop.climbRoll("Standard", always) == "Secret", "always: the Secret")
		H.expect(BlockDrop.climbRoll("Mythic", never) == "Mythic", "never: stays")
		H.expect(BlockDrop.climbRoll("Rare", never) == "Rare", "the name is the floor")
		H.expect(not pcall(BlockDrop.climbRoll, "Nope", never), "an unknown start")
		H.expect(not pcall(BlockDrop.climbRoll, "Standard", function(n: number): number
			return n + 1
		end), "an rng out of range")
	end,

	["seeded climbs land on the listed odds from every start, with and without the luck"] = function()
		local BlockDrop = load()
		local rng = seeded(0x2545F491)
		for _, luck in { false, true } do
			for _, start in { "Standard", "Uncommon", "Rare", "Epic" } do
				local n = 200000
				local counts: { [string]: number } = {}
				for _ = 1, n do
					local tier = BlockDrop.climbRoll(start, rng, luck)
					counts[tier] = (counts[tier] or 0) + 1
				end
				for tier, p in BlockDrop.chances(nil, { start = start, luck = luck }) do
					local expected = n * p
					local tolerance = 4 * math.sqrt(n * p * (1 - p)) + 1
					local got = counts[tier] or 0
					H.expect(
						math.abs(got - expected) <= tolerance,
						("%s %s luck %s: %d, expected %.1f"):format(
							start,
							tier,
							tostring(luck),
							got,
							expected
						)
					)
				end
			end
		end
	end,

	["pity: the 10th Mystery block without a Rare ends on exactly Rare"] = function()
		local BlockDrop = load()
		local pity = fresh()
		for i = 1, 9 do
			local tier
			tier, pity = BlockDrop.roll(pity, never)
			H.expect(tier == "Standard", "Mystery block " .. i)
		end
		H.expect(pity.SinceRare == 9 and pity.SinceEpic == 9 and pity.Total == 9, "counted")
		H.expect(BlockDrop.pityLeft(pity).rare == 1, "the next one is guaranteed")
		local tier
		tier, pity = BlockDrop.roll(pity, never)
		H.expect(tier == "Rare", "the 10th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 10, "a Rare resets only its count")
		H.expect(BlockDrop.pityLeft(pity).rare == 10, "10 to go again")
	end,

	["pity: the 40th without an Epic ends on exactly Epic, never more or less"] = function()
		local BlockDrop = load()
		local pity = { SinceRare = 0, SinceEpic = 38, Total = 38 }
		local tier
		tier, pity = BlockDrop.roll(pity, never)
		H.expect(tier == "Standard" and pity.SinceEpic == 39, "the 39th climbs as usual")
		tier, pity = BlockDrop.roll(pity, never)
		H.expect(tier == "Epic", "the 40th: " .. tier)
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 0, "an Epic resets both")
		-- Both due at once: Epic wins.
		tier = BlockDrop.roll({ SinceRare = 9, SinceEpic = 39, Total = 200 }, never)
		H.expect(tier == "Epic", "Epic over Rare")
		-- A higher climb is never lowered by pity.
		tier = BlockDrop.roll({ SinceRare = 9, SinceEpic = 39, Total = 200 }, always)
		H.expect(tier == "Secret", "the top climb stays")
		-- A natural Rare or better before the limit resets the count.
		local draws, i = { 1, 1, 1000000 }, 0
		local natural, after = BlockDrop.roll(
			{ SinceRare = 5, SinceEpic = 5, Total = 5 },
			function(n)
				i += 1
				return draws[i] or n
			end
		)
		H.expect(natural == "Rare", "a natural Rare: " .. natural)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 6, "its counts")
		-- The live floors' lists match what a due roll does, seeded.
		local rng = seeded(31)
		local n = 200000
		local counts: { [string]: number } = {}
		for _ = 1, n do
			local t = BlockDrop.roll({ SinceRare = 0, SinceEpic = 39, Total = 0 }, rng)
			counts[t] = (counts[t] or 0) + 1
		end
		for t, p in BlockDrop.chances("Epic") do
			H.expect(
				math.abs((counts[t] or 0) - n * p) <= 4 * math.sqrt(n * p * (1 - p)) + 1,
				t .. " under the Epic floor"
			)
		end
	end,

	["pity's head start: a new save begins at 2 / 10 and 10 / 40"] = function()
		local BlockDrop, Config = load()
		local start = BlockDrop.freshPity()
		H.expect(start.SinceRare == 2 and start.SinceEpic == 10 and start.Total == 0, "the counts")
		local left = BlockDrop.pityLeft(start)
		H.expect(left.rare == 8 and left.epic == 30, "8 and 30 to go")
		-- The first Epic is guaranteed by the 30th Mystery block.
		local pity, tier = start, ""
		for i = 1, 30 do
			tier, pity = BlockDrop.roll(pity, never)
			if i < 30 then
				H.expect(tier == "Standard" or tier == "Rare", ("block %d: %s"):format(i, tier))
			end
		end
		H.expect(tier == "Epic", "the 30th: " .. tier)
		H.expect(Config.BlockOdds.Drop.PityStart.SinceRare == 2, "Config")
	end,

	["the first win's forced Rare skips the roll and still counts"] = function()
		local BlockDrop = load()
		local tier, pity = BlockDrop.roll(fresh(), function(_n: number): number
			error("no roll for a forced drop")
		end, "Rare")
		H.expect(tier == "Rare" and pity.SinceRare == 0 and pity.SinceEpic == 1, "forced")
		H.expect(pity.Total == 1, "counted")
		H.expect(not pcall(BlockDrop.roll, fresh(), never, "Nope"), "an unknown tier")
	end,

	["pity left and a broken pity table"] = function()
		local BlockDrop = load()
		local left = BlockDrop.pityLeft({ SinceRare = 0, SinceEpic = 0, Total = 3 })
		H.expect(left.rare == 10 and left.epic == 40, "pity left")
		local some = BlockDrop.pityLeft({ SinceRare = 4, SinceEpic = 4, Total = 4 })
		H.expect(some.rare == 6 and some.epic == 36, "counted down")
		local broken = BlockDrop.readPity({ SinceRare = -2, SinceEpic = 0 / 0, Total = "x" })
		H.expect(broken.SinceRare == 0 and broken.SinceEpic == 0 and broken.Total == 0, "broken")
		H.expect(BlockDrop.readPity(nil).Total == 0, "missing")
	end,

	["drop: the daily win track gives its 10 steps (4 blocks, 6 money), then money and XP only"] = function()
		local BlockDrop, Config = load()
		local plan = "Uncommon Money Money Mystery Money Money Mystery Money Money Epic"
		H.expect(table.concat(Config.BlockOdds.Drop.WinTrack, " ") == plan, "the plan's track")
		H.expect(BlockDrop.trackSteps() == 10, "10 steps")
		H.expect(BlockDrop.trackMoney() == 1000 and BlockDrop.Money == "Money", "$1,000 steps")
		local got = {}
		for given = 0, 9 do
			local drops, kind = BlockDrop.dropFor(ctx({ trackToday = given }))
			H.expect(drops, "step " .. given + 1)
			table.insert(got, kind)
		end
		H.expect(table.concat(got, " ") == plan, table.concat(got, " "))
		H.expect(not (BlockDrop.dropFor(ctx({ trackToday = 10 }))), "win 11: nothing")
		H.expect(not (BlockDrop.dropFor(ctx({ trackToday = 99 }))), "and later")
		H.expect(BlockDrop.trackKind(11) == nil, "past the track")
		for _, overrides in { { loserRealMatches = 5 }, { dropsFromOpponentToday = 2 } } do
			local drops, kind = BlockDrop.dropFor(ctx(overrides))
			H.expect(drops and kind == "Uncommon", "the first step")
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

	["drop: Play against PC moves the track only for the first 10 PC wins of a day"] = function()
		local BlockDrop, Config = load()
		local cap = Config.Economy.PcDropsPerDay
		H.expect(cap == 10, "the plan's 10")
		H.expect(BlockDrop.dropFor(ctx({ pcLimited = true, pcDropsToday = cap - 1 })), "the 10th")
		H.expect(not (BlockDrop.dropFor(ctx({ pcLimited = true, pcDropsToday = cap }))), "the 11th")
		H.expect(BlockDrop.dropFor(ctx({ pcLimited = false, pcDropsToday = 99 })), "people: no cap")
	end,

	["climb path: four presses from any start, the name is the floor, ending on the roll"] = function()
		local BlockDrop, Config = load()
		local ladder = Config.BlockOdds.Climb.Tiers
		local clicks = Config.BlockOdds.Drop.Upgrade.Clicks
		local rng = seeded(4242)
		for s = 1, #ladder - 1 do
			local from = ladder[s]
			for f = s, #ladder do
				local final = ladder[f]
				local start = BlockDrop.startOf(final, from)
				H.expect(
					BlockDrop.rank(start) == math.max(s, f - (clicks - 1)),
					("%s to %s starts at %s"):format(from, final, start)
				)
				for _ = 1, 60 do
					local path = BlockDrop.path(final, rng, from)
					H.expect(#path == clicks, "four tiers")
					H.expect(path[1] == start, "the first press shows the start")
					H.expect(path[#path] == final, "ends on the roll")
					for i = 2, #path do
						local step = BlockDrop.rank(path[i]) - BlockDrop.rank(path[i - 1])
						H.expect(step == 0 or step == 1, "stays or goes up one")
					end
				end
			end
		end
		H.expect(BlockDrop.startOf("Epic") == "Standard", "a Mystery's Epic starts at Standard")
		H.expect(
			table.concat(BlockDrop.path("Secret", rng, "Rare"), ",")
				== "Epic,Legendary,Mythic,Secret",
			"a Rare block's Secret starts at Epic"
		)
		H.expect(
			table.concat(BlockDrop.path("Secret", rng), ",") == "Epic,Legendary,Mythic,Secret",
			"a Mystery's Secret starts at Epic"
		)
		H.expect(
			table.concat(BlockDrop.path("Mythic", rng), ",") == "Rare,Epic,Legendary,Mythic",
			"a Mystery's Mythic starts at Rare and climbs on every later press"
		)
		H.expect(
			table.concat(BlockDrop.path("Rare", rng, "Rare"), ",") == "Rare,Rare,Rare,Rare",
			"a Rare block that stays never moves"
		)
		H.expect(not pcall(BlockDrop.startOf, "Uncommon", "Rare"), "never below the start")
	end,

	["climb path: every choice of climbing presses is equally likely"] = function()
		local BlockDrop = load()
		local rng = seeded(99)
		-- A Rare from a Mystery climbs on 2 of the 3 later presses: 3 ways, each about 1 in 3.
		local seen: { [string]: number } = {}
		local n = 30000
		for _ = 1, n do
			local key = table.concat(BlockDrop.path("Rare", rng), ",")
			seen[key] = (seen[key] or 0) + 1
		end
		local ways = 0
		for _, count in seen do
			ways += 1
			local tolerance = 4 * math.sqrt(n * (1 / 3) * (2 / 3))
			H.expect(math.abs(count - n / 3) <= tolerance, ("%d, expected %d"):format(count, n / 3))
		end
		H.expect(ways == 3, "3 ways: " .. ways)
	end,

	["every block's cues: each one's chance, equal within a rarity, adding to 100"] = function()
		local BlockDrop = load()
		local cases: { { floor: string?, opts: any } } = {
			{ floor = nil, opts = nil },
			{ floor = "Rare", opts = nil },
			{ floor = "Epic", opts = { luck = true } },
			{ floor = nil, opts = { start = "Uncommon" } },
			{ floor = nil, opts = { start = "Rare", luck = true } },
			{ floor = nil, opts = { start = "Mythic" } },
		}
		for n, case in cases do
			local label = tostring(n)
			local chances = BlockDrop.cueChances(case.floor, case.opts)
			local rarities: { [string]: number } = {}
			for _, entry in BlockDrop.rarityOdds(case.floor, case.opts) do
				rarities[entry.rarity] = entry.percent
			end
			local total, seen = 0, {}
			for _, group in BlockDrop.cueGroups(case.floor, case.opts) do
				total += group.percent
				local want = rarities[group.rarity] or -1
				H.expect(
					math.abs(group.percent - want) <= want * 1e-9,
					("%s %s: %s, rarityOdds %s"):format(label, group.rarity, group.percent, want)
				)
				for _, cue in group.cues do
					H.expect(not seen[cue], label .. ": " .. cue .. " twice")
					seen[cue] = true
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
		-- The Secret's pool is the Eclipse Cue.
		local pool = BlockDrop.pool("Secret")
		H.expect(#pool == 1 and pool[1].Id == "EclipseCue", "the Secret")
		H.expect(#BlockDrop.pool("Nope") == 0, "unknown")
	end,

	["pity's live floor: the guaranteed tier and the odds the screen shows then"] = function()
		local BlockDrop, Config = load()
		local D = Config.BlockOdds.Drop
		H.expect(BlockDrop.floorOf({ rare = 1, epic = 30 }) == "Rare", "Rare due")
		H.expect(BlockDrop.floorOf({ rare = 1, epic = 1 }) == "Epic", "both due: Epic")
		H.expect(BlockDrop.floorOf({ rare = 4, epic = 1 }) == "Epic", "Epic due")
		H.expect(BlockDrop.floorOf({ rare = 4, epic = 40 }) == nil, "none due")
		H.expect(BlockDrop.floorOf(nil) == nil and BlockDrop.floorOf("x") == nil, "broken: none")
		local function left(sinceRare: number, sinceEpic: number)
			return BlockDrop.pityLeft({ SinceRare = sinceRare, SinceEpic = sinceEpic, Total = 0 })
		end
		H.expect(BlockDrop.floorOf(left(D.PityRare - 1, 0)) == "Rare", "the 10th is Rare")
		H.expect(BlockDrop.floorOf(left(D.PityRare - 2, 0)) == nil, "the 9th is not")
		H.expect(BlockDrop.floorOf(left(0, D.PityEpic - 1)) == "Epic", "the 40th is Epic")
		local function percents(floor: string?, luck: boolean?): { [string]: number }
			local out, total = {}, 0
			for _, tier in BlockDrop.tiers(floor, { luck = luck }) do
				out[tier.tier] = tier.percent
				total += tier.percent
			end
			H.near(total, 100, 1e-9, "adds to 100")
			return out
		end
		local epic = percents("Epic")
		H.expect(epic.Standard == nil and epic.Uncommon == nil and epic.Rare == nil, "under Epic")
		H.near(epic.Epic, 99.685, 1e-9, "Epic takes the tiers under it")
		H.near(epic.Legendary, 0.26775, 1e-12, "Legendary as before")
		H.near(epic.Secret, 0.00118125, 1e-12, "the Secret as before")
		local rare = percents("Rare")
		H.near(rare.Rare, 96.85, 1e-9, "Rare takes Standard and Uncommon")
		H.near(rare.Epic, 2.835, 1e-12, "Epic as before")
		local lucky = percents("Epic", true)
		H.near(lucky.Legendary, 0.6024375, 1e-12, "the luck under the floor")
		-- The rarities under a floor never give a Common.
		for _, row in BlockDrop.rarityOdds("Epic") do
			H.expect(row.rarity ~= "Common" and row.rarity ~= "Uncommon", "no " .. row.rarity)
		end
	end,

	["climb path: the first press's odds"] = function()
		local BlockDrop = load()
		local first = BlockDrop.firstOdds()
		local sum = 0
		for _, chance in first do
			sum += chance
		end
		H.expect(math.abs(sum - 1) < 1e-9, "the first press's odds add to 1")
		local c = BlockDrop.chances()
		H.near(first.Uncommon, c.Legendary, 1e-15, "Uncommon: the Legendaries")
		H.near(first.Rare, c.Mythic, 1e-15, "Rare: the Mythics")
		H.near(first.Epic, c.Secret, 1e-15, "Epic: the Secret")
		H.expect(first.Legendary == 0 and first.Secret == 0, "nothing starts above Epic")
		local rare = BlockDrop.firstOdds("Rare")
		H.near(rare.Rare, 1 - BlockDrop.chances(nil, { start = "Rare" }).Secret, 1e-12, "Rare")
		H.expect(rare.Standard == 0 and rare.Uncommon == 0, "never under the name")
	end,

	["the Grand Opening Luck runs from the Grand Opening's StartsAt for its own 30 days"] = function()
		local BlockDrop, Config = load()
		H.expect(Config.Shop.Deals.GrandOpening.StartsAt == 0, "off until the designer sets it")
		H.expect(not BlockDrop.luckLive(1800000000), "off: never live")
		local a, b = BlockDrop.luckWindow()
		H.expect(a == 0 and b == 0, "no window")
		local T = 1800000000
		withStart(Config, T, function()
			local s, e = BlockDrop.luckWindow()
			H.expect(s == T and e == T + 30 * 86400, "30 days")
			H.expect(not BlockDrop.luckLive(T - 1), "before")
			H.expect(BlockDrop.luckLive(T) and BlockDrop.luckLive(e - 1), "inside")
			H.expect(not BlockDrop.luckLive(e), "after")
			-- Its own clock: the Grand Opening's length never changes it.
			local deal = Config.Shop.Deals.GrandOpening
			local seconds = deal.Seconds
			deal.Seconds = 45 * 86400
			local _, e2 = BlockDrop.luckWindow()
			deal.Seconds = seconds
			H.expect(e2 == e, "the luck keeps its 30 days")
		end)
		H.expect(not BlockDrop.luckLive("x") and not BlockDrop.luckLive(0 / 0), "bad now")
	end,

	["the 1 in N: an exact cue's chance from the block it started as, to 3 figures"] = function()
		local BlockDrop = load()
		-- From a Mystery block (plan 3.9): a Legendary cue 1 in 2,610 (7 of them), a Mythic cue
		-- 1 in 6,510 (3), the Eclipse Cue 1 in 84,700.
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("PhoenixCue")) == 2610, "a Legendary")
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("KitsuneCue")) == 6510, "a Mythic")
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("EclipseCue")) == 84700, "the Eclipse")
		local fromLegendary = BlockDrop.cuePercent("PhoenixCue", { start = "Legendary" })
		H.near(BlockDrop.oneIn(fromLegendary) :: number, 8.24, 1e-9, "from a Legendary block")
		H.expect(
			BlockDrop.oneIn(BlockDrop.cuePercent("EclipseCue", { luck = true })) == 37600,
			"luck"
		)
		H.expect(BlockDrop.oneIn(0) == nil and BlockDrop.oneIn(0 / 0) == nil, "no chance")
		H.expect(BlockDrop.cuePercent("Classic") == 0, "a cue no climb gives")
	end,
	["climbFor: no plan rolls like climbRoll, with the luck noted"] = function()
		local BlockDrop = load()
		local tier, after, luck, ready = BlockDrop.climbFor("Uncommon", never, {})
		H.expect(tier == "Uncommon" and after == nil, "never climbs: stays at its start")
		H.expect(luck == false and ready == false, "no luck, on its timer")
		tier, after, luck, ready = BlockDrop.climbFor("Rare", always, { luck = true })
		H.expect(tier == "Secret" and after == nil, "always climbs: the top")
		H.expect(luck == true and ready == false, "the luck counted")
		local rng = seeded(7)
		local same = seeded(7)
		for _ = 1, 200 do
			local a = BlockDrop.climbFor("Standard", rng, { luck = true })
			H.expect(a == BlockDrop.climbRoll("Standard", same, true), "the same roll")
		end
		H.expect(not pcall(BlockDrop.climbFor, "Nope", never, {}), "an unknown start")
	end,
	["climbFor: a Mystery block's roll counts pity and pity sets it"] = function()
		local BlockDrop = load()
		local tier, after, luck, ready = BlockDrop.climbFor(
			"Standard",
			never,
			{ pity = { SinceRare = 9, SinceEpic = 5, Total = 4 } }
		)
		H.expect(tier == "Rare" and ready == false and luck == false, "the 10th: Rare by pity")
		H.expect(after ~= nil and after.SinceRare == 0 and after.SinceEpic == 6, "counted")
		H.expect((after :: any).Total == 5, "every Mystery block counts")
	end,
	["climbFor: stay keeps the block at its start, ready at once, nothing counted"] = function()
		local BlockDrop = load()
		local tier, after, luck, ready = BlockDrop.climbFor(
			"Uncommon",
			always,
			{ stay = true, luck = true, pity = fresh(), forced = "Epic" }
		)
		H.expect(tier == "Uncommon" and after == nil, "no climb, no pity counted (stay wins)")
		H.expect(luck == false and ready == true, "ready at once, no luck")
	end,
	["climbFor: a scripted tier ends the climb there, ready at once"] = function()
		local BlockDrop = load()
		local calls = 0
		local counted = function(n: number): number
			calls += 1
			return n
		end
		-- The tutorial's first block: a Mystery block (pity, the head start) scripted to Uncommon.
		local start = BlockDrop.freshPity()
		local tier, after, luck, ready = BlockDrop.climbFor(
			"Standard",
			counted,
			{ pity = start, luck = true, forced = "Uncommon" }
		)
		H.expect(tier == "Uncommon" and ready == true and luck == false, "Uncommon, ready, no luck")
		H.expect(calls == 0, "nothing rolled")
		H.expect(after ~= nil, "a Mystery block still counts pity")
		local a = after :: any
		H.expect(
			a.SinceRare == start.SinceRare + 1 and a.SinceEpic == start.SinceEpic + 1,
			"counted"
		)
		H.expect(a.Total == 1, "the open counted")
		-- Its presses climb Standard to Uncommon.
		local path = BlockDrop.path(tier, seeded(3), "Standard")
		H.expect(path[1] == "Standard" and path[#path] == "Uncommon", "the screen's presses")
		-- A forced Rare or better resets its pity counters like a rolled one.
		local _, reset = BlockDrop.climbFor("Standard", never, { pity = start, forced = "Epic" })
		H.expect(
			reset ~= nil and (reset :: any).SinceRare == 0 and (reset :: any).SinceEpic == 0,
			"reset"
		)
		-- A kind without pity: the tier alone.
		tier, after, luck, ready =
			BlockDrop.climbFor("Rare", always, { forced = "Epic", luck = true })
		H.expect(
			tier == "Epic" and after == nil and luck == false and ready == true,
			"no pity kind"
		)
		-- The Secret can be scripted too (it gives its cue at once, no block).
		tier = BlockDrop.climbFor("Mythic", never, { forced = "Secret" })
		H.expect(tier == "Secret", "the Secret")
	end,
	["climbFor: a scripted tier below the start or off the ladder is ignored"] = function()
		local BlockDrop = load()
		local tier, _, _, ready = BlockDrop.climbFor("Rare", never, { forced = "Uncommon" })
		H.expect(tier == "Rare" and ready == false, "below the start: a normal roll")
		tier, _, _, ready = BlockDrop.climbFor("Standard", never, { forced = "Nope" })
		H.expect(tier == "Standard" and ready == false, "not a tier: a normal roll")
		local _, after, _, ready2 =
			BlockDrop.climbFor("Standard", never, { pity = fresh(), forced = "Gold" })
		H.expect(ready2 == false and after ~= nil and (after :: any).Total == 1, "pity as a roll")
	end,
}
