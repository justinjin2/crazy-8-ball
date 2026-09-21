--!strict
-- SoundMix: the maths behind the sound mix, with no Instances in sight.
--
-- This lives in shared and stays pure for one reason: every hard part of making a table
-- sound right is arithmetic that is easy to get subtly wrong and impossible to eyeball in
-- Studio. A crossfade that dips in the middle, a clip picker that can repeat, a volume
-- curve that puts every shot in the bottom tenth of its range - all of those sound like
-- "the audio is a bit off" and none of them show up in a screenshot. Here they are Lune
-- tests instead.
--
-- Nothing in here touches math.random: the caller passes a roll in [0, 1). That keeps the
-- picker testable and keeps the decision about randomness at the edge, where it belongs.

local SoundMix = {}

-- A clip may declare the speed band it suits. Both ends are optional: no FromSpeed means
-- "however gently", no UpToSpeed means "however hard".
export type Band = {
	FromSpeed: number?,
	UpToSpeed: number?,
}

-- The volume and pitch band one kind of contact plays across, plus an optional speed range
-- of its own when the shared one does not suit it.
export type Range = {
	MinVolume: number,
	MaxVolume: number,
	MinPitch: number,
	MaxPitch: number,
	QuietSpeed: number?,
	LoudSpeed: number?,
	-- Bands with few recordings to choose between lean harder on pitch wobble.
	PitchJitter: number?,
}

--- Impact speed (or ball speed) to a 0..1 level, on a LOGARITHMIC curve.
---
--- Linear was the obvious first choice and it was wrong. Measured over 48 shots, the median
--- ball-on-ball contact in this game is 3.6 in/s and the 90th percentile is 66.8, while a
--- break peaks past 500 - so dividing by a "full volume speed" of 200 put 49% of audible
--- contacts in the bottom fifth of the volume range and left the table sounding timid at
--- every power. Loudness is perceived logarithmically, so mapping the SPEED RATIO onto the
--- range is what spreads shots across it: the same measurement puts 8 of 10 volume deciles
--- in real use instead of 5.
---
--- `lo` is the quietest speed worth hearing and maps to 0; `hi` maps to 1.
function SoundMix.loudness(speed: number, lo: number, hi: number): number
	if speed <= lo then
		return 0
	end
	if hi <= lo then
		return 1
	end
	return math.clamp(math.log(speed / lo) / math.log(hi / lo), 0, 1)
end

function SoundMix.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Volume and pitch for one contact at `speed`, from its band.
---
--- Pitch runs DOWNWARD with force on purpose: the harder contact gets the LOWER pitch, which
--- is what makes it read as heavier. It looks like a bug every time somebody reads it, so it
--- lives here with a test pinning the direction rather than inline at the call site.
---
--- `lo` and `hi` are the shared speed range; a band may override either. The cue strike does,
--- because the cue ball leaves at up to 528 in/s and the shared range tops out at 400, which
--- left the top of the power bar sounding identical at every setting.
function SoundMix.mix(range: Range, speed: number, lo: number, hi: number): (number, number)
	local k = SoundMix.loudness(speed, range.QuietSpeed or lo, range.LoudSpeed or hi)
	return SoundMix.lerp(range.MinVolume, range.MaxVolume, k),
		SoundMix.lerp(range.MaxPitch, range.MinPitch, k)
end

--- Pick a clip, never the same one twice running.
---
--- This matters more than any amount of pitch variation. The ear spots exact repetition
--- instantly, and a break makes over a hundred ball contacts, so one clack sample becomes a
--- machine gun however cleverly it is pitched.
---
--- `roll` is a uniform number in [0, 1). When `last` is given, the choice is uniform over
--- the OTHER clips - not "pick at random and nudge if it collided", which would quietly
--- make the neighbour of the last clip twice as likely as everything else.
function SoundMix.pick(count: number, last: number?, roll: number): number
	if count <= 1 then
		return 1
	end
	local r = math.clamp(roll, 0, 0.9999999)
	if last == nil or last < 1 or last > count then
		return math.floor(r * count) + 1
	end
	local i = math.floor(r * (count - 1)) + 1
	if i >= last then
		i += 1
	end
	return i
end

local function inBand(band: Band, speed: number): boolean
	return (band.FromSpeed == nil or speed >= band.FromSpeed)
		and (band.UpToSpeed == nil or speed <= band.UpToSpeed)
