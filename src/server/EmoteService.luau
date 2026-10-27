--!strict
-- EmoteService: the emote menu's server half (designer, 2026-10-26; Config.EmoteMenu). The
-- client plays the dance on its own character (an Animator's tracks reach everyone by
-- themselves); the server decides when it starts, so players nearby move in step, and tells
-- everyone, so each client plays its music from the dancer.
-- - EmoteRequest, rate limited: ("Play", id) -> { ok, at }: refused while the feature is off,
--   for an unknown id, or while the character cannot dance (none, dead, not R15, or held by a
--   turn: its root anchored). `at` is the server time the loop started: that of the nearest
--   player within SyncStuds already doing the same dance, else now (EmoteSync.joinAt).
--   ("Stop", how), ("Favorite", id, on) (the save's EmoteFavorites) and ("Open") (analytics).
-- - EmoteState to everyone: { userId, id, at } when a dance starts, { userId, stop = true } when
--   it ends; one player gets { favorites } on load and after each change. ("Who") answers a
--   starting client with { dancers, favorites }.
-- - A dance ends on Stop, after MaxSeconds, or when its character goes; a dance with a Prop
--   (Gojo's Bloxy Cola) holds it on the hand until then.
-- - The preview rig: a plain R15 body in ReplicatedStorage (EmotePreviewRig) the menu's cards
--   dance as silhouettes.
-- - Analytics (Funnel): the custom event Emote (id, device, Lobby or Match) and EmoteMenu
--   (device, where) for each tray opened.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local EmoteSync = require(Shared.EmoteSync)
local Net = require(Shared.Net)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.TableService)

local E = Config.EmoteMenu
local RIG_NAME = "EmotePreviewRig"
-- How a client may say a dance ended (anything else is logged as "Other").
local STOPS = { Move = true, Turn = true, Menu = true, Other = true }

local EmoteService = {}

type Dance = { id: string, at: number, since: number, prop: Instance? }

local started = false
local dancing: { [Player]: Dance } = {}
-- Each player's request bucket: tokens and when it was last filled (os.clock).
local buckets: { [Player]: { tokens: number, at: number } } = {}

local function allow(player: Player): boolean
	local now = os.clock()
	local b = buckets[player]
	if b == nil then
		b = { tokens = E.RequestBurst, at = now }
		buckets[player] = b
	end
	b.tokens = math.min(E.RequestBurst, b.tokens + (now - b.at) * E.RequestPerSecond)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

local function state(): RemoteEvent
	return Net.get("EmoteState")
end

local function where(player: Player): string
	return if Tables.tableOf(player) ~= nil then "Match" else "Lobby"
end

local function root(player: Player): BasePart?
	local character = player.Character
	local part = character and character:FindFirstChild("HumanoidRootPart")
	return if part and part:IsA("BasePart") then part else nil
end

-- Why `player`'s character cannot dance now, or nil when it can.
local function busy(player: Player): string?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local part = root(player)
	if not humanoid or not part or humanoid.Health <= 0 then
		return "Busy"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return "Busy"
	end
	if part.Anchored then
		return "Busy" -- a turn holds the body (TableService), or a cutscene does
	end
	return nil
end

-- The prop a dance holds, welded to the hand (seen by everyone), or nil.
local function makeProp(player: Player, key: string?): Instance?
	local spec = if key then E.Props[key] else nil
	local character = player.Character
	local hand = character and spec and character:FindFirstChild(spec.Hand)
	if not spec or not hand or not hand:IsA("BasePart") then
		return nil
	end
	local part = Instance.new("Part")
	part.Name = "EmoteProp"
	part.Size = Vector3.new(spec.Size[1], spec.Size[2], spec.Size[3])
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = spec.MeshId
	mesh.TextureId = spec.TextureId
	mesh.Parent = part
	local weld = Instance.new("Weld")
	weld.Part0 = hand
	weld.Part1 = part
	weld.C0 = CFrame.new(spec.Offset[1], spec.Offset[2], spec.Offset[3])
		* CFrame.Angles(math.rad(spec.Turn[1]), math.rad(spec.Turn[2]), math.rad(spec.Turn[3]))
	weld.Parent = part
	part.CFrame = hand.CFrame * weld.C0
	part.Parent = character
	return part
end

local function stop(player: Player, tell: boolean)
	local dance = dancing[player]
	if dance == nil then
		return
	end
	dancing[player] = nil
	if dance.prop then
		dance.prop:Destroy()
	end
	if tell then
		state():FireAllClients({ userId = player.UserId, stop = true })
	end
end

local function play(player: Player, id: any): any
	local row = EmoteSync.find(E.List, id)
	if row == nil then
		return { ok = false, reason = "BadRequest" }
	end
	local why = busy(player)
	if why then
		return { ok = false, reason = why }
	end
	stop(player, false)
	local now = workspace:GetServerTimeNow()
	local here = root(player) :: BasePart
	local nearby: { EmoteSync.Nearby } = {}
	for other, dance in dancing do
		local there = root(other)
		if there then
			table.insert(nearby, {
				id = dance.id,
				at = dance.at,
				distance = (there.Position - here.Position).Magnitude,
			})
		end
	end
	local at = EmoteSync.joinAt(now, row.Id, nearby, E.SyncStuds)
	local dance: Dance =
		{ id = row.Id, at = at, since = os.clock(), prop = makeProp(player, row.Prop) }
	dancing[player] = dance
	state():FireAllClients({ userId = player.UserId, id = row.Id, at = at })
	Funnel.event(player, "Emote", 1, row.Id, Funnel.device(player), where(player))
	-- The cap: an AFK dancer stops after MaxSeconds (the client stops itself then too).
	task.delay(E.MaxSeconds, function()
		if dancing[player] == dance then
			stop(player, true)
		end
	end)
	return { ok = true, at = at }
end

local function sendFavorites(player: Player)
	local data = PlayerData.read(player)
	if data == nil then
		return
	end
	state():FireClient(
		player,
		{ favorites = EmoteSync.cleanFavorites(E.List, data.EmoteFavorites) }
	)
end

local function answer(player: Player, kind: any, a: any, b: any): any
	if not E.Enabled then
		return { ok = false, reason = "Off" }
	end
	if not allow(player) then
		return { ok = false, reason = "TooFast" }
	end
	if kind == "Play" then
		return play(player, a)
	elseif kind == "Stop" then
		stop(player, true)
		return { ok = true, how = if STOPS[a] then a else "Other" }
	elseif kind == "Favorite" then
		if EmoteSync.find(E.List, a) == nil or type(b) ~= "boolean" then
			return { ok = false, reason = "BadRequest" }
		end
		if not PlayerData.isLoaded(player) then
			return { ok = false, reason = "NotLoaded" }
		end
		local ok = PlayerData.setEmoteFavorite(player, a, b)
		sendFavorites(player)
		return { ok = ok }
	elseif kind == "Open" then
		Funnel.event(player, "EmoteMenu", 1, Funnel.device(player), where(player))
		return { ok = true }
	elseif kind == "Who" then
		-- A client starting up: who is dancing now, and its favourites.
		local list = {}
		for other, dance in dancing do
			table.insert(list, { userId = other.UserId, id = dance.id, at = dance.at })
		end
		local data = PlayerData.read(player)
		local favorites = EmoteSync.cleanFavorites(E.List, data and data.EmoteFavorites)
		return { ok = true, dancers = list, favorites = favorites }
	end
	return { ok = false, reason = "BadRequest" }
end

-- A plain R15 body for the menu's previews (the client dances copies of it in its cards).
local function buildRig()
	if ReplicatedStorage:FindFirstChild(RIG_NAME) then
		return
	end
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(
			Instance.new("HumanoidDescription"),
			Enum.HumanoidRigType.R15
		)
	end)
	if not ok or not rig then
		warn("[8ball] EmoteService: no preview rig: " .. tostring(rig))
		return
	end
	for _, item in rig:GetDescendants() do
		local drop = item:IsA("Script")
			or item:IsA("LocalScript")
			or item:IsA("Decal")
			or item:IsA("Accessory")
			or item:IsA("Clothing")
			or item:IsA("BodyColors")
		if drop then
			item:Destroy()
		end
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		if not humanoid:FindFirstChildOfClass("Animator") then
			Instance.new("Animator").Parent = humanoid
		end
	end
	local part = rig:FindFirstChild("HumanoidRootPart")
	if part and part:IsA("BasePart") then
		part.Anchored = true
	end
	rig.Name = RIG_NAME
	rig.Parent = ReplicatedStorage
end

--- Answer the emote requests and keep everyone told who dances (server, once).
function EmoteService.start()
	if started then
		return
	end
	started = true
	Net.get("EmoteRequest").OnServerInvoke = function(player: Player, kind: any, a: any, b: any)
		local ok, result = pcall(answer, player, kind, a, b)
		if not ok then
			warn(
				("[8ball] EmoteService: a request from %d failed: %s"):format(
					player.UserId,
					tostring(result)
				)
			)
			return { ok = false, reason = "BadRequest" }
		end
		return result
	end
	if not E.Enabled then
		return
	end
	task.spawn(buildRig)
	PlayerData.Loaded:Connect(sendFavorites)
	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			stop(player, true)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
		if PlayerData.isLoaded(player) then
			sendFavorites(player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		stop(player, true)
		buckets[player] = nil
	end)
end

return EmoteService
