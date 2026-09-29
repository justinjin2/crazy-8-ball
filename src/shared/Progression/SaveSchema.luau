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
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local UltCatalog = require(script.Parent.Parent.Ults.Catalog)
local UltSlots = require(script.Parent.Parent.Ults.Slots)

local SaveCfg = Config.Save
local RanksCfg = Config.Ranks

local SaveSchema = {}

SaveSchema.Version = 3

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
		Wins = 0, -- real wins today (the free case: Config.Cases.DailyWins, EveryAfter)
		FirstWinUsed = false, -- today's first-win XP boost is used
		Opponents = {}, -- [userId as a string] = { Matches, Cases } (anti-farm, ECONOMY 3.6)
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
	"FirstWinUsed",
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
			RealMatches = 0, -- real matches played (past one minute, not solo): Rookie Boost
			Wins = 0, -- real wins ever, people or PC: the new player's free cases
		},
		Inventory = {
			Cues = {}, -- [cueId] = count >= 1: case and Exclusive cues; never Catalog.Default
			Unique = {}, -- [cueId] = copy number: numbered Limited cues (#412)
			Cases = {}, -- [caseId] = count >= 1: unopened cases
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
			StreakDay = 0, -- the streak day last claimed, 1..#Config.Daily.Streak; 0 none
			Week = 0, -- the week of the Config.Daily.WeeksForBonus cycle, 1..; 0 none
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
		},
		Codes = {}, -- [CODE] = true: promo codes redeemed
		Settings = {},
		Flags = {},
		-- The ults (v3; Ults/Slots.fresh): the default ult in slot 1, the starter spins. Slots
		-- and Locked are gapless arrays of Config.Ults.Slots ("" = an empty slot).
		Ults = UltSlots.fresh(),
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

-- `t[key]` as a table: made a new empty one when it is anything else. For the migration,
-- which must never error on a broken save (validate reports what it replaces later).
local function tableAt(t: { [any]: any }, key: string): { [any]: any }
	local value = t[key]
	if type(value) ~= "table" then
		value = {}
		t[key] = value
	end
	return value
end

-- A count read from a map that may be broken: a whole number >= 1, or 0.
local function countIn(map: { [any]: any }, key: string): number
	local value = map[key]
	if SaveSchema.isInteger(value) and value >= 1 then
		return value
	end
	return 0
end

---------------------------------------------------------------------------------------------
-- Migrations
---------------------------------------------------------------------------------------------

-- `Migrations[n]` turns a version-n save into a version n+1 save (it may change the table in
-- place and return it). `migrate` stamps the new Version after each step. A migration sees the
-- save exactly as it was stored: PlayerData migrates a copy first, then runs ProfileStore's
-- Reconcile (which fills keys the template has and the save lacks), then `validate`. If a step
-- errors, the save keeps its old Version and PlayerData releases the stored save untouched
-- (and the player cannot play), so a step must read every old field defensively.
SaveSchema.Migrations = {} :: { [number]: (data: any) -> any }

-- 0 -> 1: a save written before saves had a version (or a blank one). Reconcile, run after
-- migrating, fills any missing keys from the template, so this only stamps the version.
SaveSchema.Migrations[0] = function(data: any): any
	data.Version = 1
	return data
end

-- Version 1's ladder: every division was this many XP wide (46 divisions, Reyes at 45,000).
-- Frozen here because Config now holds the new ladder; only migration 1 -> 2 reads it.
local V1_DIVISION_XP = 1000

-- Where each division starts on Config's ladder (1 = Bronze I ... divisionCount() = the top
-- tier's one division) and each division's width (none for the top, which has no top).
local function ladder(): ({ number }, { number })
	local rows: { [string]: { number } } = RanksCfg.DivisionXp :: any
	local starts: { number } = {}
	local widths: { number } = {}
	local xp = 0
	for order, tier in RanksCfg.Tiers do
		if order == #RanksCfg.Tiers then
			table.insert(starts, xp)
		else
			local row = rows[tier] or {}
			for division = 1, RanksCfg.DivisionsPerTier do
				local width = math.max(1, row[division] or 1)
				table.insert(starts, xp)
				table.insert(widths, width)
				xp += width
			end
		end
	end
	return starts, widths
end

-- 1 -> 2: the economy (docs/ECONOMY.md; ECONOMY_UI_PROMPT section 7).
-- * Rank XP moves to the new ladder, keeping the division a player sees at the same fraction
--   through it (the top tier: the XP past its start is kept as it is). An unrated save shows
--   Unranked whatever its XP, so its XP is left alone. PeakDivision indexes the same divisions
--   (1..46) on both ladders, so it stays. The target is Config's ladder: if that ladder ever
--   changes again, freeze today's copy here first, because the migration after this one will
--   read version-2 XP as being on it.
-- * Inventory.Cues was an array of ids and becomes a count per id. "default" and Classic (the
--   default cue, always owned, never counted) and anything that is not an id are dropped;
--   unknown ids are kept (a later catalog may know them). Every kept cue is marked in
--   Index.Seen (it was owned).
-- * Every tier whose division I the player already reached (PeakDivision) gives its rank
--   reward's cases and cue now, once: that money was paid under version 1, the items did not
--   exist yet. A tier cue already owned is not given twice (rank cues are one per player).
--   Given cues are marked Seen and New.
-- * Equipped.Cue "default", or any id the catalog does not know, becomes Classic.
-- * Progress is back-filled from Stats (version 1 counted only real matches against people),
--   so existing players do not get the Rookie Boost or the new player's free cases again.
-- * Daily keeps Day and SoloMoney and gains the rest fresh. Titles, Login, Shop (FirstJoin 0:
--   PlayerData sets it to the load time) and Codes start fresh.
SaveSchema.Migrations[1] = function(data: any): any
	local divisions = SaveSchema.divisionCount()
	local rated = SaveSchema.cleanInteger(data.RatedMatches, 0, SaveCfg.StatCap, 0) > 0
	local peak = SaveSchema.cleanInteger(data.PeakDivision, 0, divisions, 0)
	local fresh = SaveSchema.template()

	if rated then
		local oldXp = SaveSchema.cleanInteger(data.RankXp, 0, SaveCfg.RankXpCap, 0)
		local index = math.min(oldXp // V1_DIVISION_XP + 1, divisions)
		local into = oldXp - (index - 1) * V1_DIVISION_XP
		local starts, widths = ladder()
		local width = widths[index]
		local xp = if width ~= nil
			then starts[index] + (into * width) // V1_DIVISION_XP
			else starts[index] + into
		data.RankXp = math.min(xp, SaveCfg.RankXpCap)
	end

	local inventory = tableAt(data, "Inventory")
	local oldCues = inventory.Cues
	local cues: { [string]: number } = {}
	if type(oldCues) == "table" then
		-- Counting is the same in any order, so walking the array in hash order is safe.
		for key, id in oldCues do
			if
				SaveSchema.isInteger(key)
				and key >= 1
				and SaveSchema.isId(id)
				and id ~= "default"
				and id ~= Catalog.Default
			then
				cues[id] = math.min((cues[id] or 0) + 1, SaveCfg.ItemCountCap)
			end
		end
	end
	inventory.Cues = cues
	tableAt(inventory, "Unique")
	local cases = tableAt(inventory, "Cases")
	local newTags = tableAt(inventory, "New")
	local seen = tableAt(tableAt(data, "Index"), "Seen")
	tableAt(data.Index, "Rows")
	for id in cues do
		seen[id] = true
	end

	local tierRewards: { [string]: any } = RanksCfg.Rewards.Tier :: any
	for order, tier in RanksCfg.Tiers do
		local reward = tierRewards[tier]
		local first = (order - 1) * RanksCfg.DivisionsPerTier + 1
		if reward ~= nil and first <= peak then
			local rewardCases = reward.Cases or {}
			for _, caseId in Config.Cases.Order do
				local count = rewardCases[caseId]
				if SaveSchema.isInteger(count) and count >= 1 then
					cases[caseId] = math.min(countIn(cases, caseId) + count, SaveCfg.ItemCountCap)
				end
			end
			local cue = reward.Cue
			if SaveSchema.isId(cue) and cue ~= Catalog.Default and cues[cue] == nil then
				cues[cue] = 1
				seen[cue] = true
				newTags[cue] = true
			end
		end
	end

	local equipped = tableAt(data, "Equipped")
	if not Catalog.exists(equipped.Cue) then
		equipped.Cue = Catalog.Default
	end

	local stats = if type(data.Stats) == "table" then data.Stats else {}
	local function stat(key: string): number
		return (SaveSchema.cleanInteger(stats[key], 0, SaveCfg.StatCap, 0))
	end
	data.Progress = {
		RealMatches = stat("Matches"),
		Wins = math.min(stat("Wins") + stat("PcWins"), SaveCfg.StatCap),
	}

	local daily = tableAt(data, "Daily")
	for _, key in DAILY_KEYS do
		if daily[key] == nil then
			daily[key] = fresh.Daily[key]
		end
	end

	for _, key in { "Titles", "Login", "Shop", "Codes" } do
		if data[key] == nil then
			data[key] = fresh[key]
		end
	end
	return data
end

-- 2 -> 3: the ults (docs/prompts/ULTIMATES_PROMPT.md section 11). Adds `Ults` as a new
-- save's (Ults/Slots.fresh): the default ult (Magnet) in slot 1 and Config.Ults.Earn.Starter
-- spins, the same starter spins a new player gets. Everything else is untouched. A version-2
-- save has no Ults, so anything found there is replaced.
SaveSchema.Migrations[2] = function(data: any): any
	data.Ults = UltSlots.fresh()
	return data
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

-- A cleaner for Daily.Opponents entries: exactly { Matches, Cases }, whole numbers in
-- 0..StatCap. Anything else in an entry is dropped, so an entry has a fixed size.
local function opponentEntry(value: any): (any, boolean)
	if type(value) ~= "table" then
		return nil, true
	end
	local matches, badMatches = SaveSchema.cleanInteger(value.Matches, 0, SaveCfg.StatCap, 0)
	local cases, badCases = SaveSchema.cleanInteger(value.Cases, 0, SaveCfg.StatCap, 0)
	local extra = false
	-- Only whether any other key exists matters, so the walk's order does not.
	for key in value do
		if key ~= "Matches" and key ~= "Cases" then
			extra = true
			break
		end
	end
	if badMatches or badCases or extra then
		return { Matches = matches, Cases = cases }, true
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

-- A cleaner for an ult slot: a catalog ult id or "" (empty); anything else becomes "".
local function ultSlot(value: any): (any, boolean)
	if value == "" or UltCatalog.exists(value) then
		return value, false
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

--- Repair a save in place so every field holds a safe value. Returns the same table (or a
--- fresh template if `data` was not a table) and the fixes it made, empty when the save was
--- clean. Unknown string keys at the top level and in the fixed-field tables are left alone
--- (they may be a newer version's fields); maps of ids are cleaned entry by entry. Never
--- errors, whatever it is given.
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
	fixMapAt(inventory, "Cases", "Inventory.Cases", SaveCfg.MaxCaseEntries, counts, fixes)
	fixMapAt(inventory, "New", "Inventory.New", cueCap, onlyTrue, fixes)

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
		elseif inventory.Cues[cue] == nil and inventory.Unique[cue] == nil then
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
	fixBoolean(daily, "FirstWinUsed", "Daily.FirstWinUsed", fixes)
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
	fixInteger(login, "Week", "Login.Week", Config.Daily.WeeksForBonus, fixes)

	local shop = data.Shop
	fixInteger(shop, "FirstJoin", "Shop.FirstJoin", SaveCfg.UnixTimeCap, fixes)
	for _, key in SHOP_FLAGS do
		fixBoolean(shop, key, "Shop." .. key, fixes)
	end
	fixPurchases(shop, fixes)
	fixMapAt(shop, "Limited", "Shop.Limited", cueCap, copies, fixes)

	fixMap(data.Codes, "Codes", SaveCfg.MaxCodeEntries, onlyTrue, fixes)

	dropNonFinite(data.Settings, "Settings", fixes)
	dropNonFinite(data.Flags, "Flags", fixes)

	fixUlts(data.Ults, fixes)

	return data, fixes
end

return SaveSchema
