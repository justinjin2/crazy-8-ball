--!strict
-- EmotePlayer: the emote menu's dancing (Config.EmoteMenu; server src/server/EmoteService.luau).
-- - Your own dance starts at once as you press: your client picks its loop's start (`at`, the
--   server clock now) and plays it on your character's Animator, which shows it to everyone;
--   the server checks it and may answer another `at` (someone's nearby doing the same dance:
--   you join them in step). It loops until you jump, pick another, reset, or your turn takes
--   the body (EmoteHud); walking does not stop it, you walk at its speed meanwhile
--   (Config.EmoteMenu.WalkSpeed, or the row's own). A refusal stops it again.
-- - Sync: the prompt on a dancer near you (EmoteSyncPrompt) starts their dance on you at once
--   from their `at` (a Duo: Gojo gets you Geto, and the other way round), and asks the server.
-- - Every dancer's track, yours included, is kept on the server clock on this screen
--   (EmoteAlign), so dancers in step look in step whatever their pings.
-- - Everyone's music: each dance's song is heard from every one of its dancers, in time
--   (EmoteMusic).
-- - The favourites: the server's list, for the menu (Changed fires when it changes).
-- - Our own emotes (Config.EmoteMenu.Custom): Popcorn plays its intro once, then its loop;
--   Bullseye plays once and ends. Their props and effects round every dancer: EmoteScene.
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local Net = require(Shared:WaitForChild("Net"))
local EmoteAlign = require(script.Parent.EmoteAlign)
local EmoteMusic = require(script.Parent.EmoteMusic)
local EmoteScene = require(script.Parent.EmoteScene)
local EmoteSyncPrompt = require(script.Parent.EmoteSyncPrompt)

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
	at: number,
	track: AnimationTrack,
	intro: AnimationTrack?,
	since: number,
	links: { RBXScriptConnection },
	release: (() -> ())?, -- lets go of the held facing (our own emotes)
	walk: (() -> ())?, -- puts your walking speed back
}
local mine: Mine? = nil
local busy = false -- a Play request is out
local tracks: { [string]: AnimationTrack } = {} -- your character's loaded dances, by id
local tracksOf: Animator? = nil
-- Everyone's dances (the server's word).
local dances: { [number]: EmoteSyncPrompt.Dancer } = {}

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

local function onDance(userId: number, id: string?, at: number?, partner: number?)
	local old = dances[userId]
	if old and id == old.id and at == old.at then
		-- The server's word on a dance this client already started (yours): only its partner.
		if partner ~= nil and old.partner ~= partner then
			old.partner = partner
			local theirs = dances[partner]
			if theirs then
				theirs.partner = userId
				EmoteSyncPrompt.set(partner, theirs)
			end
		end
		return
	end
	EmoteAlign.set(userId, id, at)
	if old then
		dances[userId] = nil
		EmoteMusic.leave(userId, old.id, old.at)
		EmoteScene.stop(userId)
		-- Their duo partner is free again.
		for other, dance in dances do
			if dance.partner == userId then
				dance.partner = nil
				EmoteSyncPrompt.set(other, dance)
			end
		end
	end
	if id and at then
		local dance: EmoteSyncPrompt.Dancer = { id = id, at = at, partner = partner }
		dances[userId] = dance
		EmoteMusic.join(userId, id, at)
		local row = EmoteSync.find(E.List, id)
		if row and row.Scene then
			EmoteScene.start(userId, row)
		end
		local theirs = partner and dances[partner]
		if theirs then
			theirs.partner = userId
			EmoteSyncPrompt.set(partner :: number, theirs)
		end
	end
	EmoteSyncPrompt.set(userId, dances[userId])
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
	if current.walk then
		current.walk()
	end
	current.track:Stop(if fade then E.FadeSeconds else 0)
	if current.intro then
		current.intro:Stop(if fade then E.FadeSeconds else 0)
	end
	EmoteSyncPrompt.mine(nil, nil, dances)
	changed:Fire()
end

-- Walk at `speed` while dancing (on this client only: the server's own speed, a table's hold
-- of 0 included, is never lowered or lost). Answers how to put it back: only if nothing else
-- changed it meanwhile.
local function slowWalk(humanoid: Humanoid, speed: number): () -> ()
	local was = humanoid.WalkSpeed
	if was <= speed then
		return function() end
	end
	humanoid.WalkSpeed = speed
	return function()
		-- (WalkSpeed is stored as a float: 1.6 reads back as 1.6000000238.)
		if humanoid.Parent and math.abs(humanoid.WalkSpeed - speed) < 1e-3 then
			humanoid.WalkSpeed = was
		end
	end
end

--- Stop your dance (`how`: "Move", "Turn", "Menu" or "Other"), telling the server.
function EmotePlayer.stop(how: string)
	if mine == nil then
		return
	end
	endMine(true)
	onDance(Players.LocalPlayer.UserId, nil, nil)
	task.spawn(request, "Stop", how)
end

--- Whether you are dancing now, and which.
function EmotePlayer.current(): string?
	return if mine then mine.id else nil
end

-- Whether your body can dance now (the server checks again): a turn or a cutscene anchors it.
local function free(): boolean
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root ~= nil and root:IsA("BasePart") and not root.Anchored
end

