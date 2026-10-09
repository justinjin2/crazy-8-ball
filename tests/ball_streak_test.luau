--!strict
-- The ball streak (Rules/Streak; designer, 2026-10-09): which balls count, the break's x1, two
-- balls in one shot, fouls and the turn passing, and the engine carrying each shot's steps to
-- every client in the ShotResult.
local H = require("./harness")
local Streak = H.require("Rules.Streak")
local E = H.require("Rules.MatchEngine")
local Ball = H.require("Physics.Ball")
local Sim = H.require("Physics.Simulation")
local expect = H.expect
local tests = {}

local function drops(...: number): { { ball: number, index: number, t: number } }
	local out = {}
	for i, ball in { ... } do
		table.insert(out, { ball = ball, index = i * 2, t = i * 0.5 })
	end
	return out
end

-- Team 1 on solids after the colours are decided, mid-turn, no foul.
local function ctx(over: any?): any
	local c: any = {
		foul = false,
		breakShot = false,
		groupsBefore = { "solids", "stripes" },
		groupsAfter = { "solids", "stripes" },
		team = 1,
		solo = false,
	}
	for k, v in over or {} do
		c[k] = v
	end
	return c
end

local function levels(steps: { any }): string
	local out = {}
	for _, s in steps do
		table.insert(out, ("%d:%d"):format(s.ball, s.level))
	end
	return table.concat(out, " ")
end

function tests.the_break_is_x1_however_many_drop()
	local state, steps = Streak.step(
		nil,
		drops(3, 12, 5),
		ctx({ breakShot = true, groupsBefore = {}, groupsAfter = {} })
	)
	expect(state ~= nil and state.team == 1 and state.count == 1, "three on the break is still x1")
	expect(levels(steps) == "3:1 12:1 5:1", levels(steps))
	-- A leftover streak from somewhere never carries into a break.
	local again = Streak.step(
		{ team = 1, count = 5 },
		drops(3),
		ctx({ breakShot = true, groupsBefore = {}, groupsAfter = {} })
	)
	expect(again ~= nil and again.count == 1)
end

function tests.each_later_ball_steps_up_and_two_in_one_shot_step_twice()
	local state, steps = Streak.step({ team = 1, count = 1 }, drops(2), ctx())
	expect(state ~= nil and state.count == 2 and levels(steps) == "2:2")
	state, steps = Streak.step(state, drops(4, 6), ctx())
	expect(state ~= nil and state.count == 4, "two in one shot step twice")
	expect(levels(steps) == "4:3 6:4", levels(steps))
end

