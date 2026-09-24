--!strict
-- Writes assets/table/Geometry.json: the physics table (cushions, jaws, pocket openings,
-- rails, spots, the default rack) as data for the Blender script that builds the table
-- model, so the drawn pockets are exactly the ones the balls fall into.
--
-- Run from the repo root after changing anything in Config.Table or Physics.Table:
--   lune run tools/export_table_geometry.luau
-- then rebuild the table package. tests/table_geometry_test.luau fails until you do.
--
-- The contents are built in tests/table_geometry.luau, which the test shares.

local fs = require("@lune/fs")

assert(
	fs.isDir("src/shared"),
	"run this from the repo root: lune run tools/export_table_geometry.luau"
)

local TableGeometryExport = require("../tests/table_geometry")

fs.writeFile(TableGeometryExport.PATH, TableGeometryExport.encode())
print("wrote " .. TableGeometryExport.PATH)
