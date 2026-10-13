--!strict
-- ShotFinder.eightPocket: the pocket a controller's call for the 8 starts lit on (designer,
-- 2026-10-12): the 8's easiest pot from the cue ball, else the pocket nearest the 8.

local H = require("./harness")
local V = require("./ult_value")

local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Finder = H.require("Bots.ShotFinder")

local geometry = TableGeometry.build({ pocketsOpen = true })

-- Balls from { id, x, y } rows (table inches, the middle at 0, 0).
local function balls(rows: { { number } }): { any }
	return Ball.cloneList(V.customState(rows, { "solids", "stripes" }).balls)
end

-- The pocket whose aim point is nearest (x, y): the one the 8 is lined up with.
local function pocketAt(x: number, y: number): number
	return Finder.nearestPocket(geometry, x, y)
end

local HL, HW = geometry.halfLength, geometry.halfWidth

return {
	["a straight-in 8 lights its own pocket, and the cue ball's side changes it"] = function()
		-- The 8 in the middle of the right half, the cue ball up-left of it: straight into the
		-- bottom-right corner (45 degrees from the 8 to it on this table).
		local x = HL / 2
		local up = Finder.eightPocket(geometry, balls({ { 0, x - 15, 15 }, { 8, x, 0 } }))
		H.expect(up == pocketAt(HL, -HW), "the bottom-right corner: " .. tostring(up))
		-- The cue ball down-left of it instead: the top-right corner.
		local down = Finder.eightPocket(geometry, balls({ { 0, x - 15, -15 }, { 8, x, 0 } }))
		H.expect(down == pocketAt(HL, HW), "the top-right corner: " .. tostring(down))
	end,

	["a side pocket when the 8 sits at its mouth"] = function()
		local pick = Finder.eightPocket(geometry, balls({ { 0, 0, -10 }, { 8, 0, HW - 6 } }))
		H.expect(pick == pocketAt(0, HW), "the side pocket: " .. tostring(pick))
	end,

	["no open pot: the pocket nearest the 8; no 8: none"] = function()
		-- The cue ball tight behind the 8 with a ball in the way of every line.
		local rows =
			{ { 0, -40, 0 }, { 1, -35, 0 }, { 2, -35, 3 }, { 3, -35, -3 }, { 8, 20, HW - 8 } }
		local pick = Finder.eightPocket(geometry, balls(rows))
		H.expect(pick ~= nil, "always a pocket")
		local none = balls({ { 0, 0, 0 } })
		H.expect(Finder.eightPocket(geometry, none) == nil, "no 8 on the table")
	end,

	["only the 8's pots count, and the same table gives the same pocket"] = function()
		local list = balls({ { 0, -20, 5 }, { 1, 30, 10 }, { 9, -30, -10 }, { 8, 25, -12 } })
		local view = { geometry = geometry, balls = list, groups = {}, team = 1 }
		for _, plan in Finder.candidates(view :: any, nil, nil, { 8 }) do
			H.expect(plan.ball == 8, "a pot of the 8")
		end
		H.expect(
			Finder.eightPocket(geometry, list) == Finder.eightPocket(geometry, list),
			"repeatable"
		)
	end,
}
