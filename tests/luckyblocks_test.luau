--!strict
-- Lucky blocks (Progression/LuckyBlocks; the test build, designer 2026-10-03): the kinds point
-- at real odds rows, timers and readiness, the hotbar order (add, remove, move), the client's copy,
-- the countdown text and BlockRequest's argument checks.

local H = require("./harness")

local function load()
	return H.require("Progression.LuckyBlocks"),
		H.require("Config"),
		H.require("Progression.BlockOdds")
end

return {
	["new block tiers use the requested odds and timers"] = function()
		local L, Config = load()
		for _, row in
			{
				-- The designer's timers (2026-10-07).
				{ "Standard", "Standard", 0 },
				{ "Uncommon", "Uncommon", 60 },
				{ "Rare", "Rare", 300 },
				{ "Epic", "Epic", 1800 }, -- economy v4 (2026-10-08): 30 minutes
				{ "Legendary", "Legendary", 21600 },
				{ "Mythic", "Mythic", 43200 },
				{ "Gift", "Rare", 43200 },
			}
		do
			H.expect(L.kind(row[1]).Odds == row[2] and L.timer(row[1]) == row[3], row[1])
		end
		-- VIP has no timers (Config.LuckyBlocks.VipTimerFactor 0, designer 2026-10-07); the
		-- Mystery block rolls a tier first (no odds row of its own).
		H.expect(Config.LuckyBlocks.VipTimerFactor == 0, "no VIP timers")
		H.expect(L.timer("Rare", true) == 0 and L.timer("Standard", true) == 0, "VIP: none")
		H.expect(L.timer("Mythic", true) == 0 and L.timer("Mythic") == 43200, "12 h, or none")
		-- Everything else has no timer, the Mystery block too.
		for _, kind in { "Mystery", "GrandOpening", "Starter", "Sky", "Lucky8" } do
			H.expect(L.timer(kind) == 0, kind .. " opens at once")
		end
		-- Timers already running when VIP arrives finish at once.
		local state = L.fresh()
		L.add(state, "Mythic", 100)
		L.add(state, "Standard", 100)
		H.expect(L.finishTimers(state, 200) == 1, "only the one still waiting")
		H.expect(L.isReady(state.List[1], 200) and state.List[1].Paid == nil, "ready, not paid")
		H.expect(L.kind("Mystery").Roll == true and L.kind("Mystery").Odds == nil, "Mystery")
		-- The old saved ids map to the new kinds (Config.LuckyBlocks.Renamed).
		H.expect(L.current("Yellow") == "Standard" and L.current("GoldKing") == "Legendary", "")
		H.expect(L.kind("Blue").Odds == "Rare" and L.current("Rare") == "Rare", "renamed")
	end,
	["the Grand Opening block's guarantee: the 1,000th open gives the Beta Cue if none"] = function()
		local L = load()
		local state = L.fresh()
		local function none(_: string): boolean
			return false
		end
		local function has(_: string): boolean
			return true
		end
		H.expect(L.opened(state, "GrandOpening") == 0, "none opened")
		H.expect(L.guaranteed(state, "GrandOpening", none) == nil, "the first: a roll")
		for _ = 1, 998 do
			L.noteOpened(state, "GrandOpening")
		end
		H.expect(L.opened(state, "GrandOpening") == 998, "counted")
		H.expect(L.guaranteed(state, "GrandOpening", none) == nil, "the 999th: a roll")
		L.noteOpened(state, "GrandOpening")
		H.expect(
			L.guaranteed(state, "GrandOpening", none) == "BetaCue",
			"the 1,000th: the Beta Cue"
		)
		H.expect(L.guaranteed(state, "GrandOpening", has) == nil, "owned already: a roll")
		H.expect(L.guaranteed(state, "Standard", none) == nil, "no guarantee")
		-- A paid block is ready at once and keeps its paid origin.
		local paid = L.add(state, "GrandOpening", 1000, nil, true)
		H.expect(paid.ReadyAt == 1000 and paid.Paid == true, "paid: ready now")
	end,
	["only the designer can bypass an unchanged countdown"] = function()
		local L = load()
		local b = L.add(L.fresh(), "Legendary", 1000)
		H.expect(not L.canOpen(b, 1001, 1234), "another account cannot bypass")
		H.expect(L.canOpen(b, 1001, 544959133), "designer can open")
		H.expect(b.ReadyAt == 22600, "bypass does not erase the timer")
	end,
	["late skip receipt preserves value and saved target across reconnect"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local b = L.add(save.LuckyBlocks, "Epic", 1000)
		save.LuckyBlocks.SkipTarget = b.Id
		local restored = Schema.validate(save)
		L.grantSkip(restored.LuckyBlocks, 1001)
		local skipped = L.find(restored.LuckyBlocks, b.Id)
		H.expect(
			skipped.ReadyAt == 1001 and skipped.Paid,
			"selected timer finished and paid origin retained"
		)
		H.expect(restored.LuckyBlocks.SkipCredits == 0, "one credit spent")
		L.grantSkip(restored.LuckyBlocks, 1002)
		H.expect(restored.LuckyBlocks.SkipCredits == 1, "no running target: credit retained")
		H.expect(not L.useSkip(restored.LuckyBlocks, b.Id, 1002), "ready timer cannot waste credit")
		local nextBlock = L.add(restored.LuckyBlocks, "Legendary", 1002)
		H.expect(L.useSkip(restored.LuckyBlocks, nextBlock.Id, 1003), "credit usable on next block")
		local again = Schema.validate(restored)
		H.expect(L.find(again.LuckyBlocks, nextBlock.Id).Paid, "paid origin survives save repair")
	end,
	["the skip by time left: 4 R$ up to 30 minutes, 9 up to 6 hours, 15 beyond"] = function()
		local L, Config = load()
		local skips = Config.LuckyBlocks.Skips
		H.expect(#skips == 3 and skips[1].UpTo == 1800 and skips[2].UpTo == 6 * 3600, "")
		local robux = {}
		for _, row in skips do
			table.insert(robux, Config.Products.List[row.Product].Robux)
		end
		H.expect(table.concat(robux, " ") == "4 9 15", "the designer's 4 / 9 / 15 R$")
		local state = L.fresh()
		local epic = L.add(state, "Epic", 1000) -- 30 minutes
		local mythic = L.add(state, "Mythic", 1000) -- 12 hours
		H.expect(L.skipProduct(epic, 1000) == "LuckyBlockSkip", "30 min left: 4 R$")
		H.expect(L.skipProduct(mythic, 1000) == "LuckyBlockSkip15", "12 h left: 15 R$")
		H.expect(L.skipProduct(mythic, 1000 + 6 * 3600) == "LuckyBlockSkip9", "6 h left: 9 R$")
		H.expect(L.skipProduct(mythic, 1000 + 12 * 3600 - 1800) == "LuckyBlockSkip", "30 min")
		H.expect(L.skipProduct(epic, 1000 + 1800) == nil, "ready: no skip")
		H.expect(L.skipTierOf("LuckyBlockSkip9") == 2 and L.skipTierOf("Pack1") == nil, "")
		-- A credit never skips a longer timer than it was bought for.
		L.grantSkip(state, 1000, 1) -- no target: a 4 R$ credit kept
		H.expect(state.SkipCredits1 == 1, "kept as a short credit")
		H.expect(not L.useSkip(state, mythic.Id, 1000), "not on 12 hours")
		H.expect(L.useSkip(state, epic.Id, 1000), "on 30 minutes")
		L.grantSkip(state, 1000, 3)
		H.expect(state.SkipCredits == 1 and L.useSkip(state, mythic.Id, 1000), "the top one")
		H.expect(L.find(state, mythic.Id).Paid and L.isReady(L.find(state, mythic.Id), 1000), "")
	end,
	["floor placement does not change the persistent inventory"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local a = L.add(save.LuckyBlocks, "Rare", 1000)
		local b = L.add(save.LuckyBlocks, "Legendary", 1000)
		-- Floor instances are transient; the serialized save keeps both unopened ids and times.
		local restored = Schema.validate(save)
		H.expect(#restored.LuckyBlocks.List == 2, "both returned in inventory")
		H.expect(L.find(restored.LuckyBlocks, a.Id).ReadyAt == 1300, "countdown unchanged")
		H.expect(L.find(restored.LuckyBlocks, b.Id).ReadyAt == 22600, "long timer unchanged")
	end,

	["every kind rolls a real odds row and the test kinds match the designer's"] = function()
		local LuckyBlocks, Config, BlockOdds = load()
		local Strings = H.require("Strings")
		H.expect(#LuckyBlocks.validate() == 0, "no problems")
		for _, id in Config.LuckyBlocks.Order do
			local kind = LuckyBlocks.kind(id)
			H.expect(kind ~= nil, id .. " is a kind")
			if kind.Roll then
				H.expect(kind.Odds == nil, id .. " rolls a tier, not a row")
			else
				H.expect(BlockOdds.get(kind.Odds) ~= nil, id .. " rolls an odds row")
				H.expect(#BlockOdds.cueOdds(kind.Odds) > 0, id .. " has cues to roll")
			end
			H.expect(
				type(Strings.LuckyBlocks.Names[id]) == "string",
				id .. " has a name in Strings"
			)
		end
		H.expect(
			LuckyBlocks.kind("Standard").Odds == "Standard",
			"Standard rolls the Standard odds"
		)
		H.expect(LuckyBlocks.timer("Standard") == 0, "Standard opens at once")
		H.expect(LuckyBlocks.kind("Rare").Odds == "Rare", "Rare rolls the Rare odds")
		H.expect(LuckyBlocks.timer("Rare") == 300, "Rare waits 5 minutes")
		H.expect(LuckyBlocks.kind("Purple") == nil and LuckyBlocks.kind(5) == nil, "unknown: nil")
		-- The extra tables roll the whole core pool; the Grand Opening block's Unique rows.
		H.expect(LuckyBlocks.kind("Sky").Odds == "Sky" and BlockOdds.get("Sky") ~= nil, "Sky")
		H.expect(#BlockOdds.uniqueRows("GrandOpening") == 2, "two Unique rows")
		H.expect(BlockOdds.canDrop("GrandOpening", "BetaCue"), "the Beta Cue drops from it")
		H.expect(not BlockOdds.canDrop("Standard", "BetaCue"), "not from a Standard block")
	end,

	["a block's timer starts when it lands"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local standard = LuckyBlocks.add(state, "Standard", 1000)
		local rare = LuckyBlocks.add(state, "Rare", 1000)
		H.expect(LuckyBlocks.isReady(standard, 1000), "Standard is ready at once")
		H.expect(not LuckyBlocks.isReady(rare, 1299), "Rare is not ready a second early")
		H.expect(LuckyBlocks.isReady(rare, 1300), "Rare is ready after 5 minutes")
		H.expect(LuckyBlocks.secondsLeft(rare, 1017.5) == 283, "seconds left round up")
		H.expect(LuckyBlocks.secondsLeft(rare, 5000) == 0, "never below 0")
	end,

	["ids never repeat and new blocks go where asked"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local a = LuckyBlocks.add(state, "Standard", 0)
		local b = LuckyBlocks.add(state, "Rare", 0)
		H.expect(a.Id == 1 and b.Id == 2 and state.Next == 2, "ids count up")
		LuckyBlocks.remove(state, a.Id)
		local c = LuckyBlocks.add(state, "Standard", 0, 1)
		H.expect(c.Id == 3, "a removed id is not given again")
		H.expect(state.List[1] == c and state.List[2] == b, "put at the place asked")
		local d = LuckyBlocks.add(state, "Yellow", 0, 99) -- an old id: a Standard block
		H.expect(state.List[3] == d and d.Kind == "Standard", "a place past the end is the end")
		H.expect(LuckyBlocks.count(state, "Standard") == 2, "count by kind")
	end,

	["remove answers the place, move closes up round it"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		for _ = 1, 4 do
			LuckyBlocks.add(state, "Standard", 0)
		end
		local block, place = LuckyBlocks.remove(state, 3)
		H.expect(block ~= nil and block.Id == 3 and place == 3, "the third, from place 3")
		H.expect(LuckyBlocks.remove(state, 3) == nil, "gone")
		H.expect(LuckyBlocks.move(state, 4, 1), "moved")
		local ids = {}
		for _, b in state.List do
			table.insert(ids, b.Id)
		end
		H.expect(table.concat(ids, ",") == "4,1,2", "4 to the front, the rest after it")
		H.expect(LuckyBlocks.move(state, 4, 50), "a place past the end")
		H.expect(state.List[3].Id == 4, "is the end")
		H.expect(not LuckyBlocks.move(state, 99, 1), "no such block")
	end,

	["the client's copy is in hotbar order"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		LuckyBlocks.add(state, "Rare", 10)
		LuckyBlocks.add(state, "Standard", 10, 1)
		local copy = LuckyBlocks.snapshot(state)
		H.expect(#copy == 2, "both")
		H.expect(copy[1].kind == "Standard" and copy[1].id == 2, "Standard first")
		H.expect(copy[2].kind == "Rare" and copy[2].readyAt == 310, "Rare with its ready time")
	end,

	["the countdown reads m:ss, or h:mm:ss past an hour"] = function()
		local LuckyBlocks = load()
		H.expect(LuckyBlocks.clockText(102) == "1:42", "1:42")
		H.expect(LuckyBlocks.clockText(4.2) == "0:05", "rounds up")
		H.expect(LuckyBlocks.clockText(-3) == "0:00", "never negative")
		H.expect(LuckyBlocks.clockText(3729) == "1:02:09", "an hour and more")
	end,

	["BlockRequest's arguments: shapes only, whole ids"] = function()
		local LuckyBlocks, Config = load()
		local r = LuckyBlocks.parse("Hold", nil)
		H.expect(r ~= nil and r.action == "Hold" and r.id == nil, "Hold nothing puts it away")
		r = LuckyBlocks.parse("Hold", 3)
		H.expect(r ~= nil and r.id == 3, "Hold a block")
		for _, action in { "Throw", "Open" } do
			H.expect(LuckyBlocks.parse(action, 2) ~= nil, action .. " a block")
			H.expect(LuckyBlocks.parse(action, nil) == nil, action .. " needs an id")
		end
		r = LuckyBlocks.parse("Move", 4, 2)
		H.expect(r ~= nil and r.id == 4 and r.to == 2, "Move a block to a place")
		local bad: { { any } } = {
			{ "Hold", 1.5 },
			{ "Hold", 0 / 0 },
			{ "Throw", "1" },
			{ "Open", -1 },
			{ "Open", math.huge },
			{ "Move", 1, 0 },
			{ "Move", 1, Config.LuckyBlocks.MaxBlocks + 1 },
			{ "Sell", 1 },
			{ 7, 1 },
		}
		for _, args in bad do
			local request, why = LuckyBlocks.parse(args[1], args[2], args[3])
			H.expect(request == nil and why == "BadRequest", "refused: " .. tostring(args[1]))
		end
	end,
	["the Gift falls once: the first leave starts its 12 hours, picking it up ends the drop"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		LuckyBlocks.add(state, "Standard", 100)
		local flags: { [string]: any } = {}
		H.expect(not LuckyBlocks.giftPending(flags), "nothing before a leave")
		H.expect(LuckyBlocks.landGift(state, flags) == nil and #state.List == 1, "no gift yet")
		H.expect(LuckyBlocks.noteLeave(flags, 1000), "the first leave is noted")
		H.expect(not LuckyBlocks.noteLeave(flags, 5000), "a later leave changes nothing")
		H.expect(flags.GiftLeftAt == 1000 and LuckyBlocks.giftPending(flags), "waiting")
		local gift = LuckyBlocks.landGift(state, flags)
		H.expect(gift ~= nil and gift.Kind == "Gift", "picked up")
		H.expect(state.List[1] == gift, "first in the hotbar")
		H.expect((gift :: any).ReadyAt == 1000 + 12 * 3600, "12 h from the leave")
		H.expect(not LuckyBlocks.giftPending(flags) and flags.GiftLanded == true, "done")
		H.expect(LuckyBlocks.landGift(state, flags) == nil and #state.List == 2, "only once")
		local vipFlags: { [string]: any } = {}
		LuckyBlocks.noteLeave(vipFlags, 0)
		local fast = LuckyBlocks.landGift(state, vipFlags, true)
		H.expect(fast ~= nil and fast.ReadyAt == 0, "VIP: no timer, like every block")
	end,

	["reveal: a Mystery block becomes its tier in place, on the tier's timer"] = function()
		local L = load()
		local state = L.fresh()
		L.add(state, "Standard", 100)
		local mystery = L.add(state, "Mystery", 100)
		L.add(state, "Rare", 100)
		H.expect(mystery.ReadyAt == 100, "the Mystery block has no timer")
		local block = L.reveal(state, mystery.Id, "Rare", 200)
		H.expect(block ~= nil and block.Id == mystery.Id, "same id")
		H.expect(state.List[2] == block and block.Kind == "Rare", "same place, now Rare")
		H.expect(block.ReadyAt == 200 + L.timer("Rare"), "on the Rare timer from the reveal")
		H.expect(L.opened(state, "Mystery") == 1, "the open is counted for the Mystery block")
		-- A VIP's: no timer. A paid one: ready at once and still paid.
		local vip = L.add(state, "Mystery", 100)
		H.expect((L.reveal(state, vip.Id, "Epic", 300, true) :: any).ReadyAt == 300, "VIP")
		local paid = L.add(state, "Mystery", 100, nil, true)
		local after = L.reveal(state, paid.Id, "Mythic", 400) :: any
		H.expect(after.ReadyAt == 400 and after.Paid == true, "paid: at once, paid origin")
		H.expect(L.reveal(state, 999, "Rare", 400) == nil, "no such block")
		local ok = pcall(L.reveal, state, mystery.Id, "Purple", 400)
		H.expect(not ok, "an unknown tier errors")
	end,

	["reveal: parse takes a Reveal of a whole id"] = function()
		local L = load()
		local r = L.parse("Reveal", 7)
		H.expect(r ~= nil and r.action == "Reveal" and r.id == 7, "Reveal 7")
		H.expect(select(2, L.parse("Reveal", nil)) == "BadRequest", "no id")
		H.expect(select(2, L.parse("Reveal", 1.5)) == "BadRequest", "not whole")
		H.expect(table.find(L.Actions, "Reveal") ~= nil, "an action")
		H.expect(table.find(L.Reasons, "Reveal") ~= nil, "Hold's refusal")
		H.expect(table.find(L.Reasons, "NotMystery") ~= nil, "Reveal's refusal")
	end,
}
