--!strict
-- BlockOdds (ECONOMY sections 7 and 8): the odds tables the lucky blocks roll, rolling one,
-- sell-back values and announcements. A lucky block kind (Config.LuckyBlocks.Kinds) names the
-- row it rolls (`Odds`); the Mystery block rolls a tier first (Progression/BlockDrop). Pure:
-- no Instances, no Roblox APIs, no clocks and no randomness of its own (the caller passes an
-- rng, so the server uses Random.new() and the tests a seeded generator). Every list is walked
-- in a Config or Catalog array order, never hash order.
--
-- The numbers live in Config.BlockOdds (odds as whole parts of OddsTotal, so each row adds to
-- exactly Config.BlockOdds.OddsTotal). The cues each row drops come from the catalog: every
-- block cue that lists the row and is not vaulted (Catalog.droppable), so vaulting a cue updates
-- the rolls and the odds panels at once (ECONOMY 7.3, 12).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)

local C = Config.BlockOdds

-- Config's literal tables, typed as the maps they are (indexed by a runtime id). Caps: a
-- Unique row's copies ever (the Grand Opening's Firework and Beta Cues, economy v4).
type RowConfig = { Odds: { [string]: number }, Caps: { [string]: number }? }
local LIST: { [string]: RowConfig } = C.List :: any
-- The odds tables outside the ladder (Config.BlockOdds.Extra: Sky, GrandOpening, Starter).
local EXTRA: { string } = C.Extra or {}
local SELL_BACK: { [string]: number } = C.SellBack :: any
local ANNOUNCE: { [string]: boolean } = C.Announce :: any
local ANNOUNCE_HERE: { [string]: boolean } = C.AnnounceHere :: any

export type Row = {
	Id: string,
	Odds: { [string]: number }, -- rarity -> parts of OddsTotal (the Config row itself)
}

