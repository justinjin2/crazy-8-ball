--!strict
-- BossService (Halloween 2026, hw-map lane): the Pumpkin King's challenge. A player at his
-- throne asks (Net KingChallenge, no arguments); the server checks them (the checks
-- PortalService.allowed makes, minus its Wins check), finds a free lobby 1v1 table (leaving
-- Boss.SpareTables free, never one a local search has promised) and seats them against the
-- King: a "Pc" bot (BotService.playBoss), so Settle pays it as practice and he can't be farmed
-- for money or rank. On a win it calls core's CandyService.bossWon (which counts the quests and
-- decides the Candy and the cooldown), copies the cooldown to the player's ReadyAttribute,
-- grants the Pumpkin Slayer badge (hw-sys) and sends the candy explosion. The throne and its
-- figure are an EventMap part (on only while Live). Off (does nothing at all) while
-- Config.HalloweenMap.Enabled or Boss.Enabled is, and in an arena.
--
-- Boss.Mode "Timed" (designer, 2026-10-28): he visits the roof's middle on the shared schedule
-- (Rules.kingWindow: UTC :15 and :45 for 12 minutes), arriving and leaving in a candy burst and
-- a puff with a banner for everyone. While he is here a challenge with no free table (or with
-- MaxAtOnce matches running) joins his line ("You're #2 in the King's line" on his prompt); the
-- first in line is seated as soon as a table frees, and walking LineStuds away or leaving the
-- server drops a place. When he leaves the line clears. A win pays once per visit (core's
-- CandyService.bossWon(player, visitStart)); losing means trying again at once. A winner of
-- this visit may play him again, but waits behind everyone in the line who hasn't won yet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
-- Core's event clock: its times (the King's cooldown, the pickup hour) carry the Studio and
-- test-place offset (HwTimeOffset; 0 in the live game).
local Clock = require(Shared:WaitForChild("Halloween"):WaitForChild("Clock"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local KingScene = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("KingScene"))
local Engine = require(Shared:WaitForChild("Rules"):WaitForChild("MatchEngine"))

local Server = script.Parent.Parent
local Tables = require(Server:WaitForChild("TableService"))
local BotService = require(Server:WaitForChild("Bots"):WaitForChild("BotService"))
local PlayerData = require(Server:WaitForChild("PlayerData"))
local TutorialService = require(Server:WaitForChild("TutorialService"))
local GlobalQueue = require(Server:WaitForChild("GlobalQueue"))
local Funnel = require(Server:WaitForChild("Funnel"))
local EventMap = require(script.Parent:WaitForChild("EventMap"))
local KingLook = require(script.Parent:WaitForChild("KingLook"))

local HM = Config.HalloweenMap
local K = HM.Boss
local S = Strings.HalloweenMap

local BossService = {}

type King = {
	player: Player,
	tableId: number,
	startedAt: number,
	playerTier: string,
	kingTier: string,
	lastTaunt: number,
	lastSeq: number?,
	ended: boolean?,
	visit: number?, -- the visit (its start) the challenge was seated in (Timed)
	goneAt: number?, -- when his bot was first seen gone with no ending (os.clock)
}

local kings: { [number]: King } = {} -- by bot id
local promised: { [any]: boolean } = {} -- tables a challenge is being seated at
local seating = 0 -- challenges being seated now (playBoss waits while his body is built)
local lastTry: { [Player]: number } = {}
local warned: { [string]: boolean } = {}
local line: { number } = {} -- the King's line this visit (user ids, first first; Timed)
local visit: number? = nil -- the start of the visit running (Timed), nil while he is away

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[HalloweenMap] " .. message)
	end
end

-- A sibling server module by name (core's CandyService, hw-sys's Badges), or nil while it is
-- missing (never a stub: the caller does nothing then).
local function optional(path: { string }): any?
	local node: Instance? = Server
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	if node and node:IsA("ModuleScript") then
		local ok, module = pcall(require, node)
		if ok then
			return module
		end
	end
	return nil
end

local function candyService(): any?
	return optional({ "Halloween", "CandyService" })
end

-- Whether the King bot `botId` still plays (not removed). A King that never saw his result
-- (his table moved on first) is gone without an ending: forgotten after a grace, so a late
-- ending (the result's event runs a moment after) still finds him.
local function playing(botId: number): boolean
	local bot = BotService.get(botId)
	if bot ~= nil and not bot.gone then
		return true
	end
	local king = kings[botId]
	if king and not king.ended then
		king.goneAt = king.goneAt or os.clock()
		if os.clock() - (king.goneAt :: number) > 10 then
			kings[botId] = nil
		end
	end
	return false
end

local function aliveKings(): number
	return Rules.kingsPlaying(kings, playing, seating)
end

local function rootOf(p: Player): BasePart?
	local character = p.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function tierOf(p: Player): string
	local tier = p:GetAttribute("RankTier")
	return if type(tier) == "string" then tier else "Unranked"
end

local function notify(p: Player, reason: string)
	GlobalQueue.notify({ p }, { kind = "Failed", reason = reason })
end

local function log(p: Player, step: string, value: number?, tiers: string?)
	pcall(Funnel.event, p, "PumpkinKing", value or 1, step, tiers or "", Funnel.device(p))
end

-- KingChallenge's outcome: Seated, Lined (Timed: no free table) or NoTable (Throne).
local function logChallenge(p: Player, outcome: string, tiers: string)
	pcall(Funnel.event, p, "KingChallenge", 1, outcome, tiers, Funnel.device(p))
end

-- The tables a local search has promised (LocalSearch.isPromised) and ours, as freeTable's skip.
local function skipSet(): { [any]: boolean }
	local skip: { [any]: boolean } = {}
	for t in promised do
		skip[t] = true
	end
	local LocalSearch = optional({ "LocalSearch" })
	if LocalSearch and LocalSearch.isPromised then
		for id = 1, #Config.Hub.Tables do
			local t = Tables.get(id)
			if t and LocalSearch.isPromised(t) then
				skip[t] = true
			end
		end
	end
	return skip
end

-- The player's own waiting 1v1 table when they are alone on it as its host (he plays them
-- right there), false when they are in any other match, nil when at no table.
local function ownTable(p: Player): any?
	local id = Tables.tableOf(p)
	if id == nil then
		return nil
	end
	local t = Tables.get(id)
	local e = t and t.engine
	if
		e
		and e.teamSize == 1
		and e.phase == "Waiting"
		and e.hostId == p.UserId
		and not e.search
		and not t.search
		and Engine.count(e) == 1
	then
		return t
	end
	return false
end

--- Why `p` may not challenge now (a Strings.GlobalQueue.Failed key), or nil when they may.
--- `qa`: the designer's /king and BotsQA (no distance, throttle or cooldown). `fromLine`: the
--- first in the King's line, seated from anywhere within Timed.LineStuds.
local function refusal(p: Player, qa: boolean, fromLine: boolean?): string?
	if not EventMap.isLive() then
		return "KingNotNow"
	end
	if Rules.kingTimed() and visit == nil and not qa then
		return "KingAway"
	end
	if not PlayerData.isLoaded(p) or PlayerData.isHandedOff(p) then
		return "KingNotNow"
	end
	if p:GetAttribute("HwOn") ~= true and not qa then
		return "KingNotNow"
	end
	if TutorialService.guided(p) or p:GetAttribute(Config.Freecam.Attribute) == true then
		return "KingNotNow"
	end
	if ownTable(p) == false then
		return "KingNotNow" -- in a match (roaming or not)
	end
	local root = rootOf(p)
	if root == nil then
		return "KingNotNow"
	end
	if not qa then
		local reach = if not Rules.kingTimed()
			then K.ServerStuds
			elseif fromLine then K.Timed.LineStuds
			else K.Timed.ServerStuds
		if (root.Position - KingLook.promptPosition()).Magnitude > reach then
			return "KingNotNow"
		end
		local CandyService = candyService()
		local ready = if CandyService then CandyService.bossCooldown(p) else 0
		if type(ready) == "number" and ready > Clock.serverNow() then
			p:SetAttribute(K.ReadyAttribute, ready)
			return "KingCooldown"
		end
	end
	if aliveKings() >= K.MaxAtOnce and not Rules.kingTimed() then
		return "KingBusy" -- (Timed: his line)
	end
	return nil
end

-- `p` joins (or keeps their place in) the King's line; their place on their prompt.
-- Whether `p` already won a prize from him this visit (BeatAttribute, set on a paid win).
local function hasBeaten(p: Player): boolean
	return visit ~= nil and p:GetAttribute(K.BeatAttribute) == visit
end

-- Who in the line (and `also`) already won this visit: they wait behind everyone who hasn't
-- (Rules.linePlace and lineNext; fairness review, 2026-10-28).
local function beatenSet(also: Player?): { [number]: boolean }
	local beaten: { [number]: boolean } = {}
	for _, id in line do
		local q = Players:GetPlayerByUserId(id)
		if q and hasBeaten(q) then
			beaten[id] = true
		end
	end
	if also and hasBeaten(also) then
		beaten[also.UserId] = true
	end
	return beaten
end

-- Everyone in the line sees their place (a joiner ahead of the winners moves them back).
local function renumber()
	for i, id in line do
		local q = Players:GetPlayerByUserId(id)
		if q and q:GetAttribute(K.LineAttribute) ~= i then
			q:SetAttribute(K.LineAttribute, i)
		end
	end
end

local function joinLine(p: Player, tiers: string)
	local fresh = table.find(line, p.UserId) == nil
	Rules.lineJoin(line, p.UserId, beatenSet(p))
	renumber()
	notify(p, if hasBeaten(p) then "KingLinedBeaten" else "KingLined")
	if fresh then
		logChallenge(p, "Lined", tiers)
	end
end

-- Seats `p` against the King. The step logged ("Challenge", or the refusal's). `fromLine`:
-- the first in his line, tried each second (no throttle, no notice while no table frees).
local function challenge(
	p: Player,
	qa: boolean,
	tierOverride: string?,
	fromLine: boolean?
): (boolean, string?)
	local now = os.clock()
	if not qa and not fromLine and lastTry[p] and now - lastTry[p] < K.ThrottleSeconds then
		return false, "Throttle"
	end
	lastTry[p] = now
	local playerTier = tierOf(p)
	local kingTier = tierOverride or Rules.kingTier(playerTier)
	local tiers = playerTier .. ">" .. kingTier
	local why = refusal(p, qa, fromLine)
	if why then
		if fromLine and Rules.lineDrop(line, p.UserId) then
			p:SetAttribute(K.LineAttribute, nil) -- (told once, not every second)
		end
		notify(p, why)
		if why == "KingBusy" then
			log(p, "Busy", 1, tiers)
		elseif why == "KingCooldown" then
			log(p, "Cooldown", 1, tiers)
		end
		return false, why
	end
	local SoloSearch = optional({ "SoloSearch" })
	if SoloSearch then
		pcall(SoloSearch.cancel, p)
	end
	local root = rootOf(p) :: BasePart
	local timed = Rules.kingTimed() and visit ~= nil
	-- Someone would be ahead of them in his line: wait your turn (the line seats them in
	-- order, everyone who hasn't won this visit before any winner).
	if timed and not fromLine and Rules.linePlace(line, p.UserId, beatenSet(p)) > 1 then
		joinLine(p, tiers)
		return false, "KingLined"
	end
	local t = if aliveKings() < K.MaxAtOnce then ownTable(p) else nil
	if not t and aliveKings() < K.MaxAtOnce then
		t = Tables.freeTable(1, root.Position, skipSet(), K.SpareTables)
	end
	if not t then
		if fromLine then
			return false, "KingLined" -- still first; tried again next second
		elseif timed then
			joinLine(p, tiers)
			return false, "KingLined"
		end
		notify(p, "KingNoTable")
		log(p, "NoTable", 1, tiers)
		logChallenge(p, "NoTable", tiers)
		return false, "KingNoTable"
	end
	-- The visit this seat belongs to, taken now: playBoss waits for his body, and a visit
	-- ending meanwhile must not credit the win to the next one.
	local seatVisit = if Rules.kingTimed() then visit or (Rules.kingWindow(Clock.now())) else nil
	promised[t] = true
	seating += 1 -- (a press at the same moment sees this seat taken)
	local ok, bot = pcall(function(): any
		if Tables.tableOf(p) ~= t.engine.id and not Tables.placeOnPad(t, p) then
			return nil
		end
		return BotService.playBoss(t, p, {
			name = S.KingName,
			tier = kingTier,
			skill = kingTier,
			cue = KingLook.cue(),
			description = KingLook.description(),
			icon = KingLook.icon(),
			animations = KingLook.animations(),
			dress = KingLook.dressTable,
		})
	end)
	promised[t] = nil
	seating -= 1
	if not ok or bot == nil then
		if not ok then
			warn("[HalloweenMap] the King's challenge failed: " .. tostring(bot))
		end
		notify(p, "KingNotNow")
		return false, "KingNotNow"
	end
	kings[bot.id] = {
		player = p,
		tableId = t.engine.id,
		startedAt = os.clock(),
		playerTier = playerTier,
		kingTier = kingTier,
		lastTaunt = 0,
		visit = seatVisit,
	}
	if Rules.lineDrop(line, p.UserId) then
		p:SetAttribute(K.LineAttribute, nil)
	end
	log(p, "Challenge", 1, tiers)
	logChallenge(p, "Seated", tiers)
	return true, nil
end

local function pick(lines: { string }): string
	return lines[math.random(1, #lines)]
end

local function taunt(botId: number, lines: { string }, force: boolean?)
	local king = kings[botId]
	local bot = BotService.get(botId)
	if not king or not bot then
		return
	end
	local now = os.clock()
	if not force and now - king.lastTaunt < K.TauntEverySeconds then
		return
	end
	king.lastTaunt = now
	pcall(BotService.say, bot, pick(lines))
end

-- After each flush of a King's table: his line on his pot, his foul, the player's pot.
local function onFlush(t: any)
	for botId, king in kings do
		if king.ended or king.tableId ~= t.engine.id then
			continue
		end
		local e = t.engine
		local pending = e.pending
		if pending == nil or pending.judgement == nil or e.shotSeq == king.lastSeq then
			continue
		end
		king.lastSeq = e.shotSeq
		local j = pending.judgement
		local his = e.shooter == botId
		if j.foul ~= nil and his then
			taunt(botId, S.Taunts.HisFoul)
		elseif j.drops and #j.drops > 0 then
			taunt(botId, if his then S.Taunts.HisPot else S.Taunts.YourPot)
		end
	end
end

-- The King's purple puff where he stood, once his body is gone (he leaves after the result).
local function puffWhenGone(botId: number)
	task.spawn(function()
		local last: Vector3? = nil
		for _ = 1, 120 do
			local bot = BotService.get(botId)
			local model = bot and bot.model
			local root = model and model:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				last = root.Position
			end
			if bot == nil or bot.gone or model == nil then
				break
			end
			task.wait(0.5)
		end
		kings[botId] = nil
		if last then
			Net.get("HalloweenMapFx"):FireAllClients({ kind = "Puff", at = last })
		end
	end)
end

local function reward(p: Player, king: King)
	local amount, granted = 0, false
	-- Timed: they beat him this visit, paid or not (a repeat win, or one paid on another
	-- server or before a rejoin): his line puts them behind everyone who hasn't yet.
	if king.visit then
		p:SetAttribute(K.BeatAttribute, king.visit)
	end
	local CandyService = candyService()
	if CandyService and CandyService.isLive() then
		-- Timed: core pays once per visit (the one the challenge was seated in).
		local ok, r = pcall(CandyService.bossWon, p, king.visit)
		if ok and type(r) == "table" then
			granted, amount = r.granted == true, tonumber(r.amount) or 0
			if type(r.cooldownEndsAt) == "number" then
				p:SetAttribute(K.ReadyAttribute, r.cooldownEndsAt)
			end
		elseif not ok then
			warn("[HalloweenMap] bossWon failed: " .. tostring(r))
		end
	elseif RunService:IsStudio() then
		warnOnce("candy", "core's CandyService is missing or not Live: a King win grants nothing")
	end
	local tiers = king.playerTier .. ">" .. king.kingTier
	pcall(
		Funnel.event,
		p,
		"KingWin",
		amount,
		tiers,
		if granted then "Paid" else "Free",
		Funnel.device(p)
	)
	local Badges = optional({ "Badges" })
	if Badges and Badges.grant then
		pcall(Badges.grant, p, "PumpkinSlayer", "Boss")
	end
	local ok, err = pcall(function()
		local t = Tables.get(king.tableId)
		local placement = t and t.placement
		local at = if placement
			then Vector3.new(placement.x, placement.y, placement.z) + Vector3.new(0, 4, 0)
			else (rootOf(p) and (rootOf(p) :: BasePart).Position or Vector3.zero)
		Net.get("HalloweenMapFx"):FireAllClients({
			kind = "Burst",
			tableId = king.tableId,
			at = at,
			amount = if granted then amount else 0,
			winner = p.UserId,
		})
	end)
	if not ok then
		warn("[HalloweenMap] the King's burst failed: " .. tostring(err))
	end
end

local function onEnded(botId: number, info: any)
	local king = kings[botId]
	if not king or king.ended then
		return
	end
	king.ended = true
	local p = king.player
	local seconds = math.floor(os.clock() - king.startedAt + 0.5)
	local tiers = king.playerTier .. ">" .. king.kingTier
	local outcome = Rules.kingOutcome(info, p.Parent == Players)
	if outcome == "Won" then
		taunt(botId, S.Taunts.HisLoss, true)
		reward(p, king)
	elseif outcome == "Lost" then
		taunt(botId, S.Taunts.HisWin, true)
	end
	if outcome ~= "Gone" then
		log(p, outcome, seconds, tiers)
	end
	puffWhenGone(botId)
end

-- The ReadyAttribute from core's save (a server hop keeps the cooldown).
local function copyCooldown(p: Player)
	local CandyService = candyService()
	if CandyService == nil then
		return
	end
	local ok, ready = pcall(CandyService.bossCooldown, p)
	if ok and type(ready) == "number" then
		p:SetAttribute(K.ReadyAttribute, ready)
	end
end

-- His arrival's puff and candy burst over his stage.
local function arrivalFx()
	local at = KingLook.promptPosition()
	local fx = Net.get("HalloweenMapFx")
	fx:FireAllClients({ kind = "Puff", at = at + Vector3.new(0, 3, 0) })
	fx:FireAllClients({ kind = "Burst", at = at + Vector3.new(0, 6, 0), amount = 0, full = true })
end

-- Timed: he arrives with a banner for everyone, rising out of the roof on each client (Boss
-- .Entrance, KingEntrance) and landing in a candy burst and a puff (at once with Entrance off).
-- KingSpawn is logged for each player here then (his reach; KingChallenge's Seated over it,
-- the uptake).
local function arrive(start: number)
	visit = start
	table.clear(line)
	KingLook.showThrone() -- (built at start; waits only if that build is still running)
	if KingScene.on() then
		task.delay(KingScene.landSeconds(), function()
			if visit == start then
				local ok, err = pcall(function(): any
					arrivalFx()
					return nil
				end)
				if not ok then
					warnOnce("arrivalFx", "the King's arrival burst: " .. tostring(err))
				end
			end
		end)
	else
		arrivalFx()
	end
	Net.get("Banner"):FireAllClients({ kind = "King", here = true })
	for _, p in Players:GetPlayers() do
		if p:GetAttribute("HwOn") == true then
			pcall(Funnel.event, p, "KingSpawn", 1, Rules.minuteText(start), "", Funnel.device(p))
		end
	end
end

-- Timed: he leaves the same way; his line clears (each in it told). The banner names his next
-- visit while the event still runs.
local function leave()
	visit = nil
	for _, id in line do
		local p = Players:GetPlayerByUserId(id)
		if p then
			p:SetAttribute(K.LineAttribute, nil)
			notify(p, "KingLeft")
		end
	end
	table.clear(line)
	Net.get("HalloweenMapFx")
		:FireAllClients({ kind = "Puff", at = KingLook.promptPosition() + Vector3.new(0, 3, 0) })
	KingLook.hideThrone()
	if EventMap.isLive() then
		local next = Rules.minuteText(Rules.kingNext(Clock.now()))
		Net.get("Banner"):FireAllClients({ kind = "King", here = false, next = next })
	end
end

-- The King's line, each second of a visit: the gone and the far lose their place, the rest see
-- their number, and the first one free (not in another match) is seated once a table frees.
local function tickLine()
	local here = KingLook.promptPosition()
	for i = #line, 1, -1 do
		local p = Players:GetPlayerByUserId(line[i])
		local root = p and rootOf(p)
		if p == nil then
			table.remove(line, i)
		elseif root == nil or (root.Position - here).Magnitude > K.Timed.LineStuds then
			table.remove(line, i)
			p:SetAttribute(K.LineAttribute, nil)
			notify(p, "KingLineLeft")
		end
	end
	renumber()
	if aliveKings() >= K.MaxAtOnce then
		return
	end
	local nextId = Rules.lineNext(line, beatenSet(), function(id: number): boolean
		local q = Players:GetPlayerByUserId(id)
		return q ~= nil and ownTable(q) ~= false
	end)
	local nextUp = if nextId then Players:GetPlayerByUserId(nextId) else nil
	if nextUp == nil then
		return
	end
	local root = rootOf(nextUp) :: BasePart
	if ownTable(nextUp) or Tables.freeTable(1, root.Position, skipSet(), K.SpareTables) then
		challenge(nextUp, false, nil, true)
	end
end

-- Timed, each second: he comes and goes on the shared schedule (only while the event is Live).
local function tickVisit()
	local now = Clock.now()
	local start = if EventMap.isLive() and Rules.kingHere(now) then (Rules.kingWindow(now)) else nil
	if visit ~= nil and start ~= visit then
		leave()
	end
	if start ~= nil and visit == nil then
		arrive(start)
	end
	if visit ~= nil and #line > 0 then
		tickLine()
	end
end

--- The designer's /king and BotsQA "boss": a real King match for `p` now, from anywhere, the
--- cooldown ignored. True, or false and why.
function BossService.qa(p: Player, tier: string?): (boolean, string?)
	return challenge(p, true, tier)
end

--- Start listening for challenges (once, from Bootstrap). isLobby: false in an arena.
function BossService.start(isLobby: boolean)
	if not (HM.Enabled and K.Enabled and isLobby) then
		return
	end
	Net.get("KingChallenge").OnServerEvent:Connect(function(p: Player)
		local ok, err = pcall(function()
			challenge(p, false)
		end)
		if not ok then
			warn("[HalloweenMap] challenge: " .. tostring(err))
		end
	end)
	BotService.matchEnded.Event:Connect(function(botId: number, info: any)
		local ok, err = pcall(function()
			onEnded(botId, info)
		end)
		if not ok then
			warn("[HalloweenMap] King result: " .. tostring(err))
		end
	end)
	Tables.onFlush(function(t: any)
		pcall(onFlush, t)
	end)
	-- The intro line once he has sat down.
	task.spawn(function()
		while true do
			task.wait(1)
			for botId, king in kings do
				if not king.ended and king.lastTaunt == 0 then
					taunt(botId, S.Taunts.Seated, true)
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(p: Player)
		-- After the save loads (PlayerData sets DataLoaded).
		p:GetAttributeChangedSignal("DataLoaded"):Connect(function()
			if p:GetAttribute("DataLoaded") == true then
				copyCooldown(p)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(p: Player)
		lastTry[p] = nil
		Rules.lineDrop(line, p.UserId)
	end)
	workspace:GetAttributeChangedSignal(HM.StateAttribute):Connect(function()
		if EventMap.isLive() then
			for _, p in Players:GetPlayers() do
				copyCooldown(p)
			end
		end
	end)
	if Rules.kingVisits() then
		-- Studio: ServerStorage.KingQA:Invoke("next", lead?) jumps the test clock (HwTimeOffset)
		-- so his next visit starts in `lead` seconds (3 by default): the whole arrival as it
		-- runs live (the throne, every client's rise and cutscene, the burst on landing);
		-- ("state") -> what the visit loop sees.
		if RunService:IsStudio() then
			local hook = Instance.new("BindableFunction")
			hook.Name = "KingQA"
			hook.OnInvoke = function(op: string?, lead: any): any
				if op == "next" then
					local now = Clock.now()
					local target = Rules.kingNext(now)
						- (if type(lead) == "number" then lead else 3)
					Clock.setOffset(Clock.offset() + math.floor(target - now))
					return "his next visit " .. Rules.minuteText(Rules.kingNext(Clock.now()))
				elseif op == "state" then
					return {
						visit = visit,
						here = Rules.kingHere(Clock.now()),
						live = EventMap.isLive(),
						line = #line,
						offset = Clock.offset(),
					}
				end
				return 'KingQA ops: ("next", leadSeconds?), ("state")'
			end
			hook.Parent = ServerStorage
		end
		-- The throne and his figure built now, once the meshes load (Assets.wait, up to
		-- Assets.WaitSeconds), into ServerStorage: a server's first visit then arrives on time
		-- (arrive's showThrone no longer waits out the build, so the rise and the burst land
		-- together on every client).
		task.spawn(function()
			local ok, err = pcall(function(): any
				KingLook.prepareThrone()
				return nil
			end)
			if not ok then
				warnOnce("prepare", "the throne's early build: " .. tostring(err))
			end
		end)
		task.spawn(function()
			while true do
				local ok, err = pcall(function()
					tickVisit()
				end)
				if not ok then
					warnOnce("visit " .. tostring(err), "the King's visit: " .. tostring(err)) -- (every second)
				end
				task.wait(1)
			end
		end)
	elseif not Rules.kingTimed() then
		EventMap.addPart(KingLook.thronePart())
	end
end

return BossService
