--!strict
-- Checks the committed assets/table/Geometry.json against the physics it was exported from.
--
-- The Blender script builds the table model from that file, so the drawn pockets, jaws and
-- rails are the ones the balls actually play on. Change Config.Table or Physics.Table and
-- the file goes stale; this test names the first key that moved so the model is rebuilt
-- rather than quietly drifting from the physics.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")
local TableGeometryExport = require("./table_geometry")

local STALE_HINT = "run lune run tools/export_table_geometry.luau, then rebuild the table package"

return {
	["the committed Geometry.json matches the physics"] = function()
		local path = TableGeometryExport.PATH
		H.expect(fs.isFile(path), path .. " is missing: " .. STALE_HINT)
		local committed = serde.decode("json", fs.readFile(path)) :: any
		-- Through JSON and back, so both sides have exactly the shape the file can hold.
		local fresh = serde.decode("json", TableGeometryExport.encode()) :: any
		local ok, err = pcall(function()
			-- Fresh as the expected side catches keys that changed or the file lacks; the
			-- committed file as the expected side catches keys the export no longer writes.
			H.matchesJson(committed, fresh, "Geometry.json", 1e-9)
			H.matchesJson(fresh, committed, "export", 1e-9)
		end)
		if not ok then
			error(("%s is stale: %s; %s"):format(path, tostring(err), STALE_HINT), 0)
		end
	end,

	["the export has every cushion, jaw and pocket where the physics has them"] = function()
		local g = TableGeometryExport.build()
		H.expect(g.schema_version == TableGeometryExport.SCHEMA_VERSION, "schema version")
		H.expect(#g.segments == 18, ("18 cushion segments, got %d"):format(#g.segments))
		H.expect(#g.points == 24, ("24 nose and jaw points, got %d"):format(#g.points))
		H.expect(#g.holes == 6, ("6 pocket holes, got %d"):format(#g.holes))
		H.expect(#g.rack.balls == 15, ("15 racked balls, got %d"):format(#g.rack.balls))

		-- Pocket 1 is the head-end corner on the top (+y) rail, moved out along the diagonal
		-- by the 1.5 in shelf: 50 + 1.5 / sqrt(2) = 51.0607.
		local corner = g.holes[1]
		H.expect(corner.id == 1 and corner.kind == "corner", "hole 1 is a corner")
		H.near(corner.x, -51.0607, 1e-4, "pocket 1 x")
		H.near(corner.y, 26.0607, 1e-4, "pocket 1 y")
		H.near(corner.radius, 2.25, 1e-9, "pocket 1 radius")
		-- The side pocket: 2.2 ball diameters of mouth, its centre half a mouth out.
		local side = g.holes[2]
		H.expect(side.id == 2 and side.kind == "side", "hole 2 is a side pocket")
		H.near(side.x, 0, 1e-9, "side pocket x")
		H.near(side.y, 27.475, 1e-9, "side pocket y")
		H.near(side.radius, 2.475, 1e-9, "side pocket radius")
		H.near(g.pockets.corner.facing_length, 2.615114, 1e-5, "corner facing length")

		-- The 7 in rail table: 100 + 2 * 7 = 114 in = 18.24 studs, 50 + 2 * 7 = 64 in = 10.24
		-- studs, and the barrier 0.36 studs beyond it, where the 5.5 in rails put it.
		H.near(g.rail.footprint_studs[1], 18.24, 1e-9, "footprint length")
		H.near(g.rail.footprint_studs[2], 10.24, 1e-9, "footprint width")
		H.near(g.rail.barrier_half_extents_studs[1], 9.48, 1e-9, "barrier half length")
		H.near(g.rail.barrier_half_extents_studs[2], 5.48, 1e-9, "barrier half width")
		H.expect(
			g.rail.footprint_studs[1] / 2 <= g.rail.barrier_half_extents_studs[1]
				and g.rail.footprint_studs[2] / 2 <= g.rail.barrier_half_extents_studs[2],
			"the table fits inside its barrier"
		)
	end,

	["the export says which pocket and cushion every facing and point belongs to"] = function()
		local g = TableGeometryExport.build()
		local segmentNamed, pointNamed = {}, {}
		for _, seg in ipairs(g.segments) do
			segmentNamed[seg.name] = seg
			H.expect(
				(seg.kind == "facing") == (seg.pocket ~= nil),
				seg.name .. ": a facing names its pocket, a rail segment does not"
			)
		end
		for _, p in ipairs(g.points) do
			pointNamed[p.name] = p
			local facing = segmentNamed[p.facing]
			H.expect(facing ~= nil and facing.kind == "facing", p.name .. " ends a facing")
			H.expect(p.pocket == facing.pocket, p.name .. " is in its facing's pocket")
			-- a is the nose end, b the jaw end.
			local at = if p.kind == "nose" then facing.a else facing.b
			H.near(p.x, at[1], 1e-12, p.name .. " x")
			H.near(p.y, at[2], 1e-12, p.name .. " y")
		end

		-- Hole 3 (topRight) is guarded by the top rail's right corner facing and the foot
		-- rail's top one; the rail SEGMENT named topLeft is the top rail between holes 1 and 2.
		H.expect(g.holes[3].facings[1] == "topCornerR", "hole 3 first facing")
		H.expect(g.holes[3].facings[2] == "footCornerT", "hole 3 second facing")
		H.expect(g.holes[2].facings[1] == "topSideL", "side pocket 2 first facing")
		H.expect(g.cushions[1].rail == "topLeft", "cushion 1 is the top rail's left half")
		H.expect(
			g.cushions[1].pockets[1] == 1 and g.cushions[1].pockets[2] == 2,
			"the topLeft rail runs from hole 1 to hole 2"
		)

		H.expect(#g.cushions == 6, ("6 cushions, got %d"):format(#g.cushions))
		for _, cushion in ipairs(g.cushions) do
			local rail = segmentNamed[cushion.rail]
			local first = segmentNamed[cushion.facings[1]]
			local last = segmentNamed[cushion.facings[2]]
			H.expect(rail.kind == "rail", cushion.rail .. " is a rail segment")
			-- The chain closes: jaw to nose along facings[1], the rail, nose to jaw on facings[2].
			H.near(first.a[1], rail.a[1], 1e-9, cushion.rail .. " start x")
			H.near(first.a[2], rail.a[2], 1e-9, cushion.rail .. " start y")
			H.near(last.a[1], rail.b[1], 1e-9, cushion.rail .. " end x")
			H.near(last.a[2], rail.b[2], 1e-9, cushion.rail .. " end y")
			H.expect(cushion.pockets[1] == first.pocket, cushion.rail .. " first pocket")
			H.expect(cushion.pockets[2] == last.pocket, cushion.rail .. " last pocket")
		end

		for _, hole in ipairs(g.holes) do
			local function jawOffset(i: number): (number, number)
				local jaw = pointNamed[hole.jaws[i]]
				H.expect(jaw.facing == hole.facings[i], ("hole %d jaw %d"):format(hole.id, i))
				H.expect(jaw.pocket == hole.id, ("hole %d jaw %d pocket"):format(hole.id, i))
				-- Corner facings run on to the rim of their shifted hole.
				if hole.kind == "corner" then
					local d = math.sqrt((jaw.x - hole.x) ^ 2 + (jaw.y - hole.y) ^ 2)
					H.near(d, hole.radius, 1e-9, ("hole %d jaw %d on the rim"):format(hole.id, i))
				end
				return jaw.x - hole.x, jaw.y - hole.y
			end
			-- Counterclockwise from jaws[1] to jaws[2] crosses the mouth. The way to the table
			-- centre lies inside every mouth, so it must be anticlockwise of jaws[1] and
			-- clockwise of jaws[2].
			local x1, y1 = jawOffset(1)
			local x2, y2 = jawOffset(2)
			local mx, my = -hole.x, -hole.y
			H.expect(x1 * my - y1 * mx > 0, ("hole %d: the mouth is after jaws[1]"):format(hole.id))
			H.expect(
				x2 * my - y2 * mx < 0,
				("hole %d: the mouth is before jaws[2]"):format(hole.id)
			)
		end
	end,

	["the frame text's Roblox formula is where Placement puts a table point"] = function()
		local g = TableGeometryExport.build()
		local Placement = H.require("Placement")
		local p = Placement.new(0, 0, 0, 0)
		local s, h = g.studs_per_inch, g.cloth.above_floor_studs
		for _, xyz in { { 10, 20, 0 }, { -51, 26, -5 }, { 3, -7, 2.08 } } do
			local x, y, z = xyz[1], xyz[2], xyz[3]
			local wx, wy, wz = Placement.toWorld(p, x, y, z)
			-- (x * s, z * s + h, -y * s), as the frame string says.
			H.near(wx, x * s, 1e-9, "Roblox local x")
			H.near(wy, z * s + h, 1e-9, "Roblox local y")
			H.near(wz, -y * s, 1e-9, "Roblox local z")
		end
		H.expect(g.frame:find("(x * s, z * s + h, -y * s)", 1, true) ~= nil, "frame gives it")
		H.expect(g.frame:find("(x * s, y * s, z * s + h)", 1, true) ~= nil, "frame gives Blender")
	end,
}
