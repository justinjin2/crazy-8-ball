--!strict
-- ShooterPoser: one shooter's body at a table, for the local player (Avatar) and for each
-- shooter someone watches (WatchedShooters). One poser per character; a respawn gets a new one.
-- A small state machine (PoseMath.transition):
--
--   rest    the body as the game left it: its own Anchored flags, fade and Animate. The root
--           is never touched.
--   aim     every rig part but the root anchored, on this client only, and posed
--           (AvatarPose.pose) whenever the frame changes; the root is written with the pose,
--           and both are eased toward the stance (Config.Avatar.Motion): a new stance, even
--           another side of the ball or a stretch over the rail, is glided to, while the hands
--           stay exactly on the cue. The local player's Animate is off and its tracks stopped; a
--           remote body's Animate and transparency are never touched.
--   stroke  aim, with the cue's gap from the stroke clock (advance) on the frozen frame the
--           driver supplies.
--   idle    the limbs let go again, so the owner's Animate idle plays. After the stroke, where
--           the shot was taken: leaving the stroke writes the root ONCE, to the exact spot the
--           server holds it at (the root's ShotSpot attribute, else the driver's own fallback),
--           because the owner's local CFrame wins once the server lets the root go, and the
--           driver hands idle no frame after that. Before the shot (the local shooter dragging
--           the cue ball in hand, a modal open) the driver hands it the live stance's frame and
--           the root follows that, eased as in aim.
--
-- The server holds the shooter by anchoring the root, and the body is only posed while it does:
-- aim is entered only then, and if the server lets the root go mid-aim the limbs are let go at
-- once (in the same replication step) and posing waits until the root is held again. A rig
-- that is not a whole R15 or R6 body is never posed: the state machine still runs (the cue's
-- stroke plays), but the body is left as it is at rest. Whatever is written is saved first (the
-- first time, and again for the parts a rebuilt rig adds) and put back on rest.
--
-- compose() is the one place that knows how a ShooterStance becomes a Frame: it solves the
-- stance, works out the cue's tip CFrame (the one the cue is drawn with, which is what keeps the
-- hands on it), and fills the Frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AvatarPose = require(Shared:WaitForChild("AvatarPose"))
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local PoseMath = require(Shared:WaitForChild("PoseMath"))
local ShooterStance = require(Shared:WaitForChild("ShooterStance"))

local ShooterPoser = {}
ShooterPoser.__index = ShooterPoser

export type State = "rest" | "aim" | "stroke" | "idle"

