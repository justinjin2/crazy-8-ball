--!strict
-- Phase-driven client wiring. The server decides play; existing shot, camera, spin,
-- cue, audio and renderer modules provide the presentation.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local SoundService = game:GetService("SoundService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AimStream = require(Shared.AimStream)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Placement = require(Shared.Placement)
local TableBuilder = require(Shared.TableBuilder)
local CueStickBuilder = require(Shared.CueStickBuilder)
local Simulation = require(Shared.Physics.Simulation)
local Aim = require(Shared.Physics.Aim)
local Judge = require(Shared.Rules.ShotJudge)
local Audio = require(script.Parent.Audio)
local Avatar = require(script.Parent.Avatar)
local Effects = require(script.Parent.Effects)
local Camera = require(script.Parent.Camera)
local Guideline = require(script.Parent.Guideline)
local Input = require(script.Parent.Input)
local Hub = require(script.Parent.Hub)
local PowerCue = require(script.Parent.PowerCue)
local SpinSelector = require(script.Parent.SpinSelector)
local UI = require(script.Parent.UI)
local MatchHUD = require(script.Parent.MatchHUD)
local MatchTargets = require(script.Parent.MatchTargets)
local BoxEffects = require(script.Parent.BoxEffects)
local QueueMenu = require(script.Parent.QueueMenu)
local M = Config.Multiplayer
local player = Players.LocalPlayer
workspace:WaitForChild(TableBuilder.FolderName)
local visuals = Instance.new("Folder")
visuals.Name = "ClientVisuals"
visuals.Parent = workspace
local hub = Hub.new(visuals)
local input = Input.new()
local cueStick = CueStickBuilder.build(visuals)
local avatar = Avatar.new()
local screen = UI.screen()
local powerCue = PowerCue.new(screen)
UI.addPlayControl(powerCue.root)
local spinSelector = SpinSelector.new(screen, input)
UI.addPlayControl(spinSelector.root)
local snapshot: any = nil
-- What the HUD and highlights draw: `snapshot` as match:view presents it, with balls down
-- as the replay drops them and the colors shown the moment they are decided. `snapshot`
-- itself stays the server's state for every rule check (canShoot, aim, targets).
local hudView: any = nil
local viewVersion = -1
local match: any = nil
local placement: any = nil
local guideline: any = nil
local hud: any = nil
local queueMenu: any = nil
local targets: any = nil
local awaitingAt: number? = nil
local currentPull = 0
local discretePower = M.PrecisionPowerDefault
local controlled = false
local lastTurnKey = ""
local lastPhaseKey = ""
local sinceAim = 0
local lastAim: number? = nil
local lastElevation: number? = nil
local lastPull: number? = nil -- the wind-up last sent, quantised (AimStream)
local lastBusy = false
local wasModal = false
local audioByTable: { [number]: any } = {}
local effectsByTable: { [number]: any } = {}
local uiSounds: { [string]: Sound } = {}
local ownHighlights: { Highlight } = {}
-- What the highlights were last built for, so an unchanged view does not rebuild them.
local highlightKey = ""
local highlightRenderer: any = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
-- Hand the camera back and free the mouse. Never restore a mouse mode saved at take-over:
-- a lock that Roblox's own camera set then (right-drag orbit, shift-lock) is one it stops
-- tracking once we take the camera, so writing it back later leaves the cursor locked for
-- good. Default is always right: the default camera re-applies shift-lock or first person
-- itself if they are genuinely on.
local function releaseMouse()
	Camera.unlock()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end
local function cueWorld(): Vector3
	local b = match and match:findCueBall()
	return if b and placement
		then TableBuilder.toWorld(placement, b.x, b.y, Config.Balls.RenderRadiusInches)
		else Vector3.zero
end
-- World positions of every ball that is moving right now, for the camera: it ends its hold
-- and pulls out the moment one of them is about to leave the screen. Reused between frames
-- rather than rebuilt, so watching for that costs nothing per frame.
--
-- Pocketed balls are left out deliberately. They are dropping down a hole at the very edge of
-- the view, so counting them would end the hold on every shot that sinks anything - which is
-- the one time the close framing is worth keeping.
local movingBuffer: { Vector3 } = {}
local function movingBallWorlds(): { Vector3 }
	table.clear(movingBuffer)
	if match and placement then
		for _, b in match.state.balls do
			-- A ball in the air counts even going straight up: it may be leaving the frame.
			if not b.pocketed and (b.vx ~= 0 or b.vy ~= 0 or b.z > 0 or b.vz ~= 0) then
				local at =
					TableBuilder.toWorld(placement, b.x, b.y, Config.Balls.RenderRadiusInches + b.z)
				table.insert(movingBuffer, at)
			end
		end
	end
	return movingBuffer
end
local function shooter(): boolean
	return snapshot ~= nil and snapshot.shooter == player.UserId
end
-- True while the shooter still owes a pocket call for the 8.
local function callPending(): boolean
	return snapshot ~= nil
		and match ~= nil
		and snapshot.calledPocket == nil
		and Judge.eligible(match.state.balls, snapshot.groups[snapshot.activeTeam])
end
-- The shot is this player's to take and not taken yet: their turn in an aiming phase, no shot
-- sent, the balls still. (A modal or a pocket still to call can hold it up: canShoot.)
local function aimTurn(): boolean
	if not shooter() or awaitingAt or not match or match:isBusy() then
		return false
	end
	return snapshot.phase == "Aiming" or snapshot.phase == "Intro" or snapshot.phase == "Placement"
end
local function canShoot(): boolean
	if not aimTurn() or (hud and hud:isModal()) then
		return false
	end
	if callPending() then
		return false
	end
	return true
end
-- The cue itself is drawn every frame after the pose (RenderStepped), from the same frame
-- the hands hold; this only hides it. A stroke keeps them: it plays on after
-- fire() has made canShoot() false.
local function refreshAim()
	local allowed = canShoot() and not targets:isDragging()
	spinSelector:setEnabled(allowed)
	if not guideline or not allowed then
		if guideline then
			guideline:hide()
		end
		if not avatar:stroking() then
			CueStickBuilder.setVisible(cueStick, false)
		end
		if hud then
			hud:setInvalidTarget(false)
		end
		return
	end
	local trace = Aim.trace(match.state, {
		angle = input.angle,
		power = math.max(currentPull, Config.Input.MinPowerToShoot),
		spin = input:getSpin(),
		elevation = input:getElevation(),
	})
	-- On the break any ball is a fair first target (ShotJudge); afterwards only the shooter's
	-- group, or the 8 once it is theirs.
	local invalid = trace.objectId ~= nil
		and not snapshot.breakShot
		and not Judge.legalTarget(
			match.state.balls,
			snapshot.groups[snapshot.activeTeam],
			trace.objectId
		)
	-- The host's difficulty decides how many lines are drawn; the wrong-target warning is
	-- shown at every level (Config.Difficulty).
	guideline:show(trace, invalid, snapshot.settings and snapshot.settings.difficulty)
	hud:setInvalidTarget(invalid)
end
local function sound(key: string, id: string)
	local existing = uiSounds[key]
	if existing then
		existing:Stop()
		existing:Play()
		return
	end
	local created = Instance.new("Sound")
	created.Name, created.SoundId, created.Volume = key, id, M.UISoundVolume
	created.Parent = SoundService
	uiSounds[key] = created
	created:Play()
end
local function clearHighlights()
	for _, h in ownHighlights do
		h:Destroy()
	end
	table.clear(ownHighlights)
	highlightKey, highlightRenderer = "", nil
end
-- Outline this player's group on the table, and the 8 once it is theirs to take. Reads the
-- presentation view, so it changes with the HUD, and is rebuilt only when what it shows does.
local function highlightOwn()
	local view = hudView
	local renderer = match and match.renderer
	if not view or not renderer or view.phase == "Result" then
		clearHighlights()
		return
	end
	local team = 1
	for _, s in view.seats do
		if s.userId == player.UserId then
			team = s.team
		end
	end
	local group = view.groups[team]
	local downMask = 0
	local left: { [string]: number } = { solids = 0, stripes = 0 } -- balls still up per group
	for id = 1, 15 do
		local ball = Judge.group(id)
		if view.balls[id * 4 + 4] == 1 then
			downMask = bit32.bor(downMask, bit32.lshift(1, id))
		elseif ball then
			left[ball] += 1
		end
	end
	-- Solo plays the first group, then the other: read off the balls shown down, so the
	-- switch (and the 8) comes the moment the replay drops the last of the first group.
	local first = view.solo and (view.solo.first or group)
	if first then
		group = if left[first] > 0 then first else Judge.opposite(first)
	end
	local eight = group ~= nil and left[group] == 0
	local key = ("%d:%d:%s:%s:%d"):format(
		view.id,
		view.epoch,
		group or "",
		tostring(eight),
		downMask
	)
	if key == highlightKey and renderer == highlightRenderer then
		return
	end
	clearHighlights()
	highlightKey, highlightRenderer = key, renderer
	if not group then
		return
	end
	-- The balls to hit get a green outline; the 8 joins them once it is this player's to take.
	-- Style.StrongBallHighlights (the tutorial style) makes that outline vivid and also
	-- washes the other group grey. At most 15 Highlights, inside Roblox's per-client budget.
	local S = M.Style
	local strong = S.StrongBallHighlights
	for _, b in match.state.balls do
		local ball = Judge.group(b.id)
		local own = ball == group or (b.id == 8 and eight)
		local other = strong and ball ~= nil and ball ~= group
		local part = renderer.parts and renderer.parts[b.id]
		if view.balls[b.id * 4 + 4] ~= 1 and (own or other) and part and part:IsA("BasePart") then
			local h = Instance.new("Highlight")
			h.Adornee = part
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			if own then
				h.FillTransparency = 1
				h.OutlineColor = rgb(if strong then S.StrongOwnOutline else S.Green)
				h.OutlineTransparency = if strong
					then S.StrongOwnOutlineTransparency
					else S.OwnBallOutlineTransparency
			else
				h.FillColor = rgb(S.OpponentBallFill)
				h.FillTransparency = S.OpponentBallFillTransparency
				h.OutlineTransparency = 1
			end
			h.Parent = part
			table.insert(ownHighlights, h)
		end
	end
end
-- Present the current snapshot. Runs on every snapshot and whenever the replay drops a ball
-- or reveals the colors (match.downVersion).
local function refreshView()
	hudView = match:view(snapshot)
	viewVersion = match.downVersion
	hud:setSnapshot(hudView, player.UserId)
	highlightOwn()
end
local function suggestAim()
	if not snapshot or not match or snapshot.breakShot then
		input:setAngle(0)
		return
	end
	local group = snapshot.groups[snapshot.activeTeam]
	if not group then
		return
	end
	local cue = match:findCueBall()
	if not cue then
		return
	end
	local target, best = nil, math.huge
	local eight = Judge.eligible(match.state.balls, group)
	for _, b in match.state.balls do
		if
			not b.pocketed and ((eight and b.id == 8) or (not eight and Judge.group(b.id) == group))
		then
			local d = (b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2
			if d < best then
				target, best = b, d
			end
		end
	end
	if target then
		input:setAngle(math.atan2(target.y - cue.y, target.x - cue.x))
	end
end
-- `windUp` is how far the cue is drawn back as the shot goes (0..1): the power itself when it
-- was drawn on the bar or a trigger (the default), nothing for the precision button, which
-- fires from the cue at rest.
local function fire(power: number, windUp: number?)
	if not canShoot() then
		return
	end
	-- The let-go goes first: once awaitingAt is set canShoot() is false, so the aim stream
	-- would never send the zero, and if the server turns the shot down the watchers' cue
	-- would stay drawn back.
	hub:reportAim(snapshot.id, input.angle, 0, input:getElevation())
	lastPull = 0
	-- The shot carries the cue ball in hand while the window is open, so the spot and the
	-- shot land together; after the cutoff the server already holds the locked spot.
	local x, y = targets:getPreview()
	-- The stroke starts here, from the wind-up (the power listeners have already dropped the
	-- pull to 0, so not from currentPull), and before awaitingAt: once that is set canShoot()
	-- is false, and the stroke has to keep the cue drawn through it.
	avatar:strike(windUp or power, x, y)
	hub:fire(snapshot.id, input.angle, power, input:getSpin(), input:getElevation(), x, y)
	targets:shotFired()
	awaitingAt = workspace:GetServerTimeNow()
	input:setEnabled(false)
	input:resetSpin()
	input:resetElevation()
	refreshAim()
end
local function leave()
	if hud:isModal() then
		hud:closeModal()
	elseif GuiService.SelectedObject then
		GuiService.SelectedObject = nil
	elseif snapshot and snapshot.phase == "Waiting" then
		-- Leaving a queue costs nothing (walking out does the same): no question asked.
		hub:action("LeaveQueue")
	else
		hud:openLeave()
	end
end
local function action(kind: string, value: any?)
	if kind == "PrecisionAim" then
		if canShoot() then
			input:setAngle(input.angle + math.rad(value :: number))
		end
	elseif kind == "PrecisionPower" then
		discretePower =
			math.clamp(discretePower + (value :: number), Config.Input.MinPowerToShoot, 1)
		hud.precisionButtons.Shoot.Text = require(Shared.Strings).Match.Shoot
			.. " "
			.. tostring(math.floor(discretePower * 100))
			.. "%"
	elseif kind == "ClosePrecision" then
		hud:togglePrecision()
	elseif kind == "PrecisionShoot" then
		fire(discretePower, 0) -- a short jab from the cue at rest
	elseif kind == "PrecisionPlace" then
		targets:nudge(value.sx, value.sy)
	elseif kind == "PrecisionToggle" then
		if value and UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1 then
			GuiService.SelectedObject = if targets:canPlace()
				then hud.precisionButtons.PlaceLeft
				else hud.precisionButtons.AimLeft
		end
	elseif kind == "Vote" then
		hub:action(kind, { yes = value })
	elseif kind == "SetDifficulty" or kind == "SetAbilities" then
		hub:action(kind, { value = value })
	else
		hub:action(kind)
	end
end
hud = MatchHUD.new(screen, action)
queueMenu = QueueMenu.new(screen, action)
targets = MatchTargets.new(screen, function(pocket)
	GuiService.SelectedObject = nil
	hub:action("Pocket", { pocket = pocket })
end, function(x, y)
	-- Predicted: the ball moves now, and stays put over snapshots until the turn moves on.
	if match and snapshot then
		match:holdCue(snapshot.epoch, snapshot.turnId, x, y)
	end
end, function(x, y, seq)
	hub:action("Place", { x = x, y = y, seq = seq })
end)

local function acquireTable(s: any?)
	local oldId = snapshot and snapshot.id
	if match and (not s or s.id ~= oldId) then
		match:releaseCue()
	end
	snapshot = s
	if not s then
		awaitingAt = nil
		input:setEnabled(false)
		input:resetSpin()
		input:resetElevation()
		UI.setPlayControlsVisible(false)
		CueStickBuilder.setVisible(cueStick, false)
		if guideline then
			guideline:destroy()
			guideline = nil
		end
		if controlled then
			avatar:release()
			releaseMouse()
			controlled = false
		end
		targets:clear()
		hud:setSnapshot(nil, player.UserId)
		queueMenu:setSnapshot(nil, player.UserId)
		hudView, viewVersion = nil, -1
		clearHighlights()
		match, placement = nil, nil
		lastTurnKey, lastPhaseKey = "", ""
		if oldId and audioByTable[oldId] then
			audioByTable[oldId]:resetStreak()
		end
		return
	end
	match = hub:matchFor(s.id)
	placement = Placement.forTable(s.id)
	if oldId ~= s.id then
		if guideline then
			guideline:destroy()
		end
		guideline = Guideline.new(visuals, placement)
		Camera.setTable(placement)
		lastTurnKey, lastPhaseKey = "", ""
	end
	local turnKey = ("%d:%d:%d"):format(s.id, s.epoch, s.turnId)
	if turnKey ~= lastTurnKey then
		lastTurnKey = turnKey
		awaitingAt = nil
		input:resetSpin()
		input:resetElevation()
		currentPull = 0
		lastAim, lastPull, lastElevation = nil, nil, nil
		-- A new turn (the same shooter again included) aims afresh, never from the last
		-- shot's frozen stance.
		avatar:newTurn()
		-- The break and a foul's ball in hand open wider than the home view.
		Camera.setBallInHand(s.ballInHand == true)
		Camera.resetZoom()
		if shooter() then
			suggestAim()
		end
	end
	if s.phase == "Resolving" then
		awaitingAt = nil
	end
	refreshView()
	queueMenu:setSnapshot(s, player.UserId)
	targets:setSnapshot(s, placement, match.state.geometry, player.UserId)
	local key = turnKey .. ":" .. s.phase
	if key ~= lastPhaseKey then
		lastPhaseKey = key
		if s.phase == "Intro" and shooter() then
			sound("YourTurn", M.YourTurnSound)
		elseif s.phase == "Foul" and s.foul and s.foul.by == player.UserId then
			sound("Foul", M.FoulSound)
		elseif s.phase == "CoinFlip" then
			sound("CoinFlip", M.CoinSound)
		end
	end
	refreshAim()
end
hub:onSeatChanged(function(id)
	acquireTable(if id then hub.snapshots[id] else nil)
end)
hub:onSnapshot(function(s)
	if hub.mySeat == s.id then
		acquireTable(s)
	end
end)
hub:onShotRejected(function()
	awaitingAt = nil
	-- The shot never happened: back from the stroke to aiming, the cue drawn again.
	avatar:cancelStroke()
	refreshAim()
end)
input:onLeave(leave)
input:onAim(refreshAim)
input:onSpin(refreshAim)
input:onElevation(refreshAim)
input:onShoot(fire)
input:onZoom(function(factor)
	if canShoot() and not targets:isDragging() then
		Camera.zoomBy(factor)
	end
end)
input:onPlaceMove(function(sx, sy, dt)
	targets:stickMove(sx, sy, dt)
end)
input:onPlaceEnd(function()
	targets:finishGesture(true)
end)
input:onTick(function()
	if snapshot and canShoot() then
		audioByTable[snapshot.id]:tick(cueWorld())
	end
end)
input:onPower(function(pull)
	powerCue:setPull(pull)
	currentPull = pull or 0
	if snapshot then
		audioByTable[snapshot.id]:setPull(pull)
	end
	refreshAim()
end)
powerCue:onDrag(function(pull)
	if canShoot() then
		input:setPower(pull)
	end
end, function()
	if canShoot() then
		input:releasePower()
	end
end)

-- Whether a ball dropping deserves the pocket effect: only a good pocket for whoever is
-- shooting. Never the white, never the other side's balls, and the 8 only once it is theirs
-- to take (judged on the balls as they stood before the shot, which the snapshot still holds
-- while it rolls). An open table rewards any object ball; solo rewards every object ball,
-- since both groups are the player's, and the 8 once all fourteen are down.
local function rewardsPocket(tableId: number, m: any, ballId: number): boolean
	if ballId == 0 then
		return false
	end
	local s = hub.snapshots[tableId]
	if not s then
		return true
	end
	local function downBefore(id: number): boolean
		return s.balls ~= nil and s.balls[id * 4 + 4] == 1
	end
	local groups = m:revealedGroups() or s.groups or {}
	local group = if s.activeTeam then groups[s.activeTeam] else nil
	if ballId == 8 then
		for id = 1, 15 do
			if id ~= 8 and not downBefore(id) and (s.solo or Judge.group(id) == group) then
				return false
			end
		end
		return s.solo ~= nil or group ~= nil
	end
	return s.solo ~= nil or group == nil or Judge.group(ballId) == group
end
for id = 1, Placement.tableCount() do
	local m = assert(hub:matchFor(id))
	local a = Audio.new(visuals)
	audioByTable[id] = a
	a:attach(m)
	local e = Effects.new(visuals)
	effectsByTable[id] = e
	m:onEvent(function(ev)
		if ev.type == "pocket" then
			-- The gust rises from the pocket's own centre; the ball's spot is the fallback.
			local at: Vector3? = nil
			for _, p in m.state.geometry.pockets do
				if p.id == ev.other then
					at = TableBuilder.toWorld(m.placement, p.x, p.y, 0)
				end
			end
			local b = Simulation.findBall(m.state, ev.ball)
			if not at and b then
				at = TableBuilder.toWorld(m.placement, b.x, b.y, 0)
			end
			if at and rewardsPocket(id, m, ev.ball) then
				e:pocketBurst(at, ev.ball)
			end
			if snapshot and snapshot.id == id then
				for _, p in m.state.geometry.pockets do
					if p.id == ev.other and controlled then
						Camera.kick(TableBuilder.toWorld(m.placement, p.x, p.y, 0), ev.speed)
					end
				end
			end
		end
	end)
end
-- A bonus this player's team earned. The server sends it ahead of the replay; the table's
-- Audio plays it in the same frame the replay drops that ball.
Net.get("MatchFeedback").OnClientEvent:Connect(function(f: any)
	if
		type(f) ~= "table"
		or type(f.id) ~= "string"
		or type(f.tableId) ~= "number"
		or type(f.epoch) ~= "number"
		or type(f.seq) ~= "number"
		or type(f.index) ~= "number"
		or type(f.ball) ~= "number"
	then
		return
	end
	local a = audioByTable[f.tableId]
	if a and hub.mySeat == f.tableId then
		a:grant(f)
	end
end)
UserInputService.InputBegan:Connect(function(key, processed)
	if processed then
		return
	end
	if
		(
			key.KeyCode == Enum.KeyCode.L
			or (key.KeyCode == Enum.KeyCode.ButtonB and not input.enabled)
		) and snapshot
	then
		leave()
	elseif key.KeyCode == Enum.KeyCode.Escape and hud:isModal() then
		hud:closeModal()
	elseif key.KeyCode == Enum.KeyCode.ButtonX and canShoot() then
		hud:togglePrecision()
	elseif key.KeyCode == Enum.KeyCode.ButtonY and snapshot and snapshot.phase == "Waiting" then
		queueMenu:focus()
	elseif key.KeyCode == Enum.KeyCode.F3 then
		UI.toggleStatus()
	end
end)
local zones = workspace:WaitForChild("TableZones")
local boxEffects = BoxEffects.new(zones)
-- A table's box stays lit only while it waits for its host.
local function queueOpen(id: number): boolean
	local s = hub.snapshots[id]
	return s == nil or s.phase == "Waiting"
end
input:setEnabled(false)
UI.setPlayControlsVisible(false)
CueStickBuilder.setVisible(cueStick, false)
-- What the avatar is handed every frame, filled in place rather than built anew.
local avatarContext: Avatar.Context = {
	placement = nil,
	state = nil,
	cueX = nil,
	cueY = nil,
	angle = 0,
	pull = 0,
	spin = nil,
	showCue = false,
	aimTurn = false,
	cameraPos = nil,
}
RunService.RenderStepped:Connect(function(dt)
	local busy = hub:update(dt)
	for id = 1, Placement.tableCount() do
		local a = audioByTable[id]
		local m = assert(hub:matchFor(id))
		a:updateRoll(m, dt)
		a:updatePull(dt)
		local e = effectsByTable[id]
		local part = hub:cueBallPartFor(id)
		if part and e.boundCue ~= part then
			e:attachTrail(part)
			e.boundCue = part
		end
		e:updateTrail(m:findCueBall(), m:isBusy())
	end
	boxEffects:update(dt, queueOpen)
	for id = 1, Placement.tableCount() do
		local panel = zones:FindFirstChild(("QueuePanel_%02d"):format(id))
		local billboard = panel and panel:FindFirstChildWhichIsA("BillboardGui")
		if billboard then
			billboard.Enabled = not controlled
		end
	end
	if not snapshot or not match then
		return
	end
	-- hub:update has dispatched this frame's events; show any ball they dropped.
	if match.downVersion ~= viewVersion then
		refreshView()
	end
	local now = workspace:GetServerTimeNow()
	if awaitingAt and now - awaitingAt >= M.ActionRetrySeconds then
		awaitingAt = nil
		Net.get("SnapshotRequest"):FireServer()
	end
	hud:update(now)
	queueMenu:update(now)
	local controlsTop = hud:reservedHeight() + M.Style.HeaderGap
	local available =
		math.max(M.Style.ButtonHeight, screen.AbsoluteSize.Y - controlsTop - M.Style.ButtonHeight)
	local height = math.min(Config.UI.PowerBarMaxHeightPx, available)
	local limit = powerCue.root:FindFirstChildWhichIsA("UISizeConstraint")
	if limit then
		limit.MinSize =
			Vector2.new(Config.UI.PowerBarWidthPx, math.min(Config.UI.PowerBarMinHeightPx, height))
	end
	powerCue.root.Position = UDim2.new(1, -Config.UI.PowerBarRightMarginPx, 0, controlsTop)
	powerCue.root.Size = UDim2.fromOffset(Config.UI.PowerBarWidthPx, height)
	local modal = hud:isModal()
	if modal ~= wasModal then
		input:setSpinEditing(false)
		if modal then
			input:setEnabled(false)
		end
		wasModal = modal
	end
	targets:setEnabled(not modal and awaitingAt == nil and not match:isBusy())
	input:setPlaceAllowed(targets:canPlace())
	local phase = snapshot.phase
	-- Only the shooter's camera is taken. The coin flip is a HUD overlay watched with the
	-- ordinary camera; the breaker is handed the home view at Intro. A solo player keeps it
	-- through a foul, since the ball in hand that follows is their own.
	local take = shooter()
		and phase ~= "Waiting"
		and phase ~= "CoinFlip"
		and (phase ~= "Foul" or snapshot.solo ~= nil)
		and phase ~= "Result"
	if take ~= controlled then
		controlled = take
		if take then
			Camera.setTable(placement)
			Camera.lock()
			if shooter() then
				avatar:take()
			end
		else
			-- The turn passed, a foul handed the table over, the game ended: the body is the
			-- player's again, where it stands (the server lets the root go there).
			avatar:release()
			CueStickBuilder.setVisible(cueStick, false)
			releaseMouse()
		end
	end
	local allowed = canShoot() and not targets:isDragging() and GuiService.SelectedObject == nil
	if input.enabled ~= allowed then
		input:setEnabled(allowed)
	end
	UI.setPlayControlsVisible(canShoot() and not modal and not hud.precisionOpen)
	input:update(dt)
	if controlled then
		-- Top-down only while a pocket is being called for the 8; everything else, placing
		-- the cue ball included, plays in the 3D view.
		local overhead = phase == "PocketChoice" or (phase == "Intro" and callPending())
		Camera.setMode(
			overhead,
			hud:reservedHeight() + GuiService:GetGuiInset().Y + M.Style.TargetSize / 2,
			hud:reservedBottom() + M.Style.TargetSize / 2
		)
		if busy and not lastBusy then
			local cue = match:findCueBall()
			local speed = match:cueBallSpeedNow()
			if cue and speed > 0 then
				local dx, dy = cue.vx / speed, cue.vy / speed
				Camera.beginShot(speed, cue.wx * dx + cue.wy * dy, -cue.wx * dy + cue.wy * dx)
			else
				Camera.beginShot(0)
			end
			-- The replay has the ball moving: the stroke may follow through now.
			avatar:ballMoving()
		end
		-- The shot "plays" until the server resolves it, not just while the balls roll: the
		-- pulled-out view stays put through the settle, and only the NEXT turn decides where
		-- the camera goes - back to the home view if this player shoots again, or straight
		-- back to their own Roblox camera if not (Camera.unlock eases that hand-over).
		-- The view holds still while the cue ball is dragged or sits in a pocket.
		local cueBall = match:findCueBall()
		local hold = targets:isHolding() or (cueBall ~= nil and cueBall.pocketed)
		Camera.update(
			dt,
			cueWorld(),
			input.angle,
			busy or phase == "Resolving",
			if busy then match:cueBallWorldNow() else nil,
			if busy then movingBallWorlds() else nil,
			hold
		)
		-- The shooter's body, then the cue in the very frame the hands hold. Once the
		-- stroke has played the body is the player's again while the balls roll: they may
		-- walk (the server lets the root go, Engine.shooterHeld) while the shot camera still
		-- follows the balls, and their next turn poses them again from wherever they walked.
		if shooter() and phase == "Resolving" and not avatar:stroking() then
			avatar:release()
			CueStickBuilder.setVisible(cueStick, false)
		elseif shooter() then
			avatar:take()
			local cue = match:findCueBall()
			local live = cue ~= nil and not cue.pocketed
			local ctx = avatarContext
			ctx.placement = placement
			ctx.state = match.state
			ctx.cueX = if live then cue.x else nil
			ctx.cueY = if live then cue.y else nil
			ctx.angle = input.angle
			ctx.pull = currentPull
			ctx.spin = input:getSpin()
			ctx.elevation = input:getElevation()
			ctx.showCue = canShoot() and not targets:isDragging()
			ctx.aimTurn = aimTurn()
			ctx.cameraPos = Camera.position()
			local out = avatar:update(dt, ctx)
			CueStickBuilder.setVisible(cueStick, out.visible)
			if out.visible then
				CueStickBuilder.placeAt(cueStick, out.tip)
				Camera.fadeNear(cueStick, Config.Cue.CameraFadeStuds)
			end
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	targets:update(dt, workspace.CurrentCamera)
	hud:setPlacing(targets:canPlace(), targets:isBlocked())
	if guideline then
		guideline:update(dt)
	end
	refreshAim()
	-- One unreliable stream for the aim, the wind-up and, while it moves, the cue ball in hand.
	sinceAim += dt
	local seq, px, py
	if sinceAim >= 1 / Config.Aim.PlacementSendsPerSecond then
		seq, px, py = targets:takeStream()
	end
	local pull = AimStream.quantizePull(currentPull) or 0
	-- A let-go goes at once, even where canShoot() has just turned false (a modal opening
	-- mid-pull drops the power), or the watchers' cue would stay drawn back.
	local aimPhase = shooter()
		and awaitingAt == nil
		and (phase == "Aiming" or phase == "Intro" or phase == "Placement")
	local letGo = lastPull ~= nil and lastPull > 0 and pull == 0
	if
		seq
		or (aimPhase and letGo)
		or (
			canShoot()
			and AimStream.due(
				sinceAim,
				input.angle,
				pull,
				lastAim,
				lastPull,
				input:getElevation(),
				lastElevation
			)
		)
	then
		sinceAim = 0
		lastAim, lastPull, lastElevation = input.angle, pull, input:getElevation()
		hub:reportAim(snapshot.id, input.angle, pull, input:getElevation(), seq, px, py)
	end
	lastBusy = busy
end)
print("[8ball] multiplayer client ready")
