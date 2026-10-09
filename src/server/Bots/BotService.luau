--!strict
-- The bots (the Bots lane; docs/prompts/BOTS_PROMPT.md). Every bot is a seat with a negative
-- id at a table, a body in workspace.Bots and a brain (src/shared/Bots). This module keeps
-- them, plays their turns (Driver), answers rematches, and runs "Play against PC".
--
-- The API other lanes use (the Tutorial lane drives its bots through it):
--   BotService.spawn(spec) -> Bot          make a bot (a body appears only once seated)
--   BotService.seat(bot, t, options) -> ok  sit it at table t (TableService's record)
--   BotService.joinTable(bot, t, options)   appear on t's pad after a delay and sit (a request)
--   BotService.stand(bot, at) -> ok         stand it in the lobby (no table)
--   BotService.tutorialBot() / tutorialSecondBot()   the tutorial's two opponents
--   BotService.startLobby(options)          lobby bots on/off (the tutorial's fake lobby: a count)
--   BotService.remove(bot, how)             "Vanish" (gone at once) or "Angry" (AUGHHHH!)
--   BotService.say(bot, text)               a chat bubble and a chat line in its name
--   BotService.matchEnded                   BindableEvent: (botId, { won, reason, epoch })
-- spec: { kind = "Pc" | "Disguised" | "Tutorial", tier, division?, skill? (the brain's tier,
-- default `tier`), name?, avatar? ({ userId, description } from Identity), cue?, ult?,
-- script? ("Tutorial"), rematch? ("Instant" | "Wait" | "Request" | "Never"), playerTier? (caps
-- its ability) }.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
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
local GlobalQueue = require(script.Parent.Parent.GlobalQueue)
local SoloSearch = require(script.Parent.Parent.SoloSearch)
local UltService = require(script.Parent.Parent.UltService)
local Body = require(script.Parent.Body)
local Identity = require(script.Parent.Identity)
local Driver = require(script.Parent.Driver)
local LobbyBots = require(script.Parent.LobbyBots)

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
	money: number, -- shown on the player list (the Money attribute), like a player's
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
	lobby: boolean?, -- a lobby bot (LobbyBots): freed from a table, it stays in the lobby
}

local bots: { [number]: Bot } = {}
local nextId = B.FirstSeatId
local started = false

--- Fired when a seated bot's game ends: (botId, { won = bool, reason, epoch }).
BotService.matchEnded = Instance.new("BindableEvent")

--- A lobby bot whose table let it go (its game over, or it stepped aside): LobbyBots sets
--- this to take it back; without it the bot leaves.
BotService.onFreed = nil :: ((Bot) -> ())?

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
		money = math.floor(
			Rng.range(rng, B.Money[1], B.Money[2]) * (Ranks.tierIndex(tier) or 1) / 5
		) * 5,
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
		Money = bot.money,
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

--- Brings `bot` to table `t` the way a person answers a request: `options.delay` seconds later
--- (default 0) it appears on the pad (teleported in) and steps on; the table starts by itself
--- once its pad is full. Options: { delay?, breakFor? (the real player who always breaks;
--- default the table's host) }. `done(ok)` is called once it sat down or could not.
function BotService.joinTable(bot: Bot, t: any, options: any?, done: ((boolean) -> ())?)
	local o = options or {}
	task.delay(o.delay or 0, function()
		local ok = t.engine.phase == "Waiting"
			and BotService.seat(bot, t, { breakFor = o.breakFor or t.engine.hostId })
		if done then
			done(ok)
		end
	end)
end

--- Lobby bots on (`options`: { count? (a fixed number: the tutorial's fake lobby, e.g. 15),
--- tiers? (their badges, e.g. { "Bronze", "Silver", "Gold" }) }) or off (nil). Without a
--- count they keep a public lobby at Config.Bots.Lobby.People people (on by themselves live only with
--- Config.Bots.Lobby.OnByDefault).
function BotService.startLobby(options: any?)
	LobbyBots.set(options)
end

--- The tutorial's first opponent (the Tutorial lane): a Silver-badged bot with a real look and
--- a made-up name, playing the tutorial script. Its first visit pots one of its balls, then
--- scratches; its second knocks the 8 in early (AUGHHHH!, a jump, gone in mid-air). If it
--- wins anyway it asks for a rematch and plays the script again. Yields for its look.
function BotService.tutorialBot(): Bot?
	return BotService.spawn({
		kind = "Tutorial",
		tier = B.Tutorial.FirstTier,
		skill = B.Tutorial.Skill,
		script = "Tutorial",
		rematch = "Request",
		playerTier = "Unranked",
	})
end

--- The tutorial's second opponent: a disguised-looking bot playing a normal game at Bronze
--- level, which never rematches. Both tutorial games are real wins (Settle.botReal).
function BotService.tutorialSecondBot(): Bot?
	return BotService.spawn({
		kind = "Tutorial",
		tier = B.Tutorial.SecondTier,
		skill = B.Tutorial.Skill,
		rematch = "Never",
		playerTier = "Unranked",
	})
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

--- Takes `bot` off its table without it leaving the game (a lobby bot getting up): its seat
--- goes (mid-game that ends the game) and its body stands free where it is.
function BotService.unseat(bot: Bot)
	local t = bot.t
	if t then
		Tables.advance(t, now())
		Engine.remove(t.engine, bot.id, now())
		Tables.broadcast(t)
	end
	bot.t = nil
	local model = bot.model
	if model then
		local root = Body.root(model)
		if root then
			Body.place(model, CFrame.new(root.Position) * root.CFrame.Rotation, false)
		end
		Body.setGroup(model, "Default")
	end
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

--- The tutorial lane (designer, 2026-10-03): game 1's bot storms off as the player's winning
--- 8 drops (AUGHHHH!, a jump, gone in mid-air), before the result. Its seat stays until the
--- game is over (the win stays a LegalEight); `remove` later finds no body left.
function BotService.stormOff(bot: Bot)
	local model = bot.model
	if bot.gone or model == nil then
		return
	end
	bot.model = nil
	BotService.say(bot, Strings.Bots.Angry)
	Body.angryExit(model)
end

-- Its game ended: tell whoever listens, and the tutorial bot's exits.
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

-- The average tier of these seats' players (a player not in the server counts as Bronze).
local function averageTier(seats: { any }): string
	local sum, n = 0, 0
	for _, s in seats do
		local p = Players:GetPlayerByUserId(s.userId)
		local tier = if p then playerTier(p) else "Bronze"
		sum += Ranks.tierIndex(tier) or 1
		n += 1
	end
	local index = math.clamp(math.floor(sum / math.max(1, n) + 0.5), 1, #Config.Ranks.Tiers)
	return Config.Ranks.Tiers[index]
end

-- One analytics event per real player per finished bot game (Config.Bots.Analytics), so the
-- designer can read the real win rate against each tier after launch: value 1 for a win, 0
-- for a loss; fields: the bot's kind, its tier, the player's tier.
local logged: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any
local function logMatch(bot: Bot, e: any)
	if logged[e] == e.epoch or not e.result then
		return
	end
	logged[e] = e.epoch
	for _, s in e.seats do
		local p = if s.userId > 0 then Players:GetPlayerByUserId(s.userId) else nil
		if p and s.team then
			local won = e.result.winner == s.team
			pcall(function()
				AnalyticsService:LogCustomEvent(p, B.Analytics.Event, if won then 1 else 0, {
					[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = bot.kind,
					[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = bot.tier,
					[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = playerTier(p),
				})
			end)
		end
	end
end

local function ended(bot: Bot, e: any)
	logMatch(bot, e)
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
	local anyone = false
	for _, s in e.seats do
		if s.userId > 0 and s.connected then
			anyone = true
		end
	end
	-- Bots alone (a lobby game) play one game, then get up.
	if not anyone or rule == "Never" then
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
		-- A lobby bot goes back to the lobby; any other leaves.
		bot.t = nil
		if bot.lobby and BotService.onFreed then
			BotService.unseat(bot)
			BotService.onFreed(bot)
		else
			BotService.remove(bot, "Vanish")
		end
		return
	end
	-- Whoever real is on its pad always breaks against it (a player who stepped onto a waiting
	-- bot's pad included); bots alone toss the coin.
	if e.phase == "Waiting" then
		local real = nil
		for _, s in e.seats do
			if s.userId > 0 and real == nil then
				real = s.userId
			end
		end
		e.breakFor = real
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

local function playPc(t: any, p: Player, _payload: any, tierOverride: string?): boolean
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
	local tier = tierOverride or playerTier(p)
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

--- Play against PC at table `t` for its host `p`, at `tier` (default: theirs, or /botrank's).
--- The /bot developer command (DevCommands). True when the game started.
function BotService.playPc(t: any, p: Player, tier: string?): boolean
	return playPc(t, p, nil, tier)
end

-- Studio only: ServerStorage.BotsQA lets a test script make and place bots (no chat command
-- can). Invoke("spawn", spec) -> bot id (spec as BotService.spawn); ("tutorial") and
-- ("tutorial2") -> the tutorial's bots' ids; ("stand", id, x, y, z, yaw degrees); ("seat", id,
-- tableId); ("join", id, tableId, delay); ("remove", id, "Vanish"|"Angry"); ("say", id, text);
-- ("ult", id, ultId) sets a bot's ability; ("pc", tableId, userId, tier?) starts Play against PC
-- there for that player, as /bot does (true when it started); ("list") -> { "id name kind tier
-- cue ult avatar" }.
local function studioHook()
	local hook = Instance.new("BindableFunction")
	hook.Name = "BotsQA"
	hook.OnInvoke = function(command: string, ...: any): any
		local args = { ... }
		if command == "spawn" then
			local bot = BotService.spawn(args[1] or {})
			return if bot then bot.id else nil
		elseif command == "tutorial" or command == "tutorial2" then
			local bot = if command == "tutorial"
				then BotService.tutorialBot()
				else BotService.tutorialSecondBot()
			return if bot then bot.id else nil
		elseif command == "pc" then
			local t = Tables.get(args[1])
			local p = game:GetService("Players"):GetPlayerByUserId(args[2])
			return t ~= nil and p ~= nil and BotService.playPc(t, p, args[3])
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
		elseif command == "join" then
			-- ("join", id, tableId, delay): as a request's answer (joinTable).
			local t = Tables.get(args[2])
			if not t then
				return false
			end
			BotService.joinTable(bot, t, { delay = args[3] })
			return true
		elseif command == "say" then
			BotService.say(bot, args[2])
			return true
		elseif command == "ult" then
			bot.ult = args[2]
			return true
		end
		return false
	end
	hook.Parent = game:GetService("ServerStorage")
end

---------------------------------------------------------------------------------------------
-- The global queue's safety net (Config.Bots.Fallback): a 1v1 search with no real opponent
-- after SoloSeconds goes to an arena whose list names a disguised bot of the player's tier.
---------------------------------------------------------------------------------------------

local F = B.Fallback
local fallbackBusy: { [any]: boolean } = {}
-- The tutorial lane: how long a player's solo search waits for a real opponent, when it says
-- (its game 2 meets the bot at once); nil: Fallback.SoloSeconds.
local fallbackWait: ((Player) -> number?)? = nil

--- The tutorial lane's hook on the solo fallback's wait (see above).
function BotService.setFallbackWait(fn: ((Player) -> number?)?)
	fallbackWait = fn
end

-- `deliver(match)` hands the bot match to the search (a pad's or a solo one) and says whether
-- it was taken (false: a real opponent came first).
local function soloFallback(player: Player, deliver: (any) -> boolean)
	local tier = playerTier(player)
	local record = {
		mode = 1,
		teams = { { player.UserId }, {} },
		homes = { [tostring(player.UserId)] = GlobalQueue.Server },
		tickets = {},
		ults = true,
		bots = {
			{ team = 2, kind = "Disguised", tier = tier, playerTier = tier, rematch = "Never" },
		},
	}
	local match = GlobalQueue.botMatch(record, 1)
	if match and not deliver(match) then
		print(("[8ball] GQ bot match %s not used: a real opponent came first"):format(match.id))
	end
end

-- A team search (2v2, 3v3) with no real team after TeamSeconds: a disguised all-bot team at
-- the real team's average rank, each bot a different tier near it.
local function teamFallback(t: any, players: { Player })
	local size = #players
	local seats = {}
	local ids = {}
	local homes = {}
	for _, p in players do
		table.insert(seats, { userId = p.UserId })
		table.insert(ids, p.UserId)
		homes[tostring(p.UserId)] = GlobalQueue.Server
	end
	local centre = Ranks.tierIndex(averageTier(seats)) or 1
	local lowest = math.huge
	for _, p in players do
		lowest = math.min(lowest, Ranks.tierIndex(playerTier(p)) or 1)
	end
	local tiers = Config.Ranks.Tiers
	local spread = if size == 2 then { 0, 1 } else { -1, 0, 1 }
	local bots = {}
	for i = 1, size do
		local index = math.clamp(centre + (spread[i] or 0), 1, #tiers)
		table.insert(bots, {
			team = 2,
			kind = "Disguised",
			tier = tiers[index],
			playerTier = tiers[math.clamp(lowest, 1, #tiers)],
			rematch = "Never",
		})
	end
	local record = {
		mode = size,
		teams = { ids, {} },
		homes = homes,
		tickets = {},
		ults = true,
		bots = bots,
	}
	local match = GlobalQueue.botMatch(record, 1)
	if match and not Tables.searchToMatch(t, match) then
		print(("[8ball] GQ bot team match %s not used: a real team came first"):format(match.id))
	end
end

local function watchSearches()
	for _, t in Tables.all() do
		local size = t.engine.teamSize
		local players, at = nil, nil
		if not fallbackBusy[t] then
			players, at = Tables.waitingSearch(t)
		end
		local wait = if size == 1 then F.SoloSeconds else F.TeamSeconds
		if size == 1 and players and players[1] and fallbackWait then
			wait = fallbackWait(players[1]) or wait
		end
		if players and #players == size and at and now() - at >= wait then
			local group = players
			fallbackBusy[t] = true
			task.spawn(function()
				local ok, err = pcall(function(): any
					if size == 1 then
						soloFallback(group[1], function(match: any): boolean
							return Tables.searchToMatch(t, match)
						end)
					else
						teamFallback(t, group)
					end
					return nil
				end)
				if not ok then
					warn("[8ball] GQ bot fallback failed: " .. tostring(err))
				end
				fallbackBusy[t] = nil
			end)
		end
	end
	-- Play Global with no pad (SoloSearch, the spawn pill): the same 1v1 safety net.
	for _, w in SoloSearch.waiting() do
		local player = w.player
		if not fallbackBusy[player] and now() - w.at >= F.SoloSeconds then
			fallbackBusy[player] = true
			task.spawn(function()
				local ok, err = pcall(function(): any
					soloFallback(player, function(match: any): boolean
						return SoloSearch.toMatch(player, match)
					end)
					return nil
				end)
				if not ok then
					warn("[8ball] GQ solo bot fallback failed: " .. tostring(err))
				end
				fallbackBusy[player] = nil
			end)
		end
	end
end

--- Walks `bot` in to `to` (a few steps from further out), then sits it at arena table `t`
--- on side `team`; `breakFor` is the real player who breaks. Yields. True when seated.
function BotService.walkIn(bot: Bot, t: any, to: CFrame, team: number, breakFor: number?): boolean
	local from = to * CFrame.new(0, 0, F.WalkInStuds)
	if BotService.stand(bot, from) and bot.model then
		local hum = bot.model:FindFirstChildOfClass("Humanoid")
		if hum then
			local arrived = false
			local c = hum.MoveToFinished:Connect(function()
				arrived = true
			end)
			hum:MoveTo(to.Position)
			local deadline = os.clock() + F.WalkInSeconds
			while not arrived and os.clock() < deadline do
				task.wait(0.1)
			end
			c:Disconnect()
		end
	end
	return BotService.seat(bot, t, { team = team, at = to, breakFor = breakFor })
end

--- An arena's bot opponents (ArenaService, from its list's `bots`): each made, walked in and
--- seated on its side; the real player on the other side breaks. Yields. True when all sat.
function BotService.seatArenaBots(t: any, record: any): boolean
	-- The real player who breaks: the first one seated (the list's own sides are empty in a
	-- Studio arena, where players fill the sides as they come).
	local breakFor = nil
	for _, seat in t.engine.seats do
		if breakFor == nil and seat.userId > 0 then
			breakFor = seat.userId
		end
	end
	local all = true
	for i, spec in record.bots do
		local bot = BotService.spawn(spec)
		-- Its side of the pad (side 2 right of the middle, side 1 left), 3 studs apart.
		local side = if (spec.team or 2) == 2 then 1 else -1
		local spot = Tables.padSpot(t, side * (2 + (i - 1) * 3))
		if not bot or not BotService.walkIn(bot, t, spot, spec.team or 2, breakFor) then
			all = false
			if bot then
				BotService.remove(bot)
			end
		end
	end
	return all
end

---------------------------------------------------------------------------------------------
-- Fill with PC (2v2 and 3v3 lobby tables): once the host's side is on the pad, the other
-- side fills with PC robots at that side's average tier; the real side breaks.
---------------------------------------------------------------------------------------------

local function fillPc(t: any, p: Player, _payload: any): boolean
	local e = t.engine
	if e.phase ~= "Waiting" or e.hostId ~= p.UserId or e.teamSize < 2 or e.search then
		return false
	end
	local people = {}
	for _, s in e.seats do
		if s.connected and not s.bot then
			table.insert(people, s)
		end
	end
	if #people ~= e.teamSize or Engine.count(e) ~= e.teamSize then
		return false
	end
	local tier = averageTier(people)
	local lowest = tier
	for _, s in people do
		local q = Players:GetPlayerByUserId(s.userId)
		local own = if q then playerTier(q) else "Bronze"
		if (Ranks.tierIndex(own) or 1) < (Ranks.tierIndex(lowest) or 1) then
			lowest = own
		end
	end
	local made: { Bot } = {}
	for i = 1, e.teamSize do
		local bot = BotService.spawn({ kind = "Pc", tier = tier, playerTier = lowest })
		local at = Tables.padSpot(t, (i - (e.teamSize + 1) / 2) * 3)
		if not bot or not BotService.seat(bot, t, { at = at, breakFor = p.UserId }) then
			if bot then
				BotService.remove(bot)
			end
			for _, other in made do
				BotService.remove(other)
			end
			return false
		end
		table.insert(made, bot)
	end
	for _, s in e.seats do
		s.presetTeam = if s.bot then 2 else 1
	end
	Tables.advance(t, now())
	local started =
		Engine.action(e, p.UserId, { kind = "Start", epoch = e.epoch, turnId = e.turnId }, now(), 1)
	if not started then
		for _, bot in made do
			BotService.remove(bot)
		end
		return false
	end
	return true
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
	Tables.onAction("FillPc", fillPc)
	if RunService:IsStudio() then
		studioHook()
	end
	LobbyBots.start(BotService)
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 1 / Config.Multiplayer.Queue.PollsPerSecond then
			return
		end
		elapsed = 0
		watchSearches()
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
