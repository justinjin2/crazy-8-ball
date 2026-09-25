--!strict
-- The hub map and the code agree: Config.Hub.Tables (hand-copied from assets/hub/Markers.json)
-- matches the generated HubLayout, and sixteen match areas fit the Skyline Club without their
-- fences overlapping.

local H = require("./harness")

local function setup()
	return H.require("Config"), H.require("Placement"), H.require("HubLayout")
end

-- The four corners of a table's match fence, in world X and Z.
local function fenceCorners(Placement: any, row: any): { { number } }
	local p = Placement.forTable(row.id)
	local fx, fy, cx = Placement.fenceHalfExtents(row.teamSize)
	local out = {}
	for _, c in { { cx - fx, -fy }, { cx + fx, -fy }, { cx + fx, fy }, { cx - fx, fy } } do
		local wx, _, wz = Placement.fromTableStuds(p, c[1], c[2], 0)
		table.insert(out, { wx, wz })
	end
	return out
end

-- Axis-aligned bounds of four corners (every hub table is at a multiple of 90 degrees).
local function bounds(corners: { { number } }): (number, number, number, number)
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in corners do
		x0, z0 = math.min(x0, c[1]), math.min(z0, c[2])
		x1, z1 = math.max(x1, c[1]), math.max(z1, c[2])
	end
	return x0, z0, x1, z1
end

return {
	["every table stands under its own pendant"] = function()
		local Config, _, Layout = setup()
		local pendants: { [string]: any } = {}
		for _, p in Layout.Placements do
			if p.name then
				pendants[p.name] = p
			end
		end
		for _, row in Config.Hub.Tables do
			local p = pendants[Config.HubMap.PendantPrefix .. row.id]
			H.expect(p ~= nil, ("table %d has a pendant"):format(row.id))
			H.near(p.x, row.X, 0.01, ("table %d x"):format(row.id))
			H.near(p.z, row.Z, 0.01, ("table %d z"):format(row.id))
			H.near(p.yaw, row.YawDegrees, 0.01, ("table %d yaw"):format(row.id))
		end
	end,

	["the zones seat one, two and three a side"] = function()
		local Config, Placement = setup()
		local count = { 0, 0, 0 }
		for _, row in Config.Hub.Tables do
			H.expect(row.teamSize == 1 or row.teamSize == 2 or row.teamSize == 3, "team size")
			count[row.teamSize] += 1
			H.expect(Placement.teamSizeOf(row.id) == row.teamSize, "teamSizeOf")
		end
		H.expect(count[1] == 10 and count[2] == 4 and count[3] == 2, "10 1v1, 4 2v2, 2 3v3")
		H.expect(Placement.tableCount() == 16, "all sixteen are built")
	end,

	["no two match fences overlap"] = function()
		local Config, Placement = setup()
		local rows = Config.Hub.Tables
		local w = Config.Multiplayer.Fence.ThicknessStuds
		for i = 1, #rows do
			local ax0, az0, ax1, az1 = bounds(fenceCorners(Placement, rows[i]))
			for j = i + 1, #rows do
				local bx0, bz0, bx1, bz1 = bounds(fenceCorners(Placement, rows[j]))
				-- The walls stand outside the inner faces, one thickness each.
				local apart = ax1 + w <= bx0 - w
					or bx1 + w <= ax0 - w
					or az1 + w <= bz0 - w
					or bz1 + w <= az0 - w
				H.expect(
					apart,
					("tables %d and %d have overlapping fences"):format(rows[i].id, rows[j].id)
				)
			end
		end
	end,

	["the fence reaches past the pads at the head and stops short at the foot"] = function()
		local Config, Placement = setup()
		local M = Config.Multiplayer
		for _, teamSize in { 1, 2, 3 } do
			local fx, _, cx = Placement.fenceHalfExtents(teamSize)
			local furthest = M.PadDistanceStuds
				+ (teamSize - 1) * (M.PadSizeStuds + M.PadGapStuds)
				+ M.PadSizeStuds / 2
			H.expect(fx - cx >= furthest, "the head end holds every pad") -- head at cx - fx
			H.near(cx + fx, M.Fence.FootHalfLengthStuds, 1e-9, "the foot end")
		end
	end,

	["the hub carries its lights, seats and collision"] = function()
		local _, _, Layout = setup()
		H.expect(#Layout.Lights <= 30, "about thirty lights at most")
		local pendants = 0
		for _, l in Layout.Lights do
			if l.name:sub(1, 14) == "Light_Pendant_" then
				pendants += 1
			end
		end
		H.expect(pendants == 16, "one light per table")
		H.expect(#Layout.Seats > 100, "plenty of seats")
		local names: { [string]: boolean } = {}
		for _, b in Layout.Collision do
			names[b.name] = true
			H.expect(b.sx > 0 and b.sy > 0 and b.sz > 0, b.name .. " has a size")
		end
		for _, need in { "COL_Floor", "COL_Balcony", "COL_StairRamp", "COL_TerraceWall_E" } do
			H.expect(names[need] == true, "collision has " .. need)
		end
		for _, p in Layout.Placements do
			H.expect(Layout.Masters[p.prop] ~= nil, "placement of a known prop " .. p.prop)
		end
	end,
}
