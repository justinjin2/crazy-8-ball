--!strict
-- Lucky blocks (Progression/LuckyBlocks; the test build, designer 2026-10-03): the kinds point
-- at real cases, timers and readiness, the hotbar order (add, remove, move), the client's copy,
-- the countdown text and BlockRequest's argument checks.

local H = require("./harness")

local function load()
	return H.require("Progression.LuckyBlocks"), H.require("Config"), H.require("Progression.Cases")
end

return {
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
