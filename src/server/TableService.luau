--!strict
-- Roblox adapter: identity/proximity, queue pads, replication and characters.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
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
local Ranking = require(script.Parent.Ranking)
local GlobalQueue = require(script.Parent.GlobalQueue)
local PadBar = require(Shared.Matchmaking.PadBar)
local Ranks = require(Shared.Progression.Ranks)
local M = Config.Multiplayer
local Q = M.QueueVisual
local Kit = Config.UI.Kit
local Service = {}
-- Every table's queue pad, barrier and fence.
Service.ZoneFolderName = "TableZones"
local tables: { [number]: any } = {}
local seatOf: { [number]: number } = {}
local buckets: { [string]: any } = {}
local characterSaved: { [number]: any } = {}
local flushHooks: { (any) -> () } = {} -- Service.onFlush
local lateShotHooks: { (any) -> () } = {} -- Service.onLateShot
local rng = Random.new()
-- Every game opens on its own rack: the seed only moves each ball a hair, but a break is
-- sensitive to exactly that, so two games never play out the same. The seed travels in the
-- snapshot, so every client still builds the identical rack.
local function newSeed(): number
	return rng:NextInteger(1, Config.Rack.MaxSeed)
end
local started = false
-- An arena server (ArenaService, designer 2026-09-28): one table, no queue pad, players
-- seated by the global queue's teams.
local arena = false
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
	-- A shot the clock finished judging (Time Stop's resume) is paid and sent now, like an
	-- accepted one (ShotService's hook).
	if Engine.takeLateShot(t.engine) then
		for _, hook in lateShotHooks do
			local ok, err = pcall(function()
				hook(t)
			end)
			if not ok then
				warn("[8ball] late shot hook failed: " .. tostring(err))
			end
		end
	end
end

--- Adds `hook(t)` for a shot judged by the clock rather than by ShotFired (a Time Stop shot's
--- resume): it pays and sends the shot as ShotService does for an accepted one.
function Service.onLateShot(hook: (any) -> ())
	table.insert(lateShotHooks, hook)
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
	l.TextColor3 = rgb(Kit.Colors.White)
	l.Font = (Enum.Font :: any)[Kit.Font]
	l.TextSize = fontSize
	-- White words outlined in ink, like every screen (docs/UI_STYLE.md).
	local outline = Instance.new("UIStroke")
	outline.Color = rgb(Kit.Colors.Ink)
	-- The kit's rule (HudParts.outlineFor): thin on small text, so letters keep their holes.
	outline.Thickness = if fontSize < Kit.TextOutlineThinBelowPx
		then Kit.TextOutlineThinPx
		else math.max(Kit.TextOutlineMinPx, math.floor(fontSize * Kit.TextOutlineRatio + 0.5))
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline.Parent = l
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

-- Walls around the whole match area and a little room beyond it (Placement.matchWalls), so
-- participants stay near their table without being teleported: they walk into these like any
-- wall. In the PoolFence collision group, which
-- only collides with PoolParticipants, so spectators and people heading for a queue pass
-- straight through. CanQuery off keeps them out of camera occlusion and raycasts, and a
-- PassThrough PathfindingModifier out of every path (the tutorial's bot and arrow walk to a
-- pad inside them).
local function buildFence(t: any, folder: Instance)
	local F = M.Fence
	local height = M.Barrier.HeightStuds
	local fx, fy, cx, cy = Placement.matchWalls(t.engine.teamSize)
	local w = F.ThicknessStuds
	-- The fence takes in the queue pad in front of the table, so it is centred off the table.
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
		local modifier = Instance.new("PathfindingModifier")
		modifier.PassThrough = true
		modifier.Parent = part
		part.Parent = folder
	end
end

-- The table's queue pad (Placement.queuePad, designer 2026-09-26): a see-through rounded
-- rectangle (tinted glass, 2026-09-27) lying along the table's long side toward the
-- entrance, with a glowing rim, the table's mode written big on it and JOIN or the count
-- under that. Stand anywhere on it to join. The part is invisible and level (turned only
-- about the up axis); everything shows on its top face. The
-- server keeps its attributes and words current (refresh); PadEffects on each client tints
-- the rim, raises the glowing queue portal over it and bobs an arrow over it from those
-- attributes.
local function buildPad(t: any, folder: Instance)
	local id = t.engine.id
	local teamSize = t.engine.teamSize
	local cx, cy, hx, hy = Placement.queuePad(teamSize)
	-- A top face's canvas runs across its part (the part's Z), so a quarter turn
	-- (LabelRotation) lays the words along the table; the part's size turns with it.
	local turned = math.round(Q.LabelRotation / 90) % 2 == 1
	local pad = Instance.new("Part")
	pad.Name = ("QueuePad_%02d"):format(id)
	pad.Anchored = true
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad.CastShadow = false
	pad.Transparency = 1
	pad.Size = if turned
		then Vector3.new(2 * hy, Q.PadHeight, 2 * hx)
		else Vector3.new(2 * hx, Q.PadHeight, 2 * hy)
	pad.CFrame = tableFrame(t.placement, cx, cy, Q.FloorOffset + Q.PadHeight / 2)
		* CFrame.Angles(0, math.rad(Q.LabelRotation), 0)
	pad:SetAttribute("TableId", id)
	pad:SetAttribute("TeamSize", teamSize)
	pad:SetAttribute("Capacity", teamSize * 2)
	pad:SetAttribute("Occupied", false)
	pad:SetAttribute("Count", 0)
	pad:SetAttribute("Full", false)
	pad.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PadLabel"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Q.PixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = Q.RimBrightness
	gui.Parent = pad
	-- The plate, inset by the rim so its glowing outline fits on the canvas.
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.new(1, -2 * Q.RimPx, 1, -2 * Q.RimPx)
	plate.BackgroundColor3 = rgb(Q.PadColor)
	plate.BackgroundTransparency = Q.PadTransparency
	plate.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, Q.PadCornerPx)
	corner.Parent = plate
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = rgb(Q.RimFree)
	rim.Thickness = Q.RimPx
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = plate
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = plate
	local mode = label(
		plate,
		Strings.Match.Mode:format(teamSize, teamSize),
		UDim2.new(1, 0, 0, Q.ModeTextSize),
		UDim2.new(),
		Q.ModeTextSize
	)
	mode.Name = "Mode"
	mode.LayoutOrder = 1
	local count =
		label(plate, "", UDim2.new(1, 0, 0, Q.CountTextSize), UDim2.new(), Q.CountTextSize)
	count.Name = "Count"
	count.LayoutOrder = 2
	local light = Instance.new("SurfaceLight")
	light.Face = Enum.NormalId.Top
	light.Brightness = Q.LightBrightness
	light.Range = Q.LightRange
	light.Color = rgb(Kit.Colors.White)
	light.Shadows = false
	light.Parent = pad
	t.pad, t.countText, t.modeText = pad, count, mode
