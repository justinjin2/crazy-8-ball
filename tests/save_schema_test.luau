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

-- Everything a repaired save must satisfy.
local function assertClean(Config: any, SaveSchema: any, save: any)
	H.expect(type(save) == "table", "save must be a table")
	H.expect(onlyStringKeys(save), "top-level keys must be strings")
	H.expect(isInt(save.Version) and save.Version >= 0, "Version must be an integer >= 0")
	inRange(save.Money, Config.Save.MoneyCap, "Money")
	inRange(save.RankXp, Config.Save.RankXpCap, "RankXp")
	inRange(save.PeakDivision, SaveSchema.divisionCount(), "PeakDivision")
	inRange(save.RatedMatches, Config.Save.StatCap, "RatedMatches")
	for _, key in { "Stats", "Daily", "Inventory", "Equipped", "Settings", "Flags" } do
		H.expect(type(save[key]) == "table", key .. " must be a table")
		H.expect(onlyStringKeys(save[key]), key .. " keys must be strings")
	end
	for _, key in STAT_KEYS do
		inRange(save.Stats[key], Config.Save.StatCap, "Stats." .. key)
	end
	H.expect(save.Stats.BestWinStreak >= save.Stats.WinStreak, "best streak below current")
	inRange(save.Daily.Day, Config.Save.StatCap, "Daily.Day")
	inRange(save.Daily.SoloMoney, Config.Save.MoneyCap, "Daily.SoloMoney")
	H.expect(isGaplessArray(save.Inventory.Cues), "Inventory.Cues must be a gapless array")
	local cue = save.Equipped.Cue
	H.expect(type(cue) == "string" and #cue >= 1 and #cue <= 64, "Equipped.Cue must be an id")
	for _, map in { save.Settings, save.Flags } do
		for _, value in map do
			if type(value) == "number" then
				H.expect(value == value and math.abs(value) ~= INF, "settings must be finite")
			end
		end
	end
end

-- A tiny deterministic generator (Numerical Recipes LCG), so the fuzz is the same every run.
local function newRng(seed: number): (number) -> number
	local state = seed
	return function(n: number): number
		state = (state * 1664525 + 1013904223) % 4294967296
		return state % n + 1
	end
end

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
		local keyPick = rng(6)
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
		else
			key = ({ "Cues", "Cue", "Wins", "Day", "x" })[rng(5)]
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
	"Daily",
	"Inventory",
	"Equipped",
	"Settings",
	"Flags",
}

