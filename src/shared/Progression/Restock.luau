--!strict
-- Restock: the restock shop (the approved economy plan, 2026-10-02, section 4). Every
-- Config.Shop.Restock.SlotSeconds on the clock (UTC :00, :10 ...) a new restock: an Uncommon
-- Case always, a Rare Case in RareChance of restocks, a lucky slot (an Epic Case, a Legendary
-- Case, else 3 Mystery Cases) and a VIP-only Rare Case. The items come from the slot number
-- through an integer hash, so every server shows the same restock with no messaging.
--
-- Stock is per player per restock (the save's Shop.Restock = { Slot, Bought = { [id] = n } },
-- which starts over when the slot changes). The Legendary Case also has a GlobalStock shared by
-- every player for that restock: the server's atomic counter (Counts.reserve), not this module.
--
-- Pure: no Instances, no clocks (the caller passes `now`), no randomness. Lune-tested.
local Config = require(script.Parent.Parent.Config)

local R = Config.Shop.Restock

-- One restock item. `id` names it in requests and the save ("Uncommon", "Rare", "Epic",
-- "Legendary", "Mystery", "Vip").
export type Item = {
	id: string,
	case: string?, -- the case it gives (nil for the Mystery Cases)
	mystery: number?, -- Mystery Cases it gives (Case Drops)
	price: number, -- money
	product: string?, -- the Config.Products key that buys it with Robux
	stock: number, -- per player per restock
	global: number?, -- copies for everyone in every server this restock (the Legendary Case)
	vip: boolean, -- VIP only
}

-- The save's restock record.
export type Save = { Slot: number, Bought: { [string]: number } }

local Restock = {}

local TWO32 = 4294967296

-- a * b mod 2^32 for whole numbers below 2^32, without losing precision in doubles.
local function mul32(a: number, b: number): number
	local aHi, aLo = a // 65536, a % 65536
	local bHi, bLo = b // 65536, b % 65536
	local cross = (aHi * bLo + aLo * bHi) % 65536
	return (cross * 65536 + aLo * bLo) % TWO32
end

-- A well-mixed whole number in 0..2^32-1 from a slot number and a salt (the same everywhere).
local function hash(slot: number, salt: number): number
	local h = bit32.bxor(slot % TWO32, mul32(salt + 1, 0x9E3779B1))
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	h = mul32(h, 0x45D9F3B)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h
end

--- A roll in 0..ChanceTotal-1 for slot `slot` and salt `salt` (exposed for the tests).
function Restock.roll(slot: number, salt: number): number
	return hash(slot, salt) % R.ChanceTotal
end

--- The restock slot at unix time `now`.
function Restock.slotOf(now: number): number
	return math.floor(now / R.SlotSeconds)
end

--- When restock `slot` starts and ends (unix seconds).
function Restock.window(slot: number): (number, number)
	return slot * R.SlotSeconds, (slot + 1) * R.SlotSeconds
end

local function item(id: string, row: any, vip: boolean): Item
	return {
		id = id,
		case = row.Case,
		mystery = row.Mystery,
		price = row.Price,
		product = row.Product,
		stock = row.Stock,
		global = row.GlobalStock,
		vip = vip,
	}
end

--- Restock `slot`'s items in shop order: Uncommon, Rare (sometimes), the lucky slot, VIP.
function Restock.items(slot: number): { Item }
	local list = { item("Uncommon", R.Uncommon, false) }
	if Restock.roll(slot, 1) < R.RareChance then
		table.insert(list, item("Rare", R.Rare, false))
	end
	local lucky = Restock.roll(slot, 2)
	if lucky < R.LegendaryChance then
		table.insert(list, item("Legendary", R.Legendary, false))
	elseif lucky < R.LegendaryChance + R.EpicChance then
		table.insert(list, item("Epic", R.Epic, false))
	else
		table.insert(list, item("Mystery", R.Mystery, false))
	end
	table.insert(list, item("Vip", R.Vip, true))
	return list
end

--- The shared stock key of restock `slot`'s global item (the server's atomic counter).
function Restock.stockKey(slot: number): string
	return "Legendary:" .. tostring(slot)
end

--- Restock `slot`'s item `id`, or nil when it is not in that restock.
function Restock.find(slot: number, id: any): Item?
	for _, it in Restock.items(slot) do
		if it.id == id then
			return it
		end
	end
	return nil
end

--- The restock item a Robux product buys in `slot` (RestockEpic, RestockLegendary), or nil.
function Restock.forProduct(slot: number, key: string): Item?
	for _, it in Restock.items(slot) do
		if it.product == key then
			return it
		end
	end
	return nil
end

local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or x < 0 or x == math.huge then
		return 0
	end
	return math.floor(x)
end

--- How many of item `id` this player bought in restock `slot` (0 once the slot changed).
function Restock.bought(save: any, slot: number, id: string): number
	if type(save) ~= "table" or save.Slot ~= slot or type(save.Bought) ~= "table" then
		return 0
	end
	return whole(save.Bought[id])
end

--- Why this player cannot buy `it` in restock `slot` now, or nil: "NotSold" (not in this
--- restock), "VipOnly", "SoldOut" (their stock used up). The Legendary's global stock is the
--- server's counter's to answer.
function Restock.check(it: Item?, save: any, slot: number, isVip: boolean): string?
	if it == nil then
		return "NotSold"
	elseif it.vip and not isVip then
		return "VipOnly"
	elseif Restock.bought(save, slot, it.id) >= it.stock then
		return "SoldOut"
	end
	return nil
end

--- Records one buy of item `id` in restock `slot` (the record starts over for a new slot; a
--- buy for an older slot than the one recorded changes nothing). Changes `save`.
function Restock.record(save: any, slot: number, id: string)
	if whole(save.Slot) > slot then
		return
	end
	if save.Slot ~= slot or type(save.Bought) ~= "table" then
		save.Slot = slot
		save.Bought = {}
	end
	save.Bought[id] = whole(save.Bought[id]) + 1
end

--- Restock `slot` as ShopState shows it: { slot, startsAt, endsAt, items = { { id, case?,
--- mystery?, price, product?, stock, left (this player's), global?, globalLeft? (nil: not
--- known), vip, canBuy, reason? } } }. `globalSold`: the Legendary's copies taken this
--- restock (nil: unknown).
function Restock.view(slot: number, save: any, isVip: boolean, globalSold: number?): any
	local startsAt, endsAt = Restock.window(slot)
	local items = {}
	for _, it in Restock.items(slot) do
		local reason = Restock.check(it, save, slot, isVip)
		local globalLeft: number? = nil
		if it.global ~= nil and globalSold ~= nil then
			globalLeft = math.max(it.global - globalSold, 0)
			if globalLeft == 0 and reason == nil then
				reason = "SoldOut"
			end
		end
		table.insert(items, {
			id = it.id,
			case = it.case,
			mystery = it.mystery,
			price = it.price,
			product = it.product,
			stock = it.stock,
			left = math.max(it.stock - Restock.bought(save, slot, it.id), 0),
			global = it.global,
			globalLeft = globalLeft,
			vip = it.vip,
			canBuy = reason == nil,
			reason = reason,
		})
	end
	return { slot = slot, startsAt = startsAt, endsAt = endsAt, items = items }
end

return Restock
