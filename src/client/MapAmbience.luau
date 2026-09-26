--!strict
-- MapAmbience: the map's slow ambient motion, local to each client. For now the sailboats
-- below the ocean side drift round their paths (Config.Map.Near.Boat, MapMotion.boatPose),
-- timed by the server's clock so every player sees them in the same places. Visual only: the
-- server's copies stay where MapBuilder left them, nothing is sent over the network, and it
-- needs no input, so it works the same on phone, PC and gamepad.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MapMotion = require(Shared:WaitForChild("MapMotion"))

local M = Config.Map
local BOAT = M.Near.Boat
local LOOK_EVERY = 2 -- seconds between looks for the boats until they have arrived

-- offset: the mesh's own frame from the boat's origin (its waterline, the bow along +Z), set
-- by MapBuilder.prepareNear as the BoatOffset attribute (a MeshPart sits at its bounds' centre).
type Boat = { part: BasePart, path: MapMotion.Path, offset: CFrame }

local MapAmbience = {}
MapAmbience.__index = MapAmbience

export type MapAmbience = typeof(setmetatable(
	{} :: { boats: { Boat }?, nextLook: number },
	MapAmbience
))

function MapAmbience.new(): MapAmbience
	return setmetatable({ boats = nil :: { Boat }?, nextLook = 0 }, MapAmbience)
end

-- The boats in Map.Near.Boats, each with its path (by its BoatIndex attribute). They are a
-- Persistent model, which can arrive after this script starts, so this is called until found.
local function findBoats(): { Boat }?
	local map = workspace:FindFirstChild(M.Name)
	local near = map and map:FindFirstChild(M.Near.Import)
	local folder = near and near:FindFirstChild(BOAT.Folder)
	if not folder then
		return nil
	end
	local boats: { Boat } = {}
	for _, child in folder:GetChildren() do
		local index = child:GetAttribute("BoatIndex")
		local offset = child:GetAttribute("BoatOffset")
		local path = if type(index) == "number" then BOAT.Paths[index] else nil
		if child:IsA("BasePart") and path and typeof(offset) == "CFrame" then
			table.insert(boats, { part = child, path = path, offset = offset })
		end
	end
	return if #boats > 0 then boats else nil
end

function MapAmbience.update(self: MapAmbience, now: number)
	local boats = self.boats
	if boats == nil then
		if now < self.nextLook then
			return
		end
		self.nextLook = now + LOOK_EVERY
		boats = findBoats()
		self.boats = boats
		if boats == nil then
			return
		end
	end
	assert(boats, "boats found above")
	local t = workspace:GetServerTimeNow()
	local parts: { BasePart } = {}
	local frames: { CFrame } = {}
	for _, boat in boats do
		if boat.part.Parent == nil then
			self.boats = nil -- the map was rebuilt: look again
			return
		end
		local pose = MapMotion.boatPose(boat.path, t, BOAT)
		table.insert(parts, boat.part)
		table.insert(
			frames,
			CFrame.new(pose.x, pose.y, pose.z)
				* CFrame.Angles(0, pose.yaw, 0)
				* CFrame.Angles(pose.pitch, 0, pose.roll)
				* boat.offset
		)
	end
	workspace:BulkMoveTo(parts, frames, Enum.BulkMoveMode.FireCFrameChanged)
end

return MapAmbience
