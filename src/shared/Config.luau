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
		[6] = { 20, 130, 70 }, -- green
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
		[6] = "rbxassetid://136578775839073",
		[7] = "rbxassetid://85399541656812",
		[8] = "rbxassetid://139487783589064",
		[9] = "rbxassetid://92953629012840",
		[10] = "rbxassetid://125354706638427",
		[11] = "rbxassetid://80865252504873",
		[12] = "rbxassetid://139601741020258",
		[13] = "rbxassetid://127747571775456",
		[14] = "rbxassetid://83778966609567",
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
	-- range 0.005-0.015, typical 0.010. Higher = balls stop sooner.
	RollingFriction = 0.010,
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
	-- Centre-hit horizontal target at full power. Designer chose one bar reaching 30 mph
	-- (528 in/s); TP A.30's impact gain derives the stick speed below. No separate break.
	MaxSpeed = 528,
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
	-- like it was on ice. MaxSpeed is a 30 mph BREAK; at the old 1.6 a half-pulled bar gave
	-- 184 in/s, which is a very firm real shot, and a ball struck that hard slides 128
	-- inches before it rolls - longer than the 100 inch table. So nothing ever rolled.
	-- At 2.6 the usable middle of the bar lands on real pool shot speeds: half power is
	-- 100 in/s and rolls after 25 inches, while the top of the bar is still a full break.
	-- (tune)
	PowerCurve = 2.6,
	-- Spin offsets are given in ball radii (-1..1). Hits beyond this miscue in real life.
	MaxSpinOffset = 0.5,
	-- Visual cue stick (placeholder built from parts), in STUDS so it matches the avatar. A
	-- true-scale 58 in cue would be 9.3 studs at this table's scale; the designer chose about
	-- 7 (2026-09-24), between that and the old 4.4 that looked like a toy next to an avatar.
	CueLengthStuds = 7,
	CueButtDiameterStuds = 0.2,
	CueTipDiameterStuds = 0.09,
	-- The drawn cue's shape, tip to butt (CueShape). Each row ends at To (a fraction of the
	-- length, ascending to 1) and is drawn Taper of the way from the tip diameter to the butt
	-- diameter (0..1, never decreasing); Look picks its colour. CueClearance keeps the same
	-- shape clear of the rail and the balls, so what is drawn is what is tested.
	Profile = {
		{ To = 0.012, Taper = 0, Look = "Tip" },
		{ To = 0.3, Taper = 0.1, Look = "Shaft" },
		{ To = 0.55, Taper = 0.36, Look = "Shaft" },
		{ To = 0.78, Taper = 0.73, Look = "Butt" },
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

	-- What a cue LOOKS like, as data. Segments run tip to butt, each a share of the length
	-- and a colour; the cue tapers linearly from TipWidth to ButtWidth. See CueArt.luau.
	--
	-- This is catalog data, not constants: a collectible cue is a row here plus a matching
	-- row in Config.Effects.Styles, which is what gives it its trail and pocket burst. The
	-- two are keyed by the same name on purpose, so one name picks a cue's whole identity.
	-- Roadmap 5.1 moves both into the real item catalog; until then everyone is on Classic.
	DefaultStyle = "Classic",
	Styles = {
		Classic = {
			-- The lengths add to 1 here for readability, but they are normalised anyway, so
			-- a hand-written row that adds to 0.98 still draws a whole cue.
			Segments = {
				{ Length = 0.015, Color = { 34, 44, 74 } }, -- leather tip
				{ Length = 0.02, Color = { 242, 238, 226 } }, -- ferrule
				{ Length = 0.48, Color = { 214, 176, 124 } }, -- maple shaft
				{ Length = 0.025, Color = { 176, 180, 188 } }, -- joint collar
				{ Length = 0.22, Color = { 86, 46, 34 } }, -- rosewood forearm
				{ Length = 0.015, Color = { 176, 180, 188 } }, -- ring
				{ Length = 0.17, Color = { 32, 32, 36 } }, -- linen wrap
				{ Length = 0.055, Color = { 20, 20, 22 } }, -- butt cap
			},
			-- Widths as a share of the widest point, so a style does not care about pixels.
			TipWidth = 0.42,
			ButtWidth = 1,
		},
	},
}

