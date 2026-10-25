--!strict
-- LeaderboardMath: the lobby boards' pure parts (Leaderboards on the server, LobbyBoards on the
-- client; designer, 2026-10-25). Lune tests them.
-- - The virtual list: a board shows up to 1000 rows with a handful of row frames, reused as it
--   scrolls; `window` says which rows they show.
-- - Places: a player's (or a country's) place in a board's list.
-- - The country tally: each server adds its players' new wins vs people to their country and
--   flushes the sums now and then; a failed flush puts its sums back.

local LeaderboardMath = {}

--- The rows the reused frames show when the list is scrolled `scrollY` px down: the first row's
--- number (from 1) and how many. `rowPx` is a row's height, `viewPx` the list's visible height,
--- `total` the list's rows, `pool` the frames there are.
function LeaderboardMath.window(
	scrollY: number,
	rowPx: number,
	viewPx: number,
	total: number,
	pool: number
): (number, number)
	if total <= 0 or pool <= 0 or rowPx <= 0 then
		return 1, 0
	end
	local need = math.min(pool, math.ceil(math.max(0, viewPx) / rowPx) + 1, total)
	local first = math.floor(math.max(0, scrollY) / rowPx) + 1
	first = math.clamp(first, 1, math.max(1, total - need + 1))
	return first, math.min(need, total - first + 1)
end

--- Which page (of `pageSize` rows, from 1) row `index` is on.
function LeaderboardMath.pageOf(index: number, pageSize: number): number
	return math.max(1, math.ceil(index / math.max(1, pageSize)))
end

--- The place (from 1) of the entry whose `field` is `key` in `list`, or nil when it is not there.
function LeaderboardMath.place(list: { any }, field: string, key: any): number?
	if key == nil then
		return nil
	end
	for i, entry in list do
		if entry[field] == key then
			return i
		end
	end
	return nil
end

--- A player's new wins since `baseline` (the count last seen; nil before the first reading):
--- the wins to add, and the new baseline. A first reading or a drop adds nothing, so a rejoin
--- or a save fix never counts old wins again.
function LeaderboardMath.newWins(baseline: number?, now: number?): (number, number?)
	if type(now) ~= "number" or now ~= now or now < 0 then
		return 0, baseline
	end
	local count = math.floor(now)
	if baseline == nil or count <= baseline then
		return 0, count
	end
	return count - baseline, count
end

export type Tally = { [string]: number }

--- Add `n` wins to `code` in the tally (a two-letter country code; anything else is dropped).
function LeaderboardMath.add(tally: Tally, code: any, n: number)
	if type(code) ~= "string" or not string.match(code, "^%u%u$") then
		return
	end
	if type(n) ~= "number" or n ~= n or n < 1 then
		return
	end
	tally[code] = (tally[code] or 0) + math.floor(n)
end

--- Take every sum out of the tally (it is left empty) to flush them.
function LeaderboardMath.take(tally: Tally): Tally
	local out: Tally = table.clone(tally)
	table.clear(tally)
	return out
end

return LeaderboardMath
