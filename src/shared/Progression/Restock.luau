--!strict
-- Restock: the restock shop (the lucky-block economy, designer 2026-10-04; ECONOMY section
-- 12). Every Config.Shop.Restock.SlotSeconds on the clock (UTC :00, :10 ...) a new restock:
-- Slots slots that each roll one lucky block kind by Odds (an Uncommon most of the time, a
-- Rare often, an Epic rarely, a Legendary almost never), and a VIP-only slot rolled by
-- VipOdds. The kinds come from the slot number through an integer hash, so every server
-- shows the same restock with no messaging.
--
-- Stock is per player per restock per slot (the save's Shop.Restock = { Slot, Bought = { [id]
-- = n } }, which starts over when the restock changes). No item has a shared stock now; the
-- `global` field and stockKey stay so the server's stock counter code keeps working for a
-- later item that has one.
--
-- Pure: no Instances, no clocks (the caller passes `now`), no randomness. Lune-tested.
local Config = require(script.Parent.Parent.Config)

local R = Config.Shop.Restock
-- One kind's row: the money price, the Robux product (if any) and the stock per player.
type KindRow = { Price: number, Product: string?, Stock: number, GlobalStock: number? }
local KINDS: { [string]: KindRow } = R.Kinds :: any
-- The kinds in Config.LuckyBlocks.Order (walked in that order when a roll is read, so the
-- answer never depends on hash order).
local KIND_ORDER: { string } = Config.LuckyBlocks.Order

-- One restock item. `id` names it in requests and the save ("Slot1" .. "Slot3", "Vip").
export type Item = {
	id: string,
	block: string, -- the lucky block kind it gives (Config.LuckyBlocks.Kinds)
	price: number, -- money
	product: string?, -- the Config.Products key that buys it with Robux
	stock: number, -- per player per restock
	global: number?, -- copies for everyone everywhere this restock (none has one now)
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

--- The block kind a roll in 0..ChanceTotal-1 lands on in an odds table ({ kind = weight },
--- parts of ChanceTotal; a short table lands on its last kind for the rest). Walks the kinds
--- in Config.LuckyBlocks.Order.
function Restock.kindOf(roll: number, odds: { [string]: number }): string
	local reached = 0
	local last = ""
	for _, kind in KIND_ORDER do
		local weight = odds[kind]
		if type(weight) == "number" and weight > 0 then
			last = kind
			reached += weight
			if roll < reached then
				return kind
			end
		end
	end
	return last
end

local function item(id: string, kind: string, vip: boolean): Item
	local row = KINDS[kind]
	assert(row ~= nil, "Restock: no Config.Shop.Restock.Kinds row for " .. kind)
	return {
		id = id,
		block = kind,
		price = row.Price,
		product = row.Product,
		stock = row.Stock,
		global = row.GlobalStock,
		vip = vip,
	}
end

--- Restock `slot`'s items in shop order: Slot1 .. Slot<Slots> (each a rolled kind), then Vip.
function Restock.items(slot: number): { Item }
	local list = {}
	for i = 1, R.Slots do
		table.insert(list, item("Slot" .. i, Restock.kindOf(Restock.roll(slot, i), R.Odds), false))
	end
	table.insert(
		list,
		item("Vip", Restock.kindOf(Restock.roll(slot, R.Slots + 1), R.VipOdds), true)
	)
	return list
end

--- Every item id a restock may hold, in shop order.
function Restock.ids(): { string }
	local list = {}
	for i = 1, R.Slots do
		table.insert(list, "Slot" .. i)
	end
	table.insert(list, "Vip")
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

--- Whether restock `slot` has block kind `kind` in a non-VIP slot (the Legendary shout).
function Restock.has(slot: number, kind: string): boolean
	for _, it in Restock.items(slot) do
		if it.block == kind and not it.vip then
			return true
		end
	end
	return false
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
--- restock), "VipOnly", "SoldOut" (their stock used up).
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

--- The restock item a Robux product buys in `slot` (RestockRare, RestockEpic,
--- RestockLegendary): the first slot with that product this player can still buy (`save`,
--- `isVip`), else the first with that product they may see (the VIP slot only for a VIP),
--- else nil.
function Restock.forProduct(slot: number, key: string, save: any?, isVip: boolean?): Item?
	local first: Item? = nil
	for _, it in Restock.items(slot) do
		if it.product == key and (isVip == true or not it.vip) then
			if Restock.check(it, save, slot, isVip == true) == nil then
				return it
			end
			first = first or it
		end
	end
	return first
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

--- Restock `slot` as ShopState shows it: { slot, startsAt, endsAt, items = { { id, block,
--- price, product?, stock, left (this player's), global?, globalLeft?, vip, canBuy,
--- reason? } } }. `globalSold`: a shared stock's copies taken this restock (nil: unknown).
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
			block = it.block,
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

--- Problems in Config.Shop.Restock (empty when it is sound): every odds kind has a Kinds row
--- and is a lucky block kind, the odds add up to ChanceTotal.
function Restock.validate(): { string }
	local problems = {}
	local tables: { [string]: { [string]: number } } = { Odds = R.Odds, VipOdds = R.VipOdds }
	for name, odds in tables do
		local sum = 0
		for kind, weight in odds do
			sum += weight
			if table.find(KIND_ORDER, kind) == nil then
				table.insert(problems, ("%s: %s is not a lucky block kind"):format(name, kind))
			elseif KINDS[kind] == nil then
				table.insert(problems, ("%s: %s has no Kinds row"):format(name, kind))
			end
		end
		if sum ~= R.ChanceTotal then
			table.insert(problems, ("%s add up to %d, not %d"):format(name, sum, R.ChanceTotal))
		end
	end
	table.sort(problems)
	return problems
end

return Restock
