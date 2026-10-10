--!strict
-- TutorialGames: tutorial v2's tables and game 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.2-4.4).
-- TutorialService owns the steps; this module moves them on from what happens at the tables:
--
-- - Arrow: the nearest empty 1v1 table is reserved for the player (lobby bots get up and stay
--   off it; TableService's `reservedFor`) and its id goes to the client (the player attribute
--   TutorialTable; 0 while every table is taken). Stepping onto any pad moves to Pad: an empty
--   1v1 table becomes the tutorial table; one where a real person waits is a fair game.
-- - Pad: alone on a 1v1 pad, the table is rigged and the tutorial bot comes (path S; TutorialBot
--   walks it over from where it strolls). A real
--   person on the pad before the game starts makes it a fair game (path R): no rig, no hidden
--   help. Walking off the pad goes back to the arrow.
-- - Game1: the game started. Path S is the rigged game (Tutorial/Rig does the physics side,
--   this the lessons: the TutorialLesson attribute); path R a normal game. A won game 1 moves
--   to Result (the chain); a lost fair game goes back to the arrow (the next time they sit
--   alone it is the rigged game); a game left halfway goes back to the arrow.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Placement = require(Shared.Placement)
local Engine = require(Shared.Rules.MatchEngine)
local Tables = require(script.Parent.TableService)
local TutorialBot = require(script.Parent.TutorialBot)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)
local Simulation = require(Shared.Physics.Simulation)
local Break = require(Shared.Tutorial.Break)
local Rig = require(Shared.Tutorial.Rig)
local Plan = require(Shared.Tutorial.Plan)
local UltMatch = require(Shared.Ults.Match)
local Judge = require(Shared.Rules.ShotJudge)

local T = Config.Tutorial
local G = T.Games

local TutorialGames = {}

-- TutorialService, handed in by start (it requires this module).
local service: any = nil

-- The table reserved for each player (its id).
local reserved: { [Player]: number } = {}
-- A player whose opponent is on its way (no second bot for a second look).
local calling: { [Player]: boolean } = {}

local function log(text: string)
	print("[8ball] Tutorial: " .. text)
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

-- Whether a bot sits at table `t`.
local function botSeated(t: any): boolean
	for _, s in t.engine.seats do
		if s.userId < 0 then
			return true
		end
	end
	return false
end

-- Whether table `t` can be the player's rigged table: a waiting 1v1 table with no real player
-- but them, no search, not reserved for someone else (lobby bots there will get up).
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

local function hold(player: Player, t: any)
	if reserved[player] == t.engine.id then
		return
	end
	release(player)
	t.reservedFor = player.UserId
	reserved[player] = t.engine.id
	player:SetAttribute("TutorialTable", t.engine.id)
	log(("%s: table %d reserved"):format(player.Name, t.engine.id))
end

-- Team tables lent to the tutorial as a 1v1 (the backup, 4.12), until they are free again.
local borrowed: { [any]: boolean } = {}

-- Whether team table `t` can be lent: waiting, nobody on it or its pad, no search, not held.
local function lendable(t: any): boolean
	local e = t.engine
	return e.teamSize > 1
		and e.phase == "Waiting"
		and t.pad ~= nil
		and Engine.count(e) == 0
		and not e.search
		and not t.search
		and t.reservedFor == nil
		and not Tables.standingOnPad(t)
end

-- Every lent table that is free again goes back to its own mode.
local function giveBack()
	for t in borrowed do
		local e = t.engine
		if
			t.reservedFor == nil
			and e.phase == "Waiting"
			and Engine.count(e) == 0
			and not e.search
			and not t.search
			and not Tables.standingOnPad(t)
			and Tables.setMode(t, Placement.teamSizeOf(e.id) or 1)
		then
			borrowed[t] = nil
			log(("table %d back to its own mode"):format(e.id))
		end
	end
end

-- Keeps a usable table reserved for the player: the one they have, else the nearest.
local function reserve(player: Player)
	local id = reserved[player]
	local current = if id then Tables.get(id) else nil
	if current and usable(current, player) then
		return
	end
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
	if best == nil then
		-- Every 1v1 table is busy: the nearest free team table plays game 1 as a 1v1.
		for _, t in Tables.all() do
			if lendable(t) then
				local gap = (t.pad.Position - root.Position).Magnitude
				if gap < bestGap then
					best, bestGap = t, gap
				end
			end
		end
		if best and Tables.setMode(best, 1) then
			borrowed[best] = true
			log(("table %d lent as a 1v1 for %s"):format(best.engine.id, player.Name))
		else
			best = nil
		end
	end
	if best then
		hold(player, best)
	else
		release(player)
	end
end

