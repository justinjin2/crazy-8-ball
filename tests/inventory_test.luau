--!strict
-- The inventory (Progression/Inventory): counts, cases, selling back (ECONOMY 8), duplicates,
-- equipping, NEW tags, the Index rows and their rewards (ECONOMY 18), and the client snapshot.

local H = require("./harness")

local function load()
	return H.require("Progression.Inventory"), H.require("Progression.Catalog"), H.require("Config")
end

-- The save v2 sections the inventory works on.
local function newSave(): any
	return {
		Money = 0,
		Inventory = { Cues = {}, Unique = {}, Cases = {}, New = {} },
		Index = { Seen = {}, Rows = {} },
		Titles = {},
		Equipped = { Cue = "Classic" },
		Progress = { RealMatches = 0, Wins = 0 },
	}
end

local function ids(list: { any }): string
	local out = {}
	for _, entry in list do
		table.insert(out, if type(entry) == "table" then entry.id else entry)
	end
	return table.concat(out, " ")
end

-- Every table reachable from `value`, to prove the snapshot shares none with the save.
local function tablesIn(value: any, found: { [any]: boolean }): { [any]: boolean }
	if type(value) == "table" and not found[value] then
		found[value] = true
		for _, v in value do
			tablesIn(v, found)
		end
	end
	return found
end

-- Plain data a RemoteEvent carries: strings, finite numbers, booleans, and tables that are
-- either gapless arrays or string-keyed maps, with no metatables and nothing from the save.
local function expectPlain(value: any, path: string, saveTables: { [any]: boolean })
	local kind = type(value)
	if kind == "string" or kind == "boolean" then
		return
	elseif kind == "number" then
		H.expect(value == value and math.abs(value) ~= math.huge, path .. " is not finite")
		return
	end
	H.expect(kind == "table", ("%s is a %s"):format(path, kind))
	H.expect(getmetatable(value) == nil, path .. " has a metatable")
	H.expect(not saveTables[value], path .. " is a table from the save")
	local length = #value
	local keys = 0
	for key, item in value do
		keys += 1
		if length > 0 then
			H.expect(
				type(key) == "number" and key >= 1 and key <= length and key == math.floor(key),
				path .. " mixes array and map keys"
			)
		else
			H.expect(type(key) == "string", path .. " has a non-string key")
		end
		expectPlain(item, path .. "." .. tostring(key), saveTables)
	end
	if length > 0 then
		H.expect(keys == length, path .. " has gaps")
	end
end

-- Runs `body` with a cue vaulted, restoring it whatever happens.
local function withVaulted(Catalog: any, id: string, body: () -> ())
	local cue = Catalog.get(id)
	local was = cue.Vaulted
	cue.Vaulted = true
	local ok, err = pcall(body)
	cue.Vaulted = was
	if not ok then
		error(err, 0)
	end
end