-- The Unique rows closed for one player (economy v4 plan 8.5): { [cueId] = true } for a cue
-- they own (Roblox's one-instance rule) or whose copies are all found (its cap). A closed
-- row's share goes to the row's lowest rarity, so the odds still add to 100.
export type Closed = { [string]: boolean }

export type RarityOdds = {
	rarity: string,
	weight: number, -- parts of Config.BlockOdds.OddsTotal
	percent: number,
	display: string, -- "64.3%", "0.003%"
}

export type CueOdds = {
	id: string,
	rarity: string,
	percent: number, -- the rarity's percent split evenly among its droppable cues (7.3)
	display: string, -- "6.667%", "0.047%"
}

local BlockOdds = {}

---------------------------------------------------------------------------------------------
-- Rows and odds
---------------------------------------------------------------------------------------------

local RARITY_KNOWN: { [string]: boolean } = {}
for _, rarity in C.Rarities do
	RARITY_KNOWN[rarity] = true
end

--- An odds row by id (Id, Odds); nil for an unknown id. Read live from Config.
function BlockOdds.get(id: any): Row?
	if type(id) ~= "string" or not (table.find(C.Order, id) or table.find(EXTRA, id)) then
		return nil
	end
	local row = LIST[id]
	if row == nil then
		return nil
	end
	return { Id = id, Odds = row.Odds }
end

--- The row with the Unique rows in `closed` moved to its lowest rarity (a fresh Odds table;
--- the row itself when nothing is closed). nil for an unknown id.
function BlockOdds.rowFor(id: any, closed: Closed?): Row?
	local row = BlockOdds.get(id)
	if row == nil or closed == nil or next(closed) == nil then
		return row
	end
	local odds = table.clone(row.Odds)
	local floor: string? = nil
	for _, rarity in C.Rarities do
		if (odds[rarity] or 0) > 0 then
			floor = rarity
			break
		end
	end
	if floor == nil then
		return row
	end
	for cue, on in closed do
		local weight = odds[cue]
		if on == true and not RARITY_KNOWN[cue] and weight ~= nil and weight > 0 then
			odds[floor] += weight
			odds[cue] = nil
		end
	end
	return { Id = row.Id, Odds = odds }
end

--- A row's caps on its Unique rows ({ [cueId] = copies ever }; empty for most rows).
function BlockOdds.caps(id: any): { [string]: number }
	local row = if BlockOdds.get(id) then LIST[id] else nil
	return if row ~= nil and row.Caps ~= nil then table.clone(row.Caps) else {}
end

--- Which of a row's Unique rows are closed for one player: `owns(cueId)` (they have one) or
--- `found(cueId)` (copies handed out so far, nil unknown) at the row's cap.
function BlockOdds.closedFor(
	id: any,
	owns: ((string) -> boolean)?,
	found: ((string) -> number?)?
): Closed
	local closed: Closed = {}
	local caps = BlockOdds.caps(id)
	for _, unique in BlockOdds.uniqueRows(id) do
		local cap = caps[unique.cue]
		local n = if found then found(unique.cue) else nil
		if (owns ~= nil and owns(unique.cue)) or (cap ~= nil and n ~= nil and n >= cap) then
			closed[unique.cue] = true
		end
	end
	return closed
end

--- The ladder's rows in order (Config.BlockOdds.Order), then the Extra rows.
function BlockOdds.list(): { Row }
	local list = {}
	for _, id in C.Order do
		local row = BlockOdds.get(id)
		if row then
			table.insert(list, row)
		end
	end
	for _, id in EXTRA do
		local row = BlockOdds.get(id)
		if row then
			table.insert(list, row)
		end
	end
	return list
end

-- A percent as every odds display shows it, rounded plainly (designer, 2026-10-08: "dont show
-- full percentage just round it"): from 10% a whole number ("52%"), from 1% one decimal
-- ("6.8%", "9%"), from 0.1% two ("0.33%"), and under that one significant digit ("0.05%",
-- "0.0008%"), so a chance that can happen never reads as 0%, and one under 100% never as 100%.
local function percentText(percent: number): string
	if type(percent) ~= "number" or percent ~= percent or percent <= 0 then
		return "0%"
	end
	local decimals
	if percent >= 10 then
		decimals = 0
	elseif percent >= 1 then
		decimals = 1
	elseif percent >= 0.1 then
		decimals = 2
	else
		-- 0.046 -> floor(log10) = -2 -> 2 decimals shows "0.05".
		decimals = math.min(-math.floor(math.log10(percent)), 10)
	end
	local text = string.format("%." .. decimals .. "f", percent)
	if percent < 100 and (tonumber(text) or 0) >= 100 then
		text = "99"
	end
	if text:find(".", 1, true) then
		text = text:gsub("0+$", ""):gsub("%.$", "")
	end
	return text .. "%"
end
BlockOdds.percentText = percentText

--- The N of "1 in N" for a chance of `percent` (economy v4 plan 18.2: rounded so it never looks
--- better than true): 100 / percent rounded up, to three significant figures from 1,000 on
--- (1 in 131,718 -> 132,000; 1 in 1,111.1 -> 1,120), else to a whole number (1 in 238.1 -> 239).
--- nil for no chance or a chance over 100%.
function BlockOdds.oneIn(percent: number): number?
	if type(percent) ~= "number" or percent ~= percent or percent <= 0 or percent > 100 then
		return nil
	end
	-- A hair under, so float noise never lifts an exact one (100 / 0.0001) to the next step.
	local n = 100 / percent * (1 - 1e-9)
	if n < 1000 then
		return math.max(1, math.ceil(n))
	end
	local step = 10 ^ (math.floor(math.log10(n)) - 2)
	return math.ceil(n / step) * step
end

--- The row's rarities with a share, bottom rarity first: { rarity, weight, percent, display }.
--- Empty for an unknown row. `closed`: this player's closed Unique rows (BlockOdds.rowFor).
function BlockOdds.odds(id: string, closed: Closed?): { RarityOdds }
	local row = BlockOdds.rowFor(id, closed)
	local list = {}
	if row == nil then
		return list
	end
	for _, rarity in C.Rarities do
		local weight = row.Odds[rarity] or 0
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

--- A Unique row of an odds table (a key that is a cue id, not a rarity: the Grand Opening
--- block's two Unique cues), bottom first by weight, sorted by id among equals.
export type UniqueOdds = { cue: string, weight: number, percent: number, display: string }

--- The row's Unique rows (cue ids with a share), in sorted id order. Empty for most rows.
--- `closed`: this player's closed rows are left out (BlockOdds.rowFor).
function BlockOdds.uniqueRows(id: string, closed: Closed?): { UniqueOdds }
	local row = BlockOdds.rowFor(id, closed)
	local list: { UniqueOdds } = {}
	if row == nil then
		return list
	end
	local ids = {}
	for key in row.Odds do
		if not RARITY_KNOWN[key] then
			table.insert(ids, key)
		end
	end
	table.sort(ids)
	for _, cue in ids do
		local weight = row.Odds[cue] or 0
		if weight > 0 then
			local percent = weight * 100 / C.OddsTotal
			table.insert(list, {
				cue = cue,
				weight = weight,
				percent = percent,
				display = percentText(percent),
			})
		end
	end
	return list
end

--- Whether rolling row `oddsId` may give cue `cueId`: one of its Unique rows, or a droppable
--- block cue of a rarity the row has a share in.
function BlockOdds.canDrop(oddsId: string, cueId: string): boolean
	local row = BlockOdds.get(oddsId)
	if row == nil then
		return false
	end
	for _, unique in BlockOdds.uniqueRows(oddsId) do
		if unique.cue == cueId then
			return true
		end
	end
	local cue = Catalog.get(cueId)
	if cue == nil or cue.Group ~= "Block" or (row.Odds[cue.Rarity] or 0) <= 0 then
		return false
	end
	for _, other in Catalog.droppable(oddsId, cue.Rarity) do
		if other.Id == cueId then
			return true
		end
	end
	return false
end

--- The highest rarity the row can drop (a share above 0 with a droppable cue), or nil.
function BlockOdds.topRarity(id: string): string?
	local row = BlockOdds.get(id)
	if row == nil then
		return nil
	end
	for i = #C.Rarities, 1, -1 do
		local rarity = C.Rarities[i]
		if (row.Odds[rarity] or 0) > 0 and #Catalog.droppable(id, rarity) > 0 then
			return rarity
		end
	end
	return nil
end

--- The lowest rarity the row can drop (its guarantee: "Uncommon or better"), or nil.
function BlockOdds.minRarity(id: string): string?
	local odds = BlockOdds.odds(id)
	return if #odds > 0 then odds[1].rarity else nil
end

--- Every cue the row can drop with its percent (ECONOMY 7.3: the rarity's percent split
--- evenly among that rarity's droppable cues), grouped by rarity bottom first, catalog order
--- inside a rarity. The percents add to 100 (within float rounding) when `uniques` is true:
--- then the row's Unique rows follow as rarity "Unique" (the Grand Opening's Firework and Beta
--- Cues; the reel shows them). Vaulted cues are left out.
function BlockOdds.cueOdds(id: string, closed: Closed?, uniques: boolean?): { CueOdds }
	local list = {}
	for _, entry in BlockOdds.odds(id, closed) do
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
	if uniques == true then
		for _, unique in BlockOdds.uniqueRows(id, closed) do
			table.insert(list, {
				id = unique.cue,
				rarity = "Unique",
				percent = unique.percent,
				display = unique.display,
			})
		end
	end
	return list
end

export type CueGroup = {
	rarity: string, -- a rarity, or "Unique" for one capped Unique cue
	percent: number, -- the group's chance
	each: number, -- each of its cues' chance (they split the group's evenly)
	cues: { string }, -- its cue ids (the catalog's order; one for a Unique)
	closed: boolean, -- a Unique this player can't get (owned, or every copy found): 0%
}

--- A block's outcomes as its odds list shows them (Roblox's paid-random-items rules: every
--- item with its chance): each rarity with a share, bottom first, with its cues, then each
--- capped Unique cue on its own, rarest last. `closed`: this player's closed Unique rows; their
--- share is already in the lowest rarity's (BlockOdds.rowFor) and they are listed at 0%.
function BlockOdds.cueGroups(id: string, closed: Closed?): { CueGroup }
	local groups: { CueGroup } = {}
	for _, entry in BlockOdds.odds(id, closed) do
		local ids: { string } = {}
		for _, cue in Catalog.droppable(id, entry.rarity) do
			table.insert(ids, cue.Id)
		end
		if #ids > 0 then
			table.insert(groups, {
				rarity = entry.rarity,
				percent = entry.percent,
				each = entry.percent / #ids,
				cues = ids,
				closed = false,
			})
		end
	end
	local uniques = BlockOdds.uniqueRows(id)
	table.sort(uniques, function(a, b)
		return a.weight > b.weight
	end)
	for _, unique in uniques do
		local shut = closed ~= nil and closed[unique.cue] == true
		local percent = if shut then 0 else unique.percent
		table.insert(groups, {
			rarity = "Unique",
			percent = percent,
			each = percent,
			cues = { unique.cue },
			closed = shut,
		})
	end
	return groups
end

--- Everything wrong with the odds rows against the catalog, sorted (empty when all is well):
--- a row missing from Order or List, an unknown rarity, a weight that is not a whole number,
--- a row that does not add to exactly OddsTotal, or a rarity with a share but no droppable cue.
--- Checked when this module loads; the server may call it again after vaulting a cue at runtime.
function BlockOdds.validate(): { string }
	local problems = {}
	local function problem(text: string)
		table.insert(problems, text)
	end
	local every = table.clone(C.Order)
	for _, id in EXTRA do
		table.insert(every, id)
	end
	for _, id in every do
		local row = LIST[id]
		if row == nil then
			problem(("odds row %s is in Order but has no List row"):format(id))
			continue
		end
		-- Walk the row to catch unknown rarity names and bad weights (the sum does not depend
		-- on the order of the walk, and the problems are sorted below). A key that is not a
		-- rarity must be a Unique cue's id (a Unique row).
		local sum = 0
		for rarity, weight in row.Odds do
			if not RARITY_KNOWN[rarity] then
				local cue = Catalog.get(rarity)
				if cue == nil or cue.Group ~= "Unique" then
					problem(
						("odds row %s has odds for unknown rarity %s"):format(id, tostring(rarity))
					)
				end
			end
			if type(weight) ~= "number" or weight < 0 or weight ~= math.floor(weight) then
				problem(
					("odds row %s: %s weight %s is not a whole number"):format(
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
			problem(("odds row %s adds to %d, not %d"):format(id, sum, C.OddsTotal))
		end
		for _, rarity in C.Rarities do
			if (row.Odds[rarity] or 0) > 0 and #Catalog.droppable(id, rarity) == 0 then
				problem(
					("odds row %s has a %s share but no droppable %s cue"):format(
						id,
						rarity,
						rarity
					)
				)
			end
		end
	end
	for id in LIST do
		if not (table.find(C.Order, id) or table.find(EXTRA, id)) then
			problem(("odds row %s has a List row but is not in Order"):format(id))
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
	local problems = BlockOdds.validate()
	assert(#problems == 0, "Config.BlockOdds: " .. table.concat(problems, "; "))
end

---------------------------------------------------------------------------------------------
-- Rolling
---------------------------------------------------------------------------------------------

--- Rolls one row: picks the rarity by weight (rng(OddsTotal)), then a cue uniformly among the
--- row's droppable cues of that rarity (rng(#pool)). `rng(n)` must return a whole number in
--- 1..n. Returns the cue id and its rarity. Errors on an unknown row or an empty pool (the
--- server checks the id first; BlockOdds.validate catches an empty pool): a failed roll must
--- never quietly hand out something, and the server rolls before it takes the block.
--- `closed`: this player's closed Unique rows roll as the row's lowest rarity instead.
function BlockOdds.roll(id: string, rng: (number) -> number, closed: Closed?): (string, string)
	local row = BlockOdds.rowFor(id, closed)
	assert(row ~= nil, "BlockOdds.roll: unknown odds row " .. tostring(id))
	local pick = rng(C.OddsTotal)
	assert(
		pick >= 1 and pick <= C.OddsTotal and pick == math.floor(pick),
		"BlockOdds.roll: rng out of range"
	)
	local reached = 0
	for _, rarity in C.Rarities do
		reached += row.Odds[rarity] or 0
		if pick <= reached then
			local pool = Catalog.droppable(id, rarity)
			assert(#pool > 0, ("BlockOdds.roll: %s has no droppable %s cue"):format(id, rarity))
			local index = rng(#pool)
			assert(
				index >= 1 and index <= #pool and index == math.floor(index),
				"BlockOdds.roll: rng out of range"
			)
			return pool[index].Id, rarity
		end
	end
	-- The Unique rows (the Grand Opening block's two cues), after the rarities.
	for _, unique in BlockOdds.uniqueRows(id, closed) do
		reached += unique.weight
		if pick <= reached then
			return unique.cue, "Unique"
		end
	end
	-- Unreachable while the row adds to OddsTotal (the load-time check).
	error("BlockOdds.roll: " .. id .. " odds do not cover the roll")
end

---------------------------------------------------------------------------------------------
-- Selling back and announcements
---------------------------------------------------------------------------------------------

--- Money for selling back one copy (ECONOMY 8): block cues by rarity; 0 for anything that
--- cannot be sold (Exclusive, Unique, Classic, unknown ids).
function BlockOdds.sellValue(cueId: any): number
	local cue = Catalog.get(cueId)
	if cue == nil or cue.Group ~= "Block" or not cue.Sellable then
		return 0
	end
	return SELL_BACK[cue.Rarity] or 0
end

--- True when selling this cue asks "are you sure?" first (Config.BlockOdds.ConfirmSellFrom up).
function BlockOdds.needsConfirm(cueId: any): boolean
	local cue = Catalog.get(cueId)
	if cue == nil or BlockOdds.sellValue(cueId) <= 0 then
		return false
	end
	return Catalog.rarityRank(cue.Rarity) >= Catalog.rarityRank(C.ConfirmSellFrom)
end

--- True when unboxing a cue of this rarity is announced in every server (Mythic, Secret).
function BlockOdds.announces(rarity: string): boolean
	return ANNOUNCE[rarity] == true
end

--- True when unboxing a cue of this rarity is announced in the opener's server only
--- (Config.BlockOdds.AnnounceHere: Legendary).
function BlockOdds.announcesHere(rarity: string): boolean
	return ANNOUNCE_HERE[rarity] == true
end

return BlockOdds
