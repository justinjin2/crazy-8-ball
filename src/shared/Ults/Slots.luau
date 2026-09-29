--!strict
-- A save's ults (docs/prompts/ULTIMATES_PROMPT.md sections 8-10): the three slots, which one is
-- selected and locked, the spins held, pity and the daily free spin. Pure functions over the
-- save's `Ults` table (SaveSchema v3): no Instances, no Roblox APIs, no clocks (the caller
-- passes the UTC day number, Daily.dayOf) and no randomness (Roll picks the ult).
--
-- Layout (Slots.fresh): `Slots` is a gapless array of Config.Ults.Slots strings, "" for an
-- empty slot, and `Locked` an array of as many booleans, because ProfileStore takes no arrays
-- with holes. Slot ownership is not saved: slot 1 is free and the others come from game passes
-- (Config.Ults.SlotPasses), passed in as `passes` = { UltSlot2 = true, ... }.
--
-- Every function checks its arguments (a slot of 9, 0, 1.5 or "2", a negative or fractional
-- count, a non-boolean) and refuses with `false, reason` rather than erroring, since the
-- server hands it what a client sent. The save itself is trusted (SaveSchema.validate repaired
-- it on load). Reasons: "BadData" (not an Ults table), "BadSlot", "BadValue", "BadCount",
-- "BadDay", "UnknownUlt", "NotOwned", "Locked", "NoSpins", "NoLucky".
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)

local U = Config.Ults
local E = U.Earn

local Slots = {}

export type Ults = {
	Slots: { string }, -- ult id per slot, "" = empty
	Selected: number, -- 1..Config.Ults.Slots: the slot spun into and played with
	Locked: { boolean }, -- a locked slot cannot be spun
	Spins: number, -- normal spins held, 0..Earn.MaxSpins
	LuckySpins: number, -- Lucky Spins held, 0..Earn.MaxSpins
	Pity: number, -- spins since the last Epic+, 0..Roll.PityAt - 1
	FreeSpinDay: number, -- the UTC day the daily free spin was last used (0: never)
	SpinsDone: number, -- every spin ever rolled
	QueueUlts: boolean, -- the global queue's Ults On / Off choice
}

export type Passes = { [string]: boolean? } -- { UltSlot2 = true, UltSlot3 = false }

--- A new save's ults: the default ult (Magnet) in slot 1, the others empty, slot 1 selected,
--- nothing locked, the starter spins, the queue's ults on.
function Slots.fresh(): Ults
	local slots: { string } = {}
	local locked: { boolean } = {}
	for i = 1, U.Slots do
		slots[i] = if i == 1 then U.Default else ""
		locked[i] = false
	end
	return {
		Slots = slots,
		Selected = 1,
		Locked = locked,
		Spins = E.Starter,
		LuckySpins = 0,
		Pity = 0,
		FreeSpinDay = 0,
		SpinsDone = 0,
		QueueUlts = true,
	}
end

-- True for a finite whole number.
local function isWhole(x: any): boolean
	return type(x) == "number"
		and x == x
		and x ~= math.huge
		and x ~= -math.huge
		and x == math.floor(x)
end

--- True for a slot number: a whole number in 1..Config.Ults.Slots (never a string).
function Slots.isSlot(slot: any): boolean
	return isWhole(slot) and slot >= 1 and slot <= U.Slots
end

local function isUlts(ults: any): boolean
	return type(ults) == "table" and type(ults.Slots) == "table" and type(ults.Locked) == "table"
end

--- True when the player owns `slot`: slot 1 always; another only with its game pass
--- (Config.Ults.SlotPasses) true in `passes`. False for anything that is not a slot.
function Slots.owns(slot: any, passes: Passes?): boolean
	if not Slots.isSlot(slot) then
		return false
	end
	local pass = U.SlotPasses[slot]
	if pass == nil or pass == "" then
		return true
	end
	return type(passes) == "table" and passes[pass] == true
end

