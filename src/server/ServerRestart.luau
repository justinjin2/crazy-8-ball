--!strict
-- ServerRestart: the server refresh (designer, 2026-10-14; Config.ServerRestart). Live
-- servers grow slow the older they get, so a public lobby server past AfterHours waits for a
-- moment with no real player mid-game (LatestHours at most; ServerRestartMath.decide), sets
-- the workspace's ServerRestartAt (the banner counts down, src/client/Banner.luau), then moves
-- everyone together through a hop to one fresh lobby server (GlobalQueue.restartHop; the hop
-- is ArenaService.runHop). While they move, matches are void as at a shutdown
-- (Ranking.setVoid) and arenas stop sending anyone back here (GlobalQueue.setLobbyClosed).
-- Someone who joins mid-move follows to the same hop. Anyone whose teleport failed is tried
-- again after RetrySeconds; still here after that, the server plays on and tries again
-- GiveUpMinutes later.
-- Studio cannot teleport: ServerStorage.ServerRestartQA ("now" / "state") and the owner's
-- /refreshserver run the countdown, then the move only logs and everything is put back.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local ServerRestartMath = require(Shared.ServerRestartMath)
local GlobalQueue = require(script.Parent.GlobalQueue)
local PlayerData = require(script.Parent.PlayerData)
local Ranking = require(script.Parent.Ranking)
local TableService = require(script.Parent.TableService)

local R = Config.ServerRestart
local IS_STUDIO = RunService:IsStudio()
local ROUNDS = 2 -- the move, and one more try for anyone still here

local ServerRestart = {}

local here = false -- this server may refresh (a public lobby server; Studio for the QA)
local bornAt = os.time() -- unix seconds: a server's age is wall time, never CPU time
local phase = "idle" -- "idle" | "counting" | "moving"
local nextTryAt = 0 -- after a move that failed, no new countdown before this (os.time)
local hop: GlobalQueue.Hop? = nil

local function log(text: string)
	print("[8ball] refresh " .. text)
end

-- Whether a real player is mid-game at any table (a table of bots alone does not count).
local function gameOn(): boolean
	for _, t in TableService.all() do
		local e = t.engine
		if e.phase ~= "Waiting" and e.phase ~= "Result" then
			for _, s in e.seats do
				if Players:GetPlayerByUserId(s.userId) then
					return true
				end
			end
		end
	end
	return false
end

-- Everyone here who is not already on the way somewhere (an arena's teleport).
local function staying(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if not PlayerData.isHandedOff(p) then
			table.insert(out, p)
		end
	end
	return out
end

-- A teleport that failed: the screen goes away with a line (the save was given back already).
local function stuck(p: Player, why: string)
	if p.Parent ~= Players then
		return
	end
	if why ~= "Studio" then
		warn(("[8ball] refresh: %d could not move: %s"):format(p.UserId, why))
	end
	GlobalQueue.notify(
		{ p },
		{ kind = "Failed", reason = if why == "Studio" then why else "Refresh" }
	)
end

-- The move did not take everyone: the server plays on as before.
local function giveUp(left: number)
	log(("%d player(s) still here; playing on"):format(left))
	phase = "idle"
	hop = nil
	nextTryAt = os.time() + R.GiveUpMinutes * 60
	workspace:SetAttribute(R.AttributeName, nil)
	Ranking.setVoid(false)
	GlobalQueue.setLobbyClosed(false)
end

local function send(round: number)
	local group = staying()
	if #group > 0 then
		local made = GlobalQueue.restartHop(group, stuck, hop)
		if made then
			hop = made
		else
			warn("[8ball] refresh: no hop could be made")
		end
	end
	if IS_STUDIO then
		task.delay(Config.GlobalQueue.FoundLeadSeconds + 1, giveUp, #group)
		return
	end
	task.delay(R.RetrySeconds, function()
		local left = #staying()
		if left == 0 or phase ~= "moving" then
			return
		end
		if round < ROUNDS then
			send(round + 1)
		else
			giveUp(left)
		end
	end)
end

local function move()
	phase = "moving"
	log(("moving %d player(s) to a fresh server"):format(#Players:GetPlayers()))
	Ranking.setVoid(true)
	GlobalQueue.setLobbyClosed(true)
	send(1)
end

local function begin(seconds: number)
	phase = "counting"
	workspace:SetAttribute(R.AttributeName, workspace:GetServerTimeNow() + seconds)
	log(
		("countdown %d s (server %.1f h old, a game on: %s)"):format(
			seconds,
			(os.time() - bornAt) / 3600,
			tostring(gameOn())
		)
	)
	task.delay(seconds, function()
		if phase == "counting" then
			move()
		end
	end)
end

--- The countdown now (the owner's /refreshserver, the QA hook): `seconds` or the usual.
--- False when this server cannot refresh or one is already under way.
function ServerRestart.now(seconds: number?): boolean
	if not here or phase ~= "idle" then
		return false
	end
	begin(seconds or R.CountdownSeconds)
	return true
end

local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("ServerRestartQA")
	if old then
		old:Destroy()
	end
	local qa = Instance.new("BindableFunction")
	qa.Name = "ServerRestartQA"
	qa.OnInvoke = function(op: string): any
		if op == "now" then
			return ServerRestart.now(R.StudioCountdownSeconds)
		elseif op == "state" then
			return {
				phase = phase,
				gameOn = gameOn(),
				hours = (os.time() - bornAt) / 3600,
				at = workspace:GetAttribute(R.AttributeName),
			}
		end
		return nil
	end
	qa.Parent = ServerStorage
end

--- Start the watch (Bootstrap calls this once). `lobby`: this is a lobby server, not an
--- arena; a private server never refreshes, and Studio only through the QA hook.
function ServerRestart.start(lobby: boolean)
	here = lobby and game.PrivateServerId == ""
	if not here then
		return
	end
	startQA()
	-- Someone joining while everyone moves follows them to the same hop.
	Players.PlayerAdded:Connect(function(p: Player)
		if phase ~= "moving" then
			return
		end
		PlayerData.waitLoaded(p, R.HopWaitSeconds)
		if p.Parent == Players and phase == "moving" then
			GlobalQueue.restartHop({ p }, stuck, hop)
		end
	end)
	if IS_STUDIO then
		return
	end
	task.spawn(function()
		while true do
			task.wait(R.CheckSeconds)
			if
				phase == "idle"
				and os.time() >= nextTryAt
				and ServerRestartMath.decide(os.time() - bornAt, gameOn(), R) == "go"
			then
				begin(R.CountdownSeconds)
			end
		end
	end)
end

return ServerRestart
