--!strict
-- Trade: the pure half of trading (the approved economy plan, 2026-10-02, section 9; designer,
-- 2026-10-03). src/server/Trading.luau owns the sessions, the remotes and the ledger.
--
-- An item is a string: a cue id ("NeonCue") or "Case:" and a case id ("Case:Rare"). A side
-- is a list of up to Config.Trade.MaxSideItems items; one entry is one copy, so three of a
-- cue are three entries. What may trade: case cues and Unique (numbered Limited) cues, the
-- Exclusive cues in Config.Trade.ExclusiveTradable, and READY cases (never one on its timer);
-- never money, never Classic, never another Exclusive cue. A paid-origin copy moves only when
-- both players may trade paid items (PolicyService); free copies always move first.
--
-- Trade.swap checks both sides against both saves and then changes them together, or changes
-- nothing. What moved (`Moved`: each item's count, how many were paid, a Unique's number) is
-- what the ledger keeps, so a save that missed the swap can replay its side (Trade.replay).
-- A cue got in a trade enters the Index but pays no finder's money (the caller pays none).
--
-- Pure: no Instances, no clocks (the caller passes `now`), no randomness; every loop walks an
-- array. Lune-tested (tests/trade_test.luau).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local Cases = require(script.Parent.Cases)
local Inventory = require(script.Parent.Inventory)

local T = Config.Trade
local CASE_PREFIX = "Case:"

-- One kind of item moved: `count` copies, `paid` of them paid origin, a Unique's `copy`.
export type MovedItem = { item: string, count: number, paid: number, copy: number? }
export type Moved = { MovedItem }

-- A save's history entry (SaveSchema: Trades.History).
export type HistoryEntry =
	{ Id: string, With: number, At: number, Gave: { string }, Got: { string } }

-- The ledger's record of one trade: who traded, when, and what moved from each of them.
export type Entry = {
	id: string,
	at: number,
	a: number, -- UserIds
	b: number,
	fromA: Moved,
	fromB: Moved,
}

local Trade = {}

