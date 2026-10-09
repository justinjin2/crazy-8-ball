--!strict
-- BlockDrop: the Mystery block's tier roll and the win's block (economy v4, 2026-10-08, plan
-- sections 3 and 5). A real win moves the day's win track and gives its step's block (the
-- first win ever a Rare block); when any Mystery block opens, the server rolls its tier by
-- Config.BlockOdds.Drop.Weights with pity, then rolls that tier's odds row. This module is the
-- tier roll, the pity counters, the per-drop rarity chances the odds panels show, the presses'
-- path, and the rule that says whether a win gives a block at all (the anti-farm rules,
-- ECONOMY 3.6).
--
-- Pure: no Instances, no clocks, no randomness of its own (the caller passes rng(n) -> 1..n).
-- Every list walks Config.BlockOdds.Order or Rarities, never hash order.
local Config = require(script.Parent.Parent.Config)
local BlockOdds = require(script.Parent.BlockOdds)
local Catalog = require(script.Parent.Catalog)

local C = Config.BlockOdds
local D = C.Drop
local E = Config.Economy
local WEIGHTS: { [string]: number } = D.Weights :: any
local WIN_TRACK: { string } = D.WinTrack :: any

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
	-- The day's win track steps already given (Daily.Track; Config.BlockOdds.Drop.WinTrack).
	-- nil counts as 0.
	trackToday: number?,
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

-- The tier weights with pity's floor (Rare or Epic) applied: every tier below it rolls as it
-- (BlockDrop.roll), so their weights move into it. No floor: Config's weights.
local function weightsWith(floor: string?): { [string]: number }
	local weights: { [string]: number } = {}
	local floorRank = if floor ~= nil then RANK[floor] else nil
	for _, id in C.Order do
		local weight = WEIGHTS[id] or 0
		if floorRank ~= nil and RANK[id] < floorRank then
			weights[floor :: string] = (weights[floor :: string] or 0) + weight
		else
			weights[id] = (weights[id] or 0) + weight
		end
	end
	return weights
end

--- The tier pity guarantees for the next Mystery block, from the drops left until each
--- guarantee (BlockDrop.pityLeft or ShopView's `pity`): "Epic" or "Rare" when the next one is
--- guaranteed, else nil. The odds screen shows it and the live odds while it is due (Roblox's
--- rules; economy v4 plan 3.3).
function BlockDrop.floorOf(left: any): string?
	local t = if type(left) == "table" then left else {}
	if type(t.epic) == "number" and t.epic <= 1 then
		return "Epic"
	elseif type(t.rare) == "number" and t.rare <= 1 then
		return "Rare"
	end
	return nil
end

--- The tiers with their weights and percents, Standard first. `floor` (BlockDrop.floorOf):
--- the live odds while pity guarantees that tier (the tiers under it are left out).
function BlockDrop.tiers(floor: string?): { TierOdds }
	local list = {}
	local weights = weightsWith(floor)
	for _, id in C.Order do
		local weight = weights[id] or 0
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
--- float rounding). The cue cards show these ("EPIC · 0.327%"). `floor`: the live odds while
--- pity guarantees that tier (BlockDrop.floorOf).
function BlockDrop.rarityOdds(floor: string?): { RarityOdds }
	local list = {}
	local total = C.OddsTotal
	local weights = weightsWith(floor)
	for _, rarity in C.Rarities do
		local parts = 0
		for _, id in C.Order do
			local row = BlockOdds.get(id)
			if row then
				parts += (weights[id] or 0) * (row.Odds[rarity] or 0)
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

-- Each cue's chance per Mystery block (summed over the tier blocks that can give it) and each
-- rarity's cue ids in the catalog's order.
local function cueChances(floor: string?): ({ [string]: number }, { [string]: { string } })
	local weights = weightsWith(floor)
	local chance: { [string]: number } = {}
	local byRarity: { [string]: { string } } = {}
	for _, id in C.Order do
		local share = (weights[id] or 0) / C.OddsTotal
		if share > 0 then
			for _, entry in BlockOdds.odds(id) do
				local pool = Catalog.droppable(id, entry.rarity)
				for _, cue in pool do
					if chance[cue.Id] == nil then
						chance[cue.Id] = 0
						local ids = byRarity[entry.rarity] or {}
						byRarity[entry.rarity] = ids
						table.insert(ids, cue.Id)
					end
					chance[cue.Id] += share * entry.percent / #pool
				end
			end
		end
	end
	return chance, byRarity
end

--- Each rarity's chance per Mystery block with its cues (Roblox's rules: every final item
--- with its chance; the Mystery block is nested, a tier block and then a cue): bottom rarity
--- first, the cues in the catalog's order. Each cue's chance is summed over the tier blocks
--- that can give it; `each` is the group's chance over its cues (every tier block splits a
--- rarity evenly among the same cues, so they are equal: the tests hold that). `floor`: the
--- live odds while pity guarantees that tier (BlockDrop.floorOf).
function BlockDrop.cueGroups(floor: string?): { BlockOdds.CueGroup }
	local chance, byRarity = cueChances(floor)
	local groups: { BlockOdds.CueGroup } = {}
	for _, rarity in C.Rarities do
		local ids = byRarity[rarity]
		if ids and #ids > 0 then
			local percent = 0
			for _, cue in ids do
				percent += chance[cue]
			end
			table.insert(groups, {
				rarity = rarity,
				percent = percent,
				each = percent / #ids,
				cues = ids,
				closed = false,
			})
		end
	end
	return groups
