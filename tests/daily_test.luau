--!strict
-- Daily rewards: the login streak, playtime gifts and promo codes (Progression/Daily, numbers
-- in Config.Daily), and the RewardState payload built from them (Progression/RewardView).
-- Expected values are ECONOMY.md section 10's table, written out here.

local H = require("./harness")

local Config = H.require("Config")
local Daily = H.require("Progression.Daily")
local RewardView = H.require("Progression.RewardView")

-- A UTC day far from zero, so "yesterday" is never day 0.
local TODAY = 20724
local SECONDS_PER_DAY = 86400
-- An hour into TODAY, as a unix time.
local NOW = TODAY * SECONDS_PER_DAY + 3600

-- ECONOMY 10: the seven streak days.
local STREAK = {
	"$250",
	"Standard x2",
	"$500",
	"Rare x1",
	"$1000",
	"Rare x2",
	"Epic x1",
}

-- A reward as one short line: "$250", "Standard x2", "$500 Standard x1", "nothing".
local function describe(reward: any): string
	local words = {}
	if reward.money > 0 then
		table.insert(words, "$" .. reward.money)
	end
	for _, entry in Daily.caseList(reward) do
		table.insert(words, ("%s x%d"):format(entry.id, entry.count))
	end
	return if #words == 0 then "nothing" else table.concat(words, " ")
end

local function fresh(): any
	return { LastDay = 0, StreakDay = 0, Week = 0 }
end

