--!strict
-- The Halloween Candy packs (Config.Products Candy500 / Candy2000; Config.Halloween.Packs): the
-- rows, the receipt check (sold only while Packs is on and the event is Live, else the money
-- fallback), the Buy check, the once-only receipt and the track steps a pack reaches. The fake
-- server applies a grant the way src/server/PlayerData.luau's applyPurchase does: the receipt
-- id, the Candy into Halloween.Bought (flat) and the due track steps in one change.

local H = require("./harness")

local Config = H.require("Config")
local Shop = H.require("Progression.Shop")
local ShopView = H.require("Progression.ShopView")
local Ledger = H.require("Halloween.Ledger")
local Track = H.require("Halloween.Track")
local SaveSchema = H.require("Progression.SaveSchema")

local C = Config.Halloween
local START = C.StartsAt
local END = C.EndsAt
local LIVE = START + 15 * 60 -- 19:15, between Rushes
local RUSH = START + 3600 + 30 -- 20:00:30, a Candy Rush (2x for match Candy)

-- Runs `fn` with Config.Halloween.Packs.Enabled (and the event's own switch) set, then puts
-- them back even if it fails.
local function withPacks(on: boolean, fn: () -> (), eventOn: boolean?)
	local event: any = C
	local packs: any = C.Packs
	local was, wasEvent = packs.Enabled, event.Enabled
	packs.Enabled = on
	if eventOn ~= nil then
		event.Enabled = eventOn
	end
	local ok, err = pcall(fn)
	packs.Enabled = was
	event.Enabled = wasEvent
	if not ok then
		error(err, 0)
	end
end

local function newShop(): any
	return {
		FirstJoin = START - 30 * 86400,
		VipOffer = false,
		VipCueGiven = false,
		StarterBought = true,
		FirstPackBought = false,
		BoostEnds = 0,
		Purchases = {},
		Limited = {},
	}
end

-- A ShopView context at unix time `now` (`hwNow`: the Halloween clock, nil = now).
local function ctxAt(now: number, hwNow: number?): any
	return {
		now = now,
		hwNow = hwNow,
		shop = newShop(),
		vipPass = false,
		restricted = false,
		partyEndsAt = 0,
		sold = {},
		prices = {},
	}
end

-- A fake server for Shop.processReceipt: one player whose receipts land at unix time `now`.
-- `grant` mirrors PlayerData.applyPurchase for a Candy pack: the receipt id, the money (a
-- closed pack's fallback), the Candy into Bought and every due track step, together.
local function fakeServer(now: number): any
	local server: any = { grants = 0, saves = 0, keys = {} }
	server.player = {
		UserId = 7,
		save = { Money = 0, Shop = newShop(), Halloween = SaveSchema.freshHalloween() },
	}
	server.keys[Config.Products.List.Candy500.Id] = "Candy500"
	server.keys[Config.Products.List.Candy2000.Id] = "Candy2000"
	server.deps = {
		keyForId = function(id: number): string?
			return server.keys[id]
		end,
		findPlayer = function(userId: number): any?
			return if userId == server.player.UserId then server.player else nil
		end,
		isLoaded = function(_player: any): boolean
			return true
		end,
		hasPurchase = function(player: any, purchaseId: string): boolean
			return Shop.hasPurchase(player.save.Shop, purchaseId)
		end,
		grant = function(player: any, key: string, purchaseId: string): boolean
			local save = player.save
			local grant = Shop.grantFor(key, save.Shop, now, false)
			if grant == nil then
				return false
			end
			Shop.recordPurchase(save.Shop, purchaseId)
			save.Money += grant.money
			if grant.candy ~= nil then
				local hw = save.Halloween
				Ledger.addCandy(hw, grant.candy, "Bought")
				for _, index in Track.due(Ledger.total(hw), hw.Given) do
					hw.Given[Track.key(index)] = true
				end
			end
			Shop.markGrant(save.Shop, grant)
			server.grants += 1
			return true
		end,
		save = function(_player: any): boolean
			server.saves += 1
			return true
		end,
	}
	return server
end

local function receipt(productId: number, purchaseId: string): any
	return { PlayerId = 7, ProductId = productId, PurchaseId = purchaseId }
end

return {
	["the two Candy packs: made, priced, Candy, the menu's keys, not money packs"] = function()
		local L = Config.Products.List :: any
		local want = { Candy500 = { 49, 500 }, Candy2000 = { 149, 2000 } }
		for key, pair in want do
			local row = L[key]
			H.expect(row ~= nil and row.Kind == "Product" and row.Id > 0, key .. " is made")
			H.expect(row.Robux == pair[1] and row.Candy == pair[2], key .. " price and Candy")
			H.expect(row.Random ~= true and row.Money == nil, key .. ": not random, no money")
			H.expect(table.find(Config.Products.PackOrder, key) == nil, key .. " not a money pack")
			H.expect(table.find(C.Packs.Keys, key) ~= nil, key .. " in Packs.Keys")
		end
		H.expect(#C.Packs.Keys == 2, "two packs")
		H.expect(Shop.GrantFields.candy == true, "PlayerData applies grant.candy")
		H.expect(type(C.Packs.Enabled) == "boolean", "Packs.Enabled is a switch")
	end,

	["receiptCheck: a pack is Closed outside Live and while Packs is off"] = function()
		local shop = newShop()
		withPacks(true, function()
			H.expect(Shop.receiptCheck("Candy500", shop, START - 1, false) == "Closed", "before")
			H.expect(Shop.receiptCheck("Candy500", shop, START, false) == nil, "at the start")
			H.expect(Shop.receiptCheck("Candy2000", shop, LIVE, false) == nil, "Live")
			H.expect(Shop.receiptCheck("Candy2000", shop, RUSH, false) == nil, "a Rush")
			H.expect(Shop.receiptCheck("Candy500", shop, END - 1, false) == nil, "the last second")
			-- No grace past EndsAt: Candy stops there and the end converts it.
			H.expect(Shop.receiptCheck("Candy500", shop, END, false) == "Closed", "at the end")
			H.expect(Shop.receiptCheck("Candy2000", shop, END + 86400, false) == "Closed", "after")
			H.expect(Shop.receiptCheck("Pack1", shop, END, false) == nil, "a money pack: open")
		end)
		withPacks(false, function()
			H.expect(Shop.receiptCheck("Candy500", shop, LIVE, false) == "Closed", "Packs off")
			H.expect(not Shop.packsOpen(LIVE), "not sold")
		end)
		withPacks(true, function()
			H.expect(Shop.receiptCheck("Candy500", shop, LIVE, false) == "Closed", "event off")
		end, false)
	end,

	["grantFor: Candy flat while open; the money fallback when closed"] = function()
		withPacks(true, function()
			for _, at in { LIVE, RUSH, C.Double.From + 3600 } do
				local grant, notFor = Shop.grantFor("Candy500", newShop(), at, false)
				H.expect(notFor == nil and grant ~= nil, "open")
				H.expect(grant.candy == 500 and grant.money == 0, "500 Candy, flat, no money")
			end
			local big = Shop.grantFor("Candy2000", newShop(), LIVE, false, true)
			H.expect(big ~= nil and big.candy == 2000, "2,000 (sold where random is restricted)")
			local late, why = Shop.grantFor("Candy2000", newShop(), END, false)
			H.expect(why == "Closed" and late ~= nil and late.candy == nil, "after: no Candy")
			H.expect(late.money == Shop.fallbackMoney("Candy2000"), "the money fallback")
		end)
		withPacks(false, function()
			local grant, why = Shop.grantFor("Candy500", newShop(), LIVE, false)
			H.expect(why == "Closed" and grant ~= nil and grant.candy == nil, "off: no Candy")
			H.expect(grant.money == Shop.fallbackMoney("Candy500"), "paid as money")
		end)
		-- The fallback is the first money pack's rate: 49 R$ and 149 R$ at $400 a Robux.
		local rate = Config.Products.List.Pack1.Money // Config.Products.List.Pack1.Robux
		H.expect(Shop.fallbackMoney("Candy500") == 49 * rate, "Candy500's fallback")
		H.expect(Shop.fallbackMoney("Candy2000") == 149 * rate, "Candy2000's fallback")
	end,

	["Buy check: a pack is Closed outside Live, sold inside, on the Halloween clock"] = function()
		withPacks(true, function()
			H.expect(ShopView.check("Candy500", ctxAt(LIVE)) == nil, "Live: prompts")
			H.expect(ShopView.check("Candy2000", ctxAt(START - 60)) == "Closed", "before")
			H.expect(ShopView.check("Candy2000", ctxAt(END)) == "Closed", "after")
			-- Studio's /hw test time: the real clock before the event, the Halloween clock Live.
			H.expect(ShopView.check("Candy500", ctxAt(START - 3600, LIVE)) == nil, "test time")
			H.expect(ShopView.check("Candy500", ctxAt(LIVE, END + 5)) == "Closed", "test end")
			local view = ShopView.build(ctxAt(LIVE))
			H.expect(view.products.Candy500.canBuy and view.products.Candy500.robux == 49, "view")
			H.expect(view.products.Candy2000.money == 0, "no money shown for Candy")
		end)
		withPacks(false, function()
			H.expect(ShopView.check("Candy500", ctxAt(LIVE)) == "Closed", "Packs off")
		end)
	end,

	["a replayed pack receipt adds its Candy once"] = function()
		withPacks(true, function()
			local server = fakeServer(LIVE)
			local hw = server.player.save.Halloween
			local id = Config.Products.List.Candy500.Id
			H.expect(Shop.processReceipt(server.deps, receipt(id, "id1")) == "Granted", "first")
			H.expect(hw.Bought == 500 and hw.Earned == 0, "500 bought")
			H.expect(Shop.processReceipt(server.deps, receipt(id, "id1")) == "Granted", "replay")
			H.expect(Shop.processReceipt(server.deps, receipt(id, "id1")) == "Granted", "again")
			H.expect(hw.Bought == 500 and server.grants == 1, "the same id: Candy once")
			H.expect(server.saves == 3, "each try saves before it is acknowledged")
			H.expect(server.player.save.Money == 0, "no money for a pack")
			local big = Config.Products.List.Candy2000.Id
			H.expect(Shop.processReceipt(server.deps, receipt(big, "id2")) == "Granted", "another")
			H.expect(hw.Bought == 2500 and server.grants == 2, "a new id: 2,000 more")
		end)
	end,

	["a pack receipt outside Live pays money, no Candy"] = function()
		withPacks(true, function()
			local server = fakeServer(END + 60)
			local id = Config.Products.List.Candy2000.Id
			H.expect(Shop.processReceipt(server.deps, receipt(id, "late")) == "Granted", "paid")
			local save = server.player.save
			H.expect(save.Halloween.Bought == 0, "no Candy after the end")
			H.expect(save.Money == Shop.fallbackMoney("Candy2000"), "the money fallback")
			H.expect(Shop.processReceipt(server.deps, receipt(id, "late")) == "Granted", "replay")
			H.expect(save.Money == Shop.fallbackMoney("Candy2000"), "paid once")
		end)
	end,

	["a pack crossing track steps marks them given, flat in a Rush"] = function()
		withPacks(true, function()
			local server = fakeServer(RUSH)
			local hw = server.player.save.Halloween
			hw.Earned = 120
			hw.Given["1"] = true -- the 50 step, earned in play
			local id = Config.Products.List.Candy500.Id
			H.expect(Shop.processReceipt(server.deps, receipt(id, "r1")) == "Granted", "bought")
			H.expect(hw.Bought == 500 and hw.Earned == 120, "flat: 500 into Bought, not doubled")
			H.expect(Ledger.total(hw) == 620, "620 in all")
			for _, index in { 1, 2, 3, 4 } do
				H.expect(hw.Given[Track.key(index)] == true, "step " .. index .. " given")
			end
			H.expect(hw.Given["5"] == nil, "1,000 not reached")
			-- The 2,000 pack carries the rest of the way past 2,000 (the Black Cat Cue).
			local big = Config.Products.List.Candy2000.Id
			H.expect(Shop.processReceipt(server.deps, receipt(big, "r2")) == "Granted", "bought")
			H.expect(Ledger.total(hw) == 2620, "2,620")
			for index = 1, 7 do
				H.expect(hw.Given[Track.key(index)] == true, "step " .. index .. " given")
			end
			H.expect(hw.Given["8"] == nil, "3,000 not reached")
			H.expect(next(hw.Q) == nil, "no quest progress from a pack")
		end)
	end,
}
