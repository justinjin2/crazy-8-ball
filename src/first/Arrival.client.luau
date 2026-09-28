--!strict
-- Arrival: arriving from a global-queue teleport (designer, 2026-09-28), keep the teleport
-- screen the last server handed Roblox (TeleportScreen) up instead of Roblox's default
-- loading screen, until this server's tables and the character are in, then fade it out.
-- ReplicatedFirst runs before the rest of the game has loaded, so it waits for Config.
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")

local gui = TeleportService:GetArrivingTeleportGui()
if not gui then
	return
end
ReplicatedFirst:RemoveDefaultLoadingScreen()
local player = Players.LocalPlayer
gui.Enabled = true
gui.Parent = player:WaitForChild("PlayerGui")

local shared = ReplicatedStorage:WaitForChild("Shared", 30)
local config = shared and shared:FindFirstChild("Config")
local Q = if config and config:IsA("ModuleScript") then (require(config) :: any).UI.Queue else nil
-- Config.UI.Queue; the fallbacks only if Config never arrived.
local hold = if Q then Q.ArrivalHoldSeconds else 15
local fade = if Q then Q.FadeSeconds else 0.4

local started = os.clock()
while os.clock() - started < hold do
	if workspace:FindFirstChild("Tables") and player.Character then
		break
	end
	task.wait(0.1)
end

local info = TweenInfo.new(fade, Enum.EasingStyle.Quad)
for _, object in gui:GetDescendants() do
	if object:IsA("Frame") then
		TweenService:Create(object, info, { BackgroundTransparency = 1 }):Play()
	elseif object:IsA("TextLabel") then
		TweenService:Create(object, info, { TextTransparency = 1 }):Play()
	elseif object:IsA("UIStroke") then
		TweenService:Create(object, info, { Transparency = 1 }):Play()
	end
end
task.wait(fade)
gui:Destroy()
