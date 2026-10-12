--!strict
-- Lobby bots (the Bots lane; the designer, 2026-10-02, reworked 2026-10-12 after a tester's
-- notes): disguised bots that make a lobby server look like Config.Bots.Lobby.People people.
-- They "join" (appear at the entrance) and "leave" (vanish) as real players come and go, and
-- move like the tutorial's bot (Bots/LobbyMotion: short stops, a swaying path, looks round,
-- the odd hop; never on the map's seats). What each does next:
--
-- - Come: a real player alone on a 1v1 pad with nobody free near them to play gets one bot,
--   walking over ComeAfterSeconds after they stepped on (ComeAnywaySeconds with a free real
--   player near: they may play each other). The bot with the badge closest to their rank comes
--   and plays at their rank's skill; with every bot busy, a bot-vs-bot game ends at once.
-- - Linger: now and then it stands a little way from a real player who has nobody free near
--   them, turning to them now and then; it never follows, and walks away when they move off or
--   another free real player comes near them.
-- - Pair: two bots play each other at a 1v1 table, only while every real player is in a match
--   (or guided by the tutorial). One game, then they walk off.
-- - Wait: a few wait on a free 1v1 pad; a real player may step on and play it (at their rank's
--   skill).
-- - Roam: otherwise it strolls the aisles, standing about between walks, keeping off people.
--
-- Public lobby servers only (never a private server or an arena), on by themselves live with
-- Config.Bots.Lobby.OnByDefault; in Studio after the designer's /lobbybots. Never near the
-- tutorial's guided part: its players (TutorialActive) and its reserved tables.
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
local LobbyMotion = require(script.Parent.LobbyMotion)

local L = Config.Bots.Lobby
local BOT = Config.Tutorial.Bot

local LobbyBots = {}

type Entry = {
	bot: any,
	mover: LobbyMotion.Mover,
	-- "Idle" (between things) | "Roam" | "Linger" | "Come" | "Wait" | "Pair" | "Play"
	state: string,
	target: Player?, -- Linger: the player it stands near; Come: the player it walks to
	t: any?, -- Come, Wait, Pair: the table it heads for or sits at
	waitUntil: number, -- Wait: when it gets up; Pair: when it gives up on its partner
	skillEpoch: number?, -- the game whose real player's rank its skill was set to
}

local entries: { Entry } = {}
local options: any = nil -- nil: off; else { count? }
local rng = Rng.new(Identity.seed())
local nextJoinAt = 0
local joining = false
local started = false
-- Filling up from none (a new server, or just turned on): they are "already there", spread
-- over the lobby, one right after another, so the first player finds a full server.
local warm = true

-- A real player alone on a pad: which table, since when (os.clock()).
local waitingSince: { [Player]: { id: number, at: number } } = {}
local coming: { [Player]: Entry } = {} -- the bot walking to each player's pad
local lingering: { [Player]: Entry } = {} -- the bot standing near each player
local cooldown: { [Player]: number } = {} -- nobody lingers by them before this

local function range(pair: { number }): number
	return Rng.range(rng, pair[1], pair[2])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
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

-- Whether this server has lobby bots at all: a public lobby, or a forced count (/lobbybots
-- <n>), or Studio with /lobbybots on.
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
-- Who is where
---------------------------------------------------------------------------------------------

