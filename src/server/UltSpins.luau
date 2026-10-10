--!strict
-- UltSpins: the ult spin screen's server (docs/prompts/ULTIMATES_PROMPT.md sections 8-10; the
-- protocol is written next to UltRequest and UltState in src/shared/Net.luau). The pure half
-- is Ults/SpinView (argument checks, one spin, the payload); the
-- save changes are PlayerData's ult mutations (one mutation per spin: take, roll, place, pity
-- and SpinsDone together). Started by Rewards.start.
--
-- - UltRequest (a RemoteFunction): the client names a kind and its choices only; the server
--   checks, rolls with its own Random and saves BEFORE it answers, so the client only plays
--   what it was sent. The order of the checks: the player's token bucket
--   (Config.Ults.RequestBurst, refilled one every RequestCooldownSeconds), the arguments
--   (SpinView.parse), the save (loaded, not handed off), then one request per player at a time
--   (a lock, so two spins can never race).
-- - Spins and money packs need the screen to be live (Config.Ults.ScreenLive, Studio, or the
--   player's developer flag); selecting and locking slots always work.
-- - PolicyService (ECONOMY 11.7, 13): where paid random items are restricted (Items'
--   PaidRandomRestricted), money spins, the R$ spin packs and Lucky Spins are refused; a player
--   PolicyService has not answered yet is refused "NotLoaded". Free spins, codes and grants
--   still work.
-- - Auto Spin was removed from the game (designer, 2026-10-10); VIP's Fast spin is the
--   client's alone (the result lands at once).
-- - A Legendary roll is a banner in this server, a Mythic one in every server (Announce.ult).
-- - The developer flag (`/ultsall on`, UltSpins.setDevAll; or Config.Ults.DevAllUlts): every
--   ult rolls and plays. Mirrored on the player attribute UltDevAll. PlayerData.setUltAccess
--   gets the passes and the flag, so the UltEquipped attribute is always right.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Daily = require(Shared.Progression.Daily)
local Requests = require(Shared.Progression.Requests)
local UltCatalog = require(Shared.Ults.Catalog)
local SpinView = require(Shared.Ults.SpinView)
local Roll = require(Shared.Ults.Roll)
local PlayerData = require(script.Parent.PlayerData)
local Funnel = require(script.Parent.Funnel)
local Store = require(script.Parent.Store)
local Items = require(script.Parent.Items)
local Announce = require(script.Parent.Announce)

local U = Config.Ults
local IS_STUDIO = RunService:IsStudio()
local VIP_ATTR = "Vip" -- the Store's attribute: VIP (Fast spin and fast reveals are VIP perks)
local DEV_ALL_ATTR = "UltDevAll" -- on the player: the developer flag is on for them

export type Reply = { [string]: any }

local UltSpins = {}

local started = false
local closing = false
local rng = Random.new()
local buckets: { [Player]: Requests.Bucket } = {}
local busy: { [Player]: boolean } = {}
local devAll: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local lastSent: { [Player]: string } = {}
local flushQueued = false

local function log(message: string)
	warn("[8ball] UltSpins: " .. message)
end

local function who(player: Player): string
	return ("%s (%d)"):format(player.Name, player.UserId)
end

local function refuse(reason: string, extra: { [string]: any }?): Reply
	local reply: Reply = { ok = false, reason = reason }
	if extra then
		for key, value in extra do
			reply[key] = value
		end
	end
	return reply
end

-- A number in [0, 1) from the server's Random (Roll.roll's rng).
local function roll01(): number
	return rng:NextNumber()
end

local function today(): number
	return Daily.dayOf(os.time())
end

-- The player's save is loaded here and not handed off for a teleport.
local function ready(player: Player): boolean
	return PlayerData.isLoaded(player) and not PlayerData.isHandedOff(player)
end

---------------------------------------------------------------------------------------------
-- What the player may use
---------------------------------------------------------------------------------------------

-- The ult slot passes owned ({ UltSlot2 = true, UltSlot3 = false }).
local function passesOf(player: Player): { [string]: boolean }
	local passes: { [string]: boolean } = {}
	for _, key in U.SlotPasses do
		if key ~= "" then
			passes[key] = Store.ownsPass(player, key)
		end
	end
	return passes
end

local function devAllOf(player: Player): boolean
	return U.DevAllUlts or devAll[player] == true
end

local function isLive(player: Player): boolean
	return U.ScreenLive or IS_STUDIO or devAllOf(player)
