--!strict
-- SoundSheet: plays the abilities' sounds (docs/prompts/ABILITIES_PROMPT.md 5.5). Several short
-- sounds are packed into one uploaded file, a sheet: `Config.Ults.Assets.Sheets[sheet]` =
-- { Id, Volume, Clips = { name = { Start, Length, Volume? } } }. A clip plays only its stretch
-- of the file (PlaybackRegionsEnabled with PlaybackRegion Start..Start + Length; a looped clip
-- loops that stretch through LoopRegion). A clip's own Volume, when given, replaces the
-- sheet's; `options.volume` then scales it. `library` plays a plain Config clip
-- { Id, Volume, StartOffset?, Pitch? } the same way (the library fallbacks).
--
-- 2D (in SoundService) when no parent is given, 3D at the given Attachment or part otherwise
-- (the game's roll-off, Config.Audio). Every call makes its own Sound and returns it. A
-- one-shot is destroyed once it has played (or its parent went away); `Ended` is never relied
-- on (STUDIO_NOTES "Audio": it never fires for a looped or stopped Sound), so one shared
-- Heartbeat loop polls TimePosition, with a wall-clock cap behind it. A looped one is the
-- caller's to Destroy (or goes with the parent it was given). A sheet whose Id is still ""
-- (not uploaded yet) plays nothing, silently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local S = Config.UI.AbilityFx.SoundSheet

export type Options = {
	volume: number?, -- a share of the clip's volume (default 1)
	pitch: number?, -- PlaybackSpeed (default 1; a library clip's own Pitch is multiplied in)
	looped: boolean?, -- loop the clip (its region, for a sheet clip) until destroyed
}

type Playing = {
	sound: Sound,
	regionEnd: number?, -- a sheet clip: where its stretch ends (seconds into the file)
	started: number, -- os.clock() at Play
	capAt: number, -- os.clock(): destroyed by now whatever it reports
	heard: boolean, -- it has been seen playing (so stopping now means it is done)
}

local SoundSheet = {}

local playing: { Playing } = {}
local heartbeat: RBXScriptConnection? = nil
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[8ball] SoundSheet: " .. message)
	end
end

local function poll()
	local now = os.clock()
	for i = #playing, 1, -1 do
		local p = playing[i]
		local sound = p.sound
		local done = sound.Parent == nil or now >= p.capAt
		if not done then
			if sound.IsPlaying then
				p.heard = true
			end
			local t = sound.TimePosition
			if p.regionEnd then
				done = p.heard and (t >= p.regionEnd - S.EndEpsilonSeconds or not sound.IsPlaying)
			else
				local length = sound.TimeLength
				done = p.heard
					and ((length > 0 and t >= length - S.EndEpsilonSeconds) or not sound.IsPlaying)
			end
		end
		if done then
			table.remove(playing, i)
			sound:Destroy()
		end
	end
	if #playing == 0 and heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

local function track(p: Playing)
	table.insert(playing, p)
	if heartbeat == nil then
		heartbeat = RunService.Heartbeat:Connect(poll)
	end
end

-- A Sound for `id` under `parent` (3D, with the game's roll-off) or in SoundService (2D).
local function newSound(id: string, volume: number, parent: Instance?, pitch: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = "AbilitySound"
	sound.SoundId = id
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.PlayOnRemove = false
	if parent then
		sound.RollOffMinDistance = Config.Audio.RollOffMinStuds
		sound.RollOffMaxDistance = Config.Audio.RollOffMaxStuds
		sound.RollOffMode = (Enum.RollOffMode :: any)[Config.Audio.RollOffMode]
	end
	sound.Parent = parent or SoundService
	return sound
end

--- Play clip `clip` of sheet `sheet` (Config.Ults.Assets.Sheets). 2D without `parent`, 3D at
--- `parent` (an Attachment or a part) with it. Returns the Sound, or nil when the sheet is not
--- uploaded yet or the clip is unknown. A one-shot destroys itself when done; a looped one
--- plays until the caller destroys it (or its parent goes).
function SoundSheet.play(sheet: string, clip: string, parent: Instance?, options: Options?): Sound?
	local row = (Config.Ults.Assets.Sheets :: any)[sheet]
	if row == nil or row.Id == nil or row.Id == "" then
		return nil
	end
	local c = row.Clips and row.Clips[clip]
	if c == nil then
		warnOnce(sheet .. "/" .. clip, ("no clip %q in sheet %q"):format(clip, sheet))
		return nil
	end
	local o: Options = options or {}
	local pitch = math.max(o.pitch or 1, 0.01)
	local volume = (c.Volume or row.Volume or 1) * (o.volume or 1)
	local sound = newSound(row.Id, volume, parent, pitch)
	local region = NumberRange.new(c.Start, c.Start + c.Length)
	sound.PlaybackRegionsEnabled = true
	sound.PlaybackRegion = region
	if o.looped then
		sound.Looped = true
		sound.LoopRegion = region
	end
	-- A fresh Sound starts at 0; the region's start is written anyway (Play() resumes from
	-- the last TimePosition written, STUDIO_NOTES "Audio").
	sound.TimePosition = c.Start
	sound:Play()
	if not o.looped then
		local now = os.clock()
		track({
			sound = sound,
			regionEnd = c.Start + c.Length,
			started = now,
			capAt = now + c.Length / pitch + S.LoadGraceSeconds,
			heard = false,
		})
	end
	return sound
end

--- Play a plain Config clip { Id, Volume, StartOffset?, Pitch?, Length? } the same way (a
--- library fallback): 2D or 3D, one-shot or looped, the Sound returned. Nothing for an Id of
--- "". With Length only that much plays from StartOffset (one part of a longer file).
function SoundSheet.library(clip: any, parent: Instance?, options: Options?): Sound?
	if type(clip) ~= "table" or type(clip.Id) ~= "string" or clip.Id == "" then
		return nil
	end
	local o: Options = options or {}
	local pitch = math.max((clip.Pitch or 1) * (o.pitch or 1), 0.01)
	local sound = newSound(clip.Id, (clip.Volume or 1) * (o.volume or 1), parent, pitch)
	local start = clip.StartOffset or 0
	local regionEnd: number? = nil
	if type(clip.Length) == "number" and clip.Length > 0 then
		regionEnd = start + clip.Length
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = NumberRange.new(start, start + clip.Length)
		if o.looped then
			sound.LoopRegion = sound.PlaybackRegion
		end
	end
	sound.Looped = o.looped == true
	sound.TimePosition = start
	sound:Play()
	if not o.looped then
		local now = os.clock()
		track({
			sound = sound,
			regionEnd = regionEnd,
			started = now,
			capAt = now + S.LibraryMaxSeconds,
			heard = false,
		})
	end
	return sound
end

--- Fetch these sheets' files now (every sheet when `sheets` is nil), so an ability's first
--- sound is not late. Never blocks the caller.
function SoundSheet.preload(sheets: { string }?)
	local all = Config.Ults.Assets.Sheets :: any
	local names: { string } = {}
	if sheets then
		names = sheets
	else
		for name in all do
			table.insert(names, name)
		end
	end
	local list: { any } = {}
	for _, name in names do
		local row = all[name]
		if row and type(row.Id) == "string" and row.Id ~= "" then
			local sound = Instance.new("Sound")
			sound.SoundId = row.Id
			table.insert(list, sound)
		end
	end
	if #list == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync(list)
		end)
		for _, sound in list do
			sound:Destroy()
		end
	end)
end

--- Stop and destroy every one-shot still playing (a table's effects cleared at once).
function SoundSheet.stopAll()
	for _, p in playing do
		p.sound:Destroy()
	end
	table.clear(playing)
	if heartbeat then
		heartbeat:Disconnect()
		heartbeat = nil
	end
end

return SoundSheet
