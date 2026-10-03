--!strict
-- The restock shop (Progression/Restock), the Legendary's shared stock transforms
-- (Progression/Counts), timer skip and Mystery Case prices (Progression/Shop) and their item
-- requests (Progression/Requests), against the approved economy plan (2026-10-02, section 4).

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
	["the plan's restock: prices, stock and chances"] = function()
		local _, Config = load()
		local R = Config.Shop.Restock
		H.expect(R.SlotSeconds == 600, "every 10 minutes")
		H.expect(R.Uncommon.Price == 14900 and R.Uncommon.Stock == 3, "Uncommon")
		H.expect(R.Rare.Price == 34900 and R.Rare.Stock == 2 and R.RareChance == 6000, "Rare")
		H.expect(R.Epic.Price == 349000 and R.Epic.Stock == 1 and R.EpicChance == 400, "Epic")
		H.expect(
			R.Legendary.Price == 3490000 and R.Legendary.GlobalStock == nil,
			"Legendary: no shared limit"
		)
		H.expect(R.LegendaryChance == 15, "0.15%")
		H.expect(R.Mystery.Mystery == 3 and R.Mystery.Price == 14700, "3 Mystery Cases")
		H.expect(R.Vip.Case == "Rare" and R.Vip.Price == 34900 and R.Vip.Stock == 1, "VIP")
		H.expect(R.Epic.Product == "RestockEpic" and R.Legendary.Product == "RestockLegendary", "")
	end,

	["100,000 restocks land on each chance; the same slot is the same everywhere"] = function()
		local Restock, Config = load()
		local R = Config.Shop.Restock
		local N = 100000
		local counts = { Rare = 0, Epic = 0, Legendary = 0, Mystery = 0 }
		local base = 2983000 -- about 2026-09 in slots
		for slot = base, base + N - 1 do
			local items = Restock.items(slot)
			H.expect(items[1].id == "Uncommon", "Uncommon first")
			H.expect(items[#items].id == "Vip" and items[#items].vip, "VIP last")
			for _, it in items do
				if counts[it.id] ~= nil then
					counts[it.id] += 1
				end
			end
		end
		local function near(id: string, chance: number)
			local p = chance / R.ChanceTotal
			local tolerance = 4 * math.sqrt(N * p * (1 - p)) + 1
			H.expect(
				math.abs(counts[id] - N * p) <= tolerance,
				("%s: %d, expected %.0f +- %.0f"):format(id, counts[id], N * p, tolerance)
			)
		end
		near("Rare", R.RareChance)
		near("Epic", R.EpicChance)
		near("Legendary", R.LegendaryChance)
		near("Mystery", R.ChanceTotal - R.EpicChance - R.LegendaryChance)
		H.expect(counts.Epic + counts.Legendary + counts.Mystery == N, "one lucky item each")
		-- Pure: the same slot gives the same items, every call.
		for slot = base, base + 50 do
			H.expect(ids(Restock.items(slot)) == ids(Restock.items(slot)), "stable")
		end
	end,

	["slots follow the clock; stock is per player per restock"] = function()
		local Restock = load()
		H.expect(
			Restock.slotOf(0) == 0 and Restock.slotOf(599) == 0 and Restock.slotOf(600) == 1,
			""
		)
		local startsAt, endsAt = Restock.window(5)
		H.expect(startsAt == 3000 and endsAt == 3600, "the window")
		local slot = 4000000
		local save = { Slot = 0, Bought = {} }
		local uncommon = Restock.find(slot, "Uncommon")
		H.expect(uncommon ~= nil and uncommon.case == "Uncommon", "always there")
		for i = 1, 3 do
			H.expect(Restock.check(uncommon, save, slot, false) == nil, "buy " .. i)
			Restock.record(save, slot, "Uncommon")
		end
		H.expect(Restock.check(uncommon, save, slot, false) == "SoldOut", "3 per player")
		H.expect(Restock.bought(save, slot + 1, "Uncommon") == 0, "a new restock starts over")
		H.expect(Restock.check(uncommon, save, slot + 1, false) == nil, "on sale again")
		Restock.record(save, slot - 1, "Uncommon")
		H.expect(save.Slot == slot and save.Bought.Uncommon == 3, "an older buy changes nothing")
		Restock.record(save, slot + 1, "Uncommon")
		H.expect(save.Slot == slot + 1 and save.Bought.Uncommon == 1, "the record starts over")
		local vip = Restock.find(slot, "Vip")
		H.expect(Restock.check(vip, save, slot, false) == "VipOnly", "VIP only")
		H.expect(Restock.check(vip, save, slot, true) == nil, "a VIP buys it")
		H.expect(Restock.check(nil, save, slot, true) == "NotSold", "not in this restock")
		H.expect(Restock.find(slot, "Nope") == nil, "unknown item")
		H.expect(Restock.stockKey(slot) == "Legendary:4000000", "the shared stock key")
	end,

	["the view: this player's stock left; the Legendary has no shared limit"] = function()
		local Restock = load()
		local slot = 0
		while Restock.find(slot, "Legendary") == nil do
			slot += 1
		end
		local view = Restock.view(slot, { Slot = slot, Bought = { Uncommon = 2 } }, false, 24)
		H.expect(view.slot == slot and view.endsAt == (slot + 1) * 600, "the restock")
		local byId: { [string]: any } = {}
		for _, it in view.items do
			byId[it.id] = it
		end
		H.expect(byId.Uncommon.left == 1 and byId.Uncommon.canBuy, "one left")
		H.expect(
			byId.Legendary.global == nil and byId.Legendary.globalLeft == nil,
			"no shared stock"
		)
		H.expect(byId.Legendary.canBuy and byId.Legendary.product == "RestockLegendary", "")
		H.expect(not byId.Vip.canBuy and byId.Vip.reason == "VipOnly", "VIP only")
		-- However many were sold everywhere, anyone who can afford it still buys it.
		local many = Restock.view(slot, nil, true, 500)
		for _, it in many.items do
			if it.id == "Legendary" then
				H.expect(it.canBuy and it.reason == nil, "never sold out")
			end
		end
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

	["skips: $25 a minute left, at least $250; the cheapest Robux skip that covers it"] = function()
		local Shop = H.require("Progression.Shop")
		H.expect(Shop.skipPrice(0) == 0 and Shop.skipPrice(-5) == 0, "a done timer")
		H.expect(Shop.skipPrice(30) == 250 and Shop.skipPrice(600) == 250, "the minimum")
		H.expect(Shop.skipPrice(601) == 275, "a part minute counts whole")
		H.expect(Shop.skipPrice(3600) == 1500, "$1,500 an hour")
		H.expect(Shop.skipPrice(48 * 3600) == 72000, "48 h")
		H.expect(Shop.skipProduct(3600) == "Skip1h" and Shop.skipProduct(3601) == "Skip6h", "")
		H.expect(
			Shop.skipProduct(6 * 3600) == "Skip6h" and Shop.skipProduct(86400) == "Skip24h",
			""
		)
		H.expect(Shop.skipProduct(86401) == "Skip48h" and Shop.skipProduct(172801) == nil, "")
		H.expect(Shop.skipProduct(0) == nil, "nothing to skip")
		H.expect(Shop.mysteryPrice(1) == 4900 and Shop.mysteryPrice(10) == 44100, "Mystery")
		H.expect(Shop.mysteryPrice(2) == nil and Shop.mysteryPrice("1") == nil, "other counts")
	end,

	["the money requests: BuyMystery, BuyRestock, SkipTimer"] = function()
		local Requests = H.require("Progression.Requests")
		local r = Requests.parse("BuyMystery", nil)
		H.expect(r ~= nil and r.count == 1, "one by default")
		r = Requests.parse("BuyMystery", 10)
		H.expect(r ~= nil and r.count == 10, "ten")
		for _, bad in { 2, 0, -1, 1.5, "10", 0 / 0 } do
			local _, why = Requests.parse("BuyMystery", bad)
			H.expect(why == "BadRequest", "count " .. tostring(bad))
		end
		for _, id in { "Uncommon", "Rare", "Epic", "Legendary", "Mystery", "Vip" } do
			local req = Requests.parse("BuyRestock", id)
			H.expect(req ~= nil and req.itemId == id, id)
		end
		for _, bad in { "Mythic", "", 3, nil :: any } do
			local _, why = Requests.parse("BuyRestock", bad)
			H.expect(why == "BadRequest", "item " .. tostring(bad))
		end
		r = Requests.parse("SkipTimer", "Rare", 1800000000)
		H.expect(r ~= nil and r.caseId == "Rare" and r.at == 1800000000, "a timer")
		for _, args in { { "Nope", 1 }, { "Rare", -1 }, { "Rare", 1.5 }, { "Rare", "1" } } do
			local _, why = Requests.parse("SkipTimer", args[1], args[2])
			H.expect(why == "BadRequest", "skip " .. tostring(args[1]) .. " " .. tostring(args[2]))
		end
		for _, reason in { "VipOnly", "NoTimer", "NotReady" } do
			H.expect(table.find(Requests.Reasons, reason) ~= nil, reason)
		end
	end,
}
