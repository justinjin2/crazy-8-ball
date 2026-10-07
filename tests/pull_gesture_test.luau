--!strict
-- PullGesture (src/shared/PullGesture.luau): a finger on the power bar. A wobble inside the
-- dead zone, a sideways swipe or a very short press never shoots; a deliberate pull just past
-- the dead zone is the softest shot, and full power is where it always was. A mouse is as before.

local H = require("./harness")

local function setup()
	return H.require("PullGesture"), H.require("Config")
end

local TRAVEL = 300 -- pixels for full power

return {
	["a wobble inside the dead zone stays at 0 and cancels"] = function()
		local G, C = setup()
		local T = C.Input.TouchPull
		local g = G.new(true, 0)
		H.near(G.move(g, 2, T.LockPx, TRAVEL), 0, 1e-12, "decided a pull, still in the dead zone")
		H.near(G.move(g, 3, T.DeadZonePx, TRAVEL), 0, 1e-12, "at the dead zone's edge")
		H.expect(G.mayShoot(g, 1), "a held press may shoot")
		H.expect(g.pull < C.Input.MinPowerToShoot, "but a 0 pull cancels in Input")
	end,

	["just past the dead zone is the softest shot, the end is full power"] = function()
		local G, C = setup()
		local T = C.Input.TouchPull
		local g = G.new(true, 0)
		local soft = G.move(g, 0, T.DeadZonePx + 1, TRAVEL)
		H.expect(soft >= C.Input.MinPowerToShoot, "shoots")
		H.expect(soft < 0.06, "and softly: " .. soft)
		H.near(G.move(g, 0, TRAVEL, TRAVEL), 1, 1e-12, "full power at the same spot as before")
		H.near(G.move(g, 0, TRAVEL * 2, TRAVEL), 1, 1e-12, "and no further")
		H.expect(G.mayShoot(g, 0.5), "a real pull shoots")
	end,

	["a sideways swipe across the bar never pulls, even if it then goes down"] = function()
		local G, C = setup()
		local T = C.Input.TouchPull
		local g = G.new(true, 0)
		H.near(G.move(g, T.LockPx + 4, 3, TRAVEL), 0, 1e-12, "sideways first")
		H.near(G.move(g, T.LockPx + 4, 120, TRAVEL), 0, 1e-12, "then down: still nothing")
		H.expect(not G.mayShoot(g, 1), "never shoots")
	end,

	["a slightly slanted pull is still a pull"] = function()
		local G, C = setup()
		local T = C.Input.TouchPull
		local g = G.new(true, 0)
		G.move(g, 6, T.LockPx, TRAVEL)
		H.expect(G.move(g, 20, 150, TRAVEL) > 0.3, "pulls")
		H.expect(G.mayShoot(g, 1), "and shoots")
	end,

	["a very short press never shoots"] = function()
		local G, C = setup()
		local g = G.new(true, 10)
		H.expect(G.move(g, 0, 200, TRAVEL) > 0.5, "a quick flick down the bar")
		H.expect(not G.mayShoot(g, 10 + C.Input.TouchPull.MinHoldSeconds * 0.5), "too quick")
		H.expect(G.mayShoot(g, 10 + C.Input.TouchPull.MinHoldSeconds), "held long enough")
	end,

	["a mouse pulls exactly as before"] = function()
		local G = setup()
		local g = G.new(false, 0)
		H.near(G.move(g, 50, 30, TRAVEL), 0.1, 1e-12, "no dead zone, sideways ignored")
		H.near(G.move(g, 0, -10, TRAVEL), 0, 1e-12, "never below 0")
		H.expect(G.mayShoot(g, 0), "no hold time")
	end,
}
