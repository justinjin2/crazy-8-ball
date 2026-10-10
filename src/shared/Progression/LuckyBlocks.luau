--!strict
-- LuckyBlocks (designer, 2026-10-03; Config.LuckyBlocks): the rules of the lucky blocks a
-- player holds. The save keeps them as { Next, List }: List is a gapless array in hotbar order
-- (the first Config.LuckyBlocks.HotbarSlots are the hotbar's slots 1..9, the rest wait in the
-- bag), each { Id, Kind, ReadyAt, Paid?, Climbed?, From?, Luck?, Pity? }; Next is the last id
-- given, so ids never repeat in a save. Economy v5 (2026-10-09): a block of a climbing kind
-- arrives unclimbed, on its own name's timer (the Gift: its Wait first), and its climb is
-- rolled when it is opened (BlockDrop.climbFor, PlayerData.planLuckyOpen): the tier it reaches
-- is the cue's rarity, and the reel shows it (economy v5.2, designer 2026-10-09: no climb
-- screen but the Mystery's). Economy v5.1: a Mystery's roll (`turn`, its upgrade screen) makes
-- it an unclimbed block of the tier reached, the same as any other; Pity: the pity counters
-- still waiting on that block's climb. Climbed / From / Luck: a block that climbed on the old
-- climb screen (v5, before v5.2), which opens from its tier's row (exactly that rarity).
--
-- Pure: no Instances, no Roblox APIs, no clocks (the caller passes `now`, unix seconds) and no
-- randomness; Lune-tested (tests/luckyblocks_test.luau). PlayerData calls the changes on the live
-- save; LuckyBlockService checks BlockRequest's arguments with `parse`.
local Config = require(script.Parent.Parent.Config)
local BlockOdds = require(script.Parent.BlockOdds)
local BlockDrop = require(script.Parent.BlockDrop)
local Catalog = require(script.Parent.Catalog)

local L = Config.LuckyBlocks

