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
}
