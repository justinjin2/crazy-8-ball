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
local Engine = require(Shared.Rules.MatchEngine)
local NiceShot = require(Shared.Rules.NiceShot)
local Audio = require(script.Parent.Audio)
local Avatar = require(script.Parent.Avatar)
local Effects = require(script.Parent.Effects)
local Camera = require(script.Parent.Camera)
local DayCycle = require(script.Parent.DayCycle)
local FirePit = require(script.Parent.FirePit)
local Guideline = require(script.Parent.Guideline)
local Input = require(script.Parent.Input)
local MapAmbience = require(script.Parent.MapAmbience)
local Hub = require(script.Parent.Hub)
local PowerCue = require(script.Parent.PowerCue)
local SpinSelector = require(script.Parent.SpinSelector)
local ZoomHint = require(script.Parent.ZoomHint)
local PadGuide = require(script.Parent.PadGuide)
local UI = require(script.Parent.UI)
local MatchHUD = require(script.Parent.MatchHUD)
local MatchTargets = require(script.Parent.MatchTargets)
local PadEffects = require(script.Parent.PadEffects)
local QueueMenu = require(script.Parent.QueueMenu)
local TableSign = require(script.Parent.TableSign)
local OpponentPrompt = require(script.Parent.OpponentPrompt)
local Progression = require(script.Parent.Progression)
local QueueStatus = require(script.Parent.QueueStatus)
local TeleportScreen = require(script.Parent.TeleportScreen)
local Strings = require(Shared.Strings)
local M = Config.Multiplayer
local player = Players.LocalPlayer
workspace:WaitForChild(TableBuilder.FolderName)
-- A global-queue arena (designer, 2026-09-28): the server set these before building its one
-- table, so every loop below sees that one table where Config.Arena puts it.
local isArena = workspace:GetAttribute(Config.Arena.ModeAttribute) == "Arena"
if isArena then
	local row: any = table.clone(Config.Arena.Table)
	row.teamSize = workspace:GetAttribute(Config.Arena.TeamSizeAttribute) or 1
	Placement.setLayout({ row })
end
local visuals = Instance.new("Folder")
visuals.Name = "ClientVisuals"
visuals.Parent = workspace
local hub = Hub.new(visuals)
local input = Input.new()
local cueStick = CueStickBuilder.build(visuals)
-- Cue looks: the stick is the player's equipped cue, repainted whenever they equip another.
CueStickBuilder.wear(cueStick, player)
local avatar = Avatar.new()
local screen = UI.screen()
local powerCue = PowerCue.new(screen)
powerCue:follow(player) -- cue looks: the power bar's cue is the equipped one too
UI.addPlayControl(powerCue.root)
local spinSelector = SpinSelector.new(screen, input)
local zoomHint = ZoomHint.new(screen) -- scroll or pinch to zoom, over the spin button
local padGuide = PadGuide.new(screen) -- the controller guide, bottom left, on a gamepad
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
-- The shot clock's ticks (Config.Audio.ClockTick): the turn they are for and the second the
-- clock last showed, so each second ticks once.
local tickTurn: number? = nil
local tickSecond = 0
local currentPull = 0
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
	elseif snapshot and snapshot.phase == "Waiting" and isArena then
		-- Waiting in an arena (for the opponent, or after a no-show): back to the lobby.
		Net.get("ArenaAction"):FireServer("Lobby")
	elseif snapshot and snapshot.phase == "Waiting" then
		-- Leaving a queue costs nothing (walking out does the same): no question asked.
		hub:action("LeaveQueue")
	else
		hud:openLeave()
	end
end
local function action(kind: string, value: any?)
	if kind == "Vote" then
		hub:action(kind, { yes = value })
	elseif kind == "SetDifficulty" or kind == "SetAbilities" or kind == "SetQueueUlts" then
		hub:action(kind, { value = value })
	else
		hub:action(kind)
	end