-- Game 1's rig on table `t` for `player` (Tutorial/Rig: the fixed rack and break, the hidden
-- help, the 8 guard), set while the table still waits for the bot.
local function rig(t: any, player: Player)
	local e = t.engine
	if e.phase ~= "Waiting" then
		return
	end
	local shot = Break.shot()
	e.tutorial = Rig.new(player.UserId)
	e.rackSeed = shot.seed
	e.rackLayout = shot.layout
	e.state = Simulation.newState(e.state.geometry, Break.rack(e.state.geometry, shot))
	e.revision += 1
	Tables.broadcast(t)
end

-- Takes the rig off table `t` while it still waits (they walked off, or a real person came).
local function unrig(t: any?)
	if t and t.engine.tutorial and t.engine.phase == "Waiting" then
		t.engine.tutorial = nil -- its rack (and rackLayout, its order) stays until the table resets
	end
end

-- Takes the player's rig off every table still waiting (they skipped, the tutorial ended or
-- they left the server before the bot came): no rigged game for anyone else.
local function unrigFor(player: Player)
	for _, t in Tables.all() do
		if Rig.isPlayer(t.engine, player.UserId) then
			unrig(t)
		end
	end
end

--- The table reserved for the player (its id), or nil.
function TutorialGames.reservedTable(player: Player): number?
	return reserved[player]
end

---------------------------------------------------------------------------------------------
-- Game 1 on path S (the rigged match: Tutorial/Rig picks each turn's lesson and plays the
-- physics side; this shows the lesson to the client and logs the funnel)
---------------------------------------------------------------------------------------------

-- What the server saw of the player's game 1 (per game: `epoch`).
type Game1 = {
	epoch: number,
	lastSeq: number, -- the last shot of theirs seen
}
local games: { [Player]: Game1 } = {}

local function gameOf(player: Player, e: any): Game1
	local g = games[player]
	if g == nil or g.epoch ~= e.epoch then
		g = { epoch = e.epoch, lastSeq = 0 }
		games[player] = g
	end
	return g
end

-- The lesson showing now (the player attribute TutorialLesson; the client shows it): Break,
-- Aim, Combo, Ability, BallInHand, Eight, Pick, Away (their turn after one they let run out),
-- or "" (nothing to teach this moment).
local function lessonOf(player: Player, e: any): string
	if e.shooter ~= player.UserId then
		return ""
	end
	local rig = e.tutorial
	local phase = e.phase
	-- Ball in hand lined up for the combination: its pointer after a few seconds.
	local comboDue = rig.lesson == "Combo"
		and workspace:GetServerTimeNow() - (e.phaseStartedAt or 0) >= T.Lessons.HandComboSeconds
	if phase == "PocketChoice" then
		return "Eight"
	elseif UltMatch.pickNeeded(e) then
		return "Pick"
	elseif phase ~= "Intro" and phase ~= "Aiming" and phase ~= "Placement" then
		return ""
	elseif rig.lesson == "Break" then
		return "Break"
	elseif
		e.ballInHand
		and rig.handTurn
		and not rig.done.Hand
		and (e.placeSeq or 0) == 0
		and not comboDue
	then
		-- Until they have moved it once (with the combination lined up: for a few seconds).
		return "BallInHand"
	elseif rig.lesson == "Aim" or rig.lesson == "Combo" then
		return rig.lesson
	elseif rig.lesson == "Ability" then
		local view = UltMatch.view(e)
		local bar = view.bars[tostring(player.UserId)]
		return if bar and bar.ready and view.armed == nil then "Ability" else ""
	end
	local team = Rig.playerTeam(e)
	if team and (e.timeouts[team] or 0) >= 1 then
		return "Away"
	end
	return ""
end

-- Whether ball `id` dropped in the shot being resolved.
local function dropped(e: any, id: number): boolean
	local outcome = e.pending and e.pending.outcome
	for _, b in if outcome then outcome.finalBalls else {} do
		if b.id == id then
			return b.pocketed == true
		end
	end
	return false
end

