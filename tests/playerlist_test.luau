--!strict
-- The player list's pure half (Progression/PlayerListView; GUI lane, designer 2026-10-03, D10):
-- a bot's wins by tier never change and stay in the tier's range; flags; the order.

local H = require("./harness")

local function load()
	return H.require("Progression.PlayerListView"), H.require("Config")
end

return {
	["a bot's wins sit in its tier's range and never change"] = function()
		local View, Config = load()
		for tier, range in Config.UI.PlayerList.BotWins do
			for id = -1, -400, -37 do
				local wins = View.botWins(tier, id)
				H.expect(wins >= range[1] and wins <= range[2], tier .. " in range")
				H.expect(wins == math.floor(wins), "whole")
				H.expect(View.botWins(tier, id) == wins, "the same every time")
			end
		end
		H.expect(
			View.botWins("Nope", -5) <= Config.UI.PlayerList.BotWins.Bronze[2],
			"unknown: Bronze"
		)
		local seen: { [number]: boolean } = {}
		local count = 0
		for id = -1, -60, -1 do
			local w = View.botWins("Gold", id)
			if not seen[w] then
				seen[w] = true
				count += 1
			end
		end
		H.expect(count > 20, "different bots differ")
	end,

	["a country code becomes its flag"] = function()
		local View = load()
		H.expect(View.flag("US") == "\u{1F1FA}\u{1F1F8}", "US")
		H.expect(View.flag("gb") == "\u{1F1EC}\u{1F1E7}", "lower case")
		H.expect(View.flag("") == "" and View.flag(nil) == "" and View.flag("USA") == "", "junk")
	end,

	["you first, then rank, wins and name"] = function()
		local View = load()
		local rows = {
			{ id = 1, name = "b", rankIndex = 3, wins = 5 },
			{ id = 2, name = "a", rankIndex = 3, wins = 5 },
			{ id = 3, name = "z", rankIndex = 9, wins = 0 },
			{ id = 4, name = "me", rankIndex = 1, wins = 0, you = true },
			{ id = 5, name = "c", rankIndex = 3, wins = 7 },
		}
		View.sort(rows)
		local order = {}
		for _, r in rows do
			table.insert(order, r.id)
		end
		H.expect(table.concat(order, ",") == "4,3,5,2,1", table.concat(order, ","))
	end,
}
