--!strict
-- Synthetic model regression captured 2026-09-22 at regulation radius, after physics A-E;
-- recaptured 2026-09-23 when side spin stopped bending the path (Config.Cue.SideSpinBendsPath
-- off). This is not an externally measured real-table shot. Coordinates and tolerance are inches.
return {
	name = "side_cut",
	description = "Right english travels straight along the aim (no squirt or swerve), then a cut sends the balls opposite ways.",
	radius = 1.125,
	pocketsOpen = false,
	balls = { { id = 0, x = -20, y = -4 }, { id = 1, x = -12, y = -3 } },
	shot = { angle = 0, power = 0.32, spin = { x = 0.3, y = 0 }, elevation = 4 },
	tolerance = 0.02,
	firstContact = 1,
	expected = {
		{ id = 0, x = 0.985326164101, y = -15.359198082452, z = 0, pocketed = false },
		{ id = 1, x = 9.387744842508, y = 8.644797108270, z = 0, pocketed = false },
	},
}
