--!strict
-- BlockDrop: the climb and the win's block (economy v5, 2026-10-09, plan sections 3 and 4).
-- Every lucky block of a climbing kind climbs from its name (Config.LuckyBlocks.Kinds[kind]
-- .Climb) one step at a time on one ladder (Config.BlockOdds.Climb): the server rolls every
-- step first (climbRoll; the Mystery block's `roll` adds pity), then the climb screen only
-- plays the path (path). The tier a block ends on is its cue's rarity. This module is the
-- climb, the Grand Opening Luck's window, the pity counters, every block's odds lists (the
-- tiers, the rarities and the cues, live during the luck and while pity is due), the presses'
-- path, and the rule that says whether a win moves the daily win track at all (the anti-farm
-- rules, ECONOMY 3.6).
--
-- Pure: no Instances, no clocks (the caller passes `now` or `luck`), no randomness of its own
-- (the caller passes rng(n) -> 1..n). Every list walks Config.BlockOdds.Climb.Tiers or
-- Rarities, never hash order.
local Config = require(script.Parent.Parent.Config)
local BlockOdds = require(script.Parent.BlockOdds)
local Catalog = require(script.Parent.Catalog)

local C = Config.BlockOdds
local D = C.Drop
local CL = C.Climb
local E = Config.Economy
local TIERS: { string } = CL.Tiers
local STEPS: { [string]: number } = CL.Steps :: any
local LUCK_STEPS: { [string]: number } = CL.Luck.Steps :: any
local RARITY: { [string]: string } = CL.Rarity :: any
local WIN_TRACK: { string } = D.WinTrack :: any

-- The drop counters the save keeps (save.Drops): Mystery blocks in a row without a
-- Rare-or-better climb and without an Epic-or-better climb, and every Mystery block ever.
export type Pity = { SinceRare: number, SinceEpic: number, Total: number }

export type TierOdds = { tier: string, weight: number, percent: number, display: string }
export type RarityOdds = { rarity: string, percent: number, display: string }

-- Which climb an odds list is for: `start` the tier it climbs from (nil: Standard, the Mystery
-- block's), `luck` true while the Grand Opening Luck runs (BlockDrop.luckLive).
export type ClimbOpts = { start: string?, luck: boolean? }

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

--- The win track's money step (Config.BlockOdds.Drop.WinTrack): pays WinTrackMoney.
BlockDrop.Money = "Money"

local RANK: { [string]: number } = {}
for i, id in TIERS do
	RANK[id] = i
end
local TOP = #TIERS

local function whole(value: any): number
	if type(value) ~= "number" or value ~= value or value < 0 or value == math.huge then
		return 0
	end
	return math.floor(value)
end

--- A tier's place on the climb ladder (Standard 1 .. Mythic 6, the Secret 7), 0 for anything
--- else.
function BlockDrop.rank(tier: any): number
	return RANK[tier] or 0
end

--- The climb ladder's tiers, bottom first (Config.BlockOdds.Climb.Tiers: the block tiers, then
--- the Secret).
function BlockDrop.ladder(): { string }
	return TIERS
end

--- Whether `tier` is a block tier: a climb that ends there leaves a block of it (every tier but
--- the Secret, which gives its cue at once).
function BlockDrop.isBlockTier(tier: any): boolean
	return type(tier) == "string" and table.find(C.Order, tier) ~= nil
end

--- The cue rarity a climb ending on `tier` gives (a Standard climb: Common), or nil.
function BlockDrop.rarityOf(tier: any): string?
	return RARITY[tier]
end

---------------------------------------------------------------------------------------------
-- The Grand Opening Luck (Config.BlockOdds.Climb.Luck; plan 3.4)
---------------------------------------------------------------------------------------------

--- When the Grand Opening Luck runs (unix seconds, from its deal's StartsAt for Luck.Seconds),
--- or (0, 0) while that StartsAt is 0 (off).
function BlockDrop.luckWindow(): (number, number)
	local deals: any = Config.Shop.Deals
	local deal = deals[CL.Luck.With]
	local startsAt = if type(deal) == "table" then whole(deal.StartsAt) else 0
	if startsAt <= 0 then
		return 0, 0
	end
	return startsAt, startsAt + whole(CL.Luck.Seconds)
end

--- Whether the Grand Opening Luck runs at unix time `now`.
function BlockDrop.luckLive(now: any): boolean
	if type(now) ~= "number" or now ~= now then
		return false
	end
	local startsAt, endsAt = BlockDrop.luckWindow()
	return startsAt > 0 and now >= startsAt and now < endsAt
end

--- The chance of the step up from `tier` in parts of OddsTotal (0 at the top or for anything
--- else): Config's step, or the Grand Opening Luck's while `luck` is true.
function BlockDrop.stepParts(tier: string, luck: boolean?): number
	if luck == true and LUCK_STEPS[tier] ~= nil then
		return LUCK_STEPS[tier]
	end
	return STEPS[tier] or 0
end

---------------------------------------------------------------------------------------------
-- The odds of a climb
---------------------------------------------------------------------------------------------

-- Each final tier's chance (0..1) for a climb from `start` (nil: Standard), with pity's floor
-- (Rare or Epic: every tier under it ends on it instead) and the luck. Exact products of the
-- steps, so the lists show exactly what the roll does.
local function chancesOf(start: string?, luck: boolean?, floor: string?): { [string]: number }
	local from = RANK[start or TIERS[1]]
	assert(from ~= nil, "BlockDrop: unknown start " .. tostring(start))
	local chances: { [string]: number } = {}
	local reach = 1
	for i = from, TOP do
		local tier = TIERS[i]
		local up = if i < TOP then BlockDrop.stepParts(tier, luck) / C.OddsTotal else 0
		chances[tier] = reach * (1 - up)
		reach *= up
	end
	local floorRank = if floor ~= nil then RANK[floor] else nil
	if floorRank ~= nil and floorRank > from then
		local moved = 0
		for i = from, floorRank - 1 do
			moved += chances[TIERS[i]] or 0
			chances[TIERS[i]] = nil
		end
		chances[floor :: string] = (chances[floor :: string] or 0) + moved
	end
	return chances
end

--- Each final tier's chance (0..1) for a climb: `opts.start` (nil: Standard), `opts.luck`, and
--- pity's `floor` (the Mystery block's; BlockDrop.floorOf). Tiers it can't end on are nil.
function BlockDrop.chances(floor: string?, opts: ClimbOpts?): { [string]: number }
	local o: ClimbOpts = opts or {}
	return chancesOf(o.start, o.luck, floor)
end

--- The tier pity guarantees for the next Mystery block, from the blocks left until each
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

--- The final tiers with their chances, the start first: { tier, weight (parts of OddsTotal,
--- not rounded), percent, display }. `floor`: the live odds while pity guarantees that tier (the
--- Mystery block's; the tiers under it are left out). `opts`: the start and the luck (nil: a
--- Mystery block's climb, without the luck).
function BlockDrop.tiers(floor: string?, opts: ClimbOpts?): { TierOdds }
	local list = {}
	local chances = BlockDrop.chances(floor, opts)
	for _, id in TIERS do
		local chance = chances[id] or 0
		if chance > 0 then
			local percent = chance * 100
			table.insert(list, {
				tier = id,
				weight = chance * C.OddsTotal,
				percent = percent,
				display = BlockOdds.percentText(percent),
			})
		end
	end
	return list
end

--- Each rarity's chance per block for a climb (the tier it ends on is the rarity): bottom
--- rarity first, only rarities it can give; the percents add to 100 (within float rounding).
--- The cue cards show the Mystery block's ("EPIC · 2.8%"). `floor` and `opts`: as
--- BlockDrop.tiers.
function BlockDrop.rarityOdds(floor: string?, opts: ClimbOpts?): { RarityOdds }
	local list = {}
	local chances = BlockDrop.chances(floor, opts)
	for _, id in TIERS do
		local chance = chances[id] or 0
		if chance > 0 then
			local percent = chance * 100
			table.insert(list, {
				rarity = RARITY[id],
				percent = percent,
				display = BlockOdds.percentText(percent),
			})
		end
	end
	return list
end

--- The cues a climb ending on `tier` can give, in catalog order: the droppable cues of its
--- rarity in its climbed block's row (the Secret, which has no block: in the Mythic row, the
--- tier it is reached from). Empty for anything else.
function BlockDrop.pool(tier: string): { Catalog.Cue }
	local rarity = RARITY[tier]
	if rarity == nil then
		return {}
	end
	local row = if BlockDrop.isBlockTier(tier) then tier else C.Order[#C.Order]
	return Catalog.droppable(row, rarity)
end

-- Each cue's chance per block (its tier's chance split evenly among its pool) and each
-- rarity's cue ids in the catalog's order.
local function cueChances(
	floor: string?,
	opts: ClimbOpts?
): ({ [string]: number }, { [string]: { string } })
	local chances = BlockDrop.chances(floor, opts)
	local chance: { [string]: number } = {}
	local byRarity: { [string]: { string } } = {}
	for _, tier in TIERS do
		local share = chances[tier] or 0
		if share > 0 then
			local pool = BlockDrop.pool(tier)
			local rarity = RARITY[tier]
			for _, cue in pool do
				if chance[cue.Id] == nil then
					chance[cue.Id] = 0
					local ids = byRarity[rarity] or {}
					byRarity[rarity] = ids
					table.insert(ids, cue.Id)
				end
				chance[cue.Id] += share * 100 / #pool
			end
		end
	end
	return chance, byRarity
end

--- Each rarity's chance per block with its cues (Roblox's rules: every final item with its
--- chance): bottom rarity first, the cues in the catalog's order; `each` is one cue's chance
--- (every cue of a rarity is equally likely). `floor` and `opts`: as BlockDrop.tiers.
function BlockDrop.cueGroups(floor: string?, opts: ClimbOpts?): { BlockOdds.CueGroup }
	local chance, byRarity = cueChances(floor, opts)
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

