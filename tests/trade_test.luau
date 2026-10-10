--!strict
-- Trading's pure rules (Progression/Trade): what may trade, the atomic swap with paid origin and
-- Unique numbers kept, the history, the ledger's replay, and the lopsided warning (the approved
-- economy plan, 2026-10-02, section 9; designer, 2026-10-03).

local H = require("./harness")

local function load()
	return H.require("Progression.Trade"),
		H.require("Progression.Inventory"),
		H.require("Progression.SaveSchema"),
		H.require("Config"),
		H.require("Progression.LuckyBlocks")
end

-- The unix time every trade here runs at.
local NOW = 1800000000

local function newSave(): any
	local _, _, SaveSchema = load()
	return SaveSchema.template()
end

-- A block of `kind` that is ready at NOW (it landed long ago), paid or free, climbed or not.
local function readyBlock(save: any, kind: string, paid: boolean?, climbed: boolean?)
	local LuckyBlocks = select(5, load())
	return LuckyBlocks.add(save.LuckyBlocks, kind, NOW - 7 * 86400, nil, paid, nil, climbed)
end

local function blocksOf(save: any, kind: string): number
	local LuckyBlocks = select(5, load())
	return LuckyBlocks.count(save.LuckyBlocks, kind)
end

return {
	["offerable: tradable cues and ready blocks, free copies only without paidOk"] = function()
		local Trade, Inventory, _, _, LuckyBlocks = load()
		local a = newSave()
		Inventory.addCue(a, "NeonCue", 2)
		Inventory.addCue(a, "NeonCue", 1, true)
		Inventory.addCue(a, "ChromaCue", 1, true)
		Inventory.addCue(a, "VipCue")
		readyBlock(a, "Rare")
		readyBlock(a, "Rare")
		readyBlock(a, "Rare", true) -- bought: only with paidOk
		readyBlock(a, "Rare", false, true) -- climbed: its own item (economy v5)
		LuckyBlocks.add(a.LuckyBlocks, "Epic", NOW, nil, nil, nil, true) -- climbed, on its timer
		local function countOf(list: { any }, item: string): number
			for _, e in list do
				if e.item == item then
					return e.count
				end
			end
			return 0
		end
		local all = Trade.offerable(a, true, NOW)
		H.expect(countOf(all, "NeonCue") == 3, "every Neon copy")
		H.expect(countOf(all, "ChromaCue") == 1, "the paid Chroma")
		H.expect(countOf(all, "Block:Rare") == 3, "three ready unclimbed Rare blocks")
		H.expect(countOf(all, "Climbed:Rare") == 1, "the climbed Rare block, apart")
		H.expect(countOf(all, "Climbed:Epic") == 0, "a block on its timer is not offerable")
		H.expect(countOf(all, "VipCue") == 0, "an Exclusive cue never trades")
		H.expect(countOf(all, "Classic") == 0, "Classic never trades")
		local free = Trade.offerable(a, false, NOW)
		H.expect(countOf(free, "NeonCue") == 2, "free Neon copies only")
		H.expect(countOf(free, "ChromaCue") == 0, "no paid Chroma")
		H.expect(countOf(free, "Block:Rare") == 2, "free Rare blocks only")
		-- Six hours on, the Epic block is ready and offerable too.
		local later = Trade.offerable(a, true, NOW + 6 * 3600)
		H.expect(countOf(later, "Climbed:Epic") == 1, "ready now")
		-- An unclimbed block waits its own name's timer (economy v5.2), then trades.
		LuckyBlocks.add(a.LuckyBlocks, "Legendary", NOW)
		H.expect(countOf(Trade.offerable(a, true, NOW), "Block:Legendary") == 0, "on its timer")
		H.expect(
			countOf(Trade.offerable(a, true, NOW + 12 * 3600), "Block:Legendary") == 1,
			"ready after 12 hours (economy v6)"
		)
	end,
	["items: cue ids and ready blocks, at most 8 a side"] = function()
		local Trade = load()
		local ok = Trade.parse({ "NeonCue", "Block:Rare", "NeonCue" })
		H.expect(ok ~= nil and #ok == 3, "three entries")
		H.expect(Trade.parse({}) ~= nil, "an empty side parses (refused at the swap)")
		for _, bad in
			{
				"NeonCue",
				{ "Nope" },
				{ "Block:Nope" },
				{ "Case:Rare" },
				{ 5 },
				{ [2] = "NeonCue" },
				{ x = "NeonCue" },
				table.create(9, "NeonCue"),
			} :: { any }
		do
			local items, why = Trade.parse(bad)
			H.expect(items == nil and why == "BadRequest", "bad side")
		end
		H.expect(Trade.blockItem("Epic") == "Block:Epic", "a block's item")
		H.expect(Trade.blockItem("Epic", true) == "Climbed:Epic", "a climbed block's item")
		H.expect(Trade.parse({ "Climbed:Epic" }) ~= nil, "a climbed block tier trades")
		H.expect(Trade.parse({ "Climbed:Mystery" }) == nil, "only block tiers are climbed")
		H.expect(Trade.parse({ "Climbed:Secret" }) == nil, "no Secret block")
		local kind, climbed = Trade.itemBlock("Climbed:Rare")
		H.expect(kind == "Rare" and climbed, "itemBlock: a climbed Rare")
		kind, climbed = Trade.itemBlock("Block:Rare")
		H.expect(kind == "Rare" and not climbed, "itemBlock: an unclimbed Rare")
		H.expect(Trade.itemBlock("NeonCue") == nil, "itemBlock: a cue is no block")
		H.expect(Trade.parse({ "Block:Mystery" }) ~= nil, "a Mystery block trades once ready")
		H.expect(Trade.tradable("NeonCue") and Trade.tradable("FireworkCue"), "block, Unique")
		H.expect(Trade.tradable("StarterCue"), "the Starter Cue may")
		H.expect(not Trade.tradable("VipCue") and not Trade.tradable("GoldCue"), "Exclusive never")
		H.expect(not Trade.tradable("Classic"), "Classic never")
	end,

	["a swap moves both sides together, free copies first, paid origin kept"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 2)
		Inventory.addCue(a, "NeonCue", 1, true) -- one paid
		readyBlock(a, "Rare")
		Inventory.addCue(b, "ChromaCue", 1, true)
		local ok, why, fromA, fromB = Trade.swap(
			a,
			b,
			{ "NeonCue", "NeonCue", "Block:Rare" },
			{ "ChromaCue" },
			true,
			NOW
		)
		H.expect(ok and why == nil, tostring(why))
		assert(fromA and fromB, "moved")
		H.expect(fromA[1].item == "NeonCue" and fromA[1].count == 2 and fromA[1].paid == 0, "free")
		H.expect(fromA[2].item == "Block:Rare" and fromA[2].paid == 0, "the block")
		H.expect(Inventory.count(a, "NeonCue") == 1 and Inventory.paidCount(a, "NeonCue") == 1, "")
		H.expect(Inventory.count(b, "NeonCue") == 2 and blocksOf(b, "Rare") == 1, "got")
		H.expect(blocksOf(a, "Rare") == 0, "the block left")
		local landed = b.LuckyBlocks.List[1]
		H.expect(landed.Kind == "Rare" and landed.ReadyAt == NOW and not landed.Paid, "ready now")
		H.expect(
			Inventory.count(a, "ChromaCue") == 1 and Inventory.paidCount(a, "ChromaCue") == 1,
			""
		)
		H.expect(Inventory.found(b, "NeonCue") and a.Money == 0 and b.Money == 0, "no money")
	end,

	["a climbed block arrives climbed, an unclimbed one unclimbed"] = function()
		local Trade, Inventory, _, _, LuckyBlocks = load()
		local a, b = newSave(), newSave()
		readyBlock(a, "Epic", false, true)
		readyBlock(a, "Rare")
		Inventory.addCue(b, "NeonCue", 1)
		local ok = Trade.swap(a, b, { "Climbed:Epic", "Block:Rare" }, { "NeonCue" }, true, NOW)
		H.expect(ok, "swapped")
		local epic, rare
		for _, block in b.LuckyBlocks.List do
			if block.Kind == "Epic" then
				epic = block
			elseif block.Kind == "Rare" then
				rare = block
			end
		end
		H.expect(epic ~= nil and LuckyBlocks.unclimbed(epic) == false, "the Epic stays climbed")
		H.expect(epic ~= nil and LuckyBlocks.isReady(epic, NOW), "and ready at once")
		H.expect(rare ~= nil and LuckyBlocks.unclimbed(rare), "the Rare still climbs")
	end,

	["refusals change nothing"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 1)
		Inventory.addCue(b, "MidnightCue", 1, true)
		local function refused(itemsA: { string }, itemsB: { string }, paidOk: boolean): string?
			local ok, why = Trade.swap(a, b, itemsA, itemsB, paidOk, NOW)
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
		H.expect(refused({ "Block:Rare" }, { "MidnightCue" }, true) == "NotOwned", "no block")
		-- A climbed block on its timer is not ready, so not tradable; nor as an unclimbed one.
		local _, _, _, _, LuckyBlocks = load()
		LuckyBlocks.add(a.LuckyBlocks, "Rare", NOW, nil, nil, nil, true)
		H.expect(refused({ "Climbed:Rare" }, { "MidnightCue" }, true) == "NotOwned", "on its timer")
		H.expect(blocksOf(a, "Rare") == 1, "the block stays")
		readyBlock(a, "Rare", false, true)
		H.expect(refused({ "Block:Rare" }, { "MidnightCue" }, true) == "NotOwned", "not unclimbed")
		-- A bought block only moves with paidOk.
		readyBlock(a, "Epic", true)
		H.expect(refused({ "Block:Epic" }, { "MidnightCue" }, false) == "PaidBlocked", "paid block")
		-- An unopened paid block never goes to (or from) a player whose paid random items are
		-- restricted (economy v4), even where paid items may trade; paid cues still may.
		local ok, why = Trade.swap(a, b, { "Block:Epic" }, { "MidnightCue" }, true, NOW, false)
		H.expect(not ok and why == "PaidBlocked", "a paid block to a restricted player")
		H.expect(blocksOf(a, "Epic") == 1, "the paid block stays")
		local offer = Trade.offerable(a, true, NOW, false)
		for _, entry in offer do
			H.expect(entry.item ~= "Block:Epic", "not offered where restricted")
		end
		H.expect(Trade.canGive(b, { "MidnightCue" }, true, NOW, false) == nil, "a paid cue may")
		-- The Starter Cue may trade, but not to someone who has one.
		Inventory.addCue(a, "StarterCue")
		Inventory.addCue(b, "StarterCue")
		H.expect(refused({ "StarterCue" }, { "MidnightCue" }, true) == "Owned", "one each")
	end,

	["a Unique keeps its number; one per player"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addUnique(a, "FireworkCue", 42, true)
		Inventory.addCue(b, "NeonCue")
		local ok, _, fromA = Trade.swap(a, b, { "FireworkCue" }, { "NeonCue" }, true, NOW)
		H.expect(ok and fromA ~= nil and fromA[1].copy == 42 and fromA[1].paid == 1, "moved")
		H.expect(Inventory.copy(b, "FireworkCue") == 42, "#42 kept")
		H.expect(Inventory.paidCount(b, "FireworkCue") == 1, "paid origin kept")
		H.expect(not Inventory.owns(a, "FireworkCue"), "gone")
		local c = newSave()
		Inventory.addUnique(c, "FireworkCue", 7)
		Inventory.addCue(b, "NeonCue")
		local no, why = Trade.swap(c, b, { "FireworkCue" }, { "NeonCue" }, true, NOW)
		H.expect(not no and why == "Owned", "b holds one already")
	end,

	["the designer's unnumbered owner copy never trades"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		a.Inventory.OwnerUnique = {}
		Inventory.addOwnerCopy(a, "FireworkCue")
		Inventory.addCue(b, "NeonCue")
		H.expect(Trade.canGive(a, { "FireworkCue" }, true, NOW) == "NotOwned", "can't give")
		for _, row in Trade.offerable(a, true, NOW) do
			H.expect(row.item ~= "FireworkCue", "not offered")
		end
		local ok = Trade.swap(a, b, { "FireworkCue" }, { "NeonCue" }, true, NOW)
		H.expect(not ok and Inventory.isOwnerCopy(a, "FireworkCue"), "kept")
	end,

	["the history and applied ids, capped"] = function()
		local Trade, _, _, Config = load()
		local save = newSave()
		local gave = { { item = "NeonCue", count = 2, paid = 0 } }
		local got = { { item = "Block:Rare", count = 1, paid = 0 } }
		for i = 1, Config.Save.MaxTradeHistory + 3 do
			Trade.record(save, "t" .. i, 99, 1000 + i, gave, got)
		end
		local h = save.Trades.History
		H.expect(#h == Config.Save.MaxTradeHistory and h[1].Id == "t4", "the last 50")
		H.expect(#h[1].Gave == 2 and h[1].Got[1] == "Block:Rare" and h[1].With == 99, "entries")
		H.expect(Trade.applied(save, "t53") and not Trade.applied(save, "nope"), "applied")
		local _, _, SaveSchema = load()
		local _, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 0, "a valid save: " .. table.concat(fixes, "; "))
	end,

	["replay: a save that missed the swap applies its side once"] = function()
		local Trade, Inventory = load()
		local a, b = newSave(), newSave()
		Inventory.addCue(a, "NeonCue", 2)
		readyBlock(a, "Rare")
		Inventory.addUnique(b, "FireworkCue", 3)
		-- The swap ran (here on stand-in saves) and the ledger kept what moved; both real saves
		-- lost it in a crash, so each replays its side on its next load.
		local planA, planB = newSave(), newSave()
		Inventory.addCue(planA, "NeonCue", 2)
		readyBlock(planA, "Rare")
		Inventory.addUnique(planB, "FireworkCue", 3)
		local ok, _, fromA, fromB = Trade.swap(
			planA,
			planB,
			{ "NeonCue", "Block:Rare" },
			{ "FireworkCue" },
			true,
			NOW
		)
		assert(ok and fromA and fromB, "planned")
		local entry = { id = "T1", at = 5000, a = 1, b = 2, fromA = fromA, fromB = fromB }
		H.expect(Trade.replay(a, entry, 1, NOW), "a replays")
		H.expect(Inventory.count(a, "NeonCue") == 1 and Inventory.copy(a, "FireworkCue") == 3, "")
		H.expect(blocksOf(a, "Rare") == 0, "the block went")
		H.expect(not Trade.replay(a, entry, 1, NOW), "once")
		H.expect(Trade.replay(b, entry, 2, NOW), "b replays")
		H.expect(Inventory.count(b, "NeonCue") == 1 and not Inventory.owns(b, "FireworkCue"), "")
		H.expect(blocksOf(b, "Rare") == 1 and b.LuckyBlocks.List[1].ReadyAt == NOW, "ready")
		H.expect(not Trade.replay(newSave(), entry, 3, NOW), "not in it")
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
		-- A trade in flight across a rename lands on the new id (Config.Items.RenamedCues).
		local across = Trade.entries({
			entries = {
				{
					id = "T9",
					at = 1,
					a = 1,
					b = 2,
					fromA = { { item = "GrandOpeningCue", count = 1, paid = 0, copy = 4 } },
					fromB = { { item = "NeonCue", count = 1, paid = 0 } },
				},
			},
		})
		H.expect(across[1].fromA[1].item == "FireworkCue", "renamed in flight")
		H.expect(across[1].fromB[1].item == "NeonCue", "others untouched")
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
		H.expect(Trade.lopsided({ "Block:Mythic" }, { "Block:Standard" }, copies) == "A", "blocks")
		H.expect(Trade.lopsided({ "Block:Mystery" }, { "Block:Standard" }, copies) == nil, "near")
		H.expect(Trade.lopsided({}, { "NeonCue" }, copies) == nil, "an empty side: no warning")
		-- Until every cue's count is known, a block's worth is 1 / Config.Trade.BlockExists.
		H.expect(Trade.blockWorth("Rare", copies) == nil, "counts unknown: the fallback")
	end,

	["a block's worth is worked out live from its odds and the copies of each cue"] = function()
		local Trade = load()
		local Catalog = H.require("Progression.Catalog")
		-- Every cue at 1,000 copies, except the Secret at 10: a block's worth follows its odds.
		local copies: { [string]: number } = {}
		for _, cue in Catalog.list() do
			copies[cue.Id] = if cue.Rarity == "Secret" then 10 else 1000
		end
		local rare = Trade.blockWorth("Rare", copies) :: number
		H.expect(rare ~= nil and rare > 0, "known")
		-- An unclimbed Rare block climbs from Rare (economy v6 steps): it reaches the Secret
		-- 10% x 15% x 10% x 2.5% = 0.00375% of the time, every other cue at 1 / 1,000.
		local secret = 0.10 * 0.15 * 0.10 * 0.025
		H.near(rare, (1 - secret) / 1000 + secret / 10, 1e-12, "the Rare climb's worth")
		-- A climbed Rare block is exactly a Rare cue.
		H.near(Trade.blockWorth("Rare", copies, true) :: number, 1 / 1000, 1e-15, "climbed Rare")
		H.expect(
			(Trade.blockWorth("Lucky8", copies) :: number) < rare,
			"Lucky 8 climbs from Uncommon"
		)
		local mythic = Trade.blockWorth("Mythic", copies) :: number
		H.expect(mythic > rare, "a Mythic block's 2.5% Secret is worth more")
		-- As copies of a rarity grow, blocks that give it are worth less (the v4 plan's reason).
		local more = table.clone(copies)
		for _, cue in Catalog.list() do
			if cue.Rarity == "Secret" then
				more[cue.Id] = 1000
			end
		end
		H.expect((Trade.blockWorth("Mythic", more) :: number) < mythic, "worth falls with supply")
		local mystery = Trade.blockWorth("Mystery", copies) :: number
		H.expect(mystery > 0 and mystery < rare, "a Mystery block: mostly Standard and Uncommon")
		H.expect(Trade.blockWorth("Nope", copies) == nil, "unknown kind")
	end,
	["until the counts load, the model's day-30 fallback: unclimbed and climbed apart"] = function()
		local Trade, _, _, Config = load()
		local T = Config.Trade
		-- Every block kind that trades has a fallback, and every block tier a climbed one.
		for _, kind in Config.LuckyBlocks.Order do
			H.expect((T.BlockExists :: any)[kind] ~= nil, kind .. ": BlockExists")
		end
		for _, tier in Config.BlockOdds.Order do
			H.expect((T.ClimbedExists :: any)[tier] ~= nil, tier .. ": ClimbedExists")
		end
		-- A climbed Mythic block (exactly a Mythic cue) is worth more than an unclimbed Rare one,
		-- and an unclimbed Legendary block less than a climbed one (it may stay Legendary).
		H.expect(
			Trade.lopsided({ "Climbed:Mythic" }, { "Block:Rare" }, {}) == "A",
			"a climbed Mythic far above a Rare start"
		)
		H.expect(
			(T.ClimbedExists :: any).Legendary > (T.BlockExists :: any).Legendary,
			"an unclimbed Legendary may climb: worth more than a climbed one"
		)
	end,
}
