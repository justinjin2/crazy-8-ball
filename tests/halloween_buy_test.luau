--!strict
-- The Halloween cue shop (Config.Halloween.Cues; designer, 2026-10-29): buying an event cue with
-- Candy (Halloween/Ledger.buyCheck and buyCue: the balance, owned, Live, the switch) and the
-- Halloween funnel's cue steps; buying one for Robux (Config.Products HwPitchfork, HwBroom,
-- HwSword: Shop.grantFor's grant.cue, the receipt window and the owned fallback, ShopView's
-- Owned and Closed, gifts). `buy` applies a Candy buy the way src/server/PlayerData.luau's
-- hwBuyCue does (Ledger.buyCue and the cue given in one change); the fake server applies a
-- receipt the way src/server/Store.luau's grantProduct and grantGift and PlayerData's
-- applyPurchase do.

local H = require("./harness")

local Config = H.require("Config")
local Ledger = H.require("Halloween.Ledger")
local SaveSchema = H.require("Progression.SaveSchema")
local Inventory = H.require("Progression.Inventory")
local Catalog = H.require("Progression.Catalog")
local Shop = H.require("Progression.Shop")
local ShopView = H.require("Progression.ShopView")

local C = Config.Halloween
local START = C.StartsAt
local END = C.EndsAt
local LIVE = START + 15 * 60

-- Runs `fn` with Config.Halloween.Cues.Enabled set, then puts it back even if it fails.
local function withCues(on: boolean, fn: () -> ())
	local cues: any = C.Cues
	local was = cues.Enabled
	cues.Enabled = on
	local ok, err = pcall(fn)
	cues.Enabled = was
	if not ok then
		error(err, 0)
	end
end

-- A player's save with `candy` earned Candy.
local function saveWith(candy: number): any
	local save = SaveSchema.template()
	save.Halloween.Earned = candy
	return save
end

-- PlayerData.hwBuyCue's one change, on a plain save: (ok, reason).
local function buy(save: any, cueId: string, now: number): (boolean, string?)
	local owned = Inventory.count(save, cueId) > 0
	local ok, why = Ledger.buyCue(save.Halloween, cueId, now, owned, Catalog.ready(cueId))
	if ok then
		local given = Inventory.addCue(save, cueId, 1)
		H.expect(given, cueId .. " given")
	end
	return ok, why
end

local function row(cue: string): any
	return Ledger.cueRow(cue)
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

-- A fake server for Shop.processReceipt with two players (7 and 8) whose receipts land at
-- unix time `now`. Its grant mirrors Store.grantProduct (Shop.grantFor with the one who gets
-- it: their own cues) and PlayerData.applyPurchase (the id recorded, the money, the cue given
-- once) in one change; a pending gift (`gifts[buyer]`) lands with the receiver, and the id in
-- the giver's save, as Store.grantGift does.
local function fakeServer(now: number): any
	local server: any = { grants = 0, players = {}, gifts = {}, keys = {} }
	for _, userId in { 7, 8 } do
		local save = SaveSchema.template()
		save.Shop = newShop()
		server.players[userId] = { UserId = userId, save = save }
	end
	for key, r in Config.Products.List :: any do
		if r.Cue ~= nil then
			server.keys[r.Id] = key
		end
	end
	local function apply(save: any, key: string, purchaseId: string): boolean
		local grant = Shop.grantFor(key, save.Shop, now, false, false, function(id: string)
			return Inventory.owns(save, id)
		end)
		if grant == nil then
			return false
		end
		Shop.recordPurchase(save.Shop, purchaseId)
		save.Money += grant.money
		if grant.cue ~= nil and Inventory.count(save, grant.cue) == 0 then
			Inventory.addCue(save, grant.cue, 1, true)
		end
		Shop.markGrant(save.Shop, grant)
		server.grants += 1
		return true
	end
	server.deps = {
		keyForId = function(id: number): string?
			return server.keys[id]
		end,
		findPlayer = function(userId: number): any?
			return server.players[userId]
		end,
		isLoaded = function(_player: any): boolean
			return true
		end,
		hasPurchase = function(player: any, purchaseId: string): boolean
			return Shop.hasPurchase(player.save.Shop, purchaseId)
		end,
		grant = function(player: any, key: string, purchaseId: string): boolean
			local gift = server.gifts[player.UserId]
			server.gifts[player.UserId] = nil
			if gift ~= nil and gift.key == key then
				local receiver = server.players[gift.to]
				if not apply(receiver.save, key, purchaseId) then
					return false
				end
				Shop.recordPurchase(player.save.Shop, purchaseId)
				return true
			end
			return apply(player.save, key, purchaseId)
		end,
		save = function(_player: any): boolean
			return true
		end,
	}
	return server
