--!strict
-- Funnel: the one place the game's funnels go to Roblox's analytics (AnalyticsService; the
-- Creator Dashboard's Funnels and Custom Events pages). Server side only, never trusted from a
-- client without a check by the caller (docs/prompts/TUTORIAL_PROMPT.md step 9).
--
-- - The onboarding funnel (LogOnboardingFunnelStepEvent): the 22 steps of Tutorial/Steps
--   .Funnel, each logged once per player ever (a bit in the save's Flags.Funnel).
-- - One-time funnels (LogFunnelStepEvent with the player's own session id): the tutorial's
--   exit funnel, each step once per player (a bit in its own Flags key).
-- - Repeating funnels (LogFunnelStepEvent with a session id per visit): the shop, a Case Drop's
--   life, the ability spins.
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
	if m == nil or Steps.funnelHas(m, n) then
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

--- Logs step `step` of a repeating funnel (the shop, a Case Drop, the spins) for one visit
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

return Funnel
