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
--
-- A receipt is Robux already paid, and any client can prompt any product itself (the ids are
-- public), so the offer windows and "once only" are checked again at the receipt
-- (receiptCheck): a receipt that is not for this player now is never refused, it is paid as
-- plain money instead (fallbackGrant, at the first pack's money per Robux).
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
	BoostEnds: number?, -- unix time the Starter Pack's 2x money hour ends (0: none)
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
	cue: string?, -- a cue to add: the VIP Cue the first time
	vip: boolean?, -- VIP from the welcome offer (sets Shop.VipOffer)
	vipCue: boolean?, -- cue is the VIP Cue (sets Shop.VipCueGiven)
	party: boolean?, -- start or extend this server's Money Party (Shop.partyEndsAt)
	limited: string?, -- a Limited cue id to number and give (a Robux Limited)
	firstPack: boolean?, -- this pack paid FirstPackMultiplier (sets Shop.FirstPackBought)
	starterBought: boolean?, -- sets Shop.StarterBought
	spins: number?, -- ult spins to add (Spin1..Spin50; the save's Ults.Spins)
	lucky: number?, -- Lucky Spins to add (Lucky1, Lucky3; Ults.LuckySpins)
	-- Lucky blocks to add, paid origin (Mystery1, GrandOpening3, the Starter Pack's block).
	blocks: { kind: string, count: number }?,
	-- A restock item bought with Robux (RestockRare .. RestockLegendary): its restock slot,
	-- item id and the block kind it gives (the Store fills it in: the restock is the server's).
	restock: { slot: number, id: string, block: string }?,
	-- A Robux timer skip (Skip1h ... Skip48h): the timer the player picked (the Store's).
	skip: { case: string, at: number }?,
	luckySkip: boolean?, -- durable lucky block timer credit, applied by PlayerData
	boostEnds: number?, -- the Starter Pack's 2x money hour ends then (sets Shop.BoostEnds)
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
	isLoaded: (any) -> boolean, -- their save is loaded (the server waits for one still loading)
	hasPurchase: (any, string) -> boolean, -- the purchase id is in their save's Purchases
	grant: (any, string, string) -> boolean, -- grants AND records the id in one save mutation
	save: (any) -> boolean, -- asks the DataStore to save and waits (with a timeout)
	log: ((string) -> ())?,
}

type ProductRow = {
	Kind: string,
	Id: number,
	Robux: number,
	Money: number?,
	Bonus: number?,
	Was: number?, -- the original price shown crossed out (ult spin packs)
	Spins: number?, -- ult spins one purchase adds
	Lucky: number?, -- Lucky Spins one purchase adds
	Blocks: { Kind: string, Count: number }?, -- lucky blocks one purchase adds
	Deal: string?, -- the Config.Shop.Deals key whose window it is sold in (GrandOpening)
	Retired: boolean?, -- no longer sold (QuickCases): hidden, never prompted
	Restock: string?, -- the restock block kind it buys (RestockRare .. RestockLegendary)
	SkipSeconds: number?, -- the most time left on the timer it finishes (Skip1h ... Skip48h)
	Random: boolean?, -- a paid random item (refused where PolicyService restricts them)
	SaleOf: string?, -- a release-sale product: gives what this key gives (Shop.releaseSale)
	Vip: boolean?, -- grants VIP in the save, like the welcome offer (the sale's VIP)
}

local LIST: { [string]: ProductRow } = P.List :: any
local PACK_ORDER: { string } = P.PackOrder
local LIMITED: { LimitedRow } = S.Limited :: any

-- A block deal (Config.Shop.Deals): blocks of Kind sold by the count, for money or Robux,
-- inside a window when StartsAt is set.
export type DealRow = {
	Kind: string,
	Money: { [number]: number },
	Products: { [number]: string },
	StartsAt: number?,
	Seconds: number?,
	VaultedSeconds: number?,
}
local DEALS: { [string]: DealRow } = S.Deals :: any

-- A deal's window: always open when it has no StartsAt; closed (off) at StartsAt 0; else
-- open from StartsAt for Seconds, and "vaulted" (shown as gone) for VaultedSeconds after.
export type DealWindow = {
	open: boolean,
	timed: boolean, -- it has a window at all
	startsAt: number, -- 0 when untimed or off
	endsAt: number,
	vaultedUntil: number, -- the end of the Vaulted card (endsAt when none)
	vaulted: boolean, -- ended, and still inside VaultedSeconds
}

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

-- This server's Limited windows set by the /limited dev command ({ StartsAt, Seconds } by
-- cue id), over Config's. Only the server sets them (Shop.setWindow).
local windows: { [string]: { StartsAt: number, Seconds: number } } = {}

-- A row with this server's window applied (a copy when one is set).
local function effective(row: LimitedRow): LimitedRow
	local window = windows[row.Cue]
	if window == nil then
		return row
	end
	local copy = table.clone(row)
	copy.StartsAt = window.StartsAt
	copy.Seconds = window.Seconds
	return copy
end

local function limitedForProduct(key: string): LimitedRow?
	for _, row in LIMITED do
		if row.Product == key then
			return effective(row)
		end
	end
	return nil
end

-- Whether a receipt at `now` still counts as bought inside a window that closes at `endsAt`:
-- open, or closed less than OfferGraceSeconds ago (a prompt shown just before the end).
local function inGrace(now: number, endsAt: number): boolean
	return now < endsAt + S.OfferGraceSeconds
end

--- The block deals' keys, sorted.
function Shop.dealKeys(): { string }
	local keys = {}
	for key in DEALS do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

--- The Config.Shop.Deals row for a key, or nil.
function Shop.dealRow(key: any): DealRow?
	if type(key) ~= "string" then
		return nil
	end
	return DEALS[key]
end

-- This server's deal windows set by the dev command ({ StartsAt, Seconds } by deal key),
-- over Config's. Only the server sets them (Shop.setDeal).
local dealWindows: { [string]: { StartsAt: number, Seconds: number } } = {}

-- A deal row with this server's window applied (a copy when one is set).
local function effectiveDeal(key: string): DealRow?
	local row = DEALS[key]
	local window = dealWindows[key]
	if row == nil or window == nil then
		return row
	end
	local copy = table.clone(row)
	copy.StartsAt = window.StartsAt
	copy.Seconds = window.Seconds
	return copy
end

--- The dev command: deal `key`'s window in this server, from `startsAt` (unix) for `seconds`;
--- nil for both goes back to Config's. False when it is no deal.
function Shop.setDeal(key: string, startsAt: number?, seconds: number?): boolean
	if DEALS[key] == nil then
		return false
	end
	if startsAt == nil or seconds == nil then
		dealWindows[key] = nil
	else
		dealWindows[key] = { StartsAt = whole(startsAt), Seconds = whole(seconds) }
	end
	return true
end

--- Deal `key`'s window at unix time `now` (see DealWindow). An unknown key is closed.
function Shop.deal(key: string, now: number): DealWindow
	local row = effectiveDeal(key)
	if row == nil then
		return {
			open = false,
			timed = true,
			startsAt = 0,
			endsAt = 0,
			vaultedUntil = 0,
			vaulted = false,
		}
	end
	if row.StartsAt == nil then
		return {
			open = true,
			timed = false,
			startsAt = 0,
			endsAt = 0,
			vaultedUntil = 0,
			vaulted = false,
		}
	end
	local startsAt = whole(row.StartsAt)
	local endsAt = if startsAt > 0 then startsAt + whole(row.Seconds) else 0
	local vaultedUntil = if startsAt > 0 then endsAt + whole(row.VaultedSeconds) else 0
	return {
		open = startsAt > 0 and now >= startsAt and now < endsAt,
		timed = true,
		startsAt = startsAt,
		endsAt = endsAt,
		vaultedUntil = vaultedUntil,
		vaulted = startsAt > 0 and now >= endsAt and now < vaultedUntil,
	}
end

--- The money price of `count` blocks of deal `key` (a count the deal sells), or nil for any
--- other count or an unknown deal.
function Shop.blockPrice(key: any, count: any): number?
	local row = Shop.dealRow(key)
	if row == nil or type(count) ~= "number" then
		return nil
	end
	local price = row.Money[count]
	return if type(price) == "number" then price else nil
end

--- The money price of `count` Mystery blocks (the Mystery deal), or nil for any other count.
function Shop.mysteryPrice(count: any): number?
	return Shop.blockPrice("Mystery", count)
end

--- Why a receipt for developer product `key` at unix time `now` must not give what the product
--- gives, or nil when it may. `vipPass` is whether the player owns the VIP game pass. "Owned":
--- VIP already (the pass or the offer) for the VIP offer, the Starter Pack bought, a Robux
--- Limited already in Shop.Limited. "Closed": the VIP offer outside both its welcome and its
--- comeback window, the Starter Pack past its week (FirstJoin unknown: closed); each window
--- counts OfferGraceSeconds longer here than at the prompt. Every other product: nil. A Robux
--- Limited's window and cap are the server's Limited counter's.
function Shop.receiptCheck(key: string, shopSave: ShopSave, now: number, vipPass: boolean): string?
	local first = whole(shopSave.FirstJoin)
	local saleRow = LIST[key]
	if saleRow ~= nil and saleRow.Vip == true and Shop.isVip(vipPass, shopSave) then
		return "Owned" -- the sale's VIP when VIP already (a receipt still pays the fallback)
	end
	if key == VIP_OFFER then
		if Shop.isVip(vipPass, shopSave) then
			return "Owned"
		end
		local welcomeEnds = first + S.WelcomeSeconds
		local comebackStarts = first + S.ComebackAfterSeconds
		local comebackEnds = comebackStarts + S.ComebackSeconds
		local welcome = first > 0 and inGrace(now, welcomeEnds)
		local comeback = first > 0 and now >= comebackStarts and inGrace(now, comebackEnds)
		if not (welcome or comeback) then
			return "Closed"
		end
	elseif key == STARTER_PACK then
		if shopSave.StarterBought == true then
			return "Owned"
		end
		if not (first > 0 and inGrace(now, first + S.StarterSeconds)) then
			return "Closed"
		end
	else
		local limited = limitedForProduct(key)
		local owned = shopSave.Limited
		if limited ~= nil and type(owned) == "table" and owned[limited.Cue] ~= nil then
			return "Owned"
		end
		-- A deal product (the Grand Opening block) only inside its window, plus the grace.
		if saleRow ~= nil and saleRow.Deal ~= nil then
			local window = Shop.deal(saleRow.Deal, now)
			if
				window.timed
				and not (
					window.startsAt > 0
					and now >= window.startsAt
					and inGrace(now, window.endsAt)
				)
			then
				return "Closed"
			end
		end
	end
	return nil
end

--- The money a receipt for product `key` pays when it cannot give what the product gives
--- (receiptCheck, or a Robux Limited sold out or ended): the product's Robux at the first
--- money pack's money per Robux (PackOrder[1]: $900 for 49 R$), rounded down. 0 for a key
--- with no Robux price.
function Shop.fallbackMoney(key: string): number
	local row = LIST[key]
	local base = LIST[PACK_ORDER[1]]
	if row == nil or base == nil or whole(base.Robux) <= 0 then
		return 0
	end
	return math.max(0, whole(row.Robux) * whole(base.Money) // whole(base.Robux))
end

--- The plain money grant for a receipt that cannot give what product `key` gives: money only
--- (Shop.fallbackMoney), no cue, no flags, not the first pack's double. nil when it is 0.
function Shop.fallbackGrant(key: string): Grant?
	local money = Shop.fallbackMoney(key)
	if money <= 0 then
		return nil
	end
	return { key = key, money = money }
end

--- Whether product `key` is a paid random item (Config.Products' Random: Mystery Cases, the
--- restock cases, timer skips, ability spins), refused where PolicyService restricts them.
function Shop.isRandom(key: string): boolean
	local row = LIST[key]
	return row ~= nil and row.Random == true
end

--- What buying developer product `key` gives this player at unix time `now` (`vipPass`: they
--- own the VIP game pass), and why it is the money fallback instead (receiptCheck's reason), or
--- nil for a pass, an unknown key, or a product that would give nothing (a receipt for it is
--- left NotProcessedYet and logged instead of taking Robux for nothing). A receipt is Robux
--- already paid, so a product that is not for this player now (an offer closed, the Starter
--- Pack or VIP had already) is never refused: it becomes Shop.fallbackGrant.
function Shop.grantFor(
	key: string,
	shopSave: ShopSave,
	now: number,
	vipPass: boolean
): (Grant?, string?)
	local row = LIST[key]
	if row == nil or row.Kind ~= "Product" then
		return nil, nil
	end
	local notFor = Shop.receiptCheck(key, shopSave, now, vipPass)
	if notFor ~= nil then
		return Shop.fallbackGrant(key), notFor
	end
	local grant: Grant = { key = key, money = math.max(0, whole(row.Money)) }
	-- The first money pack ever pays FirstPackMultiplier times its money, once (11.1).
	if
		grant.money > 0
		and table.find(PACK_ORDER, row.SaleOf or key) ~= nil
		and shopSave.FirstPackBought ~= true
	then
		grant.money *= S.FirstPackMultiplier
		grant.firstPack = true
	end
	if key == VIP_OFFER or row.Vip == true then
		grant.vip = true
		if shopSave.VipCueGiven ~= true then
			grant.cue = S.VipCue
			grant.vipCue = true
		end
	elseif key == STARTER_PACK then
		grant.money += S.StarterMoney
		grant.blocks = { kind = S.StarterBlock, count = 1 }
		grant.starterBought = true
		grant.boostEnds = math.max(now, whole(shopSave.BoostEnds)) + S.StarterBoostSeconds
	elseif key == MONEY_PARTY then
		grant.party = true
	end
	local limited = limitedForProduct(key)
	if limited ~= nil then
		grant.limited = limited.Cue
	end
	-- Ult spins and Lucky Spins (ECONOMY 11.8). A spin pack bought where paid random items are
	-- restricted is refused at the prompt; a receipt that arrives anyway is Robux paid, and
	-- grants.
	local spins, lucky = whole(row.Spins), whole(row.Lucky)
	if spins > 0 then
		grant.spins = spins
	end
	if lucky > 0 then
		grant.lucky = lucky
	end
	-- Lucky blocks bought with Robux (paid origin: ready at once).
	local blocks = row.Blocks
	if blocks ~= nil and whole(blocks.Count) > 0 and type(blocks.Kind) == "string" then
		grant.blocks = { kind = blocks.Kind, count = whole(blocks.Count) }
	end
	if
		grant.money <= 0
		and grant.cue == nil
		and not grant.vip
		and not grant.party
		and grant.limited == nil
		and grant.spins == nil
		and grant.lucky == nil
		and grant.blocks == nil
	then
		return nil, nil
	end
	return grant, nil
end

--- Sets the Shop save's flags a grant carries (VipOffer, VipCueGiven, FirstPackBought,
--- StarterBought, BoostEnds). Changes `shopSave`; call it in the grant's save mutation.
function Shop.markGrant(shopSave: ShopSave, grant: Grant)
	if grant.boostEnds ~= nil then
		shopSave.BoostEnds = math.max(whole(shopSave.BoostEnds), whole(grant.boostEnds))
	end
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
-- Timer skips for money (plan section 4)
---------------------------------------------------------------------------------------------

--- The money price of finishing a case timer with `secondsLeft` left: Config.Shop.Skip
--- MoneyPerMinute for every minute (a part minute counts whole), at least MinMoney. 0 for a
--- timer already done.
function Shop.skipPrice(secondsLeft: number): number
	local left = whole(secondsLeft)
	if left <= 0 then
		return 0
	end
	local minutes = math.ceil(left / 60)
	return math.max(minutes * S.Skip.MoneyPerMinute, S.Skip.MinMoney)
end

--- The cheapest Robux skip product (Skip1h ... Skip48h) that finishes a timer with
--- `secondsLeft` left, or nil when none covers it (or the timer is done).
function Shop.skipProduct(secondsLeft: number): string?
	local left = whole(secondsLeft)
	if left <= 0 then
		return nil
	end
	local best: string?, bestSeconds = nil, math.huge
	for _, key in KEYS do
		local seconds = whole(LIST[key].SkipSeconds)
		if seconds >= left and seconds < bestSeconds then
			best, bestSeconds = key, seconds
		end
	end
	return best
end

---------------------------------------------------------------------------------------------
-- Money Party (11.5)
---------------------------------------------------------------------------------------------

--- When the server's Money Party ends after one more paid purchase at `now`: its full
--- PartySeconds more from the later of now and the current end. A receipt is Robux already
--- paid, so it is never cut short: the PartyMaxSeconds cap is only on the prompt
--- (canQueueParty), and two buyers at once or a slow prompt may queue a little past it.
function Shop.partyEndsAt(currentEndsAt: number, now: number): number
	return math.max(now, currentEndsAt) + S.PartySeconds
end

--- Whether a Money Party bought now would stay within PartyMaxSeconds queued (the queue has
--- room for its full PartySeconds), so the shop can stop offering it when the hour is full.
function Shop.canQueueParty(currentEndsAt: number, now: number): boolean
	return math.max(now, currentEndsAt) + S.PartySeconds <= now + S.PartyMaxSeconds
end

---------------------------------------------------------------------------------------------
-- The Limited shelf (9)
---------------------------------------------------------------------------------------------

--- Every Limited shelf row (Config.Shop.Limited, shelf order). Read-only.
--- The scheduled Limited rows (StartsAt above 0), in Config order: what the shelf shows and
--- the counters read. A row with StartsAt 0 is off.
function Shop.limited(): { LimitedRow }
	local list: { LimitedRow } = {}
	for _, row in LIMITED do
		local live = effective(row)
		if whole(live.StartsAt) > 0 then
			table.insert(list, live)
		end
	end
	return list
end

--- The Limited row for a cue id (scheduled or off), or nil.
function Shop.limitedFor(cueId: string): LimitedRow?
	for _, row in LIMITED do
		if row.Cue == cueId then
			return effective(row)
		end
	end
	return nil
end

--- The /limited dev command: Limited `cueId`'s window in this server, from `startsAt` (unix)
--- for `seconds`; nil for both goes back to Config's. False when it is no Limited row.
function Shop.setWindow(cueId: string, startsAt: number?, seconds: number?): boolean
	for _, row in LIMITED do
		if row.Cue == cueId then
			if startsAt == nil or seconds == nil then
				windows[cueId] = nil
			else
				windows[cueId] = { StartsAt = whole(startsAt), Seconds = whole(seconds) }
			end
			return true
		end
	end
	return false
end

--- Every Limited row's cue id (scheduled or off), in Config order.
function Shop.limitedIds(): { string }
	local ids: { string } = {}
	for _, row in LIMITED do
		table.insert(ids, row.Cue)
	end
	return ids
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
	-- StartsAt 0: off (not scheduled yet), so never open and never ended.
	local scheduled = startsAt > 0
	local endsAt = if scheduled then startsAt + whole(row.Seconds) else math.huge
	if not scheduled then
		startsAt = math.huge
	end
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
--- Unknown product, player not here, save not loaded (after the server's wait), grant failed,
--- save failed, or any error thrown by a dep: "NotProcessedYet", and Roblox retries later. A
--- purchase id already in the save is never granted again.
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

---------------------------------------------------------------------------------------------
-- The release sale (Config.Shop.ReleaseSale; designer 2026-10-03, the GUI lane)
---------------------------------------------------------------------------------------------

export type SaleWindow = {
	open: boolean,
	startsAt: number,
	endsAt: number,
	percent: number,
	swap: { [string]: string }, -- normal product key -> its sale product key
}

-- normal key -> sale key, from every Config.Products row with SaleOf (sorted walk).
local SWAP: { [string]: string } = {}
for _, key in KEYS do
	local row = LIST[key]
	if type(row.SaleOf) == "string" then
		SWAP[row.SaleOf] = key
	end
end

--- The release sale at unix time `now`: its window (StartsAt, else the start of the block deal
--- of With, the Grand Opening's) and the products it swaps in. Closed when no start is set.
function Shop.releaseSale(now: number): SaleWindow
	local R = S.ReleaseSale
	local startsAt = whole(R and R.StartsAt)
	if startsAt <= 0 and R and type(R.With) == "string" then
		local deal = effectiveDeal(R.With)
		if deal ~= nil then
			startsAt = whole(deal.StartsAt)
		end
	end
	local endsAt = if startsAt > 0 then startsAt + whole(R and R.Seconds) else 0
	return {
		open = startsAt > 0 and now >= startsAt and now < endsAt,
		startsAt = startsAt,
		endsAt = endsAt,
		percent = whole(R and R.Percent),
		swap = table.clone(SWAP),
	}
end

--- The normal product a release-sale product stands for, or nil for any other key.
function Shop.saleOf(key: string): string?
	local row = LIST[key]
	return if row ~= nil and type(row.SaleOf) == "string" then row.SaleOf else nil
end

return Shop
