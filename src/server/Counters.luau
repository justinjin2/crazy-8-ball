--!strict
-- Counters: the numbers shared by every server (docs/ARCHITECTURE.md, "The economy"): copies
-- in existence of each cue, the Limited cues' numbered copies, and "firsts" (the first Reyes).
-- The math and the UpdateAsync transforms are Progression/Counts (pure, Lune-tested); this
-- module gives them DataStores, clocks and the attributes clients read.
--
-- - Copies in existence (ECONOMY 9): Counters.add keeps pending +/- per cue on this server and
--   never yields. Every Config.Items.FlushSeconds (+ jitter) and on BindToClose one UpdateAsync
--   adds them to this server's shard key (Counts.shardFor(JobId)); a failed flush keeps them
--   pending. Every ReadSeconds (+ jitter) one GetAsync per shard sums the totals. Each catalog
--   cue's number is an attribute on ReplicatedStorage.CueCounts (the attribute name is the cue
--   id): the last read's total plus what this server added since (flushed after that read
--   began, being flushed, or still pending), so a cue unboxed here counts at once. Nothing is
--   published before the first read: a count is never shown made up.
-- - Limited copies: Counters.takeLimited hands out the next number with one atomic UpdateAsync
--   per call, and remembers which player got it (Counts.takeNext), so a player asking again
--   gets the same number; the sold counts are attributes on ReplicatedStorage.LimitedSold,
--   refreshed after each take and on the read loop (none before the first read).
-- - Firsts: Counters.claimFirst sets a key once (UpdateAsync, set only if empty).
-- - Every DataStore call is in pcall and nothing here ever blocks gameplay: the loops run in
--   their own threads, and a background round waits while the DataStore budget is low
--   (Config.Items.BudgetFloor). Studio uses the _Studio stores.
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Progression.Catalog)
local Counts = require(Shared.Progression.Counts)
local Shop = require(Shared.Progression.Shop)

local I = Config.Items
local IS_STUDIO = RunService:IsStudio()
-- The shard key this server writes its copies to, for its whole life.
local SHARD_KEY = Counts.shardKey(Counts.shardFor(game.JobId, I.CountsShards))

-- The attribute folders clients read.
local COPIES_FOLDER = "CueCounts"
local SOLD_FOLDER = "LimitedSold"

local Counters = {}

---------------------------------------------------------------------------------------------
-- DataStores
---------------------------------------------------------------------------------------------

local STORE_NAMES: { [string]: string } = {
	Counts = if IS_STUDIO then I.CountsStudioStore else I.CountsStore,
	Limited = if IS_STUDIO then I.LimitedStudioStore else I.LimitedStore,
	Firsts = if IS_STUDIO then I.FirstsStudioStore else I.FirstsStore,
	Stock = if IS_STUDIO then I.StockStudioStore else I.StockStore,
}
local stores: { [string]: DataStore } = {}

-- One warning per kind of trouble a minute at most: an outage must not flood the log.
local lastWarn: { [string]: number } = {}
local function complain(what: string, err: any)
	local now = os.clock()
	if now - (lastWarn[what] or -math.huge) >= 60 then
		lastWarn[what] = now
		warn(("[8ball] Counters: %s failed: %s"):format(what, tostring(err)))
	end
end

-- The store of one kind ("Counts", "Limited", "Firsts"), or nil when DataStores cannot be
-- reached (Studio without API access): the counters then stay local and unpublished.
local function storeOf(kind: string): DataStore?
	local store = stores[kind]
	if store then
		return store
	end
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(STORE_NAMES[kind])
	end)
	if not ok then
		complain("opening " .. STORE_NAMES[kind], result)
		return nil
	end
	stores[kind] = result
	return result
end

-- Whether a background round may make `calls` requests of this type now.
local function budgetFor(kind: Enum.DataStoreRequestType, calls: number): boolean
	local ok, budget = pcall(function(): number
		return DataStoreService:GetRequestBudgetForRequestType(kind)
	end)
	return not ok or budget >= I.BudgetFloor + calls
end

---------------------------------------------------------------------------------------------
-- Published attributes
---------------------------------------------------------------------------------------------

local function folderOf(name: string): Instance
	local folder = ReplicatedStorage:FindFirstChild(name)
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = ReplicatedStorage
	end
	return folder :: Instance
end

