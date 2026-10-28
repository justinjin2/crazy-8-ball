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
		H.expect(near(S.musicOncePosition(105, 100, 2, 10) :: number, 7), "once: no loop yet")
		H.expect(S.musicOncePosition(111, 100, 2, 10) == nil, "once: over, not again")
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

	["the menu has the designer's 14 dances, each named, with no time limit"] = function()
		local _, Config = load()
		local E = Config.EmoteMenu
		local Strings = H.require("Strings")
		H.expect(#E.List == 14, "14 dances, got " .. #E.List)
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
		H.expect(E.WalkSpeed == 8, "half of Roblox's walking speed while dancing (designer)")
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
		H.expect(ids[4] == "Passinho" and ids[8] == "SegaWalk", "Passinho 4th, Sega Walk 8th")
		local scenario, scuba = table.find(ids, "Scenario"), table.find(ids, "Scuba")
		H.expect(scenario == n + 1 and scuba == n + 2, "the rest keep their order")
		H.expect(ids[#ids] == "Birdbrain", "Bird Brain last (designer)")
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

	["a dance joined just after it started is in step, not from its start (Sync bug)"] = function()
		local S, Config = load()
		-- Syncing 1.5 s after the leader started played from frame 0 (the old 3 s "fresh"
		-- rule): 1.5 s behind them. In step, the joiner is 1.5 s in like the leader.
		local which, at = S.phase(101.5, 100, 1, 4.438)
		H.expect(which == "Loop" and near(at, 1.5), "1.5 s in")
		H.expect((Config.EmoteMenu :: any).FreshSeconds == nil, "no fresh rule")
		H.expect((S :: any).fromStart == nil, "no fromStart")
	end,

	["a dance's phase: the intro, then its loop, a one-shot ends"] = function()
		local S = load()
		-- Popcorn: a 0.8 s intro, the 2.4 s loop blended in 0.2 s before the intro ends.
		local w1, p1 = S.phase(100.3, 100, 1, 2.4, false, 0.8, 0.2)
		H.expect(w1 == "Intro" and near(p1, 0.3), "in the intro")
		local w2, p2 = S.phase(100.7, 100, 1, 2.4, false, 0.8, 0.2)
		H.expect(w2 == "Loop" and near(p2, 0.1), "the loop took over at 0.6 s")
		local w3, p3 = S.phase(103.4, 100, 1, 2.4, false, 0.8, 0.2)
		H.expect(w3 == "Loop" and near(p3, 0.4), "looped once")
		local w4, p4 = S.phase(100.5, 100, 2, 2.4, false, 0.8, 0.2)
		H.expect(w4 == "Loop" and near(p4, 0.6), "at its speed: split at 0.4 of the intro")
		-- Bullseye plays once.
		local w5, p5 = S.phase(102, 100, 1, 3.6, true)
		H.expect(w5 == "Loop" and near(p5, 2), "a one-shot midway")
		local w6 = S.phase(104, 100, 1, 3.6, true)
		H.expect(w6 == nil, "a one-shot over")
		local w7, p7 = S.phase(99, 100, 1, 4)
		H.expect(w7 == "Loop" and near(p7, 0), "a start in the future is 0")
		local _, p8 = S.phase(105, 100, 1, 0)
		H.expect(near(p8, 0), "no length is 0")
	end,

	["drift counts the short way round a loop"] = function()
		local S = load()
		H.expect(near(S.drift(1.2, 1.0, 4, true), 0.2), "ahead")
		H.expect(near(S.drift(0.8, 1.0, 4, true), -0.2), "behind")
		H.expect(near(S.drift(3.9, 0.1, 4, true), -0.2), "across the wrap, behind")
		H.expect(near(S.drift(0.1, 3.9, 4, true), 0.2), "across the wrap, ahead")
		H.expect(near(S.drift(3.9, 0.1, 4, false), 3.8), "a one-shot does not wrap")
	end,

	["a client's start time is taken only near the server's clock"] = function()
		local S = load()
		H.expect(S.clampAt(99.6, 100, 1) == 99.6, "a little behind: taken")
		H.expect(S.clampAt(100.4, 100, 1) == 100.4, "a little ahead: taken")
		H.expect(S.clampAt(95, 100, 1) == 100, "far behind: now")
		H.expect(S.clampAt(130, 100, 1) == 100, "far ahead: now")
		H.expect(S.clampAt("x", 100, 1) == 100, "junk: now")
		H.expect(S.clampAt(0 / 0, 100, 1) == 100, "NaN: now")
		H.expect(S.clampAt(nil, 100, 1) == 100, "none: now")
	end,

	["the nearest few, ties in the list's order"] = function()
		local S = load()
		local list = {
			{ key = 1, distance = 30 },
			{ key = 2, distance = 5 },
			{ key = 3, distance = 12 },
			{ key = 4, distance = 5 },
			{ key = 5, distance = 50 },
		}
		local four = S.nearest(list, 4)
		H.expect(four[2] and four[4] and four[3] and four[1] and not four[5], "four nearest")
		local one = S.nearest(list, 1)
		H.expect(one[2] == true and one[4] == nil, "a tie: the first listed")
		H.expect(next(S.nearest({}, 4)) == nil, "nobody")
		H.expect(list[1].key == 1, "the list is untouched")
	end,

	["a song is full near a dancer and silent from its far end"] = function()
		local S, Config = load()
		local E = Config.EmoteMenu
		local curve = S.musicCurve(12, 70)
		H.expect(curve[0] == 1 and curve[12] == 1, "full to 12")
		H.expect(near(curve[24], 0.5) and near(curve[36], 1 / 3), "then hear/distance")
		H.expect(curve[70] == 0, "silent at 70")
		H.expect(curve[60] ~= nil and curve[60] < 0.2, "tapered near the end")
		local last = 1
		for _, d in { 0, 12, 18, 24, 36, 48, 60, 70 } do
			H.expect(curve[d] ~= nil and curve[d] <= last, "falls: " .. d)
			last = curve[d]
		end
		H.expect(E.MusicVoices == 4, "4 voices (designer)")
		H.expect(E.MusicToleranceSeconds >= E.Align.ToleranceSeconds, "a song's seek is rarer")
	end,

	["Popcorn stands still and turns with shift lock; Bullseye holds its facing"] = function()
		local S, Config = load()
		local C = Config.EmoteMenu.Custom
		local popcorn = S.find(C.List, "Popcorn")
		H.expect(popcorn ~= nil and popcorn.WalkSpeed == 0, "no walking while lounging")
		H.expect(C.Popcorn.HoldFacing == false, "shift lock turns the lounging body")
		H.expect(C.Bullseye.HoldFacing == true, "Bullseye faces its target")
		local bullseye = S.find(C.List, "Bullseye")
		H.expect(bullseye ~= nil and bullseye.WalkSpeed == 0, "no walking while shooting")
	end,

	["every emote sound is about 55% quieter than its listed volume"] = function()
		local _, Config = load()
		local E = Config.EmoteMenu
		H.expect(E.Loudness >= 0.4 and E.Loudness <= 0.5, "a dancer alone, 50 to 60% quieter")
		H.expect(E.MusicTwoTogether > 1, "still louder together")
	end,

	["Bullseye's puffs are small and few, and hidden while you shoot"] = function()
		local _, Config = load()
		local C = Config.EmoteMenu.Custom
		local share = C.Bullseye.PuffSizeShare
		H.expect(share >= 0.2 and share <= 0.4, "60 to 80% smaller (designer)")
		H.expect(C.Bullseye.PuffCountShare <= 0.5, "half as many or fewer")
		H.expect(C.HideWhileShooting == true, "no prop or puff on your screen while you shoot")
	end,

	["Gojo and Geto walk side by side, 7.5% faster than their first 1.6"] = function()
		local S, Config = load()
		local gojo = S.find(Config.EmoteMenu.List, "GojoWalk")
		local geto = S.find(Config.EmoteMenu.List, "GetoWalk")
		H.expect(gojo ~= nil and geto ~= nil and gojo.WalkSpeed == geto.WalkSpeed, "one speed")
		H.expect(gojo ~= nil and near(gojo.WalkSpeed :: number, 1.6 * 1.075), "1.72")
		H.expect(gojo ~= nil and gojo.Speed == nil, "the animation as it was")
	end,

	["Sync works in a match too, on a controller button the ability does not use"] = function()
		local _, Config = load()
		local Sy = Config.EmoteMenu.Sync
		H.expect(Sy.InMatch == true, "in matches (designer)")
		H.expect(
			Sy.PadKey == "ButtonX" and Sy.MatchPadKey == "ButtonY",
			"X in the lobby, Y in a match"
		)
		local ult = Config.Ults and Config.Ults.PadKey
		H.expect(ult == nil or ult ~= Sy.MatchPadKey, "never the ability's button")
	end,

	["dancing together is louder, but never double"] = function()
		local S, Config = load()
		local two = Config.EmoteMenu.MusicTwoTogether
		H.expect(two == 1.5, "two together are 1.5 times one (designer)")
		H.expect(near(S.groupGain(1, two), 1), "alone: as now")
		H.expect(near(S.groupGain(0.4, two), 1), "far off: never turned up")
		H.expect(near(S.groupGain(2, two), 0.75), "two side by side: each 0.75")
		H.expect(near(2 * S.groupGain(2, two), 1.5), "together 1.5")
		local four = 4 * S.groupGain(4, two)
		H.expect(four > 2.2 and four < 2.3, "four together about 2.25, got " .. four)
		-- A group that walked apart: you by one of them, the rest far off.
		local curve = S.musicCurve(12, 70)
		local heard = S.curveAt(curve, 3) + S.curveAt(curve, 65) + S.curveAt(curve, 69)
		H.expect(S.groupGain(heard, two) > 0.95, "one of a split group sounds like one alone")
	end,

	["a curve's value between its points"] = function()
		local S = load()
		local curve = S.musicCurve(12, 70)
		H.expect(near(S.curveAt(curve, 5), 1), "full near")
		H.expect(near(S.curveAt(curve, 21), (curve[18] + curve[24]) / 2), "a straight line between")
		H.expect(S.curveAt(curve, 70) == 0 and S.curveAt(curve, 200) == 0, "silent far")
		H.expect(S.curveAt({}, 5) == 0, "no curve")
	end,

	["the first-time nudges are saved seen kinds, worded"] = function()
		local _, Config = load()
		local Strings = H.require("Strings")
		local kinds = Config.Settings.SeenKinds
		H.expect(table.find(kinds, "EmoteButton") ~= nil, "the button's dot, once")
		H.expect(table.find(kinds, "EmoteJump") ~= nil, "the jump line, once")
		H.expect(
			Strings.Emotes.JumpHint == "Jump to cancel emote at any time",
			"the designer's words"
		)
		local B = Config.EmoteMenu.Button
		H.expect(B.HintMinLeftShare > 0.5 and B.HintMinLeftShare < 0.8, "clear of the middle")
		H.expect(B.PhoneBottomPx >= 20, "a phone's button clear of the edge")
	end,

	["the emotes' sounds are the Sound effects row's second switch, on by default"] = function()
		local _, Config = load()
		local Strings = H.require("Strings")
		local C, U = Config.Settings, Config.UI.Settings
		H.expect(C.Defaults.EmoteSounds == true, "on by default")
		H.expect(table.find(C.Order, "EmoteSounds") == nil, "not a row of its own (phone)")
		H.expect(table.find(C.Hidden, "EmoteSounds") ~= nil, "saved, with no row")
		H.expect(U.Pairs.Sfx and U.Pairs.Sfx.Second == "EmoteSounds", "on Sound effects' row")
		local words = Strings.Settings.Pairs.Sfx
		H.expect(words.First == "All" and words.Second == "Emotes", "each switch named")
		H.expect(#C.Order == 5, "five rows, as before")
	end,

	["an asset id's number"] = function()
		local S = load()
		H.expect(S.assetNumber("rbxassetid://123") == "123", "the number")
		H.expect(S.assetNumber(nil) == nil, "none")
	end,

	["Popcorn's intro length is known for the clock"] = function()
		local S, Config = load()
		local row = S.find(Config.EmoteMenu.Custom.List, "Popcorn")
		H.expect(row ~= nil and row.Intro ~= nil and row.IntroLength == 0.8, "0.8 s")
		local A = Config.EmoteMenu.Align
		H.expect(A.Seconds >= 0.25 and A.ToleranceSeconds > 0 and A.MaxSkewSeconds <= 2, "align")
	end,

	["a group key tells two starts of the same dance apart"] = function()
		local S = load()
		H.expect(S.groupKey("RatDance", 1) == S.groupKey("RatDance", 1), "same")
		H.expect(S.groupKey("RatDance", 1) ~= S.groupKey("RatDance", 2), "different start")
	end,
}
