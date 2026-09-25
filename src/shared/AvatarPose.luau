--!strict
-- AvatarPose: poses a character (R15 or R6) as the shooter, entirely in code (no animation
-- assets), and measures the body ShooterStance plans around. Shared and free of client-only
-- services: the server measures the body it places (measureBody, standHeight), the client
-- poses the shooters it draws, and the Studio preview can pose a test rig with exactly the
-- game's code.
--
-- The rig (AvatarPose.rig) is built once per character and cached. One walk over the
-- descendants finds every joint (Motor6D and the other JointInstances, AnimationConstraint,
-- RigidConstraint, WeldConstraint), and a breadth-first walk from the root orders the parts
-- parents first. Rigid welds are in that tree too, so hats, hair and tools are placed
-- explicitly rather than trusted to follow. The rest pose, the limb lengths and the body's
-- measurements all come from the joints' C0/C1 and the parts' sizes, so scaled and Rthro
-- bodies work unchanged. Events mark the rig dirty (a part, joint, attachment or accessory
-- added or removed, the rig type or hip height changed) and it rebuilds in place on next use;
-- a character destroyed or taken out of the game is forgotten.
--
-- A pose (AvatarPose.pose) is forward kinematics through anchored parts: every part's CFrame
-- is worked out from the root and all of them, the root included, are written with one
-- workspace:BulkMoveTo. The joints are never driven, so it works for Motor6D and
-- AnimationConstraint rigs alike, lands in the same frame as the cue (placed in the same
-- RenderStepped), and nothing (a remote Animator, physics) can fight it. The caller anchors
-- the limbs first; pose() only computes and moves.
--
-- The pose follows ShooterStance, which decided what reaches on the assumption that the
-- torso leans about the waist, straight along the facing, by the stance's torso angle: the
-- chest does exactly that, and the hips, twist and roll (Config.Avatar.Profiles) shape the
-- body around it. R15 arms and legs reach their targets by two-bone IK (PoseMath.twoBone);
-- R6 limbs are rigid, so they aim, and a hand slides along the cue (PoseMath.lineSphere) to
-- where the arm meets it. A hand that cannot quite reach slides along the cue rather than
-- leaving it. The legs follow the stance's support: standing, the hips drop just enough for
-- both feet to stay on the floor (stretching over the rail too); kneeling on the table or the
-- rail top, the knees rest on it with the shins lying back.

local Players = game:GetService("Players")

local Config = require(script.Parent.Config)
local PoseMath = require(script.Parent.PoseMath)
local ShooterStance = require(script.Parent.ShooterStance)

local AvatarPose = {}

export type Kind = "R15" | "R6"

-- One bone of a limb, from the rest rig. R15 elbows and knees are hinges about the parts'
-- shared local X; a bone whose two pivots are apart along X (an R15 shoulder pivot sits at the
-- arm's inner edge) keeps that part as `offset` and bends only the rest (`length`, square to
-- X). An R6 limb is one rigid bone from its pivot to its end point.
type Bone = {
	length: number, -- studs, square to the hinge (R6: the whole length)
	offset: number, -- studs along the hinge (local +X); 0 on R6
	inv: CFrame, -- the bone's local basis, inverted (see `aligned`)
}

type Limb = {
	upper: number, -- part index: upper arm or thigh (R6: the whole arm or leg)
	lower: number, -- forearm or shin (0 on R6)
	finish: number, -- hand or foot (0 on R6)
	upperBone: Bone, -- shoulder or hip pivot to the elbow or knee pivot (R6: pivot to `point`)
	wristBone: Bone, -- elbow or knee pivot to the wrist or ankle pivot (R15)
	gripBone: Bone, -- arms: elbow pivot to the grip point, the hand held at `hold` (R15)
	hold: CFrame, -- arms: the hand's rotation relative to the forearm while it holds something
	point: Vector3, -- the end point in the end part's space: grip attachment (arms), sole (legs)
	palm: Vector3, -- arms: the palm, from the wrist pivot, in the hand's space
	ankle: number, -- R15 legs: the ankle pivot's height above the sole, standing
	sign: number, -- 1 an elbow (bends toward local -Z), -1 a knee (toward +Z)
}

export type Rig = {
	character: Model,
	humanoid: Humanoid,
	root: BasePart,
	kind: Kind,
	-- Every body part was found where it should be, so the limbs can be posed. An invalid rig
	-- (a custom body) is still moved, rigidly in its rest pose, and has no measurements.
	valid: boolean,
	alive: boolean, -- false once forgotten: pose() and setFade() then do nothing
	dirty: boolean, -- something changed; rebuilt (in place) on next use
	version: number, -- bumped by every rebuild, so a caller can re-save part state
	parts: { BasePart }, -- [1] = the root, then parents before children
	cframes: { CFrame }, -- pose()'s scratch, one per part
	parent: { number }, -- index of each part's parent (0 for the root)
	rest: { CFrame }, -- part = parent * rest[i] in the rest pose
	restCF: { CFrame }, -- each part's rest CFrame relative to the root
	restRot: { CFrame }, -- ...its rotation only
	p0: { Vector3 }, -- each part's joint pivot, in its parent's space
	p1: { Vector3 }, -- ...and in its own space
	role: { [string]: number }, -- role name (R15_ROLES / R6_ROLES) to part index
	generic: { number }, -- parts placed by plain FK (accessories, tools), parents first
	pelvis: number, -- LowerTorso (R15); 0 on R6
	chest: number, -- UpperTorso (R15), Torso (R6)
	head: number,
	armR: Limb,
	armL: Limb,
	legR: Limb,
	legL: Limb,
	pivot: Vector3, -- where the torso leans, in the chest's space: waist (R15), hip line (R6)
	waist: Vector3, -- ...and relative to the root, standing
	chestRestInv: CFrame, -- restRot[chest]:Inverse(): the chest's axes without its rest turn
	stand: number, -- the root's centre above the floor, standing
	body: ShooterStance.Body?, -- nil unless valid; shared, never modify it
	visual: { BasePart }, -- every part but the root, for the local fade
	visualInAccessory: { boolean },
	decals: { Decal },
	conns: { RBXScriptConnection },
}