-- Copies in existence, in parts: base (the last read's totals, every shard), written (this
-- server's flushes that finished after that read began, which it may not include), sending
-- (the flush under way) and pending (not sent yet). The count is their sum.
local base: { [string]: number } = {}
local written: { [string]: number } = {}
local sending: { [string]: number } = {}
local pending: { [string]: number } = {}
local haveRead = false
local published: { [string]: number } = {}

-- Limited copies handed out, as far as this server knows (never goes down; missing until the
-- first read or take).
local sold: { [string]: number } = {}
local soldPublished: { [string]: number } = {}

local function copiesOf(cueId: string): number
	return math.max(
		0,
		(base[cueId] or 0) + (written[cueId] or 0) + (sending[cueId] or 0) + (pending[cueId] or 0)
	)
end

local function publishCopies(cueId: string)
	if not haveRead then
		return
	end
	local n = copiesOf(cueId)
	if published[cueId] ~= n then
		published[cueId] = n
		folderOf(COPIES_FOLDER):SetAttribute(cueId, n)
	end
end

local function publishAllCopies()
	for _, cue in Catalog.list() do
		if cue.Id ~= Catalog.Default then
			publishCopies(cue.Id)
		end
	end
end

local function setSold(cueId: string, n: number)
	sold[cueId] = math.max(sold[cueId] or 0, n)
	if soldPublished[cueId] ~= sold[cueId] then
		soldPublished[cueId] = sold[cueId]
		folderOf(SOLD_FOLDER):SetAttribute(cueId, sold[cueId])
	end
end

---------------------------------------------------------------------------------------------
-- Copies in existence
---------------------------------------------------------------------------------------------

--- Adds `delta` copies of `cueId` to this server's pending count (+1 unboxed or bought, -n
--- sold). Never yields.
function Counters.add(cueId: string, delta: number)
	if not Catalog.exists(cueId) or cueId == Catalog.Default then
		warn(("[8ball] Counters.add: %s is not a counted cue"):format(tostring(cueId)))
		return
	elseif
		not (type(delta) == "number" and delta == delta and delta == math.floor(delta))
		or math.abs(delta) > Config.Save.ItemCountCap
	then
		warn(("[8ball] Counters.add: %s is not a whole number of copies"):format(tostring(delta)))
		return
	elseif delta == 0 then
		return
	end
	Counts.addInto(pending, { [cueId] = delta })
	publishCopies(cueId)
end

--- The last published total for `cueId` (nil before the first read).
function Counters.copies(cueId: string): number?
	if not haveRead or not Catalog.exists(cueId) or cueId == Catalog.Default then
		return nil
	end
	return copiesOf(cueId)
end

local flushing = false

--- Adds this server's pending copies to its shard now (one UpdateAsync; nothing when nothing
--- is pending). Yields. True when there was nothing to send or it was sent; a failed flush
--- keeps its copies pending for the next one.
function Counters.flush(): boolean
	if flushing then
		return false
	elseif next(pending) == nil then
		return true
	end
	local store = storeOf("Counts")
	if store == nil then
		return false
	end
	flushing = true
	sending = pending
	pending = {}
	local deltas = table.clone(sending)
	local ok, err = pcall(function(): any
		return store:UpdateAsync(SHARD_KEY, function(stored: any): any
			return Counts.addDeltas(stored, deltas)
		end)
	end)
	if ok then
		Counts.addInto(written, sending)
	else
		Counts.addInto(pending, sending)
		complain("the copies flush", err)
	end
	sending = {}
	flushing = false
	return ok
end

--- Reads every shard and the Limited sold counts now, and publishes them. Yields. False when a
--- shard could not be read (the last totals stay).
function Counters.refresh(): boolean
	local store = storeOf("Counts")
	if store == nil then
		return false
	end
	local ok = true
	-- The flushes that finished before this read began are in it.
	local before = table.clone(written)
	local values: { any } = {}
	for n = 1, I.CountsShards do
		local got, value = pcall(function(): any
			return store:GetAsync(Counts.shardKey(n))
		end)
		if not got then
			complain("reading the copies", value)
			ok = false
			break
		end
		values[n] = if value == nil then false else value
	end
	if ok then
		base = Counts.sum(values)
		Counts.addInto(written, before, -1)
		haveRead = true
		publishAllCopies()
	end
	Counters.readWatchedStock()
	local limited = storeOf("Limited")
	if limited then
		for _, row in Shop.limited() do
			local got, value = pcall(function(): any
				return limited:GetAsync(row.Cue)
			end)
			if got then
				setSold(row.Cue, Counts.sold(value))
			else
				complain("reading the Limited counts", value)
				ok = false
				break
			end
		end
	end
	return ok
