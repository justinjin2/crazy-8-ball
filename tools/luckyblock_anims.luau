--!strict
-- Writes the idle animations for our own lucky block models (designer, 2026-10-07) as
-- KeyframeSequences in assets/luckyblocks/anims/.
--
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

local source = roblox.deserializeModel(fs.readFile(DIR .. "BoxIdle.rbxm"))[1]
local out = Instance.new("KeyframeSequence")
out.Name = "LuckyBoxIdle"
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
	pose("joint2", FLIP:Inverse() * scaled * FLIP, 1, j1)
	key.Parent = out
	count += 1
end

fs.writeFile(DIR .. "LuckyBoxIdle.rbxm", roblox.serializeModel({ out }))
print(("luckyblock_anims: LuckyBoxIdle, %d keyframes"):format(count))
