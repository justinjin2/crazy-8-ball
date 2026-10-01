--!strict
-- FallGuard: anyone who drops below the floor is put back at the spawn at once, before they
-- fall far or die (designer, 2026-10-01: a player fell under the map after a match). It is
-- the last resort; TableService keeps bodies out of the floor in the first place and puts a
-- player in a match back at their own table first (QueueVisual.FallTolerance, a smaller
-- drop than this one).
--
-- The floor is the lowest of the spawn and every table's floor (the lobby is a roof, nothing
-- walkable lies below it). Every Config.FallGuard.CheckSeconds each player's root is looked
-- at; one more than BelowFloorStuds below that floor is moved to the spawn, RiseStuds above
-- it, its fall stopped.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))

local G = Config.FallGuard

local FallGuard = {}

-- The lowest walkable floor: the spawn's and every table's.
local function floorY(spawn: CFrame): number
	local y = spawn.Position.Y
	for id = 1, Placement.tableCount() do
		local p = Placement.forTable(id)
		if p then
			y = math.min(y, p.y)
		end
	end
	return y
end

-- Where a fallen player is put: on the SpawnLocation (Bootstrap places it), else the Config
-- spawn.
local function spawnFrame(): CFrame
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation")
	if spawn then
		return spawn.CFrame
	end
	local s = Config.Multiplayer.Spawn
	return CFrame.new(s.X, s.Y, s.Z) * CFrame.Angles(0, math.rad(s.YawDegrees), 0)
end

local function rescue(character: Model, root: BasePart, at: CFrame)
	character:PivotTo(at * CFrame.new(0, G.RiseStuds, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

--- Start watching every player (server, once).
function FallGuard.start()
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since < G.CheckSeconds then
			return
		end
		since = 0
		local at = spawnFrame()
		local lowest = floorY(at) - G.BelowFloorStuds
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local hum = character and character:FindFirstChildOfClass("Humanoid")
			if
				character
				and root
				and root:IsA("BasePart")
				and hum
				and hum.Health > 0
				and not root.Anchored
				and root.Position.Y < lowest
			then
				rescue(character, root, at)
			end
		end
	end)
end

return FallGuard
