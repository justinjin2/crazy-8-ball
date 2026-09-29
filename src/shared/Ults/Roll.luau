--!strict
-- Ult spins (docs/prompts/ULTIMATES_PROMPT.md section 8): the roll pool, the true current
-- odds, pity and Lucky Spins. Pure: no Instances, no Roblox APIs, no clocks and no randomness
-- of its own. The caller passes `rng`, a function returning a number in [0, 1): the server
-- builds one on Roblox's Random, the tests use `Roll.seeded(seed)`. Every list is walked in
-- Config.Ults.Rarities or Config.Ults.Order, never hash order.
--
-- Odds are whole parts per million (ppm) and every table adds to exactly 1,000,000
-- (Roll.TOTAL). Config.Ults.Roll gives each rarity's share. The pool is the built ults (all 13
-- with the developer flag `devAll`); a rarity with no ult in the pool passes its whole share
-- down to the next rarity below that has one (or, with none below, up to the nearest above), so
-- the Odds panel shows what a spin really does. A Lucky Spin never passes a share below its
-- lowest rarity with a share of its own (Uncommon): "no Commons" holds whatever is built, and
-- with no Uncommon or better ult in the pool a Lucky Spin cannot be made (Roll.available). A rarity's share is split evenly between its
-- ults; the ppm left over by the split goes one each to its first ults in Order.
--
-- Pity: every spin (free, paid, normal or Lucky) adds 1; the Config.Ults.Roll.PityAt-th spin
-- without an Epic or better uses the pity odds (Epic+ only, in the normal table's proportions),
-- and any Epic+ result resets it to 0.
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)

local U = Config.Ults
local R = U.Roll

local Roll = {}

Roll.TOTAL = 1000000 -- every odds table adds to exactly this many parts per million

export type Kind = "Normal" | "Lucky"
export type RarityOdds = { rarity: string, ppm: number }
export type UltOdds = { id: string, rarity: string, ppm: number }
export type Odds = {
	rarities: { RarityOdds }, -- every rarity in ladder order, 0 where it cannot come up
	ults: { UltOdds }, -- every ult in the pool, in Config.Ults.Order
}

local TABLES: { [string]: { [string]: number } } =
	{ Normal = R.Normal :: any, Lucky = R.Lucky :: any }

--- True for a rarity of Config.Ults.Roll.PityFrom (Epic) or better.
function Roll.isEpicPlus(rarity: any): boolean
	return Catalog.rarityIndex(rarity) >= Catalog.rarityIndex(R.PityFrom)
end

--- The ult ids a spin can land on, in Config.Ults.Order: the built ones, or all of them with
--- the developer flag.
function Roll.pool(devAll: boolean?): { string }
	local pool: { string } = {}
	for _, id in Catalog.list() do
		if Catalog.usable(id, devAll) then
			table.insert(pool, id)
		end
	end
	return pool
end

-- The pool grouped by rarity: rarity -> its ids in Order.
local function poolByRarity(devAll: boolean?): { [string]: { string } }
	local by: { [string]: { string } } = {}
	for _, rarity in U.Rarities do
		by[rarity] = {}
	end
	for _, id in Roll.pool(devAll) do
		table.insert(by[Catalog.rarity(id) :: string], id)
	end
	return by
end

-- Moves each empty rarity's share (at ladder index `from` or above) to the next rarity below
-- it (down to `from`) that has an ult in the pool, or else to the nearest above that has one.
-- A share with nowhere to go is dropped. Returns rarity -> share.
local function moveShares(
	base: { [string]: number },
	by: { [string]: { string } },
	from: number
): { [string]: number }
	local rarities = U.Rarities
	local out: { [string]: number } = {}
	for _, rarity in rarities do
		out[rarity] = 0
	end
	for index = from, #rarities do
		local share = math.max(0, base[rarities[index]] or 0)
		if share > 0 then
			local target: string? = nil
			for down = index, from, -1 do
				if #by[rarities[down]] > 0 then
					target = rarities[down]
					break
				end
			end
			if target == nil then
				for up = index + 1, #rarities do
					if #by[rarities[up]] > 0 then
						target = rarities[up]
						break
					end
				end
			end
			if target ~= nil then
				out[target] += share
			end
		end
	end
	return out
end

