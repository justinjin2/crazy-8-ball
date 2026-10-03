--!strict
-- The shop's rules: money packs, offer windows, VIP, grants, Money Party, the Limited shelf and
-- the once-only receipt handler (Progression/Shop, numbers in Config.Shop and Config.Products),
-- and the ShopState payload and Buy check built from them (Progression/ShopView).
-- Expected values are ECONOMY.md section 11's tables, written out here.

local H = require("./harness")

local Config = H.require("Config")
local Shop = H.require("Progression.Shop")
local ShopView = H.require("Progression.ShopView")

local DAY = 86400
local HOUR = 3600
local JOIN = 1790553600 -- a first join, 2026-09-28 00:00 UTC

-- The economy plan (section 5): every money pack, smallest first.
local PACKS = {
	{ name = "Handful", robux = 49, money = 9000, bonus = 0 },
	{ name = "Stack", robux = 99, money = 19500, bonus = 7 },
	{ name = "Bundle", robux = 249, money = 52500, bonus = 15 },
	{ name = "Briefcase", robux = 499, money = 110000, bonus = 20 },
	{ name = "Vault", robux = 999, money = 235000, bonus = 28 },
	{ name = "Bank", robux = 2499, money = 625000, bonus = 36 },
	{ name = "Fortune", robux = 4999, money = 1300000, bonus = 42 },
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

-- Test-only Limited rows: Config's shelf holds only the Grand Opening (off until its date), so
-- the old money Beta row and a Robux Founder's row stand in for every Limited path. Runs `fn`
-- with them in Config, then takes them out even if it fails.
local function withLimiteds(fn: () -> ())
	local list: { any } = Config.Shop.Limited :: any
	local n = #list
	local products: any = Config.Products.List
	products.FoundersCue = { Kind = "Product", Id = 0, Robux = 1499 }
	table.insert(
		list,
		{ Cue = "BetaCue", Price = 40000, Cap = 1000, StartsAt = 1790553600, Seconds = 30 * DAY }
	)
	table.insert(list, {
		Cue = "FoundersCue",
		Product = "FoundersCue",
		Cap = 50,
		StartsAt = 1790553600,
		Seconds = 30 * DAY,
	})
	local ok, err = pcall(fn)
	for i = #list, n + 1, -1 do
		table.remove(list, i)
	end
	products.FoundersCue = nil
	if not ok then
		error(err, 0)
	end
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
			local grant = Shop.grantFor(key, player.save.Shop, JOIN, false)
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

-- A ShopView context at unix time `now`: a player who joined at JOIN, owns nothing, in a
-- server with no party, no sale, no Limited counts read and no live prices.
local function ctxAt(now: number, overrides: { [string]: any }?): any
	local ctx: { [string]: any } = {
		now = now,
		shop = newShop(),
		vipPass = false,
		fastOpen = false,
		restricted = false,
		partyEndsAt = 0,
		sold = {},
		prices = {},
	}
	for key, value in overrides or {} do
		ctx[key] = value
	end
	return ctx
end

-- The soonest start or end of a Limited row after `t`, or nil.
local function limitedBoundary(t: number): number?
	local soonest: number? = nil
	for _, row in Shop.limited() do
		for _, at in { row.StartsAt, row.StartsAt + row.Seconds } do
			if at > t and (soonest == nil or at < soonest) then
				soonest = at
			end
		end
	end
	return soonest
end

local function soonest(a: number?, b: number?): number?
	if a == nil then
		return b
	elseif b == nil then
		return a
	end
	return math.min(a, b)
end

-- What src/client/ItemState.offerEndsAt reads from a ShopState payload: the soonest end of an
-- open offer keyed by a word it knows (a copy of its rule, so the payload's shape is checked
-- against the client's reader), and no stray flat field it would mistake for an offer.
local OFFER_WORDS = { "vip", "welcome", "comeback", "starter" }
local function isOfferKey(key: string): boolean
	for _, word in OFFER_WORDS do
		if string.find(string.lower(key), word, 1, true) then
			return true
		end
	end
	return false
end
local function offerEndsAt(payload: any, now: number): number?
	local found: number? = nil
	for key, entry in payload.offers do
		if isOfferKey(key) and entry.open ~= false and entry.endsAt > now then
			found = soonest(found, entry.endsAt)
		end
	end
	for key, entry in payload do
		if key ~= "offers" and isOfferKey(key) then
			H.expect(type(entry) ~= "table", key .. " is a flat table the client would misread")
		end
	end
	return found
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
		local first = Shop.grantFor("Pack1", shop, JOIN, false)
		H.expect(first.money == 18000 and first.firstPack == true, "Handful doubled: $18,000")
		H.expect(first.cue == nil and not first.vip and not first.party, "money only")
		-- Asking again before it is applied changes nothing (grantFor is read-only).
		H.expect(
			Shop.grantFor("Pack1", shop, JOIN, false).money == 18000,
			"grantFor changes nothing"
		)
		Shop.markGrant(shop, first)
		H.expect(shop.FirstPackBought, "marked")
		local second = Shop.grantFor("Pack3", shop, JOIN, false)
		H.expect(second.money == 52500 and not second.firstPack, "Bundle at its normal $52,500")
		-- Other products never use up the double.
		local fresh = newShop()
		Shop.markGrant(fresh, Shop.grantFor("StarterPack", fresh, JOIN, false))
		Shop.markGrant(fresh, Shop.grantFor("MoneyParty", fresh, JOIN, false))
		H.expect(
			Shop.grantFor("Pack7", fresh, JOIN, false).money == 2600000,
			"still doubled after other products"
		)
	end,

	["VIP offer, Starter Pack, Money Party and Founder's Cue grants"] = function()
		withLimiteds(function()
			local shop = newShop()
			local vip = Shop.grantFor("VipOffer", shop, JOIN, false)
			H.expect(vip.vip and vip.money == 0, "VIP, no money")
			H.expect(vip.cue == Config.Shop.VipCue and vip.vipCue, "the VIP Cue")
			Shop.markGrant(shop, vip)
			H.expect(shop.VipOffer and shop.VipCueGiven, "flags set")
			local again, why = Shop.grantFor("VipOffer", shop, JOIN, false)
			H.expect(
				not again.vip and again.cue == nil and not again.vipCue and why == "Owned",
				"bought again: VIP already, so plain money and never a second VIP Cue"
			)

			local starter = Shop.grantFor("StarterPack", newShop(), JOIN, false)
			H.expect(
				starter.money == 75000 and starter.cue == "StarterCue",
				"$75,000 and the Starter Cue"
			)
			H.expect(
				starter.starterBought and not starter.firstPack,
				"marks the starter, not the first pack"
			)

			local party = Shop.grantFor("MoneyParty", newShop(), JOIN, false)
			H.expect(party.party and party.money == 0 and party.cue == nil, "a party only")

			local founders = Shop.grantFor("FoundersCue", newShop(), JOIN, false)
			H.expect(founders.limited == "FoundersCue" and founders.cue == nil, "the Limited copy")

			H.expect(
				Shop.grantFor("Vip", newShop(), JOIN, false) == nil,
				"a pass is not granted by receipt"
			)
			H.expect(Shop.grantFor("QuickCases", newShop(), JOIN, false) == nil, "nor Quick Cases")
			H.expect(Shop.grantFor("NoSuchProduct", newShop(), JOIN, false) == nil, "unknown")
		end)
	end,

	["Money Party queues 15 minutes a purchase; the shop offers at most an hour"] = function()
		local now = JOIN
		local ends = Shop.partyEndsAt(0, now)
		H.expect(ends == now + 15 * 60, "15 minutes")
		ends = Shop.partyEndsAt(ends, now)
		ends = Shop.partyEndsAt(ends, now)
		ends = Shop.partyEndsAt(ends, now)
		H.expect(ends == now + HOUR, "four make an hour")
		H.expect(not Shop.canQueueParty(ends, now), "the queue is full: the shop stops offering")
		-- Ten minutes later there is room for ten more minutes only: still not offered.
		local later = now + 600
		H.expect(not Shop.canQueueParty(ends, later), "not room for a full 15")
		H.expect(Shop.canQueueParty(ends, now + 900), "room again after 15 minutes")
		-- A paid receipt always adds its full 15 minutes, even past the hour (two buyers at
		-- once, or a prompt confirmed slowly near the cap).
		H.expect(Shop.partyEndsAt(ends, now) == now + HOUR + 900, "a fifth still adds 15 minutes")
		H.expect(Shop.partyEndsAt(ends, later) == ends + 900, "from the current end")
		-- An ended party starts fresh from now.
		H.expect(Shop.partyEndsAt(now - 50, now) == now + 900, "from now")
		-- A purchase never cuts time already queued.
		H.expect(Shop.partyEndsAt(now + 2 * HOUR, now) == now + 2 * HOUR + 900, "never shorter")
		for _, current in { 0, now - 1, now, now + 1, now + 50 * 60, now + 3 * HOUR } do
			H.expect(
				Shop.partyEndsAt(current, now) - math.max(now, current) == 900,
				("paid in full from %+d s"):format(current - now)
			)
		end
	end,

	["a receipt checks the offer windows and once-only again, and pays money when not for them"] = function()
		withLimiteds(function()
			local grace = Config.Shop.OfferGraceSeconds
			H.expect(grace > 0 and grace < DAY, "a grace of minutes, not days")
			local function check(key: string, shop: any, now: number, pass: boolean?): string?
				return Shop.receiptCheck(key, shop, now, pass == true)
			end
			-- The VIP offer: its welcome and comeback windows, each a grace longer; never for a VIP.
			H.expect(check("VipOffer", newShop(), JOIN + HOUR) == nil, "the welcome day")
			H.expect(
				check("VipOffer", newShop(), JOIN + DAY + grace - 1) == nil,
				"just after: grace"
			)
			H.expect(check("VipOffer", newShop(), JOIN + DAY + grace) == "Closed", "then closed")
			H.expect(
				check("VipOffer", newShop(), JOIN + 3 * DAY) == "Closed",
				"between the windows"
			)
			H.expect(
				check("VipOffer", newShop(), JOIN + 7 * DAY - 1) == "Closed",
				"a second before the comeback"
			)
			H.expect(check("VipOffer", newShop(), JOIN + 7 * DAY) == nil, "the comeback window")
			H.expect(check("VipOffer", newShop(), JOIN + 8 * DAY + grace - 1) == nil, "its grace")
			H.expect(
				check("VipOffer", newShop(), JOIN + 8 * DAY + grace) == "Closed",
				"never again"
			)
			H.expect(
				check("VipOffer", newShop(), JOIN + HOUR, true) == "Owned",
				"owns the VIP pass"
			)
			H.expect(
				check("VipOffer", newShop({ VipOffer = true }), JOIN + HOUR) == "Owned",
				"bought the offer before"
			)
			H.expect(
				check("VipOffer", newShop({ FirstJoin = 0 }), JOIN) == "Closed",
				"first join unknown"
			)
			-- The Starter Pack: its week plus the grace, once; a VIP may still buy it.
			H.expect(check("StarterPack", newShop(), JOIN + 6 * DAY, true) == nil, "its week")
			H.expect(check("StarterPack", newShop(), JOIN + 7 * DAY + grace - 1) == nil, "grace")
			H.expect(check("StarterPack", newShop(), JOIN + 7 * DAY + grace) == "Closed", "closed")
			H.expect(
				check("StarterPack", newShop({ StarterBought = true }), JOIN + HOUR) == "Owned",
				"once only"
			)
			H.expect(
				check("StarterPack", newShop({ FirstJoin = 0 }), JOIN) == "Closed",
				"first join unknown"
			)
			-- A Robux Limited already owned; packs and the party are always for everyone.
			H.expect(
				check("FoundersCue", newShop({ Limited = { FoundersCue = 3 } }), JOIN) == "Owned",
				"the Founder's Cue owned"
			)
			H.expect(check("FoundersCue", newShop(), JOIN) == nil, "the counter decides the rest")
			for _, key in { "Pack1", "Pack7", "MoneyParty" } do
				H.expect(
					check(
						key,
						newShop({ StarterBought = true, VipOffer = true }),
						JOIN + 99 * DAY,
						true
					) == nil,
					key .. " is always for everyone"
				)
			end

			-- The grant: plain money at the first pack's money per Robux, no flags.
			local grant, why =
				Shop.grantFor("StarterPack", newShop({ StarterBought = true }), JOIN, false)
			H.expect(why == "Owned" and grant ~= nil, "a fallback grant")
			H.expect(
				grant.money == 18183 and grant.key == "StarterPack",
				"99 R$ at $9,000 / 49 R$: $18,183"
			)
			H.expect(
				grant.cue == nil
					and not grant.vip
					and not grant.vipCue
					and not grant.party
					and grant.limited == nil
					and not grant.firstPack
					and not grant.starterBought,
				"money only"
			)
			local vipGrant, vipWhy = Shop.grantFor("VipOffer", newShop(), JOIN + HOUR, true)
			H.expect(
				vipWhy == "Owned" and vipGrant.money == 54918,
				"299 R$: $54,918, no permanent VIP"
			)
			local late = Shop.grantFor("VipOffer", newShop(), JOIN + 3 * DAY, false)
			H.expect(late.money == 54918 and not late.vip, "outside the windows: money, not VIP")
			local shop = newShop({ StarterBought = true })
			Shop.markGrant(shop, grant)
			H.expect(
				not shop.FirstPackBought and not shop.VipOffer and not shop.VipCueGiven,
				"the fallback sets no flag, nor uses up the first pack's double"
			)
			H.expect(Shop.fallbackMoney("FoundersCue") == 275326, "1,499 R$: $275,326")
			H.expect(Shop.fallbackMoney("Pack1") == 9000, "the first pack's own rate")
			H.expect(Shop.fallbackMoney("NoSuchProduct") == 0, "unknown: nothing")
			H.expect(Shop.fallbackGrant("NoSuchProduct") == nil, "no grant for nothing")
			local rate = Config.Products.List.Pack1.Money / Config.Products.List.Pack1.Robux
			for _, key in { "VipOffer", "StarterPack", "MoneyParty", "FoundersCue" } do
				local robux = Config.Products.List[key].Robux
				local money = Shop.fallbackMoney(key)
				H.expect(
					money <= robux * rate and money > robux * rate - 1,
					("%s: $%d for %d R$"):format(key, money, robux)
				)
			end
			-- Inside the window the real grant, with no reason.
			local real, none =
				Shop.grantFor("StarterPack", newShop(), JOIN + 7 * DAY + grace - 1, true)
			H.expect(none == nil and real.starterBought and real.money == 75000, "the real grant")
		end)
	end,

	["a forged second Starter Pack receipt is acknowledged and paid as money"] = function()
		local server = fakeServer()
		local player = server.join(8)
		H.expect(Shop.processReceipt(server.deps, receipt(8, 104, "s-1")) == "Granted", "first")
		H.expect(player.save.Money == 75000 and #player.save.Cues == 1, "$75,000 and the cue")
		H.expect(Shop.processReceipt(server.deps, receipt(8, 104, "s-2")) == "Granted", "second")
		H.expect(player.save.Money == 75000 + 18183, "the second pays $18,183 only")
		H.expect(#player.save.Cues == 1, "no second Starter Cue")
		H.expect(Shop.processReceipt(server.deps, receipt(8, 104, "s-2")) == "Granted", "a retry")
		H.expect(player.save.Money == 75000 + 18183, "grants nothing more")
	end,

	["the Grand Opening Cue: $149,000, 14 days, no cap, off until its date"] = function()
		local grand = Shop.limitedFor("GrandOpeningCue")
		H.expect(grand ~= nil and grand.Price == 149000 and grand.Cap == nil, "$149,000, no cap")
		H.expect(grand.Seconds == 14 * DAY and grand.StartsAt == 0, "14 days, not scheduled")
		H.expect(#Shop.limited() == 0, "off: not on the shelf")
		local off = Shop.limitedState(grand, JOIN, 0, false)
		H.expect(not off.open and not off.canBuy, "never open while off")
		H.expect(Shop.limitedFor("BetaCue") == nil and Shop.limitedFor("FoundersCue") == nil, "")
		H.expect(Config.Products.List.FoundersCue == nil, "no Founder's Cue product")
		-- /limited start: this server's window over Config's, then back.
		H.expect(Shop.setWindow("GrandOpeningCue", JOIN, 14 * DAY), "set")
		local rows = Shop.limited()
		H.expect(#rows == 1 and rows[1].Cue == "GrandOpeningCue" and rows[1].StartsAt == JOIN, "")
		H.expect(Shop.limitedState(rows[1], JOIN + DAY, 5000, false).canBuy, "on sale, no cap")
		H.expect(not Shop.limitedState(rows[1], JOIN + 14 * DAY, 0, false).open, "14 days")
		H.expect(Config.Shop.Limited[1].StartsAt == 0, "Config itself untouched")
		H.expect(Shop.setWindow("GrandOpeningCue", nil, nil), "cleared")
		H.expect(#Shop.limited() == 0 and not Shop.setWindow("Nope", 1, 1), "back to off")
	end,

	["the Limited shelf's state"] = function()
		withLimiteds(function()
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
			H.expect(
				Shop.limitedState(row, 1499, 9, false).canBuy,
				"the last copy, the last second"
			)
			H.expect(not Shop.limitedState(row, 1500, 0, false).open, "never again once ended")
			local soldOut = Shop.limitedState(row, 1200, 10, false)
			H.expect(
				soldOut.soldOut and not soldOut.open and not soldOut.canBuy,
				"sold out at the cap"
			)
			local owned = Shop.limitedState(row, 1200, 3, true)
			H.expect(owned.open and owned.owned and not owned.canBuy, "one per player")
			H.expect(
				not Shop.limitedState(row, 1200, nil, false).soldOut,
				"unknown count is not sold out"
			)
			local uncapped = { Cue = "Free", Price = 5, StartsAt = 0, Seconds = 10 }
			H.expect(
				not Shop.limitedState(uncapped, 5, 1e9, false).soldOut,
				"no cap, never sold out"
			)
		end)
	end,

	["Need $X more highlights the smallest pack that covers it"] = function()
		H.expect(Shop.packForGap(0, true) == nil, "nothing missing")
		H.expect(Shop.packForGap(9000, true) == "Pack1", "exactly Handful")
		H.expect(Shop.packForGap(9001, true) == "Pack2", "one over")
		H.expect(Shop.packForGap(18000, false) == "Pack1", "Handful doubled covers $18,000")
		H.expect(Shop.packForGap(120000, true) == "Pack5", "Vault")
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
		H.expect(player.save.Money == 18000 and server.grants == 1, "the first pack, doubled")
		H.expect(Shop.hasPurchase(player.save.Shop, "p-1"), "id recorded")
		H.expect(Shop.processReceipt(server.deps, r) == "Granted", "the retry is acknowledged")
		H.expect(player.save.Money == 18000 and server.grants == 1, "and grants nothing")
		H.expect(
			Shop.processReceipt(server.deps, receipt(1, 101, "p-2")) == "Granted",
			"a new purchase"
		)
		H.expect(player.save.Money == 27000 and server.grants == 2, "not doubled the second time")
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
		H.expect(player.save.Money == 18000, "once")
	end,

	["a failed save: NotProcessedYet, then Granted on retry without a second grant"] = function()
		local server = fakeServer()
		local player = server.join(3)
		server.failSaves = 1
		local r = receipt(3, 104, "p-starter")
		H.expect(Shop.processReceipt(server.deps, r) == "NotProcessedYet", "save failed")
		H.expect(server.grants == 1 and player.save.Money == 75000, "granted in memory")
		H.expect(Shop.processReceipt(server.deps, r) == "Granted", "retry: saved now")
		H.expect(server.grants == 1 and player.save.Money == 75000, "no second grant")
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

	["ShopView.check: why a Buy may not prompt"] = function()
		withLimiteds(function()
			local founders = Shop.limitedFor("FoundersCue")
			H.expect(founders ~= nil and founders.Product == "FoundersCue", "a Robux Limited")
			local start = founders.StartsAt
			local now = math.max(JOIN, start) + HOUR
			local ctx = ctxAt(now)
			H.expect(ShopView.check("NoSuchProduct", ctx) == "BadRequest", "an unknown key")
			H.expect(ShopView.check("Pack1", ctx) == "ComingSoon", "Id 0: coming soon")
			H.expect(ShopView.check("Vip", ctx) == "ComingSoon", "a pass not made yet")
			H.expect(
				ShopView.check("Vip", ctxAt(now, { vipPass = true })) == "Owned",
				"owned beats coming soon (the /vip override)"
			)
			withIds({
				Pack1 = 1,
				VipOffer = 2,
				StarterPack = 3,
				MoneyParty = 4,
				FoundersCue = 5,
				Vip = 6,
				QuickCases = 7,
			}, function()
				local joined = ctxAt(JOIN + HOUR)
				H.expect(ShopView.check("Pack1", joined) == nil, "a money pack always sells")
				H.expect(ShopView.check("VipOffer", joined) == nil, "the welcome offer, first day")
				H.expect(
					ShopView.check("VipOffer", ctxAt(JOIN + 2 * DAY)) == "Closed",
					"between the windows"
				)
				H.expect(
					ShopView.check("VipOffer", ctxAt(JOIN + 7 * DAY + 5)) == nil,
					"the comeback window"
				)
				H.expect(
					ShopView.check("VipOffer", ctxAt(JOIN + HOUR, { vipPass = true })) == "Owned",
					"VIP already"
				)
				H.expect(ShopView.check("Vip", joined) == nil, "VIP on sale")
				H.expect(
					ShopView.check("Vip", ctxAt(JOIN, { shop = newShop({ VipOffer = true }) }))
						== "Owned",
					"VIP through the offer owns the pass's perks"
				)
				H.expect(
					ShopView.check("QuickCases", ctxAt(JOIN, { fastOpen = true })) == "Owned",
					"Quick Cases owned"
				)
				H.expect(ShopView.check("QuickCases", joined) == nil, "Quick Cases on sale")
				H.expect(ShopView.check("StarterPack", joined) == nil, "the Starter Pack's week")
				H.expect(
					ShopView.check("StarterPack", ctxAt(JOIN + 7 * DAY)) == "Closed",
					"after 7 days"
				)
				H.expect(
					ShopView.check(
						"StarterPack",
						ctxAt(JOIN, { shop = newShop({ StarterBought = true }) })
					) == "Owned",
					"once"
				)
				H.expect(ShopView.check("MoneyParty", joined) == nil, "no party: room")
				H.expect(
					ShopView.check("MoneyParty", ctxAt(JOIN, { partyEndsAt = JOIN + HOUR }))
						== "PartyFull",
					"an hour queued"
				)
				H.expect(
					ShopView.check("MoneyParty", ctxAt(JOIN, { partyEndsAt = JOIN + 45 * 60 }))
						== nil,
					"room for 15 more minutes"
				)
				H.expect(
					ShopView.check("FoundersCue", ctxAt(now)) == nil,
					"the Founder's Cue on sale"
				)
				H.expect(
					ShopView.check("FoundersCue", ctxAt(start - 1)) == "Closed",
					"before it starts"
				)
				H.expect(
					ShopView.check("FoundersCue", ctxAt(start + founders.Seconds)) == "Closed",
					"never again once ended"
				)
				H.expect(
					ShopView.check(
						"FoundersCue",
						ctxAt(now, { sold = { FoundersCue = founders.Cap } })
					) == "SoldOut",
					"sold out at the cap"
				)
				H.expect(
					ShopView.check(
						"FoundersCue",
						ctxAt(now, { shop = newShop({ Limited = { FoundersCue = 7 } }) })
					) == "Owned",
					"one per player"
				)
			end)
		end)
	end,

	["ShopView.build: the ShopState payload"] = function()
		withLimiteds(function()
			local sale =
				ShopView.readSale({ Case = "Epic", Percent = 20, EndsAt = JOIN + DAY }, JOIN)
			withIds({ Pack2 = 11, Vip = 12 }, function()
				local now = JOIN + HOUR
				local p = ShopView.build(ctxAt(now, {
					prices = { Pack2 = 95 },
					partyEndsAt = now + 600,
					partyBuyer = "Painicane",
					sold = { BetaCue = 412 },
					shop = newShop({ Limited = { BetaCue = 412 } }),
					sale = sale,
				}))
				for _, key in Config.Products.PackOrder do
					H.expect(p.products[key] ~= nil, key .. " listed")
				end
				for _, key in { "VipOffer", "StarterPack", "MoneyParty", "Vip", "QuickCases" } do
					H.expect(p.products[key] ~= nil, key .. " listed")
				end
				local pack1, pack2 = p.products.Pack1, p.products.Pack2
				H.expect(
					pack1.robux == 49 and pack2.robux == 95,
					"Config's price, else the live one"
				)
				H.expect(
					not pack1.available and not pack1.canBuy and pack1.reason == "ComingSoon",
					"Id 0: coming soon"
				)
				H.expect(pack2.available and pack2.canBuy and pack2.reason == nil, "made: on sale")
				H.expect(pack1.money == 18000 and pack2.money == 39000, "the first pack doubled")
				H.expect(p.products.StarterPack.money == 75000, "the Starter Pack's $75,000")
				H.expect(p.products.Vip.kind == "Pass" and p.products.Vip.canBuy, "the VIP pass")
				H.expect(
					not p.products.Vip.owned and not p.products.QuickCases.owned,
					"nothing owned"
				)
				H.expect(
					p.products.MoneyParty.canBuy == false
						and p.products.MoneyParty.reason == "ComingSoon",
					"the party: room, but not made yet"
				)
				local welcome = p.offers.VipOffer
				H.expect(
					welcome.open and welcome.endsAt == JOIN + DAY and welcome.kind == "Welcome",
					"the welcome window"
				)
				local starter = p.offers.StarterPack
				H.expect(
					starter.open and starter.endsAt == JOIN + 7 * DAY,
					"the Starter Pack's week"
				)
				H.expect(
					p.party ~= nil and p.party.endsAt == now + 600 and p.party.buyer == "Painicane",
					"the party"
				)
				H.expect(
					p.sale ~= nil and p.sale.case == "Epic" and p.sale.percent == 20,
					"the sale"
				)
				local beta = nil
				for _, row in p.limited do
					if row.cue == "BetaCue" then
						beta = row
					end
				end
				H.expect(
					beta ~= nil and beta.price == 40000 and beta.cap == 1000,
					"the Beta Cue row"
				)
				H.expect(
					beta.owned and beta.copy == 412 and beta.sold == 412 and not beta.canBuy,
					"Owned #412"
				)
				H.expect(#p.limited == #Shop.limited(), "every Limited row, in shelf order")
				H.expect(
					not p.vip and not p.vipPass and not p.vipOffer and not p.fastOpen,
					"no VIP, no Fast Open"
				)
				H.expect(
					not p.firstPackBought and not p.starterBought and not p.restricted,
					"flags"
				)
			end)
		end)
	end,

	["ShopView.build: what the Shop tile's timer reads"] = function()
		H.expect(
			offerEndsAt(ShopView.build(ctxAt(JOIN + HOUR)), JOIN + HOUR) == JOIN + DAY,
			"welcome"
		)
		H.expect(
			offerEndsAt(ShopView.build(ctxAt(JOIN + 2 * DAY)), JOIN + 2 * DAY) == JOIN + 7 * DAY,
			"then the Starter Pack's week"
		)
		local comeback = ShopView.build(ctxAt(JOIN + 2 * DAY)).offers.VipOffer
		H.expect(
			not comeback.open
				and comeback.kind == "Comeback"
				and comeback.startsAt == JOIN + 7 * DAY,
			"the comeback still to come, closed"
		)
		H.expect(
			offerEndsAt(ShopView.build(ctxAt(JOIN + 7 * DAY + 60)), JOIN + 7 * DAY + 60)
				== JOIN + 8 * DAY,
			"the comeback window"
		)
		local vip = ctxAt(JOIN + HOUR, { vipPass = true, shop = newShop({ StarterBought = true }) })
		H.expect(offerEndsAt(ShopView.build(vip), JOIN + HOUR) == nil, "VIP, starter bought: none")
		local late = ShopView.build(ctxAt(JOIN + 9 * DAY)).offers.VipOffer
		H.expect(not late.open and late.endsAt == 0, "closed for good")
		H.expect(ShopView.build(ctxAt(JOIN, { partyEndsAt = JOIN })).party == nil, "an ended party")
	end,

	["ShopView.nextChange: when a window opens or closes by itself"] = function()
		-- The restock changes every Config.Shop.Restock.SlotSeconds on the clock.
		local slotSeconds = Config.Shop.Restock.SlotSeconds
		local function restockEnd(t: number): number
			return (t // slotSeconds + 1) * slotSeconds
		end
		local function expected(t: number, extra: number?): number?
			local offers = Shop.offers(newShop(), t, false)
			local found: number? = soonest(soonest(limitedBoundary(t), extra), restockEnd(t))
			for _, at in
				{
					offers.welcome.endsAt,
					offers.comeback.startsAt,
					offers.comeback.endsAt,
					offers.starter.endsAt,
				}
			do
				if at > t then
					found = soonest(found, at)
				end
			end
			return found
		end
		for _, t in { JOIN - HOUR, JOIN + HOUR, JOIN + 2 * DAY, JOIN + 7 * DAY + 1, JOIN + 9 * DAY } do
			H.expect(
				ShopView.nextChange(ctxAt(t)) == expected(t, nil),
				("at join %+d s"):format(t - JOIN)
			)
		end
		H.expect(
			ShopView.nextChange(ctxAt(JOIN + HOUR)) == JOIN + HOUR + slotSeconds,
			"the next restock comes first"
		)
		-- The party ends, and makes room for another 15 minutes before that.
		local t = JOIN + 9 * DAY
		H.expect(
			ShopView.nextChange(ctxAt(t, { partyEndsAt = t + HOUR })) == expected(t, t + 15 * 60),
			"an hour queued: room again in 15 minutes"
		)
		H.expect(
			ShopView.nextChange(ctxAt(t, { partyEndsAt = t + 60 })) == expected(t, t + 60),
			"the party's end"
		)
		H.expect(
			ShopView.nextChange(
				ctxAt(t, { sale = { case = "Epic", percent = 20, endsAt = t + 30 } })
			) == t + 30,
			"the sale's end"
		)
		local far = JOIN + 4000 * DAY
		H.expect(
			ShopView.nextChange(ctxAt(far)) == soonest(limitedBoundary(far), restockEnd(far)),
			"nothing left but Limiteds and the restock"
		)
		H.expect(
			ShopView.nextChange(ctxAt(far, { shop = newShop({ FirstJoin = 0 }) }))
				== soonest(limitedBoundary(far), restockEnd(far)),
			"an unknown first join has no windows"
		)
	end,

	["ShopView.readSale: only a real, running sale"] = function()
		local now = JOIN
		local sale = ShopView.readSale({ Case = "Rare", Percent = 25, EndsAt = now + 60 }, now)
		H.expect(
			sale ~= nil and sale.case == "Rare" and sale.percent == 25 and sale.endsAt == now + 60,
			"Config's spelling"
		)
		H.expect(
			ShopView.readSale({ case = "Epic", percent = 10, endsAt = now + 1 }, now) ~= nil,
			"the payload's spelling"
		)
		H.expect(ShopView.readSale(Config.Cases.Sale, now) == nil, "Config's default: no sale")
		H.expect(
			ShopView.readSale({ Case = "NoSuchCase", Percent = 25, EndsAt = now + 60 }, now) == nil,
			"an unknown case"
		)
		H.expect(
			ShopView.readSale({ Case = "Rare", Percent = 0, EndsAt = now + 60 }, now) == nil,
			"0% off"
		)
		H.expect(
			ShopView.readSale({ Case = "Rare", Percent = 100, EndsAt = now + 60 }, now) == nil,
			"free is no sale"
		)
		H.expect(
			ShopView.readSale({ Case = "Rare", Percent = 25, EndsAt = now }, now) == nil,
			"ended"
		)
		H.expect(
			ShopView.readSale(nil, now) == nil and ShopView.readSale("Rare", now) == nil,
			"not a table"
		)
		local max = Config.Cases.MaxSalePercent
		H.expect(max == 50, "at most 50% off")
		H.expect(
			ShopView.readSale({ Case = "Rare", Percent = max, EndsAt = now + 60 }, now) ~= nil,
			"the max is a sale"
		)
		H.expect(
			ShopView.readSale({ Case = "Rare", Percent = max + 1, EndsAt = now + 60 }, now) == nil,
			"past the max is no sale"
		)
	end,

	["the Dashboard list: 4 game passes and 24 developer products at the plan's prices"] = function()
		local want = {
			Vip = 599,
			QuickCases = 299,
			UltSlot2 = 59,
			UltSlot3 = 99,
			VipOffer = 299,
			StarterPack = 99,
			Pack1 = 49,
			Pack2 = 99,
			Pack3 = 249,
			Pack4 = 499,
			Pack5 = 999,
			Pack6 = 2499,
			Pack7 = 4999,
			Mystery1 = 25,
			Mystery10 = 229,
			RestockEpic = 999,
			RestockLegendary = 4999,
			Skip1h = 15,
			Skip6h = 49,
			Skip24h = 99,
			Skip48h = 149,
			MoneyParty = 199,
			Spin1 = 15,
			Spin5 = 50,
			Spin10 = 100,
			Spin50 = 449,
			Lucky1 = 49,
			Lucky3 = 129,
		}
		local passes, products = 0, 0
		for key, robux in want do
			local row = Shop.product(key)
			H.expect(row ~= nil and row.Robux == robux, key .. " costs " .. robux)
			if row.Kind == "Pass" then
				passes += 1
			else
				products += 1
			end
		end
		H.expect(
			passes == 4 and products == 24,
			("%d passes, %d products"):format(passes, products)
		)
		H.expect(Shop.product("FastOpen") == nil, "Fast Open is Quick Cases now")
		H.expect(Config.Products.BestValue == "Pack6", "Best value")
		for _, key in { "Mystery1", "RestockEpic", "Skip48h", "Spin1", "Lucky3" } do
			H.expect(Shop.isRandom(key), key .. " is a paid random item")
		end
		for _, key in { "Pack1", "Vip", "QuickCases", "StarterPack", "MoneyParty" } do
			H.expect(not Shop.isRandom(key), key .. " is not random")
		end
	end,

	["Mystery Cases grant paid Case Drops; the Starter Pack adds an hour of 2x money"] = function()
		local one = Shop.grantFor("Mystery1", newShop(), JOIN, false)
		local ten = Shop.grantFor("Mystery10", newShop(), JOIN, false)
		H.expect(one.drops == 1 and one.money == 0 and ten.drops == 10, "Case Drops")
		local shop = newShop()
		local starter = Shop.grantFor("StarterPack", shop, JOIN, false)
		H.expect(starter.boostEnds == JOIN + Config.Shop.StarterBoostSeconds, "an hour from now")
		Shop.markGrant(shop, starter)
		H.expect(shop.BoostEnds == JOIN + 3600, "marked")
		-- A later grant never shortens it.
		Shop.markGrant(shop, { key = "x", money = 0, boostEnds = JOIN + 10 })
		H.expect(shop.BoostEnds == JOIN + 3600, "kept")
	end,

	["paid random items are refused where restricted; the page order and Roblox Plus"] = function()
		withIds(
			{ Mystery1 = 21, Mystery10 = 22, Pack1 = 23, RestockEpic = 24, Skip1h = 25 },
			function()
				local now = JOIN + HOUR
				H.expect(ShopView.check("Mystery1", ctxAt(now)) == nil, "on sale")
				H.expect(
					ShopView.check("Mystery10", ctxAt(now, { restricted = true })) == "Restricted",
					"restricted"
				)
				H.expect(
					ShopView.check("Mystery1", ctxAt(now, { policyKnown = false })) == "NotLoaded",
					"policy not known yet"
				)
				H.expect(ShopView.check("Pack1", ctxAt(now, { restricted = true })) == nil, "money")
				-- RestockEpic sells only in a restock whose lucky slot is the Epic Case.
				local Restock = H.require("Progression.Restock")
				local epicSlot = 0
				while Restock.find(epicSlot, "Epic") == nil do
					epicSlot += 1
				end
				local epicAt = epicSlot * Config.Shop.Restock.SlotSeconds
				H.expect(ShopView.check("RestockEpic", ctxAt(epicAt)) == nil, "in this restock")
				H.expect(
					ShopView.check(
						"RestockEpic",
						ctxAt(epicAt, { restock = { Slot = epicSlot, Bought = { Epic = 1 } } })
					) == "SoldOut",
					"one per player"
				)
				local plainSlot = 0
				while Restock.find(plainSlot, "Epic") ~= nil do
					plainSlot += 1
				end
				H.expect(
					ShopView.check(
						"RestockEpic",
						ctxAt(plainSlot * Config.Shop.Restock.SlotSeconds)
					) == "NotSold",
					"not in this restock"
				)
				H.expect(ShopView.check("Skip1h", ctxAt(now)) == nil, "a skip passes the check")
				local p = ShopView.build(ctxAt(now))
				H.expect(
					table.concat(p.order, " ") == table.concat(Config.Shop.Order, " "),
					"order"
				)
				H.expect(p.order[1] == "Offer" and p.order[#p.order] == "RobloxPlus", "top, bottom")
				H.expect(p.robloxPlus == true and p.bestValue == "Pack6" and #p.packs == 7, "rest")
				-- A /restock forced restock shows its items on the real restock's countdown.
				local forced = ShopView.build(ctxAt(now, { restockSlot = epicSlot }))
				local _, realEnd = Restock.window(Restock.slotOf(now))
				H.expect(forced.restock.slot == epicSlot, "the forced items")
				H.expect(forced.restock.endsAt == realEnd, "the real countdown")
			end
		)
	end,

	["ShopView.build: a product not for this player shows no money"] = function()
		local now = JOIN + HOUR
		local vip = ShopView.build(ctxAt(now, { vipPass = true }))
		H.expect(vip.products.VipOffer.money == 0, "VIP: the offer gives nothing more")
		local bought = ShopView.build(ctxAt(now, { shop = newShop({ StarterBought = true }) }))
		H.expect(bought.products.StarterPack.money == 0, "the Starter Pack bought")
		H.expect(bought.products.Pack1.money == 18000, "the packs as before")
		local fresh = ShopView.build(ctxAt(now))
		H.expect(fresh.products.StarterPack.money == 75000, "on offer: its $75,000")
	end,
}
