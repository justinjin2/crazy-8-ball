--!strict
-- Roblox adapter: identity/proximity, queue pads, replication and characters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local Net = require(Shared.Net)
local AimStream = require(Shared.AimStream)
local AvatarPose = require(Shared.AvatarPose)
local CueClearance = require(Shared.CueClearance)
local Placement = require(Shared.Placement)
local ShooterStance = require(Shared.ShooterStance)
local ShotInput = require(Shared.ShotInput)
local Cue = require(Shared.Physics.Cue)
local Simulation = require(Shared.Physics.Simulation)
local Engine = require(Shared.Rules.MatchEngine)
local M = Config.Multiplayer
local Q = M.QueueVisual
local Service = {}
Service.PadFolderName = "Pads"
local tables: { [number]: any } = {}
local seatOf: { [number]: number } = {}
local buckets: { [string]: any } = {}
local characterSaved: { [number]: any } = {}
local rng = Random.new()
-- Every game opens on its own rack: the seed only moves each ball a hair, but a break is
-- sensitive to exactly that, so two games never play out the same. The seed travels in the
-- snapshot, so every client still builds the identical rack.
local function newSeed(): number
	return rng:NextInteger(1, Config.Rack.MaxSeed)
end
local started = false
-- The root attribute holding the exact spot (a CFrame) the server put the shooter at for
-- their shot. Once the root is unanchored the owner's local CFrame wins, so after the stroke
-- the client writes this spot and nothing else; nil whenever the root is not there.
local SHOT_SPOT = "ShotSpot"
-- Collision groups for the bodies at a table. Everyone seated is a participant: they walk on
-- the floor, into the fence, and through one another. A shooter the server holds is in a
-- group that touches nothing at all: the root is anchored, so it needs no floor, and the
-- server moves that body, so a move landing inside a spectator standing by the table must not
-- fling them out of it. Seated players only ever pass between the two while the root is
-- anchored: in once it is held, out before it is let go.
local PARTICIPANTS = "PoolParticipants"
local HELD = "PoolShooter"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local function now(): number
	return workspace:GetServerTimeNow()
end
local function rootOf(p: Player): BasePart?
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
-- The phases the shooter aims in, and so the only ones the aim stream is taken in.
local function aimPhase(phase: string): boolean
	return phase == "Aiming" or phase == "Intro" or phase == "Placement"
end

function Service.get(id: number): any
	return tables[id]
end
function Service.advance(t: any, timestamp: number)
	-- Every remote and heartbeat supplies the same server-owned coin source. A late
	-- request must not choose the engine's deterministic test fallback for a live coin.
	Engine.advance(t.engine, timestamp, rng:NextInteger(1, 2), newSeed())
end
function Service.tableOf(p: Player): number?
	return seatOf[p.UserId]
end
function Service.stateOf(id: number): any
	local t = tables[id]
	return if t then t.engine.state else nil
end
function Service.isBusy(id: number): boolean
	local t = tables[id]
	return t ~= nil and t.engine.phase == "Resolving"
end
-- One token bucket per player and channel (Config.Multiplayer.RateLimits), so a flood on one
-- (dragging the cue ball) can never starve another (the shot).
function Service.allow(p: Player, channel: string?): boolean
	local name = channel or "action"
	local limit = M.RateLimits[name]
	assert(limit, "Unknown rate-limit channel")
	local key = tostring(p.UserId) .. name
	local bank = buckets[key]
	local time = now()
	if not bank then
		bank = { at = time, tokens = limit.Burst }
		buckets[key] = bank
	end
	bank.tokens = math.min(limit.Burst, bank.tokens + (time - bank.at) * limit.PerSecond)
	bank.at = time
	if bank.tokens < 1 then
		return false
	end
	bank.tokens -= 1
	return true
end

