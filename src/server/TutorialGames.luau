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
-- - Queue: Join Global Queue's search turns into the Bots lane's arena bot match after
--   Game2BotAfterSeconds (BotService.setFallbackWait); the arena loads the save as Game2
--   (Steps.resume). Game2: its result moves on to Lobby (the post-match row shows only Lobby).
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
local Simulation = require(Shared.Physics.Simulation)
local Break = require(Shared.Tutorial.Break)
local Rig = require(Shared.Tutorial.Rig)
local UltMatch = require(Shared.Ults.Match)
local Judge = require(Shared.Rules.ShotJudge)

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

-- Game 1's rig on table `t` for `player` (Tutorial/Rig: the fixed rack and break, no clock,
-- the hidden assist, the 8 guard), set while the table still waits for the bot.
local function rig(t: any, player: Player)
	local e = t.engine
	if e.phase ~= "Waiting" then
		return
	end
	e.tutorial = { player = player.UserId }
	e.rackSeed = Break.shot().seed
	e.state = Simulation.newState(e.state.geometry, Break.rack(e.state.geometry))
	e.revision += 1
	Tables.broadcast(t)
end

-- Takes the rig off the player's table while it still waits (they walked off before the bot).
local function unrig(player: Player)
	local id = reserved[player]
	local t = if id then Tables.get(id) else nil
	if t and t.engine.tutorial and t.engine.phase == "Waiting" then
		t.engine.tutorial = nil
	end
end

--- The table reserved for the player (its id), or nil.
function TutorialGames.reservedTable(player: Player): number?
	return reserved[player]
end

---------------------------------------------------------------------------------------------
-- Watching the steps
---------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------
-- Game 1 (the rigged match: Tutorial/Rig does the physics side, this the lessons)
---------------------------------------------------------------------------------------------

-- What happened so far in the player's game 1 (per game: `epoch`).
type Game1 = {
	epoch: number,
	shots: number, -- the player's shots taken (1 = the break, 2 = the aim lesson)
	lastSeq: number,
	filled: boolean, -- the ability bar was filled after the aim shot
	usedAbility: boolean,
	exited: boolean, -- the bot stormed off
	sawHand: boolean, -- the ball-in-hand lesson was shown (side event, once)
	botSeq: number, -- the bot's last shot seen (its scratch is a side event)
}
local games: { [Player]: Game1 } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function gameOf(player: Player, e: any): Game1
	local g = games[player]
	if g == nil or g.epoch ~= e.epoch then
		g = {
			epoch = e.epoch,
			shots = 0,
			lastSeq = 0,
			filled = false,
			usedAbility = false,
			exited = false,
			sawHand = false,
			botSeq = 0,
		}
		games[player] = g
	end
	return g
end

-- The bot seated at `e`, if any.
local function botOf(e: any): any?
	for _, s in e.seats do
		if s.userId < 0 then
			return BotService.get(s.userId)
		end
	end
	return nil
end

-- The player's winning 8: the bot storms off just after it drops, and the result waits for it.
local function exitOn(t: any, e: any, g: Game1)
	local pending = e.pending
	local shot = e.shot
	if g.exited or not (shot and shot.eightWins and pending and pending.outcome) then
		return
	end
	g.exited = true
	local dropAt = shot.startedAt + shot.duration
	for _, ev in pending.outcome.events do
		if ev.type == "pocket" and ev.ball == 8 then
			dropAt = shot.startedAt + ev.t
			break
		end
	end
	local exitAt = dropAt + G.ExitAfterDropSeconds
	if e.deadline and e.deadline < exitAt + G.ExitHoldSeconds then
		e.deadline = exitAt + G.ExitHoldSeconds
		e.revision += 1
		Tables.broadcast(t)
	end
	local bot = botOf(e)
	if bot then
		task.delay(math.max(0, exitAt - now()), function()
			BotService.stormOff(bot)
		end)
	end
end

