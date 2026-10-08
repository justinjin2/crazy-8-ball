--!strict
-- The layout of one player's save, its version history and its repair. Pure: no Instances,
-- no Roblox APIs, no clocks, no randomness, and nothing that depends on the order a hash
-- table happens to iterate in (so the same bad save always gets the same fixes, in the same
-- order). src/server/PlayerData.luau is the only user of this layout on the server; it hands
-- `template()` to ProfileStore, then runs `migrate`, Reconcile and `validate` on a copy of
-- every loaded save.
--
-- ProfileStore's rules for what a save may hold (top of src/server/Vendor/ProfileStore.luau):
-- only string-keyed maps and gapless arrays, never a table mixing the two, no functions,
-- Instances or userdata. `validate` enforces the parts of that a bug could break, and keeps
-- every map and array under a cap from Config.Save, so no bug can grow a save without limit.
--
-- Changing the layout: bump `Version`, add `Migrations[old]` that turns an old save into the
-- new one, and update `template()` and `validate`. Never edit an old migration once shipped.
-- A new field alone needs no bump: ProfileStore's Reconcile copies it from the template.
--
-- Version 6 (2026-10-03, the economy plan; docs/ECONOMY.md): every save older than
-- `WipeBelow` starts over as a new player's (the designer: a full wipe, only friends had
-- played), keeping only Shop.Purchases so a receipt in flight is never granted twice. The
-- migrations that led to version 5 were removed with it.
-- Version 7 (2026-10-04, cases retired for lucky blocks): Inventory.Cases, PaidCases and
-- Timers, Shop.QuickApplied and the TutorialCase and LeaveGift flags are dropped (the
-- designer: nothing converted), and the first-win flag is renamed FirstWinBlock.
-- Version 8 (2026-10-06): the cue id GrandOpeningCue is now FireworkCue wherever a save holds
-- a cue id (Config.Items.RenamedCues).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local UltCatalog = require(script.Parent.Parent.Ults.Catalog)
local UltSlots = require(script.Parent.Parent.Ults.Slots)
local LuckyBlocks = require(script.Parent.LuckyBlocks)

local SaveCfg = Config.Save
local RanksCfg = Config.Ranks

local SaveSchema = {}

SaveSchema.Version = 8

--- Saves older than this start over (a full wipe, version 6).
SaveSchema.WipeBelow = 6

-- The most playtime one UTC day can hold (Daily.PlaySeconds).
local SECONDS_PER_DAY = 86400

-- Every counter in Stats, in the order fixes are reported.
local STAT_KEYS = {
	"Matches",
	"Wins",
	"Losses",
	"Draws",
	"PcWins",
	"PcLosses",
	"BallsPocketed",
	"NiceShots",
	"MoneyEarned",
	"WinStreak",
	"BestWinStreak",
}

-- The top-level sub-tables, all string-keyed maps, in the order fixes are reported.
local MAP_KEYS = {
	"Stats",
	"Progress",
	"Inventory",
	"Index",
	"Titles",
	"Equipped",
	"Daily",
	"Login",
	"Shop",
	"Codes",
	"Settings",
	"Flags",
	"Ults",
	"Drops",
	"Social",
	"Trades",
	"LuckyBlocks",
}

-- Shop's true/false fields, in the order fixes are reported.
local SHOP_FLAGS = { "VipOffer", "VipCueGiven", "StarterBought", "FirstPackBought" }

--- A fresh Daily table for UTC day `day`: every per-day count at zero. Everything in Daily
--- belongs to one UTC day and starts over on the next (`rolloverDaily`).
function SaveSchema.freshDaily(day: number): any
	return {
		Day = day, -- the UTC day number these belong to
		SoloMoney = 0, -- money earned in solo today (Config.Economy.SoloDailyCap)
		PcMoney = 0, -- money earned against PC today (Config.Economy.PcDailyCap)
		ShortMoney = 0, -- money from matches that ended before the one-minute mark today
		Wins = 0, -- real wins today
		PcDrops = 0, -- PC wins today that dropped a lucky block (Config.Economy.PcDropsPerDay)
		Disguised = 0, -- disguised-bot wins today (Config.Economy.DisguisedDailyWins)
		Opponents = {}, -- [userId as a string] = { Matches, Drops } (anti-farm, ECONOMY 3.6)
		PlaySeconds = 0, -- time played today (the playtime gifts)
		PlaytimeClaimed = {}, -- [gift index as a string] = true, the gifts claimed today
	}
end

-- Daily's fields, in the order fixes are reported and missing ones are filled.
local DAILY_KEYS = {
	"Day",
	"SoloMoney",
	"PcMoney",
	"ShortMoney",
	"Wins",
	"PcDrops",
	"Disguised",
	"Opponents",
	"PlaySeconds",
	"PlaytimeClaimed",
}

