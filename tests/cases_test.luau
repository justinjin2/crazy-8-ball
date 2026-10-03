--!strict
-- Cases (Progression/Cases): the six cases' odds and timers against the approved economy plan
-- (2026-10-02, section 3), per-cue odds, seeded rolls, the guarantee, vaulting, sell-back values
-- (ECONOMY 8), announcements and whether a win drops a Case Drop (plan sections 1-2, 3.6).

local H = require("./harness")

local function load()
	return H.require("Progression.Cases"), H.require("Progression.Catalog"), H.require("Config")
end

-- The plan's section 3 table, in percent as it prints them (nil = "-").
local ODDS: { [string]: { [string]: number } } = {
	Standard = {
		Common = 75,
		Uncommon = 23,
		Rare = 1.99,
		Epic = 0.009,
		Legendary = 0.0009,
		Mythic = 0.0001,
	},
	Uncommon = {
		Common = 40,
		Uncommon = 54,
		Rare = 5.95,
		Epic = 0.045,
		Legendary = 0.0045,
		Mythic = 0.0005,
	},
	Rare = {
		Uncommon = 70,
		Rare = 29.6,
		Epic = 0.35,
		Legendary = 0.045,
		Mythic = 0.0045,
		Secret = 0.0005,
	},
	Epic = { Rare = 78, Epic = 19, Legendary = 2.6, Mythic = 0.36, Secret = 0.04 },
	Legendary = { Epic = 75, Legendary = 22, Mythic = 2.7, Secret = 0.3 },
	Mythic = { Legendary = 75, Mythic = 22, Secret = 3 },
}
-- Opens in (seconds): instant, instant, 1 h, 6 h, 24 h, 48 h.
local TIMERS =
	{ Standard = 0, Uncommon = 0, Rare = 3600, Epic = 21600, Legendary = 86400, Mythic = 172800 }
