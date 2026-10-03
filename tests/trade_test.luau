--!strict
-- Trading's pure rules (Progression/Trade): what may trade, the atomic swap with paid origin and
-- Unique numbers kept, the history, the ledger's replay, and the lopsided warning (the approved
-- economy plan, 2026-10-02, section 9; designer, 2026-10-03).

local H = require("./harness")

local function load()
	return H.require("Progression.Trade"),
		H.require("Progression.Inventory"),
		H.require("Progression.SaveSchema"),
		H.require("Config")
end

local function newSave(): any
	local _, _, SaveSchema = load()
	return SaveSchema.template()
end

return {
	["items: cue ids and ready cases, at most 8 a side"] = function()
		local Trade = load()
		local ok = Trade.parse({ "NeonCue", "Case:Rare", "NeonCue" })
		H.expect(ok ~= nil and #ok == 3, "three entries")
		H.expect(Trade.parse({}) ~= nil, "an empty side parses (refused at the swap)")
		for _, bad in
			{
				"NeonCue",
				{ "Nope" },
				{ "Case:Nope" },
				{ 5 },
				{ [2] = "NeonCue" },
				{ x = "NeonCue" },
				table.create(9, "NeonCue"),
			} :: { any }
		do
			local items, why = Trade.parse(bad)
			H.expect(items == nil and why == "BadRequest", "bad side")
		end
		H.expect(Trade.caseItem("Epic") == "Case:Epic", "a case's item")
		H.expect(Trade.tradable("NeonCue") and Trade.tradable("GrandOpeningCue"), "case, Unique")
		H.expect(Trade.tradable("StarterCue"), "the Starter Cue may")
		H.expect(not Trade.tradable("VipCue") and not Trade.tradable("GoldCue"), "Exclusive never")
		H.expect(not Trade.tradable("Classic"), "Classic never")
	end,

	["a swap moves both sides together, free copies first, paid origin kept"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 2)
		Inventory.addCue(a, "NeonCue", 1, true) -- one paid
		Inventory.addCases(a, "Rare", 1)
		Inventory.addCue(b, "ChromaCue", 1, true)
		local ok, why, fromA, fromB = Trade.swap(
			a,
			b,
			{ "NeonCue", "NeonCue", "Case:Rare" },
			{ "ChromaCue" },
			true
		)
		H.expect(ok and why == nil, tostring(why))
		assert(fromA and fromB, "moved")
		H.expect(fromA[1].item == "NeonCue" and fromA[1].count == 2 and fromA[1].paid == 0, "free")
		H.expect(fromA[2].item == "Case:Rare" and fromA[2].paid == 0, "the case")
		H.expect(Inventory.count(a, "NeonCue") == 1 and Inventory.paidCount(a, "NeonCue") == 1, "")
		H.expect(Inventory.count(b, "NeonCue") == 2 and Inventory.caseCount(b, "Rare") == 1, "got")
		H.expect(
			Inventory.count(a, "ChromaCue") == 1 and Inventory.paidCount(a, "ChromaCue") == 1,
			""
		)
		H.expect(Inventory.found(b, "NeonCue") and a.Money == 0 and b.Money == 0, "no money")
	end,

	["refusals change nothing"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 1)
		Inventory.addCue(b, "MidnightCue", 1, true)
		local function refused(itemsA: { string }, itemsB: { string }, paidOk: boolean): string?
			local ok, why = Trade.swap(a, b, itemsA, itemsB, paidOk)
			H.expect(not ok, "refused")
			H.expect(
				Inventory.count(a, "NeonCue") == 1 and Inventory.count(b, "MidnightCue") == 1,
				""
			)
			return why
		end
		H.expect(refused({ "NeonCue" }, {}, true) == "Empty", "no gifts")
		H.expect(refused({}, { "MidnightCue" }, true) == "Empty", "no gifts either way")
		H.expect(refused({ "NeonCue", "NeonCue" }, { "MidnightCue" }, true) == "NotOwned", "two")
		H.expect(refused({ "NeonCue" }, { "MidnightCue" }, false) == "PaidBlocked", "paid copy")
		H.expect(refused({ "Classic" }, { "MidnightCue" }, true) == "NotTradable", "Classic")
		Inventory.addCue(a, "VipCue")
		H.expect(refused({ "VipCue" }, { "MidnightCue" }, true) == "NotTradable", "Exclusive")
		H.expect(refused({ "Case:Rare" }, { "MidnightCue" }, true) == "NotOwned", "no case")
		-- A case on its timer is not ready, so not tradable.
		Inventory.landCase(a, "Rare", 1000, false, false)
		H.expect(refused({ "Case:Rare" }, { "MidnightCue" }, true) == "NotOwned", "on its timer")
		-- The Starter Cue may trade, but not to someone who has one.
		Inventory.addCue(a, "StarterCue")
		Inventory.addCue(b, "StarterCue")
		H.expect(refused({ "StarterCue" }, { "MidnightCue" }, true) == "Owned", "one each")
	end,

	["a Unique keeps its number; one per player"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addUnique(a, "GrandOpeningCue", 42, true)
		Inventory.addCue(b, "NeonCue")
		local ok, _, fromA = Trade.swap(a, b, { "GrandOpeningCue" }, { "NeonCue" }, true)
		H.expect(ok and fromA ~= nil and fromA[1].copy == 42 and fromA[1].paid == 1, "moved")
		H.expect(Inventory.copy(b, "GrandOpeningCue") == 42, "#42 kept")
		H.expect(Inventory.paidCount(b, "GrandOpeningCue") == 1, "paid origin kept")
		H.expect(not Inventory.owns(a, "GrandOpeningCue"), "gone")
		local c = newSave()
		Inventory.addUnique(c, "GrandOpeningCue", 7)
		Inventory.addCue(b, "NeonCue")
		local no, why = Trade.swap(c, b, { "GrandOpeningCue" }, { "NeonCue" }, true)
		H.expect(not no and why == "Owned", "b holds one already")
	end,

	["the history and applied ids, capped"] = function()
		local Trade, _, _, Config = load()
		local save = newSave()
		local gave = { { item = "NeonCue", count = 2, paid = 0 } }
		local got = { { item = "Case:Rare", count = 1, paid = 0 } }
		for i = 1, Config.Save.MaxTradeHistory + 3 do
			Trade.record(save, "t" .. i, 99, 1000 + i, gave, got)
		end
		local h = save.Trades.History
		H.expect(#h == Config.Save.MaxTradeHistory and h[1].Id == "t4", "the last 50")
		H.expect(#h[1].Gave == 2 and h[1].Got[1] == "Case:Rare" and h[1].With == 99, "entries")
		H.expect(Trade.applied(save, "t53") and not Trade.applied(save, "nope"), "applied")
		local _, _, SaveSchema = load()
		local _, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 0, "a valid save: " .. table.concat(fixes, "; "))
	end,

	["replay: a save that missed the swap applies its side once"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 2)
		Inventory.addUnique(b, "GrandOpeningCue", 3)
		-- The swap ran (here on stand-in saves) and the ledger kept what moved; both real saves
		-- lost it in a crash, so each replays its side on its next load.
		local planA, planB = newSave(), newSave()
		Inventory.addCue(planA, "NeonCue", 2)
		Inventory.addUnique(planB, "GrandOpeningCue", 3)
		local ok, _, fromA, fromB = Trade.swap(
			planA,
			planB,
			{ "NeonCue" },
			{ "GrandOpeningCue" },
			true
		)
		assert(ok and fromA and fromB, "planned")
		local entry = { id = "T1", at = 5000, a = 1, b = 2, fromA = fromA, fromB = fromB }
		H.expect(Trade.replay(a, entry, 1), "a replays")
		H.expect(
			Inventory.count(a, "NeonCue") == 1 and Inventory.copy(a, "GrandOpeningCue") == 3,
			""
		)
		H.expect(not Trade.replay(a, entry, 1), "once")
		H.expect(Trade.replay(b, entry, 2), "b replays")
		H.expect(
			Inventory.count(b, "NeonCue") == 1 and not Inventory.owns(b, "GrandOpeningCue"),
			""
		)
		H.expect(not Trade.replay(newSave(), entry, 3), "not in it")
		H.expect(a.Trades.History[1].With == 2 and b.Trades.History[1].With == 1, "partners")
	end,

	["the ledger key: add once, remove, capped"] = function()
		local Trade, _, _, Config = load()
		local e = { id = "T1", at = 1, a = 1, b = 2, fromA = {}, fromB = {} }
		local stored = Trade.addEntry(nil, e)
		H.expect(stored ~= nil and #Trade.entries(stored) == 1, "added")
		H.expect(Trade.addEntry(stored, e) == nil, "once")
		local gone = Trade.removeEntry(stored, "T1")
		H.expect(gone ~= nil and #gone.entries == 0, "removed")
		H.expect(Trade.removeEntry(gone, "T1") == nil, "nothing to remove")
		local many: any = nil
		for i = 1, Config.Trade.MaxPending + 2 do
			many = Trade.addEntry(
				many,
				{ id = "T" .. i, at = i, a = 1, b = 2, fromA = {}, fromB = {} }
			)
		end
		local list = Trade.entries(many)
		H.expect(#list == Config.Trade.MaxPending and list[1].id == "T3", "the oldest go")
		H.expect(#Trade.entries({ entries = { 5, { id = 1 } } }) == 0, "junk dropped")
	end,

	["the lopsided warning by N exist"] = function()
		local Trade = load()
		local copies = { NeonCue = 5000, EclipseCue = 3, ChromaCue = 400 }
		H.expect(Trade.lopsided({ "NeonCue" }, { "NeonCue" }, copies) == nil, "even")
		H.expect(Trade.lopsided({ "EclipseCue" }, { "NeonCue" }, copies) == "A", "A far more")
		H.expect(Trade.lopsided({ "NeonCue" }, { "ChromaCue" }, copies) == "B", "B far more")
		H.expect(
			Trade.lopsided({ "NeonCue", "NeonCue", "NeonCue", "NeonCue" }, { "NeonCue" }, copies)
				== nil,
			"four times is not more than four times"
		)
		H.expect(Trade.lopsided({ "Case:Mythic" }, { "Case:Standard" }, copies) == "A", "cases")
		H.expect(Trade.lopsided({}, { "NeonCue" }, copies) == nil, "an empty side: no warning")
	end,
}
