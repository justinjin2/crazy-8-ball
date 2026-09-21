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
		-- Strictly INSIDE the range, so a curve that was constant, reversed or clamped flat
		-- would fail this rather than sail through a >= 0 and <= 1 check.
		for speed = 11, 399, 7 do
			local k = M.loudness(speed, 10, 400)
			H.expect(
				k > 0 and k < 1,
				("%d in/s should be inside the range, got %.4f"):format(speed, k)
			)
		end
		-- An inverted range is a caller error; it must saturate rather than produce a curve
		-- that runs backwards. The floor is still checked first, so only a speed ABOVE lo
		-- reaches that branch at all.
		H.near(M.loudness(500, 400, 10), 1, 1e-12, "inverted range saturates above the floor")
		H.near(M.loudness(50, 400, 10), 0, 1e-12, "and is still silent below it")
		H.near(M.loudness(200, 200, 200), 0, 1e-12, "a zero-width range is silent at its floor")
		H.near(M.loudness(201, 200, 200), 1, 1e-12, "and saturates one step above it")
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

	["lerp hits both ends and extrapolates past them"] = function()
		local M = setup()
		H.near(M.lerp(2, 4, 0), 2, 1e-12, "at zero")
		H.near(M.lerp(2, 4, 1), 4, 1e-12, "at one")
		H.near(M.lerp(2, 4, 0.5), 3, 1e-12, "halfway")
		-- It must NOT clamp. loudness is clamped upstream, but a future caller may not be,
		-- and a silently clamping lerp would hide that.
		H.near(M.lerp(2, 4, 2), 6, 1e-12, "extrapolates above")
		H.near(M.lerp(2, 4, -1), 0, 1e-12, "extrapolates below")
	end,

	["mix runs volume up with force and pitch DOWN with it"] = function()
		local M = setup()
		local band = { MinVolume = 0.2, MaxVolume = 1.0, MinPitch = 0.9, MaxPitch = 1.14 }
		local softVolume, softPitch = M.mix(band, 12, 10, 400)
		local hardVolume, hardPitch = M.mix(band, 500, 10, 400)
		-- The inversion is deliberate: the harder contact gets the LOWER pitch, which is what
		-- makes it read as heavier. It looks like a bug on sight, so it is pinned here.
		H.expect(hardVolume > softVolume, "a harder contact must be louder")
		H.expect(hardPitch < softPitch, "a harder contact must be LOWER pitched, not higher")
		H.near(hardVolume, band.MaxVolume, 1e-12, "the top of the range is reached")
		H.near(hardPitch, band.MinPitch, 1e-12, "and so is the bottom of the pitch range")
		local restVolume, restPitch = M.mix(band, 0, 10, 400)
		H.near(restVolume, band.MinVolume, 1e-12, "a standstill sits at the floor")
		H.near(restPitch, band.MaxPitch, 1e-12, "and at the top pitch")
	end,

	["a band may override the shared speed range"] = function()
		local M = setup()
		-- The cue strike does this: the cue ball leaves at up to 528 in/s, so on the shared
		-- 10..400 range everything from about 93% power upwards sounded identical.
		local band = { MinVolume = 0.35, MaxVolume = 1.0, MinPitch = 0.95, MaxPitch = 1.1 }
		local wide = {
			MinVolume = 0.35,
			MaxVolume = 1.0,
			MinPitch = 0.95,
			MaxPitch = 1.1,
			QuietSpeed = 15,
			LoudSpeed = 528,
		}
		local sharedAt450 = M.mix(band, 450, 10, 400)
		local sharedAt528 = M.mix(band, 528, 10, 400)
		H.near(sharedAt450, sharedAt528, 1e-12, "the shared range is flat above 400")
		local wideAt450 = M.mix(wide, 450, 10, 400)
		local wideAt528 = M.mix(wide, 528, 10, 400)
		H.expect(wideAt528 > wideAt450, "its own range keeps climbing to the top of the bar")
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

	["a banded pick respects the speed band, and blends where bands overlap"] = function()
		local M = setup()
		-- The real cushion setup: a soft take up to 70 in/s, a hard one from 40, so they
		-- overlap between 40 and 70.
		local rails = {
			{ FromSpeed = 0, UpToSpeed = 70 },
			{ FromSpeed = 40, UpToSpeed = math.huge },
		}
		-- Well below the overlap: only the soft take, whatever the roll.
		for step = 0, 50 do
			H.expect(M.pickBanded(rails, 20, nil, step / 51) == 1, "a gentle kiss must be soft")
		end
		-- Well above it: only the hard one.
		for step = 0, 50 do
			H.expect(M.pickBanded(rails, 150, nil, step / 51) == 2, "a hard thud must be hard")
		end
		-- Inside the overlap both are reachable, which is what blends one into the other
		-- instead of switching at a line a player would learn to hear.
		local seen = { false, false }
		for step = 0, 200 do
			seen[M.pickBanded(rails, 55, nil, step / 201)] = true
		end
		H.expect(seen[1] and seen[2], "the overlap must be able to choose either take")
	end,

	["a banded pick never repeats, and never goes silent on a gap"] = function()
		local M = setup()
		local rails = {
			{ FromSpeed = 0, UpToSpeed = 70 },
			{ FromSpeed = 40, UpToSpeed = math.huge },
		}
		-- In the overlap, with a previous clip, it must choose the other one.
		for step = 0, 100 do
			H.expect(M.pickBanded(rails, 55, 1, step / 101) == 2, "should have moved off clip 1")
			H.expect(M.pickBanded(rails, 55, 2, step / 101) == 1, "should have moved off clip 2")
		end
		-- OUTSIDE the overlap only one clip is eligible, so repeating it is correct: playing
		-- the wrong-sounding take would be worse than repeating the right one.
		H.expect(M.pickBanded(rails, 20, 1, 0.5) == 1, "one eligible clip may repeat")
		H.expect(M.pickBanded(rails, 150, 2, 0.5) == 2, "one eligible clip may repeat")

		-- A gap in the bands (a typo in Config) must make the event a bit random, never mute.
		local gapped = {
			{ FromSpeed = 0, UpToSpeed = 10 },
			{ FromSpeed = 200, UpToSpeed = math.huge },
		}
		local hit = { false, false }
		for step = 0, 100 do
			local i = M.pickBanded(gapped, 60, nil, step / 101)
			H.expect(i == 1 or i == 2, "a speed in no band must still pick something")
			hit[i] = true
		end
		H.expect(hit[1] and hit[2], "the fallback should use the whole list")

		-- Unbanded lists behave exactly like the plain picker.
		local plain = { {}, {}, {} }
		for step = 0, 100 do
			local i = M.pickBanded(plain, 37, 2, step / 101)
			H.expect(i ~= 2, "an unbanded list must still not repeat")
		end
		H.expect(M.pickBanded({ {} }, 5, 1, 0.9) == 1, "a single clip is always clip 1")
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
		-- A LINEAR fade would dip to 0.707 power at the midpoint. This must not - and pin the
		-- gains themselves, not just their power sum, which a pair like (1, 0) would satisfy.
		local e, f = M.crossfade(0.5)
		H.near(e, math.sqrt(0.5), 1e-12, "outgoing at the midpoint")
		H.near(f, math.sqrt(0.5), 1e-12, "incoming at the midpoint")
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
