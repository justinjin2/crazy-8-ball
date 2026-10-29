--!strict
-- CandyDrop (Halloween 2026, hw-map lane; a copy of MoneyRain): while the event is Live, candy
-- pieces pop up on the roof near each eligible player (Rules.eligible: a lobby, HwOn, not
-- filming, not in a match, not sitting, not idle), one every SpawnEverySeconds (give or take
-- JitterSeconds) on a floor spot NearStuds from them, never on a queue or portal pad nor in a
-- table's match area. Each is an invisible anchored part in workspace[Folder] (attribute Kind:
-- the wrapper's colour); every client's MapClient draws, spins and pops it. The server checks
-- pickups every PickupTickSeconds: a player walking within PickupStuds asks core's
-- CandyService.pickup, which owns the Candy and the hour cap (Config.Halloween.Pickup.HourCap):
-- ok takes it (+1 shown on that player's screen), "Cap" leaves it for others and shows the
-- bag-full note once, pausing that player to the next UTC hour (Rules.pickupOutcome). A root
-- that jumped (a teleport: a turn's move, a portal) picks up nothing for TeleportGraceSeconds.
-- No client remote collects anything. Off (does nothing at all) while Config.HalloweenMap
-- .Enabled or Candy.Enabled is, and in an arena.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Placement = require(Shared:WaitForChild("Placement"))
-- Core's event clock: its times (the King's cooldown, the pickup hour) carry the Studio and
-- test-place offset (HwTimeOffset; 0 in the live game).
local Clock = require(Shared:WaitForChild("Halloween"):WaitForChild("Clock"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))

local Server = script.Parent.Parent
local Tables = require(Server:WaitForChild("TableService"))
local Funnel = require(Server:WaitForChild("Funnel"))
local GlobalQueue = require(Server:WaitForChild("GlobalQueue"))
local EventMap = require(script.Parent:WaitForChild("EventMap"))

local HM = Config.HalloweenMap
local C = HM.Candy

local CandyDrop = {}

-- The workspace folder the candy parts live in (MapClient draws them).
CandyDrop.Folder = "HalloweenCandy"

type Candy = { part: BasePart, at: Vector3, born: number }
type Who = {
	nextAt: number,
	anchor: Vector3?, -- where they were when they last moved IdleStuds
	movedAt: number,
	last: { number }?, -- the root at the last pickup tick
	graceUntil: number,
	pausedUntil: number,
	noted: boolean, -- the bag-full note shown this pause
	pickups: number,
	capped: boolean,
	joinedAt: number,
	lobbySeconds: number,
	own: number, -- candy alive spawned for them
}

local candies: { Candy } = {}
local who: { [Player]: Who } = {}
local rng = Random.new()
local warned = false
local warnedOnce: { [string]: boolean } = {}

-- A loop's failure, said once (these loops run every 0.2 s and every second).
local function warnOnce(message: string)
	if not warnedOnce[message] then
		warnedOnce[message] = true
		warn("[HalloweenMap] " .. message)
	end
end

local function folder(): Folder
	local found = workspace:FindFirstChild(CandyDrop.Folder)
	if found and found:IsA("Folder") then
		return found
	end
	local made = Instance.new("Folder")
	made.Name = CandyDrop.Folder
	made.Parent = workspace
	return made
end

local function candyService(): any?
	local folder_ = Server:FindFirstChild("Halloween")
	local module = folder_ and folder_:FindFirstChild("CandyService")
	if module and module:IsA("ModuleScript") then
		local ok, service = pcall(require, module)
		if ok then
			return service
		end
	end
	if not warned and RunService:IsStudio() then
		warned = true
		warn("[HalloweenMap] core's CandyService is missing: no candy spawns")
	end
	return nil
end

local function rootOf(p: Player): (BasePart?, Humanoid?)
	local character = p.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or humanoid.Health <= 0 or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	return root, humanoid
end

local function stateOf(p: Player): Who
	local w = who[p]
	if w == nil then
		local now = os.clock()
		w = {
			nextAt = now + Rules.spawnDelay(rng:NextNumber()),
			anchor = nil,
			movedAt = now,
			last = nil,
			graceUntil = 0,
			pausedUntil = 0,
			noted = false,
			pickups = 0,
			capped = false,
			joinedAt = now,
			lobbySeconds = 0,
			own = 0,
		}
		who[p] = w
	end
	return w :: Who
end

-- May `p` get candy now? (Rules.eligible with this server's facts)
local function eligible(p: Player, w: Who, now: number): boolean
	local root, humanoid = rootOf(p)
	if root == nil or humanoid == nil then
		return false
	end
	local pos = root.Position
	if w.anchor == nil or (pos - (w.anchor :: Vector3)).Magnitude >= C.IdleStuds then
		w.anchor = pos
		w.movedAt = now
	end
	local ok = Rules.eligible({
		isLobby = true,
		live = EventMap.isLive(),
		hwOn = p:GetAttribute("HwOn"),
		freecam = p:GetAttribute(Config.Freecam.Attribute) == true,
		inMatch = Tables.tableOf(p) ~= nil,
		sitting = humanoid.SeatPart ~= nil,
		movedStuds = if now - w.movedAt < C.IdleSeconds then C.IdleStuds else 0,
	})
	return ok
end

-- The pads (queue and portal) a candy must keep clear of, and the tables' match areas.
local function blocked(x: number, z: number): boolean
	local clear = C.PadClearStuds
	for id = 1, #Config.Hub.Tables do
		local t = Tables.get(id)
		local pad = t and t.pad
		if pad and Vector2.new(pad.Position.X - x, pad.Position.Z - z).Magnitude < clear + 3 then
			return true
		end
		local p = Placement.forTable(id)
		local row = Config.Hub.Tables[id]
		if p and row then
			local hx, hy, cx, cy = Placement.matchWalls(row.teamSize)
			-- The point in the table's own studs (x along its length, y across).
			local dx, dz = x - p.x, z - p.z
			local lx = dx * p.cos - dz * p.sin
			local ly = -(dx * p.sin + dz * p.cos)
			if math.abs(lx - cx) <= hx and math.abs(ly - cy) <= hy then
				return true
			end
		end
	end
	for _, row in Config.Portals.List do
		local px, pz = row.X, row.Z - Config.Portals.PadAheadStuds
		if Vector2.new(px - x, pz - z).Magnitude < Config.Portals.PadRadius + clear then
			return true
		end
	end
	return false
end

local function floorParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { folder() }
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local bots = workspace:FindFirstChild("Bots")
	if bots then
		table.insert(ignore, bots)
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

-- A floor spot NearStuds from `centre` with its floor within FloorWithinStuds of `feet`, clear
-- of pads and match areas, or nil after SpotTries.
local function spot(centre: Vector3, feet: number, params: RaycastParams): Vector3?
	local near, far = C.NearStuds[1], C.NearStuds[2]
	for _ = 1, C.SpotTries do
		local angle = rng:NextNumber(0, 2 * math.pi)
		local reach = near + (far - near) * math.sqrt(rng:NextNumber())
		local x, z = centre.X + math.cos(angle) * reach, centre.Z + math.sin(angle) * reach
		if blocked(x, z) then
			continue
		end
		local from = Vector3.new(x, feet + 20, z)
		local hit = workspace:Raycast(from, Vector3.new(0, -(20 + C.FloorWithinStuds), 0), params)
		if hit and math.abs(hit.Position.Y - feet) <= C.FloorWithinStuds then
			return hit.Position
		end
	end
	return nil
end

local function spawnFor(p: Player, w: Who, params: RaycastParams)
	local root, humanoid = rootOf(p)
	if root == nil or humanoid == nil then
		return
	end
	local feet = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
	local at = spot(root.Position, feet, params)
	if at == nil then
		return
	end
	local part = Instance.new("Part")
	part.Name = "Candy"
	part.Size = Vector3.new(1, 1, 1)
	part.Transparency = 1 -- MapClient draws it
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.CFrame = CFrame.new(at + Vector3.new(0, 1.2, 0))
	part:SetAttribute("Kind", if rng:NextNumber() < 0.5 then "Orange" else "Purple")
	part:SetAttribute("For", p.UserId)
	part.Parent = folder()
	w.own += 1
	local candy: Candy = { part = part :: BasePart, at = part.Position, born = os.clock() }
	table.insert(candies, candy)
end

local function forget(c: Candy)
	local owner = c.part:GetAttribute("For")
	c.part:Destroy()
	for p, w in who do
		if p.UserId == owner then
			w.own = math.max(0, w.own - 1)
		end
	end
end

-- Every second: spawn for whoever is due, clear the old candy; everything goes once not Live.
local function spawnTick()
	local now = os.clock()
	if not EventMap.isLive() then
		for i = #candies, 1, -1 do
			forget(candies[i])
			table.remove(candies, i)
		end
		return
	end
	for i = #candies, 1, -1 do
		local c = candies[i]
		if c.part.Parent == nil or now - c.born > C.LifeSeconds then
			forget(c)
			table.remove(candies, i)
		end
	end
	if candyService() == nil then
		return
	end
	local params: RaycastParams? = nil
	for _, p in Players:GetPlayers() do
		local w = stateOf(p)
		local ok = eligible(p, w, now)
		if ok then
			w.lobbySeconds += 1
		end
		if
			ok
			and now >= w.nextAt
			and Clock.serverNow() >= w.pausedUntil
			and w.own < C.MaxAlivePerPlayer
			and #candies < C.MaxAlive
		then
			w.nextAt = now + Rules.spawnDelay(rng:NextNumber())
			params = params or floorParams()
			spawnFor(p, w, params :: RaycastParams)
		end
	end
end

-- Every PickupTickSeconds: a player within PickupStuds of a candy asks CandyService.pickup.
local function pickupTick()
	if #candies == 0 or not EventMap.isLive() then
		return
	end
	local CandyService = candyService()
	if CandyService == nil then
		return
	end
	local now = os.clock()
	for _, p in Players:GetPlayers() do
		local root = rootOf(p)
		if root == nil then
			continue
		end
		local w = stateOf(p)
		local pos = root.Position
		local here = { pos.X, pos.Y, pos.Z }
		if Rules.teleported(w.last, here) then
			w.graceUntil = now + C.TeleportGraceSeconds
		end
		w.last = here
		if now < w.graceUntil or Clock.serverNow() < w.pausedUntil then
			continue
		end
		for i = #candies, 1, -1 do
			local c = candies[i]
			if (pos - c.at).Magnitude > C.PickupStuds then
				continue
			end
			if not eligible(p, w, now) then
				break
			end
			local ok, granted, reason = pcall(CandyService.pickup, p)
			if not ok then
				warnOnce("pickup: " .. tostring(granted))
				break
			end
			local outcome = Rules.pickupOutcome(granted == true, reason, Clock.serverNow())
			if outcome.take then
				w.pickups += 1
				forget(c)
				table.remove(candies, i)
				pcall(function()
					Net.get("HalloweenMapFx"):FireClient(p, { kind = "Pickup", at = c.at })
				end)
			elseif outcome.note then
				w.capped = true
				w.pausedUntil = outcome.pauseUntil or 0
				pcall(GlobalQueue.notify, { p }, { kind = "Failed", reason = "CandyBagFull" })
			end
			break -- one candy a tick each
		end
	end
end

-- The CandyPickups event at leave: pickups this session, capped or not, lobby minutes, device.
local function report(p: Player)
	local w = who[p]
	who[p] = nil
	if w == nil or w.lobbySeconds < 60 then
		return
	end
	local minutes = w.lobbySeconds / 60
	local bucket = if minutes < 5
		then "<5"
		elseif minutes < 15 then "5-15"
		elseif minutes < 30 then "15-30"
		elseif minutes < 60 then "30-60"
		else "60+"
	pcall(
		Funnel.event,
		p,
		"CandyPickups",
		w.pickups,
		if w.capped then "capped" else "ok",
		bucket,
		Funnel.device(p)
	)
	-- Funnel's own leave handler may already have cleared its per-player log, and the event
	-- above makes a new one that would hold the Player for the server's life (Friends' guard).
	pcall(Funnel.clearLog, p)
end

--- Start the drops (once, from Bootstrap). isLobby: false in an arena.
function CandyDrop.start(isLobby: boolean)
	if not (HM.Enabled and C.Enabled and isLobby) then
		return
	end
	Players.PlayerRemoving:Connect(report)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(function()
				spawnTick()
			end)
			if not ok then
				warnOnce("CandyDrop: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(C.PickupTickSeconds)
			local ok, err = pcall(function()
				pickupTick()
			end)
			if not ok then
				warnOnce("CandyDrop pickup: " .. tostring(err))
			end
		end
	end)
end

return CandyDrop
