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
		-- Gold spans 31 values on the 2026-10-11 ladder (25 to 55): well spread, not all one.
		local range = Config.UI.PlayerList.BotWins.Gold
		H.expect(count > (range[2] - range[1] + 1) / 2, "different bots differ: " .. count)
	end,

	["the country flag is on by default and listed as a setting"] = function()
		local _, Config = load()
		-- Designer, 2026-10-25: everyone's flag shows unless they switch it off.
		H.expect(Config.Settings.Defaults.ShowFlag == true, "on by default")
		H.expect(table.find(Config.Settings.Order, "ShowFlag") ~= nil, "still a row to turn it off")
		local plate = Config.UI.Progress.Nameplate
		H.expect(
			plate.FlagShare > 0 and plate.FlagShare <= 1,
			"the nameplate's flag fits the plate"
		)
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
