--!strict
-- Money: what each shot and match pays (Progression/Money, numbers in Config.Economy). Every
-- expected number is written out from docs/ECONOMY.md section 3 (not read from Config), so
-- these tests check Config against the document.

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
		opponent = "Player",
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

-- A real match's end for one player, against a person, unless `overrides` says otherwise.
local function bonus(outcome: string, overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		outcome = outcome,
		opponent = "Player",
		real = true,
		forfeited = false,
		multiplier = 1,
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
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
		H.expect(pay.balls == 1 and pay.nice == 0 and pay.soloEarned == 0 and pay.pcEarned == 0)
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
		-- ECONOMY 3.4: Difficult x1.5, Challenger x2, on balls and on the match bonus.
		local two = Money.shotPay(input(geometry, bankAndCombo(geometry), { multiplier = 2 }))
		expectPay(two, "3:Ball:20 3:Bank:30 5:Ball:20 5:Combo:40", 110, "2x")
		H.expect(Money.matchBonus(bonus("Win", { multiplier = 1.5 })) == 75)
		H.expect(Money.matchBonus(bonus("Loss", { multiplier = 1.5 })) == 23, "22.5 rounds up")
		H.expect(Money.matchBonus(bonus("Win", { multiplier = 2 })) == 100)
		H.expect(Money.matchBonus(bonus("Loss", { multiplier = 2 })) == 30)
	end,

	["solo pays its share: 3 a ball, 5 a bank or kick, 6 a combo or carom"] = function()
		local Money, geometry = setup()
		local x, y = midCushion(geometry)
		local events = bankAndCombo(geometry)
		-- A stripe too: solo plays both groups.
		table.insert(events, rail(0, x, y))
		table.insert(events, hit(0, 12))
		table.insert(events, drop(12, 6, 3))
		local solo = { opponent = "Solo", soloEarnedToday = 100 }
		local pay = Money.shotPay(input(geometry, events, solo))
		-- Ball 12: the cue ball met ball 3 before it (a carom), before its cushion.
		expectPay(pay, "3:Ball:3 3:Bank:5 5:Ball:3 5:Combo:6 12:Ball:3 12:Carom:6", 26, "solo")
		H.expect(pay.soloEarned == 26, "all of it counts toward the daily cap")
		local kick = { rail(0, x, y), hit(0, 3), drop(3, 1, 1) }
		expectPay(Money.shotPay(input(geometry, kick, solo)), "3:Ball:3 3:Kick:5", 8, "solo kick")
		-- The winning 8 in solo.
		local eight = { opponent = "Solo", winner = 1, reason = "LegalEight" }
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
		local near =
			Money.shotPay(input(geometry, events, { opponent = "Solo", soloEarnedToday = 298 }))
		-- 298 + 3 = 301 is over the cap: the bank is skipped and later balls pay 1.
		expectPay(near, "3:Ball:3 5:Ball:1 6:Ball:1", 5, "crossing the cap")
		H.expect(near.balls == 3 and near.nice == 0 and near.soloEarned == 5)
		local over =
			Money.shotPay(input(geometry, events, { opponent = "Solo", soloEarnedToday = 300 }))
		expectPay(over, "3:Ball:1 5:Ball:1 6:Ball:1", 3, "at the cap")
		local under =
			Money.shotPay(input(geometry, events, { opponent = "Solo", soloEarnedToday = 290 }))
		-- 290 +3 +5 = 298 is still under: ball 5 pays 3 (301), then its combo is skipped.
		expectPay(under, "3:Ball:3 3:Bank:5 5:Ball:3 6:Ball:1", 12, "under the cap")
		-- The daily counter only moves in solo.
		local match = Money.shotPay(input(geometry, events, { soloEarnedToday = 500 }))
		H.expect(match.total == 65 and match.soloEarned == 0, "a match ignores the solo cap")
	end,

	-- ECONOMY 3.1 and 3.2: the win and loss bonus by opponent.
	["match bonus: $50 / $15 against people, $25 / $8 against PC"] = function()
		local Money = setup()
		local cases: { { any } } = {
			-- outcome, overrides, expected
			{ "Win", {}, 50 },
			{ "Loss", {}, 15 },
			{ "Draw", {}, 0 },
			{ "Win", { opponent = "PC" }, 25 },
			{ "Loss", { opponent = "PC" }, 8 },
			{ "Draw", { opponent = "PC" }, 0 },
			{ "Win", { opponent = "Solo" }, 0 }, -- solo has no match bonus
			{ "Loss", { forfeited = true }, 0 }, -- the leaver gets nothing
			{ "Win", { real = false }, 0 }, -- under the one-minute mark
			{ "Loss", { real = false }, 0 },
			{ "Loss", { opponent = "PC", real = false, forfeited = true }, 0 },
			{ "Win", { multiplier = nil }, 50 }, -- no multiplier is x1
		}
		for i, c in cases do
			local got = Money.matchBonus(bonus(c[1], c[2]))
			H.expect(got == c[3], ("case %d (%s): %d, expected %d"):format(i, c[1], got, c[3]))
		end
		H.expect(Money.matchBonus(nil :: any) == 0, "no context")
	end,

	["PC pays in full, then half after $1,000 in a UTC day (ECONOMY 3.2)"] = function()
		local Money, geometry = setup()
		local events = bankAndCombo(geometry)
		local under =
			Money.shotPay(input(geometry, events, { opponent = "PC", pcEarnedToday = 500 }))
		expectPay(under, "3:Ball:10 3:Bank:15 5:Ball:10 5:Combo:20", 55, "PC under the cap")
		H.expect(under.pcEarned == 55 and under.soloEarned == 0, "PC money counts toward PC")
		local over =
			Money.shotPay(input(geometry, events, { opponent = "PC", pcEarnedToday = 1000 }))
		-- Half, rounded half up: the bank's 7.5 is 8.
		expectPay(over, "3:Ball:5 3:Bank:8 5:Ball:5 5:Combo:10", 28, "PC past the cap")
		H.expect(over.pcEarned == 28)
		-- The ball that crosses the cap pays in full; everything after it at half.
		local crossing =
			Money.shotPay(input(geometry, events, { opponent = "PC", pcEarnedToday = 990 }))
		expectPay(crossing, "3:Ball:10 3:Bank:8 5:Ball:5 5:Combo:10", 33, "crossing the cap")
		-- Never zero.
		local tiny = Money.shotPay(
			input(geometry, events, { opponent = "PC", pcEarnedToday = 5000, multiplier = 0.01 })
		)
		expectPay(tiny, "3:Ball:1 3:Bank:1 5:Ball:1 5:Combo:1", 4, "never zero")
		-- A person match ignores the PC counter; the bonus halves past the cap too.
		local person = Money.shotPay(input(geometry, events, { pcEarnedToday = 5000 }))
		H.expect(person.total == 55 and person.pcEarned == 0, "people ignore the PC cap")
		H.expect(Money.matchBonus(bonus("Win", { opponent = "PC", pcCapped = true })) == 13)
		H.expect(Money.matchBonus(bonus("Loss", { opponent = "PC", pcCapped = true })) == 4)
		H.expect(Money.matchBonus(bonus("Win", { pcCapped = true })) == 50, "people: no cap")
	end,

	["team pay: each teammate $10 a ball, nice shots only to the shooter (ECONOMY 3.3)"] = function()
		local Money, geometry = setup()
		local events = bankAndCombo(geometry)
		local shooter = Money.shotPay(input(geometry, events, { isShooter = true }))
		expectPay(shooter, "3:Ball:10 3:Bank:15 5:Ball:10 5:Combo:20", 55, "the shooter")
		local mate = Money.shotPay(input(geometry, events, { isShooter = false }))
		expectPay(mate, "3:Ball:10 5:Ball:10", 20, "a teammate")
		H.expect(mate.balls == 2 and mate.nice == 0)
		-- Each teammate by their own rules: a VIP teammate, one past the PC cap.
		local vip = Money.shotPay(input(geometry, events, { isShooter = false, boost = 1 }))
		expectPay(vip, "3:Ball:20 5:Ball:20", 40, "a VIP teammate")
		local pcMate = Money.shotPay(
			input(geometry, events, { isShooter = false, opponent = "PC", pcEarnedToday = 1000 })
		)
		expectPay(pcMate, "3:Ball:5 5:Ball:5", 10, "a teammate past the PC cap")
		-- A foul pays nobody; the break pays every teammate its balls.
		local foul = Money.shotPay(input(geometry, events, { isShooter = false, foul = true }))
		expectPay(foul, "", 0, "a teammate on a foul")
		local brk = { breakShot = true, groupsBefore = {}, groupsAfter = {}, isShooter = false }
		local breakEvents = { hit(0, 1), hit(1, 2), drop(2, 1, 1), drop(11, 3, 2) }
		expectPay(
			Money.shotPay(input(geometry, breakEvents, brk)),
			"2:Ball:10 11:Ball:10",
			20,
			"break"
		)
	end,

	["boosts add, then difficulty multiplies: VIP + Money Party is x3 (ECONOMY 3.5)"] = function()
		local Money, geometry = setup()
		H.expect(Money.boost(false, false) == 0 and Money.boost(true, false) == 1)
		H.expect(Money.boost(false, true) == 1 and Money.boost(true, true) == 2)
		local both = Money.boost(true, true)
		local events = bankAndCombo(geometry)
		local x3 = Money.shotPay(input(geometry, events, { boost = both }))
		expectPay(x3, "3:Ball:30 3:Bank:45 5:Ball:30 5:Combo:60", 165, "x3")
		local x6 = Money.shotPay(input(geometry, events, { boost = both, multiplier = 2 }))
		expectPay(x6, "3:Ball:60 3:Bank:90 5:Ball:60 5:Combo:120", 330, "x6 in Challenger")
		H.expect(Money.matchBonus(bonus("Win", { boost = 1 })) == 100, "VIP doubles the win")
		H.expect(Money.matchBonus(bonus("Win", { boost = both })) == 150)
		H.expect(Money.matchBonus(bonus("Loss", { boost = both })) == 45)
		H.expect(Money.matchBonus(bonus("Win", { boost = both, multiplier = 2 })) == 300, "x6")
		H.expect(Money.matchBonus(bonus("Loss", { opponent = "PC", boost = 1 })) == 16)
		-- A bad boost never pays more.
		H.expect(Money.matchBonus(bonus("Win", { boost = -5 })) == 50)
		H.expect(Money.matchBonus(bonus("Win", { boost = 0 / 0 })) == 50)
	end,

	["the solo and PC caps apply after the boosts and count the money paid"] = function()
		local Money, geometry = setup()
		local events = bankAndCombo(geometry)
		-- VIP solo: 10 x 2 x 0.3 = 6 a ball, 9 a bank, 12 a combo.
		local solo = Money.shotPay(input(geometry, events, { opponent = "Solo", boost = 1 }))
		expectPay(solo, "3:Ball:6 3:Bank:9 5:Ball:6 5:Combo:12", 33, "VIP solo")
		H.expect(solo.soloEarned == 33 and solo.pcEarned == 0)
		-- Past the solo cap the flat $1 is not boosted.
		local flat = Money.shotPay(
			input(geometry, events, { opponent = "Solo", boost = 1, soloEarnedToday = 300 })
		)
		expectPay(flat, "3:Ball:1 5:Ball:1", 2, "VIP solo past the cap")
		-- VIP past the PC cap: 10 x 2 x 0.5.
		local pc = Money.shotPay(
			input(geometry, events, { opponent = "PC", boost = 1, pcEarnedToday = 1000 })
		)
		expectPay(pc, "3:Ball:10 3:Bank:15 5:Ball:10 5:Combo:20", 55, "VIP PC past the cap")
		-- The counter takes the boosted money: 980 + 20 reaches the cap after the first ball.
		local crossing = Money.shotPay(
			input(geometry, events, { opponent = "PC", boost = 1, pcEarnedToday = 980 })
		)
		expectPay(crossing, "3:Ball:20 3:Bank:15 5:Ball:10 5:Combo:20", 65, "VIP crossing")
	end,

	["short matches: $1 a ball and no nice shots once the $200 is reached (ECONOMY 3.6)"] = function()
		local Money, geometry = setup()
		local Config = H.require("Config")
		H.expect(Config.Economy.ShortDailyCap == 200 and Config.Economy.ShortAfterCapPay == 1)
		local events = bankAndCombo(geometry)
		local short = Money.shotPay(input(geometry, events, { shortCapped = true }))
		expectPay(short, "3:Ball:1 5:Ball:1", 2, "short capped")
		H.expect(short.balls == 2 and short.nice == 0)
		-- Nothing multiplies it: not the difficulty, the boosts or the opponent.
		local boosted = { shortCapped = true, boost = 2, multiplier = 2, opponent = "PC" }
		local pc = Money.shotPay(input(geometry, events, boosted))
		expectPay(pc, "3:Ball:1 5:Ball:1", 2, "short capped, boosted, PC")
		H.expect(pc.pcEarned == 2, "still PC money")
		local mate =
			Money.shotPay(input(geometry, events, { shortCapped = true, isShooter = false }))
		expectPay(mate, "3:Ball:1 5:Ball:1", 2, "a teammate")
		-- Not capped (the mark has passed, or the total is under $200): full pay.
		local open = Money.shotPay(input(geometry, events, { shortCapped = false }))
		H.expect(open.total == 55)
	end,

	["same opponent in one UTC day: ECONOMY 3.6's rows"] = function()
		local Money, geometry = setup()
		local Config = H.require("Config")
		local function expectRow(
			n: number,
			xp: number,
			bonusShare: number,
			balls: number,
			case: boolean
		)
			local row = Money.farmRow(n)
			H.expect(
				row.Xp == xp
					and row.Bonus == bonusShare
					and row.Balls == balls
					and row.FreeCase == case,
				("match %s: Xp %s Bonus %s Balls %s FreeCase %s"):format(
					tostring(n),
					tostring(row.Xp),
					tostring(row.Bonus),
					tostring(row.Balls),
					tostring(row.FreeCase)
				)
			)
		end
		for n = 1, 5 do
			expectRow(n, 1, 1, 1, true) -- matches 1-5 in full
		end
		for n = 6, 10 do
			expectRow(n, 0.5, 0.5, 1, false) -- 6-10: half the XP and bonus, no free case
		end
		for _, n in { 11, 12, 50, 1000 } do
			expectRow(n, 0, 0.25, 0.5, false) -- from 11: no XP, a quarter bonus, half the balls
			H.expect(Money.farmRow(n).UpTo == nil, "the last row has no UpTo")
		end
		expectRow(0, 1, 1, 1, true) -- a bad count is the first match
		expectRow(0 / 0, 1, 1, 1, true)
		local copy = Money.farmRow(1)
		copy.Xp = 9
		H.expect(Money.farmRow(1).Xp == 1, "farmRow hands out copies")
		-- What the rows do to the pay.
		H.expect(Money.matchBonus(bonus("Win", { farm = 0.5 })) == 25)
		H.expect(Money.matchBonus(bonus("Loss", { farm = 0.5 })) == 8, "7.5 rounds up")
		H.expect(Money.matchBonus(bonus("Win", { farm = 0.25 })) == 13, "12.5 rounds up")
		H.expect(Money.matchBonus(bonus("Loss", { farm = 0.25 })) == 4, "3.75")
		local half = Money.shotPay(input(geometry, bankAndCombo(geometry), { farmBalls = 0.5 }))
		expectPay(half, "3:Ball:5 3:Bank:8 5:Ball:5 5:Combo:10", 28, "half the ball pay")
		-- The rest of 3.6 lives in Config for the server.
		local E = Config.Economy
		H.expect(E.FreeCasesPerOpponent == 3, "at most 3 free cases a day from one account")
		H.expect(E.FreeCaseLoserMinMatches == 5, "the loser must have played 5 real matches")
	end,

	["the win bonus follows the opponent gap, never under half (ECONOMY 4.4)"] = function()
		local Money = setup()
		local Ranks = H.require("Progression.Ranks")
		H.expect(Money.matchBonus(bonus("Win", { gap = 1 })) == 50)
		H.expect(Money.matchBonus(bonus("Win", { gap = 0.8 })) == 40)
		H.expect(Money.matchBonus(bonus("Win", { gap = 0.3 })) == 25, "never under half")
		H.expect(Money.matchBonus(bonus("Win", { gap = 0.1 })) == 25)
		H.expect(Money.matchBonus(bonus("Win", { gap = 1.3 })) == 65)
		H.expect(Money.matchBonus(bonus("Win", { gap = 4 })) == 75, "at most x1.5")
		H.expect(Money.matchBonus(bonus("Loss", { gap = 0.3 })) == 15, "the loss bonus ignores it")
		H.expect(Money.matchBonus(bonus("Loss", { gap = 1.5 })) == 15)
		H.expect(Money.matchBonus(bonus("Win", { opponent = "PC", gap = 0.3 })) == 13, "12.5")
		-- Silver V beating Bronze V (5 divisions lower): 50 x 0.554 = 27.7.
		H.expect(Money.matchBonus(bonus("Win", { gap = Ranks.gapFactor(10, 5) })) == 28)
		-- Everything at once: Challenger, VIP, half-farm, a stronger opponent.
		local all = { multiplier = 2, boost = 1, farm = 0.5, gap = 1.2 }
		H.expect(Money.matchBonus(bonus("Win", all)) == 120, "50 x 2 x 2 x 0.5 x 1.2")
	end,

	["win streak money: +$25 from the 3rd win in a row, people only (ECONOMY 3.1)"] = function()
		local Money = setup()
		H.expect(Money.streakBonus(0, "Player") == 0 and Money.streakBonus(1, "Player") == 0)
		H.expect(Money.streakBonus(2, "Player") == 0, "not the 2nd")
		H.expect(Money.streakBonus(3, "Player") == 25, "the 3rd")
		H.expect(Money.streakBonus(4, "Player") == 25 and Money.streakBonus(20, "Player") == 25)
		H.expect(Money.streakBonus(3, "PC") == 0 and Money.streakBonus(9, "Solo") == 0, "people")
		H.expect(Money.streakBonus(0 / 0, "Player") == 0)
		-- A match bonus, so the difficulty, the boosts and the anti-farm bonus apply.
		H.expect(Money.streakBonus(3, "Player", 2) == 50, "Challenger")
		H.expect(Money.streakBonus(3, "Player", 1, 1) == 50, "VIP doubles it")
		H.expect(Money.streakBonus(3, "Player", 2, 2) == 150, "x6")
		H.expect(Money.streakBonus(3, "Player", 1, 0, 0.5) == 13, "half-farm: 12.5")
		H.expect(Money.streakBonus(3, "Player", 1.5) == 38, "Difficult: 37.5")
	end,

	["an average match pays about ECONOMY 3.1's $134 and $60"] = function()
		local Money = setup()
		-- 3.1's model: the winner pots 7.5 balls with half a nice shot (a bank or a combo,
		-- $17.50 on average) and wins; the loser pots 4 balls and loses.
		local winner = 7.5 * 10 + 0.5 * 17.5 + Money.matchBonus(bonus("Win"))
		local loser = 4 * 10 + Money.matchBonus(bonus("Loss"))
		H.near(winner, 134, 1, "the winner")
		H.near(loser, 55, 5, "the loser, about $60 with a nice shot now and then")
		H.near((winner + loser) / 2 * 7.5, 730, 25, "about $730 an hour at 7.5 matches")
	end,
}
