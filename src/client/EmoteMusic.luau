--!strict
-- EmoteMusic: each dance's song, heard from every one of its dancers (designer, 2026-10-27;
-- Config.EmoteMenu.Music*). Dancers moving in step (one EmoteSync.groupKey: the same dance from
-- the same `at`) share one AudioPlayer, wired to an AudioEmitter on each dancer's root: one
-- playback heard from several bodies, so the copies are never out of time. Two side by side are
-- louder; walk apart and each is heard from where they are. Up to MusicVoices nearest dancers
-- of a group emit, and the song is turned down as more of them reach you (EmoteSync.groupGain,
-- MusicTwoTogether: two side by side are 1.5 times one, not double; one of them alone is as
-- loud as a dancer alone). It plays where the server clock
-- says (EmoteSync.musicPosition), so a song joined late is in step with its dance, and is
-- re-sought when it drifted past MusicToleranceSeconds. Roblox's listener on the camera
-- (SoundService.DefaultListenerLocation) hears the emitters. Settings' Emote music switch (the
-- EmoteMusic sound group, apart from the lobby's Music) mutes it on this screen. A pass every MusicVoiceSeconds re-picks the voices; nothing runs every
-- frame, and the pass stops when no song plays.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local SoundGroups = require(script.Parent.SoundGroups)

local E = Config.EmoteMenu

local EmoteMusic = {}

type Music = { Id: string, Start: number, Loop: number, Volume: number?, Speed: number? }
type Group = {
	music: Music,
	gain: number, -- turned down for the voices you hear at once
	once: boolean,
	at: number,
	player: AudioPlayer,
	members: { [number]: boolean },
	voices: { [number]: AudioEmitter },
}

local groups: { [string]: Group } = {}
local running = false
local started = false
local folder: Folder? = nil
local curve = EmoteSync.musicCurve(E.MusicHearStuds, E.MusicMaxStuds)

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

local function holder(): Folder
	if folder == nil or folder.Parent == nil then
		local made = Instance.new("Folder")
		made.Name = "EmoteMusic"
		made.Parent = SoundService
		folder = made
	end
	return folder :: Folder
end

local function volumeOf(g: Group): number
	return (g.music.Volume or E.MusicVolume) * SoundGroups.get("EmoteMusic").Volume * g.gain
end