end

--- Pick a clip that suits this impact speed, never the same one twice running.
---
--- A soft cushion contact and a hard one are genuinely different sounds, not the same sound
--- at two volumes, so picking purely at random would play a hard thud for a gentle kiss. The
--- bands are allowed to OVERLAP, and where they do the choice is random between them - which
--- blends one recording into the other across a stretch of speeds instead of switching at an
--- audible line that a player would learn to hear.
---
--- If a speed falls in no band at all the whole list is eligible, so a gap left by a typo in
--- Config makes the event a bit random rather than silent.
function SoundMix.pickBanded(bands: { Band }, speed: number, last: number?, roll: number): number
	local n = #bands
	if n <= 1 then
		return 1
	end

	local count = 0
	for _, band in bands do
		if inBand(band, speed) then
			count += 1
		end
	end
	local useAll = count == 0
	if useAll then
		count = n
	end

	-- Drop the previous clip from the running, but only while something else is eligible.
	local skip: number? = nil
	if
		last ~= nil
		and last >= 1
		and last <= n
		and count > 1
		and (useAll or inBand(bands[last], speed))
	then
		skip = last
		count -= 1
	end

	local target = math.floor(math.clamp(roll, 0, 0.9999999) * count) + 1
	local seen = 0
	for i, band in bands do
		if (useAll or inBand(band, speed)) and i ~= skip then
			seen += 1
			if seen == target then
				return i
			end
		end
	end
	return if skip == 1 then math.min(2, n) else 1
end

--- Equal-power crossfade gains at `t` in 0..1: (outgoing, incoming).
---
--- Equal POWER, not equal amplitude. Two uncorrelated recordings of rolling noise sum in
--- power, not in amplitude, so fading one down linearly while the other comes up linearly
--- leaves an audible dip in the middle - the thing a crossfade exists to prevent. The
--- sine/cosine pair keeps out^2 + in^2 at 1 the whole way across.
function SoundMix.crossfade(t: number): (number, number)
	local k = math.clamp(t, 0, 1) * (math.pi / 2)
	return math.cos(k), math.sin(k)
end

--- Which speed tier a ball is in, with hysteresis so it cannot chatter.
---
--- `boundaries` is ascending; tier 1 is below boundaries[1], tier 2 between the first two,
--- and so on. A ball sitting exactly on a boundary would otherwise flip tier every frame
--- and retrigger the rolling clip each time, which is a machine-gun of its own.
function SoundMix.tierFor(
	speed: number,
	boundaries: { number },
	current: number?,
	margin: number
): number
	local n = #boundaries + 1
	if n == 1 then
		return 1
	end
	local from = if current and current >= 1 and current <= n then current else nil
	if from == nil then
		local tier = n
		for i, b in boundaries do
			if speed < b then
				tier = i
				break
			end
		end
		return tier
	end
	-- Only move once the speed is clear of the boundary by `margin`.
	if from < n and speed > boundaries[from] + margin then
		return from + 1
	end
	if from > 1 and speed < boundaries[from - 1] - margin then
		return from - 1
	end
	return from
end

--- Move `current` toward `target` at a rate that does not depend on the frame rate.
---
--- The naive version multiplies by a fixed fraction each frame, which makes a sound fade
--- twice as fast at 120fps as at 60 - so the mix quietly changes with the player's device.
--- `tau` is the time constant in seconds: after `tau` the gap has closed by about 63%.
function SoundMix.ease(current: number, target: number, dt: number, tau: number): number
	if tau <= 0 or dt <= 0 then
		return target
	end
	local alpha = 1 - math.exp(-dt / tau)
	return current + (target - current) * alpha
end

--- Real seconds of audio left in a clip, accounting for pitch.
---
--- Sound.TimePosition advances in CLIP seconds, so a clip played at 1.2x has its remaining
--- clip-seconds consumed 1.2x faster. Scheduling a crossfade off the unscaled remainder
--- starts the next clip late at high pitch and early at low pitch, which is exactly when a
--- ball is moving fast and the gap is most obvious.
function SoundMix.remaining(timeLength: number, timePosition: number, playbackSpeed: number): number
	if timeLength <= 0 then
		return math.huge -- not loaded yet; never schedule off a length we do not have
	end
	return math.max(timeLength - timePosition, 0) / math.max(playbackSpeed, 1e-3)
end

return SoundMix
