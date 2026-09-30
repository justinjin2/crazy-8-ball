--!strict
-- DevCommands: developer chat commands, checked here on the server (Config.Debug.Commands).
-- Only the designer's own account (Config.Debug.Commands.UserIds) may use them; any other
-- player gets nothing, so no player can change everyone's sky, their own save or the shop.
-- - /day and /sunset send the day/sunset cycle toward that state for the whole server, through
--   its one-minute fade (LightCycle.offsetToward): the offset goes on a workspace attribute
--   every client's DayCycle reads, and the cycle runs on from there.
-- - The rank and money ones (/rank, /xp, /money, /addmoney, /result, /newrank, /resetdata;
--   /rankhelp lists them) and the economy ones (/econhelp lists them) act on the caller only
--   and answer privately (DevNotice). A /sale or a /party is this server's, like the real ones.
--   They go through the same server APIs as the game (PlayerData, Ranking, Items, Store,
--   Counters), so they can do nothing the save's own checks refuse. They work in a live server
--   too, for the designer only.
-- - The look check's tools (Studio only; /abilityhelp lists them): /slowmo <scale> sets the
--   replay rate at the caller's table for everyone (a workspace attribute the clients read),
--   and /abilitysetup <id|name> racks it in Config.Ults.Setups' layout through the QA
--   fixture, with that ability in the caller's slot and armed.
-- - Arguments are read defensively: a bad one answers a usage line, never an error.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightCycle = require(Shared:WaitForChild("LightCycle"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared.Progression.Format)
local Ranks = require(Shared.Progression.Ranks)
local Money = require(Shared.Progression.Money)
local Cases = require(Shared.Progression.Cases)
local Catalog = require(Shared.Progression.Catalog)
local Daily = require(Shared.Progression.Daily)
local Inventory = require(Shared.Progression.Inventory)
local PlayerData = require(script.Parent.PlayerData)
local Ranking = require(script.Parent.Ranking)
local Items = require(script.Parent.Items)
local Store = require(script.Parent.Store)
local Counters = require(script.Parent.Counters)
local UltService = require(script.Parent.UltService)
local UltSpins = require(script.Parent.UltSpins)
local Tables = require(script.Parent.TableService)
local UltCatalog = require(Shared.Ults.Catalog)

local D = Config.Debug.Commands
local C = Config.Lighting.Cycle
local S = Config.Save
local E = Config.Economy
local U = Config.Ults

-- Read by a key held in a variable (the economy help and usage lines).
local ALIAS: { [string]: string } = D :: any
local USAGE: { [string]: string } = Strings.Dev.Usage :: any
local WHAT: { [string]: string } = Strings.Dev.What :: any
local CUE_NAMES: { [string]: string } = Strings.Items.Cues :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local PASS_NAMES: { [string]: string } = Strings.Dev.PassNames :: any
local ULT_REASONS: { [string]: string } = Strings.Dev.UltReasons :: any
-- A command's old name that still runs it (the ult commands' names before "abilities").
local OLD_ALIASES: { [string]: string } = D.OldAliases :: any

local DevCommands = {}

