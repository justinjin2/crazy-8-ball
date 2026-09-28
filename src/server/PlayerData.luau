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
--   Strings.Save.SessionEnded. A save that cannot be brought up to date (newer code's, or a
--   migration that failed) is released exactly as it was loaded, never half-changed.
-- * Nothing is granted before the save loads or after its session ended: every mutation
--   checks the loaded, active profile, and logs and drops the change otherwise.
-- * Every mutation checks its inputs first (whole numbers in range, known ids and words) and
--   refuses bad ones with one warning, never an error. An ordinary "no" (not enough money,
--   already claimed, not owned) is answered quietly with false or a reason word: players
--   cause those all day, and they are not bugs. None makes a DataStore request of its own
--   (saveNow only asks ProfileStore to save sooner).
-- * A change with several parts (take money and add cases, take cases and add cues, record a
--   purchase and grant it) is ONE mutation: every part is checked first, then all of it is
--   applied, and nothing yields in between, so it can never half-apply. The rules live in the
--   pure, Lune-tested modules (Progression/Inventory, Daily, Shop, Cases); a mutation checks,
--   calls them on the live save and commits (replicate, then fire Changed) only on success.
-- * Everything in Daily belongs to one UTC day: a mutation that touches it rolls it over to
--   today first (rollover), and reads treat another day's Daily as a fresh one (dailyOf).
-- * Callers only ever get frozen copies of the data (or fresh tables), never the live table.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local SaveSchema = require(Shared.Progression.SaveSchema)
local Ranks = require(Shared.Progression.Ranks)
local Catalog = require(Shared.Progression.Catalog)
local Cases = require(Shared.Progression.Cases)
local Inventory = require(Shared.Progression.Inventory)
local Daily = require(Shared.Progression.Daily)
local Settle = require(Shared.Progression.Settle)
local Shop = require(Shared.Progression.Shop)
local ProfileStore = require(script.Parent.Vendor.ProfileStore)

type Profile = ProfileStore.Profile<any>

--- What a reward gives (rank-ups, the daily streak, playtime gifts, codes, dev commands); every
--- field is optional. `money` is money given, not earned in play (no daily caps; it counts in
--- Stats.MoneyEarned). `cases` is { [caseId] = count }. `cues` are catalog ids given one copy
--- each (never Classic or a Unique cue; an Exclusive cue already owned is skipped: one per
--- player). `firstWinCase` marks the first win's Rare Case as given, in the same change
--- (refused when it was given before; see PlayerData.progress).
export type Reward = {
	money: number?,
	cases: { [string]: number }?,
	cues: { string }?,
	firstWinCase: boolean?,
}

--- One cue out of openCases, in the order given.
export type Opened = {
	cue: string,
	new: boolean, -- never owned before this open (the first of two in one open is the new one)
	duplicate: boolean, -- more than one copy once it was added
	count: number, -- copies owned once it was added
	found: number, -- the finder's money it paid (new to the Index), else 0
}

--- A cue that entered a player's Index for the first time, and the finder's money it paid.
export type Find = { cue: string, money: number }

--- PlayerData.progress: the match counts the settle needs.
export type Progress = {
	RealMatches: number, -- real matches played (Rookie Boost: Config.Ranks.Boosts.RookieMatches)
	Wins: number, -- real wins ever, people or PC (the new player's free cases)
	FirstWinCaseDue: boolean, -- the first win's Rare Case was never given
}

--- PlayerData.opponentToday: today's anti-farm count against one account.
export type OpponentDay = { Matches: number, Cases: number }

local S = Config.Save
local BOOSTS = Config.Ranks.Boosts
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
	WinStreak = "WinStreak", -- wins in a row against people (Stats.WinStreak), over the head
	EquippedCue = "EquippedCue", -- the equipped cue's catalog id (everyone's stick and trail)
	RookieLeft = "RookieLeft", -- real matches left in the Rookie Boost (the ROOKIE x2 pill)
	CasesUnopened = "CasesUnopened", -- unopened cases of every type (a red dot)
	-- Something can be claimed now: today's login streak, a playtime gift, or a complete Index
	-- row's reward (a red dot). Also refreshed on a timer: a new UTC day changes it.
	RewardReady = "RewardReady",
	VipOffer = "VipOffer", -- bought VIP through the welcome offer (Store adds the pass: Vip)
}

-- The day's money totals Daily keeps, by the word callers use (Config.Economy's daily caps).
local MONEY_KINDS: { [string]: string } = {
	Solo = "SoloMoney",
	Pc = "PcMoney",
	Short = "ShortMoney",
}

-- Flags[FIRST_WIN_FLAG] = true once the first win's Rare Case was given (Config.Cases
-- .FirstWinCase). Kept apart from Progress.Wins so a first win that an anti-farm rule kept
-- from dropping a case does not use it up (Cases.FreeCaseContext.firstWinEver).
local FIRST_WIN_FLAG = "FirstWinCase"

