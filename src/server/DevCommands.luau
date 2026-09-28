--!strict
-- DevCommands: developer chat commands, checked here on the server (Config.Debug.Commands).
-- The rank and money ones (/rank, /xp, /money, /addmoney, /result, /newrank, /resetdata,
-- /rankhelp) act on the caller only and answer privately (DevNotice); they work in a live
-- server too, for the same allowed people.
-- /day and /sunset send the day/sunset cycle toward that state for the whole server, through
-- its one-minute fade (LightCycle.offsetToward): the offset goes on a workspace attribute every
-- client's DayCycle reads, and the cycle runs on from there. Anyone not allowed (not in Studio, not listed, not the group's owner) gets
-- nothing, so no player can change everyone's sky.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightCycle = require(Shared:WaitForChild("LightCycle"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared.Progression.Format)
local Ranks = require(Shared.Progression.Ranks)
local PlayerData = require(script.Parent.PlayerData)
local Ranking = require(script.Parent.Ranking)

local D = Config.Debug.Commands
local C = Config.Lighting.Cycle

local DevCommands = {}

--- Sends the cycle toward "Day" or "Sunset" (the commands' work; Studio tests call it too).
function DevCommands.toward(hold: string)
	local t = workspace:GetServerTimeNow() * C.Speed
	local offset = workspace:GetAttribute(C.OffsetAttribute)
	local now = if type(offset) == "number" then offset else 0
	workspace:SetAttribute(C.OffsetAttribute, LightCycle.offsetToward(t, now, C, hold))
end

local function allowed(userId: number): boolean
	if RunService:IsStudio() or table.find(D.UserIds, userId) ~= nil then
		return true
	end
	if game.CreatorType ~= Enum.CreatorType.Group then
		return userId == game.CreatorId
	end
	local player = Players:GetPlayerByUserId(userId)
	local ok, rank = pcall(function()
		return if player then player:GetRankInGroup(game.CreatorId) else 0
	end)
	return ok and rank >= D.GroupRank
end

-- `run` gets the caller and the words typed after the alias.
-- Every command by its alias, for the Studio test hook (DevCommands.start).
local handlers: { [string]: (Player, { string }) -> () } = {}

-- Runs the command typed in `text` for `player`, if they may use it.
local function dispatch(player: Player, text: string)
	if not allowed(player.UserId) then
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

-- A private line in the caller's chat window.
local function tell(player: Player, text: string)
	Net.get("DevNotice"):FireClient(player, text)
end

-- A whole number within the commands' limit, or nil.
local function amount(word: string?, allowNegative: boolean): number?
	local n = tonumber(word or "")
	if n == nil or n ~= n or n % 1 ~= 0 or math.abs(n) > D.MaxAmount then
		return nil
	end
	if n < 0 and not allowNegative then
		return nil
	end
	return n
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
		local xp = Ranks.toXp(tier :: string, division, amount(args[3], false) or 0) or 0
		rank = { RankXp = xp, PeakDivision = index, RatedMatches = math.max(1, data.RatedMatches) }
	end
	if PlayerData.applyRank(player, rank) then
		local shown = Ranks.fromXp(rank.RankXp, rank.RatedMatches > 0)
		tell(player, Dev.RankSet:format(Ranks.name(shown)))
	end
end

-- /result win|lose|draw: the result screen with made-up numbers (the caller against a
-- stand-in opponent), worked out from the caller's real rank but never saved.
local function previewResult(player: Player, args: { string })
	local outcome = ({ win = "Win", lose = "Loss", loss = "Loss", draw = "Draw" })[args[1] or ""]
	local data = PlayerData.read(player)
	if outcome == nil or not data then
		tell(player, if outcome == nil then Dev.BadResult else Dev.NotLoaded)
		return
	end
	local xp = Ranks.applyMatch({
		RankXp = data.RankXp,
		PeakDivision = data.PeakDivision,
		RatedMatches = data.RatedMatches,
	}, { outcome = outcome, opponent = "Player", forfeit = false, mode = "Classic" })
	local you = {
		userId = player.UserId,
		name = player.Name,
		displayName = player.DisplayName,
		tier = xp.after.tier,
		division = xp.after.division,
		left = false,
	}
	local other = {
		userId = 1, -- Roblox's own account, for a real headshot
		name = "Opponent",
		displayName = "Opponent",
		tier = "Gold",
		division = 3,
		left = false,
	}
	local E = Config.Economy
	local balls, nice = 4, 1
	local bonus = if outcome == "Win"
		then E.WinBonus
		elseif outcome == "Loss" then E.LossBonus
		else 0
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
			ballMoney = balls * E.BallPay,
			nice = nice,
			niceMoney = E.NiceShotPay.Bank,
			bonus = bonus,
			reward = xp.rewardTotal,
			total = balls * E.BallPay + E.NiceShotPay.Bank + bonus + xp.rewardTotal,
		},
	})
end

-- /newrank [tier] [division]: the NEW RANK! popup for that rank (yours if none given),
-- as if just reached from the division below. Nothing is saved.
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
	Net.get("RankEvent"):FireClient(player, {
		kind = "Up",
		preview = true,
		before = before,
		after = after,
		reward = Ranks.rewardFor(index).money,
		newTier = division == 1 or tier == "Reyes",
	})
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
		local n = amount(args[1], false)
		if n == nil or n < 1 then
			tell(player, Dev.BadAmount:format(D.Xp))
		elseif not Ranking.addXp(player, n) then
			tell(player, Dev.NotLoaded)
		end
	end)
	command("Money", D.Money, function(player, args)
		local n = amount(args[1], false)
		if n == nil then
			tell(player, Dev.BadAmount:format(D.Money))
		elseif PlayerData.setMoney(player, n) then
			tell(player, Dev.MoneySet:format(Format.money(n)))
		else
			tell(player, Dev.NotLoaded)
		end
	end)
	command("AddMoney", D.AddMoney, function(player, args)
		local n = amount(args[1], false)
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
		tell(player, if PlayerData.reset(player) then Dev.Reset else Dev.NotLoaded)
	end)
	command("RankHelp", D.RankHelp, function(player)
		tell(player, Dev.Help)
	end)
	-- Studio only: tests type a command through ServerStorage.DevCommandsQA
	-- (Invoke(userId, "/rank gold 3")), since a script cannot type into Roblox's chat box.
	if RunService:IsStudio() then
		local hook = Instance.new("BindableFunction")
		hook.Name = "DevCommandsQA"
		hook.OnInvoke = function(userId: number, text: string)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				dispatch(player, text)
			end
			return player ~= nil
		end
		hook.Parent = game:GetService("ServerStorage")
	end
end

return DevCommands
