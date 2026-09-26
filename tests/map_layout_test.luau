--!strict
-- Checks the rooftop plan (assets/map/Layout.json, written by assets/map/map_layout.py)
-- against the game: the table grid, modes, looks and spawn in Config, and the match fences
-- and queue pads from Placement.
--
-- The plan is drawn in Python so Blender can build the map from it, but Placement is the
-- truth for where a match area is. If the two drift, a planter could stand inside a match
-- fence or a pad in a walkway. Re-run map_layout.py after changing Config.Hub or the pad;
-- this test names what disagrees.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")

local LAYOUT = "assets/map/Layout.json"
local REBUILD = "re-run assets/map/map_layout.py"
local TOL = 1e-3 -- studs; Layout.json rounds to 4 decimals

-- The prop kinds that block walking (map_layout.SOLID).
local SOLID = {
	fern_planter = true,
	palm_planter = true,
	lantern = true,
	lantern_tall = true,
	umbrella_set = true,
	side_couch = true,
	lounge_couch = true,
	coffee_table = true,
	fire_pit = true,
	piano = true,
	piano_bench = true,
	snack_counter = true,
	column = true,
}

local function load(): any
	return serde.decode("json", fs.readFile(LAYOUT)) :: any
end

-- A table's match fence as a world rectangle { x0, z0, x1, z1 } (every table is at a multiple
-- of 90 degrees, so the bounds of its corners are the rectangle).
local function fenceRect(Placement: any, row: any): { number }
	local p = Placement.forTable(row.id)
	local fx, fy, cx, cy = Placement.matchFence(row.teamSize)
	local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
	for _, c in
		{ { cx - fx, cy - fy }, { cx + fx, cy - fy }, { cx + fx, cy + fy }, { cx - fx, cy + fy } }
	do
		local wx, _, wz = Placement.fromTableStuds(p, c[1], c[2], 0)
		x0, z0 = math.min(x0, wx), math.min(z0, wz)
		x1, z1 = math.max(x1, wx), math.max(z1, wz)
	end
	return { x0, z0, x1, z1 }
end

-- A prop's footprint as a world rectangle (map_layout.footprint).
local function footprint(prop: any): { number }
	local w, d = prop.size[1], prop.size[3]
	local yaw = math.rad(prop.yaw)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	local hx = (w * c + d * s) / 2
	local hz = (w * s + d * c) / 2
	return { prop.X - hx, prop.Z - hz, prop.X + hx, prop.Z + hz }
end

local function overlaps(a: { number }, b: { number }): boolean
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

return {
	["the plan's tables are Config's tables, with their modes and looks"] = function()
		local layout = load()
		local Config = H.require("Config")
		local TableBuilder = H.require("TableBuilder")
		local rows = Config.Hub.Tables
		H.expect(
			#layout.tables == #rows,
			("the plan has %d tables, Config %d: %s"):format(#layout.tables, #rows, REBUILD)
		)
		for i, row in rows do
			local t = layout.tables[i]
			H.expect(t.id == row.id, ("table %d: ids differ: %s"):format(i, REBUILD))
			H.near(t.X, row.X, TOL, ("table %d X: %s"):format(row.id, REBUILD))
			H.near(t.Y, row.Y, TOL, ("table %d Y: %s"):format(row.id, REBUILD))
			H.near(t.Z, row.Z, TOL, ("table %d Z: %s"):format(row.id, REBUILD))
			H.near(t.yaw, row.YawDegrees, TOL, ("table %d yaw: %s"):format(row.id, REBUILD))
			H.expect(t.teamSize == row.teamSize, ("table %d mode: %s"):format(row.id, REBUILD))
			H.expect(
				t.look == TableBuilder.lookFor(row.id),
				("table %d: the plan says %s, the game %s"):format(
					row.id,
					t.look,
					TableBuilder.lookFor(row.id)
				)
			)
		end
	end,

	["the plan's spawn is Config's spawn"] = function()
		local s = load().spawn
		local c = H.require("Config").Multiplayer.Spawn
		H.near(s.X, c.X, TOL, "spawn X: " .. REBUILD)
		H.near(s.Y, c.Y, TOL, "spawn Y: " .. REBUILD)
		H.near(s.Z, c.Z, TOL, "spawn Z: " .. REBUILD)
		H.near(s.yaw, c.YawDegrees, TOL, "spawn yaw: " .. REBUILD)
	end,

	["the plan's fences and pads are Placement's"] = function()
		local layout = load()
		local Config = H.require("Config")
		local Placement = H.require("Placement")
		for i, row in Config.Hub.Tables do
			local want = fenceRect(Placement, row)
			local got = layout.fences[i]
			for k = 1, 4 do
				H.near(got[k], want[k], TOL, ("table %d fence: %s"):format(row.id, REBUILD))
			end
			local p = Placement.forTable(row.id)
			local cx, cy, hx, hy = Placement.queuePad(row.teamSize)
			local px, _, pz = Placement.fromTableStuds(p, cx, cy, 0)
			local pad = layout.pads[i]
			H.near(pad.X, px, TOL, ("table %d pad X: %s"):format(row.id, REBUILD))
			H.near(pad.Z, pz, TOL, ("table %d pad Z: %s"):format(row.id, REBUILD))
			-- The pad's world rectangle (tables stand at multiples of 90 degrees).
			local x0, z0, x1, z1 = math.huge, math.huge, -math.huge, -math.huge
			for _, c in { { cx - hx, cy - hy }, { cx + hx, cy + hy } } do
				local wx, _, wz = Placement.fromTableStuds(p, c[1], c[2], 0)
				x0, z0 = math.min(x0, wx), math.min(z0, wz)
				x1, z1 = math.max(x1, wx), math.max(z1, wz)
			end
			for k, v in { x0, z0, x1, z1 } do
				H.near(pad.rect[k], v, TOL, ("table %d pad outline: %s"):format(row.id, REBUILD))
			end
		end
	end,

	["nothing solid stands inside a match fence"] = function()
		local layout = load()
		local Config = H.require("Config")
		local Placement = H.require("Placement")
		local wall = Config.Multiplayer.Fence.ThicknessStuds
		for _, row in Config.Hub.Tables do
			local f = fenceRect(Placement, row)
			local grown = { f[1] - wall, f[2] - wall, f[3] + wall, f[4] + wall }
			for _, prop in layout.props do
				if SOLID[prop.kind] then
					H.expect(
						not overlaps(grown, footprint(prop)),
						("%s at (%.1f, %.1f) is inside table %d's match fence"):format(
							prop.kind,
							prop.X,
							prop.Z,
							row.id
						)
					)
				end
			end
		end
	end,
}