-- One frame's worth of what a shooter is doing, for compose().
export type Inputs = {
	placement: Placement.Placement,
	body: ShooterStance.Body, -- AvatarPose.measureBody, or Config.Stance.DefaultBody
	cueX: number, -- cue ball, table inches
	cueY: number,
	angle: number, -- aim angle, radians (the physics convention)
	spinX: number, -- strike offset, ball radii
	spinY: number,
	pitch: number, -- the eased visual pitch in degrees (the caller eases CueClearance.pitch)
	pull: number, -- raw wind-up 0..1 (the stance's pullLimit scales it)
	-- Stroke override: the tip's gap in studs from Poser:advance (negative = past contact);
	-- nil = the rest gap plus the pull.
	gap: number?,
	memory: ShooterStance.Memory?, -- the previous frame's stance.memory (hysteresis)
}

-- Everything a poser has written, as it was before, so rest can put it back. Lists (in the
-- order first seen) with a set each, so a rebuilt rig only adds what is new.
type Saved = {
	parts: { BasePart }, -- every rig part but the root
	anchored: { boolean },
	canCollide: { boolean }, -- written on a remote body only (Watch.NoCollidePosed)
	knownParts: { [BasePart]: boolean },
	visual: { BasePart }, -- the local player's only: LocalTransparencyModifier
	ltm: { number },
	knownVisual: { [BasePart]: boolean },
	decals: { Decal }, -- the local player's only: Transparency
	decalTransparency: { number },
	knownDecals: { [Decal]: boolean },
	animate: BaseScript?, -- the local player's only
	animateEnabled: boolean,
}

export type Poser = typeof(setmetatable(
	{} :: {
		character: Model,
		isLocal: boolean,
		state: State,
		destroyed: boolean,
		root: BasePart?, -- the root the guard watches
		guard: RBXScriptConnection?, -- root.Anchored, while out of rest
		held: boolean, -- the limbs are anchored here (and the local Animate is off)
		heldRig: AvatarPose.Rig?, -- the rig (and version) whose parts were last anchored
		heldVersion: number,
		saved: Saved?,
		savedRig: AvatarPose.Rig?, -- the rig (and version) `saved` was last extended from
		savedVersion: number,
		shownRoot: CFrame?, -- the eased root last written; nil snaps on the next one
		shownPose: ShownPose?, -- ...and the eased pose (nil with it)
		-- The skip-unchanged key: the last posed frame's, and scratch for this frame's.
		key: { number },
		nextKey: { number },
		keyMode: string,
		keyRig: AvatarPose.Rig?,
		keyValid: boolean,
		-- The stroke clock (strike to idle).
		strokeT: number,
		strokeFrom: number,
		strokeSeconds: number,
		movingAt: number?,
		idleSpot: CFrame?,
		-- The last setFade, so an unchanged one writes nothing.
		fade: number,
		fadeHide: boolean,
		fadeRig: AvatarPose.Rig?,
		fadeVersion: number,
	},
	ShooterPoser
))

-- The pose values eased toward each new stance (the rest of the frame is exact).
type ShownPose = {
	torso: number,
	lean: number,
	lift: number,
	hand: Vector3,
	supportY: number,
}

-- The root attribute holding the exact spot (a CFrame) the server holds the shooter at for the
-- shot (TableService.shotAccepted); nil whenever the root is not there.
local SHOT_SPOT = "ShotSpot"

-- The skip-unchanged key sees positions to KEY_STUDS and directions, fractions and degrees to
-- KEY_FINE: nothing finer shows on screen. Slots in the key (see fillKey).
local KEY_STUDS = 1e-3
local KEY_FINE = 1e-4
local KEY_SIZE = 27

-- The eased root lands exactly on its target once this close, so a still stance stops
-- changing the key and costs nothing.
local SETTLE_STUDS = 1e-3
local SETTLE_DOT = 1 - 1e-8

local PROFILES = (Config.Avatar.Profiles :: any) :: { [string]: { LiftFrom: number? } }

local function smoothstep(from: number, to: number, x: number): number
	if to <= from then
		return if x >= to then 1 else 0
	end
	local t = math.clamp((x - from) / (to - from), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Every table's surroundings are the same: worked out once.
local AREA = ShooterStance.area()

-- Scratch reused by every compose(): solve() and frame() read them and keep nothing.
local query: ShooterStance.Input = {
	ballXIn = 0,
	ballYIn = 0,
	angle = 0,
	spinX = 0,
	spinY = 0,
	pitchDegrees = 0,
	pull = 0,
	cueLengthStuds = nil,
	body = Config.Stance.DefaultBody,
	area = AREA,
	memory = nil,
}
local spin: CueStickBuilder.Spin = { x = 0, y = 0 }

-- A root CFrame at a spot in table studs (height above the floor the table stands on), facing
-- `yaw` (the aim convention), upright: exactly how the server places the root.
local function spotAt(p: Placement.Placement, x: number, y: number, z: number, yaw: number): CFrame
	local at = Vector3.new(Placement.fromTableStuds(p, x, y, z))
	local dx, _, dz = Placement.aimVector(p, yaw)
	return CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
end

--- Solve the stance for `inputs` and fill `frame` with the pose it asks for. Returns the
--- stance (thread stance.memory into the next frame's inputs) and the cue's tip CFrame (draw
--- the cue with CueStickBuilder.placeAt(cue, tip)).
function ShooterPoser.compose(
	inputs: Inputs,
	frame: AvatarPose.Frame
): (ShooterStance.Stance, CFrame)
	debug.profilebegin("ShooterPoser.compose")
	local C = Config.Cue
	local p = inputs.placement
	local area = AREA

	query.ballXIn, query.ballYIn = inputs.cueX, inputs.cueY
	query.angle, query.spinX, query.spinY = inputs.angle, inputs.spinX, inputs.spinY
	query.pitchDegrees, query.pull = inputs.pitch, inputs.pull
	query.body, query.area, query.memory = inputs.body, area, inputs.memory
	local stance = ShooterStance.solve(query)
	query.memory = nil

	-- The cue, from the rendered cue ball's centre (where the stance's strike point is too).
	local gap = inputs.gap or stance.cueGapStuds
	local ball =
		Vector3.new(Placement.toWorld(p, inputs.cueX, inputs.cueY, Config.Balls.RenderRadiusInches))
	local dx, dy, dz = Placement.aimVector(p, inputs.angle)
	spin.x, spin.y = inputs.spinX, inputs.spinY
	local tip = CueStickBuilder.frame(ball, Vector3.new(dx, dy, dz), gap, spin, stance.pitchDegrees)

	-- The body.
	frame.root = spotAt(p, stance.rootX, stance.rootY, stance.rootZ, stance.yaw)
	frame.floorY = p.y
	frame.mode = stance.mode
	frame.supportY = p.y + stance.supportZ
	frame.lean = stance.lean
	frame.torsoDegrees = stance.torsoDegrees
	-- The body sways with the cue as drawn: the wind-up the stance allowed, and through the
	-- stroke the gap closing (a follow-through sways it no further forward than upright).
	frame.pull = math.clamp(
		(gap - C.CueRestGapInches * Config.Table.StudsPerInch) / C.CuePullBackStuds,
		0,
		1
	)
	frame.tip = tip
	frame.gripAlong = stance.gripFromTipStuds
	frame.cueLength = C.CueLengthStuds
	frame.look = ball
	local profile = PROFILES[stance.mode]
	local liftFrom = profile and profile.LiftFrom
	frame.backLegLift = if liftFrom then smoothstep(liftFrom, 1, stance.lean) else 0

	-- The off hand: always a bridge under the cue, on the cloth or the rail top (or raised
	-- under a steep cue). AvatarPose puts the palm just above this spot.
	local bridge = stance.handBridge
	frame.offKind = 1
	frame.offHand = Vector3.new(
		Placement.fromTableStuds(
			p,
			bridge.x,
			bridge.y,
			bridge.handZ - Config.Stance.BridgeHandHeightStuds
		)
	)
	debug.profileend()
	return stance, tip
end

--- The spot the shooter idles at after the shot, facing the table centre (ShooterStance.idle),
--- as a root CFrame: the same spot and turn the server puts the root at. Poser:strike takes it
--- as the fallback for when the root carries no ShotSpot.
function ShooterPoser.idleSpot(p: Placement.Placement, stance: ShooterStance.Stance): CFrame
	local x, y, z, yaw = ShooterStance.idle(stance)
	return spotAt(p, x, y, z, yaw)
end

--- A poser for `character`. `isLocal`: the local player's own character, the only one whose
--- Animate and transparency the poser may ever touch.
function ShooterPoser.new(character: Model, isLocal: boolean): Poser
	return setmetatable({
		character = character,
		isLocal = isLocal,
		state = "rest" :: State,
		destroyed = false,
		root = nil :: BasePart?,
		guard = nil :: RBXScriptConnection?,
		held = false,
		heldRig = nil :: AvatarPose.Rig?,
		heldVersion = 0,
		saved = nil :: Saved?,
		savedRig = nil :: AvatarPose.Rig?,
		savedVersion = 0,
		shownRoot = nil :: CFrame?,
		shownPose = nil :: ShownPose?,
		key = table.create(KEY_SIZE, 0),
		nextKey = table.create(KEY_SIZE, 0),
		keyMode = "",
		keyRig = nil :: AvatarPose.Rig?,
		keyValid = false,
		strokeT = 0,
		strokeFrom = 0,
		strokeSeconds = Config.Avatar.Stroke.Seconds,
		movingAt = nil :: number?,
		idleSpot = nil :: CFrame?,
		fade = -1,
		fadeHide = false,
		fadeRig = nil :: AvatarPose.Rig?,
		fadeVersion = 0,
	}, ShooterPoser)
end

local function newSaved(): Saved
	return {
		parts = {},
		anchored = {},
		canCollide = {},
		knownParts = {},
		visual = {},
		ltm = {},
		knownVisual = {},
		decals = {},
		decalTransparency = {},
		knownDecals = {},
		animate = nil,
		animateEnabled = true,
	}
end

-- Save what the poser may write on `rig`'s parts before it first writes it: on first use, and
-- again for whatever a rebuilt rig added (a hat put on mid-aim).
local function save(self: Poser, rig: AvatarPose.Rig)
	local existing = self.saved
	if existing and self.savedRig == rig and self.savedVersion == rig.version then
		return
	end
	local saved: Saved = existing or newSaved()
	self.saved = saved
	self.savedRig, self.savedVersion = rig, rig.version
	local parts = rig.parts
	for i = 2, #parts do -- [1] is the root: the server's, never written here
		local part = parts[i]
		if not saved.knownParts[part] then
			saved.knownParts[part] = true
			table.insert(saved.parts, part)
			table.insert(saved.anchored, part.Anchored)
			table.insert(saved.canCollide, part.CanCollide)
		end
	end
	if not self.isLocal then
		return
	end
	for _, part in rig.visual do
		if not saved.knownVisual[part] then
			saved.knownVisual[part] = true
			table.insert(saved.visual, part)
			table.insert(saved.ltm, part.LocalTransparencyModifier)
		end
	end
	for _, decal in rig.decals do
		if not saved.knownDecals[decal] then
			saved.knownDecals[decal] = true
			table.insert(saved.decals, decal)
			table.insert(saved.decalTransparency, decal.Transparency)
		end
	end
	if saved.animate == nil then
		local animate = self.character:FindFirstChild("Animate")
		if animate and animate:IsA("BaseScript") then
			saved.animate = animate
			saved.animateEnabled = animate.Enabled
		end
	end
end

-- Someone else's posed body stops colliding here (Config.Avatar.Watch.NoCollidePosed), so a body
-- posed over the rail can never shove the local player's own character.
local function noCollide(self: Poser): boolean
	return not self.isLocal and Config.Avatar.Watch.NoCollidePosed
end

-- Anchor every rig part but the root, here only (only what is not anchored yet is written).
local function anchor(self: Poser, rig: AvatarPose.Rig)
	local parts = rig.parts
	local ghost = noCollide(self)
	for i = 2, #parts do
		local part = parts[i]
		if not part.Anchored then
			part.Anchored = true
		end
		if ghost and part.CanCollide then
			part.CanCollide = false
		end
	end
end

-- Take the body for posing: limbs anchored; the local player's Animate off and its tracks
-- stopped, so nothing plays under the pose.
local function hold(self: Poser, rig: AvatarPose.Rig)
	save(self, rig)
	anchor(self, rig)
	self.heldRig, self.heldVersion = rig, rig.version
	if self.isLocal then
		local saved = self.saved
		local animate = saved and saved.animate
		if animate and animate.Parent and animate.Enabled then
			animate.Enabled = false
		end
		local animator = rig.humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0)
			end
		end
	end
	self.held = true
	self.shownRoot = nil -- the first posed frame snaps to the stance
	self.keyValid = false
end

-- Give the limbs back to their joints (their own Anchored again) and the local player's
-- Animate back, so the owner's animations play.
local function unhold(self: Poser)
	self.held = false
	local saved = self.saved
	if saved == nil then
		return
	end
	local anchored, canCollide = saved.anchored, saved.canCollide
	local ghost = noCollide(self)
	for i, part in saved.parts do
		if part.Parent then
			if part.Anchored ~= anchored[i] then
				part.Anchored = anchored[i]
			end
			if ghost and part.CanCollide ~= canCollide[i] then
				part.CanCollide = canCollide[i]
			end
		end
	end
	local animate = saved.animate
	if self.isLocal and animate and animate.Parent and animate.Enabled ~= saved.animateEnabled then
		animate.Enabled = saved.animateEnabled
	end
end

-- Watch `root`'s Anchored while the poser is out of rest: the moment the server lets the root
-- go, the limbs go too, in the same replication step, so no client is left holding a body
-- frozen in the air. Posing picks up again once the root is held again (pose()).
local function watch(self: Poser, root: BasePart?)
	local want = root ~= nil and self.state ~= "rest"
	if self.root == root and (self.guard ~= nil) == want then
		return
	end
	local guard = self.guard
	if guard then
		guard:Disconnect()
		self.guard = nil
	end
	self.root = root
	if want and root then
		self.guard = root:GetPropertyChangedSignal("Anchored"):Connect(function()
			if self.held and not root.Anchored then
				unhold(self)
			end
		end)
	end
end

-- The character's rig (nil: not a humanoid body, or gone) and its root, now.
local function current(self: Poser): (AvatarPose.Rig?, BasePart?)
	local rig = AvatarPose.rig(self.character)
	if rig then
		return rig, rig.root
	end
	local found = self.character:FindFirstChild("HumanoidRootPart")
	return nil, if found and found:IsA("BasePart") then found else nil
end

local function clearStroke(self: Poser)
	self.strokeT, self.strokeFrom = 0, 0
	self.movingAt, self.idleSpot = nil, nil
end

-- Back to rest: everything written put back, the guard dropped. The root is left where it is.
local function toRest(self: Poser, root: BasePart?)
	if self.held then
		unhold(self)
	end
	local saved = self.saved
	if saved and self.isLocal then
		local ltm = saved.ltm
		for i, part in saved.visual do
			if part.Parent then
				part.LocalTransparencyModifier = ltm[i]
			end
		end
		local transparency = saved.decalTransparency
		for i, decal in saved.decals do
			if decal.Parent then
				decal.Transparency = transparency[i]
			end
		end
	end
	self.saved, self.savedRig, self.savedVersion = nil, nil, 0
	self.heldRig, self.heldVersion = nil, 0
	self.fade, self.fadeRig = -1, nil
	self.state = "rest"
	self.shownRoot = nil
	self.keyValid = false
	clearStroke(self)
	watch(self, root)
end

-- Into idle. Leaving the stroke, the root goes ONCE to the spot the server holds it at (the
-- ShotSpot attribute, else the fallback from strike()), and only while the server holds it:
-- the owner's local CFrame is what counts when the root is let go, and a watcher's local one
-- was the aim stance's. Never an unanchored root, and never one this poser was not posing.
-- Idling from aim instead (no stroke) keeps the eased root, which a followed stance goes on
-- easing from.
local function toIdle(self: Poser, root: BasePart?, fromStroke: boolean)
	if fromStroke then
		if self.held and root and root.Anchored then
			local spot = root:GetAttribute(SHOT_SPOT)
			local cf: CFrame? = if typeof(spot) == "CFrame" then spot else self.idleSpot
			if cf then
				root.CFrame = cf
			end
		end
		self.shownRoot = nil -- the root is at the shot spot now, not where it was eased to
	end
	if self.held then
		unhold(self)
	end
	self.state = "idle"
	clearStroke(self)
end

local function quantise(v: number, step: number): number
	return math.floor(v / step + 0.5)
end

-- Everything the pose depends on, quantised, into `key` (KEY_SIZE slots).
local function fillKey(key: { number }, f: AvatarPose.Frame, root: CFrame, version: number)
	local at, look = root.Position, root.LookVector
	local tip = f.tip
	local tipAt, axis = tip.Position, tip.ZVector
	local hand, target = f.offHand, f.look
	key[1] = quantise(at.X, KEY_STUDS)
	key[2] = quantise(at.Y, KEY_STUDS)
	key[3] = quantise(at.Z, KEY_STUDS)
	key[4] = quantise(look.X, KEY_FINE)
	key[5] = quantise(look.Z, KEY_FINE)
	key[6] = quantise(tipAt.X, KEY_STUDS)
	key[7] = quantise(tipAt.Y, KEY_STUDS)
	key[8] = quantise(tipAt.Z, KEY_STUDS)
	key[9] = quantise(axis.X, KEY_FINE)
	key[10] = quantise(axis.Y, KEY_FINE)
	key[11] = quantise(axis.Z, KEY_FINE)
	key[12] = quantise(f.gripAlong, KEY_STUDS)
	key[13] = quantise(f.cueLength, KEY_STUDS)
	key[14] = f.offKind
	key[15] = quantise(hand.X, KEY_STUDS)
	key[16] = quantise(hand.Y, KEY_STUDS)
	key[17] = quantise(hand.Z, KEY_STUDS)
	key[18] = quantise(f.lean, KEY_FINE)
	key[19] = if f.torsoDegrees then quantise(f.torsoDegrees, KEY_FINE) else math.huge
	key[20] = quantise(f.pull, KEY_FINE)
	key[21] = quantise(target.X, KEY_STUDS)
	key[22] = quantise(target.Y, KEY_STUDS)
	key[23] = quantise(target.Z, KEY_STUDS)
	key[24] = quantise(f.backLegLift, KEY_FINE)
	key[25] = quantise(f.floorY, KEY_STUDS)
	key[26] = quantise(f.supportY, KEY_STUDS)
	key[27] = version
end

-- The root to show this frame on the way to `target` (Config.Avatar.Motion): eased from the
-- last one shown, straight there when that is far or there is none, and exactly there once
-- close. The hands are never eased: they are on the cue.
local function ease(self: Poser, target: CFrame, dt: number): (CFrame, boolean)
	local M = Config.Avatar.Motion
	local last = self.shownRoot
	local shown: CFrame = target
	local snapped = true
	if last and (target.Position - last.Position).Magnitude <= M.SnapStuds then
		snapped = false
		shown = last:Lerp(target, PoseMath.alpha(dt, M.RootSmoothingSeconds))
		if
			(shown.Position - target.Position).Magnitude < SETTLE_STUDS
			and shown.LookVector:Dot(target.LookVector) > SETTLE_DOT
		then
			shown = target
		end
	end
	self.shownRoot = shown
	return shown, snapped
end

-- One eased value: toward `want` by `k`, exactly there once within `settle`.
local function toward(have: number, want: number, k: number, settle: number): number
	local v = have + (want - have) * k
	return if math.abs(v - want) < settle then want else v
end

local function towardV(have: Vector3, want: Vector3, k: number): Vector3
	local v = have:Lerp(want, k)
	return if (v - want).Magnitude < SETTLE_STUDS then want else v
end

-- The pose to show this frame on the way to `f`'s (Config.Avatar.Motion.PoseSmoothingSeconds):
-- the lean, torso, back leg, the bridge hand's target and the kneeling cloth's height glide,
-- so a new stance flows in rather than snapping, and snap with the root. Written into `f`,
-- which is returned to the caller's values by restorePose.
type Wanted = {
	torso: number,
	lean: number,
	lift: number,
	hand: Vector3,
	supportY: number,
}
local wanted: Wanted = { torso = 0, lean = 0, lift = 0, hand = Vector3.zero, supportY = 0 }
local function easePose(self: Poser, f: AvatarPose.Frame, dt: number, snapped: boolean)
	wanted.torso, wanted.lean, wanted.lift = f.torsoDegrees or 0, f.lean, f.backLegLift
	wanted.hand, wanted.supportY = f.offHand, f.supportY
	local was = self.shownPose
	local P: ShownPose
	if was == nil or snapped then
		P = {
			torso = wanted.torso,
			lean = wanted.lean,
			lift = wanted.lift,
			hand = wanted.hand,
			supportY = wanted.supportY,
		}
		self.shownPose = P
	else
		P = was
		local k = PoseMath.alpha(dt, Config.Avatar.Motion.PoseSmoothingSeconds)
		P.torso = toward(P.torso, wanted.torso, k, KEY_FINE)
		P.lean = toward(P.lean, wanted.lean, k, KEY_FINE)
		P.lift = toward(P.lift, wanted.lift, k, KEY_FINE)
		P.hand = towardV(P.hand, wanted.hand, k)
		P.supportY = toward(P.supportY, wanted.supportY, k, SETTLE_STUDS)
	end
	if f.torsoDegrees then
		f.torsoDegrees = P.torso
	end
	f.lean, f.backLegLift = P.lean, P.lift
	f.offHand, f.supportY = P.hand, P.supportY
end

local function restorePose(f: AvatarPose.Frame)
	if f.torsoDegrees then
		f.torsoDegrees = wanted.torso
	end
	f.lean, f.backLegLift = wanted.lean, wanted.lift
	f.offHand, f.supportY = wanted.hand, wanted.supportY
end

-- Idle before the shot: the limbs are the joints' (and the owner's Animate's), and only the
-- root moves, eased toward the frame's. Written only when it is not there already (the
-- server's own placement replicating moves it too).
local function follow(self: Poser, root: BasePart, f: AvatarPose.Frame, dt: number)
	local shown = ease(self, f.root, dt)
	self.shownPose = nil -- the limbs are the joints' now: the next pose starts afresh
	if
		(root.Position - shown.Position).Magnitude > KEY_STUDS
		or root.CFrame.LookVector:Dot(shown.LookVector) < SETTLE_DOT
	then
		root.CFrame = shown
	end
end

-- One posed frame: ease the root toward the frame's, and pose unless nothing has changed
-- since the last one (anchored parts stay where they were put). The frame's root is the
-- caller's and is left as it was.
local function posed(
	self: Poser,
	rig: AvatarPose.Rig,
	root: BasePart,
	f: AvatarPose.Frame,
	dt: number
)
	if self.heldRig ~= rig or self.heldVersion ~= rig.version then
		-- Rebuilt (a hat put on mid-aim): save and anchor what it added.
		save(self, rig)
		anchor(self, rig)
		self.heldRig, self.heldVersion = rig, rig.version
		self.keyValid = false
	end
	local target = f.root
	local shown, snapped = ease(self, target, dt)
	easePose(self, f, dt, snapped)

	local key, nextKey = self.key, self.nextKey
	fillKey(nextKey, f, shown, rig.version)
	-- Something else moved the root (the server's own placement replicating): pose again.
	local same = self.keyValid
		and self.keyRig == rig
		and self.keyMode == f.mode
		and (root.Position - shown.Position).Magnitude <= KEY_STUDS
	if same then
		for i = 1, KEY_SIZE do
			if key[i] ~= nextKey[i] then
				same = false
				break
			end
		end
	end
	if same then
		restorePose(f)
		return
	end
	self.key, self.nextKey = nextKey, key
	self.keyValid, self.keyRig, self.keyMode = true, rig, f.mode
	f.root = shown
	AvatarPose.pose(rig, f)
	f.root = target
	restorePose(f)
end

--- Move toward `want` and pose. Call every frame. "aim" needs `frame` (from compose()) and is
--- only entered while the server holds the root (it is anchored); while stroking the stroke
--- plays on (the frame should carry advance()'s gap) until it is done, whatever is wanted,
--- unless it is "rest". "idle" from aim lets the limbs go; from rest it stays at rest. A frame
--- handed to idle moves the root toward the frame's, eased, while the server holds it: only
--- ever before the shot (after the stroke the root stays at the shot spot).
function ShooterPoser.pose(
	self: Poser,
	want: "rest" | "aim" | "idle",
	frame: AvatarPose.Frame?,
	dt: number
)
	if self.destroyed then
		return
	end
	debug.profilebegin("ShooterPoser")
	local rig, root = current(self)
	if want == "rest" then
		if self.state ~= "rest" or self.saved ~= nil or self.guard ~= nil then
			toRest(self, root)
		end
	else
		local state: State = self.state
		local nextState: State = PoseMath.transition(state, want, false)
		if nextState == "aim" and state ~= "aim" and not (root and root.Anchored) then
			nextState = state -- the server is not holding the body (yet)
		end
		if nextState == "idle" and state ~= "idle" then
			toIdle(self, root, false)
		else
			self.state = nextState
		end
		watch(self, root)
		if self.state == "aim" or self.state == "stroke" then
			local ready = frame ~= nil
				and rig ~= nil
				and rig.valid
				and root ~= nil
				and root.Anchored
			if ready and not self.held and rig then
				hold(self, rig)
			elseif not ready and self.held then
				unhold(self)
			end
			if self.held and frame and rig and root then
				posed(self, rig, root, frame, dt)
			end
		elseif self.state == "idle" and frame and rig and rig.valid and root and root.Anchored then
			follow(self, root, frame, dt)
		end
	end
	debug.profileend()
end

--- The stroke clock: the cue's gap in studs (0 at contact, negative past it) while stroking,
--- nil otherwise. The frame the stroke finishes on, the poser goes to idle and returns nil.
function ShooterPoser.advance(self: Poser, dt: number): number?
	if self.destroyed or self.state ~= "stroke" then
		return nil
	end
	self.strokeT += math.max(dt, 0)
	local S = Config.Avatar.Stroke
	local gap, done = PoseMath.strokeGap(
		self.strokeT,
		self.strokeFrom,
		self.strokeSeconds,
		self.movingAt,
		S.FollowThroughStuds,
		S.FollowSeconds,
		S.HoldSeconds,
		S.MaxWaitSeconds
	)
	if done then
		local _, root = current(self)
		toIdle(self, root, true)
		return nil
	end
	return gap
end

--- Start the stroke (from aim only): the tip goes from `fromGap` (studs) into the ball over
--- `strokeSeconds`, rests there until ballMoving() (already moving: `ballMoving`), follows
--- through and holds. `idleSpot` (ShooterPoser.idleSpot of the frozen stance) is where the root
--- goes on idling when the server left no ShotSpot.
function ShooterPoser.strike(
	self: Poser,
	fromGap: number,
	ballMoving: boolean,
	strokeSeconds: number,
	idleSpot: CFrame?
)
	if self.destroyed or self.state == "stroke" then
		return
	end
	if PoseMath.transition(self.state, "strike", false) ~= "stroke" then
		return
	end
	self.state = "stroke"
	self.strokeT = 0
	self.strokeFrom = if fromGap == fromGap then fromGap else 0 -- never NaN
	self.strokeSeconds = math.max(strokeSeconds, 1e-3)
	self.movingAt = if ballMoving then 0 else nil
	self.idleSpot = idleSpot
end

--- The replay has the ball moving: the stroke may follow through.
function ShooterPoser.ballMoving(self: Poser)
	if self.state == "stroke" and self.movingAt == nil then
		self.movingAt = self.strokeT
	end
end

--- The shot was turned down: back to aim, the cue at rest again.
function ShooterPoser.cancelStroke(self: Poser)
	if self.destroyed then
		return
	end
	local nextState: State = PoseMath.transition(self.state, "cancel", false)
	if nextState ~= self.state then
		self.state = nextState
		clearStroke(self)
	end
end

function ShooterPoser.stroking(self: Poser): boolean
	return self.state == "stroke"
end

--- Fade the local player's own character (every part but the root to `transparency`, and
--- accessories gone with `hideAccessories`). The first fade saves what it overwrites, which rest
--- puts back. Writes only when something changed. Never for anyone else's body.
function ShooterPoser.setFade(self: Poser, transparency: number, hideAccessories: boolean)
	assert(self.isLocal, "ShooterPoser.setFade is for the local player's own character only")
	if self.destroyed then
		return
	end
	local rig = AvatarPose.rig(self.character)
	if rig == nil then
		return
	end
	if
		transparency == self.fade
		and hideAccessories == self.fadeHide
		and rig == self.fadeRig
		and rig.version == self.fadeVersion
	then
		return
	end
	save(self, rig)
	AvatarPose.setFade(rig, transparency, hideAccessories)
	self.fade, self.fadeHide = transparency, hideAccessories
	self.fadeRig, self.fadeVersion = rig, rig.version
end

--- Back to rest (everything put back) and the guard dropped. The poser does nothing after.
function ShooterPoser.destroy(self: Poser)
	if self.destroyed then
		return
	end
	local _, root = current(self)
	toRest(self, root)
	self.destroyed = true
end

return ShooterPoser
