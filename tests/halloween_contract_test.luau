--!strict
-- The Halloween 2026 contract (docs/halloween/PLAN.md, HW_COORDINATOR_PROMPT.md §2.7): every
-- number the plan fixes, checked against the names the lanes chose. A part whose lane has not
-- merged yet is skipped with a printed note while STRICT is false; the coordinator sets STRICT
-- at 12:00, after which nothing may skip.

local H = require("./harness")

local STRICT = true

local GO_LIVE = 1793228400 -- Wed Oct 28 19:00 EDT
local COUNTDOWN = 1793226600 -- 18:30 EDT
local ENDS = 1793750400 -- Tue Nov 3 19:00 EST
local DOUBLE_FROM, DOUBLE_TO = 1793419200, 1793505600 -- Oct 31, US Eastern
local EVENT_CUES = { "JackOLanternCue", "PitchforkCue", "WitchBroomCue", "HalloweenSwordCue" }

local function tryRequire(path: string): any
	local ok, mod = pcall(H.require, path)
	return if ok then mod else nil
end

-- Returns true when the part can run; else prints the skip (or fails once STRICT).
local function present(part: string, thing: any): boolean
	if thing ~= nil then
		return true
	end
	H.expect(not STRICT, part .. " is missing and STRICT is on")
	print(("  SKIP halloween contract: %s not merged yet"):format(part))
	return false
end

-- Finds a value in a step row whatever the lane named its keys: the number `need` and the
-- reward (a cue id, a money amount or a spin count) among its fields.
local function stepHas(step: { [string]: any }, need: number, reward: any): boolean
	local hasNeed, hasReward = false, false
	for _, v in step do
		if v == need then
			hasNeed = true
		end
		if v == reward then
			hasReward = true
		end
		if typeof(v) == "table" then
			for _, w in v do
				if w == reward then
					hasReward = true
				end
			end
		end
	end
	return hasNeed and hasReward
end

