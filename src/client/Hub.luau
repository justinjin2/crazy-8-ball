--!strict
-- Hub: the client's view of the room. It owns one simulation per table, a small pool of
-- ball renderers pointed at the nearest few, and the seat state the server sends down.
--
-- Twelve tables all drawing their balls would be 192 ball meshes on top of a scene that
-- already carries about a quarter of a million triangles of table, and the ones across the
-- room are a few pixels tall. So every table has a Match (the state is sixteen balls of
-- plain data, which costs nothing) but only Config.Hub.RenderedTables of them hold a
-- renderer at any moment. Walking towards a table hands it one.
--
-- Roadmap 1.5g adds the other players' cue sticks here, which is why the pool is a pool and
-- not "the table you are standing at". Each pooled table also shows its shooter posed, with
-- their cue and rake (WatchedShooters); this module feeds that the aim stream and the shots.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AimStream = require(Shared:WaitForChild("AimStream"))
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))
local Match = require(script.Parent:WaitForChild("Match"))
local WatchedShooters = require(script.Parent:WaitForChild("WatchedShooters"))

local Hub = {}
Hub.__index = Hub

export type Seat = { userId: number, host: boolean, connected: boolean, team: number, slot: number }

export type Hub = typeof(setmetatable(
	{} :: {
		folder: Folder,
		matches: { [number]: Match.Match },
		pool: { BallRenderer.BallRenderer },
		-- tableId -> which renderer in the pool is drawing it (absent = not drawn)
		boundTo: { [number]: BallRenderer.BallRenderer? },
		seats: { [number]: { Seat } },
		sinceRebind: number,
		seatListeners: { (number?) -> () },
		rejectListeners: { (string) -> () },
		mySeat: number?,
		snapshots: { [number]: any },
		snapshotListeners: { (any) -> () },
		-- One spare cue stick per pooled renderer, for watching other people line up.
		cues: { Model },
		cueOf: { [number]: Model },
		-- tableId -> the aim, cue-ball spot and wind-up coming off the wire, and the eased
		-- angle, spot and pull actually drawn, so a stream of a few a second makes none step.
		aims: { [number]: WatchedShooters.Aim },
		-- tableId -> the last shot the server accepted there (ShotResult): its exact angle and
		-- where the cue ball stood, which a watched shooter's stroke freezes on.
		shots: { [number]: WatchedShooters.Shot },
		-- Every pooled table's shooter, posed with their cue and rake.
		watched: WatchedShooters.WatchedShooters,
	},
	Hub
))

-- GDD section 6 wants stepping on a pad to be felt, not just seen. The sound waits on an
-- asset id; the flash needs none, so the pad's own glow is pulsed instead.
local function flashPad(id: number)
	local pads = Workspace:FindFirstChild("Pads")
	local pad = pads and pads:FindFirstChild(("Pad_%02d"):format(id))
	local glow = pad and pad:FindFirstChildOfClass("SurfaceLight")
	if glow == nil then
		return
	end
	local S = Config.Pad
	local settled = glow.Brightness
	glow.Brightness = S.FlashBrightness
	game:GetService("TweenService")
		:Create(glow, TweenInfo.new(S.FlashSeconds), { Brightness = settled })
		:Play()
	if S.StepSoundId ~= "" and pad and pad:IsA("BasePart") then
		local sound = Instance.new("Sound")
		sound.SoundId = S.StepSoundId
		sound.Volume = S.StepSoundVolume
		sound.Parent = pad
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end
end

