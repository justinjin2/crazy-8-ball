--!strict
-- Trading: player-to-player trades (the approved economy plan, 2026-10-02, section 9;
-- designer, 2026-10-03: anyone in the server, no gate, the last 50 trades kept). The rules
-- are Progression/Trade; the saves change only through PlayerData; the screen is the GUI
-- lane's, on TradeRequest and TradeState (src/shared/Net.luau).
--
-- A session: one player invites another, who accepts; each sets their side ("Offer"); both
-- accept ("Ready"); Config.Trade.ConfirmSeconds later the swap runs unless anything changed
-- (any change takes both accepts back and starts the wait over).
--
-- The swap, so a crash never duplicates or loses an item:
--   1. plan it on copies of both saves (PlayerData.tradePlan): what moves, paid copies and
--      Unique numbers included;
--   2. write that plan to both players' ledger keys (DataStore, Config.Trade.LedgerStore);
--   3. swap both live saves together, refused unless it moves exactly the plan
--      (PlayerData.applyTrade), each recording the trade id;
--   4. save both now and take the entry off both ledger keys.
-- A save that loads with a ledger entry it does not hold (its server stopped between 2 and a
-- save) replays its own side (PlayerData.replayTrade). The load waits ReplayDelaySeconds first,
-- so a trade still finishing (or being called off) in the old server is settled by then.
-- Studio without DataStores: the ledger stays in this server's memory.
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Catalog = require(Shared.Progression.Catalog)
local Requests = require(Shared.Progression.Requests)
local Trade = require(Shared.Progression.Trade)
local PlayerData = require(script.Parent.PlayerData)
local Items = require(script.Parent.Items)
local Counters = require(script.Parent.Counters)

local T = Config.Trade
local IS_STUDIO = RunService:IsStudio()

type Session = {
	id: string,
	a: Player,
	b: Player,
	offers: { [Player]: { string } },
	ready: { [Player]: boolean },
	-- GUI lane (D12): what each player asked the other for (the wish list, "They want: X"),
	-- never moved by itself; a request, shown on the other's screen.
	wants: { [Player]: { string } },
	version: number, -- bumped by every change; a pending swap checks it
	confirmAt: number?, -- unix: when the swap runs (both accepted)
	busy: boolean, -- the swap is running: no changes
}

type Reply = { [string]: any }

local Trading = {}

local started = false
local tradeState: RemoteEvent? = nil
local sessions: { [Player]: Session } = {}
local invites: { [Player]: { from: Player, expiresAt: number } } = {} -- by the invited player
local buckets: { [Player]: Requests.Bucket } = {}
local store: DataStore? = nil
local storeTried = false
local studioLedger: { [string]: any } = {}
local lastWarn: { [string]: number } = {}

local function complain(what: string, err: any)
	local now = os.clock()
	if now - (lastWarn[what] or -math.huge) >= 60 then
		lastWarn[what] = now
		warn(("[8ball] Trading: %s failed: %s"):format(what, tostring(err)))
	end
end

---------------------------------------------------------------------------------------------
-- The ledger
---------------------------------------------------------------------------------------------

