--!strict
-- Writes the idle animations for our own lucky block models (designer, 2026-10-07) as
-- KeyframeSequences in assets/luckyblocks/anims/.
--
-- LuckyWingIdle is the same hover with the wings flapping twice a loop (Legendary, Mythic, Sky).
-- LuckyBoxIdle is the pack's Box Idle (anims/BoxIdle.rbxm) moved onto our rig: the block hovers
-- between about 1 and 1.9 studs over its rest spot and tilts a few degrees, over 2.46 s. The pack's
-- poses are in its mesh units; its model plays them at scale 0.02 (measured in Studio), so the
-- copy is in studs for our 4.66-stud block at scale 1. Our rig comes from a glb
-- (tools/luckyblock_build.py), which Roblox loads as RootPart > joint1 > joint2 with joint1
-- turned half a turn about Y, so each pose is turned into that bone's own frame (B^-1 * J * B,
-- docs/STUDIO_NOTES.md "A skinned glb survives Open Cloud").
--
--   lune run tools/luckyblock_anims.luau
-- then upload with tools/roblox_upload.py --force-type Animation --group-id 675425213 and put
-- the id in Config.LuckyBlocks (the kind's Idle).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local CFrame = roblox.CFrame

local DIR = "assets/luckyblocks/anims/"
assert(fs.isDir("src/shared"), "run this from the repo root: lune run tools/luckyblock_anims.luau")

local PACK_SCALE = 0.02 -- the pack's Standard block: Model:GetScale() in Studio
local FLIP = CFrame.Angles(0, math.pi, 0) -- joint1's rest turn in our loaded rig

local function find(parent: any, name: string): any
	for _, d in parent:GetDescendants() do
		if d.Name == name and d.ClassName == "Pose" then
			return d
		end
	end
	return nil
end

local function pose(name: string, cf: any, weight: number, parent: any): any
	local p = Instance.new("Pose")
	p.Name = name
	p.CFrame = cf
	p.Weight = weight
	p.EasingStyle = roblox.Enum.PoseEasingStyle.Linear
	p.Parent = parent
	return p
end

-- The wings (Legendary, Mythic, Sky): wingL and wingR hang on joint2 at the block's upper sides.
-- Their rest frames as Roblox loads them (read from the LegendaryBlock template in Studio,
-- 2026-10-07): the bone's CFrame in joint2's space, rotation part only.
local WING_REST = {
	wingL = CFrame.new(0, 0, 0, 0, -1, 0, -4.37113883e-08, 0, 1, -1, 0, -4.37113883e-08),
	wingR = CFrame.new(0, 0, 0, 0, 1, 0, 4.37113883e-08, 0, 1, 1, 0, -4.37113883e-08),
}
local WING_SIDE = { wingL = 1, wingR = -1 } -- wingL sits on the model's +X side
local FLAP_DEGREES = 20 -- up and down from the rest pose
local FLAP_LIFT_DEGREES = 6 -- the wings rest a little raised
local FLAPS_PER_LOOP = 2

-- A wing turned `degrees` about the model's front-back axis (Z) at its hinge, tips up for +.
local function wingPose(bone: string, degrees: number): any
	local rest = WING_REST[bone]
	local turn = CFrame.Angles(0, 0, math.rad(degrees * WING_SIDE[bone]))
	-- Into joint2's frame (turned half a turn about Y), then into the bone's own.
	local inJoint2 = FLIP:Inverse() * turn * FLIP
	return rest:Inverse() * inJoint2 * rest
end

local source = roblox.deserializeModel(fs.readFile(DIR .. "BoxIdle.rbxm"))[1]
local length = 0
for _, k in source:GetChildren() do
	if k.ClassName == "Keyframe" then
		length = math.max(length, k.Time)
	end
end

-- The hover (and, with wings, the flap) as a KeyframeSequence named `name`.
local function make(name: string, wings: boolean)
	local out = Instance.new("KeyframeSequence")
	out.Name = name
	out.Loop = source.Loop
	out.Priority = source.Priority
	local count = 0
	for _, k in source:GetChildren() do
		if k.ClassName ~= "Keyframe" then
			continue
		end
		local j = find(k, "joint2")
		assert(j, "a keyframe without joint2")
		local cf = j.CFrame
		local scaled = CFrame.new(cf.Position * PACK_SCALE) * cf.Rotation
		local key = Instance.new("Keyframe")
		key.Time = k.Time
		local root = pose("RootPart", CFrame.new(), 0, key)
		local j1 = pose("joint1", CFrame.new(), 1, root)
		local j2 = pose("joint2", FLIP:Inverse() * scaled * FLIP, 1, j1)
		if wings then
			local phase = k.Time / length * FLAPS_PER_LOOP * 2 * math.pi
			local degrees = FLAP_LIFT_DEGREES + FLAP_DEGREES * math.sin(phase)
			pose("wingL", wingPose("wingL", degrees), 1, j2)
			pose("wingR", wingPose("wingR", degrees), 1, j2)
		end
		key.Parent = out
		count += 1
	end
	fs.writeFile(DIR .. name .. ".rbxm", roblox.serializeModel({ out }))
	print(("luckyblock_anims: %s, %d keyframes"):format(name, count))
end

make("LuckyBoxIdle", false)
make("LuckyWingIdle", true)