function Hub.new(parent: Instance): Hub
	local folder = Instance.new("Folder")
	folder.Name = "Balls"
	folder.Parent = parent

	-- The pool is built up front so no shot ever waits on sixteen parts being created: a
	-- renderer, a cue and (WatchedShooters) a rake per slot.
	local first = Config.Hub.Tables[1]
	local firstPlacement = Placement.forTable(first.id)
	local pool, cues = {}, {}
	for i = 1, math.min(Config.Hub.RenderedTables, Placement.tableCount()) do
		table.insert(pool, BallRenderer.new(folder, firstPlacement :: any, i))
		local cue = CueStickBuilder.build(parent)
		cue.Name = ("WatchedCue_%d"):format(i)
		CueStickBuilder.setVisible(cue, false)
		table.insert(cues, cue)
	end

	local self = setmetatable({
		folder = folder,
		matches = {},
		pool = pool,
		boundTo = {},
		seats = {},
		sinceRebind = math.huge, -- bind on the first frame
		seatListeners = {},
		rejectListeners = {},
		mySeat = nil,
		snapshots = {},
		snapshotListeners = {},
		cues = cues,
		cueOf = {},
		aims = {},
		shots = {},
		watched = WatchedShooters.new(parent, cues),
	}, Hub)

	-- Only the tables the server actually builds: a Match for a table with no model would
	-- draw sixteen balls floating where that table would have been.
	local wanted = Placement.tableCount()
	for _, row in Config.Hub.Tables do
		local p = if row.id <= wanted then Placement.forTable(row.id) else nil
		if p then
			self.matches[row.id] = Match.new(p, nil, Config.Rack.DefaultSeed + row.id)
			self.seats[row.id] = {}
		end
	end

	self:listen()
	task.defer(function()
		Net.get("SnapshotRequest"):FireServer()
	end)
	return self
end

--- Called whenever the local player's seat changes: the table id, or nil for "not seated".
function Hub.onSeatChanged(self: Hub, listener: (number?) -> ())
	table.insert(self.seatListeners, listener)
end

--- Called when the server turns a shot down. The client disables its own controls when it
--- fires and waits for a ShotResult, so this is what stops them staying dead.
function Hub.onShotRejected(self: Hub, listener: (string) -> ())
	table.insert(self.rejectListeners, listener)
end

--- Tell the server where we are aiming and how far the cue is drawn back (`pull`, 0..1,
--- already snapped by AimStream.quantizePull), so the people watching see the cue turn and
--- wind up, and at what cue angle (`elevation`, degrees) so a raised cue is drawn raised.
--- While the cue ball is in hand, `seq`, `x` and `y` carry its latest spot on the same packet.
function Hub.reportAim(
	self: Hub,
	id: number,
	angle: number,
	pull: number,
	elevation: number,
	seq: number?,
	x: number?,
	y: number?
)
	local snapshot = self.snapshots[id]
	if snapshot then
		Net.get("AimUpdate")
			:FireServer(id, angle, snapshot.epoch, snapshot.turnId, pull, seq, x, y, elevation)
	end
end
function Hub.onSnapshot(self: Hub, listener: (any) -> ())
	table.insert(self.snapshotListeners, listener)
end
function Hub.action(self: Hub, kind: string, data: any?)
	local snapshot = self.mySeat and self.snapshots[self.mySeat]
	if not snapshot then
		return
	end
	local payload: any = if data then table.clone(data) else {}
	payload.kind, payload.tableId, payload.epoch, payload.turnId =
		kind, snapshot.id, snapshot.epoch, snapshot.turnId
	Net.get("MatchAction"):FireServer(payload)
end

--- Ask the server to take a shot at table `id`. Nothing happens locally: the shot starts
--- when the server broadcasts it back, so every client (including this one) plays the same
--- motion from the same numbers at the same moment.
function Hub.fire(
	self: Hub,
	id: number,
	angle: number,
	power: number,
	spin: { x: number, y: number },
	elevation: number,
	cueX: number?,
	cueY: number?
)
	local snapshot = self.snapshots[id]
	if not snapshot then
		return
	end
	Net.get("ShotFired"):FireServer({
		epoch = snapshot.epoch,
		turnId = snapshot.turnId,
		cueX = cueX,
		cueY = cueY,
		tableId = id,
		angle = angle,
		power = power,
		spin = spin,
		elevation = elevation,
	})
