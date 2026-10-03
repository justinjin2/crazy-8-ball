--!strict
-- ArenaService: a server started for one global-queue match (designer, 2026-09-28). It is a
-- reserved server of this same place: Bootstrap asks `detect` first, and in an arena it
-- keeps the rooftop, its light and its day cycle (started at day) and stands up one table,
-- in the middle, in the blue look, instead of sixteen (designer, 2026-09-28).
--
-- - The match's player list (who, on which side, and each one's lobby server) was written
--   by the global queue's leader before anyone was told; the arena reads it by its own
--   reserved server id. Anyone not on it is sent to the lobby.
-- - Arriving players are stood on the table's pad side, facing it (they spawn at the
--   rooftop's entrance), and seated on their side as their saves open; the game starts the moment
--   everyone is in, or after Arena.ArrivalSeconds if both sides have someone. A side that
--   never came: whoever did searches again at once, as if they had waited 10 s.
-- - After each game (the result screen): Rematch is the table's own vote (MatchEngine); here
--   are the other two choices, Play another (a new opponent from the global queue, straight
--   from the arena; a team goes together once every teammate pressed it) and Lobby (back to
--   the lobby server they came from). A teammate going to the lobby takes the team with
--   them. Anyone who has chosen nothing when the rematch time is up goes to the lobby.
-- - Ults: On / Off (designer, 2026-09-28): the list names the pool the match was made in, and
--   the table plays with it (`settings.abilities`, false for a No-ults match, which the
--   rematch keeps); Play another and a no-show's new search stay in that pool.
-- - Studio: the ServerStorage attribute StudioArena (a team size) set before Play makes the
--   server an arena with no list: real players fill the sides in turn and pretend players
--   (negative ids) fill the rest a moment later. ServerStorage.ArenaQA drives them. Setting
--   StudioArenaUlts to false as well makes it a No-ults match.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Strings = require(Shared.Strings)
local Engine = require(Shared.Rules.MatchEngine)
local LightCycle = require(Shared.LightCycle)
local Placement = require(Shared.Placement)
local GlobalQueue = require(script.Parent.GlobalQueue)
local PlayerData = require(script.Parent.PlayerData)
local TableService = require(script.Parent.TableService)
local BotService = require(script.Parent.Bots.BotService)

