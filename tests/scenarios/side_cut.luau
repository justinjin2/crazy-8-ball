--!strict
-- Synthetic model regression captured 2026-09-22 at regulation radius, after physics A-E.
-- This is not an externally measured real-table shot. Coordinates and tolerance are inches.
return {
	name = "side_cut",
	description = "Right english, squirt and cloth swerve precede a cut with opposite ball paths.",
	radius = 1.125,
	pocketsOpen = false,
	balls = { { id = 0, x = -20, y = -4 }, { id = 1, x = -12, y = -3 } },
	shot = { angle = 0, power = 0.32, spin = { x = 0.3, y = 0 }, elevation = 4 },
	tolerance = 0.02,
	firstContact = 1,
	expected = {
		{ id = 0, x = -0.710109455120, y = -13.893182033368, z = 0, pocketed = false },
		{ id = 1, x = 10.821869681640, y = 8.298632659360, z = 0, pocketed = false },
	},
}
