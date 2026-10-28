--!strict
-- Friends: whether a player has a Roblox friend in this server (designer, 2026-10-07, the
-- matchmaking bar; a friend in a match counts too). Since 2026-10-09 the pad's popup and Play
-- Global no longer depend on it: both go out at once, friends here or not (PadBar).
--
-- Roblox is asked once per pair (Player:IsFriendsWithAsync, which yields), on arrival; the
-- answer is kept until either of them leaves. The result is the FriendHere attribute on each
-- player, which the client's bar reads; Friends.here reads it on the server.
--
-- The friend boost (Halloween 2026; hw-gui lane): the FriendsHere number attribute counts the
-- pairs Roblox answered true (uncapped; Money.friendBoost caps it and pays it on money, core on
-- Candy). A pair still being asked, or that errored, counts 0, never a friend (research A4: a
-- slow check once paid a whole server). A failed pair is asked once more after
-- Config.Economy.FriendRetrySeconds, then stays 0 for the session. Lobby bots are not Players,
-- so they never count. The FriendBoost event logs each session's peak (0..4) on leaving.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Funnel = require(script.Parent.Funnel)

local ATTRIBUTE = "FriendHere"
local COUNT_ATTRIBUTE = "FriendsHere"

local Friends = {}

local started = false
local known: { [string]: boolean } = {} -- "low:high" user ids -> friends
local asking: { [string]: boolean } = {} -- pairs with a call in flight
local failures: { [string]: number } = {} -- pairs whose call errored -> how many times
local forced: { [Player]: number? } = {} -- Studio only (FriendsQA): a faked count
local peak: { [Player]: number } = {} -- the session's highest count, capped (FriendBoost event)
local lastWarn = -math.huge

local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

-- Set the attributes from what is known, never yielding.
local function refresh(player: Player)
	if player.Parent ~= Players then
		return
	end
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player and known[pairKey(player.UserId, other.UserId)] == true then
			count += 1
		end
	end
	local any = count > 0
	if player:GetAttribute(ATTRIBUTE) ~= any then
		player:SetAttribute(ATTRIBUTE, any)
	end
	local shown = forced[player] or count
	if player:GetAttribute(COUNT_ATTRIBUTE) ~= shown then
		player:SetAttribute(COUNT_ATTRIBUTE, shown)
	end
	local cap = Config.Economy.FriendBoostMaxFriends or 4
	peak[player] = math.max(peak[player] or 0, math.min(shown, cap))
end

local function refreshAll()
	for _, player in Players:GetPlayers() do
		refresh(player)
	end
end

-- Ask Roblox about one pair; on a first error, once more after FriendRetrySeconds.
local function ask(player: Player, other: Player)
	local key = pairKey(player.UserId, other.UserId)
	if known[key] ~= nil or asking[key] then
		return
	end
	asking[key] = true
	local ok, result = pcall(player.IsFriendsWithAsync, player, other.UserId)
	asking[key] = nil
	if player.Parent ~= Players or other.Parent ~= Players then
		return -- one left while asking (their entries are cleared): a rejoin asks afresh
	end
	if ok then
		known[key] = result == true
		failures[key] = nil
		return
	end
	if os.clock() - lastWarn >= 60 then
		lastWarn = os.clock()
		warn(("[8ball] Friends: IsFriendsWithAsync failed: %s"):format(tostring(result)))
	end
	local tries = (failures[key] or 0) + 1
	failures[key] = tries
	if tries >= 2 then
		known[key] = false -- 0 for the rest of the session
		return
	end
	task.delay(Config.Economy.FriendRetrySeconds or 30, function()
		if player.Parent == Players and other.Parent == Players and failures[key] == tries then
			ask(player, other)
			refresh(player)
			refresh(other)
		end
	end)
end

local function arrive(player: Player)
	refresh(player)
	for _, other in Players:GetPlayers() do
		if other == player or player.Parent ~= Players then
			continue
		end
		ask(player, other)
	end
	refreshAll()
end

--- Whether `player` has a Roblox friend in this server (as far as Roblox has answered).
function Friends.here(player: Player): boolean
	return player:GetAttribute(ATTRIBUTE) == true
end

--- How many Roblox friends `player` has in this server (uncapped; 0 while unknown).
function Friends.count(player: Player): number
	local n = player:GetAttribute(COUNT_ATTRIBUTE)
	return if type(n) == "number" and n == n and n >= 0 then n else 0
end

-- Studio only: ServerStorage.FriendsQA (a BindableFunction; clients can never reach it),
-- because IsFriendsWithAsync fails in Studio.
--   ("count", player or userId, n?) -> forces that player's FriendsHere to n (nil: the real count)
local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local old = ServerStorage:FindFirstChild("FriendsQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "FriendsQA"
	hook.OnInvoke = function(op: string, who: any, n: any): any
		local player = if typeof(who) == "Instance" and who:IsA("Player")
			then who
			else Players:GetPlayerByUserId(tonumber(who) or 0)
		assert(player, "FriendsQA: no such player in game")
		if op == "count" then
			forced[player] = if type(n) == "number" then n else nil
			refresh(player)
			return player:GetAttribute(COUNT_ATTRIBUTE)
		end
		error("FriendsQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

function Friends.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(function(player)
		task.spawn(arrive, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		Funnel.event(player, "FriendBoost", peak[player] or 0, Funnel.device(player))
		-- Funnel's own PlayerRemoving may have run first: the event's log line would keep the
		-- Player for the server's life.
		Funnel.clearLog(player)
		peak[player] = nil
		forced[player] = nil
		task.defer(refreshAll)
		local id = player.UserId
		for key in known do
			local a, b = key:match("^(-?%d+):(-?%d+)$")
			if tonumber(a) == id or tonumber(b) == id then
				known[key] = nil
			end
		end
		for key in failures do
			local a, b = key:match("^(-?%d+):(-?%d+)$")
			if tonumber(a) == id or tonumber(b) == id then
				failures[key] = nil
			end
		end
	end)
	startQA()
	for _, player in Players:GetPlayers() do
		task.spawn(arrive, player)
	end
end

return Friends
