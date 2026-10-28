--!strict
-- CandyService: the Halloween 2026 event on the server (docs/halloween/PLAN.md; the hw-core
-- lane). Candy into the save (PlayerData's Halloween block, one commit a grant), the Pumpkin
-- King's paid wins and cooldown, the lobby pickups' cap, and the end's conversion. Runs in the
-- lobby and in arenas (matches settle in both).
--
-- The interface other lanes call (each call in a pcall at its call site):
--   CandyService.add(player, amount, source, opts?) -> number   Candy added (0 when refused)
--   CandyService.bossWon(player) -> { granted, amount, cooldownEndsAt }   the map lane's King
--   CandyService.bossCooldown(player) -> number   unix time the King is ready again (0: now)
--   CandyService.pickup(player) -> (ok, reason)   reason "Cap" | "NotLive" | "NotLoaded" | nil
--   CandyService.isLive() -> boolean
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local CandyMath = require(Shared.Halloween.CandyMath)
local Quests = require(Shared.Halloween.Quests)
local PlayerData = require(script.Parent.Parent.PlayerData)

local C = Config.Halloween

local CandyService = {}

export type BossWon = { granted: boolean, amount: number, cooldownEndsAt: number }

export type AddOpts = {
	boost: boolean?, -- apply the event multiplier and the friends + group boost (match Candy)
	events: { { kind: string, amount: number } }?, -- quest events counted in the same commit
}

-- The sources CandyService.add takes (the HwCandy event's field).
local SOURCES: { [string]: boolean } = {
	Match = true,
	Quest = true,
	Boss = true,
	Pickup = true,
	Dev = true,
}

-- Whether UltService.Used is heard (the ability quest; else its Alt). Set at start.
local ultHeard = false

-- The quest hooks now: the map lane's King and pickups (Config.HalloweenMap; a missing table or
-- key is off) and the ability signal.
function CandyService.hooks(): Quests.Hooks
	local HM = (Config :: any).HalloweenMap
	local mapOn = type(HM) == "table" and HM.Enabled == true
	return {
		king = mapOn and type(HM.Boss) == "table" and HM.Boss.Enabled == true,
		pickups = mapOn and type(HM.Candy) == "table" and HM.Candy.Enabled == true,
		ult = ultHeard,
	}
end

-- The context every Halloween mutation takes: the server's now, the newest open board, hooks.
function CandyService.ctx(): PlayerData.HwCtx
	local now = Clock.serverNow()
	return { now = now, open = Event.boardIndex(now), hooks = CandyService.hooks() }
end

function CandyService.isLive(): boolean
	return Event.isLive(Clock.serverNow())
end

local function isPlayer(x: any): boolean
	return typeof(x) == "Instance" and x:IsA("Player") and x.Parent == Players
end

-- The friends + group boost inputs from the player's attributes (the GUI lane's FriendsHere,
-- uncapped; the Social service's InGroup). A missing or bad count is 0.
local function boostInputs(player: Player): (number, boolean)
	local friends = tonumber(player:GetAttribute("FriendsHere")) or 0
	if friends ~= friends or friends < 0 then
		friends = 0
	end
	return friends, player:GetAttribute("InGroup") == true
end

-- The whole Candy multiplier for the player now (event x (1 + friends + group)).
function CandyService.multiplier(player: Player): number
	local friends, group = boostInputs(player)
	return CandyMath.multiplier(Event.multiplier(Clock.serverNow()), friends, group)
end

--- Adds Candy earned from `source` (Live only, the save loaded). `opts.boost` applies the
--- event multiplier and the friends + group boost (match Candy); quests, the King and pickups
--- are flat. Returns the Candy added (0 when refused).
function CandyService.add(player: Player, amount: number, source: string, opts: AddOpts?): number
	if not isPlayer(player) or not SOURCES[source] or not CandyService.isLive() then
		return 0
	end
	if type(amount) ~= "number" or amount ~= amount or amount < 1 then
		return 0
	end
	local o: AddOpts = opts or {}
	local candy = math.floor(amount)
	if o.boost == true then
		candy = CandyMath.apply(candy, CandyService.multiplier(player))
	end
	local result = PlayerData.hwAddCandy(player, candy, "Earned", CandyService.ctx(), o.events)
	return if result then result.candy else 0
end

--- A Pumpkin King win (the map lane, from BotService.matchEnded): every win counts for the
--- King quests and KingWins; the first Boss.PaidWinsPerDay wins of the UTC day pay Boss.Candy
--- (flat); every win starts the personal Boss.CooldownSeconds cooldown. Not Live: nothing.
function CandyService.bossWon(player: Player): BossWon
	local none: BossWon = { granted = false, amount = 0, cooldownEndsAt = 0 }
	if not isPlayer(player) or not CandyService.isLive() then
		return none
	end
	local boss = PlayerData.hwBoss(player, CandyService.ctx())
	if boss == nil then
		return none
	end
	return { granted = boss.granted, amount = boss.amount, cooldownEndsAt = boss.cooldownEndsAt }
end

--- When the player's King cooldown ends (unix seconds, the server clock), or 0 when none runs.
function CandyService.bossCooldown(player: Player): number
	if not isPlayer(player) then
		return 0
	end
	return PlayerData.hwBossCooldown(player, Clock.serverNow())
end

--- A lobby Candy pickup (the map lane's CandyDrop): +Pickup.Candy, flat. (ok, reason): "NotLive"
--- outside the event, "NotLoaded" before the save loads, "Cap" at Pickup.HourCap this UTC hour.
function CandyService.pickup(player: Player): (boolean, string?)
	if not isPlayer(player) then
		return false, "NotLoaded"
	end
	if not CandyService.isLive() then
		return false, "NotLive"
	end
	local ok, reason = PlayerData.hwPickup(player, CandyService.ctx())
	return ok, reason
end

--- What Ranking.settleOne knows about one player's settled match.
export type MatchFacts = {
	balls: number, -- balls that counted for the player's side (Economy.tally)
	nice: number, -- the player's nice shots
	won: boolean,
	real: boolean, -- past the one-minute mark (or a bot match that always counts)
	forfeited: boolean?, -- the player's side forfeited
	payKind: string, -- Settle.moneyKind: "Player", "PC", ...
	botKind: string?, -- Settle.botKind: "Tutorial", "Disguised", "Pc" or nil
	teamSize: number?,
	farm: { Balls: number, Bonus: number }?, -- the anti-farm row (Money.farmRow)
	matchKey: string, -- Economy.matchKey ("tableId:epoch")
}

-- The last match each player used an ability in ("tableId:epoch", from UltService.Used).
local ultMatch: { [Player]: string } = setmetatable({}, { __mode = "k" }) :: any

--- A settled match's Candy and quest events (Ranking.settleOne, in a pcall): real matches
--- against people only (the tutorial's bot counts; a disguised bot, PC and solo never do), all
--- in one commit. Returns the Candy added (0 when the match pays none: never a "+0").
function CandyService.matchSettled(player: Player, f: MatchFacts): number
	if not isPlayer(player) or C.Match.Enabled ~= true or not CandyService.isLive() then
		return 0
	end
	if not f.real or f.payKind ~= "Player" or f.botKind == "Disguised" then
		return 0
	end
	local farm = f.farm or { Balls = 1, Bonus = 1 }
	local base = CandyMath.base({
		balls = f.balls,
		finished = if f.forfeited == true then 0 else 1,
		won = if f.won then 1 else 0,
		farmBalls = farm.Balls,
		farmBonus = farm.Bonus,
	})
	local candy = CandyMath.apply(base, CandyService.multiplier(player))
	local team = (f.teamSize or 1) >= 2
	local events = {
		{ kind = "Matches", amount = 1 },
		{ kind = "Balls", amount = f.balls },
		{ kind = "NiceShots", amount = f.nice },
	}
	if f.won then
		table.insert(events, { kind = "Wins", amount = 1 })
	end
	if team then
		table.insert(events, { kind = "TeamMatches", amount = 1 })
		if f.won then
			table.insert(events, { kind = "TeamWins", amount = 1 })
		end
	end
	if ultMatch[player] == f.matchKey then
		table.insert(events, { kind = "UltMatches", amount = 1 })
	end
	local result = PlayerData.hwAddCandy(player, candy, "Earned", CandyService.ctx(), events)
	return if result then result.candy else 0
end

-- Hears hw-sys's UltService.Used (player, tableId, epoch) for the ability quest, through a
-- guarded require: missing, the quest's Alt stands in (CandyService.hooks).
local function listenUlts()
	local ok, UltService = pcall(require, script.Parent.Parent:FindFirstChild("UltService") :: any)
	local used = if ok and type(UltService) == "table" then (UltService :: any).Used else nil
	if typeof(used) ~= "RBXScriptSignal" then
		return
	end
	local connected = pcall(function()
		used:Connect(function(player: Player, tableId: number, epoch: number)
			if
				typeof(player) == "Instance"
				and type(tableId) == "number"
				and type(epoch) == "number"
			then
				ultMatch[player] = ("%d:%d"):format(tableId, epoch)
			end
		end)
	end)
	ultHeard = connected
end

-- The tick for one player: held grants (a cue that became ready) and the end's conversion.
local function tickPlayer(player: Player): any
	local ctx = CandyService.ctx()
	if Event.over(ctx.now) then
		PlayerData.hwConvert(player, ctx)
		return nil
	end
	PlayerData.hwRetry(player)
	return nil
end

-- The /hw dev command (DevCommands; the designer's account only, checked there). Returns the
-- lines to tell. `time` moves the test clock (Studio and the test place only):
--   /hw                          the state, Candy, board, multiplier, active time
--   /hw time before|countdown|live|rush|double|end|real, /hw time board <n>, /hw time +<seconds>
--   /hw candy <n>   /hw quest done   /hw active <seconds>   /hw kingwin   /hw convert   /hw reset
function CandyService.dev(player: Player, args: { string }): { string }
	local D = Strings.Halloween.Dev
	local verb, arg = args[1] or "", args[2]
	local lines: { string } = {}
	local function say(text: string)
		table.insert(lines, text)
	end
	if verb == "time" then
		if not Clock.testAllowed() then
			say(D.TimeLiveGame)
			return lines
		end
		local real = os.time()
		local targets: { [string]: number } = {
			before = C.CountdownAt - 60,
			countdown = C.StartsAt - 60,
			live = C.StartsAt + 15 * 60, -- 19:15, between Rushes
			rush = C.StartsAt + 3600 + 30, -- 20:00:30, a Rush
			double = C.Double.From + 13 * 3600 + 15 * 60, -- Oct 31 13:15 EDT, between Rushes
			["end"] = C.EndsAt + 5,
			real = real,
		}
		local target = targets[arg or ""]
		if arg == "board" then
			local n = tonumber(args[3] or "")
			if n ~= nil and n >= 1 and n <= C.Boards then
				target = Event.boardOpensAt(math.floor(n)) + 15 * 60
			end
		elseif arg ~= nil and string.sub(arg, 1, 1) == "+" then
			local skip = tonumber(string.sub(arg, 2))
			if skip ~= nil then
				target = Clock.serverNow() + math.floor(skip)
			end
		end
		if target == nil then
			say(D.TimeUsage)
			return lines
		end
		Clock.setOffset(target - real)
	elseif verb == "candy" then
		local n = tonumber(arg or "")
		if n == nil or n < 1 then
			say(D.Usage)
			return lines
		end
		say(D.Added:format(CandyService.add(player, n, "Dev")))
	elseif verb == "quest" then
		local ctx = CandyService.ctx()
		local needs: { [string]: number } = {}
		for n = 1, ctx.open do
			local list: { Quests.Quest } = Quests.board(n, ctx.hooks) or {}
			for _, quest in list do
				needs[quest.kind] = (needs[quest.kind] or 0) + quest.need
			end
		end
		local events = {}
		for kind, need in needs do
			table.insert(events, { kind = kind, amount = need })
		end
		table.sort(events, function(a, b)
			return a.kind < b.kind
		end)
		local result = PlayerData.hwQuest(player, events, ctx)
		say(D.QuestsDone:format(if result then #result.quests else 0))
	elseif verb == "active" then
		local n = tonumber(arg or "")
		if n == nil or n < 1 then
			say(D.Usage)
			return lines
		end
		PlayerData.hwActive(player, math.floor(n), CandyService.ctx())
	elseif verb == "kingwin" then
		local won = CandyService.bossWon(player)
		say(D.KingWin:format(won.amount, math.max(0, won.cooldownEndsAt - Clock.serverNow())))
	elseif verb == "convert" then
		local result = PlayerData.hwConvert(player, CandyService.ctx())
		say(if result then D.Converted:format(result.money) else D.NotConverted)
	elseif verb == "reset" then
		if not Clock.testAllowed() then
			say(D.TimeLiveGame)
			return lines
		end
		PlayerData.hwReset(player)
	elseif verb ~= "" then
		say(D.Usage)
		return lines
	end
	local now = Clock.serverNow()
	local hw = PlayerData.halloween(player)
	say(
		D.Status:format(
			Event.state(now),
			os.date("!%a %H:%M:%S", now) :: string,
			Clock.offset(),
			if hw then hw.Earned + hw.Bought else 0,
			Event.boardIndex(now),
			Event.multiplier(now),
			if hw then hw.Active else 0
		)
	)
	return lines
end

-- Studio only: ServerStorage.HwQA (a BindableFunction; clients can never reach it), so a
-- Studio check can drive this module (an MCP require gets a copy of its own).
--   ("add", userId, amount, source, boost?) -> CandyService.add
--   ("pickup", userId) -> (ok, reason)     ("boss", userId) -> bossWon
--   ("cooldown", userId) -> seconds left    ("save", userId) -> the Halloween field (a copy)
--   ("now") -> { now, state, multiplier, board }
local function startQA()
	if not RunService:IsStudio() then
		return
	end
	local old = ServerStorage:FindFirstChild("HwQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "HwQA"
	hook.OnInvoke = function(op: string, userId: number?, a: any, b: any, c: any): ...any
		if op == "now" then
			local now = Clock.serverNow()
			return {
				now = now,
				state = Event.state(now),
				multiplier = Event.multiplier(now),
				board = Event.boardIndex(now),
			}
		end
		local player = Players:GetPlayerByUserId(userId or 0)
		assert(player, "HwQA: no player in game with that UserId")
		if op == "add" then
			return CandyService.add(player, a, b, { boost = c == true })
		elseif op == "pickup" then
			return CandyService.pickup(player)
		elseif op == "boss" then
			return CandyService.bossWon(player)
		elseif op == "cooldown" then
			local at = CandyService.bossCooldown(player)
			return if at > 0 then at - Clock.serverNow() else 0
		elseif op == "save" then
			return PlayerData.halloween(player)
		end
		error("HwQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

local started = false

function CandyService.start()
	if started then
		return
	end
	started = true
	startQA()
	listenUlts()
	PlayerData.Loaded:Connect(function(player: Player)
		local ok, err = pcall(tickPlayer, player)
		if not ok then
			warn("[8ball] CandyService: on load: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while true do
			task.wait(C.TickSeconds)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, player)
				if not ok then
					warn("[8ball] CandyService: tick: " .. tostring(err))
				end
			end
		end
	end)
end

return CandyService
