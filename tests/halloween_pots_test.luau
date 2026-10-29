--!strict
-- Halloween Candy per pocket (Halloween/PotCandy; Config.Halloween.Match.PerPocket, designer
-- 2026-10-29): each pot money pays also pays Candy, against people and disguised bots only, cut
-- by money's anti-farm factor, boosted by the event multiplier and friends + group, a shot paid
-- once, the match's total logged and shown once at its settle, and the switch off giving the
-- old settle-time Candy.

local H = require("./harness")

local function load()
	return H.require("Halloween.PotCandy"),
		H.require("Config").Halloween,
		H.require("Halloween.CandyMath")
end

-- Runs `fn` with Config.Halloween.Match.PerPocketEnabled set to `on`, then puts it back.
local function withSwitch(on: boolean, fn: () -> ())
	local M: any = H.require("Config").Halloween.Match
	local was = M.PerPocketEnabled
	M.PerPocketEnabled = on
	local ok, err = pcall(fn)
	M.PerPocketEnabled = was
	if not ok then
		error(err, 0)
	end
end

local function same(a: { number }, b: { number }, what: string)
	H.expect(#a == #b, ("%s: %d pots, wanted %d"):format(what, #a, #b))
	for i = 1, math.max(#a, #b) do
		H.expect(
			a[i] == b[i],
			("%s: pot %d paid %s, wanted %s"):format(what, i, tostring(a[i]), tostring(b[i]))
		)
	end
end

return {
	["each pot that paid money pays PerPocket Candy, once per pot"] = function()
		local PotCandy, C = load()
		H.expect(C.Match.PerPocket == 3, "3 a pot")
		local state = PotCandy.new()
		local amounts, after = PotCandy.shot(state, { pots = 3, farm = 1, multiplier = 1, seq = 7 })
		same(amounts, { 3, 3, 3 }, "three pots")
		H.expect(PotCandy.sum(amounts) == 9 and after.paid == 9, "9 in all")
		H.expect(state.paid == 0, "the caller keeps the new state only once the save took it")
		local none = PotCandy.shot(after, { pots = 0, farm = 1, multiplier = 1, seq = 8 })
		H.expect(#none == 0, "a shot with no pot pays nothing")
	end,

	["a replayed or re-judged shot (the same seq) never pays twice"] = function()
		local PotCandy = load()
		local amounts, state = PotCandy.shot(PotCandy.new(), { pots = 2, multiplier = 1, seq = 4 })
		H.expect(PotCandy.sum(amounts) == 6, "paid once")
		local again, still = PotCandy.shot(state, { pots = 2, multiplier = 1, seq = 4 })
		H.expect(#again == 0 and still == state, "the same shot: nothing, the state as it was")
		local next = PotCandy.shot(state, { pots = 1, multiplier = 1, seq = 5 })
		same(next, { 3 }, "the next shot pays")
	end,

	["people and disguised bots pay; practice against PC (or the King), solo and the tutorial never"] = function()
		local PotCandy = load()
		H.expect(PotCandy.eligible("Player", nil), "people")
		H.expect(PotCandy.eligible("Player", "Disguised"), "a disguised bot pays like people")
		H.expect(not PotCandy.eligible("Player", "Tutorial"), "never the tutorial's bot")
		H.expect(not PotCandy.eligible("PC", nil), "never practice against PC")
		H.expect(not PotCandy.eligible("PC", "Pc"), "never a PC bot (the Pumpkin King's seat)")
		H.expect(not PotCandy.eligible("Solo", nil), "never solo")
		H.expect(not PotCandy.eligible(nil, nil), "nothing on a doubt")
	end,

	["the anti-farm factor cuts it like money's ball pay, rounded over the match"] = function()
		local PotCandy = load()
		-- Money's last same-opponent row pays balls at 0.5: 1.5 Candy a pot, 6 over 4 pots.
		local state = PotCandy.new()
		local paid: { number } = {}
		for seq = 1, 4 do
			local amounts
			amounts, state =
				PotCandy.shot(state, { pots = 1, farm = 0.5, multiplier = 1, seq = seq })
			table.insert(paid, amounts[1])
		end
		same(paid, { 2, 1, 2, 1 }, "1.5 a pot")
		H.expect(state.paid == 6, "the match's 6")
		local zero = PotCandy.shot(PotCandy.new(), { pots = 3, farm = 0, multiplier = 1, seq = 1 })
		H.expect(PotCandy.sum(zero) == 0, "a farm factor of 0 pays nothing")
	end,

	["the event multiplier and the friends + group boost, never rounded up on every pot"] = function()
		local PotCandy, _, CandyMath = load()
		local rush = PotCandy.shot(PotCandy.new(), { pots = 2, multiplier = 2, event = 2, seq = 1 })
		same(rush, { 6, 6 }, "a Rush or Oct 31: 2x")
		local _, rushState = PotCandy.shot(PotCandy.new(), { pots = 1, multiplier = 2, event = 2 })
		H.expect(rushState.x2 == true, "the end chip's 2x")
		local _, plain = PotCandy.shot(PotCandy.new(), { pots = 1, multiplier = 1.1, event = 1 })
		H.expect(plain.x2 == false, "a friend boost alone is no 2x")
		-- +10% (one friend, or the group): 3.3 a pot, 33 over 10 pots (not 4 x 10 = 40).
		local state = PotCandy.new()
		for seq = 1, 10 do
			local _a
			_a, state = PotCandy.shot(state, { pots = 1, multiplier = 1.1, event = 1, seq = seq })
		end
		H.expect(state.paid == 33, "33 Candy: " .. tostring(state.paid))
		-- The multiplier is CandyMath's: 2 x (1 + 0.4 + 0.1) with 4 friends and the group.
		local E: any = H.require("Config").Economy
		local was = E.FriendBoostEnabled
		E.FriendBoostEnabled = true
		local ok, err = pcall(function()
			local m = CandyMath.multiplier(2, 4, true)
			local amounts = PotCandy.shot(PotCandy.new(), { pots = 2, multiplier = m, event = 2 })
			same(amounts, { 9, 9 }, "3 x 3")
		end)
		E.FriendBoostEnabled = was
		H.expect(ok, tostring(err))
	end,

	["the settle adds nothing: it logs and shows the match's pots once, and counts the quests"] = function()
		local PotCandy = load()
		local state = PotCandy.new()
		for seq = 1, 5 do
			local _a
			_a, state = PotCandy.shot(state, { pots = 1, multiplier = 1, seq = seq })
		end
		local function settle(real: boolean, opponent: string, botKind: string?)
			return PotCandy.settle({
				real = real,
				opponent = opponent,
				botKind = botKind,
				candy = state.paid,
			})
		end
		local people = settle(true, "Player", nil)
		H.expect(people.how == "Paid" and people.quests, "people: the quests count")
		H.expect(
			people.log == 15 and people.toast == 15,
			"one HwCandy and one chip, the match's 15"
		)
		local disguised = settle(true, "Player", "Disguised")
		H.expect(disguised.how == "Disguised" and disguised.quests, "a disguised bot counts too")
		H.expect(disguised.log == 15 and disguised.toast == 15, "and shows its pots' Candy")
		local short = settle(false, "Player", nil)
		H.expect(short.how == "Short" and not short.quests, "a short match: no quest")
		H.expect(short.log == 15 and short.toast == 15, "its pots' Candy still logged and shown")
		for _, f in { { "Player", "Tutorial" }, { "PC", nil }, { "PC", "Pc" }, { "Solo", nil } } do
			local d = settle(true, f[1], f[2])
			H.expect(not d.quests and d.log == 0 and d.toast == 0, "no Candy, no quest: " .. f[1])
		end
		H.expect(settle(true, "Player", "Tutorial").how == "Tutorial", "the tutorial's own how")
		local nothing = PotCandy.settle({ real = true, opponent = "Player", candy = 0 })
		H.expect(nothing.quests and nothing.log == 0 and nothing.toast == 0, "no '+0' chip")
	end,

	["the switch: off is the old settle-time Candy (3 a ball, 10 finished, 25 a win)"] = function()
		local PotCandy, C, CandyMath = load()
		H.expect(PotCandy.on(), "on for the release")
		withSwitch(false, function()
			H.expect(not PotCandy.on(), "off: no Candy per pocket")
			H.expect(C.Match.Enabled == true, "match Candy itself still on")
			-- What CandyService pays at settle then (CandyMath, unchanged).
			H.expect(
				CandyMath.base({ balls = 6, finished = 1, won = 1 }) == 18 + 10 + 25,
				"the old numbers"
			)
			H.expect(CandyMath.how({ real = true, payKind = "Player" }) == "Paid", "people")
			H.expect(
				CandyMath.how({ real = true, payKind = "Player", botKind = "Disguised" })
					== "Disguised",
				"the old rule: a disguised bot paid none"
			)
		end)
		local M: any = C.Match
		local was = M.Enabled
		M.Enabled = false
		local ok, err = pcall(function()
			H.expect(not PotCandy.on(), "match Candy off: none per pocket either")
		end)
		M.Enabled = was
		H.expect(ok, tostring(err))
	end,

	["bad numbers pay nothing, never an error"] = function()
		local PotCandy = load()
		for _, shot in
			{
				{ pots = 0 / 0, multiplier = 1 },
				{ pots = 2, multiplier = 0 / 0 },
				{ pots = 2, multiplier = -1 },
				{ pots = 2, multiplier = 1, farm = 0 / 0 },
				{ pots = -3, multiplier = 1 },
			}
		do
			local amounts = PotCandy.shot(PotCandy.new(), shot :: any)
			H.expect(PotCandy.sum(amounts) == 0, "nothing")
		end
	end,
}
