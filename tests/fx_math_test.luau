--!strict
-- FxMath (src/shared/FxMath.luau): the arithmetic the ability looks share. A wrong envelope
-- is a grade that pops instead of fading, a flare that never goes dark, a dashed ring with a
-- gap in the wrong place; none of it shows up anywhere but on screen.

local H = require("./harness")

local function setup()
	return H.require("FxMath")
end

return {
	["an envelope fades in, holds, fades out and is 0 outside"] = function()
		local M = setup()
		H.near(M.envelope(-0.1, 0.2, 1, 0.5), 0, 1e-12, "before it begins")
		H.near(M.envelope(0, 0.2, 1, 0.5), 0, 1e-12, "at its start")
		H.near(M.envelope(0.1, 0.2, 1, 0.5), 0.5, 1e-12, "halfway up (eased)")
		H.near(M.envelope(0.2, 0.2, 1, 0.5), 1, 1e-12, "held")
		H.near(M.envelope(1.1, 0.2, 1, 0.5), 1, 1e-12, "still held")
		H.near(M.envelope(1.45, 0.2, 1, 0.5), 0.5, 1e-12, "halfway down")
		H.near(M.envelope(1.7, 0.2, 1, 0.5), 0, 1e-12, "faded out")
		H.near(M.envelope(9, 0.2, 1, 0.5), 0, 1e-12, "long gone")
		H.expect(not M.envelopeDone(1.69, 0.2, 1, 0.5), "not done while fading")
		H.expect(M.envelopeDone(1.7, 0.2, 1, 0.5), "done once faded")
	end,

	["an envelope with no ramps snaps, and one held for ever never ends"] = function()
		local M = setup()
		H.near(M.envelope(0, 0, 1, 0), 1, 1e-12, "no fade in: full at once")
		H.near(M.envelope(1, 0, 1, 0), 0, 1e-12, "no fade out: gone at once")
		H.near(M.envelope(1e6, 0.1, math.huge, 0.3), 1, 1e-12, "held until released")
		H.expect(not M.envelopeDone(1e6, 0.1, math.huge, 0.3), "never done on its own")
	end,

	["a release fades from where it was, never jumping up"] = function()
		local M = setup()
		H.near(M.released(0.6, 0, 0.4), 0.6, 1e-12, "starts where it was")
		H.near(M.released(0.6, 0.2, 0.4), 0.3, 1e-12, "halfway")
		H.near(M.released(0.6, 0.4, 0.4), 0, 1e-12, "gone")
		H.near(M.released(0.6, 1, 0), 0, 1e-12, "no fade: gone at once")
		local previous = math.huge
		for i = 0, 40 do
			local w = M.released(1, i / 100, 0.4)
			H.expect(w <= previous, "a release only ever falls")
			previous = w
		end
	end,

	["a flare peaks at its rise and is dark at both ends"] = function()
		local M = setup()
		H.near(M.flare(0, 1, 0.2), 0, 1e-12, "dark at the start")
		H.near(M.flare(0.2, 1, 0.2), 1, 1e-12, "full at the end of the rise")
		H.near(M.flare(0.6, 1, 0.2), 0.25, 1e-12, "a quarter halfway down (quadratic)")
		H.near(M.flare(1, 1, 0.2), 0, 1e-12, "dark at the end")
		H.near(M.flare(-1, 1, 0.2), 0, 1e-12, "dark before")
		H.near(M.flare(0, 1, 0), 1, 1e-12, "no rise: full at once")
		H.near(M.flare(0.5, 0, 0.2), 0, 1e-12, "a zero-length flare is dark")
	end,

	["a shake decays from full to nothing"] = function()
		local M = setup()
		H.near(M.decay(0, 2), 1, 1e-12, "full at once")
		H.near(M.decay(1, 2), 0.25, 1e-12, "a quarter halfway")
		H.near(M.decay(2, 2), 0, 1e-12, "still at the end")
	end,

	["a solid ring's arcs close the circle; dashes leave even gaps"] = function()
		local M = setup()
		local solid = M.ringArcs(4, 1, 0)
		H.expect(#solid == 4, "four arcs")
		H.near(solid[1].from, 0, 1e-12, "starts at the phase")
		for i = 1, 4 do
			local nextFrom = if i < 4 then solid[i + 1].from else 2 * math.pi
			H.near(solid[i].to, nextFrom, 1e-12, "no gap between solid arcs")
		end
		local dashes = M.ringArcs(8, 0.5, 0.3)
		H.expect(#dashes == 8, "eight dashes")
		local piece = 2 * math.pi / 8
		for i, arc in dashes do
			H.near(arc.to - arc.from, piece / 2, 1e-12, "each dash covers half its piece")
			-- Centred in its piece: the middle sits at phase + (i - 0.5) pieces.
			H.near((arc.from + arc.to) / 2, 0.3 + (i - 0.5) * piece, 1e-12, "centred")
		end
		H.expect(#M.ringArcs(0, 1, 0) == 1, "at least one arc")
	end,

	["an arc's handle is the standard circle approximation"] = function()
		local M = setup()
		H.near(M.arcHandle(1, math.pi / 2), 0.5523, 1e-4, "a quarter circle")
		H.near(M.arcHandle(2, math.pi / 2), 2 * 0.5523, 2e-4, "scales with the radius")
		H.near(M.arcHandle(1, 0), 0, 1e-12, "no sweep, no handle")
	end,

	["clipping keeps only the arcs whose middles are on the cloth"] = function()
		local M = setup()
		-- A ring of radius 10 round a point 5 in from the +x cushion of a 50 x 25 half table.
		local arcs = M.ringArcs(4, 1, -math.pi / 4) -- middles at 0, 90, 180, 270 degrees
		local kept = M.clipArcs(arcs, 45, 0, 10, 50, 25)
		H.expect(#kept == 3, ("the arc over the cushion is dropped (kept %d)"):format(#kept))
		for _, arc in kept do
			local mid = (arc.from + arc.to) / 2
			H.expect(math.abs(mid) > 1e-9, "the dropped one is the one pointing at +x")
		end
		H.expect(#M.clipArcs(arcs, 0, 0, 10, 50, 25) == 4, "in the middle, nothing is cut")
		H.expect(M.onCloth(50, -25, 50, 25), "the edge counts as on the cloth")
		H.expect(not M.onCloth(50.01, 0, 50, 25), "past it does not")
	end,

	["within is a closed disc"] = function()
		local M = setup()
		H.expect(M.within(3, 4, 5), "on the edge")
		H.expect(not M.within(3, 4.01, 5), "just outside")
		H.expect(M.within(0, 0, 0), "the centre of a zero disc")
	end,

	["flipbook frames loop or hold, and map to their cells"] = function()
		local M = setup()
		H.expect(M.flipFrame(0, 24, 16, true) == 0, "first frame")
		H.expect(M.flipFrame(0.5, 24, 16, true) == 12, "half a second at 24 fps")
		H.expect(M.flipFrame(1, 24, 16, true) == 8, "loops round (24 % 16)")
		H.expect(M.flipFrame(1, 24, 16, false) == 15, "held on the last frame")
		H.expect(M.flipFrame(-1, 24, 16, true) == 0, "before the start is the first")
		local c, r = M.flipCell(13, 4)
		H.expect(c == 1 and r == 3, "frame 13 of a 4-wide sheet is column 1, row 3")
	end,
}
