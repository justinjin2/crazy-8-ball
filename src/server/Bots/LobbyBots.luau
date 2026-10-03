--!strict
-- Lobby bots (the Bots lane; the designer, 2026-10-02): disguised bots that make a lobby
-- server look like Config.Bots.Lobby.People people. They "join" (appear at the entrance) and
-- "leave" (vanish) as real players come and go, stroll the aisles, sit on the map's seats,
-- wait on 1v1 pads and play each other there, and answer a real Request opponent that nobody
-- real took. Public lobby servers only (never a private server or an arena); in Studio only
-- after the designer's /lobbybots. The tutorial's fake lobby is `start({ count, tiers })`.
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Engine = require(Shared.Rules.MatchEngine)
local Ranks = require(Shared.Progression.Ranks)
local Rng = require(Shared.Bots.Rng)
local Tables = require(script.Parent.Parent.TableService)
-- BotService, handed over by its start (it requires this module).
local BotService: any = nil
local Body = require(script.Parent.Body)
local Identity = require(script.Parent.Identity)

local L = Config.Bots.Lobby
local HUB = Config.Hub

local LobbyBots = {}

type Entry = {
	bot: any,
	activity: string, -- "Idle" | "Stroll" | "Sit" | "Wait" | "Play" | "Walking"
	untilAt: number, -- os.clock() when the current activity ends
	seat: Seat?,
	t: any?,
	job: number, -- bumped to cancel a walk under way
}

local entries: { Entry } = {}
local options: any = nil -- nil: off; else { count?, tiers? }
local rng = Rng.new(Identity.seed())
local nextJoinAt = 0
local joining = false
local started = false
-- Filling up from none (a new server, or just turned on): they are "already there", spread
-- over the lobby, one right after another, so the first player finds a full server.
local warm = true

local function range(pair: { number }): number
	return Rng.range(rng, pair[1], pair[2])
end

type Weighted = { { name: string, weight: number } }

