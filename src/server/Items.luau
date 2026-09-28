--!strict
-- Items: the inventory service (docs/ARCHITECTURE.md, "The economy"; the protocol is written
-- next to ItemRequest and ItemState in src/shared/Net.luau).
--
-- - ItemRequest (a RemoteFunction): the client names an action with ids and counts only; this
--   module checks everything, prices and rolls on the server, changes the save through
--   PlayerData's mutations and answers { ok = true, ... } or { ok = false, reason }. It never
--   errors back to the client. The order of the checks: the player's token bucket
--   (Config.Items.RateBurst, RatePerSecond), the arguments (Progression/Requests.parse), the
--   save (loaded, not handed off for a teleport), then one request per player at a time (a
--   lock, so two racing requests can never spend the same money or open the same case).
-- - ItemState (a RemoteEvent): the player's inventory snapshot (PlayerData.snapshot) when the
--   save loads and after every change that touches it, at most once a frame per player, and
--   only when it differs from the last one sent.
-- - PolicyService (ECONOMY 13): asked on join. Player attributes PaidRandomRestricted (no cases
--   for money; free cases still open) and PaidItemTradingAllowed (kept for trading). Studio is
--   never restricted; Items.setRestricted is the /policy dev command's.
-- - The case sale (ECONOMY 9.1): at most one, from Config.Cases.Sale, changed at runtime by
--   Items.setSale (the /sale dev command). Mirrored on ReplicatedStorage attributes CaseSale,
--   CaseSalePercent and CaseSaleEndsAt; Items.SaleChanged fires on every change and when it
--   ends, so the Store can send ShopState again.
-- - Copies in existence move with every open, sale and Limited buy (Counters.add); a Mythic or
--   Secret unboxed is announced (Announce.unbox).
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Catalog = require(Shared.Progression.Catalog)
local Cases = require(Shared.Progression.Cases)
local Inventory = require(Shared.Progression.Inventory)
local Requests = require(Shared.Progression.Requests)
local Shop = require(Shared.Progression.Shop)
local Announce = require(script.Parent.Announce)
local Counters = require(script.Parent.Counters)
local PlayerData = require(script.Parent.PlayerData)

local I = Config.Items
local IS_STUDIO = RunService:IsStudio()

-- Player attributes this module owns (server-set; clients only read them).
local ATTR = {
	Restricted = "PaidRandomRestricted", -- no cases for money (ECONOMY 13)
	Trading = "PaidItemTradingAllowed", -- paid item trading allowed (for trading, later)
}
-- Read from other modules' attributes.
local FAST_OPEN = "FastOpen" -- the Store's: owns the Fast Open pass
local MONEY = "Money" -- PlayerData's: the save's money
-- The sale's mirror on ReplicatedStorage.
local SALE_ATTR = { Case = "CaseSale", Percent = "CaseSalePercent", EndsAt = "CaseSaleEndsAt" }

-- PlayerData mutations that never touch the inventory snapshot, so they push nothing (the
-- frequent ones: playtime every Config.Daily.PlaytimeTickSeconds, every shot, money).
local QUIET_OPS: { [string]: boolean } = {
	addPlaySeconds = true,
	setPlayMinutes = true,
	recordShot = true,
	addMoney = true,
	addDailyMoney = true,
	spend = true,
	setMoney = true,
	recordMatch = true,
	endStreak = true,
	recordRealMatch = true,
	useFirstWin = true,
	addOpponentCase = true,
	setRealMatches = true,
}

export type Reply = { [string]: any }
export type Sale = Cases.Sale

local Items = {}

local saleEvent = Instance.new("BindableEvent")
--- () Fires when the case sale changes or ends (Items.sale() is the new one, or nil).
Items.SaleChanged = saleEvent.Event
local policyEvent = Instance.new("BindableEvent")
--- (player) Fires when a player's PolicyService answer arrives or /policy changes it.
Items.PolicyChanged = policyEvent.Event

type Policy = { restricted: boolean, trading: boolean }

local buckets: { [Player]: Requests.Bucket } = {}
local busy: { [Player]: boolean } = {}
local policies: { [Player]: Policy } = {}
local dirty: { [Player]: boolean } = {} -- a snapshot push is due at the next Heartbeat
local lastSent: { [Player]: string } = {} -- the last snapshot sent, encoded
local sale: Sale? = nil
local saleVersion = 0 -- bumped by every change, so an old sale's end timer does nothing
local rolls = Random.new()

