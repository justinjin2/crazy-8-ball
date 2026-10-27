--!strict
-- EmotePlayer: the emote menu's dancing (Config.EmoteMenu; server src/server/EmoteService.luau).
-- - Your own dance: the server says when its loop started (`at`; someone's nearby when joining
--   them in step), then it plays on your character's Animator, which shows it to everyone, at
--   the place in its loop the server clock says (EmoteSync.offset). It loops until you walk or
--   jump (a Walk dance: until you jump), pick another, your turn takes the body (EmoteHud), or
--   MaxSeconds.
-- - Everyone's music: each dance with a licensed track plays it from the dancer's body for
--   players nearby (MusicHearStuds to MusicMaxStuds), in the Music group (Settings' Music
--   switch mutes it), at the place the server clock says. Dancers moving in step share one
--   copy (EmoteSync.groupKey), so a group's song never doubles.
-- - The favourites: the server's list, for the menu (Changed fires when it changes).
-- - Our own emotes (Config.EmoteMenu.Custom): Popcorn plays its intro once, then its loop;
--   Bullseye plays once and ends. Their props and effects round every dancer: EmoteScene.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local Net = require(Shared:WaitForChild("Net"))
local EmoteScene = require(script.Parent.EmoteScene)
local SoundGroups = require(script.Parent.SoundGroups)

local E = Config.EmoteMenu

local EmotePlayer = {}

local changed = Instance.new("BindableEvent")
--- Fires when the favourites change, or your own dance starts or stops.
EmotePlayer.Changed = changed.Event

local started = false
local favorites: { [string]: boolean } = {}
-- Your own dance: its row, its track (and the intro before it), when it started (os.clock)
-- and its watchers.
type Mine = {
	id: string,
	track: AnimationTrack,
	intro: AnimationTrack?,
	since: number,
	links: { RBXScriptConnection },
	release: (() -> ())?, -- lets go of the held facing (our own emotes)
}
local mine: Mine? = nil
local busy = false -- a Play request is out
local tracks: { [string]: AnimationTrack } = {} -- your character's loaded dances, by id
local tracksOf: Animator? = nil
-- Everyone's dances (the server's word) and the music groups playing.
local dances: { [number]: { id: string, at: number } } = {}
local groups: { [string]: { sound: Sound, members: { [number]: boolean } } } = {}

local function request(...: any): any
	local ok, result = pcall(function(...)
		return Net.get("EmoteRequest"):InvokeServer(...)
	end, ...)
	if not ok or type(result) ~= "table" then
		return { ok = false, reason = "BadRequest" }
	end
	return result
end

local function animator(): Animator?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

-- Your character's track for a dance (or its intro: `intro`), loaded once per character (a
-- track per press would pile up past Roblox's 64-track limit). It loops unless it plays once.
local function trackFor(row: EmoteSync.Row, intro: boolean?): AnimationTrack?
	local a = animator()
	local id = if intro then row.Intro else row.Animation
	if a == nil or id == nil then
		return nil
	end
	if a ~= tracksOf then
		tracks, tracksOf = {}, a
	end
	local key = if intro then row.Id .. "/Intro" else row.Id
	local track = tracks[key]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = "rbxassetid://" .. id
		local ok, loaded = pcall(function()
			return a:LoadAnimation(animation)
		end)
		if not ok then
			warn("[8ball] EmotePlayer: " .. tostring(loaded))
			return nil
		end
		local fresh: AnimationTrack = loaded
		fresh.Priority = Enum.AnimationPriority.Action
		fresh.Looped = not intro and row.Once ~= true
		tracks[key] = fresh
		return fresh
	end
	return track
end

