--!strict
-- TutorialGames: the tutorial's tables and opponents (docs/prompts/TUTORIAL_PROMPT.md steps 3,
-- 4 and 6). TutorialService owns the steps; this module moves them on from what happens at the
-- tables:
--
-- - Arrow1 / Arrow2: the nearest empty 1v1 table is reserved for the player (lobby bots get up
--   and stay off it; TableService's `reservedFor`), and its id goes to the client (the player
--   attribute TutorialTable; 0 while every table is taken). Stepping on its pad moves to
--   Request / Queue; stepping on any other table cancels the tutorial ("OtherTable").
-- - Request: the player's Request opponent brings the tutorial bot onto the pad 2 s later
--   (Config.Bots.Tutorial.JoinDelay); its game starting is Game1. A second real player on the
--   pad before then is a friend's game: the tutorial cancels ("Friend").
--
-- The opponent sits behind one small interface (`Opponent`): the Bots lane's tutorial bot.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Tables = require(script.Parent.TableService)
local BotService = require(script.Parent.Bots.BotService)
local Funnel = require(script.Parent.Funnel)

local T = Config.Tutorial
local G = T.Games

local TutorialGames = {}

-- TutorialService, handed in by start (it requires this module).
local service: any = nil

-- The table reserved for each player (its id).
local reserved: { [Player]: number } = {}
-- A player whose opponent is on its way (no second bot for a second press).
local calling: { [Player]: boolean } = {}

local function log(text: string)
	print("[8ball] Tutorial: " .. text)
end

---------------------------------------------------------------------------------------------
-- The opponent (the Bots lane's tutorial bot, behind one small interface)
---------------------------------------------------------------------------------------------

local Opponent = {}

--- Brings game 1's opponent onto table `t`'s pad (it appears there after JoinDelay); the
--- table starts by itself and the player breaks. Yields for the bot's look; tries again a few
--- times if Roblox answers nothing. True when it was sent.
function Opponent.join(t: any): boolean
	for _ = 1, G.BotTries do
		local bot = BotService.tutorialBot()
		if bot then
			BotService.joinTable(bot, t, { delay = Config.Bots.Tutorial.JoinDelay })
			return true
		end
		task.wait(G.BotRetrySeconds)
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Reserving a table
---------------------------------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Whether a real player sits at table `t`, other than `except`.
local function realSeated(t: any, except: Player?): boolean
	for _, s in t.engine.seats do
		if s.userId > 0 and (except == nil or s.userId ~= except.UserId) then
			return true
		end
	end
	return false
end

-- Whether table `t` can be the player's: a waiting 1v1 table with no real player, no search,
-- not reserved for someone else (lobby bots there will get up).
local function usable(t: any, player: Player): boolean
	local e = t.engine
	return e.teamSize == 1
		and e.phase == "Waiting"
		and t.pad ~= nil
		and not e.search
		and not t.search
		and not realSeated(t, player)
		and (t.reservedFor == nil or t.reservedFor == player.UserId)
end

local function release(player: Player)
	local id = reserved[player]
	reserved[player] = nil
	if id then
		local t = Tables.get(id)
		if t and t.reservedFor == player.UserId then
			t.reservedFor = nil
		end
	end
	if player.Parent then
		player:SetAttribute("TutorialTable", 0)
	end
end

-- Keeps a usable table reserved for the player: the one they have, else the nearest.
local function reserve(player: Player)
	local id = reserved[player]
	local current = if id then Tables.get(id) else nil
	if current and usable(current, player) then
		return
	end
	release(player)
	local root = rootOf(player)
	if root == nil then
		return
	end
	local best, bestGap = nil, math.huge
	for _, t in Tables.all() do
		if usable(t, player) then
			local gap = (t.pad.Position - root.Position).Magnitude
			if gap < bestGap then
				best, bestGap = t, gap
			end
		end
	end
	if best then
		best.reservedFor = player.UserId
		reserved[player] = best.engine.id
		player:SetAttribute("TutorialTable", best.engine.id)
		log(("%s: table %d reserved"):format(player.Name, best.engine.id))
	end
end

--- The table reserved for the player (its id), or nil.
function TutorialGames.reservedTable(player: Player): number?
	return reserved[player]
end

---------------------------------------------------------------------------------------------
-- Watching the steps
---------------------------------------------------------------------------------------------

-- The steps that keep the player's table reserved (the arrow, the pad, the game on it).
local KEEPS: { [string]: boolean } =
	{ Arrow1 = true, Request = true, Game1 = true, Arrow2 = true, Queue = true }

-- The arrow steps and the pad steps they lead to.
local PAD_STEP: { [string]: string } = { Arrow1 = "Request", Arrow2 = "Queue" }
local ARROW_STEP: { [string]: string } = { Request = "Arrow1", Queue = "Arrow2" }

local function watch(player: Player)
	local step = service.step(player)
	if step == nil then
		return
	end
	local seatedAt = Tables.tableOf(player)
	if PAD_STEP[step] then
		reserve(player)
		if seatedAt == nil then
			return
		end
		if seatedAt == reserved[player] then
			if step == "Arrow1" then
				Funnel.onboarding(player, "SteppedOnPad")
			end
			service.setStep(player, PAD_STEP[step])
		else
			service.cancel(player, "OtherTable")
		end
	elseif ARROW_STEP[step] then
		local t = if reserved[player] then Tables.get(reserved[player] :: number) else nil
		if seatedAt == nil or t == nil or seatedAt ~= reserved[player] then
			-- Walked off the pad (or onto another): back to the arrow.
			if seatedAt ~= nil and seatedAt ~= reserved[player] then
				service.cancel(player, "OtherTable")
			else
				calling[player] = nil
				player:SetAttribute("TutorialCalling", false)
				service.setStep(player, ARROW_STEP[step])
			end
			return
		end
		if realSeated(t, player) then
			service.cancel(player, "Friend")
			return
		end
		if step == "Request" and t.engine.phase ~= "Waiting" then
			calling[player] = nil
			player:SetAttribute("TutorialCalling", false)
			Funnel.onboarding(player, "Game1Started")
			service.setStep(player, "Game1")
		end
	elseif not KEEPS[step] and reserved[player] then
		release(player)
	end
end

-- A Request opponent pressed by a tutorial player at their table brings the tutorial bot.
local function onRequest(t: any, host: Player)
	if service.step(host) ~= "Request" or reserved[host] ~= t.engine.id or calling[host] then
		return
	end
	calling[host] = true
	host:SetAttribute("TutorialCalling", true)
	Funnel.onboarding(host, "PressedRequest")
	log(("%s pressed Request opponent at table %d"):format(host.Name, t.engine.id))
	if not Opponent.join(t) then
		calling[host] = nil
		host:SetAttribute("TutorialCalling", false)
		warn("[8ball] Tutorial: no tutorial bot came for " .. host.Name)
	end
end

--- Starts watching the tables. `tutorial` is TutorialService (step, setStep, cancel,
--- firstServer).
function TutorialGames.start(tutorial: any)
	service = tutorial
	-- Nobody in the tutorial's first server sends or sees a Request opponent popup.
	Tables.setRequestFilter(function(host: Player, player: Player): boolean
		return not service.firstServer(host) and not service.firstServer(player)
	end)
	Tables.onRequest(onRequest)
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < G.WatchSeconds then
			return
		end
		since = 0
		for _, player in Players:GetPlayers() do
			local ok, err = pcall(function(): any
				watch(player)
				return nil
			end)
			if not ok then
				warn("[8ball] Tutorial: watching " .. player.Name .. " failed: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		release(player)
		calling[player] = nil
	end)
end

return TutorialGames
