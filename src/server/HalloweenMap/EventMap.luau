--!strict
-- EventMap (Halloween 2026, hw-map lane): the Haunted Rooftop's switch. Follows core's
-- Event.state on the server clock (a Studio-only workspace attribute can force a state) and
-- publishes it as workspace attributes every client follows (Config.HalloweenMap
-- StateAttribute and FlipAtAttribute). While Live: the tables' event looks and decor, the
-- props and hides, the throne. Off (does nothing at all) while Config.HalloweenMap.Enabled is.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local HM = Config.HalloweenMap

local EventMap = {}

--- Start following the event (once, from Bootstrap). isArena: an arena's server (Night and the
--- table looks only).
function EventMap.start(_isArena: boolean)
	if not HM.Enabled then
		return
	end
end

return EventMap
