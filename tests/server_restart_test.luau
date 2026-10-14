--!strict
-- The server refresh's decisions (ServerRestartMath; Config.ServerRestart, designer
-- 2026-10-14): a lobby server moves everyone to a fresh one from AfterHours at a quiet moment,
-- at LatestHours whatever is going on; the hop sends its group on once everyone came.

local H = require("./harness")

local Config = H.require("Config")
local M = H.require("ServerRestartMath")

local HOUR = 3600

local function cfg(extra: { [string]: any }?): any
	local c = table.clone(Config.ServerRestart)
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

return {
	["the refresh is on, 5 to 6 hours (designer, 2026-10-14)"] = function()
		local R = Config.ServerRestart
		H.expect(R.Enabled == true, "on")
		H.expect(R.AfterHours == 5 and R.LatestHours == 6, "5 to 6 hours")
		H.expect(R.CountdownSeconds > 0 and R.HopWaitSeconds > 0, "times")
	end,

	["a young server waits, quiet or not"] = function()
		H.expect(M.decide(0, false, cfg()) == "wait", "new")
		H.expect(M.decide(4.99 * HOUR, false, cfg()) == "wait", "just before 5 h")
		H.expect(M.decide(4.99 * HOUR, true, cfg()) == "wait", "in a game")
	end,

	["from 5 hours it goes at the first quiet moment"] = function()
		H.expect(M.decide(5 * HOUR, true, cfg()) == "wait", "a game is on")
		H.expect(M.decide(5.5 * HOUR, true, cfg()) == "wait", "still on")
		H.expect(M.decide(5 * HOUR, false, cfg()) == "go", "quiet")
	end,

	["at 6 hours it goes whatever is going on"] = function()
		H.expect(M.decide(6 * HOUR, true, cfg()) == "go", "a game is on")
		H.expect(M.decide(9 * HOUR, true, cfg()) == "go", "long past")
	end,

	["switched off, a server never refreshes"] = function()
		local off = cfg({ Enabled = false })
		H.expect(M.decide(5 * HOUR, false, off) == "wait", "quiet")
		H.expect(M.decide(24 * HOUR, true, off) == "wait", "a day old")
	end,

	["the hop goes once everyone came, or after its wait with someone"] = function()
		local c = cfg()
		local listed = { 1, 2, 3 }
		H.expect(not M.hopReady(listed, {}, 0, c), "nobody yet")
		H.expect(not M.hopReady(listed, {}, c.HopWaitSeconds + 1, c), "nobody, ever")
		H.expect(not M.hopReady(listed, { [1] = true, [2] = true }, 1, c), "one to come")
		H.expect(M.hopReady(listed, { [1] = true, [2] = true, [3] = true }, 1, c), "all in")
		H.expect(M.hopReady(listed, { [1] = true }, c.HopWaitSeconds, c), "waited long enough")
		H.expect(M.hopReady({ 7 }, { [7] = true }, 0, c), "a group of one")
	end,
}
