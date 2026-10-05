--!strict
-- LuckyBlockService: lucky blocks on the server (designer 2026-10-03; Config.LuckyBlocks,
-- rules in Progression/LuckyBlocks, the save through PlayerData). Blocks come from wins
-- (PlayerData.winBlock), rewards, the shop and trades; this service is how they are held,
-- thrown and opened.
--
-- - BlockRequest (a RemoteFunction): Hold puts a copy of the block in the character's hands
--   (welded to the upper torso, so everyone sees it); Throw (sent at the throw animation's
--   release) moves it to the floor in front, in Workspace[Config.LuckyBlocks.LiveFolder], one
--   or more per player; Open (after the owner's native prompt hold) rolls the cue from the
--   block's odds row with server RNG, opens it through PlayerData.openLuckyBlock and starts
--   the rise; Move reorders
--   the hotbar and bag. Every answer is { ok = true, ... } or { ok = false, reason }.
-- - A thrown block's model carries attributes every client animates from (LuckyWorld): Owner
--   (UserId), BlockId, Kind, Phase ("Flying", "Landed", "Rising", "Burst") and PhaseAt (server
--   time), plus To (its landing CFrame). The server moves it to To when the flight ends.
-- - BlockState (a RemoteEvent): the player's blocks after every save change (deduped).
-- - The tutorial's hooks (setOpenHooks): a forced cue for game 1's Standard block and a call
--   after every open (TutorialService).
-- - Testing: the accounts in Config.Debug.Commands.UserIds get one of each
--   Config.LuckyBlocks.Test.Seed kind they lack on join, and opening one gives a fresh one of
--   the same kind in the same place (Test.Refill). Nobody else is ever given a block this way.
-- - A thrown block nobody opens goes after ReturnSeconds, or once its owner is ReturnStuds
--   away; it was never taken from the save, so it is simply back in the hotbar.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local BlockOdds = require(Shared.Progression.BlockOdds)
local Catalog = require(Shared.Progression.Catalog)
local LuckyBlocks = require(Shared.Progression.LuckyBlocks)
local Requests = require(Shared.Progression.Requests)
local Announce = require(script.Parent.Announce)
local Counters = require(script.Parent.Counters)
local PlayerData = require(script.Parent.PlayerData)

local L = Config.LuckyBlocks

type Held = { id: number, model: Model }
type Live = {
	id: number,
	kind: string,
	model: Model,
	to: CFrame,
	phase: string,
	landedAt: number, -- os.clock() it landed (the return timer)
}
export type Reply = { [string]: any }

local LuckyBlockService = {}

local held: { [Player]: Held } = {}
local live: { [Player]: { [number]: Live } } = {}
local buckets: { [Player]: Requests.Bucket } = {}
local busy: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local lastSent: { [Player]: string } = {}
local rolls = Random.new()
-- The tutorial lane (TutorialService.setOpenHooks): a forced cue for an open (game 1's
-- Standard block lands on an Uncommon cue) and a call once a block is opened. Nil: none.
local openForce: ((Player, string) -> string?)? = nil
local onOpened: ((Player, string, string) -> ())? = nil
local warnedMissing: { [string]: boolean } = {}

local function refuse(reason: string): Reply
	return { ok = false, reason = reason }
end

local function isTester(player: Player): boolean
	return table.find(Config.Debug.Commands.UserIds, player.UserId) ~= nil
end

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function liveFolder(): Folder
	local folder = workspace:FindFirstChild(L.LiveFolder)
	if folder and folder:IsA("Folder") then
		return folder
	end
	local made = Instance.new("Folder")
	made.Name = L.LiveFolder
	made.Parent = workspace
	return made
end

---------------------------------------------------------------------------------------------
-- Models
---------------------------------------------------------------------------------------------

-- The kind's template in ReplicatedStorage (Edit-mode content in the place), or nil (warned
-- once: the place was not saved with the models).
local function template(kind: string): Model?
	local row = LuckyBlocks.kind(kind)
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local model = if row and folder then folder:FindFirstChild(row.Model) else nil
	if model and model:IsA("Model") then
		return model
	end
	if not warnedMissing[kind] then
		warnedMissing[kind] = true
		warn(
			("[8ball] LuckyBlockService: no model for %s in ReplicatedStorage.%s"):format(
				kind,
				L.ModelFolder
			)
		)
	end
	return nil
