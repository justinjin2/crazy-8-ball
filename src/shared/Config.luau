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
	-- Playing surface, cushion nose to cushion nose.
	LengthInches = 100,
	WidthInches = 50,
	-- 1 stud = 10 inches (25.4 cm). Roblox's own convention is roughly 28 cm per stud, so an
	-- R15 avatar (about 5 studs tall) looks right standing at a 3-stud-high table.
	StudsPerInch = 0.1,
	-- Height of the cloth above the floor.
	SurfaceHeightInches = 30,
	-- Cushion rails, visual only: how wide the wooden rail is and how high the cushion rises.
	RailWidthInches = 5.5,
	RailHeightInches = 1.4,
	-- Slate/frame thickness below the cloth, visual only.
	BedThicknessInches = 2,
	-- Pockets. Rails stop short of each pocket, leaving a mouth. A ball is pocketed when its
	-- centre enters the pocket's capture circle or crosses the cushion line into the pocket.
	-- Mouth widths are the gap between the two jaws. Regulation: corner 4.5-5 in, side 5-5.5.
	CornerMouthInches = 4.7,
	SideMouthInches = 5.2,
	-- Jaws: small fixed circles at the rail ends either side of every mouth. A ball that
	-- clips one rattles instead of passing a sharp corner. (tune)
	JawRadiusInches = 0.3,
	-- Capture circle radius and how far its centre sits beyond the cushion line. (tune)
	CornerPocketRadiusInches = 2.3,
	CornerPocketInsetInches = 1.4,
	SidePocketRadiusInches = 2.6,
	SidePocketInsetInches = 2.2,
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
	RadiusInches = 1.125, -- regulation 2.25 inch diameter
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
		-- [ballNumber] = "rbxassetid://..." white disc with the number, transparent elsewhere
		Numbers = {} :: { [number]: string },
		-- one white band on transparent, tinted per ball with Decal.Color3
		StripeBand = "",
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
	-- Height of the cushion nose above the cloth. Regulation is 62.5% of the ball diameter
	-- (1.41 in). Higher kills more top spin on the rebound; at ball-centre height (1.125) the
	-- cushion has no effect on spin. (tune)
	CushionNoseHeightInches = 1.41,
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
	-- Visual cue stick dimensions.
	CueLengthInches = 58,
	CueButtDiameterInches = 1.2,
	CueTipDiameterInches = 0.5,
}

---------------------------------------------------------------------------------------------
-- World placement (studs). Physics x -> world X, physics y -> world -Z, up -> world Y.
---------------------------------------------------------------------------------------------
Config.World = {
	-- Floor-level centre of the table in Workspace.
	TableOrigin = { X = 0, Y = 0, Z = 20 },
}

---------------------------------------------------------------------------------------------
-- Look (colours are RGB 0-255, materials are Enum.Material names)
---------------------------------------------------------------------------------------------
Config.Look = {
	FeltColor = { 20, 105, 60 },
	FeltMaterial = "Fabric",
	RailColor = { 62, 38, 24 },
	RailMaterial = "Wood",
	FrameColor = { 45, 28, 18 },
	FrameMaterial = "WoodPlanks",
	BallMaterial = "SmoothPlastic",
	PocketColor = { 12, 10, 10 },
}

---------------------------------------------------------------------------------------------
-- Camera (studs, degrees)
---------------------------------------------------------------------------------------------
Config.Camera = {
	-- Aim views the player can toggle between (milestone 4):
	--   "topdown": GamePigeon style, high over the table so the whole board is visible,
	--              tilted just enough to read as 3D.
	--   "behind":  low 3D view behind the cue ball looking down the shot, cue stick in view,
	--              the avatar mostly transparent.
	-- The shot camera (after the strike) is the same cinematic follow view in both cases.
	DefaultAimView = "topdown",
	TopDown = {
		PitchDegrees = 72, -- degrees below horizontal (90 = straight down)
		DistanceStuds = 12.5,
		FieldOfView = 55,
		-- true: the view turns with the aim so the shooter is always at the bottom.
		-- false: fixed over the table, only the aim line turns.
		OrbitWithAim = false,
		FixedAzimuthDegrees = 0,
	},
	Behind = {
		PitchDegrees = 16,
		DistanceStuds = 2.6, -- behind the cue ball along the aim line
		HeightStuds = 0.9, -- above the cloth
		FieldOfView = 60,
	},
	-- Shot view: lower, closer, follows the action.
	Shot = {
		PitchDegrees = 32,
		DistanceStuds = 7,
		FieldOfView = 60,
	},
	-- Seconds for the camera to ease between views / follow its target. (tune)
	ModeBlendSeconds = 0.6,
	FollowSmoothing = 0.12,
	-- How long after the last ball stops before the camera returns to the aim view.
	ReturnDelaySeconds = 0.8,
}

---------------------------------------------------------------------------------------------
-- Avatar (the shooter's R15 character at the table)
---------------------------------------------------------------------------------------------
Config.Avatar = {
	-- Transparency of the character while aiming (1 = invisible). The reference wants ~90%.
	AimTransparency = 0.9,
	-- true: only the cue arm and hands stay visible while aiming; the rest is hidden.
	ArmOnlyWhileAiming = true,
	-- Seconds to fade in/out and to blend into/out of the aiming pose.
	FadeSeconds = 0.25,
	PoseBlendSeconds = 0.3,
	-- Where the character stands, measured back from the cue ball along the aim line.
	StandBackInches = 30,
	-- How far the cue tip rests from the cue ball while aiming, and the strike push-in.
	TipGapInches = 3,
	StrikeTravelInches = 6,
	StrikeSeconds = 0.12,
}

---------------------------------------------------------------------------------------------
-- Input (mouse and touch share the same code path)
---------------------------------------------------------------------------------------------
Config.Input = {
	-- Aim rotation per pixel of horizontal drag. (tune)
	AimDegreesPerPixel = 0.22,
	-- Drags slower than this many px/s rotate at a reduced rate for fine aiming.
	FineDragSpeedPx = 60,
	FineAimScale = 0.35,
	-- Aim nudge buttons step size.
	NudgeDegrees = 0.15,
	-- Power bar: pixels of pull for full power, and release deadzone. (tune)
	PowerBarPullPx = 260,
	MinPowerToShoot = 0.04,
	-- An aim tick sound plays every this many degrees of rotation.
	TickEveryDegrees = 2,
}

---------------------------------------------------------------------------------------------
-- Guideline
---------------------------------------------------------------------------------------------
Config.Guideline = {
	-- Length of the short stubs drawn after first contact (object ball and cue ball).
	StubLengthInches = 14,
	Thickness = 0.03, -- studs
	Color = { 255, 255, 255 },
	Transparency = 0.25,
	GhostBallTransparency = 0.6,
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
	PowerBarWidthPx = 44,
	PowerBarHeightPx = 300,
}

---------------------------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------------------------
Config.Debug = {
	-- Test keys in play mode (F = fire cue ball, B = break). Turned off once aiming exists.
	TestKeysEnabled = true,
	-- Print physics events to the console.
	LogEvents = false,
	-- Print a timing line when a shot finishes playing back.
	LogPlayback = true,
	-- Largest slice of shot time played per rendered frame. Keeps a hitch from skipping play.
	MaxPlaybackStepSeconds = 0.1,
}

return Config
