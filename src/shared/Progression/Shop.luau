--!strict
-- The shop's rules (ECONOMY sections 9 and 11; the overnight brief's section 12): the timed
-- offer windows, VIP, the Robux products and what each purchase gives, the Money Party queue,
-- the Limited shelf's state, and the once-only handling of developer product receipts. Pure:
-- no Instances, no Roblox APIs, no clocks (the caller passes the unix time), no randomness,
-- and every loop walks an array (the sorted product keys, PackOrder, the Limited rows), so
-- nothing depends on hash order.
--
-- src/server/Store.luau owns MarketplaceService and the save; it hands its real functions to
-- Shop.processReceipt (so Lune tests the once-only logic with fakes) and maps the answer to
-- Enum.ProductPurchaseDecision.
--
-- Who changes what: offers, grantFor, packs and the state functions change nothing.
-- markGrant and recordPurchase change the Shop save table they are given: the server calls
-- them on the live save inside the ONE mutation that also adds the grant's money and cue.
local Config = require(script.Parent.Parent.Config)

local S = Config.Shop
local P = Config.Products

-- The save's Shop table (SaveSchema v2).
export type ShopSave = {
	FirstJoin: number, -- unix time of the first join; 0 unknown
	VipOffer: boolean, -- bought the VIP welcome offer (VIP for good)
	VipCueGiven: boolean,
	StarterBought: boolean,
	FirstPackBought: boolean,
	Purchases: { string }, -- the last RecentPurchases receipt ids, oldest first
	Limited: { [string]: number }, -- Limited cue id -> its copy number
}

-- A timed offer: open now, and its real start and end (unix seconds; 0 when unknown).
export type Window = { open: boolean, startsAt: number, endsAt: number }

export type Offers = { welcome: Window, comeback: Window, starter: Window }

export type Pack = { key: string, robux: number, money: number, bonus: number }

-- What one developer product purchase gives, as plain data. The server applies all of it in
-- ONE save mutation together with Shop.recordPurchase: money and cue to the player, the Shop
-- flags through Shop.markGrant, party to this server's Money Party, limited through the
-- Limited copy counter.
export type Grant = {
	key: string, -- the Config.Products key bought
	money: number, -- money to add (0 for none)
	cue: string?, -- a cue to add: the Starter Cue, or the VIP Cue the first time
	vip: boolean?, -- VIP from the welcome offer (sets Shop.VipOffer)
	vipCue: boolean?, -- cue is the VIP Cue (sets Shop.VipCueGiven)
	party: boolean?, -- start or extend this server's Money Party (Shop.partyEndsAt)
	limited: string?, -- a Limited cue id to number and give (a Robux Limited)
	firstPack: boolean?, -- this pack paid FirstPackMultiplier (sets Shop.FirstPackBought)
	starterBought: boolean?, -- sets Shop.StarterBought
}

export type LimitedRow = {
	Cue: string,
	Price: number?, -- money; nil for a Robux one
	Product: string?, -- a Config.Products key for a Robux one
	Cap: number?, -- copies at most; nil for no cap
	StartsAt: number,
	Seconds: number,
}

export type LimitedState = {
	open: boolean, -- on sale now: started, not ended, not sold out
	startsAt: number,
	endsAt: number,
	soldOut: boolean,
	owned: boolean,
	canBuy: boolean, -- open and this player has none yet (one per player)
}

export type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

export type Decision = "Granted" | "NotProcessedYet"

-- What processReceipt needs from the server. Any of them may yield or throw.
export type ReceiptDeps = {
	keyForId: (number) -> string?, -- a developer product id -> its Config.Products key
	findPlayer: (number) -> any?, -- the Player with this UserId in this server, or nil
	isLoaded: (any) -> boolean, -- their save is loaded
	hasPurchase: (any, string) -> boolean, -- the purchase id is in their save's Purchases
	grant: (any, string, string) -> boolean, -- grants AND records the id in one save mutation
	save: (any) -> boolean, -- asks the DataStore to save and waits (with a timeout)
	log: ((string) -> ())?,
}

type ProductRow = { Kind: string, Id: number, Robux: number, Money: number?, Bonus: number? }

