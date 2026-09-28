--!strict
-- The global queue's moves against an in-memory store that behaves like MemoryStore (values
-- copied in and out, expiry, sorted ranges, failed calls). Many servers run on one clock:
-- searches come and go, the leader dies, cancels land between the leader's steps. What must
-- always hold: nobody is in two matches, a search whose Cancel said "cancelled" never moves,
-- both sides of every match are told, and close searches meet within about two ticks.
local H = require("./harness")
local Core = H.require("Matchmaking.QueueCore")
local Ticket = H.require("Matchmaking.Ticket")
local Config = H.require("Config")
local G = Config.GlobalQueue
local expect = H.expect

local function deep(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deep(x)
	end
	return out
end

-- A MemoryStore stand-in. `store.now` is the clock; `store.failNext` fails that many calls;
-- `store.beforeUpdate(map, key)` runs just before an update reads its value (another
-- server's call landing in between).
local function fakeStore(): any
	local maps: { [string]: { [string]: any } } = {}
	local store: any = { now = 0, failNext = 0, calls = 0 }
	local function mapOf(name: string): { [string]: any }
		local m = maps[name]
		if not m then
			m = {}
			maps[name] = m
		end
		return m
	end
	local function live(m: { [string]: any }, key: string): any
		local e = m[key]
		if e and e.expires <= store.now then
			m[key] = nil
			return nil
		end
		return e
	end
	local function failing(): boolean
		store.calls += 1
		if store.failNext > 0 then
			store.failNext -= 1
			return true
		end
		return false
	end
	function store.update(map: string, key: string, change: any, life: number): (boolean, any)
		if failing() then
			return false, nil
		end
		local hook = store.beforeUpdate
		if hook then
			store.beforeUpdate = nil
			hook(map, key)
			store.beforeUpdate = hook
		end
		local m = mapOf(map)
		local e = live(m, key)
		local value, sortKey = change(deep(e and e.value), e and e.sortKey)
		if value == nil then
			return true, nil
		end
		m[key] = { value = deep(value), sortKey = sortKey, expires = store.now + life }
		return true, deep(value)
	end
	function store.get(map: string, key: string): (boolean, any)
		if failing() then
			return false, nil
		end
		local e = live(mapOf(map), key)
		return true, deep(e and e.value)
	end
	function store.set(map: string, key: string, value: any, life: number, sortKey: any): boolean
		if failing() then
			return false
		end
		mapOf(map)[key] = { value = deep(value), sortKey = sortKey, expires = store.now + life }
		return true
	end
	function store.remove(map: string, key: string): boolean
		if failing() then
			return false
		end
		mapOf(map)[key] = nil
		return true
	end
	function store.range(map: string, count: number, after: any): (boolean, { any }?)
		if failing() then
			return false, nil
		end
		local m = mapOf(map)
		local all = {}
		for key in m do
			local e = live(m, key)
			if e then
				table.insert(all, { key = key, value = deep(e.value), sortKey = e.sortKey })
			end
		end
		table.sort(all, function(a: any, b: any): boolean
			local sa, sb = a.sortKey or -math.huge, b.sortKey or -math.huge
			if sa ~= sb then
				return sa < sb
			end
			return a.key < b.key
		end)
		local out = {}
		for _, e in all do
			local past = after == nil
				or (e.sortKey or -math.huge) > (after.sortKey or -math.huge)
				or (
					(e.sortKey or -math.huge) == (after.sortKey or -math.huge)
					and e.key > after.key
				)
			if past then
				table.insert(out, e)
				if #out >= count then
					break
				end
			end
		end
		return true, out
	end
	function store.peek(map: string, key: string): any
		local e = live(mapOf(map), key)
		return e and deep(e.value)
	end
	return store
end

local function reserver(): any
	local n = 0
	return function(): (string?, string?)
		n += 1
		return "code" .. n, "arena" .. n
	end
end

local function newTicket(
	id: string,
	users: { number },
	rating: number,
	at: number,
	mode: number?,
	server: string?
): any
	return Ticket.new({
		id = id,
		mode = mode or 1,
		users = users,
		rating = rating,
		at = at,
		server = server or "s1",
		home = "home-" .. (server or "s1"),
	})
end

local tests = {}

function tests.two_searches_become_one_match_both_sides_told()
	local store = fakeStore()
	local a, b = newTicket("a", { 1 }, 5, 0), newTicket("b", { 2 }, 5.5, 0, 1, "s2")
	expect(Core.post(store, a) and Core.post(store, b))
	expect(Core.lease(store, "s1", 0), "the first server leads")
	local made = Core.leaderTick(store, reserver(), 0)
	expect(#made == 1, "one match")
	local record = made[1]
	expect(record.teams[1][1] == 1 and record.teams[2][1] == 2, "the older search is team 1")
	expect(record.homes["2"] == "home-s2", "each side's way home")
	local _, va = Core.read(store, a)
	local _, vb = Core.read(store, b)
	expect(va.state == "matched" and vb.state == "matched")
	expect(
		va.match.id == record.id
			and va.match.code == vb.match.code
			and va.match.team == 1
			and vb.match.team == 2
	)
	local ok, stored = Core.readRecord(store, record.id)
	expect(ok and stored and stored.id == record.id, "the arena can read its list")
end

function tests.only_one_leader_until_its_lease_lapses()
	local store = fakeStore()
	expect(Core.lease(store, "s1", 0))
	expect(not Core.lease(store, "s2", 1), "held")
	expect(Core.lease(store, "s1", 2), "renewed by its holder")
	expect(not Core.lease(store, "s2", 2 + G.LeaseSeconds - 0.1))
	expect(Core.lease(store, "s2", 2 + G.LeaseSeconds + 0.1), "lapsed: another takes over")
end

function tests.a_cancel_before_the_claim_wins_and_nobody_moves()
	local store = fakeStore()
	local a, b = newTicket("a", { 1 }, 5, 0), newTicket("b", { 2 }, 5, 0, 1, "s2")
	Core.post(store, a)
	Core.post(store, b)
	-- b's host cancels just as the leader is about to claim b.
	local cancelled = nil
	store.beforeUpdate = function(map: string, key: string)
		if key == "b" and store.peek(map, key).state == "waiting" and cancelled == nil then
			cancelled = Core.cancel(store, b)
		end
	end
	local made = Core.leaderTick(store, reserver(), 0)
	store.beforeUpdate = nil
	expect(cancelled == "cancelled", "the cancel wins")
	expect(#made == 0, "no match")
	local _, va = Core.read(store, a)
	expect(va and va.state == "waiting", "a searches on, never told of a match")
	local _, vb = Core.read(store, b)
	expect(vb == nil, "b is out of the queue")
	expect(store.peek(G.Maps.Matches, "arena1") == nil, "the half-made list is removed")
end

function tests.a_cancel_while_claimed_is_busy_then_matched()
	local store = fakeStore()
	local a, b = newTicket("a", { 1 }, 5, 0), newTicket("b", { 2 }, 5, 0, 1, "s2")
	Core.post(store, a)
	Core.post(store, b)
	local answers = {}
	store.beforeUpdate = function(map: string, key: string)
		local v = store.peek(map, key)
		if key == "a" and v and v.state == "claimed" then
			table.insert(answers, Core.cancel(store, a))
		end
	end
	local made = Core.leaderTick(store, reserver(), 0)
	store.beforeUpdate = nil
	expect(#made == 1, "the match stands")
	expect(answers[1] == "busy", "mid-way the cancel is told to wait")
	expect(Core.cancel(store, a) == "matched", "then too late: teleport")
end

function tests.a_failed_call_is_retried_and_the_match_still_made()
	local store = fakeStore()
	Core.post(store, newTicket("a", { 1 }, 5, 0))
	Core.post(store, newTicket("b", { 2 }, 5, 0, 1, "s2"))
	-- The read fails twice, then each write after it fails once: every call is retried.
	store.failNext = 2
	local range = store.range
	store.range = function(...): (boolean, any)
		local ok, page = range(...)
		if ok then
			store.failNext = 1
		end
		return ok, page
	end
	local update = store.update
	store.update = function(...): (boolean, any)
		local ok, value = update(...)
		if ok then
			store.failNext = 1
		end
		return ok, value
	end
	local made = Core.leaderTick(store, reserver(), 0)
	expect(#made == 1, "retried through")
	expect(store.calls > 12, "and it really did fail along the way: " .. store.calls)
end

function tests.claims_take_the_time_they_are_made_and_failures_pause()
	local store = fakeStore()
	local paused = 0
	store.pause = function(seconds: number)
		paused += seconds
	end
	Core.post(store, newTicket("a", { 1 }, 5, 0))
	Core.post(store, newTicket("b", { 2 }, 5, 0, 1, "s2"))
	-- A slow tick: by the time this pair is claimed the clock reads 7, not the tick's 0.
	local claims = {}
	store.beforeUpdate = function(map: string, key: string)
		local v = store.peek(map, key)
		if v and v.state == "claimed" then
			claims[key] = v.claim.at
		end
	end
	store.failNext = 1
	local made = Core.leaderTick(store, reserver(), 0, function(): number
		return 7
	end)
	store.beforeUpdate = nil
	expect(#made == 1)
	expect(claims.a == 7 and claims.b == 7, "claimed at the clock's time")
	expect(paused == G.StoreRetrySeconds, "a failed call waits before trying again")
end

function tests.a_dead_servers_search_is_skipped()
	local store = fakeStore()
	local a = newTicket("a", { 1 }, 5, 0)
	Core.post(store, a)
	Core.post(store, newTicket("b", { 2 }, 5, 0, 1, "s2"))
	store.now = G.StaleSeconds + 1
	Core.beat(store, a, store.now) -- only a's server is alive
	local made = Core.leaderTick(store, reserver(), store.now)
	expect(#made == 0, "b's server stopped marking it")
end

function tests.a_stuck_claim_is_undone_by_its_owner()
	local store = fakeStore()
	local a = newTicket("a", { 1 }, 5, 0)
	Core.post(store, a)
	store.update(Core.ticketMap(1), "a", function(v: any, s: any): (any, any)
		return Ticket.claim(v, "arenaX", 0), s
	end, 60)
	store.now = G.ClaimTimeoutSeconds - 1
	Core.beat(store, a, store.now)
	expect(store.peek(Core.ticketMap(1), "a").state == "claimed", "not yet")
	store.now = G.ClaimTimeoutSeconds + 1
	Core.beat(store, a, store.now)
	expect(store.peek(Core.ticketMap(1), "a").state == "waiting", "the leader died: search on")
end

function tests.lobby_goes_home_only_to_an_open_server_with_room()
	local store = fakeStore()
	expect(Core.markServer(store, "lobbyA", 5, 30, 100))
	local ok, mark = Core.readServer(store, "lobbyA")
	expect(ok and mark.players == 5)
	expect(Ticket.homeOpen(mark, 110, 2, G.ServerStaleSeconds), "open, with room for two")
	expect(
		not Ticket.homeOpen(mark, 100 + G.ServerStaleSeconds + 1, 1, G.ServerStaleSeconds),
		"not marked lately: closed"
	)
	expect(not Ticket.homeOpen(mark, 110, 26, G.ServerStaleSeconds), "no room for the group")
	Core.markServer(store, "lobbyA", 0, 30, 120)
	local _, empty = Core.readServer(store, "lobbyA")
	expect(not Ticket.homeOpen(empty, 121, 1, G.ServerStaleSeconds), "empty: Roblox is closing it")
	Core.dropServer(store, "lobbyA")
	local _, gone = Core.readServer(store, "lobbyA")
	expect(not Ticket.homeOpen(gone, 121, 1, G.ServerStaleSeconds), "shut down: no mark")
	expect(not Ticket.homeOpen(nil, 0, 1, G.ServerStaleSeconds))
end

function tests.ticket_changes_refuse_the_wrong_state()
	local t = newTicket("a", { 1 }, 5, 0)
	expect(Ticket.finalize(t, "m", "c", 1) == nil, "not claimed")
	local claimed = Ticket.claim(t, "m", 0)
	expect(claimed and Ticket.claim(claimed, "n", 0) == nil, "claimed once")
	expect(Ticket.revert(claimed, "other") == nil, "only its own match undoes it")
	expect(Ticket.finalize(claimed, "other", "c", 1) == nil)
	local matched = Ticket.finalize(claimed, "m", "c", 2)
	expect(matched and matched.state == "matched" and matched.match.team == 2)
	local _, what = Ticket.cancel(matched)
	expect(what == "matched")
	expect(Ticket.beat(matched, 1, 5) == nil, "a matched ticket is not touched again")
	expect(Ticket.pairable(t, 3, 8) and not Ticket.pairable(t, 9, 8))
	expect(not Ticket.isRecord({ v = 1, teams = {} }), "a broken list is refused")
end

-- Many servers on one clock for two simulated minutes.
function tests.many_servers_never_double_match_and_stay_quick()
	local store = fakeStore()
	local seed = 12345
	local function rand(): number
		seed = (seed * 1103515245 + 12345) % 2147483648
		return seed / 2147483648
	end
	local reserve = reserver()
	local servers = {}
	for i = 1, 12 do
		table.insert(servers, {
			id = "s" .. i,
			tickets = {},
			phase = (i % 4) * 0.5,
			diesAt = if i == 1 then 40 elseif i == 5 then 70 else math.huge,
		})
	end
	local nextUser, nextTicket = 1, 1
	local matchedUsers: { [number]: string } = {}
	local cancelledTickets: { [string]: boolean } = {}
	local toldTickets: { [string]: string } = {}
	local records: { [string]: any } = {}
	local posted: { [string]: any } = {}
	local latencies = {}
	local dt = 0.25
	local t = 0
	local lastLeaderTick = -math.huge
	while t < 120 do
		store.now = t
		for _, s in servers do
			if t >= s.diesAt then
				continue
			end
			local k = math.floor((t + s.phase) / dt + 0.5)
			-- Lease every LeaseRenewSeconds; the leader pairs every MatchTickSeconds.
			if k % math.floor(G.LeaseRenewSeconds / dt) == 0 then
				s.leader = Core.lease(store, s.id, t)
			end
			if s.leader and t - lastLeaderTick >= G.MatchTickSeconds - 1e-9 then
				lastLeaderTick = t
				for _, r in Core.leaderTick(store, reserve, t) do
					records[r.id] = r
				end
			end
			-- New searches while the first 100 s last.
			if t < 100 and rand() < 0.04 then
				local mode = 1 + math.floor(rand() * 3)
				local users = {}
				for _ = 1, mode do
					table.insert(users, nextUser)
					nextUser += 1
				end
				local ticket =
					newTicket("t" .. nextTicket, users, 1 + math.floor(rand() * 46), t, mode, s.id)
				nextTicket += 1
				Core.post(store, ticket)
				posted[ticket.id] = ticket
				table.insert(s.tickets, ticket)
			end
			-- Each own ticket: poll, beat, and now and then its host cancels.
			for i = #s.tickets, 1, -1 do
				local ticket = s.tickets[i]
				if k % math.floor(G.PollSeconds / dt) == 0 then
					local _, value = Core.read(store, ticket)
					if value and value.state == "matched" then
						toldTickets[ticket.id] = value.match.id
						for _, u in ticket.users do
							expect(matchedUsers[u] == nil, "player " .. u .. " matched twice")
							matchedUsers[u] = value.match.id
						end
						table.insert(latencies, t - ticket.at)
						Core.forget(store, ticket)
						table.remove(s.tickets, i)
						continue
					end
				end
				if k % math.floor(G.HeartbeatSeconds / dt) == 0 then
					Core.beat(store, ticket, t)
				end
				if rand() < 0.004 then
					local what = Core.cancel(store, ticket)
					if what == "cancelled" then
						cancelledTickets[ticket.id] = true
						table.remove(s.tickets, i)
					end
				end
			end
		end
		t += dt
	end
	-- Every cancel that said "cancelled" was never matched; every match told both sides
	-- (unless that side's server died first).
	for id in cancelledTickets do
		expect(toldTickets[id] == nil, "cancelled ticket " .. id .. " was matched")
	end
	local made = 0
	for id, r in records do
		made += 1
		for team = 1, 2 do
			local tid = r.tickets[team]
			local owner = posted[tid].server
			local died = (owner == "s1" and r.at >= 40 - G.PollSeconds)
				or (owner == "s5" and r.at >= 70 - G.PollSeconds)
			if not died then
				expect(toldTickets[tid] == id, "ticket " .. tid .. " never heard of match " .. id)
			end
		end
	end
	expect(made >= 20, "plenty of matches: " .. made)
	-- Nothing live is left waiting with a partner available: at most one per mode.
	local waiting = { 0, 0, 0 }
	for _, s in servers do
		if s.diesAt == math.huge then
			for _, ticket in s.tickets do
				waiting[ticket.mode] += 1
			end
		end
	end
	for mode = 1, 3 do
		expect(waiting[mode] <= 1, "mode " .. mode .. " left " .. waiting[mode] .. " waiting")
	end
	-- Quick: the median search waits under the 10 s "anyone" mark, never a minute.
	table.sort(latencies)
	local median = latencies[math.max(1, math.floor(#latencies / 2))]
	expect(median <= 10.5, "median wait " .. median)
	expect(latencies[#latencies] < 60, "longest wait " .. latencies[#latencies])
end

function tests.two_close_searches_meet_within_two_ticks()
	local store = fakeStore()
	local reserve = reserver()
	local a, b = newTicket("a", { 1 }, 7, 0.3), newTicket("b", { 2 }, 7, 0.3, 1, "s2")
	local told = nil
	local t = 0.3
	Core.post(store, a)
	Core.post(store, b)
	while t < 5 and not told do
		store.now = t
		-- The leader ticks on whole seconds; owners poll every half.
		if math.abs(t - math.floor(t + 0.5)) < 1e-9 and Core.lease(store, "s3", t) then
			Core.leaderTick(store, reserve, t)
		end
		if math.abs(t / G.PollSeconds - math.floor(t / G.PollSeconds + 0.5)) < 1e-9 then
			local _, v = Core.read(store, a)
			if v and v.state == "matched" then
				told = t
			end
		end
		t += 0.05
	end
	expect(
		told ~= nil and told - 0.3 <= G.MatchTickSeconds + G.PollSeconds + 0.05,
		"told after " .. tostring(told)
	)
end

return tests