return {
	["the template has every field at its starting value"] = function()
		local _, SaveSchema = setup()
		local t = SaveSchema.template()
		H.expect(SaveSchema.Version == 1, "version 1")
		H.expect(t.Version == SaveSchema.Version, "template carries the current version")
		H.expect(t.Money == 0 and t.RankXp == 0 and t.PeakDivision == 0, "starts at zero")
		H.expect(t.RatedMatches == 0, "starts unranked")
		for _, key in STAT_KEYS do
			H.expect(t.Stats[key] == 0, "Stats." .. key .. " starts at 0")
		end
		local count = 0
		for _ in t.Stats do
			count += 1
		end
		H.expect(count == #STAT_KEYS, "Stats has exactly the listed counters")
		H.expect(t.Daily.Day == 0 and t.Daily.SoloMoney == 0, "daily starts at zero")
		H.expect(type(t.Inventory.Cues) == "table" and next(t.Inventory.Cues) == nil, "no cues")
		H.expect(t.Equipped.Cue == "default", "default cue")
		H.expect(next(t.Settings) == nil and next(t.Flags) == nil, "empty maps")
	end,

	["template copies are independent"] = function()
		local _, SaveSchema = setup()
		local a = SaveSchema.template()
		a.Money = 5
		a.Stats.Wins = 3
		a.Daily.Day = 9
		table.insert(a.Inventory.Cues, "oak")
		a.Equipped.Cue = "oak"
		a.Settings.x = 1
		a.Flags.y = true
		local b = SaveSchema.template()
		H.expect(b.Money == 0 and b.Stats.Wins == 0 and b.Daily.Day == 0, "numbers untouched")
		H.expect(#b.Inventory.Cues == 0 and b.Equipped.Cue == "default", "tables untouched")
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

	["isInteger and cleanInteger"] = function()
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
	end,

	["migrate stamps a save with no version as version 1"] = function()
		local _, SaveSchema = setup()
		for _, version in { nil :: any, 0, -2, NAN, "1", 0.5 } do
			local save = { Money = 12, Version = version }
			local out, notes = SaveSchema.migrate(save)
			H.expect(out == save, "migrated in place")
			H.expect(out.Version == 1, "now version 1, from " .. tostring(version))
			H.expect(out.Money == 12, "data kept")
			H.expect(#notes == 1 and notes[1] == "migrated 0 -> 1", table.concat(notes, "; "))
		end
	end,

	["every version below the current one has a migration"] = function()
		local _, SaveSchema = setup()
		for v = 0, SaveSchema.Version - 1 do
			H.expect(type(SaveSchema.Migrations[v]) == "function", "missing migration " .. v)
		end
		-- Every step, run from version 0, reaches the current version.
		local out = SaveSchema.migrate({ Version = 0 })
		H.expect(out.Version == SaveSchema.Version, "reaches the current version")
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

	["migrate turns a non-table into a fresh template"] = function()
		local _, SaveSchema = setup()
		for _, bad in { nil :: any, 5, "save", true } do
			local out, notes = SaveSchema.migrate(bad)
			H.expect(type(out) == "table" and out.Version == SaveSchema.Version, "template")
			H.expect(#notes == 1, "one note")
		end
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
			Version = 1,
			Money = 10,
			Stats = 5,
			Daily = "today",
			Inventory = true,
			Equipped = nil,
			Settings = 3,
			Flags = "x",
		}
		local out, fixes = SaveSchema.validate(save)
		H.expect(out == save and out.Money == 10, "kept what was good")
		H.expect(out.Stats.Wins == 0 and out.Daily.Day == 0, "rebuilt from the template")
		H.expect(#out.Inventory.Cues == 0 and out.Equipped.Cue == "default", "rebuilt")
		H.expect(#fixes >= 6, "each rebuild reported")
		assertClean(Config, SaveSchema, out)
	end,

	["validate repairs a bad inventory"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		-- Built key by key: a hostile mixed table, on purpose.
		local mixed: any = { "a", "b" }
		mixed[4] = "d"
		mixed.x = "y"
		mixed[0] = "z"
		mixed[2.5] = "w"
		save.Inventory.Cues = mixed
		local out, fixes = SaveSchema.validate(save)
		local cues = out.Inventory.Cues
		H.expect(#cues == 3 and cues[1] == "a" and cues[2] == "b" and cues[3] == "d", "packed")
		H.expect(isGaplessArray(cues), "gapless")
		H.expect(#fixes == 2, "dropped keys and closed gaps: " .. table.concat(fixes, "; "))

		save.Inventory.Cues = "oak"
		SaveSchema.validate(save)
		H.expect(type(save.Inventory.Cues) == "table" and #save.Inventory.Cues == 0, "reset")

		save.Inventory = { Cues = { "a", "b" } }
		local _, clean = SaveSchema.validate(save)
		H.expect(#clean == 0 and #save.Inventory.Cues == 2, "a good array is left alone")
		assertClean(Config, SaveSchema, save)
	end,

	["validate resets a bad equipped cue"] = function()
		local _, SaveSchema = setup()
		for _, bad in { nil :: any, "", 5, {}, string.rep("c", 65), true } do
			local save = SaveSchema.template()
			save.Equipped.Cue = bad
			local out, fixes = SaveSchema.validate(save)
			H.expect(out.Equipped.Cue == "default" and #fixes == 1, "reset " .. tostring(bad))
		end
		local save = SaveSchema.template()
		save.Equipped.Cue = string.rep("c", 64)
		local _, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 0, "64 characters is allowed")
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
		local out, fixes = SaveSchema.validate(save)
		H.expect(out.FutureField.deep[2] == 2 and out.Stats.FutureCounter == 5, "kept")
		H.expect(#fixes == 0, "not reported")
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
		for _, bad in { nil :: any, 1, "save", true } do
			local out, fixes = SaveSchema.validate(bad)
			H.expect(type(out) == "table" and #fixes == 1, "non-table save becomes a template")
			assertClean(Config, SaveSchema, out)
		end
	end,

	["fuzz: validate never errors and always leaves a clean save"] = function()
		local Config, SaveSchema = setup()
		local rng = newRng(20260927)
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
				for _ = 1, rng(4) - 1 do
					local sub = save[({ "Stats", "Daily", "Inventory", "Equipped" })[rng(4)]]
					if type(sub) == "table" then
						local keys = { "Cues", "Cue", "Day", "SoloMoney", "Wins", "WinStreak" }
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
}