end

local function receipt(playerId: number, productId: number, purchaseId: string): any
	return { PlayerId = playerId, ProductId = productId, PurchaseId = purchaseId }
end

return {
	["the cue shop: three cues with a Candy price and a Robux product that sells that cue"] = function()
		H.expect(type(C.Cues.Enabled) == "boolean", "Cues.Enabled is a switch")
		H.expect(#C.Cues.List == 3, "three cues")
		local want = { PitchforkCue = 300, WitchBroomCue = 2500, HalloweenSwordCue = 7500 }
		for _, r in C.Cues.List do
			H.expect(want[r.Cue] == r.Candy, r.Cue .. "'s price")
			local product = (Config.Products.List :: any)[r.Product]
			H.expect(product ~= nil and product.Kind == "Product", r.Product .. " is a product")
			H.expect(product.Cue == r.Cue and product.Id > 0, r.Product .. " sells " .. r.Cue)
			local cue = Catalog.get(r.Cue)
			H.expect(cue ~= nil and cue.Group == "Exclusive", r.Cue .. " is Exclusive")
			H.expect(Ledger.cueRow(r.Cue) == r, "cueRow finds " .. r.Cue)
		end
		H.expect(Ledger.cueRow(C.KingDrop.Cue) == nil, "the King's drop is not sold")
		H.expect(Ledger.cueRow("SpiderCue") == nil and Ledger.cueRow(nil) == nil, "nor others")
	end,

	["buying with Candy: the price comes off the balance and the cue is given, once"] = function()
		withCues(true, function()
			local save = saveWith(3000)
			H.expect(Catalog.ready("WitchBroomCue"), "the Broom is ready")
			local ok, why = buy(save, "WitchBroomCue", LIVE)
			H.expect(ok and why == nil, "bought")
			local hw = save.Halloween
			H.expect(hw.Spent == 2500 and Ledger.balance(hw) == 500, "2,500 spent, 500 left")
			H.expect(Inventory.count(save, "WitchBroomCue") == 1, "owned")
			H.expect(save.Index.Seen.WitchBroomCue == true, "in the Index")
			H.expect(hw.Earned == 3000, "Earned stays a lifetime total")
			-- Again: owned, nothing more spent.
			ok, why = buy(save, "WitchBroomCue", LIVE)
			H.expect(not ok and why == "Owned" and hw.Spent == 2500, "a second time: Owned")
			-- The Sword at 7,500 with 500 left: too poor, nothing spent.
			ok, why = buy(save, "HalloweenSwordCue", LIVE)
			H.expect(not ok and why == "Poor" and hw.Spent == 2500, "Poor")
			H.expect(Inventory.count(save, "HalloweenSwordCue") == 0, "not given")
			-- The Pitchfork at 300: yes.
			ok = buy(save, "PitchforkCue", LIVE)
			H.expect(ok and Ledger.balance(hw) == 200, "the Pitchfork too, 200 left")
			local fixed, fixes = SaveSchema.validate(save)
			H.expect(#fixes == 0, "the save stays clean: " .. table.concat(fixes, "; "))
			H.expect(fixed.Halloween.Spent == 2800, "Spent kept")
		end)
	end,

	["buying with Candy is Closed outside Live, while switched off, or for another cue"] = function()
		withCues(true, function()
			local hw = saveWith(10000).Halloween
			local price = row("PitchforkCue").Candy
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == nil, "Live: yes")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", START, false, true) == nil, "the start")
			H.expect(
				Ledger.buyCheck(hw, "PitchforkCue", START - 1, false, true) == "Closed",
				"before"
			)
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", END, false, true) == "Closed", "the end")
			H.expect(Ledger.buyCheck(hw, "JackOLanternCue", LIVE, false, true) == "Closed", "Jack")
			H.expect(Ledger.buyCheck(hw, 7, LIVE, false, true) == "Closed", "not a cue id")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, false) == "Closed", "unready")
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, true, true) == "Owned", "owned")
			local ok, why = Ledger.buyCue(hw, "PitchforkCue", END + 5, false, true)
			H.expect(not ok and why == "Closed" and hw.Spent == 0, "after the end: nothing spent")
			hw.Earned = price - 1
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == "Poor", "1 short")
			hw.Earned = price
			H.expect(Ledger.buyCue(hw, "PitchforkCue", LIVE, false, true), "exactly the price")
			H.expect(Ledger.balance(hw) == 0, "nothing left")
		end)
		withCues(false, function()
			local hw = saveWith(10000).Halloween
			H.expect(Ledger.buyCheck(hw, "PitchforkCue", LIVE, false, true) == "Closed", "off")
		end)
	end,

	["bought Candy buys cues too, and the end converts only what is left"] = function()
		withCues(true, function()
			local save = saveWith(200)
			local hw = save.Halloween
			Ledger.addCandy(hw, 300, "Bought") -- a pack
			H.expect(buy(save, "PitchforkCue", LIVE), "200 earned + 300 bought")
			H.expect(Ledger.balance(hw) == 200, "200 left")
			local earned, bought = Ledger.convertSplit(hw)
			H.expect(earned == 0 and bought == 2000, "the earned 200 spent first: $2,000 bought")
		end)
	end,

	["grantFor: a cue product gives its cue while open; Closed or Owned pays the money fallback"] = function()
		withCues(true, function()
			local function owns(id: string): boolean
				return id == "WitchBroomCue"
			end
			local grant, why = Shop.grantFor("HwPitchfork", newShop(), LIVE, false, nil, owns)
			H.expect(why == nil and grant ~= nil, "open")
			H.expect(grant.cue == "PitchforkCue" and grant.money == 0, "the Pitchfork, no money")
			for key in grant do
				H.expect(Shop.GrantFields[key] == true, "a known grant field: " .. tostring(key))
			end
			local owned, ownedWhy = Shop.grantFor("HwBroom", newShop(), LIVE, false, nil, owns)
			H.expect(ownedWhy == "Owned" and owned ~= nil and owned.cue == nil, "owned: no cue")
			H.expect(owned.money == Shop.fallbackMoney("HwBroom"), "owned: the money fallback")
			-- The receipt counts OfferGraceSeconds past the end (a prompt confirmed just before).
			local grace = Config.Shop.OfferGraceSeconds
			local late = Shop.grantFor("HwSword", newShop(), END + grace - 1, false)
			H.expect(late ~= nil and late.cue == "HalloweenSwordCue", "inside the grace")
			local after, afterWhy = Shop.grantFor("HwSword", newShop(), END + grace, false)
			H.expect(afterWhy == "Closed" and after ~= nil and after.cue == nil, "after it")
			H.expect(after.money == Shop.fallbackMoney("HwSword"), "the money fallback")
			local early, earlyWhy = Shop.grantFor("HwSword", newShop(), START - 60, false)
			H.expect(earlyWhy == "Closed" and early ~= nil and early.cue == nil, "before")
		end)
		withCues(false, function()
			local grant, why = Shop.grantFor("HwPitchfork", newShop(), LIVE, false)
			H.expect(why == "Closed" and grant ~= nil and grant.cue == nil, "switched off")
		end)
	end,

	["Buy check: a cue product is Closed outside Live, Owned once owned, on the Halloween clock"] = function()
		withCues(true, function()
			H.expect(ShopView.check("HwBroom", ctxAt(LIVE)) == nil, "Live: prompts")
			H.expect(ShopView.check("HwBroom", ctxAt(START - 60)) == "Closed", "before")
			H.expect(ShopView.check("HwBroom", ctxAt(END)) == "Closed", "after: no grace here")
			H.expect(ShopView.check("HwBroom", ctxAt(START - 3600, LIVE)) == nil, "test time")
			H.expect(ShopView.check("HwBroom", ctxAt(LIVE, END + 5)) == "Closed", "test end")
			local mine = ctxAt(LIVE)
			mine.ownsCue = function(id: string): boolean
				return id == "WitchBroomCue"
			end
			H.expect(ShopView.check("HwBroom", mine) == "Owned", "owned")
			H.expect(ShopView.check("HwSword", mine) == nil, "another cue still sells")
			local view = ShopView.build(mine)
			local broom, sword = view.products.HwBroom, view.products.HwSword
			H.expect(broom.owned and not broom.canBuy and broom.reason == "Owned", "OWNED")
			H.expect(not sword.owned and sword.canBuy and sword.robux == 599, "the Sword: 599")
			H.expect(view.products.HwPitchfork.robux == 49 and broom.robux == 249, "prices")
		end)
		withCues(false, function()
			H.expect(ShopView.check("HwPitchfork", ctxAt(LIVE)) == "Closed", "switched off")
		end)
	end,

	["a replayed cue receipt grants the cue once; owned or ended pays money"] = function()
		withCues(true, function()
			local server = fakeServer(LIVE)
			local save = server.players[7].save
			local id = Config.Products.List.HwBroom.Id
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "b1")) == "Granted", "first")
			H.expect(Inventory.count(save, "WitchBroomCue") == 1, "the Broom")
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "b1")) == "Granted", "replay")
			H.expect(server.grants == 1 and save.Money == 0, "the same id: once, no money")
			-- A second receipt (a new id) for the owned Broom: its money instead of nothing.
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "b2")) == "Granted", "owned")
			H.expect(Inventory.count(save, "WitchBroomCue") == 1, "still one")
			H.expect(save.Money == Shop.fallbackMoney("HwBroom"), "the money fallback")
			-- Bought with Candy, then a Robux receipt: money too.
			save.Halloween.Earned = 500
			H.expect(buy(save, "PitchforkCue", LIVE), "the Pitchfork for Candy")
			local fork = Config.Products.List.HwPitchfork.Id
			H.expect(Shop.processReceipt(server.deps, receipt(7, fork, "p1")) == "Granted", "paid")
			local both = Shop.fallbackMoney("HwBroom") + Shop.fallbackMoney("HwPitchfork")
			H.expect(save.Money == both, "the Pitchfork's money too")
			-- After the end (and its grace): money, no Sword.
			local late = fakeServer(END + Config.Shop.OfferGraceSeconds + 60)
			local sword = Config.Products.List.HwSword.Id
			H.expect(Shop.processReceipt(late.deps, receipt(7, sword, "s1")) == "Granted", "late")
			local lateSave = late.players[7].save
			H.expect(Inventory.count(lateSave, "HalloweenSwordCue") == 0, "no Sword")
			H.expect(lateSave.Money == Shop.fallbackMoney("HwSword"), "the money fallback")
			H.expect(Shop.processReceipt(late.deps, receipt(7, sword, "s1")) == "Granted", "again")
			H.expect(lateSave.Money == Shop.fallbackMoney("HwSword"), "paid once")
		end)
	end,

	["a gifted cue lands with the receiver, once; a receiver who owns it gets the money"] = function()
		withCues(true, function()
			local server = fakeServer(LIVE)
			local giver, friend = server.players[7].save, server.players[8].save
			local id = Config.Products.List.HwSword.Id
			server.gifts[7] = { key = "HwSword", to = 8 }
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "g1")) == "Granted", "gift")
			H.expect(Inventory.count(friend, "HalloweenSwordCue") == 1, "the friend's Sword")
			H.expect(Inventory.count(giver, "HalloweenSwordCue") == 0, "not the giver's")
			H.expect(Shop.hasPurchase(giver.Shop, "g1"), "the giver's save holds the id")
			server.gifts[7] = { key = "HwSword", to = 8 }
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "g1")) == "Granted", "replay")
			H.expect(Inventory.count(friend, "HalloweenSwordCue") == 1, "still one")
			H.expect(friend.Money == 0 and giver.Money == 0, "no money")
			-- Another Sword for the friend (a new receipt): they own it, so its money.
			server.gifts[7] = { key = "HwSword", to = 8 }
			H.expect(Shop.processReceipt(server.deps, receipt(7, id, "g2")) == "Granted", "again")
			H.expect(friend.Money == Shop.fallbackMoney("HwSword"), "the friend's money")
			H.expect(Inventory.count(friend, "HalloweenSwordCue") == 1, "one Sword")
		end)
	end,

	["the Halloween funnel: three steps, then each shop cue by its product key (CandyService's rule)"] = function()
		local names = H.require("Tutorial.Steps").Funnels.Halloween
		local want = { "1_Button", "2_Opened", "3_FirstCandy" }
		for i, r in C.Cues.List do
			local short = string.gsub(r.Product, "^Hw", "")
			table.insert(want, ("%d_%s"):format(i + 3, short))
		end
		H.expect(want[4] == "4_Pitchfork" and want[6] == "6_Sword", "the names")
		H.expect(#names == #want, ("%d steps, expected %d"):format(#names, #want))
		for i, name in want do
			H.expect(
				names[i] == name,
				("step %d is %s, expected %s"):format(i, tostring(names[i]), name)
			)
		end
	end,
}
