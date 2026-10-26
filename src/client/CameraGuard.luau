--!strict
-- CameraGuard: a camera pose Roblox's camera script cannot read (looking a hair past straight
-- down or up; why in src/shared/CameraSanity.luau) is tilted just off vertical, same place and
-- heading, before that script runs (Config.Camera.Guard). It runs just before
-- RenderPriority.Camera and only while Roblox's camera is in charge: a Scriptable camera (the
-- table view, the cutscenes) may look straight down, and nothing reads it there. It costs a
-- CFrame read and a few compares a frame. The first fix in a session warns once, so the error
-- report counts how often it happens without the one-a-frame spam.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CameraSanity = require(Shared.CameraSanity)
local Config = require(Shared.Config)

local G = Config.Camera.Guard

local CameraGuard = {}

local warned = false

local function check()
	local cam = Workspace.CurrentCamera
	if cam == nil or cam.CameraType == Enum.CameraType.Scriptable then
		return
	end
	local cf = cam.CFrame
	local look = cf.LookVector
	if CameraSanity.lookOk(look.X, look.Y, look.Z) then
		return
	end
	local up = cf.UpVector
	local x, y, z = CameraSanity.tilted(look.Y, up.X, up.Z, G.MaxLookHeight)
	cam.CFrame = CFrame.lookAlong(cf.Position, Vector3.new(x, y, z))
	if not warned then
		warned = true
		warn(
			("[8ball] CameraGuard: the camera looked past vertical (%.7f) under %s and was tilted back"):format(
				look.Y,
				cam.CameraType.Name
			)
		)
	end
end

function CameraGuard.start()
	if G.Enabled then
		RunService:BindToRenderStep("PoolCameraGuard", Enum.RenderPriority.Camera.Value - 1, check)
	end
end

return CameraGuard
