--!strict
-- SoundMix tests: the arithmetic behind the mix.
--
-- Every one of these covers a mistake that sounds like "the audio is a bit off" and shows up
-- nowhere else: a crossfade that dips, a picker that repeats or that is not actually uniform,
-- a tier that chatters on a boundary, a fade whose speed depends on the player's frame rate.

local H = require("./harness")

local function setup()
	return H.require("SoundMix")
end

return {
	["loudness spans 0 to 1 across the range and never leaves it"] = function()
		local M = setup()
		H.near(M.loudness(10, 10, 400), 0, 1e-12, "at the floor")
		H.near(M.loudness(400, 10, 400), 1, 1e-12, "at the ceiling")
		H.near(M.loudness(4000, 10, 400), 1, 1e-12, "past the ceiling clamps")
		H.near(M.loudness(0, 10, 400), 0, 1e-12, "a standstill is silent")
		H.near(M.loudness(-5, 10, 400), 0, 1e-12, "negative is silent, not an error")
		-- The geometric midpoint sits at the halfway mark, which is the whole point of a
		-- log curve: each doubling of speed is a fixed step of volume.
		H.near(M.loudness(math.sqrt(10 * 400), 10, 400), 0.5, 1e-12, "geometric middle")
		for speed = 0, 600, 7 do
			local k = M.loudness(speed, 10, 400)
			H.expect(k >= 0 and k <= 1, ("out of range at %d in/s"):format(speed))
		end
	end,

	["loudness is monotonic, so a harder hit is never quieter"] = function()
		local M = setup()
		local previous = -1
		for speed = 0, 600, 1 do
			local k = M.loudness(speed, 10, 400)
			H.expect(k >= previous, ("went backwards at %d in/s"):format(speed))
			previous = k
		end
	end,

	["loudness uses far more of the range than dividing by a top speed"] = function()
		local M = setup()
		-- The measured spread of real ball-on-ball contacts: median about 3.6 in/s, p90
		-- about 67, the odd break contact past 500. Anything under 12 is not played.
		local speeds = { 12, 15, 20, 26, 34, 45, 60, 80, 110, 150, 200, 280, 380, 520 }
		local logDeciles, linearDeciles = {}, {}
		for _, s in speeds do
			logDeciles[math.min(math.floor(M.loudness(s, 10, 400) * 10) + 1, 10)] = true
			linearDeciles[math.min(math.floor(math.clamp(s / 200, 0, 1) * 10) + 1, 10)] = true
		end
		local function count(t): number
			local n = 0
			for _ in t do
				n += 1
			end
			return n
		end
		H.expect(
			count(logDeciles) > count(linearDeciles),
			("log used %d deciles, linear used %d"):format(count(logDeciles), count(linearDeciles))
		)
	end,

	["pick never repeats the last clip"] = function()
		local M = setup()
		for count = 2, 8 do
			for last = 1, count do
				for step = 0, 200 do
					local i = M.pick(count, last, step / 201)
					H.expect(i ~= last, ("count %d repeated %d"):format(count, last))
					H.expect(i >= 1 and i <= count, ("count %d gave %d"):format(count, i))
				end
			end
		end
	end,

	["pick is uniform over the clips it may choose"] = function()
		local M = setup()
		-- A picker that rolls over all N and nudges on a collision makes one clip twice as
		-- likely as the rest, which is audible as a favourite sample over a long session.
		local count, last = 6, 3
		local seen = table.create(count, 0)
		local trials = 60000
		for i = 0, trials - 1 do
			local k = M.pick(count, last, (i + 0.5) / trials)
			seen[k] += 1
		end
		local expected = trials / (count - 1)
		for i = 1, count do
			if i == last then
				H.expect(seen[i] == 0, "picked the last clip")
			else
				H.near(seen[i], expected, expected * 0.02, ("clip %d share"):format(i))
			end
		end
	end,

	["pick handles a single clip and a missing history"] = function()
		local M = setup()
		H.expect(M.pick(1, nil, 0.99) == 1, "one clip")
		H.expect(M.pick(1, 1, 0.5) == 1, "one clip, even as a repeat")
		local seen = {}
		for i = 0, 299 do
			seen[M.pick(4, nil, i / 300)] = true
		end
		for i = 1, 4 do
			H.expect(seen[i] == true, ("first pick never chose clip %d"):format(i))
		end
		-- A stale index from a shorter list must not throw or bias the choice.
		for i = 0, 99 do
			local k = M.pick(3, 9, i / 100)
			H.expect(k >= 1 and k <= 3, "out of range with a stale last index")
		end
	end,

	["crossfade holds constant power the whole way across"] = function()
		local M = setup()
		for step = 0, 100 do
			local t = step / 100
			local out, into = M.crossfade(t)
			H.near(out * out + into * into, 1, 1e-12, ("power at t=%.2f"):format(t))
			H.expect(out >= 0 and into >= 0, "gains must not go negative")
		end
		local a, b = M.crossfade(0)
		H.near(a, 1, 1e-12, "starts on the outgoing clip")
		H.near(b, 0, 1e-12, "incoming starts silent")
		local c, d = M.crossfade(1)
		H.near(c, 0, 1e-12, "ends silent")
		H.near(d, 1, 1e-12, "ends on the incoming clip")
		-- A LINEAR fade would dip to 0.707 power at the midpoint. This must not.
		local e, f = M.crossfade(0.5)
		H.near(e * e + f * f, 1, 1e-12, "no dip in the middle")
	end,

	["tiers do not chatter on the boundary"] = function()
		local M = setup()
		local boundaries = { 30 }
		local margin = 6
		-- Sitting exactly on the boundary keeps whatever tier it already had.
		H.expect(M.tierFor(30, boundaries, 1, margin) == 1, "held tier 1")
		H.expect(M.tierFor(30, boundaries, 2, margin) == 2, "held tier 2")
		-- It takes a clear move past the margin to change.
		H.expect(M.tierFor(35, boundaries, 1, margin) == 1, "35 is inside the margin")
		H.expect(M.tierFor(37, boundaries, 1, margin) == 2, "37 is clear of it")
		H.expect(M.tierFor(25, boundaries, 2, margin) == 2, "25 is inside the margin")
		H.expect(M.tierFor(23, boundaries, 2, margin) == 1, "23 is clear of it")
		-- A ball wobbling across the boundary must switch at most once.
		local tier = M.tierFor(10, boundaries, nil, margin)
		local switches = 0
		for i = 0, 200 do
			local speed = 30 + math.sin(i * 0.7) * 5 -- never clears the margin
			local next_ = M.tierFor(speed, boundaries, tier, margin)
			if next_ ~= tier then
				switches += 1
			end
			tier = next_
		end
		H.expect(switches <= 1, ("chattered %d times on the boundary"):format(switches))
	end,

	["tiers with no history pick straight off the speed"] = function()
		local M = setup()
		local boundaries = { 30, 90 }
		H.expect(M.tierFor(0, boundaries, nil, 6) == 1, "still")
		H.expect(M.tierFor(29, boundaries, nil, 6) == 1, "below the first")
		H.expect(M.tierFor(31, boundaries, nil, 6) == 2, "between")
		H.expect(M.tierFor(500, boundaries, nil, 6) == 3, "above the last")
		H.expect(M.tierFor(50, {}, nil, 6) == 1, "a single tier is always tier 1")
		-- Walking the speed up and back down must land on the same tiers it started with.
		local tier = 1
		for speed = 0, 200, 2 do
			tier = M.tierFor(speed, boundaries, tier, 6)
		end
		H.expect(tier == 3, "climbed to the top tier")
		for speed = 200, 0, -2 do
			tier = M.tierFor(speed, boundaries, tier, 6)
		end
		H.expect(tier == 1, "came back to the bottom tier")
	end,

	["easing takes the same wall time whatever the frame rate"] = function()
		local M = setup()
		-- 0.15s time constant, eased over a whole second: the result must not depend on
		-- whether the player is on a 30fps phone or a 144Hz monitor.
		local function after(fps: number): number
			local v = 0
			for _ = 1, fps do
				v = M.ease(v, 1, 1 / fps, 0.15)
			end
			return v
		end
		local slow, normal, fast = after(30), after(60), after(144)
		H.near(slow, normal, 1e-3, "30 vs 60 fps")
		H.near(normal, fast, 1e-3, "60 vs 144 fps")
		-- One time constant closes about 63% of the gap, by definition.
		H.near(M.ease(0, 1, 0.15, 0.15), 1 - math.exp(-1), 1e-12, "one time constant")
		H.near(M.ease(0.5, 0.5, 1 / 60, 0.15), 0.5, 1e-12, "already there")
		H.near(M.ease(0.2, 0.9, 1 / 60, 0), 0.9, 1e-12, "no smoothing snaps")
	end,

	["remaining accounts for pitch, and refuses to guess before a clip loads"] = function()
		local M = setup()
		H.near(M.remaining(2.0, 0.5, 1.0), 1.5, 1e-12, "at normal pitch")
		-- Played 1.5x faster, the same 1.5 clip-seconds are gone in 1.0 real seconds. Miss
		-- this and every crossfade starts late exactly when the balls are moving fastest.
		H.near(M.remaining(2.0, 0.5, 1.5), 1.0, 1e-12, "pitched up")
		H.near(M.remaining(2.0, 0.5, 0.5), 3.0, 1e-12, "pitched down")
		H.near(M.remaining(2.0, 2.0, 1.0), 0, 1e-12, "at the end")
		H.near(M.remaining(2.0, 3.0, 1.0), 0, 1e-12, "past the end never goes negative")
		-- TimeLength is 0 until the asset loads. Scheduling off that would fire a crossfade
		-- every frame, retriggering the clip forever.
		H.expect(M.remaining(0, 0, 1) == math.huge, "unloaded clip must not schedule")
	end,
}
