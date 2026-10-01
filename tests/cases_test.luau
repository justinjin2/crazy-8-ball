--!strict
-- Cases (Progression/Cases): the odds against ECONOMY 7.2 and 9.1, per-cue odds (7.3), seeded
-- rolls, the guarantee, vaulting, prices (bulk, sales), sell-back values (8) and the winner's
-- free case (7.1, 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.Cases"), H.require("Progression.Catalog"), H.require("Config")
end

-- ECONOMY 7.2 and 9.1, in percent as the tables print them (nil = "-").
local ODDS: { [string]: { [string]: number } } = {
	Standard = {
		Common = 64.3,
		Uncommon = 26,
		Rare = 8.4,
		Epic = 1,
		Legendary = 0.25,
		Mythic = 0.047,
		Secret = 0.003,
	},
	Rare = {
		Uncommon = 62.5,
		Rare = 31,
		Epic = 5.5,
		Legendary = 0.85,
		Mythic = 0.14,
		Secret = 0.01,
	},
	Epic = { Rare = 73.4, Epic = 22, Legendary = 4, Mythic = 0.56, Secret = 0.04 },
	Legendary = { Epic = 76.5, Legendary = 20, Mythic = 3.25, Secret = 0.25 },
	Event = { Rare = 72.5, Epic = 22, Legendary = 4.6, Mythic = 0.8, Secret = 0.1 },
}
local PRICES = { Standard = 150, Rare = 500, Epic = 1500, Legendary = 5000, Event = 2000 }
local MIN_RARITY =
	{ Standard = "Common", Rare = "Uncommon", Epic = "Rare", Legendary = "Epic", Event = "Rare" }

-- ECONOMY 8: sell-back per copy.
local SELL = {
	Common = 15,
	Uncommon = 40,
	Rare = 120,
	Epic = 600,
	Legendary = 3000,
	Mythic = 15000,
	Secret = 75000,
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

-- A settled real 1v1 win by a veteran player, overridden per test.
local function ctx(overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		real = true,
		solo = false,
		won = true,
		winsBefore = 100,
		winsTodayBefore = 0,
		farmAllows = true,
		casesFromOpponentToday = 0,
		loserRealMatches = 100,
		firstWinEver = false,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

return {
	["every odds row adds to exactly 100,000 and matches ECONOMY 7.2 and 9.1"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Cases.OddsTotal == 100000, "OddsTotal")
		local problems = Cases.validate()
		H.expect(#problems == 0, "validate: " .. table.concat(problems, "; "))
		for id, row in ODDS do
			local case = Cases.get(id)
			H.expect(case ~= nil, id .. " is not a case")
			assert(case, "no case")
			H.expect(
				case.Price == PRICES[id],
				("%s costs %d, expected %d"):format(id, case.Price, PRICES[id])
			)
			local sum = 0
			for _, rarity in Config.Cases.Rarities do
				local expected = math.floor((row[rarity] or 0) * 1000 + 0.5)
				local got = case.Odds[rarity] or 0
				H.expect(
					got == expected,
					("%s %s: %d, expected %d"):format(id, rarity, got, expected)
				)
				sum += got
			end
			H.expect(sum == 100000, ("%s adds to %d"):format(id, sum))
			-- odds() lists exactly the rarities with a share, bottom first, with percents.
			local listed = Cases.odds(id)
			local previous = 0
			for _, entry in listed do
				H.near(
					entry.percent,
					row[entry.rarity],
					1e-9,
					id .. " " .. entry.rarity .. " percent"
				)
				local rank = table.find(Config.Cases.Rarities, entry.rarity) or 0
				H.expect(rank > previous, id .. " odds out of order")
				previous = rank
			end
			H.expect(Cases.minRarity(id) == MIN_RARITY[id], id .. " guarantee")
		end
		H.expect(Cases.odds("Nope")[1] == nil and Cases.minRarity("Nope") == nil, "unknown case")
	end,

	["list is the enabled cases in shop order; get knows every case"] = function()
		local Cases = load()
		local ids = {}
		for _, case in Cases.list() do
			table.insert(ids, case.Id)
		end
		H.expect(
			table.concat(ids, " ") == "Standard Rare Epic Legendary",
			"enabled: " .. table.concat(ids, " ")
		)
		local all = {}
		for _, case in Cases.list(true) do
			table.insert(all, case.Id)
		end
		H.expect(
			table.concat(all, " ") == "Standard Rare Epic Legendary Event",
			"all: " .. table.concat(all, " ")
		)
		local event = Cases.get("Event")
		H.expect(event ~= nil and event.Enabled == false, "the Event Case is off")
		H.expect(
			Cases.get("Nope") == nil and Cases.get(3) == nil and Cases.get(nil) == nil,
			"unknown ids"
		)
	end,

	["per-cue odds split each rarity evenly and total 100"] = function()
		local Cases, Catalog = load()
		for _, case in Cases.list(true) do
			local total = 0
			local lastRank = 0
			local listed = 0
			for _, entry in Cases.cueOdds(case.Id) do
				local pool = Catalog.droppable(case.Id, entry.rarity)
				H.near(
					entry.percent,
					case.Odds[entry.rarity] / 1000 / #pool,
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
			for _, entry in Cases.odds(case.Id) do
				droppable += #Catalog.droppable(case.Id, entry.rarity)
			end
			H.expect(
				listed == droppable,
				("%s lists %d cues, expected %d"):format(case.Id, listed, droppable)
			)
			H.near(total, 100, 1e-9, case.Id .. " total")
		end
		-- ECONOMY 7.3's example: in the Legendary Case each of the 7 Legendaries is 2.857%, each
		-- of the 3 Mythics 1.083%.
		for _, entry in Cases.cueOdds("Legendary") do
			if entry.rarity == "Legendary" then
				H.near(entry.percent, 20 / 7, 1e-9, entry.id)
				H.expect(entry.display == "2.857%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Mythic" then
				H.near(entry.percent, 3.25 / 3, 1e-9, entry.id)
				H.expect(entry.display == "1.083%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Secret" then
				H.expect(entry.display == "0.25%", entry.id .. " shows " .. entry.display)
			end
		end
		for _, entry in Cases.cueOdds("Standard") do
			if entry.rarity == "Secret" then
				H.expect(entry.display == "0.003%", "Standard Secret shows " .. entry.display)
			end
		end
	end,

	["percent text keeps small odds visible"] = function()
		local Cases = load()
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
			local got = Cases.percentText(c[1])
			H.expect(got == c[2], ("%s -> %s, expected %s"):format(tostring(c[1]), got, c[2]))
		end
	end,

	["200,000 seeded rolls per case land on each share and never break the guarantee"] = function()
		local Cases, Catalog, Config = load()
		local ROLLS = 200000
		for caseIndex, case in Cases.list(true) do
			local rng = seeded(0x9E3779B9 + caseIndex * 7919)
			local byRarity: { [string]: number } = {}
			local byCue: { [string]: number } = {}
			local floor = Catalog.rarityRank(Cases.minRarity(case.Id) :: string)
			for _ = 1, ROLLS do
				local id, rarity = Cases.roll(case.Id, rng)
				local cue = Catalog.get(id)
				assert(cue, "rolled unknown cue " .. tostring(id))
				if cue.Rarity ~= rarity or Catalog.rarityRank(rarity) < floor then
					error(("%s rolled %s (%s) as %s"):format(case.Id, id, cue.Rarity, rarity))
				end
				if cue.Group ~= "Case" or cue.Vaulted or not table.find(cue.Cases, case.Id) then
					error(("%s rolled %s, which it cannot drop"):format(case.Id, id))
				end
				byRarity[rarity] = (byRarity[rarity] or 0) + 1
				byCue[id] = (byCue[id] or 0) + 1
			end
			for _, rarity in Config.Cases.Rarities do
				local p = (case.Odds[rarity] or 0) / Config.Cases.OddsTotal
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
			for _, entry in Cases.cueOdds(case.Id) do
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
		local Cases = load()
		-- rng always 1: the first weight (the guarantee's rarity), the first cue of it.
		local low, lowRarity = Cases.roll("Epic", function(_n: number): number
			return 1
		end)
		H.expect(lowRarity == "Rare" and low == "HoneycombCue", "lowest roll: " .. low)
		-- rng always n: the last rarity (Secret), its last cue.
		local high, highRarity = Cases.roll("Standard", function(n: number): number
			return n
		end)
		H.expect(highRarity == "Secret" and high == "EclipseCue", "highest roll: " .. high)
		H.expect(not pcall(Cases.roll, "Nope", seeded(1)), "unknown case")
		H.expect(not pcall(Cases.roll, "Standard", function(n: number): number
			return n + 1
		end), "out-of-range rng")
	end,

	["a vaulted cue never drops and leaves the Odds screen at once"] = function()
		local Cases, Catalog = load()
		withVaulted(Catalog, "MidnightCue", function()
			for _, entry in Cases.cueOdds("Standard") do
				H.expect(entry.id ~= "MidnightCue", "MidnightCue still listed")
				if entry.rarity == "Common" then
					H.near(entry.percent, 64.3 / 6, 1e-9, entry.id)
				end
			end
			local total = 0
			for _, entry in Cases.cueOdds("Standard") do
				total += entry.percent
			end
			H.near(total, 100, 1e-9, "total with a cue vaulted")
			local rng = seeded(12345)
			for _ = 1, 20000 do
				local id = Cases.roll("Standard", rng)
				H.expect(id ~= "MidnightCue", "a vaulted cue dropped")
			end
		end)
		H.expect(not (Catalog.get("MidnightCue") :: any).Vaulted, "restored")
		-- Vaulting the only Secret leaves a share with no cue: validate says so.
		withVaulted(Catalog, "EclipseCue", function()
			local problems = Cases.validate()
			H.expect(#problems >= 4, "validate missed the empty Secret pool")
			H.expect(problems[1]:find("Secret") ~= nil, problems[1] or "")
		end)
		H.expect(#Cases.validate() == 0, "valid again once restored")
	end,

	["bulk: 10 of any case for the price of 9"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Cases.BulkCount == 10 and Config.Cases.BulkPayFor == 9, "10 for 9")
		for id, price in PRICES do
			local total, per, onSale = Cases.price(id, 1, 0, nil)
			H.expect(total == price and per == price and not onSale, id .. " single")
			total, per, onSale = Cases.price(id, 10, 0, nil)
			H.expect(total == price * 9 and per == price and not onSale, id .. " bulk: " .. total)
		end
		H.expect(Cases.isBuyCount(1) and Cases.isBuyCount(10), "1 and 10")
		H.expect(
			not Cases.isBuyCount(2) and not Cases.isBuyCount(0) and not Cases.isBuyCount("10"),
			"others"
		)
		H.expect(not pcall(Cases.price, "Nope", 1, 0, nil), "unknown case has no price")
		H.expect(not pcall(Cases.price, "Standard", 0, 0, nil), "zero count has no price")
		H.expect(not pcall(Cases.price, "Standard", 1.5, 0, nil), "fractional count")
	end,

	["a sale takes its percent off one case until it ends"] = function()
		local Cases, _, Config = load()
		local sale = { Case = "Epic", Percent = 20, EndsAt = 1000 }
		local total, per, onSale = Cases.price("Epic", 1, 999, sale)
		H.expect(total == 1200 and per == 1200 and onSale, "Epic 20% off: " .. total)
		total, per, onSale = Cases.price("Epic", 10, 999, sale)
		H.expect(total == 10800 and per == 1200 and onSale, "Epic bulk on sale: " .. total)
		total, per, onSale = Cases.price("Epic", 1, 1000, sale)
		H.expect(total == 1500 and per == 1500 and not onSale, "the sale ends at EndsAt")
		total, _, onSale = Cases.price("Rare", 1, 999, sale)
		H.expect(total == 500 and not onSale, "other cases keep their price")
		-- Rounded half up to whole money: 15% off $150 is $127.50 -> $128.
		total = Cases.price("Standard", 1, 0, { Case = "Standard", Percent = 15, EndsAt = 10 })
		H.expect(total == 128, "rounding: " .. total)
		total, _, onSale =
			Cases.price("Standard", 1, 0, { Case = "Standard", Percent = 0, EndsAt = 10 })
		H.expect(total == 150 and not onSale, "0% is no sale")
		-- Config's default sale is off.
		total, _, onSale = Cases.price("Standard", 1, 0, Config.Cases.Sale)
		H.expect(total == 150 and not onSale, "no sale by default")
	end,

	["sell-back values match ECONOMY 8; confirm from Epic up; only case cues sell"] = function()
		local Cases, Catalog = load()
		for _, cue in Catalog.list() do
			local value = Cases.sellValue(cue.Id)
			if cue.Group == "Case" then
				H.expect(value == SELL[cue.Rarity], ("%s sells for %d"):format(cue.Id, value))
				local rank = Catalog.rarityRank(cue.Rarity)
				H.expect(
					Cases.needsConfirm(cue.Id) == (rank >= Catalog.rarityRank("Epic")),
					cue.Id .. " confirm"
				)
			else
				H.expect(value == 0, cue.Id .. " must not sell")
				H.expect(not Cases.needsConfirm(cue.Id), cue.Id .. " has nothing to confirm")
			end
		end
		H.expect(Cases.sellValue("Nope") == 0 and Cases.sellValue(nil) == 0, "unknown ids")
	end,

	["Mythic and Secret unboxings are announced, nothing else"] = function()
		local Cases, _, Config = load()
		for _, rarity in Config.Cases.Rarities do
			local expected = rarity == "Mythic" or rarity == "Secret"
			H.expect(Cases.announces(rarity) == expected, rarity)
		end
	end,

	["free case: the first win ever gives the Rare Case"] = function()
		local Cases = load()
		H.expect(
			Cases.freeCase(ctx({ firstWinEver = true, winsBefore = 0 })) == "Rare",
			"first win"
		)
		-- Against a PC too (the tutorial): the loser's matches are taken as many.
		H.expect(
			Cases.freeCase(
				ctx({ firstWinEver = true, winsBefore = 0, loserRealMatches = math.huge })
			) == "Rare",
			"first win against a PC"
		)
	end,

	["free case: every one of a new player's first 50 wins"] = function()
		local Cases = load()
		for winsBefore = 0, 49 do
			-- However many wins today: the new-player stretch ignores the daily count.
			local got =
				Cases.freeCase(ctx({ winsBefore = winsBefore, winsTodayBefore = 30 + winsBefore }))
			H.expect(got == "Standard", ("win %d: %s"):format(winsBefore + 1, tostring(got)))
		end
		H.expect(
			Cases.freeCase(ctx({ winsBefore = 50, winsTodayBefore = 30 })) == nil,
			"win 51 is the 31st today"
		)
	end,

	["free case: after 50 wins, the first 10 of the day then every 2nd"] = function()
		local Cases = load()
		local dropped = {}
		for winsToday = 0, 29 do
			local got =
				Cases.freeCase(ctx({ winsBefore = 200 + winsToday, winsTodayBefore = winsToday }))
			if got then
				H.expect(got == "Standard", "a Standard Case")
				table.insert(dropped, winsToday + 1)
			end
		end
		H.expect(
			table.concat(dropped, ",") == "1,2,3,4,5,6,7,8,9,10,12,14,16,18,20,22,24,26,28,30",
			"wins that drop: " .. table.concat(dropped, ",")
		)
		-- A day that crosses the 50th win counts the day's earlier wins too.
		H.expect(
			Cases.freeCase(ctx({ winsBefore = 49, winsTodayBefore = 14 })) == "Standard",
			"the 50th win"
		)
		H.expect(
			Cases.freeCase(ctx({ winsBefore = 50, winsTodayBefore = 15 })) == "Standard",
			"16th today"
		)
		H.expect(
			Cases.freeCase(ctx({ winsBefore = 51, winsTodayBefore = 16 })) == nil,
			"17th today"
		)
	end,

	["free case: never for solo, a loss or a match that was not real"] = function()
		local Cases = load()
		for _, over in { { solo = true }, { won = false }, { real = false } } do
			H.expect(Cases.freeCase(ctx(over)) == nil, "no case")
			local first = table.clone(over) :: { [string]: any }
			first.firstWinEver = true
			first.winsBefore = 0
			H.expect(Cases.freeCase(ctx(first)) == nil, "not even the first win's")
		end
	end,

	["free case: the same opponent drops one in matches 1-5 only"] = function()
		local Cases, _, Config = load()
		-- The row of Config.Economy.SameOpponent that covers the nth match with one account.
		local function farmRow(match: number): any
			for _, row in Config.Economy.SameOpponent do
				if row.UpTo == nil or match <= row.UpTo then
					return row
				end
			end
			error("no row")
		end
		for match = 1, 15 do
			local got = Cases.freeCase(ctx({ farmAllows = farmRow(match).FreeCase }))
			H.expect(
				(got ~= nil) == (match <= 5),
				("match %d with the same account: %s"):format(match, tostring(got))
			)
		end
	end,

	["free case: at most 3 a day from one account"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Economy.FreeCasesPerOpponent == 3, "3 a day")
		for already = 0, 5 do
			local got = Cases.freeCase(ctx({ casesFromOpponentToday = already }))
			H.expect(
				(got ~= nil) == (already < 3),
				("%d already: %s"):format(already, tostring(got))
			)
		end
	end,

	["free case: the loser must have played 5 real matches"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Economy.FreeCaseLoserMinMatches == 5, "5 matches")
		for matches = 0, 6 do
			local got = Cases.freeCase(ctx({ loserRealMatches = matches }))
			H.expect(
				(got ~= nil) == (matches >= 5),
				("loser with %d matches: %s"):format(matches, tostring(got))
			)
		end
		-- A fresh alt can't feed the first win's Rare Case either.
		H.expect(
			Cases.freeCase(ctx({ firstWinEver = true, winsBefore = 0, loserRealMatches = 0 }))
				== nil,
			"alt"
		)
	end,
}
