--!strict
-- Ranks (GDD section 11; every number in Config.Ranks, from docs/ECONOMY.md section 4): turns
-- a player's total rank XP into their rank and back, and works out what a finished match (or
-- the /xp dev command) does to it: the XP and how it was built, the new peak, and the rewards
-- for reaching new divisions. Pure and deterministic: no Instances, no clocks, no randomness,
-- and every loop walks an ordered list (Config.Ranks.Tiers, Config.Cases.Order or the
-- division list built from them), never a keyed table.
--
-- XP is never lost (ECONOMY 4.1, designer 2026-09-28): a match gives 0 or more, so nobody ever
-- drops a division or a tier and there is no floor to keep. Only wins give XP (2026-10-02).
--
-- Divisions are numbered 1..count() from the bottom: 1 = Bronze I, 5 = Bronze V, 6 = Silver
-- I, ..., the last = the top tier (Reyes), which has one division and no top. 0 = Unranked.
-- A save's rank is its RankXp plus whether it is rated (RatedMatches > 0): an unrated save
-- is Unranked whatever its XP, and counts as 0 XP. A save becomes rated with its first match
-- that gives XP (its first win), which places it at Bronze I.
local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)

local C = Config.Ranks
local S = Strings.Ranks
local GAP = C.Gap
local BOOSTS = C.Boosts

type BaseRow = { Win: number, Loss: number }
type TierRow = { Money: number, Cases: { [string]: number }?, Cue: string? }

-- Keyed by tier (or mode, or difficulty) name; read through these so strict mode allows a name
-- held in a variable.
local DIVISION_XP: { [string]: { number } } = C.DivisionXp :: any
local BASE_XP: { [string]: BaseRow } = C.BaseXp :: any
local MODE_XP: { [string]: number } = C.ModeXp :: any
local CLASSIC_FADE: { [string]: number } = C.ClassicWinFade :: any
local STEP_PAY: { [string]: number } = C.Rewards.Step :: any
local TIER_PAY: { [string]: TierRow } = C.Rewards.Tier :: any
local UNLOCKS: { [string]: string } = C.Unlocks :: any
-- Ult spins for reaching each tier's division I (docs/prompts/ULTIMATES_PROMPT.md section 10).
local TIER_SPINS: { [string]: number } = Config.Ults.Earn.RankUp :: any
local DIFFICULTIES: { [string]: any } = Config.Difficulty.Levels :: any
local TIER_WORDS: { [string]: string } = S.Tiers :: any
-- Case ids in shop order: a reward's cases are always read in this order.
local CASE_ORDER: { string } = Config.Cases.Order

local UNRANKED = "Unranked"
local CLASSIC = "Classic"

export type Rank = {
	tier: string, -- a Config.Ranks.Tiers name, or "Unranked"
	division: number, -- 1..DivisionsPerTier (the top tier: 1; Unranked: 0)
	index: number, -- 1..count() (Unranked: 0)
	xpInDivision: number, -- XP past the start of the division
	width: number?, -- the division's XP width; nil for the top tier and Unranked
}

-- What reaching a division pays, once (ECONOMY 4.8): money, cases by case id, the tier's
-- Exclusive cue on a tier's division I, and the ult spins a new tier adds there
-- (Config.Ults.Earn.RankUp; 0 on divisions II-V).
export type Reward = {
	index: number,
	money: number,
	cases: { [string]: number },
	cue: string?,
	spins: number,
}

export type RankSave = { RankXp: number, PeakDivision: number, RatedMatches: number }

-- One XP boost that was on for a match, for the result screen's chips.
export type Boost = {
	kind: string, -- "Streak" (the only boost since 2026-10-02)
	share: number, -- what it adds (1.0 = +100%)
}