return {
	["halloween: the event clock steps at the plan's times"] = function()
		local Event = tryRequire("Halloween.Event")
		if not present("Halloween.Event (core)", Event) then
			return
		end
		H.expect(Event.state(COUNTDOWN - 1) == "Before", "Before until 18:30")
		H.expect(Event.state(COUNTDOWN) == "Countdown", "Countdown from 18:30")
		H.expect(Event.state(GO_LIVE - 1) == "Countdown", "Countdown until 19:00")
		H.expect(Event.state(GO_LIVE) == "Live", "Live from 19:00")
		H.expect(Event.state(ENDS - 1) == "Live", "Live until Nov 3 19:00 EST")
		H.expect(Event.state(ENDS) == "Ended", "Ended from Nov 3 19:00 EST")
		H.expect(
			Event.isLive(GO_LIVE) and not Event.isLive(GO_LIVE - 1) and not Event.isLive(ENDS),
			"isLive window"
		)
		for n = 1, 6 do
			local opens = GO_LIVE + (n - 1) * 86400
			H.expect(Event.boardIndex(opens) == n, ("board %d opens at its time"):format(n))
			if n > 1 then
				H.expect(
					Event.boardIndex(opens - 1) == n - 1,
					("board %d not before its time"):format(n)
				)
			end
		end
	end,

	["halloween: the multiplier is 2 only in Rush minutes and on Oct 31, never 4"] = function()
		local Event = tryRequire("Halloween.Event")
		if not present("Halloween.Event (core)", Event) then
			return
		end
		local t = GO_LIVE
		while t < ENDS do
			for _, offset in { 0, 5 * 60, 9 * 60 + 59, 10 * 60 } do
				local now = math.min(t + offset, ENDS - 1)
				local m = Event.multiplier(now)
				local minute = (now // 60) % 60
				local double = now >= DOUBLE_FROM and now < DOUBLE_TO
				local want = if minute < 10 or double then 2 else 1
				H.expect(
					m == want,
					("multiplier at %d is %s, want %d"):format(now, tostring(m), want)
				)
				H.expect(Event.rushActive(now) == (minute < 10), ("rush at %d"):format(now))
			end
			t += 600
		end
	end,

	["halloween: Candy, quests, King, pickups, packs and conversion numbers"] = function()
		local Config = H.require("Config")
		local C = Config.Halloween
		if not present("Config.Halloween (core)", C) then
			return
		end
		H.expect(
			C.StartsAt == GO_LIVE and C.EndsAt == ENDS and C.CountdownAt == COUNTDOWN,
			"event times"
		)
		H.expect(C.Double.From == DOUBLE_FROM and C.Double.To == DOUBLE_TO, "Oct 31 Eastern window")
		H.expect(
			C.Match.PerBall == 3 and C.Match.Finished == 10 and C.Match.Win == 25,
			"3 a ball, 10 finished, +25 a win"
		)
		local r = C.Quests.Rewards
		H.expect(
			r[1] == 60 and r[2] == 100 and r[3] == 150 and r[4] == 250 and #r == 4,
			"quests 60/100/150/250"
		)
		H.expect(
			C.Boss.Candy == 50 and C.Boss.PaidWinsPerDay == 2 and C.Boss.CooldownSeconds == 900,
			"King 50 x2/day, 900 s"
		)
		H.expect(
			C.Pickup.Candy == 5 and C.Pickup.HourCap == 80,
			"5 Candy a pickup, 80 pickups a player a UTC hour"
		)
		H.expect(
			C.Spider.Seconds == 10860 and C.Spider.Cue == "SpiderCue",
			"Spider at 3 h 01 m active"
		)
		H.expect(C.Convert.MoneyPerCandy == 10, "$10 a Candy at the end")
		H.expect(typeof(C.CandyIcon) == "string", "CandyIcon is a string")
		for _, banned in
			{ "FriendAdd", "FriendMax", "FriendsEnabled", "GroupAdd", "FriendBoost", "GroupBoost" }
		do
			H.expect(
				C[banned] == nil,
				"no second copy of the boost numbers: Config.Halloween." .. banned
			)
		end
		local steps = C.Track.Steps
		if
			present("Config.Halloween.Track.Steps rows (core)", if #steps > 0 then steps else nil)
		then
			local want = {
				{ 50, 1 },
				{ 150, 2 },
				{ 300, 2500 },
				{ 500, "PitchforkCue" },
				{ 1000, 2 },
				{ 1500, 5000 },
				{ 2000, "WitchBroomCue" },
				{ 3000, 3 },
				{ 4500, 10000 },
				{ 5500, 5 },
				{ 7000, "HalloweenSwordCue" },
			}
			H.expect(#steps == #want, ("track has %d steps, want 11"):format(#steps))
			for i, w in want do
				H.expect(
					steps[i] ~= nil and stepHas(steps[i], w[1], w[2]),
					("track step %d: %s at %d"):format(i, tostring(w[2]), w[1])
				)
			end
		end
	end,

	["halloween: the boost numbers live only in Config.Economy"] = function()
		local Config = H.require("Config")
		local E = Config.Economy
		if not present("Config.Economy.FriendBoost (gui)", E.FriendBoost) then
			return
		end
		H.expect(E.FriendBoost == 0.1 and E.FriendBoostMaxFriends == 4, "+10% a friend, max 4")
		H.expect(E.GroupBoost == 0.1, "group +10%")
		H.expect(typeof(E.FriendBoostEnabled) == "boolean", "FriendBoostEnabled is a switch")
		local Money = H.require("Progression.Money")
		H.expect(
			typeof(Money.friendBoost) == "function" and typeof(Money.boostParts) == "function",
			"Money API"
		)
		local was = E.FriendBoostEnabled
		E.FriendBoostEnabled = true
		local ok, err = pcall(function()
			for n = 0, 8 do
				H.near(
					Money.friendBoost(n),
					0.1 * math.min(n, 4),
					1e-9,
					("friendBoost(%d)"):format(n)
				)
			end
		end)
		E.FriendBoostEnabled = was
		H.expect(ok, tostring(err))
	end,

	["halloween: a match's Candy is 3 a ball, 10 finished, +25 a win, boosted by friends and group"] = function()
		local CandyMath = tryRequire("Halloween.CandyMath")
		if not present("Halloween.CandyMath (core)", CandyMath) then
			return
		end
		H.expect(
			CandyMath.base({ balls = 7, finished = 1, won = 1 }) == 56,
			"7 balls, finished, won: 56"
		)
		H.expect(
			CandyMath.base({ balls = 7, finished = 1, won = 0 }) == 31,
			"7 balls, finished, lost: 31"
		)
		H.expect(
			CandyMath.base({ balls = 7, finished = 0, won = 0 }) == 21,
			"the side that forfeited keeps only its balls"
		)
		if present("CandyMath.finished (core)", CandyMath.finished) then
			H.expect(CandyMath.finished(true) == 0, "a forfeit is not finished")
			H.expect(
				CandyMath.finished(false) == 1 and CandyMath.finished(nil) == 1,
				"a played-out match and the winner of a real forfeit get the 10"
			)
		end
		local E = H.require("Config").Economy
		local was = E.FriendBoostEnabled
		E.FriendBoostEnabled = true
		local ok, err = pcall(function()
			H.near(CandyMath.multiplier(1, 0, false), 1, 1e-9, "no boost")
			H.near(CandyMath.multiplier(2, 0, false), 2, 1e-9, "Rush or Oct 31 alone")
			H.near(CandyMath.multiplier(1, 9, false), 1.4, 1e-9, "friends capped at 4")
			H.near(CandyMath.multiplier(2, 4, true), 3, 1e-9, "2 x (1 + 0.4 + 0.1)")
			H.expect(CandyMath.match({ balls = 7, finished = 1, won = 1 }, 3) == 168, "56 x 3")
		end)
		E.FriendBoostEnabled = was
		H.expect(ok, tostring(err))
	end,

	["halloween: map's tables and the King"] = function()
		local Config = H.require("Config")
		local M = Config.HalloweenMap
		if not present("Config.HalloweenMap (map)", M) then
			return
		end
		local by = M.Tables.ByTeamSize
		local function rgb(c: { number }, r: number, g: number, b: number): boolean
			return c[1] == r and c[2] == g and c[3] == b
		end
		H.expect(rgb(by[1].Cloth, 185, 90, 230), "1v1 orchid purple")
		H.expect(rgb(by[2].Cloth, 90, 94, 102), "2v2 charcoal")
		H.expect(rgb(by[3].Cloth, 88, 176, 32), "3v3 toxic green")
		H.expect(
			M.Boss.Kind == "Pc" and M.Boss.Rematch == "Never",
			"King is kind Pc, rematch Never"
		)
		H.expect(
			M.Boss.MaxAtOnce == 3 and M.Boss.SpareTables == 2,
			"at most 3 King matches, 2 spare tables"
		)
		for _, k in { "HourCap", "CapPerHour", "Cap" } do
			H.expect(M.Candy[k] == nil, "no second pickup cap: HalloweenMap.Candy." .. k)
		end
	end,

	["halloween: the five cues are Exclusive rows with names"] = function()
		local Catalog = H.require("Progression.Catalog")
		local Strings = H.require("Strings")
		if not present("the five Catalog rows (cues-a)", Catalog.get("JackOLanternCue")) then
			return
		end
		for _, id in EVENT_CUES do
			local cue = Catalog.get(id)
			H.expect(cue ~= nil, id .. " is in the Catalog")
			if cue then
				H.expect(cue.Group == "Exclusive", id .. " is group Exclusive")
				H.expect(
					cue.Tradable == false and cue.Sellable == false,
					id .. " is never traded or sold"
				)
			end
			H.expect(typeof(Strings.Items.Cues[id]) == "string", id .. " has a name in Strings")
			H.expect(id ~= "CandyCue" and id ~= "PhantomCue", "never reuse CandyCue or PhantomCue")
		end
		H.expect(
			typeof(Catalog.ready) == "function",
			"Catalog.ready exists (core holds grants on it)"
		)
	end,

	["halloween: every switch is a boolean"] = function()
		local Config = H.require("Config")
		local function check(label: string, t: any, keys: { string })
			if t == nil then
				present(label, nil)
				return
			end
			for _, k in keys do
				local v = t
				for seg in k:gmatch("[^%.]+") do
					v = if typeof(v) == "table" then v[seg] else nil
				end
				H.expect(typeof(v) == "boolean", ("%s.%s is a boolean"):format(label, k))
			end
		end
		check("Config.Halloween", Config.Halloween, {
			"Match.Enabled",
			"Quests.Enabled",
			"Spider.Enabled",
			"Packs.Enabled",
			"Convert.Enabled",
		})
		check(
			"Config.HalloweenMap",
			Config.HalloweenMap,
			{ "Enabled", "Boss.Enabled", "Candy.Enabled", "Tables.Enabled" }
		)
		check("Config.Multiplayer.Roam", Config.Multiplayer.Roam, { "Enabled" })
		check("Config.Badges", Config.Badges, { "Enabled" })
		check("Config.UI.BoostPill", Config.UI.BoostPill, { "Enabled" })
		check("Config.UI.CuePreview", Config.UI.CuePreview, { "Enabled" })
		check(
			"Config.Economy friend boost",
			if Config.Economy.FriendBoost ~= nil then Config.Economy else nil,
			{ "FriendBoostEnabled" }
		)
	end,
}