---------------------------------------------------------------------------------------------
-- The hub: where the sixteen tables stand (studs). Physics x -> world X, physics y ->
-- world -Z, up -> world Y, all turned by the table's yaw. See src/shared/Placement.luau.
---------------------------------------------------------------------------------------------
Config.Hub = {
	-- A grid on the baseplate until the hub map is chosen (designer, 2026-09-25): four rows of
	-- four, 26 studs apart across and 43 along. Across is the match fence's width (22 studs:
	-- the walkway plus the queue box along one long side, Placement.matchFence) and a 4 stud
	-- gap. Any table seats 1v1, 2v2 or 3v3; the host picks by who is in the box. Y is the
	-- FLOOR height the table stands on, not the cloth: Placement.toWorld adds
	-- Table.SurfaceHeightStuds (2.9) on top. Yaw is degrees about world +Y; at 90 the head
	-- rail faces world +Z, toward the spawn, and the queue box is on world +X.
	Tables = {
		{ id = 1, X = -39, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 2, X = -13, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 3, X = 13, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 4, X = 39, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 5, X = -39, Y = 0, Z = -43, YawDegrees = 90 },
		{ id = 6, X = -13, Y = 0, Z = -43, YawDegrees = 90 },
		{ id = 7, X = 13, Y = 0, Z = -43, YawDegrees = 90 },
		{ id = 8, X = 39, Y = 0, Z = -43, YawDegrees = 90 },
		{ id = 9, X = -39, Y = 0, Z = -86, YawDegrees = 90 },
		{ id = 10, X = -13, Y = 0, Z = -86, YawDegrees = 90 },
		{ id = 11, X = 13, Y = 0, Z = -86, YawDegrees = 90 },
		{ id = 12, X = 39, Y = 0, Z = -86, YawDegrees = 90 },
		{ id = 13, X = -39, Y = 0, Z = -129, YawDegrees = 90 },
		{ id = 14, X = -13, Y = 0, Z = -129, YawDegrees = 90 },
		{ id = 15, X = 13, Y = 0, Z = -129, YawDegrees = 90 },
		{ id = 16, X = 39, Y = 0, Z = -129, YawDegrees = 90 },
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
		LogoPlate = { Color = "rbxassetid://96049906872831", Roughness = "" },
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
	} :: { [string]: { [string]: { Maps: string, Tint: { number }? } } },
	-- The look every table uses unless LookByTable names another. Eventually the regular lobby
	-- (this place) is green and the pro lobby, a separate place, all blue (GDD section 16).
	DefaultLook = "Green",
	-- Table id -> look, for exceptions. For now the baseplate shows both (designer,
	-- 2026-09-25): the right half of the grid (X = 13 and 39, Config.Hub.Tables) is blue.
	LookByTable = {
		[3] = "Blue",
		[4] = "Blue",
		[7] = "Blue",
		[8] = "Blue",
		[11] = "Blue",
		[12] = "Blue",
		[15] = "Blue",
		[16] = "Blue",
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
	-- One shadow-casting spotlight over the table centre so balls get contact shadows.
	-- Needs Lighting.Technology = ShadowMap or Future in the place (set in Edit mode; it is
	-- a place property, not a script). (tune in the look pass)
	TableLight = {
		Enabled = true,
		HeightInches = 70, -- above the cloth
		Angle = 120, -- cone angle in degrees
		Brightness = 1.6,
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
	-- While a shot plays the camera holds the framing it was taken from, then pulls out to the
	-- whole-table view so every ball's path is visible, and eases back to the home view
	-- (View.ZoomDefault) when the balls stop.
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
		-- the line sits at 1.5 lengths, just above 35%. It was 0.5 (about 25%), which pulled
		-- out for shots that had nothing to show.
		--
		-- It is a BOUND on every ball, not just the cue ball - nothing leaves a collision
		-- faster than the ball that struck it - so this can hold the camera still on a shot
		-- where little happens, and never on one where something travels. OffScreenMargin
		-- above still overrides it: anything that does reach the edge pulls the camera out
		-- however gently it was hit. (tune)
		MinTravelTableLengths = 1.5,
		-- How long the pull-out to the whole table then takes, eased in and out of the move
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
		-- The right trigger is analog, so its position IS the power (ButtonR2 reports
		-- 0..1 in Position.Z). ButtonA is the fallback for pads with digital triggers:
		-- power ramps up while it is held, at this much per second.
		PowerRampPerSecond = 1.1,
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
	-- What each level draws (src/client/Guideline.luau). Corridor: the aim line to the ghost
	-- ball and its ring. Stubs: the object ball's line and the cue ball's deflection or rail
	-- bounce. Landings: where a jump shot comes down. The red X on a wrong target or an off
	-- table shot, and the glow on your own balls, stay on at every level.
	Levels = {
		Classic = { Corridor = true, Stubs = true, Landings = true }, -- every line (the default)
		Difficult = { Corridor = true, Stubs = false, Landings = false }, -- the aim line only
		Challenger = { Corridor = false, Stubs = false, Landings = false }, -- no lines at all
	},
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
	StubLengthInches = 8, -- 16 made aiming too easy, then 11 still did (2026-09-23)
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
	-- the cue ball leaves at up to 528 in/s, and the whole top half of the power bar spanned
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
	-- proportional (speed goes as power^2.6), so 25% of the bar is only 29 in/s out of 528
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

	-- VFX are CUE DATA, not constants. Every cue names a style here, so equipping a rarer
	-- cue changes the cue ball's trail and the burst when a ball drops - which per GDD
	-- section 12 is the main reason to want one. Roadmap 5.2 adds a row per rare cue; it
	-- must never need code. Until the catalog exists everyone uses DefaultStyle.
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
				WidthStuds = 0.34,
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
				CoreWhiten = 0.55, -- how far each layer's core runs toward white (dark balls still glow)
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
	},
}

