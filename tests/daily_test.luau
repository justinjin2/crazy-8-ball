--!strict
-- Daily rewards: the first week, the later weeks' loop and its freeze, the 28-day track,
-- playtime gifts and promo codes (Progression/Daily, numbers in Config.Daily), and the
-- RewardState payload built from them (Progression/RewardView). Expected values are the
-- economy v4 plan's (2026-10-08, section 6), written out here.

local H = require("./harness")

local Config = H.require("Config")
local Daily = H.require("Progression.Daily")
local RewardView = H.require("Progression.RewardView")

-- A day far from zero, so "yesterday" is never day 0.
local TODAY = 20724
local SECONDS_PER_DAY = 86400
-- Days start at 08:00 UTC (Config.Daily.ResetHour).
local RESET = 8 * 3600
-- An hour into TODAY, as a unix time.
local NOW = TODAY * SECONDS_PER_DAY + RESET + 3600

-- The later weeks (economy v5 plan section 4).
local STREAK = {
	"$5000",
	"Mystery x1",
	"$10000",
	"Mystery x1",
	"$15000",
	"Mystery x1",
	"Rare x1 Spins x2",
}

-- The first week (economy v5 plan section 4).
local FIRST = {
	"$5000 Mystery x1",
	"Rare x1",
	"$10000",
	"Mystery x2",
	"$15000",
	"Mystery x2",
	"Cue:WeekOneCue Spins x2",
}

-- A reward as one short line: "$5000", "Rare x1 Mystery x2 Spins x1", "nothing". Blocks
-- are listed in Config.LuckyBlocks.Order (the tiers, then Mystery).
local function describe(reward: any): string
	local words = {}
	if reward.money > 0 then
		table.insert(words, "$" .. reward.money)
	end
	for _, entry in Daily.blockList(reward) do
		table.insert(words, ("%s x%d"):format(entry.kind, entry.count))
	end
	for _, id in reward.cues or {} do
		table.insert(words, "Cue:" .. id)
	end
	if (reward.spins or 0) > 0 then
		table.insert(words, ("Spins x%d"):format(reward.spins))
	end
	return if #words == 0 then "nothing" else table.concat(words, " ")
end

local function fresh(): any
	return { LastDay = 0, StreakDay = 0, Total = 0, FreezeWeek = 0 }
end

-- Claims on each UTC day in `days`; returns the final login and each claim's state and reward.
local function claimOn(login: any, days: { number }, vip: boolean?): (any, { any })
	local claims = {}
	for _, today in days do
		local state = Daily.loginState(login, today, vip)
		local ok, newLogin, reward = Daily.claimLogin(login, today, vip)
		H.expect(ok, ("claim on day %d refused"):format(today))
		table.insert(claims, {
			day = state.day,
			week = state.week,
			total = state.total,
			frozen = state.frozen,
			reward = reward,
			bonus = state.bonus,
		})
		login = newLogin
	end
	return login, claims
end

-- Claims `count` days in a row from `firstDay`.
local function claimRun(login: any, firstDay: number, count: number): (any, { any })
	local days = {}
	for i = 0, count - 1 do
		table.insert(days, firstDay + i)
	end
	return claimOn(login, days)
end

local function withCode(code: string, row: any, fn: () -> ())
	Config.Daily.Codes[code] = row
	local ok, err = pcall(fn)
	Config.Daily.Codes[code] = nil
	if not ok then
		error(err, 0)
	end
end

