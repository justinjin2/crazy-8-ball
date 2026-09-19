--!strict
-- Client entry point. Wires the systems together; each system is its own module.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Aim = require(Shared:WaitForChild("Physics"):WaitForChild("Aim"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Avatar = require(script.Parent:WaitForChild("Avatar"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Guideline = require(script.Parent:WaitForChild("Guideline"))
local Input = require(script.Parent:WaitForChild("Input"))
local Match = require(script.Parent:WaitForChild("Match"))
local UI = require(script.Parent:WaitForChild("UI"))

-- The server builds the table; wait for it so the balls have somewhere to sit.
local poolTable = Workspace:WaitForChild("PoolTable")
local joinPrompt = poolTable:WaitForChild("JoinPrompt"):WaitForChild("Play") :: ProximityPrompt

local renderer = BallRenderer.new(Workspace)
local match = Match.new(renderer)
local guideline = Guideline.new(Workspace)
local cueStick = CueStickBuilder.build(Workspace)
local input = Input.new()
local avatar = Avatar.new()

-- "roaming": walking around normally. "playing": at the table, aiming.
local mode: "roaming" | "playing" = "roaming"

local function cueBallWorld(): Vector3
	local cue = match:findCueBall()
	if cue then
		return TableBuilder.toWorld(cue.x, cue.y, Config.Balls.RadiusInches)
	end
	return TableBuilder.toWorld(0, 0, Config.Balls.RadiusInches)
end

local currentPull = 0

local function refreshCueStick()
	local cue = match:findCueBall()
	if mode ~= "playing" or match:isBusy() or cue == nil or cue.pocketed then
		CueStickBuilder.setVisible(cueStick, false)
		return
	end
	CueStickBuilder.setVisible(cueStick, true)
	local ballPos = TableBuilder.toWorld(cue.x, cue.y, Config.Balls.RadiusInches)
	local gap = TableBuilder.studs(Config.Cue.CueRestGapInches)
		+ currentPull * Config.Cue.CuePullBackStuds
	CueStickBuilder.place(cueStick, ballPos, Camera.aimDirection(input.angle), gap)
end

local function refreshGuideline()
	if mode ~= "playing" or match:isBusy() then
		guideline:hide()
	else
		guideline:show(Aim.trace(match.state, input.angle))
	end
	refreshCueStick()
end

local function describe(result)
	local rails, hits, pockets = 0, 0, 0
	for _, ev in result.events do
		if ev.type == "railHit" then
			rails += 1
		elseif ev.type == "ballHit" then
			hits += 1
		elseif ev.type == "pocket" then
			pockets += 1
		end
	end
	return ("%d ball hits, %d rail hits, %d pocketed, %.2fs"):format(
		hits,
		rails,
		pockets,
		result.duration
	)
end

local function shoot(power: number)
	if match:isBusy() then
		return
	end
	local result = match:fire({ angle = input.angle, power = power })
	if result then
		print(
			("[8ball] shot: angle %.1f deg, power %.2f: %s"):format(
				math.deg(input.angle),
				power,
				describe(result)
			)
		)
		input:setEnabled(false)
		refreshGuideline()
	end
end

local function joinTable()
	if mode == "playing" then
		return
	end
	mode = "playing"
	joinPrompt.Enabled = false
	avatar:take()
	Camera.lock()
	Camera.snap(cueBallWorld(), input.angle)
	input:setEnabled(true)
	UI.setPlayControlsVisible(true)
	refreshGuideline()
end

local function leaveTable()
	if mode ~= "playing" then
		return
	end
	mode = "roaming"
	input:setEnabled(false)
	UI.setPlayControlsVisible(false)
	guideline:hide()
	CueStickBuilder.setVisible(cueStick, false)
	Camera.resetZoom()
	Camera.unlock()
	avatar:release()
	joinPrompt.Enabled = true
end

joinPrompt.Triggered:Connect(joinTable)
UI.createLeaveButton(leaveTable)

input:onAim(refreshGuideline)
input:onShoot(shoot)
input:onZoom(function(factor)
	Camera.zoomBy(factor)
end)
input:onPower(function(pull)
	UI.setPower(pull)
	currentPull = pull or 0
	refreshCueStick()
end)
UI.createPowerBar(function(pull)
	input:setPower(pull)
end, function()
	input:releasePower()
end)
UI.createNudgeButtons(function(direction)
	input:rotate(direction * Config.Input.NudgeDegrees)
end)

if Config.Debug.TestKeysEnabled then
	UserInputService.InputBegan:Connect(function(keyInput, gameProcessed)
		if gameProcessed or match:isBusy() then
			return
		end
		if keyInput.KeyCode == Enum.KeyCode.B then
			match:rerack()
			input:setAngle(0)
			refreshGuideline()
		end
	end)
end

local wasPlaying = false

-- Start out walking: no controls, no camera lock, until the table prompt is held.
input:setEnabled(false)
UI.setPlayControlsVisible(false)
CueStickBuilder.setVisible(cueStick, false)

RunService.RenderStepped:Connect(function(dt)
	guideline:update(dt)
	local playing = match:update(dt)
	if mode ~= "playing" then
		-- Walking around: leave the camera and the character to Roblox.
		wasPlaying = playing
		return
	end
	-- Roblox's camera scripts can leave the mouse locked to the window; at the table the
	-- cursor must stay free for dragging and for leaving the window.
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local dir = Camera.aimDirection(input.angle)
	local cueNow = if playing then match:cueBallWorldNow() else cueBallWorld()
	Camera.update(dt, cueBallWorld(), input.angle, playing, cueNow)
	avatar:update(
		cueBallWorld(),
		dir,
		if playing then Config.Avatar.ShotTransparency else Config.Avatar.AimTransparency,
		Camera.position()
	)
	if wasPlaying and not playing then
		match:ensureCueBall()
		input:setEnabled(true)
		refreshGuideline()
	end
	wasPlaying = playing
	local status = if playing
		then ("cue ball %.0f in/s"):format(match:cueBallSpeedNow())
		else ("aim %.1f deg  |  drag to aim, pull the bar to shoot"):format(
			math.deg(input.angle)
		)
	UI.setStatus(("%s\n%d balls left   (B = new rack)"):format(status, match:ballsRemaining()))
end)
print("[8ball] client ready")
