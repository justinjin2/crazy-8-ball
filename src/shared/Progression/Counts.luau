--!strict
-- Counts: the pure half of the numbers every server shares (src/server/Counters.luau;
-- docs/ARCHITECTURE.md, "The economy"): which shard key a server writes its copies in existence
-- to, the DataStore UpdateAsync transforms (adding a server's pending copies to its shard,
-- handing out the next numbered Limited copy, setting a "first" only if it is empty), and
-- summing the shards. Pure: no Instances, no Roblox APIs, no clocks (the caller passes `now`);
-- Lune-tested (tests/counts_test.luau).
--
-- A transform may run more than once (UpdateAsync retries it on a conflict), so each one here
-- only reads its arguments and returns a fresh value: never a change to what it was given.
--
-- What the stores hold:
--   copies   one key per shard ("shard_3"): { [cueId] = copies added by the servers writing
--            to it } (a shard's number can be negative: sold on one shard, unboxed on another;
--            the sum over every shard is the count)
--   Limited  one key per Limited cue: { n = numbered copies handed out, by = { [UserId as a
--            string] = the copy number that player was given } }, so a buy that did not land
--            (the player left while it was saving) gets the same number on a retry instead of
--            burning a new one. An older value is a plain number (n alone, nobody recorded).
--            Each buyer adds about 20 characters and a DataStore value holds at most 4 MB, so
--            a Limited's Cap must stay far under about 200,000 (the Beta Cue's 1,000 is
--            about 20 KB).
--   firsts   one key per "first" ("Reyes"): the UserId that got there first
local Config = require(script.Parent.Parent.Config)

local Counts = {}

-- A whole number (never NaN or infinite).
local function isWhole(x: any): boolean
	return type(x) == "number"
		and x == x
		and x ~= math.huge
		and x ~= -math.huge
		and x == math.floor(x)
end

-- An id a count may be kept under (a catalog id's shape: a short non-empty string).
local function isId(x: any): boolean
	return type(x) == "string" and #x >= 1 and #x <= Config.Save.MaxIdLength
end

--- The shard (1..shards) a server writes to, from its JobId: a djb2 hash, so every server
--- keeps one shard for its whole life and servers spread evenly. Studio's empty JobId is 1.
function Counts.shardFor(jobId: string, shards: number): number
	if jobId == "" or shards <= 1 then
		return 1
	end
	local h = 5381
	for i = 1, #jobId do
		h = (h * 33 + string.byte(jobId, i)) % 4294967296
	end
	return h % shards + 1
end

--- The DataStore key of shard `n`.
function Counts.shardKey(n: number): string
	return "shard_" .. tostring(n)
end

--- Adds `deltas` into `target` in place (times `sign`, default 1), dropping entries that reach
--- 0. Skips anything that is not an id with a whole number. Returns `target`.
function Counts.addInto(
	target: { [string]: number },
	deltas: { [string]: number },
	sign: number?
): { [string]: number }
	local s = sign or 1
	for id, n in deltas do
		if isId(id) and isWhole(n) and n ~= 0 then
			local total = (target[id] or 0) + n * s
			if total ~= 0 then
				target[id] = total
			else
				target[id] = nil
			end
		end
	end
	return target
end

--- The copies transform: a fresh shard value, the stored one's valid entries (anything else in
--- it is dropped: a key that is not an id, a value that is not a whole number) plus `deltas`.
--- Entries that come to 0 are left out, so the value stays small.
function Counts.addDeltas(stored: any, deltas: { [string]: number }): { [string]: number }
	local value: { [string]: number } = {}
	if type(stored) == "table" then
		for id, n in stored do
			if isId(id) and isWhole(n) and n ~= 0 then
				value[id] = n
			end
		end
	end
	return Counts.addInto(value, deltas)
end

--- The totals over every shard's stored value (nil or junk shards count as empty). A total is
--- never below 0 (a count read between two shards' writes could dip for a moment).
function Counts.sum(shards: { any }): { [string]: number }
	local totals: { [string]: number } = {}
	for _, stored in shards do
		if type(stored) == "table" then
			Counts.addInto(totals, stored)
		end
	end
	for id, n in totals do
		if n < 0 then
			totals[id] = nil
		end
	end
	return totals
end

--- `totals` with each renamed cue's old id added into its new id (Config.Items.RenamedCues:
--- [old] = new), so copies counted before a rename still count. Changes `totals` and returns it.
function Counts.renamed(
	totals: { [string]: number },
	renames: { [string]: string }
): { [string]: number }
	for old, new in renames do
		local n = totals[old]
		if n ~= nil then
			totals[new] = (totals[new] or 0) + n
			totals[old] = nil
		end
	end
	return totals
