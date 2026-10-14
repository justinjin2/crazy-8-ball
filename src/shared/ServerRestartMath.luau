--!strict
-- The server refresh's decisions (Config.ServerRestart; src/server/ServerRestart.luau): when a
-- lobby server moves everyone to a fresh one, and when the hop sends its group on. Plain
-- functions of numbers, so they are tested in Lune. No Instances.
local ServerRestartMath = {}

local HOUR = 3600

--- What a public lobby server `uptime` seconds old does now: "wait", or "go" (start the
--- countdown). Due from AfterHours at the first moment no real player is mid-game
--- (`gameOn` false); at LatestHours whatever is going on. Always "wait" when switched off.
function ServerRestartMath.decide(uptime: number, gameOn: boolean, cfg: any): string
	if cfg.Enabled ~= true then
		return "wait"
	end
	if uptime >= cfg.LatestHours * HOUR then
		return "go"
	end
	if uptime >= cfg.AfterHours * HOUR and not gameOn then
		return "go"
	end
	return "wait"
end

--- Whether the hop sends its group on now: everyone on its list (`listed` user ids) has
--- arrived with their save open (`ready`: user id -> true), or HopWaitSeconds have passed
--- (`waited`) with at least one of them ready.
function ServerRestartMath.hopReady(
	listed: { number },
	ready: { [number]: boolean },
	waited: number,
	cfg: any
): boolean
	local count, all = 0, true
	for _, id in listed do
		if ready[id] then
			count += 1
		else
			all = false
		end
	end
	if count == 0 then
		return false
	end
	return all or waited >= cfg.HopWaitSeconds
end

return ServerRestartMath
