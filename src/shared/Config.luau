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
	-- Wooden rail width (visual only).
	RailWidthInches = 5.5,
	-- Rail top height above the cloth as a fraction of the ball diameter (visual). The rubber
	-- cushion nose that the balls hit sits lower, see Physics.CushionNoseBallFraction.
	RailHeightBallFraction = 0.8,
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
	-- Jaw facings: the short angled cushion faces either side of each mouth. Length in
	-- inches; the angle is measured off the rail line for corners (regulation 142 degree
	-- shelf = 38 off the rail) and off the perpendicular for sides (103 degree = 13 off).
	-- Balls that enter at a bad angle hit these and rattle out. (tune)
	FacingLengthInches = 1.6,
	CornerFacingDegrees = 38,
	SideFacingDegrees = 13,
	-- Rounded jaw tips at the far end of each facing.
	JawRadiusInches = 0.3,
	-- The pocket OPENING: the hole in the slate the ball actually falls through, and the one
	-- circle both the physics and the art are built from, so they can never disagree.
	--
	-- It is derived, not tuned: the radius is half the mouth width and the circle is placed
	-- so its rim is tangent to the line joining the two cushion noses. At 1.0 a ball entering
	-- the middle of the mouth is over the hole the moment its centre passes the noses, which
	-- is how a real pocket behaves; below 1.0 the opening sits further back and every pocket
	-- keeps a shelf a ball can hang on. Off-centre balls keep a shelf either way, which is
	-- what lets a ball rattle in the jaws. (tune)
	PocketOpeningMouthFraction = 1.0,
	-- Safety net only: a ball whose centre gets this far past the cushion line (in ball
	-- radii) without having crossed an opening rim is taken by the nearest pocket, so a ball
	-- can never escape the table. Ordinary pocketing happens on the rim, above.
	PocketShelfBallRadii = 0.9,
	-- The tip. A ball whose centre crosses the rim is no longer supported and pivots over the
	-- lip under gravity. A ball that crosses by a hair would balance there forever, so the
	-- tip starts from at least this angle off vertical; it is the number that caps how long a
	-- hang can last (1.5 degrees = about a third of a second). (tune)
	PocketTipMinDegrees = 1.5,
	-- The drop: once a ball's centre is over the hole it falls under gravity while the funnel
	-- shape pulls it towards the middle and the liner slows it. It stops this far down. (tune)
	PocketDropDepthInches = 5,
	PocketFunnelAccel = 900, -- in/s^2 towards the pocket centre while dropping
	PocketDragPerSecond = 5, -- fraction of horizontal speed lost per second in the liner
	PocketWallRestitution = 0.25, -- bounce off the liner wall
	-- Filled in at the bottom of this file from the fractions above.
	RailHeightInches = 0,
	CushionHeightInches = 0,
	CornerMouthInches = 0,
	SideMouthInches = 0,
	-- Opening radius, and how far a side opening's centre sits beyond the cushion line. A
	-- corner opening's centre needs no number: it always lands exactly on the table corner
	-- (the mouth midpoint is half a mouth in from the corner along the diagonal, and the
	-- centre sits half a mouth back out from it).
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
	-- Regulation balls are 2.25 in across (radius 1.125). Slightly oversized balls read better
	-- on a phone from the top-down view; the physics scales with whatever is set here. (tune)
	RadiusInches = 1.3,
	MassOunces = 6, -- all balls equal; only ratios matter in collisions
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
	-- Typical pool cloth: 0.15 to 0.25. Higher = spin takes effect sooner, and the skid
	-- after the strike resolves into a roll sooner. At the top of the real range because a
	-- ball that is still sliding when it reaches the far rail reads as ice. (tune)
	SlidingFriction = 0.25,
	-- Rolling resistance once the ball ROLLS without slipping. Typical 0.005 to 0.015.
	-- Higher = balls stop sooner. (tune)
	RollingFriction = 0.012,
	-- Decay of side spin (spin about the vertical axis) while rolling. (tune)
	SpinFriction = 0.044,
	-- Ball-ball coefficient of restitution. Phenolic balls: 0.92 to 0.96. (tune)
	BallRestitution = 0.93,
	-- Ball-cushion coefficient of restitution at the contact point. Real cushions: 0.7 to 0.9.
	-- (tune)
	RailRestitution = 0.8,
	-- Height of the cushion nose above the cloth, as a fraction of the ball diameter.
	-- Regulation is 0.625. Higher kills more top spin on the rebound; at 0.5 (ball-centre
	-- height) the cushion has no effect on spin. (tune)
	CushionNoseBallFraction = 0.625,
	-- Filled in at the bottom of this file.
	CushionNoseHeightInches = 0,
	-- Cushion friction coefficient. Caps how much the cushion can grab the ball along its
	-- length, which is what lets side spin bend the rebound. (tune)
	RailFriction = 0.2,
	-- Below this speed (in/s) and side spin (rad/s) a ball is snapped to rest.
	RestSpeed = 1.0,
	RestSpin = 0.6,
	-- Contact-point speed (in/s) under which a ball counts as rolling, not sliding.
	SlideEpsilon = 1e-4,
	-- Safety caps so a bad shot can never hang the game.
	MaxShotSeconds = 40,
	MaxEventsPerStep = 200,
	-- A ball that hits surfaces this many times within one step, each less than
	-- InstantHitSeconds after the last, is wedged and gets stopped.
	MaxInstantHits = 24,
	InstantHitSeconds = 1e-5,
	-- Tiny separation kept between touching balls to avoid re-colliding forever.
	ContactSlop = 1e-5,
}

