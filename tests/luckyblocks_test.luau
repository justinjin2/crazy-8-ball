--!strict
-- Lucky blocks (Progression/LuckyBlocks; the test build, designer 2026-10-03): the kinds point
-- at real cases, timers and readiness, the hotbar order (add, remove, move), the client's copy,
-- the countdown text and BlockRequest's argument checks.

local H = require("./harness")

local function load()
	return H.require("Progression.LuckyBlocks"), H.require("Config"), H.require("Progression.Cases")
end

return {
	["new block tiers use the requested odds and timers"] = function()
		local L = load()
		for _, row in
			{
				{ "Green", "Uncommon", 60 },
				{ "VoidLava", "Epic", 3600 },
				{ "GoldKing", "Legendary", 21600 },
			}
		do
			H.expect(L.kind(row[1]).Case == row[2] and L.timer(row[1]) == row[3], row[1])
		end
	end,
	["only the designer can bypass an unchanged countdown"] = function()
		local L = load()
		local b = L.add(L.fresh(), "GoldKing", 1000)
		H.expect(not L.canOpen(b, 1001, 1234), "another account cannot bypass")
		H.expect(L.canOpen(b, 1001, 544959133), "designer can open")
		H.expect(b.ReadyAt == 22600, "bypass does not erase the timer")
	end,
	["late skip receipt preserves value and saved target across reconnect"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local b = L.add(save.LuckyBlocks, "VoidLava", 1000)
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
		local nextBlock = L.add(restored.LuckyBlocks, "GoldKing", 1002)
		H.expect(L.useSkip(restored.LuckyBlocks, nextBlock.Id, 1003), "credit usable on next block")
		local again = Schema.validate(restored)
		H.expect(L.find(again.LuckyBlocks, nextBlock.Id).Paid, "paid origin survives save repair")
	end,
	["floor placement does not change the persistent inventory"] = function()
		local L = load()
		local Schema = H.require("Progression.SaveSchema")
		local save = Schema.template()
		local a = L.add(save.LuckyBlocks, "Green", 1000)
		local b = L.add(save.LuckyBlocks, "GoldKing", 1000)
		-- Floor instances are transient; the serialized save keeps both unopened ids and times.
		local restored = Schema.validate(save)
		H.expect(#restored.LuckyBlocks.List == 2, "both returned in inventory")
		H.expect(L.find(restored.LuckyBlocks, a.Id).ReadyAt == 1060, "countdown unchanged")
		H.expect(L.find(restored.LuckyBlocks, b.Id).ReadyAt == 22600, "long timer unchanged")
	end,

	["every kind rolls a real case and the test kinds match the designer's"] = function()
		local LuckyBlocks, Config, Cases = load()
		local Strings = H.require("Strings")
		H.expect(#LuckyBlocks.validate() == 0, "no problems")
		for _, id in Config.LuckyBlocks.Order do
			local kind = LuckyBlocks.kind(id)
			H.expect(kind ~= nil and Cases.get(kind.Case) ~= nil, id .. " rolls a case")
			H.expect(#Cases.cueOdds(kind.Case) > 0, id .. " has cues to roll")
			H.expect(
				type(Strings.LuckyBlocks.Names[id]) == "string",
				id .. " has a name in Strings"
			)
		end
		H.expect(LuckyBlocks.kind("Yellow").Case == "Standard", "Yellow rolls the Standard odds")
		H.expect(LuckyBlocks.timer("Yellow") == 0, "Yellow opens at once")
		H.expect(LuckyBlocks.kind("Blue").Case == "Rare", "Blue rolls the Rare odds")
		H.expect(LuckyBlocks.timer("Blue") == 120, "Blue waits 2 minutes")
		H.expect(LuckyBlocks.kind("Purple") == nil and LuckyBlocks.kind(5) == nil, "unknown: nil")
	end,

	["a block's timer starts when it lands"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local yellow = LuckyBlocks.add(state, "Yellow", 1000)
		local blue = LuckyBlocks.add(state, "Blue", 1000)
		H.expect(LuckyBlocks.isReady(yellow, 1000), "Yellow is ready at once")
		H.expect(not LuckyBlocks.isReady(blue, 1119), "Blue is not ready a second early")
		H.expect(LuckyBlocks.isReady(blue, 1120), "Blue is ready after 2 minutes")
		H.expect(LuckyBlocks.secondsLeft(blue, 1017.5) == 103, "seconds left round up")
		H.expect(LuckyBlocks.secondsLeft(blue, 2000) == 0, "never below 0")
	end,

	["ids never repeat and new blocks go where asked"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		local a = LuckyBlocks.add(state, "Yellow", 0)
		local b = LuckyBlocks.add(state, "Blue", 0)
		H.expect(a.Id == 1 and b.Id == 2 and state.Next == 2, "ids count up")
		LuckyBlocks.remove(state, a.Id)
		local c = LuckyBlocks.add(state, "Yellow", 0, 1)
		H.expect(c.Id == 3, "a removed id is not given again")
		H.expect(state.List[1] == c and state.List[2] == b, "put at the place asked")
		local d = LuckyBlocks.add(state, "Yellow", 0, 99)
		H.expect(state.List[3] == d, "a place past the end is the end")
		H.expect(LuckyBlocks.count(state, "Yellow") == 2, "count by kind")
	end,

	["remove answers the place, move closes up round it"] = function()
		local LuckyBlocks = load()
		local state = LuckyBlocks.fresh()
		for _ = 1, 4 do
			LuckyBlocks.add(state, "Yellow", 0)
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
		LuckyBlocks.add(state, "Blue", 10)
		LuckyBlocks.add(state, "Yellow", 10, 1)
		local copy = LuckyBlocks.snapshot(state)
		H.expect(#copy == 2, "both")
		H.expect(copy[1].kind == "Yellow" and copy[1].id == 2, "Yellow first")
		H.expect(copy[2].kind == "Blue" and copy[2].readyAt == 130, "Blue with its ready time")
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
}