return {
	["Classic is always owned, never stored, never removed or sold"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(Inventory.count(save, "Classic") == 1 and Inventory.owns(save, "Classic"), "owned")
		H.expect(not Inventory.addCue(save, "Classic"), "never added")
		H.expect(save.Inventory.Cues.Classic == nil, "never stored")
		local ok, reason = Inventory.removeCue(save, "Classic")
		H.expect(not ok and reason == "Default", "never removed: " .. tostring(reason))
		ok, reason = Inventory.canSell(save, "Classic")
		H.expect(not ok and reason == "NotSellable", "never sold: " .. tostring(reason))
		H.expect(
			Inventory.equip(save, "Classic") and Inventory.equipped(save) == "Classic",
			"equips"
		)
		-- Reads on an empty table own Classic and write nothing.
		local empty = {}
		H.expect(
			Inventory.count(empty, "Classic") == 1 and Inventory.count(empty, "ChalkDust") == 0,
			"empty"
		)
		Inventory.snapshot(empty)
		Inventory.indexRows(empty)
		H.expect(next(empty) == nil, "reads wrote to the save")
	end,

	["adding and removing cues keeps counts, the Index and NEW tags"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(Inventory.addCue(save, "ChalkDust"), "add one")
		H.expect(Inventory.count(save, "ChalkDust") == 1, "count 1")
		H.expect(
			save.Index.Seen.ChalkDust == true and save.Inventory.New.ChalkDust == true,
			"seen and new"
		)
		H.expect(
			Inventory.addCue(save, "ChalkDust", 2) and Inventory.count(save, "ChalkDust") == 3,
			"count 3"
		)
		H.expect(
			Inventory.addCue(save, "VipCue") and Inventory.owns(save, "VipCue"),
			"Exclusive cues count too"
		)

		local ok, reason = Inventory.removeCue(save, "ChalkDust", 5)
		H.expect(
			not ok and reason == "TooMany" and Inventory.count(save, "ChalkDust") == 3,
			"too many"
		)
		H.expect(
			Inventory.removeCue(save, "ChalkDust", 2) and Inventory.count(save, "ChalkDust") == 1,
			"to 1"
		)
		H.expect(Inventory.removeCue(save, "ChalkDust"), "the last one")
		H.expect(save.Inventory.Cues.ChalkDust == nil, "the key goes at 0")
		H.expect(save.Inventory.New.ChalkDust == nil, "the NEW tag goes with it")
		H.expect(save.Index.Seen.ChalkDust == true, "the Index keeps it")
		ok, reason = Inventory.removeCue(save, "ChalkDust")
		H.expect(not ok and reason == "NotOwned", "not owned: " .. tostring(reason))

		for _, bad in { 0, -1, 1.5, math.huge, "2" } do
			H.expect(
				not Inventory.addCue(save, "SideSpin", bad :: any),
				"bad count " .. tostring(bad)
			)
		end
		H.expect(
			save.Inventory.Cues.SideSpin == nil and save.Index.Seen.SideSpin == nil,
			"nothing added"
		)
		H.expect(
			not Inventory.addCue(save, "Nope") and not Inventory.addCue(save, 7),
			"unknown ids"
		)
		H.expect(not Inventory.addCue(save, "FoundersCue"), "Unique cues go through addUnique")
		ok, reason = Inventory.removeCue(save, "Nope")
		H.expect(not ok and reason == "Unknown", "unknown: " .. tostring(reason))
		ok, reason = Inventory.removeCue(save, "VipCue", 0)
		H.expect(not ok and reason == "BadCount", "bad count: " .. tostring(reason))
	end,

	["Unique cues keep their copy number, one per player"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(Inventory.addUnique(save, "FoundersCue", 12), "add #12")
		H.expect(
			Inventory.count(save, "FoundersCue") == 1 and Inventory.copy(save, "FoundersCue") == 12,
			"#12"
		)
		H.expect(save.Index.Seen.FoundersCue and save.Inventory.New.FoundersCue, "seen and new")
		H.expect(not Inventory.addUnique(save, "FoundersCue", 13), "one per player")
		H.expect(Inventory.copy(save, "FoundersCue") == 12, "still #12")
		H.expect(not Inventory.addUnique(save, "ChalkDust", 1), "only Unique cues")
		H.expect(not Inventory.addUnique(save, "BetaCue", 0), "copy numbers start at 1")
		H.expect(Inventory.copy(save, "ChalkDust") == nil, "no copy number for case cues")
		H.expect(Inventory.removeCue(save, "FoundersCue"), "removed (a trade, later)")
		H.expect(
			not Inventory.owns(save, "FoundersCue") and save.Inventory.Unique.FoundersCue == nil,
			"gone"
		)
	end,

	["unopened cases stack per type"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(
			Inventory.addCases(save, "Standard", 2) and Inventory.addCases(save, "Rare"),
			"add"
		)
		H.expect(
			Inventory.caseCount(save, "Standard") == 2 and Inventory.caseCount(save, "Rare") == 1,
			"counts"
		)
		H.expect(Inventory.addCases(save, "Event"), "a switched-off case can still be given")
		H.expect(not Inventory.takeCases(save, "Standard", 3), "not enough")
		H.expect(Inventory.caseCount(save, "Standard") == 2, "unchanged")
		H.expect(Inventory.takeCases(save, "Standard", 2), "take both")
		H.expect(save.Inventory.Cases.Standard == nil, "the key goes at 0")
		H.expect(not Inventory.takeCases(save, "Epic"), "none")
		H.expect(
			not Inventory.addCases(save, "Nope") and not Inventory.addCases(save, "Rare", 0),
			"bad input"
		)
		H.expect(
			not Inventory.takeCases(save, "Rare", -1) and Inventory.caseCount(save, "Rare") == 1,
			"bad take"
		)
		H.expect(Inventory.caseCount(save, "Nope") == 0, "unknown case")
	end,

	["duplicates are case cues above one, in catalog order"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "Eclipse", 2)
		Inventory.addCue(save, "ChalkDust", 3)
		Inventory.addCue(save, "SideSpin")
		Inventory.addCue(save, "VipCue", 2) -- Exclusive: never a duplicate to sell
		local dups = Inventory.duplicates(save)
		H.expect(ids(dups) == "ChalkDust Eclipse", "duplicates: " .. ids(dups))
		H.expect(dups[1].extra == 2 and dups[1].value == 30, "ChalkDust: 2 extra, $30")
		H.expect(dups[2].extra == 1 and dups[2].value == 75000, "Eclipse: 1 extra, $75,000")
	end,

	["selling pays the section 8 value and leaves money to the caller"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "GoldenBreak", 2)
		local ok, money = Inventory.sell(save, "GoldenBreak")
		H.expect(ok and money == 3000, "a Legendary sells for $3,000: " .. tostring(money))
		H.expect(
			Inventory.count(save, "GoldenBreak") == 1 and save.Money == 0,
			"one left, no money added"
		)
		ok, money = Inventory.sell(save, "GoldenBreak", 2)
		H.expect(not ok and money == "TooMany", tostring(money))
		ok, money = Inventory.sell(save, "GoldenBreak")
		H.expect(ok and money == 3000 and not Inventory.owns(save, "GoldenBreak"), "the last one")
		H.expect(save.Index.Seen.GoldenBreak == true, "still in the Index")

		-- Exclusive and Unique never sell, owned or not.
		Inventory.addCue(save, "VipCue")
		Inventory.addCue(save, "GoldCue")
		Inventory.addUnique(save, "BetaCue", 5)
		local expectations: { { any } } = {
			{ "VipCue", 1, "NotSellable" },
			{ "GoldCue", 1, "NotSellable" },
			{ "BetaCue", 1, "NotSellable" },
			{ "Classic", 1, "NotSellable" },
			{ "Masse", 1, "NotOwned" },
			{ "Nope", 1, "Unknown" },
			{ "SideSpin", 0, "BadCount" },
		}
		for _, e in expectations do
			local can, reason = Inventory.canSell(save, e[1], e[2])
			H.expect(
				not can and reason == e[3],
				("%s: %s, expected %s"):format(e[1], tostring(reason), e[3])
			)
			local sold, why = Inventory.sell(save, e[1], e[2])
			H.expect(not sold and why == e[3], e[1] .. " sold")
		end
		H.expect(
			Inventory.owns(save, "VipCue") and Inventory.owns(save, "BetaCue"),
			"nothing removed"
		)
	end,

	["the equipped cue's last copy is refused; selling down to one is fine"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "Masse", 3)
		H.expect(Inventory.equip(save, "Masse"), "equip")
		local ok, money = Inventory.sell(save, "Masse", 2)
		H.expect(ok and money == 240, "sell down to one: " .. tostring(money))
		local can, reason = Inventory.canSell(save, "Masse")
		H.expect(not can and reason == "Equipped", "the last copy: " .. tostring(reason))
		H.expect(
			Inventory.count(save, "Masse") == 1 and Inventory.equipped(save) == "Masse",
			"kept"
		)
		Inventory.equip(save, "Classic")
		H.expect((Inventory.sell(save, "Masse")), "sells once something else is equipped")
	end,

	["sell all duplicates keeps one of each; one cue's extras alone"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "ChalkDust", 3) -- 2 x $15
		Inventory.addCue(save, "Skyline", 2) -- 1 x $40
		Inventory.addCue(save, "ThunderBreak", 4) -- 3 x $600
		Inventory.addCue(save, "Nebula") -- no extras
		Inventory.addCue(save, "StarterCue", 2) -- Exclusive: kept
		Inventory.equip(save, "ThunderBreak")

		local total, sold = Inventory.sellDuplicates(save, "Skyline")
		H.expect(
			total == 40 and ids(sold) == "Skyline" and sold[1].count == 1,
			"one cue: " .. total
		)
		H.expect(
			Inventory.count(save, "Skyline") == 1 and Inventory.count(save, "ChalkDust") == 3,
			"only it"
		)

		total, sold = Inventory.sellDuplicates(save)
		H.expect(total == 30 + 1800, "all duplicates: " .. total)
		H.expect(ids(sold) == "ChalkDust ThunderBreak", "sold " .. ids(sold))
		for _, id in { "ChalkDust", "Skyline", "ThunderBreak", "Nebula" } do
			H.expect(Inventory.count(save, id) == 1, id .. " keeps one")
		end
		H.expect(Inventory.count(save, "StarterCue") == 2, "Exclusive untouched")
		H.expect(Inventory.equipped(save) == "ThunderBreak", "still equipped")
		H.expect(#Inventory.duplicates(save) == 0 and save.Money == 0, "none left, no money added")
		total, sold = Inventory.sellDuplicates(save)
		H.expect(total == 0 and #sold == 0, "nothing to sell")
	end,

	["equip needs the cue; losing the equipped last copy goes back to Classic"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(not Inventory.equip(save, "Masse") and save.Equipped.Cue == "Classic", "not owned")
		H.expect(not Inventory.equip(save, "Nope"), "unknown")
		Inventory.addCue(save, "Masse")
		H.expect(Inventory.equip(save, "Masse") and save.Equipped.Cue == "Masse", "equipped")
		Inventory.removeCue(save, "Masse")
		H.expect(save.Equipped.Cue == "Classic", "back to Classic")
		-- A save that names a cue it doesn't hold reads as Classic.
		save.Equipped.Cue = "GoldenBreak"
		H.expect(Inventory.equipped(save) == "Classic", "unowned equipped cue")
	end,

	["markSeen clears NEW tags once"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "ChalkDust")
		Inventory.addCue(save, "SideSpin")
		local cleared = Inventory.markSeen(save, { "ChalkDust", "ChalkDust", 5, "Nope" })
		H.expect(cleared == 1, "cleared " .. cleared)
		H.expect(
			save.Inventory.New.ChalkDust == nil and save.Inventory.New.SideSpin == true,
			"tags"
		)
		H.expect(
			Inventory.markSeen(save, nil) == 0 and Inventory.markSeen(save, "SideSpin") == 0,
			"bad input"
		)
	end,

	["Index rows: totals, rewards from Config.Index, complete and claimed once"] = function()
		local Inventory, Catalog, Config = load()
		local Strings = H.require("Strings")
		-- ECONOMY 18: money for the four lower rows, a title for each of the seven.
		local MONEY = {
			Common = 1000,
			Uncommon = 2500,
			Rare = 7500,
			Epic = 25000,
			Legendary = 0,
			Mythic = 0,
			Secret = 0,
		}
		local TOTALS =
			{ Common = 7, Uncommon = 6, Rare = 6, Epic = 5, Legendary = 3, Mythic = 2, Secret = 1 }
		local save = newSave()
		local rows = Inventory.indexRows(save)
		local order = {}
		for _, row in rows do
			table.insert(order, row.rarity)
		end
		H.expect(
			table.concat(order, " ")
				== "Common Uncommon Rare Epic Legendary Mythic Secret Exclusive Unique",
			"row order: " .. table.concat(order, " ")
		)
		for _, row in rows do
			H.expect(
				row.have == 0 and not row.complete and not row.claimed,
				row.rarity .. " starts empty"
			)
			if MONEY[row.rarity] then
				H.expect(row.total == TOTALS[row.rarity], row.rarity .. " total")
				assert(row.reward, "no reward")
				H.expect(row.reward.money == MONEY[row.rarity], row.rarity .. " money")
				H.expect(
					Strings.Items.Titles[row.reward.title] ~= nil,
					row.rarity .. " title has no name"
				)
				H.expect(
					(Config.Index.Rows :: any)[row.rarity].Money == MONEY[row.rarity],
					"Config.Index"
				)
			else
				H.expect(row.reward == nil, row.rarity .. " has no reward")
			end
		end

		local ok, why = Inventory.claimRow(save, "Common")
		H.expect(not ok and why == "Incomplete", "incomplete: " .. tostring(why))
		-- Own every Common once, then sell most of them: the Index keeps them.
		for _, cue in Catalog.ofRarity("Common") do
			Inventory.addCue(save, cue.Id)
		end
		for _, cue in Catalog.ofRarity("Common") do
			if cue.Id ~= "ChalkDust" then
				Inventory.sell(save, cue.Id)
			end
		end
		local common = Inventory.indexRows(save)[1]
		H.expect(
			common.have == 7 and common.complete and not common.claimed,
			"complete after selling"
		)
		local reward
		ok, reward = Inventory.claimRow(save, "Common")
		H.expect(
			ok and reward.money == 1000 and reward.title == "Common",
			"the Common row pays $1,000"
		)
		H.expect(save.Index.Rows.Common == true and save.Titles.Common == true, "marked")
		H.expect(save.Money == 0, "money is the caller's to add")
		ok, why = Inventory.claimRow(save, "Common")
		H.expect(not ok and why == "Claimed", "only once: " .. tostring(why))
		H.expect(Inventory.indexRows(save)[1].claimed, "claimed")

		-- A title-only row.
		for _, cue in Catalog.ofRarity("Legendary") do
			Inventory.addCue(save, cue.Id)
		end
		ok, reward = Inventory.claimRow(save, "Legendary")
		H.expect(
			ok and reward.money == 0 and reward.title == "Legendary",
			"Legendary: a title only"
		)

		ok, why = Inventory.claimRow(save, "Exclusive")
		H.expect(not ok and why == "NoReward", "Exclusive: " .. tostring(why))
		ok, why = Inventory.claimRow(save, "Nope")
		H.expect(not ok and why == "Unknown", "unknown: " .. tostring(why))
		ok, why = Inventory.claimRow(save, 3)
		H.expect(not ok and why == "Unknown", "not a string")
	end,

	["a vaulted cue still counts toward its row; held cues count without Seen"] = function()
		local Inventory, Catalog = load()
		withVaulted(Catalog, "Eclipse", function()
			local save = newSave()
			local secret = Inventory.indexRows(save)[7]
			H.expect(
				secret.rarity == "Secret" and secret.total == 1,
				"the vaulted Secret is still listed"
			)
			Inventory.addCue(save, "Eclipse")
			H.expect(Inventory.indexRows(save)[7].complete, "and completes the row")
		end)
		-- A save whose Seen was never filled in (an old layout) still counts what it holds.
		local old = newSave()
		old.Inventory.Cues.Nebula = 1
		H.expect(Inventory.indexRows(old)[6].have == 1, "held but not Seen")
	end,

	["snapshot is plain data in a fixed order"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "SideSpin", 2)
		Inventory.addCue(save, "ChalkDust")
		Inventory.addCue(save, "Eclipse")
		Inventory.addCue(save, "Masse")
		Inventory.addCue(save, "GoldCue")
		Inventory.addUnique(save, "BetaCue", 412)
		Inventory.addCases(save, "Legendary", 2)
		Inventory.addCases(save, "Standard", 3)
		Inventory.equip(save, "Masse")
		Inventory.markSeen(save, { "SideSpin" })
		Inventory.sell(save, "ChalkDust") -- sold: gone from cues, still seen
		save.Titles.FirstReyes = true
		save.Titles.Epic = true
		save.Titles.Common = true
		save.Titles.NotATitle = true -- unknown ids are left out
		save.Inventory.Cues.Bogus = 4 -- stray keys are ignored

		local snap = Inventory.snapshot(save)
		expectPlain(snap, "snapshot", tablesIn(save, {}))
		H.expect(
			ids(snap.cues) == "BetaCue GoldCue Eclipse Masse SideSpin Classic",
			"cues: " .. ids(snap.cues)
		)
		H.expect(snap.cues[1].copy == 412 and snap.cues[1].new == true, "BetaCue #412, new")
		H.expect(snap.cues[5].count == 2 and snap.cues[5].new == false, "SideSpin x2, seen")
		H.expect(snap.cues[6].count == 1 and snap.cues[6].copy == nil, "Classic")
		H.expect(ids(snap.cases) == "Standard Legendary" and snap.cases[1].count == 3, "cases")
		H.expect(snap.equipped == "Masse", "equipped")
		H.expect(
			ids(snap.seen) == "ChalkDust SideSpin Masse Eclipse GoldCue BetaCue",
			"seen: " .. ids(snap.seen)
		)
		H.expect(
			table.concat(snap.titles, " ") == "Epic Common FirstReyes",
			"titles: " .. table.concat(snap.titles, " ")
		)
		H.expect(#snap.rows == 9, "rows")

		-- Changing the save afterwards never reaches a snapshot already taken.
		Inventory.addCue(save, "Masse")
		H.expect(snap.cues[4].count == 1, "the snapshot is a copy")
	end,
}
