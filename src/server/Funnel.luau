--!strict
-- Funnel: the one place the game's funnels go to Roblox's analytics (AnalyticsService; the
-- Creator Dashboard's Funnels and Custom Events pages). Server side only, never trusted from a
-- client without a check by the caller (docs/prompts/TUTORIAL_PROMPT.md step 9).
--
-- - The onboarding funnel (LogOnboardingFunnelStepEvent): the 22 steps of Tutorial/Steps
--   .Funnel, each logged once per player ever (a bit in the save's Flags.Funnel), and only for
--   new players: step 1 is logged for a brand-new save (TutorialService), and no later step
--   is logged for a player without it.
-- - One-time funnels (LogFunnelStepEvent with the player's own session id): the tutorial's
--   exit funnel, each step once per player (a bit in its own Flags key).
-- - Repeating funnels (LogFunnelStepEvent with a session id per visit): the shop, a free lucky
--   block's life, the ability spins.
-- - Side events (LogCustomEvent): moments not everyone sees (ball in hand, the bot's scratch,
--   a lost game 2).
--
-- Every call is wrapped in pcall: analytics never breaks the game. In Studio each one prints
-- when Config.Tutorial.Funnel.Print is on.
local AnalyticsService = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Steps = require(Shared.Tutorial.Steps)
local PlayerData = require(script.Parent.PlayerData)

local F = Config.Tutorial.Funnel

local Funnel = {}

local function say(text: string)
	if F.Print and RunService:IsStudio() then
		print("[8ball] Funnel: " .. text)
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

-- The mask kept under `key` in the save's Flags (0 when not loaded or not set).
local function mask(player: Player, key: string): number?
	local data = PlayerData.read(player)
	if data == nil then
		return nil
	end
	local value = data.Flags[key]
	return if type(value) == "number" then value else 0
end

--- Logs onboarding funnel step `name` (a Steps.Funnel name) once per player ever. Steps a
--- player skips are simply never logged. False when already logged or not loaded.
function Funnel.onboarding(player: Player, name: string): boolean
	local n = Steps.funnelNumber(name)
	if n == nil then
		warn("[8ball] Funnel: unknown onboarding step " .. tostring(name))
		return false
	end
	local m = mask(player, F.OnboardingFlag)
	-- Only players whose first step was logged (a brand-new save): nobody joins it halfway.
	if m == nil or Steps.funnelHas(m, n) or (n > 1 and not Steps.funnelHas(m, 1)) then
		return false
	end
	if not PlayerData.setFlag(player, F.OnboardingFlag, Steps.funnelMark(m, n)) then
		return false
	end
	say(("onboarding %d %s (%s)"):format(n, name, player.Name))
	call("onboarding " .. name, function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, n, name)
	end)
	return true
end

--- Logs step `step` (1-based) of a one-time funnel `funnel` (a Config.Tutorial.Funnel.Once
--- row), once per player ever. False when already logged or not loaded.
function Funnel.once(player: Player, funnel: string, step: number, stepName: string): boolean
	local key = F.Once[funnel]
	if key == nil then
		warn("[8ball] Funnel: unknown one-time funnel " .. tostring(funnel))
		return false
	end
	local m = mask(player, key)
	if m == nil or Steps.funnelHas(m, step) then
		return false
	end
	if not PlayerData.setFlag(player, key, Steps.funnelMark(m, step)) then
		return false
	end
	say(("%s %d %s (%s)"):format(funnel, step, stepName, player.Name))
	call(funnel .. " " .. stepName, function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, tostring(player.UserId), step, stepName)
	end)
	return true
end

--- Logs step `step` of a repeating funnel (the shop, a lucky block, the spins) for one visit
--- `session` (any short string the caller keeps for that visit).
function Funnel.step(
	player: Player,
	funnel: string,
	session: string,
	step: number,
	stepName: string
)
	say(("%s %d %s [%s] (%s)"):format(funnel, step, stepName, session, player.Name))
	call(funnel .. " " .. stepName, function()
		AnalyticsService:LogFunnelStepEvent(player, funnel, session, step, stepName)
	end)
end

--- Logs a side event (LogCustomEvent) with an optional value and up to three short fields.
function Funnel.event(
	player: Player,
	name: string,
	value: number?,
	a: string?,
	b: string?,
	c: string?
)
	say(("event %s %s (%s)"):format(name, tostring(value or 1), player.Name))
	call("event " .. name, function()
		local fields: { [any]: string } = {}
		if a then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = a
		end
		if b then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = b
		end
		if c then
			fields[Enum.AnalyticsCustomFieldKeys.CustomField03.Name] = c
		end
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields)
	end)
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
	Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Got") or 1, "Got")
end

--- A block was opened: the oldest followed block of that kind still unopened is "Opened" (and
--- "Ready" first if the watch had not seen it ready); its cues are remembered for "Equipped".
function Funnel.blockOpened(player: Player, kind: string, cues: { string }?)
	local list: { Drop } = drops[player] or {}
	for _, drop in list do
		if drop.kind == kind and drop.cues == nil then
			if not drop.ready then
				drop.ready = true -- opened before the watch saw it ready (or its timer skipped)
				Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Ready") or 2, "Ready")
			end
			drop.cues = cues or {}
			Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Opened") or 3, "Opened")
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
			Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Equipped") or 4, "Equipped")
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
				Funnel.step(player, "Block", drop.session, stepOf(F.Block, "Ready") or 2, "Ready")
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
	game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
		shopSession[player] = nil
		spinSession[player] = nil
		drops[player] = nil
	end)
end

return Funnel