end

local function finite(value: any): boolean
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- Keep what a watched shooter's stroke freezes on from a shot the server accepted: the exact
-- direction the cue ball left in (its seed velocity: side spin never bends the launch while
-- Config.Cue.SideSpinBendsPath is off) and where it stood before the shot (the start packs
-- every ball as x, y, z, pocketed from id 0, the cue ball). Off the network, so it is checked.
local function recordShot(self: Hub, msg: any)
	local seed, start = msg.seed, msg.start
	if
		not finite(msg.epoch)
		or not finite(msg.seq)
		or typeof(seed) ~= "table"
		or typeof(start) ~= "table"
		or not finite(seed.vx)
		or not finite(seed.vy)
		or (seed.vz ~= nil and not finite(seed.vz))
		or not finite(start[1])
		or not finite(start[2])
		or seed.vx * seed.vx + seed.vy * seed.vy < 1e-12
	then
		return
	end
	local shot = self.shots[msg.tableId]
	if shot == nil then
		shot = { epoch = 0, seq = 0, angle = 0, x = 0, y = 0 }
		self.shots[msg.tableId] = shot
	end
	shot.epoch, shot.seq = msg.epoch, msg.seq
	shot.angle = math.atan2(seed.vy, seed.vx)
	shot.x, shot.y = start[1], start[2]
end

function Hub.listen(self: Hub)
	local me = Players.LocalPlayer.UserId

	Net.get("ShotRejected").OnClientEvent:Connect(function(reason)
		for _, l in self.rejectListeners do
			l(if typeof(reason) == "string" then reason else "?")
		end
	end)

	Net.get("AimBroadcast").OnClientEvent:Connect(function(batch)
		if typeof(batch) ~= "table" then
			return
		end
		local seen: { [number]: boolean } = {}
		for i = 1, #batch, Net.AimStride do
			-- A malformed group is skipped; the rest of the batch still counts.
			local row = AimStream.read(batch, i)
			if row then
				seen[row.id] = true
				local existing = self.aims[row.id]
				if existing and existing.by == row.by then
					existing.angle = row.angle
					existing.x, existing.y = row.x, row.y
					existing.pull = row.pull
					existing.elevation = row.elevation
				else
					-- First sighting, or a new shooter: draw it where it is rather than easing
					-- from zero or from the last shooter's cue.
					self.aims[row.id] = {
						angle = row.angle,
						shown = row.angle,
						by = row.by,
						x = row.x,
						y = row.y,
						shownX = row.x,
						shownY = row.y,
						pull = row.pull,
						shownPull = row.pull,
						elevation = row.elevation,
					}
				end
			end
		end
		for id in self.aims do
			if not seen[id] then
				self.aims[id] = nil
			end
		end
	end)

	Net.get("ShotResult").OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" or typeof(msg.tableId) ~= "number" then
			return
		end
		local match: Match.Match? = self.matches[msg.tableId]
		if match then
			recordShot(self, msg)
			match:receive(msg)
		end
	end)
	-- A shooter who leaves mid-turn takes their body with them: nothing posed may outlive it.
	Players.PlayerRemoving:Connect(function(p: Player)
		self.watched:forgetUser(p.UserId)
	end)
	Net.get("TableState").OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" or typeof(snapshot.id) ~= "number" then
			return
		end
		local previous = self.snapshots[snapshot.id]
		if
			previous
			and (
				snapshot.epoch < previous.epoch
				or (snapshot.epoch == previous.epoch and snapshot.revision < previous.revision)
			)
		then
			return
		end
		self.snapshots[snapshot.id] = snapshot
		-- Before the listeners below, so the Match's shown-down balls and revealed colors
		-- (downVersion, assign) are current when Main presents this snapshot.
		local match = self.matches[snapshot.id]
		if match then
			match:snapshot(snapshot)
		end
		local before = #(self.seats[snapshot.id] or {})
		self.seats[snapshot.id] = snapshot.seats or {}
		if #self.seats[snapshot.id] > before then
			flashPad(snapshot.id)
		end
		-- Work out where the local player is now sitting, if anywhere.
		local found: number? = nil
		for id, seats in self.seats do
			for _, seat in seats do
				if seat.userId == me and seat.connected then
					found = id
				end
			end
		end
		if found ~= self.mySeat then
			self.mySeat = found
			for _, l in self.seatListeners do
				l(found)
			end
		end
		for _, listener in self.snapshotListeners do
			listener(snapshot)
		end
	end)