local LIST: { [string]: ProductRow } = P.List :: any
local PACK_ORDER: { string } = P.PackOrder
local LIMITED: { LimitedRow } = S.Limited :: any

-- The products whose grant is more than their Money (ECONOMY 11.3-11.5).
local VIP_OFFER = "VipOffer"
local STARTER_PACK = "StarterPack"
local MONEY_PARTY = "MoneyParty"

local GRANTED: Decision = "Granted"
local NOT_YET: Decision = "NotProcessedYet"

-- Every product key, sorted, so an id lookup always walks the same order.
local KEYS: { string } = {}
for key in LIST do
	table.insert(KEYS, key)
end
table.sort(KEYS)

local Shop = {}

-- A finite whole number, else 0.
local function whole(x: any): number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		return 0
	end
	return math.floor(x)
end

---------------------------------------------------------------------------------------------
-- Offer windows (11.3, 11.4) and VIP (11.2)
---------------------------------------------------------------------------------------------

local function closed(): Window
	return { open = false, startsAt = 0, endsAt = 0 }
end

--- The timed offers at unix time `now`, from the save's first join. Every window is a real
--- countdown from saved times that never restarts: the welcome offer for WelcomeSeconds from
--- the first join, one comeback window of ComebackSeconds opening ComebackAfterSeconds after
--- it (then never again), neither while the player is VIP; the Starter Pack for
--- StarterSeconds, until bought. FirstJoin 0 (unknown) keeps them all closed.
function Shop.offers(shopSave: ShopSave, now: number, isVip: boolean): Offers
	local first = whole(shopSave.FirstJoin)
	if first <= 0 then
		return { welcome = closed(), comeback = closed(), starter = closed() }
	end
	-- The welcome and starter windows open at the first join itself; `now` a moment before it
	-- (another server's clock) still counts as inside.
	local welcomeEnds = first + S.WelcomeSeconds
	local comebackStarts = first + S.ComebackAfterSeconds
	local comebackEnds = comebackStarts + S.ComebackSeconds
	local starterEnds = first + S.StarterSeconds
	return {
		welcome = {
			open = not isVip and now < welcomeEnds,
			startsAt = first,
			endsAt = welcomeEnds,
		},
		comeback = {
			open = not isVip and now >= comebackStarts and now < comebackEnds,
			startsAt = comebackStarts,
			endsAt = comebackEnds,
		},
		starter = {
			open = shopSave.StarterBought ~= true and now < starterEnds,
			startsAt = first,
			endsAt = starterEnds,
		},
	}
end

--- VIP = owns the game pass OR bought the welcome offer (11.3).
function Shop.isVip(ownsPass: boolean, shopSave: ShopSave?): boolean
	return ownsPass == true or (shopSave ~= nil and shopSave.VipOffer == true)
end

--- Whether a VIP still has the VIP Cue to receive (given once, however VIP came).
function Shop.vipCueDue(isVip: boolean, shopSave: ShopSave): boolean
	return isVip and shopSave.VipCueGiven ~= true
end

---------------------------------------------------------------------------------------------
-- Products (Config.Products)
---------------------------------------------------------------------------------------------

--- The Config.Products row for a key, or nil.
function Shop.product(key: string): ProductRow?
	return LIST[key]
end

local function keyFor(id: any, kind: string): string?
	-- Id 0 is every product not made in Creator Hub yet, so it never matches.
	if type(id) ~= "number" or id == 0 then
		return nil
	end
	for _, key in KEYS do
		local row = LIST[key]
		if row.Kind == kind and row.Id == id then
			return key
		end
	end
	return nil
end

--- The key of the developer product with this id (receipts), or nil. Passes never match.
function Shop.keyForId(productId: number): string?
	return keyFor(productId, "Product")
end

--- The key of the game pass with this id, or nil.
function Shop.passKeyForId(passId: number): string?
	return keyFor(passId, "Pass")
end

--- Whether a product or pass exists in Creator Hub yet (its Id is set). While not, the shop
--- says "Coming soon" and prompts nothing.
function Shop.available(key: string): boolean
	local row = LIST[key]
	return row ~= nil and whole(row.Id) > 0
end

--- The money packs in shop order (11.1).
function Shop.packs(): { Pack }
	local list: { Pack } = {}
	for _, key in PACK_ORDER do
		local row = LIST[key]
		if row ~= nil then
			table.insert(list, {
				key = key,
				robux = whole(row.Robux),
				money = whole(row.Money),
				bonus = whole(row.Bonus),
			})
		end
	end
	return list
end

--- The pack the "Need $X more" button highlights: the smallest that covers `gap` (counting the
--- first purchase double while it is unused), else the biggest. nil when nothing is missing.
function Shop.packForGap(gap: number, firstPackBought: boolean): string?
	if whole(gap) <= 0 then
		return nil
	end
	local multiplier = if firstPackBought then 1 else S.FirstPackMultiplier
	local biggest: string? = nil
	for _, pack in Shop.packs() do
		biggest = pack.key
		if pack.money * multiplier >= gap then
			return pack.key
		end
	end
	return biggest
end

local function limitedForProduct(key: string): LimitedRow?
	for _, row in LIMITED do
		if row.Product == key then
			return row
		end
	end
	return nil
end

--- What buying developer product `key` gives this player now, or nil for a pass, an unknown
--- key, or a product that would give nothing (a receipt for it is left NotProcessedYet and
--- logged instead of taking Robux for nothing). It never refuses a real product because an
--- offer's window closed or it was bought before: a receipt is Robux already paid, and the
--- windows only gate the prompt. `_now` is kept for callers; nothing here depends on it yet.
function Shop.grantFor(key: string, shopSave: ShopSave, _now: number): Grant?
	local row = LIST[key]
	if row == nil or row.Kind ~= "Product" then
		return nil
	end
	local grant: Grant = { key = key, money = math.max(0, whole(row.Money)) }
	-- The first money pack ever pays FirstPackMultiplier times its money, once (11.1).
	if
		grant.money > 0
		and table.find(PACK_ORDER, key) ~= nil
		and shopSave.FirstPackBought ~= true
	then
		grant.money *= S.FirstPackMultiplier
		grant.firstPack = true
	end
	if key == VIP_OFFER then
		grant.vip = true
		if shopSave.VipCueGiven ~= true then
			grant.cue = S.VipCue
			grant.vipCue = true
		end
	elseif key == STARTER_PACK then
		grant.money += S.StarterMoney
		grant.cue = S.StarterCue
		grant.starterBought = true
	elseif key == MONEY_PARTY then
		grant.party = true
	end
	local limited = limitedForProduct(key)
	if limited ~= nil then
		grant.limited = limited.Cue
	end
	if
		grant.money <= 0
		and grant.cue == nil
		and not grant.vip
		and not grant.party
		and grant.limited == nil
	then
		return nil
	end
	return grant
end

--- Sets the Shop save's flags a grant carries (VipOffer, VipCueGiven, FirstPackBought,
--- StarterBought). Changes `shopSave`; call it in the grant's save mutation.
function Shop.markGrant(shopSave: ShopSave, grant: Grant)
	if grant.vip then
		shopSave.VipOffer = true
	end
	if grant.vipCue then
		shopSave.VipCueGiven = true
	end
	if grant.firstPack then
		shopSave.FirstPackBought = true
	end
	if grant.starterBought then
		shopSave.StarterBought = true
	end
