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
	"Drops",
	"Social",
	"Trades",
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
	checkMap(inv.PaidCases, S.MaxCaseEntries, "Inventory.PaidCases", countUpTo(S.ItemCountCap))
	checkMap(inv.New, S.MaxCueEntries, "Inventory.New", isTrue)
	checkMap(inv.PaidCues, S.MaxCueEntries, "Inventory.PaidCues", countUpTo(S.ItemCountCap))
	for id, n in inv.PaidCues do
		H.expect((inv.Cues[id] or 0) >= n, "a paid count is never above the copies held: " .. id)
	end
	checkMap(inv.PaidUnique, S.MaxCueEntries, "Inventory.PaidUnique", isTrue)
	for id in inv.PaidUnique do
		H.expect(inv.Unique[id] ~= nil, "a paid mark only on a Unique cue held: " .. id)
	end
	H.expect(isGaplessArray(inv.Timers), "Inventory.Timers must be a gapless array")
	H.expect(#inv.Timers <= S.MaxTimerEntries, "Inventory.Timers over its cap")
	for i = 1, #inv.Timers do
		local t = inv.Timers[i]
		H.expect(type(t) == "table" and size(t) == 3, "a timer is { Case, At, Paid }")
		H.expect(table.find(Config.Cases.Order, t.Case) ~= nil, "a timer's case is a case")
		inRange(t.At, S.UnixTimeCap, "a timer's At")
		H.expect(type(t.Paid) == "boolean", "a timer's Paid is a boolean")
	end
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
	inRange(daily.PcDrops, S.StatCap, "Daily.PcDrops")
	inRange(daily.Disguised, S.StatCap, "Daily.Disguised")
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
	for _, key in { "VipOffer", "VipCueGiven", "StarterBought", "FirstPackBought", "QuickApplied" } do
		H.expect(type(shop[key]) == "boolean", "Shop." .. key .. " must be a boolean")
	end
	H.expect(isGaplessArray(shop.Purchases), "Shop.Purchases must be a gapless array")
	H.expect(#shop.Purchases <= Config.Shop.RecentPurchases, "Shop.Purchases over its cap")
	for i = 1, #shop.Purchases do
		H.expect(type(shop.Purchases[i]) == "string", "purchase ids are strings")
	end
	checkMap(shop.Limited, S.MaxCueEntries, "Shop.Limited", countUpTo(S.CopyNumberCap))
	inRange(shop.BoostEnds, S.UnixTimeCap, "Shop.BoostEnds")
	H.expect(type(shop.Restock) == "table", "Shop.Restock must be a table")
	inRange(shop.Restock.Slot, S.StatCap, "Shop.Restock.Slot")
	checkMap(shop.Restock.Bought, S.MaxSmallEntries, "Shop.Restock.Bought", countUpTo(S.StatCap))

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

	inRange(save.Drops.SinceRare, S.StatCap, "Drops.SinceRare")
	inRange(save.Drops.SinceEpic, S.StatCap, "Drops.SinceEpic")
	inRange(save.Drops.Total, S.StatCap, "Drops.Total")
	local social = save.Social
	H.expect(type(social.Group) == "boolean" and type(social.InviteDone) == "boolean", "social")
	inRange(social.InvitedBy, 1e15, "Social.InvitedBy")
	inRange(social.InviteMonth, S.StatCap, "Social.InviteMonth")
	inRange(social.Invites, S.StatCap, "Social.Invites")
	local trades = save.Trades
	H.expect(isGaplessArray(trades.History), "Trades.History must be a gapless array")
	H.expect(#trades.History <= S.MaxTradeHistory, "Trades.History over its cap")
	for i = 1, #trades.History do
		local h = trades.History[i]
		H.expect(type(h) == "table" and size(h) == 5, "a history entry has five fields")
		H.expect(type(h.Id) == "string" and isInt(h.With) and isInt(h.At), "history fields")
		H.expect(isGaplessArray(h.Gave) and isGaplessArray(h.Got), "history sides")
		H.expect(#h.Gave <= S.MaxTradeSideItems and #h.Got <= S.MaxTradeSideItems, "sides")
	end
	H.expect(isGaplessArray(trades.Applied), "Trades.Applied must be a gapless array")
	H.expect(#trades.Applied <= S.MaxAppliedTrades, "Trades.Applied over its cap")
	for i = 1, #trades.Applied do
		H.expect(type(trades.Applied[i]) == "string", "applied trade ids are strings")
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
	"Drops",
	"Social",
	"Trades",
}

-- Sub-fields the fuzz breaks, by table.
local SUB_FIELDS: { [string]: { string } } = {
	Stats = { "Wins", "WinStreak" },
	Progress = { "RealMatches", "Wins" },
	Inventory = {
		"Cues",
		"PaidCues",
		"Unique",
		"PaidUnique",
		"Cases",
		"PaidCases",
		"Timers",
		"New",
	},
	Index = { "Seen", "Rows" },
	Equipped = { "Cue" },
	Daily = {
		"Day",
		"SoloMoney",
		"Wins",
		"PcDrops",
		"Disguised",
		"Opponents",
		"PlaySeconds",
		"PlaytimeClaimed",
	},
	Login = { "LastDay", "StreakDay", "Week" },
	Shop = { "FirstJoin", "VipOffer", "Purchases", "Limited", "BoostEnds", "Restock" },
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
	Drops = { "SinceRare", "SinceEpic", "Total" },
	Social = { "Group", "InvitedBy", "InviteDone", "InviteMonth", "Invites" },
	Trades = { "History", "Applied" },
}
local SUB_TABLES = {
	"Stats",
	"Progress",
	"Inventory",
	"Index",
	"Equipped",
	"Daily",
	"Login",
	"Shop",
	"Ults",
	"Drops",
	"Social",
	"Trades",
}

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
		H.expect(SaveSchema.Version == 6, "version 6")
		H.expect(SaveSchema.WipeBelow == 6, "everything older is wiped")
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
		local inventoryKeys =
			{ "Cues", "PaidCues", "Unique", "PaidUnique", "Cases", "PaidCases", "Timers", "New" }
		for _, key in inventoryKeys do
			H.expect(type(t.Inventory[key]) == "table", "Inventory." .. key)
			H.expect(next(t.Inventory[key]) == nil, "Inventory." .. key .. " starts empty")
		end
		H.expect(size(t.Inventory) == #inventoryKeys, "Inventory has its eight tables")
		H.expect(next(t.Index.Seen) == nil and next(t.Index.Rows) == nil, "empty Index")
		H.expect(size(t.Index) == 2, "Index has two maps")
		H.expect(next(t.Titles) == nil and next(t.Codes) == nil, "no titles or codes")
		H.expect(t.Equipped.Cue == "Classic", "Classic is the default cue")
		local d = t.Daily
		H.expect(d.Day == 0 and d.SoloMoney == 0 and d.PcMoney == 0 and d.ShortMoney == 0, "d")
		H.expect(d.Wins == 0 and d.PcDrops == 0 and d.Disguised == 0 and d.PlaySeconds == 0, "")
		H.expect(next(d.Opponents) == nil and next(d.PlaytimeClaimed) == nil, "daily maps")
		H.expect(size(d) == 10, "Daily has ten fields")
		local l = t.Login
		H.expect(l.LastDay == 0 and l.StreakDay == 0 and l.Week == 0 and size(l) == 3, "login")
		local s = t.Shop
		H.expect(s.FirstJoin == 0, "first join not set yet")
		H.expect(not s.VipOffer and not s.VipCueGiven, "no VIP")
		H.expect(not s.StarterBought and not s.FirstPackBought, "nothing bought")
		H.expect(type(s.Purchases) == "table" and #s.Purchases == 0, "no receipts")
		H.expect(s.BoostEnds == 0 and s.QuickApplied == false, "no boost, no halving yet")
		H.expect(s.Restock.Slot == 0 and next(s.Restock.Bought) == nil, "no restock buys")
		H.expect(next(s.Limited) == nil and size(s) == 10, "shop fields")
		H.expect(next(t.Settings) == nil and next(t.Flags) == nil, "empty maps")
		local Config = H.require("Config")
		local u = t.Ults
		H.expect(u.Slots[1] == Config.Ults.Default and u.Slots[1] == "Magnet", "Magnet in slot 1")
		H.expect(#u.Slots == 3 and u.Slots[2] == "" and u.Slots[3] == "", "slots 2, 3 empty")
		H.expect(#u.Locked == 3 and not u.Locked[1] and not u.Locked[2] and not u.Locked[3], "")
		H.expect(u.Selected == 1 and u.Spins == Config.Ults.Earn.Starter, "starter spins")
		H.expect(u.LuckySpins == 0 and u.Pity == 0 and u.FreeSpinDay == 0, "nothing else")
		H.expect(u.SpinsDone == 0 and u.QueueUlts == true and size(u) == 9, "ults fields")
		local drops = t.Drops
		H.expect(drops.SinceRare == 0 and drops.SinceEpic == 0 and drops.Total == 0, "no drops")
		H.expect(size(drops) == 3, "Drops has three counters")
		local social = t.Social
		H.expect(social.Group == false and social.InvitedBy == 0, "no group, not invited")
		H.expect(social.InviteDone == false and social.InviteMonth == 0, "invite state")
		H.expect(social.Invites == 0 and size(social) == 5, "social fields")
		H.expect(next(t.Trades.History) == nil and next(t.Trades.Applied) == nil, "no trades")
		H.expect(size(t.Trades) == 2, "Trades has two arrays")
	end,

	["every save older than version 6 starts over, keeping only its receipt ids"] = function()
		local Config, SaveSchema = setup()
		for _, version in { nil :: any, 0, 1, 2, 3, 4, 5, -2, NAN, "1", 0.5 } do
			local old = {
				Version = version,
				Money = 1234,
				RankXp = 5000,
				Inventory = { Cues = { GoldCue = 1 }, Cases = { Rare = 3 } },
				Shop = { Purchases = { "r1", 5, "r2" }, StarterBought = true },
				Flags = { FirstWinCase = true },
			}
			local out, notes = SaveSchema.migrate(old)
			H.expect(out ~= old, "a new table")
			H.expect(out.Version == SaveSchema.Version, "now current, from " .. tostring(version))
			H.expect(out.Money == 0 and out.RankXp == 0, "money and rank start over")
			H.expect(next(out.Inventory.Cues) == nil and next(out.Inventory.Cases) == nil, "")
			H.expect(out.Shop.StarterBought == false and out.Flags.FirstWinCase == nil, "flags")
			H.expect(#out.Shop.Purchases == 2, "the receipt ids that are strings are kept")
			H.expect(out.Shop.Purchases[1] == "r1" and out.Shop.Purchases[2] == "r2", "in order")
			H.expect(#notes == 1 and notes[1]:find("started over", 1, true) ~= nil, notes[1])
			reconcile(out, SaveSchema.template())
			local _, fixes = SaveSchema.validate(out)
			H.expect(#fixes == 0, "clean: " .. table.concat(fixes, "; "))
			assertClean(Config, SaveSchema, out)
		end
		-- Only the newest Config.Shop.RecentPurchases receipt ids survive.
		local many = {}
		for i = 1, Config.Shop.RecentPurchases + 7 do
			table.insert(many, "p" .. i)
		end
		local out = SaveSchema.migrate({ Version = 5, Shop = { Purchases = many } })
		H.expect(#out.Shop.Purchases == Config.Shop.RecentPurchases, "the cap")
		H.expect(out.Shop.Purchases[1] == "p8", "the oldest go first")
		-- Broken shops never error.
		for _, shop in { 5, "x", { Purchases = "r1" }, { Purchases = { {}, true } } } do
			local ok, wiped = pcall(SaveSchema.migrate, { Version = 4, Shop = shop })
			H.expect(ok and #wiped.Shop.Purchases == 0, "no receipts from a broken shop")
		end
	end,

	["a migration from version 6 on that errors or is missing stops at the old version"] = function()
		local _, SaveSchema = setup()
		local version = SaveSchema.Version
		-- Pretend the code knows one more version, so a version-6 save has a step to take.
		SaveSchema.Version = version + 1
		SaveSchema.Migrations[version] = function(data: any): any
			data.Money = -1
			error("disk on fire")
		end
		local okBroken, broken, brokenNotes = pcall(SaveSchema.migrate, { Version = 6, Money = 5 })
		SaveSchema.Migrations[version] = nil
		local okMissing, missing, missingNotes =
			pcall(SaveSchema.migrate, { Version = 6, Money = 5 })
		SaveSchema.Version = version
		H.expect(okBroken and okMissing, "migrate never errors")
		-- PlayerData tells a failed migration by the version, and then releases the save as it
		-- was stored (it migrates a copy), so the half-changed table is never written back.
		H.expect(broken.Version == 6, "a failed step leaves the old version")
		H.expect(
			#brokenNotes == 1 and brokenNotes[1]:find("failed", 1, true) ~= nil,
			table.concat(brokenNotes, "; ")
		)
		H.expect(missing.Version == 6 and missing.Money == 5, "a missing step changes nothing")
		H.expect(
			#missingNotes == 1 and missingNotes[1]:find("no migration", 1, true) ~= nil,
			table.concat(missingNotes, "; ")
		)
	end,

	["validate repairs the version 6 fields"] = function()
		local Config, SaveSchema = setup()
		local save = SaveSchema.template()
		local inv = save.Inventory
		inv.Cues = { GoldCue = 2, MidnightCue = 1 }
		inv.PaidCues = { GoldCue = 5, MidnightCue = 1, CherryCue = 2 } -- 5 > 2; Cherry not held
		inv.Unique = { FoundersCue = 3 }
		inv.PaidUnique = { FoundersCue = true, BetaCue = true, GoldCue = "yes" }
		inv.PaidCases = { Rare = 2.5, Epic = -1 }
		local timers: any = {
			{ Case = "Rare", At = 1790000000, Paid = false },
			{ Case = "Nope", At = 1, Paid = false },
			{ Case = "Epic", At = NAN, Paid = true },
			{ Case = "Legendary", At = 1790003600, Paid = true, Extra = 1 },
			"broken",
		}
		inv.Timers = timers
		save.Daily.PcDrops = -3
		save.Daily.Disguised = 4.5
		save.Shop.BoostEnds = INF
		save.Shop.QuickApplied = "yes"
		save.Shop.Restock = { Slot = "9", Bought = { Rare = 2, Lucky = 0, Vip = 1.5 } }
		save.Drops = { SinceRare = 3, SinceEpic = -1, Total = NAN }
		save.Social = { Group = 1, InvitedBy = 12.5, InviteDone = true, Invites = -2 }
		save.Trades = {
			History = {
				{ Id = "t1", With = 42, At = 1790000000, Gave = { "GoldCue" }, Got = {} },
				{ Id = "t2", With = 42, At = 1, Gave = "x", Got = {} },
				{ Id = "", With = 1, At = 1, Gave = {}, Got = {} },
			},
			Applied = { "t1", 5, "t0" },
		}
		local out, fixes = SaveSchema.validate(save)
		H.expect(#fixes > 0, "it found the damage")
		local i = out.Inventory
		H.expect(i.PaidCues.GoldCue == 2 and i.PaidCues.MidnightCue == 1, "clamped to held")
		H.expect(i.PaidCues.CherryCue == nil, "not held: dropped")
		H.expect(i.PaidUnique.FoundersCue == true and i.PaidUnique.BetaCue == nil, "unique")
		H.expect(i.PaidUnique.GoldCue == nil, "not true: dropped")
		H.expect(i.PaidCases.Rare == 2 and i.PaidCases.Epic == nil, "case counts")
		H.expect(#i.Timers == 2, "two good timers kept")
		H.expect(i.Timers[1].Case == "Rare" and i.Timers[2].Case == "Legendary", "in order")
		H.expect(i.Timers[2].Extra == nil and i.Timers[2].Paid == true, "rebuilt clean")
		local d = out.Daily
		H.expect(d.PcDrops == 0 and d.Disguised == 4, "daily counts")
		H.expect(out.Shop.BoostEnds == 0 and out.Shop.QuickApplied == false, "shop")
		H.expect(out.Shop.Restock.Slot == 0, "a string is not a slot")
		local bought = out.Shop.Restock.Bought
		H.expect(bought.Rare == 2 and bought.Lucky == nil and bought.Vip == 1, "restock buys")
		H.expect(out.Drops.SinceRare == 3 and out.Drops.SinceEpic == 0, "pity")
		H.expect(out.Drops.Total == 0, "NaN is 0")
		local social = out.Social
		H.expect(social.Group == false and social.InvitedBy == 12, "social")
		H.expect(social.InviteDone == true and social.InviteMonth == 0, "filled")
		H.expect(social.Invites == 0, "no negative count")
		local history = out.Trades.History
		H.expect(#history == 1 and history[1].Id == "t1" and history[1].Gave[1] == "GoldCue", "")
		local applied = out.Trades.Applied
		H.expect(#applied == 2 and applied[1] == "t1" and applied[2] == "t0", "applied ids")
		assertClean(Config, SaveSchema, out)
		local _, again = SaveSchema.validate(out)
		H.expect(#again == 0, "a repaired save is clean: " .. table.concat(again, "; "))
	end,

	["validate keeps the newest trades and the first timers within their caps"] = function()
		local Config, SaveSchema = setup()
		local S = Config.Save
		local save = SaveSchema.template()
		for n = 1, S.MaxTradeHistory + 5 do
			table.insert(save.Trades.History, {
				Id = "t" .. n,
				With = n,
				At = 1790000000 + n,
				Gave = { "GoldCue" },
				Got = { "Case:Rare" },
			})
		end
		for n = 1, S.MaxAppliedTrades + 3 do
			table.insert(save.Trades.Applied, "a" .. n)
		end
		for n = 1, S.MaxTimerEntries + 4 do
			table.insert(save.Inventory.Timers, { Case = "Rare", At = n, Paid = false })
		end
		local out = SaveSchema.validate(save)
		H.expect(#out.Trades.History == S.MaxTradeHistory, "history capped")
		H.expect(out.Trades.History[1].Id == "t6", "the newest kept")
		H.expect(#out.Trades.Applied == S.MaxAppliedTrades and out.Trades.Applied[1] == "a4", "")
		H.expect(#out.Inventory.Timers == S.MaxTimerEntries, "timers capped")
		H.expect(out.Inventory.Timers[1].At == 1, "the first ones kept")
		-- A side with more than MaxTradeSideItems items is broken.
		local big = SaveSchema.template()
		local side = {}
		for n = 1, S.MaxTradeSideItems + 1 do
			side[n] = "GoldCue"
		end
		big.Trades.History = { { Id = "x", With = 1, At = 1, Gave = side, Got = {} } }
		H.expect(#SaveSchema.validate(big).Trades.History == 0, "too many items: dropped")
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
		save.Shop.VipOffer = "yes"
		save.Shop.VipCueGiven = nil
		save.Shop.StarterBought = true
		save.Shop.FirstPackBought = 0
		local out, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 3, table.concat(fixes, "; "))
		H.expect(out.Shop.VipOffer == false, "never grants")
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

	["fuzz: the wipe never errors on any old save"] = function()
		local Config, SaveSchema = setup()
		local rng = newRng(1)
		for round = 1, 300 do
			local save: any = { Version = rng(6) - 1 }
			for _ = 1, rng(5) do
				save[FIELDS[rng(#FIELDS)]] = randomValue(rng, 1)
			end
			save.Version = rng(6) - 1
			local ok, out, notes = pcall(SaveSchema.migrate, save)
			H.expect(ok, ("round %d errored"):format(round))
			H.expect(
				out.Version == SaveSchema.Version,
				("round %d: %s"):format(round, table.concat(notes, "; "))
			)
			reconcile(out, SaveSchema.template())
			local okValid, valid = pcall(SaveSchema.validate, out)
			H.expect(okValid, ("round %d: validate errored"):format(round))
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