end

-- Paid random items restricted: true, false, or nil while PolicyService has not answered.
local function restrictedOf(player: Player): boolean?
	return Items.isRestricted(player)
end

-- Hands PlayerData the passes and the developer flag (the UltEquipped attribute follows).
local function syncAccess(player: Player)
	if player.Parent == Players then
		PlayerData.setUltAccess(player, passesOf(player), devAllOf(player))
	end
end

---------------------------------------------------------------------------------------------
-- The state (UltState)
---------------------------------------------------------------------------------------------

-- The UltState payload for this player now; nil while the save is not loaded.
local function build(player: Player): SpinView.Payload?
	local ults = PlayerData.ults(player)
	if ults == nil then
		return nil
	end
	return SpinView.state({
		ults = ults,
		day = today(),
		passes = passesOf(player),
		devAll = devAllOf(player),
		live = isLive(player),
		restricted = restrictedOf(player) ~= false,
		vip = player:GetAttribute(VIP_ATTR) == true,
		prices = Store.prices(),
	})
end

-- Sends the player's UltState when it differs from the last one sent.
local function send(player: Player)
	if player.Parent ~= Players or not ready(player) then
		return
	end
	local payload = build(player)
	if payload == nil then
		return
	end
	local encoded, text = pcall(HttpService.JSONEncode, HttpService, payload)
	if encoded and lastSent[player] == text then
		return
	end
	lastSent[player] = if encoded then text else nil
	local remote = Net.get("UltState") :: RemoteEvent
	remote:FireClient(player, payload)
end

local function flush()
	flushQueued = false
	local list: { Player } = {}
	for player in dirty do
		table.insert(list, player)
	end
	table.clear(dirty)
	for _, player in list do
		local ok, err = pcall(function(): any
			send(player)
			return nil
		end)
		if not ok then
			log(("sending the state of %s failed: %s"):format(who(player), tostring(err)))
		end
	end
end

-- Marks a player's UltState due; everything marked in one frame goes out once.
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
-- Spins
---------------------------------------------------------------------------------------------

-- PlayerData's and Slots' answers as the remote's reasons.
local REASONS: { [string]: string } = {
	Invalid = "BadRequest",
	BadSlot = "BadRequest",
	BadValue = "BadRequest",
	BadData = "Error",
	BadDay = "Error",
	BadCount = "Error",
	UnknownUlt = "Error",
}

local function reasonFrom(reason: any): string
	if type(reason) ~= "string" then
		return "Error"
	end
	return REASONS[reason] or reason
end

-- One spin through PlayerData (the caller holds the player's lock). Returns (true, the
-- result) or (false, reason, the ult a "Confirm" would replace). A Legendary or Mythic result
-- is announced.
-- The tutorial lane: the ult a player's next normal spin lands on (its first spin: Magnet),
-- and a call after each spin (TutorialService). Nil: none.
local spinForce: ((Player) -> string?)? = nil
local onSpun: ((Player, string) -> ())? = nil

--- The tutorial lane's hooks on spins (see above).
function UltSpins.setSpinHooks(force: ((Player) -> string?)?, spun: ((Player, string) -> ())?)
	spinForce, onSpun = force, spun
end

local function spinOnce(player: Player, lucky: boolean, confirm: boolean): (boolean, any, string?)
	local forced = if spinForce and not lucky then spinForce(player) else nil
	local ok, result, current = PlayerData.ultSpin(
		player,
		lucky,
		confirm,
		passesOf(player),
		devAllOf(player),
		roll01,
		forced
	)
	if not ok then
		return false, reasonFrom(result), current
	end
	if onSpun then
		task.spawn(onSpun, player, result.id)
	end
	-- A placeholder rolled with the developer flag is never news.
	if UltCatalog.built(result.id) then
		Announce.ult(player, result.id)
	end
	return true, result, nil
end

-- A spin result as a reply (the caller adds its own fields).
local function resultFields(result: SpinView.SpinResult, player: Player): Reply
	return {
		id = result.id,
		rarity = result.rarity,
		replaced = result.replaced,
		wasPity = result.wasPity,
		used = result.used,
		slot = result.slot,
		pity = result.pity,
		state = build(player),
	}
end

---------------------------------------------------------------------------------------------
-- UltRequest
---------------------------------------------------------------------------------------------

local HANDLERS: { [string]: (Player, SpinView.Request) -> Reply } = {}