-- The most playtime one UTC day can hold (SaveSchema's cap on Daily.PlaySeconds).
local SECONDS_PER_DAY = 86400

local PlayerData = {}

local loadedEvent = Instance.new("BindableEvent")
local changedEvent = Instance.new("BindableEvent")
--- (player) Fires once each time a player's save is ready.
PlayerData.Loaded = loadedEvent.Event
--- (player, op) Fires after any successful mutation, once the attributes are updated. `op` is
--- the mutation's name ("openCases", "addPlaySeconds"...), so a listener can skip changes it
--- does not show (addPlaySeconds fires every Config.Daily.PlaytimeTickSeconds).
PlayerData.Changed = changedEvent.Event
local foundEvent = Instance.new("BindableEvent")
--- (player, finds: { Find }) Fires after a mutation that put cues into the player's Index for
--- the first time (the finder's money already added), except the ones a case reel reveals
--- (openCases and the first win's case: their answers carry the money). Items tells the
--- player (the CueFound remote).
PlayerData.CueFound = foundEvent.Event

-- The mutation under way's first finds, by save table (commit sends and clears them), and the
-- saves whose finds a reel shows instead.
local pendingFinds: { [any]: { Find } } = setmetatable({}, { __mode = "k" }) :: any
local reelFinds: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

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

-- refuse() for a mutation that answers (ok, reason): one warning, then (false, "Invalid").
local function refuseInvalid(op: string, player: any, why: string): (boolean, string)
	refuse(op, player, why)
	return false, "Invalid"
end

-- A reason for the logs: a non-empty string.
local function isReason(x: any): boolean
	return type(x) == "string" and x ~= ""
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

-- The live data for a read, or nil (quietly: a read of a player who is not loaded is normal).
local function peek(player: Player): any?
	local profile = profiles[player]
	if profile and profile:IsActive() then
		return profile.Data
	end
	return nil
end

-- A deep copy of save data (only tables, strings, numbers and booleans), frozen or not.
local function copyOf(t: { [any]: any }, freeze: boolean): { [any]: any }
	local copy = {}
	for key, value in t do
		copy[key] = if type(value) == "table" then copyOf(value, freeze) else value
	end
	return if freeze then table.freeze(copy) else copy
end

-- Why `list` is not a gapless array of min..max entries, or nil when it is. Stops counting
-- past `max`, so a huge table from a client costs little.
local function badArray(list: any, name: string, min: number, max: number): string?
	if type(list) ~= "table" then
		return ("%s is not a table"):format(name)
	end
	local n = 0
	for key in list do
		if not SaveSchema.isInteger(key) or key < 1 then
			return ("%s is not an array"):format(name)
		end
		n += 1
		if n > max then
			return ("%s has more than %d entries"):format(name, max)
		end
	end
	for i = 1, n do
		if list[i] == nil then
			return ("%s has gaps"):format(name)
		end
	end
	if n < min then
		return ("%s has %d entries, fewer than %d"):format(name, n, min)
	end
	return nil
end

-- A receipt's PurchaseId as the save keeps it (Shop.Purchases).
local function isPurchaseId(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= S.MaxPurchaseIdLength
end

---------------------------------------------------------------------------------------------
-- The UTC day
---------------------------------------------------------------------------------------------

-- Today's UTC day number (the daily counts, the login streak and the gifts start over when it
-- changes).
local function today(): number
	return Daily.dayOf(os.time())
end

-- Whether a save's Daily belongs to UTC day `day`. A Daily dated tomorrow counts as today:
-- another server's clock was a moment ahead at midnight, and rolling it back would start the
-- day's counts over twice (twice the free cases, twice the capped money). Daily.loginState
-- treats a LastDay of tomorrow the same way.
local function isDay(daily: any, day: number): boolean
	return daily.Day == day or daily.Day == day + 1
end

-- Inside a mutation, before Daily is read or changed: start it over for today unless it
-- belongs to today (SaveSchema.rolloverDaily). Returns today. A rollover alone needs no
-- commit: every read already treats another day's Daily as a fresh one (dailyOf).
local function rollover(data: any): number
	local day = today()
	if not isDay(data.Daily, day) then
		SaveSchema.rolloverDaily(data.Daily, day)
	end
	return day
end

-- A save's Daily as of `day`, for reads: the save's own table when it belongs to that day,
-- else a fresh one (nothing is written).
local function dailyOf(data: any, day: number): any
	return if isDay(data.Daily, day) then data.Daily else SaveSchema.freshDaily(day)
end

-- A UserId as a Daily.Opponents key ("%d": never "1e+15" for a big number).
local function opponentKey(userId: number): string
	return ("%d"):format(userId)
end

---------------------------------------------------------------------------------------------
-- Changing the live save (callers check everything first; none of these can fail halfway)
---------------------------------------------------------------------------------------------

-- Adds money, up to Config.Save.MoneyCap. `earned` also counts it in Stats.MoneyEarned: money
-- from play and rewards, never money bought with Robux or got by selling.
local function addMoneyTo(data: any, amount: number, earned: boolean)
	data.Money = math.min(data.Money + amount, S.MoneyCap)
	if earned then
		data.Stats.MoneyEarned = math.min(data.Stats.MoneyEarned + amount, S.StatCap)
	end
end

-- Adds cases, up to Config.Save.ItemCountCap of one type (a count nobody reaches; past it the
-- extra is dropped rather than growing a number without limit).
local function addCasesTo(data: any, caseId: string, count: number)
	local n = math.min(count, S.ItemCountCap - Inventory.caseCount(data, caseId))
	if n >= 1 then
		Inventory.addCases(data, caseId, n)
	end
end

-- A cue just entered the save's Index for the first time: pay its finder's money (earned;
-- Config.Index.FindMoney) and note it for commit. Returns the money.
local function payFind(data: any, id: string): number
	local money = Inventory.findMoney(id)
	if money > 0 then
		addMoneyTo(data, money, true)
	end
	local finds = pendingFinds[data]
	if finds == nil then
		finds = {}
		pendingFinds[data] = finds
	end
	table.insert(finds, { cue = id, money = money })
	return money
end

-- Gives one copy of a case or Exclusive cue (marked Seen and NEW; a first find pays its
-- finder's money). An Exclusive cue (a rank, the VIP or the Starter Cue) is one per player: it
-- never sells, so a second copy would be worth nothing, and one already owned is not given
-- again. Returns whether it was given.
local function giveCue(data: any, id: string): boolean
	local cue = Catalog.get(id)
	if cue == nil then
		return false
	end
	local have = Inventory.count(data, id)
	if (cue.Group == "Exclusive" and have > 0) or have >= S.ItemCountCap then
		return false
	end
	local given, first = Inventory.addCue(data, id, 1)
	if first then
		payFind(data, id)
	end
	return given
end

-- Gives a Unique cue with its copy number (a first find pays its finder's money).
local function giveUnique(data: any, id: string, copy: number)
	local _, first = Inventory.addUnique(data, id, copy)
	if first then
		payFind(data, id)
	end
end

-- Why `cases` ({ [caseId] = count }) cannot be given, or nil when it can.
local function badCases(cases: any): string?
	if cases == nil then
		return nil
	elseif type(cases) ~= "table" then
		return "cases is not a table"
	end
	for caseId, count in cases do
		if Cases.get(caseId) == nil then
			return ("%s is not a case"):format(tostring(caseId))
		elseif not intIn(count, 0, S.ItemCountCap) then
			return ("case count %s is not a whole number in 0..%d"):format(
				tostring(count),
				S.ItemCountCap
			)
		end
	end
	return nil
end

-- Why a list of cues cannot be given as a reward, or nil: known cues, never Classic (always
-- owned) or a Unique cue (those come numbered: buyLimited, applyPurchase).
local function badGiftCues(cues: any): string?
	if cues == nil then
		return nil
	end
	local why = badArray(cues, "cues", 0, S.MaxSmallEntries)
	if why ~= nil then
		return why
	end
	for _, id in cues do
		local cue = Catalog.get(id)
		if cue == nil then
			return ("%s is not a catalog cue"):format(tostring(id))
		elseif cue.Group == "Default" or cue.Group == "Unique" then
			return ("%s cannot be given (%s)"):format(id, cue.Group)
		end
	end
	return nil
end

local REWARD_FIELDS: { [any]: boolean } =
	{ money = true, cases = true, cues = true, firstWinCase = true }

-- Why a Reward cannot be given, or nil when it can. An unknown field is refused, so a caller
-- passing another shape (say Ranks.rewardFor's single `cue`) never loses part of it quietly.
local function badReward(reward: any): string?
	if type(reward) ~= "table" then
		return "reward is not a table"
	end
	for key in reward do
		if not REWARD_FIELDS[key] then
			return ("reward has an unknown field %s"):format(tostring(key))
		end
	end
	if reward.money ~= nil and not intIn(reward.money, 0, S.GrantCap) then
		return ("money %s is not a whole number in 0..%d"):format(
			tostring(reward.money),
			S.GrantCap
		)
	elseif reward.firstWinCase ~= nil and type(reward.firstWinCase) ~= "boolean" then
		return "firstWinCase is not true or false"
	end
	return badCases(reward.cases) or badGiftCues(reward.cues)
end

-- Why a checked reward cannot go to this save, or nil: the first win's case is given once.
local function blockedReward(data: any, reward: any): string?
	if reward.firstWinCase == true and data.Flags[FIRST_WIN_FLAG] == true then
		return "the first win's case was given before"
	end
	return nil
end

-- Applies a checked, unblocked reward (also a Daily.Reward: { money, cases }): the first-win
-- flag, money (earned), cases in shop order, cues in the order given.
local function giveReward(data: any, reward: any)
	if reward.firstWinCase == true then
		data.Flags[FIRST_WIN_FLAG] = true
	end
	local money = reward.money or 0
	if money > 0 then
		addMoneyTo(data, money, true)
	end
	local cases = reward.cases
	if cases ~= nil then
		for _, caseId in Config.Cases.Order do
			local count = cases[caseId]
			if count ~= nil and count > 0 then
				addCasesTo(data, caseId, count)
			end
		end
	end
	local cues = reward.cues
	if cues ~= nil then
		for _, id in cues do
			giveCue(data, id)
		end
	end
end

-- How many accounts a Daily.Opponents table tracks (a count: the order does not matter).
local function opponentCount(opponents: { [string]: any }): number
	local n = 0
	for _ in opponents do
		n += 1
	end
	return n
end

-- Today's entry for an opponent in Daily.Opponents (Daily already rolled over), made when there
-- is room; nil when the table is full (Config.Economy.SameOpponentMaxEntries: that account is
-- not tracked for the rest of the day, so the table stays bounded, and reads as the worst
-- count, Settle.opponentDay).
local function opponentEntry(daily: any, key: string): any?
	local opponents = daily.Opponents
	local entry = opponents[key]
	if entry == nil then
		if opponentCount(opponents) >= Config.Economy.SameOpponentMaxEntries then
			return nil
		end
		entry = { Matches = 0, Cases = 0 }
		opponents[key] = entry
	end
	return entry
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

-- Unopened cases of every type.
local function casesUnopened(data: any): number
	local total = 0
	for _, caseId in Config.Cases.Order do
		total += Inventory.caseCount(data, caseId)
	end
	return total
end

-- Whether anything can be claimed on UTC day `day`: the login streak, a playtime gift, or a
-- complete Index row whose reward is unclaimed.
local function rewardReady(data: any, day: number): boolean
	if Daily.loginState(data.Login, day).canClaim then
		return true
	end
	for _, gift in Daily.playtimeState(dailyOf(data, day)) do
		if gift.ready then
			return true
		end
	end
	for _, row in Inventory.indexRows(data) do
		if row.complete and not row.claimed and row.reward ~= nil then
			return true
		end
	end
	return false
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
	setAttribute(player, ATTR.WinStreak, data.Stats.WinStreak)
	setAttribute(player, ATTR.EquippedCue, Inventory.equipped(data))
	setAttribute(
		player,
		ATTR.RookieLeft,
		math.max(0, BOOSTS.RookieMatches - data.Progress.RealMatches)
	)
	setAttribute(player, ATTR.CasesUnopened, casesUnopened(data))
	setAttribute(player, ATTR.RewardReady, rewardReady(data, today()))
	setAttribute(player, ATTR.VipOffer, data.Shop.VipOffer == true)
	local rankValue, moneyValue = leaderstats(player)
	local name = Ranks.name(rank)
	if rankValue.Value ~= name then
		rankValue.Value = name
	end
	if moneyValue.Value ~= data.Money then
		moneyValue.Value = data.Money
	end
end

-- Replicates, logging instead of erroring: by the time this runs the save has already changed
-- (or loaded), and a display failure must never undo that or reach the caller as an error (a
-- caller that retried an errored grant would pay it twice). The next change tries again.
local function show(player: Player, data: any)
	local ok, err = pcall(function(): any
		replicate(player, data)
		return nil
	end)
	if not ok then
		warn(
			("[8ball] PlayerData: showing the save of %s failed: %s"):format(
				who(player),
				tostring(err)
			)
		)
	end
end

-- After a mutation: replicate, then tell listeners which mutation it was, then which cues it
-- put in the Index for the first time.
local function commit(player: Player, data: any, op: string)
	show(player, data)
	changedEvent:Fire(player, op)
	local finds = pendingFinds[data]
	local onReel = reelFinds[data] == true
	pendingFinds[data] = nil
	reelFinds[data] = nil
	if finds and #finds > 0 and not onReel then
		foundEvent:Fire(player, finds)
	end
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

-- Brings an opened save up to date and repairs it. Returns nil when it is ready to play on,
-- or why it cannot be used. Everything happens on a copy, and profile.Data only takes the
-- result once every step worked: the caller puts the loaded table back on any failure, so a
-- save that cannot be used is released exactly as it was loaded (a migration that fails
-- halfway must never write a half-migrated save back). Migrations see the save as it was
-- stored; Reconcile then fills the fields the template gained that no migration set; validate
-- repairs the rest. Never yields.
local function prepare(player: Player, profile: Profile): string?
	-- A save written by newer code (a server still on the old version during an update) is
	-- never repaired or played on: Reconcile or validate would add old fields or strip new ones.
	local claimed = (profile.Data :: any).Version
	if SaveSchema.isInteger(claimed) and claimed > SaveSchema.Version then
		return ("future version %d (this code knows up to %d)"):format(claimed, SaveSchema.Version)
	end
	local migrated, notes = SaveSchema.migrate(copyOf(profile.Data :: any, false))
	for _, note in notes do
		if note:sub(1, #"future version") == "future version" then
			return note -- newer code's save (caught above too)
		end
	end
	if type(migrated) ~= "table" or migrated.Version ~= SaveSchema.Version then
		return "could not migrate: " .. table.concat(notes, "; ")
	end
	if #notes > 0 then
		print(
			("[8ball] PlayerData: save of %d: %s"):format(player.UserId, table.concat(notes, "; "))
		)
	end
	profile.Data = migrated
	profile:Reconcile()
	local valid, fixes = SaveSchema.validate(profile.Data)
	if #fixes > 0 then
		warn(
			("[8ball] PlayerData: repaired the save of %d: %s"):format(
				player.UserId,
				table.concat(fixes, "; ")
			)
		)
	end
	-- The migration and the template are pure and have no clock, so the first join is stamped
	-- here (the welcome offer, the comeback window and the Starter Pack count from it). A save
	-- that arrives with FirstJoin 0 is new or from before v2; one from before v2 that already
	-- has wins had its first win before the first win's Rare Case existed, so that case counts
	-- as given (this runs on its first v2 load only, since FirstJoin is set right after).
	local shop = valid.Shop
	if shop.FirstJoin == 0 then
		shop.FirstJoin = os.time()
		if valid.Progress.Wins > 0 and valid.Flags[FIRST_WIN_FLAG] == nil then
			valid.Flags[FIRST_WIN_FLAG] = true
		end
	end
	profile.Data = valid
	return nil
end

-- Opens, updates and repairs a player's save, then replicates it and fires Loaded. Runs in
-- its own thread per player (it yields while the DataStore answers). Every way out ends in a
-- loaded save or a kick; an opened session is never left behind with nobody holding it.
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
	local loaded = profile.Data
	local ok, why = pcall(prepare, player, profile)
	if not ok or why ~= nil then
		profile.Data = loaded -- release it exactly as it was loaded
		abandon(
			player,
			profile,
			if ok then tostring(why) else "preparing errored: " .. tostring(why)
		)
		return
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
	show(player, profile.Data)
	setAttribute(player, ATTR.Loaded, true)
	loadedEvent:Fire(player)
end

-- Players whose save was let go early for a teleport (PlayerData.handOff), so their
-- session's end kicks nobody and a failed teleport can load it again (resume).
local handedOff: { [Player]: boolean } = setmetatable({}, { __mode = "k" }) :: any

--- The player is about to teleport (the global queue): end their save's session now, saved
--- and released, so the server they arrive at opens it at once instead of waiting for this
--- one to let go (designer, 2026-09-28: "no issues with data"). Nothing can be granted from
--- here on, and DataLoaded turns false. Only while nothing is owed: the caller teleports
--- from a pad or after a settled game. True when there was a live save to let go.
function PlayerData.handOff(player: Player): boolean
	local profile = profiles[player]
	if not profile or not profile:IsActive() then
		return false
	end
	handedOff[player] = true
	quiet[profile] = true
	profiles[player] = nil
	profile:EndSession()
	return true
end

--- The teleport failed and the player is still here: open their save again.
function PlayerData.resume(player: Player)
	if not handedOff[player] then
		return
	end
	handedOff[player] = nil
	if present(player) then
		task.spawn(load, player)
	end
end

--- Whether the player's save was let go for a teleport that is under way.
function PlayerData.isHandedOff(player: Player): boolean
	return handedOff[player] == true
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

-- Every Config.Save.ReplicateRefreshSeconds, replicates every loaded save again with no change
-- to it: RewardReady depends on the clock (a new UTC day makes the streak claimable).
local function refreshLoop()
	while true do
		task.wait(S.ReplicateRefreshSeconds)
		for player, profile in profiles do
			if profile:IsActive() and present(player) then
				show(player, profile.Data)
			end
		end
	end
end

-- Whether a saved copy of the data (Profile.LastSavedData, OnAfterSave's argument) holds the
-- purchase id in Shop.Purchases.
local function savedHolds(saved: any, purchaseId: string): boolean
	local shop = if type(saved) == "table" then saved.Shop else nil
	local list = if type(shop) == "table" then shop.Purchases else nil
	return type(list) == "table" and table.find(list, purchaseId) ~= nil
end

---------------------------------------------------------------------------------------------
-- Reads (all return copies or fresh tables; nil or zeros when the save is not loaded)
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
	local data = peek(player)
	return if data ~= nil then copyOf(data, true) else nil
end

--- True once the server has begun shutting down (ProfileStore.IsClosing). From then on (with
--- DataStore access) every save is released and no change lands, and no save opens any more.
--- Roblox does not promise whether players are removed before or after this turns true, so a
--- service must not rely on it alone to tell a shutdown from a player leaving.
function PlayerData.isClosing(): boolean
	return ProfileStore.IsClosing
end

--- The money the player earned in solo on UTC day `day` (0 if another day or not loaded).
function PlayerData.soloEarnedToday(player: Player, day: number): number
	local data = peek(player)
	if data == nil then
		return 0
	end
	return if isDay(data.Daily, day) then data.Daily.SoloMoney else 0
end

--- Today's money total of one kind: "Solo", "Pc" or "Short" (Daily.SoloMoney, PcMoney,
--- ShortMoney; the daily caps of Config.Economy). 0 when another day's or not loaded.
function PlayerData.dailyMoney(player: Player, kind: string): number
	local field = MONEY_KINDS[kind]
	if field == nil then
		refuse("dailyMoney", player, ("kind %s is not Solo, Pc or Short"):format(tostring(kind)))
		return 0
	end
	local data = peek(player)
	if data == nil then
		return 0
	end
	return dailyOf(data, today())[field]
end

--- Today's anti-farm count against one account: { Matches, Cases } (Settle.opponentDay: zeros
--- for an account not met today, another day's table, or a save not loaded; once today's table
--- is full, the worst count for an account it does not track).
function PlayerData.opponentToday(player: Player, userId: number): OpponentDay
	local data = peek(player)
	if data == nil or not SaveSchema.isInteger(userId) then
		return { Matches = 0, Cases = 0 }
	end
	local opponents = dailyOf(data, today()).Opponents
	return Settle.opponentDay(opponents[opponentKey(userId)], opponentCount(opponents))
end

--- A frozen copy of today's Daily (a fresh one when the save's belongs to another day): Day,
--- SoloMoney, PcMoney, ShortMoney, Wins, FirstWinUsed, Opponents, PlaySeconds,
--- PlaytimeClaimed. nil when not loaded.
function PlayerData.dailyState(player: Player): any?
	local data = peek(player)
	if data == nil then
		return nil
	end
	return copyOf(dailyOf(data, today()), true)
end

--- The match counts the settle needs (a frozen table), or nil when not loaded.
function PlayerData.progress(player: Player): Progress?
	local data = peek(player)
	if data == nil then
		return nil
	end
	local progress: Progress = {
		RealMatches = data.Progress.RealMatches,
		Wins = data.Progress.Wins,
		FirstWinCaseDue = data.Flags[FIRST_WIN_FLAG] ~= true,
	}
	return table.freeze(progress)
end

--- Everything the Inventory and Index screens need (Inventory.snapshot: fresh plain tables a
--- remote can carry), or nil when not loaded.
function PlayerData.snapshot(player: Player): Inventory.Snapshot?
	local data = peek(player)
	return if data ~= nil then Inventory.snapshot(data) else nil
end

--- Whether the save already holds this receipt's purchase id (Shop.Purchases).
function PlayerData.hasPurchase(player: Player, purchaseId: string): boolean
	local data = peek(player)
	return data ~= nil and isPurchaseId(purchaseId) and Shop.hasPurchase(data.Shop, purchaseId)
end

---------------------------------------------------------------------------------------------
-- Mutations: money, rank and match stats
---------------------------------------------------------------------------------------------

--- Adds `amount` money (a whole number, 1..Config.Save.GrantCap) earned in play or given as a
--- reward. The total stops at Config.Save.MoneyCap; Stats.MoneyEarned counts it too. `daily`
--- also counts it toward one of today's money totals (the daily caps): "Solo", "Pc" or
--- "Short"; a number there (the older soloDay argument, a UTC day) means "Solo". The totals
--- belong to the server's UTC day and are rolled over first. `reason` says why, for the logs
--- (not saved).
function PlayerData.addMoney(
	player: Player,
	amount: number,
	reason: string,
	daily: (string | number)?
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
	elseif not isReason(reason) then
		return refuse(op, player, "no reason given")
	end
	local field: string? = nil
	if type(daily) == "number" then
		if not intIn(daily, 0, S.StatCap) then
			return refuse(
				op,
				player,
				("soloDay %s is not a whole number >= 0"):format(tostring(daily))
			)
		end
		field = MONEY_KINDS.Solo
	elseif daily ~= nil then
		field = MONEY_KINDS[daily :: any]
		if field == nil then
			return refuse(op, player, ("daily %s is not Solo, Pc or Short"):format(tostring(daily)))
		end
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	addMoneyTo(data, amount, true)
	if field ~= nil then
		rollover(data)
		data.Daily[field] = math.min(data.Daily[field] + amount, S.MoneyCap)
	end
	commit(player, data, op)
	return true
end

--- Counts `amount` (a whole number, 0..Config.Save.MoneyCap) toward one of today's money
--- totals without adding any money: "Pc", "Short" or "Solo". The settle adds a short match's
--- money (paid live, shot by shot) to the Short total this way. 0 changes nothing.
function PlayerData.addDailyMoney(player: Player, kind: string, amount: number): boolean
	local op = "addDailyMoney"
	local field = MONEY_KINDS[kind]
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif field == nil then
		return refuse(op, player, ("kind %s is not Solo, Pc or Short"):format(tostring(kind)))
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
	if amount == 0 then
		return true
	end
	rollover(data)
	data.Daily[field] = math.min(data.Daily[field] + amount, S.MoneyCap)
	commit(player, data, op)
	return true
end

--- Takes `amount` money (a whole number, 1..Config.Save.MoneyCap). False, and nothing
--- changes, when the player has less (quietly). `reason` says why, for the logs.
function PlayerData.spend(player: Player, amount: number, reason: string): boolean
	local op = "spend"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(amount, 1, S.MoneyCap) then
		return refuse(
			op,
			player,
			("amount %s is not a whole number in 1..%d"):format(tostring(amount), S.MoneyCap)
		)
	elseif not isReason(reason) then
		return refuse(op, player, "no reason given")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if data.Money < amount then
		return false
	end
	data.Money = plain(data.Money - amount)
	commit(player, data, op)
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
	commit(player, data, op)
	return true
end

--- Gives a reward (see the Reward type): rank-ups, the daily streak, gifts, codes, dev
--- commands. All of it or nothing: a bad field refuses the whole reward. `reason` says why,
--- for the logs. A cue new to the Index pays its finder's money (CueFound tells the player,
--- except for the first win's case, which the result screen's reel reveals).
function PlayerData.grantReward(player: Player, reward: Reward, reason: string): boolean
	local op = "grantReward"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not isReason(reason) then
		return refuse(op, player, "no reason given")
	end
	local why = badReward(reward)
	if why ~= nil then
		return refuse(op, player, why)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	local blocked = blockedReward(data, reward)
	if blocked ~= nil then
		return refuse(op, player, blocked)
	end
	giveReward(data, reward)
	if reward.firstWinCase == true then
		reelFinds[data] = true -- the result screen's reel shows the first win's cue
	end
	commit(player, data, op)
	return true
end

--- Sets the rank fields together (the Ranking service's result, or /rank). Each must be a
--- whole number in range, or nothing changes. `reward` (optional, the Reward type: the
--- rank-up's money, cases and tier cue) is given in the same change, so a rank-up and its
--- reward can never be split.
function PlayerData.applyRank(
	player: Player,
	rank: { RankXp: number, PeakDivision: number, RatedMatches: number },
	reward: Reward?
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
	if reward ~= nil then
		local why = badReward(reward)
		if why ~= nil then
			return refuse(op, player, "reward: " .. why)
		end
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if reward ~= nil then
		local blocked = blockedReward(data, reward)
		if blocked ~= nil then
			return refuse(op, player, "reward: " .. blocked)
		end
	end
	data.RankXp = plain(xp)
	data.PeakDivision = plain(peak)
	data.RatedMatches = plain(rated)
	if reward ~= nil then
		giveReward(data, reward)
	end
	commit(player, data, op)
	return true
end

--- Counts a finished match. `outcome` "Win" | "Loss" | "Draw"; `opponent` "Player" | "PC"
--- (vs PC a win or loss counts in PcWins / PcLosses; a draw counts in Draws either way). A win
--- against people extends the win streak (a PC win leaves it, as the settle's own count
--- does), a loss ends it, a draw leaves it. Only real matches come here (Ranking).
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
	local counts = opponent == "Player"
	stats.WinStreak = math.min(Ranks.nextStreak(stats.WinStreak, outcome, counts), S.StatCap)
	stats.BestWinStreak = math.max(stats.BestWinStreak, stats.WinStreak)
	commit(player, data, op)
	return true
end

--- Ends the player's win streak: a loss that recordMatch did not count (a forfeit under the
--- one-minute mark, leaving mid-match), which must still end it (Ranks.nextStreak). Nothing
--- happens (no save change) when there is no streak.
function PlayerData.endStreak(player: Player): boolean
	local op = "endStreak"
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if data.Stats.WinStreak == 0 then
		return true
	end
	data.Stats.WinStreak = Ranks.nextStreak(data.Stats.WinStreak, "Loss", false)
	commit(player, data, op)
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
	commit(player, data, op)
	return true
end

---------------------------------------------------------------------------------------------
-- Mutations: match bookkeeping for the settle (Progress and today's Daily)
---------------------------------------------------------------------------------------------

--- Counts a real match (past the one-minute mark, not solo; people or PC): Progress.RealMatches
--- +1; a win also adds Progress.Wins and today's Daily.Wins; each opponent's
--- Daily.Opponents[userId].Matches +1 (`opponentUserIds`: the other side's UserIds, empty
--- against PC; duplicates and the player's own id are skipped; an account new today is not
--- tracked once the table holds Config.Economy.SameOpponentMaxEntries, and reads as the worst
--- count instead, Settle.opponentDay).
function PlayerData.recordRealMatch(
	player: Player,
	won: boolean,
	opponentUserIds: { number }
): boolean
	local op = "recordRealMatch"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif type(won) ~= "boolean" then
		return refuse(op, player, "won is not true or false")
	end
	local why =
		badArray(opponentUserIds, "opponentUserIds", 0, Config.Economy.SameOpponentMaxEntries)
	if why ~= nil then
		return refuse(op, player, why)
	end
	for _, id in opponentUserIds do
		if not SaveSchema.isInteger(id) then
			return refuse(op, player, ("opponent %s is not a UserId"):format(tostring(id)))
		end
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	rollover(data)
	local progress, daily = data.Progress, data.Daily
	progress.RealMatches = math.min(progress.RealMatches + 1, S.StatCap)
	if won then
		progress.Wins = math.min(progress.Wins + 1, S.StatCap)
		daily.Wins = math.min(daily.Wins + 1, S.StatCap)
	end
	local counted: { [string]: boolean } = {}
	for _, id in opponentUserIds do
		local key = opponentKey(id)
		if id ~= player.UserId and not counted[key] then
			counted[key] = true
			local entry = opponentEntry(daily, key)
			if entry ~= nil then
				entry.Matches = math.min(entry.Matches + 1, S.StatCap)
			end
		end
	end
	commit(player, data, op)
	return true
end

--- Uses today's first-win XP boost: true only when it was unused today (it is then marked).
function PlayerData.useFirstWin(player: Player): boolean
	local op = "useFirstWin"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	rollover(data)
	if data.Daily.FirstWinUsed then
		return false
	end
	data.Daily.FirstWinUsed = true
	commit(player, data, op)
	return true
end

--- Counts a free case won from one account today (Daily.Opponents[userId].Cases +1; the
--- anti-farm limit Config.Economy.FreeCasesPerOpponent). False when the table is full and
--- that account is not tracked today (it already reads as at the limit, Settle.opponentDay).
function PlayerData.addOpponentCase(player: Player, opponentUserId: number): boolean
	local op = "addOpponentCase"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not SaveSchema.isInteger(opponentUserId) then
		return refuse(op, player, ("opponent %s is not a UserId"):format(tostring(opponentUserId)))
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	rollover(data)
	local entry = opponentEntry(data.Daily, opponentKey(opponentUserId))
	if entry == nil then
		return false
	end
	entry.Cases = math.min(entry.Cases + 1, S.StatCap)
	commit(player, data, op)
	return true
end

--- Sets Progress.RealMatches (the /rookie dev command): a whole number, 0..Config.Save.StatCap.
function PlayerData.setRealMatches(player: Player, n: number): boolean
	local op = "setRealMatches"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(n, 0, S.StatCap) then
		return refuse(
			op,
			player,
			("n %s is not a whole number in 0..%d"):format(tostring(n), S.StatCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	data.Progress.RealMatches = plain(n)
	commit(player, data, op)
	return true
end

---------------------------------------------------------------------------------------------
-- Mutations: cases and cues (the Items service)
---------------------------------------------------------------------------------------------

--- Buys `count` cases (1..Config.Save.ItemCountCap) of a case sold in the shop for `price`
--- money (0..MoneyCap; the caller priced it with Cases.price and checked PolicyService), in
--- one change. False, and nothing changes, when the money is short (quietly).
function PlayerData.buyCases(player: Player, caseId: string, count: number, price: number): boolean
	local op = "buyCases"
	local case = Cases.get(caseId)
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif case == nil then
		return refuse(op, player, ("%s is not a case"):format(tostring(caseId)))
	elseif not case.Enabled then
		return refuse(op, player, ("%s is not sold (switched off)"):format(caseId))
	elseif not intIn(count, 1, S.ItemCountCap) then
		return refuse(
			op,
			player,
			("count %s is not a whole number in 1..%d"):format(tostring(count), S.ItemCountCap)
		)
	elseif not intIn(price, 0, S.MoneyCap) then
		return refuse(
			op,
			player,
			("price %s is not a whole number in 0..%d"):format(tostring(price), S.MoneyCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if data.Money < price then
		return false
	end
	if Inventory.caseCount(data, caseId) + count > S.ItemCountCap then
		return refuse(
			op,
			player,
			("would hold more than %d %s cases"):format(S.ItemCountCap, caseId)
		)
	end
	data.Money = plain(data.Money - price)
	Inventory.addCases(data, caseId, count)
	commit(player, data, op)
	return true
end

--- Opens #cueIds cases of `caseId` (1..Config.Cases.FastOpenCount; the caller rolled each cue
--- with Cases.roll) and adds those cues, in one change. Answers (true, { Opened }) in the
--- order given, or (false, reason): "NotEnough" (fewer cases than cues), "NotLoaded",
--- "Invalid" (logged: an unknown case, or a cue that case cannot drop: a case cue that lists
--- the case, of a rarity the case has odds for; a vaulted cue is still accepted, so vaulting
--- never fails an open already rolled).
function PlayerData.openCases(
	player: Player,
	caseId: string,
	cueIds: { string }
): (boolean, { Opened } | string)
	local op = "openCases"
	local case = Cases.get(caseId)
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	elseif case == nil then
		return refuseInvalid(op, player, ("%s is not a case"):format(tostring(caseId)))
	end
	local why = badArray(cueIds, "cueIds", 1, Config.Cases.FastOpenCount)
	if why ~= nil then
		return refuseInvalid(op, player, why)
	end
	for _, id in cueIds do
		local cue = Catalog.get(id)
		if
			cue == nil
			or cue.Group ~= "Case"
			or table.find(cue.Cases, caseId) == nil
			or (case.Odds[cue.Rarity] or 0) <= 0
		then
			return refuseInvalid(
				op,
				player,
				("%s does not drop from %s"):format(tostring(id), caseId)
			)
		end
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	local n = #cueIds
	if Inventory.caseCount(data, caseId) < n then
		return false, "NotEnough"
	end
	for _, id in cueIds do
		if Inventory.count(data, id) + n > S.ItemCountCap then
			return refuseInvalid(
				op,
				player,
				("would hold more than %d of %s"):format(S.ItemCountCap, id)
			)
		end
	end
	Inventory.takeCases(data, caseId, n)
	local seen = data.Index.Seen
	local opened: { Opened } = {}
	for _, id in cueIds do
		local new = seen[id] ~= true and not Inventory.owns(data, id)
		local _, first = Inventory.addCue(data, id, 1)
		local found = if first then payFind(data, id) else 0
		local count = Inventory.count(data, id)
		table.insert(
			opened,
			{ cue = id, new = new, duplicate = count > 1, count = count, found = found }
		)
	end
	reelFinds[data] = true -- the reel shows them
	commit(player, data, op)
	return true, opened
end

--- Sells `count` copies (1..Config.Save.ItemCountCap) of a cue back and adds the money (not
--- MoneyEarned). Answers (true, money) or (false, reason): Inventory.canSell's "Unknown",
--- "NotSellable", "NotOwned", "TooMany", "Equipped" (the last copy of the equipped cue), or
--- "NotLoaded" / "Invalid".
function PlayerData.sellCue(
	player: Player,
	cueId: string,
	count: number
): (boolean, number | string)
	local op = "sellCue"
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	elseif not intIn(count, 1, S.ItemCountCap) then
		return refuseInvalid(
			op,
			player,
			("count %s is not a whole number in 1..%d"):format(tostring(count), S.ItemCountCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, result = Inventory.sell(data, cueId, count)
	if not ok then
		return false, result
	end
	local money = result :: number
	if money > 0 then
		addMoneyTo(data, money, false)
	end
	commit(player, data, op)
	return true, money
end

--- Sells every duplicate, keeping one of each: only `cueId`'s when given, else every case
--- cue's. Answers (true, money, sold) with Inventory.Sold rows in catalog order ((true, 0, {})
--- when there was nothing to sell; nothing changes), or (false, 0, {}) when not loaded or
--- `cueId` is not a catalog cue (logged).
function PlayerData.sellDuplicates(
	player: Player,
	cueId: string?
): (boolean, number, { Inventory.Sold })
	local op = "sellDuplicates"
	if not isPlayer(player) then
		refuse(op, player, "not a player")
		return false, 0, {}
	elseif cueId ~= nil and not Catalog.exists(cueId) then
		refuse(op, player, ("%s is not a catalog cue"):format(tostring(cueId)))
		return false, 0, {}
	end
	local data = liveData(op, player)
	if data == nil then
		return false, 0, {}
	end
	local total, sold = Inventory.sellDuplicates(data, cueId)
	if #sold == 0 then
		return true, 0, sold
	end
	if total > 0 then
		addMoneyTo(data, total, false)
	end
	commit(player, data, op)
	return true, total, sold
end

--- Equips an owned cue (Classic always). False when not owned (quietly).
function PlayerData.equipCue(player: Player, cueId: string): boolean
	local op = "equipCue"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not Catalog.exists(cueId) then
		return refuse(op, player, ("%s is not a catalog cue"):format(tostring(cueId)))
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if not Inventory.owns(data, cueId) then
		return false
	end
	if data.Equipped.Cue == cueId then
		return true
	end
	Inventory.equip(data, cueId)
	commit(player, data, op)
	return true
end

--- Clears the NEW tag of each cue id in `ids` (an array of at most Config.Items.MarkSeenMax).
--- Returns how many were cleared (0 changes nothing and fires nothing).
function PlayerData.markSeen(player: Player, ids: { string }): number
	local op = "markSeen"
	if not isPlayer(player) then
		refuse(op, player, "not a player")
		return 0
	end
	local why = badArray(ids, "ids", 0, Config.Items.MarkSeenMax)
	if why ~= nil then
		refuse(op, player, why)
		return 0
	end
	local data = liveData(op, player)
	if data == nil then
		return 0
	end
	local cleared = Inventory.markSeen(data, ids)
	if cleared > 0 then
		commit(player, data, op)
	end
	return cleared
end

--- Claims a complete Index row once: marks it and its title, adds its money (earned).
--- Answers (true, { money, title }) or (false, reason): Inventory.claimRow's "Unknown",
--- "NoReward" (Exclusive, Unique), "Claimed", "Incomplete", or "NotLoaded".
function PlayerData.claimIndexRow(player: Player, rarity: string): (boolean, any)
	local op = "claimIndexRow"
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, result = Inventory.claimRow(data, rarity)
	if not ok then
		return false, result
	end
	if result.money > 0 then
		addMoneyTo(data, result.money, true)
	end
	commit(player, data, op)
	return true, { money = result.money, title = result.title }
end

--- Dev (/clearinv): takes every cue but Classic and every case, clears the NEW tags, equips
--- Classic, and forgets the one-per-player guards of the cues it took (Shop.Limited,
--- Shop.VipCueGiven), so buying a Limited and getting the VIP Cue can be tested again.
--- Index.Seen, the Index rows and titles stay.
function PlayerData.clearInventory(player: Player): boolean
	local op = "clearInventory"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	local inventory = data.Inventory
	inventory.Cues = {}
	inventory.Unique = {}
	inventory.Cases = {}
	inventory.New = {}
	data.Equipped.Cue = Catalog.Default
	data.Shop.Limited = {}
	data.Shop.VipCueGiven = false
	commit(player, data, op)
	return true
end

---------------------------------------------------------------------------------------------
-- Mutations: daily streak, playtime, codes (the Rewards service)
---------------------------------------------------------------------------------------------

--- Claims today's login streak reward (Daily.claimLogin at today's UTC day) and gives its
--- money and cases, in one change. Answers (true, Daily.Reward) or (false, "Claimed" |
--- "NotLoaded").
function PlayerData.claimDaily(player: Player): (boolean, Daily.Reward | string)
	local op = "claimDaily"
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, login, reward = Daily.claimLogin(data.Login, today())
	if not ok or reward == nil then
		return false, "Claimed"
	end
	data.Login = login
	giveReward(data, reward)
	commit(player, data, op)
	return true, reward
end

--- Dev (/setday): the next claim (today's) becomes streak day `n` (1..#Config.Daily.Streak) of
--- week `week` (1..Config.Daily.WeeksForBonus; default the week today's claim is in), even
--- when today was claimed already (Daily.setStreakDay).
function PlayerData.setStreakDay(player: Player, n: number, week: number?): boolean
	local op = "setStreakDay"
	local days, weeks = #Config.Daily.Streak, Config.Daily.WeeksForBonus
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(n, 1, days) then
		return refuse(op, player, ("n %s is not a whole number in 1..%d"):format(tostring(n), days))
	elseif week ~= nil and not intIn(week, 1, weeks) then
		return refuse(
			op,
			player,
			("week %s is not a whole number in 1..%d"):format(tostring(week), weeks)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	data.Login = Daily.setStreakDay(data.Login, today(), n, week)
	commit(player, data, op)
	return true
end

--- Dev (/newday): plays the save forward as if a new UTC day had begun. Login.LastDay moves
--- back one day, so a claim made today reads as yesterday's and the next claim continues the
--- streak; a claim from yesterday reads as two days ago, so the streak starts over, exactly as
--- a real missed day would. Today's Daily starts over (money totals, wins, the first-win
--- boost, the opponents, playtime and its gifts). Shop times (the offers) are not moved.
function PlayerData.newDay(player: Player): boolean
	local op = "newDay"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	local login = data.Login
	if login.LastDay > 0 then
		login.LastDay = plain(login.LastDay - 1)
	end
	-- rolloverDaily only starts over a table that belongs to another day: date it yesterday so
	-- today's counts start over too.
	local day = today()
	data.Daily.Day = day - 1
	SaveSchema.rolloverDaily(data.Daily, day)
	commit(player, data, op)
	return true
end

--- Adds playtime to today's count (Daily.PlaySeconds, rolled over first, at most one day's
--- worth). `seconds` is a whole number, 0..86400; 0 changes nothing.
function PlayerData.addPlaySeconds(player: Player, seconds: number): boolean
	local op = "addPlaySeconds"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(seconds, 0, SECONDS_PER_DAY) then
		return refuse(
			op,
			player,
			("seconds %s is not a whole number in 0..%d"):format(tostring(seconds), SECONDS_PER_DAY)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if seconds == 0 then
		return true
	end
	rollover(data)
	data.Daily.PlaySeconds = math.min(data.Daily.PlaySeconds + seconds, SECONDS_PER_DAY)
	commit(player, data, op)
	return true
end

--- Dev (/playtime): sets today's playtime to `minutes` (a whole number, 0..1440). The gifts
--- claimed today stay claimed (/newday starts them over).
function PlayerData.setPlayMinutes(player: Player, minutes: number): boolean
	local op = "setPlayMinutes"
	local most = SECONDS_PER_DAY // 60
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not intIn(minutes, 0, most) then
		return refuse(
			op,
			player,
			("minutes %s is not a whole number in 0..%d"):format(tostring(minutes), most)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	rollover(data)
	data.Daily.PlaySeconds = plain(minutes * 60)
	commit(player, data, op)
	return true
end

--- Claims today's playtime gift `index` (1..#Config.Daily.Playtime) and gives its money and
--- cases, in one change. Answers (true, Daily.Reward) or (false, reason):
--- Daily.claimPlaytime's "Unknown", "Claimed", "NotReady", or "NotLoaded".
function PlayerData.claimPlaytime(player: Player, index: number): (boolean, Daily.Reward | string)
	local op = "claimPlaytime"
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	rollover(data)
	local ok, result = Daily.claimPlaytime(data.Daily, index)
	if not ok then
		return false, result
	end
	giveReward(data, result)
	commit(player, data, op)
	return true, result
end

--- Redeems typed text as a promo code (Daily.redeem at the server's time) and gives its money
--- and cases, in one change. Answers (true, Daily.Reward) or (false, reason): "Bad" (not a
--- possible code), "Unknown", "Used", "Expired", or "NotLoaded".
function PlayerData.redeemCode(player: Player, text: string): (boolean, Daily.Reward | string)
	local op = "redeemCode"
	if not isPlayer(player) then
		return refuseInvalid(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false, "NotLoaded"
	end
	local ok, result = Daily.redeem(data.Codes, text, os.time())
	if not ok then
		return false, result
	end
	giveReward(data, result)
	commit(player, data, op)
	return true, result
end

---------------------------------------------------------------------------------------------
-- Mutations: purchases (the Store service)
---------------------------------------------------------------------------------------------

local GRANT_FIELDS: { [any]: boolean } = {
	key = true,
	money = true,
	cue = true,
	vip = true,
	vipCue = true,
	party = true,
	limited = true,
	firstPack = true,
	starterBought = true,
}
local GRANT_FLAGS = { "vip", "vipCue", "party", "firstPack", "starterBought" }

-- Why a Shop.grantFor grant (with the Limited copy number, when it names one) cannot be
-- applied, or nil when it can.
local function badGrant(grant: any, copy: any): string?
	if type(grant) ~= "table" then
		return "grant is not a table"
	end
	for key in grant do
		if not GRANT_FIELDS[key] then
			return ("grant has an unknown field %s"):format(tostring(key))
		end
	end
	if not SaveSchema.isId(grant.key) then
		return "grant.key is not a product key"
	elseif not intIn(grant.money, 0, S.GrantCap) then
		return ("grant.money %s is not a whole number in 0..%d"):format(
			tostring(grant.money),
			S.GrantCap
		)
	end
	for _, flag in GRANT_FLAGS do
		if grant[flag] ~= nil and type(grant[flag]) ~= "boolean" then
			return ("grant.%s is not true or false"):format(flag)
		end
	end
	if grant.cue ~= nil then
		local cue = Catalog.get(grant.cue)
		if cue == nil or cue.Group == "Default" or cue.Group == "Unique" then
			return ("grant.cue %s cannot be given"):format(tostring(grant.cue))
		end
	end
	if grant.limited ~= nil then
		local cue = Catalog.get(grant.limited)
		if cue == nil or cue.Group ~= "Unique" or Shop.limitedFor(grant.limited) == nil then
			return ("grant.limited %s is not a Limited cue"):format(tostring(grant.limited))
		elseif not intIn(copy, 1, S.CopyNumberCap) then
			return ("copy %s is not a whole number in 1..%d"):format(
				tostring(copy),
				S.CopyNumberCap
			)
		end
	elseif copy ~= nil then
		return "a copy number without grant.limited"
	end
	return nil
end

--- Records a developer product purchase and applies its grant (Shop.grantFor) in ONE change,
--- so a receipt is never granted without its id recorded, nor recorded without its grant:
--- Shop.recordPurchase, the grant's money (bought: not MoneyEarned), its cue (the VIP Cue only
--- while Shop.VipCueGiven is false; an Exclusive cue already owned is not given twice), its
--- Limited cue with copy number `copy` (required with grant.limited: the caller's Limited
--- counter handed it out; refused, logged, when the player already owns that cue, so the
--- Store must not prompt then) and its Shop flags (Shop.markGrant). grant.party is the
--- caller's (this server's Money Party). A purchase id already recorded grants nothing and
--- answers true (it was granted before). The caller then waits for saveNow.
function PlayerData.applyPurchase(
	player: Player,
	purchaseId: string,
	grant: Shop.Grant,
	copy: number?
): boolean
	local op = "applyPurchase"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif not isPurchaseId(purchaseId) then
		return refuse(op, player, "purchaseId is not a receipt's purchase id")
	end
	local why = badGrant(grant, copy)
	if why ~= nil then
		return refuse(op, player, why)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	local shop = data.Shop
	if Shop.hasPurchase(shop, purchaseId) then
		return true
	end
	local limited = grant.limited
	if limited ~= nil and (Inventory.owns(data, limited) or shop.Limited[limited] ~= nil) then
		return refuse(op, player, ("already owns the Limited %s"):format(limited))
	end
	Shop.recordPurchase(shop, purchaseId)
	if grant.money > 0 then
		addMoneyTo(data, grant.money, false)
	end
	if grant.cue ~= nil and not (grant.vipCue and shop.VipCueGiven) then
		giveCue(data, grant.cue)
	end
	if limited ~= nil and copy ~= nil then
		giveUnique(data, limited, copy)
		shop.Limited[limited] = copy
	end
	Shop.markGrant(shop, grant)
	commit(player, data, op)
	return true
end

--- Buys a Limited cue (a Unique cue on Config.Shop.Limited) numbered `copy` (1..CopyNumberCap,
--- from the caller's atomic counter) for `price` money (0..MoneyCap), in one change: takes the
--- money, adds the cue (Inventory.addUnique), records Shop.Limited. Refused, logged, when the
--- player owns it already or has less money than `price` (the caller checks both before it
--- takes a number, so either means a copy number went unused).
function PlayerData.buyLimited(player: Player, cueId: string, copy: number, price: number): boolean
	local op = "buyLimited"
	local cue = Catalog.get(cueId)
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif cue == nil or cue.Group ~= "Unique" or Shop.limitedFor(cueId) == nil then
		return refuse(op, player, ("%s is not a Limited cue"):format(tostring(cueId)))
	elseif not intIn(copy, 1, S.CopyNumberCap) then
		return refuse(
			op,
			player,
			("copy %s is not a whole number in 1..%d"):format(tostring(copy), S.CopyNumberCap)
		)
	elseif not intIn(price, 0, S.MoneyCap) then
		return refuse(
			op,
			player,
			("price %s is not a whole number in 0..%d"):format(tostring(price), S.MoneyCap)
		)
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if Inventory.owns(data, cueId) or data.Shop.Limited[cueId] ~= nil then
		return refuse(op, player, ("already owns %s (copy %d unused)"):format(cueId, copy))
	elseif data.Money < price then
		return refuse(op, player, ("not enough money for %s (copy %d unused)"):format(cueId, copy))
	end
	data.Money = plain(data.Money - price)
	giveUnique(data, cueId, copy)
	data.Shop.Limited[cueId] = copy
	commit(player, data, op)
	return true
end

--- Gives the VIP Cue (Config.Shop.VipCue) once ever, however VIP came (the pass or the
--- welcome offer): true when given now, false when it was given before (quietly).
function PlayerData.giveVipCue(player: Player): boolean
	local op = "giveVipCue"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if data.Shop.VipCueGiven then
		return false
	end
	giveCue(data, Config.Shop.VipCue)
	data.Shop.VipCueGiven = true
	commit(player, data, op)
	return true
end

--- Asks ProfileStore to save now (Profile:Save()) and waits up to `timeoutSeconds` for a save
--- to reach the DataStore. With `purchaseId` (ProcessReceipt) only a save whose stored data
--- holds that id in Shop.Purchases counts, which is exact: true at once when the last save
--- already holds it, and never true for a save that started before the grant or one written
--- by another server that took the session over. Without it, the first save that completes
--- after the call counts (an autosave already under way could be it). A session that ends
--- while waiting still makes its last save, which counts the same way. False when not loaded
--- (and nothing saved holds the id) or on timeout. Yields.
function PlayerData.saveNow(player: Player, timeoutSeconds: number, purchaseId: string?): boolean
	local op = "saveNow"
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif
		not (type(timeoutSeconds) == "number" and timeoutSeconds > 0 and timeoutSeconds < math.huge)
	then
		return refuse(
			op,
			player,
			("timeout %s is not a positive number"):format(tostring(timeoutSeconds))
		)
	elseif purchaseId ~= nil and not isPurchaseId(purchaseId) then
		return refuse(op, player, "purchaseId is not a receipt's purchase id")
	end
	local profile = profiles[player]
	if profile ~= nil and purchaseId ~= nil and savedHolds(profile.LastSavedData, purchaseId) then
		return true
	end
	if not (profile and profile:IsActive()) then
		warn(("[8ball] PlayerData: %s dropped for %s: not loaded"):format(op, who(player)))
		return false
	end
	local active = profile :: Profile
	local caller = coroutine.running()
	local result: boolean? = nil
	local waiting = false
	local connection: { Disconnect: (any) -> () }? = nil
	local timer: thread? = nil
	local function finish(value: boolean)
		if result ~= nil then
			return
		end
		result = value
		if connection then
			connection:Disconnect()
		end
		-- The timer clears itself before it finishes, so this never cancels the running thread.
		if timer then
			task.cancel(timer)
		end
		-- Only resume the caller once it yielded (a save could finish inside Save() itself).
		if waiting then
			task.spawn(caller, value)
		end
	end
	connection = active.OnAfterSave:Connect(function(saved: any)
		if purchaseId == nil or savedHolds(saved, purchaseId) then
			finish(true)
		end
	end)
	timer = task.delay(timeoutSeconds, function()
		timer = nil
		finish(false)
	end)
	active:Save()
	if result ~= nil then
		return result
	end
	waiting = true
	return coroutine.yield()
end

--- Gives a title (an id in Strings.Items.Titles) outside the Index: the first Reyes ever's
--- one-of-one (Announce, Config.Items.FirstReyesTitle). True when given now, false when already
--- held (quietly) or refused (logged: an unknown title, or Config.Save.MaxTitleEntries held).
function PlayerData.addTitle(player: Player, titleId: string): boolean
	local op = "addTitle"
	local names: { [string]: string } = Strings.Items.Titles :: any
	if not isPlayer(player) then
		return refuse(op, player, "not a player")
	elseif type(titleId) ~= "string" or names[titleId] == nil then
		return refuse(op, player, ("%s is not a title"):format(tostring(titleId)))
	end
	local data = liveData(op, player)
	if data == nil then
		return false
	end
	if data.Titles[titleId] == true then
		return false
	end
	local held = 0
	for _ in data.Titles do
		held += 1
	end
	if held >= S.MaxTitleEntries then
		return refuse(op, player, ("already holds %d titles"):format(held))
	end
	data.Titles[titleId] = true
	commit(player, data, op)
	return true
end

---------------------------------------------------------------------------------------------
-- Dev
---------------------------------------------------------------------------------------------

--- Resets the player's save to a new player's (the /resetdata dev command). The same table
--- is kept (ProfileStore saves that one): it is emptied and the template copied in, and the
--- first join is now (as a new player's first load sets it), so the offers open again.
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
	data.Shop.FirstJoin = os.time()
	commit(player, data, op)
	return true
end

---------------------------------------------------------------------------------------------
-- Studio QA
---------------------------------------------------------------------------------------------

-- The hook's plain calls: op -> (player, a, b, c, d) -> the function's results (a tuple).
local QA_CALLS: { [string]: (Player, any, any, any, any) -> ...any } = {
	read = function(p)
		return PlayerData.read(p)
	end,
	snapshot = function(p)
		return PlayerData.snapshot(p)
	end,
	progress = function(p)
		return PlayerData.progress(p)
	end,
	dailyState = function(p)
		return PlayerData.dailyState(p)
	end,
	dailyMoney = function(p, a)
		return PlayerData.dailyMoney(p, a)
	end,
	opponentToday = function(p, a)
		return PlayerData.opponentToday(p, a)
	end,
	soloEarnedToday = function(p, a)
		return PlayerData.soloEarnedToday(p, a)
	end,
	hasPurchase = function(p, a)
		return PlayerData.hasPurchase(p, a)
	end,
	addMoney = function(p, a, b, c)
		return PlayerData.addMoney(p, a, b, c)
	end,
	addDailyMoney = function(p, a, b)
		return PlayerData.addDailyMoney(p, a, b)
	end,
	spend = function(p, a, b)
		return PlayerData.spend(p, a, b)
	end,
	setMoney = function(p, a)
		return PlayerData.setMoney(p, a)
	end,
	grantReward = function(p, a, b)
		return PlayerData.grantReward(p, a, b)
	end,
	applyRank = function(p, a, b)
		return PlayerData.applyRank(p, a, b)
	end,
	recordMatch = function(p, a, b)
		return PlayerData.recordMatch(p, a, b)
	end,
	endStreak = function(p)
		return PlayerData.endStreak(p)
	end,
	recordShot = function(p, a, b)
		return PlayerData.recordShot(p, a, b)
	end,
	recordRealMatch = function(p, a, b)
		return PlayerData.recordRealMatch(p, a, b)
	end,
	useFirstWin = function(p)
		return PlayerData.useFirstWin(p)
	end,
	addOpponentCase = function(p, a)
		return PlayerData.addOpponentCase(p, a)
	end,
	setRealMatches = function(p, a)
		return PlayerData.setRealMatches(p, a)
	end,
	buyCases = function(p, a, b, c)
		return PlayerData.buyCases(p, a, b, c)
	end,
	openCases = function(p, a, b)
		return PlayerData.openCases(p, a, b)
	end,
	-- QA only: rolls `b` cues of case `a` (Cases.roll with Random.new(), as the Items service
	-- will) and opens them.
	openRolled = function(p, a, b)
		local rng = Random.new()
		local cues = {}
		for _ = 1, (if type(b) == "number" then b else 1) do
			table.insert(cues, (Cases.roll(a, function(n: number): number
				return rng:NextInteger(1, n)
			end)))
		end
		return PlayerData.openCases(p, a, cues)
	end,
	sellCue = function(p, a, b)
		return PlayerData.sellCue(p, a, b)
	end,
	sellDuplicates = function(p, a)
		return PlayerData.sellDuplicates(p, a)
	end,
	equipCue = function(p, a)
		return PlayerData.equipCue(p, a)
	end,
	markSeen = function(p, a)
		return PlayerData.markSeen(p, a)
	end,
	claimIndexRow = function(p, a)
		return PlayerData.claimIndexRow(p, a)
	end,
	clearInventory = function(p)
		return PlayerData.clearInventory(p)
	end,
	claimDaily = function(p)
		return PlayerData.claimDaily(p)
	end,
	setStreakDay = function(p, a, b)
		return PlayerData.setStreakDay(p, a, b)
	end,
	newDay = function(p)
		return PlayerData.newDay(p)
	end,
	addPlaySeconds = function(p, a)
		return PlayerData.addPlaySeconds(p, a)
	end,
	setPlayMinutes = function(p, a)
		return PlayerData.setPlayMinutes(p, a)
	end,
	claimPlaytime = function(p, a)
		return PlayerData.claimPlaytime(p, a)
	end,
	redeemCode = function(p, a)
		return PlayerData.redeemCode(p, a)
	end,
	applyPurchase = function(p, a, b, c)
		return PlayerData.applyPurchase(p, a, b, c)
	end,
	buyLimited = function(p, a, b, c)
		return PlayerData.buyLimited(p, a, b, c)
	end,
	giveVipCue = function(p)
		return PlayerData.giveVipCue(p)
	end,
	saveNow = function(p, a, b)
		return PlayerData.saveNow(p, a, b)
	end,
	reset = function(p)
		return PlayerData.reset(p)
	end,
}

-- Studio only: ServerStorage.PlayerDataQA, a BindableFunction that runs inside this module
-- (the MCP's execute_luau gets its own copies of modules, so tests go through this). Clients
-- cannot reach ServerStorage, and nothing is made in a live server.
-- Invoke(op, userId, ...):
--   "state"                  -> { dataStoreState, storeName, loaded, isMock }
--   any key of QA_CALLS      -> that PlayerData function with the player and up to four more
--                               arguments, e.g. ("openCases", id, "Standard", { "..." }) ->
--                               ok, results; ("openRolled", id, "Standard", 10) rolls first;
--                               ("saveNow", id, 15, purchaseId?) yields
--   "endSession", kick?      -> ends the session as if the player left (no kick unless `kick`
--                               is true: then it runs the takeover path and kicks with
--                               SessionEnded)
--   "load"                   -> opens the save again for a player still here whose session
--                               ended; true once loaded
--   "profileInfo"            -> { key, sessionLoadCount, active }, or nil
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
	hook.OnInvoke = function(op: string, userId: number?, a: any, b: any, c: any, d: any): ...any
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
		local call = QA_CALLS[op]
		if call then
			return call(player, a, b, c, d)
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
	-- A save still held by a server the player just left is looked at again this soon
	-- (ProfileStore's public constant; its default is 5 s), so a teleport never waits long.
	ProfileStore.SetConstant("FIRST_LOAD_REPEAT", S.ConflictRetrySeconds)
	store = ProfileStore.New(STORE_NAME, SaveSchema.template())
	ProfileStore.OnError:Connect(function(_message: string, storeName: string, key: string)
		-- ProfileStore retries on its own and already printed the error; never log save data.
		warn(("[8ball] PlayerData: DataStore error on store %s, key %s"):format(storeName, key))
	end)
	task.spawn(logDataStoreState)
	task.spawn(refreshLoop)
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