end

-- A copy of the kind's model scaled so its edge is `edge` studs, nothing on it colliding or
-- touching; `anchored` for the floor, else unanchored and massless for the hands.
local function makeModel(kind: string, edge: number, anchored: boolean): Model?
	local source = template(kind)
	if source == nil then
		return nil
	end
	local row = LuckyBlocks.kind(kind) :: LuckyBlocks.Kind
	edge *= row.SizeMultiplier or 1
	local model = source:Clone()
	local _, size = model:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		model:ScaleTo(model:GetScale() * edge / longest)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
			-- Neutral base under the pack's Overlay colour maps, rather than importer grey.
			-- A part-built block (the Lucky 8) keeps its own colours.
			if d:FindFirstChildOfClass("SurfaceAppearance") then
				d.Color = Color3.new(1, 1, 1)
			end
		elseif d:IsA("SurfaceAppearance") then
			d.EmissiveStrength = (LuckyBlocks.kind(kind) :: LuckyBlocks.Kind).EmissiveStrength
				or L.Look.EmissiveStrength
		elseif d:IsA("Light") then
			d.Enabled = (LuckyBlocks.kind(kind) :: LuckyBlocks.Kind).Odds ~= "Standard"
			d.Brightness = L.Look.LightBrightness
			-- All three concrete Light classes expose Range; the shared Light type does not.
			local ranged: any = d
			ranged.Range = L.Look.LightRangeStuds
		elseif d:IsA("ParticleEmitter") then
			d.LightInfluence = L.Look.ParticleLightInfluence
		elseif d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	model:SetAttribute("Kind", kind)
	model:SetAttribute("SizeStuds", edge)
	return model
end

-- The upper torso (R15) or torso (R6) and which offset goes with it, or nil.
local function torsoOf(character: Model): (BasePart?, { number })
	local upper = character:FindFirstChild("UpperTorso")
	if upper and upper:IsA("BasePart") then
		return upper, L.Held.OffsetR15
	end
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		return torso, L.Held.OffsetR6
	end
	return nil, L.Held.OffsetR15
end

