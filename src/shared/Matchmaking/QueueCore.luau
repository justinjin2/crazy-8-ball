--!strict
-- QueueCore: the global queue's moves over a key-value store, with no Roblox in it. The
-- server passes MemoryStore (src/server/GlobalQueue); the Lune tests pass an in-memory
-- store and run many servers against it, cancels landing between steps included.
--
-- One server at a time is the leader (a lease any server may take once it lapses). The
-- leader reads every waiting search, pairs them (Matchmaker) and, pair by pair: takes a
-- reserved server, writes the arena's player list, claims both tickets, then marks both
-- matched. Every server polls its own tickets and teleports its players when one is
-- matched. A claim is invisible to the owners, so a pair that cannot be finished (one side
-- cancelled first) is undone without anyone moving.
local Config = require(script.Parent.Parent.Config)
local Matchmaker = require(script.Parent.Matchmaker)
local Ticket = require(script.Parent.Ticket)

local G = Config.GlobalQueue
local QueueCore = {}

--- What QueueCore needs from a store. Every call answers `ok` first: false means the call
--- failed (a network error), which is never the same as "declined". update runs `change`
--- on the stored value (nil if none) and answers the value it stored, or nil when the change
--- declined. Values are copied in and out, as MemoryStore does.
export type Store = {
	update: (
		map: string,
		key: string,
		change: (value: any, sortKey: any) -> (any, any),
		life: number
	) -> (boolean, any),
	get: (map: string, key: string) -> (boolean, any),
	set: (map: string, key: string, value: any, life: number, sortKey: any) -> boolean,
	remove: (map: string, key: string) -> boolean,
	-- Up to `count` entries in sort-key order after `after` ({key, sortKey}, or nil for the
	-- first page), each {key, value, sortKey}.
	range: (map: string, count: number, after: any) -> (boolean, { any }?),
	-- Waits between retries of a failed call (MemoryStore throttling needs a pause); the
	-- tests leave it out.
	pause: ((seconds: number) -> ())?,
}

--- A reserved server for a new match: its access code and its id, or nil if none could be
--- made right now.
export type Reserve = () -> (string?, string?)

function QueueCore.ticketMap(mode: number): string
	return G.Maps.Tickets .. tostring(mode)
end

--- Retries a store call a few times, StoreRetrySeconds apart when the store can wait: a
--- single failed request must not lose a match.
local function retry(call: () -> (boolean, any), pause: ((number) -> ())?): (boolean, any)
	local ok, value = false, nil
	for attempt = 1, G.StoreRetries do
		ok, value = call()
		if ok then
			return ok, value
		end
		if pause and attempt < G.StoreRetries then
			pause(G.StoreRetrySeconds)
		end
	end
	return ok, value
end

--- Put a new search in the queue.
function QueueCore.post(store: Store, ticket: Ticket.Value): boolean
	local ok = retry(function(): (boolean, any)
		return store.set(
			QueueCore.ticketMap(ticket.mode),
			ticket.id,
			ticket,
			G.TicketLifeSeconds,
			ticket.rating
		),
			nil
	end, store.pause)
	return ok
end

--- Try to be (or stay) the leader. True while this server holds the lease. A server that
--- is not the leader only reads the lease and writes it once it has lapsed, so a hundred
--- servers do not all write one key every few seconds.
function QueueCore.lease(store: Store, server: string, now: number): boolean
	local read, current = store.get(G.Maps.Lease, G.LeaseKey)
	if
		read
		and type(current) == "table"
		and current.server ~= server
		and (current["until"] or 0) > now
	then
		return false
	end
	local ok, value = store.update(G.Maps.Lease, G.LeaseKey, function(current: any): (any, any)
		if
			type(current) == "table"
			and current.server ~= server
			and (current["until"] or 0) > now
		then
			return nil, nil -- someone else holds it
		end
		return { server = server, ["until"] = now + G.LeaseSeconds }, nil
	end, G.LeaseSeconds * 2)
	return ok and type(value) == "table" and value.server == server
end

