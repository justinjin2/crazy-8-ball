--!strict
-- Roblox adapter: identity/proximity, queue boxes, replication and characters.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
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
-- Every table's queue box, host panel, barrier and fence.
Service.ZoneFolderName = "TableZones"
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
	-- Every remote and heartbeat supplies the server-owned rack seed for the next game.
	Engine.advance(t.engine, timestamp, newSeed())
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

-- A CFrame at a point in table studs (along the length, across the width) on the floor the
-- table stands on, `up` above it, turned with the table: local X runs along its length
-- (head negative) and local Z across it (physics -y).
local function tableFrame(p: Placement.Placement, x: number, y: number, up: number): CFrame
	local wx, wy, wz = Placement.fromTableStuds(p, x, y, up)
	return CFrame.new(wx, wy, wz) * CFrame.Angles(0, p.yaw, 0)
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
	local fx, fy, cx, cy = Placement.matchFence()
	local w = F.ThicknessStuds
	-- The box takes in the queue box along one long side, so it is centred off the table.
	local base = tableFrame(t.placement, cx, cy, height / 2)
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

-- A flat floor part with a label across its top: the queue box, or one of its halves.
-- `backing` is how see-through the dark label panel over it is.
local function floorPart(
	name: string,
	size: Vector3,
	cf: CFrame,
	folder: Instance,
	backing: number
): (Part, TextLabel)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Size = size
	part.CFrame = cf
	part.Color = rgb(M.Style.White)
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "FloorLabel"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Q.PixelsPerStud
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = rgb(M.Style.Panel)
	frame.BackgroundTransparency = backing
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Q.CornerPixels)
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
	-- A top face's canvas runs across the part (its Z), so the words, sized to the part's
	-- length, are turned a quarter to lie along it.
	local keep = 1 - 2 * Q.LabelInset
	local text = label(
		frame,
		"",
		UDim2.fromOffset(size.X * Q.PixelsPerStud * keep, size.Z * Q.PixelsPerStud * keep),
		UDim2.fromScale(0.5, 0.5),
		Q.FloorTextSize
	)
	text.Name = "Text"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.TextScaled = true
	text.Rotation = Q.LabelRotation
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = Q.FloorTextSize
	limit.Parent = text
	return part, text
end

-- The table's queue box (Placement.queueBox): one long floor strip up to six people step
-- into, with its two halves (team A's at the head, team B's at the foot) laid over it for
-- when four or six are in, a line between them, and the host panel floating above. The
-- server keeps the box's attributes and words current (refresh); BoxEffects on each client
-- tints, lights and sounds it from those attributes.
local function buildBox(t: any, folder: Instance)
	local id = t.engine.id
	local cx, cy, hx, hy = Placement.queueBox()
	local length, depth = 2 * hx, 2 * hy
	local box, boxText = floorPart(
		("QueueBox_%02d"):format(id),
		Vector3.new(length, Q.BoxHeight, depth),
		tableFrame(t.placement, cx, cy, Q.FloorOffset + Q.BoxHeight / 2),
		folder,
		Q.FrameTransparency
	)
	box.Transparency = Q.EmptyTransparency
	box:SetAttribute("TableId", id)
	box:SetAttribute("Occupied", false)
	box:SetAttribute("Count", 0)
	box:SetAttribute("Halves", false)
	box:SetAttribute("Even", false)
	local light = Instance.new("SurfaceLight")
	light.Face, light.Brightness, light.Range = Enum.NormalId.Top, Q.LightBrightness, Q.LightRange
	light.Color, light.Shadows, light.Parent = rgb(M.Style.White), false, box
	t.box, t.boxText, t.halves = box, boxText, {}
	for side = 1, 2 do
		local along = (if side == 1 then -1 else 1) * length / 4
		local half, text = floorPart(
			("QueueHalf_%02d_%d"):format(id, side),
			Vector3.new(length / 2 - Q.HalfGapStuds, Q.BoxHeight, depth - Q.HalfGapStuds),
			tableFrame(
				t.placement,
				cx + along,
				cy,
				Q.FloorOffset + Q.BoxHeight * 1.5 + Q.HalfLiftStuds
			),
			box,
			Q.HalfBackingTransparency
		)
		half.Transparency = 1 -- shown only while four or six are in (refresh)
		local gui = half:FindFirstChildOfClass("SurfaceGui") :: SurfaceGui
		gui.Enabled = false
		t.halves[side] = { part = half, text = text, gui = gui }
	end
	local divider = Instance.new("Part")
	divider.Name = "Divider"
	divider.Anchored = true
	divider.CanCollide = false
	divider.CanTouch = false
	divider.CanQuery = false
	divider.CastShadow = false
	divider.Material = Enum.Material.Neon
	divider.Color = rgb(M.Style.White)
	divider.Transparency = 1
	divider.Size = Vector3.new(Q.DividerStuds, Q.BoxHeight, depth)
	divider.CFrame = tableFrame(t.placement, cx, cy, Q.FloorOffset + Q.BoxHeight * 2)
	divider.Parent = box
	t.divider = divider
	local anchor = Instance.new("Part")
	anchor.Name = ("QueuePanel_%02d"):format(id)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = tableFrame(t.placement, cx, cy, Q.PanelOffset)
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
		Strings.Match.AnyMode,
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

