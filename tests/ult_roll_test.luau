--!strict
-- Ult spins (Ults/Roll; docs/prompts/ULTIMATES_PROMPT.md sections 8 and 12): every odds table
-- adds to exactly 1,000,000 ppm, a million seeded rolls land on the odds, pity, Lucky Spins,
-- the pool without the developer flag (shares moving down) and determinism. Numbers come from
-- Config.Ults.Roll.

local H = require("./harness")

local function load(): (any, any, any)
	return H.require("Ults.Roll"), H.require("Config"), H.require("Ults.Catalog")
end

-- Four standard deviations of a binomial count, plus one.
local function tolerance(n: number, p: number): number
	return 4 * math.sqrt(n * p * (1 - p)) + 1
end

local function sum(rows: { any }): number
	local total = 0
	for _, row in rows do
		total += row.ppm
	end
	return total
end

local function rarityPpm(odds: any, rarity: string): number
	for _, row in odds.rarities do
		if row.rarity == rarity then
			return row.ppm
		end
	end
	error("no row for " .. rarity)
end

local function ultPpm(odds: any, id: string): number?
	for _, row in odds.ults do
		if row.id == id then
			return row.ppm
		end
	end
	return nil
end

-- Runs `body` with some ults' Built flags changed, restoring them whatever happens.
local function withBuilt(Config: any, built: { [string]: boolean }, body: () -> ())
	local was = {}
	for id, value in built do
		was[id] = Config.Ults.Catalog[id].Built
		Config.Ults.Catalog[id].Built = value
	end
	local ok, err = pcall(body)
	for id, value in was do
		Config.Ults.Catalog[id].Built = value
	end
	if not ok then
		error(err, 0)
	end
end

-- An rng that always returns `r`.
local function always(r: number): () -> number
	return function(): number
		return r
	end
end