export type Kind = {
	Odds: string?, -- the Config.BlockOdds row a climbed (or never-climbing) block of it rolls
	Climb: string?, -- the tier it climbs from (economy v5); nil: it never climbs
	Turns: boolean?, -- the Mystery (v5.1): its screen turns it into a block (BlockDrop.turnRoll)
	Pity: boolean?, -- the Mystery block: its roll uses the pity counters
	Timer: number,
	Wait: number?, -- seconds a new block waits before its timer starts (the Gift)
	Model: string,
	Idle: string?,
	Icon: string?, -- its 2D picture for GUIs (BlockIcon, the hotbar); nil: a 3D model view
	Guarantee: { Cue: string, At: number }?, -- the At-th opened is this cue if none is owned
	Rainbow: boolean?, -- the client cycles its aura through the rainbow (Mythic)
	Bob: boolean?, -- no bones: the client bobs the model itself (the part-built Lucky 8)
	EmissiveStrength: number?,
	IconAmbient: number?,
	IconLight: number?,
	SizeMultiplier: number?,
	HoldCenterShare: number?,
	IconScale: number?,
}
export type Block = {
	Id: number,
	Kind: string,
	ReadyAt: number,
	Paid: boolean?,
	Climbed: boolean?, -- it climbed on the old climb screen (v5); nil: unclimbed
	From: string?, -- the kind it started as (a climbed block)
	Luck: boolean?, -- the Grand Opening Luck ran at its climb (a climbed block)
	-- A block a Mystery turned into (unclimbed): the pity counters still waiting on its climb,
	-- "Rare" (both) or "Epic" (the Epic one; BlockDrop.countClimb). nil: none.
	Pity: string?,
}
-- Opened: how many blocks of each kind this player has opened (the Guarantee's count).
export type State = {
	Next: number,
	List: { Block },
	-- Paid timer skips not yet used (a receipt whose block had finished), by the skip product
	-- bought (Config.LuckyBlocks.Skips): a credit skips a timer its row covers, or a shorter
	-- one. Keyed by product (economy v5, save 11), so a new skip row never changes what a saved
	-- credit buys.
	Credits: { [string]: number }?,
	SkipTarget: number?,
	Opened: { [string]: number }?,
}

-- One checked BlockRequest. Only the fields its action uses are set.
export type Request = {
	action: string,
	id: number?, -- Hold (nil: put it away), Throw, Open, Move, Reveal (OpenAll: none)
	to: number?, -- Move: the place in the list, 1..MaxBlocks
}

local KINDS: { [string]: Kind } = L.Kinds :: any
local RENAMED: { [string]: string } = L.Renamed or {}

local LuckyBlocks = {}

--- Every action a BlockRequest may name (Net "BlockRequest").
LuckyBlocks.Actions = table.freeze({ "Hold", "Throw", "Open", "Move", "Reveal", "OpenAll" })

--- Every reason a refused BlockRequest may answer (Strings.LuckyBlocks.Reasons words them).
LuckyBlocks.Reasons = table.freeze({
	"BadRequest", -- an unknown action, a wrong type or an id that is not a whole number
	"TooFast", -- the token bucket is empty (Config.LuckyBlocks.RateBurst, RatePerSecond)
	"NotLoaded", -- the save is not loaded yet
	"NotOwned", -- no block with that id
	"NotReady", -- Open: it is still on its timer
	"NotHeld", -- Throw: that block is not the one in the hands
	"Busy", -- Throw: no clear nearby spot; Open: it is already opening
	"NoBody", -- the character is missing, dead or seated
	"TooFar", -- Open: too far from the block
	"NotLanded", -- Open: it is still flying
	"Reveal", -- Hold: a Mystery block is opened on its upgrade screen, never held
	"NotMystery", -- Reveal: that block has no climb or roll ahead (climbed, or a kind that never climbs)
	"Climb", -- Open: a Mystery rolls on its upgrade screen first (economy v5.1)
	"NoneReady", -- OpenAll: no ready climbed Standard or Uncommon block (economy v5)
	"Error", -- anything else (logged on the server)
})

--- A kind's id as it is now: an old saved id (Config.LuckyBlocks.Renamed) is mapped, anything
--- else is returned as it is.
function LuckyBlocks.current(id: any): any
	if type(id) == "string" and RENAMED[id] ~= nil then
		return RENAMED[id]
	end
	return id
end

--- A kind's row, or nil for an unknown kind (an old saved id resolves to its new kind).
function LuckyBlocks.kind(id: any): Kind?
	local now = LuckyBlocks.current(id)
	if type(now) ~= "string" or table.find(L.Order, now) == nil then
		return nil
	end
	return KINDS[now]
end

--- A new player's blocks: none.
function LuckyBlocks.fresh(): State
	return {
		Next = 0,
		List = {},
		Credits = {},
		SkipTarget = 0,
		Opened = {},
	}
end

--- Seconds after a block of `kind` lands until it can be opened (0 for an unknown kind). VIP multiplies every timer by Config.LuckyBlocks.VipTimerFactor (0: VIP
--- has no timers).
function LuckyBlocks.timer(kind: string, vip: boolean?): number
	local row = LuckyBlocks.kind(kind)
	if row == nil or row.Timer <= 0 then
		return 0
	end
	return if vip then math.ceil(row.Timer * L.VipTimerFactor) else row.Timer
end

--- Seconds a new block of `kind` waits on top of its timer (the Gift's comeback wait; 0 for
--- every other kind), VIP's factor applied like a timer.
function LuckyBlocks.wait(kind: string, vip: boolean?): number
	local row = LuckyBlocks.kind(kind)
	local seconds = if row then row.Wait or 0 else 0
	if seconds <= 0 then
		return 0
	end
	return if vip then math.ceil(seconds * L.VipTimerFactor) else seconds
end

--- Whether blocks of `kind` climb (Config.LuckyBlocks.Kinds[kind].Climb).
function LuckyBlocks.climbs(kind: string): boolean
	local row = LuckyBlocks.kind(kind)
	return row ~= nil and row.Climb ~= nil
end

--- Whether `block` still has its climb ahead: a climbing kind, not yet climbed. Its climb is
--- rolled when it is opened (a Mystery's roll first, on its upgrade screen).
function LuckyBlocks.unclimbed(block: Block): boolean
	return block.Climbed ~= true and LuckyBlocks.climbs(block.Kind)
end

--- Whether blocks of `kind` turn into another block on their screen (the Mystery, v5.1).
function LuckyBlocks.turns(kind: string): boolean
	local row = LuckyBlocks.kind(kind)
	return row ~= nil and row.Turns == true
end

--- Whether `block` still needs its upgrade screen before anything else (economy v5.2: only a
--- Mystery, whose roll turns it into a block): it is never held, thrown or opened as it is.
function LuckyBlocks.needsRoll(block: Block): boolean
	return block.Climbed ~= true and LuckyBlocks.turns(block.Kind)
end

--- How many blocks of `kind` this player has opened.
function LuckyBlocks.opened(state: State, kind: string): number
	local opened = state.Opened
	local n = if type(opened) == "table" then opened[kind] else nil
	return if type(n) == "number" and n == n and n >= 0 then math.floor(n) else 0
end

--- Counts one more opened block of `kind`. Changes `state`.
function LuckyBlocks.noteOpened(state: State, kind: string)
	if type(state.Opened) ~= "table" then
		state.Opened = {}
	end
	local opened = state.Opened :: { [string]: number }
	opened[kind] = LuckyBlocks.opened(state, kind) + 1
end

--- The cue the next opened block of `kind` must give by its Guarantee (the At-th opened,
--- counting this one, when `owns` says the player has none), or nil for a normal roll.
function LuckyBlocks.guaranteed(state: State, kind: string, owns: (string) -> boolean): string?
	local row = LuckyBlocks.kind(kind)
	local g = if row then row.Guarantee else nil
	if g == nil or type(g.Cue) ~= "string" or type(g.At) ~= "number" then
		return nil
	end
	if LuckyBlocks.opened(state, kind) + 1 >= g.At and not owns(g.Cue) then
		return g.Cue
	end
	return nil
end

--- Whether `block` is off its timer at `now`.
function LuckyBlocks.isReady(block: Block, now: number): boolean
	return block.ReadyAt <= now
end

--- The N of "1 in N" for cue `cueId` from a block that started as kind `from` (economy v5
--- plan 3.9): a climbing kind's chance of that exact cue over its whole climb (with the Grand
--- Opening Luck when `luck`: the odds live at its open; a Mystery block's pity left out), a
--- kind that never climbs its row's (capped Uniques included), rounded to 3 significant
--- figures (BlockDrop.oneIn). nil for a cue that kind never gives or an unknown kind.
function LuckyBlocks.oneIn(cueId: string, from: string, luck: boolean?): number?
	local row = LuckyBlocks.kind(from)
	if row == nil then
		return nil
	elseif row.Turns == true then
		return BlockDrop.oneIn(BlockDrop.cuePercent(cueId, { mystery = true, luck = luck }))
	elseif row.Climb ~= nil then
		return BlockDrop.oneIn(BlockDrop.cuePercent(cueId, { start = row.Climb, luck = luck }))
	elseif row.Odds ~= nil then
		for _, entry in BlockOdds.cueOdds(row.Odds, nil, true) do
			if entry.id == cueId then
				return BlockDrop.oneIn(entry.percent)
			end
		end
	end
	return nil
end

--- Whether a cue of `rarity` opens with the quick reveal instead of the reel
--- (Config.LuckyBlocks.QuickReveal: none since 2026-10-09, every open spins the reel).
function LuckyBlocks.quickReveal(rarity: string): boolean
	return table.find(L.QuickReveal or {}, rarity) ~= nil
end

--- The blocks "Open all" opens at `now` for player `userId` (Config.LuckyBlocks.OpenAll): the
--- ready blocks of its tiers (economy v5.2: unclimbed ones climb as they open; a climbed one
--- from the old climb screen too), oldest first (by id), at most Max, leaving out `skip` (the
--- block in the hands and the thrown ones).
function LuckyBlocks.openAllIds(
	state: State,
	now: number,
	userId: number,
	skip: { [number]: boolean }?
): { number }
	local rule = L.OpenAll
	local out: { number } = {}
	for _, block in state.List do
		if
			table.find(rule.Tiers, block.Kind) ~= nil
			and not LuckyBlocks.needsRoll(block)
			and not (skip and skip[block.Id])
			and LuckyBlocks.canOpen(block, now, userId)
		then
			table.insert(out, block.Id)
		end
	end
	table.sort(out)
	while #out > rule.Max do
		table.remove(out)
	end
	return out
end

--- Designer-only bypass never changes ReadyAt: the original countdown remains visible.
function LuckyBlocks.canOpen(block: Block, now: number, userId: number): boolean
	return LuckyBlocks.isReady(block, now)
		or (L.Test.BypassTimer and table.find(Config.Debug.Commands.UserIds, userId) ~= nil)
end

--- VIP has no timers (designer, 2026-10-07): every block still on its timer is ready at `now`
--- (its origin unchanged). Returns how many were finished.
function LuckyBlocks.finishTimers(state: State, now: number): number
	local n = 0
	for _, block in state.List do
		if block.ReadyAt > now then
			block.ReadyAt = now
			n += 1
		end
	end
	return n
end

---------------------------------------------------------------------------------------------
-- The skip by time left (Config.LuckyBlocks.Skips; economy v4, designer 2026-10-08)
---------------------------------------------------------------------------------------------

type SkipRow = { UpTo: number?, Product: string }
local SKIPS: { SkipRow } = Config.LuckyBlocks.Skips :: any

--- The skip tier a timer with `seconds` left needs (1..#Skips): the first row whose UpTo
--- covers it, else the last.
function LuckyBlocks.skipTierFor(seconds: number): number
	for i, row in SKIPS do
		if row.UpTo == nil or seconds <= row.UpTo then
			return i
		end
	end
	return #SKIPS
end

--- The skip product for `block` at `now` (the price for the time left right now) and its
--- tier, or nil for a block that is ready.
function LuckyBlocks.skipProduct(block: Block, now: number): (string?, number?)
	local left = LuckyBlocks.secondsLeft(block, now)
	if left <= 0 then
		return nil, nil
	end
	local tier = LuckyBlocks.skipTierFor(left)
	return SKIPS[tier].Product, tier
end

--- The skip tier a Config.Products key buys, or nil for any other key.
function LuckyBlocks.skipTierOf(key: string): number?
	for i, row in SKIPS do
		if row.Product == key then
			return i
		end
	end
	return nil
end

--- The credits held for skip product `product` (0 for none).
function LuckyBlocks.credits(state: State, product: string): number
	local credits = state.Credits
	local n = if type(credits) == "table" then credits[product] else nil
	return if type(n) == "number" and n == n and n > 0 then math.floor(n) else 0
end

--- Spend one previously purchased credit on precisely this still-running timer: the cheapest
--- credit whose row covers the time left (a credit never skips a longer timer than it was
--- bought for).
function LuckyBlocks.useSkip(state: State, id: number, now: number): boolean
	local block = LuckyBlocks.find(state, id)
	if block == nil or LuckyBlocks.isReady(block, now) then
		return false
	end
	local need = LuckyBlocks.skipTierFor(LuckyBlocks.secondsLeft(block, now))
	for tier = need, #SKIPS do
		local product = SKIPS[tier].Product
		local have = LuckyBlocks.credits(state, product)
		if have >= 1 then
			(state.Credits :: { [string]: number })[product] = have - 1
			state.SkipTarget = 0
			block.ReadyAt = now
			block.Paid = true
			return true
		end
	end
	return false
end

--- Receipt grant of skip product `product` (nil or not a skip row: the top one): never lose a
--- purchase if its target disappeared or finished while offline (it stays a credit of that
--- product).
function LuckyBlocks.grantSkip(state: State, now: number, product: string?)
	local key = if product ~= nil and LuckyBlocks.skipTierOf(product) ~= nil
		then product
		else SKIPS[#SKIPS].Product
	if type(state.Credits) ~= "table" then
		state.Credits = {}
	end
	local credits = state.Credits :: { [string]: number }
	credits[key] = LuckyBlocks.credits(state, key) + 1
	LuckyBlocks.useSkip(state, state.SkipTarget or 0, now)
	state.SkipTarget = 0
end

--- Whole seconds until `block` is ready (0 once it is), rounded up.
function LuckyBlocks.secondsLeft(block: Block, now: number): number
	return math.max(0, math.ceil(block.ReadyAt - now))
end

--- A countdown: "1:42", "0:05"; an hour or more "1:02:09".
function LuckyBlocks.clockText(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	local h, m = s // 3600, (s // 60) % 60
	if h > 0 then
		return ("%d:%02d:%02d"):format(h, m, s % 60)
	end
	return ("%d:%02d"):format(m, s % 60)
end

--- The block with `id` and its place in the list, or nil.
function LuckyBlocks.find(state: State, id: number): (Block?, number?)
	for i, block in state.List do
		if block.Id == id then
			return block, i
		end
	end
	return nil, nil
end

--- Adds a block of `kind` landing at `now`, at place `at` (1..#List + 1; nil: the end), on its
--- timer (economy v5.2: its own name's; the Gift's Wait first). A climbing kind arrives
--- unclimbed. `climbed` adds a block tier's climbed block instead (a trade, the dev commands).
--- A `paid` one is ready at once and keeps its paid origin; `vip` takes the VIP timer, none.
--- Returns the new block. Errors on an unknown kind, or `climbed` for a kind that has no
--- climbed block: never a broken block.
function LuckyBlocks.add(
	state: State,
	kind: string,
	now: number,
	at: number?,
	paid: boolean?,
	vip: boolean?,
	climbed: boolean?
): Block
	assert(LuckyBlocks.kind(kind) ~= nil, "LuckyBlocks.add: unknown kind " .. tostring(kind))
	kind = LuckyBlocks.current(kind)
	assert(
		climbed ~= true or table.find(Config.BlockOdds.Order, kind) ~= nil,
		"LuckyBlocks.add: no climbed block of " .. kind
	)
	state.Next += 1
	local delay = LuckyBlocks.timer(kind, vip)
		+ (if climbed ~= true then LuckyBlocks.wait(kind, vip) else 0)
	local block: Block = {
		Id = state.Next,
		Kind = kind,
		ReadyAt = if paid then now else now + delay,
	}
	if paid then
		block.Paid = true
	end
	if climbed == true then
		block.Climbed = true
	end
	local place = math.clamp(at or #state.List + 1, 1, #state.List + 1)
	table.insert(state.List, place, block)
	return block
end

--- A Mystery's roll turned the unclimbed Mystery block `id` into an unclimbed block of `tier`
--- (economy v5.1): the same block the restock and the rewards give. It keeps its id, its place
--- and its origin, carries `waits` (the pity counters still waiting on its climb: "Rare" or
--- "Epic", else none) and starts that tier's timer at `now` (economy v5.2; a paid one is ready
--- at once, `vip` takes the VIP timer, none). The open is counted for the Mystery. Returns the
--- block, or nil when there is no such block. Errors on a tier that has no block or a block
--- that is not an unclimbed turning kind.
function LuckyBlocks.turn(
	state: State,
	id: number,
	tier: string,
	now: number,
	waits: string?,
	vip: boolean?
): Block?
	assert(
		table.find(Config.BlockOdds.Order, tier) ~= nil,
		"LuckyBlocks.turn: no block of tier " .. tostring(tier)
	)
	local block = LuckyBlocks.find(state, id)
	if block == nil then
		return nil
	end
	assert(
		block.Climbed ~= true and LuckyBlocks.turns(block.Kind),
		"LuckyBlocks.turn: the block does not turn"
	)
	LuckyBlocks.noteOpened(state, block.Kind)
	block.Kind = tier
	block.ReadyAt = if block.Paid then now else now + LuckyBlocks.timer(tier, vip)
	block.Pity = if waits == "Rare" or waits == "Epic" then waits else nil
	return block
end

--- Removes the block with `id`: returns it and the place it had, or nil.
function LuckyBlocks.remove(state: State, id: number): (Block?, number?)
	local block, i = LuckyBlocks.find(state, id)
	if block and i then
		table.remove(state.List, i)
	end
	return block, i
end

--- Moves the block with `id` to place `to` (clamped to the list); the others close up round it.
--- False when there is no such block.
function LuckyBlocks.move(state: State, id: number, to: number): boolean
	local block = LuckyBlocks.remove(state, id)
	if block == nil then
		return false
	end
	table.insert(state.List, math.clamp(to, 1, #state.List + 1), block)
	return true
end

--- How many blocks of `kind` the state holds.
function LuckyBlocks.count(state: State, kind: string): number
	local n = 0
	for _, block in state.List do
		if block.Kind == kind then
			n += 1
		end
	end
	return n
end

-- The Gift block's first-leave drop (designer, 2026-10-07): the save's Flags hold when the
-- player first left the game (GiftLeftAt, unix seconds) and whether the Gift has landed and been
-- picked up (GiftLanded). Its timer runs from the leave, so a player back the next day finds it
-- ready (Config.LuckyBlocks.GiftDrop).
LuckyBlocks.GiftFlags = table.freeze({ LeftAt = "GiftLeftAt", Landed = "GiftLanded" })

--- Notes the player's first leave at `now`: true when this leave is the first (the flag was set).
function LuckyBlocks.noteLeave(flags: { [string]: any }, now: number): boolean
	if flags[LuckyBlocks.GiftFlags.LeftAt] ~= nil then
		return false
	end
	flags[LuckyBlocks.GiftFlags.LeftAt] = now
	return true
end

--- Whether a Gift is waiting to fall from the sky (left once, not yet picked up).
function LuckyBlocks.giftPending(flags: { [string]: any }): boolean
	return type(flags[LuckyBlocks.GiftFlags.LeftAt]) == "number"
		and flags[LuckyBlocks.GiftFlags.Landed] ~= true
end

--- The Gift is picked up: it goes first in the list, its timer running from the leave, and the
--- drop is marked done. Nil (nothing changed) when no Gift is waiting.
function LuckyBlocks.landGift(state: State, flags: { [string]: any }, vip: boolean?): Block?
	if not LuckyBlocks.giftPending(flags) then
		return nil
	end
	local block = LuckyBlocks.add(state, "Gift", flags[LuckyBlocks.GiftFlags.LeftAt], 1, nil, vip)
	flags[LuckyBlocks.GiftFlags.Landed] = true
	return block
end

--- The client's copy: { { id, kind, readyAt, climbed? } } in list order (`climbed`: a block
--- that climbed on the old climb screen, economy v5; nil for any other).
function LuckyBlocks.snapshot(
	state: State
): { { id: number, kind: string, readyAt: number, climbed: boolean? } }
	local list = {}
	for _, block in state.List do
		table.insert(list, {
			id = block.Id,
			kind = block.Kind,
			readyAt = block.ReadyAt,
			climbed = if block.Climbed == true then true else nil,
		})
	end
	return list
end

--- Everything wrong with the kinds against the odds rows, sorted (empty when all is well): a kind
--- missing from Order or Kinds, an odds row that does not exist, a timer that is not a whole number
--- of seconds, or an empty model name. Checked when this module loads.
function LuckyBlocks.validate(): { string }
	local problems = {}
	for _, id in L.Order do
		local row = KINDS[id]
		if row == nil then
			table.insert(problems, id .. ": in Order but not in Kinds")
		else
			-- A climbing kind names a ladder tier to start from; a block tier's own kind is also
			-- its climbed block, which rolls its own row. A kind that never climbs rolls a row.
			local tiers: { string } = Config.BlockOdds.Climb.Tiers
			if row.Climb ~= nil then
				if not table.find(Config.BlockOdds.Order, row.Climb) then
					table.insert(
						problems,
						("%s: Climb %s is not a block tier"):format(id, tostring(row.Climb))
					)
				end
				local own = table.find(Config.BlockOdds.Order, id) ~= nil
				if own and (row.Climb ~= id or row.Odds ~= id) then
					table.insert(
						problems,
						id .. ": a tier's block climbs from and rolls its own tier"
					)
				elseif not own and row.Odds ~= nil then
					table.insert(problems, id .. ": a climbing kind that is not a tier has no Odds")
				end
			elseif BlockOdds.get(row.Odds) == nil then
				table.insert(problems, ("%s: no odds row %s"):format(id, tostring(row.Odds)))
			elseif table.find(tiers, id) ~= nil then
				table.insert(problems, id .. ": a tier's block must climb")
			end
			if row.Pity and row.Climb == nil then
				table.insert(problems, id .. ": Pity without Climb")
			end
			if row.Turns and (row.Climb ~= Config.BlockOdds.Climb.Tiers[1] or not row.Pity) then
				table.insert(problems, id .. ": Turns needs a Standard Climb and Pity")
			end
			if
				row.Wait ~= nil
				and (type(row.Wait) ~= "number" or row.Wait < 0 or row.Wait ~= math.floor(row.Wait))
			then
				table.insert(problems, id .. ": Wait is not whole seconds")
			end
			local g = row.Guarantee
			if g ~= nil then
				local cue = Catalog.get(g.Cue)
				if cue == nil or cue.Group ~= "Unique" then
					table.insert(problems, id .. ": Guarantee.Cue is not a Unique cue")
				elseif row.Odds == nil or not BlockOdds.canDrop(row.Odds, g.Cue) then
					table.insert(problems, id .. ": Guarantee.Cue does not drop from its odds row")
				end
				if type(g.At) ~= "number" or g.At < 1 or g.At ~= math.floor(g.At) then
					table.insert(problems, id .. ": Guarantee.At is not a whole count")
				end
			end
			if
				type(row.Timer) ~= "number"
				or row.Timer < 0
				or row.Timer ~= math.floor(row.Timer)
			then
				table.insert(problems, id .. ": Timer is not whole seconds")
			end
			if type(row.Model) ~= "string" or row.Model == "" then
				table.insert(problems, id .. ": no Model")
			end
			if
				row.Idle ~= nil
				and (type(row.Idle) ~= "string" or not string.find(row.Idle, "^rbxassetid://%d+$"))
			then
				table.insert(problems, id .. ": Idle is not an rbxassetid:// id")
			end
		end
	end
	for id in KINDS do
		if table.find(L.Order, id) == nil then
			table.insert(problems, id .. ": in Kinds but not in Order")
		end
	end
	for old, new in RENAMED do
		if KINDS[new] == nil or KINDS[old] ~= nil then
			table.insert(problems, ("Renamed %s -> %s is not an old id of a kind"):format(old, new))
		end
	end
	table.sort(problems)
	return problems
end

do
	local problems = LuckyBlocks.validate()
	assert(#problems == 0, "Config.LuckyBlocks: " .. table.concat(problems, "; "))
end

-- A whole number in min..max (never NaN or infinite).
local function wholeIn(x: any, min: number, max: number): boolean
	return type(x) == "number" and x == x and x >= min and x <= max and x == math.floor(x)
end

local ID_CAP = Config.Save.StatCap

--- Checks a BlockRequest's arguments (anything a client sent) and answers the request, or
--- (nil, "BadRequest"). Only shapes are checked here; ownership, timers, the body and the
--- distance are the server's to check.
function LuckyBlocks.parse(action: any, a: any, b: any): (Request?, string?)
	if action == "Hold" then
		if a == nil then
			return { action = "Hold" }, nil
		elseif wholeIn(a, 1, ID_CAP) then
			return { action = "Hold", id = a }, nil
		end
	elseif action == "Throw" or action == "Open" or action == "Reveal" then
		if wholeIn(a, 1, ID_CAP) then
			return { action = action :: string, id = a }, nil
		end
	elseif action == "OpenAll" then
		return { action = "OpenAll" }, nil
	elseif action == "Move" then
		if wholeIn(a, 1, ID_CAP) and wholeIn(b, 1, L.MaxBlocks) then
			return { action = "Move", id = a, to = b }, nil
		end
	end
	return nil, "BadRequest"
end

return LuckyBlocks
