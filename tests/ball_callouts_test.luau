--!strict
-- BallCallouts (src/shared/BallCallouts.luau): when the balls pulse. The reveal fires once
-- when the groups are decided; a team's last ball is called once per game, never again after a
-- miss, never for someone arriving mid-game, and never in solo.

local H = require("./harness")

local function eq(actual: any, expected: any, message: string)
	H.expect(
		actual == expected,
		("%s: got %s, want %s"):format(message, tostring(actual), tostring(expected))
	)
end

local function setup()
	return H.require("BallCallouts")
end

-- Every ball in `ids` shown down.
local function downOf(ids: { number }): { [number]: boolean }
	local down = {}
	for _, id in ids do
		down[id] = true
	end
	return down
end

local GROUPS = { [1] = "solids", [2] = "stripes" }

return {
	["the reveal fires once, when the groups become known"] = function()
		local M = setup()
		local s = M.new()
		eq(#M.observe(s, "1:1", nil, {}, false), 0, "the break: nothing")
		eq(#M.observe(s, "1:1", nil, downOf({ 3 }), false), 0, "a ball down, still open")
		local out = M.observe(s, "1:1", GROUPS, downOf({ 3, 4 }), false)
		eq(#out, 1, "one callout")
		eq(out[1].kind, "Reveal", "the reveal")
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 3, 4, 10 }), false), 0, "only once")
	end,

	["arriving with the groups already known reveals nothing"] = function()
		local M = setup()
		local s = M.new()
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2 }), false), 0, "arrival")
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 9 }), false), 0, "and after")
	end,

	["a team's last ball is called once and not again after a miss"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", nil, {}, false)
		M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5 }), false)
		local out = M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6 }), false)
		eq(#out, 1, "one callout")
		eq(out[1].kind, "LastBall", "the last ball")
		local call = out[1] :: any
		eq(call.team, 1, "the solids team")
		eq(call.ball, 7, "its last solid")
		-- They miss; the stripes shoot, then the solids are back at the table.
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6, 12 }), false), 0, "a miss")
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6, 12 }), false), 0, "back")
	end,

	["the opponent sinking your ball can leave you one, and that is called too"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5 }), false)
		local out = M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 9, 6 }), false)
		eq(#out, 1, "called")
		eq((out[1] :: any).team, 1, "for the solids")
	end,

	["two down at once, straight from two to none, calls nothing"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", GROUPS, downOf({ 9, 10, 11, 12, 13 }), false)
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 9, 10, 11, 12, 13, 14, 15 }), false), 0, "none")
	end,

	["both teams get their own call"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 9, 10, 11, 12, 13 }), false)
		local a =
			M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13 }), false)
		eq(#a, 1, "the solids")
		local b =
			M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14 }), false)
		eq(#b, 1, "the stripes")
		eq((b[1] :: any).team, 2, "team 2")
		eq((b[1] :: any).ball, 15, "its last stripe")
	end,

	["arriving with a team on its last ball calls nothing"] = function()
		local M = setup()
		local s = M.new()
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6 }), false), 0, "arrival")
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6, 9 }), false), 0, "and after")
	end,

	["a new game starts the calls afresh"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5 }), false)
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6 }), false), 1, "game 1")
		M.observe(s, "1:2", nil, {}, false)
		eq(#M.observe(s, "1:2", GROUPS, {}, false), 1, "game 2 reveals")
		M.observe(s, "1:2", GROUPS, downOf({ 1, 2, 3, 4, 5 }), false)
		eq(#M.observe(s, "1:2", GROUPS, downOf({ 1, 2, 3, 4, 5, 6 }), false), 1, "and calls")
	end,

	["solo has no opponent to warn"] = function()
		local M = setup()
		local s = M.new()
		M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5 }), true)
		eq(#M.observe(s, "1:1", GROUPS, downOf({ 1, 2, 3, 4, 5, 6 }), true), 0, "none")
	end,
}
