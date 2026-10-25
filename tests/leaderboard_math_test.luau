--!strict
-- LeaderboardMath: the boards' virtual list shows the right rows at both ends, places are found
-- (or not), and the country tally never loses or double counts a win.

local H = require("./harness")

local function load()
	return H.require("LeaderboardMath")
end

return {
	the_window_starts_at_the_top_and_stops_at_the_end = function()
		local M = load()
		local first, count = M.window(0, 40, 400, 1000, 14)
		H.expect(first == 1 and count == 11, ("top: %d %d"):format(first, count))
		first, count = M.window(85, 40, 400, 1000, 14)
		H.expect(first == 3 and count == 11, ("scrolled: %d %d"):format(first, count))
		first, count = M.window(40 * 1000, 40, 400, 1000, 14)
		H.expect(first == 990 and count == 11, ("bottom: %d %d"):format(first, count))
	end,
	a_short_list_shows_every_row = function()
		local M = load()
		local first, count = M.window(0, 40, 400, 3, 14)
		H.expect(first == 1 and count == 3, "three rows")
		first, count = M.window(500, 40, 400, 3, 14)
		H.expect(first == 1 and count == 3, "scrolled past a short list")
		first, count = M.window(0, 40, 400, 0, 14)
		H.expect(count == 0, "an empty list shows nothing")
	end,
	pages_are_counted_from_one = function()
		local M = load()
		H.expect(M.pageOf(1, 100) == 1 and M.pageOf(100, 100) == 1, "page 1")
		H.expect(M.pageOf(101, 100) == 2 and M.pageOf(1000, 100) == 10, "later pages")
	end,
	a_place_is_found_or_nil = function()
		local M = load()
		local list = { { userId = 5 }, { userId = 9 }, { userId = 2 } }
		H.expect(M.place(list, "userId", 9) == 2, "second")
		H.expect(M.place(list, "userId", 7) == nil, "not on the board")
		H.expect(M.place(list, "userId", nil) == nil, "no key")
	end,
	new_wins_count_once_and_never_on_the_first_reading = function()
		local M = load()
		local added, base = M.newWins(nil, 40)
		H.expect(added == 0 and base == 40, "joining with 40 wins adds none")
		added, base = M.newWins(base, 41)
		H.expect(added == 1 and base == 41, "a win adds one")
		added, base = M.newWins(base, 41)
		H.expect(added == 0, "no change adds none")
		added, base = M.newWins(base, 30)
		H.expect(added == 0 and base == 30, "a drop adds none and lowers the baseline")
		added = M.newWins(base, 0 / 0)
		H.expect(added == 0, "nonsense adds none")
	end,
	the_tally_survives_a_failed_flush = function()
		local M = load()
		local tally = {}
		M.add(tally, "US", 2)
		M.add(tally, "US", 1)
		M.add(tally, "BR", 1)
		M.add(tally, "usa", 5)
		M.add(tally, "FR", 0)
		H.expect(tally.US == 3 and tally.BR == 1, "sums")
		H.expect(tally.usa == nil and tally.FR == nil, "bad codes and zeros are dropped")
		local sent = M.take(tally)
		H.expect(next(tally) == nil and sent.US == 3, "taken out to flush")
		-- The flush failed for US: it goes back, and a win in the meantime adds to it.
		M.add(tally, "US", 1)
		M.add(tally, "US", sent.US)
		H.expect(tally.US == 4, "put back without loss")
	end,
}
