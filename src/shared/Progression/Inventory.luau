--!strict
-- The inventory, selling back and the Index, on a save-like table (ECONOMY sections 8 and 18).
-- Pure: no Instances, no Roblox APIs. Every function reads or changes the table it is given in
-- place; the server's PlayerData calls them inside its own validated mutations, and adds any
-- money these return through its money mutation (nothing here touches Money).
--
-- The part of the save these use (SaveSchema v6):
--   Inventory = { Cues = { [cueId] = count }, PaidCues = { [cueId] = count of them paid for },
--                 Unique = { [cueId] = copyNumber }, PaidUnique = { [cueId] = true },
--                 Cases = { [caseId] = ready count }, PaidCases = { [caseId] = ready count },
--                 Timers = { { Case, At, Paid } }, New = { [cueId] = true } }
-- Paid origin (economy plan section 4): a case bought with money or Robux, and every cue it
-- gives, is paid; trading paid items may be blocked by region (Roblox's rules). A timed case
-- sits in Timers until its At (a unix time), then joins its ready stack (finishTimers).
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
	timers: { { id: string, readyAt: number, paid: boolean } },
	equipped: string,
	seen: { string },
	rows: { IndexRow },
	titles: { string },
}

local Inventory = {}

-- removeCue's last count of paid copies taken (Inventory.removedPaid).
local lastRemovedPaid = 0

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

--- Adds n (default 1) copies of a case or Exclusive cue, marking it in the Index and NEW;
--- `paid` counts them as paid origin. False (and nothing changes) for an unknown id, Classic, a
--- Unique cue (addUnique) or a count that is not a whole number of at least 1. The second
--- answer is true when the cue is new to the Index (never owned before): the caller pays its
--- finder's money (findMoney).
function Inventory.addCue(save: any, id: any, n: number?, paid: boolean?): (boolean, boolean)
	local cue = Catalog.get(id)
	local amount = n or 1
	if cue == nil or cue.Group == "Default" or cue.Group == "Unique" or not isCount(amount) then
		return false, false
	end
	local first = not everOwned(save, cue.Id)
	local cues = writeMap(save, "Inventory", "Cues")
	cues[cue.Id] = storedCount(cues, cue.Id) + amount
	if paid then
		local paidCues = writeMap(save, "Inventory", "PaidCues")
		paidCues[cue.Id] = storedCount(paidCues, cue.Id) + amount
	end
	markGot(save, cue.Id)
	return true, first
end

--- How many of the copies held are paid origin (a Unique cue: 1 when it was bought).
function Inventory.paidCount(save: any, id: any): number
	local cue = Catalog.get(id)
	if cue == nil then
		return 0
	elseif cue.Group == "Unique" then
		local paid = readMap(save, "Inventory", "PaidUnique")[cue.Id] == true
		return if paid and Inventory.owns(save, cue.Id) then 1 else 0
	end
	return math.min(
		storedCount(readMap(save, "Inventory", "PaidCues"), cue.Id),
		Inventory.count(save, cue.Id)
	)
end

--- Gives a Unique cue with its copy number (`paid`: bought, paid origin). False for anything
--- not Unique, a bad copy number, or a Unique cue already owned (one per player). The second
--- answer is true when it is new to the Index, as addCue's.
function Inventory.addUnique(save: any, id: any, copy: number, paid: boolean?): (boolean, boolean)
	local cue = Catalog.get(id)
	if cue == nil or cue.Group ~= "Unique" or not isCount(copy) or Inventory.owns(save, cue.Id) then
		return false, false
	end
	local first = not everOwned(save, cue.Id)
	writeMap(save, "Inventory", "Unique")[cue.Id] = copy
	if paid then
		writeMap(save, "Inventory", "PaidUnique")[cue.Id] = true
	end
	markGot(save, cue.Id)
	return true, first
end