end

local function setText(object: TextLabel, text: string)
	if object.Text ~= text then
		object.Text = text
	end
end

-- The pad from the engine: how many are on it, whether it is full or its game is on, and the
-- words under the mode. Attributes and words only change when they differ. The sign over it
-- is the client's (TableSign), drawn from the snapshot every client already has.
local function refresh(t: any)
	if not t.pad then
		return -- an arena's table has no pad
	end
	local e = t.engine
	local C = Strings.Match
	local count = Engine.count(e)
	local capacity = Engine.capacity(e)
	local waiting = e.phase == "Waiting"
	local pad = t.pad
	pad:SetAttribute("Occupied", count > 0)
	pad:SetAttribute("Count", count)
	pad:SetAttribute("Full", not waiting or count >= capacity)
	setText(
		t.countText,
		if not waiting
			then C.PadPlaying
			elseif count >= capacity then C.PadFull
			elseif count > 0 then C.PadCount:format(count, capacity)
			else C.PadJoin
	)
end

function Service.broadcast(t: any, player: Player?)
	-- Every state change comes through here, so a match that has just ended is paid once,
	-- before its result snapshot goes out (Ranking).
	Ranking.check(t)
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
	-- Then whatever else rides with a shot's feedback (UltService's bar gains).
	for _, hook in flushHooks do
		hook(t)
	end
end

--- Adds `hook(t)` to every flush (after a shot is accepted, and after each advance), for a
--- service this one cannot require (UltService requires this module).
function Service.onFlush(hook: (any) -> ())
	table.insert(flushHooks, hook)
end

-- Where a root about to be let go can stand: clear of every table's barrier (by the release
-- clearance) and standing on the floor found under it. Nil when it already does. While held
-- the body touches nothing (HELD), so a held body overlapping the barrier, or put below the
-- floor, would be pushed through the floor the moment physics took it back (designer,
-- 2026-10-01: a player fell under the map after a match).
local function clearSpot(root: BasePart): CFrame?
	local pos = root.Position
	local x, z = pos.X, pos.Z
	local moved = false
	for _, t in tables do
		local nx, nz = Placement.outsideBarrier(t.placement, x, z, M.Barrier.ReleaseClearanceStuds)
		if nx and nz then
			x, z, moved = nx, nz, true
		end
	end
	local character = root.Parent
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	local stand = (if hum then hum.HipHeight else Q.RespawnHeight) + root.Size.Y / 2
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local bodies: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(bodies, p.Character)
		end
	end
	params.FilterDescendantsInstances = bodies
	local from = Vector3.new(x, pos.Y + Q.ReleaseProbeUpStuds, z)
	local hit = Workspace:Raycast(from, Vector3.new(0, -Q.ReleaseProbeDownStuds, 0), params)
	local floorY = if hit then hit.Position.Y else nil
	local sunk = floorY ~= nil and pos.Y < floorY + stand * Q.SunkShare
	if not moved and not sunk and floorY ~= nil then
		return nil
	end
	local y = if floorY then floorY + stand else pos.Y
	return CFrame.new(x, y, z) * root.CFrame.Rotation
end

