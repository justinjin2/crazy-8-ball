--!strict
-- AvatarPose: puts an R15 character behind the cue ball in an aiming stance, entirely in
-- code (no animation assets). Joint rotations come from Config.Avatar.Pose. Instead of
-- driving the joints, every body part's CFrame is computed directly from the root through
-- the joint chain (forward kinematics) and written with the parts anchored. That works for
-- classic Motor6D rigs, for the newer AnimationConstraint rigs, and in Studio's edit mode,
-- and nothing (animations, physics) can fight it.
-- Shared so the Studio preview can pose a test rig with exactly the game's code.

local Config = require(script.Parent.Config)

local AvatarPose = {}

type Joint = { name: string, part0: BasePart, part1: BasePart, off0: CFrame, off1: CFrame }

local jointCache: { [Model]: { joints: { Joint }, count: number } } = {}

local function angles(deg: { number }): CFrame
	return CFrame.Angles(math.rad(deg[1]), math.rad(deg[2]), math.rad(deg[3]))
end

local function collectJoints(character: Model): { Joint }
	local joints: { Joint } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(
				joints,
				{ name = d.Name, part0 = d.Part0, part1 = d.Part1, off0 = d.C0, off1 = d.C1 }
			)
		elseif d:IsA("AnimationConstraint") and d.Attachment0 and d.Attachment1 then
			local a0, a1 = d.Attachment0 :: Attachment, d.Attachment1 :: Attachment
			local p0, p1 = a0.Parent, a1.Parent
			if p0 and p0:IsA("BasePart") and p1 and p1:IsA("BasePart") then
				table.insert(
					joints,
					{ name = d.Name, part0 = p0, part1 = p1, off0 = a0.CFrame, off1 = a1.CFrame }
				)
			end
		end
	end
	return joints
end

local function jointsOf(character: Model): { Joint }
	local count = #character:GetDescendants()
	local cached = jointCache[character]
	if cached and cached.count == count then
		return cached.joints
	end
	local joints = collectJoints(character)
	jointCache[character] = { joints = joints, count = count }
	return joints
end

-- Half extents of the table including rails, in studs.
local function tableHalfExtents(): (number, number)
	local T = Config.Table
	local s = T.StudsPerInch
	return (T.LengthInches / 2 + T.RailWidthInches) * s, (T.WidthInches / 2 + T.RailWidthInches) * s
end

--- Where the character stands for a shot from the cue ball (world) along `dir`, and how
--- much it has to stretch over the table (0 = normal stance, 1 = full stretch).
--- If the natural spot behind the ball is over the table, the character stands at the
--- rail on the far side instead and reaches in.
function AvatarPose.standing(character: Model, cueWorld: Vector3, dir: Vector3): (CFrame, number)
	local A = Config.Avatar
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hip = if humanoid then humanoid.HipHeight else 2
	local rootHalf = if root and root:IsA("BasePart") then root.Size.Y / 2 else 1
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local right = flat:Cross(Vector3.yAxis)
	local o = Config.World.TableOrigin
	local origin = Vector3.new(o.X, o.Y, o.Z)

	local natural = cueWorld - flat * A.StandBackStuds
	-- Push the stand point back along the aim line until it clears the table rim.
	local hx, hz = tableHalfExtents()
	local stand = natural
	local overhang = 0
	local rel = natural - origin
	if math.abs(rel.X) < hx and math.abs(rel.Z) < hz then
		-- Distance to walk back until |X| or |Z| reaches the rim (whichever comes first
		-- along -flat).
		local tx = if math.abs(flat.X) > 1e-6
			then (hx - math.abs(rel.X)) / math.abs(flat.X)
			else math.huge
		local tz = if math.abs(flat.Z) > 1e-6
			then (hz - math.abs(rel.Z)) / math.abs(flat.Z)
			else math.huge
		-- Only the components that move outward count: walking back along -flat moves X by
		-- -flat.X, so it approaches the rim on the side rel.X and -flat.X agree on.
		local back = math.min(
			if rel.X * -flat.X > 0 then tx else math.huge,
			if rel.Z * -flat.Z > 0 then tz else math.huge
		)
		if back == math.huge then
			back = 0
		end
		stand = natural - flat * back
		overhang = back
	end
	stand = stand + right * A.SideOffsetStuds
	local pos = Vector3.new(stand.X, o.Y + hip + rootHalf, stand.Z)
	local stretch = math.clamp(overhang / math.max(A.StretchBlendStuds, 1e-3), 0, 1)
	return CFrame.lookAt(pos, pos + flat), stretch
end

--- Root CFrame only (kept for callers that do not need the stretch amount).
function AvatarPose.rootCFrame(character: Model, cueWorld: Vector3, dir: Vector3): CFrame
	local cf = AvatarPose.standing(character, cueWorld, dir)
	return cf
end

local function lerpAngles(a: { number }?, b: { number }?, t: number): CFrame
	if not a and not b then
		return CFrame.identity
	end
	local ca = if a then angles(a) else CFrame.identity
	local cb = if b then angles(b) else CFrame.identity
	return ca:Lerp(cb, t)
end

--- Place the whole character: root at `rootCFrame`, every limb in the aiming pose blended
--- towards the stretch pose by `stretch` (0..1). Call every frame while aiming. Anchors the
--- parts it moves.
function AvatarPose.apply(character: Model, rootCFrame: CFrame, stretch: number?)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local pose = Config.Avatar.Pose :: { [string]: { number } }
	local stretchPose = Config.Avatar.StretchPose :: { [string]: { number } }
	local blend = stretch or 0
	root.Anchored = true
	root.CFrame = rootCFrame

	local joints = jointsOf(character)
	local placed: { [BasePart]: boolean } = { [root] = true }
	local remaining = #joints
	local passes = 0
	while remaining > 0 and passes < 8 do
		passes += 1
		for _, j in joints do
			if not placed[j.part1] and placed[j.part0] then
				local deg, degStretch = pose[j.name], stretchPose[j.name]
				local rot = if deg or degStretch
					then lerpAngles(deg, degStretch, blend)
					else CFrame.identity
				j.part1.Anchored = true
				j.part1.CFrame = j.part0.CFrame * j.off0 * rot * j.off1:Inverse()
				placed[j.part1] = true
				remaining -= 1
			end
		end
	end
end

--- Fade every visible piece of the character. With `hideAccessories`, hats and other
--- accessories disappear entirely so they cannot cover the table.
function AvatarPose.setTransparency(
	character: Model,
	transparency: number,
	hideAccessories: boolean?
)
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local inAccessory = d:FindFirstAncestorOfClass("Accessory") ~= nil
			d.LocalTransparencyModifier = if inAccessory and hideAccessories
				then 1
				else transparency
		elseif d:IsA("Decal") then
			d.Transparency = transparency
		end
	end
end

return AvatarPose
