--!strict
-- The shop's rules: money packs, offer windows, VIP, grants, Money Party, the Limited shelf and
-- the once-only receipt handler (Progression/Shop, numbers in Config.Shop and Config.Products).
-- Expected values are ECONOMY.md section 11's tables, written out here.

local H = require("./harness")

local Config = H.require("Config")
local Shop = H.require("Progression.Shop")

local DAY = 86400
local HOUR = 3600
local JOIN = 1790553600 -- a first join, 2026-09-28 00:00 UTC

-- ECONOMY 11.1: every money pack, smallest first.
local PACKS = {
	{ name = "Handful", robux = 49, money = 900, bonus = 0 },
	{ name = "Stack", robux = 99, money = 1950, bonus = 7 },
	{ name = "Bundle", robux = 249, money = 5250, bonus = 15 },
	{ name = "Briefcase", robux = 499, money = 11000, bonus = 20 },
	{ name = "Vault", robux = 999, money = 23500, bonus = 28 },
	{ name = "Bank", robux = 2499, money = 62500, bonus = 36 },
	{ name = "Fortune", robux = 4999, money = 130000, bonus = 42 },
}

local function newShop(overrides: { [string]: any }?): any
	local shop: { [string]: any } = {
		FirstJoin = JOIN,
		VipOffer = false,
		VipCueGiven = false,
		StarterBought = false,
		FirstPackBought = false,
		Purchases = {},
		Limited = {},
	}
	for key, value in overrides or {} do
		shop[key] = value
	end
	return shop
end

-- Runs `fn` with product ids set in Config (all 0 until the designer makes them), then puts
-- the zeros back even if it fails.
local function withIds(ids: { [string]: number }, fn: () -> ())
	local list = Config.Products.List
	local keys = {}
	for key in ids do
		table.insert(keys, key)
	end
	table.sort(keys)
	local old = {}
	for _, key in keys do
		old[key] = list[key].Id
		list[key].Id = ids[key]
	end
	local ok, err = pcall(fn)
	for _, key in keys do
		list[key].Id = old[key]
	end
	if not ok then
		error(err, 0)
	end
end

-- A fake server for the receipt handler: players with saves, a save that can be told to fail,
-- and counters for grants and saves. The grant applies a Shop grant in one "mutation", the
-- way src/server/Store.luau does.
local function fakeServer(): any
	local server: any = { players = {}, grants = 0, saves = 0, failSaves = 0, logs = {} }
	server.ids = { [101] = "Pack1", [102] = "Pack3", [103] = "VipOffer", [104] = "StarterPack" }

	function server.join(userId: number): any
		local player = {
			UserId = userId,
			loaded = true,
			save = { Money = 0, Cues = {}, Shop = newShop() },
		}
		server.players[userId] = player
		return player
	end

	server.deps = {
		keyForId = function(id: number): string?
			return server.ids[id]
		end,
		findPlayer = function(userId: number): any?
			return server.players[userId]
		end,
		isLoaded = function(player: any): boolean
			return player.loaded
		end,
		hasPurchase = function(player: any, purchaseId: string): boolean
			return Shop.hasPurchase(player.save.Shop, purchaseId)
		end,
		grant = function(player: any, key: string, purchaseId: string): boolean
			local grant = Shop.grantFor(key, player.save.Shop, JOIN)
			if grant == nil then
				return false
			end
			player.save.Money += grant.money
			if grant.cue then
				table.insert(player.save.Cues, grant.cue)
			end
			Shop.markGrant(player.save.Shop, grant)
			Shop.recordPurchase(player.save.Shop, purchaseId)
			server.grants += 1
			return true
		end,
		save = function(_player: any): boolean
			server.saves += 1
			if server.failSaves > 0 then
				server.failSaves -= 1
				return false
			end
			return true
		end,
		log = function(message: string)
			table.insert(server.logs, message)
		end,
	}
	return server
end

local function receipt(userId: number, productId: number, purchaseId: string): any
	return { PlayerId = userId, ProductId = productId, PurchaseId = purchaseId }
end