--- The ult to play with: the selected slot's ult when that slot is owned and the ult usable
--- (built, or anything with the developer flag), else Config.Ults.Default.
function Slots.equipped(ults: any, passes: Passes?, devAll: boolean?): string
	if not isUlts(ults) or not Slots.owns(ults.Selected, passes) then
		return U.Default
	end
	local id = ults.Slots[ults.Selected]
	if Catalog.usable(id, devAll) then
		return id
	end
	return U.Default
end

--- The ult in the selected slot ("" when empty or the save is broken).
function Slots.selectedUlt(ults: any): string
	if not isUlts(ults) or not Slots.isSlot(ults.Selected) then
		return ""
	end
	local id = ults.Slots[ults.Selected]
	return if type(id) == "string" then id else ""
end

--- Selects slot `slot`. Returns true, or false and "BadData", "BadSlot" or "NotOwned".
function Slots.select(ults: any, slot: any, passes: Passes?): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif not Slots.isSlot(slot) then
		return false, "BadSlot"
	elseif not Slots.owns(slot, passes) then
		return false, "NotOwned"
	end
	ults.Selected = slot
	return true, nil
end

--- Locks or unlocks slot `slot` (`locked` must be true or false). Returns true, or false and
--- "BadData", "BadSlot", "BadValue" or "NotOwned".
function Slots.setLock(ults: any, slot: any, locked: any, passes: Passes?): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif not Slots.isSlot(slot) then
		return false, "BadSlot"
	elseif type(locked) ~= "boolean" then
		return false, "BadValue"
	elseif not Slots.owns(slot, passes) then
		return false, "NotOwned"
	end
	ults.Locked[slot] = locked
	return true, nil
end

--- True when the daily free spin of UTC day `day` is unused (it never stacks: an unused day is
--- simply missed). False for a day that is not a whole number >= 0.
function Slots.freeSpinReady(ults: any, day: any): boolean
	return isUlts(ults) and isWhole(day) and day >= 0 and ults.FreeSpinDay ~= day
end

--- Whether a spin may be made now: `lucky` true for a Lucky Spin, false for a normal one
--- (which uses the daily free spin first). Returns true, or false and "BadData", "BadValue",
--- "BadDay", "NotOwned" (the selected slot's pass is gone), "Locked" (the selected slot is
--- locked), "NoLucky" or "NoSpins".
function Slots.canSpin(ults: any, lucky: any, day: any, passes: Passes?): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif type(lucky) ~= "boolean" then
		return false, "BadValue"
	elseif not isWhole(day) or day < 0 then
		return false, "BadDay"
	elseif not Slots.owns(ults.Selected, passes) then
		return false, "NotOwned"
	elseif ults.Locked[ults.Selected] == true then
		return false, "Locked"
	end
	if lucky then
		if not isWhole(ults.LuckySpins) or ults.LuckySpins < 1 then
			return false, "NoLucky"
		end
	elseif not Slots.freeSpinReady(ults, day) and (not isWhole(ults.Spins) or ults.Spins < 1) then
		return false, "NoSpins"
	end
	return true, nil
end

--- Uses up one spin: for a Lucky Spin one of LuckySpins ("Lucky"); for a normal spin the day's
--- free spin while it is unused ("Free", FreeSpinDay = day), else one of Spins ("Spin"). Returns
--- which, or nil and the reason ("BadData", "BadValue", "BadDay", "NoLucky", "NoSpins"). Check
--- Slots.canSpin first (this does not look at the slot).
function Slots.take(ults: any, lucky: any, day: any): (string?, string?)
	if not isUlts(ults) then
		return nil, "BadData"
	elseif type(lucky) ~= "boolean" then
		return nil, "BadValue"
	elseif not isWhole(day) or day < 0 then
		return nil, "BadDay"
	end
	if lucky then
		if not isWhole(ults.LuckySpins) or ults.LuckySpins < 1 then
			return nil, "NoLucky"
		end
		ults.LuckySpins -= 1
		return "Lucky", nil
	end
	if Slots.freeSpinReady(ults, day) then
		ults.FreeSpinDay = day
		return "Free", nil
	end
	if not isWhole(ults.Spins) or ults.Spins < 1 then
		return nil, "NoSpins"
	end
	ults.Spins -= 1
	return "Spin", nil
