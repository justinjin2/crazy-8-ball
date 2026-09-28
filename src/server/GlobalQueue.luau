--!strict
-- GlobalQueue: the global queue on Roblox (designer, 2026-09-28). The moves are
-- Matchmaking/QueueCore's (pure, Lune-tested); this module gives it MemoryStore, the clock,
-- reserved servers and the teleports.
--
-- - Every server (lobby and arena) runs the leader loop: whoever holds the lease pairs every
--   search in the game each tick and keeps a couple of reserved servers ready.
-- - Each search this server posts has its own thread: every PollSeconds it reads its
--   ticket, and once matched it calls the owner back (TableService, ArenaService), which
--   teleports its players with `teleport`. It marks the ticket alive every HeartbeatSeconds.
-- - Before a teleport each player's save is let go (PlayerData.handOff), so the arena opens
--   it at once; a teleport that fails gives it back (resume) and tells the owner.
-- - Studio cannot reserve servers or teleport: matching runs against Studio's own
--   MemoryStore for real, then the teleport reports "Studio" so the screens can be checked.
--   ServerStorage.GlobalQueueQA (Studio only) posts a search from a pretend other server.
-- - Every step prints a "[8ball] GQ" line with its timing, for the live check.
local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local QueueCore = require(Shared.Matchmaking.QueueCore)
local Ticket = require(Shared.Matchmaking.Ticket)
local Matchmaker = require(Shared.Matchmaking.Matchmaker)
local PlayerData = require(script.Parent.PlayerData)

local G = Config.GlobalQueue
local IS_STUDIO = RunService:IsStudio()
-- This server's name in the queue: its JobId live; Studio has none, so a fresh one.
local SERVER = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)

local GlobalQueue = {}
GlobalQueue.Server = SERVER

export type Match = { id: string, code: string, team: number }
export type Search = {
	ticket: Ticket.Value,
	players: { Player },
	state: string, -- "waiting" | "found" | "done"
	postedAt: number, -- os.clock() when it went in, for the timing lines
	onFound: (search: any, match: Match) -> (),
	onEnded: ((search: any, reason: string) -> ())?,
}

local function clock(): number
	return DateTime.now().UnixTimestampMillis / 1000
end

local function log(text: string)
	print("[8ball] GQ " .. text)
end

---------------------------------------------------------------------------------------------
-- MemoryStore as QueueCore's store
---------------------------------------------------------------------------------------------
local maps: { [string]: MemoryStoreSortedMap } = {}
local function mapOf(name: string): MemoryStoreSortedMap
	local m = maps[name]
	if not m then
		m = MemoryStoreService:GetSortedMap(name)
		maps[name] = m
	end
	return m :: MemoryStoreSortedMap
end

local lastWarn = 0
local function failed(what: string, err: any)
	-- One line at most every few seconds: a MemoryStore outage must not flood the log.
	if os.clock() - lastWarn > 5 then
		lastWarn = os.clock()
		warn(("[8ball] GQ MemoryStore %s failed: %s"):format(what, tostring(err)))
	end
end

local store: QueueCore.Store = {
	update = function(name: string, key: string, change: any, life: number): (boolean, any)
		local ok, value = pcall(function(): any
			return mapOf(name):UpdateAsync(key, change, math.max(1, math.floor(life)))
		end)
		if not ok then
			failed("update", value)
			return false, nil
		end
		return true, value
	end,
	get = function(name: string, key: string): (boolean, any)
		local ok, value = pcall(function(): any
			return mapOf(name):GetAsync(key)
		end)
		if not ok then
			failed("get", value)
			return false, nil
		end
		return true, value
	end,
	set = function(name: string, key: string, value: any, life: number, sortKey: any): boolean
		local ok, err = pcall(function(): any
			return mapOf(name):SetAsync(key, value, math.max(1, math.floor(life)), sortKey)
		end)
		if not ok then
			failed("set", err)
		end
		return ok
	end,
	remove = function(name: string, key: string): boolean
		local ok, err = pcall(function(): any
			mapOf(name):RemoveAsync(key)
			return nil
		end)
		if not ok then
			failed("remove", err)
		end
		return ok
	end,
	range = function(name: string, count: number, after: any): (boolean, { any }?)
		local ok, items = pcall(function(): any
			return mapOf(name):GetRangeAsync(Enum.SortDirection.Ascending, count, after)
		end)
		if not ok then
			failed("range", items)
			return false, nil
		end
		return true, items
	end,
}
GlobalQueue.store = store

