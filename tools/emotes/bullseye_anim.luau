-- Bullseye (designer's concept v2, 2026-10-26): a bow pops into the left hand and a target a few
-- steps ahead; the player turns side-on, raises the bow, draws to the chin, holds, looses the
-- arrow dead into the centre, then lowers the bow and blows on its top limb like a smoking gun.
-- One shot, 3.6 s:
--
--   0-0.3     turn side-on, the bow low, nocking         (props pop in at 0)
--   0.3-0.75  raise the bow at the target
--   0.75-1.45 draw to the chin
--   1.45-1.9  aim, a tiny tremble
--   1.9       marker "Release": the arrow leaves (it flies in code: Config, ~0.2 s)
--   2.35-2.75 lower the bow, turn back to the front
--   2.75      marker "Blow": the puff at the bow's top limb; a hand on the hip
--   3.25      marker "Poof": bow, target and arrow vanish
--   3.6       rest
--
-- Built on tools/emotes/rig.luau: Bullseye = require("bullseye_anim")(Rig, env). Positions are
-- the root's space (studs; forward -Z, the target's way); arms reach by IK at every sample.

return function(Rig, env)
	local CFrame = env.CFrame
	local Vector3 = env.Vector3
	local Enum = env.Enum
	local V = Vector3.new
	local rad = math.rad

	local Bullseye = {}
	Bullseye.Length = 3.6
	Bullseye.Fps = 30
	Bullseye.ReleaseAt = 1.9
	Bullseye.BlowAt = 2.75
	Bullseye.PoofAt = 3.25

	-- The aim: the arrow lies level along -Z at this height and side (root space), from the
	-- drawing hand at the chin to the bow hand; the target's centre sits on the same line.
	local AIM_X, AIM_Y = 0.08, 1.1
	local GRIP = V(AIM_X, AIM_Y, -2.5) -- the bow hand's wrist at full draw
	local ANCHOR = V(AIM_X + 0.05, AIM_Y + 0.05, 0.12) -- the drawing hand's wrist under the chin

	local function ease(name, u)
		if name == "Linear" then
			return u
		elseif name == "Out" then
			return 1 - (1 - u) ^ 3
		elseif name == "In" then
			return u ^ 3
		end
		return if u < 0.5 then 4 * u ^ 3 else 1 - (-2 * u + 2) ^ 3 / 2
	end

	-- Beats: { t, fields, ease (into this beat) }. Every beat names every field; a field is a
	-- number or a Vector3, eased from the beat before.
	local function beats(list)
		return function(t)
			if t <= list[1][1] then
				return list[1][2]
			end
			for i = 2, #list do
				local b = list[i]
				if t <= b[1] then
					local a = list[i - 1]
					local u = ease(b[3], (t - a[1]) / (b[1] - a[1]))
					local out = {}
					for k, v in a[2] do
						out[k] = v + (b[2][k] - v) * u
					end
					return out
				end
			end
			return list[#list][2]
		end
	end

	-- Shared beat values.
	local REST = {
		yaw = 0,
		waist = 0,
		neckYaw = 0,
		neckPitch = 0,
		stance = 0,
		knee = 0,
		left = V(-1.0, -0.55, -0.35),
		leftElbow = V(-1, -0.3, 0.6),
		right = V(1.0, -0.55, -0.35),
		rightElbow = V(1, -0.3, 0.6),
		fingers = 0,
		bowTurn = 0,
	}
	local function with(base, changes)
		local out = table.clone(base)
		for k, v in changes do
			out[k] = v
		end
		return out
	end
	local NOCK = with(REST, {
		yaw = -80,
		waist = 4,
		neckYaw = 70,
		neckPitch = -18,
		stance = 9,
		knee = 6,
		left = V(0.0, 0.05, -1.55),
		leftElbow = V(-0.3, -1, 0.2),
		right = V(0.1, 0.25, -1.2),
		rightElbow = V(0.6, -0.6, 0.6),
	})
	local RAISE = with(NOCK, {
		neckYaw = 78,
		neckPitch = -6,
		left = GRIP + V(0, 0.02, 0.15),
		leftElbow = V(-0.4, -1, 0.3),
		right = GRIP + V(0.03, 0.05, 0.55),
		rightElbow = V(0.5, -0.5, 0.8),
	})
	local DRAW = with(RAISE, {
		neckPitch = -9,
		left = GRIP,
		right = ANCHOR,
		rightElbow = V(0.3, -0.1, 1),
	})
	local AIM1 =
		with(DRAW, { left = GRIP + V(0.012, 0.01, 0), right = ANCHOR + V(-0.01, 0.008, 0.01) })
	local AIM2 =
		with(DRAW, { left = GRIP + V(-0.008, -0.012, 0), right = ANCHOR + V(0.01, -0.01, 0) })
	local LOOSE = with(DRAW, {
		right = ANCHOR + V(0.18, 0.12, 0.62),
		rightElbow = V(0.6, 0.05, 1),
		fingers = -25,
	})
	local BLOW = with(REST, {
		yaw = -30,
		waist = 6,
		neckYaw = 14,
		neckPitch = -14,
		stance = 7,
		knee = 4,
		left = V(-0.35, -0.2, -0.85),
		leftElbow = V(-1, -0.6, 0.1),
		right = V(1.05, -0.62, 0.15),
		rightElbow = V(1, 0.1, 0.4),
		bowTurn = 1,
	})

	local track = beats({
		{ 0, REST },
		{ 0.3, NOCK, "Out" },
		{ 0.75, RAISE, "InOut" },
		{ 1.45, DRAW, "InOut" },
		{ 1.6, AIM1, "InOut" },
		{ 1.75, AIM2, "InOut" },
		{ 1.88, DRAW, "InOut" },
		{ 1.98, LOOSE, "Out" },
		{ 2.35, LOOSE, "Linear" },
		{ 2.75, BLOW, "InOut" },
		{ 2.95, with(BLOW, { neckPitch = -18 }), "InOut" },
		{ 3.15, BLOW, "InOut" },
		{ 3.6, REST, "InOut" },
	})

	local function body(b)
		local T = {}
		T.Root = Rig.rootFor(CFrame.new(0, -0.8, 0) * CFrame.Angles(0, rad(b.yaw), 0))
		T.Waist = CFrame.Angles(0, rad(b.waist), 0)
		T.Neck = CFrame.Angles(0, rad(b.neckYaw), 0) * CFrame.Angles(rad(b.neckPitch), 0, 0)
		T.RightHip = CFrame.Angles(rad(b.knee * 0.5), 0, rad(b.stance))
		T.LeftHip = CFrame.Angles(rad(b.knee * 0.5), 0, rad(-b.stance))
		T.RightKnee = CFrame.Angles(rad(-b.knee), 0, 0)
		T.LeftKnee = CFrame.Angles(rad(-b.knee), 0, 0)
		T.RightAnkle = CFrame.Angles(rad(b.knee * 0.5), 0, 0)
		T.LeftAnkle = CFrame.Angles(rad(b.knee * 0.5), 0, 0)
		return T
	end

	local function arms(T, b)
		local s, e = Rig.arm("Left", Rig.inTorso(T, b.left), Rig.dirInTorso(T, b.leftElbow))
		T.LeftShoulder, T.LeftElbow = s, e
		s, e = Rig.arm("Right", Rig.inTorso(T, b.right), Rig.dirInTorso(T, b.rightElbow))
		T.RightShoulder, T.RightElbow = s, e
		T.RightWrist = CFrame.Angles(rad(b.fingers), 0, 0)
		return T
	end

	-- The bow on the left hand: upright at full draw with its string toward the archer (the
	-- model's own axes), its grip in the fist.
	local drawT = arms(body(DRAW), DRAW)
	local drawParts = Rig.solve(drawT)
	Bullseye.BowOnHand = drawParts.LeftHand:ToObjectSpace(CFrame.new(drawParts.LeftHand.Position))
	-- Blowing: the bow upright beside the face, turned to show its curve to the front.
	local BOW_BLOW = CFrame.Angles(0, rad(-75), 0)

	--- Every joint's pose at time t.
	function Bullseye.pose(t)
		local b = track(t)
		local T = arms(body(b), b)
		local hold = Rig.wristFor(T, "Left", BOW_BLOW * Bullseye.BowOnHand.Rotation:Inverse())
		T.LeftWrist = CFrame.new():Lerp(hold, math.clamp(b.bowTurn, 0, 1))
		return T
	end

	--- The arrow's line at the release (root space): from the drawing hand to the bow hand.
	function Bullseye.aim()
		local parts = Rig.solve(Bullseye.pose(Bullseye.ReleaseAt - 0.02))
		return parts.RightHand.Position, parts.LeftHand.Position
	end

	--- The bow's place on the left hand (hand space), for Config: the runtime welds it there.
	function Bullseye.bowOnHand()
		return Bullseye.BowOnHand
	end

	function Bullseye.shot()
		local keys = {}
		local steps = math.round(Bullseye.Length * Bullseye.Fps)
		for i = 0, steps do
			local t = i / Bullseye.Fps
			table.insert(keys, { t = t, T = Bullseye.pose(t), ease = "Linear" })
		end
		for name, at in
			{ Release = Bullseye.ReleaseAt, Blow = Bullseye.BlowAt, Poof = Bullseye.PoofAt }
		do
			table.insert(keys, { t = at, T = Bullseye.pose(at), ease = "Linear", marker = name })
		end
		table.sort(keys, function(a, b)
			return a.t < b.t
		end)
		return Rig.sequence("BullseyeShot", keys, false, Enum.AnimationPriority.Action)
	end

	return Bullseye
end