local function setText(object: TextLabel, text: string)
	if object.Text ~= text then
		object.Text = text
	end
end

-- The box and its host panel, from the engine: who is in it, the halves when four or six
-- are, and what the table is doing. Attributes and words only change when they differ.
local function refresh(t: any)
	local e = t.engine
	local C = Strings.Match
	local count, inHalf = 0, { 0, 0 }
	for _, s in e.seats do
		if s.connected then
			count += 1
			if s.side then
				inHalf[s.side] += 1
			end
		end
	end
	local waiting = e.phase == "Waiting"
	-- Four or six split into teams by the half they stand in: both halves grey until the
	-- split is even, then both green (designer, 2026-09-25). Two need no halves.
	local halves = waiting and (count == 4 or count == 6)
	local even = inHalf[1] == inHalf[2]
	local box = t.box
	box:SetAttribute("Occupied", count > 0)
	box:SetAttribute("Count", count)
	for _, half in t.halves do
		half.part.Transparency = if halves then Q.HalfTransparency else 1
		half.part.Color = rgb(if even then M.Style.Green else Q.HalfUneven)
		half.gui.Enabled = halves
	end
	t.divider.Transparency = if halves then Q.DividerTransparency else 1
	setText(
		t.boxText,
		if not waiting
			then C.InProgress
			elseif halves then ""
			elseif count >= M.Queue.Capacity then C.BoxFull
			elseif count > 0 then C.BoxJoin:format(count, M.Queue.Capacity)
			else C.BoxEmpty:format(M.Queue.Capacity)
	)
	for side, half in t.halves do
		setText(
			half.text,
			if halves
				then C.HalfCount:format(if side == 1 then "A" else "B", inHalf[side], count // 2)
				else ""
		)
	end
	local host = if e.hostId then Engine.seat(e, e.hostId) else nil
	if e.solo and host then
		-- A solo game holds the whole table until its result.
		setText(t.title, C.SoloTitle)
		setText(t.hostLabel, C.SoloPanel:format(host.displayName))
		setText(t.statusLabel, C.SoloInProgress)
		return
	end
	setText(t.title, if waiting then C.AnyMode else C.Mode:format(e.teamSize, e.teamSize))
	setText(t.hostLabel, if host then C.Host:format(host.displayName) else C.StepIn)
	setText(
		t.statusLabel,
		if not waiting
			then C.InProgress
			elseif count >= M.Queue.Capacity then C.BoxFull
			else C.QueueStatus:format(count, M.Queue.Capacity, C.Waiting)
	)
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
	spinY: number,
	elevation: number?
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
			floorDegrees = elevation,
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
			area = ShooterStance.area(),
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
	local stance = solveStance(t, character, aim.angle, 0, 0, aim.elevation)
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
	if e.phase == "Waiting" or e.phase == "Result" then
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
	-- A solo player keeps the table through a foul: nobody else takes over. Once the shot's
	-- stroke has played, the shooter may walk while the balls roll (Engine.shooterHeld).
	local since = if t.shotAt then now() - t.shotAt else nil
	local locked = e.shooter == p.UserId and Engine.shooterHeld(e.phase, e.solo, since)
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
	local fx, fy, fcx, fcy = Placement.matchFence()
	local x, y = Placement.toTable(t.placement, root.Position.X, root.Position.Z)
	x, y = x * scale, y * scale -- studs along the table's axes
	local escape = M.Fence.EscapeStuds
	local outside = math.abs(x - fcx) > fx + escape or math.abs(y - fcy) > fy + escape
	if outside or root.Position.Y < t.placement.y - Q.FallTolerance then
		local inset = M.Fence.ThicknessStuds + Q.RespawnBoundaryInset
		local cx = math.clamp(x, fcx - (fx - inset), fcx + fx - inset)
		local cy = math.clamp(y, fcy - (fy - inset), fcy + fy - inset)
		-- Keep clear of the table itself: land on the queue box's line instead.
		local bx, by = Placement.barrierHalfExtents()
		if math.abs(cx) < bx and math.abs(cy) < by then
			local _, boxY = Placement.queueBox()
			cy = boxY
		end
		local wx, _, wz = Placement.fromTableStuds(t.placement, cx, cy, 0)
		root.CFrame = CFrame.new(wx, t.placement.y + Q.RespawnHeight, wz) * root.CFrame.Rotation
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

--- A shot was accepted at table `t` (ShotService, and the Studio QA fixture): hold the
--- shooter and put the anchored root exactly where they shot from, turned to face the table
--- centre (ShooterStance.idle), with that spot on the root's ShotSpot attribute for the
--- client. Called after acceptShot, which leaves the cue ball at its spot before the shot
--- until the shot resolves; `angle` and `spin` are the accepted payload's. The root then
--- waits there while the stroke plays (Multiplayer.Stance.HoldAfterShotSeconds) and is let
--- go in place, so the player can walk while the balls roll.
function Service.shotAccepted(
	t: any,
	userId: number,
	angle: number,
	spin: { x: number, y: number }?,
	elevation: number?
)
	local p = Players:GetPlayerByUserId(userId)
	if not p or not ShotInput.isFinite(angle) then
		return
	end
	t.shotAt = now()
	constrain(p, t) -- the phase is Resolving now, so this holds the body and anchors the root
	local root, character = rootOf(p), p.Character
	if not root or not character then
		return
	end
	local sx, sy = 0, 0
	if type(spin) == "table" and ShotInput.isFinite(spin.x) and ShotInput.isFinite(spin.y) then
		sx, sy = Cue.clampSpin(spin.x, spin.y)
	end
	local stance = solveStance(
		t,
		character,
		angle % (2 * math.pi),
		sx,
		sy,
		ShotInput.roundElevation(elevation)
	)
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

-- Where a root stands relative to table `t`'s queue box, in the box's own studs: X along
-- the table's length (head negative), Z across it, Y up from the box.
local function inBoxSpace(t: any, root: BasePart): Vector3
	return t.box.CFrame:PointToObjectSpace(root.Position)
end

local function insideBox(t: any, v: Vector3, margin: number): boolean
	local half = t.box.Size / 2
	return math.abs(v.X) <= half.X + margin
		and math.abs(v.Z) <= half.Z + margin
		and math.abs(v.Y) < Q.VerticalTolerance
end

-- The half of the box a point is in: 1 the head half (team A's), 2 the foot half. A player
-- already in one keeps it until Queue.SideHysteresisStuds past the middle, so standing on
-- the line does not flicker between teams.
local function sideAt(v: Vector3, current: number?): number
	local h = M.Queue.SideHysteresisStuds
	if current == 1 and v.X < h then
		return 1
	elseif current == 2 and v.X > -h then
		return 2
	end
	return if v.X < 0 then 1 else 2
end

local function poll(t: any, time: number)
	local e = t.engine
	local Queue = M.Queue
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, p in players do
		local root = rootOf(p)
		local v = if root then inBoxSpace(t, root) else nil
		local inside = v ~= nil and insideBox(t, v, 0)
		local inQueueArea = v ~= nil and insideBox(t, v, Q.AreaMargin)
		if not inQueueArea then
			t.blocked[p.UserId] = nil
		end
		local s = Engine.seat(e, p.UserId)
		if s then
			if e.phase == "Waiting" then
				if inQueueArea and v then
					t.outside[p.UserId] = nil
					Engine.setSide(e, p.UserId, sideAt(v, s.side))
				else
					t.outside[p.UserId] = t.outside[p.UserId] or time
					if time - t.outside[p.UserId] >= Queue.ExitGraceSeconds then
						Engine.remove(e, p.UserId, time)
					end
				end
			else
				constrain(p, t)
			end
		elseif inside and v and not seatOf[p.UserId] and not t.blocked[p.UserId] then
			t.dwell[p.UserId] = t.dwell[p.UserId] or time
			if time - t.dwell[p.UserId] >= Queue.DwellSeconds then
				if Engine.join(e, p.UserId, p.Name, p.DisplayName, sideAt(v, nil), time) then
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
	local old = parent:FindFirstChild(Service.ZoneFolderName)
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Service.ZoneFolderName
	folder.Parent = parent
	-- One server-owned table per Config.Hub row; any of them seats 1v1, 2v2 or 3v3.
	for id = 1, Placement.tableCount() do
		local p = Placement.forTable(id)
		assert(p, "Missing table placement")
		local t: any = {
			engine = Engine.new(id, newSeed()),
			placement = p,
			dwell = {},
			outside = {},
			blocked = {},
			sentRevision = 0,
		}
		tables[id] = t
		buildBox(t, folder)
		buildBarrier(t, folder)
		buildFence(t, folder)
		Service.broadcast(t)
	end
	Net.get("SnapshotRequest").OnServerEvent:Connect(function(p)
		if not Service.allow(p, "snapshot") then
			return
		end
		for id = 1, Placement.tableCount() do
			Service.broadcast(tables[id], p)
		end
	end)
	-- There is no join request: seats come only from the server watching the boxes.
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
		-- The coin for a host's Start is the server's, like the rack seed.
		local accepted = Engine.action(t.engine, p.UserId, payload, now(), rng:NextInteger(1, 2))
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
	aimUpdate.OnServerEvent:Connect(
		function(p, id, angle, epoch, turnId, pull, seq, x, y, elevation)
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
				-- A missing or bad angle just draws the default cue: it is cosmetic.
				elevation = ShotInput.roundElevation(elevation) or Config.Cue.CueElevationDegrees,
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
		end
	)
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
				-- Back in the queue box, which the match fence takes in.
				local cx, cy = Placement.queueBox()
				root.CFrame =
					CFrame.new(Placement.fromTableStuds(t.placement, cx, cy, Q.RespawnHeight))
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
	-- so a watched ball in hand is not held to the box-poll rate.
	local function broadcastAims()
		local batch = {}
		for id = 1, Placement.tableCount() do
			local t = tables[id]
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
				AimStream.pack(
					batch,
					e.id,
					t.aim.by,
					t.aim.angle,
					cue.x,
					cue.y,
					t.aim.pull,
					t.aim.elevation
				)
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
		if elapsed < 1 / M.Queue.PollsPerSecond then
			return
		end
		elapsed = 0
		for id = 1, Placement.tableCount() do
			local t = tables[id]
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