---------------------------------------------------------------------------------------------
-- Reserved servers
---------------------------------------------------------------------------------------------
local pool: { { code: string, id: string } } = {}
local refilling = false

local function reserveNow(): (string?, string?)
	if IS_STUDIO then
		-- Studio cannot reserve: a made-up one, so a match can still be made and read back.
		local id = "studio-" .. HttpService:GenerateGUID(false)
		return "studio-code", id
	end
	local ok, code, id = pcall(function(): (string, string)
		return TeleportService:ReserveServer(game.PlaceId)
	end)
	if not ok or type(code) ~= "string" or type(id) ~= "string" then
		failed("ReserveServer", code)
		return nil, nil
	end
	return code, id
end

local function refill()
	if refilling then
		return
	end
	refilling = true
	while #pool < G.ReservePool do
		local code, id = reserveNow()
		if not code or not id then
			break
		end
		table.insert(pool, { code = code, id = id })
	end
	refilling = false
end

local function reserve(): (string?, string?)
	local ready = table.remove(pool, 1)
	if ready then
		task.spawn(refill)
		return ready.code, ready.id
	end
	return reserveNow()
end

---------------------------------------------------------------------------------------------
-- Searches this server owns
---------------------------------------------------------------------------------------------
local searches: { [string]: Search } = {}
local counter = 0

local function finish(search: Search, reason: string)
	if search.state == "done" then
		return
	end
	search.state = "done"
	searches[search.ticket.id] = nil
	if search.onEnded then
		task.spawn(search.onEnded, search, reason)
	end
end

local function found(search: Search, match: Match)
	if search.state ~= "waiting" then
		return
	end
	search.state = "found"
	searches[search.ticket.id] = nil
	log(
		("search %s matched in %.2f s: arena %s, team %d"):format(
			search.ticket.id,
			os.clock() - search.postedAt,
			match.id,
			match.team
		)
	)
	task.spawn(QueueCore.forget, store, search.ticket)
	task.spawn(search.onFound, search, match)
end

-- One search's thread: read it every PollSeconds, mark it alive every HeartbeatSeconds.
local function run(search: Search)
	local lastBeat = os.clock()
	while search.state == "waiting" do
		task.wait(G.PollSeconds)
		if search.state ~= "waiting" then
			break
		end
		local ok, value = QueueCore.read(store, search.ticket)
		if search.state ~= "waiting" then
			break
		end
		if ok and type(value) == "table" and value.state == "matched" and value.match then
			found(search, value.match)
			break
		elseif ok and value == nil then
			-- Gone while searching (MemoryStore forgot it after missed marks): put it back.
			log(("search %s vanished; posting it again"):format(search.ticket.id))
			search.ticket.beat = clock()
			QueueCore.post(store, search.ticket)
		elseif os.clock() - lastBeat >= G.HeartbeatSeconds then
			lastBeat = os.clock()
			QueueCore.beat(store, search.ticket, clock())
		end
	end
end

--- The rating of a group of players from their saves (Matchmaker.rating), or nil if a save
--- is not loaded.
function GlobalQueue.ratingOf(players: { Player }): number?
	local ratings = {}
	for _, p in players do
		local data = PlayerData.read(p)
		if not data then
			return nil
		end
		table.insert(ratings, Matchmaker.rating(data.RankXp, data.RatedMatches > 0))
	end
	return Matchmaker.teamRating(ratings)
end

