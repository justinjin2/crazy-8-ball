--!strict
-- Config: every tunable number in the game lives here, grouped by system.
--
-- Units: the physics simulation works in INCHES and SECONDS on a real 9-foot table, so
-- friction and speed values can be taken straight from pool literature. Conversion to
-- Roblox studs happens only when rendering (BallRenderer, TableBuilder, Camera).
--
-- Values marked (tune) are starting points to be adjusted in playtests.

local Config = {}

---------------------------------------------------------------------------------------------
-- Table geometry (regulation 9-foot table)
---------------------------------------------------------------------------------------------
Config.Table = {
	-- Table size. Real tables: 7 ft bar table (78x39 in), 8 ft home (88x44), 9 ft tournament
	-- (100x50). Smaller tables make the balls read bigger from the top-down view, which is
	-- what phone pool games do. Ball size is set separately below. (decide in playtests)
	SizeFeet = 9,
	Sizes = {
		[7] = { Length = 78, Width = 39 },
		[8] = { Length = 88, Width = 44 },
		[9] = { Length = 100, Width = 50 },
	},
	-- Filled in from SizeFeet at the bottom of this file.
	LengthInches = 0,
	WidthInches = 0,
	-- World scale. Roblox avatars are stocky, so a table at true 28 cm/stud proportions looks
	-- like a toy next to one; phone pool games and Roblox pool games alike draw the table
	-- large. 0.16 studs per inch makes the 7 ft table 12.5 studs long. (tune)
	StudsPerInch = 0.16,
	-- Height of the cloth above the floor, in STUDS, so the table always sits at an R15
	-- avatar's hip and the shooter can lean over it whatever the scale.
	SurfaceHeightStuds = 2.9,
	-- Filled in at the bottom of this file from the two values above.
	SurfaceHeightInches = 0,
	-- The Pro-Am rail: wood from the cushion nose to the table's outer edge. Not visual only:
	-- it also drives the barrier around the table (Placement.barrierHalfExtents), the rail
	-- extents ShooterStance stands the shooter and lays the rail bridge against, the rectangle
	-- CueClearance keeps the cue above, and the camera's whole-table fit. It must match the
	-- table mesh (tests/table_model_test.luau, coming with the new model).
	RailWidthInches = 7,
	-- Rail top height above the cloth as a fraction of the ball diameter (visual). The rubber
	-- cushion nose that the balls hit sits lower, see Physics.CushionNoseBallFraction.
	RailHeightBallFraction = 0.8,
	-- The rail crown, in inches above the cloth: the table mesh is built to it (Geometry.json
	-- rail.top) and measured against it, and the drawn cue must clear it (CueClearance). Not
	-- the fraction above: the parts fallback builds a lower rail (1.8 in), so clearing this
	-- clears both. The shooter's pose and the cue tuning sit on it (the stance sweeps pass
	-- from 2.08 to 2.16 and fail at 2.05 and 2.3), so changing it means retuning them.
	RailTopInches = 2.08,
	-- The chrome pocket caps stand a little proud of the rail: their measured crown
	-- (assets/table/Parameters.json, tests/table_model_test.luau). CueClearance takes the nearest a cue's line inside the
	-- rail passes to a pocket centre: within PocketCastingReachInches - PocketCastingBlendInches
	-- (3 in) the cue clears this full height, and from there the height it clears ramps
	-- linearly down to RailTopInches at PocketCastingReachInches (4 in), so the drawn pitch
	-- never jumps. The cue clearance tests start failing from about 2.35 in (2.351 with the
	-- 7 in or the 5.5 in rail), so the caps' crown has to stay under that.
	PocketCastingTopInches = 2.28,
	PocketCastingReachInches = 4.0,
	PocketCastingBlendInches = 1.0,
	-- Visible cloth-covered cushion strip: how far it reaches out from the cushion line into
	-- the wooden rail, and its height (a fraction of the ball diameter). Same height as the
	-- rail so cushion and wood sit flush; it also tucks under the wood a little so there is
	-- no seam.
	CushionWidthInches = 1.8,
	CushionHeightBallFraction = 0.8,
	CushionOverlapInches = 0.4,
	-- Slate/frame thickness below the cloth, visual only.
	BedThicknessInches = 2,
	-- Pockets, in ball diameters so they stay playable whatever ball size is chosen.
	-- Mouth = gap between the cushion noses. Tight tournament tables: corner 1.95-2.05
	-- diameters, side 2.15-2.25. (tune)
	CornerMouthBallFraction = 2.0,
	SideMouthBallFraction = 2.2,
	-- Jaw facings: the short angled cushion faces either side of each mouth. Side length in
	-- inches; the angle is measured off the rail line for corners (regulation 142 degree
	-- shelf = 38 off the rail) and off the perpendicular for sides (103 degree = 13 off).
	-- Corner length is derived to reach the shifted opening rim. Balls that enter at a bad
	-- angle hit these and rattle out. (tune)
	FacingLengthInches = 1.6,
	CornerFacingDegrees = 38,
	SideFacingDegrees = 13,
	-- Rounded jaw tips at the far end of each facing.
	JawRadiusInches = 0.3,
	-- The pocket OPENING: the hole in the slate the ball actually falls through, and the one
	-- circle used by physics and the generated table. Imported meshes need separate updates.
	-- At fraction 1.0 its radius is half the mouth width: side rims touch the mouth line,
	-- while corner rims sit CornerShelfInches behind it. Reducing this fraction adds shelf
	-- depth; off-centre entries also meet cloth near the jaws and can rattle or hang. (tune)
	PocketOpeningMouthFraction = 1.0,
	-- Corner shelf measured along the mouth bisector: WPA range 1-2.25 in at regulation
	-- diameter 2.25 in, target 1.5 in (PHYSICS_REALISM_PROMPT C). Scale with ball diameter.
	CornerShelfBallFraction = 1.5 / 2.25,
	CornerShelfInches = 0, -- derived below from CornerShelfBallFraction
	-- Safety net only: extra ball radii beyond the shifted corner extent. An escaped centre
	-- is taken by the nearest pocket; ordinary pocketing happens on the opening rim above.
	PocketShelfBallRadii = 0.9,
	-- The tip. A ball whose centre crosses the rim is no longer supported and pivots over the
	-- lip under gravity. A ball that crosses by a hair would balance there forever, so the
	-- tip starts from at least this angle off vertical; it is the number that caps how long a
	-- hang can last (1.5 degrees = about a third of a second). (tune)
	PocketTipMinDegrees = 1.5,
	-- The drop: once a ball's centre is over the hole it falls under gravity while the funnel
	-- shape pulls it towards the middle and the liner slows it. It stops this far down. (tune)
	PocketDropDepthInches = 5,
	-- The drawn pocket cup must be at least this deep below the cloth. That holds the physics
	-- drop, which the replay draws exactly: the drawn ball's bottom stops PocketDropDepthInches
	-- (5 in) down. It does NOT hold the rest of the fade: BallRenderer.animate keeps the ball
	-- falling under gravity and drifting outward for Effects.PocketFadeSeconds, its bottom
	-- reaching about 15.2 in down and its side up to 1.2 in past the hole's clear_radius
	-- (Geometry.json pockets.fade_depth and fade_drift). A 6.5 to 7 in floor is passed a fifth
	-- to a quarter of the way into the fade. The cloth is only 18.1 in up, so no cup inside
	-- the body holds all of that; the floor is near-black so the fading ball reads as falling
	-- into the dark, as on the old 6.5 in cups the drop was tuned on (2026-09-24). Holding the
	-- whole fade means shortening the renderer's fall, not deepening the cup.
	MinPocketDepthInches = 6.5,
	PocketFunnelAccel = 900, -- in/s^2 towards the pocket centre while dropping
	PocketDragPerSecond = 5, -- fraction of horizontal speed lost per second in the liner
	PocketWallRestitution = 0.25, -- bounce off the liner wall
	-- Filled in at the bottom of this file from the fractions above.
	RailHeightInches = 0,
	CushionHeightInches = 0,
	CornerMouthInches = 0,
	SideMouthInches = 0,
	-- Opening radius and side opening inset. Corner centres move CornerShelfInches
	-- diagonally outward from the table corner, leaving supported cloth beyond the mouth.
	CornerPocketRadiusInches = 0,
	SidePocketRadiusInches = 0,
	SidePocketInsetInches = 0,
	-- Head string: cue ball must start behind this on the break (1/4 of the length from the
	-- head rail).
	HeadStringFraction = 0.25,
	-- Foot spot: where the apex ball of the rack sits (1/4 of the length from the foot rail).
	FootSpotFraction = 0.25,
}

---------------------------------------------------------------------------------------------
-- Rack
---------------------------------------------------------------------------------------------
Config.Rack = {
	-- Tiny gap between racked balls. Real racks are never perfectly tight; a zero gap also
	-- makes the break resolve as one giant simultaneous contact. (tune)
	GapInches = 0.005,
	-- F: reproducible per-rack layout. Integer seed travels in TableState; zero normalizes
	-- to one for xorshift32. Jitter is per axis, bounded to at most a quarter of GapInches.
	DefaultSeed = 1,
	-- Largest rack seed the server draws for a new game (a positive 31-bit integer, so it
	-- survives the network and normalizeSeed unchanged).
	MaxSeed = 2147483647,
	JitterInches = 0.001,
	-- Standard layout by row from the apex: 8 in the middle, opposite groups in the back
	-- corners. Rows are listed from the apex (nearest the cue ball) backwards.
	Layout = {
		{ 1 },
		{ 9, 2 },
		{ 10, 8, 3 },
		{ 11, 4, 12, 5 },
		{ 13, 6, 14, 15, 7 },
	},
}

---------------------------------------------------------------------------------------------
-- Balls
---------------------------------------------------------------------------------------------
Config.Balls = {
	-- WPA regulation diameter 2.25 in; selected by the designer for collision physics.
	RadiusInches = 1.125,
	-- Cosmetic readability only, never used for collision/placement/cloth calculations.
	-- Modest 8% enlargement (tune 1-1.15) keeps the mesh legible without the old 2.6 in size.
	RenderScale = 1.08,
	RenderRadiusInches = 0, -- derived below; world visuals rest this radius above the cloth
	MassOunces = 6, -- WPA 5.5-6 oz; equal balls, also used in the cue/ball mass ratio
	-- Colours by number. 1-7 solids, 8 black, 9-15 stripes use the colour of (n - 8).
	Colors = {
		[0] = { 245, 240, 225 }, -- cue ball, warm white
		[1] = { 250, 200, 40 }, -- yellow
		[2] = { 30, 80, 200 }, -- blue
		[3] = { 210, 40, 40 }, -- red
		[4] = { 100, 40, 150 }, -- purple
		[5] = { 245, 120, 30 }, -- orange
		[6] = { 12, 92, 52 }, -- green: deep, so it stands out on the green cloth (designer, 2026-09-27: was 20, 130, 70)
		[7] = { 120, 30, 30 }, -- maroon
		[8] = { 20, 20, 22 }, -- black
	},
	-- Roblox's Reflectance mirrors the SKYBOX, so on an outdoor baseplate it mixes pale blue
	-- sky into every pixel and desaturates the colour. Phenolic resin is glossy, not a
	-- mirror: the highlight should come from SmoothPlastic's specular, not from this. Was
	-- 0.12, which was visibly washing the reds towards pink. (tune in the look pass)
	Reflectance = 0.04,
	-- The rendered ball rotation is built by multiplying CFrames every frame, which drifts
	-- off orthonormal and shears the ball. Rebuild it from squared-up axes this often.
	RotationRenormaliseSteps = 512,
	-- Draw both sides of the ball's faces. FALSE, and it should stay false.
	--
	-- This existed because tools/gen_ball_mesh.py used to wind its triangles INWARD, so
	-- Roblox culled the near surface and drew the inside of the far hemisphere instead -
	-- which moves the opposite way, so every ball looked like it span backwards. Turning
	-- culling off hid that, at the cost of lighting every ball as a back face, which is
	-- what made them look dull and metallic rather than like phenolic resin.
	--
	-- The mesh in the place is now wound outward (verified on the upload itself: 528 of 528
	-- faces point out), so neither is needed. Only set this true again for a mesh you know
	-- is inside out.
	DoubleSided = false,
	-- Real sphere mesh (assets/balls/ball_sphere.obj from tools/gen_ball_mesh.py), imported
	-- once into the place as ServerStorage.<MeshTemplate>; the server copies it into
	-- ReplicatedStorage.Assets at start-up. Missing = the old Part-and-decal balls.
	MeshTemplate = "BallMesh",
	-- One baked texture per ball (assets/balls/tex_<n>.png from tools/gen_ball_textures.py),
	-- uploaded 2026-09-19 and listed here by ball number. Empty = that ball falls back to decals.
	Textures = {
		[0] = "rbxassetid://86825559129906",
		[1] = "rbxassetid://133794362813004",
		[2] = "rbxassetid://115640228515562",
		[3] = "rbxassetid://71634972299335",
		[4] = "rbxassetid://102547838391993",
		[5] = "rbxassetid://132260486678576",
		[6] = "rbxassetid://103480111027469", -- deeper green, re-uploaded 2026-09-27
		[7] = "rbxassetid://85399541656812",
		[8] = "rbxassetid://139487783589064",
		[9] = "rbxassetid://92953629012840",
		[10] = "rbxassetid://125354706638427",
		[11] = "rbxassetid://80865252504873",
		[12] = "rbxassetid://139601741020258",
		[13] = "rbxassetid://127747571775456",
		[14] = "rbxassetid://71960739423576", -- deeper green, re-uploaded 2026-09-27
		[15] = "rbxassetid://136241349086894",
	},
	-- Decal asset ids, filled in once the generated images (tools/gen_ball_decals.py) are
	-- uploaded. Empty means "no decal": solids stay flat colour, stripes show as colour too.
	Decals = {
		-- [ballNumber] = white disc with the number, transparent elsewhere (uploaded 2026-09-18)
		Numbers = {
			[1] = "rbxassetid://122007386899145",
			[2] = "rbxassetid://113307385292300",
			[3] = "rbxassetid://78814354093891",
			[4] = "rbxassetid://108148105263771",
			[5] = "rbxassetid://79854355350181",
			[6] = "rbxassetid://71914329661380",
			[7] = "rbxassetid://86541103118320",
			[8] = "rbxassetid://118343664836744",
			[9] = "rbxassetid://77964766565740",
			[10] = "rbxassetid://139144048965936",
			[11] = "rbxassetid://80906907224369",
			[12] = "rbxassetid://128812375373796",
			[13] = "rbxassetid://111068179963368",
			[14] = "rbxassetid://137544599948534",
			[15] = "rbxassetid://83279339054393",
		} :: { [number]: string },
		-- one white band on transparent, tinted per ball with Decal.Color3
		StripeBand = "rbxassetid://134967770793162",
	},
}

---------------------------------------------------------------------------------------------
-- Physics (inches, seconds, radians)
---------------------------------------------------------------------------------------------
Config.Physics = {
	-- Fixed simulation step. Collisions inside a step are resolved event-by-event at their
	-- exact time of impact, so this only sets how often friction is integrated.
	FixedStep = 1 / 240,
	-- Gravity, used to turn friction coefficients into decelerations.
	Gravity = 386.09, -- 9.81 m/s^2 in inches per second squared
	-- Cloth friction while the ball SLIDES (contact point moving relative to the cloth).
	-- Dr. Dave properties / PHYSICS_RESEARCH section 3: range 0.15-0.4, typical 0.20.
	-- Higher = spin takes effect sooner and the skid resolves into a roll sooner.
	SlidingFriction = 0.20,
	-- Rolling resistance once the ball ROLLS without slipping. Dr. Dave TP B.2:
	-- range 0.005-0.015, typical 0.010. Higher = balls stop sooner. 0.0125 on 2026-09-30 to
	-- try (designer: a faster game; shots stop 5-20% sooner, the break pots the same).
	RollingFriction = 0.0125,
	-- Optional cloth coefficients, same TP B.2 range; the default above is independent.
	ClothPresets = { slow = 0.015, medium = 0.012, fast = 0.008 },
	-- Vertical-axis spin deceleration in rad/s^2, independent of radius. TP B.2 /
	-- pooltool via PHYSICS_RESEARCH section 3: typical range 5-15, target 10.9.
	SideSpinDecel = 10.9,
	-- Ball-ball restitution. Dr. Dave / pooltool: phenolic range 0.92-0.98, target 0.95.
	BallRestitution = 0.95,
	-- Ball contact friction vs total tangential slip speed (in/s). TP A.14's Marlow fit,
	-- sampled as specified in PHYSICS_REALISM_PROMPT B; coefficients span 0.010-0.118.
	-- Interpolate linearly and hold the endpoints, avoiding exp in deterministic replays.
	BallFrictionTable = {
		{ Speed = 0, Friction = 0.118 },
		{ Speed = 20, Friction = 0.072 },
		{ Speed = 40, Friction = 0.046 },
		{ Speed = 80, Friction = 0.022 },
		{ Speed = 120, Friction = 0.014 },
		{ Speed = 200, Friction = 0.010 },
	},
	-- Contact slip below this speed is treated as zero (in/s). Prompt B's 1e-9 numerical
	-- tolerance, kept far below SlideEpsilon; valid range 0 < value <= 1e-9.
	BallSlipEpsilon = 1e-9,
	-- Han/pooltool contact restitution, used when the speed table is empty; range 0-1.
	RailRestitution = 0.85,
	-- PHYSICS_REALISM_PROMPT C calibration: normal approach speed in in/s -> true-normal
	-- restitution. Published practical range 0.6-0.9; linear interpolation, endpoints held.
	-- The 300 in/s perpendicular stun benchmark retains about half its horizontal speed.
	RailRestitutionBySpeed = {
		{ Speed = 20, Restitution = 0.9 },
		{ Speed = 300, Restitution = 0.6 },
	},
	-- Height of the cushion nose above the cloth, as a fraction of the ball diameter.
	-- WPA specification: 0.635 +/- 0.01 (PHYSICS_RESEARCH section 3). Higher kills more
	-- top spin on the rebound; at 0.5 (ball-centre height) the cushion has no effect on spin.
	CushionNoseBallFraction = 0.635,
	-- Filled in at the bottom of this file.
	CushionNoseHeightInches = 0,
	-- Full tangential cushion friction coefficient. Han/pooltool default 0.2; Mathavan
	-- fitted 0.14 (research range 0.14-0.2). Side spin changes the rebound through this cone.
	RailFriction = 0.2,
	-- E's replay hook only: future server-authorized ability material, coefficients 0-1.
	-- No player can request it until the server has an ownership/cooldown authorization path.
	ShotMaterials = {
		SuperBounce = { RailRestitution = 1, RailFriction = 0 },
	} :: { [string]: { RailRestitution: number?, RailFriction: number? } },
	SeedPlaces = 1e6, -- six decimal places; preserve the existing authoritative replay seed
	-- Translation snaps to rest below this speed (in/s), once sliding has ended.
	-- PHYSICS_REALISM_PROMPT milestone A: 0.25, reduced from 1.0 to preserve slow creep;
	-- numerical cutoff, tune within 0-1. Side spin never holds a shot open by itself.
	RestSpeed = 0.25,
	-- Contact-point speed (in/s) under which a ball counts as rolling, not sliding.
	SlideEpsilon = 1e-4,
	-- Safety caps so a bad shot can never hang the game.
	MaxShotSeconds = 40,
	MaxEventsPerStep = 200,
	-- A ball that hits surfaces this many times within one step, each less than
	-- InstantHitSeconds after the last, is wedged and gets stopped.
	MaxInstantHits = 24,
	-- PHYSICS_REALISM_PROMPT milestone A: 1e-7 s, below the rack-gap closing time at
	-- break speed. Numerical tolerance (0 < value <= 1e-7), not a material property.
	InstantHitSeconds = 1e-7,
	-- Tiny separation kept between touching balls to avoid re-colliding forever.
	ContactSlop = 1e-5,

	-- Balls in the air (jump shots, Physics/Flight.luau; designer 2026-09-24). An elevated
	-- cue drives the ball down into the slate and it rebounds; a ball coming down bounces.
	-- Ball-slate coefficient of restitution: the rebound's upward speed over the downward
	-- speed. Dr. Dave's jump-shot analysis (TP B.10) uses 0.6; his FAQ gives 0.5-0.7, pooltool
	-- 0.5. 0.6 matches TP B.10's launch angles and clearing speeds (2026-09-24 realism
	-- review). (tune 0.5-0.7)
	SlateRestitution = 0.6,
	-- Ball-cloth friction during that bounce: turns skid and spin into each other like a
	-- very short slide. Same range as SlidingFriction. (tune 0.15-0.3)
	SlateFriction = 0.2,
	-- A rebound slower than MinHopSpeed (in/s) is swallowed by the cloth and the ball stays
	-- down (pooltool ignores bounces under about 5 mm the same way); ClothHopLossSpeed is
	-- taken off every rebound first (0: the review found any loss makes jumps harder than
	-- the published numbers). FlatStrikeBounce is the share of SlateRestitution a stroke at
	-- the default 4 degrees gets, rising to all of it at Cue.JumpCapDegrees: a near-level
	-- stroke barely presses the ball into the cloth and the cloth soaks it up. Together they
	-- keep ordinary shots on the table: only the top few percent of the power bar hops the
	-- cue ball, a whisker, and it pops off a nearby ball and off the table in a few percent
	-- of full-power shots. The designer asked for that to be rare (2026-09-24). (tune)
	ClothHopLossSpeed = 0,
	MinHopSpeed = 8,
	FlatStrikeBounce = 0.4,
	-- A ball coming down on top of another more slowly than PerchSpeed (in/s along the line
	-- of centres) stops bouncing and slides off the side at PerchSlideSpeed: no ball can
	-- balance on another, and without this it bounced there in ever smaller hops until the
	-- shot timed out (2026-09-24 fuzz). Numerical; 3-10 each.
	PerchSpeed = 6,
	PerchSlideSpeed = 6,
	-- While any ball is in the air the event search window is capped at this (s), so
	-- contacts with it can treat its curved path as straight. Numerical; 1/2400 bends by
	-- well under a thousandth of an inch. Keep within 1/4800 to 1/1200.
	AirStepSeconds = 1 / 2400,

	-- Simultaneous soft contact for touching balls (Physics/Cluster.luau). A contact that
	-- involves a ball already touching a third ball is integrated as Hertz spheres for as
	-- long as any of the group are pressed together, instead of one pairwise impulse at a
	-- time. Two balls on their own keep the exact pairwise model above.
	--
	-- Head-on contact duration at BallContactReferenceSpeed, in microseconds, of the
	-- undamped Hertz spring; it sets the stiffness. Duration scales with speed^-0.2 and the
	-- damping stretches it ~10%, so a real contact lasts ~220 us at 100 in/s and ~160 us
	-- at a 30 mph break. Hertz theory for phenolic balls (modulus 5-15 GPa) gives 200-310
	-- us at 100 in/s; 200 is the stiff end of that range.
	-- Why this model and value, from the 2026-09-22 break investigation (seeded full-power
	-- straight breaks from the break line): the pairwise engine pocketed 0.02 balls per
	-- break, sent 6.9 distinct object balls to a rail and left 11.5 in the foot quarter
	-- (200 seeds). At 200 us: 0.95 pocketed, 12.2 rail balls, 3.2 in the foot quarter.
	-- Across 100-400 us those stay within 0.9-1.1, 12.2-13.3 and 1.6-4.2, but the cue
	-- ball finishes further from the rack as contacts soften (19 in at 100 us, 31 at 200,
	-- 38 at 400), so the stiff end keeps a square break's cue ball nearest the centre.
	-- (tune 100-400)
	BallContactMicroseconds = 200,
	BallContactReferenceSpeed = 100, -- in/s; the speed the duration above is quoted at
	-- A ball within this gap (inches) of a third ball makes its contacts soft. Covers the
	-- rack's 0.005 in gaps plus jitter and balls left frozen together (ContactSlop apart),
	-- while two balls merely passing close stay pairwise. Tune 0.005-0.05.
	ClusterGapInches = 0.02,
	-- Fixed soft-contact sub-step (s): ~80 velocity-Verlet sub-steps across even a full
	-- break's contact, restitution within 0.0001 of BallRestitution from 1 to 528 in/s,
	-- and break statistics over 200 seeds matching those at 5e-7 and 1e-6 within noise.
	-- Cost scales with 1/step; the break's heaviest phase takes ~4.6 ms in Lune on a
	-- desktop at this value. Numerical, not physical: keep within 5e-7 to 3e-6.
	SoftContactStep = 2e-6,
	-- Safety cap on one soft phase (s). Real contacts let go well inside it (a whole rack
	-- does in about a millisecond); a phase reaching it parts any balls still pressed.
	SoftContactMaxSeconds = 0.003,
	-- A ball hopping into a group lower than this (inches above the ball it hits) still
	-- breaks it by soft contact, laid flat for the phase and kicked up after (Simulation's
	-- layFlat). Covers a hard break's hop; higher it is the pairwise 3-D contact. 0.3-0.6.
	SoftContactMaxHopInches = 0.5,
	-- Neighbour-list margin (inches) inside a soft phase: pairs further apart than contact
	-- plus this are skipped until the list is rebuilt. Performance only; 0.01-0.2.
	SoftContactSkinInches = 0.05,
}

---------------------------------------------------------------------------------------------
-- Cue strike: turns (power, spin offset) into the cue ball's initial velocity and spin
---------------------------------------------------------------------------------------------
Config.Cue = {
	-- Centre-hit horizontal target at full power. Designer chose one bar, no separate break,
	-- first reaching 30 mph (528 in/s); lowered to 25 mph (440 in/s) on 2026-09-30 to try
	-- (pros average about 24 mph on the break). At 25 mph a straight break (200 racks) pots
	-- 0.65 balls (1.00 at 30), pots one 47% of the time (67%) and scratches 6.5% (2%); every
	-- other power on the bar is about 15% slower too. TP A.30's impact gain derives the stick
	-- speed below. (tune 440-528)
	MaxSpeed = 440,
	-- Speed at the smallest power that still counts as a shot. (tune)
	MinSpeed = 15,
	-- TP A.30 / pooltool: 19 oz cue (typical 18-21), tip restitution 0.73 (0.70-0.85).
	-- Every collectible cue uses these same physical parameters; styles only change art.
	StickMassOunces = 19,
	TipRestitution = 0.73,
	-- TP A.31 ball/effective-tip-endmass ratio; typical 15-40, default 25 from prompt D.
	-- Only read while SideSpinBendsPath is on (it sets the squirt angle).
	EndmassRatio = 25,
	-- Designer 2026-09-23: side spin must not bend the aim line or the shot for now. True is
	-- real cue physics: side spin squirts the launch off the aim (about 2.2 degrees at the
	-- offset limit) and the tilted spin axis swerves the path on the cloth. It is kept for the
	-- later feature that will also curve the guideline. False: the cue ball leaves exactly
	-- along the aim and runs straight to first contact; side spin acts only at contacts
	-- (cushion rebound, throw, spin transfer). Draw and follow are the same either way.
	SideSpinBendsPath = false,
	MinStickSpeed = 0, -- in/s; derived below to preserve MinSpeed at a centre hit
	MaxStickSpeed = 0, -- in/s; derived below to preserve MaxSpeed at a centre hit
	-- power (0..1) -> speed uses power^PowerCurve, so the low end is finer.
	--
	-- This is a feel number, not a physics one, and it was the cause of every ball looking
	-- like it was on ice. MaxSpeed is a full BREAK; at the old 1.6 (with a 30 mph top) a
	-- half-pulled bar gave 184 in/s, which is a very firm real shot, and a ball struck that
	-- hard slides 128 inches before it rolls - longer than the 100 inch table. So nothing
	-- ever rolled. At 2.6 the usable middle of the bar lands on real pool shot speeds: half
	-- power is 85 in/s (with the 25 mph top), while the top of the bar is still a full break.
	-- (tune)
	PowerCurve = 2.6,
	-- Spin offsets are given in ball radii (-1..1). Hits beyond this miscue in real life.
	MaxSpinOffset = 0.5,
	-- Visual cue stick (placeholder built from parts), in STUDS so it matches the avatar. A
	-- true-scale 58 in cue would be 9.3 studs at this table's scale; the designer chose about
	-- 7 (2026-09-24), between that and the old 4.4 that looked like a toy next to an avatar.
	CueLengthStuds = 7,
	-- 0.36 approved 2026-10-04 (+12.5% over shape 2). Keep the slim front; ease the gain
	-- between 2.1 and 3.85 studs. Shape.json drives the shared mesh and its UV rebuild.
	CueButtDiameterStuds = 0.36,
	CueTipDiameterStuds = 0.09,
	-- The drawn cue's shape, tip to butt (CueShape). Each row ends at To (a fraction of the
	-- length, ascending to 1) and is drawn Taper of the way from the tip diameter to the butt
	-- diameter (0..1, never decreasing); Look picks its colour. CueClearance keeps the same
	-- shape clear of the rail and the balls, so what is drawn is what is tested.
	Profile = {
		{ To = 0.012, Taper = 0, Look = "Tip" },
		-- Unchanged shape-2 front, then quarter samples of the approved smoothstep widening.
		{ To = 0.3, Taper = 0.05537037037037, Look = "Shaft" },
		{ To = 0.3625, Taper = 0.37055555555556, Look = "Shaft" },
		{ To = 0.425, Taper = 0.4613818359375, Look = "Shaft" },
		{ To = 0.4875, Taper = 0.5752025462963, Look = "Shaft" },
		{ To = 0.55, Taper = 0.69552029079861, Look = "Shaft" },
		{ To = 0.78, Taper = 0.79875, Look = "Butt" },
		{ To = 1, Taper = 1, Look = "Butt" },
	},
	-- Resting gap between the tip and the cue ball while aiming (table inches), how far the
	-- stick draws back at full power on the bar (studs), and how much the butt is raised.
	CueRestGapInches = 2.5,
	CuePullBackStuds = 1.3,
	-- The PHYSICS elevation. Every shot starts at the default 4 degrees; internal level-cue
	-- benchmarks may use 0. The player raises it with the cue-angle slider in the spin panel
	-- (jump shots, designer 2026-09-24) up to MaxElevationDegrees, in whole steps of
	-- ElevationStepDegrees; ShotInput rejects anything else. The drawn cue's pitch
	-- (CueClearance) never drops below the chosen angle, and may tilt further to clear a rail
	-- or a ball, which is visual only. (tune the maximum 45-70)
	CueElevationDegrees = 4,
	MaxElevationDegrees = 60,
	ElevationStepDegrees = 1,
	-- The fastest stroke a raised cue can make (in/s at the tip). Nobody swings a cue raised
	-- 30-60 degrees over a bridge at break speed: Dr. Dave's jump analysis (TP B.10) calls
	-- 12 mph (211 in/s) a typical fast jump stroke. The top of the power bar comes down from
	-- MaxStickSpeed at the default angle to this by JumpCapDegrees, so a full-power jump rises
	-- tens of inches, not five feet (2026-09-24 realism review). (tune 180-260)
	JumpMaxStickSpeed = 211,
	JumpCapDegrees = 15,
	-- The drawn cue's tilt (CueClearance, VISUAL ONLY). It starts at CueElevationDegrees and
	-- tilts up just enough for the drawn cue's surface to clear the rail top (or a pocket
	-- casting) and every ball behind the cue ball by these gaps (table inches), never past
	-- VisualPitchMaxDegrees. Designer: 0.2 in clearance, 45 degree cap (2026-09-24).
	VisualPitchMaxDegrees = 45,
	VisualRailClearanceInches = 0.2,
	VisualBallClearanceInches = 0.2,
	-- Search resolution: the upward scan step past a blocking ball, and the bisection steps
	-- that then pin the pitch down (20 halvings of 41 degrees is well under 0.001). (internal)
	VisualPitchScanStepDegrees = 0.5,
	VisualPitchBisections = 20,
	-- How fast the drawn pitch follows its target (seconds): it rises fast so the cue never
	-- dips into a rail while turning, and settles slowly so it does not bob. (tune)
	VisualPitchRiseSeconds = 0.03,
	VisualPitchFallSeconds = 0.12,
	-- The shooter's own cue and rake fade out on their screen (LocalTransparencyModifier) as a
	-- part comes within this many studs of the camera, gone entirely at the camera itself, so
	-- a steeply raised butt swinging past the lens never blocks the view. Everyone else sees
	-- them whole. (tune)
	CameraFadeStuds = 1.5,
	-- Raised above CueElevationDegrees (a jump shot), the shooter's own cue is this see-through
	-- on their screen, so it never hides the ball and the arc (designer, 2026-10-02).
	-- Everyone else sees it whole. (tune)
	RaisedCueFade = 0.95,
	-- Any cue drawn more than this many degrees above CueElevationDegrees (lifted over a rail or
	-- a ball by CueClearance), or raised by the player at all, has every effect off, for
	-- everyone, until it comes back down or the shot is done (designer, 2026-10-06; the
	-- stick's AuraOff, CueSkinLook). The rail lift is small far out (+0.75 at 25 in from a
	-- rail, none past ~30 in) and steep close in (+3 at 15 in, +6 at 10 in, +19 at 5 in), so
	-- 2 means "visibly lifted": within about 17 in of a rail. (tune)
	RaisedFxOffDegrees = 2,

	-- What a cue LOOKS like is catalog data (2026-09-28): each Progression/Catalog row has a
	-- Look, and Catalog.style turns it into CueArt segments (tip, ferrule, shaft, joint ring,
	-- forearm with its accent band or rainbow bands, ring, wrap, cap) for the 3D stick
	-- (CueStickBuilder.paint) and the 2D cue in the power bar (PowerCue). The row's Effect
	-- names its Config.Effects.Styles row, which gives it its trail and pocket burst.
	--
	-- The cue drawn for a player with none equipped, or an id the catalog does not know: the
	-- catalog's default cue (Catalog.Default; tests/cue_looks_test checks they agree).
	DefaultStyle = "Classic",
	-- The player attribute the server sets to the catalog id of the cue they have equipped.
	-- Everyone's copy of that player's stick, the trail and pocket bursts of their shots, and
	-- their own power-bar cue follow it; nil (not loaded yet) draws DefaultStyle.
	EquippedAttribute = "EquippedCue",
	-- The 3D stick is drawn as coloured bands, each inside one piece of Profile (so the shape
	-- never changes) and one segment of the cue's style. A segment boundary this close to a
	-- Profile boundary (a share of the length; 0.012 is under a tenth of a stud) moves onto it,
	-- so a joint ring that nearly meets the shaft's step costs no sliver part of its own. Every
	-- stick is built with as many parts as the most banded catalog cue needs (a rainbow one:
	-- 14), and a plainer cue hides the spare ones. (internal)
	BandSnap = 0.012,
	-- The shared cue mesh (assets/cue, 2026-09-29): every cue with a skin (CueSkins) is drawn
	-- from it instead of bands, by a template ReplicatedStorage[MeshSkinsFolder][id] built in
	-- Edit mode by tools/build_cue_templates.luau (a Model whose PrimaryPart is the MeshPart
	-- with the skin's SurfaceAppearance, pivot on the tip, +Z toward the butt; a Frames folder
	-- holds a Legendary's extra SurfaceAppearances). A cue with no skin (the Unique cues) or no
	-- template keeps its bands, with one warning.
	MeshSkinsFolder = "CueSkins",
	-- The cue on every player's back (BackCue, designer 2026-09-28): their equipped cue, welded
	-- to BodyBackAttachment (R15 UpperTorso, R6 Torso), diagonal with the tip over the LEFT
	-- shoulder and the butt toward the right hip, the seam toward the body. Shown always,
	-- except while that player's cue is in their hands.
	Back = {
		-- The tilt from upright (degrees), tip toward the left shoulder. (tune)
		TiltDegrees = 36,
		-- The cue's axis sits this far behind the attachment (studs), off the back and over
		-- common back accessories; 0.35 since the cue grew 1.6x (2026-10-01). (tune)
		OutStuds = 0.35,
		-- Where along the cue (studs from the tip) it crosses the attachment: more than half the
		-- cue rises over the shoulder. (tune)
		GripFromTipStuds = 4.3,
		-- The butt stays at least this high above the floor (studs): on a small body the cue
		-- slides up instead of stabbing the ground. (tune)
		MinButtHeightStuds = 0.8,
		-- Sitting on a seat, the cue tilts this much further so its butt clears the seat cushion
		-- (checked on the lobby's loungers and sofas: their backrests hide the middle of the
		-- stick, the tip still shows over the shoulder). (tune)
		SeatedExtraTiltDegrees = 30,
		-- Only characters this close to the camera carry one (studs), from a pool of this many
		-- sticks built up front; who is near is looked at this often (seconds). (tune)
		MaxDistanceStuds = 90,
		PoolSize = 12,
		RefreshSeconds = 0.3,
		-- The camera this close to your own head is first person: your back cue hides. (internal)
		FirstPersonStuds = 1.0,
	},
}

---------------------------------------------------------------------------------------------
-- The hub: where the sixteen tables stand (studs). Physics x -> world X, physics y ->
-- world -Z, up -> world Y, all turned by the table's yaw. See src/shared/Placement.luau.
---------------------------------------------------------------------------------------------
Config.Hub = {
	-- How fast a player walks on the roof (studs a second): Roblox's 16 plus 30% (designer,
	-- 2026-09-26). A seated player's speed is saved and put back by TableService. (tune)
	WalkSpeed = 20.8,
	-- The rooftop map (assets/map/Spec.md, drawn in assets/map/Plan.png): four rows of four,
	-- turned sideways like the concept art, long sides to the entrance (+Z), the queue pad in
	-- front of each (Placement.queuePad). 36 studs apart across (the match fence's 26 plus a
	-- 10 stud aisle) and 31.5 deep (the match fence's 23.5 plus an 8 stud aisle), so every row
	-- is evenly spaced. Every table plays one mode, `teamSize` a side (designer,
	-- 2026-09-26): ten 1v1 at the front, the four 2v2 together (2 x 2) in the back city corner
	-- and the two 3v3 in the back ocean corner (designer, Checkpoint B); their looks are in
	-- TableModel.LookByTable. The positions come from assets/map/map_layout.py,
	-- and tests/map_layout_test.luau keeps the two equal. Y is the FLOOR height the table
	-- stands on, not the cloth: Placement.toWorld adds Table.SurfaceHeightStuds (2.9) on top.
	-- Yaw is degrees about world +Y; at 0 the length runs along world X, the head rail at -X.
	Tables = {
		{ id = 1, X = -54, Y = 0, Z = 47.25, YawDegrees = 0, teamSize = 1 },
		{ id = 2, X = -18, Y = 0, Z = 47.25, YawDegrees = 0, teamSize = 1 },
		{ id = 3, X = 18, Y = 0, Z = 47.25, YawDegrees = 0, teamSize = 1 },
		{ id = 4, X = 54, Y = 0, Z = 47.25, YawDegrees = 0, teamSize = 1 },
		{ id = 5, X = -54, Y = 0, Z = 15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 6, X = -18, Y = 0, Z = 15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 7, X = 18, Y = 0, Z = 15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 8, X = 54, Y = 0, Z = 15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 9, X = -54, Y = 0, Z = -15.75, YawDegrees = 0, teamSize = 2 },
		{ id = 10, X = -18, Y = 0, Z = -15.75, YawDegrees = 0, teamSize = 2 },
		{ id = 11, X = 18, Y = 0, Z = -15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 12, X = 54, Y = 0, Z = -15.75, YawDegrees = 0, teamSize = 1 },
		{ id = 13, X = -54, Y = 0, Z = -47.25, YawDegrees = 0, teamSize = 2 },
		{ id = 14, X = -18, Y = 0, Z = -47.25, YawDegrees = 0, teamSize = 2 },
		{ id = 15, X = 18, Y = 0, Z = -47.25, YawDegrees = 0, teamSize = 3 },
		{ id = 16, X = 54, Y = 0, Z = -47.25, YawDegrees = 0, teamSize = 3 },
	},

	-- How many tables to build, taken from the front of Tables.
	TableCount = 16,

	-- Which table the client treats as "the" table before it has a seat.
	ActiveTableId = 1,

	-- How many tables draw their balls at once. Sixteen racked tables is 256 ball meshes, and
	-- the ones across the room are a few pixels each. The nearest few are bound to a small
	-- pool of renderers instead; every table still simulates, it just may not be drawn.
	RenderedTables = 4,
	-- How often the pool is re-pointed at the nearest tables. Every frame is wasteful and
	-- the player cannot cross twenty studs in half a second.
	RebindEverySeconds = 0.5,
}

---------------------------------------------------------------------------------------------
-- Table model (imported from Blender, see assets/table/Readme.md and ARCHITECTURE section 7)
---------------------------------------------------------------------------------------------
Config.TableModel = {
	-- The imported template: a Model with this name in ServerStorage is cloned for every
	-- table; without it the parts-and-solid-modelling build is used (with one warning). The
	-- old seven-mesh ServerStorage.PoolTableModel stays in the place as the rollback until the
	-- designer signs the new table off. Its mesh names differ, so rolling back means reverting
	-- this code in git, not only changing this name.
	Name = "PoolTable",
	-- ServerStorage folder of looks: <LooksFolder>.<Look>.<Mesh> is a SurfaceAppearance.
	-- Generated in Edit mode by TableBuilder.prepareImport from Maps below (map ids are
	-- plugin-only writes, so they must be saved in the place); never edit it by hand.
	LooksFolder = "TableLooks",
	-- The eight meshes the template must contain, and how each behaves. CanCollide is for
	-- the walking character (CanQuery follows it; CanTouch is always off). Collision is the
	-- CollisionFidelity baked in Edit mode (colliding meshes only; the rest get Box, the
	-- cheapest). CastShadow is off for the small and flat parts (ARCHITECTURE section 7).
	-- AlphaMode is the SurfaceAppearance's (Overlay when absent); Marks is a transparent
	-- overlay just above the cloth. A mesh with an AlphaMode is hidden while its look has no
	-- SurfaceAppearance for it (no maps uploaded), since bare it would draw as solid grey.
	Meshes = {
		Cloth = { CanCollide = false, CastShadow = true },
		Rails = { CanCollide = true, Collision = "Box", CastShadow = true },
		Body = { CanCollide = true, Collision = "Box", CastShadow = true },
		Pockets = { CanCollide = false, CastShadow = false },
		Caps = { CanCollide = false, CastShadow = false },
		Hardware = { CanCollide = false, CastShadow = false },
		LogoPlate = { CanCollide = false, CastShadow = false },
		Marks = { CanCollide = false, CastShadow = false, AlphaMode = "Transparency" },
	} :: {
		[string]: {
			CanCollide: boolean,
			Collision: string?,
			CastShadow: boolean,
			AlphaMode: string?,
		},
	},
	-- The chrome pocket caps are their own mesh so they can go: false removes them from
	-- every table (the corners underneath are modelled finished).
	CapsMesh = "Caps",
	Caps = false, -- TEMPORARILY OFF (designer, 2026-09-24): to see the table without chrome caps
	-- The Marks overlay (the foot-spot sticker and the break smudge at the head spot) is its
	-- own mesh too: false removes it from every table, leaving plain clean cloth. Off
	-- (designer, 2026-09-24): "a new looking clean table".
	MarksMesh = "Marks",
	Marks = false,
	-- Map sets: uploaded image ids ("rbxassetid://digits"), "" until uploaded (an empty id is
	-- skipped, so a mesh with none keeps its bare part colour). Every table map is uploaded at
	-- 1024 (STUDIO_NOTES, "SurfaceAppearance facts"). A missing Metalness means non-metal.
	-- The Black and Cherry sets share their Normal and Roughness ids; only Color differs.
	-- Pockets, Caps and Hardware share the Parts atlas. Keep the unique ids within
	-- ImageBudget (tests/table_looks_test.luau counts them).
	Maps = {
		-- Uploaded 2026-09-24 from assets/table/textures (1024). Near-white repeating cloth tile
		-- (every 1.5 studs), tinted per look.
		Cloth = {
			Color = "rbxassetid://104070410744758",
			Normal = "rbxassetid://121047747339628",
			Roughness = "rbxassetid://132743328374369",
		},
		RailsBlack = {
			Color = "rbxassetid://72121062541710",
			Normal = "rbxassetid://92174527330284",
			Roughness = "rbxassetid://124817456406827",
		},
		RailsCherry = {
			Color = "rbxassetid://81503261228945",
			Normal = "rbxassetid://92174527330284",
			Roughness = "rbxassetid://124817456406827",
		},
		BodyBlack = {
			Color = "rbxassetid://135442205956199",
			Normal = "rbxassetid://91154183751639",
			Roughness = "rbxassetid://113070527451560",
		},
		BodyCherry = {
			Color = "rbxassetid://81072811464120",
			Normal = "rbxassetid://91154183751639",
			Roughness = "rbxassetid://113070527451560",
		},
		-- Leather, cups and chrome: the only set that needs a metalness map.
		Parts = {
			Color = "rbxassetid://94769619219469",
			Normal = "rbxassetid://136927565609550",
			Roughness = "rbxassetid://98528895126663",
			Metalness = "rbxassetid://126325716540474",
		},
		-- The plate with the game's logo (assets/table/LogoPlate.py; designer, 2026-10-06; the
		-- plain plate was rbxassetid://96049906872831).
		LogoPlate = { Color = "rbxassetid://132668892562034", Roughness = "" },
		-- RGBA overlay: sticker, rack patch, break streak, chalk, cushion and rim shading.
		Marks = { Color = "rbxassetid://76511654024840" },
	} :: {
		[string]: { Color: string, Normal: string?, Roughness: string?, Metalness: string? },
	},
	-- A look picks a map set for every mesh, and optionally a Tint: SurfaceAppearance.Color,
	-- RGB 0-255, which multiplies the colour map and is the one thing scripts may change at
	-- run time. Adding a look is a new row here plus maps, never new code.
	Looks = {
		-- Photo-16 blue cloth (about #01A9F7) with satin black wood.
		Blue = {
			Cloth = { Maps = "Cloth", Tint = { 1, 169, 247 } },
			Rails = { Maps = "RailsBlack" },
			Body = { Maps = "BodyBlack" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		-- The same tournament blue cloth on the regular lobby's cherry wood: the 1v1 tables
		-- (designer, 2026-10-06: blue as it always was, instead of green).
		BlueWood = {
			Cloth = { Maps = "Cloth", Tint = { 1, 169, 247 } },
			Rails = { Maps = "RailsCherry" },
			Body = { Maps = "BodyCherry" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		-- Yellow-green cloth with red-brown (cherry) wood. The tint aims at an albedo of
		-- #26A62A over the cloth map's ~0.95 grey. (tune)
		Green = {
			Cloth = { Maps = "Cloth", Tint = { 40, 175, 45 } },
			Rails = { Maps = "RailsCherry" },
			Body = { Maps = "BodyCherry" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		-- The team tables (designer, 2026-09-26). Raspberry red for 2v2 and slate charcoal for
		-- 3v3, each on either frame. Picked by colour difference (CIEDE2000) against every
		-- ball: raspberry keeps at least 17 from the red and maroon balls, slate 22 from the 8
		-- (the green cloth was 14.8 from the green ball, 31.6 since it went deeper on
		-- 2026-09-27). A truer red blends the red balls in.
		RedWood = {
			Cloth = { Maps = "Cloth", Tint = { 191, 38, 89 } },
			Rails = { Maps = "RailsCherry" },
			Body = { Maps = "BodyCherry" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		RedBlack = {
			Cloth = { Maps = "Cloth", Tint = { 191, 38, 89 } },
			Rails = { Maps = "RailsBlack" },
			Body = { Maps = "BodyBlack" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		CharcoalWood = {
			Cloth = { Maps = "Cloth", Tint = { 90, 94, 102 } },
			Rails = { Maps = "RailsCherry" },
			Body = { Maps = "BodyCherry" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
		CharcoalBlack = {
			Cloth = { Maps = "Cloth", Tint = { 90, 94, 102 } },
			Rails = { Maps = "RailsBlack" },
			Body = { Maps = "BodyBlack" },
			Pockets = { Maps = "Parts" },
			Caps = { Maps = "Parts" },
			Hardware = { Maps = "Parts" },
			LogoPlate = { Maps = "LogoPlate" },
			Marks = { Maps = "Marks" },
		},
	} :: { [string]: { [string]: { Maps: string, Tint: { number }? } } },
	-- The look every table uses unless LookByTable names another.
	DefaultLook = "BlueWood",
	-- Table id -> look. The regular lobby has wood frames (blue 1v1 since 2026-10-06, was
	-- green; red 2v2, charcoal 3v3) and the pro lobby black frames (blue 1v1, red 2v2,
	-- charcoal 3v3) (designer, 2026-09-26). This place is the regular lobby: the 1v1 tables
	-- take DefaultLook (blue)
	-- and the team tables their mode's wood look; see Hub.Tables for the modes. The
	-- black-frame looks stay for the pro lobby.
	LookByTable = {
		[9] = "RedWood",
		[10] = "RedWood",
		[13] = "RedWood",
		[14] = "RedWood",
		[15] = "CharcoalWood",
		[16] = "CharcoalWood",
	} :: { [number]: string },
	-- Most triangles over all eight meshes (Roblox caps each mesh at 20,000), and most unique
	-- 1024 images over every look (ARCHITECTURE section 7).
	TriangleBudget = 13000,
	ImageBudget = 18,
	-- TableBuilder.checkTemplate: how far the Rails footprint may be off the Config one
	-- ((Table.LengthInches or WidthInches + 2 * RailWidthInches) * StudsPerInch), as a
	-- fraction, before it is reported as a wrong Scale Unit or a 90 degree turn; and how far
	-- the pivot may sit off the table centre on the floor, measured at the rail crown
	-- (Table.SurfaceHeightStuds + RailTopInches * StudsPerInch above it) and the Rails centre.
	FootprintTolerance = 0.02,
	PivotToleranceStuds = 0.05,
}

---------------------------------------------------------------------------------------------
-- Look (colours are RGB 0-255, materials are Enum.Material names)
---------------------------------------------------------------------------------------------
Config.Look = {
	-- A lamp over every table (TableBuilder.build): a spotlight down on the cloth, no shadows,
	-- so a game stays easy to see at sunset (designer, 2026-09-26). Its brightness is the day
	-- cycle's (Config.Lighting's TableLights: off by day, lit at sunset). (tune)
	TableLight = {
		Enabled = true,
		Name = "TableLight", -- the lamp's part and its SpotLight (MapLighting finds them by it)
		HeightInches = 70, -- above the cloth
		Angle = 120, -- cone angle in degrees
		RangeStuds = 30,
		Color = { 255, 244, 225 }, -- warm white
	},
	-- Tournament blue cloth. With detail maps the part colour tints the map, so this is
	-- lighter than the final look. (tune)
	FeltColor = { 110, 165, 215 },
	FeltMaterial = "Fabric",
	-- Cloth detail: a MaterialVariant built at start-up from these PBR maps (generated with
	-- Studio's material generator on 2026-09-18, four candidates: PoolClothBlue, 1, 2, 3).
	-- Empty name = plain built-in Fabric. StudsPerTile sets how fine the weave repeats.
	FeltMaterialVariant = "PoolClothBlue",
	FeltMaps = {
		Color = "rbxassetid://104592584333753",
		Normal = "rbxassetid://126631440467468",
		Roughness = "rbxassetid://118902681046263",
		Metalness = "rbxassetid://107819495080440",
	},
	FeltStudsPerTile = 0.45,
	CushionColor = { 80, 130, 180 },
	RailColor = { 96, 42, 30 },
	RailMaterial = "Wood",
	FrameColor = { 58, 28, 20 },
	FrameMaterial = "WoodPlanks",
	BallMaterial = "SmoothPlastic",
	-- Pocket hole: colour and material of the leather casting and the shaft inside, and how
	-- deep the visible shaft goes below the cloth.
	PocketColor = { 12, 11, 11 },
	PocketMaterial = "Leather",
	-- The shaft floor sits this far below the cloth (deep enough to be in shadow).
	PocketShaftDepthInches = 9,
	ShaftColor = { 4, 4, 5 },
	ShaftMaterial = "Fabric",
	-- Leather U casting on the rail: how far it reaches out from the hole edge and how tall
	-- it stands above the rail; and the thickness of the leather lining the hole wall. The
	-- lining thickness also sets how much wider than the physics opening the hole is cut,
	-- so the lining's inner face sits exactly on the rim the ball drops through.
	PocketRingWidthInches = 1.1,
	PocketRingHeightInches = 0.35,
	PocketWallThicknessInches = 0.3,
	CueShaftColor = { 222, 190, 140 },
	CueButtColor = { 70, 40, 25 },
	CueTipColor = { 70, 110, 190 },
}

---------------------------------------------------------------------------------------------
-- Camera (studs, degrees)
---------------------------------------------------------------------------------------------
Config.Camera = {
	-- The one aim view. The camera orbits a focus point inside the table, on the side opposite
	-- the aim, so it always looks across the table in the aim direction. Every frame it solves
	-- for the closest distance (and the shallowest pitch) that keeps all four table corners on
	-- screen for the current viewport, so the whole table is always visible at the tightest
	-- framing the screen allows, and the view stays 3D. (all tune)
	View = {
		FieldOfView = 60,
		-- What sits at the centre of the screen: 0 = the table's outline, 1 = the cue ball,
		-- in between = the table shifted toward the ball (a bigger shift costs table size,
		-- since the fit has to back off to keep the far side on screen).
		FocusBallWeight = 0.15,
		-- Pitch above the cloth, degrees. The solver starts at Preferred and steepens toward
		-- Max only when a shallower angle cannot show the table as large on screen (a portrait
		-- phone with the table crosswise).
		PitchPreferred = 50,
		PitchMax = 65,
		-- The close view (fully zoomed in): low behind the cue ball looking down the aim line,
		-- this far from the ball and at this pitch, so the guideline runs into the distance.
		PitchClose = 30,
		CloseDistanceInches = 14,
		-- In the close view the camera looks this far ahead of the cue ball along the aim
		-- line (the ball sits low on screen and the guideline runs up into the distance).
		CloseLookAheadInches = 10,
		-- How far into the zoom (0 = fitted, 1 = fully close) the cue ball becomes the point
		-- the camera is centred on.
		CloseBallWeightAt = 0.5,
		PitchSamples = 6, -- pitches tried between Preferred and Max (internal)
		PitchBias = 0.06, -- fill advantage (fraction of screen) a steeper pitch must beat to win
		-- Fraction of the screen kept clear around the table.
		FitMargin = 0.05,
		-- Camera distance search range for the whole-table fit, in table inches (internal).
		DistanceMinInches = 40,
		DistanceMaxInches = 400,
		-- Seconds the camera takes to settle after an aim change (smaller = snappier).
		Smoothing = 0.18,
		-- Zoom: 1 = whole table fitted, ZoomMin = the close view. In between the camera moves
		-- in geometrically (equal scroll notches feel equal) while the pitch lowers and the
		-- centre shifts to the cue ball. Pinch on touch or scroll on PC.
		ZoomMin = 0.25,
		ZoomMax = 1.0,
		-- The HOME VIEW: where the camera sits whenever it is handed back to the player - the
		-- start of every turn, after every shot, and after calling a pocket for the 8. The
		-- exact midpoint of the zoom range, which is also the halfway point in SCROLL NOTCHES,
		-- because the distance is interpolated geometrically (see zoomedDistance in
		-- Camera.viewFor) - so this is the middle of the range however you measure it. At the
		-- 9 ft table that is 5.3 studs from the cue ball at a 35 degree pitch, against 10.1
		-- studs at 50 degrees fitted and 2.2 studs at 18 degrees closest.
		--
		-- A shot always ends here rather than at whatever the player had pinched to, so every
		-- turn starts from the same framing. Multiplayer uses this framing unchanged: no HUD
		-- shift. Only the whole-table end of the zoom is fitted clear of the match HUD,
		-- blended in between here and ZoomMax. (tune)
		ZoomDefault = 0.625,
		-- A turn that starts with the cue ball in hand (the break, or after a foul) opens this
		-- many mouse-wheel notches (Input.ZoomStep each) further out than the home view, so
		-- there is room to see where to put the ball. That turn's shot returns to the same
		-- framing; every other turn uses the home view. (tune)
		BallInHandZoomNotches = 2,
		-- On a phone (Camera.setBallInHand) every turn starts closer: the home view this many
		-- notches in, and a ball-in-hand turn (the break) opens this many notches out from
		-- that, instead of BallInHandZoomNotches (designer, 2026-09-27: the break was too far
		-- out on a phone; the pockets behind the cue ball may be off screen). (tune)
		PhoneZoomNotchesIn = 1,
		PhoneBallInHandZoomNotches = 0,
	},
	-- A ball dropping nudges the camera a hair TOWARD the pocket it went into. This is a
	-- reward, not an effect: it should register somewhere below conscious notice and never
	-- be the reason someone puts the game down with a headache.
	--
	-- Everything here is sized against that. The amplitude is a sixth of a stud, against a
	-- camera that sits 12 to 15 studs out - about half a percent of the view. It runs for a
	-- quarter of a second, and it swings barely more than once in that time, because it is
	-- FAST repeated motion that makes people feel sick rather than large motion. It is also
	-- horizontal only: a camera that bobs vertically is far more nauseating than one that
	-- slides.
	Shake = {
		Enabled = true,
		AmplitudeStuds = 0.16,
		Seconds = 0.26,
		-- Swings back and forth this many times while decaying. Keep it near 1: this is a
		-- nudge that settles, not a rumble. (tune)
		Oscillations = 1.25,
		-- A ball trickling in gets less of it than one hammered in, but even the gentlest
		-- drop still registers - a pocket that gave nothing back would feel broken.
		QuietSpeed = 20,
		LoudSpeed = 220,
		MinScale = 0.45,
	},
	-- While a shot plays the camera holds the framing it was taken from, then pulls out to a
	-- whole-table view (PullOutView) so every ball's path is visible, and goes back to the home
	-- view (View.ZoomDefault) when the balls stop.
	Shot = {
		ZoomOut = true, -- false = stay at the player's zoom during the shot
		FocusWeight = 0, -- gaze pull toward the moving cue ball: 0 = none, 1 = track it
		-- The camera does NOT leave at the strike. It holds the framing you shot from while
		-- the cue ball goes in, and only then pulls out to the whole table. The contact is
		-- the moment worth watching from where you aimed it; leaving immediately threw the
		-- view away at exactly the wrong instant and read as a lurch.
		--
		-- Half a second is long enough to see the cue ball leave and reach the first object
		-- ball on most shots, and short enough not to feel like a pause. It was 1.0, which
		-- was a wait. (tune)
		HoldSeconds = 0.5,
		-- ...but the hold is a fallback, not a rule. A ball leaving the screen ends it at
		-- once: a bank across the table can put a ball out of view well inside half a second,
		-- and holding then means staring at empty cloth while the shot happens somewhere
		-- off screen. This is what actually decides the timing on the shots that need it.
		--
		-- A ball counts as gone once its CENTRE reaches this fraction in from the screen
		-- edge (at the top, from the bottom of the match header, which hides the far end of
		-- the table on a phone), so the camera starts moving a moment before it truly disappears rather than
		-- after - by the time the centre is at the edge, half the ball is already outside.
		-- Raise it to leave earlier, drop it to 0 to wait for the ball to actually go. (tune)
		OffScreenMargin = 0.06,
		-- A shot too small to be worth leaving for at all. If the cue ball could not run this
		-- far even with a clear table (Cue.rollOutDistance, in table lengths), the camera
		-- stays exactly where the shot was taken from: a tap that moves the ball a few inches
		-- has nothing to show at the far end, and pulling out for it throws away the close
		-- view for no reason.
		--
		-- Measured against it, this is a sharp line rather than a fussy one, because power
		-- drives speed as power^2.6 (centre hit, 4 degree cue): 0.25 power runs 0.51 lengths,
		-- 0.30 runs 0.85, 0.35 runs 1.43, 0.37 runs 1.75 and 0.40 runs 2.36. The designer
		-- wanted shots of about 35% power and under to keep the aiming view (2026-09-23), so
		-- the line sat at 1.5 lengths, just above 35%. It was 0.5 (about 25%), which pulled
		-- out for shots that had nothing to show. Those lengths were at the 30 mph bar and
		-- 0.010 cloth; with the 25 mph bar and 0.0125 cloth (2026-09-30) every shot runs
		-- shorter, so the line moved to 1.0 length to stay at the same place on the bar (it
		-- crosses at 34.8%, where it crossed at 34.3%).
		--
		-- It is a BOUND on every ball, not just the cue ball - nothing leaves a collision
		-- faster than the ball that struck it - so this can hold the camera still on a shot
		-- where little happens, and never on one where something travels. OffScreenMargin
		-- above still overrides it: anything that does reach the edge pulls the camera out
		-- however gently it was hit. (tune)
		MinTravelTableLengths = 1.0,
		-- Where the pull-out goes (designer, 2026-09-26, a test). "Side": the camera swings
		-- round the table to a fixed semi-top-down view of all of it from one long side, the
		-- table centred, the same view every shot. It takes the long side that needs the
		-- smaller turn from where the shot was aimed, so the camera never turns more than about
		-- a quarter of the way round, and when the balls stop it swings back the same way.
		-- "Aim": the older pull-out, the whole table seen along the aim line.
		PullOutView = "Side",
		-- The "Side" swing out takes this long, eased in and out (smoothstep) and not smoothed
		-- on top, so the camera arrives at exactly this time. The designer chose about 0.9 s:
		-- quick enough to catch the balls rolling, gentle enough for a quarter turn. (tune)
		SidePullOutSeconds = 0.9,
		-- ...and the swing back to the aiming view once the balls stop, if it is still your
		-- turn. (tune)
		SideReturnSeconds = 0.9,
		-- A shot aimed within this many degrees of straight down the table's length needs about
		-- a quarter turn to either side; the camera then takes the side it already stands on,
		-- so it also travels less. (tune)
		SideTieDegrees = 5,
		-- How long the "Aim" pull-out to the whole table takes, eased in and out of the move
		-- (smoothstep) so it has no corners at either end. Smoothing below is applied on top,
		-- so the move actually lands somewhat after this: at 1.2 and 0.35 it took 1.6s to get
		-- 95% of the way out, which read as slow. Both came down together, because cutting
		-- only one of them leaves the other setting the pace. (tune)
		PullOutSeconds = 0.7,
		-- Seconds of easing while a shot is playing. The anchor is frozen for the whole shot,
		-- so during one this eases nothing but the pull-out above.
		Smoothing = 0.22,
		ReturnSmoothing = 0.6, -- seconds to ease back to the aim framing after the balls stop
		ReturnSeconds = 1.5, -- how long the slower easing applies after the shot ends
	},
}

---------------------------------------------------------------------------------------------
-- Live aim: opponents and spectators watch the shooter's cue turn
---------------------------------------------------------------------------------------------
Config.Aim = {
	-- How often a shooter tells the server where they are aiming. Ten a second is plenty for
	-- a cue that turns slowly, and the stream is unreliable, so a dropped one costs a frame of
	-- lag and nothing else.
	SendsPerSecond = 10,
	-- How often the server passes every table's aim (and cue-ball spot) on: its own clock,
	-- a little faster than the aim so a watched ball in hand keeps up with the drag.
	BroadcastsPerSecond = 15,
	-- While the shooter drags the cue ball in hand, its spot rides the same stream at this
	-- rate (only while it is actually moving), and watchers ease their copy of the ball
	-- toward each spot they hear over this many seconds.
	PlacementSendsPerSecond = 15,
	BallSmoothingSeconds = 0.1,
	-- Do not send at all unless the aim actually moved this far (radians). A player resting
	-- their thumb should cost nothing.
	MinChangeRadians = 0.004,
	-- How fast a watched cue eases to each new angle. The stream is a few a second; without
	-- easing the remote cue would visibly step.
	SmoothingSeconds = 0.08,
	-- The wind-up: how far the shooter has drawn the power (0..1) rides the aim stream so
	-- everyone watching sees the cue draw back. Sent in 1/PullSteps steps (and snapped again on
	-- the server): a change smaller than one step is not a change, so a resting thumb costs
	-- nothing.
	PullSteps = 50,
	-- How fast a watched cue eases to each new pull (seconds). Short, so a let-go reads as a
	-- stroke.
	PullSmoothingSeconds = 0.05,
	-- ARCHITECTURE.md section 4: the aim angle, the wind-up (pull) and the ball in hand travel;
	-- the guideline never does. On 2026-09-24 the designer accepted that opponents can read
	-- roughly how hard a shot will be. The pull is cosmetic: the shot's power comes only from
	-- ShotFired and is validated there.
}

---------------------------------------------------------------------------------------------
-- Avatar (the shooter's character at the table, R15 or R6)
---------------------------------------------------------------------------------------------
Config.Avatar = {
	-- How see-through the local shooter sees their own body (1 = invisible): while aiming and
	-- through the stroke, then in the idle stance at the shot spot while the balls roll. Only
	-- on their own screen: everyone else always sees the body whole.
	AimTransparency = 0.9, -- aiming and through the stroke
	IdleTransparency = 0.9, -- in the idle stance after the stroke
	-- Hats, hoods, wings and other accessories are hidden on the shooter's own screen (aiming
	-- and idle alike) so they cannot cover the table; the body stays a faded silhouette.
	HideAccessoriesWhileAiming = true,
	-- When the camera ends up close to the character (the ball at the near rail, aiming
	-- away), the character fades out completely so it never covers the cue ball. Fully
	-- invisible within FadeNearStuds of the camera, the normal transparency (AimTransparency
	-- or IdleTransparency) from FadeFarStuds out, blended in between.
	FadeNearStuds = 3,
	FadeFarStuds = 8,

	-- The posed shooter (AvatarPose), R15 and R6. ShooterStance decides where the body stands,
	-- how far the torso leans and where the hands go; these shape the rest of the body around
	-- that. Studs and degrees at normal avatar size.
	Body = {
		-- The hips tip further on a taller body: the profile's PelvisPitch is scaled by the
		-- body's standing root height over NominalStandStuds, kept within LeanScaleMin to
		-- LeanScaleMax. (tune)
		NominalStandStuds = 3,
		LeanScaleMin = 0.85,
		LeanScaleMax = 1.3,
		-- How far the body sways back at a full wind-up, following the cue. An R6 arm cannot
		-- bend to follow it, so an R6 body sways further instead. (tune)
		FollowStuds = 0.18,
		R6FollowStuds = 0.35,
		-- An R6 torso is one piece (no waist): it leans this share of the stance's torso lean,
		-- about the hip line, so it does not lie flat along the cue. (tune)
		R6TorsoPitchScale = 0.85,
	},
	-- The hips and chest in each stance mode (ShooterStance). Pairs are {at lean 0, at lean 1}
	-- over the stance's lean (stand is always at 0; lean, stretch and table run through their
	-- lean ranges).
	--   PelvisPitch          the hips tip forward this far (degrees, never past the torso)
	--   ChestPitch           the torso's lean when a pose has no stance angle (the stance's
	--                        torsoDegrees is used whenever it is given; degrees, on top of
	--                        PelvisPitch)
	--   HipTwistDegrees      the hips turn this much further open than the stance's facing
	--   ChestCounterDegrees  the chest turns back this much of that, about its own spine (so
	--                        the chin stays over the cue)
	--   ChestRollDegrees     the chest rolls this far, raising the grip-side shoulder
	--   HipBackStuds         the upper body sits back this far at full lean
	--   CrouchStuds          ...and this much lower
	--   LiftFrom             the back foot starts to lift at this lean (none: never lifts; the
	--                        designer wants both feet planted, 2026-09-25)
	-- The hips tip and twist only a little: R15 legs and hips are rigid blocks, and a pelvis
	-- turned well away from the thighs shows as a gap at the hips. (tune)
	Profiles = {
		stand = { -- hand bridge at the natural lean
			PelvisPitch = { 0, 10 },
			ChestPitch = { 5, 20 },
			HipTwistDegrees = 8,
			ChestCounterDegrees = 4,
			ChestRollDegrees = 0,
			HipBackStuds = 0.1,
			CrouchStuds = 0.05,
		},
		lean = { -- hand bridge, stretching further in
			PelvisPitch = { 10, 15 },
			ChestPitch = { 25, 45 },
			HipTwistDegrees = 8,
			ChestCounterDegrees = 4,
			ChestRollDegrees = 4,
			HipBackStuds = 0.2,
			CrouchStuds = 0,
		},
		-- Both feet on the floor, the belly against the rail edge.
		stretch = {
			PelvisPitch = { 10, 15 },
			ChestPitch = { 40, 70 },
			HipTwistDegrees = 8,
			ChestCounterDegrees = 4,
			ChestRollDegrees = 4,
			HipBackStuds = 0,
			CrouchStuds = 0,
		},
		table = { -- kneeling on the cloth, sitting back toward the heels
			PelvisPitch = { 25, 50 },
			ChestPitch = { 30, 70 },
			HipTwistDegrees = 10,
			ChestCounterDegrees = 5,
			ChestRollDegrees = 3,
			HipBackStuds = 0,
			CrouchStuds = 0,
		},
		rail = { -- kneeling up on the rail top (the last resort), as on the cloth
			PelvisPitch = { 25, 50 },
			ChestPitch = { 30, 70 },
			HipTwistDegrees = 10,
			ChestCounterDegrees = 5,
			ChestRollDegrees = 3,
			HipBackStuds = 0,
			CrouchStuds = 0,
		},
	},
	-- The head turns to look at the cue ball: this share of the way, never more than these
	-- angles from the chest (degrees). (tune)
	Head = {
		LookWeight = 0.85,
		MaxPitchDegrees = 70,
		MaxYawDegrees = 55,
	},
	Arms = {
		-- Where each elbow points, as a hint in the chest's axes {right, up the spine, back}:
		-- the grip elbow up, back and out; the bridge elbow out and down. (tune)
		GripPole = { 0.35, 0.55, 0.75 },
		BridgePole = { -0.9, -0.25, 0.2 },
		-- The grip hand turns this far at the wrist (degrees about its X). (tune)
		GripWristDegrees = -10,
		-- The bridge hand lies palm down, fingers along the cue dipping this far toward the
		-- cloth (degrees), its palm this far above the surface (studs). (tune)
		BridgeFingerDownDegrees = 15,
		BridgeLiftStuds = 0.05,
		-- The palm's centre is this share of the hand's length below the hand's centre.
		PalmFraction = 0.25,
		-- An arm reaching further than this share of its length straightens gradually rather
		-- than snapping (PoseMath.twoBone's soft reach), and its hand first slides to where the
		-- arm meets it: the grip along the cue (up to MaxGripSlideStuds, enough for the cue to
		-- slide back through a straight arm's hand over a whole wind-up, Cue.CuePullBackStuds;
		-- an R6 grip anywhere along the cue's back part), the bridge hand back along it
		-- (MaxBridgeSlideStuds). (tune)
		SoftReach = 0.97,
		MaxGripSlideStuds = 1.5,
		MaxBridgeSlideStuds = 0.8,
		-- ...and a hand is never brought nearer its shoulder than this share of the arm's
		-- length (folded tighter, an elbow cannot reach it): a grip that close slides along
		-- the cue too. (tune)
		MinReachFraction = 0.4,
		-- A relaxed off arm (no bridge to make) hangs straight down, its wrist this share of
		-- the arm's length below the shoulder. (tune)
		RelaxedReach = 0.95,
	},
	Legs = {
		-- Where the feet stand, {right, forward} studs from the root on the floor, in the
		-- stance's facing: the left (front) foot and the right (back) foot, each turned out
		-- ToeOutDegrees. (tune)
		FrontFoot = { -0.45, 0.35 },
		BackFoot = { 0.5, -0.45 },
		ToeOutDegrees = 15,
		-- A lifted back foot (a long lean) rises this far, moves this much further back and
		-- pitches this far toe down at full lift. (tune)
		BackLegLiftStuds = 0.8,
		BackLegLiftBackStuds = 0.5,
		BackFootPitchDegrees = 35,
		-- The hips come down just far enough that neither planted leg is straighter than this
		-- share of its length (so the feet stay on the floor with a hint of knee bend), but
		-- never more than MaxHipDropStuds. (tune)
		Straightness = 0.99,
		MaxHipDropStuds = 0.5,
		-- Kneeling on the table ("table"), the knees rest on the cloth (the stance's
		-- Table.KneeRestStuds up), each shin lying back along it with the foot pitched this far
		-- toe down, and the knees this far apart either side of the hips' own spread. (tune)
		KneelFootPitchDegrees = 70,
		KneelKneeSpreadStuds = 0.1,
	},
	-- The stroke once the shot is fired (ShooterPoser): the tip accelerates into the ball, rests
	-- on it until the replay has the ball moving, follows through past contact, holds there,
	-- and then the shooter stands up into the idle. Seconds and studs. (tune)
	Stroke = {
		Seconds = 0.1, -- the local shooter's stroke, from the wind-up to contact
		-- A watched shooter's: quicker, because their replay has already started by the time
		-- the stroke is seen.
		WatcherSeconds = 0.06,
		FollowThroughStuds = 0.35, -- how far past contact the tip goes
		FollowSeconds = 0.08, -- ...and how long it takes to get there
		HoldSeconds = 0.25, -- held at the follow-through before the idle
		-- The longest the tip rests on the ball waiting for the replay (a slow server): after
		-- this the stroke gives up and the shooter idles anyway.
		MaxWaitSeconds = 1.5,
	},
	-- How a posed body's root follows its stance (ShooterPoser). The hands are never eased:
	-- they stay on the cue. (tune)
	Motion = {
		-- The root eases toward a moving stance, settling in about this long (seconds).
		RootSmoothingSeconds = 0.12,
		-- ...but jumps straight there when it is more than this far away (studs), as it does on
		-- the first frame of aiming. A new pose (another side of the ball, up onto the rail)
		-- glides there instead, as long as it is nearer than this.
		SnapStuds = 12,
		-- The pose itself (lean, twist, the hips and the hands' targets) settles on a new
		-- stance in about this long (seconds); the hands are then put exactly on the cue.
		PoseSmoothingSeconds = 0.15,
	},
	-- Everyone else's shooter as this client poses them (WatchedShooters), only at the tables
	-- whose balls are drawn (Config.Hub.RenderedTables).
	Watch = {
		-- Beyond this distance from the camera (studs) a watched shooter is posed less often:
		-- a few pixels tall, a lower rate cannot be seen. (tune)
		FarStuds = 60,
		-- ...at most this many times a second out there (a stroke starting or the hand-over to
		-- idle still lands at once). Nearer, every frame. (tune)
		FarPosesPerSecond = 15,
		-- A posed body's parts stop colliding on this client until it is let go, so a body
		-- posed here over the rail can never shove this player's own character.
		NoCollidePosed = true,
	},
}

---------------------------------------------------------------------------------------------
-- Shooter stance (ShooterStance): where the shooter stands, sits or kneels and how they reach
-- the cue, in table studs. The client poses from it and the server places the root with it.
-- Avatars stay normal Roblox size, the cue its own length and the table its size; there is no
-- rake and no cue extension. A ball out of reach from the floor is reached by the body: one
-- foot on the floor stretching over the rail, then kneeling on the table (designer,
-- 2026-09-25).
---------------------------------------------------------------------------------------------
Config.Stance = {
	-- The body when a character cannot be measured, in studs above the floor: root centre,
	-- the hip line the torso leans about, the shoulder pivots, half the shoulder span, one
	-- arm from the shoulder pivot to the grip, the half extents of the body's footprint, the
	-- hip (leg) pivots, one thigh from its hip pivot to its knee pivot, the neck pivot, the
	-- neck pivot to the head's centre and the head's radius. The default R15 rig as
	-- AvatarPose.measureBody measures it in Studio (2026-09-24, the legs and head
	-- 2026-09-25; the default R6 rig measures 3.0, 2.0, 3.5, 1.0, 1.581, 1.0, 0.5, 2.0, 2.06,
	-- 4.0, 0.5 and 0.5, its leg being rigid).
	DefaultBody = {
		RootHeight = 3.192,
		WaistHeight = 2.592,
		ShoulderHeight = 4.039,
		ShoulderHalfWidth = 0.972,
		ArmReach = 1.931,
		HalfWidth = 1.0,
		HalfDepth = 0.58,
		HipHeight = 2.192,
		ThighLength = 0.921,
		NeckHeight = 4.29,
		HeadLift = 0.576,
		HeadRadius = 0.591,
	},
	-- The ways the body can stand to the cue, each tried at every support. TwistDegrees: the
	-- body faces this far right of the aim (a right-hander's hips turn away from the stroking
	-- arm). ChinSideStuds: the chin (the shoulders' centre) this far left of the cue (negative:
	-- right of it). Cost: how much less natural it is than the classic stance, in the units of
	-- Costs. (tune)
	--   classic     the open stance, chin over the cue
	--   classicOut  ...the cue by the right shoulder (the body a little off the line)
	--   side        turned along the cue with it running by the right hip, as a player stands
	--               at the side rail for a ball along it
	--   sideOut     ...further off, leaning in from outside the rail
	--   square      facing across the cue, reaching over the table with both arms
	--   squareOut   ...from further off
	--   closed      turned the other way, the cue under the left side of the chin
	Sides = {
		{ Name = "classic", TwistDegrees = 40, ChinSideStuds = 0.05, Cost = 0 },
		{ Name = "classicOut", TwistDegrees = 40, ChinSideStuds = 0.6, Cost = 1 },
		{ Name = "side", TwistDegrees = 10, ChinSideStuds = 0.75, Cost = 1.5 },
		{ Name = "sideOut", TwistDegrees = 10, ChinSideStuds = 1.4, Cost = 2.5 },
		{ Name = "square", TwistDegrees = 75, ChinSideStuds = 0.05, Cost = 2.5 },
		{ Name = "squareOut", TwistDegrees = 85, ChinSideStuds = 1.2, Cost = 3 },
		{ Name = "closed", TwistDegrees = -15, ChinSideStuds = -0.3, Cost = 2 },
	},
	-- How the search ranks the candidates of one support (the floor always beats the rail,
	-- the rail the table): a side's Cost, plus one per LeanDegrees of lean past the support's
	-- least, plus PerStudFromNatural per stud the root is from its natural distance; the
	-- side and support used last frame are Sticky cheaper, so it does not flip. (tune)
	Costs = {
		LeanDegrees = 15,
		PerStudFromNatural = 0.3,
		Sticky = 1,
	},
	-- Where the grip hand holds the cue: the arm reaches back along it toward the butt, the
	-- hand GripArmRestFraction of the arm's reach behind the shoulder at rest (a long wind-up
	-- slides the cue back through the hand once the arm is straight: Avatar.Arms
	-- MaxGripSlideStuds), never within GripButtEndStuds of the
	-- butt end and never nearer the tip than GripMinFromTipFraction of the length (a steep
	-- jump cue chokes up further, down to SteepGripMinFromTipFraction at SteepGripDegrees and
	-- above), and never more than GripAboveShoulderStuds above the shoulder: a steep cue
	-- chokes up instead. The body stands where a grip GripFromButtFraction of the length up
	-- from the butt sits GripBehindRootStuds behind the hip, when it can. (tune)
	GripArmRestFraction = 0.8,
	GripFromButtFraction = 0.15,
	GripButtEndStuds = 0.25,
	GripMinFromTipFraction = 0.35,
	SteepGripMinFromTipFraction = 0.15,
	SteepGripDegrees = 30,
	GripBehindRootStuds = 0.9,
	GripAboveShoulderStuds = 0.4,
	-- Torso lean from vertical on the floor, degrees: the natural stance, the most it
	-- stretches, and the most upright. A steeper drawn cue stands the body up by
	-- LeanUprightPerPitchDegree per degree of pitch. (tune)
	LeanNaturalDegrees = 45,
	LeanMaxDegrees = 85,
	LeanMinDegrees = 20,
	LeanUprightPerPitchDegree = 1,
	-- Arm reach as a fraction of the body's ArmReach: comfortable (the natural stance, and
	-- the start of a lean) and fully stretched (the end of a lean, the rail and the table,
	-- and the grip arm). (tune)
	ArmNaturalFraction = 0.8,
	ArmMaxFraction = 0.97,
	LeanBisections = 16, -- search steps for the least lean that reaches (internal)
	-- When the least lean that reaches leaves the root more than ExtraLeanFromStuds from its
	-- natural distance, these extra leans (degrees) are tried too, and the cheapest kept
	-- (Costs): a little more lean often lets it stand much nearer. The first must be 0. (tune)
	ExtraLeanDegrees = { 0, 4, 10 },
	ExtraLeanFromStuds = 0.5,
	-- Standing, the root keeps this far outside the rail's outer edge: the hips against the
	-- rail, the feet under its overhang. (tune)
	FloorGapStuds = 0.6,
	-- The root is always at least this far back along the cue from the strike point. (tune)
	UMinStuds = 0.8,
	-- Where the spot nearest the natural distance does not clear the table, the search steps
	-- out from it this far at a time for one that does. (internal)
	ClearStepStuds = 0.2,
	-- Stretching over the rail: both feet on the floor, the root from MinOutStuds to
	-- MaxOutStuds outside the rail's outer edge (the table's apron is flush with that edge, so
	-- the hips stay outside it), the belly allowed BellyIntoRailStuds into the rail top where
	-- it leans on the edge; the torso leans from LeanMinDegrees to LeanMaxDegrees. An avatar's
	-- legs are too short for any stance with the hips on the rail to keep a foot on the floor,
	-- so a shot this does not reach is taken kneeling on the table (designer, 2026-09-25).
	-- (tune)
	Stretch = {
		MinOutStuds = 0.4,
		MaxOutStuds = 1.0,
		BellyIntoRailStuds = 0.2,
		LeanMinDegrees = 40,
		LeanMaxDegrees = 90,
	},
	-- Kneeling on the table: the root at least KneelInsetStuds inside the cushion noses, the
	-- knee pivots KneeRestStuds above the cloth, the thighs leaning ThighBackDegrees back from
	-- upright; the torso leans from LeanMinDegrees to LeanMaxDegrees. The last resort, kneeling
	-- up on the rail top the same way (ShooterStance "rail"), keeps the root over the rail at
	-- least RailKneelOutStuds inside its outer edge, so the knees behind it stay on it. (tune)
	Table = {
		KneelInsetStuds = 0.5,
		RailKneelOutStuds = 0.8,
		KneeRestStuds = 0.15,
		ThighBackDegrees = 60,
		LeanMinDegrees = 20,
		LeanMaxDegrees = 88,
	},
	-- What the body must clear, studs (tune):
	--   TorsoFractions          the points up the torso (waist 0 to shoulders 1) checked
	--   TorsoHalfThicknessStuds ...each this far above whatever is under it
	--   ClothStuds, RailStuds   what counts as under: the cloth plus the balls on it, the rail
	--   HeadGapStuds            the head (the body's measured head, looking at the cue ball)
	--                           stays this far above whatever is under any part of it, so it
	--                           reads clearly above the table
	--   CueTorsoStuds           the cue keeps this far from those torso points
	--   CueHeadStuds            ...and this far outside the head
	Clearance = {
		TorsoFractions = { 0.35, 0.7 },
		TorsoHalfThicknessStuds = 0.3,
		ClothStuds = 0.4,
		RailStuds = 0.05,
		HeadGapStuds = 0.25,
		CueTorsoStuds = 0.3,
		CueHeadStuds = 0.05,
	},
	-- The hand bridge: the bridge arm reaches out toward the ball, the hand as far along the
	-- cue as BridgeArmExtendFraction of the arm's reach takes it (nearly straight, lining the
	-- cue up), but never nearer the cue ball than BridgeFromBallInches (table inches) nor
	-- within BridgeTipClearInches of the tip at a full wind-up; out of reach it may sit up to
	-- MaxBridgeInches back. On the cloth it stays BridgeCushionInsetInches clear of the
	-- cushion (BridgeFrozenInsetInches when the cue runs along it, nothing else left), on the
	-- rail RailBridgeInsetInches in from either rail edge, and never within
	-- PocketBridgeMarginStuds of a pocket's mouth. The cue passes between BridgeMinRiseStuds and
	-- BridgeMaxRiseStuds above the surface there (a steep cue with no such spot raises the
	-- hand under it); the hand's target is BridgeHandHeightStuds off the surface. Moving
	-- between the cloth and the rail costs BridgeRailHysteresisInches, so it does not flicker.
	-- (tune)
	BridgeArmExtendFraction = 0.95,
	BridgeFromBallInches = 6,
	BridgeTipClearInches = 1.5,
	MaxBridgeInches = 22,
	BridgeCushionInsetInches = 1.5,
	BridgeFrozenInsetInches = 0.3,
	RailBridgeInsetInches = 0.8,
	PocketBridgeMarginStuds = 0.1,
	BridgeMinRiseStuds = 0.1,
	BridgeMaxRiseStuds = 0.6,
	BridgeHandHeightStuds = 0.08,
	BridgeRailHysteresisInches = 1.0,
	-- A bridge nearer the ball than a full wind-up needs (on the rail by the cushion) scales
	-- the drawn wind-up down so the tip never passes it. Cosmetic: the shot's power is never
	-- touched.
	LimitPullAtBridge = true,
	-- The body's footprint stays this far inside the match fence. (tune)
	FenceMarginStuds = 0.2,
	-- The idle spot lands this far past the barrier so rounding never reads as inside it.
	-- (internal)
	SlopStuds = 1e-3,
}

---------------------------------------------------------------------------------------------
-- Input (mouse and touch share the same code path)
---------------------------------------------------------------------------------------------
Config.Input = {
	-- Aim rotation per pixel of horizontal drag. (tune)
	AimDegreesPerPixel = 0.18,
	-- Drags slower than this many px/s rotate at a reduced rate for fine aiming.
	FineDragSpeedPx = 80,
	FineAimScale = 0.35,
	-- A finger's drag turns the aim this much more than a mouse's (designer, 2026-10-02:
	-- a bit easier to aim on a phone).
	TouchAimScale = 1.15,
	-- Aim nudge buttons: step per tap, and repeat rate while held.
	NudgeDegrees = 0.2,
	NudgeRepeatDelay = 0.35,
	NudgeRepeatInterval = 0.06,
	-- Cue-angle buttons in the spin panel (D-pad up/down with L1, or the arrow keys): one
	-- ElevationStepDegrees step per press, repeating after this delay at this interval (s).
	ElevationRepeatDelay = 0.35,
	ElevationRepeatInterval = 0.07,
	-- Power bar: pulling this fraction of the bar's height gives full power, and the smallest
	-- power that still shoots (anything less on release cancels).
	PowerPullBarFraction = 0.9,
	MinPowerToShoot = 0.04,
	-- A finger on the power bar (PullGesture; designer, 2026-10-06: no more fat-fingered
	-- shots). Touch only; a mouse pulls as before. (tune)
	TouchPull = {
		-- The first this many pixels down do nothing and letting go there cancels; past it the
		-- bar clicks in at the softest shot (MinPowerToShoot). About a fingertip.
		DeadZonePx = 24,
		-- Once the finger has moved this far, the drag is decided: a pull, or sideways (aiming
		-- across the bar), which never shoots.
		LockPx = 12,
		SidewaysRatio = 1, -- sideways when across travel is more than this times the down travel
		MinHoldSeconds = 0.15, -- a press shorter than this never shoots
	},
	-- The bar's little bump when a finger pull clicks in past the dead zone (PowerCue).
	PullClickScale = 1.06,
	PullClickSeconds = 0.18,
	-- An aim tick fires every this many degrees of rotation. Fine enough that the smallest
	-- deliberate movement a player can make still clicks: a nudge tap is NudgeDegrees (0.2),
	-- which used to be a tenth of a tick and made careful aiming silent. What actually
	-- reaches the ear is held back by Audio.MinSecondsBetweenTicks, and by the frame rate -
	-- the accumulator below fires at most once per call, so a fast sweep cannot ask for more
	-- ticks than there are frames. (tune)
	TickEveryDegrees = 0.1,
	-- Zoom factor per mouse-wheel notch.
	ZoomStep = 1.12,
	-- Gamepad. Sticks are POLLED every frame, never driven by events: InputChanged only
	-- fires while a stick moves, so a stick held hard over reports nothing at all and an
	-- event-driven aim would stall the moment you stopped wiggling it.
	Gamepad = {
		-- Sticks rest slightly off centre; treat anything under this as centred.
		AimDeadZone = 0.15,
		ZoomDeadZone = 0.2,
		SpinDeadZone = 0.15, -- same stick-drift tolerance as aiming (0-1)
		SpinPerSecond = 0.55, -- ball radii per second while L1 + right stick adjusts the tip
		ElevationPerSecond = 30, -- cue-angle degrees per second at full L1 + left stick (tune)
		-- Aim rate at full deflection. The curve makes small pushes much finer, which is
		-- what the drag path gets from FineDragSpeedPx. 2 = a squared response.
		AimDegreesPerSecond = 80,
		AimCurve = 2,
		-- Ball in hand: hold LT and the left stick slides the cue ball at this many inches a
		-- second at full push, with the same squared response as aiming.
		PlaceInchesPerSecond = 30,
		PlaceCurve = 2,
		-- Zoom is applied as exp(stick * rate * dt), so it is smooth and frame-rate
		-- independent: a full push takes about e^1 = 2.7x per second.
		ZoomRatePerSecond = 1.0,
		-- ButtonA (Cross) is the shot: power ramps up while it is held, at this much per
		-- second, and releasing shoots. (R2 was an analog pull; it did not work well and is
		-- unbound, designer 2026-09-27.)
		PowerRampPerSecond = 1.1,
		-- A pull (A held) is called off when the left stick moves this far (0-1) from
		-- where it was as the pull began (designer, 2026-09-27: change your mind by aiming).
		CancelStickPush = 0.3,
		-- Y in the hub can leave the selection on the host menu or the opponent prompt, and
		-- a selected button takes the left stick from walking. A push harder than this that
		-- has not moved the selection after FreeStickSeconds (it hit the menu's edge) lets go
		-- of the menu so the player walks again.
		FreeStickPush = 0.8,
		FreeStickSeconds = 0.25,
	},
}

---------------------------------------------------------------------------------------------
-- Difficulty: how much of the guideline a table draws (GDD section 7). The host picks one
-- for the whole table in the queue menu, before the game (designer, 2026-09-25).
---------------------------------------------------------------------------------------------
Config.Difficulty = {
	-- Selected whenever a box fills up afresh and after every game.
	Default = "Classic",
	-- The menu's order, left to right.
	Order = { "Classic", "Difficult", "Challenger" },
	-- Money earned is multiplied by the table's difficulty (designer, 2026-09-26; shown under
	-- each difficulty in the host menu, paid once money exists, Roadmap 4.3). (tune)
	MoneyMultiplier = { Classic = 1, Difficult = 1.5, Challenger = 2 },
	-- What each level draws (src/client/Guideline.luau). Corridor: the aim line to the ghost
	-- ball and its ring. Stubs: the object ball's line and the cue ball's deflection or rail
	-- bounce. Landings: where a jump shot comes down. Arc: a jump shot's flight drawn in the
	-- air (Config.Guideline.Arc; designer, 2026-10-02: Classic only). The red X on a wrong
	-- target or an off table shot, and the glow on your own balls, stay on at every level.
	Levels = {
		-- every line (the default)
		Classic = { Corridor = true, Stubs = true, Landings = true, Arc = true },
		-- the aim line only
		Difficult = { Corridor = true, Stubs = false, Landings = false, Arc = false },
		-- no lines at all
		Challenger = { Corridor = false, Stubs = false, Landings = false, Arc = false },
	},
}

---------------------------------------------------------------------------------------------
-- Saves (src/server/PlayerData.luau over the vendored ProfileStore; the layout and its checks
-- are src/shared/Progression/SaveSchema.luau)
---------------------------------------------------------------------------------------------
Config.Save = {
	-- One DataStore for real saves and another for Studio, so testing never touches a real
	-- player's save. A new name starts everyone fresh: change it only on purpose.
	StoreName = "PlayerData_v1",
	StudioStoreName = "PlayerData_Studio_v1",
	KeyPrefix = "Player_", -- key = KeyPrefix .. UserId
	-- Hard caps a save can never pass (validate clamps to them). Far above any honest total;
	-- they only stop a bug from writing a nonsense number.
	MoneyCap = 1e12,
	RankXpCap = 1e9,
	StatCap = 1e9, -- every counter in Stats
	-- Save layout v2 (SaveSchema.validate): every map in a save is bounded, so a bug can never
	-- grow one without limit (a DataStore key holds at most 4 MB). Far above any honest need;
	-- validate keeps the entries with the smallest keys when a map is over its cap.
	MaxIdLength = 64, -- the longest key or id a save may hold (cue, block, title, code, user id)
	MaxCueEntries = 500, -- Inventory.Cues, .Unique, .New, Index.Seen, Shop.Limited
	MaxTitleEntries = 200, -- Titles
	MaxCodeEntries = 500, -- Codes redeemed
	MaxSmallEntries = 50, -- Index.Rows (rarities) and Daily.PlaytimeClaimed (gift indices)
	ItemCountCap = 1e6, -- copies of one cue
	CopyNumberCap = 1e6, -- a numbered Limited cue's copy number (#412)
	UnixTimeCap = 1e10, -- Shop.FirstJoin, unix seconds (1e10 is the year 2286)
	-- A receipt's PurchaseId (Shop.Purchases). Roblox's are about 30-40 characters; a longer
	-- one is kept up to this, since dropping a real id could grant a retried receipt twice.
	MaxPurchaseIdLength = 128,
	-- How long the join waits for a session (another server may be letting go of it) before
	-- kicking with Strings.Save.LoadFailed. Over a minute on purpose: a server that crashed
	-- still holds the lock, and ProfileStore only takes it over after about 45-50 s (its
	-- SESSION_STEAL); a shorter wait would kick that player on every rejoin for ten minutes.
	LoadTimeoutSeconds = 60,
	-- When a save is still held by the server a player just left (a teleport), ProfileStore asks
	-- it to let go and looks again after this long (its own default is 5 s). The global queue
	-- lets go before teleporting (PlayerData.handOff), so this is only the rare slow case.
	ConflictRetrySeconds = 1.5,
	-- The most one PlayerData.addMoney call may grant. Far above any honest reward; a bigger
	-- amount is a bug and is refused.
	GrantCap = 1e9,
	-- The most balls (or nice shots) one PlayerData.recordShot call may add.
	ShotCountCap = 100,
	-- PlayerData replicates every loaded save again this often (seconds), with no change to it:
	-- the RewardReady attribute depends on the clock (a new UTC day makes the daily streak
	-- claimable), so the red dot lights within this long of midnight.
	ReplicateRefreshSeconds = 30,
	-- Save layout v6 (2026-10-03, the economy plan): every save older than v6 starts over
	-- (designer: a full wipe, only friends had played), keeping only Shop.Purchases.
	MaxTradeHistory = 50, -- Trades.History: the last trades kept (designer, 2026-10-03)
	MaxAppliedTrades = 100, -- Trades.Applied: trade ids this save already applied
	MaxTradeSideItems = 8, -- items on one side of a trade (history entries too)
}

---------------------------------------------------------------------------------------------
-- Ranks (src/shared/Progression/Ranks.luau; GDD section 11). Every number is from
-- docs/ECONOMY.md section 4 (reworked 2026-10-02). One number, rank XP (the save's RankXp), is
-- the only progression, and it is never lost: nobody drops a division or a tier. XP comes only
-- from winning: 100 a win, 0 a loss, no Rookie, VIP or first-win boosts (designer, 2026-10-02).
-- Change a number here, in ECONOMY.md and in tools/economy_model.py together. (tune)
---------------------------------------------------------------------------------------------
Config.Ranks = {
	-- Bottom to top. Each has divisions I to V (I the bottom) except the last, which has one.
	Tiers = {
		"Bronze",
		"Silver",
		"Gold",
		"Platinum",
		"Diamond",
		"Expert",
		"Veteran",
		"Master",
		"Grandmaster",
		"Reyes",
	},
	DivisionsPerTier = 5,
	-- XP to climb through each division, I to V, per tier (ECONOMY 4.2), counted in wins of
	-- 100 XP: 1 win to Bronze I (a player is Unranked until their first win), 2 more to Bronze
	-- II, then 3, 4, 5... one more win each division to Platinum, then a steady ramp sized so a
	-- 3 h a day, 50% player reaches Expert in about a month, Veteran 2, Master 3.5,
	-- Grandmaster 6 and Reyes 9. The first win's 100 XP lands inside Bronze I, so it is 300 wide.
	-- Silver I starts at 2,100 XP (21 wins), Grandmaster I at 202,500 and Reyes at 307,500
	-- (tests/ranks_test checks these). Reyes has no top.
	DivisionXp = {
		Bronze = { 300, 300, 400, 500, 600 },
		Silver = { 700, 800, 900, 1000, 1100 },
		Gold = { 1200, 1300, 1400, 1500, 1600 },
		Platinum = { 1700, 1800, 1900, 2000, 2200 },
		Diamond = { 2500, 2800, 3200, 3600, 4000 },
		Expert = { 4500, 5000, 5600, 6200, 6900 },
		Veteran = { 7700, 8800, 10000, 11300, 12700 },
		Master = { 14300, 15700, 17000, 18000, 19500 },
		Grandmaster = { 20000, 20500, 21000, 21500, 22000 },
	},
	-- A match's XP against an equal opponent, by YOUR tier, before the mode, fade, gap, PC and
	-- streak (ECONOMY 4.2). One win is 100 XP at every tier and a loss gives nothing (designer,
	-- 2026-10-02): the ladder's widths carry the slope. Unranked plays by Bronze's row.
	BaseXp = {
		Bronze = { Win = 100, Loss = 0 },
		Silver = { Win = 100, Loss = 0 },
		Gold = { Win = 100, Loss = 0 },
		Platinum = { Win = 100, Loss = 0 },
		Diamond = { Win = 100, Loss = 0 },
		Expert = { Win = 100, Loss = 0 },
		Veteran = { Win = 100, Loss = 0 },
		Master = { Win = 100, Loss = 0 },
		Grandmaster = { Win = 100, Loss = 0 },
		Reyes = { Win = 100, Loss = 0 },
	},
	-- The table's difficulty multiplies XP (ECONOMY 4.2): a harder table's win is worth more.
	ModeXp = { Classic = 1, Difficult = 1.25, Challenger = 1.5 },
	-- Classic's WINS can fade up the ladder: { [tier] = factor }, a tier not listed keeps x1.
	-- Empty since 2026-10-02 (was x0.5 in Diamond, x0.2 from Expert): a Classic win is always
	-- a full win; Difficult and Challenger still pay more.
	ClassicWinFade = {} :: { [string]: number },
	-- Beating much lower players pays less (ECONOMY 4.4). gap = your division index minus the
	-- opponent's (Bronze I = 1 ... Grandmaster V = 45, Reyes 46; an Unranked player counts as
	-- Bronze I; a team uses the other team's average). E = 1 / (1 + 10^(-gap / scale)), factor
	-- = 2(1 - E), clamped to [floor, Max]. Gentle while YOU are below StrictFromTier (small
	-- servers may only have weaker players), strict from it.
	Gap = {
		Scale = 12, -- divisions, Bronze to Diamond
		Floor = 0.3, -- a win there is never worth less than 30%
		StrictFromTier = "Expert",
		StrictScale = 8, -- divisions, Expert and up
		StrictFloor = 0.1,
		Max = 1.5, -- beating a much stronger player pays at most this
		LossMax = 1, -- a loss's small XP uses the same factor, capped here
	},
	-- Against PC (bots, not built yet; ECONOMY 4.5): XP x Low while YOU are below
	-- Gap.StrictFromTier, x High from it. The rules take the opponent kind now.
	PcXp = { Low = 0.75, High = 0.5 },
	-- XP boosts ADD together, then multiply (ECONOMY 4.5): xp = round-half-even(base x mode x
	-- fade x gap x PC x (1 + boosts)). Only the win streak is left: it is skill (the Rookie,
	-- VIP and first-win-of-the-day boosts went on 2026-10-02).
	Boosts = {
		Streak = 0.25, -- each win from the StreakFrom-th in a row, against people (wins only)
		StreakFrom = 3,
	},
	-- A match counts only after this much server-tracked time from the break (GDD section
	-- 13). Under it, a forfeit or an early 8 pays nobody anything. (tune)
	RealMatchSeconds = 60,
	-- Difficulty unlocks by YOUR rank (ECONOMY 4.7): host Difficult and Challenger from Gold I
	-- (designer, 2026-10-02; Challenger was Diamond I). Ranks.canHost: the host card greys a
	-- locked level ("Requires Gold I+") and the server refuses it (TableService).
	Unlocks = { Difficult = "Gold", Challenger = "Gold" },
	-- Rank rewards, paid once, the first time you reach a division (PeakDivision passes it;
	-- ECONOMY 4.8). Step: the money for each new division II-V of a tier. Tier: reaching a
	-- tier's division I pays its money, its lucky blocks ({ [kind] = count }, into the hotbar)
	-- and the tier's cue (an Exclusive catalog id, never tradable or sellable). The chat tag
	-- comes from the tier itself (ChatTags).
	Rewards = {
		-- The approved economy plan (2026-10-02, section 6).
		Step = {
			Bronze = 1000,
			Silver = 2000,
			Gold = 3500,
			Platinum = 6000,
			Diamond = 15000,
			Expert = 30000,
			Veteran = 50000,
			Master = 80000,
			Grandmaster = 150000,
		},
		-- Blocks: lucky blocks by kind (a Mystery block rolls its tier with pity when opened).
		-- Bronze's block is given at once with the first win (the tutorial's Standard block);
		-- everything else waits until the player claims it in Rank (designer, 2026-10-03).
		Tier = {
			Bronze = { Money = 2500, Blocks = { Mystery = 1 }, Cue = "BronzeCue" },
			Silver = { Money = 5000, Blocks = { Rare = 1 }, Cue = "SilverCue" },
			Gold = { Money = 10000, Blocks = { Rare = 2 }, Cue = "GoldCue" },
			Platinum = { Money = 20000, Blocks = { Rare = 3 }, Cue = "PlatinumCue" },
			Diamond = { Money = 50000, Blocks = { Epic = 1 }, Cue = "DiamondCue" },
			Expert = { Money = 100000, Blocks = { Epic = 2 }, Cue = "ExpertCue" },
			Veteran = { Money = 200000, Blocks = { Epic = 3 }, Cue = "VeteranCue" },
			Master = { Money = 400000, Blocks = { Legendary = 1 }, Cue = "MasterCue" },
			Grandmaster = { Money = 750000, Blocks = { Legendary = 2 }, Cue = "GrandmasterCue" },
			Reyes = { Money = 2000000, Blocks = { Mythic = 1 }, Cue = "ReyesCue" },
		},
	},
	-- The [TIER] tag before a player's name in chat (src/client/ChatTags.luau; designer,
	-- 2026-09-27): tier only, in capitals, in these colours, which read on Roblox's dark chat
	-- window (the badge colours below do not all: Grandmaster's is near black). Reyes is the
	-- house rainbow, letter by letter. Unranked players get no tag.
	ChatColors = {
		Bronze = { 232, 150, 92 },
		Silver = { 205, 214, 228 },
		Gold = { 255, 205, 60 },
		Platinum = { 150, 200, 245 },
		Diamond = { 90, 230, 245 },
		Expert = { 255, 100, 105 },
		Veteran = { 100, 222, 125 },
		Master = { 195, 135, 255 },
		Grandmaster = { 255, 196, 40 }, -- the badge's gold (its black would vanish)
	},
	ChatRainbow = {
		{ 255, 77, 77 },
		{ 255, 159, 28 },
		{ 255, 225, 77 },
		{ 61, 214, 107 },
		{ 59, 155, 255 },
		{ 162, 89, 255 },
	},
	-- Each tier's colour, for the roadmap's rank card and the rank-up confetti.
	Colors = {
		Unranked = { 156, 163, 175 },
		Bronze = { 205, 127, 70 },
		Silver = { 170, 182, 200 },
		Gold = { 255, 196, 40 },
		Platinum = { 120, 176, 230 },
		Diamond = { 60, 214, 230 },
		Expert = { 232, 64, 72 },
		Veteran = { 64, 196, 96 },
		Master = { 158, 92, 230 },
		Grandmaster = { 60, 56, 70 },
		Reyes = { 255, 92, 184 },
	},
}

---------------------------------------------------------------------------------------------
-- Money (src/shared/Progression/Money.luau, paid by src/server/Economy.luau and Ranking;
-- GDD section 12). Every number is from docs/ECONOMY.md section 3, the economy plan the
-- designer approved on 2026-10-02 (all money x10 of the 2026-09-28 numbers). (tune)
---------------------------------------------------------------------------------------------
Config.Economy = {
	BallPay = 100, -- every ball that counts for the shooter's team (3.1)
	-- A nice shot pays this on top of its ball (Rules/NiceShot's kinds), to the shooter only.
	-- Never in solo (3.2).
	NiceShotPay = { Bank = 150, Kick = 150, Combo = 200, Carom = 200 },
	-- The match bonus at the end of a real match (3.1, 3.2), by opponent. The leaver gets
	-- nothing. The win bonus is multiplied by the opponent-gap factor (Config.Ranks.Gap) but
	-- never below WinBonusGapFloor of it (4.4); the loss bonus is not.
	WinBonus = 500,
	LossBonus = 150,
	PcWinBonus = 250, -- Play against PC (and a disguised bot past DisguisedDailyWins)
	PcLossBonus = 80,
	WinBonusGapFloor = 0.5,
	-- Win streak money (3.1): +StreakBonus on each win from the StreakFrom-th in a row,
	-- against people only (the same streak as the XP boost and the fire over the head).
	StreakBonus = 250,
	StreakFrom = 3,
	-- Team matches (3.3): every ball a team pots pays EACH teammate BallPay (with each
	-- player's own solo/short/PC rules); the nice-shot bonus goes only to the shooter.
	TeamBallPay = true,
	-- PC (3.2): after PcDailyCap of PC money in a UTC day, PC pays PcAfterCapShare of
	-- everything (rounded, never below $1 a ball).
	PcDailyCap = 10000,
	PcAfterCapShare = 0.5,
	-- Lucky blocks from Play against PC (3.2, 7.1): only the first PcDropsPerDay PC wins of a
	-- UTC day drop one.
	PcDropsPerDay = 10,
	-- Disguised bots (3.2; the queue's fallback bot, lobby bots): they pay like a person until
	-- the player has DisguisedDailyWins disguised wins in a UTC day; after that a disguised win
	-- pays the PC rows (PC bonuses, the PC cap) and drops no block. Hidden: nothing on screen
	-- says so (designer, 2026-10-03). Stops farming lobby bots in an empty server.
	DisguisedDailyWins = 20,
	-- Solo (3.2): this share of BallPay ($30) until SoloDailyCap has been earned in solo in a
	-- UTC day, then SoloAfterCapPay a ball. No nice shots, no bonus, no block drop in solo.
	SoloShare = 0.3,
	SoloDailyCap = 3000,
	SoloAfterCapPay = 10,
	-- Short matches (3.6): pots are paid live, but money from a match that ends before the
	-- one-minute mark adds to a daily short-match total; once that total reaches ShortDailyCap
	-- in a UTC day, balls potted before the one-minute mark pay ShortAfterCapPay each (and no
	-- nice-shot bonus) until the mark passes.
	ShortDailyCap = 2000,
	ShortAfterCapPay = 10,
	-- Boosts (3.5): money = base x difficulty x (1 + VIP + Money Party + Starter + group) on
	-- everything earned in play (balls, nice shots, match bonuses), never on rewards,
	-- sell-back or packs. They add (designer, 2026-10-03: VIP plus the Starter hour is x3).
	VipBoost = 1.0,
	PartyBoost = 1.0,
	StarterBoost = 1.0, -- the Starter Pack's hour of 2x money (Config.Shop.StarterBoostSeconds)
	GroupBoost = 0.1, -- a member of the game's group (Config.Social.GroupId; the InGroup attribute)
	-- A Roblox Plus (Premium) subscriber (designer, 2026-10-03, C14; the GUI lane): +10% if the
	-- economy model allows it (tools/economy_model.py), else 0.05. The RobloxPlus attribute.
	PlusBoost = 0.1,
	-- Anti-farm (3.6): the same opponent in one UTC day. Each row covers matches up to UpTo
	-- (the last row has no UpTo: every match after). Xp, Bonus and Balls multiply the match's
	-- XP, its win/loss bonus and its ball pay; Drop says whether the winner's lucky block
	-- can drop. In a team match the most-played opponent's count is used.
	SameOpponent = {
		{ UpTo = 5, Xp = 1, Bonus = 1, Balls = 1, Drop = true },
		{ UpTo = 10, Xp = 0.5, Bonus = 0.5, Balls = 1, Drop = false },
		{ Xp = 0, Bonus = 0.25, Balls = 0.5, Drop = false },
	} :: {
		{
			UpTo: number?,
			Xp: number,
			Bonus: number,
			Balls: number,
			Drop: boolean,
		}
	},
	-- The save's per-day opponent table keeps at most this many accounts; past it, a new
	-- account reads as the worst count (Settle.opponentDay), so a full table never switches
	-- anti-farm off. 300 (about 12 KB of save) is far above a real day: a 3v3 meets 3 new
	-- accounts at most, so even 100 team matches in a day stay inside it.
	SameOpponentMaxEntries = 300,
	DropsPerOpponent = 3, -- at most this many lucky blocks a day from beating one account
	DropLoserMinMatches = 5, -- the loser must have played this many real matches
	-- Pay the table's difficulty multiplier (Config.Difficulty.MoneyMultiplier: Difficult x1.5,
	-- Challenger x2). On since 2026-10-03 (the designer decided it 2026-09-26; it waited for
	-- the rank lock, which exists from Gold I).
	UseDifficultyMultiplier = true,
	-- The economy analytics (src/server/EconomyLog.luau; AnalyticsService:LogEconomyEvent for
	-- every money source and sink): each player's changes are added up by reason and sent once
	-- every FlushSeconds (and when they leave), so a match's many pots make one event.
	Analytics = {
		FlushSeconds = 60,
		Currency = "Money",
	},
}

---------------------------------------------------------------------------------------------
-- Block odds (src/shared/Progression/BlockOdds.luau and BlockDrop.luau): the odds tables every
-- lucky block rolls, the win's tier roll with pity, and cue sell-back. Every number from
-- docs/ECONOMY.md sections 7, 8 and 9 (2026-09-28; cases retired for lucky blocks 2026-10-04).
-- (tune)
---------------------------------------------------------------------------------------------
Config.BlockOdds = {
	-- The tier ladder, lowest first (the approved economy plan, 2026-10-02, section 3). A lucky
	-- block kind names the row it rolls (Config.LuckyBlocks.Kinds[kind].Odds).
	Order = { "Standard", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	-- Odds tables outside the ladder (the lucky-block economy, designer 2026-10-04): the Sky
	-- block (Lucky Rain), the Grand Opening block (21 days) and the Starter block (the Starter
	-- Pack). They roll the whole core pool (every block cue of a rarity), never the tier roll.
	Extra = { "Sky", "GrandOpening", "Starter" },
	-- Rarities, bottom to top (GDD section 12). Exclusive and Unique sit outside the ladder.
	Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	-- When sorting by rarity, Exclusive cues sit just above this rarity (below Legendary;
	-- designer, 2026-09-28). Unique sits above Secret.
	ExclusiveRanksAbove = "Epic",
	-- Odds are whole parts of OddsTotal (a million, so 0.0001% is 1), and each row adds to
	-- exactly OddsTotal (a load-time assert and tests/blockodds_test check it).
	OddsTotal = 1000000,
	List = {
		Standard = {
			Odds = {
				Common = 750000,
				Uncommon = 230000,
				Rare = 19900,
				Epic = 90,
				Legendary = 9,
				Mythic = 1,
			},
		},
		Uncommon = {
			Odds = {
				Common = 400000,
				Uncommon = 540000,
				Rare = 59500,
				Epic = 450,
				Legendary = 45,
				Mythic = 5,
			},
		},
		Rare = {
			Odds = {
				Uncommon = 700000,
				Rare = 296000,
				Epic = 3500,
				Legendary = 450,
				Mythic = 45,
				Secret = 5,
			},
		},
		Epic = {
			Odds = { Rare = 780000, Epic = 190000, Legendary = 26000, Mythic = 3600, Secret = 400 },
		},
		Legendary = {
			Odds = { Epic = 750000, Legendary = 220000, Mythic = 27000, Secret = 3000 },
		},
		Mythic = {
			Odds = { Legendary = 750000, Mythic = 220000, Secret = 30000 },
		},
		-- Lucky Rain's Sky block (plan section 7): between Standard and Uncommon.
		Sky = {
			Odds = {
				Common = 450000,
				Uncommon = 450000,
				Rare = 99000,
				Epic = 900,
				Legendary = 90,
				Mythic = 10,
			},
		},
		-- The Grand Opening block (plan 2.3): Uncommon or better plus two Unique rows that exist
		-- nowhere else, named by cue id: the Firework Cue 3% and the Beta Cue 0.3% (the
		-- 400th block guarantees Beta: Config.LuckyBlocks.Kinds.GrandOpening.Guarantee).
		GrandOpening = {
			Odds = {
				Uncommon = 563500,
				Rare = 374500,
				Epic = 25000,
				Legendary = 3500,
				Mythic = 460,
				Secret = 40,
				FireworkCue = 30000,
				BetaCue = 3000,
			},
		},
		-- The Starter Pack's block: Rare or better, guaranteed.
		Starter = {
			Odds = { Rare = 970000, Epic = 25000, Legendary = 4500, Mythic = 450, Secret = 50 },
		},
	},
	-- The win's block (plan section 2): every real win gives a Mystery lucky block; when it
	-- opens the server rolls its tier by Weights (out of OddsTotal), then that tier's row.
	-- Pity: the PityRare-th drop in a row without a Rare-or-better tier is Rare; the
	-- PityEpic-th without an Epic-or-better is Epic; pity never gives Legendary. The first
	-- win ever gives a FirstWin block instead (Progression/BlockDrop).
	Drop = {
		-- The tier roll (plan 4.2, trimmed 2026-10-04 so the day-30 targets hold with every
		-- new block source): Standard 68, Uncommon 25, Rare 6.7, Epic 0.28, Legendary 0.0196,
		-- Mythic 0.0004. A Mystery lucky block ticks through these tiers when it opens.
		Weights = {
			Standard = 680000,
			Uncommon = 250000,
			Rare = 67000,
			Epic = 2800,
			Legendary = 196,
			Mythic = 4,
		},
		PityRare = 10,
		PityEpic = 150,
		FirstWin = "Rare",
	},
	-- Selling a block cue back (section 8), by rarity. Exclusive and Unique never sell.
	SellBack = {
		Common = 150,
		Uncommon = 400,
		Rare = 1500,
		Epic = 25000,
		Legendary = 250000,
		Mythic = 2500000,
		Secret = 25000000,
	},
	ConfirmSellFrom = "Epic", -- the client asks "are you sure?" from this rarity up
	-- Unboxing one of these is announced in every server (7.4); AnnounceHere only in the
	-- opener's server (plan section 3: Legendary pulls).
	Announce = { Mythic = true, Secret = true },
	AnnounceHere = { Legendary = true },
}

---------------------------------------------------------------------------------------------
-- Lucky blocks (designer, 2026-10-03): the cue gacha. You hold a block, throw it on the floor
-- and open it with a 0.5 s hold. Blocks come from wins, rewards, the shop and trades (cases
-- retired 2026-10-04). Pure rules: src/shared/Progression/LuckyBlocks.luau;
-- server: src/server/LuckyBlockService.luau; client: LuckyClient, LuckyHotbar, LuckyWorld,
-- LuckyOpening. The models are Edit-mode content in ReplicatedStorage.LuckyBlocks (our own,
-- built by tools/luckyblock_build.py and tools/luckyblock_template.luau; assets/luckyblocks/).
---------------------------------------------------------------------------------------------
local BOX_IDLE = "rbxassetid://126596744037463" -- LuckyBoxIdle (2026-10-07)
local WING_IDLE = "rbxassetid://90314042377562" -- LuckyWingIdle (2026-10-07)
Config.LuckyBlocks = {
	-- Every kind, in this order (the Lune tests, the dev command's list and the icon sheet walk
	-- it; the 12 kinds of the lucky-block economy, designer 2026-10-04).
	Order = {
		"Standard",
		"Uncommon",
		"Rare",
		"Epic",
		"Legendary",
		"Mythic",
		"Mystery",
		"GrandOpening",
		"Lucky8",
		"Sky",
		"Starter",
		"Gift",
	},
	-- Saved ids from the test build (2026-10-03) and what they are now: read anywhere a kind
	-- is looked up, and rewritten when a save loads (SaveSchema).
	Renamed = {
		Yellow = "Standard",
		Green = "Uncommon",
		Blue = "Rare",
		VoidLava = "Epic",
		GoldKing = "Legendary",
	},
	-- Odds: the Config.BlockOdds row whose odds and cue pool it rolls (Roll = true instead:
	-- the Mystery block rolls a tier by Config.BlockOdds.Drop.Weights first and opens as that
	-- tier's block). Timer: seconds after it lands in the inventory until it can be opened (0:
	-- at once); a bought block (Paid) opens at once and VIP multiplies every timer by
	-- VipTimerFactor. Model: its
	-- template's name in ReplicatedStorage[ModelFolder]. Idle (optional): the block's own idle
	-- animation, uploaded to the group; without one it plays Anim.BlockIdle. Guarantee: the
	-- At-th block of this kind a player opens is this cue if they have none (a paid pity, shown
	-- live). Adding a block: the recipe in assets/luckyblocks/Readme.md.
	Kinds = {
		-- Our own models (designer, 2026-10-07): built by tools/luckyblock_build.py, pivot at
		-- the bottom of the block. Idle: LuckyBoxIdle (the pack's Box Idle on our rig) or
		-- LuckyWingIdle (the same hover, wings flapping), tools/luckyblock_anims.luau. A model
		-- wider or taller than the 4.66-stud cube (wings, toppers, a cloud) is scaled by its
		-- longest side, so SizeMultiplier = longest / 4.66 keeps its block as big as the
		-- others', and HoldCenterShare = the block's centre height / longest puts the block,
		-- not the wings, in the hands.
		Standard = { Odds = "Standard", Timer = 0, Model = "StandardBlock", Idle = BOX_IDLE },
		Uncommon = { Odds = "Uncommon", Timer = 0, Model = "UncommonBlock", Idle = BOX_IDLE },
		Rare = { Odds = "Rare", Timer = 3600, Model = "RareBlock", Idle = BOX_IDLE }, -- 1 hour
		Epic = { Odds = "Epic", Timer = 6 * 3600, Model = "EpicBlock", Idle = BOX_IDLE }, -- 6 hours
		Legendary = {
			Odds = "Legendary",
			Timer = 24 * 3600,
			Model = "LegendaryBlock", -- gold, with wings
			Idle = WING_IDLE,
			SizeMultiplier = 2.7, -- 12.6 studs wide (the wings)
			HoldCenterShare = 0.185,
			IconScale = 2.2, -- close in on the block
		},
		Mythic = {
			Odds = "Mythic",
			Timer = 48 * 3600,
			Model = "MythicBlock", -- pastel rainbow, halo and wings
			Idle = WING_IDLE,
			SizeMultiplier = 2.7, -- 12.6 studs wide (the wings)
			HoldCenterShare = 0.185,
			IconScale = 2.2,
			Rainbow = true, -- the client cycles its icon's aura through the rainbow
		},
		-- The tier roll's block (plan 2, 4.2): 5 minutes when won (none when bought); on
		-- opening it morphs into the tier's block and that block opens in the same flow.
		Mystery = {
			Roll = true,
			Timer = 300,
			Model = "MysteryBlock", -- frame C (flush rims), the moving rainbow
			Idle = BOX_IDLE,
		},
		-- The shop's hero for 21 days (Config.Shop.Deals.GrandOpening), then retired.
		GrandOpening = {
			Odds = "GrandOpening",
			Timer = 0,
			Model = "GrandOpeningBlock", -- gold, with a crown
			Idle = BOX_IDLE,
			Guarantee = { Cue = "BetaCue", At = 400 },
			SizeMultiplier = 1.4, -- 6.5 studs tall (the crown)
			HoldCenterShare = 0.36,
			IconScale = 1.2,
		},
		Lucky8 = { Odds = "Rare", Timer = 0, Model = "EightBallBlock", Idle = BOX_IDLE }, -- group + favorite
		-- Lucky Rain: a baby-blue block on a cloud, small wings.
		Sky = {
			Odds = "Sky",
			Timer = 0,
			Model = "SkyBlock",
			Idle = WING_IDLE,
			SizeMultiplier = 2, -- 9.2 studs wide (the cloud and wings)
			HoldCenterShare = 0.35, -- the block sits 0.9 studs up on its cloud
			IconScale = 1.6,
		},
		Starter = { -- the Starter Pack: red, gift-wrapped
			Odds = "Starter",
			Timer = 0,
			Model = "StarterBlock",
			Idle = BOX_IDLE,
			SizeMultiplier = 1.28, -- 6 studs tall (the bow)
			HoldCenterShare = 0.39,
			IconScale = 1.1,
		},
		Gift = { -- given the first time a player leaves (GDD); white, gold ribbon and clock
			Odds = "Rare",
			Timer = 12 * 3600,
			Model = "GiftBlock",
			Idle = BOX_IDLE,
			SizeMultiplier = 1.28, -- 6 studs tall (the bow)
			HoldCenterShare = 0.39,
			IconScale = 1.1,
		},
	},
	ModelFolder = "LuckyBlocks",
	-- A kind with Bob = true (a model without an animation; none now) hovers and turns by
	-- code once it has landed: this high, this fast.
	Bob = { HeightStuds = 0.35, Seconds = 2.4, TurnDegreesPerSecond = 30 },
	SkipProduct = "LuckyBlockSkip", -- 19 Robux: one durable timer skip
	VipTimerFactor = 0.5, -- VIP multiplies every block timer by this: twice as fast
	PlacementGapStuds = 3.5, -- keep adjacent floor blocks and their prompts apart
	PlacementAttempts = 24, -- nearby empty spots to try before asking the player to move
	LiveFolder = "LuckyBlocksLive", -- Workspace folder for thrown blocks (server-made)
	Look = {
		EmissiveStrength = 0.65, -- gentle texture-coloured fill in the rooftop's shadows/sunset
		LightBrightness = 2, -- non-standard blocks cast a small coloured pool of light
		LightRangeStuds = 7,
		ParticleLightInfluence = 0, -- sparkles keep their authored colours under warm lobby light
		-- The Mystery block's moving rainbow rims (designer, 2026-10-07): textures tagged Tag
		-- on a block's frame slide sideways, one rainbow every StudsPerTile studs.
		Scroll = { Tag = "LuckyScroll", StudsPerTile = 6, StudsPerSecond = 1.2 }, -- slower (designer)
	},
	MaxBlocks = 200, -- the save holds at most this many blocks
	-- A block that rolls a Unique cue the player already owns (one per player) is rolled again,
	-- at most this many times; then it gives the first cue of the row's top rarity.
	UniqueRerolls = 10,
	HotbarSlots = 9, -- the first 9 blocks sit in the hotbar (keys 1-9); the rest in the bag
	-- The test build: on join every account in Config.Debug.Commands.UserIds is given one of
	-- each Seed kind it lacks, and opening a block gives a fresh one of the same kind in the
	-- same place (its timer starting again), so testing never runs out.
	Test = {
		Seed = {
			"Standard",
			"Uncommon",
			"Rare",
			"Epic",
			"Legendary",
			"Mythic",
			"Mystery",
			"GrandOpening",
			"Lucky8",
			"Sky",
			"Starter",
			"Gift",
		},
		Refill = true,
		BypassTimer = true, -- only Config.Debug.Commands.UserIds; ReadyAt is left unchanged
	},
	-- BlockRequest's token bucket: this many at once, refilling this fast.
	RateBurst = 8,
	RatePerSecond = 4,
	-- Animations, all uploaded to the group (675425213) so they play in the game. BlockIdle:
	-- the pack's bounce, played on a thrown block whose kind has no Idle of its own. Hold and Throw: the arms (an empty id plays
	-- nothing), per rig.
	Anim = {
		BlockIdle = "rbxassetid://120822945598411",
		-- Built by tools/make_hand_anims.luau (assets/luckyblocks/anims), uploaded 2026-10-03.
		HoldR15 = "rbxassetid://97081574599269",
		ThrowR15 = "rbxassetid://127441949230799",
		HoldR6 = "rbxassetid://91317833672251",
		ThrowR6 = "rbxassetid://133046367802407",
		HoldFadeSeconds = 0.15,
		ThrowFadeSeconds = 0.05,
		ReleaseMarker = "Release", -- the throw's keyframe marker where the block leaves the hands
		ReleaseFallbackSeconds = 0.22, -- when there is no marker (or no animation), this long in
	},
	-- In the hands: the block's edge (studs) and where its centre sits against the upper torso
	-- (R15 UpperTorso, R6 Torso; +Y up, -Z forward). Built to match the Hold animation's hands.
	Held = {
		SizeStuds = 2.8, -- nearly twice the old edge: a big two-handed block
		OffsetR15 = { 0, 0.3, -2.1 },
		OffsetR6 = { 0, 0.1, -1.9 },
		TimerLiftStuds = 2.2, -- the countdown floats this far over the block's centre
	},
	-- The throw: the block lands this far in front of the root (shorter when a wall is
	-- closer), on the floor found under that spot, and flies there on an arc in Seconds.
	Throw = {
		DistanceStuds = 6,
		WallGapStuds = 1.5, -- stop this far short of a wall in the way
		FloorSearchStuds = 12, -- how far down to look for the floor
		ArcHeightStuds = 2.5,
		Seconds = 0.45,
		SpinTurns = 1, -- the block turns over this many times in the air
		LandYawJitterDegrees = 25, -- it lands facing the thrower, give or take this
	},
	FloorSizeStuds = 3, -- the block's edge once it is on the floor
	-- Opening: the owner holds E (gamepad X, or touch and hold the prompt) for HoldSeconds,
	-- within MaxDistanceStuds (the server checks the distance again, with SlackStuds).
	Open = {
		HoldSeconds = 0.5, -- native prompt: a quick half-second hold
		MaxDistanceStuds = 10,
		SlackStuds = 4,
		PromptLiftStuds = 2.4, -- the prompt floats this far over the block's base
	},
	-- After the hold: the block rises and spins faster and faster, then bursts and the reel
	-- opens. Spin in turns a second, easing from SpinStart to SpinEnd.
	Rise = {
		HeightStuds = 4,
		Seconds = 1.4, -- one second shorter before the burst/reel
		SpinStart = 2, -- visibly spinning from the start
		SpinEnd = 9,
		ShakeStuds = 0.12, -- a growing shiver near the top
		GlowBoost = 3, -- its light and particles grow to this many times as it rises
	},
	BurstSeconds = 0.35, -- the pop at the top: it swells and fades, then is gone
	BurstScale = 1.6,
	-- A thrown block nobody opens goes back to the hotbar after this long, or as soon as its
	-- owner is this far away (it never leaves the save until it is opened).
	ReturnSeconds = 60,
	ReturnStuds = 60,
	CheckSeconds = 1, -- how often the server looks for blocks to return
	-- The screens (LuckyHotbar, LuckyWorld, LuckyOpening).
	UI = {
		SlotPx = 64, -- a hotbar slot, square (phone: PhoneSlotPx)
		PhoneSlotPx = 48,
		PhoneWidthPx = 900, -- a screen narrower than this uses the phone sizes
		-- A phone's hotbar shows only the first blocks (designer 2026-10-07: 9 was too crowded);
		-- the rest wait in the bag ("+n").
		PhoneHotbarSlots = 3,
		SlotGapPx = 6,
		SlotCornerPx = 12,
		SlotStrokePx = 2.5,
		SelectedStrokePx = 4, -- the held block's slot: a thick gold outline
		SlotFillTransparency = 0.35, -- the slots' ink fill, see-through over the world
		BottomPx = 10, -- the hotbar's gap from the bottom of the screen
		NumberPx = 14, -- the slot's number, top-left
		TimerPx = 14, -- the countdown along the slot's bottom
		IconTurnDegreesPerSecond = 30, -- the 3D icon turns slowly
		IconFieldOfView = 30,
		IconAmbient = 1, -- neutral fill keeps every turning face bright in the bag/hotbar
		IconLight = 2, -- brighter directional key; retains the original texture colours
		IconLightDirection = { -1, -2, -1.5 }, -- above and in front of the preview
		IconDistance = 3.1, -- the icon camera's distance, in block edges
		IconAboveShare = 0.3, -- the camera this far above the block's middle, in block edges
		-- The Mythic block's aura on its icons (the shop's cards, the hotbar and the bag; a
		-- kind with Rainbow = true): a soft glow behind the block cycling through pastels.
		RainbowAura = {
			Seconds = 5, -- one trip round the colours
			Reach = 2.2, -- the glow's size, of the icon's (a soft image: big and solid reads)
			Transparency = 0,
			Colors = {
				{ 255, 170, 190 },
				{ 255, 214, 150 },
				{ 255, 250, 160 },
				{ 170, 255, 190 },
				{ 160, 220, 255 },
				{ 210, 170, 255 },
			},
		},
		BagButtonPx = 44, -- the bag button at the hotbar's end (touch and mouse)
		BagCountPx = 14, -- "+12" on it: blocks waiting in the bag
		-- The bag panel (` key, the bag button, L3 on a gamepad): a grid of every block.
		BagColumns = 6,
		BagRowsShown = 3,
		BagPadPx = 12,
		BagTitlePx = 26,
		BagHintPx = 16,
		BagGapAbovePx = 12, -- between the panel and the hotbar
		DragThresholdPx = 8, -- a press that moves this far is a drag
		ShakeWords = 1.6, -- "Ready in 1:42" shows this long over the hotbar
		NoticePx = 22,
		-- The world countdown; Roblox draws the native open prompt.
		BillboardTimerPx = 24,
		-- Lifts for the bottom-centre prompts (OpponentPrompt, claim block,
		-- Collect) while the hotbar shows, so they sit over it.
		LiftPx = 80,
		PhoneLiftPx = 62,
		-- The dark reel (LuckyOpening): a very see-through grey-black over everything, so the
		-- world still shows through (designer, 2026-10-03: no white panel).
		DimColor = { 12, 14, 22 },
		-- 1: no dim any more, the world blurs instead (Config.UI.Blur; designer, 2026-10-06).
		-- Was 0.35. The clear layer still takes the reel's taps.
		DimTransparency = 1,
		DimSeconds = 0.25,
		DisplayOrderAbove = 16, -- over the HUD screen
		TileFillTransparency = 0.45, -- each reel tile: a dark see-through card...
		TileStrokePx = 2, -- ...with a slight border in its rarity's colour
		TileStrokeTransparency = 0.25,
		RarityTextPx = 16, -- "Epic" in its colour, under the name
		-- A tile's rows, as shares of its height (thumbnail middle, then the tops of the name,
		-- the rarity and the chance).
		TileThumbCentreShare = 0.33,
		TileNameTopShare = 0.58,
		TileRarityTopShare = 0.7,
		TileOddsTopShare = 0.82,
		ReelFadeShare = 0.12, -- the strip fades out over this share of its width at each end
		-- The result card: "YOU GOT <CUE>!" with turning rays in the rarity's colour.
		CardWidthPx = 460,
		CardArtPx = 220,
		CardTitlePx = 40,
		CardNamePx = 30,
		CardRarityPx = 24,
		CardHintPx = 18,
		CardRaysImage = "rbxassetid://103944500004159", -- 1024px soft rays, transparent edges
		CardRaysShare = 1.8, -- the rays' size, of the card's width
		CardRaysTransparency = 0.35,
		CardRaysDegreesPerSecond = 25,
		CardInSeconds = 0.35,
		CardDismissAfterSeconds = 0.6, -- a tap before this does nothing (no accidental skip)
		MinScale = 0.55,
		MaxScale = 1.4,
		MarginPx = 12,
	},
}

---------------------------------------------------------------------------------------------
-- A bot's equipped cue (src/shared/Progression/BotCues.luau; the Bots lane's Look.cue calls
-- it): its rarity matches what real players at that rank own (the approved economy plan,
-- 2026-10-02, section 3). Each row is the chance the cue is that rarity or better; the rest
-- (Common, Uncommon, Rare) is spread by the Mystery block's odds. Mythic+ is a Mythic: a bot
-- never shows the Secret cue (lane decision, 2026-10-03). (tune)
---------------------------------------------------------------------------------------------
Config.BotCues = {
	Bronze = { EpicPlus = 0.05, LegendaryPlus = 0.008, MythicPlus = 0.001 },
	Silver = { EpicPlus = 0.1, LegendaryPlus = 0.015, MythicPlus = 0.002 },
	Gold = { EpicPlus = 0.2, LegendaryPlus = 0.03, MythicPlus = 0.004 },
	Platinum = { EpicPlus = 0.34, LegendaryPlus = 0.06, MythicPlus = 0.008 },
	Diamond = { EpicPlus = 0.5, LegendaryPlus = 0.1, MythicPlus = 0.013 },
	Expert = { EpicPlus = 0.7, LegendaryPlus = 0.16, MythicPlus = 0.02 },
	Veteran = { EpicPlus = 0.88, LegendaryPlus = 0.26, MythicPlus = 0.04 },
	Master = { EpicPlus = 0.97, LegendaryPlus = 0.4, MythicPlus = 0.065 },
	Grandmaster = { EpicPlus = 0.99, LegendaryPlus = 0.58, MythicPlus = 0.11 },
	Reyes = { EpicPlus = 0.99, LegendaryPlus = 0.7, MythicPlus = 0.15 },
}

---------------------------------------------------------------------------------------------
-- The Index (src/shared/Progression/Inventory.luau): completing a rarity row (every cue of
-- that rarity ever owned; selling one later keeps it counted, and a vaulted cue still counts)
-- pays once. ECONOMY section 18 (2026-09-28). (tune)
---------------------------------------------------------------------------------------------
Config.Index = {
	-- The money a complete rarity row pays once, claimed in the Index. Rows not listed have no
	-- reward: Legendary, Mythic and Secret (money there would reward luck more than play),
	-- Exclusive and Unique. The rows' "Collector" titles are gone (designer, 2026-09-28).
	Rows = {
		Common = { Money = 10000 },
		Uncommon = { Money = 25000 },
		Rare = { Money = 75000 },
		Epic = { Money = 250000 },
	},
	-- The finder's money (designer, 2026-09-28): the first time a player gets a cue (it enters
	-- their Index), the server pays this much, by the cue's rarity or group; once per cue
	-- ever (sold and found again pays nothing; a cue got in a trade pays nothing, plan section
	-- 6). Earned money, not boosted by VIP or a party.
	-- (tune)
	FindMoney = {
		Common = 500,
		Uncommon = 1000,
		Rare = 2500,
		Epic = 7500,
		Legendary = 25000,
		Mythic = 100000,
		Secret = 500000,
		Exclusive = 5000, -- rank cues, the VIP and Starter cues
		Unique = 10000, -- numbered Limited cues
	},
}

---------------------------------------------------------------------------------------------
-- The inventory service (src/server/Items.luau) and the global counters
-- (src/server/Counters.luau). (tune)
---------------------------------------------------------------------------------------------
Config.Items = {
	-- Each player's item requests (buy, open, sell, equip, claim): a token bucket
	-- (Progression/Requests). One request of a player's is answered at a time.
	RateBurst = 6, -- this many at once...
	RatePerSecond = 3, -- ...refilling this fast
	MarkSeenMax = 60, -- the most cue ids one MarkSeen may name
	-- Cue ids renamed after players could own them: [old id] = new id (2026-10-06, the
	-- designer: the Grand Opening Cue is the Firework Cue, behind the scenes too). Saves move
	-- over in SaveSchema's migration 7 -> 8; Counters still uses the old id as the Limited
	-- numbering key (copy numbers carry on) and folds the old id's copies in existence into the
	-- new one; a trade in flight under the old id is read under the new one (Trade.entries).
	RenamedCues = { GrandOpeningCue = "FireworkCue" },
	-- Paid random items (ECONOMY 13): PolicyService is asked on join, this many times this far
	-- apart; if it never answers, the player is treated as restricted (no blocks for money, no
	-- paid item trading) for the session: the cautious answer. Studio is never restricted.
	PolicyRetries = 3,
	PolicyRetrySeconds = 2,
	-- Copies in existence (ECONOMY 9): each server keeps pending +/- per cue and every
	-- FlushSeconds (+ up to FlushJitterSeconds, and on shutdown) adds them with one UpdateAsync
	-- to its own shard key (Shards, picked from the JobId); every ReadSeconds (+ up to
	-- ReadJitterSeconds) one read of the shards sums the totals for the clients. The Limited
	-- sold counts are read on the same loop.
	CountsStore = "CueCounts_v1",
	CountsStudioStore = "CueCounts_Studio_v1",
	CountsShards = 8,
	FlushSeconds = 60,
	FlushJitterSeconds = 15,
	ReadSeconds = 120,
	ReadJitterSeconds = 20,
	-- A background flush or read waits for the next round while Roblox's DataStore budget for
	-- that request type is under this (plus the calls it would make), so the counters never
	-- take requests the saves need (ECONOMY 9).
	BudgetFloor = 10,
	-- On shutdown the last flush waits at most this long for one already under way (Roblox
	-- gives BindToClose 30 s in all, shared with the saves).
	CloseWaitSeconds = 10,
	-- Numbered Limited copies (ECONOMY 9): one atomic UpdateAsync counter per Limited cue.
	LimitedStore = "LimitedCounts_v1",
	LimitedStudioStore = "LimitedCounts_Studio_v1",
	-- The first player ever to reach Reyes (ECONOMY 4.6), set once with UpdateAsync. A claim
	-- that fails is tried this many times, this far apart, before it counts as not first.
	FirstsStore = "Firsts_v1",
	FirstsStudioStore = "Firsts_Studio_v1",
	-- The restock shop's shared stock (the Legendary slot's GlobalStock), one key per restock.
	StockStore = "RestockStock_v1",
	StockStudioStore = "RestockStock_Studio_v1",
	FirstRetries = 3,
	FirstRetrySeconds = 2,
	FirstReyesTitle = "FirstReyes", -- the one-of-one title (an id in Strings.Items.Titles; 4.6)
	-- MessagingService topic for announcements every server shows (the first Reyes).
	AnnounceTopic = "Announce_v1",
	-- Subscribing to it is tried this many times: after a failure it waits AnnounceRetrySeconds,
	-- and each next wait is AnnounceRetryGrowth times longer (5, 10, 20, 40, 80 s: about 2.5
	-- minutes in all). After the last try this server hears no other server's news.
	AnnounceTries = 6,
	AnnounceRetrySeconds = 5,
	AnnounceRetryGrowth = 2,
	-- A Mythic or Secret unboxed (ECONOMY 7.4) is announced this long after the server rolled
	-- it, so the banner never spoils the opener's reel: that reel runs Config.UI.Reel
	-- .Reel's BigSeconds + CentreSeconds + BigSettleHoldSeconds (about 7.7 s) before its card,
	-- and this is at least a second more (config_test).
	UnboxAnnounceDelaySeconds = 9,
}

---------------------------------------------------------------------------------------------
-- Daily and playtime rewards, codes (src/shared/Progression/Daily.luau; the server's
-- src/server/Rewards.luau). Every number from docs/ECONOMY.md section 10. (tune)
---------------------------------------------------------------------------------------------
Config.Daily = {
	-- The login loop (the approved economy plan, 2026-10-02, section 6): one claim per UTC day,
	-- seven days that repeat. A missed day starts again at day 1, unless the week's streak
	-- freeze covers it. Each day: Money, Blocks (lucky blocks, { [kind] = count }) and/or
	-- Spins (ability spins). Every reward is claimed in the Rewards menu (no popups,
	-- designer 2026-10-04).
	Streak = {
		{ Money = 5000 },
		{ Blocks = { Mystery = 1 } },
		{ Money = 10000 },
		{ Blocks = { Mystery = 2 } },
		{ Money = 15000 },
		{ Blocks = { Mystery = 3 } },
		{ Blocks = { Rare = 1 }, Spins = 2 },
	} :: { { Money: number?, Blocks: { [string]: number }?, Spins: number? } },
	-- One free streak freeze a UTC week (weeks start Monday): a single missed day is covered
	-- by itself, so the streak goes on. Two or more missed days start it over.
	FreezePerWeek = 1,
	-- VIP's extra free ability spin a day (plan section 5), added to each day's claim. Everyone's
	-- one free spin a day is Config.Ults.Earn.DailyFree.
	VipSpins = 1,
	-- The 28-day track: total days claimed (never resets), repeating every TrackDays. On the
	-- day the count reaches one of these it adds its reward to that day's claim.
	TrackDays = 28,
	Track = {
		{ Day = 7, Blocks = { Rare = 1 } },
		{ Day = 14, Blocks = { Rare = 2 } },
		{ Day = 21, Blocks = { Rare = 2 } },
		{ Day = 28, Blocks = { Epic = 1 } },
	} :: { { Day: number, Money: number?, Blocks: { [string]: number }? } },
	-- Old names the Rewards screen still reads until the GUI lane rebuilds it: the track's four
	-- weeks ("Week 2 of 4") and its day-28 prize.
	WeeksForBonus = 4,
	WeekBonus = { Blocks = { Epic = 1 } },
	-- Playtime gifts: minutes played in a UTC day, each claimable once that day.
	Playtime = {
		{ Minutes = 10, Money = 2000 },
		{ Minutes = 30, Blocks = { Mystery = 1 } },
		{ Minutes = 60, Blocks = { Mystery = 2 }, Spins = 1 },
		{ Minutes = 90, Money = 10000 },
		{ Minutes = 120, Blocks = { Rare = 1 } },
	} :: {
		{
			Minutes: number,
			Money: number?,
			Blocks: { [string]: number }?,
			Spins: number?,
		}
	},
	PlaytimeTickSeconds = 30, -- the server adds playtime this often (and on leave)
	-- Promo codes (plan section 6): case-insensitive, once per player, optional Expires (the
	-- unix time it stops working: midnight UTC after its last day). Live = true: off until the
	-- designer switches it on in a live game (/code on <CODE>, every server at once; the like
	-- milestone codes, designer 2026-10-03).
	Codes = {
		WELCOME = { Money = 5000, Blocks = { Mystery = 1 } },
		["8BALL"] = { Money = 2500 },
		ROOFTOP = { Blocks = { Rare = 1 }, Expires = 1798761600 }, -- through 2026-12-31 (UTC)
		-- The spin screen's code box (Config.Ults.CodeBanner.ActiveCode names it): 3 ability
		-- spins. The tutorial points at it (designer, 2026-10-03: RELEASE replaces ABILITIES).
		RELEASE = { Spins = 3 },
		-- Like milestones: 1k, 5k, 10k, 25k, 50k, 100k likes.
		LIKES1K = { Money = 10000, Blocks = { Mystery = 1 }, Live = true },
		LIKES5K = { Money = 25000, Blocks = { Mystery = 2 }, Live = true },
		LIKES10K = { Blocks = { Rare = 1 }, Spins = 3, Live = true },
		LIKES25K = { Blocks = { Rare = 2 }, Live = true },
		LIKES50K = { Money = 100000, Blocks = { Rare = 2 }, Live = true },
		LIKES100K = { Blocks = { Rare = 3 }, Spins = 5, Live = true },
	} :: {
		[string]: {
			Money: number?,
			Blocks: { [string]: number }?, -- lucky blocks by kind
			Spins: number?, -- ability spins
			LuckySpins: number?, -- Lucky Spins
			Expires: number?,
			Live: boolean?,
		},
	},
	CodeMaxLength = 24,
	-- The Live codes switched on (src/server/LiveCodes.luau): one DataStore key holding the set,
	-- a MessagingService message so every server switches at once, and a read every
	-- LiveReadSeconds in case a message was missed.
	LiveStore = "LiveCodes_v1",
	LiveStudioStore = "LiveCodes_Studio_v1",
	LiveTopic = "LiveCodes_v1",
	LiveReadSeconds = 300,
	-- The Rewards service's limits (src/server/Rewards.luau; server limits, not ECONOMY.md
	-- numbers): one RewardRequest per player this often, one code attempt this often (so codes
	-- cannot be guessed quickly), and how often the server looks for a new UTC day (section 10:
	-- the streak and the gifts start over at midnight UTC, and the menu's state is re-sent).
	RequestCooldownSeconds = 0.5,
	RedeemCooldownSeconds = 2,
	DayCheckSeconds = 1,
}

---------------------------------------------------------------------------------------------
-- Trading (the approved economy plan, 2026-10-02, section 9; designer, 2026-10-03):
-- src/shared/Progression/Trade.luau, src/server/Trading.luau. Anyone in the server, no gate.
-- Cues and ready lucky blocks only, never money; Exclusive cues never except ExclusiveTradable. (tune)
---------------------------------------------------------------------------------------------
Config.Trade = {
	-- Items one side may offer (the history keeps as many: Config.Save.MaxTradeSideItems).
	MaxSideItems = Config.Save.MaxTradeSideItems,
	-- Both accept, then this long before the swap; any change starts it over on both sides.
	ConfirmSeconds = 3,
	InviteSeconds = 30, -- an unanswered trade invite goes away
	ExclusiveTradable = { StarterCue = true },
	-- The lopsided warning: one side's worth is more than this many times the other's. A
	-- cue's worth is 1 / its copies in existence (fewer than MinExists counts as MinExists);
	-- a lucky block's is 1 / BlockExists (about the copies of a cue as rare as what it usually
	-- gives). Only READY blocks trade (Progression/Trade).
	LopsidedRatio = 4,
	MinExists = 10,
	BlockExists = {
		Standard = 100000,
		Uncommon = 50000,
		Rare = 10000,
		Epic = 1000,
		Legendary = 200,
		Mythic = 30,
		Mystery = 70000, -- the tier roll: mostly Standard
		GrandOpening = 20000,
		Lucky8 = 10000, -- the Rare row
		Sky = 60000,
		Starter = 10000,
		Gift = 10000,
	},
	-- The ledger: each player's trades written before their saves change, replayed on a load
	-- that missed one (one key per player: the trades not yet confirmed saved).
	LedgerStore = "TradeLedger_v1",
	LedgerStudioStore = "TradeLedger_Studio_v1",
	MaxPending = 20,
	SaveWaitSeconds = 10, -- how long the swap waits for both saves before leaving it to replay
	-- A load reads its ledger this long after it loads, so a trade its old server was still
	-- finishing or calling off (the player left mid-swap) is settled first.
	ReplayDelaySeconds = 30,
	-- TradeRequest limits (not design numbers): a burst, then this many a second.
	RequestBurst = 8,
	RequestPerSecond = 4,
}

---------------------------------------------------------------------------------------------
-- The game's group and invites (the approved economy plan, 2026-10-02, section 6; designer,
-- 2026-10-03). src/server/Social.luau, src/shared/Progression/Social.luau. (tune)
---------------------------------------------------------------------------------------------
Config.Social = {
	GroupId = 675425213, -- "Lucky 8"
	-- Join (the client's GroupService:PromptJoinAsync) then Claim: this once per player. While a
	-- member, match money gets Config.Economy.GroupBoost (checked on join and on Claim).
	GroupReward = { Blocks = { Mystery = 3 } },
	-- Invites: a brand-new player who joined through a player's invite (the invite's launch
	-- data) and wins any match that is not solo gives both of them this lucky block. The inviter gets
	-- at most InvitesPerMonth a UTC month; one who is offline gets theirs on the next join.
	InviteBlock = "Rare",
	InvitesPerMonth = 5,
	-- "Brand new": the save was made at most this long before the launch data is read.
	NewPlayerSeconds = 600,
	-- The inviters' rewards waiting to be given (one key per inviter, the invitees' ids), and
	-- the message that tells the inviter's server.
	InviteStore = "InviteRewards_v1",
	InviteStudioStore = "InviteRewards_Studio_v1",
	InviteTopic = "InviteRewards_v1",
	MaxPending = 50, -- invitees one key keeps waiting (far above a month's cap)
	-- GUI lane (designer 2026-10-03, D7): the inviter's reward is given once ever (their first
	-- invited friend's first win); every invited friend still gets their own block.
	InviterOnce = true,
	-- GUI lane (D4): favoriting the game through Roblox's favorite prompt gives this once.
	-- Roblox gives a server no way to check a favorite, so the client reports it.
	FavoriteReward = { Money = 10000, Blocks = { Mystery = 1 } },
	-- A ClaimGroup request (it asks Roblox for the player's groups) at most this often.
	ClaimCooldownSeconds = 5,
}

---------------------------------------------------------------------------------------------
-- The shop's timed offers, VIP, Money Party and the Limited shelf (src/shared/Progression/
-- Shop.luau; src/server/Store.luau). Every number from docs/ECONOMY.md sections 9 and 11.
---------------------------------------------------------------------------------------------
Config.Shop = {
	-- The VIP welcome offer (11.3): half-price VIP for WelcomeSeconds from the first join; if
	-- not bought, one comeback window of ComebackSeconds opens ComebackAfterSeconds after the
	-- first join, then never again.
	WelcomeSeconds = 86400,
	ComebackAfterSeconds = 7 * 86400,
	ComebackSeconds = 86400,
	-- The Starter Pack (11.4): for StarterSeconds after the first join, once.
	StarterSeconds = 7 * 86400,
	StarterMoney = 75000,
	-- The Starter Pack's hour of 2x money (Config.Economy.StarterBoost; it adds to VIP's).
	StarterBoostSeconds = 3600,
	StarterBlock = "Starter", -- the Starter Lucky Block (Rare or better; designer 2026-10-04)
	VipCue = "VipCue", -- given once to every VIP
	-- The one short shop page, top to bottom (designer, 2026-10-04): the Grand Opening Lucky
	-- Block hero, the Mystery Lucky Block, the restock slots, the Starter Pack and VIP, money
	-- packs, Money Party and Get Roblox Plus. Jump buttons: Config.UI.Shop.Page.Jump.
	Order = {
		"GrandOpening",
		"Mystery",
		"Restock",
		"Offer", -- the Starter Pack and VIP, side by side
		"Money",
		"Boosts", -- Money Party, the ability slots and Roblox Plus
		"RobloxPlus", -- (folded into Boosts on the page; kept for the jump groups)
	},
	-- The Get Roblox Plus button (MarketplaceService:PromptRobloxSubscriptionPurchase; Roblox
	-- pays the game for each subscriber signed up in it). false hides it.
	RobloxPlus = true,
	-- Lucky blocks sold by the count (plan section 12; ItemRequest "BuyBlocks" for money,
	-- Config.Products for Robux): Kind, Money by count, Products by count (the same counts).
	-- A deal with StartsAt runs StartsAt..StartsAt + Seconds only (0: off until the designer
	-- sets it, right before the release is published; the release sale follows it).
	Deals = {
		Mystery = {
			Kind = "Mystery",
			Money = { [1] = 4900, [10] = 44100 },
			Products = { [1] = "Mystery1", [10] = "Mystery10" },
		},
		GrandOpening = {
			Kind = "GrandOpening",
			Money = { [1] = 49000, [3] = 139000, [10] = 441000 },
			Products = { [1] = "GrandOpening1", [3] = "GrandOpening3", [10] = "GrandOpening10" },
			StartsAt = 0,
			Seconds = 21 * 86400,
			VaultedSeconds = 7 * 86400, -- the "Vaulted" card stays this long after the end
		},
	},
	-- The Mystery block's money price (plan section 4; the shop's Mystery band reads it).
	Mystery = { Price = 4900, BulkCount = 10, BulkPrice = 44100 },
	-- The restock shop (plan section 12; Progression/Restock): new blocks every SlotSeconds on
	-- the clock (UTC :00, :10 ...), the same in every server (picked from the slot number).
	-- Three slots each roll one block kind by Odds (parts of ChanceTotal), a fourth for VIP by
	-- VipOdds. Stock is per player per restock, per slot; one block per press. Robux where a
	-- Product is named.
	Restock = {
		SlotSeconds = 600,
		ChanceTotal = 10000,
		Slots = 3,
		Odds = { Uncommon = 6200, Rare = 3660, Epic = 135, Legendary = 5 },
		VipOdds = { Rare = 9600, Epic = 385, Legendary = 15 },
		Kinds = {
			Uncommon = { Price = 14900, Stock = 3 },
			Rare = { Price = 34900, Product = "RestockRare", Stock = 1 },
			Epic = { Price = 349000, Product = "RestockEpic", Stock = 1 },
			Legendary = { Price = 3490000, Product = "RestockLegendary", Stock = 1 },
		},
		-- A Robux restock receipt still counts for its restock this long after the prompt
		-- opened (the prompt may be confirmed after the slot ended).
		ReceiptGraceSeconds = 600,
	},
	-- The first money pack a player ever buys pays this many times its money (11.1).
	FirstPackMultiplier = 2,
	-- Money Party (11.5): +Config.Economy.PartyBoost money for everyone in the server for
	-- PartySeconds; buying again adds PartySeconds. The shop offers it only while that stays
	-- within PartyMaxSeconds queued; a paid receipt always adds its full PartySeconds.
	PartySeconds = 900,
	PartyMaxSeconds = 3600,
	-- Receipts remembered in the save (the last N purchase ids), so a retried receipt is
	-- never granted twice.
	RecentPurchases = 50,
	-- How long ProcessReceipt waits for the save to reach the DataStore before giving up
	-- (NotProcessedYet: Roblox retries it later).
	ReceiptSaveTimeoutSeconds = 15,
	-- A receipt is checked again when it arrives (Shop.receiptCheck): the VIP offer and the
	-- Starter Pack still count as bought in their window this long after it closed (a prompt
	-- shown just before the end); later, or VIP or the Starter Pack already had, the receipt
	-- pays plain money (Shop.fallbackMoney) instead.
	OfferGraceSeconds = 600,
	-- A Robux Limited's receipt still takes a new copy number this long past the Limited's end
	-- (a purchase confirmed just before it); later it pays plain money instead.
	LimitedReceiptGraceSeconds = 600,
	-- A VIP offer receipt re-offered at join waits at most this long for the join's VIP pass
	-- check (a pass owner's receipt pays plain money); then the pass counts as not owned.
	ReceiptPassWaitSeconds = 30,
	-- The Store service's limits (src/server/Store.luau; server limits, not ECONOMY.md
	-- numbers). One StoreRequest per player this often ("TooFast"). How often the server looks
	-- for an offer window (11.3, 11.4), a Limited (9) or the Money Party
	-- (11.5) opening or closing, and re-sends that player's ShopState. Game pass ownership
	-- (11.2, 11.5) is asked of Roblox on join up to PassCheckTries times, PassRetrySeconds
	-- apart (the call can fail); a purchase in this server counts at once.
	RequestCooldownSeconds = 0.5,
	StateTickSeconds = 1,
	PassCheckTries = 3,
	PassRetrySeconds = 5,
	-- The Limited shelf (the approved economy plan, 2026-10-02, section 7): numbered Unique
	-- cues, one per player, for a set time with a real countdown; once ended never sold again,
	-- tradable forever. Price in money (or Product = a Config.Products key for a Robux one),
	-- Cap copies at most (none: no cap). StartsAt (unix, UTC) 0 = off: not shown, not sold,
	-- until the designer sets it (the Grand Opening's: right before the release is published).
	-- A new Limited is one row here plus its catalog cue. Beta is off (no row) until
	-- scheduled; there is no Founder's Cue (designer, 2026-10-05).
	-- (Designer, 2026-10-04: the $149,000 Firework Cue shelf is gone; the cue comes from
	-- the Grand Opening block only. The shelf code stays for a later Limited.)
	Limited = {} :: {
		{
			Cue: string,
			Price: number?,
			Product: string?,
			Cap: number?,
			StartsAt: number,
			Seconds: number,
		}
	},
	-- The release sale (designer, 2026-10-03, D5; the GUI lane): money packs 4-7, VIP and 10
	-- Mystery blocks at Percent off for Seconds, as their own developer products (Config.Products
	-- rows with SaleOf), shown in place of the normal ones only inside the window, so the
	-- crossed-out normal price is always true. StartsAt 0: it starts with the Limited row of
	-- With (the Firework Cue), so one date sets both.
	ReleaseSale = {
		StartsAt = 0,
		With = "GrandOpening", -- the Config.Shop.Deals key whose window it follows
		Seconds = 21 * 86400,
		Percent = 30,
	},
}

---------------------------------------------------------------------------------------------
-- Robux products (ECONOMY 11). tools/roblox_products.py creates each through Open Cloud and
-- writes its id to tools/products_ids.json; paste it here. While Id is 0 the shop says
-- "Coming soon" and prompts nothing. Robux is the display
-- fallback only: the shop shows Roblox's live price once an id exists (11).
---------------------------------------------------------------------------------------------
Config.Products = {
	-- Everything Robux buys (the approved economy plan, 2026-10-02, section 5): 4 game passes
	-- and 24 developer products with exactly these names, prices and descriptions
	-- (docs/prompts/ECONOMY_PROMPT.md step 3), created 2026-10-03 through Open Cloud by
	-- tools/roblox_products.py (managed pricing off). Id 0 would show "Coming soon" and prompt
	-- nothing. Robux is the fallback price; the live price
	-- is read from Roblox. Random = true: a paid random item, refused where PolicyService
	-- restricts them (ArePaidRandomItemsRestricted).
	-- The shop's order of the money packs (plan 5).
	PackOrder = { "Pack1", "Pack2", "Pack3", "Pack4", "Pack5", "Pack6", "Pack7" },
	-- The pack marked "Best value".
	BestValue = "Pack6",
	List = {
		-- Game passes.
		-- VIP (499 R$, designer 2026-10-04: was 599; halved block timers, fast reveals and
		-- Auto Spin). The live price is read from Roblox; change the pass's price in Creator
		-- Hub to match. The Quick Cases pass (id 2006144658) was retired into VIP 2026-10-04.
		Vip = { Kind = "Pass", Id = 2005370712, Robux = 499 },
		UltSlot2 = { Kind = "Pass", Id = 2006096679, Robux = 59 }, -- the second ability slot
		UltSlot3 = { Kind = "Pass", Id = 2006012697, Robux = 99 }, -- the third ability slot
		-- Offers (once).
		VipOffer = { Kind = "Product", Id = 3716158339, Robux = 249 }, -- VIP at half price, 24 h windows
		-- The Starter Pack: a Starter Lucky Block (Rare or better), $75,000, 1 h of 2x money.
		StarterPack = { Kind = "Product", Id = 3716158341, Robux = 99, Random = true },
		-- Money packs: Money each, Bonus = % more money per Robux than Pack1 (shown).
		Pack1 = { Kind = "Product", Id = 3716158342, Robux = 49, Money = 9000, Bonus = 0 }, -- Handful
		Pack2 = { Kind = "Product", Id = 3716158345, Robux = 99, Money = 19500, Bonus = 7 }, -- Stack
		Pack3 = { Kind = "Product", Id = 3716158347, Robux = 249, Money = 52500, Bonus = 15 }, -- Bundle
		Pack4 = { Kind = "Product", Id = 3716158349, Robux = 499, Money = 110000, Bonus = 20 }, -- Briefcase
		Pack5 = { Kind = "Product", Id = 3716158353, Robux = 999, Money = 235000, Bonus = 28 }, -- Vault
		Pack6 = { Kind = "Product", Id = 3716158356, Robux = 2499, Money = 625000, Bonus = 36 }, -- Bank
		Pack7 = { Kind = "Product", Id = 3716158358, Robux = 4999, Money = 1300000, Bonus = 42 }, -- Fortune
		-- Lucky blocks by the count (Config.Shop.Deals): Blocks = { Kind, Count }, paid origin
		-- (they open at once). The Grand Opening ones sell inside their deal's window only.
		Mystery1 = {
			Kind = "Product",
			Id = 3716158359,
			Robux = 25,
			Blocks = { Kind = "Mystery", Count = 1 },
			Random = true,
		},
		Mystery10 = {
			Kind = "Product",
			Id = 3716158365,
			Robux = 229,
			Blocks = { Kind = "Mystery", Count = 10 },
			Random = true,
		},
		GrandOpening1 = {
			Kind = "Product",
			Id = 3716907625,
			Robux = 49,
			Blocks = { Kind = "GrandOpening", Count = 1 },
			Deal = "GrandOpening",
			Random = true,
		},
		GrandOpening3 = {
			Kind = "Product",
			Id = 3716907627,
			Robux = 129,
			Was = 147,
			Blocks = { Kind = "GrandOpening", Count = 3 },
			Deal = "GrandOpening",
			Random = true,
		},
		GrandOpening10 = {
			Kind = "Product",
			Id = 3716907629,
			Robux = 349,
			Was = 490,
			Blocks = { Kind = "GrandOpening", Count = 10 },
			Deal = "GrandOpening",
			Random = true,
		},
		-- The restock slots' Robux prices (only while that block is in stock).
		RestockRare = {
			Kind = "Product",
			Id = 0,
			Robux = 99,
			Restock = "Rare",
			Random = true,
		},
		RestockEpic = {
			Kind = "Product",
			Id = 3716158370,
			Robux = 999,
			Restock = "Epic",
			Random = true,
		},
		RestockLegendary = {
			Kind = "Product",
			Id = 3716158374,
			Robux = 4999,
			Restock = "Legendary",
			Random = true,
		},
		LuckyBlockSkip = { Kind = "Product", Id = 3716368528, Robux = 19, Random = true },
		MoneyParty = { Kind = "Product", Id = 3716158385, Robux = 199 }, -- +100% money, 15 min, server
		-- Ability spins (ECONOMY 11.8; the spin screen's R$ buy row). Spins / Lucky: what one
		-- purchase adds; Was: the original price shown crossed out (a real bulk saving against
		-- Spin1 or Lucky1, never an always-on fake sale).
		Spin1 = { Kind = "Product", Id = 3716158388, Robux = 15, Spins = 1, Random = true },
		Spin5 = {
			Kind = "Product",
			Id = 3716158389,
			Robux = 50,
			Was = 75,
			Spins = 5,
			Random = true,
		},
		Spin10 = {
			Kind = "Product",
			Id = 3716158392,
			Robux = 100,
			Was = 150,
			Spins = 10,
			Random = true,
		},
		Spin50 = {
			Kind = "Product",
			Id = 3716158395,
			Robux = 449,
			Was = 750,
			Spins = 50,
			Random = true,
		},
		Lucky1 = { Kind = "Product", Id = 3716158396, Robux = 49, Lucky = 1, Random = true }, -- no Commons
		Lucky3 = {
			Kind = "Product",
			Id = 3716158399,
			Robux = 129,
			Was = 147,
			Lucky = 3,
			Random = true,
		},
		-- The release sale (Config.Shop.ReleaseSale): each gives what its SaleOf product gives,
		-- sold only inside the sale window (created 2026-10-03 by tools/roblox_products.py).
		Pack4Sale = {
			Kind = "Product",
			Id = 3716177484,
			Robux = 349,
			Money = 110000,
			SaleOf = "Pack4",
		},
		Pack5Sale = {
			Kind = "Product",
			Id = 3716177486,
			Robux = 699,
			Money = 235000,
			SaleOf = "Pack5",
		},
		Pack6Sale = {
			Kind = "Product",
			Id = 3716177488,
			Robux = 1749,
			Money = 625000,
			SaleOf = "Pack6",
		},
		Pack7Sale = {
			Kind = "Product",
			Id = 3716177490,
			Robux = 3499,
			Money = 1300000,
			SaleOf = "Pack7",
		},
		VipSale = { Kind = "Product", Id = 3716177492, Robux = 349, Vip = true, SaleOf = "Vip" },
		Mystery10Sale = {
			Kind = "Product",
			Id = 3716177494,
			Robux = 160,
			Blocks = { Kind = "Mystery", Count = 10 },
			Random = true,
			SaleOf = "Mystery10",
		},
	},
}

---------------------------------------------------------------------------------------------
-- Ultimates (docs/prompts/ULTIMATES_PROMPT.md; GDD section 9). The rules, the bar, the catalog
-- of 13, the spin odds, pity, slots and where spins come from. Pure modules in
-- src/shared/Ults read these; the server (UltService, UltSpins) and the screens do too.
-- Numbers marked (tune) are starting values.
---------------------------------------------------------------------------------------------
Config.Ults = {
	-- Ults are on by default everywhere (designer, 2026-09-28): public tables, the global
	-- queue (which offers No ults) and vs PC. A table's settings.abilities is its switch.
	Enabled = true,
	-- The spin screen for live players (spins, money packs and Lucky Spins). On since all 13
	-- are built (abilities step 19, 2026-09-29); Studio always shows it.
	ScreenLive = true,
	-- The developer flag: every ult, built or not, can be rolled and equipped (friend tests).
	-- `/ultsall on` turns it on for one player for the session.
	DevAllUlts = false,
	-- Everyone's starter ult, free forever; an empty or unusable slot plays as it (Heat Seeker
	-- since 2026-10-03, the tutorial teaches it; was Magnet).
	Default = "HeatSeeker",
	BarMax = 100, -- a full bar
	MaxPerMatch = 2, -- at most this many ults a match; after the second the bar stays empty
	-- Solo shows the real bar, always full and ready: a press arms the equipped ult for free,
	-- any number of times, and a practice shot (or a practice Rewind's redo) pays no money.
	PracticeInSolo = true,
	-- The bar's fill (section 5, all (tune); tools/ult_model.py reads these through
	-- tools/export_ult_config.luau). Balls pocketed on an ult shot fill nothing for its user.
	Fill = {
		-- Your own balls in one turn: the 1st, 2nd, 3rd, 4th... (the brief's 8, 6, 5, 4 and 2
		-- raised by tools/ult_model.py so the goal holds with room: the strong Classic case was
		-- 81%, now 85%; a run of 7 gives +38, x1.3 = +49, still half a bar).
		Own = { 10, 8, 6, 5 },
		OwnAfter = 3, -- ...then this for each ball after
		Nice = 20, -- a nice shot (bank, kick, combo, carom), on top of the ball
		OppBase = 8, -- an opponent's ball...
		OppPerBehind = 7, -- ...plus this for every ball you are behind after it
		TurnLegal = 15, -- each of your turns that ends on a legal shot (no foul, no timeout)
		OppTurn = 6, -- each of the opponent's turns that ends
		TurnCap = 50, -- turn-end fill (the two rows above) in total, per bar (never scaled)
		Teammate = 2, -- a teammate's ball (overnight assumption)
		-- Every gain times the table's difficulty (Classic's easy aiming makes short matches).
		Difficulty = { Classic = 1.3, Difficult = 1.0, Challenger = 1.0 },
		-- After your first ult everything x this, and the turn cap counts again (0.3 in the brief;
		-- 0.25 keeps second ults under 2% with the higher own-ball fill).
		AfterFirst = 0.25,
	},
	-- Activation and arming (section 4 and 7.2). The shot clock pauses from activation until
	-- the ult is armed, for both sides: the cutscene, then the wait, then the arming effect.
	-- The designer, 2026-09-28: the cutscene half as long (was 1.6 s) and the effect straight
	-- after it (the wait was 1.0 s).
	CutsceneSeconds = 0.8,
	ArmDelaySeconds = 0.1,
	-- Slots (section 8): slot 1 free, slots 2 and 3 are game passes (Config.Products UltSlot2,
	-- UltSlot3). The selected slot is the one equipped in matches.
	Slots = 3,
	SlotPasses = { "", "UltSlot2", "UltSlot3" }, -- "" = free
	-- Replacing an ult of this rarity or rarer asks "Replace BLACK FLASH?" first.
	ConfirmReplaceFrom = "Epic",
	-- The rarity ladder, lowest first (the item rarities, GDD section 12).
	Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" },
	-- The catalog of 13 (section 6). Names and descriptions are in Strings.Ults.Names and
	-- .Descriptions; colours are the item rarity colours (Config.UI.Kit.Rarity). Built = false
	-- is a placeholder: its cutscene plays with its own name, then nothing ("Coming soon"). It
	-- can only be rolled or equipped with the developer flag. Effect is the module in
	-- src/shared/Ults/Effects that hooks the physics for one shot. Worth = the power ladder's
	-- target, in balls per use, measured by each ult's harness (section 6).
	Order = {
		"Magnet",
		"EaglesEye",
		"SuperBounce",
		"Ghost",
		"HeatSeeker",
		"Rewind",
		"Portals",
		"TimeStop",
		"ChainLightning",
		"SteelBall",
		"BlackFlash",
		"BlackHole",
		"GuangdongTiger",
	},
	-- Worth: the careful shooter's measured net balls a use (extra own balls minus the
	-- opponent's gifted), the mean of skills 1/2/3 (tools/ult_value.luau, 120 tables, the step
	-- 16 balance pass, 2026-09-29; every number in tools/ult_value_results.json). The GDD's
	-- rough targets (0.33 / 0.5 / 1 / 1.5 / 2.2 / 2.6) are out of reach inside the reach and
	-- ball caps (5.3: report the measured value); the ladder holds on each rarity's mean:
	-- Common 0.37, Uncommon 0.44, Rare 0.50, Epic 0.69, Legendary 1.15, Mythic 1.31.
	Catalog = {
		-- +0.38 / +0.54 / +0.44 (careless +0.37 / +0.56 / +0.52).
		-- Uncommon since the economy plan (2026-10-02, section 8: its measured strength).
		Magnet = { Rarity = "Uncommon", Built = true, Effect = "Magnet", Worth = 0.46, Area = true },
		-- +0.14 / +0.38 / +0.48.
		EaglesEye = { Rarity = "Common", Built = true, Effect = "EaglesEye", Worth = 0.34 },
		-- +0.27 / +0.39 / +0.32.
		SuperBounce = { Rarity = "Common", Built = true, Effect = "SuperBounce", Worth = 0.33 },
		-- +0.39 / +0.56 / +0.46 with the ghostly pull (about 0 without it).
		Ghost = { Rarity = "Uncommon", Built = true, Effect = "Ghost", Worth = 0.47 },
		-- +0.36 / +0.41 / +0.43 (30 degrees of cut correction).
		HeatSeeker = {
			Rarity = "Common", -- Common since the economy plan (2026-10-02, section 8)
			Built = true,
			Effect = "HeatSeeker",
			Worth = 0.4,
			Pick = "OwnBall",
		},
		-- +0.36 / +0.58 / +0.65 (two redos, each with the full-path guide).
		Rewind = { Rarity = "Rare", Built = true, Worth = 0.53, Redo = true },
		-- +0.65 / +0.42 / +0.34 (three strikes in stopped time).
		TimeStop = { Rarity = "Epic", Built = true, Effect = "TimeStop", Worth = 0.47 }, -- Epic since 2026-09-30
		-- +0.97 / +0.98 / +0.94 (careless +0.78 / +0.72 / +0.76; three jumps).
		ChainLightning = {
			Rarity = "Epic",
			Built = true,
			Effect = "ChainLightning",
			Worth = 0.96,
			Area = true,
		},
		-- +0.37 / +0.52 / +0.38, whole turn included: a low bound (the model shooter does not
		-- reuse the kept portals as a player will; the designer keeps it, flagged, 2026-09-29).
		Portals = {
			Rarity = "Rare", -- Rare since 2026-09-30 (the designer swapped it with Time Stop)
			Built = true,
			Effect = "Portals",
			Worth = 0.42,
			Pick = "Portals",
			Turn = true,
		},
		-- +1.00 / +1.11 / +1.18.
		SteelBall = {
			Rarity = "Legendary",
			Built = true,
			Effect = "SteelBall",
			Worth = 1.09,
			MaxBalls = 3,
		},
		-- +1.11 / +1.25 / +1.26 (careless +0.85 / +1.00 / +1.08; 4 of yours at most).
		BlackFlash = {
			Rarity = "Legendary",
			Built = true,
			Effect = "BlackFlash",
			Worth = 1.21,
			MaxBalls = 4,
			Area = true,
		},
		-- +1.21 / +1.36 / +1.39 (careless +0.93 / +1.08 / +1.15; 4 of yours, 1 of theirs).
		BlackHole = {
			Rarity = "Mythic",
			Built = true,
			Effect = "BlackHole",
			Worth = 1.32,
			MaxBalls = 4,
			Area = true,
		},
		-- +1.22 / +1.34 / +1.34 (careless +0.93 / +1.07 / +1.14; 4 of yours, 1 of theirs).
		GuangdongTiger = {
			Rarity = "Mythic",
			Built = true,
			Effect = "GuangdongTiger",
			Worth = 1.3,
			MaxBalls = 4,
			Area = true,
		},
	} :: {
		[string]: {
			Rarity: string,
			Built: boolean,
			Effect: string?,
			Worth: number,
			MaxBalls: number?,
			-- "OwnBall" (Heat Seeker) or "Portals": the aim-phase pick it needs first.
			Pick: string?,
			-- An area ability (5.7): the opponent's balls too, at OpponentFactor.
			Area: boolean?,
			-- Rewind (7.6): a shot that drops none of the shooter's balls is undone and redone.
			Redo: boolean?,
			-- Portals (7.9): it keeps acting on every shot of the shooter's turn (the same
			-- pick), until the turn passes or the game ends.
			Turn: boolean?,
		},
	},
	-- Rolls (section 8), in parts per million so each table adds to exactly 1,000,000. Each
	-- rarity's share is split evenly between its ults in the pool. A rarity with no ult in the
	-- pool passes its share down to the next rarity below that has one (the Odds panel shows
	-- the true current odds).
	Roll = {
		Normal = {
			Common = 550000, -- 55%
			Uncommon = 300000, -- 30%
			Rare = 122333, -- 12.2333%
			Epic = 20000, -- 2%
			Legendary = 6667, -- 0.6667%, 1 in 150 (tune)
			Mythic = 1000, -- 0.1%, 1 in 1,000 (tune)
		},
		-- A Lucky Spin never rolls Common (Robux only).
		Lucky = {
			Common = 0,
			Uncommon = 631667, -- 63.1667%
			Rare = 250000, -- 25%
			Epic = 80000, -- 8%
			Legendary = 33333, -- 3.3333%, 1 in 30
			Mythic = 5000, -- 0.5%, 1 in 200
		},
		-- Pity: every spin adds 1; the PityAt-th spin without an Epic or better is Epic+ (split
		-- in the normal table's proportions: Epic 72.3%, Legendary 24.1%, Mythic 3.6%), and any
		-- Epic+ resets it to 0.
		PityAt = 100,
		PityFrom = "Epic",
		-- Mythic rolls use the server announcement (like Mythic unboxings); Legendary gets a banner
		-- in this server only.
		AnnounceAll = { Mythic = true },
		AnnounceServer = { Legendary = true },
	},
	-- Where spins come from (section 10, (tune)).
	Earn = {
		Starter = 1, -- a fresh save, and the migration for existing saves (the tutorial spins it)
		DailyFree = 1, -- one free spin a UTC day (Rewards > Daily's reset); never stacks
		-- Reaching each tier (division I) adds spins: +1 up to Gold, +2 Platinum and Diamond, +3 above.
		RankUp = {
			Bronze = 1,
			Silver = 1,
			Gold = 1,
			Platinum = 2,
			Diamond = 2,
			Expert = 3,
			Veteran = 3,
			Master = 3,
			Grandmaster = 3,
			Reyes = 3,
		},
		-- Money spins: this much each, no bulk discount ("way more expensive" than Robux).
		MoneyPerSpin = 17500,
		MoneyPacks = { 1, 5, 10, 50 }, -- BUY 1, 5, 10, 50 in $ mode
		-- Robux packs: the developer products in Config.Products (Spin1..Spin50, Lucky1, Lucky3).
		RobuxPacks = { "Spin1", "Spin5", "Spin10", "Spin50" },
		LuckyPacks = { "Lucky1", "Lucky3" },
		MaxSpins = 100000, -- the save's cap on held spins (and Lucky Spins)
	},
	-- The code box on the spin screen (section 9.3): the designer edits these two in one place.
	-- The code itself is a row in Config.Daily.Codes (Spins = 3).
	CodeBanner = { ActiveCode = "RELEASE", NextGoalLikes = 100 },
	-- VIP's Auto Spin (section 9.6): one spin this often, server-checked.
	AutoSpinSeconds = 0.4,
	AutoStopChoices = { "Rare", "Epic", "Legendary" },
	-- The PC opponent (section 4): it activates when its bar is full and it is behind, or when
	-- its shot finder sees no easy shot.
	Pc = { WhenBehind = true, WhenNoEasyShot = true },
	-- The spin service's request limits (not design numbers).
	RequestCooldownSeconds = 0.25,
	RequestBurst = 6,
	-- Sounds (section 7). The designer's two, uploaded to the group (assets/audio/abilities).
	-- Levels (designer, 2026-10-07: normalize, nothing should hurt): every clip in this table was
	-- measured through an AudioAnalyzer and its Volume set from Volume x 90th-percentile RMS
	-- (Config.Audio.Ui uses the same scale): about 0.045 for a sting (YourTurn's loudness), up to
	-- 0.06 for a big moment (an ability going off), 0.025 or under for a loop, and no transient
	-- peaking past 0.6 (a hard cue strike). Volumes were only ever turned DOWN to get there.
	Audio = {
		-- The Smash Bros. "Final Smash activation" (designer, 2026-10-07): trimmed to its 1.63 s
		-- (no silent lead, so the hit lands with the panel's slam from 0) and normalized to -16
		-- LUFS; Volume x RMS 0.057, a big moment.
		Activate = { Id = "rbxassetid://115276502447131", Volume = 0.4, StartOffset = 0 },
		-- The Smash Bros. Smash Ball sound (designer, 2026-10-07): the bar reaching 100%. Trimmed
		-- to its 1.11 s and normalized to -16 LUFS; played whole (MaxSeconds 0; above 0 it plays
		-- that long, then fades over FadeSeconds). Volume x RMS 0.028, about half YourTurn: a cue,
		-- not a fanfare (designer, 2026-10-04).
		Ready = {
			Id = "rbxassetid://119991075881327",
			Volume = 0.2,
			StartOffset = 0,
			MaxSeconds = 0,
			FadeSeconds = 0.8,
		},
		-- Magnet (public library audio, each checked loading in this game, 2026-09-28):
		-- "Force Field Sci Fi Constant Deep Pulsing Hum" (Pro Sound Effects, 27 s): the low
		-- magnetic hum looping at the armed cue ball (3D, quiet); it rises in pitch while a
		-- ball is pulled.
		MagnetHum = { Id = "rbxassetid://9125566994", Volume = 0.23, Pitch = 0.9, PullPitch = 1.35 },
		-- "Electric Zapping loop" (FastFoxVita, 0.98 s loop, loud): crackle while a ball is in
		-- a capture zone, at the ball.
		MagnetPull = { Id = "rbxassetid://427262367", Volume = 0.12 },
		-- The drop: "Metal Impact Heavy Clunking Hits 4" (Pro Sound Effects, 0.87 s) with
		-- "Electric Zaps 12" (Pro Sound Effects, 0.97 s) on top: the clunk-zap at the pocket.
		MagnetClunk = { Id = "rbxassetid://9116673944", Volume = 0.075 },
		MagnetZap = { Id = "rbxassetid://9114277757", Volume = 0.55 },
		-- Arming: "Electric Zaps 6" (Pro Sound Effects, 2.1 s, starts at 0.16 s) as the rings
		-- snap onto the cue ball.
		MagnetArm = { Id = "rbxassetid://9114277402", Volume = 0.45, StartOffset = 0.14 },
		-- Eagle's Eye arming: "Eagle Screech 1" (public library audio, 1.8 s, checked loading in
		-- this game), 3D at the cue ball, at the Magnet arm's level. (tune by ear)
		EagleScreech = { Id = "rbxassetid://133423182233493", Volume = 0.19 },
		-- Super Bounce (public library audio, each checked loading in this game, 2026-09-29):
		-- arming, "Cartoon Spring Bounce Sound" (MysteryMilo, 1.3 s, a long boing-oing, peak
		-- 0.54); every bounce, "SS_rubberduck_variety_spring_02" (Roblox, 1.3 s but a quick
		-- 0.3 s spring, peak 0.48), pitched up per bounce (Config.UI.SuperBounceFx).
		BounceArm = { Id = "rbxassetid://6075441854", Volume = 0.31 },
		BounceHit = { Id = "rbxassetid://111237552536869", Volume = 0.45 },
		-- Ghost (public library audio, each checked loading in this game, 2026-09-29): arming,
		-- "Dream Weirdness Constant 6" (Pro Sound Effects, Ghosts, 3.3 s of reverberant wails,
		-- quiet: peak 36 at volume 0.5, in from 0.9 s), started at 0.6; each ball the cue ball
		-- passes through, "Fast Pass By Airy Whooshes Windy 2" (Pro Sound Effects, 1.2 s, peak
		-- at 0.5 s), started at 0.25 so the rush lands on the ball. (tune by ear)
		GhostWail = { Id = "rbxassetid://9114170094", Volume = 0.9, StartOffset = 0.6 },
		GhostWhoosh = { Id = "rbxassetid://9114373663", Volume = 0.4, StartOffset = 0.25 },
		-- Heat Seeker (public library audio, checked loading in this game, 2026-09-29): each
		-- lock-on beep, "shortbeep" (maybealian, 0.13 s, loud: peak 284 at volume 0.5); the lock,
		-- "1000 hz sine tone" (BuilderBillbert, 1 s, peak 64), cut to the look's LockToneSeconds.
		SeekerBeep = { Id = "rbxassetid://124455167265111", Volume = 0.16 },
		SeekerLock = { Id = "rbxassetid://126305525792122", Volume = 0.35 },
		-- Rewind (public library audio, each checked loading in this game and measured with an
		-- AudioAnalyzer, 2026-09-29): arming, "Eject Cassette SFX" (zImBored, from Pixabay,
		-- 1.25 s, two clacks peaking 25 at volume 0.5); the rewind, "Tape Rewind" (AppleBraid,
		-- 3.6 s, a whirr whose loudest pitch climbs from about 750 Hz to 4.6 kHz), sped to fit
		-- the playback and pitched up further as it goes (Config.UI.RewindFx); the landing,
		-- "Cassette Play SFX" (WaddelsG, 0.65 s, a sharp clunk, peak 41, with a low tail);
		-- a try that drops one of yours (the ability spent, no rewind), "cassette click"
		-- (zKevin, 0.17 s). (tune by ear)
		RewindArm = { Id = "rbxassetid://124843841489877", Volume = 0.64 },
		RewindWhirr = { Id = "rbxassetid://7361292522", Volume = 0.48 },
		RewindClunk = { Id = "rbxassetid://4511695221", Volume = 0.6 },
		RewindSpent = { Id = "rbxassetid://830440268", Volume = 0.5 },
		-- Time Stop (public library audio, each checked loading in this game and measured with
		-- an AudioAnalyzer, 2026-09-29): from the first contact, "504_Reverse_Cymbal"
		-- (kyleamida, 1.41 s, rising to peak 37 at 1.2 s), sped up so it peaks on the freeze
		-- (Config.UI.TimeStopFx); on the freeze, "Boom Impact Deep Distant Thumping Hits 1"
		-- (Pro Sound Effects, 2.9 s, a 90-140 Hz boom, peak 29); each second while frozen, the
		-- first of "Clock Ticking [2 Ticks]" (heiroftheeternalname, a tick at 0.3 s, peak 12);
		-- the resume, "Reversed Whoosh Backwards Hissing Burst 2" (Pro Sound Effects, 1.3 s,
		-- peak 21 at 0.3 s) into "Clock Tick Tock - ULTRAKILL" (ImJustDou, 0.5 s, quiet), which
		-- also plays as it arms. (tune by ear)
		TimeSwell = { Id = "rbxassetid://119247066943033", Volume = 0.25 },
		-- The freeze: the designer's own clip (2026-09-30, 3.1 s, a hit at the start fading
		-- out, peak 0.74 at volume 1; was "Boom Impact Deep Distant Thumping Hits 1").
		TimeBoom = { Id = "rbxassetid://119468975319371", Volume = 0.27 },
		TimeTick = { Id = "rbxassetid://8140501675", Volume = 1.2, StartOffset = 0.22 },
		TimeResume = { Id = "rbxassetid://9118158113", Volume = 0.7 },
		TimeTickTock = { Id = "rbxassetid://98448773080489", Volume = 0.28 },
		-- Chain Lightning (public library audio, each checked loading in this game and measured
		-- with an AudioAnalyzer, 2026-09-29): the charge, "thunder crack" (DundeiEh, 3.5 s, a crack
		-- at 0.2 s then a rolling tail); each jump, "Quick Electric Zap" (ConeExpierence, 0.9 s,
		-- loud from the start); while balls glow and while armed, "energy buzz" (mastermilosz,
		-- 7.4 s, a steady quiet hum, looped); arming, "Electric Zaps 6 (SFX)" (Pro Sound
		-- Effects, a zap at 0.2-0.35 s). (tune by ear)
		ChainThunder = { Id = "rbxassetid://72827145254925", Volume = 0.38, StartOffset = 0.12 },
		ChainZap = { Id = "rbxassetid://97096310054904", Volume = 0.08 },
		ChainHum = { Id = "rbxassetid://124666497875357", Volume = 0.6 },
		ChainArm = { Id = "rbxassetid://9114277402", Volume = 0.87, StartOffset = 0.15 },
		-- Portals (public library audio, each checked loading in this game and measured with an
		-- AudioAnalyzer, 2026-09-29): while open, "Metallic Glow Constant Deep Ticking Bassy Hum"
		-- (Pro Sound Effects, 18.5 s, a steady surging hum, looped); a ball going in, "swish
		-- teleport tp flashstep sfx" (Axellatic, 1.9 s, peak at 0.2 s), pitched down; coming out,
		-- "Pop Sound Effect" (Siegegeddon, 0.2 s); opening, "teleport" (Joshua00924, 1 s);
		-- closing, the swish pitched further down. (tune by ear)
		PortalHum = { Id = "rbxassetid://9125674114", Volume = 0.22 },
		PortalEnter = { Id = "rbxassetid://108156925383225", Volume = 0.15, Pitch = 0.8 },
		PortalExit = { Id = "rbxassetid://140323850218372", Volume = 0.75 },
		PortalOpen = { Id = "rbxassetid://135640489101126", Volume = 0.16, Pitch = 1.1 },
		PortalClose = { Id = "rbxassetid://108156925383225", Volume = 0.15, Pitch = 0.6 },
		-- Steel Ball (public library audio, each checked loading in this game): the "nyo-ho"
		-- stand-in is a playful two-note whistle call (the brief's fallback; a recorded call is
		-- the designer's), a spinning-top loop for the whirr, a heavy metal hit for each
		-- contact, a twinkle for each guided pot.
		-- The activation and the cue ball's first hit: the designer's own clip (2026-09-30,
		-- 3.8 s, loud throughout, peak 1.0 at volume 1; was a two-note whistle call). Later
		-- contacts keep the short clank.
		SteelCall = { Id = "rbxassetid://88567420275306", Volume = 0.25 },
		SteelWhirr = { Id = "rbxassetid://122309511753634", Volume = 0.53, Pitch = 1.2 },
		SteelClank = { Id = "rbxassetid://117478490073055", Volume = 0.42 },
		SteelPot = { Id = "rbxassetid://135385970610304", Volume = 0.49 },
		-- Black Flash: the cue ball's first hit plays the designer's own clip (2026-09-30; was a
		-- boom, a glass shatter and a crackle tail). The file holds three hits (about 0.4 s,
		-- 2.8 s and 6.5 s in, peak 0.66 at volume 1): only the first plays. An electric
		-- crackle (public library audio) loops quietly while armed.
		FlashHit = {
			Id = "rbxassetid://78697555368113",
			Volume = 0.35,
			StartOffset = 0.2,
			Length = 2.35,
		},
		FlashCrackle = { Id = "rbxassetid://84986266888002", Volume = 0.8 },
		-- Black Hole (public library audio, each checked loading in this game, 2026-09-29):
		-- while open, "Hollow Rumble 1" (Pro Sound Effects, a deep steady drone, looped);
		-- opening, "Tutti Suck" (APM, 2.9 s, an orchestral swell to a suck-out); each ball
		-- caught, Time Stop's reversed whoosh (a rising whoosh); the collapse, Portals' pop
		-- pitched far down (hollow). (tune by ear)
		HoleDrone = { Id = "rbxassetid://9112795463", Volume = 0.31 },
		HoleOpen = { Id = "rbxassetid://9039693523", Volume = 0.18 },
		HolePull = { Id = "rbxassetid://9118158113", Volume = 0.6, Pitch = 1.1 },
		HolePop = { Id = "rbxassetid://140323850218372", Volume = 0.75, Pitch = 0.45 },
		-- Guangdong Tiger (public library audio, each checked loading in this game, 2026-09-29):
		-- the leap, "Tiger Roars 9" (Pro Sound Effects, 1.6 s); the swipe, "Red Mist Vertical
		-- Split" played three times a beat apart, each a little higher; the landing, "Body
		-- Impact 2" (Pro Sound Effects, a hard thump) pitched down. (tune by ear)
		TigerRoar = { Id = "rbxassetid://9120047974", Volume = 0.52 },
		TigerSlash = { Id = "rbxassetid://122411746821632", Volume = 0.1 },
		TigerThump = { Id = "rbxassetid://9113524237", Volume = 0.74, Pitch = 0.6 },
	},
}

-- Ghost (docs/prompts/ABILITIES_PROMPT.md 7.4; Ults/Effects/Ghost, Arming.extras): the cue
-- ball passes through the opponent's balls and the 8 (unless it is your legal 8) for the shot.
-- Measured (tools/ult_value.luau, 2026-09-29, net balls a use at skills 1/2/3): about 0 on
-- every table (an open pot is nearly always there), +0.25 / +0.12 / +0.03 on the tables where
-- it changes the best shot (--useful, 118 of 960). Under the Uncommon row: the balance step's.
Config.Ults.Ghost = {
	-- A cue ball that comes to rest inside a ball it passed through is moved off it at rest,
	-- to just clear of it (this gap, inches), the nearest free spot on the cloth first.
	ClearGapInches = 0.05,
	-- From the cue ball's first contact the ball it hit also passes through the balls the cue
	-- ball did (the opponent's and the 8), so a pot they block goes in (the step 16 buff:
	-- worth about 0 without it; the cue ball passing your own balls after the first contact
	-- is always on).
	CarryPhase = true,
	-- The ball the cue ball hit (the shooter's) is pulled into a pocket it nearly misses with
	-- this share of Magnet's strength (0: off). The designer's step 16 buff (2026-09-29):
	-- without it Ghost measured about 0 a use; 0.5 +0.34 / +0.46 / +0.31, 1 +0.39 / +0.56 /
	-- +0.46 (careful net, skills 1/2/3). (tune)
	PullFactor = 1,
}

-- Heat Seeker (docs/prompts/ABILITIES_PROMPT.md 7.5; Ults/Effects/HeatSeeker): the cue ball
-- homes on the shooter's locked ball (overrides.Pick) until its first contact. (tune)
Config.Ults.HeatSeeker = {
	-- The heading turns toward its path on a curve no tighter than this radius (inches) at any
	-- speed, like a missile: a fast shot turns as sharply as a slow one, so it can dodge a
	-- ball just ahead. Random tables and aims reach the locked ball 84% of the time at 6, 90%
	-- at 4.5, 92% at 3, 95% at 2 and 96% at 1.5 (the misses: aimed straight into a ball or
	-- pocket right beside the cue ball, or boxed in); 2 still reads as a curve.
	TurnRadiusInches = 2,
	-- The missile's thrust: while homing, the cue ball never drops below this speed (in/s), so
	-- a soft shot aimed away still arrives.
	MinSpeed = 35,
	-- ...and never goes faster than this (in/s) while homing, so it can steer round a ball
	-- next to the target (a full-power 450 in/s moved 1.9 in a step and ran into them). Plenty
	-- for any pot; normal physics from the first contact.
	MaxSpeed = 160,
	MaxSeconds = 6, -- homing stops after this long (a cue ball boxed in rolls on as normal)
	-- Balls and pockets on the way are passed this far clear (inches beyond touching).
	AvoidMarginInches = 0.6,
	-- The path is planned on a grid of the cloth this fine (inches: 100 x 50 cells), once at
	-- the strike and again (up to MaxReplans times) when a cushion knocks it off the path.
	GridInches = 1,
	MaxReplans = 6,
	-- A direct aim's cut is turned toward the best pocket by at most this angle, as its tangent
	-- (0.364 is 20 degrees): it improves a bad cut, never guarantees the pot. Measured
	-- (tools/ult_value.luau, 2026-09-29, net balls a use at skills 1/2/3): 10 degrees +0.28 /
	-- +0.23 / +0.18, 15 +0.32 / +0.31 / +0.31, 20 +0.34 / +0.34 / +0.32, 27 +0.35 / +0.38 /
	-- +0.39 (it saturates: the misses left are not the cut's), 30 +0.36 / +0.41 / +0.43
	-- (the step 16 balance pass: 30 degrees, above the Commons on average). (tune)
	CutCorrectionTan = 0.5774,
}

-- Chain Lightning (docs/prompts/ABILITIES_PROMPT.md 7.8; src/shared/Ults/Effects/ChainLightning).
-- Measured (tools/ult_value.luau, 2026-09-29, 120 tables, net balls a use at skills 1/2/3):
-- careful +1.08 / +1.08 / +1.13, careless +0.88 / +0.79 / +0.86 (the skill the rule adds
-- +0.2 to +0.3): the bottom of the Epic band (1 to 2). The brief's numbers (8 degrees, 3
-- jumps, a short push) measured +0.6: the chain reaches few of your balls on a real spread
-- (about 0.7 a use), so the steer and the push carry most of it; the balance step (16) decides.
Config.Ults.ChainLightning = {
	-- Caps per use (5.7): at most this many of the shooter's balls and of the opponent's; the
	-- closest go first. Per ability so the ladder can climb (the step 16 balance pass). (tune)
	MaxOwn = 3,
	MaxOpp = 2,
	-- The charged ball (the first ball hit, if yours): its heading turns toward its best
	-- pocket by at most this angle, as its tangent (0.2679 is 15 degrees; 8 measured +0.6,
	-- 12 +0.94, 18 +1.0), and its speed is multiplied by Boost. (tune)
	SteerTan = 0.2679,
	Boost = 1.25,
	-- The chain: up to Links jumps, each to the nearest ball within ReachInches (centre to
	-- centre) of the last one struck, LinkSeconds apart. The reach is at the cap
	-- (Config.Ults.Shared.MaxReachShare of the table; 12 in reached a ball on a third of the
	-- jumps). Four jumps measured +1.08 / +1.08 / +1.12 (careful net, skills 1/2/3), too close
	-- to the Legendaries; three +0.97 / +0.98 / +0.94 (the step 16 balance pass). (tune)
	Links = 3,
	ReachInches = 20,
	LinkSeconds = 0.08,
	-- The push on each struck ball: toward its closest pocket with a clear line in (traced
	-- with a ball ClearanceInches fatter), fast enough to roll PushReachShare of the way to
	-- the opening's centre, at most PushMaxInches (a ball with an open pocket within about
	-- 20 in drops, 63% of your struck balls did); the opponent's at OpponentFactor of that
	-- speed, which rolls a quarter as far. (tune)
	PushReachShare = 3,
	PushMaxInches = 60,
	ClearanceInches = 0.1,
}

-- Steel Ball (docs/prompts/ABILITIES_PROMPT.md 7.10; src/shared/Ults/Effects/SteelBall).
Config.Ults.SteelBall = {
	-- A guided ball reaches its pocket's centre at this speed (in/s): set every step from the
	-- distance still to go, so a soft hit is sped up and a hard one slowed. (tune)
	ArriveSpeed = 30,
	GuideMaxSpeed = 150, -- never faster while guided (in/s), so it steers clean round a ball
	-- A guided ball's heading turns on a curve no tighter than this (inches).
	GuideTurnRadiusInches = 3,
	GuideSeconds = 8, -- a guided ball is let go after this long (boxed in)
	-- A guided ball with no clean line in heads for a point this far in front of the opening,
	-- on the pocket's axis, then straight in (inches).
	EntryInches = 4,
	-- A line counts as clean with a ball this much fatter (inches), as Chain Lightning's.
	ClearanceInches = 0.1,
	-- The cue ball's next ball is guided in when its pocket has a clean line and the opening is
	-- within this (inches); farther, it is lined up instead. (tune: the balance pass)
	CloseInches = 36,
	-- A lined-up ball stops this far short of its pocket's opening (inches). (tune)
	LineUpInches = 8,
	-- The cue ball's curve to the next ball: no tighter than this radius (inches), between
	-- these speeds (in/s), straight in over the last ApproachInches behind the ghost-ball spot.
	CueTurnRadiusInches = 4,
	CueMinSpeed = 45,
	CueMaxSpeed = 100,
	ApproachInches = 4,
	CueSeconds = 6, -- the cue ball's trip gives up after this long (and the cue ball stops)
	-- The trip is planned again when its ball has moved this far (inches) since.
	ReplanMoveInches = 0.5,
	-- A waypoint counts as reached within this (inches): steering moves on to the next.
	WaypointInches = 0.5,
	-- Paths: balls and pockets passed this far clear (inches beyond touching), on a grid this
	-- fine (inches), planned again at most this many times when knocked off.
	AvoidMarginInches = 0.6,
	GridInches = 1,
	MaxReplans = 6,
}

-- Black Flash (docs/prompts/ABILITIES_PROMPT.md 7.11; src/shared/Ults/Effects/BlackFlash).
Config.Ults.BlackFlash = {
	-- The launch (the designer, 2026-09-30): the cue ball leaves at this many times the
	-- power bar's speed, its spin scaled the same (a full-power shot about 75 mph). (tune)
	LaunchSpeedScale = 3,
	-- Caps per use (5.7): at most this many of the shooter's balls and of the opponent's; the
	-- closest go first. Per ability so the ladder can climb (the step 16 balance pass). (tune)
	-- The step 16 balance pass (the designer's approved buff, 2026-09-29): 4 of yours: +1.11 /
	-- +1.25 / +1.26 careful net at skills 1/2/3 (3: +1.04 / +1.18 / +1.18); its opponent cap never
	-- binds.
	MaxOwn = 4,
	MaxOpp = 2,
	-- The blast nudges object balls within this of the shattered ball (inches) on a full-power
	-- shot, at most Config.Ults.Shared.MaxReachShare of the table. (tune)
	RadiusInches = 20,
	-- The reach grows with the shot's power (the designer, 2026-09-30, so a soft shot keeps the
	-- blast off nearby opponent balls): RadiusInches x (RadiusMinShare + (1 - RadiusMinShare) x
	-- power), 4 in at the lowest, 6.4 at 15%, 20 at full. (tune)
	RadiusMinShare = 0.2,
	-- Each nudged ball rolls this share of the way to its pocket (at most NudgeMaxInches):
	-- under 1 moves it toward the pocket, over 1 can drop a near one. The designer halved the
	-- push (2026-09-30: was 1.5 and 40). (tune)
	NudgeShare = 0.75,
	NudgeMaxInches = 20,
	-- The cue ball rolls straight back this far (inches), stopping this much clear of any
	-- pocket on its line. (tune)
	BounceInches = 6,
	PocketClearInches = 1,
	-- The hit-stop at the flash (the look's frozen frame): every replay crawls through this
	-- much play (seconds) over HitStopSeconds more of wall time; the server waits for it.
	HitStopShotSeconds = 0.004,
	HitStopSeconds = 0.15,
}

-- Black Hole (docs/prompts/ABILITIES_PROMPT.md 7.12; src/shared/Ults/Effects/BlackHole).
Config.Ults.BlackHole = {
	-- Caps per use (5.7): at most this many of the shooter's balls and of the opponent's; the
	-- closest go first. Per ability so the ladder can climb (the step 16 balance pass). (tune)
	-- The step 16 balance pass (the designer's approved buff, 2026-09-29): 4 of yours and 1 of
	-- theirs: +1.21 / +1.36 / +1.39 careful net at skills 1/2/3 (3 and 2: +1.02 / +1.15 / +1.20),
	-- a Mythic above the Legendaries.
	MaxOwn = 4,
	MaxOpp = 1,
	-- It catches the shooter's balls within this of the hole (inches; the opponent's within
	-- Config.Ults.Shared.OpponentFactor of it), at most MaxReachShare of the table. (tune)
	RadiusInches = 20,
	-- It keeps catching balls that come in reach for this long after it opens (seconds).
	OpenSeconds = 2.5,
	-- A caught ball is dragged straight at the hole at StartSpeed + PullAccel x the time since
	-- it was caught (inches a second, a second squared), at most MaxSpeed, with Swirl of that
	-- speed sideways (the spiral). (tune: the look)
	StartSpeed = 2,
	PullAccel = 12,
	MaxSpeed = 60,
	Swirl = 0.6,
	-- Swallowed within this of the hole (inches); any caught ball still out this long after
	-- it opened goes anyway (seconds).
	SwallowInches = 0.5,
	GiveUpSeconds = 6,
	-- The cue ball is pushed this far straight away from the hole (inches), short of pockets.
	PushInches = 6,
}

-- Guangdong Tiger (docs/prompts/ABILITIES_PROMPT.md 7.13; src/shared/Ults/Effects/GuangdongTiger).
Config.Ults.GuangdongTiger = {
	-- Caps per use (5.7): at most this many of the shooter's balls and of the opponent's; the
	-- closest go first. Per ability so the ladder can climb (the step 16 balance pass). (tune)
	-- The step 16 balance pass (the designer's approved buff, 2026-09-29): 4 of yours and 1 of
	-- theirs: +1.22 / +1.34 / +1.34 careful net at skills 1/2/3 (3 and 2: +1.02 / +1.13 / +1.16),
	-- a Mythic above the Legendaries.
	MaxOwn = 4,
	MaxOpp = 1,
	-- The swipe cuts the shooter's balls within this of the first contact (inches; the
	-- opponent's within Config.Ults.Shared.OpponentFactor of it), at most MaxReachShare of the
	-- table. (tune)
	RadiusInches = 20,
	-- The moment slows for the tiger: this much play (seconds) over this much more wall time
	-- (about 0.7 s at a seventh speed: its leap in and the swipe; GuangdongTigerFx's timeline).
	SlowShotSeconds = 0.1,
	SlowSeconds = 0.6,
}

-- Portals (docs/prompts/ABILITIES_PROMPT.md 7.9; src/shared/Ults/Effects/Portals). Where they
-- may be placed is Config.Ults.Shared.Pick.
Config.Ults.Portals = {
	-- A ball goes in when its centre passes within this of a portal's centre (the drawn ring is
	-- a ball width across the middle of it). (tune)
	InnerRadiusInches = 2, -- 1.2 until the step 16 balance pass (2: +0.05 a use)
	-- After coming out, a ball cannot go into a portal again until it has left the exit's inner
	-- circle and this long has passed. (tune)
	CooldownSeconds = 0.3,
	-- One of the shooter's balls coming out is turned toward the pocket nearest its heading by
	-- at most this angle's tangent (0.2679: 15 degrees, as Chain Lightning's charge; 0 off).
	-- The step 16 buff. (tune)
	ExitSteerTan = 0.2679,
}

-- Eagle's Eye (docs/prompts/ABILITIES_PROMPT.md 7.2; src/shared/Ults/Predict.luau): the aim's
-- full path, the cue ball's and the first object ball's, from the real simulation.
Config.Ults.EaglesEye = {
	-- The drawn path keeps a point every this many fixed steps (240 Hz) between bounces: 6 is
	-- 40 points a second of travel, smooth enough for the curves spin and throw make.
	SampleSteps = 6,
	-- Each drawn path stops at this many cushion bounces (nil: every bounce to rest). The
	-- harness's lever if the worth comes out far over the Common row. (tune)
	MaxRails = nil :: number?,
}

-- Super Bounce (docs/prompts/ABILITIES_PROMPT.md 7.3; Arming.extras): the cue ball's own
-- material for the shot's first Seconds, then normal friction returns. Tuned 2026-09-29: a
-- medium shot (power 0.5) alone touches 6-10 cushions; on real tables (the harness's states)
-- the median is 4 (a quarter reach 6), the cue ball giving its speed to the balls it hits.
Config.Ults.SuperBounce = {
	RailRestitution = 1.0, -- no speed lost off a cushion (normal 0.85) (tune)
	RailFriction = 0, -- nor along it (normal 0.2) (tune)
	BallRestitution = 1.0, -- a perfectly springy hit on a ball (normal 0.95) (tune)
	-- Sliding and rolling losses: after each cushion the ball slides, and normal sliding
	-- friction would turn much of its speed into roll; tiny values keep it going. (tune)
	SlidingFriction = 0.005, -- normal 0.20
	RollingFriction = 0.0004, -- normal 0.010
	Seconds = 8, -- the cap: shot seconds with the material (tune)
	-- The first ball of yours the cue ball hits catches the bounce (never the 8; the designer,
	-- 2026-09-29, after the cue ball alone measured about +0.05 balls a use): this material
	-- from the hit for Seconds, and a cushion hit within JawReachInches of a pocket's rim
	-- boings it into that pocket (Effects/SuperBounce). Tuned with the harness (2026-09-29,
	-- skill 2, net balls a use): the material alone added +0.03 to +0.10 even at 30 s (a ball
	-- bouncing at random almost never finds a pocket); jaws 2/4/6/8 in +0.10/+0.20/+0.26/+0.28
	-- with the springier cloth; these cloth losses +0.34 to +0.39. (tune)
	Caught = {
		RailRestitution = 1.0, -- normal 0.85
		RailFriction = 0.03, -- normal 0.2
		BallRestitution = nil :: number?,
		SlidingFriction = 0.04, -- normal 0.20
		RollingFriction = 0.0017, -- normal 0.010
		Seconds = 8,
		JawReachInches = 6 :: number?,
	},
}

-- Magnet's physics (section 7.3; src/shared/Ults/Effects/Magnet.luau). Each allowed ball that
-- has been hit (it is moving) and is heading roughly toward a pocket inside that pocket's pull
-- zone has its heading turned toward an aim point just inside the mouth and its speed blended
-- toward CaptureSpeed, both harder the closer it gets: a fast ball is visibly caught and
-- eased in, a creeping one pulled over the lip. A ball at rest is never moved. Tuned by
-- tests/ult_magnet_test.luau (buffed 2026-09-28); every number (tune).
Config.Ults.Magnet = {
	-- The pull zone: a circle this many ball diameters in radius around the middle of each
	-- pocket's mouth. Nothing outside it is pulled. Was 3 before the buff, then 7.5; 5.25 on
	-- 2026-09-30 (the designer: 30% smaller). The field lines and the aiming preview's rings
	-- are drawn from it, so they shrink with it. (tune)
	ZoneBallWidths = 5.25,
	-- How the pull grows toward the mouth: strength = closeness ^ Power, closeness 0 at the
	-- zone's edge and 1 at the mouth (and past it). Scales both the turn and the speed blend.
	-- A whole number (it is multiplied out, never pow()). Higher keeps the pull near the
	-- pocket and makes the curve sharper at the end. (tune)
	Power = 2,
	-- How hard the path can bend at a corner mouth: radians of turn per inch rolled at full
	-- strength. Per inch rather than per second, so a slow and a firm ball curve alike. (tune)
	CornerBend = 0.3,
	-- The same at a side mouth: its window is narrower to angled balls, so it needs about
	-- twice the bend for the same rescue rates. (tune)
	SideBend = 0.6,
	-- The most one fixed step (1/240 s) may turn a ball, as the sine of the angle (0.1 = about
	-- 6 degrees), so a fast ball near the mouth is never snapped round. (tune)
	MaxStepTurn = 0.1,
	-- The path is traced with a ball this much fatter (inches): a path counts as going in, and
	-- is left on its line, only when it clears the jaws with this to spare. (tune)
	ClearanceInches = 0.1,
	-- The speed a pulled ball is blended toward (in/s): slow enough to drop through any jaw,
	-- fast enough to be seen creeping in. (tune)
	CaptureSpeed = 18,
	-- Braking of a faster ball: the share of its extra speed over CaptureSpeed taken off per
	-- inch rolled at full strength. Per inch, so a hard hit ball is caught over the same
	-- stretch as a soft one. (tune)
	BrakePerInch = 0.4,
	-- Pulling a slower ball up: the share of its missing speed added per second at full
	-- strength. Against rolling friction (about 4 in/s^2) this pulls in a ball that would
	-- have stopped within about 4 widths of the mouth; one dying further out stops about
	-- where it would have (6 widths out: 0.1 of a width nearer). (tune)
	CreepPerSecond = 1,
	-- Below this speed (in/s) a ball is not pulled at all: a ball at rest stays put. (tune)
	MinSpeed = 1,
	-- "Heading roughly toward the pocket": the cosine of the angle between the velocity and
	-- the direction to the pocket centre must be above this (0.5 = within 60 degrees). (tune)
	MinApproachCos = 0.5,
}

-- What every ability shares (docs/prompts/ABILITIES_PROMPT.md 5; the framework, step 1).
Config.Ults.Shared = {
	-- The skill rule (5.7): the area abilities (Magnet, Chain Lightning, Black Flash's blast,
	-- Black Hole, the Tiger) act on the opponent's balls too, at this share of the pull or push,
	-- and within this share of the reach for the ones that remove balls. (tune)
	OpponentFactor = 0.5,
	-- The default caps per use: at most this many of your balls and of the opponent's; when
	-- more are in range the closest go first. Each area ability sets its own (MaxOwn, MaxOpp
	-- in its block) since the step 16 balance pass. (tune)
	MaxOwnPerUse = 3,
	MaxOppPerUse = 2,
	-- No capture or push radius is ever more than this share of the table's playing length
	-- (100 in: 20 in), however the harness tunes it (5.3: "not half the table").
	MaxReachShare = 0.2,
	-- Aim-phase picks (Heat Seeker's ball, Portals' two spots), checked by the server.
	Pick = {
		-- A portal's centre must be at least this far from every cushion line and every ball
		-- centre (in ball diameters), from every pocket's opening edge, and this far from the
		-- other portal (inches). (tune)
		PortalClearBallWidths = 1,
		PortalMinGapInches = 12,
	},
	-- The reach preview while an area ability is armed and the player aims (5.7): a soft ring
	-- on the cloth at full reach, a dashed inner ring at the opponent's reach, a small red
	-- outline on each opponent ball inside it.
	Preview = {
		RingTransparency = 0.55,
		InnerRingTransparency = 0.6,
		ColorOwn = { 120, 220, 255 },
		ColorOpp = { 255, 90, 90 },
		OutlineTransparency = 0.25,
	},
	-- Rewind (7.6): the redo's shot clock, and how long the rewind moment lasts on screen.
	-- Measured (tools/ult_value.luau, 2026-09-29, balls a use at skills 1/2/3, careless):
	-- +0.16, +0.19, +0.20 (the redo is taken on 50-82% of uses), counting only the shot, under
	-- the Rare 1.0; the balance pass (step 16) decides the whole-turn measure.
	RewindRedoSeconds = 10, -- (tune)
	-- The redo's aim shows Eagle's Eye's full-path guide to its shooter (the step 16 buff: the
	-- second chance comes with the knowledge of how the first one went).
	RewindRedoGuide = true,
	-- How many redos one Rewind gives: each miss rewinds again until they run out (tune).
	RewindRedos = 2,
	RewindSeconds = 2.4, -- the table rewinding for everyone (tune)
	-- Time Stop (7.7): the freeze comes this long after the cue ball's first contact and lasts
	-- this long (the shooter's time to line up and strike; untouched, time resumes by itself);
	-- after the strike, time resumes this long after the cue ball touches a ball or a cushion
	-- (or drops, or stops). The designer, 2026-09-30: 8 s to line up one strike, resuming 1 s
	-- after it hits (was 5 s each for three, resuming 0.75 s after). (tune)
	FreezeAfterSeconds = 1,
	FrozenSeconds = 8,
	ResumeAfterStrikeSeconds = 1,
	-- How many strikes of the cue ball the shooter gets in stopped time (the designer,
	-- 2026-09-30: one; the step 16 buff had 3, measured +0.65 / +0.42 / +0.34 careful net at
	-- skills 1/2/3, 2 +0.58 / +0.38 / +0.24). With more than one, each strike's end starts the
	-- clock again for the next (FrozenSeconds).
	TimeStopStrikes = 1,
}

-- Uploaded ability assets (AbilityAssets loads the models once per server, on the server,
-- into ReplicatedStorage.AbilityAssets). Each row: an asset id (0 while not uploaded), and
-- the image ids its look needs. Filled as each ability is built.
Config.Ults.Assets = {
	Models = {
		-- tools/blender/abilities/magnet.py: FieldArcs, FieldFlares, FieldRing, Chevron and
		-- PoleCaps, one shared texture (MeshPart.TextureID), unit size (scaled at runtime).
		MagnetField = 96715013262604,
		-- tools/blender/abilities/superbounce.py: RainbowShell (a shell a little over the ball,
		-- its rainbow texture scrolled at runtime) and BoingRing (the hit's star-burst ring).
		SuperBounce = 75004032615944,
		-- tools/blender/abilities/ghost.py: LittleGhost (the ghost that circles the armed cue
		-- ball, facing -Z), GhostWisp (a trailing sheet, its wide root at +X) and Ripple (a
		-- flat ring).
		Ghost = 100126316259892,
		-- tools/blender/abilities/rewind.py: RewindDial (a flat counter-clockwise circular arrow
		-- with clock ticks, unit radius, magenta-white-green across its band).
		Rewind = 110978850889818,
		-- tools/blender/abilities/timestop.py: TimeBubble (a unit sphere with the warp pattern,
		-- drawn as ForceField), ClockFace (a flat ring of 60 ticks, unit radius) and ClockHand
		-- (a needle from its hub along +Z; the part's centre sits 0.365 of a unit up the
		-- needle from the hub).
		TimeStop = 113214769332073,
		-- tools/blender/abilities/chainlightning.py: Bolt1..Bolt4 Core and Glow (a unit-long
		-- jagged bolt with forks along X, flat in XZ, its box centred on the bolt's middle; the
		-- glow on every other point). Replaces 116394570082854 (the glow on every point).
		ChainLightning = 110751750592714,
		-- tools/blender/abilities/portals.py: PortalRim (a ragged torus of unit radius, flat),
		-- PortalCore (the thin inner ring) and PortalDisc (a flat unit disc with the swirl).
		Portals = 134871963661060,
		-- tools/blender/abilities/steelball.py: SteelShell (the manga steel ball, unit radius)
		-- and GoldSpiral (a flat spiral ribbon).
		SteelBall = 83844850418816,
		-- tools/blender/abilities/blackflash.py: BFBolt1..4 (thick black radiating bolts, unit
		-- length along X, flat) and Shard1..12 (the ball shell's pieces, the ball mesh's UVs).
		BlackFlash = 75008622077798,
		BlackHole = 86337602765410,
		-- tools/blender/abilities/tiger.py: the tiger's rigid parts (TigerTorso, TigerHead,
		-- TigerJaw, TigerLegFL/FR/HL/HR, TigerTail; facing -X, feet at Y 0, left at +Z), its
		-- joints (J_Head, J_Jaw, J_LegFL/FR/HL/HR, J_Tail), TigerSlash (a flat curved blade, 1
		-- long along X) and HalfA/HalfB (a unit ball's halves, the cut at Z 0, the ball's UVs).
		-- Replaces 86221317508788, 109390616019165 and 93994396609133 (redder, ringed
		-- stripes, a round-eyed face).
		GuangdongTiger = 119880658779603,
		-- tools/blender/abilities/heatseeker.py: Reticle (flat), ExhaustFlame (its nozzle at +X,
		-- its tip at -X) and SmokeRing (flat).
		HeatSeeker = 130162252552172, -- (the hotter flame; 81275063362861 was the first cut)
	} :: { [string]: number },
	Images = {
		-- The pocket-to-ball field lines' Beam tile: a white line and one arrowhead along +U.
		MagnetFieldBeam = "rbxassetid://138868230682274",
		-- Heat Seeker's exhaust smoke: a 4 x 4 flipbook of a puff swelling and thinning
		-- (heatseeker.py's smoke_flipbook.png).
		SeekerSmoke = "rbxassetid://81395420363490", -- (the image inside Decal 126970755165309)
		-- Rewind's VHS screen (rewind.py, each rendered on a transparent background): the big
		-- glitching rewind icon (a 4 x 4 flipbook), sparse grain (2 x 2), scanlines, tearing
		-- bands, one tracking-noise band, and the magenta and green split at the screen's
		-- edges. (The images inside Decals 71250904849806, 120393885666074, 82791665115124,
		-- 78629616715158, 92718377745753 and 79151185429591.)
		RewindIcon = "rbxassetid://79830999355189",
		RewindStatic = "rbxassetid://114309948120374",
		RewindScanlines = "rbxassetid://106680197039186",
		RewindTear = "rbxassetid://77495663973716",
		RewindTracking = "rbxassetid://80127029771602",
		RewindFringe = "rbxassetid://73954710228943",
		-- Time Stop's screen (timestop.py): the freeze's warp ring and stopped time's lens edge.
		-- (The images inside Decals 126594807194835 and 76685822924680.)
		TimeWarpRing = "rbxassetid://113854329541350",
		TimeLensEdge = "rbxassetid://113700118006901",
		-- Chain Lightning (chainlightning.py): the crackle flipbook (4 x 4), the round glow and the
		-- spark. (The images inside Decals 100855703223608, 94198140772777, 115799752256848.)
		ChainCrackle = "rbxassetid://132435040693570",
		ChainGlow = "rbxassetid://107241054746462",
		ChainSpark = "rbxassetid://77146187473853",
		-- Portals (portals.py): the swirl, the sparkle streaks and the exit's burst ring. (The
		-- images inside Decals 101107225209328, 106363579778020, 128288450574948.)
		PortalSwirl = "rbxassetid://85317008061907",
		PortalSparkles = "rbxassetid://110779778163475",
		PortalBurst = "rbxassetid://136798614538270",
		-- Steel Ball (steelball.py): the golden path on the cloth, the pot's burst ring and the
		-- sparkle. (Images inside Decals 95892418217107, 74393921524104, 74762707211639.)
		SteelPath = "rbxassetid://115232544003418",
		SteelBurst = "rbxassetid://140169441770879",
		SteelSparkle = "rbxassetid://116655548573479",
		-- Black Flash (blackflash.py): the shockwave ring. (Image inside Decal 112993995726160.)
		FlashRing = "rbxassetid://74704280023743",
		HolePop = "rbxassetid://121232364344408",
		-- Guangdong Tiger (tiger.py): the tiger-stripe fur frame (V chevrons of thin forked
		-- strokes on gold) with three claw slashes, the reference's flash frame. (Image inside
		-- Decal 87600337874853; replaces Decals 76952602462039 and 122114074802883.)
		TigerFur = "rbxassetid://131150432548296",
	} :: { [string]: string },
	-- The 13 icons (tools/blender/abilities/icons.py: Blender renders, 512 px, transparent),
	-- by ult id: the image ids (tools/upload_manifest.json's imageId, not the Decal ids).
	Icons = {
		Magnet = "rbxassetid://117672288856146",
		EaglesEye = "rbxassetid://81255543534825", -- an eagle's eye and brow line (2026-09-30)
		SuperBounce = "rbxassetid://95265934894642",
		Ghost = "rbxassetid://103298708355834",
		HeatSeeker = "rbxassetid://109084609734062",
		Rewind = "rbxassetid://120627614883189",
		TimeStop = "rbxassetid://88800552854518",
		ChainLightning = "rbxassetid://124544923626211",
		Portals = "rbxassetid://117852135071427",
		SteelBall = "rbxassetid://76826199313352",
		BlackFlash = "rbxassetid://100178683348331",
		BlackHole = "rbxassetid://75754504005260",
		GuangdongTiger = "rbxassetid://115608626042209",
	} :: { [string]: string },
	-- Sound sheets (5.5): each an uploaded audio id with its clips' start and length (s).
	Sheets = {} :: {
		[string]: {
			Id: string,
			Volume: number,
			Clips: { [string]: { Start: number, Length: number, Volume: number? } },
		},
	},
	LoadRetries = 3,
	LoadRetrySeconds = 2,
	-- The ReplicatedStorage folder the loaded models go in (src/client/AbilityModels.luau).
	FolderName = "AbilityAssets",
}

---------------------------------------------------------------------------------------------
-- Guideline
---------------------------------------------------------------------------------------------
Config.Guideline = {
	-- Length of the short lines drawn after first contact at their longest. Off a ball each is
	-- scaled by the share of speed it carries (Aim.Trace): the object ball's line is full on
	-- a straight-on hit and shrinks as the cut gets thinner, the cue ball's does the reverse,
	-- like the classic phone pool games. CueStubScale sets the cue line's longest relative to
	-- the object line's; RailStubScale is the fixed cue line off a cushion. A line shorter
	-- than MinStubInches is not drawn. (tune)
	StubLengthInches = 7, -- 16 made aiming too easy, then 11 and 8 still did (2026-09-23, 09-30)
	-- The longer lines kept for the first-time playthrough / tutorial (GDD section 14), where
	-- seeing exactly where the balls will go matters more than the challenge. Not wired yet.
	TutorialStubLengthInches = 16,
	CueStubScale = 1.0,
	RailStubScale = 0.6,
	MinStubInches = 0.4,
	-- The path is a corridor one ball wide: two thin solid edge lines a ball radius either
	-- side of the aim line, so what the cue ball clears or clips is obvious even from the
	-- low close-up view. A faint dashed centre line scrolls towards the target.
	EdgeWidthStuds = 0.05,
	EdgeTransparency = 0.25,
	ShowCentreLine = true,
	CentreLineTransparency = 0.5,
	LineWidthStuds = 0.07,
	DashTileStuds = 0.34,
	DashSpeed = 2.0, -- tiles per second
	DashFlip = true,
	-- The contact ("ghost") ball is a white ring outline, slightly larger than the ball.
	RingScale = 1.08,
	-- Images (assets/ui/guide_dash.png, guide_ring.png). Empty = plain shapes.
	DashTextureId = "rbxassetid://83727874065758",
	RingTextureId = "rbxassetid://137854164925995",
	HeightAboveClothInches = 0.15,
	-- Jump shots: a small, fainter ring where the cue ball comes down on the way (up to this
	-- many), and the red cross where it would fly off the table.
	MaxLandingMarks = 4,
	LandingRingScale = 0.6,
	LandingTransparency = 0.45,
	-- A jump shot's flight, drawn in the air where the levels say Arc (designer, 2026-10-02:
	-- see the ball go over the one in the way). Dots along the cue ball centre's path, every
	-- arc it hops, drifting toward the target at the dashes' speed, with a faint shadow line on
	-- the cloth under each arc. The flat corridor starts where the ball settles. (tune)
	Arc = {
		MaxDots = 120, -- dots in the pool; a longer flight stops drawing there
		DotSpacingInches = 1.4, -- between dots, along the flight on the cloth
		DotDiameterInches = 0.45,
		DotTransparency = 0.15,
		DriftInchesPerSecond = 2.5, -- the dots' drift toward the target
		ShadowTransparency = 0.7, -- the line on the cloth under each arc
		MaxHops = 8, -- arcs with a shadow line (Aim traces at most 8)
	},
	Color = { 255, 255, 255 },
	LineTransparency = 0.15,
	StubTransparency = 0.3,
}

---------------------------------------------------------------------------------------------
-- Audio
---------------------------------------------------------------------------------------------
-- These are our own recordings, uploaded to the group that owns the game, so they are used
-- by id with nothing to insert into the place. The one exception is the aim tick, which is
-- a UI click rather than a pool sound and has no recording yet.
--
-- Two separate mechanisms do the work here and they are not interchangeable.
--
--   VARIATION comes from several clips per event, never the same one twice running. This
--   matters more than any amount of pitch shifting: the ear spots exact repetition
--   instantly, and a single break makes over a hundred ball contacts, so one clack sample
--   is a machine gun however cleverly it is pitched.
--
--   DYNAMICS come from impact speed driving volume and pitch, on a LOGARITHMIC curve. See
--   SoundMix.loudness for the measurement that showed linear was wrong.
--
-- GAIN is a measured correction, not a taste setting. Every clip was played through an
-- AudioAnalyzer in Studio and its level recorded; the gain brings them to a common loudness
-- so that WHICH clip got picked does not change how loud the hit is. Skipping this lets the
-- random choice fight the speed curve, and the spread is not small: the rail recording is
-- the quietest thing here (peak 0.18) and the pocket drops are near full scale (0.91),
-- which is 14 dB apart. Re-measure with tools/measure_audio.luau if clips are replaced.
Config.Audio = {
	Clips = {
		-- Three takes, chosen by how HARD you hit rather than at random, because a tap and a
		-- break are different sounds and not the same sound at two volumes. The bands are
		-- given as power fractions in StrikeSoftUpToPower / StrikeHardFromPower below and
		-- turned into the cue ball speeds pickBanded compares against at the bottom of this
		-- file. Listed softest first. The edges are inclusive at both ends, so exactly on a
		-- line either neighbour may play, which takes the hard edge off the changeover.
		CueStrike = {
			-- cue_strike_2, peak 0.406. The softest take, up to StrikeSoftUpToPower.
			{ Id = "rbxassetid://73604297014560", Gain = 1.23 },
			-- cue_strike_1, peak 0.334. The middle of the bar.
			{ Id = "rbxassetid://125535762394405", Gain = 1.5 },
			-- cue_strike_3, peak 0.940, 0.627s. The hard take, from StrikeHardFromPower up.
			-- Gain levels its PEAK with the other two, but it is four times as long as
			-- cue_strike_2 and carries far more body, so it still lands as a much bigger
			-- sound - which is the point of it.
			{ Id = "rbxassetid://99994473089274", Gain = 0.53 },
		},
		-- Six ball-on-ball takes, including two with a slight rattle to them.
		--
		-- The SOFT take is banded to gentle contacts, because that is what it is a recording
		-- of: below 6 in/s it is the only thing eligible, so a ball rolling into another one
		-- clicks rather than thudding. From 6 to 25 all six are in the running and the
		-- choice is random, which blends the soft take into the rest instead of switching at
		-- a line. Above 25 the five firmer takes share it, as before.
		BallClack = {
			-- ball_clack_soft, peak 0.254
			{ Id = "rbxassetid://94692321009640", Gain = 1.97, FromSpeed = 0, UpToSpeed = 25 },
			-- ball_clack_1, peak 0.484
			{
				Id = "rbxassetid://71776844222034",
				Gain = 1.03,
				FromSpeed = 6,
				UpToSpeed = math.huge,
			},
			-- ball_clack_2, peak 0.312
			{
				Id = "rbxassetid://129164941963034",
				Gain = 1.6,
				FromSpeed = 6,
				UpToSpeed = math.huge,
			},
			-- clack_3, peak 0.523
			{
				Id = "rbxassetid://127287227972129",
				Gain = 0.96,
				FromSpeed = 6,
				UpToSpeed = math.huge,
			},
			-- TEMPORARILY OFF (designer, 2026-09-24): the two rattle takes, so every hit is a clean
			-- clack. Uncomment to bring them back.
			-- -- rattle_1, peak 0.425
			-- {
			-- Id = "rbxassetid://104388069204336",
			-- Gain = 1.18,
			-- FromSpeed = 6,
			-- UpToSpeed = math.huge,
			-- },
			-- -- rattle_2, peak 0.267
			-- {
			-- Id = "rbxassetid://84658060587712",
			-- Gain = 1.87,
			-- FromSpeed = 6,
			-- UpToSpeed = math.huge,
			-- },
		},
		-- One take for every cushion contact, soft through hard. The older, harder recording
		-- was dropped outright at the designer's call: it did not sound like a ball meeting
		-- a cushion. A clean sample carried across the range by volume and pitch beats an
		-- unconvincing one used at its "correct" speed.
		--
		-- The cost is variation: rails are the most frequent contact in the game after ball
		-- hits, and one take means one sample repeating. Speed-driven volume and pitch do
		-- most of the disguising, and Rail below carries extra pitch wobble of its own to
		-- help. A second cushion recording would fix it properly.
		RailThud = {
			-- soft, peak 0.955 - by far the hottest recording in the set, hence the low gain
			{ Id = "rbxassetid://95956239942472", Gain = 0.52 },
		},
		PocketDrop = {
			{ Id = "rbxassetid://139585329610041", Gain = 0.55 }, -- pocket_drop_1, peak 0.907
			{ Id = "rbxassetid://96380432160952", Gain = 0.59 }, -- pocket_drop_2, peak 0.841
		},
		-- A bright UI sting layered ON TOP of the drop, for the reward rather than the
		-- physics. It is the one sound here that is not a recording of something happening on
		-- the table, so it has to stay well under the drop: the drop is the event, this is
		-- the garnish. See Config.Audio.Bonus for how far under. It is private: it sounds only
		-- for the team that owns the ball, and only when the server grants it (Audio.grant,
		-- played by Audio.attach), so a drop with no grant stays silent - and a scratch is
		-- never a reward.
		PocketBonus = {
			-- ball_pocketed_bonus_sfx, peak 0.786, 3.496s
			{ Id = "rbxassetid://139288823087630", Gain = 0.64 },
		},
		-- A short crowd clap under NICE SHOT! (designer, 2026-10-05): the designer's "XMS
		-- CROWD Clap Small", cut to 1.8 s: full for 0.6 s (past the sting's opening hit, which
		-- buried a 0.25 s first cut), then a fast fade (assets/audio/NiceShotClap.wav), peak
		-- 0.93. Layered UNDER the bonus sting, never the main sound: Config.Audio.NiceClap.
		NiceClap = {
			{ Id = "rbxassetid://114608192396126", Gain = 0.54 },
		},
		-- The tick while the aim turns. A UI click, not a pool sound. Replace it the same way
		-- as the rest; this is v1 of the designer's own recording, in to be listened to.
		--
		-- v2, on trial. Its gain is measured so it reaches the mixer at the same level v1 did
		-- (0.055 volume x gain x peak = 0.028 either way), so what is being judged is the
		-- sound and not a volume change.
		--
		-- It is 0.059s where v1 was 0.107s, so ticks no longer come close to overlapping at
		-- the 0.1s gap below - that gap is now purely a choice about how busy the ratchet
		-- should be, not a limit the recording imposes.
		--
		-- To go back: rbxassetid://103816034774626 at gain 0.69 (v1, peak 0.729, 0.107s).
		AimTick = {
			{ Id = "rbxassetid://118414949820773", Gain = 0.99 }, -- turn_tick_2, peak 0.505
		},
	},

	-- The speed range the volume curve spans, in in/s, shared by every impact sound.
	--
	-- Measured over 48 shots at eight power settings: the median ball-on-ball contact is
	-- 3.6 in/s, the 90th percentile is 66.8, and a break tops 520. Quiet is where almost
	-- everything lives, which is why the curve is logarithmic and why these two numbers are
	-- a RATIO rather than a maximum. (tune)
	QuietSpeed = 10, -- maps to zero volume
	LoudSpeed = 400, -- maps to full volume

	-- Volume and pitch range per event. Pitch runs DOWNWARD with force: a harder contact
	-- gets the lower pitch, which is what makes it read as heavier. (tune)
	-- Ball-on-ball contact has its OWN quiet end, an order of magnitude below the shared one.
	-- Measured over 48 shots, 66% of all ball contacts happen below 12 in/s and the median is
	-- 3.6, so on the shared 10 in/s floor every one of those either never played or played at
	-- the same flat minimum - which is why gentle touches made no sound. Starting the curve
	-- at 1 in/s gives the bottom two thirds of the range somewhere to go. (tune)
	Clack = {
		MinVolume = 0.07,
		-- Raised from 1.0, but only a little: on a hard break NINE of these sound at once,
		-- and the stack is where a break's weight comes from (+9.5 dB) rather than the
		-- curve. Pushing the curve much past this risks nine voices summing into the master
		-- mixer's ceiling, and clipping is far uglier than being a shade quiet. Raise it if
		-- a break still wants more. (tune)
		MaxVolume = 1.1,
		MinPitch = 0.9,
		MaxPitch = 1.14,
		QuietSpeed = 1,
	},
	-- Rails sit WELL below ball-on-ball contact. They were about 2.4 dB under a clack at the
	-- same speed, which is far too close given they are the most frequent contact after ball
	-- hits (37 in a nine-shot test) - a cushion is a duller, quieter thing than two phenolic
	-- balls meeting, and a loud one every second is fatiguing. These are 10.1 dB down on the
	-- old values; lower MaxVolume further if rails still sit forward in the mix. (tune)
	Rail = {
		-- Barely there on purpose. Rails are the most frequent contact in the game after ball
		-- hits, and at the designer's call they should sit right at the back of the mix: a
		-- further 8 dB down on the already-reduced numbers, which puts a cushion about 25 dB
		-- under a ball-on-ball contact at the same speed. This is the one number to raise if
		-- they become inaudible rather than subtle. (tune)
		MinVolume = 0.014,
		MaxVolume = 0.1,
		-- Narrowed very slightly from 0.88..1.08 when the wobble below was added, so the two
		-- together stay inside the 15% the comment asks for rather than reaching 17%.
		MinPitch = 0.9,
		MaxPitch = 1.07,
		-- More wobble than everything else, because there is only ONE cushion recording and
		-- rails are the most frequent contact after ball hits. Pitch variation is a weaker
		-- disguise than having another take, but it is what there is. Keep the total spread
		-- (this plus the MinPitch..MaxPitch range) inside about 15% either way, or the
		-- sample stops sounding like a ball hitting a cushion and starts sounding like a
		-- synthesiser. Together these reach 0.855 .. 1.124, or -14.5% to +12.4%. (tune)
		PitchJitter = 0.05,
	},
	-- A ball in the air coming down on the slate (jump shots): the one cushion recording,
	-- pitched well down so it reads as a knock on stone rather than a rail, and far more
	-- present than a rail because it is rare and part of the trick. (tune)
	Land = {
		MinVolume = 0.05,
		MaxVolume = 0.5,
		MinPitch = 0.62,
		MaxPitch = 0.8,
		QuietSpeed = 4,
		PitchJitter = 0.04,
	},
	-- The strike gets its own speed range, tied to the cue itself. On the shared range
	-- (10..400) everything from about 93% power upwards produced an identical sound, because
	-- the cue ball left at up to 528 in/s then, and the whole top half of the power bar spanned
	-- barely 2.4 dB. Across the cue's own range the bar is audible end to end.
	Strike = {
		MinVolume = 0.35,
		MaxVolume = 1.3,
		MinPitch = 0.95,
		MaxPitch = 1.1,
		QuietSpeed = Config.Cue.MinSpeed,
		LoudSpeed = Config.Cue.MaxSpeed,
	},
	-- Where the three strike takes hand over, as fractions of the POWER BAR, because that is
	-- what the player is looking at when they decide how hard to hit. They are converted to
	-- cue ball speeds at the bottom of this file: power and speed are nothing like
	-- proportional (speed goes as power^2.6), so 25% of the bar is only 27 in/s out of 440
	-- and writing these as speeds would hide where the lines actually fall. (tune)
	StrikeSoftUpToPower = 0.25,
	StrikeHardFromPower = 0.75,
	-- A ball dropping is the payoff, so it stays loud whatever speed it went in at.
	Pocket = { MinVolume = 0.7, MaxVolume = 1.0, MinPitch = 0.96, MaxPitch = 1.06 },
	-- The bright sting over the top of the drop. Flat in VOLUME, like the drop: it is a reward
	-- for pocketing a ball, and a ball that trickles in earned it just as much as one that was
	-- smashed in. The volume is set so it lands about 16 dB UNDER the drop at the drop's
	-- loudest - there, felt more than heard, never the thing you notice first. It was 0.25
	-- (12 dB under) for a day and sat too far forward at the designer's ear. This is the
	-- number to move if it disappears or creeps back out in front. (tune)
	--
	-- The pitch is NOT random. It climbs with a RUN of bonuses played for this player and
	-- drops straight back at the strike after a shot that played none, so where it sits means
	-- something: the first bonus of a run is the plain sound, and a high one tells you you are
	-- several deep. Random drift was tried first and was the wrong idea - it made every
	-- pocket differ without any of them meaning anything, and a tonal sting that wanders
	-- just sounds out of tune.
	--
	-- The rungs of that ladder, in semitones above the plain sound, one per bonus. It is a LIST
	-- rather than a step size because which notes they are matters: balls often drop within a
	-- moment of each other, and then two rungs are sounding together as a chord whether that
	-- was intended or not.
	--
	-- A MAJOR SCALE: C D E F G A B C. A run walks up it a note at a time, which is what makes
	-- it read as climbing rather than as a series of unrelated pings. A flat semitone per ball
	-- was tried first and was wrong twice over - it is not a scale, and neighbouring rungs a
	-- minor second apart grind when two balls drop together. A major triad was tried after
	-- that and was wrong the other way: every pair of its rungs is consonant, but thirds are
	-- LEAPS, so it sounded like an arpeggio being outlined rather than a scale being walked.
	--
	-- The cost of a real scale is that two of its seven steps are semitones, E-F and B-C. A
	-- run deep enough to reach them AND two balls dropping close enough to overlap on exactly
	-- that pair is the one case that can still grind. Rare enough to be worth the scale.
	-- { 0, 2, 4, 7, 9, 12 } is the major pentatonic, the same walk with those two steps
	-- removed, if it ever turns out not to be. (tune)
	--
	-- It stops at the octave on purpose: a short bright sting pitched much past that stops
	-- sounding like itself and starts sounding like a chirp.
	--
	-- BaseSemitones transposes the whole ladder. The recording is not one note: it starts on a
	-- D and rises to a G inside itself, so played untouched a run began on D. -2 drops it a
	-- whole tone so the first ball of a run is a C and the ladder above reads as C D E F G A B
	-- C from its own root rather than from a D. It also buys headroom - the top rung now lands
	-- 10 semitones above the recording instead of 12. (tune)
	-- The interface's own sounds (src/client/UISound.luau): ranks, money and buttons. Not
	-- positional, well under the pool sounds. Placeholders from the Creator Store, listed in
	-- assets/audio/README.md; swap any by changing its id. An empty Id plays nothing.
	-- Overlap: several may sound at once (a clone per play) instead of restarting.
	-- Levels (designer, 2026-10-04: normalize): every clip here was measured through an
	-- AudioAnalyzer (its 90th-percentile RMS; peak for clicks and ticks) and the Volumes set so a
	-- sting lands near YourTurn's loudness (Volume x RMS about 0.045), the big moments (rank-up,
	-- new tier, the lucky block's build, the Secret heartbeat) a little over it. Before this the
	-- Secret heartbeat sat 8x and the rank fanfares 2x louder than everything else. Re-measured
	-- 2026-10-07 (designer: nothing should hurt): the reveals and the pull cutscenes' risers and
	-- hits, added since, sat 1.5 to 3x over and now cap at 0.06, a big moment.
	Ui = {
		-- "CoinTransfer_01" (Roblox, 1.7 s): a chip lands in the money HUD.
		CashLand = { Id = "rbxassetid://127645268874265", Volume = 0.3, Overlap = true },
		-- "Roblox_UI_Small_Click" (Roblox, 0.13 s), pitched up: the money count ticking.
		MoneyTick = { Id = "rbxassetid://15675032796", Volume = 0.12, Overlap = true, Pitch = 1.4 },
		-- "Roblox_UI_Bright_Click" (Roblox, 0.37 s): the XP bar filling (pitch rises, XpTickPitch).
		XpTick = { Id = "rbxassetid://15675059323", Volume = 0.15, Overlap = true },
		-- "Roblox_UI_Tonal_Stinger" (Roblox, 1.5 s): the XP bar reaching a division's top.
		XpFull = { Id = "rbxassetid://15675043410", Volume = 0.3 },
		-- Rank-up sound picked by the designer, 2026-10-03.
		RankUp = { Id = "rbxassetid://2789429656", Volume = 0.21 },
		-- "Glamour Fanfare 4" (APM Music via Roblox, 3.7 s): a new tier, the bigger fanfare.
		NewTier = { Id = "rbxassetid://1844584807", Volume = 0.23 },
		-- "RBLX UI Hover 01 (SFX)" (Roblox, 0.2 s, a soft tone near 900 Hz): the mouse or a
		-- gamepad on a badge or a roadmap tier (designer, 2026-09-27: short and pleasant; was
		-- "Roblox_UI_Cute_Pop", 2.7 s with its tail). Its 0.23 peak x 0.22 sits just under Click.
		BadgeHover = { Id = "rbxassetid://10066931761", Volume = 0.22 },
		-- "Roblox_UI_Small_Click" (Roblox, 0.13 s): a button pressed.
		Click = { Id = "rbxassetid://15675032796", Volume = 0.25 },
		-- The case reel (2026-09-28, overnight placeholders; assets/audio/README.md). All from
		-- Roblox's own library or APM Music via Roblox; each checked loading in this game.
		-- "Roblox_UI_Small_Click" (0.13 s), pitched up and quiet: one card passing the marker.
		LuckyPlace = { Id = "rbxassetid://4612375802", Volume = 0.28, Overlap = true },
		LuckyAnticipation = { Id = "rbxassetid://86828699372798", Volume = 0.2, Overlap = true },
		ReelTick = { Id = "rbxassetid://15675032796", Volume = 0.1, Overlap = true, Pitch = 1.7 },
		-- "Roblox_UI_Sweep" (Roblox, 0.61 s): the reel settling on the prize.
		ReelSettle = { Id = "rbxassetid://15675046931", Volume = 0.3 },
		-- "Roblox_UI_Whoosh_03" (Roblox, 1.1 s): the longer build-up before a Mythic or Secret.
		ReelBuild = { Id = "rbxassetid://15674975792", Volume = 0.35 },
		-- TRIAL (designer, 2026-10-04): Common to Rare play 4612378086 ("reward_screen_reveal")
		-- and, from 2026-10-05, Epic and up its bigger twin 4612378364 ("..._day5", 3.2 s). To go back, restore the orchestral stings: RevealLow 126239656683349
		-- (0.3), RevealRare 101099108525458 (0.28), RevealEpic 101099108525458 (0.31),
		-- RevealLegendary 83442240487773 (0.28), RevealMythic 83442240487773 (0.3);
		-- assets/audio/luckyblocks/README.md.
		RevealLow = { Id = "rbxassetid://4612378086", Volume = 0.2 },
		RevealRare = { Id = "rbxassetid://4612378086", Volume = 0.2 },
		RevealEpic = { Id = "rbxassetid://4612378364", Volume = 0.18 },
		RevealLegendary = { Id = "rbxassetid://4612378364", Volume = 0.18 },
		RevealMythic = { Id = "rbxassetid://4612378364", Volume = 0.18 },
		-- The win (designer, 2026-10-07): the old Rare reveal's orchestral sting (403300
		-- "Fast Orchestral WIN Celebration", assets/audio/luckyblocks/README.md), timed so its
		-- two hits land on a winner's Total and Continue (ResultScreen; Result.WinSting).
		ResultWin = { Id = "rbxassetid://101099108525458", Volume = 0.28 },
		-- "Riser_104" (the designer's file, trimmed to 1.5 s; peak at 0.45 s): the Rare pull
		-- cutscene's build into its white flash (Config.Cutscenes.Rare).
		RiserRare = { Id = "rbxassetid://97579914761531", Volume = 0.5 },
		-- "Riser_080" (the designer's file, trimmed to 2.7 s; peak at 1.98 s) and a pulsing bass
		-- hit ("InnerCircle01", 1.75 s, loud: kept low): the Epic pull cutscene, both from the
		-- fade to black (Config.Cutscenes.Epic).
		RiserEpic = { Id = "rbxassetid://96196182552147", Volume = 0.37 },
		ImpactEpic = { Id = "rbxassetid://124125612588605", Volume = 0.13 },
		-- The Legendary pull cutscene (Config.Cutscenes.Legendary), the designer's files trimmed
		-- (assets/audio/cutscenes): "Logo_Reveal_Sequence_01" (5 s: a bass drop at once, its
		-- impact at 4.0 s; loud, kept low), "Chaos-Rise" (from 1.8 s, 3.4 s: peak at 3.1 s) and
		-- "Cinematic-Hit-016" (from its onset, 4.5 s).
		LegendaryCinematic = { Id = "rbxassetid://111448999523683", Volume = 0.15 },
		LegendaryRise = { Id = "rbxassetid://119943211186448", Volume = 0.41 },
		LegendaryHit = { Id = "rbxassetid://98145599201576", Volume = 0.27 },
		-- "Aurora" (the designer's 214981, its first 40 s, 1 s fade in, 3 s fade out; quiet
		-- already): looped VERY faintly under the Legendary card (Config.Cutscenes.Legendary
		-- .Ambience).
		LegendaryAurora = { Id = "rbxassetid://138935380522596", Volume = 0.3, Looped = true },
		-- The Secret pull's heartbeat and shockwave (GUI lane, 2026-10-03; licensed library
		-- sounds: APM "Heart Beat", Pro Sound Effects "Thruster Blast 8").
		Heartbeat = { Id = "rbxassetid://1839088414", Volume = 0.12, Overlap = true },
		Shockwave = { Id = "rbxassetid://9120009360", Volume = 0.5 },
		-- "Roblox_UI_Tonal_Stinger" (1.5 s): a reward claimed (daily, playtime, index, code).
		Claim = { Id = "rbxassetid://15675043410", Volume = 0.3 },
		-- "Roblox_UI_Indicator" (3.4 s), quiet: a banner (Money Party, an announcement).
		Banner = { Id = "rbxassetid://15675085146", Volume = 0.3 },
	},
	XpTickPitch = { From = 0.9, To = 1.5 }, -- the XP tick's pitch across one fill (tune)
	MoneyTickEvery = 0.06, -- the money count ticks at most this often, seconds
	Bonus = {
		MinVolume = 0.16,
		MaxVolume = 0.16,
		MinPitch = 1,
		MaxPitch = 1,
		PitchJitter = 0,
		BaseSemitones = -2,
		StreakSemitoneSteps = { 0, 2, 4, 5, 7, 9, 11, 12 },
		-- The bonus is private, so the server grants it and the replay plays it on the drop.
		-- The grant is sent ahead of the replay; only a split packet brings it late, and one
		-- this long after its ball dropped still sounds. Later would read as a separate
		-- event rather than the ball's reward. (tune)
		LateSeconds = 0.25,
	},
	-- The NICE SHOT! clap's level (Clips.NiceClap). Measured in Studio (PlaybackLoudness at the
	-- pocket): at 0.09 the clap peaked at 82 against the bonus sting's 239 and nobody heard it
	-- (designer, 2026-10-05). Clapping is spiky: at 0.2 it peaked at 175 against 229 but
	-- averaged a third of the sting between claps; 0.26 matches the sting's peaks while its
	-- body stays well under the sting's (the sting is still the main sound). Played at the pocket with the NICE SHOT! pop, so everyone who sees the words hears
	-- it. (tune)
	NiceClap = {
		MinVolume = 0.26,
		MaxVolume = 0.26,
		MinPitch = 1,
		MaxPitch = 1,
		PitchJitter = 0.03, -- two nice shots in a row never clap identically
	},
	-- The shot clock's last seconds (designer, 2026-09-26): one clock tick a second from
	-- FromSeconds down to 1, for the shooter only, so they know to shoot now. Flat, not placed
	-- in the world: it is the clock in your head, like the power bar's stretch. The recording
	-- is APM's "TICK TOCK 06 120BPM" (Roblox's licensed library, courtesy of APM Music), a
	-- clock ticking once a second; only its first tick plays (Region, measured in Studio: the
	-- tick starts at 0.07 s and the next strong one at 1.07 s). Volume x the recording's 0.84
	-- peak sits just over the bonus sting (0.16 x 0.64 x 0.79). (tune)
	ClockTick = {
		Id = "rbxassetid://9043366464",
		Region = { 0.03, 0.45 }, -- seconds of the recording: its first tick, no tock after it
		FromSeconds = 5,
		Volume = 0.14,
		-- The last seconds tick a little higher, so the pressure climbs.
		FinalSeconds = 2,
		FinalPitch = 1.1,
	},
	-- The aim tick fires on every step of rotation, so it is the most repeated sound in the
	-- game by far and has to sit under everything: about 21 dB below a typical ball-on-ball
	-- contact and below even the QUIETEST audible clack, which is the bar it has to clear.
	--
	-- 0.055 is that level carried over exactly, not a fresh guess: the library click it
	-- replaced played at volume 0.12 against a peak of 0.230 at gain 1, so 0.028 reached the
	-- mixer, and the new clip's gain brings its 0.729 peak to 0.5, so 0.055 puts 0.028 back.
	--
	-- It was cut to 0.035 while MinSecondsBetweenTicks was 0.033, because at 30 ticks a
	-- second the clips piled three deep and a continuous sound is heard as far louder than
	-- an occasional one. At the 0.1 gap they no longer overlap at all, so that cut had
	-- nothing left to correct for and the measured level stands. This is still the number to
	-- move by ear if the tick sits too far forward or disappears. (tune)
	Tick = { MinVolume = 0.055, MaxVolume = 0.055, MinPitch = 1, MaxPitch = 1 },

	-- A touch of pitch wobble on every play, on top of the speed-driven pitch, so two
	-- identical impacts still differ. Keep it small: past about 15% a pitched sample stops
	-- sounding like the same object being struck and starts sounding like a synthesiser.
	PitchJitter = 0.04,

	-- A single break makes well over a hundred ball contacts (121 in one measured shot).
	-- Playing every one is mush and a frame cost, so the quiet ones are dropped and the
	-- rest are rate limited. Pocket drops deliberately bypass all of this.
	-- The quietest contact worth playing, per kind. These are separate because the two are
	-- nothing alike: a gentle ball-on-ball kiss is a real sound a player expects to hear,
	-- while a cushion brushed at walking pace is not, and rails are already the most frequent
	-- contact in the game.
	--
	-- The clack floor was 12, which silenced 66% of all ball contacts. It is now 1. Anything
	-- under about 0.05 in/s is two balls already touching being re-detected rather than a new
	-- contact, and must stay silent or a settled rack buzzes. Replaying the rate limiter
	-- against real event times, dropping the floor to 1 adds 81 audible clacks per 48 shots
	-- and masks no more loud contacts than before (189 against 188): during a break the loud
	-- hits are crowded out by OTHER loud hits, never by quiet ones. (tune)
	MinClackSpeed = 1,
	MinRailSpeed = 12,
	-- These two gaps ARE the rate limiter. There used to be a per-frame budget as well, but
	-- with a wall-clock gap per contact type at most one clack and one rail can start in any
	-- one frame, so a budget of three could never bind - it was dead config that read like a
	-- safety net. Being wall-clock, these bind at any frame rate.
	-- Loosened from 0.035 alongside the floor change. Replaying the limiter against real
	-- event times, most of the missing clacking was the FLOOR, not this: dropping the floor
	-- took a shot from 2.5 audible clacks to 4.5, while tightening this from 0.035 all the
	-- way to 0.010 only reaches 5.6 and takes the busiest single second from 13 clacks to 19,
	-- which is where a break turns to mush. 0.022 is 4.9 per shot at 15 in the busiest
	-- second. (tune)
	MinSecondsBetweenClacks = 0.022,
	-- A break should hit like one crack, not a tidy queue of clicks. Contacts at or above
	-- StackSpeed skip the gap above and are allowed to sound TOGETHER, which is what stacks
	-- them into a single transient.
	--
	-- 110 in/s is a clean discriminator rather than a guess. Measured on a full-power break,
	-- nine contacts land at or above it and every one of them falls inside the same 90 ms
	-- window, starting 0.091s in as the cue ball reaches the rack. At half power NOTHING
	-- reaches it. So this fires on a hard launch and stays completely out of the way of
	-- ordinary play, which is exactly the ask. Since the rack became a soft cluster
	-- (Physics.BallContactMicroseconds) 12-15 contacts clear it, all within the first
	-- millisecond; the ceiling below stacks the first ten and the rest are inside the same
	-- crack anyway.
	--
	-- Nine sounds of equal level sum to about +9.5 dB over one of them. That, and not the
	-- volume curve, is where most of a break's new weight comes from. (tune)
	StackSpeed = 110,
	MaxStackedClacks = 10,
	StackWindowSeconds = 0.1,
	-- Rails need their own, and a wider one: a break sends a burst of cushion contacts, and
	-- the soft cushion take rings for almost a second, so without this they pile up and
	-- drone. Widened from 0.05 when that take came in.
	MinSecondsBetweenRails = 0.07,
	-- And the tick needs one too, now that it is a real recording rather than a 22 ms click.
	-- A tick is asked for every Input.TickEveryDegrees (0.1) of rotation, so any real
	-- movement asks for far more than can be played; this is what decides how dense it
	-- actually gets. The old library click was short enough that it could never overlap
	-- itself and this never had to exist.
	--
	-- This is the number that decides the FEEL, and it is a ceiling on how fast the tick may
	-- repeat, not a rhythm: under the ceiling every 0.1 degree clicks, over it the extra
	-- steps are swallowed. So the two halves fall out of one number.
	--
	--   0.1 sets the ceiling at 10 a second, which at 0.1 degrees a tick is 1 degree per
	--   second. Adjust slower than that - which is what nudging by tenths IS - and every
	--   single step clicks. Sweep the aim faster and it stops trying to keep up and settles
	--   into a calm 10 a second however fast you go.
	--
	-- It was 0.033 for a moment, and that was wrong: 30 a second is a continuous ratchet
	-- three clips deep, which is far too busy for a sound that plays the whole time a player
	-- is aiming. Only the slow half of the range is worth tracking step for step.
	--
	-- 0.1 also happens to be just past the point where the recording stops being audible -
	-- turn_tick_1 runs 0.107s but spends 90% of its energy by 48 ms and is more than 34 dB
	-- down past 65 ms - so consecutive ticks no longer overlap at all. That is why Tick's
	-- volume below is back at its carried-over value rather than cut for a pile-up. (tune)
	MinSecondsBetweenTicks = 0.1,

	-- Sounds are emitted from where the contact happened, so a break sounds like it is
	-- spread across the table rather than coming from one point.
	--
	-- RollOffMinStuds is full volume out to that distance, and it has to sit ABOVE the
	-- camera's own working range or the mix changes with the zoom. The playfield is only
	-- about 16 x 8 studs (100 x 50 inches at 0.16 studs/inch) and the close view sits 2.2
	-- studs from the cue ball, so the old value of 8 put the camera inside the min distance
	-- when zoomed in and outside it when fitted - a loudness swing of about 3x from the
	-- zoom alone, which reads as "the volume is broken". Tables are 20+ studs apart,
	-- so a neighbouring game still attenuates properly. Measured in Studio: over a whole
	-- shot the camera sits 16.2 to 17.5 studs from the table and drops to 2.2 studs in the
	-- close aiming view, so 18 keeps the entire zoom range inside the plateau. (tune)
	RollOffMinStuds = 18,
	RollOffMaxStuds = 90,
	-- Roblox's default distance model (Inverse) attenuates as min/distance and never
	-- actually reaches zero, which makes RollOffMaxStuds a number that does nothing.
	-- InverseTapered keeps the realistic near-field curve and gives genuine silence at the
	-- far end. Held as a string because Config is loaded by the Lune tests, which have no
	-- Enum; Audio.luau maps it.
	RollOffMode = "InverseTapered",
	-- Roblox applies a Doppler shift from listener and emitter movement (SoundService.
	-- DopplerScale, default 1). The camera sweeps out to the whole-table view at the exact
	-- moment a break fires, and the roll emitter jumps between balls whenever the leader
	-- changes, so Doppler would warble every clip against the pitch this module is
	-- deliberately setting - and it would be very hard to recognise as Doppler. Off, so all
	-- pitch stays explicit.
	DopplerScale = 0,
	-- Roblox allows up to 10; this is a safety net so a gain and a volume cannot multiply
	-- into something that clips the mix. The loudest thing here is a clack at 1.97 (its
	-- MaxVolume of 1.0 against the 1.97 gain on the quietest take); the roll's first tier,
	-- which used to be the binding case, now reaches 0.76. config_test fails if any band and
	-- gain ever multiply past this, which would silently flatten the top of that sound.
	MaxVolume = 3,
	-- Emitters are pooled and reused rather than created and destroyed per contact. This
	-- caps how many can sound at once: past it, a new impact is dropped rather than
	-- stealing a voice, EXCEPT a pocket drop, which always gets one. (tune)
	MaxVoices = 32,
	-- The longest recording in the set (pocket_drop_1 is 4.144s). A voice is freed by the
	-- clip's own Ended event; this is only the fallback for when that never arrives. It has
	-- to be at least as long as the longest clip, because Sound.TimeLength reads 0 until the
	-- asset is cached - measuring the fallback off that would free a voice mid-drop and let
	-- the next contact cut it off.
	LongestClipSeconds = 4.2,

	-- Drawing the cue back stretches something. This is a recording of rubber under tension
	-- and it SWELLS over its 2.776 seconds (+7 dB from its first quarter to its last), so it
	-- is played straight from the start of a drag and its own build does the work, with
	-- volume and pitch following how far back the cue is on top of that.
	--
	-- Pitch rises with the pull here, the opposite of an impact: tightening something raises
	-- its pitch, while a harder knock reads as heavier and lower.
	--
	-- If the drag is held past the end of the clip it loops back to LoopStartSeconds rather
	-- than to zero, because the head of the recording is the quiet part and restarting there
	-- would drop the tension out from under a player who is still holding the cue back.
	Pull = {
		Id = "rbxassetid://131218253392089", -- measured peak 0.810, length 2.776s
		Gain = 0.62,
		-- One volume, played straight through. This used to scale with how far back the cue
		-- was, and it was wrong: the recording is quiet friction that only builds late (RMS
		-- 0.006 at its start against 0.025 near its end), so scaling the start DOWN as well
		-- left the first part of every pull all but inaudible - which is the part you hear
		-- most, because that is when your finger is moving. (tune)
		Volume = 1.2,
		-- The sound belongs to the MOTION of drawing back, not to the tension of holding
		-- there: it plays while the cue is actually being pulled further and goes quiet the
		-- moment it stops moving, the way real friction does.
		--
		-- StillSeconds is how long without any further pull counts as stopped. It has to
		-- clear the gaps between input events during a normal drag, or an ordinary finger
		-- would chop the sound up; 0.1s is several frames' worth of slack.
		StillSeconds = 0.1,
		-- The smallest increase in pull that counts as still dragging. A finger resting on
		-- the control jitters by well under a pixel's worth of this. (tune)
		MinIncrease = 0.003,
		-- Fades in and out, not because a fade should be heard but because cutting a
		-- sustained sound dead clicks. Both are too fast to read as fades. (tune)
		AttackSeconds = 0.02,
		ReleaseSeconds = 0.05,

		-- The recording ENDS with the band being released, and this sound must only ever be
		-- something being stretched. Measured through an analyser, that release is a single
		-- unmistakable transient at 2.539s: RMS 0.130 and peak 0.810, against nothing above
		-- RMS 0.029 or peak 0.13 anywhere earlier in the clip. Playback is held to the
		-- stretch before it, so the snap is never reached.
		--
		-- Playing past EndSeconds is impossible rather than merely unlikely: the Sound is
		-- given a playback region, so the engine itself will not go there.
		EndSeconds = 2.45,
		-- ...and a drag that outlasts the clip loops back into the middle of the stretch
		-- rather than stopping dead or starting over at the quiet opening. Only a drag with
		-- more than 2.45 seconds of CONTINUOUS motion ever reaches this.
		LoopStartSeconds = 1.0,
	},

	-- The roll is NOT a one-shot. It is one continuous sound for the whole table whose
	-- volume and pitch follow the fastest ball still moving, emitted from that ball so it
	-- travels with whatever is actually rolling. One sound rather than sixteen: sixteen
	-- loops would phase against each other and cost sixteen voices for something the ear
	-- hears as a single texture.
	--
	-- It is built from TWO alternating Sounds that crossfade into each other, because the
	-- recordings are not known to loop seamlessly and a seam in a loop clicks every couple
	-- of seconds - which, during the long quiet stretch of a shot, is the only thing you
	-- would hear. Crossfading means the raw join is never reached.
	Roll = {
		-- Slower rolls use the first tier, faster ones the second, per the recordings.
		-- Clip 1 measured 15x quieter than 2 and 3, so its gain is large; its noise floor
		-- sits 10.4 dB below its own average (2 and 3 are at 12.6 and 16.7), which is what
		-- says the material survives the boost rather than turning to hiss.
		Tiers = {
			{
				{ Id = "rbxassetid://133913351163474", Gain = 15.0 }, -- rolling_1, RMS 0.0036
			},
			{
				{ Id = "rbxassetid://132150152826928", Gain = 1.0 }, -- rolling_2, RMS 0.0548
				{ Id = "rbxassetid://101439770172296", Gain = 0.95 }, -- rolling_3, RMS 0.0581
			},
		},
		-- Ball speed (in/s) where the tier changes, and how far past it the speed must go
		-- before it does. Without the margin a ball hovering on the boundary retriggers the
		-- clip every frame. Measured: the table spends about a third of its moving time
		-- above 30 in/s. (tune)
		TierSpeeds = { 30 },
		TierMargin = 6,

		MinSpeed = 4, -- below this the table is silent
		LoudSpeed = 300, -- full volume; see QuietSpeed/LoudSpeed above for why it is a ratio
		-- The rolling clips are levelled on RMS and the impact clips on PEAK, which is right
		-- for each on its own - RMS is what you hear in continuous material, peak is what you
		-- hear in a transient - but the two families were never checked AGAINST each other,
		-- and at 0.45 the roll came out 4.2 dB above a ball-on-ball clack in RMS terms.
		-- Continuously, while a clack lasts 0.08s. So it sat on top of the whole mix.
		--
		-- At 0.10 it sits about 9 dB UNDER a clack, which is where a background bed belongs.
		-- This is the one number to move if the roll wants to be more or less present.
		-- (tune)
		MaxVolume = 0.1,
		MinPitch = 0.82,
		MaxPitch = 1.25,
		-- The first tier holds a single recording, so without this it would crossfade into
		-- the same 2.45 seconds of itself for as long as the table rolls slowly - which is
		-- about two thirds of a shot. Starting each pass at a random offset makes the
		-- repeat land on different material every time. Seeking makes the engine re-buffer,
		-- but that happens while the incoming clip is still silent at the start of its
		-- crossfade, so it cannot be heard. (tune)
		StartOffsetMaxSeconds = 1.2,
		-- Seconds for volume and pitch to follow a change. Without smoothing every collision
		-- steps the volume and it clicks. (tune)
		VolumeTau = 0.12,
		PitchTau = 0.09,
		-- How long the two clips overlap. (tune)
		CrossfadeSeconds = 0.35,
		-- ...but never more than this share of the clip, so a short recording cannot start
		-- handing over before it has properly begun. (tune)
		CrossfadeMaxClipFraction = 0.4,
		-- A random start offset must leave at least this many crossfades' worth of clip
		-- behind it, or the new voice would be due to hand over again almost at once. (tune)
		StartOffsetHeadroomCrossfades = 3,
	},
}

-- The cue skins' runtime (CueSkinLook, CuePiece, Effects; designer's rules 2026-09-30). Each
-- skin's own numbers (its aura, trail, pocket, piece) are data rows generated from assets/cue
-- (CueSkins); these are the rules for showing them.
-- FallGuard (server): anyone below the lobby floor is put back at the spawn at once, the last
-- resort against falling out of the map (designer, 2026-10-01). A player in a match is put
-- back at their table first (Multiplayer.QueueVisual.FallTolerance is smaller). (tune)
Config.FallGuard = {
	CheckSeconds = 0.1, -- how often every player's height is looked at
	BelowFloorStuds = 12, -- this far below the lowest floor (spawn or table) counts as fallen
	RiseStuds = 3, -- put back this far above the spawn mat, standing
}

Config.CueSkins = {
	-- ReplicatedStorage folder of the pieces' Edit-mode templates (tools/build_cue_templates).
	PiecesFolder = "CuePieces",
	-- A back-worn cue's aura emitters run at this share of their rate (1: the full aura; the
	-- designer, 2026-10-01: visuals first). (tune)
	BackRateScale = 1,
	-- On the back, an aura emitter whose particles grow wider than this (studs, about a torso)
	-- is a big camera-facing sprite: it is drawn this far behind the body (a ZOffset, studs) so
	-- it never covers the avatar. Smaller ones wrap round the body like any aura. (tune)
	BehindBodySizeStuds = 2.4,
	BehindBodyZOffset = -1.6,
	-- An Orbiter's glowing head is a short-lived particle re-emitted this often (per second)
	-- with this life (seconds): two or three overlap, so it reads as one steady glow. (internal)
	HeadRate = 24,
	HeadLifetime = 0.12,
	-- Effects are stepped on cues within this distance of the camera (studs); farther ones
	-- keep their particles but hold their scripted motion (orbiters, arcs, pulses, joints). (tune)
	StepDistanceStuds = 60,
	-- A skin's Aura.Highlight (an outline and soft fill on its 3D piece, so the dragon or the
	-- fox reads on the bright floor) shows only on cues within this distance of the camera
	-- (studs): Roblox draws at most 31 Highlights at once. (tune)
	HighlightDistanceStuds = 45,
	-- A cue switched in replaces the old one, in one frame, only once the renderer has loaded
	-- its look (designer, 2026-10-01; CueAssets: the maps of a SurfaceAppearance load only when
	-- one is drawn, so a hidden copy is drawn Transparency see-through in front of the camera
	-- until every texture reports loaded). The old cue shows meanwhile, so these waits cost no
	-- empty gap, only how soon after Equip the swap happens. (tune)
	Warm = {
		Transparency = 0.99, -- the hidden copy: drawn (the renderer loads it), never seen
		DistanceStuds = 10, -- from the camera, so it is always in view
		-- Where on the screen, in pixels from the top-left corner: under Roblox's own round
		-- menu button, which covers it and where nobody looks (designer, 2026-10-05; it was
		-- the middle of the view). The shrunk copy is about 20 px long, so it stays on screen. (tune)
		CornerPx = { 34, 30 },
		-- The copy (stick, piece and effect sprites) at this share of its size: at full size it
		-- showed as a faint ghost cue and a round blur across the view, plainest over a match's
		-- felt (designer, 2026-10-05, live). A few pixels at 1% is never seen; the renderer
		-- still draws it, so its textures still load. (tune)
		Scale = 0.05,
		MinSeconds = 0.25, -- drawn at least this long, and MinFrames frames, before it is ready:
		MinFrames = 8, -- the textures reach the graphics card a few frames after they download
		SettleSeconds = 0.25, -- every texture reports loaded for this long without a new fetch
		-- A texture the renderer has still not asked for after this long, with nothing else
		-- downloading (or after UnrequestedMaxSeconds anyway), came from Roblox's own cache on
		-- the device, which loads it without a fetch status. The renderer asks 0.7-1.1 s after
		-- a copy is first drawn (measured in Studio on a Mac, 2026-10-01).
		UnrequestedSeconds = 2,
		UnrequestedMaxSeconds = 5,
		-- A texture whose download failed (a dropped connection) is downloaded again, up to
		-- Retries times, a new failure looked for RetrySeconds after the last repair (Roblox
		-- never retries one on its own).
		Retries = 3,
		RetrySeconds = 1,
		TimeoutSeconds = 15, -- shown anyway after this, so a broken asset never hides a cue
		KeepSeconds = 60, -- a loaded copy stays drawn this long after last asked for (Equip
		-- after picking a cue in the inventory is then instant); then it is dropped
		MaxCopies = 6, -- at most this many loaded copies kept drawn (the oldest go first)
		-- Shot effects (a pocket finisher's creature, trail and pocket sprites) of the cues
		-- about to be played with: yours and everyone's at the drawn tables, looked up every
		-- ShotRefreshSeconds, at most MaxHeldShots kept loaded (yours and your table's first).
		MaxHeldShots = 8,
		ShotRefreshSeconds = 1,
		SpriteEmitSeconds = 0.25, -- how often each effect sprite's hidden particle is emitted
	},
	-- When a cue's look comes into view, each aura emitter emits this share of the particles it
	-- holds when running (rate x average lifetime) at once, so the aura is already there
	-- rather than growing in (designer, 2026-10-01). 0 turns it off. (tune)
	ShowPrefillShare = 0.7,
	-- The aura stays on the cue as you walk (designer, 2026-10-01: the flames smeared behind
	-- the player). Every cue emitter is LockedToPart (its particles move with the cue) except
	-- the tiny specks, whose largest size is at most MaxSizeStuds: they still drift off behind
	-- at RateScale of their rate, a faint wisp. An orbiter's ribbon (a world-space Trail)
	-- shortens toward MovingTrailSeconds as the stick moves at MovingSpeedStuds (studs per
	-- second, eased over MovingEaseSeconds), so it stays round the cue rather than streaking.
	Drift = {
		MaxSizeStuds = 0.3, -- (tune)
		RateScale = 0.5, -- (tune)
		MovingTrailSeconds = 0.1, -- (tune)
		MovingSpeedStuds = 6, -- a walk is 16 studs per second (tune)
		MovingEaseSeconds = 0.15, -- (internal)
	},
	-- Quieter auras in a match (designer, 2026-10-01: a big aura hides the table). The cue of
	-- whoever is shooting runs its aura at its tier's share below (emitter rates, aura beams'
	-- and lights' strength); on your own turn every cue at your table does, so your view is
	-- clear; a player waiting while someone else shoots has the full aura. AuraQuiet decides,
	-- the stick's AuraQuiet attribute carries it, CueSkinLook eases over FadeSeconds. The 3D
	-- piece, the orbiters and the moving material stay as they are.
	Quiet = {
		Shares = {
			Rare = 0.5,
			Epic = 0.5,
			Exclusive = 0.5,
			Rank = 0.5,
			Legendary = 0.25,
			Mythic = 0.25,
			Secret = 0.25,
			Unique = 0.25, -- the numbered Limited cues quiet like a Secret (designer, 2026-10-04)
		},
		DefaultShare = 0.5, -- a tier not listed (tune)
		-- A skin's own share, by catalog id, in place of its tier's: the two biggest auras
		-- are barely there while quiet (designer, 2026-10-01: 5-10%). (tune)
		SkinShares = {
			KitsuneCue = 0.07,
			CelestialDragonCue = 0.07,
		},
		FadeSeconds = 0.4, -- (tune)
		CheckSeconds = 0.2, -- how often the match state is looked at (internal)
	},
	-- The engulfing aura round a player (a skin's Carrier piece and its Carrier-host emitters,
	-- Secret cues) is gone while a shot is being watched at the owner's table and comes back
	-- between shots (designer, 2026-10-04): the match phases that count as a shot in flight.
	-- (It also goes while the stick is AuraQuiet: the owner shooting, or your own turn.)
	Carrier = {
		ShotPhases = { "Resolving", "Frozen", "Rewinding" },
		-- A Carrier piece and its hosts are modelled for the default R15 body, whose head top
		-- is this far above the HumanoidRootPart; the look lifts them by the difference to the
		-- carrying body's own head top, so a tall or short avatar wears them at its head
		-- (designer, 2026-10-04). (measured in Studio)
		HeadTopStuds = 2.1,
	},
	-- Every cue with an aura also wears a thin, faint outline of its colour (a Highlight on
	-- the stick), so it stands out on the bright lobby (designer, 2026-10-01; made much
	-- fainter and the tint over the whole cue dropped the same day). The colour is the
	-- skin's Aura.Outline, else its tier's below.
	-- A skin's aura sound (Aura.Sound in the skin data: the Beta Cue's faint hologram hum, the
	-- Grand Opening's crackles; designer, 2026-10-04): a looping Sound on the cue, local to
	-- this client, in the Sfx group (SoundGroups adopts it, so the Settings switch silences
	-- it), playing while the aura shows and scaled by the aura's quiet share. The skin's row
	-- gives Asset, Volume, Looped and may override the roll-off here.
	Sound = {
		AtStuds = 3.5, -- where on the cue it sits
		RollOffMinStuds = 3, -- full volume inside this
		RollOffMaxStuds = 24, -- silent beyond this
	},
	-- A piece joint's Type visual (the Beta Cue's blueprint panels, 2026-10-04): a SurfaceGui
	-- riding the joint that types made-up glyph strings, row by row, in step with the panel's
	-- life (its Period and Phase), then clears and starts over. Never readable words.
	Typing = {
		Font = "Code", -- Enum.Font: monospaced, techy
		Glyphs = "0123456789ABCDEF<>/|[]{}=+-*#%&^~:;._", -- the alphabet the gibberish is built from
		TokenMin = 2, -- glyphs per token (a "word"), min and max
		TokenMax = 5,
		PixelsPerStud = 160, -- the gui's canvas density (text crispness)
		Brightness = 2.5, -- SurfaceGui.Brightness: the text glows
		LineHeight = 1.25, -- row pitch as a share of the text size
		CursorGlyph = "_", -- blinks at the end of the typed text
		CursorPeriod = 0.5, -- seconds per cursor blink
	},
	Outline = {
		Colors = {
			Rare = "#2F8CFF",
			Epic = "#A040FF",
			Legendary = "#FFB000",
			Mythic = "#C06CFF",
			Secret = "#FF3048",
			Rank = "#FFB000",
			Exclusive = "#2F8CFF",
			-- Unique's pink is only the default: each Unique cue sets its own Aura.Outline
			-- (Beta electric blue, Grand Opening gold; designer, 2026-10-04).
			Unique = "#FF5CB8",
		},
		OutlineTransparency = 0.65, -- 0 a solid line, 1 none (tune)
		FillTransparency = 1, -- 1 no tint; lower tints the whole cue (tune)
		-- A skin's Aura.Highlight on its piece (the dragon, the fox) is never stronger than
		-- these: a soft edge, not a glow over it. (tune)
		PieceFillTransparencyMin = 0.85,
		PieceOutlineTransparencyMin = 0.6,
		-- The nearest cues' Highlights (outlines and pieces) only, at most this many: Roblox
		-- draws 31 at once and a match's ball outlines use up to 15. (tune)
		MaxShown = 14,
	},
	-- The pop pass (designer, 2026-10-05: the cues' textures and auras were lost on the bright
	-- roof). Additive glow (LightEmission 1) adds light to what is behind it, and on the cream
	-- floor and pale sky there is nothing left to add, so it vanished. CueSkins.Pop rewrites a
	-- cue's aura rows before they are built: emitters are deepened and drawn more as paint than
	-- as light; every aura beam and orbiter ribbon gets a dark, wider twin behind it (the
	-- backing a glow needs on a bright background); the stick wears a solid ink outline.
	Pop = {
		-- On test: only these cues' auras pop (the rewrite below). Remove Ids (nil) to pop every
		-- cue's aura. The outline is Outline.Every's.
		Ids = { "FrostbiteCue", "CandyCue", "FlareCue", "PlasmaCue", "GummyCue", "MagmaCue" },
		-- Aura emitters: LightEmission times this (1 unchanged, 0 plain paint), and each colour
		-- deepened: saturation raised by SaturationAdd, brightness times Value. (tune)
		Emitters = { LightEmissionScale = 0.4, SaturationAdd = 0.25, Value = 0.85 },
		-- Aura beams and orbiter ribbons: LightEmission times this on the bright layer. (tune)
		GlowLightEmissionScale = 0.6,
		-- The twin behind each aura beam and ribbon: drawn as paint (LightEmission 0), its colour
		-- saturated by SaturationAdd and darkened to Value times its brightness, Width times
		-- its width, Opacity times the layer's opacity, pushed ZOffset behind it. (tune)
		Backing = { SaturationAdd = 0.5, Value = 0.4, Width = 2, Opacity = 0.8, ZOffset = -1 },
		-- The stick's outline, solid, aura or not. Color "Theme" is the cue's own colour
		-- (designer, 2026-10-05: Frostbite light blue, not black): its Aura.Outline, else the
		-- first colourful one (MinSaturation) of its trail, pocket burst and stick colours,
		-- else Fallback (the UI's ink, for the grey cues); a hex colour instead puts
		-- every cue in that colour. The theme colour is saturated by SaturationAdd and its
		-- brightness times Value (0 and 1: as it is). (tune)
		Outline = {
			-- Every cue wears this outline (designer, 2026-10-05), not only the Ids above;
			-- false: only those. (tune)
			Every = true,
			-- A theme colour has to be at least this saturated (0..1): a near-white or grey one
			-- would vanish on the bright roof, so the next source is tried. (tune)
			MinSaturation = 0.3,
			Color = "Theme",
			Fallback = "#1B2033",
			SaturationAdd = 0,
			Value = 1,
			Transparency = 0,
			-- Up close Roblox thins a Highlight's outline to nothing (the aiming view), so the
			-- stick also wears ribbons LineStuds wider than the cue each side, in Pieces along
			-- it (the cue tapers), a rim that grows as the camera nears. EndStuds at each end
			-- narrow to the bare cue (no square ends). The ribbons are off while the stick has
			-- any camera fade (they showed over a see-through cue) and when the view is within
			-- MinViewDegrees of straight down the stick (designer, 2026-10-05: both seen on
			-- the back). (tune)
			Ink = { LineStuds = 0.012, Pieces = 8, EndStuds = 0.06, MinViewDegrees = 18 },
			-- Less flare on the lower rarities (designer, 2026-10-05; CueSkins.Pop.level): the
			-- ribbons' LineStuds times LineScale, and the Highlight this see-through instead of
			-- Transparency above (Roblox draws its line at one width). Common the least. (tune)
			ByRarity = {
				Common = { LineScale = 0.35, Transparency = 0.7 },
				Uncommon = { LineScale = 0.6, Transparency = 0.45 },
			},
			-- A moving gradient outline for these tiers (designer, 2026-10-05): up close the
			-- colours flow along the stick (the ribbons), Spread loops of the palette over its
			-- length; the Highlight (one colour) cycles through them. One loop takes Period
			-- seconds. Each cue's gradient is its own theme (designer: not one Mythic palette,
			-- "the blue is too off-putting" on Kitsune): a Palettes row by catalog id, else
			-- its vivid trail and pocket colours (CueSkins.Pop.palette). (tune)
			Gradient = {
				Tiers = { Legendary = true, Mythic = true, Secret = true },
				Palettes = {
					-- pink, pastel red, soft pink, a touch of light purple
					KitsuneCue = { "#FF78DC", "#FF8E9E", "#FF9FD6", "#C08CFF" },
					-- its cyan, azure and violet
					CelestialDragonCue = { "#3FD6FF", "#4FA8FF", "#8A5CFF", "#4FA8FF" },
					-- its gold, amber and warm light gold
					EclipseCue = { "#FFB300", "#FF9A1A", "#FFD27A", "#FF9A1A" },
				},
				Period = 3,
				Spread = 1,
				MaxColors = 4,
				MergeDegrees = 12, -- colours closer than this in hue count once
				ShineMix = 0.6, -- a one-colour cue shines toward white by this share
			},
		},
		-- The surface's glowing parts (its emissive map) times this. (tune)
		EmissiveScale = 1.6,
	},
}

Config.Effects = {
	-- Seconds for a pocketed ball to drop out of sight.
	SinkDropSeconds = 0.35,
	-- A pocketed ball drops in under real gravity (the physics drop, drawn as it is) and,
	-- rather than vanishing at the bottom, keeps falling and drifting outward as it fades out
	-- over PocketFadeSeconds. A slower "sit in the pocket, then roll out" version read as
	-- lowering rather than dropping, and was cut (2026-09-24). (tune)
	PocketFadeSeconds = 0.12,
	PocketDriftInchesPerSecond = 10, -- outward, as if running off into the gutter
	PocketGutterSpin = 8, -- radians per second the ball keeps turning as it rolls away
	-- A ball that flies off the table (jump shots) is drawn carrying on: it skips off the rail
	-- top if it comes down on it, drops a cloth's height to the floor, bounces at this
	-- restitution, rolls on the floor for FlyOffRollSeconds (slowing at FloorRollDecel), then
	-- fades over FlyOffFadeSeconds. The designer wants it seen landing and rolling before the
	-- foul (2026-09-24), so the server holds the foul for exactly this long (MatchEngine,
	-- Flight.floorTime). Cosmetic otherwise. (tune)
	FlyOffFloorRestitution = 0.4,
	FlyOffRailRestitution = 0.35,
	FlyOffRollSeconds = 1,
	FlyOffFadeSeconds = 0.35,
	FloorRollDecel = 40, -- in/s^2, a ball rolling on a hard floor
	FlyOffMaxSeconds = 5, -- gives up and hides it after this, wherever it is
	-- A soft round shadow on the cloth under a ball in the air, so its height reads on a
	-- phone: darkest right under a ball just off the cloth, fading out by FadeHeightInches.
	Shadow = {
		Color = { 0, 0, 0 },
		NearTransparency = 0.45,
		FadeHeightInches = 14,
		MinHeightInches = 0.03, -- below this the ball's own contact shadow is enough
		GrowPerInch = 0.04, -- the shadow widens a little as the ball rises (fraction per in)
	},
	PopupSeconds = 1.1,
	-- NICE SHOT! (designer, 2026-09-27): a gold word over the pocket and a sparkle burst when
	-- a good pot was not a plain one: a bank, combo, kick or carom (Rules/NiceShot). (tune)
	NiceShot = {
		-- A rail hit this close to a pocket's centre is its jaws or facings (a rattle, or a
		-- ball running along the cushion into the corner), not a bank or a kick.
		RailClearInches = 7,
		-- A drop the replay reaches this late (someone joining mid-roll catches up in one
		-- frame) gets no popup, so a late joiner is not shown a pile of old ones.
		FreshSeconds = 0.25,
		Seconds = 1.5, -- the word's whole life over the pocket
		FadeSeconds = 0.35, -- it fades over the end of that
		-- Just over the pocket, clear of the rail: any higher and a close camera puts it
		-- behind the top bar.
		HeightStuds = 1.1,
		RiseStuds = 0.5, -- it floats up this far as it lives
		-- On screen, the same size near or far; small (designer, 2026-09-27: 18 px, from the
		-- first 40 and then 22).
		SizePx = { 124, 28 },
		TextSize = 18,
		TiltDegrees = -6, -- a little jaunty
		RaysPx = 74, -- the gold rays turning behind the word
		RaysDegreesPerSecond = 90,
		SparkleCount = 26, -- gold sparkles thrown out of the pocket, on top of its burst
		SparkleSpeed = { 3, 6 }, -- studs per second: they stay round the pocket
		SparkleSeconds = { 0.4, 0.8 },
		SparkleSize = 0.35, -- studs
	},

	-- VFX are CUE DATA, not constants. Every catalog cue (Progression/Catalog) names a style
	-- here in its Effect, so equipping a rarer cue changes the cue ball's trail and the burst
	-- when a ball drops - which per GDD section 12 is the main reason to want one. The shooter's
	-- equipped cue (Config.Cue.EquippedAttribute) picks the style for their shots, and everyone
	-- at the table sees it. A new style is a row, never code.
	--
	-- DefaultStyle is the Classic cue's Effect (tests/cue_looks_test checks it), and what an
	-- unknown name falls back to. Every other row lists ONLY what differs from it: Effects
	-- fills in the rest of its Trail and Pocket from DefaultStyle's, key by key.
	--
	-- Beyond the default's keys a row may give (all optional):
	--   Trail.Colors      a list of colours run along the trail from the ball to its tail,
	--                     in place of the single Trail.Color
	--   Trail.Core        a thinner second ribbon inside the trail, for a glowing core:
	--                     { Color, Width (a share of the trail's width), NearTransparency,
	--                     LightEmission }
	--   Pocket.Colors     the burst's own colours, in place of the pocketed ball's: the
	--                     particles run through them over their life, the ring and the flash
	--                     take the first
	--   Pocket.ColorShare how far the ball's colour moves toward Pocket.Colors (0..1, default
	--                     1): below 1 it is a tint and the ball still reads through
	-- Rarity rows are placeholders (2026-09-28, overnight); real effects later only change rows.
	-- Every cue's ball trail is short and quick (designer, 2026-10-01: the special cues' ran
	-- over a second and looked choppy): its Lifetime (and its Core's) is at most
	-- TrailMaxSeconds, a little over the plain wisp's 0.34; its ball sprites live
	-- TrailEmitterLifetimeScale of their row's; a textured trail is stretched once along its
	-- length (TrailStretch), never tiled in a repeating chunk every TextureLength studs.
	TrailMaxSeconds = 0.45, -- (tune)
	TrailEmitterLifetimeScale = 0.5, -- (tune)
	TrailStretch = true, -- (tune)
	-- A pocket finisher's 3D creature (the fox, the dragon) stands out on the bright lobby
	-- (designer, 2026-10-01: it washed out): a dark outline (a Highlight, Occluded, fading with
	-- the creature) and its colour map tinted TintShare of the way to the skin's first pocket
	-- colour (a white spirit fox reads pink); while it shows, the pocket's flash is
	-- FlashScale as bright, its glassy ForceField shell ShellFade of the way to clear and its
	-- glow EmissiveScale as strong. A dark fill (FillTransparency below 1) greyed it: off.
	Finisher = {
		-- A skin's pocket sound (Pocket.Sound in the skin data: the Grand Opening's fireworks;
		-- designer, 2026-10-04), played once at the pocket; the row gives Asset and Volume and
		-- may override the roll-off; Seconds keeps the pocket's root alive for it.
		Sound = {
			RollOffMinStuds = 8,
			RollOffMaxStuds = 60,
			Seconds = 7,
		},
		OutlineColor = { 20, 10, 30 }, -- (tune)
		OutlineTransparency = 0.3, -- (tune)
		FillColor = { 0, 0, 0 },
		FillTransparency = 1, -- (tune)
		TintShare = 0.85, -- (tune)
		FlashScale = 0.35, -- (tune)
		ShellFade = 0.6, -- (tune)
		EmissiveScale = 0.4, -- (tune)
	},
	DefaultStyle = "Default",
	Styles = {
		Default = {
			-- The trail every common cue gets: a thin white translucent wisp, like wind
			-- coming off the ball. Deliberately understated - it is on screen for every
			-- shot of every game.
			Trail = {
				Enabled = true,
				Color = { 255, 255, 255 },
				-- Transparency at the ball end and at the tail end; it fades out behind.
				NearTransparency = 0.55,
				FarTransparency = 1,
				Lifetime = 0.34, -- seconds of tail
				-- The ribbon's width: how far apart its two attachments sit across the ball.
				-- 0.21 is the 1.1 ball radii it was always drawn at (this number was not read
				-- until 2026-09-28, when the rarer styles needed wider trails).
				WidthStuds = 0.21,
				LightEmission = 0.4, -- 0 draws the colour as it is (a dark trail), 1 glows
				-- How far the ball must travel before any ribbon is laid down. This, not a
				-- speed threshold, is what stops a ball creeping to a stop leaving a
				-- smear: a Roblox Trail draws nothing at all while its attachments are
				-- still, so it needs no help from us to go quiet.
				MinLengthStuds = 0.12,
				-- Texture is optional: with none, Roblox draws a plain tapered ribbon,
				-- which is already close to "wind". A sprite can be added later.
				Texture = "",
			},
			-- The reward when a ball drops: a gust of wind blowing up out of the pocket in the
			-- ball's own colour (Effects.pocketBurst). Made big on purpose (2026-09-23): it is
			-- the dopamine hit for pocketing, so it should feel like one. (tune)
			Pocket = {
				Enabled = true,
				EightBallScale = 1.6, -- the 8 gets a bigger gust
				-- The whole gust's size (its reach, height, speed, ring and flash; not how
				-- many particles, which stay few so low-end phones keep them). Rarer styles
				-- bring a bigger one.
				Scale = 1,
				CoreWhiten = 0.55, -- how far each layer's core runs toward white (dark balls still glow)
				LightEmission = 1, -- the particles and ribbons glow; lower lets a dark style read dark
				ParticleTexture = "rbxasset://textures/particles/sparkles_main.dds", -- built in
				SparkleTexture = "rbxasset://textures/particles/sparkles_main.dds", -- built in
				-- Swirling ribbons of wind corkscrewing up out of the pocket.
				Ribbons = 3,
				EightBallRibbons = 5,
				RibbonWidthStuds = 0.22,
				TrailSeconds = 0.35, -- how long each ribbon's tail lingers
				SwirlSeconds = 0.6, -- the climb
				SwirlHeightStuds = 4.2,
				SwirlStartRadiusStuds = 0.25,
				SwirlEndRadiusStuds = 1.1,
				SwirlTurns = 1.25,
				-- Streaks shooting straight up: particles squashed along their motion.
				Streaks = 16,
				StreakSpeedStuds = 16,
				StreakSizeStuds = 0.45,
				StreakSquash = -2.2, -- negative stretches them along their travel
				StreakLifetime = 0.5,
				StreakSpreadDegrees = 18,
				StreakDrag = 3,
				-- Sparkles drifting up after the gust.
				Sparkles = 14,
				SparkleSpeedStuds = 7,
				SparkleSizeStuds = 0.35,
				SparkleLifetime = 0.9,
				SparkleSpreadDegrees = 40,
				SparkleFallStuds = 3, -- they drift back down a little as they fade
				-- The flat shockwave ring on the cloth.
				RingStartStuds = 0.6,
				RingEndStuds = 5,
				RingSeconds = 0.45,
				-- A coloured flash in the pocket so the drop registers even at the view's edge.
				FlashBrightness = 6,
				FlashRangeStuds = 12,
				FlashSeconds = 0.35,
			},
		},
		-- One row per rarity (the catalog's block cues name their rarity; rank and special
		-- cues name the rarity their look matches). Colours from UI_STYLE section 4. (tune)
		-- Common: the very same plain wisp and gust as Classic (GDD 12).
		Common = {},
		-- Uncommon: the wisp, tinted a soft green; the gust stays the ball's own.
		Uncommon = {
			Trail = { Color = { 165, 240, 190 } },
		},
		-- Rare: a clear blue trail, a touch stronger, and the gust tinted blue half way (the
		-- pocketed ball still reads through).
		Rare = {
			Trail = { Color = { 90, 170, 255 }, NearTransparency = 0.45, LightEmission = 0.6 },
			Pocket = { Colors = { { 59, 155, 255 } }, ColorShare = 0.5 },
		},
		-- Epic: a lilac-to-purple trail that lasts a little longer, and a purple-to-pink gust
		-- in its own colours.
		Epic = {
			Trail = {
				Colors = { { 205, 160, 255 }, { 162, 89, 255 } },
				NearTransparency = 0.4,
				Lifetime = 0.4,
				WidthStuds = 0.24,
				LightEmission = 0.7,
			},
			Pocket = { Colors = { { 162, 89, 255 }, { 255, 120, 230 } } },
		},
		-- Legendary: a brighter, wider gold trail with a white-hot core, and a bigger gold
		-- gust with a brighter flash.
		Legendary = {
			Trail = {
				Colors = { { 255, 240, 170 }, { 242, 178, 0 } },
				NearTransparency = 0.3,
				Lifetime = 0.45,
				WidthStuds = 0.3,
				LightEmission = 0.9,
				Core = {
					Color = { 255, 255, 235 },
					Width = 0.35,
					NearTransparency = 0.2,
					LightEmission = 1,
				},
			},
			Pocket = {
				Colors = { { 255, 225, 120 }, { 242, 178, 0 } },
				Scale = 1.3,
				FlashBrightness = 8,
			},
		},
		-- Mythic: the pale holographic shimmer (cyan, lilac, pink, white) along the trail, and
		-- a bigger gust in the same pastels whose sparkles hang longer, like stars.
		Mythic = {
			Trail = {
				Colors = {
					{ 127, 231, 255 },
					{ 183, 156, 255 },
					{ 255, 156, 230 },
					{ 255, 255, 255 },
				},
				NearTransparency = 0.3,
				Lifetime = 0.5,
				WidthStuds = 0.28,
				LightEmission = 0.8,
			},
			Pocket = {
				Colors = {
					{ 127, 231, 255 },
					{ 183, 156, 255 },
					{ 255, 156, 230 },
					{ 255, 255, 255 },
				},
				Scale = 1.3,
				SparkleLifetime = 1.4,
				SparkleSizeStuds = 0.45,
			},
		},
		-- Secret: a near-black smoke trail with a red glowing core, and a red-to-black gust
		-- that reads dark (UI_STYLE 4's open suggestion for Secret).
		Secret = {
			Trail = {
				Color = { 14, 10, 14 },
				NearTransparency = 0.25,
				Lifetime = 0.45,
				WidthStuds = 0.28,
				LightEmission = 0,
				Core = {
					Color = { 255, 40, 50 },
					Width = 0.35,
					NearTransparency = 0.05,
					LightEmission = 1,
				},
			},
			Pocket = {
				Colors = { { 255, 50, 60 }, { 150, 0, 20 }, { 20, 0, 6 } },
				CoreWhiten = 0.15,
				LightEmission = 0.5,
				Scale = 1.3,
			},
		},
	},
}

Config.UI = {
	-- Spin selector: full-disc dragging, with 44 px Center/Done targets on small screens.
	Spin = {
		ToggleSizePx = 64, -- the left-middle cue-ball button
		MarginPx = 12,
		ToggleMarginPx = 18,
		BallSizePx = 150, -- full white disc maps to the existing legal spin range
		ButtonSizePx = 44,
		GapPx = 8,
		PanelWidthPx = 240,
		TextSizePx = 14,
		DotSizePx = 30, -- the strike point on the big ball
		IconDotSizePx = 14, -- the strike point on the left toggle
		CornerRadiusPx = 12,
		-- No dimming behind the spin picker: nothing darkens the screen, it is just a popup
		-- (designer, 2026-09-27). The see-through layer still catches taps outside it.
		OverlayTransparency = 1,
		BallColor = { 244, 244, 236 },
		DotColor = { 220, 75, 70 },
		-- Cue-angle slider beside the strike ball (jump shots, 2026-09-24). Tap or drag the
		-- track; the thumb shows the angle in degrees; top is the steepest.
		AngleColumnPx = 50, -- the slider's column, right of the ball
		AngleTrackWidthPx = 10,
		AngleThumbHeightPx = 26,
		-- A raised cue shows its angle under the left toggle, so it is never forgotten.
		AngleBadgeHeightPx = 20,
	},
	-- The zoom guide (src/client/ZoomHint.luau): just above the spin button while it is your
	-- turn, a mouse-wheel or pinching-hand icon and "Zoom In/Out", nothing behind them, greyed
	-- out so it reads as a control guide, not a button (designer, 2026-09-26). (tune)
	ZoomHint = {
		IconPx = 40,
		ShortIconPx = 32, -- a phone on its side
		TextSize = 16,
		ShortTextSize = 14,
		PaddingPx = 4, -- between the icon and the words
		GapPx = 10, -- between the guide and the spin button
		-- A light grey, clearly readable (designer, 2026-09-27: it was too faint).
		Tint = { 238, 238, 242 }, -- greys the icon and the words a touch
		IconTransparency = 0.1,
		TextTransparency = 0.05,
		OutlineTransparency = 0.25, -- the words' ink outline
	},
	-- The controller guide (PadGuide, designer 2026-09-27): a faint strip at the bottom left,
	-- above the money HUD, while it is your turn on a gamepad, and a Circle beside Leave.
	-- Roblox's own button glyphs; the kit's arrows beside the sticks.
	PadGuide = {
		GlyphPx = 30, -- a button or stick picture
		ShortGlyphPx = 24, -- on a phone on its side
		ArrowShare = 0.6, -- a chevron beside a stick, of the glyph (its image has padding)
		TextSize = 16,
		ShortTextSize = 14,
		PartGapPx = 2, -- between an item's pictures and its words
		ItemGapPx = 16, -- between the items in a row
		RowGapPx = 4,
		AboveMoneyPx = 10, -- the strip's bottom this far over the money HUD's top
		-- As the zoom guide: a light grey, clearly readable, but a guide rather than a button.
		Tint = { 238, 238, 242 }, -- the arrows and words
		GlyphTransparency = 0.1,
		IconTransparency = 0.1,
		TextTransparency = 0.05,
		OutlineTransparency = 0.25,
		LeaveShare = 0.75, -- the Circle beside Leave, of the Leave button's size
		LeaveGapPx = 4,
	},
	-- The power bar: a vertical panel on the right that you press and drag down, with the
	-- fill charging up behind it (PowerCue.place, every frame).
	--
	-- On a phone it sits HIGH, just under the top bar, rather than centred, because the cue
	-- drops a whole bar height below it at full pull and a centred bar pushes that off the
	-- bottom of the screen; its height is what the screen leaves, up to PowerBarMaxHeightPx.
	PowerBarWidthPx = 44,
	PowerBarMinHeightPx = 140,
	PowerBarMaxHeightPx = 250,
	PowerBarRightMarginPx = 18,
	-- On a phone the bar sits this far in from the right edge of the safe area. It used to
	-- reach a share of the side safe area (the strip Roblox keeps clear of the rounded corners
	-- and the notch), away from the aiming thumb (2026-10-02), but a real iPhone cut it off
	-- there (designer, 2026-10-06); the touch guard (TouchPull) now stops accidental shots.
	PowerBarPhoneRightMarginPx = 8,
	PowerBarPhoneInsetShare = 0, -- share of the side safe area the bar may reach into
	-- A computer or tablet (the screen at least Multiplayer.Style.ShortHeight tall) gets a
	-- bigger bar centred on the right edge (designer, 2026-09-26: it was small and too high).
	-- Centred, a whole-bar cue travel would leave the screen at full pull, so the cue slides
	-- PowerLargeCueTravelScale of the bar there: its bottom lands at 0.5 + (0.97 + 0.55 - 0.5)
	-- x 0.45 = 96% of the screen at full pull. (tune)
	PowerBarLargeWidthPx = 60,
	PowerBarLargeHeightFraction = 0.45,
	PowerBarLargeMaxHeightPx = 480,
	PowerLargeCueWidthPx = 20,
	PowerLargeCueTravelScale = 0.55,
	-- ...and sits this share of the screen above the centre (designer, 2026-09-27: a little
	-- higher). Its full-pull cue then ends 5% higher too. (tune)
	PowerBarLargeRaiseFraction = 0.05,
	PowerLargeLabelSize = 20,
	PowerBarTransparency = 0.15, -- the white track, a little see-through over the table
	PowerLabelSize = 16, -- PULL and the percentage over the bar
	-- Near full pull the fill fades into the house rainbow (Config.Ranks.ChatRainbow), its
	-- bands drifting down the bar, to show a powerful shot is coming (designer, 2026-09-30):
	-- from this share of the bar it starts mixing in (smoothly), and it is all rainbow at 100%
	-- (the label's own rounding). (tune 0.7-0.85)
	PowerRainbowFromPower = 0.75,
	-- One colour takes this long to travel the bar. (tune)
	PowerFullRainbowCycleSeconds = 1.2,

	-- ...and a top-down cue lying INSIDE that bar, which slides down as you pull. The cue is
	-- the player's equipped catalog cue (Catalog.style), so the cue they pull back is the one
	-- on their stick, and a new cue changes nothing here.
	PowerCueWidthPx = 15, -- at the butt, the widest point
	-- The cue nearly fills the bar at rest, and at full pull it slides a whole bar height -
	-- so it leaves the bar completely and hangs below it, which is what GamePigeon does and
	-- what makes a big pull look like a big pull. The bar deliberately does NOT clip its
	-- children, or the cue would be cut off at the bottom edge instead of travelling past it.
	PowerCueLengthScale = 0.97, -- of the bar's height
	-- A skin's picture (assets/cue/thumbs, rendered by CuePreview.py --thumb) has the cue this
	-- many times the picture's side long, leaning this many degrees right of upright (measured
	-- from the pictures, 2026-10-03: not 45, so turning it 45 left the bar's cue crooked). The
	-- power bar turns the picture back by the lean and sizes it so the cue keeps
	-- PowerCueLengthScale. Re-measure if the thumbnail camera changes.
	PowerCueArtLength = 1.12,
	PowerCueArtLeanDegrees = 37.45,
	PowerCueTravelScale = 1.0, -- of the bar's height, at full pull
	-- Slices used to draw the taper. A Frame cannot be a trapezoid, so the cue is built
	-- from thin bands; enough of them and the steps disappear. (tune)
	PowerCueSlices = 44,
	StatusTransparency = 0.35, -- the developer status line's ink backing (Config.Debug.ShowStatus)

	-- The sign over a table's queue pad (src/client/TableSign.luau). Only one shows: over the
	-- table you walk right up to, popping in, and never while you are in a box or playing
	-- (designer, 2026-09-25: it used to hang over all sixteen tables all the time).
	Sign = {
		ShowStuds = 6, -- it pops up within this far of the table's match area (tune)
		HideStuds = 8, -- and goes once you are this far out, so it does not flicker at the edge
		HeightStuds = 6.5, -- above the queue pad
		WidthPx = 220, -- its width on screen, pixels (the same at any distance); its height fits its rows
		MarginPx = 14, -- room round the card for its shadow and the pop's overshoot
		ModeTextPx = 34, -- the big 1v1, 2v2 or 3v3 (designer, 2026-09-27)
		InfoGapPx = 16, -- between the player count and the difficulty (designer: they touched)
		-- The count and difficulty words. Their earlier scaled text filled its 28 px row, past
		-- the kit's 16 px cap (a BillboardGui's scaled text did not take the cap), drawing
		-- about this big; kept so the sign looks the same (designer, 2026-09-27).
		InfoTextPx = 22,
	},

	-- The shared UI kit (src/client/HudParts.luau): the one look every screen is built from.
	-- docs/UI_STYLE.md; the designer's choices of 2026-09-25: white panels with a thick ink
	-- outline, a soft shadow and a faint pool-ball pattern; raised candy buttons in traffic
	-- colours; glossy cartoon icons. Colours are RGB 0-255.
	-- Rank badges (assets/ui/ranks, tools/gen_rank_badges.py; uploaded 2026-09-27), keyed by
	-- file name (Progression/Ranks.badgeKey). Each badge has a white shine mask of its shape
	-- that the light sweep is clipped to. How they shine: assets/ui/ranks/README.md and Shine.
	Ranks = {
		Badges = {
			unranked = "rbxassetid://85817045223700",
			bronze_1 = "rbxassetid://122609279357864",
			bronze_2 = "rbxassetid://98513469427482",
			bronze_3 = "rbxassetid://104525573584920",
			bronze_4 = "rbxassetid://73437113993546",
			bronze_5 = "rbxassetid://102497769305294",
			silver_1 = "rbxassetid://132013427876026",
			silver_2 = "rbxassetid://136857414187597",
			silver_3 = "rbxassetid://111963858575413",
			silver_4 = "rbxassetid://116771976750056",
			silver_5 = "rbxassetid://72710335902653",
			gold_1 = "rbxassetid://103406251248446",
			gold_2 = "rbxassetid://131967342541214",
			gold_3 = "rbxassetid://94235005188665",
			gold_4 = "rbxassetid://109610064722447",
			gold_5 = "rbxassetid://72528139389162",
			platinum_1 = "rbxassetid://123563259363618",
			platinum_2 = "rbxassetid://104769679771147",
			platinum_3 = "rbxassetid://91292511884342",
			platinum_4 = "rbxassetid://102686741608316",
			platinum_5 = "rbxassetid://104395401170387",
			diamond_1 = "rbxassetid://139623464291124",
			diamond_2 = "rbxassetid://89410647123532",
			diamond_3 = "rbxassetid://83576518316835",
			diamond_4 = "rbxassetid://85394843089261",
			diamond_5 = "rbxassetid://74377813086184",
			expert_1 = "rbxassetid://85497393392265",
			expert_2 = "rbxassetid://112301331501085",
			expert_3 = "rbxassetid://104613561854749",
			expert_4 = "rbxassetid://75924298250228",
			expert_5 = "rbxassetid://140536494582504",
			veteran_1 = "rbxassetid://117150895477573",
			veteran_2 = "rbxassetid://134806387656444",
			veteran_3 = "rbxassetid://137875853719727",
			veteran_4 = "rbxassetid://114326078662040",
			veteran_5 = "rbxassetid://119003709445636",
			master_1 = "rbxassetid://84787243033664",
			master_2 = "rbxassetid://132325068147761",
			master_3 = "rbxassetid://74764675181498",
			master_4 = "rbxassetid://91995598623992",
			master_5 = "rbxassetid://121857813241897",
			grandmaster_1 = "rbxassetid://136711422067518",
			grandmaster_2 = "rbxassetid://129767224344295",
			grandmaster_3 = "rbxassetid://83397655216067",
			grandmaster_4 = "rbxassetid://73037426483869",
			grandmaster_5 = "rbxassetid://110373976238540",
			reyes = "rbxassetid://85525344487370",
		},
		Masks = {
			unranked = "rbxassetid://86894285513434",
			bronze_1 = "rbxassetid://85181087151560",
			bronze_2 = "rbxassetid://122505119016095",
			bronze_3 = "rbxassetid://71651690464224",
			bronze_4 = "rbxassetid://119849788464461",
			bronze_5 = "rbxassetid://138788925666526",
			silver_1 = "rbxassetid://81284985811206",
			silver_2 = "rbxassetid://125527280070261",
			silver_3 = "rbxassetid://87984953107289",
			silver_4 = "rbxassetid://82827246176778",
			silver_5 = "rbxassetid://115615794826079",
			gold_1 = "rbxassetid://78254474255452",
			gold_2 = "rbxassetid://101782420274587",
			gold_3 = "rbxassetid://133699009224702",
			gold_4 = "rbxassetid://135482071212309",
			gold_5 = "rbxassetid://102100476621010",
			platinum_1 = "rbxassetid://111825725108333",
			platinum_2 = "rbxassetid://70725683729166",
			platinum_3 = "rbxassetid://109189858823297",
			platinum_4 = "rbxassetid://112184192867110",
			platinum_5 = "rbxassetid://78565686918078",
			diamond_1 = "rbxassetid://133556283098698",
			diamond_2 = "rbxassetid://71937062683469",
			diamond_3 = "rbxassetid://85854510500360",
			diamond_4 = "rbxassetid://114219595134971",
			diamond_5 = "rbxassetid://72823718113554",
			expert_1 = "rbxassetid://90124480372908",
			expert_2 = "rbxassetid://75819312890543",
			expert_3 = "rbxassetid://127776737648930",
			expert_4 = "rbxassetid://78706850549394",
			expert_5 = "rbxassetid://108129152305679",
			veteran_1 = "rbxassetid://125284521284134",
			veteran_2 = "rbxassetid://84569412963335",
			veteran_3 = "rbxassetid://73538697701693",
			veteran_4 = "rbxassetid://81191620254119",
			veteran_5 = "rbxassetid://108324078388123",
			master_1 = "rbxassetid://88614016352212",
			master_2 = "rbxassetid://77712090247966",
			master_3 = "rbxassetid://79152653883234",
			master_4 = "rbxassetid://75987876862643",
			master_5 = "rbxassetid://82957146712087",
			grandmaster_1 = "rbxassetid://93056769729177",
			grandmaster_2 = "rbxassetid://139737722919137",
			grandmaster_3 = "rbxassetid://82057808378194",
			grandmaster_4 = "rbxassetid://99132613759822",
			grandmaster_5 = "rbxassetid://106079198114272",
			reyes = "rbxassetid://72059479928036",
		},
		Sparkle = "rbxassetid://93784382803534", -- the white twinkle for Expert and up (128 px)
		-- The shine per tier band (README): a light sweep every Every seconds taking Across
		-- seconds; Sparkles twinkles one after another over a SparkleCycle; Reyes also turns
		-- gold rays behind it once every RaysSeconds. Unranked is still.
		-- Mostly sparkles, with a faint sweep now and then (designer, 2026-09-27: "the shimmer
		-- needs to be way less"; it was every 2-4 s at 0.35): more sparkles higher up.
		Shine = {
			Low = { Every = 9, Across = 1.1, Sparkles = 2, SparkleCycle = 2.6 }, -- Bronze to Diamond
			High = { Every = 8, Across = 1.0, Sparkles = 3, SparkleCycle = 2.0 }, -- Expert to Grandmaster
			Top = { Every = 7, Across = 1.0, Sparkles = 5, SparkleCycle = 1.5, RaysSeconds = 14 }, -- Reyes
		},
		ShineBandTransparency = 0.75, -- the idle sweep's brightest point: faint
		ShineRotation = 20, -- the sweep's slant, degrees
		RaysColor = { 255, 201, 40 }, -- Reyes' rays, #FFC928
		RaysTransparency = 0.55,
		RaysScale = 1.7, -- the rays are this many times the badge's size
		-- Where sparkles twinkle, as fractions of the badge (crown tips, wing tips, corners).
		SparkleSpots = {
			{ 0.5, 0.1 },
			{ 0.18, 0.4 },
			{ 0.82, 0.4 },
			{ 0.3, 0.2 },
			{ 0.7, 0.2 },
		},
		SparkleShare = 0.22, -- a sparkle's size as a share of the badge
		HoverScale = 1.08, -- a badge that reacts to the mouse pops up this much
		HoverShineEvery = 6, -- and sweeps this often while hovered (it sparkles as the mouse arrives)
		PressScales = { 0.9, 1.1, 1 }, -- the squish and bounce when pressed
		PressSeconds = 0.28, -- the whole squish and bounce
		-- (src/client/RankBadge.luau) Shine.High (sparkles) from this tier up; the top tier
		-- (Reyes) gets Shine.Top; below it, Shine.Low.
		HighShineFrom = "Expert",
		ShineBandWidth = 0.1, -- the sweep's band reaches this far either side of its middle (as UIAnim.shine)
		ShineBrightTransparency = 0.45, -- a pop's, press's or hover's brighter sweep (was 0.1)
		RaysCenter = { 0.5, 0.54 }, -- Reyes' rays turn about the 8 ball, as fractions of the badge
		SparkleMinPx = 28, -- a badge smaller than this on screen skips its sparkles (specks)
		RaysMinPx = 40, -- and Reyes' rays (they would cover what is round a small badge)
		BurstScale = 1.35, -- a rank-up's burst: the badge jumps to this size
		BurstGrowSeconds = 0.12, -- that fast
		BurstSettleSeconds = 0.45, -- then settles back with an overshoot
		BurstSparkleShare = 0.3, -- the burst's sparkles, one at every SparkleSpots spot, this big
		BurstSparkleSeconds = 0.55, -- each twinkle, in and out
		BurstStaggerSeconds = 0.07, -- one after another by this much
	},
	-- The rank and money screens (src/client/Progression.luau and the modules it owns).
	-- Pixel sizes are for a computer; phones scale down where noted. (tune)
	Progress = {
		-- The rank HUD, top left beside Roblox's buttons (RankHud; reference 02): the badge,
		-- bigger than the pill and over its left end, then a white pill with the rank's name over
		-- the XP bar. Laid out at these sizes (a phone, where it fits Roblox's 58 px top row),
		-- then scaled by ComputerScale on a computer or tablet, and down if the room is short.
		RankHud = {
			-- The badge's box, square. Its art fills the middle 76% (margins), so 58 shows a 44 px
			-- badge: as tall as the pill and Roblox's own top-bar buttons, in line with them
			-- (designer 2026-10-07: was 70, hanging below the row).
			BadgePx = 58,
			PendingDotPx = 24, -- the red "!" on the badge while rank rewards wait in Rank (RankPending)
			-- Its centre, as shares of the badge's box from the top left (designer 2026-10-07:
			-- was 0.14 down, which poked above the screen's top edge on a phone).
			PendingDotAt = { 0.84, 0.24 },
			PendingDotTextPx = 18,
			HoverScale = 1.06, -- the whole HUD grows this much under the mouse or a gamepad selection
			HoverSeconds = 0.18, -- that fast, with a small overshoot
			PillWidthPx = 196, -- the pill, from under the badge's centre to its right end
			PillHeightPx = 44, -- as tall as Roblox's own top-bar buttons
			PadPx = 6, -- inside the pill: after the badge, and at the right end
			NameTopPx = 3, -- "Gold III", this far down the pill
			NameTextPx = 18,
			BarHeightPx = 16, -- the XP bar's track
			BarBottomPx = 6, -- from the track's bottom to the pill's (the pill's outline takes 3)
			BarStrokePx = 2, -- the track's ink outline
			NumbersTextPx = 14, -- "520 / 1,000 XP", on the bar
			-- A computer or tablet (screen at least Style.ShortHeight tall): the whole HUD this
			-- much bigger and the badge alone BadgeScale more, about its centre (designer
			-- 2026-10-07: a phone's HUD sits in line with Roblox's buttons, a bigger screen's is
			-- bigger, the badge most of all).
			ComputerScale = 1.3,
			ComputerBadgeScale = 1.35,
			RowButtonTopPx = 12, -- Roblox's top-bar buttons (44 px) start this far down the row
			-- Never closer than this to the top of the screen. The HUD is lowered further when
			-- needed so the "!" dot stays on screen at its biggest (hover, press bounce, breath).
			TopMinPx = 2,
			TrackColor = { 214, 222, 235 }, -- the empty bar
			FillColor = { 255, 201, 40 }, -- the XP, gold
			FillShade = { 214, 150, 20 }, -- the fill darkens to this along its bottom
			DrainColor = { 255, 77, 77 }, -- the fill turns red while XP drains
			-- Reyes has no top: a full bar in the house rainbow (UI_STYLE section 4, VIP) that
			-- shimmers every ReyesShineEvery seconds.
			ReyesColors = {
				{ 255, 77, 77 },
				{ 255, 159, 28 },
				{ 255, 225, 77 },
				{ 61, 214, 107 },
				{ 59, 155, 255 },
				{ 162, 89, 255 },
			},
			ReyesShineEvery = 2.5,
			FillSeconds = 0.6, -- the bar filling or draining to a new value (each leg)
			FlashSeconds = 0.4, -- the flash as the bar crosses into another division
			TickEvery = 0.07, -- the XP tick sounds at most this often
			-- GUI lane (designer 2026-10-03, C3): white stripes slide along the gold fill, and
			-- when one win (vs an equal player) would rank up, the badge and bar wiggle with
			-- "ONE MORE WIN!" under the bar.
			OneMoreTextPx = 18,
			OneMoreGapPx = 2, -- under the pill
			-- A phone: the column starts right under the badge, so the words sit in the pill's
			-- name row instead, right-aligned and smaller.
			OneMoreShortTextPx = 12,
			-- The small badge under each portrait in the match bar (MatchHUD): this share of the
			-- portrait, its centre this share of the badge above the portrait's lower edge, so it
			-- overlaps the edge rather than growing the bar.
			PortraitBadgeShare = 0.72,
			PortraitBadgeRaise = 0.15,
		},
		-- The money HUD, bottom left (MoneyHud): the cash stack over the left end of a white
		-- pill with the total. Purely visual (takes no input), so the touch thumbstick under it
		-- still works. "Short" sizes are for a phone (screen under Multiplayer.Style.ShortHeight).
		MoneyHud = {
			ZIndex = 40, -- over the result screen and NEW RANK!, so their chips land on it
			MarginPx = 12, -- from the screen's bottom-left corner (a computer)
			ShortMarginPx = 8, -- on a phone: tight in the corner, clear of the thumbstick
			PillHeightPx = 32, -- the white pill with the total
			ShortPillHeightPx = 26,
			IconSizePx = 50, -- the cash stack, bigger than the pill, over its left end
			ShortIconSizePx = 40,
			IconOverPill = 0.55, -- this share of the icon's width sits over the pill
			TextPx = 20, -- the total ("$1,250")
			ShortTextPx = 16,
			TextPadPx = 10, -- room after the number inside the pill
			-- The shown total only rises when a chip lands. When the saved money changes and no
			-- chip is on its way, it counts to the true value after this long (long enough for
			-- a grant or result arriving just after the change to say its chips are coming).
			SettleDelaySeconds = 1.2,
			PendingTimeoutSeconds = 20, -- chips said to be coming that never land are forgotten
			LandCountSeconds = 0.35, -- the count-up when a chip lands
			SettleCountSeconds = 0.6, -- the count to the true value
			Sparkles = 4, -- little twinkles round the icon when a chip lands
			SparkleSizePx = 16,
			SparkleSpreadPx = 30, -- how far from the icon's centre they pop
			SparkleSeconds = 0.5, -- one twinkle, in and out
			-- The gold "+" at the pill's right end (designer, 2026-10-04): opens the Shop on
			-- its Money tab. Sized square; PlusOverPill of it sits over the pill's end.
			PlusPx = 30,
			ShortPlusPx = 24,
			PlusTextPx = 24,
			ShortPlusTextPx = 19,
			PlusOverPill = 0.5,
			PlusColor = { 255, 196, 0 }, -- the kit's gold
		},
		-- The flying cash from a pocket to the money HUD (CashFlyer): a chip (one cash bundle
		-- and "+$10") pops out at the pocket, hangs, then flies on a curve into the HUD's icon,
		-- about 1 s in all.
		Cash = {
			ZIndex = 45, -- over everything, the money HUD included
			ChipHeightPx = 36, -- the chip's height (a computer; 30 read small over the table)
			ShortChipHeightPx = 28, -- on a phone
			TextPx = 28, -- "+$10"
			ShortTextPx = 22,
			IconWidthShare = 1.4, -- the bundle is wide: its box is this many chip heights across
			PopSeconds = 0.2, -- pops out at the pocket with a small overshoot
			PopFromScale = 0.3, -- from this size
			HangSeconds = 0.25, -- then hangs
			FlySeconds = 0.55, -- then flies into the HUD
			EndScale = 0.45, -- shrinking to this size as it lands
			ArcLiftShare = 0.3, -- the curve's control point rises this share of the distance
			ArcMinLiftPx = 50, -- and at least this far above the start
			StaggerSeconds = 0.18, -- several pots in one shot follow each other by this much
			DropLeadSeconds = 0, -- added to the ball's drop time (the replay's; + later) (tune)
			MaxWaitSeconds = 15, -- a chip never waits longer than this for its drop
			EdgeMarginPx = 40, -- a pocket off screen starts this far inside the nearest edge
		},
		-- Over every character's head (Nameplates; reference 02): the rank badge, then the
		-- player's name. Its height is SizeStuds studs plus SizePx pixels: near plates grow with
		-- the world, far ones keep a readable floor. (tune)
		Nameplate = {
			UseDisplayName = false, -- false: the username (Player.Name), as the designer asked
			AlwaysOnTop = true, -- over the world (hats and walls never cut it); false to see it in Studio captures
			-- The plate's height in the world (the badge; the name is NameShare of it). Sized to
			-- read like reference 02 at a normal camera distance.
			SizeStuds = 1.1,
			-- ...plus this many pixels at any distance. In Studio this part drew far smaller than
			-- its number (STUDIO_NOTES), so the studs carry the size.
			SizePx = 8,
			NameShare = 0.55, -- the name's box, as a share of the badge's height (the badge art has margins)
			NameSlack = 0.08, -- extra room after the name for its outline
			GapShare = 0.12, -- between the badge and the name, as a share of the badge
			OffsetStuds = 3.2, -- the plate's middle, above the head's centre (clear of tall hats)
			FadeStartStuds = 45, -- from the camera: plates fade out from here...
			FadeEndStuds = 60, -- ...and are gone from here (the BillboardGui's MaxDistance)
			ShineDistance = 30, -- only badges this close to the camera shine
			UpdateSeconds = 0.2, -- the fade, outline and shine pass runs this often, not every frame
			FadeStep = 0.1, -- the fade moves in steps this big (fewer property writes)
			-- A win streak (designer, 2026-09-28): "🔥 3" on a line over the badge and name,
			-- from the first win in a row. The line's height, as a share of the plate's; the
			-- plate stays where it was and the line sits above it. (tune)
			StreakShare = 0.7,
			StreakFrom = 1, -- shown once the streak is at least this
			-- A VIP's rainbow name (designer, 2026-09-28: calm, the colours moving a little):
			-- one whole loop of the house rainbow drifts along the name. (tune)
			VipRainbowCycleSeconds = 8, -- a colour takes this long to travel the whole name
			VipRainbowStepSeconds = 0.05, -- the colours are moved this often (20 a second)
		},
		-- The end-of-match screen (ResultScreen): the face-off (a card per player, VS between,
		-- WINNER and a crown on the winner) and your rewards (the XP bar, the money list and
		-- its total chip), about 5 to 6 s in all. It is laid out at the natural size below and
		-- scaled to fit the screen: side by side on a wide screen, the rewards under the
		-- face-off on a narrow one.
		Result = {
			ZIndex = 30, -- over the match HUD; the money HUD and the chips stay over it
			-- 1 = clear: popups never darken the screen (designer; UI_STYLE section 2). The clear
			-- backdrop still takes the tap that speeds the screen up.
			BackdropTransparency = 1,
			UseDisplayName = false, -- false: usernames, as over the players' heads
			MarginPx = 10, -- kept clear round the screen's edge
			MaxScale = 1.25, -- grows up to this much on a big screen
			-- Natural sizes, side by side (the stage), in pixels before scaling.
			FaceWidth = 390, -- the face-off column
			RewardsWidth = 290, -- the rewards card
			ColumnGap = 20,
			Height = 300,
			-- The rewards card's faint 8-balls scroll up-left at 45 degrees like the lively Shop's
			-- header (designer, 2026-10-07: the same look, only moving), this fast along the line;
			-- each repeat shown Kit.PatternTilePx big, as the still pattern was.
			PatternPxPerSecond = 23,
			StackedFaceHeight = 250, -- stacked (a narrow screen): the face-off's height
			TitleHeight = 40, -- WINNER, DRAW or SOLO GAME over the cards
			TitleTextPx = 32,
			-- DEFEAT (TitleTextPx, red) over the losing side on WINNER's line (designer,
			-- 2026-10-07). When an 8-ball rule lost it for you, the reason goes under it at up to
			-- LossReasonTextPx (it shrinks to fit LossReasonHeightPx) and DEFEAT sits
			-- LossTitleLiftPx higher so the reason clears the rank badge.
			LossTitleLiftPx = 22,
			LossReasonTextPx = 18,
			LossReasonHeightPx = 40, -- two lines
			LossReasonTuckPx = 8, -- the reason starts this far up into DEFEAT's row
			LossReasonSpillPx = 12, -- the reason may run this far past each side of your side
			VsWidth = 70, -- the VS column between the sides
			VsTextPx = 44,
			PortraitPx = 120, -- a portrait on its own; team portraits share the side
			PortraitGap = 8, -- between team-mates' portraits
			NameHeight = 26, -- the name under a portrait
			NameTextPx = 18,
			TeamNameTextPx = 14, -- names under the smaller team portraits
			BadgeShare = 0.42, -- the rank badge on a portrait's outer top corner
			CrownShare = 0.55, -- the crown's width as a share of the portrait
			CrownOverlap = 0.35, -- this share of the crown sits over the portrait's top edge
			RaysShare = 1.9, -- the winner's rays, as a share of the side's width
			RaysTransparency = 0.35, -- the rays at their brightest
			CrownDropShare = 1.6, -- the crown drops from this many crown heights up
			LeftFade = 0.6, -- a player who left: their picture this see-through
			PaddingPx = 12, -- inside the rewards card
			XpHeight = 56, -- the XP block: badge, rank name, delta, bar
			XpBadgePx = 52,
			XpBarHeight = 20,
			XpNameTextPx = 20,
			XpDeltaWidth = 96, -- "+250 XP" (or "+0 XP": XP is never lost) right of the rank's name
			XpTextPx = 14, -- "520 / 1,000 XP" on the bar
			LineHeight = 22, -- one money line
			LineGap = 2,
			LineTextPx = 16,
			TotalHeight = 34, -- the Total pill
			TotalTextPx = 20,
			ButtonHeight = 44, -- Continue (a touch target)
			-- The card grows past Height when its contents need it (boosts, a streak line, the
			-- win's block); the whole screen still scales to fit.
			BlockGap = 6, -- between the card's parts (the XP, the boosts, the Total, the block chip)
			-- The XP boosts (ECONOMY 4.5; brief section 13): a chip each under the XP bar (only
			-- "STREAK +25%" since 2026-10-02; a boost of +100% or more would read as a
			-- multiplier, a smaller one as a percent), in rows as wide as the bar.
			BoostHeight = 20,
			BoostTextPx = 14,
			BoostGap = 6, -- between two chips, and between two rows
			BoostPadPx = 8, -- room each side of a chip's words
			-- Each boost's colour: a Kit colour name, or "Rainbow" (the house rainbow).
			BoostTones = { Streak = "Red" },
			BoostStagger = 0.08, -- the chips pop one after another with the XP
			-- The winner's lucky block (ECONOMY 7): "+1 Mystery Lucky Block" with the block,
			-- under the Total; the block then flies into the hotbar (or the Inventory tile).
			BlockChipHeight = 30,
			BlockChipTextPx = 16,
			BlockAfterSeconds = 0.2, -- it pops this long after the total chip flies
			BlockFlySeconds = 0.45, -- and its block flies this long after that
			-- Timings, seconds from the screen opening (a tap skips to the end).
			CrownAt = 0.35, -- the crown starts to drop
			CrownDropSeconds = 0.45,
			CrownWobbleDegrees = 6, -- then it rocks gently
			XpAt = 0.8, -- the XP bar starts
			XpFillSeconds = 1.1, -- the whole change, shared out over the divisions it crosses
			XpMinSegmentSeconds = 0.25, -- never quicker than this through one division
			-- A division reached: the bar holds full, solid yellow, saying NEW RANK! this long before
			-- the next division (designer, 2026-10-07; was a 0.35 s white flash).
			XpNewRankSeconds = 1,
			XpTickEvery = 0.07, -- the rising XP tick
			MoneyAt = 1.1, -- the money list starts (while the bar fills)
			LineSeconds = 0.32, -- each line pops and counts up in this
			TotalSeconds = 0.45, -- then the Total
			ChipDelaySeconds = 0.15, -- then the total chip flies to the money HUD
			ContinueDelaySeconds = 0.4, -- then Continue (it stays until pressed; designer 2026-10-07)
			-- A win instead plays to the sting (Config.Audio.Ui.ResultWin, designer 2026-10-07):
			-- its two hits, seconds into the clip (read off the file's low end).
			WinSting = {
				FirstHitSeconds = 0.05, -- the Total pops, its whole amount at once
				SecondHitSeconds = 0.19, -- the block chip and Continue pop
			},
			SkipGuardSeconds = 0.35, -- a tap this soon after a skip does not also close
			-- After a two-sided game a row under both columns replaces Continue (PostMatch,
			-- designer 2026-09-28): the series score, Rematch, Play another and Lobby (an arena)
			-- or Leave (a lobby table), and the seconds left to choose. The screen stays until
			-- the choice is made.
			ChoicesHeight = 58, -- the row, under the face-off and the rewards
			ChoicesGap = 10, -- between the columns and the row
			ChoiceButtonWidth = 150, -- each choice
			ChoiceGap = 8, -- between the choices
			SeriesWidth = 92, -- SERIES over "1 - 0", at the row's left
			SeriesLabelPx = 14,
			SeriesScorePx = 28,
			CountdownWidth = 44, -- the seconds left, at the row's right
			CountdownPx = 24,
			ChoiceTextPx = 18,
		},
		-- NEW RANK! (NewRankPopup), laid out at the natural size below and scaled to fit, so the
		-- badge is about 40% of the screen's short side. XP is never lost: no rank-down card.
		NewRank = {
			ZIndex = 32, -- over the result screen; the money HUD and the chips stay over it
			-- The dim behind it (designer, 2026-09-28: NEW RANK! sat awkwardly over the match
			-- results): black, fading to this transparency with the popup (0.5: a little dark;
			-- 1 would be clear again). It is this many screens plus this many pixels big, centred,
			-- so it spills past Roblox's top bar and a phone's notch and never shows an edge.
			-- The one popup that still darkens (designer, 2026-10-06): it stacks on the match
			-- results, so the dim sets it apart from the screen under it; the world blurs too
			-- (Config.UI.Blur). Everything else blurs only.
			BackdropTransparency = 0.5,
			BackdropOverScale = 2,
			BackdropOverPx = 400,
			MarginPx = 10,
			MaxScale = 1.35, -- grows up to this much on a big screen (1.75 made Continue huge)
			Width = 360, -- natural size
			Height = 340, -- with one row of chips (the rows set the real height)
			TitleTextPx = 40, -- NEW RANK!
			TierTextPx = 58, -- a new tier's name, huge: PLATINUM!
			TitleHeight = 54,
			TitleWidth = 480, -- the title may reach past the popup's sides
			BadgePx = 150, -- the new badge
			RaysShare = 2.2, -- the rays behind it, as a share of the badge
			RaysTransparency = 0.4, -- the rays at their brightest
			NameTextPx = 26, -- "Gold IV"
			NameHeight = 34,
			-- The reward chips (RewardChips; brief section 9): the money, each block ("x2"), the
			-- tier's cue and its chat tag, in centred rows under the name. A row may reach past
			-- the popup's sides like the title; more wrap onto a second row.
			RewardHeight = 32, -- a reward chip
			RewardTextPx = 20,
			ChipGap = 8, -- between two chips
			ChipRowGap = 6, -- between two rows
			ChipsMaxWidth = 520, -- a row of chips at most
			ChipStagger = 0.1, -- they pop one after another with the burst
			ItemFlyAfter = 0.3, -- the first block or cue flies to the hotbar or Inventory this long after the money
			ItemFlyStagger = 0.25, -- then each next one
			ButtonHeight = 44, -- Continue
			ButtonWidth = 160,
			Gap = 8,
			ConfettiScale = 1, -- the burst
			TierConfettiScale = 1.8, -- a new tier's bigger burst
			-- Timings, seconds.
			BurstAt = 0.3, -- the badge bursts and the confetti flies
			TierHoldSeconds = 0.7, -- a new tier: the old badge shows this long
			TierSpinSeconds = 0.45, -- then spins away into the new one
			TierSpinDegrees = 540, -- turning this far
			TierSpinEndScale = 0.15, -- and shrinking to this size
			RewardAt = 1.1, -- the reward chip flies to the money HUD (after the badge)
			ContinueAfterSeconds = 0.3, -- Continue pops this long after the burst
			-- Closes by itself (was 4 with the money chip alone; 5 gives the reward chips time
			-- to be read: overnight assumption, 2026-09-28).
			AutoCloseSeconds = 5,
			MinShowSeconds = 0.6, -- a tap on the backdrop closes it only after this
		},
		-- The rank roadmap (Roadmap; reference 03, designer 2026-09-27): the header, the ten
		-- tiers side by side, your rank's card and the chosen tier's rewards card, one line of
		-- rules. Sizes given as { a, b } run from a on the smallest panel (a phone) to b on a
		-- full-size one (DesignHeightPx tall); text shrinks with the panel down to MinScale. (tune)
		Roadmap = {
			DisplayOrderAbove = 10, -- its own ScreenGui sits this far over the HUD's
			-- The backdrop behind the panel (a tap on it closes); 1: clear, the world blurs
			-- instead (Config.UI.Blur; designer, 2026-10-06; was 0.45). Menus share it.
			DimTransparency = 1,
			DimSeconds = 0.2, -- the backdrop's fade in and out
			MaxSizePx = { 1120, 640 }, -- the panel's largest width and height (a computer)
			MarginPx = 4, -- the least gap between the panel and the screen's edges
			-- A screen shorter than this below Roblox's top bar is a phone: the panel also takes
			-- the top bar's row, its title right of Roblox's buttons, so the tiers keep their height.
			ShortScreenPx = 500,
			TopbarLeftFallbackPx = 212, -- where Roblox's buttons end, when Roblox does not say
			TouchMinPx = 44, -- the smallest touch target (UI_STYLE section 5)
			DesignHeightPx = 620, -- rows and text are full size at this panel height
			MinScale = 0.72, -- and shrink with a shorter panel, never below this share
			PaddingPx = { 6, 14 }, -- inside the panel
			GapPx = { 5, 8 }, -- between its rows
			HeaderPx = { 46, 68 }, -- the title row (on a phone: the top bar row's height)
			TitleScale = 1.2, -- "Ranked" is this much bigger than the kit's title size
			SubtitleMinPx = 120, -- a narrower room beside the title drops the subtitle
			CloseMaxPx = 48, -- the close X's largest size
			-- The tier row: the ten tiers side by side between a round < and > button. Yours is
			-- CurrentScale bigger and CurrentCellScale wider; as many show as fit (VisibleTiers).
			ArrowPx = { 44, 56 }, -- the round arrow buttons (never under TouchMinPx)
			ChevronShare = 0.75, -- the chevron image, of the button (its glyph fills 0.6 of it across)
			BadgeMaxPx = 140, -- a tier's badge at most (the row's height sets it below that)
			CurrentScale = 1.3, -- your tier's badge and dots are this much bigger...
			CurrentCellScale = 1.4, -- ...and its place in the row this much wider
			CellAspect = 1.2, -- a tier's place is at least this many of its badges wide...
			CellTextPadPx = 12, -- ...and this much wider than its name and its tag
			VisibleTiers = { 3, 6 }, -- the fewest and most tiers seen at once (as many as fit)
			TagPx = { 20, 26 }, -- the Current Rank and Next Rank tags' height
			TagAboveShare = 0.46, -- a tag's bottom sits this far over its badge's centre (of the badge)
			NameBelowShare = 0.4, -- a tier's name starts this far under its badge's centre (of the badge)
			DotPx = { 8, 12 }, -- a division dot under the name (yours CurrentScale bigger)
			DotGapShare = 0.6, -- the gap between two dots (of a dot)
			DotStrokePx = 1.5, -- a dot's ink outline
			DotEmptyColor = { 222, 227, 236 }, -- a division not reached (reached: Kit Gold)
			RingPx = 4, -- the gold outline round the chosen tier
			RingCornerPx = 16, -- its corners on a full-size panel (a phone's are 3/4 of it)
			RingFillTransparency = 0.84, -- the chosen tier's pale gold fill
			FocusRingTransparency = 0.5, -- a hovered or gamepad-focused tier's outline (not chosen)
			HoverScale = 1.06, -- a hovered or focused tier pops up this much
			PressScale = 0.92, -- a pressed tier squishes to this, then bounces back
			PressSeconds = 0.28,
			GlowScale = 1.6, -- the gold rays turning behind your badge (of your badge)
			GlowTransparency = 0.45,
			GlowDegreesPerSecond = 20,
			WheelStepPx = 160, -- one mouse wheel notch moves the row this far
			DragThresholdPx = 6, -- a mouse press moving further drags the row instead
			ScrollEaseSeconds = 0.09, -- the row's glide to a tier (time constant)
			LockedTint = { 150, 158, 175 }, -- a tier past your next: its badge tinted grey...
			LockedTransparency = 0.45, -- ...and see-through
			LockedTextTransparency = 0.35, -- its name and dots
			NextTagColor = { 110, 122, 145 }, -- the Next Rank tag (Current Rank: Kit Blue)
			-- The cards under the row: your rank (left) and the chosen tier's rewards (right).
			CardsPx = { 108, 190 }, -- their height
			RewardsShare = { 0.53, 0.46 }, -- the rewards card's share of the width (the rest: your rank)
			CardPadShare = 0.07, -- inside a card (of its height)
			RankBadgeShare = 0.94, -- your badge on the rank card (of the card's height)
			CardTint = 0.3, -- the rank card fades to this much of your tier's colour
			NextRowShare = 0.2, -- the next-division line (of the card's height; at least a text line)
			NextArrowShare = 0.8, -- its arrow (of the line)
			NextBadgeShare = 1.3, -- its small badge (of the line; pokes out)
			ChipIconShare = 1.2, -- the cash on its money chip (of the chip; pokes out)
			BarBackColor = { 222, 227, 236 }, -- the XP bar's empty part
			BarTopColor = { 255, 236, 150 }, -- its fill fades from this to Kit Gold
			TileGapPx = { 4, 8 }, -- between two reward tiles
			TileCornerPx = { 8, 12 },
			TileStrokePx = 2, -- a tile's outline...
			TileEdgeColor = { 178, 196, 224 }, -- ...pale, so the tiles sit quietly in the inked card
			TileCheckShare = 0.26, -- the green check on a reward you have (of the tile's height)
			NudgeScale = 0.94, -- the tiles pop from this size when another tier is chosen
			NudgeSeconds = 0.25,
		},
		-- The reward chips (RewardChips) on the result screen and NEW RANK!: a white pill with
		-- the picture then the words; and a block or cue flying from its chip to the hotbar or
		-- the left column's Inventory tile (they show meanwhile, even under a popup).
		Chips = {
			PadPx = 6, -- before the picture
			GapPx = 4, -- between the picture and the words
			EndPadPx = 10, -- after the words
			CashWidthShare = 1.3, -- the cash bundle is this many of its heights wide
			ZIndex = 45, -- the flying copies, over everything (as the cash chips)
			PopSeconds = 0.18, -- the copy pops up off its chip...
			PopScale = 1.3, -- ...to this size
			HangSeconds = 0.2, -- hangs
			FlySeconds = 0.6, -- then arcs into the tile
			EndScale = 0.5, -- shrinking to this size as it lands
			ArcLiftShare = 0.3, -- the arc rises this share of the distance first
			ArcMinLiftPx = 50, -- and at least this far
			HoldSeconds = 0.8, -- the column stays this long after the last copy lands
			LandSound = "Click", -- a Config.Audio.Ui key: the tile catching it
			LandPitch = 0.8,
		},
		-- Confetti (UIAnim.confetti).
		Confetti = {
			Count = 36, -- pieces in one burst
			Seconds = 1.6, -- how long a piece falls
			SizePx = { 6, 12 }, -- smallest and largest piece
			SpreadPx = 260, -- how far pieces fly out sideways
			RisePx = 180, -- how high they are thrown before falling
			FallPx = 420, -- how far they fall
		},
		CountUpSeconds = 0.6, -- a number counting to a new value (UIAnim.countUp)
	},
	Kit = {
		Font = "FredokaOne", -- Enum.Font name; Config is loaded by Lune, which has no Enum
		Colors = {
			Ink = { 27, 32, 51 }, -- #1B2033: outlines on panels, buttons, balls and all text
			White = { 255, 255, 255 }, -- panels and body text
			Soft = { 214, 226, 245 }, -- secondary text: still white-ish, set apart from headings
			Green = { 61, 214, 107 }, -- ready, go, your turn, the active shooter
			Red = { 255, 77, 77 }, -- foul, danger, low clock
			Blue = { 59, 155, 255 }, -- the house accent: selected things, called pockets
			Gold = { 255, 201, 40 }, -- special: the coin, SOON, gamepad selection
			Grey = { 156, 163, 175 }, -- pocketed balls and anything switched off
		},
		PanelFade = { 226, 238, 255 }, -- panels fade from white at the top to this pale blue
		PanelStrokePx = 3, -- the ink outline round every panel
		PanelCornerPx = 16, -- panel corner radius
		-- A menu's panel (HudParts.menuCard; the roadmap, the host menu, later the shop), after
		-- the designer's Ranked reference (2026-09-27): a pale-blue header band for the title,
		-- and the content on a near-white sheet with big rounded top corners and a thin
		-- light-blue edge. Colours measured off the reference. (tune)
		HeaderTop = { 222, 239, 254 }, -- the band at the panel's top...
		HeaderBottom = { 208, 234, 253 }, -- ...deepening a little toward the sheet
		SheetTop = { 252, 253, 255 }, -- the sheet, nearly white at its top...
		SheetBottom = { 236, 244, 253 }, -- ...fading to a pale blue at the bottom
		SheetEdge = { 176, 216, 250 }, -- its thin edge (light blue, not ink)
		SheetEdgePx = 2,
		-- A pale-blue outline in place of the ink one round a menu's panel and its cards
		-- (designer, 2026-10-06), on the menus in Config.UI.Menu.PaleEdgeMenus. (tune)
		PaleEdge = { 176, 216, 250 },
		SheetCornerPx = 22, -- its rounded corners: the header's curve
		SheetInsetPx = 6, -- in from the panel's outline at the sides and bottom
		PillCornerPx = 999, -- pills are fully round at the ends
		-- The shadow under panels: a 9-slice blurred square (tools/gen_ui_art.py shadow.png).
		ShadowImage = "rbxassetid://73622387505906",
		ShadowSlice = { 48, 48, 80, 80 }, -- SliceCenter in the 128 px image, pixels
		ShadowSpreadPx = 14, -- reaches this far past the panel on every side
		ShadowDropPx = 6, -- and sits this far lower, as if lit from above
		ShadowTransparency = 0.72, -- 0.5 read as a dark smear under a small panel (tune)
		-- The faint pattern over every panel (pattern.png, tiled): soft pale-blue 8 balls of a
		-- few sizes, each turned its own way, and small bubbles, after the designer's reference
		-- (2026-09-27; was tiny flat pool balls, 123651371748115; an even grid of small balls,
		-- 128929587897948, was tried and dropped). The image has its own colours.
		PatternImage = "rbxassetid://132770883034156",
		PatternTilePx = 380, -- one 512 px tile of eight balls shown this big
		PatternColor = { 255, 255, 255 }, -- no tint: the balls are drawn in their pale blues
		PatternTransparency = 0.7, -- faint, like the reference (tune)
		-- Text: Fredoka One, white, outlined in ink. Sizes are pixels; nothing goes below Min
		-- except ball numbers, which are part of the ball graphic.
		-- About 80% of the first build's sizes (designer, 2026-09-26: "shrink the new gui").
		Text = { Title = 32, Heading = 22, Button = 20, Body = 16, Min = 14 },
		TextOutlineRatio = 0.1, -- outline thickness as a share of the text size
		TextOutlineMinPx = 2, -- never thinner than this, from TextOutlineThinBelowPx up
		-- Text smaller than this gets a TextOutlineThinPx outline instead: Roblox strokes the
		-- inside edges of letters too, and at 14 px a 2 px outline closed the holes of o, a, e,
		-- 0 and 8 (designer, 2026-09-27; Fredoka One kept, compared in Studio against Nunito,
		-- Builder Sans, Montserrat and Luckiest Guy).
		TextOutlineThinBelowPx = 20,
		TextOutlineThinPx = 1,
		-- Solid ink in outlined letters' holes and a thick ink lip under them (HoleFill;
		-- designer, 2026-10-05 and 2026-10-06, on every outlined text). The fill: two ink
		-- copies of the text under it, nudged left and right by the outline's own thickness,
		-- so they stay inside the outline in any font. It shows only on outlines from
		-- FillMinOutlinePx up: small text's 1 px outline (text under 20 px) leaves its holes
		-- part open, and a wider nudge made card names, Sort and the money pill blobby.
		-- Drop: an ink copy with the outline, moved down OutlineShare of the outline's
		-- thickness (at least MinPx; fractions kept for high-DPI screens). Sized from the
		-- outline, not TextSize, which on a scaled text is only its largest size (a nameplate's
		-- 100 for 34 px letters put the copies past the outline). Picked as 6% of the text
		-- size (2 px) over 10% and 14%, then made a little thinner. (tune)
		HoleFill = {
			Everywhere = true, -- every outlined text in PlayerGui (false: only pages that ask)
			FillMinOutlinePx = 2,
			Drop = { Everywhere = true, OutlineShare = 0.45, MinPx = 1.5 },
		},
		-- Raised candy buttons: a light top, the colour, then a darker lip along the bottom.
		-- The controller's back button (Circle, or B on Xbox: Roblox's own picture) on a close
		-- X's bottom-left corner while a gamepad is the last input, like the menu column's D-pad
		-- glyphs, so a controller player sees how to leave (designer, 2026-10-06;
		-- HudParts.padBack): an ink disc (Roblox's white pictures vanish on the pale header) its
		-- size as a share of the X, the picture's share of the disc, its centre in shares of the X.
		PadBack = { Share = 0.8, GlyphShare = 0.92, At = { 0.02, 0.88 } },
		Buttons = {
			Green = { Top = { 140, 240, 160 }, Mid = { 61, 214, 107 }, Lip = { 30, 150, 70 } },
			Red = { Top = { 255, 150, 150 }, Mid = { 255, 77, 77 }, Lip = { 196, 38, 56 } },
			Blue = { Top = { 150, 206, 255 }, Mid = { 59, 155, 255 }, Lip = { 31, 104, 208 } },
			Yellow = { Top = { 255, 236, 150 }, Mid = { 255, 201, 40 }, Lip = { 214, 145, 0 } },
			Grey = { Top = { 222, 227, 236 }, Mid = { 186, 194, 208 }, Lip = { 132, 142, 160 } },
			White = { Top = { 255, 255, 255 }, Mid = { 244, 248, 255 }, Lip = { 190, 206, 230 } },
			Purple = { Top = { 214, 160, 255 }, Mid = { 168, 85, 247 }, Lip = { 112, 48, 190 } }, -- the gift squares
		},
		ButtonLipShare = 0.18, -- the lip is this share of the button's height
		ButtonStrokePx = 3, -- ink outline
		ButtonCornerPx = 12,
		ButtonIconShare = 0.62, -- an icon on a button is this share of its height
		ButtonIconOnlyShare = 0.95, -- an icon with no words (Leave's door) fills most of the button (designer, 2026-09-27)
		PressedScale = 0.94, -- the squish when pressed
		SelectedScale = 1.04, -- a gamepad-selected or hovered button grows a little
		SelectedStrokePx = 5, -- and its outline thickens, in Gold
		DisabledTransparency = 0.45, -- a button only the host may press, seen by a guest
		Ball = {
			StrokePx = 2.5, -- the ink ring that keeps every ball (stripes above all) off the white
			DiscShare = 0.5, -- the white number disc, as a share of the ball
			NumberShare = 0.4, -- the digits, as a share of the ball
		},
		-- Glossy cartoon icons, no words (tools/gen_ui_art.py, assets/ui/icons). Any one can be
		-- swapped for a better image by changing its id here.
		Icons = {
			Cue = "rbxassetid://116758585284705", -- your turn, aiming, Shoot
			Hourglass = "rbxassetid://96213788446334", -- someone else's turn
			Stopwatch = "rbxassetid://74222974804673", -- the shot clock
			Whistle = "rbxassetid://123711745342070", -- a foul
			Crown = "rbxassetid://88932863469480", -- the host
			People = "rbxassetid://126967121282359", -- how many are in
			Globe = "rbxassetid://102000229917965", -- Play Global (the matchmaking bar)
			Person = "rbxassetid://134579193841579", -- a person (blue)
			-- Play solo: grey, so it stands out on the blue button (designer, 2026-10-02)
			PersonGrey = "rbxassetid://102357114365453",
			Robot = "rbxassetid://118948986409177", -- Play against PC
			Play = "rbxassetid://87915961490645", -- Start
			Door = "rbxassetid://108459063618521", -- Leave
			Flag = "rbxassetid://121800890987382", -- surrender, and a draw
			Trophy = "rbxassetid://133568661073411", -- a win
			Sad = "rbxassetid://83322300789151", -- a loss
			Coin = "rbxassetid://94354793241176", -- the coin flip
			Hand = "rbxassetid://98407510851293", -- ball in hand
			Target = "rbxassetid://101004180917014", -- choose a pocket
			Rolling = "rbxassetid://117937533191868", -- balls moving
			Lightning = "rbxassetid://79533357402482", -- abilities
			Check = "rbxassetid://102199824142465", -- ready, even split
			X = "rbxassetid://114855661740318", -- a pocketed ball, a wrong target
			Arrow = "rbxassetid://135119886891841", -- points right; turned for the others
			-- The roadmap's < and > buttons: one white chevron each, drawn as a single stroke so
			-- the tip is one clean joint (2026-09-27; four rotated bars left a seam there).
			ChevronRight = "rbxassetid://83677689417587",
			ChevronLeft = "rbxassetid://139144449776506",
			ChevronUp = "rbxassetid://86978612733332", -- the controller guide's arrows by a stick
			ChevronDown = "rbxassetid://133654278514766",
			Sliders = "rbxassetid://72906258640929", -- fine controls
			Classic = "rbxassetid://77520789288930", -- difficulty: every line
			Difficult = "rbxassetid://96329200527250", -- difficulty: the aim line only
			Challenger = "rbxassetid://111544414092808", -- difficulty: no lines
			-- Money: a stack of green cash, never coins. Three bundles (cash_stack, after the
			-- designer's reference 04, 2026-09-27; was 73979676771161) everywhere money shows.
			Money = "rbxassetid://140297726302884",
			CashStack = "rbxassetid://140297726302884", -- the money HUD's total
			CashSingle = "rbxassetid://120556642167836", -- one bundle: the flying "+$10" chip
			ChatTag = "rbxassetid://108097317615793", -- a speech bubble (the chat-tag reward tile)
			-- The economy (2026-09-28; tools/gen_ui_art.py, assets/ui/icons/README.md). An empty id
			-- draws nothing until the image is uploaded.
			Shop = "rbxassetid://130453738066274", -- the red basket (GUI lane, ref 02; was 107658760787268)
			Inventory = "rbxassetid://105879289234800", -- a backpack
			Rewards = "rbxassetid://92894769753979", -- a gift box with a bow
			Trade = "rbxassetid://98977101809699", -- two arrows swapping
			Pack1 = "rbxassetid://104093005133758", -- the money packs, smallest to biggest
			Pack2 = "rbxassetid://107106986765797",
			Pack3 = "rbxassetid://78352765658351",
			Pack4 = "rbxassetid://78298939867579",
			Pack5 = "rbxassetid://79088631223048",
			Pack6 = "rbxassetid://75989511488683",
			Pack7 = "rbxassetid://70683561627175",
			Vip = "rbxassetid://114618538604206", -- a crown with rainbow gems
			StarterPack = "rbxassetid://112625803604762", -- a gift box with a cue
			MoneyParty = "rbxassetid://70489851952209", -- a party popper with cash confetti
			Limited = "rbxassetid://105313592367901", -- a numbered star ticket
			-- The GUI lane's icons (2026-10-03; tools/openai_image.py in the kit's sticker style,
			-- uploaded to the group).
			ShopBasket = "rbxassetid://130453738066274", -- the Shop: a red basket, silver handle (ref 02)
			Deals = "rbxassetid://127731721548070", -- a price tag with a star burst (the Deals jump button)
			Passes = "rbxassetid://93981799998814", -- a golden ticket (the Passes jump button)
			RobloxPlus = "rbxassetid://132944105986264", -- a gold badge with a plus
			Gift = "rbxassetid://120885254928899", -- the Free Reward gift
			Group = "rbxassetid://98530804278165", -- three busts (join the group)
			Invite = "rbxassetid://121644690849571", -- an envelope with a plus
			Star = "rbxassetid://125192913454809", -- the favorite star
			Challenge = "rbxassetid://127346327357150", -- the Daily Challenge
			Gear = "rbxassetid://125677637012120", -- Settings
			Heart = "rbxassetid://93822415051422", -- the thank-you burst
			FreeReward = "rbxassetid://120885254928899", -- the column's Free Reward tile (Gift) -- the shake hint's finger
			Calendar = "rbxassetid://81931904688937", -- the daily streak
			Code = "rbxassetid://139681599835662", -- promo codes
			Index = "rbxassetid://94908077553080", -- a book with a cue on it
			Sell = "rbxassetid://106552564585529", -- a price tag
			Lock = "rbxassetid://106188433501601", -- a padlock (Exclusive and Unique cues, locked things)
			Odds = "rbxassetid://116548417104330", -- a pie of rarities (the Odds button)
			-- A cue's thumbnail, drawn from layers that all share one canvas (CueThumb): the
			-- white layers are tinted with the cue's look colours (ImageColor3).
			CueOutline = "rbxassetid://79236419588604", -- the ink outline and shadow, untinted, under the rest
			CueShaft = "rbxassetid://103302145306091",
			CueTip = "rbxassetid://139935284491020",
			CueRing = "rbxassetid://83061685733531", -- the joint collar and the ring
			CueForearm = "rbxassetid://126056531698047",
			CueAccent = "rbxassetid://91223791753924", -- a band in the middle of the forearm
			CueRainbow = "rbxassetid://99026288213964", -- the forearm in the house rainbow, untinted (VIP, Reyes)
			CueWrap = "rbxassetid://115386170032197",
			CueCap = "rbxassetid://93663666480532",
			CueGloss = "rbxassetid://80942448683389", -- the shine, untinted, on top
			CueSilhouette = "rbxassetid://116727821385649", -- the whole cue as one dark shape (the Index's unowned cues)
			ScrollZoom = "rbxassetid://76220420219490", -- the zoom guide on a computer: a mouse wheel rolling
			PinchZoom = "rbxassetid://115866473257495", -- the zoom guide on touch: a pinching hand
			-- Ultimates (uploaded to the group 2026-09-28).
			Ults = "rbxassetid://116359776498638", -- the left column's 5th button: the 8-ball with a lightning splash
			UltBadge = "rbxassetid://132970855167502", -- the ult bar's badge: the 8-ball with a blue splash (ball right of centre)
			UltBadgeGold = "rbxassetid://74974990816876", -- the same badge with a gold flame, for the ready bar
			Lucky = "rbxassetid://97997677415172", -- a four-leaf clover: LUCKY SPINS
			UltSpin = "rbxassetid://76372169720993", -- a gold spin arrow round a bolt: SPIN and the spins count
		},
		Art = {
			BallGloss = "rbxassetid://109282983367810", -- shading and shine over a HUD ball
			BallBand = "rbxassetid://118056017631758", -- a stripe's band, clipped round, tinted
			Rays = "rbxassetid://112352358460844", -- spinning behind the win trophy
			-- Ultimates (tools/gen_ui_art.py `ults`, uploaded to the group 2026-09-28): white art
			-- tinted in Roblox.
			UltBackdrop = "rbxassetid://121308269711722", -- the cutscene's swirl, 1024 square; the 3:1 strip is rows 341-683
			AuraFlame = "rbxassetid://90187359321182", -- the aura's flipbook, Grid4x4, 16 frames, OneShot
			FieldLines = "rbxassetid://132811450841753", -- Magnet's beam, 512 x 128, tiles left to right (Wrap)
			RingGlow = "rbxassetid://121133273572178", -- a soft ring: the pocket's pulse and the N/S rings round the cue ball
			Spark = "rbxassetid://131919576694289", -- a 4-point sparkle for bursts
			SoftGlow = "rbxassetid://121163827465552", -- a round soft glow (the ball's glow, the bar's ready glow)
		},
		-- Rarity colours (UI_STYLE section 4): card frames, strips, reel glows, filter chips.
		-- Mythic's solid colour is its shimmer's lilac (the UI adds the pastel shimmer over
		-- deep space); Secret is near-black with red (overnight assumption, 2026-09-28, UI_STYLE
		-- 4's suggestion); Exclusive is the house blue (its rank cues show their tier).
		Rarity = {
			Common = { 156, 163, 175 },
			Uncommon = { 61, 214, 107 },
			Rare = { 59, 155, 255 },
			Epic = { 162, 89, 255 },
			Legendary = { 242, 178, 0 },
			Mythic = { 183, 156, 255 },
			Secret = { 30, 24, 32 },
			Unique = { 255, 92, 184 },
			Exclusive = { 59, 155, 255 },
			Default = { 156, 163, 175 },
		},
		-- Mythic's shimmer colours over its deep-space background, and Secret's red glow.
		MythicShimmer = {
			{ 127, 231, 255 },
			{ 183, 156, 255 },
			{ 255, 156, 230 },
			{ 255, 255, 255 },
		},
		MythicSpace = { 26, 20, 70 },
		SecretGlow = { 255, 40, 60 },
		-- src/client/UIAnim.luau. Things pop in with a little overshoot; only important things
		-- shine or bounce (designer, 2026-09-25).
		Motion = {
			PopSeconds = 0.32, -- pop in
			PopFromScale = 0.6, -- from this size
			-- A one-by-one entrance (UIAnim.expandIn; designer, 2026-10-06: the lucky block
			-- reel's cards "should appear like all individually in rapid succession"): each
			-- piece grows from nothing in PopSeconds, the next GapSeconds after it. (tune)
			Stagger = { PopSeconds = 0.18, GapSeconds = 0.04 },
			OutSeconds = 0.14, -- pop out, quicker
			SlideSeconds = 0.25,
			SlidePx = 24, -- how far a slide travels
			ShineSeconds = 0.7, -- one shine sweep across a panel or button
			PulseSeconds = 0.9, -- one breath of a pulsing button
			PulseScale = 1.03, -- how big it breathes (a full-width Start stays inside its card)
			BounceScale = 1.2, -- a pocketed ball's pop
			RaysDegreesPerSecond = 30, -- the win card's rays
			-- Hovering anything pressable (or a gamepad resting on it) makes it sway: it rocks
			-- side to side with a little extra wiggle, a small dance, easing in from still and
			-- back to still when the pointer leaves (UIAnim.sway; designer, 2026-09-28). Touch
			-- has no hover, so a tap never starts it. (tune)
			Sway = {
				Degrees = 3, -- how far it tips each way at most
				EdgePx = 5, -- ...but a wide thing tips less: its ends move at most this far
				Seconds = 1.4, -- one full rock, there and back
				WiggleShare = 0.3, -- a second rock at twice the speed, this share as big
				EaseSeconds = 0.25, -- from still to the full sway, and back
			},
			-- The rank HUD's badge: a quicker little shake, the badge alone (the HUD grows).
			BadgeSway = {
				Degrees = 7,
				EdgePx = 8,
				Seconds = 0.6,
				WiggleShare = 0.3,
				EaseSeconds = 0.15,
			},
			-- Big words shake now and then (UIAnim.shake): a quick rattle every `Every` seconds.
			-- "Wiggle" is the louder one (one win from a rank-up, an icon calling for a click).
			Shake = {
				-- Speed: radians a second. Kept low enough that a frame never jumps far (fast
				-- ones looked like a choppy sprite; designer, 2026-10-03).
				Text = { Degrees = 3, Every = 2.6, Seconds = 0.45, Speed = 20 },
				Wiggle = { Degrees = 6, Every = 1.7, Seconds = 0.6, Speed = 15 },
				-- The Grand Opening card's tilted NEW tag (the approved animatic, 2026-10-06).
				NewTag = { Degrees = 7, Every = 3, Seconds = 0.4, Speed = 40 },
				Jolt = { Degrees = 5, Every = 0, Seconds = 0.45, Speed = 22 }, -- once (a slam)
				-- A rattle that keeps going (Every = Seconds): the grid's rarest card before it turns.
				Hard = { Degrees = 6, Every = 0.4, Seconds = 0.4, Speed = 26 },
			},
			-- The glow that bursts behind a pressed or hovered thing, or a menu opening.
			Glow = { Seconds = 0.55, FromPad = 1.2, ToPad = 3.2, Transparency = 0 }, -- pads: shares of its smaller side
			-- Twinkling sparkles over something special (a deal, a rare card): one appears
			-- every `Every` seconds and lives `Seconds`, at most `Max` at once (half with Lower
			-- effects).
			Sparkle = { Every = 0.22, Seconds = 0.7, Max = 6, SizePx = { 10, 22 } },
			-- Moving stripes over a fill (the XP bar): white bands sliding right. (tune)
			Stripes = {
				WidthPx = 7,
				GapPx = 18,
				Degrees = 35,
				PxPerSecond = 22,
				Transparency = 0.72,
			},
			RainbowSeconds = 3, -- one loop of a rainbow word's colours (deals, multipliers)
			-- A big word or card slamming in: from this big down to its size, then a jolt.
			Slam = { FromScale = 1.9, Seconds = 0.26 },
			-- An icon calling for a click rocks gently side to side (a turn, never a move: a GUI
			-- move snaps to whole pixels and looked like a 2 fps sprite; designer, 2026-10-03).
			Bob = { Degrees = 4, Seconds = 1.8 },
			-- Hover on an icon (the column, the corners): soft sun rays fade in behind it and turn
			-- slowly, two layers turning opposite ways, like the Legendary ability's rays.
			SunRays = {
				Reach = 3, -- the rays' size, of the icon's
				Transparency = 0.2, -- at full strength
				GlowTransparency = 0.05, -- the bright soft glow at their centre
				GlowShare = 0.75, -- its size, of the rays'
				Color = { 255, 240, 190 }, -- warm sunlight
				DegreesPerSecond = 22,
				EaseSeconds = 0.22, -- fading in and out
				FromScale = 0.7, -- they grow from this size as they fade in
			},
		},
		-- Big and simple (designer, 2026-10-03): new and restyled screens use these sizes,
		-- bigger than Text above, especially on a phone. (tune)
		Big = { Hero = 56, Title = 40, Heading = 28, Button = 24, Body = 19, Min = 16 },
		-- The number palette (UI_STYLE 13): one meaning per colour so the screen reads as a
		-- theme, not a random rainbow. Rainbow (Config.Ranks.ChatRainbow) is for deals and
		-- multipliers only.
		Numbers = {
			Money = { 255, 214, 10 }, -- prices and money amounts: bright yellow
			Gain = { 61, 224, 107 }, -- what you get, FREE, +bonuses: green
			Count = { 82, 196, 255 }, -- counts, odds and timers: sky blue
			Old = { 255, 64, 64 }, -- a crossed-out price: red
		},
		-- VIP's colour now that the rainbow is for deals (designer, 2026-10-03): a rich gold
		-- shimmer with a crown mark, a placeholder until the designer picks VIP's new look.
		Vip = {
			Colors = {
				{ 255, 196, 0 },
				{ 255, 236, 140 },
				{ 255, 170, 0 },
				{ 255, 226, 90 },
			},
		},
		-- Secret's red-white glitch (UI_STYLE 4, designer 2026-10-03): over its near-black.
		SecretGlitch = { { 255, 40, 60 }, { 255, 255, 255 } },
		-- Big title words set letter by letter on a gentle arch, each letter its own group of
		-- layers so it can pop in alone (ArchTitle; the lively Shop's "GRAND OPENING", after
		-- 13b's painted title). Shares are of the text size; colours sampled off 13b. (tune)
		ArchTitle = {
			Gold = {
				-- The face: pale yellow at the top of the letters, gold, orange at the foot,
				-- with a soft light band near the top for the gloss. Positions are of the
				-- letter's box (its glyphs fill about 0.15 to 0.85 of it).
				Face = {
					{ At = 0, Color = { 255, 252, 196 } },
					{ At = 0.3, Color = { 255, 247, 150 } },
					{ At = 0.36, Color = { 255, 236, 70 } },
					{ At = 0.6, Color = { 255, 214, 30 } },
					{ At = 0.85, Color = { 253, 176, 4 } },
					{ At = 1, Color = { 240, 150, 0 } },
				},
				Extrude = { 214, 112, 4 }, -- the letters' depth under the face
				ExtrudeShare = 0.09, -- how far down the depth reaches
				Outline = { 6, 14, 40 }, -- the thick navy outline that merges the word
				OutlineShare = 0.11,
				Rim = { 30, 200, 255 }, -- the cyan rim outside the outline
				RimShare = 0.045, -- its width outside the outline
				RimTransparency = 0.1,
				TrackingShare = -0.03, -- extra room between letters (the outlines merge)
				SagShare = 0.05, -- the arch: how much higher the middle is, of the word's width
			},
			-- The subtitle under it: white letters, a navy outline, straight (the designer, gate 2).
			Subtitle = {
				FaceColor = { 255, 255, 255 },
				Outline = { 6, 14, 40 },
				OutlineShare = 0.16,
				TrackingShare = 0.0,
				SagShare = 0, -- 0 = a straight line
				ByWord = true, -- whole words placed (small letters alone lose their kerning)
			},
		},
	},
	-- Lower effects (Settings, designer 2026-10-03): weaker devices get fewer particles and
	-- auras, never none. Every particle rate and UI loop reads Quality (src/client/Quality).
	Quality = {
		LowRate = 0.35, -- particle rates and sparkle counts are multiplied by this
	},
}

---------------------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------------------
-- Shared multiplayer tuning. Rule choices are recorded in MULTIPLAYER_SPEC.md.
Config.Multiplayer = {
	-- The rail-after-contact rule (after the first hit a ball must drop or touch a rail, or it
	-- is a foul). The designer keeps it out of casual public games and in ranked only
	-- (2026-09-23). Every table is casual until ranked matches exist (a table's `ranked` flag).
	RailAfterContact = { Casual = false, Ranked = true },
	-- On the rooftop's entrance landing, at the top of the stair, facing the tables
	-- (assets/map/Spec.md). Y is the SpawnLocation's centre: it is the art's entrance mat, a
	-- 0.2 stud slab lying on the floor (MapBuilder).
	Spawn = { X = 0, Y = 0.1, Z = 76.75, YawDegrees = 0 },
	-- The coin flip; the host's Start leads straight into it. It reads YOU ARE HEADS/TAILS
	-- (Style.CoinHoldSeconds), spins (Style.CoinSpinSeconds), then holds who breaks for the
	-- rest, over a second (designer, 2026-09-27: quick, a few words at a time). (tune)
	CoinSeconds = 3,
	IntroSeconds = 2, -- new shooter introduction, early shots permitted
	PlacementSeconds = 10, -- cue-ball placement window (ball in hand), then ShotSeconds to aim (designer, 2026-09-27: was 15)
	-- The break: moving the cue ball along the line and shooting share this one clock, and
	-- running out is a timeout foul like the shot clock's (designer, 2026-09-27). (tune)
	BreakSeconds = 20,
	PocketChoiceSeconds = 10, -- called-pocket selection window
	ShotSeconds = 20, -- aiming deadline
	FoulSeconds = 1.4, -- foul announcement before incoming turn
	ResultSeconds = 2.8, -- outcome hold before table reuse (solo; a two-sided game waits RematchSeconds)
	-- After a two-sided game everyone may press Rematch (designer, 2026-09-28): all of them
	-- within this long and the same players play again, the other team breaking, and the
	-- series score goes on; otherwise the table frees. Long enough to read the result screen. (tune)
	RematchSeconds = 20,
	PocketSettleSeconds = 0.6, -- extra settling after a pocket (designer, 2026-10-04: was 1)
	VoteSeconds = 10, -- unanimous surrender window
	VoteCooldownSeconds = 30, -- prevent surrender prompt spam
	RejoinCooldownSeconds = 2, -- leave/reenter guard after reset
	TimeoutLimit = 2, -- consecutive team shooting timeouts lose
	BreakLineX = -25, -- head string on the 100-inch table
	PlacementClearanceInches = 0.01, -- keep placed balls out of exact contact
	PlacementGridInches = 1, -- deterministic fallback search spacing
	PlacementLockLeadSeconds = 0.15, -- client stops moving the ball this long before the placement deadline so its last spot reaches the server first
	PlacementEchoEpsilonInches = 0.001, -- a late shot may repeat the locked cue spot within this and still be accepted
	PlacementResolveIterations = 4, -- push-out passes per drag sample (balls, pockets, jaws, cushions)
	PlacementResolveBisections = 10, -- walk-back steps toward the last legal spot when push-out fails
	PlacementResolveSlopInches = 0.001, -- pushed spots land this far clear so rounding never reads as contact
	BreakAxisMinComponent = 0.35, -- break arrows follow screen-right unless the line runs nearly vertical on screen
	-- One pad per table (Placement.queuePad). The first on is the host, who picks the
	-- difficulty and presses Start once the pad is full; teams alternate in arrival order.
	Queue = {
		-- One rectangular pad per table (designer, 2026-09-26: a rectangle, not the circle
		-- tried first): stand anywhere on it to join. It holds both teams, twice the table's
		-- teamSize. It sits in front of the table, centred on the long side toward the
		-- entrance, lying along it.
		-- By team size (1v1, 2v2, 3v3): { length along the table, depth out from it }. (tune)
		PadSizeStuds = { { 10, 5 }, { 14, 5 }, { 18, 5 } },
		-- Which long side: the sign of physics y. -1 is world +Z at yaw 0, toward the entrance.
		PadSide = -1,
		PadGapStuds = 1, -- from the walkway's long edge (Fence.HalfWidthStuds) to the pad
		FenceMarginStuds = 0.5, -- the match fence stands this far beyond the pad
		-- The server checks who is on each pad this often, rather than using .Touched, which
		-- misses a player who walks on and stands still. It also paces the match loop.
		PollsPerSecond = 10,
		-- Join the moment you are on it (designer, 2026-09-26: "it needs to be instant").
		DwellSeconds = 0,
		ExitGraceSeconds = 0.5, -- off it this long before you leave: forgive edge jitter
		-- The host pressed Start before the pad was full: the game starts by itself this long
		-- after the pad fills, so someone who walked on by accident can step off (designer,
		-- 2026-09-27). A pad that is already full at Start begins at once. (tune)
		ReadyGraceSeconds = 3,
		-- Request opponent / players (the host's card while the pad has room): everyone free in
		-- the server gets a popup to join (designer, 2026-09-27). A request stands this long:
		-- the popup shows, the host's card stays folded to "Requested!", and the host cannot
		-- ask again; then the card unfolds if nobody came. (tune)
		RequestSeconds = 15,
		-- After a request, the host may ask again no sooner than this, even having cancelled
		-- it (the Cancel button, designer 2026-09-27), so Request and Cancel cannot flood
		-- everyone with popups. (tune)
		RerequestSeconds = 3,
		-- The matchmaking bar (designer, 2026-10-07): a host who steps onto a pad with no Roblox
		-- friend in the server sends "<name> needs an opponent!" to everyone by themselves,
		-- once per step-on; stepping off and on again sends it no sooner than this after the
		-- last one, so nobody is flooded with popups. (tune)
		AutoRequestCooldownSeconds = 15,
	},
	Barrier = { -- invisible wall around each table: nobody can touch or jump onto it
		-- Beyond the rails. 5.5 in rails + 0.6 and 7 in rails + 0.36 put the wall in the same
		-- place (half extents 9.48 x 5.48 studs), so the stance and fence tuned to it stay put.
		MarginStuds = 0.36,
		HeightStuds = 14, -- well above a character's jump
		ReleaseClearanceStuds = 1.2, -- the shooter's root stands at least this far outside it (ShooterStance), so a shooter let go where they stand is clear of it
	},
	Fence = { -- invisible walls around each match area; stop participants only (PoolFence group)
		-- The walkway round the table, where the shooter stands (ShooterStance.area): this far
		-- from the table centre along its length, both ends, and across its width. The match
		-- fence is the walkway grown to take in the queue pad (Placement.matchFence).
		HalfLengthStuds = 13,
		HalfWidthStuds = 8.5,
		ThicknessStuds = 1, -- wall thickness
		-- The walls stand this far beyond the match area on every side (Placement.matchWalls),
		-- so a player waiting for their turn can walk about a little without reaching another
		-- table (designer, 2026-09-26: a bit more room, but stay by your table). The aisles are
		-- 10 studs across and 8 deep, so two neighbours' walls still stand 4 and 2 apart. (tune)
		RoomStuds = 3,
		EscapeStuds = 2, -- a participant this far outside (clipped through) is put back inside
	},
	-- The shooter's root on the server (TableService). While they aim, the anchored root
	-- follows ShooterStance, so a late joiner or a far table sees the shooter at the table; at
	-- the shot it goes exactly to the stance spot. Each client poses the body itself.
	Stance = {
		ServerMovesPerSecond = 5, -- while aiming, the root follows the aim at most this often (constrain runs at Queue.PollsPerSecond, so more has no effect)
		ServerMoveStuds = 1, -- ...and only once the stance has moved this far from where the root is
		ServerMoveDegrees = 20, -- ...or turned this far
		-- After the shot the root is held at the shot spot this long (seconds), so the stroke
		-- and its follow-through play out on the shooter's screen and on every watcher's (a
		-- network delay behind), and is then let go: the player may walk while the balls
		-- roll, the shot camera still following them (designer, 2026-09-25). (tune)
		HoldAfterShotSeconds = 1.2,
	},
	RateLimits = { -- per player and channel token buckets
		action = { Burst = 12, PerSecond = 8 }, -- calls, votes, surrender, queue leave
		place = { Burst = 10, PerSecond = 6 }, -- reliable cue-ball commits (drag release, nudge pause)
		shot = { Burst = 4, PerSecond = 2 }, -- ShotFired; own bucket so placement can never starve it
		aim = { Burst = 30, PerSecond = 20 }, -- unreliable aim + wind-up + ball-in-hand stream (client sends <= 15/s, plus one let-go)
		snapshot = { Burst = 12, PerSecond = 8 }, -- full-state recovery requests
	},
	CameraFitIterations = 32, -- HUD-aware fit of the fully zoomed-out view; blended in above the home view
	CameraFitGrowth = 1.12, -- retreat factor until every corner is clear
	CameraMaxHudFraction = 0.65, -- portrait/landscape HUD clearance limit
	CameraTransitionSeconds = 0.55, -- on taking the camera and on switching to/from the top-down pocket call
	CameraReleaseSeconds = 0.7, -- easing from the table camera into the player's own camera when the turn passes
	CameraBottomFraction = 0.14, -- leave space for setup controls
	CameraSideFraction = 0.1, -- pocket/rail clearance
	ActionRetrySeconds = 2, -- recover controls if an acknowledgement is lost
	MaxReplayStepsPerFrame = 32, -- bounded catch-up work per visible table
	SnapshotIntervalSeconds = 2, -- recover late/missed client subscriptions
	YourTurnSound = "rbxassetid://120722072794939", -- user supplied; preload verified
	FoulSound = "rbxassetid://128802141795458", -- user supplied; preload verified
	CoinSound = "rbxassetid://7022812395", -- Creator Store coin flip; preload verified
	UISoundVolume = 0.35, -- quiet underneath physical impact mix
	FoulSoundVolume = 0.22, -- the foul clip measures 1.6x YourTurn's loudness at the same Volume (2026-10-04)
	QueueVisual = {
		-- The queue pad (TableService.buildPad): a see-through rounded rectangle tinted like its
		-- glowing rim (designer, 2026-09-27: glass, not a white sheet), the table's mode written
		-- big on it and JOIN or the count under that. The part is invisible and all of it is
		-- drawn on its top face, so the corners can round. PadEffects tints the plate with the
		-- rim: blue with room, green with somebody on, gold when full or playing.
		PadHeight = 0.12, -- thin floor plate, studs
		FloorOffset = 0.08, -- avoid z-fighting with the floor, studs
		PadColor = { 59, 155, 255 }, -- the plate before PadEffects tints it: the rim's blue
		PadTransparency = 0.55, -- the floor shows through (tune)
		PadCornerPx = 36, -- its rounded corners, pixels (at PixelsPerStud)
		RimPx = 14, -- the glowing rim round it, pixels
		RimFree = { 59, 155, 255 }, -- house blue while there is room
		RimFull = { 255, 201, 40 }, -- gold once the pad is full or its game is on
		PixelsPerStud = 40, -- sharp words on the pad without large canvases
		ModeTextSize = 110, -- "1v1" on the pad, pixels (about 2.75 studs tall)
		CountTextSize = 50, -- STEP IN or 1/2 under it
		-- Turns the pad about its table's up axis, a quarter turn at a time, so its words lie
		-- along the table and read upright from the entrance (tables at yaw 0). (tune)
		LabelRotation = 270,
		LightBrightness = 0.35, -- bounded ambient glow from the pad
		LightRange = 6, -- studs
		VerticalTolerance = 6, -- a pad cannot seat someone on a different floor, studs
		AreaMargin = 1, -- the queue area round the pad: leaving it starts the exit grace
		FallTolerance = 5, -- recover a falling participant below the table area
		RespawnHeight = 3, -- safe standing root height above the floor, studs
		RespawnBoundaryInset = 1, -- keep respawns inside confinement, studs
		-- A held body let go (a turn passing, the match ending) first steps clear of the table
		-- barrier and onto the floor if it is not already (TableService.clearSpot): the floor is
		-- looked for from ReleaseProbeUpStuds above the root down ReleaseProbeDownStuds, and a
		-- root lower than SunkShare of its standing height above it counts as sunk.
		ReleaseProbeUpStuds = 4,
		ReleaseProbeDownStuds = 14,
		SunkShare = 0.5,
		-- The pad's effects (src/client/PadEffects.luau). (tune)
		FadeInSeconds = 0.25, -- how fast the whole effect lights up and fades out
		MoteTexture = "rbxasset://textures/particles/sparkles_main.dds", -- built-in sparkle
		MoteRate = 30, -- light motes per second while occupied, over the whole pad
		MoteBurst = 40, -- motes thrown up on arrival
		MoteSize = 0.5, -- studs, shrinking to nothing
		MoteLifetime = { 0.8, 1.4 }, -- seconds
		MoteSpeed = { 3, 6 }, -- studs per second, upward
		MoteSpreadDegrees = 8, -- nearly straight up
		GlowRange = 10, -- studs
		GlowBrightness = 1.4, -- steady glow while occupied
		GlowBurstBrightness = 5, -- arrival flare
		GlowBurstSeconds = 0.6, -- flare settling time
		-- Outlines pulse out from the rim while the pad has room: "step here".
		RingPeriodSeconds = 1.6, -- one outline every this often
		RingReachStuds = 2, -- how far past the rim an outline travels before it fades
		RingStrokePx = 12, -- outline thickness (PixelsPerStud)
		RingTransparency = 0.25, -- an outline at its brightest
		-- A big arrow bobs above the pad, pointing down, while it has room and you are not
		-- seated anywhere.
		ArrowHeightStuds = 6, -- above the pad
		ArrowSizeStuds = 3.2,
		ArrowBobStuds = 0.7, -- up and down
		ArrowBobSeconds = 1.2, -- one bob
		ArrowMaxDistance = 90, -- studs: hidden further away
		-- Only the pads near you show the arrow (designer, 2026-10-06: not every table at once);
		-- at spawn that is the two in front (25 studs; the next row is 52). Measured flat, from
		-- your character to the pad's middle.
		ArrowNearStuds = 35,
		ArrowFadeSeconds = 0.25, -- an arrow fades in or out over this as you come and go
		JoinSound = "rbxassetid://131677760492710", -- Creator Store "Beacon SFX" power-up; loads in this experience, listening pending
		JoinSoundVolume = 0.5, -- heard around the pad, not across the room
		JoinSoundMinDistance = 8, -- studs at full volume
		JoinSoundMaxDistance = 60, -- studs until silent
	},
	Style = {
		QuickMotion = 0.15, -- hover transitions in seconds
		Motion = 0.25, -- status and ball emphasis in seconds
		PulsePeriod = 1.8, -- local queue/pocket pulse period
		HeaderMargin = 10, -- outer safe-area margin
		HeaderGap = 8, -- spacing between panels and rows
		HeaderTop = 6, -- minimal spacing at the upper screen edge
		-- The top bar is as small as it can be: the balls and a sliver of white round them
		-- (designer, 2026-09-26: it blocked the table on every device; it was 64 on a computer
		-- and 52 on a phone). One row, left to right: our team, the clock, their team, Leave;
		-- laid out at these sizes and scaled down to fit the room beside Roblox's buttons
		-- (MatchHUD.layout), so it is one row on every screen. No status card: a turn popup
		-- says whose turn it is (designer, 2026-09-26).
		HeaderHeight = 37, -- the top bar's cards: BallSize and 5 each side (the ink outline takes 3)
		CenterClockWidth = 94, -- the shot clock between the teams, as tall as the bar
		CenterClockTextSize = 26, -- big (designer: centred and bigger)
		ShortCenterClockWidth = 76, -- the same on a phone
		ShortCenterClockTextSize = 21,
		-- With ball in hand this blue pill under the big clock counts the time left to move the
		-- cue ball, and the big clock holds at the full shot clock until it ends, so the 15 s
		-- to move never reads as 15 s to shoot (designer, 2026-09-27). (tune)
		MoveClockWidth = 108, -- the move pill, centred under the big clock
		MoveClockHeight = 26,
		MoveClockTextSize = 18,
		ShortMoveClockWidth = 94, -- the same on a phone
		ShortMoveClockHeight = 23,
		ShortMoveClockTextSize = 16,
		LeaveSize = 33, -- the red door (Leave) at the bar's right end, square
		ShortLeaveSize = 27, -- the same on a phone (its touch area is still TouchTargetPx)
		-- The turn popup (YOUR TURN, OPPONENT'S TURN, ALLY'S TURN) under the bar when a turn
		-- starts, like the foul popup but smaller. (tune)
		TurnPopupTitleSize = 24,
		TurnPopupSeconds = 2, -- up this long
		TurnPopupFadeSeconds = 0.35, -- and fades out over its last part
		-- The same popup says YOU ARE SOLIDS or YOU ARE STRIPES when the groups are decided
		-- (designer, 2026-09-27), up longer: 3.5 s (designer, 2026-09-27: a second more). (tune)
		GroupPopupSeconds = 3.5,
		TouchTargetPx = 44, -- a small button's touch area is still at least this (UI_STYLE section 5)
		-- Room for Roblox's own buttons at the top, only when Roblox does not report the free
		-- part of its top bar (GuiService / ScreenInsets.TopbarSafeInsets; MatchHUD).
		HeaderMenuLeft = 250, -- the menu, chat and voice buttons on the left
		HeaderMenuRight = 64, -- anything on the right
		ShortHeight = 430, -- compact layout for phone landscape
		-- Short screens (a phone on its side, height under ShortHeight) use a compact top bar
		-- so a 3v3 still fits on one line and the table keeps most of the screen.
		ShortHeaderHeight = 30, -- the compact bar's cards: ShortBallSize and 5 each side
		ShortPortraitSize = 22, -- six portraits in landscape, inside the bar
		ShortOpenLabelSize = 16, -- OPEN TABLE on the compact bar
		ShortHeaderGap = 6, -- the compact bar's spacing (HeaderGap on a computer)
		ShortBallSize = 20, -- balls on short screens (a phone on its side)
		-- The ball-in-hand hint: one thin line at the bottom, only as wide as its words
		-- (designer, 2026-09-26: as small as possible; it was 36 and 30 high and always 460 wide).
		ShortSetupHeight = 24, -- one-line placement instruction on short screens
		SetupHeight = 28, -- one-line placement instruction
		SetupTextSize = 16, -- its words (the kit's body size)
		ShortSetupTextSize = 14, -- the same on a phone (the kit's smallest)
		SetupMaxWidth = 460, -- the ball-in-hand hint pill at its widest
		MobileBreakpoint = 760, -- stack central status below teams
		PortraitSize = 29, -- square avatar beside the ball row, inside the bar (no name under it)
		PortraitCornerPx = 10, -- the portrait's rounded corners
		PortraitGap = 6, -- teammate portrait spacing
		ActiveDotPx = 9, -- the green dot on the shooter's portrait
		ActiveEdgePx = 3, -- the shooter's green outline and the clock running round it
		BallSize = 27, -- numbered HUD ball diameter
		BallGap = 4, -- stable ball-slot spacing
		NameSize = 14, -- player names and secondary lines (the kit's smallest text)
		StatusSize = 20, -- the one-line status and other primary labels
		ButtonHeight = 44, -- touch target (at least 44)
		ResultPanelHeight = 170, -- the result card; its icon sits on the top edge
		ResultIconSize = 90, -- trophy, sad ball or flag
		CoinPanelHeight = 150, -- the coin flip card: one title line and the coin
		CoinHoldSeconds = 0.5, -- YOU ARE HEADS/TAILS on the still coin before it flips
		CoinSpinSeconds = 1.2, -- the flip; who breaks shows for the rest of CoinSeconds
		CoinSize = 78, -- the coin
		DialogIconSize = 52, -- the door or flag over the leave question
		ModalWidth = 340, -- responsive dialog maximum width
		-- How much the screen behind a dialog and the coin and result cards darkens: none,
		-- they are just popups (designer, 2026-09-27; it was 0.45). The see-through backdrop
		-- still blocks taps behind a dialog.
		ModalDim = 0,
		TargetStroke = 4, -- the coloured ring round a pocket target or the ball in hand
		TargetInkPx = 2, -- the ink outline just outside it
		PlacementIconPx = 26, -- the glove on the ball-in-hand ring
		-- The foul popup (no panel, designer 2026-09-25): FOUL! and a few words on the rule.
		FoulCardSeconds = 3, -- up this long from the foul (it was 8, a card that stayed too long)
		FoulCardFadeSeconds = 0.4, -- and fades out over its last part
		FoulCardWidth = 380, -- pixels, narrower on small screens
		FoulTitleSize = 36, -- FOUL!
		FoulReasonSize = 16, -- the reason under it
		OpenBallSize = 18, -- balls already down while the table is open, beside OPEN TABLE
		ShortOpenBallSize = 15, -- the same on the two-row (narrow) layout
		OpenBallMinSize = 12, -- never shrink them below this to fit
		OpenLabelShare = 0.36, -- share of the ball-row width the OPEN TABLE label keeps
		-- The "needs an opponent" popup (src/client/OpponentPrompt.luau), bottom centre, kept
		-- small and low so it clears the player's legs (designer, 2026-09-27: was 330 x 96).
		PromptWidth = 250, -- pixels, before shrinking to fit a narrow screen
		PromptHeight = 66,
		PromptPadding = 6, -- inside the card
		PromptFaceSize = 48, -- the host's headshot
		PromptButtonHeight = 30, -- Join and Dismiss (each still takes a 44 px touch, HudParts.setMinHit)
		PromptBottom = 6, -- above the screen's bottom edge
		PromptMinScale = 0.7, -- never shrink it further than this
		PromptHeadshot = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", -- the host's face
		OwnBallOutlineTransparency = 0.6, -- subtle local group hint (the normal style)
		-- The STRONG style: a vivid solid outline on the balls to hit and the other group
		-- washed grey. Off in normal play by the designer's choice (2026-09-23); kept for the
		-- first-time playthrough / tutorial (GDD section 14), where making "these are yours"
		-- unmissable matters more than a clean table.
		StrongBallHighlights = false,
		StrongOwnOutline = { 70, 255, 130 }, -- vivid green outline on the balls to hit
		StrongOwnOutlineTransparency = 0, -- solid
		OpponentBallFill = { 70, 74, 82 }, -- grey wash over the other group's balls
		OpponentBallFillTransparency = 0.5, -- clearly dimmed, still recognisable
		TargetSize = 44, -- minimum pocket hit target
		-- Choosing a pocket with the stick (MatchTargets.linkPockets): a ring off to the side
		-- of a push counts this many times its sideways distance, so the straight one wins.
		PocketNavAcrossWeight = 2,
		-- After the call, the chosen pocket's marker sits inside its hole while you shoot, so it
		-- never covers the jaws (designer, 2026-09-27): its outer edge (ink included) spans this
		-- share of the hole's narrow way on screen, before the pulse (TargetPulse) adds 15%.
		CalledRingShare = 0.75,
		CalledRingMinPx = 8, -- never smaller than this inside its outline, however far the pocket
		CalledRingSamples = 8, -- directions sampled round the hole to find its narrow way
		PlacementHandleSize = 48, -- draggable cue-ball handle, never smaller than this
		PlacementGrabScale = 1.4, -- grab radius as a multiple of the ball's on-screen radius
		PlacementBlockedInches = 1.5, -- ring turns red when the ball lags the pointer by more than this
		TargetHeightInches = 1.5, -- selection targets above cloth
		TargetPulse = 0.15, -- bounded ring pulse
		BreakDotSpacingInches = 2, -- dotted break line spacing
		Green = { 92, 223, 157 }, -- the glow on your own balls on the table (Main)
		Red = { 242, 104, 112 }, -- the guideline's red X on a wrong target (Guideline)
		-- The balls pulse to call something out (designer, 2026-10-06; BallCallouts, BallPulse):
		-- your own group when the groups are decided (with YOU ARE SOLIDS / STRIPES; the other
		-- group does not glow), and a team's last ball once per game as a warning, seen by
		-- everyone. Green only, four slow bright pulses (designer, 2026-10-06). (tune)
		BallPulse = {
			Color = { 70, 255, 130 }, -- a vivid green (the strong style's own-ball outline)
			Pulses = 4, -- each callout pulses this many times (designer, 2026-10-06: one more)
			PulseSeconds = 2, -- one pulse: up from nothing to full and back down
			Low = 0, -- the glow's strength between pulses (1 at each peak)
			FillPeak = 0.8, -- how solid the colour wash over the ball is at a peak (0..1)
		},
		FadeSeconds = 0.25, -- panel/status motion
		PulseSeconds = 1.8, -- calm ambient pulse
	},
}

---------------------------------------------------------------------------------------------
-- The hub map (the rooftop pool club; docs/prompts/ROOFTOP_MAP_PROMPT.md, assets/map/Spec.md).
-- Built in Edit mode by src/shared/MapBuilder.luau and saved in the place. In the running game
-- only the drifting boats read it (Map.Near.Boat: src/client/MapAmbience.luau). Colours are
-- hex strings (this file loads in Lune).
---------------------------------------------------------------------------------------------
Config.Map = {
	Name = "Map", -- Workspace model holding the whole map
	Tables = "Tables", -- Workspace folder of the tables (TableBuilder.FolderName): their lamps
	CollisionName = "Collision", -- its invisible walls and steps, and the tiled floor
	-- The architecture from assets/map/fbx/Rooftop.fbx (3D Importer, assets/map/Readme.md);
	-- MapBuilder.prepareImport puts it back where Blender built it with three anchor cubes
	-- (AnchorO at the origin, AnchorX and AnchorZ this far along +X and +Z), then deletes them.
	Architecture = "Rooftop",
	Anchors = { O = "AnchorO", X = "AnchorX", Z = "AnchorZ", Spacing = 10 },
	-- Every mesh the model must hold and how it behaves. None collides: collision is the
	-- gray-box's invisible parts (CollisionName). Maps names a set in Maps (a SurfaceAppearance
	-- from it); without Maps the mesh is a flat Color. AlphaMode is the SurfaceAppearance's.
	-- Shadows: only the big solid pieces cast them (ARCHITECTURE section 7); the slats do not,
	-- so the lounge has no zebra stripes.
	Meshes = {
		Parapet = { Maps = "Arch", CastShadow = true },
		RailingFrame = { Color = "#1B1B22", CastShadow = false },
		RailingGlass = { Color = "#66B4D2", Transparency = 0.6, CastShadow = false },
		Steps = { Maps = "Arch", CastShadow = false },
		Pergola = { Maps = "Arch", CastShadow = true },
		PergolaSlats = { Maps = "Arch", CastShadow = false },
		Vines = { Maps = "Foliage", AlphaMode = "Transparency", CastShadow = false },
		TowerTop = { Maps = "Arch", CastShadow = false },
		TableGlow = { Maps = "Overlays", AlphaMode = "Transparency", CastShadow = false },
		FloorShade = { Maps = "Overlays", AlphaMode = "Transparency", CastShadow = false },
	} :: {
		[string]: {
			Maps: string?,
			Color: string?,
			Transparency: number?,
			AlphaMode: string?,
			CastShadow: boolean,
		},
	},
	-- Uploaded images ("rbxassetid://digits"), "" until uploaded (an empty id is skipped).
	-- The files are assets/map/textures/*.png at 1024, drawn by assets/map/gen_textures.py.
	Maps = {
		-- Uploaded 2026-09-26 from assets/map/textures (1024; third round, after the Stage 2 critic).
		Arch = { Color = "rbxassetid://95334117032577" }, -- arch_color.png: the trim sheet, soft shade baked in
		Foliage = { Color = "rbxassetid://139476467352315" }, -- foliage.png: vines and bougainvillea (alpha)
		-- overlays.png: the table glow and the contact shade (alpha); overlays_emissive.png: the
		-- glow pool white, so the cycle can light it up at sunset (Config.Lighting's TableGlow).
		Overlays = {
			Color = "rbxassetid://121924065179218",
			Emissive = "rbxassetid://118986965583502",
		},
		Props = { Color = "rbxassetid://96571614972736" }, -- props_color.png: the props trim sheet, soft shade baked in
		Plants = { Color = "rbxassetid://140554243257866" }, -- plants.png: palm fronds, fern fronds, a leafy clump (alpha)
		-- near_color.png: the near world's trim sheet (alpha in its shallows strip); near_emissive.png:
		-- its windows white, so the near city's windows light up at sunset (Lighting's Windows).
		Near = { Color = "rbxassetid://125734655757192", Emissive = "rbxassetid://91247627901343" },
		-- skyline_color.png: the mid skyline's sheet (backdrop/skyline_textures.py);
		-- skyline_emissive.png: a third of its windows white, lit at sunset (Lighting's Windows).
		Skyline = {
			Color = "rbxassetid://88372511776132",
			Emissive = "rbxassetid://78621028936301",
		},
		Islands = { Color = "rbxassetid://76649656535397" }, -- islands_color.png: the near islands' sheet (backdrop/islands_textures.py)
		-- shallows_color.png: near_color's shallows strip alone, every other strip clear (the same
		-- layout, so the meshes keep their UVs). On near_color the far, low-angle mip levels mixed
		-- the opaque strips round the shallows in, and the rings showed a hard edge.
		Shallows = { Color = "rbxassetid://104750795818920" },
	} :: {
		[string]: { Color: string, Normal: string?, Roughness: string?, Emissive: string? },
	},
	-- The floor: the gray-box's floor parts with this MaterialVariant. Part materials map in
	-- world space (STUDIO_NOTES), so the grid lines up everywhere: 2 x 2 slabs of 9 studs per
	-- image, about half a table long as in the art (Stage 2 critic). 9 divides the table pitch
	-- across (36); the rows (31.5 apart) sit mirrored about the terrace's middle.
	Floor = {
		Variant = "RooftopTile", -- MaterialService.<Variant>
		BaseMaterial = "Slate", -- what it overrides (footstep sounds)
		StudsPerTile = 18,
		Color = "rbxassetid://111994988694463", -- floor_color.png
		Normal = "rbxassetid://78720275464973", -- floor_normal.png
		Tint = "#FFFFFF", -- the floor parts' Color (multiplies the map)
	},
	-- Most unique map images (the brief: 20, besides the two skyboxes and four far cards).
	ImageBudget = 20,
	-- Triangle caps by group (the brief, section 6), checked by prepareImport and prepareProps.
	TriangleCaps = { Rooftop = 60000, Props = 140000, Near = 50000, Backdrop = 110000 },
	MeshPartBudget = 400, -- rooftop and props (the brief)
	BackdropMeshPartBudget = 30, -- the near world and the mid backdrop together (the brief: about 30)
	LightBudget = 20, -- PointLights, SpotLights and SurfaceLights in the whole map, Shadows off

	-- The props (assets/map/fbx/Props.fbx, gen_props.py): one template per kind, each up to
	-- three meshes named <Kind>__Opaque (the props trim sheet), <Kind>__Foliage (the plants
	-- alpha atlas) and <Kind>__Glow (a flat colour that glows). MapBuilder.prepareProps keeps
	-- the templates in ServerStorage and clones one to every spot in the plan.
	Props = {
		Import = "Props", -- the imported model's name in Workspace
		Templates = "MapProps", -- ServerStorage.<Templates>: one template per kind
		Placed = "Props", -- Workspace.Map.<Placed>: every placed prop
		Seats = "Seats", -- Workspace.Map.<Seats>: the invisible Seat parts
		Groups = {
			Opaque = { Maps = "Props" },
			Foliage = { Maps = "Plants", AlphaMode = "Transparency" },
			-- The glass and flames: a flat colour that glows (Neon), so the lanterns read warm
			-- and lit as in the art even by day (as SmoothPlastic they read mint; Stage 3 critic).
			-- Their colours are Config.Lighting's Glow, by kind and light state.
			Glow = { Material = "Neon" },
		},
		-- Per kind: whether its opaque mesh casts a shadow (only the big ones; foliage and
		-- glow never do). A kind with a Glow mesh takes its colour from Config.Lighting's Glow.
		Kinds = {
			LoungeCouch = { CastShadow = true },
			SideCouch = { CastShadow = true },
			CoffeeTable = { CastShadow = false },
			FirePit = { CastShadow = true },
			FernPlanter = { CastShadow = false },
			PalmPlanter = { CastShadow = true },
			Palm = { CastShadow = false },
			PlanterBed = { CastShadow = false },
			Lantern = { CastShadow = false },
			LanternTall = { CastShadow = false },
			GlobeLight = { CastShadow = false },
			UmbrellaSet = { CastShadow = true },
			Piano = { CastShadow = true },
			PianoBench = { CastShadow = false },
		} :: { [string]: { CastShadow: boolean } },
		-- The Seat parts: invisible pads on the seat surfaces; a character sits facing the
		-- prop's seat direction (gen_props seats' yaw).
		SeatSize = { 2, 0.2, 2 },
	},

	-- The fire pit's fire (the client's FirePit module): Roblox's own Fire over the pit's bed and a
	-- flickering warm light, only at sunset (designer, 2026-09-26: the stock fire, not a custom
	-- effect); the static flame mesh is hidden. How much it burns is the day cycle's
	-- (Config.Lighting's Fire: none by day, all at sunset). Colours are hex. (tune)
	FirePit = {
		Kind = "FirePit", -- the prop kind: Map.Props.<Kind>_<n>, its meshes <Kind>__Opaque and __Glow
		BedDrop = 0.5, -- the pit's bed sits this far under its rim
		Fire = { Size = 5, Heat = 9, Color = "#FF7A2A", SecondaryColor = "#FFC23A" },
		Light = { Brightness = 2.5, Range = 16, Color = "#FF9A45", Flicker = 0.3, FlickerSpeed = 9 },
	},

	-- The near world below the roof (assets/map/fbx/Near.fbx, gen_near.py; Stage 4): the
	-- tower's walls, the streets and neighbour buildings, the promenade, beach and painted
	-- shallows, palms, trees and one sailboat template. MapBuilder.prepareNear places it by
	-- its anchors as Map.<Import>. Nobody can get down there, so nothing in it collides.
	Near = {
		Import = "Near", -- the imported model's name in Workspace, then Map.<Import>
		-- Every mesh the model must hold: its map set (Maps), alpha and RenderFidelity. The
		-- backdrop casts no shadows. It draws at Precise, not the brief's Performance: Roblox's
		-- distance LOD crumpled the boxy meshes and smeared their textures, so the parks below
		-- read as grass terraces and the far towers warped (designer, 2026-09-26). Only about
		-- 9,000 triangles here. The tower's walls are big and close, so they keep Automatic,
		-- and cast the tower's shadow: without it the rooftop's own shadow lay on the plaza 300
		-- below as a floating outline.
		Meshes = {
			Tower = { Maps = "Arch", Fidelity = "Automatic", CastShadow = true },
			Ground = { Maps = "Near", Fidelity = "Precise" },
			Buildings_Left = { Maps = "Near", Fidelity = "Precise" },
			Buildings_Front = { Maps = "Near", Fidelity = "Precise" },
			Coast = { Maps = "Near", Fidelity = "Precise" },
			Shallows = { Maps = "Shallows", AlphaMode = "Transparency", Fidelity = "Precise" },
			Palms = { Maps = "Plants", AlphaMode = "Transparency", Fidelity = "Precise" },
			Trees = { Maps = "Plants", AlphaMode = "Transparency", Fidelity = "Precise" },
		} :: {
			[string]: { Maps: string, AlphaMode: string?, Fidelity: string?, CastShadow: boolean? },
		},
		-- The sailboats: the Boat mesh kept in ServerStorage.<Templates>, cloned once per path
		-- into Map.<Import>.<Folder>; each client drifts them along their paths from the
		-- server's clock (MapMotion.boatPose), so everyone sees the same boats.
		Boat = {
			Mesh = "Boat",
			Scale = 1.5, -- the template (40 long) this much bigger, so a boat reads from the roof (critic 2)
			Templates = "MapNear",
			Folder = "Boats",
			SeaY = -304, -- the sea's surface (city_plan.WORLD.sea_y; the tests check they agree)
			MaxSpeed = 4, -- studs a second: drifting, never racing (the brief)
			BobHeight = 0.3, -- studs, up and down on the swell...
			BobSeconds = 5.5, -- ...once in this long
			RollDegrees = 2, -- side to side...
			RollSeconds = 7,
			PitchDegrees = 1, -- and bow to stern
			PitchSeconds = 6,
			-- Long slow loops at sea behind the tower and off its ocean side, where the roof's
			-- high and day views look (Stage 4 critic: none showed from the roof). Centre X, Z;
			-- Radius along X, Z; Seconds a loop; Phase 0..1 where it starts; Direction 1
			-- anticlockwise seen from above, -1 clockwise.
			Paths = {
				{
					Centre = { 450, -1000 },
					Radius = { 250, 150 },
					Seconds = 900,
					Phase = 0,
					Direction = 1,
				},
				{
					Centre = { 900, -600 },
					Radius = { 300, 140 },
					Seconds = 1100,
					Phase = 0.4,
					Direction = -1,
				},
				{
					Centre = { 250, -1500 },
					Radius = { 200, 150 },
					Seconds = 800,
					Phase = 0.7,
					Direction = 1,
				},
			},
		},
	},

	-- The mid backdrop (assets/map/fbx/Backdrop.fbx, gen_backdrop.py; Stage 5): the skyline from
	-- the near world's edge out to 2,300 studs and the near islands out to 2,500, in chunks
	-- named Prefix_i_j, each dressed by its prefix's row. Everything further is painted into
	-- the skybox (Stage 6): at low graphics levels Roblox draws nothing this far. No shadows.
	-- RenderFidelity Precise, as the near world's (Performance's LOD warped the towers).
	Backdrop = {
		Import = "Backdrop", -- the imported model's name in Workspace, then Map.<Import>
		Meshes = {
			Skyline = { Maps = "Skyline", Fidelity = "Precise" },
			Islands = { Maps = "Islands", Fidelity = "Precise" },
			IslandShallows = { Maps = "Shallows", AlphaMode = "Transparency", Fidelity = "Precise" },
		} :: { [string]: { Maps: string, AlphaMode: string?, Fidelity: string? } },
	},
}

---------------------------------------------------------------------------------------------
-- Lighting (the rooftop map): the Day and Sunset states and the cycle between them, the same
-- for everyone on a server (the brief: Day 10 min, Sunset 5 min; no night: one was tried and
-- dropped by the designer, 2026-10-05). LightCycle mixes the two states by the server's clock,
-- MapLighting puts a state onto the place (MapLighting.preview in Edit mode, for captures and
-- so the place is saved lit), and DayCycle drives it on each client. Day and Sunset have the
-- same keys (a Lune test checks). Colours are hex strings. The background (the city, the islands, the sea) is kept
-- soft by the haze and the depth of field so the eye goes to the tables (designer,
-- Checkpoint C).
---------------------------------------------------------------------------------------------
Config.Lighting = {
	Cycle = {
		Day = 600, -- seconds of day
		-- seconds of each fade, eased (designer, 2026-10-05: 10, the minute's fade was too slow)
		Fade = 10,
		Sunset = 300, -- seconds of sunset
		-- Test only: the cycle runs this many times as fast (Checkpoint D's timed run). A Lune
		-- test keeps it 1, so a test value cannot be committed.
		Speed = 1,
		Look = 2, -- seconds between a client's looks for map parts still streaming in
		-- workspace's attribute holding the cycle's offset (scaled seconds); an arena sets it so
		-- its match opens at day (ArenaService). The server's, so all agree.
		OffsetAttribute = "DayCycleOffset",
		-- The /day, /sunset and /cycle developer commands (Config.Debug.Commands) hold the
		-- light: workspace attributes (LightCycle.readHold) every client reads. Goal is the blend
		-- held (none: back to the cycle), From the blend shown when typed, At the scaled clock.
		Hold = { Goal = "LightHoldGoal", From = "LightHoldFrom", At = "LightHoldAt" },
		Holds = { Day = 0, Sunset = 1 }, -- each command's blend
	},
	-- The sky's images change in one frame at these blends (0 Day, 1 Sunset), both ways: Day's
	-- sky, then DuskSky, then Sunset's. One swap from the blue day sky to the magenta sunset one
	-- popped even under a haze (Studio, 2026-09-26), so an in-between sky halves each step.
	SkySwaps = { 0.3, 0.6 },
	-- gen_sky.py's dusk faces (textures/sky_dusk_*.png): half way from the day sky to the sunset
	-- one, the same cloud scene.
	DuskSky = {
		SkyboxBk = "rbxassetid://133151880175765",
		SkyboxDn = "rbxassetid://120434251320949",
		SkyboxFt = "rbxassetid://86916716496048",
		SkyboxLf = "rbxassetid://77746871022306",
		SkyboxRt = "rbxassetid://138655321584686",
		SkyboxUp = "rbxassetid://110285038213161",
	},
	-- Round each swap (Width of the blend either side), the Atmosphere thickens by Density and
	-- Haze and the sky's light on the scene (EnvironmentDiffuse and Specular scales) dims by
	-- the share Environment. Only a hint: a real haze (0.5) takes the sky's colour and tints the
	-- whole rooftop with it, so the swap showed more, not less (Play, 2026-09-26); the dusk sky
	-- does the hiding.
	SwapHaze = { Width = 0.1, Density = 0.03, Haze = 0, Environment = 0.2 },
	-- Half way through a fade, the light leans warm (a dusk, not a grey overcast: the straight mix
	-- of the day's white light and the sunset's lavender read grey; Stage 7 critic 2). Each named
	-- colour (a Day and Sunset key; "Block.Key" inside a block) moves Amount of the way toward
	-- its colour here at blend 0.5, easing to nothing by Width either side.
	DuskWarm = {
		Width = 0.35,
		Amount = 0.6,
		Colours = {
			OutdoorAmbient = "#B08C84", -- between the day's and the sunset's warm shades (2026-09-26 look)
			ColorShift_Top = "#FFB880",
			["ColorCorrection.TintColor"] = "#FFE6D0",
		},
	},
	-- The sun by blend (Spec section 6): Roblox's sun sets over the city, so the sunset one is a
	-- dawn sun swung by the latitude to sit low over the sea, right of the lounge. Measured in
	-- Studio (2026-09-26): straight between these two it slides down the ocean side (azimuth
	-- 128 to 35, elevation 54 to 12), never across the sky or under the horizon. It arrives
	-- before the sunset sky's swap, so it stands in the painted glow whenever that sky is up.
	-- The sunset sun is a golden hour, 12 degrees up (designer, 2026-09-26: bright and happy
	-- but warm and cosy): at 4 degrees (ClockTime 6.4) it only grazed the roof, the shade's
	-- light carried the scene and everything read lavender-grey. Its disc still sits in the
	-- painted glow above the sea (Play capture).
	SunPath = {
		{ Blend = 0, GeographicLatitude = 45, ClockTime = 10 },
		{ Blend = 0.5, GeographicLatitude = -30, ClockTime = 7.4 },
	},
	-- Day (Spec section 6): the sun high and front-right. Tuned in Studio (2026-09-26) until
	-- the floor rendered near the art's measured #F1CDBD: Roblox's default noon light (a white
	-- sun, a strong blue sky fill) washed every warm colour to grey. Then made brighter and
	-- more saturated, like the top Roblox games (designer, 2026-09-26: it read pastel and
	-- hazy): a stronger sun, a lighter and cleaner shade, less haze, and colour and contrast
	-- lifted in ColorCorrection. A stronger sun than 2.6 blew the pale floor out to white. (tune)
	Day = {
		Brightness = 2.6,
		ExposureCompensation = -0.05,
		EnvironmentDiffuseScale = 0.45, -- less of the blue sky's fill
		EnvironmentSpecularScale = 0.6,
		Ambient = "#000000",
		OutdoorAmbient = "#8C8480", -- a light warm shade (the brown #7D6C62 greyed it)
		ColorShift_Top = "#FFE4C4", -- the sun's warm tint on lit faces
		ColorShift_Bottom = "#000000",
		-- A pale sky-blue haze, so the far distance fades toward the art's pale horizon rather
		-- than grey (Stage 4 critic). Density and Offset 0.2 fade the far city and its join
		-- with the painted sky while the roof stays crisp (designer, 2026-09-26: "fade away
		-- into the distance"; tuned in Play, where 0.3 greyed the whole city). 0.08 since the
		-- brighter look: 0.15 veiled the far tables too.
		Atmosphere = {
			Density = 0.08,
			Offset = 0.2,
			Haze = 0,
			Glare = 0,
			Color = "#C6E5FC",
			Decay = "#A9D4FA",
		},
		-- Lighting.Sky: assets/map/gen_sky.py's day faces (textures/sky_day_*.png): the art's
		-- gradient and cumulus clouds, the far city and islands painted on the horizon (Stage 6).
		Sky = {
			SkyboxBk = "rbxassetid://136510513323451",
			SkyboxDn = "rbxassetid://112654746925961",
			SkyboxFt = "rbxassetid://98738080244894",
			SkyboxLf = "rbxassetid://116034246180095",
			SkyboxRt = "rbxassetid://129820624640544",
			SkyboxUp = "rbxassetid://93123509257023",
			-- degrees; Roblox's 21 glares over the painted sky. 0: no sun disc for now (designer,
			-- 2026-10-05, a lighting test; it was 12). The sun still lights the roof. (tune)
			SunAngularSize = 0,
			MoonAngularSize = 0, -- no moon: a dawn sky can show it near the horizon
			StarCount = 0, -- no stars
			CelestialBodiesShown = true, -- the sun is Roblox's, never painted
		},
		-- Terrain water (Studio test, 2026-09-26): nearly clear, with little reflection, so the
		-- sea renders the art's bright blue (about #349BD6) instead of mirroring the pale sky
		-- (Roblox's reflectance 1 made the far sea read nearly as pale as the sky). What lies
		-- under the water shows only at high graphics quality, so the shallows are painted on
		-- the near world's beach, not seen through the water.
		Water = {
			WaterColor = "#1B6FBF",
			WaterTransparency = 0.85,
			WaterReflectance = 0.05, -- barely any: the sky's clouds smeared white on the water (Stage 4 critics)
			-- Visible swell (designer, 2026-09-26: make the water move); the low reflectance keeps
			-- the sky's clouds from smearing across it. (tune)
			WaterWaveSize = 0.25,
			WaterWaveSpeed = 12,
		},
		-- Post effects: always enabled (MapLighting.preview), faded by their numbers. (tune)
		ColorCorrection = {
			Brightness = 0,
			Contrast = 0.12,
			Saturation = 0.2,
			TintColor = "#FFFFFF",
		},
		-- Bloom on (designer, 2026-10-01): the cue auras' HDR glow (particle Brightness above
		-- about 3) blooms; at Threshold 2.6 the floor, balls, tables and UI do not (1.1-1.8 made
		-- the balls glow).
		Bloom = { Intensity = 1, Size = 24, Threshold = 2.6 },
		SunRays = { Intensity = 0, Spread = 0.5 },
		-- The background soft, the rooftop sharp (designer, Checkpoint C): in focus from the
		-- camera out to FocusDistance + InFocusRadius (260 studs: the whole roof, the lounge
		-- from the entrance), blurred beyond by FarIntensity (at 1 the lounge blurred from the
		-- day view). Tested in Play, 2026-09-26: Studio's Edit viewport draws no depth of field.
		-- Devices that skip the effect still have the soft painted sky.
		DepthOfField = {
			FarIntensity = 0.5,
			FocusDistance = 100,
			InFocusRadius = 160,
			NearIntensity = 0,
		},
		-- The Neon glass and flames (Map.Props.<Kind>__Glow), by prop kind. Neon renders a colour
		-- much lighter, so these are the art's deeper amber and flame clusters: they render as its
		-- lit glass and flame (the pale measured #FAE091 read white-lime; Stage 3 critic 2).
		Glow = {
			Lantern = "#FBB267", -- the art's amber lantern glass
			LanternTall = "#FBB267",
			GlobeLight = "#FBB267",
			FirePit = "#C25A1E", -- the flame: deeper still, or Neon reads it lemon (critic 3)
		},
		-- The PointLights at the props' light spots (the tall lanterns, the globes, the fire pit).
		Lights = { Brightness = 0.4, Range = 14, Color = "#FFD9A0" },
		-- Self-lit glow (SurfaceAppearance emissive, through a mask image): the under-table glow
		-- (Map.Rooftop.TableGlow) and the skyline's lit windows (Map.Backdrop.Skyline_*). Color
		-- tints the skyline's and the near islands' look (white: as painted).
		TableGlow = { EmissiveStrength = 0, EmissiveTint = "#EF9054" },
		TableLights = { Brightness = 0 }, -- the lamps over the tables (Look.TableLight): off by day
		Fire = { Intensity = 0 }, -- the fire pit's fire (Map.FirePit): out by day
		Windows = { EmissiveStrength = 0, EmissiveTint = "#D5B59C", Color = "#FFFFFF" },
		Islands = { Color = "#FFFFFF" },
	},
	-- Sunset (Spec section 2's sunset targets: a magenta and purple sky, the sun low over the sea
	-- right of the lounge, warm lanterns, lit windows). Same keys as Day. A golden hour since
	-- 2026-09-26 (designer: keep it bright and happy while warm and cosy; the lavender dusk read
	-- washed out and grey): a stronger golden sun a little higher (SunPath), a warm light shade,
	-- less of the magenta sky's fill, a thinner warm haze, and colour lifted. The sky keeps
	-- the sunset. Tuned in Play captures. (tune)
	Sunset = {
		Brightness = 3.4,
		ExposureCompensation = 0.1,
		EnvironmentDiffuseScale = 0.25, -- the magenta sky's fill tinted the whole roof pink
		EnvironmentSpecularScale = 0.6,
		Ambient = "#000000",
		-- The shade: a light warm tan, so the floor reads peach in the golden light, not rose
		-- (a mauve #AC94A4 turned it pink) or lavender-grey (the cool #8E86A4 before).
		-- Less warm (designer, 2026-10-05: "way too yellow saturated"; it was #B8A090).
		OutdoorAmbient = "#B4A49C",
		ColorShift_Top = "#FFDDB8", -- the low sun's soft gold on lit faces (#FFCB88 read yellow)
		ColorShift_Bottom = "#000000",
		-- A thin warm tint, no haze: in Play (not in Edit's preview) Haze 0.3 and density 0.1
		-- fogged the 3D city, islands and sea into one flat magenta (Studio, 2026-09-26).
		-- Density alone keeps the lit windows and fades the far edge (Play); 0.08 as by day,
		-- peach rather than the rose #D8BCC8, which veiled the roof grey-pink.
		Atmosphere = {
			Density = 0.08,
			Offset = 0.2,
			Haze = 0,
			Glare = 0,
			Color = "#F0C8BC", -- a softer peach (#F6C2A4 before, 2026-10-05)
			Decay = "#8A4C8A",
		},
		-- gen_sky.py's sunset faces (textures/sky_sunset_*.png): the day's cloud scene lit by the
		-- low sun, a glow round it, the purple sea with the sun's path, the far city's lit windows.
		Sky = {
			SkyboxBk = "rbxassetid://110051239637159",
			SkyboxDn = "rbxassetid://88040117694749",
			SkyboxFt = "rbxassetid://96378244528009",
			SkyboxLf = "rbxassetid://94840130578947",
			SkyboxRt = "rbxassetid://76832687371860",
			SkyboxUp = "rbxassetid://139224542954081",
			-- a gold disc on the horizon, not a white blaze (critics 1 and 2); 0: no sun disc for
			-- now (designer, 2026-10-05, a lighting test; it was 5)
			SunAngularSize = 0,
			MoonAngularSize = 0,
			StarCount = 0,
			CelestialBodiesShown = true,
		},
		Water = {
			WaterColor = "#5C5CA8", -- the art's violet sunset sea (#6263A0)
			WaterTransparency = 0.85,
			-- More reflection than by day: the sea picks up the pink sky round the sun, as in
			-- the art (at 0.05 it was flat indigo). No clouds to smear at this sun angle.
			WaterReflectance = 0.2,
			WaterWaveSize = 0.25,
			WaterWaveSpeed = 12,
		},
		-- Colour lifted less than by day: 0.25 pushed the felt to neon in the golden light.
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.1,
			Saturation = 0.05, -- 0.15 with a #FFF4E6 tint read too yellow (designer, 2026-10-05)
			TintColor = "#FFF9F4",
		},
		-- The lanterns, windows and cue auras bloom; the higher threshold keeps the sun from
		-- blowing out to a white disc (Intensity 0.3 at Threshold 2.2 before the auras, 2026-10-01).
		Bloom = { Intensity = 0.8, Size = 24, Threshold = 2.6 },
		SunRays = { Intensity = 0, Spread = 0.5 }, -- 0 with the sun disc hidden (was 0.04, 2026-10-05)
		DepthOfField = {
			FarIntensity = 0.5,
			FocusDistance = 100,
			InFocusRadius = 160,
			NearIntensity = 0,
		},
		Glow = {
			Lantern = "#F59038", -- deeper, or Neon reads the glass lime (critic 2)
			LanternTall = "#F59038",
			GlobeLight = "#FFC070",
			FirePit = "#E06A20",
		},
		-- Brighter than by day, not blinding: at 2 and 20 studs the globes washed the lounge's
		-- couches white (Play, 2026-09-26).
		Lights = { Brightness = 0.8, Range = 12, Color = "#FFC99A" }, -- small amber pools (critic 2)
		-- A tight rim at each table's foot (the mask's glow is tighter than the painted pool).
		TableGlow = { EmissiveStrength = 0.8, EmissiveTint = "#EF9054" },
		-- The lamps over the tables lit, so a game is easy to see (designer, 2026-09-26). (tune)
		TableLights = { Brightness = 3 },
		Fire = { Intensity = 1 }, -- the fire pit burning (designer: only at sunset)
		-- The city and the near islands toward the art's dusk (blue-violet glass, island
		-- silhouettes #564175), as the painted far world is.
		-- The city at sunset (designer, 2026-09-26): its windows lit a warm yellow and its walls
		-- tinted pink-lavender by the sky (the blue-violet tint turned the brown maroon). The
		-- mid skyline's and the near world's buildings alike.
		Windows = { EmissiveStrength = 0.9, EmissiveTint = "#FFD27A", Color = "#C9A0D2" }, -- 1.6 read all orange
		Islands = { Color = "#6A5088" }, -- violet silhouettes, as the art's (#673E6D)
	},
}

---------------------------------------------------------------------------------------------
-- The global queue (designer, 2026-09-28): the host's Join Global Queue looks for an opponent
-- in every server, matched by rank, and both sides teleport into an arena (a reserved server
-- of this same place, Config.Arena). Pure matching: src/shared/Matchmaking; the Roblox side
-- (MemoryStore, TeleportService): src/server/GlobalQueue. Times are seconds. (tune)
---------------------------------------------------------------------------------------------
Config.GlobalQueue = {
	-- MemoryStore sorted maps. A new name starts an empty queue: change it only on purpose
	-- (Roblox keeps Studio's memory stores apart from the live game's by itself).
	Maps = {
		Tickets = "GQ_Tickets_v1_", -- one per mode: .. teamSize ("GQ_Tickets_v1_2" is 2v2)
		Lease = "GQ_Lease_v1", -- which server runs the matching now
		Matches = "GQ_Matches_v1", -- each arena's players, keyed by its reserved server id
		-- Each lobby server's "still open, with N players", keyed by its JobId, so Lobby only
		-- sends players back to a server that still exists (Roblox shuts an empty one down,
		-- and a teleport to it fails with error 771 and Roblox's own popup).
		Servers = "GQ_Servers_v1",
	},
	LeaseKey = "leader",
	-- How far apart two searches may be, in rank divisions, by how long the one that has
	-- waited longer has searched: the closest rank first, anyone after 10 s (designer,
	-- 2026-09-28: "as quick as possible ... after 10 seconds pair with anyone"). Within the
	-- range the closest is always picked. (tune)
	Window = {
		{ After = 0, Divisions = 1 },
		{ After = 3, Divisions = 3 },
		{ After = 6, Divisions = 6 },
		{ After = 10, Divisions = math.huge },
	},
	-- "Play another" never meets the opponent it just played until it has searched this long
	-- (after that, anyone rather than no one).
	AvoidRecentSeconds = 10,
	MatchTickSeconds = 1, -- the leader pairs everyone searching this often
	PollSeconds = 0.5, -- each server checks its own searches for a match this often
	HeartbeatSeconds = 2, -- each server marks its searches alive this often...
	StaleSeconds = 8, -- ...and one not marked for this long (its server died) is skipped
	TicketLifeSeconds = 120, -- a search MemoryStore forgets unless marked alive again
	ClaimTimeoutSeconds = 5, -- a half-made match (the leader died mid-way) is undone after this
	LeaseSeconds = 6, -- the leader's turn lasts this long unless renewed...
	LeaseRenewSeconds = 2, -- ...which it (and every other server, trying) does this often
	MatchRecordSeconds = 900, -- how long an arena's player list is kept
	PageSize = 200, -- MemoryStore's most per read
	MaxScan = 1000, -- the most searches one mode reads per tick
	-- Reserved servers made ahead of time by the leader, so a match does not wait for one.
	ReservePool = 2,
	TeleportRetries = 3, -- a failed teleport is tried again this many times...
	TeleportRetrySeconds = 1, -- ...this far apart, then the players are told and stay
	-- A teleport that has neither taken the player away nor failed after this long is given
	-- up: the save comes back and the player is told (a hung client).
	TeleportHangSeconds = 45,
	-- A failed MemoryStore call is tried again this many times, this far apart.
	StoreRetries = 3,
	StoreRetrySeconds = 0.25,
	ServerBeatSeconds = 10, -- a lobby server marks itself open this often...
	ServerStaleSeconds = 25, -- ...and one not marked for this long is taken as closed
	-- What a match-found player sees before the teleport starts, so the screen can come up.
	FoundLeadSeconds = 0.4,
	-- The Ults: On / Off choice (designer, 2026-09-28): a search only meets searches on the
	-- same setting, two pools in the one queue (each ticket names its pool). A No-ults
	-- search that has found nobody after this long is offered the ults-on pool ("Search
	-- with ults on?"), keeping its search time. (tune)
	NoUltsFallbackSeconds = 30,
	-- The server takes the offer's Yes this much sooner than the card shows it (the
	-- client's estimate of the server clock may run a little ahead).
	FallbackSlackSeconds = 1,
	-- Player attributes the server sets (clients only read them): the saved choice the
	-- host's toggle shows (Ults.QueueUlts), and the pool of the search their pad runs (read
	-- only while it searches).
	UltsAttribute = "QueueUlts",
	SearchUltsAttribute = "QueueSearchUlts",
}

---------------------------------------------------------------------------------------------
-- The arena (designer, 2026-09-28): the same rooftop, its light and its day cycle, with just
-- one table, in the middle, for the match the global queue made (a reserved server of this
-- place). Studs, world axes.
---------------------------------------------------------------------------------------------
Config.Arena = {
	-- The workspace attributes an arena's server sets before anyone arrives, so every client
	-- knows before it builds anything: the place's mode ("Arena", or "Hub") and the team size.
	ModeAttribute = "PlaceMode",
	TeamSizeAttribute = "ArenaTeamSize",
	-- The one table (Placement.setLayout gives it id 1): the middle of the rooftop, where the
	-- four middle tables' aisles cross (clear floor at Y = 0, checked in Studio 2026-09-28).
	Table = { id = 1, X = 0, Y = 0, Z = 0, YawDegrees = 0 },
	-- Its look (Config.TableModel.Looks): the blue felt on satin black (designer, 2026-09-28).
	Look = "Blue",
	RecordWaitSeconds = 10, -- how long a new arena looks for its player list
	-- Players have this long (from the list's arrival) to come in; then the game starts if
	-- both sides have someone, or whoever came searches again. (tune)
	ArrivalSeconds = 25,
	-- After the rematch countdown, anyone who chose nothing is sent back to the lobby.
	-- Someone searching for another game from here may wait this long, then goes too.
	SearchMaxSeconds = 120,
	-- A side whose opponent never came searches again for anyone, for this long at most, then
	-- goes to the lobby (it has no row of buttons, only Leave on a keyboard or pad).
	NoShowSearchSeconds = 30,
	-- Someone who cannot be seated here (not on the list) is sent to the lobby, tried again
	-- this far apart, and kicked with a line to rejoin if every try fails.
	EvictRetrySeconds = 5,
	-- Arriving players stand on the table's pad side, facing it: team 1 to the left of the
	-- pad's centre, team 2 to the right, this far apart (studs).
	ArrivalSpacingStuds = 2.5,
}

-- The global queue's screens (designer, 2026-09-28): the small card at the top middle
-- (QueueStatus: an arena's arrivals, a teammate's search, why a teleport did not happen) and
-- the full screen shown while a teleport is on its way (TeleportScreen). Pixels and seconds.
Config.UI.Queue = {
	StatusWidth = 320, -- the card's width before it shrinks to fit a phone
	StatusHeight = 44,
	StatusTop = 8, -- below Roblox's top bar
	StatusTextPx = 18,
	NoticeSeconds = 4, -- a one-off line (a failed teleport) shows this long
	ZIndex = 28, -- over the match bar, under the result screen
	-- The teleport screen: a dark full screen with the title and one line, a pulse of dots.
	TeleportZIndex = 60,
	TeleportColor = { 16, 22, 26 },
	TeleportAccent = { 40, 220, 150 }, -- MATCH FOUND in a bright green
	TeleportTitlePx = 48,
	TeleportLinePx = 22,
	-- A teleport that has not taken the player away after this long gives the screen back
	-- (the server also says when one failed).
	TeleportGiveUpSeconds = 20,
	-- Arriving from a teleport, the screen stays until the arena's table is ready, at most
	-- this long, then fades out in FadeSeconds.
	ArrivalHoldSeconds = 15,
	FadeSeconds = 0.4,
}

-- The matchmaking bar (MatchBar; designer, 2026-10-07, look A): one slim pill above the lucky
-- block hotbar for everyone on a waiting pad, the mode icon, a count chip and "Waiting for
-- opponent...". The host alone gets "Don't want to wait?" and a big green Play Global joined
-- to its right end after a short wait, then the search's time and a small red X. Pixels are
-- a computer's; a phone draws the same bar at PhoneScale. Seconds as named.
Config.UI.MatchBar = {
	-- When Play Global shows: this long after stepping on with no Roblox friend in the server
	-- (the popup has gone to everyone), longer with one (a friend may be on their way). (tune)
	PromptAloneSeconds = 3,
	PromptFriendsSeconds = 5,
	BottomPx = 10, -- from the screen's bottom, plus the hotbar's lift (BottomLift) when it shows
	PhoneScale = 0.8, -- the whole bar on a phone (screen narrower than LuckyBlocks.UI.PhoneWidthPx)
	ZIndex = 26, -- over the world's HUD, under the status card and the result screen
	PillHeight = 44,
	PillPadPx = 6, -- inside the pill, round its row
	GapPx = 8, -- between the pieces in the row
	Icon = "Classic", -- the mode icon: the old pad card's Classic picture (Config.UI.Kit.Icons)
	IconPx = 32,
	ChipHeight = 30, -- the "1/2" chip
	ChipWidth = 68,
	ChipTextPx = 20,
	LineTextPx = 21, -- "Waiting for opponent..."
	-- The line's fixed width (its longest words), so the bar never jumps as the dots light.
	LineWidthPx = 250,
	DotSeconds = 0.4, -- the waiting line's dots light one by one, this long each
	-- Play Global: joined to the pill's right end, slightly taller so it reads as the hero.
	GlobalHeight = 52,
	GlobalWidth = 190,
	GlobalTextPx = 26,
	GlobalOverlapPx = 14, -- tucked this far under the pill's rounded right end
	AskTextPx = 18, -- "Don't want to wait?" just above the button (designer, 2026-10-07: 1 px bigger)
	AskGapPx = 2,
	GrowSeconds = 0.2, -- the pill making room for Play Global
	-- Play Global's idle: a gentle breath (designer, 2026-10-07: gentler than the house pulse,
	-- 1.03 over 0.9 s), its first this long after it lands.
	PulseDelaySeconds = 0.6,
	PulseScale = 1.015,
	PulseSeconds = 1.6,
	-- The red X while the search runs.
	CancelPx = 38,
	-- The small red X on Play Global's top-right corner (designer, 2026-10-07): dismisses it
	-- for those who would rather keep waiting (still a 44 px touch).
	DismissPx = 24,
	DismissInsetPx = 6, -- how far its centre sits in from the button's corner
	-- The spawn pill (designer, 2026-10-07): a player alone in a public lobby server gets
	-- "Don't want to wait?" and Play Global the moment they spawn; it goes by itself after
	-- this long if they ignore it (a search it started keeps it up). (tune)
	SpawnPillSeconds = 20,
	-- The workspace attribute the server sets true in a public lobby server (no private server,
	-- no arena): a client cannot read game.PrivateServerId.
	PublicLobbyAttribute = "PublicLobby",
}

-- The economy's menus (2026-09-28, docs/prompts/ECONOMY_UI_PROMPT.md sections 5 and 5.1): the
-- left column (MenuColumn), every full menu's frame (MenuFrame: header band, tabs, sheet, red
-- X), its confirm dialog, notice line, scrollers and card tiles, the rarity dressing and cue
-- thumbnails (CueThumb) and the top banner (Banner). Pixels and seconds. "Short" values are for
-- a phone on its side (the HUD screen under Multiplayer.Style.ShortHeight, as the rank and money
-- HUDs). A menu's slight dim is the roadmap's (Config.UI.Progress.Roadmap.Dim*). (tune)
Config.UI.Menu = {
	-- The menus whose panel and cards take Kit.PaleEdge's pale-blue outline instead of ink
	-- (designer, 2026-10-06: these four for now). Names as Menus.register ("Ults": Abilities).
	PaleEdgeMenus = { "Shop", "Inventory", "Ults", "FreeReward" },
	-- The lively frame (docs/prompts/SHOP_LIVELY_PROMPT.md section 5), a kit switch per menu:
	-- the panel unrolls open and folds shut (Stage, with the menu's Open schedule), the header's
	-- 8-balls scroll, the white sheet has the still dots and an 8-ball sits on the top edge.
	-- Menus not listed keep the kit frame (pop in, still pattern). Names as Menus.register.
	LivelyMenus = { "Shop" },
	-- One thing at a time (HudFocus; designer, 2026-10-06): while a full menu is open every
	-- other screen of ours is off. These ScreenGuis stay on (a "...Menu" screen always does):
	-- popups that must still reach the player and invisible probes. KeepWith: more per menu.
	Focus = {
		Keep = {
			"MenuTopbar", -- probes (no pictures)
			"TopbarRoom",
			"PowerSafeProbe",
			"UltScreenTopbar",
			"Freecam",
			"LuckyOpening", -- the reel and its dim
			"LuckyOpeningDim",
			"TeleportScreen",
			"TutorialGui",
			"TradeInvite", -- someone asking to trade
			"RewardsFlyer", -- rewards flying in
			"RankClaimBlock", -- the roadmap's claim card
		},
		KeepWith = {
			LuckyBag = { "LuckyHotbar" }, -- the bag opens over its hotbar
		},
	},
	Lively = {
		-- The header band's 8-balls (assets/ui/frame/header_tile.png: pattern.png at a 200 texel
		-- period repeated across 1024), scrolling up-left at 45 degrees. Numbers from the approved
		-- animatic (2026-10-06): a period shown 260 px across, a whole period every 16 s.
		HeaderImage = "rbxassetid://103637839065202",
		HeaderPeriod = 200, -- texels per repeat in HeaderImage
		HeaderSheetPx = 1024, -- HeaderImage's size: the scroll window stays inside it
		HeaderTilePx = 260, -- one repeat shown this big (the kit's still pattern: 380 per 512)
		HeaderPxPerSecond = 23, -- along the 45 degree line (16.25 px/s on each axis)
		HeaderTransparency = 0.6, -- a little more visible than the kit's 0.7 (brief, gate 2)
		-- The white sheet's dots: the original tiny pool balls (option A, designer 2026-10-06),
		-- assets/ui/frame/dots_512.png, white, tinted and faded here. Still.
		DotsImage = "rbxassetid://91688642128658",
		DotsColor = { 74, 123, 192 },
		DotsTransparency = 0.92, -- about 8%
		DotsTilePx = 88, -- one 512 px tile shown this big
		-- The lively panel's size (designer, 2026-10-06: menus covered the whole phone screen):
		-- never in Roblox's top bar row, at most this share of the screen's width, and only as
		-- tall as its page's first screen (the hero card), up to the room under the bar. The
		-- jump buttons stand outside its right edge.
		MaxWidthShare = 0.66,
		-- Its own smaller header and tighter rows (designer, 2026-10-06: "shrink the header
		-- more... use up as much room as you can"); anything not here is Config.UI.Menu.Frame's.
		Frame = {
			HeaderPx = { 32, 44 }, -- the title row
			TitleScale = 0.75,
			TitleOfHeader = 0.82, -- the title fills its row, the icon beside it as tall as the row
			IconShare = 1.3,
			CloseMaxPx = 34,
			CloseOfMoney = 0.95, -- the red X a little smaller than the money pill (its touch area stays 44)
			MoneyPx = { 28, 34 },
			MoneyTextPx = { 16, 18 },
			PaddingPx = { 4, 8 },
			GapPx = { 4, 6 },
			ContentPadPx = { 2, 6 },
		},
		-- The 8-ball flair pinned on the panel's left edge (designer, 2026-10-06), its middle on
		-- the edge DownShare of the way down. It drops on last (the Open schedule's "Flair"),
		-- rocks RockDegrees either way over RockSeconds, and every HopEvery s hops HopPx for
		-- HopSeconds with a sparkle (Config.UI.Effects.Sparkle).
		FlairImage = "rbxassetid://132422184916082", -- as Config.UI.GrandOpeningCard.Images.Flair8ball
		FlairPx = 48,
		FlairDownShare = 0.85, -- low, clear of the NEW tag and the block
		FlairRockDegrees = 5.7,
		FlairRockSeconds = 2.9,
		FlairHopEvery = 5,
		FlairHopPx = 9,
		FlairHopSeconds = 0.4,
		FlairSparklePx = 40,
		-- Idle rocks once landed: the menu's icon (the basket) and the selected tab's icon.
		IconRockDegrees = 3.4,
		TabRockDegrees = 6.9,
		RockSeconds = 2.9,
	},
	-- The left column (reference 06): one tile each, top to bottom, each just its big icon
	-- with no box behind it (designer, 2026-09-28). Keys name the menus (Menus.register) and
	-- their words (Strings.Menus.Column) and icons (Kit.Icons).
	Column = {
		-- GUI lane (designer 2026-10-03, C2): Shop, Inventory, Abilities ("Ults"), and Free
		-- Reward while something is left to claim. Rewards and Trade left the column (daily
		-- and playtime rewards pop up; trading starts from the player list).
		Order = { "Shop", "Inventory", "Ults", "FreeReward" },
		TilePx = 78, -- a tile's square slot, its touch area (a computer or tablet)
		ShortTilePx = 52, -- on a phone (at least a 44 px touch target)
		GapPx = 4, -- between two slots (the icons' own margins space them out)
		ShortGapPx = 8, -- a phone's words overhang the small slots: room for the next red dot
		MarginPx = 12, -- from the screen's left edge (the money HUD's margins)
		ShortMarginPx = 8,
		-- A phone: the column starts this far under the rank HUD's badge (it hangs below
		-- Roblox's 58 px top row); a big screen centres it on the left edge.
		BelowRankPx = 6,
		AboveMoneyPx = 20, -- and it always ends at least this far above the money HUD
		MinScale = 0.8, -- a screen too short for it shrinks the column, never below this
		IconShare = 1.08, -- the glossy icon's size, of the slot (its own margins are clear)
		IconCentreShare = 0.46, -- the icon's middle sits this far down the slot
		LabelTextPx = 18, -- the word across the icon's lower edge (white, ink outline)
		-- The words' font: back on the kit's Fredoka One (designer, 2026-10-05, after looks at
		-- Montserrat Black and Builder Extended ExtraBold). Roblox's font family file and an
		-- Enum.FontWeight name, kept apart from the kit so a word font can be tried again. Measure
		-- is the Enum.Font name the words are measured with (TextService:GetTextSize takes no
		-- family file; pick one at least as wide as the family). (tune)
		LabelFont = {
			Family = "rbxasset://fonts/families/FredokaOne.json",
			Weight = "Regular", -- Fredoka One has one weight
			Measure = "FredokaOne",
		},
		ShortLabelTextPx = 14, -- never under the kit's minimum
		LabelCentreShare = 0.86, -- the word's middle sits this far down the tile
		-- The word's box may be this many tiles wide, overhanging both sides ("Inventory" is
		-- wider than a phone's tile at 14 px); the column moves right by the overhang.
		LabelMaxShare = 1.7,
		DotPx = 22, -- the red dot's height (it widens for "9+"), top right of the tile
		ShortDotPx = 20,
		DotTextPx = 14,
		DotInsetPx = 4, -- its centre sits this far inside the tile's top-right corner
		DotMax = 9, -- a count above this reads "9+"
		TimerPx = 22, -- the Shop's gold timer pill while an offer window is open
		ShortTimerPx = 20,
		TimerTextPx = 14,
		TimerOverTileShare = 0.3, -- this share of the pill sits over the tile, the rest past it
		DaysFromSeconds = 86400, -- from a day left the timer reads "6d 4h", else "23:59:12"
		-- Each tile's D-pad direction (UserInputService KeyCode names; Config has no Enum):
		-- in the hub the D-pad opens that menu (overnight assumption, 2026-09-28).
		-- GUI lane: down is Free Reward (the Daily Challenge when it is gone); left focuses the
		-- player list (PlayerList, no tile).
		PadKeys = {
			Shop = "DPadUp",
			Inventory = "DPadRight",
			FreeReward = "DPadDown",
			PlayerList = "DPadLeft",
		},
		-- Hover (or a gamepad resting on a tile): the kit's small sway plus sun rays fading in
		-- behind the icon (Kit.Motion.SunRays; designer, 2026-10-03: no hard shake).
		-- The Free Reward tile has its own gold rays turning behind it while it is up.
		FreeRaysShare = 2.2, -- its turning rays, of the tile
		FreeRaysTransparency = 0.1,
		GlyphPx = 26, -- the D-pad glyph on the tile's top-left corner while a gamepad is in use
		ShortGlyphPx = 22,
		GlyphInsetPx = 4, -- its centre sits this far inside the corner
		ZIndex = 6, -- in the HUD screen: over the world, under the popups
		TimerRefreshSeconds = 0.5, -- the timer pill's text is refreshed this often
	},
	-- Every full menu's frame (MenuFrame), laid out like the roadmap: on a phone the panel takes
	-- the whole screen with its title in Roblox's top bar row, right of Roblox's buttons; on a
	-- bigger screen a capped panel is centred under the bar. Sizes given as { a, b } run from a
	-- on the smallest panel (a phone) to b on a full-size one (DesignHeightPx tall).
	Frame = {
		MaxSizePx = { 920, 600 }, -- the panel's largest width and height (a computer)
		MarginPx = 4, -- the least gap between the panel and the screen's edges
		-- On a computer the panel is centred on the whole screen and never closer than this
		-- to the bottom edge, its shadow included (designer, 2026-10-03: menus touched the
		-- bottom on PC).
		BottomGapPx = 36,
		-- Shorter than this below Roblox's top bar is a phone: the panel takes the bar's row too.
		ShortScreenPx = 500,
		TopbarLeftFallbackPx = 212, -- where Roblox's buttons end, when Roblox does not say
		TouchMinPx = 44, -- the smallest touch target (UI_STYLE section 5)
		DesignHeightPx = 600, -- rows and text are full size at this panel height
		MinScale = 0.72, -- and shrink with a shorter panel, never below this share
		PaddingPx = { 6, 14 }, -- inside the panel
		GapPx = { 5, 8 }, -- between its rows
		HeaderPx = { 46, 64 }, -- the title row (on a phone: the top bar row's height)
		TitleScale = 1.1, -- the title is this much bigger than the kit's title size
		IconShare = 1.45, -- the header's icon, of the title's size
		CloseMaxPx = 48, -- the red X's largest size (its touch area is always 44)
		TabPx = { 44, 48 }, -- the tab buttons' height (never under TouchMinPx)
		TabTextPx = { 16, 20 },
		TabMinWidthPx = 84, -- a tab is at least this wide
		TabGapPx = { 6, 8 }, -- between two tabs
		-- A phone: the tabs share the title row when they fit there, which gives the pages
		-- about 50 px more height; otherwise (and on bigger screens) they get a row under it.
		TabsBesideTitle = true,
		ContentPadPx = { 6, 12 }, -- inside the sheet, round the pages
		MoneyPx = { 32, 38 }, -- the header's money pill (menus that show it)
		MoneyTextPx = { 16, 20 },
		MoneyIconShare = 1.25, -- its cash bundle, of the pill's height (pokes out)
		MoneyPlusShare = 1.05, -- the "+" on the pill's end (a menu that has one), of the pill's height
		MoneyPlusGapPx = 10, -- room between the "+" and the red X (the X's touch area)
		PlaceholderTextPx = 18, -- the "Loading..." line on an empty page
	},
	-- MenuFrame.scroller: a vertical list or grid of cards in a page.
	Scroll = {
		BarPx = 6, -- the scroll bar's thickness
		BarColor = { 150, 190, 235 }, -- light blue, like the sheet's edge but readable
		PadPx = 8, -- inside it: room for a hovered card's grow and gold outline
		GapPx = 8, -- between cards
		GridMinCellPx = 120, -- a grid fits as many columns as keep each card this wide
		GridAspect = 1.2, -- a grid card's height, of its width
	},
	-- MenuFrame.tile: a card like reference 03's reward tiles (icon, name, a count line).
	Card = {
		CornerPx = 12,
		StrokePx = 2, -- its outline...
		EdgeColor = { 178, 196, 224 }, -- ...pale, as the roadmap's reward tiles
		PadShare = 0.06, -- inside the card, of its height
		IconShare = 0.56, -- the icon (or art) box, of the height
		NameShare = 0.2, -- the name's line
		CountShare = 0.16, -- the count line ("x3")
		NameTextPx = 18,
		CountTextPx = 16,
		BadgeShare = 0.18, -- a pill in the top-right slot (NEW, Equipped), of the height
	},
	-- MenuFrame.confirm: the kit's dialog card, no dim (popups never darken the screen).
	Confirm = {
		WidthPx = 360,
		MarginPx = 12, -- from the parent's edges on a small screen
		PadPx = 14,
		GapPx = 10,
		ButtonPx = 44,
		TitleTextPx = 22,
		TextPx = 18,
		ZIndex = 60, -- over the page and its notices
	},
	-- MenuFrame.notice: a short line from the server's answer at the bottom of the panel.
	Notice = {
		Seconds = 2.6,
		HeightPx = 34,
		TextPx = 16,
		PadPx = 14, -- room each side of the words
		BottomPx = 12, -- above the panel's bottom edge
		MaxWidthPx = 460,
		ZIndex = 55,
	},
	-- The rarity dressing on a card (CueThumb.dress) and the cue thumbnails.
	Rarity = {
		StrokePx = 3, -- the rarity-coloured edge inside the card's ink outline
		StripShare = 0.07, -- a bar across the card's bottom, of its height
		StripInsetShare = 0.12, -- the bar is inset this share of the width at each end
		TintTransparency = 0.72, -- the colour wash at the card's bottom (1 = none)
		TintFromShare = 0.45, -- the wash starts this far down the card
		-- Mythic: a slow pastel shimmer over deep space with twinkling stars (UI_STYLE 4).
		ShimmerSeconds = 5, -- one sweep of the shimmer across the card
		ShimmerTransparency = 0.55,
		Stars = 5,
		StarPx = 3,
		TwinkleSeconds = 1.8,
		-- Secret: the dark fill with a slow red glow (overnight assumption, UI_STYLE 4's Open).
		GlowSeconds = 2.4, -- one breath of the glow
		GlowTransparency = { 0.15, 0.7 }, -- the edge's glow at its brightest and faintest
		GlowWashTransparency = { 0.45, 0.8 }, -- the red wash at the bottom, brightest and faintest
	},
	Thumb = {
		TipColor = { 34, 44, 74 }, -- a Look with no Tip: the Classic cue's blue tip
		CapShade = 0.6, -- a Look with no Cap: the wrap darkened to this share
		-- The silhouette image missing: every layer tinted this dark instead.
		SilhouetteColor = { 44, 48, 64 },
	},
	-- The top-centre banner (Banner): Money Party, unboxings, Reyes.
	Banner = {
		-- A Mythic or Secret pull's [GLOBAL] line (every server; designer 2026-10-05): Mythic in a
		-- pastel rainbow (letter by letter in chat, a gradient on the banner), Secret in red.
		GlobalMythic = {
			{ 255, 179, 186 },
			{ 255, 223, 186 },
			{ 255, 255, 186 },
			{ 186, 255, 201 },
			{ 186, 225, 255 },
			{ 210, 186, 255 },
		},
		GlobalSecret = { 255, 45, 60 },
		TopPx = 6, -- under Roblox's top bar (the HUD screen starts there)
		HeightPx = 38,
		ShortHeightPx = 32,
		TextPx = 20,
		ShortTextPx = 16,
		PadPx = 18, -- room each side of the words
		-- An ability roll's line: the ability's icon at the left end, PadPx in, IconGapPx
		-- before the words.
		IconPx = 30,
		ShortIconPx = 26,
		IconGapPx = 6,
		MaxWidthPx = 620,
		SideMarginPx = 10, -- never closer to the screen's sides
		BelowPx = 6, -- the gap under anything it moves below (the rank HUD, the status card)
		Seconds = 4.5, -- a one-off line shows this long
		MaxQueued = 6, -- more waiting than this drops the oldest
		-- A one-off line waiting this long (a match held it back) is dropped: old news.
		MaxAgeSeconds = 180,
		-- While a Money Party runs, its countdown takes turns with the one-off lines: this long
		-- between two lines, so a run of unboxings never hides the party (and waits, not lost).
		PartyTurnSeconds = 3,
		TickSeconds = 0.2, -- how often it looks at its queue and the party's countdown
		ZIndex = 29, -- over the status card (28), under the result screen (30)
	},
	-- ItemState's requests: a reply not back after this long counts as a network failure.
	RequestTimeoutSeconds = 15,
	-- A request waiting for another on the same remote (a Sell, a MarkSeen) looks this often.
	RequestPollSeconds = 0.05,
	-- Escape this soon after a text box stopped typing only ended the typing (the Rewards
	-- menu's code box): the menu stays open.
	EscapeAfterTypingSeconds = 0.1,
}

-- The Shop (ShopMenu with ShopParts; emptied for the GUI overhaul, designer 2026-10-04: the
-- frame and its jump buttons; the card sizes stay for the ult screen's buy buttons and the
-- page to come). Sizes given as { a, b } run from a on a phone-sized panel to b on a full one
-- (MenuFrame's geo.t, as Config.UI.Menu.Frame). Text never goes under Kit.Text.Min. Pixels and
-- seconds. (tune)
Config.UI.Shop = {
	TickSeconds = 0.25, -- the jump buttons' NEW badges are redrawn this often
	DaysFromSeconds = 86400, -- from a day left a countdown reads "6d 4h", else "2:59:12"
	ScrollPadPx = 8, -- inside a page's scroller: room for a hovered button's grow and outline
	ScrollBarPx = 6, -- its bar (always inset, so the cards never jump sideways)
	CardPadPx = { 8, 12 }, -- inside a card
	CardGapPx = { 8, 12 }, -- between cards, and between a card's buttons
	LineGapPx = { 2, 4 }, -- between the lines of words in a card
	CardCornerPx = 14,
	CardStrokePx = 2, -- the card's pale edge (Config.UI.Menu.Card.EdgeColor)
	ButtonPx = { 44, 48 }, -- a buy button's height (never under the 44 px touch target)
	ButtonTextPx = { 16, 20 },
	NameTextPx = { 18, 22 }, -- a card's name (white, ink outline)
	PriceTextPx = { 18, 22 }, -- a price beside its cash bundle, a pack's money
	OldPriceTextPx = { 14, 16 }, -- the price struck through during a sale
	LineTextPx = { 14, 16 }, -- the ink detail lines: the guarantee, "412 of 1,000 sold", timers
	PillPx = { 22, 26 }, -- small pills: "20% OFF", "+7%", "x3", "Pay for 9"
	PillTextPx = { 14, 16 },
	PillPadPx = 10, -- room each side of a pill's words
	CashShare = 1.3, -- the cash bundle beside a price, of the price's text size
	-- The one scrolling page (GUI lane, designer 2026-10-03), emptied for the GUI overhaul
	-- (designer, 2026-10-04): the frame, its background and the four jump buttons down the
	-- right side are all that is left; the sections come back with the new design. Sizes
	-- { a, b } run from a phone-sized panel (a) to a full one (b). (tune)
	-- The Gift Player popup (ShopGift): the purple gift square beside a Robux button opens it
	-- with the other players in this server (designer, 2026-10-06, back on the Grand Opening card).
	Gift = {
		WidthPx = { 320, 460 },
		RowPx = { 54, 70 }, -- a player's row: headshot, display name, @username, Gift
		RowGapPx = { 4, 6 },
		MaxRows = 5, -- more scroll
		NamePx = { 16, 21 },
		AtPx = { 12, 15 }, -- the @username
		AtColor = { 120, 128, 142 },
		ButtonWidthPx = { 84, 110 },
		Headshot = "rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",
	},
	Page = {
		-- The jump buttons, top to bottom (designer, 2026-10-04: Featured, Blocks, Money,
		-- Passes). Icons are Config.UI.Kit.Icons keys. Each will scroll to its sections once
		-- the page has them again.
		Jump = {
			{ Key = "Featured", Icon = "Deals", Sections = { "GrandOpening", "Limited" } },
			{ Key = "Blocks", Icon = "Inventory", Sections = { "Mystery", "Restock" } },
			{ Key = "Money", Icon = "Pack4", Sections = { "Money" } },
			{ Key = "Passes", Icon = "Passes", Sections = { "Offer", "Boosts", "RobloxPlus" } },
		},
		-- The 3D block icon (BlockIcon, used by the hotbar, the reward chips and the trade
		-- screen; the shop's cards will use it again).
		Block = {
			IconYawDegrees = 35, -- a still block icon's turn, so three faces show
			-- A kit icon per block kind, shown only if the block's 3D model is missing from the
			-- place (every kind has one since 2026-10-04); a missing model shows the gift box.
			Fallback = {
				Starter = "StarterPack",
				Gift = "Gift",
				Vip = "Vip", -- the VIP band's crown (never a model)
			},
			FallbackDefault = "Gift",
		},
		-- A block icon's little pop (BlockIcon.pop): it grows to this and settles.
		IconPop = { Scale = 1.12 },
		-- These jump buttons keep their red NEW badge all through the Grand Opening window
		-- (designer, 2026-10-04); every other badge clears once the Shop has been opened.
		PinnedBadges = { "Featured", "Blocks" },
		-- The white sheet goes on below the Grand Opening card (the page scrolls to it; the
		-- other groups' sections will be there): at least this tall, with its note.
		MoreBelowPx = 120,
		MoreBelowTextPx = 18,
		-- The first screen shows this much of what is under the card (the next section's
		-- header), so a player sees there is more and scrolls (designer, 2026-10-06).
		PeekPx = 30,
		RailWidthPx = { 66, 96 }, -- a jump button
		RailButtonPx = { 60, 86 },
		RailGapPx = { 6, 12 },
		RailTextPx = { 14, 18 },
		-- On a computer the buttons stand outside the panel's right edge when the screen has
		-- this much room there; otherwise (a phone) they take a column inside the page.
		RailOutsidePx = 14,
		JumpSeconds = 0.4, -- a jump's scroll
		-- Opened on a tab (the HUD's "+", a corner): a layout within this many seconds of
		-- opening jumps to the tab again, so a late geometry pass cannot leave it elsewhere.
		JumpSettleSeconds = 0.6,
	},
}

-- Motion tokens for lively screens (docs/prompts/SHOP_LIVELY_PROMPT.md section 3; the designer
-- approved these in the animatic, tools/gui/animatic, 2026-10-06). Stage plays every reveal from
-- them in code, per frame (no CanvasGroup; slow motion inside still frames, gate 1). Seconds.
Config.UI.Motion = {
	Stagger = 0.04, -- between pieces of one group (the tabs, the buttons, a card's insides)
	PopSeconds = 0.28, -- one piece's pop
	PopFrom = 0.6, -- a pop starts this big (UIScale)...
	PopPeak = 1.1, -- ...grows past full size to this...
	PopPeakAt = 0.6, -- ...at this share of the pop (Quad Out), then settles at 1 (Sine InOut)
	FadeSeconds = 0.1, -- a piece's fade in, alongside its pop
	UnrollSeconds = 0.2, -- a panel opening up and down from a thin bar
	UnrollOvershoot = 1.04, -- the panel's overshoot, of its height (Quart Out to it, then settle)
	UnrollPeakAt = 0.7, -- the share of the unroll where it peaks
	SlamFrom = 1.6, -- a slam (the lucky block) starts this big and drops in (Quad In)
	SlamBounce = 0.05, -- then bulges this much once as it lands
	SlamLandAt = 0.6, -- the share of the slam where it lands
	GrowSeconds = 0.15, -- a background opening from its centre, lines growing out (Quart Out)
	CloseSeconds = 0.15, -- a close: everything fades while the panel folds to a line, no stagger
	TabSeconds = 0.5, -- a tab switch: the new page's pieces stagger in over this, no unroll
	BurstFps = 30, -- a reveal's firework burst plays its 64 frames at this rate
	ReducedFadeSeconds = 0.2, -- with Reduce Motion: pieces only fade in, over this
	DropPx = 45, -- a drop (the crown, the flair) falls from this high (game px at 1x)
	BurstShare = 1.4, -- a reveal's firework burst, this many times its piece's size
	BarPx = 7, -- an unrolling panel starts as a bar this tall
}

-- The Shop's open, in order (docs/prompts/SHOP_LIVELY_PROMPT.md section 4; approved in the
-- animatic, 2026-10-06; the card's part twice as fast since gate 4). `At` is seconds from the
-- open's start; a longer or shorter open (StageMath.schedule) scales every `At`, not the lengths.
-- A step lists its pieces in `Ids`, each `Stagger` (x
-- Config.UI.Motion.Stagger) after the one before. `Kind` picks the curve; `Length` overrides the
-- kind's own length from Config.UI.Motion. `Badge` pops a NEW badge `BadgeAfter` s after its tab.
Config.UI.Shop.Open = {
	OpenSeconds = 0.91, -- the whole open, first piece to the flair landing (faster 2026-10-06, 2026-10-07)
	Steps = {
		{ Ids = { "Panel" }, Kind = "Unroll", At = 0 },
		{ Ids = { "Header" }, Kind = "Fade", At = 0.12, Length = 0.15 }, -- its pattern starts scrolling
		{ Ids = { "Basket", "Title", "Money", "Close" }, Kind = "Pop", At = 0.18 },
		{
			Ids = { "Tab1", "Tab2", "Tab3", "Tab4" },
			Kind = "Pop",
			At = 0.3,
			Stagger = 1.25,
			Badge = true,
			BadgeAfter = 0.08,
		},
		-- From here the Featured card, twice as fast as the animatic (designer, 2026-10-06: "after
		-- the white background frame appears the featured frame and everything with it needs to be
		-- faster"). It starts as the panel finishes unrolling, 0.16 s sooner than before (designer,
		-- 2026-10-07: too long a pause between the shop's frame opening and the hero card).
		{ Ids = { "Featured" }, Kind = "Pop", At = 0.18 }, -- "- FEATURED -"
		{ Ids = { "FeaturedLines" }, Kind = "Grow", At = 0.22 },
		{ Ids = { "Card" }, Kind = "Grow", At = 0.20 }, -- the card's background opens from its centre
		{ Ids = { "Block" }, Kind = "Slam", At = 0.25, Length = 0.16, Burst = "Gold" },
		{ Ids = { "NewTag" }, Kind = "Pop", At = 0.34 },
		{ Ids = { "CardTitle" }, Kind = "Pop", At = 0.28, Burst = "Purple" }, -- the title pops as one (designer)
		{ Ids = { "StarLeft", "StarRight" }, Kind = "Pop", At = 0.30 },
		{ Ids = { "Subtitle" }, Kind = "Fade", At = 0.32, Length = 0.12 },
		{ Ids = { "Beta" }, Kind = "Pop", At = 0.36, Burst = "Cyan" },
		{ Ids = { "BetaName", "BetaPills", "BetaOdds", "BetaCue" }, Kind = "Pop", At = 0.39 },
		{ Ids = { "Firework" }, Kind = "Pop", At = 0.43, Burst = "Pink" },
		{
			Ids = { "FireworkName", "FireworkPills", "FireworkOdds", "FireworkCue" },
			Kind = "Pop",
			At = 0.46,
		},
		{ Ids = { "Robux1", "Robux3", "Robux10" }, Kind = "Pop", At = 0.50 }, -- with their gift squares
		{ Ids = { "Counts" }, Kind = "Fade", At = 0.53, Length = 0.12 }, -- "1 block", "3 blocks", "10 blocks"
		{ Ids = { "Money1", "Money3", "Money10" }, Kind = "Pop", At = 0.55 },
		{ Ids = { "EndsIn" }, Kind = "Fade", At = 0.62, Length = 0.12 },
		{ Ids = { "Flair" }, Kind = "Drop", At = 0.66, Length = 0.25 }, -- the 8-ball lands on the frame
	},
	-- The optional flair, each a switch (all on in the approved animatic, gate 3):
	Poppers = true, -- party poppers burst from the card's bottom corners as it opens
	Streamers = true, -- gold confetti streamers drift down the card
	Twinkles = true, -- sparkles twinkle over the card
}

-- The lively GUI's effects library (docs/prompts/SHOP_LIVELY_PROMPT.md 7.2): flipbooks any
-- screen can play on one ImageLabel by stepping ImageRectOffset (drawn by tools/gui/effects.py,
-- the ribbons rendered by tools/gui/render_cues.py; each sheet's JSON beside it in
-- assets/ui/effects/). Image ids from tools/upload_manifest.json.
Config.UI.Effects = {
	-- A firework burst: a white flash cooling into its colour (baked; a tint cannot make white).
	Firework = {
		Gold = "rbxassetid://74896337141026",
		Pink = "rbxassetid://122426139419809",
		Cyan = "rbxassetid://140697632199442",
		Purple = "rbxassetid://122427114274964",
		Orange = "rbxassetid://90380179097737",
		Columns = 8,
		Rows = 8,
		FramePx = 128, -- square frames
		Frames = 64,
		Fps = 30, -- 64 frames: about 2.1 s, played once
	},
	-- A four-point twinkle that grows, turns a little and shrinks (white; tint it).
	Sparkle = {
		Image = "rbxassetid://101521209518869",
		Columns = 8,
		Rows = 8,
		FramePx = 128,
		Frames = 64,
		Fps = 30, -- loops
	},
	Rays = "rbxassetid://103944500004159", -- white rays (tint them), turned by Rotation
}

-- The Shop's Grand Opening card: its pictures (assets/ui/grand_opening, made by tools/gui; each
-- piece's source in tools/gui/grand_opening/pieces.json). Layout and timing come with the
-- animatic (gate 3).
Config.UI.GrandOpeningCard = {
	Images = {
		BallFar = "rbxassetid://133917866454159",
		BallMid = "rbxassetid://131006186802889",
		BallNear = "rbxassetid://106188181329401",
		BetaBg = "rbxassetid://79365265074624",
		BetaCallouts = "rbxassetid://100443049445710",
		BetaCode = "rbxassetid://84645552488171",
		BetaCodeTile = "rbxassetid://85815838814214", -- the strip at half width, twice: scrolls (512 period)
		BetaCue = "rbxassetid://119107559983869",
		BetaCueMask = "rbxassetid://133658662502990",
		BetaMote = "rbxassetid://97352339516537",
		BetaPanel1 = "rbxassetid://74810348586393",
		BetaPanel10 = "rbxassetid://134787497363227",
		BetaPanel2 = "rbxassetid://105979651588502",
		BetaPanel3 = "rbxassetid://124209830176541",
		BetaPanel4 = "rbxassetid://94361946702812",
		BetaPanel5 = "rbxassetid://71517930256519",
		BetaPanel6 = "rbxassetid://93956731802484",
		BetaPanel7 = "rbxassetid://90738951762522",
		BetaPanel8 = "rbxassetid://135281657731283",
		BetaPanel9 = "rbxassetid://123761250140819",
		BetaRing = "rbxassetid://105202280309632",
		Block = "rbxassetid://109891094531777",
		BlockGlow = "rbxassetid://81188257491328",
		BlockMask = "rbxassetid://73238073614819",
		-- The block with its crown baked on (tools/gui/crowned_block.py; designer, 2026-10-06:
		-- the crown is part of the block, breathing and shining with it) and its silhouette.
		BlockCrowned = "rbxassetid://77359537632274",
		BlockCrownedMask = "rbxassetid://118250533479699",
		BokehDisc = "rbxassetid://94800187656206",
		Confetti1 = "rbxassetid://76787298053979",
		Confetti2 = "rbxassetid://87754386394250",
		Confetti3 = "rbxassetid://107098604559953",
		Confetti4 = "rbxassetid://120125257618602",
		Confetti5 = "rbxassetid://104704902760777",
		Confetti6 = "rbxassetid://138178384118884",
		-- The same ribbons centred on clear 256 squares (the drift windows a square picture).
		ConfettiSquare = {
			"rbxassetid://73410510313552",
			"rbxassetid://130296626050021",
			"rbxassetid://103992410457197",
			"rbxassetid://137675637490855",
			"rbxassetid://118321190574872",
			"rbxassetid://126831229907440",
		},
		Crown = "rbxassetid://118495873177958",
		Flair8ball = "rbxassetid://132422184916082",
		FireworkBg = "rbxassetid://99479265638524",
		FireworkCue = "rbxassetid://130447726546401",
		FireworkCueMask = "rbxassetid://113286103070085",
		FireworkCueGlow = "rbxassetid://126476349740073", -- the Firework Cue's glow (white, tinted)
		-- Its gold ribbons, one still frame (designer, 2026-10-06: not the choppy loop; they
		-- pulse on their own: Loops.Ribbon*; tools/gui/firework_still.py).
		FireworkRibbons = "rbxassetid://103502864734313",
		Plate = "rbxassetid://93204646083675",
		StarLeft = "rbxassetid://81445661051193",
		StarRight = "rbxassetid://133224366351187",
	},
	-- The card's idle loops, as approved in the animatic (2026-10-06). Seconds; Lower effects
	-- halves the counts and rates; Reduce Motion stops floating and scrolling.
	Loops = {
		GlowPulseSeconds = 2.6, -- the block's gold glow pulses (transparency 0.05 to 0.45)
		RaysTurnPerSecond = 8.6, -- degrees: the block's rays turn slowly
		-- The block breathes this much over this; a little quicker than the animatic's 3.1 s
		-- (designer, 2026-10-06).
		BreatheScale = 0.015,
		BreatheSeconds = 2.3,
		BlockShineEvery = 4, -- a shine sweeps across the block (0.7 s)
		-- the NEW tag wiggles every 3 s: Config.UI.Kit.Motion.Shake.NewTag
		BallFloatPx = { 6, 9 }, -- the 8-balls float this far (x, y), the far ones slower
		CornerFireworkEvery = 3.2, -- the corner fireworks burst on a loop
		ConfettiFallPxPerSecond = 22, -- gold confetti drifts down, tumbling
		BokehCount = 14,
		TwinkleCount = 7,
		-- A shine across each Robux button, staggered 0.35 s; the money buttons never shine
		-- (designer, 2026-10-06: only the Robux options).
		ButtonShineEvery = 3,
		-- The Firework Cue's ribbons never move: they pulse, dimming to this transparency and
		-- glowing back to full, over this (designer, 2026-10-06).
		RibbonDimTransparency = 0.6,
		RibbonPulseSeconds = 2.4,
		BetaScanEvery = 3, -- the Beta card's scan line (1.2 s down the card)
		BetaPulseEvery = 1.5, -- the light pulse along the Beta cue (1 s)
		BetaGlitchEvery = 5, -- a quick glitch (0.14 s)
		BetaPanelWaveSeconds = 4, -- the blueprint panels dim and brighten in slow waves
		BetaRingTurnPerSecond = 14, -- degrees
		BetaCodePxPerSecond = 24, -- the glyph code scrolls
		FireworkBurstFps = 15, -- the Grand Opening card's mini fireworks play at half speed (designer)...
		FireworkBurstEvery = 1.5, -- ...and burst half as often, calm like the ribbons
	},
	-- Where everything sits, in the approved animatic's units (tools/gui/animatic, its card
	-- 1275 x 498; the card fills the page's width and every number scales with it). Places are
	-- a piece's centre { x, y } and its width (or { x, y, w, h } boxes from the top-left), card
	-- local. Text sizes are in the same units, never under MinTextPx on screen.
	Layout = {
		-- The card's size. It is scaled to fit the page whole, both ways, so nothing scrolls
		-- (designer, 2026-10-06: a phone shows the cue cards and every button at once).
		Card = { 1275, 520 },
		DesignHeightUnits = 498, -- the animatic's card height: the block's group and the background were placed on it
		CornerUnits = 28,
		RimUnits = 6, -- its pale rim
		Rim = { 191, 227, 255 },
		Featured = { Units = 40, MinPx = 18, TextUnits = 30, LineUnits = 150, LineGapUnits = 18 }, -- "- FEATURED -" over the card (tight: designer, 2026-10-06)
		-- This card's smallest text: under the kit's 16 so the whole card fits the smaller panel
		-- on a phone (designer, 2026-10-06). The small words' units give about 16 px on a computer.
		MinTextPx = 12,
		-- The block's group (box 0..364 x 0..498).
		Block = { 182, 262, 300 },
		Glow = { 182, 262, 560 },
		GlowTint = { 255, 190, 60 },
		GlowTransparency = { 0.05, 0.45 }, -- pulsing between these
		Rays = { 182, 262, 620 },
		RaysTint = { 255, 208, 96 },
		RaysTransparency = 0.65,
		-- The crowned block's picture (884 x 1024 px with a clear 24 px border, which the breathe
		-- zooms inside): its centre from the block's, width and height (crowned_block.py prints it).
		CrownedBlock = { 0.1, -25.2, 317.3, 367.6 },
		CrownedBlockPx = { 884, 1024, 24 }, -- its width, height and clear border in pixels
		NewTag = { 92, 66, 148, 60 }, -- centre, width, height
		NewTagDegrees = -8,
		NewTextUnits = 40,
		OddsBadge = { 300, 360, 44 }, -- the sky-blue "i" on the block (centre, size)
		EndsIn = { 182, 466 },
		EndsInUnits = 32,
		EndsInColor = { 70, 215, 255 },
		-- The title's group (box 470..1155 x 10..130).
		Title = { 812, 54 },
		TitleUnits = 70, -- bigger than the animatic's 58: 13b's title fills more of the card
		Subtitle = { 812, 112 },
		SubtitleUnits = 25,
		StarLeft = { 520, 66, 62 },
		StarRight = { 1104, 66, 62 },
		StarRockDegrees = 4.6,
		StarRockSeconds = 3.7,
		-- The two cue cards (box 360..1256 x 140..300).
		Beta = { 360, 140, 432, 160 },
		Firework = { 808, 140, 448, 160 },
		CueCardCornerUnits = 18,
		CueCardRimUnits = 6,
		BetaRim = { { 70, 215, 255 }, { 255, 79, 198 } }, -- cyan to magenta
		FireworkRim = { { 255, 79, 198 }, { 70, 215, 255 } },
		NameAt = { 18, 26 }, -- the card's name, from its top-left
		BetaNameUnits = 30,
		FireworkNameUnits = 26,
		BetaColors = { { 70, 215, 255 }, { 255, 106, 213 } }, -- "BETA" cyan, "CUE" pink
		FireworkColors = { { 255, 210, 58 }, { 255, 255, 255 } }, -- "GRAND OPENING" gold, "CUE" white
		PillsAt = { 18, 64 }, -- the UNIQUE pill's top-left
		PillUnits = { 104, 30 },
		PillTextUnits = 20,
		PillMinTextPx = 9, -- the pills may go smaller than MinTextPx: they sit over the cue (designer, 2026-10-06)
		PillGapUnits = 8,
		UniqueColor = { 226, 79, 216 },
		-- The odds chip, at the card's bottom-right on both cards (designer, 2026-10-06: the same
		-- place on each): its width and height.
		OddsChip = { 76, 32 },
		OddsTextUnits = 24,
		OddsColor = { 70, 215, 255 }, -- sky blue (Kit.Numbers' odds colour)
		CueShare = { 0.5, 0.68, 0.98 }, -- the cue's centre (shares of the card) and width: under the pills
		FireworkCueShare = { 0.5, 0.7, 0.98 },
		-- The ribbons' picture on the cue's box ({left, top, right, bottom} as shares of the cue
		-- render's canvas; tools/gui/firework_still.py prints it).
		FireworkRibbons = { 0.0573, 0.0328, 0.9822, 0.9750 },
		-- The Firework Cue's yellow glow (designer, 2026-10-06): tint, its transparency
		-- pulsing between these, and the pulse's length.
		FireworkGlow = {
			Tint = { 255, 205, 40 },
			Transparency = { 0.05, 0.35 },
			PulseSeconds = 2.4,
		},
		CueDegrees = -14,
		BetaPanels = { -- the blueprint panels: number, centre x, y (of a 1120 x 660 card), width, strength
			{ 1, 150, 170, 230, 0.5 },
			{ 2, 880, 120, 250, 0.45 },
			{ 3, 200, 520, 190, 0.45 },
			{ 5, 980, 520, 170, 0.5 },
			{ 6, 560, 120, 170, 0.35 },
			{ 7, 720, 560, 180, 0.4 },
			{ 8, 420, 590, 210, 0.4 },
			{ 9, 1010, 330, 160, 0.35 },
			{ 10, 110, 350, 150, 0.4 },
			{ 4, 640, 300, 200, 0.25 },
		},
		BetaMotes = 12,
		BetaRingShare = 0.9, -- of the card's height
		BetaCodeRows = { { 9, -1, 0.5 }, { -9, 1, 0.35 } }, -- y from the top (or bottom), direction, strength
		BetaCodeUnits = 20, -- the glyph strip's height
		-- The buttons (box 360..1256 x 310..498), a column per pack (designer, 2026-10-06): the
		-- purple gift square and the green Robux price ("129" and the old "147" struck through),
		-- the pack's "3 blocks" under them, then the gold money button (no "save" line: the
		-- room went to bigger buttons, the Robux ones a little bigger than the money ones).
		RowGreen = 318, -- clear of the cue cards above (designer, 2026-10-06)
		RowGreenUnits = 70,
		CountY = 409, -- the "1 block" words' centre, between the green and gold rows
		CountTextUnits = 32,
		RowGold = 428,
		RowGoldUnits = 70,
		ButtonX = 360,
		ButtonUnits = 288, -- a column's width
		ButtonGapUnits = 16,
		-- The gift square, smaller than the Robux row: clear of the cue cards and more room for
		-- the price (designer, 2026-10-06).
		GiftUnits = 58,
		GiftGapUnits = 8, -- between the gift square and the Robux button
		GreenTextUnits = 44,
		GoldTextUnits = 40,
		CashIconShare = 1.1, -- the gold buttons' cash bundle, big as in 13b (of the button's height)
		-- The background (scaled with the card when it restacks).
		-- The floating 8-balls: picture, centre, width, sway speed (radians a second; the far ones
		-- slower), and the picture's smaller side in pixels (the float windows a square).
		Balls = {
			{ Picture = "BallFar", At = { 700, 26 }, Units = 92, Speed = 0.25, ImagePx = 212 },
			{ Picture = "BallMid", At = { 1232, 468 }, Units = 112, Speed = 0.18, ImagePx = 188 },
			{ Picture = "BallNear", At = { 336, 486 }, Units = 92, Speed = 0.32, ImagePx = 170 },
		},
		-- The corner fireworks: colour (Config.UI.Effects.Firework), centre, width.
		Fireworks = {
			{ Colour = "Gold", At = { 120, 96 }, Units = 240 },
			{ Colour = "Pink", At = { 28, 260 }, Units = 170 },
			{ Colour = "Purple", At = { 560, 36 }, Units = 150 },
			{ Colour = "Orange", At = { 1208, 60 }, Units = 210 },
		},
		Confetti = 6,
		ConfettiUnits = 50,
		BokehTints = { { 90, 160, 255 }, { 70, 215, 255 }, { 160, 112, 255 } },
		Twinkle = { Units = 60, Tint = { 255, 243, 192 } },
		-- The odds pop-up beside the block: these on a computer, shrunk to fit a short card.
		OddsCardPx = 260, -- its width on screen
		OddsRowPx = 24,
		OddsTitlePx = 22,
	},
}

-- The lucky block opening's reel (LuckyOpening with BlockReel, LuckyResult and ReelFx; the
-- pull cutscenes in PullCutscene; docs/prompts/ECONOMY_UI_PROMPT.md section 11): a full-screen
-- overlay over the menus with the reel and the YOU GOT card. Everything is laid out at the
-- natural sizes below and scaled to fit (phone first: about 1 on a 750 x 361 phone, so its
-- text stays at these sizes). Pixels and seconds. (tune)
Config.UI.Reel = {
	-- B's priority over ContextActionPriority.High: over the menus' (+20) and the result
	-- screen's (+10), under a confirm dialog's (+30).
	BackPriorityAbove = 25,
	StageMinWidthPx = 600, -- the reel is fitted to at least this width (about five cards)
	TitleHeightPx = 40, -- the title row: the block's name
	TitlePx = 30,
	GapPx = 10, -- between the title, the reel and the hint
	HintHeightPx = 30, -- "Tap to skip" (the gamepad's A glyph and "Skip" on a gamepad)
	HintPx = 24,
	ReelSideMarginPx = 12, -- the reel's room from the stage's sides
	CardMarginPx = 12, -- the prize card's room in the fit (its glow and shadow)
	-- The rarity from which the card's effects show (Common ... Secret).
	ConfettiFrom = "Legendary",
	BigFrom = "Mythic", -- the long crawl, the building glow, the thicker edge
	ShimmerCycleSeconds = 2.4, -- Mythic's glow drifts once through its pastels in this long
	-- The reveal sting per rarity (Config.Audio.Ui keys).
	Stings = {
		Common = "RevealLow",
		Uncommon = "RevealLow",
		Rare = "RevealRare",
		Epic = "RevealEpic",
		Legendary = "RevealLegendary",
		Mythic = "RevealMythic",
		Secret = "RevealMythic",
		Default = "RevealLow",
	},
	-- The reel.
	Reel = {
		Cards = 40, -- cards on the strip
		PrizeSlot = 34, -- the prize's place: late, with cards after it for the window's right side
		-- Each cue's weight on the strip is its odds (BlockOdds.cueOdds) to this power: 1 = the true
		-- odds (a Standard strip is mostly grey and green); under 1 shows rarer cues more often.
		WeightPower = 1,
		CardWidthPx = 136, -- bigger cards with the cue's name and odds (GUI lane, 2026-10-03)
		CardHeightPx = 176,
		GapPx = 8, -- between two cards
		CardCornerPx = 12,
		CardStrokePx = 2.5, -- a card's ink outline
		ThumbShare = 0.8, -- the thumbnail, of the card's width...
		ThumbCentreShare = 0.37, -- ...its middle this far down the card
		NameTextPx = 15, -- the cue's name under it...
		NameTopShare = 0.63, -- ...this far down
		OddsTextPx = 15, -- its odds in its rarity's colour ("0.3%")...
		OddsTopShare = 0.75, -- ...this far down
		PadYPx = 10, -- above and below the cards inside the window
		CornerPx = 18, -- the window's corners (the strip is clipped inside their straight part)
		MinWidthPx = 300,
		MaxWidthPx = 1100, -- a wide screen shows about ten cards
		FadePx = 70, -- the soft white ends over the strip
		FadeEdgeTransparency = 0.05, -- at the window's very edge
		MarkerWidthPx = 5, -- the gold bar down the middle
		MarkerStrokePx = 2,
		MarkerTipPx = 18, -- the gold diamond on each end of the bar
		MarkerTipCornerPx = 3,
		MarkerOverPx = 2, -- the bar reaches this far past the window's top and bottom edges
		MarkerTintSeconds = 0.25, -- the marker turns the prize's colour as it settles
		Seconds = 4.2, -- one spin
		EasePower = 4, -- its slow-down: 1 - (1 - t)^power (higher: a longer crawl at the end)
		BigSeconds = 6, -- Mythic and Secret: a longer spin...
		BigEasePower = 5, -- ...and a longer crawl
		LandSpread = 0.8, -- it lands anywhere within this share of the prize card's half-width
		-- A skip (once per spin, designer 2026-10-04): the strip races on from where it is and
		-- brakes onto the prize over SkipSeconds, a blur that shows the roll was skipped. (tune)
		SkipSeconds = 0.7,
		SkipEasePower = 4, -- its brake: 1 - (1 - t)^power (higher: faster start, longer crawl)
		CentreSeconds = 0.4, -- then glides the prize to the marker's middle
		SettleHoldSeconds = 0.7, -- and holds this long before the prize card
		BigSettleHoldSeconds = 1.3,
		TickMinGapSeconds = 0.05, -- the tick per card, never faster than this
		BuildLeadSeconds = 1.8, -- Mythic and Secret: ReelBuild and the glow start this long before the stop
		BuildGlowShare = 0.6, -- how far the glow builds before it lands (then full)
		HaloSpreadPx = 22, -- the glow round the window, past each side
		HaloTransparency = 0.15, -- at its brightest
		BreathSeconds = 1.6, -- Secret's red glow breathes this slowly
		SecretBreathDepth = 0.5, -- and dims this much at its faintest
		PrizeStrokePx = 5, -- the prize card's edge in its colour once it lands
	},
}

-- The Rewards menu (RewardsMenu and its pages RewardsDaily, RewardsPlaytime, RewardsCodes;
-- RewardsFlyer; docs/prompts/ECONOMY_UI_PROMPT.md section 11).
-- Pixels and seconds. Pairs { a, b } run from a on a phone-sized panel to b on a full-size one,
-- like Config.UI.Menu.Frame's. Buttons drawn smaller than TouchPx keep a TouchPx touch area
-- (HudParts.setMinHit). The rewards themselves are Config.Daily's. (tune)
Config.UI.Rewards = {
	TouchPx = 44, -- the smallest touch area (UI_STYLE section 5)
	-- The Daily tab: the week's day tiles, Columns to a row (days 1-4, then 5, 6 and the last
	-- day spanning the rest of its row as the week's big prize), a line under them.
	Columns = 4,
	TileGapPx = { 6, 10 },
	TileMaxPx = { 150, 210 }, -- a tile's largest height (a tall page centres the rows)
	TilePadShare = 0.06, -- inside a tile, of its height
	DayTextPx = { 16, 20 }, -- "Day 1"
	WordsTextPx = { 14, 18 }, -- the reward's words ("2 Mystery Lucky Blocks")
	CountTextPx = { 14, 18 }, -- "x2" on a block's icon
	ClaimShare = 0.26, -- today's Claim button, of the tile's height...
	ClaimPx = { 30, 44 }, -- ...kept between these
	TodayStrokePx = 4, -- today's gold edge (the kit's selection gold)
	GlowSpreadPx = 12, -- the soft gold glow round today's tile reaches this far
	GlowTransparency = 0.3,
	ClaimedFade = 0.5, -- a claimed tile's picture and words fade this much (its check stays solid)
	LaterFade = 0.3, -- the days still to come are a little dimmer
	CheckShare = 0.3, -- the check on a claimed tile, of the tile's height...
	CheckMaxPx = 40, -- ...at most this big
	RaysTransparency = 0.55, -- faint gold rays behind the last day's prize
	IconOverlapShare = 0.2, -- two pictures in one reward overlap by this share of one
	FooterTextPx = { 14, 18 }, -- the line under the tiles (and under the gifts)
	-- The Playtime tab: one row per gift (picture, prize, time, bar, button), a line under them.
	GiftRowMaxPx = { 84, 112 },
	GiftGapPx = { 6, 10 },
	GiftPadPx = { 6, 10 },
	GiftTitlePx = { 16, 22 }, -- the prize's words
	GiftTimePx = { 14, 16 }, -- "4:12 / 10:00"
	BarPx = { 12, 18 }, -- the progress bar's height
	GiftButtonWidthPx = { 116, 150 },
	GiftButtonPx = { 44, 50 },
	-- The bars tick on the client between two RewardState snapshots (from its playSeconds and
	-- sentAt, the server's count, which lags the real time a little); a gift shows Claim this
	-- long after the tick says it is due (the server credits the time first, then decides).
	ReadyMarginSeconds = 2,
	TickSeconds = 0.25, -- the menu's countdowns and bars redraw this often while it is open
	-- The Codes tab: a title, the box and Redeem, the server's answer, a note; kept high on the
	-- page so a phone's keyboard never covers it.
	CodeWidthPx = { 440, 540 }, -- the column's largest width
	CodeBoxPx = { 44, 54 }, -- the box's and Redeem's height
	CodeTextPx = { 18, 22 }, -- the typed text
	CodeTitlePx = { 18, 24 },
	CodeAnswerPx = { 16, 20 }, -- "Code redeemed: +$500 and a Mystery Lucky Block"
	CodeNotePx = { 14, 16 },
	RedeemWidthPx = { 116, 150 },
	CodeGapPx = { 8, 12 },
	CodeStrokePx = 3, -- the box's ink outline (gold while selected or typing)
	-- A tab's red dot while something on it can be claimed.
	TabDotPx = 18,
	TabDotTextPx = 14,
	-- The Index banner at the top of the Daily tab while an Index row can be claimed (the
	-- Rewards tile's dot counts it, but only the Inventory's Index tab claims it): its line and
	-- Open Index. On a phone it takes the room of the line under the tiles, so they keep their
	-- size.
	IndexBannerPx = { 36, 48 }, -- the row's height
	IndexBannerPadPx = { 3, 5 }, -- inside the row, round the picture and the button
	IndexBannerTextPx = { 16, 20 }, -- "An Index reward is ready!"
	IndexBannerStrokePx = 3, -- its gold edge
	-- Rewards flying out of a claim (RewardsFlyer), over the menus: money into the money HUD
	-- (the CashFlyer's chips), each lucky block to the hotbar (or the Inventory tile).
	Fly = {
		DisplayOrderAbove = 5, -- its ScreenGui sits this far over a menu's
		BlockSizePx = 56, -- a block chip's picture (a computer)...
		ShortBlockSizePx = 44, -- ...and on a phone
		CountTextPx = 18, -- "x2" on it
		PopSeconds = 0.2, -- pops out at the button with a small overshoot
		PopFromScale = 0.3,
		HangSeconds = 0.3, -- hangs
		FlySeconds = 0.6, -- then flies to the tile
		EndScale = 0.45, -- shrinking to this size as it lands
		ArcLiftShare = 0.3, -- the curve rises this share of the distance...
		ArcMinLiftPx = 50, -- ...and at least this far
		StaggerSeconds = 0.15, -- several blocks follow each other
		AfterMoneySeconds = 0.12, -- the blocks start this long after the money
		ZIndex = 5,
	},
}

-- The trade screen (TradeMenu; GUI lane, designer 2026-10-03, D12): two big halves (you left,
-- them right) with a headshot, MaxSideItems slots each and a giant READY under each that turns
-- into 3-2-1; under them a strip of big cards: your items (tap to add) or theirs (tap to ask);
-- a big yellow banner when one side is worth far more. Pairs { a, b } are { a phone-sized
-- panel, a full one } (MenuFrame's t). (tune)
Config.UI.Trade = {
	SlotColumns = 4, -- each half's slots: 4 x 2 for 8
	SlotGapPx = { 4, 8 },
	HeadPx = { 28, 44 }, -- a half's header row (headshot, name, ready tick)
	NameTextPx = { 16, 22 },
	ReadyPx = { 34, 56 }, -- the giant READY button
	ReadyTextPx = { 20, 30 },
	HalfShare = 0.52, -- the halves' share of the page's height (the strip gets the rest)
	HalfGapPx = { 8, 16 }, -- between the two halves
	MaxWidthPx = 1100, -- the screen's content is never wider than this (centred)
	StripTabPx = { 28, 36 }, -- the strip's two tab buttons
	StripTabTextPx = { 13, 16 },
	CardWidthShare = 0.95, -- a strip card's width, of its height
	CardGapPx = { 6, 10 },
	CardTextPx = { 12, 15 },
	BannerPx = { 26, 36 }, -- the lopsided warning
	BannerTextPx = { 14, 20 },
	CountdownPx = { 70, 120 }, -- the 3-2-1 over the halves
	WantGlow = { 255, 214, 10 }, -- the ring round an item the other player asked for (gold)
	Thumbnail = "Size150x150", -- Enum.ThumbnailSize name for the headshots
	InviteWidthPx = 340, -- the invite card at the top middle
	InviteHeightPx = 118,
	InviteTopPx = 70,
	DoneSeconds = 2.5, -- "Trade done!" stays this long before the screen closes
}

-- The ult bar in a match (UltHud and UltBar; docs/prompts/ULTIMATES_PROMPT.md 5 and 7.1,
-- UI_STYLE section 11), the opponent's ult icon and the NO ULTS pills (MatchHUD, the result
-- screen). Pixels and seconds. Pairs { a, b } are { a phone on its side, a computer or tablet }
-- (the HUD screen under or over Multiplayer.Style.ShortHeight). (tune)
Config.UI.Ults = {
	ZIndex = 30, -- over the match HUD's lines, under the result screen and the money HUD
	-- The bar: bottom centre, the badge's ball at its left end, the pill to its right.
	WidthPx = { 220, 300 }, -- from the ball's left edge to the pill's right end
	MaxWidthShare = 0.4, -- never wider than this share of the screen
	PillPx = { 22, 28 }, -- the pill's height
	PillStrokePx = 3, -- its ink outline (the kit's button outline)
	BallPx = { 34, 42 }, -- the badge's 8 ball, bigger than the pill, over its left end
	PillFromBallShare = 0.45, -- the pill starts this share of the ball in from its left edge
	LabelPx = { 14, 16 }, -- ULTIMATE over the pill
	PercentPx = { 14, 18 }, -- the % in the pill ("READY! 100%" too)
	GapPx = { 4, 6 }, -- between the pill and ULTIMATE or the prompt over it
	BottomMarginPx = { 8, 12 }, -- the bar's lowest point this far above the screen's bottom
	CanvasPadPx = { 18, 24 }, -- room round the bar for sparkles (the fade's canvas)
	ReserveGapPx = 6, -- MatchHUD's bottom lines (ball in hand, wrong ball) sit this far above it
	-- Where the 8 ball sits in the badge art (UltBadge, 256 px): its centre and radius, as
	-- shares of the image, so the art's ball lands on the bar's ball spot.
	BadgeBall = { X = 148 / 256, Y = 152 / 256, Radius = 70 / 256 },
	-- The drawn badge while the art is "" (still uploading): the HUD 8 ball on a round splash.
	SplashShare = 1.3, -- the splash's size, of the ball
	SplashOffsetShare = 0.14, -- ...moved up and left by this share of the ball
	SplashBlue = { 90, 190, 255 },
	SplashGold = { 255, 196, 40 },
	-- Colours: the empty track, the blue fill, the gold ready fill (top to bottom).
	TrackColor = { 150, 158, 172 },
	TrackFade = { { 172, 180, 194 }, { 128, 137, 152 } },
	FillBlue = { { 140, 222, 255 }, { 36, 158, 250 } },
	FillGold = { { 255, 236, 120 }, { 255, 184, 20 } },
	GlossTransparency = 0.55, -- the white gloss over the fill's top half
	-- The moving shine: a white band along the fill, then a pause.
	ShineSeconds = 1.4,
	ShinePauseSeconds = 1.6,
	ShineDegrees = 20,
	ShineTransparency = 0.45,
	-- A gain: the % counts up, the fill's edge flashes, "+34" floats up (gold for a nice shot).
	CountSeconds = 0.6,
	FlashSeconds = 0.4,
	FlashWidthPx = { 6, 8 },
	FloatTextPx = { 18, 22 },
	FloatRisePx = { 22, 30 },
	FloatSeconds = 1.0,
	FloatFadeFrom = 0.6, -- it fades over the last part of its rise (share of FloatSeconds)
	GainStaggerSeconds = 0.35, -- between two gains of one shot (a ball, then its nice shot)
	-- Your turn: the bar slides up, then the gains stored in the opponent's turn animate as one.
	SlideSeconds = 0.35,
	SlidePx = { 50, 70 },
	HideSeconds = 0.18, -- sliding away when the turn passes
	StoredDelaySeconds = 0.15, -- after the slide, before the stored gains count up
	-- A change of the server's bar with no gain (the Studio QA hook) counts to it after this
	-- long: long enough for a gain sent with the snapshot to arrive and animate instead.
	SettleDelaySeconds = 0.35,
	-- While the cue is pulled back the whole HUD fades to 25% opacity.
	PullTransparency = 0.75,
	PullFadeSeconds = 0.15,
	-- Ready: a gold glow breathing behind the pill, sparkles, a shake every ~2 s.
	ReadyGlow = { 255, 208, 60 },
	GlowReachShare = 0.22, -- how far past the pill the glow reaches, of the pill's height
	GlowTransparency = { 0.45, 0.85 }, -- at its brightest, and its faintest
	GlowPulseSeconds = 1.2,
	SparkleColor = { 255, 244, 190 },
	SparkleEverySeconds = 0.28,
	SparkleSeconds = 0.7,
	SparklePx = { 12, 16 },
	SparkleReachPx = { 8, 12 }, -- how far off the pill they pop
	ShakeEverySeconds = 2,
	ShakeFirstSeconds = 0.6, -- the first shake comes this soon after it turns ready
	ShakeSeconds = 0.45,
	ShakeWobbles = 3, -- side to side this many times in one shake
	ShakeDegrees = 4,
	ShakePx = 3,
	-- The prompt over the ready bar: PRESS [G] TO ACTIVATE, TAP TO ACTIVATE, PRESS [X] ...
	PromptPx = { 22, 26 },
	PromptTextPx = { 14, 16 },
	KeycapShare = 0.78, -- the keycap or the controller glyph, of the prompt's height
	KeycapCornerPx = 5,
	PromptDimTransparency = 0.4, -- greyed while a press waits for the server
	KeyboardKey = "G", -- Enum.KeyCode names (Config is loaded by Lune: no Enum)
	GamepadKey = "ButtonX", -- free in a match (Input binds A, B, Y, L1, L2, the sticks, D-pad)
	PendingSeconds = 3, -- a press not answered in this long may be sent again
	-- Your armed ult: a pill in its rarity colour, "MAGNET: NEXT SHOT"; the opponent's is smaller.
	ArmedPx = { 26, 32 },
	ArmedTextPx = { 14, 18 },
	OpponentPx = { 22, 26 },
	OpponentTextPx = { 14, 16 },
	-- Each armed pill's ability icon (Config.Ults.Assets.Icons) on its left end, bigger than the
	-- pill like the bar's badge ball, hanging IconOutShare of itself past the pill's left end;
	-- the words start IconGapPx after it.
	ArmedIconPx = { 34, 42 },
	OpponentIconPx = { 30, 34 },
	IconOutShare = 0.2,
	IconGapPx = 2,
	-- A long pill ("Opponent's ability: GUANGDONG TIGER" on a phone) is never wider than this
	-- share of the screen; the fade's canvas widens to hold it, so it is never cut off.
	ArmedMaxWidthShare = 0.8,
	NoteTextPx = 14, -- "Coming soon" over a placeholder's pill
	-- A refusal (UltNotice), for a moment over the bar.
	NoticeTextPx = { 14, 18 },
	NoticeSeconds = 2.2,
	NoticeFadeSeconds = 0.4,
	-- The top bar (MatchHUD): a small ult icon on each opponent's portrait, lit when ready: the
	-- ability they have equipped (their UltEquipped attribute; a pretend player's is
	-- Config.Ults.Default), greyed and faded until ready, then in full colour on a soft gold
	-- glow (Kit.Art.SoftGlow, OpponentGlowShare of the icon, at OpponentGlowTransparency).
	OpponentIconShare = 0.6, -- of the portrait's size
	OpponentDimTransparency = 0.55, -- not ready: faded
	OpponentGlowShare = 1.6,
	OpponentGlowTransparency = 0.3,
	-- The NO ULTS pill: under the top bar's clock, and on the result screen under VS.
	NoUltsTextPx = 14,
	NoUltsPadPx = 8, -- room at each end of its words
	NoUltsColor = { 120, 128, 144 },
	ResultNoUltsHeightPx = 24,
}

-- The Inventory (InventoryMenu and its pages InventoryCues, InventoryIndex and
-- the cue card InventoryCard; docs/prompts/ECONOMY_UI_PROMPT.md section 11). Pixels and
-- seconds. Pairs { a, b } run from a on a phone-sized panel to b on a full-size one, like
-- Config.UI.Menu.Frame's. Buttons drawn smaller than 44 px keep a 44 px touch area
-- (HudParts.setMinHit). (tune)
Config.UI.Inventory = {
	-- The Cues tab: a strip (the sort button, Sell all duplicates) over a grid of cue cards,
	-- and the chosen cue's detail panel on the right.
	StripPx = { 36, 44 }, -- the strip's height: the sort button and Sell all
	StripTextPx = { 14, 16 }, -- their words
	-- The grid's orders, in the sort button's turn (each press moves to the next, round; the
	-- first is where it starts). Names in Strings.Menus.Inventory.SortOrders. The rarity
	-- filter chips were dropped for this (designer, 2026-09-28).
	SortOrders = { "RarestFirst", "CommonFirst", "MostCopies", "NameAZ" },
	SortMaxShare = 0.5, -- the sort button takes at most this share of the strip
	SellAllMaxShare = 0.5, -- Sell all duplicates takes at most this share of the strip
	GapPx = { 6, 10 }, -- between the strip, the grid and the detail panel
	DetailShare = 0.34, -- the detail panel's width, of the page's
	DetailMinPx = 210,
	DetailMaxPx = 320,
	-- A page at least this tall stacks the detail (the picture on top) beside both the strip
	-- and the grid; a shorter one (a phone) puts the picture left of the words and runs the
	-- strip across the whole page.
	StackFromPx = 360,
	CardMinPx = { 118, 150 }, -- a grid card at least this wide (bigger cards, GUI lane)
	CardGapPx = { 6, 8 }, -- between two cards
	CardAspect = 1.42, -- a card's height, of its width (room for the odds line, GUI lane)
	-- A cue card (InventoryCard, in the grid and the Index): the picture, the name on up to
	-- two lines under it, pills over its top corners.
	Card = {
		CornerPx = 12,
		StrokePx = 2, -- its pale outline (Config.UI.Menu.Card.EdgeColor)
		ChosenStrokePx = 4, -- the card whose details show: a thicker blue outline
		PadShare = 0.06, -- inside the card, of its width
		ArtShare = 0.55, -- the picture's size, of the card's height
		NameTextPx = 18, -- the name (it wraps rather than shrinks; 14 read too small, 2026-10-03)
		NameLines = 2, -- lines the name may wrap to
		BottomShare = 0.1, -- room kept at the card's bottom for the rarity strip
		PillPx = 24, -- NEW, Equipped, x3 and #412: their height
		PillTextPx = 17,
		PillPadPx = 6, -- room each side of a pill's word
		LockPx = 20, -- the padlock on Exclusive and Unique cues
		InsetPx = 3, -- the pills and the lock sit this far inside the card's corners
		EquipGapPx = 4, -- the Equipped pill's bottom sits this far above the name
		UnknownShare = 0.62, -- a never-owned cue's "?" in the Index, of the card's picture room
	},
	-- The detail panel (the chosen cue).
	Detail = {
		PadPx = { 8, 12 },
		GapPx = { 6, 8 },
		ArtPx = { 76, 128 }, -- the picture: left of the words on a phone, on top on a computer
		NameTextPx = { 22, 28 },
		RarityTextPx = { 18, 22 },
		LineTextPx = { 17, 20 }, -- "4.2% chance", "You own 3", "Can't be sold"
		ButtonPx = { 40, 48 }, -- Equip, Sell, Sell duplicates
		ButtonTextPx = { 17, 20 },
		LockPx = { 18, 22 }, -- the padlock before "Can't be sold"
		ThumbShare = 0.86, -- the cue's thumbnail, of the picture's box
	},
	-- The Cues tab (GUI lane, 2026-10-03; the case strip went with the cases, 2026-10-04): the
	-- cue grid, and the chosen cue as a big card over the page (ref 07's size).
	Items = {
		BigCardMaxWidthPx = 460, -- the chosen cue's card
		BigArtShare = 0.42, -- its picture, of the card's height at most
		BigArtMinPx = 96, -- the picture never smaller (the card scrolls past this)
		-- A landscape space (wider than tall by this) lays the card out side by side: the
		-- picture fills the left, the words and buttons stand beside it (phones, short PCs).
		BigWideRatio = 1.5,
		BigWideMaxWidthPx = 760, -- the side-by-side card's width at most
		BigWideArtMaxPx = 400, -- its picture's side at most
		BigWideArtShare = 0.5, -- and at most this share of the card's width
		ChooserPx = { 40, 48 }, -- the count chooser's row: - 3 + Max
		ShimmerSeconds = 2.4, -- a rarity card's light sweeping across it
		ShimmerFromRarity = "Uncommon", -- cards of this rarity and up shimmer
		SparkleFromRarity = "Epic", -- and from this one also sparkle
	},
	CardOddsTextPx = 18, -- a cue card's "4.2% chance" line (bigger, and the exist count gone, 2026-10-03)
	-- The Index's turning 3D cue (CueViewport, in the Index's detail panel; designer,
	-- 2026-09-28): the game's own cue in a ViewportFrame, thicker so it reads small, turning
	-- round the upright axis. A cue not found yet is one near-black colour.
	Viewport = {
		-- The stick's diameter times this (a real cue is too thin to read); 1.6 keeps the look
		-- it had at 2.6 before the cue grew 1.6x (2026-10-01).
		Thickness = 1.6,
		TiltDegrees = 45, -- the stick's lean from level (tip up and to the right)
		StartDegrees = 25, -- where the turn starts when a cue is shown
		SpinDegreesPerSecond = 55, -- about one turn in 6.5 s
		FieldOfView = 30, -- the camera's (narrow: little perspective stretch)
		FillShare = 0.86, -- the stick's longer half-extent, of the picture's half-size
		SilhouetteColor = { 22, 24, 34 }, -- a cue not found yet (near-black, lit a little)
		Ambient = { 150, 150, 160 }, -- the viewport's light
		LightColor = { 255, 255, 255 },
		LightDirection = { -1, -1, -1.5 }, -- from the top left, in front
	},
	-- The Index tab: the titles and the rarity rows (a card per row, its cues as small cells)
	-- on the left, the chosen cue's detail panel on the right (IndexDetail*).
	IndexDetailShare = 0.34, -- the panel's width, of the page's
	IndexDetailMinPx = 180,
	IndexDetailMaxPx = 300,
	IndexViewShare = 0.5, -- a phone's turning cue at most this share of the page's height
	CellMinPx = { 84, 100 }, -- an Index cell at least this wide (as many columns as fit)
	CellAspect = 1.45, -- its height, of its width
	CellNameLines = 3, -- a narrow cell's name may wrap to this many lines (never under 14 px)
	CellGapPx = { 6, 8 },
	SectionPadPx = { 8, 12 }, -- inside a row's card
	HeaderPx = { 36, 44 }, -- a row's header line: its name, "5 / 7", the reward, Claim
	HeaderTextPx = { 18, 22 },
	ProgressTextPx = { 14, 16 },
	RewardPx = { 26, 30 }, -- a reward chip's height (the money, the title)
	RewardTextPx = { 14, 16 },
	RewardIconShare = 1.1, -- the money chip's cash, of the chip's height...
	RewardIconOverShare = 0.25, -- ...this share of it past the chip's left end
	ClaimWidthPx = { 90, 120 },
	TitlePillPx = { 28, 32 }, -- an earned title at the top
	TitleTextPx = { 14, 16 },
	-- The red dots on the tab buttons: the NEW count on Cues, "!" on
	-- Index while a row can be claimed.
	TabDotPx = 20,
	TabDotTextPx = 14,
	TabDotMax = 9, -- more than this reads "9+"
	MarkSeenRetrySeconds = 1.5, -- a MarkSeen turned away (Busy, TooFast) is tried once more after this
}

-- The ult cutscene (src/client/UltCutscene.luau; ULTIMATES_PROMPT 7.2, reference 10): a tilted
-- manga panel for everyone in the match, Config.Ults.CutsceneSeconds long. Shares are of the
-- screen (or of the panel where it says so), so it fits every screen from a 750 x 361 phone to
-- 1920 x 1080. Times are seconds from the activation (armed.at). (tune)
Config.UI.UltCutscene = {
	DisplayOrderAbove = 8, -- its ScreenGui sits this far over the HUD's (the menus sit at +10)
	-- GUI lane (step 13): the words jolt and the name flares gold this long after they appear.
	WordsJoltSeconds = 0.12,
	-- The arming callback still fires for a client that hears of the activation this late
	-- after readyAt (a slow snapshot); later than that, the armed look just appears.
	ArmGraceSeconds = 0.3,
	-- The panel: a band HeightShare of the screen tall, WidthShare of its width plus its own
	-- height wide (so its ends never show), tilted, centred at CenterYShare.
	HeightShare = 0.4,
	WidthShare = 1.35,
	TiltDegrees = -8, -- rising to the right, like reference 10
	CenterYShare = 0.5,
	BorderShare = 0.05, -- the thick white border, of the panel's height...
	BorderMinPx = 5, -- ...at least this
	InkShare = 0.015, -- the ink outline round it, of the panel's height...
	InkMinPx = 3, -- ...at least this
	InnerInkShare = 0.5, -- the thinner ink line round the picture, of the outer one
	-- The picture is the kit's white with the rarity colour round it (the designer, 2026-09-28:
	-- no dark swirl): a line RarityEdgeShare of the outer ink thick in the ult's rarity colour,
	-- and a soft glow of it behind the avatar, lightened by GlowWhiteShare toward white.
	InnerColor = { 255, 255, 255 },
	RarityEdgeShare = 2.2,
	GlowWhiteShare = 0.72,
	BackdropArt = false, -- true brings back the dark swirl art below
	AvatarFadeShare = 0.35, -- the bottom of the avatar's window fading into the glow
	-- The backdrop (Config.UI.Kit.Art.UltBackdrop, a 1024 square white swirl on near-black),
	-- tinted in the ult's rarity colour lightened by BackdropWhiteShare, cropped from the 3:1
	-- strip (rows StripRows) round the calm eye (EyePx), which sits behind the avatar.
	ArtSizePx = 1024,
	StripRows = { 341, 683 },
	EyePx = { 420, 512 },
	BackdropWhiteShare = 0.2,
	BackdropCropWidthPx = 900, -- the crop's width in art pixels (less than 1024 leaves room to drift)
	BackdropDriftPxPerSecond = 60, -- art pixels a second, sliding right
	BackdropZoomShare = 0.08, -- the crop closes in this much over the push-in
	-- Speed lines behind the avatar, racing right to left.
	SpeedLines = 7,
	SpeedLineHeightShare = { 0.006, 0.016 }, -- thickness, of the picture's height
	SpeedLineLengthShare = { 0.15, 0.4 }, -- length, of the screen's width
	SpeedLineScreensPerSecond = 2.4, -- speed, in screen widths a second
	SpeedLineStaggerSeconds = 0.45, -- they set off spread over this
	SpeedLineTransparency = 0.35,
	SpeedLineWhiteShare = 0.35, -- in the rarity colour, lightened this much (white on the swirl)
	-- The avatar: a clone of the activator's character in its rest pose, upper body (waist to
	-- the top of the head) filling FrameMargin of the picture's height, at AvatarScreenX across
	-- the screen, turned AvatarYawDegrees toward the words. A pretend player is an ink silhouette.
	-- A ViewportFrame neither rotates nor clips under a tilted frame, so the avatar stands in its
	-- own upright window, AvatarWindowShare of the picture's height wide and as tall as fits
	-- inside the tilted band there. Upper body = waist to the top of the head or its hat, the hat
	-- counted up to HatMaxHeads head heights above the head.
	AvatarScreenX = 0.4,
	AvatarWindowShare = 1.6,
	HatMaxHeads = 2.5,
	AvatarYawDegrees = 20,
	FieldOfView = 30,
	FrameMargin = 1.1,
	FocusUpShare = -0.04, -- the window's bottom sits this share of the upper body above the waist (-: below)
	Ambient = { 150, 150, 170 },
	LightColor = { 255, 244, 228 },
	LightDirection = { -0.5, -1, 0.7 }, -- from the front left, above
	SilhouetteColor = { 27, 32, 51 }, -- the ink
	-- The words: "ULTIMATE" over the top edge at the left, the ult's name over the bottom edge
	-- at the right, Fredoka One, white, thick ink outlines. EdgeAnchor is how much of a word
	-- sits outside the panel's edge.
	TitleHeightShare = 0.2, -- of the panel's height
	TitleWidthShare = 0.4, -- its box, of the screen's width (the words shrink to fit)
	TitleInsetShare = 0.06, -- in from the screen's left edge
	NameHeightShare = 0.22,
	NameWidthShare = 0.55,
	NameInsetShare = 0.06, -- in from the screen's right edge
	EdgeAnchor = 0.6,
	TextMinPx = 22,
	OutlineShare = 0.12, -- a big word's outline, of its size (thicker than the kit's tenth)
	OutlineMinPx = 3,
	-- The ability's icon (Config.Ults.Assets.Icons; ABILITIES_PROMPT 5.1), stamped into the band
	-- beside the avatar, tilted with it: its centre IconFromAvatarShare of the avatar window's
	-- width right of the avatar's centre, IconYShare down the band, IconShare of the picture's
	-- height big (clear of "ABILITY" top left and the name bottom right). At IconDelaySeconds
	-- (the slam landing) it pops from IconFromScale to 1 over IconPopSeconds with a burst of
	-- the rarity colour behind it (Kit.Art.SoftGlow growing from IconGlowFromScale to
	-- IconGlowToScale of the icon over IconGlowSeconds, fading out from IconGlowTransparency,
	-- lightened IconGlowWhiteShare toward white), then stays until the band squeezes, fading
	-- with the words. It adds no time: the panel still ends by Config.Ults.CutsceneSeconds.
	IconShare = 0.72,
	IconFromAvatarShare = 0.55,
	IconYShare = 0.47, -- a little above the middle, clear of the name on the bottom edge
	IconDelaySeconds = 0.1,
	IconPopSeconds = 0.16,
	IconFromScale = 1.3,
	IconGlowSeconds = 0.35,
	IconGlowFromScale = 0.8,
	IconGlowToScale = 2.1,
	IconGlowTransparency = 0.1,
	IconGlowWhiteShare = 0.15,
	-- The timeline. 0 to SlamSeconds: the panel slams in from the right along its tilt, a little
	-- large, overshooting as it lands; the words pop in after TextDelaySeconds. PushStart to
	-- PushEnd: the camera eases in to PushInScale of its distance. From ShrinkStart: the band
	-- squeezes to a LineHeightPx line, then the line snaps shut over SnapSeconds. The end is
	-- never later than Config.Ults.CutsceneSeconds.
	SlamSeconds = 0.12,
	SlamFromScale = 1.12,
	SlideFromShare = 0.6, -- of the screen's width
	TextDelaySeconds = 0.03,
	TextPopSeconds = 0.14,
	TextFromScale = 1.6,
	PushStartSeconds = 0.08,
	PushEndSeconds = 0.6,
	PushInScale = 0.8,
	ShrinkStartSeconds = 0.58,
	ShrinkSeconds = 0.14,
	SnapSeconds = 0.07,
	LineHeightPx = 4,
}

-- Magnet's look and sound (src/client/MagnetFx.luau; ABILITIES_PROMPT 7.1). Studs unless named;
-- the ball's radius is Config.Balls.RenderRadiusInches (about 0.19 studs). The field-line
-- meshes are Config.Ults.Assets.Models.MagnetField (their colours are baked in the texture:
-- only their transparency is set here). (tune)
-- The power bar dressed for an armed Legendary or Mythic ability (the designer, 2026-09-30;
-- src/client/PowerCue.luau, art from tools/gen_power_skins.py): while the local shooter's own
-- armed ability has a row here, the fill wears it instead of green-to-red and the rainbow;
-- the cue in the bar, the label and the controls stay as they are. A row (every part
-- optional, a data row per ability, no code):
--   Fill = { top, bottom }: the fill's colours, top to bottom.
--   Tile = { Image, Px, DriftPxPerSecond }: an image tiled Px square over the fill, drifting
--     down the bar (faster with the pull: MinShare of the drift at no pull, all of it at full).
--   Flipbook = { Image, Cols, Rows, FramePx = { w, h }, Fps, MinFps, MinShare }: frames over
--     the whole bar (the fill shows them as it grows), from MinFps to Fps and from MinShare
--     of full opacity to all of it as the pull grows.
--   Emblem = { Image, WidthShare, SpinDegPerSecond, MinSpinDegPerSecond }: an image riding
--     the fill's leading (bottom) edge, WidthShare of the bar wide, turning faster with the
--     pull.
--   Glow = the colour the bar's outline turns as the pull grows (all of it at 100%).
-- (tune by eye)
Config.UI.PowerSkinMinShare = 0.3 -- a Tile's drift and a Flipbook's opacity floor at no pull
Config.UI.PowerSkins = {
	-- Black lightning with a red glow, crackling harder and faster as you pull.
	BlackFlash = {
		Fill = { { 12, 0, 0 }, { 70, 0, 8 } },
		Flipbook = {
			Image = "rbxassetid://105408795030918",
			Cols = 4,
			Rows = 4,
			FramePx = { 128, 256 },
			Fps = 24,
			MinFps = 6,
			MinShare = 0.35,
		},
		Glow = { 255, 40, 50 },
	},
	-- Green, with the steel ball riding the fill's edge, spinning faster as you pull.
	SteelBall = {
		Fill = { { 90, 225, 120 }, { 20, 130, 60 } },
		Emblem = {
			Image = "rbxassetid://85376916012292",
			WidthShare = 0.95,
			SpinDegPerSecond = 1080,
			MinSpinDegPerSecond = 90,
		},
		Glow = { 140, 255, 170 },
	},
	-- Deep space drifting down the bar, the black hole turning at the fill's edge.
	BlackHole = {
		Fill = { { 255, 255, 255 }, { 255, 255, 255 } },
		Tile = { Image = "rbxassetid://86393046488401", Px = 64, DriftPxPerSecond = 30 },
		Emblem = {
			Image = "rbxassetid://109042133398887",
			WidthShare = 1.35,
			SpinDegPerSecond = 540,
			MinSpinDegPerSecond = 45,
		},
		Glow = { 190, 110, 255 },
	},
	-- Tiger skin, drifting slowly.
	GuangdongTiger = {
		Fill = { { 255, 255, 255 }, { 255, 255, 255 } },
		Tile = { Image = "rbxassetid://91211346868786", Px = 72, DriftPxPerSecond = 20 },
		Glow = { 255, 150, 40 },
	},
} :: { [string]: any }

Config.UI.MagnetFx = {
	FieldColor = { 160, 210, 255 }, -- the fallback's faint arcs round the armed cue ball
	GlowColor = { 70, 160, 255 }, -- the pull: the ball's glow, the vortex, the fallback ring
	SparkColor = { 190, 230, 255 },
	BeamSegments = 12, -- a Beam's smoothness
	-- The opponent's balls are pulled at Config.Ults.Shared.OpponentFactor: their burst,
	-- lines, pocket fan and shockwave keep this share of their opacity (and their charge's zap
	-- and sparks this share of theirs), so theirs reads weaker.
	OpponentOpacityShare = 0.5,
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The field-line meshes lie this far over the cloth (their underside).
	MeshLiftInches = 0.08,
	-- These pieces drop their baked texture for this flat colour: the reference's pale blue
	-- (#7BA3D6) washed out to near white on the lit green cloth, so a deeper, saturated blue of
	-- the same hue (the look check, 2026-09-29). PoleCaps is not drawn (2026-09-30).
	FlatPieces = { "FieldArcs", "FieldFlares", "FieldRing", "Chevron" },
	FieldMeshColor = { 45, 115, 240 },
	-- Armed: the cue ball as a dipole, nothing drawn on the ball itself (the designer,
	-- 2026-09-30: the red and blue caps and rings are gone). Its N turns after the shooter's aim
	-- (the aim stream) with this time constant; with no aim heard it turns once every
	-- ArcTurnSeconds.
	PoleEaseSeconds = 0.12,
	-- The arcs flat round it (three nested loops each side, N to S): scaled so the inner loops
	-- pass this many ball radii from its centre (the outer ones reach about 2.7x as far).
	ArcsInnerRadiusBalls = 1.35,
	ArcsTransparency = 0.15,
	-- Chevrons flowing along every loop toward S: this many per loop, one lap each this long,
	-- each loop's this share of a lap behind the last (so they don't march in step), each
	-- this long (of the arcs' scale; the mesh's own arrowheads are 0.16), fading in and out
	-- over this share of the loop at each foot.
	ChevronsPerLoop = 2,
	ChevronLapSeconds = 1.2,
	ChevronStagger = 0.37,
	ChevronShare = 0.16,
	ChevronFadeShare = 0.15,
	ChevronTransparency = 0.05,
	-- The arming snap: the fallback arcs start this many times wider and snap in; the arcs
	-- start this small and pop out to size.
	SnapSeconds = 0.35,
	SnapFromScale = 2.6,
	MeshSnapFromScale = 0.2,
	LookFadeSeconds = 0.25, -- the armed look fades in at readyAt (and out if the shot ends first)
	-- The hand-off (2026-09-30): the armed look rides the rolling cue ball until its first hit,
	-- then field lines run from the cue ball into the ball it hit for HandoffSeconds, arrows
	-- flowing into it, while the cue ball's look goes in HandoffLookFadeSeconds and the hit
	-- ball charges (the burst below). (tune)
	HandoffSeconds = 0.45,
	HandoffLookFadeSeconds = 0.12,
	HandoffSparkCount = 14, -- sparks at the contact
	-- The fallback field (no model yet): a dipole across the ball (N along the aim), a line
	-- leaving each pole ArcSpreadDegrees off the axis and looping ArcReachStuds out, one line
	-- per angle round the axis (0 = flat to one side, 90 = straight over the top).
	ArcAngles = { 25, 90, 155 },
	ArcSpreadDegrees = 55,
	ArcReachStuds = 0.45,
	ArcWidthStuds = 0.03,
	ArcTurnSeconds = 5,
	ArcTransparency = { 0.55, 0.95 }, -- each flicker picks between these (faint)
	ArcFlickerSeconds = 0.07,
	ArcTextureLengthStuds = 0.35, -- Config.UI.Kit.Art.FieldLines along the arcs
	ArcTextureSpeed = 1,
	-- A pull: three field lines on the cloth from the ball to the pocket (one straight, two
	-- bowing out either side), Beams tiled with Config.Ults.Assets.Images.MagnetFieldBeam in
	-- the reference's blue (#7BA3D6). Their opacity is LineMinShare at the weakest pull,
	-- rising to full at the strongest.
	LineColor = { 45, 115, 240 }, -- FieldMeshColor, deeper than the reference for the cloth
	LineWidthStuds = 0.22, -- flat on the cloth, seen at a low angle: wide enough to read
	LineTextureLengthStuds = 0.88, -- one arrow this often (4x the width: the tile is 4:1)
	-- The arrows' flow: positive runs from the ball (the beam's start) toward the pocket.
	-- Flip the sign if Studio shows it flowing the wrong way.
	LineTextureSpeed = 1.5,
	LineLightEmission = 0, -- any glow washes the blue out to white on the lit cloth
	LineTransparency = 0, -- the straight line
	SideLineTransparency = 0.15, -- the two bowing out
	LineBowShare = 0.3, -- how far the side lines bow, of the ball-to-pocket distance
	LineMinShare = 0.6, -- (0.35 left the lines nearly invisible on a light pull: the look check)
	LineLiftInches = 0.1, -- over the cloth
	-- false: the lines lie flat on the cloth like the reference's diagram (each end's
	-- attachment faces up). true: they face the camera (switch if Studio shows the flat ones
	-- standing on edge or too thin from the shooter's camera).
	LinesFaceCamera = false,
	-- The drop: the lines' ball end snaps into the pocket over this long...
	SnapInSeconds = 0.12,
	-- ...and a FieldRing shockwave spreads from the pocket, from this to this many pocket
	-- radii over WaveSeconds, fading, turning WaveSpinDegrees as it goes. It rides this high
	-- over the cloth: at the cloth the rails hid most of a ring centred on a pocket (the look
	-- check, 2026-09-29), so it spreads just over the rail tops (RailTopInches 2.08).
	WaveSeconds = 0.55,
	WaveLiftInches = 2.3,
	WaveFromRadii = 0.6,
	WaveToRadii = 4.5,
	WaveTransparency = 0.05,
	WaveSpinDegrees = 50,
	-- The pocket's fan of flared lines (FieldFlares) at the middle of its mouth, fanning out
	-- over the table: scaled to this many pocket radii (its lines run from about 0.15 to 1.4
	-- of that out of the mouth), breathing with PocketPulseScale.
	PocketFlareScale = 1.6,
	PocketFlareTransparency = 0.1,
	-- A charging ball's burst: the arcs and a fan out of each pole, flat on the cloth, growing
	-- from BurstFromScale to BurstToScale of the ball-fitted size (ArcsInnerRadiusBalls) over
	-- BurstSeconds while fading; the fans' lines start this far out (of the arcs' scale; the
	-- inner loops' feet are at about 0.78).
	BurstSeconds = 0.35,
	BurstFromScale = 0.4,
	BurstToScale = 2.2,
	BurstTransparency = 0.05,
	BurstFlareStart = 0.8,
	PullRiseSeconds = 0.08, -- a pull's effects come up this fast...
	-- ...and let go this slowly: a pull lasts only while the ball crosses the mouth, so the look
	-- lingers a moment to be seen (polish, 2026-09-28: 0.2 barely showed from the player's camera)
	PullFadeSeconds = 0.5,
	PitchEaseSeconds = 0.25, -- the hum's pitch rising and falling with the strongest pull
	-- The pulled ball's glow: a PointLight and (with Config.UI.Kit.Art.SoftGlow) a soft halo.
	GlowRangeStuds = 2.5,
	GlowBrightness = 3,
	GlowBallWidths = 3.5, -- the halo's size
	GlowTransparency = 0.15,
	GlowPulseShare = 0.2,
	GlowPulseSeconds = 0.3,
	-- The fallback pocket ring on the cloth (Config.UI.Kit.Art.RingGlow; a beam circle without
	-- it), when the model has not arrived.
	PocketRingScale = 2, -- of the pocket's opening
	PocketPulseSeconds = 0.5,
	PocketPulseScale = 0.15, -- it breathes this much bigger and smaller
	PocketPulseFade = 0.35, -- and this much fainter at its biggest
	PocketTransparency = 0.05,
	PocketLiftInches = 0.1, -- above the cloth
	PocketPixelsPerStud = 200,
	PocketBrightness = 2,
	PocketRingWidthStuds = 0.05,
	-- The drop: the clunk-zap and a burst of sparks. Few, long-lived sparks hold up at low
	-- graphics (STUDIO_NOTES).
	SparkCount = 14,
	ArmSparkCount = 8, -- at the arming snap, round the cue ball
	SparkLifetime = { 0.45, 0.8 },
	SparkSpeed = { 4, 9 },
	SparkSpreadDegrees = 70,
	SparkSizeStuds = 0.14,
	SparkGravity = 20,
	SparkDrag = 3,
	DropSoundSeconds = 1.5, -- the drop's sounds are cleared after this
	FreshSeconds = 0.3, -- a drop the replay only caught up with (a late join) gets nothing
	EndFadeSeconds = 0.5, -- everything fades this long after the balls stop
	-- Charged (the designer, 2026-09-28: "once it hits a ball that ball should have some magnet
	-- effect"): the moment a ball Magnet may pull is hit on a Magnet shot (it starts moving) it
	-- charges with a zap, a spark burst and the field-line burst, and keeps a faint glow for the
	-- rest of the shot (its red and blue caps went, 2026-09-30).
	ChargeMinSpeed = 0.5, -- in/s: moving at all means it has been hit
	ChargeSparkCount = 10,
	ChargeZapShare = 0.5, -- of MagnetZap's volume
	ChargeGlowBrightness = 1.2,
	ChargeGlowRangeStuds = 1.6,
	-- The pull, drawn as a flow: bright dust streaming off the ball into the pocket (reaching
	-- it as it fades) and, round the pocket, a vortex of motes drawn in to its centre.
	DustRate = 60, -- a second, at full pull
	DustLifetime = 0.35,
	DustSizeStuds = 0.08,
	DustSpreadDegrees = 12,
	VortexRate = 90, -- a second, at full pull
	VortexLifetime = 0.5,
	VortexScale = 3.2, -- the vortex's width, of the pocket's opening
	VortexHeightShare = 0.3, -- its height, of its width (motes come in low over the cloth)
	VortexSizeStuds = 0.09,
}

-- Eagle's Eye's look (src/client/EaglesEyeFx.luau; ABILITIES_PROMPT 7.2): the aim's full path
-- in the guideline's style, tinted gold, seen only by the aiming player. Studs unless named;
-- the path's maths is Config.Ults.EaglesEye. (tune)
Config.UI.EaglesEyeFx = {
	-- Neon lifts a colour a long way and not evenly: (255, 205, 70) drew lemon yellow and
	-- (235, 110, 10) orange (the look check, 2026-09-29). These draw gold on the cloth.
	CueColor = { 252, 155, 18 }, -- the cue ball's track
	ObjectColor = { 242, 125, 12 }, -- the first object ball's track: a deeper gold
	RingColor = { 255, 205, 90 }, -- the bounce rings
	PocketColor = { 255, 175, 30 }, -- the glowing pocket (ring and light)
	-- The strips: flat thin Neon on the cloth, a little thinner than the guideline's centre
	-- line (0.07) and just under it (Config.Guideline.HeightAboveClothInches 0.15, the reach
	-- preview 0.12), so the white aim line always draws over the gold.
	StripWidthStuds = 0.055,
	ThicknessStuds = 0.005,
	LiftInches = 0.09,
	StripTransparency = 0.2,
	-- A track's points closer than this to a straight line are merged (inches): a straight run
	-- between cushions is one strip, a spin curve a few.
	SimplifyInches = 0.04,
	MaxStripsPerTrack = 80, -- a safety cap on the pool (a long curving shot)
	-- The cushion bounce rings (the guideline's ring image), in ball widths.
	RingBallWidths = 0.7,
	RingTransparency = 0.15,
	MaxRingsPerTrack = 12,
	-- The glowing pocket: Kit.Art.RingGlow this many times the pocket's opening, a PointLight
	-- over it, breathing PocketPulseShare fainter once every PocketPulseSeconds.
	PocketRingScale = 1.8,
	PocketLiftInches = 0.08,
	PocketPixelsPerStud = 200,
	PocketBrightness = 2,
	PocketTransparency = 0.1,
	PocketLightBrightness = 2,
	PocketLightRangeStuds = 2.5,
	PocketPulseShare = 0.35,
	PocketPulseSeconds = 0.8,
	-- The prediction. It re-runs only when the rounded aim changes: the angle to AngleStep
	-- radians (about 0.01 degrees), the power to PowerStep, each spin axis to SpinStep, a ball
	-- moved by BallKeyInches. Each frame runs at most StepsPerFrame fixed steps (240 a second
	-- of play), ChunkSteps at a time, stopping early once BudgetMs of the frame is spent. A
	-- step cost about 15 microseconds in Lune on a Mac (2026-09-29; an average shot is about
	-- 1,400 steps), so a desktop draws a new path in about 4 frames and a phone, several times
	-- slower, in about a third of a second, never spending more than the budget a frame.
	AngleStep = 0.0002,
	PowerStep = 0.002,
	SpinStep = 0.01,
	BallKeyInches = 0.01,
	StepsPerFrame = 400,
	ChunkSteps = 25,
	BudgetMs = 3,
	-- The golden vignette: each screen edge fades from VignetteTransparency (at the edge) to
	-- clear over VignetteDepth of the screen, reaching VignetteKneeTransparency (of the
	-- gradient) VignetteKneeShare of the way in. Faint: it must never hide the table. Its
	-- ScreenGui sits VignetteBelowHud under the HUD's so the buttons stay crisp.
	VignetteColor = { 255, 190, 60 },
	VignetteTransparency = 0.62, -- (0.8 could not be seen at all: the look check)
	VignetteDepth = 0.16,
	VignetteKneeShare = 0.35,
	VignetteKneeTransparency = 0.7,
	VignetteBelowHud = 1,
	VignetteFadeInSeconds = 0.3,
	VignetteFadeOutSeconds = 0.25,
	-- The arming moment: a gold light burst at the cue ball, with the screech
	-- (Config.Ults.Audio.EagleScreech; its holder is let go after ScreechSeconds).
	ArmColor = { 255, 210, 90 },
	ArmLightRangeStuds = 5,
	ArmLightBrightness = 6,
	ArmSeconds = 0.6,
	ScreechSeconds = 2.5,
}

-- Super Bounce's look (src/client/SuperBounceFx.luau; ABILITIES_PROMPT 7.3): the rainbow shell
-- on the cue ball, a rainbow ribbon, a boing ring and a squash at every bounce. Studs unless
-- named; the bounce itself is Config.Ults.SuperBounce. (tune)
Config.UI.SuperBounceFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The shell: this many times the drawn cue ball's width, turning this fast (its bands roll
	-- round the ball), popping on over PopSeconds with a PopOvershoot spring, fading in and out.
	ShellScale = 1.06,
	TurnDegreesPerSecond = 220,
	PopSeconds = 0.35,
	PopOvershoot = 2.2,
	FadeInSeconds = 0.12,
	FadeOutSeconds = 0.5,
	-- A hit squashes it along the hit by this share (and bulges it half that across), springing
	-- back over SquashSeconds.
	SquashShare = 0.3,
	SquashSeconds = 0.22,
	-- The boing ring at a hit: this many ball widths across, growing from RingFromScale to
	-- RingToScale while it fades over RingSeconds, turning RingSpinDegrees.
	RingBallWidths = 2.6, -- (1.6 was a speck from the replay camera: the look check)
	RingFromScale = 0.45,
	RingToScale = 1.3,
	RingSeconds = 0.35,
	RingSpinDegrees = 40,
	-- A hit's ring faces out of the hit tilted this share of the way to straight up, so the
	-- overhead replay camera sees it face on and not as an edge (0: standing on the cushion).
	RingTiltShare = 0.55,
	RingTransparency = 0,
	FloorRingLiftInches = 0.1, -- the arming ring, flat on the cloth under the cue ball
	-- A hit's sparkles: SparkCount at full weight (Config.UI.Kit.Art.Spark, the rainbow), thrown
	-- every way and slowed by SparkDrag.
	SparkCount = 9,
	SparkSizeStuds = 0.12,
	SparkLifetime = { 0.3, 0.55 },
	SparkSpeed = { 3, 6 },
	SparkDrag = 4,
	SparkLightEmission = 0.3,
	-- A hit's weight (ring opacity, boing volume): its speed over FullSpeed (in/s), at least
	-- MinWeight.
	FullSpeed = 60,
	MinWeight = 0.35,
	-- The boings: each pitched PitchStep higher than the last of the shot, up to PitchMax; never
	-- two within BoingGapSeconds; each holder let go after BoingHoldSeconds.
	PitchStep = 0.05,
	PitchMax = 1.6,
	BoingGapSeconds = 0.06,
	BoingHoldSeconds = 2,
	JawPitch = 0.3, -- the caught ball's jaw boing, this much higher (a jaw sends it in)
	FreshSeconds = 0.3, -- a hit the replay only caught up with (a late join) gets nothing
	-- The ribbon: a camera-facing Trail across the cue ball (TrailBallWidths of it), fading over
	-- TrailSeconds and narrowing to TrailTailWidth, while the cue ball moves faster than
	-- TrailMinSpeed (in/s). The house rainbow (superbounce.py's RAINBOW).
	TrailBallWidths = 1,
	TrailSeconds = 0.45,
	TrailTailWidth = 0.3,
	TrailTransparency = 0,
	TrailLightEmission = 0, -- any glow washed the rainbow to pale yellow (the look check)
	TrailMinSpeed = 3,
	TrailColors = {
		{ 255, 77, 77 },
		{ 255, 159, 28 },
		{ 255, 225, 77 },
		{ 61, 214, 107 },
		{ 59, 155, 255 },
		{ 162, 89, 255 },
	},
}

-- Ghost's look (src/client/GhostFx.luau; ABILITIES_PROMPT 7.4): a see-through cue ball with a
-- cold glow, a little ghost circling it, wisps trailing it, and a flicker and a ripple on each
-- ball it passes through. Sizes in drawn ball widths unless named. (tune)
Config.UI.GhostFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	FadeInSeconds = 0.2,
	FadeOutSeconds = 0.6,
	-- The cue ball: this see-through (LocalTransparencyModifier, 0 solid), inside a Neon glow
	-- GlowScale times its width at GlowTransparency, with a cold point light.
	CueSeeThrough = 0.45,
	-- The ball the ghost pulls (from the first contact): this see-through while it rolls, and
	-- the little ghost eases over to it at this rate (per second; higher is snappier).
	PulledSeeThrough = 0.3,
	GhostFollowRate = 10,
	GlowColor = { 120, 180, 255 }, -- (190, 222, 255) read green-white on the cloth
	GlowScale = 1.22,
	GlowTransparency = 0.1,
	GlowMaterial = "ForceField", -- a cold shimmer; Neon read teal over the green cloth
	LightColor = { 175, 212, 255 },
	LightBrightness = 3,
	LightRangeBallWidths = 6,
	-- The little ghost: GhostHeight ball widths tall, circling the cue ball's centre at
	-- OrbitRadius, LiftShare of a ball width above it, bobbing Bob widths at BobHz, facing
	-- the way it flies. It pops out of the ball over PopSeconds with a PopOvershoot spring.
	GhostHeight = 1.15,
	GhostTransparency = 0.18, -- a little see-through: it crosses the aim view (0.25 showed the far eye)
	OrbitRadius = 1.45,
	OrbitDegreesPerSecond = 140,
	LiftShare = 0.85,
	Bob = 0.12,
	BobHz = 1.4,
	PopSeconds = 0.5,
	PopOvershoot = 1.8,
	-- The wisps: WispCount sheets WispLength long and WispWidth wide trailing the moving cue
	-- ball (faster than WispMinSpeed in/s), fanned WispSpreadDegrees apart, each rippling
	-- WispWaveDegrees round its length at WispWaveHz; they grow in and out over WispGrowSeconds.
	WispCount = 3,
	WispLength = 3.6,
	WispWidth = 1.7,
	WispSpreadDegrees = 16,
	WispWaveDegrees = 18,
	WispWaveHz = 2.4,
	-- Above 0: at 0 Roblox draws the mesh opaque and ignores its texture's alpha fade (the
	-- look check: solid grey ribbons).
	WispTransparency = 0.02,
	WispMinSpeed = 3,
	WispGrowSeconds = 0.25,
	-- A soft pale Trail under the wisps, across the cue ball, TrailSeconds long.
	TrailColor = { 215, 235, 255 },
	TrailSeconds = 0.35,
	TrailTransparency = 0.55,
	-- A ball the cue ball passes through: it flickers for FlickerSeconds (up to FlickerDepth
	-- see-through, FlickerHz), a ripple spreads round it on the cloth (RippleFrom to RippleTo
	-- ball widths over RippleSeconds, from RippleTransparency), and a whoosh plays there.
	FlickerSeconds = 0.55,
	FlickerHz = 16,
	FlickerDepth = 0.75,
	RippleFrom = 0.8,
	RippleTo = 3.4,
	RippleSeconds = 0.9, -- (0.6 was gone before the replay camera settled)
	RippleTransparency = 0.1,
	RippleLiftInches = 0.1,
	SoundHoldSeconds = 3, -- each sound's holder is let go after this long
	FreshSeconds = 0.3, -- a replay frame jumping further than this (a late join) draws no passes
}

-- Heat Seeker's look (src/client/HeatSeekerFx.luau; ABILITIES_PROMPT 7.5): the red lock-on
-- reticle, the blinking dot on the cue ball, the missile's exhaust and smoke, the impact's
-- flash and smoke ring, and the beeps. Sizes in drawn ball widths unless named. (tune)
Config.UI.HeatSeekerFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The reticle: flat over the locked ball, closing from LockFrom to LockTo ball widths across
	-- over LockSeconds as the pick lands (then the solid tone), spinning SpinDegreesPerSecond,
	-- LiftInches above the cloth; it pulses PulseShare in size at PulseHz while it waits.
	LockFrom = 4.4,
	LockTo = 2.5, -- (1.7 hid under the pick view's ring from overhead: the look check)
	LockSeconds = 0.7,
	SpinDegreesPerSecond = 90,
	LockSpinDegreesPerSecond = 420, -- as it closes in
	LiftInches = 0.15,
	PulseShare = 0.06,
	PulseHz = 1.5,
	FadeSeconds = 0.25,
	-- The beeps: while it closes in, from BeepSlowSeconds apart to BeepFastSeconds; in flight,
	-- the gap shrinks with the distance left (FarInches or more: slow), and each beep is
	-- pitched up a little as it closes. The lock tone plays LockToneSeconds.
	BeepSlowSeconds = 0.2,
	BeepFastSeconds = 0.05,
	FarInches = 60,
	BeepPitchRise = 0.35,
	LockToneSeconds = 0.45,
	-- The red dot on the cue ball's top: DotBallWidths across, blinking at BlinkHz armed and
	-- FlightBlinkHz in flight.
	DotColor = { 255, 40, 40 },
	DotBallWidths = 0.22,
	BlinkHz = 2.5,
	FlightBlinkHz = 9,
	-- The exhaust: the flame FlameLength long and FlameWidth wide behind the moving cue ball,
	-- flickering FlickerShare at FlickerHz, sized by speed (full at FullSpeed in/s); smoke
	-- puffs (the flipbook) at SmokeRate a second at full speed, SmokeSize studs, SmokeSeconds.
	FlameLength = 3.4,
	FlameWidth = 0.85,
	FlickerShare = 0.18,
	FlickerHz = 18,
	FullSpeed = 120,
	MinSpeed = 4, -- slower than this (in/s): no exhaust
	SmokeRate = 70,
	SmokeSize = { 0.25, 0.7 },
	SmokeSeconds = { 0.45, 0.8 },
	SmokeTransparency = 0.25,
	SmokeColor = { 175, 172, 168 }, -- grey: white puffs read as a glow under the flame's light
	FlameLightColor = { 255, 150, 60 },
	FlameLightBrightness = 2,
	FlameLightRangeBallWidths = 5,
	-- The impact: an orange flash (a light and a Neon ball growing to FlashBallWidths over
	-- FlashSeconds) and the smoke ring spreading from RingFrom to RingTo ball widths over
	-- RingSeconds.
	FlashColor = { 255, 170, 70 },
	FlashBallWidths = 2.2,
	FlashSeconds = 0.18,
	FlashBrightness = 6,
	RingFrom = 0.8,
	RingTo = 3.2,
	RingSeconds = 0.7,
	RingTransparency = 0.2,
	HoldSeconds = 2, -- each sound's and flash's holder is let go after this long
	FreshSeconds = 0.3, -- an impact the replay only caught up with (a late join) gets nothing
}

-- Rewind's look (src/client/RewindFx.luau; docs/prompts/ABILITIES_PROMPT.md 7.6, reference 02)
-- and its playback in src/client/Match.luau. Studs unless named. (tune)
Config.UI.RewindFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The playback: the table flies back through the shot at RewindSpeed times real time,
	-- faster when that would take over MaxPlaySeconds; it starts LeadSeconds into the rewind
	-- moment (Config.Ults.Shared.RewindSeconds), once the glitch is up, so the landing's clunk
	-- comes before the redo's clock.
	RewindSpeed = 3,
	MaxPlaySeconds = 1.7,
	LeadSeconds = 0.25,
	-- The dial round the armed cue ball: DialBallWidths across (its outer edge), LiftInches
	-- over the cloth, turning backward (counter-clockwise from above) SpinDegreesPerSecond,
	-- RewindSpinDegreesPerSecond while the table rewinds; it pops in over PopSeconds. It stays
	-- on the cue ball's start spot through the shot (the table comes back there), with a
	-- see-through ghost of the cue ball, GhostTransparency.
	DialBallWidths = 3.2,
	LiftInches = 0.12,
	SpinDegreesPerSecond = 60,
	RewindSpinDegreesPerSecond = 900,
	PopSeconds = 0.25,
	DialTransparency = 0.02, -- a textured MeshPart at 0 ignores its texture's alpha (STUDIO_NOTES)
	GhostTransparency = 0.7,
	GhostColor = { 255, 200, 250 },
	-- A try that drops one of yours: the dial glitches (flickers FlickerHz) and fades over
	-- SpentSeconds.
	SpentSeconds = 0.6,
	FlickerHz = 16,
	-- The balls' streaks while they fly back: a Trail StreakBallWidths wide, StreakSeconds
	-- long, white at the ball through magenta to green at its tail.
	StreakBallWidths = 1,
	StreakSeconds = 0.3,
	StreakTransparency = 0.1, -- (look check: 0.25 with half the glow was lost under the screen)
	StreakColors = { { 255, 255, 255 }, { 255, 40, 235 }, { 60, 255, 90 } },
	-- The whirr: sped up to last the playback, from WhirrPitchFrom to WhirrPitchTo times that.
	WhirrPitchFrom = 1,
	WhirrPitchTo = 1.45,
	-- The screen (ScreenFx, for everyone at the table): a grade (a little grey, contrast up, a
	-- pink tint), the edge split jittering, scanlines, grain flickering, tearing bands jumping,
	-- a tracking band rolling up, and the big icon pulsing in the middle, all in over FadeIn
	-- and out over FadeOut; a white flash as it starts and as the table lands, a small shake.
	FadeIn = 0.12,
	FadeOut = 0.3,
	-- (Look checks: a brighter grade washed the view out and the white icon did not pop; the
	-- edge split at 0.15, then 0.45, flooded the screen's sides pink and green; the grain at
	-- 0.55 turned the whole view to snow.)
	Grade = {
		Saturation = -0.2,
		Contrast = 0.45,
		Brightness = -0.15,
		TintColor = { 245, 225, 255 },
	},
	FringeTransparency = 0.62,
	FringeJitter = 0.006,
	ScanTransparency = 0.45,
	StaticTransparency = 0.8,
	StaticFps = 18,
	TearTransparency = 0.25,
	TearJitter = 0.05,
	TearJitterSeconds = 0.07,
	TrackingTransparency = 0.35,
	TrackingScroll = 0.8, -- screens a second, upward
	IconSquare = 0.55, -- the icon's size, a share of the screen's height
	IconFps = 12,
	IconTransparency = 0,
	IconPulseHz = 2.5,
	IconPulseShare = 0.06,
	StartFlash = { 255, 255, 255 },
	StartFlashSeconds = 0.2,
	LandFlash = { 255, 240, 255 },
	LandFlashSeconds = 0.3,
	ShakeStuds = 0.12,
	ShakeSeconds = 0.4,
	-- The SECOND CHANCE: 10s pill under the clock (MatchHUD).
	PillColor = { 255, 150, 240 },
	FreshSeconds = 0.5, -- a rewind this client only caught up with late gets no screen
}

-- Time Stop's look (src/client/TimeStopFx.luau; docs/prompts/ABILITIES_PROMPT.md 7.7, reference
-- 03). Studs unless named. (tune)
Config.UI.TimeStopFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The bubble (ForceField, BubbleColor): BubbleBallWidths across on the armed cue ball,
	-- turning SpinDegreesPerSecond; from the first contact it swells to SwellBallWidths as the
	-- freeze nears; on the freeze it bursts out to BurstStuds over BurstSeconds and fades; on the
	-- resume it comes back that big and collapses onto the cue ball over CollapseSeconds.
	-- (Look check 1: a paler, smaller bubble all but vanished round the armed cue ball.)
	BubbleColor = { 175, 130, 255 },
	BubbleTransparency = 0,
	BubbleBallWidths = 1.9,
	SwellBallWidths = 2.4,
	SpinDegreesPerSecond = 40,
	BurstStuds = 60,
	PatternMaxBallWidths = 4, -- bigger than this the bubble drops its warp pattern (look check 2)
	BurstSeconds = 0.5,
	CollapseSeconds = 0.4,
	PopSeconds = 0.25,
	-- The clock face on the cloth round the frozen cue ball: ClockBallWidths across, LiftInches
	-- up, ClockTransparency at full; its hand sweeps once round in the stopped time
	-- (Config.Ults.Shared.FrozenSeconds). The hand's centre sits HandCentreShare of its length
	-- up the needle from its hub (the model's bounding box).
	ClockBallWidths = 9,
	LiftInches = 0.1,
	ClockTransparency = 0.25,
	ClockFadeSeconds = 0.3,
	HandCentreShare = 0.365 / 0.97,
	-- Frozen balls' afterimages: Ghosts copies behind each ball moving faster than
	-- GhostMinSpeed (in/s), spaced GhostSpacingSeconds of its motion apart (at most
	-- GhostMaxBallWidths), each more see-through (GhostTransparency).
	Ghosts = 3,
	GhostMinSpeed = 8,
	GhostSpacingSeconds = 0.035,
	GhostMaxBallWidths = 1.2,
	GhostTransparency = { 0.55, 0.72, 0.86 },
	-- The second strike in stopped time: the cue ball's violet trail.
	TrailColor = { 190, 160, 255 },
	TrailSeconds = 0.35,
	-- The screen (ScreenFx, for everyone at the table): the negative flash on the freeze and on
	-- the resume, the warp ring growing from the middle past the edges, then while frozen a
	-- cold grade and the lens edge.
	InvertSeconds = 0.18,
	RingSquare = 0.5, -- the ring's size at 1x, a share of the screen height
	RingGrowFrom = 0.1,
	RingGrowTo = 4,
	RingSeconds = 0.55,
	RingTransparency = 0.05,
	-- (Look check 1: at -0.75 the cloth stayed plainly green, not the reference's cold violet.)
	Grade = {
		Saturation = -0.92,
		Contrast = 0.3,
		Brightness = -0.05,
		TintColor = { 195, 170, 255 },
	},
	GradeFadeIn = 0.2,
	GradeFadeOut = 0.15,
	LensTransparency = 0.18,
	LensFadeIn = 0.35,
	LensFadeOut = 0.2,
	ShakeStuds = 0.15,
	ShakeSeconds = 0.35,
	-- The sounds: the swell sped up by SwellPitch so its peak (1.2 s in) lands on the freeze
	-- (Shared.FreezeAfterSeconds after the first contact); a tick every TickSeconds frozen;
	-- the tick-tock ResumeTickDelay after the resume whoosh.
	SwellPitch = 1.2,
	TickSeconds = 1,
	ResumeTickDelay = 0.3,
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no screen
}

-- Chain Lightning's look (src/client/ChainLightningFx.luau; docs/prompts/ABILITIES_PROMPT.md 7.8,
-- reference 04). Studs unless named. (tune)
Config.UI.ChainLightningFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- The bolts (the model's Bolt meshes): a white-hot Neon core in a see-through cyan Neon
	-- shell, rolled to face the camera, swapping to another variant every SwapSeconds. Across
	-- the jags a bolt is scaled by sqrt(length x WidthRefStuds), so a short one is not a
	-- hairline and a long one not a rope. Each jump's bolt lasts BoltSeconds, shown in pulses
	-- (start and end as shares of it, each fading over its second half). The opponent's bolts
	-- are OppWidth as wide and fainter. (Look check 2: one 0.4 s flash was over before the balls
	-- parted, so the chain did not read as a chain.)
	-- (Look check 1: at 2 studs and a cyan shell the bolts were hairlines from the shot camera,
	-- lost on the green cloth.)
	CoreColor = { 235, 248, 255 },
	GlowColor = { 50, 140, 255 },
	CoreTransparency = 0,
	GlowTransparency = 0.2,
	WidthRefStuds = 4.5,
	SwapSeconds = 0.05,
	BoltSeconds = 0.8,
	BoltPulses = { { 0, 0.35 }, { 0.45, 0.62 }, { 0.75, 0.88 } },
	OppWidth = 0.6,
	OppCoreTransparency = 0.35,
	OppGlowTransparency = 0.6,
	-- The charge: a bolt strikes down from StrikeHeightStuds above onto the charged ball for
	-- StrikeSeconds, a blue light flares over the cloth, the view shakes, and a blue glow
	-- spreads on the cloth round the ball (FlashBallWidths across) and fades.
	StrikeHeightStuds = 4,
	StrikeSeconds = 0.25,
	FlashBallWidths = 14,
	FlashTransparency = 0.35,
	FlashSeconds = 0.5,
	BurstRangeStuds = 8,
	BurstBrightness = 4,
	BurstSeconds = 0.45,
	ShakeStuds = 0.1,
	ShakeSeconds = 0.25,
	-- A charged or struck ball glows for GlowSeconds (or until it drops): crackling arcs (the
	-- flipbook, CrackleRate a second, CrackleBallWidths across, each CrackleLife long), a
	-- flickering blue light, and sparks when it is struck (Sparks of them); the charged ball
	-- (and the armed cue ball) also has Arcs small bolt cores jumping round it (ArcBallWidths
	-- long). (A frame-time check: arcs on every struck ball put 26 bolt meshes, about 26k
	-- triangles, on screen at once.) The opponent's at OppWidth of the size.
	-- Under a glowing ball a deep blue glow on the cloth (PoolBallWidths across, PoolTransparency
	-- at full), so the white arcs read against blue as in the reference, not on green.
	PoolBallWidths = 5,
	PoolColor = { 30, 90, 255 },
	PoolTransparency = 0.15,
	GlowSeconds = 1.3,
	CrackleRate = 30,
	CrackleBallWidths = 1.7,
	CrackleLife = { 0.06, 0.12 },
	Arcs = 1,
	ArcBallWidths = 1.1,
	LightColor = { 110, 200, 255 },
	LightBrightness = 2.5,
	LightRangeBallWidths = 6,
	Sparks = 14,
	SparkBallWidths = 0.5,
	SparkSpeed = { 3, 7 },
	-- Armed: the cue ball crackles softly (ArmedRate) with an arc now and then (ArmedArcChance a
	-- swap), and hums quietly (ArmedHumVolume of the hum).
	ArmedRate = 10,
	ArmedArcChance = 0.3,
	ArmedHumVolume = 0.35,
	PopSeconds = 0.25,
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no screen
}

-- Portals' look (src/client/PortalsFx.luau; docs/prompts/ABILITIES_PROMPT.md 7.9, reference 05).
-- Studs unless named; each portal is drawn at Config.UI.UltPick.PortalRingBallWidths (its
-- radius) so it matches the pick view's ring. (tune)
Config.UI.PortalsFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	-- A is the entry's cyan, B the violet-blue (the pick view's colours); each turns its own way.
	RimSpinDegrees = 25, -- a second
	SwirlSpinDegrees = 70,
	CoreTransparency = 0.1,
	RimTransparency = 0,
	DiscTransparency = 0.02, -- the swirl's own alpha shows only below 1 (MeshPart textures)
	DiscTint = { 120, 125, 150 }, -- (look check 2: at white the portal's light washed the dark middle out)
	LiftInches = 0.05, -- above the cloth
	-- The sparkles stream in: two sparkle layers each shrink from SparkleFrom to SparkleTo of
	-- the portal over SparkleSeconds, fading, half a cycle apart, turning faster than the swirl.
	SparkleFrom = 1.1,
	SparkleTo = 0.35,
	SparkleSeconds = 1.2,
	SparkleSpinDegrees = 160,
	SparkleTransparency = 0.1,
	-- The soft light on the cloth round each portal, and a glow of the portal's colour on the
	-- cloth under it (HaloScale x the portal across, pulsing HaloPulse either side of
	-- HaloTransparency at HaloHz). (Look check 1: without it the rims read thin and faint.)
	LightBrightness = 1.6,
	LightRangeBallWidths = 3,
	HaloScale = 2.4,
	HaloTransparency = 0.3,
	HaloPulse = 0.1,
	HaloHz = 1.5,
	-- Opening (a spiral in: from nothing, turning OpenTurns extra) and closing (collapsing back
	-- the same way) once the balls stop.
	OpenSeconds = 0.45,
	OpenTurns = 1,
	CloseSeconds = 0.35,
	-- A ball going in: a copy of it shrinks and sinks into the portal over SinkSeconds with a
	-- flash; the portal swells to Pulse for PulseSeconds. Coming out: the burst ring grows from
	-- 1 to BurstTo of the portal over BurstSeconds, fading, with Sparks sparks.
	-- (Look check 1: a flash of 5 on the cloth washed the swirl white.)
	SinkSeconds = 0.22,
	FlashBrightness = 2.5,
	FlashSeconds = 0.3,
	Pulse = 1.3,
	PulseSeconds = 0.25,
	BurstTo = 3.2,
	BurstSeconds = 0.35,
	BurstTransparency = 0.05,
	Sparks = 12,
	-- While placing, a pair the server would refuse turns the rims to the pick view's
	-- PortalBlockedColor.
	HumVolume = 1,
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no sound
}

-- Steel Ball's look (src/client/SteelBallFx.luau). Studs unless named. (tune)
Config.UI.SteelBallFx = {
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	FadeInSeconds = 0.2,
	FadeOutSeconds = 0.5,
	ShellScale = 1, -- the shell over the drawn cue ball
	OutlineColor = { 0, 0, 0 }, -- the heavy manga outline (a Highlight round the shell)
	-- The spin: this slowly (degrees a second) while armed; rolling, SpinBoost times its
	-- natural roll (it spins hard).
	IdleSpinDegrees = 90,
	SpinBoost = 2.5,
	-- The golden spirals round it: how many, their size (x the modelled one, whose outer end is
	-- 2.3 ball radii out), their turn (degrees a second, SpiralMovingBoost times more rolling),
	-- their tilt either way (degrees), and their spring out at the arming.
	Spirals = 2, -- (art director: 3 thin ones read as atom orbits)
	SpiralScale = 1.3, -- (look check 1: at 0.75 they were hairlines from the replay camera)
	SpiralSpinDegrees = 540,
	SpiralMovingBoost = 1.5,
	SpiralTiltDegrees = 35,
	SpiralTransparency = 0.02, -- the ribbon's own alpha shows only below 1 (MeshPart textures)
	PopSeconds = 0.5,
	PopOvershoot = 1.8,
	-- Gold: the light, the trail and the flashes.
	GoldColor = { 255, 190, 60 },
	TrailColor = { 255, 245, 200 },
	LightColor = { 255, 200, 90 },
	LightBrightness = 3,
	LightRangeBallWidths = 4,
	TrailSeconds = 0.25,
	TrailBallWidths = 0.6, -- the trail's width at the ball
	TrailTransparency = 0.25,
	RollingInchesPerSecond = 4, -- slower than this it is not rolling (no trail, no whirr)
	MovingFadeSeconds = 0.25,
	WhirrFullInchesPerSecond = 100, -- the whirr is loudest and highest from this fast
	FlashBrightness = 3,
	FlashSeconds = 0.35,
	SparkleBallWidths = 0.9,
	ArmSparks = 16,
	SteelSparks = 8,
	PotSparks = 20,
	ShakeStuds = 0.15,
	ShakeSeconds = 0.25,
	-- A guided ball's golden path on the cloth: this wide (ball widths), fading in and out over
	-- these, scrolling toward the pocket, gone after PathMaxSeconds at most.
	PathBallWidths = 1.3, -- (look check 1: at 0.9 the curls were too small to read)
	PathLiftInches = 0.06,
	PathTransparency = 0,
	PathInSeconds = 0.25,
	PathOutSeconds = 0.4,
	PathScrollStuds = 1.5,
	PathMaxSeconds = 6,
	-- A guided pot's burst ring at the pocket: grows to BurstBallWidths across over
	-- BurstSeconds, fading. (Art director: at the first contact too it stole the pot's moment;
	-- the contact now only sparkles.)
	BurstBallWidths = 9,
	BurstSeconds = 0.35,
	BurstTransparency = 0,
	-- Clanks: no closer together than this; full volume from this contact speed (in/s).
	ClankGapSeconds = 0.08,
	ClankFullSpeed = 120,
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no sound
}

-- Black Flash's look (src/client/BlackFlashFx.luau). Studs unless named. (tune)
Config.UI.BlackFlashFx = {
	RedColor = { 255, 24, 40 },
	-- Armed: the cue ball crackles: ArmedSparkRate red sparks a second, a faint red light and a
	-- quiet crackle loop.
	ArmedSparkRate = 25,
	ArmedSparkBallWidths = 1, -- each spark's size at birth
	-- And ArmedArcs small black arcs (outlined red) flicker out of it: each re-drawn every
	-- ArmedArcSeconds, shown with ArmedArcChance, ArmedArcBallWidths long (a range), rising up
	-- to ArmedArcRiseDegrees, ArmedArcThickness times the bolt mesh's width share.
	ArmedArcs = 2,
	ArmedArcSeconds = 0.07,
	ArmedArcChance = 0.6,
	ArmedArcBallWidths = { 0.6, 1.1 },
	ArmedArcRiseDegrees = 30,
	ArmedArcThickness = 2,
	ArmedLightBrightness = 1.2,
	ArmedCrackleVolume = 0.25,
	-- The flash: Bolts black bolts (outlined red by one Highlight) tear out of the ball, each
	-- BoltBallWidths long (a range), mostly flat and outward, rising up to BoltRiseDegrees;
	-- flickering between the four variants every SwapSeconds, gone after BoltSeconds (on the
	-- replay's clock, so /slowmo slows them).
	Bolts = 7,
	BoltBallWidths = { 5, 8.5 },
	BoltThickness = 1.7, -- the bolts drawn this many times thicker than the mesh's own share
	-- The red rim: a red Neon copy of each bolt, GlowWidth times as wide, GlowBehindStuds
	-- behind it from the camera, at GlowTransparency.
	GlowWidth = 1.35,
	GlowBehindStuds = 0.02,
	GlowTransparency = 0.15,
	BoltGrowShare = 0.06, -- the share of BoltSeconds they take to reach full length
	BoltRiseDegrees = 25,
	LiftedBolts = 2, -- of the Bolts, this many tear up toward the sky instead
	LiftedRiseDegrees = { 40, 55 }, -- how steeply they rise (a range)
	SwapSeconds = 0.05,
	BoltSeconds = 0.7,
	-- The shards: burst out at ShardSpeed (studs a second, a range) plus ShardUp, spinning,
	-- falling with ShardGravity, fading out over the last ShardFadeSeconds of ShardSeconds.
	-- On the cloth each bounce keeps ShardBounceSpinShare of its spin, and a shard lying there
	-- slides to a stop (ShardSlideFriction, a share of its speed lost a second).
	ShardSpeed = { 3, 7 },
	ShardUp = 2.5,
	ShardSpinDegrees = 720,
	ShardGravity = 18,
	ShardSeconds = 6.1, -- the designer (2026-09-30): 5 s longer on the table (was 1.1)
	ShardScale = 1.5, -- the shards drawn this much bigger than the ball's own pieces (they read)
	ShardFadeSeconds = 0.4,
	ShardBounceSpinShare = 0.4,
	ShardSlideFriction = 4,
	-- The shockwave ring on the cloth: grows to RingBallWidths (a full-power blast; a softer one
	-- in proportion to its reach) over RingSeconds, fading.
	RingBallWidths = 22,
	RingSeconds = 0.45,
	-- The screen: a red flash, then a pale, high-contrast red-grey grade (the black bolts pop on
	-- it, as in the reference), a shake and an FOV punch.
	FlashSeconds = 0.25,
	Grade = { TintColor = { 255, 140, 150 }, Contrast = 1.7, Saturation = -1, Brightness = 0.08 },
	GradeIn = 0.02,
	GradeHold = 0.25,
	GradeOut = 0.45,
	ShakeStuds = 0.35,
	ShakeSeconds = 0.4,
	FovDegrees = 8,
	FovSeconds = 0.35,
	LightBrightness = 6,
	LightRangeBallWidths = 25,
	LightSeconds = 0.4,
	-- Each nudged ball: a spurt of red and black sparks.
	NudgeSparks = 10,
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no sound
}

-- Black Hole's look (src/client/BlackHoleFx.luau). Studs unless named; the hole's pieces are
-- sized from the horizon's radius. (tune)
Config.UI.BlackHoleFx = {
	-- Armed: a small dark vortex this many ball widths across turns under the cue ball.
	ArmedVortexBallWidths = 2.6,
	ArmedSpinDegrees = 120,
	ArmedTransparency = 0.1,
	-- Opening: a pinprick for PinprickSeconds, then it swells to full over OpenSeconds,
	-- overshooting to OpenOvershoot; a light flash (FlashColor, FlashBrightness, over
	-- FlashRangeBallWidths, FlashSeconds), a pale blue screen flash and a small shake.
	PinprickSeconds = 0.08,
	OpenSeconds = 0.45,
	OpenOvershoot = 1.25,
	FlashColor = { 190, 220, 255 },
	FlashBrightness = 8,
	FlashRangeBallWidths = 18,
	FlashSeconds = 0.35,
	ScreenFlashColor = { 200, 225, 255 },
	ScreenFlashSeconds = 0.18,
	OpenShakeStuds = 0.12,
	OpenShakeSeconds = 0.3,
	-- The hole: the horizon's size in ball widths across; the photon ring (PhotonColor)
	-- flares FlareScale times over FlareSeconds on each swallow; the lensed light at
	-- LensTransparency.
	HorizonBallWidths = 3,
	-- The horizon sits on the cloth, HoverInches clear; the photon ring and the lensed light
	-- are drawn RingForwardShare of its radius toward the camera (in front of the disk).
	HoverInches = 0.1,
	RingForwardShare = 0.6,
	PhotonColor = { 255, 244, 225 },
	FlareScale = 1.35,
	FlareSeconds = 0.3,
	SwallowPulse = 0.08, -- and the horizon swells this share with it
	LensTransparency = 0.05,
	-- The accretion disk: tilted DiskTiltDegrees toward the camera, spinning DiskSpinDegrees a
	-- second, at DiskTransparency.
	DiskTiltDegrees = 14,
	DiskSpinDegrees = 160,
	DiskTransparency = 0.15,
	-- The vortex on the cloth: as wide as the reach, VortexLiftInches above the cloth, grown
	-- VortexGrowShare times faster than the hole, turning VortexSpinDegrees a second.
	VortexLiftInches = 0.04,
	VortexGrowShare = 1.6,
	VortexSpinDegrees = 45,
	VortexTransparency = 0.05,
	-- Over it a second layer InnerShare as wide turns InnerSpinDegrees a second and flows
	-- inward: shrinking by FlowShrink and fading over FlowSeconds, round and round.
	InnerShare = 0.65,
	InnerSpinDegrees = 120,
	InnerTransparency = 0.35,
	FlowSeconds = 1.2,
	FlowShrink = 0.15,
	-- The light at the hole (LightColor, LightBrightness over LightRangeBallWidths).
	LightColor = { 255, 170, 90 },
	LightBrightness = 3,
	LightRangeBallWidths = 14,
	-- Each pulled ball: drawn stretched toward the hole up to 1 + Stretch times long as it
	-- nears, spinning SpinDegrees a second (1 + SpinBoost times near the hole), shrinking
	-- inside ShrinkHorizons horizon radii (down to MinScale), gone GoneSeconds after the
	-- swallow; a streak StreakBallWidths wide lasting StreakSeconds.
	Stretch = 2.2,
	-- It rises into the disk's plane as it nears: all the way by 1 / RiseShare of the trip.
	RiseShare = 1.5,
	SpinDegrees = 360,
	SpinBoost = 4,
	ShrinkHorizons = 1.6,
	MinScale = 0.05,
	GoneSeconds = 0.12,
	StreakBallWidths = 0.5,
	StreakSeconds = 0.4,
	StreakTransparency = 0.25,
	StreakColor = { 120, 190, 255 },
	-- The close: once no caught ball is left, the hole open MinOpenSeconds and CloseDelaySeconds
	-- after the last swallow (or the replay over), it swells a little and collapses over
	-- CollapseSeconds, then pops: a ring (PopRingBallWidths across over PopRingSeconds), a
	-- PopColor light flash, a shake.
	MinOpenSeconds = 1.2,
	CloseDelaySeconds = 0.35,
	CollapseSeconds = 0.5,
	PopRingBallWidths = 14,
	PopRingSeconds = 0.45,
	PopColor = { 220, 235, 255 },
	PopShakeStuds = 0.15,
	PopShakeSeconds = 0.25,
	-- And a short colour punch (ScreenFx.grade: in, hold, out seconds).
	PopGrade = { Saturation = -0.6, Contrast = 0.3 },
	PopGradeIn = 0.02,
	PopGradeHold = 0.1,
	PopGradeOut = 0.2,
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no sound
}

-- Guangdong Tiger's look (src/client/GuangdongTigerFx.luau). Inches and seconds unless named:
-- the tiger's own clock, from the "swipe" event (the replay is slowed round it by
-- Config.Ults.GuangdongTiger's slow, the tiger is not). Angles in degrees. (tune)
Config.UI.GuangdongTigerFx = {
	-- Armed: three claw marks (the cloth marks' look, MarkHotColor) this many ball widths long
	-- and wide, diagonal under the cue ball, pulsing ArmedPulseHz times a second between
	-- ArmedTransparency and fully clear.
	ArmedMarkBallWidths = 2.4,
	ArmedMarkWidthBallWidths = 0.8,
	ArmedPulseHz = 1.2,
	ArmedTransparency = 0.1,
	ArmedColor = { 255, 150, 60 },
	-- The tiger, nose to tail tip, seen side-on (it crosses the view), with a black outline;
	-- its head and jaw HeadScale times the model's (the face reads from the shooting camera).
	TigerLengthInches = 42,
	HeadScale = 1.15,
	OutlineColor = { 12, 6, 2 },
	-- The leap in: from LeapFromInches behind where it lands and StartLiftInches up, over
	-- ArcInches (low: its head stays in the shooting camera's frame), in LeapSeconds; nose up
	-- LeapPitch[1] at the start to LeapPitch[2] at the end, the front legs reaching
	-- LeapFrontDegrees forward, the hind ones LeapHindDegrees back.
	LeapSeconds = 0.42,
	LeapFromInches = 50,
	StartLiftInches = 0,
	ArcInches = 5,
	LeapPitch = { 18, -10 },
	LeapFrontDegrees = 60,
	LeapHindDegrees = 55,
	-- It lands with its front paws PawBackInches short of the swipe's centre (beside the cut
	-- balls, not on them), crouching CrouchShare of its height and back over CrouchSeconds; a
	-- shake and a thump.
	PawBackInches = 12,
	CrouchShare = 0.1,
	CrouchSeconds = 0.18,
	LandShakeStuds = 0.18,
	LandShakeSeconds = 0.3,
	-- The swipe: the paw nearer the camera winds up to PawRaiseDegrees (out PawOutDegrees)
	-- over RaiseSeconds, strikes down to PawStrikeDegrees over StrikeSeconds and freezes on the
	-- impact ImpactFreezeSeconds; the jaw opens JawDegrees for the roar, from the leap to
	-- RoarEndSeconds after the strike.
	RaiseSeconds = 0.15,
	StrikeSeconds = 0.08,
	ImpactFreezeSeconds = 0.06,
	PawRaiseDegrees = 150,
	PawOutDegrees = 45,
	PawStrikeDegrees = -15,
	JawDegrees = 42,
	RoarEndSeconds = 0.35,
	-- At the strike's middle: three slashes in the air, crescents of beams (SlashEdgeColor
	-- round a SlashCoreColor core SlashCoreShare as wide, the core added light so the grade
	-- cannot eat it: SlashCoreEmission, SlashCoreBrightness), SlashWidthInches wide in the middle
	-- tapering to points, SlashLengthInches long, SlashGapInches apart, bowed SlashBow of their
	-- length; SlashLiftInches over the centre and SlashForwardInches toward the camera (in
	-- front of the tiger), falling SlashTiltDegrees forward across the view; each
	-- SlashStaggerSeconds after the one before, drawn in over SlashGrowSeconds, held
	-- SlashHoldSeconds, fading over SlashFadeSeconds.
	SlashLengthInches = 28,
	SlashWidthInches = 1.6,
	SlashCoreShare = 0.4,
	SlashCoreEmission = 1,
	SlashCoreBrightness = 3,
	SlashGapInches = 3,
	SlashBow = 0.14, -- about 4 in on a 28 in slash
	SlashLiftInches = 8,
	SlashForwardInches = 10,
	SlashTiltDegrees = 35,
	SlashStaggerSeconds = 0.02,
	SlashGrowSeconds = 0.06,
	SlashHoldSeconds = 0.1,
	SlashFadeSeconds = 0.35,
	SlashEdgeColor = { 255, 74, 26 },
	SlashCoreColor = { 255, 250, 235 },
	SlashBrightness = 2,
	SlashEmission = 0.2, -- how much of the beams is added light (1: all; over green reads yellow)
	-- A SlashColor light burst, a shake, an FOV punch and a colour punch (ScreenFx.grade: in,
	-- hold, out).
	SlashColor = { 255, 185, 110 },
	SlashLightBrightness = 3,
	SlashLightBallWidths = 22,
	SlashLightSeconds = 0.3,
	StrikeShakeStuds = 0.14,
	StrikeShakeSeconds = 0.25,
	FovPunchDegrees = 6,
	FovPunchSeconds = 0.25,
	StrikeGrade = { Saturation = 0.35, Contrast = 0.35, TintColor = { 255, 220, 180 } },
	StrikeGradeIn = 0.02,
	StrikeGradeHold = 0.12,
	StrikeGradeOut = 0.25,
	-- And three claw marks gouged in the cloth (the slash picture as a decal), raked
	-- MarkAngleDegrees off the leap's line: MarkLengthInches long, MarkWidthInches wide,
	-- MarkGapInches apart, at MarkTransparency; white-hot (MarkHotColor) cooling to scorched
	-- (MarkScorchColor) over MarkCoolSeconds, held MarkHoldSeconds, fading over MarkFadeSeconds.
	MarkAngleDegrees = 35,
	MarkLengthInches = 20,
	MarkWidthInches = 1.6,
	MarkGapInches = 3.5,
	MarkTransparency = 0,
	MarkHotColor = { 255, 245, 230 },
	MarkScorchColor = { 120, 45, 25 },
	MarkCoolSeconds = 1,
	MarkHoldSeconds = 0.9,
	MarkFadeSeconds = 0.5,
	-- The fur frame (Config.Ults.Assets.Images.TigerFur) over the whole view: in, hold, out, at
	-- FurTransparency (solid: the reference's flash frame).
	FurFadeIn = 0,
	FurHold = 0.1,
	FurFadeOut = 0.15,
	FurTransparency = 0,
	-- Each cut ball waits where it was until the strike, then splits along the slash into
	-- halves HalfScale times its size, each with a hot cut face (a CutRimColor rim round a
	-- CutCoreColor core): they fly apart at HalfSpeedInches a second (HalfUpInches a second
	-- up), under HalfGravityInches, spinning HalfSpinDegrees a second, fading over HalfSeconds
	-- (about 8-12 in of tumble); each ball CutStaggerSeconds after the one before.
	HalfScale = 1.25,
	CutSparks = 8, -- and a burst of white sparks where the slash crosses the ball
	CutSparkColor = { 255, 245, 225 },
	CutRimColor = { 255, 110, 30 },
	CutCoreColor = { 255, 236, 205 },
	HalfSpeedInches = 18,
	HalfUpInches = 14,
	HalfGravityInches = 120,
	HalfSpinDegrees = 300,
	HalfSeconds = 0.55,
	CutStaggerSeconds = 0.025,
	-- It holds HoldSeconds after the freeze, then bounds off forward: LeapOutInches, over
	-- LeapOutArcInches, in LeapOutSeconds, fading over its last FadeSeconds.
	HoldSeconds = 0.3,
	LeapOutInches = 56,
	LeapOutArcInches = 10,
	LeapOutSeconds = 0.55,
	FadeSeconds = 0.15,
	ModelCheckSeconds = 1, -- while the model has not arrived, look for it this often
	FreshSeconds = 0.4, -- a moment the replay only caught up with (a late join) gets no tiger
}

-- The abilities' shared look framework (src/client/AbilityFx.luau and its kit; the brief's
-- step 1, docs/prompts/ABILITIES_PROMPT.md 5). Studs unless named. (tune)
Config.UI.AbilityFx = {
	-- Each ability's client look module (ult id -> a ModuleScript next to AbilityFx). A missing
	-- one is skipped with a warning.
	Looks = {
		Magnet = "MagnetFx",
		EaglesEye = "EaglesEyeFx",
		SuperBounce = "SuperBounceFx",
		Ghost = "GhostFx",
		HeatSeeker = "HeatSeekerFx",
		Rewind = "RewindFx",
		TimeStop = "TimeStopFx",
		ChainLightning = "ChainLightningFx",
		Portals = "PortalsFx",
		SteelBall = "SteelBallFx",
		BlackFlash = "BlackFlashFx",
		BlackHole = "BlackHoleFx",
		GuangdongTiger = "GuangdongTigerFx",
	} :: { [string]: string },
	-- A table's effects are let go this long after its last shot ends with no ult armed (so a
	-- payoff can fade out); kit.keep holds them longer.
	LingerSeconds = 1.5,
	-- The kit's defaults: beams, sparks, lights.
	BeamWidthStuds = 0.06,
	BeamSegments = 10,
	SparkTexture = "", -- "" = Roblox's own sparkle
	ParticleSizeStuds = 0.1,
	ParticleLifetime = { 0.3, 0.6 }, -- seconds, min and max
	ParticleSpeed = { 2, 6 }, -- studs a second, min and max
	LightBrightness = 2,
	LightRangeStuds = 4,
	BurstRiseShare = 0.15, -- a burst light reaches its peak this share of the way in
	-- How long AbilityModels.get waits for the server to finish loading a model.
	ModelWaitSeconds = 5,
	-- The reach preview's full radius for an area ability whose look gives none (inches); the
	-- opponent's is this times Config.Ults.Shared.OpponentFactor.
	PreviewDefaultReachInches = 12,
	-- How the preview is drawn (its colours and transparencies: Config.Ults.Shared.Preview).
	Preview = {
		LiftInches = 0.12, -- over the cloth, just under the guideline (0.15)
		RingWidthStuds = 0.05, -- the soft outer ring
		InnerWidthStuds = 0.035, -- the dashed inner ring
		RingSegments = 24, -- arcs in a solid ring (fine enough to cut at the cushions)
		DashSegments = 20, -- dashes in the inner ring...
		DashShare = 0.55, -- ...each this share of its piece
		DashTurnSeconds = 12, -- the dashes creep round once in this long
		BeamSegments = 6, -- each arc's smoothness
		LightEmission = 0.6,
		ZoneTransparency = 0.72, -- Magnet's pocket zones: fainter than a reach ring
		OutlineBallWidths = 1.35, -- the red ring round an opponent ball in reach
	},
	-- SoundSheet (src/client/SoundSheet.luau).
	SoundSheet = {
		-- A one-shot counts as done this close to its end (seconds): the region's end is
		-- reached in frame steps.
		EndEpsilonSeconds = 0.03,
		-- A sheet clip is destroyed by its length plus this, whatever it reports (it may be
		-- waiting on the file).
		LoadGraceSeconds = 3,
		-- A library clip (its length unknown until loaded) is destroyed by this at the latest.
		LibraryMaxSeconds = 12,
	},
}

-- Table-wide screen effects (src/client/ScreenFx.luau; ABILITIES_PROMPT 5.2), seen by the
-- table's players and spectators only. (tune)
Config.UI.ScreenFx = {
	-- Its ScreenGui sits this far over the HUD's: under the cutscene (+8) and the menus (+10).
	DisplayOrderAbove = 6,
	-- A flash starts this see-through and clears; it peaks this share of the way in.
	FlashTransparency = 0.15,
	FlashRiseShare = 0.08,
	-- An overlay's default see-through at full weight, and its default fades (seconds).
	OverlayTransparency = 0.2,
	OverlayFadeSeconds = 0.15,
	SheetPx = 1024, -- a flipbook sheet's size in pixels when the spec gives none
	JitterSeconds = 0.06, -- a glitch overlay jumps this often
	-- Running effects are dropped this often once their table no longer involves the player
	-- (seat left, walked out of range; Time Stop's grade has no end of its own).
	InvolvedCheckSeconds = 0.5,
	-- The shake: noise this many cycles a second, and this much roll per stud of shake.
	ShakeFrequency = 18,
	ShakeRollDegreesPerStud = 4,
	FovRiseShare = 0.2, -- an FOV punch peaks this share of the way in
	FovMin = 20, -- the punch never takes the field of view outside these (degrees)
	FovMax = 110,
	-- Our camera offset is taken back off only if the camera still sits where we left it
	-- (within these), so a camera moved by something else is never yanked back.
	PoseEpsilonStuds = 0.001,
	PoseEpsilonDot = 1e-6,
	-- The inversion (Roblox cannot truly invert the 3D view): grey, contrast high, brightness
	-- up and a cold tint over a white flash reads as a blown-out negative.
	Invert = {
		Saturation = -1,
		Contrast = 1.2,
		Brightness = 0.35,
		TintColor = { 200, 225, 255 },
		FadeInSeconds = 0.05,
		FadeOutSeconds = 0.25,
		FlashColor = { 255, 255, 255 },
		FlashSeconds = 0.3,
	},
}

-- The ult spin screen (UltScreen and its parts UltSlots, UltOdds, UltBuy, UltFast,
-- UltSpinAnim, UltScreenParts; the stage UltStage and its aura UltAura; reference 09,
-- docs/prompts/ULTIMATES_PROMPT.md section 9). Full: a computer or tablet, laid out for a
-- DesignPx screen and scaled by the real one (ScaleMin..ScaleMax); Short: a phone on its side
-- (a screen under Multiplayer.Style.ShortHeight), laid out for 750 x 361. Text never goes
-- under the kit's minimum. (tune)
Config.UI.UltScreen = {
	DisplayOrderAbove = 10, -- its ScreenGui sits this far over the HUD's (with the menus)
	-- Other HUD ScreenGuis put away while the screen is open (PoolHud always is), by name.
	HideGuis = { "RankHud" },
	-- A popup on the screen (Odds, Buy spins, Auto Spin): its B over ContextActionPriority.High,
	-- above Menus' own B (+20), so B closes the popup first.
	PopupPriorityAbove = 30,
	-- The left column's 5th tile (MenuColumn), after the others. In the hub gamepad X opens it
	-- (overnight assumption: the D-pad's four directions are taken, and X is the ult button in a
	-- match, so X means "ult" everywhere).
	Column = { Name = "Ults", PadKey = "ButtonX" },
	TouchPx = 44, -- the smallest touch area (UI_STYLE 5)
	Full = {
		DesignPx = { 1280, 720 },
		ScaleMin = 0.75,
		ScaleMax = 1.5,
		MarginPx = 16, -- from the screen's edges
		GapPx = 10, -- between things in a group
		-- Top centre: "CURRENT ULT:", the name huge in its rarity colour, the description.
		TitleTopPx = 6,
		CurrentTextPx = 20,
		NameTextPx = 64,
		NameOutlinePx = 6, -- the name's thick ink outline
		NameIconPx = 72, -- the ability's icon left of the name, as tall as the name's row
		DescTextPx = 18,
		DescWidthPx = 600,
		-- Left: the three slot cards.
		SlotWidthPx = 190,
		SlotHeightPx = 112,
		SlotGapPx = 10,
		SlotNameTextPx = 22,
		SlotPillHeightPx = 30, -- EQUIPPED, SELECT or PURCHASE
		SlotPillTextPx = 18,
		SlotStripPx = 6, -- the rarity strip under the name
		-- The slot's ability icon, top left, the name and the strip to its right (at most down to
		-- the pill: it shrinks to fit a short card).
		SlotIconPx = 58,
		LockPx = 30, -- the lock toggle, top right
		-- Right: the odds (the Lucky odds switch, the rarity bars and their lists) and the code box.
		OddsWidthPx = 320,
		SwitchHeightPx = 34,
		BarHeightPx = 38,
		BarGapPx = 8,
		BarTextPx = 20,
		RowHeightPx = 28, -- one ult in an opened bar's list
		RowTextPx = 16,
		RowIconPx = 26, -- its ability icon, left of the name
		CodeTextPx = 18,
		CodeBoxPx = 40,
		RedeemWidthPx = 110,
		CodeNoteTextPx = 16,
		-- The code box on its own (the designer, 2026-09-28): centred in the room between the
		-- slot cards and SPIN, at most CodeCardWidthPx wide; with less than CodeCardMinWidthPx
		-- there it goes back under the odds.
		CodeCardWidthPx = 400,
		CodeCardMinWidthPx = 250,
		-- Bottom centre: LUCKY SPINS, SPIN, SPINS LEFT.
		LuckyWidthPx = 300,
		LuckyHeightPx = 42,
		LuckyTextPx = 20,
		SpinWidthPx = 300,
		SpinHeightPx = 84,
		SpinTextPx = 44,
		SpinsLeftTextPx = 22,
		-- Bottom left: BACK TO MENU.
		BackWidthPx = 230,
		BackHeightPx = 50,
		BackTextPx = 22,
		-- Bottom right: Pity, the money, the buy row.
		PityTextPx = 20,
		MoneyHeightPx = 34,
		MoneyTextPx = 22,
		BuyWidthPx = 88,
		BuyHeightPx = 46,
		BuyTextPx = 18,
		PriceTextPx = 16, -- the price over each buy button (and the crossed-out one over it)
		ToggleWidthPx = 58, -- each half of the R$ / $ toggle
		ToggleHeightPx = 34,
		-- VIP's Skip and Auto Spin, between BACK TO MENU and SPIN.
		FastWidthPx = 180,
		FastHeightPx = 40,
		FastTextPx = 18,
		-- A popup (Auto Spin here; Odds and Buy spins on a phone).
		PopupWidthPx = 440,
		PopupTitleTextPx = 22,
		PopupCloseInsetPx = 22, -- the red X's middle this far in from the card's corner
		PopupClosePx = 36,
		-- The buttons that open the Odds and Buy spins popups (phones only).
		OpenWidthPx = 150,
		OpenHeightPx = 40,
		OpenTextPx = 18,
	},
	Short = {
		DesignPx = { 750, 361 },
		ScaleMin = 1,
		ScaleMax = 1.25,
		MarginPx = 8,
		GapPx = 6,
		TitleTopPx = 4,
		CurrentTextPx = 14,
		NameTextPx = 32,
		NameOutlinePx = 3,
		NameIconPx = 40,
		DescTextPx = 14,
		DescWidthPx = 380,
		SlotWidthPx = 124,
		SlotHeightPx = 58,
		SlotGapPx = 6,
		SlotNameTextPx = 16,
		SlotPillHeightPx = 18,
		SlotPillTextPx = 14,
		SlotStripPx = 4,
		SlotIconPx = 30,
		LockPx = 22,
		OddsWidthPx = 380,
		SwitchHeightPx = 30,
		BarHeightPx = 32,
		BarGapPx = 6,
		BarTextPx = 16,
		RowHeightPx = 26,
		RowTextPx = 14,
		RowIconPx = 24,
		CodeTextPx = 16,
		CodeBoxPx = 36,
		RedeemWidthPx = 90,
		CodeNoteTextPx = 14,
		LuckyWidthPx = 200,
		LuckyHeightPx = 30,
		LuckyTextPx = 16,
		SpinWidthPx = 200,
		SpinHeightPx = 54,
		SpinTextPx = 30,
		SpinsLeftTextPx = 16,
		BackWidthPx = 150,
		BackHeightPx = 36,
		BackTextPx = 16,
		PityTextPx = 16,
		MoneyHeightPx = 26,
		MoneyTextPx = 16,
		BuyWidthPx = 84,
		BuyHeightPx = 40,
		BuyTextPx = 16,
		PriceTextPx = 14,
		ToggleWidthPx = 56,
		ToggleHeightPx = 32,
		FastWidthPx = 116,
		FastHeightPx = 34,
		FastTextPx = 16,
		PopupWidthPx = 420,
		PopupTitleTextPx = 18,
		PopupCloseInsetPx = 18,
		PopupClosePx = 30,
		OpenWidthPx = 116,
		OpenHeightPx = 36,
		OpenTextPx = 16,
	},
	-- LUCKY SPINS' green-to-teal gradient, left to right, over the green candy.
	LuckyFrom = { 61, 214, 107 },
	LuckyTo = { 30, 196, 196 },
	LuckyTintTransparency = 0.15, -- the teal end's tint (the green end shows the candy)
	-- The description on the dark stage: the kit's soft white (ink text would vanish there).
	DescColor = { 214, 226, 245 },
	PlaceholderTransparency = 0.25, -- a placeholder ult's name in a list ("Soon")
	LockOffTransparency = 0.6, -- the lock toggle while the slot is unlocked
	MythicShimmerSeconds = 2.4, -- Mythic's name and bar shimmer drifts once through its pastels
	-- The spin (section 9.4): the name at the top cycles through ult names, fast then slowing,
	-- ticking once per name, and lands on the result with its rarity sting.
	Spin = {
		Seconds = 2.5, -- the cycling, start to landing
		BuildFrom = "Epic", -- this rarity and up: a longer build-up before landing...
		BuildSeconds = 1.0, -- ...this much longer, with the reel's build-up whoosh
		FirstStepSeconds = 0.05, -- the first names change this fast...
		LastStepSeconds = 0.34, -- ...slowing to this just before landing
		StepPower = 2.4, -- how the steps slow: (t / Seconds) ^ StepPower (higher: a longer crawl at the end)
		FlashFrom = "Epic", -- this rarity and up: a screen flash on landing
		FlashTransparency = 0.2, -- the flash at its brightest
		FlashSeconds = 0.5, -- its fade
		ConfettiFrom = "Legendary", -- this rarity and up: confetti from the name
		ConfettiScale = 1.3,
		AutoStingFrom = "Rare", -- Auto Spin: only this rarity and up plays its sting (the rest tick)
		HintTextPx = { 14, 18 }, -- "Tap to skip" under the name (phone, computer)
		-- The tier ticking under the name in its colour, like a slot window (GUI lane, step 13,
		-- reference 10): it ticks with every name and slams on the result.
		TierTextPx = { 22, 30 }, -- (phone, computer) in the description's row; the hint goes under it
		TierGapPx = 4, -- between the tier word and the hint under it
		TierHoldSeconds = 1.6, -- it stays this long after landing, then the description returns
	},
	-- The stage (UltStage, section 9.2): the avatar where the player stands, the real world
	-- behind it (the designer, 2026-09-28), the camera cut there. Studs unless named.
	Stage = {
		-- Every player's character and name plate is hidden while the screen is open (this
		-- client only), checked again this often for anyone who respawns or joins.
		HidePlayers = true,
		HideRefreshSeconds = 0.5,
		GroundSearchStuds = 6, -- how far below the feet to look for the ground
		-- The camera's side: the player's camera's side first, then this many directions round;
		-- the first with ClearanceStuds of room past the camera, clear of the world, wins.
		ViewTries = 12,
		ClearanceStuds = 1.5,
		MinCameraStuds = 5, -- boxed in on every side: never closer than this
		FloorGlowStuds = 9, -- the soft glow on the ground under the avatar, in the aura's colour
		FloorGlowTransparency = 0.35,
		-- The camera: straight at the avatar, which fills FillShare of the view's height and sits
		-- a little low (LookUpShare of its height), under the title.
		FieldOfView = 34,
		FillShare = 0.6,
		LookUpShare = 0.14,
		SwayStuds = 0.12, -- the camera drifts this much, slowly, so the stage feels alive
		SwaySeconds = 7,
		-- Two small lights on the avatar (in its frame: x right, y up, z toward the camera),
		-- gentle: the world's own light does most of it.
		KeyLight = {
			Offset = { 5, 9, 9 },
			Brightness = 1.2,
			Range = 28,
			Angle = 70,
			Color = { 255, 244, 230 },
		},
		FillLight = {
			Offset = { -4, 4, 7 },
			Brightness = 0.4,
			Range = 18,
			Color = { 170, 190, 255 },
		},
		BounceStuds = 0.9, -- the avatar's hop as a spin lands
		BounceSeconds = 0.16, -- up (and the same back down)
		-- The idle when the character's Animate script names none (Roblox's defaults).
		IdleR15 = "rbxassetid://507766666",
		IdleR6 = "rbxassetid://180435571",
	},
	-- The aura (UltAura; JoJo style): the AuraFlame flipbook rising from the feet and round the
	-- body in the equipped ult's rarity colour (Kit.Rarity, unless Color), growing with rarity.
	Aura = {
		Tiers = {
			Common = { Scale = 0.7, Rate = 10, Transparency = 0.35, Light = 0.6 },
			Uncommon = { Scale = 0.85, Rate = 14, Transparency = 0.25, Light = 1 },
			Rare = { Scale = 1, Rate = 18, Transparency = 0.2, Light = 1.4 },
			Epic = { Scale = 1.15, Rate = 22, Transparency = 0.15, Light = 1.8, Sparks = 14 },
			Legendary = {
				Scale = 1.3,
				Rate = 26,
				Transparency = 0.1,
				Light = 2.2,
				Sparks = 18,
				Rays = true,
			},
			-- Red and black with crackling arcs (the brief's colours, not the card's pastel shimmer).
			Mythic = {
				Scale = 1.45,
				Rate = 30,
				Transparency = 0.1,
				Light = 2.6,
				Sparks = 22,
				Arcs = true,
				Color = { 255, 40, 60 },
				Dark = { 24, 0, 6 }, -- black flames behind the red
			},
		},
		LifetimeSeconds = { 0.7, 1.15 },
		RiseSpeed = { 1.5, 3 }, -- studs a second, times the tier's Scale
		RiseAcceleration = 5, -- upward, times Scale
		SizeStuds = 1.5, -- a flame at its biggest, times Scale
		LightEmission = 1,
		Brightness = 2,
		FeetWidth = 3.2, -- the patch the feet flames rise from, times Scale
		BodyWidth = 2.6, -- the box round the body the wisps rise from
		BodyDepth = 1.6,
		BackZOffset = -1, -- the flames drawn behind the avatar
		FrontZOffset = 0.6, -- a thinner layer in front
		FrontShare = 0.35, -- the front layer's rate, of the back's
		FrontTransparencyAdd = 0.3, -- and it is this much fainter
		SparkSpeed = { 4, 9 },
		SparkLifetimeSeconds = { 0.35, 0.7 },
		SparkSizeStuds = 0.35,
		RaysSizeStuds = 11,
		RaysRotSpeed = 18,
		RaysLifetimeSeconds = 5,
		RaysRate = 0.5,
		RaysTransparency = 0.55,
		ArcCount = 3, -- crackling arcs at once
		ArcPoints = 5, -- each a zig-zag of this many points
		ArcEverySeconds = 0.09, -- they jump this often
		ArcWidthStuds = 0.09,
		ArcJitterStuds = 0.45,
		ArcColor = { 255, 110, 130 },
		LightRange = 11, -- the aura's own glow on the avatar
		-- A spin landing: the aura bursts into the new colour.
		BurstCount = 40,
		BurstSpeed = { 10, 18 },
		BoostSeconds = 0.6, -- the flames run hotter this long
		BoostRate = 3, -- times the tier's rate
		BoostLight = 3, -- times the tier's light
	},
}

-- The aim-phase pick view (src/client/UltPick.luau; ABILITIES_PROMPT 5.2, 7.5, 7.9): the
-- shooter's top-down view while Heat Seeker's ball or Portals' two spots are owed. Pixels and
-- seconds; pairs { a, b } are a phone on its side (a screen shorter than
-- Multiplayer.Style.ShortHeight), then a bigger screen. The rings are placeholders until each
-- ability's look module draws its own (UltPick.onPicked / onPortals). (tune)
Config.UI.UltPick = {
	ZIndex = 25, -- over the pocket targets and the match HUD's lines, under the ability bar
	-- The title pill at the top: "TAP ONE OF YOUR BALLS", "PLACE PORTAL A" ... in the
	-- ability's rarity colour.
	TitlePx = { 34, 42 }, -- its height
	TitleTextPx = { 18, 24 },
	TitlePadPx = { 14, 20 }, -- room at each end of its words
	TitleGapPx = 8, -- under the top bar
	-- CONFIRM (green) and, for Portals, RESET (blue): stacked on the right edge, where the
	-- power bar sits while aiming (it is hidden meanwhile).
	ButtonWidthPx = { 124, 170 },
	ButtonHeightPx = { 44, 52 }, -- never under 44: the touch target
	ButtonTextPx = { 18, 20 },
	ButtonGapPx = 10,
	EdgeMarginPx = { 12, 24 }, -- from the screen's right edge
	-- The rings on the cloth, drawn on screen over the balls and the portal spots.
	HitPx = 44, -- the touch target round a ball or a portal, whatever its drawn size
	BallRingShare = 1.55, -- a pickable ball's ring, of the ball's size on screen
	MinRingPx = 26, -- never drawn smaller than this
	RingStrokePx = 3,
	RingInkPx = 2, -- the ink just outside the colour, so it reads on bright cloth
	RingColor = { 255, 255, 255 }, -- a ball you may pick, pulsing
	HoverColor = { 255, 204, 40 }, -- under the mouse or the gamepad's cursor
	PulseSeconds = 1.2, -- one breath of the pickable rings
	PulseGrow = 0.12, -- they grow by this share at the top of the breath
	PulseTransparency = 0.45, -- ...and fade to this at the bottom
	-- The lock-on placeholder on the picked ball (the real reticle is Heat Seeker's look).
	LockColor = { 255, 56, 56 },
	LockShare = 2.1, -- its size, of the ball's size on screen
	LockStrokePx = 4,
	LockDegreesPerSecond = 90, -- it turns slowly
	LockPopSeconds = 0.25, -- it closes in from LockPopGrow times its size when a ball is picked
	LockPopGrow = 1.8,
	-- The portals' placeholder rings: a flat disc with a coloured rim and its letter.
	PortalColorA = { 64, 224, 255 }, -- cyan (entry)
	PortalColorB = { 128, 104, 255 }, -- violet-blue
	PortalBlockedColor = { 255, 64, 64 }, -- a spot the server would refuse
	PortalRingBallWidths = 1.3, -- the ring's radius on the cloth, in ball widths (Portals' look check: 1 read small)
	PortalStrokePx = 4,
	PortalFillTransparency = 0.72,
	PortalLetterPx = { 16, 20 },
	PreviewTransparency = 0.45, -- a portal the gamepad is still moving, not yet placed
	-- Gamepad: the left stick moves a cursor (Heat Seeker) or the active portal.
	CursorInchesPerSecond = 40, -- at a full push, in table inches
	StickDeadZone = 0.2,
	StickCurve = 1.6, -- a small push moves finely
	CursorPx = 30, -- the cursor's ring (shown on a gamepad only)
	NavAcrossWeight = 2, -- D-pad: sideways distance counts this many times (as the pocket rings)
	PortalStartX = -25, -- portal A starts here on a gamepad (inches along the length, centre line)
	PartnerGapShare = 1.5, -- portal B starts at least this share of the minimum gap from A
	-- A CONFIRM the server has not answered in this long shows the view again.
	PendingSeconds = 3,
}

---------------------------------------------------------------------------------------------
-- Bots (the Bots lane, docs/prompts/BOTS_PROMPT.md; the designer, 2026-10-02). The brain is
-- src/shared/Bots (pure), the bodies and the table driver src/server/Bots. Every bot is a
-- negative seat id. (tune) on every number.
---------------------------------------------------------------------------------------------
Config.Bots = {
	-- One skill level per tier (Gold I and Gold V meet the same bot). The player's chance of
	-- beating the bot of their own rank (the designer's targets, for a typical player of that
	-- rank): Bronze 90%, Silver 80, Gold 65, Platinum 57, Diamond 50, Expert 50, Veteran 45,
	-- Master 40, Grandmaster 35, Reyes 30. tools/bot_duel.luau measures them; its table is in
	-- tools/bot_duel_results.json (tuned 2026-10-02 against the duel's model player of each
	-- rank, kept rising with the rank).
	--   Make: how often it lands a pot it goes for (else a near miss, never wild).
	--   Behind: added to Make while it has BehindBalls or more balls left than the opponent.
	--   Blunder: share of pot attempts played as a full-ball hit with no real angle (Bronze).
	--   Scratch: share of shots it scratches by accident when it can find such a shot.
	--   Position: how many of its best pots it compares for where the cue ball stops.
	--   Safety: with no pot, plays a real safety (else a soft hit on its nearest ball).
	--   PlaceSamples: ball in hand spots it weighs.
	Tiers = {
		Bronze = {
			Make = 0.08,
			Behind = 0.05,
			Blunder = 0.36,
			Scratch = 0.12,
			Position = 1,
			Safety = false,
			PlaceSamples = 4,
		},
		Silver = {
			Make = 0.3,
			Behind = 0.06,
			Blunder = 0.15,
			Scratch = 0.05,
			Position = 1,
			Safety = false,
			PlaceSamples = 6,
		},
		Gold = {
			Make = 0.45,
			Behind = 0.07,
			Blunder = 0.05,
			Scratch = 0.02,
			Position = 1,
			Safety = false,
			PlaceSamples = 8,
		},
		Platinum = {
			Make = 0.525,
			Behind = 0.08,
			Blunder = 0,
			Scratch = 0.01,
			Position = 2,
			Safety = false,
			PlaceSamples = 10,
		},
		Diamond = {
			Make = 0.545,
			Behind = 0.09,
			Blunder = 0,
			Scratch = 0,
			Position = 2,
			Safety = true,
			PlaceSamples = 12,
		},
		Expert = {
			Make = 0.555,
			Behind = 0.1,
			Blunder = 0,
			Scratch = 0,
			Position = 3,
			Safety = true,
			PlaceSamples = 14,
		},
		Veteran = {
			Make = 0.63,
			Behind = 0.08,
			Blunder = 0,
			Scratch = 0,
			Position = 3,
			Safety = true,
			PlaceSamples = 16,
		},
		Master = {
			Make = 0.71,
			Behind = 0.06,
			Blunder = 0,
			Scratch = 0,
			Position = 4,
			Safety = true,
			PlaceSamples = 18,
		},
		Grandmaster = {
			Make = 0.77,
			Behind = 0.04,
			Blunder = 0,
			Scratch = 0,
			Position = 4,
			Safety = true,
			PlaceSamples = 20,
		},
		Reyes = {
			Make = 0.975,
			Behind = 0.015,
			Blunder = 0,
			Scratch = 0,
			Position = 5,
			Safety = true,
			PlaceSamples = 24,
		},
	},
	BehindBalls = 2,
	MaxMake = 0.99, -- Make + Behind never passes this
	-- The shot finder (ported from the ability harness's model shooter): the thinnest cut,
	-- how far off a pocket's axis a ball may arrive, the object ball's speed at the mouth.
	Finder = {
		MaxCutDegrees = 78,
		CornerApproachDegrees = 60,
		SideApproachDegrees = 50,
		ArriveSpeed = 30, -- in/s
		MaxPower = 0.85,
		SafeSpeed = 60, -- the soft hit: cue ball in/s plus this per inch to go
		SafeSpeedPerInch = 1,
		CandidatesTried = 9, -- calibrations tried at most per decision
	},
	-- An "easy" pot (the ability policy's WhenNoEasyShot): its forgiveness score (radians of
	-- aim error the pot allows) at least this.
	EasyScore = 0.006,
	-- A shot it means to make: this much natural aim spread (degrees), checked in our physics
	-- (MakeTries draws) so the ball really drops.
	MakeAimSigmaDegrees = 0.12,
	MakePowerSigma = 0.04,
	MakeTries = 6,
	-- A near miss: the aim moved off the line by one of these (degrees, both sides tried,
	-- smallest first) until the ball stays up with no foul; one that stops within NearInches of
	-- the pocket is preferred.
	NearMissDegrees = { 0.7, 1.0, 1.4, 1.9, 2.5, 3.2 },
	NearInches = 12,
	-- The break in a bot-vs-bot game (the real player always breaks against a bot).
	BreakPower = { 0.88, 1 },
	BreakAimSigmaDegrees = 0.5,
	-- Safety search (Safety tiers): soft hits at its own balls, kept when legal, scored by how
	-- little the opponent is left.
	SafetyAngles = 9,
	SafetyPowers = { 0.25, 0.35, 0.45 },
	-- Blunder: a full-ball hit at this power.
	BlunderPower = { 0.35, 0.6 },
	-- Shot time: from the start of its turn to the strike, random in this range (seconds;
	-- the designer: never over 4), plus PlaceExtraSeconds with ball in hand. The same at every
	-- rank. The ability's cutscene is extra (it pauses the clock).
	ShotSeconds = { 2, 4 },
	PlaceExtraSeconds = 2,
	-- Lining up: the cue swings onto the line from SwingFromDegrees away, then drifts a few
	-- times by up to WiggleDegrees either side, settling on the line; the pull starts
	-- PullSeconds before the strike.
	Aim = {
		SwingFromDegrees = { 12, 35 },
		SwingShare = 0.35, -- of the lining-up time spent on the first swing
		Wiggles = { 2, 4 },
		WiggleDegrees = { 0.6, 2.5 },
		PullSeconds = 0.7,
		AimSendsPerSecond = 10, -- like a person's AimUpdate
	},
	-- Seat ids: the first bot is FirstSeatId, then one less each (clear of the QA fixtures).
	FirstSeatId = -1000,
	-- Looks (src/shared/Bots/Look.luau). A bot's cue comes from opening one of these lucky
	-- blocks (a Config.BlockOdds row) for its tier (a Legendary as rare as for a real player
	-- who opens the same block), or, TierCueChance of the time, the tier cue of its own tier
	-- or one below.
	CueBlock = {
		Bronze = "Standard",
		Silver = "Standard",
		Gold = "Standard",
		Platinum = "Standard",
		Diamond = "Rare",
		Expert = "Rare",
		Veteran = "Rare",
		Master = "Epic",
		Grandmaster = "Epic",
		Reyes = "Epic",
	},
	TierCueChance = 0.25,
	-- Its ability: weighted like a real spin (Config.Ults.Roll.Normal by rarity, then even
	-- within the rarity, built ones only); none rarer than CappedRarity while the real player
	-- is CapUpToTier or below (the designer: no Legendary or higher for Gold and below).
	CapUpToTier = "Gold",
	CappedRarity = "Epic",
	-- The PC robot (Play against PC, Fill with PC): Roblox's Bludroid bundle (196), picked by
	-- the designer from screenshots, 2026-10-02; the same body for every tier.
	Robot = {
		Torso = 136801229,
		LeftArm = 136800990,
		RightArm = 136801037,
		LeftLeg = 136801087,
		RightLeg = 136801165,
		Hats = "136801320", -- its dome head (an accessory)
		Icon = "rbxthumb://type=BundleThumbnail&id=196&w=150&h=150", -- its portrait
	},
	-- Disguised bots wear a real account's avatar (the designer, 2026-10-02): a random user id
	-- in this range (accounts made from 2020 on), kept only if the avatar loads and looks styled
	-- (below; a terminated account's comes back blank), never anyone in the server or the
	-- designer. The server keeps PoolSize looks ready.
	Avatars = {
		MinUserId = 1400000000,
		MaxUserId = 6000000000,
		PoolSize = 6,
		-- Most random accounts wear a starter look (measured in Studio 2026-10-02: of 60, 30
		-- wore one of three default outfits and 6 were blank), so a look must be styled: at
		-- least MinStyleItems accessories that are not face parts (eyebrows, eyelashes), a
		-- graphic T-shirt counting as one, and no StarterShirts top unless layered clothing
		-- covers it. About 1 look in 7 passes, so a look takes several lookups.
		TriesPerLook = 30,
		MinStyleItems = 2,
		StarterShirts = {
			144076358, -- Blue and Black Motorcycle Shirt (the "bacon hair" starter)
			144076436, -- the starter's other shirt (with Chestnut Bun)
			4047884939, -- My Favorite Pizza Shirt (a starter)
		},
		RetrySeconds = 0.25, -- between lookups (Roblox's web limits)
	},
	-- The global queue's safety net (the designer, 2026-10-02): real players first; a 1v1
	-- search with no real opponent after SoloSeconds gets a disguised bot of the player's own
	-- tier in an arena (its list names the bot), with no rematch. A team search waits
	-- TeamSeconds for an all-bot team (step 8). SoloSeconds went 10 -> 5 with the matchmaking
	-- bar's Play Global (designer, 2026-10-07): a lobby 1v1 search now meets its bot before
	-- Config.GlobalQueue.Window widens to anyone, so a real player far from the rank is skipped.
	Fallback = {
		SoloSeconds = 5,
		TeamSeconds = 25,
		WalkInStuds = 18, -- the arena bot walks this far in to its spot
		WalkInSeconds = 4, -- at most this long, then it is put there
	},
	-- Lobby bots (the designer, 2026-10-02; public lobby servers only, never a private server
	-- or an arena): the server looks like People people, so there are People minus the real
	-- players of them (none at People real players). They stroll, sit, wait on 1v1 pads and
	-- play each other there (one game, then they walk off), never at 2v2/3v3 tables. A real
	-- player can step onto a waiting bot's pad to play it (at its badge's level). They do not
	-- answer a real "needs an opponent!" (designer, 2026-10-07: Play Global is the way to a
	-- bot). When a real player joins, a bot leaves:
	-- idle ones first, then bot-vs-bot players, and one playing a real player only once the
	-- server holds People real players (its forfeit pays in full). In Studio they are off
	-- unless the designer's /lobbybots turns them on.
	Lobby = {
		People = 11,
		-- Their badges (weights, in this order): mostly Bronze to Gold, a few Platinum and
		-- Diamond, none above.
		Tiers = {
			{ name = "Bronze", weight = 30 },
			{ name = "Silver", weight = 30 },
			{ name = "Gold", weight = 25 },
			{ name = "Platinum", weight = 10 },
			{ name = "Diamond", weight = 5 },
		},
		TickSeconds = 1, -- how often the director looks
		JoinGapSeconds = { 3, 9 }, -- between one bot "joining" the server and the next
		-- What an idle bot does next (weights); Play needs a second idle bot and a table.
		Activities = {
			{ name = "Play", weight = 40 },
			{ name = "Wait", weight = 20 },
			{ name = "Sit", weight = 15 },
			{ name = "Stroll", weight = 25 },
		},
		MinFreeTables = 3, -- bot-vs-bot games start only while this many 1v1 tables stay free
		PlayShare = 0.6, -- at most this share of the lobby bots are in bot-vs-bot games
		MaxWaiting = 2, -- bots waiting on pads at once
		WaitSeconds = { 45, 120 }, -- a waiting bot gives up on its pad after this long
		SitSeconds = { 15, 45 },
		StrollPauseSeconds = { 4, 12 }, -- standing about between walks
		StrollSteps = { 1, 3 }, -- spots a stroll visits
		WalkTimeoutSeconds = 12, -- a walk that has not arrived by now is cut short
	},
	-- A bot's money for the player list (its Money attribute): a random amount in this range
	-- times its tier's place (Bronze 1 ... Diamond 5), so higher ranks look richer.
	Money = { 150, 1800 },
	-- One analytics event per real player per finished game against bots (AnalyticsService
	-- custom event; the Creator Dashboard's average value per tier is the real win rate):
	-- value 1 for a win, 0 for a loss; fields: bot kind, bot tier, player tier.
	Analytics = { Event = "BotMatch" },
	-- The tutorial's opponents (BotService.tutorialBot, tutorialSecondBot; the designer,
	-- 2026-10-02): the first wears a Silver badge and plays the script, the second a normal
	-- game; both play at Skill's level.
	Tutorial = {
		FirstTier = "Silver",
		SecondTier = "Bronze",
		Skill = "Bronze",
		JoinDelay = 2, -- seconds from Request opponent until it appears on the pad
	},
	-- Rematch answers. A PC robot says yes at once once the player has; a disguised lobby bot
	-- waits for the player, then answers after RematchDelay seconds, yes RematchAccept of the
	-- time; global-queue bots and the tutorial's second bot always say no.
	RematchDelay = { 1, 3 },
	RematchAccept = 0.85,
	-- A bot appears on its pad this long after it is called (Play against PC).
	PcArriveSeconds = 0.6,
	-- The server's thinking yields every this many simulations (spreads a turn over frames).
	YieldEvery = 4,
	-- Ball in hand: the cue ball is dragged to its spot over this long.
	DragSeconds = 1.4,
	-- The R15 animations a bot body plays (Roblox's default set).
	Animations = {
		Idle = "rbxassetid://507766388",
		Walk = "rbxassetid://507777826",
		Jump = "rbxassetid://507765000",
		Fall = "rbxassetid://507767968",
		Sit = "rbxassetid://2506281703",
	},
	WalkSpeed = 16,
	-- The tutorial bot's angry exit: it jumps, then is gone this long after (mid-air).
	AngryVanishSeconds = 0.35,
	-- A tutorial bot that lost normally (the player ran to the 8) leaves this long after.
	LeaveAfterSeconds = 2.5,
}

-- The first-time tutorial and the onboarding funnels (docs/prompts/TUTORIAL_PROMPT.md;
-- src/server/TutorialService.luau, src/client/Tutorial*.luau, src/shared/Tutorial/). (tune)
Config.Tutorial = {
	-- Rank rewards wait until the player claims them in Rank (designer, 2026-10-03), except
	-- these tiers' lucky blocks, given at once with the rank-up (Bronze's block follows the
	-- first win: the tutorial's Standard block, BronzeBlockKind).
	RankClaim = {
		BlocksAtOnce = { Bronze = true },
		MinGapSeconds = 0.5, -- one claim request at most this often per player (a double tap)
		-- The claim block over the roadmap (src/client/RankClaimBlock.luau), in pixels.
		Block = {
			DisplayOrderAbove = 1, -- over the roadmap's ScreenGui
			WidthPx = 560,
			MaxWidthShare = 0.94, -- of the screen's width at most (a phone)
			BottomGapPx = 24, -- from the screen's foot
			PadPx = 16,
			GapPx = 10,
			TitlePx = 30,
			ChipHeightPx = 40,
			ChipTextPx = 22,
			ChipGapPx = 8,
			RowGapPx = 8,
			ButtonPx = 52,
			ButtonWidthPx = 220,
			ReplyTimeoutSeconds = 5, -- CLAIM can be pressed again if no answer came
			ItemsAfterSeconds = 0.6, -- the drops and cues fly this long after the money
			StaggerSeconds = 0.15,
		},
	},
	-- The tutorial's tables and opponents (src/server/TutorialGames.luau).
	Games = {
		WatchSeconds = 0.25, -- how often the server looks at each tutorial player's table
		BotTries = 3, -- asks for the tutorial bot's look this many times before giving up
		BotRetrySeconds = 1,
		-- The bot storms off this long after the player's winning 8 drops, and the result
		-- waits until this long after that (designer: it vanishes before the result screen).
		ExitAfterDropSeconds = 0.25,
		ExitHoldSeconds = 1.5,
		-- Game 2: the global queue's search turns into the bot match after this long (a beat
		-- of "Finding you an opponent..."), not Config.Bots.Fallback.SoloSeconds.
		Game2BotAfterSeconds = 1,
		SearchRetrySeconds = 3, -- game 2's search starts by itself on the pad; a failed start retries after this
	},
	-- The real server's nudges (step 7, Steps.nudge): the server looks this often.
	Nudges = {
		WatchSeconds = 1,
	},
	-- Game 1's rigged rack and break (src/shared/Tutorial/Break.luau), found by
	-- `lune run tools/tutorial_break.luau` (designer, 2026-10-03: 3 solids down, a 4th left
	-- near a corner pocket). Inches and radians, table coordinates (+x towards the foot rail).
	Break = {
		Seed = 153, -- the rack's seed (Rack.newGame)
		CueX = -25, -- where the cue ball stands for the break
		CueY = -6,
		Angle = 0.115429, -- the break's direction (straight at the rack's apex)
		Power = 1, -- any pull plays the break at this power
		Solids = 3, -- the break pots exactly this many solids and nothing else
		-- The aim lesson's pot (Break.lesson): a cut no wider than this, the cue ball no
		-- farther than LessonMaxInches from the ghost ball; cost per inch of travel.
		LessonMaxCutDegrees = 20,
		LessonMaxInches = 45,
		LessonCostPerInch = 0.3,
		-- The search prefers a break that leaves the 8 this close to a pocket (by this much).
		EightNearInches = 20,
		EightNearBonus = 15,
	},
	-- The tutorial bot's later visits (Bots/Script.poor): weak, legal shots at its own balls
	-- that pot nothing and leave the player's balls and the 8 where they are.
	BotPoor = {
		Sweeps = 9, -- angles tried across each of its balls, thin hit to thin hit
		Powers = { 0.3, 0.42, 0.55 }, -- soft, so little else moves
		StillInches = 0.3, -- a ball that moved less than this counts as untouched
	},
	-- Game 1's lessons on screen (src/client/Tutorial.luau).
	Lessons = {
		AimOffsetDegrees = 7, -- the aim lesson starts this far off its pot: a small turn fixes it
		AimTurnedDegrees = 2, -- once the player has turned this much, the line says to shoot
		DragPx = { 170, -80 }, -- the ball-in-hand demo drags the ghost ball this far (px)
		BlockPadPx = 28, -- the ring round the thrown block on the floor, past its outline (px)
	},
	-- Game 1's rewards (answer 9): Bronze's at-once block is a Standard lucky block, thrown and
	-- opened in the tutorial (cases retired for blocks 2026-10-04).
	BronzeBlockKind = "Standard",
	BronzeCueRarity = "Uncommon", -- that block opens to a cue of this rarity (answer 9)
	-- The Equip step (designer 2026-10-03): once that cue is equipped, the Inventory stays open
	-- this long (its "Equipped" notice) before the tutorial closes it for the Rare block.
	EquipCloseSeconds = 1.2,
	SpinUlt = "Magnet", -- the one starter spin lands on this ability
	-- The art (tools/gen_tutorial_art.py; uploaded to the group, tools/upload_manifest_tutorial
	-- .json): the pointer hand (upright, index finger up; redrawn 2026-10-03 after the designer's
	-- "tap here" icon) and its tap lines, the mouse, the floor arrow after reference 02's path.
	Art = {
		Hand = "rbxassetid://71143067788609",
		HandRays = "rbxassetid://136125893092975", -- the tap lines, laid exactly over Hand

		Mouse = "rbxassetid://82136605713937",
		FloorArrow = "rbxassetid://103256796918925",
	},
	-- The screen layer (src/client/TutorialOverlay.luau). Pixels unless named.
	Overlay = {
		DisplayOrder = 40, -- over the HUD and menus, under the teleport screen
		PhoneBelowPx = 500, -- a screen whose short side is under this is a phone
		LineTextPx = 40, -- the instruction line (UI_STYLE 3: big white Fredoka, ink outline)
		LineHeightPx = 56,
		LinePhoneHeightPx = 40,
		LineWidthScale = 0.8, -- of the screen's width, at most LineMaxWidthPx
		LineMaxWidthPx = 900,
		LineTopGapPx = 10, -- under Roblox's top bar
		LineLowGapPx = 80, -- a low line clears a screen's own title (Heat Seeker's pick pill)
		LineNearGapPx = 80, -- a "Near" line's gap over the lit hole: clears the hand
		-- The light dim (designer, 2026-10-03: light): black at this transparency.
		DimTransparency = 0.65,
		DimFadeSeconds = 0.25,
		BeyondEdgePx = 600, -- the dim runs this far past every edge so none ever shows
		HolePadPx = 10, -- the lit hole's margin round a button
		RingThicknessPx = 4,
		RingColor = { 255, 214, 74 }, -- the house gold
		RingCornerPx = 18,
		RingPulse = 0.08, -- grows by this share at the top of each pulse
		RingPulseSeconds = 1.1,
		-- "Roblox_UI_Bright_Click" (Roblox, 0.37 s): a soft sound with each new line.
		Ding = { Id = "rbxassetid://15675059323", Volume = 0.35 },
		SkipHeightPx = 38,
		SkipPhoneHeightPx = 32,
		SkipWidthRatio = 4.2, -- the Skip button's width as a multiple of its height
		SkipEdgePx = 12,
		ConfirmSize = { 300, 150 },
		ConfirmTextPx = 22,
	},
	-- The hand (src/client/TutorialHand.luau). Pixels unless named.
	Hand = {
		TipX = 0.425, -- the fingertip in hand.png (pointing up), as a share of the image
		TipY = 0.18,
		SizeShare = 0.2, -- of the screen's short side, between MinPx and MaxPx
		MinPx = 90,
		MaxPx = 170,
		HoverPx = 6, -- the tip rests this far below a button's centre
		TapSeconds = 0.9, -- one tap (dip and squish) per loop
		TapDipPx = 12,
		TapSquish = 0.1,
		GestureTransparency = 0.35, -- the see-through demonstrations
		GestureSeconds = 1.8, -- one demonstration loop
		SwipeHeightShare = 0.62, -- the swipe's height on the screen
		SwipeWidthShare = 0.36, -- how far it swipes across
		MouseShare = 0.55, -- the mouse's size against the hand's
		GlyphHeightShare = 0.62, -- where a gamepad glyph shows
		GlyphShare = 0.6, -- the glyph's size against the hand's
		HoldBarPx = 10,
		StickSeconds = 1.4,
		StickDegrees = 18,
		StickShiftPx = 22,
		GhostBallShare = 0.32, -- the dragged ghost cue ball against the hand
		GhostBallTransparency = 0.45,
	},
	-- The floor arrow path (src/client/TutorialArrow.luau). Studs unless named.
	Arrow = {
		MaxArrows = 60,
		SizeStuds = 2, -- each arrow, square
		SpacingStuds = 2.1, -- close together, like reference 02's line
		SpeedStudsPerSecond = 3, -- how fast the line flows toward the pad
		LiftStuds = 0.06, -- above the floor
		FeetBelowRoot = 3, -- from the HumanoidRootPart to the floor
		StartGapStuds = 2, -- clear of the player's feet
		EndGapStuds = 1, -- stops just short of the pad's centre
		FadeStuds = 2, -- the arrows fade in and out over this at each end
		Transparency = 0.05,
		ImageTurnDegrees = 180, -- turns the image on its part so its arrow points along the route
		AgentRadius = 2,
		AgentHeight = 5,
		ReplanSeconds = 3,
		ReplanMovedStuds = 4,
	},
	-- The funnels (src/server/Funnel.luau; step 9). Each mask is a Flags entry, one bit per
	-- step, so a step is never logged twice.
	Funnel = {
		Print = true, -- Studio prints each logged step in the output (never live)
		OnboardingFlag = "Funnel",
		-- One-time funnels: the funnel's name on the dashboard -> its Flags key.
		Once = { TutorialExit = "FunnelExit" },
		ThirdMatch = 3, -- onboarding step 21: this many matches played
		EventGapSeconds = 0.5, -- a client's funnel report of one kind counts at most this often
		-- The repeating funnels' steps, in order (Funnel.shop, .spins, .blockLanded ...).
		Shop = { "Opened", "Viewed", "PressedBuy", "Bought" },
		Block = { "Got", "Ready", "Opened", "Equipped" },
		Spins = { "OpenedAbilities", "Spun", "Equipped", "UsedInMatch" },
	},
}

Config.Debug = {
	-- Test keys in play mode: B = rack and break (until rules handle new games).
	TestKeysEnabled = true,
	-- In Studio only: the Grand Opening deal (and with it the release sale and every Limited
	-- row) opens when the server starts, as if "/limited start" had been typed, so the Shop's
	-- Featured section is always there to look at. Live, Config.Shop.Deals' StartsAt rules.
	StudioOpening = true,
	-- The developer status line in the top-left corner. It is a readout of aim, speed and
	-- table counts, not part of the game, so it starts hidden and this key brings it in and
	-- out. Held as a string because Config is loaded by the Lune tests, which have no Enum;
	-- Main maps it. Keyboard only: it is a tool, not a feature that needs a phone path.
	ShowStatus = false,
	StatusKey = "F3",
	-- The lively Shop's motion spike (MotionSpike, docs/prompts/SHOP_LIVELY_PROMPT.md 7.1):
	-- a Studio-only test screen opened with PlayerScripts.GuiQA:Invoke("spike"), showing each
	-- way of moving slowly side by side at one speed, to pick the smooth one from video.
	-- Images from tools/gui/spike_art.py (uploaded to the group). (test tool)
	MotionSpike = {
		Pattern2x2 = "rbxassetid://80667987508003", -- the header tile 2 x 2 (1024 px, period 512)
		PatternTile = "rbxassetid://132770883034156", -- the same 512 px tile alone (Kit.PatternImage)
		PatternPeriod = 512, -- texels in one repeat of the tile
		PatternTilePx = 380, -- one tile shown this big (as Kit.PatternTilePx)
		PatternTransparency = 0.45, -- stronger than the menus' 0.7, so steps are easy to see
		ScrollPxPerSecond = 14, -- on each axis (45 degrees up-left); slow, where steps show most
		Ball = "rbxassetid://75662875722190", -- an 8-ball, 224 px inside 256 with a clear border
		BallBorder = 16, -- texels of clear border round the ball in its image
		BallPx = 72, -- the ball's size on screen
		FloatPx = 6, -- how far it floats up and down
		FloatSeconds = 3, -- one float, up and back
		BreatheScale = 0.05, -- how much it breathes (5%)
		BreatheSeconds = 2.4,
		PopEvery = 1.6, -- a pop test repeats this often
		Firework = "rbxassetid://137945828795312", -- the Firework Cue's 8 x 8 burst (128 px frames)
		FireworkFps = 30,
		Spark = "rbxassetid://131919576694289", -- Kit.Art.Spark, for the pooled particle burst
		Particles = 28, -- sparks in one burst
		ParticleEvery = 1.5, -- seconds between bursts
		-- The time code the measuring script reads (16 squares at the top, clear of Roblox's
		-- buttons on a phone).
		CodeX = 210,
		CodeY = 12,
		CodeCellPx = 8,
	},
	-- Developer chat commands (DevCommands): typed in the Roblox chat, checked on the server. Who
	-- may use them: only the user ids in UserIds (the designer, Painicane), in Studio and live.
	-- Anyone else's command does nothing. Their private answers are in
	-- Strings.Dev. The Studio hook ServerStorage.DevCommandsQA runs any of them from a script.
	Commands = {
		-- The light fades to day or sunset and holds there for the whole server; /cycle fades
		-- back into the running cycle (Config.Lighting.Cycle.Hold).
		Day = "/day",
		Sunset = "/sunset",
		Cycle = "/cycle",
		-- The commands that give things (by name): only the accounts in UserIds may use them,
		-- and the last word may name a player in the server to give it to instead
		-- (/givecue chalk dust 3 bob, /money 5000 @bob, /abilitysetup black hole bob).
		Gives = {
			"Rank",
			"Xp",
			"Money",
			"AddMoney",
			"GiveCue",
			"GiveBlock",
			"Spins",
			"Lucky",
			"Ult",
			"AbilitySetup",
		},
		-- Ranks and money, acting on the caller (or a named player: Gives) (DevCommands;
		-- `/rankhelp` lists them).
		Rank = "/rank", -- /rank gold 3 [xp] | /rank reyes | /rank unranked: set it (no rewards)
		Xp = "/xp", -- /xp 250: a gain through the real rules (peak, rewards, popups); never a loss
		Money = "/money", -- /money 5000: set money
		AddMoney = "/addmoney", -- /addmoney 100: add it, with the flying cash
		-- /result win|lose|draw|firstwin: preview the result screen (sample boosts; no save change);
		-- /result lose early|pocket|foul|off: a loss by that 8-ball rule (LOSS and why)
		Result = "/result",
		NewRank = "/newrank", -- /newrank [tier] [division]: preview NEW RANK! with its reward chips
		ResetData = "/resetdata", -- your own save back to a fresh one
		RankHelp = "/rankhelp", -- lists these
		-- The economy (DevCommands; `/econhelp` lists them), acting on the caller only (a sale
		-- and a Money Party are this server's, like the real ones).
		GiveCue = "/givecue", -- /givecue <id|name> [count]: never Classic or a Unique cue
		GiveBlock = "/giveblock", -- /giveblock <standard|rare|mystery ...> [count]: lucky blocks
		Cutscene = "/cutscene", -- /cutscene <rare|epic|legendary|mythic|secret>: the pull cutscene alone (nothing given)
		Inv = "/inv", -- prints your inventory privately
		ClearInv = "/clearinv", -- empties your cues (but Classic) and lucky blocks
		Dupes = "/dupes", -- DupeCopies copies of DupeKinds random Common and Uncommon cues
		SetDay = "/setday", -- /setday <1-7> [week]: the login streak's next claim
		NewDay = "/newday", -- as if a new UTC day began (daily claim, playtime, limits)
		Playtime = "/playtime", -- /playtime <minutes>: set today's minutes played
		Buy = "/buy", -- /buy <product> [purchaseId]: the receipt grant with a fake purchase id
		Vip = "/vip", -- /vip on|off: fake owning the VIP pass
		Party = "/party", -- starts (or extends) a Money Party
		Policy = "/policy", -- /policy restricted|normal: fake PolicyService's paid random items
		Restock = "/restock", -- this server shows a restock with that item until it ends
		Limited = "/limited", -- /limited start [minutes] | end | off: this server's Limited window
		Code = "/code", -- /code on|off <CODE> | /code list: a Live code in every server
		EconHelp = "/econhelp", -- lists these
		-- Ultimates, acting on the caller only (`/abilityhelp` lists them). Players call ults
		-- "abilities" (2026-09-28), so each command's name says ability; its old ult name in
		-- OldAliases still works (its TextChatCommand's second alias).
		UltBar = "/abilitybar", -- /abilitybar <0-100>: your bar at your table
		UltFull = "/abilityfull", -- fills your bar
		UltArm = "/abilityarm", -- fills your bar, arms your equipped ult at once (no cutscene wait)
		Spins = "/spins", -- /spins <n>: set the Ability Spins you hold
		Lucky = "/lucky", -- /lucky <n>: set the Lucky Spins you hold
		Pity = "/pity", -- /pity <n>: set pity (99: the next spin is the pity spin)
		FreeSpin = "/freespin", -- today's free spin becomes unused again
		Ult = "/ability", -- /ability <id|name>: any ult into your selected slot (no spin used)
		UltsAll = "/abilitiesall", -- /abilitiesall on|off: every ult rolls and plays for you (session)
		OpUlt = "/opability", -- fills the bars of the other side at your table (the QA opponent's)
		UltHelp = "/abilityhelp", -- lists these
		-- The look check's tools (Studio only, ABILITIES_PROMPT 5.6; also in /abilityhelp).
		-- /slowmo <scale>: every replay at your table plays at that rate for everyone watching
		-- (/slowmo or /slowmo 1: normal). It goes on the workspace attribute SlowmoAttribute
		-- followed by the table id, which every client reads (Main).
		Slowmo = "/slowmo",
		SlowmoMin = 0.05, -- the slowest rate accepted (Match.setTimeScale's floor)
		SlowmoMax = 4, -- the fastest rate accepted (Match.setTimeScale's ceiling)
		SlowmoAttribute = "ReplaySlowmo_",
		-- /hold <seconds>: every replay at your table stops at that shot time and stays there
		-- (a still frame of any moment to capture), until /hold alone releases it. It rides on
		-- the workspace attribute HoldAttribute followed by the table id, like /slowmo.
		Hold = "/hold",
		HoldMax = 40, -- the latest shot time accepted, seconds (Config.Physics.MaxShotSeconds)
		HoldAttribute = "ReplayHold_",
		-- /abilitysetup <id|name>: puts that ability in your selected slot, nothing more
		-- (2026-09-30). Only the accounts in UserIds may use it, in Studio and live.
		AbilitySetup = "/abilitysetup",
		-- /botrank <tier>: every bot you meet plays at that tier (Bots lane, for testing);
		-- /botrank off: your own tier again. Only the accounts in UserIds, Studio and live.
		BotRank = "/botrank",
		-- /lobbybots on | off | <count>: lobby bots in this server (on: as live, People minus
		-- the real players; a count: that many, like the tutorial's fake lobby). Studio starts
		-- with them off. Only the accounts in UserIds.
		LobbyBots = "/lobbybots",
		-- /solo: play the 1v1 pad you stand on by yourself (practice). /bot [tier]: play the
		-- computer there, at your tier or the one named. Temporary (designer, 2026-10-07): the pad
		-- lost its solo and PC buttons with the matchmaking bar. Only the accounts in UserIds.
		Solo = "/solo",
		Bot = "/bot",
		-- /tutorial reset | skip | off | step <name> (the tutorial lane): restart your tutorial
		-- from the arrow, end it as skipped, end it as done, or jump to a step (Tutorial/Steps
		-- .Order). Only the accounts in UserIds, Studio and live.
		Tutorial = "/tutorial",
		-- The ult commands' old names, by command: each still runs its command.
		OldAliases = {
			UltBar = "/ultbar",
			UltFull = "/ultfull",
			UltArm = "/ultarm",
			Ult = "/ult",
			UltsAll = "/ultsall",
			OpUlt = "/opult",
			UltHelp = "/ulthelp",
		},
		MaxAmount = 1e9, -- the largest /money, /addmoney or /xp amount accepted
		MaxGive = 100, -- the most copies one /givecue gives
		DupeKinds = 5, -- /dupes: how many different cues...
		DupeCopies = 3, -- ...and how many copies of each
		LineChars = 180, -- /inv packs its lists into chat lines of at most this many characters
		UserIds = { 544959133 }, -- the designer (Painicane) and nobody else, ever
	},
	-- Print physics events to the console.
	LogEvents = false,
	-- Print a timing line when a shot finishes playing back.
	LogPlayback = true,
	-- Print a line when the server turns a shot down. Noisy but useful while the net layer
	-- is new; a rejection is usually a race, not a cheat.
	LogRejectedShots = true,
	-- Warn when a client's replay of a shot does not land where the server said it would.
	-- This is the measurement that turns "float determinism is scary" into a number.
	LogChecksumMismatch = true,
	-- Largest slice of shot time simulated per rendered frame. A hitch must not fast-forward
	-- the shot, and it caps how much simulation one frame can ever be asked to do.
	MaxPlaybackStepSeconds = 0.1,
}

-- Font tests (FontTest; designer, 2026-10-05, while the font is still open): one place to try
-- a font on one screen, one part of a screen, or all of them. A font is
--   { Family = "rbxasset://fonts/families/<Name>.json", Weight = "<Enum.FontWeight name>" }
-- Family names: in Studio, pick any TextLabel and open its FontFace property's list (e.g.
-- FredokaOne, BuilderSans, BuilderExtended, Montserrat, Nunito, LuckiestGuy). Weights: Regular,
-- Medium, SemiBold, Bold, ExtraBold, Heavy; a font without that weight shows its nearest.
-- Example: Screens = { ShopMenu = { Family = "rbxasset://fonts/families/Nunito.json",
-- Weight = "Heavy" } }. Rejoin the playtest to see a change. (tune)
Config.UI.FontTest = {
	-- Every screen at once; nil keeps the kit's Fredoka One.
	All = nil :: { Family: string, Weight: string }?,
	-- One screen, by its ScreenGui's name, or one part of it as a path ("PoolHud/MoneyHud");
	-- a name ending in * takes every screen it starts ("Nameplate_*"). The most specific wins
	-- (a part over its screen over All). The screens: PoolHud (the main
	-- HUD; its parts MenuColumn, MoneyHud, HubCorners, HubCorners/Challenge,
	-- HubCorners/StarterPack, HubCorners/VipOffer...), RankHud, PlayerList, LuckyHotbar,
	-- ShopMenu, InventoryMenu, UltScreen (the Abilities page), FreeRewardMenu, RewardsMenu,
	-- SettingsMenu, TradeMenu, TradeInvite, RankClaimBlock, TutorialGui, TableSign,
	-- Nameplate_<user id>.
	Screens = {} :: { [string]: { Family: string, Weight: string } },
}

-- The Free Reward page (FreeRewardMenu; GUI lane, D4): join the group, favorite the game.
Config.UI.FreeReward = {
	CardMaxWidthPx = 380, -- one card at most this wide (two side by side when they fit)
	IconPx = { 72, 120 },
	TitlePx = { 20, 28 },
	RewardPx = { 22, 34 },
	LinePx = { 14, 17 },
	ButtonPx = { 44, 54 },
	-- After Roblox's favorite prompt says yes, look again this long for GetFavorite to agree.
	FavoriteCheckSeconds = 3,
}

-- The blur over the world behind menus, the roadmap, the lucky block reel, the match results
-- and NEW RANK! (ScreenBlur; designer, 2026-10-06, after a reference: "only blur it", in place
-- of every dark dim, a very quick fade "almost like a focus effect on a camera"). (tune)
Config.UI.Blur = {
	Size = 20, -- the BlurEffect's size at full blur (Roblox's 0 to 56)
	InSeconds = 0.2, -- the fade in as a screen opens
	OutSeconds = 0.2, -- and out as the last one closes
	-- The lucky block reel pops up this long after the blur starts, so its fade shows
	-- (designer, 2026-10-06: "starts to blur a bit earlier ... tenths of a second").
	ReelLeadSeconds = 0.15,
}

-- The hub's small corner buttons (HubCorners; GUI lane, C2): the Daily Challenge on the right
-- (flashing; says "Soon"), Invite and Roblox Plus beside the money HUD.
Config.UI.Corners = {
	ChallengePx = 70, -- the Daily Challenge target (a computer); a phone's is ShortChallengePx
	ShortChallengePx = 50,
	ChallengeRightPx = 14, -- from the right edge
	ChallengeYShare = 0.42, -- its middle this far down the screen
	ChallengeFlashSeconds = 1.2, -- one flash of its glow
	SmallPx = 46, -- Invite and Plus (a computer)
	ShortSmallPx = 38,
	SmallGapPx = 8, -- between them, and from the money HUD
	WordPx = 13, -- the word under each
	ShortWordPx = 11,
	BubbleSeconds = 2.5, -- the "Soon" bubble stays this long
	BubblePx = 16,
	-- The open offers (the Starter Pack, VIP's welcome offer) stand in a column under the
	-- Daily Challenge, each with its countdown: never a popup (designer, 2026-10-03).
	OfferPx = 58, -- each offer's icon (a computer)
	ShortOfferPx = 42,
	OfferGapPx = 26, -- under the challenge (room for its word) and under each offer's countdown
	TimerPx = 12, -- the countdown under each offer's word
	ShortTimerPx = 10,
}

-- Settings (SettingsMenu, src/server/Settings.luau; GUI lane, designer 2026-10-03, C10): each
-- switch and its default, saved in the save's Settings map; the moments a player has seen
-- once (so their Skip shows) saved in Flags as "Seen:<kind>".
Config.Settings = {
	Defaults = {
		Sfx = true, -- sound effects on
		LowFx = false, -- Lower effects (Quality: fewer particles, calmer UI loops)
		ShowFlag = false, -- show my country flag in the player list (off until turned on)
		ListOpen = false, -- the player list left open (designer 2026-10-07: folded until opened)
	} :: { [string]: boolean },
	Order = { "Sfx", "LowFx", "ShowFlag" }, -- the rows, top to bottom (the music is gone, 2026-10-03)
	-- Saved switches with no row on the Settings screen (the HUD remembers them).
	Hidden = { "ListOpen" },
	-- The kinds Seen may mark (anything else is refused).
	SeenKinds = { "Rare", "Epic", "Legendary", "Mythic", "Secret", "Result" },
	RequestBurst = 6, -- SettingsRequest: a burst, then this many a second (not design numbers)
	RequestPerSecond = 3,
}

-- The Settings screen (SettingsMenu) and its gear beside the rank HUD (GUI lane, C10).
Config.UI.Settings = {
	GearPx = 44, -- the gear (a computer); a phone's is ShortGearPx
	ShortGearPx = 44, -- as big as Roblox's top-bar buttons, in line with them (designer 2026-10-07)
	GearGapPx = 8, -- right of the rank HUD
	RowPx = { 54, 70 }, -- a switch row ({ phone, full })
	RowTextPx = { 17, 22 },
	SwitchPx = { 40, 48 }, -- the on/off switch's height (twice as wide)
	IconPx = { 30, 40 },
	CodeBoxPx = { 44, 52 },
	MaxWidthPx = 640,
}

-- The global boards (src/server/Leaderboards.luau; GUI lane, designer 2026-10-03, D9): Most
-- wins vs players and Highest rank, in OrderedDataStores (the one exception to "saves go
-- through the save layer": boards are not saves). Written from the server when a value
-- changed (at most once a WriteSeconds per player, and on leave), read about once a minute.
Config.Leaderboards = {
	Boards = {
		{ Key = "Wins", Store = "Board_WinsVsPlayers_v1", Attribute = "WinsVsPlayers" },
		{ Key = "Rank", Store = "Board_RankXp_v1", Attribute = "RankXp" },
	},
	StudioSuffix = "_Studio", -- Studio writes to its own stores
	Size = 50, -- the list's rows (the signs show the first SignRows)
	SignRows = 10,
	ReadSeconds = 60,
	WriteSeconds = 60,
	-- The lobby signs are off for now (designer, 2026-10-03: they looked ugly; a better place
	-- to be found). The boards still save and still show in the player list's tabs.
	SignsOn = false,
	-- The two lobby signs, built by code: either side of the spawn, a little toward the tables,
	-- each turned to face the spawn (a part's front is its -Z; yaw 180 faces +Z, the spawn).
	Signs = {
		{ Board = "Wins", X = -24, Z = 70, YawDegrees = -130 },
		{ Board = "Rank", X = 24, Z = 70, YawDegrees = 130 },
	},
	SignSize = { 12, 9, 1 }, -- studs: width, height, depth
	SignLiftStuds = 1, -- its bottom edge above the floor
	SignPixelsPerStud = 40, -- the SurfaceGui's resolution
	SignColor = { 27, 32, 51 }, -- the board's back and frame (Kit Ink)
	SignTitlePx = 40, -- the sign's title (SurfaceGui pixels)
	SignRowTextPx = 22, -- each row
	SignTopPx = 70, -- the rows start this far down
	SignPadPx = 30, -- the rows' side margins
}

-- The player list, flush in the top-right corner of Roblox's top bar row like Roblox's own list
-- (PlayerList; designer 2026-10-07): the Shop's lively header band, the rank badge and the
-- username, then Wins and Money columns. A computer's sizes, then a phone's (Short*: the HUD
-- screen under Multiplayer.Style.ShortHeight). Pixels.
Config.UI.PlayerList = {
	WidthPx = 360, -- a computer or tablet (designer 2026-10-07: long names need the room)
	ShortWidthPx = 230, -- a phone
	MinWidthPx = 176, -- squeezed this narrow at most to stay clear of the Settings gear
	AvoidGapPx = 8, -- kept between the gear (and its word) and the list's left edge
	RightPx = 8, -- in from the top bar row's right end (inside the safe area)
	-- The header band, tight round "Players (3)" (in the rank name's size) and centred on the
	-- same line as the rank HUD and Roblox's own top-bar buttons (designer 2026-10-07: the
	-- pill's 44 left too much space round the words). A phone's (not shown for now) is apart.
	HeaderPx = 30,
	TitleLeftPx = 10, -- "Players (3)" in from the header's left end
	ShortHeaderPx = 38,
	ShortTitlePx = 17,
	ChevronPx = 22,
	ShortChevronPx = 18,
	ColumnsPx = 18, -- the "Wins" and "Money" titles row at the top of the sheet
	ShortColumnsPx = 15,
	ColumnsTextPx = 13,
	ShortColumnsTextPx = 12,
	RowPx = 34,
	ShortRowPx = 27,
	BadgePx = 30,
	ShortBadgePx = 24,
	TextPx = 16,
	ShortTextPx = 14,
	WinsColumnPx = 42, -- the Wins column's width (numbers right-aligned, "1,234" fits)
	ShortWinsColumnPx = 40,
	MoneyColumnPx = 66, -- the Money column's width ("$999.99M", the widest with $123K, fits)
	ShortMoneyColumnPx = 64,
	CornerPx = 14, -- the card's rounded corners
	SheetCornerPx = 10, -- the white sheet's (the Shop's 22 is for a big panel)
	-- Open, it shows at most this many rows and scrolls past them (a part row peeks in so it
	-- reads as a scroller); a phone's list is smaller and ends above the Daily Challenge.
	MaxRows = 8.5,
	ShortMaxRows = 3.3,
	MaxHeightShare = 0.5, -- and never taller than this share of the screen's height
	YouTransparency = 0.55, -- your own row's pale blue highlight
	-- Every person in their own box (designer 2026-10-07): a white rounded card with a thin
	-- pale blue edge, a small gap between them.
	RowGapPx = 4,
	RowCornerPx = 8,
	RowStrokePx = 1.5,
	RowEdge = { 176, 216, 250 }, -- the edge (Kit.SheetEdge's light blue)
	RowHover = { 228, 241, 255 }, -- a box under the mouse
	ToggleSeconds = 0.15, -- the list opening or folding up to its header
	PopoutWidthPx = 220,
	PopoutButtonPx = 44,
	PopoutGapPx = 8, -- between the popout and the list
	FooterSeconds = 3, -- a trade invite's answer shows this long under the rows
	-- Disguised and tutorial bots show a fixed, believable "wins vs players" for their tier
	-- (D10): somewhere in { low, high }, picked from the bot's id so it never changes.
	BotWins = {
		Bronze = { 0, 12 },
		Silver = { 8, 40 },
		Gold = { 30, 110 },
		Platinum = { 90, 260 },
		Diamond = { 200, 520 },
		Expert = { 420, 900 },
		Veteran = { 800, 1500 },
		Master = { 1300, 2400 },
		Grandmaster = { 2200, 3800 },
		Reyes = { 3500, 6000 },
	} :: { [string]: { number } },
}

-- The rare-pull cutscenes (PullCutscene; GUI lane, designer 2026-10-03, C11d). After the reel
-- lands on a Rare or better cue, before its card: each rarity bigger than the last. Local only
-- for Rare and Epic; from Legendary up every other player in the server sees a light sky tint
-- (through the Unbox banner), never a camera or screen effect. One owner holds the camera, the
-- light and the sky (DayCycle is held) and puts them back exactly as they were on the end, a
-- skip, a second pull or a match starting. A kind can be skipped once it has been seen.
-- Seconds, studs and 0..1 shares. (tune)
Config.Cutscenes = {
	From = "Rare", -- pulls of this rarity and up get a cutscene
	RemoteFrom = "Legendary", -- and from this one up, everyone else in the server a sky tint
	DisplayOrder = 60, -- its screen over the lucky block reel (whose overlay hides while it plays)
	-- Every pull cutscene starts the same way (designer, 2026-10-05, Sol's RNG style): a second
	-- before the reel stops on a Rare or better, everything fades to black (the reel's last
	-- crawl plays on under it, so the prize is glimpsed, never seen to land), then the
	-- rarity's scene. The scenes not yet redone (Legendary and up) lift the black off as they
	-- begin.
	Black = {
		LeadSeconds = 1, -- the fade starts this long before the reel stops
		InSeconds = 0.6, -- the fade to black (designer 2026-10-05: was 0.35)
		OutSeconds = 0.3, -- an old scene lifting it off
		DisplayOrder = 70, -- its screen: over the scenes (60) and the lucky block's card
	},
	-- Rare (designer, 2026-10-05; still common, so it is short): a moment of black, a soft
	-- blue glow swells from the middle until the screen is blue while the riser builds, a
	-- white flash on the riser's peak, and the card is underneath as the white fades. No skip.
	Rare = {
		BlackSeconds = 0.4, -- held black after the fade (designer 2026-10-05: was 0.15)
		GlowSeconds = 0.52, -- the glow's swell from nothing to past the screen's corners (15% slower than 0.45)
		GlowEndScale = 2.4, -- its last size, of the screen's longer side
		GlowEasePower = 2.2, -- its growth: u^power (higher: a slower start, a faster burst)
		FillFrom = 0.55, -- a flat blue fills in behind it from this share of the swell...
		FillTo = 0.9, -- ...and covers the screen from this share
		Blue = { 40, 120, 255 }, -- the glow's edge and the fill
		Core = { 150, 210, 255 }, -- its bright middle
		CoreShare = 0.45, -- the bright middle's size, of the glow's
		FlashInSeconds = 0.06, -- the white flash snaps in on the riser's peak...
		FlashOutSeconds = 0.35, -- ...and fades off the card
		Riser = "RiserRare", -- Config.Audio.Ui: starts so its peak lands on the flash
		RiserPeakSeconds = 0.45, -- the riser's loudest moment, from its start
		Skippable = false, -- too short to need it
	},
	-- Epic (designer, 2026-10-05): the purple vortex. The bass hit and a longer riser start
	-- with the fade to black. In the black a ring pulses out on the bass; purple rays spin up
	-- and grow over a purple glow and haze while sparkles spiral in from the edges, a second
	-- pulse; then it all implodes into a bright point and bursts white on the riser's peak,
	-- the card under the white. No skip. Black.InSeconds + BlackSeconds + BuildSeconds +
	-- ImplodeSeconds = RiserPeakSeconds puts the flash on the peak with the riser starting at
	-- the fade.
	Epic = {
		BlackSeconds = 0.25, -- held black after the fade (the first pulse)
		BuildSeconds = 0.8, -- the vortex spins up and grows
		ImplodeSeconds = 0.33, -- and collapses into the point
		ImplodePower = 1.8, -- the collapse: 1 - v^power (higher: holds, then falls in fast)
		Purple = { 162, 89, 255 }, -- the rays, the glow and the pulses (the Epic colour)
		Haze = { 45, 12, 80 }, -- the dark purple that rises behind them...
		HazeShare = 0.85, -- ...this far over the black at its fullest
		Core = { 235, 215, 255 }, -- the bright point everything falls into, and the sparkles
		RaysEndScale = 1.25, -- the rays' last size, of the screen's longer side (their ends fade out)
		RaysTransparency = 0.35, -- at their brightest
		GlowEndScale = 1,
		CoreScale = 0.35, -- the core's size at the build's end, of the longer side...
		CorePointScale = 0.05, -- ...and as the point at the collapse's end
		SpinFrom = 40, -- the rays' spin, degrees a second, rising through the build...
		SpinTo = 520, -- ...to this, and faster still as it collapses
		Pulses = { 0.1, 0.5 }, -- rings out from the middle (scene seconds, on the bass)
		PulseSeconds = 0.7,
		PulseEndScale = 1.4, -- a ring's last size, of the longer side
		PulseTransparency = 0.2, -- at its start
		Sparks = 18, -- sparkles spiralling in (scaled by the quality setting)
		SparkSeconds = 0.6, -- one's trip from the edge to the middle
		SparkShare = 0.055, -- its size at the edge, of the longer side
		SparkSwirlDegrees = 120, -- how far round it turns on the way in
		FlashInSeconds = 0.08, -- the white burst on the riser's peak...
		FlashOutSeconds = 0.4, -- ...and its fade off the card
		Riser = "RiserEpic", -- Config.Audio.Ui
		RiserPeakSeconds = 1.98,
		Impact = "ImpactEpic", -- the bass hit, with the fade to black
		Skippable = false,
	},
	-- Legendary (designer, 2026-10-05): two parts. First a film: black bars come in (a wider
	-- picture) and the black fades up on the player while the "Logo Reveal" plays from its bass
	-- drop. The camera, close in, swings from their side round to their front; then low, looking
	-- up past them at a gold star gathering light high above; then from high in the sky looking
	-- down as a beam of gold light falls from the star and slams into them on the track's impact
	-- (sparks, a shockwave, a ground ring, a heavy shake), its light blinding the screen into
	-- the backdrop (white) as the rise starts. The second part: a pointed yellow star pulses up
	-- from nothing, then expands spinning faster and faster to fill the screen as the rise
	-- builds; a white flash on its peak with a cinematic hit, and the card under the white, a
	-- very faint ambience under it. Skippable once seen. (No sky effect: the designer dropped
	-- the gold aurora, 2026-10-05.)
	-- Scene seconds (from the end of the fade to black), studs, degrees and 0..1 shares.
	Legendary = {
		FadeInSeconds = 0.5, -- the black fades up on the first shot
		BarsShare = 0.12, -- each letterbox bar, of the screen's height
		BarsInSeconds = 0.5, -- they slide in during the fade...
		BarsOutAt = 0.5, -- ...and out once the warp is this far to the flash (designer 2026-10-05)...
		BarsOutSeconds = 0.5, -- ...over this long
		Gold = { 255, 196, 60 }, -- the beam, the star, the sparks (the Legendary gold)
		Light = { 255, 240, 190 }, -- the white-gold hottest parts (the beam's core, the star's centre)
		Grade = { -- the world's colour while the film plays (ColorCorrection)
			Brightness = -0.04,
			Contrast = 0.18,
			Saturation = -0.15,
			Tint = { 255, 236, 200 },
		},
		-- The camera. Every shot is clamped so it never passes through a table or a wall: it
		-- stops this far short of anything solid between the player and where it wants to be.
		CameraPadStuds = 0.6,
		FieldOfView = 55,
		Side = { -- shot 1: close in, from the player's side round to their front
			To = 1.7, -- it ends here (it starts with the scene)
			FromDegrees = 95, -- round from straight in front (0) to their side...
			ToDegrees = 14, -- ...and on to nearly their front
			FromStuds = 6.5, -- from the player, closing in
			ToStuds = 5.2,
			HeightStuds = 3.6, -- the camera's height above their feet
			LookHeightStuds = 3.4, -- it looks at this height on them (chest and face)
		},
		LookUp = { -- shot 2: low, looking up past the player at the star
			To = 3.3,
			Studs = 10, -- in front of them
			HeightStuds = 0.9,
			TiltShare = 0.5, -- where it looks between their shoulders (0) and the star (1), by angle
			PushStuds = 1.5, -- a slow push in through the shot
			FieldOfView = 90, -- wide, so the player and the star both fit between the bars
		},
		Overhead = { -- shot 3: from high in the sky, looking down for the hit (to the cut)
			HeightStuds = 30,
			Studs = 20, -- out in front of them, so the falling beam is seen coming in
			FromDegrees = -12, -- round from straight in front of them (designer 2026-10-05: was behind)
			LookHeightStuds = 6, -- it looks at this height above the player's feet
			DropStuds = 4, -- it sinks a little toward the hit
			TurnDegrees = 25, -- and turns slowly
			FieldOfView = 68,
		},
		-- The star the beam falls from: it gathers light from the second shot on.
		StarHeightStuds = 48, -- straight above the player
		StarFrom = 1.5, -- it starts to glow...
		StarFullAt = 3.15, -- ...and is at full size here
		StarStuds = 15, -- its glow's size at full (particles)
		GatherStuds = 32, -- light streams in toward it from a sphere this wide
		-- The beam: falls from the star and hits the player on the Logo Reveal's impact.
		ImpactAt = 3.83, -- the impact, 3.83 s into the track (designer 2026-10-05: 4.03 was late); the film follows the track's own clock
		DropSeconds = 0.45, -- the beam's fall from the star to the ground: a slam (designer 2026-10-05: was 1.3)
		DropPower = 1.5, -- its fall speeds up: u^power
		CoreStuds = 2.4, -- the bright core's width
		GlowStuds = 6, -- its glow
		HazeStuds = 16, -- and the faint haze round it
		SwellAfterHit = 1.6, -- every width swells this much at the hit
		Spirals = 2, -- ribbons of light that wind down round the falling beam
		SpiralStuds = 2.6, -- their distance from its middle
		SpiralTurnsPerSecond = 2.2,
		RingFrom = 2.9, -- a gold ring on the ground round the player, turning and growing
		RingStuds = 16, -- its size at the hit
		ShockSeconds = 0.55, -- the shockwave out along the ground after the hit
		ShockStuds = 70, -- its last size
		Sparks = 160, -- sparks thrown out by the hit (scaled by the quality setting)
		-- The hit shakes the camera hard (designer 2026-10-05: "way more physical"): a jolt down
		-- and back, then a heavy shake (move and roll) dying away; the falling beam rumbles it first.
		ShakeStuds = 2.2, -- the shake's size at the hit...
		ShakeSeconds = 1.2, -- ...dying away over this long
		ShakeRollDegrees = 7, -- its roll at the hit
		ShakeHz = 18, -- how fast it shakes
		KickStuds = 1.6, -- the jolt down at the hit
		RumbleStuds = 0.35, -- the falling beam's rumble, growing to the hit
		-- The hit's light blinds the screen, then it fades to the second part's backdrop
		-- (designer 2026-10-05).
		Glare = 0.92, -- the white-gold glare the hit floods the screen with (0..1)...
		GlareInSeconds = 0.12, -- ...this fast (was 0.06)
		ImpactHoldSeconds = 0.1, -- the blinding holds this long, then fades to the backdrop...
		FadeOutSeconds = 0.35, -- ...this fast (designer 2026-10-05: was a cut, then 0.9, 0.6, 0.35, 0.15)
		-- The second part's background: the designer is trying white (2026-10-05); black was
		-- { 0, 0, 0 }. On a bright one the warp's palest pieces turn deep gold so they still show.
		Backdrop = { 255, 255, 255 },
		WarpGold = { 255, 206, 0 }, -- the warp's yellow (designer 2026-10-05: brighter than Gold)
		DeepGold = { 255, 160, 0 }, -- its deeper yellow, for edges and the inner star
		RiseAfterHitSeconds = -0.2, -- the rise starts this long after the hit (negative: before it;
		-- 3.63 s in). Designer 2026-10-05: it came 1.1 s after the hit, then 0.1, then 0.3, too late.
		-- Part two, on the screen: the starlight warp.
		InterludeSeconds = 3.1, -- the rise's start to the flash (its peak lands on the flash); the
		-- warp shows from the black
		WarpStars = 70, -- streaks of light flying out from the middle (scaled by quality)
		WarpStreakShare = 0.2, -- a streak's length at the edge, of the screen's longer side
		WarpSpeedFrom = 0.35, -- the streaks' speed (screens a second), at the start...
		WarpSpeedTo = 2.2, -- ...and at the end
		Pillars = 5, -- vertical shafts of gold light sweeping across
		-- The star (designer 2026-10-05; Art.StarFlare: long thin vertical spikes, shorter
		-- horizontal ones, short diagonals): plain backdrop first, then it pulses up from nothing
		-- in the middle a few times, turning; then it stops pulsing and expands, spinning faster
		-- and faster, until it fills the screen on the flash.
		WarpHoldSeconds = 0.25, -- just the backdrop this long
		StarLight = { 255, 238, 150 }, -- the inner star and the hot core: a shade lighter than WarpGold
		StarPulses = 3, -- it pulses this many times...
		StarPulseHz = 2.6, -- ...this often...
		StarPulseShare = 0.22, -- ...at about this size, of the screen's longer side
		StarFillShare = 4, -- then expands to this size on the flash (its core fills the screen)
		StarExpandPower = 2.2, -- the expansion speeds up: share^power
		StarSpinPulse = 70, -- its spin while it pulses, degrees a second...
		StarSpinTo = 900, -- ...rising to this at the flash
		WarpGrowPower = 1.4, -- the rays, streaks and rings grow with the expansion: share^power
		-- How strongly the softer pieces show over a bright backdrop (they wash it out on white).
		BrightHaze = 0.2, -- the haze's most (0.6 on black)
		BrightPillars = 0.15, -- the light shafts' most (0.35 on black)
		BrightGlow = 0.55, -- the round glow's transparency (0 on black)
		FlashInSeconds = 0.08, -- the white flash on the rise's peak...
		FlashOutSeconds = 0.5, -- ...and its fade off the card
		-- Sounds (Config.Audio.Ui), each from the start of its moment.
		Logo = "LegendaryCinematic", -- with the scene (its bass drop at once, its impact at ImpactAt)
		Rise = "LegendaryRise", -- just after the hit (its peak 3.1 s in: the flash)
		Finale = "LegendaryHit", -- on the flash, over the card's own reveal sound
		Ambience = "LegendaryAurora", -- very faint, looping under the card; after it is closed...
		AmbienceTailSeconds = 1, -- ...it plays on this long...
		AmbienceFadeSeconds = 1.2, -- ...then tapers away over this long
		Skippable = true, -- once it has been seen
	},
	-- For the Mythic and Secret redo (designer, 2026-10-05): both also get the Legendary's bonus
	-- reveal sounds, the "Cinematic Hit" on the flash (Audio.Ui.LegendaryHit) and the faint
	-- angelic "Aurora" ambience under the card (Audio.Ui.LegendaryAurora, PullCutscene.cardClosed).
	Mythic = {
		Seconds = 4.6,
		SpaceInSeconds = 0.6, -- the sky turns to deep space
		Stars = 6000,
		Tint = { 225, 210, 255 },
		TintShare = 0.35,
		Brightness = 0.6, -- the light while in space
		RiseFrom = 0.4, -- the camera rises into the stars
		RiseSeconds = 2.4,
		RiseStuds = 40,
		AuroraBands = 4, -- pastel aurora ribbons high in the sky
		AuroraHeightStuds = 120,
		AuroraWidthStuds = 26,
		AuroraTransparency = 0.5, -- at a ribbon's middle (the stars show through)
		AuroraSpreadStuds = 160,
		DescendAt = 2.6, -- the cue comes down from the stars on a beam of light
		DescendSeconds = 1.4,
		CueSharePx = 0.42, -- the falling cue's size, of the screen's height
	},
	Secret = {
		Seconds = 5.6,
		GlitchSeconds = 1.6, -- red-white glitch blocks over the screen
		GlitchBlocks = 10,
		LightsFrom = 0.3, -- the map's lights go out one by one...
		LightsSeconds = 1.8,
		DarkBrightness = 0.05, -- ...down to this
		SilenceSeconds = 0.4, -- every other sound fades out this fast
		Heartbeats = { 2.2, 2.85, 3.5 }, -- a heartbeat in the silence
		ShockAt = 3.9, -- the shockwave
		ShockSeconds = 0.6,
		SpinSeconds = 0.9, -- the camera shakes and spins
		ShakeStuds = 0.6,
		SkyGlitchSeconds = 1.4, -- the sky flickers red and white (everyone in the server)
		FlickerHz = 9,
		RestoreAt = 5.0, -- the lights come back in one go
		Red = { 255, 40, 60 },
	},
	-- Others' pulls (Legendary and up): the sky tint only, never a camera or screen effect.
	Remote = { Seconds = 2.2, TintShare = 0.35 },
	-- The cutscene effects' own art (tools/gen_cutscene_art.py; white, tinted here).
	Art = {
		BeamEnergy = "rbxassetid://90134123684817", -- streaks running along a beam
		BeamSoft = "rbxassetid://98573532343624", -- a soft falloff across a beam
		LightStreak = "rbxassetid://114536414580559", -- one soft streak of light (the warp's streaks)
		StarFlare = "rbxassetid://84051192712402", -- a pointed eight-spike star (the Legendary warp)
	},
	HintAfterSeconds = 0.6, -- "Tap to skip" shows this late (only once the kind was seen)
	-- The 1v1 match result (ResultCutscene; GUI lane, C11a, D2; redone by the designer
	-- 2026-10-07): black letterbox bars slide in as the screen fades to black, then it fades
	-- back in on the sky and the camera tilts down into the player's own camera. Partway down
	-- the result screen opens (centred) and the bars slide away. Studs, degrees and seconds.
	Result = {
		FadeInSeconds = 0.35, -- to black (the bars slide in meanwhile)
		HoldSeconds = 0.15, -- black
		FadeOutSeconds = 0.45,
		PanSeconds = 1.55, -- the tilt from the sky down into the player's own camera (designer: 30% quicker)
		SkyLookDegrees = 20, -- it starts aimed this far above the horizon (sky with the map's tops in view)
		LiftStuds = 3, -- from this far above the player's camera...
		BackStuds = 3, -- ...and this far behind it, easing in as it tilts down
		ResultsAtShare = 0.45, -- the result screen opens this far through the pan
		BarsShare = 0.12, -- each letterbox bar, of the screen's height (as the Legendary's)
		BarsOutSeconds = 0.4, -- the bars slide away as the result screen opens
	},
}

-- Derived values (do not edit; change the fractions above)
---------------------------------------------------------------------------------------------
do
	local T = Config.Table
	local size = T.Sizes[T.SizeFeet]
	T.LengthInches = size.Length
	T.WidthInches = size.Width
	T.SurfaceHeightInches = T.SurfaceHeightStuds / T.StudsPerInch
	local D = Config.Balls.RadiusInches * 2
	Config.Balls.RenderRadiusInches = Config.Balls.RadiusInches * Config.Balls.RenderScale
	T.RailHeightInches = T.RailHeightBallFraction * D
	T.CushionHeightInches = T.CushionHeightBallFraction * D
	T.CornerMouthInches = T.CornerMouthBallFraction * D
	T.SideMouthInches = T.SideMouthBallFraction * D
	-- The opening is half the mouth wide; the centre sits half a mouth straight out from the
	-- mouth midpoint, so at fraction 1 the rim is tangent to the line joining the two noses
	-- and a lower fraction pulls the rim back, leaving a shelf of (mouth / 2) * (1 - f).
	T.CornerPocketRadiusInches = T.CornerMouthInches / 2 * T.PocketOpeningMouthFraction
	T.SidePocketRadiusInches = T.SideMouthInches / 2 * T.PocketOpeningMouthFraction
	T.SidePocketInsetInches = T.SideMouthInches / 2
	T.CornerShelfInches = T.CornerShelfBallFraction * D
	Config.Physics.CushionNoseHeightInches = Config.Physics.CushionNoseBallFraction * D

	-- Strike bands: power fractions -> the cue ball speeds SoundMix.pickBanded compares
	-- against. Same curve as Cue.speedForPower, which cannot be required from here (Cue
	-- requires Config), so it is spelled out from the numbers Config already owns.
	local C = Config.Cue
	local ratio = Config.Balls.MassOunces / C.StickMassOunces
	local elevation = math.rad(C.CueElevationDegrees)
	local k = 1 + ratio + 2.5 * math.sin(elevation) ^ 2
	local eta = ((1 - ratio * C.TipRestitution) ^ 2 + ratio * (1 + C.TipRestitution) ^ 2)
		/ (1 + ratio) ^ 2
	local gain = (1 + math.sqrt(1 - (1 - eta) / ratio * k)) / k * math.cos(elevation)
	C.MinStickSpeed, C.MaxStickSpeed = C.MinSpeed / gain, C.MaxSpeed / gain
	local function speedForPower(p: number): number
		return C.MinSpeed + (C.MaxSpeed - C.MinSpeed) * p ^ C.PowerCurve
	end
	local A = Config.Audio
	local soft = speedForPower(A.StrikeSoftUpToPower)
	local hard = speedForPower(A.StrikeHardFromPower)
	A.Clips.CueStrike[1].UpToSpeed = soft
	A.Clips.CueStrike[2].FromSpeed = soft
	A.Clips.CueStrike[2].UpToSpeed = hard
	A.Clips.CueStrike[3].FromSpeed = hard
end

return Config