local function rootOfPlayer(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function bodyAt(entry: Entry): Vector3?
	local root = Body.root(entry.bot.model)
	return if root then root.Position else nil
end

-- Guided by the tutorial (its arrow, game 1, the chain): the lobby bots leave them be.
local function guided(p: Player): boolean
	return p:GetAttribute("TutorialActive") == true
end

-- In a match (seated at a table whose game is on).
local function inMatch(p: Player): boolean
	local id = Tables.tableOf(p)
	local t = id and Tables.get(id)
	return t ~= nil and t.engine.phase ~= "Waiting"
end

-- Free to play someone: in the lobby (or alone on a pad), not in a match, not guided.
local function free(p: Player): boolean
	return not guided(p) and not inMatch(p) and rootOfPlayer(p) ~= nil
end

-- Whether no free real player but `p` stands within NearStuds of `at`.
local function nobodyNear(p: Player, at: Vector3): boolean
	for _, other in Players:GetPlayers() do
		if other ~= p and free(other) then
			local root = rootOfPlayer(other)
			if root and flat(root.Position - at).Magnitude <= L.NearStuds then
				return false
			end
		end
	end
	return true
end

-- Every real player is in a match or guided by the tutorial.
local function allBusy(): boolean
	for _, p in Players:GetPlayers() do
		if free(p) then
			return false
		end
	end
	return true
end

-- Table `t` (a 1v1) where `p` waits alone on the pad: no search, not the tutorial's.
local function aloneOn(t: any?, p: Player): boolean
	if t == nil or guided(p) then
		return false
	end
	local e = t.engine
	return e.teamSize == 1
		and e.phase == "Waiting"
		and Engine.count(e) == 1
		and Engine.seat(e, p.UserId) ~= nil
		and not e.search
		and not t.search
		and not t.reservedFor
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
			and not t.reservedFor -- the tutorial's table
		then
			table.insert(out, t)
		end
	end
	table.sort(out, function(a, b)
		return a.engine.id < b.engine.id
	end)
	return out
end

local function stillFree(t: any): boolean
	local e = t.engine
	return e.phase == "Waiting" and Engine.count(e) < Engine.capacity(e) and not t.reservedFor
end

-- The real player seated at table `t` (the first), or nil.
local function realAt(t: any): Player?
	for _, s in t.engine.seats do
		if s.userId > 0 then
			local p = Players:GetPlayerByUserId(s.userId)
			if p then
				return p
			end
		end
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- Where they go
---------------------------------------------------------------------------------------------

-- The roof's strolling spots: the aisles between the tables (beside them and at the
-- crossings) and the walkway in front of the first row (from Config.Hub.Tables). A spot with
-- something solid on it (a planter) moves just beside it, or is left out.
local spots: { Vector3 } = {}

local function clearAt(at: Vector3): boolean
	local size = Vector3.new(BOT.AgentRadius * 2, BOT.AgentHeight, BOT.AgentRadius * 2)
	for _, part in workspace:GetPartBoundsInBox(CFrame.new(at), size, OverlapParams.new()) do
		local top = part.Position.Y + part.Size.Y / 2
		local model = part:FindFirstAncestorOfClass("Model")
		local body = model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil -- people move
		if
			part.CanCollide
			and top > BOT.RootHeight - 2
			and part.CollisionGroup ~= "PoolFence"
			and not body
		then
			return false
		end
	end
	return true
end

local function addSpot(at: Vector3)
	local step = BOT.SpotNudgeStuds
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(step, 0, 0),
			Vector3.new(-step, 0, 0),
			Vector3.new(0, 0, step),
			Vector3.new(0, 0, -step),
		}
	do
		if clearAt(at + offset) then
			table.insert(spots, at + offset)
			return
		end
	end
end

