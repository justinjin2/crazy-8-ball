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

-- Config's literal tables, typed as the maps they are (indexed by a runtime id).
type RowConfig = { Odds: { [string]: number } }
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

-- A percent for the odds panels: three decimals ("6.667%", "1.625%"), trailing zeros cut
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
BlockOdds.percentText = percentText

--- The row's rarities with a share, bottom rarity first: { rarity, weight, percent, display }.
--- Empty for an unknown row.
function BlockOdds.odds(id: string): { RarityOdds }
	local row = BlockOdds.get(id)
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
function BlockOdds.uniqueRows(id: string): { UniqueOdds }
	local row = BlockOdds.get(id)
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
--- inside a rarity. The percents add to 100 (within float rounding). Vaulted cues are left out.
function BlockOdds.cueOdds(id: string): { CueOdds }
	local list = {}
	for _, entry in BlockOdds.odds(id) do
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
function BlockOdds.roll(id: string, rng: (number) -> number): (string, string)
	local row = BlockOdds.get(id)
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
	for _, unique in BlockOdds.uniqueRows(id) do
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
