--!strict
-- Audio: turns simulation events into sound.
--
-- It listens to a Match rather than watching the balls, so what you hear is exactly what
-- the physics said happened, at the moment it happened, with the impact speed already
-- worked out. Volume and pitch come off that speed, so a firm break sounds like one and a
-- gentle kiss sounds like one.
--
-- Two things stop a break turning into mush. A single break makes well over a hundred ball
-- contacts (121 in one measured shot), so anything under Config.Audio.MinImpactSpeed is
-- dropped, and the rest are rate limited per frame and by a short gap between clacks.
--
-- The library clips are field recordings several seconds long containing multiple hits and
-- rolls, not one-shots, so each is trimmed to its attack by Config.Audio.Trim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Simulation = require(Shared:WaitForChild("Physics"):WaitForChild("Simulation"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

type Event = Simulation.Event

local Audio = {}
Audio.__index = Audio

export type Audio = typeof(setmetatable(
	{} :: {
		folder: Folder,
		lastClack: number,
		playedThisFrame: number,
		frameStamp: number,
	},
	Audio
))

function Audio.new(parent: Instance): Audio
	local folder = Instance.new("Folder")
	folder.Name = "Audio"
	folder.Parent = parent
	return setmetatable({
		folder = folder,
		lastClack = 0,
		playedThisFrame = 0,
		frameStamp = 0,
	}, Audio)
end

-- 0 at a standstill, 1 at the speed Config calls full volume.
local function loudness(speed: number): number
	return math.clamp(speed / math.max(Config.Audio.FullVolumeSpeed, 1e-3), 0, 1)
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

--- Play one clip at a world position. Sounds are emitted from where the contact happened,
--- so a break spreads across the table instead of arriving from a single point.
function Audio.playAt(self: Audio, name: string, at: Vector3, volume: number, pitch: number)
	local A = Config.Audio
	local id = A.Ids[name]
	if id == nil or id == "" then
		return -- no asset wired up for this one yet
	end
	local trim = A.Trim[name]

	local emitter = Instance.new("Part")
	emitter.Name = "SoundAt_" .. name
	emitter.Anchored = true
	emitter.CanCollide = false
	emitter.CanQuery = false
	emitter.CanTouch = false
	emitter.CastShadow = false
	emitter.Transparency = 1
	emitter.Size = Vector3.new(0.2, 0.2, 0.2)
	emitter.Position = at
	emitter.Parent = self.folder

	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.RollOffMinDistance = A.RollOffMinStuds
	sound.RollOffMaxDistance = A.RollOffMaxStuds
	sound.Parent = emitter

	local window = if trim then trim.Seconds else nil
	sound.Ended:Once(function()
		emitter:Destroy()
	end)
	sound:Play()
	if trim and trim.Start > 0 then
		sound.TimePosition = trim.Start
	end
	-- Stop the clip before the recording wanders into the next hit, and make sure the
	-- emitter goes away even if Ended never fires.
	local life = (window or 2) + 0.2
	if window then
		task.delay(window, function()
			if sound.Parent then
				sound:Stop()
			end
		end)
	end
	Debris:AddItem(emitter, life)
end

-- Per-frame budget, so a break cannot spawn fifty sounds in one step.
local function canPlay(self: Audio, now: number): boolean
	if now ~= self.frameStamp then
		self.frameStamp = now
		self.playedThisFrame = 0
	end
	if self.playedThisFrame >= Config.Audio.MaxSoundsPerFrame then
		return false
	end
	self.playedThisFrame += 1
	return true
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
			local k = loudness(ev.speed)
			self:playAt(
				"CueStrike",
				at,
				lerp(A.Strike.MinVolume, A.Strike.MaxVolume, k),
				lerp(A.Strike.MaxPitch, A.Strike.MinPitch, k) -- harder hit, lower pitch
			)
		elseif ev.type == "pocket" then
			-- Always audible: a ball dropping is the payoff and must never be rate limited
			-- away behind a wall of clacks.
			self:playAt("PocketDrop", at, A.Pocket.Volume, 1)
		elseif ev.type == "ballHit" then
			if ev.speed < A.MinImpactSpeed then
				return
			end
			if now - self.lastClack < A.MinSecondsBetweenClacks or not canPlay(self, now) then
				return
			end
			self.lastClack = now
			local k = loudness(ev.speed)
			self:playAt(
				"BallClack",
				at,
				lerp(A.Clack.MinVolume, A.Clack.MaxVolume, k),
				lerp(A.Clack.MaxPitch, A.Clack.MinPitch, k)
			)
		elseif ev.type == "railHit" then
			if ev.speed < A.MinImpactSpeed or not canPlay(self, now) then
				return
			end
			local k = loudness(ev.speed)
			self:playAt(
				"RailThud",
				at,
				lerp(A.Rail.MinVolume, A.Rail.MaxVolume, k),
				lerp(A.Rail.MaxPitch, A.Rail.MinPitch, k)
			)
		end
	end)
end

--- The soft click while the aim turns (GDD section 5: a tick every step of rotation).
function Audio.tick(self: Audio, at: Vector3)
	self:playAt("AimTick", at, Config.Audio.Tick.Volume, 1)
end

return Audio
