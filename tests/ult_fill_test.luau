--!strict
-- The ult bar's fill (Ults/Fill; docs/prompts/ULTIMATES_PROMPT.md sections 4, 5 and 12): the
-- run, nice shots, opponent's balls and falling behind, turn ends and their cap, the table's
-- difficulty, after the first ult, the cap of 2, teams, the ult shot, the break, the open
-- table, the full bar and the 8. Every number is read from Config.Ults.Fill.

local H = require("./harness")

local function load(): (any, any)
	return H.require("Ults.Fill"), H.require("Config")
end

local ME, THEM = 101, 202

-- Round half up, as the fill does after its multipliers.
local function round(x: number): number
	return math.floor(x + 0.5 + 1e-9)
end

-- A full rack before any shot: the cue ball and 1..15, nothing pocketed.
local function rack(pocketed: { number }?): { any }
	local balls = {}
	for id = 0, 15 do
		table.insert(balls, { id = id, pocketed = table.find(pocketed or {}, id) ~= nil })
	end
	return balls
end

local function oneVsOne(): { any }
	return { { userId = ME, team = 1 }, { userId = THEM, team = 2 } }
end

-- Drops of `ids`, half a second apart; ids in `nice` are nice shots.
local function dropsOf(ids: { number }, nice: { number }?): { any }
	local list = {}
	for i, id in ids do
		table.insert(list, { ball = id, t = i * 0.5, nice = table.find(nice or {}, id) ~= nil })
	end
	return list
end

-- A shot by ME (solids, team 1) in Difficult, from level, overridden by `fields`.
local function ctx(bars: any, fields: { [string]: any }?): any
	local c: any = {
		seats = oneVsOne(),
		bars = bars,
		shooter = ME,
		team = 1,
		difficulty = "Difficult",
		breakShot = false,
		groupsBefore = { "solids", "stripes" },
		groupsAfter = { "solids", "stripes" },
		ballsBefore = rack(),
		openPotted = { 0, 0 },
		drops = {},
		run = 0,
		turnEnds = false,
		legal = true,
		ultShot = false,
	}
	for key, value in fields or {} do
		c[key] = value
	end
	return c
end

-- The total `userId` gained in `gains` (only `reason` when given).
local function total(gains: { any }, userId: number, reason: string?): number
	local sum = 0
	for _, gain in gains do
		if gain.userId == userId and (reason == nil or gain.reason == reason) then
			sum += gain.amount
		end
	end
	return sum
end

local function barOf(bars: any, userId: number): any
	return bars[tostring(userId)]
end

-- What an opponent's `n` balls in a row from level give, before the bar's cap.
local function oppRun(F: any, n: number, scale: number): number
	local sum = 0
	for behind = 1, n do
		sum += round((F.OppBase + F.OppPerBehind * behind) * scale)
	end
	return sum
end