Config.UI = {
	-- Spin selector: full-disc dragging, with 44 px Center/Done targets on small screens.
	Spin = {
		ToggleSizePx = 80, -- larger left-middle cue-ball button
		MarginPx = 12,
		ToggleMarginPx = 18,
		BallSizePx = 180, -- full white disc maps to the existing legal spin range
		ButtonSizePx = 44,
		GapPx = 8,
		PanelWidthPx = 280,
		TextSizePx = 16,
		DotSizePx = 36, -- selector marker, slightly smaller than the previous 39.6 px version
		IconDotSizePx = 17.6, -- retain the left toggle's smaller marker
		CornerRadiusPx = 12,
		OverlayTransparency = 0.9, -- only 10% dimming while spin is selected
		BallColor = { 244, 244, 236 },
		DotColor = { 220, 75, 70 },
		CenterColor = { 150, 154, 165 },
		-- Cue-angle slider beside the strike ball (jump shots, 2026-09-24). Tap or drag the
		-- track; the thumb shows the angle in degrees; top is the steepest.
		AngleColumnPx = 60, -- the slider's column, right of the ball
		AngleTrackWidthPx = 10,
		AngleThumbHeightPx = 30,
		AngleTrackColor = { 70, 74, 84 },
		-- A raised cue shows its angle under the left toggle, so it is never forgotten.
		AngleBadgeHeightPx = 22,
	},
	-- Power bar on the right edge of the screen. Height is a fraction of the screen, clamped.
	-- The power bar: a vertical panel on the right that you press and drag down, with the
	-- fill charging up behind it.
	--
	-- It sits HIGH rather than centred, because the cue drops a whole bar height below it at
	-- full pull and a centred bar pushes that off the bottom of the screen. The control
	-- needs room for the bar AND the cue hanging under it - about 1.97 bar heights all told -
	-- so the height fraction is set to leave that much below the top margin on any screen.
	PowerBarWidthPx = 52,
	PowerBarHeightFraction = 0.4,
	PowerBarMinHeightPx = 140,
	PowerBarMaxHeightPx = 300,
	PowerBarRightMarginPx = 18,
	-- To the TOP of the bar. The Leave button sits at the top right and runs to 52 px down,
	-- and the PULL label sits 28 px above the bar, so anything under about 0.13 puts the
	-- label behind that button. (tune)
	PowerBarTopFraction = 0.145,

	-- ...and a top-down cue lying INSIDE that bar, which slides down as you pull. The cue is
	-- drawn from Config.Cue.Styles, so the cue a player has equipped is the cue they pull
	-- back, and Roadmap 5.2 changes nothing here.
	PowerCueWidthPx = 15, -- at the butt, the widest point
	-- The cue nearly fills the bar at rest, and at full pull it slides a whole bar height -
	-- so it leaves the bar completely and hangs below it, which is what GamePigeon does and
	-- what makes a big pull look like a big pull. The bar deliberately does NOT clip its
	-- children, or the cue would be cut off at the bottom edge instead of travelling past it.
	PowerCueLengthScale = 0.97, -- of the bar's height
	PowerCueTravelScale = 1.0, -- of the bar's height, at full pull
	-- Slices used to draw the taper. A Frame cannot be a trapezoid, so the cue is built
	-- from thin bands; enough of them and the steps disappear. (tune)
	PowerCueSlices = 44,
	-- Colours (RGB 0-255).
	Accent = { 255, 205, 60 },
	Panel = { 20, 20, 24 },
	PanelTransparency = 0.35,

	-- The shared UI kit (src/client/HudParts.luau): the one look every screen is built from.
	-- docs/UI_STYLE.md; the designer's choices of 2026-09-25: white panels with a thick ink
	-- outline, a soft shadow and a faint pool-ball pattern; raised candy buttons in traffic
	-- colours; glossy cartoon icons. Colours are RGB 0-255.
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
		PanelCornerPx = 18, -- panel corner radius
		PillCornerPx = 999, -- pills are fully round at the ends
		-- The shadow under panels: a 9-slice blurred square (tools/gen_ui_art.py shadow.png).
		ShadowImage = "rbxassetid://73622387505906",
		ShadowSlice = { 48, 48, 80, 80 }, -- SliceCenter in the 128 px image, pixels
		ShadowSpreadPx = 14, -- reaches this far past the panel on every side
		ShadowDropPx = 6, -- and sits this far lower, as if lit from above
		ShadowTransparency = 0.72, -- 0.5 read as a dark smear under a small panel (tune)
		-- The faint pool-ball pattern over every panel (pattern.png, tiled).
		PatternImage = "rbxassetid://123651371748115",
		PatternTilePx = 88, -- one 256 px tile of eight balls shown this big
		PatternColor = { 74, 123, 192 }, -- pale blue marks
		PatternTransparency = 0.92, -- about 8% strength: felt, not seen (tune)
		-- Text: Fredoka One, white, outlined in ink. Sizes are pixels; nothing goes below Min
		-- except ball numbers, which are part of the ball graphic.
		Text = { Title = 40, Heading = 28, Button = 24, Body = 18, Min = 16 },
		TextOutlineRatio = 0.1, -- outline thickness as a share of the text size
		TextOutlineMinPx = 2, -- never thinner than this
		-- Raised candy buttons: a light top, the colour, then a darker lip along the bottom.
		Buttons = {
			Green = { Top = { 140, 240, 160 }, Mid = { 61, 214, 107 }, Lip = { 30, 150, 70 } },
			Red = { Top = { 255, 150, 150 }, Mid = { 255, 77, 77 }, Lip = { 196, 38, 56 } },
			Blue = { Top = { 150, 206, 255 }, Mid = { 59, 155, 255 }, Lip = { 31, 104, 208 } },
			Yellow = { Top = { 255, 236, 150 }, Mid = { 255, 201, 40 }, Lip = { 214, 145, 0 } },
			Grey = { Top = { 222, 227, 236 }, Mid = { 186, 194, 208 }, Lip = { 132, 142, 160 } },
			White = { Top = { 255, 255, 255 }, Mid = { 244, 248, 255 }, Lip = { 190, 206, 230 } },
		},
		ButtonLipShare = 0.18, -- the lip is this share of the button's height
		ButtonStrokePx = 3, -- ink outline
		ButtonCornerPx = 14,
		ButtonIconShare = 0.62, -- an icon on a button is this share of its height
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
			Person = "rbxassetid://134579193841579", -- Play solo
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
			Sliders = "rbxassetid://72906258640929", -- fine controls
			Classic = "rbxassetid://77520789288930", -- difficulty: every line
			Difficult = "rbxassetid://96329200527250", -- difficulty: the aim line only
			Challenger = "rbxassetid://111544414092808", -- difficulty: no lines
		},
		Art = {
			BallGloss = "rbxassetid://109282983367810", -- shading and shine over a HUD ball
			BallBand = "rbxassetid://118056017631758", -- a stripe's band, clipped round, tinted
			Rays = "rbxassetid://112352358460844", -- spinning behind the win trophy
		},
		-- Rarity colours (UI_STYLE section 4), for the shop and inventory later.
		Rarity = {
			Common = { 156, 163, 175 },
			Uncommon = { 61, 214, 107 },
			Rare = { 59, 155, 255 },
			Epic = { 162, 89, 255 },
			Legendary = { 242, 178, 0 },
			Unique = { 255, 92, 184 },
		},
		-- src/client/UIAnim.luau. Things pop in with a little overshoot; only important things
		-- shine or bounce (designer, 2026-09-25).
		Motion = {
			PopSeconds = 0.32, -- pop in
			PopFromScale = 0.6, -- from this size
			OutSeconds = 0.14, -- pop out, quicker
			SlideSeconds = 0.25,
			SlidePx = 24, -- how far a slide travels
			ShineSeconds = 0.7, -- one shine sweep across a panel or button
			PulseSeconds = 0.9, -- one breath of a pulsing button
			PulseScale = 1.05, -- how big it breathes
			BounceScale = 1.2, -- a pocketed ball's pop
			RaysDegreesPerSecond = 30, -- the win card's rays
		},
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
	-- On the baseplate in front of the table grid (Config.Hub.Tables), facing it: the green
	-- tables on the left, the blue on the right. Y is the SpawnLocation's centre.
	Spawn = { X = 0, Y = 0.5, Z = 29, YawDegrees = 0 },
	CoinSeconds = 2.6, -- shared coin presentation; the host's Start leads straight into it
	IntroSeconds = 2, -- new shooter introduction, early shots permitted
	PlacementSeconds = 15, -- cue-ball placement window (break and ball in hand)
	PocketChoiceSeconds = 10, -- called-pocket selection window
	ShotSeconds = 20, -- aiming deadline
	FoulSeconds = 1.4, -- foul announcement before incoming turn
	ResultSeconds = 2.8, -- outcome hold before table reuse
	PocketSettleSeconds = 1, -- extra settling after a pocket
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
	PlacementCommitIdleSeconds = 0.35, -- button nudges send one reliable Place after this pause
	BreakAxisMinComponent = 0.35, -- break arrows follow screen-right unless the line runs nearly vertical on screen
	-- One long box along a long side of every table (designer, 2026-09-25). Up to six step
	-- in; the first in is the host, who picks the difficulty and presses Start. Two play 1v1,
	-- four or six split into the box's two halves, one team each (Placement.queueBox).
	Queue = {
		Capacity = 6, -- players in one box: up to 3v3
		BoxLengthStuds = 18, -- along the table's length, six abreast
		BoxDepthStuds = 4, -- out from the table
		BoxGapStuds = 0.5, -- from the walkway's edge (Fence.HalfWidthStuds) to the box
		-- Which long side: the sign of physics y. -1 puts it on world +X at yaw 90, the right
		-- of each table as you walk in from the spawn.
		Side = -1,
		SideHysteresisStuds = 0.4, -- past the middle line by this much before your half changes
		FenceMarginStuds = 0.5, -- the match fence stands this far beyond the box
		-- The server checks who is in each box this often, rather than using .Touched, which
		-- misses a player who walks in and stands still.
		PollsPerSecond = 5,
		DwellSeconds = 0.35, -- inside the box this long before you join: walking across does not
		ExitGraceSeconds = 0.5, -- outside it this long before you leave: forgive edge jitter
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
		-- fence is the walkway grown to take in the queue box (Placement.matchFence).
		HalfLengthStuds = 13,
		HalfWidthStuds = 8.5,
		ThicknessStuds = 1, -- wall thickness
		EscapeStuds = 2, -- a participant this far outside (clipped through) is put back inside
	},
	-- The shooter's root on the server (TableService). While they aim, the anchored root
	-- follows ShooterStance, so a late joiner or a far table sees the shooter at the table; at
	-- the shot it goes exactly to the stance spot. Each client poses the body itself.
	Stance = {
		ServerMovesPerSecond = 5, -- while aiming, the root follows the aim at most this often (constrain runs at Pad.PollsPerSecond, so more has no effect)
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
	PrecisionPlaceInches = 1, -- cue-ball button step
	PrecisionAimDegrees = 0.5, -- fine aim button step
	PrecisionPowerStep = 0.05, -- button alternative to power drag
	PrecisionPowerDefault = 0.4, -- initial discrete power
	MaxReplayStepsPerFrame = 32, -- bounded catch-up work per visible table
	SnapshotIntervalSeconds = 2, -- recover late/missed client subscriptions
	YourTurnSound = "rbxassetid://120722072794939", -- user supplied; preload verified
	FoulSound = "rbxassetid://128802141795458", -- user supplied; preload verified
	CoinSound = "rbxassetid://7022812395", -- Creator Store coin flip; preload verified
	UISoundVolume = 0.35, -- quiet underneath physical impact mix
	QueueVisual = {
		BoxHeight = 0.12, -- thin floor strip, studs
		FloorOffset = 0.08, -- avoid baseplate z-fighting, studs
		PixelsPerStud = 40, -- sharp floor labels without large canvases
		FrameTransparency = 0.35, -- dark label backing
		CornerPixels = 24, -- rounded floor strip corners
		EdgePixels = 4, -- softly pulsing outline thickness
		EdgeTransparency = 0.15, -- brightest edge phase
		GradientRotation = 45, -- subtle diagonal surface highlight
		GradientMin = 0.05, -- first gradient stop transparency
		GradientMax = 0.5, -- last gradient stop transparency
		LightBrightness = 0.35, -- bounded ambient surface glow
		LightRange = 5, -- local box lighting, studs
		EmptyTransparency = 0.18, -- the box's white footprint
		LabelInset = 0.18, -- floor words keep this share of the strip clear at each edge
		FloorTextSize = 40, -- the largest the floor words scale to, pixels
		LabelRotation = 90, -- floor words lie along the box, upright from outside it (90 or -90)
		HalfGapStuds = 0.3, -- the two halves stop short of the middle and the edges by this
		HalfLiftStuds = 0.02, -- halves float this far over the box, so they never z-fight it
		HalfTransparency = 0.25, -- a shown half
		HalfBackingTransparency = 0.8, -- its label panel lets the grey or green show through
		HalfUneven = { 150, 156, 166 }, -- grey: the halves do not hold half each yet
		DividerStuds = 0.2, -- the line between the halves
		DividerTransparency = 0.1, -- shown with the halves
		PanelOffset = 6.5, -- floating panel above the box, studs
		PanelWidth = 240, -- readable mode/host panel, pixels
		PanelHeight = 104, -- fixed panel height, pixels
		PanelMaxDistance = 90, -- avoid distant billboard clutter, studs
		PanelTransparency = 0.08, -- readable dark backing
		ModeLabel = { 1, 0.35, 0, 0.04, 24 }, -- panel headline layout
		HostLabel = { 0.9, 0.25, 0.05, 0.42, 14 }, -- quiet host label
		StatusLabel = { 1, 0.25, 0, 0.7, 16 }, -- occupancy/status line
		VerticalTolerance = 6, -- a box cannot seat someone on a different floor, studs
		AreaMargin = 1, -- the queue area around the box: leaving it starts the exit grace
		FallTolerance = 5, -- recover a falling participant below the table area
		RespawnHeight = 3, -- safe standing root height above baseplate, studs
		RespawnBoundaryInset = 1, -- keep respawns inside confinement, studs
		-- Somebody in the box (src/client/BoxEffects.luau). (tune)
		EdgeBaseTransparency = 0.15, -- box outline at rest
		EdgePulseAmplitude = 0.1, -- box outline breathing
		FadeInSeconds = 0.25, -- how fast the whole effect lights up and fades out
		MoteTexture = "rbxasset://textures/particles/sparkles_main.dds", -- built-in sparkle
		MoteRate = 30, -- light motes per second while occupied, over the whole box
		MoteBurst = 40, -- motes thrown up on arrival
		MoteSize = 0.5, -- studs, shrinking to nothing
		MoteLifetime = { 0.8, 1.4 }, -- seconds
		MoteSpeed = { 3, 6 }, -- studs per second, upward
		MoteSpreadDegrees = 8, -- nearly straight up
		GlowRange = 10, -- studs
		GlowBrightness = 1.4, -- steady glow while occupied
		GlowBurstBrightness = 5, -- arrival flare
		GlowBurstSeconds = 0.6, -- flare settling time
		FrameThicknessStuds = 0.16, -- rising scan frame round the box
		FrameRiseStuds = 7, -- how high it climbs before vanishing
		FrameRiseSeconds = 1.1, -- climb time
		FramePeriodSeconds = 1.6, -- one frame every this often
		JoinSound = "rbxassetid://131677760492710", -- Creator Store "Beacon SFX" power-up; loads in this experience, listening pending
		JoinSoundVolume = 0.5, -- heard around the box, not across the room
		JoinSoundMinDistance = 8, -- studs at full volume
		JoinSoundMaxDistance = 60, -- studs until silent
	},
	Style = {
		PanelTop = { 36, 42, 51 }, -- gradient upper tone
		Active = { 92, 223, 157 }, -- current shooter and legal placement
		Danger = { 242, 104, 112 }, -- foul and low clock
		Selected = { 91, 177, 255 }, -- selected pocket
		Disabled = { 77, 84, 94 }, -- inactive ball/portrait fill
		Radius = 12, -- component corner radius in pixels
		PressedScale = 0.97, -- small button press response
		PanelEntranceScale = 0.97, -- restrained modal/result entrance
		QuickMotion = 0.15, -- hover transitions in seconds
		Motion = 0.25, -- status and ball emphasis in seconds
		PulsePeriod = 1.8, -- local queue/pocket pulse period
		HeaderMargin = 10, -- outer safe-area margin
		HeaderGap = 8, -- spacing between panels and rows
		HeaderTop = 6, -- minimal spacing at the upper screen edge
		HeaderHeight = 80, -- the top bar's cards: a portrait with its name under it
		HeaderCenterWidth = 372, -- the status card: phase icon, status, clock and Leave
		ClockTextSize = 20, -- the shot clock in its pill
		ClockPillWidth = 72, -- the clock pill, pixels
		ClockPillHeight = 28,
		LeaveWidth = 104, -- the red Leave button in the status card
		HeaderMenuLeft = 250, -- room for Roblox menu/chat/voice at screen top
		HeaderMenuRight = 64, -- room for Roblox controls at screen right
		ShortHeight = 430, -- compact layout for phone landscape
		-- Short screens (a phone on its side, height under ShortHeight) use a compact top bar
		-- so a 3v3 still fits on one line and the table keeps most of the screen.
		ShortHeaderHeight = 60, -- the compact bar's cards
		ShortPortraitSize = 36, -- six identifiable portraits in landscape
		ShortCenterWidth = 280, -- the compact status card (a 1v1 fits beside it on a 667 px phone)
		ShortStatusSize = 18, -- its status line
		ShortNameSize = 14, -- names under portraits
		ShortLeaveWidth = 56, -- its Leave button, the door icon alone
		TeamNameShrink = 3, -- names under two or three portraits are this much smaller; long ones end in ...
		ShortBallSize = 24, -- balls in two rows of four, and on short screens
		ShortSetupHeight = 36, -- one-line placement instruction on short screens
		SetupHeight = 44, -- one-line placement instruction
		SetupMinWidth = 220, -- narrower than this, the instruction stacks above the precision row
		MobileBreakpoint = 760, -- stack central status below teams
		NarrowBreakpoint = 480, -- use two ball rows
		PortraitSize = 48, -- square avatar beside the ball row, its name under it
		PortraitCornerPx = 12, -- the portrait's rounded corners
		PortraitGap = 8, -- teammate portrait spacing
		ActiveDotPx = 14, -- the green dot on the shooter's portrait
		ActiveEdgePx = 4, -- the shooter's green outline and the clock running round it
		BallSize = 34, -- numbered HUD ball diameter
		BallGap = 5, -- stable ball-slot spacing
		NameSize = 16, -- player names and secondary lines (the kit's smallest text)
		StatusSize = 22, -- the status line and other primary labels
		ButtonHeight = 48, -- touch target (at least 44)
		ResultPanelHeight = 210, -- the result card; its icon sits on the top edge
		ResultIconSize = 112, -- trophy, sad ball or flag
		CoinPanelHeight = 290, -- the coin flip card
		CoinSize = 96, -- the coin
		DialogIconSize = 64, -- the door or flag over the leave question
		ModalWidth = 420, -- responsive dialog maximum width
		ModalDim = 0.45, -- how much the screen behind a dialog darkens
		PrecisionAngleDegrees = 0.5, -- aim button step
		PrecisionMoveInches = 1, -- placement button step
		PrecisionPowerStep = 0.05, -- power button step
		TargetStroke = 2.5, -- readable blue selection outline
		-- The foul popup (no panel, designer 2026-09-25): FOUL! and a few words on the rule.
		FoulCardSeconds = 3, -- up this long from the foul (it was 8, a card that stayed too long)
		FoulCardFadeSeconds = 0.4, -- and fades out over its last part
		FoulCardWidth = 460, -- pixels, narrower on small screens
		FoulTitleSize = 44, -- FOUL!
		FoulReasonSize = 20, -- the reason under it
		OpenBallSize = 22, -- balls already down while the table is open, beside OPEN TABLE
		ShortOpenBallSize = 18, -- the same on the two-row (narrow) layout
		OpenBallMinSize = 14, -- never shrink them below this to fit
		OpenLabelShare = 0.36, -- share of the ball-row width the OPEN TABLE label keeps
		-- The queue menu (src/client/QueueMenu.luau), top right while waiting in a box.
		QueueMenuWidth = 290, -- pixels, before shrinking to fit
		QueueMenuPadding = 12, -- inside the card
		QueueMenuLineGap = 4, -- a text row is its font size plus this
		QueueMenuMinScale = 0.6, -- never shrink the card further than this
		QueueTouchRight = 120, -- on touch screens the card keeps this far from the right edge: the jump button
		QueueHostSize = 20, -- the host's name
		QueueLevelHeight = 40, -- the difficulty segments and the abilities row
		QueueToggleWidth = 72, -- the abilities ON/OFF button
		QueueSoonWidth = 44, -- the SOON tag on Play against PC
		QueueDisabledText = 0.55, -- text transparency of a control only the host may press
		QueueNoticeSeconds = 2.5, -- "Coming soon" stays up this long
		SoloWrapColumns = 8, -- the solo 15-ball row wraps to this many + the rest on narrow screens
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
		PlacementHandleSize = 48, -- draggable cue-ball handle, never smaller than this
		PlacementGrabScale = 1.4, -- grab radius as a multiple of the ball's on-screen radius
		PlacementBlockedInches = 1.5, -- ring turns red when the ball lags the pointer by more than this
		PlacementRepeatDelay = 0.3, -- a held placement arrow starts repeating after this
		PlacementRepeatInterval = 0.06, -- then steps this often while held
		TargetHeightInches = 1.5, -- selection targets above cloth
		TargetPulse = 0.15, -- bounded ring pulse
		BreakDotSpacingInches = 2, -- dotted break line spacing
		Panel = { 20, 23, 29 }, -- dark neutral HUD
		PanelLight = { 36, 42, 51 }, -- restrained gradient
		Text = { 244, 247, 250 }, -- primary copy
		Muted = { 159, 171, 186 }, -- secondary copy
		Green = { 92, 223, 157 }, -- active/ready
		Red = { 242, 104, 112 }, -- foul/urgency
		Blue = { 91, 177, 255 }, -- called pockets
		Gold = { 255, 205, 60 }, -- established cue controls/coin
		White = { 235, 241, 248 }, -- empty slot
		Border = { 81, 96, 113 }, -- subtle panel outline
		CornerPx = 12, -- shared corner shape
		FadeSeconds = 0.25, -- panel/status motion
		ControlSeconds = 0.15, -- hover/press motion
		PulseSeconds = 1.8, -- calm ambient pulse
	},
}

Config.Debug = {
	-- Test keys in play mode: B = rack and break (until rules handle new games).
	TestKeysEnabled = true,
	-- The developer status line in the top-left corner. It is a readout of aim, speed and
	-- table counts, not part of the game, so it starts hidden and this key brings it in and
	-- out. Held as a string because Config is loaded by the Lune tests, which have no Enum;
	-- Main maps it. Keyboard only: it is a tool, not a feature that needs a phone path.
	ShowStatus = false,
	StatusKey = "F3",
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

---------------------------------------------------------------------------------------------
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
