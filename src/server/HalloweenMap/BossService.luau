--!strict
-- BossService (Halloween 2026, hw-map lane): the Pumpkin King's challenge. A player at his
-- throne asks (Net KingChallenge); the server checks them, finds a free lobby table and seats
-- them against the King (a "Pc" bot, BotService.playBoss), and on a win calls core's
-- CandyService.bossWon. Off (does nothing at all) while Config.HalloweenMap.Enabled or
-- Boss.Enabled is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HM = Config.HalloweenMap

local BossService = {}

--- Start listening for challenges (once, from Bootstrap). isLobby: false in an arena.
function BossService.start(isLobby: boolean)
	if not (HM.Enabled and HM.Boss.Enabled and isLobby) then
		return
	end
end

return BossService
