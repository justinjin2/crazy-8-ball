--!strict
-- The cue skins' catalog hook-up (CueSkins data, CueStickBuilder's mesh path): every cue but
-- the Unique ones (not built yet) has a skin, every skin is a catalog cue, and every asset a
-- skin names is filled in.

local H = require("./harness")

return {
	["every block, rank and Exclusive cue and Classic has a skin; the Unique cues do not yet"] = function()
		local Catalog = H.require("Progression.Catalog")
		local CueSkins = H.require("CueSkins")
		for _, cue in Catalog.list() do
			if cue.Group == "Unique" then
				H.expect(
					not CueSkins.has(cue.Id),
					cue.Id .. ": a Unique cue's skin is not built yet"
				)
			else
				H.expect(CueSkins.has(cue.Id), cue.Id .. " has no skin")
			end
		end
		for _, id in CueSkins.ids() do
			H.expect(Catalog.exists(id), id .. " is a skin but not a catalog cue")
		end
	end,

	["every skin row loads and agrees with its Index row and piece"] = function()
		local CueSkins = H.require("CueSkins")
		for _, id in CueSkins.ids() do
			local row = CueSkins.get(id)
			H.expect(row ~= nil and row.CatalogId == id, id .. ": row")
			local index = CueSkins.index(id)
			H.expect(index.Tier == row.Tier and index.Name == row.Name, id .. ": index")
			H.expect(type(row.Maps.Color) == "string", id .. ": no colour map")
			if row.Piece then
				local piece = CueSkins.piece(row.Piece)
				H.expect(piece ~= nil and #piece.Parts > 0, id .. ": piece " .. row.Piece)
			end
			local pocket = row.Pocket and row.Pocket.Piece
			if pocket then
				H.expect(
					CueSkins.piece(pocket.Piece) ~= nil,
					id .. ": pocket piece " .. pocket.Piece
				)
			end
		end
	end,
}