end

-- A stored Limited value (the shape above).
export type LimitedValue = { n: number, by: { [string]: number } }

-- A stored Limited value read safely: the copies handed out and a fresh copy of who got which
-- number. An old plain number is the count with nobody recorded; junk entries are dropped and
-- anything else reads as none. The count is never below the biggest number recorded, so a new
-- number never repeats one.
local function readLimited(stored: any): (number, { [string]: number })
	local by: { [string]: number } = {}
	local n = 0
	if isWhole(stored) then
		n = math.max(0, stored)
	elseif type(stored) == "table" then
		if isWhole(stored.n) then
			n = math.max(0, stored.n)
		end
		if type(stored.by) == "table" then
			for who, copy in stored.by do
				if isId(who) and isWhole(copy) and copy >= 1 then
					by[who] = copy
					n = math.max(n, copy)
				end
			end
		end
	end
	return n, by
end

--- How many numbered copies a stored Limited value says were handed out, either shape (0 for
--- nothing or junk).
function Counts.sold(stored: any): number
	local n = readLimited(stored)
	return n
end

--- The Limited transform for player `userId`: (the value to store, or nil to write nothing;
--- their copy number, or nil; the reason when there is none). A player who already has a
--- number gets that same one again and nothing is written (a retry, or a rejoin after a buy
--- that did not land), even past the cap or the end: it was handed out before. Otherwise
--- "Ended" at or past `endsAt` (unix seconds), "SoldOut" once `cap` copies are out, else the
--- next number, recorded under their id.
function Counts.takeNext(
	stored: any,
	userId: number,
	cap: number,
	now: number,
	endsAt: number
): (LimitedValue?, number?, string?)
	local n, by = readLimited(stored)
	local who = tostring(userId)
	local mine = by[who]
	if mine ~= nil then
		return nil, mine, nil
	end
	if not (now < endsAt) then
		return nil, nil, "Ended"
	end
	if not (n < cap) then
		return nil, nil, "SoldOut"
	end
	by[who] = n + 1
	return { n = n + 1, by = by }, n + 1, nil
end

--- The firsts transform: (the value to store, or nil to write nothing; whether `userId` is the
--- first). An empty key takes `userId`; a key already holding `userId` answers true again
--- without writing (a retried claim); any other holder answers false.
function Counts.claim(stored: any, userId: number): (number?, boolean)
	if stored == nil then
		return userId, true
	end
	return nil, stored == userId
end

---------------------------------------------------------------------------------------------
-- Shared stock (the restock shop's Legendary block: Config.Shop.Restock.Legendary.GlobalStock)
---------------------------------------------------------------------------------------------

-- The stored players holding a unit, as a fresh map (anything else reads as none).
local function readStock(stored: any): { [string]: boolean }
	local by: { [string]: boolean } = {}
	if type(stored) == "table" and type(stored.by) == "table" then
		for who, held in stored.by do
			if type(who) == "string" and held == true then
				by[who] = true
			end
		end
	end
	return by
end

local function holders(by: { [string]: boolean }): number
	local n = 0
	for _ in by do
		n += 1
	end
	return n
end

--- Units of a shared stock taken.
function Counts.stockTaken(stored: any): number
	return holders(readStock(stored))
end

--- The reserve transform: (the value to store, or nil to write nothing; whether `userId` holds
--- a unit now; why not). A player already holding one keeps it (a retry); otherwise a unit is
--- taken while fewer than `cap` are, else "SoldOut".
function Counts.reserve(
	stored: any,
	userId: number,
	cap: number
): ({ by: { [string]: boolean } }?, boolean, string?)
	local by = readStock(stored)
	local who = tostring(userId)
	if by[who] then
		return nil, true, nil
	elseif holders(by) >= cap then
		return nil, false, "SoldOut"
	end
	by[who] = true
	return { by = by }, true, nil
end

--- The release transform: gives `userId`'s unit back (a cancelled prompt). nil when they hold
--- none (nothing to write).
function Counts.release(stored: any, userId: number): { by: { [string]: boolean } }?
	local by = readStock(stored)
	local who = tostring(userId)
	if not by[who] then
		return nil
	end
	by[who] = nil
	return { by = by }
end

return Counts
