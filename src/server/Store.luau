--!strict
-- Store: Robux products and passes, VIP, the timed offers and the Money Party
-- (ECONOMY section 11; the overnight brief's section 12; docs/ARCHITECTURE.md "The economy").
-- The pure rules are Progression/Shop (offers, grants, the party queue, the once-only receipt
-- logic) and Progression/ShopView (the ShopState payload and the Buy check).
--
-- - ProcessReceipt: one handler, Shop.processReceipt with this server's functions. Player not
--   here: NotProcessedYet. A save still loading (Roblox re-offers receipts on join) is waited
--   for (PlayerData.waitLoaded, Config.Save.LoadTimeoutSeconds); one handed off for a teleport
--   is not. A purchase id already in the save: Granted once its save is written. Otherwise the
--   grant and the id go into the save in ONE PlayerData mutation (applyPurchase), then
--   PlayerData.saveNow waits for a save holding the id, and only then PurchaseGranted.
-- - A receipt is Robux already paid and any client can prompt any product itself, so what it
--   gives is decided again at the receipt (Shop.grantFor): an offer outside its window (plus
--   Config.Shop.OfferGraceSeconds), VIP or the Starter Pack had already, pays plain money
--   instead (Shop.fallbackGrant), logged. A Robux Limited (none yet) takes this
--   player's copy number from Counters.takeLimited first (Config.Shop.LimitedReceiptGraceSeconds
--   past its end); already owned, sold out, ended or not started pay the money fallback too
--   (logged), while a counter error, a busy retry or a save not loaded leave the receipt
--   NotProcessedYet for Roblox to retry.
-- - Game passes (Vip, the ult slots UltSlot2 and UltSlot3): UserOwnsGamePassAsync on join (pcall, retried, cached; Id 0
--   is never owned), and PromptGamePassPurchaseFinished with wasPurchased counts the pass for
--   the session at once (Roblox fires it on the server; UserOwnsGamePassAsync may still answer
--   false from its cache right after a purchase). VIP = owns the pass OR bought the welcome
--   offer: the player attribute Vip (the money and XP boosts, the chat tag and the block
--   timers read it), and the VIP Cue once (PlayerData.giveVipCue).
-- - The Money Party is this server's: workspace attributes MoneyPartyEndsAt (unix) and
--   MoneyPartyBuyer (a username), Announce.party on every purchase; cleared when it ends.
-- - StoreRequest "Buy" (a Config.Products key): checked (ShopView.check), then this server
--   prompts the purchase itself. ShopState goes to each player on load and whenever any of it
--   changes (a purchase, a pass, the restriction, the party, a Limited count, an
--   offer window opening or closing on the clock). StoreRequest "RobloxPlus"
--   prompts the Roblox Plus subscription (Config.Shop.RobloxPlus).
-- - The ult spin service (UltSpins) reads passes through Store.ownsPass, hears changes on
--   Store.PassChanged, prompts its Robux products through Store.prompt (the same check as a
--   Buy: ShopView.check, which refuses spin packs where paid random items are restricted) and
--   shows live prices from Store.price. Spin pack receipts grant through the same
--   ProcessReceipt (Shop.grantFor's spins and lucky).
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Shop = require(Shared.Progression.Shop)
local ShopView = require(Shared.Progression.ShopView)
local Restock = require(Shared.Progression.Restock)
local Daily = require(Shared.Progression.Daily)
local Inventory = require(Shared.Progression.Inventory)
local LuckyBlocks = require(Shared.Progression.LuckyBlocks)
local PlayerData = require(script.Parent.PlayerData)
local Funnel = require(script.Parent.Funnel)
local Counters = require(script.Parent.Counters)
local Announce = require(script.Parent.Announce)
local Items = require(script.Parent.Items)

local S = Config.Shop
local IS_STUDIO = RunService:IsStudio()
local LIST: {
	[string]: {
		Kind: string,
		Id: number,
		Robux: number,
		Restock: string?,
		Vip: boolean?, -- the release sale's VIP (grants VIP like VipOffer)
		Retired: boolean?, -- never offered again, so its price is never shown
		ClaimAll: number?, -- Claim All (Config.Daily.ClaimAll): never a gift
	},
} =
	Config.Products.List :: any

-- Server-set attributes (clients and the other services only read them).
local ATTR = {
	Vip = "Vip", -- on the player: VIP (the pass or the welcome offer)
	Restricted = "PaidRandomRestricted", -- on the player, set by Items (PolicyService)
	PartyEndsAt = "MoneyPartyEndsAt", -- on workspace: this server's Money Party end, unix
	PartyBuyer = "MoneyPartyBuyer", -- on workspace: the last buyer's username
}
-- The instance Counters keeps the Limited copy counts on (one attribute per Limited cue).
local LIMITED_SOLD = "LimitedSold"
-- A dev grant's purchase id starts with this (never a Roblox receipt's).
local DEV_PREFIX = "Dev-"
-- The product whose grant depends on the VIP pass (Shop.receiptCheck).
local VIP_OFFER = "VipOffer"
-- Why a Robux Limited's copy could not be taken that may pass on a later try: the receipt stays
-- NotProcessedYet. Any other reason is for good, and the receipt pays the money fallback.
local TRANSIENT: { [string]: boolean } = { Busy = true, Error = true, NotLoaded = true }

-- The game pass keys (Kind "Pass"), sorted.
local PASS_KEYS: { string } = {}
for key, row in LIST do
	if row.Kind == "Pass" then
		table.insert(PASS_KEYS, key)
	end
end
table.sort(PASS_KEYS)

export type Reply = { ok: boolean, reason: string? }

local Store = {}

local passEvent = Instance.new("BindableEvent")
--- (player) Fires when a player's game pass ownership may have changed: the join check
--- finished, a pass was bought in this server, or /buy or /vip faked one.
Store.PassChanged = passEvent.Event

local started = false
local shopState: RemoteEvent? = nil