-- The lesson showing now (the player attribute TutorialLesson; the client shows it):
-- Break, Aim, Ability, Pick, BallInHand, Eight, or "" (nothing to teach this moment).
local function lessonOf(player: Player, e: any, g: Game1): string
	if e.shooter ~= player.UserId then
		return ""
	end
	local phase = e.phase
	if phase == "PocketChoice" then
		return "Eight"
	elseif UltMatch.pickNeeded(e) then
		return "Pick"
	elseif phase ~= "Intro" and phase ~= "Aiming" and phase ~= "Placement" then
		return ""
	elseif e.breakShot then
		return "Break"
	elseif e.ballInHand and (e.placeSeq or 0) == 0 then
		return "BallInHand" -- until they have moved it once
	elseif g.shots == 1 then
		return "Aim"
	elseif g.filled and not g.usedAbility then
		local view = UltMatch.view(e)
		local bar = view.bars[tostring(player.UserId)]
		if bar and bar.ready and view.armed == nil then
			return "Ability"
		end
	end
	return ""
end

-- Watches the player's game 1 at their table.
local function watchGame1(player: Player, t: any)
	local e = t.engine
	local uid = player.UserId
	if not Rig.isPlayer(e, uid) then
		return
	end
	local g = gameOf(player, e)
	local shot = e.shot
	if shot and shot.shooter == uid and shot.seq ~= g.lastSeq then
		g.lastSeq = shot.seq
		g.shots += 1
		local j = e.pending and e.pending.judgement
		if g.shots == 1 then
			Funnel.onboarding(player, "Broke")
		elseif g.shots == 2 and j and j.keep then
			Funnel.onboarding(player, "PottedAimShot")
		end
		if shot.ult and shot.ult.by == uid then
			g.usedAbility = true
			Funnel.onboarding(player, "UsedAbility")
		end
		exitOn(t, e, g)
	end
	-- The bar fills once the aim shot is over (designer: the ability comes after that shot).
	if g.shots >= 2 and not g.filled and e.phase ~= "Resolving" then
		g.filled = true
		if UltMatch.setBar(e, uid, Config.Ults.BarMax) then
			Tables.broadcast(t)
		end
	end
	-- Side events (the funnel lane of step 9): the bot's scratch, ball in hand shown.
	if shot and shot.shooter ~= uid and shot.seq ~= g.botSeq then
		g.botSeq = shot.seq
		local j = e.pending and e.pending.judgement
		if j and j.foul == "Scratch" then
			Funnel.event(player, "TutorialBotScratch")
		end
	end
	if e.calledPocket and e.shooter == uid then
		Funnel.onboarding(player, "CalledEight")
	end
	local lesson = lessonOf(player, e, g)
	if lesson == "Ability" then
		-- Its ult armed counts as used (the press, before the shot).
		local view = UltMatch.view(e)
		if view.armed and view.armed.by == uid then
			g.usedAbility = true
		end
	end
	player:SetAttribute("TutorialLesson", lesson)
	if lesson == "BallInHand" and not g.sawHand then
		g.sawHand = true
		Funnel.event(player, "TutorialBallInHand")
	end
	if lesson == "Pick" then
		local group = Rig.playerGroup(e)
		local pick = Break.lesson(e.state.geometry, e.state.balls, group)
		local ball = if pick then pick.ball else nil
		if ball == nil then
			for _, b in e.state.balls do
				if ball == nil and not b.pocketed and Judge.group(b.id) == group then
					ball = b.id
				end
			end
		end
		player:SetAttribute("TutorialPickBall", ball or 0)
	elseif lesson == "Eight" then
		player:SetAttribute(
			"TutorialPocket",
			Break.eightPocket(e.state.geometry, e.state.balls) or 0
		)
	elseif lesson == "Aim" then
		-- The aim lesson's pot (the client starts the aim a little off it).
		local pot = Break.lesson(e.state.geometry, e.state.balls, Rig.playerGroup(e))
		player:SetAttribute("TutorialAimAngle", if pot then pot.angle else nil)
	end