-- Dance `row` with its loop from server time `at`, at once (the server is asked after).
-- `partner`: the duo dancer you joined. Answers your dance, or nil and why.
local function begin(row: EmoteSync.Row, at: number, partner: number?): (Mine?, string?)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local track = trackFor(row)
	local intro = if row.Intro then trackFor(row, true) else nil
	if humanoid == nil or track == nil or (row.Intro ~= nil and intro == nil) then
		return nil, "Busy"
	end
	endMine(false)
	local speed = row.Speed or 1
	local links = {}
	local current: Mine = {
		id = row.Id,
		at = at,
		track = track,
		intro = intro,
		since = os.clock(),
		links = links,
		release = if row.Scene and E.Custom.HoldFacing then holdFacing(humanoid) else nil,
		walk = slowWalk(humanoid, row.WalkSpeed or E.WalkSpeed),
	}
	mine = current
	if intro then
		-- Our own emotes: the intro, then the loop from its start, blended in as the intro ends
		-- (its last pose is the loop's first).
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
	-- A jump stops it (walking does not: it plays over the walk animation).
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
	-- Your music and your place on the clock now, not after the server's echo.
	onDance(Players.LocalPlayer.UserId, row.Id, at, partner)
	EmoteSyncPrompt.mine(row.Id, at, dances)
	changed:Fire()
	return current, nil
end

-- The server's answer to a dance already started (`current`): a refusal stops it, another
-- `at` (joining a dancer nearby in step) moves it there.
local function settle(current: Mine, answer: any): (boolean, string?)
	if mine ~= current then
		return answer.ok == true, answer.reason -- another pick or a stop came meanwhile
	end
	if not answer.ok then
		endMine(true)
		onDance(Players.LocalPlayer.UserId, nil, nil)
		return false, answer.reason
	end
	if type(answer.at) == "number" and answer.at ~= current.at then
		current.at = answer.at
		local theirs = dances[Players.LocalPlayer.UserId]
		onDance(Players.LocalPlayer.UserId, current.id, answer.at, theirs and theirs.partner)
		EmoteSyncPrompt.mine(current.id, answer.at, dances)
	end
	return true, nil
end

--- Start a dance (a card pressed): at once, then the server's word. Answers false with the
--- server's reason when refused.
function EmotePlayer.play(id: string): (boolean, string?)
	local row = EmoteSync.find(E.List, id)
	if row == nil or busy or not free() then
		return false, "Busy"
	end
	local current, why = begin(row, workspace:GetServerTimeNow(), nil)
	if current == nil then
		return false, why
	end
	busy = true
	local answer = request("Play", id, current.at)
	busy = false
	return settle(current, answer)
end

--- Dance with `userId` (their Sync prompt held): their dance, or its duo partner, at once in
--- step with them (our own emotes from their start), then the server's word.
function EmotePlayer.sync(userId: number): (boolean, string?)
	local me = Players.LocalPlayer.UserId
	local theirs = dances[userId]
	if busy or not free() then
		return false, "Busy"
	end
	if theirs == nil or userId == me then
		return false, "Gone"
	end
	local partnered = theirs.partner ~= nil and theirs.partner ~= me
	local row, why = EmoteSync.syncRow(E.List, theirs.id, partnered)
	if row == nil then
		return false, why
	end
	local at = if row.Scene then workspace:GetServerTimeNow() else theirs.at
	local current, why2 = begin(row, at, if row.Id ~= theirs.id then userId else nil)
	if current == nil then
		return false, why2
	end
	busy = true
	local answer = request("Sync", userId, at)
	busy = false
	return settle(current, answer)
end

-- Fetch these assets now (in the background), so a dance or a song starts without a wait:
-- `class` instances (Animation or Sound, never parented) carry each id with its asset type.
local function preload(class: string, property: string, ids: { string })
	task.spawn(function()
		local items = {}
		for _, id in ids do
			local item: any = Instance.new(class :: any)
			item[property] = id
			table.insert(items, item)
		end
		pcall(function()
			ContentProvider:PreloadAsync(items)
		end)
		for _, item in items do
			item:Destroy()
		end
	end)
end

local musicLoaded = false

--- The tray opened: the dances' songs load now (once), so a pick's music starts at once.
function EmotePlayer.preloadMusic()
	if musicLoaded then
		return
	end
	musicLoaded = true
	local ids = {}
	for _, row in E.List do
		if row.Music then
			table.insert(ids, row.Music.Id)
		end
	end
	preload("Sound", "SoundId", ids)
end

--- Whether you may dance now (EmoteHud's button is up): the Sync prompts show only then.
function EmotePlayer.allowSync(on: boolean)
	EmoteSyncPrompt.allow(on, dances)
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
	EmoteMusic.start()
	-- The dances' animations (small) a little after joining, so everyone's dance shows at once.
	task.delay(E.Align.PreloadSeconds, function()
		local ids = {}
		for _, row in E.List do
			table.insert(ids, "rbxassetid://" .. row.Animation)
			if row.Intro then
				table.insert(ids, "rbxassetid://" .. row.Intro)
			end
		end
		preload("Animation", "AnimationId", ids)
	end)
	EmoteSyncPrompt.start(function(userId: number)
		task.spawn(EmotePlayer.sync, userId)
	end)
	Net.get("EmoteState").OnClientEvent:Connect(function(message: any)
		if type(message) ~= "table" then
			return
		end
		if type(message.favorites) == "table" then
			favorites = EmoteSync.cleanFavorites(E.List, message.favorites)
			changed:Fire()
		elseif type(message.userId) == "number" then
			if message.stop == true then
				-- A stop names the dance's `at`: one for a dance since replaced (your own new
				-- pick, started here before the server heard of it) is old news.
				local now = dances[message.userId]
				if now == nil or type(message.at) ~= "number" or message.at == now.at then
					onDance(message.userId, nil, nil)
				end
			elseif type(message.id) == "string" and type(message.at) == "number" then
				local partner = if type(message.partner) == "number" then message.partner else nil
				onDance(message.userId, message.id, message.at, partner)
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
						local partner = if type(d.partner) == "number" then d.partner else nil
						onDance(d.userId, d.id, d.at, partner)
					end
				end
			end
		end
	end)
end

return EmotePlayer