-- The character's root and humanoid while it can hold and throw (alive, not seated), or nil.
local function bodyOf(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid == nil or root == nil or not root:IsA("BasePart") then
		return nil, nil
	end
	if humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return nil, nil
	end
	return root, humanoid
end

local function dropHeld(player: Player)
	local h = held[player]
	held[player] = nil
	if h and h.model.Parent then
		h.model:Destroy()
	end
end

local function dropLive(player: Player, id: number?)
	local entries = live[player]
	if entries == nil then
		return
	end
	if id ~= nil then
		local entry = entries[id]
		entries[id] = nil
		if entry then
			entry.model:Destroy()
		end
	else
		live[player] = nil
		for _, entry in entries do
			entry.model:Destroy()
		end
	end
end

---------------------------------------------------------------------------------------------
-- BlockState
---------------------------------------------------------------------------------------------

local function flushPushes()
	local remote: RemoteEvent? = nil
	for player in dirty do
		dirty[player] = nil
		local data = PlayerData.read(player)
		if data ~= nil and player.Parent == Players then
			local state = data.LuckyBlocks
			-- Update visible countdowns after a skip receipt.
			local placed: { [number]: Live } = live[player] or {}
			for id, entry in placed do
				local block = LuckyBlocks.find(state :: any, id)
				if block then
					entry.model:SetAttribute("ReadyAt", block.ReadyAt)
				end
			end
			local h = held[player]
			if h then
				local block = LuckyBlocks.find(state :: any, h.id)
				if block then
					h.model:SetAttribute("ReadyAt", block.ReadyAt)
				end
			end
			local snapshot = { blocks = if state then LuckyBlocks.snapshot(state :: any) else {} }
			local encoded = HttpService:JSONEncode(snapshot)
			if encoded ~= lastSent[player] then
				lastSent[player] = encoded
				remote = remote or Net.get("BlockState");
				(remote :: RemoteEvent):FireClient(player, snapshot)
			end
		end
	end
end

---------------------------------------------------------------------------------------------
-- Requests
---------------------------------------------------------------------------------------------

local HANDLERS: { [string]: (Player, LuckyBlocks.Request, any) -> Reply } = {}

function HANDLERS.Hold(player: Player, r: LuckyBlocks.Request, data: any): Reply
	local id = r.id
	if id == nil then
		dropHeld(player)
		return { ok = true }
	end
	local block = LuckyBlocks.find(data.LuckyBlocks, id)
	if block == nil then
		return refuse("NotOwned")
	end
	local l = live[player]
	if l and l[id] then
		return refuse("Busy")
	end
	local current = held[player]
	if current and current.id == id and current.model.Parent then
		return { ok = true }
	end
	local character = player.Character
	local root = bodyOf(player)
	local torso: BasePart?, offset = nil, L.Held.OffsetR15
	if character then
		torso, offset = torsoOf(character)
	end
	if character == nil or root == nil or torso == nil then
		return refuse("NoBody")
	end
	local model = makeModel(block.Kind, L.Held.SizeStuds, false)
	if model == nil then
		return refuse("Error")
	end
	dropHeld(player)
	-- No bounce in the hands: the pack's AnimationController only plays on the floor.
	local controller = model:FindFirstChildOfClass("AnimationController")
	if controller then
		controller:Destroy()
	end
	local centre = torso.CFrame * CFrame.new(offset[1], offset[2], offset[3])
	local row = LuckyBlocks.kind(block.Kind) :: LuckyBlocks.Kind
	local edge = L.Held.SizeStuds * (row.SizeMultiplier or 1)
	model:PivotTo(centre * CFrame.new(0, -edge * (row.HoldCenterShare or 0.5), 0))
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if part == nil then
		model:Destroy()
		return refuse("Error")
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = part
	weld.Parent = part
	model.Name = "LuckyHeld"
	model:SetAttribute("BlockId", id)
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("ReadyAt", block.ReadyAt)
	model.Parent = character
	held[player] = { id = id, model = model }
	return { ok = true }
end

-- Where a block thrown now lands: in front of the root (short of a wall), on the floor found
-- under that spot, turned to face the thrower give or take a little.
local function landing(root: BasePart, humanoid: Humanoid): CFrame?
	local flat = root.CFrame.LookVector * Vector3.new(1, 0, 1)
	local look = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { liveFolder() }
	for _, other in Players:GetPlayers() do
		if other.Character then
			table.insert(ignore, other.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	local T = L.Throw
	for attempt = 0, L.PlacementAttempts - 1 do
		local side = math.ceil(attempt / 2) * (if attempt % 2 == 0 then -1 else 1)
		local delta = look * T.DistanceStuds + right * side * L.PlacementGapStuds
		if delta.Magnitude > L.Open.MaxDistanceStuds then
			continue
		end
		local wall = workspace:Raycast(root.Position, delta, params)
		if wall then
			delta = delta.Unit * math.max(0, wall.Distance - T.WallGapStuds)
		end
		local spot = root.Position + delta
		local floor = workspace:Raycast(
			spot + Vector3.new(0, 2, 0),
			Vector3.new(0, -T.FloorSearchStuds, 0),
			params
		)
		local feet = root.Position.Y - root.Size.Y / 2 - humanoid.HipHeight
		local at = Vector3.new(spot.X, if floor then floor.Position.Y else feet, spot.Z)
		local occupied = false
		for _, entries in live do
			for _, entry in entries do
				if (entry.to.Position - at).Magnitude < L.PlacementGapStuds then
					occupied = true
					break
				end
			end
			if occupied then
				break
			end
		end
		if not occupied then
			local jitter =
				math.rad(rolls:NextNumber(-T.LandYawJitterDegrees, T.LandYawJitterDegrees))
			return CFrame.lookAt(at, at - look) * CFrame.Angles(0, jitter, 0)
		end
	end
	return nil
end

function HANDLERS.Throw(player: Player, r: LuckyBlocks.Request, data: any): Reply
	local id = r.id :: number
	local block = LuckyBlocks.find(data.LuckyBlocks, id)
	if block == nil then
		return refuse("NotOwned")
	end
	local h = held[player]
	if h == nil or h.id ~= id or h.model.Parent == nil then
		return refuse("NotHeld")
	elseif live[player] and live[player][id] then
		return refuse("Busy")
	end
	local root, humanoid = bodyOf(player)
	if root == nil or humanoid == nil then
		return refuse("NoBody")
	end
	local model = makeModel(block.Kind, L.FloorSizeStuds, true)
	if model == nil then
		return refuse("Error")
	end
	local to = landing(root, humanoid)
	if to == nil then
		model:Destroy()
		return refuse("Busy")
	end
	local fromBox = h.model:GetBoundingBox()
	local fromCentre = fromBox.Position
	local floorEdge = L.FloorSizeStuds
		* ((LuckyBlocks.kind(block.Kind) :: LuckyBlocks.Kind).SizeMultiplier or 1)
	dropHeld(player)
	-- It starts in the hands; every client flies it to To (LuckyWorld), and the server puts it
	-- there when the flight ends.
	model:PivotTo(CFrame.new(fromCentre - Vector3.new(0, floorEdge / 2, 0)) * to.Rotation)
	model.Name = "LuckyBlock" .. player.UserId .. "_" .. id
	model:SetAttribute("Owner", player.UserId)
	model:SetAttribute("BlockId", id)
	model:SetAttribute("ReadyAt", block.ReadyAt)
	model:SetAttribute("To", to)
	model:SetAttribute("Phase", "Flying")
	model:SetAttribute("PhaseAt", serverNow())
	model.Parent = liveFolder()
	local entry: Live = {
		id = id,
		kind = block.Kind,
		model = model,
		to = to,
		phase = "Flying",
		landedAt = math.huge,
	}
	live[player] = live[player] or {}
	live[player][id] = entry
	task.delay(L.Throw.Seconds, function()
		if live[player] and live[player][id] == entry and entry.phase == "Flying" then
			entry.phase = "Landed"
			entry.landedAt = os.clock()
			model:PivotTo(to)
			model:SetAttribute("Phase", "Landed")
			model:SetAttribute("PhaseAt", serverNow())
		end
	end)
	return { ok = true }
end

local function roll(n: number): number
	return rolls:NextInteger(1, n)
end

--- The tutorial lane's hooks on Open: `force(player, kind)` names the cue the block gives
--- (only one its odds row can drop; anything else is ignored), `opened(player, kind, cueId)`
--- runs after an open.
function LuckyBlockService.setOpenHooks(
	force: ((Player, string) -> string?)?,
	opened: ((Player, string, string) -> ())?
)
	openForce, onOpened = force, opened
end

function HANDLERS.Open(player: Player, r: LuckyBlocks.Request, data: any): Reply
	local id = r.id :: number
	local entry = live[player] and live[player][id]
	if entry == nil then
		return refuse("NotOwned")
	elseif entry.phase == "Flying" then
		return refuse("NotLanded")
	elseif entry.phase ~= "Landed" then
		return refuse("Busy")
	end
	local root = bodyOf(player)
	if root == nil then
		return refuse("NoBody")
	end
	local reach = L.Open.MaxDistanceStuds + L.Open.SlackStuds
	if (root.Position - entry.to.Position).Magnitude > reach then
		return refuse("TooFar")
	end
	local block = LuckyBlocks.find(data.LuckyBlocks, id)
	local kind = if block then LuckyBlocks.kind(block.Kind) else nil
	if block == nil or kind == nil then
		dropLive(player, id)
		return refuse("NotOwned")
	end
	local plan, why = PlayerData.planLuckyOpen(player, id, roll)
	if plan == nil then
		return refuse(
			if why == "NotReady" or why == "NotOwned" or why == "NotLoaded" then why else "Error"
		)
	end
	-- The tutorial's forced cue (never a Unique or Guarantee cue: those keep their roll).
	local forcedCue = if openForce
			and not plan.unique
			and not plan.forced
		then openForce(player, block.Kind)
		else nil
	if forcedCue ~= nil and BlockOdds.canDrop(plan.oddsId, forcedCue) then
		plan.cueId = forcedCue
	end
	-- A Unique cue takes its copy number from the shared counter first (yields): the block
	-- is busy meanwhile, so a second Open waits its turn.
	local copy: number? = nil
	if plan.unique then
		entry.phase = "Opening"
		local number, reason = Counters.takeUnique(plan.cueId, player.UserId)
		if live[player] == nil or live[player][id] ~= entry then
			return refuse("NotOwned")
		end
		entry.phase = "Landed"
		if number == nil then
			warn(
				("[8ball] LuckyBlockService: no copy of %s (%s)"):format(
					plan.cueId,
					tostring(reason)
				)
			)
			return refuse("Error")
		end
		copy = number
	end
	local ok, opened, place = PlayerData.openLuckyBlock(player, id, plan, copy)
	if not ok then
		return refuse(
			if opened == "NotReady"
					or opened == "NotOwned"
					or opened == "NotLoaded"
				then opened
				else "Error"
		)
	end
	local cue = Catalog.get(plan.cueId) :: Catalog.Cue
	Counters.add(cue.Id, 1)
	Announce.unbox(player, cue.Id)
	if onOpened then
		task.spawn(onOpened, player, block.Kind, cue.Id)
	end
	if L.Test.Refill and isTester(player) then
		PlayerData.giveLuckyBlocks(player, block.Kind, 1, place)
	end
	-- The rise, then the burst, then it is gone.
	local now = serverNow()
	local burstAt = now + L.Rise.Seconds
	entry.phase = "Rising"
	entry.model:SetAttribute("Phase", "Rising")
	entry.model:SetAttribute("PhaseAt", now)
	task.delay(L.Rise.Seconds, function()
		if live[player] and live[player][id] == entry then
			entry.phase = "Burst"
			entry.model:SetAttribute("Phase", "Burst")
			entry.model:SetAttribute("PhaseAt", serverNow())
		end
		task.wait(L.BurstSeconds)
		if live[player] and live[player][id] == entry then
			dropLive(player, id)
		elseif entry.model.Parent then
			entry.model:Destroy()
		end
	end)
	return {
		ok = true,
		cue = cue.Id,
		rarity = cue.Rarity,
		kind = block.Kind,
		tier = plan.tier, -- the Mystery block's tier roll
		oddsId = plan.oddsId,
		copy = copy, -- a Unique cue's copy number
		forced = plan.forced, -- the Guarantee gave it
		new = opened.new,
		found = opened.found,
		count = opened.count,
		burstAt = burstAt,
	}
end

function HANDLERS.Move(player: Player, r: LuckyBlocks.Request, data: any): Reply
	local id, to = r.id :: number, r.to :: number
	if LuckyBlocks.find(data.LuckyBlocks, id) == nil then
		return refuse("NotOwned")
	end
	if not PlayerData.moveLuckyBlock(player, id, to) then
		return refuse("Error")
	end
	return { ok = true }
end

local function handle(player: Player, action: any, a: any, b: any): Reply
	local bucket = buckets[player]
	if bucket == nil then
		bucket = Requests.newBucket(os.clock(), L.RateBurst)
		buckets[player] = bucket
	end
	if not Requests.take(bucket, os.clock(), L.RateBurst, L.RatePerSecond) then
		return refuse("TooFast")
	end
	local request, why = LuckyBlocks.parse(action, a, b)
	if request == nil then
		return refuse(why or "BadRequest")
	end
	local data = PlayerData.read(player)
	if data == nil or type(data.LuckyBlocks) ~= "table" then
		return refuse("NotLoaded")
	end
	if busy[player] then
		return refuse("Busy")
	end
	busy[player] = true
	local ok, reply = pcall(HANDLERS[request.action], player, request, data)
	busy[player] = nil
	if not ok then
		warn(
			("[8ball] LuckyBlockService: %s from %d failed: %s"):format(
				request.action,
				player.UserId,
				tostring(reply)
			)
		)
		return refuse("Error")
	end
	return reply
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

-- The testers' seed: one of each Seed kind the tester lacks.
local function seed(player: Player)
	if not isTester(player) then
		return
	end
	local data = PlayerData.read(player)
	if data == nil or type(data.LuckyBlocks) ~= "table" then
		return
	end
	for _, kind in L.Test.Seed do
		if LuckyBlocks.count(data.LuckyBlocks :: any, kind) == 0 then
			PlayerData.giveLuckyBlocks(player, kind, 1)
		end
	end
end

-- Thrown blocks nobody opened go back (to the hotbar: they never left the save).
local function returnStale()
	local now = os.clock()
	for player, entries in live do
		for id, entry in entries do
			if entry.phase == "Landed" then
				local root = bodyOf(player)
				local far = root == nil
					or (root.Position - entry.to.Position).Magnitude > L.ReturnStuds
				if far or now - entry.landedAt > L.ReturnSeconds then
					dropLive(player, id)
				end
			end
		end
	end
end

local started = false

function LuckyBlockService.start()
	if started then
		return
	end
	started = true
	liveFolder()
	local remote = Net.get("BlockRequest") :: RemoteFunction
	remote.OnServerInvoke = function(player: Player, action: any, a: any, b: any): Reply
		local ok, reply = pcall(handle, player, action, a, b)
		if not ok then
			warn(
				("[8ball] LuckyBlockService: a request from %d failed: %s"):format(
					player.UserId,
					tostring(reply)
				)
			)
			return refuse("Error")
		end
		return reply
	end
	PlayerData.Loaded:Connect(function(player: Player)
		lastSent[player] = nil
		dirty[player] = true
		task.spawn(seed, player)
	end)
	-- Blocks come from many mutations (wins, rewards, purchases, trades, the dev commands):
	-- every change is checked and the push is deduped (lastSent).
	PlayerData.Changed:Connect(function(player: Player)
		dirty[player] = true
	end)
	RunService.Heartbeat:Connect(flushPushes)
	local function joined(player: Player)
		player.CharacterRemoving:Connect(function()
			dropHeld(player)
		end)
		if PlayerData.isLoaded(player) then
			dirty[player] = true
			task.spawn(seed, player)
		end
	end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do
		joined(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		dropHeld(player)
		dropLive(player)
		buckets[player] = nil
		busy[player] = nil
		dirty[player] = nil
		lastSent[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(L.CheckSeconds)
			local ok, err = pcall(function(): any
				returnStale()
				return nil
			end)
			if not ok then
				warn("[8ball] LuckyBlockService: " .. tostring(err))
			end
		end
	end)
end

return LuckyBlockService
