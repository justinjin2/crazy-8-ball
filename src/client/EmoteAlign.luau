--!strict
-- EmoteAlign: every dancer near you moves on your screen where the server clock says
-- (2026-10-27, Config.EmoteMenu.Align). A dance is a loop that started at a server time `at`
-- (EmoteSync). A dancer's own client plays it on their Animator and Roblox copies it to everyone
-- else, late by the dancer's ping and yours; AnimationTrack.TimePosition does not replicate.
-- So this client seeks each dancer's track itself, on its own screen only: as Roblox's copy
-- arrives (Animator.AnimationPlayed), then every Align.Seconds a track that drifted more than
-- Align.ToleranceSeconds. Two players in step are in step on every screen, whatever their pings.
-- Your own dance goes through the same seek (with the switch off: only yours, as before). A
-- dance in Parts seeks only the part the clock is in, to its place in that part (the dancer's
-- client hands each part to the next; EmotePlayer).
-- Nothing runs every frame; the pass stops when nobody dances.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))

local E = Config.EmoteMenu
local A = E.Align

local EmoteAlign = {}

type Watch = {
	row: EmoteSync.Row,
	at: number,
	animator: Animator?,
	link: RBXScriptConnection?,
	parts: { [string]: number }, -- the loop's animation numbers (its parts), each part's index
	intro: string?, -- the intro's
}

local watched: { [number]: Watch } = {}
local running = false

local function characterOf(userId: number): Model?
	local player = Players:GetPlayerByUserId(userId)
	return player and player.Character
end

local function animatorOf(userId: number): Animator?
	local character = characterOf(userId)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid and humanoid:FindFirstChildOfClass("Animator")
end

local function near(userId: number): boolean
	local character = characterOf(userId)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local camera = workspace.CurrentCamera
	if root == nil or not root:IsA("BasePart") or camera == nil then
		return false
	end
	return (root.Position - camera.CFrame.Position).Magnitude <= A.Studs
end

-- Seek `track` to the clock if it is this dance's and it drifted (or always, `force`).
local function fix(w: Watch, track: AnimationTrack, force: boolean)
	local animation = track.Animation
	local number = animation and EmoteSync.assetNumber(animation.AnimationId)
	local part = if number then w.parts[number] else nil
	local kind = if part ~= nil
		then "Loop"
		elseif number ~= nil and number == w.intro then "Intro"
		else nil
	if kind == nil or not track.IsPlaying then
		return
	end
	local row = w.row
	local which, want = EmoteSync.phase(
		workspace:GetServerTimeNow(),
		w.at,
		row.Speed,
		row.Length,
		row.Once,
		if row.Intro then row.IntroLength else nil,
		E.FadeSeconds
	)
	if which ~= kind then
		return -- the intro fading out under the loop, or a one-shot that is over
	end
	local loopLength = row.Length
	if kind == "Loop" and row.Parts then
		local now, into = EmoteSync.partAt(row, want)
		if now ~= part then
			return -- the part before, fading out, or the next, just started early
		end
		want, loopLength = into, row.Length / #row.Parts
	end
	local length = if track.Length > 0
		then track.Length
		elseif kind == "Loop" then loopLength
		else row.IntroLength or 0
	local looped = kind == "Loop" and row.Once ~= true
	if looped and length > 0 then
		want %= length
	end
	if
		force
		or math.abs(EmoteSync.drift(track.TimePosition, want, length, looped))
			> A.ToleranceSeconds
	then
		track.TimePosition = want
	end
end

-- Watch the dancer's Animator (a new body gets a new one) and seek what plays now.
local function hook(userId: number, w: Watch, force: boolean)
	local animator = animatorOf(userId)
	if animator ~= w.animator then
		if w.link then
			w.link:Disconnect()
			w.link = nil
		end
		w.animator = animator
		if animator then
			w.link = animator.AnimationPlayed:Connect(function(track: AnimationTrack)
				if watched[userId] == w then
					fix(w, track, true)
				end
			end)
		end
	end
	if animator then
		for _, track in animator:GetPlayingAnimationTracks() do
			fix(w, track, force)
		end
	end
end

local function pass()
	running = true
	while next(watched) ~= nil do
		for userId, w in watched do
			if near(userId) then
				hook(userId, w, false)
			end
		end
		task.wait(A.Seconds)
	end
	running = false
end

local function unwatch(userId: number)
	local w = watched[userId]
	if w then
		watched[userId] = nil
		if w.link then
			w.link:Disconnect()
		end
	end
end

--- `userId` dances `id` from server time `at` (nil: stopped): keep their track on the clock.
function EmoteAlign.set(userId: number, id: string?, at: number?)
	unwatch(userId)
	if id == nil or at == nil then
		return
	end
	if not A.Enabled and userId ~= Players.LocalPlayer.UserId then
		return
	end
	local row = EmoteSync.find(E.List, id)
	if row == nil then
		return
	end
	local w: Watch = {
		row = row,
		at = at,
		animator = nil,
		link = nil,
		parts = {},
		intro = if row.Intro then tostring(row.Intro) else nil,
	}
	for index, animation in EmoteSync.animations(row) do
		w.parts[tostring(animation)] = index
	end
	watched[userId] = w
	hook(userId, w, true)
	if not running then
		task.spawn(pass)
	end
end

return EmoteAlign
