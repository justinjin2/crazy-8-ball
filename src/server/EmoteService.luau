--!strict
-- EmoteService: the emote menu's server half (designer, 2026-10-26; Config.EmoteMenu). The
-- client plays the dance on its own character (an Animator's tracks reach everyone by
-- themselves); the server decides when it starts, so players nearby move in step, and tells
-- everyone, so each client plays its music from the dancer.
-- - EmoteRequest, rate limited: ("Play", id) -> { ok, at }: refused while the feature is off,
--   for an unknown id, or while the character cannot dance (none, dead, not R15, or held by a
--   turn: its root anchored). `at` is the server time the loop started: that of the nearest
--   player within SyncStuds already doing the same dance, else now (EmoteSync.joinAt).
--   ("Sync", userId) -> { ok, id, at }: you dance what that player dances, in step with them
--   (their `at`); they must be dancing within Sync.Studs (plus SlackStuds). A Duo dance (Gojo
--   and Geto) gives you its partner dance, and only while they have no partner yet.
--   ("Stop", how), ("Favorite", id, on) (the save's EmoteFavorites) and ("Open") (analytics).
-- - EmoteState to everyone: { userId, id, at, partner? } when a dance starts (partner: the
--   duo dancer synced with), { userId, stop = true } when it ends; one player gets
--   { favorites } on load and after each change. ("Who") answers a starting client with
--   { dancers, favorites }.
-- - A dance ends on Stop, when it plays once and is done, or when its character goes (no time
--   limit: designer, 2026-10-27); a dance with a Prop (Gojo's Bloxy Cola) holds it on the hand
--   until then.
-- - Our own emotes (Config.EmoteMenu.Custom: Popcorn, Bullseye) always start on their own
--   (never in step), a one-shot ends after its length, and their props' models are loaded
--   once into ReplicatedStorage for the clients' scenes (EmoteScene).
-- - The preview rig: a plain R15 body in ReplicatedStorage (EmotePreviewRig) the menu's cards
--   dance as silhouettes.
-- - Analytics (Funnel): the custom event Emote (id, device, Lobby or Match) and EmoteMenu
--   (device, where) for each tray opened.
local InsertService = game:GetService("InsertService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local EmotePropBuilder = require(Shared.EmotePropBuilder)
local EmoteSync = require(Shared.EmoteSync)
local Net = require(Shared.Net)
local Funnel = require(script.Parent.Funnel)
local PlayerData = require(script.Parent.PlayerData)
local Tables = require(script.Parent.TableService)

local E = Config.EmoteMenu
local C = E.Custom
local RIG_NAME = "EmotePreviewRig"
-- How a client may say a dance ended (anything else is logged as "Other").
local STOPS = { Move = true, Turn = true, Menu = true, Other = true }

local EmoteService = {}

type Dance = { id: string, at: number, since: number, prop: Instance?, partner: Player? }

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
	return EmotePropBuilder.build(E.Props, key, player.Character)
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
	local partner = dance.partner
	local theirs = partner and dancing[partner]
	if theirs and theirs.partner == player then
		theirs.partner = nil -- their duo is free for someone else
	end
	if tell then
		state():FireAllClients({ userId = player.UserId, stop = true })
	end
end

-- Start `row` on `player` with its loop from `at` (in step with `partner` for a duo).
local function begin(player: Player, row: EmoteSync.Row, at: number, partner: Player?): any
	stop(player, false)
	local dance: Dance = {
		id = row.Id,
		at = at,
		since = os.clock(),
		prop = makeProp(player, row.Prop),
		partner = partner,
	}
	dancing[player] = dance
	local theirs = partner and dancing[partner]
	if theirs then
		theirs.partner = player
	end
	state():FireAllClients({
		userId = player.UserId,
		id = row.Id,
		at = at,
		partner = if partner then partner.UserId else nil,
	})
	Funnel.event(player, "Emote", 1, row.Id, Funnel.device(player), where(player))
	-- A one-shot ends when it is done (its client stops it too; the later is a no-op).
	local ends = EmoteSync.endsAfter(row)
	if ends then
		task.delay(ends, function()
			if dancing[player] == dance then
				stop(player, true)
			end
		end)
	end
	return { ok = true, id = row.Id, at = at }
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
	local now = workspace:GetServerTimeNow()
	local here = root(player) :: BasePart
	local nearby: { EmoteSync.Nearby } = {}
	for other, dance in dancing do
		local there = root(other)
		if there and other ~= player then
			table.insert(nearby, {
				id = dance.id,
				at = dance.at,
				distance = (there.Position - here.Position).Magnitude,
			})
		end
	end
	return begin(player, row, EmoteSync.startAt(now, row, nearby, E.SyncStuds), nil)
end

-- Sync with `userId`'s dance: theirs (or its duo partner), in step with them.
local function sync(player: Player, userId: any): any
	if not E.Sync.Enabled then
		return { ok = false, reason = "Off" }
	end
	local target = if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
	local theirs = target and dancing[target]
	if target == nil or target == player or theirs == nil then
		return { ok = false, reason = "Gone" }
	end
	local why = busy(player)
	if why then
		return { ok = false, reason = why }
	end
	local here, there = root(player), root(target)
	local reach = E.Sync.Studs + E.Sync.SlackStuds
	if here == nil or there == nil or (there.Position - here.Position).Magnitude > reach then
		return { ok = false, reason = "TooFar" }
	end
	local partnered = theirs.partner ~= nil and theirs.partner ~= player
	local row, reason = EmoteSync.syncRow(E.List, theirs.id, partnered)
	if row == nil then
		return { ok = false, reason = reason }
	end
	Funnel.event(player, "EmoteSync", 1, theirs.id, Funnel.device(player), where(player))
	return begin(player, row, theirs.at, if row.Id ~= theirs.id then target else nil)
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
	elseif kind == "Sync" then
		return sync(player, a)
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
			table.insert(list, {
				userId = other.UserId,
				id = dance.id,
				at = dance.at,
				partner = if dance.partner then dance.partner.UserId else nil,
			})
		end
		local data = PlayerData.read(player)
		local favorites = EmoteSync.cleanFavorites(E.List, data and data.EmoteFavorites)
		return { ok = true, dancers = list, favorites = favorites }
	end
	return { ok = false, reason = "BadRequest" }
end

-- Our own emotes' prop models, loaded once (Config.EmoteMenu.Custom.Models) into a
-- ReplicatedStorage folder for the clients to clone; scripts inside are removed. One that does
-- not load is warned about; its dance still plays, with its hand prop only.
local function loadModels()
	local folder = Instance.new("Folder")
	folder.Name = C.FolderName
	folder.Parent = ReplicatedStorage
	local models: { [string]: number } = C.Models
	for name, id in models do
		task.spawn(function()
			local why = "?"
			for attempt = 1, math.max(C.LoadRetries, 1) do
				local ok, result = pcall(InsertService.LoadAsset, InsertService, id)
				if ok and result then
					local children = result:GetChildren()
					local model = if #children == 1 then children[1] else result
					for _, d in model:GetDescendants() do
						if d:IsA("BaseScript") or d:IsA("ModuleScript") then
							d:Destroy()
						end
					end
					model.Name = name
					model.Parent = folder
					if model ~= result then
						result:Destroy()
					end
					return
				end
				why = tostring(result)
				if attempt < C.LoadRetries then
					task.wait(C.LoadRetrySeconds)
				end
			end
			warn(
				("[8ball] EmoteService: emote model %s (%d) did not load: %s"):format(name, id, why)
			)
		end)
	end
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
	if C.Enabled then
		loadModels()
	end
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
