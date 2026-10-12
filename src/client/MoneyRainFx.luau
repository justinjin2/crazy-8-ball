--!strict
-- MoneyRainFx: the owner's money rain on this screen (src/server/MoneyRain.luau; Config.Admin
-- .Rain). Each bill in Workspace[Rain.Folder] (the money icon facing the camera, its amount
-- above it, sparkling) falls from SkyStuds above its To (CFrame) until LandAt (server time),
-- swaying side to side; once down it bobs a little. It never turns (designer, 2026-10-11).
-- Only this screen moves it: the server owns where it lies and who picks it up.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local R = Config.Admin.Rain

local MoneyRainFx = {}

type Tracked = { part: BasePart, to: CFrame, landAt: number, phase: number }

local tracked: { [BasePart]: Tracked } = {}
local started = false

local function track(part: Instance)
	if not part:IsA("BasePart") or tracked[part] then
		return
	end
	local to, landAt = part:GetAttribute("To"), part:GetAttribute("LandAt")
	if typeof(to) ~= "CFrame" or type(landAt) ~= "number" then
		return
	end
	tracked[part] = { part = part, to = to, landAt = landAt, phase = math.random() * 2 * math.pi }
	part.AncestryChanged:Connect(function()
		if not part:IsDescendantOf(workspace) then
			tracked[part] = nil
		end
	end)
end

local function step()
	local now = workspace:GetServerTimeNow()
	for part, t in tracked do
		local left = t.landAt - now
		if left > 0 then
			local u = 1 - math.clamp(left / R.FallSeconds, 0, 1)
			local sway = math.sin(u * 3 * math.pi + t.phase) * R.SwayStuds
			local drop = R.SkyStuds * (1 - u)
			part.CFrame = t.to * CFrame.new(sway, drop, 0)
		else
			part.CFrame = t.to * CFrame.new(0, R.BobStuds * math.sin(-left * 2 + t.phase), 0)
		end
	end
end

--- Watches the rain folder (Progression calls this once).
function MoneyRainFx.start()
	if started then
		return
	end
	started = true
	local function watch(folder: Instance)
		if not folder:IsA("Folder") or folder.Name ~= R.Folder then
			return
		end
		for _, child in folder:GetChildren() do
			track(child)
		end
		folder.ChildAdded:Connect(track)
	end
	for _, child in workspace:GetChildren() do
		watch(child)
	end
	workspace.ChildAdded:Connect(watch)
	RunService.RenderStepped:Connect(function()
		if next(tracked) ~= nil then
			step()
		end
	end)
end

return MoneyRainFx
