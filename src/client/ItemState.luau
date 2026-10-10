--!strict
-- ItemState: the client's copy of the economy's snapshots and the one way to ask the server
-- for anything in it (docs/prompts/ECONOMY_UI_PROMPT.md; the protocol is written next to each
-- remote in src/shared/Net.luau).
--
-- Snapshots (server -> this player, on load and after every change; the server's copy is the
-- truth, the client only draws it). Kinds and their remotes:
--   "Items"   ItemState    the inventory (Progression/Inventory.snapshot):
--             { cues = { { id, count, new, copy? } }, equipped,
--               seen = { id... }, rows = { { rarity, have, total, complete, claimed,
--               reward = { money }? } }, titles = { id... } }
--   "Shop"    ShopState    offers and their end times, VIP, the paid-random-items
--             restriction, a sale, the Limited shelf, first pack bought, live Robux prices
--   "Rewards" RewardState  the login streak, playtime gifts, the next streak reward, titles
-- Every reader here is tolerant: a field that is missing or the wrong type reads as empty.
--
-- Requests (RemoteFunctions ItemRequest, StoreRequest, RewardRequest): ItemState.request never
-- errors; a failed or timed-out call answers { ok = false, reason = "Network" }. One request per
-- remote is on its way at a time: a second one waits for the first to come back, then goes (at
-- most the request timeout; past that it answers { ok = false, reason = "Busy" } without
-- sending anything). A double tap never buys twice because each caller keeps its own button
-- off while its request is out.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

-- A reply: { ok: boolean, reason: string?, ... } (the rest depends on the action).
export type Reply = { [string]: any }

local ItemState = {}

-- Snapshot kinds and the RemoteEvent each arrives on.
local KINDS: { [string]: string } = {
	Items = "ItemState",
	Shop = "ShopState",
	Rewards = "RewardState",
}
local KIND_ORDER = { "Items", "Shop", "Rewards" }
-- The request remotes (Net: RemoteFunctions).
local REQUESTS: { [string]: boolean } = {
	ItemRequest = true,
	StoreRequest = true,
	RewardRequest = true,
	TradeRequest = true, -- GUI lane: the player list's Trade and the trade screen
}

local latest: { [string]: any } = {}
local events: { [string]: BindableEvent } = {}
local inFlight: { [string]: boolean } = {}
local started = false

for _, kind in KIND_ORDER do
	local event = Instance.new("BindableEvent")
	event.Name = kind .. "Changed"
	events[kind] = event
end

--- One signal per kind, fired with the new snapshot: ItemState.Changed.Items:Connect(fn).
ItemState.Changed = {
	Items = events.Items.Event,
	Shop = events.Shop.Event,
	Rewards = events.Rewards.Event,
}

--- Listen to the three snapshot remotes (once; Progression.start calls it early, so the
--- snapshot sent on load is never missed: Roblox queues a remote's events until someone
--- listens). Each remote is waited for in its own thread, so this never blocks.
function ItemState.start()
	if started then
		return
	end
	started = true
	for _, kind in KIND_ORDER do
		task.spawn(function()
			local ok, remote = pcall(Net.get, KINDS[kind])
			if not ok or typeof(remote) ~= "Instance" or not remote:IsA("RemoteEvent") then
				warn(("[8ball] ItemState: no %s remote"):format(KINDS[kind]))
				return
			end
			remote.OnClientEvent:Connect(function(payload: any)
				if type(payload) ~= "table" then
					return
				end
				latest[kind] = payload
				events[kind]:Fire(payload)
			end)
		end)
	end
end

--- The latest snapshot of a kind ("Items", "Shop", "Rewards"), or nil before the first.
function ItemState.get(kind: string): any?
	return latest[kind]
end

function ItemState.items(): any?
	return latest.Items
end

function ItemState.shop(): any?
	return latest.Shop
end

function ItemState.rewards(): any?
	return latest.Rewards
end

--- Whether a request on this remote is on its way.
function ItemState.isBusy(remoteName: string): boolean
	return inFlight[remoteName] == true
end

local function failed(reason: string): Reply
	return { ok = false, reason = reason }
end

--- Ask the server: `remoteName` is "ItemRequest", "StoreRequest" or "RewardRequest", then the
--- action and its arguments as Net.luau describes them (ids and counts only). Yields until the
--- answer (after the one already on its way on this remote, if any); never errors. The reply
--- always has `ok`, and `reason` whenever ok is false.
function ItemState.request(remoteName: string, action: string, a: any?, b: any?): Reply
	if not REQUESTS[remoteName] then
		return failed("Network")
	end
	-- Another request on this remote is on its way (a Sell, a MarkSeen): wait for it. It
	-- always comes back within the timeout, so this waits no longer than that.
	local waited = 0
	while inFlight[remoteName] do
		if waited >= Config.UI.Menu.RequestTimeoutSeconds then
			return failed("Busy")
		end
		waited += task.wait(Config.UI.Menu.RequestPollSeconds)
	end
	inFlight[remoteName] = true
	local got, remote = pcall(Net.get, remoteName)
	if not got or typeof(remote) ~= "Instance" or not remote:IsA("RemoteFunction") then
		inFlight[remoteName] = nil
		return failed("Network")
	end
	local fn = remote :: RemoteFunction
	-- The call runs in its own thread so a server that never answers only costs the timeout.
	local done = false
	local answer: any = nil
	local signal = Instance.new("BindableEvent")
	task.spawn(function()
		local ok, reply = pcall(fn.InvokeServer, fn, action, a, b)
		if done then
			return -- too late: the caller already heard "Network"
		end
		done = true
		answer = if ok then reply else nil
		signal:Fire()
	end)
	if not done then
		task.delay(Config.UI.Menu.RequestTimeoutSeconds, function()
			if not done then
				done = true
				signal:Fire()
			end
		end)
		signal.Event:Wait()
	end
	signal:Destroy()
	inFlight[remoteName] = nil
	if type(answer) ~= "table" then
		return failed("Network")
	end
	local reply: Reply = answer
	if reply.ok ~= true then
		reply.ok = false
		if type(reply.reason) ~= "string" then
			reply.reason = "Default"
		end
	end
	return reply
