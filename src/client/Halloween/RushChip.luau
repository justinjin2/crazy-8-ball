--!strict
-- RushChip: the Candy Rush chip's content for the GUI lane's shell (hw-core; R1.10). The shell
-- (above the boost pill) polls RushChip.content() once a second through a guarded require and
-- places and styles the chip itself:
--   { text = "2x CANDY 8:12", endsAt = <unix>, kind = "Rush" } in a Rush (the player's own
--   10 minutes, then every 45, while the event is Live), { text = "2x CANDY 9:12:44", kind = "Double" } on Oct 31,
--   nil otherwise and for a player the event may not show to yet (HwOn: the tutorial not over).
-- The time is always the event's (Halloween/Clock, so Studio's test offset counts); the shell's
-- own `now`, if it passes one, is ignored.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local State = require(script.Parent.State)

local RushChip = {}

export type Content = Event.Chip

function RushChip.content(_now: number?): Content?
	if not State.on() then
		return nil
	end
	-- the personal Rush's anchor (the server's HwRushAt, Config Rush.Personal)
	local at = Players.LocalPlayer:GetAttribute("HwRushAt")
	return Event.rushChip(Clock.now(), if type(at) == "number" then at else nil)
end

return RushChip
