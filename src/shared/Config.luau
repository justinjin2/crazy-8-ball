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
	DefaultLook = "Green",
	-- Table id -> look. The regular lobby has wood frames (green 1v1, red 2v2, charcoal 3v3)
	-- and the pro lobby black frames (blue 1v1, red 2v2, charcoal 3v3) (designer,
	-- 2026-09-26). This place is the regular lobby: the 1v1 tables take DefaultLook (green)
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
		-- the line sits at 1.5 lengths, just above 35%. It was 0.5 (about 25%), which pulled
		-- out for shots that had nothing to show.
		--
		-- It is a BOUND on every ball, not just the cue ball - nothing leaves a collision
		-- faster than the ball that struck it - so this can hold the camera still on a shot
		-- where little happens, and never on one where something travels. OffScreenMargin
		-- above still overrides it: anything that does reach the edge pulls the camera out
		-- however gently it was hit. (tune)
		MinTravelTableLengths = 1.5,
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
	-- bounce. Landings: where a jump shot comes down. The red X on a wrong target or an off
	-- table shot, and the glow on your own balls, stay on at every level.
	Levels = {
		Classic = { Corridor = true, Stubs = true, Landings = true }, -- every line (the default)
		Difficult = { Corridor = true, Stubs = false, Landings = false }, -- the aim line only
		Challenger = { Corridor = false, Stubs = false, Landings = false }, -- no lines at all
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
	MaxIdLength = 64, -- the longest key or id a save may hold (cue, case, title, code, user id)
	MaxCueEntries = 500, -- Inventory.Cues, .Unique, .New, Index.Seen, Shop.Limited
	MaxCaseEntries = 50, -- Inventory.Cases (one entry per case type)
	MaxTitleEntries = 200, -- Titles
	MaxCodeEntries = 500, -- Codes redeemed
	MaxSmallEntries = 50, -- Index.Rows (rarities) and Daily.PlaytimeClaimed (gift indices)
	ItemCountCap = 1e6, -- copies of one cue, or unopened cases of one type
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
}

