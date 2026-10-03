--!strict
-- Settings: each player's switches and the moments they have seen (GUI lane, designer
-- 2026-10-03, C10). The switches (Config.Settings.Defaults: sound effects, Lower
-- effects, show my country flag) live in the save's Settings map; the moments seen once
-- (Config.Settings.SeenKinds: their Skip shows from then on) in Flags as "Seen:<kind>". Both
-- change only through PlayerData (setSetting, markMomentSeen).
-- - SettingsState goes to the player on load and after each change.
-- - SettingsRequest ("Set", key, boolean) / ("Seen", kind): rate-limited; a bad request is
--   refused, never an error.
-- - The country flag: while ShowFlag is on, the player's CountryFlag attribute holds their
--   country code (LocalizationService), for the player list; off, it is cleared. Never on by
--   default.
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local PlayerData = require(script.Parent.PlayerData)

local C = Config.Settings
local FLAG_ATTRIBUTE = "CountryFlag"

local Settings = {}

local started = false
local stateRemote: RemoteEvent? = nil
-- Each player's request bucket: tokens and when it was last filled (os.clock).
local buckets: { [Player]: { tokens: number, at: number } } = {}
local countries: { [Player]: string } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if b == nil then
		b = { tokens = C.RequestBurst, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(C.RequestBurst, b.tokens + (now - b.at) * C.RequestPerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

--- The player's switches (defaults filled in) and seen kinds, from their save; nil when not
--- loaded.
function Settings.of(player: Player): ({ [string]: boolean }?, { [string]: boolean }?)
	local data = PlayerData.read(player)
	if data == nil then
		return nil, nil
	end
	local out: { [string]: boolean } = {}
	for _, key in C.Order do
		local saved = data.Settings[key]
		out[key] = if type(saved) == "boolean" then saved else C.Defaults[key]
	end
	local seen: { [string]: boolean } = {}
	for _, kind in C.SeenKinds do
		if data.Flags["Seen:" .. kind] == true then
			seen[kind] = true
		end
	end
	return out, seen
end

-- The CountryFlag attribute follows ShowFlag (the country asked of Roblox once).
local function refreshFlag(player: Player, show: boolean)
	if not show then
		player:SetAttribute(FLAG_ATTRIBUTE, nil)
		return
	end
	local code = countries[player]
	if code == nil then
		local ok, result = pcall(function(): string
			return LocalizationService:GetCountryRegionForPlayerAsync(player)
		end)
		if not ok or type(result) ~= "string" or #result ~= 2 then
			return
		end
		code = string.upper(result)
		countries[player] = code
	end
	if player.Parent == Players then
		player:SetAttribute(FLAG_ATTRIBUTE, code)
	end
end

local function send(player: Player)
	local settings, seen = Settings.of(player)
	if settings == nil or player.Parent ~= Players then
		return
	end
	local remote = stateRemote
	if remote then
		remote:FireClient(player, { settings = settings, seen = seen })
	end
	task.spawn(refreshFlag, player, settings.ShowFlag == true)
end

local function onRequest(player: Player, action: any, a: any, b: any): any
	if not allow(player) then
		return { ok = false, reason = "TooFast" }
	end
	if not PlayerData.isLoaded(player) then
		return { ok = false, reason = "NotLoaded" }
	end
	if action == "Set" then
		if type(a) ~= "string" or C.Defaults[a] == nil or type(b) ~= "boolean" then
			return { ok = false, reason = "BadRequest" }
		end
		return { ok = PlayerData.setSetting(player, a, b) }
	elseif action == "Seen" then
		if type(a) ~= "string" or not table.find(C.SeenKinds, a) then
			return { ok = false, reason = "BadRequest" }
		end
		return { ok = PlayerData.markMomentSeen(player, a) }
	end
	return { ok = false, reason = "BadRequest" }
end

--- Connects the remotes (Bootstrap calls this once).
function Settings.start()
	if started then
		return
	end
	started = true
	stateRemote = Net.get("SettingsState")
	local request: RemoteFunction = Net.get("SettingsRequest")
	request.OnServerInvoke = function(player: Player, action: any, a: any, b: any): any
		local ok, result = pcall(onRequest, player, action, a, b)
		if not ok then
			warn(
				("[8ball] Settings: a request from %d failed: %s"):format(
					player.UserId,
					tostring(result)
				)
			)
			return { ok = false, reason = "BadRequest" }
		end
		return result
	end
	PlayerData.Loaded:Connect(send)
	PlayerData.Changed:Connect(function(player: Player, op: string)
		if op == "setSetting" or op == "markMomentSeen" or op == "reset" then
			send(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
		countries[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		if PlayerData.isLoaded(player) then
			send(player)
		end
	end
end

return Settings