return {
	["every odds table adds to exactly 1,000,000 ppm"] = function()
		local Roll, Config = load()
		H.expect(Roll.TOTAL == 1000000, "parts per million")
		for _, devAll in { false, true } do
			local tables = {
				Normal = Roll.odds("Normal", devAll),
				Lucky = Roll.odds("Lucky", devAll),
				Pity = Roll.pityOdds(devAll),
			}
			for name, odds in tables do
				local label = ("%s (flag %s)"):format(name, tostring(devAll))
				if name == "Lucky" and not devAll and not Roll.available("Lucky", false) then
					-- Only Commons are built: a Lucky Spin has nothing it may land.
					H.expect(not Roll.available("Lucky", false), "Lucky closed")
					H.expect(sum(odds.rarities) == 0 and sum(odds.ults) == 0, "Lucky: no odds")
					continue
				end
				H.expect(sum(odds.rarities) == 1000000, label .. ": rarities add to 1,000,000")
				H.expect(sum(odds.ults) == 1000000, label .. ": ults add to 1,000,000")
				H.expect(#odds.rarities == #Config.Ults.Rarities, label .. ": every rarity listed")
				for i, row in odds.rarities do
					H.expect(row.rarity == Config.Ults.Rarities[i], "ladder order")
					H.expect(row.ppm == math.floor(row.ppm) and row.ppm >= 0, "whole ppm")
				end
			end
		end
	end,

	["with the developer flag the odds are Config's, split evenly"] = function()
		local Roll, Config, Catalog = load()
		for _, kind in { "Normal", "Lucky" } do
			local odds = Roll.odds(kind, true)
			H.expect(#odds.ults == #Config.Ults.Order, "all 13 in the pool")
			for i, row in odds.ults do
				H.expect(row.id == Config.Ults.Order[i], "catalog order")
			end
			for _, rarity in Config.Ults.Rarities do
				local share = Config.Ults.Roll[kind][rarity]
				H.expect(rarityPpm(odds, rarity) == share, kind .. " " .. rarity)
				local ids = Catalog.byRarity(rarity)
				local given = 0
				for _, id in ids do
					local ppm = ultPpm(odds, id) :: number
					H.expect(math.abs(ppm - share / #ids) <= 1, "an even split: " .. id)
					given += ppm
				end
				H.expect(given == share, "the split keeps the whole share")
			end
		end
		-- The brief's per-ult odds.
		local normal = Roll.odds("Normal", true)
		-- (The abilities rework, 2026-10-08: Common is Eagle's Eye and Fire Shot.)
		H.expect(ultPpm(normal, "EaglesEye") == 275000, "27.5% (Common's share between two)")
		H.expect(ultPpm(normal, "BlackHole") == 500, "0.05%")
	end,

	["a million seeded rolls land on every rarity's share"] = function()
		local Roll, Config = load()
		local n = 1000000
		local rng = Roll.seeded(20260928)
		local counts: { [string]: number } = {}
		for _, rarity in Config.Ults.Rarities do
			counts[rarity] = 0
		end
		for _ = 1, n do
			local _, rarity = Roll.roll("Normal", 0, rng, true)
			counts[rarity] += 1
		end
		for _, rarity in Config.Ults.Rarities do
			local p = Config.Ults.Roll.Normal[rarity] / 1000000
			local expected = n * p
			H.near(counts[rarity], expected, tolerance(n, p), rarity)
		end
		-- Legendary about 1 in 150, Mythic about 1 in 1,000.
		H.near(n / counts.Legendary, 150, 10, "Legendary 1 in 150")
		H.near(n / counts.Mythic, 1000, 150, "Mythic 1 in 1,000")
	end,

	["pity guarantees Epic+ on the 100th spin and resets on any Epic+"] = function()
		local Roll, Config = load()
		local PityAt = Config.Ults.Roll.PityAt
		H.expect(PityAt == 100, "the 100th spin")
		-- The worst luck: every spin lands on the first ult (Eagle's Eye, Common: the ladder's
		-- first since the abilities rework, 2026-10-08).
		local pity = 0
		for spin = 1, PityAt - 1 do
			local id, rarity, newPity, wasPity = Roll.roll("Normal", pity, always(0), true)
			H.expect(id == "EaglesEye" and rarity == "Common" and not wasPity, "spin " .. spin)
			H.expect(newPity == pity + 1, "pity counts every spin")
			pity = newPity
		end
		H.expect(pity == PityAt - 1, "99 without an Epic")
		local _, rarity, newPity, wasPity = Roll.roll("Normal", pity, always(0), true)
		H.expect(Roll.isEpicPlus(rarity) and wasPity, "the 100th is Epic+")
		H.expect(newPity == 0, "and resets")
		-- Every pity spin is Epic+, whatever the rng says.
		local rng = Roll.seeded(7)
		for _ = 1, 5000 do
			local _, r, p, was = Roll.roll("Normal", PityAt - 1, rng, true)
			H.expect(Roll.isEpicPlus(r) and p == 0 and was, "guaranteed")
		end
		-- Any Epic+ resets it early; a Lucky Spin counts too.
		local _, top, early = Roll.roll("Normal", 12, always(0.9999999), true)
		H.expect(top == "Mythic" and early == 0, "a Mythic at 12 resets")
		local _, lucky, afterLucky = Roll.roll("Lucky", 12, always(0), true)
		H.expect(lucky == "Uncommon" and afterLucky == 13, "Lucky counts")
		-- A broken pity counts as 0; a huge one is a pity spin.
		local _, _, fromBad = Roll.roll("Normal", -5, always(0), true)
		H.expect(fromBad == 1, "a negative pity counts from 0")
		local _, huge = Roll.roll("Normal", 1e9, always(0), true)
		H.expect(Roll.isEpicPlus(huge), "clamped to the pity spin")
	end,

	["the pity odds keep the normal table's Epic+ proportions"] = function()
		local Roll = load()
		local odds = Roll.pityOdds(true)
		H.near(rarityPpm(odds, "Epic") / 10000, 72.3, 0.05, "Epic 72.3%")
		H.near(rarityPpm(odds, "Legendary") / 10000, 24.1, 0.05, "Legendary 24.1%")
		H.near(rarityPpm(odds, "Mythic") / 10000, 3.6, 0.05, "Mythic 3.6%")
		for _, rarity in { "Common", "Uncommon", "Rare" } do
			H.expect(rarityPpm(odds, rarity) == 0, rarity .. " never")
		end
		H.expect(Roll.isEpicPlus("Epic") and Roll.isEpicPlus("Mythic"), "Epic+")
		H.expect(not Roll.isEpicPlus("Rare") and not Roll.isEpicPlus("x"), "not Epic+")
	end,

	["a Lucky Spin never rolls Common"] = function()
		local Roll, Config, Catalog = load()
		local odds = Roll.odds("Lucky", true)
		H.expect(rarityPpm(odds, "Common") == 0, "no Common share")
		for _, id in Catalog.byRarity("Common") do
			H.expect((ultPpm(odds, id) or 0) == 0, id .. " never")
		end
		local rng = Roll.seeded(99)
		local counts: { [string]: number } = {}
		local n = 200000
		for _ = 1, n do
			local _, rarity = Roll.roll("Lucky", 0, rng, true)
			H.expect(rarity ~= "Common", "never Common")
			counts[rarity] = (counts[rarity] or 0) + 1
		end
		for _, rarity in Config.Ults.Rarities do
			local p = Config.Ults.Roll.Lucky[rarity] / 1000000
			H.near(counts[rarity] or 0, n * p, tolerance(n, p), "Lucky " .. rarity)
		end
	end,

	["without the flag only built ults roll, and empty shares move down"] = function()
		local Roll, Config = load()
		-- A fixed catalog: only EaglesEye built (the abilities are switched on one by one).
		local only = {}
		for _, id in Config.Ults.Order do
			only[id] = id == "EaglesEye"
		end
		withBuilt(Config, only, function()
			local pool = Roll.pool(false)
			H.expect(
				#pool == 1 and pool[1] == "EaglesEye",
				"only EaglesEye built: only EaglesEye rolls"
			)
			H.expect(#Roll.pool(true) == #Config.Ults.Order, "the flag: all 13")
			local odds = Roll.odds("Normal", false)
			H.expect(
				#odds.ults == 1 and ultPpm(odds, "EaglesEye") == 1000000,
				"Normal: 100% EaglesEye"
			)
			H.expect(rarityPpm(odds, "Common") == 1000000, "every share moved down to Common")
			-- Lucky never lands a Common, so with only EaglesEye built it is closed (audit M3).
			H.expect(
				Roll.available("Normal", false) and not Roll.available("Lucky", false),
				"closed"
			)
			H.expect(sum(Roll.odds("Lucky", false).ults) == 0, "Lucky: nothing to land")
			local ok = pcall(Roll.roll, "Lucky", 0, Roll.seeded(1), false)
			H.expect(not ok, "a closed Lucky Spin never hands out a Common")
			local pity = Roll.pityOdds(false)
			H.expect(ultPpm(pity, "EaglesEye") == 1000000, "no Epic+ built: the normal odds")
			local id, _, newPity, wasPity = Roll.roll("Normal", 99, Roll.seeded(3), false)
			H.expect(id == "EaglesEye" and not wasPity and newPity == 99, "no pity without Epic+")

			-- A Rare built too: Uncommon moves down to Common, Epic+ down to Rare.
			withBuilt(Config, { Portals = true }, function()
				local R = Config.Ults.Roll.Normal
				local odds = Roll.odds("Normal", false)
				H.expect(ultPpm(odds, "EaglesEye") == R.Common + R.Uncommon, "Common + Uncommon")
				H.expect(
					ultPpm(odds, "Portals") == R.Rare + R.Epic + R.Legendary + R.Mythic,
					"Rare + Epic + Legendary + Mythic"
				)
				H.expect(
					rarityPpm(odds, "Uncommon") == 0 and rarityPpm(odds, "Mythic") == 0,
					"empty"
				)
				H.expect(ultPpm(odds, "Magnet") == nil, "not in the pool")
				-- Lucky: Uncommon's share moves up to Portals, never down to a Common.
				local lucky = Roll.odds("Lucky", false)
				H.expect((ultPpm(lucky, "EaglesEye") or 0) == 0, "no Commons from a Lucky Spin")
				H.expect(ultPpm(lucky, "Portals") == 1000000, "every Lucky share to the only Rare")
			end)
			-- Nothing below: a share moves up to the nearest rarity that has an ult.
			withBuilt(Config, { EaglesEye = false, Portals = true }, function()
				local odds = Roll.odds("Normal", false)
				H.expect(ultPpm(odds, "Portals") == 1000000, "everything to the only Rare")
			end)
			-- Pity with one Epic+ built: all of the pity odds go to it.
			withBuilt(Config, { TimeStop = true }, function()
				local odds = Roll.pityOdds(false)
				H.expect(ultPpm(odds, "TimeStop") == 1000000, "all to Time Stop")
				local got, rarity, p, was = Roll.roll("Normal", 99, Roll.seeded(5), false)
				H.expect(got == "TimeStop" and rarity == "Epic" and p == 0 and was, "the pity spin")
			end)
		end)
	end,

	["the same seed gives the same rolls"] = function()
		local Roll = load()
		local function sequence(seed: number): { string }
			local rng = Roll.seeded(seed)
			local out = {}
			local pity = 0
			for i = 1, 2000 do
				local id, _, newPity =
					Roll.roll(if i % 3 == 0 then "Lucky" else "Normal", pity, rng, true)
				pity = newPity
				table.insert(out, id)
			end
			return out
		end
		local a, b, c = sequence(42), sequence(42), sequence(43)
		H.expect(table.concat(a, ",") == table.concat(b, ","), "same seed, same results")
		H.expect(table.concat(a, ",") ~= table.concat(c, ","), "another seed differs")
		local rng = Roll.seeded(0)
		for _ = 1, 1000 do
			local r = rng()
			H.expect(r >= 0 and r < 1, "[0, 1), even from seed 0")
		end
	end,

	["a broken rng is refused"] = function()
		local Roll = load()
		for _, bad in { 1, -0.1, 0 / 0, 2 } do
			local ok = pcall(Roll.roll, "Normal", 0, always(bad), true)
			H.expect(not ok, "rng " .. tostring(bad))
		end
	end,
}
