--!strict
-- Writes the lucky block arm animations (the test build, 2026-10-03) as KeyframeSequences in
-- assets/luckyblocks/anims/: Hold (looped: both arms out in front, holding the block at chest
-- height) and Throw (a short dip and a flick forward, with a "Release" marker where the block
-- leaves the hands), each for R15 and R6. Only the arms (and the throw's waist) are posed, so the
-- legs keep walking under them.
--
--   lune run tools/make_hand_anims.luau
-- then upload with tools/roblox_upload.py --force-type Animation --group-id 675425213 and put
-- the ids in Config.LuckyBlocks.Anim. The block's place in the hands is Config.LuckyBlocks.Held.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local OUT = "assets/luckyblocks/anims/"
assert(fs.isDir("src/shared"), "run this from the repo root: lune run tools/make_hand_anims.luau")

local rad = math.rad

-- One arm's angles (degrees): pitch raises it forward, yaw turns it in toward the middle,
-- elbow bends the forearm up, wrist rolls the palm in.
type Arm = { pitch: number, yaw: number, elbow: number, wrist: number }
-- One frame: both arms (mirrored) and the waist's lean (R15 UpperTorso; + forward).
type Frame = { t: number, arm: Arm, lean: number?, easing: string? }

local HOLD: Arm = { pitch = 72, yaw = 10, elbow = 18, wrist = 25 }
-- R6 arms are a stud thick with no hands: turned in a little more to meet the block's sides.
local HOLD_R6: Arm = { pitch = 72, yaw = 14, elbow = 0, wrist = 0 }

local THROW: { Frame } = {
	{ t = 0, arm = HOLD },
	{ t = 0.12, arm = { pitch = 38, yaw = 14, elbow = 34, wrist = 20 }, lean = -6 },
	{ t = 0.24, arm = { pitch = 105, yaw = 8, elbow = 4, wrist = 10 }, lean = 10, easing = "Out" },
	{ t = 0.45, arm = { pitch = 70, yaw = 12, elbow = 12, wrist = 15 }, lean = 3 },
}
local RELEASE_AT = 0.22

local function pose(name: string, cf: any, weight: number?, easing: string?): any
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	p.Weight = weight or 1
	p.EasingStyle = Enum.PoseEasingStyle.Cubic
	p.EasingDirection = if easing == "Out"
		then Enum.PoseEasingDirection.Out
		else Enum.PoseEasingDirection.InOut
	return p
end

-- A parent pose that only carries the hierarchy (weight 0: it drives nothing).
local function holder(name: string): any
	return pose(name, CFrame.new(), 0)
end

local function r15Keyframe(frame: Frame): any
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = frame.t
	local root = holder("HumanoidRootPart")
	root.Parent = keyframe
	local lower = holder("LowerTorso")
	lower.Parent = root
	local upper = if frame.lean
		then pose("UpperTorso", CFrame.Angles(rad(-(frame.lean :: number)), 0, 0), 1, frame.easing)
		else holder("UpperTorso")
	upper.Parent = lower
	local a = frame.arm
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local upperArm = pose(
			side .. "UpperArm",
			CFrame.fromEulerAnglesYXZ(rad(a.pitch), rad(a.yaw * s), 0),
			1,
			frame.easing
		)
		upperArm.Parent = upper
		local lowerArm =
			pose(side .. "LowerArm", CFrame.Angles(rad(a.elbow), 0, 0), 1, frame.easing)
		lowerArm.Parent = upperArm
		local hand = pose(side .. "Hand", CFrame.Angles(0, rad(a.wrist * s), 0), 1, frame.easing)
		hand.Parent = lowerArm
	end
	return keyframe
end

-- R6: the shoulders' C0 is turned a quarter about Y, so raising an arm forward is a turn about
-- the joint's Z (right +, left -) and turning it in is about Y.
local function r6Keyframe(frame: Frame): any
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = frame.t
	local root = holder("HumanoidRootPart")
	root.Parent = keyframe
	local torso = holder("Torso")
	torso.Parent = root
	local a = frame.arm
	for _, side in { "Right", "Left" } do
		local s = if side == "Right" then 1 else -1
		local cf = CFrame.Angles(0, rad(a.yaw * s), 0) * CFrame.Angles(0, 0, rad(a.pitch * s))
		local arm = pose(side .. " Arm", cf, 1, frame.easing)
		arm.Parent = torso
	end
	return keyframe
end

local function sequence(
	name: string,
	frames: { Frame },
	loop: boolean,
	priority: any,
	r15: boolean
): any
	local kfs = Instance.new("KeyframeSequence")
	kfs.Name = name
	kfs.Loop = loop
	kfs.Priority = priority
	for _, frame in frames do
		local keyframe = if r15 then r15Keyframe(frame) else r6Keyframe(frame)
		keyframe.Parent = kfs
	end
	return kfs
end

local function withRelease(kfs: any)
	local keyframe = Instance.new("Keyframe")
	keyframe.Time = RELEASE_AT
	local marker = Instance.new("KeyframeMarker")
	marker.Name = "Release"
	marker.Parent = keyframe
	keyframe.Parent = kfs
end

local function holdFrames(r15: boolean): { Frame }
	local arm = if r15 then HOLD else HOLD_R6
	return { { t = 0, arm = arm }, { t = 1, arm = arm } }
end

for _, rig in { "R15", "R6" } do
	local r15 = rig == "R15"
	local hold =
		sequence("LuckyHold" .. rig, holdFrames(r15), true, Enum.AnimationPriority.Action, r15)
	local throw = sequence("LuckyThrow" .. rig, THROW, false, Enum.AnimationPriority.Action2, r15)
	withRelease(throw)
	for _, kfs in { hold, throw } do
		local path = OUT .. kfs.Name .. ".rbxm"
		fs.writeFile(path, roblox.serializeModel({ kfs }))
		print("wrote " .. path)
	end
end