-- Watches the player's rigged game 1 at their table.
local function watchRigged(player: Player, t: any)
	local e = t.engine
	local uid = player.UserId
	if not Rig.isPlayer(e, uid) then
		return
	end
	local rig = e.tutorial
	local g = gameOf(player, e)
	local shot = e.shot
	if shot and shot.shooter == uid and shot.seq ~= g.lastSeq and e.pending then
		-- A shot of theirs, being resolved (its turn's lesson is still set).
		g.lastSeq = shot.seq
		local j = e.pending.judgement
		local made = j ~= nil and j.keep and j.foul == nil
		local plan = rig.plan
		if rig.lesson == "Break" then
			Funnel.once(player, "PathS", "Break")
		elseif rig.lesson == "Aim" and made then
			Funnel.once(player, "PathS", "AimPotted")
		elseif rig.lesson == "Combo" and made and plan and dropped(e, plan.b) then
			Funnel.once(player, "PathS", "ComboPotted")
		end
		if shot.ult and shot.ult.by == uid then
			Funnel.once(player, "PathS", "AbilityUsed")
			if made then
				Funnel.once(player, "PathS", "AbilityPotted")
			end
		end
	end
	if e.calledPocket and e.shooter == uid then
		Funnel.once(player, "PathS", "EightCalled")
	end
	-- The lesson's details first, then its name (the client reads them when the name changes).
	local lesson = lessonOf(player, e)
	local plan = rig.plan
	if lesson == "Aim" or lesson == "Combo" or lesson == "Ability" then
		-- The lesson's pot: the client opens the aim on (or, for Aim, a little off) it, and the
		-- pocket it goes in glows.
		player:SetAttribute("TutorialAimAngle", if plan then plan.angle else nil)
		player:SetAttribute("TutorialAimPocket", if plan then plan.pocket else 0)
		-- The ball it pots: outlined alone while the table is still open (Main).
		player:SetAttribute("TutorialAimBall", if plan and plan.ball then plan.ball else 0)
		player:SetAttribute(
			"TutorialComboBalls",
			if lesson == "Combo" and plan then ("%d,%d"):format(plan.a, plan.b) else ""
		)
	end
	if lesson == "Combo" then
		Funnel.once(player, "PathS", "ComboShown")
	elseif lesson == "BallInHand" then
		Funnel.once(player, "PathS", "BallInHand")
	elseif lesson == "Pick" then
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
			Plan.eightGlow(e.state.geometry, e.state.balls, e.ballInHand == true) or 0
		)
	end
	player:SetAttribute("TutorialLesson", lesson)
end

-- The player's seat team at table `t` (nil when not seated there).
local function teamOf(t: any, player: Player): number?
	for _, s in t.engine.seats do
		if s.userId == player.UserId then
			return s.team
		end
	end
	return nil
end

-- Game 1 is over: a win moves on to the chain (Result), a loss or a game left halfway back to
-- the arrow. True when it was over.
local function game1Over(player: Player, t: any?): boolean
	local e = if t then t.engine else nil
	local path = service.path(player)
	local funnel = if path == "S" then "PathS" else "PathR"
	if e and e.phase == "Result" and e.result then
		local team = teamOf(t, player)
		local won = team ~= nil and e.result.winner == team
		player:SetAttribute("TutorialLesson", "")
		games[player] = nil
		Funnel.onboarding(player, "Game1Ended")
		if path == "R" then
			Funnel.once(player, "PathR", "Ended")
		end
		if won then
			Funnel.onboarding(player, "FirstWin")
			Funnel.once(player, funnel, "Won")
			service.setStep(player, "Result")
		else
			service.setPath(player, nil)
			service.setStep(player, "Arrow")
		end
		return true
	end
	if e == nil or teamOf(t, player) == nil or e.phase == "Waiting" then
		-- Not at a game any more (left it, or the table reset): a win already in the save is
		-- the first win (the result was missed), anything else plays game 1 again.
		player:SetAttribute("TutorialLesson", "")
		games[player] = nil
		local data = PlayerData.read(player)
		if data and (data.Progress.Wins or 0) > 0 then
			service.setStep(player, "Result")
		else
			service.setPath(player, nil)
			service.setStep(player, "Arrow")
		end
		return true
	end
	return false
end

-- Path S: a tutorial player alone on their pad gets the tutorial bot (TutorialBot walks it
-- over and sits it down; the table starts by itself once the pad is full).
local function callOpponent(t: any, host: Player)
	calling[host] = true
	rig(t, host)
	Funnel.once(host, "PathS", "Seated")
	log(
		("%s stepped on the pad at table %d: the tutorial bot comes"):format(host.Name, t.engine.id)
	)
	if not TutorialBot.come(host) then
		warn("[8ball] Tutorial: no tutorial bot is ready for " .. host.Name)
	end
end

---------------------------------------------------------------------------------------------
-- Watching the steps
---------------------------------------------------------------------------------------------

local function atArrow(player: Player)
	reserve(player)
	local id = Tables.tableOf(player)
	local t = if id then Tables.get(id) else nil
	-- Only a 1v1 pad waiting for a game: a team pad never gets the bot, and a lost game 1's
	-- result screen (still seated) must not start the steps over until the table is free.
	if t == nil or t.engine.teamSize ~= 1 or t.engine.phase ~= "Waiting" then
		return
	end
	Funnel.onboarding(player, "OnTable")
	if usable(t, player) then
		hold(player, t) -- any empty 1v1 table becomes the tutorial table
	end
	service.setStep(player, "Pad")
