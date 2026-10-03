--!strict
-- SoundGroups: the volume group behind Settings (GUI lane, designer 2026-10-03, C10): "Sfx"
-- (every sound effect: the UI, the table, the abilities, the map). Every Sound that turns up
-- without a group in the places the game's sounds live (the workspace, SoundService, the
-- player's GUI and scripts, ReplicatedStorage) joins Sfx. The group is local to this client,
-- so switching it off silences only this player's game. (The lobby music was dropped by the
-- designer, 2026-10-03.)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local SoundGroups = {}

local started = false
local groups: { [string]: SoundGroup } = {}

local function group(name: string): SoundGroup
	local found = groups[name]
	if found then
		return found
	end
	local made = Instance.new("SoundGroup")
	made.Name = "8ball" .. name
	made.Volume = 1
	made.Parent = SoundService
	groups[name] = made
	return made
end

--- The "Sfx" group.
function SoundGroups.get(name: string): SoundGroup
	return group(name)
end

--- Turn a group on (full volume) or off (silent).
function SoundGroups.setOn(name: string, on: boolean)
	group(name).Volume = if on then 1 else 0
end

local function adopt(instance: Instance)
	if instance:IsA("Sound") and instance.SoundGroup == nil then
		instance.SoundGroup = group("Sfx")
	end
end

--- Put every grouped-less sound into Sfx, now and from now on.
function SoundGroups.start()
	if started then
		return
	end
	started = true
	group("Sfx")
	local roots: { Instance } = { workspace, SoundService, ReplicatedStorage }
	local player = Players.LocalPlayer
	if player then
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if gui then
			table.insert(roots, gui)
		end
		local scripts = player:FindFirstChild("PlayerScripts")
		if scripts then
			table.insert(roots, scripts)
		end
	end
	for _, root in roots do
		root.DescendantAdded:Connect(adopt)
		for _, instance in root:GetDescendants() do
			adopt(instance)
		end
	end
end

return SoundGroups