--- Takes n (default 1) copies away (a Unique cue: n = 1). Paid copies go first (selling back),
--- or free copies first with `freeFirst` (a trade); Inventory.removedPaid then answers how
--- many paid copies went. Reasons:
--- "Unknown" (not a catalog id), "BadCount", "Default" (Classic can't go), "NotOwned",
--- "TooMany". When the last copy goes its NEW tag goes too and, if it was equipped, Classic is
--- equipped instead (a save never equips a cue it doesn't own). The Index keeps it.
function Inventory.removeCue(
	save: any,
	id: any,
	n: number?,
	freeFirst: boolean?
): (boolean, string?)
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
	local paidHave = Inventory.paidCount(save, cue.Id)
	local paidGone = if freeFirst
		then math.max(amount - (have - paidHave), 0)
		else math.min(amount, paidHave)
	lastRemovedPaid = paidGone
	if cue.Group == "Unique" then
		writeMap(save, "Inventory", "Unique")[cue.Id] = nil
		local paidUnique = readMap(save, "Inventory", "PaidUnique")
		if paidUnique[cue.Id] ~= nil then
			paidUnique[cue.Id] = nil
		end
	else
		writeMap(save, "Inventory", "Cues")[cue.Id] = if left > 0 then left else nil
		local paidLeft = paidHave - paidGone
		local paidCues = readMap(save, "Inventory", "PaidCues")
		if paidLeft > 0 then
			writeMap(save, "Inventory", "PaidCues")[cue.Id] = paidLeft
		elseif paidCues[cue.Id] ~= nil then
			paidCues[cue.Id] = nil
		end
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

--- How many paid copies the last successful removeCue took (a trade passes them on as paid).
function Inventory.removedPaid(): number
	return lastRemovedPaid
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

--- Ready (openable) cases of one type, free and paid origin together.
function Inventory.caseCount(save: any, caseId: any): number
	if Cases.get(caseId) == nil then
		return 0
	end
	return storedCount(readMap(save, "Inventory", "Cases"), caseId)
		+ storedCount(readMap(save, "Inventory", "PaidCases"), caseId)
end

--- Ready cases of one type that are paid origin.
function Inventory.paidCases(save: any, caseId: any): number
	if Cases.get(caseId) == nil then
		return 0
	end
	return storedCount(readMap(save, "Inventory", "PaidCases"), caseId)
end

--- Adds n (default 1) READY cases of a known type (`paid`: paid origin), skipping any timer:
--- for a case that has finished its timer. New cases land through landCase.
function Inventory.addCases(save: any, caseId: any, n: number?, paid: boolean?): boolean
	local amount = n or 1
	if Cases.get(caseId) == nil or not isCount(amount) then
		return false
	end
	local cases = writeMap(save, "Inventory", if paid then "PaidCases" else "Cases")
	cases[caseId] = storedCount(cases, caseId) + amount
	return true
end

--- Takes n (default 1) ready cases, paid origin first; false (and nothing changes) without
--- enough of them. The second answer is how many of them were paid.
function Inventory.takeCases(save: any, caseId: any, n: number?): (boolean, number)
	local amount = n or 1
	if not isCount(amount) then
		return false, 0
	end
	if Inventory.caseCount(save, caseId) < amount then
		return false, 0
	end
	local paidHave = Inventory.paidCases(save, caseId)
	local paid = math.min(amount, paidHave)
	local free = amount - paid
	if paid > 0 then
		writeMap(save, "Inventory", "PaidCases")[caseId] = if paidHave > paid
			then paidHave - paid
			else nil
	end
	if free > 0 then
		local freeHave = storedCount(readMap(save, "Inventory", "Cases"), caseId)
		writeMap(save, "Inventory", "Cases")[caseId] = if freeHave > free
			then freeHave - free
			else nil
	end
	return true, paid
end

-- The save's timers that read as timers (anything else is skipped), in stored order.
local function timerList(save: any): { { Case: string, At: number, Paid: boolean } }
	local list = {}
	local stored: { any } = readMap(save, "Inventory", "Timers") :: any
	for _, t in ipairs(stored) do
		if
			type(t) == "table"
			and Cases.get(t.Case) ~= nil
			and type(t.At) == "number"
			and t.At == t.At
		then
			table.insert(list, { Case = t.Case, At = t.At, Paid = t.Paid == true })
		end
	end
	return list
end

--- Lands one new case (a Case Drop, a reward, a purchase) at unix time `now`: an instant case
--- (or one whose timer is 0) joins its ready stack; a timed one starts its timer, halved with
--- `quick` (Quick Cases). `paid`: paid origin. Returns the unix time it is ready (0: now), or
--- nil for an unknown case. With Config.Save.MaxTimerEntries timers already running (a number
--- nobody reaches) the case lands ready rather than growing the list.
function Inventory.landCase(
	save: any,
	caseId: any,
	now: number,
	quick: boolean?,
	paid: boolean?
): number?
	if Cases.get(caseId) == nil then
		return nil
	end
	local seconds = Cases.timer(caseId, quick)
	local timers: { any } = writeMap(save, "Inventory", "Timers") :: any
	if seconds <= 0 or #timers >= Config.Save.MaxTimerEntries then
		Inventory.addCases(save, caseId, 1, paid)
		return 0
	end
	local at = math.floor(now) + seconds
	table.insert(timers, { Case = caseId, At = at, Paid = paid == true })
	return at
end

--- Moves every timer that has run out by unix time `now` into its ready stack, keeping the rest
--- in order. Returns how many finished.
function Inventory.finishTimers(save: any, now: number): number
	local stored: { any } = readMap(save, "Inventory", "Timers") :: any
	if #stored == 0 then
		return 0
	end
	local keep = {}
	local finished = 0
	for _, t in timerList(save) do
		if t.At <= now then
			Inventory.addCases(save, t.Case, 1, t.Paid)
			finished += 1
		else
			table.insert(keep, t)
		end
	end
	writeMap(save, "Inventory").Timers = keep
	return finished
end

--- Finishes one running timer at once (a skip): the timer of case `caseId` that ends at `at`.
--- False when there is no such timer.
function Inventory.finishTimer(save: any, caseId: any, at: any): boolean
	local timers = timerList(save)
	for i, t in timers do
		if t.Case == caseId and t.At == at then
			table.remove(timers, i)
			writeMap(save, "Inventory").Timers = timers
			Inventory.addCases(save, t.Case, 1, t.Paid)
			return true
		end
	end
	return false
end

--- Halves every timer still running at `now` (Quick Cases bought while they run), rounded up
--- to a whole second. Returns how many changed.
function Inventory.halveTimers(save: any, now: number): number
	local timers = timerList(save)
	local changed = 0
	for _, t in timers do
		if t.At > now then
			t.At = math.floor(now) + math.ceil((t.At - now) * Config.Cases.QuickTimerFactor)
			changed += 1
		end
	end
	writeMap(save, "Inventory").Timers = timers
	return changed
end

--- Cases of one type that can be opened at unix time `now`: the ready stacks plus timers that
--- have run out (finishTimers moves those on the next change).
function Inventory.readyCount(save: any, caseId: any, now: number): number
	local count = Inventory.caseCount(save, caseId)
	for _, t in timerList(save) do
		if t.Case == caseId and t.At <= now then
			count += 1
		end
	end
	return count
end

--- The running timers soonest first ({ id, readyAt, paid }; equal times keep stored order).
function Inventory.timers(save: any): { { id: string, readyAt: number, paid: boolean } }
	local list = {}
	for i, t in timerList(save) do
		table.insert(list, { id = t.Case, readyAt = t.At, paid = t.Paid, order = i })
	end
	table.sort(list, function(a: any, b: any): boolean
		if a.readyAt ~= b.readyAt then
			return a.readyAt < b.readyAt
		end
		return a.order < b.order
	end)
	local out = {}
	for _, t in list do
		table.insert(out, { id = t.id, readyAt = t.readyAt, paid = t.paid })
	end
	return out
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
---   cases     ready cases in ladder order: { id, count }
---   timers    cases still on their timer, soonest first: { id, readyAt (unix time), paid }
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

	-- Classic is in the Index's Common row (always found: everyone owns it).
	local seen = {}
	for _, cue in Catalog.list() do
		if everOwned(save, cue.Id) then
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
		timers = Inventory.timers(save),
		equipped = Inventory.equipped(save),
		seen = seen,
		rows = Inventory.indexRows(save),
		titles = titles,
	}
end

return Inventory