end

---------------------------------------------------------------------------------------------
-- Money Party (11.5)
---------------------------------------------------------------------------------------------

--- When the server's Money Party ends after one more purchase at `now`: PartySeconds more
--- from the later of now and the current end, but never more than PartyMaxSeconds past now,
--- and never earlier than it already ended (a paid purchase never cuts time).
function Shop.partyEndsAt(currentEndsAt: number, now: number): number
	local from = math.max(now, currentEndsAt)
	return math.max(currentEndsAt, math.min(from + S.PartySeconds, now + S.PartyMaxSeconds))
end

--- Whether a Money Party bought now would add its full PartySeconds (the queue has room), so
--- the shop can stop offering it when the hour is full.
function Shop.canQueueParty(currentEndsAt: number, now: number): boolean
	return math.max(now, currentEndsAt) + S.PartySeconds <= now + S.PartyMaxSeconds
end

---------------------------------------------------------------------------------------------
-- The Limited shelf (9)
---------------------------------------------------------------------------------------------

--- Every Limited shelf row (Config.Shop.Limited, shelf order). Read-only.
function Shop.limited(): { LimitedRow }
	return LIMITED
end

--- The Limited row for a cue id, or nil.
function Shop.limitedFor(cueId: string): LimitedRow?
	for _, row in LIMITED do
		if row.Cue == cueId then
			return row
		end
	end
	return nil
