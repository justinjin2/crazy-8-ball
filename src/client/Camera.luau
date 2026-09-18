--!strict
-- Camera: milestone 1 only needs a fixed, high, angled view over the whole table so the
-- shot can be watched. Milestone 4 adds the orbiting aim view and the cinematic shot view.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))

local Camera = {}

local locked = false

--- Park the camera above the head rail looking at the table centre.
function Camera.applyTableView()
	local C = Config.Camera
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = C.AimFieldOfView

	local center = TableBuilder.toWorld(0, 0, 0)
	local pitch = math.rad(C.AimPitchDegrees)
	local azimuth = math.rad(C.FixedAzimuthDegrees)
	local flat = math.cos(pitch) * C.AimDistanceStuds
	-- Azimuth 0 stands behind the head rail (physics -x).
	local offset = Vector3.new(
		-math.cos(azimuth) * flat,
		math.sin(pitch) * C.AimDistanceStuds,
		math.sin(azimuth) * flat
	)
	cam.CFrame = CFrame.lookAt(center + offset, center)
end

--- Keep the table view even when Roblox's default camera scripts try to take over
--- (they reset CameraType when the character spawns).
function Camera.lockTableView()
	if locked then
		return
	end
	locked = true
	Camera.applyTableView()
	local function watch(cam: Camera)
		cam:GetPropertyChangedSignal("CameraType"):Connect(function()
			if cam.CameraType ~= Enum.CameraType.Scriptable then
				Camera.applyTableView()
			end
		end)
	end
	watch(Workspace.CurrentCamera)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local cam = Workspace.CurrentCamera
		if cam then
			watch(cam)
			Camera.applyTableView()
		end
	end)
end

return Camera
