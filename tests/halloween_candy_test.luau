--!strict
-- Halloween Candy (Halloween/CandyMath and Halloween/Ledger; Config.Halloween): a match's Candy,
-- the friends and group parts through Money and through the fallback, the King's paid wins and
-- cooldown, the pickup cap, the Spider and the end's conversion.

local H = require("./harness")

local START = 1793228400
local END = 1793750400

local function load()
	return H.require("Halloween.CandyMath"),
		H.require("Halloween.Ledger"),
		H.require("Config"),
		H.require("Progression.SaveSchema")
end

-- Runs `fn` with Config.Economy's friend keys set, then puts them back.
local function withFriends(enabled: boolean, fn: () -> ())
	local E: any = H.require("Config").Economy
	local saved = { E.FriendBoostEnabled, E.FriendBoost, E.FriendBoostMaxFriends }
	E.FriendBoostEnabled = enabled
	E.FriendBoost = 0.1
	E.FriendBoostMaxFriends = 4
	local ok, err = pcall(fn)
	E.FriendBoostEnabled, E.FriendBoost, E.FriendBoostMaxFriends = saved[1], saved[2], saved[3]
	if not ok then
		error(err, 0)
	end
end

-- Runs `fn` with Money's friend functions removed (before the GUI lane's merge), then back.
local function withoutMoneyFriends(fn: () -> ())
	local Money: any = H.require("Progression.Money")
	local fb, bp = Money.friendBoost, Money.boostParts
	Money.friendBoost, Money.boostParts = nil, nil
	local ok, err = pcall(fn)
	Money.friendBoost, Money.boostParts = fb, bp
	if not ok then
		error(err, 0)
	end
end

