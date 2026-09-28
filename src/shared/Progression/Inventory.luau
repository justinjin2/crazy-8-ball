--!strict
-- The inventory, selling back and the Index, on a save-like table (ECONOMY sections 8 and 18).
-- Pure: no Instances, no Roblox APIs. Every function reads or changes the table it is given in
-- place; the server's PlayerData calls them inside its own validated mutations, and adds any
-- money these return through its money mutation (nothing here touches Money).
--
-- The part of the save these use (SaveSchema v2):
--   Inventory = { Cues = { [cueId] = count }, Unique = { [cueId] = copyNumber },
--                 Cases = { [caseId] = count }, New = { [cueId] = true } }
--   Index = { Seen = { [cueId] = true }, Rows = { [rarity] = true } }
--   Titles = { [titleId] = true }
--   Equipped = { Cue = cueId }
-- Counts are whole numbers of at least 1 (a key is removed at 0). Classic is always owned and
-- never stored. A cue is in the Index once ever owned (Index.Seen); selling keeps it there.
--
-- Reads never write (a missing section reads as empty), and every list is built by walking the
-- catalog or Config arrays, so stray keys in a save are ignored and nothing depends on hash
-- order.
local Config = require(script.Parent.Parent.Config)
local Strings = require(script.Parent.Parent.Strings)
local Catalog = require(script.Parent.Catalog)
local Cases = require(script.Parent.Cases)

type IndexReward = { Money: number }
local INDEX_ROWS: { [string]: IndexReward } = Config.Index.Rows :: any
local FIND_MONEY: { [string]: number } = Config.Index.FindMoney :: any
local TITLE_NAMES: { [string]: string } = Strings.Items.Titles :: any

export type Duplicate = {
	id: string,
	extra: number, -- copies above the one kept
	value: number, -- money for selling all of them
}

export type Sold = { id: string, count: number, money: number }

export type IndexRow = {
	rarity: string, -- a rarity, "Exclusive" or "Unique"
	have: number, -- cues of it ever owned
	total: number, -- cues of it in the catalog (vaulted ones included)
	complete: boolean,
	claimed: boolean,
	reward: { money: number }?, -- nil for a row with no reward (Legendary up, Exclusive, Unique)
}

export type Snapshot = {
	cues: { { id: string, count: number, new: boolean, copy: number? } },
	cases: { { id: string, count: number } },
	equipped: string,
	seen: { string },
	rows: { IndexRow },
	titles: { string },
}

local Inventory = {}

-- The Index's rows: the rarity ladder, then the two groups outside it.
local INDEX_GROUPS: { string } = table.clone(Config.Cases.Rarities)
table.insert(INDEX_GROUPS, "Exclusive")
table.insert(INDEX_GROUPS, "Unique")

-- The catalog rarest first (Unique, Secret ... Legendary, Exclusive, Epic ... Common, Classic),
-- catalog order inside a rarity: the snapshot's order.
local RAREST_FIRST: { Catalog.Cue } = {}
do
	local position: { [string]: number } = {}
	for i, cue in Catalog.list() do
		position[cue.Id] = i
		table.insert(RAREST_FIRST, cue)
	end
	table.sort(RAREST_FIRST, function(a, b)
		local ra, rb = Catalog.rarityRank(a.Rarity), Catalog.rarityRank(b.Rarity)
		if ra ~= rb then
			return ra > rb
		end
		return position[a.Id] < position[b.Id]
	end)
end

---------------------------------------------------------------------------------------------
-- Save access
---------------------------------------------------------------------------------------------

local EMPTY: { [string]: any } = table.freeze({})

-- save[section][key] (or save[section]) when it is a table, else an empty read-only table.
local function readMap(save: any, section: string, key: string?): { [string]: any }
	local t = if type(save) == "table" then save[section] else nil
	if key ~= nil then
		t = if type(t) == "table" then t[key] else nil
	end
	return if type(t) == "table" then t else EMPTY
end

-- The same, creating any missing table on the way, for writes.
local function writeMap(save: any, section: string, key: string?): { [string]: any }
	local t = save[section]
	if type(t) ~= "table" then
		t = {}
		save[section] = t
	end
	if key == nil then
		return t
	end
	local inner = t[key]
	if type(inner) ~= "table" then
		inner = {}
		t[key] = inner
	end
	return inner
end

-- A whole number of at least 1.
local function isCount(n: any): boolean
	return type(n) == "number" and n >= 1 and n == math.floor(n) and n < math.huge
end

-- A stored count, 0 for anything that is not a count.
local function storedCount(map: { [string]: any }, id: string): number
	local n = map[id]
	return if isCount(n) then n else 0
