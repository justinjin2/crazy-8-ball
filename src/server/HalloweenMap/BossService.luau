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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
-- Core's event clock: its times (the King's cooldown, the pickup hour) carry the Studio and
-- test-place offset (HwTimeOffset; 0 in the live game).
local Clock = require(Shared:WaitForChild("Halloween"):WaitForChild("Clock"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
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
}

local kings: { [number]: King } = {} -- by bot id
local promised: { [any]: boolean } = {} -- tables a challenge is being seated at
local lastTry: { [Player]: number } = {}
local warned: { [string]: boolean } = {}

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

local function aliveKings(): number
	local n = 0
	for _, king in kings do
		if not king.ended then
			n += 1
		end
	end
	return n
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
--- `qa`: the designer's /king and BotsQA (no distance, throttle or cooldown).
local function refusal(p: Player, qa: boolean): string?
	if not EventMap.isLive() then
		return "KingNotNow"
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
		local at = Vector3.new(HM.Throne.PromptAt[1], HM.Throne.PromptAt[2], HM.Throne.PromptAt[3])
		if (root.Position - at).Magnitude > K.ServerStuds then
			return "KingNotNow"
		end
		local CandyService = candyService()
		local ready = if CandyService then CandyService.bossCooldown(p) else 0
		if type(ready) == "number" and ready > Clock.serverNow() then
			p:SetAttribute(K.ReadyAttribute, ready)
			return "KingCooldown"
		end
	end
	if aliveKings() >= K.MaxAtOnce then
		return "KingBusy"
	end
	return nil
end

-- Seats `p` against the King. The step logged ("Challenge", or the refusal's).
local function challenge(p: Player, qa: boolean, tierOverride: string?): (boolean, string?)
	local now = os.clock()
	if not qa and lastTry[p] and now - lastTry[p] < K.ThrottleSeconds then
		return false, "Throttle"
	end
	lastTry[p] = now
	local playerTier = tierOf(p)
	local kingTier = tierOverride or Rules.kingTier(playerTier)
	local tiers = playerTier .. ">" .. kingTier
	local why = refusal(p, qa)
	if why then
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
	local t = ownTable(p)
	if not t then
		t = Tables.freeTable(1, root.Position, skipSet(), K.SpareTables)
	end
	if not t then
		notify(p, "KingNoTable")
		log(p, "NoTable", 1, tiers)
		return false, "KingNoTable"
	end
	promised[t] = true
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
			dress = KingLook.dress,
		})
	end)
	promised[t] = nil
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
	}
	log(p, "Challenge", 1, tiers)
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
	local CandyService = candyService()
	if CandyService and CandyService.isLive() then
		local ok, r = pcall(CandyService.bossWon, p)
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
	end)
	workspace:GetAttributeChangedSignal(HM.StateAttribute):Connect(function()
		if EventMap.isLive() then
			for _, p in Players:GetPlayers() do
				copyCooldown(p)
			end
		end
	end)
	EventMap.addPart(KingLook.thronePart())
end

return BossService
