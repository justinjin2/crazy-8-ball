--!strict
-- Badges (hw-sys lane, designer 2026-10-28): the rules that decide each Roblox badge from a save
-- or a settled match, what is still to award, and the registry check.
local H = require("./harness")
local Badges = H.require("Progression.Badges")
local Catalog = H.require("Progression.Catalog")
local SaveSchema = H.require("Progression.SaveSchema")
local Config = H.require("Config")
local Strings = H.require("Strings")
local expect = H.expect

local OWNER = Config.Badges.OwnerUserId

-- The registry with every row live (an id per row), so pending() keeps them.
local function live(): { any }
	local out = {}
	for i, row in Config.Badges.List do
		table.insert(out, { Key = row.Key, BadgeId = 1000 + i, Rule = row.Rule })
	end
	return out
end

local function has(keys: { string }, key: string): boolean
	return table.find(keys, key) ~= nil
end

-- The first Catalog cue of a group (and rarity).
local function cueOf(group: string, rarity: string?): string
	for _, cue in Catalog.list() do
		if cue.Group == group and (rarity == nil or cue.Rarity == rarity) then
			return cue.Id
		end
	end
	error("no cue " .. group .. " " .. tostring(rarity))
end

local function rule(key: string): any
	for _, row in Config.Badges.List do
		if row.Key == key then
			return row.Rule
		end
	end
	error("no row " .. key)
end

