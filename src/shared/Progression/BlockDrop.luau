--!strict
-- BlockDrop: the tier roll behind a win's lucky block (the approved economy plan, 2026-10-02,
-- section 2, moved onto lucky blocks 2026-10-04). Every real win gives a Mystery lucky block
-- (the first win ever a Rare block); when a free Mystery block opens, the server rolls its tier
-- by Config.BlockOdds.Drop.Weights with pity, then rolls that tier's odds row. This module is
-- the tier roll, the pity counters, the per-drop rarity chances the odds panels show, and the
-- rule that says whether a win drops a block at all (the anti-farm rules, ECONOMY 3.6).
--
-- Pure: no Instances, no clocks, no randomness of its own (the caller passes rng(n) -> 1..n).
-- Every list walks Config.BlockOdds.Order or Rarities, never hash order.
local Config = require(script.Parent.Parent.Config)
local BlockOdds = require(script.Parent.BlockOdds)

local C = Config.BlockOdds
local D = C.Drop
local E = Config.Economy
local WEIGHTS: { [string]: number } = D.Weights :: any

-- The drop counters the save keeps (save.Drops): drops in a row without a Rare-or-better tier
-- and without an Epic-or-better tier, and every drop ever.
export type Pity = { SinceRare: number, SinceEpic: number, Total: number }

export type TierOdds = { tier: string, weight: number, percent: number, display: string }
export type RarityOdds = { rarity: string, percent: number, display: string }

-- What the drop rule needs to know about a settled match, for one winner.
export type DropContext = {
	real: boolean, -- a real match: past the one-minute mark, not a quick forfeit (people or PC)
	solo: boolean,
	won: boolean,
	-- Play against PC (the PC money rows): drops only for the first Config.Economy
	-- .PcDropsPerDay such wins a UTC day (`pcDropsToday` so far).
	pcLimited: boolean,
	pcDropsToday: number,
	farmAllows: boolean, -- the Config.Economy.SameOpponent row's Drop for this pairing
	dropsFromOpponentToday: number, -- blocks already won from this account today
	loserRealMatches: number, -- the loser's real matches (a PC: any large number)
	-- True while the player has never been given the first win's block. The server may keep
	-- this true until that block actually drops, so a first win blocked by an anti-farm rule
	-- does not use it up.
	firstWinEver: boolean,
}

local BlockDrop = {}

local RANK: { [string]: number } = {}
for i, id in C.Order do
	RANK[id] = i
end