--- A fresh copy of a new player's save. Every call builds new tables, so changing one copy
--- never changes the next. Every map starts empty: ProfileStore's Reconcile copies template
--- keys into saves that lack them, so an entry here would appear in every player's map.
function SaveSchema.template(): any
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	return {
		Version = SaveSchema.Version,
		Money = 0, -- integer 0..Config.Save.MoneyCap
		RankXp = 0, -- integer 0..Config.Save.RankXpCap; the rank is derived from it
		PeakDivision = 0, -- 0 never ranked, 1 Bronze I ... divisionCount() the top tier
		RatedMatches = 0, -- 0 means Unranked
		Stats = stats, -- every counter an integer 0..Config.Save.StatCap
		Progress = {
			RealMatches = 0, -- real matches played (past one minute, not solo): the block-drop alt rule
			Wins = 0, -- real wins ever, people or PC
		},
		Inventory = {
			Cues = {}, -- [cueId] = count >= 1: block and Exclusive cues; never Catalog.Default
			-- [cueId] = how many of Cues[cueId] came from something paid (a lucky block bought
			-- with money or Robux): at most the count. Paid copies cannot be traded where Roblox's
			-- IsPaidItemTradingAllowed is false (ECONOMY 13).
			PaidCues = {},
			Unique = {}, -- [cueId] = copy number: numbered Limited cues (#412)
			PaidUnique = {}, -- [cueId] = true: that Unique cue was bought (money or Robux)
			-- [cueId] = true: the designer's own unnumbered copy of a Unique cue (/givecue):
			-- never counted among the copies in existence, never traded.
			OwnerUnique = {},
			New = {}, -- [cueId] = true: the NEW tag until the player has seen it
		},
		Index = {
			Seen = {}, -- [cueId] = true: ever owned (selling it later keeps it here)
			Rows = {}, -- [rarity] = true: that Index row's reward is claimed
		},
		Titles = {}, -- [titleId] = true
		Equipped = { Cue = Catalog.Default },
		Daily = SaveSchema.freshDaily(0),
		Login = {
			LastDay = 0, -- the UTC day of the last claim; 0 never claimed
			StreakDay = 0, -- the loop day last claimed, 1..#Config.Daily.Streak; 0 none
			Total = 0, -- every day ever claimed (the 28-day track, Config.Daily.Track)
			FreezeWeek = 0, -- the UTC week whose streak freeze was used (Daily.weekOf); 0 none
		},
		Shop = {
			-- Unix seconds of the first join; 0 until PlayerData sets it on load (the migration
			-- and the template are pure and have no clock). The welcome offer and the comeback
			-- window are timed from it (Config.Shop).
			FirstJoin = 0,
			VipOffer = false, -- bought VIP through the welcome offer (VIP = the pass or this)
			VipCueGiven = false,
			StarterBought = false,
			FirstPackBought = false, -- the first money pack's double money is used
			Purchases = {}, -- gapless array, oldest first: the last Config.Shop.RecentPurchases
			Limited = {}, -- [cueId] = copy number: Limited cues bought (one per player)
			BoostEnds = 0, -- unix seconds the Starter Pack's 2x money runs until; 0 none
			-- The restock shop's purchases in one 10-minute slot (Config.Restock): Slot is the
			-- slot number they belong to, Bought = { [item key] = count } (a new slot starts over).
			Restock = { Slot = 0, Bought = {} },
		},
		Codes = {}, -- [CODE] = true: promo codes redeemed
		Settings = {},
		Flags = {},
		-- The ults (v3; Ults/Slots.fresh): the default ult in slot 1, the starter spins. Slots
		-- and Locked are gapless arrays of Config.Ults.Slots ("" = an empty slot).
		Ults = UltSlots.fresh(),
		-- The Mystery block's pity (Config.BlockOdds.Drop; ECONOMY 7): opens since the last
		-- Rare-or-better tier and since the last Epic-or-better tier, and every roll ever.
		Drops = { SinceRare = 0, SinceEpic = 0, Total = 0 },
		Social = {
			Group = false, -- the group's one-time reward was claimed (Config.Social)
			InvitedBy = 0, -- the UserId whose invite brought this player (0 none)
			InviteDone = false, -- this player's own invite reward was settled (given or not due)
			InviteMonth = 0, -- the month InvitesThisMonth counts (year * 12 + month)
			Invites = 0, -- invite rewards this player got as the inviter that month
		},
		Trades = {
			-- The last Config.Save.MaxTradeHistory trades, oldest first: { Id, With (UserId),
			-- At (unix), Gave = { item }, Got = { item } } (an item: a cue id or "Block:<kind>").
			History = {},
			Applied = {}, -- the last MaxAppliedTrades trade ids this save holds the result of
		},
		-- Lucky blocks (Progression/LuckyBlocks, 2026-10-03): Next is the last block id given;
		-- List, a gapless array in hotbar order of { Id, Kind, ReadyAt (unix), Paid? }.
		LuckyBlocks = LuckyBlocks.fresh(),
	}
end

--- How many divisions the ladder has, bottom to top: DivisionsPerTier for every tier but the
--- last, which has one.
function SaveSchema.divisionCount(): number
	return (#RanksCfg.Tiers - 1) * RanksCfg.DivisionsPerTier + 1
end

--- If `daily` (a save's Daily table) belongs to another UTC day than `day`, start it over for
--- `day`: every field back to its fresh value, in place. Returns whether it did. Call it
--- before reading or changing anything in Daily.
function SaveSchema.rolloverDaily(daily: any, day: number): boolean
	if daily.Day == day then
		return false
	end
	-- Everything in Daily is per-day, so anything else found there went stale with the day.
	table.clear(daily)
	local fresh = SaveSchema.freshDaily(day)
	for _, key in DAILY_KEYS do
		daily[key] = fresh[key]
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Number and id helpers (also used by other modules to check inputs)
---------------------------------------------------------------------------------------------

--- True for a finite whole number (not NaN, not +/-infinity, no fraction).
function SaveSchema.isInteger(x: any): boolean
	return type(x) == "number"
		and x == x
		and x ~= math.huge
		and x ~= -math.huge
		and x == math.floor(x)
end

--- `x` made into a whole number in min..max: a non-number, NaN or infinity becomes `default`
--- (never the cap: a broken number must not turn into a fortune), a fraction is floored, and
--- anything outside the range is clamped to it. Returns the value and whether it changed.
function SaveSchema.cleanInteger(
	x: any,
	min: number,
	max: number,
	default: number
): (number, boolean)
	local value: number
	if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then
		value = default
	else
		value = math.clamp(math.floor(x), min, max)
	end
	if value == 0 then
		value = 0 -- no -0 in a save
	end
	return value, not (type(x) == "number" and x == value)
end

--- True for something a save may use as a key or an id: a string of 1 to
--- Config.Save.MaxIdLength characters.
function SaveSchema.isId(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= SaveCfg.MaxIdLength
end

-- A short, readable form of a bad value for a fix note.
local function describe(x: any): string
	local kind = type(x)
	if kind == "number" then
		if x ~= x then
			return "NaN"
		end
		return tostring(x)
	elseif kind == "string" then
		if #x > 20 then
			return ("%q..."):format(x:sub(1, 20))
		end
		return ("%q"):format(x)
	elseif kind == "boolean" then
		return tostring(x)
	end
	return kind
end

---------------------------------------------------------------------------------------------
-- Migrations
---------------------------------------------------------------------------------------------

-- `Migrations[n]` turns a version-n save into a version n+1 save (it may change the table in
-- place and return it), for n >= WipeBelow. `migrate` stamps the new Version after each step.
-- A migration sees the save exactly as it was stored: PlayerData migrates a copy first, then
-- runs ProfileStore's Reconcile (which fills keys the template has and the save lacks), then
-- `validate`. If a step errors, the save keeps its old Version and PlayerData releases the
-- stored save untouched (and the player cannot play), so a step must read every old field
-- defensively.
SaveSchema.Migrations = {} :: { [number]: (data: any) -> any }

-- 6 -> 7 (2026-10-04): cases are gone. Their inventory fields, the Quick Cases flag and the
-- tutorial's and first-leave gift's case flags are dropped; the first-win flag keeps its
-- meaning under its new name, so no old player gets a second first-win block.
SaveSchema.Migrations[6] = function(data: any): any
	local inventory = data.Inventory
	if type(inventory) == "table" then
		inventory.Cases = nil
		inventory.PaidCases = nil
		inventory.Timers = nil
	end
	local shop = data.Shop
	if type(shop) == "table" then
		shop.QuickApplied = nil
	end
	local flags = data.Flags
	if type(flags) == "table" then
		if flags.FirstWinCase == true then
			flags.FirstWinBlock = true
		end
		flags.FirstWinCase = nil
		flags.TutorialCase = nil
		flags.LeaveGift = nil
	end
	return data
end

-- 7 -> 8 (2026-10-06): the Grand Opening Cue became the Firework Cue, its id too. Every map
-- keyed by cue id, the equipped cue and both sides of each trade in the history take the new
-- id. Fixed here (not read from Config) so this step never changes once shipped.
local RENAMED_8 = { GrandOpeningCue = "FireworkCue" }

local function renameKeys(map: any)
	if type(map) ~= "table" then
		return
	end
	for old, new in RENAMED_8 do
		if map[old] ~= nil then
			if map[new] == nil then
				map[new] = map[old]
			end
			map[old] = nil
		end
	end
end

local function renameItems(list: any)
	if type(list) ~= "table" then
		return
	end
	for i, item in list do
		local new = type(item) == "string" and RENAMED_8[item]
		if new then
			list[i] = new
		end
	end
end

SaveSchema.Migrations[7] = function(data: any): any
	local inventory = data.Inventory
	if type(inventory) == "table" then
		for _, key in { "Cues", "PaidCues", "Unique", "PaidUnique", "OwnerUnique", "New" } do
			renameKeys(inventory[key])
		end
	end
	if type(data.Index) == "table" then
		renameKeys(data.Index.Seen)
	end
	if type(data.Shop) == "table" then
		renameKeys(data.Shop.Limited)
	end
	local equipped = data.Equipped
	if type(equipped) == "table" and type(equipped.Cue) == "string" then
		equipped.Cue = RENAMED_8[equipped.Cue] or equipped.Cue
	end
	local trades = data.Trades
	if type(trades) == "table" and type(trades.History) == "table" then
		for _, entry in trades.History do
			if type(entry) == "table" then
				renameItems(entry.Gave)
				renameItems(entry.Got)
			end
		end
	end
	return data
end

-- The wipe (version 6): a new player's save, keeping only the receipt ids of `old` (strings,
-- the newest Config.Shop.RecentPurchases; validate checks them again).
local function wiped(old: { [any]: any }): any
	local fresh = SaveSchema.template()
	local shop = old.Shop
	local list = if type(shop) == "table" then shop.Purchases else nil
	if type(list) == "table" then
		local kept: { string } = {}
		for i = 1, #list do
			local id = list[i]
			if type(id) == "string" and #id >= 1 and #id <= SaveCfg.MaxPurchaseIdLength then
				table.insert(kept, id)
			end
		end
		local extra = math.max(#kept - Config.Shop.RecentPurchases, 0)
		for i = extra + 1, #kept do
			table.insert(fresh.Shop.Purchases, kept[i])
		end
	end
	return fresh
end

-- The version a save claims: missing, broken or negative means 0 (older than versioning).
local function versionOf(data: { [any]: any }): number
	local v = data.Version
	if not SaveSchema.isInteger(v) or v < 0 then
		return 0
	end
	return v
end

--- Bring a save up to `SaveSchema.Version`. Returns the save (a fresh template if it was not
--- a table) and notes on what happened. A save from a newer version than this code knows is
--- returned untouched (never downgraded or wiped) with a note starting "future version": the
--- caller must not play on it.
function SaveSchema.migrate(data: any): (any, { string })
	local notes: { string } = {}
	if type(data) ~= "table" then
		table.insert(notes, ("save was %s, not a table: started a new one"):format(describe(data)))
		return SaveSchema.template(), notes
	end
	local version = versionOf(data)
	if version > SaveSchema.Version then
		table.insert(
			notes,
			("future version %d (this code knows up to %d): left untouched"):format(
				version,
				SaveSchema.Version
			)
		)
		return data, notes
	end
	if version < SaveSchema.WipeBelow then
		table.insert(
			notes,
			("version %d is older than %d: started over (the version 6 wipe)"):format(
				version,
				SaveSchema.WipeBelow
			)
		)
		return wiped(data), notes
	end
	while version < SaveSchema.Version do
		local step = SaveSchema.Migrations[version]
		if step == nil then
			table.insert(notes, ("no migration from version %d: stopped"):format(version))
			return data, notes
		end
		local ok, result = pcall(step, data)
		if not ok then
			table.insert(
				notes,
				("migration %d -> %d failed: %s"):format(version, version + 1, tostring(result))
			)
			return data, notes
		end
		if type(result) == "table" then
			data = result
		end
		data.Version = version + 1
		table.insert(notes, ("migrated %d -> %d"):format(version, version + 1))
		version += 1
	end
	return data, notes
end

---------------------------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------------------------

-- "1 entry" or "3 entries", for fix notes.
local function entries(n: number): string
	return if n == 1 then "1 entry" else ("%d entries"):format(n)
end

-- Remove every key that is not a string (ProfileStore maps must be string-keyed). Keys are
-- gathered first, and the fix reports only a count, so hash order never shows.
local function dropNonStringKeys(t: { [any]: any }, where: string, fixes: { string })
	local bad = {}
	for key in t do
		if type(key) ~= "string" then
			table.insert(bad, key)
		end
	end
	for _, key in bad do
		t[key] = nil
	end
	if #bad > 0 then
		table.insert(fixes, ("%s: dropped %d key(s) that were not strings"):format(where, #bad))
	end
end

-- Make `parent[key]` a table, rebuilding it from `fresh` when it is anything else. `path`
-- names it in the fix note.
local function ensureTable(
	parent: { [any]: any },
	key: string,
	path: string,
	fresh: any,
	fixes: { string }
): any
	local value = parent[key]
	if type(value) ~= "table" then
		table.insert(fixes, ("%s was %s: reset"):format(path, describe(value)))
		parent[key] = fresh
		return fresh
	end
	return value
end

-- Clean `t[key]` to an integer in 0..max, reporting a change under `path`.
local function fixInteger(
	t: { [any]: any },
	key: string,
	path: string,
	max: number,
	fixes: { string }
)
	local old = t[key]
	local value, changed = SaveSchema.cleanInteger(old, 0, max, 0)
	if changed then
		table.insert(fixes, ("%s was %s: set to %d"):format(path, describe(old), value))
	end
	t[key] = value
end

-- Make `t[key]` true or false: anything else is false (a broken flag never grants anything).
local function fixBoolean(t: { [any]: any }, key: string, path: string, fixes: { string })
	local old = t[key]
	if type(old) ~= "boolean" then
		table.insert(fixes, ("%s was %s: set to false"):format(path, describe(old)))
		t[key] = false
	end
end

-- Make `t` a gapless array: keep its values under positive whole-number keys, in key order,
-- packed from 1, and drop everything else.
local function fixArray(t: { [any]: any }, path: string, fixes: { string })
	local indices: { number } = {}
	local dropped = 0
	for key in t do
		if SaveSchema.isInteger(key) and key >= 1 then
			table.insert(indices, key)
		else
			dropped += 1
		end
	end
	table.sort(indices)
	local gapless = #indices == 0 or indices[#indices] == #indices
	if dropped == 0 and gapless then
		return
	end
	local values = {}
	for _, index in indices do
		table.insert(values, t[index])
	end
	table.clear(t)
	for i, value in values do
		t[i] = value
	end
	if dropped > 0 then
		table.insert(
			fixes,
			("%s: dropped %d key(s) that were not array indices"):format(path, dropped)
		)
	end
	if not gapless then
		table.insert(fixes, ("%s: closed the gaps in the array"):format(path))
	end
end

-- What a map's value cleaner returns: the value to keep (nil drops the entry) and whether it
-- differs from the value it was given.
type Cleaner = (value: any) -> (any, boolean)

-- Repair a string-keyed map in place: drop keys that are not strings, keys that are not ids
-- (Config.Save.MaxIdLength) and the `banned` key; run every value through `clean`; then keep
-- at most `maxEntries` entries, those with the smallest keys. Keys are sorted before anything
-- is dropped and the notes report counts, so the same map always gets the same fixes.
local function fixMap(
	t: { [any]: any },
	path: string,
	maxEntries: number,
	clean: Cleaner,
	fixes: { string },
	banned: string?
)
	dropNonStringKeys(t, path, fixes)
	local keys: { string } = {}
	for key in t do
		table.insert(keys, key)
	end
	table.sort(keys)
	local kept: { string } = {}
	local badIds, dropped, repaired = 0, 0, 0
	local droppedBanned = false
	for _, key in keys do
		if key == banned then
			t[key] = nil
			droppedBanned = true
		elseif not SaveSchema.isId(key) then
			t[key] = nil
			badIds += 1
		else
			local value, changed = clean(t[key])
			if value == nil then
				t[key] = nil
				dropped += 1
			else
				if changed then
					t[key] = value
					repaired += 1
				end
				table.insert(kept, key)
			end
		end
	end
	if droppedBanned then
		table.insert(fixes, ("%s: dropped %q (never kept here)"):format(path, banned :: string))
	end
	if badIds > 0 then
		table.insert(
			fixes,
			("%s: dropped %s whose key was empty or too long"):format(path, entries(badIds))
		)
	end
	if dropped > 0 then
		table.insert(fixes, ("%s: dropped %s with a bad value"):format(path, entries(dropped)))
	end
	if repaired > 0 then
		table.insert(fixes, ("%s: repaired %s"):format(path, entries(repaired)))
	end
	if #kept > maxEntries then
		for i = maxEntries + 1, #kept do
			t[kept[i]] = nil
		end
		table.insert(
			fixes,
			("%s: kept the first %d of %s (the cap)"):format(path, maxEntries, entries(#kept))
		)
	end
end

-- A cleaner for counts and copy numbers: a whole number in 1..cap. A fraction is floored and
-- a number over the cap is clamped (an item is never lost to a rounding bug); a non-number,
-- NaN, infinity or anything below 1 drops the entry (a broken count never becomes items).
local function wholeFrom1(cap: number): Cleaner
	return function(value: any): (any, boolean)
		if
			type(value) ~= "number"
			or value ~= value
			or value == math.huge
			or value == -math.huge
		then
			return nil, true
		end
		local whole = math.floor(value)
		if whole < 1 then
			return nil, true
		end
		whole = math.min(whole, cap)
		return whole, whole ~= value
	end
end

-- A cleaner for sets: the value must be `true`.
local function onlyTrue(value: any): (any, boolean)
	if value == true then
		return true, false
	end
	return nil, true
end

-- A cleaner for Daily.Opponents entries: exactly { Matches, Drops }, whole numbers in
-- 0..StatCap. Anything else in an entry is dropped, so an entry has a fixed size.
local function opponentEntry(value: any): (any, boolean)
	if type(value) ~= "table" then
		return nil, true
	end
	local matches, badMatches = SaveSchema.cleanInteger(value.Matches, 0, SaveCfg.StatCap, 0)
	local drops, badDrops = SaveSchema.cleanInteger(value.Drops, 0, SaveCfg.StatCap, 0)
	local extra = false
	-- Only whether any other key exists matters, so the walk's order does not.
	for key in value do
		if key ~= "Matches" and key ~= "Drops" then
			extra = true
			break
		end
	end
	if badMatches or badDrops or extra then
		return { Matches = matches, Drops = drops }, true
	end
	return value, false
end

-- `parent[key]` made a table (reported under `path`) and repaired as a map.
local function fixMapAt(
	parent: { [any]: any },
	key: string,
	path: string,
	maxEntries: number,
	clean: Cleaner,
	fixes: { string },
	banned: string?
)
	local t = ensureTable(parent, key, path, {}, fixes)
	fixMap(t, path, maxEntries, clean, fixes, banned)
end

-- Shop.Purchases: a gapless array of receipt ids (strings), oldest first, at most
-- Config.Shop.RecentPurchases of them (the newest are kept: they guard the receipts Roblox
-- may still retry).
local function fixPurchases(shop: { [any]: any }, fixes: { string })
	local path = "Shop.Purchases"
	local list = ensureTable(shop, "Purchases", path, {}, fixes)
	fixArray(list, path, fixes)
	local good: { string } = {}
	local dropped = 0
	for i = 1, #list do
		local id = list[i]
		if type(id) == "string" and #id >= 1 and #id <= SaveCfg.MaxPurchaseIdLength then
			table.insert(good, id)
		else
			dropped += 1
		end
	end
	local cap = Config.Shop.RecentPurchases
	local extra = math.max(#good - cap, 0)
	if dropped == 0 and extra == 0 then
		return
	end
	table.clear(list)
	for i = extra + 1, #good do
		table.insert(list, good[i])
	end
	if dropped > 0 then
		table.insert(fixes, ("%s: dropped %d id(s) that were not strings"):format(path, dropped))
	end
	if extra > 0 then
		table.insert(fixes, ("%s: kept the last %d of %d"):format(path, cap, #good))
	end
end

-- Drop values a DataStore cannot hold (NaN, infinity) from a string-keyed map of settings.
local function dropNonFinite(t: { [any]: any }, where: string, fixes: { string })
	local bad = {}
	for key, value in t do
		if
			type(value) == "number"
			and (value ~= value or value == math.huge or value == -math.huge)
		then
			table.insert(bad, key)
		end
	end
	for _, key in bad do
		t[key] = nil
	end
	if #bad > 0 then
		table.insert(fixes, ("%s: dropped %d value(s) that were not finite"):format(where, #bad))
	end
end

-- Make `parent[key]` an array of exactly `n` values, each run through `clean` (which returns
-- the value to keep and whether it changed): missing entries are filled, entries past `n` and
-- keys that are not 1..n dropped. A non-table is rebuilt from `fresh`.
local function fixFixedArray(
	parent: { [any]: any },
	key: string,
	path: string,
	n: number,
	clean: Cleaner,
	fresh: { any },
	fixes: { string }
)
	local t = ensureTable(parent, key, path, fresh, fixes)
	if t == fresh then
		return
	end
	local extra = 0
	for index in t do
		if not (SaveSchema.isInteger(index) and index >= 1 and index <= n) then
			extra += 1
		end
	end
	local values = {}
	local repaired = 0
	for i = 1, n do
		local value, changed = clean(t[i])
		values[i] = value
		if changed then
			repaired += 1
		end
	end
	if extra == 0 and repaired == 0 then
		return
	end
	table.clear(t)
	for i = 1, n do
		t[i] = values[i]
	end
	if extra > 0 then
		table.insert(fixes, ("%s: dropped %d key(s) outside 1..%d"):format(path, extra, n))
	end
	if repaired > 0 then
		table.insert(fixes, ("%s: repaired %s"):format(path, entries(repaired)))
	end
end

-- A cleaner for an ult slot: a catalog ult id or "" (empty); a retired ult becomes the one
-- that replaces it (Config.Ults.Retired); anything else becomes "".
local function ultSlot(value: any): (any, boolean)
	if value == "" or UltCatalog.exists(value) then
		return value, false
	end
	local replaced = UltCatalog.retired(value)
	if replaced ~= nil then
		return replaced, true
	end
	return "", true
end

-- A cleaner for a slot lock: true or false; anything else becomes false.
local function lockFlag(value: any): (any, boolean)
	if type(value) == "boolean" then
		return value, false
	end
	return false, true
end

-- The ults (v3): Slots and Locked exactly Config.Ults.Slots long, Selected a slot, every count
-- a whole number in its range, QueueUlts a boolean (true when broken: the default). Called
-- after the top-level tables are made tables.
local function fixUlts(ults: { [any]: any }, fixes: { string })
	local fresh = UltSlots.fresh()
	local n = Config.Ults.Slots
	fixFixedArray(ults, "Slots", "Ults.Slots", n, ultSlot, fresh.Slots, fixes)
	fixFixedArray(ults, "Locked", "Ults.Locked", n, lockFlag, fresh.Locked, fixes)
	local selected = ults.Selected
	if not (SaveSchema.isInteger(selected) and selected >= 1 and selected <= n) then
		table.insert(fixes, ("Ults.Selected was %s: set to 1"):format(describe(selected)))
		ults.Selected = 1
	end
	local maxSpins = Config.Ults.Earn.MaxSpins
	fixInteger(ults, "Spins", "Ults.Spins", maxSpins, fixes)
	fixInteger(ults, "LuckySpins", "Ults.LuckySpins", maxSpins, fixes)
	fixInteger(ults, "Pity", "Ults.Pity", Config.Ults.Roll.PityAt - 1, fixes)
	-- A UTC day number, bounded like Daily.Day.
	fixInteger(ults, "FreeSpinDay", "Ults.FreeSpinDay", SaveCfg.StatCap, fixes)
	fixInteger(ults, "SpinsDone", "Ults.SpinsDone", SaveCfg.StatCap, fixes)
	if type(ults.QueueUlts) ~= "boolean" then
		table.insert(fixes, ("Ults.QueueUlts was %s: set to true"):format(describe(ults.QueueUlts)))
		ults.QueueUlts = true
	end
end

-- The largest UserId a save keeps (Social.InvitedBy, a trade's partner). Roblox's are far below.
local USER_ID_CAP = 1e15

-- Inventory.PaidCues and PaidUnique after the inventory is clean: a paid count never above the
-- copies held, and no paid mark on a cue not held (selling or trading may have taken them).
local function fixPaid(inventory: { [any]: any }, fixes: { string })
	local cues, paid = inventory.Cues, inventory.PaidCues
	local ids: { string } = {}
	for id in paid do
		table.insert(ids, id)
	end
	table.sort(ids)
	local trimmed = 0
	for _, id in ids do
		local have = cues[id]
		local held = if type(have) == "number" then have else 0
		if held <= 0 then
			paid[id] = nil
			trimmed += 1
		elseif paid[id] > held then
			paid[id] = held
			trimmed += 1
		end
	end
	if trimmed > 0 then
		table.insert(
			fixes,
			("Inventory.PaidCues: trimmed %s to the copies held"):format(entries(trimmed))
		)
	end
	local unique, paidUnique = inventory.Unique, inventory.PaidUnique
	local marks: { string } = {}
	for id in paidUnique do
		table.insert(marks, id)
	end
	table.sort(marks)
	local dropped = 0
	for _, id in marks do
		if unique[id] == nil then
			paidUnique[id] = nil
			dropped += 1
		end
	end
	if dropped > 0 then
		table.insert(fixes, ("Inventory.PaidUnique: dropped %s not held"):format(entries(dropped)))
	end
end

-- One side of a trade in the history: a gapless array of item strings (a cue id or
-- "Block:<kind>"), at most Config.Save.MaxTradeSideItems. nil when it is not one.
local function tradeSide(value: any): { string }?
	if type(value) ~= "table" then
		return nil
	end
	local n = 0
	for key in value do
		if not (SaveSchema.isInteger(key) and key >= 1) then
			return nil
		end
		n += 1
	end
	if n > SaveCfg.MaxTradeSideItems then
		return nil
	end
	local out: { string } = {}
	for i = 1, n do
		local item = value[i]
		if not SaveSchema.isId(item) then
			return nil
		end
		table.insert(out, item)
	end
	return out
end

-- Trades: History, the last MaxTradeHistory entries { Id, With, At, Gave, Got }, oldest
-- first; Applied, the last MaxAppliedTrades trade ids. A broken entry is dropped.
local function fixTrades(trades: { [any]: any }, fixes: { string })
	local path = "Trades.History"
	local history = ensureTable(trades, "History", path, {}, fixes)
	fixArray(history, path, fixes)
	local good = {}
	local dropped = 0
	for i = 1, #history do
		local h = history[i]
		local gave = if type(h) == "table" then tradeSide(h.Gave) else nil
		local got = if type(h) == "table" then tradeSide(h.Got) else nil
		if
			gave ~= nil
			and got ~= nil
			and SaveSchema.isId(h.Id)
			and SaveSchema.isInteger(h.With)
			and h.With >= 0
			and h.With <= USER_ID_CAP
			and SaveSchema.isInteger(h.At)
			and h.At >= 0
			and h.At <= SaveCfg.UnixTimeCap
		then
			table.insert(good, { Id = h.Id, With = h.With, At = h.At, Gave = gave, Got = got })
		else
			dropped += 1
		end
	end
	local cap = SaveCfg.MaxTradeHistory
	local extra = math.max(#good - cap, 0)
	table.clear(history)
	for i = extra + 1, #good do
		table.insert(history, good[i])
	end
	if dropped > 0 then
		table.insert(fixes, ("%s: dropped %s that were broken"):format(path, entries(dropped)))
	end
	if extra > 0 then
		table.insert(fixes, ("%s: kept the last %d of %d"):format(path, cap, #good))
	end

	local appliedPath = "Trades.Applied"
	local applied = ensureTable(trades, "Applied", appliedPath, {}, fixes)
	fixArray(applied, appliedPath, fixes)
	local ids: { string } = {}
	local bad = 0
	for i = 1, #applied do
		if SaveSchema.isId(applied[i]) then
			table.insert(ids, applied[i])
		else
			bad += 1
		end
	end
	local over = math.max(#ids - SaveCfg.MaxAppliedTrades, 0)
	if bad > 0 or over > 0 then
		table.clear(applied)
		for i = over + 1, #ids do
			table.insert(applied, ids[i])
		end
		if bad > 0 then
			table.insert(fixes, ("%s: dropped %d id(s) that were not ids"):format(appliedPath, bad))
		end
		if over > 0 then
			table.insert(
				fixes,
				("%s: kept the last %d of %d"):format(appliedPath, SaveCfg.MaxAppliedTrades, #ids)
			)
		end
	end
end

--- Repair a save in place so every field holds a safe value. Returns the same table (or a
--- fresh template if `data` was not a table) and the fixes it made, empty when the save was
--- clean. Unknown string keys at the top level and in the fixed-field tables are left alone
--- (they may be a newer version's fields); maps of ids are cleaned entry by entry. Never
--- errors, whatever it is given.
-- Lucky blocks: Next a whole number; List a gapless array of at most Config.LuckyBlocks
-- .MaxBlocks blocks, each { Id (1..Next, unique), Kind (a known kind), ReadyAt (unix) }. A block
-- that cannot be read is dropped (it never becomes a block of another kind); a ReadyAt out of
-- range is clamped, so a block is never lost to a clock bug.
local function fixLuckyBlocks(blocks: { [any]: any }, fixes: { string })
	fixInteger(blocks, "Next", "LuckyBlocks.Next", SaveCfg.StatCap, fixes)
	fixInteger(blocks, "SkipCredits", "LuckyBlocks.SkipCredits", SaveCfg.StatCap, fixes)
	fixInteger(blocks, "SkipTarget", "LuckyBlocks.SkipTarget", SaveCfg.StatCap, fixes)
	local list = ensureTable(blocks, "List", "LuckyBlocks.List", {}, fixes)
	fixArray(list, "LuckyBlocks.List", fixes)
	-- Opened: a count per known kind (the Guarantee's). Old kind ids are renamed.
	local opened = ensureTable(blocks, "Opened", "LuckyBlocks.Opened", {}, fixes)
	local cleanOpened = {}
	for kind, n in opened do
		local now = LuckyBlocks.current(kind)
		if LuckyBlocks.kind(now) ~= nil then
			cleanOpened[now] = (cleanOpened[now] or 0)
				+ SaveSchema.cleanInteger(n, 0, SaveCfg.StatCap, 0)
		end
	end
	table.clear(opened)
	for kind, n in cleanOpened do
		opened[kind] = n
	end
	local kept, seen, dropped = {}, {}, 0
	for _, block in list do
		local id = if type(block) == "table" then block.Id else nil
		if
			type(block) ~= "table"
			or not SaveSchema.isInteger(id)
			or id < 1
			or seen[id]
			or LuckyBlocks.kind(block.Kind) == nil
		then
			dropped += 1
		else
			seen[id] = true
			local readyAt = SaveSchema.cleanInteger(block.ReadyAt, 0, SaveCfg.UnixTimeCap, 0)
			table.insert(kept, {
				Id = id,
				Kind = LuckyBlocks.current(block.Kind), -- an old id becomes its new kind
				ReadyAt = readyAt,
				Paid = block.Paid == true,
			})
			if blocks.Next < id then
				blocks.Next = id
			end
		end
	end
	if #kept > Config.LuckyBlocks.MaxBlocks then
		table.insert(
			fixes,
			("LuckyBlocks.List: kept the first %d of %s (the cap)"):format(
				Config.LuckyBlocks.MaxBlocks,
				entries(#kept)
			)
		)
		for i = #kept, Config.LuckyBlocks.MaxBlocks + 1, -1 do
			kept[i] = nil
		end
	end
	if dropped > 0 then
		table.insert(
			fixes,
			("LuckyBlocks.List: dropped %s with a bad value"):format(entries(dropped))
		)
	end
	table.clear(list)
	for i, block in kept do
		list[i] = block
	end
	-- Only the inventory, the opened counts and the durable skip fields stay.
	for key in table.clone(blocks) do
		if
			key ~= "Next"
			and key ~= "List"
			and key ~= "Opened"
			and key ~= "SkipCredits"
			and key ~= "SkipTarget"
		then
			blocks[key] = nil
		end
	end
end

function SaveSchema.validate(data: any): (any, { string })
	local fixes: { string } = {}
	if type(data) ~= "table" then
		table.insert(fixes, ("save was %s, not a table: started a new one"):format(describe(data)))
		return SaveSchema.template(), fixes
	end
	local fresh = SaveSchema.template()
	dropNonStringKeys(data, "save", fixes)

	-- Version: a whole number >= 0. A newer version than ours is kept (migrate reports it).
	if not SaveSchema.isInteger(data.Version) or data.Version < 0 then
		table.insert(
			fixes,
			("Version was %s: set to %d"):format(describe(data.Version), SaveSchema.Version)
		)
		data.Version = SaveSchema.Version
	end

	fixInteger(data, "Money", "Money", SaveCfg.MoneyCap, fixes)
	fixInteger(data, "RankXp", "RankXp", SaveCfg.RankXpCap, fixes)
	fixInteger(data, "PeakDivision", "PeakDivision", SaveSchema.divisionCount(), fixes)
	fixInteger(data, "RatedMatches", "RatedMatches", SaveCfg.StatCap, fixes)

	for _, key in MAP_KEYS do
		local t = ensureTable(data, key, key, fresh[key], fixes)
		dropNonStringKeys(t, key, fixes)
	end

	local stats = data.Stats
	for _, key in STAT_KEYS do
		fixInteger(stats, key, "Stats." .. key, SaveCfg.StatCap, fixes)
	end
	if stats.BestWinStreak < stats.WinStreak then
		table.insert(
			fixes,
			("Stats.BestWinStreak was %d, below WinStreak %d: raised"):format(
				stats.BestWinStreak,
				stats.WinStreak
			)
		)
		stats.BestWinStreak = stats.WinStreak
	end

	fixInteger(data.Progress, "RealMatches", "Progress.RealMatches", SaveCfg.StatCap, fixes)
	fixInteger(data.Progress, "Wins", "Progress.Wins", SaveCfg.StatCap, fixes)

	-- The inventory. Classic is always owned, so it is never counted or numbered.
	local inventory = data.Inventory
	local counts = wholeFrom1(SaveCfg.ItemCountCap)
	local copies = wholeFrom1(SaveCfg.CopyNumberCap)
	local cueCap = SaveCfg.MaxCueEntries
	fixMapAt(inventory, "Cues", "Inventory.Cues", cueCap, counts, fixes, Catalog.Default)
	fixMapAt(inventory, "Unique", "Inventory.Unique", cueCap, copies, fixes, Catalog.Default)
	fixMapAt(inventory, "New", "Inventory.New", cueCap, onlyTrue, fixes)
	fixMapAt(inventory, "PaidCues", "Inventory.PaidCues", cueCap, counts, fixes, Catalog.Default)
	fixMapAt(inventory, "PaidUnique", "Inventory.PaidUnique", cueCap, onlyTrue, fixes)
	fixMapAt(inventory, "OwnerUnique", "Inventory.OwnerUnique", cueCap, onlyTrue, fixes)
	fixPaid(inventory, fixes)

	fixMapAt(data.Index, "Seen", "Index.Seen", cueCap, onlyTrue, fixes)
	fixMapAt(data.Index, "Rows", "Index.Rows", SaveCfg.MaxSmallEntries, onlyTrue, fixes)
	fixMap(data.Titles, "Titles", SaveCfg.MaxTitleEntries, onlyTrue, fixes)

	-- The equipped cue: a catalog cue the player owns, or Classic (always owned). Checked after
	-- the inventory, so a count repaired away above cannot stay equipped.
	local cue = data.Equipped.Cue
	if cue ~= Catalog.Default then
		local problem: string? = nil
		if not Catalog.exists(cue) then
			problem = "not a catalog cue"
		elseif
			inventory.Cues[cue] == nil
			and inventory.Unique[cue] == nil
			and inventory.OwnerUnique[cue] == nil
		then
			problem = "not owned"
		end
		if problem ~= nil then
			table.insert(
				fixes,
				("Equipped.Cue was %s (%s): set to %q"):format(
					describe(cue),
					problem,
					Catalog.Default
				)
			)
			data.Equipped.Cue = Catalog.Default
		end
	end

	-- The UTC day number has no natural top; StatCap (about 2.7 million years) bounds it.
	local daily = data.Daily
	fixInteger(daily, "Day", "Daily.Day", SaveCfg.StatCap, fixes)
	fixInteger(daily, "SoloMoney", "Daily.SoloMoney", SaveCfg.MoneyCap, fixes)
	fixInteger(daily, "PcMoney", "Daily.PcMoney", SaveCfg.MoneyCap, fixes)
	fixInteger(daily, "ShortMoney", "Daily.ShortMoney", SaveCfg.MoneyCap, fixes)
	fixInteger(daily, "Wins", "Daily.Wins", SaveCfg.StatCap, fixes)
	fixInteger(daily, "PcDrops", "Daily.PcDrops", SaveCfg.StatCap, fixes)
	fixInteger(daily, "Disguised", "Daily.Disguised", SaveCfg.StatCap, fixes)
	fixMapAt(
		daily,
		"Opponents",
		"Daily.Opponents",
		Config.Economy.SameOpponentMaxEntries,
		opponentEntry,
		fixes
	)
	fixInteger(daily, "PlaySeconds", "Daily.PlaySeconds", SECONDS_PER_DAY, fixes)
	fixMapAt(
		daily,
		"PlaytimeClaimed",
		"Daily.PlaytimeClaimed",
		SaveCfg.MaxSmallEntries,
		onlyTrue,
		fixes
	)

	local login = data.Login
	fixInteger(login, "LastDay", "Login.LastDay", SaveCfg.StatCap, fixes)
	fixInteger(login, "StreakDay", "Login.StreakDay", #Config.Daily.Streak, fixes)
	fixInteger(login, "Total", "Login.Total", SaveCfg.StatCap, fixes)
	fixInteger(login, "FreezeWeek", "Login.FreezeWeek", SaveCfg.StatCap, fixes)
	login.Week = nil -- the old four-week cycle (the track replaced it, plan section 6)

	local shop = data.Shop
	fixInteger(shop, "FirstJoin", "Shop.FirstJoin", SaveCfg.UnixTimeCap, fixes)
	for _, key in SHOP_FLAGS do
		fixBoolean(shop, key, "Shop." .. key, fixes)
	end
	fixPurchases(shop, fixes)
	fixMapAt(shop, "Limited", "Shop.Limited", cueCap, copies, fixes)
	fixInteger(shop, "BoostEnds", "Shop.BoostEnds", SaveCfg.UnixTimeCap, fixes)
	local restock = ensureTable(shop, "Restock", "Shop.Restock", fresh.Shop.Restock, fixes)
	fixInteger(restock, "Slot", "Shop.Restock.Slot", SaveCfg.StatCap, fixes)
	fixMapAt(
		restock,
		"Bought",
		"Shop.Restock.Bought",
		SaveCfg.MaxSmallEntries,
		wholeFrom1(SaveCfg.StatCap),
		fixes
	)

	fixMap(data.Codes, "Codes", SaveCfg.MaxCodeEntries, onlyTrue, fixes)

	dropNonFinite(data.Settings, "Settings", fixes)
	dropNonFinite(data.Flags, "Flags", fixes)

	fixUlts(data.Ults, fixes)

	local drops = data.Drops
	fixInteger(drops, "SinceRare", "Drops.SinceRare", SaveCfg.StatCap, fixes)
	fixInteger(drops, "SinceEpic", "Drops.SinceEpic", SaveCfg.StatCap, fixes)
	fixInteger(drops, "Total", "Drops.Total", SaveCfg.StatCap, fixes)

	local social = data.Social
	fixBoolean(social, "Group", "Social.Group", fixes)
	fixInteger(social, "InvitedBy", "Social.InvitedBy", USER_ID_CAP, fixes)
	fixBoolean(social, "InviteDone", "Social.InviteDone", fixes)
	fixInteger(social, "InviteMonth", "Social.InviteMonth", SaveCfg.StatCap, fixes)
	fixInteger(social, "Invites", "Social.Invites", SaveCfg.StatCap, fixes)

	fixTrades(data.Trades, fixes)

	fixLuckyBlocks(data.LuckyBlocks, fixes)

	return data, fixes
end

return SaveSchema