end

--- The simulation for table `id`.
function Hub.matchFor(self: Hub, id: number): Match.Match?
	return self.matches[id]
end

--- The rendered cue ball for table `id`, if that table is currently being drawn. The trail
--- hangs off this part directly, so it follows the ball without any per-frame work here.
function Hub.cueBallPartFor(self: Hub, id: number): BasePart?
	local renderer = self.boundTo[id]
	if renderer == nil then
		return nil
	end
	local part = renderer.folder:FindFirstChild("CueBall")
	return if part and part:IsA("BasePart") then part else nil
end

--- Who is sitting at table `id`.
function Hub.seatsAt(self: Hub, id: number): { Seat }
	return self.seats[id] or {}
end

--- Ask the server for a seat, or to give one up.
function Hub.requestSeat(_self: Hub, id: number)
	Net.get("RequestSeat"):FireServer(id)
end

function Hub.requestLeave(_self: Hub)
	Net.get("RequestLeave"):FireServer()
end

function Hub.requestRerack(_self: Hub, id: number)
	Net.get("RequestRerack"):FireServer(id)
end

-- Point the pool at the nearest tables. The table the player is actually sitting at always
-- keeps one, however far the camera has wandered during a shot.
local function rebind(self: Hub, from: Vector3)
	local order = {}
	for id, match in self.matches do
		local p = match.placement
		local dx, dz = p.x - from.X, p.z - from.Z
		table.insert(order, { id = id, d = if id == self.mySeat then -1 else dx * dx + dz * dz })
	end
	table.sort(order, function(a, b)
		-- Ties broken by id, so the choice is stable instead of flickering frame to frame.
		if a.d == b.d then
			return a.id < b.id
		end
		return a.d < b.d
	end)

	local wanted: { [number]: boolean } = {}
	for i = 1, math.min(#self.pool, #order) do
		wanted[order[i].id] = true
	end

	-- Let go of every table that has dropped out of the nearest set.
	for id, _ in self.boundTo do
		if not wanted[id] then
			self.matches[id]:detach()
			self.boundTo[id] = nil
			local held: Model? = self.cueOf[id]
			if held then
				CueStickBuilder.setVisible(held, false)
				self.cueOf[id] = nil
			end
			-- ...and of its shooter: let go of the body, hide the rake.
			self.watched:unbind(id)
		end
	end

	-- Whatever is left over in the pool is available.
	local used: { [BallRenderer.BallRenderer]: boolean } = {}
	for _, renderer in self.boundTo do
		used[renderer :: BallRenderer.BallRenderer] = true
	end
	local free = {}
	for _, renderer in self.pool do
		if not used[renderer] then
			table.insert(free, renderer)
		end
	end

	-- Watched cues follow the same pool: a table nobody is drawing needs no cue either.
	local cueUsed: { [Model]: boolean } = {}
	for _, cue in self.cueOf do
		cueUsed[cue] = true
	end
	local freeCues = {}
	for _, cue in self.cues do
		if not cueUsed[cue] then
			table.insert(freeCues, cue)
		end
	end

	for id in wanted do
		if self.boundTo[id] == nil then
			local renderer = table.remove(free)
			if renderer then
				local match = self.matches[id]
				renderer:rebind(match.placement, id)
				match:attach(renderer)
				self.boundTo[id] = renderer
			end
		end
		local held: Model? = self.cueOf[id]
		if held == nil then
			local cue = table.remove(freeCues)
			if cue then
				self.cueOf[id] = cue
			end
		end
	end
end

-- Slide each watched cue ball in hand toward the spot its shooter last sent, eased so the
-- stream never makes it step. Never our own: the local shooter's ball is predicted in Main.
local function followPlacement(self: Hub, dt: number)
	local alpha = 1 - math.exp(-dt / math.max(Config.Aim.BallSmoothingSeconds, 1e-3))
	local me = Players.LocalPlayer.UserId
	for id, aim in self.aims do
		local match = self.matches[id]
		local snapshot = self.snapshots[id]
		if
			match
			and snapshot
			and aim.by ~= me
			and aim.by == snapshot.shooter
			and snapshot.ballInHand == true
			and (snapshot.phase == "Intro" or snapshot.phase == "Placement")
			and not match:isBusy()
		then
			local fromX, fromY = aim.shownX, aim.shownY
			aim.shownX += (aim.x - fromX) * alpha
			aim.shownY += (aim.y - fromY) * alpha
			local cue = match:findCueBall()
			if
				cue and (math.abs(cue.x - aim.shownX) > 1e-4 or math.abs(cue.y - aim.shownY) > 1e-4)
			then
				match:setCue(aim.shownX, aim.shownY)
			end
		else
			aim.shownX, aim.shownY = aim.x, aim.y
		end
	end
end

-- Ease each watched aim toward what was last heard: the stream is ten a second, so drawing it
-- raw would visibly step. Only while the shooter is lining up at a table we can see; never
-- our own (the local player's cue is driven directly by their input, with no round trip).
-- WatchedShooters draws the cue and the shooter from the eased values.
local function easeAims(self: Hub, dt: number)
	local A = Config.Aim
	local alpha = 1 - math.exp(-dt / math.max(A.SmoothingSeconds, 1e-3))
	local pullAlpha = 1 - math.exp(-dt / math.max(A.PullSmoothingSeconds, 1e-3))
	local me = Players.LocalPlayer.UserId
	for id in self.cueOf do
		local aim = self.aims[id]
		local match = self.matches[id]
		local snapshot = self.snapshots[id]
		if
			aim
			and aim.by ~= me
			and match
			and not match:isBusy()
			and snapshot
			and snapshot.shooter == aim.by
			and (
				snapshot.phase == "Aiming"
				or snapshot.phase == "Intro"
				or snapshot.phase == "Placement"
			)
		then
			local delta = (aim.angle - aim.shown + math.pi) % (2 * math.pi) - math.pi
			aim.shown += delta * alpha
			-- The wind-up eases too, but quickly, so a let-go still reads as a stroke.
			aim.shownPull += (aim.pull - aim.shownPull) * pullAlpha
		end
	end
end

--- Step every table and keep the renderer pool pointed at the nearest ones. Returns true if
--- the table the player is sitting at is mid-shot.
function Hub.update(self: Hub, dt: number): boolean
	self.sinceRebind += dt
	if self.sinceRebind >= Config.Hub.RebindEverySeconds then
		self.sinceRebind = 0
		local camera = Workspace.CurrentCamera
		rebind(self, if camera then camera.CFrame.Position else Vector3.zero)
	end

	local playingHere = false
	for id, match in self.matches do
		local busy = match:update(dt)
		if match.renderer then
			match.renderer:animate(dt)
		end
		if id == self.mySeat then
			playingHere = busy
		end
	end
	followPlacement(self, dt)
	easeAims(self, dt)
	self.watched:update(dt, self.cueOf, self.snapshots, self.matches, self.aims, self.shots)
	return playingHere
end

--- How many tables are currently drawing their balls (for the debug readout).
function Hub.renderedCount(self: Hub): number
	local n = 0
	for _ in self.boundTo do
		n += 1
	end
	return n
end

return Hub