end

-- The game is over: a win moves on to the rewards (step 5); the player gone from the table
-- (they left mid-game) plays game 1 again from the arrow (designer, 2026-10-03).
local function game1Over(player: Player, t: any?): boolean
	local e = if t then t.engine else nil
	local seat = if e then Rig.playerTeam(e) else nil
	if e and e.phase == "Result" and e.result and Rig.isPlayer(e, player.UserId) then
		if seat and e.result.winner == seat then
			Funnel.onboarding(player, "WonGame1")
			player:SetAttribute("TutorialLesson", "")
			service.setStep(player, "Drop")
			return true
		end
	end
	if e == nil or not Rig.isPlayer(e, player.UserId) or seat == nil then
		player:SetAttribute("TutorialLesson", "")
		games[player] = nil
		service.setStep(player, "Arrow1")
		return true
	end
	return false
end

-- Game 2 (in its arena): once its result shows, the player goes back with Lobby. A win is the
-- funnel's step; a loss is a side event (the bot is a fair Bronze one).
local function game2Over(player: Player)
	local t = Tables.arenaTable()
	local e = if t then t.engine else nil
	if e == nil or e.phase ~= "Result" or e.result == nil then
		return
	end
	local team = nil
	for _, s in e.seats do
		if s.userId == player.UserId then
			team = s.team
		end
	end
	if team == nil then
		return
	end
	if e.result.winner == team then
		Funnel.onboarding(player, "WonGame2")
	else
		Funnel.event(player, "TutorialLostGame2")
	end
	service.setStep(player, "Lobby")
end

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
	if Tables.arenaTable() ~= nil then
		-- An arena has no pads to reserve: only game 2's end is watched here.
		if step == "Game2" then
			game2Over(player)
		end
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
				unrig(player)
				service.cancel(player, "OtherTable")
			else
				calling[player] = nil
				player:SetAttribute("TutorialCalling", false)
				unrig(player)
				service.setStep(player, ARROW_STEP[step])
			end
			return
		end
		if realSeated(t, player) then
			unrig(player)
			service.cancel(player, "Friend")
			return
		end
		if step == "Request" and t.engine.phase ~= "Waiting" then
			calling[player] = nil
			player:SetAttribute("TutorialCalling", false)
			Funnel.onboarding(player, "Game1Started")
			service.setStep(player, "Game1")
		elseif step == "Queue" then
			-- Join Global Queue pressed: the search runs (its bot match comes at once, see
			-- start) until the teleport; a search that ended shows the button again.
			local searching = t.engine.search ~= nil
			if searching and not calling[player] then
				Funnel.onboarding(player, "JoinedGlobalQueue")
			end
			if searching then
				calling[player] = true
			else
				calling[player] = nil
			end
			player:SetAttribute("TutorialCalling", searching)
		end
	elseif step == "Game1" then
		local t = if reserved[player] then Tables.get(reserved[player] :: number) else nil
		if not game1Over(player, t) and t then
			watchGame1(player, t)
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
	rig(t, host)
	Funnel.onboarding(host, "PressedRequest")
	log(("%s pressed Request opponent at table %d"):format(host.Name, t.engine.id))
	if not Opponent.join(t) then
		calling[host] = nil
		host:SetAttribute("TutorialCalling", false)
		warn("[8ball] Tutorial: no tutorial bot came for " .. host.Name)
	end
end

--- Whether the player is on a table's pad or seat (the real server's nudges wait meanwhile).
function TutorialGames.seated(player: Player): boolean
	return Tables.tableOf(player) ~= nil
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
	-- Game 2's search meets the Bots lane's disguised bot (the player's tier, no rematch) at
	-- once instead of after the usual wait.
	BotService.setFallbackWait(function(player: Player): number?
		return if service.step(player) == "Queue" then G.Game2BotAfterSeconds else nil
	end)
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
		games[player] = nil
	end)
end

return TutorialGames
