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

--- The style a cue asks for, falling back to the default. Roadmap 5.1 gives this a real
--- catalog id; until then everyone is on the default.
function CueArt.styleFor(styles: { [string]: Style }, defaultName: string, name: string?): Style
	return styles[name or defaultName] or styles[defaultName]
end

return CueArt
