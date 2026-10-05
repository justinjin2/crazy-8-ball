--!strict
-- Cue looks: every catalog cue draws as a real cue (its CueArt style and the 3D stick's bands)
-- and brings an effect style that exists, and the default is one name everywhere.
--
-- The looks and effects are placeholder data that will be retuned by hand, so these guard
-- what a typo would break quietly: a colour out of range, a segment list that no longer adds
-- up, an Effect naming a style that is not there (it would fall back to the plain wisp and
-- nobody would notice), or a style key spelled wrong (Effects would ignore it).

local H = require("./harness")

local function load()
	return H.require("Progression.Catalog"), H.require("Config"), H.require("CueArt")
end

-- The most parts a stick may be built with (CueStickBuilder builds this many at most, per
-- stick, for the local stick and each of Config.Hub.RenderedTables watched ones).
local MAX_BANDS = 16

local function validRgb(rgb: any): boolean
	if type(rgb) ~= "table" or #rgb ~= 3 then
		return false
	end
	for _, v in rgb do
		if type(v) ~= "number" or v ~= math.floor(v) or v < 0 or v > 255 then
			return false
		end
	end
	return true
end

-- Where each Config.Cue.Profile piece ends, as a share of the length (CueStickBuilder's).
local function pieceEnds(Config: any): { number }
	local ends = {}
	for _, row in Config.Cue.Profile do
		table.insert(ends, row.To)
	end
	return ends
end

local function sameRgb(a: { number }, b: { number }): boolean
	return a[1] == b[1] and a[2] == b[2] and a[3] == b[3]
end

-- Style keys a row may give beyond the default's (Config.Effects, the comment above Styles).
local EXTRA_TRAIL = { Colors = true, Core = true }
local EXTRA_POCKET = { Colors = true, ColorShare = true }

return {
	["the default cue is one name: Config.Cue, the catalog and the effects agree"] = function()
		local Catalog, Config = load()
		H.expect(
			Config.Cue.DefaultStyle == Catalog.Default,
			("Config.Cue.DefaultStyle %s is not Catalog.Default %s"):format(
				tostring(Config.Cue.DefaultStyle),
				tostring(Catalog.Default)
			)
		)
		local classic = Catalog.get(Catalog.Default)
		assert(classic, "the default cue is in the catalog")
		H.expect(
			classic.Effect == Config.Effects.DefaultStyle,
			"the default cue's Effect must be Config.Effects.DefaultStyle"
		)
		local base = (Config.Effects.Styles :: any)[Config.Effects.DefaultStyle]
		H.expect(
			base ~= nil and base.Trail ~= nil and base.Pocket ~= nil,
			"the default style is whole"
		)
		H.expect(type(Config.Cue.EquippedAttribute) == "string", "the EquippedCue attribute name")
		-- An unknown id draws the default cue.
		local unknown = Catalog.style("NoSuchCue")
		local default = Catalog.style(Catalog.Default)
		H.expect(#unknown.Segments == #default.Segments, "an unknown cue draws as the default")
		for i, segment in unknown.Segments do
			H.expect(
				sameRgb(segment.Color, default.Segments[i].Color),
				"unknown draws as the default"
			)
		end
	end,

	["every catalog cue's style has valid colours and lengths that add to one"] = function()
		local Catalog = load()
		for _, cue in Catalog.list() do
			local style = Catalog.style(cue.Id)
			local total = 0
			for i, segment in style.Segments do
				H.expect(segment.Length > 0, ("%s segment %d has no length"):format(cue.Id, i))
				H.expect(
					validRgb(segment.Color),
					("%s segment %d has a bad colour"):format(cue.Id, i)
				)
				total += segment.Length
			end
			H.near(total, 1, 1e-6, cue.Id .. "'s segments add to one")
			H.expect(style.TipWidth > 0 and style.TipWidth <= style.ButtWidth, cue.Id .. " tapers")
		end
	end,

	["every catalog cue's Effect names a style, and every rarity has one"] = function()
		local Catalog, Config = load()
		local styles = Config.Effects.Styles :: any
		for _, cue in Catalog.list() do
			H.expect(
				styles[cue.Effect] ~= nil,
				("%s's Effect %s is not in Config.Effects.Styles"):format(
					cue.Id,
					tostring(cue.Effect)
				)
			)
		end
		for _, rarity in Config.BlockOdds.Rarities do
			H.expect(styles[rarity] ~= nil, "no effect style for rarity " .. rarity)
		end
	end,

	["effect styles only give keys the default has, with values of the same kind"] = function()
		local _, Config = load()
		local styles = Config.Effects.Styles :: any
		local base = styles[Config.Effects.DefaultStyle]
		H.expect(validRgb(base.Trail.Color), "the default trail's colour")
		for name, row in styles do
			for part, extras in { Trail = EXTRA_TRAIL, Pocket = EXTRA_POCKET } do
				local over = row[part]
				if over ~= nil then
					for key, value in over do
						local where = ("%s.%s.%s"):format(name, part, key)
						if extras[key] then
							continue
						end
						H.expect(base[part][key] ~= nil, where .. " is not a key the default has")
						H.expect(
							type(value) == type(base[part][key]),
							where .. " is the wrong kind"
						)
					end
					if over.Color ~= nil then
						H.expect(validRgb(over.Color), ("%s.%s.Color"):format(name, part))
					end
					if over.Colors ~= nil then
						-- A ColorSequence holds at most 20 keypoints; a few are plenty.
						H.expect(
							#over.Colors >= 1 and #over.Colors <= 8,
							name .. "." .. part .. ".Colors"
						)
						for _, c in over.Colors do
							H.expect(
								validRgb(c),
								("%s.%s.Colors has a bad colour"):format(name, part)
							)
						end
					end
				end
			end
			for key in row do
				H.expect(
					key == "Trail" or key == "Pocket",
					("%s has an unknown part %s"):format(name, key)
				)
			end
			local trail = row.Trail
			if trail and trail.Core then
				local core = trail.Core
				H.expect(validRgb(core.Color), name .. ".Trail.Core.Color")
				H.expect(
					type(core.Width) == "number" and core.Width > 0 and core.Width <= 1,
					name .. " core width"
				)
				H.expect(type(core.NearTransparency) == "number", name .. " core transparency")
				H.expect(type(core.LightEmission) == "number", name .. " core light")
			end
			local pocket = row.Pocket
			if pocket and pocket.ColorShare ~= nil then
				H.expect(
					pocket.ColorShare >= 0 and pocket.ColorShare <= 1,
					name .. ".Pocket.ColorShare"
				)
				H.expect(pocket.Colors ~= nil, name .. ": ColorShare without Colors does nothing")
			end
		end
	end,

	["every catalog cue's stick bands tile it, each in one piece, in segment order"] = function()
		local Catalog, Config, CueArt = load()
		local ends = pieceEnds(Config)
		for _, cue in Catalog.list() do
			local style = Catalog.style(cue.Id)
			local bands = CueArt.bands(style, ends, Config.Cue.BandSnap)
			H.expect(
				#bands >= 1 and #bands <= MAX_BANDS,
				("%s needs %d parts"):format(cue.Id, #bands)
			)
			H.expect(
				bands[1].from == 0 and bands[#bands].to == 1,
				cue.Id .. " bands run tip to butt"
			)
			local segment = 1
			for i, band in bands do
				H.expect(band.to > band.from, ("%s band %d is empty"):format(cue.Id, i))
				if i > 1 then
					H.expect(
						band.from == bands[i - 1].to,
						("%s band %d leaves a gap"):format(cue.Id, i)
					)
				end
				-- Inside its piece: never across a change of width.
				local pieceFrom = if band.piece > 1 then ends[band.piece - 1] else 0
				H.expect(
					band.from >= pieceFrom - 1e-9 and band.to <= ends[band.piece] + 1e-9,
					("%s band %d crosses a piece"):format(cue.Id, i)
				)
				-- Its colour is this segment's or a later one's: the order is the style's.
				while
					segment <= #style.Segments
					and not sameRgb(style.Segments[segment].Color, band.color)
				do
					segment += 1
				end
				H.expect(
					segment <= #style.Segments,
					("%s band %d is out of order"):format(cue.Id, i)
				)
			end
		end
	end,

	["Classic's stick: nine bands, the tip and the joint snapped onto the shape's steps"] = function()
		local Catalog, Config, CueArt = load()
		local ends = pieceEnds(Config)
		local style = Catalog.style(Catalog.Default)
		local bands = CueArt.bands(style, ends, Config.Cue.BandSnap)
		-- Tip, ferrule, shaft (thin piece), shaft (thicker piece), joint ring, forearm, ring,
		-- wrap, cap.
		H.expect(#bands == 9, ("Classic has %d bands, expected 9"):format(#bands))
		H.expect(bands[1].to == ends[1], "the tip ends where the shape's tip piece does")
		H.expect(sameRgb(bands[1].color, style.Segments[1].Color), "the tip is the tip's colour")
		local forearm = style.Segments[5].Color
		local found = false
		for _, band in bands do
			if sameRgb(band.color, forearm) then
				found = true
				H.expect(band.from == 0.55, "the forearm starts at the shape's shaft-to-butt step")
			end
		end
		H.expect(found, "Classic has a forearm")
	end,

	["bands: snapping, merging, squeezed and empty segments"] = function()
		local CueArt = select(3, load())
		local red, blue, green = { 255, 0, 0 }, { 0, 0, 255 }, { 0, 255, 0 }
		local near = {
			Segments = { { Length = 0.49, Color = red }, { Length = 0.51, Color = blue } },
			TipWidth = 0.5,
			ButtWidth = 1,
		}
		local snapped = CueArt.bands(near, { 0.5, 1 }, 0.02)
		H.expect(#snapped == 2, "a boundary near a step snaps onto it")
		H.expect(
			snapped[1].to == 0.5 and snapped[1].piece == 1 and sameRgb(snapped[1].color, red),
			"red piece"
		)
		H.expect(snapped[2].piece == 2 and sameRgb(snapped[2].color, blue), "blue piece")
		local unsnapped = CueArt.bands(near, { 0.5, 1 }, 0)
		H.expect(#unsnapped == 3, "no snap leaves the sliver")
		H.expect(
			unsnapped[2].piece == 1 and sameRgb(unsnapped[2].color, blue),
			"the sliver is blue"
		)

		local repeated = {
			Segments = {
				{ Length = 0.3, Color = red },
				{ Length = 0.3, Color = { 255, 0, 0 } },
				{ Length = 0.4, Color = blue },
			},
			TipWidth = 0.5,
			ButtWidth = 1,
		}
		local merged = CueArt.bands(repeated, { 1 }, 0)
		H.expect(#merged == 2 and merged[1].to == 0.6, "one colour in one piece is one band")

		local squeezed = {
			Segments = {
				{ Length = 0.495, Color = red },
				{ Length = 0.01, Color = green },
				{ Length = 0.495, Color = blue },
			},
			TipWidth = 0.5,
			ButtWidth = 1,
		}
		local gone = CueArt.bands(squeezed, { 0.5, 1 }, 0.01)
		H.expect(#gone == 2, "a segment squeezed to nothing has no band")
		H.expect(
			sameRgb(gone[1].color, red) and sameRgb(gone[2].color, blue),
			"its neighbours stay"
		)

		local empty = CueArt.bands(
			{ Segments = {}, TipWidth = 0.5, ButtWidth = 1 },
			{ 0.3, 1 },
			0.01
		)
		H.expect(
			#empty == 2 and #empty[1].color == 3,
			"no segments: one band per piece, still coloured"
		)
	end,
}