function tests.a_foul_ends_it_and_its_ball_does_not_raise_it()
	local state, steps = Streak.step({ team = 1, count = 4 }, drops(2), ctx({ foul = true }))
	expect(state == nil and #steps == 0, "a foul that pots your ball ends the streak (designer)")
end

function tests.a_shot_with_no_counted_ball_ends_it()
	local state, steps = Streak.step({ team = 1, count = 3 }, drops(), ctx())
	expect(state == nil and #steps == 0, "a miss")
	state, steps = Streak.step({ team = 1, count = 3 }, drops(11, 13), ctx())
	expect(state == nil and #steps == 0, "only the other group's balls")
	-- Mixed: the opponent's ball is skipped, the own ball steps.
	state, steps = Streak.step({ team = 1, count = 3 }, drops(11, 1), ctx())
	expect(state ~= nil and state.count == 4 and levels(steps) == "1:4", levels(steps))
end

function tests.the_eight_counts_only_when_it_wins()
	local state, steps =
		Streak.step({ team = 1, count = 7 }, drops(8), ctx({ reason = "LegalEight", winner = 1 }))
	expect(
		state ~= nil and state.count == 8 and levels(steps) == "8:8",
		"the run-out's last ball is x8"
	)
	state, steps =
		Streak.step({ team = 1, count = 3 }, drops(8), ctx({ reason = "EarlyEight", winner = 2 }))
	expect(state == nil and #steps == 0)
end

function tests.the_open_table_pick_counts()
	local state, steps = Streak.step(
		nil,
		drops(11),
		ctx({ groupsBefore = {}, groupsAfter = { "stripes", "solids" } })
	)
	expect(state ~= nil and state.count == 1 and levels(steps) == "11:1")
	-- A table still open after the shot (an early 8 on an open table) counts nothing.
	state =
		Streak.step({ team = 1, count = 1 }, drops(3), ctx({ groupsBefore = {}, groupsAfter = {} }))
	expect(state == nil)
end

function tests.solo_counts_both_groups_and_can_pass_x8()
	local state: any = { team = 1, count = 8 }
	local steps
	state, steps = Streak.step(state, drops(9, 10), ctx({ solo = true }))
	expect(state ~= nil and state.count == 10 and levels(steps) == "9:9 10:10", levels(steps))
end

function tests.another_team_starts_from_nothing()
	local state = Streak.step({ team = 2, count = 6 }, drops(1), ctx())
	expect(state ~= nil and state.team == 1 and state.count == 1)
end

-- The engine ----------------------------------------------------------------------------

local function queue(size: number): any
	local m = E.new(1, size)
	for slot = 1, size do
		for team = 1, 2 do
			local user = team * 10 + slot
			expect(E.join(m, user, tostring(user), tostring(user), slot - 1))
		end
	end
	return m
end
local function expire(m: any)
	expect(m.deadline ~= nil)
	E.advance(m, m.deadline)
end
local function playing(size: number): any
	local m = queue(size)
	expect(
		E.action(
			m,
			m.hostId,
			{ kind = "Start", epoch = m.epoch, turnId = m.turnId },
			m.phaseStartedAt,
			1
		)
	)
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 11)
	return m
end
-- Ball `id` lined up for the +y side pocket, the cue ball straight behind it (the engine
-- tests' sidePocketShot): a soft straight shot drops it.
local function sidePocketShot(m: any, id: number): any
	local ball = Sim.findBall(m.state, id)
	local cue = Sim.findBall(m.state, 0)
	ball.x, ball.y = 0, m.state.geometry.halfWidth - 5
	cue.x, cue.y = 0, ball.y - 8
	return {
		tableId = m.id,
		epoch = m.epoch,
		turnId = m.turnId,
		angle = math.pi / 2,
		power = 0.2,
	}
end
local function resolveFixture(m: any, keep: boolean, foul: string?)
	m.pending = {
		outcome = { finalBalls = Ball.cloneList(m.state.balls), events = {} },
		judgement = { groups = m.groups, keep = keep, foul = foul, pockets = {} },
	}
	m.phase = "Resolving"
	m.deadline = m.phaseStartedAt + 1
	expire(m)
end

function tests.an_accepted_shot_carries_its_steps_to_every_client()
	local m = playing(1)
	expect(m.streak == nil, "a fresh game has no streak")
	-- The break drops the apex: x1.
	local wire = E.acceptShot(m, 11, sidePocketShot(m, 1), m.phaseStartedAt)
	expect(wire ~= nil and wire.streakAfter == 1 and #wire.streaks == 1)
	local step = wire.streaks[1]
	local ev = m.pending.outcome.events[step.index]
	expect(
		step.ball == 1 and step.level == 1 and ev.type == "pocket" and ev.ball == 1,
		"index is the drop's event"
	)
	expect(E.snapshot(m).shot.streaks[1].level == 1, "the snapshot carries it too")
	expire(m) -- resolve: the breaker keeps the table
	expect(m.shooter == 11 and m.streak ~= nil and m.streak.count == 1)
	-- The next ball picks the colours and steps to x2.
	while m.phase ~= "Aiming" do
		expire(m)
	end
	wire = E.acceptShot(m, 11, sidePocketShot(m, 3), m.phaseStartedAt)
	expect(wire ~= nil and wire.assign ~= nil and wire.streakAfter == 2)
	expect(wire.streaks[1].ball == 3 and wire.streaks[1].level == 2)
end

function tests.the_turn_passing_and_any_foul_end_it()
	local m = playing(1)
	m.breakShot = false
	m.streak = { team = 1, count = 4 }
	resolveFixture(m, false, nil) -- a miss: the table passes
	expect(m.shooter == 21 and m.streak == nil)
	m.streak = { team = 2, count = 3 }
	resolveFixture(m, false, "Scratch")
	expect(m.phase == "Foul" and m.streak == nil, "a judged foul")
	expire(m)
	m.streak = { team = 1, count = 2 }
	while not E.isShotClock(m.phase, m.breakShot) do
		expire(m)
	end
	expire(m) -- the shot clock runs out: a Timeout foul
	expect(m.phase == "Foul" and m.foul.reason == "Timeout" and m.streak == nil)
end

function tests.teammates_carry_the_team_streak()
	local m = playing(2)
	m.breakShot = false
	m.streak = { team = 1, count = 2 }
	resolveFixture(m, true, nil) -- the team keeps the table; the shooter rotates
	expect(m.shooter == 12 and m.streak ~= nil and m.streak.team == 1 and m.streak.count == 2)
end

function tests.the_next_game_starts_without_one()
	local m = playing(1)
	m.streak = { team = 1, count = 5 }
	m.phase, m.deadline = "Result", m.phaseStartedAt + 1
	expire(m)
	expect(m.phase == "Waiting" and m.streak == nil)
end

return tests
