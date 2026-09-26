--!strict
-- Placement tests: the table-space <-> world-space conversion, at every yaw.
--
-- These matter more than they look. A pool table is symmetric end to end, so a sign error
-- in the yaw maths builds a table that LOOKS right and plays mirrored: the guideline would
-- point at the wrong pocket with nothing on screen to give it away. Every rooftop table is
-- at yaw 0, but the tests turn tables through every yaw so any layout stays safe.

local H = require("./harness")

local function setup()
	return H.require("Config"), H.require("Placement")
end

local YAWS = { 0, 90, 180, 270, 37, -90 }

-- The four corners of a table's match fence, in world X and Z.
local function fenceCorners(Placement: any, row: any): { { number } }
	local p = Placement.forTable(row.id)
	local fx, fy, cx, cy = Placement.matchFence(row.teamSize)
	local out = {}
	for _, c in
		{ { cx - fx, cy - fy }, { cx + fx, cy - fy }, { cx + fx, cy + fy }, { cx - fx, cy + fy } }
	do
		local wx, _, wz = Placement.fromTableStuds(p, c[1], c[2], 0)
		table.insert(out, { wx, wz })
	end
	return out
end

-- Axis-aligned bounds of four corners (every table is at a multiple of 90 degrees).
local function bounds(corners: { { number } }): (number, number, number, number)
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in corners do
		x0, z0 = math.min(x0, c[1]), math.min(z0, c[2])
		x1, z1 = math.max(x1, c[1]), math.max(z1, c[2])
	end
	return x0, z0, x1, z1
end

