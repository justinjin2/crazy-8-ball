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
local PadBar = require(Shared.Matchmaking.PadBar)
local AuraQuiet = require(Shared.AuraQuiet)
local TableBuilder = require(Shared.TableBuilder)
local CueStickBuilder = require(Shared.CueStickBuilder)
local Simulation = require(Shared.Physics.Simulation)
local Aim = require(Shared.Physics.Aim)
local Judge = require(Shared.Rules.ShotJudge)
local Engine = require(Shared.Rules.MatchEngine)
local TimeStop = require(Shared.Ults.Effects.TimeStop)
local UltCatalog = require(Shared.Ults.Catalog)
local NiceShot = require(Shared.Rules.NiceShot)
local Audio = require(script.Parent.Audio)
local Avatar = require(script.Parent.Avatar)
local BackCue = require(script.Parent.BackCue)
local BotChat = require(script.Parent.BotChat) -- the Bots lane
local People = require(script.Parent.People) -- the Bots lane: players and bots behind one lookup
local TutorialAnchors = require(script.Parent.TutorialAnchors) -- the tutorial lane
local BallCallouts = require(Shared.BallCallouts)
local BallPulse = require(script.Parent.BallPulse)
local CueAssets = require(script.Parent.CueAssets)
local CueSkinLook = require(script.Parent.CueSkinLook)
local Effects = require(script.Parent.Effects)
local Camera = require(script.Parent.Camera)
local DayCycle = require(script.Parent.DayCycle)
local FirePit = require(script.Parent.FirePit)
local FontTest = require(script.Parent.FontTest)
local HoleFill = require(script.Parent.HoleFill)
local Guideline = require(script.Parent.Guideline)
local Input = require(script.Parent.Input)
local MapAmbience = require(script.Parent.MapAmbience)
local Hub = require(script.Parent.Hub)
local PowerCue = require(script.Parent.PowerCue)
local SpinSelector = require(script.Parent.SpinSelector)
local ZoomHint = require(script.Parent.ZoomHint)
local PadGuide = require(script.Parent.PadGuide)
local UltHud = require(script.Parent.UltHud)
local UltPick = require(script.Parent.UltPick)
local UltCutscene = require(script.Parent.UltCutscene)
local AbilityFx = require(script.Parent.AbilityFx)
local LookOverThereFx = require(script.Parent.LookOverThereFx)
local UltScreen = require(script.Parent.UltScreen)
local UI = require(script.Parent.UI)
local MatchHUD = require(script.Parent.MatchHUD)
local StreakHud = require(script.Parent.StreakHud)
local MatchTargets = require(script.Parent.MatchTargets)
local PadEffects = require(script.Parent.PadEffects)
local MatchBar = require(script.Parent.MatchBar)
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
BotChat.start() -- a bot's chat bubble and line (the Bots lane)
-- The developer's /slowmo (Studio only, DevCommands): each table's replay rate rides on a
-- workspace attribute (Config.Debug.Commands.SlowmoAttribute .. the table id); none is 1.
for id = 1, Placement.tableCount() do
	local attribute = Config.Debug.Commands.SlowmoAttribute .. id
	local function applySlowmo()
		local m = hub:matchFor(id)
		local scale = workspace:GetAttribute(attribute)
		if m then
			m:setTimeScale(if type(scale) == "number" then scale else 1)
		end
	end
	workspace:GetAttributeChangedSignal(attribute):Connect(applySlowmo)
	applySlowmo()
	-- The developer's /hold: the replay stops at that shot time (Config.Debug.Commands.Hold).
	local holdAttribute = Config.Debug.Commands.HoldAttribute .. id
	local function applyHold()
		local m = hub:matchFor(id)
		local at = workspace:GetAttribute(holdAttribute)
		if m then
			m:setHold(if type(at) == "number" then at else nil)
		end
	end
	workspace:GetAttributeChangedSignal(holdAttribute):Connect(applyHold)
	applyHold()
