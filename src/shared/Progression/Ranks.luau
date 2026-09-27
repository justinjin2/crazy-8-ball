--!strict
-- Ranks (GDD section 11): turns a player's total rank XP into their rank and back, and works
-- out what a finished match (or the /xp dev command) does to it: the XP, the floor, the new
-- peak and the money paid for reaching new divisions. Pure and deterministic: no Instances,
-- no clocks, no randomness, and every loop walks an ordered list (Config.Ranks.Tiers or the
-- division list built from it), never a keyed table.
--
-- Divisions are numbered 1..count() from the bottom: 1 = Bronze I, 5 = Bronze V, 6 = Silver
-- I, ..., the last = the top tier (Reyes), which has one division and no top. 0 = Unranked.
-- A save's rank is its RankXp plus whether it is rated (RatedMatches > 0): an unrated save
-- is Unranked whatever its XP, and counts as 0 XP.
local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)

local C = Config.Ranks
local S = Strings.Ranks
-- Keyed by tier name; read through these so strict mode allows a name held in a variable.
local DIVISION_XP: { [string]: { number } } = C.DivisionXp :: any
local LOSS_XP: { [string]: number } = C.LossXp :: any
local STEP_PAY: { [string]: number } = C.Rewards.Step :: any
local FIRST_PAY: { [string]: number } = C.Rewards.TierFirst :: any
local TIER_WORDS: { [string]: string } = S.Tiers :: any

local UNRANKED = "Unranked"

export type Rank = {
	tier: string, -- a Config.Ranks.Tiers name, or "Unranked"
	division: number, -- 1..DivisionsPerTier (the top tier: 1; Unranked: 0)
	index: number, -- 1..count() (Unranked: 0)
	xpInDivision: number, -- XP past the start of the division
	width: number?, -- the division's XP width; nil for the top tier and Unranked
}

export type Reward = { index: number, amount: number }

export type RankSave = { RankXp: number, PeakDivision: number, RatedMatches: number }

export type MatchResult = {
	before: Rank,
	after: Rank,
	xpBefore: number,
	xpAfter: number,
	delta: number, -- xpAfter - xpBefore, after the floor
	peakBefore: number,
	peakAfter: number,
	ratedMatches: number, -- the save's new RatedMatches
	rewards: { Reward },
	rewardTotal: number,
	promoted: boolean, -- after.index > before.index
	newTier: boolean, -- promoted into a different tier (Unranked to Bronze counts)
	demoted: boolean, -- after.index < before.index
}

export type Division = {
	index: number,
	tier: string,
	division: number,
	startXp: number,
	width: number?,
	reward: number,
}

