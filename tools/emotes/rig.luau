-- The R15 body the custom emotes are posed on (Popcorn, Bullseye), and the maths to pose it.
-- Shared by the Lune writer (tools/emotes/make_emote_anims.luau) and the Studio preview
-- (the same source pasted into an Edit-mode run), so it takes its datatypes from `env`
-- instead of globals: Rig = require("rig")({ CFrame = ..., Vector3 = ..., Instance = ..., Enum = ... }).
--
-- Rest frames: a default body from Players:CreateHumanoidModelFromDescription (R15, every scale
-- 1), read in Studio on 2026-10-26. Every joint's rest rotation is the identity, so a joint is
-- just where it sits on its parent (C0) and on its child (C1). A child part is
--   parent * CFrame.new(C0) * T * CFrame.new(C1):Inverse()
-- where T is the pose a KeyframeSequence stores under the child's name. Studs; the body faces
-- -Z, +X is its right, +Y up; everything is in the HumanoidRootPart's space.

return function(env)
	local CFrame = env.CFrame
	local Vector3 = env.Vector3
	local Instance = env.Instance
	local Enum = env.Enum

	local Rig = {}

	local function v(x, y, z)
		return Vector3.new(x, y, z)
	end

	-- { joint, parent part, child part, C0, C1 }, parents before children.
	Rig.Joints = {
		{ "Root", "HumanoidRootPart", "LowerTorso", v(0, -1, 0), v(0, -0.2, 0) },
		{ "Waist", "LowerTorso", "UpperTorso", v(0, 0.2, 0), v(0, -0.849, 0) },
		{ "Neck", "UpperTorso", "Head", v(0, 0.849, 0), v(0, -0.5758, 0) },
		{
			"RightShoulder",
			"UpperTorso",
			"RightUpperArm",
			v(0.9716, 0.5975, 0),
			v(-0.5005, 0.4189, 0),
		},
		{ "RightElbow", "RightUpperArm", "RightLowerArm", v(0, -0.355, 0), v(0, 0.2748, 0) },
		{ "RightWrist", "RightLowerArm", "RightHand", v(0, -0.5322, 0), v(0, 0.1316, 0) },
		{
			"LeftShoulder",
			"UpperTorso",
			"LeftUpperArm",
			v(-0.9716, 0.5975, 0),
			v(0.5005, 0.4189, 0),
		},
		{ "LeftElbow", "LeftUpperArm", "LeftLowerArm", v(0, -0.355, 0), v(0, 0.2748, 0) },
		{ "LeftWrist", "LeftLowerArm", "LeftHand", v(0, -0.5322, 0), v(0, 0.1316, 0) },
		{ "RightHip", "LowerTorso", "RightUpperLeg", v(0.5, -0.2, 0), v(0, 0.4714, 0) },
		{ "RightKnee", "RightUpperLeg", "RightLowerLeg", v(0, -0.4493, 0), v(0, 0.4132, 0) },
		{ "RightAnkle", "RightLowerLeg", "RightFoot", v(0, -0.5965, 0), v(0, 0.106, 0) },
		{ "LeftHip", "LowerTorso", "LeftUpperLeg", v(-0.5, -0.2, 0), v(0, 0.4714, 0) },
		{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg", v(0, -0.4493, 0), v(0, 0.4132, 0) },
		{ "LeftAnkle", "LeftLowerLeg", "LeftFoot", v(0, -0.5965, 0), v(0, 0.106, 0) },
	}
	local byName = {}
	for _, j in Rig.Joints do
		byName[j[1]] = j
	end
	Rig.ByName = byName

	-- The floor under the root: the Humanoid's HipHeight (2.1924) and half the root's height.
	Rig.Ground = -3.1924
	-- The mouth on the head (head space): the face's front, a little under the middle.
	Rig.Mouth = v(0, -0.22, -0.58)

	--- Every part's CFrame in the root's space for joint poses T (a missing joint rests).
	function Rig.solve(T)
		local parts = { HumanoidRootPart = CFrame.new() }
		for _, j in Rig.Joints do
			local t = T[j[1]] or CFrame.new()
			parts[j[3]] = parts[j[2]] * CFrame.new(j[4]) * t * CFrame.new(j[5]):Inverse()
		end
		return parts
	end

	--- The Root pose that puts the LowerTorso at `lower` (the root's space).
	function Rig.rootFor(lower)
		local j = byName.Root
		return CFrame.new(j[4]):Inverse() * lower * CFrame.new(j[5])
	end

	local function frame(a, b)
		-- An orthonormal frame (as a rotation) whose -Y is `a` and whose YZ plane holds `b`.
		local y = -a.Unit
		local z = (b - y * b:Dot(y))
		z = -z.Unit
		local x = y:Cross(z)
		return CFrame.fromMatrix(Vector3.new(), x, y, z)
	end

	--- An arm reaching its wrist to `wrist` (the UpperTorso's space), the elbow pointing toward
	--- `elbowDir` (a direction; e.g. down and out for a lazy arm).
	--- Returns the shoulder's and the elbow's poses. The upper arm hangs off its shoulder joint
	--- on a slant (the joint sits at the part's inner top), which the solve keeps.
	function Rig.arm(side: string, wrist, elbowDir)
		local sh = byName[side .. "Shoulder"]
		local el = byName[side .. "Elbow"]
		local wr = byName[side .. "Wrist"]
		local S = sh[4]
		-- The upper bone at rest (part space), shoulder joint to elbow joint, and its length.
		local upperRest = el[4] - sh[5]
		local l1 = upperRest.Magnitude
		local l2 = (wr[4] - el[5]).Magnitude
		local d = wrist - S
		local dist = math.clamp(d.Magnitude, math.abs(l1 - l2) + 1e-3, (l1 + l2) - 1e-3)
		local u = d.Unit
		local q = elbowDir - u * elbowDir:Dot(u)
		if q.Magnitude < 1e-6 then
			q = u:Cross(Vector3.new(1, 0, 0))
		end
		q = q.Unit
		local cosA = math.clamp((l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist), -1, 1)
		local E = S + u * (l1 * cosA) + q * (l1 * math.sqrt(1 - cosA * cosA))
		local W = S + u * dist
		local upperDir = (E - S).Unit
		local foreDir = (W - E).Unit
		-- The elbow's bend: the forearm's -Y swings toward the upper arm's -Z by angle e, and
		-- the slanted upper bone makes the straight-arm angle a little more than zero.
		local c = upperDir:Dot(foreDir)
		local k = -upperRest.Unit.Y -- cos of the angle between the upper bone and the part's -Y
		local e = math.acos(math.clamp(c / k, -1, 1))
		local foreRest = Vector3.new(0, -math.cos(e), -math.sin(e))
		local R = frame(upperDir, foreDir) * frame(upperRest, foreRest):Inverse()
		return R.Rotation, CFrame.Angles(e, 0, 0)
	end

	--- Where a point fixed to a part lands (the root's space) for poses T.
	function Rig.point(T, part: string, offset)
		return Rig.solve(T)[part] * offset
	end

	--- A world (root space) point in the UpperTorso's space, for arm targets.
	function Rig.inTorso(T, p)
		return Rig.solve(T).UpperTorso:PointToObjectSpace(p)
	end

	--- A world (root space) direction in the UpperTorso's space, for elbow hints.
	function Rig.dirInTorso(T, d)
		return Rig.solve(T).UpperTorso:VectorToObjectSpace(d)
	end

	--- The wrist pose that turns a hand to `rotation` (root space) once its arm is posed in T,
	--- so a held prop keeps the angle a beat needs (a bow upright, a bucket level).
	function Rig.wristFor(T, side: string, rotation)
		local lower = Rig.solve(T)[side .. "LowerArm"]
		return lower.Rotation:Inverse() * rotation.Rotation
	end

	-- Easing names to Roblox's pose easings.
	local function easing(name)
		if name == "Linear" then
			return Enum.PoseEasingStyle.Linear, Enum.PoseEasingDirection.In
		elseif name == "Out" then
			return Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.Out
		elseif name == "In" then
			return Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.In
		end
		return Enum.PoseEasingStyle.Cubic, Enum.PoseEasingDirection.InOut
	end

	--- A KeyframeSequence from keys { t, T = { joint = CFrame }, ease = "InOut"|"Out"|"In"|"Linear",
	--- marker = "Name"? }. Every key poses every joint (a missing one rests), so no joint drifts
	--- between keys.
	function Rig.sequence(name: string, keys, loop: boolean, priority)
		local kfs = Instance.new("KeyframeSequence")
		kfs.Name = name
		kfs.Loop = loop
		kfs.Priority = priority
		for _, key in keys do
			local kf = Instance.new("Keyframe")
			kf.Time = key.t
			local style, dir = easing(key.ease)
			local poses = {}
			local root = Instance.new("Pose")
			root.Name = "HumanoidRootPart"
			root.Weight = 0
			root.Parent = kf
			poses.HumanoidRootPart = root
			for _, j in Rig.Joints do
				local p = Instance.new("Pose")
				p.Name = j[3]
				p.CFrame = key.T[j[1]] or CFrame.new()
				p.Weight = 1
				p.EasingStyle = style
				p.EasingDirection = dir
				p.Parent = poses[j[2]]
				poses[j[3]] = p
			end
			if key.marker then
				local m = Instance.new("KeyframeMarker")
				m.Name = key.marker
				m.Parent = kf
			end
			kf.Parent = kfs
		end
		return kfs
	end

	return Rig
end
