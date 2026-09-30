--!strict
-- Synthetic model regression captured 2026-09-22 at regulation radius, after physics A-E;
-- recaptured 2026-09-23 when side spin stopped bending the path (Config.Cue.SideSpinBendsPath
-- off), and 2026-09-30 for the 25 mph bar and 0.0125 rolling friction. This is not an
-- externally measured real-table shot. Coordinates and tolerance are inches.
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
		{ id = 0, x = -4.828059143966, y = -11.054508367366, z = 0, pocketed = false },
		{ id = 1, x = 1.149792642056, y = 4.185708824853, z = 0, pocketed = false },
	},
}