local function label(
	parent: Instance,
	text: string,
	size: UDim2,
	position: UDim2,
	fontSize: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextColor3 = rgb(M.Style.Text)
	l.Font = Enum.Font.GothamBold
	l.TextSize = fontSize
	l.Size = size
	l.Position = position
	l.Text = text
	l.Parent = parent
	return l
end

local function queuePoint(p: Placement.Placement, team: number, slot: number): Vector3
	local along = -M.PadDistanceStuds - (slot - 1) * (M.PadSizeStuds + M.PadGapStuds)
	local across = (if team == 1 then -1 else 1) * (M.PadSizeStuds + M.PadTeamGapStuds) / 2
	local dx, dz = Placement.dirToWorld(p, along, across)
	return Vector3.new(p.x + dx, p.y + Q.FloorOffset, p.z + dz)
end

-- An invisible wall around the table so nobody can walk into it, lean on it or jump onto
-- it and stand in the shooter's view. It stops characters only: CanQuery off keeps it out
-- of camera occlusion and every raycast, and the balls are simulated, not physical.
local function buildBarrier(t: any, folder: Instance)
	local B = M.Barrier
	local hx, hy = Placement.barrierHalfExtents()
	local part = Instance.new("Part")
	part.Name = ("TableBarrier_%02d"):format(t.engine.id)
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Size = Vector3.new(2 * hx, B.HeightStuds, 2 * hy)
	part.CFrame = CFrame.new(t.placement.x, t.placement.y + B.HeightStuds / 2, t.placement.z)
		* CFrame.Angles(0, t.placement.yaw, 0)
	part.Parent = folder
end

-- Walls around the whole match area, so participants stay near their table without being
-- teleported: they walk into these like any wall. In the PoolFence collision group, which
-- only collides with PoolParticipants, so spectators and people heading for a queue pass
-- straight through. CanQuery off keeps them out of camera occlusion and raycasts.
local function buildFence(t: any, folder: Instance)
	local F = M.Fence
	local height = M.Barrier.HeightStuds
	local fx, fy = Placement.fenceHalfExtents(t.engine.teamSize)
	local w = F.ThicknessStuds
	local base = CFrame.new(t.placement.x, t.placement.y + height / 2, t.placement.z)
		* CFrame.Angles(0, t.placement.yaw, 0)
	local walls = {
		{ Vector3.new(0, 0, fy + w / 2), Vector3.new(2 * (fx + w), height, w) },
		{ Vector3.new(0, 0, -(fy + w / 2)), Vector3.new(2 * (fx + w), height, w) },
		{ Vector3.new(fx + w / 2, 0, 0), Vector3.new(w, height, 2 * fy) },
		{ Vector3.new(-(fx + w / 2), 0, 0), Vector3.new(w, height, 2 * fy) },
	}
	for i, wall in walls do
		local part = Instance.new("Part")
		part.Name = ("MatchFence_%02d_%d"):format(t.engine.id, i)
		part.Anchored = true
		part.CanCollide = true
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Transparency = 1
		part.Size = wall[2]
		part.CFrame = base * CFrame.new(wall[1])
		part.CollisionGroup = "PoolFence"
		part.Parent = folder
	end
end

local function buildPads(t: any, folder: Instance)
	t.pads = {}
	for team = 1, 2 do
		for slot = 1, t.engine.teamSize do
			local part = Instance.new("Part")
			part.Name = ("Pad_%02d_%d_%d"):format(t.engine.id, team, slot)
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.CastShadow = false
			part.Size = Vector3.new(M.PadSizeStuds, Q.PadHeight, M.PadSizeStuds)
			part.CFrame = CFrame.new(queuePoint(t.placement, team, slot))
				* CFrame.Angles(0, t.placement.yaw, 0)
			part.Color = rgb(M.Style.White)
			part.Transparency = Q.EmptyTransparency
			part.Material = Enum.Material.SmoothPlastic
			part:SetAttribute("TableId", t.engine.id)
			part:SetAttribute("Team", team)
			part:SetAttribute("Slot", slot)
			part:SetAttribute("Occupied", false)
			part.Parent = folder
			local gui = Instance.new("SurfaceGui")
			gui.Name = "SlotLabel"
			gui.Face = Enum.NormalId.Top
			gui.CanvasSize = Vector2.new(Q.CanvasPixels, Q.CanvasPixels)
			gui.Parent = part
			local frame = Instance.new("Frame")
			frame.Size = UDim2.fromScale(1 - 2 * Q.Inset, 1 - 2 * Q.Inset)
			frame.Position = UDim2.fromScale(Q.Inset, Q.Inset)
			frame.Rotation = Q.LabelRotation
			frame.BackgroundColor3 = rgb(M.Style.Panel)
			frame.BackgroundTransparency = Q.FrameTransparency
			frame.Parent = gui
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(Q.CornerScale, 0)
			corner.Parent = frame
			local border = Instance.new("UIStroke")
			border.Name = "Edge"
			border.Color = rgb(M.Style.White)
			border.Thickness = Q.EdgePixels
			border.Transparency = Q.EdgeTransparency
			border.Parent = frame
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = Q.GradientRotation
			gradient.Transparency = NumberSequence.new(Q.GradientMin, Q.GradientMax)
			gradient.Parent = frame
			label(
				frame,
				Strings.Match.TeamSlot:format(if team == 1 then "A" else "B", slot),
				UDim2.fromScale(Q.TeamLabel[1], Q.TeamLabel[2]),
				UDim2.fromScale(Q.TeamLabel[3], Q.TeamLabel[4]),
				Q.TeamLabel[5]
			)
			local name = label(
				frame,
				Strings.Match.EmptySlot,
				UDim2.fromScale(Q.NameLabel[1], Q.NameLabel[2]),
				UDim2.fromScale(Q.NameLabel[3], Q.NameLabel[4]),
				Q.NameLabel[5]
			)
			name.Name = "Occupant"
			name.TextTruncate = Enum.TextTruncate.AtEnd
			local light = Instance.new("SurfaceLight")
			light.Face, light.Brightness, light.Range =
				Enum.NormalId.Top, Q.LightBrightness, Q.LightRange
			light.Color, light.Shadows, light.Parent = rgb(M.Style.White), false, part
			local pulse = TweenService:Create(
				border,
				TweenInfo.new(
					Q.PulseSeconds,
					Enum.EasingStyle.Sine,
					Enum.EasingDirection.InOut,
					-1,
					true
				),
				{ Transparency = Q.PulseTransparency }
			)
			pulse:Play()
			table.insert(t.pads, {
				part = part,
				team = team,
				slot = slot,
				label = name,
				edge = border,
				light = light,
				occupied = false,
				tweens = {},
			})
		end
	end
	local anchor = Instance.new("Part")
	anchor.Name = ("QueuePanel_%02d"):format(t.engine.id)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = (queuePoint(t.placement, 1, 1) + queuePoint(t.placement, 2, 1)) / 2
		+ Vector3.new(0, Q.PanelOffset, 0)
	anchor.Parent = folder
	local gui = Instance.new("BillboardGui")
	gui.Name = "HostPanel"
	gui.Size = UDim2.fromOffset(Q.PanelWidth, Q.PanelHeight)
	gui.MaxDistance = Q.PanelMaxDistance
	gui.Parent = anchor
	local panel = Instance.new("Frame")
	panel.Size = UDim2.fromScale(1, 1)
	panel.BackgroundColor3 = rgb(M.Style.Panel)
	panel.BackgroundTransparency = Q.PanelTransparency
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, M.Style.CornerPx)
	corner.Parent = panel
	local edge = Instance.new("UIStroke")
	edge.Color = rgb(M.Style.Border)
	edge.Parent = panel
	t.title = label(
		panel,
		Strings.Match.Mode:format(t.engine.teamSize, t.engine.teamSize),
		UDim2.fromScale(Q.ModeLabel[1], Q.ModeLabel[2]),
		UDim2.fromScale(Q.ModeLabel[3], Q.ModeLabel[4]),
		Q.ModeLabel[5]
	)
	t.hostLabel = label(
		panel,
		"",
		UDim2.fromScale(Q.HostLabel[1], Q.HostLabel[2]),
		UDim2.fromScale(Q.HostLabel[3], Q.HostLabel[4]),
		Q.HostLabel[5]
	)
	t.hostLabel.TextTruncate = Enum.TextTruncate.AtEnd
	t.statusLabel = label(
		panel,
		"",
		UDim2.fromScale(Q.StatusLabel[1], Q.StatusLabel[2]),
		UDim2.fromScale(Q.StatusLabel[3], Q.StatusLabel[4]),
		Q.StatusLabel[5]
	)