function HANDLERS.Spin(player: Player, r: SpinView.Request): Reply
	if not isLive(player) then
		return refuse("NotLive")
	end
	local ok, result, current = spinOnce(player, r.lucky == true, r.confirm == true)
	if not ok then
		if result == "Confirm" then
			return refuse("Confirm", { current = current, rarity = UltCatalog.rarity(current) })
		end
		return refuse(result)
	end
	local reply = resultFields(result, player)
	reply.ok = true
	return reply
end

function HANDLERS.Select(player: Player, r: SpinView.Request): Reply
	local ok, reason = PlayerData.ultSelect(player, r.slot :: number, passesOf(player))
	if not ok then
		return refuse(reasonFrom(reason))
	end
	Funnel.spins(player, "Equipped") -- the ability spins funnel (the tutorial lane)
	return { ok = true, state = build(player) }
end

function HANDLERS.Lock(player: Player, r: SpinView.Request): Reply
	local ok, reason =
		PlayerData.ultLock(player, r.slot :: number, r.locked == true, passesOf(player))
	if not ok then
		return refuse(reasonFrom(reason))
	end
	return { ok = true, state = build(player) }
end

function HANDLERS.BuySpins(player: Player, r: SpinView.Request): Reply
	if not isLive(player) then
		return refuse("NotLive")
	end
	local pack = r.pack :: number
	local data = PlayerData.read(player)
	local money = if data ~= nil then data.Money else 0
	local price, why, need = SpinView.buyCheck(pack, money, restrictedOf(player))
	if why == "NotEnoughMoney" then
		return refuse(why, { need = need, price = price })
	elseif why ~= nil then
		return refuse(why)
	end
	local ok, reason = PlayerData.buyUltSpins(player, pack, price)
	if not ok then
		if reason == "NotEnoughMoney" then
			local now = PlayerData.read(player)
			local left = if now ~= nil then now.Money else 0
			return refuse("NotEnoughMoney", { need = math.max(0, price - left), price = price })
		end
		return refuse(reasonFrom(reason))
	end
	return { ok = true, pack = pack, price = price, state = build(player) }
end

function HANDLERS.BuyProduct(player: Player, r: SpinView.Request): Reply
	if not isLive(player) then
		return refuse("NotLive")
	end
	local product = r.product :: string
	if SpinView.isSpinProduct(product) then
		local restricted = restrictedOf(player)
		if restricted == nil then
			return refuse("NotLoaded")
		elseif restricted then
			return refuse("Restricted")
		end
		local row = (Config.Products.List :: any)[product]
		if row and row.Lucky and not Roll.available("Lucky", devAllOf(player)) then
			return refuse("LuckyClosed")
		end
	end
	local ok, reason = Store.prompt(player, product)
	if not ok then
		return refuse(reason or "Error")
	end
	return { ok = true }
end

-- One request, start to finish. `skipBucket` is the Studio QA hook's. Never errors.
local function handle(player: Player, kind: any, args: any, skipBucket: boolean?): Reply
	if not skipBucket then
		local bucket = buckets[player]
		if bucket == nil then
			bucket = Requests.newBucket(os.clock(), U.RequestBurst)
			buckets[player] = bucket
		end
		if not Requests.take(bucket, os.clock(), U.RequestBurst, 1 / U.RequestCooldownSeconds) then
			return refuse("TooFast")
		end
	end
	local request, why = SpinView.parse(kind, args)
	if request == nil then
		return refuse(why or "BadRequest")
	elseif PlayerData.isHandedOff(player) then
		return refuse("Teleporting")
	elseif not PlayerData.isLoaded(player) then
		return refuse("NotLoaded")
	elseif closing then
		return refuse("Error")
	end
	if busy[player] then
		return refuse("Busy")
	end
	busy[player] = true
	local ok, reply = pcall(HANDLERS[request.kind], player, request)
	busy[player] = nil
	if not ok then
		log(("%s for %s failed: %s"):format(request.kind, who(player), tostring(reply)))
		return refuse("Error")
	end
	return reply
end

---------------------------------------------------------------------------------------------
-- Dev and reads for other services
---------------------------------------------------------------------------------------------

--- The ult this player plays in matches (the selected slot's when owned and usable, else
--- Config.Ults.Default), with their passes and developer flag.
function UltSpins.equipped(player: Player): string
	return PlayerData.equippedUlt(player, passesOf(player), devAllOf(player))
