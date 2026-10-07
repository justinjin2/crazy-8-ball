--!strict
-- SettingsState: this player's switches on the client (GUI lane, designer 2026-10-03, C10). It
-- keeps the server's SettingsState (Config.Settings.Defaults until it arrives), applies them
-- (the Sfx sound group, Quality's Lower effects) and saves a change through
-- SettingsRequest (shown at once, put back if the server refuses). It also gives Seen the
-- saved "seen" moments, so a cutscene seen in an earlier session can be skipped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Quality = require(script.Parent.Quality)
local Seen = require(script.Parent.Seen)
local SoundGroups = require(script.Parent.SoundGroups)

local C = Config.Settings

local SettingsState = {}

local current: { [string]: boolean } = table.clone(C.Defaults)
local seen: { [string]: boolean } = {}
local started = false
local loaded = false -- the server's state has arrived at least once
local changed = Instance.new("BindableEvent")

--- Fires after any switch changes (from the server or a press).
SettingsState.Changed = changed.Event

local function apply()
	SoundGroups.setOn("Sfx", current.Sfx ~= false)
	Quality.set(current.LowFx == true)
end

--- Whether the saved switches have arrived (until then `get` answers the defaults).
function SettingsState.loaded(): boolean
	return loaded
end

function SettingsState.get(key: string): boolean
	return current[key] == true
end

--- Flip a switch: shown and applied at once, saved on the server.
function SettingsState.set(key: string, value: boolean)
	if C.Defaults[key] == nil or current[key] == value then
		return
	end
	current[key] = value
	apply()
	changed:Fire()
	task.spawn(function()
		local ok, reply = pcall(function(): any
			return Net.get("SettingsRequest"):InvokeServer("Set", key, value)
		end)
		if not ok or type(reply) ~= "table" or reply.ok ~= true then
			-- Refused (too fast, or not loaded): the next state puts it right; until then, undo.
			current[key] = not value
			apply()
			changed:Fire()
		end
	end)
end

function SettingsState.start()
	if started then
		return
	end
	started = true
	SoundGroups.start()
	apply()
	Seen.setStore(function(kind: string): boolean
		return seen[kind] == true
	end, function(kind: string)
		if seen[kind] or not table.find(C.SeenKinds, kind) then
			return
		end
		seen[kind] = true
		task.spawn(function()
			pcall(function()
				Net.get("SettingsRequest"):InvokeServer("Seen", kind)
			end)
		end)
	end)
	Net.get("SettingsState").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if type(payload.settings) == "table" then
			loaded = true
			for key in C.Defaults do
				local value = payload.settings[key]
				if type(value) == "boolean" then
					current[key] = value
				end
			end
		end
		if type(payload.seen) == "table" then
			for _, kind in C.SeenKinds do
				if payload.seen[kind] == true then
					seen[kind] = true
				end
			end
		end
		apply()
		changed:Fire()
	end)
end

return SettingsState