---------------------------------------------------------------------------------------------
-- Cue strike: turns (power, spin offset) into the cue ball's initial velocity and spin
---------------------------------------------------------------------------------------------
Config.Cue = {
	-- Cue ball speed at full power. 30 mph = 528 in/s, a very strong break. (tune)
	MaxSpeed = 528,
	-- Speed at the smallest power that still counts as a shot. (tune)
	MinSpeed = 15,
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
	-- Angular velocity from an off-centre hit: w = SpinFactor * v * offset / R.
	-- 2.5 is the rigid-sphere value; lower it if spin feels too strong. (tune)
	SpinFactor = 2.5,
	-- Visual cue stick (placeholder built from parts), in STUDS so it matches the avatar:
	-- a real cue is about 85% of a person's height.
	CueLengthStuds = 4.4,
	CueButtDiameterStuds = 0.13,
	CueTipDiameterStuds = 0.06,
	-- Resting gap between the tip and the cue ball while aiming (table inches), how far the
	-- stick draws back at full power on the bar (studs), and how much the butt is raised.
	CueRestGapInches = 2.5,
	CuePullBackStuds = 1.3,
	CueElevationDegrees = 4,

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
-- The lounge: where the twelve tables stand (studs). Physics x -> world X, physics y ->
-- world -Z, up -> world Y, all turned by the table's yaw. See src/shared/Placement.luau.
---------------------------------------------------------------------------------------------
Config.Lounge = {
	-- Transcribed from assets/lounge/Markers.json (schema_version 1). Y is the FLOOR height
	-- of the tier the table stands on, not the cloth: Placement.toWorld adds
	-- Table.SurfaceHeightStuds (2.9) on top, which is exactly the package's
	-- cloth_height_above_floor. Yaw is degrees about world +Y.
	--
	-- Do not hand-edit: tests/lounge_layout_test.luau checks every number against
	-- Markers.json, so a typo here fails tools/test.sh.
	-- Tables 1-4 are the front row, 5-8 the middle tier, 9-12 the rear tier.
	Tables = {
		{ id = 1, X = -30, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 2, X = -10, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 3, X = 10, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 4, X = 30, Y = 0, Z = 0, YawDegrees = 90 },
		{ id = 5, X = -30, Y = 2.4, Z = -43, YawDegrees = 90 },
		{ id = 6, X = -10, Y = 2.4, Z = -43, YawDegrees = 90 },
		{ id = 7, X = 10, Y = 2.4, Z = -43, YawDegrees = 90 },
		{ id = 8, X = 30, Y = 2.4, Z = -43, YawDegrees = 90 },
		{ id = 9, X = -30, Y = 4.8, Z = -86, YawDegrees = 90 },
		{ id = 10, X = -10, Y = 4.8, Z = -86, YawDegrees = 90 },
		{ id = 11, X = 10, Y = 4.8, Z = -86, YawDegrees = 90 },
		{ id = 12, X = 30, Y = 4.8, Z = -86, YawDegrees = 90 },
	},
	-- The imported lounge is a placeholder the designer has set aside, so the game currently
	-- runs on a plain baseplate. FALSE means: do not expect lounge geometry in the place,
	-- do not build the pendant lights or the sofa seats, and leave Lighting alone.
	--
	-- Nothing else changes. The tables are still server-owned, shots are still validated and
	-- broadcast by the server, and the pads still work; there are just fewer tables and no
	-- room around them. Turn this back on when there is a lounge worth standing in.
	Enabled = false,

	-- How many tables to build, taken from the front of Tables below. Twelve is the lounge;
	-- one is what the shot is actually tested on.
	TableCount = 1,

	-- Which table the client treats as "the" table before it has a seat.
	ActiveTableId = 1,

	-- How many tables draw their balls at once. Twelve racked tables is 192 ball meshes for
	-- a scene that already carries a quarter of a million triangles of table, and the ones
	-- across the room are a few pixels each. The nearest few are bound to a small pool of
	-- renderers instead; every table still simulates, it just may not be drawn.
	RenderedTables = 4,
	-- How often the pool is re-pointed at the nearest tables. Every frame is wasteful and
	-- the player cannot cross twenty studs in half a second.
	RebindEverySeconds = 0.5,

	-- Where the player spawns (Markers.json "Spawn_Lounge", the seating area).
	Spawn = { X = 0, Y = 0.1, Z = 20 },

	-- The six FBX packages and how each behaves once imported, from step 5 of
	-- assets/lounge/Readme.md. Two deliberate departures from that note, both so the room
	-- is playable rather than only pretty: the window glass collides (the package would
	-- have it pass-through, and there is no proxy behind it, so players would walk out of
	-- the building) and the furniture collides (there is no proxy for the sofas either).
	Packages = {
		Lounge_Architecture = { CanCollide = true, Collision = "Box", CastShadow = true },
		Lounge_Collision = { CanCollide = true, Collision = "Box", CastShadow = false, Hide = true },
		Lounge_Emissive = { CanCollide = false, CastShadow = false, Material = "Neon" },
		Lounge_Furniture = { CanCollide = true, Collision = "Box", CastShadow = true },
		Lounge_Props = { CanCollide = false, CastShadow = false },
		Lounge_Signs = { CanCollide = false, CastShadow = false },
	},
	-- Per-part exceptions, by exact name or by a name fragment.
	PartRules = {
		Glass_Windows = { Material = "Glass", Transparency = 0.65, Color = { 214, 232, 240 } },
	},
	-- Anything whose name contains one of these is flat on the floor and must not be walked
	-- into (a rug with a collision box is a step).
	NoCollideFragments = { "Rug" },
	-- Invisible seats on the lounge furniture. GDD section 10 wants the chairs and sofas
	-- sittable; sitting is free look only, so a spectator keeps the normal walk-around
	-- camera (decided 2026-09-20, closing the open question in GDD section 6). Table
	-- cameras for spectators are Roadmap 2.3.
	Seating = {
		{ Part = "Furniture_Sofa_Teal_Foreground", Seats = 3 },
		{ Part = "Furniture_Sofa_Teal_Left", Seats = 3 },
		{ Part = "Furniture_Loveseat_Cream", Seats = 2 },
		{ Part = "Furniture_Armchair_Teal_Right", Seats = 1 },
		{ Part = "Furniture_Ottoman_Butter", Seats = 1 },
	},
	-- Where a seated player faces: the middle of the lounge rug, so everyone on the sofas
	-- looks inwards at the seating area rather than at a wall.
	SeatingFocus = { X = 0, Y = 0, Z = 26.8 },
	-- How far up the furniture the seat sits, as a fraction of its height, and the seat
	-- pad's size in studs.
	SeatHeightFraction = 0.55,
	SeatSizeStuds = { 2.2, 0.4, 2.2 },
	-- Parts the package ships that the game provides for real, so they are deleted rather
	-- than left to clash. Table_DisplayProps_NN is a tray of fake balls and a rack sitting
	-- on each table's cloth, put there so the Blender render looked furnished; the real
	-- tables carry sixteen simulated balls and the fakes sat on top of them.
	RemovePartFragments = { "Table_DisplayProps" },

	-- How far the pendant fixtures are lifted above where the Blender package hung them.
	-- The package drops them to 7.5 studs above the floor, which is 4.6 above the cloth,
	-- and the aim camera sits at about 10.8 - so the fixture hung squarely between the
	-- player and the table. Lifting shortens the drop; the cord still meets the ceiling.
	PendantLiftStuds = 4.5,

	-- One pendant over each table. Markers.json puts every pendant directly above its own
	-- table at the same height above that tier's floor, so one number covers all twelve.
	-- Shadows are OFF on purpose: twelve shadow-casting lights is the most expensive thing
	-- this scene could contain, and the sun does the shadow work instead. This replaces the
	-- old per-table SpotLight that did not scale past one table.
	Pendant = {
		HeightAboveFloor = 7.42,
		Brightness = 1.8,
		RangeStuds = 24,
		AngleDegrees = 120,
		Color = { 255, 177, 110 }, -- 3000 K, warm
		Shadows = false,
	},

	-- Lighting recipe supplied with the package. Its own notes call these a starting point
	-- that was never evaluated inside Studio, so treat every number as (tune).
	Lighting = {
		ClockTime = 17.4,
		Brightness = 2,
		Ambient = { 150, 146, 133 },
		OutdoorAmbient = { 170, 154, 130 },
		ColorShiftTop = { 18, 10, 3 },
		EnvironmentDiffuseScale = 0.65,
		EnvironmentSpecularScale = 0.5,
		Bloom = { Intensity = 0.12, Size = 20, Threshold = 1.2 },
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.04,
			Saturation = 0.04,
			TintColor = { 255, 244, 224 },
		},
	},
}

