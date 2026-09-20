--!strict
-- TableService: the server's view of the twelve tables. It owns who is sitting where, and
-- it owns the floor pads that put them there.
--
-- Joining is "step on the pad" (GDD section 6), not a prompt. Occupancy is POLLED rather
-- than driven by BasePart.Touched, for two reasons: Touched does not fire for a player who
-- walks on and then stands still, and it fires repeatedly for one that jitters. A distance
-- check a few times a second is both cheaper and steadier for twelve pads.
--
-- A player has to be on the pad for two polls running before it counts. Without that, the
-- acceptance test for this milestone breaks it immediately: someone walking across the room
-- clips the corner of three pads on the way and gets dragged into a seat at each.
--
-- Roadmap 1.5f gives this the shot authority as well (validating a shot, running the
-- simulation, broadcasting the result). Right now it only tracks seats, which is why there
-- is no turn order here: the designer's call is that anyone at a table may shoot until the
-- rules land in 2.1.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local Physics = Shared:WaitForChild("Physics")
local Rack = require(Physics:WaitForChild("Rack"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableGeometry = require(Physics:WaitForChild("Table"))

local TableService = {}

TableService.PadFolderName = "Pads"

export type Seat = { userId: number, host: boolean }

type TableState = {
	id: number,
	placement: Placement.Placement,
	pad: BasePart,
	-- The authoritative balls. Clients keep their own copy and replay shots onto it, but
	-- this one is the truth and they settle onto it when a shot ends.
	state: Simulation.State,
	-- Bumped per shot, so a client that missed one can tell and snap instead of replaying.
	shotSeq: number,
	-- Where the shooter at this table is currently aiming, relayed to everyone watching.
	aim: number?,
	aimBy: number?,
	-- Server time the current shot started, or nil when the table is still.
	shotStartedAt: number?,
	seats: { Seat },
	-- userId -> how many polls in a row they have been standing on this pad
	dwell: { [number]: number },
	-- userId -> the time they left this table, so the pad can ignore them for a moment
	leftAt: { [number]: number },
}

local tables: { [number]: TableState } = {}
local seatOf: { [number]: number } = {} -- userId -> table id

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

--- Where table `id`'s pad stands: out past the head rail, on that tier's floor.
function TableService.padPosition(p: Placement.Placement): Vector3
	local dx, dz = Placement.dirToWorld(p, -1, 0) -- towards the head rail in table space
	local d = Config.Pad.DistanceStuds
	return Vector3.new(p.x + dx * d, p.y + Config.Pad.SizeStuds[2] / 2, p.z + dz * d)
end

local function buildPad(p: Placement.Placement, id: number, parent: Instance): BasePart
	local S = Config.Pad
	local pad = Instance.new("Part")
	pad.Name = ("Pad_%02d"):format(id)
	pad.Anchored = true
	pad.CanCollide = false -- you walk onto it, never into it
	pad.CanQuery = false
	pad.CanTouch = false
	pad.CastShadow = false
	pad.Size = Vector3.new(S.SizeStuds[1], S.SizeStuds[2], S.SizeStuds[3])
	pad.Material = Enum.Material.SmoothPlastic
	pad.Color = color(S.FreeColor)
	pad.Transparency = S.FreeTransparency
	pad.TopSurface = Enum.SurfaceType.Smooth
	pad.BottomSurface = Enum.SurfaceType.Smooth
	pad.CFrame = CFrame.new(TableService.padPosition(p)) * CFrame.Angles(0, p.yaw, 0)
	pad.Parent = parent

	-- A soft light under the pad so "this table is taken" reads from across the room.
	local glow = Instance.new("SurfaceLight")
	glow.Name = "Glow"
	glow.Face = Enum.NormalId.Top
	glow.Angle = 120
	glow.Range = 10
	glow.Brightness = 0
	glow.Shadows = false
	glow.Color = color(S.OccupiedColor)
	glow.Parent = pad

	local label = Instance.new("SurfaceGui")
	label.Name = "Number"
	label.Face = Enum.NormalId.Top
	label.CanvasSize = Vector2.new(200, 200)
	label.Parent = pad
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextScaled = true
	text.TextTransparency = 0.35
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.Text = tostring(id)
	text.Parent = label
	return pad
end

local function refreshPad(t: TableState)
	local S = Config.Pad
	local n = #t.seats
	local glow = t.pad:FindFirstChild("Glow") :: SurfaceLight?
	if n == 0 then
		t.pad.Color = color(S.FreeColor)
		t.pad.Transparency = S.FreeTransparency
		if glow then
			glow.Brightness = 0
		end
	else
		local full = n >= S.MaxSeats
		t.pad.Color = color(if full then S.FullColor else S.OccupiedColor)
		t.pad.Transparency = S.ActiveTransparency
		if glow then
			glow.Brightness = 1.4
			glow.Color = t.pad.Color
		end
	end
end

--- What the clients are told about one table.
local function snapshot(t: TableState)
	local seats = {}
	for i, seat in t.seats do
		seats[i] = { userId = seat.userId, host = seat.host }
	end
	return { id = t.id, seats = seats }
end

local function broadcast(t: TableState)
	refreshPad(t)
	Net.get("TableState"):FireAllClients(snapshot(t))
end

--- Every table's seats, for a client that has just joined the server.
function TableService.snapshotAll(): { any }
	local all = {}
	for _, t in tables do
		table.insert(all, snapshot(t))
	end
	return all
end

--- Seat `player` at table `id`. Returns true if they ended up seated there.
function TableService.seat(player: Player, id: number): boolean
	local t = tables[id]
	if t == nil then
		return false
	end
	local current = seatOf[player.UserId]
	if current == id then
		return true
	end
	if #t.seats >= Config.Pad.MaxSeats then
		return false
	end
	if current then
		TableService.unseat(player)
	end
	-- The first player on a free table is the host (GDD section 6). The host popup and the
	-- settings it carries are Roadmap 2.4; the slot exists from now so they have somewhere
	-- to land.
	table.insert(t.seats, { userId = player.UserId, host = #t.seats == 0 })
	seatOf[player.UserId] = id
	broadcast(t)
	return true
end

--- Take `player` off whatever table they are on.
function TableService.unseat(player: Player): boolean
	local id = seatOf[player.UserId]
	if id == nil then
		return false
	end
	local t = tables[id]
	seatOf[player.UserId] = nil
	if t == nil then
		return false
	end
	for i, seat in t.seats do
		if seat.userId == player.UserId then
			table.remove(t.seats, i)
			break
		end
	end
	-- If the host left, the next player along becomes host rather than the table stalling
	-- with nobody able to set it up.
	if #t.seats > 0 then
		local stillHosted = false
		for _, seat in t.seats do
			stillHosted = stillHosted or seat.host
		end
		if not stillHosted then
			t.seats[1].host = true
		end
	end
	if t.aimBy == player.UserId then
		t.aim = nil
		t.aimBy = nil
	end
	-- Leaving has to stick. The shooter stands at the rail, well inside the pad's radius, so
	-- without this the next poll would seat them again immediately.
	t.leftAt[player.UserId] = os.clock()
	for _, other in tables do
		other.dwell[player.UserId] = nil
	end
	broadcast(t)
	return true
end

--- Which table `player` is sitting at, if any.
function TableService.tableOf(player: Player): number?
	return seatOf[player.UserId]
end

--- The authoritative simulation for table `id`, for ShotService.
function TableService.stateOf(id: number): Simulation.State?
	local t = tables[id]
	return if t then t.state else nil
end

--- True while a shot is still running on table `id`, so a second one cannot be started.
function TableService.isBusy(id: number): boolean
	local t = tables[id]
	if t == nil or t.shotStartedAt == nil then
		return false
	end
	return (workspace:GetServerTimeNow() - t.shotStartedAt) < Config.Physics.MaxShotSeconds
end

--- Record that a shot has begun, returning its sequence number and start time.
function TableService.beginShot(id: number, duration: number): (number, number)
	local t = tables[id]
	t.shotSeq += 1
	local now = workspace:GetServerTimeNow()
	t.shotStartedAt = now
	-- The table is free again once the balls would have stopped.
	task.delay(duration + 0.25, function()
		if t.shotStartedAt == now then
			t.shotStartedAt = nil
		end
	end)
	return t.shotSeq, now
end

--- Put a fresh rack on table `id` (the B test key until the rules land in 2.1).
function TableService.rerack(id: number)
	local t = tables[id]
	if t and not TableService.isBusy(id) then
		t.state.balls = Rack.newGame(t.state.geometry)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- One poll: anybody standing on a free-enough pad long enough gets seated.
local function poll()
	local S = Config.Pad
	local radiusSq = S.RadiusStuds * S.RadiusStuds
	-- Sorted by UserId so that two players landing on the same pad in the same poll are
	-- seated in a fixed order, rather than whichever GetPlayers happened to list first.
	local players = Players:GetPlayers()
	table.sort(players, function(a, b)
		return a.UserId < b.UserId
	end)

	for _, t in tables do
		for _, player in players do
			local root = rootOf(player)
			local on = false
			if root then
				local d = root.Position - t.pad.Position
				-- Flat distance: standing on a pad one tier up does not count.
				on = (d.X * d.X + d.Z * d.Z) <= radiusSq and math.abs(d.Y) < 8
			end
			local cooling = false
			local left = t.leftAt[player.UserId]
			if left and (os.clock() - left) < S.RejoinCooldownSeconds then
				cooling = true
			elseif left then
				t.leftAt[player.UserId] = nil
			end
			if on and not cooling then
				local n = (t.dwell[player.UserId] or 0) + 1
				t.dwell[player.UserId] = n
				if n >= S.DwellPolls and seatOf[player.UserId] == nil then
					TableService.seat(player, t.id)
				end
			else
				t.dwell[player.UserId] = nil
			end
		end
	end
end

--- Build the pads and start watching them. Called once from Bootstrap.
function TableService.start(parent: Instance)
	local folder = parent:FindFirstChild(TableService.PadFolderName)
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder");
	(folder :: Folder).Name = TableService.PadFolderName;
	(folder :: Folder).Parent = parent

	-- One geometry for all twelve: it is read-only and identical, so there is no reason to
	-- build the same cushion and pocket list a dozen times.
	local geometry = TableGeometry.build({ pocketsOpen = true })
	for _, row in Config.Lounge.Tables do
		local placement = Placement.forTable(row.id)
		if placement then
			tables[row.id] = {
				id = row.id,
				placement = placement,
				pad = buildPad(placement, row.id, folder :: Folder),
				state = Simulation.newState(geometry, Rack.newGame(geometry)),
				shotSeq = 0,
				aim = nil,
				aimBy = nil,
				shotStartedAt = nil,
				seats = {},
				dwell = {},
				leftAt = {},
			}
		end
	end

	-- The aim stream. Each shooter's angle is stored, and one batched message a tick carries
	-- every table's aim to everyone: twelve separate broadcasts to thirty players would be
	-- 3,600 messages a second where this is 10.
	Net.get("AimUpdate").OnServerEvent:Connect(function(player, id, angle)
		if typeof(id) ~= "number" or typeof(angle) ~= "number" or angle ~= angle then
			return
		end
		-- Only the people actually sitting at a table may move its cue.
		if seatOf[player.UserId] ~= id then
			return
		end
		local t = tables[id]
		if t then
			t.aim = angle % (2 * math.pi)
			t.aimBy = player.UserId
		end
	end)

	local aimInterval = 1 / Config.Aim.BroadcastsPerSecond
	local sinceAim = 0
	RunService.Heartbeat:Connect(function(dt)
		sinceAim += dt
		if sinceAim < aimInterval then
			return
		end
		sinceAim = 0
		-- Flattened: id, userId, angle per table, so the payload stays small.
		local batch: { number } = {}
		for _, t in tables do
			if t.aim and t.aimBy then
				table.insert(batch, t.id)
				table.insert(batch, t.aimBy)
				table.insert(batch, t.aim)
			end
		end
		if #batch > 0 then
			Net.get("AimBroadcast"):FireAllClients(batch)
		end
	end)

	Net.get("RequestSeat").OnServerEvent:Connect(function(player, id)
		if typeof(id) == "number" then
			TableService.seat(player, id)
		end
	end)
	Net.get("RequestLeave").OnServerEvent:Connect(function(player)
		TableService.unseat(player)
	end)

	Players.PlayerAdded:Connect(function(player)
		-- Tell the newcomer where everyone already is.
		for _, t in tables do
			Net.get("TableState"):FireClient(player, snapshot(t))
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		TableService.unseat(player)
		for _, t in tables do
			t.leftAt[player.UserId] = nil
			t.dwell[player.UserId] = nil
		end
	end)

	local interval = 1 / Config.Pad.PollsPerSecond
	local since = 0
	RunService.Heartbeat:Connect(function(dt)
		since += dt
		if since >= interval then
			since = 0
			poll()
		end
	end)

	for _, t in tables do
		refreshPad(t)
	end
end

return TableService
