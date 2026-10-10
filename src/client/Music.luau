--!strict
-- Music: the background music (designer, 2026-10-10; Config.Music). The anchor track plays
-- first, then the list cycles in order, forever, each fading in, with a short gap between. It
-- plays in the "Music" sound group, which the Settings row turns on and off (SettingsState), so
-- the Sound effects switch never silences it. A track that won't load is skipped.
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local SoundGroups = require(script.Parent.SoundGroups)

local M = Config.Music

local Music = {}

local started = false

-- Plays `id` to its end (or skips it when it won't load).
local function playOne(id: string)
	local sound = Instance.new("Sound")
	sound.Name = "8ballMusic"
	sound.SoundId = id
	sound.Volume = 0
	sound.Looped = false
	sound.SoundGroup = SoundGroups.get("Music") -- before parenting: never adopted into Sfx
	sound.Parent = SoundService
	pcall(function()
		ContentProvider:PreloadAsync({ sound })
	end)
	local waited = 0
	while not sound.IsLoaded and waited < M.LoadTimeoutSeconds do
		waited += task.wait(0.25)
	end
	if not sound.IsLoaded then
		warn("[8ball] Music: could not load " .. id)
		sound:Destroy()
		return
	end
	sound:Play()
	TweenService:Create(sound, TweenInfo.new(M.FadeInSeconds), { Volume = M.Volume }):Play()
	sound.Ended:Wait()
	sound:Destroy()
end

--- Starts the music (once).
function Music.start()
	if started or #M.Tracks == 0 then
		return
	end
	started = true
	task.spawn(function()
		local i = 1
		while true do
			playOne(M.Tracks[i])
			task.wait(M.GapSeconds)
			i = i % #M.Tracks + 1
		end
	end)
end

return Music