---------------------------------------------------------------------------------------------
-- Table model (imported from Blender, see assets/table/Readme.md)
---------------------------------------------------------------------------------------------
Config.TableModel = {
	-- If a Model with this name exists in ServerStorage, it is used as the visible table
	-- instead of the parts-and-solid-modelling build. It must be authored in studs with its
	-- origin at the table centre on the floor (the Blender package does this), and its
	-- physics numbers must match Config.Table: the 9 ft preset does.
	Name = "PoolTableModel",
	-- Mesh names inside the model and how each behaves for the walking character.
	Meshes = {
		Bed = { CanCollide = false },
		Cushions = { CanCollide = false },
		Rails = { CanCollide = true, Collision = "Hull" },
		Pockets = { CanCollide = false },
		Apron = { CanCollide = true, Collision = "Box" },
		Legs = { CanCollide = true, Collision = "Box" },
		Sights = { CanCollide = false },
	} :: { [string]: { CanCollide: boolean, Collision: string? } },
	-- PBR maps per mesh (uploaded 2026-09-19 from assets/table/textures). Applied in Edit
	-- mode by TableBuilder.applyModelTextures(); scripts cannot write SurfaceAppearance maps
	-- at runtime, so the textured model must be saved in the place.
	Textures = {
		Bed = {
			Color = "rbxassetid://102609553781623",
			Normal = "rbxassetid://99826595778879",
			Roughness = "rbxassetid://79061809007876",
			Metalness = "rbxassetid://117796518523512",
		},
		Cushions = {
			Color = "rbxassetid://83703463882218",
			Normal = "rbxassetid://123457432035826",
			Roughness = "rbxassetid://119649434177392",
			Metalness = "rbxassetid://117796518523512",
		},
		Rails = {
			Color = "rbxassetid://119510198309668",
			Normal = "rbxassetid://123261438390044",
			Roughness = "rbxassetid://104978786475849",
			Metalness = "rbxassetid://117796518523512",
		},
		Pockets = {
			Color = "rbxassetid://94430625696465",
			Normal = "rbxassetid://88074073045389",
			Roughness = "rbxassetid://102085622441837",
			Metalness = "rbxassetid://117796518523512",
		},
		Apron = {
			Color = "rbxassetid://96632718126173",
			Normal = "rbxassetid://98672244173539",
			Roughness = "rbxassetid://131454951510818",
			Metalness = "rbxassetid://117796518523512",
		},
		Legs = {
			Color = "rbxassetid://95182369270183",
			Normal = "rbxassetid://134542152833241",
			Roughness = "rbxassetid://76006405458350",
			Metalness = "rbxassetid://117796518523512",
		},
		Sights = {
			Color = "rbxassetid://88180350419004",
			Normal = "rbxassetid://74066395438874",
			Roughness = "rbxassetid://74333689947684",
			Metalness = "rbxassetid://117796518523512",
		},
	} :: {
		[string]: { Color: string, Normal: string, Roughness: string, Metalness: string },
	},
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
	-- While a shot plays the camera zooms out to the whole-table view (if the player was
	-- zoomed in) so every ball's path is visible, holds there, then eases back to the
	-- player's zoom when the balls stop.
	Shot = {
		ZoomOut = true, -- false = stay at the player's zoom during the shot
		FocusWeight = 0, -- gaze pull toward the moving cue ball: 0 = none, 1 = track it
		Smoothing = 0.35, -- seconds to ease out at the strike
		ReturnSmoothing = 0.5, -- seconds to ease back in after the balls stop
		ReturnSeconds = 1.5, -- how long the slower easing applies after the shot ends
	},
}