end
hud = MatchHUD.new(screen, action)
padGuide:attachLeave(hud.leave) -- the Circle beside Leave
queueMenu = QueueMenu.new(screen, action)
-- Ranks and money: the HUDs, nameplates, flying cash, result screen, NEW RANK! and roadmap.
Progression.start(screen, {
	-- Where a table's pocket is on screen, in this ScreenGui's pixels (it keeps clear of
	-- Roblox's top bar, so the inset comes off). A pocket behind the camera is mirrored back
	-- so the flying cash starts from the nearest edge on the right side.
	pocketToScreen = function(tableId: number, pocket: number): Vector2?
		local m = hub:matchFor(tableId)
		local camera = workspace.CurrentCamera
		if not m or not camera then
			return nil
		end
		for _, p in m.state.geometry.pockets do
			if p.id == pocket then
				local v =
					camera:WorldToViewportPoint(TableBuilder.toWorld(m.placement, p.x, p.y, 0))
				local at = Vector2.new(v.X, v.Y)
				if v.Z < 0 then
					at = camera.ViewportSize - at
				end
				return at - GuiService:GetGuiInset()
			end
		end
		return nil
	end,
})
-- "<name> needs an opponent...": Join asks the server to stand you on their pad.
local opponentPrompt = OpponentPrompt.new(screen, function(id: number, epoch: number)
	Net.get("AnswerRequest"):FireServer(id, epoch)
end)
Net.get("OpponentRequest").OnClientEvent:Connect(function(ask: any)
	if hub.mySeat == nil then
		opponentPrompt:show(ask)
	end
end)
-- The global queue (designer, 2026-09-28): the teleport screen, the small status card, and
-- the rematch row on the result screen.
local teleportScreen = TeleportScreen.new()
local queueStatus = QueueStatus.new(screen)
local arenaState: any = nil
Net.get("QueueNotice").OnClientEvent:Connect(function(notice: any)
	if type(notice) ~= "table" then
		return
	end
	if notice.kind == "Found" or notice.kind == "Home" then
		teleportScreen:show(notice.kind)
	elseif notice.kind == "Failed" then
		teleportScreen:hide()
		local reason = notice.reason
		local text = type(reason) == "string"
			and ((Strings.GlobalQueue.Failed :: any)[reason] or (Strings.Arena :: any)[reason])
		if type(text) == "string" then
			queueStatus:flash(text)
		end
	elseif notice.kind == "Stopped" then
		queueStatus:flash(Strings.GlobalQueue.Failed.Party)
	end
end)
Net.get("ArenaState").OnClientEvent:Connect(function(state: any)
	if type(state) == "table" then
		arenaState = state
	end
end)
-- The row's buttons. Rematch and Leave are the table's vote; Play another, its Cancel and
-- Lobby are the arena's own.
local leftChoiceAt: number? = nil
Progression.setChoiceHandler(function(kind: string, summary: any)
	local s = hub.snapshots[summary.tableId]
	local sameGame = s ~= nil and s.epoch == summary.epoch and s.phase == "Result"
	if kind == "Rematch" then
		if sameGame and hub.mySeat == summary.tableId then
			hub:action("Rematch")
		end
	elseif kind == "Leave" then
		if sameGame and hub.mySeat == summary.tableId then
			hub:action("Decline")
		end
		Progression.endChoices()
	elseif kind == "Another" or kind == "CancelAnother" or kind == "Lobby" then
		Net.get("ArenaAction"):FireServer(kind)
		if kind == "Lobby" then
			leftChoiceAt = os.clock()
		end
	end
end)

-- What the rematch row shows now, for the summary whose row is up; nil once the choosing
-- is over (a rematch began, or a lobby table freed).
local lobbyGoneAt: number? = nil
local function postMatchState(summary: any, now: number): any?
	local me = player.UserId
	local s = hub.snapshots[summary.tableId]
	if s and s.epoch > summary.epoch and s.phase ~= "Waiting" and hub.mySeat == summary.tableId then
		return nil -- the rematch has begun
	end
	local state: any = { arena = summary.arena == true, rematch = "gone", votes = 0, total = 0 }
	if s and s.epoch == summary.epoch and s.phase == "Result" and s.rematch then
		local total = 0
		for _, seat in s.seats do
			if seat.connected ~= false and seat.team then
				total += 1
			end
		end
		state.votes, state.total = #s.rematch.yes, total
		state.rematch = if s.rematch.declined
			then "gone"
			elseif table.find(s.rematch.yes, me) then "voted"
			else "open"
		state.deadline = s.deadline
	end
	if state.arena then
		local a = arenaState
		local key = tostring(me)
		local mine = a and a.choices and a.choices[key]
		local since = a and a.searching and a.searching[key]
		if mine then
			state.rematch = "off"
		end
		state.another = if since then "searching" elseif mine == "Another" then "team" else "ready"
		state.searchingSince = since
		if a and a.teams then
			for _, team in a.teams do
				if table.find(team, me) then
					local ready = 0
					for _, id in team do
						if a.choices[tostring(id)] == "Another" then
							ready += 1
						end
					end
					state.teamReady, state.teamSize = ready, #team
				end
			end
		end
		local by = a and a.decideBy and a.decideBy[key]
		if by then
			state.deadline = by
		end
		state.leaving = mine == "Lobby"
			or teleportScreen:isShown()
			or (leftChoiceAt ~= nil and os.clock() - leftChoiceAt < M.ActionRetrySeconds)
		return state
	end
	-- A lobby table that has moved on: say so a moment, then the row goes.
	if state.rematch == "gone" then
		local since = lobbyGoneAt or now
		lobbyGoneAt = since
		if now - since > Config.UI.Queue.NoticeSeconds / 2 then
			return nil
		end
	else
		lobbyGoneAt = nil
	end
	return state
end

-- The status card's standing line: an arena's arrivals, or a teammate's search.
local function statusLine(now: number): string?
	if isArena then
		local a = arenaState
		if not a or a.begun then
			return nil
		end
		if a.notice == "NoOpponent" then
			return Strings.Arena.NoOpponent
		end
		local total = #(a.teams and a.teams[1] or {}) + #(a.teams and a.teams[2] or {})
		return Strings.Arena.WaitingFor:format(#(a.arrived or {}), math.max(total, 2))
	end
	local s = hub.mySeat and hub.snapshots[hub.mySeat]
	if s and s.phase == "Waiting" and s.search and s.hostId ~= player.UserId then
		if not table.find(s.search.users, player.UserId) then
			return nil
		end
		if s.search.found then
			return Strings.Match.Queue.MatchFound
		end
		local waited = math.max(0, math.floor(now - s.search.at))
		return Strings.Match.Queue.SearchTime:format(waited // 60, waited % 60)
	end
	return nil
end

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
	-- An arena's table has no host card: its players were matched by the global queue.
	queueMenu:setSnapshot(if isArena then nil else s, player.UserId)
	targets:setSnapshot(s, placement, match.state.geometry, player.UserId)
	local key = turnKey .. ":" .. s.phase
	if key ~= lastPhaseKey then
		lastPhaseKey = key
		if s.phase == "Intro" and shooter() then
			sound("YourTurn", M.YourTurnSound)
		elseif s.phase == "Foul" and s.foul and s.foul.by == player.UserId then
			sound("Foul", M.FoulSound)
		elseif s.phase == "CoinFlip" then
			-- As the coin starts to spin, after its YOU ARE HEADS/TAILS moment.
			task.delay(M.Style.CoinHoldSeconds, sound, "CoinFlip", M.CoinSound)
		end
	end
	refreshAim()
end
-- The pad you just left (Leave, or a game that ended): the server will not seat you on it
-- again until you step off, so neither does the predicted menu below.
local seatedAt: number? = nil
local leftPad: number? = nil
hub:onSeatChanged(function(id)
	if id == nil and seatedAt then
		leftPad = seatedAt
	end
	seatedAt = id
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
		zoomHint:dismiss() -- they know how to zoom now
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
-- shooting. Never the white, never the other side's balls, and the 8 only when it wins the
-- game: the server says so with the shot (`eightWins`), so an early, wrong-pocket or foul 8
-- gets no burst and no NICE SHOT! (designer, 2026-09-27). An open table rewards any object
-- ball; solo rewards every object ball, since both groups are the player's.
local function rewardsPocket(tableId: number, m: any, ballId: number): boolean
	if ballId == 0 then
		return false
	end
	if ballId == 8 then
		return m.shot ~= nil and m.shot.eightWins == true
	end
	local s = hub.snapshots[tableId]
	if not s then
		return true
	end
	local groups = m:revealedGroups() or s.groups or {}
	local group = if s.activeTeam then groups[s.activeTeam] else nil
	return s.solo ~= nil or group == nil or Judge.group(ballId) == group
end
for id = 1, Placement.tableCount() do
	local m = assert(hub:matchFor(id))
	local a = Audio.new(visuals)
	audioByTable[id] = a
	a:attach(m)
	local e = Effects.new(visuals)
	effectsByTable[id] = e
	m:onEvent(function(ev, index)
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
				-- NICE SHOT! for a good pot that was a bank, combo, kick or carom; never on the
				-- break, and not for a drop a late joiner's replay only caught up with.
				local s = hub.snapshots[id]
				local shot = m.shot
				if
					shot
					and not (s and s.breakShot)
					and m.state.time - ev.t < Config.Effects.NiceShot.FreshSeconds
					and NiceShot.isNice(shot.events, ev.ball, index, m.state.geometry.pockets)
				then
					e:niceShot(at)
				end
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
	-- The D-pad in the hub opens the left column's menus (Shop, Inventory, Rewards, Trade);
	-- never in a match, while a menu is open (its D-pad moves the selection) or while a text
	-- box has focus (Progression.padRoute). B closing an open menu is Menus' own binding.
	if Progression.padRoute(key.KeyCode) then
		return
	end
	if
		(
			key.KeyCode == Enum.KeyCode.L
			or (key.KeyCode == Enum.KeyCode.ButtonB and not input.enabled)
		)
		and snapshot
		and not Progression.isBusy()
	then
		leave()
	elseif key.KeyCode == Enum.KeyCode.Escape and hud:isModal() then
		hud:closeModal()
	elseif
		key.KeyCode == Enum.KeyCode.ButtonY
		and snapshot
		and snapshot.phase == "Waiting"
		and not Progression.isBusy()
	then
		queueMenu:focus()
	elseif key.KeyCode == Enum.KeyCode.ButtonY and not snapshot and opponentPrompt:isOpen() then
		opponentPrompt:focus()
	elseif key.KeyCode == Enum.KeyCode.ButtonY and not snapshot then
		Progression.toggleRank() -- opens the roadmap, or closes it
	elseif key.KeyCode == Enum.KeyCode.F3 then
		UI.toggleStatus()
	end
end)
local zones = workspace:WaitForChild("TableZones")
local padEffects = PadEffects.new(zones)
local mapAmbience = MapAmbience.new() -- the map's drifting sailboats
local dayCycle = DayCycle.new() -- the map's day and sunset light (an arena starts at day)
local firePit = FirePit.new() -- the fire pit's fire, lit at sunset
local tableSign = TableSign.new(player:WaitForChild("PlayerGui"))
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
-- Which table's pad a root stands on (grown by `margin` studs), the same test as the
-- server's (TableService onPad), or nil.
local predictedPad: number? = nil
local function padUnder(root: BasePart, margin: number): number?
	for id = 1, Placement.tableCount() do
		local pad = zones:FindFirstChild(("QueuePad_%02d"):format(id))
		if pad and pad:IsA("BasePart") then
			local d = pad.CFrame:PointToObjectSpace(root.Position)
			if
				math.abs(d.X) <= pad.Size.X / 2 + margin
				and math.abs(d.Z) <= pad.Size.Z / 2 + margin
				and math.abs(d.Y) < M.QueueVisual.VerticalTolerance
			then
				return id
			end
		end
	end
	return nil
end
-- Y in the hub can leave the gamepad's selection on the host menu or the opponent prompt,
-- and a selected button takes the left stick from walking. A hard push that has not moved
-- the selection after Gamepad.FreeStickSeconds (it hit the menu's edge) lets go of the menu
-- so the player walks again.
local freeStick = { at = nil :: number?, from = nil :: GuiObject?, moved = false }
local function freeStickFromMenu()
	local G = Config.Input.Gamepad
	local selected = GuiService.SelectedObject
	local inMenu = selected ~= nil
		and (queueMenu:focused() or selected:IsDescendantOf(opponentPrompt.root))
	local push = 0
	if inMenu then
		for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if state.KeyCode == Enum.KeyCode.Thumbstick1 then
				push = Vector2.new(state.Position.X, state.Position.Y).Magnitude
			end
		end
	end
	if push < G.FreeStickPush then
		freeStick.at, freeStick.from, freeStick.moved = nil, nil, false
		return
	end
	local now = os.clock()
	if freeStick.at == nil then
		freeStick.at, freeStick.from, freeStick.moved = now, selected, false
		return
	end
	if selected ~= freeStick.from then
		freeStick.moved = true -- this push went somewhere in the menu: it is navigating
	end
	if not freeStick.moved and now - freeStick.at >= G.FreeStickSeconds then
		GuiService.SelectedObject = nil
		freeStick.at, freeStick.from, freeStick.moved = nil, nil, false
	end
end
-- In a match the gamepad plays, and a selected button would take its sticks (the input is
-- off while anything is selected). Starting a game from the host menu with the gamepad hides
-- the menu under its selection, and Roblox hands the selection to the next button it finds
-- (the spin toggle), so the player had to press Circle before they could play (designer,
-- 2026-09-27). Drop any selection there that is not one of the match's own: the leave
-- dialog, the pocket rings while calling the 8, or a result or NEW RANK! screen.
local function dropStrayMatchSelection()
	local selected = GuiService.SelectedObject
	if not selected or not snapshot or snapshot.phase == "Waiting" then
		return
	end
	if
		selected:IsDescendantOf(hud.modal)
		or selected:IsDescendantOf(targets.root)
		or Progression.isBusy()
	then
		return
	end
	GuiService.SelectedObject = nil
end
RunService.RenderStepped:Connect(function(dt)
	local busy = hub:update(dt)
	for id = 1, Placement.tableCount() do
		local a = audioByTable[id]
		local m = assert(hub:matchFor(id))
		a:updateRoll(m, dt)
		a:updatePull(dt)
		local e = effectsByTable[id]
		-- Cue looks: the trail and pocket bursts are the current shooter's equipped cue's.
		local s = hub.snapshots[id]
		e:follow(if s then s.shooter else nil)
		local part = hub:cueBallPartFor(id)
		if part and e.boundCue ~= part then
			e:attachTrail(part)
			e.boundCue = part
		elseif part == nil and e.boundCue then
			-- The renderer went to another table: take this table's trail off its ball.
			e:detachTrail()
			e.boundCue = nil
		end
		e:updateTrail(m:findCueBall(), m:isBusy())
	end
	padEffects:update(dt, queueOpen, hub.mySeat ~= nil or controlled, tableSign.id)
	-- The shot clock's last seconds tick once a second for the shooter, until the shot goes.
	if
		snapshot
		and aimTurn()
		and Engine.isShotClock(snapshot.phase, snapshot.breakShot)
		and snapshot.deadline
	then
		local second = math.ceil(snapshot.deadline - workspace:GetServerTimeNow())
		if tickTurn ~= snapshot.turnId then
			tickTurn, tickSecond = snapshot.turnId, second -- a turn starts: no tick for it yet
		elseif second ~= tickSecond then
			tickSecond = second
			if second >= 1 and second <= Config.Audio.ClockTick.FromSeconds then
				audioByTable[snapshot.id]:clockTick(second)
			end
		end
	end
	mapAmbience:update(os.clock())
	dayCycle:update(os.clock())
	firePit:update(os.clock(), dayCycle.blend or 0)
	-- The sign over the table you walk up to, or over your own while you wait on its pad as a
	-- guest; none while you host (your own card stands there) or play. Stepping onto an
	-- empty pad makes you its host before the server says so (predictedPad, below).
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local seated = hub.mySeat and hub.snapshots[hub.mySeat]
	local waiting = seated ~= nil and seated.phase == "Waiting"
	local predictedHost = predictedPad ~= nil
		and hub.snapshots[predictedPad] ~= nil
		and hub.snapshots[predictedPad].hostId == nil
	local hosting = (waiting and seated.hostId == player.UserId) or predictedHost
	-- Stepped off your pad: the host's card goes at once (designer, 2026-09-27: it lingered),
	-- not when the server lets you go after its exit grace; back on in time, it comes back.
	local root = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	queueMenu:setAway(waiting and root ~= nil and padUnder(root, 0) ~= hub.mySeat)
	tableSign:update(
		if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil,
		controlled or hosting or (hub.mySeat ~= nil and not waiting),
		if waiting and not hosting then hub.mySeat else nil,
		zones,
		function(id: number)
			return hub.snapshots[id]
		end,
		workspace:GetServerTimeNow()
	)
	opponentPrompt:update(
		workspace:GetServerTimeNow(),
		hub.mySeat ~= nil or controlled,
		function(id: number)
			return hub.snapshots[id]
		end
	)
	-- The global queue's screens and the rematch row.
	do
		local serverNow = workspace:GetServerTimeNow()
		local summary = Progression.choosing()
		if summary then
			local state = postMatchState(summary, serverNow)
			if state then
				Progression.setChoices(state, serverNow)
			else
				Progression.endChoices()
			end
		else
			lobbyGoneAt = nil
		end
		queueStatus:setLine(statusLine(serverNow))
		queueStatus:update()
		teleportScreen:update()
	end
	-- Stepping onto a pad pops the host menu this frame (designer, 2026-09-26: "it needs to
	-- be instant"), before the server, which polls the pads, has seated you: the table's
	-- snapshot with you added. The server's own arrives a moment later and takes over; if it
	-- never seats you (the pad filled first), the menu goes when you step off.
	if hub.mySeat == nil and not controlled then
		local root = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
		local on = root and padUnder(root, 0)
		if leftPad and not (root and padUnder(root, M.QueueVisual.AreaMargin) == leftPad) then
			leftPad = nil
		end
		local s = if on and on ~= leftPad then hub.snapshots[on] else nil
		if s and s.phase == "Waiting" and #s.seats < s.teamSize * 2 then
			local predicted = table.clone(s)
			predicted.seats = table.clone(s.seats)
			table.insert(predicted.seats, {
				userId = player.UserId,
				name = player.Name,
				displayName = player.DisplayName,
				connected = true,
			})
			predicted.hostId = s.hostId or player.UserId
			queueMenu:setSnapshot(predicted, player.UserId)
			queueMenu:update(workspace:GetServerTimeNow())
			predictedPad = on
		elseif predictedPad then
			predictedPad = nil
			queueMenu:setSnapshot(nil, player.UserId)
		end
	elseif predictedPad then
		predictedPad = nil -- the server has seated you; the real snapshot drives the menu
	end
	-- Ranks and money: the rank HUD hides while you play, your match's nameplates too, and a
	-- rank-up popup waits until your shot is over.
	local inMatch = seated ~= nil and seated.phase ~= "Waiting" and seated.phase ~= "Result"
	local matchIds = {}
	if inMatch then
		for _, s in seated.seats do
			matchIds[s.userId] = true
		end
	end
	Progression.update({ inMatch = inMatch, shooting = controlled, matchUserIds = matchIds })
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
	powerCue:place(hud:reservedHeight()) -- under the top bar on a phone, centred on a big screen
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
	UI.setPlayControlsVisible(canShoot() and not modal)
	zoomHint:setVisible(canShoot() and not modal)
	padGuide:setVisible(canShoot() and not modal)
	padGuide:setSet(if input.spinEditing then "spin" else "aim")
	freeStickFromMenu()
	dropStrayMatchSelection()
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
