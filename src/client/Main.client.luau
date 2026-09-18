--!strict
-- Client entry point. Wires the systems together; each system is its own module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Match = require(script.Parent:WaitForChild("Match"))
local UI = require(script.Parent:WaitForChild("UI"))

-- The server builds the table; wait for it so the balls have somewhere to sit.
Workspace:WaitForChild("PoolTable")

local renderer = BallRenderer.new(Workspace)
local match = Match.new(renderer)
Camera.lockTableView()

local seed = 1
local function nextRandom(): number
	-- Small deterministic generator so test shots are repeatable between sessions.
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function fireTestShot()
	local angle = nextRandom() * 2 * math.pi
	local power = 0.3 + nextRandom() * 0.7
	local result = match:fire({ angle = angle, power = power })
	if result then
		print(
			("[8ball] test shot: angle %.2f rad, power %.2f, %d rail hits, %.2fs"):format(
				angle,
				power,
				#result.events - 1,
				result.duration
			)
		)
	end
end

if Config.Debug.TestKeysEnabled then
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			fireTestShot()
		end
	end)
end

RunService.RenderStepped:Connect(function(dt)
	local playing = match:update(dt)
	local status = if playing
		then ("cue ball %.0f in/s"):format(match:cueBallSpeedNow())
		else "at rest"
	UI.setDebugText(("Press F to fire a test shot\n%s"):format(status))
end)

print(("[8ball] client ready. Camera aim mode: %s"):format(Config.Camera.AimMode))
