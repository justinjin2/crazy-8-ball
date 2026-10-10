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
-- - Rewards carry lucky blocks and ability spins too (the economy plan, 2026-10-02, section
--   6: Daily's rewards `blocks`, `spins`, `lucky`). Every reward is claimed in the Rewards
--   menu (designer 2026-10-04: no popups, nothing given by itself); VIP adds a spin to each
--   day's claim; Live codes count only while LiveCodes has them on. A new UTC day also
--   re-shows every save (PlayerData.refreshAll: the UltFreeSpin attribute) and tells UltSpins
--   (the spin screen's FREE SPIN). Rewards.start starts UltSpins.
-- - RewardRequest "ClaimFavorite" gives the favorite reward once (GUI lane, D4).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Daily = require(Shared.Progression.Daily)
local Inventory = require(Shared.Progression.Inventory)
local RewardView = require(Shared.Progression.RewardView)
local PlayerData = require(script.Parent.PlayerData)
local LiveCodes = require(script.Parent.LiveCodes)
local Counters = require(script.Parent.Counters)
local Social = require(script.Parent.Social)
local Funnel = require(script.Parent.Funnel)

local D = Config.Daily
local SECONDS_PER_DAY = 86400

-- A RewardRequest answer: { ok, reason? } and, once claimed, { money, blocks = { { kind,
-- count } }, spins, lucky } (RewardView.reward).
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
-- The ult spin service, once started (required in Rewards.start: it requires Store and Items).
local UltSpinsModule: any = nil

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

-- Whether the player is VIP (the Store's attribute: the pass or the welcome offer), and
-- whether paid random items are restricted for them: VIP's daily spin and block need
-- PolicyService to have answered no (economy v4 plan 6.7: else Config.Daily.VipRestrictedMoney).
local function vipOf(player: Player): (boolean, boolean)
	return player:GetAttribute("Vip") == true, player:GetAttribute("PaidRandomRestricted") ~= false
end

-- What the login rules need besides the save (Daily.LoginExtra; today's match comes from Daily).
local function loginExtra(player: Player, data: any): Daily.LoginExtra
	local _, restricted = vipOf(player)
	local firstJoin = data.Shop.FirstJoin
	return {
		joinDay = if type(firstJoin) == "number" and firstJoin > 0
			then Daily.dayOf(firstJoin)
			else nil,
		restricted = restricted,
	}
end

-- The RewardState payload for this player now, and today's Daily; nil when not loaded.
local function build(player: Player): (RewardView.Payload?, any)
	local data = PlayerData.read(player)
	local daily = PlayerData.dailyState(player)
	if data == nil or daily == nil then
		return nil, nil
	end
	return RewardView.build(
		data.Login,
		daily,
		data.Titles,
		os.time(),
		(vipOf(player)),
		data.Social,
		Social.isMember(player),
		data.Flags,
		loginExtra(player, data)
	),
		daily
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
	claimGroup = true,
	claimFavorite = true,
	setInvitedBy = true,
	giveInviteRewards = true,
	recordMatch = true, -- an invited player's first win
	recordRealMatch = true, -- today's first finished match lets the login day be claimed
	winBlock = true, -- the win track's bar
	applyPurchase = true, -- Claim All claims the login row (Config.Daily.ClaimAll)
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
			safely("re-showing the saves", PlayerData.refreshAll)
			local ultSpins = UltSpinsModule
			if ultSpins ~= nil then
				safely("the ult spins' new day", ultSpins.dayChanged)
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
	return {
		ok = true,
		money = out.money,
		blocks = out.blocks,
		spins = out.spins,
		lucky = out.lucky,
	}
end

-- PlayerData's answers as the remote's reason codes.
local REASONS: { [string]: string } = {
	Claimed = "AlreadyClaimed",
	NeedsMatch = "NeedsMatch",
	NotReady = "NotReady",
	NotLoaded = "NotLoaded",
	Used = "Used",
	Expired = "Expired",
	Invalid = "BadRequest",
	NotMember = "NotMember",
	TooFast = "TooFast",
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

-- The tutorial lane: a call after each code redeemed (TutorialService: RELEASE moves its Code
-- step on). Nil: none.
local redeemed: ((Player, string) -> ())? = nil

--- The tutorial lane's hook on redeemed codes (see above).
function Rewards.onRedeemed(fn: ((Player, string) -> ())?)
	redeemed = fn
end

local function onRewardRequest(player: Player, action: any, a: any): Reply
	if
		action ~= "ClaimDaily"
		and action ~= "ClaimPlaytime"
		and action ~= "Redeem"
		and action ~= "ClaimGroup"
		and action ~= "ClaimFavorite"
	then
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
		local vip, restricted = vipOf(player)
		-- The copies in existence: a cue the claim gives (the Week One Cue) counts once it lands.
		local cues = Daily.rewardCues()
		local before = PlayerData.read(player)
		local had: { number } = {}
		for i, id in cues do
			had[i] = if before then Inventory.count(before, id) else 0
		end
		local ok, result = PlayerData.claimDaily(player, vip, restricted)
		local after = if ok then PlayerData.read(player) else nil
		if after then
			Funnel.social(player, "DailyClaimed")
			for i, id in cues do
				local gained = Inventory.count(after, id) - had[i]
				if gained > 0 then
					Counters.add(id, gained)
				end
			end
		end
		return answer(ok, result, "BadRequest")
	elseif action == "ClaimGroup" then
		local ok, result = Social.claimGroup(player)
		mark(player) -- the InGroup answer may have changed even when refused
		return answer(ok, result, "BadRequest")
	elseif action == "ClaimFavorite" then
		local ok, result = PlayerData.claimFavorite(player)
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
		local ok, result = PlayerData.redeemCode(player, a, LiveCodes.on())
		if ok and redeemed then
			task.spawn(redeemed, player, a) -- the tutorial lane (Rewards.onRedeemed)
		end
		return answer(ok, result, "Unknown")
	end
end

---------------------------------------------------------------------------------------------
-- Dev and start
---------------------------------------------------------------------------------------------

--- The tutorial's Abilities fallback (Config.Tutorial.Timing.AbilitiesRedeemSeconds): redeems
--- `code` for the player as Redeem would, without its cooldown; true when it paid.
function Rewards.redeemFor(player: Player, code: string): boolean
	if not ready(player) then
		return false
	end
	local ok = PlayerData.redeemCode(player, code, LiveCodes.on())
	if ok and redeemed then
		task.spawn(redeemed, player, code)
	end
	return ok == true
end

--- Sends the player's RewardState again. (The day, streak and playtime dev commands go
--- through PlayerData.setStreakDay, newDay and setPlayMinutes; the state follows by itself.)
function Rewards.refresh(player: Player)
	mark(player)
end

-- Studio only: ServerStorage.RewardsQA (a BindableFunction; clients can never reach it).
--   ("state", userId)          -> the RewardState payload that player would get now
--   ("request", userId, action, a) -> the RewardRequest answer (the cooldowns skipped)
--   ("credit", userId)         -> credits the playtime due now
--   ("invitedBy", userId, inviterId) -> PlayerData.setInvitedBy (a brand-new save only)
--   ("inviteWon", userId, inviterId) -> the inviter's reward queued and given, as on a win
--   ("liveCode", userId, code, on)   -> LiveCodes.set (every server; Studio: this one)
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
		elseif op == "invitedBy" then
			return PlayerData.setInvitedBy(player, a)
		elseif op == "inviteWon" then
			Social.qaInviteWon(player, a)
			return true
		elseif op == "liveCode" then
			return LiveCodes.set(a, b == true)
		end
		error("RewardsQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

local function onLoaded(player: Player)
	credited[player] = os.clock()
	mark(player)
	-- VIP (its daily spin on the tiles) and the group answer arrive after the load.
	for _, attribute in { "Vip", "InGroup", "PaidRandomRestricted" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			mark(player)
		end)
	end
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
	LiveCodes.start()
	Social.start()
	task.spawn(playtimeLoop)
	task.spawn(dayLoop)
	startQA()
	-- The ult spin service rides on this start (Bootstrap starts Items and Store before it).
	local ultSpins = require(script.Parent.UltSpins) :: any
	UltSpinsModule = ultSpins
	ultSpins.start()
end

return Rewards
