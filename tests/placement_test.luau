--!strict
-- Placement tests: the table-space <-> world-space conversion, at every yaw.
--
-- These matter more than they look. A pool table is symmetric end to end, so a sign error
-- in the yaw maths builds a table that LOOKS right and plays mirrored: the guideline would
-- point at the wrong pocket with nothing on screen to give it away. Every lounge table is
-- at yaw 90, so the yaw path is load-bearing from the first table onwards.

local H = require("./harness")

local function setup()
	return H.require("Config"), H.require("Placement")
end

local YAWS = { 0, 90, 180, 270, 37, -90 }

return {
	["toTable undoes toWorld at every yaw"] = function()
		local _, Placement = setup()
		local points = { { 0, 0 }, { 50, 25 }, { -50, -25 }, { 13.5, -7.25 }, { -3, 19 } }
		for _, yaw in YAWS do
			local p = Placement.new(-30, 2.4, -43, yaw)
			for _, pt in points do
				local wx, _, wz = Placement.toWorld(p, pt[1], pt[2], 0)
				local x, y = Placement.toTable(p, wx, wz)
				H.near(x, pt[1], 1e-9, ("yaw %d x"):format(yaw))
				H.near(y, pt[2], 1e-9, ("yaw %d y"):format(yaw))
			end
		end
	end,

	["the table centre lands on the placement, at cloth height"] = function()
		local Config, Placement = setup()
		local p = Placement.new(10, 4.8, -86, 90)
		local wx, wy, wz = Placement.toWorld(p, 0, 0, 0)
		H.near(wx, 10, 1e-9, "centre x")
		H.near(wz, -86, 1e-9, "centre z")
		-- The cloth sits SurfaceHeightStuds above the floor the table stands on, which is
		-- exactly the lounge package's cloth_height_above_floor.
		H.near(wy, 4.8 + Config.Table.SurfaceHeightStuds, 1e-9, "cloth height")
	end,

	["yaw 0 keeps the old mapping: x -> +X, y -> -Z"] = function()
		local Config, Placement = setup()
		local s = Config.Table.StudsPerInch
		local p = Placement.new(0, 0, 0, 0)
		local wx, _, wz = Placement.toWorld(p, 10, 0, 0)
		H.near(wx, 10 * s, 1e-9, "x maps to +X")
		H.near(wz, 0, 1e-9, "x does not move Z")
		wx, _, wz = Placement.toWorld(p, 0, 10, 0)
		H.near(wx, 0, 1e-9, "y does not move X")
		H.near(wz, -10 * s, 1e-9, "y maps to -Z")
	end,

	["yaw 90 turns the table: length runs along -Z, width along -X"] = function()
		local Config, Placement = setup()
		local s = Config.Table.StudsPerInch
		local p = Placement.new(0, 0, 0, 90)
		-- The foot rail (physics +x) must end up at world -Z, not +Z: that is the sign the
		-- symmetric model cannot show us.
		local wx, _, wz = Placement.toWorld(p, 10, 0, 0)
		H.near(wx, 0, 1e-9, "length does not move X")
		H.near(wz, -10 * s, 1e-9, "length maps to -Z")
		wx, _, wz = Placement.toWorld(p, 0, 10, 0)
		H.near(wx, -10 * s, 1e-9, "width maps to -X")
		H.near(wz, 0, 1e-9, "width does not move Z")
	end,

	["the placed footprint matches the lounge package"] = function()
		local Config, Placement = setup()
		-- assets/lounge/Readme.md: the 9 ft table is 17.76 x 9.76 studs natively and the
		-- lounge records placed_plan_footprint_studs as 9.76 across X by 17.76 along Z.
		local T = Config.Table
		local halfLen = T.LengthInches / 2 + T.RailWidthInches
		local halfWid = T.WidthInches / 2 + T.RailWidthInches
		local p = Placement.new(0, 0, 0, 90)
		local ax, _, az = Placement.toWorld(p, halfLen, halfWid, 0)
		local bx, _, bz = Placement.toWorld(p, -halfLen, -halfWid, 0)
		H.near(math.abs(ax - bx), 9.76, 1e-3, "footprint across X")
		H.near(math.abs(az - bz), 17.76, 1e-3, "footprint along Z")
	end,

	["aimVector agrees with toWorld's own rotation"] = function()
		local _, Placement = setup()
		for _, yaw in YAWS do
			local p = Placement.new(5, 0, -7, yaw)
			for _, angle in { 0, 0.4, 1.9, 3.3, 5.7 } do
				local ux, uy, uz = Placement.aimVector(p, angle)
				H.near(uy, 0, 1e-12, "aim is flat")
				H.near(ux * ux + uz * uz, 1, 1e-12, "aim is a unit vector")
				-- Stepping one inch along the aim from the centre must land where
				-- aimVector points.
				local s = (H.require("Config")).Table.StudsPerInch
				local wx, _, wz = Placement.toWorld(p, math.cos(angle), math.sin(angle), 0)
				H.near((wx - p.x) / s, ux, 1e-9, ("yaw %d aim x"):format(yaw))
				H.near((wz - p.z) / s, uz, 1e-9, ("yaw %d aim z"):format(yaw))
			end
		end
	end,

	["aimAngle undoes aimVector"] = function()
		local _, Placement = setup()
		for _, yaw in YAWS do
			local p = Placement.new(0, 0, 0, yaw)
			for _, angle in { 0, 0.4, 1.9, 3.3, 5.7 } do
				local ux, _, uz = Placement.aimVector(p, angle)
				H.near(Placement.aimAngle(p, ux, uz), angle % (2 * math.pi), 1e-9, "aim angle")
			end
		end
	end,

	["dirToTable undoes dirToWorld and keeps unit length"] = function()
		local _, Placement = setup()
		for _, yaw in YAWS do
			local p = Placement.new(0, 0, 0, yaw)
			for _, angle in { 0.2, 1.1, 2.9, 4.4 } do
				local tx, ty = math.cos(angle), math.sin(angle)
				local wx, wz = Placement.dirToWorld(p, tx, ty)
				H.near(wx * wx + wz * wz, 1, 1e-12, "stays a unit vector")
				local bx, by = Placement.dirToTable(p, wx, wz)
				H.near(bx, tx, 1e-9, "dir x round trip")
				H.near(by, ty, 1e-9, "dir y round trip")
			end
		end
	end,

	["forTable gives every lounge table, and nothing else"] = function()
		local Config, Placement = setup()
		H.expect(#Config.Lounge.Tables == 12, "the lounge has twelve tables")
		for _, row in Config.Lounge.Tables do
			local p = Placement.forTable(row.id)
			H.expect(p ~= nil, ("table %d has a placement"):format(row.id))
			H.near((p :: any).x, row.X, 1e-9, "x")
			H.near((p :: any).y, row.Y, 1e-9, "y")
			H.near((p :: any).z, row.Z, 1e-9, "z")
		end
		H.expect(Placement.forTable(0) == nil, "no table 0")
		H.expect(Placement.forTable(13) == nil, "no table 13")
	end,
}