end

--- Each cue's chance per Mystery block, by id (what BlockDrop.cueGroups sums), for the tests.
function BlockDrop.cueChances(floor: string?): { [string]: number }
	return (cueChances(floor))
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
-- The upgrade screen's path (Config.BlockOdds.Drop.Upgrade; economy v4 plan 3.2)
---------------------------------------------------------------------------------------------

local UP = D.Upgrade
local CHANCE: { [string]: number } = UP.Chances :: any

--- The tier the first press shows for a block that ends on `final`: the block is a Mystery
--- block on screen until that press, and the later Clicks - 1 presses can each climb one tier,
--- so it starts as low as it can (Standard for Epic and below; one tier above Standard for each
--- climb the later presses can't make: Uncommon for a Legendary, Rare for a Mythic).
function BlockDrop.startOf(final: string): string
	assert(RANK[final] ~= nil, "BlockDrop.startOf: unknown tier " .. tostring(final))
	return C.Order[math.max(1, RANK[final] - (UP.Clicks - 1))]
end

--- The first press's chance of each tier (0..1): each final tier's weight on its start
--- (BlockDrop.startOf).
function BlockDrop.firstOdds(): { [string]: number }
	local first: { [string]: number } = {}
	for _, tier in C.Order do
		first[tier] = 0
	end
	for _, tier in C.Order do
		local start = BlockDrop.startOf(tier)
		first[start] += (WEIGHTS[tier] or 0) / C.OddsTotal
	end
	return first
end

--- The tiers a Mystery block shows press by press on the upgrade screen, ending on `final`
--- (the tier BlockDrop.roll gave): Clicks tiers. The first press turns the Mystery block into
--- its start (BlockDrop.startOf); a block that ends `k` tiers above its start climbs one tier on
--- exactly `k` of the later presses, which ones picked with every choice equally likely. A
--- climb never fizzles or falls back. `rng(n)` returns 1..n.
function BlockDrop.path(final: string, rng: (number) -> number): { string }
	assert(RANK[final] ~= nil, "BlockDrop.path: unknown tier " .. tostring(final))
	local clicks = UP.Clicks
	local at = RANK[BlockDrop.startOf(final)]
	local left = RANK[final] - at
	local tiers = table.create(clicks, C.Order[at])
	for press = 2, clicks do
		-- Selection sampling: climb with chance (climbs left) / (presses left), which picks
		-- each set of `k` presses equally often.
		if left > 0 and rng(clicks - press + 1) <= left then
			at += 1
			left -= 1
		end
		tiers[press] = C.Order[at]
	end
	return tiers
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
	if type(UP.Clicks) ~= "number" or UP.Clicks < 2 or UP.Clicks ~= math.floor(UP.Clicks) then
		table.insert(problems, "Drop.Upgrade.Clicks must be a whole number of at least 2")
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
-- The win's block: the daily win track (v4 plan section 5; ECONOMY 3.6)
---------------------------------------------------------------------------------------------

--- How many steps the daily win track has (#Config.BlockOdds.Drop.WinTrack).
function BlockDrop.trackSteps(): number
	return #WIN_TRACK
end

--- The block kind of win track step `step` (1..trackSteps()), or nil past the track.
function BlockDrop.trackKind(step: number): string?
	return WIN_TRACK[step]
end

--- The block kind a win that moves the track gives: the first win ever's FirstWin block,
--- else the next step's block (`trackToday` steps given today). nil past the track.
function BlockDrop.winKind(trackToday: number, firstWinEver: boolean): string?
	local step = whole(trackToday) + 1
	if step > #WIN_TRACK then
		return nil
	end
	return if firstWinEver then D.FirstWin else WIN_TRACK[step]
end

--- Whether this win moves the day's win track (and gives its step's block), and that block's
--- kind (the first win ever's FirstWin block, else the step's). Every real win does, except:
--- a loss, solo, a match that was not real, the track already done today (trackSteps() steps),
--- a same-opponent row that forbids it, DropsPerOpponent blocks from this account today
--- already, a loser with fewer than DropLoserMinMatches real matches (the anti-farm rules apply
--- to the first win too), or Play against PC past PcDropsPerDay blocks today.
function BlockDrop.dropFor(ctx: DropContext): (boolean, string?)
	if not ctx.won or not ctx.real or ctx.solo then
		return false, nil
	end
	local kind = BlockDrop.winKind(ctx.trackToday or 0, ctx.firstWinEver)
	if kind == nil then
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
	return true, kind
end

return BlockDrop
