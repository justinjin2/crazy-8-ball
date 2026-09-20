--!strict
-- Client entry point. Wires the systems together; each system is its own module.
--
-- You join a table by stepping on its floor pad: the server decides who is sitting where
-- (src/server/TableService.luau) and tells every client, so a table looks taken from across
-- the room. This script reacts to "the server says I am now at table N" and switches the
-- camera, guideline, cue and controls over to that table.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Aim = require(Shared:WaitForChild("Physics"):WaitForChild("Aim"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Avatar = require(script.Parent:WaitForChild("Avatar"))
local Camera = require(script.Parent:WaitForChild("Camera"))
local Guideline = require(script.Parent:WaitForChild("Guideline"))
local Input = require(script.Parent:WaitForChild("Input"))
local Lounge = require(script.Parent:WaitForChild("Lounge"))
local Match = require(script.Parent:WaitForChild("Match"))
local UI = require(script.Parent:WaitForChild("UI"))

-- Wait for the server to have built the tables before drawing balls on them.
Workspace:WaitForChild(TableBuilder.FolderName)

-- Client-built visuals never hang off a server-built model: a model that streams out takes
-- its children with it and they do not come back.
local visuals = Instance.new("Folder")
visuals.Name = "ClientVisuals"
visuals.Parent = Workspace

local lounge = Lounge.new(visuals)
local cueStick = CueStickBuilder.build(visuals)
local input = Input.new()
local avatar = Avatar.new()

-- The table this client is sitting at, and its pieces. nil while walking around.
local seatId: number? = nil
local match: Match.Match? = nil
local placement: Placement.Placement? = nil
local guideline: Guideline.Guideline? = nil

local function cueBallWorld(): Vector3
	local p = placement
	local m = match
	if p == nil then
		return Vector3.zero
	end
	local cue = m and m:findCueBall()
	if cue then
		return TableBuilder.toWorld(p, cue.x, cue.y, Config.Balls.RadiusInches)
	end
	return TableBuilder.toWorld(p, 0, 0, Config.Balls.RadiusInches)
end

local currentPull = 0

local function refreshCueStick()
	local m, p = match, placement
	local cue = m and m:findCueBall()
	if m == nil or p == nil or m:isBusy() or cue == nil or cue.pocketed then
		CueStickBuilder.setVisible(cueStick, false)
		return
	end
	CueStickBuilder.setVisible(cueStick, true)
	local ballPos = TableBuilder.toWorld(p, cue.x, cue.y, Config.Balls.RadiusInches)
	local gap = TableBuilder.studs(Config.Cue.CueRestGapInches)
		+ currentPull * Config.Cue.CuePullBackStuds
	CueStickBuilder.place(cueStick, ballPos, Camera.aimDirection(input.angle), gap)
end

local function refreshGuideline()
	local m, g = match, guideline
	if g then
		if m == nil or m:isBusy() then
			g:hide()
		else
			g:show(Aim.trace(m.state, input.angle))
		end
	end
	refreshCueStick()
end

local function describe(summary): string
	local rails, hits, pockets = 0, 0, 0
	for _, ev in summary.events do
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
		summary.duration
	)
end

-- The shot is simulated as it plays, so what it did is only known once it stops.
local shotAngle, shotPower = 0, 0

local function shoot(power: number)
	local m, id = match, seatId
	if m == nil or id == nil or m:isBusy() then
		return
	end
	-- Inputs go to the server; the shot begins when it broadcasts the result back. Nothing
	-- is simulated here first, so the shooter sees exactly what everybody else sees.
	lounge:fire(id, input.angle, power)
	shotAngle, shotPower = input.angle, power
	input:setEnabled(false)
	refreshGuideline()
end

--- The server has seated us somewhere (or taken us off a table).
local function setSeat(id: number?)
	if id == seatId then
		return
	end
	seatId = id

	if guideline then
		guideline:destroy()
		guideline = nil
	end

	if id == nil then
		match = nil
		placement = nil
		input:setEnabled(false)
		UI.setPlayControlsVisible(false)
		CueStickBuilder.setVisible(cueStick, false)
		Camera.resetZoom()
		Camera.unlock()
		avatar:release()
		return
	end

	match = lounge:matchFor(id)
	placement = Placement.forTable(id)
	local p = placement
	if match == nil or p == nil then
		return
	end
	guideline = Guideline.new(visuals, p)
	Camera.setTable(p)
	avatar:take()
	Camera.lock()
	Camera.snap(cueBallWorld(), input.angle)
	input:setEnabled(true)
	UI.setPlayControlsVisible(true)
	refreshGuideline()
end

lounge:onSeatChanged(setSeat)

local function leaveTable()
	if seatId ~= nil then
		lounge:requestLeave()
	end
end

UI.createLeaveButton(leaveTable)
input:onLeave(leaveTable)

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
		local m = match
		if gameProcessed or m == nil or m:isBusy() then
			return
		end
		if keyInput.KeyCode == Enum.KeyCode.B then
			-- The rack belongs to the server now, so this only clears the local view until
			-- the next shot result arrives. Rules (2.1) replace the test key entirely.
			m:rerack()
			input:setAngle(0)
			refreshGuideline()
		end
	end)
end

local wasPlaying = false

input:setEnabled(false)
UI.setPlayControlsVisible(false)
CueStickBuilder.setVisible(cueStick, false)

RunService.RenderStepped:Connect(function(dt)
	if guideline then
		guideline:update(dt)
	end
	-- Sticks and the D-pad repeat have to be sampled, not waited for.
	input:update(dt)
	-- Every table steps, whether or not it is being drawn.
	local playing = lounge:update(dt)

	local m, p = match, placement
	if m == nil or p == nil then
		wasPlaying = playing
		return
	end
	-- Roblox's camera scripts can leave the mouse locked to the window; at the table the
	-- cursor must stay free for dragging and for leaving the window.
	if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	local dir = Camera.aimDirection(input.angle)
	local cueNow = if playing then m:cueBallWorldNow() else cueBallWorld()
	Camera.update(dt, cueBallWorld(), input.angle, playing, cueNow)
	avatar:update(
		p,
		cueBallWorld(),
		dir,
		if playing then Config.Avatar.ShotTransparency else Config.Avatar.AimTransparency,
		Camera.position()
	)
	if wasPlaying and not playing then
		local summary = m.lastShot
		if summary then
			print(
				("[8ball] shot: angle %.1f deg, power %.2f: %s"):format(
					math.deg(shotAngle),
					shotPower,
					describe(summary)
				)
			)
		end
		m:ensureCueBall()
		input:setEnabled(true)
		refreshGuideline()
	end
	wasPlaying = playing
	local status = if playing
		then ("cue ball %.0f in/s"):format(m:cueBallSpeedNow())
		else ("aim %.1f deg  |  drag to aim, pull the bar to shoot"):format(
			math.deg(input.angle)
		)
	UI.setStatus(
		("table %d  |  %s\n%d balls left   (%d tables drawn, B = new rack)"):format(
			seatId or 0,
			status,
			m:ballsRemaining(),
			lounge:renderedCount()
		)
	)
end)
print("[8ball] client ready")