end

--- Puts ult `id` (a catalog id) in the selected slot and counts the spin (SpinsDone). Returns
--- the id it replaced ("" for an empty slot), or nil and "BadData", "BadSlot" or "UnknownUlt".
function Slots.place(ults: any, id: any): (string?, string?)
	if not isUlts(ults) then
		return nil, "BadData"
	elseif not Slots.isSlot(ults.Selected) then
		return nil, "BadSlot"
	elseif not Catalog.exists(id) then
		return nil, "UnknownUlt"
	end
	local old = Slots.selectedUlt(ults)
	ults.Slots[ults.Selected] = id
	local done = if isWhole(ults.SpinsDone) then ults.SpinsDone else 0
	ults.SpinsDone = math.clamp(done + 1, 0, Config.Save.StatCap)
	return old, nil
end

--- True when a spin would replace an ult of Config.Ults.ConfirmReplaceFrom (Epic) or rarer in
--- the selected slot, so the screen asks "Replace BLACK FLASH?" first.
function Slots.needsConfirm(ults: any): boolean
	local rarity = Catalog.rarity(Slots.selectedUlt(ults))
	return rarity ~= nil
		and Catalog.rarityIndex(rarity) >= Catalog.rarityIndex(U.ConfirmReplaceFrom)
end

-- Adds `n` (a whole number >= 1) to ults[key], capped at Earn.MaxSpins.
local function add(ults: any, key: string, n: any): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif not isWhole(n) or n < 1 then
		return false, "BadCount"
	end
	local held = if isWhole(ults[key]) then math.max(ults[key], 0) else 0
	ults[key] = math.min(held + n, E.MaxSpins)
	return true, nil
end

-- Sets ults[key] to `n`, a whole number in 0..max.
local function set(ults: any, key: string, n: any, max: number): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif not isWhole(n) or n < 0 or n > max then
		return false, "BadCount"
	end
	ults[key] = n
	return true, nil
end

--- Adds `n` normal spins (a whole number >= 1), capped at Config.Ults.Earn.MaxSpins. Returns
--- true, or false and "BadData" or "BadCount".
function Slots.addSpins(ults: any, n: any): (boolean, string?)
	return add(ults, "Spins", n)
end

--- Adds `n` Lucky Spins (a whole number >= 1), capped at Config.Ults.Earn.MaxSpins.
function Slots.addLucky(ults: any, n: any): (boolean, string?)
	return add(ults, "LuckySpins", n)
end

--- Sets the normal spins held to `n` (0..MaxSpins; the `/spins N` dev command).
function Slots.setSpins(ults: any, n: any): (boolean, string?)
	return set(ults, "Spins", n, E.MaxSpins)
end

--- Sets the Lucky Spins held to `n` (0..MaxSpins; the `/lucky N` dev command).
function Slots.setLucky(ults: any, n: any): (boolean, string?)
	return set(ults, "LuckySpins", n, E.MaxSpins)
end

--- Sets pity to `n`, a whole number in 0..Config.Ults.Roll.PityAt - 1 (Roll.roll's new pity,
--- or the `/pity N` dev command).
function Slots.setPity(ults: any, n: any): (boolean, string?)
	return set(ults, "Pity", n, U.Roll.PityAt - 1)
end

--- Sets the global queue's Ults On / Off choice (`on` must be true or false).
function Slots.setQueueUlts(ults: any, on: any): (boolean, string?)
	if not isUlts(ults) then
		return false, "BadData"
	elseif type(on) ~= "boolean" then
		return false, "BadValue"
	end
	ults.QueueUlts = on
	return true, nil
end

return Slots