end

--- Whether the developer flag is on for this player (Config.Ults.DevAllUlts or /ultsall on).
function UltSpins.devAll(player: Player): boolean
	return devAllOf(player)
end

--- Dev (/ultsall on|off): every ult rolls and plays for this player for the session.
function UltSpins.setDevAll(player: Player, on: boolean)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or type(on) ~= "boolean" then
		return
	end
	devAll[player] = on
	player:SetAttribute(DEV_ALL_ATTR, on)
	syncAccess(player)
	mark(player)
end

--- Sends the player's UltState again (even if unchanged).
function UltSpins.refresh(player: Player)
	lastSent[player] = nil
	mark(player)
end

-- Studio only: ServerStorage.UltSpinsQA, a BindableFunction that runs inside this module
-- (clients cannot reach ServerStorage; nothing is made in a live server). Invoke(op, userId,
-- ...):
--   "state"                   -> the UltState payload that player would get now
--   "request", kind, args     -> the UltRequest reply, exactly as the remote answers (the
--                                token bucket skipped)
--   "grant", spins, lucky?    -> adds spins and Lucky Spins (PlayerData.addUltSpins/Lucky)
--   "setDevAll", on           -> as /ultsall
--   "equipped"                -> UltSpins.equipped
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("UltSpinsQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "UltSpinsQA"
	hook.OnInvoke = function(op: string, userId: number, a: any, b: any): ...any
		local player = Players:GetPlayerByUserId(userId)
		assert(player, "UltSpinsQA: no player in game with that UserId")
		if op == "state" then
			return build(player)
		elseif op == "request" then
			return handle(player, a, b, true)
		elseif op == "grant" then
			local okSpins = if type(a) == "number" and a > 0
				then PlayerData.addUltSpins(player, a, "UltSpinsQA")
				else true
			local okLucky = if type(b) == "number" and b > 0
				then PlayerData.addUltLucky(player, b, "UltSpinsQA")
				else true
			return okSpins and okLucky
		elseif op == "setDevAll" then
			UltSpins.setDevAll(player, a == true)
			return devAllOf(player)
		elseif op == "equipped" then
			return UltSpins.equipped(player)
		end
		error("UltSpinsQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

-- The PlayerData changes the spin screen shows.
local STATE_OPS: { [string]: boolean } = {
	ultSpin = true,
	ultSelect = true,
	ultLock = true,
	buyUltSpins = true,
	addUltSpins = true,
	addUltLucky = true,
	setUltSpins = true,
	setUltLucky = true,
	setUltPity = true,
	setFreeSpin = true,
	setUlt = true,
	applyPurchase = true, -- spin packs
	grantReward = true, -- rank, dev and other grants with spins
	applyRank = true, -- rank-up spins
	claimRank = true, -- the Rank screen's CLAIM (its rewards' spins)
	claimDaily = true, -- day 7's spins
	claimPlaytime = true, -- the last gift's spin
	redeemCode = true, -- RELEASE
	newDay = true,
	reset = true,
}

local function onLoaded(player: Player)
	lastSent[player] = nil
	syncAccess(player)
	mark(player)
end

local function onPlayerRemoving(player: Player)
	buckets[player] = nil
	busy[player] = nil
	devAll[player] = nil
	dirty[player] = nil
	lastSent[player] = nil
end

--- A new UTC day began (the Rewards day tick): today's free spin is ready again for everyone.
function UltSpins.dayChanged()
	markAll()
end

--- Connects the remotes (Rewards.start calls this once, after Items and Store started).
function UltSpins.start()
	if started then
		return
	end
	started = true
	local remote = Net.get("UltRequest") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, kind: any, args: any): Reply
		local ok, reply = pcall(handle, player, kind, args)
		if not ok then
			log(("a request from %s failed: %s"):format(who(player), tostring(reply)))
			return refuse("Error")
		end
		return reply
	end
	PlayerData.Loaded:Connect(onLoaded)
	PlayerData.Changed:Connect(function(player: Player, op: string)
		if STATE_OPS[op] then
			mark(player)
		end
	end)
	Store.PassChanged:Connect(function(player: Player)
		syncAccess(player)
		mark(player)
	end)
	Items.PolicyChanged:Connect(mark)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			onLoaded(player)
		end
	end
	game:BindToClose(function()
		closing = true
	end)
	startQA()
end

return UltSpins
