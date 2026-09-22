--!strict
-- Synthetic model regression captured 2026-09-22 at regulation radius, after physics A-E.
-- This is not an externally measured real-table shot. Coordinates and tolerance are inches.
return {
	name = "gentle_draw",
	description = "The same near straight hit with draw brings the cue ball behind contact.",
	radius = 1.125,
	pocketsOpen = false,
	balls = { { id = 0, x = -20, y = 0 }, { id = 1, x = -16, y = 0 } },
	shot = { angle = 0, power = 0.3, spin = { x = 0, y = -0.45 }, elevation = 4 },
	tolerance = 0.02,
	firstContact = 1,
	expected = {
		{ id = 0, x = -18.761809190024, y = 0, z = 0, pocketed = false },
		{ id = 1, x = 2.694160550165, y = 0, z = 0, pocketed = false },
	},
}
