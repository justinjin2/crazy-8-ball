--!strict
-- Trade: the pure half of trading (the approved economy plan, 2026-10-02, section 9; designer,
-- 2026-10-03). src/server/Trading.luau owns the sessions, the remotes and the ledger.
--
-- An item is a string: a cue id ("NeonCue") or "Block:" and a lucky block kind
-- ("Block:Rare"). A side is a list of up to Config.Trade.MaxSideItems items; one entry is one
-- copy, so three of a cue are three entries. What may trade: block cues and Unique (numbered
-- Limited) cues, the Exclusive cues in Config.Trade.ExclusiveTradable, and READY lucky blocks
-- (never one on its timer; the caller passes `now`); never money, never Classic, never
-- another Exclusive cue. A paid-origin copy moves only when both players may trade paid items
-- (PolicyService); a paid-origin lucky block (an unopened paid random item) also needs
-- `blocksOk`: neither player has paid random items restricted (economy v4 plan 13). Free
-- copies always move first. A traded block lands ready at once.
--
-- Trade.swap checks both sides against both saves and then changes them together, or changes
-- nothing. What moved (`Moved`: each item's count, how many were paid, a Unique's number) is
-- what the ledger keeps, so a save that missed the swap can replay its side (Trade.replay).
-- A cue got in a trade enters the Index but pays no finder's money (the caller pays none).
--
-- Pure: no Instances, no clocks (the caller passes `now`, unix seconds), no randomness; every
-- loop walks an array. Lune-tested (tests/trade_test.luau).
local Config = require(script.Parent.Parent.Config)
local BlockDrop = require(script.Parent.BlockDrop)
local BlockOdds = require(script.Parent.BlockOdds)
local Catalog = require(script.Parent.Catalog)
local Inventory = require(script.Parent.Inventory)
local LuckyBlocks = require(script.Parent.LuckyBlocks)

local T = Config.Trade
local BLOCK_PREFIX = "Block:"

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

