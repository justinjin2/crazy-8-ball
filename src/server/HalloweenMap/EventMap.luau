--!strict
-- EventMap (Halloween 2026, hw-map lane): the Haunted Rooftop's switch. Follows core's
-- Event.state on the server clock (Clock.now carries core's test offset; in Studio only, the
-- workspace attribute Config.HalloweenMap.ForceAttribute can force a state) and publishes it
-- as the workspace attributes StateAttribute and FlipAtAttribute, which every client follows
-- (the light, the King's prompt, the FX), so server and clients always agree.
--
-- While Live, each part below is on (when its own switch is): the tables' event looks by mode
-- and their decor kit, the props and the hides, the throne. Leaving Live undoes them in
-- reverse. Every step is pcall-wrapped and idempotent (on twice changes nothing). Off (does
-- nothing at all) while Config.HalloweenMap.Enabled is. Other modules add their parts with
-- EventMap.addPart (the throne: BossService, after start; addPart turns it on by itself when it
-- comes while Live, and each part's build runs once however often it is asked: HalloweenMap.Once).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local Assets = require(script.Parent:WaitForChild("Assets"))
local MapProps = require(script.Parent:WaitForChild("MapProps"))

local HM = Config.HalloweenMap

local EventMap = {}

export type Part = {
	name: string,
	enabled: () -> boolean,
	on: () -> (),
	off: () -> (),
	arena: boolean?, -- also in an arena (the tables' looks)
}

local parts: { Part } = {}
local current: Rules.State? = nil
local isArenaServer = false
local warned: { [string]: boolean } = {}

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn("[HalloweenMap] " .. message)
	end
end

local function run(name: string, step: string, fn: () -> ())
	local ok, err = pcall(function()
		fn()
	end)
	if not ok then
		warn(("[HalloweenMap] %s %s failed: %s"):format(name, step, tostring(err)))
	end
end

--- Add a part turned on while Live and off after (in reverse order of adding). Added while
--- already Live, it turns on at once in its own thread (an on may wait for meshes, and the
--- caller, Bootstrap, must not wait with it).
function EventMap.addPart(part: Part)
	table.insert(parts, part)
	if current == "Live" and (part.arena or not isArenaServer) and part.enabled() then
		task.spawn(run, part.name, "on", part.on)
	end
end

--- The map's state now (the attribute the clients follow).
function EventMap.state(): Rules.State
	return current or "Before"
end

--- True while the event is Live on this server.
function EventMap.isLive(): boolean
	return current == "Live"
end

-- Core's Event.state(Clock.now()), or nil while core's modules are missing (the map stays
-- today's) or fail.
local function eventState(): string?
	local folder = Shared:FindFirstChild("Halloween")
	local event = folder and folder:FindFirstChild("Event")
	local clock = folder and folder:FindFirstChild("Clock")
	if not (event and clock and event:IsA("ModuleScript") and clock:IsA("ModuleScript")) then
		if RunService:IsStudio() then
			warnOnce(
				"event",
				"core's Shared.Halloween.Event or Clock is missing: the map follows only the Studio force"
			)
		end
		return nil
	end
	local ok, result = pcall(function()
		return (require(event) :: any).state((require(clock) :: any).now())
	end)
	if not ok then
		warnOnce("eventError", "Event.state failed: " .. tostring(result))
		return nil
	end
	return result
end

-- The parts as they are now: a part added while this pass waits on a mesh load is turned on
-- by addPart, never a second time by this pass.
local function turnOn()
	for _, part in table.clone(parts) do
		if (part.arena or not isArenaServer) and part.enabled() then
			run(part.name, "on", part.on)
		end
	end
end

local function turnOff()
	for i = #parts, 1, -1 do
		local part = parts[i]
		run(part.name, "off", part.off)
	end
end

-- The tables: the black-frame look with each mode's cloth tint (Config.HalloweenMap.Tables),
-- the template look back after. Only a SurfaceAppearance's Color changes on the cloth (no new
-- images, no new mesh); the physics never sees any of it.
local function tableModels(): { Model }
	local out: { Model } = {}
	local folder = workspace:FindFirstChild(TableBuilder.FolderName)
	if folder then
		for _, model in folder:GetChildren() do
			if model:IsA("Model") and model.Name:match("^Table_%d+$") then
				table.insert(out, model)
			end
		end
	end
	return out
end

local function tableId(model: Model): number
	return tonumber(model.Name:match("^Table_(%d+)$")) or 0
end

-- The mode of a table: its Config.Hub.Tables row, or an arena's team size.
local function teamSize(model: Model): number
	if isArenaServer then
		local size = workspace:GetAttribute(Config.Arena.TeamSizeAttribute)
		if type(size) == "number" and HM.Tables.ByTeamSize[size] then
			return size
		end
	end
	return (Rules.tableLook(tableId(model)))
end

local function clothOf(model: Model): SurfaceAppearance?
	for _, inst in model:GetDescendants() do
		if inst.Name == "Cloth" and inst:IsA("BasePart") then
			return inst:FindFirstChildOfClass("SurfaceAppearance")
		end
	end
	return nil
end

--- The event look on one table (also used for a table built while Live).
function EventMap.relook(model: Model)
	TableBuilder.applyLook(model, HM.Tables.Base)
	local rgb = HM.Tables.ByTeamSize[teamSize(model)].Cloth
	local cloth = clothOf(model)
	if cloth then
		cloth.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	else
		warnOnce("cloth", "a table has no Cloth SurfaceAppearance: its event tint is skipped")
	end
	model:SetAttribute("HalloweenLook", true)
end

local function restoreLook(model: Model)
	if model:GetAttribute("HalloweenLook") then
		local look = if isArenaServer
			then Config.Arena.Look
			else TableBuilder.lookFor(tableId(model))
		TableBuilder.applyLook(model, look)
		model:SetAttribute("HalloweenLook", nil)
	end
end

EventMap.addPart({
	name = "Tables",
	arena = true,
	enabled = function(): boolean
		return HM.Tables.Enabled
	end,
	on = function()
		for _, model in tableModels() do
			EventMap.relook(model)
		end
	end,
	off = function()
		for _, model in tableModels() do
			restoreLook(model)
		end
	end,
})

-- The haunted kit on every table by its mode (Config.HalloweenMap.Decor, TableBuilder.addDecor),
-- once the event's meshes are in: it waits for them in the background, so no other part waits,
-- and a kit whose wait outlives Live is never added. Off takes every kit away.
local decorToken = 0
EventMap.addPart({
	name = "Decor",
	arena = true,
	enabled = function(): boolean
		return HM.Decor.Enabled
	end,
	on = function()
		decorToken += 1
		local token = decorToken
		task.spawn(function()
			Assets.wait()
			if token ~= decorToken or current ~= "Live" then
				return
			end
			for _, model in tableModels() do
				local row = HM.Tables.ByTeamSize[teamSize(model)]
				local ok, err = pcall(TableBuilder.addDecor, model, row and row.Kit)
				if not ok then
					warnOnce("decor", "a table's decor kit failed: " .. tostring(err))
				end
			end
		end)
	end,
	off = function()
		decorToken += 1
		for _, model in tableModels() do
			TableBuilder.addDecor(model, nil)
		end
	end,
})

-- The rooftop's props and hides (MapProps; the lobby only).
EventMap.addPart(MapProps.part())

local function setState(state: Rules.State)
	if state == current then
		return
	end
	local actions = Rules.actions(current, state)
	-- A server booting into a state shows it at once (FlipAt 0: no fade on the clients).
	local flipAt = if current == nil then 0 else workspace:GetServerTimeNow()
	current = state
	workspace:SetAttribute(HM.FlipAtAttribute, flipAt)
	workspace:SetAttribute(HM.StateAttribute, state)
	if actions.on then
		turnOn()
	elseif actions.off then
		turnOff()
	end
end

--- Start following the event (once, from Bootstrap, after the tables are built). isArena: an
--- arena's server (the light and the table looks only).
function EventMap.start(isArena: boolean)
	if not HM.Enabled then
		return
	end
	isArenaServer = isArena
	Assets.start() -- the event's meshes, loaded in the background
	task.spawn(function()
		while true do
			local state = Rules.mapState(
				eventState(),
				workspace:GetAttribute(HM.ForceAttribute),
				RunService:IsStudio()
			)
			setState(state :: any)
			task.wait(HM.PollSeconds)
		end
	end)
end

return EventMap
