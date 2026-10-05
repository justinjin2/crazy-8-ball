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
				{ "Uncommon", "Uncommon", 0 },
				{ "Rare", "Rare", 3600 },
				{ "Epic", "Epic", 21600 },
				{ "Legendary", "Legendary", 86400 },
				{ "Mythic", "Mythic", 172800 },
				{ "Gift", "Rare", 43200 },
			}
		do
			H.expect(L.kind(row[1]).Odds == row[2] and L.timer(row[1]) == row[3], row[1])
		end
		-- VIP halves every timer (Config.LuckyBlocks.VipTimerFactor); the Mystery block rolls a
		-- tier first (no odds row of its own).
		H.expect(Config.LuckyBlocks.VipTimerFactor == 0.5, "twice as fast")
		H.expect(L.timer("Rare", true) == 1800 and L.timer("Standard", true) == 0, "VIP halves")
		H.expect(L.timer("Mythic", true) == 86400, "48 h becomes 24 h")
		H.expect(L.kind("Mystery").Roll == true and L.kind("Mystery").Odds == nil, "Mystery")
		-- The old saved ids map to the new kinds (Config.LuckyBlocks.Renamed).
		H.expect(L.current("Yellow") == "Standard" and L.current("GoldKing") == "Legendary", "")
		H.expect(L.kind("Blue").Odds == "Rare" and L.current("Rare") == "Rare", "renamed")
	end,
	["the Grand Opening block's guarantee: the 400th open gives the Beta Cue if none"] = function()
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
		for _ = 1, 398 do
			L.noteOpened(state, "GrandOpening")
		end
		H.expect(L.opened(state, "GrandOpening") == 398, "counted")
		H.expect(L.guaranteed(state, "GrandOpening", none) == nil, "the 399th: a roll")
		L.noteOpened(state, "GrandOpening")
		H.expect(L.guaranteed(state, "GrandOpening", none) == "BetaCue", "the 400th: the Beta Cue")
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
		H.expect(b.ReadyAt == 87400, "bypass does not erase the timer")
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
	["floor placement does not change the persistent inventory"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local a = L.add(save.LuckyBlocks, "Rare", 1000)
		local b = L.add(save.LuckyBlocks, "Legendary", 1000)
		-- Floor instances are transient; the serialized save keeps both unopened ids and times.
		local restored = Schema.validate(save)
		H.expect(#restored.LuckyBlocks.List == 2, "both returned in inventory")
		H.expect(L.find(restored.LuckyBlocks, a.Id).ReadyAt == 4600, "countdown unchanged")
		H.expect(L.find(restored.LuckyBlocks, b.Id).ReadyAt == 87400, "long timer unchanged")
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
		H.expect(LuckyBlocks.timer("Rare") == 3600, "Rare waits an hour")
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
		H.expect(not LuckyBlocks.isReady(rare, 4599), "Rare is not ready a second early")
		H.expect(LuckyBlocks.isReady(rare, 4600), "Rare is ready after an hour")
		H.expect(LuckyBlocks.secondsLeft(rare, 1017.5) == 3583, "seconds left round up")
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
		H.expect(copy[2].kind == "Rare" and copy[2].readyAt == 3610, "Rare with its ready time")
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
		r = LuckyBlocks.parse("Reveal")
		H.expect(r ~= nil and r.action == "Reveal", "a Legendary card showing")
		H.expect(LuckyBlocks.parse("Reveal", 1) == nil, "Reveal takes nothing")
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
}
