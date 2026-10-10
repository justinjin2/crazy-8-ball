--!strict
-- LocalSearch: every 1v1 Play Global looks in this server first (tutorial v2 4.7, for
-- everyone; the designer: "this new search is also for the rest of the game as well ... max 5
-- seconds wait no matter what, after 5 seconds it plays against a bot").
--
-- Every Config.GlobalQueue.LocalTickSeconds it gathers this server's 1v1 searches (a pad's,
-- the spawn pill's SoloSearch) and the players waiting alone on a 1v1 pad, and pairs them by
-- Matchmaker with this server's windows (Config.GlobalQueue.LocalWindow, never "anyone"); one
-- of a pair must be searching. A pair's searches leave the global queue, both see "Match
-- found!" for a moment (the QueueNotice "Local": a quick screen over the move) and are stood
-- on one table's pad: the pad one of them is on (the older's first), else the free table
-- nearest the older. The full pad starts as any pad does. The global queue keeps running all
-- the while, so a real match worldwide may come first; whichever is taken first stands.
--
-- A search still waiting after Config.Bots.Fallback.SoloSeconds plays a disguised bot of the
-- player's tier (BotService.hereBot) here: at their pad, or at the free table nearest them.
-- With no free table here (or no look for a bot), today's arena bot (BotService.arenaBot).
-- Nobody waits longer than that.
--
-- For the tutorial's Game 2 funnel: Searching fires (player) when a search is first seen, Found
-- (player, kind) when this module makes its match: "Server" (a person here), "Bot" (a bot
-- here) or "Arena" (the arena bot). Lobby servers only (never an arena).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Engine = require(Shared.Rules.MatchEngine)
local Matchmaker = require(Shared.Matchmaking.Matchmaker)
local GlobalQueue = require(script.Parent.GlobalQueue)
local SoloSearch = require(script.Parent.SoloSearch)
local Tables = require(script.Parent.TableService)
local BotService = require(script.Parent.Bots.BotService)

local G = Config.GlobalQueue
local F = Config.Bots.Fallback

local LocalSearch = {}

local searchingEvent = Instance.new("BindableEvent")
--- Fires (player) when a 1v1 search of theirs is first seen here.
LocalSearch.Searching = searchingEvent.Event

local foundEvent = Instance.new("BindableEvent")
--- Fires (player, kind) when this module makes their match: "Server", "Bot" or "Arena".
LocalSearch.Found = foundEvent.Event

-- One side of a match here: a 1v1 search or a player waiting alone on a pad.
type Side = {
	id: string,
	mode: number,
	users: { number },
	rating: number,
	at: number, -- when the search began, or when they stepped onto the pad (server time)
	ults: boolean,
	player: Player,
	kind: string, -- "Pad" (a pad's search), "Solo" (the spawn pill's) or "Waiting" (alone on a pad)
	searching: boolean,
	t: any?, -- the table whose pad they are on
}

local started = false
-- Players a match is being made for now (each once at a time).
local busy: { [Player]: boolean } = {}
-- Tables promised to a match being made (not free to another meanwhile).
local promised: { [any]: boolean } = {}
-- Each player's search last seen (its start), so Searching fires once a search.
local seenAt: { [Player]: number } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function log(text: string)
	print("[8ball] LocalSearch: " .. text)
end

-- Whether `player` may be matched here now: in the server with the save open, past the
-- tutorial's guided part, and not being matched already.
local function eligible(player: Player): boolean
	return player.Parent == Players
		and player:GetAttribute("DataLoaded") == true
		and player:GetAttribute("TutorialActive") == false
		and not busy[player]
end

local function sideOf(player: Player, kind: string, at: number, t: any?): Side?
	if not eligible(player) then
		return nil
	end
	local rating = GlobalQueue.ratingOf({ player })
	if rating == nil then
		return nil
	end
	return {
		id = kind .. player.UserId,
		mode = 1,
		users = { player.UserId },
		rating = rating,
		at = at,
		ults = true, -- every search plays with ults on (designer, 2026-10-02)
		player = player,
		kind = kind,
		searching = kind ~= "Waiting",
		t = t,
	}
end

-- This server's 1v1 searches and lone pad-waiters, now.
local function gather(): { Side }
	local out: { Side } = {}
	local all = Tables.all()
	for id = 1, #all do
		local t = all[id]
		local e = t.engine
		if e.teamSize == 1 and e.phase == "Waiting" and t.pad and not promised[t] then
			local players, at = Tables.waitingSearch(t)
			if players and #players == 1 and at and not e.tutorial then
				local side = sideOf(players[1], "Pad", at, t)
				if side then
					table.insert(out, side)
				end
			elseif
				not e.search
				and not t.search
				and not e.tutorial
				and t.reservedFor == nil
				and Engine.count(e) == 1
			then
				local seat = e.seats[1]
				local p = if seat
						and seat.userId > 0
						and seat.connected
					then Players:GetPlayerByUserId(seat.userId)
					else nil
				local side = if p then sideOf(p, "Waiting", seat.joinedAt, t) else nil
				if side then
					table.insert(out, side)
				end
			end
		end
	end
	for _, w in SoloSearch.waiting() do
		local side = sideOf(w.player, "Solo", w.at, nil)
		if side then
			table.insert(out, side)
		end
	end
	return out
end

