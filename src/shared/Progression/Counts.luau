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
--   Limited  one key per Limited cue: how many numbered copies were handed out
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

--- How many numbered copies a stored Limited value says were handed out (0 for nothing or
--- junk).
function Counts.sold(stored: any): number
	return if isWhole(stored) and stored > 0 then stored else 0
end

--- The Limited transform: the next copy number (the value to store), or (nil, reason) to write
--- nothing: "Ended" at or past `endsAt` (unix seconds), "SoldOut" once `cap` copies are out.
function Counts.takeNext(stored: any, cap: number, now: number, endsAt: number): (number?, string?)
	if not (now < endsAt) then
		return nil, "Ended"
	end
	local sold = Counts.sold(stored)
	if not (sold < cap) then
		return nil, "SoldOut"
	end
	return sold + 1, nil
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

return Counts
