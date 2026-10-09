--!strict
-- The ball streak's on-screen maths (StreakMath, Config.UI.Streak): the step's punch, the
-- beat, the fire's flare, the fade and each level's size.
local H = require("./harness")
local StreakMath = H.require("StreakMath")
local C = H.require("Config").UI.Streak
local expect = H.expect
local tests = {}

function tests.levels_look_like_x1_to_x8_and_past_it_like_x8()
	expect(
		StreakMath.look(1, 8) == 1 and StreakMath.look(8, 8) == 8 and StreakMath.look(12, 8) == 8
	)
	expect(#C.Levels == 8, "one look per level, x1 to x8")
	H.near(StreakMath.size(8, 8, C.GrowPerLevel), 1 + 7 * C.GrowPerLevel, 1e-9, "x8's size")
	H.near(
		StreakMath.size(11, 8, C.GrowPerLevel),
		StreakMath.size(8, 8, C.GrowPerLevel),
		1e-9,
		"Solo past x8"
	)
end

function tests.the_step_squashes_flashes_white_punches_and_settles()
	local S = C.Step
	local first = StreakMath.punch(0, S)
	expect(first.frozen and not first.white and first.scale == 1)
	local impact = StreakMath.punch(S.SquashSeconds + S.ImpactSeconds / 2, S)
	expect(impact.white and impact.frozen and impact.scale == S.ImpactScale, "the impact frames")
	local out = StreakMath.punch(S.SquashSeconds + S.ImpactSeconds, S)
	H.near(out.scale, S.PunchScale, 1e-6, "the punch starts at PunchScale")
	expect(not out.white and not out.frozen and out.numberScale > 1 and out.numberTilt < 0)
	local done = StreakMath.punch(S.SquashSeconds + S.ImpactSeconds + S.SettleSeconds + 0.01, S)
	expect(done.scale == 1 and done.numberScale == 1 and done.numberTilt == 0, "settled")
	-- Back easing overshoots below 1 on the way, then lands on it.
	local low = math.huge
	for k = 0, 100 do
		low = math.min(
			low,
			StreakMath.punch(S.SquashSeconds + S.ImpactSeconds + S.SettleSeconds * k / 100, S).scale
		)
	end
	expect(low < 1, "the settle overshoots a little")
	H.near(StreakMath.popIn(0, S), S.InFromScale, 1e-9, "x1 pops in from InFromScale")
	H.near(StreakMath.popIn(S.InSeconds, S), 1, 1e-9, "and lands on 1")
end

function tests.the_beat_pops_then_eases_and_the_flare_settles()
	expect(StreakMath.beat(0, 1, 0.05) == 0)
	H.near(StreakMath.beat(0.1, 1, 0.05), 0.05, 1e-9, "the peak a tenth into the beat")
	expect(StreakMath.beat(0.9, 1, 0.05) < 0.005, "nearly gone by the next beat")
	expect(StreakMath.beat(0.3, 0, 0.05) == 0, "no beat")
	local F = C.Fire
	expect(StreakMath.flare(0, true, F, 0.05) == 0, "the fire lights from nothing")
	H.near(StreakMath.flare(0.05 + F.IgniteSeconds, true, F, 0.05), 1, 1e-6, "and grows in")
	expect(StreakMath.flare(0.06, false, F, 0.05) > 1.25, "a step flares it")
	expect(StreakMath.flare(2, false, F, 0.05) < 1.001, "then it settles")
end

function tests.the_end_fades_and_drops()
	local a0, d0 = StreakMath.fade(0, C.FadeSeconds)
	local a1, d1 = StreakMath.fade(C.FadeSeconds, C.FadeSeconds)
	expect(a0 == 1 and d0 == 0 and a1 == 0 and d1 == 1)
end

function tests.every_level_has_its_look_and_the_assets_are_set()
	for n, L in C.Levels do
		expect(#L.Color == 3 and L.Beat[1] > 0, "level " .. n)
		if L.Fire then
			expect(n >= 3, "fire only from x3")
			expect(
				string.match(C.Fire.Sheets[L.Fire], "^rbxassetid://%d+$") ~= nil,
				"x" .. n .. " fire sheet id"
			)
		end
		expect((L.Shake > 0) == (n >= 3), "the shake from x3")
	end
	expect(string.match(C.Burst.Image, "^rbxassetid://%d+$") ~= nil, "the burst id")
	-- The low flames: the words' top row inside the frame, with room above it for the tips.
	expect(C.Fire.TextTopPx > 0 and C.Fire.TextTopPx < C.Fire.FrameHeightPx, "the words' row")
	expect(C.HideSeconds > 0 and C.HideSeconds < C.Step.InSeconds, "a quick step aside")
	local Ui = H.require("Config").Audio.Ui
	for n = 2, 8 do
		expect(string.match(Ui["Streak" .. n].Id, "^rbxassetid://%d+$") ~= nil, "spray x" .. n)
	end
end

return tests
