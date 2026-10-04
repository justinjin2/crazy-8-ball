--!strict
-- LuckyBlocks (designer, 2026-10-03; Config.LuckyBlocks): the rules of the lucky blocks a
-- player holds. The save keeps them as { Next, List }: List is a gapless array in hotbar order
-- (the first Config.LuckyBlocks.HotbarSlots are the hotbar's slots 1..9, the rest wait in the
-- bag), each { Id, Kind, ReadyAt }; Next is the last id given, so ids never repeat in a save.
-- A block's cue is rolled from its kind's case (Cases.roll / Cases.cueOdds): no odds of its own.
--
-- Pure: no Instances, no Roblox APIs, no clocks (the caller passes `now`, unix seconds) and no
-- randomness; Lune-tested (tests/luckyblocks_test.luau). PlayerData calls the changes on the live
-- save; LuckyBlockService checks BlockRequest's arguments with `parse`.
local Config = require(script.Parent.Parent.Config)
local Cases = require(script.Parent.Cases)

local L = Config.LuckyBlocks

export type Kind = { Case: string, Timer: number, Model: string, Idle: string? }
export type Block = { Id: number, Kind: string, ReadyAt: number }
export type State = { Next: number, List: { Block } }

-- One checked BlockRequest. Only the fields its action uses are set.
export type Request = {
	action: string,
	id: number?, -- Hold (nil: put it away), Throw, Open, Move
	to: number?, -- Move: the place in the list, 1..MaxBlocks
}

local KINDS: { [string]: Kind } = L.Kinds :: any

local LuckyBlocks = {}

--- Every action a BlockRequest may name (Net "BlockRequest").
LuckyBlocks.Actions = table.freeze({ "Hold", "Throw", "Open", "Move" })

--- Every reason a refused BlockRequest may answer (Strings.LuckyBlocks.Reasons words them).
LuckyBlocks.Reasons = table.freeze({
	"BadRequest", -- an unknown action, a wrong type or an id that is not a whole number
	"TooFast", -- the token bucket is empty (Config.LuckyBlocks.RateBurst, RatePerSecond)
	"NotLoaded", -- the save is not loaded yet
	"NotOwned", -- no block with that id
	"NotReady", -- Throw: it is still on its timer
	"NotHeld", -- Throw: that block is not the one in the hands
	"Busy", -- Throw: another thrown block is still on the floor; Open: it is already opening
	"NoBody", -- the character is missing, dead or seated
	"TooFar", -- Open: too far from the block
	"NotLanded", -- Open: it is still flying
	"Error", -- anything else (logged on the server)
})

--- A kind's row, or nil for an unknown kind.
function LuckyBlocks.kind(id: any): Kind?
	if type(id) ~= "string" or table.find(L.Order, id) == nil then
		return nil
	end
	return KINDS[id]
end

--- A new player's blocks: none.
function LuckyBlocks.fresh(): State
	return { Next = 0, List = {} }
end

--- Seconds after landing until a block of `kind` can be thrown (0 for an unknown kind).
function LuckyBlocks.timer(kind: string): number
	local row = LuckyBlocks.kind(kind)
	return if row then row.Timer else 0
end

--- Whether `block` is off its timer at `now`.
function LuckyBlocks.isReady(block: Block, now: number): boolean
	return block.ReadyAt <= now
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

--- Adds a block of `kind` landing at `now` (its timer starts), at place `at` (1..#List + 1;
--- nil: the end). Returns the new block. Errors on an unknown kind: never a broken block.
function LuckyBlocks.add(state: State, kind: string, now: number, at: number?): Block
	assert(LuckyBlocks.kind(kind) ~= nil, "LuckyBlocks.add: unknown kind " .. tostring(kind))
	state.Next += 1
	local block = { Id = state.Next, Kind = kind, ReadyAt = now + LuckyBlocks.timer(kind) }
	local place = math.clamp(at or #state.List + 1, 1, #state.List + 1)
	table.insert(state.List, place, block)
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

--- The client's copy: { { id, kind, readyAt } } in list order.
function LuckyBlocks.snapshot(state: State): { { id: number, kind: string, readyAt: number } }
	local list = {}
	for _, block in state.List do
		table.insert(list, { id = block.Id, kind = block.Kind, readyAt = block.ReadyAt })
	end
	return list
end

--- Everything wrong with the kinds against the cases, sorted (empty when all is well): a kind
--- missing from Order or Kinds, a case that does not exist, a timer that is not a whole number
--- of seconds, or an empty model name. Checked when this module loads.
function LuckyBlocks.validate(): { string }
	local problems = {}
	for _, id in L.Order do
		local row = KINDS[id]
		if row == nil then
			table.insert(problems, id .. ": in Order but not in Kinds")
		else
			if Cases.get(row.Case) == nil then
				table.insert(problems, ("%s: no case %s"):format(id, tostring(row.Case)))
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
	elseif action == "Throw" or action == "Open" then
		if wholeIn(a, 1, ID_CAP) then
			return { action = action :: string, id = a }, nil
		end
	elseif action == "Move" then
		if wholeIn(a, 1, ID_CAP) and wholeIn(b, 1, L.MaxBlocks) then
			return { action = "Move", id = a, to = b }, nil
		end
	end
	return nil, "BadRequest"
end

return LuckyBlocks
