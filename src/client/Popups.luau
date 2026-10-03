--!strict
-- Popups: the queue of join and reward popups (GUI lane, designer 2026-10-03, C8): one at a
-- time, never in a match, never while the tutorial runs (the player attribute TutorialActive,
-- set by the Tutorial lane), never over a full menu, the result screen or the case opening
-- (Progression's gate). A popup waits in the queue until the gate opens, then shows; it calls
-- `done` when it closes and the next one may show.
local Players = game:GetService("Players")

local Popups = {}

export type Entry = {
	id: string, -- one entry per id in the queue at a time
	show: (done: () -> ()) -> (),
}

local queue: { Entry } = {}
local showing: string? = nil
local gate: () -> boolean = function()
	return true
end
local polling = false

local function allowed(): boolean
	local player = Players.LocalPlayer
	if player and player:GetAttribute("TutorialActive") == true then
		return false
	end
	return gate()
end

local function pump()
	if polling then
		return
	end
	polling = true
	task.spawn(function()
		while #queue > 0 do
			if showing == nil and allowed() then
				local entry = table.remove(queue, 1) :: Entry
				showing = entry.id
				local finished = false
				local ok, err = pcall(function()
					entry.show(function()
						if not finished then
							finished = true
							showing = nil
						end
					end)
				end)
				if not ok then
					warn("[8ball] popup " .. entry.id .. " failed: " .. tostring(err))
					showing = nil
				end
			end
			task.wait(0.5)
		end
		polling = false
	end)
end

--- Progression's say: true while a popup may show (the hub, nothing else up).
function Popups.setGate(fn: () -> boolean)
	gate = fn
end

--- Queue a popup (a second one with the same id while the first waits is dropped).
function Popups.push(entry: Entry)
	if showing == entry.id then
		return
	end
	for _, waiting in queue do
		if waiting.id == entry.id then
			return
		end
	end
	table.insert(queue, entry)
	pump()
end

--- Whether a popup is up now.
function Popups.isShowing(): boolean
	return showing ~= nil
end

return Popups