-- How a match's XP was built: xp = round(base x mode x fade x gap x pc x farm x (1 +
-- boostTotal)). A match that gives nothing by rule (a draw, a forfeit) has base 0 and 1s.
export type Breakdown = {
	base: number, -- the tier's win or loss XP (Config.Ranks.BaseXp)
	mode: number, -- the table's difficulty (ModeXp)
	fade: number, -- Classic's win fade (ClassicWinFade); 1 otherwise
	gap: number, -- the opponent-gap factor (a loss's capped at Gap.LossMax)
	pc: number, -- PcXp against PC; 1 against people
	farm: number, -- the anti-farm XP multiplier (Config.Economy.SameOpponent)
	boosts: { Boost }, -- the boosts that were on
	boostTotal: number, -- their shares added up
}

-- What a finished match was, for one player. `boosts` flags are decided by the server: streak
-- (this win makes the streak Boosts.StreakFrom or more).
export type MatchContext = {
	outcome: string, -- "Win", "Loss" or "Draw"
	opponent: string, -- "Player" or "PC"; "Tutorial" (or anything else) gives no XP
	forfeit: boolean?, -- this player surrendered, left, timed out or sank the 8 early
	mode: string?, -- the table's difficulty, a Config.Ranks.ModeXp key (default Classic)
	opponentIndex: number?, -- the opponent's division index (a team's average); nil = equal
	boosts: { streak: boolean? }?,
	farm: number?, -- anti-farm XP multiplier (default 1)
}

export type MatchResult = {
	before: Rank,
	after: Rank,
	xpBefore: number,
	xpAfter: number,
	delta: number, -- xpAfter - xpBefore, never negative
	peakBefore: number,
	peakAfter: number,
	ratedMatches: number, -- the save's new RatedMatches
	rewards: { Reward }, -- every division the new peak passed, bottom first
	rewardTotal: number, -- their money added up
	rewardCases: { [string]: number }, -- their cases added up, by case id
	rewardCues: { string }, -- their cues, bottom first
	rewardSpins: number, -- their ult spins added up
	promoted: boolean, -- after.index > before.index
	newTier: boolean, -- promoted into a different tier (Unranked to Bronze counts)
	breakdown: Breakdown?, -- how the XP was built (a match only; nil for applyXp)
}

export type Division = {
	index: number,
	tier: string,
	division: number,
	startXp: number,
	width: number?,
	reward: number, -- the money for reaching it
	cases: { [string]: number },
	cue: string?,
	spins: number, -- the ult spins for reaching it (a tier's division I only)
}

local Ranks = {}

---------------------------------------------------------------------------------------------
-- Input cleaning: a bad caller may hand in anything; nothing here crashes or goes negative.
---------------------------------------------------------------------------------------------

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

-- A whole number >= 0 (non-numbers, NaN, infinities and negatives become 0).
local function whole(value: any): number
	if not finite(value) or value < 0 then
		return 0
	end
	return math.floor(value)
end

-- A multiplier: nil is `default`; anything not a finite number >= 0 is 0 (never pays more).
local function factor(value: any, default: number): number
	if value == nil then
		return default
	end
	if not finite(value) or value < 0 then
		return 0
	end
	return value
end

-- The most rank XP a save may hold (the save layer clamps to the same cap).
local XP_CAP = math.floor(Config.Save.RankXpCap)

local function clampXp(xp: number): number
	return math.clamp(xp, 0, XP_CAP)
end

--- Rounds half to even (312.5 -> 312, 37.5 -> 38), as ECONOMY 4.2's table was made (Python's
--- round). A product that lands a hair off .5 through floating point still counts as a tie.
function Ranks.roundHalfEven(x: number): number
	local low = math.floor(x)
	local rest = x - low
	if math.abs(rest - 0.5) < 1e-9 then
		return if low % 2 == 0 then low else low + 1
	end
	return math.floor(x + 0.5)
end

