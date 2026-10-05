--!strict
-- CueSkins: the cue skins' data (the cue-skins run, docs/prompts/CUE_SKINS_REPORT.md). Every
-- block, rank and Exclusive cue has a skin: its surface maps on the shared cue mesh, its aura,
-- moving material, ball trail, pocket finisher and 3D piece, all as data rows generated from
-- assets/cue by tools/cue_skins_data.py (Skins/<CatalogId>, Pieces/<piece>, Index). Never edit
-- those by hand; change the skin file and run the tool. Pure: the client modules that build
-- a look from a row are CueSkinLook, CuePiece and Effects.
--
-- Rows are loaded on first use (the big ones, the Mythics', are tens of kilobytes), so the
-- server, which only needs the Index for the catalog, never loads them.

local Index = require(script.Index)

local CueSkins = {}

local skinsFolder = script:WaitForChild("Skins")
local piecesFolder = script:WaitForChild("Pieces")
local skins: { [string]: any } = {}
local pieces: { [string]: any } = {}

--- True when catalog cue `id` has a skin.
function CueSkins.has(id: any): boolean
	return type(id) == "string" and Index[id] ~= nil
end

--- A skin's Index row (Id, Name, Tier, Thumb, Look, Piece?), or nil.
function CueSkins.index(id: any): any
	return if type(id) == "string" then Index[id] else nil
end

--- A skin's full row (Maps, Surface, Frames, Aura, Moving, TrailEmitters, Style, Pocket,
--- Piece, Thumb, Look), or nil for a cue with no skin.
function CueSkins.get(id: any): any
	if not CueSkins.has(id) then
		return nil
	end
	local row = skins[id]
	if row == nil then
		local module = skinsFolder:FindFirstChild(id)
		row = if module then (require :: any)(module) else nil
		skins[id] = row
	end
	return row
end

--- A piece's row (Id, Frame, Rigid, Models, Parts, Joints, Paths), or nil.
function CueSkins.piece(name: any): any
	if type(name) ~= "string" then
		return nil
	end
	local row = pieces[name]
	if row == nil then
		local module = piecesFolder:FindFirstChild(name)
		row = if module then (require :: any)(module) else nil
		pieces[name] = row
	end
	return row
end

--- Every catalog id with a skin, sorted.
function CueSkins.ids(): { string }
	local ids: { string } = {}
	for id in Index :: { [string]: any } do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return CueSkins
