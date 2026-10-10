--!strict
-- SkyBlock: the Sky Lucky Block's clock (economy v6, designer 2026-10-10; Config.SkyBlock).
-- After EverySeconds of active play in a day (the save's Daily.SkySeconds, across visits), a
-- Sky block is earned (Flags.SkyPending) and falls from the sky; at most PerDay a day
-- (Daily.SkyGiven). The clock runs only once the player has finished a real match that day
-- (NeedsMatch: Daily.Matches) and while nothing earned is still waiting to fall. Pure: the
-- caller rolls Daily over first and says how long the player was active.
local Config = require(script.Parent.Parent.Config)

local C = Config.SkyBlock

local SkyBlock = {}

SkyBlock.PendingFlag = "SkyPending"

export type View = {
	left: number, -- seconds of active play to the next one (0 when none is coming today)
	today: number, -- earned today
	perDay: number,
	needsMatch: boolean, -- the clock waits for today's first finished real match
	pending: boolean, -- one is earned and waits to fall (or to be picked up)
}

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

--- Whether the clock runs now (before the activity check).
function SkyBlock.running(daily: any, flags: any): boolean
	return flags[SkyBlock.PendingFlag] ~= true
		and whole(daily.SkyGiven) < C.PerDay
		and (not C.NeedsMatch or whole(daily.Matches) > 0)
end

--- Adds `seconds` of active play: true when that earned a Sky block (Daily and Flags changed).
function SkyBlock.add(daily: any, flags: any, seconds: number): boolean
	if not SkyBlock.running(daily, flags) or whole(seconds) <= 0 then
		return false
	end
	daily.SkySeconds = whole(daily.SkySeconds) + whole(seconds)
	if daily.SkySeconds < C.EverySeconds then
		return false
	end
	daily.SkySeconds = 0
	daily.SkyGiven = whole(daily.SkyGiven) + 1
	flags[SkyBlock.PendingFlag] = true
	return true
end

--- What the banner shows.
function SkyBlock.view(daily: any, flags: any): View
	local today = whole(daily.SkyGiven)
	local pending = flags[SkyBlock.PendingFlag] == true
	local more = today < C.PerDay and not pending
	return {
		left = if more then math.max(0, C.EverySeconds - whole(daily.SkySeconds)) else 0,
		today = today,
		perDay = C.PerDay,
		needsMatch = more and C.NeedsMatch and whole(daily.Matches) == 0,
		pending = pending,
	}
end

return SkyBlock