end

---------------------------------------------------------------------------------------------
-- Limited copies and firsts
---------------------------------------------------------------------------------------------

--- Takes player `userId`'s numbered copy of a Limited cue with one atomic UpdateAsync: the
--- number they were given before if any (a retry or a rejoin after a buy that did not land;
--- even past the cap or the end), else the next one, refused past `cap` or once `endsAt`
--- (unix) has passed. Yields. Returns the copy number, or nil and a reason: "SoldOut", "Ended"
--- or "Error".
function Counters.takeLimited(
	cueId: string,
	userId: number,
	cap: number,
	endsAt: number
): (number?, string?)
	if
		Shop.limitedFor(cueId) == nil
		or type(userId) ~= "number"
		or userId ~= math.floor(userId)
		or type(cap) ~= "number"
		or cap ~= cap
		or cap < 1
		or type(endsAt) ~= "number"
		or endsAt ~= endsAt
	then
		warn(("[8ball] Counters.takeLimited: bad arguments for %s"):format(tostring(cueId)))
		return nil, "Error"
	end
	-- No early "Ended" here: only the stored value knows whether this player already has one.
	local now = os.time()
	local store = storeOf("Limited")
	if store == nil then
		return nil, "Error"
	end
	-- UpdateAsync may run the transform more than once; the last run is the one written.
	local copy: number? = nil
	local reason: string? = nil
	local count = 0
	local ok, err = pcall(function(): any
		return store:UpdateAsync(cueId, function(stored: any): any
			local value
			value, copy, reason = Counts.takeNext(stored, userId, cap, now, endsAt)
			count = Counts.sold(if value ~= nil then value else stored)
			return value
		end)
	end)
	if not ok then
		complain("taking a Limited copy", err)
		return nil, "Error"
	end
	setSold(cueId, count)
	if copy ~= nil then
		return copy, nil
	end
	return nil, reason or "Error"
end

--- How many copies of a Limited cue are handed out (the last read or take), or nil before
--- this server has read it (unknown: callers never treat it as sold out, and the atomic
--- counter refuses past the cap anyway).
function Counters.limitedSold(cueId: string): number?
	return sold[cueId]
end

-- A firsts key: a short non-empty string (DataStore keys are at most 50 characters).
local function isKey(key: any): boolean
	return type(key) == "string" and #key >= 1 and #key <= 50
end

--- Sets key `key` of the firsts store to `userId` only if it is empty. Yields. True when this
--- call set it (this player is the first). A key already holding this same userId answers true
--- again (a retried claim); a failed call is tried Config.Items.FirstRetries times.
function Counters.claimFirst(key: string, userId: number): boolean
	if not isKey(key) or not (type(userId) == "number" and userId == math.floor(userId)) then
		warn(("[8ball] Counters.claimFirst: bad arguments for %s"):format(tostring(key)))
		return false
	end
	local store = storeOf("Firsts")
	if store == nil then
		return false
	end
	for attempt = 1, I.FirstRetries do
		local first = false
		local ok, err = pcall(function(): any
			return store:UpdateAsync(key, function(stored: any): any
				local value, isFirst = Counts.claim(stored, userId)
				first = isFirst
				return value
			end)
		end)
		if ok then
			return first
		end
		complain("claiming the first " .. key, err)
		if attempt < I.FirstRetries then
			task.wait(I.FirstRetrySeconds)
		end
	end
	return false
end

--- Who holds key `key` of the firsts store (a UserId), or nil when nobody does or it could not
--- be read. Yields.
function Counters.first(key: string): number?
	if not isKey(key) then
		return nil
	end
	local store = storeOf("Firsts")
	if store == nil then
		return nil
	end
	local ok, value = pcall(function(): any
		return store:GetAsync(key)
	end)
	if not ok then
		complain("reading the first " .. key, value)
		return nil
	end
	return if type(value) == "number" then value else nil
end