-- One pose, in world space. The caller keeps one per posed character (newFrame) and fills it
-- every frame; nothing here allocates a frame.
export type Frame = {
	-- In.
	-- The root: the stance's spot at y = floorY + rootZ, facing the stance's yaw (flat).
	-- pose() writes it along with every other part.
	root: CFrame,
	floorY: number, -- world height of the floor the shooter stands on
	mode: ShooterStance.Mode, -- picks Config.Avatar.Profiles[mode] and what the legs do
	-- "table", "rail": world height of the cloth or the rail top the knees rest on.
	supportY: number,
	lean: number, -- 0..1, the stance's lean through its mode's range
	torsoDegrees: number?, -- the stance's torso lean from vertical; nil: the profile's own
	pull: number, -- 0..1 wind-up: the body sways back with it
	-- The cue's frame: pivot at the tip, +Z toward the butt. The same CFrame the cue is drawn
	-- with (CueStickBuilder.frame), which is what keeps the hands on the cue.
	tip: CFrame,
	gripAlong: number, -- studs from the tip to the grip hand along +Z
	cueLength: number, -- studs from the tip to the butt end
	offKind: number, -- the off (left) hand: 0 relaxed, 1 hand bridge
	-- 1: the bridge's spot on the cloth or rail top under the cue (fingers follow the cue),
	-- or raised under a steep cue.
	offHand: Vector3,
	look: Vector3, -- what the head looks at: the cue ball's centre
	backLegLift: number, -- 0..1: the back (right) foot lifts off the floor, toe down
	-- Out: where the hands ended up, for the Studio report.
	grip: Vector3, -- where on the cue the grip hand was sent (after any slide)
	gripMiss: number, -- studs from the grip hand's grip point to there
	offMiss: number, -- studs from the off hand's palm to its bridge target
}

-- Config.Avatar.Profiles rows (the keys are the stance modes).
type Profile = {
	PelvisPitch: { number },
	ChestPitch: { number },
	HipTwistDegrees: number,
	ChestCounterDegrees: number,
	ChestRollDegrees: number,
	HipBackStuds: number,
	CrouchStuds: number,
	LiftFrom: number?,
}

local PROFILES = (Config.Avatar.Profiles :: any) :: { [string]: Profile }

local UP = Vector3.yAxis
local ZERO = Vector3.zero

-- { role, part name, parent role } ("" is the root); parents come first. A part takes a role
-- only when the joint tree gives it that parent, so a stray part with a body part's name is
-- never mistaken for one.
local R15_ROLES: { { string } } = {
	{ "Pelvis", "LowerTorso", "" },
	{ "Chest", "UpperTorso", "Pelvis" },
	{ "Head", "Head", "Chest" },
	{ "UpperArmR", "RightUpperArm", "Chest" },
	{ "LowerArmR", "RightLowerArm", "UpperArmR" },
	{ "HandR", "RightHand", "LowerArmR" },
	{ "UpperArmL", "LeftUpperArm", "Chest" },
	{ "LowerArmL", "LeftLowerArm", "UpperArmL" },
	{ "HandL", "LeftHand", "LowerArmL" },
	{ "UpperLegR", "RightUpperLeg", "Pelvis" },
	{ "LowerLegR", "RightLowerLeg", "UpperLegR" },
	{ "FootR", "RightFoot", "LowerLegR" },
	{ "UpperLegL", "LeftUpperLeg", "Pelvis" },
	{ "LowerLegL", "LeftLowerLeg", "UpperLegL" },
	{ "FootL", "LeftFoot", "LowerLegL" },
}
local R6_ROLES: { { string } } = {
	{ "Torso", "Torso", "" },
	{ "Head", "Head", "Torso" },
	{ "ArmR", "Right Arm", "Torso" },
	{ "ArmL", "Left Arm", "Torso" },
	{ "LegR", "Right Leg", "Torso" },
	{ "LegL", "Left Leg", "Torso" },
}

local NO_BONE: Bone = { length = 0, offset = 0, inv = CFrame.identity }
local NO_LIMB: Limb = {
	upper = 0,
	lower = 0,
	finish = 0,
	upperBone = NO_BONE,
	wristBone = NO_BONE,
	gripBone = NO_BONE,
	hold = CFrame.identity,
	point = ZERO,
	palm = ZERO,
	ankle = 0,
	sign = 1,
}

-- Weak keys as a backstop only: forget() (on Destroying, or the character leaving the game)
-- is what drops a rig and its connections.
local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function lerp(pair: { number }, t: number): number
	return pair[1] + (pair[2] - pair[1]) * t
end

local function vec(v: { number }): Vector3
	return Vector3.new(v[1], v[2], v[3])
end

-- A rotation whose Y axis runs along `axis` and whose X axis points as near `ref` as it can
-- (made square to the axis).
local function basis(axis: Vector3, ref: Vector3): CFrame
	local y = if axis.Magnitude > 1e-9 then axis.Unit else UP
	local x = ref - y * ref:Dot(y)
	if x.Magnitude < 1e-5 then
		x = y:Cross(if math.abs(y.Z) < 0.9 then Vector3.zAxis else Vector3.xAxis)
	end
	x = x.Unit
	return CFrame.fromMatrix(ZERO, x, y, x:Cross(y))
end

-- The rotation that takes a bone's local axis onto `axis` and its local reference onto `ref`;
-- `inv` is basis(localAxis, localRef):Inverse(), worked out once when the rig is built.
local function aligned(axis: Vector3, ref: Vector3, inv: CFrame): CFrame
	return basis(axis, ref) * inv
end

-- A part's CFrame from where its joint pivot goes in the world, its rotation (no position),
-- and where that pivot is in the part's own space.
local function place(pivot: Vector3, rot: CFrame, pivotLocal: Vector3): CFrame
	return rot + (pivot - rot * pivotLocal)
end

-- The farthest from its pivot a two-bone limb puts its end exactly on target: in the bending
-- plane, a hair inside where PoseMath.twoBone's soft limit starts easing in.
local function reachOf(upperBone: Bone, lowerBone: Bone, soft: number): number
	local bend = (upperBone.length + lowerBone.length) * soft * (1 - 1e-3)
	local offset = upperBone.offset + lowerBone.offset
	return math.sqrt(bend * bend + offset * offset)
end

-- The nearest to its pivot a two-bone limb comfortably puts its end: folded to
-- Arms.MinReachFraction of its length, never tighter than the bones allow.
local function reachMinOf(upperBone: Bone, lowerBone: Bone): number
	local a, b = upperBone.length, lowerBone.length
	local fold = math.max(math.abs(a - b) + 1e-3, (a + b) * Config.Avatar.Arms.MinReachFraction)
	local offset = upperBone.offset + lowerBone.offset
	return math.sqrt(fold * fold + offset * offset)