local function storeOf(): DataStore?
	if storeTried then
		return store
	end
	storeTried = true
	local name = if IS_STUDIO then T.LedgerStudioStore else T.LedgerStore
	local ok, result = pcall(function(): DataStore
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		complain("opening " .. name, result)
	end
	return store
end

-- Runs a transform on a player's ledger key atomically. Yields. True when it ran.
local function update(userId: number, transform: (any) -> any): boolean
	local key = tostring(userId)
	local s = storeOf()
	local ok, err = false, "no DataStore"
	if s ~= nil then
		ok, err = pcall(function(): any
			return s:UpdateAsync(key, transform)
		end)
	end
	if ok then
		return true
	elseif IS_STUDIO then
		local value = transform(studioLedger[key])
		if value ~= nil then
			studioLedger[key] = value
		end
		return true
	end
	complain("updating the ledger", err)
	return false
end

-- A player's ledger entries. Yields. nil when it could not be read.
local function readLedger(userId: number): { Trade.Entry }?
	local key = tostring(userId)
	local s = storeOf()
	if s ~= nil then
		local ok, value = pcall(function(): any
			return s:GetAsync(key)
		end)
		if ok then
			return Trade.entries(value)
		elseif not IS_STUDIO then
			complain("reading the ledger", value)
			return nil
		end
	end
	return Trade.entries(studioLedger[key])
end

local function addEntry(userId: number, entry: Trade.Entry): boolean
	return update(userId, function(stored: any): any
		return Trade.addEntry(stored, entry)
	end)
end

local function removeEntry(userId: number, id: string)
	update(userId, function(stored: any): any
		return Trade.removeEntry(stored, id)
	end)
end

---------------------------------------------------------------------------------------------
-- Sessions and the state
---------------------------------------------------------------------------------------------

local function otherOf(session: Session, player: Player): Player
	return if session.a == player then session.b else session.a
end

local function card(player: Player): { userId: number, name: string }
	return { userId = player.UserId, name = player.Name }
end

-- Paid-origin copies move only when both players may trade paid items (PolicyService; not
-- answered yet counts as no).
local function paidOk(session: Session): boolean
	return Items.tradingAllowed(session.a) == true and Items.tradingAllowed(session.b) == true
end

-- A paid lucky block (an unopened paid random item) moves only when neither player has paid
-- random items restricted (economy v4 plan 13; not answered yet counts as restricted).
local function blocksOk(session: Session): boolean
	return Items.isRestricted(session.a) == false and Items.isRestricted(session.b) == false
end

local function fire(player: Player, payload: any)
	local remote = tradeState
	if remote ~= nil and player.Parent == Players then
		remote:FireClient(player, payload)
	end
end

-- Each cue's copies in existence on both sides (the lopsided warning); with a lucky block on
-- either side, every cue's (its worth is worked out live from its odds: Trade.blockWorth).
local function copiesOf(session: Session): { [string]: number }
	local copies: { [string]: number } = {}
	local function note(id: string)
		if copies[id] == nil then
			local n = Counters.copies(id)
			if n ~= nil then
				copies[id] = n
			end
		end
	end
	local anyBlock = false
	for _, side in { session.offers[session.a], session.offers[session.b] } do
		for _, item in side do
			if string.sub(item, 1, 6) == "Block:" then
				anyBlock = true
			else
				note(item)
			end
		end
	end
	if anyBlock then
		for _, cue in Catalog.list() do
			note(cue.Id)
		end
	end
	return copies
end

-- Why the sides cannot swap now (nil: they can, or a side is still empty).
local function problemOf(session: Session): string?
	local mineA, mineB = session.offers[session.a], session.offers[session.b]
	if #mineA == 0 or #mineB == 0 then
		return nil
	end
	local ok, why =
		PlayerData.tradePlan(session.a, session.b, mineA, mineB, paidOk(session), blocksOk(session))
	return if ok then nil else why
end

local function send(session: Session)
	local problem = problemOf(session)
	local copies = copiesOf(session)
	for _, me in { session.a, session.b } do
		local other = otherOf(session, me)
		local mine, theirs = session.offers[me], session.offers[other]
		local side = Trade.lopsided(mine, theirs, copies)
		fire(me, {
			kind = "Session",
			id = session.id,
			with = card(other),
			mine = table.clone(mine),
			theirs = table.clone(theirs),
			myReady = session.ready[me] == true,
			theirReady = session.ready[other] == true,
			confirmAt = session.confirmAt,
			problem = problem,
			lopsided = if side == "A" then "Mine" elseif side == "B" then "Theirs" else nil,
			paidOk = paidOk(session),
			blocksOk = blocksOk(session), -- paid lucky blocks may move (economy v4)
			-- GUI lane (D12): both sides' offerable items ({ item, count }) and the wish list.
			myItems = PlayerData.tradeOfferable(me, paidOk(session), blocksOk(session)),
			theirItems = PlayerData.tradeOfferable(other, paidOk(session), blocksOk(session)),
			theyWant = table.clone(session.wants[other]),
			iWant = table.clone(session.wants[me]),
		})
	end
end

local function close(session: Session, reason: string, gaveA: { string }?, gaveB: { string }?)
	if sessions[session.a] == session then
		sessions[session.a] = nil
	end
	if sessions[session.b] == session then
		sessions[session.b] = nil
	end
	session.version += 1
	fire(session.a, { kind = "Closed", reason = reason, gave = gaveA, got = gaveB })
	fire(session.b, { kind = "Closed", reason = reason, gave = gaveB, got = gaveA })
end

-- Takes both accepts back (any change).
local function unready(session: Session)
	session.ready[session.a] = false
	session.ready[session.b] = false
	session.confirmAt = nil
	session.version += 1
end

---------------------------------------------------------------------------------------------
-- The swap
---------------------------------------------------------------------------------------------

local function itemsOf(moved: Trade.Moved): { string }
	local out: { string } = {}
	for _, m in moved do
		for _ = 1, m.count do
			table.insert(out, m.item)
		end
	end
	return out
end

-- Saves both and takes the entry off both ledger keys (a save that fails keeps its entry, so
-- the next load checks it). Yields.
local function settle(a: Player, b: Player, entry: Trade.Entry)
	for _, player in { a, b } do
		if PlayerData.saveNow(player, T.SaveWaitSeconds) then
			removeEntry(player.UserId, entry.id)
		end
	end
end

local function execute(session: Session, version: number)
	if sessions[session.a] ~= session or session.version ~= version or session.busy then
		return
	end
	if not (session.ready[session.a] and session.ready[session.b]) then
		return
	end
	session.busy = true
	local a, b = session.a, session.b
	local itemsA, itemsB = session.offers[a], session.offers[b]
	local ok, why, fromA, fromB =
		PlayerData.tradePlan(a, b, itemsA, itemsB, paidOk(session), blocksOk(session))
	if not ok or fromA == nil or fromB == nil then
		session.busy = false
		unready(session)
		send(session)
		return
	end
	local entry: Trade.Entry = {
		id = HttpService:GenerateGUID(false),
		at = os.time(),
		a = a.UserId,
		b = b.UserId,
		fromA = fromA,
		fromB = fromB,
	}
	local wroteA = addEntry(a.UserId, entry)
	local wroteB = wroteA and addEntry(b.UserId, entry)
	local here = a.Parent == Players and b.Parent == Players and sessions[a] == session
	local done, reason = false, if wroteA and wroteB then nil else "Error"
	if wroteA and wroteB and here then
		done, reason =
			PlayerData.applyTrade(a, b, entry, itemsA, itemsB, paidOk(session), blocksOk(session))
	end
	if not done then
		-- Nothing changed in the saves: the ledger entries go too.
		if wroteA then
			removeEntry(a.UserId, entry.id)
		end
		if wroteB then
			removeEntry(b.UserId, entry.id)
		end
		session.busy = false
		if sessions[a] == session then
			unready(session)
			send(session)
		end
		warn(("[8ball] Trading: trade %s not done: %s"):format(entry.id, tostring(reason or why)))
		return
	end
	close(session, "Done", itemsOf(fromA), itemsOf(fromB))
	task.spawn(settle, a, b, entry)
end

---------------------------------------------------------------------------------------------
-- TradeRequest
---------------------------------------------------------------------------------------------

local ACTIONS: { [string]: boolean } = {
	Invite = true,
	Accept = true,
	Decline = true,
	Offer = true,
	Ready = true,
	Cancel = true,
	History = true,
	Want = true, -- GUI lane (D12): ask for one of their items, or take the ask back
}

local function refused(reason: string): Reply
	return { ok = false, reason = reason }
end

local function loaded(player: Player): boolean
	return PlayerData.isLoaded(player) and not PlayerData.isHandedOff(player)
end

local function onRequest(player: Player, action: any, arg: any): Reply
	local now = os.clock()
	local bucket = buckets[player]
	if bucket == nil then
		bucket = Requests.newBucket(now, T.RequestBurst)
		buckets[player] = bucket
	end
	if not Requests.take(bucket, now, T.RequestBurst, T.RequestPerSecond) then
		return refused("TooFast")
	end
	if type(action) ~= "string" or not ACTIONS[action] then
		return refused("BadRequest")
	end
	if not loaded(player) then
		return refused("NotLoaded")
	end
	local session = sessions[player]
	if action == "History" then
		return { ok = true, history = PlayerData.tradeHistory(player) }
	elseif action == "Invite" then
		local target = if type(arg) == "number" then Players:GetPlayerByUserId(arg) else nil
		if target == nil or not loaded(target) then
			return refused("NotHere")
		elseif target == player then
			return refused("Self")
		elseif session ~= nil or sessions[target] ~= nil then
			return refused("Busy")
		end
		local expiresAt = os.time() + T.InviteSeconds
		invites[target] = { from = player, expiresAt = expiresAt }
		fire(target, { kind = "Invite", from = card(player), expiresAt = expiresAt })
		return { ok = true }
	elseif action == "Accept" or action == "Decline" then
		local invite = invites[player]
		if
			invite == nil
			or type(arg) ~= "number"
			or invite.from.UserId ~= arg
			or os.time() >= invite.expiresAt
		then
			return refused("NoInvite")
		end
		invites[player] = nil
		local from = invite.from
		if action == "Decline" then
			fire(from, { kind = "Declined", by = card(player) })
			return { ok = true }
		end
		if from.Parent ~= Players or not loaded(from) then
			return refused("NotHere")
		elseif session ~= nil or sessions[from] ~= nil then
			return refused("Busy")
		end
		local new: Session = {
			id = HttpService:GenerateGUID(false),
			a = from,
			b = player,
			offers = { [from] = {}, [player] = {} },
			ready = { [from] = false, [player] = false },
			wants = { [from] = {}, [player] = {} },
			version = 0,
			confirmAt = nil,
			busy = false,
		}
		sessions[from] = new
		sessions[player] = new
		send(new)
		return { ok = true }
	end
	if session == nil then
		return refused("NoSession")
	end
	if action == "Cancel" then
		if session.busy then
			return refused("Busy")
		end
		close(session, "Cancelled")
		return { ok = true }
	elseif session.busy then
		return refused("Busy")
	elseif action == "Offer" then
		local items, why = Trade.parse(arg)
		if items == nil then
			return refused(why or "BadRequest")
		end
		session.offers[player] = items
		unready(session)
		send(session)
		return { ok = true }
	elseif action == "Want" then
		-- Ask for one of the other's offerable items (or take the ask back): a highlight on
		-- their screen, at most MaxSideItems asks; nothing moves.
		local items = Trade.parse({ arg })
		if items == nil then
			return refused("BadRequest")
		end
		local item = items[1]
		local wants = session.wants[player]
		local at = table.find(wants, item)
		if at then
			table.remove(wants, at)
		else
			local other = otherOf(session, player)
			local offerable = false
			for _, entry in PlayerData.tradeOfferable(other, paidOk(session), blocksOk(session)) do
				if entry.item == item then
					offerable = true
					break
				end
			end
			if not offerable then
				return refused("NotOwned")
			elseif #wants >= T.MaxSideItems then
				return refused("Full")
			end
			table.insert(wants, item)
		end
		send(session)
		return { ok = true }
	elseif action == "Ready" then
		if arg == true then
			local other = otherOf(session, player)
			local ok, why = PlayerData.tradePlan(
				session.a,
				session.b,
				session.offers[session.a],
				session.offers[session.b],
				paidOk(session),
				blocksOk(session)
			)
			if not ok then
				return refused(why or "Error")
			end
			session.ready[player] = true
			if session.ready[other] then
				session.confirmAt = os.time() + T.ConfirmSeconds
				local version = session.version
				task.delay(T.ConfirmSeconds, execute, session, version)
			end
		else
			unready(session)
		end
		send(session)
		return { ok = true }
	end
	return refused("BadRequest")
end

---------------------------------------------------------------------------------------------
-- Loads (the ledger's replay), leaves and start
---------------------------------------------------------------------------------------------

-- A trade the save missed is replayed; one it holds is taken off the ledger. Yields.
local function checkLedger(player: Player)
	task.wait(T.ReplayDelaySeconds)
	if player.Parent ~= Players or not loaded(player) then
		return
	end
	local entries = readLedger(player.UserId)
	if entries == nil then
		return
	end
	for _, entry in entries do
		if not PlayerData.tradeApplied(player, entry.id) then
			if PlayerData.replayTrade(player, entry) then
				warn(("[8ball] Trading: replayed trade %s for %d"):format(entry.id, player.UserId))
			end
			if PlayerData.saveNow(player, T.SaveWaitSeconds) then
				removeEntry(player.UserId, entry.id)
			end
		else
			removeEntry(player.UserId, entry.id)
		end
	end
end

local function onLeave(player: Player)
	local session = sessions[player]
	if session ~= nil and not session.busy then
		close(session, "Left")
	end
	invites[player] = nil
	for invited, invite in invites do
		if invite.from == player then
			invites[invited] = nil
		end
	end
	buckets[player] = nil
end

-- Studio only: ServerStorage.TradingQA, a BindableFunction (clients cannot reach it).
--   ("request", userId, action, arg) -> the TradeRequest answer (the rate limit skipped)
--   ("ledger", userId)               -> that player's ledger entries
--   ("addEntry", userId, entry)      -> writes a ledger entry (to test the replay)
--   ("checkLedger", userId)          -> runs the load's ledger check now (no delay)
local function startQA()
	if not IS_STUDIO then
		return
	end
	local old = ServerStorage:FindFirstChild("TradingQA")
	if old then
		old:Destroy()
	end
	local hook = Instance.new("BindableFunction")
	hook.Name = "TradingQA"
	hook.OnInvoke = function(op: string, userId: number, a: any, b: any): any
		local player = Players:GetPlayerByUserId(userId)
		if op == "ledger" then
			return readLedger(userId)
		elseif op == "addEntry" then
			return addEntry(userId, a)
		end
		assert(player, "TradingQA: no player in game with that UserId")
		if op == "request" then
			buckets[player] = nil
			return onRequest(player, a, b)
		elseif op == "checkLedger" then
			local delay = T.ReplayDelaySeconds
			T.ReplayDelaySeconds = 0
			local ok, err = pcall(function(): any
				checkLedger(player)
				return nil
			end)
			T.ReplayDelaySeconds = delay
			if not ok then
				error(err, 0)
			end
			return true
		end
		error("TradingQA: unknown op " .. tostring(op))
	end
	hook.Parent = ServerStorage
end

--- Connects the remotes and the loads' ledger check (Bootstrap calls this once).
function Trading.start()
	if started then
		return
	end
	started = true
	tradeState = Net.get("TradeState")
	local request: RemoteFunction = Net.get("TradeRequest")
	request.OnServerInvoke = function(player: Player, action: any, arg: any): Reply
		local ok, result = pcall(onRequest, player, action, arg)
		if not ok then
			warn(
				("[8ball] Trading: TradeRequest from %d failed: %s"):format(
					player.UserId,
					tostring(result)
				)
			)
			return refused("Error")
		end
		return result
	end
	PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(function()
			local ok, err = pcall(function(): any
				checkLedger(player)
				return nil
			end)
			if not ok then
				warn(
					("[8ball] Trading: the ledger check for %d failed: %s"):format(
						player.UserId,
						tostring(err)
					)
				)
			end
		end)
	end)
	Players.PlayerRemoving:Connect(onLeave)
	startQA()
end

return Trading