local function pick(weighted: Weighted): string
	local total = 0
	for _, row in weighted do
		total += row.weight
	end
	local r = Rng.uniform(rng) * total
	for _, row in weighted do
		r -= row.weight
		if r <= 0 then
			return row.name
		end
	end
	return weighted[#weighted].name
end

-- Whether this server has lobby bots at all: a public lobby, or a forced count (the
-- tutorial), or Studio with /lobbybots on.
local function wanted(): boolean
	if options == nil then
		return false
	end
	if options.count then
		return true
	end
	return game.PrivateServerId == ""
		and workspace:GetAttribute(Config.Arena.ModeAttribute) ~= "Arena"
end

-- How many lobby bots the server should hold now.
local function target(): number
	if options and options.count then
		return options.count
	end
	return math.max(0, L.People - #Players:GetPlayers())
end

---------------------------------------------------------------------------------------------
-- Where they go
---------------------------------------------------------------------------------------------

-- Spots in the aisles between the tables (from Config.Hub.Tables), and in front of the rows.
local strollSpots: { Vector3 } = {}
local function buildSpots()
	local xs, zs = {}, {}
	for _, row in HUB.Tables do
		if not table.find(xs, row.X) then
			table.insert(xs, row.X)
		end
		if not table.find(zs, row.Z) then
			table.insert(zs, row.Z)
		end
	end
	table.sort(xs)
	table.sort(zs)
	local ax, az = {}, {}
	for i = 1, #xs - 1 do
		table.insert(ax, (xs[i] + xs[i + 1]) / 2)
	end
	for i = 1, #zs - 1 do
		table.insert(az, (zs[i] + zs[i + 1]) / 2)
	end
	local front = zs[#zs] + (zs[#zs] - (az[#az] or zs[#zs])) + 6
	for _, x in ax do
		for _, z in az do
			table.insert(strollSpots, Vector3.new(x, 0, z))
		end
	end
	for _, x in xs do
		table.insert(strollSpots, Vector3.new(x, 0, front))
	end
end

local function seats(): { Seat }
	local out = {}
	local map = workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Seats")
	if folder then
		for _, s in folder:GetChildren() do
			if s:IsA("Seat") and s.Occupant == nil then
				table.insert(out, s)
			end
		end
	end
	return out
end

-- 1v1 tables free for anyone: waiting, nobody on the pad, no search, no real player there.
local function freeTables(): { any }
	local out = {}
	for _, t in Tables.all() do
		local e = t.engine
		if
			e.teamSize == 1
			and e.phase == "Waiting"
			and Engine.count(e) == 0
			and not e.search
			and not t.search
			and not Tables.standingOnPad(t)
		then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.engine.id < b.engine.id
	end)
	return out
end

---------------------------------------------------------------------------------------------
-- Moving a body
---------------------------------------------------------------------------------------------

local function humanoidOf(entry: Entry): Humanoid?
	local model = entry.bot.model
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

-- Walks the body to `to` along a path round the tables (a straight walk if none is found).
-- Yields. True when it got there; false when cut short (another job, a timeout, gone).
local function walkTo(entry: Entry, to: Vector3): boolean
	entry.job += 1
	local job = entry.job
	local hum = humanoidOf(entry)
	local root = Body.root(entry.bot.model)
	if not hum or not root then
		return false
	end
	if hum.Sit then
		hum.Sit = false
		task.wait(0.3)
	end
	local points = { to }
	local path = PathfindingService:CreatePath({
		AgentRadius = 2,
		AgentHeight = 5,
		AgentCanJump = false,
	})
	local ok = pcall(function()
		path:ComputeAsync(root.Position, to)
	end)
	if ok and path.Status == Enum.PathStatus.Success then
		points = {}
		for _, w in path:GetWaypoints() do
			table.insert(points, w.Position)
		end
	end
	local deadline = os.clock() + L.WalkTimeoutSeconds
	for _, point in points do
		if entry.job ~= job or entry.bot.gone or os.clock() > deadline then
			return false
		end
		local arrived = false
		local c = hum.MoveToFinished:Connect(function(reached: boolean)
			arrived = reached or true
		end)
		hum:MoveTo(point)
		local stepEnd = math.min(deadline, os.clock() + 4)
		while not arrived and os.clock() < stepEnd and entry.job == job do
			task.wait(0.1)
		end
		c:Disconnect()
	end
	return entry.job == job and not entry.bot.gone
end

---------------------------------------------------------------------------------------------
-- Activities
---------------------------------------------------------------------------------------------

local function idle(entry: Entry, seconds: number?)
	entry.activity = "Idle"
	entry.untilAt = os.clock() + (seconds or range(L.StrollPauseSeconds))
	entry.seat = nil
	entry.t = nil
end

local function stroll(entry: Entry)
	entry.activity = "Stroll"
	task.spawn(function()
		local steps = math.floor(range(L.StrollSteps) + 0.5)
		for _ = 1, steps do
			local spot = strollSpots[Rng.int(rng, 1, #strollSpots)]
			local jitter = Vector3.new(Rng.range(rng, -3, 3), 0, Rng.range(rng, -2, 2))
			if not walkTo(entry, spot + jitter) then
				break
			end
			task.wait(Rng.range(rng, 0.5, 2))
		end
		if entry.activity == "Stroll" then
			idle(entry)
		end
	end)
end

local function sit(entry: Entry): boolean
	local free = seats()
	if #free == 0 then
		return false
	end
	local seat = free[Rng.int(rng, 1, #free)]
	entry.activity = "Walking"
	entry.seat = seat
	task.spawn(function()
		local front = seat.CFrame * CFrame.new(0, 0, -3)
		local reached = walkTo(entry, front.Position)
		local hum = humanoidOf(entry)
		if reached and hum and seat.Occupant == nil and entry.activity == "Walking" then
			seat:Sit(hum)
			entry.activity = "Sit"
			entry.untilAt = os.clock() + range(L.SitSeconds)
		elseif entry.activity == "Walking" then
			idle(entry)
		end
	end)
	return true
end

-- Walks to table `t`'s pad and sits down there (alone: waiting; with `partner`: their game).
local function goPlay(entry: Entry, t: any, side: number)
	entry.activity = "Walking"
	entry.t = t
	local spot = Tables.padSpot(t, if side == 1 then -2 else 2)
	if walkTo(entry, spot.Position) and entry.t == t then
		local e = t.engine
		if e.phase == "Waiting" and Engine.count(e) < Engine.capacity(e) then
			if BotService.seat(entry.bot, t, { at = spot }) then
				entry.activity = if Engine.count(e) >= Engine.capacity(e) then "Play" else "Wait"
				entry.untilAt = os.clock() + range(L.WaitSeconds)
				return
			end
		end
	end
	if entry.activity == "Walking" then
		idle(entry)
	end
end

local function counts(): { [string]: number }
	local out = { Play = 0, Wait = 0 }
	for _, entry in entries do
		if entry.t and not entry.bot.t then
			out.Wait += 1 -- on its way to a pad
		elseif entry.bot.t then
			local e = entry.bot.t.engine
			if Engine.count(e) >= Engine.capacity(e) or e.phase ~= "Waiting" then
				out.Play += 1
			else
				out.Wait += 1
			end
		end
	end
	return out
end

local function idleEntries(): { Entry }
	local out = {}
	for _, entry in entries do
		if entry.activity == "Idle" and os.clock() >= entry.untilAt and not entry.bot.t then
			table.insert(out, entry)
		end
	end
	return out
end

-- Gives an idle bot something to do.
local function nextActivity(entry: Entry)
	local choice = pick(L.Activities)
	local free = freeTables()
	if
		choice == "Play"
		and #free > L.MinFreeTables
		and counts().Play + 2 <= math.floor(#entries * L.PlayShare)
	then
		-- Its partner: any other bot about the lobby (idle, strolling or sitting).
		for _, other in entries do
			local free_ = other.activity == "Idle"
				or other.activity == "Stroll"
				or other.activity == "Sit"
			if other ~= entry and free_ and not other.bot.t and not other.t then
				local t = free[Rng.int(rng, 1, #free)]
				task.spawn(goPlay, entry, t, 1)
				task.spawn(goPlay, other, t, 2)
				return
			end
		end
		choice = "Stroll"
	end
	if choice == "Wait" and #free > L.MinFreeTables and counts().Wait < L.MaxWaiting then
		task.spawn(goPlay, entry, free[Rng.int(rng, 1, #free)], 1)
		return
	end
	if choice == "Sit" and sit(entry) then
		return
	end
	stroll(entry)
end

---------------------------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------------------------

local function tiers(): Weighted
	if options and options.tiers then
		local out = {}
		for _, tier in options.tiers do
			table.insert(out, { name = tier, weight = 1 })
		end
		return out
	end
	return L.Tiers
end

local function join(at: CFrame?)
	joining = true
	local tier = pick(tiers())
	local bot = BotService.spawn({ kind = "Disguised", tier = tier, playerTier = tier })
	joining = false
	if not bot or not wanted() then
		if bot then
			BotService.remove(bot)
		end
		return
	end
	bot.lobby = true
	local s = Config.Multiplayer.Spawn
	local spot = strollSpots[Rng.int(rng, 1, #strollSpots)]
	local spawnAt = at
		or if warm
			then CFrame.new(spot + Vector3.new(Rng.range(rng, -3, 3), 3, Rng.range(rng, -2, 2)))
				* CFrame.Angles(0, Rng.range(rng, 0, 2 * math.pi), 0)
			else CFrame.new(s.X + Rng.range(rng, -4, 4), s.Y + 3, s.Z - Rng.range(rng, 0, 4))
				* CFrame.Angles(0, math.rad(180), 0)
	if not BotService.stand(bot, spawnAt) then
		BotService.remove(bot)
		return
	end
	local entry: Entry = { bot = bot, activity = "Idle", untilAt = 0, job = 0 }
	table.insert(entries, entry)
end

local function removeEntry(entry: Entry)
	local i = table.find(entries, entry)
	if i then
		table.remove(entries, i)
	end
	entry.job += 1
end

-- One bot leaves the server: idle ones first, then bot-vs-bot players, and one playing a
-- real player only once the server holds People real players.
local function leaveOne()
	local function playsReal(entry: Entry): boolean
		local t = entry.bot.t
		if not t then
			return false
		end
		for _, s in t.engine.seats do
			if s.userId > 0 then
				return true
			end
		end
		return false
	end
	local best, bestRank = nil, math.huge
	for _, entry in entries do
		local rank = if entry.bot.t == nil
			then 1
			elseif entry.bot.t.engine.phase == "Waiting" and not playsReal(entry) then 2
			elseif not playsReal(entry) then 3
			else 4
		if rank < bestRank then
			best, bestRank = entry, rank
		end
	end
	if not best or (bestRank == 4 and #Players:GetPlayers() < L.People) then
		return
	end
	removeEntry(best)
	BotService.remove(best.bot, "Vanish")
end

---------------------------------------------------------------------------------------------
-- The director
---------------------------------------------------------------------------------------------

local function tick()
	-- Gone bots (removed elsewhere) leave the list.
	for i = #entries, 1, -1 do
		if entries[i].bot.gone then
			table.remove(entries, i)
		end
	end
	if not wanted() then
		for _, entry in table.clone(entries) do
			removeEntry(entry)
			BotService.remove(entry.bot, "Vanish")
		end
		return
	end
	local want = target()
	if #entries >= want then
		warm = false
	end
	if #entries < want and not joining and os.clock() >= nextJoinAt then
		nextJoinAt = os.clock() + if warm then 0 else range(L.JoinGapSeconds)
		task.spawn(join)
	elseif #entries > want then
		leaveOne()
	end
	-- Real players stepping onto a pad where bots play: the bots get up and walk off.
	for _, t in Tables.all() do
		local e = t.engine
		local allBots = Engine.count(e) > 0
		for _, s in e.seats do
			if s.userId > 0 then
				allBots = false
			end
		end
		if allBots and Tables.standingOnPad(t) then
			for _, entry in entries do
				if entry.bot.t == t then
					BotService.unseat(entry.bot)
					idle(entry, 0)
				end
			end
		end
	end
	-- A waiting bot that waited long enough gets up.
	for _, entry in entries do
		local t = entry.bot.t
		if
			t
			and entry.activity == "Wait"
			and os.clock() >= entry.untilAt
			and t.engine.phase == "Waiting"
			and Engine.count(t.engine) == 1
		then
			BotService.unseat(entry.bot)
			idle(entry, 0)
		elseif t and entry.activity == "Wait" and Engine.count(t.engine) > 1 then
			entry.activity = "Play"
		end
		if entry.activity == "Sit" and os.clock() >= entry.untilAt then
			idle(entry, 0)
		end
	end
	for _, entry in idleEntries() do
		if entry.activity == "Idle" then
			nextActivity(entry)
		end
	end
end

-- A lobby bot whose table let it go: back to the lobby, standing by the pad.
local function freed(bot: any)
	for _, entry in entries do
		if entry.bot == bot then
			idle(entry)
			return
		end
	end
	BotService.remove(bot, "Vanish")
end

-- A real Request opponent nobody real answered in AnswerAfter seconds: the idle lobby bot
-- nearest the host's rank appears on the pad.
local function answer(t: any, host: Player)
	if not wanted() or t.engine.teamSize ~= 1 then
		return
	end
	local e = t.engine
	local epoch, asked = e.epoch, e.requestedAt
	task.wait(L.AnswerAfter)
	if
		e.epoch ~= epoch
		or e.phase ~= "Waiting"
		or e.requestedAt ~= asked
		or Engine.count(e) ~= 1
		or not Engine.seat(e, host.UserId)
	then
		return
	end
	local hostTier = host:GetAttribute("RankTier")
	local want = Ranks.tierIndex(if type(hostTier) == "string" then hostTier else "Bronze") or 1
	local best, bestGap = nil, math.huge
	for _, entry in entries do
		if not entry.bot.t and entry.activity ~= "Walking" then
			local gap = math.abs((Ranks.tierIndex(entry.bot.tier) or 1) - want)
			if gap < bestGap then
				best, bestGap = entry, gap
			end
		end
	end
	if not best then
		return
	end
	local entry = best :: Entry
	entry.job += 1
	local hum = humanoidOf(entry)
	if hum and hum.Sit then
		hum.Sit = false
	end
	entry.activity = "Play"
	entry.t = t
	BotService.joinTable(entry.bot, t, { delay = 0, breakFor = host.UserId }, function(ok)
		if not ok then
			idle(entry)
		end
	end)
end

--- Turns the lobby bots on (`opts`: { count? (a fixed number: the tutorial's fake lobby),
--- tiers? (their badges, e.g. { "Bronze", "Silver", "Gold" }) }) or off (nil). Without a count
--- they keep the server at Config.Bots.Lobby.People people, in public lobby servers only.
function LobbyBots.set(opts: any?)
	options = opts
	nextJoinAt = 0
	warm = true
end

--- Whether lobby bots are on.
function LobbyBots.isOn(): boolean
	return wanted()
end

--- Starts the director (BotService.start hands itself over as `bots`). Live public lobbies start with them on; Studio
--- waits for /lobbybots.
function LobbyBots.start(bots: any)
	if started then
		return
	end
	started = true
	BotService = bots
	buildSpots()
	BotService.onFreed = freed
	Tables.onRequest(answer)
	if not RunService:IsStudio() then
		options = {}
	end
	task.spawn(function()
		while true do
			task.wait(L.TickSeconds)
			local ok, err = pcall(function(): any
				tick()
				return nil
			end)
			if not ok then
				warn("[8ball] lobby bots: " .. tostring(err))
			end
		end
	end)
end

return LobbyBots
