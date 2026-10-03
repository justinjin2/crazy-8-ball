--!strict
-- Quality: the Lower effects setting (Settings; designer, 2026-10-03). Weaker devices get fewer
-- particles, thinner auras and calmer UI loops, never none. Every particle rate (CueVfx,
-- UltAura) and the UI's looping effects (UIAnim) read the one multiplier here, so one switch
-- lowers them all. Settings calls `set` when the saved choice arrives or changes.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Quality = {}

local low = false
local changed = Instance.new("BindableEvent")

--- Fires with the new value (true = lower effects) when the setting changes.
Quality.Changed = changed.Event

function Quality.isLow(): boolean
	return low
end

function Quality.set(on: boolean)
	if low == on then
		return
	end
	low = on
	changed:Fire(on)
end

--- The multiplier for particle rates and effect counts: 1 normally, Config.UI.Quality.LowRate
--- with Lower effects (never 0).
function Quality.rate(): number
	return if low then Config.UI.Quality.LowRate else 1
end

return Quality
