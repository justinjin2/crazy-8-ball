--!strict
-- The save layout: its template, its migrations and its repair of hostile data.

local H = require("./harness")

local function setup(): (any, any)
	return H.require("Config"), H.require("Progression.SaveSchema")
end

local NAN = 0 / 0
local INF = math.huge

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

local function isInt(x: any): boolean
	return type(x) == "number" and x == x and math.abs(x) ~= INF and x == math.floor(x)
end

local function inRange(x: any, max: number, what: string)
	H.expect(isInt(x), what .. " must be a finite integer, got " .. tostring(x))
	H.expect(x >= 0 and x <= max, ("%s out of range: %s"):format(what, tostring(x)))
end

local function isGaplessArray(t: any): boolean
	if type(t) ~= "table" then
		return false
	end
	local count = 0
	for key in t do
		if not isInt(key) or key < 1 then
			return false
		end
		count += 1
	end
	return count == #t
end

local function onlyStringKeys(t: any): boolean
	for key in t do
		if type(key) ~= "string" then
			return false
		end
	end
	return true
end

local function size(t: any): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- A bounded map of ids: a table, string keys of 1..64 characters, at most `max` entries,
-- every value passing `ok`.
local function checkMap(t: any, max: number, what: string, ok: (any) -> boolean)
	H.expect(type(t) == "table", what .. " must be a table")
	local n = 0
	for key, value in t do
		H.expect(
			type(key) == "string" and #key >= 1 and #key <= 64,
			what .. " has a bad key " .. tostring(key)
		)
		H.expect(ok(value), ("%s[%s] has a bad value %s"):format(what, key, tostring(value)))
		n += 1
	end
	H.expect(n <= max, ("%s has %d entries, over %d"):format(what, n, max))
end

local function isTrue(v: any): boolean
	return v == true
end

local function countUpTo(cap: number): (any) -> boolean
	return function(v: any): boolean
		return isInt(v) and v >= 1 and v <= cap
	end
end

