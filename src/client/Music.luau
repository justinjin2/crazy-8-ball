--!strict
-- Music: the lobby music (GUI lane, designer 2026-10-03, C10). Config.Audio.Music's tracks
-- (Roblox's licensed APM library) play one after another in a shuffled order with a short
-- silence between them, quieter while the player is in a match (Progression tells it), in the
-- "Music" sound group (Settings' Music switch silences the group).
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local SoundGroups = require(script.Parent.SoundGroups)

local M = Config.Audio.Music

local Music = {}

local started = false
local inMatch = false
local sound: Sound? = nil

local function target(): number
	return if inMatch then M.MatchVolume else M.Volume
end

local function fadeTo(volume: number)
	local s = sound
	if s then
		TweenService:Create(s, TweenInfo.new(M.FadeSeconds), { Volume = volume }):Play()
	end
end

--- In a match the music is quieter.
function Music.setInMatch(on: boolean)
	if inMatch == on then
		return
	end
	inMatch = on
	fadeTo(target())
end

--- Start playing (once).
function Music.start()
	if started or #M.Tracks == 0 then
		return
	end
	started = true
	local s = Instance.new("Sound")
	s.Name = "LobbyMusic"
	s.SoundGroup = SoundGroups.get("Music")
	s.Volume = 0
	s.Parent = SoundService
	sound = s
	task.spawn(function()
		local random = Random.new()
		local order: { string } = table.clone(M.Tracks)
		local index = #order
		while true do
			index += 1
			if index > #order then
				-- A new shuffle, never starting on the track that just ended.
				local last = order[#order]
				for i = #order, 2, -1 do
					local j = random:NextInteger(1, i)
					order[i], order[j] = order[j], order[i]
				end
				if #order > 1 and order[1] == last then
					order[1], order[2] = order[2], order[1]
				end
				index = 1
			end
			s.SoundId = order[index]
			s.TimePosition = 0
			s.Volume = 0
			s:Play()
			fadeTo(target())
			s.Ended:Wait()
			task.wait(M.GapSeconds)
		end
	end)
end

return Music
