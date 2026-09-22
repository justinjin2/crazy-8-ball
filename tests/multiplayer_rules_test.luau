--!strict
-- Agreed multiplayer rules, using complete before/after balls and timed event fixtures.

local H = require("./harness")

local function setup()
	local Judge = H.require("Rules.ShotJudge")
	local Ball = H.require("Physics.Ball")
	local balls = {}
	for id = 0, 15 do
		table.insert(balls, Ball.new(id, id * 3 - 20, 0))
	end
	return Judge, Ball, balls
end

local function contact(id: number, t: number?)
	return { t = t or 1, type = "ballHit", ball = 0, other = id, speed = 10 }
end

local function rail(id: number, t: number?)
	return { t = t or 2, type = "railHit", ball = id, speed = 10 }
end

local function pocket(id: number, hole: number?, t: number?)
	return { t = t or 3, type = "pocket", ball = id, other = hole or 1, speed = 10 }
end

local function outcome(balls, events)
	local Ball = H.require("Physics.Ball")
	local after = Ball.cloneList(balls)
	for _, event in events do
		if event.type == "pocket" then
			after[event.ball + 1].pocketed = true
			after[event.ball + 1].pocket = event.other
		end
	end
	return {
		events = events,
		finalBalls = after,
		firstContact = H.require("Physics.Simulation").firstContact(events),
		duration = 4,
		steps = 960,
		capped = false,
	}
end

local function context(group: string?, breakShot: boolean?, call: number?)
	return {
		groups = if group then { group, if group == "solids" then "stripes" else "solids" } else {},
		activeTeam = 1,
		breakShot = breakShot or false,
		calledPocket = call,
	}
end

local function eligible(balls, group: string)
	local Judge = H.require("Rules.ShotJudge")
	for _, ball in balls do
		if Judge.group(ball.id) == group then
			ball.pocketed = true
		end
	end
end