end

---------------------------------------------------------------------------------------------
-- Cues
---------------------------------------------------------------------------------------------

--- How many of a cue the save holds: Classic always 1, a Unique cue 1 or 0, unknown ids 0.
function Inventory.count(save: any, id: any): number
	local cue = Catalog.get(id)
	if cue == nil then
		return 0
	end
	if cue.Group == "Default" then
		return 1
	end
	if cue.Group == "Unique" then
		return if isCount(readMap(save, "Inventory", "Unique")[cue.Id]) then 1 else 0
	end
	return storedCount(readMap(save, "Inventory", "Cues"), cue.Id)
end

--- True when the save owns at least one of the cue (Classic always).
function Inventory.owns(save: any, id: any): boolean
	return Inventory.count(save, id) > 0
end

--- A Unique cue's copy number (#412), or nil when not owned or not Unique.
function Inventory.copy(save: any, id: any): number?
	local cue = Catalog.get(id)
	if cue == nil or cue.Group ~= "Unique" then
		return nil
	end
	local copy = readMap(save, "Inventory", "Unique")[cue.Id]
	return if isCount(copy) then copy else nil
end

--- The equipped cue: the saved one while it is owned, else Classic.
function Inventory.equipped(save: any): string
	local id = readMap(save, "Equipped").Cue
	return if Inventory.owns(save, id) then id else Catalog.Default
end

-- Ever owned: in Index.Seen, or held now (a save whose Seen was never filled in still counts
-- what it holds).
local function everOwned(save: any, id: string): boolean
	return readMap(save, "Index", "Seen")[id] == true or Inventory.owns(save, id)
end

--- True when the cue is in the save's Index: owned now or ever (sold ones stay).
function Inventory.found(save: any, id: any): boolean
	local cue = Catalog.get(id)
	return cue ~= nil and everOwned(save, cue.Id)
end

--- The finder's money for a cue (Config.Index.FindMoney by its rarity or group): paid once,
--- the first time a player gets it. 0 for Classic and unknown ids.
function Inventory.findMoney(id: any): number
	local cue = Catalog.get(id)
	if cue == nil or cue.Group == "Default" then
		return 0
	end
	return FIND_MONEY[cue.Rarity] or 0
end

-- Marks a cue ever owned and NEW.
local function markGot(save: any, id: string)
	writeMap(save, "Index", "Seen")[id] = true
	writeMap(save, "Inventory", "New")[id] = true
end

--- Adds n (default 1) copies of a case or Exclusive cue, marking it in the Index and NEW.
--- False (and nothing changes) for an unknown id, Classic, a Unique cue (addUnique) or a
--- count that is not a whole number of at least 1. The second answer is true when the cue is
--- new to the Index (never owned before): the caller pays its finder's money (findMoney).
function Inventory.addCue(save: any, id: any, n: number?): (boolean, boolean)
	local cue = Catalog.get(id)
	local amount = n or 1
	if cue == nil or cue.Group == "Default" or cue.Group == "Unique" or not isCount(amount) then
		return false, false
	end
	local first = not everOwned(save, cue.Id)
	local cues = writeMap(save, "Inventory", "Cues")
	cues[cue.Id] = storedCount(cues, cue.Id) + amount
	markGot(save, cue.Id)
	return true, first
end

--- Gives a Unique cue with its copy number. False for anything not Unique, a bad copy
--- number, or a Unique cue already owned (one per player). The second answer is true when it
--- is new to the Index, as addCue's.
function Inventory.addUnique(save: any, id: any, copy: number): (boolean, boolean)
	local cue = Catalog.get(id)
	if cue == nil or cue.Group ~= "Unique" or not isCount(copy) or Inventory.owns(save, cue.Id) then
		return false, false
	end
	local first = not everOwned(save, cue.Id)
	writeMap(save, "Inventory", "Unique")[cue.Id] = copy
	markGot(save, cue.Id)
	return true, first
end