---------------------------------------------------------------------------------------------
-- Ranks (src/shared/Progression/Ranks.luau; GDD section 11). Every number is from
-- docs/ECONOMY.md section 4 (2026-09-28). One number, rank XP (the save's RankXp), is the only
-- progression, and it is never lost: nobody drops a division or a tier. Change a number here,
-- in ECONOMY.md and in tools/economy_model.py together. (tune)
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
	-- XP to climb through each division, I to V, per tier (ECONOMY 4.2). Quick and flat to
	-- Platinum, then about 17% bigger every division from Diamond I. Grandmaster I starts at
	-- 1,057,500 XP and Reyes at 2,352,500 (tests/ranks_test checks both). Reyes has no top.
	DivisionXp = {
		Bronze = { 250, 250, 250, 250, 250 },
		Silver = { 350, 350, 350, 350, 350 },
		Gold = { 800, 800, 800, 800, 800 },
		Platinum = { 1200, 1200, 1200, 1200, 1200 },
		Diamond = { 8000, 9500, 11000, 13000, 15000 },
		Expert = { 17500, 20500, 24000, 28000, 33000 },
		Veteran = { 38000, 45000, 53000, 62000, 72000 },
		Master = { 85000, 100000, 115000, 135000, 160000 },
		Grandmaster = { 185000, 215000, 255000, 295000, 345000 },
	},
	-- A match's XP against an equal opponent, by YOUR tier, before the mode, fade, gap, PC and
	-- boosts (ECONOMY 4.2 "How it is built"). A loss gives a little to Platinum and nothing
	-- from Diamond; never less than 0. Unranked plays by Bronze's row.
	BaseXp = {
		Bronze = { Win = 250, Loss = 100 },
		Silver = { Win = 250, Loss = 75 },
		Gold = { Win = 250, Loss = 50 },
		Platinum = { Win = 250, Loss = 25 },
		Diamond = { Win = 250, Loss = 0 },
		Expert = { Win = 450, Loss = 0 },
		Veteran = { Win = 450, Loss = 0 },
		Master = { Win = 450, Loss = 0 },
		Grandmaster = { Win = 450, Loss = 0 },
		Reyes = { Win = 450, Loss = 0 },
	},
	-- The table's difficulty multiplies XP, wins and losses (ECONOMY 4.2).
	ModeXp = { Classic = 1, Difficult = 1.25, Challenger = 1.5 },
	-- Classic's WINS fade up the ladder (ECONOMY 4.2): x0.5 in Diamond, x0.2 from Expert. A
	-- tier not listed keeps x1. Only Classic fades; losses never do.
	ClassicWinFade = {
		Diamond = 0.5,
		Expert = 0.2,
		Veteran = 0.2,
		Master = 0.2,
		Grandmaster = 0.2,
		Reyes = 0.2,
	},
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
	-- XP boosts ADD together, then multiply (ECONOMY 4.5, 4.3): xp = round-half-even(base x
	-- mode x fade x gap x PC x (1 + boosts)). A new VIP's first win of the day is x3.5.
	Boosts = {
		Rookie = 1.0, -- +100% ("ROOKIE x2") for a player's first RookieMatches real matches
		RookieMatches = 25,
		Vip = 0.5, -- VIP +50%
		FirstWin = 1.0, -- the first win of each UTC day (wins only)
		Streak = 0.25, -- each win from the StreakFrom-th in a row, against people (wins only)
		StreakFrom = 3,
	},
	-- A match counts only after this much server-tracked time from the break (GDD section
	-- 13). Under it, a forfeit or an early 8 pays nobody anything. (tune)
	RealMatchSeconds = 60,
	-- Difficulty unlocks by YOUR rank (ECONOMY 4.7): host Difficult from Gold I, Challenger
	-- from Diamond I. Pure rule (Ranks.canHost); not enforced while every table is Classic.
	Unlocks = { Difficult = "Gold", Challenger = "Diamond" },
	-- Rank rewards, paid once, the first time you reach a division (PeakDivision passes it;
	-- ECONOMY 4.8). Step: the money for each new division II-V of a tier. Tier: reaching a
	-- tier's division I pays its money, its cases (into the inventory: { [caseId] = count })
	-- and the tier's cue (an Exclusive catalog id, never tradable or sellable). The chat tag
	-- comes from the tier itself (ChatTags).
	Rewards = {
		Step = {
			Bronze = 50,
			Silver = 75,
			Gold = 150,
			Platinum = 250,
			Diamond = 1500,
			Expert = 3000,
			Veteran = 5000,
			Master = 8000,
			Grandmaster = 15000,
		},
		Tier = {
			Bronze = { Money = 100, Cases = { Standard = 2 }, Cue = "BronzeCue" },
			Silver = { Money = 300, Cases = { Rare = 1 }, Cue = "SilverCue" },
			Gold = { Money = 600, Cases = { Rare = 2 }, Cue = "GoldCue" },
			Platinum = { Money = 1200, Cases = { Epic = 1 }, Cue = "PlatinumCue" },
			Diamond = { Money = 3000, Cases = { Epic = 2 }, Cue = "DiamondCue" },
			Expert = { Money = 10000, Cases = { Legendary = 2 }, Cue = "ExpertCue" },
			Veteran = { Money = 15000, Cases = { Legendary = 3 }, Cue = "VeteranCue" },
			Master = { Money = 25000, Cases = { Legendary = 5 }, Cue = "MasterCue" },
			Grandmaster = { Money = 50000, Cases = { Legendary = 10 }, Cue = "GrandmasterCue" },
			Reyes = { Money = 150000, Cases = { Legendary = 25 }, Cue = "ReyesCue" },
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
-- GDD section 12). Every number is from docs/ECONOMY.md section 3 (2026-09-28). (tune)
---------------------------------------------------------------------------------------------
Config.Economy = {
	BallPay = 10, -- every ball that counts for the shooter's team (3.1)
	-- A nice shot pays this on top of its ball (Rules/NiceShot's kinds), to the shooter only.
	NiceShotPay = { Bank = 15, Kick = 15, Combo = 20, Carom = 20 },
	-- The match bonus at the end of a real match (3.1, 3.2), by opponent. The leaver gets
	-- nothing. The win bonus is multiplied by the opponent-gap factor (Config.Ranks.Gap) but
	-- never below WinBonusGapFloor of it (4.4); the loss bonus is not.
	WinBonus = 50,
	LossBonus = 15,
	PcWinBonus = 25,
	PcLossBonus = 8,
	WinBonusGapFloor = 0.5,
	-- Win streak money (3.1): +StreakBonus on each win from the StreakFrom-th in a row,
	-- against people only (the same streak as the XP boost and the fire over the head).
	StreakBonus = 25,
	StreakFrom = 3,
	-- Team matches (3.3): every ball a team pots pays EACH teammate BallPay (with each
	-- player's own solo/short/PC rules); the nice-shot bonus goes only to the shooter.
	TeamBallPay = true,
	-- PC (3.2): after PcDailyCap of PC money in a UTC day, PC pays PcAfterCapShare of
	-- everything (rounded, never below $1 a ball).
	PcDailyCap = 1000,
	PcAfterCapShare = 0.5,
	-- Solo (3.2): this share of the normal pay (rounded, at least 1) until SoloDailyCap has
	-- been earned in solo in a UTC day, then SoloAfterCapPay a ball and nothing for nice shots.
	SoloShare = 0.3,
	SoloDailyCap = 300,
	SoloAfterCapPay = 1,
	-- Short matches (3.6): pots are paid live, but money from a match that ends before the
	-- one-minute mark adds to a daily short-match total; once that total reaches ShortDailyCap
	-- in a UTC day, balls potted before the one-minute mark pay ShortAfterCapPay each (and no
	-- nice-shot bonus) until the mark passes.
	ShortDailyCap = 200,
	ShortAfterCapPay = 1,
	-- Boosts (3.5): money = base x difficulty x (1 + VIP + Money Party) on everything earned
	-- in play (balls, nice shots, match bonuses), never on rewards, sell-back or packs.
	VipBoost = 1.0,
	PartyBoost = 1.0,
	-- Anti-farm (3.6): the same opponent in one UTC day. Each row covers matches up to UpTo
	-- (the last row has no UpTo: every match after). Xp, Bonus and Balls multiply the match's
	-- XP, its win/loss bonus and its ball pay; FreeCase says whether the winner's free case
	-- can drop. In a team match the most-played opponent's count is used.
	SameOpponent = {
		{ UpTo = 5, Xp = 1, Bonus = 1, Balls = 1, FreeCase = true },
		{ UpTo = 10, Xp = 0.5, Bonus = 0.5, Balls = 1, FreeCase = false },
		{ Xp = 0, Bonus = 0.25, Balls = 0.5, FreeCase = false },
	} :: {
		{
			UpTo: number?,
			Xp: number,
			Bonus: number,
			Balls: number,
			FreeCase: boolean,
		}
	},
	-- The save's per-day opponent table keeps at most this many accounts; past it, a new
	-- account reads as the worst count (Settle.opponentDay), so a full table never switches
	-- anti-farm off. 300 (about 12 KB of save) is far above a real day: a 3v3 meets 3 new
	-- accounts at most, so even 100 team matches in a day stay inside it.
	SameOpponentMaxEntries = 300,
	FreeCasesPerOpponent = 3, -- at most this many free cases a day from beating one account
	FreeCaseLoserMinMatches = 5, -- the loser must have played this many real matches
	-- Pay the table's difficulty multiplier (Config.Difficulty.MoneyMultiplier). Off until the
	-- difficulty picker and its lock exist (Roadmap 6.2): the server still accepts a host's
	-- SetDifficulty, so a modified client could otherwise pick 2x (second audit, 2026-09-27).
	-- Every table is Classic; the multipliers and Ranks.canHost are coded and tested.
	UseDifficultyMultiplier = false,
}

---------------------------------------------------------------------------------------------
-- Cases (src/shared/Progression/Cases.luau; the server's src/server/Items.luau). Every
-- number from docs/ECONOMY.md sections 7, 8 and 9 (2026-09-28). (tune)
---------------------------------------------------------------------------------------------
Config.Cases = {
	-- The case ladder, shop order.
	Order = { "Standard", "Rare", "Epic", "Legendary", "Event" },
	-- Rarities, bottom to top (GDD section 12). Exclusive and Unique sit outside the ladder.
	Rarities = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" },
	-- When sorting by rarity, Exclusive cues sit just above this rarity (below Legendary;
	-- designer, 2026-09-28). Unique sits above Secret.
	ExclusiveRanksAbove = "Epic",
	-- Odds are whole thousandths of a percent, so each row adds to exactly OddsTotal (a
	-- load-time assert and tests/cases_test check it). Standard: 64.3% = 64300.
	OddsTotal = 100000,
	List = {
		Standard = {
			Price = 150,
			Enabled = true,
			Odds = {
				Common = 64300,
				Uncommon = 26000,
				Rare = 8400,
				Epic = 1000,
				Legendary = 250,
				Mythic = 47,
				Secret = 3,
			},
		},
		Rare = {
			Price = 500,
			Enabled = true,
			Odds = {
				Uncommon = 62500,
				Rare = 31000,
				Epic = 5500,
				Legendary = 850,
				Mythic = 140,
				Secret = 10,
			},
		},
		Epic = {
			Price = 1500,
			Enabled = true,
			Odds = { Rare = 73400, Epic = 22000, Legendary = 4000, Mythic = 560, Secret = 40 },
		},
		Legendary = {
			Price = 5000,
			Enabled = true,
			Odds = { Epic = 76500, Legendary = 20000, Mythic = 3250, Secret = 250 },
		},
		-- The special Event Case (9.1): switched off until an event gives it its own cues.
		Event = {
			Price = 2000,
			Enabled = false,
			Odds = { Rare = 72500, Epic = 22000, Legendary = 4600, Mythic = 800, Secret = 100 },
		},
	},
	-- Bulk opening (9.1): BulkCount of any case for the price of BulkPayFor.
	BulkCount = 10,
	BulkPayFor = 9,
	-- A real, timed sale on ONE case (9.1): Case = a case id, Percent off, EndsAt = a unix time.
	-- Nothing is on by default (Case = ""). The /sale dev command sets it for this server only.
	Sale = { Case = "", Percent = 0, EndsAt = 0 },
	-- The most a sale may take off (percent). Above about 61% off, buying Legendary Cases 10 for
	-- 9 and selling back what they drop makes money; tests/shop_test checks every case at this
	-- percent still costs more than its drops sell for.
	MaxSalePercent = 50,
	-- Selling a case cue back (section 8), by rarity. Exclusive and Unique never sell.
	SellBack = {
		Common = 15,
		Uncommon = 40,
		Rare = 120,
		Epic = 600,
		Legendary = 3000,
		Mythic = 15000,
		Secret = 75000,
	},
	ConfirmSellFrom = "Epic", -- the client asks "are you sure?" from this rarity up
	-- The winner's free case (7.1): FreeCase for every win for the first NewPlayerWins wins
	-- ever, then the first DailyWins wins each UTC day, then every EveryAfter-th win. Real
	-- matches only (people or PC; never solo), with the anti-farm limits of
	-- Config.Economy.SameOpponent. The very first win ever gives FirstWinCase instead, rolled
	-- by the server when the match settles and revealed on the result screen.
	FreeCase = "Standard",
	NewPlayerWins = 50,
	DailyWins = 10,
	EveryAfter = 2,
	FirstWinCase = "Rare",
	-- Unboxing one of these is announced to everyone in the server (7.4).
	Announce = { Mythic = true, Secret = true },
	-- How many cases one request may open: one on the reel, or FastOpenCount with Fast Open.
	FastOpenCount = 10,
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
		Common = { Money = 1000 },
		Uncommon = { Money = 2500 },
		Rare = { Money = 7500 },
		Epic = { Money = 25000 },
	},
	-- The finder's money (designer, 2026-09-28): the first time a player gets a cue (it enters
	-- their Index), the server pays this much, by the cue's rarity or group; once per cue
	-- ever (sold and found again pays nothing). Earned money, not boosted by VIP or a party.
	-- (tune)
	FindMoney = {
		Common = 50,
		Uncommon = 100,
		Rare = 250,
		Epic = 750,
		Legendary = 2500,
		Mythic = 10000,
		Secret = 50000,
		Exclusive = 500, -- rank cues, the VIP and Starter cues
		Unique = 1000, -- numbered Limited cues
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
	-- Paid random items (ECONOMY 13): PolicyService is asked on join, this many times this far
	-- apart; if it never answers, the player is treated as restricted (no cases for money, no
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
	-- it, so the banner never spoils the opener's reel: that reel runs Config.UI.CaseOpening
	-- .Reel's BigSeconds + CentreSeconds + BigSettleHoldSeconds (about 7.7 s) before its card,
	-- and this is at least a second more (config_test).
	UnboxAnnounceDelaySeconds = 9,
}

---------------------------------------------------------------------------------------------
-- Daily and playtime rewards, codes (src/shared/Progression/Daily.luau; the server's
-- src/server/Rewards.luau). Every number from docs/ECONOMY.md section 10. (tune)
---------------------------------------------------------------------------------------------
Config.Daily = {
	-- The login streak, one claim per UTC day (10). Missing a day starts again at day 1.
	-- Each day: Money and/or Cases ({ [caseId] = count }).
	Streak = {
		{ Money = 250 },
		{ Cases = { Standard = 2 } },
		{ Money = 500 },
		{ Cases = { Rare = 1 } },
		{ Money = 1000 },
		{ Cases = { Rare = 2 } },
		{ Cases = { Epic = 1 } },
	} :: { { Money: number?, Cases: { [string]: number }? } },
	-- Four full weeks in a row add WeekBonus on day 28 (the 7th day of the 4th week).
	WeeksForBonus = 4,
	WeekBonus = { Cases = { Legendary = 1 } },
	-- Playtime gifts: minutes played in a UTC day, each claimable once that day.
	Playtime = {
		{ Minutes = 10, Money = 100 },
		{ Minutes = 30, Cases = { Standard = 1 } },
		{ Minutes = 60, Cases = { Standard = 2 } },
	} :: { { Minutes: number, Money: number?, Cases: { [string]: number }? } },
	PlaytimeTickSeconds = 30, -- the server adds playtime this often (and on leave)
	-- Promo codes (ECONOMY 18): case-insensitive, once per player, optional Expires (the unix
	-- time it stops working: midnight UTC after its last day). Codes give money, free cases,
	-- ult spins and Lucky Spins (the designer, 2026-09-28, the ultimates brief 9.3). Placeholders.
	Codes = {
		WELCOME = { Money = 500, Cases = { Standard = 1 } },
		["8BALL"] = { Money = 250 },
		ROOFTOP = { Cases = { Rare = 1 }, Expires = 1798761600 }, -- through 2026-12-31 (UTC)
		-- The spin screen's code box (Config.Ults.CodeBanner.ActiveCode names it): 3 ability
		-- spins. Was ULTS until players' "ults" became "abilities" (2026-09-28, pre-release).
		ABILITIES = { Spins = 3 },
	} :: {
		[string]: {
			Money: number?,
			Cases: { [string]: number }?,
			Spins: number?, -- ult spins (the designer, 2026-09-28: codes give spins)
			LuckySpins: number?, -- Lucky Spins
			Expires: number?,
		},
	},
	CodeMaxLength = 24,
	-- The Rewards service's limits (src/server/Rewards.luau; server limits, not ECONOMY.md
	-- numbers): one RewardRequest per player this often, one code attempt this often (so codes
	-- cannot be guessed quickly), and how often the server looks for a new UTC day (section 10:
	-- the streak and the gifts start over at midnight UTC, and the menu's state is re-sent).
	RequestCooldownSeconds = 0.5,
	RedeemCooldownSeconds = 2,
	DayCheckSeconds = 1,
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
	StarterMoney = 3000,
	StarterCue = "StarterCue",
	VipCue = "VipCue", -- given once to every VIP
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
	-- for an offer window (11.3, 11.4), a Limited (9), a case sale (9.1) or the Money Party
	-- (11.5) opening or closing, and re-sends that player's ShopState. Game pass ownership
	-- (11.2, 11.5) is asked of Roblox on join up to PassCheckTries times, PassRetrySeconds
	-- apart (the call can fail); a purchase in this server counts at once.
	RequestCooldownSeconds = 0.5,
	StateTickSeconds = 1,
	PassCheckTries = 3,
	PassRetrySeconds = 5,
	-- The Limited shelf (9): numbered Unique cues, one per player, for a set time. Price in
	-- money (or Product = a Config.Products key for a Robux one), Cap copies at most.
	Limited = {
		{ Cue = "BetaCue", Price = 40000, Cap = 1000, StartsAt = 1790553600, Seconds = 30 * 86400 },
		{
			Cue = "FoundersCue",
			Product = "FoundersCue",
			Cap = 50,
			StartsAt = 1790553600,
			Seconds = 30 * 86400,
		},
	} :: {
		{
			Cue: string,
			Price: number?,
			Product: string?,
			Cap: number?,
			StartsAt: number,
			Seconds: number,
		}
	},
}

---------------------------------------------------------------------------------------------
-- Robux products (ECONOMY 11). The designer makes each in Creator Hub and pastes its id here;
-- while Id is 0 the shop says "Coming soon" and prompts nothing. Robux is the display
-- fallback only: the shop shows Roblox's live price once an id exists (11).
---------------------------------------------------------------------------------------------
Config.Products = {
	-- The shop's order of the money packs (11.1).
	PackOrder = { "Pack1", "Pack2", "Pack3", "Pack4", "Pack5", "Pack6", "Pack7" },
	List = {
		Pack1 = { Kind = "Product", Id = 0, Robux = 49, Money = 900, Bonus = 0 }, -- Handful
		Pack2 = { Kind = "Product", Id = 0, Robux = 99, Money = 1950, Bonus = 7 }, -- Stack
		Pack3 = { Kind = "Product", Id = 0, Robux = 249, Money = 5250, Bonus = 15 }, -- Bundle
		Pack4 = { Kind = "Product", Id = 0, Robux = 499, Money = 11000, Bonus = 20 }, -- Briefcase
		Pack5 = { Kind = "Product", Id = 0, Robux = 999, Money = 23500, Bonus = 28 }, -- Vault
		Pack6 = { Kind = "Product", Id = 0, Robux = 2499, Money = 62500, Bonus = 36 }, -- Bank
		Pack7 = { Kind = "Product", Id = 0, Robux = 4999, Money = 130000, Bonus = 42 }, -- Fortune
		VipOffer = { Kind = "Product", Id = 0, Robux = 299 }, -- VIP at half price (11.3)
		StarterPack = { Kind = "Product", Id = 0, Robux = 79 }, -- 11.4
		MoneyParty = { Kind = "Product", Id = 0, Robux = 199 }, -- 11.5
		FoundersCue = { Kind = "Product", Id = 0, Robux = 1499 }, -- the Limited shelf (9)
		Vip = { Kind = "Pass", Id = 0, Robux = 599 }, -- 11.2
		FastOpen = { Kind = "Pass", Id = 0, Robux = 99 }, -- 11.5 (also Skip and Auto Spin for ult spins)
		-- Ult spins (ECONOMY 11.8; the spin screen's R$ buy row). Spins / Lucky: what one
		-- purchase adds; Was: the original price shown crossed out (a real bulk saving against
		-- Spin1 or Lucky1, never an always-on fake sale). Paid random items: refused at the prompt
		-- where PolicyService restricts them (a receipt that arrives anyway still grants).
		Spin1 = { Kind = "Product", Id = 0, Robux = 15, Spins = 1 }, -- 1 spin
		Spin5 = { Kind = "Product", Id = 0, Robux = 50, Was = 75, Spins = 5 }, -- 5 spins
		Spin10 = { Kind = "Product", Id = 0, Robux = 100, Was = 150, Spins = 10 }, -- 10 spins
		Spin50 = { Kind = "Product", Id = 0, Robux = 449, Was = 750, Spins = 50 }, -- 50 spins
		Lucky1 = { Kind = "Product", Id = 0, Robux = 49, Lucky = 1 }, -- 1 Lucky Spin (no Commons)
		Lucky3 = { Kind = "Product", Id = 0, Robux = 129, Was = 147, Lucky = 3 }, -- 3 Lucky Spins
		-- Ult slots 2 and 3 (Config.Ults.SlotPasses): owning the pass makes the slot usable.
		UltSlot2 = { Kind = "Pass", Id = 0, Robux = 59 },
		UltSlot3 = { Kind = "Pass", Id = 0, Robux = 99 },
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
	-- The spin screen for live players. Off until more ults than Magnet are built (today's live
	-- roll pool is 100% Magnet); Studio always shows it.
	ScreenLive = false,
	-- The developer flag: every ult, built or not, can be rolled and equipped (friend tests).
	-- `/ultsall on` turns it on for one player for the session.
	DevAllUlts = false,
	Default = "Magnet", -- everyone's starter ult, free forever; an empty or unusable slot plays as it
	BarMax = 100, -- a full bar
	MaxPerMatch = 2, -- at most this many ults a match; after the second the bar stays empty
	-- Solo gets no bar: a small "Practice ult" button arms the equipped ult for free.
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
		"TimeStop",
		"ChainLightning",
		"Portals",
		"SteelBall",
		"BlackFlash",
		"BlackHole",
		"GuangdongTiger",
	},
	Catalog = {
		Magnet = { Rarity = "Common", Built = true, Effect = "Magnet", Worth = 0.33 },
		EaglesEye = { Rarity = "Common", Built = false, Worth = 0.33 },
		SuperBounce = { Rarity = "Common", Built = false, Worth = 0.33 },
		Ghost = { Rarity = "Uncommon", Built = false, Worth = 0.5 },
		HeatSeeker = { Rarity = "Uncommon", Built = false, Worth = 0.5 },
		Rewind = { Rarity = "Rare", Built = false, Worth = 1 },
		TimeStop = { Rarity = "Rare", Built = false, Worth = 1 },
		ChainLightning = { Rarity = "Epic", Built = false, Worth = 1.5 },
		Portals = { Rarity = "Epic", Built = false, Worth = 1.5 },
		SteelBall = { Rarity = "Legendary", Built = false, Worth = 2.5, MaxBalls = 3 },
		BlackFlash = { Rarity = "Legendary", Built = false, Worth = 2.5, MaxBalls = 3 },
		BlackHole = { Rarity = "Mythic", Built = false, Worth = 2.5, MaxBalls = 3 },
		GuangdongTiger = { Rarity = "Mythic", Built = false, Worth = 2.5, MaxBalls = 3 },
	} :: {
		[string]: {
			Rarity: string,
			Built: boolean,
			Effect: string?,
			Worth: number,
			MaxBalls: number?,
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
		Starter = 3, -- a fresh save, and the migration for existing saves
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
		StreakDay7 = 2, -- day 7 of the login streak (each week of the cycle), on top of its reward
		PlaytimeLast = 1, -- the day's last playtime gift adds this many spins
		-- Money spins: this much each, no bulk discount ("way more expensive" than Robux).
		MoneyPerSpin = 1750,
		MoneyPacks = { 1, 5, 10, 50 }, -- BUY 1, 5, 10, 50 in $ mode
		-- Robux packs: the developer products in Config.Products (Spin1..Spin50, Lucky1, Lucky3).
		RobuxPacks = { "Spin1", "Spin5", "Spin10", "Spin50" },
		LuckyPacks = { "Lucky1", "Lucky3" },
		MaxSpins = 100000, -- the save's cap on held spins (and Lucky Spins)
	},
	-- The code box on the spin screen (section 9.3): the designer edits these two in one place.
	-- The code itself is a row in Config.Daily.Codes (Spins = 3).
	CodeBanner = { ActiveCode = "ABILITIES", NextGoalLikes = 100 },
	-- Fast Open's Auto Spin (section 9.6): one spin this often, server-checked.
	AutoSpinSeconds = 0.4,
	AutoStopChoices = { "Rare", "Epic", "Legendary" },
	-- The PC opponent (section 4): it activates when its bar is full and it is behind, or when
	-- its shot finder sees no easy shot.
	Pc = { WhenBehind = true, WhenNoEasyShot = true },
	-- The spin service's request limits (not design numbers).
	RequestCooldownSeconds = 0.25,
	RequestBurst = 6,
	-- Sounds (section 7). The designer's two, uploaded to the group; ult_activate starts after
	-- its silent lead (StartOffset, measured in Studio).
	Audio = {
		-- ult_activate (1.67 s): silent until 0.74 s (measured with an AudioAnalyzer, 2026-09-28),
		-- so it starts at 0.72 and its hit lands with the panel's slam.
		Activate = { Id = "rbxassetid://97016460180199", Volume = 0.6, StartOffset = 0.72 },
		-- ult_ready (8.2 s, a steady jingle from 0.15 s): the bar reaching 100%. It plays for
		-- MaxSeconds then fades over FadeSeconds so it never talks over the shot (overnight
		-- assumption; MaxSeconds 0 plays it whole).
		Ready = {
			Id = "rbxassetid://140675130154393",
			Volume = 0.45,
			StartOffset = 0.12,
			MaxSeconds = 3,
			FadeSeconds = 0.8,
		},
		-- Magnet (public library audio, each checked loading in this game, 2026-09-28):
		-- "Force Field Sci Fi Constant Deep Pulsing Hum" (Pro Sound Effects, 27 s): the low
		-- magnetic hum looping at the armed cue ball (3D, quiet); it rises in pitch while a
		-- ball is pulled.
		MagnetHum = { Id = "rbxassetid://9125566994", Volume = 0.35, Pitch = 0.9, PullPitch = 1.35 },
		-- "Electric Zapping loop" (FastFoxVita, 0.98 s loop, loud): crackle while a ball is in
		-- a capture zone, at the ball.
		MagnetPull = { Id = "rbxassetid://427262367", Volume = 0.12 },
		-- The drop: "Metal Impact Heavy Clunking Hits 4" (Pro Sound Effects, 0.87 s) with
		-- "Electric Zaps 12" (Pro Sound Effects, 0.97 s) on top: the clunk-zap at the pocket.
		MagnetClunk = { Id = "rbxassetid://9116673944", Volume = 0.3 },
		MagnetZap = { Id = "rbxassetid://9114277757", Volume = 0.55 },
		-- Arming: "Electric Zaps 6" (Pro Sound Effects, 2.1 s, starts at 0.16 s) as the rings
		-- snap onto the cue ball.
		MagnetArm = { Id = "rbxassetid://9114277402", Volume = 0.45, StartOffset = 0.14 },
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
	-- pocket's mouth. Nothing outside it is pulled. Was 3 before the buff. (tune)
	ZoneBallWidths = 7.5,
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
	-- The interface's own sounds (src/client/UISound.luau): ranks, money and buttons. Not
	-- positional, well under the pool sounds. Placeholders from the Creator Store, listed in
	-- assets/audio/README.md; swap any by changing its id. An empty Id plays nothing.
	-- Overlap: several may sound at once (a clone per play) instead of restarting.
	Ui = {
		-- "CoinTransfer_01" (Roblox, 1.7 s): a chip lands in the money HUD.
		CashLand = { Id = "rbxassetid://127645268874265", Volume = 0.3, Overlap = true },
		-- "Roblox_UI_Small_Click" (Roblox, 0.13 s), pitched up: the money count ticking.
		MoneyTick = { Id = "rbxassetid://15675032796", Volume = 0.12, Overlap = true, Pitch = 1.4 },
		-- "Roblox_UI_Bright_Click" (Roblox, 0.37 s): the XP bar filling (pitch rises, XpTickPitch).
		XpTick = { Id = "rbxassetid://15675059323", Volume = 0.15, Overlap = true },
		-- "Roblox_UI_Tonal_Stinger" (Roblox, 1.5 s): the XP bar reaching a division's top.
		XpFull = { Id = "rbxassetid://15675043410", Volume = 0.3 },
		-- "Game Show" (APM Music via Roblox, 2.2 s): NEW RANK!
		RankUp = { Id = "rbxassetid://1844692556", Volume = 0.35 },
		-- "Glamour Fanfare 4" (APM Music via Roblox, 3.7 s): a new tier, the bigger fanfare.
		NewTier = { Id = "rbxassetid://1844584807", Volume = 0.4 },
		-- "RBLX UI Hover 01 (SFX)" (Roblox, 0.2 s, a soft tone near 900 Hz): the mouse or a
		-- gamepad on a badge or a roadmap tier (designer, 2026-09-27: short and pleasant; was
		-- "Roblox_UI_Cute_Pop", 2.7 s with its tail). Its 0.23 peak x 0.22 sits just under Click.
		BadgeHover = { Id = "rbxassetid://10066931761", Volume = 0.22 },
		-- "Roblox_UI_Small_Click" (Roblox, 0.13 s): a button pressed.
		Click = { Id = "rbxassetid://15675032796", Volume = 0.25 },
		-- The case reel (2026-09-28, overnight placeholders; assets/audio/README.md). All from
		-- Roblox's own library or APM Music via Roblox; each checked loading in this game.
		-- "Roblox_UI_Small_Click" (0.13 s), pitched up and quiet: one card passing the marker.
		ReelTick = { Id = "rbxassetid://15675032796", Volume = 0.1, Overlap = true, Pitch = 1.7 },
		-- "Roblox_UI_Sweep" (Roblox, 0.61 s): the reel settling on the prize.
		ReelSettle = { Id = "rbxassetid://15675046931", Volume = 0.3 },
		-- "Roblox_UI_Whoosh_03" (Roblox, 1.1 s): the longer build-up before a Mythic or Secret.
		ReelBuild = { Id = "rbxassetid://15674975792", Volume = 0.35 },
		-- The reveal sting by rarity tier: "Roblox_UI_Cute_Pop" (2.7 s) for Common and
		-- Uncommon, "Fortune Fun Logo" (APM, 3.1 s) for Rare, "Everything Works Out - Tag2" (APM,
		-- 3.7 s) for Epic, "Shooting Stars" (APM, 4.9 s) for Legendary, "Spinning Around (b)"
		-- (APM, 5.4 s) for Mythic and Secret.
		RevealLow = { Id = "rbxassetid://15675055424", Volume = 0.3 },
		RevealRare = { Id = "rbxassetid://1846251729", Volume = 0.3 },
		RevealEpic = { Id = "rbxassetid://1848281810", Volume = 0.32 },
		RevealLegendary = { Id = "rbxassetid://9045294353", Volume = 0.35 },
		RevealMythic = { Id = "rbxassetid://1839881844", Volume = 0.38 },
		-- "Roblox_UI_Tonal_Stinger" (1.5 s): a reward claimed (daily, playtime, index, code).
		Claim = { Id = "rbxassetid://15675043410", Volume = 0.3 },
		-- "Roblox_UI_Indicator" (3.4 s), quiet: a banner (Money Party, an announcement).
		Banner = { Id = "rbxassetid://15675085146", Volume = 0.2 },
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
		-- One row per rarity (the catalog's case cues name their rarity; rank and special
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

	-- ...and a top-down cue lying INSIDE that bar, which slides down as you pull. The cue is
	-- the player's equipped catalog cue (Catalog.style), so the cue they pull back is the one
	-- on their stick, and a new cue changes nothing here.
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
			BadgePx = 70, -- the badge, square: bigger than the pill, as in reference 02 (its art has margins)
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
			-- A computer or tablet (screen at least Style.ShortHeight tall): bigger, an easier
			-- mouse target (designer, 2026-09-27; was 1.15). It hangs below Roblox's top row.
			ComputerScale = 1.5,
			TopMinPx = 1, -- never closer than this to the top of the screen
			FallbackRowPx = 58, -- the top row's height when Roblox does not report it
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
			-- The small badge under each portrait in the match bar (MatchHUD): this share of the
			-- portrait, its centre this share of the badge above the portrait's lower edge, so it
			-- overlaps the edge rather than growing the bar.
			PortraitBadgeShare = 0.72,
			PortraitBadgeRaise = 0.15,
			-- The Rookie Boost (ECONOMY 4.5): a small green "ROOKIE x2" pill stuck on the pill's
			-- bottom edge, under the XP bar's right end, while the RookieLeft attribute is above
			-- 0 (overnight assumption, 2026-09-28: there, it covers neither the name nor the
			-- numbers, and it stays inside the badge's height, clear of the column below).
			RookieHeightPx = 18,
			RookieTextPx = 14, -- the kit's smallest text
			RookiePadPx = 7, -- room each side of its words
			RookieRightPx = 8, -- its right end, this far in from the pill's right end
			-- Its top this far above the pill's bottom edge: it hangs below, clear of the XP
			-- numbers, and ends no lower than the badge (13 + 44 - 5 + 18 = 70), clear of the
			-- column under the HUD on a phone.
			RookieOverlapPx = 5,
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
			StackedFaceHeight = 250, -- stacked (a narrow screen): the face-off's height
			TitleHeight = 40, -- WINNER, DRAW or SOLO GAME over the cards
			TitleTextPx = 32,
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
			-- free case, the reminder); the whole screen still scales to fit.
			BlockGap = 6, -- between the card's blocks (the XP, the boosts, the Total, the case)
			-- The XP boosts (ECONOMY 4.5; brief section 13): a chip each under the XP bar,
			-- "ROOKIE x2", "FIRST WIN x2", "STREAK +25%", "VIP +50%" (a boost of +100% or more
			-- reads as a multiplier, a smaller one as a percent), in rows as wide as the bar.
			BoostHeight = 20,
			BoostTextPx = 14,
			BoostGap = 6, -- between two chips, and between two rows
			BoostPadPx = 8, -- room each side of a chip's words
			-- Each boost's colour: a Kit colour name, or "Rainbow" (the house rainbow: VIP).
			BoostTones = { Rookie = "Green", FirstWin = "Gold", Streak = "Red", Vip = "Rainbow" },
			BoostStagger = 0.08, -- the chips pop one after another with the XP
			-- The winner's free case (ECONOMY 7.1): "+1 Standard Case" with its chest, under the
			-- Total; its chest then flies into the left column's Inventory tile.
			CaseChipHeight = 30,
			CaseChipTextPx = 16,
			CaseAfterSeconds = 0.2, -- it pops this long after the total chip flies
			CaseFlySeconds = 0.45, -- and its chest flies this long after that
			-- The reminder under it ("Come back tomorrow for your Rare Case", Reminders): small
			-- ink text, one line, more when the words need them (a phone, a translation).
			ReminderTextPx = 14,
			ReminderMaxLines = 3,
			-- The first win's Rare Case (ECONOMY 7.1): after the counts, the face-off and the
			-- card make way for CaseOpening's reel and its card with Equip (a step before the
			-- buttons); once the player is done with it they come back with Continue.
			RevealSwapSeconds = 0.2, -- the columns pop out this long before the reel starts
			-- Timings, seconds from the screen opening (a tap skips to the end).
			CrownAt = 0.35, -- the crown starts to drop
			CrownDropSeconds = 0.45,
			CrownWobbleDegrees = 6, -- then it rocks gently
			XpAt = 0.8, -- the XP bar starts
			XpFillSeconds = 1.1, -- the whole change, shared out over the divisions it crosses
			XpMinSegmentSeconds = 0.25, -- never quicker than this through one division
			XpFlashSeconds = 0.35, -- a full bar flashes this long before the next division
			XpTickEvery = 0.07, -- the rising XP tick
			MoneyAt = 1.1, -- the money list starts (while the bar fills)
			LineSeconds = 0.32, -- each line pops and counts up in this
			TotalSeconds = 0.45, -- then the Total
			ChipDelaySeconds = 0.15, -- then the total chip flies to the money HUD
			ContinueDelaySeconds = 0.4, -- then Continue
			AutoCloseSeconds = 2.5, -- and the screen closes by itself this long after
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
			-- The reward chips (RewardChips; brief section 9): the money, each case ("x2"), the
			-- tier's cue and its chat tag, in centred rows under the name. A row may reach past
			-- the popup's sides like the title; more wrap onto a second row.
			RewardHeight = 32, -- a reward chip
			RewardTextPx = 20,
			ChipGap = 8, -- between two chips
			ChipRowGap = 6, -- between two rows
			ChipsMaxWidth = 520, -- a row of chips at most
			ChipStagger = 0.1, -- they pop one after another with the burst
			ItemFlyAfter = 0.3, -- the first case or cue flies to Inventory this long after the money
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
			DimTransparency = 0.45, -- the backdrop behind the panel (a tap on it closes)
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
		-- the picture then the words; and a case or cue flying from its chip into the left
		-- column's Inventory tile (the column shows meanwhile, even under a popup).
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
			Case = "rbxassetid://119138673224082", -- a case chest (case_standard; was 123526196779472)
			ChatTag = "rbxassetid://108097317615793", -- a speech bubble (the chat-tag reward tile)
			-- The economy (2026-09-28; tools/gen_ui_art.py, assets/ui/icons/README.md). An empty id
			-- draws nothing until the image is uploaded.
			Shop = "rbxassetid://107658760787268", -- the left column: a shopping basket
			Inventory = "rbxassetid://105879289234800", -- a backpack
			Rewards = "rbxassetid://92894769753979", -- a gift box with a bow
			Trade = "rbxassetid://98977101809699", -- two arrows swapping
			CaseStandard = "rbxassetid://119138673224082", -- the case chest after reference 07, in its case's colour
			CaseRare = "rbxassetid://121070015585025",
			CaseEpic = "rbxassetid://86949000248568",
			CaseLegendary = "rbxassetid://115568776906467",
			CaseEvent = "rbxassetid://102627378767988",
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
			FastOpen = "rbxassetid://119005216671556", -- a chest with a lightning bolt
			Limited = "rbxassetid://105313592367901", -- a numbered star ticket
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
		-- The host's card (src/client/QueueMenu.luau), top right while their table waits.
		QueueMenuWidth = 260, -- pixels, before shrinking to fit
		QueueMenuPadding = 10, -- inside the card
		QueueMenuLineGap = 4, -- a text row is its font size plus this
		QueueRowGap = 6, -- between the card's rows
		QueueMenuMinScale = 0.6, -- never shrink the card further than this
		QueueTitleHeight = 32, -- the difficulty's picture and "Classic 1v1"
		-- Where the card goes (designer, 2026-09-27: keep it out of the way). A screen at least
		-- this tall, in GUI pixels, is big (PC, console, tablet): the card sits on the right,
		-- halfway down, at full size. Shorter (a phone) tucks it into the top right corner at
		-- QueueCornerScale. (tune)
		QueueWideMinHeight = 500,
		QueueWideScale = 1.3, -- the card on a big screen (designer, 2026-09-27: bigger on PC; was 1)
		QueueCornerScale = 0.85,
		QueueDotSeconds = 0.4, -- "Waiting for opponent...": each dot lights this long after the last
		QueueFoldSeconds = 0.3, -- the card folding to "Requested!" and back, about this long
		QueueFoldEdgePx = 6, -- room above and below a folding part's buttons for their outlines (and a hovered one's grow)
		QueueFoldSidePx = 10, -- and beside them: the part reaches this far past the card's column
		QueueCountWidth = 72, -- the people n/6 pill
		QueuePillHeight = 26, -- the count and team-split pills
		-- The No-ults fallback's line on the searching card ("Nobody's in No ults right now.
		-- Search with ults on?"): this many lines of Body text, over Yes and No side by side.
		QueueFallbackLines = 2,
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
-- for everyone on a server (the brief: Day 10 min, a 1 min fade, Sunset 5 min, a 1 min fade;
-- no night). LightCycle mixes the two states by the server's clock, MapLighting puts a state
-- onto the place (MapLighting.preview in Edit mode, for captures and so the place is saved
-- lit), and DayCycle drives it on each client. Day and Sunset have the same keys (a Lune test
-- checks). Colours are hex strings. The background (the city, the islands, the sea) is kept
-- soft by the haze and the depth of field so the eye goes to the tables (designer,
-- Checkpoint C).
---------------------------------------------------------------------------------------------
Config.Lighting = {
	Cycle = {
		Day = 600, -- seconds of day
		Fade = 60, -- seconds of each fade, eased
		Sunset = 300, -- seconds of sunset
		-- Test only: the cycle runs this many times as fast (Checkpoint D's timed run). A Lune
		-- test keeps it 1, so a test value cannot be committed.
		Speed = 1,
		Rate = 12, -- a client applies the fading light this many times a second
		Look = 2, -- seconds between a client's looks for map parts still streaming in
		-- workspace's attribute holding the cycle's offset (scaled seconds), set by the /day and
		-- /sunset developer commands (Config.Debug.Commands); the server's, so all agree.
		OffsetAttribute = "DayCycleOffset",
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
			SunAngularSize = 12, -- degrees; Roblox's 21 glares over the painted sky (tune)
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
		Bloom = { Intensity = 0, Size = 24, Threshold = 2 },
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
		OutdoorAmbient = "#B8A090",
		ColorShift_Top = "#FFCB88", -- the low sun's gold on lit faces
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
			Color = "#F6C2A4",
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
			SunAngularSize = 5, -- a gold disc on the horizon, not a white blaze (critics 1 and 2)
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
			Saturation = 0.15,
			TintColor = "#FFF4E6",
		},
		-- The lanterns and windows bloom a little; more blew the sun out to a white disc.
		Bloom = { Intensity = 0.3, Size = 20, Threshold = 2.2 },
		SunRays = { Intensity = 0.04, Spread = 0.5 },
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

-- The economy's menus (2026-09-28, docs/prompts/ECONOMY_UI_PROMPT.md sections 5 and 5.1): the
-- left column (MenuColumn), every full menu's frame (MenuFrame: header band, tabs, sheet, red
-- X), its confirm dialog, notice line, scrollers and card tiles, the rarity dressing and cue
-- thumbnails (CueThumb) and the top banner (Banner). Pixels and seconds. "Short" values are for
-- a phone on its side (the HUD screen under Multiplayer.Style.ShortHeight, as the rank and money
-- HUDs). A menu's slight dim is the roadmap's (Config.UI.Progress.Roadmap.Dim*). (tune)
Config.UI.Menu = {
	-- The left column (reference 06): one tile each, top to bottom, each just its big icon
	-- with no box behind it (designer, 2026-09-28). Keys name the menus (Menus.register) and
	-- their words (Strings.Menus.Column) and icons (Kit.Icons).
	Column = {
		Order = { "Shop", "Inventory", "Rewards", "Trade" },
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
		ShortLabelTextPx = 14, -- never under the kit's minimum
		LabelCentreShare = 0.86, -- the word's middle sits this far down the tile
		-- The word's box may be this many tiles wide, overhanging both sides ("Inventory" is
		-- wider than a phone's tile at 14 px); the column moves right by the overhang.
		LabelMaxShare = 1.7,
		DotPx = 22, -- the red dot's height (it widens for "9+"), top right of the tile
		ShortDotPx = 20,
		DotTextPx = 14,
		DotInsetPx = 4, -- its centre sits this far inside the tile's top-right corner
		DotMax = 9, -- more unopened cases than this read "9+"
		TimerPx = 22, -- the Shop's gold timer pill while an offer window is open
		ShortTimerPx = 20,
		TimerTextPx = 14,
		TimerOverTileShare = 0.3, -- this share of the pill sits over the tile, the rest past it
		DaysFromSeconds = 86400, -- from a day left the timer reads "6d 4h", else "23:59:12"
		-- Each tile's D-pad direction (UserInputService KeyCode names; Config has no Enum):
		-- in the hub the D-pad opens that menu (overnight assumption, 2026-09-28).
		PadKeys = {
			Shop = "DPadUp",
			Inventory = "DPadRight",
			Rewards = "DPadDown",
			Trade = "DPadLeft",
		},
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
		TopPx = 6, -- under Roblox's top bar (the HUD screen starts there)
		HeightPx = 38,
		ShortHeightPx = 32,
		TextPx = 20,
		ShortTextPx = 16,
		PadPx = 18, -- room each side of the words
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

-- The Shop (ShopMenu and its pages ShopCases, ShopOdds, ShopLimited, ShopMoney and ShopVip, with
-- ShopParts; docs/prompts/ECONOMY_UI_PROMPT.md section 11): cards laid out by hand from the
-- page's size. Sizes given as { a, b } run from a on a phone-sized panel to b on a full one
-- (MenuFrame's geo.t, as Config.UI.Menu.Frame). Text never goes under Kit.Text.Min. Pixels and
-- seconds. (tune)
Config.UI.Shop = {
	TickSeconds = 0.25, -- the countdowns (sale, offers, Limited, party) are redrawn this often
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
	-- The Cases tab: standing cards side by side (the chest on top) when each is at least
	-- TallMinWidthPx wide and the page leaves the chest IconMinPx, else one row per case.
	Cases = {
		TallMinWidthPx = 150,
		TallMaxPx = 420, -- a standing card is never taller than this (centred on a tall page)
		IconMinPx = 56, -- the chest
		IconMaxPx = 130,
		OddsWidthPx = { 84, 104 }, -- the Odds button (its touch area is always 44)
		OddsHeightPx = { 34, 40 },
		RowButtonsPx = { 150, 180 }, -- a row's Buy / Buy 10 column (fits "Need $12,000 more")
		NoteColor = { 255, 246, 214 }, -- the restricted note's card, a pale gold
	},
	-- The odds panel over the pages: a heading per rarity, a row per cue in as many columns as
	-- keep a row RowMinWidthPx wide.
	Odds = {
		ZIndex = 50, -- over the pages, under the notices (55) and dialogs (60)
		HeaderPx = { 44, 52 }, -- the chest, the title and the red X
		TitleTextPx = { 20, 28 },
		CloseMaxPx = 44,
		HeadingTextPx = { 16, 20 }, -- a rarity's name and %, in its colour
		RowPx = { 36, 44 }, -- a cue's row: its thumbnail, name and %
		RowTextPx = { 14, 16 },
		RowMinWidthPx = 210,
		RowCornerPx = 10,
		RowStrokePx = 2, -- a row's edge, in its rarity's colour
	},
	-- The Limited tab: a card per shelf row, the thumbnail at the left.
	Limited = {
		MinWidthPx = { 300, 360 }, -- cards side by side while each is this wide
		MaxWidthPx = { 420, 440 },
		ExtraHeightPx = 60, -- a card grows at most this much past its needs on a tall page
		Aspect = 0.6, -- the height / width the fit prefers
		ArtShare = 0.42, -- the thumbnail's slot, of the card's width
		ArtCornerPx = 12,
		ThumbInsetShare = 0.06, -- the cue inside its card
	},
	-- The Money tab: the seven packs (one shelf on a phone), the ribbon over them.
	Money = {
		MinWidthPx = { 86, 100 }, -- a pack at least this wide
		MaxWidthPx = 220,
		IconMinPx = 40, -- the pack's icon
		IconMaxPx = 96,
		Aspect = 1.6, -- the height / width the fit prefers: tall cards, one shelf
		RibbonPx = { 30, 36 }, -- "First purchase: double money!"
		RibbonIconShare = 1.2, -- its cash stack, of its height (pokes out a little)
	},
	-- The VIP tab: the VIP card at the left, the other items as rows at the right.
	Vip = {
		SideBySideMinPx = 520, -- narrower: the card, then the rows under it
		CardShare = 0.44, -- the VIP card's share of the width, side by side
		CardMinPx = 260,
		CardMaxPx = 520, -- stacked
		CardMaxHeightPx = 440,
		RowMinPx = 300, -- the rows' column at least this wide beside the card
		RowMaxWidthPx = 620, -- stacked
		RowMaxPx = { 90, 120 }, -- a row never taller than this
		RowIconPx = { 40, 56 },
		RowButtonPx = { 112, 150 }, -- a row's Buy
		HeaderPx = { 32, 44 }, -- the crown and "VIP"
		TitleTextPx = { 26, 34 },
		PerkGapPx = { 3, 8 }, -- under each perk's line
		PerkIconExtraPx = { 6, 8 }, -- a perk's icon is its text size plus this
		TimerColor = { 214, 145, 0 }, -- a row's countdown ("Party on! 12:34 left"), a deep gold
	},
}

-- The case opening (CaseOpening and its CaseOpeningReel, CaseOpeningCard, CaseOpeningGrid and
-- CaseOpeningFx; docs/prompts/ECONOMY_UI_PROMPT.md section 11): a full-screen overlay over the
-- menus with the reel, the prize card and Fast Open's grid, and the same reel inside the result
-- screen for the first win's case. Everything is laid out at the natural sizes below and scaled
-- to fit (phone first: about 1 on a 750 x 361 phone, so its text stays at these sizes). Pixels
-- and seconds. (tune)
Config.UI.CaseOpening = {
	DisplayOrderAbove = 14, -- its ScreenGuis sit this far over the HUD's (the menus sit at +10)
	-- The soft backdrop (UI_STYLE 2 allows no other dim): over the world, and over a menu
	-- (whose own slight dim is already under it) dark enough that the menu's title and tabs do
	-- not read through the reel's title (checked on phones, 2026-09-28). 1 = none.
	BackdropTransparency = 0.5,
	BackdropOverMenuTransparency = 0.45,
	BackdropSeconds = 0.2, -- its fade in and out
	-- B's priority over ContextActionPriority.High: over the menus' (+20) and the result
	-- screen's (+10), under a confirm dialog's (+30).
	BackPriorityAbove = 25,
	ShortScreenPx = 500, -- shorter than this under Roblox's top bar: the stage uses that row too
	MarginPx = 6, -- the least room round the stage's contents
	MinScale = 0.8, -- the overlay's fit never shrinks or grows it past these
	MaxScale = 1.5,
	RevealMinScale = 0.45, -- the result screen's reveal (its frame may be small)
	RevealMaxScale = 1.2,
	StageMinWidthPx = 600, -- the reel is fitted to at least this width (about five cards)
	RevealMinWidthPx = 360, -- in the result screen, at least this
	TitleHeightPx = 40, -- the title row: the case's chest and its name
	TitlePx = 30,
	TitleIconShare = 1.15, -- the chest, of the row's height (it pokes out a little)
	TitleGapPx = 8, -- between the chest and the name
	TitleMinWidthPx = 300, -- Fast Open's stage is at least this wide
	GapPx = 10, -- between the title, the reel (or grid) and the hint
	HintHeightPx = 24, -- "Tap to skip" (the gamepad's A glyph and "Skip" on a gamepad)
	HintPx = 18,
	HintGlyphGapPx = 6,
	ReelSideMarginPx = 12, -- the reel's room from the stage's sides
	CardMarginPx = 12, -- the prize card's room in the fit (its glow and shadow)
	FailCloseSeconds = 2.5, -- an open that did not work: its reason shows this long, then it closes
	-- While the server answers an open, B, Escape and a tap do nothing for this long (the case
	-- is being spent, the reel is coming); after it they close, and a prize that arrives later
	-- shows a line in the menu under it (the cue's NEW tag marks it).
	WaitCloseSeconds = 3,
	DialogGraceSeconds = 0.2, -- an Escape just after a confirm dialog took it is ignored
	-- A cue new to the Index: its finder's money flies from the card's "NEW! +$250" this long
	-- after the card pops (once the pop has settled, so the pill is where it stays).
	FoundFlyDelaySeconds = 0.6,
	CloseBackstopSeconds = 0.3, -- closing: the overlay goes this long after its pop-out at the latest
	RevealZIndex = 40, -- the reveal's frame over the rest of the result screen's frame
	-- The moment grows with the rarity (Config.Cases.Rarities names): turning rays behind the
	-- prize card from RaysFrom, confetti from ConfettiFrom, and from BigFrom the bigger moment
	-- (the longer build-up, Mythic's shimmer, Secret's red glow).
	RaysFrom = "Epic",
	ConfettiFrom = "Legendary",
	BigFrom = "Mythic",
	ShimmerCycleSeconds = 2.4, -- Mythic's glow drifts once through its pastels in this long
	-- The reveal sting by rarity (Config.Audio.Ui keys).
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
	-- A sale's cash chip ("+$600") flying into the money HUD (timings: Progress.Cash's).
	ChipHeightPx = 30,
	ChipTextPx = 24,
	ChipZIndex = 70, -- over everything in the overlay
	-- The reel (CaseOpeningReel).
	Reel = {
		Cards = 40, -- cards on the strip
		PrizeSlot = 34, -- the prize's place: late, with cards after it for the window's right side
		-- Each cue's weight on the strip is its odds (Cases.cueOdds) to this power: 1 = the true
		-- odds (a Standard strip is mostly grey and green); under 1 shows rarer cues more often.
		WeightPower = 1,
		CardWidthPx = 104,
		CardHeightPx = 124,
		GapPx = 8, -- between two cards
		CardCornerPx = 12,
		CardStrokePx = 2.5, -- a card's ink outline
		ThumbShare = 0.9, -- the thumbnail, of the card's width...
		ThumbCentreShare = 0.46, -- ...its middle this far down the card
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
	-- The prize card (CaseOpeningCard). Its height follows what it shows (about 312).
	Card = {
		WidthPx = 380,
		PadPx = 12,
		GapPx = 6, -- between its rows
		CornerPx = 18,
		ArtPx = 140, -- the thumbnail's tile, square
		ArtCornerPx = 14,
		ArtStrokePx = 2.5,
		ThumbShare = 0.9, -- the thumbnail, of the tile
		NamePx = 26, -- the cue's name
		NameHeightPx = 30,
		PillPx = 26, -- the rarity and NEW! / Duplicate pills
		PillTextPx = 16,
		PillPadPx = 12, -- room each side of a pill's words
		PillGapPx = 8,
		ExistPx = 16, -- "1,284 exist"
		ExistHeightPx = 20,
		ButtonsAbovePx = 4, -- extra room over the buttons
		ButtonPx = 44, -- Equip, Sell, Open next / Done (a 44 px touch target)
		ButtonTextPx = 18,
		ButtonGapPx = 8,
		ClosePx = 36, -- the red X in the top-right corner...
		CloseInsetPx = 22, -- ...its middle this far in from the corner
		TouchMinPx = 44, -- ...and its touch area at least this
		BigStrokePx = 5, -- Mythic and Secret: the card's thicker edge
		RaysShare = 2.6, -- the rays behind it (Epic and up), of the thumbnail's tile
		RaysTransparency = 0.35, -- at their brightest
		RaysDegreesPerSecond = 30,
		HaloSpreadPx = 18, -- the glow round the card in the prize's colour
		HaloTransparency = 0.45,
		BigHaloSpreadPx = 30, -- Mythic and Secret: bigger and brighter
		BigHaloTransparency = 0.1,
		GlowInSeconds = 0.5, -- the rays and the glow fade in this long
		ShimmerDegreesPerSecond = 90, -- Mythic's edge, pill and rays shimmer turning
		BreathSeconds = 1.6, -- Secret's glow breathes this slowly
		SecretBreathDepth = 0.5, -- and dims this much at its faintest
		SecretEdgeDim = 0.6, -- its red edge fades this much at the faintest
		ConfettiDelaySeconds = 0.15, -- after the card pops
		ConfettiScale = 1.2, -- Legendary's burst
		BigConfettiScale = 1.8, -- Mythic's and Secret's
	},
	-- Fast Open's grid (CaseOpeningGrid): ten cards in two rows of five.
	Grid = {
		Columns = 5,
		CardWidthPx = 112,
		CardHeightPx = 116,
		GapPx = 10,
		CornerPx = 12,
		StrokePx = 2.5,
		ChosenStrokePx = 5, -- the chosen card's gold outline
		PadPx = 6, -- inside a card
		ThumbPx = 64,
		NamePx = 16, -- a cue's name, two lines at most
		NameHeightPx = 36,
		BackIconShare = 0.62, -- the chest on a face-down card
		PillPx = 20, -- NEW!
		PillTextPx = 14,
		PillPadPx = 8,
		PillInsetPx = 5, -- NEW! and the equipped check sit this far in from the corners
		CheckPx = 22,
		GlowFrom = "Epic", -- cards of this rarity and up glow in their colour
		HaloSpreadPx = 14,
		HaloTransparency = 0.3,
		StartDelaySeconds = 0.25, -- the first card turns after this
		FlipEverySeconds = 0.15, -- then one after another
		FlipSeconds = 0.22, -- one card's turn
		ButtonsAbovePx = 10, -- between the grid and its buttons
		ButtonPx = 44,
		ButtonWidthPx = 150,
		ButtonGapPx = 10,
		ButtonTextPx = 18,
	},
}

-- The Rewards menu (RewardsMenu and its pages RewardsDaily, RewardsPlaytime, RewardsCodes;
-- RewardsFlyer; the reminder toast in Reminders; docs/prompts/ECONOMY_UI_PROMPT.md section 11).
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
	WordsTextPx = { 14, 18 }, -- the reward's words ("2 Standard Cases")
	CountTextPx = { 14, 18 }, -- "x2" on a case's icon
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
	CodeAnswerPx = { 16, 20 }, -- "Code redeemed: +$500 and a Standard Case"
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
	-- (the CashFlyer's chips), each case to the left column's Inventory tile.
	Fly = {
		DisplayOrderAbove = 5, -- its ScreenGui sits this far over a menu's
		CaseSizePx = 56, -- a case chip's picture (a computer)...
		ShortCaseSizePx = 44, -- ...and on a phone
		CountTextPx = 18, -- "x2" on it
		PopSeconds = 0.2, -- pops out at the button with a small overshoot
		PopFromScale = 0.3,
		HangSeconds = 0.3, -- hangs
		FlySeconds = 0.6, -- then flies to the tile
		EndScale = 0.45, -- shrinking to this size as it lands
		ArcLiftShare = 0.3, -- the curve rises this share of the distance...
		ArcMinLiftPx = 50, -- ...and at least this far
		StaggerSeconds = 0.15, -- several cases follow each other
		AfterMoneySeconds = 0.12, -- the cases start this long after the money
		ZIndex = 5,
	},
	-- The reminder toast (Reminders): "Come back tomorrow for your Rare Case" at the bottom
	-- middle when Roblox's menu opens or the window loses focus (GDD 14, ECONOMY 10).
	Toast = {
		DisplayOrderAbove = 6, -- its ScreenGui sits this far over a menu's
		HeightPx = 46,
		ShortHeightPx = 38, -- on a phone
		TextPx = 20,
		ShortTextPx = 16,
		IconShare = 1.35, -- the gift, of the toast's height (it pokes out past the left end)
		PadPx = 16, -- room each side of the words
		MaxWidthPx = 600,
		SideMarginPx = 10, -- never closer to the screen's sides
		BottomPx = 28, -- above the screen's bottom edge
		ShortBottomPx = 10,
		ShowSeconds = 6, -- it shows at least this long...
		LingerSeconds = 4, -- ...and this long after Roblox's menu closes or the window is back
		CooldownSeconds = 120, -- at most one toast this often
	},
}

-- The Trade menu (TradeMenu; trading itself is a later session): the players in this server,
-- each with a greyed Trade button, under a "Trading is coming soon" note. Pairs { a, b } as
-- above. (tune)
Config.UI.Trade = {
	NotePx = { 48, 60 }, -- the note's strip at the top
	NoteTextPx = { 16, 20 }, -- "Trading is coming soon!"
	NoteDetailPx = { 14, 16 }, -- the line under it
	SoonTextPx = { 14, 18 }, -- the gold SOON pill
	RowPx = { 56, 72 }, -- a player's row
	RowGapPx = { 6, 8 },
	RowPadPx = { 6, 10 },
	MaxWidthPx = 680, -- the list is never wider than this (centred)
	NameTextPx = { 16, 20 }, -- the username (ends in "..." when too long)
	RankTextPx = { 14, 16 }, -- "Gold III" under it
	ButtonWidthPx = { 100, 130 },
	ButtonPx = 44,
	HeadshotShare = 0.82, -- the headshot, of the row's height
	BadgeShare = 0.95, -- the rank badge, of the row's height
	Thumbnail = "Size150x150", -- Enum.ThumbnailSize name (Config is loaded by Lune: no Enum)
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
	NoteTextPx = 14, -- "Coming soon" over a placeholder's pill
	-- Solo: the Practice ult button in the bar's place.
	PracticeTone = "Blue", -- a Config.UI.Kit.Buttons name
	PracticeWidthPx = { 150, 180 },
	PracticeHeightPx = { 36, 44 }, -- a phone's keeps a 44 px touch area (HudParts.setMinHit)
	PracticeTextPx = { 14, 18 },
	-- A refusal (UltNotice), for a moment over the bar.
	NoticeTextPx = { 14, 18 },
	NoticeSeconds = 2.2,
	NoticeFadeSeconds = 0.4,
	-- The top bar (MatchHUD): a small ult icon on each opponent's portrait, lit when ready.
	OpponentIconShare = 0.6, -- of the portrait's size
	OpponentDimTransparency = 0.55, -- not ready: faded
	-- The NO ULTS pill: under the top bar's clock, and on the result screen under VS.
	NoUltsTextPx = 14,
	NoUltsPadPx = 8, -- room at each end of its words
	NoUltsColor = { 120, 128, 144 },
	ResultNoUltsHeightPx = 24,
}

-- The Inventory (InventoryMenu and its pages InventoryCues, InventoryCases, InventoryIndex and
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
	CardMinPx = { 104, 128 }, -- a grid card at least this wide (as many columns as fit)
	CardGapPx = { 6, 8 }, -- between two cards
	CardAspect = 1.3, -- a card's height, of its width
	-- A cue card (InventoryCard, in the grid and the Index): the picture, the name on up to
	-- two lines under it, pills over its top corners.
	Card = {
		CornerPx = 12,
		StrokePx = 2, -- its pale outline (Config.UI.Menu.Card.EdgeColor)
		ChosenStrokePx = 4, -- the card whose details show: a thicker blue outline
		PadShare = 0.06, -- inside the card, of its width
		ArtShare = 0.55, -- the picture's size, of the card's height
		NameTextPx = 14, -- the name (the kit's minimum; it wraps rather than shrinks)
		NameLines = 2, -- lines the name may wrap to
		BottomShare = 0.1, -- room kept at the card's bottom for the rarity strip
		PillPx = 20, -- NEW, Equipped, x3 and #412: their height
		PillTextPx = 14,
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
		NameTextPx = { 18, 24 },
		RarityTextPx = { 16, 18 },
		LineTextPx = { 14, 16 }, -- "1,284 exist", "You own 3", "Can't be sold"
		ButtonPx = { 40, 48 }, -- Equip, Sell, Sell duplicates
		ButtonTextPx = { 14, 18 },
		LockPx = { 18, 22 }, -- the padlock before "Can't be sold"
		ThumbShare = 0.86, -- the cue's thumbnail, of the picture's box
	},
	-- The Cases tab: a row per case type owned.
	CaseRowPx = { 60, 84 },
	CaseIconShare = 0.95, -- the chest, of the row's height
	CaseRowPadShare = 0.1, -- inside a row, of its height
	CaseNameTextPx = { 18, 22 },
	CaseCountTextPx = { 14, 18 },
	CaseButtonPx = { 44, 48 },
	CaseButtonWidthPx = { 96, 132 }, -- Open and Open 10
	CaseButtonTextPx = { 14, 18 },
	HintTextPx = { 14, 16 }, -- the line beside Buy more
	BuyMoreWidthPx = { 130, 170 },
	EmptyIconPx = { 64, 110 }, -- the chest over the empty state's line
	EmptyTextPx = { 16, 20 },
	EmptyLineMaxPx = 460, -- the empty state's line wraps at this width
	-- The Index's turning 3D cue (CueViewport, in the Index's detail panel; designer,
	-- 2026-09-28): the game's own cue in a ViewportFrame, thicker so it reads small, turning
	-- round the upright axis. A cue not found yet is one near-black colour.
	Viewport = {
		Thickness = 2.6, -- the stick's diameter times this (a real cue is too thin to read)
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
	-- The red dots on the tab buttons: the NEW count on Cues, unopened cases on Cases, "!" on
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
	-- Who sees it: the table's players, and anyone standing this close to its centre (studs).
	SpectateRadiusStuds = 40,
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

-- Magnet's look and sound (src/client/MagnetFx.luau; ULTIMATES_PROMPT 7.3). Studs unless named;
-- the ball's radius is Config.Balls.RenderRadiusInches (about 0.19 studs). (tune)
Config.UI.MagnetFx = {
	NorthColor = { 255, 70, 80 }, -- the red N ring
	SouthColor = { 70, 150, 255 }, -- the blue S ring
	FieldColor = { 160, 210, 255 }, -- the faint arcs round the armed cue ball
	GlowColor = { 70, 160, 255 }, -- the pull: beams, the pocket ring, the ball's glow
	SparkColor = { 190, 230, 255 },
	BeamSegments = 12, -- a Beam's smoothness
	-- Armed: two rings round the cue ball, tilted RingTiltDegrees from flat and precessing
	-- opposite ways (one turn every RingTurnSeconds), each with a bead running round it.
	RingRadiusBalls = 1.8, -- in ball radii
	RingWidthStuds = 0.025,
	RingTiltDegrees = 62,
	RingTurnSeconds = 2.6,
	RingTransparency = 0.1,
	BeadStuds = 0.07,
	BeadSeconds = 0.9, -- one lap
	-- The arming snap: the rings (and arcs) start this many times wider and snap in.
	SnapSeconds = 0.35,
	SnapFromScale = 2.6,
	LookFadeSeconds = 0.25, -- the rings fade in at readyAt and out as the shot starts
	-- The field arcs: a dipole across the ball turning once every ArcTurnSeconds, a line
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
	-- A pull: two curved beams from the ball to the pocket (a bright one and a fainter one
	-- bowing the other way), thin at the ball and wider at the pocket.
	BeamWidthStuds = { 0.05, 0.14 },
	BeamTransparency = 0.1,
	SecondBeamTransparency = 0.6,
	BeamBowShare = 0.3, -- how far each bows, of the ball-to-pocket distance
	SecondBeamBowScale = 0.6,
	BeamBowSide = 0.8, -- the bow's direction: this much sideways...
	BeamBowUp = 0.6, -- ...and this much up off the cloth
	BeamTextureLengthStuds = 0.8,
	-- The field lines' flow: positive runs from the ball (the beam's start) toward the pocket.
	-- Flip the sign if Studio shows it flowing the wrong way.
	BeamTextureSpeed = 2,
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
	-- The pocket's ring on the cloth (Config.UI.Kit.Art.RingGlow; a beam circle without it).
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
	-- effect"): the moment one of the shooter's balls is hit on a Magnet shot (it starts
	-- moving) it charges with a zap and a spark burst, and small red and blue rings circle it
	-- for the rest of the shot (snapping in from ChargeSnapFromScale wide), with a faint glow.
	ChargeMinSpeed = 0.5, -- in/s: moving at all means it has been hit
	ChargeRingRadiusBalls = 1.7, -- in ball radii
	ChargeRingWidthStuds = 0.03,
	ChargeRingTransparency = 0.2,
	ChargeTurnSeconds = 1.4,
	ChargeSnapFromScale = 3,
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
		LockPx = 30, -- the lock toggle, top right
		-- Right: the odds (the Lucky odds switch, the rarity bars and their lists) and the code box.
		OddsWidthPx = 320,
		SwitchHeightPx = 34,
		BarHeightPx = 38,
		BarGapPx = 8,
		BarTextPx = 20,
		RowHeightPx = 28, -- one ult in an opened bar's list
		RowTextPx = 16,
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
		-- Fast Open's Skip and Auto Spin, between BACK TO MENU and SPIN.
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
		DescTextPx = 14,
		DescWidthPx = 380,
		SlotWidthPx = 124,
		SlotHeightPx = 58,
		SlotGapPx = 6,
		SlotNameTextPx = 16,
		SlotPillHeightPx = 18,
		SlotPillTextPx = 14,
		SlotStripPx = 4,
		LockPx = 22,
		OddsWidthPx = 380,
		SwitchHeightPx = 30,
		BarHeightPx = 32,
		BarGapPx = 6,
		BarTextPx = 16,
		RowHeightPx = 26,
		RowTextPx = 14,
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
	-- The leave reminder's button (Reminders, while the free spin is unused).
	Reminder = { ButtonWidthPx = { 84, 110 }, GapPx = 8, ButtonTextPx = { 14, 18 } },
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
	-- Developer chat commands (DevCommands): typed in the Roblox chat, checked on the server. Who
	-- may use them: anyone in Studio, these user ids, and the owner of the group that owns the
	-- game (rank GroupRank). Anyone else's command does nothing. Their private answers are in
	-- Strings.Dev. The Studio hook ServerStorage.DevCommandsQA runs any of them from a script.
	Commands = {
		Day = "/day", -- the day/sunset cycle fades to day now (the 1 min fade)
		Sunset = "/sunset", -- ...or to sunset; it runs on from there
		-- Ranks and money, acting on the caller only (DevCommands; `/rankhelp` lists them).
		Rank = "/rank", -- /rank gold 3 [xp] | /rank reyes | /rank unranked: set it (no rewards)
		Xp = "/xp", -- /xp 250: a gain through the real rules (peak, rewards, popups); never a loss
		Money = "/money", -- /money 5000: set money
		AddMoney = "/addmoney", -- /addmoney 100: add it, with the flying cash
		-- /result win|lose|draw|firstwin: preview the result screen (sample boosts; no save change)
		Result = "/result",
		NewRank = "/newrank", -- /newrank [tier] [division]: preview NEW RANK! with its reward chips
		ResetData = "/resetdata", -- your own save back to a fresh one
		RankHelp = "/rankhelp", -- lists these
		-- The economy (DevCommands; `/econhelp` lists them), acting on the caller only (a sale
		-- and a Money Party are this server's, like the real ones).
		GiveCue = "/givecue", -- /givecue <id|name> [count]: never Classic or a Unique cue
		GiveCase = "/givecase", -- /givecase <standard|rare|epic|legendary|event> [count]
		OpenCase = "/opencase", -- /opencase <type>: opens one on the reel, like the button
		Inv = "/inv", -- prints your inventory privately
		ClearInv = "/clearinv", -- empties your cues (but Classic) and cases
		Dupes = "/dupes", -- DupeCopies copies of DupeKinds random Common and Uncommon cues
		SetDay = "/setday", -- /setday <1-7> [week]: the login streak's next claim
		NewDay = "/newday", -- as if a new UTC day began (daily claim, playtime, limits)
		Playtime = "/playtime", -- /playtime <minutes>: set today's minutes played
		Buy = "/buy", -- /buy <product> [purchaseId]: the receipt grant with a fake purchase id
		Vip = "/vip", -- /vip on|off: fake owning the VIP pass
		FastOpen = "/fastopen", -- /fastopen on|off: fake owning Fast Open
		Party = "/party", -- starts (or extends) a Money Party
		Policy = "/policy", -- /policy restricted|normal: fake PolicyService's paid random items
		Sale = "/sale", -- /sale <case> <percent> <minutes> | /sale off: a case sale on this server
		Rookie = "/rookie", -- /rookie <n>: set how many real matches you have played
		FreeCase = "/freecase", -- as if you won a real match (the free-case rule)
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
		MaxGive = 100, -- the most copies one /givecue, or cases one /givecase, gives
		DupeKinds = 5, -- /dupes: how many different cues...
		DupeCopies = 3, -- ...and how many copies of each
		MaxSaleMinutes = 10080, -- the longest /sale (a week)
		LineChars = 180, -- /inv packs its lists into chat lines of at most this many characters
		UserIds = { 544959133 }, -- the designer
		GroupRank = 255, -- the group's owner
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