-- Everything a repaired save must satisfy.
local function assertClean(Config: any, SaveSchema: any, save: any)
	local S = Config.Save
	local Catalog = H.require("Progression.Catalog")
	H.expect(type(save) == "table", "save must be a table")
	H.expect(onlyStringKeys(save), "top-level keys must be strings")
	H.expect(isInt(save.Version) and save.Version >= 0, "Version must be an integer >= 0")
	inRange(save.Money, S.MoneyCap, "Money")
	inRange(save.RankXp, S.RankXpCap, "RankXp")
	inRange(save.PeakDivision, SaveSchema.divisionCount(), "PeakDivision")
	inRange(save.RatedMatches, S.StatCap, "RatedMatches")
	for _, key in MAP_KEYS do
		H.expect(type(save[key]) == "table", key .. " must be a table")
		H.expect(onlyStringKeys(save[key]), key .. " keys must be strings")
	end
	for _, key in STAT_KEYS do
		inRange(save.Stats[key], S.StatCap, "Stats." .. key)
	end
	H.expect(save.Stats.BestWinStreak >= save.Stats.WinStreak, "best streak below current")
	inRange(save.Progress.RealMatches, S.StatCap, "Progress.RealMatches")
	inRange(save.Progress.Wins, S.StatCap, "Progress.Wins")

	local inv = save.Inventory
	checkMap(inv.Cues, S.MaxCueEntries, "Inventory.Cues", countUpTo(S.ItemCountCap))
	H.expect(inv.Cues.Classic == nil, "Classic is never counted")
	checkMap(inv.Unique, S.MaxCueEntries, "Inventory.Unique", countUpTo(S.CopyNumberCap))
	H.expect(inv.Unique.Classic == nil, "Classic is never numbered")
	checkMap(inv.Cases, S.MaxCaseEntries, "Inventory.Cases", countUpTo(S.ItemCountCap))
	checkMap(inv.New, S.MaxCueEntries, "Inventory.New", isTrue)
	checkMap(save.Index.Seen, S.MaxCueEntries, "Index.Seen", isTrue)
	checkMap(save.Index.Rows, S.MaxSmallEntries, "Index.Rows", isTrue)
	checkMap(save.Titles, S.MaxTitleEntries, "Titles", isTrue)
	checkMap(save.Codes, S.MaxCodeEntries, "Codes", isTrue)

	local cue = save.Equipped.Cue
	H.expect(
		cue == Catalog.Default or (Catalog.exists(cue) and (inv.Cues[cue] or inv.Unique[cue])),
		"Equipped.Cue must be Classic or an owned catalog cue, got " .. tostring(cue)
	)

	local daily = save.Daily
	inRange(daily.Day, S.StatCap, "Daily.Day")
	inRange(daily.SoloMoney, S.MoneyCap, "Daily.SoloMoney")
	inRange(daily.PcMoney, S.MoneyCap, "Daily.PcMoney")
	inRange(daily.ShortMoney, S.MoneyCap, "Daily.ShortMoney")
	inRange(daily.Wins, S.StatCap, "Daily.Wins")
	H.expect(type(daily.FirstWinUsed) == "boolean", "Daily.FirstWinUsed must be a boolean")
	checkMap(
		daily.Opponents,
		Config.Economy.SameOpponentMaxEntries,
		"Daily.Opponents",
		function(v: any): boolean
			return type(v) == "table"
				and size(v) == 2
				and isInt(v.Matches)
				and v.Matches >= 0
				and v.Matches <= S.StatCap
				and isInt(v.Cases)
				and v.Cases >= 0
				and v.Cases <= S.StatCap
		end
	)
	inRange(daily.PlaySeconds, 86400, "Daily.PlaySeconds")
	checkMap(daily.PlaytimeClaimed, S.MaxSmallEntries, "Daily.PlaytimeClaimed", isTrue)

	inRange(save.Login.LastDay, S.StatCap, "Login.LastDay")
	inRange(save.Login.StreakDay, #Config.Daily.Streak, "Login.StreakDay")
	inRange(save.Login.Week, Config.Daily.WeeksForBonus, "Login.Week")

	local shop = save.Shop
	inRange(shop.FirstJoin, S.UnixTimeCap, "Shop.FirstJoin")
	for _, key in { "VipOffer", "VipCueGiven", "StarterBought", "FirstPackBought" } do
		H.expect(type(shop[key]) == "boolean", "Shop." .. key .. " must be a boolean")
	end
	H.expect(isGaplessArray(shop.Purchases), "Shop.Purchases must be a gapless array")
	H.expect(#shop.Purchases <= Config.Shop.RecentPurchases, "Shop.Purchases over its cap")
	for i = 1, #shop.Purchases do
		H.expect(type(shop.Purchases[i]) == "string", "purchase ids are strings")
	end
	checkMap(shop.Limited, S.MaxCueEntries, "Shop.Limited", countUpTo(S.CopyNumberCap))

	for _, map in { save.Settings, save.Flags } do
		for _, value in map do
			if type(value) == "number" then
				H.expect(value == value and math.abs(value) ~= INF, "settings must be finite")
			end
		end
	end

	local ults = save.Ults
	local UltCatalog = H.require("Ults.Catalog")
	local slots = Config.Ults.Slots
	H.expect(isGaplessArray(ults.Slots) and #ults.Slots == slots, "Ults.Slots has every slot")
	for i = 1, slots do
		local id = ults.Slots[i]
		H.expect(id == "" or UltCatalog.exists(id), "Ults.Slots holds ult ids or empty")
	end
	H.expect(isGaplessArray(ults.Locked) and #ults.Locked == slots, "Ults.Locked has every slot")
	for i = 1, slots do
		H.expect(type(ults.Locked[i]) == "boolean", "Ults.Locked holds booleans")
	end
	H.expect(isInt(ults.Selected) and ults.Selected >= 1 and ults.Selected <= slots, "Selected")
	inRange(ults.Spins, Config.Ults.Earn.MaxSpins, "Ults.Spins")
	inRange(ults.LuckySpins, Config.Ults.Earn.MaxSpins, "Ults.LuckySpins")
	inRange(ults.Pity, Config.Ults.Roll.PityAt - 1, "Ults.Pity")
	inRange(ults.FreeSpinDay, S.StatCap, "Ults.FreeSpinDay")
	inRange(ults.SpinsDone, S.StatCap, "Ults.SpinsDone")
	H.expect(type(ults.QueueUlts) == "boolean", "Ults.QueueUlts must be a boolean")
end

-- A version-2 save as the economy's code wrote it (no Ults).
local function v2Save(SaveSchema: any): any
	local save = SaveSchema.template()
	save.Version = 2
	save.Ults = nil
	return save
end

-- A tiny deterministic generator (Numerical Recipes LCG), so the fuzz is the same every run.
local function newRng(seed: number): (number) -> number
	local state = seed
	return function(n: number): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state % n + 1
	end
end

local FUZZ_KEYS = {
	"Cues",
	"Cue",
	"Wins",
	"Day",
	"x",
	"Classic",
	"GoldCue",
	"Standard",
	"Matches",
	"Cases",
}

-- A random value that could turn up anywhere in a broken save.
local function randomValue(rng: (number) -> number, depth: number): any
	local pick = rng(16)
	if pick == 1 then
		return nil
	elseif pick == 2 then
		return NAN
	elseif pick == 3 then
		return INF
	elseif pick == 4 then
		return -INF
	elseif pick == 5 then
		return -rng(1000)
	elseif pick == 6 then
		return rng(1000) + 0.5
	elseif pick == 7 then
		return 1e300
	elseif pick == 8 then
		return "100"
	elseif pick == 9 then
		return rng(2) == 1
	elseif pick == 10 then
		return ""
	elseif pick == 11 then
		return string.rep("x", 100)
	elseif pick == 12 or pick == 13 then
		return rng(1000) - 1
	end
	-- A table: an array, a map, or both at once, with odd keys.
	local t = {}
	if depth >= 3 then
		return t
	end
	for _ = 1, rng(5) - 1 do
		local keyPick = rng(7)
		local key: any
		if keyPick == 1 then
			key = rng(4)
		elseif keyPick == 2 then
			key = rng(10) + 0.5
		elseif keyPick == 3 then
			key = true
		elseif keyPick == 4 then
			key = {}
		elseif keyPick == 5 then
			key = -rng(3)
		elseif keyPick == 6 then
			key = string.rep("k", 60 + rng(10))
		else
			key = FUZZ_KEYS[rng(#FUZZ_KEYS)]
		end
		t[key] = randomValue(rng, depth + 1)
	end
	return t
end

local FIELDS = {
	"Version",
	"Money",
	"RankXp",
	"PeakDivision",
	"RatedMatches",
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

-- Sub-fields the fuzz breaks, by table.
local SUB_FIELDS: { [string]: { string } } = {
	Stats = { "Wins", "WinStreak" },
	Progress = { "RealMatches", "Wins" },
	Inventory = { "Cues", "Unique", "Cases", "New" },
	Index = { "Seen", "Rows" },
	Equipped = { "Cue" },
	Daily = {
		"Day",
		"SoloMoney",
		"Wins",
		"FirstWinUsed",
		"Opponents",
		"PlaySeconds",
		"PlaytimeClaimed",
	},
	Login = { "LastDay", "StreakDay", "Week" },
	Shop = { "FirstJoin", "VipOffer", "Purchases", "Limited" },
	Ults = {
		"Slots",
		"Selected",
		"Locked",
		"Spins",
		"LuckySpins",
		"Pity",
		"FreeSpinDay",
		"SpinsDone",
		"QueueUlts",
	},
}
local SUB_TABLES =
	{ "Stats", "Progress", "Inventory", "Index", "Equipped", "Daily", "Login", "Shop", "Ults" }

-- ProfileStore's Reconcile (src/server/Vendor/ProfileStore.luau ReconcileTable), which
-- PlayerData runs between migrate and validate: fill missing string keys from the template.
local function reconcile(target: any, template: any)
	for key, value in template do
		if type(key) == "string" then
			if target[key] == nil then
				target[key] = if type(value) == "table" then table.clone(value) else value
			elseif type(target[key]) == "table" and type(value) == "table" then
				reconcile(target[key], value)
			end
		end
	end
end

-- A version-1 save as the old code wrote it.
local function v1Save(fields: { [string]: any }?): any
	local stats = {}
	for _, key in STAT_KEYS do
		stats[key] = 0
	end
	local save: any = {
		Version = 1,
		Money = 0,
		RankXp = 0,
		PeakDivision = 0,
		RatedMatches = 0,
		Stats = stats,
		Daily = { Day = 0, SoloMoney = 0 },
		Inventory = { Cues = {} },
		Equipped = { Cue = "default" },
		Settings = {},
		Flags = {},
	}
	for key, value in fields or {} do
		save[key] = value
	end
	return save
end

-- The new ladder's division starts and widths, from Config (independent of SaveSchema).
local function newLadder(Config: any): ({ number }, { number })
	local R = Config.Ranks
	local starts, widths = {}, {}
	local xp = 0
	for order, tier in R.Tiers do
		if order == #R.Tiers then
			table.insert(starts, xp)
		else
			for division = 1, R.DivisionsPerTier do
				table.insert(starts, xp)
				table.insert(widths, R.DivisionXp[tier][division])
				xp += R.DivisionXp[tier][division]
			end
		end
	end
	return starts, widths
end

-- The division index of a tier's division `d` (Bronze I = 1).
local function indexOf(Config: any, tier: string, d: number): number
	return (table.find(Config.Ranks.Tiers, tier) :: number - 1) * Config.Ranks.DivisionsPerTier + d
end

-- A rough JSON encoder's length (what a DataStore stores): keys and strings quoted, numbers
-- as Luau prints them, arrays as [..], maps as {..}. Escapes are ignored (ids have none).
local function jsonLength(value: any): number
	local kind = type(value)
	if kind == "string" then
		return #value + 2
	elseif kind == "number" then
		if value == math.floor(value) and math.abs(value) < 1e15 then
			return #("%d"):format(value)
		end
		return #tostring(value)
	elseif kind == "boolean" then
		return if value then 4 else 5
	elseif kind == "table" then
		local n = 0
		local total = 2 -- the brackets
		if #value > 0 then
			for i = 1, #value do
				total += jsonLength(value[i])
				n += 1
			end
		else
			for key, item in value do
				total += #tostring(key) + 3 + jsonLength(item) -- "key":
				n += 1
			end
		end
		return total + math.max(n - 1, 0) -- commas
	end
	return 4 -- null
end

return {
	["the template has every field at its starting value"] = function()
		local _, SaveSchema = setup()
		local t = SaveSchema.template()
		H.expect(SaveSchema.Version == 4, "version 4")
		H.expect(t.Version == SaveSchema.Version, "template carries the current version")
		H.expect(t.Money == 0 and t.RankXp == 0 and t.PeakDivision == 0, "starts at zero")
		H.expect(t.RatedMatches == 0, "starts unranked")
		for _, key in STAT_KEYS do
			H.expect(t.Stats[key] == 0, "Stats." .. key .. " starts at 0")
		end
		H.expect(size(t.Stats) == #STAT_KEYS, "Stats has exactly the listed counters")
		H.expect(size(t) == #FIELDS, "exactly the listed fields")
		H.expect(t.Progress.RealMatches == 0 and t.Progress.Wins == 0, "no progress yet")
		H.expect(size(t.Progress) == 2, "Progress has two counters")
		for _, key in { "Cues", "Unique", "Cases", "New" } do
			H.expect(type(t.Inventory[key]) == "table", "Inventory." .. key)
			H.expect(next(t.Inventory[key]) == nil, "Inventory." .. key .. " starts empty")
		end
		H.expect(size(t.Inventory) == 4, "Inventory has four maps")
		H.expect(next(t.Index.Seen) == nil and next(t.Index.Rows) == nil, "empty Index")
		H.expect(size(t.Index) == 2, "Index has two maps")
		H.expect(next(t.Titles) == nil and next(t.Codes) == nil, "no titles or codes")
		H.expect(t.Equipped.Cue == "Classic", "Classic is the default cue")
		local d = t.Daily
		H.expect(d.Day == 0 and d.SoloMoney == 0 and d.PcMoney == 0 and d.ShortMoney == 0, "d")
		H.expect(d.Wins == 0 and d.FirstWinUsed == false and d.PlaySeconds == 0, "daily")
		H.expect(next(d.Opponents) == nil and next(d.PlaytimeClaimed) == nil, "daily maps")
		H.expect(size(d) == 9, "Daily has nine fields")
		local l = t.Login
		H.expect(l.LastDay == 0 and l.StreakDay == 0 and l.Week == 0 and size(l) == 3, "login")
		local s = t.Shop
		H.expect(s.FirstJoin == 0, "first join not set yet")
		H.expect(not s.VipOffer and not s.VipCueGiven, "no VIP")
		H.expect(not s.StarterBought and not s.FirstPackBought, "nothing bought")
		H.expect(type(s.Purchases) == "table" and #s.Purchases == 0, "no receipts")
		H.expect(next(s.Limited) == nil and size(s) == 7, "shop fields")
		H.expect(next(t.Settings) == nil and next(t.Flags) == nil, "empty maps")
		local Config = H.require("Config")
		local u = t.Ults
		H.expect(u.Slots[1] == Config.Ults.Default and u.Slots[1] == "Magnet", "Magnet in slot 1")
		H.expect(#u.Slots == 3 and u.Slots[2] == "" and u.Slots[3] == "", "slots 2, 3 empty")
		H.expect(#u.Locked == 3 and not u.Locked[1] and not u.Locked[2] and not u.Locked[3], "")
		H.expect(u.Selected == 1 and u.Spins == Config.Ults.Earn.Starter, "starter spins")
		H.expect(u.LuckySpins == 0 and u.Pity == 0 and u.FreeSpinDay == 0, "nothing else")
		H.expect(u.SpinsDone == 0 and u.QueueUlts == true and size(u) == 9, "ults fields")
	end,

	["template copies are independent"] = function()
		local _, SaveSchema = setup()
		local a = SaveSchema.template()
		a.Money = 5
		a.Stats.Wins = 3
		a.Daily.Day = 9
		a.Daily.Opponents["1"] = { Matches = 1, Cases = 0 }
		a.Inventory.Cues.GoldCue = 1
		a.Index.Seen.GoldCue = true
		a.Equipped.Cue = "GoldCue"
		a.Shop.Purchases[1] = "r1"
		a.Settings.x = 1
		a.Flags.y = true
		local b = SaveSchema.template()
		H.expect(b.Money == 0 and b.Stats.Wins == 0 and b.Daily.Day == 0, "numbers untouched")
		H.expect(next(b.Inventory.Cues) == nil and b.Equipped.Cue == "Classic", "untouched")
		H.expect(next(b.Daily.Opponents) == nil and next(b.Index.Seen) == nil, "maps untouched")
		H.expect(#b.Shop.Purchases == 0, "array untouched")
		H.expect(b.Settings.x == nil and b.Flags.y == nil, "maps untouched")
		H.expect(a.Stats ~= b.Stats and a.Inventory.Cues ~= b.Inventory.Cues, "new tables")
	end,

	["the division count comes from Config"] = function()
		local Config, SaveSchema = setup()
		local R = Config.Ranks
		H.expect(
			SaveSchema.divisionCount() == (#R.Tiers - 1) * R.DivisionsPerTier + 1,
			"every tier but the last has DivisionsPerTier divisions"
		)
		H.expect(SaveSchema.divisionCount() == 46, "10 tiers of 5, the last with one")
	end,

	["the clean template needs no fixes and passes every check"] = function()
		local Config, SaveSchema = setup()
		local t = SaveSchema.template()
		local out, fixes = SaveSchema.validate(t)
		H.expect(out == t, "same table back")
		H.expect(#fixes == 0, "no fixes, got: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["isInteger, cleanInteger and isId"] = function()
		local _, SaveSchema = setup()
		H.expect(
			SaveSchema.isInteger(0) and SaveSchema.isInteger(-3) and SaveSchema.isInteger(1e12)
		)
		local notIntegers: { any } = { 1.5, NAN, INF, -INF, "1", true, {} }
		for _, bad in notIntegers do
			H.expect(not SaveSchema.isInteger(bad), "not an integer: " .. tostring(bad))
		end
		local function check(x: any, expected: number, expectChanged: boolean)
			local value, changed = SaveSchema.cleanInteger(x, 0, 100, 7)
			H.expect(
				value == expected,
				("cleanInteger(%s) = %s"):format(tostring(x), tostring(value))
			)
			H.expect(changed == expectChanged, "changed flag for " .. tostring(x))
		end
		check(50, 50, false)
		check(0, 0, false)
		check(100, 100, false)
		check(1.9, 1, true)
		check(-5, 0, true)
		check(1e300, 100, true)
		check(NAN, 7, true)
		check(INF, 7, true)
		check(-INF, 7, true)
		check("100", 7, true)
		check({}, 7, true)
		check(nil, 7, true)
		local negZero, changed = SaveSchema.cleanInteger(-0.5, -1, 100, 0)
		H.expect(negZero == -1 and changed, "floors toward minus infinity")
		local zero = SaveSchema.cleanInteger(-0, 0, 100, 0)
		H.expect(1 / zero == INF, "no -0 comes back")

		H.expect(SaveSchema.isId("a") and SaveSchema.isId(string.rep("a", 64)), "ids")
		for _, bad in { "", string.rep("a", 65), 5, true, {}, nil :: any } do
			H.expect(not SaveSchema.isId(bad), "not an id: " .. tostring(bad))
		end
	end,

	["freshDaily and rolloverDaily"] = function()
		local _, SaveSchema = setup()
		local a = SaveSchema.freshDaily(20000)
		local b = SaveSchema.freshDaily(20000)
		H.expect(a.Day == 20000 and a ~= b and a.Opponents ~= b.Opponents, "fresh copies")

		local daily = SaveSchema.freshDaily(20000)
		daily.SoloMoney = 120
		daily.PcMoney = 500
		daily.ShortMoney = 80
		daily.Wins = 4
		daily.FirstWinUsed = true
		daily.Opponents["123"] = { Matches = 3, Cases = 1 }
		daily.PlaySeconds = 1800
		daily.PlaytimeClaimed["1"] = true
		daily.Stale = 5 -- a field the day left behind
		local opponents = daily.Opponents

		H.expect(SaveSchema.rolloverDaily(daily, 20000) == false, "same day: no reset")
		H.expect(daily.SoloMoney == 120 and daily.Opponents["123"].Matches == 3, "untouched")
		H.expect(daily.Stale == 5, "nothing touched on the same day")

		H.expect(SaveSchema.rolloverDaily(daily, 20001) == true, "a new day resets")
		H.expect(daily.Day == 20001, "the new day")
		local fresh = SaveSchema.freshDaily(20001)
		for key, value in fresh do
			if type(value) == "table" then
				H.expect(type(daily[key]) == "table" and next(daily[key]) == nil, key .. " empty")
			else
				H.expect(daily[key] == value, key .. " back to its fresh value")
			end
		end
		H.expect(size(daily) == size(fresh), "exactly the fresh fields")
		H.expect(daily.Opponents ~= opponents and next(opponents) ~= nil, "a new table")
		H.expect(SaveSchema.rolloverDaily(daily, 20001) == false, "once per day")
		-- An earlier day (a clock step back) is still another day.
		H.expect(SaveSchema.rolloverDaily(daily, 19999) == true and daily.Day == 19999, "back")
	end,

	["migrate brings a save with no version to the current one"] = function()
		local _, SaveSchema = setup()
		for _, version in { nil :: any, 0, -2, NAN, "1", 0.5 } do
			local save = { Money = 12, Version = version }
			local out, notes = SaveSchema.migrate(save)
			H.expect(out == save, "migrated in place")
			H.expect(out.Version == SaveSchema.Version, "now current, from " .. tostring(version))
			H.expect(out.Money == 12, "data kept")
			H.expect(
				#notes == 4
					and notes[1] == "migrated 0 -> 1"
					and notes[2] == "migrated 1 -> 2"
					and notes[3] == "migrated 2 -> 3"
					and notes[4] == "migrated 3 -> 4",
				table.concat(notes, "; ")
			)
		end
	end,

	["every version below the current one has a migration"] = function()
		local Config, SaveSchema = setup()
		for v = 0, SaveSchema.Version - 1 do
			H.expect(type(SaveSchema.Migrations[v]) == "function", "missing migration " .. v)
		end
		-- Every step, run from version 0 and then through Reconcile, gives a clean save.
		local out = SaveSchema.migrate({ Version = 0 })
		H.expect(out.Version == SaveSchema.Version, "reaches the current version")
		reconcile(out, SaveSchema.template())
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "clean after Reconcile: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["migrate leaves a current save alone"] = function()
		local _, SaveSchema = setup()
		local t = SaveSchema.template()
		t.Money = 42
		local out, notes = SaveSchema.migrate(t)
		H.expect(out == t and out.Money == 42 and out.Version == SaveSchema.Version, "no-op")
		H.expect(#notes == 0, "nothing to report")
	end,

	["migrate never downgrades a save from a newer version"] = function()
		local _, SaveSchema = setup()
		local future = { Version = SaveSchema.Version + 1, Money = 9, NewThing = { a = 1 } }
		local out, notes = SaveSchema.migrate(future)
		H.expect(out == future, "same table")
		H.expect(out.Version == SaveSchema.Version + 1, "version kept")
		H.expect(out.Money == 9 and out.NewThing.a == 1, "data untouched")
		H.expect(#notes == 1 and notes[1]:sub(1, 14) == "future version", "reported")
	end,

	["a migration that errors or is missing stops at the old version"] = function()
		local _, SaveSchema = setup()
		local real = SaveSchema.Migrations[0]
		-- A step that changes the save, then errors partway.
		SaveSchema.Migrations[0] = function(data: any): any
			data.Money = -1
			error("disk on fire")
		end
		local okBroken, broken, brokenNotes = pcall(SaveSchema.migrate, { Money = 5 })
		SaveSchema.Migrations[0] = nil
		local okMissing, missing, missingNotes = pcall(SaveSchema.migrate, { Money = 5 })
		SaveSchema.Migrations[0] = real
		H.expect(okBroken and okMissing, "migrate never errors")
		-- PlayerData tells a failed migration by the version, and then releases the save as it
		-- was stored (it migrates a copy), so the half-changed table is never written back.
		H.expect(broken.Version ~= SaveSchema.Version, "a failed step leaves the old version")
		H.expect(
			#brokenNotes == 1 and brokenNotes[1]:find("failed", 1, true) ~= nil,
			table.concat(brokenNotes, "; ")
		)
		H.expect(missing.Version ~= SaveSchema.Version, "a missing step leaves the old version")
		H.expect(missing.Money == 5, "a missing step changes nothing")
		H.expect(
			#missingNotes == 1 and missingNotes[1]:find("no migration", 1, true) ~= nil,
			table.concat(missingNotes, "; ")
		)
	end,

	["migrate turns a non-table into a fresh template"] = function()
		local _, SaveSchema = setup()
		for _, bad in { nil :: any, 5, "save", true } do
			local out, notes = SaveSchema.migrate(bad)
			H.expect(type(out) == "table" and out.Version == SaveSchema.Version, "template")
			H.expect(#notes == 1, "one note")
		end
	end,

	["migration 1 -> 2 keeps Gold III halfway at Gold III halfway"] = function()
		local Config, SaveSchema = setup()
		local Ranks = H.require("Progression.Ranks")
		local gold3 = indexOf(Config, "Gold", 3)
		H.expect(gold3 == 13, "Gold III is division 13")
		-- Old ladder: 1,000 per division, so Gold III starts at 12,000; halfway is 12,500.
		local save = v1Save({ RankXp = 12500, PeakDivision = gold3, RatedMatches = 40 })
		local out, notes = SaveSchema.migrate(save)
		H.expect(notes[1] == "migrated 1 -> 2", table.concat(notes, "; "))
		local starts, widths = newLadder(Config)
		H.expect(out.RankXp == starts[gold3] + widths[gold3] // 2, "halfway on the new ladder")
		-- Bronze 1,250 + Silver 1,750 + Gold I and II 1,600 = 4,600; Gold is 800 wide.
		H.expect(out.RankXp == 5000, "4,600 + 400, got " .. tostring(out.RankXp))
		local rank = Ranks.fromXp(out.RankXp, true)
		H.expect(rank.tier == "Gold" and rank.division == 3, "still shows Gold III")
		H.expect(rank.xpInDivision == 400, "halfway through it")
		H.expect(out.PeakDivision == gold3 and out.RatedMatches == 40, "peak and count kept")
	end,

	["migration 1 -> 2 keeps every division, at its start and its end"] = function()
		local Config, SaveSchema = setup()
		local Ranks = H.require("Progression.Ranks")
		local starts, widths = newLadder(Config)
		local count = SaveSchema.divisionCount()
		for index = 1, count do
			for _, into in { 0, 1, 250, 999 } do
				local oldXp = (index - 1) * 1000 + into
				local out = SaveSchema.migrate(v1Save({ RankXp = oldXp, RatedMatches = 1 }))
				local expected = if index < count
					then starts[index] + (into * widths[index]) // 1000
					else starts[index] + into
				H.expect(
					out.RankXp == expected,
					("old %d: expected %d, got %d"):format(oldXp, expected, out.RankXp)
				)
				H.expect(
					Ranks.fromXp(out.RankXp, true).index == index,
					("old %d left division %d"):format(oldXp, index)
				)
			end
		end
	end,

	["migration 1 -> 2 keeps Reyes XP past the Reyes start"] = function()
		local Config, SaveSchema = setup()
		local starts = newLadder(Config)
		local reyes = SaveSchema.divisionCount()
		H.expect(starts[reyes] == 2352500, "Reyes starts at 2,352,500")
		local out = SaveSchema.migrate(
			v1Save({ RankXp = 45000 + 1234, PeakDivision = reyes, RatedMatches = 900 })
		)
		H.expect(out.RankXp == 2352500 + 1234, "XP past the start kept")
		-- Far past it: the cap still holds.
		local huge = SaveSchema.migrate(
			v1Save({ RankXp = Config.Save.RankXpCap, PeakDivision = reyes, RatedMatches = 9 })
		)
		H.expect(huge.RankXp == Config.Save.RankXpCap, "clamped to the XP cap")
	end,

	["migration 1 -> 2 leaves an unranked save's XP alone"] = function()
		local _, SaveSchema = setup()
		local out = SaveSchema.migrate(v1Save({ RankXp = 12500, RatedMatches = 0 }))
		H.expect(out.RankXp == 12500, "unrated: XP as it was")
		H.expect(next(out.Inventory.Cases) == nil, "never ranked: no rank rewards")
		H.expect(next(out.Inventory.Cues) == nil, "no cues")
	end,

	["migration 1 -> 2 gives a Diamond I peak its tier rewards once"] = function()
		local Config, SaveSchema = setup()
		local diamond1 = indexOf(Config, "Diamond", 1)
		local save = v1Save({
			RankXp = (diamond1 - 1) * 1000 + 10,
			PeakDivision = diamond1,
			RatedMatches = 60,
			Money = 7777,
		})
		local out = SaveSchema.migrate(save)
		H.expect(out.Money == 7777, "no money: it was paid under version 1")
		-- The cases of Bronze to Diamond, summed from Config.
		local expected: { [string]: number } = {}
		local tiers = { "Bronze", "Silver", "Gold", "Platinum", "Diamond" }
		for _, tier in tiers do
			for caseId, n in Config.Ranks.Rewards.Tier[tier].Cases do
				expected[caseId] = (expected[caseId] or 0) + n
			end
		end
		H.expect(size(out.Inventory.Cases) == size(expected), "the same case types")
		for caseId, n in expected do
			H.expect(
				out.Inventory.Cases[caseId] == n,
				("%s: %s, expected %d"):format(caseId, tostring(out.Inventory.Cases[caseId]), n)
			)
		end
		-- ECONOMY 4.8: 2 Standard; 1 + 2 Rare; 1 + 2 Epic.
		local c = out.Inventory.Cases
		H.expect(c.Standard == 2 and c.Rare == 3 and c.Epic == 3, "the ECONOMY 4.8 cases")
		H.expect(c.Legendary == nil, "no Expert cases yet")
		H.expect(size(out.Inventory.Cues) == 5, "five tier cues")
		for _, tier in tiers do
			local cue = Config.Ranks.Rewards.Tier[tier].Cue
			H.expect(out.Inventory.Cues[cue] == 1, cue .. " given once")
			H.expect(out.Index.Seen[cue] == true and out.Inventory.New[cue] == true, cue)
		end
		H.expect(out.Inventory.Cues.ExpertCue == nil, "not the next tier's cue")
		-- Once: a second migrate is a no-op, and the save is already clean.
		local cases = table.clone(out.Inventory.Cases)
		local again, notes = SaveSchema.migrate(out)
		H.expect(#notes == 0 and again.Inventory.Cases.Rare == cases.Rare, "not given twice")
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "clean: " .. table.concat(fixes, "; "))
	end,

	["migration 1 -> 2 rewards follow the peak"] = function()
		local Config, SaveSchema = setup()
		local tiers = Config.Ranks.Tiers
		for _, case in { { 0, 0 }, { 1, 1 }, { 5, 1 }, { 6, 2 }, { 20, 4 }, { 21, 5 }, { 46, 10 } } do
			local peak, tierCount = case[1], case[2]
			local out = SaveSchema.migrate(v1Save({ PeakDivision = peak, RatedMatches = 1 }))
			H.expect(
				size(out.Inventory.Cues) == tierCount,
				("peak %d: %d tier cues, got %d"):format(peak, tierCount, size(out.Inventory.Cues))
			)
			for order, tier in tiers do
				local cue = Config.Ranks.Rewards.Tier[tier].Cue
				H.expect((out.Inventory.Cues[cue] ~= nil) == (order <= tierCount), cue)
			end
		end
		-- The top: every tier's cases, Legendary summed from Expert to Reyes.
		local top = SaveSchema.migrate(v1Save({ PeakDivision = 46, RatedMatches = 1 }))
		local legendary = 0
		for _, tier in tiers do
			legendary += Config.Ranks.Rewards.Tier[tier].Cases.Legendary or 0
		end
		H.expect(top.Inventory.Cases.Legendary == legendary, "every Legendary Case")
		H.expect(legendary == 2 + 3 + 5 + 10 + 25, "ECONOMY 4.8's Legendary Cases")
	end,

	["migration 1 -> 2 turns the cue array into counts"] = function()
		local _, SaveSchema = setup()
		local long = string.rep("z", 65)
		local save = v1Save({
			Inventory = {
				Cues = { "Oak", "Maple", "Oak", "default", "Classic", 5, "", long, "GoldCue" },
			},
			Equipped = { Cue = "default" },
		})
		local out = SaveSchema.migrate(save)
		local cues = out.Inventory.Cues
		H.expect(cues.Oak == 2 and cues.Maple == 1, "duplicates count up; unknown ids kept")
		H.expect(cues.GoldCue == 1, "a known cue kept")
		H.expect(cues.default == nil and cues.Classic == nil, "the default cue is never counted")
		H.expect(cues[long] == nil and cues[""] == nil, "not ids")
		H.expect(size(cues) == 3, "three ids")
		H.expect(out.Index.Seen.Oak and out.Index.Seen.Maple and out.Index.Seen.GoldCue, "seen")
		H.expect(next(out.Inventory.New) == nil, "cues already owned are not NEW")
		H.expect(out.Equipped.Cue == "Classic", '"default" -> Classic')
	end,

	["migration 1 -> 2 fixes the equipped cue and fills the new fields"] = function()
		local _, SaveSchema = setup()
		local unknown = SaveSchema.migrate(v1Save({ Equipped = { Cue = "Nope" } }))
		H.expect(unknown.Equipped.Cue == "Classic", "unknown -> Classic")
		local known = SaveSchema.migrate(
			v1Save({ Equipped = { Cue = "GoldCue" }, PeakDivision = 11, RatedMatches = 3 })
		)
		H.expect(known.Equipped.Cue == "GoldCue", "a known cue stays equipped")

		local stats = SaveSchema.template().Stats
		stats.Matches = 30
		stats.Wins = 10
		stats.PcWins = 2
		local out =
			SaveSchema.migrate(v1Save({ Stats = stats, Daily = { Day = 19000, SoloMoney = 120 } }))
		H.expect(out.Progress.RealMatches == 30 and out.Progress.Wins == 12, "from Stats")
		local d = out.Daily
		H.expect(d.Day == 19000 and d.SoloMoney == 120, "the day and its solo money kept")
		H.expect(d.PcMoney == 0 and d.ShortMoney == 0 and d.Wins == 0, "the rest fresh")
		H.expect(d.FirstWinUsed == false and d.PlaySeconds == 0, "the rest fresh")
		H.expect(next(d.Opponents) == nil and next(d.PlaytimeClaimed) == nil, "empty maps")
		H.expect(out.Shop.FirstJoin == 0, "FirstJoin waits for PlayerData's clock")
		H.expect(out.Login.LastDay == 0 and next(out.Codes) == nil, "fresh")
		H.expect(next(out.Titles) == nil and next(out.Index.Rows) == nil, "fresh")
		-- Complete without Reconcile, and clean.
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "clean: " .. table.concat(fixes, "; "))
	end,

	["migration 1 -> 2 never errors on a broken version-1 save"] = function()
		local Config, SaveSchema = setup()
		local weird: { any } = { NAN, INF, -INF, -1, 1.5, "100", true, 1e300, {} }
		local v1Fields = {
			"RankXp",
			"PeakDivision",
			"RatedMatches",
			"Stats",
			"Daily",
			"Inventory",
			"Equipped",
		}
		for _, field in v1Fields do
			for _, value in weird do
				local save = v1Save({ RatedMatches = 3, PeakDivision = 30, RankXp = 30500 })
				save[field] = value
				local out, notes = SaveSchema.migrate(save)
				H.expect(
					notes[1] == "migrated 1 -> 2",
					("%s = %s: %s"):format(field, tostring(value), table.concat(notes, "; "))
				)
				reconcile(out, SaveSchema.template())
				assertClean(Config, SaveSchema, (SaveSchema.validate(out)))
			end
		end
		-- Broken insides.
		local cues: any = { "Oak" }
		cues[3] = "Maple"
		cues.x = "Birch"
		cues[2.5] = "Pine"
		local cases: any = { Rare = "lots", Epic = NAN }
		local save = v1Save({
			RatedMatches = 1,
			PeakDivision = 11,
			Inventory = { Cues = cues, Cases = cases, New = 5 },
			Index = "x",
			Daily = { Day = NAN, SoloMoney = "x", Opponents = 3 },
		})
		local out, notes = SaveSchema.migrate(save)
		H.expect(notes[1] == "migrated 1 -> 2", table.concat(notes, "; "))
		H.expect(out.Inventory.Cues.Oak == 1 and out.Inventory.Cues.Maple == 1, "array part")
		H.expect(out.Inventory.Cues.Birch == nil and out.Inventory.Cues.Pine == nil, "not")
		H.expect(out.Inventory.Cases.Rare == 3, "a broken count becomes the reward alone")
		H.expect(out.Inventory.New.GoldCue == true, "New rebuilt")
		assertClean(Config, SaveSchema, (SaveSchema.validate(out)))
	end,

	["validate repairs broken numbers"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Money = NAN
		save.RankXp = INF
		save.PeakDivision = -INF
		save.RatedMatches = -4
		save.Stats.Wins = 1.5
		save.Stats.Losses = "100"
		save.Stats.Matches = 1e300
		save.Stats.Draws = {}
		save.Stats.NiceShots = nil
		save.Daily.Day = 19000.7
		save.Daily.SoloMoney = 1e13
		local out, fixes = SaveSchema.validate(save)
		H.expect(out == save, "repaired in place")
		H.expect(out.Money == 0, "NaN money to 0 (never to the cap)")
		H.expect(out.RankXp == 0, "infinite XP to 0 (never to the cap)")
		H.expect(out.PeakDivision == 0 and out.RatedMatches == 0, "negatives to 0")
		H.expect(out.Stats.Wins == 1, "fraction floored")
		H.expect(out.Stats.Losses == 0, "a string is not a number")
		H.expect(out.Stats.Matches == Config.Save.StatCap, "clamped to the cap")
		H.expect(out.Stats.Draws == 0 and out.Stats.NiceShots == 0, "missing and table to 0")
		H.expect(out.Daily.Day == 19000, "day floored")
		H.expect(out.Daily.SoloMoney == Config.Save.MoneyCap, "solo money clamped")
		H.expect(
			#fixes == 11,
			("one fix per bad field, got %d: %s"):format(#fixes, table.concat(fixes, "; "))
		)
		assertClean(Config, SaveSchema, out)
		local _, again = SaveSchema.validate(out)
		H.expect(#again == 0, "a repaired save is clean")
	end,

	["validate repairs the new number fields"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Progress.RealMatches = -3
		save.Progress.Wins = NAN
		save.Daily.PcMoney = INF
		save.Daily.ShortMoney = "50"
		save.Daily.Wins = 2.5
		save.Daily.PlaySeconds = 90000
		save.Login.LastDay = -1
		save.Login.StreakDay = 8
		save.Login.Week = 5
		save.Shop.FirstJoin = 1e300
		local out, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 10, ("one fix each, got: %s"):format(table.concat(fixes, "; ")))
		H.expect(out.Progress.RealMatches == 0 and out.Progress.Wins == 0, "progress")
		H.expect(out.Daily.PcMoney == 0 and out.Daily.ShortMoney == 0, "never a fortune")
		H.expect(out.Daily.Wins == 2 and out.Daily.PlaySeconds == 86400, "floored, one day")
		H.expect(out.Login.LastDay == 0, "login day")
		H.expect(out.Login.StreakDay == #Config.Daily.Streak, "streak day 0..7")
		H.expect(out.Login.Week == Config.Daily.WeeksForBonus, "week 0..4")
		H.expect(out.Shop.FirstJoin == Config.Save.UnixTimeCap, "a time in range")
		assertClean(Config, SaveSchema, out)
	end,

	["validate makes flags true or false"] = function()
		local _, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Daily.FirstWinUsed = 1
		save.Shop.VipOffer = "yes"
		save.Shop.VipCueGiven = nil
		save.Shop.StarterBought = true
		save.Shop.FirstPackBought = 0
		local out, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 4, table.concat(fixes, "; "))
		H.expect(out.Daily.FirstWinUsed == false and out.Shop.VipOffer == false, "never grants")
		H.expect(out.Shop.VipCueGiven == false and out.Shop.FirstPackBought == false, "false")
		H.expect(out.Shop.StarterBought == true, "a real true is kept")
	end,

	["validate clamps to every cap"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Money = Config.Save.MoneyCap + 1
		save.RankXp = Config.Save.RankXpCap * 10
		save.PeakDivision = SaveSchema.divisionCount() + 1
		save.RatedMatches = Config.Save.StatCap + 5
		local out = SaveSchema.validate(save)
		H.expect(out.Money == Config.Save.MoneyCap, "money cap")
		H.expect(out.RankXp == Config.Save.RankXpCap, "rank XP cap")
		H.expect(out.PeakDivision == SaveSchema.divisionCount(), "top division")
		H.expect(out.RatedMatches == Config.Save.StatCap, "stat cap")
		-- Values at the caps are fine as they are.
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "the caps themselves are valid")
	end,

	["validate raises a best streak below the current one"] = function()
		local _, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Stats.WinStreak = 7
		save.Stats.BestWinStreak = 3
		local out, fixes = SaveSchema.validate(save)
		H.expect(out.Stats.BestWinStreak == 7 and out.Stats.WinStreak == 7, "best raised")
		H.expect(#fixes == 1, "one fix")
	end,

	["validate rebuilds missing or wrong-typed sub-tables"] = function()
		local Config, SaveSchema = setup()
		local save = {
			Version = 2,
			Money = 10,
			Stats = 5,
			Daily = "today",
			Inventory = true,
			Equipped = nil,
			Settings = 3,
			Flags = "x",
			Shop = { Purchases = "r1", Limited = 4 },
			Index = { Seen = false },
		}
		local out, fixes = SaveSchema.validate(save)
		H.expect(out == save and out.Money == 10, "kept what was good")
		H.expect(out.Stats.Wins == 0 and out.Daily.Day == 0, "rebuilt from the template")
		H.expect(next(out.Inventory.Cues) == nil and out.Equipped.Cue == "Classic", "rebuilt")
		H.expect(#out.Shop.Purchases == 0 and next(out.Shop.Limited) == nil, "inner rebuilt")
		H.expect(next(out.Index.Seen) == nil and next(out.Index.Rows) == nil, "inner rebuilt")
		H.expect(#fixes >= 12, "each rebuild reported")
		assertClean(Config, SaveSchema, out)
	end,

	["validate repairs cue and case counts"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		local long = string.rep("q", 65)
		local cues: any = {
			Oak = 2,
			Negative = -1,
			Zero = 0,
			Half = 0.5,
			Fraction = 2.7,
			Huge = 1e300,
			Nan = NAN,
			Inf = INF,
			Text = "5",
			Flag = true,
			Table = {},
			Classic = 3,
			[""] = 1,
			[long] = 1,
		}
		cues[5] = 1
		cues[true] = 1
		save.Inventory.Cues = cues
		save.Inventory.Cases = { Standard = 3, Rare = -2, Epic = Config.Save.ItemCountCap + 1 }
		local out, fixes = SaveSchema.validate(save)
		local c = out.Inventory.Cues
		H.expect(c.Oak == 2 and c.Fraction == 2, "good kept, fraction floored")
		H.expect(c.Huge == Config.Save.ItemCountCap, "clamped, never lost")
		for _, gone in { "Negative", "Zero", "Half", "Nan", "Inf", "Text", "Flag", "Table" } do
			H.expect(c[gone] == nil, gone .. " dropped")
		end
		H.expect(c.Classic == nil and c[""] == nil and c[long] == nil, "Classic and bad keys")
		H.expect(size(c) == 3, "three left")
		local cases = out.Inventory.Cases
		H.expect(cases.Standard == 3 and cases.Rare == nil, "cases")
		H.expect(cases.Epic == Config.Save.ItemCountCap, "case count clamped")
		assertClean(Config, SaveSchema, out)
		local _, again = SaveSchema.validate(out)
		H.expect(#again == 0, "clean after one pass")
		H.expect(#fixes >= 6, table.concat(fixes, "; "))
	end,

	["validate repairs copy numbers and sets"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Inventory.Unique = { BetaCue = 412, FoundersCue = 0, Classic = 1, X = 1.5 }
		save.Shop.Limited = { BetaCue = 412, FoundersCue = "7", Y = 1e300 }
		save.Inventory.New = { A = true, B = false, C = 1, D = "true" }
		save.Index.Seen = { A = true, B = {}, C = NAN }
		save.Index.Rows = { Common = true, Rare = 1 }
		save.Titles = { Collector = true, Bad = false }
		save.Codes = { WELCOME = true, ["8BALL"] = "yes" }
		save.Daily.PlaytimeClaimed = { ["1"] = true, ["2"] = 0 }
		local out = SaveSchema.validate(save)
		local u = out.Inventory.Unique
		H.expect(u.BetaCue == 412 and u.X == 1 and u.FoundersCue == nil, "copy numbers")
		H.expect(u.Classic == nil, "Classic never numbered")
		local l = out.Shop.Limited
		H.expect(l.BetaCue == 412 and l.FoundersCue == nil, "Limited bought")
		H.expect(l.Y == Config.Save.CopyNumberCap, "clamped")
		H.expect(size(out.Inventory.New) == 1 and out.Inventory.New.A, "true only")
		H.expect(size(out.Index.Seen) == 1 and out.Index.Seen.A, "true only")
		H.expect(size(out.Index.Rows) == 1 and out.Index.Rows.Common, "true only")
		H.expect(size(out.Titles) == 1 and out.Titles.Collector, "true only")
		H.expect(size(out.Codes) == 1 and out.Codes.WELCOME, "true only")
		H.expect(size(out.Daily.PlaytimeClaimed) == 1, "true only")
		assertClean(Config, SaveSchema, out)
	end,

	["validate caps every map, keeping the smallest keys"] = function()
		local Config, SaveSchema = setup()
		local S = Config.Save
		local save = SaveSchema.template()
		local function fill(n: number, value: any): any
			local t = {}
			for i = 1, n do
				t[("id%05d"):format(i)] = value
			end
			return t
		end
		save.Inventory.Cues = fill(S.MaxCueEntries + 7, 1)
		save.Inventory.Unique = fill(S.MaxCueEntries + 1, 3)
		save.Inventory.Cases = fill(S.MaxCaseEntries + 5, 2)
		save.Inventory.New = fill(S.MaxCueEntries * 3, true)
		save.Index.Seen = fill(S.MaxCueEntries + 1, true)
		save.Index.Rows = fill(S.MaxSmallEntries + 1, true)
		save.Titles = fill(S.MaxTitleEntries + 1, true)
		save.Codes = fill(S.MaxCodeEntries + 1, true)
		save.Daily.PlaytimeClaimed = fill(S.MaxSmallEntries + 1, true)
		save.Shop.Limited = fill(S.MaxCueEntries + 1, 9)
		local out, fixes = SaveSchema.validate(save)
		H.expect(size(out.Inventory.Cues) == S.MaxCueEntries, "cues capped")
		H.expect(out.Inventory.Cues.id00001 and out.Inventory.Cues.id00500, "smallest kept")
		H.expect(out.Inventory.Cues.id00501 == nil, "largest dropped")
		H.expect(size(out.Inventory.Cases) == S.MaxCaseEntries, "cases capped")
		H.expect(size(out.Inventory.New) == S.MaxCueEntries, "a huge map capped")
		H.expect(#fixes == 10, "one note per map: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["validate repairs the same-opponent table"] = function()
		local Config, SaveSchema = setup()
		local max = Config.Economy.SameOpponentMaxEntries
		local save = SaveSchema.template()
		local opponents: any = {}
		for i = 1, max + 10 do
			opponents[tostring(5000 + i)] = { Matches = i, Cases = 0 }
		end
		opponents["1"] = { Matches = -3, Cases = NAN, Extra = { deep = 1 } }
		opponents["2"] = "x"
		opponents["3"] = { Matches = 2.5 }
		opponents[4] = { Matches = 1, Cases = 0 }
		save.Daily.Opponents = opponents
		local out, fixes = SaveSchema.validate(save)
		local o = out.Daily.Opponents
		H.expect(size(o) == max, "capped at SameOpponentMaxEntries")
		H.expect(o["1"].Matches == 0 and o["1"].Cases == 0 and o["1"].Extra == nil, "rebuilt")
		H.expect(o["2"] == nil and o["3"].Matches == 2 and o["3"].Cases == 0, "repaired")
		-- Sorted as strings: "1", "3", "5001" ... are kept, the biggest ids go.
		H.expect(o["5001"] ~= nil and o[tostring(5000 + max - 2)] ~= nil, "smallest keys kept")
		H.expect(o[tostring(5000 + max - 1)] == nil, "the rest dropped")
		-- A non-string key, a bad entry, two repaired, the cap.
		H.expect(#fixes == 4, table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["validate keeps the last purchases as a gapless array of strings"] = function()
		local Config, SaveSchema = setup()
		local cap = Config.Shop.RecentPurchases
		local save = SaveSchema.template()
		local list: any = {}
		for i = 1, cap + 20 do
			list[i] = "receipt-" .. i
		end
		list[3] = 42
		list[cap + 30] = "late" -- after a hole
		list.x = "map key"
		list[5] = string.rep("r", Config.Save.MaxPurchaseIdLength + 1)
		save.Shop.Purchases = list
		local out, fixes = SaveSchema.validate(save)
		local p = out.Shop.Purchases
		H.expect(isGaplessArray(p) and #p == cap, "the last RecentPurchases")
		H.expect(p[#p] == "late", "newest last")
		H.expect(p[#p - 1] == "receipt-" .. (cap + 20), "in order")
		H.expect(p[1] == "receipt-" .. (cap + 20 - cap + 2), "the oldest dropped")
		H.expect(#fixes == 4, "keys, gaps, non-strings, trimmed: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["validate equips only an owned catalog cue"] = function()
		local _, SaveSchema = setup()
		local function equip(cue: any, setup: ((any) -> ())?): (string, number)
			local save = SaveSchema.template()
			save.Equipped.Cue = cue
			if setup then
				setup(save)
			end
			local out, fixes = SaveSchema.validate(save)
			return out.Equipped.Cue, #fixes
		end
		for _, bad in { nil :: any, "", 5, {}, string.rep("c", 65), true, "default", "Nope" } do
			local cue, n = equip(bad)
			H.expect(cue == "Classic" and n == 1, "reset " .. tostring(bad))
		end
		local notOwned, n1 = equip("GoldCue")
		H.expect(notOwned == "Classic" and n1 == 1, "a cue you do not own")
		local owned, n2 = equip("GoldCue", function(save: any)
			save.Inventory.Cues.GoldCue = 1
		end)
		H.expect(owned == "GoldCue" and n2 == 0, "an owned cue stays")
		local unique, n3 = equip("BetaCue", function(save: any)
			save.Inventory.Unique.BetaCue = 412
		end)
		H.expect(unique == "BetaCue" and n3 == 0, "a numbered cue stays")
		local sold, n4 = equip("GoldCue", function(save: any)
			save.Inventory.Cues.GoldCue = 0
		end)
		H.expect(sold == "Classic" and n4 == 2, "a count repaired away unequips")
		local classic, n5 = equip("Classic")
		H.expect(classic == "Classic" and n5 == 0, "Classic is always owned")
	end,

	["validate drops keys that are not strings"] = function()
		local Config, SaveSchema = setup()
		local save: any = SaveSchema.template()
		save[1] = "array part"
		save[true] = 1
		save[{}] = 2
		save.Settings[1] = "x"
		save.Settings.Volume = 0.5
		save.Settings.Bad = NAN
		save.Flags[2.5] = true
		save.Flags.Seen = true
		save.Flags.Huge = -INF
		save.Stats[3] = 3
		save.Equipped[1] = "x"
		local out, fixes = SaveSchema.validate(save)
		H.expect(out.Settings.Volume == 0.5 and out.Flags.Seen == true, "string keys kept")
		H.expect(out.Settings.Bad == nil and out.Flags.Huge == nil, "non-finite values dropped")
		H.expect(#fixes == 7, "save, Stats, Equipped, Settings, Flags keys + 2 non-finite")
		assertClean(Config, SaveSchema, out)
	end,

	["validate leaves unknown string fields alone"] = function()
		local _, SaveSchema = setup()
		local save = SaveSchema.template()
		save.FutureField = { deep = { 1, 2 } }
		save.Stats.FutureCounter = 5
		save.Shop.FutureFlag = true
		local out, fixes = SaveSchema.validate(save)
		H.expect(out.FutureField.deep[2] == 2 and out.Stats.FutureCounter == 5, "kept")
		H.expect(out.Shop.FutureFlag == true, "kept")
		H.expect(#fixes == 0, "not reported")
	end,

	["validate reports the same fixes whatever order a map was built in"] = function()
		local _, SaveSchema = setup()
		local ids = {}
		for i = 1, 700 do
			table.insert(ids, ("c%04d"):format((i * 379) % 1000))
		end
		local function build(reverse: boolean): any
			local save = SaveSchema.template()
			local from, to, step = 1, #ids, 1
			if reverse then
				from, to, step = #ids, 1, -1
			end
			for i = from, to, step do
				local id = ids[i]
				save.Inventory.Cues[id] = if i % 7 == 0 then -1 else i % 5 + 0.5
				save.Daily.Opponents[id] = if i % 3 == 0 then "bad" else { Matches = i }
			end
			return save
		end
		local a, fixesA = SaveSchema.validate(build(false))
		local b, fixesB = SaveSchema.validate(build(true))
		H.expect(table.concat(fixesA, "\n") == table.concat(fixesB, "\n"), "same fixes")
		for id in a.Inventory.Cues do
			H.expect(b.Inventory.Cues[id] == a.Inventory.Cues[id], "same cues kept")
		end
		for id in a.Daily.Opponents do
			H.expect(b.Daily.Opponents[id] ~= nil, "same opponents kept")
		end
		H.expect(size(a.Inventory.Cues) == size(b.Inventory.Cues), "same size")
	end,

	["validate survives a non-table in every field"] = function()
		local Config, SaveSchema = setup()
		local weird: { any } = { NAN, INF, -INF, -1, 1.5, "100", true, 1e300 }
		for _, field in FIELDS do
			for _, value in weird do
				local save = SaveSchema.template()
				save[field] = value
				local ok, out = pcall(SaveSchema.validate, save)
				H.expect(ok, ("%s = %s: %s"):format(field, tostring(value), tostring(out)))
				assertClean(Config, SaveSchema, out)
			end
			-- And a table where a number goes.
			local save = SaveSchema.template()
			local mixed: any = { 1 }
			mixed.x = 2
			save[field] = mixed
			local ok, out = pcall(SaveSchema.validate, save)
			H.expect(ok, field .. " as a mixed table")
			assertClean(Config, SaveSchema, out)
		end
		-- Every sub-field too.
		for _, parent in SUB_TABLES do
			for _, field in SUB_FIELDS[parent] do
				for _, value in weird do
					local save = SaveSchema.template()
					save[parent][field] = value
					local ok, out = pcall(SaveSchema.validate, save)
					H.expect(
						ok,
						("%s.%s = %s: %s"):format(parent, field, tostring(value), tostring(out))
					)
					assertClean(Config, SaveSchema, out)
				end
			end
		end
		for _, bad in { nil :: any, 1, "save", true } do
			local out, fixes = SaveSchema.validate(bad)
			H.expect(type(out) == "table" and #fixes == 1, "non-table save becomes a template")
			assertClean(Config, SaveSchema, out)
		end
	end,

	["migration 3 -> 4 removes the retired placeholder cues and keeps the rest"] = function()
		local _, SaveSchema = setup()
		local save = SaveSchema.template()
		save.Version = 3
		save.Money = 500
		save.Inventory.Cues.ChalkDust = 3
		save.Inventory.Cues.Eclipse = 1
		save.Inventory.Cues.GoldCue = 1
		save.Inventory.Cues.KitsuneCue = 2
		save.Inventory.New.Nebula = true
		save.Inventory.New.KitsuneCue = true
		save.Index.Seen.GoldenBreak = true
		save.Index.Seen.GoldCue = true
		save.Equipped.Cue = "Eclipse"
		local out, notes = SaveSchema.migrate(save)
		H.expect(#notes == 1 and notes[1] == "migrated 3 -> 4", table.concat(notes, "; "))
		H.expect(out.Version == 4 and out.Money == 500, "version 4, money kept")
		local cues = out.Inventory.Cues
		H.expect(cues.ChalkDust == nil and cues.Eclipse == nil, "retired cues removed")
		H.expect(cues.GoldCue == 1 and cues.KitsuneCue == 2, "current cues kept")
		H.expect(out.Inventory.New.Nebula == nil and out.Inventory.New.KitsuneCue, "NEW tags")
		H.expect(out.Index.Seen.GoldenBreak == nil and out.Index.Seen.GoldCue, "Index.Seen")
		H.expect(out.Equipped.Cue == "Classic", "a retired equipped cue becomes Classic")
		-- A broken save (no tables where they belong) never errors.
		local broken = { Version = 3, Inventory = "x", Index = 4, Equipped = false }
		local ok = pcall(SaveSchema.migrate, broken)
		H.expect(ok, "broken save")
	end,

	["migration 2 -> 3 adds the ults: Magnet in slot 1 and the starter spins"] = function()
		local Config, SaveSchema = setup()
		local save = v2Save(SaveSchema)
		save.Money = 777
		save.RankXp = 4321
		save.Inventory.Cues.GoldCue = 2
		save.Equipped.Cue = "GoldCue"
		save.Codes.WELCOME = true
		save.Settings.Volume = 0.5
		local before = SaveSchema.template()
		local out, notes = SaveSchema.migrate(save)
		H.expect(
			#notes == 2 and notes[1] == "migrated 2 -> 3" and notes[2] == "migrated 3 -> 4",
			table.concat(notes, "; ")
		)
		H.expect(out == save and out.Version == 4, "migrated in place to version 4")
		local u = out.Ults
		H.expect(u.Slots[1] == "Magnet" and u.Slots[2] == "" and u.Slots[3] == "", "slots")
		H.expect(u.Spins == Config.Ults.Earn.Starter and u.Spins == 3, "the 3 starter spins")
		H.expect(u.Selected == 1 and u.LuckySpins == 0 and u.Pity == 0, "fresh")
		H.expect(u.QueueUlts == true and u.FreeSpinDay == 0 and u.SpinsDone == 0, "fresh")
		-- Everything else untouched.
		H.expect(out.Money == 777 and out.RankXp == 4321, "numbers kept")
		H.expect(out.Inventory.Cues.GoldCue == 2 and out.Equipped.Cue == "GoldCue", "items kept")
		H.expect(out.Codes.WELCOME == true and out.Settings.Volume == 0.5, "maps kept")
		for key in before do
			H.expect(out[key] ~= nil, key .. " present")
		end
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "clean without Reconcile: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
	end,

	["migration 2 -> 3 replaces anything a version-2 save held under Ults"] = function()
		local Config, SaveSchema = setup()
		for _, junk in { 5, "x", { Slots = { "BlackHole" }, Spins = 99999 } :: any } do
			local save = v2Save(SaveSchema)
			save.Ults = junk
			local out = SaveSchema.migrate(save)
			H.expect(out.Ults.Slots[1] == "Magnet" and out.Ults.Spins == 3, "fresh ults")
			assertClean(Config, SaveSchema, out)
		end
	end,

	["a fresh template round-trips through migrate, Reconcile and validate"] = function()
		local Config, SaveSchema = setup()
		local t = SaveSchema.template()
		local out, notes = SaveSchema.migrate(t)
		H.expect(out == t and #notes == 0, "a current save needs no migration")
		reconcile(out, SaveSchema.template())
		local _, fixes = SaveSchema.validate(out)
		H.expect(#fixes == 0, "clean: " .. table.concat(fixes, "; "))
		assertClean(Config, SaveSchema, out)
		local fresh = SaveSchema.template()
		for i = 1, 3 do
			H.expect(out.Ults.Slots[i] == fresh.Ults.Slots[i], "slot " .. i)
			H.expect(out.Ults.Locked[i] == fresh.Ults.Locked[i], "lock " .. i)
		end
		-- Reconcile fills a v3 save that lost its Ults (or a field of it) from the template.
		local lost = SaveSchema.template()
		lost.Ults = nil
		reconcile(lost, SaveSchema.template())
		H.expect(lost.Ults.Slots[1] == "Magnet" and lost.Ults.Spins == 3, "refilled")
		local _, again = SaveSchema.validate(lost)
		H.expect(#again == 0, "clean after Reconcile")
	end,

	["validate repairs damaged ults"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		local slots: any = { "Ghost", "NotAnUlt", 5 }
		slots[4] = "BlackHole"
		slots.x = "Magnet"
		save.Ults.Slots = slots
		save.Ults.Locked = { true, "yes" } -- too short, and a non-boolean
		save.Ults.Selected = 4
		save.Ults.Spins = -5
		save.Ults.LuckySpins = Config.Ults.Earn.MaxSpins + 10
		save.Ults.Pity = Config.Ults.Roll.PityAt
		save.Ults.FreeSpinDay = 20000.5
		save.Ults.SpinsDone = NAN
		save.Ults.QueueUlts = "on"
		local out, fixes = SaveSchema.validate(save)
		local u = out.Ults
		H.expect(u.Slots[1] == "Ghost" and u.Slots[2] == "" and u.Slots[3] == "", "slots")
		H.expect(#u.Slots == 3 and u.Slots.x == nil and u.Slots[4] == nil, "exactly 3")
		H.expect(u.Locked[1] == true and u.Locked[2] == false and u.Locked[3] == false, "locks")
		H.expect(#u.Locked == 3, "3 locks")
		H.expect(u.Selected == 1, "a bad selection goes back to slot 1")
		H.expect(u.Spins == 0, "no negative spins")
		H.expect(u.LuckySpins == Config.Ults.Earn.MaxSpins, "clamped to the cap")
		H.expect(u.Pity == Config.Ults.Roll.PityAt - 1, "pity below PityAt")
		H.expect(u.FreeSpinDay == 20000 and u.SpinsDone == 0, "whole numbers")
		H.expect(u.QueueUlts == true, "a broken choice goes back to the default (on)")
		-- Slots: extra keys, repaired entries; Locked: repaired; Selected; 6 numbers/flags.
		H.expect(#fixes == 10, ("%d fixes: %s"):format(#fixes, table.concat(fixes, "; ")))
		assertClean(Config, SaveSchema, out)
		local _, again = SaveSchema.validate(out)
		H.expect(#again == 0, "a repaired save is clean")

		-- A missing or wrong-typed Ults table is rebuilt as a new player's.
		for _, bad in { 5, "x", true } do
			local broken = SaveSchema.template()
			broken.Ults = bad
			local fixed, notes = SaveSchema.validate(broken)
			H.expect(#notes == 1 and fixed.Ults.Slots[1] == "Magnet", "rebuilt")
			assertClean(Config, SaveSchema, fixed)
		end
		-- Wrong-typed arrays inside it are rebuilt too; valid ids in every slot are kept.
		local arrays = SaveSchema.template()
		arrays.Ults.Slots = "Magnet"
		arrays.Ults.Locked = 1
		arrays.Ults.Selected = "2"
		local fixedArrays = SaveSchema.validate(arrays)
		H.expect(fixedArrays.Ults.Slots[1] == "Magnet" and #fixedArrays.Ults.Locked == 3, "")
		H.expect(fixedArrays.Ults.Selected == 1, "a string is not a slot")
		local full = SaveSchema.template()
		full.Ults.Slots = { "BlackHole", "Magnet", "GuangdongTiger" }
		full.Ults.Selected = 3
		local _, none = SaveSchema.validate(full)
		H.expect(#none == 0, "every catalog id is kept, built or not")
	end,

	["fuzz: validate never errors and always leaves a clean save"] = function()
		local Config, SaveSchema = setup()
		local rng = newRng(20260928)
		for round = 1, 400 do
			local save: any
			if rng(10) == 1 then
				save = randomValue(rng, 0)
			else
				-- Start from a template and break a few fields, sub-fields and keys.
				save = SaveSchema.template()
				for _ = 1, rng(6) do
					save[FIELDS[rng(#FIELDS)]] = randomValue(rng, 1)
				end
				for _ = 1, rng(6) - 1 do
					local parent = SUB_TABLES[rng(#SUB_TABLES)]
					local sub = save[parent]
					if type(sub) == "table" then
						local keys = SUB_FIELDS[parent]
						sub[keys[rng(#keys)]] = randomValue(rng, 1)
					end
				end
				if rng(4) == 1 then
					save[rng(3)] = randomValue(rng, 2)
				end
			end
			local ok, out = pcall(SaveSchema.validate, save)
			H.expect(ok, ("round %d errored: %s"):format(round, tostring(out)))
			assertClean(Config, SaveSchema, out)
			local _, again = SaveSchema.validate(out)
			H.expect(
				#again == 0,
				("round %d: a second pass still fixed %s"):format(round, table.concat(again, "; "))
			)
		end
	end,

	["fuzz: migration 1 -> 2 never errors on a broken version-1 save"] = function()
		local Config, SaveSchema = setup()
		local rng = newRng(1)
		local v1Fields = { "RankXp", "PeakDivision", "RatedMatches", "Stats", "Daily", "Inventory" }
		for round = 1, 300 do
			local save = v1Save({ RatedMatches = rng(3) - 1, PeakDivision = rng(47) - 1 })
			for _ = 1, rng(4) do
				save[v1Fields[rng(#v1Fields)]] = randomValue(rng, 1)
			end
			if type(save.Inventory) == "table" and rng(2) == 1 then
				save.Inventory.Cues = randomValue(rng, 1)
			end
			local out, notes = SaveSchema.migrate(save)
			H.expect(
				out.Version == SaveSchema.Version,
				("round %d: %s"):format(round, table.concat(notes, "; "))
			)
			reconcile(out, SaveSchema.template())
			local ok, valid = pcall(SaveSchema.validate, out)
			H.expect(ok, ("round %d: validate errored"):format(round))
			assertClean(Config, SaveSchema, valid)
		end
	end,

	["a full save stays small"] = function()
		local Config, SaveSchema = setup()
		local Catalog = H.require("Progression.Catalog")
		local save = SaveSchema.template()
		save.Money = 123456789
		save.RankXp = 2352500
		save.PeakDivision = 46
		save.RatedMatches = 99999
		for _, key in STAT_KEYS do
			save.Stats[key] = 123456
		end
		save.Progress = { RealMatches = 99999, Wins = 55555 }
		local cueCount = 0
		for _, cue in Catalog.list() do
			if cue.Id ~= Catalog.Default then
				save.Inventory.Cues[cue.Id] = 99
				save.Inventory.New[cue.Id] = true
				save.Index.Seen[cue.Id] = true
				cueCount += 1
				if cue.Group == "Unique" then
					save.Inventory.Unique[cue.Id] = 999
					save.Shop.Limited[cue.Id] = 999
				end
			end
		end
		for _, caseId in Config.Cases.Order do
			save.Inventory.Cases[caseId] = 999
		end
		for _, rarity in Config.Cases.Rarities do
			save.Index.Rows[rarity] = true
			save.Titles[rarity .. "Collector"] = true
		end
		save.Equipped.Cue = "GoldCue"
		save.Daily = SaveSchema.freshDaily(20500)
		for i = 1, 50 do
			save.Daily.Opponents[tostring(1234567890 + i)] = { Matches = 99, Cases = 3 }
		end
		for i = 1, #Config.Daily.Playtime do
			save.Daily.PlaytimeClaimed[tostring(i)] = true
		end
		save.Daily.PlaySeconds = 86400
		save.Login = { LastDay = 20500, StreakDay = 7, Week = 4 }
		save.Shop.FirstJoin = 1790553600
		for i = 1, 50 do
			table.insert(save.Shop.Purchases, ("%08x-4b1c-4d2e-9f3a-%012d"):format(i, i))
		end
		for i = 1, 20 do
			save.Codes[("PROMOCODE%02d"):format(i)] = true
		end
		local _, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 0, "a full save is valid: " .. table.concat(fixes, "; "))
		local bytes = jsonLength(save)
		print(
			("    a full save (%d cues x99, cases x999, 50 opponents, 50 receipts, 20 codes): about %d bytes"):format(
				cueCount,
				bytes
			)
		)
		H.expect(bytes < 16 * 1024, ("%d bytes is over 16 KB"):format(bytes))
	end,
}
