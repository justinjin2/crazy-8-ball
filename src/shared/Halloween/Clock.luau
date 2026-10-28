--!strict
-- Clock: the Halloween event's `now` for Halloween/Event, on the server and the client. Every
-- lane gates the event on Event.*(Clock.now()).
--
-- Test time: the workspace attribute HwTimeOffset (seconds, set by the server: /hw time) is
-- added only in Studio and on the test place (Config.Save.TestPlace.GameId); the live game
-- ignores it, so nothing a player does can move the event. Not pure (reads the workspace):
-- only services and the client require it, never Physics, Rules or a Lune test.
local Config = require(script.Parent.Parent.Config)

local Clock = {}

Clock.OffsetAttribute = "HwTimeOffset"

local allowed: boolean? = nil

-- Whether test time counts in this server or client (Studio or the test place).
function Clock.testAllowed(): boolean
	if allowed == nil then
		local RunService = game:GetService("RunService")
		allowed = RunService:IsStudio() or game.GameId == Config.Save.TestPlace.GameId
	end
	return allowed :: boolean
end

-- The test offset in whole seconds (0 in the live game, or when none is set).
function Clock.offset(): number
	if not Clock.testAllowed() then
		return 0
	end
	local value = workspace:GetAttribute(Clock.OffsetAttribute)
	if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
		return 0
	end
	return math.floor(value)
end

-- The shared clock (server and clients agree): what every screen and gate reads.
function Clock.now(): number
	return workspace:GetServerTimeNow() + Clock.offset()
end

-- Whole unix seconds for the server's saves and caps (cooldowns, the pickup hour).
function Clock.serverNow(): number
	return os.time() + Clock.offset()
end

-- Server only: sets the test offset (whole seconds; 0 = the real clock).
function Clock.setOffset(seconds: number)
	if Clock.testAllowed() then
		workspace:SetAttribute(Clock.OffsetAttribute, math.floor(seconds))
	end
end

-- Server only, at boot: in Studio and on the test place, when the real clock is before the
-- event, moves it to Test.LiveAfter seconds past StartsAt, so a playtest before 19:00 sees the
-- event Live (Config.Halloween.Test.BootLive). A set offset is left alone.
function Clock.boot()
	local C = Config.Halloween
	if not Clock.testAllowed() or C.Test.BootLive ~= true then
		return
	end
	if workspace:GetAttribute(Clock.OffsetAttribute) ~= nil then
		return
	end
	local real = os.time()
	Clock.setOffset(if real < C.StartsAt then C.StartsAt + C.Test.LiveAfter - real else 0)
end

return Clock
