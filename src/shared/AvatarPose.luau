--!strict
-- AvatarPose: puts an R15 character behind the cue ball in an aiming stance, entirely in
-- code (no animation assets). Joint rotations come from Config.Avatar.Pose. Instead of
-- driving the joints, every body part's CFrame is computed directly from the root through
-- the joint chain (forward kinematics) and written with the parts anchored. That works for
-- classic Motor6D rigs, for the newer AnimationConstraint rigs, and in Studio's edit mode,
-- and nothing (animations, physics) can fight it.
-- Shared so the Studio preview can pose a test rig with exactly the game's code.

local Config = require(script.Parent.Config)
local Placement = require(script.Parent.Placement)

local AvatarPose = {}

type Joint = { name: string, part0: BasePart, part1: BasePart, off0: CFrame, off1: CFrame }

-- Weak keys: a character that has left must not be kept alive by this cache. With 30 players
-- respawning all session a strong table would hold every character ever posed.
local jointCache: { [Model]: { joints: { Joint }, count: number } } = setmetatable(
	{},
	{ __mode = "k" }
) :: any

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

-- Half extents of the table including rails, in INCHES along the table's own axes: the
-- first along the length (physics x), the second across the width (physics y).
local function tableHalfExtents(): (number, number)
	local T = Config.Table
	return T.LengthInches / 2 + T.RailWidthInches, T.WidthInches / 2 + T.RailWidthInches
end

--- Where the character stands for a shot from the cue ball (world) along `dir` at table `p`,
--- and how much it has to stretch over the table (0 = normal stance, 1 = full stretch).
--- If the natural spot behind the ball is over the table, the character stands at the
--- rail on the far side instead and reaches in.
---
--- The rim test is done in the TABLE's own axes, not world X/Z: the lounge stands every
--- table at yaw 90, where a world-axis-aligned box would put the shooter inside the table.
function AvatarPose.standing(
	character: Model,
	p: Placement.Placement,
	cueWorld: Vector3,
	dir: Vector3
): (CFrame, number, number)
	local A = Config.Avatar
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	local hip = if humanoid then humanoid.HipHeight else 2
	local rootHalf = if root and root:IsA("BasePart") then root.Size.Y / 2 else 1
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	local right = flat:Cross(Vector3.yAxis)

	local natural = cueWorld - flat * A.StandBackStuds
	-- Push the stand point back along the aim line until it clears the table rim, all in
	-- table space and inches. `back` is a distance along a line, so converting it to studs
	-- at the end is the only scaling needed.
	local hx, hy = tableHalfExtents()
	local relX, relY = Placement.toTable(p, natural.X, natural.Z)
	local flatX, flatY = Placement.dirToTable(p, flat.X, flat.Z)
	local stand = natural
	local overhang = 0
	if math.abs(relX) < hx and math.abs(relY) < hy then
		-- Where walking back along -flat leaves the table. A ray starting inside a box
		-- always exits somewhere, and this has to find that exit rather than only the
		-- nearest rim: with the cue ball near a cushion and the shot going INTO it,
		-- walking back goes DEEPER and leaves by the far rail. The old version only
		-- tested the near rim, found nothing, and left the shooter stood on the cloth -
		-- which is the "player is on top of the table" everyone could see.
		local bx, by = -flatX, -flatY -- the direction we walk while backing off
		local function exitAt(rel: number, comp: number, half: number): number
			if math.abs(comp) < 1e-6 then
				return math.huge -- never crosses this pair of rails
			end
			return ((if comp > 0 then half else -half) - rel) / comp
		end
		local back = math.min(exitAt(relX, bx, hx), exitAt(relY, by, hy))
		if back == math.huge or back < 0 then
			back = 0
		end
		back *= Config.Table.StudsPerInch
		stand = natural - flat * back
		overhang = back
	end
	stand = stand + right * A.SideOffsetStuds
	-- The floor the table stands on, which is the tier height in the lounge.
	local pos = Vector3.new(stand.X, p.y + hip + rootHalf, stand.Z)
	local stretch = math.clamp(overhang / math.max(A.StretchBlendStuds, 1e-3), 0, 1)
	-- The raw reach in studs comes back too: how far past a normal stance the shooter is
	-- having to get to the ball is what decides whether they are worth drawing at all.
	return CFrame.lookAt(pos, pos + flat), stretch, overhang
end

--- Root CFrame only (kept for callers that do not need the stretch amount).
function AvatarPose.rootCFrame(
	character: Model,
	p: Placement.Placement,
	cueWorld: Vector3,
	dir: Vector3
): CFrame
	local cf = AvatarPose.standing(character, p, cueWorld, dir)
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
