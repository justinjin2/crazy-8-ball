--!strict
-- Settle: the pure choices the server makes when it pays a shot or a finished match
-- (Progression/Settle; src/server/Economy.luau and Ranking.luau call them). Expected numbers
-- are written out from docs/ECONOMY.md (3.3, 3.6, 4.4, 4.5, 7.1), not read from Config.

local H = require("./harness")

local function load()
	return H.require("Progression.Settle"),
		H.require("Progression.Cases"),
		H.require("Progression.Money")
end

-- A winner's free-case facts: an established player's 60th win, 3rd of the day, against one
-- fresh-today account with plenty of real matches, unless `overrides` says otherwise.
local function facts(overrides: { [string]: any }?): any
	local base: { [string]: any } = {
		real = true,
		solo = false,
		won = true,
		pc = false,
		winsBefore = 60,
		winsTodayBefore = 2,
		firstWinDue = false,
		farmAllows = true,
		losers = { { realMatches = 40, casesToday = 0 } },
	}
	for key, value in overrides or {} do
		base[key] = value
	end
	return base
end

return {
	["opponentKind: solo, PC (marked on the engine) or people"] = function()
		local Settle = load()
		H.expect(Settle.opponentKind({ solo = { team = 1 } }) == "Solo", "solo")
		H.expect(Settle.opponentKind({ pc = true }) == "PC", "pc")
		H.expect(Settle.opponentKind({}) == "Player", "people")
		H.expect(Settle.opponentKind({ solo = { team = 1 }, pc = true }) == "Solo", "solo first")
	end,

	["isReal: one minute of server time from the break (GDD 13)"] = function()
		local Settle = load()
		H.expect(not Settle.isReal(59.9), "59.9 s")
		H.expect(Settle.isReal(60), "60 s")
		H.expect(Settle.isReal(400), "400 s")
		H.expect(not Settle.isReal(nil), "nil")
		H.expect(not Settle.isReal(0 / 0), "NaN")
	end,

	["forfeitTeam: surrender, the side that emptied, an early 8 under the mark"] = function()
		local Settle = load()
		H.expect(Settle.forfeitTeam({ winner = 1, reason = "Surrender", forfeit = 2 }, true) == 2)
		H.expect(Settle.forfeitTeam({ winner = 2, reason = "EmptyTeam" }, true) == 1, "left")
		H.expect(Settle.forfeitTeam({ winner = 2, reason = "EarlyEight" }, false) == 1, "early")
		H.expect(Settle.forfeitTeam({ winner = 2, reason = "EarlyEight" }, true) == nil, "late 8")
		H.expect(Settle.forfeitTeam({ winner = 1, reason = "LegalEight" }, false) == nil, "legal")
		H.expect(Settle.forfeitTeam({ reason = "EmptyTeam" }, true) == nil, "nobody won")
	end,

	["outcome: win, loss, draw"] = function()
		local Settle = load()
		H.expect(Settle.outcome(1, 1) == "Win")
		H.expect(Settle.outcome(2, 1) == "Loss")
		H.expect(Settle.outcome(1, nil) == "Draw")
	end,

	["opponentIndex: the other side's average, Unranked as Bronze I (4.4)"] = function()
		local Settle = load()
		H.expect(Settle.opponentIndex({}) == nil, "nobody known")
		H.expect(Settle.opponentIndex({ 0 }) == 1, "Unranked is Bronze I")
		H.expect(Settle.opponentIndex({ 11 }) == 11, "Gold I")
		-- Unranked and Gold I: (1 + 11) / 2, not (0 + 11) / 2.
		H.expect(Settle.opponentIndex({ 0, 11 }) == 6, "Unranked counted before averaging")
		H.expect(Settle.opponentIndex({ 20, 25, 30 }) == 25, "a 3v3 side")
	end,

	["matchNumber: this match against the most-played opponent today (3.6)"] = function()
		local Settle, _, Money = load()
		H.expect(Settle.matchNumber({}) == 1, "PC or nobody")
		H.expect(Settle.matchNumber({ 0 }) == 1, "first today")
		H.expect(Settle.matchNumber({ 4, 7 }) == 8, "the most-played of two")
		-- Matches 1-5 full; 6-10 half XP and bonus, no free case; 11+ no XP, a quarter of the
		-- bonus, half the ball pay.
		local fifth = Money.farmRow(Settle.matchNumber({ 4 }))
		H.expect(fifth.Xp == 1 and fifth.Bonus == 1 and fifth.Balls == 1 and fifth.FreeCase)
		local sixth = Money.farmRow(Settle.matchNumber({ 5 }))
		H.expect(sixth.Xp == 0.5 and sixth.Bonus == 0.5 and sixth.Balls == 1, "6th")
		H.expect(not sixth.FreeCase, "6th drops no case")
		local eleventh = Money.farmRow(Settle.matchNumber({ 2, 10 }))
		H.expect(eleventh.Xp == 0 and eleventh.Bonus == 0.25 and eleventh.Balls == 0.5, "11th")
	end,

	["opponentDay: once the table is full, a new one reads as the worst (3.6)"] = function()
		local Settle, Cases, Money = load()
		local full = H.require("Config").Economy.SameOpponentMaxEntries
		local met = Settle.opponentDay({ Matches = 4, Cases = 1 }, full)
		H.expect(met.Matches == 4 and met.Cases == 1, "a tracked account: its own entry")
		local fresh = Settle.opponentDay(nil, full - 1)
		H.expect(fresh.Matches == 0 and fresh.Cases == 0, "room left: a new account is match 1")
		for _, tracked in { full, full + 1 } do
			local worst = Settle.opponentDay(nil, tracked)
			-- 10 matches already (the 11th row) and 3 cases already.
			H.expect(worst.Matches == 10 and worst.Cases == 3, ("full at %d"):format(tracked))
			local row = Money.farmRow(Settle.matchNumber({ worst.Matches }))
			H.expect(row.Xp == 0 and row.Bonus == 0.25 and row.Balls == 0.5, "it pays the floor")
			H.expect(not row.FreeCase, "its row drops no case")
			local ctx = Settle.freeCaseContext(facts({
				farmAllows = row.FreeCase,
				losers = { { realMatches = 40, casesToday = worst.Cases } },
			}))
			H.expect(Cases.freeCase(ctx) == nil, "no free case")
			-- Its cases alone stop one too, whatever the row says.
			local cases = Settle.freeCaseContext(facts({
				losers = { { realMatches = 40, casesToday = worst.Cases } },
			}))
			H.expect(Cases.freeCase(cases) == nil, "3 cases from it already")
		end
		-- A team match with one untracked account is played at the floor (the most-played).
		local team = Settle.matchNumber({ 0, Settle.opponentDay(nil, full).Matches })
		H.expect(Money.farmRow(team).Xp == 0, "the team match's row is the worst")
		local odd = Settle.opponentDay({ Matches = -3, Cases = 0.5 }, 0)
		H.expect(odd.Matches == 0 and odd.Cases == 0, "a bad entry reads as whole numbers")
	end,

	["shortCapped: $2,000 of short-match money today, before the one-minute mark (3.6)"] = function()
		local Settle = load()
		H.expect(not Settle.shortCapped(1999, 10), "under the cap")
		H.expect(Settle.shortCapped(2000, 10), "at the cap, 10 s in")
		H.expect(Settle.shortCapped(4500, nil), "at the cap, before the break")
		H.expect(not Settle.shortCapped(2000, 60), "past the mark pays in full")
	end,

	["moneyKind: a disguised bot pays the PC rows from the 20th disguised win of the day"] = function()
		local Settle = load()
		local Config = H.require("Config")
		local cap = Config.Economy.DisguisedDailyWins
		H.expect(cap == 20, "the plan's 20")
		local disguised =
			{ seats = { { userId = 1 }, { userId = -1, bot = { kind = "Disguised" } } } }
		H.expect(Settle.moneyKind(disguised, 0) == "Player", "pays like a person at first")
		H.expect(Settle.moneyKind(disguised, cap - 1) == "Player", "the 20th win still pays")
		H.expect(Settle.moneyKind(disguised, cap) == "PC", "after 20 wins: the PC rows")
		H.expect(Settle.moneyKind(disguised, 0 / 0) == "Player", "a bad count reads as 0")
		H.expect(Settle.opponentKind(disguised) == "Player", "the XP still sees a person")
		local people = { seats = { { userId = 1 }, { userId = 2 } } }
		H.expect(Settle.moneyKind(people, 99) == "Player", "people always pay as people")
		local pc = { pc = true, seats = { { userId = 1 } } }
		H.expect(Settle.moneyKind(pc, 0) == "PC", "PC is PC")
		H.expect(Settle.moneyKind({ solo = 1, seats = {} }, 99) == "Solo", "solo is solo")
	end,

	["boosts: only the streak, from the 3rd win in a row (4.3, 4.5)"] = function()
		local Settle = load()
		local function flags(overrides: { [string]: any }): any
			local base: { [string]: any } = { won = true, streakAfter = 1 }
			for key, value in overrides do
				base[key] = value
			end
			return Settle.boosts(base)
		end
		H.expect(not flags({ streakAfter = 2 }).streak, "2nd win in a row")
		H.expect(flags({ streakAfter = 3 }).streak, "3rd win in a row")
		H.expect(not flags({ streakAfter = 5, won = false }).streak, "never on a loss")
		local all = flags({ streakAfter = 3 })
		H.expect(all.rookie == nil and all.vip == nil and all.firstWin == nil, "no other boosts")
	end,

	["freeCaseContext: a win against an established account drops by the daily rule (7.1)"] = function()
		local Settle, Cases = load()
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts())) == "Standard", "3rd win today")
		-- 11th win of the day: nothing; 12th: a case (then every 2nd).
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts({ winsTodayBefore = 10 }))) == nil)
		H.expect(
			Cases.freeCase(Settle.freeCaseContext(facts({ winsTodayBefore = 11 }))) == "Standard",
			"12th win today"
		)
		-- The first 50 wins ever: every win, even past 10 today.
		H.expect(
			Cases.freeCase(Settle.freeCaseContext(facts({ winsBefore = 49, winsTodayBefore = 30 })))
				== "Standard",
			"50th win ever"
		)
	end,

	["freeCaseContext: the first win ever is the Rare Case, under the same anti-farm rules"] = function()
		local Settle, Cases = load()
		local first = facts({ winsBefore = 0, winsTodayBefore = 0, firstWinDue = true })
		H.expect(Cases.freeCase(Settle.freeCaseContext(first)) == "Rare", "first win")
		-- A fresh loser (4 real matches) feeds nothing, not even the first win's case.
		first.losers = { { realMatches = 4, casesToday = 0 } }
		H.expect(Cases.freeCase(Settle.freeCaseContext(first)) == nil, "fresh loser")
		-- An unknown account never allows one.
		first.losers = { { realMatches = nil, casesToday = 0 } }
		H.expect(Cases.freeCase(Settle.freeCaseContext(first)) == nil, "unknown loser")
	end,

	["freeCaseContext: anti-farm (3.6): the 6th match, 3 cases from one account, solo"] = function()
		local Settle, Cases = load()
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts({ farmAllows = false }))) == nil)
		local third = facts({ losers = { { realMatches = 40, casesToday = 3 } } })
		H.expect(Cases.freeCase(Settle.freeCaseContext(third)) == nil, "3 from this account")
		local two = facts({ losers = { { realMatches = 40, casesToday = 2 } } })
		H.expect(Cases.freeCase(Settle.freeCaseContext(two)) == "Standard", "2 so far")
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts({ solo = true }))) == nil, "solo")
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts({ real = false }))) == nil, "short")
		H.expect(Cases.freeCase(Settle.freeCaseContext(facts({ won = false }))) == nil, "loss")
	end,

	["freeCaseContext: a team's most experienced loser counts; any loser's 3 cases stop it"] = function()
		local Settle, Cases = load()
		local ctx = Settle.freeCaseContext(facts({
			losers = {
				{ realMatches = 2, casesToday = 0 },
				{ realMatches = 12, casesToday = 1 },
			},
		}))
		H.expect(ctx.loserRealMatches == 12 and ctx.casesFromOpponentToday == 1)
		H.expect(Cases.freeCase(ctx) == "Standard", "one established loser is enough")
		local capped = Settle.freeCaseContext(facts({
			losers = {
				{ realMatches = 12, casesToday = 0 },
				{ realMatches = 12, casesToday = 3 },
			},
		}))
		H.expect(Cases.freeCase(capped) == nil, "one loser already gave 3 today")
	end,

	["freeCaseContext: a PC win drops under the same daily limits, no account rules"] = function()
		local Settle, Cases = load()
		local pc = Settle.freeCaseContext(facts({ pc = true, farmAllows = false, losers = {} }))
		H.expect(pc.farmAllows and pc.casesFromOpponentToday == 0, "no account to farm")
		H.expect(pc.loserRealMatches >= 5, "the loser rule is met")
		H.expect(Cases.freeCase(pc) == "Standard", "PC win")
		local late = Settle.freeCaseContext(facts({ pc = true, losers = {}, winsTodayBefore = 10 }))
		H.expect(Cases.freeCase(late) == nil, "the 11th win of the day, PC too")
	end,
}