-- Takes a side's search out of the global queue. Yields. False when the queue matched it
-- first (it goes there) or it is gone. A pad-waiter has none to take.
local function take(side: Side): boolean
	if side.kind == "Pad" then
		return Tables.takeSearch(side.t)
	elseif side.kind == "Solo" then
		return SoloSearch.cancel(side.player)
	end
	return true
end

-- A match here fell through after `side`'s search was taken: it searches again.
local function giveBack(side: Side)
	if side.player.Parent ~= Players then
		return
	end
	if side.kind == "Pad" and side.t and Tables.tableOf(side.player) == side.t.engine.id then
		Tables.startSearch(side.t, side.player)
	elseif side.kind == "Solo" and Tables.tableOf(side.player) == nil then
		SoloSearch.begin(side.player)
	end
end

local function rootPosition(player: Player): Vector3?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

-- "Match found!" for a moment, covering the move to table `t` (and a bot's arrival); its
-- "Heading to your table..." only for those not on that pad already.
local function announce(players: { Player }, t: any)
	for _, p in players do
		GlobalQueue.notify({ p }, { kind = "Local", moving = Tables.tableOf(p) ~= t.engine.id })
	end
end

-- Two of this server's sides play each other here.
local function matchHere(a: Side, b: Side)
	local t = a.t or b.t
	if t == nil then
		t = Tables.freeTable(1, rootPosition(a.player), promised)
		if t == nil then
			return -- no free table: both keep searching (the global queue may pair them)
		end
	end
	busy[a.player], busy[b.player] = true, true
	promised[t] = true
	local function done()
		busy[a.player], busy[b.player] = nil, nil
		promised[t] = nil
	end
	if not take(a) then
		done()
		return
	end
	if not take(b) then
		giveBack(a)
		done()
		return
	end
	log(
		("%s and %s meet here at table %d (%.1f divisions apart)"):format(
			a.player.Name,
			b.player.Name,
			t.engine.id,
			math.abs(a.rating - b.rating)
		)
	)
	announce({ a.player, b.player }, t)
	task.wait(G.LocalLeadSeconds)
	for _, side in { a, b } do
		if Tables.tableOf(side.player) ~= t.engine.id and not Tables.placeOnPad(t, side.player) then
			-- Someone took the pad meanwhile, or they left: whoever is still here searches again.
			log(("table %d could not take %s"):format(t.engine.id, side.player.Name))
			giveBack(a)
			giveBack(b)
			done()
			return
		end
	end
	foundEvent:Fire(a.player, "Server")
	foundEvent:Fire(b.player, "Server")
	done()
end

-- The arena bot (today's fallback) for a search with no table here.
local function arenaBot(side: Side)
	BotService.arenaBot(side.player, function(match: any): boolean
		local ok = if side.kind == "Pad"
			then Tables.searchToMatch(side.t, match)
			else SoloSearch.toMatch(side.player, match)
		if ok then
			foundEvent:Fire(side.player, "Arena")
		end
		return ok
	end)
end

-- A search that waited SoloSeconds: a bot of the player's tier here, else in an arena.
local function botHere(side: Side)
	local player = side.player
	busy[player] = true
	local t = side.t or Tables.freeTable(1, rootPosition(player), promised)
	if t then
		promised[t] = true
	end
	local function done()
		busy[player] = nil
		if t then
			promised[t] = nil
		end
	end
	local bot = if t then BotService.hereBot(player) else nil -- yields for its look
	if t == nil or bot == nil then
		local ok: boolean, err: any = pcall(arenaBot :: any, side)
		if not ok then
			warn("[8ball] LocalSearch: the arena bot failed: " .. tostring(err))
		end
		done()
		return
	end
	local here = t :: any
	local opponent = bot :: any
	if not take(side) then
		BotService.remove(opponent) -- a real match came first
		done()
		return
	end
	announce({ player }, here)
	task.wait(G.LocalLeadSeconds)
	if Tables.tableOf(player) ~= here.engine.id and not Tables.placeOnPad(here, player) then
		BotService.remove(opponent)
		giveBack(side)
		done()
		return
	end
	-- The bot steps on beside them; the full pad starts as any does.
	if not BotService.seat(opponent, here, { breakFor = player.UserId }) then
		BotService.remove(opponent)
		giveBack(side)
		done()
		return
	end
	log(("%s plays a %s bot here at table %d"):format(player.Name, opponent.tier, here.engine.id))
	foundEvent:Fire(player, "Bot")
	done()
end

local function tick()
	local time = now()
	local sides = gather()
	for _, side in sides do
		if side.searching and seenAt[side.player] ~= side.at then
			seenAt[side.player] = side.at
			searchingEvent:Fire(side.player)
		end
	end
	local paired: { [Side]: boolean } = {}
	local pairs = Matchmaker.pair(sides :: any, time, {
		windows = G.LocalWindow,
		allow = function(a: any, b: any): boolean
			return a.searching or b.searching
		end,
	})
	for _, pair in pairs do
		paired[pair.a], paired[pair.b] = true, true
		task.spawn(matchHere, pair.a, pair.b)
	end
	for _, side in sides do
		if side.searching and not paired[side] and not busy[side.player] then
			if time - side.at >= F.SoloSeconds then
				task.spawn(botHere, side)
			end
		end
	end
end

--- Starts the search's loop (a lobby server; never an arena).
function LocalSearch.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			task.wait(G.LocalTickSeconds)
			local ok: boolean, err: any = pcall(tick :: any)
			if not ok then
				warn("[8ball] LocalSearch: " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		busy[player] = nil
		seenAt[player] = nil
	end)
end

return LocalSearch
