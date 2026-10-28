--!strict
-- State: the client's copy of the player's Halloween event (hw-core; the server's CandyService
-- pushes it on the Halloween remote). Every Halloween screen reads it:
--   State.on()       the event may show for this player (the HwOn attribute: the save loaded,
--                    the event switched on, the tutorial Done or Skipped)
--   State.view()     the last view pushed (nil before the first)
--   State.phase()    Event.state(Clock.now()), "Before" while State.on() is false
--   State.Changed    fires (view) when a new view arrives or HwOn changes
--   State.Moment     fires (moment) for { toast = {...} }, { step = n }, { spider = true }
--   State.send(msg)  { claim = key } | { seen = true } | { endSeen = true }
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)

local State = {}

local changedEvent = Instance.new("BindableEvent")
local momentEvent = Instance.new("BindableEvent")
State.Changed = changedEvent.Event
State.Moment = momentEvent.Event

local current: any = nil
local started = false

function State.on(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("HwOn") == true
end

function State.view(): any?
	return current
end

-- The event's phase for this player: "Before" until it may show at all.
function State.phase(): Event.State
	if not State.on() then
		return "Before"
	end
	return Event.state(Clock.now())
end

-- The player's Candy (the Candy attribute: earned + bought).
function State.candy(): number
	local player = Players.LocalPlayer
	local candy = player and player:GetAttribute("Candy")
	return if type(candy) == "number" then candy else 0
end

function State.send(msg: { [string]: any })
	Net.get("Halloween"):FireServer(msg)
end

function State.start()
	if started then
		return
	end
	started = true
	Net.get("Halloween").OnClientEvent:Connect(function(msg: any)
		if type(msg) ~= "table" then
			return
		end
		if type(msg.view) == "table" then
			current = msg.view
			changedEvent:Fire(current)
		elseif type(msg.toast) == "table" or type(msg.step) == "number" or msg.spider == true then
			momentEvent:Fire(msg)
		end
	end)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("HwOn"):Connect(function()
			changedEvent:Fire(current)
		end)
	end
end

return State
