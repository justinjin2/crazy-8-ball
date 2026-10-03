--!strict
-- The bots (the Bots lane; docs/prompts/BOTS_PROMPT.md). Every bot is a seat with a negative
-- id at a table, a body in workspace.Bots and a brain (src/shared/Bots). This module keeps
-- them, plays their turns (Driver), answers rematches, and runs "Play against PC".
--
-- The API other lanes use (the Tutorial lane drives its bots through it):
--   BotService.spawn(spec) -> Bot          make a bot (a body appears only once seated)
--   BotService.seat(bot, t, options) -> ok  sit it at table t (TableService's record)
--   BotService.remove(bot, how)             "Vanish" (gone at once) or "Angry" (AUGHHHH!)
--   BotService.say(bot, text)               a chat bubble and a chat line in its name
--   BotService.matchEnded                   BindableEvent: (botId, { won, reason, epoch })
-- spec: { kind = "Pc" | "Disguised" | "Tutorial", tier, division?, skill? (the brain's tier,
-- default `tier`), name?, avatar? ({ userId, description } from Identity), cue?, ult?,
-- script? ("Tutorial"), rematch? ("Instant" | "Wait" | "Request" | "Never"), playerTier? (caps
-- its ability) }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Net = require(Shared.Net)
local Engine = require(Shared.Rules.MatchEngine)
local Ranks = require(Shared.Progression.Ranks)
local Look = require(Shared.Bots.Look)
local Rng = require(Shared.Bots.Rng)
local Tables = require(script.Parent.Parent.TableService)
local UltService = require(script.Parent.Parent.UltService)
local Body = require(script.Parent.Body)
local Identity = require(script.Parent.Identity)
local Driver = require(script.Parent.Driver)

local B = Config.Bots

local BotService = {}

export type Bot = {
	id: number,
	kind: string,
	tier: string,
	division: number,
	skill: string,
	name: string,
	avatarUserId: number?,
	description: HumanoidDescription?,
	cue: string,
	ult: string?,
	script: string?,
	rematch: string,
	model: Model?,
	t: any?,
	turnKey: string?,
	epoch: number?,
	visit: number,
	shotInVisit: number,
	lastShooter: number?,
	answered: number?,
	endedEpoch: number?,
	seq: number?,
	gone: boolean?,
}

local bots: { [number]: Bot } = {}
local nextId = B.FirstSeatId
local started = false

--- Fired when a seated bot's game ends: (botId, { won = bool, reason, epoch }).
BotService.matchEnded = Instance.new("BindableEvent")

local function now(): number
	return workspace:GetServerTimeNow()
end

--- The bot with seat id `id`, or nil.
function BotService.get(id: number): Bot?
	return bots[id]
end

--- Every bot now (a copy).
function BotService.list(): { Bot }
	local out = {}
	for _, bot in bots do
		table.insert(out, bot)
	end
	table.sort(out, function(a, b)
		return a.id > b.id
	end)
	return out
end

local function tierOf(tier: any): string
	return if type(tier) == "string"
			and Ranks.tierIndex(tier) ~= nil
			and tier ~= "Unranked"
		then tier
		else "Bronze"
end

--- A new bot from `spec` (see the header). Yields (a disguised bot's look and name are
--- fetched from Roblox). Nil when no look could be had.
function BotService.spawn(spec: any): Bot?
	local kind = spec.kind or "Pc"
	local tier = tierOf(spec.tier)
	local rng = Rng.new(Identity.seed())
	local division = if tier == "Reyes" then 1 else (spec.division or Rng.int(rng, 1, 5))
	local avatarUserId, description, name = nil, nil, nil
	if kind == "Pc" then
		description = Identity.robot()
		name = spec.name or Look.pcName(tier)
	else
		local avatar = spec.avatar or Identity.avatar()
		if not avatar then
			return nil
		end
		avatarUserId, description = avatar.userId, avatar.description
		name = spec.name or Identity.name(Identity.seed())
	end
	local id = nextId
	nextId -= 1
	local bot: Bot = {
		id = id,
		kind = kind,
		tier = tier,
		division = division,
		skill = tierOf(spec.skill or tier),
		name = name :: string,
		avatarUserId = avatarUserId,
		description = description,
		cue = spec.cue or Look.cue(rng, tier),
		ult = spec.ult or Look.ability(rng, spec.playerTier),
		script = spec.script,
		rematch = spec.rematch or (if kind == "Pc" then "Instant" else "Wait"),
		visit = 0,
		shotInVisit = 0,
	}
	bots[id] = bot
	return bot
end

-- The attributes a body carries: what a Player carries for the nameplate, the badge, the
-- cue on its back, the ability icon and the player list (src/client/People.luau).
local function attributesOf(bot: Bot): { [string]: any }
	return {
		[Body.SeatAttribute] = bot.id,
		BotKind = bot.kind,
		DisplayName = bot.name,
		RankTier = bot.tier,
		RankDivision = bot.division,
		RankIndex = Ranks.indexOf(bot.tier, bot.division) or 1,
		[Config.Cue.EquippedAttribute] = bot.cue,
		UltEquipped = bot.ult,
		AvatarUserId = bot.avatarUserId,
	}
end

-- The seat's bot record the engine carries (Settle, Ranking, every client's HUD).
local function seatInfo(bot: Bot): any
	return {
		kind = bot.kind,
		tier = bot.tier,
		division = bot.division,
		avatarUserId = bot.avatarUserId,
		noRematch = bot.rematch == "Never" or nil,
	}
