--!strict
-- Roam (designer, 2026-10-28): who walks free while waiting, when a shooter is taken home, the
-- home spot (the queue pad) inside the walls and clear of the table, and the rematch walk-off.
local H = require("./harness")
local Roam = H.require("Matchmaking.Roam")
local Config = H.require("Config")
local Placement = H.require("Placement")
local expect = H.expect

local function facts(over: { [string]: any }?): any
	local f: { [string]: any } = {
		enabled = true,
		arena = false,
		engineTutorial = nil,
		botKind = nil,
		tutorialActive = false,
		freecam = false,
	}
	for k, v in over or {} do
		f[k] = v
	end
	return f
end

return {
	["a lobby match player roams; every guard keeps the fence"] = function()
		expect(Roam.allowed(facts()), "a plain lobby match roams")
		expect(Roam.allowed(facts({ botKind = "Pc" })), "against PC (the Pumpkin King too)")
		expect(not Roam.allowed(facts({ enabled = false })), "the switch off")
		expect(not Roam.allowed(facts({ arena = true })), "an arena server")
		expect(not Roam.allowed(facts({ engineTutorial = {} })), "the engine's tutorial")
		expect(not Roam.allowed(facts({ botKind = "Tutorial" })), "a Tutorial bot")
		expect(not Roam.allowed(facts({ tutorialActive = true })), "TutorialActive true")
		local unknown = facts()
		unknown.tutorialActive = nil
		expect(not Roam.allowed(unknown), "TutorialActive nil counts as the tutorial")
		expect(not Roam.allowed(facts({ freecam = true })), "in freecam")
	end,

	["home only when outside the walls plus the extra"] = function()
		local extra = Config.Multiplayer.Roam.HomeExtraStuds
		for _, teamSize in { 1, 2, 3 } do
			local fx, fy, fcx, fcy = Placement.matchWalls(teamSize)
			local px, py = Placement.queuePad(teamSize)
			expect(not Roam.needsHome(px, py, fx, fy, fcx, fcy, extra), "on the pad")
			expect(
				not Roam.needsHome(fcx + fx + extra * 0.9, fcy, fx, fy, fcx, fcy, extra),
				"at the wall + extra"
			)
			expect(
				not Roam.needsHome(fcx, fcy - fy - extra * 0.9, fx, fy, fcx, fcy, extra),
				"across, inside"
			)
			expect(
				Roam.needsHome(fcx + fx + extra + 0.1, fcy, fx, fy, fcx, fcy, extra),
				"just past along"
			)
			expect(
				Roam.needsHome(fcx, fcy + fy + extra + 0.1, fx, fy, fcx, fcy, extra),
				"just past across"
			)
			-- Two tables away: well past any wall.
			expect(Roam.needsHome(fcx + 4 * fx, fcy, fx, fy, fcx, fcy, extra), "two tables away")
		end
	end,

	["the home spot (the queue pad) is inside the walls and clear of the table on every table"] = function()
		local s = Config.Table.StudsPerInch
		local count = Placement.tableCount()
		expect(count > 0, "tables")
		for id = 1, count do
			local p = Placement.forTable(id)
			local teamSize = Placement.teamSizeOf(id) or 1
			expect(p ~= nil, "placement " .. id)
			local fx, fy, fcx, fcy = Placement.matchWalls(teamSize)
			local px, py = Placement.queuePad(teamSize)
			expect(
				not Roam.needsHome(px, py, fx, fy, fcx, fcy, 0),
				("table %d: pad inside the walls"):format(id)
			)
			local wx, _, wz = Placement.fromTableStuds(p :: any, px, py, 0)
			local bx = Placement.outsideBarrier(p :: any, wx, wz, 0)
			expect(bx == nil, ("table %d: the pad spot is clear of the table barrier"):format(id))
			-- And the world point maps back to the same table spot.
			local tx, ty = Placement.toTable(p :: any, wx, wz)
			expect(math.abs(tx * s - px) < 1e-6 and math.abs(ty * s - py) < 1e-6, "round trip")
		end
	end,

	["the walk-off truth table"] = function()
		expect(
			Roam.walkOffExempt(true, true, true),
			"far at the result and still away: keeps the offer"
		)
		expect(not Roam.walkOffExempt(false, true, true), "walked off after the result: declines")
		expect(not Roam.walkOffExempt(true, false, true), "came back: nothing to exempt")
		expect(not Roam.walkOffExempt(false, false, true), "by the table: nothing to exempt")
	end,

	["roam off: away at the result still declines, as before the roam"] = function()
		expect(
			not Roam.walkOffExempt(true, true, false),
			"a player who may not roam (switch off, tutorial, arena) keeps the old walk-off rule"
		)
	end,
}