end

-- How far the hips must come down for a leg reaching `reach` from hip H to reach T.
local function dropFor(H: Vector3, T: Vector3, reach: number): number
	local dx, dz = H.X - T.X, H.Z - T.Z
	return (H.Y - T.Y) - math.sqrt(math.max(0, reach * reach - dx * dx - dz * dz))
end

-- Everything whose arrival or departure changes the rig.
local function relevant(d: Instance): boolean
	return d:IsA("BasePart")
		or d:IsA("JointInstance")
		or d:IsA("Constraint")
		or d:IsA("WeldConstraint")
		or d:IsA("Attachment")
		or d:IsA("Accoutrement")
		or d:IsA("Decal")
		or d:IsA("Humanoid")
end

local function gripPoint(part: BasePart, name: string): Vector3
	local attachment = part:FindFirstChild(name)
	if attachment and attachment:IsA("Attachment") then
		return attachment.Position
	end
	return Vector3.new(0, -part.Size.Y / 2, 0) -- the bottom centre
end

local function bone(v: Vector3, ref: Vector3, hinged: boolean): Bone
	if not hinged then
		return { length = v.Magnitude, offset = 0, inv = basis(v, ref):Inverse() }
	end
	local offset = v.X
	local square = Vector3.new(0, v.Y, v.Z)
	return { length = square.Magnitude, offset = offset, inv = basis(square, ref):Inverse() }
end

-- An R15 arm. `bendDegrees` turns the hand at the wrist while it holds; `palmSide` is the
-- side of the hand its palm faces (+1 local +X).
local function arm15(
	rig: Rig,
	upper: number,
	lower: number,
	hand: number,
	gripName: string,
	bendDegrees: number,
	palmSide: number
): Limb
	local p0, p1, restRot = rig.p0, rig.p1, rig.restRot
	local handPart = rig.parts[hand]
	local grip = gripPoint(handPart, gripName)
	local hold = restRot[lower]:Inverse()
		* restRot[hand]
		* CFrame.Angles(math.rad(bendDegrees), 0, 0)
	-- The grip point in the forearm's space with the hand held at `hold`.
	local gripInLower = p0[hand] + hold * (grip - p1[hand])
	local size = handPart.Size
	local palm = Vector3.new(palmSide * size.X / 2, -size.Y * Config.Avatar.Arms.PalmFraction, 0)
		- p1[hand]
	return {
		upper = upper,
		lower = lower,
		finish = hand,
		upperBone = bone(p0[lower] - p1[upper], Vector3.xAxis, true),
		wristBone = bone(p0[hand] - p1[lower], Vector3.xAxis, true),
		gripBone = bone(gripInLower - p1[lower], Vector3.xAxis, true),
		hold = hold,
		point = grip,
		palm = palm,
		ankle = 0,
		sign = 1,
	}
end

local function leg15(rig: Rig, upper: number, lower: number, foot: number): Limb
	local p0, p1, restCF = rig.p0, rig.p1, rig.restCF
	local sole = Vector3.new(0, -rig.parts[foot].Size.Y / 2, 0)
	return {
		upper = upper,
		lower = lower,
		finish = foot,
		upperBone = bone(p0[lower] - p1[upper], Vector3.xAxis, true),
		wristBone = bone(p0[foot] - p1[lower], Vector3.xAxis, true),
		gripBone = NO_BONE,
		hold = CFrame.identity,
		point = sole,
		palm = ZERO,
		ankle = (restCF[foot] * p1[foot]).Y - (restCF[foot] * sole).Y,
		sign = -1,
	}
end

-- An R6 limb: one rigid part from its pivot to `point`, its front (local -Z) the reference.
local function rod6(rig: Rig, part: number, point: Vector3): Limb
	return {
		upper = part,
		lower = 0,
		finish = 0,
		upperBone = bone(point - rig.p1[part], -Vector3.zAxis, false),
		wristBone = NO_BONE,
		gripBone = NO_BONE,
		hold = CFrame.identity,
		point = point,
		palm = point - rig.p1[part],
		ankle = 0,
		sign = 1,
	}
end

-- The body ShooterStance plans with, from the rest rig, heights above the floor.
local function measure(rig: Rig): ShooterStance.Body
	local restCF, parts = rig.restCF, rig.parts
	local chest = restCF[rig.chest]
	local right = chest * rig.p0[rig.armR.upper]
	local left = chest * rig.p0[rig.armL.upper]
	local across = Vector3.new(right.X - left.X, 0, right.Z - left.Z)
	local r15 = rig.kind == "R15"
	local reachR = if r15
		then reachOf(rig.armR.upperBone, rig.armR.gripBone, 1)
		else rig.armR.upperBone.length
	local reachL = if r15
		then reachOf(rig.armL.upperBone, rig.armL.gripBone, 1)
		else rig.armL.upperBone.length
	-- The footprint: the parts a humanoid collides with (root, torso, head), in the root's
	-- axes. Limbs and accessories do not collide, so they do not count.
	local halfWidth, halfDepth = 0, 0
	local function cover(i: number)
		local cf, half = restCF[i], parts[i].Size / 2
		local x, y, z = cf.XVector, cf.YVector, cf.ZVector
		halfWidth = math.max(
			halfWidth,
			math.abs(cf.X)
				+ math.abs(x.X) * half.X
				+ math.abs(y.X) * half.Y
				+ math.abs(z.X) * half.Z
		)
		halfDepth = math.max(
			halfDepth,
			math.abs(cf.Z)
				+ math.abs(x.Z) * half.X
				+ math.abs(y.Z) * half.Y
				+ math.abs(z.Z) * half.Z
		)
	end
	cover(1)
	cover(rig.chest)
	cover(rig.head)
	if rig.pelvis > 0 then
		cover(rig.pelvis)
	end
	-- The hip pivots, and a thigh: pivot to knee (R15), or the whole rigid leg (R6).
	local legL, legR = rig.legL, rig.legR
	local hipL = (restCF[legL.upper] * rig.p1[legL.upper]).Y
	local hipR = (restCF[legR.upper] * rig.p1[legR.upper]).Y
	local thigh = math.min(legL.upperBone.length, legR.upperBone.length)
	-- The head: the neck pivot, the head's centre, and half its height or depth.
	local neck = restCF[rig.chest] * rig.p0[rig.head]
	local headCF, headSize = restCF[rig.head], parts[rig.head].Size
	return {
		RootHeight = rig.stand,
		WaistHeight = rig.stand + rig.waist.Y,
		ShoulderHeight = rig.stand + (right.Y + left.Y) / 2,
		ShoulderHalfWidth = across.Magnitude / 2,
		-- The shorter arm, shoulder pivot to grip point straight out: the stance's reach for
		-- the grip hand and the bridge hand alike.
		ArmReach = math.min(reachR, reachL),
		HalfWidth = halfWidth,
		HalfDepth = halfDepth,
		HipHeight = rig.stand + (hipL + hipR) / 2,
		ThighLength = thigh,
		NeckHeight = rig.stand + neck.Y,
		HeadLift = (headCF.Position - neck).Magnitude,
		HeadRadius = math.max(headSize.Y, headSize.Z) / 2,
	}
