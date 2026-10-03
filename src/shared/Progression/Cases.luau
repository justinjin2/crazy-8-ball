--!strict
-- Cases (ECONOMY sections 7, 8 and 9.1): the case rows, their odds and timers, rolling one,
-- sell-back values and whether a win drops a case (the Case Drop itself: Progression/CaseDrop). Pure: no Instances, no Roblox APIs, no clocks and no
-- randomness of its own (the caller passes an rng, so the server uses Random.new() and the tests
-- a seeded generator). Every list is walked in a Config or Catalog array order, never hash order.
--
-- The numbers live in Config.Cases (odds as whole thousandths of a percent, so each row adds to
-- exactly Config.Cases.OddsTotal). The cues each case drops come from the catalog: every case cue
-- that lists the case and is not vaulted (Catalog.droppable), so vaulting a cue updates the rolls
-- and the Odds screen at once (ECONOMY 7.3, 12).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)

local C = Config.Cases
local E = Config.Economy

-- Config's literal tables, typed as the maps they are (indexed by a runtime id).
type CaseConfig = { Timer: number, Price: number, Enabled: boolean, Odds: { [string]: number } }
local LIST: { [string]: CaseConfig } = C.List :: any
local SELL_BACK: { [string]: number } = C.SellBack :: any
local ANNOUNCE: { [string]: boolean } = C.Announce :: any
local ANNOUNCE_HERE: { [string]: boolean } = C.AnnounceHere :: any

export type Case = {
	Id: string,
	Timer: number, -- seconds from landing until it opens (0: at once)
	Price: number, -- the old shop price (0: no case is sold)
	Enabled: boolean, -- sold in the shop (none is; a case can still be given and opened)
	Odds: { [string]: number }, -- rarity -> thousandths of a percent (the Config row itself)
}

export type RarityOdds = {
	rarity: string,
	weight: number, -- thousandths of a percent, out of Config.Cases.OddsTotal
	percent: number,
	display: string, -- "64.3%", "0.003%"
}

export type CueOdds = {
	id: string,
	rarity: string,
	percent: number, -- the rarity's percent split evenly among its droppable cues (7.3)
	display: string, -- "6.667%", "0.047%"
}

