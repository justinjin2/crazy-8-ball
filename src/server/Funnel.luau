--!strict
-- Funnel: the one place the game's funnels go to Roblox's analytics (AnalyticsService; the
-- Creator Dashboard's Funnels and Custom Events pages). Server side only, never trusted from a
-- client without a check by the caller. Tutorial v2's design: docs/TUTORIAL_FUNNELS.md.
--
-- - The onboarding funnel (LogOnboardingFunnelStepEvent): Tutorial/Steps.Funnel, each step
--   once per player ever (a bit in the save's Flags.Funnel), and only for new players: step 1
--   (Joined) is logged for a brand-new save, and no later step for a player without it. Its
--   fields (device, path) are read from the first step on the dashboard.
-- - One-time funnels (LogFunnelStepEvent with the player's id as the session): Steps.Funnels
--   (PathS, PathR, Game2, Social), each step once per player (a bit in its own Flags key).
-- - Repeating funnels (a session per visit): the shop, a free lucky block's life, the spins.
-- - Custom events (LogCustomEvent, up to three fields): Hint, TutorialSkipped, StepTime,
--   TutorialError and the Game2 result.
--
-- Every call is wrapped in pcall: analytics never breaks the game. Studio sends nothing to the
-- dashboard, so each call prints there (Config.Tutorial.Funnel.Print), and every player's last
-- calls are kept in this server for the designer's /funnel command.
local AnalyticsService = game:GetService("AnalyticsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Steps = require(Shared.Tutorial.Steps)
local PlayerData = require(script.Parent.PlayerData)

local F = Config.Tutorial.Funnel

local Funnel = {}

-- The devices the field may name (the client reports its own; TutorialService checks it).
Funnel.Devices = { PC = true, Phone = true, Tablet = true, Console = true }

-- The player attribute holding the checked device ("" until reported).
Funnel.DeviceAttribute = "TutorialDevice"

-- Each player's last calls (text lines), for /funnel.
local logs: { [Player]: { string } } = {}

local function keep(player: Player, text: string)
	local list = logs[player]
	if list == nil then
		list = {}
		logs[player] = list
	end
	table.insert(list, text)
	while #list > F.LogKeep do
		table.remove(list, 1)
	end
	if F.Print and RunService:IsStudio() then
		print(("[8ball] Funnel: %s (%s)"):format(text, player.Name))
	end
end

local function call(what: string, fn: () -> ())
	local ok, err = pcall(function(): any
		fn()
		return nil
	end)
	if not ok then
		warn(("[8ball] Funnel: %s failed: %s"):format(what, tostring(err)))
	end
end

-- Up to three short field values as AnalyticsService's custom fields (nil ones left out).
local function fields(a: string?, b: string?, c: string?): { [string]: string }
	local out: { [string]: string } = {}
	if a then
		out[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = a
	end
	if b then
		out[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = b
	end
	if c then
		out[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = c
	end
	return out
end

-- The mask kept under `key` in the save's Flags (nil when not loaded, 0 when not set).
local function mask(player: Player, key: string): number?
	local data = PlayerData.read(player)
	if data == nil then
		return nil
	end
	local value = data.Flags[key]
	return if type(value) == "number" then value else 0
end

--- The player's device for a field ("PC", "Phone", "Tablet", "Console"; "Unknown" before
--- the client said).
function Funnel.device(player: Player): string
	local d = player:GetAttribute(Funnel.DeviceAttribute)
	return if type(d) == "string" and Funnel.Devices[d] then d else "Unknown"
end

-- The player's game-1 path for a field ("S", "R"; "None" before game 1).
local function pathOf(player: Player): string
	local p = PlayerData.flag(player, "TutorialPath")
	return if type(p) == "string" and Steps.Paths[p] then p else "None"
end

--- Logs onboarding funnel step `name` (a Steps.Funnel name) once per player ever, with the
--- device and path as its fields. Steps a player skips are simply never logged. False when
--- already logged, not a new player's, or not loaded.
function Funnel.onboarding(player: Player, name: string): boolean
	local n = Steps.funnelNumber(name)
	if n == nil then
		warn("[8ball] Funnel: unknown onboarding step " .. tostring(name))
		return false
	end
	local m = mask(player, F.OnboardingFlag)
	-- Only players whose first step was logged (a brand-new save): nobody joins it halfway.
	if m == nil or Steps.has(m, n) or (n > 1 and not Steps.has(m, 1)) then
		return false
	end
	if not PlayerData.setFlag(player, F.OnboardingFlag, Steps.mark(m, n)) then
		return false
	end
	local device, path = Funnel.device(player), pathOf(player)
	keep(player, ("onboarding %d %s [%s, %s]"):format(n, name, device, path))
	call("onboarding " .. name, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, name, fields(device, path))
	end)
	return true
end

--- Whether onboarding step `name` was logged for the player.
function Funnel.onboarded(player: Player, name: string): boolean
	local n = Steps.funnelNumber(name)
	local m = mask(player, F.OnboardingFlag)
	return n ~= nil and m ~= nil and Steps.has(m, n)
end

--- Logs step `name` of a one-time funnel (a Steps.Funnels name: PathS, PathR, Game2, Social)
--- once per player ever, with the device (and `extra`, a second field) as fields. False when
--- already logged or not loaded.
function Funnel.once(player: Player, funnel: string, name: string, extra: string?): boolean
	local key = F.Once[funnel]
	local step = Steps.funnelStep(funnel, name)
	if key == nil or step == nil then
		warn(
			("[8ball] Funnel: unknown one-time step %s %s"):format(tostring(funnel), tostring(name))
		)
		return false
	end
	local m = mask(player, key)
	if m == nil or Steps.has(m, step) then
		return false
	end
	if not PlayerData.setFlag(player, key, Steps.mark(m, step)) then
		return false
	end
	local device = Funnel.device(player)
	keep(
		player,
		("%s %d %s [%s%s]"):format(funnel, step, name, device, if extra then ", " .. extra else "")
	)
	call(funnel .. " " .. name, function()
		AnalyticsService:LogFunnelStepEvent(
			player,
			funnel,
			tostring(player.UserId),
			step,
			name,
			fields(device, extra)
		)
	end)
	return true
end

--- The steps of one-time funnel `funnel` logged for the player so far (saved), in order.
function Funnel.onceLogged(player: Player, funnel: string): { string }
	local key = F.Once[funnel]
	local m = if key then mask(player, key) else nil
	local out = {}
	for i, name in (if m then Steps.Funnels[funnel] else nil) or {} do
		if Steps.has(m :: number, i) then
			table.insert(out, name)
		end
	end
	return out
end

--- Logs step `name` of the Social funnel (InviteShown, Invited, FreeRewardOpened ...) once
--- per player, only for a player whose soft part began (the tutorial's icons came out, the
--- Icons moment in Flags.TutorialSeen): it follows new players, not everyone. False when not
--- logged.
function Funnel.social(player: Player, name: string): boolean
	local seen = mask(player, "TutorialSeen")
	local icons = Steps.seenBit("Icons")
	if seen == nil or icons == nil or not Steps.has(seen, icons) then
		return false
	end
	return Funnel.once(player, "Social", name)
end

--- Logs step `step` of a repeating funnel (the shop, a lucky block, the spins) for one visit
--- `session` (any short string the caller keeps for that visit). `note` (the block's kind)
--- goes in /funnel's line only.
function Funnel.step(
	player: Player,
	funnel: string,
	session: string,
	step: number,
	stepName: string,
	note: string?
)
	keep(
		player,
		("%s %d %s%s"):format(funnel, step, stepName, if note then " (" .. note .. ")" else "")
	)
	call(funnel .. " " .. stepName, function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, session, step, stepName)
	end)
end

--- Logs a custom event (LogCustomEvent) with an optional value and up to three short fields
--- (each from a small fixed set: the dashboard allows few distinct values).
function Funnel.event(
	player: Player,
	name: string,
	value: number?,
	a: string?,
	b: string?,
	c: string?
)
	keep(
		player,
		("event %s %s [%s]"):format(
			name,
			tostring(value or 1),
			table.concat({ a or "", b or "", c or "" }, ", ")
		)
	)
	call("event " .. name, function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields(a, b, c))
	end)
end

--- A first-time hint's moment (`outcome`: "Shown", "Done" or "Ignored").
function Funnel.hint(player: Player, name: string, outcome: string)
	Funnel.event(player, "Hint", 1, name, outcome, Funnel.device(player))
end

--- The tutorial was skipped at `step`.
function Funnel.skipped(player: Player, step: string)
	Funnel.event(player, "TutorialSkipped", 1, step, pathOf(player), Funnel.device(player))
end

--- The player spent `seconds` on `step` (logged when they leave it).
function Funnel.stepTime(player: Player, step: string, seconds: number)
	local value =
		math.clamp(math.floor(seconds + 0.5), 0, Config.Tutorial.Timing.StepTimeMaxSeconds)
	Funnel.event(player, "StepTime", value, step, pathOf(player), Funnel.device(player))
end

--- A guarded failure in tutorial code at `step` (`code`: a short fixed word naming where).
function Funnel.error(player: Player, step: string, code: string)
	Funnel.event(player, "TutorialError", 1, step, code)
end

--- The lines kept for the player (oldest first), for /funnel.
function Funnel.log(player: Player): { string }
	return table.clone(logs[player] or {})
end

--- Forgets what this server logged for the player (a /tutorial reset starts them over).
function Funnel.clearLog(player: Player)
	logs[player] = nil
end

---------------------------------------------------------------------------------------------
-- The repeating funnels' sessions (kept in this server only: a visit, a lucky block or a spin
-- that moves to another server is not followed there). The steps are Config.Tutorial.Funnel
-- .Shop, .Block and .Spins; other lanes' code calls these with one line each.
---------------------------------------------------------------------------------------------

local counter = 0
local shopSession: { [Player]: string } = {}
local spinSession: { [Player]: string } = {}
-- Each free lucky block followed here: its session, kind, when it is ready, and what came of
-- it.
type Drop = { session: string, kind: string, at: number, ready: boolean, cues: { string }? }
local drops: { [Player]: { Drop } } = {}

local function newSession(player: Player, kind: string): string
	counter += 1
	return ("%d-%s-%d-%d"):format(player.UserId, kind, os.time(), counter)
end

local function stepOf(steps: { string }, name: string): number?
	return table.find(steps, name)
end

--- A step of the Shop funnel ("Opened", "Viewed", "PressedBuy", "Bought"). Opened starts a
--- new visit; a later step with no visit yet (a buy from a popup) starts one too.
function Funnel.shop(player: Player, name: string)
	local step = stepOf(F.Shop, name)
	if step == nil then
		return
	end
	if name == "Opened" or shopSession[player] == nil then
		shopSession[player] = newSession(player, "shop")
	end
	Funnel.step(player, "Shop", shopSession[player], step, name)
end

--- A step of the Ability spins funnel ("OpenedAbilities", "Spun", "Equipped", "UsedInMatch").
--- Opening Abilities starts a new session; the others belong to the latest one.
function Funnel.spins(player: Player, name: string)
	local step = stepOf(F.Spins, name)
	if step == nil then
		return
	end
	if name == "OpenedAbilities" or spinSession[player] == nil then
		spinSession[player] = newSession(player, "spins")
	end
	Funnel.step(player, "AbilitySpins", spinSession[player], step, name)
end

--- A free lucky block landed (`at`: the unix time it is ready; now for one with no timer):
--- the Block funnel's "Got".
function Funnel.blockLanded(player: Player, kind: string, at: number)
	local list = drops[player] or {}
	drops[player] = list
	local drop: Drop = {
		session = newSession(player, "block"),
		kind = kind,
		at = at,
		ready = false,
		cues = nil,
	}
	table.insert(list, drop)
	Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Got") or 1, "Got", drop.kind)
end

--- A Mystery block's presses turned it from kind `from` into `to`: the oldest followed `from`
--- drop still unopened is a `to` from now on, so its open is matched.
function Funnel.blockRevealed(player: Player, from: string, to: string)
	local list: { Drop } = drops[player] or {}
	for _, drop in list do
		if drop.kind == from and drop.cues == nil then
			drop.kind = to
			return
		end
	end
end

--- A block was opened: the oldest followed block of that kind still unopened is "Opened" (and
--- "Ready" first if the watch had not seen it ready); its cues are remembered for "Equipped".
function Funnel.blockOpened(player: Player, kind: string, cues: { string }?)
	local list: { Drop } = drops[player] or {}
	for _, drop in list do
		if drop.kind == kind and drop.cues == nil then
			if not drop.ready then
				drop.ready = true -- opened before the watch saw it ready (or its timer skipped)
				Funnel.step(
					player,
					"Block",
					drop.session,
					stepOf(F.Block, "Ready") or 2,
					"Ready",
					drop.kind
				)
			end
			drop.cues = cues or {}
			Funnel.step(
				player,
				"Block",
				drop.session,
				stepOf(F.Block, "Opened") or 3,
				"Opened",
				drop.kind
			)
			return
		end
	end
end

--- A cue was equipped: the drop it came from is "Equipped" (and its following ends).
function Funnel.cueEquipped(player: Player, cueId: string)
	local list = drops[player]
	if list == nil then
		return
	end
	for i, drop in list do
		if drop.cues and table.find(drop.cues, cueId) then
			Funnel.step(
				player,
				"Block",
				drop.session,
				stepOf(F.Block, "Equipped") or 4,
				"Equipped",
				drop.kind
			)
			table.remove(list, i)
			return
		end
	end
end

-- Each second: drops whose timer has ended are "Ready".
local function watchDrops()
	local now = os.time()
	for player, list in drops do
		for _, drop in list do
			if not drop.ready and now >= drop.at then
				drop.ready = true
				Funnel.step(
					player,
					"Block",
					drop.session,
					stepOf(F.Block, "Ready") or 2,
					"Ready",
					drop.kind
				)
			end
		end
	end
end

local started = false

--- Starts the block watch and forgets players who leave (TutorialService.start calls it).
function Funnel.start()
	if started then
		return
	end
	started = true
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		since += dt
		if since >= 1 then
			since = 0
			watchDrops()
		end
	end)
	-- Every free lucky block (a win's, a reward's, an invite's) lands through PlayerData.
	PlayerData.BlocksGiven:Connect(function(player: Player, list: any)
		for _, block in (if type(list) == "table" then list else {}) :: { any } do
			if type(block) == "table" and type(block.kind) == "string" then
				local at = if type(block.readyAt) == "number" and block.readyAt > 0
					then block.readyAt
					else os.time()
				Funnel.blockLanded(player, block.kind, at)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		shopSession[player] = nil
		spinSession[player] = nil
		drops[player] = nil
		logs[player] = nil
	end)
end

return Funnel