-- Where its song is now (the track's own seconds), or nil once a play-once song is over.
local function positionOf(g: Group): number?
	local now = workspace:GetServerTimeNow()
	local m = g.music
	if g.once then
		return EmoteSync.musicOncePosition(now, g.at, m.Start, m.Loop, m.Speed)
	end
	return EmoteSync.musicPosition(now, g.at, m.Start, m.Loop, m.Speed)
end

local function addVoice(g: Group, userId: number, root: BasePart)
	local emitter = Instance.new("AudioEmitter")
	emitter.Name = "EmoteMusic"
	emitter:SetDistanceAttenuation(curve)
	local wire = Instance.new("Wire")
	wire.SourceInstance = g.player
	wire.TargetInstance = emitter
	wire.Parent = emitter
	emitter.Parent = root
	g.voices[userId] = emitter
end

-- The nearest MusicVoices dancers of the group emit (a new body gets a new emitter).
local function pickVoices(g: Group)
	local camera = workspace.CurrentCamera
	local list = {}
	for userId in g.members do
		local root = rootOf(userId)
		if root and camera then
			table.insert(
				list,
				{ key = userId, distance = (root.Position - camera.CFrame.Position).Magnitude }
			)
		end
	end
	local keep = EmoteSync.nearest(list, E.MusicVoices)
	for userId, emitter in g.voices do
		if not keep[userId] or emitter.Parent == nil or emitter.Parent ~= rootOf(userId) then
			emitter:Destroy()
			g.voices[userId] = nil
		end
	end
	for userId in keep do
		local root = rootOf(userId)
		if not g.voices[userId] and root then
			addVoice(g, userId, root)
		end
	end
	-- How many voices reach you, each as loud as it arrives, sets the group's gain.
	local heard = 0
	if camera then
		for _, emitter in g.voices do
			local root = emitter.Parent
			if root and root:IsA("BasePart") then
				heard += EmoteSync.curveAt(
					curve,
					(root.Position - camera.CFrame.Position).Magnitude
				)
			end
		end
	end
	local gain = EmoteSync.groupGain(heard, E.MusicTwoTogether)
	if math.abs(gain - g.gain) > 0.02 then
		g.gain = gain
		g.player.Volume = volumeOf(g)
	end
end

-- Back on the clock if it drifted (a hitch, a slow load).
local function resync(g: Group)
	if not g.player.IsPlaying then
		return
	end
	local want = positionOf(g)
	if want == nil then
		g.player:Stop()
		return
	end
	local m = g.music
	local drift =
		EmoteSync.drift(g.player.TimePosition - m.Start, want - m.Start, m.Loop, not g.once)
	if math.abs(drift) > E.MusicToleranceSeconds then
		g.player.TimePosition = want
	end
end

local function pass()
	running = true
	while next(groups) ~= nil do
		task.wait(E.MusicVoiceSeconds)
		for _, g in groups do
			pickVoices(g)
			resync(g)
		end
	end
	running = false
end

--- `userId` dances `id` from server time `at`: their song (if it has one) is heard from them.
function EmoteMusic.join(userId: number, id: string, at: number)
	local row = EmoteSync.find(E.List, id)
	local music: Music? = row and row.Music
	if row == nil or music == nil then
		return
	end
	local key = EmoteSync.groupKey(id, at)
	local found = groups[key]
	if found then
		found.members[userId] = true
		pickVoices(found)
		return
	end
	-- A dance that plays once (Money) plays its song once too: it never loops.
	local once = row.Once == true
	local player = Instance.new("AudioPlayer")
	player.Name = id
	local untyped: any = player -- (AssetId is missing from the type definitions)
	untyped.AssetId = music.Id
	player.Volume = (music.Volume or E.MusicVolume) * SoundGroups.get("EmoteMusic").Volume
	player.PlaybackSpeed = music.Speed or 1
	player.Looping = not once
	player.PlaybackRegion = NumberRange.new(music.Start, music.Start + music.Loop)
	player.LoopRegion = NumberRange.new(music.Start, music.Start + music.Loop)
	player.Parent = holder()
	local g: Group = {
		music = music,
		gain = 1,
		once = once,
		at = at,
		player = player,
		members = { [userId] = true },
		voices = {},
	}
	groups[key] = g
	pickVoices(g)
	task.spawn(function()
		local deadline = os.clock() + E.MusicLoadSeconds
		while not player.IsReady and os.clock() < deadline and groups[key] == g do
			task.wait(0.05)
		end
		if groups[key] ~= g or not player.IsReady then
			return -- stopped meanwhile, or the track is gone: the dance goes on silent
		end
		local position = positionOf(g)
		if position == nil then
			return -- a play-once song is over: not again
		end
		player.TimePosition = position
		player:Play()
	end)
	if not running then
		task.spawn(pass)
	end
end

--- `userId` stopped dancing `id` from `at`: their voice goes, the song with the last of them.
function EmoteMusic.leave(userId: number, id: string, at: number)
	local key = EmoteSync.groupKey(id, at)
	local g = groups[key]
	if g == nil then
		return
	end
	g.members[userId] = nil
	local voice = g.voices[userId]
	if voice then
		voice:Destroy()
		g.voices[userId] = nil
	end
	if next(g.members) == nil then
		groups[key] = nil
		g.player:Destroy()
		for _, emitter in g.voices do
			emitter:Destroy()
		end
	else
		pickVoices(g) -- one further away may take the freed voice
	end
end

--- Follow Settings' Emote music switch (client, once).
function EmoteMusic.start()
	if started then
		return
	end
	started = true
	local group = SoundGroups.get("EmoteMusic")
	group:GetPropertyChangedSignal("Volume"):Connect(function()
		for _, g in groups do
			g.player.Volume = volumeOf(g)
		end
	end)
end

return EmoteMusic
