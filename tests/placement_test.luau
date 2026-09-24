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

	["the placed footprint is the 7 in rail table"] = function()
		local Config, Placement = setup()
		-- The Pro-Am rail is 7 in from cushion nose to outer edge, so the 9 ft table is
		-- 100 + 2 * 7 = 114 in = 18.24 studs long and 50 + 2 * 7 = 64 in = 10.24 studs wide.
		-- At yaw 90 (every lounge table) that is 10.24 across X by 18.24 along Z.
		local T = Config.Table
		local halfLen = T.LengthInches / 2 + T.RailWidthInches
		local halfWid = T.WidthInches / 2 + T.RailWidthInches
		local p = Placement.new(0, 0, 0, 90)
		local ax, _, az = Placement.toWorld(p, halfLen, halfWid, 0)
		local bx, _, bz = Placement.toWorld(p, -halfLen, -halfWid, 0)
		H.near(math.abs(ax - bx), 10.24, 1e-3, "footprint across X")
		H.near(math.abs(az - bz), 18.24, 1e-3, "footprint along Z")
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

	["screenDelta moves the ball the way the screen points at every yaw"] = function()
		local _, Placement = setup()
		-- A camera looking along world -Z: screen right is world +X.
		local expected = {
			[0] = { right = { 1, 0 }, up = { 0, 1 } },
			[90] = { right = { 0, -1 }, up = { 1, 0 } },
			[-90] = { right = { 0, 1 }, up = { -1, 0 } },
		}
		for _, yaw in { 0, 90, -90 } do
			local p = Placement.new(4, 0, -7, yaw)
			local want = expected[yaw]
			-- The camera vectors need not be unit length; the result still is.
			local rx, ry = Placement.screenDelta(p, 2, 0, 0, -3, 1, 0, false)
			local ux, uy = Placement.screenDelta(p, 2, 0, 0, -3, 0, 1, false)
			H.near(rx, want.right[1], 1e-9, ("yaw %d right x"):format(yaw))
			H.near(ry, want.right[2], 1e-9, ("yaw %d right y"):format(yaw))
			H.near(ux, want.up[1], 1e-9, ("yaw %d up x"):format(yaw))
			H.near(uy, want.up[2], 1e-9, ("yaw %d up y"):format(yaw))
			local lx, ly = Placement.screenDelta(p, 2, 0, 0, -3, -1, 0, false)
			H.near(lx, -rx, 1e-9, "left is minus right")
			H.near(ly, -ry, 1e-9, "left is minus right")
		end
		-- Any camera heading: the two screen axes stay perpendicular unit moves on the cloth.
		local p = Placement.new(0, 0, 0, 37)
		for degrees = 0, 355, 5 do
			local a = math.rad(degrees)
			local cx, cz = math.cos(a), math.sin(a)
			local rx, ry = Placement.screenDelta(p, cx, cz, cz, -cx, 1, 0, false)
			local ux, uy = Placement.screenDelta(p, cx, cz, cz, -cx, 0, 1, false)
			H.near(rx * rx + ry * ry, 1, 1e-9, "unit right")
			H.near(ux * ux + uy * uy, 1, 1e-9, "unit up")
			H.near(rx * ux + ry * uy, 0, 1e-9, "perpendicular")
		end
	end,

	["screenDelta on the break slides along the line and Left/Right never go dead"] = function()
		local _, Placement = setup()
		for _, yaw in { 0, 90, -90, 37 } do
			local p = Placement.new(0, 0, 0, yaw)
			for degrees = 0, 355, 5 do
				local a = math.rad(degrees)
				local cx, cz = math.cos(a), math.sin(a)
				local lx, ly = Placement.screenDelta(p, cx, cz, cz, -cx, -1, 0, true, true)
				local rx, ry = Placement.screenDelta(p, cx, cz, cz, -cx, 1, 0, true, true)
				H.expect(lx == 0 and rx == 0, "never off the head string")
				H.expect(math.abs(ry) == 1 and ly == -ry, "Left/Right are full, opposite steps")
				local ux, uy = Placement.screenDelta(p, cx, cz, cz, -cx, 0, 1, true, true)
				local _, dy = Placement.screenDelta(p, cx, cz, cz, -cx, 0, -1, true, true)
				H.expect(ux == 0 and math.abs(uy) == 1 and dy == -uy, "Up/Down never go dead")
			end
		end
	end,

	["screenDelta on the break projects a stick push smoothly onto the line"] = function()
		local _, Placement = setup()
		for _, yaw in { 0, 90, -90, 37 } do
			local p = Placement.new(0, 0, 0, yaw)
			for degrees = 0, 355, 5 do
				local a = math.rad(degrees)
				local cx, cz = math.cos(a), math.sin(a)
				local _, ry = Placement.screenDelta(p, cx, cz, cz, -cx, 1, 0, false)
				local _, fy = Placement.screenDelta(p, cx, cz, cz, -cx, 0, 1, false)
				-- A push exactly on one axis and one a hair off it move the ball about the same.
				for _, push in { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } do
					local sx, sy = push[1], push[2]
					local x, along = Placement.screenDelta(p, cx, cz, cz, -cx, sx, sy, true)
					H.expect(x == 0, "the stick never leaves the head string")
					H.near(along, ry * sx + fy * sy, 1e-9, "a stick push is its projection")
					local _, tilted = Placement.screenDelta(
						p,
						cx,
						cz,
						cz,
						-cx,
						sx + 0.01 * sy,
						sy + 0.01 * sx,
						true
					)
					H.near(tilted, along, 0.02, "no jump a hair off the axis")
				end
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

	["fromTableStuds is toWorld in studs, height from the floor, at every yaw"] = function()
		local Config, Placement = setup()
		local T = Config.Table
		local s = T.StudsPerInch
		local points = { { 0, 0, 0 }, { 50, 25, 2 }, { -50, -25, -1 }, { 13.5, -7.25, 0.4 } }
		for _, yaw in YAWS do
			local p = Placement.new(-30, 2.4, -43, yaw)
			for _, pt in points do
				local ax, ay, az = Placement.toWorld(p, pt[1], pt[2], pt[3])
				local bx, by, bz = Placement.fromTableStuds(
					p,
					pt[1] * s,
					pt[2] * s,
					(T.SurfaceHeightInches + pt[3]) * s
				)
				H.near(bx, ax, 1e-9, ("yaw %d x"):format(yaw))
				H.near(by, ay, 1e-9, ("yaw %d y"):format(yaw))
				H.near(bz, az, 1e-9, ("yaw %d z"):format(yaw))
			end
			local _, floor = Placement.fromTableStuds(p, 3, 4, 0)
			H.near(floor, p.y, 1e-12, "height 0 is the floor the table stands on")
		end
	end,

	["rayExit finds where a ray leaves a box, from anywhere inside"] = function()
		local _, Placement = setup()
		-- Along each axis from the centre.
		H.near(Placement.rayExit(0, 0, 1, 0, 8, 4), 8, 1e-12, "+x")
		H.near(Placement.rayExit(0, 0, -1, 0, 8, 4), 8, 1e-12, "-x")
		H.near(Placement.rayExit(0, 0, 0, 1, 8, 4), 4, 1e-12, "+y")
		H.near(Placement.rayExit(0, 0, 0, -1, 8, 4), 4, 1e-12, "-y")
		-- Off centre, the nearer edge along the way.
		H.near(Placement.rayExit(5, 1, 1, 0, 8, 4), 3, 1e-12, "near edge")
		H.near(Placement.rayExit(5, 1, -1, 0, 8, 4), 13, 1e-12, "far edge")
		-- A diagonal leaves through whichever edge it meets first.
		local d = math.sqrt(0.5)
		H.near(Placement.rayExit(0, 0, d, d, 8, 4), 4 / d, 1e-9, "through the long side")
		H.near(Placement.rayExit(7, 0, d, -d, 8, 4), 1 / d, 1e-9, "through the short end")
		H.near(Placement.rayExit(0, 0, d * 2, d * 2, 8, 4), 2 / d, 1e-9, "direction's own units")
		-- Exactly into a corner.
		local c = 1 / math.sqrt(5)
		H.near(Placement.rayExit(0, 0, 2 * c, c, 8, 4), 4 / c, 1e-9, "corner")
		-- Already on or past the edge: nothing to walk.
		H.expect(Placement.rayExit(8, 0, -1, 0, 8, 4) == 0, "on the edge")
		H.expect(Placement.rayExit(9, 1, -1, 0, 8, 4) == 0, "outside")
		H.expect(Placement.rayExit(0, -4, 0, 1, 8, 4) == 0, "on the long side")
		-- No direction: it never leaves.
		H.expect(Placement.rayExit(1, 1, 0, 0, 8, 4) == math.huge, "no direction")
		-- The exit point really is on the edge, whatever the angle.
		for degrees = 0, 355, 5 do
			local a = math.rad(degrees)
			local dx, dy = math.cos(a), math.sin(a)
			local t = Placement.rayExit(-3, 1.5, dx, dy, 8, 4)
			local x, y = -3 + dx * t, 1.5 + dy * t
			local onEdge = math.abs(math.abs(x) - 8) < 1e-9 or math.abs(math.abs(y) - 4) < 1e-9
			H.expect(onEdge and math.abs(x) <= 8 + 1e-9 and math.abs(y) <= 4 + 1e-9, "on the edge")
		end
	end,
}