-- Hand a held root back to the player where it stands. An anchored part keeps whatever
-- velocity it had when it was anchored, so a root just let go is stilled first, or it would
-- resume the walk it was stopped in and shove the player off the spot they shot from. It is
-- no longer at a shot spot the client should return to, either. A root that would be let go
-- inside a barrier or below the floor first steps to the nearest clear spot (clearSpot).
local function release(root: BasePart, anchored: boolean)
	local released = root.Anchored and not anchored
	if released then
		local spot = clearSpot(root)
		if spot then
			root.CFrame = spot
		end
	end
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
	local fx, fy, fcx, fcy = Placement.matchWalls(t.engine.teamSize)
	local x, y = Placement.toTable(t.placement, root.Position.X, root.Position.Z)
	x, y = x * scale, y * scale -- studs along the table's axes
	local escape = M.Fence.EscapeStuds
	local outside = math.abs(x - fcx) > fx + escape or math.abs(y - fcy) > fy + escape
	if outside or root.Position.Y < t.placement.y - Q.FallTolerance then
		local inset = M.Fence.ThicknessStuds + Q.RespawnBoundaryInset
		local cx = math.clamp(x, fcx - (fx - inset), fcx + fx - inset)
		local cy = math.clamp(y, fcy - (fy - inset), fcy + fy - inset)
		-- Keep clear of the table itself: land on the queue pad instead.
		local bx, by = Placement.barrierHalfExtents()
		if math.abs(cx) < bx and math.abs(cy) < by then
			cx, cy = Placement.queuePad(t.engine.teamSize)
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

-- Whether a root stands on table `t`'s queue pad, grown by `margin` studs: inside its
-- rectangle across the floor and on the same floor.
local function onPad(t: any, root: BasePart, margin: number): boolean
	if not t.pad then
		return false
	end
	local d = t.pad.CFrame:PointToObjectSpace(root.Position)
	local half = t.pad.Size / 2
	return math.abs(d.X) <= half.X + margin
		and math.abs(d.Z) <= half.Z + margin
		and math.abs(d.Y) < Q.VerticalTolerance
end

-- Whether a root stands more than `extra` studs outside table `t`'s match walls.
local function outsideArea(t: any, root: BasePart, extra: number): boolean
	local scale = Config.Table.StudsPerInch
	local fx, fy, fcx, fcy = Placement.matchWalls(t.engine.teamSize)
	local x, y = Placement.toTable(t.placement, root.Position.X, root.Position.Z)
	x, y = x * scale, y * scale
	return math.abs(x - fcx) > fx + extra or math.abs(y - fcy) > fy + extra
end

-- Set below sendRequest: a host who just stepped on asks everyone free for an opponent.
local askForOpponent: (t: any, host: Player, time: number) -> ()

local function poll(t: any, time: number)
	local e = t.engine
	local Queue = M.Queue
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)
	for _, p in players do
		local root = rootOf(p)
		local inside = root ~= nil and onPad(t, root, 0)
		local inQueueArea = root ~= nil and onPad(t, root, Q.AreaMargin)
		if not inQueueArea then
			t.blocked[p.UserId] = nil
		end
		local s = Engine.seat(e, p.UserId)
		if s then
			if e.phase == "Waiting" then
				if arena then
					continue -- arriving players wait for the rest; there is no pad to leave
				end
				if inQueueArea then
					t.outside[p.UserId] = nil
				else
					t.outside[p.UserId] = t.outside[p.UserId] or time
					if time - t.outside[p.UserId] >= Queue.ExitGraceSeconds then
						Engine.remove(e, p.UserId, time)
					end
				end
			else
				constrain(p, t)
				-- Walking away from a finished lobby game says no to the rematch.
				if
					not arena
					and e.phase == "Result"
					and e.rematch
					and not e.rematch.declined
					and root
					and outsideArea(t, root, M.Fence.EscapeStuds)
				then
					Engine.action(
						e,
						p.UserId,
						{ kind = "Decline", epoch = e.epoch, turnId = e.turnId },
						time
					)
				end
			end
		elseif
			not arena
			and inside
			and not seatOf[p.UserId]
			and not t.blocked[p.UserId]
			and p:GetAttribute("DataLoaded") == true -- no seat before the save is open
		then
			t.dwell[p.UserId] = t.dwell[p.UserId] or time
			if time - t.dwell[p.UserId] >= Queue.DwellSeconds then
				if Engine.join(e, p.UserId, p.Name, p.DisplayName, time) then
					seatOf[p.UserId] = e.id
					askForOpponent(t, p, time)
				end
			end
		else
			t.dwell[p.UserId] = nil
		end
	end
	releaseMissing(t)
end

-- Whether table `t`'s host still wants players: waiting with room on the pad, and asked
-- recently enough for the popup to still be up (Queue.RequestSeconds).
local function wantsOpponent(t: any, epoch: any, time: number): boolean
	local e = t.engine
	return e.epoch == epoch
		and e.phase == "Waiting"
		and Engine.count(e) < Engine.capacity(e)
		and e.requestedAt ~= nil
		and time - e.requestedAt <= M.Queue.RequestSeconds
end

-- The tutorial lane: whether `player` may see `host`'s ask (TutorialService: nobody in the
-- tutorial's first server sends or gets one). Nil: everyone may.
local requestFilter: ((host: Player, player: Player) -> boolean)? = nil

