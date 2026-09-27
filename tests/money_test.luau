--!strict
-- Money: what each shot and match pays (Progression/Money, numbers in Config.Economy).

local H = require("./harness")

local function setup()
	local Money = H.require("Progression.Money")
	local TableGeometry = H.require("Physics.Table")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	return Money, geometry
end

-- Hand-written logs, as in nice_shot_test: `rail(ball, x, y)`, `hit(a, b)`, `drop(ball, ...)`.
local function rail(ball: number, x: number, y: number): any
	return { t = 0, type = "railHit", ball = ball, speed = 50, x = x, y = y }
end
local function hit(a: number, b: number): any
	return { t = 0, type = "ballHit", ball = a, other = b, speed = 50 }
end
local function drop(ball: number, pocket: number, t: number): any
	return { t = t, type = "pocket", ball = ball, other = pocket, speed = 10 }
end

-- The drops ShotJudge would list: every object ball's first pocket event, in order.
local function dropsOf(events: { any }): { any }
	local drops = {}
	for index, ev in events do
		if ev.type == "pocket" and ev.ball ~= 0 then
			table.insert(drops, { ball = ev.ball, index = index, t = ev.t })
		end
	end
	return drops
end

-- A shot by team 1 (solids against stripes) unless `overrides` says otherwise.
local function input(geometry: any, events: { any }, overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		events = events,
		drops = dropsOf(events),
		pockets = geometry.pockets,
		foul = false,
		breakShot = false,
		groupsBefore = { "solids", "stripes" },
		groupsAfter = { "solids", "stripes" },
		team = 1,
		winner = nil,
		reason = nil,
		solo = false,
		soloEarnedToday = 0,
		multiplier = 1,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

-- Grants as "ball:kind:amount" words, in order, to compare in one go.
local function summary(pay: any): string
	local words = {}
	for _, g in pay.grants do
		table.insert(words, ("%d:%s:%d"):format(g.ball, g.kind, g.amount))
	end
	return table.concat(words, " ")
end

local function expectPay(pay: any, expected: string, total: number, message: string)
	H.expect(
		summary(pay) == expected,
		("%s: grants %q, expected %q"):format(message, summary(pay), expected)
	)
	H.expect(pay.total == total, ("%s: total %d, expected %d"):format(message, pay.total, total))
end

-- A cushion hit far from every pocket.
local function midCushion(geometry: any): (number, number)
	return geometry.halfLength / 2, geometry.halfWidth
end

-- Ball 3 banked in, then ball 5 knocked in by ball 3: a bank and a combo.
local function bankAndCombo(geometry: any): { any }
	local x, y = midCushion(geometry)
	return { hit(0, 3), hit(3, 5), rail(3, x, y), drop(3, 1, 1.5), drop(5, 4, 2.25) }
end

return {
	["round and utcDay"] = function()
		local Money = setup()
		H.expect(Money.round(4.5) == 5 and Money.round(4.49) == 4 and Money.round(7.5) == 8)
		H.expect(Money.round(-0.5) == 0 and Money.round(3) == 3)
		H.expect(Money.utcDay(0) == 0 and Money.utcDay(86399) == 0 and Money.utcDay(86400) == 1)
		H.expect(Money.utcDay(1790000000) == 20717, "a day in 2026")
	end,

	["a plain pot pays one ball with its pocket and time"] = function()
		local Money, geometry = setup()
		local pay = Money.shotPay(input(geometry, { hit(0, 3), drop(3, 2, 1.5) }))
		expectPay(pay, "3:Ball:10", 10, "plain pot")
		local g = pay.grants[1]
		H.expect(g.pocket == 2 and g.t == 1.5, "the grant carries its pocket and drop time")
		H.expect(pay.balls == 1 and pay.nice == 0 and pay.soloEarned == 0)
	end,

	["a foul shot pays nothing"] = function()
		local Money, geometry = setup()
		local pay = Money.shotPay(input(geometry, bankAndCombo(geometry), { foul = true }))
		expectPay(pay, "", 0, "foul")
		H.expect(pay.balls == 0 and pay.nice == 0)
	end,

	["the other side's balls pay nothing"] = function()
		local Money, geometry = setup()
		local events = { hit(0, 3), hit(3, 11), drop(11, 1, 1), drop(3, 2, 2) }
		expectPay(Money.shotPay(input(geometry, events)), "3:Ball:10", 10, "solids shooter")
		local stripes =
			input(geometry, events, { team = 2, groupsBefore = { "solids", "stripes" } })
		-- Team 2 shoots stripes: ball 11 went in off ball 3, a combo.
		expectPay(Money.shotPay(stripes), "11:Ball:10 11:Combo:20", 30, "stripes shooter")
	end,

	["the legal pot that picks the colors pays every object ball"] = function()
		local Money, geometry = setup()
		local events = { hit(0, 3), hit(0, 11), drop(3, 1, 1), drop(11, 2, 2) }
		local open = input(geometry, events, { groupsBefore = {} })
		-- Ball 11: the cue ball met ball 3 before it, so it went in off a carom.
		expectPay(Money.shotPay(open), "3:Ball:10 11:Ball:10 11:Carom:20", 40, "open table")
		-- An early 8 on an open table loses and picks nothing: nothing pays.
		local early = input(
			geometry,
			{ hit(0, 3), drop(3, 1, 1), drop(8, 2, 2) },
			{ groupsBefore = {}, groupsAfter = {}, winner = 2, reason = "EarlyEight" }
		)
		expectPay(Money.shotPay(early), "", 0, "early eight")
	end,

	["the break pays every object ball, no nice shots, never the 8"] = function()
		local Money, geometry = setup()
		local events = { hit(0, 1), hit(1, 2), hit(2, 11), drop(2, 1, 1), drop(11, 3, 2) }
		table.insert(events, drop(8, 5, 3))
		local brk = { breakShot = true, groupsBefore = {}, groupsAfter = {} }
		expectPay(Money.shotPay(input(geometry, events, brk)), "2:Ball:10 11:Ball:10", 20, "break")
		local foul = { breakShot = true, groupsBefore = {}, groupsAfter = {}, foul = true }
		expectPay(Money.shotPay(input(geometry, events, foul)), "", 0, "foul break")
	end,

	["the 8 pays only when it wins for the shooter"] = function()
		local Money, geometry = setup()
		local events = { hit(0, 8), drop(8, 3, 1) }
		local won = { winner = 1, reason = "LegalEight" }
		expectPay(Money.shotPay(input(geometry, events, won)), "8:Ball:10", 10, "legal eight")
		local wrong = { winner = 2, reason = "WrongPocket" }
		expectPay(Money.shotPay(input(geometry, events, wrong)), "", 0, "wrong pocket")
		local theirs = { winner = 2, reason = "LegalEight" }
		expectPay(Money.shotPay(input(geometry, events, theirs)), "", 0, "not the shooter's win")
		local foul = { winner = 2, reason = "FoulEight", foul = true }
		expectPay(Money.shotPay(input(geometry, events, foul)), "", 0, "8 on a foul")
	end,

	["nice shots pay right after their ball"] = function()
		local Money, geometry = setup()
		local pay = Money.shotPay(input(geometry, bankAndCombo(geometry)))
		expectPay(pay, "3:Ball:10 3:Bank:15 5:Ball:10 5:Combo:20", 55, "bank and combo")
		H.expect(pay.balls == 2 and pay.nice == 2)
		H.expect(pay.grants[2].pocket == 1 and pay.grants[2].t == 1.5, "bank at ball 3's drop")
		H.expect(pay.grants[4].pocket == 4 and pay.grants[4].t == 2.25, "combo at ball 5's drop")
		local x, y = midCushion(geometry)
		local kick = { rail(0, x, y), hit(0, 3), drop(3, 1, 1) }
		expectPay(Money.shotPay(input(geometry, kick)), "3:Ball:10 3:Kick:15", 25, "kick")
		local carom = { hit(0, 11), hit(0, 3), drop(3, 1, 1) }
		expectPay(Money.shotPay(input(geometry, carom)), "3:Ball:10 3:Carom:20", 30, "carom")
	end,

	["the difficulty multiplier scales every grant and bonus"] = function()
		local Money, geometry = setup()
		local pay = Money.shotPay(input(geometry, bankAndCombo(geometry), { multiplier = 1.5 }))
		expectPay(pay, "3:Ball:15 3:Bank:23 5:Ball:15 5:Combo:30", 83, "1.5x")
		local tiny = Money.shotPay(input(geometry, bankAndCombo(geometry), { multiplier = 0.01 }))
		expectPay(tiny, "3:Ball:1 3:Bank:1 5:Ball:1 5:Combo:1", 4, "never zero")
		H.expect(Money.matchBonus("Win", "Player", true, false, 1.5) == 75)
		H.expect(Money.matchBonus("Loss", "Player", true, false, 1.5) == 23)
	end,

	["solo pays its share: 3 a ball, 5 a bank or kick, 6 a combo or carom"] = function()
		local Money, geometry = setup()
		local x, y = midCushion(geometry)
		local events = bankAndCombo(geometry)
		-- A stripe too: solo plays both groups.
		table.insert(events, rail(0, x, y))
		table.insert(events, hit(0, 12))
		table.insert(events, drop(12, 6, 3))
		local solo = { solo = true, soloEarnedToday = 100 }
		local pay = Money.shotPay(input(geometry, events, solo))
		-- Ball 12: the cue ball met ball 3 before it (a carom), before its cushion.
		expectPay(pay, "3:Ball:3 3:Bank:5 5:Ball:3 5:Combo:6 12:Ball:3 12:Carom:6", 26, "solo")
		H.expect(pay.soloEarned == 26, "all of it counts toward the daily cap")
		local kick = { rail(0, x, y), hit(0, 3), drop(3, 1, 1) }
		expectPay(Money.shotPay(input(geometry, kick, solo)), "3:Ball:3 3:Kick:5", 8, "solo kick")
		-- The winning 8 in solo.
		local eight = { solo = true, winner = 1, reason = "LegalEight" }
		expectPay(
			Money.shotPay(input(geometry, { hit(0, 8), drop(8, 1, 1) }, eight)),
			"8:Ball:3",
			3,
			"8"
		)
	end,

	["solo past the daily cap pays 1 a ball and no nice shots"] = function()
		local Money, geometry = setup()
		local events = bankAndCombo(geometry)
		table.insert(events, drop(6, 2, 3))
		local near = Money.shotPay(input(geometry, events, { solo = true, soloEarnedToday = 298 }))
		-- 298 + 3 = 301 is over the cap: the bank is skipped and later balls pay 1.
		expectPay(near, "3:Ball:3 5:Ball:1 6:Ball:1", 5, "crossing the cap")
		H.expect(near.balls == 3 and near.nice == 0 and near.soloEarned == 5)
		local over = Money.shotPay(input(geometry, events, { solo = true, soloEarnedToday = 300 }))
		expectPay(over, "3:Ball:1 5:Ball:1 6:Ball:1", 3, "at the cap")
		local under = Money.shotPay(input(geometry, events, { solo = true, soloEarnedToday = 290 }))
		-- 290 +3 +5 = 298 is still under: ball 5 pays 3 (301), then its combo is skipped.
		expectPay(under, "3:Ball:3 3:Bank:5 5:Ball:3 6:Ball:1", 12, "under the cap")
		-- The daily counter only moves in solo.
		local match = Money.shotPay(input(geometry, events, { soloEarnedToday = 500 }))
		H.expect(match.total == 65 and match.soloEarned == 0, "a match ignores the solo cap")
	end,

	["match bonus"] = function()
		local Money = setup()
		local cases: { { any } } = {
			-- outcome, opponent, real, forfeited, multiplier, expected
			{ "Win", "Player", true, false, 1, 50 },
			{ "Loss", "Player", true, false, 1, 15 },
			{ "Draw", "Player", true, false, 1, 0 },
			{ "Win", "PC", true, false, 1, 25 },
			{ "Loss", "PC", true, false, 1, 8 }, -- 7.5 rounds up
			{ "Win", "Player", true, false, 2, 100 },
			{ "Loss", "Player", true, true, 1, 0 }, -- forfeited or left
			{ "Win", "Player", false, false, 1, 0 }, -- under the one-minute mark
			{ "Loss", "Player", false, false, 1, 0 },
			{ "Loss", "PC", false, true, 1, 0 },
		}
		for _, c in cases do
			local got = Money.matchBonus(c[1], c[2], c[3], c[4], c[5])
			H.expect(
				got == c[6],
				("%s vs %s real=%s forfeited=%s x%s: %d, expected %d"):format(
					c[1],
					c[2],
					tostring(c[3]),
					tostring(c[4]),
					tostring(c[5]),
					got,
					c[6]
				)
			)
		end
	end,
}
