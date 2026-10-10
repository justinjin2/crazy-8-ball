--!strict
-- PullMath (src/shared/PullMath.luau): the Mythic and Secret pull cutscenes' timing. A wrong
-- warp is bullet time that jumps, a heartbeat that slows when it should race, lights that die
-- in the wrong order; none of it shows up anywhere but on screen.

local H = require("./harness")

local function setup()
	return H.require("PullMath")
end

return {
	["the warped clock is real time outside the window and slower inside it"] = function()
		local M = setup()
		H.near(M.warp(1, 2, 4, 0.1, 0.2), 1, 1e-12, "before the window")
		H.near(M.warp(2, 2, 4, 0.1, 0.2), 2, 1e-12, "at its start")
		local inside = M.warp(3, 2, 4, 0.1, 0.2)
		H.expect(inside > 2 and inside < 2.4, "a second inside moves the world a little")
		-- After the window the world is behind real time by exactly what the slow part
		-- swallowed: the hold (1.6 s at 0.1) and the two ramps (0.2 s each, averaging 0.55).
		local lost = 1.6 * 0.9 + 2 * 0.2 * 0.45
		H.near(M.warp(5, 2, 4, 0.1, 0.2), 5 - lost, 1e-9, "after it, behind by what it swallowed")
	end,

	["the warped clock never runs backwards or jumps"] = function()
		local M = setup()
		local previous = -math.huge
		for i = 0, 800 do
			local t = i / 100
			local w = M.warp(t, 2, 4, 0.06, 0.15)
			H.expect(w >= previous - 1e-12, "it only moves forward")
			if i > 0 then
				local step = w - previous
				H.expect(step <= 0.01 + 1e-9, "never faster than real time")
				H.expect(step >= 0.06 * 0.01 - 1e-9, "never slower than the slow speed")
			end
			previous = w
		end
	end,

	["the warped clock's speed matches its slope"] = function()
		local M = setup()
		for _, t in { 1.9, 2.05, 2.1, 3, 3.9, 3.95, 4.1 } do
			local h = 1e-5
			local slope = (M.warp(t + h, 2, 4, 0.1, 0.2) - M.warp(t - h, 2, 4, 0.1, 0.2)) / (2 * h)
			H.near(slope, M.warpSpeed(t, 2, 4, 0.1, 0.2), 1e-4, "slope at " .. t)
		end
	end,

	["a racing heartbeat's gaps shrink from the first to the last"] = function()
		local M = setup()
		local beats = M.beats(10, 15, 0.9, 0.3)
		H.near(beats[1], 10, 1e-12, "the first beat is at the start")
		H.expect(beats[#beats] <= 15 + 1e-9, "none after the end")
		H.expect(#beats >= 8, "a race, not a few beats")
		for i = 3, #beats do
			local gap = beats[i] - beats[i - 1]
			local before = beats[i - 1] - beats[i - 2]
			H.expect(gap <= before + 1e-9, "each gap is no longer than the one before")
		end
		H.near(beats[2] - beats[1], 0.9, 1e-9, "the first gap")
	end,

	["the lights die from the far end, faster as the dark comes closer"] = function()
		local M = setup()
		local times = M.lightsOut(8, 7.5, 9.5, 1.8)
		H.expect(#times == 8, "one time per light")
		H.near(times[1], 7.5, 1e-12, "the farthest first")
		H.near(times[8], 9.5, 1e-12, "the nearest last")
		for i = 3, 8 do
			H.expect(times[i] - times[i - 1] <= times[i - 1] - times[i - 2] + 1e-9, "gaps shrink")
		end
		H.near(M.lightsOut(1, 7.5, 9.5, 1.8)[1], 9.5, 1e-12, "a single light dies at the end")
	end,

	["a dolly zoom widens as the camera closes in, within its limits"] = function()
		local M = setup()
		H.near(M.dollyFov(100, 100, 30, 20, 110), 30, 1e-9, "the start keeps its angle")
		local closer = M.dollyFov(50, 100, 30, 20, 110)
		H.expect(closer > 30, "closer is wider")
		H.near(
			math.tan(math.rad(closer) / 2) * 50,
			math.tan(math.rad(30) / 2) * 100,
			1e-9,
			"same size"
		)
		H.near(M.dollyFov(1, 100, 30, 20, 110), 110, 1e-9, "never wider than the most")
		H.near(M.dollyFov(1e6, 100, 30, 20, 110), 20, 1e-9, "never narrower than the least")
	end,

	["a homing flight starts slow and arrives at 1"] = function()
		local M = setup()
		H.near(M.homing(0, 2), 0, 1e-12, "starts at 0")
		H.near(M.homing(1, 2), 1, 1e-12, "arrives at 1")
		H.expect(M.homing(0.5, 2) < 0.5, "slow at first")
		H.near(M.homing(2, 2), 1, 1e-12, "clamped past the end")
	end,

	["a glitch is the same at the same moment and on about as often as asked"] = function()
		local M = setup()
		H.expect(M.glitchOn(3.21, 0.05, 0.3, 7) == M.glitchOn(3.21, 0.05, 0.3, 7), "repeatable")
		local on = 0
		for i = 0, 1999 do
			if M.glitchOn(i * 0.05 + 0.01, 0.05, 0.3, 7) then
				on += 1
			end
		end
		H.expect(on > 2000 * 0.22 and on < 2000 * 0.38, "about 30% of the slots: " .. on)
		for i = 0, 200 do
			local h = M.hash(i, 3)
			H.expect(h >= 0 and h < 1, "a hash is in 0..1")
		end
	end,
}