-- What an item string names: ("Cue", cue id) or ("Case", case id), or nil.
local function parseItem(item: any): (string?, string?)
	if type(item) ~= "string" then
		return nil, nil
	end
	if string.sub(item, 1, #CASE_PREFIX) == CASE_PREFIX then
		local caseId = string.sub(item, #CASE_PREFIX + 1)
		if Cases.get(caseId) ~= nil then
			return "Case", caseId
		end
		return nil, nil
	end
	local cue = Catalog.get(item)
	if cue ~= nil then
		return "Cue", cue.Id
	end
	return nil, nil
end

--- The item string of a case.
function Trade.caseItem(caseId: string): string
	return CASE_PREFIX .. caseId
end

--- Whether a cue may ever be traded: case and Unique cues, and the Exclusive ones listed in
--- Config.Trade.ExclusiveTradable (the Starter Cue).
function Trade.tradable(cueId: string): boolean
	local cue = Catalog.get(cueId)
	if cue == nil then
		return false
	end
	if cue.Group == "Exclusive" then
		return (T.ExclusiveTradable :: any)[cue.Id] == true
	end
	return cue.Group == "Case" or cue.Group == "Unique"
end

--- A side from a client: a list of known item strings, at most MaxSideItems (a fresh copy), or
--- (nil, "BadRequest").
function Trade.parse(items: any): ({ string }?, string?)
	if type(items) ~= "table" then
		return nil, "BadRequest"
	end
	local n = 0
	for key in items do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			return nil, "BadRequest"
		end
		n += 1
		if n > T.MaxSideItems then
			return nil, "BadRequest"
		end
	end
	local out: { string } = {}
	for i = 1, n do
		local kind = parseItem(items[i])
		if kind == nil then
			return nil, "BadRequest"
		end
		table.insert(out, items[i])
	end
	return out, nil
end

-- A side's items counted, in the order each first appears: { item, count }.
local function counted(items: { string }): { { item: string, count: number } }
	local list: { { item: string, count: number } } = {}
	local at: { [string]: number } = {}
	for _, item in items do
		local i = at[item]
		if i == nil then
			table.insert(list, { item = item, count = 1 })
			at[item] = #list
		else
			list[i].count += 1
		end
	end
	return list
end

-- How many copies of an item the save may give: (all it holds, the free ones).
local function holding(save: any, item: string): (number, number)
	local kind, id = parseItem(item)
	if kind == "Case" then
		local have = Inventory.caseCount(save, id)
		return have, have - Inventory.paidCases(save, id)
	elseif kind == "Cue" then
		local have = Inventory.count(save, id)
		return have, have - Inventory.paidCount(save, id)
	end
	return 0, 0
end

--- What this save can put in a trade now (GUI lane, the trade screen and its wish list):
--- { item, count } for every tradable cue it holds and every READY case, cues in the Index's
--- order then cases in shop order; `count` is how many may go (free copies only unless
--- `paidOk`). Items with nothing to give are left out.
function Trade.offerable(save: any, paidOk: boolean): { { item: string, count: number } }
	local out: { { item: string, count: number } } = {}
	for _, cue in Catalog.list() do
		if Trade.tradable(cue.Id) then
			local have, free = holding(save, cue.Id)
			local n = if paidOk then have else free
			if n > 0 then
				table.insert(out, { item = cue.Id, count = n })
			end
		end
	end
	for _, case in Cases.list(true) do
		local item = Trade.caseItem(case.Id)
		local have, free = holding(save, item)
		local n = if paidOk then have else free
		if n > 0 then
			table.insert(out, { item = item, count = n })
		end
	end
	return out
end

--- Why this save cannot give `items`, or nil: "NotTradable" (Classic, an Exclusive cue),
--- "NotOwned" (fewer than offered, or a case still on its timer), "PaidBlocked" (only paid
--- copies would make the count and `paidOk` is false). Ready cases only: finish the save's
--- timers first.
function Trade.canGive(save: any, items: { string }, paidOk: boolean): string?
	for _, entry in counted(items) do
		local kind, id = parseItem(entry.item)
		if kind == "Cue" and not Trade.tradable(id :: string) then
			return "NotTradable"
		end
		local have, free = holding(save, entry.item)
		if entry.count > have then
			return "NotOwned"
		elseif not paidOk and entry.count > free then
			return "PaidBlocked"
		end
	end
	return nil
end

--- Why this save cannot receive `items`, or nil: "Owned" (a Unique or Exclusive cue it holds
--- already: one per player).
function Trade.canReceive(save: any, items: { string }): string?
	for _, entry in counted(items) do
		local kind, id = parseItem(entry.item)
		if kind == "Cue" then
			local cue = Catalog.get(id) :: Catalog.Cue
			if
				(cue.Group == "Unique" or cue.Group == "Exclusive")
				and (entry.count > 1 or Inventory.owns(save, cue.Id))
			then
				return "Owned"
			end
		end
	end
	return nil
end

--- Why these two saves cannot swap these sides, or nil: "Empty" (a side with nothing: no
--- gifts), then canGive's and canReceive's reasons, A's side first.
function Trade.check(
	saveA: any,
	saveB: any,
	itemsA: { string },
	itemsB: { string },
	paidOk: boolean
): string?
	if #itemsA == 0 or #itemsB == 0 then
		return "Empty"
	end
	return Trade.canGive(saveA, itemsA, paidOk)
		or Trade.canGive(saveB, itemsB, paidOk)
		or Trade.canReceive(saveB, itemsA)
		or Trade.canReceive(saveA, itemsB)
end

-- Takes a side out of a save (free copies first): what moved. Checked first by the caller.
local function take(save: any, items: { string }): Moved
	local moved: Moved = {}
	for _, entry in counted(items) do
		local kind, id = parseItem(entry.item)
		if kind == "Case" then
			local _, paid = Inventory.takeCases(save, id, entry.count, true)
			table.insert(moved, { item = entry.item, count = entry.count, paid = paid })
		else
			local copy = Inventory.copy(save, id)
			Inventory.removeCue(save, id, entry.count, true)
			table.insert(moved, {
				item = entry.item,
				count = entry.count,
				paid = Inventory.removedPaid(),
				copy = copy,
			})
		end
	end
	return moved
end

-- Gives what moved to a save, keeping each copy's paid origin and a Unique's number.
local function give(save: any, moved: Moved)
	for _, m in moved do
		local kind, id = parseItem(m.item)
		if kind == "Case" then
			local free = m.count - m.paid
			if free > 0 then
				Inventory.addCases(save, id, free, false)
			end
			if m.paid > 0 then
				Inventory.addCases(save, id, m.paid, true)
			end
		else
			local cue = Catalog.get(id) :: Catalog.Cue
			if cue.Group == "Unique" then
				Inventory.addUnique(save, cue.Id, m.copy or 1, m.paid > 0)
			else
				local free = m.count - m.paid
				if free > 0 then
					Inventory.addCue(save, cue.Id, free, false)
				end
				if m.paid > 0 then
					Inventory.addCue(save, cue.Id, m.paid, true)
				end
			end
		end
	end
end

--- Swaps A's `itemsA` for B's `itemsB` in the two saves: everything checked first, then both
--- changed. Returns (true, nil, from A, from B) or (false, reason) with nothing changed.
function Trade.swap(
	saveA: any,
	saveB: any,
	itemsA: { string },
	itemsB: { string },
	paidOk: boolean
): (boolean, string?, Moved?, Moved?)
	local why = Trade.check(saveA, saveB, itemsA, itemsB, paidOk)
	if why ~= nil then
		return false, why, nil, nil
	end
	local fromA = take(saveA, itemsA)
	local fromB = take(saveB, itemsB)
	give(saveB, fromA)
	give(saveA, fromB)
	return true, nil, fromA, fromB
end

--- Whether two Moved lists are the same (the ledger's plan and the real swap).
function Trade.same(x: Moved, y: Moved): boolean
	if #x ~= #y then
		return false
	end
	for i, m in x do
		local n = y[i]
		if m.item ~= n.item or m.count ~= n.count or m.paid ~= n.paid or m.copy ~= n.copy then
			return false
		end
	end
	return true
end

-- What moved as the history's item list (one entry per copy).
local function itemsOf(moved: Moved): { string }
	local out: { string } = {}
	for _, m in moved do
		for _ = 1, m.count do
			table.insert(out, m.item)
		end
	end
	return out
end

--- Records a trade in one save: its history (the last Config.Save.MaxTradeHistory) and its
--- applied ids (the last MaxAppliedTrades). Changes `save`.
function Trade.record(save: any, id: string, with: number, at: number, gave: Moved, got: Moved)
	local trades = save.Trades
	table.insert(
		trades.History,
		{ Id = id, With = with, At = at, Gave = itemsOf(gave), Got = itemsOf(got) }
	)
	while #trades.History > Config.Save.MaxTradeHistory do
		table.remove(trades.History, 1)
	end
	table.insert(trades.Applied, id)
	while #trades.Applied > Config.Save.MaxAppliedTrades do
		table.remove(trades.Applied, 1)
	end
end

--- Whether a save already holds a trade's result.
function Trade.applied(save: any, id: string): boolean
	local trades = if type(save) == "table" then save.Trades else nil
	return type(trades) == "table"
		and type(trades.Applied) == "table"
		and table.find(trades.Applied, id) ~= nil
end

--- Replays one player's side of a ledger trade on a save that missed it (its load came after
--- a crash that lost the swap): takes what that player gave as far as the save still holds it
--- (free first) and gives what they got, then records it. False (nothing changed) when the
--- save already holds it or the player is not in it.
function Trade.replay(save: any, entry: Entry, userId: number): boolean
	if Trade.applied(save, entry.id) or (userId ~= entry.a and userId ~= entry.b) then
		return false
	end
	local isA = userId == entry.a
	local gave = if isA then entry.fromA else entry.fromB
	local got = if isA then entry.fromB else entry.fromA
	for _, m in gave do
		local kind, id = parseItem(m.item)
		if kind == "Case" then
			local n = math.min(m.count, Inventory.caseCount(save, id))
			if n > 0 then
				Inventory.takeCases(save, id, n, true)
			end
		elseif kind == "Cue" then
			local n = math.min(m.count, Inventory.count(save, id))
			if n > 0 then
				Inventory.removeCue(save, id, n, true)
			end
		end
	end
	local receivable: Moved = {}
	for _, m in got do
		local kind, id = parseItem(m.item)
		local cue = if kind == "Cue" then Catalog.get(id) else nil
		if not (cue ~= nil and cue.Group == "Unique" and Inventory.owns(save, cue.Id)) then
			table.insert(receivable, m)
		end
	end
	give(save, receivable)
	Trade.record(save, entry.id, if isA then entry.b else entry.a, entry.at, gave, got)
	return true
end

---------------------------------------------------------------------------------------------
-- The lopsided warning
---------------------------------------------------------------------------------------------

-- An item's worth: 1 / its copies in existence (cues; fewer than MinExists counts as
-- MinExists, unknown as MinExists) or 1 / Config.Trade.CaseExists (cases).
local function worth(item: string, copies: { [string]: number }): number
	local kind, id = parseItem(item)
	if kind == "Case" then
		return 1 / math.max(1, (T.CaseExists :: any)[id] or 1)
	elseif kind == "Cue" then
		local n = copies[id :: string]
		return 1 / math.max(T.MinExists, if type(n) == "number" then n else T.MinExists)
	end
	return 0
end

--- Which side is worth far more ("A" or "B": more than LopsidedRatio times the other), or nil.
--- `copies` is each cue's copies in existence (Counters).
function Trade.lopsided(
	itemsA: { string },
	itemsB: { string },
	copies: { [string]: number }
): string?
	local a, b = 0, 0
	for _, item in itemsA do
		a += worth(item, copies)
	end
	for _, item in itemsB do
		b += worth(item, copies)
	end
	if a > 0 and b > 0 then
		if a > b * T.LopsidedRatio then
			return "A"
		elseif b > a * T.LopsidedRatio then
			return "B"
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- The ledger's per-player key: { entries = { Entry } } (the trades not yet confirmed saved)
---------------------------------------------------------------------------------------------

local function isEntry(e: any): boolean
	return type(e) == "table"
		and type(e.id) == "string"
		and type(e.a) == "number"
		and type(e.b) == "number"
		and type(e.at) == "number"
		and type(e.fromA) == "table"
		and type(e.fromB) == "table"
end

--- The entries in a stored key, oldest first (anything else dropped).
function Trade.entries(stored: any): { Entry }
	local out: { Entry } = {}
	if type(stored) == "table" and type(stored.entries) == "table" then
		for _, e in stored.entries do
			if isEntry(e) then
				table.insert(out, e)
			end
		end
	end
	return out
end

--- The add transform: the key with `entry` (once; the oldest go past MaxPending).
function Trade.addEntry(stored: any, entry: Entry): { entries: { Entry } }?
	local list = Trade.entries(stored)
	for _, e in list do
		if e.id == entry.id then
			return nil
		end
	end
	table.insert(list, entry)
	while #list > T.MaxPending do
		table.remove(list, 1)
	end
	return { entries = list }
end

--- The remove transform: the key without trade `id`, or nil when it is not there.
function Trade.removeEntry(stored: any, id: string): { entries: { Entry } }?
	local list = Trade.entries(stored)
	for i, e in list do
		if e.id == id then
			table.remove(list, i)
			return { entries = list }
		end
	end
	return nil
end

return Trade