end

-- Rebuild the rig in place from the character as it is now. False (and the rig forgotten)
-- when its humanoid or root has gone or been replaced: the next AvatarPose.rig starts fresh.
local function rebuild(rig: Rig): boolean
	rig.dirty = false
	local character = rig.character
	local root, humanoid = rig.root, rig.humanoid
	if
		character:FindFirstChildOfClass("Humanoid") ~= humanoid
		or character:FindFirstChild("HumanoidRootPart") ~= root
	then
		AvatarPose.forget(character)
		return false
	end

	-- 1. Every joint between two of the character's parts, and the lists the local fade walks.
	local edgeA: { BasePart } = {}
	local edgeB: { BasePart } = {}
	local edgeC0: { CFrame } = {}
	local edgeC1: { CFrame } = {}
	local visual: { BasePart } = {}
	local inAccessory: { boolean } = {}
	local decals: { Decal } = {}
	local function edge(a: Instance?, b: Instance?, c0: CFrame, c1: CFrame)
		if
			a
			and b
			and a ~= b
			and a:IsA("BasePart")
			and b:IsA("BasePart")
			and a:IsDescendantOf(character)
			and b:IsDescendantOf(character)
		then
			table.insert(edgeA, a)
			table.insert(edgeB, b)
			table.insert(edgeC0, c0)
			table.insert(edgeC1, c1)
		end
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			if d ~= root then
				table.insert(visual, d)
				table.insert(inAccessory, d:FindFirstAncestorWhichIsA("Accoutrement") ~= nil)
			end
		elseif d:IsA("Decal") then
			table.insert(decals, d)
		elseif d:IsA("JointInstance") then
			-- Part0 * C0 == Part1 * C1 at rest (Motor6D, Weld, ManualWeld and the rest).
			if d.Enabled then
				edge(d.Part0, d.Part1, d.C0, d.C1)
			end
		elseif d:IsA("AnimationConstraint") or d:IsA("RigidConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if d.Enabled and a0 and a1 then
				edge(a0.Parent, a1.Parent, a0.CFrame, a1.CFrame)
			end
		elseif d:IsA("WeldConstraint") then
			-- No offset property: the parts' offset as they stand now.
			local a, b = d.Part0 :: BasePart?, d.Part1 :: BasePart?
			if d.Enabled and a and b then
				edge(a, b, a.CFrame:ToObjectSpace(b.CFrame), CFrame.identity)
			end
		end
	end

	-- 2. The tree: breadth first from the root over the joints in either direction, so each
	-- part comes after its parent. A joint met from its Part1 side is inverted.
	local adjacency: { [BasePart]: { number } } = {}
	local function link(part: BasePart, k: number)
		local list = adjacency[part]
		if list then
			table.insert(list, k)
		else
			adjacency[part] = { k }
		end
	end
	for k = 1, #edgeA do
		link(edgeA[k], k)
		link(edgeB[k], k)
	end
	local parts: { BasePart } = { root }
	local parent: { number } = { 0 }
	local rest: { CFrame } = { CFrame.identity }
	local p0: { Vector3 } = { ZERO }
	local p1: { Vector3 } = { ZERO }
	local seen: { [BasePart]: boolean } = { [root] = true }
	local at = 1
	while at <= #parts do
		local list = adjacency[parts[at]]
		if list then
			for _, k in list do
				local forward = edgeA[k] == parts[at]
				local child = if forward then edgeB[k] else edgeA[k]
				if not seen[child] then
					seen[child] = true
					table.insert(parts, child)
					local n = #parts
					parent[n] = at
					local c0, c1 = edgeC0[k], edgeC1[k]
					if forward then
						rest[n], p0[n], p1[n] = c0 * c1:Inverse(), c0.Position, c1.Position
					else
						rest[n], p0[n], p1[n] = c1 * c0:Inverse(), c1.Position, c0.Position
					end
				end
			end
		end
		at += 1
	end
	local n = #parts
	local restCF = table.create(n, CFrame.identity)
	local restRot = table.create(n, CFrame.identity)
	for i = 2, n do
		restCF[i] = restCF[parent[i]] * rest[i]
		restRot[i] = restCF[i].Rotation
	end

	-- 3. The body parts' roles.
	local kind: Kind = if humanoid.RigType == Enum.HumanoidRigType.R15 then "R15" else "R6"
	local role: { [string]: number } = {}
	local valid = true
	local roles: { { string } } = if kind == "R15" then R15_ROLES else R6_ROLES
	for _, row in roles do
		local want = if row[3] == "" then 1 else role[row[3]]
		local found = 0
		if want then
			for i = 2, n do
				if parent[i] == want and parts[i].Name == row[2] then
					found = i
					break
				end
			end
		end
		if found > 0 then
			role[row[1]] = found
		else
			valid = false
		end
	end
	local isRole: { [number]: boolean } = {}
	for _, i in role do
		isRole[i] = true
	end
	local generic: { number } = {}
	for i = 2, n do
		if not valid or not isRole[i] then
			table.insert(generic, i)
		end
	end

	rig.kind = kind
	rig.valid = valid
	rig.version += 1
	rig.parts = parts
	rig.cframes = table.create(n, CFrame.identity)
	rig.parent = parent
	rig.rest = rest
	rig.restCF = restCF
	rig.restRot = restRot
	rig.p0 = p0
	rig.p1 = p1
	rig.role = role
	rig.generic = generic
	rig.visual = visual
	rig.visualInAccessory = inAccessory
	rig.decals = decals

	-- 4. Limbs and measurements.
	if not valid then
		rig.pelvis, rig.chest, rig.head = 0, 1, 1
		rig.armR, rig.armL, rig.legR, rig.legL = NO_LIMB, NO_LIMB, NO_LIMB, NO_LIMB
		rig.pivot, rig.waist, rig.chestRestInv = ZERO, ZERO, CFrame.identity
		rig.stand = humanoid.HipHeight + root.Size.Y / 2
		rig.body = nil
		return true
	end
	if kind == "R15" then
		local bend = Config.Avatar.Arms.GripWristDegrees
		rig.pelvis, rig.chest, rig.head = role.Pelvis, role.Chest, role.Head
		rig.armR =
			arm15(rig, role.UpperArmR, role.LowerArmR, role.HandR, "RightGripAttachment", bend, -1)
		-- The off hand's grip bone is straight (no wrist turn): measure() takes the arm's reach
		-- from it. Its palm faces local +X.
		rig.armL =
			arm15(rig, role.UpperArmL, role.LowerArmL, role.HandL, "LeftGripAttachment", 0, 1)
		rig.legR = leg15(rig, role.UpperLegR, role.LowerLegR, role.FootR)
		rig.legL = leg15(rig, role.UpperLegL, role.LowerLegL, role.FootL)
		rig.pivot = p1[rig.chest] -- the waist
		-- What the Humanoid itself holds the root at, so a released body does not drop.
		rig.stand = humanoid.HipHeight + root.Size.Y / 2
	else
		local function sole(i: number): Vector3
			return Vector3.new(0, -parts[i].Size.Y / 2, 0)
		end
		rig.pelvis, rig.chest, rig.head = 0, role.Torso, role.Head
		rig.armR = rod6(rig, role.ArmR, gripPoint(parts[role.ArmR], "RightGripAttachment"))
		rig.armL = rod6(rig, role.ArmL, gripPoint(parts[role.ArmL], "LeftGripAttachment"))
		rig.legR = rod6(rig, role.LegR, sole(role.LegR))
		rig.legL = rod6(rig, role.LegL, sole(role.LegL))
		-- No waist: the one torso leans about the centre of the hip line.
		local hips = (p0[role.LegR] + p0[role.LegL]) / 2
		rig.pivot = Vector3.new(0, hips.Y, hips.Z)
		local lowest =
			math.min((restCF[role.LegR] * rig.legR.point).Y, (restCF[role.LegL] * rig.legL.point).Y)
		rig.stand = humanoid.HipHeight - lowest
	end
	rig.waist = restCF[rig.chest] * rig.pivot
	rig.chestRestInv = restRot[rig.chest]:Inverse()
	rig.body = measure(rig)
	return true
end

-- A new rig for `character`, listening for changes; nil without a humanoid and a root.
local function create(character: Model): Rig?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") then
		return nil
	end
	local rig: Rig = {
		character = character,
		humanoid = humanoid,
		root = root,
		kind = "R15",
		valid = false,
		alive = true,
		dirty = true,
		version = 0,
		parts = {},
		cframes = {},
		parent = {},
		rest = {},
		restCF = {},
		restRot = {},
		p0 = {},
		p1 = {},
		role = {},
		generic = {},
		pelvis = 0,
		chest = 1,
		head = 1,
		armR = NO_LIMB,
		armL = NO_LIMB,
		legR = NO_LIMB,
		legL = NO_LIMB,
		pivot = ZERO,
		waist = ZERO,
		chestRestInv = CFrame.identity,
		stand = 0,
		body = nil,
		visual = {},
		visualInAccessory = {},
		decals = {},
		conns = {},
	}
	local function changed(d: Instance)
		if relevant(d) then
			rig.dirty = true
		end
	end
	local function mark()
		rig.dirty = true
	end
	local conns = rig.conns
	table.insert(conns, character.DescendantAdded:Connect(changed))
	table.insert(conns, character.DescendantRemoving:Connect(changed))
	table.insert(conns, humanoid:GetPropertyChangedSignal("RigType"):Connect(mark))
	-- A rescaled body (the humanoid's scale values) changes its hip height with its sizes.
	table.insert(conns, humanoid:GetPropertyChangedSignal("HipHeight"):Connect(mark))
	table.insert(
		conns,
		character.Destroying:Connect(function()
			AvatarPose.forget(character)
		end)
	)
	table.insert(
		conns,
		character.AncestryChanged:Connect(function()
			if character.Parent == nil then
				AvatarPose.forget(character)
			end
		end)
	)
	return rig
end

--- The character's rig, built on first use and cached; rebuilt (in place, `version` bumped)
--- after the character changed. nil without a Humanoid and a HumanoidRootPart, or outside the
--- game. A rig that was forgotten is never revived: ask again for a fresh one.
function AvatarPose.rig(character: Model): Rig?
	local cached = rigs[character]
	if cached and (not cached.dirty or rebuild(cached)) then
		return cached
	end
	if character.Parent == nil then
		return nil
	end
	local rig = create(character)
	if rig == nil then
		return nil
	end
	rigs[character] = rig
	return if rebuild(rig) then rig else nil
end

--- Drop the character's rig and its connections (called on its own when the character is
--- destroyed or taken out of the game).
function AvatarPose.forget(character: Model)
	local rig = rigs[character]
	if rig == nil then
		return
	end
	rigs[character] = nil
	rig.alive = false
	rig.valid = false
	for _, conn in rig.conns do
		conn:Disconnect()
	end
	table.clear(rig.conns)
end

--- The body ShooterStance plans with, measured from the character's rest rig (R15 or R6,
--- scaled or not): heights above the floor, reach and footprint in studs. nil if the rig is
--- not a whole R15 or R6 body. The table is shared: never modify it.
function AvatarPose.measureBody(character: Model): ShooterStance.Body?
	local rig = AvatarPose.rig(character)
	return if rig then rig.body else nil