local function rootOf(userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

------------------------------------------------------------------------------------------------
-- The music
------------------------------------------------------------------------------------------------

local function musicOf(id: string): any
	local row = EmoteSync.find(E.List, id)
	return row and row.Music
end

local function placeSound(group: any)
	for userId in group.members do
		local part = rootOf(userId)
		if part then
			group.sound.Parent = part
			return
		end
	end
	group.sound.Parent = nil
end

local function joinMusic(userId: number, id: string, at: number)
	local music = musicOf(id)
	if music == nil then
		return
	end
	local key = EmoteSync.groupKey(id, at)
	local group = groups[key]
	if group then
		group.members[userId] = true
		if group.sound.Parent == nil then
			placeSound(group)
		end
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "EmoteMusic"
	sound.SoundId = music.Id
	sound.Volume = music.Volume or E.MusicVolume
	sound.PlaybackSpeed = music.Speed or 1
	sound.Looped = true
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = NumberRange.new(music.Start, music.Start + music.Loop)
	sound.LoopRegion = NumberRange.new(music.Start, music.Start + music.Loop)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = E.MusicHearStuds
	sound.RollOffMaxDistance = E.MusicMaxStuds
	sound.SoundGroup = SoundGroups.get("Music") -- before parenting: never adopted into Sfx
	group = { sound = sound, members = { [userId] = true } }
	groups[key] = group
	placeSound(group)
	task.spawn(function()
		local deadline = os.clock() + E.MusicLoadSeconds
		while not sound.IsLoaded and os.clock() < deadline and groups[key] == group do
			task.wait(0.1)
		end
		if groups[key] ~= group or not sound.IsLoaded then
			return -- stopped meanwhile, or the track is gone: the dance goes on silent
		end
		sound.TimePosition = EmoteSync.musicPosition(
			workspace:GetServerTimeNow(),
			at,
			music.Start,
			music.Loop,
			music.Speed
		)
		sound:Play()
	end)
end

local function leaveMusic(userId: number, id: string, at: number)
	local key = EmoteSync.groupKey(id, at)
	local group = groups[key]
	if group == nil then
		return
	end
	group.members[userId] = nil
	if next(group.members) == nil then
		groups[key] = nil
		group.sound:Destroy()
	elseif group.sound.Parent == nil or group.sound.Parent == rootOf(userId) then
		placeSound(group) -- the one it played from stopped: it moves to another of the group
	end
end

local function onDance(userId: number, id: string?, at: number?)
	local old = dances[userId]
	if old then
		dances[userId] = nil
		leaveMusic(userId, old.id, old.at)
		EmoteScene.stop(userId)
	end
	if id and at then
		dances[userId] = { id = id, at = at }
		joinMusic(userId, id, at)
		local row = EmoteSync.find(E.List, id)
		if row and row.Scene then
			EmoteScene.start(userId, row)
		end
	end
end

------------------------------------------------------------------------------------------------
-- Your own dance
------------------------------------------------------------------------------------------------

-- Our own emotes hold the body's facing (their lounger and target are built round it): the
-- camera, shift lock and auto-rotate cannot turn it until the dance ends. Answers how to let go.
local function holdFacing(humanoid: Humanoid): () -> ()
	local root = humanoid.RootPart
	if root == nil then
		return function() end
	end
	local was = humanoid.AutoRotate
	humanoid.AutoRotate = false
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local attachment = Instance.new("Attachment")
	attachment.Name = "EmoteFacing"
	attachment.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "EmoteFacing"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = true
	align.CFrame = CFrame.lookAt(Vector3.zero, flat)
	align.Parent = root
	return function()
		align:Destroy()
		attachment:Destroy()
		if humanoid.Parent then
			humanoid.AutoRotate = was
		end
	end
end

local function endMine(fade: boolean)
	local current = mine
	if current == nil then
		return
	end
	mine = nil
	for _, link in current.links do
		link:Disconnect()
	end
	if current.release then
		current.release()
	end
	current.track:Stop(if fade then E.FadeSeconds else 0)
	if current.intro then
		current.intro:Stop(if fade then E.FadeSeconds else 0)
	end
	changed:Fire()
end

--- Stop your dance (`how`: "Move", "Turn", "Menu" or "Other"), telling the server.
function EmotePlayer.stop(how: string)
	if mine == nil then
		return
	end
	endMine(true)
	task.spawn(request, "Stop", how)
end

--- Whether you are dancing now, and which.
function EmotePlayer.current(): string?
	return if mine then mine.id else nil
end

--- Start a dance (a card pressed). Answers false with the server's reason when refused.
function EmotePlayer.play(id: string): (boolean, string?)
	local row = EmoteSync.find(E.List, id)
	if row == nil or busy then
		return false, "Busy"
	end
	busy = true
	local answer = request("Play", id)
	busy = false
	if not answer.ok then
		return false, answer.reason
	end
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local track = trackFor(row)
	local intro = if row.Intro then trackFor(row, true) else nil
	if humanoid == nil or track == nil or (row.Intro ~= nil and intro == nil) then
		task.spawn(request, "Stop", "Other")
		return false, "Busy"
	end
	endMine(false)
	local speed = row.Speed or 1
	local links = {}
	local current: Mine = {
		id = row.Id,
		track = track,
		intro = intro,
		since = os.clock(),
		links = links,
		release = if row.Scene and E.Custom.HoldFacing then holdFacing(humanoid) else nil,
	}
	mine = current
	if intro then
		-- Our own emotes start on their own: the intro, then the loop from its start, blended
		-- in as the intro ends (its last pose is the loop's first).
		intro:Play(E.FadeSeconds, 1, speed)
		local chained = false
		table.insert(
			links,
			intro.Stopped:Connect(function()
				if mine == current and not chained then
					EmotePlayer.stop("Other") -- something else stopped it (a turn's pose)
				end
			end)
		)
		task.spawn(function()
			local deadline = os.clock() + E.LoadSeconds
			while intro.Length <= 0 and os.clock() < deadline and mine == current do
				task.wait()
			end
			local left = (intro.Length - intro.TimePosition) / speed - E.FadeSeconds
			if left > 0 then
				task.wait(left)
			end
			if mine == current then
				chained = true
				track:Play(E.FadeSeconds, 1, speed)
				track.TimePosition = 0
				intro:Stop(E.FadeSeconds)
			end
		end)
	else
		track:Play(E.FadeSeconds, 1, speed)
	end
	local at = if type(answer.at) == "number" then answer.at else workspace:GetServerTimeNow()
	-- In step with the loop the server started (yours, or the dancer you joined). Our own
	-- emotes start on their own: from their start.
	task.spawn(function()
		if row.Scene then
			return
		end
		local deadline = os.clock() + E.LoadSeconds
		while track.Length <= 0 and os.clock() < deadline do
			task.wait()
		end
		if track.IsPlaying and track.Length > 0 then
			track.TimePosition =
				EmoteSync.offset(workspace:GetServerTimeNow(), at, track.Length, speed)
		end
	end)
	-- Walking or jumping stops it, like Roblox's own emotes (pushes do not); a Walk dance goes
	-- on while you walk, over the walk animation, until you jump.
	if not row.Walk then
		table.insert(
			links,
			humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
				if humanoid.MoveDirection.Magnitude > E.MoveStopSpeed then
					EmotePlayer.stop("Move")
				end
			end)
		)
	end
	table.insert(
		links,
		humanoid.StateChanged:Connect(function(_, new)
			if new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Dead then
				EmotePlayer.stop("Move")
			end
		end)
	)
	table.insert(
		links,
		track.Stopped:Connect(function()
			-- Something else stopped it (a turn's pose stops every track), or a one-shot is
			-- done: tell the server.
			if mine == current then
				EmotePlayer.stop("Other")
			end
		end)
	)
	task.delay(E.MaxSeconds, function()
		if mine == current then
			EmotePlayer.stop("Other")
		end
	end)
	changed:Fire()
	return true, nil
end

--- The favourites ([id] = true).
function EmotePlayer.favorites(): { [string]: boolean }
	return favorites
end

local function setLocal(id: string, on: boolean)
	if on then
		favorites[id] = true
	else
		favorites[id] = nil
	end
	changed:Fire()
end

--- Make a dance a favourite or not (the star). The change shows at once; a refusal (too many
--- taps, the save not loaded yet) puts the star back.
function EmotePlayer.setFavorite(id: string, on: boolean)
	if EmoteSync.find(E.List, id) == nil then
		return
	end
	setLocal(id, on)
	task.spawn(function()
		local answer = request("Favorite", id, on)
		if not answer.ok and (favorites[id] == true) == on then
			setLocal(id, not on)
		end
	end)
end

--- Start listening (client, once).
function EmotePlayer.start()
	if started or not E.Enabled then
		return
	end
	started = true
	Net.get("EmoteState").OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		if type(message.favorites) == "table" then
			favorites = EmoteSync.cleanFavorites(E.List, message.favorites)
			changed:Fire()
		elseif type(message.userId) == "number" then
			if message.stop == true then
				onDance(message.userId, nil, nil)
			elseif type(message.id) == "string" and type(message.at) == "number" then
				onDance(message.userId, message.id, message.at)
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		onDance(player.UserId, nil, nil)
	end)
	-- A dancer's new body (respawn): their song follows them.
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		endMine(false)
	end)
	task.spawn(function()
		local answer = request("Who")
		if not answer.ok then
			return
		end
		if type(answer.favorites) == "table" then
			favorites = EmoteSync.cleanFavorites(E.List, answer.favorites)
			changed:Fire()
		end
		if type(answer.dancers) == "table" then
			for _, d in answer.dancers do
				if type(d) == "table" and type(d.userId) == "number" and type(d.id) == "string" then
					if type(d.at) == "number" and dances[d.userId] == nil then
						onDance(d.userId, d.id, d.at)
					end
				end
			end
		end
	end)
end

return EmotePlayer
