--!strict
-- Announce: the top banner and system chat lines everyone sees (Net "Banner"): a Legendary
-- unboxed (this server), a Mythic or Secret unboxed (every server), a Legendary block in the
-- restock shop (every server, each by itself), a Money Party, a player reaching Reyes (the first ever in every server), an ult
-- spin landing a Legendary (this server) or a Mythic (every server).
--
-- The server sends ids and names only; the client words each line from Strings.Banner
-- (src/client/Banner.luau) and adds the chat line. Payloads: { kind = "Unbox", userId, name,
-- cue, rarity }, { kind = "Party", endsAt, name }, { kind = "Reyes" | "FirstReyes", userId,
-- name }, { kind = "Ult", userId, name, ult, rarity }. `name` is the player's username
-- (Strings.Banner words it).
--
-- Reyes news, Mythic and Secret unboxes (Config.BlockOdds.Announce) and Mythic ult rolls
-- (Config.Ults.Roll.AnnounceAll) go to every server: fired here
-- at once, then published on the MessagingService
-- topic Config.Items.AnnounceTopic with this server's id, and every other server's subscriber
-- fires it for its own players (this server ignores its own message, so nobody sees it twice).
-- A subscribe that fails is tried again a few times, further apart each time.
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
local BlockOdds = require(Shared.Progression.BlockOdds)
local UltCatalog = require(Shared.Ults.Catalog)
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

-- A Reyes, unbox or ult-roll message from another server, checked before it is shown here.
local function onMessage(message: any)
	local data = if type(message) == "table" then message.Data else nil
	if type(data) ~= "table" or data.from == SERVER then
		return
	end
	local kind, userId, name = data.kind, data.userId, data.name
	if
		(kind ~= "Reyes" and kind ~= "FirstReyes" and kind ~= "Ult" and kind ~= "Unbox")
		or type(userId) ~= "number"
		or type(name) ~= "string"
		or name == ""
		or #name > MAX_NAME_LENGTH
	then
		return
	end
	if kind == "Unbox" then
		local cue = Catalog.get(data.cue)
		if cue == nil or cue.Rarity ~= data.rarity or not BlockOdds.announces(cue.Rarity) then
			return
		end
		fire({ kind = kind, userId = userId, name = name, cue = cue.Id, rarity = cue.Rarity })
		return
	elseif kind == "Ult" then
		local ult = data.ult
		if not UltCatalog.exists(ult) or UltCatalog.rarity(ult) ~= data.rarity then
			return
		end
		fire({ kind = kind, userId = userId, name = name, ult = ult, rarity = data.rarity })
		return
	end
	fire({ kind = kind, userId = userId, name = name })
end

-- Publishes a message to every other server (this one already showed it). Yields; logs a
-- failure.
local function publish(payload: { [string]: any }, what: string)
	local message = table.clone(payload)
	message.from = SERVER
	local ok, err = pcall(function()
		MessagingService:PublishAsync(I.AnnounceTopic, message)
	end)
	if not ok then
		warn(
			("[8ball] Announce: the %s news did not reach other servers: %s"):format(
				what,
				tostring(err)
			)
		)
	end
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

-- Subscribes to the cross-server topic, trying again with longer and longer waits
-- (Config.Items.AnnounceTries, AnnounceRetrySeconds, AnnounceRetryGrowth); after the last
-- failure it gives up with one warning. Yields.
local function subscribe()
	local pause = I.AnnounceRetrySeconds
	for attempt = 1, I.AnnounceTries do
		local ok, err = pcall(function(): any
			return MessagingService:SubscribeAsync(I.AnnounceTopic, onMessage)
		end)
		if ok then
			return
		elseif attempt == I.AnnounceTries then
			warn(("[8ball] Announce: cannot hear other servers: %s"):format(tostring(err)))
			return
		end
		task.wait(pause)
		pause *= I.AnnounceRetryGrowth
	end
end

--- Subscribes to the cross-server topic (Bootstrap calls this once).
function Announce.start()
	task.spawn(subscribe)
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

--- `player` unboxed `cueId`: a Legendary (BlockOdds.announcesHere) is a banner for this server,
--- a Mythic or Secret (BlockOdds.announces) for every server, Config.Items.UnboxAnnounceDelaySeconds
--- later so the opener's reel settles first. Never yields.
function Announce.unbox(player: Player, cueId: string)
	local cue = Catalog.get(cueId)
	if not isPlayer(player) or cue == nil then
		return
	end
	local everywhere = BlockOdds.announces(cue.Rarity)
	if not everywhere and not BlockOdds.announcesHere(cue.Rarity) then
		return
	end
	local payload = {
		kind = "Unbox",
		userId = player.UserId,
		name = player.Name,
		cue = cue.Id,
		rarity = cue.Rarity,
	}
	task.delay(I.UnboxAnnounceDelaySeconds, function()
		fire(payload)
		if everywhere then
			publish(payload, "unbox")
		end
	end)
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
		publish(payload, "Reyes")
	end)
end

--- `player` rolled ult `ultId` on the spin screen: a rarity in Config.Ults.Roll.AnnounceServer
--- (Legendary) is a banner for everyone in this server; one in AnnounceAll (Mythic) for everyone
--- in every server (MessagingService, like Reyes). Sent Config.Items.UnboxAnnounceDelaySeconds
--- later so the spinner's own reveal lands first. Others: nothing. Never yields.
function Announce.ult(player: Player, ultId: string)
	local rarity = UltCatalog.rarity(ultId)
	if not isPlayer(player) or rarity == nil then
		return
	end
	local roll = Config.Ults.Roll
	local everywhere = (roll.AnnounceAll :: any)[rarity] == true
	local here = everywhere or (roll.AnnounceServer :: any)[rarity] == true
	if not here then
		return
	end
	local payload = {
		kind = "Ult",
		userId = player.UserId,
		name = player.Name,
		ult = ultId,
		rarity = rarity,
	}
	task.delay(I.UnboxAnnounceDelaySeconds, function()
		fire(payload)
		if everywhere then
			publish(payload, "ult roll")
		end
	end)
end

--- A restock with block kind `kind` in it began here (the Legendary block: plan section 3):
--- the banner for everyone in this server until `endsAt` (unix). Every server picks the same
--- restock (Progression/Restock), so each announces it to its own players; nothing is
--- published. Never yields.
function Announce.restock(kind: string, endsAt: number)
	fire({ kind = "Restock", block = kind, endsAt = endsAt })
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
