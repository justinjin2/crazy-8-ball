--!strict
-- BlockOdds (Progression/BlockOdds): the odds rows the lucky blocks roll (the economy v4 plan,
-- 2026-10-08, section 4; cases retired for lucky blocks 2026-10-04), per-cue odds, seeded
-- rolls, the guarantee, vaulting, sell-back values (ECONOMY 8) and announcements.

local H = require("./harness")

local function load()
	return H.require("Progression.BlockOdds"), H.require("Progression.Catalog"), H.require("Config")
end

-- The v4 plan's section 4 table, in percent as it prints them (nil = "-").
local ODDS: { [string]: { [string]: number } } = {
	Standard = {
		Common = 72.5,
		Uncommon = 25,
		Rare = 2.4,
		Epic = 0.09,
		Legendary = 0.009,
		Mythic = 0.0009,
		Secret = 0.0001,
	},
	Uncommon = {
		Common = 40,
		Uncommon = 54,
		Rare = 5.8,
		Epic = 0.18,
		Legendary = 0.018,
		Mythic = 0.0018,
		Secret = 0.0002,
	},
	Rare = {
		Uncommon = 68,
		Rare = 31,
		Epic = 0.9,
		Legendary = 0.09,
		Mythic = 0.009,
		Secret = 0.001,
	},
	Epic = { Rare = 77.3, Epic = 21, Legendary = 1.5, Mythic = 0.18, Secret = 0.02 },
	Legendary = { Epic = 72, Legendary = 25, Mythic = 2.7, Secret = 0.3 },
	Mythic = { Legendary = 72, Mythic = 25, Secret = 3 },
	Starter = { Rare = 90, Epic = 9, Legendary = 0.9, Mythic = 0.09, Secret = 0.01 },
	Sky = {
		Common = 45,
		Uncommon = 45,
		Rare = 9.5,
		Epic = 0.45,
		Legendary = 0.045,
		Mythic = 0.0045,
		Secret = 0.0005,
	},
}
local MIN_RARITY = {
	Standard = "Common",
	Uncommon = "Common",
	Rare = "Uncommon",
	Epic = "Rare",
	Legendary = "Epic",
	Mythic = "Legendary",
	Starter = "Rare",
	Sky = "Common",
}