--- Start searching for `players` (one side of `mode` a side). Yields while the search is
--- posted. Answers the search, or nil and why ("Save", "Store").
function GlobalQueue.enqueue(
	opts: {
		players: { Player },
		mode: number,
		home: string?,
		avoid: { number }?,
		head: number?, -- seconds of searching to credit it with (a search that is starting again)
		onFound: (search: any, match: Match) -> (),
		onEnded: ((search: any, reason: string) -> ())?,
	}
): (Search?, string?)
	local rating = GlobalQueue.ratingOf(opts.players)
	if not rating then
		return nil, "Save"
	end
	counter += 1
	local users = {}
	for _, p in opts.players do
		table.insert(users, p.UserId)
	end
	local now = clock()
	local ticket = Ticket.new({
		id = ("%s:%d"):format(SERVER, counter),
		mode = opts.mode,
		users = users,
		rating = rating,
		at = now - (opts.head or 0),
		server = SERVER,
		home = opts.home or "",
		avoid = opts.avoid,
	})
	ticket.beat = now
	local started = os.clock()
	if not QueueCore.post(store, ticket) then
		return nil, "Store"
	end
	local search: Search = {
		ticket = ticket,
		players = table.clone(opts.players),
		state = "waiting",
		postedAt = started,
		onFound = opts.onFound,
		onEnded = opts.onEnded,
	}
	searches[ticket.id] = search
	log(
		("search %s posted in %.0f ms: %dv%d, rating %.2f, players %s"):format(
			ticket.id,
			(os.clock() - started) * 1000,
			opts.mode,
			opts.mode,
			rating,
			table.concat(users, ",")
		)
	)
	task.spawn(run, search)
	return search, nil
end

--- Take a search back. Yields. Answers "cancelled" (out of the queue), "matched" (too late:
--- the match stands and onFound runs or ran) or "error" (MemoryStore did not answer; the
--- search is still in the queue and this may be tried again).
function GlobalQueue.cancel(search: Search): string
	if search.state == "found" then
		return "matched"
	elseif search.state == "done" then
		return "cancelled"
	end
	local deadline = os.clock() + G.ClaimTimeoutSeconds + 1
	local outcome = "error"
	repeat
		outcome = QueueCore.cancel(store, search.ticket)
		if outcome == "busy" then
			task.wait(0.25) -- the leader is finishing a match with it: a moment
		end
	until outcome ~= "busy" or os.clock() > deadline or search.state ~= "waiting"
	if search.state == "found" then
		return "matched"
	end
	if outcome == "cancelled" then
		finish(search, "Cancelled")
		log(("search %s cancelled"):format(search.ticket.id))
	elseif outcome == "matched" then
		-- Read the match now rather than wait for the next poll.
		local ok, value = QueueCore.read(store, search.ticket)
		if ok and type(value) == "table" and value.match then
			found(search, value.match)
		end
		return "matched"
	end
	return if outcome == "busy" then "error" else outcome
end

--- Whether a search is still looking.
function GlobalQueue.isWaiting(search: Search?): boolean
	return search ~= nil and search.state == "waiting"
end

---------------------------------------------------------------------------------------------
-- Teleports
---------------------------------------------------------------------------------------------
-- Players whose teleport is under way: what to retry with and whom to tell if it fails.
type Pending = {
	options: TeleportOptions,
	tries: number,
	failed: (Player, string) -> (),
	keepReleased: boolean, -- a fallback teleport follows: leave the save let go
}
local pending: { [Player]: Pending } = {}

local function giveBack(player: Player, reason: string)
	local job = pending[player]
	pending[player] = nil
	if not (job and job.keepReleased) then
		PlayerData.resume(player)
	end
	if job then
		job.failed(player, reason)
	end
end

local function teleportGroup(
	players: { Player },
	options: TeleportOptions,
	tries: number,
	failed: (Player, string) -> (),
	keepReleased: boolean?
)
	local here = {}
	for _, p in players do
		if p.Parent == Players then
			table.insert(here, p)
			pending[p] = {
				options = options,
				tries = tries,
				failed = failed,
				keepReleased = keepReleased == true,
			}
		end
	end
	if #here == 0 then
		return
	end
	local ok, err = pcall(function(): any
		return TeleportService:TeleportAsync(game.PlaceId, here, options)
	end)
	if not ok then
		if tries < G.TeleportRetries then
			warn(("[8ball] GQ teleport failed (%s); trying again"):format(tostring(err)))
			task.delay(
				G.TeleportRetrySeconds,
				teleportGroup,
				here,
				options,
				tries + 1,
				failed,
				keepReleased
			)
		else
			warn(("[8ball] GQ teleport failed %d times: %s"):format(tries, tostring(err)))
			for _, p in here do
				giveBack(p, "Teleport")
			end
		end
	end
