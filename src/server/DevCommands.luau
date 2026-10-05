--!strict
-- DevCommands: developer chat commands, checked here on the server (Config.Debug.Commands).
-- Only the designer's own account (Config.Debug.Commands.UserIds) may use them; any other
-- player gets nothing, so no player can change everyone's sky, their own save or the shop.
-- - /day and /sunset send the day/sunset cycle toward that state for the whole server, through
--   its one-minute fade (LightCycle.offsetToward): the offset goes on a workspace attribute
--   every client's DayCycle reads, and the cycle runs on from there.
-- - The rank and money ones (/rank, /xp, /money, /addmoney, /result, /newrank, /resetdata;
--   /rankhelp lists them) and the economy ones (/econhelp lists them) act on the caller only
--   and answer privately (DevNotice). A /party or a /restock is this server's, like the real ones.
--   They go through the same server APIs as the game (PlayerData, Ranking, Items, Store,
--   Counters), so they can do nothing the save's own checks refuse. They work in a live server
--   too, for the designer only.
-- - The look check's tools (Studio only; /abilityhelp lists them): /slowmo <scale> sets the
--   replay rate at the caller's table for everyone (a workspace attribute the clients read).
--   /abilitysetup <id|name> puts that ability in the caller's selected slot: the designer's
--   own account only (Config.Debug.Commands.UserIds), in Studio and live.
-- - The giving commands (Config.Debug.Commands.Gives: rank, XP, money, cues, blocks, spins,
--   abilities) are the designer's account only (UserIds), and their last word may be a
--   player's username (or display name) in this server, "@" optional: it acts on that player
--   instead, and the answers come back to the designer with the name in front.
-- - Arguments are read defensively: a bad one answers a usage line, never an error.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
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
local Catalog = require(Shared.Progression.Catalog)
local Inventory = require(Shared.Progression.Inventory)
local LuckyBlocks = require(Shared.Progression.LuckyBlocks)
local Daily = require(Shared.Progression.Daily)
local PlayerData = require(script.Parent.PlayerData)
local Ranking = require(script.Parent.Ranking)
local Items = require(script.Parent.Items)
local Store = require(script.Parent.Store)
local Counters = require(script.Parent.Counters)
local LiveCodes = require(script.Parent.LiveCodes)
local UltService = require(script.Parent.UltService)
local UltSpins = require(script.Parent.UltSpins)
local Tables = require(script.Parent.TableService)
local BotService = require(script.Parent.Bots.BotService)
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

-- The commands that give things (Config.Debug.Commands.Gives), by alias: the designer's own
-- account only, and they may name someone else in this server as the last word.
local gives: { [string]: boolean? } = {}

-- A player given something by someone else's command -> that caller, while it runs: the
-- command's answers go to the caller (tell), never to the one given it.
local givenBy: { [Player]: Player } = {}

local function isDesigner(userId: number): boolean
	return table.find(D.UserIds, userId) ~= nil
end

-- The player in this server whose username (or else display name) is `name`, any case.
local function playerNamed(name: string): Player?
	for _, p in Players:GetPlayers() do
		if string.lower(p.Name) == name then
			return p
		end
	end
	for _, p in Players:GetPlayers() do
		if string.lower(p.DisplayName) == name then
			return p
		end
	end
	return nil
end

