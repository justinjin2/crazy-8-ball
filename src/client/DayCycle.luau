--!strict
-- DayCycle: the map's day and sunset cycle on this client (Config.Lighting). The server's clock
-- sets where the cycle is (LightCycle.blend), so every player sees the same light with nothing
-- sent over the network. MapLighting writes the state onto the place: every tick of a fade (at
-- Cycle.Rate), once per hold. Visual only, and it needs no input, so it works the same on phone,
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

export type DayCycle = typeof(setmetatable(
	{} :: {
		handles: MapLighting.Handles?,
		last: { [string]: any }?,
		blend: number?,
		nextApply: number,
		nextLook: number,
		dirty: boolean,
		watched: Instance?,
		watch: RBXScriptConnection?,
		watchedTables: Instance?,
		watchTables: RBXScriptConnection?,
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
		nextApply = 0,
		nextLook = 0,
		dirty = true,
		watched = nil :: Instance?,
		watch = nil :: RBXScriptConnection?,
		watchedTables = nil :: Instance?,
		watchTables = nil :: RBXScriptConnection?,
	}, DayCycle)
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
	local handles = self.handles
	if self.dirty or handles == nil or (not handles.complete and now >= self.nextLook) then
		self:look(now)
	end
	-- The /day and /sunset developer commands shift the cycle for everyone (DevCommands).
	local offset = workspace:GetAttribute(C.OffsetAttribute)
	local t = workspace:GetServerTimeNow() * C.Speed
		+ (if type(offset) == "number" then offset else 0)
	local blend = LightCycle.blend(t, C)
	if self.last ~= nil and (blend == self.blend or now < self.nextApply) then
		return
	end
	self.nextApply = now + 1 / C.Rate
	self.blend = blend
	local found = self.handles
	assert(found, "looked above")
	self.last = MapLighting.apply(LightCycle.state(blend, L), found, self.last)
end

return DayCycle