return {
	["dayOf: days start at 08:00 UTC"] = function()
		H.expect(Config.Daily.ResetHour == 8, "the v4 plan's 08:00 UTC")
		H.expect(Daily.dayOf(RESET) == 0, "08:00 on 1970-01-01 starts day 0")
		H.expect(Daily.dayOf(RESET - 1) == -1, "07:59:59 is still the day before")
		H.expect(Daily.dayOf(RESET + 86399) == 0, "last second of day 0")
		H.expect(Daily.dayOf(RESET + 86400) == 1, "first second of day 1")
		H.expect(Daily.dayOf(1790553600 + RESET) == 20724, "2026-09-28 08:00 UTC")
		H.expect(Daily.dayOf(1790553600) == 20723, "midnight UTC is the day before")
		H.expect(Daily.dayOf(1790553600 + RESET + 86399.5) == 20724, "a fraction before")
		H.expect(Daily.dayStart(20724) == 1790553600 + RESET, "the day's start")
	end,

	["weeks start on Monday"] = function()
		-- 2026-09-28 (TODAY) is a Monday; the Sunday before is the week before.
		H.expect(Daily.weekOf(TODAY) == Daily.weekOf(TODAY + 6), "Monday to Sunday")
		H.expect(Daily.weekOf(TODAY - 1) == Daily.weekOf(TODAY) - 1, "Sunday is last week")
		H.expect(Daily.weekOf(TODAY + 7) == Daily.weekOf(TODAY) + 1, "next Monday")
	end,

	["the later weeks' seven loop days match the plan"] = function()
		H.expect(#Config.Daily.Streak == 7, "seven loop days")
		local _, claims = claimRun(fresh(), TODAY, 7)
		for i, claim in claims do
			H.expect(
				claim.day == i and claim.total == i,
				("claim %d is day %d"):format(i, claim.day)
			)
			local expected = STREAK[i]
			H.expect(
				describe(claim.reward) == expected,
				("day %d gives %s, expected %s"):format(i, describe(claim.reward), expected)
			)
			H.expect(not claim.bonus, ("day %d track flag"):format(i))
			local tile = Daily.streakReward(i)
			H.expect(describe(tile) == STREAK[i], ("tile %d shows %s"):format(i, describe(tile)))
		end
	end,

	["VIP adds an Uncommon block and one ability spin to every day's claim"] = function()
		local state = Daily.loginState(fresh(), TODAY, true)
		H.expect(describe(state.reward) == "$5000 Uncommon x1 Spins x1", describe(state.reward))
		local _, claims = claimOn(fresh(), { TODAY }, true)
		H.expect(claims[1].reward.spins == Config.Daily.VipSpins, "claimed with it")
		H.expect(claims[1].reward.blocks.Uncommon == 1, "VIP's daily Uncommon block")
		H.expect(
			describe(Daily.streakReward(7, true)) == "Uncommon x1 Rare x1 Spins x3",
			"day 7's tile"
		)
		H.expect(Daily.loginState(fresh(), TODAY).reward.spins == 0, "not without VIP")
		-- Where paid random items are restricted: $5,000 instead of the block and the spin.
		local restricted = Daily.loginState(fresh(), TODAY, true, { restricted = true })
		H.expect(describe(restricted.reward) == "$10000", describe(restricted.reward))
		H.expect(Config.Daily.VipRestrictedMoney == 5000, "the plan's $5,000")
		local first = Daily.firstWeekReward(2, true)
		H.expect(describe(first) == "Uncommon x1 Rare x1 Spins x1", "on first-week days too")
	end,

	["the first week: any 7 login days within 14 of joining, then the later weeks"] = function()
		H.expect(#Config.Daily.FirstWeek == 7 and Config.Daily.FirstWeekWindow == 14, "7 in 14")
		local extra = { joinDay = TODAY }
		-- Days 1, 2, 4, 5, 9, 12 and 14 of the window: every claim is the next first-week day.
		local login = fresh()
		for i, offset in { 0, 1, 3, 4, 8, 11, 13 } do
			local state = Daily.loginState(login, TODAY + offset, nil, extra)
			H.expect(state.firstWeek and state.day == i, ("first-week day %d"):format(i))
			H.expect(state.firstWeekLeft == 14 - offset, "days left in the window")
			local ok, newLogin, reward = Daily.claimLogin(login, TODAY + offset, nil, extra)
			H.expect(
				ok and describe(reward) == FIRST[i],
				("day %d: %s"):format(i, describe(reward))
			)
			H.expect(
				newLogin.StreakDay == 0 and newLogin.FirstWeek == i,
				"stored as the first week"
			)
			local after = Daily.loginState(newLogin, TODAY + offset, nil, extra)
			H.expect(after.claimedToday and after.firstWeek and after.day == i, "claimed today")
			H.expect(after.firstWeekDays == i, "counted")
			login = newLogin
		end
		-- The next claim is the later weeks' day 1; the 28-day track's day 8 adds its $50,000.
		local next = Daily.loginState(login, TODAY + 14, nil, extra)
		H.expect(not next.firstWeek and next.day == 1, "the later weeks start at day 1")
		H.expect(describe(next.reward) == "$55000" and next.bonus, "day 8's money")
		H.expect(next.firstWeekLeft == 0, "the window is over")
		-- After the window, the first week is over even with days left: later weeks.
		local late = fresh()
		for _, offset in { 0, 1, 2 } do
			local _, newLogin = Daily.claimLogin(late, TODAY + offset, nil, extra)
			late = newLogin
		end
		local inside = Daily.loginState(late, TODAY + 13, nil, extra)
		H.expect(inside.firstWeek and inside.day == 4, "day 14 is still inside")
		local outside = Daily.loginState(late, TODAY + 14, nil, extra)
		H.expect(not outside.firstWeek and outside.day == 1, "day 15 is the later weeks")
		H.expect(describe(outside.reward) == "$5000", "the later weeks' day 1")
		-- Without a join day (an old caller), there is no first week.
		H.expect(not Daily.loginState(fresh(), TODAY).firstWeek, "no join day: later weeks")
	end,

	["a login day counts only once a match was finished that day"] = function()
		H.expect(Config.Daily.NeedsMatch == true, "the v4 plan's match rule")
		local waiting = { joinDay = TODAY, played = false }
		local state = Daily.loginState(fresh(), TODAY, nil, waiting)
		H.expect(not state.canClaim and state.needsMatch, "waits for a match")
		H.expect(state.firstWeek and state.day == 1, "still shows the day it will be")
		local ok, same, reward = Daily.claimLogin(fresh(), TODAY, nil, waiting)
		H.expect(not ok and reward == nil and same.LastDay == 0, "refused")
		local played = { joinDay = TODAY, played = true }
		H.expect(Daily.loginState(fresh(), TODAY, nil, played).canClaim, "after a match")
		H.expect((Daily.claimLogin(fresh(), TODAY, nil, played)), "claimed")
		local _, claimed = Daily.claimLogin(fresh(), TODAY, nil, played)
		local done = Daily.loginState(claimed, TODAY, nil, waiting)
		H.expect(done.claimedToday and not done.needsMatch, "a claimed day never waits")
	end,

	["claiming twice in a day is refused"] = function()
		local ok, login, reward = Daily.claimLogin(fresh(), TODAY)
		H.expect(ok and reward ~= nil, "first claim")
		local state = Daily.loginState(login, TODAY)
		H.expect(state.claimedToday and not state.canClaim, "claimed today")
		H.expect(state.day == 1 and describe(state.reward) == "$5000", "state still shows day 1")
		H.expect(state.total == 1, "one day claimed")
		local again, same, none = Daily.claimLogin(login, TODAY)
		H.expect(not again and none == nil, "second claim refused")
		H.expect(
			same.LastDay == TODAY and same.StreakDay == 1 and same.Total == 1,
			"login unchanged"
		)
		H.expect(same ~= login, "a copy, not the same table")
	end,

	["claimLogin never changes the table it is given"] = function()
		local login = { LastDay = TODAY - 1, StreakDay = 3, Total = 10, FreezeWeek = 0 }
		local ok, newLogin = Daily.claimLogin(login, TODAY)
		H.expect(ok, "claimed")
		H.expect(
			login.LastDay == TODAY - 1 and login.StreakDay == 3 and login.Total == 10,
			"input untouched"
		)
		H.expect(
			newLogin.LastDay == TODAY and newLogin.StreakDay == 4 and newLogin.Total == 11,
			"day 4, the 11th day"
		)
	end,

	["the week's freeze covers one missed day; two missed days start over"] = function()
		local week = Daily.weekOf(TODAY)
		-- Monday to Wednesday, Thursday missed, Friday: the freeze keeps the streak.
		local login, claims = claimOn(fresh(), { TODAY, TODAY + 1, TODAY + 2, TODAY + 4 })
		H.expect(claims[4].day == 4 and claims[4].frozen, "day 4 through the freeze")
		H.expect(login.FreezeWeek == week, "this week's freeze used")
		H.expect(not Daily.loginState(login, TODAY + 5).freezeReady, "used up this week")
		-- Saturday claimed, Sunday missed: the freeze is used, so Monday... is a new week.
		local after, more = claimOn(login, { TODAY + 5, TODAY + 7 })
		H.expect(more[1].day == 5 and not more[1].frozen, "Saturday continues")
		H.expect(more[2].day == 6 and more[2].frozen, "next Monday: a new week's freeze")
		-- Another miss in the same week starts over.
		local reset = Daily.loginState(after, TODAY + 9)
		H.expect(reset.day == 1 and not reset.frozen, "one freeze a week")
		-- Two missed days in a row start over even with the freeze unused.
		local two = Daily.loginState(claimRun(fresh(), TODAY, 3), TODAY + 5)
		H.expect(two.day == 1 and not two.frozen and two.freezeReady, "two missed days")
		H.expect(describe(two.reward) == "$5000", "day 1's reward")
	end,

	["the 28-day track counts every day claimed and repeats"] = function()
		local login, claims = claimRun(fresh(), TODAY, 56)
		local trackOn = {
			[8] = "$55000",
			[14] = "Rare x2 Spins x2",
			[21] = "$150000 Rare x1 Spins x2",
			[28] = "Rare x1 Epic x1 Spins x2",
		}
		for i, claim in claims do
			local place = (i - 1) % 28 + 1
			local expected = trackOn[place] or STREAK[(i - 1) % 7 + 1]
			H.expect(claim.total == i and claim.week == (place - 1) // 7 + 1, "the place")
			H.expect(
				describe(claim.reward) == expected,
				("claim %d gives %s, expected %s"):format(i, describe(claim.reward), expected)
			)
			H.expect(claim.bonus == (trackOn[place] ~= nil), ("claim %d track flag"):format(i))
		end
		H.expect(login.Total == 56 and login.StreakDay == 7, "56 days, loop day 7")
		-- A reset streak keeps the track: day 8 of the track lands on loop day 3.
		local broken = claimRun(fresh(), TODAY, 5)
		local _, later = claimOn(broken, { TODAY + 8, TODAY + 9, TODAY + 10 })
		H.expect(later[1].day == 1 and later[3].day == 3 and later[3].total == 8, "counted")
		H.expect(describe(later[3].reward) == "$60000", describe(later[3].reward))
		H.expect(Daily.trackReward(36) ~= nil and Daily.trackReward(35) == nil, "repeats")
	end,

	["a claim dated tomorrow by another server's clock still counts as today"] = function()
		local skewed = { LastDay = TODAY + 1, StreakDay = 2, Total = 2, FreezeWeek = 0 }
		local state = Daily.loginState(skewed, TODAY)
		H.expect(state.claimedToday and not state.canClaim, "no second claim")
		H.expect(state.day == 2, "the streak kept")
		H.expect(Daily.loginState(skewed, TODAY + 2).day == 3, "continues the day after")
		-- A LastDay far ahead is a broken save: start again rather than lock claims.
		local broken = { LastDay = TODAY + 30, StreakDay = 4, Total = 9, FreezeWeek = 0 }
		local fixed = Daily.loginState(broken, TODAY)
		H.expect(fixed.canClaim and fixed.day == 1 and fixed.total == 10, "a broken save restarts")
	end,

	["bad login data never crashes and starts at day 1"] = function()
		for _, login in { {}, { LastDay = "x", StreakDay = 99, Total = -1 }, { LastDay = 0 / 0 } } do
			local state = Daily.loginState(login :: any, TODAY)
			H.expect(state.canClaim and state.day == 1 and state.total == 1, "day 1")
		end
	end,

	["setStreakDay makes the next claim that day"] = function()
		for week = 1, 4 do
			for n = 1, 7 do
				local login = Daily.setStreakDay(fresh(), TODAY, n, week)
				local state = Daily.loginState(login, TODAY)
				H.expect(state.canClaim, ("day %d week %d claimable"):format(n, week))
				H.expect(
					state.day == n and state.week == week and state.total == (week - 1) * 7 + n,
					("set %d/%d gave %d/%d"):format(n, week, state.day, state.week)
				)
				local ok, _, reward = Daily.claimLogin(login, TODAY)
				H.expect(ok and reward ~= nil, "claims")
				-- Day 7's Rare block; the track adds a Rare on day 14 and an Epic on day 28.
				local rares = if n == 7 then (if week == 2 then 2 else 1) else nil
				H.expect((reward :: any).blocks.Rare == rares, "day 7's Rare block, two on day 14")
				local epic = if n == 7 and week == 4 then 1 else nil
				H.expect((reward :: any).blocks.Epic == epic, "day 28's Epic block")
				H.expect((reward :: any).blocks.Legendary == nil, "no Legendary block")
			end
		end
		-- Already claimed today: the command still lets day n be claimed now.
		local _, claimed = Daily.claimLogin(
			{ LastDay = TODAY - 1, StreakDay = 2, Total = 2, FreezeWeek = 0 },
			TODAY
		)
		local reset = Daily.setStreakDay(claimed, TODAY, 7)
		local state = Daily.loginState(reset, TODAY)
		H.expect(state.canClaim and state.day == 7, "day 7 now")
		-- The first week's days too (inside the window).
		local firstDay = Daily.setStreakDay(fresh(), TODAY, 7, nil, true)
		local first = Daily.loginState(firstDay, TODAY, nil, { joinDay = TODAY - 6 })
		H.expect(first.canClaim and first.firstWeek and first.day == 7, "first-week day 7")
		local later = Daily.loginState(reset, TODAY, nil, { joinDay = TODAY })
		H.expect(not later.firstWeek, "setting a loop day ends the first week")
		-- Out of range numbers clamp.
		H.expect(
			Daily.loginState(Daily.setStreakDay(fresh(), TODAY, 12), TODAY).day == 7,
			"clamped to 7"
		)
		H.expect(
			Daily.loginState(Daily.setStreakDay(fresh(), TODAY, 0), TODAY).day == 1,
			"clamped to 1"
		)
	end,

	["playtime gifts at 5, 15, 30, 45 and 60 minutes"] = function()
		local expected = {
			{ 5, "$1000" },
			{ 15, "Mystery x1" },
			{ 30, "$2500" },
			{ 45, "$3500" },
			{ 60, "$5000 Spins x1" },
		}
		local daily = { PlaySeconds = 0, PlaytimeClaimed = {} }
		local gifts = Daily.playtimeState(daily)
		H.expect(#gifts == 5, "five gifts")
		for i, gift in gifts do
			H.expect(gift.index == i, "index")
			H.expect(
				gift.minutes == expected[i][1],
				("gift %d at %d minutes"):format(i, gift.minutes)
			)
			H.expect(
				describe(gift.reward) == expected[i][2],
				("gift %d gives %s"):format(i, describe(gift.reward))
			)
			H.expect(not gift.ready and not gift.claimed and gift.progress == 0, "nothing yet")
		end
		local function readyAt(seconds: number): string
			daily.PlaySeconds = seconds
			local flags = {}
			for _, gift in Daily.playtimeState(daily) do
				table.insert(flags, if gift.ready then "R" else "-")
			end
			return table.concat(flags)
		end
		H.expect(readyAt(299) == "-----", "299 s")
		H.expect(readyAt(300) == "R----", "5 minutes")
		H.expect(readyAt(900) == "RR---", "15 minutes")
		H.expect(readyAt(1800) == "RRR--", "30 minutes")
		H.expect(readyAt(2699) == "RRR--", "2699 s")
		H.expect(readyAt(2700) == "RRRR-", "45 minutes")
		H.expect(readyAt(3600) == "RRRRR", "60 minutes")
		daily.PlaySeconds = 150
		local half = Daily.playtimeState(daily)
		H.near(half[1].progress, 0.5, 1e-9, "2.5 of 5 minutes")
		H.near(half[2].progress, 150 / 900, 1e-9, "2.5 of 15 minutes")
		daily.PlaySeconds = 99999
		H.expect(Daily.playtimeState(daily)[5].progress == 1, "progress stops at 1")
	end,

	["each playtime gift claims once"] = function()
		local daily: any = { PlaySeconds = 600, PlaytimeClaimed = {} }
		local ok, why = Daily.claimPlaytime(daily, 2)
		H.expect(not ok and why == "NotReady", "15-minute gift not ready at 10 minutes")
		local got, reward = Daily.claimPlaytime(daily, 1)
		H.expect(got and describe(reward) == "$1000", "5-minute gift")
		H.expect(daily.PlaytimeClaimed["1"] == true, "marked with a string key")
		local again, reason = Daily.claimPlaytime(daily, 1)
		H.expect(not again and reason == "Claimed", "only once")
		local state = Daily.playtimeState(daily)
		H.expect(state[1].claimed and not state[1].ready, "shown as claimed")
		daily.PlaySeconds = 1800
		H.expect((Daily.claimPlaytime(daily, 3)), "30-minute gift")
		H.expect((Daily.claimPlaytime(daily, 2)), "15-minute gift, out of order")
		for _, bad in { 0, 6, 1.5, "1", 0 / 0, math.huge } do
			local fine, whyBad = Daily.claimPlaytime(daily, bad)
			H.expect(not fine and whyBad == "Unknown", ("%s is unknown"):format(tostring(bad)))
		end
		local none, whyNone = Daily.claimPlaytime(daily, nil)
		H.expect(not none and whyNone == "Unknown", "nil is unknown")
		-- A day's save from before the gifts existed gets its table on the first claim.
		local old: any = { PlaySeconds = 600 }
		H.expect((Daily.claimPlaytime(old, 1)) and old.PlaytimeClaimed["1"] == true, "table made")
	end,

	["codes are normalized: trimmed, any case, letters and digits only"] = function()
		H.expect(Daily.normalizeCode("  welcome  ") == "WELCOME", "trimmed and upper-cased")
		H.expect(Daily.normalizeCode("WeLcOmE") == "WELCOME", "mixed case")
		H.expect(Daily.normalizeCode("8ball") == "8BALL", "digits")
		H.expect(Daily.normalizeCode("\twelcome\n") == "WELCOME", "tabs and newlines")
		for _, bad in { "", "   ", "8 BALL", "8ball!", "wel-come", "café", "ÅÄÖ" } do
			H.expect(Daily.normalizeCode(bad) == nil, ("%q is not a code"):format(bad))
		end
		local max = Config.Daily.CodeMaxLength
		H.expect(Daily.normalizeCode(("A"):rep(max)) == ("A"):rep(max), "exactly the longest")
		H.expect(Daily.normalizeCode(("A"):rep(max + 1)) == nil, "one too long")
		H.expect(
			Daily.normalizeCode((" "):rep(100000) .. "x" .. (" "):rep(100000)) == nil,
			"huge text"
		)
		for _, notText in { 5, true, {} } do
			H.expect(Daily.normalizeCode(notText) == nil, "not a string")
		end
		H.expect(Daily.normalizeCode(nil) == nil, "nil")
	end,

	["WELCOME and 8BALL pay once each, in any case"] = function()
		local codes = {}
		local ok, reward = Daily.redeem(codes, "welcome", TODAY * 86400)
		H.expect(ok and describe(reward) == "$5000 Mystery x1", "WELCOME: $5,000 and a block")
		H.expect(codes.WELCOME == true, "saved upper-case")
		local again, why = Daily.redeem(codes, " WELCOME ", TODAY * 86400)
		H.expect(not again and why == "Used", "once per player")
		local ok8, reward8 = Daily.redeem(codes, "8Ball", TODAY * 86400)
		H.expect(ok8 and describe(reward8) == "$2500", "8BALL: $2,500")
		-- Another player's save is separate.
		H.expect((Daily.redeem({}, "WELCOME", TODAY * 86400)), "a second player can redeem it")
	end,

	["unknown, bad and expired codes are refused and never saved"] = function()
		local codes = {}
		local ok, why = Daily.redeem(codes, "NOSUCHCODE", 0)
		H.expect(not ok and why == "Unknown", "unknown")
		local ok2, why2 = Daily.redeem(codes, "!!", 0)
		H.expect(not ok2 and why2 == "Bad", "bad text")
		local ok3, why3 = Daily.redeem(codes, 42 :: any, 0)
		H.expect(not ok3 and why3 == "Bad", "not text")
		H.expect(next(codes) == nil, "nothing saved")
		withCode("TESTEXPIRY", { Money = 10, Expires = 5000 }, function()
			local early = {}
			H.expect((Daily.redeem(early, "testexpiry", 4999)), "works a second before")
			local late = {}
			local okLate, whyLate = Daily.redeem(late, "TESTEXPIRY", 5000)
			H.expect(not okLate and whyLate == "Expired", "expired at Expires")
			H.expect(late.TESTEXPIRY == nil, "not saved")
			local usedLate, whyUsed = Daily.redeem(early, "TESTEXPIRY", 9000)
			H.expect(not usedLate and whyUsed == "Used", "used before it expired says Used")
		end)
	end,

	["ROOFTOP works all of 2026-12-31 UTC and stops at 2027-01-01 00:00 UTC"] = function()
		-- 2027-01-01 00:00:00 UTC as a unix time: midnight, 20819 days after 1970-01-01.
		local newYear = 1798761600
		H.expect(newYear == 20819 * SECONDS_PER_DAY, "midnight UTC")
		local lastMinute = newYear - 60 -- 2026-12-31 23:59 UTC
		local ok, reward = Daily.redeem({}, "rooftop", lastMinute)
		H.expect(ok and describe(reward) == "Uncommon x1", "works at 23:59 on Dec 31")
		H.expect((Daily.redeem({}, "ROOFTOP", newYear - 1)), "works at 23:59:59")
		H.expect((Daily.redeem({}, "ROOFTOP", newYear - SECONDS_PER_DAY)), "works at 00:00 Dec 31")
		local late, why = Daily.redeem({}, "ROOFTOP", newYear)
		H.expect(not late and why == "Expired", "expired at 00:00 on Jan 1")
	end,

	["every Config code gives only money, lucky blocks and spins"] = function()
		local known = {}
		for _, kind in Config.LuckyBlocks.Order do
			known[kind] = true
		end
		local names = {}
		for code in Config.Daily.Codes do
			table.insert(names, code)
		end
		table.sort(names)
		H.expect(#names > 0, "some codes")
		for _, code in names do
			local row = Config.Daily.Codes[code]
			H.expect(
				Daily.normalizeCode(code) == code,
				code .. " is written as players' text normalizes"
			)
			for field, value in row do
				H.expect(
					field == "Money"
						or field == "Blocks"
						or field == "Spins"
						or field == "LuckySpins"
						or field == "Expires"
						or field == "Live",
					("%s has %s: codes give only money, blocks and spins"):format(code, field)
				)
				if field == "Money" or field == "Spins" or field == "LuckySpins" then
					H.expect(
						value > 0 and value == math.floor(value),
						("%s %s is whole"):format(code, field)
					)
				elseif field == "Blocks" then
					for kind, count in value do
						H.expect(
							known[kind] == true,
							("%s names the unknown block %s"):format(code, kind)
						)
						H.expect(
							count > 0 and count == math.floor(count),
							code .. " block count is whole"
						)
					end
				end
			end
			local live = if row.Live then { [code] = true } else nil
			local ok, reward = Daily.redeem({}, code:lower(), (row.Expires or 1e12) - 1, live)
			H.expect(ok, code .. " redeems before it expires")
			for field, value in reward :: any do
				H.expect(
					field == "money"
						or field == "blocks"
						or field == "spins"
						or field == "lucky"
						or (field == "cues" and #value == 0),
					code .. " reward has only money, blocks and spins"
				)
			end
			local gives = describe(reward) ~= "nothing" or (reward :: any).lucky > 0
			H.expect(gives, code .. " gives something")
		end
	end,

	["the like codes: off until switched on, the plan's six steps"] = function()
		local expect = {
			LIKES1K = "$10000 Mystery x1",
			LIKES5K = "$25000 Mystery x2",
			LIKES10K = "Rare x1 Spins x3",
			LIKES25K = "Rare x2",
			LIKES50K = "$100000 Rare x2",
			LIKES100K = "Rare x3 Spins x5",
		}
		for code, words in expect do
			H.expect(Daily.isLive(code), code .. " is Live")
			local off, why = Daily.redeem({}, code, NOW)
			H.expect(not off and why == "Unknown", code .. " off: unknown")
			local saved = {}
			local okOn, reward = Daily.redeem(saved, code, NOW, { [code] = true })
			H.expect(okOn and describe(reward) == words, code .. " gives " .. describe(reward))
			H.expect(saved[code] == true, "saved once redeemed")
		end
		H.expect(not Daily.isLive("WELCOME") and not Daily.isLive("NOPE"), "only Live rows")
		-- The stored set: only Live codes, switched on and off; anything else writes nothing.
		local on = Daily.setLive(nil, "LIKES1K", true)
		H.expect(on ~= nil and on.LIKES1K == true, "on")
		local both = Daily.setLive(on, "LIKES5K", true)
		H.expect(both ~= nil and both.LIKES1K and both.LIKES5K, "two on")
		local off = Daily.setLive(both, "LIKES1K", false)
		H.expect(off ~= nil and off.LIKES1K == nil and off.LIKES5K, "one off")
		H.expect(on.LIKES5K == nil, "the stored value is never changed")
		H.expect(Daily.setLive(nil, "WELCOME", true) == nil, "not a Live code")
		local read = Daily.readLive({ LIKES1K = true, WELCOME = true, LIKES5K = "yes", [3] = true })
		H.expect(read.LIKES1K and read.WELCOME == nil and read.LIKES5K == nil, "junk dropped")
		H.expect(next(Daily.readLive("x")) == nil, "not a table")
	end,

	["reward blocks are listed in Config.LuckyBlocks.Order"] = function()
		local list = Daily.blockList({
			money = 0,
			blocks = { Legendary = 1, Standard = 3, Mystery = 2, Epic = 0 },
			spins = 0,
			lucky = 0,
		})
		H.expect(#list == 3, "three (a zero count is left out)")
		H.expect(
			list[1].kind == "Standard" and list[2].kind == "Legendary" and list[3].kind == "Mystery",
			"Config order"
		)
		H.expect(list[1].count == 3, "count kept")
	end,

	["Claim All: a new player's whole first week at once, at the 399 R$ step"] = function()
		local extra = { joinDay = TODAY, played = false } -- no match needed: it is bought
		local offer = Daily.claimAllOffer(fresh(), TODAY, nil, extra)
		H.expect(offer.available and offer.firstWeek, "the first week's row")
		H.expect(offer.from == 1 and offer.days == 7, "days 1 to 7")
		H.expect(offer.product == "ClaimAllFirst7", tostring(offer.product))
		local r = offer.reward
		H.expect(r.money == 30000 and r.spins == 2, describe(r))
		H.expect(
			r.blocks.Mystery == 5
				and r.blocks.Epic == nil
				and r.blocks.Rare == 1
				and r.blocks.Legendary == nil
				and r.cues
				and #r.cues == 1
				and r.cues[1] == "WeekOneCue",
			describe(r)
		)
		local days, login, reward = Daily.claimAll(fresh(), TODAY, nil, extra)
		H.expect(days == 7 and describe(reward) == describe(r), "the offer's reward")
		H.expect(login.LastDay == TODAY and login.Total == 1, "today counts as one real day")
		H.expect(login.FirstWeek == 7 and login.StreakDay == 0, "the first week is done")
		local same = Daily.loginState(login, TODAY, nil, extra)
		H.expect(same.claimedToday and not same.canClaim, "today is claimed")
		H.expect(not Daily.claimAllOffer(login, TODAY, nil, extra).available, "nothing left")
		local played = { joinDay = TODAY, played = true }
		local tomorrow = Daily.loginState(login, TODAY + 1, nil, played)
		H.expect(not tomorrow.firstWeek and tomorrow.day == 1, "tomorrow: a later week's day 1")
		H.expect(tomorrow.total == 2 and tomorrow.canClaim, "the track counts real days")
	end,

	["Claim All: the price steps follow the days left; today's claim starts it tomorrow"] = function()
		local played = { joinDay = TODAY, played = true }
		local login = fresh()
		for day = 0, 1 do
			local ok
			ok, login = Daily.claimLogin(login, TODAY + day, nil, played)
			H.expect(ok, "claim " .. day)
		end
		-- Days 1 and 2 claimed, today's (day 2) included: days 3 to 7 are ahead.
		local offer = Daily.claimAllOffer(login, TODAY + 1, nil, played)
		H.expect(
			offer.from == 3 and offer.days == 5,
			("from %d, %d days"):format(offer.from, offer.days)
		)
		H.expect(offer.product == "ClaimAllFirst5", tostring(offer.product))
		local days, after = Daily.claimAll(login, TODAY + 1, nil, played)
		H.expect(days == 5 and after.FirstWeek == 7, "the rest of the week")
		H.expect(after.LastDay == TODAY + 1 and after.Total == 2, "no extra real day")
		-- Five first-week days claimed: days 6 and 7 are ahead, the 299 R$ step.
		local five =
			{ LastDay = TODAY + 4, StreakDay = 0, Total = 5, FreezeWeek = 0, FirstWeek = 5 }
		local late = Daily.claimAllOffer(five, TODAY + 4, nil, played)
		H.expect(late.days == 2 and late.product == "ClaimAllFirst2", tostring(late.product))
		H.expect(
			late.reward.blocks.Legendary == nil
				and late.reward.blocks.Mystery == 2
				and late.reward.cues
				and late.reward.cues[1] == "WeekOneCue",
			describe(late.reward)
		)
		-- Day 7 claimed today: nothing is left of the row.
		local done =
			{ LastDay = TODAY + 6, StreakDay = 0, Total = 7, FreezeWeek = 0, FirstWeek = 7 }
		local none = Daily.claimAllOffer(done, TODAY + 6, nil, played)
		H.expect(not none.available and none.days == 0 and none.product == nil, "none left")
		local zero, same, nothing = Daily.claimAll(done, TODAY + 6, nil, played)
		H.expect(zero == 0 and describe(nothing) == "nothing", "claims nothing")
		H.expect(same.FirstWeek == 7 and same.LastDay == TODAY + 6, "unchanged")
	end,

	["Claim All in a later week: VIP's part and the track prize only on today's day"] = function()
		-- The first week done yesterday: today is a later week's day 1 and the 8th real day,
		-- the track's $50,000.
		local login =
			{ LastDay = TODAY - 1, StreakDay = 0, Total = 7, FreezeWeek = 0, FirstWeek = 7 }
		local extra = { joinDay = TODAY - 10, played = true }
		local offer = Daily.claimAllOffer(login, TODAY, true, extra)
		H.expect(not offer.firstWeek and offer.days == 7, "a later week, 7 days")
		H.expect(offer.product == "ClaimAllWeek7", tostring(offer.product))
		local r = offer.reward
		-- The week: $30,000, 3 Mystery, a Rare and 2 spins; today adds VIP's Uncommon and spin
		-- and the track's $50,000 (once, not once a day).
		H.expect(r.money == 80000 and r.spins == 3, describe(r))
		H.expect(
			r.blocks.Uncommon == 1 and r.blocks.Rare == 1 and r.blocks.Mystery == 3,
			describe(r)
		)
		H.expect(r.blocks.Epic == nil, describe(r))
		local _, after = Daily.claimAll(login, TODAY, true, extra)
		H.expect(after.StreakDay == 7 and after.Total == 8 and after.LastDay == TODAY, "")
		local tomorrow = Daily.loginState(after, TODAY + 1, nil, extra)
		H.expect(tomorrow.day == 1 and tomorrow.total == 9, "a new loop tomorrow")
		-- 3 to 5 days ahead: the 99 R$ step; 1 or 2: the 59 R$ one.
		local mid = { LastDay = TODAY, StreakDay = 3, Total = 10, FreezeWeek = 0, FirstWeek = 7 }
		H.expect(Daily.claimAllOffer(mid, TODAY, nil, extra).product == "ClaimAllWeek5", "")
		local end6 = { LastDay = TODAY, StreakDay = 6, Total = 10, FreezeWeek = 0, FirstWeek = 7 }
		H.expect(Daily.claimAllOffer(end6, TODAY, nil, extra).product == "ClaimAllWeek2", "")
	end,

	["Claim All: a receipt pays at most its product's days; the freeze still counts"] = function()
		-- The 16th real day (no track prize).
		local login =
			{ LastDay = TODAY - 1, StreakDay = 7, Total = 15, FreezeWeek = 0, FirstWeek = 7 }
		local extra = { joinDay = TODAY - 30, played = true }
		local days, after, reward = Daily.claimAll(login, TODAY, nil, extra, 2)
		H.expect(days == 2 and after.StreakDay == 2, "days 1 and 2 only")
		H.expect(reward.money == 5000 and reward.blocks.Mystery == 1, describe(reward))
		H.expect(Daily.loginState(after, TODAY + 1, nil, extra).day == 3, "day 3 tomorrow")
		-- One missed day, this week's freeze unused: today's day goes on the streak, freezing it.
		local missed =
			{ LastDay = TODAY - 2, StreakDay = 3, Total = 20, FreezeWeek = 0, FirstWeek = 7 }
		local n, frozen = Daily.claimAll(missed, TODAY, nil, extra)
		H.expect(n == 4 and frozen.StreakDay == 7, "days 4 to 7")
		H.expect(frozen.FreezeWeek == Daily.weekOf(TODAY), "the freeze is used")
		-- It never changes the table it is given.
		H.expect(missed.StreakDay == 3 and missed.LastDay == TODAY - 2, "unchanged input")
	end,

	["Claim All's products: one per step, paid random items, priced as the plan"] = function()
		local list = Config.Products.List :: any
		local want = {
			ClaimAllFirst7 = { 399, 7 },
			ClaimAllFirst5 = { 349, 5 },
			ClaimAllFirst2 = { 299, 2 },
			ClaimAllWeek7 = { 79, 7 },
			ClaimAllWeek5 = { 69, 5 },
			ClaimAllWeek2 = { 35, 2 },
		}
		for key, pair in want do
			local row = list[key]
			H.expect(row ~= nil and row.Kind == "Product" and row.Random == true, key)
			H.expect(row.Robux == pair[1] and row.ClaimAll == pair[2], key)
		end
		for _, kind in { "First", "Week" } do
			local steps = (Config.Daily.ClaimAll :: any)[kind]
			for i, step in steps do
				H.expect(want[step.Product] ~= nil, step.Product)
				H.expect(
					want[step.Product][2] >= (if i == 1 then 7 else steps[i - 1].MinDays - 1),
					""
				)
				if i > 1 then
					H.expect(step.MinDays < steps[i - 1].MinDays, "steps go down")
				end
			end
			H.expect(steps[#steps].MinDays == 1, "one day left still has a step")
		end
	end,

	["RewardView: a new player's first day"] = function()
		-- A match finished today (the login claim waits for one: Config.Daily.NeedsMatch).
		local daily = { Day = TODAY, Matches = 1, PlaySeconds = 0, PlaytimeClaimed = {} }
		local p = RewardView.build(fresh(), daily, {}, NOW)
		H.expect(p.today == TODAY and p.sentAt == NOW, "today")
		H.expect(p.resetsAt == (TODAY + 1) * SECONDS_PER_DAY + RESET, "resets at 08:00 UTC")
		H.expect(p.weeks == Config.Daily.WeeksForBonus, "weeks in the cycle")
		H.expect(p.login.canClaim and not p.login.claimedToday, "today's claim waits")
		H.expect(p.login.day == 1 and p.login.week == 1 and not p.login.bonus, "day 1, week 1")
		H.expect(p.login.reward.money == 5000 and #p.login.reward.blocks == 0, "$5,000")
		H.expect(p.login.total == 1 and p.login.freezeReady and not p.login.frozen, "the track")
		H.expect(#p.days == 7, "seven tiles")
		H.expect(p.days[1].today and not p.days[1].claimed, "day 1 glows")
		H.expect(not p.days[2].today and not p.days[2].claimed, "day 2 later")
		local day2 = p.days[2].reward.blocks
		H.expect(#day2 == 1 and day2[1].kind == "Mystery" and day2[1].count == 1, "1 Mystery")
		H.expect(p.trackDays == 28 and p.trackPlace == 0 and #p.track == 4, "the 28-day track")
		H.expect(p.track[1].day == 8 and not p.track[1].reached, "day 8 to come")
		H.expect(p.wins.given == 0 and #p.wins.kinds == 10, "the win track's bar")
		-- The win track's tiles: money between the blocks; the first win's Rare while it is due.
		local due = RewardView.wins({ Track = 0 }, {})
		H.expect(due.kinds[1] == "Rare" and due.kinds[2] == "Money", "the first win's Rare")
		local given = RewardView.wins({ Track = 0 }, { [RewardView.FirstWinFlag] = true })
		H.expect(given.kinds[1] == "Uncommon" and given.kinds[10] == "Epic", "the day's steps")
		local later = RewardView.wins({ Track = 3 }, {})
		H.expect(later.given == 3 and later.kinds[4] == "Rare", "still due at step 4")
		-- With a join day, a new player's tiles are the first week's.
		local unplayed = { Day = TODAY, PlaySeconds = 0, PlaytimeClaimed = {} }
		local new = RewardView.build(fresh(), unplayed, {}, NOW, false, nil, false, nil, {
			joinDay = TODAY,
		})
		H.expect(new.login.firstWeek and new.login.firstWeekLeft == 14, "the first week")
		H.expect(new.login.needsMatch and not new.login.canClaim, "waits for a match")
		H.expect(new.days[2].reward.blocks[1].kind == "Rare", "day 2's Rare block")
		H.expect(
			#new.days[7].reward.blocks == 0 and new.days[7].reward.cues[1] == "WeekOneCue",
			"day 7's Week One Cue"
		)
		local played = { Day = TODAY, Matches = 1, Track = 3, PlaySeconds = 0 }
		local after = RewardView.build(fresh(), played, {}, NOW, false, nil, false, nil, {
			joinDay = TODAY,
		})
		H.expect(after.login.canClaim and after.wins.given == 3, "a match played, 3 track wins")
		H.expect(p.track[4].reward.blocks[1].kind == "Epic", "day 28's Epic block")
		H.expect((p :: any).next == nil, "no reminder of tomorrow (the popups are gone)")
		H.expect(p.ready and p.playSeconds == 0 and #p.titles == 0, "ready, nothing played")
	end,

	["RewardView: Claim All's offer, hidden where paid random items are restricted"] = function()
		local daily = { Day = TODAY, Matches = 0, PlaySeconds = 0, PlaytimeClaimed = {} }
		local extra = { joinDay = TODAY, restricted = false }
		local p = RewardView.build(fresh(), daily, {}, NOW, false, nil, false, nil, extra)
		local c = p.claimAll
		H.expect(c.available and c.product == "ClaimAllFirst7" and c.robux == 399, "399 R$")
		H.expect(c.from == 1 and c.days == 7, "the whole first week")
		H.expect(
			c.reward.cues[1] == "WeekOneCue" and c.reward.money == 30000,
			"day 7's Week One Cue in it"
		)
		local shut = RewardView.build(fresh(), daily, {}, NOW, false, nil, false, nil, {
			joinDay = TODAY,
			restricted = true,
		})
		H.expect(not shut.claimAll.available and shut.claimAll.product ~= nil, "hidden")
	end,

	["RewardView: the favorite card (GUI lane, D4)"] = function()
		local p = RewardView.build(fresh(), nil, nil, NOW)
		H.expect(not p.favorite.claimed, "not yet")
		H.expect(p.favorite.reward.money == Config.Social.FavoriteReward.Money, "the money")
		H.expect(
			p.favorite.reward.blocks[1].kind == "Lucky8"
				and p.favorite.reward.blocks[1].count
					== Config.Social.FavoriteReward.Blocks.Lucky8,
			"the Lucky 8 block (designer, 2026-10-08)"
		)
		local flags = { [RewardView.FavoriteFlag] = true }
		local after = RewardView.build(fresh(), nil, nil, NOW, false, nil, false, flags)
		H.expect(after.favorite.claimed, "claimed")
	end,

	["RewardView: the invite card says whether the inviter's own block was given"] = function()
		local p = RewardView.build(fresh(), nil, nil, NOW)
		H.expect(p.invite.rewarded == false, "not given yet")
		local flags = { [RewardView.InviterFlag] = true }
		local after = RewardView.build(fresh(), nil, nil, NOW, false, nil, false, flags)
		H.expect(after.invite.rewarded == true, "given (once ever: Config.Social.InviterOnce)")
	end,

	["RewardView: after the claim, tomorrow's reward is next"] = function()
		local ok, login = Daily.claimLogin(fresh(), TODAY)
		H.expect(ok, "claimed")
		local p = RewardView.build(login, nil, nil, NOW)
		H.expect(not p.login.canClaim and p.login.claimedToday, "claimed today")
		H.expect(
			p.days[1].claimed and p.days[1].today and not p.days[2].claimed,
			"a check on day 1"
		)
		H.expect(p.trackPlace == 1, "one day on the track")
		H.expect(not p.ready, "nothing to claim")
		local played = { Matches = 1 }
		local tomorrow = RewardView.build(login, played, nil, NOW + SECONDS_PER_DAY)
		H.expect(tomorrow.today == TODAY + 1 and tomorrow.login.canClaim, "a new day")
		H.expect(tomorrow.login.day == 2 and tomorrow.days[2].today, "day 2 glows")
		H.expect(tomorrow.days[1].claimed and not tomorrow.days[2].claimed, "day 1 stays checked")
		local frozen = RewardView.build(login, played, nil, NOW + 2 * SECONDS_PER_DAY)
		H.expect(frozen.login.day == 2 and frozen.login.frozen, "one missed day: the freeze")
		local missed = RewardView.build(login, played, nil, NOW + 3 * SECONDS_PER_DAY)
		H.expect(missed.login.day == 1 and not missed.days[1].claimed, "two missed: day 1 again")
	end,

	["RewardView: day 28 carries the track's Epic block; VIP's spin on every tile"] = function()
		-- (VIP's daily Uncommon block is on every tile too.)
		local weeks = Config.Daily.WeeksForBonus
		local login = Daily.setStreakDay(fresh(), TODAY, 7, weeks)
		local p = RewardView.build(login, nil, nil, NOW, true)
		H.expect(p.login.day == 7 and p.login.week == weeks and p.login.bonus, "day 28")
		local blocks = p.login.reward.blocks
		H.expect(
			#blocks == 3
				and blocks[1].kind == "Uncommon"
				and blocks[2].kind == "Rare"
				and blocks[2].count == 1
				and blocks[3].kind == "Epic",
			"VIP's Uncommon block, day 7's Rare and the track's Epic block, in Config order"
		)
		H.expect(p.login.reward.spins == 3, "2 + VIP's 1")
		H.expect(p.days[1].reward.spins == 1 and p.days[7].reward.spins == 3, "VIP tiles")
		H.expect(p.trackPlace == 27, "27 days on the track")
		H.expect(p.track[3].reached and not p.track[4].reached, "day 28 is today's")
		for day = 1, 6 do
			H.expect(p.days[day].claimed, ("day %d checked"):format(day))
		end
	end,

	["RewardView: playtime gifts, progress and the ready key"] = function()
		local daily: any = { Day = TODAY, PlaySeconds = 11 * 60, PlaytimeClaimed = {} }
		local p = RewardView.build(fresh(), daily, nil, NOW)
		H.expect(#p.playtime == #Config.Daily.Playtime, "every gift")
		H.expect(p.playSeconds == 660, "seconds played today")
		local first, second = p.playtime[1], p.playtime[2]
		H.expect(
			first.index == 1 and first.minutes == 5 and first.ready and first.progress == 1,
			"5 min ready"
		)
		H.expect(first.reward.money == 1000, "$1,000")
		H.expect(not second.ready and math.abs(second.progress - 11 / 15) < 1e-9, "15 min at 11/15")
		H.expect(second.reward.blocks[1].kind == "Mystery", "a Mystery block")
		H.expect(RewardView.readyKey(daily) == "10000-0", "the first gift ready")
		daily.PlaytimeClaimed["1"] = true
		H.expect(RewardView.readyKey(daily) == "00000-0", "claimed: none ready")
		daily.Matches = 1
		daily.Track = 2
		H.expect(RewardView.readyKey(daily) == "00000m2", "a match and two track wins")
		daily.Matches, daily.Track = nil, nil
		local _, claimedLogin = Daily.claimLogin(fresh(), TODAY)
		local after = RewardView.build(claimedLogin, daily, nil, NOW)
		H.expect(after.playtime[1].claimed and not after.playtime[1].ready, "claimed")
		H.expect(not after.ready, "nothing left to claim")
		H.expect(RewardView.readyKey(nil) == "00000-0", "no Daily yet")
		H.expect(RewardView.build(fresh(), nil, nil, NOW).playSeconds == 0, "nothing played")
	end,

	["RewardView: the group and invite cards"] = function()
		local p = RewardView.build(fresh(), nil, nil, NOW, false, nil, false)
		H.expect(p.group.id == Config.Social.GroupId and not p.group.member, "not a member")
		local group = p.group.reward.blocks
		H.expect(not p.group.claimed and group[1].kind == "Mystery" and group[1].count == 2, "2")
		H.expect(p.group.boost == 0.1, "+10%")
		H.expect(p.invite.perMonth == 5 and p.invite.used == 0, "five a month")
		H.expect(p.invite.reward.blocks[1].kind == "Uncommon", "an Uncommon block each")
		local _, claimed = Daily.claimLogin(fresh(), TODAY)
		local member = RewardView.build(claimed, nil, nil, NOW, false, { Group = false }, true)
		H.expect(member.group.member and member.ready, "a member can claim")
		local done = RewardView.build(claimed, nil, nil, NOW, false, { Group = true }, true)
		H.expect(done.group.claimed and not done.ready, "claimed: nothing to do")
		local Social = H.require("Progression.Social")
		local social = {
			InvitedBy = 5,
			InviteDone = true,
			InviteMonth = Social.monthOf(NOW),
			Invites = 2,
		}
		local inv = RewardView.build(claimed, nil, nil, NOW, false, social, false)
		H.expect(inv.invite.invited and inv.invite.done and inv.invite.used == 2, "invited")
		social.InviteMonth -= 1
		H.expect(
			RewardView.build(claimed, nil, nil, NOW, false, social, false).invite.used == 0,
			""
		)
	end,

	["RewardView: titles sorted, rewards as lists"] = function()
		local titles = RewardView.titles({ Rare = true, Common = true, Epic = false, [5] = true })
		H.expect(
			#titles == 2 and titles[1] == "Common" and titles[2] == "Rare",
			"sorted, true only"
		)
		H.expect(#RewardView.titles(nil) == 0, "none")
		local out = RewardView.reward({
			money = 500,
			blocks = { Rare = 1, Standard = 2, Mystery = 2 },
			spins = 0,
			lucky = 0,
		})
		H.expect(out.money == 500 and #out.blocks == 3, "money and three block kinds")
		H.expect(out.blocks[1].kind == "Standard" and out.blocks[1].count == 2, "Standard first")
		H.expect(out.blocks[2].kind == "Rare" and out.blocks[2].count == 1, "then Rare")
		H.expect(out.blocks[3].kind == "Mystery" and out.blocks[3].count == 2, "then Mystery")
		H.expect(out.spins == 0 and out.lucky == 0, "no spins")
		local bad = RewardView.reward({ money = -5, blocks = {}, spins = -1, lucky = 0 } :: any)
		H.expect(bad.money == 0 and bad.spins == 0, "never negative")
	end,
	["the Week One Cue: day 7's cue, known to the catalog, a copy each claim"] = function()
		local Catalog = H.require("Progression.Catalog")
		local Inventory = H.require("Progression.Inventory")
		local SaveSchema = H.require("Progression.SaveSchema")
		local cues = Daily.rewardCues()
		H.expect(#cues == 1 and cues[1] == "WeekOneCue", "the only cue a login gives")
		for _, id in cues do
			local cue = Catalog.get(id)
			H.expect(cue ~= nil and cue.Group ~= "Unique" and cue.Group ~= "Default", id)
		end
		local seventh = Daily.firstWeekReward(7)
		H.expect(describe(seventh) == "Cue:WeekOneCue Spins x2", describe(seventh))
		-- A player who owns one already (a trade) gets another copy: a block cue stacks.
		local save = SaveSchema.template()
		Inventory.addCue(save, "WeekOneCue", 1)
		Inventory.addCue(save, "WeekOneCue", 1)
		H.expect(Inventory.count(save, "WeekOneCue") == 2, "two copies")
	end,
}
