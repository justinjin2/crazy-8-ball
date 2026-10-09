--!strict
-- Ticket: one search in the global queue as it is stored in MemoryStore, and the pure
-- changes every server makes to it through UpdateAsync. UpdateAsync may run a change more
-- than once and on a value another server just wrote, so each one reads only the value it
-- is given and returns the new value, or nil to leave it as it is.
--
-- A ticket's life:  waiting -> claimed (the leader picked it) -> matched (go to the arena)
--                   waiting -> cancelled (its host pressed Cancel)
-- The owner acts only on "matched", so a pair the leader could not finish (the other side
-- cancelled first) never sends anyone anywhere: the claim is undone (revert) and the ticket
-- searches on. Cancel works only while waiting: once claimed the match is a moment away,
-- and the Cancel is answered "busy" and tried again, ending as cancelled or matched.
--
-- Pools (designer, 2026-09-28): each ticket names its pool, Ults On or Off (`ults`), and only
-- meets its own. A waiting ticket may move to the other pool (the No-ults fallback's Yes),
-- keeping its search time; like Cancel it works only while waiting, and a claim checks the
-- pool the leader paired it in, so a ticket that moved between the leader's read and its
-- claim is never claimed into the old pool's match.
local Ticket = {}

Ticket.Version = 1

export type Value = {
	v: number,
	id: string,
	mode: number, -- players a side: 1, 2 or 3
	users: { number }, -- the side, host first
	rating: number,
	at: number, -- search start, the servers' shared clock (seconds)
	beat: number, -- last "still here" from its server
	server: string, -- the server that owns it and will teleport its players
	home: string, -- the lobby server its players return to ("" for any)
	avoid: { number }?,
	ults: boolean?, -- its pool: false for No ults; true (or missing, an older ticket) for on
	state: string, -- "waiting" | "claimed" | "matched" | "cancelled"
	claim: { match: string, at: number }?,
	match: { id: string, code: string, team: number }?,
}

--- A new waiting ticket.
function Ticket.new(
	fields: {
		id: string,
		mode: number,
		users: { number },
		rating: number,
		at: number,
		server: string,
		home: string?,
		avoid: { number }?,
		ults: boolean?, -- the pool; ults on unless false
	}
): Value
	return {
		v = Ticket.Version,
		id = fields.id,
		mode = fields.mode,
		users = table.clone(fields.users),
		rating = fields.rating,
		at = fields.at,
		beat = fields.at,
		server = fields.server,
		home = fields.home or "",
		avoid = if fields.avoid then table.clone(fields.avoid) else nil,
		ults = fields.ults ~= false,
		state = "waiting",
	}
end

local function copy(value: Value): Value
	return table.clone(value)
end

local function isValue(value: any): boolean
	return type(value) == "table" and value.v == Ticket.Version and type(value.state) == "string"
end

--- A ticket's (or a match record's) pool: ults on unless it says exactly false.
function Ticket.pool(value: any): boolean
	return type(value) ~= "table" or value.ults ~= false
end

--- The leader takes a waiting ticket for match `matchId`. `ults`, the pool it was paired in:
--- a ticket that has since moved to the other pool is not taken.
function Ticket.claim(value: any, matchId: string, now: number, ults: boolean?): Value?
	if not isValue(value) or value.state ~= "waiting" then
		return nil
	end
	if ults ~= nil and Ticket.pool(value) ~= ults then
		return nil
	end
	local new = copy(value)
	new.state = "claimed"
	new.claim = { match = matchId, at = now }
	return new
end

--- Both sides were claimed: this one is matched and its server may teleport it.
function Ticket.finalize(value: any, matchId: string, code: string, team: number): Value?
	if
		not isValue(value)
		or value.state ~= "claimed"
		or not value.claim
		or value.claim.match ~= matchId
	then
		return nil
	end
	local new = copy(value)
	new.state = "matched"
	new.claim = nil
	new.match = { id = matchId, code = code, team = team }
	return new
end

--- The other side could not be claimed: this one searches on.
function Ticket.revert(value: any, matchId: string): Value?
	if
		not isValue(value)
		or value.state ~= "claimed"
		or not value.claim
		or value.claim.match ~= matchId
	then
		return nil
	end
	local new = copy(value)
	new.state = "waiting"
	new.claim = nil
	return new
end