-- ECONOMY 8: sell-back per copy.
local SELL = {
	Common = 150,
	Uncommon = 400,
	Rare = 1500,
	Epic = 25000,
	Legendary = 250000,
	Mythic = 2500000,
	Secret = 25000000,
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

-- Four standard deviations of a binomial count, plus one so a share of a few in 200,000
-- is not held to a fraction of a roll.
local function tolerance(n: number, p: number): number
	return 4 * math.sqrt(n * p * (1 - p)) + 1
end

-- Runs `body` with a cue vaulted, restoring it whatever happens.
local function withVaulted(Catalog: any, id: string, body: () -> ())
	local cue = Catalog.get(id)
	assert(cue, id)
	local was = cue.Vaulted
	cue.Vaulted = true
	local ok, err = pcall(body)
	cue.Vaulted = was
	if not ok then
		error(err, 0)
	end
end

return {
	["every odds row adds to exactly 1,000,000 and matches the plan"] = function()
		local BlockOdds, _, Config = load()
		H.expect(Config.BlockOdds.OddsTotal == 1000000, "OddsTotal")
		local problems = BlockOdds.validate()
		H.expect(#problems == 0, "validate: " .. table.concat(problems, "; "))
		for id, row in ODDS do
			local odds = BlockOdds.get(id)
			H.expect(odds ~= nil, id .. " is not an odds row")
			assert(odds, "no row")
			H.expect(odds.Id == id and (odds :: any).Timer == nil, "a row is its id and odds")
			local sum = 0
			for _, rarity in Config.BlockOdds.Rarities do
				local expected = math.floor((row[rarity] or 0) * 10000 + 0.5)
				local got = odds.Odds[rarity] or 0
				H.expect(
					got == expected,
					("%s %s: %d, expected %d"):format(id, rarity, got, expected)
				)
				sum += got
			end
			H.expect(sum == 1000000, ("%s adds to %d"):format(id, sum))
			-- odds() lists exactly the rarities with a share, bottom first, with percents.
			local previous = 0
			local total = 0
			for _, entry in BlockOdds.odds(id) do
				H.near(
					entry.percent,
					row[entry.rarity],
					1e-9,
					id .. " " .. entry.rarity .. " percent"
				)
				local rank = table.find(Config.BlockOdds.Rarities, entry.rarity) or 0
				H.expect(rank > previous, id .. " odds out of order")
				previous = rank
				total += entry.percent
			end
			H.near(total, 100, 1e-9, id .. " percents add to 100")
			H.expect(BlockOdds.minRarity(id) == MIN_RARITY[id], id .. " guarantee")
		end
		H.expect(
			BlockOdds.odds("Nope")[1] == nil and BlockOdds.minRarity("Nope") == nil,
			"unknown row"
		)
	end,

	["six tier rows on the ladder, then the extra rows; nothing is a case any more"] = function()
		local BlockOdds, _, Config = load()
		H.expect(
			table.concat(Config.BlockOdds.Order, " ")
				== "Standard Uncommon Rare Epic Legendary Mythic",
			"the ladder"
		)
		local all = {}
		for _, row in BlockOdds.list() do
			table.insert(all, row.Id)
			H.expect(
				(row :: any).Price == nil
					and (row :: any).Enabled == nil
					and (row :: any).Timer == nil,
				row.Id .. " is odds only: a lucky block kind carries the timer"
			)
		end
		local want = table.clone(Config.BlockOdds.Order)
		for _, id in Config.BlockOdds.Extra do
			table.insert(want, id)
		end
		H.expect(
			table.concat(all, " ") == table.concat(want, " "),
			"all: " .. table.concat(all, " ")
		)
		H.expect(
			BlockOdds.get("Event") == nil
				and BlockOdds.get("Nope") == nil
				and BlockOdds.get(3) == nil,
			"unknown ids"
		)
		H.expect(BlockOdds.get(nil) == nil, "nil")
		H.expect(Config.Cases == nil, "Config.Cases is gone")
		for _, gone in { "timer", "price", "isBuyCount", "dropFor" } do
			H.expect((BlockOdds :: any)[gone] == nil, gone .. " is gone")
		end
	end,

	["per-cue odds split each rarity evenly and total 100"] = function()
		local BlockOdds, Catalog, Config = load()
		for _, case in BlockOdds.list() do
			local total = 0
			local lastRank = 0
			local listed = 0
			for _, entry in BlockOdds.cueOdds(case.Id) do
				local pool = Catalog.droppable(case.Id, entry.rarity)
				H.near(
					entry.percent,
					case.Odds[entry.rarity] * 100 / Config.BlockOdds.OddsTotal / #pool,
					1e-9,
					case.Id .. " " .. entry.id
				)
				H.expect(
					entry.display ~= "0%" and entry.display:match("^[%d%.]+%%$") ~= nil,
					entry.display
				)
				local cue = Catalog.get(entry.id)
				H.expect(cue ~= nil and cue.Rarity == entry.rarity, entry.id .. " rarity")
				-- Grouped by rarity, bottom first.
				local rank = Catalog.rarityRank(entry.rarity)
				H.expect(rank >= lastRank, case.Id .. " cue odds are not grouped by rarity")
				lastRank = rank
				listed += 1
				total += entry.percent
			end
			-- Every droppable cue is listed once.
			local droppable = 0
			for _, entry in BlockOdds.odds(case.Id) do
				droppable += #Catalog.droppable(case.Id, entry.rarity)
			end
			H.expect(
				listed == droppable,
				("%s lists %d cues, expected %d"):format(case.Id, listed, droppable)
			)
			-- An extra row's Unique rows (the Grand Opening Cue, the Beta Cue) take the rest.
			for _, unique in BlockOdds.uniqueRows(case.Id) do
				total += unique.percent
			end
			H.near(total, 100, 1e-9, case.Id .. " total")
		end
		-- In the Legendary row each of the 7 Legendaries is 25/7%, each of the 3 Mythics 0.9%.
		for _, entry in BlockOdds.cueOdds("Legendary") do
			if entry.rarity == "Legendary" then
				H.near(entry.percent, 25 / 7, 1e-9, entry.id)
				H.expect(entry.display == "3.571%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Mythic" then
				H.expect(entry.display == "0.9%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Secret" then
				H.expect(entry.display == "0.3%", entry.id .. " shows " .. entry.display)
			end
		end
		-- The rarest share anywhere still reads as more than 0.
		for _, entry in BlockOdds.cueOdds("Standard") do
			if entry.rarity == "Mythic" then
				H.expect(entry.display == "0.0003%", "Standard Mythic shows " .. entry.display)
			elseif entry.rarity == "Secret" then
				H.expect(entry.display == "0.0001%", "Standard Secret shows " .. entry.display)
			end
		end
	end,

	["percent text keeps small odds visible"] = function()
		local BlockOdds = load()
		local cases: { { any } } = {
			{ 64.3, "64.3%" },
			{ 20, "20%" },
			{ 100, "100%" },
			{ 20 / 3, "6.667%" },
			{ 0.25 / 3, "0.083%" },
			{ 0.01, "0.01%" },
			{ 0.004, "0.004%" },
			{ 0.0015, "0.0015%" },
			{ 0.00012, "0.00012%" },
		}
		for _, c in cases do
			local got = BlockOdds.percentText(c[1])
			H.expect(got == c[2], ("%s -> %s, expected %s"):format(tostring(c[1]), got, c[2]))
		end
	end,

	["200,000 seeded rolls per row land on each share and never break the guarantee"] = function()
		local BlockOdds, Catalog, Config = load()
		local ROLLS = 200000
		for caseIndex, case in BlockOdds.list() do
			local rng = seeded(0x9E3779B9 + caseIndex * 7919)
			local byRarity: { [string]: number } = {}
			local byCue: { [string]: number } = {}
			local floor = Catalog.rarityRank(BlockOdds.minRarity(case.Id) :: string)
			for _ = 1, ROLLS do
				local id, rarity = BlockOdds.roll(case.Id, rng)
				local cue = Catalog.get(id)
				assert(cue, "rolled unknown cue " .. tostring(id))
				if cue.Rarity ~= rarity or Catalog.rarityRank(rarity) < floor then
					error(("%s rolled %s (%s) as %s"):format(case.Id, id, cue.Rarity, rarity))
				end
				if not BlockOdds.canDrop(case.Id, id) then
					error(("%s rolled %s, which it cannot drop"):format(case.Id, id))
				end
				byRarity[rarity] = (byRarity[rarity] or 0) + 1
				byCue[id] = (byCue[id] or 0) + 1
			end
			for _, rarity in Config.BlockOdds.Rarities do
				local p = (case.Odds[rarity] or 0) / Config.BlockOdds.OddsTotal
				local got = byRarity[rarity] or 0
				local expected = ROLLS * p
				H.expect(
					math.abs(got - expected) <= tolerance(ROLLS, p),
					("%s %s: %d rolls, expected %.1f +- %.1f"):format(
						case.Id,
						rarity,
						got,
						expected,
						tolerance(ROLLS, p)
					)
				)
			end
			for _, entry in BlockOdds.cueOdds(case.Id) do
				local p = entry.percent / 100
				local got = byCue[entry.id] or 0
				H.expect(
					math.abs(got - ROLLS * p) <= tolerance(ROLLS, p),
					("%s %s: %d rolls, expected %.1f"):format(case.Id, entry.id, got, ROLLS * p)
				)
			end
		end
	end,

	["roll uses the rng's top and bottom values and refuses bad input"] = function()
		local BlockOdds, Catalog = load()
		-- rng always 1: the first weight (the guarantee's rarity), the first cue of it.
		local low, lowRarity = BlockOdds.roll("Epic", function(_n: number): number
			return 1
		end)
		H.expect(lowRarity == "Rare" and low == "HoneycombCue", "lowest roll: " .. low)
		-- rng always n: the last rarity, its last cue.
		local high, highRarity = BlockOdds.roll("Rare", function(n: number): number
			return n
		end)
		H.expect(highRarity == "Secret" and high == "EclipseCue", "highest roll: " .. high)
		local secrets = Catalog.droppable("Standard", "Secret")
		local top, topRarity = BlockOdds.roll("Standard", function(n: number): number
			return n
		end)
		H.expect(topRarity == "Secret" and top == secrets[#secrets].Id, "Standard's top: " .. top)
		H.expect(not pcall(BlockOdds.roll, "Nope", seeded(1)), "unknown row")
		H.expect(not pcall(BlockOdds.roll, "Standard", function(n: number): number
			return n + 1
		end), "out-of-range rng")
	end,

	["a vaulted cue never drops and leaves the Odds screen at once"] = function()
		local BlockOdds, Catalog = load()
		withVaulted(Catalog, "MidnightCue", function()
			H.expect(not BlockOdds.canDrop("Standard", "MidnightCue"), "vaulted: cannot drop")
			for _, entry in BlockOdds.cueOdds("Standard") do
				H.expect(entry.id ~= "MidnightCue", "MidnightCue still listed")
				if entry.rarity == "Common" then
					H.near(entry.percent, 72.5 / 6, 1e-9, entry.id)
				end
			end
			local total = 0
			for _, entry in BlockOdds.cueOdds("Standard") do
				total += entry.percent
			end
			H.near(total, 100, 1e-9, "total with a cue vaulted")
			local rng = seeded(12345)
			for _ = 1, 20000 do
				local id = BlockOdds.roll("Standard", rng)
				H.expect(id ~= "MidnightCue", "a vaulted cue dropped")
			end
		end)
		H.expect(not (Catalog.get("MidnightCue") :: any).Vaulted, "restored")
		H.expect(BlockOdds.canDrop("Standard", "MidnightCue"), "drops again")
		-- Vaulting the only Secret leaves a share with no cue: validate says so.
		withVaulted(Catalog, "EclipseCue", function()
			local problems = BlockOdds.validate()
			H.expect(#problems >= 4, "validate missed the empty Secret pool")
			H.expect(problems[1]:find("Secret") ~= nil, problems[1] or "")
		end)
		H.expect(#BlockOdds.validate() == 0, "valid again once restored")
	end,

	["sell-back values match ECONOMY 8; confirm from Epic up; only block cues sell"] = function()
		local BlockOdds, Catalog = load()
		for _, cue in Catalog.list() do
			local value = BlockOdds.sellValue(cue.Id)
			if cue.Group == "Block" then
				H.expect(value == SELL[cue.Rarity], ("%s sells for %d"):format(cue.Id, value))
				local rank = Catalog.rarityRank(cue.Rarity)
				H.expect(
					BlockOdds.needsConfirm(cue.Id) == (rank >= Catalog.rarityRank("Epic")),
					cue.Id .. " confirm"
				)
			else
				H.expect(value == 0, cue.Id .. " must not sell")
				H.expect(not BlockOdds.needsConfirm(cue.Id), cue.Id .. " has nothing to confirm")
			end
		end
		H.expect(BlockOdds.sellValue("Nope") == 0 and BlockOdds.sellValue(nil) == 0, "unknown ids")
	end,

	["Legendary pulls announce in the server; Mythic and Secret in every server"] = function()
		local BlockOdds, _, Config = load()
		for _, rarity in Config.BlockOdds.Rarities do
			local everywhere = rarity == "Mythic" or rarity == "Secret"
			H.expect(BlockOdds.announces(rarity) == everywhere, rarity)
			H.expect(BlockOdds.announcesHere(rarity) == (rarity == "Legendary"), rarity .. " here")
		end
	end,

	["the top rarity and the Unique rows of the extra tables"] = function()
		local BlockOdds, Catalog = load()
		H.expect(BlockOdds.topRarity("Standard") == "Secret", "every row reaches the Secret (v4)")
		H.expect(BlockOdds.topRarity("Rare") == "Secret", "Rare reaches Secret")
		H.expect(BlockOdds.topRarity("Nope") == nil, "unknown")
		H.expect(#BlockOdds.uniqueRows("GrandOpening") == 2, "two Unique rows")
		H.expect(#BlockOdds.uniqueRows("Standard") == 0, "the ladder rows have none")
		H.expect(BlockOdds.canDrop("GrandOpening", "BetaCue"), "the Beta Cue drops from it")
		H.expect(not BlockOdds.canDrop("Standard", "BetaCue"), "not from the Standard row")
		H.expect(not BlockOdds.canDrop("Standard", "Classic"), "Classic never drops")
		H.expect(not BlockOdds.canDrop("Nope", "MidnightCue"), "unknown row")
		H.expect(Catalog.get("MidnightCue").Group == "Block", "a droppable cue is a Block cue")
	end,
	["the Grand Opening: 1,000 Firework and 100 Beta Cues ever; owned or all found reads as Rare"] = function()
		local BlockOdds, _, Config = load()
		local row = Config.BlockOdds.List.GrandOpening
		H.expect(row.Odds.FireworkCue == 60000 and row.Odds.BetaCue == 4000, "6% and 0.4%")
		H.expect(row.Odds.Uncommon == nil and BlockOdds.minRarity("GrandOpening") == "Rare", "")
		local caps = BlockOdds.caps("GrandOpening")
		H.expect(caps.FireworkCue == 1000 and caps.BetaCue == 100, "the caps")
		H.expect(next(BlockOdds.caps("Rare")) == nil, "no caps elsewhere")
		local G = Config.LuckyBlocks.Kinds.GrandOpening.Guarantee
		H.expect(G.Cue == "BetaCue" and G.At == 1000, "the 1,000th block's Beta Cue")
		-- Nobody owns one and copies are left: nothing closed, the row as Config says.
		local none = BlockOdds.closedFor("GrandOpening", function()
			return false
		end, function()
			return 5
		end)
		H.expect(next(none) == nil, "open")
		H.expect(BlockOdds.rowFor("GrandOpening", none).Odds.Rare == 818400, "unchanged")
		-- The Beta Cue all found, the Firework Cue owned: both shares go to Rare.
		local closed = BlockOdds.closedFor("GrandOpening", function(cue)
			return cue == "FireworkCue"
		end, function(cue)
			return if cue == "BetaCue" then 100 else 400
		end)
		H.expect(closed.BetaCue and closed.FireworkCue, "both closed")
		local mine = BlockOdds.rowFor("GrandOpening", closed) :: any
		H.expect(mine.Odds.Rare == 818400 + 60000 + 4000, "the shares moved to Rare")
		H.expect(mine.Odds.FireworkCue == nil and mine.Odds.BetaCue == nil, "")
		H.expect(Config.BlockOdds.List.GrandOpening.Odds.BetaCue == 4000, "Config untouched")
		H.expect(#BlockOdds.uniqueRows("GrandOpening", closed) == 0, "no Unique rows shown")
		local total = 0
		for _, entry in BlockOdds.odds("GrandOpening", closed) do
			total += entry.percent
		end
		H.near(total, 100, 1e-9, "the player's odds still add to 100")
		local rng = seeded(77)
		for _ = 1, 5000 do
			local id, rarity = BlockOdds.roll("GrandOpening", rng, closed)
			H.expect(rarity ~= "Unique" and id ~= "BetaCue", "never a closed row")
		end
		-- An unknown count closes nothing (only the atomic counter refuses past the cap).
		local unknown = BlockOdds.closedFor("GrandOpening", nil, function()
			return nil
		end)
		H.expect(next(unknown) == nil, "unknown: open")
	end,
}
