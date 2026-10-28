--!strict
-- MapClient (Halloween 2026, hw-map lane): this client's side of the Haunted Rooftop. Follows
-- only the server's workspace attributes (Config.HalloweenMap StateAttribute and
-- FlipAtAttribute): the Night light through DayCycle, the Pumpkin King's prompt, the candy's
-- spin and +1, the King's candy explosion. Off (does nothing at all) while
-- Config.HalloweenMap.Enabled is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HM = Config.HalloweenMap

local MapClient = {}

--- Start following the event (once, from Main). dayCycle: the map's DayCycle, handed the event
--- light while Live.
function MapClient.start(_dayCycle: any)
	if not HM.Enabled then
		return
	end
end

return MapClient