end

--- Send `players` to a match's arena. Their saves are let go first. `failed(player, why)`
--- runs for anyone still here once every try failed (Studio: at once, "Studio").
function GlobalQueue.teleport(players: { Player }, match: Match, failed: (Player, string) -> ())
	local data = { gq = { match = match.id, sentAt = clock(), from = SERVER } }
	if IS_STUDIO then
		log(("Studio cannot teleport: %d player(s) would join arena %s"):format(#players, match.id))
		task.delay(G.FoundLeadSeconds, function()
			for _, p in players do
				failed(p, "Studio")
			end
		end)
		return
	end
	for _, p in players do
		PlayerData.handOff(p)
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = match.code
	options:SetTeleportData(data)
	log(("teleporting %d player(s) to arena %s"):format(#players, match.id))
	teleportGroup(players, options, 1, failed)
end

--- Send players back to the lobby: to `home` (the lobby server they came from) when there is
--- one, or any lobby server if that fails. Groups by home. `failed(player, why)` runs for
--- anyone still here once every try failed (Studio: at once, "Studio").
function GlobalQueue.sendHome(
	players: { Player },
	homes: { [number]: string },
	failed: ((Player, string) -> ())?
)
	local groups: { [string]: { Player } } = {}
	local order = {}
	for _, p in players do
		if p.Parent == Players then
			local home = homes[p.UserId] or ""
			if not groups[home] then
				groups[home] = {}
				table.insert(order, home)
			end
			table.insert(groups[home], p)
		end
	end
	if IS_STUDIO then
		log(("Studio cannot teleport: %d player(s) would go back to the lobby"):format(#players))
		GlobalQueue.notify(players, { kind = "Failed", reason = "Studio" })
		if failed then
			for _, p in players do
				task.spawn(failed, p, "Studio")
			end
		end
		return
	end
	for _, home in order do
		local group = groups[home]
		for _, p in group do
			PlayerData.handOff(p)
		end
		local options = Instance.new("TeleportOptions")
		options:SetTeleportData({ gq = { home = true, sentAt = clock(), from = SERVER } })
		local anywhere = Instance.new("TeleportOptions")
		anywhere:SetTeleportData({ gq = { home = true, sentAt = clock(), from = SERVER } })
		if home ~= "" and home ~= game.JobId then
			options.ServerInstanceId = home
		else
			options = anywhere
		end
		log(
			("sending %d player(s) back to the lobby %s"):format(
				#group,
				if home ~= "" then home else "(any)"
			)
		)
		-- That server full or gone: any lobby server instead; a last failure keeps them here.
		local function stuck(q: Player, why: string)
			warn(("[8ball] GQ %d could not go back to the lobby: %s"):format(q.UserId, why))
			GlobalQueue.notify({ q }, { kind = "Failed", reason = "Teleport" })
			if failed then
				failed(q, why)
			end
		end
		if options == anywhere then
			teleportGroup(group, anywhere, 1, stuck)
		else
			teleportGroup(group, options, 1, function(p: Player, _why: string)
				teleportGroup({ p }, anywhere, 1, stuck)
			end, true)
		end
	end
end

--- An arena's player list, looking for up to `seconds` (it is written just before the first
--- player could arrive). nil if there is none.
function GlobalQueue.readRecord(matchId: string, seconds: number): any?
	local until_ = os.clock() + seconds
	repeat
		local ok, record = QueueCore.readRecord(store, matchId)
		if ok and record then
			return record
		end
		task.wait(0.25)
	until os.clock() > until_
	return nil
end

---------------------------------------------------------------------------------------------
-- The leader loop, and start
---------------------------------------------------------------------------------------------
local leading = false
local started = false

local function leaderLoop()
	local nextLease, nextTick = 0, 0
	while true do
		local now = os.clock()
		if now >= nextLease then
			nextLease = now + G.LeaseRenewSeconds
			local was = leading
			leading = QueueCore.lease(store, SERVER, clock())
			if leading and not was then
				log("this server now pairs the queue")
				task.spawn(refill)
			end
		end
		if leading and now >= nextTick then
			nextTick = now + G.MatchTickSeconds
			local t0 = os.clock()
			local made, failures = QueueCore.leaderTick(store, reserve, clock())
			for _, record in made do
				log(
					("paired %s vs %s (%dv%d) into arena %s in %.0f ms"):format(
						table.concat(record.teams[1], ","),
						table.concat(record.teams[2], ","),
						record.mode,
						record.mode,
						record.id,
						(os.clock() - t0) * 1000
					)
				)
			end
			for _, why in failures do
				log("could not pair " .. why)
			end
		end
		task.wait(0.1)
	end
end

-- Studio only: pretend another server searches, so matching can be tried with one player.
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("GlobalQueueQA")
	if old then
		old:Destroy()
	end
	local qa = Instance.new("BindableFunction")
	qa.Name = "GlobalQueueQA"
	local fakes: { [string]: Ticket.Value } = {}
	qa.OnInvoke = function(op: string, a: any, b: any, c: any): any
		if op == "inject" then
			-- (mode, users, rating): a search from "qa-remote", kept alive until matched.
			counter += 1
			local ticket = Ticket.new({
				id = ("qa-remote:%d"):format(counter),
				mode = a,
				users = b,
				rating = c or 1,
				at = clock(),
				server = "qa-remote",
				home = "",
			})
			fakes[ticket.id] = ticket
			QueueCore.post(store, ticket)
			task.spawn(function()
				while fakes[ticket.id] do
					task.wait(G.HeartbeatSeconds)
					local ok, value = QueueCore.read(store, ticket)
					if
						not ok
						or not value
						or value.state ~= "waiting" and value.state ~= "claimed"
					then
						fakes[ticket.id] = nil
						break
					end
					QueueCore.beat(store, ticket, clock())
				end
			end)
			return ticket.id
		elseif op == "read" then
			-- (mode, ticketId): the stored ticket.
			local _, value = store.get(QueueCore.ticketMap(a), b)
			return value
		elseif op == "record" then
			local _, record = QueueCore.readRecord(store, a)
			return record
		elseif op == "status" then
			local mine = {}
			for id, s in searches do
				table.insert(mine, { id = id, state = s.state, users = s.ticket.users })
			end
			return { server = SERVER, leading = leading, searches = mine, pool = #pool }
		elseif op == "clear" then
			for id, ticket in fakes do
				fakes[id] = nil
				QueueCore.forget(store, ticket)
			end
			return true
		end
		return nil
	end
	qa.Parent = ServerStorage
end

--- Tell a group of players about their search (QueueNotice).
function GlobalQueue.notify(players: { Player }, notice: any)
	for _, p in players do
		if p.Parent == Players then
			Net.get("QueueNotice"):FireClient(p, notice)
		end
	end
end

function GlobalQueue.start()
	if started then
		return
	end
	started = true
	TeleportService.TeleportInitFailed:Connect(
		function(player: Player, result: Enum.TeleportResult, message: string)
			local job = pending[player]
			if not job then
				return
			end
			warn(
				("[8ball] GQ teleport of %d failed: %s %s"):format(
					player.UserId,
					tostring(result),
					message
				)
			)
			if job.tries < G.TeleportRetries then
				job.tries += 1
				task.delay(G.TeleportRetrySeconds, function()
					if player.Parent == Players and pending[player] == job then
						local ok, err = pcall(function(): any
							return TeleportService:TeleportAsync(
								game.PlaceId,
								{ player },
								job.options
							)
						end)
						if not ok then
							warn("[8ball] GQ teleport retry failed: " .. tostring(err))
							giveBack(player, "Teleport")
						end
					end
				end)
			else
				giveBack(player, "Teleport")
			end
		end
	)
	Players.PlayerRemoving:Connect(function(player: Player)
		pending[player] = nil
	end)
	task.spawn(leaderLoop)
	startQA()
end

return GlobalQueue