-- Scales shares to exactly Roll.TOTAL by the largest remainder (ties to the lower rarity), so a
-- table whose shares already add to the total comes back unchanged.
local function scale(shares: { [string]: number }): { [string]: number }
	local total = 0
	for _, rarity in U.Rarities do
		total += shares[rarity]
	end
	local out: { [string]: number } = {}
	if total <= 0 then
		for _, rarity in U.Rarities do
			out[rarity] = 0
		end
		return out
	end
	local given = 0
	local remainders: { { rarity: string, rest: number, index: number } } = {}
	for index, rarity in U.Rarities do
		local exact = shares[rarity] * Roll.TOTAL
		local whole = exact // total
		out[rarity] = whole
		given += whole
		if shares[rarity] > 0 then
			table.insert(
				remainders,
				{ rarity = rarity, rest = exact - whole * total, index = index }
			)
		end
	end
	table.sort(remainders, function(a, b)
		if a.rest ~= b.rest then
			return a.rest > b.rest
		end
		return a.index < b.index
	end)
	local i = 1
	while given < Roll.TOTAL and #remainders > 0 do
		out[remainders[i].rarity] += 1
		given += 1
		i = i % #remainders + 1
	end
	return out
end

-- The odds table for rarity shares (already moved and scaled) over the pool.
local function build(shares: { [string]: number }, by: { [string]: { string } }): Odds
	local rarities: { RarityOdds } = {}
	local perRarity: { [string]: { UltOdds } } = {}
	for _, rarity in U.Rarities do
		local share = shares[rarity]
		table.insert(rarities, { rarity = rarity, ppm = share })
		local ids = by[rarity]
		local list: { UltOdds } = {}
		if #ids > 0 then
			local each = share // #ids
			local left = share - each * #ids
			for i, id in ids do
				table.insert(
					list,
					{ id = id, rarity = rarity, ppm = each + (if i <= left then 1 else 0) }
				)
			end
		end
		perRarity[rarity] = list
	end
	-- The ults in catalog Order.
	local ults: { UltOdds } = {}
	local lookup: { [string]: UltOdds } = {}
	for _, rarity in U.Rarities do
		for _, row in perRarity[rarity] do
			lookup[row.id] = row
		end
	end
	for _, id in Catalog.list() do
		local row = lookup[id]
		if row ~= nil then
			table.insert(ults, row)
		end
	end
	return { rarities = rarities, ults = ults }
end

-- Odds tables already built, by what they depend on: the kind and which ults are in the pool
-- (a bitmask over Config.Ults.Order), so a roll does not rebuild them. An ult marked built at
-- runtime (a test) changes the mask and builds a new entry. Config's shares are read when an
-- entry is built; they are constants.
type Cached = { odds: Odds, pity: boolean }
local cache: { [string]: Cached } = {}

local function cacheKey(name: string, devAll: boolean?): string
	local mask = 0
	for i, id in U.Order do
		if Catalog.usable(id, devAll) then
			mask += 2 ^ (i - 1)
		end
	end
	return name .. mask
end

-- The (cached, never changed) odds of a normal or Lucky spin.
local function kindTable(kind: any, devAll: boolean?): Odds
	local name = if kind == "Lucky" then "Lucky" else "Normal"
	local base = TABLES[name]
	local key = cacheKey(name, devAll)
	local hit = cache[key]
	if hit == nil then
		local by = poolByRarity(devAll)
		-- Shares move no lower than the table's lowest rarity with a share (Lucky: Uncommon).
		local from = 1
		for index, rarity in U.Rarities do
			if (base[rarity] or 0) > 0 then
				from = index
				break
			end
		end
		hit = { odds = build(scale(moveShares(base, by, from)), by), pity = false }
		cache[key] = hit
	end
	return hit.odds
end

-- The (cached) pity spin's odds, and whether they are really pity odds (false: no Epic+ ult is
-- in the pool, so they fell back to the normal odds).
local function pityTable(devAll: boolean?): (Odds, boolean)
	local key = cacheKey("Pity", devAll)
	local hit = cache[key]
	if hit == nil then
		local by = poolByRarity(devAll)
		local from = Catalog.rarityIndex(R.PityFrom)
		local any = false
		for index = from, #U.Rarities do
			if #by[U.Rarities[index]] > 0 then
				any = true
			end
		end
		if any then
			hit = { odds = build(scale(moveShares(TABLES.Normal, by, from)), by), pity = true }
		else
			hit = { odds = kindTable("Normal", devAll), pity = false }
		end
		cache[key] = hit
	end
	return hit.odds, hit.pity