--- The tutorial lane's filter on Request opponent's popups (see requestFilter).
function Service.setRequestFilter(fn: ((host: Player, player: Player) -> boolean)?)
	requestFilter = fn
end

-- Ask everyone free in the server (not seated at any table) whether they want to play at
-- the host of table `t`'s table (designer, 2026-09-27).
local function sendRequest(t: any, host: Player)
	local e = t.engine
	local ask = {
		tableId = e.id,
		epoch = e.epoch,
		teamSize = e.teamSize,
		userId = host.UserId,
		name = host.DisplayName,
		at = e.requestedAt,
	}
	for _, p in Players:GetPlayers() do
		if
			p ~= host
			and not seatOf[p.UserId]
			and (requestFilter == nil or requestFilter(host, p))
		then
			Net.get("OpponentRequest"):FireClient(p, ask)
		end
	end
end

-- When each player's last "needs an opponent!" went out by itself (askForOpponent), so
-- stepping off and on again does not send another within AutoRequestCooldownSeconds.
local autoAskedAt: { [number]: number } = {}

-- The matchmaking bar (designer, 2026-10-07): a host who steps onto a pad asks everyone free
-- for an opponent at once, no button to press, friends in the server or not (2026-10-09).
askForOpponent = function(t: any, host: Player, time: number)
	local e = t.engine
	if
		e.phase ~= "Waiting"
		or not PadBar.autoRequest({
			isHost = e.hostId == host.UserId,
			count = Engine.count(e),
			capacity = Engine.capacity(e),
			searching = e.search ~= nil,
			lastAt = autoAskedAt[host.UserId],
			now = time,
		})
	then
		return
	end
	local payload = { kind = "RequestOpponent", epoch = e.epoch, turnId = e.turnId }
	if Engine.action(e, host.UserId, payload, time) then
		autoAskedAt[host.UserId] = time
		sendRequest(t, host)
	end
end

-- A player answered an ask with Join: if it still stands and they are free, stand them on
-- the pad, facing the table, and seat them at once (the poll would a moment later).
local function answerRequest(p: Player, id: any, epoch: any)
	local t = type(id) == "number" and tables[id]
	local root = rootOf(p)
	if
		not t
		or not root
		or seatOf[p.UserId]
		or p:GetAttribute("DataLoaded") ~= true -- a match's results need the save open
		or not wantsOpponent(t, epoch, now())
	then
		return
	end
	local e = t.engine
	local spot = t.pad.Position + Vector3.new(0, Q.RespawnHeight, 0)
	local centre = Vector3.new(t.placement.x, spot.Y, t.placement.z)
	local character = p.Character :: Model
	character:PivotTo(CFrame.lookAt(spot, centre))
	t.blocked[p.UserId] = nil
	if Engine.join(e, p.UserId, p.Name, p.DisplayName, now()) then
		seatOf[p.UserId] = e.id
		Service.broadcast(t)
	end
end

