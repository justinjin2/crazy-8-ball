--!strict
-- Cue shape export: the drawn cue's outline and its zones written out as data, for the Blender
-- scripts that build the shared cue mesh (assets/cue). The mesh is lathed from these numbers,
-- so the cue a player sees stays inside the outline CueClearance tests.
--
-- Not a test itself (the runner only picks up *_test.luau files). Two users:
--   tools/export_cue_shape.luau writes encode() to PATH;
--   tests/cue_shape_test.luau fails when the committed PATH no longer matches build().
--
-- Everything comes from Config.Cue, CueShape.radiusAt and Catalog.style("Classic"), never
-- copied numbers. Arrays are built by index and serde sorts object keys, so the file is
-- byte-for-byte reproducible.

local serde = require("@lune/serde")

local H = require("./harness")

local CueShapeExport = {}

--- Bump when a key is renamed, removed or changes meaning; cue_common.py checks it.
CueShapeExport.SCHEMA_VERSION = 1

--- Relative to the repo root.
CueShapeExport.PATH = "assets/cue/Shape.json"

--- The envelope is sampled this often (studs).
CueShapeExport.SAMPLE_STEP = 0.005

-- The Classic style's segments, tip first, as the zone names the mesh uses. Catalog.style
-- gives nine segments for a plain (no accent, no rainbow) cue, which Classic is.
local ZONES = { "tip", "ferrule", "shaft", "joint", "forearm", "ring", "wrap", "cap" }

local FRAME = table.concat({
	"Studs. d is the distance from the tip along the cue toward the butt; radius is",
	"CueShape.radiusAt(d), the envelope the drawn cue must stay inside. Blender: 1 unit = 1",
	"stud, the tip at the origin and the cue along -Y (tip toward butt), which the glTF",
	"exporter (+Y up) turns into Roblox local +Z; the UV seam faces Blender -Z (Roblox -Y).",
}, " ")

local function round(x: number): number
	-- 1e-12 studs: removes float noise so the file does not churn between machines.
	return math.floor(x * 1e12 + 0.5) / 1e12
end

function CueShapeExport.build(): any
	local Config = H.require("Config")
	local CueShape = H.require("CueShape")
	local Catalog = H.require("Progression.Catalog")
	local C = Config.Cue
	local L = C.CueLengthStuds

	local profile = {}
	for i, row in C.Profile do
		profile[i] = { to = row.To, taper = row.Taper, look = row.Look }
	end

	local style = Catalog.style(Config.Cue.DefaultStyle)
	local segments = style.Segments
	assert(#segments == #ZONES, ("Classic has %d segments, expected %d"):format(#segments, #ZONES))
	local total = 0
	for _, segment in segments do
		total += segment.Length
	end
	local zones = {}
	local walked = 0
	for i, segment in segments do
		local from = walked / total
		walked += segment.Length
		local to = if i == #segments then 1 else walked / total
		zones[i] = {
			name = ZONES[i],
			from = round(from),
			to = round(to),
			from_studs = round(from * L),
			to_studs = round(to * L),
			color = { segment.Color[1], segment.Color[2], segment.Color[3] },
		}
	end

	local envelope = {}
	local n = math.floor(L / CueShapeExport.SAMPLE_STEP + 0.5)
	for i = 0, n do
		local d = round(i * CueShapeExport.SAMPLE_STEP)
		envelope[i + 1] = { d, round(CueShape.radiusAt(d, L)) }
	end
	-- Where the envelope bends: the Profile piece ends, where the mesh must place a ring.
	local kinks = {}
	for i, row in C.Profile do
		if i < #C.Profile then
			table.insert(kinks, round(row.To * L))
		end
	end

	local inputs = {
		length_studs = L,
		tip_diameter_studs = C.CueTipDiameterStuds,
		butt_diameter_studs = C.CueButtDiameterStuds,
		profile = profile,
		zones = zones,
	}
	local data = {
		schema_version = CueShapeExport.SCHEMA_VERSION,
		generator = "tools/export_cue_shape.luau",
		note = "generated, do not edit; tests/cue_shape_test.luau fails when stale",
		frame = FRAME,
		style = Config.Cue.DefaultStyle,
		length_studs = L,
		tip_diameter_studs = C.CueTipDiameterStuds,
		butt_diameter_studs = C.CueButtDiameterStuds,
		profile = profile,
		zones = zones,
		envelope_step_studs = CueShapeExport.SAMPLE_STEP,
		envelope = envelope,
		kinks_studs = kinks,
	}
	data.inputs_sha256 = serde.hash("sha256", serde.encode("json", inputs, false))
	return data
end

function CueShapeExport.encode(): string
	return serde.encode("json", CueShapeExport.build(), true) .. "\n"
end

return CueShapeExport
