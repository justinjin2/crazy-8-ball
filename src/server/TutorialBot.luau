--!strict
-- TutorialBot: game 1's opponent, as a person (docs/prompts/TUTORIAL_V2_PROMPT.md 4.3, 4.5).
--
-- The tutorial bot (BotService.tutorialBot: a real look, a made-up name, a rank badge) joins
-- the server the moment a tutorial player does, appearing out of their view, and strolls round
-- the roof near the tables like any player (the designer, 2026-10-09: "he should just be
-- roaming around the server"). As the player heads for a table it walks over, timed to step
-- onto their pad 0.5-2 s after them (Tutorial/BotWalk, the plan's bot-arrival model). It walks
-- like a player: short stops, a path that sways, looks round (the body turns, as with
-- shift-lock), now and then a jump, and it faces the table as it steps on. A switch of table
-- re-routes it; a player who steps off finds it waiting by the table; a real person on their
-- pad (path R) sends it back to strolling. Everyone sees the same body, on the player list.
--
-- After game 1 it stays at the table, idle, until NEW RANK! is dismissed (the Rank step), then
-- says one casual line, walks a few steps away and leaves the game. It leaves quietly when its
-- player leaves. Anything that goes wrong falls back to seating it on the pad (GiveUpSeconds).
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local BotWalk = require(Shared.Tutorial.BotWalk)
local Tables = require(script.Parent.TableService)
local BotService = require(script.Parent.Bots.BotService)
local Body = require(script.Parent.Bots.Body)

local BOT = Config.Tutorial.Bot
local N = BOT.Natural
local G = Config.Tutorial.Games

local TutorialBot = {}

-- TutorialService (step, path, guard) and the table reserved for a player, from start.
local service: any = nil
local reservedOf: (Player) -> number? = function(_player: Player): number?
	return nil
end

type Turn = { from: number, to: number, t0: number, dur: number }

type Escort = {
	player: Player,
	bot: any?,
	loading: boolean,
	-- "Waiting" (no body yet) | "Roaming" (strolling round the roof) | "Out" (walking to or
	-- waiting by a table) | "Seated" | "Idle" (by the table after its game) | "Leaving"
	state: string,
	job: number, -- bumped to cancel the walk under way
	target: number?, -- the table it heads for
	walking: boolean, -- a walk to its table is under way
	holding: boolean, -- waiting by its table for the player
	heading: number?, -- the pad the player seems to head for, since headingSince
	headingSince: number,
	on: boolean, -- the player stands on the target's pad
	onTable: number?,
	onAt: number?, -- os.clock() the player was first seen on that pad
	eta: number, -- the player's seconds to the target's pad (0 on it)
	played: boolean, -- its game 1 began
	turn: Turn?,
	lockYaw: boolean,
	walkPoints: { Vector3 },
	walkIndex: number,
}

local escorts: { [Player]: Escort } = {}
local random = Random.new()

local function log(text: string)
	print("[8ball] TutorialBot: " .. text)
end

local function range(pair: { number }): number
	return pair[1] + random:NextNumber() * (pair[2] - pair[1])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- The yaw that faces flat direction `dir`.
local function yawOf(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function yawOfPart(part: BasePart): number
	return yawOf(part.CFrame.LookVector)
end

-- b - a, wrapped into (-pi, pi].
local function angleDiff(a: number, b: number): number
	local d = (b - a) % (2 * math.pi)
	return if d > math.pi then d - 2 * math.pi else d
end

local function modelOf(e: Escort): Model?
	return if e.bot then e.bot.model else nil
end

local function rootOf(e: Escort): BasePart?
	return Body.root(modelOf(e))
end

local function humOf(e: Escort): Humanoid?
	local model = modelOf(e)
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

local function playerRoot(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

---------------------------------------------------------------------------------------------
-- Turning the body (a look round, facing the table): the Heartbeat pass turns it
---------------------------------------------------------------------------------------------

local function turnTo(e: Escort, yaw: number, seconds: number)
	local root = rootOf(e)
	if not root then
		return
	end
	local from = yawOfPart(root)
	e.turn = {
		from = from,
		to = from + angleDiff(from, yaw),
		t0 = os.clock(),
		dur = math.max(seconds, 1e-3),
	}
	e.lockYaw = true
end

-- The body's turner: an AlignOrientation on its root, on only while it holds a facing (a
-- written CFrame would stop the Humanoid's walk).
local function turnerOf(e: Escort): AlignOrientation?
	local root = rootOf(e)
	local turner = if root then root:FindFirstChild("Turn") else nil
	return if turner and turner:IsA("AlignOrientation") then turner else nil
end

-- Lets the body face its walk again.
local function release(e: Escort)
	e.turn = nil
	e.lockYaw = false
	local turner = turnerOf(e)
	if turner then
		turner.Enabled = false
	end
	local hum = humOf(e)
	if hum then
		hum.AutoRotate = true
	end
end

local function applyTurns()
	for _, e in escorts do
		local turn = e.turn
		if e.lockYaw and turn then
			local hum, turner = humOf(e), turnerOf(e)
			if hum and turner then
				hum.AutoRotate = false
				local a = math.clamp((os.clock() - turn.t0) / turn.dur, 0, 1)
				a = a * a * (3 - 2 * a)
				turner.CFrame = CFrame.Angles(0, turn.from + (turn.to - turn.from) * a, 0)
				turner.Enabled = true
			end
		end
	end
end

-- Readies a new body to walk like a player: it never trips (a body kept anchored at a table
-- comes back "fallen down" otherwise), and gets its turner.
local function prepare(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = Body.root(model)
	if hum then
		hum.WalkSpeed = BOT.WalkSpeed
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	end
	if root and not root:FindFirstChild("Turn") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TurnAttachment"
		attachment.Parent = root
		local turner = Instance.new("AlignOrientation")
		turner.Name = "Turn"
		turner.Mode = Enum.OrientationAlignmentMode.OneAttachment
		turner.Attachment0 = attachment
		turner.RigidityEnabled = true -- follows the eased facing exactly
		turner.Enabled = false
		turner.Parent = root
	end
end

-- Standing, ready to walk (after its table let it go).
local function standUp(e: Escort)
	local hum = humOf(e)
	if hum then
		hum:ChangeState(Enum.HumanoidStateType.Running)
	end
end

---------------------------------------------------------------------------------------------
-- Tables and pads
---------------------------------------------------------------------------------------------

-- Table `t`'s pad on the floor (its world extents).
local function padOf(t: any): BotWalk.Pad?
	local pad = t.pad
	if not pad then
		return nil
	end
	local cf, size = pad.CFrame, pad.Size
	local function half(axis: string): number
		return math.abs((cf.RightVector :: any)[axis]) * size.X / 2
			+ math.abs((cf.UpVector :: any)[axis]) * size.Y / 2
			+ math.abs((cf.LookVector :: any)[axis]) * size.Z / 2
	end
	return { id = t.engine.id, x = cf.Position.X, z = cf.Position.Z, hx = half("X"), hz = half("Z") }
end

-- Whether a real person other than `player` sits at table `t`.
local function realOther(t: any, player: Player): boolean
	for _, s in t.engine.seats do
		if s.userId > 0 and s.userId ~= player.UserId then
			return true
		end
	end
	return false
end

-- Whether table `t` is one the bot can play `player` at: a waiting 1v1 table with a pad, no
-- search, not reserved for anyone else, no other real person.
local function open(t: any, player: Player): boolean
	local e = t.engine
	return e.teamSize == 1
		and e.phase == "Waiting"
		and t.pad ~= nil
		and not e.search
		and not t.search
		and (t.reservedFor == nil or t.reservedFor == player.UserId)
		and not realOther(t, player)
end

-- Where it stands on table `t`'s pad: SideStuds along the pad from the player, on the side it
-- comes from (`from`), or the other side when that end is too near; with nobody on the pad,
-- PadOffsetStuds from the middle at its own end. Kept inside the pad's ends.
local function spotOn(t: any, from: Vector3, player: Player): CFrame
	local centre = Tables.padSpot(t, 0)
	local axis = Tables.padSpot(t, 1).Position - centre.Position
	local scale = flat(axis).Magnitude
	if scale < 1e-6 then
		return centre
	end
	local dir = flat(axis).Unit
	local limit = (Config.Multiplayer.Queue.PadLengthStuds / 2 - BOT.PadEndStuds) / scale
	local function along(at: Vector3): number
		return flat(at - centre.Position):Dot(dir) / scale
	end
	local side = if along(from) < 0 then -1 else 1
	local root = playerRoot(player)
	local offset = side * BOT.PadOffsetStuds / scale
	if root and Tables.tableOf(player) == t.engine.id then
		local them = along(root.Position)
		local gap = BOT.SideStuds / scale
		offset = math.clamp(them + side * gap, -limit, limit)
		if math.abs(offset - them) * scale < BOT.ClearStuds then
			offset = math.clamp(them - side * gap, -limit, limit)
		end
	end
	return Tables.padSpot(t, offset)
end

-- A spot HoldStuds off `pad`'s edge on the side of `from`.
local function holdPoint(pad: BotWalk.Pad, from: Vector3): Vector3
	local d = Vector3.new(from.X - pad.x, 0, from.Z - pad.z)
	if d.Magnitude < 0.1 then
		d = Vector3.new(0, 0, 1)
	end
	local s = math.min(
		if math.abs(d.X) > 1e-6 then pad.hx / math.abs(d.X) else math.huge,
		if math.abs(d.Z) > 1e-6 then pad.hz / math.abs(d.Z) else math.huge
	)
	local edge = Vector3.new(pad.x, from.Y, pad.z) + d * s
	return edge + d.Unit * BOT.HoldStuds
end

-- Whether the player has been on the target's pad long enough, at a table rigged for them, for
-- it to step on.
local function onFor(e: Escort): number?
	return if e.onAt then os.clock() - e.onAt else nil
end

-- Whether the player stands on table `t`'s pad, not just crossing it (on its rectangle, slower
-- than SettledSpeed): a player walking over a pad on their way elsewhere joins it for a moment.
local function standing(player: Player, t: any): boolean
	local root = playerRoot(player)
	local pad = padOf(t)
	return root ~= nil
		and pad ~= nil
		and BotWalk.distanceToPad(pad, root.Position.X, root.Position.Z) == 0
		and flat(root.AssemblyLinearVelocity).Magnitude < BOT.SettledSpeed
end

local function ready(e: Escort, t: any): boolean
	local player = e.player
	local eng = t.engine
	return Tables.tableOf(player) == eng.id
		and eng.phase == "Waiting"
		and eng.tutorial ~= nil
		and eng.tutorial.player == player.UserId
		and not realOther(t, player)
		and BotWalk.mayStepOn(onFor(e))
		and standing(player, t)
end

---------------------------------------------------------------------------------------------
-- Walks
---------------------------------------------------------------------------------------------

local function length(points: { Vector3 }): number
	local n = 0
	for i = 2, #points do
		n += flat(points[i] - points[i - 1]).Magnitude
	end
	return n
end

-- The path from `from` to `to` round the tables (a straight line if none).
local function route(from: Vector3, to: Vector3): { Vector3 }
	local path = PathfindingService:CreatePath({
		AgentRadius = BOT.AgentRadius,
		AgentHeight = BOT.AgentHeight,
		AgentCanJump = false,
	})
	local ok = pcall(function()
		path:ComputeAsync(from, to)
	end)
	local points = {}
	if ok and path.Status == Enum.PathStatus.Success then
		for _, w in path:GetWaypoints() do
			table.insert(points, w.Position)
		end
	end
	if #points < 2 then
		points = { from, to }
	end
	return points
end

-- A path that is never perfectly straight: a gentle sideways sway (none at either end), the
-- start point dropped (it is where the body stands).
local function sway(points: { Vector3 }): { Vector3 }
	local out = {}
	local total = length(points)
	local phase = random:NextNumber() * 2 * math.pi
	local s = 0
	for i = 2, #points do
		s += flat(points[i] - points[i - 1]).Magnitude
		local p = points[i]
		if i < #points then
			local dir = flat(points[i + 1] - points[i - 1])
			if dir.Magnitude > 0.1 then
				local side = Vector3.new(-dir.Unit.Z, 0, dir.Unit.X)
				local fade = math.min(s, total - s, 4) / 4
				p += side * N.CurveStuds * fade * math.sin(
					phase + s / N.CurveWaveStuds * 2 * math.pi
				)
			end
		end
		table.insert(out, p)
	end
	return out
end

-- The bot's seconds to walk from where it stands to table `t`'s pad (round the tables).
local function secondsTo(e: Escort, t: any): number
	local root = rootOf(e)
	local pad = padOf(t)
	if not root or not pad then
		return math.huge
	end
	local studs = BotWalk.distanceToPad(pad, root.Position.X, root.Position.Z)
	return BotWalk.walkSeconds(studs * BOT.StraightFactor)
end

-- The roof's strolling spots: the aisles between the tables (beside them and at the crossings)
-- and the walkway in front of the first row (from Config.Hub.Tables). A spot with something
-- solid on it (a planter at a crossing) moves just beside it, or is left out.
local spots: { Vector3 } = {}

local function clear(at: Vector3): boolean
	local size = Vector3.new(BOT.AgentRadius * 2, BOT.AgentHeight, BOT.AgentRadius * 2)
	for _, part in workspace:GetPartBoundsInBox(CFrame.new(at), size, OverlapParams.new()) do
		local top = part.Position.Y + part.Size.Y / 2
		if part.CanCollide and top > BOT.RootHeight - 2 and part.CollisionGroup ~= "PoolFence" then
			return false
		end
	end
	return true
end

local function addSpot(at: Vector3)
	local step = BOT.SpotNudgeStuds
	for _, offset in
		{
			Vector3.zero,
			Vector3.new(step, 0, 0),
			Vector3.new(-step, 0, 0),
			Vector3.new(0, 0, step),
			Vector3.new(0, 0, -step),
		}
	do
		if clear(at + offset) then
			table.insert(spots, at + offset)
			return
		end
	end
end

local function buildSpots()
	local xs, zs = {}, {}
	for _, row in Config.Hub.Tables do
		if not table.find(xs, row.X) then
			table.insert(xs, row.X)
		end
		if not table.find(zs, row.Z) then
			table.insert(zs, row.Z)
		end
	end
	table.sort(xs)
	table.sort(zs)
	local ax, az = {}, {}
	for i = 1, #xs - 1 do
		table.insert(ax, (xs[i] + xs[i + 1]) / 2)
	end
	for i = 1, #zs - 1 do
		table.insert(az, (zs[i] + zs[i + 1]) / 2)
	end
	local front = zs[#zs] + (zs[#zs] - (az[#az] or zs[#zs])) + BOT.FrontStuds
	for _, x in ax do
		for _, z in az do
			addSpot(Vector3.new(x, BOT.RootHeight, z))
		end
		for _, z in zs do
			addSpot(Vector3.new(x, BOT.RootHeight, z))
		end
		addSpot(Vector3.new(x, BOT.RootHeight, front))
	end
	for _, x in xs do
		addSpot(Vector3.new(x, BOT.RootHeight, front))
	end
end

-- The pads the player will most likely walk to: the open 1v1 pads within LikelyStuds of them
-- (at least their arrow table's).
local function likelyPads(e: Escort): { BotWalk.Pad }
	local out = {}
	local root = playerRoot(e.player)
	for _, t in Tables.all() do
		if open(t, e.player) then
			local pad = padOf(t)
			local near = root
				and pad
				and BotWalk.distanceToPad(pad, root.Position.X, root.Position.Z)
					<= BOT.LikelyStuds
			if pad and (near or t.engine.id == reservedOf(e.player)) then
				table.insert(out, pad)
			end
		end
	end
	return out
end

-- A strolling spot from which it reaches every likely pad in time (RoamReachStuds), not where
-- it stands now; the most central one when none is near enough. A little jitter on top.
local function roamSpot(e: Escort): Vector3?
	local root = rootOf(e)
	local pads = likelyPads(e)
	if not root or #pads == 0 then
		return nil
	end
	local near: { Vector3 } = {}
	local central: Vector3? = nil
	local centralFar = math.huge
	for _, spot in spots do
		local far = 0
		for _, pad in pads do
			far = math.max(far, BotWalk.distanceToPad(pad, spot.X, spot.Z))
		end
		local here = flat(spot - root.Position).Magnitude <= BOT.RoamJitterStuds * 2
		if far <= BOT.RoamReachStuds and not here then
			table.insert(near, spot)
		end
		if far < centralFar then
			central, centralFar = spot, far
		end
	end
	local spot: Vector3? = if #near > 0 then near[random:NextInteger(1, #near)] else central
	if not spot then
		return nil
	end
	local angle = random:NextNumber() * 2 * math.pi
	return spot
		+ Vector3.new(math.cos(angle), 0, math.sin(angle))
			* BOT.RoamJitterStuds
			* random:NextNumber()
end

-- Where its body is made when it joins: a strolling spot at least EntryMinStuds from the player
-- and as far off where they face as there is (never seen appearing), facing its first stroll.
local function entryOf(player: Player): CFrame
	local root = playerRoot(player)
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local from = if root then root.Position elseif spawn then spawn.Position else Vector3.zero
	local facing = if root then flat(root.CFrame.LookVector) else Vector3.new(0, 0, -1)
	facing = if facing.Magnitude > 0.1 then facing.Unit else Vector3.new(0, 0, -1)
	local best, bestScore = nil, -math.huge
	for _, spot in spots do
		local d = flat(spot - from)
		if d.Magnitude >= BOT.EntryMinStuds then
			local off = math.deg(math.acos(math.clamp(d.Unit:Dot(facing), -1, 1)))
			-- Any spot off their view will do; nearer ones (a short stroll in) are better.
			local score = math.min(off, BOT.EntryOffDegrees) * 10 - d.Magnitude
			if score > bestScore then
				best, bestScore = spot, score
			end
		end
	end
	local at = best or (from + Vector3.new(0, 0, BOT.EntryMinStuds))
	return CFrame.lookAt(at, Vector3.new(from.X, at.Y, from.Z))
end

-- The walk's studs left from the body.
local function remaining(e: Escort): number
	local root = rootOf(e)
	local points = e.walkPoints
	if not root or e.walkIndex > #points then
		return 0
	end
	local n = flat(points[e.walkIndex] - root.Position).Magnitude
	for i = e.walkIndex + 1, #points do
		n += flat(points[i] - points[i - 1]).Magnitude
	end
	return n
end

-- A look round while walking: the body turns aside a moment, then faces its walk again.
local function lookRound(e: Escort, job: number)
	local root = rootOf(e)
	if not root then
		return
	end
	local v = flat(root.AssemblyLinearVelocity)
	local base = if v.Magnitude > 1 then yawOf(v) else yawOfPart(root)
	local sign = if random:NextNumber() < 0.5 then -1 else 1
	turnTo(e, base + sign * math.rad(range(N.LookDegrees)), N.TurnSeconds)
	task.delay(N.TurnSeconds + range(N.LookSeconds), function()
		if e.job == job and e.lockYaw then
			release(e)
		end
	end)
end

type WalkOptions = {
	pace: boolean?, -- keep time with the player (BotWalk.lateness)
	hold: ((Vector3) -> boolean)?, -- stop here and report "Hold" once this says so
	deadline: number?, -- os.clock() to give up by ("Done")
	quiet: boolean?, -- no stops, looks or jumps (a step aside, walking off)
	face: Vector3?, -- turns to face this in its last FaceStuds
	replan: boolean?, -- stops ("Replan") when the player steps on or off the pad
}

-- Walks the body along `points` like a player; yields. "Done" at the end (or the deadline),
-- "Replan" when the player stepped on or off (o.replan),
-- "Hold" when `hold` said so, "Stuck" when it stopped moving, "Cancel" when its job changed.
local function walk(e: Escort, job: number, points: { Vector3 }, o: WalkOptions): string
	local hum, root = humOf(e), rootOf(e)
	if not hum or not root then
		return "Cancel"
	end
	e.walkPoints, e.walkIndex = points, 1
	local now = os.clock()
	local pauseAt = now + range(N.PauseEverySeconds)
	local lookAt = now - math.log(1 - random:NextNumber()) / N.LookChancePerSecond
	local studs = length(points)
	-- The odd jump: once, with 40-70% of the walk left, never close to the end.
	local jumpLeft: number? = nil
	if not o.quiet and studs >= N.JumpMinStuds and random:NextNumber() < N.JumpChance then
		local left = studs * (0.4 + 0.3 * random:NextNumber())
		jumpLeft = if left >= N.JumpClearStuds then left else nil
	end
	local arriving = false -- turning to face `o.face` (no more looks or jumps)
	local wasOn = e.on
	local lastPos, lastMoveAt = root.Position, now
	local issuedAt = -math.huge
	while e.walkIndex <= #points do
		if e.job ~= job or e.bot == nil or e.bot.gone or root.Parent == nil then
			return "Cancel"
		end
		now = os.clock()
		if o.deadline and now >= o.deadline then
			hum:MoveTo(root.Position)
			return "Done"
		end
		if o.hold and o.hold(root.Position) then
			hum:MoveTo(root.Position)
			return "Hold"
		end
		if o.replan and e.on ~= wasOn then
			return "Replan" -- its spot depends on where the player stands
		end
		local point = points[e.walkIndex]
		if flat(point - root.Position).Magnitude < BOT.ArriveStuds then
			e.walkIndex += 1
			issuedAt = -math.huge
			continue
		end
		-- A short stop now and then (skipped while late), and a stop while early.
		local stop = 0
		if not o.quiet then
			local early = false
			if o.pace then
				local late =
					BotWalk.lateness(BotWalk.walkSeconds(remaining(e)), e.eta, onFor(e) or 0)
				early = BotWalk.shouldPause(late)
				if now >= pauseAt then
					pauseAt = now + range(N.PauseEverySeconds)
					if late < 0 then
						stop = range(N.PauseSeconds)
					end
				end
			elseif now >= pauseAt then
				pauseAt = now + range(N.PauseEverySeconds)
				stop = range(N.PauseSeconds)
			end
			if early then
				stop = math.max(stop, N.EarlyPauseSeconds)
			end
		end
		if stop > 0 then
			hum:MoveTo(root.Position)
			task.wait(stop)
			issuedAt = -math.huge
			lastPos, lastMoveAt = root.Position, os.clock()
			continue
		end
		-- MoveTo gives up after 8 s, and a jump can drop it: issue it again often, at once
		-- when the body stands still.
		local speed = flat(root.AssemblyLinearVelocity).Magnitude
		if now - issuedAt > 1 or (speed < 2 and now - issuedAt > 0.25) then
			hum:MoveTo(point)
			issuedAt = now
		end
		local left = remaining(e)
		if o.face and not arriving and left <= N.FaceStuds then
			-- Arriving: it turns to the table as it takes its last steps.
			arriving = true
			turnTo(e, yawOf(flat(o.face - root.Position)), N.TurnSeconds)
		end
		if not o.quiet and not arriving then
			if now >= lookAt and left > N.FaceStuds * 2 then
				lookAt = now - math.log(1 - random:NextNumber()) / N.LookChancePerSecond
				lookRound(e, job)
			end
			if jumpLeft and left <= jumpLeft then
				jumpLeft = nil
				hum.Jump = true
			end
		end
		if (root.Position - lastPos).Magnitude > BOT.StuckStuds then
			lastPos, lastMoveAt = root.Position, now
		elseif now - lastMoveAt > BOT.StuckSeconds then
			hum:MoveTo(root.Position)
			return "Stuck"
		end
		task.wait(0.05)
	end
	return "Done"
end

-- One fidget while it waits: faces the player, looks round, shifts its feet, or (rarely) jumps.
local function fidget(e: Escort, job: number)
	local root, hum = rootOf(e), humOf(e)
	if not root or not hum or root.Anchored then
		return
	end
	local r = random:NextNumber()
	local them = playerRoot(e.player)
	if r < N.FidgetJumpChance then
		hum.Jump = true
	elseif r < 0.45 and them then
		turnTo(e, yawOf(flat(them.Position - root.Position)), N.TurnSeconds * 2)
	elseif r < 0.75 then
		local base = yawOfPart(root)
		local sign = if random:NextNumber() < 0.5 then -1 else 1
		turnTo(e, base + sign * math.rad(range(N.LookDegrees) * 1.4), N.TurnSeconds * 2)
		task.delay(N.TurnSeconds * 2 + range(N.LookSeconds), function()
			if e.job == job and e.lockYaw then
				turnTo(e, base, N.TurnSeconds * 2)
			end
		end)
	else
		release(e)
		local angle = random:NextNumber() * 2 * math.pi
		local step = Vector3.new(math.cos(angle), 0, math.sin(angle)) * N.FidgetStepStuds
		hum:MoveTo(root.Position + step)
	end
end

-- Waits where it is like a person until `done()` says so (true) or its job changes (false).
local function idle(e: Escort, job: number, done: () -> boolean): boolean
	local fidgetAt = os.clock() + range(N.FidgetEverySeconds)
	while e.job == job and e.bot and not e.bot.gone do
		if done() then
			return true
		end
		if os.clock() >= fidgetAt then
			fidgetAt = os.clock() + range(N.FidgetEverySeconds)
			fidget(e, job)
		end
		task.wait(0.1)
	end
	return false
end

---------------------------------------------------------------------------------------------
-- Coming, going
---------------------------------------------------------------------------------------------

local function newJob(e: Escort): number
	e.job += 1
	release(e)
	return e.job
end

-- Runs `fn` as the escort's own thread; an error seats the bot the plain way (or lets it go).
local fallbackSeat: (Escort, string) -> ()
local function run(e: Escort, what: string, fn: () -> ())
	task.spawn(function()
		local ok, err = pcall(fn :: any)
		if not ok then
			warn(
				("[8ball] TutorialBot: %s failed for %s: %s"):format(
					what,
					e.player.Name,
					tostring(err)
				)
			)
			service.logError(e.player, "Bot" .. what)
			fallbackSeat(e, what)
		end
	end)
end

-- Gone at once, as a player leaving the game.
local function dismiss(e: Escort)
	local bot = e.bot
	e.bot = nil
	e.state = "Waiting"
	newJob(e)
	if bot then
		BotService.remove(bot, "Vanish")
	end
end

-- Faces the table, then sits where it stands (BotService.seat anchors it right there).
local function stepOn(e: Escort, job: number, t: any): boolean
	local root = rootOf(e)
	if not root then
		return false
	end
	local centre = Vector3.new(t.placement.x, root.Position.Y, t.placement.z)
	local yaw = yawOf(flat(centre - root.Position))
	if math.abs(angleDiff(yawOfPart(root), yaw)) > math.rad(N.FacedDegrees) then
		turnTo(e, yaw, N.TurnSeconds)
		task.wait(N.TurnSeconds)
	end
	if e.job ~= job or not ready(e, t) then
		return false
	end
	release(e)
	local at = CFrame.new(root.Position) * CFrame.Angles(0, yaw, 0)
	if BotService.seat(e.bot :: any, t, { at = at, breakFor = e.player.UserId }) then
		e.state = "Seated"
		log(
			("%s's bot stepped on at table %d, %.2f s after them"):format(
				e.player.Name,
				t.engine.id,
				onFor(e) or -1
			)
		)
		return true
	end
	return false
end

-- Walks to its target's pad, keeping time with the player, and steps on. Re-plans after a
-- stop or a block; waits by the table while the player is off the pad. Yields.
local function approach(e: Escort, job: number)
	local stuck = 0
	while e.job == job do
		local t = if e.target then Tables.get(e.target) else nil
		local root = rootOf(e)
		local pad = if t then padOf(t) else nil
		if t == nil or root == nil or pad == nil then
			return
		end
		local p: BotWalk.Pad = pad
		local spot = spotOn(t, root.Position, e.player)
		local result = walk(e, job, sway(route(root.Position, spot.Position)), {
			pace = true,
			replan = true,
			face = Vector3.new(t.placement.x, root.Position.Y, t.placement.z),
			hold = function(at: Vector3): boolean
				return not e.on and BotWalk.distanceToPad(p, at.X, at.Z) <= BOT.HoldStuds
			end,
		})
		if result == "Cancel" then
			return
		elseif result == "Replan" then
			continue -- a new spot from here
		elseif result == "Stuck" then
			stuck += 1
			if stuck >= 3 then
				return -- GiveUpSeconds seats it if the player is waiting
			end
		elseif result == "Hold" then
			e.holding = true
			idle(e, job, function(): boolean
				return e.on
			end)
			e.holding = false
		else
			-- On its spot: steps on once the player has been on a moment and the table is
			-- rigged; if they step off, it steps off too and waits by the table.
			local offSince: number? = nil
			local ok = idle(e, job, function(): boolean
				if ready(e, t) then
					return true
				end
				if e.on then
					offSince = nil
				else
					offSince = offSince or os.clock()
				end
				return offSince ~= nil and os.clock() - offSince > 1
			end)
			if not ok then
				return
			end
			if ready(e, t) then
				if stepOn(e, job, t) then
					return
				end
			else
				local back =
					holdPoint(p, root.Position + (root.Position - Vector3.new(p.x, 0, p.z)))
				walk(e, job, { back }, { quiet = true })
			end
		end
	end
end

-- Heads for table `t`'s pad (the player is going there) and steps on.
local function goOut(e: Escort, t: any)
	local job = newJob(e)
	e.state = "Out"
	e.target = t.engine.id
	e.holding = false
	e.walking = true
	log(("%s's bot heads for table %d"):format(e.player.Name, t.engine.id))
	run(e, "Out", function()
		standUp(e)
		approach(e, job)
		if e.job == job then
			e.walking = false
		end
	end)
end

-- Heads for table `t` instead (the player switched tables), or plans its walk again.
local function retarget(e: Escort, t: any)
	local job = newJob(e)
	e.target = t.engine.id
	e.holding = false
	e.walking = true
	log(("%s's bot turns for table %d"):format(e.player.Name, t.engine.id))
	run(e, "Retarget", function()
		approach(e, job)
		if e.job == job then
			e.walking = false
		end
	end)
end

-- Strolls round the roof near the player's likely table: a walk to a spot, a while standing
-- about there, again (before game 1, after a fair game 1 began without it, after a lost one).
local function roam(e: Escort)
	local job = newJob(e)
	e.state = "Roaming"
	e.target = nil
	e.holding = false
	e.walking = false
	run(e, "Roam", function()
		local bot = e.bot
		if bot and bot.t then
			BotService.unseat(bot)
		end
		standUp(e)
		while e.job == job do
			local root = rootOf(e)
			local spot = roamSpot(e)
			if root and spot then
				walk(e, job, sway(route(root.Position, spot)), {})
			end
			local until_ = os.clock() + range(BOT.RoamPauseSeconds)
			idle(e, job, function(): boolean
				return os.clock() >= until_
			end)
		end
	end)
end

-- Leaves the game: one casual line (unless `quiet`), a few steps away, gone.
local function leave(e: Escort, quiet: boolean)
	if e.state == "Leaving" then
		return
	end
	local bot = e.bot
	if bot == nil or modelOf(e) == nil then
		dismiss(e)
		return
	end
	local job = newJob(e)
	e.state = "Leaving"
	run(e, "Leave", function()
		if not quiet then
			local lines = Strings.Tutorial.BotLines
			BotService.say(bot, lines[random:NextInteger(1, #lines)])
			task.wait(BOT.LineSeconds)
		end
		if bot.t then
			BotService.unseat(bot)
		end
		standUp(e)
		local root = rootOf(e)
		if root and e.job == job then
			local them = playerRoot(e.player)
			local away = if them then flat(root.Position - them.Position) else Vector3.zero
			if away.Magnitude < 0.5 then
				away = flat(root.CFrame.LookVector)
			end
			local turned = CFrame.Angles(0, math.rad(random:NextNumber() * 60 - 30), 0) * away.Unit
			local to = root.Position + turned * range(BOT.LeaveStuds)
			walk(e, job, sway(route(root.Position, to)), {
				deadline = os.clock() + BOT.LeaveSeconds,
				quiet = true,
			})
		end
		if e.bot == bot then
			e.bot = nil
		end
		BotService.remove(bot, "Vanish")
		log(("%s's bot left"):format(e.player.Name))
	end)
end

-- Stands by its table after its game, fidgeting, until it leaves.
local function stayIdle(e: Escort)
	local job = newJob(e)
	e.state = "Idle"
	standUp(e)
	run(e, "Idle", function()
		idle(e, job, function(): boolean
			return false
		end)
	end)
end

-- The last resort: seats it on the player's pad the plain way (after GiveUpSeconds, or an
-- error in a walk).
fallbackSeat = function(e: Escort, why: string)
	local bot = e.bot
	if bot == nil or bot.gone or bot.t or e.state == "Leaving" then
		return
	end
	local id = Tables.tableOf(e.player)
	local t = if id then Tables.get(id) else nil
	if
		t == nil
		or not open(t, e.player)
		or t.engine.tutorial == nil
		or not standing(e.player, t)
	then
		return
	end
	newJob(e)
	if BotService.seat(bot, t, { breakFor = e.player.UserId }) then
		e.state = "Seated"
		warn(("[8ball] TutorialBot: %s's bot was seated directly (%s)"):format(e.player.Name, why))
	end
end

-- Its table let it go (the game's result reset the pad): by the table it stays, or back to
-- strolling when the player is at the arrow again (a lost game 1).
local function onFreed(e: Escort, bot: any)
	if e.bot ~= bot or e.state == "Leaving" then
		return
	end
	local step = service.step(e.player)
	if step == "Arrow" or step == "Pad" then
		roam(e)
	else
		stayIdle(e)
	end
end

-- Its look when Roblox gave none (a plain starter look).
local function plainLook(): any
	local d = Instance.new("HumanoidDescription")
	local look = BOT.PlainLook
	local skin = Color3.fromRGB(look.Skin[1], look.Skin[2], look.Skin[3])
	d.HeadColor, d.LeftArmColor, d.RightArmColor = skin, skin, skin
	d.TorsoColor = Color3.fromRGB(look.Torso[1], look.Torso[2], look.Torso[3])
	local legs = Color3.fromRGB(look.Legs[1], look.Legs[2], look.Legs[3])
	d.LeftLegColor, d.RightLegColor = legs, legs
	return { description = d }
end

-- Makes the escort's bot (a real look; a plain one if Roblox answers nothing): it joins out of
-- the player's view and starts strolling. `loading` holds until its body is built (that yields
-- too), so only one is ever made at a time; a failed try is tried again on a later tick.
local function make(e: Escort)
	e.loading = true
	task.spawn(function()
		local ok, err = pcall(
			(
					function()
						local bot = nil
						for _ = 1, G.BotTries do
							bot = BotService.tutorialBot()
							if bot then
								break
							end
							task.wait(G.BotRetrySeconds)
						end
						bot = bot or BotService.tutorialBot(plainLook())
						if bot == nil then
							return
						end
						if escorts[e.player] ~= e or e.player.Parent == nil then
							BotService.remove(bot, "Vanish")
							return
						end
						if not BotService.stand(bot, entryOf(e.player)) then
							BotService.remove(bot, "Vanish")
							return
						end
						if escorts[e.player] ~= e or e.player.Parent == nil then
							BotService.remove(bot, "Vanish") -- they left while it loaded
							return
						end
						bot.freed = function(b: any)
							local fine, why = pcall(onFreed :: any, e, b)
							if not fine then
								warn("[8ball] TutorialBot: freed failed: " .. tostring(why))
								service.logError(e.player, "BotFreed")
							end
						end
						if bot.model then
							prepare(bot.model)
						end
						e.bot = bot
						e.state = "Waiting"
						log(("%s's bot %s joined the server"):format(e.player.Name, bot.name))
						roam(e)
					end
				) :: any
		)
		e.loading = false
		if not ok then
			warn("[8ball] TutorialBot: making a bot failed: " .. tostring(err))
			service.logError(e.player, "BotMake")
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Following the player
---------------------------------------------------------------------------------------------

-- At the arrow or on a pad: which table the player is going to, and when the bot sets off.
local function follow(e: Escort)
	local player = e.player
	local root = playerRoot(player)
	if not root then
		return
	end
	local now = os.clock()
	local seatedId = Tables.tableOf(player)
	local seatedAt = if seatedId then Tables.get(seatedId) else nil
	local t, eta, on, moving = nil, 0, false, false
	if seatedAt and seatedAt.engine.teamSize == 1 then
		if not open(seatedAt, player) then
			-- A real person is there, or their game began without it (path R): it strolls on.
			e.onTable, e.onAt, e.on = nil, nil, false
			if e.state == "Out" then
				roam(e)
			end
			return
		end
		t, on = seatedAt, true
	else
		local pads, byId = {}, {}
		for _, candidate in Tables.all() do
			if open(candidate, player) then
				local pad = padOf(candidate)
				if pad then
					table.insert(pads, pad)
					byId[pad.id] = pad
				end
			end
		end
		local v = root.AssemblyLinearVelocity
		local id = BotWalk.heading(pads, root.Position.X, root.Position.Z, v.X, v.Z)
		if id ~= e.heading then
			e.heading, e.headingSince = id, now
		end
		-- Strolling, it takes the freshest guess; on its way to a table, a new heading must hold
		-- a moment, and the player be near that pad or far enough that it must leave now to be
		-- in time (a wander is no switch).
		local settled = false
		local headed = if id then byId[id] else nil
		if id ~= nil and headed ~= nil then
			if e.state ~= "Out" then
				settled = true
			elseif now - e.headingSince >= BOT.RetargetSeconds then
				local theirs = BotWalk.eta(
					BotWalk.distanceToPad(headed, root.Position.X, root.Position.Z),
					true
				)
				local candidate = Tables.get(id)
				settled = theirs <= BOT.RetargetEtaSeconds
					or candidate ~= nil and BotWalk.shouldGo(secondsTo(e, candidate), theirs)
			end
		end
		local chosen = if settled then id else e.target or reservedOf(player)
		t = if chosen then Tables.get(chosen) else nil
		if t == nil or not open(t, player) then
			return
		end
		local pad = padOf(t)
		if pad == nil then
			return
		end
		moving = flat(v).Magnitude >= BOT.HeadingSpeed
		eta = BotWalk.eta(BotWalk.distanceToPad(pad, root.Position.X, root.Position.Z), moving)
	end
	if on then
		if e.onTable ~= t.engine.id then
			e.onTable, e.onAt = t.engine.id, now
		end
	else
		e.onTable, e.onAt = nil, nil
	end
	e.on, e.eta = on, eta
	if e.state == "Roaming" then
		-- Never while they stand about (looking round at the spawn): it strolls on.
		if on or (moving and BotWalk.shouldGo(secondsTo(e, t), eta)) then
			goOut(e, t)
		end
	elseif e.state == "Out" and e.target ~= t.engine.id then
		-- Waiting by its table, it moves only when the player steps onto another pad.
		if on or not e.holding then
			retarget(e, t)
		end
	elseif e.state == "Out" and not e.walking then
		retarget(e, t) -- its walk gave up (blocked): it plans again from where it stands
	end
	if on and e.onAt and now - e.onAt > BOT.GiveUpSeconds and e.state ~= "Seated" then
		fallbackSeat(e, "late")
	end
end

local function update(e: Escort)
	local player = e.player
	local step = service.step(player)
	if e.bot and e.bot.gone then
		-- Taken away elsewhere (a QA command): a new one is made if still needed.
		e.bot = nil
		e.state = "Waiting"
		newJob(e)
	end
	local bot = e.bot
	if step == "Arrow" or step == "Pad" then
		if bot == nil then
			if not e.loading then
				make(e)
			end
		elseif e.state == "Roaming" or e.state == "Out" then
			follow(e)
		elseif
			e.state == "Seated"
			and bot.t
			and bot.t.engine.phase == "Waiting"
			and Tables.tableOf(player) ~= bot.t.engine.id
		then
			roam(e) -- the player stepped off before the game began: it gets up and strolls
		end
	elseif step == "Game1" then
		-- Path R: nobody needs it; one on its way strolls on.
		if bot and e.state == "Out" then
			roam(e)
		elseif bot and e.state == "Seated" and bot.t and bot.t.engine.phase ~= "Waiting" then
			e.played = true -- its game began (a skip before that leaves it quiet)
		end
	elseif bot == nil then
		if not e.loading then
			escorts[player] = nil
		end
	elseif e.state == "Roaming" or e.state == "Out" or e.state == "Waiting" then
		leave(e, true) -- it never played them (path R, a skip): it just leaves the server
	elseif step ~= "Result" and e.state ~= "Leaving" then
		-- NEW RANK! is dismissed (or the tutorial is over): it leaves once its game is.
		local live = bot.t and bot.t.engine.phase ~= "Result" and bot.t.engine.phase ~= "Waiting"
		if not live then
			leave(e, not e.played)
		end
	end
end

local function drop(player: Player)
	local e = escorts[player]
	escorts[player] = nil
	if e then
		leave(e, true)
	end
end

--- The player is on a pad alone at their rigged table: their bot is coming (made now if it is
--- not yet). False when there is no bot and none is being made.
function TutorialBot.come(player: Player): boolean
	local e = escorts[player]
	return e ~= nil and (e.bot ~= nil or e.loading)
end

--- Starts the tutorial bots: timing every tutorial player's bot. `tutorial` is TutorialService
--- (step, path, guard); `reserved(player)` the table reserved for them.
function TutorialBot.start(tutorial: any, reserved: (Player) -> number?)
	if Tables.arenaTable() ~= nil then
		return -- an arena has no pads: the tutorial's tables are a lobby's
	end
	service = tutorial
	reservedOf = reserved
	buildSpots()
	local since = 0
	RunService.Heartbeat:Connect(function(dt: number)
		applyTurns()
		since += dt
		if since < BOT.TickSeconds then
			return
		end
		since = 0
		for _, player in Players:GetPlayers() do
			service.guard(player, "Bot", function()
				local e = escorts[player]
				if e == nil then
					local step = service.step(player)
					if step ~= "Arrow" and step ~= "Pad" then
						return
					end
					e = {
						player = player,
						bot = nil,
						loading = false,
						state = "Waiting",
						job = 0,
						target = nil,
						walking = false,
						holding = false,
						heading = nil,
						headingSince = 0,
						on = false,
						onTable = nil,
						onAt = nil,
						eta = math.huge,
						played = false,
						turn = nil,
						lockYaw = false,
						walkPoints = {},
						walkIndex = 1,
					}
					escorts[player] = e
				end
				update(e :: Escort)
			end)
		end
	end)
	Players.PlayerRemoving:Connect(drop)
end

--- QA (Studio): the escort's state for `player`.
function TutorialBot.state(player: Player): any
	local e = escorts[player]
	if e == nil then
		return nil
	end
	local root = rootOf(e)
	return {
		state = e.state,
		target = e.target,
		on = e.on,
		onFor = onFor(e),
		eta = e.eta,
		holding = e.holding,
		name = if e.bot then e.bot.name else nil,
		at = if root then root.Position else nil,
	}
end

return TutorialBot