return {
	["nearestArea finds the table you stand at and how far outside its area you are"] = function()
		local Config, Placement = setup()
		for _, row in Config.Hub.Tables do
			local fx, fy, cx, cy = Placement.matchFence(row.teamSize)
			if row.id <= Placement.tableCount() then
				local p = Placement.forTable(row.id)
				-- Inside the area (its centre): this table, no distance.
				local wx, _, wz = Placement.fromTableStuds(p, cx, cy, 0)
				local id, d = Placement.nearestArea(wx, wz)
				H.expect(id == row.id, ("table %d centre"):format(row.id))
				H.near(d, 0, 1e-9, "inside")
				-- Two studs past the far end of its length: still this table, two studs out.
				wx, _, wz = Placement.fromTableStuds(p, cx + fx + 2, cy, 0)
				id, d = Placement.nearestArea(wx, wz)
				H.expect(id == row.id, ("table %d end"):format(row.id))
				H.near(d, 2, 1e-9, "two studs past the end")
				-- Three and four studs out beyond a corner: five in a straight line from this
				-- table, unless a neighbour's area is nearer still, or just as near with a lower
				-- id (ties go to the lower id; an 8 stud aisle makes one exactly).
				wx, _, wz = Placement.fromTableStuds(p, cx - fx - 3, cy - fy - 4, 0)
				id, d = Placement.nearestArea(wx, wz)
				if id == row.id then
					H.near(d, 5, 1e-9, "a corner is measured straight")
				else
					H.expect(
						d < 5 - 1e-9 or (d <= 5 + 1e-9 and (id :: number) < row.id),
						"a neighbour only wins when it is nearer, or as near with a lower id"
					)
				end
			end
		end
		-- Far from everything, it is still the nearest table, a long way off.
		local id, d = Placement.nearestArea(0, 5000)
		H.expect(id ~= nil and d > 1000, "far away")
	end,

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
		-- the table package's cloth height.
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
		-- At yaw 90 (every hub table) that is 10.24 across X by 18.24 along Z.
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

	-- The rooftop map (designer, 2026-09-26; assets/map/Spec.md): sixteen tables, ids 1 to 16,
	-- in four rows of four. Ten 1v1, four 2v2 and two 3v3, every one in the regular lobby's
	-- wood look for its mode: 1v1 green, 2v2 red, 3v3 charcoal. The 1v1 tables stand at the
	-- front (nearest the entrance, +Z), the 3v3 at the back.
	["the rooftop has ten 1v1 at the front and wood looks by mode"] = function()
		local Config, Placement = setup()
		local TableBuilder = H.require("TableBuilder")
		local rows = Config.Hub.Tables
		H.expect(#rows == 16 and Placement.tableCount() == 16, "sixteen tables, all built")
		local byMode: { [number]: number } = {}
		local lookOfMode = { [1] = "Green", [2] = "RedWood", [3] = "CharcoalWood" }
		for i, row in rows do
			H.expect(row.id == i, ("table ids run 1 to 16 (row %d)"):format(i))
			H.expect(Placement.teamSizeOf(row.id) == row.teamSize, "teamSizeOf reads the row")
			byMode[row.teamSize] = (byMode[row.teamSize] or 0) + 1
			local look = TableBuilder.lookFor(row.id)
			H.expect(
				look == lookOfMode[row.teamSize],
				("table %d: %s on a %dv%d"):format(i, look, row.teamSize, row.teamSize)
			)
		end
		H.expect(
			byMode[1] == 10 and byMode[2] == 4 and byMode[3] == 2,
			"ten 1v1, four 2v2, two 3v3"
		)
		-- Front to back: the front row (largest Z) is all 1v1, and no 3v3 stands in front of a
		-- 2v2 or a 1v1.
		local frontZ = -math.huge
		for _, row in rows do
			frontZ = math.max(frontZ, row.Z)
		end
		local front3 = -math.huge
		local back1 = math.huge
		for _, row in rows do
			if row.Z == frontZ then
				H.expect(row.teamSize == 1, ("table %d in the front row is 1v1"):format(row.id))
			end
			if row.teamSize == 3 then
				front3 = math.max(front3, row.Z)
			elseif row.teamSize == 1 then
				back1 = math.min(back1, row.Z)
			end
		end
		H.expect(front3 < back1, "the 3v3 tables stand behind every 1v1 table")
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

	-- The queue pad is round, in front of the table on its long side (Queue.PadSide), beyond
	-- the walkway the shooter stands in, and the match fence takes in both: whoever starts a
	-- game standing on the pad is inside it.
	["the queue pad sits outside the walkway and inside the match fence"] = function()
		local Config, Placement = setup()
		local Q = Config.Multiplayer.Queue
		local wx, wy, wcx = Placement.fenceHalfExtents()
		local _, barrierY = Placement.barrierHalfExtents()
		H.near(wcx, 0, 1e-9, "the walkway is centred on the table")
		H.expect(Q.PadSide == 1 or Q.PadSide == -1, "PadSide names a long side")
		local lastRadius = 0
		for teamSize = 1, 3 do
			local pcx, pcy, r = Placement.queuePad(teamSize)
			local fx, fy, fcx, fcy = Placement.matchFence(teamSize)
			H.near(r, Q.PadRadiusStuds[teamSize], 1e-9, "the radius for the mode")
			H.expect(r > lastRadius, "a bigger team gets a bigger pad")
			lastRadius = r
			H.expect(pcx == 0 and pcy * Q.PadSide > 0, "centred on the PadSide long side")
			H.expect(math.abs(pcy) - r >= wy, "beyond the walkway")
			H.expect(math.abs(pcy) - r > barrierY, "clear of the table")
			H.expect(r < wx, "no wider than the walkway is long")
			local function inside(x0: number, x1: number, y0: number, y1: number): boolean
				return x0 >= fcx - fx and x1 <= fcx + fx and y0 >= fcy - fy and y1 <= fcy + fy
			end
			H.expect(inside(-wx, wx, -wy, wy), "the fence holds the walkway")
			H.expect(inside(pcx - r, pcx + r, pcy - r, pcy + r), "the fence holds the pad")
			H.near(
				fcy + Q.PadSide * fy,
				pcy + Q.PadSide * (r + Q.FenceMarginStuds),
				1e-9,
				"with the margin beyond it"
			)
		end
	end,

	["forTable gives every table, and nothing else"] = function()
		local Config, Placement = setup()
		H.expect(#Config.Hub.Tables == 16, "sixteen tables")
		for _, row in Config.Hub.Tables do
			local p = Placement.forTable(row.id)
			H.expect(p ~= nil, ("table %d has a placement"):format(row.id))
			H.near((p :: any).x, row.X, 1e-9, "x")
			H.near((p :: any).y, row.Y, 1e-9, "y")
			H.near((p :: any).z, row.Z, 1e-9, "z")
		end
		H.expect(Placement.forTable(0) == nil, "no table 0")
		H.expect(Placement.forTable(17) == nil, "no table 17")
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
