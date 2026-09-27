--!strict
-- PlayerData: every player's save, and the only module that touches ProfileStore or a
-- DataStore. ProfileStore (src/server/Vendor, never edited) does the session lock, the
-- autosave on its own clock, the retries and the last save on shutdown; this module opens a
-- session when a player joins, brings the save up to date and repairs it
-- (Progression/SaveSchema), offers named, validated mutations, and copies what clients need
-- onto the player (attributes and leaderstats). Nothing else reads or writes save data.
--
-- The rules:
-- * Nobody plays on a save that could not be opened: a failed load kicks with
--   Strings.Save.LoadFailed; a session another server took over kicks with
--   Strings.Save.SessionEnded.
-- * Nothing is granted before the save loads or after its session ended: every mutation
--   checks the loaded, active profile, and logs and drops the change otherwise.
-- * Every mutation checks its inputs first (whole numbers in range, known words) and refuses
--   bad ones with one warning, never an error. None makes a DataStore request of its own.
-- * Callers only ever get frozen copies of the data, never the live table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local SaveSchema = require(Shared.Progression.SaveSchema)
local Ranks = require(Shared.Progression.Ranks)
local ProfileStore = require(script.Parent.Vendor.ProfileStore)

type Profile = ProfileStore.Profile<any>

local S = Config.Save
local IS_STUDIO = RunService:IsStudio()
-- Studio saves go to their own store, so testing never touches a real player's save.
local STORE_NAME = if IS_STUDIO then S.StudioStoreName else S.StoreName
-- Studio-only failure test: set this attribute on ServerStorage to true and the next save
-- that opens fails as if the DataStore refused the session (the player is kicked with
-- Strings.Save.LoadFailed); the attribute clears itself. Never read outside Studio.
local FAIL_NEXT_LOAD = "PlayerDataFailNextLoad"

-- The player attributes this module owns (server-set; clients only read them).
local ATTR = {
	Loaded = "DataLoaded", -- true once the save is loaded, false after its session ended
	Money = "Money",
	RankXp = "RankXp",
	RatedMatches = "RatedMatches",
	PeakDivision = "PeakDivision",
	RankTier = "RankTier", -- "Gold", or "Unranked"
	RankDivision = "RankDivision", -- 1 = I; 0 for Unranked
	RankIndex = "RankIndex", -- 0 Unranked, 1 Bronze I ... the top division
}

local PlayerData = {}

local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
--- (player) Fires once each time a player's save is ready.
PlayerData.Loaded = loadedEvent.Event
--- (player) Fires after any successful mutation, once the attributes are updated.
PlayerData.Changed = changedEvent.Event

local store: ProfileStore.ProfileStore<any>? = nil
local started = false
local profiles: { [Player]: Profile } = {} -- the loaded, active saves
local loading: { [Player]: boolean } = {} -- joins whose session is being opened
-- Sessions this module ended on purpose (the player left, or a QA "endSession"): their
-- OnSessionEnd kicks nobody.
local quiet: { [Profile]: boolean } = {}
-- Players whose PlayerRemoving has fired (weak, so a gone Player can be collected).
local gone: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------

local function isPlayer(x: any): boolean
	return typeof(x) == "Instance" and x:IsA("Player")
end

-- The UserId for a log line (never any save data).
local function who(player: any): string
	return if isPlayer(player) then tostring(player.UserId) else "?"
end

-- Still in this server, and not on the way out.
local function present(player: Player): boolean
	return player.Parent == Players and not gone[player]
end

-- A whole, finite number in min..max.
local function intIn(x: any, min: number, max: number): boolean
	return SaveSchema.isInteger(x) and x >= min and x <= max
end

-- 0 for -0 (a save never holds -0).
local function plain(x: number): number
	return if x == 0 then 0 else x
end

-- Refuses a mutation's bad input: one warning, then false.
local function refuse(op: string, player: any, why: string): boolean
	warn(("[8ball] PlayerData: %s refused for %s: %s"):format(op, who(player), why))
	return false
end