---------------------------------------------------------------------------------------------
-- The floor pad you step on to join a table (GDD section 6)
---------------------------------------------------------------------------------------------
Config.Pad = {
	-- Where the pad sits: this far from the table centre, towards the head rail, on the
	-- floor of that table's tier. It has to clear the place the SHOOTER stands, not just
	-- the rail: the table half-length with rails is 8.88 studs and AvatarPose parks the
	-- shooter at the rim, so a pad reaching in to 8.88 would sit under their feet and seat
	-- them again the instant they left.
	DistanceStuds = 14,
	SizeStuds = { 6, 0.08, 6 },
	-- How close the character has to be to count as standing on it. 14 - 3 = 11 studs, well
	-- clear of the shooter at the rim.
	RadiusStuds = 3,
	-- Occupancy is polled on the server rather than using .Touched, which misses a player
	-- who walks on and stands still. Two polls in a row are needed before it counts, so
	-- somebody crossing a pad on the way to another table is not dragged into a seat.
	PollsPerSecond = 5,
	-- Three polls is 0.6s. A player walking straight across a 6 stud pad at the default 16
	-- studs per second is only on it for about 0.37s, so they pass through without being
	-- seated, which is exactly what this milestone's "a third player walks between the
	-- tables" test does.
	DwellPolls = 3,
	-- After leaving a table, that table's pad ignores you for this long. Without it you can
	-- never leave: the shooter is parked at the rail, which is barely two studs from the
	-- pad, so the next poll sees you standing on it and sits you straight back down.
	RejoinCooldownSeconds = 2,
	-- Colours (RGB 0-255). Green means somebody is on this table, which is what GDD section
	-- 6 asks for: you can see a table is being used from across the room.
	FreeColor = { 70, 74, 84 },
	OccupiedColor = { 80, 220, 110 },
	FullColor = { 235, 170, 60 },
	FreeTransparency = 0.45,
	ActiveTransparency = 0.15,
	-- The ring of light around an occupied pad.
	GlowStuds = 0.6,
	-- Sound played to everyone nearby when a player steps on. Empty = silent (no asset yet).
	StepSoundId = "",
	StepSoundVolume = 0.5,
	-- Seats a table offers before it is full. 1v1 for now; teams are Roadmap 2.5.
	MaxSeats = 2,
	-- The pad flashes when somebody steps on it (GDD section 6 asks for a sound and a VFX).
	-- The sound waits on an asset; the flash is a brightness pulse, which needs none.
	FlashBrightness = 6,
	FlashSeconds = 0.45,
}

