--!strict
-- Rewards: the login streak, the playtime gifts and the promo codes (ECONOMY sections 10 and
-- 18) behind the Rewards menu. The pure rules are Progression/Daily (claims, gifts, codes)
-- and Progression/RewardView (the RewardState payload); every claim is one PlayerData
-- mutation that checks, marks and gives in one step.
--
-- - RewardRequest (a RemoteFunction): "ClaimDaily", "ClaimPlaytime" (a gift index) and
--   "Redeem" (the typed code text). The client names what to claim, never what it gives: the
--   server decides from the UTC day, today's playtime and Config.Daily. Rate-limited per
--   player; a bad request is refused, never an error.
-- - The playtime clock: every Config.Daily.PlaytimeTickSeconds each loaded player (not handed
--   off for a teleport) gets the whole seconds played since the last credit
--   (PlayerData.addPlaySeconds), and the rest when they leave.
-- - RewardState goes to each player on load, after every change it shows, when a playtime
--   gift becomes ready, and to everyone when the UTC day rolls over.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Daily = require(Shared.Progression.Daily)
local RewardView = require(Shared.Progression.RewardView)
local PlayerData = require(script.Parent.PlayerData)

local D = Config.Daily
local SECONDS_PER_DAY = 86400

-- A RewardRequest answer: { ok, reason? } and, once claimed, { money, cases = { { id,
-- count } } } (RewardView.reward).
export type Reply = { [string]: any }

local Rewards = {}

local started = false
local rewardState: RemoteEvent? = nil

-- The last RewardRequest and the last code attempt per player (os.clock), for the cooldowns.
local lastRequest: { [Player]: number } = {}
local lastRedeem: { [Player]: number } = {}
-- os.clock() up to which each loaded player's playtime has been credited.
local credited: { [Player]: number } = {}
-- The ready playtime gifts last sent (RewardView.readyKey), to notice one becoming ready.
local readySent: { [Player]: string } = {}
-- Players whose RewardState is due, sent together at the end of the frame.
local dirty: { [Player]: boolean } = {}
local flushQueued = false
-- The UTC day the last states were built on.
local currentDay = Daily.dayOf(os.time())

local function log(message: string)
	warn("[8ball] Rewards: " .. message)
end

-- Runs fn(...) and logs an error instead of raising it (a loop or a leave must go on).
local function safely(what: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(function(...: any): any
		fn(...)
		return nil
	end, ...)
	if not ok then
		log(("%s failed: %s"):format(what, tostring(err)))
	end
end

-- The player's save is loaded here and not handed off for a teleport.
local function ready(player: Player): boolean
	return PlayerData.isLoaded(player) and not PlayerData.isHandedOff(player)
end

---------------------------------------------------------------------------------------------
-- The state (RewardState)
---------------------------------------------------------------------------------------------

-- The RewardState payload for this player now, and today's Daily; nil when not loaded.
local function build(player: Player): (RewardView.Payload?, any)
	local data = PlayerData.read(player)
	local daily = PlayerData.dailyState(player)
	if data == nil or daily == nil then
		return nil, nil
	end
	return RewardView.build(data.Login, daily, data.Titles, os.time()), daily
end

local function send(player: Player)
	if player.Parent ~= Players or not ready(player) then
		return
	end
	local payload, daily = build(player)
	if payload == nil then
		return
	end
	readySent[player] = RewardView.readyKey(daily)
	local remote = rewardState
	if remote ~= nil then
		remote:FireClient(player, payload)
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
		safely(("sending the rewards of %d"):format(player.UserId), send, player)
	end
end

-- Marks a player's RewardState due; everything marked in one frame goes out once.
local function mark(player: Player)
	dirty[player] = true
	if not flushQueued then
		flushQueued = true
		task.defer(flush)
	end
end

-- The PlayerData changes the Rewards menu shows (addPlaySeconds is handled on its own: it
-- fires every tick and only matters when a gift becomes ready).
local REWARD_OPS: { [string]: boolean } = {
	claimDaily = true,
	claimPlaytime = true,
	redeemCode = true,
	setStreakDay = true,
	newDay = true,
	setPlayMinutes = true,
	claimIndexRow = true, -- a title
	reset = true,
}

local function onChanged(player: Player, op: string)
	if REWARD_OPS[op] or string.find(op, "Title", 1, true) ~= nil then
		mark(player)
	elseif op == "addPlaySeconds" then
		local daily = PlayerData.dailyState(player)
		if daily ~= nil and RewardView.readyKey(daily) ~= readySent[player] then
			mark(player)
		end
	end
end

---------------------------------------------------------------------------------------------
-- The playtime clock
---------------------------------------------------------------------------------------------

-- Credits the whole seconds played since the last credit (the fraction waits for the next).
local function credit(player: Player)
	local since = credited[player]
	if since == nil then
		return
	end
	local now = os.clock()
	if not ready(player) then
		credited[player] = now -- time without a loaded save is not counted
		return
	end
	local seconds = math.floor(now - since)
	if seconds <= 0 then
		return
	end
	seconds = math.min(seconds, SECONDS_PER_DAY)
	if PlayerData.addPlaySeconds(player, seconds) then
		credited[player] = since + seconds
	else
		credited[player] = now
	end
end

local function playtimeLoop()
	while true do
		task.wait(D.PlaytimeTickSeconds)
		local list: { Player } = {}
		for player in credited do
			table.insert(list, player)
		end
		for _, player in list do
			safely(("playtime for %d"):format(player.UserId), credit, player)
		end
	end
end

-- Every DayCheckSeconds: a new UTC day re-sends everyone's state (the streak and the gifts
-- start over at midnight UTC).
local function dayLoop()
	while true do
		task.wait(D.DayCheckSeconds)
		local day = Daily.dayOf(os.time())
		if day ~= currentDay then
			currentDay = day
			for _, player in Players:GetPlayers() do
				mark(player)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- RewardRequest
