--!strict
-- Checks the committed assets/cue/Shape.json against the cue it was exported from.
--
-- The Blender scripts lathe the shared cue mesh from that file, so the drawn cue stays inside
-- the outline CueClearance tests. Change Config.Cue's size or Profile, or Catalog.style, and
-- the file goes stale; this test names the first key that moved so the mesh is rebuilt.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local H = require("./harness")
local CueShapeExport = require("./cue_shape")

local STALE_HINT = "run lune run tools/export_cue_shape.luau, then rebuild assets/cue"

return {
	["the committed Shape.json matches the cue"] = function()
		local path = CueShapeExport.PATH
		H.expect(fs.isFile(path), path .. " is missing: " .. STALE_HINT)
		local committed = serde.decode("json", fs.readFile(path)) :: any
		local fresh = serde.decode("json", CueShapeExport.encode()) :: any
		local ok, err = pcall(function()
			H.matchesJson(committed, fresh, "Shape.json", 1e-12)
			H.matchesJson(fresh, committed, "export", 1e-12)
		end)
		if not ok then
			error(("%s is stale: %s; %s"):format(path, tostring(err), STALE_HINT), 0)
		end
	end,

	["the export covers the whole cue, zones in order, the envelope sampled to the butt"] = function()
		local g = CueShapeExport.build()
		H.near(g.length_studs, 7, 1e-12, "length")
		H.near(g.butt_diameter_studs, 0.2, 1e-12, "butt diameter")
		local expected = { 0, 0.015, 0.035, 0.515, 0.54, 0.76, 0.775, 0.945, 1 }
		H.expect(#g.zones == 8, "eight zones")
		for i, zone in g.zones do
			H.near(zone.from, expected[i], 1e-9, zone.name .. " from")
			H.near(zone.to, expected[i + 1], 1e-9, zone.name .. " to")
			H.near(zone.to_studs, zone.to * g.length_studs, 1e-9, zone.name .. " studs")
		end
		local last = g.envelope[#g.envelope]
		H.near(last[1], g.length_studs, 1e-12, "envelope reaches the butt")
		H.near(last[2], g.butt_diameter_studs / 2, 1e-12, "the butt radius")
		H.near(g.envelope[1][2], g.tip_diameter_studs / 2, 1e-12, "the tip radius")
	end,
}
