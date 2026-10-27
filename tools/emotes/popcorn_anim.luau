-- Popcorn (designer's concept v2, 2026-10-26): lounging back on the beach lounger, the bucket
-- on the belly in the left hand, the right hand digging in and flicking a messy handful at the
-- mouth, chewing, the crossed foot tapping. A lazy "this is too easy" taunt.
--
--   Intro  0.8 s, once: sits back into the lounger from standing.
--   Loop   2.4 s, looped: dig (0-0.25), lift (0.55), wind (0.8), flick at 0.92 (marker
--          "Toss": the popcorn leaves the hand), chew from 1.1 (marker "Crunch"), lower.
--
-- Built on tools/emotes/rig.luau: Popcorn = require("popcorn_anim")(Rig, env). Positions are
-- the root's space (studs; forward is -Z); arms reach their targets by IK at every sample, so the
-- hands stay on the bucket and in front of the mouth whatever the torso does.

return function(Rig, env)
	local CFrame = env.CFrame
	local Vector3 = env.Vector3
	local Enum = env.Enum
	local V = Vector3.new
	local rad = math.rad

	local function rx(d)
		return CFrame.Angles(rad(d), 0, 0)
	end

	local Popcorn = {}
	Popcorn.Loop = 2.4
	Popcorn.Intro = 0.8
	Popcorn.Fps = 20 -- samples a second; linear between them, the curves are smooth already
	Popcorn.TossAt = 0.92
	Popcorn.CrunchAt = 1.1

	-- Lying back on the sling: the LowerTorso rests just above the seat's bend (the lounger's
	-- origin is the floor under the root), the body along the 51-degree backrest.
	Popcorn.Lean = 51.3
	Popcorn.Lower = CFrame.new(0, -2.014, -0.229) * rx(Popcorn.Lean)
	-- The bucket standing on the belly near the chest, its top tipped toward the face so the
	-- right hand reaches in without stretching (the shoulders sit far back when lying down).
	Popcorn.Bucket = CFrame.new(0.2, -1.15, -0.38) * rx(25)

	-- Catmull-Rom through { t, value } points (numbers or Vector3s, times rising in
	-- [0, period)) that loop every `period` seconds.
	local function track(points, period)
		local n = #points
		local function at(k)
			local wrap = 0
			while k < 1 do
				k += n
				wrap -= period
			end
			while k > n do
				k -= n
				wrap += period
			end
			return points[k][2], points[k][1] + wrap
		end
		return function(t)
			t = t % period
			local i = 0 -- the last point at or before t (0: the previous loop's last)
			for k = 1, n do
				if points[k][1] <= t then
					i = k
				end
			end
			local p0 = at(i - 1)
			local p1, t1 = at(i)
			local p2, t2 = at(i + 1)
			local p3 = at(i + 2)
			local u = (t - t1) / (t2 - t1)
			local u2, u3 = u * u, u * u * u
			return (
				p1 * 2
				+ (p2 - p0) * u
				+ (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2
				+ (p1 * 3 - p0 - p2 * 3 + p3) * u3
			) * 0.5
		end
	end

	-- Head: looking down the body a little, tipped back to catch the toss, then chewing bobs.
	local neck = track({
		{ 0, -26 },
		{ 0.8, -24 },
		{ 0.97, -11 },
		{ 1.12, -14 },
		{ 1.3, -27 },
		{ 1.45, -21 },
		{ 1.6, -28 },
		{ 1.75, -22 },
		{ 1.9, -28 },
		{ 2.1, -24 },
	}, Popcorn.Loop)
	-- Breathing (the waist) and the crossed right foot tapping.
	local waist = track({ { 0, 0 }, { 1.2, 2 } }, Popcorn.Loop)
	local tap = track(
		{
			{ 0, 0 },
			{ 0.3, 16 },
			{ 0.6, 0 },
			{ 0.9, 16 },
			{ 1.2, 0 },
			{ 1.5, 16 },
			{ 1.8, 0 },
			{ 2.1, 16 },
		},
		Popcorn.Loop
	)

	local top = Popcorn.Bucket * V(0, 0.62, 0) -- the heap's top
	-- The right wrist's path (top: the heap, M: the mouth at rest).
	local function rightPath(M)
		return track({
			{ 0, top + V(0.05, 0.12, 0.05) }, -- in the heap
			{ 0.25, top + V(0.08, 0.03, 0.02) }, -- grab
			{ 0.55, top + V(0.8, 0.35, -0.05) }, -- lift, out to the side
			{ 0.8, M + V(0.75, -0.55, -0.25) }, -- wind, low beside the chin
			{ 0.95, M + V(0.55, -0.05, -0.45) }, -- the flick: a toss up at the mouth, not into it
			{ 1.15, M + V(0.7, -0.25, -0.5) },
			{ 1.6, top + V(0.75, 0.25, -0.1) }, -- lowering, lazy
			{ 2.0, top + V(0.2, 0.15, 0.0) },
		}, Popcorn.Loop)
	end
	-- The wrist's bend: limp while carrying, snapping up for the flick.
	local flick = track(
		{ { 0, 60 }, { 0.3, 65 }, { 0.55, 30 }, { 0.8, 50 }, { 0.95, -30 }, { 1.2, 0 }, { 2.0, 50 } },
		Popcorn.Loop
	)

	local LEFT_WRIST = Popcorn.Bucket * V(-0.58, -0.15, 0.05) -- gripping its left side

	local function base(t)
		local T = {}
		T.Root = Rig.rootFor(Popcorn.Lower)
		T.Waist = rx(waist(t))
		T.Neck = rx(neck(t))
		-- Legs out along the seat, the right one crossed over the left at the ankle.
		T.LeftHip = rx(43)
		T.LeftKnee = rx(-6)
		T.LeftAnkle = rx(-20)
		T.RightHip = rx(52) * CFrame.Angles(0, 0, rad(-21))
		T.RightKnee = rx(-12)
		T.RightAnkle = rx(-20 - tap(t))
		return T
	end

	local restMouth = Rig.point(base(0), "Head", Rig.Mouth)
	local right = rightPath(restMouth)

	--- Every joint's pose at loop time t.
	function Popcorn.pose(t)
		local T = base(t)
		local s, e = Rig.arm("Left", Rig.inTorso(T, LEFT_WRIST), V(-0.5, -1, 0.5))
		T.LeftShoulder, T.LeftElbow = s, e
		T.LeftWrist = CFrame.Angles(0, rad(-70), 0)
		s, e = Rig.arm("Right", Rig.inTorso(T, right(t)), V(0.5, -1, 0.5))
		T.RightShoulder, T.RightElbow = s, e
		T.RightWrist = rx(flick(t))
		return T
	end

	--- The bucket's place on the left hand (hand space), from the resting pose: the runtime
	--- welds it there.
	function Popcorn.bucketOnHand()
		local hand = Rig.solve(Popcorn.pose(0)).LeftHand
		return hand:ToObjectSpace(Popcorn.Bucket)
	end

	function Popcorn.loop()
		local keys = {}
		local steps = math.round(Popcorn.Loop * Popcorn.Fps)
		for i = 0, steps do
			local t = i / Popcorn.Fps
			table.insert(keys, { t = t, T = Popcorn.pose(t), ease = "Linear" })
		end
		table.insert(
			keys,
			{
				t = Popcorn.TossAt,
				T = Popcorn.pose(Popcorn.TossAt),
				ease = "Linear",
				marker = "Toss",
			}
		)
		table.insert(
			keys,
			{
				t = Popcorn.CrunchAt,
				T = Popcorn.pose(Popcorn.CrunchAt),
				ease = "Linear",
				marker = "Crunch",
			}
		)
		table.sort(keys, function(a, b)
			return a.t < b.t
		end)
		return Rig.sequence("PopcornLoop", keys, true, Enum.AnimationPriority.Action)
	end

	--- Sitting back into the lounger: the hips drop and slide back with bent knees, then the
	--- legs swing up onto the seat and the arms settle into the loop's first pose.
	function Popcorn.intro()
		local final = Popcorn.pose(0)
		local sit = {
			Root = Rig.rootFor(CFrame.new(0, -1.75, 0.25) * rx(14)),
			Waist = rx(-8),
			Neck = rx(-10),
			LeftHip = rx(78),
			LeftKnee = rx(-82),
			LeftAnkle = rx(6),
			RightHip = rx(78),
			RightKnee = rx(-82),
			RightAnkle = rx(6),
			LeftShoulder = final.LeftShoulder,
			LeftElbow = final.LeftElbow,
			LeftWrist = final.LeftWrist,
			RightShoulder = rx(25),
			RightElbow = rx(35),
		}
		local tip = {
			Root = Rig.rootFor(CFrame.new(0, -2.0, -0.12) * rx(42)),
			Waist = rx(-2),
			Neck = rx(-22),
			LeftHip = rx(55),
			LeftKnee = rx(-35),
			LeftAnkle = rx(-10),
			RightHip = rx(62) * CFrame.Angles(0, 0, rad(-12)),
			RightKnee = rx(-40),
			RightAnkle = rx(-10),
			LeftShoulder = final.LeftShoulder,
			LeftElbow = final.LeftElbow,
			LeftWrist = final.LeftWrist,
			RightShoulder = final.RightShoulder,
			RightElbow = final.RightElbow,
			RightWrist = final.RightWrist,
		}
		return Rig.sequence("PopcornIntro", {
			{
				t = 0,
				T = {
					LeftShoulder = final.LeftShoulder,
					LeftElbow = final.LeftElbow,
					LeftWrist = final.LeftWrist,
				},
			},
			{ t = 0.35, T = sit, ease = "InOut" },
			{ t = 0.6, T = tip, ease = "Out" },
			{ t = Popcorn.Intro, T = final, ease = "InOut" },
		}, false, Enum.AnimationPriority.Action)
	end

	return Popcorn
end
