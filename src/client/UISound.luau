--!strict
-- UISound: the interface's own sounds (a cash chip landing, the money and XP ticks, rank-up
-- fanfares, the badge's hover pop, button clicks). Not positional: they belong to the screen,
-- not the table, and sit well under the pool sounds (Config.Audio.Ui). A clip with an empty
-- id plays nothing, so a missing sound never breaks a screen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Clips: { [string]: any } = Config.Audio.Ui
local UISound = {}

local sounds: { [string]: Sound } = {}
local folder: Folder? = nil

local function soundFor(key: string): Sound?
	local clip = Clips[key]
	if not clip or clip.Id == "" then
		return nil
	end
	local sound = sounds[key]
	if sound then
		return sound
	end
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "UISounds"
		f.Parent = SoundService
		folder = f
	end
	local made = Instance.new("Sound")
	made.Name = key
	made.SoundId = clip.Id
	made.Volume = clip.Volume
	made.Looped = clip.Looped == true
	made.Parent = folder
	sounds[key] = made
	return made
end

--- Play a UI sound by its Config.Audio.Ui key. `pitch` scales its speed on top of the clip's
--- own Pitch (1 = as recorded); `volume` scales its level (1 = the configured volume).
function UISound.play(key: string, pitch: number?, volume: number?)
	local sound = soundFor(key)
	if not sound then
		return
	end
	local clip = Clips[key]
	pitch = (pitch or 1) * (clip.Pitch or 1)
	if clip.Overlap then
		local copy = sound:Clone()
		copy.PlaybackSpeed = pitch or 1
		copy.Volume = clip.Volume * (volume or 1)
		copy.Parent = sound.Parent
		copy.Ended:Once(function()
			copy:Destroy()
		end)
		copy:Play()
		task.delay(10, function()
			if copy.Parent then
				copy:Destroy()
			end
		end)
	else
		sound.PlaybackSpeed = pitch or 1
		sound.Volume = clip.Volume * (volume or 1)
		sound:SetAttribute("FadeStamp", nil) -- a taper under way is cancelled
		sound:Stop() -- Play() alone does not rewind (docs/STUDIO_NOTES.md, Audio)
		sound:Play()
	end
end

--- Stop a UI sound that is playing (not an Overlap one's copies): a cutscene cut short.
function UISound.stop(key: string)
	local sound = sounds[key]
	if sound then
		sound:Stop()
	end
end

--- Let a playing UI sound (not an Overlap one's copies) play on for `after` seconds, then
--- taper it away over `seconds` and stop it. A Play in the meantime cancels the taper.
function UISound.fadeOut(key: string, after: number, seconds: number)
	local sound = sounds[key]
	if not sound or not sound.IsPlaying then
		return
	end
	local from = sound.Volume
	local stamp = os.clock()
	sound:SetAttribute("FadeStamp", stamp)
	task.delay(after, function()
		local started = os.clock()
		while sound.Parent and sound:GetAttribute("FadeStamp") == stamp do
			local u = (os.clock() - started) / math.max(seconds, 1e-3)
			if u >= 1 then
				sound:Stop()
				sound.Volume = from
				return
			end
			sound.Volume = from * (1 - u)
			task.wait()
		end
	end)
end

--- Where a UI sound is in its clip (seconds) and whether it is playing: a cutscene keeping
--- to its track's clock.
function UISound.position(key: string): (number, boolean)
	local sound = sounds[key]
	if sound then
		return sound.TimePosition, sound.IsPlaying
	end
	return 0, false
end

--- Load every UI sound now, so the first chip does not land in silence.
function UISound.preload()
	for key: string in Clips do
		soundFor(key)
	end
end

return UISound
