--!strict
-- BlockDrop (Progression/BlockDrop): the climb (economy v6's numbers, 2026-10-10): one
-- ladder for every block, the Grand Opening Luck, the Mystery's roll into a block (v5.1) and its
-- pity with the head start, every block's odds lists, the climb screen's path from any start, the "1 in N", and the daily
-- win track with its money steps (section 4), and whether a win moves it at all (the anti-farm
-- rules, ECONOMY 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.BlockDrop"), H.require("Config")
end

-- Economy v6's ladder (2026-10-10) in parts of a million. The Grand Opening Luck is off: its
-- two steps are the plain ones (and its window is 0 seconds long).
local STEPS = {
	Standard = 400000,
	Uncommon = 300000,
	Rare = 100000,
	Epic = 150000,
	Legendary = 100000,
	Mythic = 25000,
}
local LUCK = { Rare = 100000, Epic = 150000 }

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }

-- The plan's tables 3.3 and 3.4: each block's rarities in percent, as the plan prints them (to
-- 7 decimals at most, so within half a last digit; they are exact products of the steps).
local PLAN = {
	Standard = { 60, 28, 10.8, 1.02, 0.162, 0.01755, 0.00045 },
	Uncommon = { 0, 70, 27, 2.55, 0.405, 0.043875, 0.001125 },
	Rare = { 0, 0, 90, 8.5, 1.35, 0.14625, 0.00375 },
	Epic = { 0, 0, 0, 85, 13.5, 1.4625, 0.0375 },
	Legendary = { 0, 0, 0, 0, 90, 9.75, 0.25 },
	Mythic = { 0, 0, 0, 0, 0, 97.5, 2.5 },
}
-- With the luck off its table is the plain one.
local PLAN_LUCK = PLAN
-- The "or better" table as 1 in N, rounded as the plan prints them: Epic+, Legendary+,
-- Mythic+, the Secret.
local ONE_IN = {
	Standard = { 83, 556, 5556, 222222 },
	Uncommon = { 33, 222, 2222, 88889 },
	Rare = { 10, 67, 667, 26667 },
	Epic = { 1, 6.7, 67, 2667 },
	Legendary = { 1, 1, 10, 400 },
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

-- One whole Mystery: its roll, then that block's climb. (the block, the cue's tier, the counters).
local function mystery(BlockDrop: any, pity: any, rng: (number) -> number): (string, string, any)
	local block, after, waits = BlockDrop.turnRoll(pity, rng)
	local final = BlockDrop.climbRoll(block, rng)
	return block, final, BlockDrop.countClimb(after, waits, final)
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
		H.expect(CL.Luck.Steps.Rare == 100000 and CL.Luck.Steps.Epic == 150000, "luck steps")
		H.expect(CL.Luck.With == "GrandOpening" and CL.Luck.Seconds == 0, "the luck is off")
		for i, tier in CL.Tiers do
			H.expect(BlockDrop.rank(tier) == i, tier .. " rank")
			H.expect(BlockDrop.rarityOf(tier) == RARITIES[i], tier .. " rarity")
		end
		H.expect(BlockDrop.rank("Nope") == 0 and BlockDrop.rank(nil) == 0, "unknown")
		H.expect(BlockDrop.isBlockTier("Mythic") and not BlockDrop.isBlockTier("Secret"), "blocks")
		local D = Config.BlockOdds.Drop
		H.expect(D.PityRare == 10 and D.PityEpic == 50 and D.FirstWin == nil, "pity, no first win")
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
		H.near(mystery[1].percent, 60, 1e-12, "Mystery Common")
		H.near(mystery[7].percent, 0.00045, 1e-15, "Mystery Secret")
	end,

	["the Grand Opening Luck is off: its odds are the plain ones"] = function()
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
		-- A Standard start with the luck flag: the plain odds (Epic+ 1.2%, Legendary+ 0.18%).
		local c = BlockDrop.chances(nil, { luck = true })
		local epicUp = c.Epic + c.Legendary + c.Mythic + c.Secret
		local legUp = c.Legendary + c.Mythic + c.Secret
		H.near(epicUp * 100, 1.2, 1e-12, "Epic+")
		H.near(legUp * 100, 0.18, 1e-12, "Legendary+")
		H.expect(printed(c.Secret * 100) == 222222, "1 in 222,222")
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
		H.near((c.Epic + c.Legendary + c.Mythic + c.Secret) * 100, 1.2, 1e-12, "Standard Epic+")
		H.near((c.Legendary + c.Mythic + c.Secret) * 100, 0.18, 1e-12, "Standard Legendary+")
		H.near((c.Mythic + c.Secret) * 100, 0.018, 1e-12, "Standard Mythic+")
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
		-- The luck changes nothing (economy v6): one over Rare's 10% stays with it too.
		local final = BlockDrop.climbRoll("Rare", function(_n: number): number
			return 100001
		end, true)
		H.expect(final == "Rare", "100,001 misses Rare's 10% under the luck")
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

	["pity: the 10th Mystery without a Rare turns into a Rare block"] = function()
		local BlockDrop = load()
		local pity = fresh()
		for i = 1, 9 do
			local block, final
			block, final, pity = mystery(BlockDrop, pity, never)
			H.expect(block == "Standard" and final == "Standard", "Mystery " .. i)
		end
		H.expect(pity.SinceRare == 9 and pity.SinceEpic == 9 and pity.Total == 9, "counted")
		H.expect(BlockDrop.pityLeft(pity).rare == 1, "the next one is guaranteed")
		local block, after, waits = BlockDrop.turnRoll(pity, never)
		H.expect(block == "Rare" and waits == "Epic", "the 10th: " .. block)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 9, "the Rare count resets at the roll")
		after = BlockDrop.countClimb(after, waits, BlockDrop.climbRoll(block, never))
		H.expect(after.SinceRare == 0 and after.SinceEpic == 10, "the Epic one counts at the climb")
		H.expect(BlockDrop.pityLeft(after).rare == 10, "10 to go again")
	end,

	["pity: the 50th without an Epic turns into an Epic block, never more or less"] = function()
		local BlockDrop = load()
		local pity = { SinceRare = 0, SinceEpic = 48, Total = 48 }
		local block, final
		block, final, pity = mystery(BlockDrop, pity, never)
		H.expect(block == "Standard" and final == "Standard", "the 49th rolls as usual")
		H.expect(pity.SinceEpic == 49 and pity.SinceRare == 1, "counted at its climb")
		local after, waits
		block, after, waits = BlockDrop.turnRoll(pity, never)
		H.expect(block == "Epic" and waits == nil, "the 50th: " .. block)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 0, "an Epic block resets both")
		-- Both due at once: Epic wins.
		block = BlockDrop.turnRoll({ SinceRare = 9, SinceEpic = 49, Total = 200 }, never)
		H.expect(block == "Epic", "Epic over Rare")
		-- A higher roll is never lowered by pity.
		block = BlockDrop.turnRoll({ SinceRare = 9, SinceEpic = 49, Total = 200 }, always)
		H.expect(block == "Legendary", "the top roll stays")
		-- A natural Rare block before the limit resets the Rare count; the Epic one waits.
		local draws, i = { 1, 1, 1000000 }, 0
		local natural
		natural, after, waits = BlockDrop.turnRoll(
			{ SinceRare = 5, SinceEpic = 5, Total = 5 },
			function(n)
				i += 1
				return draws[i] or n
			end
		)
		H.expect(natural == "Rare" and waits == "Epic", "a natural Rare: " .. natural)
		H.expect(after.SinceRare == 0 and after.SinceEpic == 5, "its counts")
		-- The live floor's cue list matches what a due Mystery does, seeded.
		local rng = seeded(31)
		local n = 200000
		local counts: { [string]: number } = {}
		for _ = 1, n do
			local _, t = mystery(BlockDrop, { SinceRare = 0, SinceEpic = 49, Total = 0 }, rng)
			counts[t] = (counts[t] or 0) + 1
		end
		for t, p in BlockDrop.chances("Epic", { mystery = true }) do
			H.expect(
				math.abs((counts[t] or 0) - n * p) <= 4 * math.sqrt(n * p * (1 - p)) + 1,
				t .. " under the Epic floor"
			)
		end
	end,

	["pity: Mysteries rolled while pity is due are lifted once; held blocks count later"] = function()
		local BlockDrop = load()
		-- The 10th lifts to Rare and resets at once, so a second roll before its climb is not.
		local due = { SinceRare = 9, SinceEpic = 5, Total = 9 }
		local first, after = BlockDrop.turnRoll(due, never)
		local second = BlockDrop.turnRoll(after, never)
		H.expect(first == "Rare" and second == "Standard", "one lift, not two")
		-- Standard blocks held unopened count when they climb, so pity is late, never lost.
		local pity = { SinceRare = 8, SinceEpic = 8, Total = 8 }
		local a, afterA, waitsA = BlockDrop.turnRoll(pity, never)
		local b, afterB, waitsB = BlockDrop.turnRoll(afterA, never)
		H.expect(a == "Standard" and b == "Standard", "neither is due yet")
		H.expect(afterB.SinceRare == 8 and afterB.Total == 10, "the counts wait")
		pity = BlockDrop.countClimb(afterB, waitsA, "Uncommon")
		pity = BlockDrop.countClimb(pity, waitsB, "Standard")
		H.expect(pity.SinceRare == 10 and pity.SinceEpic == 10, "both counted at their climbs")
		H.expect(BlockDrop.turnRoll(pity, never) == "Rare", "the next is lifted")
		-- A climb's cue resets what it carried; nothing else changes.
		local reset = BlockDrop.countClimb(pity, "Rare", "Epic")
		H.expect(reset.SinceRare == 0 and reset.SinceEpic == 0, "an Epic cue resets both")
		local rare = BlockDrop.countClimb(pity, "Rare", "Rare")
		H.expect(rare.SinceRare == 0 and rare.SinceEpic == 11, "a Rare cue resets the Rare one")
		local epicOnly = BlockDrop.countClimb(pity, "Epic", "Rare")
		H.expect(epicOnly.SinceRare == 10 and epicOnly.SinceEpic == 11, "only the Epic one")
		local none = BlockDrop.countClimb(pity, nil, "Standard")
		H.expect(none.SinceRare == 10 and none.SinceEpic == 10, "nothing carried")
		H.expect(none.Total == pity.Total, "the total counts at the roll only")
	end,

	["pity's head start: none since economy v6, a new save begins at 0 / 10 and 0 / 50"] = function()
		local BlockDrop, Config = load()
		local start = BlockDrop.freshPity()
		H.expect(start.SinceRare == 0 and start.SinceEpic == 0 and start.Total == 0, "the counts")
		local left = BlockDrop.pityLeft(start)
		H.expect(left.rare == 10 and left.epic == 50, "10 and 50 to go")
		-- The first Epic block is guaranteed by the 50th Mystery.
		local pity, block = start, ""
		for i = 1, 50 do
			block, _, pity = mystery(BlockDrop, pity, never)
			if i < 50 then
				H.expect(
					block == "Standard" or block == "Rare",
					("Mystery %d: %s"):format(i, block)
				)
			end
		end
		H.expect(block == "Epic", "the 50th: " .. block)
		H.expect(Config.BlockOdds.Drop.PityStart.SinceRare == 0, "Config")
	end,

	["a forced turn skips the roll and still counts"] = function()
		local BlockDrop = load()
		local tier, pity, waits = BlockDrop.turnRoll(fresh(), function(_n: number): number
			error("no roll for a forced turn")
		end, "Rare")
		H.expect(tier == "Rare" and waits == "Epic", "forced")
		H.expect(pity.SinceRare == 0 and pity.SinceEpic == 0 and pity.Total == 1, "counted")
		H.expect(not pcall(BlockDrop.turnRoll, fresh(), never, "Nope"), "an unknown tier")
		H.expect(not pcall(BlockDrop.turnRoll, fresh(), never, "Mythic"), "above the top")
	end,

	["the Mystery's roll: 30 / 20 / 10 / 5, up to a Legendary block"] = function()
		local BlockDrop, Config = load()
		local T = Config.BlockOdds.Turn
		H.expect(T.Top == "Legendary", "the top")
		H.expect(T.Steps.Standard == 300000 and T.Steps.Uncommon == 200000, "the first two")
		H.expect(T.Steps.Rare == 100000 and T.Steps.Epic == 50000, "the last two")
		H.expect(
			BlockDrop.turnParts("Legendary") == 0 and BlockDrop.turnParts("Mythic") == 0,
			"top"
		)
		local want = {
			Standard = 0.7,
			Uncommon = 0.24,
			Rare = 0.054,
			Epic = 0.0057,
			Legendary = 0.0003,
		}
		local turn = BlockDrop.turnChances()
		local total = 0
		for tier, p in turn do
			H.near(p, want[tier] or -1, 1e-12, tier)
			total += p
		end
		H.near(total, 1, 1e-12, "adds to 1")
		H.expect(turn.Mythic == nil and turn.Secret == nil, "never a Mythic block")
		-- Under a floor the tiers below it move into it.
		local floored = BlockDrop.turnChances("Rare")
		H.near(floored.Rare, 0.994, 1e-12, "Rare takes Standard and Uncommon")
		H.expect(floored.Standard == nil and floored.Uncommon == nil, "gone")
		H.near(floored.Epic, 0.0057, 1e-15, "Epic as before")
		local rows = BlockDrop.turnTiers()
		H.expect(#rows == 5 and rows[1].tier == "Standard" and rows[5].tier == "Legendary", "rows")
		-- A seeded roll lands on those odds.
		local rng = seeded(19)
		local n = 200000
		local counts: { [string]: number } = {}
		for _ = 1, n do
			local t = BlockDrop.turnClimb(rng)
			counts[t] = (counts[t] or 0) + 1
		end
		for t, p in turn do
			H.expect(
				math.abs((counts[t] or 0) - n * p) <= 4 * math.sqrt(n * p * (1 - p)) + 1,
				t .. " rolled"
			)
		end
		H.expect(BlockDrop.isTurnTier("Legendary") and not BlockDrop.isTurnTier("Mythic"), "turns")
		H.expect(not BlockDrop.isTurnTier("Nope") and not BlockDrop.isTurnTier(nil), "broken")
	end,

	["a Mystery's cue odds: its roll, then that block's climb (the plan's 1 in N)"] = function()
		local BlockDrop = load()
		local m = BlockDrop.chances(nil, { mystery = true })
		local turn = BlockDrop.turnChances()
		for _, tier in BlockDrop.ladder() do
			local want = 0
			for from, p in turn do
				want += p * (BlockDrop.chances(nil, { start = from })[tier] or 0)
			end
			H.near(m[tier] or 0, want, 1e-15, tier .. ": the sum over the roll")
		end
		H.near(m.Standard, 0.42, 1e-12, "a Common: 70% Standard blocks, 60% of them stay")
		local function orBetter(from: string): number
			local sum = 0
			for tier, p in m do
				if BlockDrop.rank(tier) >= BlockDrop.rank(from) then
					sum += p
				end
			end
			return sum
		end
		-- Economy v6's plan page (2026-10-10): 1 in 37, 232, 2,323 and 92,915.
		H.expect(printed(orBetter("Epic") * 100) == 37, "Epic or better")
		H.expect(printed(orBetter("Legendary") * 100) == 232, "Legendary or better")
		H.expect(printed(orBetter("Mythic") * 100) == 2323, "Mythic or better")
		H.expect(printed(m.Secret * 100) == 92915, "the Secret")
		-- Every block a Mystery can turn into can still reach the Secret.
		for tier in turn do
			H.expect(BlockDrop.chances(nil, { start = tier }).Secret > 0, tier .. " reaches it")
		end
		-- The luck is off (economy v6): the same odds.
		local lucky = BlockDrop.chances(nil, { mystery = true, luck = true })
		H.near(lucky.Legendary, m.Legendary, 1e-15, "the luck changes nothing")
		H.near(lucky.Standard, m.Standard, 1e-15, "the roll is the same")
		-- A Mystery is never worse than a Standard block.
		H.expect(orBetter("Rare") > BlockDrop.chances().Rare, "better than Standard")
	end,

	["pity left and a broken pity table"] = function()
		local BlockDrop = load()
		local left = BlockDrop.pityLeft({ SinceRare = 0, SinceEpic = 0, Total = 3 })
		H.expect(left.rare == 10 and left.epic == 50, "pity left")
		local some = BlockDrop.pityLeft({ SinceRare = 4, SinceEpic = 4, Total = 4 })
		H.expect(some.rare == 6 and some.epic == 46, "counted down")
		local broken = BlockDrop.readPity({ SinceRare = -2, SinceEpic = 0 / 0, Total = "x" })
		H.expect(broken.SinceRare == 0 and broken.SinceEpic == 0 and broken.Total == 0, "broken")
		H.expect(BlockDrop.readPity(nil).Total == 0, "missing")
	end,

	["drop: the daily win track gives its 10 steps (3 blocks, 7 money), then money and XP only"] = function()
		local BlockDrop, Config = load()
		local plan = "Mystery Money Money Money Mystery Money Money Money Money Rare"
		H.expect(table.concat(Config.BlockOdds.Drop.WinTrack, " ") == plan, "the plan's track")
		H.expect(BlockDrop.trackSteps() == 10, "10 steps")
		H.expect(BlockDrop.trackMoney() == 250 and BlockDrop.Money == "Money", "$250 steps")
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
			H.expect(drops and kind == "Mystery", "the first step")
		end
	end,

	["drop: the first win ever is the track's step (no first-win block since v6), same anti-farm rules"] = function()
		local BlockDrop, Config = load()
		H.expect(Config.BlockOdds.Drop.FirstWin == nil, "no first-win block")
		local drops, kind = BlockDrop.dropFor(ctx({ firstWinEver = true }))
		H.expect(drops and kind == "Mystery", "win 1's Mystery")
		local _, later = BlockDrop.dropFor(ctx({ firstWinEver = true, trackToday = 1 }))
		H.expect(later == "Money", "the track's own step later")
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

	["drop: Play against PC never moves the track (economy v6: practice)"] = function()
		local BlockDrop, Config = load()
		local cap = Config.Economy.PcDropsPerDay
		H.expect(cap == 0, "none")
		H.expect(not (BlockDrop.dropFor(ctx({ pcLimited = true, pcDropsToday = 0 }))), "the 1st")
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
		H.near(epic.Epic, 99.82, 1e-9, "Epic takes the tiers under it")
		H.near(epic.Legendary, 0.162, 1e-12, "Legendary as before")
		H.near(epic.Secret, 0.00045, 1e-12, "the Secret as before")
		local rare = percents("Rare")
		H.near(rare.Rare, 98.8, 1e-9, "Rare takes Standard and Uncommon")
		H.near(rare.Epic, 1.02, 1e-12, "Epic as before")
		local lucky = percents("Epic", true)
		H.near(lucky.Legendary, 0.162, 1e-12, "the luck is off under the floor too")
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

	["the Grand Opening Luck is off: no window is ever live (economy v6)"] = function()
		local BlockDrop, Config = load()
		H.expect(Config.Shop.Deals.GrandOpening.StartsAt > 0, "started 2026-10-10")
		H.expect(not BlockDrop.luckLive(1800000000), "off: never live")
		local a, b = BlockDrop.luckWindow()
		H.expect(a == b, "a window 0 seconds long")
		local T = 1800000000
		withStart(Config, T, function()
			local s, e = BlockDrop.luckWindow()
			H.expect(s == T and e == T, "0 seconds long")
			H.expect(not BlockDrop.luckLive(T - 1), "before")
			H.expect(not BlockDrop.luckLive(T) and not BlockDrop.luckLive(T + 86400), "never")
		end)
		H.expect(not BlockDrop.luckLive("x") and not BlockDrop.luckLive(0 / 0), "bad now")
	end,

	["the 1 in N: an exact cue's chance from the block it started as, to 3 figures"] = function()
		local BlockDrop = load()
		-- From a Standard block (economy v6): a Legendary cue 1 in 3,700 (6 drop: Chroma is a
		-- reward cue), a Mythic cue 1 in 17,100 (3), the Eclipse Cue 1 in 222,000.
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("PhoenixCue")) == 3700, "a Legendary")
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("KitsuneCue")) == 17100, "a Mythic")
		H.expect(BlockDrop.oneIn(BlockDrop.cuePercent("EclipseCue")) == 222000, "the Eclipse")
		local fromLegendary = BlockDrop.cuePercent("PhoenixCue", { start = "Legendary" })
		H.near(BlockDrop.oneIn(fromLegendary) :: number, 6.67, 1e-9, "from a Legendary block")
		H.expect(
			BlockDrop.oneIn(BlockDrop.cuePercent("EclipseCue", { luck = true })) == 222000,
			"the luck is off"
		)
		H.expect(BlockDrop.cuePercent("ChromaCue") == 0, "Chroma drops from no block")
		H.expect(BlockDrop.cuePercent("CandyCue") == 0, "nor Candy Cane")
		H.expect(BlockDrop.oneIn(0) == nil and BlockDrop.oneIn(0 / 0) == nil, "no chance")
		H.expect(BlockDrop.cuePercent("Classic") == 0, "a cue no climb gives")
	end,
	["climbFor: no plan rolls like climbRoll, with the luck noted"] = function()
		local BlockDrop = load()
		local tier, luck, ready = BlockDrop.climbFor("Uncommon", never, {})
		H.expect(tier == "Uncommon", "never climbs: stays at its start")
		H.expect(luck == false and ready == false, "no luck, on its timer")
		tier, luck, ready = BlockDrop.climbFor("Rare", always, { luck = true })
		H.expect(tier == "Secret", "always climbs: the top")
		H.expect(luck == true and ready == false, "the luck counted")
		local rng = seeded(7)
		local same = seeded(7)
		for _ = 1, 200 do
			local a = BlockDrop.climbFor("Standard", rng, { luck = true })
			H.expect(a == BlockDrop.climbRoll("Standard", same, true), "the same roll")
		end
		H.expect(not pcall(BlockDrop.climbFor, "Nope", never, {}), "an unknown start")
	end,
	["climbFor: stay keeps the block at its start, ready at once"] = function()
		local BlockDrop = load()
		local tier, luck, ready =
			BlockDrop.climbFor("Uncommon", always, { stay = true, luck = true, forced = "Epic" })
		H.expect(tier == "Uncommon", "no climb (stay wins)")
		H.expect(luck == false and ready == true, "ready at once, no luck")
	end,
	["climbFor: a scripted tier ends the climb there, ready at once"] = function()
		local BlockDrop = load()
		local calls = 0
		local counted = function(n: number): number
			calls += 1
			return n
		end
		local tier, luck, ready =
			BlockDrop.climbFor("Standard", counted, { luck = true, forced = "Uncommon" })
		H.expect(tier == "Uncommon" and ready == true and luck == false, "Uncommon, ready, no luck")
		H.expect(calls == 0, "nothing rolled")
		-- Its presses climb Standard to Uncommon.
		local path = BlockDrop.path(tier, seeded(3), "Standard")
		H.expect(path[1] == "Standard" and path[#path] == "Uncommon", "the screen's presses")
		tier, luck, ready = BlockDrop.climbFor("Rare", always, { forced = "Epic", luck = true })
		H.expect(tier == "Epic" and luck == false and ready == true, "from Rare")
		-- The Secret can be scripted too (it gives its cue at once, no block).
		tier = BlockDrop.climbFor("Mythic", never, { forced = "Secret" })
		H.expect(tier == "Secret", "the Secret")
	end,
	["climbFor: a scripted tier below the start or off the ladder is ignored"] = function()
		local BlockDrop = load()
		local tier, _, ready = BlockDrop.climbFor("Rare", never, { forced = "Uncommon" })
		H.expect(tier == "Rare" and ready == false, "below the start: a normal roll")
		tier, _, ready = BlockDrop.climbFor("Standard", never, { forced = "Nope" })
		H.expect(tier == "Standard" and ready == false, "not a tier: a normal roll")
	end,
	["turnFor: a Mystery's roll with pity; stay and a scripted block (the tutorial)"] = function()
		local BlockDrop = load()
		local rng, same = seeded(11), seeded(11)
		for _ = 1, 200 do
			local p = { SinceRare = 3, SinceEpic = 7, Total = 3 }
			local a, afterA, waitsA, scripted = BlockDrop.turnFor(p, rng, {})
			local b, afterB, waitsB = BlockDrop.turnRoll(p, same)
			H.expect(a == b and waitsA == waitsB and not scripted, "the same roll")
			H.expect(afterA.SinceRare == afterB.SinceRare and afterA.Total == 4, "the same counts")
		end
		-- Stay: a Standard block, nothing counted, nothing waiting.
		local start = BlockDrop.freshPity()
		local tier, after, waits, scripted =
			BlockDrop.turnFor(start, always, { stay = true, forced = "Epic" })
		H.expect(tier == "Standard" and waits == nil and scripted, "stay")
		H.expect(after.SinceRare == 0 and after.SinceEpic == 0 and after.Total == 0, "uncounted")
		-- Forced: that block, nothing rolled, the Mystery counted.
		local calls = 0
		local counted = function(n: number): number
			calls += 1
			return n
		end
		tier, after, waits, scripted = BlockDrop.turnFor(start, counted, { forced = "Uncommon" })
		H.expect(tier == "Uncommon" and waits == "Rare" and scripted, "forced Uncommon")
		H.expect(calls == 0 and after.Total == 1 and after.SinceRare == 0, "waits for its climb")
		-- A block it can't turn into: a normal roll.
		for _, bad in { "Mythic", "Secret", "Nope" } do
			tier, _, _, scripted = BlockDrop.turnFor(fresh(), never, { forced = bad })
			H.expect(tier == "Standard" and not scripted, bad)
		end
	end,
}