return {
	["an empty save earns Welcome only"] = function()
		local keys = Badges.fromSave(SaveSchema.template(), Config.Badges.List)
		expect(#keys == 1 and keys[1] == "Welcome", "got " .. table.concat(keys, ","))
	end,

	["a veteran save earns the exact keys, in registry order"] = function()
		local save = SaveSchema.template()
		save.Stats.Wins = 30
		save.Stats.Matches = 120
		save.Stats.BestWinStreak = 5
		save.Stats.BallsPocketed = 1500
		save.Stats.NiceShots = 12
		save.Stats.MoneyEarned = 1200000
		save.PeakDivision = 13 -- Gold III
		save.Index.Seen[cueOf("Block", "Rare")] = true
		save.Index.Seen[cueOf("Block", "Epic")] = true
		local count = 0
		for _, cue in Catalog.list() do
			if cue.Group == "Block" and count < 3 then
				save.Index.Seen[cue.Id] = true
				count += 1
			end
		end
		local got = Badges.fromSave(save, Config.Badges.List)
		local want = {
			"Welcome",
			"FirstWin",
			"Wins5",
			"Wins10",
			"Wins25",
			"RankBronze",
			"RankSilver",
			"RankGold",
			"Streak3",
			"Streak5",
			"CueRare",
			"CueEpic",
			"Cues5",
			"Balls100",
			"Balls1000",
			"Matches10",
			"Matches100",
			"Nice10",
			"Money1M",
		}
		expect(table.concat(got, ",") == table.concat(want, ","), "got " .. table.concat(got, ","))
	end,

	["the ranks read the peak division; Reyes is 46"] = function()
		local save = SaveSchema.template()
		save.PeakDivision = 45
		expect(not Badges.passes(rule("RankReyes"), save), "45 is not Reyes")
		save.PeakDivision = 46
		expect(Badges.passes(rule("RankReyes"), save), "46 is Reyes")
		expect(SaveSchema.divisionCount() == 46, "46 divisions")
		save.PeakDivision = 0
		expect(not Badges.passes(rule("RankBronze"), save), "unranked")
		save.PeakDivision = 1
		expect(Badges.passes(rule("RankBronze"), save), "Bronze I")
	end,

	["cue rarity counts Block cues only; Unique is its group; Classic never counts"] = function()
		local save = SaveSchema.template()
		-- A Unique row tagged Epic or Legendary never earns the Block rarity badges.
		for _, cue in Catalog.list() do
			if cue.Group ~= "Block" and cue.Group ~= "Default" then
				save.Index.Seen[cue.Id] = true
			end
		end
		for _, key in { "CueRare", "CueEpic", "CueLegendary", "CueMythic", "CueSecret" } do
			expect(not Badges.passes(rule(key), save), key .. " from a non-Block cue")
		end
		expect(Badges.passes(rule("CueUnique"), save), "Unique group")
		-- Classic alone: no collection badge.
		local classic = SaveSchema.template()
		classic.Index.Seen[Catalog.Default] = true
		expect(not Badges.passes({ seenCount = 1 }, classic), "Classic excluded")
		-- Seen or held: a cue held now (Inventory.Cues) counts without Seen.
		local held = SaveSchema.template()
		held.Inventory.Cues[cueOf("Block", "Mythic")] = 1
		expect(Badges.passes(rule("CueMythic"), held), "held counts")
		-- Sold (Seen only) still counts.
		local sold = SaveSchema.template()
		sold.Index.Seen[cueOf("Block", "Secret")] = true
		expect(Badges.passes(rule("CueSecret"), sold), "seen counts")
	end,

	["UltMatches drives Ability Master"] = function()
		local save = SaveSchema.template()
		save.Stats.UltMatches = 99
		expect(not Badges.passes(rule("Ability100"), save), "99")
		save.Stats.UltMatches = 100
		expect(Badges.passes(rule("Ability100"), save), "100")
	end,

	["Beat the Owner: a real win over him that no forfeit decided"] = function()
		local function facts(over: { [string]: any }?): any
			local f: { [string]: any } = {
				outcome = "Win",
				real = true,
				teamSize = 1,
				opponents = { OWNER },
				forfeitTeam = nil,
				userId = 77,
			}
			for k, v in over or {} do
				f[k] = v
			end
			return f
		end
		local function beats(f: any): boolean
			return has(Badges.fromMatch(f, OWNER), "BeatOwner")
		end
		expect(beats(facts()), "win + real + owner + no forfeit")
		-- His surrender, his timeouts, his team leaving (EmptyTeam) and an early 8 all set the
		-- forfeit team (Settle.forfeitTeam).
		expect(not beats(facts({ forfeitTeam = 2 })), "a forfeit decided it")
		expect(not beats(facts({ forfeitTeam = 1 })), "any forfeit")
		expect(not beats(facts({ outcome = "Loss" })), "a loss")
		expect(not beats(facts({ real = false })), "PC or solo")
		expect(not beats(facts({ opponents = {} })), "no people opposite")
		expect(not beats(facts({ opponents = { 5, 6 } })), "someone else")
		expect(not beats(facts({ userId = OWNER })), "the owner himself")
		expect(beats(facts({ teamSize = 2, opponents = { 9, OWNER } })), "2v2 against him")
	end,

	["Squad Goals: a real team match"] = function()
		expect(has(Badges.fromMatch({ real = true, teamSize = 2 }, OWNER), "TeamMatch"), "2v2")
		expect(has(Badges.fromMatch({ real = true, teamSize = 3 }, OWNER), "TeamMatch"), "3v3")
		expect(not has(Badges.fromMatch({ real = true, teamSize = 1 }, OWNER), "TeamMatch"), "1v1")
		expect(not has(Badges.fromMatch({ real = false, teamSize = 2 }, OWNER), "TeamMatch"), "PC")
		local keys = Badges.forEvent(Config.Badges.List, "TeamMatch")
		expect(#keys == 1 and keys[1] == "Squad", "TeamMatch is Squad")
	end,

	["the halloween rules read the Halloween save field, nil-safe"] = function()
		local none = SaveSchema.template()
		none.Halloween = nil
		expect(not Badges.passes(rule("PumpkinSlayer"), none), "no field: no Pumpkin Slayer")
		expect(not Badges.passes(rule("Halloween2026"), none), "no field: no Halloween 2026")
		local king = SaveSchema.template()
		king.Halloween = { KingWins = 1 }
		expect(Badges.passes(rule("PumpkinSlayer"), king), "KingWins 1")
		expect(not Badges.passes(rule("Halloween2026"), king), "no Candy yet")
		local bought = SaveSchema.template()
		bought.Halloween = { Earned = 0, Bought = 2 }
		expect(Badges.passes(rule("Halloween2026"), bought), "bought Candy counts")
		expect(not Badges.passes(rule("PumpkinSlayer"), bought), "no King win")
	end,

	["pending drops owned, inert, paused and unknown keys"] = function()
		local save = SaveSchema.template()
		save.Badges = { FirstWin = true }
		local list = live()
		list[3].BadgeId = 0 -- Wins5 inert
		local got = Badges.pending(
			{ "Welcome", "FirstWin", "Wins5", "Wins10", "Nope" },
			save,
			list,
			{ Wins10 = true }
		)
		expect(table.concat(got, ",") == "Welcome", "got " .. table.concat(got, ","))
	end,

	["the registry is sound and has 52 rows"] = function()
		local problems = Badges.check(Config.Badges.List, Strings.Badges, Catalog, 52)
		expect(#problems == 0, table.concat(problems, "; "))
	end,

	["check catches each bad row"] = function()
		local text = { Name = "N", Description = "D" }
		local function problemsOf(rows: { any }, strings: any?): { string }
			local s = strings or {}
			if not strings then
				for _, row in rows do
					s[row.Key] = text
				end
			end
			return Badges.check(rows, s, Catalog)
		end
		local cases = {
			{
				{ Key = "A", BadgeId = 0, Rule = { always = true } },
				{ Key = "A", BadgeId = 0, Rule = { always = true } },
			},
			{
				{ Key = "A", BadgeId = 5, Rule = { always = true } },
				{ Key = "B", BadgeId = 5, Rule = { always = true } },
			},
			{ { Key = "A", BadgeId = 0, Rule = { wat = 1 } } },
			{ { Key = "A", BadgeId = 0, Rule = { stat = "Nope", atLeast = 1 } } },
			{ { Key = "A", BadgeId = 0, Rule = { stat = "Wins", atLeast = 0 } } },
			{ { Key = "A", BadgeId = 0, Rule = { stat = "Wins", atLeast = 1.5 } } },
			{ { Key = "A", BadgeId = 0, Rule = { peak = "Wood" } } },
			{ { Key = "A", BadgeId = 0, Rule = { seenRarity = "Shiny" } } },
			{ { Key = "A", BadgeId = 0, Rule = { seenGroup = "Nope" } } },
			{ { Key = "A", BadgeId = 0, Rule = { seenCue = "NoSuchCue" } } },
			{ { Key = "A", BadgeId = 0, Rule = { halloween = "Wins", atLeast = 1 } } },
			{ { Key = "A", BadgeId = 0, Rule = { halloween = "Candy", atLeast = 0 } } },
			{ { Key = "A", BadgeId = 0, Rule = { event = "Nope" } } },
			{ { Key = "A", BadgeId = 9 } }, -- an id but no rule
			{ { Key = "A", BadgeId = 0, Rule = { always = true, stat = "Wins", atLeast = 1 } } }, -- two kinds
		}
		for i, rows in cases do
			expect(#problemsOf(rows) > 0, "case " .. i .. " passed")
		end
		expect(#problemsOf({ { Key = "A", BadgeId = 0 } }) == 0, "no rule while inert is fine")
		expect(
			#problemsOf({ { Key = "A", BadgeId = 0, Rule = { always = true } } }, {}) > 0,
			"no text"
		)
		local long = { A = { Name = string.rep("x", 51), Description = "D" } }
		expect(
			#problemsOf({ { Key = "A", BadgeId = 0, Rule = { always = true } } }, long) > 0,
			"name over 50"
		)
		local many = {}
		for i = 1, Config.Save.MaxBadgeEntries + 1 do
			table.insert(many, { Key = "K" .. i, BadgeId = 0 })
		end
		expect(#problemsOf(many) > 0, "more rows than a save holds")
		expect(#Badges.check({}, {}, Catalog, 52) > 0, "not 52 rows")
	end,

	["the reel hold lasts until the slowest pull's card"] = function()
		-- Coordinator review 09:52: the old flat 8 s ended before a Mythic or Secret scene did.
		local hold = Badges.revealSeconds()
		local R = Config.UI.Reel.Reel
		local CS = Config.Cutscenes
		local secret = Config.LuckyBlocks.Rise.Seconds + R.BigSeconds + CS.Secret.FlashAt
		local mythic = Config.LuckyBlocks.Rise.Seconds + R.BigSeconds + CS.Mythic.FlashAt
		expect(hold > secret and hold > mythic, "the hold ends before a big pull's card")
		expect(hold < 60, "a hold over a minute: check the scene timings")
	end,
}