end

local function atPad(player: Player)
	local id = Tables.tableOf(player)
	local t = if id then Tables.get(id) else nil
	if t == nil then
		-- Walked off the pad: back to the arrow (the table stays theirs while it is free).
		calling[player] = nil
		unrig(if reserved[player] then Tables.get(reserved[player] :: number) else nil)
		service.setStep(player, "Arrow")
		return
	end
	local e = t.engine
	if e.phase ~= "Waiting" then
		-- The game started: rigged against the tutorial bot (S), or fair (R).
		calling[player] = nil
		local rigged = Rig.isPlayer(e, player.UserId) and botSeated(t) and not realSeated(t, player)
		service.setPath(player, if rigged then "S" else "R")
		Funnel.onboarding(player, "Game1Started")
		if rigged then
			Funnel.once(player, "PathS", "BotArrived")
		else
			Funnel.once(player, "PathR", "OpponentArrived")
			Funnel.once(player, "PathR", "Started")
		end
		service.setStep(player, "Game1")
		return
	end
	if realSeated(t, player) then
		-- A real person is here before the game: a fair first game (path R).
		if e.tutorial then
			unrig(t)
		end
		calling[player] = nil
		Funnel.once(player, "PathR", "Seated")
		return
	end
	if usable(t, player) then
		hold(player, t)
		if not calling[player] and not botSeated(t) then
			callOpponent(t, player)
		end
	end
end

local function watch(player: Player)
	local step = service.step(player)
	if step == nil or Tables.arenaTable() ~= nil then
		return -- an arena has no pads: the tutorial's tables are a lobby's
	end
	if step == "Arrow" then
		atArrow(player)
	elseif step == "Pad" then
		atPad(player)
	elseif step == "Game1" then
		local id = Tables.tableOf(player)
		local t = if id then Tables.get(id) else nil
		if reserved[player] and reserved[player] ~= id then
			release(player) -- game 1 is at another table: the reserved one is free for others
		end
		if not game1Over(player, t) and t and service.path(player) == "S" then
			watchRigged(player, t)
		end
	elseif reserved[player] then
		unrigFor(player)
		release(player)
	end
end

--- Studio QA (TutorialQA "game1"): game 1's rig at the player's table (Tutorial/Rig: the
--- lesson, its plan, what is done), or nil.
function TutorialGames.rigState(player: Player): any?
	local id = Tables.tableOf(player)
	local t = if id then Tables.get(id) else nil
	local rig = t and t.engine.tutorial
	if rig == nil then
		return nil
	end
	return {
		table = id,
		phase = t.engine.phase,
		shooter = t.engine.shooter,
		lesson = rig.lesson,
		plan = rig.plan,
		done = rig.done,
		misses = rig.misses,
		shots = rig.shots,
		deadline = t.engine.deadline,
	}
end

--- Studio QA (TutorialQA "holdTables"): marks every waiting 1v1 table held by nobody (`on`;
--- a tutorial's reservation too), as if busy, so the team-table backup can be tried; false
--- lets them go. Answers how many.
function TutorialGames.qaHoldTables(on: boolean): number
	local n = 0
	for _, t in Tables.all() do
		local e = t.engine
		if e.teamSize == 1 and not borrowed[t] then
			if on and e.phase == "Waiting" and (t.reservedFor == nil or t.reservedFor > 0) then
				t.reservedFor = -1
				n += 1
			elseif not on and t.reservedFor == -1 then
				t.reservedFor = nil
				n += 1
			end
		end
	end
	return n
end

--- Whether the player is on a table's pad or seat.
function TutorialGames.seated(player: Player): boolean
	return Tables.tableOf(player) ~= nil
end

--- Starts watching the tables. `tutorial` is TutorialService (step, setStep, path, setPath,
--- guided, guard).
function TutorialGames.start(tutorial: any)
	service = tutorial
	TutorialBot.start(tutorial, TutorialGames.reservedTable)
	-- Nobody in the guided part sends or sees a Request opponent popup.
	Tables.setRequestFilter(function(host: Player, player: Player): boolean
		return not service.guided(host) and not service.guided(player)
	end)
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since < G.WatchSeconds then
			return
		end
		since = 0
		for _, player in Players:GetPlayers() do
			service.guard(player, "Games", function()
				watch(player)
			end)
		end
		local ok: boolean, err: any = pcall(giveBack :: any)
		if not ok then
			warn("[8ball] Tutorial: giving a lent table back failed: " .. tostring(err))
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		unrigFor(player)
		release(player)
		calling[player] = nil
		games[player] = nil
	end)
end

return TutorialGames
