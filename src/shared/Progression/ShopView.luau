--!strict
-- ShopView: what one player's shop looks like right now, as plain data (the ShopState payload,
-- src/shared/Net.luau), and the check behind every StoreRequest "Buy" (ECONOMY sections 9 and
-- 11; the overnight brief's section 12). Pure: no Instances, no Roblox APIs, no clocks (the
-- caller passes the unix time and everything it knows), no randomness, and every loop walks an
-- array (the sorted product keys, the Limited rows), so nothing depends on hash order.
--
-- src/server/Store.luau gathers a Context (the save's Shop table, pass ownership, this
-- server's Money Party, the case sale, the Limited counts, the live Robux prices), sends
-- ShopView.build's payload, asks ShopView.check before it prompts a purchase, and re-sends
-- the payload at ShopView.nextChange, when a window opens or closes by itself.
local Config = require(script.Parent.Parent.Config)
local Shop = require(script.Parent.Shop)
local Restock = require(script.Parent.Restock)
local CaseDrop = require(script.Parent.CaseDrop)

local S = Config.Shop
local LIST: { [string]: { Kind: string, Id: number, Robux: number, Restock: string?, SkipSeconds: number?, SaleOf: string?, Vip: boolean? } } =
	Config.Products.List :: any
local CASE_ORDER: { string } = Config.Cases.Order
local MAX_SALE: number = Config.Cases.MaxSalePercent

-- A timed sale on one case type (ECONOMY 9.1).
export type Sale = { case: string, percent: number, endsAt: number }

-- Everything the server knows about one player's shop at unix time `now`.
export type Context = {
	now: number,
	shop: Shop.ShopSave, -- the save's Shop table (a read-only copy is fine)
	vipPass: boolean, -- owns the VIP game pass (or the /vip dev override)
	fastOpen: boolean, -- owns the Quick Cases game pass (or /fastopen)
	restricted: boolean, -- the PaidRandomRestricted attribute (PolicyService)
	-- false while PolicyService has not answered for this player (nil counts as answered)
	policyKnown: boolean?,
	-- false while the ult spin screen is closed to this player (Config.Ults.ScreenLive)
	spinsLive: boolean?,
	partyEndsAt: number, -- this server's Money Party end, unix (0: none)
	partyBuyer: string?, -- the last buyer's username
	sale: Sale?, -- the case sale running now (ShopView.readSale), or nil
	sold: { [string]: number }, -- Limited cue id -> copies sold (missing: unknown)
	prices: { [string]: number }, -- product key -> live Robux price (missing: Config's)
	-- Other game passes owned (the ult slots UltSlot2, UltSlot3), by product key; nil: none.
	passes: { [string]: boolean }?,
	restock: any?, -- the save's Shop.Restock (nil: nothing bought)
	drops: any?, -- the save's Drops (the pity counters; nil: none yet)
	stockTaken: number?, -- this restock's Legendary units taken everywhere (nil: unknown)
	restockSlot: number?, -- the restock shown (nil: the one at `now`; /restock forces one)
}

-- The restock shown, timed by the real restock's window (a /restock forced one is shown only
-- until the real one ends, so its countdown is the real one's too).
local function restockView(ctx: Context, vip: boolean): any
	local view =
		Restock.view(ctx.restockSlot or Restock.slotOf(ctx.now), ctx.restock, vip, ctx.stockTaken)
	view.startsAt, view.endsAt = Restock.window(Restock.slotOf(ctx.now))
	return view
end

-- One timed offer as the client reads it (ItemState.offerEndsAt reads `open` and `endsAt`).
export type OfferView = {
	open: boolean,
	startsAt: number,
	endsAt: number,
	kind: string?, -- VipOffer only: "Welcome" or "Comeback"
}

export type ProductView = {
	kind: string, -- "Product" (developer product) or "Pass" (game pass)
	robux: number, -- the live price once known, else Config's fallback
	available: boolean, -- made in Creator Hub (its Id is set); false: "Coming soon"
	owned: boolean, -- a pass owned, VIP already (VipOffer), bought (StarterPack, a Limited)
	canBuy: boolean, -- a "Buy" now would prompt (ShopView.check found nothing against it)
	reason: string?, -- why not, when canBuy is false (ShopView.check's reason)
	-- The money one purchase gives now (a first pack doubled); 0 for none, and 0 for a product
	-- that is not for this player now (a receipt for it pays Shop.fallbackMoney instead).
	money: number,
}

export type LimitedView = {
	cue: string,
	product: string?, -- the Config.Products key of a Robux Limited
	price: number?, -- the money price of a money Limited
	cap: number?, -- copies at most (nil: no cap)
	sold: number?, -- copies sold everywhere (nil: not read yet)
	startsAt: number,
	endsAt: number,
	open: boolean, -- on sale now: started, not ended, not sold out
	soldOut: boolean,
	owned: boolean,
	copy: number?, -- this player's copy number (#412) once owned
	canBuy: boolean, -- open and not owned (a Robux one also needs products[product].available)
}

export type PartyView = { endsAt: number, buyer: string? }

export type Payload = {
	vip: boolean,
	vipPass: boolean,
	vipOffer: boolean,
	fastOpen: boolean,
	restricted: boolean,
	firstPackBought: boolean,
	starterBought: boolean,
	offers: { [string]: OfferView },
	party: PartyView?,
	sale: Sale?,
	limited: { LimitedView },
	products: { [string]: ProductView },
	order: { string }, -- the shop page's sections, top to bottom (Config.Shop.Order)
	restock: any, -- Restock.view: this restock's items, this player's stock left, its end
	mystery: { price: number, bulkCount: number, bulkPrice: number }, -- money prices
	skip: { moneyPerMinute: number, minMoney: number }, -- the money price of a timer skip
	pity: { rare: number, epic: number }, -- Case Drops until a Rare / Epic is guaranteed
	robloxPlus: boolean, -- show the Get Roblox Plus button (StoreRequest "RobloxPlus")
	bestValue: string, -- the money pack marked "Best value"
	packs: { string }, -- the money packs in shop order
	releaseSale: Shop.SaleWindow, -- the release sale: its window and which products it swaps in
}

-- The products whose purchase depends on more than their Id (ECONOMY 11.2-11.5).
local VIP_PASS = "Vip"
local FAST_OPEN = "QuickCases"
local VIP_OFFER = "VipOffer"
local STARTER_PACK = "StarterPack"
local MONEY_PARTY = "MoneyParty"

-- The ult spin products (ECONOMY 11.8): closed while the spin screen is (spinsLive). Every
-- paid random item (Shop.isRandom) is refused where PolicyService restricts them.
local SPIN_PRODUCTS: { [string]: boolean } = {}
for _, key in Config.Ults.Earn.RobuxPacks do
	SPIN_PRODUCTS[key] = true
end
for _, key in Config.Ults.Earn.LuckyPacks do
	SPIN_PRODUCTS[key] = true
end

-- Every product key, sorted, so building the payload always walks the same order.
local KEYS: { string } = {}
for key in LIST do
	table.insert(KEYS, key)
end
table.sort(KEYS)

local ShopView = {}

-- A finite whole number, else 0.
local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return math.floor(x)
end

-- The Limited shelf row sold as developer product `key`, or nil.
local function limitedRow(key: string): Shop.LimitedRow?
	for _, row in Shop.limited() do
		if row.Product == key then
			return row
		end
	end
	return nil
end

-- Whether a pass other than Vip and QuickCases (an ult slot) is owned.
local function otherPassOwned(ctx: Context, key: string): boolean
	local passes = ctx.passes
	return type(passes) == "table" and passes[key] == true
end

--- Whether product `key` is an ult spin pack (spins or Lucky Spins: a paid random item).
function ShopView.isSpinProduct(key: string): boolean
	return SPIN_PRODUCTS[key] == true
end

local function limitedOwned(ctx: Context, cueId: string): boolean
	local owned = ctx.shop.Limited
	return type(owned) == "table" and owned[cueId] ~= nil
end

local function limitedState(ctx: Context, row: Shop.LimitedRow): Shop.LimitedState
	return Shop.limitedState(row, ctx.now, ctx.sold[row.Cue], limitedOwned(ctx, row.Cue))
end

--- VIP = owns the pass OR bought the welcome offer (11.3).
function ShopView.isVip(ctx: Context): boolean
	return Shop.isVip(ctx.vipPass, ctx.shop)
end

--- The case sale in `raw` if one is really running at `now`: a known case id, a percent above
--- 0 and at most Config.Cases.MaxSalePercent, an end still ahead. Reads { Case, Percent,
--- EndsAt } (Config's spelling) or { case, percent, endsAt }. nil for anything else, so a
--- stale or broken sale is never shown (ECONOMY 9.1: a true countdown or no sale).
function ShopView.readSale(raw: any, now: number): Sale?
	if type(raw) ~= "table" then
		return nil
	end
	local caseId = raw.case or raw.Case
	local percent = raw.percent or raw.Percent
	local endsAt = raw.endsAt or raw.EndsAt
	if type(caseId) ~= "string" or table.find(CASE_ORDER, caseId) == nil then
		return nil
	end
	if type(percent) ~= "number" or not (percent > 0 and percent <= MAX_SALE) then
		return nil
	end
	if type(endsAt) ~= "number" or endsAt ~= endsAt or endsAt <= now then
		return nil
	end
	return { case = caseId, percent = percent, endsAt = whole(endsAt) }
end

--- Why a StoreRequest "Buy" of `key` must not prompt now, or nil when it may: "BadRequest"
--- (not a Config.Products key), "Owned" (a pass owned; VIP already, for the welcome offer; the
--- Starter Pack or a Limited bought), "Closed" (its offer or Limited window is not open),
--- "SoldOut" (a Limited at its cap), "PartyFull" (the Money Party already has an hour queued),
--- "Restricted" (an ult spin pack where paid random items are restricted), "NotLoaded" (a spin
--- pack before PolicyService has answered), "ComingSoon" (its Id is still 0, or a spin pack
--- while the spin screen is closed). Money packs are always on sale.
function ShopView.check(key: string, ctx: Context): string?
	local row = LIST[key]
	if row == nil then
		return "BadRequest"
	end
	local vip = ShopView.isVip(ctx)
	-- A release-sale product (Config.Shop.ReleaseSale) only inside its window; its VIP not
	-- for a VIP. The checks below then run as for any product (Mystery10Sale is random).
	if row.SaleOf ~= nil then
		if not Shop.releaseSale(ctx.now).open then
			return "Closed"
		elseif row.Vip == true and vip then
			return "Owned"
		end
	end
	if key == VIP_PASS then
		if vip then
			return "Owned"
		end
	elseif key == FAST_OPEN then
		if ctx.fastOpen then
			return "Owned"
		end
	elseif key == VIP_OFFER then
		if vip then
			return "Owned"
		end
		local offers = Shop.offers(ctx.shop, ctx.now, vip)
		if not (offers.welcome.open or offers.comeback.open) then
			return "Closed"
		end
	elseif key == STARTER_PACK then
		if ctx.shop.StarterBought == true then
			return "Owned"
		end
		if not Shop.offers(ctx.shop, ctx.now, vip).starter.open then
			return "Closed"
		end
	elseif key == MONEY_PARTY then
		if not Shop.canQueueParty(ctx.partyEndsAt, ctx.now) then
			return "PartyFull"
		end
	elseif Shop.isRandom(key) then
		if ctx.policyKnown == false then
			return "NotLoaded"
		elseif ctx.restricted then
			return "Restricted"
		elseif SPIN_PRODUCTS[key] and ctx.spinsLive == false then
			return "ComingSoon"
		elseif row.Restock ~= nil then
			-- In this restock, within this player's stock, and the Legendary's global stock.
			local slot = ctx.restockSlot or Restock.slotOf(ctx.now)
			local item = Restock.forProduct(slot, key)
			local why = Restock.check(item, ctx.restock, slot, vip)
			if why ~= nil then
				return why
			elseif
				item ~= nil
				and item.global ~= nil
				and ctx.stockTaken ~= nil
				and ctx.stockTaken >= item.global
			then
				return "SoldOut"
			end
		end
	elseif row.Kind == "Pass" then
		if otherPassOwned(ctx, key) then
			return "Owned"
		end
	end
	local limited = limitedRow(key)
	if limited ~= nil then
		local state = limitedState(ctx, limited)
		if state.owned then
			return "Owned"
		elseif state.soldOut then
			return "SoldOut"
		elseif not state.open then
			return "Closed"
		end
	end
	if not Shop.available(key) then
		return "ComingSoon"
	end
	return nil
end

-- The VIP welcome offer's window as one offer: the welcome window while open, else the
-- comeback window while open or still to come (and not VIP), else closed.
local function vipOffer(ctx: Context, vip: boolean): OfferView
	local offers = Shop.offers(ctx.shop, ctx.now, vip)
	local welcome, comeback = offers.welcome, offers.comeback
	if welcome.open then
		return {
			open = true,
			startsAt = welcome.startsAt,
			endsAt = welcome.endsAt,
			kind = "Welcome",
		}
	end
	if comeback.open or (not vip and comeback.startsAt > ctx.now) then
		return {
			open = comeback.open,
			startsAt = comeback.startsAt,
			endsAt = comeback.endsAt,
			kind = "Comeback",
		}
	end
	return { open = false, startsAt = 0, endsAt = 0, kind = "Welcome" }
end

--- The ShopState payload for one player (its shape is written in Net.luau, ShopState).
function ShopView.build(ctx: Context): Payload
	local shop = ctx.shop
	local vip = ShopView.isVip(ctx)
	local starter = Shop.offers(shop, ctx.now, vip).starter

	local products: { [string]: ProductView } = {}
	for _, key in KEYS do
		local row = LIST[key]
		local reason = ShopView.check(key, ctx)
		local grant: Shop.Grant?, notFor: string? = nil, nil
		if row.Kind == "Product" then
			grant, notFor = Shop.grantFor(key, shop, ctx.now, ctx.vipPass == true)
		end
		local limited = limitedRow(key)
		local owned = false
		if key == VIP_PASS or key == VIP_OFFER or row.Vip == true then
			owned = vip
		elseif key == FAST_OPEN then
			owned = ctx.fastOpen
		elseif key == STARTER_PACK then
			owned = shop.StarterBought == true
		elseif limited ~= nil then
			owned = limitedOwned(ctx, limited.Cue)
		elseif row.Kind == "Pass" then
			owned = otherPassOwned(ctx, key)
		end
		local price = ctx.prices[key]
		products[key] = {
			kind = row.Kind,
			robux = if type(price) == "number" and price > 0
				then whole(price)
				else whole(row.Robux),
			available = Shop.available(key),
			owned = owned,
			canBuy = reason == nil,
			reason = reason,
			money = if grant ~= nil and notFor == nil then grant.money else 0,
		}
	end

	local limited: { LimitedView } = {}
	for _, row in Shop.limited() do
		local state = limitedState(ctx, row)
		local owned = shop.Limited
		local copy = if type(owned) == "table" then owned[row.Cue] else nil
		table.insert(limited, {
			cue = row.Cue,
			product = row.Product,
			price = row.Price,
			cap = row.Cap,
			sold = ctx.sold[row.Cue],
			startsAt = state.startsAt,
			endsAt = state.endsAt,
			open = state.open,
			soldOut = state.soldOut,
			owned = state.owned,
			copy = if type(copy) == "number" then copy else nil,
			canBuy = state.canBuy,
		})
	end

	local party: PartyView? = nil
	if ctx.partyEndsAt > ctx.now then
		party = { endsAt = ctx.partyEndsAt, buyer = ctx.partyBuyer }
	end

	return {
		vip = vip,
		vipPass = ctx.vipPass == true,
		vipOffer = shop.VipOffer == true,
		fastOpen = ctx.fastOpen == true,
		restricted = ctx.restricted == true,
		firstPackBought = shop.FirstPackBought == true,
		starterBought = shop.StarterBought == true,
		offers = {
			[VIP_OFFER] = vipOffer(ctx, vip),
			[STARTER_PACK] = {
				open = starter.open,
				startsAt = starter.startsAt,
				endsAt = starter.endsAt,
			},
		},
		party = party,
		sale = ctx.sale,
		limited = limited,
		products = products,
		order = table.clone(S.Order),
		restock = restockView(ctx, vip),
		mystery = {
			price = S.Mystery.Price,
			bulkCount = S.Mystery.BulkCount,
			bulkPrice = S.Mystery.BulkPrice,
		},
		skip = { moneyPerMinute = S.Skip.MoneyPerMinute, minMoney = S.Skip.MinMoney },
		pity = CaseDrop.pityLeft(CaseDrop.readPity(ctx.drops)),
		robloxPlus = S.RobloxPlus == true,
		releaseSale = Shop.releaseSale(ctx.now),
		bestValue = Config.Products.BestValue,
		packs = table.clone(Config.Products.PackOrder),
	}
end

--- The next unix time after `now` at which this player's shop changes by itself (an offer
--- window, a Limited or the sale opening or closing, the Money Party ending or making room
--- for another purchase), or nil when nothing is due. The server re-sends ShopState then.
function ShopView.nextChange(ctx: Context): number?
	local now = ctx.now
	local soonest: number? = nil
	local function consider(at: number)
		if at > now and (soonest == nil or at < soonest) then
			soonest = at
		end
	end
	if whole(ctx.shop.FirstJoin) > 0 then
		local offers = Shop.offers(ctx.shop, now, ShopView.isVip(ctx))
		consider(offers.welcome.endsAt)
		consider(offers.comeback.startsAt)
		consider(offers.comeback.endsAt)
		consider(offers.starter.endsAt)
	end
	for _, row in Shop.limited() do
		local state = limitedState(ctx, row)
		consider(state.startsAt)
		consider(state.endsAt)
	end
	local _, restockEnds = Restock.window(Restock.slotOf(now))
	consider(restockEnds)
	if ctx.partyEndsAt > now then
		consider(ctx.partyEndsAt)
		-- canQueueParty turns true again once less than PartyMax - PartySeconds is queued.
		consider(ctx.partyEndsAt + S.PartySeconds - S.PartyMaxSeconds)
	end
	if ctx.sale ~= nil then
		consider(ctx.sale.endsAt)
	end
	local release = Shop.releaseSale(now)
	consider(release.startsAt)
	consider(release.endsAt)
	return soonest
end

return ShopView