end
-- Ultimates: the activation cutscene everyone at the table sees, then every ability's look
-- and sound (Config.UI.AbilityFx.Looks: Magnet's is MagnetFx), armed at each activation's
-- arming moment.
local ultCutscene = UltCutscene.start(hub)
local abilityFx = AbilityFx.start(hub, visuals, ultCutscene)
local input = Input.new()
-- On every stick a switched-in cue is painted only once the renderer has loaded it (CueAssets).
CueStickBuilder.setLoader(CueAssets)
local cueStick = CueStickBuilder.build(visuals)
-- Cue looks: the stick is the player's equipped cue, repainted whenever they equip another.
CueStickBuilder.wear(cueStick, player)
-- Its skin's look with the full aura (designer, 2026-10-01: the aura shows in the hands too).
CueSkinLook.attach(cueStick, { aura = true })
-- Everyone's cue on their back, hidden while it is in their hands (updated after the frame).
local backCue = BackCue.new(visuals)
local avatar = Avatar.new()
local screen = UI.screen()
local powerCue = PowerCue.new(screen)
powerCue:follow(player) -- cue looks: the power bar's cue is the equipped one too
UI.addPlayControl(powerCue.root)
local spinSelector = SpinSelector.new(screen, input)
local zoomHint = ZoomHint.new(screen) -- scroll or pinch to zoom, over the spin button
local padGuide = PadGuide.new(screen) -- the controller guide, bottom left, on a gamepad
-- The ult bar, bottom centre on your turn (always full in solo); a press sends UltActivate.
local ultHud = UltHud.new(screen, function()
	Net.get("UltActivate"):FireServer()
end)
task.spawn(function()
	Net.get("UltGain").OnClientEvent:Connect(function(payload: any)
		ultHud:onGain(payload)
	end)
	Net.get("UltNotice").OnClientEvent:Connect(function(notice: any)
		ultHud:onNotice(notice)
	end)
end)
-- An ability's aim-phase pick (Heat Seeker's ball, Portals' spots): the top-down pick view
-- sends the UltPick table action; the shot waits for it (canShoot).
local ultPick = UltPick.new(screen, function(data)
	hub:action("UltPick", data)
end)
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
local matchBar: any = nil
local targets: any = nil
local awaitingAt: number? = nil
-- Time Stop: how many strikes the server had taken when this player sent one in stopped time
-- (nil otherwise); a reply with more clears awaitingAt, as a new turn does for a normal shot.
local strikesAtSend: number? = nil
-- The shot clock's ticks (Config.Audio.ClockTick): the turn they are for and the second the
-- clock last showed, so each second ticks once.
local tickTurn: number? = nil
local tickSecond = 0
local currentPull = 0
-- The shot the guideline traces while the local player aims (AbilityFx.AimShot, for an armed
-- ability's look: Eagle's Eye's path), nil while it is hidden.
local aimShot: AbilityFx.AimShot? = nil
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
-- The balls pulse when the groups are decided and at a team's last ball (BallCallouts).
local callouts = BallCallouts.new()
local ballPulse = BallPulse.new()

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
-- The ability the local shooter has armed (arming or armed), for the power bar's skin.
local function ownArmedUlt(): string?
	if not shooter() then
		return nil
	end
	local ults = (snapshot :: any).ults
	local armed = if type(ults) == "table" then ults.armed else nil
	return if type(armed) == "table" and type(armed.id) == "string" then armed.id else nil
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
-- Time Stop (7.7): the shooter's strikes in stopped time. Their replay has reached the freeze
-- (or the last strike's end), it is still frozen with a strike left, and no strike of theirs is
-- still on its way: they aim and shoot the cue ball from where it stopped, any ball a fair
-- target.
local function frozenTurn(): boolean
	if not shooter() or awaitingAt or not match or snapshot.phase ~= "Frozen" then
		return false
	end
	if not match:isHalted() or not TimeStop.isFrozen(match.state) then
		return false
	end
	local cue = match:findCueBall()
	if cue == nil or cue.pocketed then
		return false -- frozen dropping into a pocket: the server takes no strike ("NoCueBall")
	end
	-- Every strike the server has taken is already in the replay (none still on its way).
	local shot = match.shot
	local sent = shot and shot.parts and shot.parts.strikes
	return sent == nil or #sent <= (shot :: any).applied.strikes
end
local function aimTurn(): boolean
	if frozenTurn() then
		return true
	end
	if not shooter() or awaitingAt or not match or match:isBusy() then
		return false
	end
	return snapshot.phase == "Aiming" or snapshot.phase == "Intro" or snapshot.phase == "Placement"
end
-- Look Over There!'s sneak on a gamepad (the render step): the left stick, shaped as ball in
-- hand's (the aim's dead zone, the placement curve), moves the cue ball; let go, it is sent.
local sneakSticking = false
local function sneakStick(dt: number)
	if not UserInputService:GetGamepadConnected(Enum.UserInputType.Gamepad1) then
		return
	end
	local x, y = 0, 0
	for _, state in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
		if state.KeyCode == Enum.KeyCode.Thumbstick1 then
			x, y = state.Position.X, state.Position.Y
		end
	end
	local G = Config.Input.Gamepad
	local length = math.sqrt(x * x + y * y)
	local edge = math.min(length, 1)
	local shaped = if edge > G.AimDeadZone
		then ((edge - G.AimDeadZone) / (1 - G.AimDeadZone)) ^ G.PlaceCurve
		else 0
	if shaped > 0 then
		sneakSticking = true
		targets:stickMove(x / length * shaped, y / length * shaped, dt)
	elseif sneakSticking then
		sneakSticking = false
		targets:finishGesture(true)
	end
end

local function canShoot(): boolean
	if not aimTurn() or (hud and hud:isModal()) then
		return false
	end
	if callPending() then
		return false
	end
	-- An ult still in its cutscene: the server would refuse the shot until it is armed.
	if UltHud.arming(snapshot, workspace:GetServerTimeNow()) then
		return false
	end
	-- An ability's pick still owed: the server would refuse the shot ("PickRequired").
	if ultPick:blocking() then
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
		aimShot = nil
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
	local spin = input:getSpin()
	local elevation = input:getElevation()
	local armedUlt = ownArmedUlt()
	-- A launch ability armed (Black Flash, Fire Shot) speeds the cue ball off the cue: a jump
	-- flies that much further.
	local trace = Aim.trace(match.state, {
		angle = input.angle,
		power = math.max(currentPull, Config.Input.MinPowerToShoot),
		spin = spin,
		elevation = elevation,
	}, UltCatalog.launchScale(armedUlt))
	-- The raw pull, not the clamped one: below MinPowerToShoot means not pulling yet.
	aimShot = {
		angle = input.angle,
		power = currentPull,
		spin = spin,
		elevation = elevation,
	}
	-- On the break any ball is a fair first target (ShotJudge); afterwards only the shooter's
	-- group, or the 8 once it is theirs.
	local invalid = trace.objectId ~= nil
		and not snapshot.breakShot
		and not frozenTurn()
		and not Judge.legalTarget(
			match.state.balls,
			snapshot.groups[snapshot.activeTeam],
			trace.objectId
		)
	-- The host's difficulty decides how many lines are drawn; the wrong-target warning is
	-- shown at every level (Config.Difficulty). Fire Shot armed: every line, and the two after
	-- the first contact run on to the next cushion (Aim.fullLines).
	local full = if UltCatalog.fullLines(armedUlt) then Aim.fullLines(match.state, trace) else nil
	guideline:show(trace, invalid, snapshot.settings and snapshot.settings.difficulty, full)
	hud:setInvalidTarget(invalid)
end
local function sound(key: string, id: string, volume: number?)
	local existing = uiSounds[key]
	if existing then
		existing:Stop()
		existing:Play()
		return
	end
	local created = Instance.new("Sound")
	created.Name, created.SoundId, created.Volume = key, id, volume or M.UISoundVolume
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
		ballPulse:clear()
		return
	end
	local team = 1
	for _, s in view.seats do
		if s.userId == player.UserId then
			team = s.team
		end
	end
	local group = view.groups[team]
	-- The tutorial's game 1: the player's colour is solids from the break on (Tutorial/Rig).
	if group == nil and TutorialAnchors.game1() then
		group = "solids"
	end
	local downMask = 0
	local down: { [number]: boolean } = {}
	local left: { [string]: number } = { solids = 0, stripes = 0 } -- balls still up per group
	for id = 1, 15 do
		local ball = Judge.group(id)
		if view.balls[id * 4 + 4] == 1 then
			downMask = bit32.bor(downMask, bit32.lshift(1, id))
			down[id] = true
		elseif ball then
			left[ball] += 1
		end
	end
	-- The groups just decided: this player's group pulses green; a team down to its last ball:
	-- that ball pulses green for everyone (designer, 2026-10-06).
	local P = M.Style.BallPulse
	local gameKey = ("%d:%d"):format(view.id, view.epoch)
	if gameKey ~= callouts.key then
		ballPulse:clear() -- another table or a new game: the last one's pulse stops
	end
	local calls = BallCallouts.observe(callouts, gameKey, view.groups, down, view.solo ~= nil)
	if #calls > 0 then
		local mine = view.groups[team]
		local items: { BallPulse.Item } = {}
		for _, call in calls do
			for _, b in match.state.balls do
				local part = renderer.parts and renderer.parts[b.id]
				local wanted = if call.kind == "Reveal"
					then mine ~= nil and Judge.group(b.id) == mine
					else b.id == call.ball
				if wanted and not down[b.id] and part and part:IsA("BasePart") then
					table.insert(items, { part = part, color = rgb(P.Color) })
				end
			end
		end
		ballPulse:start(items, P.Pulses * P.PulseSeconds)
	end
	-- Solo plays the first group, then the other: read off the balls shown down, so the
	-- switch (and the 8) comes the moment the replay drops the last of the first group.
	local first = view.solo and (view.solo.first or group)
	if first then
		group = if left[first] > 0 then first else Judge.opposite(first)
	end
	local eight = group ~= nil and left[group] == 0
	local key = ("%d:%d:%s:%s:%d:%s"):format(
		view.id,
		view.epoch,
		group or "",
		tostring(eight),
		downMask,
		tostring(ballPulse:active())
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
	-- The tutorial's game 1 always uses the strong style (the tutorial lane).
	local strong = S.StrongBallHighlights or TutorialAnchors.game1()
	for _, b in match.state.balls do
		local ball = Judge.group(b.id)
		local own = ball == group or (b.id == 8 and eight)
		local other = strong and ball ~= nil and ball ~= group
		local part = renderer.parts and renderer.parts[b.id]
		-- A pulsing ball has the pulse's glow instead (BallPulse).
		if
			view.balls[b.id * 4 + 4] ~= 1
			and (own or other)
			and part
			and part:IsA("BasePart")
			and not ballPulse:has(part)
		then
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
	local strikes = match and match.shot and match.shot.parts and match.shot.parts.strikes
	strikesAtSend = if snapshot.phase == "Frozen" then (if strikes then #strikes else 0) else nil
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
	elseif kind == "SetDifficulty" or kind == "SetAbilities" then
		hub:action(kind, { value = value })
	else
		hub:action(kind)
	end
end
hud = MatchHUD.new(screen, action)
-- The ball streak under the match popups (Rules/Streak decides it; each step plays as the
-- replay drops its ball, from the per-table hook below).
local streakHud = StreakHud.new(screen, hub, hud)
padGuide:attachLeave(hud.leave) -- the Circle beside Leave
matchBar = MatchBar.new(screen, action)
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
-- The ult spin screen ("Ults" in Menus): the column's 5th tile and gamepad X in the hub open
-- it.
UltScreen.start(screen)
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
local function postMatchState(summary: any, now: number): (any?, boolean)
	local me = player.UserId
	local s = hub.snapshots[summary.tableId]
	if s and s.epoch > summary.epoch and s.phase ~= "Waiting" and hub.mySeat == summary.tableId then
		return nil, true -- the rematch has begun
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
		return state, false
	end
	-- A lobby table that has moved on: say so a moment, then the row goes.
	if state.rematch == "gone" then
		local since = lobbyGoneAt or now
		lobbyGoneAt = since
		if now - since > Config.UI.Queue.NoticeSeconds / 2 then
			return nil, false
		end
	else
		lobbyGoneAt = nil
	end
	return state, false
end

-- The status card's standing line: an arena's arrivals, or a teammate's search.
local function statusLine(): string?
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
	-- A teammate's search on the pad shows on the matchmaking bar (MatchBar).
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
		ultHud:setSnapshot(nil, player.UserId)
		ultPick:setSnapshot(nil, nil, nil, player.UserId)
		matchBar:setSnapshot(nil, player.UserId)
		hudView, viewVersion = nil, -1
		clearHighlights()
		ballPulse:clear()
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
	ultHud:setSnapshot(s, player.UserId)
	ultPick:setSnapshot(s, match, placement, player.UserId)
	-- An arena's table has no host card: its players were matched by the global queue.
	matchBar:setSnapshot(if isArena then nil else s, player.UserId)
	targets:setSnapshot(s, placement, match.state.geometry, player.UserId)
	local key = turnKey .. ":" .. s.phase
	if key ~= lastPhaseKey then
		lastPhaseKey = key
		if s.phase == "Intro" and shooter() then
			sound("YourTurn", M.YourTurnSound)
		elseif s.phase == "Foul" and s.foul and s.foul.by == player.UserId then
			sound("Foul", M.FoulSound, M.FoulSoundVolume)
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
			streakHud:onPocket(id, m, ev, index)
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
					a:niceClap(at)
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
		matchBar:focus()
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
FontTest.watch(player:WaitForChild("PlayerGui")) -- Config.UI.FontTest's fonts, if any
if Config.UI.Kit.HoleFill.Everywhere then
	-- Solid ink in every outlined letter's holes, and the thick ink lip under them.
	HoleFill.watch(player:WaitForChild("PlayerGui"), Config.UI.Kit.HoleFill.Drop.Everywhere)
end
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
		and (matchBar:focused() or selected:IsDescendantOf(opponentPrompt.root))
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
-- Cue looks: the shot effects (pocket finisher creatures, trail and pocket sprites) of your
-- cue and of everyone at the drawn tables load before they play (CueAssets.holdShots), yours
-- and your table's first.
local shotsClock = math.huge
local function holdShots(dt: number)
	shotsClock += dt
	if shotsClock < Config.CueSkins.Warm.ShotRefreshSeconds then
		return
	end
	shotsClock = 0
	local ids = { CueStickBuilder.equippedCue(player) }
	local tables: { number } = {}
	if hub.mySeat then
		table.insert(tables, hub.mySeat)
	end
	for id in hub.boundTo do
		if id ~= hub.mySeat then
			table.insert(tables, id)
		end
	end
	for _, id in tables do
		for _, seat in hub:seatsAt(id) do
			local seated = People.owner(seat.userId) -- a player or a bot (the Bots lane)
			if seated then
				table.insert(ids, CueStickBuilder.equippedCue(seated))
			end
		end
	end
	CueAssets.holdShots(ids)
end
-- Quieter auras in a match (AuraQuiet): the shooter's cue and, on your turn, every cue at
-- your table.
local quietClock = math.huge
local quietSticks: { [Model]: number } = {}
local function quietAuras(dt: number)
	quietClock += dt
	if quietClock < Config.CueSkins.Quiet.CheckSeconds then
		return
	end
	quietClock = 0
	table.clear(quietSticks)
	quietSticks[cueStick] = player.UserId
	hub.watched:owners(quietSticks)
	backCue:owners(quietSticks)
	AuraQuiet.apply(quietSticks, player.UserId, hub.snapshots)
end
local function renderFrame(dt: number)
	-- The tutorial lane: an aim the tutorial asked for (its locked break, the aim lesson).
	local tutorialAim = TutorialAnchors.takeAim()
	if tutorialAim then
		input:setAngle(tutorialAim)
	end
	-- A shot halted for Time Stop's second strike aims like a turn, not like a replay.
	local busy = hub:update(dt) and not frozenTurn()
	holdShots(dt)
	quietAuras(dt)
	-- The reach preview rides on the guideline's first contact, an armed look's aim hook on the
	-- shot it traces (last frame's; nil unless the player is aiming).
	abilityFx:update(dt, if guideline then guideline:contact() else nil, aimShot)
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
	local standing = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	padEffects:update(
		dt,
		queueOpen,
		hub.mySeat ~= nil or controlled,
		tableSign.id,
		if standing and standing:IsA("BasePart") then standing.Position else nil
	)
	-- The shot clock's last seconds tick once a second for the shooter, until the shot goes.
	if
		snapshot
		and aimTurn()
		and Engine.isShotClock(snapshot.phase, snapshot.breakShot)
		and snapshot.deadline
	then
		-- Held while an ult is activated, as the HUD's clock (MatchHUD.clockLeft).
		local second = math.ceil(MatchHUD.clockLeft(snapshot, workspace:GetServerTimeNow()))
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
	firePit:update(os.clock(), dayCycle.fire)
	-- The sign over the table you walk up to; none while you are on a pad (the matchmaking
	-- bar says it all, host or guest) or play. Stepping onto a pad shows the bar before the
	-- server has seated you (predictedPad, below).
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local seated = hub.mySeat and hub.snapshots[hub.mySeat]
	local waiting = seated ~= nil and seated.phase == "Waiting"
	-- Stepped off your pad: the bar goes at once (designer, 2026-09-27: the card lingered),
	-- not when the server lets you go after its exit grace; back on in time, it comes back.
	local root = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	matchBar:setAway(waiting and root ~= nil and padUnder(root, 0) ~= hub.mySeat)
	tableSign:update(
		if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil,
		controlled or hub.mySeat ~= nil or predictedPad ~= nil,
		nil,
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
			local state, rematch = postMatchState(summary, serverNow)
			if state then
				Progression.setChoices(state, serverNow)
			elseif rematch then
				Progression.endChoices()
			else
				-- No rematch: the result screen stays, with Continue in the row's place.
				Progression.dropChoices()
			end
		else
			lobbyGoneAt = nil
		end
		queueStatus:setLine(statusLine())
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
			matchBar:setSnapshot(predicted, player.UserId)
			predictedPad = on
		elseif predictedPad then
			predictedPad = nil
			matchBar:setSnapshot(nil, player.UserId)
		end
	elseif predictedPad then
		predictedPad = nil -- the server has seated you; the real snapshot drives the menu
	end
	-- The matchmaking bar, every frame: a pad's, or the spawn pill of a player in a public
	-- lobby server with nobody else free (designer, 2026-10-07: never in a private server, not
	-- during the tutorial; a step it has not published yet counts as the tutorial; 2026-10-09:
	-- also when everyone else is busy at a table).
	do
		local step = player:GetAttribute("TutorialStep")
		local others = {}
		for _, p in Players:GetPlayers() do
			if p ~= player then
				table.insert(others, p.UserId)
			end
		end
		matchBar:setSpawn({
			nobodyFree = PadBar.nobodyFree(others, hub.snapshots),
			publicLobby = workspace:GetAttribute(Config.UI.MatchBar.PublicLobbyAttribute) == true
				and not isArena,
			tutorial = type(step) ~= "string" or step ~= "",
			seated = hub.mySeat ~= nil or controlled or predictedPad ~= nil,
		})
		matchBar:update(workspace:GetServerTimeNow())
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
	Progression.update({
		inMatch = inMatch,
		afterMatch = seated ~= nil and seated.phase == "Result",
		shooting = controlled,
		matchUserIds = matchIds,
		-- The matchmaking bar or an opponent's ask has the space over the hotbar.
		overHotbar = matchBar:isOpen() or opponentPrompt:isOpen(),
	})
	-- The ult bar: it fades while the cue is pulled back, the bottom lines sit above it, and the
	-- controller guide lists "Ult" while it offers its press.
	ultHud:update(dt, currentPull > 0)
	hud:setUltReserve(ultHud:reservedBottom())
	padGuide:setUlt(ultHud:promptShown())
	if not snapshot or not match then
		return
	end
	-- hub:update has dispatched this frame's events; show any ball they dropped.
	if match.downVersion ~= viewVersion then
		refreshView()
	end
	if ballPulse:step() then
		highlightOwn()
	end
	local now = workspace:GetServerTimeNow()
	-- A strike in stopped time has no new turn to answer it: its part arriving does (else the
	-- shooter waited out ActionRetrySeconds of their FrozenSeconds; the audit).
	if awaitingAt and strikesAtSend then
		local sent = match.shot and match.shot.parts and match.shot.parts.strikes
		if (sent and #sent > strikesAtSend) or snapshot.phase ~= "Frozen" then
			awaitingAt, strikesAtSend = nil, nil
		end
	end
	if awaitingAt and now - awaitingAt >= M.ActionRetrySeconds then
		awaitingAt = nil
		Net.get("SnapshotRequest"):FireServer()
	end
	hud:update(now)
	powerCue:place(hud:reservedHeight()) -- under the top bar on a phone, centred on a big screen
	powerCue:setSkin(ownArmedUlt()) -- a Legendary or Mythic ability dresses the bar
	local modal = hud:isModal()
	if modal ~= wasModal then
		input:setSpinEditing(false)
		if modal then
			input:setEnabled(false)
		end
		wasModal = modal
	end
	-- An ability's pick owed (UltPick): top-down, the ball in hand held still meanwhile.
	local picking = ultPick:setActive(
		aimTurn() and not callPending() and not UltHud.arming(snapshot, now),
		not modal,
		hud:reservedHeight()
	)
	targets:setEnabled(not modal and awaitingAt == nil and not match:isBusy() and not picking)
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
	padGuide:setVisible((canShoot() or picking) and not modal)
	padGuide:setSet(ultPick:padSet() or (if input.spinEditing then "spin" else "aim"))
	freeStickFromMenu()
	dropStrayMatchSelection()
	input:update(dt)
	if controlled then
		-- Top-down only while a pocket is being called for the 8, an ability's pick is owed or
		-- Look Over There!'s sneak is on (the cue ball moved with ball in hand's drag:
		-- MatchTargets); everything else, placing the cue ball included, plays in the 3D view.
		local overhead = phase == "PocketChoice"
			or (phase == "Intro" and callPending())
			or picking
			or phase == "Sneak"
		local header = if picking
			then ultPick:reserveTop()
			elseif phase == "Sneak" then LookOverThereFx.reserveTop(hud:reservedHeight())
			else hud:reservedHeight() + M.Style.TargetSize / 2
		Camera.setMode(
			overhead,
			header + GuiService:GetGuiInset().Y,
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
			-- Look Over There!: the shooter stands up and points in their own close-up.
			ctx.showBody = phase == "Sneak"
			local out = avatar:update(dt, ctx)
			CueStickBuilder.setVisible(cueStick, out.visible)
			-- Raised for a jump shot: on this screen only, nearly see-through, so it never
			-- hides the ball or the arc (Config.Cue.RaisedCueFade).
			local raised = ctx.elevation > Config.Cue.CueElevationDegrees
			-- Raised by the player, or lifted visibly over a rail: every effect off.
			local fxOff = raised
				or out.pitch > Config.Cue.CueElevationDegrees + Config.Cue.RaisedFxOffDegrees
			if cueStick:GetAttribute("AuraOff") ~= fxOff then
				cueStick:SetAttribute("AuraOff", fxOff)
			end
			if out.visible then
				CueStickBuilder.placeAt(cueStick, out.tip)
				Camera.fadeNear(
					cueStick,
					Config.Cue.CameraFadeStuds,
					if raised then Config.Cue.RaisedCueFade else nil
				)
			end
		end
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	-- Look Over There!'s sneak on a gamepad: the left stick moves the cue ball at once (no LT
	-- to hold: there is nothing else to do), and letting go sets it down.
	if phase == "Sneak" and targets:canPlace() then
		sneakStick(dt)
	elseif sneakSticking then
		sneakSticking = false
	end
	targets:update(dt, workspace.CurrentCamera)
	ultPick:update(dt, workspace.CurrentCamera)
	-- (Look Over There!'s sneak has its own countdown pill, and no shooting "any time".)
	hud:setPlacing(targets:canPlace() and phase ~= "Sneak", targets:isBlocked())
	hud:setFrozenAim(frozenTurn())
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
		or frozenTurn()
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
end
-- The first-time tutorial (the tutorial lane): its line, dim, hand and floor arrow.
require(script.Parent.Tutorial).start()
RunService.RenderStepped:Connect(function(dt)
	renderFrame(dt)
	-- The back cues last, once every hand cue of this frame is drawn: a cue is never on a back
	-- and in the hands at once, nor missing from both.
	backCue:update(dt, cueStick:GetAttribute("Visible") == true, hub.watched:holding())
end)
-- GUI lane: a Studio-only test hook for the screens (GuiQA; nothing in a live server).
require(script.Parent.GuiQA).start()
-- The abilities' Studio checks: GuiQA "aim" aims at `angle` (radians) with `pull` (0..1) as the
-- player would, so an ability's aim line is checked without the mouse; "camera" shows the
-- view from `cf` (a close-up still) until it is called with nothing.
require(script.Parent.GuiQA).add("aim", function(angle: number?, pull: number?)
	if type(angle) == "number" then
		input:setAngle(angle)
	end
	if type(pull) == "number" then
		currentPull = pull
	end
	refreshAim()
	return input.angle
end)
require(script.Parent.GuiQA).add("camera", function(cf: CFrame?)
	Camera.setOverride(if typeof(cf) == "CFrame" then cf else nil, 1)
	return cf ~= nil
end)
-- One thing at a time: a full menu hides the rest of the HUD (HudFocus).
require(script.Parent.HudFocus).start()
-- The lively Shop's motion spike (Studio only; GuiQA "spike").
require(script.Parent.MotionSpike).start()
-- The lively Shop's gate 2 mock-ups (Studio only; GuiQA "lab").
require(script.Parent.ShopLab).start()
-- Every cue card look on one board (Studio only; GuiQA "cueCards").
require(script.Parent.CueCardLab).start()
print("[8ball] multiplayer client ready")