--- Every search of `mode` the leader may pair now, oldest pages first.
function QueueCore.scan(store: Store, mode: number, now: number): { Ticket.Value }
	local found = {}
	local after = nil
	local read = 0
	while read < G.MaxScan do
		local ok, page = retry(function(): (boolean, any)
			return store.range(QueueCore.ticketMap(mode), G.PageSize, after)
		end, store.pause)
		if not ok or not page or #page == 0 then
			break
		end
		for _, entry in page do
			if Ticket.pairable(entry.value, now, G.StaleSeconds) and entry.value.mode == mode then
				table.insert(found, entry.value)
			end
		end
		read += #page
		if #page < G.PageSize then
			break
		end
		local last = page[#page]
		after = { key = last.key, sortKey = last.sortKey }
	end
	return found
end

-- Run a ticket change through the store. Answers whether the change was stored.
local function change(store: Store, ticket: Ticket.Value, fn: (any) -> any): boolean
	local ok, value = retry(function(): (boolean, any)
		return store.update(
			QueueCore.ticketMap(ticket.mode),
			ticket.id,
			function(current: any, sortKey: any): (any, any)
				local new = fn(current)
				if new == nil then
					return nil, nil
				end
				return new, sortKey
			end,
			G.TicketLifeSeconds
		)
	end, store.pause)
	return ok and value ~= nil
end

--- Make one pair into a match. Answers the match record, or nil (and why) when it could
--- not be made; then neither side has moved and both search on. `clock` gives the time for
--- each claim (a slow tick must not stamp a claim with an old time, or the owner's beat
--- would undo it as stuck); without it, `now`.
function QueueCore.makeMatch(
	store: Store,
	pair: Matchmaker.Pair,
	reserve: Reserve,
	now: number,
	clock: (() -> number)?
): (any?, string?)
	local a, b = pair.a :: Ticket.Value, pair.b :: Ticket.Value
	local code, matchId = reserve()
	if not code or not matchId then
		return nil, "NoServer"
	end
	-- The list first, so the arena can read it the moment its first player arrives.
	local record = Ticket.record(matchId, a, b, now)
	local wrote = retry(function(): (boolean, any)
		return store.set(G.Maps.Matches, matchId, record, G.MatchRecordSeconds, nil), nil
	end, store.pause)
	if not wrote then
		return nil, "NoRecord"
	end
	local claimedAt = if clock then clock() else now
	if
		not change(store, a, function(v: any): any
			return Ticket.claim(v, matchId, claimedAt)
		end)
	then
		store.remove(G.Maps.Matches, matchId)
		return nil, "LostA"
	end
	if
		not change(store, b, function(v: any): any
			return Ticket.claim(v, matchId, claimedAt)
		end)
	then
		change(store, a, function(v: any): any
			return Ticket.revert(v, matchId)
		end)
		store.remove(G.Maps.Matches, matchId)
		return nil, "LostB"
	end
	-- Both are ours now: cancels answer "busy" until this is done.
	local finalA = change(store, a, function(v: any): any
		return Ticket.finalize(v, matchId, code, 1)
	end)
	local finalB = change(store, b, function(v: any): any
		return Ticket.finalize(v, matchId, code, 2)
	end)
	if not finalA or not finalB then
		-- A store outage mid-way. Whichever side was not marked is let go (its claim times
		-- out otherwise); the arena then starts without it or sends the other side on.
		if not finalA then
			change(store, a, function(v: any): any
				return Ticket.revert(v, matchId)
			end)
		end
		if not finalB then
			change(store, b, function(v: any): any
				return Ticket.revert(v, matchId)
			end)
		end
		return nil, "Unfinished"
	end
	return record, nil
end

--- The leader's work for one tick: every mode's searches paired and made into matches.
--- Answers the records made and the pairs that failed (for the logs).
function QueueCore.leaderTick(
	store: Store,
	reserve: Reserve,
	now: number,
	clock: (() -> number)?
): ({ any }, { string })
	local made, failed = {}, {}
	for mode = 1, 3 do
		local tickets = QueueCore.scan(store, mode, now)
		if #tickets >= 2 then
			for _, pair in Matchmaker.pair(tickets :: any, now) do
				local record, why = QueueCore.makeMatch(store, pair, reserve, now, clock)
				if record then
					table.insert(made, record)
				else
					table.insert(failed, ("%s+%s: %s"):format(pair.a.id, pair.b.id, why or "?"))
				end
			end
		end
	end
	return made, failed
end

--- The owner reads one of its tickets. Answers ok and the stored value (nil once gone).
function QueueCore.read(store: Store, ticket: Ticket.Value): (boolean, any)
	return store.get(QueueCore.ticketMap(ticket.mode), ticket.id)
end

--- The owner's "still here" for one of its tickets.
function QueueCore.beat(store: Store, ticket: Ticket.Value, now: number): boolean
	return change(store, ticket, function(v: any): any
		return Ticket.beat(v, now, G.ClaimTimeoutSeconds)
	end)
end

--- The owner's Cancel: "cancelled" (it is out of the queue), "matched" (too late: the
--- match stands, teleport), "busy" (the leader is finishing a match with it: ask again in a
--- moment) or "error" (the store did not answer).
function QueueCore.cancel(store: Store, ticket: Ticket.Value): string
	local outcome = "error"
	local ok = retry(function(): (boolean, any)
		return store.update(
			QueueCore.ticketMap(ticket.mode),
			ticket.id,
			function(current: any, sortKey: any): (any, any)
				local new, what = Ticket.cancel(current)
				outcome = what
				return new, if new then sortKey else nil
			end,
			G.TicketLifeSeconds
		)
	end, store.pause)
	if not ok then
		return "error"
	end
	if outcome == "gone" then
		outcome = "cancelled" -- nothing left to cancel
	end
	if outcome == "cancelled" then
		store.remove(QueueCore.ticketMap(ticket.mode), ticket.id)
	end
	return outcome
end

--- The owner is done with a matched ticket (its players are on their way).
function QueueCore.forget(store: Store, ticket: Ticket.Value)
	store.remove(QueueCore.ticketMap(ticket.mode), ticket.id)
end

--- An arena reads its player list. ok false when the store failed; record nil when absent.
function QueueCore.readRecord(store: Store, matchId: string): (boolean, any)
	local ok, record = store.get(G.Maps.Matches, matchId)
	if ok and not Ticket.isRecord(record) then
		return true, nil
	end
	return ok, record
end

--- An arena's list changes (players sent on), or a Studio fixture writes one.
function QueueCore.writeRecord(store: Store, record: any): boolean
	return store.set(G.Maps.Matches, record.id, record, G.MatchRecordSeconds, nil)
end

return QueueCore