return {
	["group helpers distinguish open table remaining balls and locked eight"] = function()
		local Judge, _, balls = setup()
		H.expect(Judge.group(0) == nil and Judge.group(8) == nil and Judge.group(16) == nil)
		H.expect(
			Judge.group(1.5) == nil and Judge.group(1) == "solids" and Judge.group(15) == "stripes"
		)
		H.expect(Judge.remaining(balls, "solids") == 7 and Judge.remaining(balls, "stripes") == 7)
		H.expect(not Judge.eligible(balls, nil) and not Judge.eligible(balls, "solids"))
		H.expect(Judge.legalTarget(balls, nil, 1) and Judge.legalTarget(balls, nil, 15))
		H.expect(not Judge.legalTarget(balls, nil, 8) and not Judge.legalTarget(balls, nil, 0))
		H.expect(
			not Judge.legalTarget(balls, "solids", 9) and not Judge.legalTarget(balls, "solids", 8)
		)
		eligible(balls, "solids")
		H.expect(Judge.eligible(balls, "solids") and Judge.legalTarget(balls, "solids", 8))
		H.expect(not Judge.legalTarget(balls, "solids", 1), "pocketed balls are not targets")
	end,

	["mixed assignment uses event time then stable event index and preserves input"] = function()
		local Judge, _, balls = setup()
		local ctx = context(nil)
		local shot = outcome(balls, { contact(1), pocket(3, 1, 4), pocket(10, 2, 3) })
		local result = Judge.judge(balls, shot, ctx)
		H.expect(result.groups[1] == "stripes" and result.groups[2] == "solids")
		H.expect(result.pockets[1].ball == 10 and result.pockets[2].ball == 3)
		H.expect(result.retain and not result.foul)
		H.expect(ctx.groups[1] == nil and not balls[11].pocketed, "inputs are unchanged")
		H.expect(shot.events[2].ball == 3, "sorting does not reorder the outcome log")
		local tie = Judge.judge(balls, outcome(balls, { contact(1), pocket(3), pocket(10) }), ctx)
		H.expect(tie.groups[1] == "solids", "equal timestamps preserve simulation ordering")
	end,

	["second team can assign and existing ownership does not change"] = function()
		local Judge, _, balls = setup()
		local ctx = context(nil)
		ctx.activeTeam = 2
		local result = Judge.judge(balls, outcome(balls, { contact(9), pocket(10) }), ctx)
		H.expect(result.groups[2] == "stripes" and result.groups[1] == "solids")
		ctx.groups = result.groups
		result = Judge.judge(balls, outcome(balls, { contact(9), pocket(2) }), ctx)
		H.expect(result.groups[2] == "stripes" and not result.retain)
	end,

	["scratch never assigns groups and overrides a scoring run"] = function()
		local Judge, _, balls = setup()
		for _, group in { false, "solids" } do
			local result = Judge.judge(
				balls,
				outcome(balls, { contact(1), pocket(2), pocket(0) }),
				context(group or nil)
			)
			H.expect(result.foul and result.reason == "Scratch" and not result.retain)
			H.expect(result.groups[1] == (group or nil))
			H.expect(#result.pockets == 2, "balls stay pocketed and audio can inspect ownership")
		end
	end,

	["no contact is a foul even with a pocket or rail"] = function()
		local Judge, _, balls = setup()
		for _, events in { {}, { rail(0) }, { pocket(1) } } do
			local result = Judge.judge(balls, outcome(balls, events), context(nil))
			H.expect(result.foul and result.reason == "NoContact" and result.groups[1] == nil)
		end
	end,

	["open eight and assigned opponent contact are fouls"] = function()
		local Judge, _, balls = setup()
		for _, fixture in
			{ { context(nil), 8 }, { context("solids"), 9 }, { context("solids"), 8 } }
		do
			local result =
				Judge.judge(balls, outcome(balls, { contact(fixture[2]), rail(0) }), fixture[1])
			H.expect(result.foul and result.reason == "WrongContact" and not result.retain)
		end
	end,

	["rail is required after first contact and may be the cue ball rail"] = function()
		local Judge, _, balls = setup()
		local missing = Judge.judge(balls, outcome(balls, { contact(1) }), context("solids"))
		local before =
			Judge.judge(balls, outcome(balls, { rail(0, 0.5), contact(1) }), context("solids"))
		local after = Judge.judge(balls, outcome(balls, { contact(1), rail(0) }), context("solids"))
		H.expect(missing.foul and missing.reason == "NoRail")
		H.expect(before.foul and before.reason == "NoRail")
		H.expect(not after.foul and not after.retain)
	end,

	["same-time contact ordering distinguishes rail before and after"] = function()
		local Judge, _, balls = setup()
		local before =
			Judge.judge(balls, outcome(balls, { rail(0, 1), contact(1, 1) }), context(nil))
		local after =
			Judge.judge(balls, outcome(balls, { contact(1, 1), rail(0, 1) }), context(nil))
		H.expect(before.foul and not after.foul)
	end,

	["only a legal own ball keeps possession after assignment"] = function()
		local Judge, _, balls = setup()
		local own = Judge.judge(balls, outcome(balls, { contact(1), pocket(3) }), context("solids"))
		local other =
			Judge.judge(balls, outcome(balls, { contact(1), pocket(10) }), context("solids"))
		local both = Judge.judge(
			balls,
			outcome(balls, { contact(1), pocket(10), pocket(3) }),
			context("solids")
		)
		H.expect(own.retain and not own.foul)
		H.expect(
			not other.retain and not other.foul,
			"opponent pockets satisfy the rail alternative"
		)
		H.expect(both.retain and not both.foul)
	end,

	["break pockets retain possession without assigning groups"] = function()
		local Judge, _, balls = setup()
		local result =
			Judge.judge(balls, outcome(balls, { contact(1), pocket(9) }), context(nil, true))
		H.expect(
			not result.foul
				and result.retain
				and result.groups[1] == nil
				and result.groups[2] == nil
		)
	end,

	["break requires apex first even if an object ball drops"] = function()
		local Judge, _, balls = setup()
		local result =
			Judge.judge(balls, outcome(balls, { contact(9), pocket(2) }), context(nil, true))
		H.expect(result.foul and result.reason == "IllegalBreak" and not result.retain)
	end,

	["break rail requirement counts four distinct object balls after contact"] = function()
		local Judge, _, balls = setup()
		local legal = { contact(1), rail(1), rail(2), rail(3), rail(4) }
		local duplicate = { contact(1), rail(1), rail(2), rail(3), rail(3), rail(0) }
		local before = { rail(4, 0.5), contact(1), rail(1), rail(2), rail(3) }
		local result = Judge.judge(balls, outcome(balls, legal), context(nil, true))
		H.expect(not result.foul and not result.retain)
		for _, events in { duplicate, before } do
			result = Judge.judge(balls, outcome(balls, events), context(nil, true))
			H.expect(result.foul and result.reason == "IllegalBreak")
		end
	end,

	["eight on legal break respots and retains without winning"] = function()
		local Judge, _, balls = setup()
		local result =
			Judge.judge(balls, outcome(balls, { contact(1), pocket(8) }), context(nil, true))
		H.expect(result.respotEight and result.retain and not result.foul and result.winner == nil)
		H.expect(result.groups[1] == nil)
	end,

	["eight on scratched or illegal break respots but passes possession"] = function()
		local Judge, _, balls = setup()
		for _, events in { { contact(1), pocket(8), pocket(0) }, { contact(8), pocket(8) } } do
			local result = Judge.judge(balls, outcome(balls, events), context(nil, true))
			H.expect(
				result.respotEight and not result.retain and result.foul and result.winner == nil
			)
		end
	end,

	["early eight loses even after legal first contact"] = function()
		local Judge, _, balls = setup()
		local result = Judge.judge(
			balls,
			outcome(balls, { contact(1), pocket(8) }),
			context("solids", false, 1)
		)
		H.expect(result.winner == 2 and result.reason == "EarlyEight" and not result.retain)
	end,

	["clearing final group ball and eight together still loses"] = function()
		local Judge, _, balls = setup()
		eligible(balls, "solids")
		balls[2].pocketed = false
		local result = Judge.judge(
			balls,
			outcome(balls, { contact(1), pocket(1), pocket(8, 1, 4) }),
			context("solids", false, 1)
		)
		H.expect(result.winner == 2 and result.reason == "EarlyEight")
	end,

	["called eligible eight wins and wrong or missing call loses"] = function()
		local Judge, _, balls = setup()
		eligible(balls, "solids")
		local shot = outcome(balls, { contact(8), pocket(8, 3) })
		local good = Judge.judge(balls, shot, context("solids", false, 3))
		H.expect(good.winner == 1 and not good.foul and good.reason == "LegalEight")
		for _, call in { 1, false } do
			local bad = Judge.judge(balls, shot, context("solids", false, call or nil))
			H.expect(bad.winner == 2 and bad.reason == "WrongPocket")
		end
	end,

	["foul with an eligible eight loses but a scratch without eight does not"] = function()
		local Judge, _, balls = setup()
		eligible(balls, "solids")
		local foulEight = Judge.judge(
			balls,
			outcome(balls, { contact(8), pocket(8), pocket(0) }),
			context("solids", false, 1)
		)
		H.expect(foulEight.winner == 2 and foulEight.foul and foulEight.reason == "FoulEight")
		local scratch = Judge.judge(
			balls,
			outcome(balls, { contact(8), pocket(0) }),
			context("solids", false, 1)
		)
		H.expect(scratch.winner == nil and scratch.foul and scratch.reason == "Scratch")
	end,

	["duplicate or already-down pockets cannot assign or award twice"] = function()
		local Judge, _, balls = setup()
		balls[10].pocketed = true
		local result = Judge.judge(
			balls,
			outcome(balls, { contact(1), pocket(9), pocket(3), pocket(3) }),
			context(nil)
		)
		H.expect(
			result.groups[1] == "solids" and #result.pockets == 1 and result.pockets[1].ball == 3
		)
	end,

	["a real deterministic rack break satisfies the agreed rules"] = function()
		local Judge = H.require("Rules.ShotJudge")
		local geometry = H.require("Physics.Table").build()
		local balls = H.require("Physics.Rack").newGame(geometry, 1)
		local Simulation = H.require("Physics.Simulation")
		local shot =
			Simulation.runHeadless(Simulation.newState(geometry, balls), { angle = 0, power = 1 })
		local result = Judge.judge(balls, shot, context(nil, true))
		H.expect(not shot.capped and not result.foul, "a full-power apex break must pass")
		H.expect(result.groups[1] == nil and result.winner == nil)
	end,
}