local A = Config.Arena
local IS_STUDIO = RunService:IsStudio()
local STUDIO_ATTRIBUTE = "StudioArena"
local STUDIO_ULTS_ATTRIBUTE = "StudioArenaUlts" -- false: the Studio arena plays with no ults
-- The Bots lane: a tier name here makes the Studio arena's other side a disguised bot of it
-- (the global queue's fallback), instead of pretend players.
local STUDIO_BOT_ATTRIBUTE = "StudioArenaBot"
local ArenaService = {}

-- The place's mode, for every client (Main reads it before building anything).
ArenaService.ModeAttribute = A.ModeAttribute
ArenaService.TeamSizeAttribute = A.TeamSizeAttribute

local function now(): number
	return workspace:GetServerTimeNow()
end
local function clock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end
local function log(text: string)
	print("[8ball] GQ arena " .. text)
end

--- Whether this server is an arena, and its match id: a reserved server (no owner), or in
--- Studio the StudioArena attribute.
function ArenaService.detect(): (boolean, string?)
	if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
		return true, game.PrivateServerId
	end
	if IS_STUDIO and type(ServerStorage:GetAttribute(STUDIO_ATTRIBUTE)) == "number" then
		return true, "studio-arena"
	end
	return false, nil
end

--- The arena's first step, before anything else is built: tell the clients, and start the
--- day/sunset cycle at the start of the day, so every match opens in daylight.
function ArenaService.prepare()
	workspace:SetAttribute(ArenaService.ModeAttribute, "Arena")
	local C = Config.Lighting.Cycle
	local t = workspace:GetServerTimeNow() * C.Speed
	workspace:SetAttribute(C.OffsetAttribute, LightCycle.offsetToDayStart(t, C))
end

--- The match's player list (yields up to Arena.RecordWaitSeconds), or nil.
function ArenaService.loadRecord(matchId: string): any?
	if matchId == "studio-arena" then
		local size =
			math.clamp(math.floor(ServerStorage:GetAttribute(STUDIO_ATTRIBUTE) :: number), 1, 3)
		return {
			v = 1,
			id = matchId,
			mode = size,
			teams = { {}, {} },
			homes = {},
			ults = ServerStorage:GetAttribute(STUDIO_ULTS_ATTRIBUTE) ~= false,
			studio = true,
			bots = if type(ServerStorage:GetAttribute(STUDIO_BOT_ATTRIBUTE)) == "string"
				then {
					{
						team = 2,
						kind = "Disguised",
						tier = ServerStorage:GetAttribute(STUDIO_BOT_ATTRIBUTE),
						rematch = "Never",
					},
				}
				else nil,
		}
	end
	local started = os.clock()
	local record = GlobalQueue.readRecord(matchId, A.RecordWaitSeconds)
	if record then
		log(
			("list read in %.0f ms: %dv%d"):format(
				(os.clock() - started) * 1000,
				record.mode,
				record.mode
			)
		)
	else
		warn("[8ball] GQ arena: no player list for " .. matchId)
	end
	return record
end

---------------------------------------------------------------------------------------------
-- The running arena
---------------------------------------------------------------------------------------------
local record: any = nil
local teamOf: { [number]: number } = {} -- userId -> side
local homeOf: { [number]: string } = {} -- userId -> lobby server
local seated: { [number]: boolean } = {}
local choice: { [number]: string } = {} -- userId -> "Another" | "Lobby"
local searchOf: { [number]: any } = {} -- userId -> their GlobalQueue search (shared by a team)
local searchAt: { [number]: number } = {} -- userId -> when it started (server time)
local searchMax: { [number]: number } = {} -- userId -> how long that search may run
local decideBy: { [number]: number } = {} -- userId -> when the choosing time ends
local arrivalDeadline: number? = nil
local begun = false -- the first game has started
-- The arrival time ran out with a side missing: whoever came searches again, and nobody
-- else is seated or started here any more.
local closed = false
local notice: string? = nil -- a line for everyone's card (Strings.Arena key)
local seenResult = -1 -- the epoch whose result opened the choosing
local listAt = 0

-- The match's pool: ults on unless its list says exactly false (Ticket.pool).
local function ultsOn(): boolean
	return record == nil or record.ults ~= false
end

-- The table plays in the match's pool (settings.abilities). Set when the arena starts and
-- again just before the first game (a seat emptying while it waits resets the settings);
-- the rematch keeps them (MatchEngine).
local function applyUlts()
	local t = TableService.arenaTable()
	if not t or t.engine.phase ~= "Waiting" then
		return
	end
	local e = t.engine
	if e.settings.abilities ~= ultsOn() then
		e.settings.abilities = ultsOn()
		e.revision += 1
		TableService.broadcast(t)
	end
end

local function allPlayers(): { Player }
	return Players:GetPlayers()
end

local function sendState()
	local teams = { {}, {} }
	for id, team in teamOf do
		table.insert(teams[team], id)
	end
	table.sort(teams[1])
	table.sort(teams[2])
	local arrived = {}
	for id in seated do
		table.insert(arrived, id)
	end
	table.sort(arrived)
	local choices, searching = {}, {}
	for id, kind in choice do
		choices[tostring(id)] = kind
	end
	for id, at in searchAt do
		searching[tostring(id)] = at
	end
	local deadlines = {}
	for id, at in decideBy do
		deadlines[tostring(id)] = at
	end
	Net.get("ArenaState"):FireAllClients({
		mode = record and record.mode or 1,
		teams = teams,
		arrived = arrived,
		deadline = if begun then nil else arrivalDeadline,
		begun = begun,
		choices = choices,
		searching = searching,
		decideBy = deadlines,
		notice = notice,
	})
end

local function home(players: { Player })
	local homes = {}
	for _, p in players do
		homes[p.UserId] = homeOf[p.UserId] or ""
		choice[p.UserId] = "Lobby"
		decideBy[p.UserId] = nil
	end
	sendState()
	GlobalQueue.notify(players, { kind = "Home" })
	GlobalQueue.sendHome(players, homes, function(p: Player)
		-- Still here: choose again (a later time-out tries the lobby once more).
		choice[p.UserId] = nil
		decideBy[p.UserId] = now() + Config.Multiplayer.RematchSeconds
		sendState()
	end)
end

-- Someone this arena cannot seat (not on its list, or it has no list): to the lobby, tried
-- again a few times, and as a last resort kicked with a line saying to rejoin, so nobody is
-- ever left in an arena with nothing to do.
function ArenaService.evict(p: Player, tries: number?)
	local n = tries or 1
	GlobalQueue.sendHome({ p }, {}, function(q: Player, why: string)
		if why == "Studio" or q.Parent ~= Players then
			return
		end
		if n < Config.GlobalQueue.TeleportRetries then
			task.delay(A.EvictRetrySeconds, ArenaService.evict, q, n + 1)
		else
			q:Kick(Strings.Arena.Rejoin)
		end
	end)
end

-- Everyone on `team` still in the server.
local function teammates(team: number): { Player }
	local out = {}
	for _, p in allPlayers() do
		if teamOf[p.UserId] == team then
			table.insert(out, p)
		end
	end
	return out
end

local function opponentsOf(team: number): { number }
	local out = {}
	for id, t in teamOf do
		if t ~= team then
			table.insert(out, id)
		end
	end
	return out
end

local function clearSearch(players: { Player })
	for _, p in players do
		searchOf[p.UserId] = nil
		searchAt[p.UserId] = nil
		searchMax[p.UserId] = nil
	end
end

-- The teammates of `p` who wait on the team: pressed Play another, or share its search.
local function waitingMates(p: Player, team: number, search: any?): { Player }
	local out = {}
	for _, mate in teammates(team) do
		if
			mate ~= p
			and (
				(choice[mate.UserId] == "Another" and not searchOf[mate.UserId])
				or (search ~= nil and searchOf[mate.UserId] == search)
			)
		then
			table.insert(out, mate)
		end
	end
	return out
end

-- Search again for `players` (one whole side), straight from here. `head` credits seconds of
-- searching (a no-show: anyone at once).
local function searchFor(players: { Player }, head: number)
	local team = teamOf[players[1].UserId] or 1
	local search, why = GlobalQueue.enqueue({
		players = players,
		mode = record.mode,
		home = homeOf[players[1].UserId] or "",
		avoid = if head > 0 then nil else opponentsOf(team),
		head = head,
		ults = ultsOn(), -- the arena's pool: Play another keeps the setting
		onFound = function(found: any, match: any)
			local here = {}
			for _, p in found.players do
				if p.Parent == Players then
					table.insert(here, p)
				end
			end
			GlobalQueue.notify(here, { kind = "Found", mode = record.mode })
			task.wait(Config.GlobalQueue.FoundLeadSeconds)
			GlobalQueue.teleport(here, match, function(p: Player, reason: string)
				GlobalQueue.notify({ p }, { kind = "Failed", reason = reason })
				searchOf[p.UserId], searchAt[p.UserId], choice[p.UserId] = nil, nil, nil
				decideBy[p.UserId] = now() + Config.Multiplayer.RematchSeconds
				sendState()
			end)
		end,
	})
	if not search then
		GlobalQueue.notify(players, { kind = "Failed", reason = "Store" })
		for _, p in players do
			choice[p.UserId] = nil
			decideBy[p.UserId] = now() + Config.Multiplayer.RematchSeconds
		end
		warn("[8ball] GQ arena could not search again: " .. tostring(why))
		sendState()
		return
	end
	for _, p in players do
		searchOf[p.UserId] = search
		searchAt[p.UserId] = now()
		searchMax[p.UserId] = if head > 0 then A.NoShowSearchSeconds else A.SearchMaxSeconds
		decideBy[p.UserId] = nil
	end
	GlobalQueue.notify(players, { kind = "Searching", mode = record.mode })
	sendState()
end

local function begin()
	if begun or closed then
		return
	end
	for _ in searchOf do
		return -- someone here is already searching for another match
	end
	applyUlts()
	if TableService.startArena() then
		begun = true
		notice = nil
		log(("match started %.1f s after the list"):format(os.clock() - listAt))
		sendState()
	end
end

local function everyoneIn(): boolean
	for id in teamOf do
		if not seated[id] then
			return false
		end
	end
	return next(teamOf) ~= nil
end

-- The Bots lane: a list may name bot opponents (`bots`, the global queue's fallback after its
-- wait). Once the real players are in they walk in and sit down, just before the game starts.
-- Yields. True when there are none or all sat.
local botsSeated = false
local function seatBots(): boolean
	if type(record.bots) ~= "table" or botsSeated then
		return true
	end
	botsSeated = true
	local t = TableService.arenaTable()
	return t ~= nil and BotService.seatArenaBots(t, record)
end

-- Studio: pretend players fill every side's empty seats.
local function fillSynthetic()
	local t = TableService.arenaTable()
	if not t or not record then
		return
	end
	local next_ = -1
	for team = 1, 2 do
		while Engine.count(t.engine, team) < record.mode do
			while teamOf[next_] do
				next_ -= 1
			end
			if not TableService.seatSynthetic(next_, "Opponent" .. -next_, team) then
				break
			end
			teamOf[next_] = team
			seated[next_] = true
		end
	end
end

-- Stand a player on the table's pad side, facing the table: team 1 left of the pad's centre,
-- team 2 right, each a little apart (they spawn at the rooftop's entrance, far away).
local function standAtTable(p: Player, team: number)
	local character = p.Character or p.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local t = TableService.arenaTable()
	if not root or not t or p.Parent ~= Players then
		return
	end
	local order = 0
	for id, side in teamOf do
		if side == team and id < p.UserId then
			order += 1
		end
	end
	local cx, cy = Placement.queuePad(record.mode)
	local along = (if team == 1 then -1 else 1) * (order + 0.5) * A.ArrivalSpacingStuds
	local x, y, z = Placement.fromTableStuds(
		t.placement,
		cx + along,
		cy,
		Config.Multiplayer.QueueVisual.RespawnHeight
	)
	local spot = Vector3.new(x, y, z)
	local centre = Vector3.new(t.placement.x, y, t.placement.z)
	character:PivotTo(CFrame.lookAt(spot, centre))
end

local function arrive(p: Player)
	local team: number? = teamOf[p.UserId]
	if not team and record.studio then
		-- Studio: fill the sides in turn.
		local counts = { 0, 0 }
		for _, t in teamOf do
			counts[t] += 1
		end
		team = if counts[1] <= counts[2] and counts[1] < record.mode
			then 1
			elseif counts[2] < record.mode then 2
			else nil
		if team then
			teamOf[p.UserId] = team
		end
	end
	if not team then
		log(("%d is not on this match's list; sending them to the lobby"):format(p.UserId))
		GlobalQueue.notify({ p }, { kind = "Failed", reason = "NotYours" })
		ArenaService.evict(p)
		return
	end
	task.spawn(standAtTable, p, team)
	local joinData: any = p:GetJoinData()
	local data: any = joinData and joinData.TeleportData
	local sentAt = type(data) == "table" and type(data.gq) == "table" and data.gq.sentAt
	if type(sentAt) == "number" then
		log(("%d arrived %.2f s after their teleport began"):format(p.UserId, clock() - sentAt))
	end
	local arrivedAt = os.clock()
	if not PlayerData.waitLoaded(p, Config.Save.LoadTimeoutSeconds) then
		return
	end
	log(("%d save open %.2f s after arriving"):format(p.UserId, os.clock() - arrivedAt))
	if begun or closed then
		-- Too late: the game began, or the other side already went looking for a new one.
		GlobalQueue.notify({ p }, { kind = "Failed", reason = "Started" })
		home({ p })
		return
	end
	if TableService.seatArena(p, team) then
		seated[p.UserId] = true
		sendState()
		if record.studio then
			task.delay(1.5, function()
				if not begun then
					seatBots()
					fillSynthetic()
					sendState()
					if everyoneIn() then
						begin()
					end
				end
			end)
		elseif everyoneIn() then
			seatBots()
			begin()
		end
	end
end

-- The arrival time ran out.
local function arrivalsDone()
	if begun then
		return
	end
	local t = TableService.arenaTable()
	if not t then
		return
	end
	if Engine.count(t.engine, 1) > 0 and Engine.count(t.engine, 2) > 0 then
		log("starting without everyone: arrival time ran out")
		begin()
		return
	end
	-- One side never came: whoever did searches again, now, for anyone. Anyone arriving
	-- after this goes to the lobby instead of starting a game here.
	closed = true
	notice = "NoOpponent"
	for team = 1, 2 do
		local side = teammates(team)
		if #side > 0 then
			if #side == record.mode then
				log(("side %d had no opponent; searching again"):format(team))
				searchFor(side, Config.GlobalQueue.Window[#Config.GlobalQueue.Window].After)
			else
				home(side)
			end
		end
	end
	sendState()
end

-- The post-game choices this server handles (the rematch vote is the table's own).
local function onAction(p: Player, kind: string)
	local team = teamOf[p.UserId]
	if not team or not TableService.allow(p, "action") then
		return
	end
	local t = TableService.arenaTable()
	if not t then
		return
	end
	local e = t.engine
	-- Only between games (the result is showing, or the table has freed after it), or before
	-- the first game, where Lobby is the way out (Leave) while waiting.
	local between = begun and (e.phase == "Result" or e.phase == "Waiting")
	local exits = kind == "Lobby" or kind == "CancelAnother"
	if not between and not (not begun and exits) then
		return
	end
	if kind == "Lobby" then
		local search = searchOf[p.UserId]
		if search and GlobalQueue.cancel(search) == "matched" then
			return -- the new match stands: its teleport is on its way
		end
		TableService.arenaDecline(p)
		-- A team goes back together: teammates waiting on the team (or on its search) go too.
		local going = { p }
		if record.mode > 1 then
			for _, mate in waitingMates(p, team, search) do
				table.insert(going, mate)
			end
		end
		clearSearch(going)
		home(going)
	elseif kind == "Another" then
		if choice[p.UserId] == "Another" then
			return
		end
		choice[p.UserId] = "Another"
		decideBy[p.UserId] = nil
		TableService.arenaDecline(p)
		local side = teammates(team)
		local ready = #side == record.mode
		for _, mate in side do
			if choice[mate.UserId] ~= "Another" then
				ready = false
			end
		end
		if record.mode == 1 or ready then
			searchFor(side, 0)
		elseif #side < record.mode then
			home(side) -- a teammate is gone: the team cannot search as a team
		else
			sendState()
		end
	elseif kind == "CancelAnother" then
		local search = searchOf[p.UserId]
		if search then
			if GlobalQueue.cancel(search) ~= "cancelled" then
				return -- matched: the teleport is on its way
			end
		end
		local side: { Player } = if record.mode == 1 then { p } else teammates(team)
		clearSearch(side)
		for _, mate in side do
			choice[mate.UserId] = nil
			decideBy[mate.UserId] = now() + Config.Multiplayer.RematchSeconds
		end
		sendState()
	end
end

-- Each quarter second: open the choosing when a result shows, close it when a rematch
-- starts, and send home whoever let the time run out.
local function watch()
	local t = TableService.arenaTable()
	if not t or not (begun or closed) then
		return
	end
	local e = t.engine
	-- (A no-show arena, never begun, has only the time-outs below.)
	if begun and e.phase == "Result" and e.epoch ~= seenResult then
		seenResult = e.epoch
		local by = now() + Config.Multiplayer.RematchSeconds
		for _, p in allPlayers() do
			if teamOf[p.UserId] and not choice[p.UserId] then
				decideBy[p.UserId] = by
			end
		end
		sendState()
	elseif begun and e.phase ~= "Result" and e.phase ~= "Waiting" and next(decideBy) ~= nil then
		-- A rematch began: nobody is choosing any more.
		table.clear(decideBy)
		table.clear(choice)
		sendState()
	end
	local time = now()
	local late = {}
	for _, p in allPlayers() do
		local id = p.UserId
		local by = decideBy[id]
		local rematching = begun and e.phase ~= "Result" and e.phase ~= "Waiting"
		if by and time > by and not searchOf[id] and not rematching then
			table.insert(late, p)
		elseif searchAt[id] and time - searchAt[id] > (searchMax[id] or A.SearchMaxSeconds) then
			local search = searchOf[id]
			if search and GlobalQueue.cancel(search) == "cancelled" then
				table.insert(late, p)
			end
		end
	end
	if #late > 0 then
		home(late)
	end
end

--- Run the arena for `list` (after TableService.start in arena mode).
function ArenaService.start(list: any)
	record = list
	listAt = os.clock()
	for team = 1, 2 do
		for _, id in list.teams[team] do
			teamOf[id] = team
		end
	end
	for id, where in list.homes do
		local n = tonumber(id)
		if n then
			homeOf[n] = where
		end
	end
	applyUlts()
	log(("the match plays with %s"):format(if ultsOn() then "ults on" else "no ults"))
	arrivalDeadline = now() + A.ArrivalSeconds
	task.delay(A.ArrivalSeconds, arrivalsDone)
	Net.get("ArenaAction").OnServerEvent:Connect(onAction)
	Players.PlayerAdded:Connect(function(p: Player)
		task.spawn(arrive, p)
		task.defer(sendState)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(arrive, p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		seated[p.UserId] = nil
		local search = searchOf[p.UserId]
		-- A search that found its match is on its way (a team teleports player by player):
		-- nothing here to undo.
		local live = search ~= nil and GlobalQueue.isWaiting(search)
		if live then
			-- A team's search goes with any of its players.
			task.spawn(GlobalQueue.cancel, search)
		end
		searchOf[p.UserId], searchAt[p.UserId], searchMax[p.UserId], decideBy[p.UserId] =
			nil, nil, nil, nil
		-- A teammate left while the team waited to search, or searched, together: the rest go
		-- to the lobby (designer, 2026-09-28).
		local team = teamOf[p.UserId]
		if team and record.mode > 1 and (begun or closed) and (live or search == nil) then
			local waiting = waitingMates(p, team, if live then search else nil)
			if #waiting > 0 then
				clearSearch(waiting)
				home(waiting)
			end
		end
		sendState()
	end)
	task.spawn(function()
		local sinceState = 0
		while true do
			task.wait(0.25)
			sinceState += 0.25
			watch()
			if sinceState >= 2 then
				sinceState = 0
				sendState() -- late listeners
			end
		end
	end)
	if IS_STUDIO then
		local old = ServerStorage:FindFirstChild("ArenaQA")
		if old then
			old:Destroy()
		end
		local qa = Instance.new("BindableFunction")
		qa.Name = "ArenaQA"
		qa.OnInvoke = function(op: string, a: any, b: any): any
			local t = TableService.arenaTable()
			if op == "state" then
				return {
					begun = begun,
					phase = t and t.engine.phase,
					epoch = t and t.engine.epoch,
					series = t and t.engine.series,
					choice = choice,
					notice = notice,
					abilities = t and t.engine.settings.abilities,
				}
			elseif op == "vote" and t then
				-- (userId, "Rematch" | "Decline") for a pretend player.
				local e = t.engine
				TableService.advance(t, now())
				local ok =
					Engine.action(e, a, { kind = b, epoch = e.epoch, turnId = e.turnId }, now())
				TableService.broadcast(t)
				return ok
			elseif op == "fill" then
				fillSynthetic()
				return true
			end
			return nil
		end
		qa.Parent = ServerStorage
	end
	sendState()
end

return ArenaService
