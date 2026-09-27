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
-- Instances or userdata. `validate` enforces the parts of that a bug could break.
--
-- Changing the layout: bump `Version`, add `Migrations[old]` that turns an old save into the
-- new one, and update `template()` and `validate`. Never edit an old migration once shipped.
local Config = require(script.Parent.Parent.Config)

local SaveCfg = Config.Save
local RanksCfg = Config.Ranks

local SaveSchema = {}

SaveSchema.Version = 1

-- The longest cue id a save may name (a catalog id, never player text).
local MAX_ID_LENGTH = 64
local DEFAULT_CUE = "default"

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

-- The sub-tables that are string-keyed maps, in the order fixes are reported.
local MAP_KEYS = { "Stats", "Daily", "Inventory", "Equipped", "Settings", "Flags" }

--- A fresh copy of a new player's save. Every call builds new tables, so changing one copy
--- never changes the next.
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
		Daily = { Day = 0, SoloMoney = 0 }, -- UTC day number and money earned in solo that day
		Inventory = { Cues = {} }, -- gapless array of owned cue ids
		Equipped = { Cue = DEFAULT_CUE },
		Settings = {},
		Flags = {},
	}
end

--- How many divisions the ladder has, bottom to top: DivisionsPerTier for every tier but the
--- last, which has one.
function SaveSchema.divisionCount(): number
	return (#RanksCfg.Tiers - 1) * RanksCfg.DivisionsPerTier + 1
end

---------------------------------------------------------------------------------------------
-- Number helpers (also used by other modules to check inputs)
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
-- place and return it). `migrate` stamps the new Version after each step. A migration sees the
-- save exactly as it was stored: PlayerData migrates a copy first, then runs ProfileStore's
-- Reconcile (which fills keys the template has and the save lacks), then `validate`. If a step
-- errors, the save keeps its old Version and PlayerData releases the stored save untouched.
SaveSchema.Migrations = {} :: { [number]: (data: any) -> any }

-- 0 -> 1: a save written before saves had a version (or a blank one). Reconcile, run after
-- migrating, fills any missing keys from the template, so this only stamps the version.
SaveSchema.Migrations[0] = function(data: any): any
	data.Version = 1
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

-- Make `parent[key]` a table, rebuilding it from `fresh` when it is anything else.
local function ensureTable(parent: { [any]: any }, key: string, fresh: any, fixes: { string }): any
	local value = parent[key]
	if type(value) ~= "table" then
		table.insert(fixes, ("%s was %s: reset"):format(key, describe(value)))
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

--- Repair a save in place so every field holds a safe value. Returns the same table (or a
--- fresh template if `data` was not a table) and the fixes it made, empty when the save was
--- clean. Unknown string keys are left alone (they may be a newer version's fields). Never
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
		local t = ensureTable(data, key, fresh[key], fixes)
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

	-- The UTC day number has no natural top; StatCap (about 2.7 million years) bounds it.
	fixInteger(data.Daily, "Day", "Daily.Day", SaveCfg.StatCap, fixes)
	fixInteger(data.Daily, "SoloMoney", "Daily.SoloMoney", SaveCfg.MoneyCap, fixes)

	local inventory = data.Inventory
	if type(inventory.Cues) ~= "table" then
		table.insert(fixes, ("Inventory.Cues was %s: reset"):format(describe(inventory.Cues)))
		inventory.Cues = {}
	end
	fixArray(inventory.Cues, "Inventory.Cues", fixes)

	local cue = data.Equipped.Cue
	if type(cue) ~= "string" or #cue == 0 or #cue > MAX_ID_LENGTH then
		table.insert(fixes, ("Equipped.Cue was %s: set to %q"):format(describe(cue), DEFAULT_CUE))
		data.Equipped.Cue = DEFAULT_CUE
	end

	dropNonFinite(data.Settings, "Settings", fixes)
	dropNonFinite(data.Flags, "Flags", fixes)

	return data, fixes
end

return SaveSchema
