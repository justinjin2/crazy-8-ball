--!strict
-- CueArt tests: the shape of a cue.
--
-- These guard the things that would look like bad art rather than a bug: a taper running the
-- wrong way, a joint ring landing half a slice off, a hand-written style whose lengths do not
-- quite add to one quietly losing its butt cap.

local H = require("./harness")

local function setup()
	return H.require("CueArt")
end

-- Tip, ferrule, shaft, butt. Lengths deliberately do NOT add to 1.
local function style(): any
	return {
		Segments = {
			{ Length = 0.05, Color = { 10, 10, 10 } },
			{ Length = 0.05, Color = { 250, 250, 250 } },
			{ Length = 0.60, Color = { 200, 160, 110 } },
			{ Length = 0.20, Color = { 60, 30, 20 } },
		},
		TipWidth = 0.4,
		ButtWidth = 1,
	}
end

return {
	["slices tile the cue exactly once, tip to butt"] = function()
		local CueArt = setup()
		for _, count in { 1, 2, 7, 48, 100 } do
			local slices = CueArt.slices(style(), count)
			H.expect(#slices == count, ("asked for %d slices, got %d"):format(count, #slices))
			local total = 0
			local expectedOffset = 0
			for _, slice in slices do
				H.near(slice.offset, expectedOffset, 1e-9, "slices must be contiguous")
				expectedOffset += slice.length
				total += slice.length
			end
			H.near(total, 1, 1e-9, ("%d slices must cover the whole cue"):format(count))
		end
	end,

	["the taper only ever widens from tip to butt"] = function()
		local CueArt = setup()
		local slices = CueArt.slices(style(), 48)
		local previous = -1
		for _, slice in slices do
			H.expect(slice.width >= previous, "a cue must not get thinner toward the butt")
			H.expect(slice.width > 0, "a slice with no width would be invisible")
			previous = slice.width
		end
		-- Ends sit inside the declared range, half a slice in from each end.
		H.expect(slices[1].width >= 0.4, "the tip is the narrowest point")
		H.expect(slices[#slices].width <= 1, "the butt is the widest point")
		H.expect(slices[#slices].width > slices[1].width, "it must actually taper")
	end,

	["a cue that does not taper is allowed"] = function()
		local CueArt = setup()
		local flat = style()
		flat.TipWidth, flat.ButtWidth = 1, 1
		for _, slice in CueArt.slices(flat, 12) do
			H.near(slice.width, 1, 1e-9, "an untapered cue is the same width throughout")
		end
	end,

	["colours land where the data says, not half a slice early"] = function()
		local CueArt = setup()
		local s = style()
		-- Lengths add to 0.9, so they normalise: tip 0..0.0556, ferrule ..0.1111,
		-- shaft ..0.7778, butt ..1.
		H.expect(CueArt.colorAt(s, 0)[1] == 10, "the very tip is the tip colour")
		H.expect(CueArt.colorAt(s, 0.03)[1] == 10, "still the tip")
		H.expect(CueArt.colorAt(s, 0.08)[1] == 250, "the ferrule")
		H.expect(CueArt.colorAt(s, 0.5)[1] == 200, "the shaft")
		H.expect(CueArt.colorAt(s, 0.9)[1] == 60, "the butt")
		H.expect(CueArt.colorAt(s, 1)[1] == 60, "the very butt")
		-- Out of range must clamp rather than fall off the end.
		H.expect(CueArt.colorAt(s, -1)[1] == 10, "before the tip clamps to the tip")
		H.expect(CueArt.colorAt(s, 5)[1] == 60, "past the butt clamps to the butt")
	end,

	["every segment survives into the slices"] = function()
		local CueArt = setup()
		-- With enough slices even the 5%-long tip and ferrule must appear. A picker that
		-- sampled leading edges instead of midpoints would drop the thinnest band.
		local slices = CueArt.slices(style(), 48)
		local seen: { [number]: boolean } = {}
		for _, slice in slices do
			seen[slice.color[1]] = true
		end
		for _, key in { 10, 250, 200, 60 } do
			H.expect(seen[key] == true, ("segment with red %d never appeared"):format(key))
		end
	end,

	["a style whose lengths do not add to one is normalised, not truncated"] = function()
		local CueArt = setup()
		local short = {
			Segments = {
				{ Length = 1, Color = { 1, 1, 1 } },
				{ Length = 1, Color = { 2, 2, 2 } },
			},
			TipWidth = 0.5,
			ButtWidth = 1,
		}
		-- Two equal segments given as 1 and 1, not 0.5 and 0.5: the split is still halfway.
		H.expect(CueArt.colorAt(short, 0.49)[1] == 1, "first half")
		H.expect(CueArt.colorAt(short, 0.51)[1] == 2, "second half")
		local slices = CueArt.slices(short, 10)
		local first, second = 0, 0
		for _, slice in slices do
			if slice.color[1] == 1 then
				first += 1
			else
				second += 1
			end
		end
		H.expect(first == 5 and second == 5, ("expected 5/5, got %d/%d"):format(first, second))
	end,

	["degenerate styles do not throw"] = function()
		local CueArt = setup()
		local empty = { Segments = {}, TipWidth = 0.5, ButtWidth = 1 }
		H.expect(#CueArt.colorAt(empty, 0.5) == 3, "an empty cue still yields a colour")
		H.expect(#CueArt.slices(empty, 4) == 4, "an empty cue still yields slices")
		local zero = {
			Segments = { { Length = 0, Color = { 7, 7, 7 } } },
			TipWidth = 0.5,
			ButtWidth = 1,
		}
		H.expect(CueArt.colorAt(zero, 0.5)[1] == 7, "zero-length segments fall back")
		H.expect(#CueArt.slices(style(), 0) == 1, "asking for no slices still gives one")
	end,

	["styleFor falls back to the default rather than returning nothing"] = function()
		local CueArt = setup()
		local styles = { Classic = style(), Fancy = style() }
		H.expect(CueArt.styleFor(styles, "Classic", "Fancy") == styles.Fancy, "named style")
		H.expect(CueArt.styleFor(styles, "Classic", nil) == styles.Classic, "no name")
		H.expect(CueArt.styleFor(styles, "Classic", "Nope") == styles.Classic, "unknown name")
	end,
}