--- Each cue's chance per block in percent, by id (what BlockDrop.cueGroups sums).
function BlockDrop.cueChances(floor: string?, opts: ClimbOpts?): { [string]: number }
	return (cueChances(floor, opts))
end

--- One rarity's chance per block in percent (0 for a rarity the climb never gives). `opts`:
--- the start and the luck (nil: a Mystery block's climb without the luck).
function BlockDrop.rarityPercent(rarity: string, opts: ClimbOpts?): number
	for _, entry in BlockDrop.rarityOdds(nil, opts) do
		if entry.rarity == rarity then
			return entry.percent
		end
	end
	return 0
end

--- The chance in percent that a climb from `opts.start` gives exactly cue `cueId` (the "1 in N"
--- of the Legendary-or-better messages, plan 3.9), or 0 for a cue no climb gives.
function BlockDrop.cuePercent(cueId: string, opts: ClimbOpts?): number
	return BlockDrop.cueChances(nil, opts)[cueId] or 0
end

--- The N of "1 in N" for a chance of `percent`, rounded to 3 significant figures (plan 3.9:
--- 1 in 2,614.4 -> 2,610; 1 in 84,656 -> 84,700; 1 in 8.235 -> 8.24). nil for no chance.
function BlockDrop.oneIn(percent: number): number?
	if type(percent) ~= "number" or percent ~= percent or percent <= 0 or percent > 100 then
		return nil
	end
	local n = 100 / percent
	local step = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.floor(n / step + 0.5) * step
end

---------------------------------------------------------------------------------------------
-- Pity (the Mystery block's; plan 3.6)
---------------------------------------------------------------------------------------------

--- A new save's counters: the head start (Config.BlockOdds.Drop.PityStart).
function BlockDrop.freshPity(): Pity
	return {
		SinceRare = whole(D.PityStart.SinceRare),
		SinceEpic = whole(D.PityStart.SinceEpic),
		Total = 0,
	}
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

--- Mystery blocks left until a Rare and an Epic are guaranteed (1: the next one is).
function BlockDrop.pityLeft(pity: Pity): { rare: number, epic: number }
	return {
		rare = math.max(D.PityRare - pity.SinceRare, 1),
		epic = math.max(D.PityEpic - pity.SinceEpic, 1),
	}
end

---------------------------------------------------------------------------------------------
-- Rolling a climb
---------------------------------------------------------------------------------------------

--- Rolls a climb from `start` (a ladder tier): each step up is one rng(OddsTotal) draw at or
--- under its chance (BlockDrop.stepParts, the Grand Opening Luck's while `luck`), until a step
--- fails or the Secret is reached. Returns the final tier. `rng(n)` returns 1..n.
function BlockDrop.climbRoll(start: string, rng: (number) -> number, luck: boolean?): string
	local at = RANK[start]
	assert(at ~= nil, "BlockDrop.climbRoll: unknown start " .. tostring(start))
	while at < TOP do
		local pick = rng(C.OddsTotal)
		assert(
			pick >= 1 and pick <= C.OddsTotal and pick == math.floor(pick),
			"BlockDrop.climbRoll: rng out of range"
		)
		if pick > BlockDrop.stepParts(TIERS[at], luck) then
			break
		end
		at += 1
	end
	return TIERS[at]
end

--- Rolls one Mystery block's climb: (final tier, the counters after it). `forced` skips the
--- roll. Otherwise it climbs from Standard (BlockDrop.climbRoll, with the luck while `luck`),
--- then pity sets it: exactly Epic on the PityEpic-th Mystery block in a row without an
--- Epic-or-better climb, else exactly Rare on the PityRare-th without a Rare-or-better. Every
--- Mystery block counts, forced ones too. `rng(n)` returns 1..n.
function BlockDrop.roll(
	pity: Pity,
	rng: (number) -> number,
	forced: string?,
	luck: boolean?
): (string, Pity)
	local tier: string
	if forced ~= nil then
		assert(RANK[forced] ~= nil, "BlockDrop.roll: unknown tier " .. tostring(forced))
		tier = forced
	else
		tier = BlockDrop.climbRoll(TIERS[1], rng, luck)
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
-- The climb screen's path (Config.BlockOdds.Drop.Upgrade; plan 3.5)
---------------------------------------------------------------------------------------------

local UP = D.Upgrade

--- The tier the first press shows for a climb from `start` (nil: Standard) that ends on
--- `final`: the start, or higher when the later Clicks - 1 presses (one tier each at most)
--- couldn't reach `final` otherwise (the higher of the start and `final` minus Clicks - 1).
function BlockDrop.startOf(final: string, start: string?): string
	assert(RANK[final] ~= nil, "BlockDrop.startOf: unknown tier " .. tostring(final))
	local from = RANK[start or TIERS[1]]
	assert(from ~= nil, "BlockDrop.startOf: unknown start " .. tostring(start))
	assert(RANK[final] >= from, "BlockDrop.startOf: the final tier is below the start")
	return TIERS[math.max(from, RANK[final] - (UP.Clicks - 1))]
end

--- The first press's chance of each tier (0..1) for a climb from `start` (nil: Standard): each
--- final tier's chance on its first press (BlockDrop.startOf).
function BlockDrop.firstOdds(start: string?, luck: boolean?): { [string]: number }
	local first: { [string]: number } = {}
	for _, tier in TIERS do
		first[tier] = 0
	end
	for tier, chance in chancesOf(start, luck, nil) do
		local shown = BlockDrop.startOf(tier, start)
		first[shown] += chance
	end
	return first
end

--- The tiers a block shows press by press on the climb screen, from `start` (nil: Standard) to
--- `final` (the tier the roll gave): Clicks tiers. The first press shows its start
--- (BlockDrop.startOf); a block that ends `k` tiers above it climbs one tier on exactly `k` of
--- the later presses, which ones picked with every choice equally likely. A climb never
--- fizzles or falls back. `rng(n)` returns 1..n.
function BlockDrop.path(final: string, rng: (number) -> number, start: string?): { string }
	local clicks = UP.Clicks
	local at = RANK[BlockDrop.startOf(final, start)]
	local left = RANK[final] - at
	local tiers = table.create(clicks, TIERS[at])
	for press = 2, clicks do
		-- Selection sampling: climb with chance (climbs left) / (presses left), which picks
		-- each set of `k` presses equally often.
		if left > 0 and rng(clicks - press + 1) <= left then
			at += 1
			left -= 1
		end
		tiers[press] = TIERS[at]
	end
	return tiers
end

--- A press path as today's climb screen can show it (a shim until the GUI session's screen
--- knows the Secret): every tier that is not a block (the Secret) shown as the top block tier.
function BlockDrop.shown(tiers: { string }): { string }
	local top = C.Order[#C.Order]
	local out = table.clone(tiers)
	for i, tier in out do
		if not BlockDrop.isBlockTier(tier) then
			out[i] = top
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- Checks
---------------------------------------------------------------------------------------------

local function isPart(x: any): boolean
	return type(x) == "number" and x >= 0 and x <= C.OddsTotal and x == math.floor(x)
end

--- Everything wrong with Config.BlockOdds.Climb and Drop, sorted (empty when all is well): a
--- ladder that is not the block tiers plus one on top, a step that is not a whole part of
--- OddsTotal, a tier without a rarity or without a cue to give, bad pity limits or head start,
--- a FirstWin or win track step that is not a lucky block kind (or "Money"), or too few presses.
function BlockDrop.validate(): { string }
	local problems = {}
	local function problem(text: string)
		table.insert(problems, text)
	end
	if #TIERS ~= #C.Order + 1 then
		problem("Climb.Tiers must be Order plus one tier on top")
	end
	for i, tier in C.Order do
		if TIERS[i] ~= tier then
			problem(("Climb.Tiers[%d] is %s, not %s"):format(i, tostring(TIERS[i]), tier))
		end
	end
	for i, tier in TIERS do
		if RARITY[tier] == nil or not table.find(C.Rarities, RARITY[tier]) then
			problem(("Climb.Rarity has no rarity for %s"):format(tier))
		elseif #BlockDrop.pool(tier) == 0 then
			problem(("Climb: no cue to give for %s"):format(tier))
		end
		if i < TOP and not isPart(STEPS[tier]) then
			problem(("Climb.Steps.%s is not a whole part of OddsTotal"):format(tier))
		end
	end
	for tier in STEPS do
		if RANK[tier] == nil or RANK[tier] >= TOP then
			problem(("Climb.Steps has %s, not a tier below the top"):format(tostring(tier)))
		end
	end
	for tier, parts in LUCK_STEPS do
		if RANK[tier] == nil or RANK[tier] >= TOP then
			problem(("Climb.Luck.Steps has %s, not a tier below the top"):format(tostring(tier)))
		elseif not isPart(parts) then
			problem(("Climb.Luck.Steps.%s is not a whole part of OddsTotal"):format(tier))
		end
	end
	if whole(CL.Luck.Seconds) <= 0 then
		problem("Climb.Luck.Seconds must be above 0")
	end
	if D.PityRare < 1 or D.PityEpic < 1 then
		problem("Drop pity limits must be at least 1")
	end
	local start = D.PityStart
	if
		whole(start.SinceRare) ~= start.SinceRare
		or whole(start.SinceEpic) ~= start.SinceEpic
		or start.SinceRare >= D.PityRare
		or start.SinceEpic >= D.PityEpic
	then
		problem("Drop.PityStart must be whole counts under the pity limits")
	end
	local kinds: { [string]: any } = Config.LuckyBlocks.Kinds :: any
	if kinds[D.FirstWin] == nil then
		problem(("Drop.FirstWin %s is not a lucky block"):format(tostring(D.FirstWin)))
	end
	local money = false
	for i, step in WIN_TRACK do
		if step == BlockDrop.Money then
			money = true
		elseif kinds[step] == nil then
			problem(("Drop.WinTrack[%d] %s is not a lucky block"):format(i, tostring(step)))
		end
	end
	if money and whole(D.WinTrackMoney) <= 0 then
		problem("Drop.WinTrackMoney must be above 0 for the money steps")
	end
	if type(UP.Clicks) ~= "number" or UP.Clicks < 2 or UP.Clicks ~= math.floor(UP.Clicks) then
		problem("Drop.Upgrade.Clicks must be a whole number of at least 2")
	end
	table.sort(problems)
	return problems
end

do
	local problems = BlockDrop.validate()
	assert(#problems == 0, "Config.BlockOdds.Climb/Drop: " .. table.concat(problems, "; "))
end

---------------------------------------------------------------------------------------------
-- The win's block: the daily win track (v5 plan section 4; ECONOMY 3.6)
---------------------------------------------------------------------------------------------

--- How many steps the daily win track has (#Config.BlockOdds.Drop.WinTrack).
function BlockDrop.trackSteps(): number
	return #WIN_TRACK
end

--- Win track step `step` (1..trackSteps()): a block kind or BlockDrop.Money, or nil past it.
function BlockDrop.trackKind(step: number): string?
	return WIN_TRACK[step]
end

--- The money a money step pays (Config.BlockOdds.Drop.WinTrackMoney).
function BlockDrop.trackMoney(): number
	return whole(D.WinTrackMoney)
end

--- What a win that moves the track gives: the first win ever's FirstWin block, else the next
--- step (`trackToday` steps given today): a block kind or BlockDrop.Money. nil past the track.
function BlockDrop.winKind(trackToday: number, firstWinEver: boolean): string?
	local step = whole(trackToday) + 1
	if step > #WIN_TRACK then
		return nil
	end
	return if firstWinEver then D.FirstWin else WIN_TRACK[step]
end

--- Whether this win moves the day's win track (and gives its step), and that step (the first
--- win ever's FirstWin block, else the step's block or BlockDrop.Money). Every real win does,
--- except: a loss, solo, a match that was not real, the track already done today
--- (trackSteps() steps), a same-opponent row that forbids it, DropsPerOpponent steps from this
--- account today already, a loser with fewer than DropLoserMinMatches real matches (the
--- anti-farm rules apply to the first win too), or Play against PC past PcDropsPerDay steps
--- today.
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