local function whole(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return 0
	end
	return math.floor(value)
end

--- A tier's place on the ladder (Standard 1 .. Mythic 6), 0 for anything else.
function BlockDrop.rank(tier: any): number
	return RANK[tier] or 0
end

--- The tiers with their weights and percents, Standard first.
function BlockDrop.tiers(): { TierOdds }
	local list = {}
	for _, id in C.Order do
		local weight = WEIGHTS[id] or 0
		if weight > 0 then
			local percent = weight * 100 / C.OddsTotal
			table.insert(list, {
				tier = id,
				weight = weight,
				percent = percent,
				display = BlockOdds.percentText(percent),
			})
		end
	end
	return list
end

--- Each rarity's chance per Mystery block (pity aside): the tier weights times each row's
--- odds. Bottom rarity first, only rarities that can drop; the percents add to 100 (within
--- float rounding). The cue cards show these ("EPIC · 0.138%").
function BlockDrop.rarityOdds(): { RarityOdds }
	local list = {}
	local total = C.OddsTotal
	for _, rarity in C.Rarities do
		local parts = 0
		for _, id in C.Order do
			local row = BlockOdds.get(id)
			if row then
				parts += (WEIGHTS[id] or 0) * (row.Odds[rarity] or 0)
			end
		end
		if parts > 0 then
			local percent = parts * 100 / (total * total)
			table.insert(list, {
				rarity = rarity,
				percent = percent,
				display = BlockOdds.percentText(percent),
			})
		end
	end
	return list
end

--- One rarity's chance per Mystery block in percent (0 for a rarity no row drops).
function BlockDrop.rarityPercent(rarity: string): number
	for _, entry in BlockDrop.rarityOdds() do
		if entry.rarity == rarity then
			return entry.percent
		end
	end
	return 0
end

--- The save's counters read as whole numbers (anything missing or broken is 0).
function BlockDrop.readPity(drops: any): Pity
	local t = if type(drops) == "table" then drops else {}
	return {
		SinceRare = whole(t.SinceRare),
		SinceEpic = whole(t.SinceEpic),
		Total = whole(t.Total),
	}
end

--- Drops left until a Rare and an Epic tier are guaranteed (1: the next drop is).
function BlockDrop.pityLeft(pity: Pity): { rare: number, epic: number }
	return {
		rare = math.max(D.PityRare - pity.SinceRare, 1),
		epic = math.max(D.PityEpic - pity.SinceEpic, 1),
	}
end

--- Rolls one tier: (tier, the counters after it). `forced` skips the roll. Otherwise the
--- weights pick a tier, then pity raises it: to Epic on the PityEpic-th drop in a row without
--- an Epic-or-better tier, else to Rare on the PityRare-th without a Rare-or-better. Every
--- drop counts, forced ones too. `rng(n)` returns 1..n.
function BlockDrop.roll(pity: Pity, rng: (number) -> number, forced: string?): (string, Pity)
	local tier: string
	if forced ~= nil then
		assert(RANK[forced] ~= nil, "BlockDrop.roll: unknown tier " .. tostring(forced))
		tier = forced
	else
		local pick = rng(C.OddsTotal)
		assert(
			pick >= 1 and pick <= C.OddsTotal and pick == math.floor(pick),
			"BlockDrop.roll: rng out of range"
		)
		local reached = 0
		tier = C.Order[#C.Order]
		for _, id in C.Order do
			reached += WEIGHTS[id] or 0
			if pick <= reached then
				tier = id
				break
			end
		end
		if pity.SinceEpic + 1 >= D.PityEpic and RANK[tier] < RANK.Epic then
			tier = "Epic"
		elseif pity.SinceRare + 1 >= D.PityRare and RANK[tier] < RANK.Rare then
			tier = "Rare"
		end
	end
	local rank = RANK[tier]
	local after: Pity = {
		SinceRare = if rank >= RANK.Rare then 0 else pity.SinceRare + 1,
		SinceEpic = if rank >= RANK.Epic then 0 else pity.SinceEpic + 1,
		Total = pity.Total + 1,
	}
	return tier, after
end

---------------------------------------------------------------------------------------------
-- The upgrade screen's path (Config.BlockOdds.Drop.Upgrade, designer 2026-10-07)
---------------------------------------------------------------------------------------------

local UP = D.Upgrade
local CHANCE: { [string]: number } = UP.Chances :: any

-- A press's chance to raise `tier` one step (0 at the top of the ladder).
local function upChance(tier: string): number
	if RANK[tier] >= #C.Order then
		return 0
	end
	return (CHANCE[tier] or 0) / C.OddsTotal
end

-- Every way Clicks presses can go: { tiers, weight } where weight is the chance of the
-- starting tier (from `first`) times each later press's stay-or-raise chance.
local function allPaths(first: { [string]: number }): { { tiers: { string }, weight: number } }
	local paths = {}
	local function walk(tiers: { string }, weight: number)
		if weight <= 0 then
			return
		end
		if #tiers == UP.Clicks then
			table.insert(paths, { tiers = table.clone(tiers), weight = weight })
			return
		end
		local at = tiers[#tiers]
		local up = upChance(at)
		table.insert(tiers, at)
		walk(tiers, weight * (1 - up))
		table.remove(tiers)
		if up > 0 then
			table.insert(tiers, C.Order[RANK[at] + 1])
			walk(tiers, weight * up)
			table.remove(tiers)
		end
	end
	for _, tier in C.Order do
		walk({ tier }, first[tier] or 0)
	end
	return paths
end

local firstCache: { [string]: number }? = nil

--- The first press's chance of each tier (0..1), the one that makes the chain's final tier
--- match Drop.Weights exactly (solved from the top of the ladder down; a tier the chain can
--- only reach by upgrading gets 0).
function BlockDrop.firstOdds(): { [string]: number }
	if firstCache then
		return firstCache
	end
	-- reach[i][j]: the chance a block that starts at tier i ends at tier j after the presses.
	local n = #C.Order
	local steps = UP.Clicks - 1
	local reach: { { number } } = {}
	for i = 1, n do
		local row = table.create(n, 0)
		row[i] = 1
		for _ = 1, steps do
			local nextRow = table.create(n, 0)
			for j = 1, n do
				if row[j] > 0 then
					local up = upChance(C.Order[j])
					nextRow[j] += row[j] * (1 - up)
					if up > 0 then
						nextRow[j + 1] += row[j] * up
					end
				end
			end
			row = nextRow
		end
		reach[i] = row
	end
	local first: { [string]: number } = {}
	for j = 1, n do
		local want = (WEIGHTS[C.Order[j]] or 0) / C.OddsTotal
		for i = 1, j - 1 do
			want -= (first[C.Order[i]] or 0) * reach[i][j]
		end
		first[C.Order[j]] = math.max(0, want / reach[j][j])
	end
	firstCache = first
	return first
end

--- The tiers a Mystery block shows press by press on the upgrade screen, ending on `final`
--- (the tier BlockDrop.roll gave): Clicks tiers, never going down, at most one step a press.
--- Picked among every path the chain could take to `final`, by how likely each is, so the
--- presses look exactly like the chain while the final odds stay Drop.Weights with pity.
--- `rng(n)` returns 1..n.
function BlockDrop.path(final: string, rng: (number) -> number): { string }
	assert(RANK[final] ~= nil, "BlockDrop.path: unknown tier " .. tostring(final))
	local ending = {}
	local total = 0
	for _, p in allPaths(BlockDrop.firstOdds()) do
		if p.tiers[#p.tiers] == final then
			table.insert(ending, p)
			total += p.weight
		end
	end
	if total <= 0 then
		-- No path weighs anything (a tier the chain cannot reach): it simply starts there.
		return table.create(UP.Clicks, final)
	end
	local pick = (rng(C.OddsTotal) - 0.5) / C.OddsTotal * total
	for _, p in ending do
		pick -= p.weight
		if pick <= 0 then
			return p.tiers
		end
	end
	return ending[#ending].tiers
end

--- Everything wrong with Config.BlockOdds.Drop, sorted (empty when all is well): weights that
--- are not whole numbers, a tier that is not a ladder row, weights that do not add to
--- OddsTotal, pity limits below 1, or a FirstWin that is not a ladder row.
function BlockDrop.validate(): { string }
	local problems = {}
	local sum = 0
	for tier, weight in WEIGHTS do
		if RANK[tier] == nil then
			table.insert(problems, ("Drop.Weights has %s, not a tier"):format(tostring(tier)))
		end
		if type(weight) ~= "number" or weight < 0 or weight ~= math.floor(weight) then
			table.insert(problems, ("Drop.Weights.%s is not a whole number"):format(tier))
		else
			sum += weight
		end
	end
	if sum ~= C.OddsTotal then
		table.insert(problems, ("Drop.Weights add to %d, not %d"):format(sum, C.OddsTotal))
	end
	if D.PityRare < 1 or D.PityEpic < 1 then
		table.insert(problems, "Drop pity limits must be at least 1")
	end
	if RANK[D.FirstWin] == nil then
		table.insert(problems, ("Drop.FirstWin %s is not a tier"):format(tostring(D.FirstWin)))
	end
	if type(UP.Clicks) ~= "number" or UP.Clicks < 1 or UP.Clicks ~= math.floor(UP.Clicks) then
		table.insert(problems, "Drop.Upgrade.Clicks must be a whole number of at least 1")
	end
	for tier, chance in CHANCE do
		if RANK[tier] == nil or RANK[tier] >= #C.Order then
			table.insert(
				problems,
				("Drop.Upgrade.Chances has %s, not a tier below the top"):format(tostring(tier))
			)
		elseif
			type(chance) ~= "number"
			or chance < 0
			or chance >= C.OddsTotal
			or chance ~= math.floor(chance)
		then
			table.insert(
				problems,
				("Drop.Upgrade.Chances.%s is not a whole part under OddsTotal"):format(tier)
			)
		end
	end
	table.sort(problems)
	return problems
end

do
	local problems = BlockDrop.validate()
	assert(#problems == 0, "Config.BlockOdds.Drop: " .. table.concat(problems, "; "))
end

---------------------------------------------------------------------------------------------
-- The win's block (economy plan sections 1 and 2; ECONOMY 3.6)
---------------------------------------------------------------------------------------------

--- Whether this win drops a lucky block, and the kind it is forced to (the first win's Rare
--- block) or nil for the usual Mystery block. Every real win drops one, except: a loss, solo,
--- a match that was not real, a same-opponent row that forbids it, DropsPerOpponent drops from
--- this account today already, a loser with fewer than DropLoserMinMatches real matches (the
--- anti-farm rules apply to the first win too), or Play against PC past PcDropsPerDay drops
--- today.
function BlockDrop.dropFor(ctx: DropContext): (boolean, string?)
	if not ctx.won or not ctx.real or ctx.solo then
		return false, nil
	end
	if ctx.pcLimited and ctx.pcDropsToday >= E.PcDropsPerDay then
		return false, nil
	end
	if not ctx.farmAllows then
		return false, nil
	end
	if ctx.dropsFromOpponentToday >= E.DropsPerOpponent then
		return false, nil
	end
	if ctx.loserRealMatches < E.DropLoserMinMatches then
		return false, nil
	end
	if ctx.firstWinEver then
		return true, D.FirstWin
	end
	return true, nil
end

return BlockDrop