-- The live data of a loaded, active save for a mutation, or nil (logged): nothing is granted
-- before the save loads or after its session ended.
local function liveData(op: string, player: Player): any?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	warn(("[8ball] PlayerData: %s dropped for %s: not loaded"):format(op, who(player)))
	return nil
end

local function frozenCopy(t: { [any]: any }): { [any]: any }
	local copy = {}
	for key, value in t do
		copy[key] = if type(value) == "table" then frozenCopy(value) else value
	end
	return table.freeze(copy)
end

---------------------------------------------------------------------------------------------
-- Replication: attributes and leaderstats, set only when a value changed
---------------------------------------------------------------------------------------------

local function setAttribute(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- The leaderboard columns, Rank then Money (Roblox shows them in the order they were made).
local function leaderstats(player: Player): (StringValue, IntValue)
	local folder = player:FindFirstChild("leaderstats")
	if folder == nil then
		local made = Instance.new("Folder")
		made.Name = "leaderstats"
		made.Parent = player
		folder = made
	end
	local parent = folder :: Instance
	local rank = parent:FindFirstChild("Rank")
	if not (rank and rank:IsA("StringValue")) then
		local made = Instance.new("StringValue")
		made.Name = "Rank"
		made.Parent = parent
		rank = made
	end
	local money = parent:FindFirstChild("Money")
	if not (money and money:IsA("IntValue")) then
		local made = Instance.new("IntValue")
		made.Name = "Money"
		made.Parent = parent
		money = made
	end
	return rank :: StringValue, money :: IntValue
end

local function replicate(player: Player, data: any)
	local rank = Ranks.fromXp(data.RankXp, data.RatedMatches > 0)
	setAttribute(player, ATTR.Money, data.Money)
	setAttribute(player, ATTR.RankXp, data.RankXp)
	setAttribute(player, ATTR.RatedMatches, data.RatedMatches)
	setAttribute(player, ATTR.PeakDivision, data.PeakDivision)
	setAttribute(player, ATTR.RankTier, rank.tier)
	setAttribute(player, ATTR.RankDivision, rank.division)
	setAttribute(player, ATTR.RankIndex, rank.index)
	local rankValue, moneyValue = leaderstats(player)
	local name = Ranks.name(rank)
	if rankValue.Value ~= name then
		rankValue.Value = name
	end
	if moneyValue.Value ~= data.Money then
		moneyValue.Value = data.Money
	end
end

-- After a mutation: replicate, then tell listeners.
local function commit(player: Player, data: any)
	replicate(player, data)
	changedEvent:Fire(player)
end

---------------------------------------------------------------------------------------------
-- Loading and releasing
---------------------------------------------------------------------------------------------

-- Opens the player's session, or nil when it could not (logged).
local function openSession(player: Player): Profile?
	if IS_STUDIO and ServerStorage:GetAttribute(FAIL_NEXT_LOAD) == true then
		-- The Studio-only failure test (see FAIL_NEXT_LOAD): no session is opened.
		ServerStorage:SetAttribute(FAIL_NEXT_LOAD, nil)
		warn(
			("[8ball] PlayerData: %s set: failing the load of %d"):format(
				FAIL_NEXT_LOAD,
				player.UserId
			)
		)
		return nil
	end
	local profileStore = store :: ProfileStore.ProfileStore<any>
	local key = S.KeyPrefix .. tostring(player.UserId)
	local startedAt = os.clock()
	local params: any = {
		-- Stop waiting once the player has gone, or after LoadTimeoutSeconds (ProfileStore
		-- has no timeout of its own once a cancel check is given).
		Cancel = function(): boolean
			return not present(player) or os.clock() - startedAt > S.LoadTimeoutSeconds
		end,
	}
	local ok, result = pcall(function()
		return profileStore:StartSessionAsync(key, params)
	end)
	if not ok then
		warn(
			("[8ball] PlayerData: opening the save of %d errored: %s"):format(
				player.UserId,
				tostring(result)
			)
		)
		return nil
	end
	return result
end

-- Gives up on a session that opened but cannot be played on: releases it untouched, kicks.
local function abandon(player: Player, profile: Profile, why: string)
	warn(("[8ball] PlayerData: not using the save of %d: %s"):format(player.UserId, why))
	profile:EndSession() -- no OnSessionEnd listener yet, so this kicks nobody twice
	if present(player) then
		player:Kick(Strings.Save.LoadFailed)
	end
end

-- Opens, updates and repairs a player's save, then replicates it and fires Loaded. Runs in
-- its own thread per player (it yields while the DataStore answers).
local function load(player: Player)
	if loading[player] or profiles[player] then
		return
	end
	loading[player] = true
	local profile = openSession(player)
	loading[player] = nil
	if profile == nil then
		if present(player) then
			warn(
				("[8ball] PlayerData: could not open the save of %d: kicked"):format(player.UserId)
			)
			player:Kick(Strings.Save.LoadFailed)
		end
		return
	end
	if not present(player) then
		profile:EndSession() -- left while it loaded
		return
	end

	profile:AddUserId(player.UserId) -- GDPR: ties the key to the player for erasure requests
	-- A save written by newer code (a server still on the old version during an update) is
	-- released untouched: Reconcile or validate would add old fields to it or strip new ones.
	local claimed = (profile.Data :: any).Version
	if SaveSchema.isInteger(claimed) and claimed > SaveSchema.Version then
		abandon(
			player,
			profile,
			("future version %d (this code knows up to %d)"):format(claimed, SaveSchema.Version)
		)
		return
	end
	profile:Reconcile()
	local okMigrate, migrated, notes = pcall(SaveSchema.migrate, profile.Data)
	if not okMigrate then
		abandon(player, profile, "migrate errored: " .. tostring(migrated))
		return
	end
	for _, note in notes do
		if note:sub(1, #"future version") == "future version" then
			-- Newer code's save (caught above too): never repair or play on it.
			abandon(player, profile, note)
			return
		end
	end
	if type(migrated) ~= "table" or migrated.Version ~= SaveSchema.Version then
		abandon(player, profile, "could not migrate: " .. table.concat(notes, "; "))
		return
	end
	if #notes > 0 then
		print(
			("[8ball] PlayerData: save of %d: %s"):format(player.UserId, table.concat(notes, "; "))
		)
	end
	local okValidate, valid, fixes = pcall(SaveSchema.validate, migrated)
	if not okValidate then
		abandon(player, profile, "validate errored: " .. tostring(valid))
		return
	end
	if #fixes > 0 then
		warn(
			("[8ball] PlayerData: repaired the save of %d: %s"):format(
				player.UserId,
				table.concat(fixes, "; ")
			)
		)
	end
	if profile.Data ~= valid then
		profile.Data = valid
	end

	profile.OnSessionEnd:Connect(function()
		local wasQuiet = quiet[profile] == true
		quiet[profile] = nil
		if profiles[player] == profile then
			profiles[player] = nil
		end
		if present(player) then
			setAttribute(player, ATTR.Loaded, false)
			-- Another server took the save over. (Not on shutdown: the server is closing.)
			if not wasQuiet and not ProfileStore.IsClosing then
				player:Kick(Strings.Save.SessionEnded)
			end
		end
	end)
	profiles[player] = profile
	replicate(player, profile.Data)
	setAttribute(player, ATTR.Loaded, true)
	loadedEvent:Fire(player)
end

-- A player left. The release waits a moment (task.defer) so other PlayerRemoving handlers,
-- say one granting the leaver's last match, still find the save active.
local function release(player: Player)
	gone[player] = true
	task.defer(function()
		local profile = profiles[player]
		profiles[player] = nil
		if profile and profile:IsActive() then
			quiet[profile] = true
			profile:EndSession()
		end
	end)
end

-- Logs whether saves reach Roblox's DataStores or only ProfileStore's in-memory mock.
local function logDataStoreState()
	while ProfileStore.DataStoreState == "NotReady" do
		task.wait()
	end
	local state: string = ProfileStore.DataStoreState
	if state == "Access" then
		print(("[8ball] saves: DataStoreState=Access (store %s)"):format(STORE_NAME))
	else
		warn(
			("[8ball] saves: DataStoreState=%s: this is ProfileStore's mock store, so saves vanish when the session stops"):format(
				state
			)
		)
	end
end

---------------------------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------------------------

--- True once the player's save is loaded and its session is still active.
function PlayerData.isLoaded(player: Player): boolean
	local profile = profiles[player]
	return profile ~= nil and profile:IsActive()
end

--- Yields until the player's save is loaded (true), or they leave or `timeout` seconds pass
--- (false). The default timeout is Config.Save.LoadTimeoutSeconds.
function PlayerData.waitLoaded(player: Player, timeout: number?): boolean
	if PlayerData.isLoaded(player) then
		return true
	end
	if not isPlayer(player) or not present(player) then
		return false
	end
	local limit = if type(timeout) == "number"
			and timeout > 0
			and timeout < math.huge
		then timeout
		else S.LoadTimeoutSeconds
	local caller = coroutine.running()
	local finished = false
	local connections: { RBXScriptConnection } = {}
	local timer: thread? = nil
	local function finish(result: boolean)
		if finished then
			return
		end
		finished = true
		for _, connection in connections do
			connection:Disconnect()
		end
		if timer and coroutine.running() ~= timer then
			task.cancel(timer)
		end
		task.spawn(caller, result)
	end
	table.insert(
		connections,
		loadedEvent.Event:Connect(function(loaded: Player)
			if loaded == player then
				finish(true)
			end
		end)
	)
	table.insert(
		connections,
		player.AncestryChanged:Connect(function()
			if player.Parent ~= Players then
				finish(false)
			end
		end)
	)
	timer = task.delay(limit, finish, false)
	return coroutine.yield()
end

--- A deep, frozen copy of the player's save, or nil when it is not loaded.
function PlayerData.read(player: Player): any?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return frozenCopy(profile.Data)
	end
	return nil
end

--- The money the player earned in solo on UTC day `day` (0 if another day or not loaded).
function PlayerData.soloEarnedToday(player: Player, day: number): number
	local profile = profiles[player]
	if not (profile and profile:IsActive()) then
		return 0
	end
	local daily = (profile.Data :: any).Daily
	return if daily.Day == day then daily.SoloMoney else 0
end

---------------------------------------------------------------------------------------------
-- Mutations: check the inputs, check the save, change it, replicate, fire Changed
---------------------------------------------------------------------------------------------

--- Adds `amount` money (a whole number, 1..Config.Save.GrantCap). The total stops at
--- Config.Save.MoneyCap; Stats.MoneyEarned counts it too. With `soloDay` (the UTC day
--- number) it also counts toward that day's solo money, starting the count over on a new
--- day. `reason` says why, for the logs (not saved).
function PlayerData.addMoney(
	player: Player,
	amount: number,
	reason: string,
	soloDay: number?
): boolean
	local op = "addMoney"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(amount, 1, S.GrantCap) then
		return refuse(
			op,
			player,
			("amount %s is not a whole number in 1..%d"):format(tostring(amount), S.GrantCap)
		)
	elseif type(reason) ~= "string" or reason == "" then
		return refuse(op, player, "no reason given")
	elseif soloDay ~= nil and not intIn(soloDay, 0, S.StatCap) then
		return refuse(
			op,
			player,
			("soloDay %s is not a whole number >= 0"):format(tostring(soloDay))
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	data.Money = math.min(data.Money + amount, S.MoneyCap)
	data.Stats.MoneyEarned = math.min(data.Stats.MoneyEarned + amount, S.StatCap)
	if soloDay ~= nil then
		local daily = data.Daily
		if daily.Day ~= soloDay then
			daily.Day = plain(soloDay)
			daily.SoloMoney = 0
		end
		daily.SoloMoney = math.min(daily.SoloMoney + amount, S.MoneyCap)
	end
	commit(player, data)
	return true
end

--- Sets money outright (the /money dev command): a whole number, 0..Config.Save.MoneyCap.
function PlayerData.setMoney(player: Player, amount: number): boolean
	local op = "setMoney"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(amount, 0, S.MoneyCap) then
		return refuse(
			op,
			player,
			("amount %s is not a whole number in 0..%d"):format(tostring(amount), S.MoneyCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	data.Money = plain(amount)
	commit(player, data)
	return true
end

--- Sets the rank fields together (the Ranking service's result, or /rank). Each must be a
--- whole number in range, or nothing changes.
function PlayerData.applyRank(
	player: Player,
	rank: { RankXp: number, PeakDivision: number, RatedMatches: number }
): boolean
	local op = "applyRank"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif type(rank) ~= "table" then
		return refuse(op, player, "rank is not a table")
	end
	local xp, peak, rated = rank.RankXp, rank.PeakDivision, rank.RatedMatches
	if not intIn(xp, 0, S.RankXpCap) then
		return refuse(
			op,
			player,
			("RankXp %s is not a whole number in 0..%d"):format(tostring(xp), S.RankXpCap)
		)
	end
	local divisions = SaveSchema.divisionCount()
	if not intIn(peak, 0, divisions) then
		return refuse(
			op,
			player,
			("PeakDivision %s is not a whole number in 0..%d"):format(tostring(peak), divisions)
		)
	elseif not intIn(rated, 0, S.StatCap) then
		return refuse(
			op,
			player,
			("RatedMatches %s is not a whole number in 0..%d"):format(tostring(rated), S.StatCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	data.RankXp = plain(xp)
	data.PeakDivision = plain(peak)
	data.RatedMatches = plain(rated)
	commit(player, data)
	return true
end

--- Counts a finished match. `outcome` "Win" | "Loss" | "Draw"; `opponent` "Player" | "PC"
--- (vs PC a win or loss counts in PcWins / PcLosses; a draw counts in Draws either way). A win
--- extends the win streak, a loss ends it, a draw leaves it.
function PlayerData.recordMatch(player: Player, outcome: string, opponent: string): boolean
	local op = "recordMatch"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif outcome ~= "Win" and outcome ~= "Loss" and outcome ~= "Draw" then
		return refuse(op, player, ("outcome %s is not Win, Loss or Draw"):format(tostring(outcome)))
	elseif opponent ~= "Player" and opponent ~= "PC" then
		return refuse(op, player, ("opponent %s is not Player or PC"):format(tostring(opponent)))
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	local stats = data.Stats
	local function bump(key: string)
		stats[key] = math.min(stats[key] + 1, S.StatCap)
	end
	bump("Matches")
	if outcome == "Draw" then
		bump("Draws")
	elseif opponent == "PC" then
		bump(if outcome == "Win" then "PcWins" else "PcLosses")
	else
		bump(if outcome == "Win" then "Wins" else "Losses")
	end
	if outcome == "Win" then
		bump("WinStreak")
		stats.BestWinStreak = math.max(stats.BestWinStreak, stats.WinStreak)
	elseif outcome == "Loss" then
		stats.WinStreak = 0
	end
	commit(player, data)
	return true
end

--- Counts one shot's pocketed balls and nice shots (whole numbers, 0..Config.Save.ShotCountCap
--- each). A shot with neither changes nothing and fires nothing.
function PlayerData.recordShot(player: Player, balls: number, nice: number): boolean
	local op = "recordShot"
	local cap = S.ShotCountCap
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(balls, 0, cap) then
		return refuse(
			op,
			player,
			("balls %s is not a whole number in 0..%d"):format(tostring(balls), cap)
		)
	elseif not intIn(nice, 0, cap) then
		return refuse(
			op,
			player,
			("nice %s is not a whole number in 0..%d"):format(tostring(nice), cap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if balls == 0 and nice == 0 then
		return true
	end
	local stats = data.Stats
	stats.BallsPocketed = math.min(stats.BallsPocketed + balls, S.StatCap)
	stats.NiceShots = math.min(stats.NiceShots + nice, S.StatCap)
	commit(player, data)
	return true
end

--- Resets the player's save to a new player's (the /resetdata dev command). The same table
--- is kept (ProfileStore saves that one): it is emptied and the template copied in.
function PlayerData.reset(player: Player): boolean
	local op = "reset"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	table.clear(data)
	for key, value in SaveSchema.template() do
		data[key] = value
	end
	commit(player, data)
	return true
end

---------------------------------------------------------------------------------------------
-- Studio QA
---------------------------------------------------------------------------------------------

-- Studio only: ServerStorage.PlayerDataQA, a BindableFunction that runs inside this module
-- (the MCP's execute_luau gets its own copies of modules, so tests go through this). Clients
-- cannot reach ServerStorage, and nothing is made in a live server.
-- Invoke(op, userId, ...):
--   "state"                                  -> { dataStoreState, storeName, loaded, isMock }
--   "read"                                   -> the frozen data copy, or nil
--   "addMoney", amount, reason, soloDay?     -> boolean (and "setMoney", "applyRank",
--   "recordMatch", "recordShot", "reset", "soloEarnedToday" with their own arguments)
--   "endSession", kick?                      -> ends the session as if the player left (no
--                                               kick unless `kick` is true: then it runs the
--                                               takeover path and kicks with SessionEnded)
--   "load"                                   -> opens the save again for a player still here
--                                               whose session ended; true once loaded
--   "profileInfo"                            -> { key, sessionLoadCount, active }, or nil
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("PlayerDataQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "PlayerDataQA"
	hook.OnInvoke = function(op: string, userId: number?, a: any, b: any, c: any): any
		if op == "state" then
			local loaded = {}
			for player in profiles do
				table.insert(loaded, player.UserId)
			end
			table.sort(loaded)
			return {
				dataStoreState = ProfileStore.DataStoreState,
				storeName = STORE_NAME,
				loaded = loaded,
				isMock = ProfileStore.DataStoreState ~= "Access",
			}
		end
		local player = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		assert(player, "PlayerDataQA: no player in game with that UserId")
		if op == "read" then
			return PlayerData.read(player)
		elseif op == "addMoney" then
			return PlayerData.addMoney(player, a, b, c)
		elseif op == "setMoney" then
			return PlayerData.setMoney(player, a)
		elseif op == "applyRank" then
			return PlayerData.applyRank(player, a)
		elseif op == "recordMatch" then
			return PlayerData.recordMatch(player, a, b)
		elseif op == "recordShot" then
			return PlayerData.recordShot(player, a, b)
		elseif op == "reset" then
			return PlayerData.reset(player)
		elseif op == "soloEarnedToday" then
			return PlayerData.soloEarnedToday(player, a)
		elseif op == "endSession" then
			local profile = profiles[player]
			if profile == nil then
				return false
			end
			quiet[profile] = a ~= true
			profile:EndSession()
			profiles[player] = nil
			return true
		elseif op == "load" then
			load(player)
			return PlayerData.isLoaded(player)
		elseif op == "profileInfo" then
			local profile = profiles[player]
			if profile == nil then
				return nil
			end
			return {
				key = profile.Key,
				sessionLoadCount = profile.SessionLoadCount,
				active = profile:IsActive(),
			}
		end
		error("PlayerDataQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

--- Opens the store and loads every player's save as they join (and anyone already here).
--- Safe to call more than once.
function PlayerData.start()
	if started then
		return
	end
	started = true
	store = ProfileStore.New(STORE_NAME, SaveSchema.template())
	ProfileStore.OnError:Connect(function(_message: string, storeName: string, key: string)
		-- ProfileStore retries on its own and already printed the error; never log save data.
		warn(("[8ball] PlayerData: DataStore error on store %s, key %s"):format(storeName, key))
	end)
	task.spawn(logDataStoreState)
	Players.PlayerAdded:Connect(function(player)
		task.spawn(load, player)
	end)
	Players.PlayerRemoving:Connect(release)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	startQA()
end

return PlayerData