return {
	["the plan's numbers"] = function()
		local _, _, Config = load()
		local C = Config.Halloween
		H.expect(C.Match.PerBall == 3 and C.Match.Finished == 10 and C.Match.Win == 25, "match")
		H.expect(C.Boss.Candy == 50 and C.Boss.PaidWinsPerDay == 2, "King")
		H.expect(C.Boss.CooldownSeconds == 900, "15:00")
		H.expect(C.Pickup.Candy == 1 and C.Pickup.HourCap == 40, "pickups")
		H.expect(C.Spider.Seconds == 10860 and C.Convert.MoneyPerCandy == 10, "Spider, $10")
	end,

	["a match's base Candy: 3 a ball, 10 finished, 25 a win"] = function()
		local CandyMath = load()
		H.expect(CandyMath.base({ balls = 6, finished = 1, won = 1 }) == 18 + 10 + 25, "a win")
		H.expect(CandyMath.base({ balls = 4, finished = 1, won = 0 }) == 12 + 10, "a loss")
		H.expect(CandyMath.base({ balls = 3, finished = 1, won = 0 }) == 19, "a draw: 10")
		-- The side that forfeited a real match keeps its balls, nothing else.
		H.expect(CandyMath.base({ balls = 2, finished = 0, won = 0 }) == 6, "forfeited")
		-- The winner of a real forfeit gets the 10 and the 25.
		H.expect(CandyMath.base({ balls = 0, finished = 1, won = 1 }) == 35, "forfeit winner")
		H.expect(CandyMath.base({ balls = -3, finished = 0, won = 0 }) == 0, "never below 0")
	end,

	["only real matches against people pay: every pay kind and bot kind"] = function()
		local CandyMath = load()
		local function how(real: boolean, payKind: string, botKind: string?): string
			return CandyMath.how({ real = real, payKind = payKind, botKind = botKind })
		end
		H.expect(how(true, "Player", nil) == "Paid", "people")
		H.expect(how(true, "Player", "Tutorial") == "Paid", "the tutorial's bot counts")
		H.expect(how(true, "Player", "Disguised") == "Disguised", "a disguised bot pays 0")
		H.expect(how(true, "PC", "Disguised") == "Disguised", "past its daily limit too")
		H.expect(how(true, "PC", "Pc") == "PC", "Play against PC (the King too)")
		H.expect(how(true, "PC", nil) == "PC", "PC")
		H.expect(how(false, "Player", nil) == "Short", "a short forfeit")
		H.expect(how(false, "Player", "Tutorial") == "Short", "not real is never paid")
		H.expect(how(true, "Solo", nil) == "PC", "solo never pays")
	end,

	["finished: a played-out match, a draw and both sides of a real forfeit"] = function()
		local CandyMath = load()
		local function candy(balls: number, forfeited: boolean?, won: boolean): number
			return CandyMath.match({
				balls = balls,
				finished = CandyMath.finished(forfeited),
				won = if won then 1 else 0,
			}, 1)
		end
		H.expect(candy(7, false, true) == 21 + 10 + 25, "a win played out: 56")
		H.expect(candy(5, false, false) == 15 + 10, "a loss played out: 25")
		H.expect(candy(4, nil, false) == 12 + 10, "a draw pays the 10")
		H.expect(candy(1, false, true) == 3 + 10 + 25, "the winner of a real forfeit")
		H.expect(candy(3, true, false) == 9, "the side that forfeited keeps its balls only")
	end,

	["the anti-farm rows cut a match's Candy like its money"] = function()
		local CandyMath = load()
		local f = { balls = 6, finished = 1, won = 1, farmBalls = 0.5, farmBonus = 0.25 }
		H.near(CandyMath.base(f), 9 + 2.5 + 6.25, 1e-9, "row 3")
		H.expect(CandyMath.match(f, 1) == 18, "rounded half up (17.75)")
		f.farmBalls, f.farmBonus = 1, 0.5
		H.expect(CandyMath.match(f, 1) == 18 + 5 + 12.5 + 0.5, "row 2 (35.5 -> 36)")
	end,

	["friends +10% each, at most 4, and the group +10%, added (through Money)"] = function()
		local CandyMath = load()
		withFriends(true, function()
			H.near(CandyMath.friendsAdd(0), 0, 1e-9, "none")
			H.near(CandyMath.friendsAdd(2), 0.2, 1e-9, "two")
			H.near(CandyMath.friendsAdd(9), 0.4, 1e-9, "capped at 4")
			H.near(CandyMath.groupAdd(true), 0.1, 1e-9, "group")
			H.near(CandyMath.groupAdd(false), 0, 1e-9, "not in it")
			H.near(CandyMath.multiplier(1, 4, true), 1.5, 1e-9, "1 x (1 + 0.4 + 0.1)")
			H.near(CandyMath.multiplier(2, 4, true), 3.0, 1e-9, "a Rush: 2 x 1.5")
			H.expect(CandyMath.percent(3, true) == 40, "+40%")
			H.expect(CandyMath.match({ balls = 6, finished = 1, won = 1 }, 3.0) == 159, "53 x 3")
		end)
		withFriends(false, function()
			H.near(CandyMath.friendsAdd(4), 0, 1e-9, "the friend switch off: 0")
			H.near(CandyMath.multiplier(2, 4, true), 2.2, 1e-9, "group only")
		end)
	end,

	["the same friends and group without Money's new functions (the fallback)"] = function()
		local CandyMath = load()
		withoutMoneyFriends(function()
			withFriends(true, function()
				H.near(CandyMath.friendsAdd(2), 0.2, 1e-9, "two")
				H.near(CandyMath.friendsAdd(7), 0.4, 1e-9, "capped")
				H.near(CandyMath.groupAdd(true), 0.1, 1e-9, "GroupBoost")
			end)
			withFriends(false, function()
				H.near(CandyMath.friendsAdd(3), 0, 1e-9, "off")
			end)
		end)
	end,

	["the King: two paid wins a UTC day, every win counted, a cooldown each"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		local t = START + 3600
		local first = Ledger.bossWin(hw, t)
		H.expect(first ~= nil and first.granted and first.amount == 50, "first win pays")
		H.expect(first ~= nil and first.cooldownEndsAt == t + 900, "15:00 cooldown")
		H.expect(Ledger.bossCooldown(hw, t + 1) == t + 900, "cooling down")
		H.expect(Ledger.bossCooldown(hw, t + 900) == 0, "ready at 15:00")
		local second = Ledger.bossWin(hw, t + 1000)
		H.expect(second ~= nil and second.granted and second.amount == 50, "second pays")
		local third = Ledger.bossWin(hw, t + 2000)
		H.expect(third ~= nil and not third.granted and third.amount == 0, "third: no Candy")
		H.expect(third ~= nil and third.cooldownEndsAt == t + 2900, "still a cooldown")
		H.expect(hw.KingWins == 3 and hw.Earned == 100, "every win counted, 100 Candy")
		-- The next UTC day pays again.
		local nextDay = (t // 86400 + 1) * 86400 + 5
		local fourth = Ledger.bossWin(hw, nextDay)
		H.expect(fourth ~= nil and fourth.granted and hw.Earned == 150, "a new day")
		H.expect(Ledger.bossWin(hw, START - 1) == nil, "not before the event")
		H.expect(Ledger.bossWin(hw, END) == nil, "not after it")
		H.expect(hw.KingWins == 4, "unchanged outside Live")
		local _ = Config
	end,

	["the timed King: a visit's first win pays Visit once, the rest count only"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local V = Config.Halloween.Boss.Visit
		local hw = SaveSchema.freshHalloween()
		local visit = START + 900 -- a visit's start (the map's kingWindow)
		local first = Ledger.bossVisitWin(hw, visit + 60, visit)
		H.expect(first ~= nil and first.granted and first.amount == V.Candy, "the visit pays Candy")
		H.expect(
			first ~= nil and first.money == V.Money and first.xp == V.Xp,
			"money and XP to give"
		)
		H.expect(first ~= nil and first.cooldownEndsAt == 0, "no cooldown")
		H.expect(hw.KingVisit == visit and hw.Earned == V.Candy, "the visit marked")
		-- A replay, or a second win in the same visit (even one that ends after he left).
		local again = Ledger.bossVisitWin(hw, visit + 900, visit)
		H.expect(again ~= nil and not again.granted and again.amount == 0, "once a visit")
		H.expect(again ~= nil and again.money == 0 and again.xp == 0, "no money or XP again")
		H.expect(hw.KingWins == 2 and hw.Earned == V.Candy, "counted, not paid")
		-- The next visit pays again.
		local nextVisit = visit + 1800
		local third = Ledger.bossVisitWin(hw, nextVisit + 30, nextVisit)
		H.expect(third ~= nil and third.granted and hw.Earned == 2 * V.Candy, "the next visit")
		-- No visit given, or outside the event: nothing.
		local none = Ledger.bossVisitWin(hw, nextVisit + 60, 0)
		H.expect(none ~= nil and not none.granted, "no visit, no pay")
		H.expect(Ledger.bossVisitWin(hw, END, END - 100) == nil, "not after the event")
		H.expect(Ledger.bossVisitWin(hw, START - 1, START - 100) == nil, "not before it")
		H.expect(hw.KingWins == 4, "every win in Live counted")
	end,

	["pickups: NotLive outside the event, Cap at 40 a UTC hour"] = function()
		local _, Ledger, _, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		local ok, why = Ledger.pickup(hw, START - 1)
		H.expect(not ok and why == "NotLive", "before")
		ok, why = Ledger.pickup(hw, END)
		H.expect(not ok and why == "NotLive", "after")
		local hour = START + 7200
		for i = 1, 40 do
			local got, reason = Ledger.pickup(hw, hour + i)
			H.expect(got and reason == nil, "pickup " .. i)
		end
		ok, why = Ledger.pickup(hw, hour + 41)
		H.expect(not ok and why == "Cap", "the 41st")
		H.expect(hw.Earned == 40 and hw.PickCount == 40, "40 Candy")
		ok, why = Ledger.pickup(hw, hour + 3600)
		H.expect(ok and why == nil and hw.PickCount == 1, "the next hour starts over")
	end,

	["Candy adds whole amounts into its bucket; the total counts both"] = function()
		local _, Ledger, _, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		H.expect(Ledger.addCandy(hw, 57, "Earned") == 57, "earned")
		H.expect(Ledger.addCandy(hw, 500, "Bought") == 500, "bought")
		H.expect(
			Ledger.addCandy(hw, 0, "Earned") == 0 and Ledger.addCandy(hw, -5, "Earned") == 0,
			""
		)
		H.expect(Ledger.addCandy(hw, 0 / 0, "Earned") == 0, "NaN")
		H.expect(Ledger.addCandy(hw, 2.9, "Earned") == 2, "floored")
		H.expect(Ledger.total(hw) == 559, "total")
	end,

	["the Spider at 3 h 01 m of active play, once"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local S = Config.Halloween.Spider
		local saved = S.Enabled
		S.Enabled = true
		local hw = SaveSchema.freshHalloween()
		Ledger.addActive(hw, 10855)
		H.expect(not Ledger.spiderDue(hw), "5 s short")
		Ledger.addActive(hw, 5)
		H.expect(Ledger.spiderDue(hw), "due at 10,860")
		hw.Spider = true
		Ledger.addActive(hw, 5)
		H.expect(not Ledger.spiderDue(hw), "once")
		S.Enabled = false
		local other = SaveSchema.freshHalloween()
		Ledger.addActive(other, 20000)
		H.expect(not Ledger.spiderDue(other), "switched off")
		S.Enabled = saved
	end,

	["the lineup of 2026-10-29: the Spider is a track cue and his clock is off"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local C = Config.Halloween
		H.expect(C.Spider.Enabled == false, "the playtime clock is off")
		local onTrack = false
		for _, step in C.Track.Steps do
			onTrack = onTrack or step.Cue == C.Spider.Cue
		end
		H.expect(onTrack, "the Spider is on the track")
		local hw = SaveSchema.freshHalloween()
		Ledger.addActive(hw, 20000)
		H.expect(not Ledger.spiderDue(hw), "never given for play time")
		H.expect(hw.Active == 20000, "active time still counts (the Play N min quests)")
	end,

	["active play counts only after a real match today, the time before it credited"] = function()
		local _, Ledger, Config = load()
		local G = Config.Halloween.ActiveGate
		local saved = G.Enabled
		G.Enabled = true
		-- Before the day's first real match: nothing counts, the time waits.
		local credit, held = Ledger.gateActive(0, 5, false)
		H.expect(credit == 0 and held == 5, "held, not counted")
		credit, held = Ledger.gateActive(held, 5, false)
		H.expect(credit == 0 and held == 10, "still held")
		-- The match is done: the held time and this tick count together.
		credit, held = Ledger.gateActive(held, 5, true)
		H.expect(credit == 15 and held == 0, "credited at once")
		credit, held = Ledger.gateActive(held, 5, true)
		H.expect(credit == 5 and held == 0, "then every tick counts")
		-- An idle lobby never earns: the held time stops at the cap and is never credited alone.
		held = 0
		for _ = 1, 1000 do
			credit, held = Ledger.gateActive(held, 5, false)
			H.expect(credit == 0, "no credit without a match")
		end
		H.expect(held == G.HoldCapSeconds, "held stops at the cap")
		-- Switched off: every active second counts at once.
		G.Enabled = false
		credit, held = Ledger.gateActive(20, 5, false)
		H.expect(credit == 25 and held == 0, "gate off")
		G.Enabled = saved
	end,

	["the end: all Candy at $10, once, only after EndsAt"] = function()
		local _, Ledger, _, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		hw.Earned, hw.Bought = 1240, 500
		H.expect(Ledger.convertMoney(hw) == 17400, "$17,400")
		H.expect(not Ledger.convertDue(hw, END - 1), "not before the end")
		H.expect(Ledger.convertDue(hw, END), "due at the end")
		hw.Converted = true
		H.expect(not Ledger.convertDue(hw, END + 86400 * 40), "once (a December rejoin too)")
	end,

	["the end's money splits into earned and bought (bought Candy is never earned money)"] = function()
		local _, Ledger, _, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		hw.Earned, hw.Bought = 1240, 500
		local earned, bought = Ledger.convertSplit(hw)
		H.expect(earned == 12400 and bought == 5000, "$12,400 earned, $5,000 bought")
		H.expect(earned + bought == Ledger.convertMoney(hw), "the two make the whole")
		hw.Earned, hw.Bought = 0 / 0, -3
		earned, bought = Ledger.convertSplit(hw)
		H.expect(earned == 0 and bought == 0, "bad values are 0")
	end,

	["the end on a rejoin: finished quests claimed first, the marks survive a reload"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local Quests = H.require("Halloween.Quests")
		local hooks = { king = true, pickups = true, ult = true }
		local hw = SaveSchema.freshHalloween()
		hw.Earned = 1000
		-- Board 1 finished, its first quest already claimed: three wait.
		for _, quest in Quests.board(1, hooks) or {} do
			hw.Q[quest.key] = quest.need
		end
		hw.Claimed["1.1"] = true
		local waiting = Quests.claimable(hw.Q, hw.Claimed, Config.Halloween.Boards, hooks)
		H.expect(#waiting == 3, "three to claim: " .. #waiting)
		for _, quest in waiting do -- as PlayerData.hwConvert does, before paying
			hw.Claimed[quest.key] = true
			Ledger.addCandy(hw, quest.reward, "Earned")
		end
		H.expect(hw.Earned == 1000 + 100 + 150 + 250, "rewards in: " .. hw.Earned)
		H.expect(Ledger.convertMoney(hw) == 15000, "$15,000")
		hw.Converted, hw.ConvertedMoney, hw.ConvertedAt = true, 15000, END + 5
		-- Saved and loaded again (a rejoin in any server): still converted, never paid twice.
		local save = SaveSchema.template()
		save.Halloween = hw
		local loaded, fixes = SaveSchema.validate(save)
		H.expect(#fixes == 0, "clean: " .. table.concat(fixes, "; "))
		local again = loaded.Halloween
		H.expect(again.Converted == true and again.ConvertedMoney == 15000, "marks kept")
		H.expect(not Ledger.convertDue(again, END + 86400 * 40), "not again")
		H.expect(
			#Quests.claimable(again.Q, again.Claimed, Config.Halloween.Boards, hooks) == 0,
			"all claimed"
		)
	end,

	["a King match counts one match and its balls for the quests, never a win or Candy"] = function()
		local CandyMath, _, Config = load()
		local B = Config.Halloween.Boss
		local function kinds(events: { { kind: string, amount: number } }): string
			local out = {}
			for _, e in events do
				table.insert(out, e.kind .. "=" .. e.amount)
			end
			return table.concat(out, ",")
		end
		H.expect(B.CountsForQuests == true, "on by default")
		H.expect(kinds(CandyMath.kingEvents(4, false)) == "Matches=1,Balls=4", "a finished match")
		H.expect(kinds(CandyMath.kingEvents(0, nil)) == "Matches=1", "no balls: no Balls event")
		-- A surrender (or timeouts) is no match: an instant one cannot farm the Matches quests.
		H.expect(kinds(CandyMath.kingEvents(3, true)) == "Balls=3", "forfeited: balls only")
		H.expect(kinds(CandyMath.kingEvents(0, true)) == "", "forfeited at once: nothing")
		H.expect(kinds(CandyMath.kingEvents(-2, false)) == "Matches=1", "never negative balls")
		for _, e in CandyMath.kingEvents(7, false) do
			H.expect(e.kind ~= "Wins" and e.kind ~= "TeamWins", "never a win")
		end
		local saved = B.CountsForQuests
		B.CountsForQuests = false
		local off = CandyMath.kingEvents(5, false)
		B.CountsForQuests = saved
		H.expect(#off == 0, "switched off: nothing")
	end,

	["the end with no Candy pays nothing; switched off it never runs"] = function()
		local _, Ledger, Config, SaveSchema = load()
		local hw = SaveSchema.freshHalloween()
		H.expect(Ledger.convertDue(hw, END) and Ledger.convertMoney(hw) == 0, "due, $0")
		local C = Config.Halloween.Convert
		local saved = C.Enabled
		C.Enabled = false
		H.expect(not Ledger.convertDue(hw, END + 60), "off")
		C.Enabled = saved
	end,
}