-- Game passes: what Roblox said each player owns, the dev override (/vip), and
-- whether the join check finished (the VIP Cue waits for it).
local passOwned: { [Player]: { [string]: boolean } } = {}
local passFake: { [Player]: { [string]: boolean } } = {}
local passChecked: { [Player]: boolean } = {}
-- The designer's /vip off (designer, 2026-10-09: "see what its like for a normal player
-- without VIP"): this session they count as a player without VIP everywhere the game asks
-- (the Vip attribute every perk reads, the Shop's state), whatever the pass and the save say.
-- A purchase still checks the real VIP, so nothing already owned can be bought again.
local actingRegular: { [Player]: boolean } = {}
-- The last StoreRequest per player (os.clock), for the cooldown.
local lastRequest: { [Player]: number } = {}
-- When each player's shop next changes by itself (unix; ShopView.nextChange).
local nextChange: { [Player]: number } = {}
-- Players whose ShopState is due, sent together at the end of the frame.
local dirty: { [Player]: boolean } = {}
local flushQueued = false
-- Live Robux prices by product key (GetProductInfoAsync, read once at start).
local prices: { [string]: number } = {}
-- This server's Money Party.
local partyEndsAt = 0
local partyBuyer: string? = nil
-- Robux Limited copy numbers taken for a receipt whose grant has not landed yet (a retry in
-- this server reuses it), and the receipts taking one right now (a concurrent retry waits).
local pendingCopies: { [string]: number } = {}
local takingCopy: { [string]: boolean } = {}
-- A Robux restock remembered from its prompt until its receipt: the restock slot the player
-- saw (and whether a Legendary unit was reserved for it).
local pendingRestock: { [Player]: { key: string, slot: number, at: number, reserved: boolean } } =
	{}
-- A gift remembered from its prompt until its receipt: the product and who gets it.
local pendingGift: { [Player]: { key: string, to: number, name: string } } = {}
local giftEvent: RemoteEvent? = nil
local purchaseEvent: RemoteEvent? = nil
-- The restock slot this server last saw (a new one re-sends ShopState and may announce).
local restockSlot = -1
-- The Legendary units taken last sent in ShopState (Counters.stockTaken).
local stockSeen: number? = nil
-- Dev grants made this session (their purchase ids count up).
local devGrants = 0

local function log(message: string)
	warn("[8ball] Store: " .. message)
end

-- Runs fn(...) and logs an error instead of raising it (a display or announce failure must
-- never reach a receipt, a remote or a loop).
local function safely(what: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(function(...: any): any
		fn(...)
		return nil
	end, ...)
	if not ok then
		log(("%s failed: %s"):format(what, tostring(err)))
	end
end

local function present(player: Player): boolean
	return player.Parent == Players
end

-- The player's save is loaded here and not handed off for a teleport.
local function ready(player: Player): boolean
	return PlayerData.isLoaded(player) and not PlayerData.isHandedOff(player)
end

---------------------------------------------------------------------------------------------
-- The state (ShopState) and the attributes
---------------------------------------------------------------------------------------------

-- The Shop save as the game should see it: without the welcome offer's VIP while acting as a
-- regular player (a copy; the save itself is never changed).
local function shopSeen(player: Player, shopSave: any): any
	if actingRegular[player] and shopSave ~= nil and shopSave.VipOffer == true then
		local copy = table.clone(shopSave)
		copy.VipOffer = false
		return copy
	end
	return shopSave
end

local function owns(player: Player, passKey: string): boolean
	local fake = passFake[player]
	if fake ~= nil and fake[passKey] ~= nil then
		return fake[passKey]
	end
	local real = passOwned[player]
	return real ~= nil and real[passKey] == true
end

local function limitedSold(): { [string]: number }
	local sold: { [string]: number } = {}
	for _, row in Shop.limited() do
		local ok, n = pcall(Counters.limitedSold, row.Cue)
		if ok and type(n) == "number" then
			sold[row.Cue] = n
		end
	end
	return sold
end

-- The passes other than Vip (the ult slots) this player owns, by key.
local function otherPasses(player: Player): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, key in PASS_KEYS do
		if key ~= "Vip" then
			out[key] = owns(player, key)
		end
	end
	return out
end

-- Everything ShopView needs for this player now; nil while the save is not loaded.
local function context(player: Player, now: number): ShopView.Context?
	local data = PlayerData.read(player)
	if data == nil then
		return nil
	end
	return {
		passes = otherPasses(player),
		now = now,
		shop = shopSeen(player, data.Shop),
		vipPass = owns(player, "Vip") and not actingRegular[player],
		restricted = player:GetAttribute(ATTR.Restricted) == true,
		policyKnown = player:GetAttribute(ATTR.Restricted) ~= nil,
		-- UltSpins' isLive, read here without requiring it (it requires Store).
		spinsLive = Config.Ults.ScreenLive or IS_STUDIO or player:GetAttribute("UltDevAll") == true,
		partyEndsAt = partyEndsAt,
		partyBuyer = partyBuyer,
		sold = limitedSold(),
		restock = data.Shop.Restock,
		drops = data.Drops,
		stockTaken = Counters.stockTaken(Restock.stockKey(Items.restockSlot(now))),
		restockSlot = Items.restockSlot(now),
		prices = prices,
		blocks = data.LuckyBlocks,
		ownsCue = function(id: string): boolean
			return Inventory.owns(data, id)
		end,
		found = Counters.limitedSold,
		claimAll = Daily.claimAllOffer(
			data.Login,
			Daily.dayOf(now),
			nil,
			{ joinDay = Daily.joinDayOf(data.Shop.FirstJoin) }
		).product,
	}
end

-- Sets Vip from the pass and the save (the save may not be loaded yet).
local function setAttributes(player: Player, shopSave: any?)
	local vip = Shop.isVip(owns(player, "Vip"), shopSave) and not actingRegular[player]
	if player:GetAttribute(ATTR.Vip) ~= vip then
		player:SetAttribute(ATTR.Vip, vip)
	end
end

-- Sends one player's ShopState now, sets their attributes, and gives the VIP Cue when due.
local function send(player: Player)
	if not present(player) then
		return
	end
	local now = os.time()
	local ctx = if ready(player) then context(player, now) else nil
	setAttributes(player, if ctx ~= nil then ctx.shop else nil)
	if ctx == nil then
		return
	end
	-- The VIP Cue, once, however VIP came; after the join's pass check so a pass owner is
	-- never missed. giveVipCue fires Changed, which sends the state again.
	if passChecked[player] and Shop.vipCueDue(ShopView.isVip(ctx), ctx.shop) then
		task.defer(function()
			if PlayerData.giveVipCue(player) then
				Counters.add(Config.Shop.VipCue, 1) -- one more copy in existence
			end
		end)
	end
	local remote = shopState
	if remote ~= nil then
		remote:FireClient(player, ShopView.build(ctx))
	end
	local at = ShopView.nextChange(ctx)
	if at ~= nil then
		nextChange[player] = at
	else
		nextChange[player] = nil
	end
end

local function flush()
	flushQueued = false
	local list: { Player } = {}
	for player in dirty do
		table.insert(list, player)
	end
	table.clear(dirty)
	for _, player in list do
		safely(("sending the shop of %d"):format(player.UserId), send, player)
	end
end

-- Marks a player's ShopState due; everything marked in one frame goes out once.
local function mark(player: Player)
	dirty[player] = true
	if not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

local function markAll()
	for _, player in Players:GetPlayers() do
		mark(player)
	end
end

---------------------------------------------------------------------------------------------
-- Game passes
---------------------------------------------------------------------------------------------

-- Asks Roblox whether the player owns pass `key` (Id 0: never). nil when the call failed.
local function askPass(player: Player, key: string): boolean?
	local id = LIST[key].Id
	if type(id) ~= "number" or id <= 0 then
		return false
	end
	local ok, result = pcall(function(): boolean
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if not ok then
		return nil
	end
	return result == true
end

-- The join check of every pass, retried when Roblox's call fails.
local function checkPasses(player: Player)
	local owned: { [string]: boolean } = passOwned[player] or {}
	passOwned[player] = owned
	for _, key in PASS_KEYS do
		for try = 1, S.PassCheckTries do
			if not present(player) then
				return
			end
			local answer = askPass(player, key)
			if answer ~= nil then
				-- A purchase counted meanwhile stays counted (Roblox's answer may be cached).
				owned[key] = answer or owned[key] == true
				break
			elseif try == S.PassCheckTries then
				log(
					("could not check pass %s for %d; not owned this session"):format(
						key,
						player.UserId
					)
				)
			else
				task.wait(S.PassRetrySeconds)
			end
		end
	end
	if present(player) then
		passChecked[player] = true
		mark(player)
		passEvent:Fire(player)
	end
end

-- Tell `player`'s client what a Robux purchase gave (Net PurchaseDone: the thank-you and the
-- flow to the HUD). `grant` is what landed (nil: nothing to tell); `extra` adds pass, to, from.
local function tellPurchase(player: Player, grant: Shop.Grant?, extra: { [string]: any }?)
	local remote = purchaseEvent
	if remote == nil or grant == nil or not present(player) then
		return
	end
	local blocks = {}
	if grant.blocks ~= nil then
		table.insert(blocks, { kind = grant.blocks.kind, count = grant.blocks.count })
	elseif grant.restock ~= nil then
		table.insert(blocks, { kind = grant.restock.block, count = 1 })
	end
	local message: { [string]: any } = {
		key = grant.key,
		money = grant.money,
		blocks = blocks,
		cue = grant.cue or grant.limited,
		vip = grant.vip == true or grant.key == "Vip",
		party = grant.party == true,
		spins = grant.spins,
		skip = grant.luckySkip == true,
		claimAll = grant.claimAll ~= nil,
	}
	if extra ~= nil then
		for field, value in extra do
			message[field] = value
		end
	end
	remote:FireClient(player, message)
end

-- A pass purchase finished in this server: counted for the session at once. Roblox fires
-- PromptGamePassPurchaseFinished on the server itself (its own game pass guide grants on it),
-- while UserOwnsGamePassAsync may answer false from its cache for a while after a purchase;
-- the join check asks again next session.
local function onPassPurchase(player: Player, passId: number, purchased: boolean)
	if not purchased or not present(player) then
		return
	end
	local key = Shop.passKeyForId(passId)
	if key == nil then
		return
	end
	local owned = passOwned[player] or {}
	passOwned[player] = owned
	owned[key] = true
	mark(player)
	Funnel.shop(player, "Bought") -- the shop funnel (the tutorial lane)
	tellPurchase(player, { key = key, money = 0 }, { pass = true })
	passEvent:Fire(player)
end

-- A VIP offer receipt re-offered at join waits for the join's VIP pass answer (a pass owner's
-- receipt pays the money fallback), up to Config.Shop.ReceiptPassWaitSeconds; after that the
-- pass counts as not owned, as when the join check fails.
local function waitVipPassCheck(player: Player)
	local deadline = os.clock() + S.ReceiptPassWaitSeconds
	while present(player) and os.clock() < deadline do
		local owned = passOwned[player]
		if passChecked[player] or (owned ~= nil and owned.Vip ~= nil) then
			return
		end
		task.wait()
	end
end

---------------------------------------------------------------------------------------------
-- The Money Party
---------------------------------------------------------------------------------------------

local function setParty(endsAt: number, buyer: string?)
	partyEndsAt = endsAt
	partyBuyer = buyer
	workspace:SetAttribute(ATTR.PartyEndsAt, if endsAt > 0 then endsAt else nil)
	workspace:SetAttribute(ATTR.PartyBuyer, if endsAt > 0 then buyer else nil)
	markAll()
end

-- One more Money Party purchase by `buyer` (Shop.partyEndsAt: its full 15 more minutes; the
-- hour cap is only on the prompt), announced to everyone here. Returns the new end.
local function addParty(buyer: Player): number
	local now = os.time()
	local current = if partyEndsAt > now then partyEndsAt else 0
	local endsAt = Shop.partyEndsAt(current, now)
	setParty(endsAt, buyer.Name)
	safely("announcing the party", Announce.party, endsAt, buyer.Name)
	return endsAt
end

---------------------------------------------------------------------------------------------
-- Receipts
---------------------------------------------------------------------------------------------

-- A Robux Limited's copy number for this purchase: one kept from an earlier try in this
-- server, else this player's from the shared counter (yields): the number they were given
-- before (a try in another server), else the next one. A receipt still takes a new one
-- LimitedReceiptGraceSeconds past the Limited's end (a prompt confirmed just before it). nil
-- and a reason when none: "Busy", "Error" (try again later), "Unknown", "Closed" (not
-- started), "Ended", "SoldOut" (for good).
local function copyFor(cueId: string, userId: number, purchaseId: string): (number?, string?)
	local kept = pendingCopies[purchaseId]
	if kept ~= nil then
		return kept, nil
	end
	if takingCopy[purchaseId] then
		return nil, "Busy" -- another try of this receipt is asking the counter right now
	end
	local row = Shop.limitedFor(cueId)
	if row == nil then
		return nil, "Unknown"
	end
	if os.time() < row.StartsAt then
		return nil, "Closed"
	end
	takingCopy[purchaseId] = true
	local ok, copy, why = pcall(
		Counters.takeLimited,
		cueId,
		userId,
		row.Cap or Config.Save.CopyNumberCap,
		row.StartsAt + row.Seconds + S.LimitedReceiptGraceSeconds
	)
	takingCopy[purchaseId] = nil
	if not ok then
		return nil, "Error"
	end
	if type(copy) ~= "number" then
		return nil, if type(why) == "string" then why else "Error"
	end
	pendingCopies[purchaseId] = copy
	return copy, nil
end

local function ownsLimited(data: any, cueId: string): boolean
	return data.Shop.Limited[cueId] ~= nil or Inventory.owns(data, cueId)
end

-- A Robux restock receipt's grant: the item of the restock the player saw at the prompt (within
-- Config.Shop.Restock.ReceiptGraceSeconds), else of the restock now; the Legendary's shared
-- unit reserved (kept from the prompt). Not in that restock, the player's stock used, or the
-- shared stock gone: the money fallback, with why. A third answer names a passing trouble (the
-- counter could not be reached): the receipt stays NotProcessedYet.
local function restockGrant(player: Player, key: string, data: any): (Shop.Grant?, string?, string?)
	local now = os.time()
	local pend = pendingRestock[player]
	local slot = if pend ~= nil
			and pend.key == key
			and now - pend.at <= S.Restock.ReceiptGraceSeconds
		then pend.slot
		else Items.restockSlot(now)
	local vip = player:GetAttribute(ATTR.Vip) == true
	local item = Restock.forProduct(slot, key, data.Shop.Restock, vip)
	local why = Restock.check(item, data.Shop.Restock, slot, vip)
	if why == nil and item ~= nil and item.global ~= nil then
		local held, reason =
			Counters.reserveStock(Restock.stockKey(slot), player.UserId, item.global)
		if not held then
			if reason ~= "SoldOut" then
				return nil, nil, reason or "Error"
			end
			why = reason
		end
	end
	if why ~= nil or item == nil then
		return Shop.fallbackGrant(key), why or "NotSold", nil
	end
	return {
		key = key,
		money = 0,
		restock = { slot = slot, id = item.id, block = item.block },
	},
		nil,
		nil
end

-- Grants developer product `key` to `player` and records `purchaseId`, in one PlayerData
-- mutation (Shop.processReceipt's `grant`). What it gives is decided now (Shop.grantFor, and
-- the Limited counter for a Robux Limited); a receipt that cannot give its product pays the
-- money fallback, logged. True once granted (now, or by a concurrent try of the same
-- receipt), with the grant when it landed now; false and a reason otherwise (the receipt
-- stays NotProcessedYet).
local function grantProduct(
	player: Player,
	key: string,
	purchaseId: string
): (boolean, string?, Shop.Grant?)
	local saleRow = LIST[key]
	if key == VIP_OFFER or (saleRow ~= nil and saleRow.Vip == true) then
		waitVipPassCheck(player)
	end
	local data = PlayerData.read(player)
	if data == nil or not ready(player) then
		return false, "NotLoaded"
	end
	local row = LIST[key]
	local grant: Shop.Grant?, notFor: string? = nil, nil
	if row ~= nil and row.Restock ~= nil then
		local why: string?
		grant, notFor, why = restockGrant(player, key, data)
		if why ~= nil then
			return false, why
		end
	elseif LuckyBlocks.skipTierOf(key) ~= nil then
		grant = { key = key, money = 0, luckySkip = true }
	else
		grant, notFor = Shop.grantFor(
			key,
			data.Shop,
			os.time(),
			owns(player, "Vip"),
			player:GetAttribute(ATTR.Restricted) == true
		)
	end
	if grant == nil then
		return false, "Unknown"
	end
	local copy: number? = nil
	local limited = grant.limited
	if limited ~= nil then
		local why: string? = if ownsLimited(data, limited) then "Owned" else nil
		if why == nil then
			local number, reason = copyFor(limited, player.UserId, purchaseId)
			-- The counter yielded: the player may have left, or another try granted it meanwhile.
			if PlayerData.hasPurchase(player, purchaseId) then
				pendingCopies[purchaseId] = nil
				return true, nil
			end
			data = PlayerData.read(player)
			if data == nil or not ready(player) then
				return false, "NotLoaded"
			end
			if number == nil then
				why = reason or "Error"
			elseif ownsLimited(data, limited) then
				why = "Owned" -- another receipt gave it meanwhile (the same number: theirs)
			else
				copy = number
			end
		end
		if why ~= nil then
			if TRANSIENT[why] then
				return false, why
			end
			pendingCopies[purchaseId] = nil
			grant, notFor = Shop.fallbackGrant(key), why
			if grant == nil then
				return false, "Unknown"
			end
		end
	end
	if notFor ~= nil then
		log(
			("receipt %s: %s is not for %d now (%s); paid as $%d instead"):format(
				purchaseId,
				key,
				player.UserId,
				notFor,
				grant.money
			)
		)
	end
	-- The copies in existence: a granted cue (the Starter Cue, a Limited) counts once it lands,
	-- and so does a cue Claim All gives (the Week One Cue, economy v5).
	local cueBefore = if grant.cue ~= nil then Inventory.count(data, grant.cue) else 0
	local dayCues: { string } = if grant.claimAll ~= nil then Daily.rewardCues() else {}
	local dayHad: { number } = {}
	for i, id in dayCues do
		dayHad[i] = Inventory.count(data, id)
	end
	if not PlayerData.applyPurchase(player, purchaseId, grant, copy) then
		return false, "Failed"
	end
	pendingCopies[purchaseId] = nil
	local after = PlayerData.read(player)
	if grant.cue ~= nil and after ~= nil and Inventory.count(after, grant.cue) > cueBefore then
		Counters.add(grant.cue, 1)
	end
	for i, id in dayCues do
		local gained = if after ~= nil then Inventory.count(after, id) - dayHad[i] else 0
		if gained > 0 then
			Counters.add(id, gained)
		end
	end
	if limited ~= nil and copy ~= nil then
		Counters.add(limited, 1)
	end
	if grant.party then
		addParty(player)
	end
	if grant.restock ~= nil then
		pendingRestock[player] = nil
	end
	Funnel.shop(player, "Bought") -- the shop funnel (the tutorial lane)
	return true, nil, grant
end

-- Whether Config.Products key `key` may be gifted: a developer product that is not a restock
-- item or the block timer skip (those name the buyer's own restock or block).
local function giftable(key: string): boolean
	local row = LIST[key]
	return row ~= nil
		and row.Kind == "Product"
		and row.Restock == nil
		and row.ClaimAll == nil -- priced by the buyer's own login row
		and LuckyBlocks.skipTierOf(key) == nil
end

-- The giver's receipt for a gift: the product lands in the receiver's save (their own
-- first-buy double, offer windows and fallbacks), then the purchase id is recorded in the
-- giver's save so Roblox's retries never grant twice. A receiver who left gets nothing: the
-- giver gets the item instead and is told. Returns (true) or (false, why).
local function grantGift(
	buyer: Player,
	pend: { key: string, to: number, name: string },
	key: string,
	purchaseId: string
): (boolean, string?)
	local receiver = Players:GetPlayerByUserId(pend.to)
	local remote = giftEvent
	if receiver == nil or not ready(receiver) then
		local ok, why, grant = grantProduct(buyer, key, purchaseId)
		if ok then
			tellPurchase(buyer, grant) -- theirs after all: thanked, and it flows in
			pendingGift[buyer] = nil
			log(
				("gift %s from %d: %d left; granted to the giver"):format(
					key,
					buyer.UserId,
					pend.to
				)
			)
			if remote ~= nil then
				remote:FireClient(buyer, { key = key, returned = true })
			end
		end
		return ok, why
	end
	local ok, why, grant = grantProduct(receiver, key, purchaseId)
	if not ok then
		return false, why
	end
	-- Their copy of the id, saved now (the giver's receipt waits for the giver's save only).
	if not PlayerData.saveNow(receiver, S.ReceiptSaveTimeoutSeconds, purchaseId) then
		log(("gift %s to %d: their save is late (it saves again later)"):format(key, pend.to))
	end
	-- The giver's record of it: a grant of nothing but the purchase id.
	if not PlayerData.applyPurchase(buyer, purchaseId, { key = key, money = 0 }) then
		return false, "Failed"
	end
	pendingGift[buyer] = nil
	log(("gift %s from %d to %d (receipt %s)"):format(key, buyer.UserId, pend.to, purchaseId))
	if remote ~= nil then
		remote:FireClient(receiver, { from = buyer.DisplayName, key = key })
	end
	tellPurchase(buyer, grant, { to = receiver.DisplayName }) -- the giver is thanked
	tellPurchase(receiver, grant, { from = buyer.DisplayName }) -- the gift flows in
	mark(receiver)
	return true, nil
end

-- Runs one receipt through Shop.processReceipt. `key` names the product for a dev grant
-- (whose ProductId is 0); nil reads it from the ProductId. Returns the decision and, when not
-- granted, why (for the dev command's answer).
local function runReceipt(receipt: Shop.Receipt, key: string?): (Shop.Decision, string?)
	local why: string? = nil
	local purchaseId = receipt.PurchaseId
	local deps: Shop.ReceiptDeps = {
		keyForId = function(id: number): string?
			if key ~= nil then
				return key
			end
			local found = Shop.keyForId(id)
			if found == nil then
				why = "Unknown"
			end
			return found
		end,
		findPlayer = function(userId: number): any?
			local player = Players:GetPlayerByUserId(userId)
			if player == nil then
				why = "NotHere"
			end
			return player
		end,
		isLoaded = function(player: any): boolean
			-- Roblox re-offers a receipt as the player joins, while their save is still
			-- loading: wait for it (Config.Save.LoadTimeoutSeconds, waitLoaded's default), but
			-- never for a save handed off for a teleport.
			if not PlayerData.isHandedOff(player) and not PlayerData.isLoaded(player) then
				PlayerData.waitLoaded(player)
			end
			local loaded = ready(player)
			if not loaded then
				why = "NotLoaded"
			end
			return loaded
		end,
		hasPurchase = function(player: any, id: string): boolean
			return PlayerData.hasPurchase(player, id)
		end,
		grant = function(player: any, productKey: string, id: string): boolean
			local pend = pendingGift[player]
			local ok, reason
			if pend ~= nil and pend.key == productKey then
				ok, reason = grantGift(player, pend, productKey, id)
			else
				local grant
				ok, reason, grant = grantProduct(player, productKey, id)
				if ok then
					tellPurchase(player, grant)
				end
			end
			why = reason
			return ok
		end,
		save = function(player: any): boolean
			local ok = PlayerData.saveNow(player, S.ReceiptSaveTimeoutSeconds, purchaseId)
			if not ok then
				why = "SaveFailed"
			end
			return ok
		end,
		log = log,
	}
	if Shop.processReceipt(deps, receipt) == "Granted" then
		return "Granted", nil
	end
	return "NotProcessedYet", why or "Failed"
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local receipt: Shop.Receipt = {
		PlayerId = info.PlayerId,
		ProductId = info.ProductId,
		PurchaseId = info.PurchaseId,
	}
	local decision, why = runReceipt(receipt, nil)
	if decision == "Granted" then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	-- A player who left or is still loading is ordinary: Roblox retries when they are back.
	if why ~= "NotLoaded" and why ~= "NotHere" then
		log(
			("receipt %s (product %s, player %s) not processed yet: %s"):format(
				tostring(info.PurchaseId),
				tostring(info.ProductId),
				tostring(info.PlayerId),
				tostring(why)
			)
		)
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

---------------------------------------------------------------------------------------------
-- StoreRequest
---------------------------------------------------------------------------------------------

local function reply(ok: boolean, reason: string?): Reply
	return { ok = ok, reason = reason }
end

local function prompt(player: Player, key: string): boolean
	local row = LIST[key]
	local ok, err = pcall(function()
		if row.Kind == "Pass" then
			MarketplaceService:PromptGamePassPurchase(player, row.Id)
		else
			MarketplaceService:PromptProductPurchase(player, row.Id)
		end
	end)
	if not ok then
		log(("prompting %s for %d failed: %s"):format(key, player.UserId, tostring(err)))
	end
	return ok
end

-- Prompts the Roblox Plus subscription (Roblox pays the game for each subscriber signed up in
-- it). False when Roblox refused.
local function promptPlus(player: Player): boolean
	local ok, err = pcall(function()
		MarketplaceService:PromptRobloxSubscriptionPurchase(player)
	end)
	if not ok then
		log(("prompting Roblox Plus for %d failed: %s"):format(player.UserId, tostring(err)))
	end
	return ok
end

local function promptLuckySkip(player: Player, id: any): Reply
	if not ready(player) then
		return reply(false, "NotLoaded")
	end
	-- The skip's price follows the time left right now (Config.LuckyBlocks.Skips, economy v4).
	local data = PlayerData.read(player)
	local block = if data and type(id) == "number"
		then LuckyBlocks.find(data.LuckyBlocks, id)
		else nil
	local product = if block then LuckyBlocks.skipProduct(block, os.time()) else nil
	if product == nil then
		return reply(false, "NoTimer")
	end
	local ctx = context(player, os.time())
	local reason = if ctx then ShopView.check(product, ctx) else "NotLoaded"
	if reason ~= nil then
		return reply(false, reason)
	end
	local selected, used = PlayerData.prepareLuckySkip(player, id)
	if not selected then
		return reply(false, "NoTimer")
	end
	if used then
		return reply(true, nil)
	end
	-- Save the selection before prompting; if delivery moves servers without it, the receipt
	-- still grants a durable credit. The receipt and credit use the existing save barrier.
	PlayerData.saveNow(player, S.ReceiptSaveTimeoutSeconds)
	return reply(prompt(player, product), nil)
end

local function onStoreRequest(player: Player, action: any, key: any, extra: any): Reply
	local clock = os.clock()
	local last = lastRequest[player]
	if action == "LuckySkip" then
		if last ~= nil and clock - last < S.RequestCooldownSeconds then
			return reply(false, "TooFast")
		end
		lastRequest[player] = clock
		return promptLuckySkip(player, key)
	end
	if action == "RobloxPlus" then
		if not S.RobloxPlus then
			return reply(false, "BadRequest")
		elseif last ~= nil and clock - last < S.RequestCooldownSeconds then
			return reply(false, "TooFast")
		end
		lastRequest[player] = clock
		return reply(promptPlus(player), nil)
	end
	if action == "Gift" then
		if type(key) ~= "string" or LIST[key] == nil then
			return reply(false, "BadRequest")
		elseif last ~= nil and clock - last < S.RequestCooldownSeconds then
			return reply(false, "TooFast")
		end
		lastRequest[player] = clock
		if not giftable(key) then
			return reply(false, "NoGift")
		elseif Shop.isRandom(key) and Items.isRestricted(player) ~= false then
			-- The giver buys a paid random item too (economy v4 plan 13): not where restricted.
			return reply(
				false,
				if Items.isRestricted(player) == nil then "NotLoaded" else "Restricted"
			)
		elseif type(extra) ~= "number" or extra ~= extra or extra ~= math.floor(extra) then
			return reply(false, "BadRequest")
		elseif extra == player.UserId then
			return reply(false, "GiftSelf")
		elseif not ready(player) then
			return reply(false, "NotLoaded")
		end
		local receiver = Players:GetPlayerByUserId(extra)
		if receiver == nil then
			return reply(false, "GiftGone")
		elseif not ready(receiver) then
			return reply(false, "GiftNotLoaded")
		end
		-- The product is checked for the one who gets it (owned, closed, coming soon...).
		local ctx = context(receiver, os.time())
		if ctx == nil then
			return reply(false, "GiftNotLoaded")
		end
		local reason = ShopView.check(key, ctx)
		if reason ~= nil then
			return reply(false, reason)
		end
		Funnel.shop(player, "PressedBuy")
		pendingGift[player] = { key = key, to = extra, name = receiver.DisplayName }
		if not prompt(player, key) then
			pendingGift[player] = nil
			return reply(false, "Error")
		end
		return reply(true)
	end
	if action ~= "Buy" or type(key) ~= "string" or LIST[key] == nil then
		return reply(false, "BadRequest")
	end
	if last ~= nil and clock - last < S.RequestCooldownSeconds then
		return reply(false, "TooFast")
	end
	lastRequest[player] = clock
	if not ready(player) then
		return reply(false, "NotLoaded")
	end
	local ctx = context(player, os.time())
	if ctx == nil then
		return reply(false, "NotLoaded")
	end
	local row = LIST[key]
	local reason = ShopView.check(key, ctx)
	if reason ~= nil then
		return reply(false, reason)
	end
	Funnel.shop(player, "PressedBuy") -- the shop funnel (the tutorial lane)
	-- A restock item: remember the restock seen, and hold a Legendary unit while the prompt is up.
	if row.Restock ~= nil then
		local slot = Items.restockSlot(ctx.now)
		local item = Restock.forProduct(slot, key, ctx.restock, ShopView.isVip(ctx))
		local reserved = false
		if item ~= nil and item.global ~= nil then
			local held, why =
				Counters.reserveStock(Restock.stockKey(slot), player.UserId, item.global)
			if not held then
				mark(player)
				return reply(false, why or "Error")
			end
			reserved = true
		end
		pendingRestock[player] = { key = key, slot = slot, at = ctx.now, reserved = reserved }
	end
	pendingGift[player] = nil -- this prompt is for themselves
	if not prompt(player, key) then
		return reply(false, "Error")
	end
	return reply(true)
end

-- A product prompt closed: a cancelled restock gives its Legendary unit back, a cancelled gift
-- forgets its pick (a bought one waits for its receipt).
local function onProductPromptFinished(userId: number, productId: number, purchased: boolean)
	if purchased then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	if player == nil then
		return
	end
	local key = Shop.keyForId(productId)
	local pend = pendingRestock[player]
	if pend ~= nil and pend.key == key then
		pendingRestock[player] = nil
		if pend.reserved then
			Counters.releaseStock(Restock.stockKey(pend.slot), player.UserId)
			mark(player)
		end
	end
	local gift = pendingGift[player]
	if gift ~= nil and gift.key == key then
		pendingGift[player] = nil
	end
end

---------------------------------------------------------------------------------------------
-- Dev (the /buy, /vip and /party commands; the Studio QA hook)
---------------------------------------------------------------------------------------------

--- Dev (/buy): grants Config.Products key `key` exactly as a receipt would (the same
--- Shop.processReceipt, grant, record and save), with `purchaseId` or a new fake one, so the
--- same id grants once. A product that is not for this player now (an offer closed, VIP or the
--- Starter Pack had, a Limited owned, sold out or ended) pays the money fallback, as a real
--- receipt does. A pass key turns that pass on (Store.setPass). Yields until the save.
--- Returns (true) or (false, reason): "Unknown" (no such key), "NotLoaded", "Busy", "Error"
--- (the Limited counter), "Failed" (the mutation refused), "SaveFailed".
function Store.grant(player: Player, key: string, purchaseId: string?): (boolean, string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "BadRequest"
	end
	local row = if type(key) == "string" then LIST[key] else nil
	if row == nil then
		return false, "Unknown"
	end
	if row.Kind == "Pass" then
		return Store.setPass(player, key, true), nil
	end
	if not ready(player) then
		return false, "NotLoaded"
	end
	local id = purchaseId
	if type(id) ~= "string" or id == "" then
		devGrants += 1
		id = ("%s%s-%d-%d-%d"):format(DEV_PREFIX, key, player.UserId, os.time(), devGrants)
	end
	local decision, why =
		runReceipt({ PlayerId = player.UserId, ProductId = 0, PurchaseId = id :: string }, key)
	if decision == "Granted" then
		return true, nil
	end
	return false, why
end

--- Dev (/vip): pretends the player owns (`on`) or does not own game pass `passKey`
--- ("Vip", "UltSlot2" ...) for this session, whatever Roblox says; nil drops the pretence.
--- True when it is a pass key.
function Store.setPass(player: Player, passKey: string, on: boolean?): boolean
	local row = LIST[passKey]
	if row == nil or row.Kind ~= "Pass" or typeof(player) ~= "Instance" then
		return false
	end
	local fake = passFake[player] or {}
	passFake[player] = fake
	if on == nil then
		fake[passKey] = nil -- nil: no override, what Roblox says
	else
		fake[passKey] = on
	end
	passChecked[player] = true
	mark(player)
	passEvent:Fire(player)
	return true
end

--- The designer's /vip off and on: `regular` true makes this player count as one without VIP
--- for this session (the Vip attribute and the Shop), false gives back what they really have.
--- Returns whether they are VIP now, as the game sees it.
function Store.actAsRegular(player: Player, regular: boolean): boolean
	if regular then
		actingRegular[player] = true
	else
		actingRegular[player] = nil
	end
	local data = PlayerData.read(player)
	setAttributes(player, if data then data.Shop else nil)
	mark(player)
	return player:GetAttribute(ATTR.Vip) == true
end

--- Whether the player owns game pass `name` (a Config.Products key of Kind "Pass": "Vip",
--- "UltSlot2", "UltSlot3"): Roblox's join answer, a purchase in this server, or the
--- dev override (Store.setPass). "Vip" is the pass alone (VIP also comes from the welcome
--- offer: the Vip attribute). False for anything else and while the join check is running.
function Store.ownsPass(player: Player, name: string): boolean
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(name) ~= "string" then
		return false
	end
	local row = LIST[name]
	if row == nil or row.Kind ~= "Pass" then
		return false
	end
	return owns(player, name)
end

--- The live Robux price of Config.Products key `key` (read once at start), or nil (Config's
--- fallback price applies: an id of 0, or Roblox did not answer).
function Store.price(key: string): number?
	return prices[key]
end

--- Every live Robux price known, by product key (a new table).
function Store.prices(): { [string]: number }
	return table.clone(prices)
end

--- Prompts the purchase of Config.Products key `key` for this player after the same check a
--- StoreRequest "Buy" gets (ShopView.check: "Owned", "Restricted" for a spin pack where paid
--- random items are restricted, "ComingSoon" for id 0...). The grant comes later through
--- ProcessReceipt (a pass: PromptGamePassPurchaseFinished). Returns (true) once the prompt is
--- up, or (false, reason): "BadRequest", "NotLoaded", ShopView.check's reasons, "Error".
function Store.prompt(player: Player, key: string): (boolean, string?)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false, "BadRequest"
	elseif type(key) ~= "string" or LIST[key] == nil then
		return false, "BadRequest"
	elseif not ready(player) then
		return false, "NotLoaded"
	end
	local ctx = context(player, os.time())
	if ctx == nil then
		return false, "NotLoaded"
	end
	local reason = ShopView.check(key, ctx)
	if reason ~= nil then
		return false, reason
	end
	if not prompt(player, key) then
		return false, "Error"
	end
	return true, nil
end

--- Dev (/party): starts or extends this server's Money Party as if `player` bought one.
--- Returns the party's new end (unix).
function Store.startParty(player: Player): number
	return addParty(player)
end

--- This server's Money Party: its end (unix) and buyer while one runs, else nil.
function Store.party(): (number?, string?)
	if partyEndsAt > os.time() then
		return partyEndsAt, partyBuyer
	end
	return nil, nil
end

--- Sends the player's ShopState again (and refreshes Vip).
function Store.refresh(player: Player)
	mark(player)
end

-- Studio only: ServerStorage.StoreQA (a BindableFunction; clients can never reach it).
--   ("state", userId)            -> the ShopState payload that player would get now
--   ("grant", userId, key, id?)  -> Store.grant's (ok, reason)
--   ("setPass", userId, key, on) -> Store.setPass
--   ("party", userId)            -> Store.startParty
--   ("buy", userId, key)         -> the StoreRequest answer (prompts in Studio)
--   ("receipt", userId, productId, purchaseId) -> the ProcessReceipt decision's Name
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("StoreQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "StoreQA"
	hook.OnInvoke = function(op: string, userId: number, a: any, b: any): ...any
		local player = Players:GetPlayerByUserId(userId)
		assert(player, "StoreQA: no player in game with that UserId")
		if op == "state" then
			local ctx = context(player, os.time())
			return if ctx ~= nil then ShopView.build(ctx) else nil
		elseif op == "grant" then
			return Store.grant(player, a, b)
		elseif op == "setPass" then
			return Store.setPass(player, a, b)
		elseif op == "party" then
			return Store.startParty(player)
		elseif op == "buy" then
			lastRequest[player] = nil
			return onStoreRequest(player, "Buy", a)
		elseif op == "receipt" then
			return processReceipt({ PlayerId = userId, ProductId = a, PurchaseId = b }).Name
		end
		error("StoreQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

-- Reads every live Robux price once (Id 0: Config's fallback price stays). A Retired
-- product is never shown (and is off sale on Roblox), so its price is not read.
local function readPrices()
	local keys: { string } = {}
	for key, row in LIST do
		if row.Retired ~= true then
			table.insert(keys, key)
		end
	end
	table.sort(keys)
	local any = false
	for _, key in keys do
		local row = LIST[key]
		if type(row.Id) == "number" and row.Id > 0 then
			local infoType = if row.Kind == "Pass"
				then Enum.InfoType.GamePass
				else Enum.InfoType.Product
			local ok, info = pcall(function(): any
				return MarketplaceService:GetProductInfoAsync(row.Id, infoType)
			end)
			local price = if ok and type(info) == "table" then info.PriceInRobux else nil
			if type(price) == "number" and price > 0 then
				prices[key] = price
				any = true
			else
				log(("no live price for %s (id %d): showing %d"):format(key, row.Id, row.Robux))
			end
		end
	end
	if any then
		markAll()
	end
end

-- Watches Counters' Limited counts: a new count can sell a Limited out.
local function watchLimitedSold()
	local function watch(child: Instance)
		if child.Name == LIMITED_SOLD then
			child.AttributeChanged:Connect(markAll)
		end
	end
	ReplicatedStorage.ChildAdded:Connect(watch)
	local existing = ReplicatedStorage:FindFirstChild(LIMITED_SOLD)
	if existing then
		watch(existing)
	end
end

-- Every StateTickSeconds: the party's end, a new restock (a Legendary or Mythic block in it
-- is announced here: every server picks the same restock, so every server announces it), and
-- each player's next change.
local function tick()
	local now = os.time()
	local slot = Items.restockSlot(now)
	if slot ~= restockSlot then
		local first = restockSlot < 0
		restockSlot = slot
		markAll()
		local shout = if first then nil else Restock.announced(slot)
		if shout ~= nil then
			local _, endsAt = Restock.window(Restock.slotOf(now))
			Announce.restock(shout, endsAt)
		end
	end
	if partyEndsAt > 0 and now >= partyEndsAt then
		setParty(0, nil)
	end
	-- The Legendary's shared stock changed (a buy here or, read every refresh, elsewhere).
	local stock = Counters.stockTaken(Restock.stockKey(slot))
	if stock ~= stockSeen then
		stockSeen = stock
		markAll()
	end
	for player, at in nextChange do
		if now >= at then
			nextChange[player] = nil
			mark(player)
		end
	end
end

local function onPlayerAdded(player: Player)
	setAttributes(player, nil)
	player:GetAttributeChangedSignal(ATTR.Restricted):Connect(function()
		mark(player)
	end)
	task.spawn(checkPasses, player)
end

local function onPlayerRemoving(player: Player)
	passOwned[player] = nil
	passFake[player] = nil
	passChecked[player] = nil
	actingRegular[player] = nil
	lastRequest[player] = nil
	nextChange[player] = nil
	dirty[player] = nil
	-- A Legendary unit held for a prompt that never finished goes back.
	local pend = pendingRestock[player]
	pendingRestock[player] = nil
	pendingGift[player] = nil
	if pend ~= nil and pend.reserved then
		local userId = player.UserId
		task.spawn(Counters.releaseStock, Restock.stockKey(pend.slot), userId)
	end
end

-- The PlayerData changes that change the shop.
local SHOP_OPS: { [string]: boolean } = {
	applyPurchase = true,
	buyRestock = true,
	buyMystery = true,
	buyBlocks = true,
	openLuckyBlock = true, -- the Mystery block's pity count
	winBlock = true,
	giveVipCue = true,
	buyLimited = true,
	clearInventory = true,
	reset = true,
}

--- Sets ProcessReceipt and connects the passes and remotes (Bootstrap calls this once).
function Store.start()
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = processReceipt
	shopState = Net.get("ShopState")
	giftEvent = Net.get("GiftReceived")
	purchaseEvent = Net.get("PurchaseDone")
	local request: RemoteFunction = Net.get("StoreRequest")
	request.OnServerInvoke = function(player: Player, action: any, key: any, extra: any): Reply
		local ok, result = pcall(onStoreRequest, player, action, key, extra)
		if not ok then
			log(("StoreRequest from %d failed: %s"):format(player.UserId, tostring(result)))
			return reply(false, "Error")
		end
		return result
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchase)
	MarketplaceService.PromptProductPurchaseFinished:Connect(onProductPromptFinished)

	PlayerData.Loaded:Connect(mark)
	PlayerData.Changed:Connect(function(player: Player, op: string)
		if SHOP_OPS[op] then
			mark(player)
		end
	end)
	Items.ShopChanged:Connect(markAll)
	watchLimitedSold()

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
		if PlayerData.isLoaded(player) then
			mark(player)
		end
	end
	task.spawn(readPrices)
	task.spawn(function()
		while true do
			task.wait(S.StateTickSeconds)
			safely("the tick", tick)
		end
	end)
	startQA()
end

return Store
