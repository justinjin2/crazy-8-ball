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
	-- A ball drops once its centre is this far past the cushion line (as a fraction of the
	-- ball radius, 1 = the ball is fully over the shelf) or inside the pocket's capture
	-- circle (radius and inset in ball diameters). (tune)
	PocketShelfBallRadii = 0.9,
	CornerPocketRadiusBallFraction = 0.75,
	CornerPocketInsetBallFraction = 0.95,
	SidePocketRadiusBallFraction = 0.8,
	SidePocketInsetBallFraction = 1.05,
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
	CornerPocketRadiusInches = 0,
	CornerPocketInsetInches = 0,
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
	-- Glossy look (tune in the look pass).
	Reflectance = 0.12,
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
	-- Typical pool cloth: 0.15 to 0.25. Higher = spin takes effect sooner. (tune)
	SlidingFriction = 0.2,
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
	-- power (0..1) -> speed uses power^PowerCurve, so the low end is finer. (tune)
	PowerCurve = 1.6,
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
}

---------------------------------------------------------------------------------------------
-- World placement (studs). Physics x -> world X, physics y -> world -Z, up -> world Y.
---------------------------------------------------------------------------------------------
Config.World = {
	-- Floor-level centre of the table in Workspace.
	TableOrigin = { X = 0, Y = 0, Z = 20 },
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
	-- The hole is cut this much wider than the physics capture circle (inches).
	PocketLinerExtraInches = 0.5,
	-- Leather U casting on the rail: how far it reaches out from the hole edge and how tall
	-- it stands above the rail; and the thickness of the leather lining the hole wall.
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
		-- phone with the table crosswise). Min is the floor for the zoomed-in close view.
		PitchPreferred = 40,
		PitchMax = 60,
		PitchMin = 35,
		PitchSamples = 6, -- pitches tried between Preferred and Max (internal)
		PitchBias = 0.06, -- fill advantage (fraction of screen) a steeper pitch must beat to win
		-- Fraction of the screen kept clear around the table.
		FitMargin = 0.05,
		-- Camera distance search range for the whole-table fit, in table inches (internal).
		DistanceMinInches = 40,
		DistanceMaxInches = 400,
		-- Seconds the camera takes to settle after an aim change (smaller = snappier).
		Smoothing = 0.18,
		-- Zoom: 1 = whole table fitted. Below 1 the camera closes in on the cue ball (the focus
		-- blends from the table focus to the ball). Pinch on touch or scroll on PC.
		ZoomMin = 0.45,
		ZoomMax = 1.0,
	},
	-- While a shot plays the camera stays put but its gaze drifts towards the cue ball.
	Shot = {
		FocusWeight = 0.6, -- 0 = keep looking down the original aim line, 1 = track the cue ball
		Smoothing = 0.35,
	},
}

---------------------------------------------------------------------------------------------
-- Joining the table
---------------------------------------------------------------------------------------------
Config.Join = {
	-- Hold E (or the on-screen button on phones) near the table to start playing.
	PromptActionText = "Play pool",
	PromptObjectText = "8-Ball table",
	HoldSeconds = 0.6,
	-- How close (studs from the table centre) the prompt appears.
	PromptDistanceStuds = 14,
}

---------------------------------------------------------------------------------------------
-- Avatar (the shooter's R15 character at the table)
---------------------------------------------------------------------------------------------
Config.Avatar = {
	-- Transparency while aiming and while a shot plays (1 = invisible).
	AimTransparency = 0.9,
	ShotTransparency = 0.6,
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
	-- stretches over it. The stretch pose blends in over this many studs of "overhang".
	StretchBlendStuds = 1.2,
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
	-- An aim tick fires every this many degrees of rotation.
	TickEveryDegrees = 2,
	-- Zoom factor per mouse-wheel notch.
	ZoomStep = 1.12,
}

---------------------------------------------------------------------------------------------
-- Guideline
---------------------------------------------------------------------------------------------
Config.Guideline = {
	-- Length of the short lines drawn after first contact (object ball and cue ball), and
	-- how much shorter the cue ball's line is.
	StubLengthInches = 14,
	CueStubScale = 0.6,
	-- The path is a thin flat strip with dashes that scroll towards the target.
	LineWidthStuds = 0.07,
	DashTileStuds = 0.34,
	DashSpeed = 2.0, -- tiles per second
	DashFlip = true,
	-- The contact ("ghost") ball is a white ring outline, slightly larger than the ball.
	RingScale = 1.08,
	-- Images (assets/ui/guide_dash.png, guide_ring.png). Empty = plain shapes.
	DashTextureId = "rbxassetid://83727874065758",
	RingTextureId = "rbxassetid://137854164925995",
	HeightAboveClothInches = 0.12,
	Color = { 255, 255, 255 },
	LineTransparency = 0.15,
	StubTransparency = 0.3,
}

---------------------------------------------------------------------------------------------
-- Audio (asset ids are placeholders until the user picks sounds, see docs/SOUNDS.md)
---------------------------------------------------------------------------------------------
Config.Audio = {
	Ids = {
		CueStrike = "",
		BallClack = "",
		RailThud = "",
		PocketDrop = "",
		AimTick = "",
	},
	-- Impact speed (in/s) that maps to full volume, and the volume/pitch ranges.
	FullVolumeSpeed = 200,
	Clack = { MinVolume = 0.15, MaxVolume = 1.0, MinPitch = 0.92, MaxPitch = 1.12 },
	Rail = { MinVolume = 0.1, MaxVolume = 0.7, MinPitch = 0.9, MaxPitch = 1.05 },
	Strike = { MinVolume = 0.3, MaxVolume = 1.0, MinPitch = 0.95, MaxPitch = 1.1 },
	Pocket = { Volume = 0.9 },
	Tick = { Volume = 0.35 },
}

---------------------------------------------------------------------------------------------
-- Effects and UI
---------------------------------------------------------------------------------------------
Config.Effects = {
	-- Seconds for a pocketed ball to drop out of sight.
	SinkDropSeconds = 0.35,
	SinkBurstParticles = 18,
	EightBallBurstParticles = 48,
	PopupSeconds = 1.1,
}

Config.UI = {
	-- Power bar on the right edge of the screen. Height is a fraction of the screen, clamped.
	PowerBarWidthPx = 52,
	PowerBarHeightFraction = 0.62,
	PowerBarMinHeightPx = 140,
	PowerBarMaxHeightPx = 300,
	PowerBarRightMarginPx = 18,
	-- Fine-aim nudge buttons at the bottom (pixels).
	NudgeButtonPx = 56,
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
	-- Print physics events to the console.
	LogEvents = false,
	-- Print a timing line when a shot finishes playing back.
	LogPlayback = true,
	-- Largest slice of shot time played per rendered frame. Keeps a hitch from skipping play.
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
	T.CornerPocketRadiusInches = T.CornerPocketRadiusBallFraction * D
	T.CornerPocketInsetInches = T.CornerPocketInsetBallFraction * D
	T.SidePocketRadiusInches = T.SidePocketRadiusBallFraction * D
	T.SidePocketInsetInches = T.SidePocketInsetBallFraction * D
	Config.Physics.CushionNoseHeightInches = Config.Physics.CushionNoseBallFraction * D
end

return Config
