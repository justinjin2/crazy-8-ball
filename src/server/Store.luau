--!strict
-- Store: Robux products and passes, VIP, the timed offers, the Money Party and Fast Open
-- (ECONOMY section 11; the overnight brief's section 12; docs/ARCHITECTURE.md "The economy").
-- The pure rules are Progression/Shop (offers, grants, the party queue, the once-only receipt
-- logic) and Progression/ShopView (the ShopState payload and the Buy check).
--
-- - ProcessReceipt: one handler, Shop.processReceipt with this server's functions. Player not
--   here or save not loaded: NotProcessedYet. A purchase id already in the save: Granted once
--   its save is written. Otherwise the grant and the id go into the save in ONE PlayerData
--   mutation (applyPurchase), then PlayerData.saveNow waits for a save holding the id, and only
--   then PurchaseGranted. A Robux Limited (the Founder's Cue) takes its copy number from
--   Counters.takeLimited first; sold out, ended, already owned or a counter error leave the
--   receipt NotProcessedYet (logged) rather than acknowledging a purchase that gave nothing;
--   Roblox keeps retrying it.
-- - Game passes (Vip, FastOpen): UserOwnsGamePassAsync on join (pcall, retried, cached; Id 0
--   is never owned) and PromptGamePassPurchaseFinished (on a live server checked with
--   UserOwnsGamePassAsync before it counts, since the event alone is not proof; in Studio it
--   counts at once, as test purchases never show as owned). VIP = owns the pass OR bought the
--   welcome offer: the player attributes Vip and FastOpen (the money and XP boosts, the chat
--   tag and the case opening read them), and the VIP Cue once (PlayerData.giveVipCue).
-- - The Money Party is this server's: workspace attributes MoneyPartyEndsAt (unix) and
--   MoneyPartyBuyer (a username), Announce.party on every purchase; cleared when it ends.
-- - StoreRequest "Buy" (a Config.Products key): checked (ShopView.check), then this server
--   prompts the purchase itself. ShopState goes to each player on load and whenever any of it
--   changes (a purchase, a pass, the restriction, the sale, the party, a Limited count, an
--   offer window opening or closing on the clock).
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
local Inventory = require(Shared.Progression.Inventory)
local PlayerData = require(script.Parent.PlayerData)
local Counters = require(script.Parent.Counters)
local Announce = require(script.Parent.Announce)
local Items = require(script.Parent.Items)

local S = Config.Shop
local IS_STUDIO = RunService:IsStudio()
local LIST: { [string]: { Kind: string, Id: number, Robux: number } } = Config.Products.List :: any

-- Server-set attributes (clients and the other services only read them).
local ATTR = {
	Vip = "Vip", -- on the player: VIP (the pass or the welcome offer)
	FastOpen = "FastOpen", -- on the player: owns Fast Open
	Restricted = "PaidRandomRestricted", -- on the player, set by Items (PolicyService)
	PartyEndsAt = "MoneyPartyEndsAt", -- on workspace: this server's Money Party end, unix
	PartyBuyer = "MoneyPartyBuyer", -- on workspace: the last buyer's username
}
-- The instance Counters keeps the Limited copy counts on (one attribute per Limited cue).
local LIMITED_SOLD = "LimitedSold"
-- A dev grant's purchase id starts with this (never a Roblox receipt's).
local DEV_PREFIX = "Dev-"

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

local started = false
local shopState: RemoteEvent? = nil

-- Game passes: what Roblox said each player owns, the dev overrides (/vip, /fastopen), and
-- whether the join check finished (the VIP Cue waits for it).
local passOwned: { [Player]: { [string]: boolean } } = {}
local passFake: { [Player]: { [string]: boolean } } = {}
local passChecked: { [Player]: boolean } = {}
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
-- The last case sale seen (its fields joined), to notice a change.
local saleKey = ""
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

local function owns(player: Player, passKey: string): boolean
	local fake = passFake[player]
	if fake ~= nil and fake[passKey] ~= nil then
		return fake[passKey]
	end
	local real = passOwned[player]
	return real ~= nil and real[passKey] == true
end

-- The case sale running now (Items.sale: Config.Cases.Sale, or the /sale dev command's).
local function currentSale(now: number): ShopView.Sale?
	local ok, sale = pcall(Items.sale)
	return if ok then ShopView.readSale(sale, now) else nil
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

-- Everything ShopView needs for this player now; nil while the save is not loaded.
local function context(player: Player, now: number): ShopView.Context?
	local data = PlayerData.read(player)
	if data == nil then
		return nil
	end
	return {
		now = now,
		shop = data.Shop,
		vipPass = owns(player, "Vip"),
		fastOpen = owns(player, "FastOpen"),
		restricted = player:GetAttribute(ATTR.Restricted) == true,
		partyEndsAt = partyEndsAt,
		partyBuyer = partyBuyer,
		sale = currentSale(now),
		sold = limitedSold(),
		prices = prices,
	}
end

-- Sets Vip and FastOpen from the passes and the save (the save may not be loaded yet).
local function setAttributes(player: Player, shopSave: any?)
	local vip = Shop.isVip(owns(player, "Vip"), shopSave)
	if player:GetAttribute(ATTR.Vip) ~= vip then
		player:SetAttribute(ATTR.Vip, vip)
	end
	local fastOpen = owns(player, "FastOpen")
	if player:GetAttribute(ATTR.FastOpen) ~= fastOpen then
		player:SetAttribute(ATTR.FastOpen, fastOpen)
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
				owned[key] = answer
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
	end
end

-- A pass purchase finished in this server: counted once Roblox confirms the ownership (the
-- event alone is not proof on a live server). In Studio a test purchase never shows in
-- UserOwnsGamePassAsync, so there the event counts for the session.
local function onPassPurchase(player: Player, passId: number, purchased: boolean)
	if not purchased then
		return
	end
	local key = Shop.passKeyForId(passId)
	if key == nil then
		return
	end
	local function count()
		local owned = passOwned[player] or {}
		passOwned[player] = owned
		owned[key] = true
		mark(player)
	end
	if IS_STUDIO then
		count()
		return
	end
	for try = 1, S.PassCheckTries do
		if not present(player) then
			return
		end
		if askPass(player, key) == true then
			count()
			return
		end
		if try < S.PassCheckTries then
			task.wait(S.PassRetrySeconds)
		end
	end
	log(
		("pass %s for %d not confirmed by Roblox; checked again on the next join"):format(
			key,
			player.UserId
		)
	)
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

-- One more Money Party purchase by `buyer` (Shop.partyEndsAt: 15 more minutes, at most an hour
-- queued), announced to everyone here. Returns the new end.
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
-- server, else the next one from the shared counter (yields). nil and a reason when none.
local function copyFor(cueId: string, purchaseId: string): (number?, string?)
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
		row.Cap or Config.Save.CopyNumberCap,
		row.StartsAt + row.Seconds
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

-- Grants developer product `key` to `player` and records `purchaseId`, in one PlayerData
-- mutation (Shop.processReceipt's `grant`). True once granted (now, or by a concurrent try of
-- the same receipt); false and a reason otherwise (the receipt stays NotProcessedYet).
local function grantProduct(player: Player, key: string, purchaseId: string): (boolean, string?)
	local data = PlayerData.read(player)
	if data == nil then
		return false, "NotLoaded"
	end
	local grant = Shop.grantFor(key, data.Shop, os.time())
	if grant == nil then
		return false, "Unknown"
	end
	local copy: number? = nil
	local limited = grant.limited
	if limited ~= nil then
		if data.Shop.Limited[limited] ~= nil or Inventory.owns(data, limited) then
			return false, "Owned"
		end
		local number, why = copyFor(limited, purchaseId)
		if number == nil then
			return false, why
		end
		copy = number
		-- The counter yielded: the player may have left, or another try granted it meanwhile.
		if PlayerData.hasPurchase(player, purchaseId) then
			pendingCopies[purchaseId] = nil
			return true, nil
		end
		if not ready(player) then
			return false, "NotLoaded"
		end
	end
	-- The copies in existence: a granted cue (the Starter Cue, a Limited) counts once it lands.
	local cueBefore = if grant.cue ~= nil then Inventory.count(data, grant.cue) else 0
	if not PlayerData.applyPurchase(player, purchaseId, grant, copy) then
		return false, "Failed"
	end
	pendingCopies[purchaseId] = nil
	local after = PlayerData.read(player)
	if grant.cue ~= nil and after ~= nil and Inventory.count(after, grant.cue) > cueBefore then
		Counters.add(grant.cue, 1)
	end
	if limited ~= nil then
		Counters.add(limited, 1)
	end
	if grant.party then
		addParty(player)
	end
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
			local ok, reason = grantProduct(player, productKey, id)
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

local function onStoreRequest(player: Player, action: any, key: any): Reply
	if action ~= "Buy" or type(key) ~= "string" or LIST[key] == nil then
		return reply(false, "BadRequest")
	end
	local clock = os.clock()
	local last = lastRequest[player]
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
	local reason = ShopView.check(key, ctx)
	if reason ~= nil then
		return reply(false, reason)
	end
	if not prompt(player, key) then
		return reply(false, "Error")
	end
	return reply(true)
end

---------------------------------------------------------------------------------------------
-- Dev (the /buy, /vip, /fastopen and /party commands; the Studio QA hook)
---------------------------------------------------------------------------------------------

--- Dev (/buy): grants Config.Products key `key` exactly as a receipt would (the same
--- Shop.processReceipt, grant, record and save), with `purchaseId` or a new fake one, so the
--- same id grants once. A pass key turns that pass on (Store.setPass). Yields until the save.
--- Returns (true) or (false, reason): "Unknown" (no such key), "NotLoaded", "Owned" (a Limited
--- already owned), "SoldOut", "Ended", "Closed", "Busy", "Error" (the Limited counter),
--- "Failed" (the mutation refused), "SaveFailed".
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

--- Dev (/vip, /fastopen): pretends the player owns (`on`) or does not own game pass `passKey`
--- ("Vip" or "FastOpen") for this session, whatever Roblox says. True when it is a pass key.
function Store.setPass(player: Player, passKey: string, on: boolean): boolean
	local row = LIST[passKey]
	if row == nil or row.Kind ~= "Pass" or typeof(player) ~= "Instance" then
		return false
	end
	local fake = passFake[player] or {}
	passFake[player] = fake
	fake[passKey] = on == true
	passChecked[player] = true
	mark(player)
	return true
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

--- Sends the player's ShopState again (and refreshes Vip and FastOpen).
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

-- Reads every live Robux price once (Id 0: Config's fallback price stays).
local function readPrices()
	local keys: { string } = {}
	for key in LIST do
		table.insert(keys, key)
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

-- Every StateTickSeconds: the party's end, a sale changing, and each player's next change.
local function tick()
	local now = os.time()
	if partyEndsAt > 0 and now >= partyEndsAt then
		setParty(0, nil)
	end
	local sale = currentSale(now)
	local key = if sale ~= nil
		then ("%s:%s:%d"):format(sale.case, tostring(sale.percent), sale.endsAt)
		else ""
	if key ~= saleKey then
		saleKey = key
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
	lastRequest[player] = nil
	nextChange[player] = nil
	dirty[player] = nil
end

-- The PlayerData changes that change the shop.
local SHOP_OPS: { [string]: boolean } = {
	applyPurchase = true,
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
	local request: RemoteFunction = Net.get("StoreRequest")
	request.OnServerInvoke = function(player: Player, action: any, key: any): Reply
		local ok, result = pcall(onStoreRequest, player, action, key)
		if not ok then
			log(("StoreRequest from %d failed: %s"):format(player.UserId, tostring(result)))
			return reply(false, "Error")
		end
		return result
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchase)

	PlayerData.Loaded:Connect(mark)
	PlayerData.Changed:Connect(function(player: Player, op: string)
		if SHOP_OPS[op] then
			mark(player)
		end
	end)
	Items.SaleChanged:Connect(markAll)
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
