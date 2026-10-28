--!strict
-- DayCycle: the map's day and sunset cycle on this client (Config.Lighting). The server's clock
-- sets where the cycle is (LightCycle.blend), so every player sees the same light with nothing
-- sent over the network. MapLighting writes the state onto the place: every frame of a fade,
-- once per hold. Visual only, and it needs no input, so it works the same on phone,
-- PC and gamepad.
--
-- The map streams in (StreamingEnabled): a lantern or light arriving mid-sunset would keep the
-- look it was saved with, so any relevant arrival makes the next tick look again and rewrite
-- everything; while parts are missing it looks every Cycle.Look seconds.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LightCycle = require(Shared:WaitForChild("LightCycle"))
local MapLighting = require(Shared:WaitForChild("MapLighting"))

local L = Config.Lighting
local C = L.Cycle

local DayCycle = {}
DayCycle.__index = DayCycle

-- A cutscene that owns the sky and light (PullCutscene) holds the cycle; on release every
-- value is written again, so nothing it changed stays behind.
local holds = 0
local rewrite = false

--- Hold the cycle still until the returned release runs (once).
function DayCycle.hold(): () -> ()
	holds += 1
	local released = false
	return function()
		if released then
			return
		end
		released = true
		holds -= 1
		rewrite = true
	end
end

export type DayCycle = typeof(setmetatable(
	{} :: {
		handles: MapLighting.Handles?,
		last: { [string]: any }?,
		blend: number?,
		fire: number, -- the fire pit's intensity in the light now (Config.Lighting's Fire)
		nextLook: number,
		dirty: boolean,
		watched: Instance?,
		watch: RBXScriptConnection?,
		watchedTables: Instance?,
		watchTables: RBXScriptConnection?,
		-- The lighting followed (Config.Lighting, or an event's: setLighting), the last state
		-- written, and a crossfade from it after a change.
		lighting: any,
		state: { [string]: any }?,
		fade: { from: { [string]: any }, start: number, seconds: number }?,
	},
	DayCycle
))

function DayCycle.new(): DayCycle
	-- Load both skies' faces up front, so the swap never shows a face still loading.
	task.spawn(function()
		local ids: { string } = {}
		local skies: { { [string]: any } } = { L.Day.Sky, L.DuskSky, L.Sunset.Sky }
		for _, sky in skies do
			for key: string, id in sky :: { [string]: any } do
				if key:match("^Skybox") then
					table.insert(ids, id)
				end
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(ids)
		end)
	end)
	return setmetatable({
		handles = nil :: MapLighting.Handles?,
		last = nil :: { [string]: any }?,
		blend = nil :: number?,
		fire = 0,
		nextLook = 0,
		dirty = true,
		watched = nil :: Instance?,
		watch = nil :: RBXScriptConnection?,
		watchedTables = nil :: Instance?,
		watchTables = nil :: RBXScriptConnection?,
		lighting = L,
		state = nil :: { [string]: any }?,
		fade = nil :: { from: { [string]: any }, start: number, seconds: number }?,
	}, DayCycle)
end

--- Follow another lighting table (the Halloween event's LightCycle.event, or nil for
--- Config.Lighting again), crossfading from the light shown now over `seconds` (0: at once).
function DayCycle.setLighting(self: DayCycle, lighting: any?, seconds: number)
	local target = lighting or L
	if target == self.lighting then
		return
	end
	self.lighting = target
	self.fade = if self.state and seconds > 0
		then { from = self.state, start = os.clock(), seconds = seconds }
		else nil
	self.last = nil -- write everything for the new light
end

-- Finds the map's glow, light and emissive parts and the tables' lamps again, and watches the
-- map and the tables for more (both stream in).
function DayCycle.look(self: DayCycle, now: number)
	self.nextLook = now + C.Look
	self.dirty = false
	self.handles = MapLighting.collect(Config.Map)
	self.last = nil -- write everything to what was found
	local map = workspace:FindFirstChild(Config.Map.Name)
	if map ~= self.watched then
		if self.watch then
			self.watch:Disconnect()
		end
		self.watched = map
		self.watch = if map
			then map.DescendantAdded:Connect(function(inst)
				if MapLighting.relevant(inst) then
					self.dirty = true
				end
			end)
			else nil
	end
	local tables = workspace:FindFirstChild(Config.Map.Tables)
	if tables ~= self.watchedTables then
		if self.watchTables then
			self.watchTables:Disconnect()
		end
		self.watchedTables = tables
		self.watchTables = if tables
			then tables.DescendantAdded:Connect(function(inst)
				if MapLighting.relevant(inst) then
					self.dirty = true
				end
			end)
			else nil
	end
end

function DayCycle.update(self: DayCycle, now: number)
	if holds > 0 then
		return
	end
	if rewrite then
		rewrite = false
		self.last = nil
	end
	local handles = self.handles
	if self.dirty or handles == nil or (not handles.complete and now >= self.nextLook) then
		self:look(now)
	end
	-- An arena's offset starts its cycle at day (ArenaService); the /day, /sunset and /cycle
	-- developer commands hold the light for everyone (DevCommands).
	local offset = workspace:GetAttribute(C.OffsetAttribute)
	local t = workspace:GetServerTimeNow() * C.Speed
		+ (if type(offset) == "number" then offset else 0)
	local A = C.Hold
	local hold = LightCycle.readHold(
		workspace:GetAttribute(A.Goal),
		workspace:GetAttribute(A.From),
		workspace:GetAttribute(A.At)
	)
	local blend = LightCycle.shown(t, C, hold)
	-- A fade is written every frame (at 12 a second it stepped visibly, designer 2026-10-05).
	local fade = self.fade
	if self.last ~= nil and blend == self.blend and fade == nil then
		return
	end
	self.blend = blend
	local found = self.handles
	assert(found, "looked above")
	local state = LightCycle.state(blend, self.lighting)
	if fade then
		local k = math.clamp((now - fade.start) / fade.seconds, 0, 1)
		if k < 1 then
			state = LightCycle.mixStates(fade.from, state, k * k * (3 - 2 * k))
		else
			self.fade = nil
			self.last = nil -- the crossfade's end: write everything once more
		end
	end
	self.state = state
	self.fire = state.Fire.Intensity
	self.last = MapLighting.apply(state, found, self.last)
end

return DayCycle
