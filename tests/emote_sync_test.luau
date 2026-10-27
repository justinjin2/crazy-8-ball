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
		H.expect(near(S.musicPosition(110, 100, 0, 3, 0.17), 1.7), "at its speed")
		H.expect(S.fromStart(101.5, 100, 3) == true, "just started: from the beginning")
		H.expect(near(S.musicOncePosition(105, 100, 2, 10) :: number, 7), "once: no loop yet")
		H.expect(S.musicOncePosition(111, 100, 2, 10) == nil, "once: over, not again")
		H.expect(S.fromStart(104, 100, 3) == false, "older: in step")
		H.expect(near(S.musicPosition(120, 100, 0, 3, 0.17), 0.4), "looped once at its speed")
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
			H.expect(row.Animation > 0 and row.Length > 0, "ids and length " .. row.Id)
			-- Only our own emotes (a Scene) have no catalog item.
			H.expect(
				(row.Catalog or 0) > 0 or (row.Scene ~= nil and row.Catalog == nil),
				"catalog " .. row.Id
			)
			H.expect(row.Intro == nil or row.Intro > 0, "intro " .. row.Id)
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

	["our own emotes start on their own; a one-shot ends after its length"] = function()
		local S = load()
		local nearby =
			{ { id = "Popcorn", at = 60, distance = 2 }, { id = "Money", at = 70, distance = 2 } }
		local popcorn =
			{ Id = "Popcorn", Animation = 1, Creator = "x", Length = 2.4, Scene = "Popcorn" }
		local money = { Id = "Money", Catalog = 1, Animation = 1, Creator = "x", Length = 9 }
		H.expect(S.startAt(100, popcorn :: any, nearby, 24) == 100, "never in step")
		H.expect(S.startAt(100, money :: any, nearby, 24) == 70, "a bought dance joins")
		local shot = { Id = "Bullseye", Animation = 1, Creator = "x", Length = 3.6, Once = true }
		H.expect(near(S.endsAfter(shot :: any) :: number, 3.6), "one shot")
		shot.Speed = 2
		H.expect(near(S.endsAfter(shot :: any) :: number, 1.8), "at its speed")
		H.expect(S.endsAfter(money :: any) == nil, "a loop never ends by itself")
	end,

	["syncing gives their dance, or its duo partner while the duo is free"] = function()
		local S, Config = load()
		local list = Config.EmoteMenu.List
		local rat = S.syncRow(list, "RatDance", false)
		H.expect(rat ~= nil and rat.Id == "RatDance", "the same dance")
		local many = S.syncRow(list, "RatDance", true)
		H.expect(many ~= nil and many.Id == "RatDance", "no limit outside a duo")
		local geto = S.syncRow(list, "GojoWalk", false)
		H.expect(geto ~= nil and geto.Id == "GetoWalk", "Gojo gives Geto")
		local gojo = S.syncRow(list, "GetoWalk", false)
		H.expect(gojo ~= nil and gojo.Id == "GojoWalk", "Geto gives Gojo")
		local taken, why = S.syncRow(list, "GojoWalk", true)
		H.expect(taken == nil and why == "Taken", "a duo is two")
		local gone, why2 = S.syncRow(list, "Nope", false)
		H.expect(gone == nil and why2 == "Gone", "an unknown dance")
	end,

	["the menu has the designer's 13 dances, each named, with no time limit"] = function()
		local _, Config = load()
		local E = Config.EmoteMenu
		local Strings = H.require("Strings")
		H.expect(#E.List == 13, "13 dances, got " .. #E.List)
		for _, row in E.List do
			H.expect(type(Strings.Emotes.Names[row.Id]) == "string", "a name: " .. row.Id)
			if row.Duo then
				local pair = nil
				for _, other in E.List do
					if other.Id == row.Duo then
						pair = other
					end
				end
				H.expect(pair ~= nil and pair.Duo == row.Id, "duo both ways: " .. row.Id)
			end
		end
		H.expect((E :: any).MaxSeconds == nil, "no time limit")
		H.expect(E.WalkSpeed == 16, "Roblox's walking speed while dancing")
	end,

	["the menu starts with First, in order, then the rest as listed"] = function()
		local _, Config = load()
		local E = Config.EmoteMenu
		local ids = {}
		for _, row in E.List do
			table.insert(ids, row.Id)
		end
		local n = 0
		for _, id in E.First do
			local at = table.find(ids, id)
			if at then
				n += 1
				H.expect(at == n, "first, in order: " .. id)
			end
		end
		H.expect(n >= 4, "the first ones are in the menu")
		H.expect(ids[1] == "Popcorn" and ids[2] == "RatDance", "Popcorn, then Rat Dance")
		local passinho, scenario = table.find(ids, "Passinho"), table.find(ids, "Scenario")
		H.expect(passinho == n + 1 and scenario == n + 2, "the rest keep their order")
	end,

	["our own emotes are in the menu while their switch is on"] = function()
		local S, Config = load()
		local C = Config.EmoteMenu.Custom
		for _, row in C.List do
			local found = S.find(Config.EmoteMenu.List, row.Id)
			H.expect((found ~= nil) == C.Enabled, "listed iff on: " .. row.Id)
			H.expect(type(C.Models[row.Scene]) == "number", "a model: " .. row.Id)
			H.expect(type(C[row.Scene]) == "table", "a scene: " .. row.Id)
		end
		for name, sound in C.Sounds do
			H.expect(sound.Id:match("^rbxassetid://%d+$") ~= nil, "sound id " .. name)
			H.expect(sound.Volume > 0 and sound.Volume <= 1, "volume " .. name)
		end
	end,

	["a group key tells two starts of the same dance apart"] = function()
		local S = load()
		H.expect(S.groupKey("RatDance", 1) == S.groupKey("RatDance", 1), "same")
		H.expect(S.groupKey("RatDance", 1) ~= S.groupKey("RatDance", 2), "different start")
	end,
}