end

-- A copy of an odds table for callers (the cached one is never handed out).
local function copy(odds: Odds): Odds
	local rarities: { RarityOdds } = {}
	for _, row in odds.rarities do
		table.insert(rarities, { rarity = row.rarity, ppm = row.ppm })
	end
	local ults: { UltOdds } = {}
	for _, row in odds.ults do
		table.insert(ults, { id = row.id, rarity = row.rarity, ppm = row.ppm })
	end
	return { rarities = rarities, ults = ults }
end

--- The true current odds of a "Normal" or "Lucky" spin (anything else is read as "Normal"),
--- after empty rarities pass their shares on. Every rarity is listed (ppm 0 where it cannot
--- come up) and every ult in the pool; both lists add to exactly Roll.TOTAL. A new table.
function Roll.odds(kind: any, devAll: boolean?): Odds
	return copy(kindTable(kind, devAll))
end

--- Whether a "Normal" or "Lucky" spin can be made at all: false when no ult in the pool can
--- come up (a Lucky Spin while no Uncommon or better ult is built). Roll.roll errors then.
function Roll.available(kind: any, devAll: boolean?): boolean
	for _, row in kindTable(kind, devAll).ults do
		if row.ppm > 0 then
			return true
		end
	end
	return false
end

--- The pity spin's odds: Epic+ only, in the normal table's proportions (Epic 72.3%, Legendary
--- 24.1%, Mythic 3.6%), shares of empty Epic+ rarities moved as in `Roll.odds`. With no Epic+
--- ult in the pool it is the normal odds. A new table.
function Roll.pityOdds(devAll: boolean?): Odds
	return copy((pityTable(devAll)))
end

--- True when a spin made with `pity` spins already without an Epic+ uses the pity odds.
function Roll.isPitySpin(pity: number): boolean
	return pity + 1 >= R.PityAt
end

-- `pity` made a whole number in 0..PityAt-1 (a broken value counts as 0).
local function cleanPity(pity: any): number
	if type(pity) ~= "number" or pity ~= pity or pity == math.huge or pity == -math.huge then
		return 0
	end
	return math.clamp(math.floor(pity), 0, R.PityAt - 1)
end

--- One spin. `kind` is "Normal" or "Lucky"; `pity` the spins since the last Epic+ (the save's
--- Ults.Pity); `rng()` a number in [0, 1). Returns the ult id, its rarity, the new pity (0 after
--- any Epic+, else pity + 1, never past PityAt - 1) and whether this spin used the pity odds.
--- Errors on an rng out of range or an empty pool (the default ult is always built), so a
--- broken roll never quietly hands something out; the server rolls before it takes the spin.
function Roll.roll(
	kind: any,
	pity: any,
	rng: () -> number,
	devAll: boolean?
): (string, string, number, boolean)
	local before = cleanPity(pity)
	local odds: Odds
	local wasPity = false
	if Roll.isPitySpin(before) then
		odds, wasPity = pityTable(devAll)
	else
		odds = kindTable(kind, devAll)
	end
	local any = false
	for _, row in odds.ults do
		any = any or row.ppm > 0
	end
	assert(any, "Roll.roll: nothing can come up (an empty pool, or a Lucky Spin with no Uncommon+)")
	local r = rng()
	assert(type(r) == "number" and r >= 0 and r < 1, "Roll.roll: rng out of range")
	local pick = math.floor(r * Roll.TOTAL) + 1 -- 1..TOTAL
	local reached = 0
	local chosen = odds.ults[#odds.ults]
	for _, row in odds.ults do
		reached += row.ppm
		if pick <= reached then
			chosen = row
			break
		end
	end
	local newPity = if Roll.isEpicPlus(chosen.rarity) then 0 else math.min(before + 1, R.PityAt - 1)
	return chosen.id, chosen.rarity, newPity, wasPity
end

--- A deterministic generator for tests (xorshift32): returns a function giving numbers in
--- [0, 1), the same sequence for the same seed on every run and machine.
function Roll.seeded(seed: number): () -> number
	local state = math.floor(math.abs(seed)) % 4294967296
	if state == 0 then
		state = 0x9E3779B9 -- xorshift is stuck at 0
	end
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

return Roll
