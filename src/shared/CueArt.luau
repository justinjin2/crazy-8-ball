--!strict
-- CueArt: the shape of a cue, as numbers.
--
-- A cue is described as a list of SEGMENTS running tip to butt - leather tip, ferrule,
-- shaft, joint ring, forearm, wrap, butt cap - each with a length and a colour, plus how
-- much the whole thing tapers. That description is catalog DATA: adding a collectible cue
-- is a row here, never new code (Roadmap 5.2), and the same row can drive the 2D cue in the
-- power control, the 3D stick on the table, and an inventory thumbnail.
--
-- This module turns that description into SLICES: thin bands from tip to butt, each with its
-- own width and colour. Slicing is what makes a taper possible out of rectangles, since a
-- Frame cannot be a trapezoid - enough slices and the steps disappear.
--
-- It is pure so the awkward parts are Lune-testable: lengths that do not add to one, a
-- colour landing on a segment boundary, a taper that must never run backwards.

local CueArt = {}

export type Segment = {
	-- Fraction of the cue's length. The list is normalised, so these need not add to 1.
	Length: number,
	Color: { number },
}

export type Style = {
	-- Tip first, butt last.
	Segments: { Segment },
	-- Widths as a fraction of the widest point, so a style is resolution independent.
	TipWidth: number,
	ButtWidth: number,
}

export type Slice = {
	offset: number, -- 0 at the tip, 1 at the butt
	length: number,
	width: number, -- fraction of the widest point
	color: { number },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- The colour at `t` along the cue, 0 at the tip and 1 at the butt.
---
--- Segment lengths are normalised rather than trusted to add to 1: a style is hand-written
--- data, and a row that adds to 0.98 should look very slightly off, not lose its butt cap.
function CueArt.colorAt(style: Style, t: number): { number }
	local segments = style.Segments
	if #segments == 0 then
		return { 255, 255, 255 }
	end
	local total = 0
	for _, segment in segments do
		total += math.max(segment.Length, 0)
	end
	if total <= 0 then
		return segments[1].Color
	end

	local want = math.clamp(t, 0, 1) * total
	local walked = 0
	for _, segment in segments do
		walked += math.max(segment.Length, 0)
		if want <= walked then
			return segment.Color
		end
	end
	return segments[#segments].Color
end

--- Cut the cue into `count` slices from tip to butt.
---
--- Each slice takes the colour at its own MIDPOINT rather than its leading edge, so a thin
--- band like a joint ring lands where the data says it does instead of half a slice early.
function CueArt.slices(style: Style, count: number): { Slice }
	local n = math.max(math.floor(count), 1)
	local out: { Slice } = table.create(n)
	local span = 1 / n
	for i = 1, n do
		local middle = (i - 0.5) * span
		table.insert(out, {
			offset = (i - 1) * span,
			length = span,
			-- The taper is linear along the cue, which is what a real one looks like from
			-- above: an even swell from the tip to the wrap.
			width = lerp(style.TipWidth, style.ButtWidth, middle),
			color = CueArt.colorAt(style, middle),
		})
	end
	return out
end

export type Band = {
	from: number, -- a share of the length, 0 at the tip
	to: number,
	piece: number, -- the shape piece it lies in (an index into the `pieceEnds` given)
	color: { number },
}

-- Two cuts closer than this (a share of the length) are the same cut. (internal)
local SAME_CUT = 1e-6

--- Cut a style into coloured bands over a stick made of shape pieces, for the 3D cue
--- (CueStickBuilder): every band lies inside one piece (so it is drawn at that piece's width
--- and the silhouette stays the shape's) and one segment (so it has one colour).
---
--- `pieceEnds` are where the pieces end, as shares of the length, ascending, the last 1. A
--- segment boundary within `snap` of a piece boundary moves onto it, so a joint ring that
--- almost meets the shaft's step does not leave a sliver band (a part) of its own. Snapping to
--- the nearest boundary keeps the segments in order; one squeezed to nothing simply has no
--- band. Neighbours of one colour in one piece merge into one band.
function CueArt.bands(style: Style, pieceEnds: { number }, snap: number): { Band }
	local segments = style.Segments
	local total = 0
	for _, segment in segments do
		total += math.max(segment.Length, 0)
	end
	-- Where each segment ends (a share of the length), snapped.
	local ends: { number } = {}
	local walked = 0
	for i, segment in segments do
		walked += math.max(segment.Length, 0)
		local at = if total > 0 then walked / total else 1
		if i == #segments then
			at = 1
		else
			local raw, best = at, snap
			for _, cut in pieceEnds do
				local d = math.abs(cut - raw)
				if d <= best then
					best = d
					at = cut
				end
			end
		end
		ends[i] = at
	end

	local cuts: { number } = { 0, 1 }
	for _, cut in pieceEnds do
		table.insert(cuts, math.clamp(cut, 0, 1))
	end
	for _, cut in ends do
		table.insert(cuts, cut)
	end
	table.sort(cuts)

	local bands: { Band } = {}
	for i = 1, #cuts - 1 do
		local from, to = cuts[i], cuts[i + 1]
		if to - from > SAME_CUT then
			local middle = (from + to) / 2
			local piece = #pieceEnds
			for p, cut in pieceEnds do
				if middle < cut then
					piece = p
					break
				end
			end
			local colour: { number } = { 255, 255, 255 }
			if #segments > 0 then
				colour = segments[#segments].Color
				for s, cut in ends do
					if middle < cut then
						colour = segments[s].Color
						break
					end
				end
			end
			local last = bands[#bands]
			if
				last
				and last.piece == piece
				and last.color[1] == colour[1]
				and last.color[2] == colour[2]
				and last.color[3] == colour[3]
			then
				last.to = to
			else
				table.insert(bands, { from = from, to = to, piece = piece, color = colour })
			end
		end
	end
	return bands
end

--- The style a cue asks for, falling back to the default. Roadmap 5.1 gives this a real
--- catalog id; until then everyone is on the default.
function CueArt.styleFor(styles: { [string]: Style }, defaultName: string, name: string?): Style
	return styles[name or defaultName] or styles[defaultName]
end

return CueArt
