--!strict
-- Writes assets/cue/outlines.json: each skinned cue's in-game outline (CueSkinLook's CueOutline,
-- from CueSkins.Pop) by skin id, for the card pictures (assets/cue/CuePreview.py --thumb):
--   color         the solid outline's colour (Pop.outline)
--   transparency  its Highlight's OutlineTransparency (Pop.Outline.ByRarity, else Transparency)
--   lineScale     its width share (ByRarity's LineScale, else 1)
--   palette       the moving gradient's colours from Legendary up (Pop.palette), else absent
--   pop           true when the cue's aura pops (Pop.Ids)
--   level         its rarity for the outline (Pop.level)
--
-- Run from the repo root after changing Config.CueSkins.Pop or a skin's colours:
--   lune run tools/export_cue_outlines.luau [out.json]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

assert(
	fs.isDir("src/shared"),
	"run this from the repo root: lune run tools/export_cue_outlines.luau"
)

local H = require("../tests/harness")
local Config = H.require("Config")
local CueSkins = H.require("CueSkins")
local Pop = H.require("CueSkins.Pop")
local Catalog = H.require("Progression.Catalog")

local C = Config.CueSkins
local O = C.Pop.Outline
local out = {}
for _, catalogId in CueSkins.ids() do
	local row = CueSkins.get(catalogId)
	if row then
		local level = Pop.level(Catalog.get(row.CatalogId or catalogId), row)
		local tier = O.ByRarity[level] or {}
		out[CueSkins.index(catalogId).Id] = {
			catalogId = catalogId,
			color = Pop.outline(row, C.Pop),
			transparency = tier.Transparency or O.Transparency,
			lineScale = tier.LineScale or 1,
			palette = Pop.palette(row, C.Pop, level),
			pop = Pop.applies(catalogId, C.Pop),
			level = level,
		}
	end
end

local path = process.args[1] or "assets/cue/outlines.json"
fs.writeFile(path, serde.encode("json", out, true))
print("wrote " .. path)
