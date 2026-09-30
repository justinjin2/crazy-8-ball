--!strict
-- Synthetic model regression captured 2026-09-22 at regulation radius, after physics A-E.
-- Recaptured 2026-09-30 for the 25 mph bar and 0.0125 rolling friction (the power keeps
-- the old ball speed).
-- This is not an externally measured real-table shot. Coordinates and tolerance are inches.
return {
	name = "gentle_follow",
	description = "A near straight hit with follow carries the cue ball past contact.",
	radius = 1.125,
	pocketsOpen = false,
	balls = { { id = 0, x = -20, y = 0 }, { id = 1, x = -16, y = 0 } },
	shot = { angle = 0, power = 0.33, spin = { x = 0, y = 0.45 }, elevation = 4 },
	tolerance = 0.02,
	firstContact = 1,
	expected = {
		{ id = 0, x = -12.259818410087, y = 0, z = 0, pocketed = false },
		{ id = 1, x = 22.152047695376, y = 0, z = 0, pocketed = false },
	},
}