--- The host's Cancel. Returns the new value (or nil) and what happened: "cancelled", "busy"
--- (claimed: try again in a moment), "matched" (too late, the match stands) or "gone".
function Ticket.cancel(value: any): (Value?, string)
	if not isValue(value) then
		return nil, "gone"
	end
	if value.state == "waiting" then
		local new = copy(value)
		new.state = "cancelled"
		return new, "cancelled"
	elseif value.state == "claimed" then
		return nil, "busy"
	elseif value.state == "matched" then
		return nil, "matched"
	end
	return nil, "cancelled"
end

--- The owner moves its search to pool `ults` (the No-ults fallback's Yes), keeping `at`, its
--- search time. Returns the new value (or nil) and what happened: "switched" (it is in that
--- pool now, or already was), "busy" (claimed: try again in a moment), "matched" (too late,
--- the match stands) or "gone".
function Ticket.switchPool(value: any, ults: boolean): (Value?, string)
	if not isValue(value) then
		return nil, "gone"
	end
	if value.state == "waiting" then
		if Ticket.pool(value) == ults then
			return nil, "switched"
		end
		local new = copy(value)
		new.ults = ults
		return new, "switched"
	elseif value.state == "claimed" then
		return nil, "busy"
	elseif value.state == "matched" then
		return nil, "matched"
	end
	return nil, "gone"
end

--- The owner's "still here". Also undoes a claim older than `claimTimeout` (the leader died
--- between claiming and finishing), so the ticket searches on.
function Ticket.beat(value: any, now: number, claimTimeout: number): Value?
	if not isValue(value) then
		return nil
	end
	if value.state == "waiting" then
		local new = copy(value)
		new.beat = now
		return new
	elseif value.state == "claimed" then
		local new = copy(value)
		new.beat = now
		if value.claim and now - value.claim.at > claimTimeout then
			new.state = "waiting"
			new.claim = nil
		end
		return new
	end
	return nil
end

--- Whether the leader may pair it now: waiting, and its server marked it alive recently.
function Ticket.pairable(value: any, now: number, staleSeconds: number): boolean
	return isValue(value) and value.state == "waiting" and now - value.beat <= staleSeconds
end

--- An arena's player list, written by the leader before either side is told, so the arena
--- can read it the moment it starts. Keyed by the reserved server's id.
function Ticket.record(matchId: string, a: Value, b: Value, now: number): any
	local homes = {}
	for _, u in a.users do
		homes[tostring(u)] = a.home
	end
	for _, u in b.users do
		homes[tostring(u)] = b.home
	end
	return {
		v = Ticket.Version,
		id = matchId,
		mode = a.mode,
		teams = { table.clone(a.users), table.clone(b.users) },
		homes = homes,
		tickets = { a.id, b.id },
		ults = Ticket.pool(a), -- the arena's table plays with ults on or off (settings.abilities)
		at = now,
	}
end

--- Whether a lobby server can take `group` players back now, from its last "still open" mark
--- (QueueCore.markServer): marked within `staleSeconds`, someone still in it (an empty server
--- is closing), and room for the whole group. Otherwise they go to any lobby server.
function Ticket.homeOpen(entry: any, now: number, group: number, staleSeconds: number): boolean
	return type(entry) == "table"
		and type(entry.beat) == "number"
		and now - entry.beat <= staleSeconds
		and type(entry.players) == "number"
		and entry.players > 0
		and type(entry.max) == "number"
		and entry.players + group <= entry.max
end

-- How many bots a match record puts on side `team` (BotService's bot matches name them).
local function botsOn(record: any, team: number): number
	local n = 0
	if type(record.bots) == "table" then
		for _, spec in record.bots do
			if type(spec) == "table" and spec.team == team then
				n += 1
			end
		end
	end
	return n
end

--- Whether a stored match record is one this code can read. A side may be all bots (a bot
--- match's list names no player there).
function Ticket.isRecord(record: any): boolean
	if type(record) ~= "table" or record.v ~= Ticket.Version or type(record.teams) ~= "table" then
		return false
	end
	if type(record.mode) ~= "number" or type(record.homes) ~= "table" then
		return false
	end
	if record.ults ~= nil and type(record.ults) ~= "boolean" then
		return false
	end
	for team = 1, 2 do
		local list = record.teams[team]
		if
			type(list) ~= "table"
			or #list + botsOn(record, team) < 1
			or #list + botsOn(record, team) > record.mode
		then
			return false
		end
		for _, u in list do
			if type(u) ~= "number" then
				return false
			end
		end
	end
	return true
end

return Ticket
