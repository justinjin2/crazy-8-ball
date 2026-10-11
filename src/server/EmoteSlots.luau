--!strict
-- EmoteSlots: the emote wheel works for everyone (designer, 2026-10-11). Roblox's wheel says
-- "Emotes are disabled in this experience" when a character has no emote in its slots, so on
-- each spawn a character that owns emotes but has none in a slot gets them put in (EmotePick,
-- Config.Emotes): straight on the HumanoidDescription Roblox applied, which the wheel reads,
-- with no avatar reload. A player who chose their own slots keeps them. Off with
-- Config.Emotes.FillEmptySlots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmotePick = require(Shared:WaitForChild("EmotePick"))

local E = Config.Emotes

local EmoteSlots = {}

local function fill(character: Model)
	local humanoid = character:WaitForChild("Humanoid", E.WaitSeconds)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	local description = humanoid:WaitForChild("HumanoidDescription", E.WaitSeconds)
	if not description or not description:IsA("HumanoidDescription") then
		return
	end
	local ok, err = pcall(function()
		local owned: { string } = {}
		for name in description:GetEmotes() do
			table.insert(owned, name)
		end
		local slots = EmotePick.fill(owned, #description:GetEquippedEmotes(), E.Slots)
		if slots then
			description:SetEquippedEmotes(slots :: any)
		end
	end)
	if not ok then
		warn("[8ball] EmoteSlots: " .. tostring(err))
	end
end

local function watch(player: Player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(fill, character)
	end)
	if player.Character then
		task.spawn(fill, player.Character)
	end
end

--- Fill each spawning character's empty emote slots (server, once).
function EmoteSlots.start()
	if not E.FillEmptySlots then
		return
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return EmoteSlots