local function refuse(reason: string, extra: { [string]: any }?): Reply
	local reply: Reply = { ok = false, reason = reason }
	if extra then
		for key, value in extra do
			reply[key] = value
		end
	end
	return reply
end

local function who(player: Player): string
	return ("%s (%d)"):format(player.Name, player.UserId)
end

---------------------------------------------------------------------------------------------
-- The snapshot push (ItemState)
---------------------------------------------------------------------------------------------

--- Sends the player's inventory snapshot at the next Heartbeat (Items does this itself on load
--- and after every change; other services only need it after something unusual).
function Items.push(player: Player)
	dirty[player] = true
end

local function send(player: Player)
	if player.Parent ~= Players then
		return
	end
	local snapshot = PlayerData.snapshot(player)
	if snapshot == nil then
		return
	end
	local encoded, text = pcall(HttpService.JSONEncode, HttpService, snapshot)
	if encoded and lastSent[player] == text then
		return
	end
	lastSent[player] = if encoded then text else nil
	local remote = Net.get("ItemState") :: RemoteEvent
	remote:FireClient(player, snapshot)
end

local function flushPushes()
	if next(dirty) == nil then
		return
	end
	local due = dirty
	dirty = {}
	for player in due do
		local ok, err = pcall(function(): any
			send(player)
			return nil
		end)
		if not ok then
			warn(
				("[8ball] Items: the snapshot for %s failed: %s"):format(who(player), tostring(err))
			)
		end
	end
end

---------------------------------------------------------------------------------------------
-- PolicyService (ECONOMY 13)
---------------------------------------------------------------------------------------------

local function setPolicy(player: Player, restricted: boolean, trading: boolean)
	policies[player] = { restricted = restricted, trading = trading }
	player:SetAttribute(ATTR.Restricted, restricted)
	player:SetAttribute(ATTR.Trading, trading)
	policyEvent:Fire(player)
end