export type RulesLine = {
	win: number,
	lowLoss: number, -- the XP a loss still gives in the low tiers (positive; 0 if none)
	lossTiersLow: { string },
	freeTiers: { string },
	loseTiers: { string },
	highLoss: number, -- the XP a loss costs in the high tiers (negative; 0 if none)
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

-- A whole number of either sign, cut toward zero (non-finite becomes 0).
local function signedWhole(value: any): number
	if not finite(value) then
		return 0
	end
	return if value < 0 then math.ceil(value) else math.floor(value)
end

-- The most rank XP a save may hold (the save layer clamps to the same cap).
local XP_CAP = math.floor(Config.Save.RankXpCap)

local function clampXp(xp: number): number
	return math.clamp(xp, 0, XP_CAP)
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
local divReward: { number } = {}
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
		for division = 1, count do
			local index = #divTier + 1
			divTier[index] = tier
			divNumber[index] = division
			divStart[index] = start
			if division == 1 then
				tierFirstIndex[tier] = index
				divReward[index] = whole(FIRST_PAY[tier])
			else
				divReward[index] = whole(STEP_PAY[tier])
			end
			if not isTop then
				local width = math.max(1, whole(widths[division]))
				divWidth[index] = width
				start += width
			end
		end
	end
end

local COUNT = #divTier

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
-- Rewards (money for the first time a division is reached)
---------------------------------------------------------------------------------------------

--- The money for reaching a division for the first time (0 for Unranked).
function Ranks.rewardFor(index: number): number
	local i = clampIndex(index)
	return if i == 0 then 0 else divReward[i]
end

--- Every division a new peak passes, above the old peak up to and including the new one,
--- bottom first, with its money. Empty when the peak did not rise; a $0 division is left out.
function Ranks.rewardsBetween(peakBefore: number, peakAfter: number): { Reward }
	local list: { Reward } = {}
	for i = clampIndex(peakBefore) + 1, clampIndex(peakAfter) do
		local amount = divReward[i]
		if amount > 0 then
			table.insert(list, { index = i, amount = amount })
		end
	end
	return list
end

---------------------------------------------------------------------------------------------
-- Match XP
---------------------------------------------------------------------------------------------

--- The raw XP a finished match gives (before the floor). `outcome` is "Win", "Loss" or
--- "Draw"; `opponent` "Player" or "PC". `forfeit` means this player surrendered, left, timed
--- out or sank the 8 early: always a loss, never the low tiers' consolation XP. Unranked
--- plays by the bottom tier's rules. An unknown outcome gives 0.
function Ranks.matchXp(rank: Rank, outcome: string, opponent: string, forfeit: boolean): number
	local named = canonicalTier(if type(rank) == "table" then rank.tier else nil)
	local tier: string = if named == nil or named == UNRANKED then TIERS[1] else named
	local lossXp = signedWhole(LOSS_XP[tier])
	if forfeit == true then
		return math.min(lossXp, 0)
	end
	if outcome == "Win" then
		if opponent == "PC" then
			-- Config.Ranks.PcCapTier would apply here: past that tier a PC win gives less (GDD).
			-- It is nil (no cap) until bots exist.
			return math.floor(whole(C.WinXp) * C.PcWinShare)
		end
		return whole(C.WinXp)
	elseif outcome == "Loss" then
		return lossXp
	end
	return 0
end

--- The lowest total XP a loss can leave: division I, 0 XP, of the tier `xp` is in (a rated
--- player keeps every tier they reach).
function Ranks.floorXp(xp: number): number
	local i = indexForXp(whole(xp))
	return divStart[tierFirstIndex[divTier[i]]]
end

-- Applies a signed XP change to a rated total: a loss stops at the tier's floor, a gain has
-- no limit but the save cap.
local function applyDelta(xp: number, delta: number): number
	local after = xp + delta
	if delta < 0 then
		after = math.max(after, Ranks.floorXp(xp))
	end
	return clampXp(after)
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
	for _, reward in rewards do
		total += reward.amount
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
		promoted = after.index > before.index,
		newTier = after.index > before.index and after.tier ~= before.tier,
		demoted = after.index < before.index,
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

--- A finished match for one player: their XP, floor, peak and rewards. Counts the match
--- (RatedMatches + 1); an Unranked player's first match makes them Bronze I with that
--- match's XP applied from 0. Does not change `save`.
function Ranks.applyMatch(
	save: RankSave,
	outcome: string,
	opponent: string,
	forfeit: boolean
): MatchResult
	local xp, rated, peak, ratedMatches = readSave(save)
	local delta = Ranks.matchXp(Ranks.fromXp(xp, rated), outcome, opponent, forfeit)
	local xpAfter = applyDelta(xp, delta)
	return buildResult(xp, xpAfter, rated, true, peak, ratedMatches + 1)
end

--- The /xp dev command: `delta` XP through the same floor, peak and rewards as a match,
--- without counting a match. A gain on an Unranked save makes it rated at Bronze I first;
--- a loss on an Unranked save changes nothing.
function Ranks.applyXp(save: RankSave, delta: number): MatchResult
	local xp, rated, peak, ratedMatches = readSave(save)
	local change = signedWhole(delta)
	if not rated then
		if change <= 0 then
			return buildResult(xp, xp, false, false, peak, ratedMatches)
		end
		return buildResult(xp, applyDelta(xp, change), false, true, peak, math.max(1, ratedMatches))
	end
	return buildResult(xp, applyDelta(xp, change), true, true, peak, ratedMatches)
end

---------------------------------------------------------------------------------------------
-- The roadmap
---------------------------------------------------------------------------------------------

--- Every division, bottom first, with where it starts, its width and its money.
function Ranks.list(): { Division }
	local list: { Division } = {}
	for i = 1, COUNT do
		table.insert(list, {
			index = i,
			tier = divTier[i],
			division = divNumber[i],
			startXp = divStart[i],
			width = divWidth[i],
			reward = divReward[i],
		})
	end
	return list
end

--- The numbers behind the roadmap's one line of rules: the win XP, and the tiers grouped by
--- what a loss does (gain a little, nothing, lose XP), in Tier order. lowLoss and highLoss
--- are the lowest such tier's loss XP, signed (+50 and -150 now).
function Ranks.rulesLine(): RulesLine
	local line: RulesLine = {
		win = whole(C.WinXp),
		lowLoss = 0,
		lossTiersLow = {},
		freeTiers = {},
		loseTiers = {},
		highLoss = 0,
	}
	for _, tier in TIERS do
		local loss = signedWhole(LOSS_XP[tier])
		if loss > 0 then
			if #line.lossTiersLow == 0 then
				line.lowLoss = loss
			end
			table.insert(line.lossTiersLow, tier)
		elseif loss < 0 then
			if #line.loseTiers == 0 then
				line.highLoss = loss
			end
			table.insert(line.loseTiers, tier)
		else
			table.insert(line.freeTiers, tier)
		end
	end
	return line
end

return Ranks
