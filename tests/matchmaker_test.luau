--!strict
-- The global queue's pairing (designer, 2026-09-28): the closest rank first, anyone after
-- 10 s, the oldest search served first, never one player twice.
local H = require("./harness")
local Matchmaker = H.require("Matchmaking.Matchmaker")
local Config = H.require("Config")
local expect = H.expect

local function ticket(
	id: string,
	rating: number,
	at: number,
	mode: number?,
	users: { number }?
): any
	return {
		id = id,
		mode = mode or 1,
		users = users or { tonumber(id:sub(2)) or 0 },
		rating = rating,
		at = at,
	}
end

local function names(pairs: { any }): { string }
	local out = {}
	for _, p in pairs do
		table.insert(out, p.a.id .. "+" .. p.b.id)
	end
	return out
end

local tests = {}

function tests.the_range_widens_to_anyone_after_ten_seconds()
	expect(Matchmaker.window(0) == 1, "a new search takes one division either side")
	expect(Matchmaker.window(3) == 3)
	expect(Matchmaker.window(6.5) == 6)
	expect(Matchmaker.window(9.99) == 6)
	expect(Matchmaker.window(10) == math.huge, "after 10 s anyone")
	local last = Config.GlobalQueue.Window[#Config.GlobalQueue.Window]
	expect(last.After == 10 and last.Divisions == math.huge, "the designer's 10 s")
end

function tests.ratings_count_divisions_and_how_far_into_one()
	local Ranks = H.require("Progression.Ranks")
	expect(Matchmaker.rating(0, false) == 1, "unranked counts as Bronze I")
	expect(Matchmaker.rating(9000, false) == 1, "unrated XP does not count")
	expect(Matchmaker.rating(0, true) == 1, "Bronze I with no XP")
	-- Division widths grow up the ladder (ECONOMY 4.2): Bronze I is 300 XP, Diamond II 2,800.
	expect(Matchmaker.rating(150, true) == 1.5, "half way into Bronze I")
	expect(Matchmaker.rating(600, true) == 3, "Bronze III")
	local diamond2 = Ranks.toXp("Diamond", 2, 1400)
	expect(Matchmaker.rating(diamond2, true) == 22.5, "half way into Diamond II")
	expect(Matchmaker.rating(Ranks.toXp("Reyes", nil, 5e6), true) == 46, "Reyes has no top")
	local top = Matchmaker.rating(Ranks.toXp("Grandmaster", 5, 1e9), true)
	expect(top > 45.99 and top < 46, "the top of Grandmaster V stays below Reyes")
	-- Ratings rise with XP everywhere on the ladder, so they order players sensibly.
	local last = 0
	for index = 1, Ranks.count() do
		for _, share in { 0, 0.25, 0.5, 0.99 } do
			local width = Ranks.width(index) or 1000
			local rating = Matchmaker.rating(Ranks.startXp(index) + math.floor(width * share), true)
			expect(rating >= last, "rating never falls at division " .. index)
			expect(rating >= index and rating < index + 1, "inside its division " .. index)
			last = rating
		end
	end
	expect(Matchmaker.teamRating({ 2, 4 }) == 3, "a team averages")
	expect(Matchmaker.teamRating({}) == 1)
end

function tests.two_close_new_searches_meet_at_once()
	local pairs = Matchmaker.pair({ ticket("u1", 5.2, 100), ticket("u2", 5.9, 100) }, 100)
	expect(
		#pairs == 1 and pairs[1].a.id == "u1" and pairs[1].b.id == "u2",
		"u1 older by id: team 1"
	)
end

function tests.far_ranks_wait_then_meet_after_ten_seconds()
	local list = { ticket("u1", 2, 100), ticket("u2", 30, 100) }
	expect(#Matchmaker.pair(list, 100) == 0, "28 divisions apart: not yet")
	expect(#Matchmaker.pair(list, 109) == 0, "9 s: still six at most")
	expect(#Matchmaker.pair(list, 110) == 1, "10 s: anyone")
end

function tests.the_longer_search_opens_the_range_for_both()
	-- u1 has searched 7 s (6 divisions), u2 just arrived (1): they are 5 apart and meet.
	local pairs = Matchmaker.pair({ ticket("u1", 10, 93), ticket("u2", 15, 100) }, 100)
	expect(#pairs == 1)
end

function tests.the_closest_in_range_is_picked()
	local pairs = Matchmaker.pair({
		ticket("u1", 10, 90), -- the oldest, anyone in range
		ticket("u2", 20, 99),
		ticket("u3", 10.4, 99),
		ticket("u4", 12, 99),
	}, 100)
	expect(names(pairs)[1] == "u1+u3", "closest to the oldest: " .. table.concat(names(pairs), ","))
end

function tests.the_oldest_search_goes_first()
	-- u2 and u3 are an exact match, but u1 has waited longest and u2 is in its range.
	local pairs =
		Matchmaker.pair({ ticket("u1", 8, 80), ticket("u2", 9, 99), ticket("u3", 9, 99) }, 100)
	expect(#pairs == 1 and pairs[1].a.id == "u1" and pairs[1].b.id == "u2")
end

function tests.modes_never_mix()
	local pairs = Matchmaker.pair({
		ticket("u1", 5, 0, 1),
		ticket("t2", 5, 0, 2, { 2, 3 }),
		ticket("t4", 5, 0, 2, { 4, 5 }),
	}, 100)
	expect(#pairs == 1 and pairs[1].a.mode == 2 and pairs[1].b.mode == 2)
end

function tests.nobody_is_in_two_pairs()
	-- The same player on two tickets (a stale one left behind) is only ever used once.
	local pairs = Matchmaker.pair({
		ticket("a", 5, 0, 1, { 1 }),
		ticket("b", 5, 0, 1, { 1 }),
		ticket("c", 5, 0, 1, { 2 }),
		ticket("d", 5, 0, 1, { 3 }),
		ticket("e", 5, 0, 1, { 4 }),
	}, 100)
	local seen = {}
	for _, p in pairs do
		for _, t in { p.a, p.b } do
			for _, u in t.users do
				expect(not seen[u], "player twice")
				seen[u] = true
			end
		end
	end
	expect(#pairs == 2)
end

function tests.a_new_game_avoids_the_last_opponent_for_a_while()
	local a = ticket("u1", 5, 100)
	a.avoid = { 2 }
	local b = ticket("u2", 5, 100)
	expect(#Matchmaker.pair({ a, b }, 100) == 0, "just played each other")
	expect(
		#Matchmaker.pair({ a, b }, 100 + Config.GlobalQueue.AvoidRecentSeconds) == 1,
		"then anyone"
	)
	local c = ticket("u3", 5, 100)
	local pairs = Matchmaker.pair({ a, b, c }, 100)
	expect(#pairs == 1 and pairs[1].b.id == "u3", "a fresh opponent instead")
end

function tests.pairing_is_the_same_in_any_order()
	local list = {}
	for i = 1, 30 do
		table.insert(list, ticket("u" .. i, (i * 7) % 40 + 1, (i * 13) % 20))
	end
	local first = table.concat(names(Matchmaker.pair(list, 30)), ",")
	local reversed = {}
	for i = #list, 1, -1 do
		table.insert(reversed, list[i])
	end
	expect(table.concat(names(Matchmaker.pair(reversed, 30)), ",") == first)
end

function tests.the_ults_pools_never_meet()
	local off = ticket("a1", 5, 0)
	off.ults = false
	local on = ticket("a2", 5, 0)
	on.ults = true
	expect(#Matchmaker.pair({ off, on }, 100) == 0, "No ults never meets ults on, even at 100 s")
	local old = ticket("a3", 5, 0) -- a ticket from before the choice: ults on
	local pairs = Matchmaker.pair({ off, on, old }, 100)
	expect(#pairs == 1 and names(pairs)[1] == "a2+a3", "missing means ults on")
	local off2 = ticket("a4", 40, 1)
	off2.ults = false
	pairs = Matchmaker.pair({ off, on, old, off2 }, 100)
	table.sort(pairs, function(x: any, y: any): boolean
		return x.a.id < y.a.id
	end)
	expect(#pairs == 2, "one pair per pool")
	expect(names(pairs)[1] == "a1+a4" and names(pairs)[2] == "a2+a3", "each with its own pool")
end

function tests.this_servers_windows_never_reach_anyone()
	local W = Config.GlobalQueue.LocalWindow
	expect(Matchmaker.window(0, W) == 2, "two divisions at once")
	expect(Matchmaker.window(1, W) == 4)
	expect(Matchmaker.window(2.5, W) == 7)
	expect(Matchmaker.window(3.5, W) == 12)
	expect(Matchmaker.window(60, W) == 12, "never anyone here")
	local far = Matchmaker.pair({ ticket("u1", 1, 0), ticket("u2", 20, 0) }, 60, { windows = W })
	expect(#far == 0, "19 divisions apart never meet here")
	local near = Matchmaker.pair({ ticket("u1", 1, 0), ticket("u2", 12, 0) }, 4, { windows = W })
	expect(#near == 1, "11 apart after 3.5 s")
end

function tests.a_rule_can_keep_two_tickets_apart()
	local a, b, c = ticket("u1", 5, 0), ticket("u2", 5.1, 1), ticket("u3", 5.5, 2)
	a.searching, b.searching, c.searching = false, false, true
	local rules = {
		windows = Config.GlobalQueue.LocalWindow,
		allow = function(x: any, y: any): boolean
			return x.searching or y.searching
		end,
	}
	local pairs = Matchmaker.pair({ a, b, c }, 3, rules)
	expect(#pairs == 1, "two waiting on pads never meet by themselves")
	expect(names(pairs)[1] == "u1+u3", "the oldest waiter meets the searcher")
end

return tests