local function loadPolicy(player: Player)
	if IS_STUDIO then
		setPolicy(player, false, true)
		return
	end
	for attempt = 1, I.PolicyRetries do
		local ok, info = pcall(function(): any
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		if player.Parent ~= Players then
			return
		end
		if ok and type(info) == "table" then
			setPolicy(
				player,
				info.ArePaidRandomItemsRestricted == true,
				info.IsPaidItemTradingAllowed == true
			)
			return
		end
		warn(
			("[8ball] Items: PolicyService for %s failed (%d): %s"):format(
				who(player),
				attempt,
				tostring(info)
			)
		)
		if attempt < I.PolicyRetries then
			task.wait(I.PolicyRetrySeconds)
		end
	end
	-- Never answered: the cautious answer for this session.
	setPolicy(player, true, false)
end

--- Whether paid random items are restricted for the player (no cases for money): nil while
--- PolicyService has not answered yet.
function Items.isRestricted(player: Player): boolean?
	local policy = policies[player]
	return if policy then policy.restricted else nil
end

--- Whether paid item trading is allowed for the player: nil while PolicyService has not answered.
function Items.tradingAllowed(player: Player): boolean?
	local policy = policies[player]
	return if policy then policy.trading else nil
end

--- The /policy dev command: paid random items restricted (or not) for this player, as if
--- PolicyService had said so. Trading follows the player's current answer.
function Items.setRestricted(player: Player, on: boolean)
	if not (typeof(player) == "Instance" and player:IsA("Player")) or type(on) ~= "boolean" then
		warn("[8ball] Items.setRestricted: bad arguments")
		return
	end
	local policy = policies[player]
	setPolicy(player, on, if policy then policy.trading else not on)
end

---------------------------------------------------------------------------------------------
-- The case sale (ECONOMY 9.1)
---------------------------------------------------------------------------------------------

local function mirrorSale()
	local current = Items.sale()
	ReplicatedStorage:SetAttribute(SALE_ATTR.Case, if current then current.Case else nil)
	ReplicatedStorage:SetAttribute(SALE_ATTR.Percent, if current then current.Percent else nil)
	ReplicatedStorage:SetAttribute(SALE_ATTR.EndsAt, if current then current.EndsAt else nil)
end

-- A sale's own check: a case sold in the shop, a whole percent 1..Config.Cases.MaxSalePercent
-- off (past it, buying cases and selling back what they drop would make money), an end in the
-- future.
local function validSale(caseId: any, percent: any, endsAt: any, now: number): boolean
	local case = Cases.get(caseId)
	return case ~= nil
		and case.Enabled
		and type(percent) == "number"
		and percent == math.floor(percent)
		and percent >= 1
		and percent <= Config.Cases.MaxSalePercent
		and type(endsAt) == "number"
		and endsAt == endsAt
		and endsAt > now
		and endsAt < Config.Save.UnixTimeCap
end

-- Puts a sale on (or none) and times its end.
local function applySale(value: Sale?)
	sale = value
	saleVersion += 1
	local version = saleVersion
	mirrorSale()
	saleEvent:Fire()
	if value then
		task.delay(math.max(0, value.EndsAt - os.time()), function()
			if saleVersion == version then
				sale = nil
				saleVersion += 1
				mirrorSale()
				saleEvent:Fire()
			end
		end)
	end
end

--- The case sale on now ({ Case, Percent, EndsAt }, a fresh table), or nil: none, or it ended.
function Items.sale(): Sale?
	local current = sale
	if current == nil or os.time() >= current.EndsAt then
		return nil
	end
	return { Case = current.Case, Percent = current.Percent, EndsAt = current.EndsAt }
end

--- The /sale dev command: `percent` off case `caseId` until `endsAt` (unix), replacing any
--- sale; a nil or "" caseId ends the sale. True when done; false (logged) for a case not sold
--- in the shop, a percent that is not a whole 1..Config.Cases.MaxSalePercent, or an end not in
--- the future.
function Items.setSale(caseId: string?, percent: number?, endsAt: number?): boolean
	if caseId == nil or caseId == "" then
		applySale(nil)
		return true
	end
	if not validSale(caseId, percent, endsAt, os.time()) then
		warn(
			("[8ball] Items.setSale: refused %s %s%% until %s"):format(
				tostring(caseId),
				tostring(percent),
				tostring(endsAt)
			)
		)
		return false
	end
	applySale({ Case = caseId, Percent = percent :: number, EndsAt = endsAt :: number })
	return true
end

---------------------------------------------------------------------------------------------
-- The actions
---------------------------------------------------------------------------------------------

local function moneyOf(player: Player): number
	local money = player:GetAttribute(MONEY)
	return if type(money) == "number" then money else 0
end

local function roll(n: number): number
	return rolls:NextInteger(1, n)
end

local HANDLERS: { [string]: (Player, Requests.Request) -> Reply } = {}

function HANDLERS.BuyCase(player: Player, r: Requests.Request): Reply
	local caseId, count = r.caseId :: string, r.count :: number
	local restricted = Items.isRestricted(player)
	if restricted == nil then
		return refuse("NotLoaded") -- PolicyService has not answered yet
	elseif restricted then
		return refuse("Restricted")
	end
	local price, perCase, onSale = Cases.price(caseId, count, os.time(), Items.sale())
	if PlayerData.buyCases(player, caseId, count, price) then
		return {
			ok = true,
			caseId = caseId,
			count = count,
			price = price,
			perCase = perCase,
			onSale = onSale,
		}
	end
	local money = moneyOf(player)
	if money < price then
		return refuse("NotEnoughMoney", { need = price - money, price = price })
	end
	return refuse("Error")
end

function HANDLERS.OpenCase(player: Player, r: Requests.Request): Reply
	local caseId, count = r.caseId :: string, r.count :: number
	if count > 1 and player:GetAttribute(FAST_OPEN) ~= true then
		return refuse("NoFastOpen")
	end
	local cueIds = {}
	for _ = 1, count do
		table.insert(cueIds, (Cases.roll(caseId, roll)))
	end
	local ok, result = PlayerData.openCases(player, caseId, cueIds)
	if not ok then
		return refuse(Requests.reasonFrom(result))
	end
	local results = {}
	for _, opened in result :: { any } do
		local cue = Catalog.get(opened.cue) :: Catalog.Cue
		Counters.add(cue.Id, 1)
		Announce.unbox(player, cue.Id)
		table.insert(results, {
			cue = cue.Id,
			rarity = cue.Rarity,
			new = opened.new,
			duplicate = opened.duplicate,
			count = opened.count,
		})
	end
	return { ok = true, caseId = caseId, results = results }
end

function HANDLERS.SellCue(player: Player, r: Requests.Request): Reply
	local cueId, count = r.cueId :: string, r.count :: number
	local ok, result = PlayerData.sellCue(player, cueId, count)
	if not ok then
		return refuse(Requests.reasonFrom(result))
	end
	Counters.add(cueId, -count)
	return { ok = true, cueId = cueId, count = count, money = result }
end

function HANDLERS.SellDuplicates(player: Player, r: Requests.Request): Reply
	local ok, money, sold = PlayerData.sellDuplicates(player, r.cueId)
	if not ok then
		return refuse("Error")
	end
	local rows = {}
	for _, row in sold do
		Counters.add(row.id, -row.count)
		table.insert(rows, { id = row.id, count = row.count, money = row.money })
	end
	return { ok = true, money = money, sold = rows }
end

function HANDLERS.EquipCue(player: Player, r: Requests.Request): Reply
	local cueId = r.cueId :: string
	if not PlayerData.equipCue(player, cueId) then
		return refuse("NotOwned")
	end
	return { ok = true, cueId = cueId }
end

function HANDLERS.MarkSeen(player: Player, r: Requests.Request): Reply
	local ids = r.ids :: { string }
	local cleared = if #ids > 0 then PlayerData.markSeen(player, ids) else 0
	return { ok = true, cleared = cleared }
end

function HANDLERS.ClaimIndexRow(player: Player, r: Requests.Request): Reply
	local rarity = r.rarity :: string
	local ok, result = PlayerData.claimIndexRow(player, rarity)
	if not ok then
		return refuse(Requests.reasonFrom(result))
	end
	return { ok = true, rarity = rarity, money = result.money, title = result.title }
end

function HANDLERS.BuyLimited(player: Player, r: Requests.Request): Reply
	local cueId = r.cueId :: string
	local row = Shop.limitedFor(cueId) :: Shop.LimitedRow
	local price = row.Price :: number
	local data = PlayerData.read(player)
	if data == nil then
		return refuse("NotLoaded")
	end
	local limited = if type(data.Shop) == "table" then data.Shop.Limited else nil
	local owned = Inventory.owns(data, cueId)
		or (type(limited) == "table" and limited[cueId] ~= nil)
	local why, endsAt = Requests.limitedCheck(row, os.time(), Counters.limitedSold(cueId), owned)
	if why then
		return refuse(why)
	end
	-- The money is checked before a number is taken, and taken only after one is given. The
	-- number is this player's for good (the counter remembers who got it), so a buy that does
	-- not land (they left while it was taken) gets the same number on a retry or a rejoin.
	if data.Money < price then
		return refuse("NotEnoughMoney", { need = price - data.Money, price = price })
	end
	local copy, reason =
		Counters.takeLimited(cueId, player.UserId, row.Cap or Config.Save.CopyNumberCap, endsAt)
	if copy == nil then
		return refuse(reason or "Error")
	end
	if not PlayerData.buyLimited(player, cueId, copy, price) then
		warn(
			("[8ball] Items: %s's buy of %s copy #%d failed after the number was taken; it stays theirs for a retry"):format(
				who(player),
				cueId,
				copy
			)
		)
		return refuse("Error")
	end
	Counters.add(cueId, 1)
	return { ok = true, cueId = cueId, copy = copy, price = price }
end

-- One request, start to finish. Never errors.
local function handle(player: Player, action: any, a: any, b: any): Reply
	local bucket = buckets[player]
	if bucket == nil then
		bucket = Requests.newBucket(os.clock())
		buckets[player] = bucket
	end
	if not Requests.take(bucket, os.clock()) then
		return refuse("TooFast")
	end
	local request, why = Requests.parse(action, a, b)
	if request == nil then
		return refuse(why or "BadRequest")
	elseif PlayerData.isHandedOff(player) then
		return refuse("Teleporting")
	elseif not PlayerData.isLoaded(player) then
		return refuse("NotLoaded")
	elseif busy[player] then
		return refuse("Busy")
	end
	busy[player] = true
	local ok, reply = pcall(HANDLERS[request.action], player, request)
	busy[player] = nil
	if not ok then
		warn(
			("[8ball] Items: %s for %s failed: %s"):format(
				request.action,
				who(player),
				tostring(reply)
			)
		)
		return refuse("Error")
	end
	return reply
end

---------------------------------------------------------------------------------------------
-- Studio QA
---------------------------------------------------------------------------------------------

-- Studio only: ServerStorage.ItemsQA, a BindableFunction that runs inside this module (the
-- MCP's execute_luau gets its own copies of modules). Clients cannot reach ServerStorage, and
-- nothing is made in a live server. Invoke(op, ...):
--   "request", userId, action, a?, b?  -> the ItemRequest reply, exactly as the remote answers
--   "push", userId                     -> sends the snapshot again (even if unchanged)
--   "policy", userId                   -> { restricted, trading } or nil
--   "setRestricted", userId, on        -> as /policy
--   "sale" / "setSale", caseId?, percent, endsAt
--   "copies", cueId / "limitedSold", cueId / "flush" / "refresh"
--   "takeLimited", cueId, userId, cap, endsAt -> copy, reason (a real number in the Studio
--                                      store, recorded under that userId)
--   "claimFirst", key, userId / "first", key
--   "unbox", userId, cueId / "reyes", userId / "party", endsAt, name
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("ItemsQA")
	if old then
		old:Destroy()
	end
	local function playerOf(userId: any): Player
		local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		assert(player, "ItemsQA: no player in game with that UserId")
		return player
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "ItemsQA"
	hook.OnInvoke = function(op: string, a: any, b: any, c: any, d: any): ...any
		if op == "request" then
			return handle(playerOf(a), b, c, d)
		elseif op == "push" then
			local player = playerOf(a)
			lastSent[player] = nil
			send(player)
			return true
		elseif op == "policy" then
			local policy = policies[playerOf(a)]
			return if policy then table.clone(policy) else nil
		elseif op == "setRestricted" then
			Items.setRestricted(playerOf(a), b == true)
			return Items.isRestricted(playerOf(a))
		elseif op == "sale" then
			return Items.sale()
		elseif op == "setSale" then
			return Items.setSale(a, b, c)
		elseif op == "copies" then
			return Counters.copies(a)
		elseif op == "limitedSold" then
			return Counters.limitedSold(a)
		elseif op == "flush" then
			return Counters.flush()
		elseif op == "refresh" then
			return Counters.refresh()
		elseif op == "takeLimited" then
			return Counters.takeLimited(a, b, c, d)
		elseif op == "claimFirst" then
			return Counters.claimFirst(a, b)
		elseif op == "first" then
			return Counters.first(a)
		elseif op == "unbox" then
			Announce.unbox(playerOf(a), b)
			return true
		elseif op == "reyes" then
			Announce.reyes(playerOf(a))
			return true
		elseif op == "party" then
			Announce.party(a, b)
			return true
		end
		error("ItemsQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

local started = false

--- Connects the remotes and the snapshot pushes (Bootstrap calls this once).
function Items.start()
	if started then
		return
	end
	started = true
	local initial = Config.Cases.Sale
	if validSale(initial.Case, initial.Percent, initial.EndsAt, os.time()) then
		applySale({ Case = initial.Case, Percent = initial.Percent, EndsAt = initial.EndsAt })
	else
		mirrorSale()
	end

	local remote = Net.get("ItemRequest") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, action: any, a: any, b: any): Reply
		local ok, reply = pcall(handle, player, action, a, b)
		if not ok then
			warn(
				("[8ball] Items: a request from %s failed: %s"):format(who(player), tostring(reply))
			)
			return refuse("Error")
		end
		return reply
	end

	PlayerData.Loaded:Connect(function(player: Player)
		lastSent[player] = nil
		dirty[player] = true
	end)
	PlayerData.Changed:Connect(function(player: Player, op: string)
		if not QUIET_OPS[op] then
			dirty[player] = true
		end
	end)
	RunService.Heartbeat:Connect(flushPushes)

	local function joined(player: Player)
		task.spawn(loadPolicy, player)
		if PlayerData.isLoaded(player) then
			dirty[player] = true
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
		busy[player] = nil
		policies[player] = nil
		dirty[player] = nil
		lastSent[player] = nil
	end)
	startQA()
end

return Items
