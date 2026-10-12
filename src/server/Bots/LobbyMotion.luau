--!strict
-- LobbyMotion: a lobby bot's body moving like a player (designer, 2026-10-12: "like the
-- tutorial bots"), the tutorial bot's walk (src/server/TutorialBot.luau) for the lobby bots
-- (Bots/LobbyBots): a path round the tables that sways a little, short stops, looks round (the
-- body turns, shift-lock style), now and then a hop; standing about it fidgets (a turn, a step,
-- a look, rarely a hop) and may turn to face someone. It never sits: the Seated state is off
-- (a bot sat on a map seat and floated off with it when it walked). Numbers: Config.Tutorial
-- .Bot (its walk, Natural) and Config.Bots.Lobby.
local PathfindingService = game:GetService("PathfindingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Body = require(script.Parent.Body)

local BOT = Config.Tutorial.Bot
local N = BOT.Natural

local LobbyMotion = {}

type Turn = { from: number, to: number, t0: number, dur: number }

export type Mover = {
	bot: any,
	job: number, -- bumped to cancel what the body is doing
	turn: Turn?,
	lockYaw: boolean,
	points: { Vector3 },
	index: number,
}

local movers: { [Mover]: boolean } = {}
local random = Random.new()

local function range(pair: { number }): number
	return pair[1] + (pair[2] - pair[1]) * random:NextNumber()
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function yawOf(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function yawOfPart(part: BasePart): number
	return yawOf(part.CFrame.LookVector)
end

local function angleDiff(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

local function rootOf(m: Mover): BasePart?
	return Body.root(m.bot.model)
end

local function humOf(m: Mover): Humanoid?
	local model = m.bot.model
	return if model then model:FindFirstChildOfClass("Humanoid") else nil
end

local function turnerOf(m: Mover): AlignOrientation?
	local root = rootOf(m)
	local turner = if root then root:FindFirstChild("Turn") else nil
	return if turner and turner:IsA("AlignOrientation") then turner else nil
end

--- Readies a body to walk like a player: a player's speed, it never trips or ragdolls, never
--- sits (a map seat it walks over would carry it off), and gets its turner.
function LobbyMotion.prepare(model: Model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = Body.root(model)
	if hum then
		hum.WalkSpeed = BOT.WalkSpeed
		hum.Sit = false
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	end
	if root and not root:FindFirstChild("Turn") then
		local attachment = Instance.new("Attachment")
		attachment.Name = "TurnAttachment"
		attachment.Parent = root
		local turner = Instance.new("AlignOrientation")
		turner.Name = "Turn"
		turner.Mode = Enum.OrientationAlignmentMode.OneAttachment
		turner.Attachment0 = attachment
		turner.RigidityEnabled = true
		turner.Enabled = false
		turner.Parent = root
	end
end

--- A mover for `bot` (its body made by BotService.stand).
function LobbyMotion.new(bot: any): Mover
	local m: Mover = { bot = bot, job = 0, turn = nil, lockYaw = false, points = {}, index = 1 }
	movers[m] = true
	return m
end

--- Forgets `m` (its bot is gone).
function LobbyMotion.forget(m: Mover)
	m.job += 1
	movers[m] = nil
end

-- Lets the body face its walk again.
local function release(m: Mover)
	m.turn = nil
	m.lockYaw = false
	local turner = turnerOf(m)
	if turner then
		turner.Enabled = false
	end
	local hum = humOf(m)
	if hum then
		hum.AutoRotate = true
	end
end

--- Cancels what the body is doing (a walk, a wait) and returns the new job's number.
function LobbyMotion.cancel(m: Mover): number
	m.job += 1
	release(m)
	local hum, root = humOf(m), rootOf(m)
	if hum and root and not root.Anchored then
		hum:MoveTo(root.Position)
	end
	return m.job
end

--- Turns the body to `yaw` over `seconds` (held until the next walk or release).
local function turnTo(m: Mover, yaw: number, seconds: number)
	local root = rootOf(m)
	if not root then
		return
	end
	local from = yawOfPart(root)
	m.turn = {
		from = from,
		to = from + angleDiff(from, yaw),
		t0 = os.clock(),
		dur = math.max(seconds, 1e-3),
	}
	m.lockYaw = true
end

--- Turns the body to face `at`.
function LobbyMotion.face(m: Mover, at: Vector3)
	local root = rootOf(m)
	if root and not root.Anchored then
		turnTo(m, yawOf(flat(at - root.Position)), N.TurnSeconds * 2)
	end
end

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

-- The walk's studs left from the body.
local function remaining(m: Mover, root: BasePart): number
	local points = m.points
	if m.index > #points then
		return 0
	end
	local n = flat(points[m.index] - root.Position).Magnitude
	for i = m.index + 1, #points do
		n += flat(points[i] - points[i - 1]).Magnitude
	end
	return n
end

-- A look round while walking: the body turns aside a moment, then faces its walk again.
local function lookRound(m: Mover, job: number, root: BasePart)
	local v = flat(root.AssemblyLinearVelocity)
	local base = if v.Magnitude > 1 then yawOf(v) else yawOfPart(root)
	local sign = if random:NextNumber() < 0.5 then -1 else 1
	turnTo(m, base + sign * math.rad(range(N.LookDegrees)), N.TurnSeconds)
	task.delay(N.TurnSeconds + range(N.LookSeconds), function()
		if m.job == job and m.lockYaw then
			release(m)
		end
	end)
end

export type WalkOptions = {
	deadline: number?, -- os.clock() to give up by
	quiet: boolean?, -- no stops, looks or hops (walking away, hurrying to a pad)
	face: Vector3?, -- turns to face this in its last FaceStuds
	stop: (() -> boolean)?, -- checked as it walks: true stops it ("Stop")
}

--- Walks the body to `to` like a player (job `job`; yields): "Done" there, "Late" past the
--- deadline, "Stop" when `o.stop` said so, "Stuck" when it stopped moving, "Cancel" when the
--- job changed or the body is gone.
function LobbyMotion.walkTo(m: Mover, job: number, to: Vector3, o: WalkOptions?): string
	local opts: WalkOptions = o or {}
	local hum, root = humOf(m), rootOf(m)
	if not hum or not root or root.Anchored then
		return "Cancel"
	end
	release(m)
	local points = sway(route(root.Position, to))
	if m.job ~= job then
		return "Cancel"
	end
	m.points, m.index = points, 1
	local now = os.clock()
	local pauseAt = now + range(N.PauseEverySeconds)
	local lookAt = now - math.log(1 - random:NextNumber()) / N.LookChancePerSecond
	local studs = length(points)
	-- The odd hop: once, with 40-70% of the walk left, never close to the end.
	local jumpLeft: number? = nil
	if not opts.quiet and studs >= N.JumpMinStuds and random:NextNumber() < N.JumpChance then
		local left = studs * (0.4 + 0.3 * random:NextNumber())
		jumpLeft = if left >= N.JumpClearStuds then left else nil
	end
	local arriving = false
	local lastPos, lastMoveAt = root.Position, now
	local issuedAt = -math.huge
	while m.index <= #points do
		if m.job ~= job or m.bot.gone or root.Parent == nil or root.Anchored then
			return "Cancel"
		end
		now = os.clock()
		if opts.deadline and now >= opts.deadline then
			hum:MoveTo(root.Position)
			return "Late"
		end
		if opts.stop and opts.stop() then
			hum:MoveTo(root.Position)
			return "Stop"
		end
		local point = points[m.index]
		if flat(point - root.Position).Magnitude < BOT.ArriveStuds then
			m.index += 1
			issuedAt = -math.huge
			continue
		end
		if not opts.quiet and now >= pauseAt then
			pauseAt = now + range(N.PauseEverySeconds)
			hum:MoveTo(root.Position)
			task.wait(range(N.PauseSeconds))
			issuedAt = -math.huge
			lastPos, lastMoveAt = root.Position, os.clock()
			continue
		end
		-- MoveTo gives up after 8 s and a hop can drop it: issue it again often, at once when
		-- the body stands still.
		local speed = flat(root.AssemblyLinearVelocity).Magnitude
		if now - issuedAt > 1 or (speed < 2 and now - issuedAt > 0.25) then
			hum:MoveTo(point)
			issuedAt = now
		end
		local left = remaining(m, root)
		if opts.face and not arriving and left <= N.FaceStuds then
			arriving = true
			turnTo(m, yawOf(flat(opts.face - root.Position)), N.TurnSeconds)
		end
		if not opts.quiet and not arriving then
			if now >= lookAt and left > N.FaceStuds * 2 then
				lookAt = now - math.log(1 - random:NextNumber()) / N.LookChancePerSecond
				lookRound(m, job, root)
			end
			if jumpLeft and left <= jumpLeft then
				jumpLeft = nil
				hum.Jump = true
			end
		end
		if (root.Position - lastPos).Magnitude > BOT.StuckStuds then
			lastPos, lastMoveAt = root.Position, now
		elseif now - lastMoveAt > BOT.StuckSeconds * 2 then
			hum:MoveTo(root.Position)
			return "Stuck"
		end
		task.wait(0.05)
	end
	return "Done"
end

-- One fidget while it stands about: faces `towards` (when given), looks round, shifts its
-- feet, or (rarely) hops.
local function fidget(m: Mover, job: number, towards: Vector3?)
	local root, hum = rootOf(m), humOf(m)
	if not root or not hum or root.Anchored then
		return
	end
	local r = random:NextNumber()
	if r < N.FidgetJumpChance then
		hum.Jump = true
	elseif r < 0.45 and towards then
		turnTo(m, yawOf(flat(towards - root.Position)), N.TurnSeconds * 2)
	elseif r < 0.75 then
		local base = yawOfPart(root)
		local sign = if random:NextNumber() < 0.5 then -1 else 1
		turnTo(m, base + sign * math.rad(range(N.LookDegrees) * 1.4), N.TurnSeconds * 2)
		task.delay(N.TurnSeconds * 2 + range(N.LookSeconds), function()
			if m.job == job and m.lockYaw then
				turnTo(m, base, N.TurnSeconds * 2)
			end
		end)
	else
		release(m)
		local angle = random:NextNumber() * 2 * math.pi
		hum:MoveTo(
			root.Position + Vector3.new(math.cos(angle), 0, math.sin(angle)) * N.FidgetStepStuds
		)
	end
end

--- Stands about like a person for `seconds` (yields): fidgets, now and then facing what
--- `towards()` gives. False when its job changed (or `stop()` said so) first.
function LobbyMotion.idle(
	m: Mover,
	job: number,
	seconds: number,
	towards: (() -> Vector3?)?,
	stop: (() -> boolean)?
): boolean
	local endAt = os.clock() + seconds
	local fidgetAt = os.clock() + range(N.FidgetEverySeconds)
	while m.job == job and not m.bot.gone do
		local now = os.clock()
		if now >= endAt then
			return true
		end
		if stop and stop() then
			return false
		end
		if now >= fidgetAt then
			fidgetAt = now + range(N.FidgetEverySeconds)
			fidget(m, job, if towards then towards() else nil)
		end
		task.wait(0.2)
	end
	return false
end

-- Every frame: the turning bodies ease to their facing.
RunService.Heartbeat:Connect(function()
	for m in movers do
		local turn = m.turn
		if m.lockYaw and turn then
			local hum, turner = humOf(m), turnerOf(m)
			local root = rootOf(m)
			if hum and turner and root and not root.Anchored then
				hum.AutoRotate = false
				local a = math.clamp((os.clock() - turn.t0) / turn.dur, 0, 1)
				a = a * a * (3 - 2 * a)
				turner.CFrame = CFrame.Angles(0, turn.from + (turn.to - turn.from) * a, 0)
				turner.Enabled = true
			end
		end
	end
end)

return LobbyMotion
