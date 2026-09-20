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
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))
local Match = require(script.Parent:WaitForChild("Match"))

local Lounge = {}
Lounge.__index = Lounge

export type Seat = { userId: number, host: boolean }

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
		mySeat: number?,
	},
	Lounge
))

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
		mySeat = nil,
	}, Lounge)

	for _, row in Config.Lounge.Tables do
		local p = Placement.forTable(row.id)
		if p then
			self.matches[row.id] = Match.new(p)
			self.seats[row.id] = {}
		end
	end

	-- The pool is built up front so no shot ever waits on sixteen parts being created.
	local first = Config.Lounge.Tables[1]
	local firstPlacement = Placement.forTable(first.id)
	for i = 1, Config.Lounge.RenderedTables do
		table.insert(self.pool, BallRenderer.new(folder, firstPlacement :: any, i))
	end

	self:listen()
	return self
end

--- Called whenever the local player's seat changes: the table id, or nil for "not seated".
function Lounge.onSeatChanged(self: Lounge, listener: (number?) -> ())
	table.insert(self.seatListeners, listener)
end

--- Ask the server to take a shot at table `id`. Nothing happens locally: the shot starts
--- when the server broadcasts it back, so every client (including this one) plays the same
--- motion from the same numbers at the same moment.
function Lounge.fire(_self: Lounge, id: number, angle: number, power: number)
	Net.get("ShotFired"):FireServer({ tableId = id, angle = angle, power = power })
end

function Lounge.listen(self: Lounge)
	local me = Players.LocalPlayer.UserId

	Net.get("ShotResult").OnClientEvent:Connect(function(msg)
		if typeof(msg) ~= "table" or typeof(msg.tableId) ~= "number" then
			return
		end
		local match: Match.Match? = self.matches[msg.tableId]
		if match then
			match:replay(msg.seq, msg.seed, msg.startedAt, msg.final, msg.checksum)
		end
	end)
	Net.get("TableState").OnClientEvent:Connect(function(snapshot)
		if typeof(snapshot) ~= "table" or typeof(snapshot.id) ~= "number" then
			return
		end
		self.seats[snapshot.id] = snapshot.seats or {}
		-- Work out where the local player is now sitting, if anywhere.
		local found: number? = nil
		for id, seats in self.seats do
			for _, seat in seats do
				if seat.userId == me then
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
	end)
end

--- The simulation for table `id`.
function Lounge.matchFor(self: Lounge, id: number): Match.Match?
	return self.matches[id]
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
