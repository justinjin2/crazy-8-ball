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
local Simulation = require(Shared:WaitForChild("Physics"):WaitForChild("Simulation"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local Audio = require(script.Parent:WaitForChild("Audio"))
local Avatar = require(script.Parent:WaitForChild("Avatar"))
local Effects = require(script.Parent:WaitForChild("Effects"))
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
local audio = Audio.new(visuals)
local effects = Effects.new(visuals)
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

-- The aim goes to the server a few times a second so opponents and spectators see the cue
-- turn. Never the guideline and never the power (ARCHITECTURE.md section 4): watching
-- someone line up is the point, seeing their aiming aid is not.
local sinceAimSent = 0
local lastAimSent: number? = nil

local function sendAim(dt: number)
	local id = seatId
	if id == nil then
		return
	end
	sinceAimSent += dt
	if sinceAimSent < 1 / Config.Aim.SendsPerSecond then
		return
	end
	local angle = input.angle
	if lastAimSent then
		local delta = math.abs((angle - lastAimSent + math.pi) % (2 * math.pi) - math.pi)
		if delta < Config.Aim.MinChangeRadians then
			return -- resting on the stick should cost nothing
		end
	end
	sinceAimSent = 0
	lastAimSent = angle
	lounge:reportAim(id, angle)
end

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

-- Tables whose events are already wired to audio and effects.
local wiredForEffects: { [number]: boolean } = {}

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
		effects:detachTrail()
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

	lastAimSent = nil
	match = lounge:matchFor(id)
	placement = Placement.forTable(id)
	local p = placement
	if match == nil or p == nil then
		return
	end
	-- Sound and the pocket burst follow the table being played. Wired once per TABLE, not
	-- once per seat: Match.onEvent has no way to unsubscribe, so subscribing again every
	-- time you sat down would stack listeners and play every clack twice over.
	local m = match
	if m and not wiredForEffects[id] then
		wiredForEffects[id] = true
		audio:attach(m)
		m:onEvent(function(ev)
			if ev.type ~= "pocket" then
				return
			end
			local b = Simulation.findBall(m.state, ev.ball)
			if b then
				effects:pocketBurst(
					TableBuilder.toWorld(p, b.x, b.y, Config.Balls.RadiusInches),
					ev.ball
				)
			end
		end)
	end
	guideline = Guideline.new(visuals, p)
	-- The trail hangs off the cue ball part itself, so it follows the ball with no
	-- per-frame positioning of its own.
	local cueBallPart = lounge:cueBallPartFor(id)
	if cueBallPart then
		effects:attachTrail(cueBallPart)
	end
	Camera.setTable(p)
	avatar:take()
	Camera.lock()
	Camera.snap(cueBallWorld(), input.angle)
	input:setEnabled(true)
	UI.setPlayControlsVisible(true)
	refreshGuideline()
end

lounge:onSeatChanged(setSeat)

-- A shot the server refuses has to give the controls back. shoot() turns input off the
-- moment it fires and only the end of a shot turns it back on, so without this the player
-- is left unable to aim, shoot or (on a gamepad) even leave.
lounge:onShotRejected(function(reason)
	if seatId ~= nil then
		warn(("[8ball] the server turned that shot down: %s"):format(reason))
		input:setEnabled(true)
		refreshGuideline()
	end
end)

local function leaveTable()
	if seatId ~= nil then
		lounge:requestLeave()
	end
end

UI.createLeaveButton(leaveTable)
input:onLeave(leaveTable)

input:onAim(refreshGuideline)
-- A soft tick every step of rotation (GDD section 5).
input:onTick(function()
	if placement then
		audio:tick(cueBallWorld())
	end
end)
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
	sendAim(dt)
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
	effects:updateTrail(m:findCueBall())
	audio:updateRoll(m, dt)
	local dir = Camera.aimDirection(input.angle)
	local cueNow = if playing then m:cueBallWorldNow() else cueBallWorld()
	Camera.update(dt, cueBallWorld(), input.angle, playing, cueNow)
	if playing and Config.Avatar.HideWhileShooting then
		-- The shooter steps out of the way while the balls run. Posing them against the
		-- LIVE cue ball, which is what used to happen here, walked the body around the
		-- cloth chasing it for the length of the shot.
		avatar:conceal()
	else
		avatar:update(p, cueBallWorld(), dir, Config.Avatar.AimTransparency, Camera.position())
	end
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