local MIN_RARITY = {
	Standard = "Common",
	Uncommon = "Common",
	Rare = "Uncommon",
	Epic = "Rare",
	Legendary = "Epic",
	Mythic = "Legendary",
}

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
		pcLimited = false,
		pcDropsToday = 0,
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
	["every odds row adds to exactly 1,000,000 and matches the plan"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Cases.OddsTotal == 1000000, "OddsTotal")
		local problems = Cases.validate()
		H.expect(#problems == 0, "validate: " .. table.concat(problems, "; "))
		for id, row in ODDS do
			local case = Cases.get(id)
			H.expect(case ~= nil, id .. " is not a case")
			assert(case, "no case")
			H.expect(case.Timer == TIMERS[id], ("%s opens in %d s"):format(id, case.Timer))
			local sum = 0
			for _, rarity in Config.Cases.Rarities do
				local expected = math.floor((row[rarity] or 0) * 10000 + 0.5)
				local got = case.Odds[rarity] or 0
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
			for _, entry in Cases.odds(id) do
				H.near(
					entry.percent,
					row[entry.rarity],
					1e-9,
					id .. " " .. entry.rarity .. " percent"
				)
				local rank = table.find(Config.Cases.Rarities, entry.rarity) or 0
				H.expect(rank > previous, id .. " odds out of order")
				previous = rank
				total += entry.percent
			end
			H.near(total, 100, 1e-9, id .. " percents add to 100")
			H.expect(Cases.minRarity(id) == MIN_RARITY[id], id .. " guarantee")
		end
		H.expect(Cases.odds("Nope")[1] == nil and Cases.minRarity("Nope") == nil, "unknown case")
	end,

	["six cases on the ladder, none sold for money"] = function()
		local Cases, _, Config = load()
		H.expect(
			table.concat(Config.Cases.Order, " ") == "Standard Uncommon Rare Epic Legendary Mythic",
			"the ladder"
		)
		H.expect(#Cases.list() == 0, "no case is in the shop")
		local all = {}
		for _, case in Cases.list(true) do
			table.insert(all, case.Id)
			H.expect(not case.Enabled and case.Price == 0, case.Id .. " is not sold")
		end
		H.expect(table.concat(all, " ") == table.concat(Config.Cases.Order, " "), "all")
		H.expect(
			Cases.get("Event") == nil and Cases.get("Nope") == nil and Cases.get(3) == nil,
			"unknown ids"
		)
		H.expect(Cases.get(nil) == nil, "nil")
	end,

	["timers: instant to 48 hours, halved with Quick Cases"] = function()
		local Cases, _, Config = load()
		H.expect(Config.Cases.QuickTimerFactor == 0.5, "twice as fast")
		for id, seconds in TIMERS do
			H.expect(Cases.timer(id) == seconds, id)
			H.expect(Cases.timer(id, true) == seconds // 2, id .. " quick")
		end
		H.expect(Cases.timer("Nope") == 0 and Cases.timer(nil, true) == 0, "unknown: 0")
	end,

	["per-cue odds split each rarity evenly and total 100"] = function()
		local Cases, Catalog, Config = load()
		for _, case in Cases.list(true) do
			local total = 0
			local lastRank = 0
			local listed = 0
			for _, entry in Cases.cueOdds(case.Id) do
				local pool = Catalog.droppable(case.Id, entry.rarity)
				H.near(
					entry.percent,
					case.Odds[entry.rarity] * 100 / Config.Cases.OddsTotal / #pool,
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
		-- In the Legendary Case each of the 7 Legendaries is 22/7%, each of the 3 Mythics 0.9%.
		for _, entry in Cases.cueOdds("Legendary") do
			if entry.rarity == "Legendary" then
				H.near(entry.percent, 22 / 7, 1e-9, entry.id)
				H.expect(entry.display == "3.143%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Mythic" then
				H.expect(entry.display == "0.9%", entry.id .. " shows " .. entry.display)
			elseif entry.rarity == "Secret" then
				H.expect(entry.display == "0.3%", entry.id .. " shows " .. entry.display)
			end
		end
		-- The rarest share anywhere still reads as more than 0.
		for _, entry in Cases.cueOdds("Standard") do
			if entry.rarity == "Mythic" then
				H.expect(entry.display == "0.000033%", "Standard Mythic shows " .. entry.display)
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
		local Cases, Catalog = load()
		-- rng always 1: the first weight (the guarantee's rarity), the first cue of it.
		local low, lowRarity = Cases.roll("Epic", function(_n: number): number
			return 1
		end)
		H.expect(lowRarity == "Rare" and low == "HoneycombCue", "lowest roll: " .. low)
		-- rng always n: the last rarity, its last cue.
		local high, highRarity = Cases.roll("Rare", function(n: number): number
			return n
		end)
		H.expect(highRarity == "Secret" and high == "EclipseCue", "highest roll: " .. high)
		local mythics = Catalog.droppable("Standard", "Mythic")
		local top, topRarity = Cases.roll("Standard", function(n: number): number
			return n
		end)
		H.expect(topRarity == "Mythic" and top == mythics[#mythics].Id, "Standard's top: " .. top)
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
					H.near(entry.percent, 75 / 6, 1e-9, entry.id)
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

	["Legendary pulls announce in the server; Mythic and Secret in every server"] = function()
		local Cases, _, Config = load()
		for _, rarity in Config.Cases.Rarities do
			local everywhere = rarity == "Mythic" or rarity == "Secret"
			H.expect(Cases.announces(rarity) == everywhere, rarity)
			H.expect(Cases.announcesHere(rarity) == (rarity == "Legendary"), rarity .. " here")
		end
	end,

	["drop: every real win drops one, forever"] = function()
		local Cases = load()
		for _, overrides in { {}, { loserRealMatches = 5 }, { casesFromOpponentToday = 2 } } do
			local drops, forced = Cases.dropFor(ctx(overrides))
			H.expect(drops and forced == nil, "a normal roll")
		end
	end,

	["drop: the first win ever is the Rare Case, under the same anti-farm rules"] = function()
		local Cases = load()
		local drops, forced = Cases.dropFor(ctx({ firstWinEver = true }))
		H.expect(drops and forced == "Rare", "the first win's Rare Case")
		drops = Cases.dropFor(ctx({ firstWinEver = true, loserRealMatches = 4 }))
		H.expect(not drops, "a first win against a new account drops nothing")
		drops = Cases.dropFor(ctx({ firstWinEver = true, farmAllows = false }))
		H.expect(not drops, "nor on a farm row")
	end,

	["drop: never for solo, a loss or a match that was not real"] = function()
		local Cases = load()
		for _, overrides in { { solo = true }, { won = false }, { real = false } } do
			H.expect(not (Cases.dropFor(ctx(overrides))), "no drop")
		end
	end,

	["drop: the anti-farm rules (matches 6-10, 3 a day from one account, 5 real matches)"] = function()
		local Cases, _, Config = load()
		local E = Config.Economy
		H.expect(not (Cases.dropFor(ctx({ farmAllows = false }))), "a row with no case")
		H.expect(
			not (Cases.dropFor(ctx({ casesFromOpponentToday = E.FreeCasesPerOpponent }))),
			"3 from one account"
		)
		H.expect(
			not (Cases.dropFor(ctx({ loserRealMatches = E.FreeCaseLoserMinMatches - 1 }))),
			"a loser with too few real matches"
		)
	end,

	["drop: Play against PC drops only for the first 10 PC wins of a day"] = function()
		local Cases, _, Config = load()
		local cap = Config.Economy.PcDropsPerDay
		H.expect(cap == 10, "the plan's 10")
		H.expect(Cases.dropFor(ctx({ pcLimited = true, pcDropsToday = cap - 1 })), "the 10th")
		H.expect(not (Cases.dropFor(ctx({ pcLimited = true, pcDropsToday = cap }))), "the 11th")
		H.expect(Cases.dropFor(ctx({ pcLimited = false, pcDropsToday = 99 })), "people: no cap")
	end,
}
