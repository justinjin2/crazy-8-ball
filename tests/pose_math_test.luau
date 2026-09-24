--!strict
-- PoseMath tests: the limb solver, the slide along the cue, the stroke's timeline and the
-- poser's states. Everything the shooter's body does is built on these, and a sign error in
-- any of them shows up in Studio as an elbow bent backwards or a cue that never strikes.

local H = require("./harness")

local function setup()
	return H.require("PoseMath")
end

local function length(x: number, y: number, z: number): number
	return math.sqrt(x * x + y * y + z * z)
end

local function finite(...: number): boolean
	for _, v in { ... } do
		if v ~= v or math.abs(v) == math.huge then
			return false
		end
	end
	return true
end

return {
	["two bones reach a reachable target exactly, with the joint toward the hint"] = function()
		local PoseMath = setup()
		local l1, l2 = 1.1, 0.9
		local targets = {
			{ 1.2, -0.4, 0.3 },
			{ 0.2, 0.5, -1.4 },
			{ -0.9, -0.9, 0.1 },
			{ 0.0, -1.95, 0.0 },
			{ 0.3, 0.3, 0.3 },
		}
		local hints = { { 0, 0, 1 }, { 1, 0, 0 }, { 0.3, -0.5, 0.8 } }
		for _, t in targets do
			for _, p in hints do
				local ex, ey, ez, endx, endy, endz, reached = PoseMath.twoBone(
					1,
					2,
					3,
					1 + t[1],
					2 + t[2],
					3 + t[3],
					p[1],
					p[2],
					p[3],
					l1,
					l2,
					1
				)
				H.expect(reached, "within reach")
				H.near(endx, 1 + t[1], 1e-9, "end x")
				H.near(endy, 2 + t[2], 1e-9, "end y")
				H.near(endz, 3 + t[3], 1e-9, "end z")
				H.near(length(ex - 1, ey - 2, ez - 3), l1, 1e-9, "upper bone length")
				H.near(length(endx - ex, endy - ey, endz - ez), l2, 1e-9, "lower bone length")
				-- The joint lies on the hint's side of the reach line.
				local d = length(t[1], t[2], t[3])
				local ux, uy, uz = t[1] / d, t[2] / d, t[3] / d
				local along = p[1] * ux + p[2] * uy + p[3] * uz
				local qx, qy, qz = p[1] - ux * along, p[2] - uy * along, p[3] - uz * along
				if length(qx, qy, qz) > 1e-3 then
					local side = (ex - 1) * qx + (ey - 2) * qy + (ez - 3) * qz
					H.expect(side > 0, "the joint does not bend toward the hint")
				end
			end
		end
	end,

	["past its reach the limb stretches along the line, never further than it is long"] = function()
		local PoseMath = setup()
		local l1, l2 = 1, 1
		local previous = 0
		for i = 0, 40 do
			local far = 1.5 + i * 0.1
			local _, _, _, endx, endy, endz, reached =
				PoseMath.twoBone(0, 0, 0, far, 0, 0, 0, 1, 0, l1, l2, 0.9)
			H.near(endy, 0, 1e-12, "on the line")
			H.near(endz, 0, 1e-12, "on the line")
			H.expect(endx < l1 + l2, "never longer than the limb")
			H.expect(endx >= previous, "moves out as the target does")
			H.expect(reached == (far <= (l1 + l2) * (1 - 1e-4)), "reached flag")
			previous = endx
		end
		-- The soft zone starts easing at soft * reach and joins the hard limit smoothly.
		local soft = 0.9
		local start = soft * 2 * (1 - 1e-4)
		local _, _, _, atStart = PoseMath.twoBone(0, 0, 0, start, 0, 0, 0, 1, 0, 1, 1, soft)
		H.near(atStart, start, 1e-9, "exact up to the soft start")
		local _, _, _, justPast = PoseMath.twoBone(0, 0, 0, start + 1e-4, 0, 0, 0, 1, 0, 1, 1, soft)
		H.expect(justPast > start and justPast < start + 1e-4, "eases, no jump")
	end,

	["no NaN with a hint along the reach, no hint, or no distance at all"] = function()
		local PoseMath = setup()
		local cases = {
			{ { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 0 } }, -- hint parallel to the reach
			{ { 0, 0, 0 }, { 0, 1.5, 0 }, { 0, -3, 0 } }, -- hint anti-parallel
			{ { 0, 0, 0 }, { 1, 1, 0 }, { 0, 0, 0 } }, -- no hint
			{ { 1, 1, 1 }, { 1, 1, 1 }, { 0, 0, 1 } }, -- target on the shoulder
			{ { 1, 1, 1 }, { 1, 1, 1 }, { 0, 0, 0 } }, -- and no hint either
			{ { 0, 0, 0 }, { 5, 0, 0 }, { 5, 0, 0 } }, -- far away, hint along
		}
		for i, case in cases do
			local sp, tp, hp = case[1], case[2], case[3]
			local ex, ey, ez, endx, endy, endz = PoseMath.twoBone(
				sp[1],
				sp[2],
				sp[3],
				tp[1],
				tp[2],
				tp[3],
				hp[1],
				hp[2],
				hp[3],
				1,
				0.8,
				0.95
			)
			H.expect(finite(ex, ey, ez, endx, endy, endz), ("case %d gave a NaN"):format(i))
			H.near(length(ex - sp[1], ey - sp[2], ez - sp[3]), 1, 1e-9, "bone length kept")
			H.near(length(endx - ex, endy - ey, endz - ez), 0.8, 1e-9, "bone length kept")
		end
	end,

	["lineSphere finds the touching point nearest the preference, within the window"] = function()
		local PoseMath = setup()
		-- A line along +x through the origin, a sphere of radius 2 about (3, 1, 0): roots at
		-- x = 3 - sqrt(3) and 3 + sqrt(3).
		local r3 = math.sqrt(3)
		local t, exact = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 1, 0, 2, 0, -10, 10)
		H.near(t, 3 - r3, 1e-12, "the near root")
		H.expect(exact, "exact")
		t, exact = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 1, 0, 2, 6, -10, 10)
		H.near(t, 3 + r3, 1e-12, "the far root")
		H.expect(exact, "exact")
		-- The nearer root out of the window, the other in it.
		t, exact = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 1, 0, 2, 0, 2, 10)
		H.near(t, 3 + r3, 1e-12, "the root in the window")
		H.expect(exact, "exact")
		-- Neither root in the window: clamped, not exact.
		t, exact = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 1, 0, 2, 0, 1.5, 4)
		H.near(t, 1.5, 1e-12, "clamped toward the nearer root")
		H.expect(not exact, "not exact")
		-- A direction that is not unit length measures t in its own steps.
		t = PoseMath.lineSphere(0, 0, 0, 2, 0, 0, 3, 1, 0, 2, 0, -10, 10)
		H.near(t, (3 - r3) / 2, 1e-12, "scaled direction")
		-- Out of reach altogether: the closest approach, clamped.
		t, exact = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 5, 0, 2, 0, -10, 10)
		H.near(t, 3, 1e-12, "closest approach")
		H.expect(not exact, "not exact")
		t = PoseMath.lineSphere(0, 0, 0, 1, 0, 0, 3, 5, 0, 2, 0, -10, 2.5)
		H.near(t, 2.5, 1e-12, "closest approach, clamped")
		-- No direction: the preference, clamped.
		t, exact = PoseMath.lineSphere(0, 0, 0, 0, 0, 0, 3, 1, 0, 2, 7, -1, 5)
		H.near(t, 5, 1e-12, "no direction")
		H.expect(not exact, "not exact")
	end,

	["the stroke accelerates in, rests on the ball, follows through, then ends"] = function()
		local PoseMath = setup()
		local from, strokeSec, follow, followSec, hold, wait = 0.8, 0.1, 0.35, 0.08, 0.25, 1.5
		local function at(t: number, movingAt: number?): (number, boolean)
			return PoseMath.strokeGap(t, from, strokeSec, movingAt, follow, followSec, hold, wait)
		end
		H.near((at(0, nil)), from, 1e-12, "starts where the wind-up was")
		-- Accelerating: each step covers more than the last.
		local last, lastStep = from, 0
		for i = 1, 10 do
			local gap = at(i * strokeSec / 10, nil)
			local step = last - gap
			H.expect(step > lastStep - 1e-12, "accelerates")
			last, lastStep = gap, step
		end
		H.near(last, 0, 1e-12, "reaches the ball at strokeSec")
		-- The local shooter: resting on the ball until the replay moves it.
		local gap, done = at(0.5, nil)
		H.expect(gap == 0 and not done, "rests on the ball")
		gap, done = at(strokeSec + wait, nil)
		H.expect(gap == 0 and done, "gives up waiting")
		-- The ball moves at 0.4: follow-through from then on, easing out.
		gap = at(0.4, 0.4)
		H.near(gap, 0, 1e-12, "follow-through starts at contact")
		local mid = at(0.4 + followSec / 2, 0.4)
		H.expect(mid < 0 and mid > -follow, "past the ball, not yet all the way")
		gap, done = at(0.4 + followSec, 0.4)
		H.near(gap, -follow, 1e-12, "all the way through")
		H.expect(not done, "then holds")
		gap, done = at(0.4 + followSec + hold + 1e-9, 0.4)
		H.expect(gap == -follow and done, "and ends")
		-- A watcher strikes after the replay has started: the follow-through waits for contact.
		gap = at(0.05, 0)
		H.expect(gap > 0, "still coming in")
		gap = at(strokeSec + 0.01, 0)
		H.expect(gap < 0 and gap > -follow, "through straight after contact")
		-- A movingAt from the future never pushes the tip back off the ball.
		gap = at(0.3, 0.5)
		H.expect(gap == 0, "holds at the ball until the replay moves")
	end,

	["the poser's states"] = function()
		local PoseMath = setup()
		-- { state, want, strokeDone, expected }
		local rows: { { any } } = {
			{ "rest", "aim", false, "aim" },
			{ "idle", "aim", false, "aim" },
			{ "aim", "aim", false, "aim" },
			{ "aim", "strike", false, "stroke" },
			{ "rest", "strike", false, "rest" },
			{ "idle", "strike", false, "idle" },
			{ "stroke", "aim", false, "stroke" },
			{ "stroke", "idle", false, "stroke" },
			{ "stroke", "strike", false, "stroke" },
			{ "stroke", "idle", true, "idle" },
			{ "stroke", "aim", true, "idle" },
			{ "stroke", "cancel", false, "aim" },
			{ "stroke", "rest", false, "rest" },
			{ "aim", "idle", false, "idle" },
			{ "rest", "idle", false, "rest" },
			{ "idle", "idle", false, "idle" },
			{ "aim", "rest", false, "rest" },
			{ "idle", "rest", false, "rest" },
			{ "aim", "cancel", false, "aim" },
			{ "idle", "cancel", false, "idle" },
		}
		for _, row in rows do
			local got = PoseMath.transition(row[1], row[2], row[3])
			H.expect(
				got == row[4],
				("%s + %s (%s) -> %s, expected %s"):format(
					row[1],
					row[2],
					tostring(row[3]),
					got,
					row[4]
				)
			)
		end
	end,

	["smoothing is frame-rate independent"] = function()
		local PoseMath = setup()
		H.expect(PoseMath.alpha(0, 0.12) == 0, "no time, no move")
		H.near(PoseMath.alpha(1e6, 0.12), 1, 1e-12, "long enough, all the way")
		-- Two half frames move exactly as far as one whole frame.
		local half = PoseMath.alpha(1 / 120, 0.12)
		H.near(1 - (1 - half) * (1 - half), PoseMath.alpha(1 / 60, 0.12), 1e-12, "composes")
		H.expect(PoseMath.alpha(1 / 60, 0) <= 1, "a zero time constant still behaves")
	end,
}
