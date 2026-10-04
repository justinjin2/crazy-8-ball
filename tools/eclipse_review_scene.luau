--!nocheck
-- Transient Client comparison harness. Identical camera/lighting for original and candidate.
-- Run vfx_lab with Eclipse alone first. MODE orbit / back / walking; no saved scripts.
local MODE = "orbit"
local RS = game:GetService("RunService")
local C = require(game.ReplicatedStorage.Shared.Config)
local Quality = require(game.Players.LocalPlayer.PlayerScripts.Client.Quality)
local cycle = C.Lighting.Cycle
if _G.EclipseReviewStop then _G.EclipseReviewStop() end
if _G.VfxCam then _G.VfxCam:Disconnect(); _G.VfxCam = nil end
local cam = workspace.CurrentCamera
local me = game.Players.LocalPlayer.Character
if MODE ~= "gameplay" then me:PivotTo(CFrame.new(-46, 4, 85)) end
if MODE == "orbit" and _G.VfxLabPool then
	for ch in _G.VfxLabPool.carried do _G.VfxLabPool:release(ch); ch:Destroy() end
end
if MODE == "gameplay" then
	local light = RS.RenderStepped:Connect(function()
		workspace:SetAttribute(cycle.OffsetAttribute, 30 - workspace:GetServerTimeNow() * cycle.Speed)
	end)
	_G.EclipseReviewStop = function() light:Disconnect() end
	return "Matched gameplay: fixed bright lobby lighting; natural game camera"
end
local start = os.clock()
local busy = false
local function frame()
	local t = os.clock() - start
	if MODE == "orbit" then
		local angle = t * math.pi / 6
		local target = Vector3.new(-34, 4, 70)
		return CFrame.lookAt(target + Vector3.new(8 * math.sin(angle), 1.4, 8 * math.cos(angle)), target)
	elseif MODE == "back" then
		local angle = t * math.pi / 10
		local target = Vector3.new(-40, 3.6, 70)
		return CFrame.lookAt(target + Vector3.new(8 * math.sin(angle), 1.8, 8 * math.cos(angle)), target)
	else
		local root = me.HumanoidRootPart
		return CFrame.lookAt(root.Position + Vector3.new(-3, 2.5, 8), root.Position + Vector3.new(0, 1, 0))
	end
end
local lock = cam:GetPropertyChangedSignal("CFrame"):Connect(function()
	if busy then return end
	busy = true; cam.CFrame = frame(); busy = false
end)
local tick = RS.RenderStepped:Connect(function()
	workspace:SetAttribute(cycle.OffsetAttribute, 30 - workspace:GetServerTimeNow() * cycle.Speed)
	if MODE ~= "walking" then Quality.set(os.clock() - start >= 12) end
	if MODE == "walking" then
		local t = (os.clock() - start) % 12
		me.Humanoid:Move(Vector3.new(math.sin(t * math.pi / 6), 0, -math.cos(t * math.pi / 6)), false)
	end
	busy = true; cam.CFrame = frame(); busy = false
end)
_G.EclipseReviewStop = function()
	lock:Disconnect(); tick:Disconnect(); Quality.set(false)
	me.Humanoid:Move(Vector3.zero, false)
end
return "Matched " .. MODE .. ": bright lobby; full 0–12s / Lower effects 12–24s"