local function buildSpots()
	local xs, zs = {}, {}
	for _, row in Config.Hub.Tables do
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
	local front = zs[#zs] + (zs[#zs] - (az[#az] or zs[#zs])) + BOT.FrontStuds
	for _, x in ax do
		for _, z in az do
			addSpot(Vector3.new(x, BOT.RootHeight, z))
		end
		for _, z in zs do
			addSpot(Vector3.new(x, BOT.RootHeight, z))
		end
		addSpot(Vector3.new(x, BOT.RootHeight, front))
	end
	for _, x in xs do
		addSpot(Vector3.new(x, BOT.RootHeight, front))
	end
end

-- Whether `at` keeps KeepStuds off every real player.
local function offPeople(at: Vector3): boolean
	for _, p in Players:GetPlayers() do
		local root = rootOfPlayer(p)
		if root and flat(root.Position - at).Magnitude < L.KeepStuds then
			return false
		end
	end
	return true
end

-- A stroll spot within RoamStuds (not where it stands, off people), a little jitter on top.
local function roamSpot(entry: Entry): Vector3?
	local here = bodyAt(entry)
	if #spots == 0 or here == nil then
		return nil
	end
	local near, any = {}, {}
	for _, spot in spots do
		local d = flat(spot - here).Magnitude
		if d > BOT.RoamJitterStuds * 2 and offPeople(spot) then
			table.insert(any, spot)
			if d <= L.RoamStuds then
				table.insert(near, spot)
			end
		end
	end
	local list = if #near > 0 then near else any
	if #list == 0 then
		return nil
	end
	local angle = Rng.range(rng, 0, 2 * math.pi)
	return list[Rng.int(rng, 1, #list)]
		+ Vector3.new(math.cos(angle), 0, math.sin(angle))
			* BOT.RoamJitterStuds
			* Rng.uniform(rng)
end

-- Its spot on table `t`'s pad: the end away from `p` (or either end).
local function padSpotFor(t: any, p: Player?): CFrame
	local a, b = Tables.padSpot(t, -L.PadSideStuds), Tables.padSpot(t, L.PadSideStuds)
	local root = if p then rootOfPlayer(p) else nil
	if root == nil then
		return if Rng.chance(rng, 0.5) then a else b
	end
	local da = flat(a.Position - root.Position).Magnitude
	local db = flat(b.Position - root.Position).Magnitude
	return if da >= db then a else b
end

---------------------------------------------------------------------------------------------
-- What they do
---------------------------------------------------------------------------------------------

local function idle(entry: Entry)
	entry.state = "Idle"
	entry.target = nil
	entry.t = nil
end

-- A walk to `spot` then a stand about; back to Idle after (unless something else took over).
local function roam(entry: Entry)
	entry.state = "Roam"
	local job = LobbyMotion.cancel(entry.mover)
	task.spawn(function()
		local spot = roamSpot(entry)
		if spot then
			LobbyMotion.walkTo(
				entry.mover,
				job,
				spot,
				{ deadline = os.clock() + L.WalkTimeoutSeconds }
			)
		end
		if entry.mover.job == job then
			LobbyMotion.idle(entry.mover, job, range(L.RoamPauseSeconds))
		end
		if entry.mover.job == job and entry.state == "Roam" then
			idle(entry)
		end
	end)
end

-- Whether `entry` may keep standing near `p`: they are still free with nobody free near them,
-- and not LingerLeaveStuds off.
local function keepLingering(entry: Entry, p: Player): boolean
	if p.Parent ~= Players or not free(p) or Tables.tableOf(p) ~= nil then
		return false
	end
	local root, at = rootOfPlayer(p), bodyAt(entry)
	if root == nil or at == nil then
		return false
	end
	return flat(root.Position - at).Magnitude <= L.LingerLeaveStuds and nobodyNear(p, root.Position)
end

local function linger(entry: Entry, p: Player)
	entry.state = "Linger"
	entry.target = p
	lingering[p] = entry
	local job = LobbyMotion.cancel(entry.mover)
	task.spawn(function()
		local root, here = rootOfPlayer(p), bodyAt(entry)
		if root and here then
			-- A spot a little way off them, on its own side (a few tries for a clear one).
			local away = flat(here - root.Position)
			local base = if away.Magnitude > 0.1
				then math.atan2(away.Z, away.X)
				else Rng.range(rng, 0, 2 * math.pi)
			local dist = range(L.LingerStuds)
			local spot = root.Position + Vector3.new(math.cos(base), 0, math.sin(base)) * dist
			for _, turn in { 0, 0.6, -0.6, 1.2, -1.2 } do
				local at = root.Position
					+ Vector3.new(math.cos(base + turn), 0, math.sin(base + turn)) * dist
				at = Vector3.new(at.X, BOT.RootHeight, at.Z)
				if clearAt(at) then
					spot = at
					break
				end
			end
			LobbyMotion.walkTo(entry.mover, job, spot, {
				deadline = os.clock() + L.WalkTimeoutSeconds,
				face = root.Position,
				stop = function(): boolean
					return p.Parent ~= Players or not free(p) or not nobodyNear(p, root.Position)
				end,
			})
			if entry.mover.job == job and keepLingering(entry, p) then
				LobbyMotion.idle(entry.mover, job, range(L.LingerSeconds), function(): Vector3?
					local r = rootOfPlayer(p)
					return if r then r.Position else nil
				end, function(): boolean
					return not keepLingering(entry, p)
				end)
			end
		end
		if lingering[p] == entry then
			lingering[p] = nil
		end
		cooldown[p] = os.clock() + range(L.LingerCooldownSeconds)
		if entry.mover.job == job and entry.state == "Linger" then
			roam(entry) -- walks off, keeping off people
		end
	end)
end

-- Sets a seated bot's skill to its real opponent's rank (once a game).
local function matchSkill(entry: Entry)
	local t = entry.bot.t
	local p = if t then realAt(t) else nil
	if t and p and entry.skillEpoch ~= t.engine.epoch then
		entry.skillEpoch = t.engine.epoch
		entry.bot.skill = BotService.tierFor(p)
	end
end

-- Walks to table `t`'s pad and sits down there (alone: waiting; with `partner`: their game).
local function goSit(entry: Entry, t: any, state: string)
	entry.state = state
	entry.t = t
	local job = LobbyMotion.cancel(entry.mover)
	task.spawn(function()
		local spot = padSpotFor(t, nil)
		local result = LobbyMotion.walkTo(entry.mover, job, spot.Position, {
			deadline = os.clock() + L.WalkTimeoutSeconds,
			face = spot.Position + spot.LookVector * 5,
			stop = function(): boolean
				return not stillFree(t)
			end,
		})
		if entry.mover.job ~= job or entry.state ~= state then
			return
		end
		if (result == "Done" or result == "Late") and stillFree(t) then
			LobbyMotion.cancel(entry.mover)
			if BotService.seat(entry.bot, t, { at = spot }) then
				entry.waitUntil = os.clock()
					+ (if state == "Wait" then range(L.WaitSeconds) else L.WalkTimeoutSeconds)
				matchSkill(entry)
				return
			end
		end
		idle(entry)
	end)
end

-- Walks to `p`'s pad at table `t` and plays them (their rank's skill).
local function come(entry: Entry, p: Player, t: any)
	coming[p] = entry
	if lingering[p] == entry then
		lingering[p] = nil
	end
	if entry.bot.t then
		BotService.unseat(entry.bot) -- a waiting bot gets up
	end
	entry.state = "Come"
	entry.target = p
	entry.t = t
	local job = LobbyMotion.cancel(entry.mover)
	task.spawn(function()
		local spot = padSpotFor(t, p)
		local result = LobbyMotion.walkTo(entry.mover, job, spot.Position, {
			deadline = os.clock() + L.ComeTimeoutSeconds,
			face = spot.Position + spot.LookVector * 5,
			stop = function(): boolean
				return not aloneOn(t, p)
			end,
		})
		if coming[p] == entry then
			coming[p] = nil
		end
		if entry.mover.job ~= job or entry.state ~= "Come" or entry.bot.gone then
			return
		end
		-- Arrived (or a walk that took too long or got stuck: seated anyway, a last resort).
		if result ~= "Stop" and result ~= "Cancel" and aloneOn(t, p) then
			LobbyMotion.cancel(entry.mover)
			entry.bot.skill = BotService.tierFor(p)
			if BotService.seat(entry.bot, t, { at = spot }) then
				entry.state = "Play"
				entry.skillEpoch = t.engine.epoch
				return
			end
		end
		idle(entry)
	end)
end

-- Whether `entry` can drop what it does to come to a player's pad.
local function available(entry: Entry): boolean
	if entry.bot.gone or entry.bot.model == nil then
		return false
	end
	local s = entry.state
	if s == "Idle" or s == "Roam" or s == "Linger" then
		return entry.bot.t == nil
	end
	if s == "Wait" then
		local t = entry.bot.t
		return t ~= nil and t.engine.phase == "Waiting" and Engine.count(t.engine) == 1
	end
	return false
end

-- Ends a bot-vs-bot game at once (both get up) and answers one of its bots, nearest `at`
-- first; nil when there is none.
local function freeFromGame(at: Vector3): Entry?
	local best, bestGap = nil, math.huge
	for _, entry in entries do
		local t = entry.bot.t
		if t and realAt(t) == nil and Engine.count(t.engine) >= 2 and not entry.bot.gone then
			local here = bodyAt(entry)
			local gap = if here then flat(here - at).Magnitude else math.huge
			if gap < bestGap then
				best, bestGap = entry, gap
			end
		end
	end
	if best == nil then
		return nil
	end
	local t = best.bot.t
	for _, entry in entries do
		if entry.bot.t == t then
			BotService.unseat(entry.bot)
			idle(entry)
		end
	end
	return best
end

-- Sends a bot to `p`, waiting alone at table `t`: the badge closest to their rank, the
-- nearest of those; a bot-vs-bot game ends to free one when none is free.
local function callBot(p: Player, t: any)
	local root = rootOfPlayer(p)
	if root == nil then
		return
	end
	local want = Ranks.tierIndex(BotService.tierFor(p)) or 1
	local best, bestKey = nil, math.huge
	for _, entry in entries do
		if available(entry) then
			local here = bodyAt(entry)
			local gap = math.abs((Ranks.tierIndex(entry.bot.tier) or 1) - want)
			local key = gap * 100000
				+ (if here then flat(here - root.Position).Magnitude else 99999)
			if key < bestKey then
				best, bestKey = entry, key
			end
		end
	end
	local entry = best or freeFromGame(root.Position)
	if entry then
		come(entry, p, t)
	end
end

-- A free real player for `entry` to stand near: nobody free near them, nobody lingering by
-- them, off their cooldown, not at a table; the nearest.
local function lonelyFor(entry: Entry): Player?
	local here = bodyAt(entry)
	if here == nil then
		return nil
	end
	local best, bestGap = nil, math.huge
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local root = rootOfPlayer(p)
		if
			root
			and free(p)
			and Tables.tableOf(p) == nil
			and lingering[p] == nil
			and now >= (cooldown[p] or 0)
			and nobodyNear(p, root.Position)
		then
			local gap = flat(root.Position - here).Magnitude
			if gap < bestGap then
				best, bestGap = p, gap
			end
		end
	end
	return best
end

local function counts(): { [string]: number }
	local out = { Pair = 0, Wait = 0 }
	for _, entry in entries do
		if entry.state == "Pair" then
			out.Pair += 1
		elseif entry.state == "Wait" then
			out.Wait += 1
		end
	end
	return out
end

-- Gives an idle bot its next thing.
local function nextActivity(entry: Entry)
	local free_ = freeTables()
	if
		allBusy()
		and Rng.chance(rng, L.PlayShare)
		and #free_ > L.MinFreeTables
		and counts().Pair + 2 <= math.max(2, math.floor(#entries * L.MaxPlayShare))
	then
		for _, other in entries do
			if
				other ~= entry
				and (other.state == "Idle" or other.state == "Roam")
				and other.bot.t == nil
				and other.bot.model
			then
				local t = free_[Rng.int(rng, 1, #free_)]
				goSit(entry, t, "Pair")
				goSit(other, t, "Pair")
				return
			end
		end
	end
	if
		Rng.chance(rng, L.WaitShare)
		and #free_ > L.MinFreeTables
		and counts().Wait < L.MaxWaiting
	then
		goSit(entry, free_[Rng.int(rng, 1, #free_)], "Wait")
		return
	end
	if Rng.chance(rng, L.LingerShare) then
		local p = lonelyFor(entry)
		if p then
			linger(entry, p)
			return
		end
	end
	roam(entry)
end

---------------------------------------------------------------------------------------------
-- Joining and leaving
---------------------------------------------------------------------------------------------

local function join(at: CFrame?)
	joining = true
	local tier = pick(L.Tiers)
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
	local spot = if #spots > 0 then spots[Rng.int(rng, 1, #spots)] else Vector3.new(s.X, s.Y, s.Z)
	local spawnAt = at
		or if warm
			then CFrame.new(spot + Vector3.new(Rng.range(rng, -3, 3), 0, Rng.range(rng, -2, 2)))
				* CFrame.Angles(0, Rng.range(rng, 0, 2 * math.pi), 0)
			else CFrame.new(s.X + Rng.range(rng, -4, 4), s.Y + 3, s.Z - Rng.range(rng, 0, 4))
				* CFrame.Angles(0, math.rad(180), 0)
	if not BotService.stand(bot, spawnAt) then
		BotService.remove(bot)
		return
	end
	LobbyMotion.prepare(bot.model)
	local entry: Entry = {
		bot = bot,
		mover = LobbyMotion.new(bot),
		state = "Idle",
		waitUntil = 0,
	}
	table.insert(entries, entry)
end

local function removeEntry(entry: Entry)
	local i = table.find(entries, entry)
	if i then
		table.remove(entries, i)
	end
	LobbyMotion.forget(entry.mover)
	for p, e in coming do
		if e == entry then
			coming[p] = nil
		end
	end
	for p, e in lingering do
		if e == entry then
			lingering[p] = nil
		end
	end
end

-- One bot leaves the server: roaming ones first, then waiting, then bot-vs-bot players, and
-- one coming to or playing a real player only once the server holds People real players.
local function leaveOne()
	local best, bestRank = nil, math.huge
	for _, entry in entries do
		local t = entry.bot.t
		local rank = if entry.state == "Come"
			then 4
			elseif t == nil then 1
			elseif realAt(t) ~= nil then 4
			elseif t.engine.phase == "Waiting" then 2
			else 3
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
	for i = #entries, 1, -1 do
		if entries[i].bot.gone then
			removeEntry(entries[i])
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
	-- A real player stepping onto a pad that bots fill (the tutorial's reserved table too): the
	-- bots get up and walk off. (A bot waiting alone keeps its seat: the player sits with it.)
	for _, t in Tables.all() do
		local e = t.engine
		local full = Engine.count(e) >= Engine.capacity(e)
		if
			Engine.count(e) > 0
			and realAt(t) == nil
			and ((full and Tables.standingOnPad(t)) or t.reservedFor)
		then
			for _, entry in entries do
				if entry.bot.t == t then
					BotService.unseat(entry.bot)
					idle(entry)
				end
			end
		end
	end
	local now = os.clock()
	for _, entry in entries do
		local t = entry.bot.t
		if t then
			if realAt(t) then
				-- A real player sat down with it (a waiting bot, a pair's empty seat): it plays
				-- them at their rank's skill.
				entry.state = "Play"
				matchSkill(entry)
			elseif
				(entry.state == "Wait" or entry.state == "Pair")
				and t.engine.phase == "Waiting"
				and Engine.count(t.engine) == 1
				and now >= entry.waitUntil
			then
				-- Waited long enough (or its partner never came): it gets up.
				BotService.unseat(entry.bot)
				idle(entry)
			end
		end
	end
	-- Real players alone on a 1v1 pad: one bot each, in time.
	for _, p in Players:GetPlayers() do
		local id = Tables.tableOf(p)
		local t = if id then Tables.get(id) else nil
		if aloneOn(t, p) then
			local w = waitingSince[p]
			if w == nil or w.id ~= id then
				w = { id = id :: number, at = now }
				waitingSince[p] = w
			end
			local busy = coming[p]
			if busy == nil or busy.bot.gone or busy.state ~= "Come" then
				local root = rootOfPlayer(p)
				local lonely = root ~= nil and nobodyNear(p, root.Position)
				local due = w.at + (if lonely then L.ComeAfterSeconds else L.ComeAnywaySeconds)
				if now >= due then
					callBot(p, t)
				end
			end
		else
			waitingSince[p] = nil
		end
	end
	for _, entry in entries do
		if entry.state == "Idle" and entry.bot.t == nil and entry.bot.model then
			nextActivity(entry)
		end
	end
end

-- A lobby bot whose table let it go: back to the lobby, standing by the pad.
local function freed(bot: any)
	for _, entry in entries do
		if entry.bot == bot then
			local model = bot.model
			local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
			if hum then
				hum:ChangeState(Enum.HumanoidStateType.Running)
			end
			if model then
				LobbyMotion.prepare(model)
			end
			LobbyMotion.cancel(entry.mover)
			idle(entry)
			return
		end
	end
	BotService.remove(bot, "Vanish")
end

Players.PlayerRemoving:Connect(function(p: Player)
	waitingSince[p] = nil
	coming[p] = nil
	lingering[p] = nil
	cooldown[p] = nil
end)

--- Turns the lobby bots on (`opts`: { count? (a fixed number) }) or off (nil). Without a count
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

--- Studio QA: each lobby bot's state, badge, skill and table (BotsQA).
function LobbyBots.state(): { any }
	local out = {}
	for _, entry in entries do
		local at = bodyAt(entry)
		table.insert(out, {
			name = entry.bot.name,
			tier = entry.bot.tier,
			skill = entry.bot.skill,
			state = entry.state,
			target = if entry.target then entry.target.Name else nil,
			table = if entry.bot.t then entry.bot.t.engine.id else nil,
			at = if at then { math.floor(at.X), math.floor(at.Z) } else nil,
			sitting = (function(): boolean
				local model = entry.bot.model
				local hum = if model then model:FindFirstChildOfClass("Humanoid") else nil
				return hum ~= nil and hum.Sit
			end)(),
		})
	end
	return out
end

--- Starts the director (BotService.start hands itself over as `bots`). Live public lobbies
--- start with them on with Config.Bots.Lobby.OnByDefault; in Studio it waits for /lobbybots.
function LobbyBots.start(bots: any)
	if started then
		return
	end
	started = true
	BotService = bots
	buildSpots()
	BotService.onFreed = freed
	if L.OnByDefault and not RunService:IsStudio() then
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
