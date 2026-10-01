--!strict
-- Writes assets/cue/Shape.json: the drawn cue's outline (CueShape.radiusAt), its Profile and
-- the Classic zones, for the Blender scripts that build the shared cue mesh.
--
-- Run from the repo root after changing Config.Cue's size or Profile, or Catalog.style:
--   lune run tools/export_cue_shape.luau
-- then rebuild the cue package (assets/cue/Readme.md). tests/cue_shape_test.luau fails until
-- you do. The contents are built in tests/cue_shape.luau, which the test shares.

local fs = require("@lune/fs")

assert(fs.isDir("src/shared"), "run this from the repo root: lune run tools/export_cue_shape.luau")

local CueShapeExport = require("../tests/cue_shape")

fs.writeFile(CueShapeExport.PATH, CueShapeExport.encode())
print("wrote " .. CueShapeExport.PATH)
