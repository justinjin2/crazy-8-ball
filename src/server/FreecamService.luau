--!strict
-- FreecamService: the lobby freecam's server half (designer, 2026-10-25: a free camera to film
-- friends for clips; the client flies the camera, src/client/Freecam.luau).
-- - FreecamRequest ("Start" | "Stop", how): rate-limited. A start is refused unless the
--   feature is on (Config.Freecam.Enabled), this is a lobby, the save is loaded, the player is
--   not seated, not searching for a match and not in the guided tutorial.
-- - While it is on the player's Freecam attribute is true, and every way into a match refuses
--   them (the attribute Config.Freecam.Attribute, checked by TableService's pad poll, answerRequest, placeOnPad
--   and startSearch, SoloSearch.begin, LocalSearch, PortalService and GlobalQueue.teleport):
--   freecam is for filming friends, never for playing.
-- - Analytics (Funnel): the custom event Freecam, "Start" with the device; "End" with the
--   seconds it lasted (capped, Config.Freecam.EndMaxSeconds) and how it ended ("Exit",
--   "Settings", "Pad", "Auto", "Left"); "Refused" with why.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.TableService)

local F = Config.Freecam
local ATTRIBUTE = F.Attribute
-- How a client may say it ended (anything else is logged as "Auto").
local ENDS = { Exit = true, Settings = true, Pad = true, Auto = true }

local FreecamService = {}

local started = false
-- When each player's freecam started (os.clock), while it is on.
local since: { [Player]: number } = {}
-- Each player's request bucket: tokens and when it was last filled (os.clock).
local buckets: { [Player]: { tokens: number, at: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if b == nil then
		b = { tokens = F.RequestBurst, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(F.RequestBurst, b.tokens + (now - b.at) * F.RequestPerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- Why `player` may not start it now, or nil when they may.
local function refusal(player: Player): string?
	if not F.Enabled then
		return "Off"
	end
	if not PlayerData.isLoaded(player) or player:GetAttribute("DataLoaded") ~= true then
		return "Busy"
	end
	if player:GetAttribute("TutorialActive") ~= false then
		return "Tutorial"
	end
	if Tables.tableOf(player) ~= nil then
		return "Seated"
	end
	if player:GetAttribute("SoloSearchAt") ~= nil then
		return "Searching"
	end
	return nil
end

local function stop(player: Player, how: string)
	local at = since[player]
	since[player] = nil
	if player:GetAttribute(ATTRIBUTE) ~= nil then
		player:SetAttribute(ATTRIBUTE, nil)
	end
	if at then
		local seconds = math.clamp(math.floor(os.clock() - at + 0.5), 0, F.EndMaxSeconds)
		Funnel.event(player, "Freecam", seconds, "End", how, Funnel.device(player))
	end
end

local function onRequest(player: Player, action: any, how: any): any
	if not allow(player) then
		return { ok = false, reason = "Busy" }
	end
	if action == "Start" then
		if since[player] then
			return { ok = true }
		end
		local why = refusal(player)
		if why then
			Funnel.event(player, "Freecam", 1, "Refused", why, Funnel.device(player))
			return { ok = false, reason = why }
		end
		since[player] = os.clock()
		player:SetAttribute(ATTRIBUTE, true)
		Funnel.event(player, "Freecam", 1, "Start", Funnel.device(player))
		return { ok = true }
	elseif action == "Stop" then
		stop(player, if type(how) == "string" and ENDS[how] then how else "Auto")
		return { ok = true }
	end
	return { ok = false, reason = "Busy" }
end

--- Connects the remote (Bootstrap calls this once, in a lobby only). In an arena every start
--- is refused as "Lobby".
function FreecamService.start(lobby: boolean)
	if started then
		return
	end
	started = true
	local request: RemoteFunction = Net.get("FreecamRequest")
	request.OnServerInvoke = function(player: Player, action: any, how: any): any
		if not lobby then
			return { ok = false, reason = "Lobby" }
		end
		local ok, result = pcall(onRequest, player, action, how)
		if not ok then
			warn(
				("[8ball] Freecam: a request from %d failed: %s"):format(
					player.UserId,
					tostring(result)
				)
			)
			return { ok = false, reason = "Busy" }
		end
		return result
	end
	local function watch(player: Player)
		-- A new body (a death, a respawn) ends it: the client starts over on its own camera.
		player.CharacterRemoving:Connect(function()
			if since[player] then
				stop(player, "Auto")
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		if since[player] then
			stop(player, "Left")
		end
		buckets[player] = nil
	end)
end

return FreecamService
