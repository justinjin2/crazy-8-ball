--!strict
-- CaseDrop: the Case Drop (the approved economy plan, 2026-10-02, section 2). After every real
-- win, and from Mystery Cases and reward drops, the server rolls a case tier by
-- Config.Cases.Drop.Weights, with pity, then lands that case (Inventory.landCase). The reveal
-- (the Cutscenes lane's magic 8-ball) climbs from Standard one step per shake; the server has
-- decided the tier first, so `climbs` is only the tier's steps above Standard.
--
-- Pure: no Instances, no clocks, no randomness of its own (the caller passes rng(n) -> 1..n).
-- Every list walks Config.Cases.Order or Rarities, never hash order.
local Config = require(script.Parent.Parent.Config)
local Cases = require(script.Parent.Cases)

local C = Config.Cases
local D = C.Drop
local WEIGHTS: { [string]: number } = D.Weights :: any

-- The drop counters the save keeps (save.Drops): drops in a row without a Rare-or-better case
-- and without an Epic-or-better case, and every drop ever.
export type Pity = { SinceRare: number, SinceEpic: number, Total: number }

-- What the client is sent for one drop (the CaseDrop remote, MatchSummary.caseDrop).
export type Payload = {
	source: string, -- "Win", "Mystery", "Reward" ...
	tier: string, -- the case it landed as
	climbs: number, -- steps above Standard the reveal shows (0..5)
	readyAt: number, -- unix time the case can be opened (0: now)
	instant: boolean, -- no timer: the reveal ends on Open now / Later
	pity: { rare: number, epic: number }, -- drops left until a Rare / Epic is guaranteed
}

export type TierOdds = { tier: string, weight: number, percent: number, display: string }
export type RarityOdds = { rarity: string, percent: number, display: string }
export type Climb = { from: string, to: string, percent: number, display: string }

local CaseDrop = {}

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

--- A case tier's place on the ladder (Standard 1 .. Mythic 6), 0 for anything else.
function CaseDrop.rank(tier: any): number
	return RANK[tier] or 0
end

--- The steps above Standard the reveal climbs to show `tier`.
function CaseDrop.climbs(tier: string): number
	return math.max(CaseDrop.rank(tier) - 1, 0)
end

--- The tiers with their weights and percents, Standard first.
function CaseDrop.tiers(): { TierOdds }
	local list = {}
	for _, id in C.Order do
		local weight = WEIGHTS[id] or 0
		if weight > 0 then
			local percent = weight * 100 / C.OddsTotal
			table.insert(list, {
				tier = id,
				weight = weight,
				percent = percent,
				display = Cases.percentText(percent),
			})
		end
	end
	return list
end

--- The chance each step of the reveal climbs, given it reached the step below (derived from
--- the weights: the share of drops at or above the next tier among those at or above this one).
function CaseDrop.climbChances(): { Climb }
	local list = {}
	for i = 1, #C.Order - 1 do
		local atOrAbove, aboveNext = 0, 0
		for j = i, #C.Order do
			local weight = WEIGHTS[C.Order[j]] or 0
			atOrAbove += weight
			if j > i then
				aboveNext += weight
			end
		end
		if atOrAbove > 0 and aboveNext > 0 then
			local percent = aboveNext * 100 / atOrAbove
			table.insert(list, {
				from = C.Order[i],
				to = C.Order[i + 1],
				percent = percent,
				display = Cases.percentText(percent),
			})
		end
	end
	return list
end

--- Each rarity's chance per Case Drop (pity aside): the tier weights times each case's odds.
--- Bottom rarity first, only rarities that can drop; the percents add to 100 (within float
--- rounding). The cue cards show these ("EPIC · 0.138%").
function CaseDrop.rarityOdds(): { RarityOdds }
	local list = {}
	local total = C.OddsTotal
	for _, rarity in C.Rarities do
		local parts = 0
		for _, id in C.Order do
			local case = Cases.get(id)
			if case then
				parts += (WEIGHTS[id] or 0) * (case.Odds[rarity] or 0)
			end
		end
		if parts > 0 then
			local percent = parts * 100 / (total * total)
			table.insert(list, {
				rarity = rarity,
				percent = percent,
				display = Cases.percentText(percent),
			})
		end
	end
	return list
end

--- One rarity's chance per Case Drop in percent (0 for a rarity no case drops).
function CaseDrop.rarityPercent(rarity: string): number
	for _, entry in CaseDrop.rarityOdds() do
		if entry.rarity == rarity then
			return entry.percent
		end
	end
	return 0
end

--- The save's counters read as whole numbers (anything missing or broken is 0).
function CaseDrop.readPity(drops: any): Pity
	local t = if type(drops) == "table" then drops else {}
	return {
		SinceRare = whole(t.SinceRare),
		SinceEpic = whole(t.SinceEpic),
		Total = whole(t.Total),
	}
end

--- Drops left until a Rare and an Epic case are guaranteed (1: the next drop is).
function CaseDrop.pityLeft(pity: Pity): { rare: number, epic: number }
	return {
		rare = math.max(D.PityRare - pity.SinceRare, 1),
		epic = math.max(D.PityEpic - pity.SinceEpic, 1),
	}
end

--- Rolls one Case Drop: (tier, the counters after it). `forced` (the first win's Rare Case)
--- skips the roll. Otherwise the weights pick a tier, then pity raises it: to Epic on the
--- PityEpic-th drop in a row without an Epic-or-better case, else to Rare on the PityRare-th
--- without a Rare-or-better. Every drop counts, forced ones too. `rng(n)` returns 1..n.
function CaseDrop.roll(pity: Pity, rng: (number) -> number, forced: string?): (string, Pity)
	local tier: string
	if forced ~= nil then
		assert(RANK[forced] ~= nil, "CaseDrop.roll: unknown case " .. tostring(forced))
		tier = forced
	else
		local pick = rng(C.OddsTotal)
		assert(
			pick >= 1 and pick <= C.OddsTotal and pick == math.floor(pick),
			"CaseDrop.roll: rng out of range"
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

--- Everything wrong with Config.Cases.Drop, sorted (empty when all is well): weights that are
--- not whole numbers, a tier that is not a case, weights that do not add to OddsTotal, pity
--- limits below 1, or a FirstWin that is not a case.
function CaseDrop.validate(): { string }
	local problems = {}
	local sum = 0
	for tier, weight in WEIGHTS do
		if RANK[tier] == nil then
			table.insert(problems, ("Drop.Weights has %s, not a case"):format(tostring(tier)))
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
		table.insert(problems, ("Drop.FirstWin %s is not a case"):format(tostring(D.FirstWin)))
	end
	table.sort(problems)
	return problems
end

do
	local problems = CaseDrop.validate()
	assert(#problems == 0, "Config.Cases.Drop: " .. table.concat(problems, "; "))
end

--- The payload for one landed drop.
function CaseDrop.payload(source: string, tier: string, readyAt: number, pity: Pity): Payload
	return {
		source = source,
		tier = tier,
		climbs = CaseDrop.climbs(tier),
		readyAt = readyAt,
		instant = readyAt == 0,
		pity = CaseDrop.pityLeft(pity),
	}
end

return CaseDrop