-- A reward's cases, cleaned and copied: whole counts above 0, case ids in CASE_ORDER only.
local function cleanCases(cases: { [string]: number }?): { [string]: number }
	local out: { [string]: number } = {}
	if type(cases) ~= "table" then
		return out
	end
	for _, id in CASE_ORDER do
		local count = whole(cases[id])
		if count > 0 then
			out[id] = count
		end
	end
	return out
end

---------------------------------------------------------------------------------------------
-- The division list, built once from Config in Tier order.
---------------------------------------------------------------------------------------------

local TIERS: { string } = C.Tiers
local TOP_TIER = TIERS[#TIERS]
local PER_TIER: number = C.DivisionsPerTier

local divTier: { string } = {}
local divNumber: { number } = {}
local divStart: { number } = {}
local divWidth: { [number]: number } = {} -- no entry for the top division
local divMoney: { number } = {}
local divCases: { { [string]: number } } = {}
local divCue: { [number]: string } = {} -- only tiers' division I
local divSpins: { number } = {} -- ult spins (only tiers' division I pay any)
local divPays: { boolean } = {} -- whether reaching it pays anything at all
local tierFirstIndex: { [string]: number } = {} -- each tier's division I
local tierOrder: { [string]: number } = { [UNRANKED] = 0 } -- tier name -> 1..#TIERS
local canonical: { [string]: string } = { [string.lower(UNRANKED)] = UNRANKED } -- lower -> name

do
	local start = 0
	for order, tier in TIERS do
		tierOrder[tier] = order
		canonical[string.lower(tier)] = tier
		local isTop = order == #TIERS
		local count = if isTop then 1 else PER_TIER
		local widths = DIVISION_XP[tier]
		assert(isTop or widths ~= nil, "Config.Ranks.DivisionXp has no row for " .. tier)
		assert(BASE_XP[tier] ~= nil, "Config.Ranks.BaseXp has no row for " .. tier)
		for division = 1, count do
			local index = #divTier + 1
			divTier[index] = tier
			divNumber[index] = division
			divStart[index] = start
			if division == 1 then
				tierFirstIndex[tier] = index
				local row = TIER_PAY[tier]
				divMoney[index] = whole(row and row.Money)
				divCases[index] = cleanCases(row and row.Cases)
				local cue = row and row.Cue
				if type(cue) == "string" and cue ~= "" then
					divCue[index] = cue
				end
				divSpins[index] = whole(TIER_SPINS[tier])
			else
				divMoney[index] = whole(STEP_PAY[tier])
				divCases[index] = {}
				divSpins[index] = 0
			end
			divPays[index] = divMoney[index] > 0
				or next(divCases[index]) ~= nil
				or divCue[index] ~= nil
				or divSpins[index] > 0
			if not isTop then
				local width = math.max(1, whole(widths[division]))
				divWidth[index] = width
				start += width
			end
		end
	end
end

local COUNT = #divTier
-- The first division that plays by the strict gap and the PC's High share (Expert I).
local STRICT_FROM = tierFirstIndex[GAP.StrictFromTier]
assert(STRICT_FROM ~= nil, "Config.Ranks.Gap.StrictFromTier is not a tier")

-- A division index kept inside 0..COUNT (Unranked to the top).
local function clampIndex(index: any): number
	return math.min(whole(index), COUNT)
end

-- The Config spelling of a tier name typed in any case ("gold" -> "Gold"), or nil.
local function canonicalTier(tier: any): string?
	if type(tier) ~= "string" then
		return nil
	end
	return canonical[string.lower(tier)]
end

---------------------------------------------------------------------------------------------
-- Divisions
---------------------------------------------------------------------------------------------

--- How many divisions there are above Unranked (46: nine tiers of five, then Reyes).
function Ranks.count(): number
	return COUNT
end

--- The tier and division of a division index (0 is "Unranked", 0).
function Ranks.at(index: number): (string, number)
	local i = clampIndex(index)
	if i == 0 then
		return UNRANKED, 0
	end
	return divTier[i], divNumber[i]
end

--- The division index of a tier name (any case) and division (default I). The top tier
--- ignores the division; "unranked" is 0. Nil for an unknown tier or a division off 1..V.
function Ranks.indexOf(tier: string, division: number?): number?
	local name = canonicalTier(tier)
	if name == nil then
		return nil
	end
	if name == UNRANKED then
		return 0
	end
	local first = tierFirstIndex[name]
	if name == TOP_TIER then
		return first
	end
	local d = if division == nil then 1 else division
	if type(d) ~= "number" or d ~= math.floor(d) or d < 1 or d > PER_TIER then
		return nil
	end
	return first + d - 1
end

--- The total XP at the start of a division (0 for Unranked and Bronze I).
function Ranks.startXp(index: number): number
	local i = clampIndex(index)
	return if i == 0 then 0 else divStart[i]
end

--- A division's XP width; nil for the top tier (no top) and Unranked.
function Ranks.width(index: number): number?
	local i = clampIndex(index)
	return if i == 0 then nil else divWidth[i]
end

-- The division that total XP falls in (1..COUNT).
local function indexForXp(xp: number): number
	for i = COUNT, 2, -1 do
		if xp >= divStart[i] then
			return i
		end
	end
	return 1
end

local function unrankedRank(): Rank
	return { tier = UNRANKED, division = 0, index = 0, xpInDivision = 0, width = nil }
end

--- The rank for a total XP. `rated` false (no rated match yet) is always Unranked.
function Ranks.fromXp(xp: number, rated: boolean): Rank
	if not rated then
		return unrankedRank()
	end
	local total = whole(xp)
	local i = indexForXp(total)
	return {
		tier = divTier[i],
		division = divNumber[i],
		index = i,
		xpInDivision = total - divStart[i],
		width = divWidth[i],
	}
end

--- The total XP for a rank: the division's start plus `xpInDivision` (default 0), kept
--- inside the division (at most width - 1; the top tier has no top). Nil for a bad name.
function Ranks.toXp(tier: string, division: number?, xpInDivision: number?): number?
	local index = Ranks.indexOf(tier, division)
	if index == nil then
		return nil
	end
	if index == 0 then
		return 0
	end
	local into = whole(xpInDivision)
	local width = divWidth[index]
	if width ~= nil then
		into = math.min(into, width - 1)
	end
	return clampXp(divStart[index] + into)
end

---------------------------------------------------------------------------------------------
-- Names and badges (words from Strings.Ranks)
---------------------------------------------------------------------------------------------

--- A tier's display word ("Gold", "Unranked"); an unknown name comes back as given.
function Ranks.tierName(tier: string): string
	local name = canonicalTier(tier)
	if name == nil then
		return tostring(tier)
	end
	if name == UNRANKED then
		return S.Unranked
	end
	return TIER_WORDS[name] or name
end

--- A rank as shown beside its badge: "Gold III", "Reyes", "Unranked".
function Ranks.name(rank: Rank): string
	local fields: any = if type(rank) == "table" then rank else {}
	local name = canonicalTier(fields.tier)
	if name == nil or name == UNRANKED then
		return S.Unranked
	end
	if name == TOP_TIER then
		return Ranks.tierName(name)
	end
	local division = math.clamp(whole(fields.division), 1, PER_TIER)
	return string.format(S.Division, Ranks.tierName(name), S.Numerals[division])
end

--- A badge image's file name: "gold_3", "reyes", "unranked" (an unknown tier: "unranked").
function Ranks.badgeKey(tier: string, division: number): string
	local name = canonicalTier(tier)
	if name == nil or name == UNRANKED then
		return "unranked"
	end
	local lower = string.lower(name)
	if name == TOP_TIER then
		return lower
	end
	return lower .. "_" .. math.clamp(whole(division), 1, PER_TIER)
end

--- A tier's place from the bottom: 1..10, 0 for Unranked, nil for an unknown name.
function Ranks.tierIndex(tier: string): number?
	local name = canonicalTier(tier)
	return if name == nil then nil else tierOrder[name]
end

---------------------------------------------------------------------------------------------
-- Rewards (ECONOMY 4.8: paid once, the first time a division is reached)
---------------------------------------------------------------------------------------------

-- A fresh copy of a division's reward (callers may keep or change it).
local function rewardAt(i: number): Reward
	return {
		index = i,
		money = divMoney[i],
		cases = table.clone(divCases[i]),
		cue = divCue[i],
		spins = divSpins[i],
	}
end

--- What reaching a division pays: `money`, `cases` ({ [caseId] = count }), the tier's `cue`
--- and its ult `spins` (division I only; 0 otherwise). Division II-V pays its tier's step
--- money; Unranked pays nothing.
function Ranks.rewardFor(
	index: number
): { money: number, cases: { [string]: number }, cue: string?, spins: number }
	local i = clampIndex(index)
	if i == 0 then
		return { money = 0, cases = {}, cue = nil, spins = 0 }
	end
	local reward = rewardAt(i)
	return { money = reward.money, cases = reward.cases, cue = reward.cue, spins = reward.spins }
end

--- Every division a new peak passes, above the old peak up to and including the new one,
--- bottom first, with its rewards. Empty when the peak did not rise; a division that pays
--- nothing at all is left out.
function Ranks.rewardsBetween(peakBefore: number, peakAfter: number): { Reward }
	local list: { Reward } = {}
	for i = clampIndex(peakBefore) + 1, clampIndex(peakAfter) do
		if divPays[i] then
			table.insert(list, rewardAt(i))
		end
	end
	return list
end

---------------------------------------------------------------------------------------------
-- Match XP (ECONOMY 4.2 to 4.5)
---------------------------------------------------------------------------------------------

-- Whether a division plays by the strict rules (the strict gap, the PC's High share).
local function strict(index: number): boolean
	return index >= STRICT_FROM
end

--- The opponent-gap factor (ECONOMY 4.4). gap = my division index minus the opponent's (a
--- team's average may be fractional); Unranked counts as Bronze I on either side, and a nil
--- opponent is an equal one. E = 1 / (1 + 10^(-gap / scale)); factor = 2(1 - E), clamped to
--- [floor, Gap.Max]: gentle (Scale, Floor) while I am below Gap.StrictFromTier, strict from it.
function Ranks.gapFactor(myIndex: number, opponentIndex: number?): number
	local mine = math.max(1, clampIndex(myIndex))
	local theirs = if finite(opponentIndex)
		then math.clamp(opponentIndex :: number, 1, COUNT)
		else mine
	local isStrict = strict(mine)
	local scale = if isStrict then GAP.StrictScale else GAP.Scale
	local floor = if isStrict then GAP.StrictFloor else GAP.Floor
	local expected = 1 / (1 + 10 ^ (-(mine - theirs) / scale))
	return math.clamp(2 * (1 - expected), floor, GAP.Max)
end

local function nothing(): Breakdown
	return { base = 0, mode = 1, fade = 1, gap = 1, pc = 1, farm = 1, boosts = {}, boostTotal = 0 }
end

--- The XP a finished match gives one player, and how it was built. xp = round-half-even(base
--- x mode x fade x gap x PC x farm x (1 + boosts)), never below 0:
--- - base: my tier's Win or Loss XP (Unranked plays by the bottom tier's row);
--- - mode: the table's difficulty (an unknown one is Classic); fade: Classic wins only;
--- - gap: Ranks.gapFactor, a loss's capped at Gap.LossMax;
--- - PC: PcXp.Low below Gap.StrictFromTier, PcXp.High from it;
--- - boosts add: Streak on a win against people.
--- A draw, a forfeit (surrender, leaving, timing out, an early 8) and an opponent that is
--- neither "Player" nor "PC" (the tutorial, solo) give 0.
function Ranks.matchXp(rank: Rank, ctx: MatchContext): (number, Breakdown)
	local fields: any = if type(ctx) == "table" then ctx else {}
	local outcome, opponent = fields.outcome, fields.opponent
	local win = outcome == "Win"
	if
		fields.forfeit == true
		or (not win and outcome ~= "Loss")
		or (opponent ~= "Player" and opponent ~= "PC")
	then
		return 0, nothing()
	end
	local rankFields: any = if type(rank) == "table" then rank else {}
	local named = canonicalTier(rankFields.tier)
	local tier: string = if named == nil or named == UNRANKED then TIERS[1] else named
	local myIndex = math.max(1, clampIndex(rankFields.index))

	local row = BASE_XP[tier]
	local base = whole(if win then row.Win else row.Loss)
	local modeName: string = if type(fields.mode) == "string"
			and MODE_XP[fields.mode] ~= nil
		then fields.mode
		else CLASSIC
	local mode = MODE_XP[modeName]
	local fade = if win and modeName == CLASSIC then CLASSIC_FADE[tier] or 1 else 1
	local gap = Ranks.gapFactor(myIndex, fields.opponentIndex)
	if not win then
		gap = math.min(gap, GAP.LossMax)
	end
	local pc = if opponent == "PC" then (if strict(myIndex) then C.PcXp.High else C.PcXp.Low) else 1
	local farm = factor(fields.farm, 1)

	local flags: any = if type(fields.boosts) == "table" then fields.boosts else {}
	local boosts: { Boost } = {}
	local boostTotal = 0
	local function add(kind: string, share: number)
		table.insert(boosts, { kind = kind, share = share })
		boostTotal += share
	end
	if win and opponent == "Player" and flags.streak == true then
		add("Streak", BOOSTS.Streak)
	end

	local xp = base * mode * fade * gap * pc * farm * (1 + boostTotal)
	return math.max(0, Ranks.roundHalfEven(xp)),
		{
			base = base,
			mode = mode,
			fade = fade,
			gap = gap,
			pc = pc,
			farm = farm,
			boosts = boosts,
			boostTotal = boostTotal,
		}
end

local function buildResult(
	xpBefore: number,
	xpAfter: number,
	ratedBefore: boolean,
	ratedAfter: boolean,
	peakSaved: number,
	ratedMatches: number
): MatchResult
	local before = Ranks.fromXp(xpBefore, ratedBefore)
	local after = Ranks.fromXp(xpAfter, ratedAfter)
	-- A peak is never below the rank held (only a bad save could say so).
	local peakBefore = math.max(clampIndex(peakSaved), before.index)
	local peakAfter = math.max(peakBefore, after.index)
	local rewards = Ranks.rewardsBetween(peakBefore, peakAfter)
	local total = 0
	local spins = 0
	local cases: { [string]: number } = {}
	local cues: { string } = {}
	for _, reward in rewards do
		total += reward.money
		spins += reward.spins
		for _, id in CASE_ORDER do
			local count = reward.cases[id]
			if count then
				cases[id] = (cases[id] or 0) + count
			end
		end
		if reward.cue then
			table.insert(cues, reward.cue)
		end
	end
	return {
		before = before,
		after = after,
		xpBefore = xpBefore,
		xpAfter = xpAfter,
		delta = xpAfter - xpBefore,
		peakBefore = peakBefore,
		peakAfter = peakAfter,
		ratedMatches = ratedMatches,
		rewards = rewards,
		rewardTotal = total,
		rewardCases = cases,
		rewardCues = cues,
		rewardSpins = spins,
		promoted = after.index > before.index,
		newTier = after.index > before.index and after.tier ~= before.tier,
		breakdown = nil,
	}
end

-- The save's fields, cleaned: (xp, rated, peak, ratedMatches). An unrated save counts as 0 XP.
local function readSave(save: RankSave): (number, boolean, number, number)
	local fields: any = if type(save) == "table" then save else {}
	local ratedMatches = whole(fields.RatedMatches)
	local rated = ratedMatches > 0
	local xp = if rated then clampXp(whole(fields.RankXp)) else 0
	return xp, rated, clampIndex(fields.PeakDivision), ratedMatches
end

--- A finished match for one player (`ctx` as Ranks.matchXp): their XP, how it was built,
--- their new peak and every reward it passed. Counts the match (RatedMatches + 1) once the
--- player is rated: an Unranked player stays Unranked (and uncounted) until a match gives
--- them XP, their first win, which makes them Bronze I with that XP applied from 0. Does not
--- change `save`.
function Ranks.applyMatch(save: RankSave, ctx: MatchContext): MatchResult
	local xp, rated, peak, ratedMatches = readSave(save)
	local gained, breakdown = Ranks.matchXp(Ranks.fromXp(xp, rated), ctx)
	local ratedAfter = rated or gained > 0
	local counted = if ratedAfter then ratedMatches + 1 else ratedMatches
	local result = buildResult(xp, clampXp(xp + gained), rated, ratedAfter, peak, counted)
	result.breakdown = breakdown
	return result
end

--- The /xp dev command: `delta` XP through the same peak and rewards as a match, without
--- counting a match. XP is never lost, so only a gain does anything (0 or less changes
--- nothing); a gain on an Unranked save makes it rated at Bronze I first.
function Ranks.applyXp(save: RankSave, delta: number): MatchResult
	local xp, rated, peak, ratedMatches = readSave(save)
	local gain = whole(delta)
	if gain <= 0 then
		return buildResult(xp, xp, rated, rated, peak, ratedMatches)
	end
	local count = if rated then ratedMatches else math.max(1, ratedMatches)
	return buildResult(xp, clampXp(xp + gain), rated, true, peak, count)
end

--- Whether a rank may host a table of `difficulty` (ECONOMY 4.7): a difficulty with no row in
--- Config.Ranks.Unlocks (Classic) always; the others from their tier's division I. An unknown
--- difficulty never. The host card and the server both use it (QueueMenu, TableService).
function Ranks.canHost(rank: Rank, difficulty: string): boolean
	if type(difficulty) ~= "string" or DIFFICULTIES[difficulty] == nil then
		return false
	end
	local tier = UNLOCKS[difficulty]
	if tier == nil then
		return true
	end
	local needed = tierFirstIndex[tier]
	local fields: any = if type(rank) == "table" then rank else {}
	return needed ~= nil and clampIndex(fields.index) >= needed
end

--- The rank that unlocks `difficulty`, as shown ("Gold I"), or nil when anyone may host it.
function Ranks.unlockName(difficulty: string): string?
	local tier = UNLOCKS[difficulty]
	if tier == nil then
		return nil
	end
	return Ranks.name({ tier = tier, division = 1 } :: any)
end

---------------------------------------------------------------------------------------------
-- The roadmap
---------------------------------------------------------------------------------------------

--- Every division, bottom first, with where it starts, its width and what reaching it pays.
function Ranks.list(): { Division }
	local list: { Division } = {}
	for i = 1, COUNT do
		table.insert(list, {
			index = i,
			tier = divTier[i],
			division = divNumber[i],
			startXp = divStart[i],
			width = divWidth[i],
			reward = divMoney[i],
			cases = table.clone(divCases[i]),
			cue = divCue[i],
			spins = divSpins[i],
		})
	end
	return list
end

--- A player's win streak after a match (designer, 2026-09-28: shown over their head as
--- "🔥 3"): a win that counts (a real match against people) adds one, any loss ends it (a
--- forfeit too, so leaving early never protects a streak), and anything else leaves it.
function Ranks.nextStreak(streak: number, outcome: string, counts: boolean): number
	if outcome == "Loss" then
		return 0
	elseif outcome == "Win" and counts then
		return streak + 1
	end
	return streak
end

return Ranks
