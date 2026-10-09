--!strict
-- The restock shop (Progression/Restock: three rolled lucky block slots and a VIP slot, the
-- lucky-block economy of 2026-10-04), the shared stock transforms (Progression/Counts), timer
-- skip and block prices (Progression/Shop) and their item requests (Progression/Requests).

local H = require("./harness")

local function load()
	return H.require("Progression.Restock"), H.require("Config")
end

local function ids(items: { any }): string
	local out = {}
	for _, it in items do
		table.insert(out, it.id)
	end
	return table.concat(out, " ")
end

return {
	["the restock: two rolled slots and a VIP slot, prices and stock per kind"] = function()
		local Restock, Config = load()
		local R = Config.Shop.Restock
		H.expect(R.SlotSeconds == 600 and R.Slots == 2, "every 10 minutes, two slots")
		-- Economy v5 (plan 6.2): slot 1 always Epic or better; Rare or better everywhere.
		H.expect(R.Kinds.Uncommon == nil and R.Odds.Uncommon == nil, "no Uncommon slot")
		H.expect(R.Kinds.Rare.Price == 49900 and R.Kinds.Rare.Product == "RestockRare", "Rare")
		H.expect(R.Kinds.Rare.Stock == 2, "two Rare blocks a restock")
		H.expect(R.Kinds.Epic.Price == 249000 and R.Kinds.Epic.Product == "RestockEpic", "Epic")
		H.expect(
			R.Kinds.Legendary.Price == 1290000 and R.Kinds.Legendary.Product == "RestockLegendary",
			"Legendary"
		)
		H.expect(
			R.Kinds.Mythic.Price == 4990000
				and R.Kinds.Mythic.Product == "RestockMythic"
				and R.Kinds.Mythic.Stock == 1,
			"Mythic"
		)
		local first = Restock.oddsOf(1)
		H.expect(first.Rare == nil and first.Epic == 7556, "slot 1: Epic 75.56%, never Rare")
		H.expect(first.Legendary == 2111 and first.Mythic == 333, "Legendary 21.11%, Mythic 3.33%")
		H.expect(Restock.oddsOf(2) == R.Odds, "slot 2 rolls Odds")
		H.expect(R.Odds.Rare == 5500 and R.Odds.Epic == 3400, "Rare 55%, Epic 34%")
		H.expect(R.Odds.Legendary == 950 and R.Odds.Mythic == 150, "Legendary 9.5%, Mythic 1.5%")
		H.expect(R.VipOdds.Rare == 4000 and R.VipOdds.Epic == 4000, "the VIP slot")
		H.expect(R.VipOdds.Legendary == 1600 and R.VipOdds.Mythic == 400, "the VIP slot's top")
		H.expect(#Restock.validate() == 0, table.concat(Restock.validate(), "; "))
		H.expect(table.concat(Restock.ids(), " ") == "Slot1 Slot2 Vip", "the item ids")
		-- A roll lands on the kinds in ladder order.
		H.expect(Restock.kindOf(0, R.Odds) == "Rare", "0: Rare")
		H.expect(Restock.kindOf(5499, R.Odds) == "Rare", "the last Rare")
		H.expect(Restock.kindOf(5500, R.Odds) == "Epic", "the first Epic")
		H.expect(Restock.kindOf(8900, R.Odds) == "Legendary", "the first Legendary")
		H.expect(Restock.kindOf(9850, R.Odds) == "Mythic", "the first Mythic")
		H.expect(Restock.kindOf(9999, R.Odds) == "Mythic", "the last roll")
		H.expect(Restock.kindOf(0, first) == "Epic", "slot 1's first roll is an Epic")
		H.expect(Restock.kindOf(0, R.VipOdds) == "Rare", "the VIP slot is Rare or better")
	end,

	["per restock: Legendary or better 32.8%, Mythic 4.8%; with VIP's slot 46.2% and 8.6%"] = function()
		local Restock = load()
		local function pct(x: number): number
			return math.floor(x * 1000 + 0.5) / 10
		end
		H.expect(Restock.chanceOf("Epic") == 1, "every restock has an Epic or better")
		H.expect(
			pct(Restock.chanceOf("Legendary")) == 32.8,
			tostring(Restock.chanceOf("Legendary"))
		)
		H.expect(pct(Restock.chanceOf("Mythic")) == 4.8, tostring(Restock.chanceOf("Mythic")))
		H.expect(pct(Restock.chanceOf("Legendary", true)) == 46.2, "with VIP's slot")
		H.expect(pct(Restock.chanceOf("Mythic", true)) == 8.6, "a Mythic with VIP's slot")
		-- Exactly: 1 - (1 - 0.2444)(1 - 0.11) and 1 - (1 - 0.0333)(1 - 0.015).
		H.near(Restock.chanceOf("Legendary"), 1 - 0.7556 * 0.89, 1e-12, "exact Legendary+")
		H.near(Restock.chanceOf("Mythic"), 1 - 0.9667 * 0.985, 1e-12, "exact Mythic")
	end,

	["100,000 restocks land on each chance; the same slot is the same everywhere"] = function()
		local Restock, Config = load()
		local R = Config.Shop.Restock
		local N = 100000
		local counts = {
			{ Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 },
			{ Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 },
		}
		local vipCounts = { Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
		local base = 2983000 -- about 2026-09 in slots
		for slot = base, base + N - 1 do
			local items = Restock.items(slot)
			H.expect(#items == R.Slots + 1, "two slots and VIP")
			H.expect(items[1].id == "Slot1" and not items[1].vip, "Slot1 first")
			H.expect(items[#items].id == "Vip" and items[#items].vip, "VIP last")
			for i = 1, R.Slots do
				counts[i][items[i].block] += 1
			end
			vipCounts[items[#items].block] += 1
		end
		local function near(got: number, draws: number, chance: number, label: string)
			local p = chance / R.ChanceTotal
			local tolerance = 4 * math.sqrt(draws * p * (1 - p)) + 1
			H.expect(
				math.abs(got - draws * p) <= tolerance,
				("%s: %d, expected %.0f +- %.0f"):format(label, got, draws * p, tolerance)
			)
		end
		for i = 1, R.Slots do
			for _, kind in { "Rare", "Epic", "Legendary", "Mythic" } do
				near(
					counts[i][kind],
					N,
					Restock.oddsOf(i)[kind] or 0,
					("slot %d %s"):format(i, kind)
				)
			end
		end
		for kind, weight in R.VipOdds do
			near(vipCounts[kind], N, weight, "VIP " .. kind)
		end
		-- Pure: the same slot gives the same items, every call.
		for slot = base, base + 50 do
			H.expect(ids(Restock.items(slot)) == ids(Restock.items(slot)), "stable")
			local a, b = Restock.items(slot), Restock.items(slot)
			for i, it in a do
				H.expect(it.block == b[i].block, "the same kinds")
			end
		end
	end,

	["slots follow the clock; stock is per player per restock per slot"] = function()
		local Restock, Config = load()
		local R = Config.Shop.Restock
		H.expect(
			Restock.slotOf(0) == 0 and Restock.slotOf(599) == 0 and Restock.slotOf(600) == 1,
			""
		)
		local startsAt, endsAt = Restock.window(5)
		H.expect(startsAt == 3000 and endsAt == 3600, "the window")
		-- A restock whose second slot is a Rare block (2 per player; slot 1 is never Rare).
		local slot = 4000000
		while Restock.find(slot, "Slot2").block ~= "Rare" do
			slot += 1
		end
		local save = { Slot = 0, Bought = {} }
		local first = Restock.find(slot, "Slot2")
		H.expect(first ~= nil and first.price == R.Kinds.Rare.Price, "Slot2")
		for i = 1, 2 do
			H.expect(Restock.check(first, save, slot, false) == nil, "buy " .. i)
			Restock.record(save, slot, "Slot2")
		end
		H.expect(Restock.check(first, save, slot, false) == "SoldOut", "2 per player")
		H.expect(Restock.bought(save, slot + 1, "Slot2") == 0, "a new restock starts over")
		H.expect(Restock.check(first, save, slot + 1, false) == nil, "on sale again")
		Restock.record(save, slot - 1, "Slot2")
		H.expect(save.Slot == slot and save.Bought.Slot2 == 2, "an older buy changes nothing")
		Restock.record(save, slot + 1, "Slot2")
		H.expect(save.Slot == slot + 1 and save.Bought.Slot2 == 1, "the record starts over")
		local vip = Restock.find(slot, "Vip")
		H.expect(Restock.check(vip, save, slot, false) == "VipOnly", "VIP only")
		H.expect(Restock.check(vip, save, slot, true) == nil, "a VIP buys it")
		H.expect(Restock.check(nil, save, slot, true) == "NotSold", "not in this restock")
		H.expect(Restock.find(slot, "Nope") == nil and Restock.find(slot, "Rare") == nil, "")
		H.expect(Restock.stockKey(slot) == "Legendary:" .. slot, "the shared stock key")
	end,

	["a Legendary or Mythic block in a shared slot is announced, the rarest first"] = function()
		local Restock = load()
		local slot = 0
		while not Restock.has(slot, "Mythic") do
			slot += 1
		end
		H.expect(Restock.announced(slot) == "Mythic", "a Mythic block is announced")
		local legendary = 0
		while not (Restock.has(legendary, "Legendary") and not Restock.has(legendary, "Mythic")) do
			legendary += 1
		end
		H.expect(Restock.announced(legendary) == "Legendary", "a Legendary block too")
		local plain = 0
		while Restock.has(plain, "Legendary") or Restock.has(plain, "Mythic") do
			plain += 1
		end
		H.expect(Restock.announced(plain) == nil, "Rare and Epic restocks are not")
	end,

	["the view: this player's stock left; a Robux product finds a slot still in stock"] = function()
		local Restock = load()
		-- A restock with a Legendary in a slot and a Rare in another.
		local slot = 0
		while not (Restock.has(slot, "Legendary") and Restock.has(slot, "Rare")) do
			slot += 1
		end
		local legendaryId, rareIds = "", {}
		for _, it in Restock.items(slot) do
			if it.vip then
				continue
			elseif it.block == "Legendary" then
				legendaryId = it.id
			elseif it.block == "Rare" then
				table.insert(rareIds, it.id)
			end
		end
		local view = Restock.view(slot, { Slot = slot, Bought = { [rareIds[1]] = 2 } }, false, 24)
		H.expect(view.slot == slot and view.endsAt == (slot + 1) * 600, "the restock")
		local byId: { [string]: any } = {}
		for _, it in view.items do
			byId[it.id] = it
		end
		H.expect(byId[rareIds[1]].left == 0 and not byId[rareIds[1]].canBuy, "the Rare bought")
		H.expect(byId[rareIds[1]].reason == "SoldOut", "sold out for this player")
		H.expect(byId[legendaryId].global == nil and byId[legendaryId].globalLeft == nil, "")
		H.expect(
			byId[legendaryId].canBuy and byId[legendaryId].product == "RestockLegendary",
			"the Legendary, with its Robux product"
		)
		H.expect(byId[legendaryId].block == "Legendary", "the block kind is in the view")
		H.expect(not byId.Vip.canBuy and byId.Vip.reason == "VipOnly", "VIP only")
		-- The Robux product RestockRare buys the first Rare slot still in this player's stock.
		local bought = { Slot = slot, Bought = { [rareIds[1]] = 2 } }
		local item = Restock.forProduct(slot, "RestockRare", bought, false)
		if #rareIds > 1 then
			H.expect(item ~= nil and item.id == rareIds[2], "the next Rare slot")
		else
			H.expect(item ~= nil and item.id == rareIds[1], "the only Rare slot, sold out")
		end
		H.expect(Restock.forProduct(slot, "Nope") == nil, "no such product")
	end,

	["shared stock: 25 players at most, a retry keeps its unit, a cancel gives it back"] = function()
		local Counts = H.require("Progression.Counts")
		local stored: any = nil
		for user = 1, 25 do
			local value, held = Counts.reserve(stored, user, 25)
			H.expect(held and value ~= nil, "unit " .. user)
			stored = value
		end
		H.expect(Counts.stockTaken(stored) == 25, "25 taken")
		local value, held, why = Counts.reserve(stored, 26, 25)
		H.expect(value == nil and not held and why == "SoldOut", "the 26th")
		value, held = Counts.reserve(stored, 7, 25)
		H.expect(value == nil and held, "a retry keeps its unit, writes nothing")
		local released = Counts.release(stored, 7)
		H.expect(released ~= nil and Counts.stockTaken(released) == 24, "given back")
		value, held = Counts.reserve(released, 26, 25)
		H.expect(held and Counts.stockTaken(value) == 25, "someone else takes it")
		H.expect(Counts.release(stored, 99) == nil, "nothing to give back")
		H.expect(Counts.stockTaken(nil) == 0 and Counts.stockTaken({ by = { x = 5 } }) == 0, "")
	end,

	["the Mystery deal's money prices; the case timer skips are gone"] = function()
		local Shop = H.require("Progression.Shop")
		H.expect(Shop.skipPrice == nil and Shop.skipProduct == nil, "no case timer skips")
		H.expect(Shop.mysteryPrice(1) == 4900 and Shop.mysteryPrice(10) == 44100, "Mystery")
		H.expect(Shop.mysteryPrice(2) == nil and Shop.mysteryPrice("1") == nil, "other counts")
	end,

	["the money requests: BuyBlocks (and the old BuyMystery), BuyRestock"] = function()
		local Requests = H.require("Progression.Requests")
		local r = Requests.parse("BuyMystery", nil)
		H.expect(r ~= nil and r.action == "BuyBlocks" and r.dealId == "Mystery", "the old name")
		H.expect(r.count == 1, "one by default")
		r = Requests.parse("BuyMystery", 10)
		H.expect(r ~= nil and r.count == 10, "ten")
		for _, bad in { 2, 0, -1, 1.5, "10", 0 / 0 } do
			local _, why = Requests.parse("BuyMystery", bad)
			H.expect(why == "BadRequest", "count " .. tostring(bad))
		end
		r = Requests.parse("BuyBlocks", "GrandOpening", 3)
		H.expect(r ~= nil and r.dealId == "GrandOpening" and r.count == 3, "three Grand Opening")
		r = Requests.parse("BuyBlocks", "Mystery", nil)
		H.expect(r ~= nil and r.count == 1, "one Mystery by default")
		for _, args in { { "GrandOpening", 2 }, { "Nope", 1 }, { 3, 1 }, { "Mystery", 5 } } do
			local _, why = Requests.parse("BuyBlocks", args[1], args[2])
			H.expect(
				why == "BadRequest",
				"blocks " .. tostring(args[1]) .. " " .. tostring(args[2])
			)
		end
		for _, id in { "Slot1", "Slot2", "Vip" } do
			local req = Requests.parse("BuyRestock", id)
			H.expect(req ~= nil and req.itemId == id, id)
		end
		for _, bad in { "Uncommon", "Slot3", "Slot4", "", 3, nil :: any } do
			local _, why = Requests.parse("BuyRestock", bad)
			H.expect(why == "BadRequest", "item " .. tostring(bad))
		end
		H.expect(
			select(2, Requests.parse("SkipTimer", "Rare", 1800000000)) == "BadRequest",
			"no skips"
		)
		for _, reason in { "VipOnly", "Full", "Restricted" } do
			H.expect(table.find(Requests.Reasons, reason) ~= nil, reason)
		end
		for _, reason in { "NoTimer", "NotReady", "NoCases", "NoFastOpen", "NotSold" } do
			H.expect(table.find(Requests.Reasons, reason) == nil, reason .. " is gone")
		end
	end,
}