---------------------------------------------------------------------------------------------
-- Shared stock (the restock shop's Legendary Case)
---------------------------------------------------------------------------------------------

-- Studio without DataStore access keeps shared stock here, so the restock can be tried.
local studioStock: { [string]: any } = {}
-- The last units-taken count seen per stock key (Counters.stockTaken).
local taken: { [string]: number } = {}

-- Runs a stock transform on key `key` atomically (UpdateAsync; Studio without DataStores: in
-- memory). Yields. True when it ran.
local function updateStock(key: string, transform: (any) -> any): boolean
	local store = storeOf("Stock")
	local ok, err = false, "no DataStore"
	if store ~= nil then
		ok, err = pcall(function(): any
			return store:UpdateAsync(key, transform)
		end)
	end
	if ok then
		return true
	elseif IS_STUDIO then
		local value = transform(studioStock[key])
		if value ~= nil then
			studioStock[key] = value
		end
		return true
	end
	complain("updating the restock stock", err)
	return false
end

--- Reserves player `userId`'s unit of shared stock `key` (at most `cap` players), keeping one
--- they hold already. Yields. Returns (true) or (false, "SoldOut" | "Error").
function Counters.reserveStock(key: string, userId: number, cap: number): (boolean, string?)
	if not isKey(key) or type(userId) ~= "number" or type(cap) ~= "number" then
		return false, "Error"
	end
	local held, reason = false, nil
	local ran = updateStock(key, function(stored: any): any
		local value
		value, held, reason = Counts.reserve(stored, userId, cap)
		taken[key] = Counts.stockTaken(if value ~= nil then value else stored)
		return value
	end)
	if not ran then
		return false, "Error"
	end
	return held, if held then nil else reason or "Error"
end

--- Gives player `userId`'s unit of shared stock `key` back (a cancelled prompt, a buy that
--- failed). Yields. True when it ran.
function Counters.releaseStock(key: string, userId: number): boolean
	if not isKey(key) or type(userId) ~= "number" then
		return false
	end
	return updateStock(key, function(stored: any): any
		local value = Counts.release(stored, userId)
		taken[key] = Counts.stockTaken(if value ~= nil then value else stored)
		return value
	end)
end

-- The stock key the shop last asked about (this restock's): the read loop reads it.
local watched: string? = nil

-- Reads shared stock `key` into `taken` (Studio without DataStores: the memory copy). Yields.
local function readStock(key: string): boolean
	local store = storeOf("Stock")
	local got, value = false, nil
	if store ~= nil then
		got, value = pcall(function(): any
			return store:GetAsync(key)
		end)
	end
	if not got and IS_STUDIO then
		got, value = true, studioStock[key]
	end
	if not got then
		complain("reading the restock stock", value)
		return false
	end
	taken[key] = Counts.stockTaken(value)
	return true
end

--- Reads the shared stock the shop last asked about again (refresh). Yields.
function Counters.readWatchedStock()
	if watched ~= nil then
		readStock(watched)
	end
end

--- Units of shared stock `key` taken, as last seen by this server (nil: not seen yet). Asking
--- about a new key reads it at once, then with every refresh (other servers' buys).
function Counters.stockTaken(key: string): number?
	if isKey(key) and key ~= watched then
		watched = key
		task.spawn(readStock, key)
	end
	return taken[key]
end

---------------------------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------------------------

local started = false

--- Starts the flush and read loops and the BindToClose flush (Bootstrap calls this once).
function Counters.start()
	if started then
		return
	end
	started = true
	folderOf(COPIES_FOLDER)
	folderOf(SOLD_FOLDER)
	local jitter = Random.new()
	-- Flush: only when something is pending, and not while the budget is low.
	task.spawn(function()
		while true do
			task.wait(I.FlushSeconds + jitter:NextNumber(0, I.FlushJitterSeconds))
			if next(pending) ~= nil and budgetFor(Enum.DataStoreRequestType.UpdateAsync, 1) then
				Counters.flush()
			end
		end
	end)
	-- Read: at once (so a new server shows counts soon), then every ReadSeconds.
	task.spawn(function()
		local reads = I.CountsShards + #Shop.limited() + 1 -- + the restock stock
		while true do
			if budgetFor(Enum.DataStoreRequestType.GetAsync, reads) then
				Counters.refresh()
			end
			task.wait(I.ReadSeconds + jitter:NextNumber(0, I.ReadJitterSeconds))
		end
	end)
	-- Shutdown: wait for a flush under way, then send what is left.
	game:BindToClose(function()
		local deadline = os.clock() + I.CloseWaitSeconds
		while flushing and os.clock() < deadline do
			task.wait(0.1)
		end
		Counters.flush()
	end)
	print(("[8ball] Counters: copies go to %s of %s"):format(SHARD_KEY, STORE_NAMES.Counts))
end

return Counters