return {
	["every money pack matches ECONOMY 11.1"] = function()
		local packs = Shop.packs()
		H.expect(#packs == #PACKS, ("%d packs, expected %d"):format(#packs, #PACKS))
		for i, want in PACKS do
			local pack = packs[i]
			H.expect(pack.key == Config.Products.PackOrder[i], "shop order")
			H.expect(
				Shop.product(pack.key).Kind == "Product",
				want.name .. " is a developer product"
			)
			H.expect(
				pack.robux == want.robux and pack.money == want.money and pack.bonus == want.bonus,
				("%s: %d R$ $%d +%d%%"):format(want.name, pack.robux, pack.money, pack.bonus)
			)
		end
	end,

	["each pack's bonus is its money per Robux over the first pack's"] = function()
		local packs = Shop.packs()
		local base = packs[1].money / packs[1].robux
		for _, pack in packs do
			local bonus = (pack.money / pack.robux / base - 1) * 100
			H.near(bonus, pack.bonus, 1, pack.key .. " bonus %")
		end
	end,

	["the welcome offer is open for 24 hours from the first join"] = function()
		local shop = newShop()
		local function open(t: number): boolean
			return Shop.offers(shop, t, false).welcome.open
		end
		H.expect(open(JOIN), "at the first join")
		H.expect(open(JOIN + DAY - 1), "the last second")
		H.expect(not open(JOIN + DAY), "closed after 24 hours")
		H.expect(open(JOIN - 2), "another server's clock a moment behind")
		H.expect(
			Shop.offers(shop, JOIN + 5, false).welcome.endsAt == JOIN + DAY,
			"a real countdown"
		)
	end,

	["one comeback window 7 days later, then never again"] = function()
		local shop = newShop()
		local function open(t: number): boolean
			return Shop.offers(shop, t, false).comeback.open
		end
		H.expect(not open(JOIN + DAY), "not between the windows")
		H.expect(not open(JOIN + 7 * DAY - 1), "a second before")
		H.expect(open(JOIN + 7 * DAY), "opens 7 days after the first join")
		H.expect(open(JOIN + 8 * DAY - 1), "open for 24 hours")
		H.expect(not open(JOIN + 8 * DAY), "closed after")
		local window = Shop.offers(shop, JOIN + 7 * DAY + 60, false).comeback
		H.expect(
			window.startsAt == JOIN + 7 * DAY and window.endsAt == JOIN + 8 * DAY,
			"saved times"
		)
		for day = 8, 400 do
			local offers = Shop.offers(shop, JOIN + day * DAY + 1234, false)
			H.expect(
				not offers.welcome.open and not offers.comeback.open,
				("day %d: never again"):format(day)
			)
		end
	end,

	["the Starter Pack is on for 7 days, until bought"] = function()
		local shop = newShop()
		H.expect(Shop.offers(shop, JOIN, false).starter.open, "at the first join")
		H.expect(Shop.offers(shop, JOIN + 7 * DAY - 1, false).starter.open, "the last second")
		H.expect(not Shop.offers(shop, JOIN + 7 * DAY, false).starter.open, "closed after 7 days")
		H.expect(Shop.offers(shop, JOIN, true).starter.open, "VIP still sees it")
		shop.StarterBought = true
		H.expect(not Shop.offers(shop, JOIN + DAY, false).starter.open, "once only")
	end,

	["VIP closes the welcome and comeback offers"] = function()
		local shop = newShop()
		H.expect(not Shop.offers(shop, JOIN, true).welcome.open, "welcome")
		H.expect(not Shop.offers(shop, JOIN + 7 * DAY, true).comeback.open, "comeback")
	end,

	["an unknown first join keeps every offer closed"] = function()
		local offers = Shop.offers(newShop({ FirstJoin = 0 }), JOIN, false)
		H.expect(
			not offers.welcome.open and not offers.comeback.open and not offers.starter.open,
			"closed"
		)
		H.expect(offers.welcome.endsAt == 0, "no countdown")
	end,

	["VIP is the pass or the welcome offer"] = function()
		H.expect(not Shop.isVip(false, newShop()), "neither")
		H.expect(Shop.isVip(true, newShop()), "pass")
		H.expect(Shop.isVip(false, newShop({ VipOffer = true })), "offer")
		H.expect(Shop.isVip(true, newShop({ VipOffer = true })), "both")
		H.expect(Shop.vipCueDue(true, newShop()), "a new VIP gets the cue")
		H.expect(not Shop.vipCueDue(true, newShop({ VipCueGiven = true })), "once")
		H.expect(not Shop.vipCueDue(false, newShop()), "not VIP")
	end,

	["product ids: 0 is never a match; products and passes are apart"] = function()
		H.expect(Shop.keyForId(0) == nil and Shop.passKeyForId(0) == nil, "id 0")
		H.expect(not Shop.available("Pack1") and not Shop.available("Vip"), "nothing made yet")
		H.expect(not Shop.available("NoSuchProduct"), "unknown")
		withIds({ Pack2 = 111, Vip = 222, MoneyParty = 333 }, function()
			H.expect(Shop.keyForId(111) == "Pack2", "a pack")
			H.expect(Shop.keyForId(333) == "MoneyParty", "the party")
			H.expect(Shop.keyForId(222) == nil, "a pass is not a developer product")
			H.expect(Shop.passKeyForId(222) == "Vip", "the VIP pass")
			H.expect(Shop.passKeyForId(111) == nil, "a product is not a pass")
			H.expect(Shop.keyForId(999) == nil, "unknown id")
			H.expect(Shop.available("Pack2") and Shop.available("Vip"), "made")
			H.expect(not Shop.available("Pack1"), "still 0")
		end)
		H.expect(Shop.keyForId(111) == nil, "ids restored")
	end,

	["the first money pack pays double, exactly once"] = function()
		local shop = newShop()
		local first = Shop.grantFor("Pack1", shop, JOIN)
		H.expect(first.money == 1800 and first.firstPack == true, "Handful doubled: $1,800")
		H.expect(first.cue == nil and not first.vip and not first.party, "money only")
		-- Asking again before it is applied changes nothing (grantFor is read-only).
		H.expect(Shop.grantFor("Pack1", shop, JOIN).money == 1800, "grantFor changes nothing")
		Shop.markGrant(shop, first)
		H.expect(shop.FirstPackBought, "marked")
		local second = Shop.grantFor("Pack3", shop, JOIN)
		H.expect(second.money == 5250 and not second.firstPack, "Bundle at its normal $5,250")
		-- Other products never use up the double.
		local fresh = newShop()
		Shop.markGrant(fresh, Shop.grantFor("StarterPack", fresh, JOIN))
		Shop.markGrant(fresh, Shop.grantFor("MoneyParty", fresh, JOIN))
		H.expect(
			Shop.grantFor("Pack7", fresh, JOIN).money == 260000,
			"still doubled after other products"
		)
	end,

	["VIP offer, Starter Pack, Money Party and Founder's Cue grants"] = function()
		local shop = newShop()
		local vip = Shop.grantFor("VipOffer", shop, JOIN)
		H.expect(vip.vip and vip.money == 0, "VIP, no money")
		H.expect(vip.cue == Config.Shop.VipCue and vip.vipCue, "the VIP Cue")
		Shop.markGrant(shop, vip)
		H.expect(shop.VipOffer and shop.VipCueGiven, "flags set")
		local again = Shop.grantFor("VipOffer", shop, JOIN)
		H.expect(again.vip and again.cue == nil and not again.vipCue, "the VIP Cue only once")

		local starter = Shop.grantFor("StarterPack", newShop(), JOIN)
		H.expect(
			starter.money == 3000 and starter.cue == "StarterCue",
			"$3,000 and the Starter Cue"
		)
		H.expect(
			starter.starterBought and not starter.firstPack,
			"marks the starter, not the first pack"
		)

		local party = Shop.grantFor("MoneyParty", newShop(), JOIN)
		H.expect(party.party and party.money == 0 and party.cue == nil, "a party only")

		local founders = Shop.grantFor("FoundersCue", newShop(), JOIN)
		H.expect(founders.limited == "FoundersCue" and founders.cue == nil, "the Limited copy")

		H.expect(Shop.grantFor("Vip", newShop(), JOIN) == nil, "a pass is not granted by receipt")
		H.expect(Shop.grantFor("FastOpen", newShop(), JOIN) == nil, "nor Fast Open")
		H.expect(Shop.grantFor("NoSuchProduct", newShop(), JOIN) == nil, "unknown")
	end,

	["Money Party queues 15 minutes a purchase, at most an hour"] = function()
		local now = JOIN
		local ends = Shop.partyEndsAt(0, now)
		H.expect(ends == now + 15 * 60, "15 minutes")
		ends = Shop.partyEndsAt(ends, now)
		ends = Shop.partyEndsAt(ends, now)
		ends = Shop.partyEndsAt(ends, now)
		H.expect(ends == now + HOUR, "four make an hour")
		H.expect(not Shop.canQueueParty(ends, now), "the queue is full")
		H.expect(Shop.partyEndsAt(ends, now) == now + HOUR, "a fifth adds nothing past the hour")
		-- Ten minutes later there is room for ten more minutes only.
		local later = now + 600
		H.expect(not Shop.canQueueParty(ends, later), "not room for a full 15")
		H.expect(Shop.partyEndsAt(ends, later) == later + HOUR, "capped an hour past now")
		H.expect(Shop.canQueueParty(ends, now + 900), "room again after 15 minutes")
		-- An ended party starts fresh from now.
		H.expect(Shop.partyEndsAt(now - 50, now) == now + 900, "from now")
		-- A purchase never cuts time already queued.
		H.expect(Shop.partyEndsAt(now + 2 * HOUR, now) == now + 2 * HOUR, "never shorter")
	end,

	["the Limited shelf's state"] = function()
		local rows = Shop.limited()
		H.expect(#rows >= 1, "rows")
		local beta = Shop.limitedFor("BetaCue")
		H.expect(
			beta ~= nil and beta.Price == 40000 and beta.Cap == 1000,
			"the Beta Cue: $40,000, 1,000 copies"
		)
		H.expect(Shop.limitedFor("NoSuchCue") == nil, "unknown")
		local row = { Cue = "TestCue", Price = 100, Cap = 10, StartsAt = 1000, Seconds = 500 }
		local before = Shop.limitedState(row, 999, 0, false)
		H.expect(not before.open and not before.canBuy, "not started")
		local start = Shop.limitedState(row, 1000, 0, false)
		H.expect(start.open and start.canBuy and start.endsAt == 1500, "open from StartsAt")
		H.expect(Shop.limitedState(row, 1499, 9, false).canBuy, "the last copy, the last second")
		H.expect(not Shop.limitedState(row, 1500, 0, false).open, "never again once ended")
		local soldOut = Shop.limitedState(row, 1200, 10, false)
		H.expect(soldOut.soldOut and not soldOut.open and not soldOut.canBuy, "sold out at the cap")
		local owned = Shop.limitedState(row, 1200, 3, true)
		H.expect(owned.open and owned.owned and not owned.canBuy, "one per player")
		H.expect(
			not Shop.limitedState(row, 1200, nil, false).soldOut,
			"unknown count is not sold out"
		)
		local uncapped = { Cue = "Free", Price = 5, StartsAt = 0, Seconds = 10 }
		H.expect(not Shop.limitedState(uncapped, 5, 1e9, false).soldOut, "no cap, never sold out")
	end,

	["Need $X more highlights the smallest pack that covers it"] = function()
		H.expect(Shop.packForGap(0, true) == nil, "nothing missing")
		H.expect(Shop.packForGap(900, true) == "Pack1", "exactly Handful")
		H.expect(Shop.packForGap(901, true) == "Pack2", "one over")
		H.expect(Shop.packForGap(1800, false) == "Pack1", "Handful doubled covers $1,800")
		H.expect(Shop.packForGap(12000, true) == "Pack5", "Vault")
		H.expect(Shop.packForGap(1e9, true) == "Pack7", "nothing covers it: the biggest")
		local last = 0
		for _, pack in Shop.packs() do
			H.expect(
				pack.money > last,
				"packs grow in money, so the first that covers is the smallest"
			)
			last = pack.money
		end
	end,

	["a receipt is granted once; a retry grants nothing more"] = function()
		local server = fakeServer()
		local player = server.join(1)
		local r = receipt(1, 101, "p-1")
		H.expect(Shop.processReceipt(server.deps, r) == "Granted", "granted")
		H.expect(player.save.Money == 1800 and server.grants == 1, "the first pack, doubled")
		H.expect(Shop.hasPurchase(player.save.Shop, "p-1"), "id recorded")
		H.expect(Shop.processReceipt(server.deps, r) == "Granted", "the retry is acknowledged")
		H.expect(player.save.Money == 1800 and server.grants == 1, "and grants nothing")
		H.expect(
			Shop.processReceipt(server.deps, receipt(1, 101, "p-2")) == "Granted",
			"a new purchase"
		)
		H.expect(player.save.Money == 2700 and server.grants == 2, "not doubled the second time")
	end,

	["a player who left or is not loaded: NotProcessedYet"] = function()
		local server = fakeServer()
		H.expect(
			Shop.processReceipt(server.deps, receipt(7, 101, "p-1")) == "NotProcessedYet",
			"not here"
		)
		local player = server.join(7)
		player.loaded = false
		H.expect(
			Shop.processReceipt(server.deps, receipt(7, 101, "p-1")) == "NotProcessedYet",
			"not loaded"
		)
		H.expect(server.grants == 0 and player.save.Money == 0, "nothing granted")
		player.loaded = true
		H.expect(
			Shop.processReceipt(server.deps, receipt(7, 101, "p-1")) == "Granted",
			"later: granted"
		)
		H.expect(player.save.Money == 1800, "once")
	end,

	["a failed save: NotProcessedYet, then Granted on retry without a second grant"] = function()
		local server = fakeServer()
		local player = server.join(3)
		server.failSaves = 1
		local r = receipt(3, 104, "p-starter")
		H.expect(Shop.processReceipt(server.deps, r) == "NotProcessedYet", "save failed")
		H.expect(server.grants == 1 and player.save.Money == 3000, "granted in memory")
		H.expect(Shop.processReceipt(server.deps, r) == "Granted", "retry: saved now")
		H.expect(server.grants == 1 and player.save.Money == 3000, "no second grant")
		H.expect(#player.save.Cues == 1 and player.save.Cues[1] == "StarterCue", "one Starter Cue")
		H.expect(server.saves == 2, "the retry saved again before acknowledging")
		-- A retry whose save fails too stays NotProcessedYet, still without granting.
		server.failSaves = 1
		H.expect(
			Shop.processReceipt(server.deps, r) == "NotProcessedYet",
			"not acknowledged unsaved"
		)
		H.expect(server.grants == 1, "still one grant")
	end,

	["a dep that throws: NotProcessedYet"] = function()
		local server = fakeServer()
		local player = server.join(4)
		local deps = table.clone(server.deps)
		deps.grant = function(): boolean
			error("DataStore exploded")
		end
		H.expect(
			Shop.processReceipt(deps, receipt(4, 101, "p-1")) == "NotProcessedYet",
			"grant threw"
		)
		H.expect(player.save.Money == 0, "nothing granted")
		H.expect(
			#server.logs == 1 and server.logs[1]:find("DataStore exploded", 1, true) ~= nil,
			"logged"
		)
		for _, name in { "keyForId", "findPlayer", "isLoaded", "hasPurchase", "save" } do
			local broken = table.clone(server.deps)
			broken[name] = function(): any
				error(name .. " broke")
			end
			H.expect(
				Shop.processReceipt(broken, receipt(4, 101, "p-9")) == "NotProcessedYet",
				name .. " threw"
			)
		end
		-- Even a log that throws cannot break the answer.
		local noisy = table.clone(server.deps)
		noisy.log = function()
			error("log broke")
		end
		noisy.save = function(): boolean
			return false
		end
		H.expect(
			Shop.processReceipt(noisy, receipt(4, 102, "p-10")) == "NotProcessedYet",
			"log threw"
		)
		H.expect(Shop.processReceipt(noisy, nil :: any) == "NotProcessedYet", "no receipt at all")
	end,

	["unknown products and bad receipts: NotProcessedYet, logged"] = function()
		local server = fakeServer()
		server.join(5)
		H.expect(
			Shop.processReceipt(server.deps, receipt(5, 999, "p-1")) == "NotProcessedYet",
			"unknown id"
		)
		H.expect(
			#server.logs == 1 and server.logs[1]:find("999", 1, true) ~= nil,
			"logged with the id"
		)
		H.expect(
			Shop.processReceipt(server.deps, receipt(5, 101, "")) == "NotProcessedYet",
			"no purchase id"
		)
		-- With the real lookup every product is still id 0: nothing matches.
		local real = table.clone(server.deps)
		real.keyForId = Shop.keyForId
		H.expect(Shop.processReceipt(real, receipt(5, 0, "p-2")) == "NotProcessedYet", "id 0")
		H.expect(server.grants == 0, "nothing granted")
	end,

	["recent purchases keep the last 50, each once"] = function()
		H.expect(Config.Shop.RecentPurchases == 50, "50 remembered")
		local shop = newShop()
		for i = 1, 60 do
			Shop.recordPurchase(shop, "p-" .. i)
		end
		H.expect(#shop.Purchases == 50, "capped at 50")
		H.expect(
			shop.Purchases[1] == "p-11" and shop.Purchases[50] == "p-60",
			"oldest dropped first"
		)
		H.expect(not Shop.hasPurchase(shop, "p-10") and Shop.hasPurchase(shop, "p-11"), "lookups")
		Shop.recordPurchase(shop, "p-60")
		H.expect(#shop.Purchases == 50 and shop.Purchases[50] == "p-60", "no duplicate")
		local old = newShop()
		old.Purchases = nil
		H.expect(not Shop.hasPurchase(old, "x"), "no list yet")
		Shop.recordPurchase(old, "x")
		H.expect(Shop.hasPurchase(old, "x"), "list made")
	end,
}
