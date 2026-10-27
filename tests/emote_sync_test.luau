--!strict
-- EmoteSync: the emote menu's maths (designer, 2026-10-26): where a dance is in its loop, its
-- music's place, joining a dance nearby in step, favourites first.

local H = require("./harness")

local function load()
	return H.require("EmoteSync"), H.require("Config")
end

local function near(x: number, y: number): boolean
	return math.abs(x - y) < 1e-6
end

return {
	["a dance's place in its loop follows the server clock"] = function()
		local S = load()
		H.expect(near(S.offset(100, 100, 4, 1), 0), "starts at 0")
		H.expect(near(S.offset(102.5, 100, 4, 1), 2.5), "2.5 s in")
		H.expect(near(S.offset(109, 100, 4, 1), 1), "loops")
		H.expect(near(S.offset(102, 100, 4, 1.5), 3), "speed")
		H.expect(near(S.offset(99, 100, 4, 1), 0), "a start in the future is 0")
		H.expect(near(S.offset(105, 100, 0, 1), 0), "no length is 0")
	end,

	["its music plays from Start and loops Loop seconds"] = function()
		local S = load()
		H.expect(near(S.musicPosition(100, 100, 31, 20), 31), "from the start")
		H.expect(near(S.musicPosition(125, 100, 31, 20), 36), "looped once")
		H.expect(near(S.musicPosition(125, 100, 31, 0), 31), "no loop stays at the start")
	end,

	["a dance joins the nearest dancer doing it within reach, else starts now"] = function()
		local S = load()
		local nearby = {
			{ id = "RatDance", at = 50, distance = 30 },
			{ id = "RatDance", at = 60, distance = 10 },
			{ id = "Gangnam", at = 70, distance = 2 },
		}
		H.expect(S.joinAt(100, "RatDance", nearby, 24) == 60, "the nearest in reach")
		H.expect(S.joinAt(100, "Gangnam", nearby, 24) == 70, "the same dance only")
		H.expect(S.joinAt(100, "Scuba", nearby, 24) == 100, "nobody: now")
		H.expect(
			S.joinAt(100, "RatDance", { { id = "RatDance", at = 50, distance = 30 } }, 24) == 100,
			"too far"
		)
		H.expect(
			S.joinAt(100, "RatDance", { { id = "RatDance", at = 120, distance = 1 } }, 24) == 100,
			"never the future"
		)
	end,

	["favourites come first, each group in the list's order"] = function()
		local S, Config = load()
		local list = Config.EmoteMenu.List
		local order = S.order(list, { Money = true, Passinho = true })
		H.expect(order[1] == "Passinho" and order[2] == "Money", "favourites in list order")
		H.expect(order[3] == list[1].Id, "then the list")
		H.expect(#order == #list, "every dance once")
		H.expect(S.order(list, nil)[1] == list[1].Id, "no favourites: the list")
	end,

	["favourites keep only dances still in the list"] = function()
		local S, Config = load()
		local clean =
			S.cleanFavorites(Config.EmoteMenu.List, { RatDance = true, Gone = true, Scuba = false })
		H.expect(clean.RatDance == true and clean.Gone == nil and clean.Scuba == nil, "cleaned")
		H.expect(next(S.cleanFavorites(Config.EmoteMenu.List, "junk")) == nil, "not a table")
	end,

	["every dance row is whole, unique and named"] = function()
		local S, Config = load()
		local Strings = H.require("Strings")
		local seen = {}
		for _, row in Config.EmoteMenu.List do
			H.expect(
				type(row.Id) == "string" and not seen[row.Id],
				"unique id " .. tostring(row.Id)
			)
			seen[row.Id] = true
			H.expect(
				row.Catalog > 0 and row.Animation > 0 and row.Length > 0,
				"ids and length " .. row.Id
			)
			H.expect(type(row.Creator) == "string" and row.Creator ~= "", "creator " .. row.Id)
			H.expect(type(Strings.Emotes.Names[row.Id]) == "string", "named " .. row.Id)
			H.expect(row.Prop == nil or Config.EmoteMenu.Props[row.Prop] ~= nil, "prop " .. row.Id)
			local m = row.Music
			if m then
				H.expect(m.Start >= 0 and m.Loop > 0 and m.Loop <= 60, "music " .. row.Id)
			end
			H.expect(S.find(Config.EmoteMenu.List, row.Id) == row, "found " .. row.Id)
		end
		H.expect(
			S.find(Config.EmoteMenu.List, "Nope") == nil and S.find(Config.EmoteMenu.List, 5) == nil,
			"unknown"
		)
	end,

	["a group key tells two starts of the same dance apart"] = function()
		local S = load()
		H.expect(S.groupKey("RatDance", 1) == S.groupKey("RatDance", 1), "same")
		H.expect(S.groupKey("RatDance", 1) ~= S.groupKey("RatDance", 2), "different start")
	end,
}
