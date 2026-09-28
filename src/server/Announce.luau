--!strict
-- Announce: the top banner and system chat lines everyone sees (Net "Banner"): a Mythic or
-- Secret unboxed, a Money Party, a player reaching Reyes (the first ever in every server).
--
-- The server sends ids and names only; the client words each line from Strings.Banner
-- (src/client/Banner.luau) and adds the chat line. Payloads: { kind = "Unbox", userId, name,
-- cue, rarity }, { kind = "Party", endsAt, name }, { kind = "Reyes" | "FirstReyes", userId,
-- name }. `name` is the player's username (Strings.Banner words it).
--
-- Reyes news goes to every server: fired here at once, then published on the MessagingService
-- topic Config.Items.AnnounceTopic with this server's id, and every other server's subscriber
-- fires it for its own players (this server ignores its own message, so nobody sees it twice).
-- The first Reyes ever (Counters.claimFirst) also gets the one-of-one title
-- (Config.Items.FirstReyesTitle) through PlayerData.addTitle; a first who left before the title
-- landed gets it on their next join here (a Reyes player without it looks the key up once).
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Catalog = require(Shared.Progression.Catalog)
local Cases = require(Shared.Progression.Cases)
local Counters = require(script.Parent.Counters)
local PlayerData = require(script.Parent.PlayerData)

local I = Config.Items
-- This server's id in cross-server messages: its JobId live; Studio has none, so a fresh one.
local SERVER = if game.JobId ~= "" then game.JobId else "studio-" .. HttpService:GenerateGUID(false)
-- The firsts key of the first player ever to reach Reyes (ECONOMY 4.6).
local REYES_KEY = "Reyes"
-- The rank tier whose players may hold the first-Reyes title (PlayerData's RankTier attribute).
local REYES_TIER = "Reyes"
-- A name in a message from another server longer than this is not a Roblox name: dropped.
local MAX_NAME_LENGTH = 50

local Announce = {}

-- The Money Party running here, for players who join while it runs.
local party: { kind: string, endsAt: number, name: string? }? = nil

local function isPlayer(x: any): boolean
	return typeof(x) == "Instance" and x:IsA("Player")
end

-- The banner to everyone in this server (or one player). Never errors.
local function fire(payload: { [string]: any }, only: Player?)
	local ok, err = pcall(function()
		local remote = Net.get("Banner") :: RemoteEvent
		if only then
			remote:FireClient(only, payload)
		else
			remote:FireAllClients(payload)
		end
	end)
	if not ok then
		warn(
			("[8ball] Announce: the %s banner failed: %s"):format(
				tostring(payload.kind),
				tostring(err)
			)
		)
	end
end

-- A Reyes message from another server, checked before it is shown here.
local function onMessage(message: any)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" or data.from == SERVER then
		return
	end
	local kind, userId, name = data.kind, data.userId, data.name
	if
		(kind ~= "Reyes" and kind ~= "FirstReyes")
		or type(userId) ~= "number"
		or type(name) ~= "string"
		or name == ""
		or #name > MAX_NAME_LENGTH
	then
		return
	end
	fire({ kind = kind, userId = userId, name = name })
end

-- The title of the first Reyes, for a first whose title never landed (they left at once).
local function titleIfFirst(player: Player)
	if player:GetAttribute("RankTier") ~= REYES_TIER then
		return
	end
	local data = PlayerData.read(player)
	local titles = if data then data.Titles else nil
	if type(titles) ~= "table" or titles[I.FirstReyesTitle] == true then
		return
	end
	if Counters.first(REYES_KEY) == player.UserId and PlayerData.isLoaded(player) then
		PlayerData.addTitle(player, I.FirstReyesTitle)
	end
end

--- Subscribes to the cross-server topic (Bootstrap calls this once).
function Announce.start()
	task.spawn(function()
		local ok, err = pcall(function(): any
			return MessagingService:SubscribeAsync(I.AnnounceTopic, onMessage)
		end)
		if not ok then
			warn(("[8ball] Announce: cannot hear other servers: %s"):format(tostring(err)))
		end
	end)
	Players.PlayerAdded:Connect(function(player: Player)
		local running = party
		if running and running.endsAt > os.time() then
			fire(running, player)
		end
	end)
	PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(titleIfFirst, player)
	end)
end

--- `player` unboxed `cueId`: announced to this server when its rarity announces
--- (Cases.announces), Config.Items.UnboxAnnounceDelaySeconds later so the opener's reel settles
--- first. Never yields.
function Announce.unbox(player: Player, cueId: string)
	local cue = Catalog.get(cueId)
	if not isPlayer(player) or cue == nil or not Cases.announces(cue.Rarity) then
		return
	end
	local payload = {
		kind = "Unbox",
		userId = player.UserId,
		name = player.Name,
		cue = cue.Id,
		rarity = cue.Rarity,
	}
	task.delay(I.UnboxAnnounceDelaySeconds, fire, payload)
end

--- `player` just reached Reyes: claims the global first (Counters.claimFirst) and tells every
--- server. Yields in its own thread; returns at once.
function Announce.reyes(player: Player)
	if not isPlayer(player) then
		return
	end
	local userId, name = player.UserId, player.Name
	task.spawn(function()
		local first = Counters.claimFirst(REYES_KEY, userId)
		if first and not PlayerData.addTitle(player, I.FirstReyesTitle) then
			-- Already held (a retried claim), or they left: their next join gives it.
			print(("[8ball] Announce: the first Reyes title for %d not added now"):format(userId))
		end
		local payload =
			{ kind = if first then "FirstReyes" else "Reyes", userId = userId, name = name }
		fire(payload)
		local message = table.clone(payload)
		message.from = SERVER
		local ok, err = pcall(function()
			MessagingService:PublishAsync(I.AnnounceTopic, message)
		end)
		if not ok then
			warn(
				("[8ball] Announce: the Reyes news did not reach other servers: %s"):format(
					tostring(err)
				)
			)
		end
	end)
end

--- A Money Party is on until `endsAt` (unix), bought by `buyerName`: the banner for everyone
--- here (and anyone who joins while it runs).
function Announce.party(endsAt: number, buyerName: string)
	if type(endsAt) ~= "number" or endsAt ~= endsAt or endsAt <= os.time() then
		return
	end
	local name = if type(buyerName) == "string" and buyerName ~= "" then buyerName else nil
	local payload = { kind = "Party", endsAt = endsAt, name = name }
	party = payload
	fire(payload)
end

return Announce