-- Runs the command typed in `text` for `player`, if they may use it (`fromScript`: the Studio
-- test hook, a server script rather than a player, may run it for any test player).
local function dispatch(player: Player, text: string, fromScript: boolean?)
	if not fromScript and not allowed(player.UserId) then
		return
	end
	local words = string.split(string.lower(text or ""), " ")
	local alias = words[1] or ""
	local run = handlers[alias]
	if not run then
		return
	end
	-- Giving: the designer only (2026-09-30), whoever else may use the other commands.
	if gives[alias] and not fromScript and not isDesigner(player.UserId) then
		return
	end
	local args = {}
	for i = 2, #words do
		if words[i] ~= "" then
			table.insert(args, words[i])
		end
	end
	-- A giving command's last word may name its receiver: a player in this server ("@" optional).
	local target = player
	local last = args[#args]
	if gives[alias] and last then
		local name = string.gsub(last, "^@", "")
		local found = playerNamed(name)
		if found then
			target = found
			table.remove(args)
		elseif string.sub(last, 1, 1) == "@" then
			Net.get("DevNotice"):FireClient(player, Strings.Dev.NoPlayer:format(name))
			return
		end
	end
	if target == player then
		run(player, args)
		return
	end
	givenBy[target] = player
	local ok, err = pcall(function()
		run(target, args)
	end)
	givenBy[target] = nil
	if not ok then
		error(err, 0)
	end
end

-- `run` gets the caller and the words typed after the alias.
local function command(name: string, alias: string, run: (Player, { string }) -> ())
	handlers[alias] = run
	local giving = table.find(D.Gives, name) ~= nil
	gives[alias] = if giving then true else nil
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev" .. name
	cmd.PrimaryAlias = alias
	local old = OLD_ALIASES[name]
	if old then
		handlers[old] = run
		gives[old] = if giving then true else nil
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

-- A private line in the caller's chat window. While a command gives something to someone else
-- (givenBy), its lines go to the giver instead, with the receiver's name.
local function tell(player: Player, text: string)
	local giver = givenBy[player]
	if giver then
		player, text = giver, Dev.ForPlayer:format(player.Name, text)
	end
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
-- boost that can apply is on (the streak, on a win) so every chip shows, a win brings the
-- Mystery block chip, and `firstwin` the first win's Rare block instead (nothing is given).
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
		boosts = { streak = win },
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
	local boost = Money.boost({ vip = true, party = Store.party() ~= nil })
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
	-- The win's block chip (a sample: nothing is given).
	local block = nil
	if win then
		local kind = if firstWin then Config.BlockOdds.Drop.FirstWin else "Mystery"
		local timer = LuckyBlocks.timer(kind, player:GetAttribute("Vip") == true)
		block = { kind = kind, readyAt = if timer > 0 then os.time() + timer else 0 }
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
		block = block,
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
	-- The rows as Ranking sends them: { index, money, blocks, cue? }, and their totals.
	local rows, total, blocks, cues = {}, 0, {}, {}
	for _, row in Ranks.rewardsBetween(index - 1, index) do
		total += row.money
		table.insert(rows, {
			index = row.index,
			money = row.money,
			blocks = table.clone(row.blocks),
			cue = row.cue,
		})
		for _, kind in Config.LuckyBlocks.Order do
			local count = row.blocks[kind]
			if count then
				blocks[kind] = (blocks[kind] or 0) + count
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
		rewardBlocks = blocks,
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

-- The rarities with a pull cutscene (Rare and up), as typed, for the usage line.
local CUTSCENES: { string } = {}
for index, rarity in Config.BlockOdds.Rarities do
	if index >= (table.find(Config.BlockOdds.Rarities, "Rare") or math.huge) then
		table.insert(CUTSCENES, rarity)
	end
end
local CUTSCENE_WORDS = string.lower(table.concat(CUTSCENES, "|"))

--- A cutscene's rarity from typed words ("legendary", "mythical"), or nil.
local function findCutscene(words: { string }): string?
	local key = squash(table.concat(words, ""))
	for _, rarity in CUTSCENES do
		local name = squash(rarity)
		if key == name or key == name .. "al" then -- "mythical" too
			return rarity
		end
	end
	return nil
end

-- A lucky block kind from typed words ("yellow", "blue lucky block"), or nil.
local function findBlock(words: { string }): string?
	local key = trim(trim(squash(table.concat(words, "")), "block"), "lucky")
	for _, id in Config.LuckyBlocks.Order do
		if squash(id) == key then
			return id
		end
	end
	return nil
end

-- The lucky block kinds as they are typed, for the usage line: "yellow|blue".
local BLOCK_WORDS = string.lower(table.concat(Config.LuckyBlocks.Order, "|"))

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
	GiveBlock = { BLOCK_WORDS },
	Cutscene = { CUTSCENE_WORDS },
	SetDay = { #Config.Daily.Streak, Config.Daily.WeeksForBonus },
	Code = { D.Code },
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
	"GiveBlock",
	"Cutscene",
	"Inv",
	"ClearInv",
	"Dupes",
	"SetDay",
	"NewDay",
	"Playtime",
	"Buy",
	"Vip",
	"Party",
	"Policy",
	"Restock",
	"Code",
	"Limited",
}

-- Whether a cue's copies in existence are counted (Counters), as the game counts them: every
-- cue but Classic (block cues, the Exclusive tier cues a rank-up gives (Ranking), the Starter
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
		-- The designer's own unnumbered copy (2026-10-05): never someone else's, never numbered,
		-- counted or traded, so the numbered pool is untouched.
		if not isDesigner(player.UserId) then
			tell(player, Dev.UniqueOwnerOnly:format(cueName(id)))
		elseif PlayerData.giveOwnerCopy(player, id) then
			tell(player, Dev.GaveOwnerCopy:format(cueName(id)))
		elseif PlayerData.read(player) == nil then
			tell(player, Dev.NotLoaded)
		else
			tell(player, Dev.UniqueOwned:format(cueName(id)))
		end
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

-- /giveblock <kind> [count]: lucky blocks at the end of the hotbar.
local function giveBlock(player: Player, args: { string })
	local words, countWord = splitCount(args)
	local count = if countWord then wholeIn(countWord, 1, D.MaxGive) else 1
	if #words == 0 or count == nil then
		try(player, "GiveBlock")
		return
	end
	local kind = findBlock(words)
	if kind == nil then
		tell(player, Dev.BadBlock:format(table.concat(words, " "), BLOCK_WORDS))
	elseif PlayerData.giveLuckyBlocks(player, kind, count) then
		tell(player, Dev.GaveBlock:format(Strings.LuckyBlocks.Names[kind] or kind, count))
	else
		tell(player, Dev.NotLoaded)
	end
end

-- /cutscene <rarity>: asks the caller's client to play that rarity's pull cutscene on its own
-- (a table DevNotice; nothing is rolled or given).
local function cutscene(player: Player, args: { string })
	local rarity = findCutscene(args)
	if rarity == nil then
		try(player, "Cutscene")
		return
	end
	tell(player, Dev.Cutscene:format(rarity))
	-- Its reveal reaches everyone in the server as a real pull's does (the aurora).
	require(script.Parent.LuckyBlockService).expectReveal(player, rarity)
	Net.get("DevNotice"):FireClient(player, { kind = "Cutscene", rarity = rarity })
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

-- /inv: the equipped cue, the lucky blocks held and the cues owned (Classic left out).
local function showInventory(player: Player)
	local snapshot = PlayerData.snapshot(player)
	local data = PlayerData.read(player)
	if not snapshot or not data then
		tell(player, Dev.NotLoaded)
		return
	end
	tell(player, Dev.InvEquipped:format(cueName(snapshot.equipped)))
	local blocks = {}
	local blockNames: { [string]: string } = Strings.LuckyBlocks.Names :: any
	for _, kind in Config.LuckyBlocks.Order do
		local count = LuckyBlocks.count(data.LuckyBlocks, kind)
		if count > 0 then
			table.insert(blocks, Dev.InvCount:format(blockNames[kind] or kind, count))
		end
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
	local lines: { string } = if #blocks > 0
		then packLines(Dev.InvBlocks, blocks)
		else { Dev.InvNoBlocks }
	local cueLines: { string } = if #cues > 0
		then packLines(Dev.InvCues:format(#cues, copies), cues)
		else { Dev.InvNoCues }
	table.move(cueLines, 1, #cueLines, #lines + 1, lines)
	for _, line in lines do
		tell(player, line)
	end
end

-- /clearinv: every cue but Classic and every lucky block gone; the copies in existence follow.
local function clearInventory(player: Player)
	local snapshot = PlayerData.snapshot(player)
	if not snapshot or not PlayerData.clearInventory(player) then
		tell(player, Dev.NotLoaded)
		return
	end
	uncount(snapshot)
	tell(player, Dev.Cleared)
end

-- /dupes: D.DupeCopies copies of D.DupeKinds different random Common and Uncommon block cues.
local function giveDupes(player: Player)
	local pool = {}
	for _, rarity in { "Common", "Uncommon" } do
		for _, cue in Catalog.ofRarity(rarity) do
			if cue.Group == "Block" and not cue.Vaulted then
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

-- /vip on|off: fake owning that game pass for this session.
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

-- /abilitysetup <id|name> [player]: puts that ability in the selected slot, nothing more (no
-- table, no match: the designer, 2026-09-30). A giving command (Config.Debug.Commands.Gives):
-- the designer's own account only, in Studio and live alike, checked in dispatch.
local function abilitySetup(player: Player, args: { string })
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
	if not PlayerData.setUlt(player, id) then
		tell(player, Dev.NotLoaded)
		return
	end
	tell(player, Dev.AbilitySet:format(UltCatalog.name(id)))
end

-- /botrank <tier> | off: the tier of every bot the caller meets (the Bots lane's testing
-- tool; the designer's account only, like every command here).
local function botRank(player: Player, args: { string })
	local word = args[1]
	if word == nil then
		tell(player, Dev.BotRankBad:format("", table.concat(Config.Ranks.Tiers, ", ")))
		return
	end
	if string.lower(word) == "off" then
		BotService.forceTier(player.UserId, nil)
		tell(player, Dev.BotRankOff)
		return
	end
	for _, tier in Config.Ranks.Tiers do
		if string.lower(tier) == string.lower(word) then
			BotService.forceTier(player.UserId, tier)
			tell(player, Dev.BotRankSet:format(tier))
			return
		end
	end
	tell(player, Dev.BotRankBad:format(word, table.concat(Config.Ranks.Tiers, ", ")))
end

-- /lobbybots on | off | <count>: the lobby bots in this server (the Bots lane's testing
-- tool; Studio starts with them off).
local function lobbyBots(player: Player, args: { string })
	local word = string.lower(args[1] or "")
	local n = tonumber(word)
	if word == "on" then
		BotService.startLobby({})
		tell(player, Dev.LobbyBotsOn:format(Config.Bots.Lobby.People))
	elseif word == "off" then
		BotService.startLobby(nil)
		tell(player, Dev.LobbyBotsOff)
	elseif n and n >= 0 and n <= 30 and n == math.floor(n) then
		BotService.startLobby({ count = n })
		tell(player, Dev.LobbyBotsCount:format(n))
	else
		tell(player, Dev.LobbyBotsBad)
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
	command("GiveBlock", D.GiveBlock, giveBlock)
	command("Cutscene", D.Cutscene, cutscene)
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
	command("Restock", D.Restock, function(player, args)
		local words = {
			uncommon = "Uncommon",
			rare = "Rare",
			epic = "Epic",
			legendary = "Legendary",
			mystery = "Mystery",
		}
		local itemId = words[string.lower(args[1] or "")]
		if itemId == nil then
			try(player, "Restock")
			return
		end
		local slot = Items.forceRestock(itemId)
		tell(player, if slot then Dev.RestockForced:format(itemId) else Dev.RestockNone)
	end)
	command("Code", D.Code, function(player, args)
		local verb = string.lower(args[1] or "")
		if verb == "list" then
			local onList, offList = {}, {}
			local live = LiveCodes.on()
			for _, code in LiveCodes.all() do
				table.insert(if live[code] then onList else offList, code)
			end
			local function words(list: { string }): string
				return if #list > 0 then table.concat(list, ", ") else Dev.CodeNone
			end
			tell(player, Dev.CodeList:format(words(onList), words(offList)))
			return
		end
		local code = string.upper(args[2] or "")
		if (verb ~= "on" and verb ~= "off") or code == "" then
			try(player, "Code")
			return
		end
		if not table.find(LiveCodes.all(), code) then
			tell(player, Dev.CodeNotLive:format(code, table.concat(LiveCodes.all(), ", ")))
			return
		end
		if LiveCodes.set(code, verb == "on") then
			tell(player, (if verb == "on" then Dev.CodeOn else Dev.CodeOff):format(code))
		else
			tell(player, Dev.CodeFailed:format(code))
		end
	end)
	command("Limited", D.Limited, function(player, args)
		local verb = string.lower(args[1] or "")
		if verb == "start" then
			local minutes = if args[2] ~= nil
				then wholeIn(args[2], 1, 365 * 24 * 60)
				else Config.Shop.Limited[1].Seconds // 60
			if minutes == nil then
				try(player, "Limited")
				return
			end
			Items.setLimitedWindow(os.time(), minutes * 60)
			tell(player, Dev.LimitedStart:format(minutes))
		elseif verb == "end" then
			-- Ended a second ago: refused as "Ended" from now on.
			Items.setLimitedWindow(os.time() - 2, 1)
			tell(player, Dev.LimitedEnd)
		elseif verb == "off" then
			Items.setLimitedWindow(nil, nil)
			tell(player, Dev.LimitedOff)
		else
			try(player, "Limited")
		end
	end)
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
	command("BotRank", D.BotRank, botRank)
	command("LobbyBots", D.LobbyBots, lobbyBots)
	-- The tutorial lane: /tutorial reset | skip | off | step <name> (TutorialService.dev).
	command("Tutorial", D.Tutorial, function(player: Player, args: { string })
		tell(player, require(script.Parent.TutorialService).dev(player, args))
	end)

	-- Studio only: tests type a command through ServerStorage.DevCommandsQA, since a script
	-- cannot type into Roblox's chat box: Invoke(userId, "/givecue chalk dust 3") -> (true,
	-- { the lines told back, in order }), or (false, {}) when that player is not here. Every
	-- command in `handlers` is reachable. A /buy waits for its grant (up to about 15 s) so its
	-- answer is in the lines.
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
