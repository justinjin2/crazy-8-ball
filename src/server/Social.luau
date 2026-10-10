--!strict
-- Social: the game's group and invites (the approved economy plan, 2026-10-02, section 6;
-- designer, 2026-10-03). The pure rules are Progression/Social; the saves change only through
-- PlayerData.
--
-- - The group (Config.Social.GroupId): each player's membership is asked of Roblox on join
--   and on Claim and kept in the InGroup attribute, which adds Config.Economy.GroupBoost to
--   match money (src/server/Economy.luau). The Rewards menu's Join button is the client's
--   GroupService:PromptJoinAsync; its Claim is RewardRequest "ClaimGroup" (Rewards calls
--   Social.claimGroup), which asks Roblox again and gives Config.Social.GroupReward once.
-- - Invites: the client's SocialService:PromptGameInvite carries Social.launchData(its own
--   UserId). A brand-new player joining with it is recorded as invited (PlayerData.
--   setInvitedBy); their first win gives them the invite cue (Config.Social.InviteCue, the
--   Candy Cane Cue since economy v6; PlayerData.recordMatch) and fires PlayerData.InviteWon,
--   and the inviter's cue waits in a DataStore key of theirs
--   (InviteStore) until a server they are in takes it: on a MessagingService message
--   (InviteTopic) or on their next join. The inviter gets at most InvitesPerMonth a month.
--   Studio without DataStores: the waiting list stays in this server's memory.
local DataStoreService = game:GetService("DataStoreService")
local GroupService = game:GetService("GroupService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local SocialRules = require(Shared.Progression.Social)
local PlayerData = require(script.Parent.PlayerData)
local Counters = require(script.Parent.Counters)

local C = Config.Social
local IS_STUDIO = RunService:IsStudio()
local IN_GROUP = "InGroup"

local Social = {}

local started = false
local store: DataStore? = nil
local storeTried = false
local studioPending: { [string]: any } = {}
local lastClaim: { [Player]: number } = {}
local lastWarn: { [string]: number } = {}

local function complain(what: string, err: any)
	local now = os.clock()
	if now - (lastWarn[what] or -math.huge) >= 60 then
		lastWarn[what] = now
		warn(("[8ball] Social: %s failed: %s"):format(what, tostring(err)))
	end
end

---------------------------------------------------------------------------------------------
-- The group
---------------------------------------------------------------------------------------------

-- Whether the player is in the group now, asked of Roblox (GetGroupsAsync, so a join this
-- session counts; IsInGroupAsync if that fails). nil when Roblox did not answer.
local function askMember(player: Player): boolean?
	local ok, groups = pcall(function(): any
		return GroupService:GetGroupsAsync(player.UserId)
	end)
	if ok and type(groups) == "table" then
		for _, group in groups do
			if type(group) == "table" and group.Id == C.GroupId then
				return true
			end
		end
		return false
	end
	local okCached, member = pcall(function(): boolean
		return player:IsInGroupAsync(C.GroupId)
	end)
	if okCached then
		return member
	end
	complain("asking for the groups", groups)
	return nil
end

local function checkGroup(player: Player): boolean?
	local member = askMember(player)
	if member ~= nil and player.Parent == Players then
		player:SetAttribute(IN_GROUP, member)
	end
	return member
end

--- RewardRequest "ClaimGroup": asks Roblox whether the player joined, then gives the group's
--- one-time reward. Yields. Answers (true, Daily.Reward) or (false, "TooFast" | "Claimed" |
--- "NotMember" | "NotLoaded" | "Error").
function Social.claimGroup(player: Player): (boolean, any)
	local clock = os.clock()
	local last = lastClaim[player]
	if last ~= nil and clock - last < C.ClaimCooldownSeconds then
		return false, "TooFast"
	end
	lastClaim[player] = clock
	local member = checkGroup(player)
	if member == nil then
		return false, "Error"
	end
	return PlayerData.claimGroup(player, member)
end

--- Whether the player was a member when last asked (the InGroup attribute).
function Social.isMember(player: Player): boolean
	return player:GetAttribute(IN_GROUP) == true
end

---------------------------------------------------------------------------------------------
-- Invites
---------------------------------------------------------------------------------------------

local function storeOf(): DataStore?
	if storeTried then
		return store
	end
	storeTried = true
	local name = if IS_STUDIO then C.InviteStudioStore else C.InviteStore
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		complain("opening " .. name, result)
	end
	return store
end

-- Runs a transform on inviter `inviterId`'s waiting key atomically. Yields. True when it ran.
local function update(inviterId: number, transform: (any) -> any): boolean
	local key = tostring(inviterId)
	local s = storeOf()
	local ok, err = false, "no DataStore"
	if s ~= nil then
		ok, err = pcall(function(): any
			return s:UpdateAsync(key, transform)
		end)
	end
	if ok then
		return true
	elseif IS_STUDIO then
		local value = transform(studioPending[key])
		if value ~= nil then
			studioPending[key] = value
		end
		return true
	end
	complain("updating the invite rewards", err)
	return false
end

-- Takes the player's waiting invite rewards and gives them (the monthly cap applies). Yields.
local function takePending(player: Player)
	if not PlayerData.isLoaded(player) then
		return
	end
	local taken: { number } = {}
	local ran = update(player.UserId, function(stored: any): any
		local value, ids = SocialRules.takePending(stored)
		taken = ids
		return value
	end)
	if ran and #taken > 0 then
		local given = PlayerData.giveInviteRewards(player, taken)
		if given > 0 then
			Counters.add(C.InviteCue, given) -- the copies in existence
		end
	end
end

-- An invited player's first win: the inviter's reward waits for them; their server is told.
local function onInviteWon(invitee: Player, inviterId: number)
	local inviteeId = invitee.UserId
	local added = update(inviterId, function(stored: any): any
		return SocialRules.addPending(stored, inviteeId)
	end)
	if not added then
		return
	end
	local here = Players:GetPlayerByUserId(inviterId)
	if here then
		takePending(here)
		return
	end
	local ok, err = pcall(function()
		MessagingService:PublishAsync(C.InviteTopic, inviterId)
	end)
	if not ok then
		complain("telling the inviter's server", err)
	end
end

-- Join data: a brand-new player who came through an invite is recorded as invited.
local function readInvite(player: Player)
	local ok, joinData = pcall(function(): any
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then
		return
	end
	local inviterId = SocialRules.inviterFrom(joinData.LaunchData, player.UserId)
	if inviterId ~= nil then
		PlayerData.setInvitedBy(player, inviterId)
	end
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

local function safely(what: string, fn: (...any) -> (), ...: any)
	local ok, err = pcall(function(...: any): any
		fn(...)
		return nil
	end, ...)
	if not ok then
		warn(("[8ball] Social: %s failed: %s"):format(what, tostring(err)))
	end
end

local function onLoaded(player: Player)
	safely("the group check", checkGroup, player)
	safely("the invite", readInvite, player)
	safely("the waiting invite rewards", takePending, player)
end

--- Connects the saves' events and the invite messages (Rewards.start calls this once).
function Social.start()
	if started then
		return
	end
	started = true
	PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(onLoaded, player)
	end)
	PlayerData.InviteWon:Connect(function(invitee: Player, inviterId: number)
		Counters.add(C.InviteCue, 1) -- the invitee's cue, in the copies in existence
		task.spawn(safely, "an invite reward", onInviteWon, invitee, inviterId)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastClaim[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			task.spawn(onLoaded, player)
		end
	end
	task.spawn(function()
		local ok, err = pcall(function(): any
			return MessagingService:SubscribeAsync(C.InviteTopic, function(message: any)
				local id = if type(message) == "table" then message.Data else nil
				local player = if type(id) == "number" then Players:GetPlayerByUserId(id) else nil
				if player then
					safely("the waiting invite rewards", takePending, player)
				end
			end)
		end)
		if not ok then
			complain("listening for invite rewards", err)
		end
	end)
end

--- Studio QA: an invite win as if `invitee` had been invited by `inviterId` (the queue and
--- the inviter's reward run for real). Yields.
function Social.qaInviteWon(invitee: Player, inviterId: number)
	onInviteWon(invitee, inviterId)
end

return Social