-- What an item string names: ("Cue", cue id) or ("Block", block kind), or nil.
local function parseItem(item: any): (string?, string?)
	if type(item) ~= "string" then
		return nil, nil
	end
	if string.sub(item, 1, #BLOCK_PREFIX) == BLOCK_PREFIX then
		local kind = string.sub(item, #BLOCK_PREFIX + 1)
		if LuckyBlocks.kind(kind) ~= nil and LuckyBlocks.current(kind) == kind then
			return "Block", kind
		end
		return nil, nil
	end
	local cue = Catalog.get(item)
	if cue ~= nil then
		return "Cue", cue.Id
	end
	return nil, nil
end

--- The item string of a lucky block kind.
function Trade.blockItem(kind: string): string
	return BLOCK_PREFIX .. kind
end

--- Whether a cue may ever be traded: block and Unique cues, and the Exclusive ones listed in
--- Config.Trade.ExclusiveTradable (the Starter Cue).
function Trade.tradable(cueId: string): boolean
	local cue = Catalog.get(cueId)
	if cue == nil then
		return false
	end
	if cue.Group == "Exclusive" then
		return (T.ExclusiveTradable :: any)[cue.Id] == true
	end
	return cue.Group == "Block" or cue.Group == "Unique"
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

-- The save's lucky block list (empty for a save without one).
local function blockList(save: any): { LuckyBlocks.Block }
	local state = if type(save) == "table" then save.LuckyBlocks else nil
	local list = if type(state) == "table" then state.List else nil
	return if type(list) == "table" then list else {}
end

-- The save's READY blocks of `kind` at `now`, oldest first (by id).
local function readyBlocks(save: any, kind: string, now: number): { LuckyBlocks.Block }
	local out: { LuckyBlocks.Block } = {}
	for _, block in blockList(save) do
		if type(block) == "table" and block.Kind == kind and LuckyBlocks.isReady(block, now) then
			table.insert(out, block)
		end
	end
	table.sort(out, function(a, b)
		return a.Id < b.Id
	end)
	return out
end

-- How many copies of an item the save may give at `now`: (all it holds, the free ones).
local function holding(save: any, item: string, now: number): (number, number)
	local kind, id = parseItem(item)
	if kind == "Block" then
		local have, free = 0, 0
		for _, block in readyBlocks(save, id :: string, now) do
			have += 1
			if not block.Paid then
				free += 1
			end
		end
		return have, free
	elseif kind == "Cue" then
		if Inventory.isOwnerCopy(save, id) then
			return 0, 0 -- the designer's unnumbered copy never leaves their save
		end
		local have = Inventory.count(save, id)
		return have, have - Inventory.paidCount(save, id)
	end
	return 0, 0
end

-- Whether paid-origin copies of `item` may move: `paidOk` for cues; for a lucky block also
-- `blocksOk` (nil: as paidOk).
local function paidMoves(item: string, paidOk: boolean, blocksOk: boolean?): boolean
	if string.sub(item, 1, #BLOCK_PREFIX) == BLOCK_PREFIX then
		return paidOk and blocksOk ~= false
	end
	return paidOk
end

--- What this save can put in a trade at `now` (GUI lane, the trade screen and its wish
--- list): { item, count } for every tradable cue it holds and every READY lucky block, cues
--- in the Index's order then blocks in Config.LuckyBlocks.Order; `count` is how many may go
--- (free copies only unless `paidOk`, and for a block `blocksOk`). Items with nothing to give
--- are left out.
function Trade.offerable(
	save: any,
	paidOk: boolean,
	now: number,
	blocksOk: boolean?
): { { item: string, count: number } }
	local out: { { item: string, count: number } } = {}
	for _, cue in Catalog.list() do
		if Trade.tradable(cue.Id) then
			local have, free = holding(save, cue.Id, now)
			local n = if paidOk then have else free
			if n > 0 then
				table.insert(out, { item = cue.Id, count = n })
			end
		end
	end
	for _, kind in Config.LuckyBlocks.Order do
		local item = Trade.blockItem(kind)
		local have, free = holding(save, item, now)
		local n = if paidMoves(item, paidOk, blocksOk) then have else free
		if n > 0 then
			table.insert(out, { item = item, count = n })
		end
	end
	return out
end

--- Why this save cannot give `items` at `now`, or nil: "NotTradable" (Classic, an Exclusive
--- cue), "NotOwned" (fewer than offered, or a block still on its timer), "PaidBlocked" (only
--- paid copies would make the count and `paidOk` is false, or for a block `blocksOk`).
function Trade.canGive(
	save: any,
	items: { string },
	paidOk: boolean,
	now: number,
	blocksOk: boolean?
): string?
	for _, entry in counted(items) do
		local kind, id = parseItem(entry.item)
		if kind == "Cue" and not Trade.tradable(id :: string) then
			return "NotTradable"
		end
		local have, free = holding(save, entry.item, now)
		if entry.count > have then
			return "NotOwned"
		elseif not paidMoves(entry.item, paidOk, blocksOk) and entry.count > free then
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

--- Why these two saves cannot swap these sides at `now`, or nil: "Empty" (a side with
--- nothing: no gifts), then canGive's and canReceive's reasons, A's side first.
function Trade.check(
	saveA: any,
	saveB: any,
	itemsA: { string },
	itemsB: { string },
	paidOk: boolean,
	now: number,
	blocksOk: boolean?
): string?
	if #itemsA == 0 or #itemsB == 0 then
		return "Empty"
	end
	return Trade.canGive(saveA, itemsA, paidOk, now, blocksOk)
		or Trade.canGive(saveB, itemsB, paidOk, now, blocksOk)
		or Trade.canReceive(saveB, itemsA)
		or Trade.canReceive(saveA, itemsB)
end

-- Takes `count` ready blocks of `kind` out of a save at `now`, free ones first, then the
-- oldest: how many of them were paid.
local function takeBlocks(save: any, kind: string, count: number, now: number): number
	local ready = readyBlocks(save, kind, now)
	local picked: { LuckyBlocks.Block } = {}
	for _, block in ready do
		if #picked < count and not block.Paid then
			table.insert(picked, block)
		end
	end
	for _, block in ready do
		if #picked < count and block.Paid then
			table.insert(picked, block)
		end
	end
	local paid = 0
	for _, block in picked do
		LuckyBlocks.remove(save.LuckyBlocks, block.Id)
		if block.Paid then
			paid += 1
		end
	end
	return paid
end

-- Takes a side out of a save at `now` (free copies first): what moved. Checked first by the
-- caller.
local function take(save: any, items: { string }, now: number): Moved
	local moved: Moved = {}
	for _, entry in counted(items) do
		local kind, id = parseItem(entry.item)
		if kind == "Block" then
			local paid = takeBlocks(save, id :: string, entry.count, now)
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

-- Gives what moved to a save at `now`, keeping each copy's paid origin and a Unique's number.
-- A block lands at the end of the list, ready at once.
local function give(save: any, moved: Moved, now: number)
	for _, m in moved do
		local kind, id = parseItem(m.item)
		if kind == "Block" then
			for i = 1, m.count do
				local block = LuckyBlocks.add(save.LuckyBlocks, id :: string, now, nil, i <= m.paid)
				block.ReadyAt = now
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

--- Swaps A's `itemsA` for B's `itemsB` in the two saves at `now`: everything checked first,
--- then both changed. Returns (true, nil, from A, from B) or (false, reason) with nothing
--- changed.
function Trade.swap(
	saveA: any,
	saveB: any,
	itemsA: { string },
	itemsB: { string },
	paidOk: boolean,
	now: number,
	blocksOk: boolean?
): (boolean, string?, Moved?, Moved?)
	local why = Trade.check(saveA, saveB, itemsA, itemsB, paidOk, now, blocksOk)
	if why ~= nil then
		return false, why, nil, nil
	end
	local fromA = take(saveA, itemsA, now)
	local fromB = take(saveB, itemsB, now)
	give(saveB, fromA, now)
	give(saveA, fromB, now)
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
--- a crash that lost the swap) at `now`: takes what that player gave as far as the save still
--- holds it (free first; a block ready now) and gives what they got, then records it. False
--- (nothing changed) when the save already holds it or the player is not in it.
function Trade.replay(save: any, entry: Entry, userId: number, now: number): boolean
	if Trade.applied(save, entry.id) or (userId ~= entry.a and userId ~= entry.b) then
		return false
	end
	local isA = userId == entry.a
	local gave = if isA then entry.fromA else entry.fromB
	local got = if isA then entry.fromB else entry.fromA
	for _, m in gave do
		local kind, id = parseItem(m.item)
		if kind == "Block" then
			local n = math.min(m.count, #readyBlocks(save, id :: string, now))
			if n > 0 then
				takeBlocks(save, id :: string, n, now)
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
	give(save, receivable, now)
	Trade.record(save, entry.id, if isA then entry.b else entry.a, entry.at, gave, got)
	return true
end

---------------------------------------------------------------------------------------------
-- The lopsided warning
---------------------------------------------------------------------------------------------

-- One cue's worth from its copies in existence (fewer than MinExists counts as MinExists),
-- or nil when its count is unknown.
local function cueWorth(cueId: string, copies: { [string]: number }): number?
	local n = copies[cueId]
	if type(n) ~= "number" then
		return nil
	end
	return 1 / math.max(T.MinExists, n)
end

-- An odds row's expected worth: each rarity's share times the mean worth of its droppable
-- cues, plus its Unique rows; nil when any of those cues' counts is unknown.
local function rowWorth(oddsId: string, copies: { [string]: number }): number?
	local total = 0
	for _, entry in BlockOdds.odds(oddsId) do
		local pool = Catalog.droppable(oddsId, entry.rarity)
		local sum = 0
		for _, cue in pool do
			local w = cueWorth(cue.Id, copies)
			if w == nil then
				return nil
			end
			sum += w
		end
		if #pool > 0 then
			total += entry.percent / 100 * sum / #pool
		end
	end
	for _, unique in BlockOdds.uniqueRows(oddsId) do
		local w = cueWorth(unique.cue, copies)
		if w == nil then
			return nil
		end
		total += unique.percent / 100 * w
	end
	return total
end

--- A lucky block's worth worked out live (economy v4 plan section 11): what its odds row gives
--- on average, each cue worth 1 / its copies in existence; a Mystery block weighs each tier's
--- row by Config.BlockOdds.Drop.Weights. nil when a needed count is unknown (the caller falls
--- back to Config.Trade.BlockExists).
function Trade.blockWorth(kind: string, copies: { [string]: number }): number?
	local row = LuckyBlocks.kind(kind)
	if row == nil then
		return nil
	end
	if row.Roll then
		local total = 0
		for _, tier in BlockDrop.tiers() do
			local tierRow = LuckyBlocks.kind(tier.tier)
			local w = if tierRow and tierRow.Odds then rowWorth(tierRow.Odds, copies) else nil
			if w == nil then
				return nil
			end
			total += tier.percent / 100 * w
		end
		return total
	end
	return if row.Odds then rowWorth(row.Odds, copies) else nil
end

-- An item's worth: 1 / its copies in existence (cues; fewer than MinExists counts as
-- MinExists, unknown as MinExists) or Trade.blockWorth (lucky blocks; until the counts are
-- known, 1 / Config.Trade.BlockExists).
local function worth(item: string, copies: { [string]: number }): number
	local kind, id = parseItem(item)
	if kind == "Block" then
		local live = Trade.blockWorth(id :: string, copies)
		if live ~= nil and live > 0 then
			return live
		end
		return 1 / math.max(T.MinExists, (T.BlockExists :: any)[id] or T.MinExists)
	elseif kind == "Cue" then
		return cueWorth(id :: string, copies) or 1 / T.MinExists
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

-- A renamed cue's moved items under its new id (Config.Items.RenamedCues), so a trade in flight
-- across the rename lands on the cue the saves now hold.
local function renameMoved(moved: Moved)
	for _, m in moved do
		local new = type(m) == "table" and Config.Items.RenamedCues[m.item]
		if new then
			m.item = new
		end
	end
end

--- The entries in a stored key, oldest first (anything else dropped).
function Trade.entries(stored: any): { Entry }
	local out: { Entry } = {}
	if type(stored) == "table" and type(stored.entries) == "table" then
		for _, e in stored.entries do
			if isEntry(e) then
				renameMoved(e.fromA)
				renameMoved(e.fromB)
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