-- Claims `count` days in a row from `firstDay`; returns the final login and each claim's
-- { day, week, reward, bonus }.
local function claimRun(login: any, firstDay: number, count: number): (any, { any })
	local claims = {}
	for i = 0, count - 1 do
		local today = firstDay + i
		local state = Daily.loginState(login, today)
		local ok, newLogin, reward = Daily.claimLogin(login, today)
		H.expect(ok, ("claim on day %d refused"):format(today))
		table.insert(
			claims,
			{ day = state.day, week = state.week, reward = reward, bonus = state.bonus }
		)
		login = newLogin
	end
	return login, claims
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
	["dayOf is the UTC day number"] = function()
		H.expect(Daily.dayOf(0) == 0, "epoch")
		H.expect(Daily.dayOf(86399) == 0, "last second of day 0")
		H.expect(Daily.dayOf(86400) == 1, "first second of day 1")
		H.expect(Daily.dayOf(1790553600) == 20724, "2026-09-28 00:00 UTC")
		H.expect(Daily.dayOf(1790553600 + 86399.5) == 20724, "a fraction before midnight")
	end,

	["the seven streak rewards match ECONOMY 10"] = function()
		H.expect(#Config.Daily.Streak == 7, "seven streak days")
		local _, claims = claimRun(fresh(), TODAY, 7)
		for i, claim in claims do
			H.expect(
				claim.day == i and claim.week == 1,
				("claim %d is day %d week %d"):format(i, claim.day, claim.week)
			)
			H.expect(
				describe(claim.reward) == STREAK[i],
				("day %d gives %s, expected %s"):format(i, describe(claim.reward), STREAK[i])
			)
			H.expect(not claim.bonus, ("day %d of week 1 has no bonus"):format(i))
			local tile = Daily.streakReward(i, 1)
			H.expect(describe(tile) == STREAK[i], ("tile %d shows %s"):format(i, describe(tile)))
		end
	end,

	["claiming twice in a day is refused"] = function()
		local ok, login, reward = Daily.claimLogin(fresh(), TODAY)
		H.expect(ok and reward ~= nil, "first claim")
		local state = Daily.loginState(login, TODAY)
		H.expect(state.claimedToday and not state.canClaim, "claimed today")
		H.expect(state.day == 1 and describe(state.reward) == "$250", "state still shows day 1")
		local again, same, none = Daily.claimLogin(login, TODAY)
		H.expect(not again and none == nil, "second claim refused")
		H.expect(
			same.LastDay == TODAY and same.StreakDay == 1 and same.Week == 1,
			"login unchanged"
		)
		H.expect(same ~= login, "a copy, not the same table")
	end,

	["claimLogin never changes the table it is given"] = function()
		local login = { LastDay = TODAY - 1, StreakDay = 3, Week = 2 }
		local ok, newLogin = Daily.claimLogin(login, TODAY)
		H.expect(ok, "claimed")
		H.expect(
			login.LastDay == TODAY - 1 and login.StreakDay == 3 and login.Week == 2,
			"input untouched"
		)
		H.expect(
			newLogin.LastDay == TODAY and newLogin.StreakDay == 4 and newLogin.Week == 2,
			"day 4 of week 2"
		)
	end,

	["a missed day starts again at day 1"] = function()
		local login = claimRun(fresh(), TODAY, 3)
		H.expect(login.StreakDay == 3, "three days claimed")
		-- TODAY + 3 skipped.
		local state = Daily.loginState(login, TODAY + 4)
		H.expect(state.canClaim and state.day == 1 and state.week == 1, "back to day 1")
		H.expect(describe(state.reward) == "$250", "day 1's reward")
		-- A miss deep into week 3 goes back to week 1 too.
		local long = claimRun(fresh(), TODAY, 17)
		H.expect(long.StreakDay == 3 and long.Week == 3, "day 3 of week 3")
		local after = Daily.loginState(long, TODAY + 18)
		H.expect(after.day == 1 and after.week == 1, "a missed day resets the weeks")
	end,

	["four full weeks add the Legendary Case on day 28 only"] = function()
		local login, claims = claimRun(fresh(), TODAY, 56)
		for i, claim in claims do
			local cycleDay = (i - 1) % 28 + 1
			local expectedDay = (cycleDay - 1) % 7 + 1
			local expectedWeek = (cycleDay - 1) // 7 + 1
			H.expect(
				claim.day == expectedDay and claim.week == expectedWeek,
				("claim %d is day %d of week %d"):format(i, claim.day, claim.week)
			)
			local expected = STREAK[expectedDay]
			if cycleDay == 28 then
				expected = "Epic x1 Legendary x1"
			end
			H.expect(
				describe(claim.reward) == expected,
				("claim %d gives %s, expected %s"):format(i, describe(claim.reward), expected)
			)
			H.expect(claim.bonus == (cycleDay == 28), ("claim %d bonus flag"):format(i))
		end
		H.expect(claims[7].reward.cases.Legendary == nil, "day 7 of week 1 has no Legendary")
		H.expect(claims[29].day == 1 and claims[29].week == 1, "the cycle starts over after day 28")
		H.expect(login.StreakDay == 7 and login.Week == 4, "ends on day 28 of the second cycle")
	end,

	["a claim dated tomorrow by another server's clock still counts as today"] = function()
		local skewed = { LastDay = TODAY + 1, StreakDay = 2, Week = 1 }
		local state = Daily.loginState(skewed, TODAY)
		H.expect(state.claimedToday and not state.canClaim, "no second claim")
		H.expect(state.day == 2, "the streak kept")
		H.expect(Daily.loginState(skewed, TODAY + 2).day == 3, "continues the day after")
		-- A LastDay far ahead is a broken save: start again rather than lock claims.
		local broken = { LastDay = TODAY + 30, StreakDay = 4, Week = 2 }
		local fixed = Daily.loginState(broken, TODAY)
		H.expect(fixed.canClaim and fixed.day == 1 and fixed.week == 1, "a broken save restarts")
	end,

	["bad login data never crashes and starts at day 1"] = function()
		for _, login in { {}, { LastDay = "x", StreakDay = 99, Week = -1 }, { LastDay = 0 / 0 } } do
			local state = Daily.loginState(login :: any, TODAY)
			H.expect(state.canClaim and state.day == 1 and state.week == 1, "day 1")
		end
		local noWeek = Daily.loginState({ LastDay = TODAY - 1, StreakDay = 2, Week = 0 }, TODAY)
		H.expect(noWeek.day == 3 and noWeek.week == 1, "a missing week reads as week 1")
	end,

	["setStreakDay makes the next claim that day"] = function()
		for week = 1, 4 do
			for n = 1, 7 do
				local login = Daily.setStreakDay(fresh(), TODAY, n, week)
				local state = Daily.loginState(login, TODAY)
				H.expect(state.canClaim, ("day %d week %d claimable"):format(n, week))
				H.expect(
					state.day == n and state.week == week,
					("set %d/%d gave %d/%d"):format(n, week, state.day, state.week)
				)
				local ok, _, reward = Daily.claimLogin(login, TODAY)
				H.expect(ok and reward ~= nil, "claims")
				H.expect(
					(reward :: any).cases.Legendary == (if n == 7 and week == 4 then 1 else nil),
					"Legendary only on day 28"
				)
			end
		end
		-- Already claimed today: the command still lets day n be claimed now, in the same week.
		local _, claimed = Daily.claimLogin({ LastDay = TODAY - 1, StreakDay = 2, Week = 3 }, TODAY)
		local reset = Daily.setStreakDay(claimed, TODAY, 7)
		local state = Daily.loginState(reset, TODAY)
		H.expect(state.canClaim and state.day == 7 and state.week == 3, "day 7 of the current week")
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

	["nextReward is today's while unclaimed, else tomorrow's"] = function()
		local first = Daily.nextReward(fresh(), TODAY)
		H.expect(
			not first.tomorrow and first.day == 1 and describe(first.reward) == "$250",
			"today's day 1"
		)
		local login = claimRun(fresh(), TODAY, 3)
		local next = Daily.nextReward(login, TODAY + 2)
		H.expect(next.tomorrow and next.day == 4, "tomorrow is day 4")
		H.expect(describe(next.reward) == "Rare x1", "Come back tomorrow for your Rare Case")
		-- The day before day 28 promises the bonus.
		local week4 = claimRun(fresh(), TODAY, 27)
		local big = Daily.nextReward(week4, TODAY + 26)
		H.expect(big.tomorrow and big.bonus and big.day == 7 and big.week == 4, "day 28 tomorrow")
		H.expect(describe(big.reward) == "Epic x1 Legendary x1", "Epic and Legendary")
		-- After day 28 the next is day 1 again.
		local done = claimRun(fresh(), TODAY, 28)
		local over = Daily.nextReward(done, TODAY + 27)
		H.expect(over.tomorrow and over.day == 1 and over.week == 1, "cycle over")
		-- A missed day: today's day 1.
		local missed = Daily.nextReward(login, TODAY + 5)
		H.expect(not missed.tomorrow and missed.day == 1, "missed: day 1 today")
	end,

	["playtime gifts at 10, 30 and 60 minutes"] = function()
		local expected = { { 10, "$100" }, { 30, "Standard x1" }, { 60, "Standard x2" } }
		local daily = { PlaySeconds = 0, PlaytimeClaimed = {} }
		local gifts = Daily.playtimeState(daily)
		H.expect(#gifts == 3, "three gifts")
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
		H.expect(readyAt(599) == "---", "599 s")
		H.expect(readyAt(600) == "R--", "10 minutes")
		H.expect(readyAt(1799) == "R--", "1799 s")
		H.expect(readyAt(1800) == "RR-", "30 minutes")
		H.expect(readyAt(3599) == "RR-", "3599 s")
		H.expect(readyAt(3600) == "RRR", "60 minutes")
		daily.PlaySeconds = 300
		local half = Daily.playtimeState(daily)
		H.near(half[1].progress, 0.5, 1e-9, "5 of 10 minutes")
		H.near(half[2].progress, 300 / 1800, 1e-9, "5 of 30 minutes")
		daily.PlaySeconds = 99999
		H.expect(Daily.playtimeState(daily)[3].progress == 1, "progress stops at 1")
	end,

	["each playtime gift claims once"] = function()
		local daily: any = { PlaySeconds = 900, PlaytimeClaimed = {} }
		local ok, why = Daily.claimPlaytime(daily, 2)
		H.expect(not ok and why == "NotReady", "30-minute gift not ready at 15 minutes")
		local got, reward = Daily.claimPlaytime(daily, 1)
		H.expect(got and describe(reward) == "$100", "10-minute gift")
		H.expect(daily.PlaytimeClaimed["1"] == true, "marked with a string key")
		local again, reason = Daily.claimPlaytime(daily, 1)
		H.expect(not again and reason == "Claimed", "only once")
		local state = Daily.playtimeState(daily)
		H.expect(state[1].claimed and not state[1].ready, "shown as claimed")
		daily.PlaySeconds = 3600
		H.expect((Daily.claimPlaytime(daily, 3)), "60-minute gift")
		H.expect((Daily.claimPlaytime(daily, 2)), "30-minute gift, out of order")
		for _, bad in { 0, 4, 1.5, "1", 0 / 0, math.huge } do
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
		H.expect(ok and describe(reward) == "$500 Standard x1", "WELCOME: $500 and a Standard Case")
		H.expect(codes.WELCOME == true, "saved upper-case")
		local again, why = Daily.redeem(codes, " WELCOME ", TODAY * 86400)
		H.expect(not again and why == "Used", "once per player")
		local ok8, reward8 = Daily.redeem(codes, "8Ball", TODAY * 86400)
		H.expect(ok8 and describe(reward8) == "$250", "8BALL: $250")
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

	["every Config code gives only money and cases"] = function()
		local known = {}
		for _, caseId in Config.Cases.Order do
			known[caseId] = true
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
					field == "Money" or field == "Cases" or field == "Expires",
					("%s has %s: codes give only money and cases"):format(code, field)
				)
				if field == "Money" then
					H.expect(value > 0 and value == math.floor(value), code .. " money is whole")
				elseif field == "Cases" then
					for caseId, count in value do
						H.expect(
							known[caseId] == true,
							("%s names the unknown case %s"):format(code, caseId)
						)
						H.expect(
							count > 0 and count == math.floor(count),
							code .. " case count is whole"
						)
					end
				end
			end
			local ok, reward = Daily.redeem({}, code:lower(), (row.Expires or 1e12) - 1)
			H.expect(ok, code .. " redeems before it expires")
			for field in reward :: any do
				H.expect(
					field == "money" or field == "cases",
					code .. " reward has only money and cases"
				)
			end
			H.expect(describe(reward) ~= "nothing", code .. " gives something")
		end
	end,

	["reward cases are listed in the case ladder's order"] = function()
		local list =
			Daily.caseList({ money = 0, cases = { Legendary = 1, Standard = 3, Epic = 2 } })
		H.expect(#list == 3, "three")
		H.expect(
			list[1].id == "Standard" and list[2].id == "Epic" and list[3].id == "Legendary",
			"ladder order"
		)
		H.expect(list[1].count == 3, "count kept")
	end,

	["RewardView: a new player's first day"] = function()
		local daily = { Day = TODAY, PlaySeconds = 0, PlaytimeClaimed = {} }
		local p = RewardView.build(fresh(), daily, {}, NOW)
		H.expect(p.today == TODAY and p.sentAt == NOW, "today")
		H.expect(p.resetsAt == (TODAY + 1) * SECONDS_PER_DAY, "resets at the next UTC midnight")
		H.expect(p.weeks == Config.Daily.WeeksForBonus, "weeks in the cycle")
		H.expect(p.login.canClaim and not p.login.claimedToday, "today's claim waits")
		H.expect(p.login.day == 1 and p.login.week == 1 and not p.login.bonus, "day 1, week 1")
		H.expect(p.login.reward.money == 250 and #p.login.reward.cases == 0, "$250")
		H.expect(#p.days == 7, "seven tiles")
		H.expect(p.days[1].today and not p.days[1].claimed, "day 1 glows")
		H.expect(not p.days[2].today and not p.days[2].claimed, "day 2 later")
		local day2 = p.days[2].reward.cases
		H.expect(#day2 == 1 and day2[1].id == "Standard" and day2[1].count == 2, "2 Standard Cases")
		H.expect(not p.next.tomorrow and p.next.day == 1, "the next claim is today's")
		H.expect(p.ready and p.playSeconds == 0 and #p.titles == 0, "ready, nothing played")
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
		H.expect(p.next.tomorrow and p.next.day == 2, "tomorrow is day 2")
		H.expect(
			p.next.reward.cases[1].id == "Standard",
			"tomorrow's 2 Standard Cases (the reminder)"
		)
		H.expect(not p.ready, "nothing to claim")
		local tomorrow = RewardView.build(login, nil, nil, NOW + SECONDS_PER_DAY)
		H.expect(tomorrow.today == TODAY + 1 and tomorrow.login.canClaim, "a new day")
		H.expect(tomorrow.login.day == 2 and tomorrow.days[2].today, "day 2 glows")
		H.expect(tomorrow.days[1].claimed and not tomorrow.days[2].claimed, "day 1 stays checked")
		local missed = RewardView.build(login, nil, nil, NOW + 2 * SECONDS_PER_DAY)
		H.expect(missed.login.day == 1 and not missed.days[1].claimed, "a missed day: day 1 again")
	end,

	["RewardView: week 4's day 7 carries the Legendary Case"] = function()
		local weeks = Config.Daily.WeeksForBonus
		local login = Daily.setStreakDay(fresh(), TODAY, 7, weeks)
		local p = RewardView.build(login, nil, nil, NOW)
		H.expect(p.login.day == 7 and p.login.week == weeks and p.login.bonus, "day 28")
		H.expect(p.days[7].bonus and not p.days[6].bonus, "the bonus tile")
		local cases = p.days[7].reward.cases
		H.expect(
			#cases == 2 and cases[1].id == "Epic" and cases[2].id == "Legendary",
			"the Epic Case and the Legendary Case, in ladder order"
		)
		for day = 1, 6 do
			H.expect(p.days[day].claimed, ("day %d of the last week checked"):format(day))
		end
		local week1 = RewardView.build(Daily.setStreakDay(fresh(), TODAY, 7, 1), nil, nil, NOW)
		H.expect(not week1.days[7].bonus and #week1.days[7].reward.cases == 1, "no bonus in week 1")
	end,

	["RewardView: playtime gifts, progress and the ready key"] = function()
		local daily = { Day = TODAY, PlaySeconds = 11 * 60, PlaytimeClaimed = {} }
		local p = RewardView.build(fresh(), daily, nil, NOW)
		H.expect(#p.playtime == #Config.Daily.Playtime, "every gift")
		H.expect(p.playSeconds == 660, "seconds played today")
		local first, second = p.playtime[1], p.playtime[2]
		H.expect(
			first.index == 1 and first.minutes == 10 and first.ready and first.progress == 1,
			"10 min ready"
		)
		H.expect(first.reward.money == 100, "$100")
		H.expect(not second.ready and math.abs(second.progress - 11 / 30) < 1e-9, "30 min at 11/30")
		H.expect(second.reward.cases[1].id == "Standard", "a Standard Case")
		H.expect(RewardView.readyKey(daily) == "100", "the first gift ready")
		daily.PlaytimeClaimed["1"] = true
		H.expect(RewardView.readyKey(daily) == "000", "claimed: none ready")
		local _, claimedLogin = Daily.claimLogin(fresh(), TODAY)
		local after = RewardView.build(claimedLogin, daily, nil, NOW)
		H.expect(after.playtime[1].claimed and not after.playtime[1].ready, "claimed")
		H.expect(not after.ready, "nothing left to claim")
		H.expect(RewardView.readyKey(nil) == "000", "no Daily yet")
		H.expect(RewardView.build(fresh(), nil, nil, NOW).playSeconds == 0, "nothing played")
	end,

	["RewardView: titles sorted, rewards as lists"] = function()
		local titles = RewardView.titles({ Rare = true, Common = true, Epic = false, [5] = true })
		H.expect(
			#titles == 2 and titles[1] == "Common" and titles[2] == "Rare",
			"sorted, true only"
		)
		H.expect(#RewardView.titles(nil) == 0, "none")
		local out = RewardView.reward({ money = 500, cases = { Rare = 1, Standard = 2 } })
		H.expect(out.money == 500 and #out.cases == 2, "money and two case types")
		H.expect(out.cases[1].id == "Standard" and out.cases[1].count == 2, "Standard first")
		H.expect(out.cases[2].id == "Rare" and out.cases[2].count == 1, "then Rare")
		H.expect(RewardView.reward({ money = -5, cases = {} }).money == 0, "never negative")
	end,
}