---------------------------------------------------------------------------------------------

local function refused(reason: string): Reply
	return { ok = false, reason = reason }
end

local function claimed(reward: Daily.Reward): Reply
	local out = RewardView.reward(reward)
	return { ok = true, money = out.money, cases = out.cases }
end

-- PlayerData's answers as the remote's reason codes.
local REASONS: { [string]: string } = {
	Claimed = "AlreadyClaimed",
	NotReady = "NotReady",
	NotLoaded = "NotLoaded",
	Used = "Used",
	Expired = "Expired",
	Invalid = "BadRequest",
}

-- One claim's result: (true, reward) or (false, PlayerData's reason) as a reply. `unknown` is
-- what PlayerData's "Unknown" means here (no such gift is a bad request; no such code is not).
local function answer(ok: boolean, result: any, unknown: string): Reply
	if ok and type(result) == "table" then
		return claimed(result)
	end
	if result == "Unknown" or result == "Bad" then
		return refused(unknown)
	end
	return refused(if type(result) == "string" then REASONS[result] or "Error" else "Error")
end

local function onRewardRequest(player: Player, action: any, a: any): Reply
	if action ~= "ClaimDaily" and action ~= "ClaimPlaytime" and action ~= "Redeem" then
		return refused("BadRequest")
	end
	local clock = os.clock()
	local last = lastRequest[player]
	if last ~= nil and clock - last < D.RequestCooldownSeconds then
		return refused("TooFast")
	end
	if action == "Redeem" then
		local lastCode = lastRedeem[player]
		if lastCode ~= nil and clock - lastCode < D.RedeemCooldownSeconds then
			return refused("TooFast")
		end
	end
	lastRequest[player] = clock
	if not ready(player) then
		return refused("NotLoaded")
	end
	if action == "ClaimDaily" then
		local ok, result = PlayerData.claimDaily(player)
		return answer(ok, result, "BadRequest")
	elseif action == "ClaimPlaytime" then
		if type(a) ~= "number" or a ~= math.floor(a) or a < 1 or a > #D.Playtime then
			return refused("BadRequest")
		end
		-- Seconds played since the last tick count too, so a gift that just became due claims.
		credit(player)
		local ok, result = PlayerData.claimPlaytime(player, a)
		return answer(ok, result, "BadRequest")
	else
		if type(a) ~= "string" then
			return refused("BadRequest")
		end
		lastRedeem[player] = clock
		-- Anything far longer than a code is no code (Daily.normalizeCode refuses it too).
		if #a > D.CodeMaxLength * 4 then
			return refused("Unknown")
		end
		local ok, result = PlayerData.redeemCode(player, a)
		return answer(ok, result, "Unknown")
	end
end

---------------------------------------------------------------------------------------------
-- Dev and start
---------------------------------------------------------------------------------------------

--- Sends the player's RewardState again. (The day, streak and playtime dev commands go
--- through PlayerData.setStreakDay, newDay and setPlayMinutes; the state follows by itself.)
function Rewards.refresh(player: Player)
	mark(player)
end

-- Studio only: ServerStorage.RewardsQA (a BindableFunction; clients can never reach it).
--   ("state", userId)          -> the RewardState payload that player would get now
--   ("request", userId, action, a) -> the RewardRequest answer (the cooldowns skipped)
--   ("credit", userId)         -> credits the playtime due now
local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local old = ServerStorage:FindFirstChild("RewardsQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "RewardsQA"
	hook.OnInvoke = function(op: string, userId: number, a: any, b: any): any
		local player = Players:GetPlayerByUserId(userId)
		assert(player, "RewardsQA: no player in game with that UserId")
		if op == "state" then
			return (build(player))
		elseif op == "request" then
			lastRequest[player] = nil
			lastRedeem[player] = nil
			return onRewardRequest(player, a, b)
		elseif op == "credit" then
			credit(player)
			return true
		end
		error("RewardsQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

local function onLoaded(player: Player)
	credited[player] = os.clock()
	mark(player)
end

local function onPlayerRemoving(player: Player)
	-- The save is still open during PlayerRemoving (PlayerData lets it go a frame later).
	safely(("the last playtime of %d"):format(player.UserId), credit, player)
	credited[player] = nil
	lastRequest[player] = nil
	lastRedeem[player] = nil
	readySent[player] = nil
	dirty[player] = nil
end

--- Connects the remotes and starts the playtime clock (Bootstrap calls this once).
function Rewards.start()
	if started then
		return
	end
	started = true
	rewardState = Net.get("RewardState")
	local request: RemoteFunction = Net.get("RewardRequest")
	request.OnServerInvoke = function(player: Player, action: any, a: any): Reply
		local ok, result = pcall(onRewardRequest, player, action, a)
		if not ok then
			log(("RewardRequest from %d failed: %s"):format(player.UserId, tostring(result)))
			return refused("Error")
		end
		return result
	end
	PlayerData.Loaded:Connect(onLoaded)
	PlayerData.Changed:Connect(onChanged)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			onLoaded(player)
		end
	end
	task.spawn(playtimeLoop)
	task.spawn(dayLoop)
	startQA()
end

return Rewards
