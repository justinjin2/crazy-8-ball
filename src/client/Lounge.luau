--!strict
-- Lounge: the client's view of the room. It owns one simulation per table, a small pool of
-- ball renderers pointed at the nearest few, and the seat state the server sends down.
--
-- Twelve tables all drawing their balls would be 192 ball meshes on top of a scene that
-- already carries about a quarter of a million triangles of table, and the ones across the
-- room are a few pixels tall. So every table has a Match (the state is sixteen balls of
-- plain data, which costs nothing) but only Config.Lounge.RenderedTables of them hold a
-- renderer at any moment. Walking towards a table hands it one.
--
-- Roadmap 1.5g adds the other players' cue sticks here, which is why the pool is a pool and
-- not "the table you are standing at".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueStickBuilder = require(Shared:WaitForChild("CueStickBuilder"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))
local Match = require(script.Parent:WaitForChild("Match"))

local Lounge = {}
Lounge.__index = Lounge

export type Seat = { userId: number, host: boolean, connected: boolean, team: number, slot: number }

export type Lounge = typeof(setmetatable(
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
		-- tableId -> { angle, shown, by }: the aim coming off the wire, and the eased angle
		-- actually drawn, so a ten-a-second stream does not make the cue step.
		aims: { [number]: { angle: number, shown: number, by: number } },
	},
	Lounge
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

function Lounge.new(parent: Instance): Lounge
	local folder = Instance.new("Folder")
	folder.Name = "Balls"
	folder.Parent = parent

	local self = setmetatable({
		folder = folder,
		matches = {},
		pool = {},
		boundTo = {},
		seats = {},
		sinceRebind = math.huge, -- bind on the first frame
		seatListeners = {},
		rejectListeners = {},
		mySeat = nil,
		snapshots = {},
		snapshotListeners = {},
		cues = {},
		cueOf = {},
		aims = {},
	}, Lounge)

	-- Only the tables the server actually builds: a Match for a table with no model would
	-- draw sixteen balls floating where that table would have been.
	local wanted = Placement.tableCount()
	for _, row in Config.Lounge.Tables do
		local p = if row.id <= wanted then Placement.forTable(row.id) else nil
		if p then
			self.matches[row.id] = Match.new(p, nil, Config.Rack.DefaultSeed + row.id)
			self.seats[row.id] = {}
		end
	end

	-- The pool is built up front so no shot ever waits on sixteen parts being created.
	local first = Config.Lounge.Tables[1]
	local firstPlacement = Placement.forTable(first.id)
	for i = 1, math.min(Config.Lounge.RenderedTables, Placement.tableCount()) do
		table.insert(self.pool, BallRenderer.new(folder, firstPlacement :: any, i))
		local cue = CueStickBuilder.build(parent)
		cue.Name = ("WatchedCue_%d"):format(i)
		CueStickBuilder.setVisible(cue, false)
		table.insert(self.cues, cue)
	end

	self:listen()
	task.defer(function()
		Net.get("SnapshotRequest"):FireServer()
	end)
	return self
end

--- Called whenever the local player's seat changes: the table id, or nil for "not seated".
function Lounge.onSeatChanged(self: Lounge, listener: (number?) -> ())
	table.insert(self.seatListeners, listener)
end

--- Called when the server turns a shot down. The client disables its own controls when it
--- fires and waits for a ShotResult, so this is what stops them staying dead.
function Lounge.onShotRejected(self: Lounge, listener: (string) -> ())
	table.insert(self.rejectListeners, listener)
end

--- Tell the server where we are aiming, so the people watching see the cue turn.
function Lounge.reportAim(self: Lounge, id: number, angle: number)
	local snapshot = self.snapshots[id]
	if snapshot then
		Net.get("AimUpdate"):FireServer(id, angle, snapshot.epoch, snapshot.turnId)
	end
end
function Lounge.onSnapshot(self: Lounge, listener: (any) -> ())
	table.insert(self.snapshotListeners, listener)
end
function Lounge.action(self: Lounge, kind: string, data: any?)
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
function Lounge.fire(
	self: Lounge,
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

function Lounge.listen(self: Lounge)
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
		for i = 1, #batch, 3 do
			seen[batch[i]] = true
			local id, by, angle = batch[i], batch[i + 1], batch[i + 2]
			if typeof(id) == "number" and typeof(angle) == "number" then
				local existing = self.aims[id]
				if existing then
					existing.angle = angle
					existing.by = by
				else
					-- First sighting: draw it where it is rather than easing from zero.
					self.aims[id] = { angle = angle, shown = angle, by = by }
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
			match:receive(msg)
		end
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
function Lounge.matchFor(self: Lounge, id: number): Match.Match?
	return self.matches[id]
end

--- The rendered cue ball for table `id`, if that table is currently being drawn. The trail
--- hangs off this part directly, so it follows the ball without any per-frame work here.
function Lounge.cueBallPartFor(self: Lounge, id: number): BasePart?
	local renderer = self.boundTo[id]
	if renderer == nil then
		return nil
	end
	local part = renderer.folder:FindFirstChild("CueBall")
	return if part and part:IsA("BasePart") then part else nil
end

--- Who is sitting at table `id`.
function Lounge.seatsAt(self: Lounge, id: number): { Seat }
	return self.seats[id] or {}
end

--- Ask the server for a seat, or to give one up.
function Lounge.requestSeat(_self: Lounge, id: number)
	Net.get("RequestSeat"):FireServer(id)
end

function Lounge.requestLeave(_self: Lounge)
	Net.get("RequestLeave"):FireServer()
end

function Lounge.requestRerack(_self: Lounge, id: number)
	Net.get("RequestRerack"):FireServer(id)
end

-- Point the pool at the nearest tables. The table the player is actually sitting at always
-- keeps one, however far the camera has wandered during a shot.
local function rebind(self: Lounge, from: Vector3)
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

-- Draw the cue of whoever is lining up at each table we can see. Never our own: the local
-- player's cue is driven directly by their input, with no round trip.
local function updateWatchedCues(self: Lounge, dt: number)
	local A = Config.Aim
	local alpha = 1 - math.exp(-dt / math.max(A.SmoothingSeconds, 1e-3))
	for id, cue in self.cueOf do
		local aim = self.aims[id]
		local match = self.matches[id]
		local cueBall = match and match:findCueBall()
		local snapshot = self.snapshots[id]
		local mine = aim and aim.by == Players.LocalPlayer.UserId
		-- A shot in flight has no cue against the ball, and neither has an empty table.
		if
			aim == nil
			or mine
			or cueBall == nil
			or cueBall.pocketed
			or match:isBusy()
			or not snapshot
			or snapshot.shooter ~= aim.by
			or (
				snapshot.phase ~= "Aiming"
				and snapshot.phase ~= "Intro"
				and snapshot.phase ~= "Placement"
			)
		then
			CueStickBuilder.setVisible(cue, false)
		else
			-- Ease towards the last angle heard: the stream is ten a second, so drawing it
			-- raw would visibly step.
			local delta = (aim.angle - aim.shown + math.pi) % (2 * math.pi) - math.pi
			aim.shown += delta * alpha
			CueStickBuilder.setVisible(cue, true)
			local p = match.placement
			local ballPos =
				TableBuilder.toWorld(p, cueBall.x, cueBall.y, Config.Balls.RenderRadiusInches)
			CueStickBuilder.place(
				cue,
				ballPos,
				TableBuilder.aimDirection(p, aim.shown),
				TableBuilder.studs(Config.Cue.CueRestGapInches)
			)
		end
	end
end

--- Step every table and keep the renderer pool pointed at the nearest ones. Returns true if
--- the table the player is sitting at is mid-shot.
function Lounge.update(self: Lounge, dt: number): boolean
	self.sinceRebind += dt
	if self.sinceRebind >= Config.Lounge.RebindEverySeconds then
		self.sinceRebind = 0
		local camera = Workspace.CurrentCamera
		rebind(self, if camera then camera.CFrame.Position else Vector3.zero)
	end

	local playingHere = false
	for id, match in self.matches do
		local busy = match:update(dt)
		if id == self.mySeat then
			playingHere = busy
		end
	end
	updateWatchedCues(self, dt)
	return playingHere
end

--- How many tables are currently drawing their balls (for the debug readout).
function Lounge.renderedCount(self: Lounge): number
	local n = 0
	for _ in self.boundTo do
		n += 1
	end
	return n
end

return Lounge