return {
	["a new bar, ready and spend"] = function()
		local Fill, Config = load()
		local bar = Fill.newBar()
		H.expect(bar.bar == 0 and bar.used == 0 and bar.turnFill == 0, "empty")
		H.expect(not Fill.ready(bar), "not ready empty")
		bar.bar = Config.Ults.BarMax
		bar.turnFill = 30
		H.expect(Fill.ready(bar), "full is ready")
		Fill.spend(bar)
		H.expect(bar.bar == 0 and bar.used == 1 and bar.turnFill == 0, "spent")
		bar.bar = Config.Ults.BarMax
		H.expect(Fill.ready(bar), "a second ult")
		Fill.spend(bar)
		bar.bar = Config.Ults.BarMax
		H.expect(not Fill.ready(bar), "never a third")
	end,

	["four opponent balls from level fill the bar, three don't"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local four = oppRun(F, 4, F.Difficulty.Difficult)
		local three = oppRun(F, 3, F.Difficulty.Difficult)
		H.expect(four >= Config.Ults.BarMax and three < Config.Ults.BarMax, "4 fills, 3 doesn't")

		local bars = {}
		local result = Fill.shot(ctx(bars, { drops = dropsOf({ 1, 2, 3, 4 }) }))
		H.expect(barOf(bars, THEM).bar == Config.Ults.BarMax, "full after 4 (Difficult)")
		H.expect(total(result.gains, THEM, "Opponent") == Config.Ults.BarMax, "cut at 100")
		local amounts = {}
		for _, gain in result.gains do
			if gain.userId == THEM then
				table.insert(amounts, gain.amount)
			end
		end
		for behind = 1, 3 do
			H.expect(amounts[behind] == F.OppBase + F.OppPerBehind * behind, "+8, +7 a ball behind")
		end
		H.expect(amounts[4] == Config.Ults.BarMax - three, "the last cut to the bar's top")

		bars = {}
		Fill.shot(ctx(bars, { drops = dropsOf({ 1, 2, 3 }) }))
		H.expect(barOf(bars, THEM).bar == three, "3 balls' worth")
		-- Even with the opponent's turn end, 3 balls don't fill it.
		bars = {}
		Fill.shot(ctx(bars, { drops = dropsOf({ 1, 2, 3 }), turnEnds = true }))
		H.expect(barOf(bars, THEM).bar == three + F.OppTurn, "3 balls and the turn end")
		H.expect(barOf(bars, THEM).bar < Config.Ults.BarMax, "not full")

		bars = {}
		Fill.shot(ctx(bars, { drops = dropsOf({ 1, 2, 3, 4 }), difficulty = "Classic" }))
		H.expect(barOf(bars, THEM).bar == Config.Ults.BarMax, "full after 4 (Classic)")
		H.expect(oppRun(F, 3, F.Difficulty.Classic) < Config.Ults.BarMax, "3 in Classic don't")
	end,

	["a run of 7 in one turn gives the run fill, continuing across shots"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local expected = 0
		for n = 1, 7 do
			expected += F.Own[n] or F.OwnAfter
		end

		local function runOf7(difficulty: string): (number, { number })
			local bars = {}
			local runs = {}
			local run = 0
			local pocketed = {}
			for _, shot in { { 1, 2, 3 }, { 4, 5 }, { 6, 7 } } do
				local result = Fill.shot(ctx(bars, {
					drops = dropsOf(shot),
					ballsBefore = rack(pocketed),
					run = run,
					difficulty = difficulty,
				}))
				run = result.run
				table.insert(runs, run)
				for _, id in shot do
					table.insert(pocketed, id)
				end
			end
			return barOf(bars, ME).bar, runs
		end
		local bar, runs = runOf7("Difficult")
		H.expect(bar == expected, ("+%d in Difficult, got %d"):format(expected, bar))
		H.expect(runs[1] == 3 and runs[2] == 5 and runs[3] == 7, "the run carries on")
		H.expect(bar < Config.Ults.BarMax, "your own run alone doesn't fill it")

		local classic = 0
		for n = 1, 7 do
			classic += round((F.Own[n] or F.OwnAfter) * F.Difficulty.Classic)
		end
		H.expect(runOf7("Classic") == classic, "Classic's run of 7: x1.3 rounded per ball")

		-- The turn's end starts the next run over.
		local bars = {}
		local ended = Fill.shot(ctx(bars, { drops = dropsOf({ 1 }), run = 4, turnEnds = true }))
		H.expect(ended.run == 0, "a new turn starts a new run")
		H.expect(total(ended.gains, ME, "Own") == (F.Own[5] or F.OwnAfter), "the 5th ball")
	end,

	["a nice shot gives +20 on top of the ball"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		local result = Fill.shot(ctx(bars, { drops = dropsOf({ 3 }, { 3 }) }))
		H.expect(total(result.gains, ME, "Own") == F.Own[1], "the ball")
		H.expect(total(result.gains, ME, "Nice") == F.Nice, "+Nice on top")
		local nice = result.gains[2]
		H.expect(nice.reason == "Nice" and nice.ball == 3 and nice.t == 0.5, "ball and time")

		bars = {}
		result = Fill.shot(ctx(bars, { drops = dropsOf({ 3 }, { 3 }), difficulty = "Classic" }))
		H.expect(total(result.gains, ME, "Nice") == round(F.Nice * F.Difficulty.Classic), "x1.3")

		-- A nice pot of the opponent's ball is no nice shot of yours.
		bars = {}
		result = Fill.shot(ctx(bars, { drops = dropsOf({ 9 }, { 9 }) }))
		H.expect(total(result.gains, ME, "Nice") == 0, "not your own pot")
	end,

	["turn ends: +15 for your legal shot, +6 for the opponent's, none on a foul or timeout"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		local result = Fill.shot(ctx(bars, { turnEnds = true, legal = true }))
		H.expect(total(result.gains, ME, "Turn") == F.TurnLegal, "+TurnLegal")
		H.expect(total(result.gains, THEM, "OpponentTurn") == F.OppTurn, "+OppTurn")
		H.expect(barOf(bars, ME).turnFill == F.TurnLegal, "counted as turn fill")
		H.expect(barOf(bars, THEM).turnFill == F.OppTurn, "counted as turn fill")

		bars = {}
		result = Fill.shot(ctx(bars, { turnEnds = true, legal = false }))
		H.expect(total(result.gains, ME) == 0, "a foul gives the shooter nothing")
		H.expect(total(result.gains, THEM, "OpponentTurn") == F.OppTurn, "the opponent's +6")

		bars = {}
		local timeout = Fill.timeout({
			seats = oneVsOne(),
			bars = bars,
			shooter = ME,
			team = 1,
			difficulty = "Difficult",
		})
		H.expect(total(timeout.gains, ME) == 0, "a timeout gives the shooter nothing")
		H.expect(total(timeout.gains, THEM, "OpponentTurn") == F.OppTurn, "+6 after a timeout")

		-- A turn that goes on gives no turn fill.
		bars = {}
		result = Fill.shot(ctx(bars, { drops = dropsOf({ 1 }), turnEnds = false }))
		H.expect(total(result.gains, ME, "Turn") == 0, "no turn fill mid-turn")
		H.expect(total(result.gains, THEM) == F.OppBase + F.OppPerBehind, "only the ball")
	end,

	["turn-end fill stops at 50: ten deliberate misses leave the bar at 50"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		for _, difficulty in { "Difficult", "Classic" } do
			local bars = {}
			for _ = 1, 10 do
				Fill.shot(ctx(bars, { turnEnds = true, legal = true, difficulty = difficulty }))
				Fill.shot(ctx(bars, {
					shooter = THEM,
					team = 2,
					turnEnds = true,
					legal = true,
					difficulty = difficulty,
				}))
			end
			H.expect(barOf(bars, ME).bar == F.TurnCap, difficulty .. ": the cap")
			H.expect(barOf(bars, THEM).bar == F.TurnCap, "the other misser too")
			H.expect(barOf(bars, ME).turnFill == F.TurnCap, "the cap doesn't scale")
			-- Balls still fill past the cap.
			Fill.shot(
				ctx(
					bars,
					{ shooter = THEM, team = 2, drops = dropsOf({ 9 }), difficulty = difficulty }
				)
			)
			H.expect(barOf(bars, ME).bar > F.TurnCap, "an opponent's ball still counts")
		end
	end,

	["Classic multiplies every gain by 1.3"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local scale = F.Difficulty.Classic
		H.expect(scale > 1 and F.Difficulty.Difficult == 1 and F.Difficulty.Challenger == 1, "")
		local bars = {}
		local result = Fill.shot(
			ctx(bars, { drops = dropsOf({ 1 }), turnEnds = true, difficulty = "Classic" })
		)
		H.expect(total(result.gains, ME, "Own") == round(F.Own[1] * scale), "own x1.3")
		H.expect(total(result.gains, ME, "Turn") == round(F.TurnLegal * scale), "turn x1.3")
		H.expect(
			total(result.gains, THEM, "Opponent") == round((F.OppBase + F.OppPerBehind) * scale),
			"opponent's ball x1.3, rounded half up"
		)
		H.expect(total(result.gains, THEM, "OpponentTurn") == round(F.OppTurn * scale), "x1.3")
		for _, gain in result.gains do
			H.expect(gain.amount == math.floor(gain.amount) and gain.amount >= 1, "whole numbers")
		end
		-- Challenger is x1 like Difficult.
		bars = {}
		result = Fill.shot(ctx(bars, { drops = dropsOf({ 1 }), difficulty = "Challenger" }))
		H.expect(total(result.gains, ME, "Own") == F.Own[1], "x1")
	end,

	["after the first ult gains are x AfterFirst and the turn cap counts again"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		for _ = 1, 5 do
			Fill.shot(ctx(bars, { turnEnds = true, legal = true }))
		end
		local mine = barOf(bars, ME)
		H.expect(mine.turnFill == F.TurnCap, "capped before the ult")
		mine.bar = Config.Ults.BarMax
		Fill.spend(mine)
		H.expect(mine.bar == 0 and mine.used == 1 and mine.turnFill == 0, "spent")

		local result = Fill.shot(ctx(bars, { shooter = THEM, team = 2, drops = dropsOf({ 9 }) }))
		local expected = round((F.OppBase + F.OppPerBehind) * F.AfterFirst)
		H.expect(total(result.gains, ME, "Opponent") == expected, "x AfterFirst, rounded")
		H.expect(total(result.gains, THEM, "Own") == F.Own[1], "the opponent's bar is untouched")

		mine.bar = 0
		local turnGain = round(F.TurnLegal * F.AfterFirst)
		local turns = 0
		while mine.turnFill < F.TurnCap and turns < 100 do
			Fill.shot(ctx(bars, { turnEnds = true, legal = true }))
			turns += 1
		end
		H.expect(mine.turnFill == F.TurnCap and mine.bar == F.TurnCap, "the cap again, from 0")
		H.expect(turns == math.ceil(F.TurnCap / turnGain), "at AfterFirst speed")
		result = Fill.shot(ctx(bars, { turnEnds = true, legal = true }))
		H.expect(total(result.gains, ME) == 0, "capped")

		-- Classic's x1.3 and AfterFirst multiply before one rounding.
		local classic = {}
		Fill.shot(ctx(classic, { drops = dropsOf({ 1 }), difficulty = "Classic" }))
		barOf(classic, ME).bar = 0
		Fill.spend(barOf(classic, ME))
		Fill.shot(ctx(classic, { drops = dropsOf({ 2 }), difficulty = "Classic" }))
		local both = F.Own[1] * F.Difficulty.Classic * F.AfterFirst
		H.expect(barOf(classic, ME).bar == round(both), "one rounding")
	end,

	["at most 2 ults: after the second the bar stays empty"] = function()
		local Fill, Config = load()
		local bars = {}
		bars[tostring(ME)] = { bar = 0, used = Config.Ults.MaxPerMatch, turnFill = 0 }
		local result = Fill.shot(ctx(bars, {
			drops = dropsOf({ 1, 2, 9, 10 }, { 1 }),
			turnEnds = true,
			legal = true,
		}))
		H.expect(total(result.gains, ME) == 0 and barOf(bars, ME).bar == 0, "nothing")
		H.expect(total(result.gains, THEM) > 0, "the opponent still fills")
		local t = Fill.timeout({
			seats = oneVsOne(),
			bars = bars,
			shooter = THEM,
			team = 2,
			difficulty = "Classic",
		})
		H.expect(total(t.gains, ME) == 0 and barOf(bars, ME).bar == 0, "not even turn fill")
	end,

	["teams: a teammate's ball gives +2 and behind compares sides"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local seats = {
			{ userId = 1, team = 1 },
			{ userId = 2, team = 2 },
			{ userId = 3, team = 1 },
			{ userId = 4, team = 2 },
		}
		local bars = {}
		local result = Fill.shot(ctx(bars, { seats = seats, shooter = 1, drops = dropsOf({ 1 }) }))
		H.expect(total(result.gains, 1, "Own") == F.Own[1], "the shooter's run")
		H.expect(total(result.gains, 3, "Teammate") == F.Teammate, "+Teammate")
		H.expect(total(result.gains, 3) == F.Teammate, "only that")
		for _, user in { 2, 4 } do
			H.expect(
				total(result.gains, user, "Opponent") == F.OppBase + F.OppPerBehind,
				"1 behind"
			)
		end

		-- Team 2 has pocketed 3 stripes: team 1 is 3 behind, 4 after the next stripe.
		bars = {}
		result = Fill.shot(ctx(bars, {
			seats = seats,
			shooter = 2,
			team = 2,
			ballsBefore = rack({ 9, 10, 11 }),
			drops = dropsOf({ 12 }),
		}))
		for _, user in { 1, 3 } do
			H.expect(total(result.gains, user, "Opponent") == F.OppBase + F.OppPerBehind * 4, "")
		end
		H.expect(total(result.gains, 4, "Teammate") == F.Teammate, "the teammate")
		H.expect(total(result.gains, 2, "Own") == F.Own[1], "the shooter")

		-- A ball of the other side, pocketed by your teammate, fills you as an opponent's ball.
		bars = {}
		result = Fill.shot(ctx(bars, { seats = seats, shooter = 1, drops = dropsOf({ 9 }) }))
		H.expect(total(result.gains, 3, "Opponent") == F.OppBase + F.OppPerBehind, "behind 1")
		H.expect(total(result.gains, 2) == 0 and total(result.gains, 4) == 0, "their own ball")
		-- Turn ends: every opponent gets +6, the shooter's teammate nothing.
		bars = {}
		result = Fill.shot(ctx(bars, { seats = seats, shooter = 1, turnEnds = true, legal = true }))
		H.expect(total(result.gains, 1) == F.TurnLegal and total(result.gains, 3) == 0, "")
		H.expect(total(result.gains, 2) == F.OppTurn and total(result.gains, 4) == F.OppTurn, "")
	end,

	["an ult shot gives its user nothing but fills the opponent"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		local result = Fill.shot(ctx(bars, {
			ultShot = true,
			drops = dropsOf({ 1, 2, 9 }, { 1 }),
			turnEnds = true,
			legal = true,
		}))
		H.expect(total(result.gains, ME, "Own") == 0 and total(result.gains, ME, "Nice") == 0, "")
		H.expect(total(result.gains, ME, "Opponent") == 0, "not even the opponent's ball")
		H.expect(total(result.gains, ME, "Turn") == F.TurnLegal, "the turn end still counts")
		H.expect(
			total(result.gains, THEM, "Opponent")
				== (F.OppBase + F.OppPerBehind) + (F.OppBase + F.OppPerBehind * 2),
			"the opponent fell 1, then 2 behind"
		)
		H.expect(result.run == 0, "the turn ended")
		-- The run still counts the ult shot's balls.
		bars = {}
		result = Fill.shot(ctx(bars, { ultShot = true, drops = dropsOf({ 1, 2 }) }))
		H.expect(result.run == 2, "two balls in the run")
		result = Fill.shot(
			ctx(bars, { drops = dropsOf({ 3 }), run = result.run, ballsBefore = rack({ 1, 2 }) })
		)
		H.expect(total(result.gains, ME, "Own") == F.Own[3], "the third ball of the run")
	end,

	["the break: its balls are the breaker's own"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		local result = Fill.shot(ctx(bars, {
			breakShot = true,
			groupsBefore = {},
			groupsAfter = {},
			drops = dropsOf({ 1, 9, 8 }),
		}))
		H.expect(total(result.gains, ME, "Own") == F.Own[1] + F.Own[2], "both balls, the 8 none")
		H.expect(result.run == 2, "the run")
		-- The opponent is 1, then 2 behind (open table: balls pocketed).
		H.expect(
			total(result.gains, THEM, "Opponent")
				== (F.OppBase + F.OppPerBehind) + (F.OppBase + F.OppPerBehind * 2),
			"1, then 2 behind"
		)
		for _, gain in result.gains do
			H.expect(gain.ball ~= 8, "the 8 fills nothing")
		end
	end,

	["an open table: behind comes from the balls each side pocketed"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		-- Team 2 pocketed 2 while open and pockets one more: team 1 is 3 behind.
		local bars = {}
		local result = Fill.shot(ctx(bars, {
			shooter = THEM,
			team = 2,
			groupsBefore = {},
			openPotted = { 0, 2 },
			ballsBefore = rack({ 3, 12 }),
			drops = dropsOf({ 5 }),
		}))
		H.expect(total(result.gains, THEM, "Own") == F.Own[1], "a solid is the shooter's own")
		H.expect(total(result.gains, ME, "Opponent") == F.OppBase + F.OppPerBehind * 3, "3 behind")
		-- Ahead on the open table: never negative.
		bars = {}
		result = Fill.shot(ctx(bars, {
			groupsBefore = {},
			openPotted = { 0, 2 },
			drops = dropsOf({ 9 }),
		}))
		H.expect(total(result.gains, THEM, "Opponent") == F.OppBase, "ahead: just +8")
		H.expect(Fill.behind({}, rack(), 1, { 1, 4 }) == 3, "behind helper, open")
		H.expect(Fill.behind({}, rack(), 2, { 1, 4 }) == 0, "never negative")
		H.expect(Fill.behind({ "solids", "stripes" }, rack({ 9, 10 }), 1) == 2, "with groups")
		-- A side on the 8 counts 0 left.
		local cleared = rack({ 1, 2, 3, 4, 5, 6, 7 })
		H.expect(Fill.behind({ "solids", "stripes" }, cleared, 2) == 7, "solids cleared")
	end,

	["your own balls pocketed by the opponent give you nothing"] = function()
		local Fill, Config = load()
		local F = Config.Ults.Fill
		local bars = {}
		local result = Fill.shot(ctx(bars, { drops = dropsOf({ 9 }) }))
		H.expect(total(result.gains, THEM) == 0, "the stripes player gets nothing")
		H.expect(
			total(result.gains, ME, "Opponent") == F.OppBase + F.OppPerBehind,
			"the shooter gets an opponent's ball: 7 left vs 6, 1 behind"
		)
		H.expect(result.run == 0, "not your run")
	end,

	["the bar never passes 100"] = function()
		local Fill, Config = load()
		local max = Config.Ults.BarMax
		local bars = {}
		bars[tostring(THEM)] = { bar = max - 5, used = 0, turnFill = 0 }
		local result = Fill.shot(ctx(bars, { drops = dropsOf({ 1, 2 }), turnEnds = true }))
		H.expect(barOf(bars, THEM).bar == max, "full")
		H.expect(total(result.gains, THEM) == 5, "only what fits")
		H.expect(#result.gains == 4, "two own balls, the opponent's first, your turn end")
		result =
			Fill.shot(ctx(bars, { drops = dropsOf({ 3, 4, 5, 6, 7 }, { 3 }), turnEnds = true }))
		H.expect(total(result.gains, THEM) == 0 and barOf(bars, THEM).bar == max, "stays full")
		H.expect(barOf(bars, ME).bar <= max, "yours too")
	end,

	["the 8 fills nothing"] = function()
		local Fill = load()
		local bars = {}
		local result = Fill.shot(ctx(bars, {
			ballsBefore = rack({ 1, 2, 3, 4, 5, 6, 7 }),
			drops = dropsOf({ 8 }, { 8 }),
		}))
		H.expect(#result.gains == 0, "no gains")
		result = Fill.shot(ctx(bars, { groupsBefore = {}, drops = dropsOf({ 8 }) }))
		H.expect(#result.gains == 0 and result.run == 0, "not on an open table either")
	end,

	["gains come in drop order with their ball and time, and repeat exactly"] = function()
		local Fill = load()
		local function run(): { any }
			local bars = {}
			return Fill.shot(ctx(bars, { drops = dropsOf({ 2, 10, 4 }, { 4 }), turnEnds = true })).gains
		end
		local a, b = run(), run()
		H.expect(#a == #b, "same count")
		for i, gain in a do
			local other = b[i]
			H.expect(
				gain.userId == other.userId
					and gain.amount == other.amount
					and gain.reason == other.reason,
				"same gains"
			)
		end
		local lastT = 0
		for _, gain in a do
			if gain.t ~= nil then
				H.expect(gain.t >= lastT and gain.ball ~= nil, "chronological, with the ball")
				lastT = gain.t
			else
				H.expect(gain.reason == "Turn" or gain.reason == "OpponentTurn", "turn ends last")
			end
		end
	end,
}