--- Takes n (default 1) copies away (a Unique cue: n = 1). Reasons: "Unknown" (not a catalog
--- id), "BadCount", "Default" (Classic can't go), "NotOwned", "TooMany". When the last copy
--- goes its NEW tag goes too and, if it was equipped, Classic is equipped instead (a save never
--- equips a cue it doesn't own). The Index keeps it.
function Inventory.removeCue(save: any, id: any, n: number?): (boolean, string?)
	local cue = Catalog.get(id)
	local amount = n or 1
	if cue == nil then
		return false, "Unknown"
	end
	if not isCount(amount) then
		return false, "BadCount"
	end
	if cue.Group == "Default" then
		return false, "Default"
	end
	local have = Inventory.count(save, cue.Id)
	if have == 0 then
		return false, "NotOwned"
	end
	if amount > have then
		return false, "TooMany"
	end
	local left = have - amount
	if cue.Group == "Unique" then
		writeMap(save, "Inventory", "Unique")[cue.Id] = nil
	else
		writeMap(save, "Inventory", "Cues")[cue.Id] = if left > 0 then left else nil
	end
	if left == 0 then
		local new = readMap(save, "Inventory", "New")
		if new[cue.Id] ~= nil then
			new[cue.Id] = nil
		end
		if readMap(save, "Equipped").Cue == cue.Id then
			writeMap(save, "Equipped").Cue = Catalog.Default
		end
	end
	return true, nil
end

--- Equips an owned cue (Classic always). False for anything not owned.
function Inventory.equip(save: any, id: any): boolean
	local cue = Catalog.get(id)
	if cue == nil or not Inventory.owns(save, cue.Id) then
		return false
	end
	writeMap(save, "Equipped").Cue = cue.Id
	return true
end

--- Clears the NEW tag of each id in the array; returns how many were cleared.
function Inventory.markSeen(save: any, ids: any): number
	if type(ids) ~= "table" then
		return 0
	end
	local new = readMap(save, "Inventory", "New")
	local cleared = 0
	for _, id in ipairs(ids) do
		if type(id) == "string" and new[id] ~= nil then
			new[id] = nil
			cleared += 1
		end
	end
	return cleared
end

---------------------------------------------------------------------------------------------
-- Cases
---------------------------------------------------------------------------------------------

--- Unopened cases of one type.
function Inventory.caseCount(save: any, caseId: any): number
	if Cases.get(caseId) == nil then
		return 0
	end
	return storedCount(readMap(save, "Inventory", "Cases"), caseId)
end

--- Adds n (default 1) unopened cases of a known type (enabled in the shop or not).
function Inventory.addCases(save: any, caseId: any, n: number?): boolean
	local amount = n or 1
	if Cases.get(caseId) == nil or not isCount(amount) then
		return false
	end
	local cases = writeMap(save, "Inventory", "Cases")
	cases[caseId] = storedCount(cases, caseId) + amount
	return true
end

--- Takes n (default 1) unopened cases; false (and nothing changes) without enough of them.
function Inventory.takeCases(save: any, caseId: any, n: number?): boolean
	local amount = n or 1
	if not isCount(amount) then
		return false
	end
	local have = Inventory.caseCount(save, caseId)
	if have < amount then
		return false
	end
	writeMap(save, "Inventory", "Cases")[caseId] = if have > amount then have - amount else nil
	return true
end

---------------------------------------------------------------------------------------------
-- Selling back (ECONOMY 8)
---------------------------------------------------------------------------------------------

--- Whether n (default 1) copies can be sold. Reasons: "Unknown" (not a catalog id),
--- "BadCount", "NotSellable" (Exclusive, Unique, Classic), "NotOwned", "TooMany", "Equipped"
--- (the last copy of the equipped cue; selling down to one is fine).
function Inventory.canSell(save: any, id: any, n: number?): (boolean, string?)
	local cue = Catalog.get(id)
	local amount = n or 1
	if cue == nil then
		return false, "Unknown"
	end
	if not isCount(amount) then
		return false, "BadCount"
	end
	if Cases.sellValue(cue.Id) <= 0 then
		return false, "NotSellable"
	end
	local have = Inventory.count(save, cue.Id)
	if have == 0 then
		return false, "NotOwned"
	end
	if amount > have then
		return false, "TooMany"
	end
	if amount == have and Inventory.equipped(save) == cue.Id then
		return false, "Equipped"
	end
	return true, nil
end

--- Sells n (default 1) copies: removes them and returns (true, money), or (false, reason) from
--- canSell. The money is NOT added here: the caller adds it through its money mutation.
function Inventory.sell(save: any, id: any, n: number?): (boolean, number | string)
	local ok, reason = Inventory.canSell(save, id, n)
	if not ok then
		return false, reason :: string
	end
	local amount = n or 1
	Inventory.removeCue(save, id, amount)
	return true, amount * Cases.sellValue(id)
end

--- Case cues held more than once, in catalog order: { id, extra (count - 1), value }.
function Inventory.duplicates(save: any): { Duplicate }
	local list = {}
	for _, cue in Catalog.list() do
		if cue.Group == "Case" then
			local extra = Inventory.count(save, cue.Id) - 1
			if extra > 0 then
				table.insert(
					list,
					{ id = cue.Id, extra = extra, value = extra * Cases.sellValue(cue.Id) }
				)
			end
		end
	end
	return list
end

--- Sells duplicates, keeping one of each: only `id`'s extras when given, else every case
--- cue's. Returns the total money (for the caller to add) and what was sold, catalog order.
function Inventory.sellDuplicates(save: any, id: any?): (number, { Sold })
	local total = 0
	local sold = {}
	for _, dup in Inventory.duplicates(save) do
		if id == nil or dup.id == id then
			local ok, money = Inventory.sell(save, dup.id, dup.extra)
			if ok and type(money) == "number" then
				total += money
				table.insert(sold, { id = dup.id, count = dup.extra, money = money })
			end
		end
	end
	return total, sold
end

---------------------------------------------------------------------------------------------
-- The Index (ECONOMY 18)
---------------------------------------------------------------------------------------------

--- Every Index row: the rarities Common ... Secret, then Exclusive and Unique. A row is
--- complete when every catalog cue of it has ever been owned (vaulted ones count too).
function Inventory.indexRows(save: any): { IndexRow }
	local claimed = readMap(save, "Index", "Rows")
	local rows = {}
	for _, rarity in INDEX_GROUPS do
		local cues = Catalog.ofRarity(rarity)
		local have = 0
		for _, cue in cues do
			if everOwned(save, cue.Id) then
				have += 1
			end
		end
		local reward = INDEX_ROWS[rarity]
		table.insert(rows, {
			rarity = rarity,
			have = have,
			total = #cues,
			complete = #cues > 0 and have == #cues,
			claimed = claimed[rarity] == true,
			reward = if reward then { money = reward.Money } else nil,
		})
	end
	return rows
end

--- Claims a complete row's reward once: marks the row and returns (true, { money }) with the
--- money for the caller to add. Reasons: "Unknown" (not a rarity), "NoReward" (a row with no
--- reward: Legendary, Mythic, Secret, Exclusive, Unique), "Claimed", "Incomplete".
function Inventory.claimRow(save: any, rarity: any): (boolean, any)
	if type(rarity) ~= "string" or not table.find(INDEX_GROUPS, rarity) then
		return false, "Unknown"
	end
	local reward = INDEX_ROWS[rarity]
	if reward == nil then
		return false, "NoReward"
	end
	if readMap(save, "Index", "Rows")[rarity] == true then
		return false, "Claimed"
	end
	for _, row in Inventory.indexRows(save) do
		if row.rarity == rarity and not row.complete then
			return false, "Incomplete"
		end
	end
	writeMap(save, "Index", "Rows")[rarity] = true
	return true, { money = reward.Money }
end

---------------------------------------------------------------------------------------------
-- Snapshot for the client
---------------------------------------------------------------------------------------------

--- Everything the Inventory and Index screens need, as fresh plain data a RemoteEvent can
--- carry (strings, numbers, booleans, gapless arrays, string-keyed tables; nothing shared with
--- the save):
---   cues      owned cues, rarest first then catalog order, Classic last: { id, count, new, copy? }
---   cases     unopened cases in shop order: { id, count }
---   equipped  the equipped cue id
---   seen      every cue ever owned (Classic left out), catalog order
---   rows      Inventory.indexRows
---   titles    earned title ids Strings knows (the first Reyes'), by id; the old Index rows'
---             "Collector" titles stay in old saves but are no longer listed
function Inventory.snapshot(save: any): Snapshot
	local new = readMap(save, "Inventory", "New")
	local cues = {}
	for _, cue in RAREST_FIRST do
		local count = Inventory.count(save, cue.Id)
		if count > 0 then
			table.insert(cues, {
				id = cue.Id,
				count = count,
				new = new[cue.Id] == true,
				copy = Inventory.copy(save, cue.Id),
			})
		end
	end

	local cases = {}
	for _, caseId in Config.Cases.Order do
		local count = Inventory.caseCount(save, caseId)
		if count > 0 then
			table.insert(cases, { id = caseId, count = count })
		end
	end

	local seen = {}
	for _, cue in Catalog.list() do
		if cue.Group ~= "Default" and everOwned(save, cue.Id) then
			table.insert(seen, cue.Id)
		end
	end

	-- Titles: only ids Strings knows (so the list stays small and every one can be shown).
	local titles = {}
	for titleId, value in readMap(save, "Titles") do
		if type(titleId) == "string" and value == true and TITLE_NAMES[titleId] then
			table.insert(titles, titleId)
		end
	end
	table.sort(titles)

	return {
		cues = cues,
		cases = cases,
		equipped = Inventory.equipped(save),
		seen = seen,
		rows = Inventory.indexRows(save),
		titles = titles,
	}
end

return Inventory
