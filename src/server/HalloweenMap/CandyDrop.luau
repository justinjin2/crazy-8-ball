--!strict
-- CandyDrop (Halloween 2026, hw-map lane): candy pieces pop up on the roof near active players
-- while the event is Live (a copy of MoneyRain); walking over one asks core's
-- CandyService.pickup, which owns the Candy and the hour cap. Off (does nothing at all) while
-- Config.HalloweenMap.Enabled or Candy.Enabled is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HM = Config.HalloweenMap

local CandyDrop = {}

--- Start the drops (once, from Bootstrap). isLobby: false in an arena.
function CandyDrop.start(isLobby: boolean)
	if not (HM.Enabled and HM.Candy.Enabled and isLobby) then
		return
	end
end

return CandyDrop
