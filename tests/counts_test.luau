--!strict
-- The shared counters' pure half (Progression/Counts): the shard a server writes to, the
-- UpdateAsync transforms for copies in existence, numbered Limited copies and firsts, and
-- summing the shards (docs/ARCHITECTURE.md, "The economy").

local H = require("./harness")

local function load()
	return H.require("Progression.Counts"), H.require("Config")
end

local function size(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

return {
	shards_are_stable_in_range_and_spread = function()
		local Counts, Config = load()
		local shards = Config.Items.CountsShards
		H.expect(Counts.shardFor("", shards) == 1, "Studio's empty JobId is shard 1")
		H.expect(Counts.shardFor("anything", 1) == 1, "one shard")
		local id = "1f0e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
		H.expect(Counts.shardFor(id, shards) == Counts.shardFor(id, shards), "the same every time")
		local hits: { number } = table.create(shards, 0)
		local runs = 4000
		for i = 1, runs do
			-- JobId-like strings: a GUID shape with a counter in it.
			local jobId = ("%08x-%04x-4000-8000-%012x"):format(
				i * 2654435761 % 4294967296,
				i,
				i * 7
			)
			local n = Counts.shardFor(jobId, shards)
			H.expect(n >= 1 and n <= shards and n == math.floor(n), "in range: " .. n)
			hits[n] += 1
		end
		for n = 1, shards do
			local share = hits[n] / runs
			H.expect(
				share > 0.5 / shards and share < 1.5 / shards,
				("shard %d share %.3f"):format(n, share)
			)
		end
		H.expect(Counts.shardKey(3) == "shard_3", "the key")
	end,

	add_deltas_keeps_valid_entries_and_drops_zeros = function()
		local Counts = load()
		local stored = { Alpha = 5, Beta = -2, Gamma = 1 }
		local deltas = { Alpha = 1, Beta = 2, Delta = 4 }
		local value = Counts.addDeltas(stored, deltas)
		H.expect(value.Alpha == 6, "added")
		H.expect(value.Beta == nil, "a zero is dropped")
		H.expect(value.Gamma == 1, "kept")
		H.expect(value.Delta == 4, "a new entry")
		H.expect(size(value) == 3, "nothing else")
		-- Neither argument is changed (the transform can run again after a conflict).
		H.expect(stored.Alpha == 5 and stored.Beta == -2 and size(stored) == 3, "stored untouched")
		H.expect(deltas.Alpha == 1 and size(deltas) == 3, "deltas untouched")
		local again = Counts.addDeltas(stored, deltas)
		H.expect(again.Alpha == 6 and again ~= value, "a fresh, identical value")
	end,

	add_deltas_on_empty_or_junk = function()
		local Counts = load()
		for _, junk in { nil :: any, 5, "text", true } do
			local value = Counts.addDeltas(junk, { Alpha = 2 })
			H.expect(value.Alpha == 2 and size(value) == 1, "from " .. tostring(junk))
		end
		local messy: any =
			{ Alpha = 1.5, Beta = "3", [7] = 4, Gamma = 0 / 0, Delta = math.huge, Ok = 3 }
		local value = Counts.addDeltas(messy, { Ok = -1, [""] = 5, Bad = 0.25 } :: any)
		H.expect(value.Ok == 2 and size(value) == 1, "only whole numbers under ids survive")
	end,

	add_into_signs_and_zeros = function()
		local Counts = load()
		local target = { Alpha = 3 }
		Counts.addInto(target, { Alpha = 3, Beta = 1 }, -1)
		H.expect(target.Alpha == nil and target.Beta == -1, "subtracted, zero dropped")
		Counts.addInto(target, { Beta = 1 })
		H.expect(target.Beta == nil and size(target) == 0, "back to empty")
	end,

	sum_over_shards = function()
		local Counts = load()
		local totals = Counts.sum({
			{ Alpha = 5, Beta = 2 },
			nil :: any,
			{ Alpha = -1, Gamma = 3 },
			"junk" :: any,
			{ Beta = -4 },
		})
		H.expect(totals.Alpha == 4, "Alpha across shards")
		H.expect(totals.Gamma == 3, "Gamma")
		H.expect(totals.Beta == nil, "a sum below zero reads as none")
		local empty = Counts.sum({})
		H.expect(size(empty) == 0, "no shards")
	end,

	limited_take_next = function()
		local Counts = load()
		-- takeNext(stored, userId, cap, now, endsAt) -> value to store, copy, reason
		local value, copy, why = Counts.takeNext(nil, 42, 3, 100, 200)
		H.expect(copy == 1 and why == nil, "the first copy is #1")
		H.expect(value ~= nil and value.n == 1 and value.by["42"] == 1, "recorded under the id")
		local second, copy2 = Counts.takeNext(value, 7, 3, 100, 200)
		H.expect(copy2 == 2 and second.n == 2, "then #2 for the next player")
		H.expect(second.by["42"] == 1 and second.by["7"] == 2 and size(second.by) == 2, "both kept")
		H.expect(value.n == 1 and size(value.by) == 1, "the stored value is never changed")
		-- The same player again (a retry, a rejoin): the same number, nothing written.
		local again, same, none = Counts.takeNext(second, 42, 3, 100, 200)
		H.expect(again == nil and same == 1 and none == nil, "the same number, no write")
		-- The cap and the end, for a new player; never for one who has a number.
		local full = { n = 3, by = { ["42"] = 1, ["7"] = 2, ["9"] = 3 } }
		value, copy, why = Counts.takeNext(full, 5, 3, 100, 200)
		H.expect(value == nil and copy == nil and why == "SoldOut", "at the cap")
		value, copy, why = Counts.takeNext(full, 9, 3, 100, 200)
		H.expect(value == nil and copy == 3 and why == nil, "at the cap: still theirs")
		value, copy, why = Counts.takeNext(nil, 5, 3, 200, 200)
		H.expect(value == nil and copy == nil and why == "Ended", "at the end time")
		value, copy, why = Counts.takeNext(full, 5, 3, 300, 200)
		H.expect(copy == nil and why == "Ended", "ended wins over sold out")
		value, copy, why = Counts.takeNext(full, 7, 3, 300, 200)
		H.expect(value == nil and copy == 2 and why == nil, "after the end: still theirs")
		-- The old shape: a plain count, nobody recorded.
		value, copy = Counts.takeNext(5, 42, 10, 100, 200)
		H.expect(copy == 6 and value.n == 6 and value.by["42"] == 6, "an old count goes on")
		value, copy, why = Counts.takeNext(3, 42, 3, 100, 200)
		H.expect(copy == nil and why == "SoldOut", "an old count at the cap")
		H.expect(select(2, Counts.takeNext("junk", 1, 3, 100, 200)) == 1, "junk reads as none")
		H.expect(select(2, Counts.takeNext(-4, 1, 3, 100, 200)) == 1, "a negative reads as none")
		H.expect(select(2, Counts.takeNext(999999, 1, math.huge, 100, 200)) == 1000000, "no cap")
		-- Junk inside a stored table is dropped; the count never falls under a number given.
		local messy: any = { n = 2, by = { ["42"] = 5, ["7"] = 0, ["8"] = 1.5, [3] = 2 } }
		value, copy = Counts.takeNext(messy, 1, 10, 100, 200)
		H.expect(copy == 6 and value.n == 6, "past the biggest number recorded")
		H.expect(value.by["42"] == 5 and value.by["1"] == 6 and size(value.by) == 2, "junk dropped")
		H.expect(Counts.sold(7) == 7 and Counts.sold(nil) == 0 and Counts.sold(2.5) == 0, "sold")
		H.expect(Counts.sold(full) == 3 and Counts.sold(messy) == 5, "sold, the new shape")
		H.expect(Counts.sold({ n = "x" }) == 0 and Counts.sold({}) == 0, "sold, junk")
	end,

	firsts_set_only_if_empty = function()
		local Counts = load()
		local value, first = Counts.claim(nil, 42)
		H.expect(value == 42 and first, "an empty key takes the claim")
		value, first = Counts.claim(42, 42)
		H.expect(value == nil and first, "the same player again: true, no write")
		value, first = Counts.claim(42, 7)
		H.expect(value == nil and not first, "someone else was first")
	end,
}