---------------------------------------------------------------------------------------------
-- Live aim: opponents and spectators watch the shooter's cue turn
---------------------------------------------------------------------------------------------
Config.Aim = {
	-- How often a shooter tells the server where they are aiming, and how often the server
	-- passes every table's aim on. Ten a second is plenty for a cue that turns slowly, and
	-- the stream is unreliable, so a dropped one costs a frame of lag and nothing else.
	SendsPerSecond = 10,
	BroadcastsPerSecond = 10,
	-- Do not send at all unless the aim actually moved this far (radians). A player resting
	-- their thumb should cost nothing.
	MinChangeRadians = 0.004,
	-- How fast a watched cue eases to each new angle. The stream is ten a second; without
	-- easing the remote cue would visibly step.
	SmoothingSeconds = 0.08,
	-- ARCHITECTURE.md section 4: the aim angle and the ball in hand travel, never the
	-- guideline and never the power. Watching someone line up is the point; seeing their
	-- aiming aid is not.
}

---------------------------------------------------------------------------------------------
-- Avatar (the shooter's R15 character at the table)
---------------------------------------------------------------------------------------------
Config.Avatar = {
	-- Transparency while aiming (1 = invisible).
	AimTransparency = 0.9,
	-- The shooter is hidden outright while the balls are moving, and comes back when they
	-- stop. Watching a faded body slide around the cloth chasing the cue ball was worse
	-- than not seeing them at all, and the shot is the thing worth looking at.
	HideWhileShooting = true,
	-- Hats, hoods, wings and other accessories are hidden while aiming so they cannot cover
	-- the table; the body itself stays as a faded silhouette.
	HideAccessoriesWhileAiming = true,
	-- When the camera ends up close to the character (the ball at the near rail, aiming
	-- away), the character fades out completely so it never covers the cue ball. Fully
	-- invisible within FadeNearStuds of the camera, the normal AimTransparency from
	-- FadeFarStuds out, blended in between.
	FadeNearStuds = 3,
	FadeFarStuds = 8,
	-- Where the character stands (studs, avatar scale): this far behind the cue ball along
	-- the aim line, and shifted sideways so the cue runs past the chin (positive = the
	-- shooter's right).
	StandBackStuds = 3.6,
	SideOffsetStuds = 0.35,
	-- When that spot would be on the table, the character stands at the rail instead and
	-- reaches over it. The stretch pose blends in over this many studs of reach past a
	-- normal stance. It used to be 1.2, but a plain shot from the middle of the table is
	-- already 5.3 studs of reach, so EVERY shot came out at full stretch - which is why the
	-- shooter always looked like they were lying across the cloth.
	StretchBlendStuds = 6,
	-- Past a certain reach there is no stance that reads as a person: the cue ball against
	-- the far cushion with the shot going INTO it is nearly the length of the table away
	-- from anywhere you could stand. Rather than contort further, the body fades out.
	-- In STUDS of reach past a normal stance, so it is comparable with StretchBlendStuds:
	-- a shot from the middle of the table is about 5.3 and stays fully visible, while the
	-- worst reach on a 9 ft table is about 13 and is gone.
	ReachFadeStartStuds = 8,
	ReachFadeEndStuds = 12,
	-- Procedural aiming pose. Joint rotations in degrees applied on top of the rest pose:
	-- {pitch, yaw, roll} as CFrame.Angles(X, Y, Z). Negative pitch = bend/tilt forward.
	Pose = {
		Waist = { -68, 0, 0 },
		Neck = { 62, 0, 0 },
		LeftShoulder = { -75, 0, 30 }, -- bridge arm reaches forward along the cue
		LeftElbow = { -15, 0, 0 },
		LeftWrist = { -20, 0, 0 },
		RightShoulder = { 30, 0, -28 }, -- grip arm hangs back along the butt
		RightElbow = { -85, 0, 0 },
		RightWrist = { 0, 0, 0 },
		LeftHip = { 12, 18, 0 },
		RightHip = { -12, -18, 0 },
		LeftKnee = { -10, 0, 0 },
		RightKnee = { -10, 0, 0 },
	},
	-- Stretching over the rail: torso nearly flat, bridge arm fully extended, back leg
	-- lifted for balance, like a player reaching for a long shot.
	StretchPose = {
		Waist = { -88, 0, 0 },
		Neck = { 78, 0, 0 },
		LeftShoulder = { -100, 0, 18 },
		LeftElbow = { 0, 0, 0 },
		LeftWrist = { -10, 0, 0 },
		RightShoulder = { 10, 0, -18 },
		RightElbow = { -60, 0, 0 },
		RightWrist = { 0, 0, 0 },
		LeftHip = { 40, 8, 0 },
		RightHip = { -6, -10, 0 },
		LeftKnee = { -25, 0, 0 },
		RightKnee = { -4, 0, 0 },
	},
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
		-- Aim rate at full deflection. The curve makes small pushes much finer, which is
		-- what the drag path gets from FineDragSpeedPx. 2 = a squared response.
		AimDegreesPerSecond = 80,
		AimCurve = 2,
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
-- Guideline
---------------------------------------------------------------------------------------------
Config.Guideline = {
	-- Length of the short lines drawn after first contact (object ball and cue ball), and
	-- how much shorter the cue ball's line is.
	StubLengthInches = 14,
	CueStubScale = 0.6,
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
			-- rattle_1, peak 0.425
			{
				Id = "rbxassetid://104388069204336",
				Gain = 1.18,
				FromSpeed = 6,
				UpToSpeed = math.huge,
			},
			-- rattle_2, peak 0.267
			{
				Id = "rbxassetid://84658060587712",
				Gain = 1.87,
				FromSpeed = 6,
				UpToSpeed = math.huge,
			},
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
		-- the garnish. See Config.Audio.Bonus for how far under, and Audio.attach for the one
		-- case it is withheld - a scratch is not a reward.
		PocketBonus = {
			-- ball_pocketed_bonus_sfx, peak 0.786, 3.496s
			{ Id = "rbxassetid://139288823087630", Gain = 0.64 },
		},
		-- The tick while the aim turns. A UI click, not a pool sound. Replace it the same way
		-- as the rest; this is v1 of the designer's own recording, in to be listened to.
		--
		-- It is 0.107s long where the library click it replaced was 0.022s, which is what
		-- MinSecondsBetweenTicks below exists for.
		AimTick = {
			{ Id = "rbxassetid://103816034774626", Gain = 0.69 }, -- turn_tick_1, peak 0.729
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
	-- The bright sting over the top of the drop. Flat, like the drop: it is a reward for
	-- pocketing a ball, and a ball that trickles in earned it just as much as one that was
	-- smashed in. Pitched dead straight, because a UI sting that wanders in pitch stops
	-- sounding deliberate. The volume is set so it lands about 16 dB UNDER the drop at the
	-- drop's loudest - there, felt more than heard, never the thing you notice first. It was
	-- 0.25 (12 dB under) for a day and sat too far forward at the designer's ear. This is the
	-- number to move if it disappears or creeps back out in front. (tune)
	Bonus = { MinVolume = 0.16, MaxVolume = 0.16, MinPitch = 1, MaxPitch = 1, PitchJitter = 0 },
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
	-- ordinary play, which is exactly the ask.
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
	-- zoom alone, which reads as "the volume is broken". Lounge tables are 20+ studs apart,
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
			-- The burst when a ball drops. Coloured from the ball itself so the 8 reads
			-- black and a stripe reads its own colour.
			Pocket = {
				Enabled = true,
				Particles = 18,
				EightBallParticles = 48,
				SpeedStuds = 9,
				Lifetime = 0.45,
				SizeStuds = 0.5,
				-- A brief light in the pocket so the drop registers even off-screen edge.
				FlashBrightness = 4,
				FlashRangeStuds = 10,
				FlashSeconds = 0.25,
			},
		},
	},
}

Config.UI = {
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
}

---------------------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------------------
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
	Config.Physics.CushionNoseHeightInches = Config.Physics.CushionNoseBallFraction * D

	-- Strike bands: power fractions -> the cue ball speeds SoundMix.pickBanded compares
	-- against. Same curve as Cue.speedForPower, which cannot be required from here (Cue
	-- requires Config), so it is spelled out from the numbers Config already owns.
	local C = Config.Cue
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