end

--- Sits `bot` at table `t`: on its pad (or `options.at`), seated in the engine. Options:
--- { team? (an arena's side), at? (CFrame), breakFor? (the real player who always breaks) }.
--- True when seated.
function BotService.seat(bot: Bot, t: any, options: any?): boolean
	local o = options or {}
	if bot.gone or bot.t then
		return false
	end
	if not Tables.seatBot(t, bot.id, bot.name, o.team) then
		return false
	end
	local seat = Engine.seat(t.engine, bot.id)
	if seat then
		seat.bot = seatInfo(bot)
	end
	if o.breakFor then
		t.engine.breakFor = o.breakFor
	end
	bot.t = t
	bot.epoch = nil
	local at = o.at or Tables.padSpot(t, if t.engine.teamSize == 1 then 2 else 0)
	if bot.model == nil and bot.description then
		bot.model = Body.build(bot.description, bot.name, at, attributesOf(bot))
	elseif bot.model then
		Body.place(bot.model, at, true)
	end
	if bot.model then
		Body.setGroup(bot.model, Tables.ParticipantsGroup)
	end
	Tables.broadcast(t)
	return true
end

--- Stands `bot`'s body at `at`, free to walk (the lobby, off any table). True when it has a
--- body there.
function BotService.stand(bot: Bot, at: CFrame): boolean
	if bot.gone or bot.t then
		return false
	end
	if bot.model == nil and bot.description then
		bot.model = Body.build(bot.description, bot.name, at, attributesOf(bot))
	end
	local model = bot.model
	if not model then
		return false
	end
	Body.place(model, at, false)
	Body.setGroup(model, "Default")
	return true
end

--- `bot` says `text`: a bubble over its head and a chat line in its name, on every screen.
function BotService.say(bot: Bot, text: string)
	Net.get("BotSay"):FireAllClients(bot.id, text)
end

--- Takes `bot` away: "Vanish" (gone at once, as if it left the game) or "Angry" (the
--- tutorial bot's AUGHHHH!, a jump, gone in mid-air). Leaving its table mid-match is a
--- forfeit (a disguised bot's pays the real player in full: Settle.botReal).
function BotService.remove(bot: Bot, how: string?)
	if bot.gone then
		return
	end
	bot.gone = true
	local t = bot.t
	if t then
		local e = t.engine
		local seat = Engine.seat(e, bot.id)
		if seat and type(seat.bot) == "table" and e.phase ~= "Waiting" and e.phase ~= "Result" then
			seat.bot.vanished = true
		end
		Tables.advance(t, now())
		Engine.remove(e, bot.id, now())
		Tables.broadcast(t)
	end
	bot.t = nil
	local model = bot.model
	bot.model = nil
	if how == "Angry" and model then
		BotService.say(bot, Strings.Bots.Angry)
		Body.angryExit(model)
	else
		Body.vanish(model)
	end
	Identity.releaseAvatar(bot.avatarUserId)
	Identity.releaseName(if bot.kind ~= "Pc" then bot.name else nil)
	bots[bot.id] = nil
end

-- Its game ended: tell whoever listens, and the tutorial bot's exits.
local function ended(bot: Bot, e: any)
	local seat = Engine.seat(e, bot.id)
	local won = seat ~= nil and e.result and e.result.winner == seat.team
	BotService.matchEnded:Fire(bot.id, {
		won = won,
		reason = if e.result then e.result.reason else nil,
		epoch = e.epoch,
	})
	if bot.script == "Tutorial" and not won then
		-- The tutorial bot loses: on its own early 8 it storms off (AUGHHHH!, a jump, gone);
		-- if the player simply ran out, it leaves a moment later.
		local early = e.result and (e.result.reason ~= "LegalEight")
		if early then
			task.delay(0.8, function()
				BotService.remove(bot, "Angry")
			end)
		else
			task.delay(B.LeaveAfterSeconds, function()
				BotService.remove(bot, "Vanish")
			end)
		end
	end
end

-- The rematch row: answered by its rule once the game is over.
local function answerRematch(bot: Bot, t: any)
	local e = t.engine
	local r = e.rematch
	if not r or r.declined or bot.answered == e.epoch then
		return
	end
	local seat = Engine.seat(e, bot.id)
	if not seat or not seat.team then
		return
	end
	local function vote(kind: string)
		Tables.advance(t, now())
		Engine.action(e, bot.id, { kind = kind, epoch = e.epoch, turnId = e.turnId }, now())
		Tables.broadcast(t)
	end
	-- Have the people at the table all said yes?
	local peopleYes = true
	for _, s in e.seats do
		if s.connected and s.team and not s.bot and not r.yes[tostring(s.userId)] then
			peopleYes = false
		end
	end
	local rule = bot.rematch
	if rule == "Never" then
		bot.answered = e.epoch
		vote("Decline")
	elseif rule == "Request" then
		-- The tutorial bot asks for a rematch after beating the player, at once.
		local won = e.result and e.result.winner == seat.team
		bot.answered = e.epoch
		if won then
			vote("Rematch")
		end
	elseif rule == "Instant" then
		if peopleYes then
			bot.answered = e.epoch
			vote("Rematch")
		end
	elseif peopleYes then
		bot.answered = e.epoch
		local epoch = e.epoch
		local rng = Rng.new(Identity.seed())
		local delay = Rng.range(rng, B.RematchDelay[1], B.RematchDelay[2])
		local yes = Rng.chance(rng, B.RematchAccept)
		task.delay(delay, function()
			if bot.t == t and e.epoch == epoch and e.phase == "Result" then
				vote(if yes then "Rematch" else "Decline")
			end
		end)
	end
end

-- One poll of one seated bot.
local function poll(bot: Bot)
	local t = bot.t
	if not t then
		return
	end
	local e = t.engine
	local seat = Engine.seat(e, bot.id)
	if not seat then
		-- The table moved on without it (the game's result reset the pad): it is done here.
		bot.t = nil
		BotService.remove(bot, "Vanish")
		return
	end
	if bot.model then
		Tables.holdBot(t, bot.model, bot.id)
	end
	if bot.epoch ~= e.epoch then
		-- A new game (a rematch): the tutorial script starts again.
		bot.epoch = e.epoch
		bot.visit, bot.shotInVisit, bot.lastShooter, bot.turnKey = 0, 0, nil, nil
	end
	if e.phase == "Result" then
		if bot.endedEpoch ~= e.epoch then
			bot.endedEpoch = e.epoch
			ended(bot, e)
		end
		answerRematch(bot, t)
		return
	end
	local shooting = e.shooter == bot.id
		and (
			e.phase == "Intro"
			or e.phase == "Placement"
			or e.phase == "PocketChoice"
			or e.phase == "Aiming"
			or e.phase == "Frozen"
		)
	if e.shooter ~= nil and e.shooter ~= bot.lastShooter and e.phase ~= "Resolving" then
		if e.shooter == bot.id then
			bot.visit += 1
			bot.shotInVisit = 0
		end
		bot.lastShooter = e.shooter
	end
	if not shooting then
		return
	end
	local key = ("%d:%d:%s:%d"):format(
		e.epoch,
		e.turnId,
		e.phase == "Frozen" and "F" or "T",
		e.shotSeq or 0
	)
	if bot.turnKey == key then
		return
	end
	bot.turnKey = key
	bot.shotInVisit += 1
	task.spawn(Driver.turn, bot, Identity.seed())
end

---------------------------------------------------------------------------------------------
-- Play against PC (the host card, 1v1): the robot of the player's own tier, at once.
---------------------------------------------------------------------------------------------

-- The designer's /botrank (DevCommands): the tier of every bot they meet, by user id.
local forcedTier: { [number]: string } = {}

--- Sets (or with nil clears) the tier of the bots player `userId` meets (/botrank).
function BotService.forceTier(userId: number, tier: string?)
	if tier then
		forcedTier[userId] = tierOf(tier)
	else
		forcedTier[userId] = nil
	end
end

local function playerTier(p: Player): string
	return forcedTier[p.UserId] or tierOf(p:GetAttribute("RankTier"))
end

local function playPc(t: any, p: Player, _payload: any): boolean
	local e = t.engine
	if
		e.phase ~= "Waiting"
		or e.hostId ~= p.UserId
		or e.teamSize ~= 1
		or Engine.count(e) ~= 1
		or e.search
	then
		return false
	end
	local tier = playerTier(p)
	local bot =
		BotService.spawn({ kind = "Pc", tier = tier, playerTier = tier, rematch = "Instant" })
	if not bot then
		return false
	end
	if not BotService.seat(bot, t, { breakFor = p.UserId }) then
		BotService.remove(bot)
		return false
	end
	-- Starts at once, like Play solo: the coin lands for the player (breakFor).
	Tables.advance(t, now())
	local started =
		Engine.action(e, p.UserId, { kind = "Start", epoch = e.epoch, turnId = e.turnId }, now(), 1)
	if not started then
		BotService.remove(bot)
		return false
	end
	return true
end

-- Studio only: ServerStorage.BotsQA lets a test script make and place bots (no chat command
-- can). Invoke("spawn", spec) -> bot id (spec as BotService.spawn); ("stand", id, x, y, z,
-- yaw degrees); ("seat", id, tableId); ("remove", id, "Vanish"|"Angry"); ("say", id, text);
-- ("list") -> { "id name kind tier cue ult avatar" }.
local function studioHook()
	local hook = Instance.new("BindableFunction")
	hook.Name = "BotsQA"
	hook.OnInvoke = function(command: string, ...: any): any
		local args = { ... }
		if command == "spawn" then
			local bot = BotService.spawn(args[1] or {})
			return if bot then bot.id else nil
		elseif command == "list" then
			local out = {}
			for _, bot in BotService.list() do
				table.insert(
					out,
					("%d %s %s %s %s %s %s"):format(
						bot.id,
						bot.name,
						bot.kind,
						bot.tier,
						bot.cue,
						tostring(bot.ult),
						tostring(bot.avatarUserId)
					)
				)
			end
			return out
		end
		local bot = bots[args[1]]
		if not bot then
			return false
		end
		if command == "stand" then
			local at = CFrame.new(args[2], args[3], args[4])
				* CFrame.Angles(0, math.rad(args[5] or 0), 0)
			return BotService.stand(bot, at)
		elseif command == "seat" then
			local t = Tables.get(args[2])
			return t ~= nil and BotService.seat(bot, t)
		elseif command == "remove" then
			BotService.remove(bot, args[2])
			return true
		elseif command == "say" then
			BotService.say(bot, args[2])
			return true
		end
		return false
	end
	hook.Parent = game:GetService("ServerStorage")
end

--- Runs the bots (Bootstrap, after the table, shot and ult services).
function BotService.start()
	if started then
		return
	end
	started = true
	Identity.start()
	UltService.botUlt = function(userId: number): string?
		local bot = bots[userId]
		return if bot then bot.ult else nil
	end
	Tables.onAction("PlayPc", playPc)
	if RunService:IsStudio() then
		studioHook()
	end
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / Config.Multiplayer.Queue.PollsPerSecond then
			return
		end
		elapsed = 0
		for _, bot in BotService.list() do
			local ok, err = pcall(function(): any
				poll(bot)
				return nil
			end)
			if not ok then
				warn("[8ball] bot poll failed: " .. tostring(err))
			end
		end
	end)
end

return BotService