end

--- A Limited row's state at `now`. `sold` is the global copy count (nil when unknown: never
--- shown as sold out; the server's atomic counter refuses past the cap anyway); `owned` is
--- whether this player has one.
function Shop.limitedState(
	row: LimitedRow,
	now: number,
	sold: number?,
	owned: boolean
): LimitedState
	local startsAt = whole(row.StartsAt)
	local endsAt = startsAt + whole(row.Seconds)
	local soldOut = row.Cap ~= nil and sold ~= nil and sold >= row.Cap
	local open = now >= startsAt and now < endsAt and not soldOut
	return {
		open = open,
		startsAt = startsAt,
		endsAt = endsAt,
		soldOut = soldOut,
		owned = owned == true,
		canBuy = open and owned ~= true,
	}
end

---------------------------------------------------------------------------------------------
-- Receipts (the brief's section 12): every developer product purchase granted exactly once
---------------------------------------------------------------------------------------------

--- Whether the Shop save already holds this receipt's purchase id.
function Shop.hasPurchase(shopSave: ShopSave, purchaseId: string): boolean
	local list = shopSave.Purchases
	return type(list) == "table" and table.find(list, purchaseId) ~= nil
end

--- Records a purchase id (once), keeping only the last RecentPurchases, oldest dropped first.
--- Changes `shopSave`; call it in the grant's save mutation.
function Shop.recordPurchase(shopSave: ShopSave, purchaseId: string)
	if type(shopSave.Purchases) ~= "table" then
		shopSave.Purchases = {}
	end
	local list = shopSave.Purchases
	if table.find(list, purchaseId) ~= nil then
		return
	end
	table.insert(list, purchaseId)
	while #list > S.RecentPurchases do
		table.remove(list, 1)
	end
end

local function decide(deps: ReceiptDeps, receipt: Receipt, say: (string) -> ()): Decision
	local purchaseId = receipt.PurchaseId
	if type(purchaseId) ~= "string" or purchaseId == "" then
		say("receipt without a purchase id")
		return NOT_YET
	end
	local key = deps.keyForId(receipt.ProductId)
	if key == nil then
		say(("unknown product id %s (purchase %s)"):format(tostring(receipt.ProductId), purchaseId))
		return NOT_YET
	end
	-- Not in this server, or their save not loaded yet: Roblox retries when they are back.
	local player = deps.findPlayer(receipt.PlayerId)
	if player == nil or not deps.isLoaded(player) then
		return NOT_YET
	end
	if not deps.hasPurchase(player, purchaseId) then
		if not deps.grant(player, key, purchaseId) then
			say(("could not grant %s (purchase %s)"):format(key, purchaseId))
			return NOT_YET
		end
	end
	-- Granted now or on an earlier try whose save failed: acknowledge only once the save
	-- holding the purchase id has reached the DataStore. A retry finds the id and saves
	-- again without granting again.
	if not deps.save(player) then
		say(("save failed after %s (purchase %s); Roblox will retry"):format(key, purchaseId))
		return NOT_YET
	end
	return GRANTED
end

--- The ProcessReceipt decision for one receipt ({ PlayerId, ProductId, PurchaseId }):
--- "Granted" or "NotProcessedYet" (the server maps it to Enum.ProductPurchaseDecision).
--- Unknown product, player not here, save not loaded, grant failed, save failed, or any error
--- thrown by a dep: "NotProcessedYet", and Roblox retries later. A purchase id already in the
--- save is never granted again.
function Shop.processReceipt(deps: ReceiptDeps, receipt: Receipt): Decision
	local function say(message: string)
		local log = deps.log
		if log ~= nil then
			pcall(log, "[Shop] " .. message)
		end
	end
	local ok, result = pcall(decide, deps, receipt, say)
	if not ok then
		say("receipt failed: " .. tostring(result))
		return NOT_YET
	end
	return result :: Decision
end

return Shop