-- A timed sale on one case (Config.Cases.Sale's shape): Percent off that case while
-- now < EndsAt (a unix time).
export type Sale = { Case: string, Percent: number, EndsAt: number }

-- What the Case Drop rule needs to know about a settled match, for one winner.
export type DropContext = {
	real: boolean, -- a real match: past the one-minute mark, not a quick forfeit (people or PC)
	solo: boolean,
	won: boolean,
	-- Play against PC (the PC money rows): drops only for the first Config.Economy
	-- .PcDropsPerDay such wins a UTC day (`pcDropsToday` so far).
	pcLimited: boolean,
	pcDropsToday: number,
	farmAllows: boolean, -- the Config.Economy.SameOpponent row's FreeCase for this pairing
	casesFromOpponentToday: number, -- free cases already won from this account today
	loserRealMatches: number, -- the loser's real matches (a PC: any large number)
	-- True while the player has never been given the first win's case. The server may keep
	-- this true until that case actually drops, so a first win blocked by an anti-farm rule
	-- does not use it up.
	firstWinEver: boolean,
}

local Cases = {}

---------------------------------------------------------------------------------------------
-- Rows and odds
---------------------------------------------------------------------------------------------

local RARITY_KNOWN: { [string]: boolean } = {}
for _, rarity in C.Rarities do
	RARITY_KNOWN[rarity] = true
end

--- A case by id (Id, Price, Enabled, Odds), enabled or not; nil for an unknown id. Read live
--- from Config, so a server that switches a case on at runtime is seen at once.
function Cases.get(id: any): Case?
	if type(id) ~= "string" or not table.find(C.Order, id) then
		return nil
	end
	local row = LIST[id]
	if row == nil then
		return nil
	end
	return {
		Id = id,
		Timer = row.Timer,
		Price = row.Price,
		Enabled = row.Enabled,
		Odds = row.Odds,
	}
end

--- Seconds from landing until case `id` opens (0 for an instant case or an unknown id), halved
--- with Quick Cases (Config.Cases.QuickTimerFactor, rounded up to a whole second).
function Cases.timer(id: any, quick: boolean?): number
	local case = Cases.get(id)
	if case == nil or case.Timer <= 0 then
		return 0
	end
	return if quick then math.ceil(case.Timer * C.QuickTimerFactor) else case.Timer
end

--- The cases in shop order (Config.Cases.Order): only enabled ones unless includeDisabled.
function Cases.list(includeDisabled: boolean?): { Case }
	local list = {}
	for _, id in C.Order do
		local case = Cases.get(id)
		if case and (case.Enabled or includeDisabled) then
			table.insert(list, case)
		end
	end
	return list
end

-- A percent for the Odds screen: three decimals ("6.667%", "1.625%"), trailing zeros cut
-- ("64.3%", "20%"), and under 0.01% as many decimals as it takes to show two significant
-- digits, so no cue that can drop ever reads as 0%.
local function percentText(percent: number): string
	local decimals = 3
	if percent > 0 and percent < 0.01 then
		-- 0.0015 -> floor(log10) = -3 -> 4 decimals shows "0.0015".
		decimals = math.min(-math.floor(math.log10(percent)) + 1, 8)
	end
	local text = string.format("%." .. decimals .. "f", percent)
	if text:find(".", 1, true) then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. "%"
end
Cases.percentText = percentText

--- The case's rarities with a share, bottom rarity first: { rarity, weight, percent, display }.
--- Empty for an unknown case.
function Cases.odds(id: string): { RarityOdds }
	local case = Cases.get(id)
	local list = {}
	if case == nil then
		return list
	end
	for _, rarity in C.Rarities do
		local weight = case.Odds[rarity] or 0
		if weight > 0 then
			local percent = weight * 100 / C.OddsTotal
			table.insert(list, {
				rarity = rarity,
				weight = weight,
				percent = percent,
				display = percentText(percent),
			})
		end
	end
	return list
end

--- The lowest rarity the case can drop (its guarantee: "Uncommon or better"), or nil.
function Cases.minRarity(id: string): string?
	local odds = Cases.odds(id)
	return if #odds > 0 then odds[1].rarity else nil
end

--- Every cue the case can drop with its percent (ECONOMY 7.3: the rarity's percent split
--- evenly among that rarity's droppable cues), grouped by rarity bottom first, catalog order
--- inside a rarity. The percents add to 100 (within float rounding). Vaulted cues are left out.
function Cases.cueOdds(id: string): { CueOdds }
	local list = {}
	for _, entry in Cases.odds(id) do
		local pool = Catalog.droppable(id, entry.rarity)
		for _, cue in pool do
			local percent = entry.percent / #pool
			table.insert(list, {
				id = cue.Id,
				rarity = entry.rarity,
				percent = percent,
				display = percentText(percent),
			})
		end
	end
	return list
end

--- Everything wrong with the case rows against the catalog, sorted (empty when all is well):
--- a row missing from Order or List, an unknown rarity, a weight that is not a whole number,
--- a row that does not add to exactly OddsTotal, or a rarity with a share but no droppable cue.
--- Checked when this module loads; the server may call it again after vaulting a cue at runtime.
function Cases.validate(): { string }
	local problems = {}
	local function problem(text: string)
		table.insert(problems, text)
	end
	for _, id in C.Order do
		local row = LIST[id]
		if row == nil then
			problem(("case %s is in Order but has no List row"):format(id))
			continue
		end
		-- Walk the row to catch unknown rarity names and bad weights (the sum does not depend
		-- on the order of the walk, and the problems are sorted below).
		local sum = 0
		for rarity, weight in row.Odds do
			if not RARITY_KNOWN[rarity] then
				problem(("case %s has odds for unknown rarity %s"):format(id, tostring(rarity)))
			end
			if type(weight) ~= "number" or weight < 0 or weight ~= math.floor(weight) then
				problem(
					("case %s: %s weight %s is not a whole number"):format(
						id,
						rarity,
						tostring(weight)
					)
				)
			else
				sum += weight
			end
		end
		if sum ~= C.OddsTotal then
			problem(("case %s odds add to %d, not %d"):format(id, sum, C.OddsTotal))
		end
		local timer = row.Timer
		if type(timer) ~= "number" or timer < 0 or timer ~= math.floor(timer) then
			problem(("case %s timer %s is not whole seconds"):format(id, tostring(timer)))
		end
		for _, rarity in C.Rarities do
			if (row.Odds[rarity] or 0) > 0 and #Catalog.droppable(id, rarity) == 0 then
				problem(
					("case %s has a %s share but no droppable %s cue"):format(id, rarity, rarity)
				)
			end
		end
	end
	for id in LIST do
		if not table.find(C.Order, id) then
			problem(("case %s has a List row but is not in Order"):format(id))
		end
	end
	for _, id in { C.FreeCase, C.FirstWinCase } do
		if LIST[id] == nil then
			problem(("free case %s is not a case"):format(id))
		end
	end
	for _, rarity in C.Rarities do
		if SELL_BACK[rarity] == nil then
			problem(("SellBack has no value for %s"):format(rarity))
		end
	end
	if not RARITY_KNOWN[C.ConfirmSellFrom] then
		problem(("ConfirmSellFrom %s is not a rarity"):format(C.ConfirmSellFrom))
	end
	table.sort(problems)
	return problems
end

do
	local problems = Cases.validate()
	assert(#problems == 0, "Config.Cases: " .. table.concat(problems, "; "))
end

---------------------------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------------------------

--- Opens one case: picks the rarity by weight (rng(OddsTotal)), then a cue uniformly among
--- the case's droppable cues of that rarity (rng(#pool)). `rng(n)` must return a whole number
--- in 1..n. Returns the cue id and its rarity. Errors on an unknown case or an empty pool (the
--- server checks the id first; Cases.validate catches an empty pool): a failed roll must never
--- quietly hand out something, and the server rolls before it takes the case.
function Cases.roll(id: string, rng: (number) -> number): (string, string)
	local case = Cases.get(id)
	assert(case ~= nil, "Cases.roll: unknown case " .. tostring(id))
	local pick = rng(C.OddsTotal)
	assert(
		pick >= 1 and pick <= C.OddsTotal and pick == math.floor(pick),
		"Cases.roll: rng out of range"
	)
	local reached = 0
	for _, rarity in C.Rarities do
		reached += case.Odds[rarity] or 0
		if pick <= reached then
			local pool = Catalog.droppable(id, rarity)
			assert(#pool > 0, ("Cases.roll: %s has no droppable %s cue"):format(id, rarity))
			local index = rng(#pool)
			assert(
				index >= 1 and index <= #pool and index == math.floor(index),
				"Cases.roll: rng out of range"
			)
			return pool[index].Id, rarity
		end
	end
	-- Unreachable while the row adds to OddsTotal (the load-time check).
	error("Cases.roll: " .. id .. " odds do not cover the roll")
end

---------------------------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------------------------

--- True for a count one purchase may name: 1, or the bulk count (the old shop; nothing is sold).
function Cases.isBuyCount(count: any): boolean
	return count == 1 or count == C.BulkCount
end

--- The price of `count` cases (1 or Config.Cases.BulkCount) at unix time `now`:
--- (total, perCase, onSale). Every full bulk lot pays for BulkPayFor cases (9.1). `sale`
--- ({ Case, Percent, EndsAt }, Config.Cases.Sale's shape) takes Percent off this case only
--- while now < EndsAt, rounded half up to whole money; nil or 0% means no sale. Errors on an
--- unknown case or a count that is not a whole number of at least 1: never a free price.
function Cases.price(id: string, count: number, now: number, sale: Sale?): (number, number, boolean)
	local case = Cases.get(id)
	assert(case ~= nil, "Cases.price: unknown case " .. tostring(id))
	assert(
		type(count) == "number" and count >= 1 and count == math.floor(count),
		"Cases.price: bad count " .. tostring(count)
	)
	local perCase = case.Price
	local onSale = false
	if sale and sale.Case == id and sale.Percent > 0 and now < sale.EndsAt then
		local percent = math.clamp(sale.Percent, 0, 100)
		perCase = math.floor(case.Price * (100 - percent) / 100 + 0.5)
		onSale = true
	end
	local lots = count // C.BulkCount
	local paidFor = lots * C.BulkPayFor + count % C.BulkCount
	return perCase * paidFor, perCase, onSale
end

---------------------------------------------------------------------------------------------
-- Selling back and announcements
---------------------------------------------------------------------------------------------

--- Money for selling back one copy (ECONOMY 8): case cues by rarity; 0 for anything that
--- cannot be sold (Exclusive, Unique, Classic, unknown ids).
function Cases.sellValue(cueId: any): number
	local cue = Catalog.get(cueId)
	if cue == nil or cue.Group ~= "Case" or not cue.Sellable then
		return 0
	end
	return SELL_BACK[cue.Rarity] or 0
end

--- True when selling this cue asks "are you sure?" first (Config.Cases.ConfirmSellFrom up).
function Cases.needsConfirm(cueId: any): boolean
	local cue = Catalog.get(cueId)
	if cue == nil or Cases.sellValue(cueId) <= 0 then
		return false
	end
	return Catalog.rarityRank(cue.Rarity) >= Catalog.rarityRank(C.ConfirmSellFrom)
end

--- True when unboxing a cue of this rarity is announced in every server (Mythic, Secret).
function Cases.announces(rarity: string): boolean
	return ANNOUNCE[rarity] == true
end

--- True when unboxing a cue of this rarity is announced in the opener's server only
--- (Config.Cases.AnnounceHere: Legendary).
function Cases.announcesHere(rarity: string): boolean
	return ANNOUNCE_HERE[rarity] == true
end

---------------------------------------------------------------------------------------------
-- The win's Case Drop (economy plan sections 1 and 2; ECONOMY 3.6)
---------------------------------------------------------------------------------------------

--- Whether this win drops a Case Drop, and the tier it is forced to (the first win's Rare
--- Case) or nil for a normal roll. Every real win drops one, except: a loss, solo, a match that
--- was not real, a same-opponent row that forbids it, FreeCasesPerOpponent drops from this
--- account today already, a loser with fewer than FreeCaseLoserMinMatches real matches (the
--- anti-farm rules apply to the first win too), or Play against PC past PcDropsPerDay drops
--- today.
function Cases.dropFor(ctx: DropContext): (boolean, string?)
	if not ctx.won or not ctx.real or ctx.solo then
		return false, nil
	end
	if ctx.pcLimited and ctx.pcDropsToday >= E.PcDropsPerDay then
		return false, nil
	end
	if not ctx.farmAllows then
		return false, nil
	end
	if ctx.casesFromOpponentToday >= E.FreeCasesPerOpponent then
		return false, nil
	end
	if ctx.loserRealMatches < E.FreeCaseLoserMinMatches then
		return false, nil
	end
	if ctx.firstWinEver then
		return true, C.Drop.FirstWin
	end
	return true, nil
end

return Cases
