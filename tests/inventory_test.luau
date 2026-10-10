--!strict
-- The inventory (Progression/Inventory): counts, selling back (ECONOMY 8), duplicates,
-- equipping, NEW tags, the Index rows and their rewards (ECONOMY 18), and the client snapshot.

local H = require("./harness")

local function load()
	return H.require("Progression.Inventory"), H.require("Progression.Catalog"), H.require("Config")
end

-- The save v7 sections the inventory works on.
local function newSave(): any
	return {
		Money = 0,
		Inventory = {
			Cues = {},
			PaidCues = {},
			Unique = {},
			PaidUnique = {},
			New = {},
		},
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
			Inventory.count(empty, "Classic") == 1 and Inventory.count(empty, "MidnightCue") == 0,
			"empty"
		)
		Inventory.snapshot(empty)
		Inventory.indexRows(empty)
		H.expect(next(empty) == nil, "reads wrote to the save")
	end,

	["adding and removing cues keeps counts, the Index and NEW tags"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(Inventory.addCue(save, "MidnightCue"), "add one")
		H.expect(Inventory.count(save, "MidnightCue") == 1, "count 1")
		H.expect(
			save.Index.Seen.MidnightCue == true and save.Inventory.New.MidnightCue == true,
			"seen and new"
		)
		H.expect(
			Inventory.addCue(save, "MidnightCue", 2) and Inventory.count(save, "MidnightCue") == 3,
			"count 3"
		)
		H.expect(
			Inventory.addCue(save, "VipCue") and Inventory.owns(save, "VipCue"),
			"Exclusive cues count too"
		)

		local ok, reason = Inventory.removeCue(save, "MidnightCue", 5)
		H.expect(
			not ok and reason == "TooMany" and Inventory.count(save, "MidnightCue") == 3,
			"too many"
		)
		H.expect(
			Inventory.removeCue(save, "MidnightCue", 2)
				and Inventory.count(save, "MidnightCue") == 1,
			"to 1"
		)
		H.expect(Inventory.removeCue(save, "MidnightCue"), "the last one")
		H.expect(save.Inventory.Cues.MidnightCue == nil, "the key goes at 0")
		H.expect(save.Inventory.New.MidnightCue == nil, "the NEW tag goes with it")
		H.expect(save.Index.Seen.MidnightCue == true, "the Index keeps it")
		ok, reason = Inventory.removeCue(save, "MidnightCue")
		H.expect(not ok and reason == "NotOwned", "not owned: " .. tostring(reason))

		for _, bad in { 0, -1, 1.5, math.huge, "2" } do
			H.expect(
				not Inventory.addCue(save, "HeritageCue", bad :: any),
				"bad count " .. tostring(bad)
			)
		end
		H.expect(
			save.Inventory.Cues.HeritageCue == nil and save.Index.Seen.HeritageCue == nil,
			"nothing added"
		)
		H.expect(
			not Inventory.addCue(save, "Nope") and not Inventory.addCue(save, 7),
			"unknown ids"
		)
		H.expect(not Inventory.addCue(save, "FireworkCue"), "Unique cues go through addUnique")
		ok, reason = Inventory.removeCue(save, "Nope")
		H.expect(not ok and reason == "Unknown", "unknown: " .. tostring(reason))
		ok, reason = Inventory.removeCue(save, "VipCue", 0)
		H.expect(not ok and reason == "BadCount", "bad count: " .. tostring(reason))
	end,

	["Unique cues keep their copy number, one per player"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(Inventory.addUnique(save, "FireworkCue", 12), "add #12")
		H.expect(
			Inventory.count(save, "FireworkCue") == 1 and Inventory.copy(save, "FireworkCue") == 12,
			"#12"
		)
		H.expect(save.Index.Seen.FireworkCue and save.Inventory.New.FireworkCue, "seen and new")
		H.expect(not Inventory.addUnique(save, "FireworkCue", 13), "one per player")
		H.expect(Inventory.copy(save, "FireworkCue") == 12, "still #12")
		H.expect(not Inventory.addUnique(save, "MidnightCue", 1), "only Unique cues")
		H.expect(not Inventory.addUnique(save, "BetaCue", 0), "copy numbers start at 1")
		H.expect(Inventory.copy(save, "MidnightCue") == nil, "no copy number for block cues")
		H.expect(Inventory.removeCue(save, "FireworkCue"), "removed (a trade, later)")
		H.expect(
			not Inventory.owns(save, "FireworkCue") and save.Inventory.Unique.FireworkCue == nil,
			"gone"
		)
	end,

	-- The designer's own copy (2026-10-05): owned, but with no number.
	["an owner copy of a Unique cue has no number and is one per player"] = function()
		local Inventory = load()
		local save = newSave()
		save.Inventory.OwnerUnique = {}
		H.expect(Inventory.addOwnerCopy(save, "BetaCue"), "given")
		H.expect(Inventory.count(save, "BetaCue") == 1 and Inventory.owns(save, "BetaCue"), "owned")
		H.expect(Inventory.copy(save, "BetaCue") == nil, "no copy number")
		H.expect(Inventory.isOwnerCopy(save, "BetaCue"), "the owner's copy")
		H.expect(save.Index.Seen.BetaCue == true, "in the Index")
		H.expect(not Inventory.addOwnerCopy(save, "BetaCue"), "one per player")
		H.expect(not Inventory.addUnique(save, "BetaCue", 5), "a numbered one on top: no")
		H.expect(not Inventory.addOwnerCopy(save, "MidnightCue"), "only Unique cues")
		Inventory.addUnique(save, "FireworkCue", 9)
		H.expect(not Inventory.isOwnerCopy(save, "FireworkCue"), "a numbered copy is not one")
		H.expect(Inventory.removeCue(save, "BetaCue"), "removed")
		H.expect(
			not Inventory.owns(save, "BetaCue") and save.Inventory.OwnerUnique.BetaCue == nil,
			"gone"
		)
	end,

	-- The finder's money (designer, 2026-09-28): addCue and addUnique say when a cue is new to
	-- the Index, once ever; the amount comes from Config.Index.FindMoney by rarity.
	["a cue's first find is reported once, even after selling it"] = function()
		local Inventory, _, Config = load()
		local save = newSave()
		local ok, first = Inventory.addCue(save, "MidnightCue")
		H.expect(ok and first, "the first copy is a find")
		ok, first = Inventory.addCue(save, "MidnightCue")
		H.expect(ok and not first, "a second copy is not")
		H.expect(Inventory.removeCue(save, "MidnightCue", 2), "sold both")
		H.expect(Inventory.found(save, "MidnightCue"), "still in the Index")
		ok, first = Inventory.addCue(save, "MidnightCue")
		H.expect(ok and not first, "found again after selling: no second find")
		ok, first = Inventory.addCue(save, "Classic")
		H.expect(not ok and not first, "Classic is never a find")
		ok, first = Inventory.addUnique(save, "BetaCue", 7)
		H.expect(ok and first, "a Unique cue's first copy is a find")
		H.expect(Inventory.removeCue(save, "BetaCue"), "traded away")
		ok, first = Inventory.addUnique(save, "BetaCue", 9)
		H.expect(ok and not first, "and back again is not")
		-- A held cue with no Seen entry (an old save) counts as found already.
		save.Inventory.Cues.NeonCue = 1
		ok, first = Inventory.addCue(save, "NeonCue")
		H.expect(ok and not first, "held already")
		H.expect(Inventory.findMoney("MidnightCue") == Config.Index.FindMoney.Common, "Common pays")
		H.expect(Inventory.findMoney("Classic") == 0, "Classic pays nothing")
		H.expect(Inventory.findMoney("Nope") == 0, "unknown pays nothing")
	end,

	["every cue but Classic has a finder's money, rarer never less"] = function()
		local Inventory, Catalog, Config = load()
		local last = 0
		for _, rarity in Config.BlockOdds.Rarities do
			local money = Config.Index.FindMoney[rarity]
			H.expect(
				type(money) == "number" and money >= last and money % 1 == 0,
				rarity .. ": a whole amount, at least the rarity below's"
			)
			last = money
		end
		for _, cue in Catalog.list() do
			local money = Inventory.findMoney(cue.Id)
			if cue.Group == "Default" then
				H.expect(money == 0, "Classic pays nothing")
			else
				H.expect(money > 0, cue.Id .. " pays a finder's money")
			end
		end
	end,

	["paid cues: counted on add, sold first, traded last"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "MidnightCue", 2)
		Inventory.addCue(save, "MidnightCue", 2, true)
		H.expect(Inventory.count(save, "MidnightCue") == 4, "four held")
		H.expect(Inventory.paidCount(save, "MidnightCue") == 2, "two paid")
		-- A sale takes paid copies first.
		H.expect(Inventory.removeCue(save, "MidnightCue", 1), "sell one")
		H.expect(Inventory.removedPaid() == 1 and Inventory.paidCount(save, "MidnightCue") == 1, "")
		-- A trade takes free copies first.
		H.expect(Inventory.removeCue(save, "MidnightCue", 2, true), "trade two")
		H.expect(Inventory.removedPaid() == 0 and Inventory.paidCount(save, "MidnightCue") == 1, "")
		H.expect(Inventory.removeCue(save, "MidnightCue", 1, true), "the last")
		H.expect(Inventory.removedPaid() == 1 and save.Inventory.PaidCues.MidnightCue == nil, "")
		-- A Unique cue: one copy, paid or not.
		H.expect(Inventory.addUnique(save, "FireworkCue", 7, true), "a bought Unique")
		H.expect(Inventory.paidCount(save, "FireworkCue") == 1, "paid")
		H.expect(Inventory.removeCue(save, "FireworkCue"), "gone")
		H.expect(Inventory.removedPaid() == 1 and save.Inventory.PaidUnique.FireworkCue == nil, "")
		H.expect(Inventory.paidCount(save, "Nope") == 0, "unknown")
	end,

	["duplicates are block cues above one, in catalog order"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "EclipseCue", 2)
		Inventory.addCue(save, "MidnightCue", 3)
		Inventory.addCue(save, "HeritageCue")
		Inventory.addCue(save, "VipCue", 2) -- Exclusive: never a duplicate to sell
		local dups = Inventory.duplicates(save)
		H.expect(ids(dups) == "MidnightCue EclipseCue", "duplicates: " .. ids(dups))
		H.expect(dups[1].extra == 2 and dups[1].value == 300, "MidnightCue: 2 extra, $300")
		H.expect(dups[2].extra == 1 and dups[2].value == 25000000, "EclipseCue: 1 extra, $25M")
	end,

	["selling pays the section 8 value and leaves money to the caller"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "ChromaCue", 2)
		local ok, money = Inventory.sell(save, "ChromaCue")
		H.expect(ok and money == 250000, "a Legendary sells for $250,000: " .. tostring(money))
		H.expect(
			Inventory.count(save, "ChromaCue") == 1 and save.Money == 0,
			"one left, no money added"
		)
		ok, money = Inventory.sell(save, "ChromaCue", 2)
		H.expect(not ok and money == "TooMany", tostring(money))
		ok, money = Inventory.sell(save, "ChromaCue")
		H.expect(ok and money == 250000 and not Inventory.owns(save, "ChromaCue"), "the last one")
		H.expect(save.Index.Seen.ChromaCue == true, "still in the Index")

		-- Exclusive and Unique never sell, owned or not.
		Inventory.addCue(save, "VipCue")
		Inventory.addCue(save, "GoldCue")
		Inventory.addUnique(save, "BetaCue", 5)
		local expectations: { { any } } = {
			{ "VipCue", 1, "NotSellable" },
			{ "GoldCue", 1, "NotSellable" },
			{ "BetaCue", 1, "NotSellable" },
			{ "Classic", 1, "NotSellable" },
			{ "NeonCue", 1, "NotOwned" },
			{ "Nope", 1, "Unknown" },
			{ "HeritageCue", 0, "BadCount" },
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
		Inventory.addCue(save, "NeonCue", 3)
		H.expect(Inventory.equip(save, "NeonCue"), "equip")
		local ok, money = Inventory.sell(save, "NeonCue", 2)
		H.expect(ok and money == 3000, "sell down to one: " .. tostring(money))
		local can, reason = Inventory.canSell(save, "NeonCue")
		H.expect(not can and reason == "Equipped", "the last copy: " .. tostring(reason))
		H.expect(
			Inventory.count(save, "NeonCue") == 1 and Inventory.equipped(save) == "NeonCue",
			"kept"
		)
		Inventory.equip(save, "Classic")
		H.expect((Inventory.sell(save, "NeonCue")), "sells once something else is equipped")
	end,

	["sell all duplicates keeps one of each; one cue's extras alone"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "MidnightCue", 3) -- 2 x $150
		Inventory.addCue(save, "GummyCue", 2) -- 1 x $400
		Inventory.addCue(save, "VoidCue", 4) -- 3 x $25,000
		Inventory.addCue(save, "KitsuneCue") -- no extras
		Inventory.addCue(save, "StarterCue", 2) -- Exclusive: kept
		Inventory.equip(save, "VoidCue")

		local total, sold = Inventory.sellDuplicates(save, "GummyCue")
		H.expect(
			total == 400 and ids(sold) == "GummyCue" and sold[1].count == 1,
			"one cue: " .. total
		)
		H.expect(
			Inventory.count(save, "GummyCue") == 1 and Inventory.count(save, "MidnightCue") == 3,
			"only it"
		)

		total, sold = Inventory.sellDuplicates(save)
		H.expect(total == 300 + 75000, "all duplicates: " .. total)
		H.expect(ids(sold) == "MidnightCue VoidCue", "sold " .. ids(sold))
		for _, id in { "MidnightCue", "GummyCue", "VoidCue", "KitsuneCue" } do
			H.expect(Inventory.count(save, id) == 1, id .. " keeps one")
		end
		H.expect(Inventory.count(save, "StarterCue") == 2, "Exclusive untouched")
		H.expect(Inventory.equipped(save) == "VoidCue", "still equipped")
		H.expect(#Inventory.duplicates(save) == 0 and save.Money == 0, "none left, no money added")
		total, sold = Inventory.sellDuplicates(save)
		H.expect(total == 0 and #sold == 0, "nothing to sell")
	end,

	["equip needs the cue; losing the equipped last copy goes back to Classic"] = function()
		local Inventory = load()
		local save = newSave()
		H.expect(
			not Inventory.equip(save, "NeonCue") and save.Equipped.Cue == "Classic",
			"not owned"
		)
		H.expect(not Inventory.equip(save, "Nope"), "unknown")
		Inventory.addCue(save, "NeonCue")
		H.expect(Inventory.equip(save, "NeonCue") and save.Equipped.Cue == "NeonCue", "equipped")
		Inventory.removeCue(save, "NeonCue")
		H.expect(save.Equipped.Cue == "Classic", "back to Classic")
		-- A save that names a cue it doesn't hold reads as Classic.
		save.Equipped.Cue = "ChromaCue"
		H.expect(Inventory.equipped(save) == "Classic", "unowned equipped cue")
	end,

	["markSeen clears NEW tags once"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "MidnightCue")
		Inventory.addCue(save, "HeritageCue")
		local cleared = Inventory.markSeen(save, { "MidnightCue", "MidnightCue", 5, "Nope" })
		H.expect(cleared == 1, "cleared " .. cleared)
		H.expect(
			save.Inventory.New.MidnightCue == nil and save.Inventory.New.HeritageCue == true,
			"tags"
		)
		H.expect(
			Inventory.markSeen(save, nil) == 0 and Inventory.markSeen(save, "HeritageCue") == 0,
			"bad input"
		)
	end,

	["Index rows: totals, rewards from Config.Index, complete and claimed once"] = function()
		local Inventory, Catalog, Config = load()
		-- ECONOMY 18: money for the four lower rows; no titles (the designer dropped them,
		-- 2026-09-28), so the rows above Epic have no reward.
		local MONEY = { Common = 10000, Uncommon = 25000, Rare = 75000, Epic = 250000 }
		local TOTALS =
			-- Legendary 8: the seven block Legendaries and the Week One Cue (economy v5).
			{ Common = 8, Uncommon = 9, Rare = 10, Epic = 9, Legendary = 8, Mythic = 3, Secret = 1 }
		local save = newSave()
		local rows = Inventory.indexRows(save)
		local order = {}
		for _, row in rows do
			table.insert(order, row.rarity)
		end
		H.expect(
			table.concat(order, " ")
				== "Common Uncommon Rare Epic Legendary Mythic Secret Ranked Exclusive Unique",
			"row order: " .. table.concat(order, " ")
		)
		for _, row in rows do
			-- Classic is a Common everyone owns (designer, 2026-09-30): that row starts at 1.
			local starts = if row.rarity == "Common" then 1 else 0
			H.expect(
				row.have == starts and not row.complete and not row.claimed,
				row.rarity .. " starts empty"
			)
			if TOTALS[row.rarity] then
				H.expect(row.total == TOTALS[row.rarity], row.rarity .. " total")
			end
			if MONEY[row.rarity] then
				assert(row.reward, "no reward")
				H.expect(row.reward.money == MONEY[row.rarity], row.rarity .. " money")
				H.expect((row.reward :: any).title == nil, row.rarity .. " has no title")
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
			if cue.Id ~= "MidnightCue" then
				Inventory.sell(save, cue.Id)
			end
		end
		local common = Inventory.indexRows(save)[1]
		H.expect(
			common.have == 8 and common.complete and not common.claimed,
			"complete after selling"
		)
		local reward
		ok, reward = Inventory.claimRow(save, "Common")
		H.expect(
			ok and reward.money == 10000 and (reward :: any).title == nil,
			"the Common row pays $10,000, no title"
		)
		H.expect(save.Index.Rows.Common == true and next(save.Titles) == nil, "marked")
		H.expect(save.Money == 0, "money is the caller's to add")
		ok, why = Inventory.claimRow(save, "Common")
		H.expect(not ok and why == "Claimed", "only once: " .. tostring(why))
		H.expect(Inventory.indexRows(save)[1].claimed, "claimed")

		-- A complete row with no reward.
		for _, cue in Catalog.ofRarity("Legendary") do
			Inventory.addCue(save, cue.Id)
		end
		ok, why = Inventory.claimRow(save, "Legendary")
		H.expect(not ok and why == "NoReward", "Legendary: " .. tostring(why))

		ok, why = Inventory.claimRow(save, "Exclusive")
		H.expect(not ok and why == "NoReward", "Exclusive: " .. tostring(why))
		ok, why = Inventory.claimRow(save, "Ranked")
		H.expect(not ok and why == "NoReward", "Ranked: " .. tostring(why))
		ok, why = Inventory.claimRow(save, "Nope")
		H.expect(not ok and why == "Unknown", "unknown: " .. tostring(why))
		ok, why = Inventory.claimRow(save, 3)
		H.expect(not ok and why == "Unknown", "not a string")
	end,

	["a vaulted cue still counts toward its row; held cues count without Seen"] = function()
		local Inventory, Catalog = load()
		withVaulted(Catalog, "EclipseCue", function()
			local save = newSave()
			local secret = Inventory.indexRows(save)[7]
			H.expect(
				secret.rarity == "Secret" and secret.total == 1,
				"the vaulted Secret is still listed"
			)
			Inventory.addCue(save, "EclipseCue")
			H.expect(Inventory.indexRows(save)[7].complete, "and completes the row")
		end)
		-- A save whose Seen was never filled in (an old layout) still counts what it holds.
		local old = newSave()
		old.Inventory.Cues.KitsuneCue = 1
		H.expect(Inventory.indexRows(old)[6].have == 1, "held but not Seen")
	end,

	["the rank cues sort together, highest tier first (designer, 2026-10-08)"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "SilverCue")
		Inventory.addCue(save, "VipCue")
		Inventory.addCue(save, "ReyesCue")
		Inventory.addCue(save, "PhoenixCue")
		Inventory.addCue(save, "MagmaCue")
		Inventory.addCue(save, "BronzeCue")
		Inventory.addCue(save, "DiamondCue")
		local snap = Inventory.snapshot(save)
		H.expect(
			ids(snap.cues)
				== "PhoenixCue ReyesCue DiamondCue SilverCue BronzeCue VipCue MagmaCue Classic",
			"cues: " .. ids(snap.cues)
		)
	end,

	["snapshot is plain data in a fixed order"] = function()
		local Inventory = load()
		local save = newSave()
		Inventory.addCue(save, "HeritageCue", 2)
		Inventory.addCue(save, "MidnightCue")
		Inventory.addCue(save, "EclipseCue")
		Inventory.addCue(save, "NeonCue")
		Inventory.addCue(save, "GoldCue")
		Inventory.addUnique(save, "BetaCue", 412)
		Inventory.equip(save, "NeonCue")
		Inventory.markSeen(save, { "HeritageCue" })
		Inventory.sell(save, "MidnightCue") -- sold: gone from cues, still seen
		save.Titles.FirstReyes = true
		save.Titles.Epic = true -- an old Collector title: left out
		save.Titles.NotATitle = true -- unknown ids are left out
		save.Inventory.Cues.Bogus = 4 -- stray keys are ignored

		local snap = Inventory.snapshot(save)
		expectPlain(snap, "snapshot", tablesIn(save, {}))
		H.expect(
			ids(snap.cues) == "BetaCue EclipseCue GoldCue NeonCue Classic HeritageCue",
			"cues: " .. ids(snap.cues)
		)
		H.expect(snap.cues[1].copy == 412 and snap.cues[1].new == true, "BetaCue #412, new")
		H.expect(snap.cues[6].count == 2 and snap.cues[6].new == false, "HeritageCue x2, seen")
		H.expect(snap.cues[5].count == 1 and snap.cues[5].copy == nil, "Classic")
		H.expect((snap :: any).cases == nil and (snap :: any).timers == nil, "no case fields")
		H.expect(snap.equipped == "NeonCue", "equipped")
		H.expect(
			ids(snap.seen) == "Classic MidnightCue HeritageCue NeonCue EclipseCue GoldCue BetaCue",
			"seen: " .. ids(snap.seen)
		)
		H.expect(
			table.concat(snap.titles, " ") == "FirstReyes",
			"titles: " .. table.concat(snap.titles, " ")
		)
		H.expect(#snap.rows == 10, "rows")

		-- Changing the save afterwards never reaches a snapshot already taken.
		Inventory.addCue(save, "NeonCue")
		H.expect(snap.cues[4].count == 1, "the snapshot is a copy")
	end,
}