---------------------------------------------------------------------------------------------
-- The global queue from a pad (designer, 2026-09-28)
---------------------------------------------------------------------------------------------
local function sameUsers(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i, u in a do
		if b[i] ~= u then
			return false
		end
	end
	return true
end

local function playersOf(users: { number }): { Player }
	local out = {}
	for _, id in users do
		local p = Players:GetPlayerByUserId(id)
		if p then
			table.insert(out, p)
		end
	end
	return out
end

-- The search of table `t` found a match: tell its players, then teleport them. Dropped if
-- the pad has moved on (its search cancelled, a local game started): the other side's arena
-- then starts without them or sends its players on.
local function searchFound(t: any, epoch: number, search: any, match: any)
	local e = t.engine
	if t.search ~= search or e.epoch ~= epoch or e.phase ~= "Waiting" or not e.search then
		warn(("[8ball] GQ table %d moved on; match %s dropped on this side"):format(e.id, match.id))
		if t.search == search then
			t.search = nil
		end
		return
	end
	Engine.searchFound(e, search.ticket.users, now())
	t.foundAt = now()
	Service.broadcast(t)
	local players = playersOf(search.ticket.users)
	GlobalQueue.notify(players, { kind = "Found", mode = e.teamSize })
	task.wait(Config.GlobalQueue.FoundLeadSeconds)
	GlobalQueue.teleport(players, match, function(p: Player, reason: string)
		GlobalQueue.notify({ p }, { kind = "Failed", reason = reason })
		if t.search == search then
			t.search = nil
		end
		if e.epoch == epoch and e.phase == "Waiting" and e.search and e.search.found then
			Engine.clearSearch(e)
			t.foundAt = nil
			Service.broadcast(t)
		end
	end)
end

-- The host's Join Global Queue: the first whole side on the pad goes into the global queue.
-- Yields while the search is posted. True when it went in.
local function startSearch(t: any, host: Player): boolean
	local e = t.engine
	if arena or t.search or t.searchStarting or not Engine.canSearch(e, host.UserId) then
		return false
	end
	local users = Engine.searchParty(e)
	local players = playersOf(users)
	if #players ~= #users then
		return false
	end
	for _, p in players do
		if p:GetAttribute("DataLoaded") ~= true then
			return false
		end
	end
	local epoch = e.epoch
	t.searchStarting = true
	local search, why = GlobalQueue.enqueue({
		players = players,
		mode = e.teamSize,
		home = game.JobId,
		-- Every search plays with ults on (designer, 2026-10-02: the card's On / Off toggle is
		-- gone; a save still holding Off is ignored).
		ults = true,
		-- A 1v1's search stands with MemoryStore down: LocalSearch matches it here.
		holdIfDown = e.teamSize == 1,
		onFound = function(found: any, match: any)
			searchFound(t, epoch, found, match)
		end,
	})
	t.searchStarting = false
	if not search then
		GlobalQueue.notify(players, { kind = "Failed", reason = "Store" })
		warn(("[8ball] GQ table %d could not start a search: %s"):format(e.id, tostring(why)))
		return false
	end
	-- The pad may have changed while the search went in.
	if
		e.epoch ~= epoch
		or not Engine.canSearch(e, host.UserId)
		or not sameUsers(Engine.searchParty(e), users)
	then
		task.spawn(GlobalQueue.cancel, search)
		return false
	end
	t.search, t.searchEpoch = search, epoch
	Engine.setSearch(e, now())
	GlobalQueue.notify(players, { kind = "Searching", mode = e.teamSize })
	return true
end

-- The host's Cancel. Yields. True when the search is out of the queue; a search the queue
-- already matched stands (its players go), and a store that does not answer keeps it.
local function stopSearch(t: any, host: Player): boolean
	local e = t.engine
	local search = t.search
	if not search or not GlobalQueue.isWaiting(search) or e.hostId ~= host.UserId then
		return false
	end
	if GlobalQueue.cancel(search) ~= "cancelled" then
		return false
	end
	if t.search == search then
		t.search = nil
	end
	if e.search and not e.search.found then
		Engine.clearSearch(e)
	end
	return true
end

-- Whether `userId` may host a table of `difficulty` (designer, 2026-10-02: Difficult and
-- Challenger from Gold I, Config.Ranks.Unlocks): their rank, the server-set RankIndex. Someone
-- not in this server (a Studio stand-in) hosts Classic only.
local function mayHost(userId: number?, difficulty: any): boolean
	local player = if userId then Players:GetPlayerByUserId(userId) else nil
	local index = if player then player:GetAttribute("RankIndex") else nil
	return Ranks.canHost(
		{ index = if type(index) == "number" then index else 0 } :: any,
		difficulty
	)
end

-- A waiting table whose host may not host its difficulty (the host left and someone of a
-- lower rank took over) goes back to the default.
local function keepDifficulty(t: any)
	local e = t.engine
	local level = e.settings and e.settings.difficulty
	if e.phase == "Waiting" and level ~= nil and level ~= Config.Difficulty.Default then
		if not mayHost(e.hostId, level) then
			e.settings.difficulty = Config.Difficulty.Default
			e.revision += 1
		end
	end
end

-- Each poll: a search whose pad no longer backs it (a party member stepped off, the host
-- left, the pad filled for a local game) is cancelled; a found search whose players have
-- all gone (teleported) is cleared from the pad.
local function watchSearch(t: any)
	local e = t.engine
	local search = t.search
	if search and GlobalQueue.isWaiting(search) and not t.searchCancelling then
		local lost = not e.search or e.phase ~= "Waiting" or e.epoch ~= t.searchEpoch
		local full = e.phase == "Waiting" and Engine.count(e) >= Engine.capacity(e)
		if lost or full then
			t.searchCancelling = true
			task.spawn(function()
				local outcome = GlobalQueue.cancel(search)
				t.searchCancelling = false
				if outcome == "cancelled" then
					if t.search == search then
						t.search = nil
					end
					if
						e.epoch == t.searchEpoch
						and e.phase == "Waiting"
						and e.search
						and not e.search.found
					then
						Engine.clearSearch(e)
						Service.broadcast(t)
					end
					if lost then
						GlobalQueue.notify(playersOf(search.ticket.users), { kind = "Stopped" })
					end
				end
			end)
		end
	elseif search and not GlobalQueue.isWaiting(search) and search.state == "done" then
		t.search = nil
	end
	if e.search and e.search.found and e.phase == "Waiting" then
		local anyone = false
		for _, id in e.search.users do
			if Engine.seat(e, id) then
				anyone = true
			end
		end
		-- Everyone left for the arena, or the teleport never came back (a minute).
		if not anyone or (t.foundAt and now() - t.foundAt > 60) then
			Engine.clearSearch(e)
			t.foundAt = nil
			if t.search and t.search.state ~= "waiting" then
				t.search = nil
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- The arena's one table (ArenaService)
---------------------------------------------------------------------------------------------
--- The arena's table (the only one), or nil outside an arena.
function Service.arenaTable(): any?
	return if arena then tables[1] else nil
end

--- Seat an arrived player on their side. True when they are seated.
function Service.seatArena(p: Player, team: number): boolean
	local t = tables[1]
	if not arena or not t then
		return false
	end
	if seatOf[p.UserId] then
		return true
	end
	local e = t.engine
	if Engine.join(e, p.UserId, p.Name, p.DisplayName, now(), team) then
		seatOf[p.UserId] = e.id
		Service.broadcast(t)
		return true
	end
	return false
end

--- Studio: seat a pretend player (no Player object) on `team`, for one-person tests.
function Service.seatSynthetic(userId: number, name: string, team: number): boolean
	local t = tables[1]
	if not arena or not t or not RunService:IsStudio() then
		return false
	end
	local ok = Engine.join(t.engine, userId, name, name, now(), team)
	if ok then
		Service.broadcast(t)
	end
	return ok
end

--- Start the arena's game (both sides have someone). True when it started.
function Service.startArena(): boolean
	local t = tables[1]
	if not arena or not t then
		return false
	end
	Service.advance(t, now())
	if Engine.startFixed(t.engine, now(), rng:NextInteger(1, 2)) then
		Service.broadcast(t)
		return true
	end
	return false
end

--- A player's table vote from the arena's own row (Play another and Lobby also say no to
--- the rematch). True when the engine took it.
function Service.arenaDecline(p: Player): boolean
	local t = tables[1]
	if not arena or not t then
		return false
	end
	local e = t.engine
	Service.advance(t, now())
	if
		Engine.action(e, p.UserId, { kind = "Decline", epoch = e.epoch, turnId = e.turnId }, now())
	then
		Service.broadcast(t)
		return true
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Bots (the Bots lane, src/server/Bots): a bot is a seat with no Player, its id negative. The
-- BotService drives it through these, as the remotes drive a person.
---------------------------------------------------------------------------------------------
local actionHooks: { [string]: (t: any, p: Player, payload: any) -> boolean } = {}

--- Adds a host-card action the engine does not know (Play against PC, Fill with PC):
--- `hook(t, player, payload)` runs instead of Engine.action and says whether it was taken.
function Service.onAction(kind: string, hook: (t: any, p: Player, payload: any) -> boolean)
	actionHooks[kind] = hook
end

--- Starts table `t`'s global search for its host `host`, as their Play Global would (the
--- tutorial's game 2 starts it for them). Yields; true when the search went in.
function Service.startSearch(t: any, host: Player): boolean
	local ok = startSearch(t, host)
	Service.broadcast(t)
	return ok
end

--- Every table (BotService's poll).
function Service.all(): { [number]: any }
	return tables
end

--- The collision group of a table's participants (a seated bot's body joins it).
Service.ParticipantsGroup = PARTICIPANTS

--- Seats a bot at table `t` (on `team` at an arena's table). True when seated.
function Service.seatBot(t: any, userId: number, name: string, team: number?): boolean
	local ok = Engine.join(t.engine, userId, name, name, now(), if arena then team else nil)
	if ok then
		Service.broadcast(t)
	end
	return ok
end

--- A bot's aim, as a person's AimUpdate sets it (the aim stream carries it to everyone).
function Service.setBotAim(t: any, userId: number, angle: number, pull: number, elevation: number?)
	local e = t.engine
	if e.shooter ~= userId or not aimPhase(e.phase) or not ShotInput.isFinite(angle) then
		return
	end
	t.aim = {
		angle = angle % (2 * math.pi),
		pull = AimStream.quantizePull(math.clamp(pull, 0, 1)) or 0,
		elevation = elevation or Config.Cue.CueElevationDegrees,
		by = userId,
		turnId = e.turnId,
		epoch = e.epoch,
	}
end

--- A bot drags its ball in hand (the aim stream's ball-in-hand move).
function Service.moveBotCue(t: any, userId: number, seq: number, x: number, y: number): boolean
	local e = t.engine
	local time = now()
	Service.advance(t, time)
	return Engine.moveCue(
		e,
		userId,
		{ epoch = e.epoch, turnId = e.turnId, seq = seq, x = x, y = y },
		time
	)
end

--- Holds a seated bot's body like a shooting person's (constrain): anchored, and while it
--- lines up, its root follows the stance of its aim. Otherwise left where it is.
function Service.holdBot(t: any, character: Model, userId: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local e = t.engine
	if e.phase == "Waiting" then
		return
	end
	root.Anchored = true
	if e.shooter == userId and aimPhase(e.phase) then
		followStance(t, { UserId = userId } :: any, root, character)
	end
end

--- A bot's shot was accepted: its body goes to the spot it shot from (Service.shotAccepted
--- for a person).
function Service.botShotAccepted(
	t: any,
	character: Model,
	angle: number,
	spin: any,
	elevation: number?
)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") or not ShotInput.isFinite(angle) then
		return
	end
	t.shotAt = now()
	root.Anchored = true
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
	if stance then
		local x, y, z, yaw = ShooterStance.idle(stance)
		local spot = worldSpot(t.placement, x, y, z, yaw)
		if spot and placeRoot(t, root, spot) then
			root:SetAttribute(SHOT_SPOT, spot)
		end
	end
end

--- A lobby search that waited long enough is given a bot instead (the Bots lane): its search
--- comes out of the global queue and `match` (a reserved arena whose list names the bot) goes
--- ahead as if the queue had found it. Yields. False when the search was not waiting any more
--- or the queue matched it with real players after all (then that match stands).
function Service.searchToMatch(t: any, match: any): boolean
	local e = t.engine
	local search = t.search
	if arena or not search or not GlobalQueue.isWaiting(search) or t.searchCancelling then
		return false
	end
	t.searchCancelling = true
	local outcome = GlobalQueue.cancel(search)
	t.searchCancelling = false
	if outcome ~= "cancelled" or t.search ~= search or not e.search or e.search.found then
		return false
	end
	searchFound(t, t.searchEpoch, search, match)
	return true
end

--- This server's search (LocalSearch): takes table `t`'s waiting search out of the global
--- queue for a match here. Yields. True when it is out (false: the queue matched it first, or
--- there is none).
function Service.takeSearch(t: any): boolean
	local e = t.engine
	local search = t.search
	if arena or not search or not GlobalQueue.isWaiting(search) or t.searchCancelling then
		return false
	end
	t.searchCancelling = true
	local outcome = GlobalQueue.cancel(search)
	t.searchCancelling = false
	if outcome ~= "cancelled" or t.search ~= search then
		return false
	end
	t.search = nil
	if e.search and not e.search.found then
		Engine.clearSearch(e)
	end
	Service.broadcast(t)
	return true
end

--- This server's search (LocalSearch): stands `p` on table `t`'s pad facing the table and
--- seats them at once, as an answered ask does, leaving the waiting pad they were on. True
--- when they are seated there.
function Service.placeOnPad(t: any, p: Player): boolean
	local e = t.engine
	local character = p.Character
	if
		arena
		or not t.pad
		or not character
		or rootOf(p) == nil
		or e.phase ~= "Waiting"
		or p:GetAttribute("DataLoaded") ~= true
	then
		return false
	end
	if Engine.seat(e, p.UserId) then
		return true
	end
	if Engine.count(e) >= Engine.capacity(e) then
		return false
	end
	local from = seatOf[p.UserId]
	if from then
		local old = tables[from]
		if not old or old.engine.phase ~= "Waiting" then
			return false
		end
		Engine.remove(old.engine, p.UserId, now())
		seatOf[p.UserId] = nil
		Service.broadcast(old)
	end
	-- The second on a 1v1 pad stands beside the first, as a bot answering does.
	local offset = if Engine.count(e) > 0 and e.teamSize == 1 then 2 else 0
	character:PivotTo(Service.padSpot(t, offset))
	t.blocked[p.UserId] = nil
	if Engine.join(e, p.UserId, p.Name, p.DisplayName, now()) then
		seatOf[p.UserId] = e.id
		Service.broadcast(t)
		return true
	end
	return false
end

--- Switches table `t` to `teamSize` a side while it is free (waiting, nobody seated, no
--- search): the tutorial's backup (tutorial v2 4.12) plays game 1 as a 1v1 on a free team
--- table, then gives the table back its own mode (Placement.teamSizeOf). A fresh engine, as a
--- game's reset makes one (the same table object, so references stay good), and the pad's
--- mode, capacity and words follow. False when the table is not free.
function Service.setMode(t: any, teamSize: number): boolean
	local e = t.engine
	if e.teamSize == teamSize then
		return true
	end
	if
		e.phase ~= "Waiting"
		or Engine.count(e) > 0
		or e.search
		or t.search
		or e.fixed
		or t.pad == nil
	then
		return false
	end
	local fresh = Engine.new(e.id, teamSize, newSeed())
	fresh.epoch = e.epoch + 1
	fresh.revision = e.revision + 1
	table.clear(e)
	for key, value in fresh do
		e[key] = value
	end
	t.pad:SetAttribute("TeamSize", teamSize)
	t.pad:SetAttribute("Capacity", teamSize * 2)
	setText(t.modeText, Strings.Match.Mode:format(teamSize, teamSize))
	Service.broadcast(t)
	return true
end

--- This server's search (LocalSearch): a table of `teamSize` a side free for a match here,
--- the nearest to `near` (else the lowest id): waiting, nobody on or standing on its pad, no
--- search, not held for the tutorial nor in `skip` (tables already promised this round). Nil
--- while no more than `spare` such tables are free (they stay for new players).
function Service.freeTable(
	teamSize: number,
	near: Vector3?,
	skip: { [any]: boolean }?,
	spare: number?
): any?
	local best, bestGap, count = nil, math.huge, 0
	for id = 1, #tables do
		local t = tables[id]
		local e = t and t.engine
		if
			e
			and e.teamSize == teamSize
			and t.pad
			and e.phase == "Waiting"
			and Engine.count(e) == 0
			and not e.search
			and not t.search
			and t.reservedFor == nil
			and not (skip and skip[t])
			and not Service.standingOnPad(t)
		then
			count += 1
			local gap = if near then (t.pad.Position - near).Magnitude else id
			if gap < bestGap then
				best, bestGap = t, gap
			end
		end
	end
	return if count > (spare or 0) then best else nil
end

--- The players of table `t`'s waiting search, and when it began (server time); nil when it
--- has none.
function Service.waitingSearch(t: any): ({ Player }?, number?)
	local e = t.engine
	local search = t.search
	if arena or not search or not GlobalQueue.isWaiting(search) or t.searchCancelling then
		return nil, nil
	end
	if not e.search or e.search.found or e.phase ~= "Waiting" then
		return nil, nil
	end
	return playersOf(search.ticket.users), e.search.at
end

--- Whether a real player not seated here stands on table `t`'s pad (bots playing there get up
--- for them).
function Service.standingOnPad(t: any): boolean
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		if root and not Engine.seat(t.engine, p.UserId) and onPad(t, root, 0) then
			return true
		end
	end
	return false
end

--- Where a body stands on table `t`'s queue pad (a bot appearing to play).
function Service.padSpot(t: any, offset: number?): CFrame
	local cx, cy = Placement.queuePad(t.engine.teamSize)
	local wx, wy, wz =
		Placement.fromTableStuds(t.placement, cx + (offset or 0), cy, Q.RespawnHeight)
	local at = Vector3.new(wx, wy, wz)
	return CFrame.lookAt(at, Vector3.new(t.placement.x, wy, t.placement.z))
end

--- Build the tables and run them. `mode` "Arena" (ArenaService) stands up the one table of
--- Placement's layout with no queue pad; anything else is the lobby's sixteen.
function Service.start(parent: Instance, mode: string?)
	if started then
		return
	end
	started = true
	arena = mode == "Arena"
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
	-- One server-owned table per Config.Hub row, each playing its own mode.
	for id = 1, Placement.tableCount() do
		local p = Placement.forTable(id)
		assert(p, "Missing table placement")
		local t: any = {
			engine = Engine.new(id, Placement.teamSizeOf(id) or 1, newSeed()),
			placement = p,
			dwell = {},
			outside = {},
			blocked = {},
			sentRevision = 0,
		}
		t.engine.fixed = arena or nil
		tables[id] = t
		if not arena then
			buildPad(t, folder)
		end
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
		-- The global queue's Ults: On / Off is gone (designer, 2026-10-02): every search plays
		-- with ults on. The matchmaking bar (designer, 2026-10-07) has one choice, Play Global:
		-- the server sends the request itself (askForOpponent) and lobby tables play Classic,
		-- so a client's Request, Cancel or difficulty is refused.
		if
			payload.kind == "SetQueueUlts"
			or payload.kind == "SearchWithUlts"
			or payload.kind == "RequestOpponent"
			or payload.kind == "CancelRequest"
			or payload.kind == "SetDifficulty"
		then
			Net.get("ShotRejected"):FireClient(p, "ActionRejected")
			return
		end
		local hook = actionHooks[payload.kind]
		if hook then
			if payload.epoch ~= t.engine.epoch then
				return
			end
			Service.advance(t, now())
			local ok, taken = pcall(hook, t, p, payload)
			if not ok then
				warn("[8ball] action hook failed: " .. tostring(taken))
			end
			Service.broadcast(t)
			if not (ok and taken) then
				Net.get("ShotRejected"):FireClient(p, "ActionRejected")
			end
			return
		end
		if payload.kind == "GlobalSearch" or payload.kind == "CancelSearch" then
			if payload.epoch ~= t.engine.epoch then
				return
			end
			local ok = if payload.kind == "GlobalSearch"
				then startSearch(t, p)
				else stopSearch(t, p)
			Service.broadcast(t)
			if not ok then
				Net.get("ShotRejected"):FireClient(p, "ActionRejected")
			end
			return
		end
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
	Net.get("AnswerRequest").OnServerEvent:Connect(function(p, id, epoch)
		if Service.allow(p, "action") then
			answerRequest(p, id, epoch)
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
				-- Back on the queue pad, which the match fence takes in.
				local cx, cy = Placement.queuePad(t.engine.teamSize)
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
		autoAskedAt[p.UserId] = nil
		local id = seatOf[p.UserId]
		if id then
			-- A leaver's forfeit loss, while their save is still open (Ranking.departed).
			local ok, err = pcall(function(): any
				Ranking.departed(tables[id], p)
				return nil
			end)
			if not ok then
				warn("[8ball] Ranking.departed failed: " .. tostring(err))
			end
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
			-- Each table on its own guard: one table's error (a Time Stop resume settles and
			-- judges in here) never stops the tables after it.
			local ok, err = pcall(function()
				local time = now()
				poll(t, time)
				Service.advance(t, time)
				keepDifficulty(t)
				releaseMissing(t)
				if not arena then
					watchSearch(t)
				end
				Service.flush(t)
				if e.revision ~= t.sentRevision or snapshots >= M.SnapshotIntervalSeconds then
					Service.broadcast(t)
				else
					refresh(t)
				end
			end)
			if not ok then
				warn(("[8ball] table %d failed its poll: %s"):format(id, tostring(err)))
			end
		end
		if snapshots >= M.SnapshotIntervalSeconds then
			snapshots = 0
		end
	end)
end

return Service