end

--- The root's centre above the floor when the character stands (the Body's RootHeight).
function AvatarPose.standHeight(character: Model): number?
	local body = AvatarPose.measureBody(character)
	return if body then body.RootHeight else nil
end

--- A frame to fill and pass to pose() every frame. Keep one per posed character.
function AvatarPose.newFrame(): Frame
	return {
		root = CFrame.identity,
		floorY = 0,
		mode = "stand",
		supportY = 0,
		lean = 0,
		torsoDegrees = nil,
		pull = 0,
		tip = CFrame.identity,
		gripAlong = 0,
		cueLength = Config.Cue.CueLengthStuds,
		offKind = 0,
		offHand = ZERO,
		look = ZERO,
		backLegLift = 0,
		grip = ZERO,
		gripMiss = 0,
		offMiss = 0,
	}
end

-- Two-bone IK for an R15 limb (upper bone then `lowerBone`), placing its upper and lower
-- parts. The limb bends about a hinge toward `pole`. Bones whose pivots sit apart along the
-- hinge put the bending plane off the start pivot by that much, so the hinge is tilted until
-- the target lies in that plane.
local function reachTo(
	rig: Rig,
	limb: Limb,
	lowerBone: Bone,
	S: Vector3,
	T: Vector3,
	pole: Vector3,
	soft: number
)
	local cf, p0, p1 = rig.cframes, rig.p0, rig.p1
	local upperBone = limb.upperBone
	local d = T - S
	local dist = d.Magnitude
	local u = if dist > 1e-6 then d / dist else -UP
	-- A two-bone chain bent toward the pole bends about pole x reach (an elbow's local +X).
	local normal = pole:Cross(u)
	if normal.Magnitude < 1e-6 then
		normal = u:Cross(if math.abs(u.Y) < 0.9 then UP else Vector3.xAxis)
		pole = u:Cross(normal)
	end
	local hinge = normal.Unit * limb.sign
	local offset = upperBone.offset + lowerBone.offset
	if offset ~= 0 and dist > 1e-6 then
		local s = math.clamp(offset / dist, -1, 1)
		hinge = hinge * math.sqrt(1 - s * s) + u * s
	end
	local S2 = S + hinge * upperBone.offset
	local T2 = T - hinge * lowerBone.offset
	-- Into the bending plane (only a target nearer than the offsets is ever out of it): the
	-- end then falls short, but the joint stays a true hinge.
	T2 -= hinge * (T2 - S2):Dot(hinge)
	local bendPole = pole - hinge * pole:Dot(hinge)
	local ex, ey, ez, nx, ny, nz = PoseMath.twoBone(
		S2.X,
		S2.Y,
		S2.Z,
		T2.X,
		T2.Y,
		T2.Z,
		bendPole.X,
		bendPole.Y,
		bendPole.Z,
		upperBone.length,
		lowerBone.length,
		soft
	)
	local E = Vector3.new(ex, ey, ez)
	local N = Vector3.new(nx, ny, nz)
	local upper = limb.upper
	cf[upper] = place(S, aligned(E - S2, hinge, upperBone.inv), p1[upper])
	local lower = limb.lower
	cf[lower] = place(cf[upper] * p0[lower], aligned(N - E, hinge, lowerBone.inv), p1[lower])
end

-- Point a rigid (R6) limb from its pivot S at T, its front turned toward `ref`.
local function aimRod(rig: Rig, limb: Limb, S: Vector3, T: Vector3, ref: Vector3)
	local part = limb.upper
	rig.cframes[part] = place(S, aligned(T - S, ref, limb.upperBone.inv), rig.p1[part])
end

-- The point along the line through `from` (along `dir`, lo to hi studs from it) that is
-- exactly `r` from S, the one nearest `prefer` of the two; or the nearest the range allows.
local function along(
	from: Vector3,
	dir: Vector3,
	S: Vector3,
	r: number,
	prefer: number,
	lo: number,
	hi: number
): Vector3
	local t = PoseMath.lineSphere(
		from.X,
		from.Y,
		from.Z,
		dir.X,
		dir.Y,
		dir.Z,
		S.X,
		S.Y,
		S.Z,
		r,
		prefer,
		lo,
		hi
	)
	return from + dir * t
end

-- The limbs, head and body of a valid rig into rig.cframes (the root is already there).
local function solve(rig: Rig, f: Frame)
	local A = Config.Avatar
	local Arms, Legs = A.Arms, A.Legs
	local cf, p0, p1, restRot = rig.cframes, rig.p0, rig.p1, rig.restRot
	local r15 = rig.kind == "R15"
	local profile = PROFILES[f.mode] or PROFILES.stand
	local lean = math.clamp(f.lean, 0, 1)
	local root = f.root
	local rootRot = root.Rotation
	local fwd, right = root.LookVector, root.RightVector

	-- 1. The torso. The chest leans the stance's torso angle about the waist, straight along
	-- the facing, which is where the stance put the shoulders when it decided what reaches;
	-- the hips tip part of the way (more on a taller body), twist further open, and the chest
	-- turns back about its own spine, which keeps the chin over the cue.
	local k =
		math.clamp(rig.stand / A.Body.NominalStandStuds, A.Body.LeanScaleMin, A.Body.LeanScaleMax)
	local pelvisPitch = math.rad(lerp(profile.PelvisPitch, lean)) * k
	local torso = if f.torsoDegrees
		then math.rad(f.torsoDegrees)
		else pelvisPitch + math.rad(lerp(profile.ChestPitch, lean)) * k
	pelvisPitch = math.min(pelvisPitch, torso)
	local follow = if r15 then A.Body.FollowStuds else A.Body.R6FollowStuds
	local waist = root * rig.waist
		- fwd * (profile.HipBackStuds * lean + follow * math.clamp(f.pull, 0, 1))
		- UP * (profile.CrouchStuds * lean)
	local chest = rig.chest
	local chestRot: CFrame, hipRot: CFrame, hipPivot: Vector3
	if r15 then
		local twist = math.rad(profile.HipTwistDegrees)
		hipRot = rootRot * CFrame.fromEulerAnglesYXZ(-pelvisPitch, -twist, 0) * restRot[rig.pelvis]
		hipPivot = p0[chest] -- the waist, in the pelvis's space
		chestRot = rootRot
			* CFrame.Angles(
				-torso,
				math.rad(profile.ChestCounterDegrees) - twist,
				math.rad(profile.ChestRollDegrees)
			)
			* restRot[chest]
	else
		-- One torso: it leans about the hip line, so the legs stay where they are.
		chestRot = rootRot * CFrame.Angles(-torso * A.Body.R6TorsoPitchScale, 0, 0) * restRot[chest]
		hipRot, hipPivot = chestRot, rig.pivot
	end

	-- 2. Where the legs go. Standing, the feet are planted around where the root stands (an
	-- R15 body's sway and lean never drag them), the back foot may lift, toe down, and the
	-- hips come down just enough for both legs to reach, so the feet stay on the floor.
	-- Stretching over the rail, the same. Kneeling on the table (or
	-- up on the rail top), each knee rests on the surface below and behind its hip, the shin
	-- lying back along it; the hips never move for that: the stance put the root at the height
	-- it needs.
	local legL, legR = rig.legL, rig.legR
	local lift = math.clamp(f.backLegLift, 0, 1)
	local hipL = waist + hipRot * (p0[legL.upper] - hipPivot)
	local hipR = waist + hipRot * (p0[legR.upper] - hipPivot)
	local targetL, targetR, kneeL, kneeR
	local kneeling = f.mode == "table" or f.mode == "rail"
	if kneeling then
		-- The knee on the cloth (KneeRestStuds up), straight back from the hip as far as the
		-- thigh reaches down to it; the ankle a shin's length further back, just above.
		local rest = Config.Stance.Table.KneeRestStuds
		local spread = right * Legs.KneelKneeSpreadStuds
		local function knee(hip: Vector3, length: number, sign: number): Vector3
			local drop = hip.Y - (f.supportY + rest)
			local back = math.sqrt(math.max(0, length * length - drop * drop))
			return Vector3.new(hip.X, f.supportY + rest, hip.Z) - fwd * back + spread * sign
		end
		if r15 then
			kneeL = knee(hipL, legL.upperBone.length, -1)
			kneeR = knee(hipR, legR.upperBone.length, 1)
			local shinL = legL.wristBone.length
			local shinR = legR.wristBone.length
			targetL = kneeL - fwd * shinL + UP * legL.ankle * 0.5
			targetR = kneeR - fwd * shinR + UP * legR.ankle * 0.5
		else
			targetL = knee(hipL, legL.upperBone.length, -1)
			targetR = knee(hipR, legR.upperBone.length, 1)
		end
	else
		local floor = Vector3.new(root.X, f.floorY, root.Z)
		if not r15 then
			-- Rigid legs cannot take up the sway, so an R6 body sways as a whole.
			local sway = waist - root * rig.waist
			floor += Vector3.new(sway.X, 0, sway.Z)
		end
		local front, back = Legs.FrontFoot, Legs.BackFoot
		targetL = floor + right * front[1] + fwd * front[2] + UP * legL.ankle
		targetR = floor
			+ right * back[1]
			+ fwd * (back[2] - lift * Legs.BackLegLiftBackStuds)
			+ UP * (lift * Legs.BackLegLiftStuds + legR.ankle)
		local reachL = if r15
			then reachOf(legL.upperBone, legL.wristBone, Legs.Straightness)
			else legL.upperBone.length
		local reachR = if r15
			then reachOf(legR.upperBone, legR.wristBone, Legs.Straightness)
			else legR.upperBone.length
		-- Bending legs both reach once the hips are as low as the further one needs. Rigid
		-- (R6) legs are exact for one foot only, so the hips split the difference (up or down)
		-- and neither foot sinks or floats by more than half of it; a lifting back foot counts
		-- for less, and not at all once it is off the floor.
		local dropL, dropR = dropFor(hipL, targetL, reachL), dropFor(hipR, targetR, reachR)
		local most = Legs.MaxHipDropStuds
		local planted = 1 - lift
		local drop = if r15
			then math.clamp(math.max(dropL, dropR), 0, most)
			else math.clamp((dropL + dropR * planted) / (1 + planted), -most, most)
		waist -= UP * drop
		hipL -= UP * drop
		hipR -= UP * drop
	end
	if r15 then
		cf[rig.pelvis] = place(waist, hipRot, hipPivot)
	end
	cf[chest] = place(waist, chestRot, rig.pivot)
	local chestCF = cf[chest]
	local axes = chestCF.Rotation * rig.chestRestInv -- the chest's axes without its rest turn

	-- 3. The head looks at the cue ball, as far as a neck turns.
	local head = rig.head
	local neck = chestCF * p0[head]
	local toLook = f.look - neck
	local yaw, pitch = 0, 0
	if toLook.Magnitude > 1e-4 then
		local H = A.Head
		local v = axes:VectorToObjectSpace(toLook.Unit)
		local maxYaw, maxPitch = math.rad(H.MaxYawDegrees), math.rad(H.MaxPitchDegrees)
		yaw = math.clamp(math.atan2(-v.X, -v.Z) * H.LookWeight, -maxYaw, maxYaw)
		pitch = math.clamp(math.asin(math.clamp(v.Y, -1, 1)) * H.LookWeight, -maxPitch, maxPitch)
	end
	cf[head] =
		place(neck, axes * CFrame.fromEulerAnglesYXZ(pitch, yaw, 0) * restRot[head], p1[head])

	-- 4. The grip hand holds the cue gripAlong from the tip. Out of reach (or too near the
	-- shoulder to fold the arm), it slides along the cue, never past the butt's end, to where
	-- the arm meets it; an R6 arm is rigid, so it always meets the cue where it can.
	local soft = Arms.SoftReach
	local tip = f.tip
	local tipPos, cueAxis = tip.Position, tip.ZVector
	local gripAlong = f.gripAlong
	local grip = rig.armR
	local S = chestCF * p0[grip.upper]
	local reach = if r15
		then reachOf(grip.upperBone, grip.gripBone, soft)
		else grip.upperBone.length
	local G = tipPos + cueAxis * gripAlong
	local Stance = Config.Stance
	local butt = math.max(0, f.cueLength - Stance.GripButtEndStuds - gripAlong)
	-- As far toward the tip as a stance would ever put a grip.
	local nearest =
		math.min(0, Stance.GripMinFromTipFraction * Config.Cue.CueLengthStuds - gripAlong)
	if r15 then
		-- Too far: a short slide either way. Too near (the butt by the shoulder, as the rake's
		-- upright stance often has it): the hand chokes up the cue until the arm can fold to it.
		local slide = Arms.MaxGripSlideStuds
		local d = (G - S).Magnitude
		local rMin = reachMinOf(grip.upperBone, grip.gripBone)
		if d > reach then
			G = along(G, cueAxis, S, reach, 0, math.max(nearest, -slide), math.min(slide, butt))
		elseif d < rMin then
			G = along(G, cueAxis, S, rMin, 0, nearest, math.min(slide, butt))
		end
	else
		-- A rigid arm holds the cue wherever along its back part the arm meets it.
		G = along(G, cueAxis, S, reach, 0, nearest, butt)
	end
	f.grip = G
	if r15 then
		local pole = axes:VectorToWorldSpace(vec(Arms.GripPole))
		reachTo(rig, grip, grip.gripBone, S, G, pole, soft)
		local hand = grip.finish
		local forearm = cf[grip.lower]
		cf[hand] = place(forearm * p0[hand], forearm.Rotation * grip.hold, p1[hand])
		f.gripMiss = (cf[hand] * grip.point - G).Magnitude
	else
		aimRod(rig, grip, S, G, fwd)
		f.gripMiss = math.abs((G - S).Magnitude - reach)
	end

	-- 5. The off hand: a bridge under the cue, or hanging relaxed.
	local off = rig.armL
	S = chestCF * p0[off.upper]
	local offKind = f.offKind
	local slide = Arms.MaxBridgeSlideStuds
	if offKind == 1 then
		-- Palm down on the surface, fingers along the cue dipping toward the cloth, the palm
		-- snapped under the cue; out of reach, it slides back along the cue toward the body.
		local cueBack = tip.ZVector
		local flat = Vector3.new(-cueBack.X, 0, -cueBack.Z)
		flat = if flat.Magnitude > 1e-6 then flat.Unit else fwd
		local side = flat:Cross(UP)
		local B = f.offHand + UP * Arms.BridgeLiftStuds
		B -= side * (B - tipPos):Dot(side)
		if r15 then
			local dip = math.rad(Arms.BridgeFingerDownDegrees)
			local fingers = flat * math.cos(dip) - UP * math.sin(dip)
			local down = (-UP + fingers * fingers.Y).Unit
			-- The hand's +X (its palm) down, its -Y (the fingers) along the cue.
			local handRot = CFrame.fromMatrix(ZERO, down, -fingers)
			local offset = handRot * off.palm
			local W = B - offset
			local r = reachOf(off.upperBone, off.wristBone, soft)
			if (W - S).Magnitude > r then
				W = along(W, -flat, S, r, 0, 0, slide)
				B = W + offset
			end
			local pole = axes:VectorToWorldSpace(vec(Arms.BridgePole))
			reachTo(rig, off, off.wristBone, S, W, pole, soft)
			local hand = off.finish
			cf[hand] = place(cf[off.lower] * p0[hand], handRot, p1[hand])
			f.offMiss = (cf[hand] * (p1[hand] + off.palm) - B).Magnitude
		else
			local P = along(B, -flat, S, off.upperBone.length, 0, -slide, slide)
			aimRod(rig, off, S, P, fwd)
			f.offMiss = math.abs((P - S).Magnitude - off.upperBone.length)
		end
	else
		-- Relaxed: the arm hangs straight down, the elbow barely bent.
		if r15 then
			local W = S - UP * ((off.upperBone.length + off.wristBone.length) * Arms.RelaxedReach)
			local pole = axes:VectorToWorldSpace(vec(Arms.BridgePole))
			reachTo(rig, off, off.wristBone, S, W, pole, soft)
			local hand = off.finish
			local forearm = cf[off.lower]
			cf[hand] = place(forearm * p0[hand], forearm.Rotation * off.hold, p1[hand])
		else
			aimRod(rig, off, S, S - UP, fwd)
		end
		f.offMiss = 0
	end

	-- 6. The legs reach their targets. Standing, knees over the toes and the feet flat, toes out
	-- (the back one pitched down as it lifts). Kneeling, each knee lands on its spot on the cloth and the foot lies pitched toe down.
	local toe = math.rad(Legs.ToeOutDegrees)
	local footPitch = lift * math.rad(Legs.BackFootPitchDegrees)
	for side = 1, 2 do
		local leg = if side == 1 then legL else legR
		local H = if side == 1 then hipL else hipR
		local T = if side == 1 then targetL else targetR
		local turn = if side == 1 then toe else -toe -- the left (front) foot turns left
		local toes = fwd * math.cos(turn) - right * math.sin(turn)
		if r15 then
			local pole = toes
			if kneeling then
				-- Bend at the knee's spot: pole from the hip-ankle line out toward it.
				local K = if side == 1 then kneeL else kneeR
				pole = K - (H + T) / 2
			end
			reachTo(rig, leg, leg.wristBone, H, T, pole, 1)
			local foot = leg.finish
			local down = if kneeling
				then math.rad(Legs.KneelFootPitchDegrees)
				elseif side == 1 then 0
				else footPitch
			cf[foot] = place(
				cf[leg.lower] * p0[foot],
				rootRot * CFrame.fromEulerAnglesYXZ(-down, turn, 0) * restRot[foot],
				p1[foot]
			)
		else
			aimRod(rig, leg, H, T, toes)
		end
	end
end

--- Pose the character for one frame: every part of the rig, the root included (at f.root),
--- moved with one BulkMoveTo. The caller anchors the limbs (the server holds the root) and
--- keeps them anchored while posing. An invalid rig moves rigidly in its rest pose.
function AvatarPose.pose(rig: Rig, f: Frame)
	if rig.alive and rig.dirty then
		rebuild(rig)
	end
	if not rig.alive then
		return
	end
	local cf = rig.cframes
	cf[1] = f.root
	if rig.valid then
		solve(rig, f)
		local parent, rest = rig.parent, rig.rest
		for _, i in rig.generic do
			cf[i] = cf[parent[i]] * rest[i]
		end
	else
		local parent, rest = rig.parent, rig.rest
		for i = 2, #rig.parts do
			cf[i] = cf[parent[i]] * rest[i]
		end
	end
	workspace:BulkMoveTo(rig.parts, cf, Enum.BulkMoveMode.FireCFrameChanged)
end

--- Fade the local player's own character: every part but the root to `transparency` (local
--- only, LocalTransparencyModifier), and with `hideAccessories` accessories gone entirely so
--- they cannot cover the table. Never for anyone else's body: everyone else is seen whole.
function AvatarPose.setFade(rig: Rig, transparency: number, hideAccessories: boolean)
	local me = Players.LocalPlayer
	local owner = Players:GetPlayerFromCharacter(rig.character)
	assert(
		me ~= nil and (owner == nil or owner == me),
		"AvatarPose.setFade is for the local player's own character only"
	)
	if rig.alive and rig.dirty then
		rebuild(rig)
	end
	if not rig.alive then
		return
	end
	local inAccessory = rig.visualInAccessory
	for i, part in rig.visual do
		part.LocalTransparencyModifier = if hideAccessories and inAccessory[i]
			then 1
			else transparency
	end
	for _, decal in rig.decals do
		decal.Transparency = transparency
	end
end

return AvatarPose
