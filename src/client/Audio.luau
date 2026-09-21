--!strict
-- Audio: turns simulation events into sound.
--
-- It listens to a Match rather than watching the balls, so what you hear is exactly what the
-- physics said happened, at the moment it happened, with the impact speed already worked
-- out. Volume and pitch come off that speed, so a firm break sounds like one and a gentle
-- kiss sounds like one.
--
-- Three things keep a break from turning to mush. A single break makes well over a hundred
-- ball contacts (121 in one measured shot), so anything under Config.Audio.MinClackSpeed or
-- MinRailSpeed is dropped; the rest are held apart by a minimum gap per contact type; and
-- each event picks from several recordings, banded by speed, so the survivors neither sound
-- identical nor play a hard thud for a gentle touch.
--
-- All of the arithmetic lives in SoundMix, which is pure and Lune-tested. What is left here
-- is the Roblox side: instances, pooling and the crossfade bookkeeping.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Ball = require(Shared:WaitForChild("Physics"):WaitForChild("Ball"))
local Simulation = require(Shared:WaitForChild("Physics"):WaitForChild("Simulation"))
local SoundMix = require(Shared:WaitForChild("SoundMix"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

type Event = Simulation.Event

-- One recording, the measured correction that levels it against the others, and optionally
-- the band of impact speeds it suits (see SoundMix.pickBanded).
type Clip = { Id: string, Gain: number, FromSpeed: number?, UpToSpeed: number? }

-- One reusable emitter. Impacts happen all over the table so each needs its own position,
-- but the instances themselves are recycled.
--
-- The emitter is an Attachment rather than a Part. Both work, but a Part-parented Sound is
-- affected by SoundService.VolumetricAudio - a place-level setting anyone could flip in
-- Studio - while an Attachment is a point source whatever that is set to. It also means one
-- anchored part carries every voice instead of one part per voice.
type Voice = {
	attachment: Attachment,
	sound: Sound,
	busy: boolean,
	startedAt: number,
}

-- One side of the rolling crossfade.
type RollVoice = {
	sound: Sound,
	gain: number,
	level: number, -- 0..1 crossfade position, before the table volume is applied
}

-- The tension under a cue being drawn back. Not positional: it belongs to the control in
-- your hand, not to a place on the table.
type Pull = {
	sound: Sound,
	active: boolean,
	volume: number,
}

type Roll = {
	attachment: Attachment,
	voices: { RollVoice },
	front: number,
	incoming: number?,
	fadeStart: number,
	fadeLength: number,
	tier: number?,
	lastClip: { [number]: number },
	volume: number,
	pitch: number,
}

local Audio = {}
Audio.__index = Audio

export type Audio = typeof(setmetatable(
	{} :: {
		folder: Folder,
		anchor: BasePart,
		pool: { Voice },
		lastClack: number,
		lastRail: number,
		-- A tumbling window counting how many hard contacts have been allowed to stack.
		stackStart: number,
		stacked: number,
		-- Which clip each event played last, so the next pick is never the same one.
		lastPick: { [string]: number },
		roll: Roll?,
		pull: Pull?,
	},
	Audio
))

---------------------------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------------------------

-- Every voice hangs off this one part, so the emitters cost no physics and no rendering.
local function newAnchor(parent: Instance): BasePart
	local part = Instance.new("Part")
	part.Name = "Emitters"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Position = Vector3.zero
	part.Parent = parent
	return part
end

local function newAttachment(anchor: BasePart, name: string): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Parent = anchor
	return attachment
end

local function newSound(parent: Instance, name: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.Volume = 0
	sound.RollOffMinDistance = Config.Audio.RollOffMinStuds
	sound.RollOffMaxDistance = Config.Audio.RollOffMaxStuds
	sound.RollOffMode = (Enum.RollOffMode :: any)[Config.Audio.RollOffMode]
	-- A Sound with this set re-plays itself when its parent is removed, ignoring distance
	-- attenuation entirely. It defaults off; set explicitly so recycling a voice can never
	-- fire a clip at full volume from the wrong place.
	sound.PlayOnRemove = false
	sound.Parent = parent
	return sound
end

--- Pull every clip into the cache up front.
---
--- Without this the first contact of the session is silent: a Sound told to play an asset it
--- has not fetched yet simply does not, and the break is exactly when the most sounds fire.
local function preload(folder: Instance)
	local holder = Instance.new("Folder")
	holder.Name = "Preload"
	holder.Parent = folder

	local queue: { Instance } = {}
	local function add(id: string)
		if id == "" then
			return
		end
		local s = Instance.new("Sound")
		s.SoundId = id
		s.Parent = holder
		table.insert(queue, s)
	end
	for _, clips in Config.Audio.Clips :: any do
		for _, clip in clips do
			add(clip.Id)
		end
	end
	for _, tier in Config.Audio.Roll.Tiers :: any do
		for _, clip in tier do
			add(clip.Id)
		end
	end
	add(Config.Audio.Pull.Id)

	-- A moderated, deleted or wrong id is otherwise completely silent, and looks exactly
	-- like a logic bug.
	local failures = ContentProvider.AssetFetchFailed:Connect(function(id: string)
		warn(("[8ball] audio failed to load: %s"):format(id))
	end)

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(queue)
		end)
		holder:Destroy()
		task.delay(10, function()
			failures:Disconnect()
		end)
	end)
end

function Audio.new(parent: Instance): Audio
	local folder = Instance.new("Folder")
	folder.Name = "Audio"
	folder.Parent = parent
	preload(folder)

	-- Doppler is global, not per sound, and it fights every pitch this module sets. See
	-- Config.Audio.DopplerScale.
	SoundService.DopplerScale = Config.Audio.DopplerScale

	local self = setmetatable({
		folder = folder,
		anchor = newAnchor(folder),
		pool = {},
		lastClack = 0,
		lastRail = 0,
		stackStart = 0,
		stacked = 0,
		lastPick = {},
		roll = nil,
		pull = nil,
	}, Audio)

	return self
end

---------------------------------------------------------------------------------------------
-- One-shots
---------------------------------------------------------------------------------------------

--- Pick a clip for this event, never the same one twice running.
---
--- Randomness here is purely cosmetic and client-side, so math.random is fine; the ban on it
--- lives in Physics and Rules, where determinism matters.
local function pickClip(self: Audio, name: string, speed: number): Clip?
	local clips = (Config.Audio.Clips :: any)[name] :: { Clip }?
	if clips == nil or #clips == 0 then
		return nil
	end
	local i = SoundMix.pickBanded(clips :: any, speed, self.lastPick[name], math.random())
	self.lastPick[name] = i
	return clips[i]
end

--- Take an emitter from the pool, growing it up to the cap.
---
--- `force` is for pocket drops: a ball dropping is the payoff of the whole shot and must
--- never be lost to a wall of clacks, so it takes the oldest voice rather than being dropped.
local function acquire(self: Audio, force: boolean): Voice?
	local oldest: Voice? = nil
	for _, voice in self.pool do
		if not voice.busy then
			return voice
		end
		if oldest == nil or voice.startedAt < oldest.startedAt then
			oldest = voice
		end
	end
	if #self.pool < Config.Audio.MaxVoices then
		local attachment = newAttachment(self.anchor, "Emitter")
		local voice: Voice = {
			attachment = attachment,
			sound = newSound(attachment, "Impact"),
			busy = false,
			startedAt = 0,
		}
		table.insert(self.pool, voice)
		return voice
	end
	if force and oldest then
		oldest.sound:Stop()
		return oldest
	end
	return nil
end

--- Whether a hard contact may sound ON TOP of the ones around it rather than waiting for the
--- gap. A break lands most of its hardest contacts inside a tenth of a second, and letting
--- them overlap is what makes it one crack instead of a queue of clicks - but it needs a
--- ceiling, or a pile-up would spend every voice at once.
local function canStack(self: Audio, now: number): boolean
	local A = Config.Audio
	if now - self.stackStart > A.StackWindowSeconds then
		self.stackStart = now
		self.stacked = 0
	end
	if self.stacked >= A.MaxStackedClacks then
		return false
	end
	self.stacked += 1
	return true
end

-- Impact speed to the volume and pitch this event should play at. See SoundMix.mix.
local function mix(range: any, speed: number): (number, number)
	local A = Config.Audio
	return SoundMix.mix(range, speed, A.QuietSpeed, A.LoudSpeed)
end

--- Play one clip at a world position. Sounds are emitted from where the contact happened, so
--- a break spreads across the table instead of arriving from a single point.
function Audio.playAt(
	self: Audio,
	name: string,
	at: Vector3,
	range: any,
	speed: number,
	force: boolean?
)
	-- The speed decides which recording, not just how loud it plays: some clips declare the
	-- band of impact speeds they suit (see Config.Audio.Clips.RailThud).
	local clip = pickClip(self, name, speed)
	if clip == nil or clip.Id == "" then
		return -- no recording wired up for this one yet
	end
	local volume, pitch = mix(range, speed)
	local voice = acquire(self, force == true)
	if voice == nil then
		return -- every voice is busy; dropping this one beats cutting another one off
	end

	-- A little wobble on top of the speed-driven pitch, so two identical impacts still
	-- differ from each other. A band may ask for more of it when it has fewer recordings to
	-- choose between, which is the only disguise left to it.
	local wobble = range.PitchJitter or Config.Audio.PitchJitter
	local jitter = 1 + (math.random() * 2 - 1) * wobble

	voice.busy = true
	voice.startedAt = os.clock()
	voice.attachment.WorldPosition = at

	local sound = voice.sound
	-- Stop() is what rewinds a pooled Sound: Play() resumes from the last position a script
	-- set, and writing TimePosition directly makes the engine re-buffer, which is audible.
	sound:Stop()
	sound.SoundId = clip.Id
	-- Gain levels the recordings against each other so the random choice does not decide how
	-- loud the hit is; speed does.
	sound.Volume = math.clamp(volume * clip.Gain, 0, Config.Audio.MaxVolume)
	sound.PlaybackSpeed = math.max(pitch * jitter, 0.05)
	sound:Play()

	local token = voice.startedAt
	local function release()
		-- Only the play that started this one may free it: a voice stolen for a pocket drop
		-- has already been handed on, and freeing it here would let two sounds share it.
		if voice.startedAt == token then
			voice.busy = false
		end
	end
	sound.Ended:Once(release)
	sound.Stopped:Once(release)
	-- Ended does not always arrive (a clip that fails to load never plays at all), so nothing
	-- may hold a voice for longer than the clip it is playing. TimeLength reads 0 until the
	-- asset is cached, so fall back to the LONGEST clip in the set rather than to something
	-- shorter than the one now playing - which would free this voice mid-drop and let the
	-- next contact cut it off.
	local length = if sound.TimeLength > 0
		then sound.TimeLength
		else Config.Audio.LongestClipSeconds
	task.delay(length / math.max(sound.PlaybackSpeed, 0.05) + 0.5, release)
end

--- Listen to a table. Every contact the simulation reports becomes a sound.
function Audio.attach(self: Audio, match: any)
	match:onEvent(function(ev: Event)
		local A = Config.Audio
		local now = os.clock()

		-- Where did it happen? The event names a ball; ask the table where that ball is.
		local ball = Simulation.findBall(match.state, ev.ball)
		local at = if ball
			then TableBuilder.toWorld(
				match.placement,
				ball.x,
				ball.y,
				Config.Balls.RadiusInches + ball.z
			)
			else TableBuilder.toWorld(match.placement, 0, 0, 0)

		if ev.type == "cueStrike" then
			self:playAt("CueStrike", at, A.Strike, ev.speed)
		elseif ev.type == "pocket" then
			-- Always audible: a ball dropping is the payoff and must never be rate limited
			-- away behind a wall of clacks, so it skips the gaps and forces a voice.
			self:playAt("PocketDrop", at, A.Pocket, ev.speed, true)
		elseif ev.type == "ballHit" then
			if ev.speed < A.MinClackSpeed then
				return
			end
			-- Hard contacts may stack; everything else waits its turn.
			local stacking = ev.speed >= A.StackSpeed and canStack(self, now)
			if not stacking and now - self.lastClack < A.MinSecondsBetweenClacks then
				return
			end
			self.lastClack = now
			self:playAt("BallClack", at, A.Clack, ev.speed)
		elseif ev.type == "railHit" then
			if ev.speed < A.MinRailSpeed then
				return
			end
			if now - self.lastRail < A.MinSecondsBetweenRails then
				return
			end
			self.lastRail = now
			self:playAt("RailThud", at, A.Rail, ev.speed)
		end
	end)
end

--- The soft click while the aim turns (GDD section 5: a tick every step of rotation).
function Audio.tick(self: Audio, at: Vector3)
	self:playAt("AimTick", at, Config.Audio.Tick, 0)
end

---------------------------------------------------------------------------------------------
-- Drawing the cue back
---------------------------------------------------------------------------------------------

local function buildPull(self: Audio): Pull
	local P = Config.Audio.Pull
	-- Parented to the FOLDER, not to an attachment: a Sound with no BasePart or Attachment
	-- above it plays flat and unpositioned, which is what a control in your hand should do.
	local sound = Instance.new("Sound")
	sound.Name = "PullTension"
	sound.SoundId = P.Id
	sound.Looped = false
	sound.Volume = 0
	sound.PlayOnRemove = false
	sound.Parent = self.folder

	local pull: Pull = { sound = sound, active = false, volume = 0 }
	self.pull = pull
	return pull
end

--- Drawing the cue back, or nil once it is let go.
---
--- The recording is played straight through at one volume and stopped when the pull ends.
--- It used to be scaled by how far back the cue was, and that was wrong: this is quiet
--- friction that only builds late, so scaling the start down as well made the beginning of
--- every pull - the part you hear most, because that is when your finger is moving - all but
--- silent.
---
--- Driven from the pull VALUE rather than from the control, so a gamepad trigger sounds
--- exactly like a finger.
function Audio.setPull(self: Audio, pull: number?)
	local state = self.pull or buildPull(self)
	local wanted = pull ~= nil
	if wanted == state.active then
		return -- already in the right state; a drag reports continuously
	end
	state.active = wanted
	if wanted then
		local sound = state.sound
		sound:Stop() -- Stop is what rewinds a Sound; Play resumes from wherever it was left
		state.volume = Config.Audio.Pull.Volume
		sound.Volume = math.clamp(state.volume * Config.Audio.Pull.Gain, 0, Config.Audio.MaxVolume)
		sound:Play()
	end
end

--- Fade out a released pull. Call every frame. Nothing to do while one is being held: the
--- clip simply plays.
function Audio.updatePull(self: Audio, dt: number)
	local state = self.pull
	if state == nil or state.active or state.volume <= 0 then
		return
	end
	local P = Config.Audio.Pull
	state.volume = SoundMix.ease(state.volume, 0, dt, P.ReleaseSeconds)
	if state.volume < 1e-3 then
		state.volume = 0
		state.sound:Stop()
		state.sound.Volume = 0
		return
	end
	state.sound.Volume = math.clamp(state.volume * P.Gain, 0, Config.Audio.MaxVolume)
end

---------------------------------------------------------------------------------------------
-- The rolling loop
---------------------------------------------------------------------------------------------

local function buildRoll(self: Audio): Roll
	local attachment = newAttachment(self.anchor, "RollLoop")
	local roll: Roll = {
		attachment = attachment,
		voices = {
			{ sound = newSound(attachment, "RollA"), gain = 1, level = 1 },
			{ sound = newSound(attachment, "RollB"), gain = 1, level = 0 },
		},
		front = 1,
		incoming = nil,
		fadeStart = 0,
		fadeLength = Config.Audio.Roll.CrossfadeSeconds,
		tier = nil,
		lastClip = {},
		volume = 0,
		pitch = 1,
	}
	self.roll = roll
	return roll
end

-- Start one side of the crossfade on a freshly picked clip from the current tier.
local function startRollVoice(roll: Roll, index: number, tier: number)
	local clips = (Config.Audio.Roll.Tiers :: any)[tier] :: { Clip }?
	if clips == nil or #clips == 0 then
		return
	end
	local i = SoundMix.pick(#clips, roll.lastClip[tier], math.random())
	roll.lastClip[tier] = i
	local clip = clips[i]

	local voice = roll.voices[index]
	voice.gain = clip.Gain
	local sound = voice.sound
	sound:Stop()
	sound.SoundId = clip.Id
	sound.Looped = false
	sound.Volume = 0
	sound.PlaybackSpeed = math.max(roll.pitch, 0.05)

	-- Start somewhere other than the beginning, so a tier holding a single recording does
	-- not hand the same stretch of it to itself over and over. Leave room for three
	-- crossfades' worth of clip after the offset, or the new voice would be due to hand
	-- over again almost immediately.
	--
	-- This is always written, never left alone: Sound:Play() restores whatever position a
	-- script last set, so a pooled voice with no room for an offset would otherwise inherit
	-- the previous pass's one and start part way in forever.
	local R = Config.Audio.Roll
	local headroom = sound.TimeLength - R.CrossfadeSeconds * R.StartOffsetHeadroomCrossfades
	sound.TimePosition = if headroom > 0
		then math.random() * math.min(R.StartOffsetMaxSeconds, headroom)
		else 0
	sound:Play()
end

local function silenceRoll(roll: Roll)
	for _, voice in roll.voices do
		voice.sound:Stop()
		voice.sound.Volume = 0
		voice.level = 0
	end
	roll.voices[roll.front].level = 1
	roll.incoming = nil
	-- Reset the eased volume too. Leaving it behind means the next table starts above the
	-- silence threshold, skips the "a still table costs nothing" branch, and audibly starts
	-- a rolling clip on a table where nothing is moving.
	roll.volume = 0
	roll.tier = nil
end

--- Stop the roll outright. The per-frame update is the only thing that winds it down, and
--- the moment a player leaves a table nothing calls that again - so without this the two
--- voices are abandoned still playing, at the table just walked away from.
function Audio.stopRoll(self: Audio)
	local roll = self.roll
	if roll then
		silenceRoll(roll)
	end
end

--- The rolling loop: one continuous sound for the whole table whose volume and pitch follow
--- how fast the balls are actually moving. Call every frame with the table being played.
---
--- It is built from two alternating Sounds that crossfade, rather than one looping Sound,
--- because the recordings are not known to loop seamlessly. A seam clicks every couple of
--- seconds, and during the long quiet stretch after a break that click is the only thing you
--- would hear. Crossfading means the raw join is never reached.
function Audio.updateRoll(self: Audio, match: any, dt: number)
	local R = Config.Audio.Roll
	local roll = self.roll or buildRoll(self)

	-- The fastest ball still on the table stands for the whole table, and the sound comes
	-- from that ball so it travels with whatever is actually rolling.
	local fastest = 0
	local leader: Ball.Ball? = nil
	for _, b in match.state.balls do
		if not b.pocketed then
			local speed = Ball.speed(b)
			if speed > fastest then
				fastest, leader = speed, b
			end
		end
	end
	if leader then
		roll.attachment.WorldPosition =
			TableBuilder.toWorld(match.placement, leader.x, leader.y, Config.Balls.RadiusInches)
	end

	local k = SoundMix.loudness(fastest, R.MinSpeed, R.LoudSpeed)
	local targetVolume = if fastest > R.MinSpeed then R.MaxVolume * k else 0
	roll.volume = SoundMix.ease(roll.volume, targetVolume, dt, R.VolumeTau)
	roll.pitch = SoundMix.ease(roll.pitch, SoundMix.lerp(R.MinPitch, R.MaxPitch, k), dt, R.PitchTau)

	-- A still table costs nothing: both voices stop rather than looping silently.
	if targetVolume <= 0 and roll.volume < 1e-3 then
		if roll.voices[roll.front].sound.IsPlaying or roll.incoming ~= nil then
			silenceRoll(roll)
		end
		return
	end

	local tier = SoundMix.tierFor(fastest, R.TierSpeeds, roll.tier, R.TierMargin)
	roll.tier = tier
	local now = os.clock()
	local front = roll.voices[roll.front]

	-- Nothing playing (first frame of a shot, or a hitch swallowed the handover): start now.
	if not front.sound.IsPlaying and roll.incoming == nil then
		startRollVoice(roll, roll.front, tier)
		front.level = 1
	end

	if roll.incoming == nil and front.sound.IsPlaying then
		local sound = front.sound
		local remaining =
			SoundMix.remaining(sound.TimeLength, sound.TimePosition, sound.PlaybackSpeed)
		-- Never fade for longer than a sensible share of the clip, or a short recording
		-- would start handing over before it had properly begun.
		local playable = sound.TimeLength / math.max(sound.PlaybackSpeed, 1e-3)
		local fade =
			math.max(math.min(R.CrossfadeSeconds, playable * R.CrossfadeMaxClipFraction), 1e-3)
		if remaining <= fade then
			local other = 3 - roll.front
			startRollVoice(roll, other, tier)
			roll.incoming = other
			roll.fadeStart = now
			-- Fade over the audio that is ACTUALLY left, not the nominal length. The frame
			-- that crosses the threshold can overshoot it badly after a hitch - a 0.3s frame
			-- takes the remainder from 0.36 to 0.06 - and scheduling the full 0.35s anyway
			-- would run the outgoing clip dry a sixth of the way through the curve, leaving
			-- the incoming at a quarter amplitude and a hole where the crossfade should be.
			roll.fadeLength = math.max(math.min(remaining, fade), 1e-3)
		end
	end

	local incoming = roll.incoming
	if incoming ~= nil then
		local t = (now - roll.fadeStart) / math.max(roll.fadeLength, 1e-3)
		local outGain, inGain = SoundMix.crossfade(t)
		front.level = outGain
		roll.voices[incoming].level = inGain
		if t >= 1 then
			front.sound:Stop()
			front.level = 0
			roll.front = incoming
			roll.voices[incoming].level = 1
			roll.incoming = nil
		end
	end

	for _, voice in roll.voices do
		voice.sound.Volume =
			math.clamp(voice.level * voice.gain * roll.volume, 0, Config.Audio.MaxVolume)
		voice.sound.PlaybackSpeed = math.max(roll.pitch, 0.05)
	end
end

return Audio