--- Sends the cycle toward "Day" or "Sunset" (the commands' work; Studio tests call it too).
function DevCommands.toward(hold: string)
	local t = workspace:GetServerTimeNow() * C.Speed
	local offset = workspace:GetAttribute(C.OffsetAttribute)
	local now = if type(offset) == "number" then offset else 0
	workspace:SetAttribute(C.OffsetAttribute, LightCycle.offsetToward(t, now, C, hold))
end

-- Only the designer's own account (Config.Debug.Commands.UserIds), in Studio and live alike:
-- not other Studio collaborators, not a group owner, nobody else (the designer, 2026-09-30).
local function allowed(userId: number): boolean
	return table.find(D.UserIds, userId) ~= nil
end

-- `run` gets the caller and the words typed after the alias.
-- Every command by its alias, for the Studio test hook (DevCommands.start).
local handlers: { [string]: (Player, { string }) -> () } = {}

-- Runs the command typed in `text` for `player`, if they may use it (`fromScript`: the Studio
-- test hook, a server script rather than a player, may run it for any test player).
local function dispatch(player: Player, text: string, fromScript: boolean?)
	if not fromScript and not allowed(player.UserId) then
		return
	end
	local words = string.split(string.lower(text or ""), " ")
	local run = handlers[words[1] or ""]
	if not run then
		return
	end
	local args = {}
	for i = 2, #words do
		if words[i] ~= "" then
			table.insert(args, words[i])
		end
	end
	run(player, args)
end

-- `run` gets the caller and the words typed after the alias.
local function command(name: string, alias: string, run: (Player, { string }) -> ())
	handlers[alias] = run
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev" .. name
	cmd.PrimaryAlias = alias
	local old = OLD_ALIASES[name]
	if old then
		handlers[old] = run
		cmd.SecondaryAlias = old
	end
	cmd.AutocompleteVisible = false -- not offered to players
	cmd.Triggered:Connect(function(source: TextSource, text: string)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			dispatch(player, text)
		end
	end)
	cmd.Parent = TextChatService
end

local Dev = Strings.Dev

-- The lines told to a player during a Studio hook call, which the hook hands back.
local captured: { [Player]: { string } } = {}

-- A private line in the caller's chat window.
local function tell(player: Player, text: string)
	local lines = captured[player]
	if lines then
		table.insert(lines, text)
	end
	if player.Parent == Players then
		Net.get("DevNotice"):FireClient(player, text)
	end
end

-- A whole number in lo..hi from a typed word, or nil.
local function wholeIn(word: string?, lo: number, hi: number): number?
	local n = tonumber(word or "")
	if n == nil or n ~= n or n % 1 ~= 0 or n < lo or n > hi then
		return nil
	end
	return n
end

-- A whole number within the commands' limit (0..MaxAmount), or nil.
local function amount(word: string?): number?
	return wholeIn(word, 0, D.MaxAmount)
end

-- A rank from the words after /rank or /newrank: (tier, division, index), nil when not one.
local function parseRank(args: { string }): (string?, number, number?)
	local tier = args[1]
	if tier == nil then
		return nil, 0, nil
	end
	local division = tonumber(args[2] or "1") or 0
	local index = Ranks.indexOf(tier, division)
	if index == nil then
		return nil, 0, nil
	end
	local name, div = Ranks.at(index)
	return name, div, index
end

-- /rank <tier> [division] [xp]: set the rank outright (the peak follows it; no rewards, no
-- popup), so every badge can be looked at.
local function setRank(player: Player, args: { string })
	local tier, division, index = parseRank(args)
	if index == nil or not PlayerData.read(player) then
		tell(player, if index == nil then Dev.BadRank else Dev.NotLoaded)
		return
	end
	local rank
	if index == 0 then
		rank = { RankXp = 0, PeakDivision = 0, RatedMatches = 0 }
	else
		local data = PlayerData.read(player) :: any
		local xp = Ranks.toXp(tier :: string, division, amount(args[3]) or 0) or 0
		rank = { RankXp = xp, PeakDivision = index, RatedMatches = math.max(1, data.RatedMatches) }
	end
	if PlayerData.applyRank(player, rank) then
		local shown = Ranks.fromXp(rank.RankXp, rank.RatedMatches > 0)
		tell(player, Dev.RankSet:format(Ranks.name(shown)))
	end
end

-- The server's own randomness for the previews and /dupes (never for a real roll).
local random = Random.new()
local function roll(n: number): number
	return random:NextInteger(1, n)
end

-- The stand-in opponent of the /result preview (Roblox's own account, for a real headshot).
local STAND_IN = { userId = 1, name = "Opponent", tier = "Gold", division = 3 }

local RESULTS: { [string]: string } =
	{ win = "Win", lose = "Loss", loss = "Loss", draw = "Draw", firstwin = "Win" }

-- /result win|lose|draw|firstwin: the result screen with made-up numbers (the caller against a
-- stand-in opponent), worked out from the caller's real rank but never saved. A sample: every
-- boost that can apply is on (Rookie and VIP; First Win and Streak on a win) so every chip
-- shows, a win brings the free case, and `firstwin` brings the first win's opened case instead.
local function previewResult(player: Player, args: { string })
	local word = args[1] or ""
	local outcome = RESULTS[word]
	local data = PlayerData.read(player)
	local progress = PlayerData.progress(player)
	if outcome == nil or not data or not progress then
		tell(player, if outcome == nil then Dev.BadResult else Dev.NotLoaded)
		return
	end
	local win = outcome == "Win"
	local firstWin = word == "firstwin"
	local opponentIndex = Ranks.indexOf(STAND_IN.tier, STAND_IN.division)
	local xp = Ranks.applyMatch({
		RankXp = data.RankXp,
		PeakDivision = data.PeakDivision,
		RatedMatches = data.RatedMatches,
	}, {
		outcome = outcome,
		opponent = "Player",
		forfeit = false,
		mode = "Classic",
		opponentIndex = opponentIndex,
		boosts = { rookie = true, vip = true, firstWin = win, streak = win },
	})
	local you = {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		tier = xp.after.tier,
		division = xp.after.division,
		left = false,
	}
	local other = {
		userId = STAND_IN.userId,
		name = STAND_IN.name,
		displayName = STAND_IN.name,
		tier = STAND_IN.tier,
		division = STAND_IN.division,
		left = false,
	}
	-- The money as the settle would pay it, with the sample's VIP (and a party if one runs).
	local boost = Money.boost(true, Store.party() ~= nil)
	local myIndex = Ranks.fromXp(data.RankXp, data.RatedMatches > 0).index
	local balls, nice = 4, 1
	local ballMoney = Money.round(balls * E.BallPay * (1 + boost))
	local niceMoney = Money.round(E.NiceShotPay.Bank * (1 + boost))
	local bonus = Money.matchBonus({
		outcome = outcome,
		opponent = "Player",
		real = true,
		forfeited = false,
		multiplier = 1,
		gap = Ranks.gapFactor(myIndex, opponentIndex),
		boost = boost,
		farm = 1,
	})
	local streak = if win then Money.streakBonus(E.StreakFrom, "Player", 1, boost, 1) else 0
	-- The first win's case, opened at once (a sample roll: nothing is given).
	local reveal = nil
	if firstWin then
		local caseId = Config.Cases.FirstWinCase
		local ok, cue, rarity = pcall(Cases.roll, caseId, roll)
		if ok then
			reveal =
				{ case = caseId, cue = cue, rarity = rarity, new = not Inventory.owns(data, cue) }
		end
	end
	local reward = xp.rewardTotal
	Net.get("MatchSummary"):FireClient(player, {
		key = "preview",
		tableId = 0,
		epoch = 0,
		preview = true,
		solo = false,
		winner = if outcome == "Win" then 1 elseif outcome == "Loss" then 2 else nil,
		reason = if outcome == "Draw" then "EmptyTeam" else "LegalEight",
		short = false,
		teams = { { you }, { other } },
		you = { userId = player.UserId, team = 1, outcome = outcome, forfeited = false },
		xp = Ranking.xpPart(xp),
		money = {
			balls = balls,
			ballMoney = ballMoney,
			nice = nice,
			niceMoney = niceMoney,
			bonus = bonus,
			streak = streak,
			reward = reward,
			boost = boost,
			total = ballMoney + niceMoney + bonus + streak + reward,
		},
		freeCase = if win and not firstWin then Config.Cases.FreeCase else nil,
		firstWin = reveal,
		nextReward = Daily.nextReward(data.Login, Daily.dayOf(os.time())),
		-- The sample's Rookie Boost: the real count, but at least one match left.
		rookieLeft = math.max(1, Config.Ranks.Boosts.RookieMatches - progress.RealMatches - 1),
		rematch = false,
		arena = false,
	})
end

-- /newrank [tier] [division]: the NEW RANK! popup for that rank (yours if none given), as if
-- just reached from the division below, with that division's reward chips. Nothing is saved
-- or given. XP is never lost, so there is no rank-down to preview.
local function previewNewRank(player: Player, args: { string })
	local index: number?
	if args[1] then
		local _, _, found = parseRank(args)
		index = found
	else
		index = player:GetAttribute("RankIndex") :: number?
	end
	if type(index) ~= "number" or index < 1 then
		tell(player, Dev.BadRank)
		return
	end
	local tier, division = Ranks.at(index)
	local after = Ranks.fromXp(Ranks.startXp(index), true)
	local before = if index > 1
		then Ranks.fromXp(Ranks.startXp(index - 1), true)
		else Ranks.fromXp(0, false)
	-- The rows as Ranking sends them: { index, money, cases, cue? }, and their totals.
	local rows, total, cases, cues = {}, 0, {}, {}
	for _, row in Ranks.rewardsBetween(index - 1, index) do
		total += row.money
		table.insert(
			rows,
			{ index = row.index, money = row.money, cases = table.clone(row.cases), cue = row.cue }
		)
		for _, caseId in Config.Cases.Order do
			local count = row.cases[caseId]
			if count then
				cases[caseId] = (cases[caseId] or 0) + count
			end
		end
		if row.cue then
			table.insert(cues, row.cue)
		end
	end
	Net.get("RankEvent"):FireClient(player, {
		kind = "Up",
		preview = true,
		before = before,
		after = after,
		reward = total,
		newTier = division == 1 or tier == "Reyes",
		rewards = rows,
		rewardCases = cases,
		rewardCues = cues,
	})
end

---------------------------------------------------------------------------------------------
-- The economy commands
---------------------------------------------------------------------------------------------

-- Lowercase letters and digits only ("Chalk Dust Cue" -> "chalkdustcue"), so ids and names
-- match however they are typed.
local function squash(text: string): string
	return (string.gsub(string.lower(text), "[^%w]", ""))
end

-- `text` without a trailing `suffix` ("chalkdustcue" -> "chalkdust") when more is left.
local function trim(text: string, suffix: string): string
	if #text > #suffix and string.sub(text, -#suffix) == suffix then
		return string.sub(text, 1, #text - #suffix)
	end
	return text
end

local function cueName(id: string): string
	return CUE_NAMES[id] or id
end

local function caseName(id: string): string
	return CASE_NAMES[id] or id
end

-- Every cue by its squashed id and name, with and without "cue" at the end (catalog order:
-- the first cue to claim a key keeps it).
local cueByKey: { [string]: string } = {}
for _, cue in Catalog.list() do
	for _, text in { cue.Id, cueName(cue.Id) } do
		local key = squash(text)
		for _, candidate in { key, trim(key, "cue") } do
			if cueByKey[candidate] == nil then
				cueByKey[candidate] = cue.Id
			end
		end
	end
end

-- The cue named by typed words ("chalk dust", "chalkdust", "ChalkDustCue"), or nil.
local function findCue(words: { string }): string?
	local key = squash(table.concat(words, ""))
	if key == "" then
		return nil
	end
	return cueByKey[key] or cueByKey[trim(key, "cue")]
end

-- The case named by typed words ("rare", "rare case"), or nil.
local function findCase(words: { string }): string?
	local key = trim(squash(table.concat(words, "")), "case")
	for _, id in Config.Cases.Order do
		if squash(id) == key then
			return id
		end
	end
	return nil
end

-- The case ids as they are typed, for the usage lines: "standard|rare|...".
local CASE_WORDS = string.lower(table.concat(Config.Cases.Order, "|"))

-- Every Config.Products key, sorted (the /buy help and its refusal list them).
local PRODUCT_KEYS: { string } = {}
for key in Config.Products.List :: { [string]: any } do
	table.insert(PRODUCT_KEYS, key)
end
table.sort(PRODUCT_KEYS)

local function findProduct(word: string?): string?
	local key = squash(word or "")
	for _, product in PRODUCT_KEYS do
		if squash(product) == key then
			return product
		end
	end
	return nil
end

-- A name's words and the count typed after it ("chalk dust 3" -> {"chalk", "dust"}, "3"):
-- the last of two or more words, when it is a number.
local function splitCount(args: { string }): ({ string }, string?)
	local n = #args
	if n >= 2 and tonumber(args[n]) ~= nil then
		return table.move(args, 1, n - 1, 1, {}), args[n]
	end
	return args, nil
end

-- What follows each alias in its usage line (Strings.Dev.Usage), and the numbers in its
-- help line (Strings.Dev.What).
local USAGE_ARGS: { [string]: { any } } = {
	GiveCase = { CASE_WORDS },
	OpenCase = { CASE_WORDS },
	SetDay = { #Config.Daily.Streak, Config.Daily.WeeksForBonus },
	Sale = { D.Sale },
	UltBar = { U.BarMax },
	Spins = { U.Earn.MaxSpins },
	Lucky = { U.Earn.MaxSpins },
	Pity = { U.Roll.PityAt - 1 },
	Slowmo = { D.SlowmoMin, D.SlowmoMax, D.Slowmo },
	Hold = { D.HoldMax, D.Hold },
}
local WHAT_ARGS: { [string]: { any } } = {
	Dupes = { D.DupeCopies, D.DupeKinds },
	Buy = { table.concat(PRODUCT_KEYS, ", ") },
	Pity = { U.Roll.PityAt - 1 },
}

local function usage(key: string): string
	return USAGE[key]:format(ALIAS[key], table.unpack(USAGE_ARGS[key] or {}))
end

-- Answers a bad argument with the command's usage.
local function try(player: Player, key: string)
	tell(player, Dev.Try:format(usage(key)))
end

-- The /econhelp order.
local ECON: { string } = {
	"GiveCue",
	"GiveCase",
	"OpenCase",
	"Inv",
	"ClearInv",
	"Dupes",
	"SetDay",
	"NewDay",
	"Playtime",
	"Buy",
	"Vip",
	"FastOpen",
	"Party",
	"Policy",
	"Sale",
	"Rookie",
	"FreeCase",
}

-- Whether a cue's copies in existence are counted (Counters), as the game counts them: every
-- cue but Classic (case cues, the Exclusive tier cues a rank-up gives (Ranking), the Starter
-- and VIP cues (Store), the Limited ones).
local function counted(id: string): boolean
	local cue = Catalog.get(id)
	return cue ~= nil and cue.Group ~= "Default"
end

-- Takes the copies a save no longer holds out of the counts: every counted cue row of
-- `snapshot` (PlayerData.snapshot, read before the save was emptied).
local function uncount(snapshot: Inventory.Snapshot)
	for _, row in snapshot.cues do
		if counted(row.id) then
			Counters.add(row.id, -row.count)
		end
	end
end

-- Gives `copies` of each cue in `ids` (distinct ids; one reward per Config.Save.MaxSmallEntries
-- copies, a reward's most) and counts what landed as copies in existence. Returns the copies
-- each cue really got (none for an Exclusive cue already owned), or nil when not loaded.
local function giveCues(player: Player, ids: { string }, copies: number): { [string]: number }?
	local before = PlayerData.read(player)
	if not before then
		return nil
	end
	local list = {}
	for _, id in ids do
		for _ = 1, copies do
			table.insert(list, id)
		end
	end
	for first = 1, #list, S.MaxSmallEntries do
		local last = math.min(first + S.MaxSmallEntries - 1, #list)
		local part = table.move(list, first, last, 1, {})
		if not PlayerData.grantReward(player, { cues = part }, "DevCommand") then
			break
		end
	end
	local after = PlayerData.read(player)
	local given: { [string]: number } = {}
	for _, id in ids do
		local n = if after then Inventory.count(after, id) - Inventory.count(before, id) else 0
		given[id] = n
		if n > 0 and counted(id) then
			Counters.add(id, n)
		end
	end
	return given
end

-- Why a Unique cue cannot be given, and how to get one: its Robux product, else the shelf.
local function uniqueHint(id: string): string
	for _, row in Config.Shop.Limited do
		if row.Cue == id and row.Product ~= nil then
			return Dev.UniqueCueBuy:format(cueName(id), D.Buy, string.lower(row.Product))
		end
	end
	return Dev.UniqueCue:format(cueName(id))
end

-- /givecue <id|name> [count]
local function giveCue(player: Player, args: { string })
	local words, countWord = splitCount(args)
	local count = if countWord then wholeIn(countWord, 1, D.MaxGive) else 1
	if #words == 0 or count == nil then
		try(player, "GiveCue")
		return
	end
	local id = findCue(words)
	local cue = if id then Catalog.get(id) else nil
	if id == nil or cue == nil then
		tell(player, Dev.BadCue:format(table.concat(words, " ")))
		return
	elseif cue.Group == "Default" then
		tell(player, Dev.ClassicCue)
		return
	elseif cue.Group == "Unique" then
		tell(player, uniqueHint(id))
		return
	end
	local given = giveCues(player, { id }, if cue.Group == "Exclusive" then 1 else count)
	local n = if given then given[id] else 0
	if given == nil then
		tell(player, Dev.NotLoaded)
	elseif n > 0 then
		tell(player, Dev.GaveCue:format(cueName(id), n))
	elseif cue.Group == "Exclusive" then
		tell(player, Dev.ExclusiveOwned:format(cueName(id)))
	else
		tell(player, Dev.NotGiven:format(cueName(id)))
	end
end

-- /givecase <type> [count]
local function giveCase(player: Player, args: { string })
	local words, countWord = splitCount(args)
	local count = if countWord then wholeIn(countWord, 1, D.MaxGive) else 1
	if #words == 0 or count == nil then
		try(player, "GiveCase")
		return
	end
	local caseId = findCase(words)
	if caseId == nil then
		tell(player, Dev.BadCase:format(table.concat(words, " "), CASE_WORDS))
	elseif PlayerData.grantReward(player, { cases = { [caseId] = count } }, "DevCommand") then
		tell(player, Dev.GaveCase:format(caseName(caseId), count))
	else
		tell(player, Dev.NotLoaded)
	end
end

-- /opencase <type>: gives one of that case when the player has none, then asks their client
-- to open one on the reel, exactly as its button does (a table DevNotice: CaseOpening sends
-- the real OpenCase request, so the server rolls and takes the case as always).
local function openCase(player: Player, args: { string })
	local caseId = findCase(args)
	if #args == 0 or caseId == nil then
		try(player, "OpenCase")
		return
	end
	local data = PlayerData.read(player)
	if not data then
		tell(player, Dev.NotLoaded)
		return
	end
	local gave = false
	if Inventory.caseCount(data, caseId) < 1 then
		if not PlayerData.grantReward(player, { cases = { [caseId] = 1 } }, "DevCommand") then
			tell(player, Dev.NotLoaded)
			return
		end
		gave = true
	end
	tell(player, Dev.Opening:format(caseName(caseId)))
	local notice = { kind = "OpenCase", caseId = caseId, count = 1 }
	task.spawn(function()
		-- A case just given reaches the client in its ItemState at the next Heartbeat (Items):
		-- the reel is asked for after that, so the client already holds the case it opens.
		if gave then
			RunService.Heartbeat:Wait()
			RunService.Heartbeat:Wait()
		end
		if player.Parent == Players then
			Net.get("DevNotice"):FireClient(player, notice)
		end
	end)
end

-- Joins entries after `prefix` with ", " into chat lines of at most D.LineChars characters (an
-- entry longer than that gets a line of its own).
local function packLines(prefix: string, entries: { string }): { string }
	local lines = {}
	local line, empty = prefix, true
	for _, entry in entries do
		local joined = if empty then line .. entry else line .. ", " .. entry
		if not empty and #joined > D.LineChars then
			table.insert(lines, line)
			line = entry
		else
			line = joined
		end
		empty = false
	end
	table.insert(lines, line)
	return lines
end

-- /inv: the equipped cue, the unopened cases and the cues owned (Classic left out).
local function showInventory(player: Player)
	local snapshot = PlayerData.snapshot(player)
	if not snapshot then
		tell(player, Dev.NotLoaded)
		return
	end
	tell(player, Dev.InvEquipped:format(cueName(snapshot.equipped)))
	local cases = {}
	for _, row in snapshot.cases do
		table.insert(cases, Dev.InvCount:format(caseName(row.id), row.count))
	end
	local cues, copies = {}, 0
	for _, row in snapshot.cues do
		if row.id ~= Catalog.Default then
			copies += row.count
			table.insert(
				cues,
				if row.copy
					then Dev.InvCopy:format(cueName(row.id), row.copy)
					elseif row.count > 1 then Dev.InvCount:format(cueName(row.id), row.count)
					else cueName(row.id)
			)
		end
	end
	local lines: { string } = if #cases > 0
		then packLines(Dev.InvCases, cases)
		else { Dev.InvNoCases }
	local cueLines: { string } = if #cues > 0
		then packLines(Dev.InvCues:format(#cues, copies), cues)
		else { Dev.InvNoCues }
	table.move(cueLines, 1, #cueLines, #lines + 1, lines)
	for _, line in lines do
		tell(player, line)
	end
end

-- /clearinv: every cue but Classic and every case gone; the copies in existence follow.
local function clearInventory(player: Player)
	local snapshot = PlayerData.snapshot(player)
	if not snapshot or not PlayerData.clearInventory(player) then
		tell(player, Dev.NotLoaded)
		return
	end
	uncount(snapshot)
	tell(player, Dev.Cleared)
end

-- /dupes: D.DupeCopies copies of D.DupeKinds different random Common and Uncommon case cues.
local function giveDupes(player: Player)
	local pool = {}
	for _, rarity in { "Common", "Uncommon" } do
		for _, cue in Catalog.ofRarity(rarity) do
			if cue.Group == "Case" and not cue.Vaulted then
				table.insert(pool, cue.Id)
			end
		end
	end
	local picks = {}
	while #picks < D.DupeKinds and #pool > 0 do
		table.insert(picks, table.remove(pool, roll(#pool)) :: string)
	end
	if giveCues(player, picks, D.DupeCopies) == nil then
		tell(player, Dev.NotLoaded)
		return
	end
	local names = {}
	for _, id in picks do
		table.insert(names, cueName(id))
	end
	tell(player, Dev.Dupes:format(D.DupeCopies, table.concat(names, ", ")))
end

-- /setday <1-7> [week]: the next daily claim (today's) becomes that streak day.
local function setDay(player: Player, args: { string })
	local weeks = Config.Daily.WeeksForBonus
	local n = wholeIn(args[1], 1, #Config.Daily.Streak)
	local week = if args[2] then wholeIn(args[2], 1, weeks) else nil
	if n == nil or (args[2] ~= nil and week == nil) then
		try(player, "SetDay")
		return
	end
	local data = if PlayerData.setStreakDay(player, n, week) then PlayerData.read(player) else nil
	if not data then
		tell(player, Dev.NotLoaded)
		return
	end
	local state = Daily.loginState(data.Login, Daily.dayOf(os.time()))
	tell(player, Dev.DaySet:format(state.day, state.week))
end

-- /buy <product> [purchaseId]: Store.grant yields until the save is written (up to about 15 s),
-- so from chat it runs in its own thread and answers when it returns; from the Studio hook it
-- runs in the hook's call, so the answer is among the lines the hook hands back.
local function buy(player: Player, args: { string })
	local key = findProduct(args[1])
	if args[1] == nil then
		try(player, "Buy")
		return
	elseif key == nil then
		tell(player, Dev.BadProduct:format(args[1], table.concat(PRODUCT_KEYS, ", ")))
		return
	end
	local product: string = key
	local purchaseId = args[2]
	tell(player, Dev.Buying:format(product))
	local function grant()
		local called, ok, reason = pcall(Store.grant, player, product, purchaseId)
		if called and ok then
			tell(player, Dev.Bought:format(product))
		else
			tell(player, Dev.BuyFailed:format(product, tostring(if called then reason else ok)))
		end
	end
	if captured[player] then
		grant()
	else
		task.spawn(grant)
	end
end

-- /vip on|off and /fastopen on|off: fake owning that game pass for this session.
local function pass(key: string): (Player, { string }) -> ()
	return function(player: Player, args: { string })
		local on = ({ on = true, off = false } :: { [string]: boolean })[args[1] or ""]
		if on == nil then
			try(player, key)
			return
		end
		Store.setPass(player, key, on)
		local name = PASS_NAMES[key] or key
		tell(player, (if on then Dev.PassOn else Dev.PassOff):format(name))
		if not on and key == "Vip" and player:GetAttribute("VipOffer") == true then
			tell(player, Dev.VipOfferStays)
		end
	end
end

-- /sale <case> <percent> <minutes>, or /sale off. The percent is at most
-- Config.Cases.MaxSalePercent (a deeper sale would pay to buy, open and sell back).
local function sale(player: Player, args: { string })
	if args[1] == "off" and #args == 1 then
		Items.setSale(nil)
		tell(player, Dev.SaleOff)
		return
	end
	local caseId = findCase({ args[1] or "" })
	local percent = wholeIn(args[2], 1, Config.Cases.MaxSalePercent)
	local minutes = wholeIn(args[3], 1, D.MaxSaleMinutes)
	if caseId == nil or percent == nil or minutes == nil then
		try(player, "Sale")
		return
	end
	local case = Cases.get(caseId)
	if case and case.Enabled and Items.setSale(caseId, percent, os.time() + minutes * 60) then
		tell(player, Dev.SaleOn:format(caseName(caseId), percent, minutes))
	else
		tell(player, Dev.SaleNotSold:format(caseName(caseId)))
	end
end

-- /freecase: the free-case rule run as if the caller had just won a real match (Ranking).
local function freeCase(player: Player)
	if not PlayerData.isLoaded(player) then
		tell(player, Dev.NotLoaded)
		return
	end
	local caseId, cue = Ranking.freeCase(player)
	local progress = PlayerData.progress(player)
	local daily = PlayerData.dailyState(player)
	local wins = if progress then progress.Wins else 0
	local today = if daily then daily.Wins else 0
	if caseId and cue then
		tell(player, Dev.FreeCaseFirst:format(caseName(caseId), cueName(cue), today, wins))
	elseif caseId then
		tell(player, Dev.FreeCaseGave:format(caseName(caseId), today, wins))
	else
		tell(player, Dev.FreeCaseNone:format(today, wins))
	end
end

-- The /abilityhelp order.
local ULTS: { string } = {
	"UltBar",
	"UltFull",
	"UltArm",
	"Spins",
	"Lucky",
	"Pity",
	"FreeSpin",
	"Ult",
	"UltsAll",
	"OpUlt",
	"Slowmo",
	"Hold",
	"AbilitySetup",
}

-- An ult by id or name, any case or spacing ("blackflash", "black flash"), or nil.
local function findUlt(words: { string }): string?
	local typed = squash(table.concat(words, ""))
	for _, id in UltCatalog.list() do
		if squash(id) == typed or squash(UltCatalog.name(id)) == typed then
			return id
		end
	end
	return nil
end

-- A bar or arming answer: done, or why not.
local function ultAnswer(player: Player, ok: boolean, reason: string?, done: string)
	if ok then
		tell(player, done)
	else
		local why = ULT_REASONS[reason or ""] or tostring(reason)
		tell(player, Dev.UltNotDone:format(why))
	end
end

-- /spins, /lucky and /pity: a whole number in 0..hi, set through `set`.
local function ultCount(
	key: string,
	hi: number,
	set: (Player, number) -> boolean,
	answer: (number) -> string
): (Player, { string }) -> ()
	return function(player, args)
		local n = wholeIn(args[1], 0, hi)
		if n == nil then
			try(player, key)
		elseif set(player, n) then
			tell(player, answer(n))
		else
			tell(player, Dev.NotLoaded)
		end
	end
end

local function ultHelp(player: Player)
	tell(player, Dev.UltHelp)
	for _, key in ULTS do
		local what = WHAT[key]:format(table.unpack(WHAT_ARGS[key] or {}))
		tell(player, Dev.HelpLine:format(usage(key), what))
	end
end

---------------------------------------------------------------------------------------------
-- The look check's tools (Studio only; docs/prompts/ABILITIES_PROMPT.md 5.6)
---------------------------------------------------------------------------------------------

local SETUP_NOTES: { [string]: string } = Dev.SetupNotes :: any

-- The table the look-check tools act on: the one the player is in the game at, else the one
-- nearest their character (table 1 without a character).
local function nearTable(player: Player): number
	local seated = Tables.tableOf(player)
	if seated then
		return seated
	end
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local best, bestDistance = 1, math.huge
	if root and root:IsA("BasePart") then
		for id = 1, Placement.tableCount() do
			local p = Placement.forTable(id)
			if p then
				local distance = (Vector3.new(p.x, p.y, p.z) - root.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = id, distance
				end
			end
		end
	end
	return best
end

-- Whether this is Studio; answers the caller when it is not.
local function inStudio(player: Player, alias: string): boolean
	if RunService:IsStudio() then
		return true
	end
	tell(player, Dev.StudioOnly:format(alias))
	return false
end

-- /slowmo <scale>: every replay at the caller's table plays at that rate for everyone there
-- (a workspace attribute each client's Main hands to that table's Match.setTimeScale);
-- /slowmo or /slowmo 1 clears it.
local function slowmo(player: Player, args: { string })
	if not inStudio(player, D.Slowmo) then
		return
	end
	local scale = tonumber(args[1] or "1")
	if scale == nil or scale ~= scale or scale < D.SlowmoMin or scale > D.SlowmoMax then
		try(player, "Slowmo")
		return
	end
	local id = nearTable(player)
	workspace:SetAttribute(D.SlowmoAttribute .. id, if scale == 1 then nil else scale)
	tell(
		player,
		if scale == 1 then Dev.SlowmoOff:format(id) else Dev.SlowmoSet:format(id, tostring(scale))
	)
end

-- /hold <seconds>: every replay at the caller's table stops at that shot time and stays (a
-- workspace attribute each client's Main hands to that table's Match.setHold); /hold alone
-- lets go.
local function hold(player: Player, args: { string })
	if not inStudio(player, D.Hold) then
		return
	end
	local at = if args[1] then tonumber(args[1]) else nil
	if args[1] and (at == nil or at ~= at or at < 0 or at > D.HoldMax) then
		try(player, "Hold")
		return
	end
	local id = nearTable(player)
	workspace:SetAttribute(D.HoldAttribute .. id, at)
	tell(player, if at then Dev.HoldSet:format(id, tostring(at)) else Dev.HoldOff:format(id))
end

-- /abilitysetup <id|name>: the caller's table racked in the ult's Config.Ults.Setups layout
-- through the QA fixture (ServerStorage.PoolMatchQA: a new game vs the QA opponent, the
-- caller's turn in Aiming), the ult put in their selected slot and armed at once.
local function abilitySetup(player: Player, args: { string })
	if not inStudio(player, D.AbilitySetup) then
		return
	end
	if #args == 0 then
		try(player, "AbilitySetup")
		return
	end
	local id = findUlt(args)
	if id == nil then
		tell(
			player,
			Dev.BadUlt:format(table.concat(args, " "), table.concat(UltCatalog.list(), ", "))
		)
		return
	end
	local name = UltCatalog.name(id)
	local setup = U.Setups[id]
	if setup == nil then
		tell(player, Dev.NoSetup:format(name))
		return
	end
	if not PlayerData.setUlt(player, id) then
		tell(player, Dev.NotLoaded)
		return
	end
	local hook = ServerStorage:FindFirstChild("PoolMatchQA")
	if not (hook and hook:IsA("BindableFunction")) then
		tell(player, Dev.SetupFailed:format("no PoolMatchQA"))
		return
	end
	-- String keys: a table crossing a BindableFunction keeps them (the fixture reads tonumber).
	local spots: { [string]: { number } | false } = {
		["0"] = { setup.Cue[1], setup.Cue[2] },
	}
	for ball, spot in setup.Spots do
		local at: { number }? = if spot then spot :: any else nil
		spots[tostring(ball)] = if at then { at[1], at[2] } else false
	end
	local tableId = nearTable(player)
	local ok, err = pcall(function()
		hook:Invoke("fixture", tableId, {
			phase = "Aiming",
			userId = player.UserId,
			spots = spots,
			open = setup.Groups == "open",
			groups = setup.Groups,
			seconds = D.SetupClockSeconds,
		})
	end)
	if not ok then
		tell(player, Dev.SetupFailed:format(tostring(err)))
		return
	end
	tell(player, Dev.SetupDone:format(tableId, name, SETUP_NOTES[id] or ""))
	local armed, reason = UltService.arm(player, id)
	if not armed then
		ultAnswer(player, false, reason, "")
	end
end

local function econHelp(player: Player)
	tell(player, Dev.EconHelp)
	for _, key in ECON do
		local what = WHAT[key]:format(table.unpack(WHAT_ARGS[key] or {}))
		tell(player, Dev.HelpLine:format(usage(key), what))
	end
end

function DevCommands.start()
	for _, hold in { "Day", "Sunset" } do
		command(hold, D[hold], function()
			DevCommands.toward(hold)
		end)
	end
	command("Rank", D.Rank, setRank)
	command("Xp", D.Xp, function(player, args)
		-- XP is never lost (ECONOMY 4.1): only a gain.
		local n = amount(args[1])
		local typed = tonumber(args[1] or "")
		if typed ~= nil and typed < 0 then
			tell(player, Dev.XpNeverLost:format(D.Xp))
		elseif n == nil or n < 1 then
			tell(player, Dev.BadAmount:format(D.Xp))
		elseif not Ranking.addXp(player, n) then
			tell(player, Dev.NotLoaded)
		end
	end)
	command("Money", D.Money, function(player, args)
		local n = amount(args[1])
		if n == nil then
			tell(player, Dev.BadAmount:format(D.Money))
		elseif PlayerData.setMoney(player, n) then
			tell(player, Dev.MoneySet:format(Format.money(n)))
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("AddMoney", D.AddMoney, function(player, args)
		local n = amount(args[1])
		if n == nil or n < 1 then
			tell(player, Dev.BadAmount:format(D.AddMoney))
		elseif PlayerData.addMoney(player, n, "DevCommand") then
			-- The flying cash from the middle of the screen (no pocket).
			Net.get("MoneyGrant"):FireClient(player, {
				tableId = 0,
				epoch = 0,
				seq = 0,
				total = n,
				grants = {
					{ ball = 0, amount = n, kind = "Ball", at = workspace:GetServerTimeNow() },
				},
			})
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("Result", D.Result, previewResult)
	command("NewRank", D.NewRank, previewNewRank)
	command("ResetData", D.ResetData, function(player)
		-- A new player's save holds only Classic: the cues it held leave the counts.
		local snapshot = PlayerData.snapshot(player)
		if not snapshot or not PlayerData.reset(player) then
			tell(player, Dev.NotLoaded)
			return
		end
		uncount(snapshot)
		tell(player, Dev.Reset)
	end)
	command("RankHelp", D.RankHelp, function(player)
		tell(player, Dev.Help)
	end)

	-- The economy.
	command("GiveCue", D.GiveCue, giveCue)
	command("GiveCase", D.GiveCase, giveCase)
	command("OpenCase", D.OpenCase, openCase)
	command("Inv", D.Inv, showInventory)
	command("ClearInv", D.ClearInv, clearInventory)
	command("Dupes", D.Dupes, giveDupes)
	command("SetDay", D.SetDay, setDay)
	command("NewDay", D.NewDay, function(player)
		tell(player, if PlayerData.newDay(player) then Dev.NewDay else Dev.NotLoaded)
	end)
	command("Playtime", D.Playtime, function(player, args)
		local minutes = wholeIn(args[1], 0, 24 * 60)
		if minutes == nil then
			try(player, "Playtime")
		elseif PlayerData.setPlayMinutes(player, minutes) then
			tell(player, Dev.PlaytimeSet:format(minutes))
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("Buy", D.Buy, buy)
	command("Vip", D.Vip, pass("Vip"))
	command("FastOpen", D.FastOpen, pass("FastOpen"))
	command("Party", D.Party, function(player)
		local endsAt = Store.startParty(player)
		tell(player, Dev.Party:format(math.max(0, math.ceil((endsAt - os.time()) / 60))))
	end)
	command("Policy", D.Policy, function(player, args)
		local on = ({ restricted = true, normal = false } :: { [string]: boolean })[args[1] or ""]
		if on == nil then
			try(player, "Policy")
			return
		end
		Items.setRestricted(player, on)
		tell(player, if on then Dev.PolicyOn else Dev.PolicyOff)
	end)
	command("Sale", D.Sale, sale)
	command("Rookie", D.Rookie, function(player, args)
		local n = wholeIn(args[1], 0, S.StatCap)
		if n == nil then
			try(player, "Rookie")
		elseif PlayerData.setRealMatches(player, n) then
			local left = math.max(0, Config.Ranks.Boosts.RookieMatches - n)
			tell(player, Dev.RookieSet:format(n, left))
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("FreeCase", D.FreeCase, freeCase)
	command("EconHelp", D.EconHelp, econHelp)

	-- Ultimates.
	command("UltBar", D.UltBar, function(player, args)
		local n = wholeIn(args[1], 0, U.BarMax)
		if n == nil then
			try(player, "UltBar")
			return
		end
		local ok, reason = UltService.setBar(player, n)
		ultAnswer(player, ok, reason, Dev.UltBarSet:format(n))
	end)
	command("UltFull", D.UltFull, function(player)
		local ok, reason = UltService.fill(player)
		ultAnswer(player, ok, reason, Dev.UltBarSet:format(U.BarMax))
	end)
	command("UltArm", D.UltArm, function(player)
		local ok, reason = UltService.arm(player)
		ultAnswer(
			player,
			ok,
			reason,
			Dev.UltArmed:format(UltCatalog.name(UltService.equipped(player)))
		)
	end)
	command(
		"Spins",
		D.Spins,
		ultCount("Spins", U.Earn.MaxSpins, PlayerData.setUltSpins, function(n)
			return Dev.SpinsSet:format(n)
		end)
	)
	command(
		"Lucky",
		D.Lucky,
		ultCount("Lucky", U.Earn.MaxSpins, PlayerData.setUltLucky, function(n)
			return Dev.LuckySet:format(n)
		end)
	)
	command(
		"Pity",
		D.Pity,
		ultCount("Pity", U.Roll.PityAt - 1, PlayerData.setUltPity, function(n)
			return Dev.PitySet:format(n, U.Roll.PityAt)
		end)
	)
	command("FreeSpin", D.FreeSpin, function(player)
		tell(
			player,
			if PlayerData.setFreeSpin(player, true) then Dev.FreeSpinReady else Dev.NotLoaded
		)
	end)
	command("Ult", D.Ult, function(player, args)
		if #args == 0 then
			try(player, "Ult")
			return
		end
		local id = findUlt(args)
		if id == nil then
			tell(
				player,
				Dev.BadUlt:format(table.concat(args, " "), table.concat(UltCatalog.list(), ", "))
			)
		elseif PlayerData.setUlt(player, id) then
			tell(player, Dev.UltSet:format(UltCatalog.name(id)))
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("UltsAll", D.UltsAll, function(player, args)
		local on = ({ on = true, off = false } :: { [string]: boolean })[args[1] or ""]
		if on == nil then
			try(player, "UltsAll")
			return
		end
		UltSpins.setDevAll(player, on)
		tell(player, if on then Dev.UltsAllOn else Dev.UltsAllOff)
	end)
	command("OpUlt", D.OpUlt, function(player)
		-- It fills other players' bars, so only in Studio (the QA opponent), never live.
		if not RunService:IsStudio() then
			tell(player, Dev.OpUltNone)
			return
		end
		local n = UltService.fillOpponent(player)
		tell(player, if n > 0 then Dev.OpUlt:format(n) else Dev.OpUltNone)
	end)
	command("Slowmo", D.Slowmo, slowmo)
	command("Hold", D.Hold, hold)
	command("AbilitySetup", D.AbilitySetup, abilitySetup)
	command("UltHelp", D.UltHelp, ultHelp)

	-- Studio only: tests type a command through ServerStorage.DevCommandsQA, since a script
	-- cannot type into Roblox's chat box: Invoke(userId, "/givecue chalk dust 3") -> (true,
	-- { the lines told back, in order }), or (false, {}) when that player is not here. Every
	-- command in `handlers` is reachable. A /buy waits for its grant (up to about 15 s) so its
	-- answer is in the lines; /opencase's reel request reaches the client a moment later.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DevCommandsQA"
		hook.OnInvoke = function(userId: number, text: string)
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				return false, {}
			end
			local lines = {}
			captured[player] = lines
			local ok, err = pcall(function(): any
				dispatch(player, text, true)
				return nil
			end)
			captured[player] = nil
			if not ok then
				error(err, 0)
			end
			return true, lines
		end
		hook.Parent = game:GetService("ServerStorage")
	end
end

return DevCommands