end

--------------------------------------------------------------------------------------------
-- Tolerant readers of the inventory snapshot
--------------------------------------------------------------------------------------------

local function list(value: any): { any }
	return if type(value) == "table" then value else {}
end

--- How many of a cue the player owns (0 when unknown).
function ItemState.cueCount(id: string): number
	local items = latest.Items
	for _, row in list(items and items.cues) do
		if type(row) == "table" and row.id == id then
			return if type(row.count) == "number" then row.count else 0
		end
	end
	return 0
end

--- The row of an owned cue ({ id, count, new, copy? }), or nil.
function ItemState.cue(id: string): any?
	local items = latest.Items
	for _, row in list(items and items.cues) do
		if type(row) == "table" and row.id == id then
			return row
		end
	end
	return nil
end

--- The equipped cue's id (the catalog's default before the snapshot arrives).
function ItemState.equipped(): string
	local items = latest.Items
	local id = items and items.equipped
	return if type(id) == "string" then id else "Classic"
end

--- Whether the player has ever owned a cue (the Index shows it in colour).
function ItemState.everOwned(id: string): boolean
	local items = latest.Items
	return table.find(list(items and items.seen), id) ~= nil
end

--- Whether an Index row (a snapshot `rows` entry) is complete with its reward not claimed yet.
function ItemState.indexRowReady(row: any): boolean
	return type(row) == "table"
		and row.complete == true
		and row.claimed ~= true
		and type(row.reward) == "table"
end

--- Whether any Index row can be claimed now, or finder's money waits (the Inventory's Index
--- tab claims it; the server's RewardReady, the Rewards tile's dot, counts the rows too).
function ItemState.indexReady(): boolean
	local items = latest.Items
	-- Finder's money waiting to be collected (economy v6) counts too.
	if type(items) == "table" and type(items.findMoney) == "number" and items.findMoney > 0 then
		return true
	end
	for _, row in list(items and items.rows) do
		if ItemState.indexRowReady(row) then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------------------
-- The shop's offer windows (the column's timer pill)
--------------------------------------------------------------------------------------------

-- The offers the Shop tile counts down: the VIP welcome offer (and its comeback window) and
-- the Starter Pack (ECONOMY 11.3, 11.4). Matched by key, case-insensitive.
local OFFER_WORDS = { "vip", "welcome", "comeback", "starter" }

local function isOfferKey(key: any): boolean
	if type(key) ~= "string" then
		return false
	end
	local lower = string.lower(key)
	for _, word in OFFER_WORDS do
		if string.find(lower, word, 1, true) then
			return true
		end
	end
	return false
end

-- An end time from an entry: a number, or a table with endsAt / EndsAt / ends (and not
-- open = false or owned/bought = true).
local function endOf(entry: any): number?
	if type(entry) == "number" then
		return entry
	end
	if type(entry) ~= "table" then
		return nil
	end
	if entry.open == false or entry.owned == true or entry.bought == true then
		return nil
	end
	local at = entry.endsAt or entry.EndsAt or entry.ends
	return if type(at) == "number" then at else nil
end

--- The soonest end (unix seconds, the server's clock: workspace:GetServerTimeNow()) of an
--- open VIP welcome offer or Starter Pack window after `now`, or nil when none is open or the
--- shop snapshot does not say. It reads `shop.offers` (a map by product key, or an array of
--- { key | id | kind, endsAt }) and, failing that, flat fields such as `welcomeEndsAt`,
--- `vipOfferEndsAt`, `starterEndsAt` or tables `vipOffer = { endsAt }`.
function ItemState.offerEndsAt(now: number): number?
	local shop = latest.Shop
	if type(shop) ~= "table" then
		return nil
	end
	local soonest: number? = nil
	local function consider(at: number?)
		if at and at > now and (soonest == nil or at < soonest) then
			soonest = at
		end
	end
	local offers = shop.offers
	if type(offers) == "table" then
		if #offers > 0 then
			for _, entry in offers do
				if type(entry) == "table" and isOfferKey(entry.key or entry.id or entry.kind) then
					consider(endOf(entry))
				end
			end
		else
			for key, entry in offers do
				if isOfferKey(key) then
					consider(endOf(entry))
				end
			end
		end
	end
	for key, entry in shop do
		if key ~= "offers" and isOfferKey(key) then
			local name = string.lower(key)
			if type(entry) == "table" or string.find(name, "ends", 1, true) then
				consider(endOf(entry))
			end
		end
	end
	return soonest
end

return ItemState
