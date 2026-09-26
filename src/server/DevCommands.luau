--!strict
-- DevCommands: developer chat commands, checked here on the server (Config.Debug.Commands).
-- /day and /sunset send the day/sunset cycle toward that state for the whole server, through
-- its one-minute fade (LightCycle.offsetToward): the offset goes on a workspace attribute every
-- client's DayCycle reads, and the cycle runs on from there. Anyone not allowed (not in Studio, not listed, not the group's owner) gets
-- nothing, so no player can change everyone's sky.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextChatService = game:GetService("TextChatService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightCycle = require(Shared:WaitForChild("LightCycle"))

local D = Config.Debug.Commands
local C = Config.Lighting.Cycle

local DevCommands = {}

--- Sends the cycle toward "Day" or "Sunset" (the commands' work; Studio tests call it too).
function DevCommands.toward(hold: string)
	local t = workspace:GetServerTimeNow() * C.Speed
	local offset = workspace:GetAttribute(C.OffsetAttribute)
	local now = if type(offset) == "number" then offset else 0
	workspace:SetAttribute(C.OffsetAttribute, LightCycle.offsetToward(t, now, C, hold))
end

local function allowed(userId: number): boolean
	if RunService:IsStudio() or table.find(D.UserIds, userId) ~= nil then
		return true
	end
	if game.CreatorType ~= Enum.CreatorType.Group then
		return userId == game.CreatorId
	end
	local player = Players:GetPlayerByUserId(userId)
	local ok, rank = pcall(function()
		return if player then player:GetRankInGroup(game.CreatorId) else 0
	end)
	return ok and rank >= D.GroupRank
end

local function command(name: string, alias: string, run: () -> ())
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "Dev" .. name
	cmd.PrimaryAlias = alias
	cmd.AutocompleteVisible = false -- not offered to players
	cmd.Triggered:Connect(function(source: TextSource)
		if allowed(source.UserId) then
			run()
		end
	end)
	cmd.Parent = TextChatService
end

function DevCommands.start()
	for _, hold in { "Day", "Sunset" } do
		command(hold, D[hold], function()
			DevCommands.toward(hold)
		end)
	end
end

return DevCommands
