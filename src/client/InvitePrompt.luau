--!strict
-- InvitePrompt: Roblox's invite prompt carrying our launch data (the invite rewards,
-- Progression/Social.launchData), for the hub's Invite corner (HubCorners) and the Free Reward
-- menu's invite card (FreeSocial).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SocialRules = require(Shared:WaitForChild("Progression"):WaitForChild("Social"))

local InvitePrompt = {}

--- Show Roblox's invite prompt (in its own thread); `failed()` runs when Roblox will not show
--- it for this player here.
function InvitePrompt.show(failed: () -> ())
	local player = Players.LocalPlayer
	if not player then
		return
	end
	task.spawn(function()
		local okCan, can = pcall(function(): boolean
			return SocialService:CanSendGameInviteAsync(player)
		end)
		if not okCan or not can then
			failed()
			return
		end
		local options = Instance.new("ExperienceInviteOptions")
		options.LaunchData = SocialRules.launchData(player.UserId)
		local ok = pcall(function()
			SocialService:PromptGameInvite(player, options)
		end)
		if not ok then
			failed()
		end
	end)
end

return InvitePrompt