end

local function refresh(t: any)
	local e = t.engine
	for _, pad in t.pads do
		local occupant = nil
		for _, s in e.seats do
			if s.connected and s.team == pad.team and s.slot == pad.slot then
				occupant = s
			end
		end
		local occupied = occupant ~= nil
		if pad.occupied ~= occupied then
			pad.occupied = occupied
			for _, tween in pad.tweens do
				tween:Cancel()
			end
			local tint = rgb(if occupied then M.Style.Green else M.Style.White)
			local timing =
				TweenInfo.new(M.Style.FadeSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			pad.tweens = {
				TweenService:Create(pad.part, timing, {
					Color = tint,
					Transparency = if occupied then Q.OccupiedTransparency else Q.EmptyTransparency,
				}),
				TweenService:Create(pad.edge, timing, { Color = tint }),
				TweenService:Create(pad.light, timing, { Color = tint }),
			}
			for _, tween in pad.tweens do
				tween:Play()
			end
		end
		pad.part:SetAttribute("Occupied", occupied)
		pad.label.Text = if occupant
			then occupant.displayName
			elseif e.phase == "Waiting" or e.phase == "Countdown" then Strings.Match.EmptySlot
			else Strings.Match.InProgress
	end
	local host = if e.hostId then Engine.seat(e, e.hostId) else nil
	if e.solo and host then
		-- A solo game holds the whole table until its result.
		t.hostLabel.Text = Strings.Match.SoloPanel:format(host.displayName)
		t.statusLabel.Text = Strings.Match.SoloInProgress
		return
	end
	t.hostLabel.Text = if host
		then Strings.Match.Host:format(host.displayName)
		else Strings.Match.JoinHint
	local state = if e.phase == "Waiting"
		then Strings.Match.Waiting
		elseif e.phase == "Countdown" then Strings.Match.Starting:format(
			math.max(0, math.ceil(e.deadline - now()))
		)
		else Strings.Match.InProgress
	t.statusLabel.Text = Strings.Match.QueueStatus:format(Engine.count(e), e.teamSize * 2, state)
end

function Service.broadcast(t: any, player: Player?)
	local data = Engine.snapshot(t.engine)
	if player then
		Net.get("TableState"):FireClient(player, data)
	else
		Net.get("TableState"):FireAllClients(data)
		t.sentRevision = t.engine.revision
	end
	refresh(t)
end

-- Bonus grants go only to the owning team. ShotService sends them before the ShotResult, so
-- a client already holds its grant when the replay drops the ball (see Audio.grant).
function Service.flush(t: any)
	for _, f in t.engine.feedback do
		for _, s in t.engine.seats do
			if s.connected and s.team == f.team then
				local p = Players:GetPlayerByUserId(s.userId)
				if p then
					Net.get("MatchFeedback"):FireClient(p, {
						tableId = t.engine.id,
						epoch = t.engine.epoch,
						id = f.id,
						seq = f.seq,
						index = f.index,
						ball = f.ball,
						team = f.team,
						at = f.at,
					})
				end
			end
		end
	end
	table.clear(t.engine.feedback)
end

-- Hand a held root back to the player where it stands. An anchored part keeps whatever
-- velocity it had when it was anchored, so a root just let go is stilled first, or it would
-- resume the walk it was stopped in and shove the player off the spot they shot from. It is
-- no longer at a shot spot the client should return to, either.
local function release(root: BasePart, anchored: boolean)
	local released = root.Anchored and not anchored
	root.Anchored = anchored
	if released then
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
	end
	if root:GetAttribute(SHOT_SPOT) ~= nil then
		root:SetAttribute(SHOT_SPOT, nil)
	end
end

-- Put every part of a seated character in `group` (PARTICIPANTS or HELD); parts added later
-- join it too (see constrain). Only what changes is written.
local function setGroup(saved: any, group: string)
	if saved.group == group then
		return
	end
	saved.group = group
	for _, row in saved.parts do
		if row.part.Parent then
			row.part.CollisionGroup = group
		end
	end
end

local function restore(p: Player)
	local saved = characterSaved[p.UserId]
	if not saved then
		return
	end
	if saved.added then
		saved.added:Disconnect()
	end
	if saved.died then
		saved.died:Disconnect()
	end
	for _, row in saved.parts do
		if row.part.Parent then
			row.part.CollisionGroup = row.group
		end
	end
	if saved.hum.Parent then
		saved.hum.WalkSpeed = saved.walk
		saved.hum.AutoRotate = saved.rotate
		saved.hum.JumpPower = saved.jump
		saved.hum.JumpHeight = saved.jumpHeight
	end
	if saved.root.Parent then
		release(saved.root, saved.anchored)
	end
	characterSaved[p.UserId] = nil
end

-- A root CFrame for a spot in table studs (ShooterStance's units: height above the floor the
-- table stands on) facing `yaw` (the aim convention), or nil if a number is not finite: a
-- NaN CFrame on a character is never worth the risk.
local function worldSpot(
	p: Placement.Placement,
	x: number,
	y: number,
	z: number,
	yaw: number
): CFrame?
	local wx, wy, wz = Placement.fromTableStuds(p, x, y, z)
	if
		not (
			ShotInput.isFinite(wx)
			and ShotInput.isFinite(wy)
			and ShotInput.isFinite(wz)
			and ShotInput.isFinite(yaw)
		)
	then
		return nil
	end
	local dx, _, dz = Placement.aimVector(p, yaw)
	local at = Vector3.new(wx, wy, wz)
	return CFrame.lookAt(at, at + Vector3.new(dx, 0, dz))
end

-- The shooter's stance at table `t` for an aim, solved from the server's own balls with the
-- same pure functions every client poses with, so the two agree on where the body stands:
-- the body measured from the rig, the raw drawn pitch (the client eases its own toward it),
-- and no pull (the root never depends on it). The Memory threads through one turn and starts
-- afresh when the epoch, the turn or the shooter changes. nil when the rig cannot be
-- measured (the root is then left where it is, never guessed at) or the cue ball is down.
local function solveStance(
	t: any,
	character: Model,
	angle: number,
	spinX: number,
	spinY: number
): ShooterStance.Stance?
	local e = t.engine
	local key = ("%d:%d:%d"):format(e.epoch, e.turnId, e.shooter or 0)
	if t.stanceKey ~= key then
		t.stanceKey, t.stanceMemory = key, nil
	end
	local cue = Simulation.findBall(e.state, 0)
	if not cue or cue.pocketed then
		return nil
	end
	local ok, stance = pcall(function(): ShooterStance.Stance?
		local body = AvatarPose.measureBody(character)
		if not body then
			return nil
		end
		local pitch = CueClearance.pitch(e.state.geometry, e.state.balls, {
			cueX = cue.x,
			cueY = cue.y,
			angle = angle,
			spinX = spinX,
			spinY = spinY,
		})
		return ShooterStance.solve({
			ballXIn = cue.x,
			ballYIn = cue.y,
			angle = angle,
			spinX = spinX,
			spinY = spinY,
			pitchDegrees = pitch.degrees,
			pull = 0,
			body = body,
			area = ShooterStance.area(e.teamSize),
			memory = t.stanceMemory,
		})
	end)
	if not ok then
		-- The stance is presentation: a failure must never stop the poll loop or hold back a
		-- shot's broadcast. Said once per turn, not five times a second.
		if t.stanceWarned ~= key then
			t.stanceWarned = key
			warn("[8ball] shooter stance failed: " .. tostring(stance))
		end
		return nil
	end
	if stance then
		t.stanceMemory = stance.memory
	end
	return stance
end

-- Move a held root. Only ever an anchored one: the client owns an unanchored body, so a
-- write there would fight its physics and rubber-band. Returns whether it moved.
local function placeRoot(t: any, root: BasePart, cf: CFrame): boolean
	if not root.Anchored then
		return false
	end
	root.CFrame = cf
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	t.stanceAt = now()
	return true
end

-- While the shooter aims, their anchored root follows the stance, so a late joiner, a table
-- nobody is posing and a respawned shooter all show the body at the table, and the move at
-- the shot is tiny. At most Stance.ServerMovesPerSecond, and only once the stance is past
-- the hysteresis from where the root IS (it may have been anywhere when the turn began).
-- Never an unanchored root, never during Resolving (it waits at the shot spot), and never
-- from an aim of another turn or shooter. The aim stream carries no spin, so none is used.
local function followStance(t: any, p: Player, root: BasePart, character: Model)
	local S = M.Stance
	local e, aim = t.engine, t.aim
	if
		not root.Anchored
		or not aimPhase(e.phase)
		or not aim
		or aim.by ~= p.UserId
		or aim.epoch ~= e.epoch
		or aim.turnId ~= e.turnId
	then
		return
	end
	if t.stanceAt and now() - t.stanceAt < 1 / S.ServerMovesPerSecond then
		return
	end
	local stance = solveStance(t, character, aim.angle, 0, 0)
	local cf = stance
		and worldSpot(t.placement, stance.rootX, stance.rootY, stance.rootZ, stance.yaw)
	if not cf then
		return
	end
	local moved = (cf.Position - root.Position).Magnitude
	local turned = math.deg(math.acos(math.clamp(cf.LookVector:Dot(root.CFrame.LookVector), -1, 1)))
	if
		(moved >= S.ServerMoveStuds or turned >= S.ServerMoveDegrees)
		and placeRoot(t, root, cf)
		and root:GetAttribute(SHOT_SPOT) ~= nil
	then
		root:SetAttribute(SHOT_SPOT, nil) -- it has left the last shot's spot
	end
end

local function constrain(p: Player, t: any)
	local e = t.engine
	if e.phase == "Waiting" or e.phase == "Countdown" or e.phase == "Result" then
		restore(p)
		return
	end
	local root = rootOf(p)
	local character = p.Character
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or not character or hum.Health <= 0 then
		return
	end
	local saved = characterSaved[p.UserId]
	if not saved or saved.root ~= root then
		restore(p)
		saved = {
			root = root,
			hum = hum,
			walk = hum.WalkSpeed,
			rotate = hum.AutoRotate,
			jump = hum.JumpPower,
			jumpHeight = hum.JumpHeight,
			anchored = root.Anchored,
			parts = {},
			group = PARTICIPANTS,
		}
		local function excludePlayerCollision(part: Instance)
			if part:IsA("BasePart") then
				table.insert(saved.parts, { part = part, group = part.CollisionGroup })
				part.CollisionGroup = saved.group
			end
		end
		for _, part in character:GetDescendants() do
			excludePlayerCollision(part)
		end
		saved.added = character.DescendantAdded:Connect(excludePlayerCollision)
		-- A body that dies while held falls apart, and its pieces need the floor again.
		saved.died = hum.Died:Connect(function()
			setGroup(saved, PARTICIPANTS)
		end)
		characterSaved[p.UserId] = saved
	end
	-- A solo player keeps the table through a foul: nobody else takes over. The watchers ask
	-- the same question (Engine.shooterLocked), so they pose exactly the body held here.
	local locked = e.shooter == p.UserId and Engine.shooterLocked(e.phase, e.solo)
	if locked then
		hum.WalkSpeed = 0
		hum.AutoRotate = false
		hum.JumpPower = 0
		hum.JumpHeight = 0
		root.Anchored = true
		setGroup(saved, HELD) -- only now it is anchored, before followStance can move it
		followStance(t, p, root, character)
		return
	end
	hum.WalkSpeed = saved.walk
	hum.AutoRotate = saved.rotate
	hum.JumpPower = saved.jump
	hum.JumpHeight = saved.jumpHeight
	-- Back on the floor first, then let go where it stands, the shot spot included: no
	-- teleport when the turn passes.
	setGroup(saved, PARTICIPANTS)
	release(root, saved.anchored)
	-- Everyone else walks normally: the fence and the table's own barrier are physical walls,
	-- so nothing here moves a character that is walking about. A teleport only rescues a body
	-- that fell through the floor or ended up well outside its fence (spawned there, clipped
	-- through); the client owns its character, so moving it every poll would rubber-band.
	local scale = Config.Table.StudsPerInch
	local fx, fy = Placement.fenceHalfExtents(e.teamSize)
	local x, y = Placement.toTable(t.placement, root.Position.X, root.Position.Z)
	x, y = x * scale, y * scale -- studs along the table's axes
	local escape = M.Fence.EscapeStuds
	local outside = math.abs(x) > fx + escape or math.abs(y) > fy + escape
	if outside or root.Position.Y < t.placement.y - Q.FallTolerance then
		local inset = M.Fence.ThicknessStuds + Q.RespawnBoundaryInset
		local cx = math.clamp(x, -(fx - inset), fx - inset) / scale
		local cy = math.clamp(y, -(fy - inset), fy - inset) / scale
		-- Keep clear of the table itself: land on the nearer long side.
		local bx, by = Placement.barrierHalfExtents()
		if math.abs(cx * scale) < bx and math.abs(cy * scale) < by then
			cy = (if cy < 0 then -1 else 1) * (fy - inset) / scale
		end
		local wx, _, wz = Placement.toWorld(t.placement, cx, cy, 0)
		root.CFrame = CFrame.new(wx, t.placement.y + Q.RespawnHeight, wz) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

--- A shot was accepted at table `t` (ShotService, and the Studio QA fixture): hold the
--- shooter and put the anchored root exactly where they shot from, turned to face the table
--- centre (ShooterStance.idle), with that spot on the root's ShotSpot attribute for the
--- client. Called after acceptShot, which leaves the cue ball at its spot before the shot
--- until the shot resolves; `angle` and `spin` are the accepted payload's. The root then
--- waits there through Resolving and is let go in place if the turn passes.
function Service.shotAccepted(
	t: any,
	userId: number,
	angle: number,
	spin: { x: number, y: number }?
)
	local p = Players:GetPlayerByUserId(userId)
	if not p or not ShotInput.isFinite(angle) then
		return
	end
	constrain(p, t) -- the phase is Resolving now, so this holds the body and anchors the root
	local root, character = rootOf(p), p.Character
	if not root or not character then
		return
	end
	local sx, sy = 0, 0
	if type(spin) == "table" and ShotInput.isFinite(spin.x) and ShotInput.isFinite(spin.y) then
		sx, sy = Cue.clampSpin(spin.x, spin.y)
	end
	local stance = solveStance(t, character, angle % (2 * math.pi), sx, sy)
	local spot: CFrame? = nil
	if stance then
		local x, y, z, yaw = ShooterStance.idle(stance)
		spot = worldSpot(t.placement, x, y, z, yaw)
	end
	-- No spot (a rig that cannot be measured, a body not held): the client falls back to its
	-- own, and a spot left from an earlier shot must not outlive this one.
	if spot and placeRoot(t, root, spot) then
		root:SetAttribute(SHOT_SPOT, spot)
	elseif root:GetAttribute(SHOT_SPOT) ~= nil then
		root:SetAttribute(SHOT_SPOT, nil)
	end
end

local function releaseMissing(t: any)
	for id, tableId in seatOf do
		if tableId == t.engine.id and not Engine.seat(t.engine, id) then
			seatOf[id] = nil
			t.blocked[id] = true
			local p = Players:GetPlayerByUserId(id)
			if p then
				restore(p)
			end
		end
	end
end

local function onPad(root: BasePart, pad: any): boolean
	local v = pad.part.CFrame:PointToObjectSpace(root.Position)
	return math.abs(v.X) <= M.PadSizeStuds / 2
		and math.abs(v.Z) <= M.PadSizeStuds / 2
		and math.abs(v.Y) < Q.VerticalTolerance
end

local function poll(t: any, time: number)
	local e = t.engine
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, p in players do
		local root = rootOf(p)
		local pad = nil
		local inQueueArea = false
		if root then
			for _, candidate in t.pads do
				local localPoint = candidate.part.CFrame:PointToObjectSpace(root.Position)
				if
					math.abs(localPoint.X) <= M.PadSizeStuds / 2 + Q.AreaMargin
					and math.abs(localPoint.Z) <= M.PadSizeStuds / 2 + Q.AreaMargin
					and math.abs(localPoint.Y) < Q.VerticalTolerance
				then
					inQueueArea = true
				end
				if onPad(root, candidate) then
					pad = candidate
				end
			end
		end
		if not inQueueArea then
			t.blocked[p.UserId] = nil
		end
		local s = Engine.seat(e, p.UserId)
		if s then
			if e.phase == "Waiting" or e.phase == "Countdown" then
				if inQueueArea then
					t.outside[p.UserId] = nil
				else
					t.outside[p.UserId] = t.outside[p.UserId] or time
					if time - t.outside[p.UserId] >= M.QueueExitGraceSeconds then
						Engine.remove(e, p.UserId, time)
					end
				end
			else
				constrain(p, t)
			end
		elseif pad and not seatOf[p.UserId] and not t.blocked[p.UserId] then
			local dwell = t.dwell[p.UserId]
			if not dwell or dwell.pad ~= pad then
				t.dwell[p.UserId] = { pad = pad, at = time }
			elseif time - dwell.at >= M.PadDwellSeconds then
				if Engine.join(e, p.UserId, p.Name, p.DisplayName, pad.team, pad.slot, time) then
					seatOf[p.UserId] = e.id
				end
			end
		else
			t.dwell[p.UserId] = nil
		end
	end
	releaseMissing(t)
end

function Service.start(parent: Instance)
	if started then
		return
	end
	started = true
	-- Participants cannot push one another, while normal floor collision remains intact.
	pcall(function()
		PhysicsService:RegisterCollisionGroup(PARTICIPANTS)
	end)
	PhysicsService:CollisionGroupSetCollidable(PARTICIPANTS, PARTICIPANTS, false)
	-- Match fences stop only the people in a match; everyone else walks through them.
	pcall(function()
		PhysicsService:RegisterCollisionGroup("PoolFence")
	end)
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(
			"PoolFence",
			group.name,
			group.name == PARTICIPANTS
		)
	end
	-- The shooter the server holds touches nothing, itself included (see HELD).
	pcall(function()
		PhysicsService:RegisterCollisionGroup(HELD)
	end)
	for _, group in PhysicsService:GetRegisteredCollisionGroups() do
		PhysicsService:CollisionGroupSetCollidable(HELD, group.name, false)
	end
	local old = parent:FindFirstChild(Service.PadFolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Service.PadFolderName
	folder.Parent = parent
	for _, mode in M.Modes do
		local p = Placement.forTable(mode.id)
		assert(p, "Missing table placement")
		local t: any = {
			engine = Engine.new(mode.id, mode.teamSize, newSeed()),
			placement = p,
			dwell = {},
			outside = {},
			blocked = {},
			sentRevision = 0,
		}
		tables[mode.id] = t
		buildPads(t, folder)
		buildBarrier(t, folder)
		buildFence(t, folder)
		Service.broadcast(t)
	end
	Net.get("SnapshotRequest").OnServerEvent:Connect(function(p)
		if not Service.allow(p, "snapshot") then
			return
		end
		for _, mode in M.Modes do
			Service.broadcast(tables[mode.id], p)
		end
	end)
	-- Join requests cannot bypass server-observed pad occupancy.
	Net.get("MatchAction").OnServerEvent:Connect(function(p, payload)
		if type(payload) ~= "table" then
			return
		end
		local isPlace = payload.kind == "Place"
		if not Service.allow(p, if isPlace then "place" else "action") then
			return
		end
		local id = seatOf[p.UserId]
		if not id or payload.tableId ~= id then
			return
		end
		local t = tables[id]
		Service.advance(t, now())
		local accepted = Engine.action(t.engine, p.UserId, payload, now())
		releaseMissing(t)
		if accepted or t.engine.revision ~= t.sentRevision then
			Service.broadcast(t) -- one snapshot per accepted Place (a drag release)
		elseif not isPlace then
			Service.broadcast(t, p) -- private resync only
		end
		-- A rejected Place is routine (the window just closed, or a stale seq) and must not
		-- clear the client's awaiting state while a shot it already fired is in flight.
		if not accepted and not isPlace then
			Net.get("ShotRejected"):FireClient(p, "ActionRejected")
		end
	end)
	local aimUpdate = Net.get("AimUpdate")
	aimUpdate.OnServerEvent:Connect(function(p, id, angle, epoch, turnId, pull, seq, x, y)
		-- The wind-up is cosmetic, but it is still checked like the angle: a pull that is not
		-- a finite number drops the whole packet, and the rest are snapped to whole steps.
		local held = AimStream.quantizePull(pull)
		if
			id ~= seatOf[p.UserId]
			or not ShotInput.isFinite(angle)
			or held == nil
			or not Service.allow(p, "aim")
		then
			return
		end
		local t = tables[id]
		if not t then
			return
		end
		local e = t.engine
		if
			e.shooter ~= p.UserId
			or e.epoch ~= epoch
			or e.turnId ~= turnId
			or not aimPhase(e.phase)
		then
			return
		end
		t.aim = {
			angle = angle % (2 * math.pi),
			pull = held,
			by = p.UserId,
			turnId = turnId,
			epoch = epoch,
		}
		if seq ~= nil then
			-- Ball in hand rides the aim stream. The engine checks the window, the seq and
			-- the spot; a bad one is simply dropped, like any lost unreliable packet.
			local time = now()
			Service.advance(t, time)
			Engine.moveCue(
				e,
				p.UserId,
				{ epoch = epoch, turnId = turnId, seq = seq, x = x, y = y },
				time
			)
		end
	end)
	local function added(p: Player)
		local endedCharacter: Model? = nil
		local function characterEnded(character: Model)
			if endedCharacter == character then
				return
			end
			endedCharacter = character
			local id = seatOf[p.UserId]
			if id then
				Engine.death(tables[id].engine, p.UserId, now())
				Service.broadcast(tables[id])
			end
		end
		local function characterAdded(character: Model)
			restore(p)
			local hum = character:WaitForChild("Humanoid") :: Humanoid
			hum.Died:Connect(function()
				characterEnded(character)
			end)
			local id = seatOf[p.UserId]
			if id then
				local t = tables[id]
				local root = character:WaitForChild("HumanoidRootPart") :: BasePart
				local _, fenceY = Placement.fenceHalfExtents(t.engine.teamSize)
				local dx, dz = Placement.dirToWorld(t.placement, 0, fenceY - Q.RespawnBoundaryInset)
				root.CFrame = CFrame.new(
					t.placement.x + dx,
					t.placement.y + Q.RespawnHeight,
					t.placement.z + dz
				)
			end
		end
		p.CharacterAdded:Connect(characterAdded)
		if p.Character then
			task.spawn(characterAdded, p.Character)
		end
		p.CharacterRemoving:Connect(function(character)
			characterEnded(character)
			restore(p)
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		local id = seatOf[p.UserId]
		if id then
			Engine.remove(tables[id].engine, p.UserId, now())
			Service.broadcast(tables[id])
		end
		seatOf[p.UserId] = nil
		restore(p)
		for name in M.RateLimits do
			buckets[tostring(p.UserId) .. tostring(name)] = nil
		end
		for _, t in tables do
			t.dwell[p.UserId] = nil
			t.outside[p.UserId] = nil
			t.blocked[p.UserId] = nil
		end
	end)
	require(script.Parent.StudioMatchQA).start(
		tables,
		seatOf,
		Service.broadcast,
		Service.flush,
		Service.shotAccepted
	)
	-- Every table's aim, wind-up and cue spot, on its own clock (Config.Aim.BroadcastsPerSecond)
	-- so a watched ball in hand is not held to the pad-poll rate.
	local function broadcastAims()
		local batch = {}
		for _, mode in M.Modes do
			local t = tables[mode.id]
			local e = t.engine
			local cue = Simulation.findBall(e.state, 0)
			if
				t.aim
				and cue
				and t.aim.epoch == e.epoch
				and t.aim.turnId == e.turnId
				and t.aim.by == e.shooter
				and e.phase ~= "Resolving"
				and e.phase ~= "Result"
			then
				AimStream.pack(batch, e.id, t.aim.by, t.aim.angle, cue.x, cue.y, t.aim.pull)
			end
		end
		Net.get("AimBroadcast"):FireAllClients(batch)
	end
	local elapsed, snapshots, aims = 0, 0, 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		snapshots += dt
		aims += dt
		if aims >= 1 / Config.Aim.BroadcastsPerSecond then
			aims = 0
			broadcastAims()
		end
		if elapsed < 1 / Config.Pad.PollsPerSecond then
			return
		end
		elapsed = 0
		for _, mode in M.Modes do
			local t = tables[mode.id]
			local e = t.engine
			local time = now()
			poll(t, time)
			Service.advance(t, time)
			releaseMissing(t)
			Service.flush(t)
			if e.revision ~= t.sentRevision or snapshots >= M.SnapshotIntervalSeconds then
				Service.broadcast(t)
			else
				refresh(t)
			end
		end
		if snapshots >= M.SnapshotIntervalSeconds then
			snapshots = 0
		end
	end)
end

return Service
