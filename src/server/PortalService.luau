--!strict
-- PortalService: the Solo and Practice portals (designer, 2026-10-10; Config.Portals, the
-- client's Portals). A player standing on a portal's pad asks on the Portal remote ("Solo" or
-- "Pc"); the server checks it all (a public lobby, the tutorial over and a match won, not at a
-- table or searching, the save open, standing near that pad, not too often), then makes a
-- one-table arena of their own (GlobalQueue.botMatch with `practice` on its list) and sends
-- them there (GlobalQueue.teleport). The arena starts their game the moment they arrive
-- (ArenaService). In Studio the teleport cannot happen: the screen says so.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local GlobalQueue = require(script.Parent.GlobalQueue)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.TableService)
local TutorialService = require(script.Parent.TutorialService)

local P = Config.Portals

local PortalService = {}

local lastTry: { [Player]: number } = {}
local going: { [Player]: boolean } = {}
local started = false

local function portalOf(mode: string): any?
	for _, row in P.List do
		if row.Mode == mode then
			return row
		end
	end
	return nil
end

-- The pad's centre on the floor (world X, Z).
function PortalService.padCentre(row: any): (number, number)
	return row.X, row.Z - P.PadAheadStuds
end

local function allowed(player: Player, row: any): boolean
	if
		game.PrivateServerId ~= ""
		or workspace:GetAttribute(Config.Arena.ModeAttribute) == "Arena"
	then
		return false
	end
	if not PlayerData.isLoaded(player) or PlayerData.isHandedOff(player) then
		return false
	end
	if TutorialService.guided(player) then
		return false
	end
	local progress = PlayerData.progress(player)
	if progress == nil or (progress.Wins or 0) < 1 then
		return false
	end
	if Tables.tableOf(player) ~= nil then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		return false
	end
	local x, z = PortalService.padCentre(row)
	local d = Vector2.new(root.Position.X - x, root.Position.Z - z).Magnitude
	return d <= P.PadRadius + P.ServerSlackStuds
end

local function send(player: Player, mode: string)
	local row = portalOf(mode)
	if row == nil or going[player] then
		return
	end
	local now = os.clock()
	if lastTry[player] and now - lastTry[player] < P.CooldownSeconds then
		return
	end
	lastTry[player] = now
	if not allowed(player, row) then
		return
	end
	going[player] = true
	GlobalQueue.notify({ player }, { kind = "Portal" })
	local record = {
		mode = 1,
		teams = { { player.UserId }, {} },
		homes = { [tostring(player.UserId)] = game.JobId },
		ults = true,
		practice = mode,
	}
	local match = GlobalQueue.botMatch(record, 1)
	if match == nil then
		going[player] = nil
		GlobalQueue.notify({ player }, { kind = "Failed", reason = "Teleport" })
		return
	end
	GlobalQueue.teleport({ player }, match, function(p: Player, why: string)
		going[p] = nil
		GlobalQueue.notify({ p }, { kind = "Failed", reason = why })
	end)
end

function PortalService.start()
	if started then
		return
	end
	started = true
	Net.get("Portal").OnServerEvent:Connect(function(player: Player, mode: any)
		if type(mode) == "string" then
			send(player, mode)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		lastTry[player] = nil
		going[player] = nil
	end)
end

return PortalService
