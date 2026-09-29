--!strict
-- The ult rules in a match (Ults/Match through Rules/MatchEngine; docs/prompts/ULTIMATES_PROMPT.md
-- section 4): activation, the paused clock, the ult shot's overrides, fouls, the timeout, bars
-- filled by real engine shots, rematches, teams, solo practice, the PC policy and the snapshot.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local Match = H.require("Ults.Match")
local Config = H.require("Config")
local Sim = H.require("Physics.Simulation")
local U = Config.Ults
local expect = H.expect
local tests = {}

local PAUSE = U.CutsceneSeconds + U.ArmDelaySeconds

local function expire(m: any)
	expect(m.deadline ~= nil, "a deadline to expire")
	E.advance(m, m.deadline)
end

-- A pad of `size` a side, started: user team * 10 + slot, 11 hosts and breaks.
local function playing(size: number): any
	local m = E.new(1, size)
	for slot = 1, size do
		for team = 1, 2 do
			local user = team * 10 + slot
			expect(E.join(m, user, tostring(user), tostring(user), slot - 1))
		end
	end
	local request = { kind = "Start", epoch = m.epoch, turnId = m.turnId }
	expect(E.action(m, m.hostId, request, m.phaseStartedAt, 1))
	expire(m) -- the coin
	expect(m.phase == "Intro" and m.shooter == 11 and m.breakShot)
	return m
end

-- Past the break: solids (team 1) and stripes (team 2), 11 aiming on the shot clock. The
-- difficulty is Difficult (x1.0) unless `classic`, so the gains are the plain numbers.
local function midGame(size: number, classic: boolean?): any
	local m = playing(size)
	m.settings.difficulty = if classic then "Classic" else "Difficult"
	m.breakShot, m.ballInHand = false, false
	m.groups = { "solids", "stripes" }
	expire(m) -- the introduction
	expect(m.phase == "Aiming" and m.deadline ~= nil and m.shooter == 11)
	return m
end

local function payload(m: any, angle: number, power: number): any
	return {
		tableId = m.id,
		epoch = m.epoch,
		turnId = m.turnId,
		angle = angle,
		power = power,
	}
end

-- Every other ball on the table stays where the rack put it (the foot end), clear of these.
-- Ball `id` sits in front of the +y side pocket with the cue ball behind it: a soft straight
-- shot drops it and leaves the cue ball up.
local function potShot(m: any, id: number): any
	local ball = Sim.findBall(m.state, id)
	local cue = Sim.findBall(m.state, 0)
	ball.x, ball.y, ball.pocketed = 0, m.state.geometry.halfWidth - 5, false
	cue.x, cue.y, cue.pocketed = 0, ball.y - 8, false
	return payload(m, math.pi / 2, 0.12)
end

-- Ball `id` mid-table at the head end with the cue ball behind it: a soft hit that drops
-- nothing (a legal miss on a casual table).
local function missShot(m: any, id: number): any
	local ball = Sim.findBall(m.state, id)
	local cue = Sim.findBall(m.state, 0)
	ball.x, ball.y, ball.pocketed = -15, 0, false
	cue.x, cue.y, cue.pocketed = -7, 0, false
	return payload(m, math.pi, 0.06)
end

-- The cue ball alone in front of the +y side pocket, shot straight in: a scratch.
local function scratchShot(m: any): any
	local cue = Sim.findBall(m.state, 0)
	cue.x, cue.y = 0, m.state.geometry.halfWidth - 6
	return payload(m, math.pi / 2, 0.12)
end

local function shoot(m: any, p: any, now: number?): (any, string?)
	return E.acceptShot(m, m.shooter, p, now or m.phaseStartedAt)
end

-- Shoot and resolve; the shot must be accepted.
local function play(m: any, p: any): any
	local wire, why = shoot(m, p)
	expect(wire ~= nil, "shot accepted: " .. tostring(why))
	expire(m)
	return wire
end

local function bar(m: any, user: number): any
	return m.ults.bars[tostring(user)] or { bar = 0, used = 0, turnFill = 0 }
end

local function full(m: any, user: number)
	expect(Match.setBar(m, user, U.BarMax), "bar set")
end

-- Activate and let the cutscene and the wait run out: the ult is armed.
local function armNow(m: any, user: number, id: string?)
	local now = m.phaseStartedAt
	local ok, why = Match.activate(m, user, id or "Magnet", now)
	expect(ok, "activation: " .. tostring(why))
	E.advance(m, now + PAUSE)
	expect(m.ults.armed.stage == "Armed")
end

local function sidePocket(m: any): number
	for _, p in m.state.geometry.pockets do
		if p.x == 0 and p.y > 0 then
			return p.id
		end
	end
	error("no +y side pocket")
end

local function sameList(a: { number }, b: { number }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

function tests.activation_is_refused_off_turn_on_the_break_and_with_a_bar_under_100()
	local m = playing(1)
	full(m, 11)
	full(m, 21)
	local ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Break", "never on the break")
	ok, why = Match.activate(m, 21, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "NotYourTurn", "not the shooter")
	expect(bar(m, 11).bar == 100 and bar(m, 11).used == 0, "a refusal spends nothing")

	m = midGame(1)
	expect(Match.setBar(m, 11, 99))
	ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "NotReady", "99 is not full")
	full(m, 21)
	ok, why = Match.activate(m, 21, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "NotYourTurn", "a full bar still waits for its own turn")
	-- Mid-shot: the balls are rolling.
	shoot(m, missShot(m, 3))
	expect(m.phase == "Resolving")
	full(m, 11)
	ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Moving", "not while the balls roll")
end

function tests.activation_is_allowed_with_ball_in_hand_and_refused_after_the_deadline()
	local m = playing(1)
	m.settings.difficulty = "Difficult"
	m.breakShot = false
	m.groups = { "solids", "stripes" }
	expire(m) -- the introduction: ball in hand
	expect(m.phase == "Placement" and m.ballInHand)
	full(m, 11)
	local deadline = m.deadline
	local ok, why = Match.activate(m, 11, "Magnet", deadline)
	expect(not ok and why == "NotYourTurn", "the clock already ran out")
	ok = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(ok and m.deadline == deadline + PAUSE, "ball in hand is fine, and its clock pauses")
end

function tests.an_armed_ult_is_refused_again_and_a_third_is_refused()
	local m = midGame(1)
	full(m, 11)
	local ok = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(ok and bar(m, 11).used == 1 and bar(m, 11).bar == 0, "spent at once")
	full(m, 11)
	local why
	ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Armed", "one at a time")
	E.advance(m, m.phaseStartedAt + PAUSE)
	play(m, potShot(m, 3)) -- the first ult shot; 11 keeps the table
	expect(m.phase == "Aiming" and m.shooter == 11 and m.ults.armed == nil)
	full(m, 11)
	armNow(m, 11)
	expect(bar(m, 11).used == 2)
	play(m, potShot(m, 4))
	expect(m.shooter == 11 and m.phase == "Aiming")
	full(m, 11)
	expect(bar(m, 11).bar == 0, "after the second ult the bar stays empty")
	m.ults.bars["11"].bar = 100
	ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Used", "at most two a match")
end

function tests.ults_off_refuses_and_solo_practises_for_free()
	local m = midGame(1)
	m.settings.abilities = false
	expect(not Match.setBar(m, 11, 100), "setBar only works with ults on")
	m.ults.bars["11"] = { bar = 100, used = 0, turnFill = 0 }
	local ok, why = Match.activate(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Off")
	local view = E.snapshot(m).ults
	expect(view.on == false and next(view.bars) == nil and view.armed == nil)
	ok, why = Match.practice(m, 11, "Magnet", m.phaseStartedAt)
	expect(not ok and why == "Off", "practice is solo's")
	play(m, potShot(m, 3))
	expect(#m.ultFeed == 0, "no fill with ults off")

	-- Solo: no bar, a free practice ult any number of times.
	local s = E.new(2, 1)
	expect(E.join(s, 11, "s", "s", 0))
	expect(E.action(s, 11, { kind = "StartSolo", epoch = s.epoch, turnId = s.turnId }, 0))
	s.breakShot, s.ballInHand = false, false
	expire(s)
	expect(s.phase == "Aiming" and s.deadline == nil)
	ok, why = Match.activate(s, 11, "Magnet", s.phaseStartedAt)
	expect(not ok and why == "Off", "solo has no bar")
	for round = 1, 3 do
		ok, why = Match.practice(s, 11, "Magnet", s.phaseStartedAt)
		expect(ok, "practice " .. round .. ": " .. tostring(why))
		expect(s.ults.armed.practice and s.ults.armed.seq == round)
		local refused, reason = shoot(s, potShot(s, round))
		expect(refused == nil and reason == "UltArming", "the cutscene first")
		E.advance(s, s.phaseStartedAt + PAUSE)
		local wire = play(s, potShot(s, round))
		expect(wire.ult ~= nil and wire.ult.practice == true and wire.ult.by == 11)
		expect(wire.overrides ~= nil and wire.overrides.Effect == "Magnet")
		expect(s.ults.armed == nil and next(s.ults.bars) == nil and #s.ultFeed == 0)
		expect(s.phase == "Aiming" and s.shooter == 11)
	end
	local view2 = E.snapshot(s).ults
	expect(view2.on == false and next(view2.bars) == nil)
end

function tests.the_clock_pauses_for_the_cutscene_and_resumes()
	local m = midGame(1)
	full(m, 11)
	local now = m.phaseStartedAt + 3
	local deadline = m.deadline
	local revision = m.revision
	expect(Match.activate(m, 11, "Magnet", now))
	expect(m.revision > revision, "a change everyone sees")
	expect(m.deadline == deadline + PAUSE, "the deadline moved by the pause")
	expect(m.ults.pausedUntil == now + PAUSE)
	local view = E.snapshot(m).ults
	expect(view.pausedUntil == now + PAUSE and view.armed.stage == "Arming")
	expect(view.armed.at == now and view.armed.readyAt == now + PAUSE and view.armed.seq == 1)
	-- A shot during the cutscene is refused, and changes nothing.
	local wire, why = shoot(m, potShot(m, 3), now + 1)
	expect(wire == nil and why == "UltArming" and m.phase == "Aiming")
	-- The old deadline passes during the pause: no timeout.
	E.advance(m, deadline + 0.01)
	expect(m.phase == "Aiming" and m.ults.armed ~= nil)
	E.advance(m, now + PAUSE)
	expect(m.ults.armed.stage == "Armed" and m.ults.pausedUntil == nil)
	expect(E.snapshot(m).ults.pausedUntil == nil and m.deadline == deadline + PAUSE)
	-- The clock runs again: its (moved) end is still a timeout.
	E.advance(m, m.deadline)
	expect(m.phase == "Foul" and m.foul.reason == "Timeout")
end

function tests.the_ult_shot_targets_the_shooters_own_group_only()
	local m = midGame(1)
	Sim.findBall(m.state, 5).pocketed = true
	full(m, 11)
	armNow(m, 11)
	local wire = play(m, potShot(m, 3))
	expect(wire.ult ~= nil and wire.ult.id == "Magnet" and wire.ult.by == 11)
	expect(wire.ult.practice == false)
	local o = wire.overrides
	expect(o ~= nil and o.Effect == "Magnet" and o.EightPocket == nil)
	expect(sameList(o.Targets, { 1, 2, 3, 4, 6, 7 }), "solids still up, never 0, 8 or stripes")
	expect(m.ults.armed == nil, "the shot spent it")
	expect(E.snapshot(m).ults.armed == nil)
	-- The next shot is a normal one.
	local next = play(m, potShot(m, 4))
	expect(next.ult == nil and (next.overrides == nil or next.overrides.Effect == nil))

	-- An open table: any ball but the 8.
	m = midGame(1)
	m.groups = {}
	full(m, 11)
	armNow(m, 11)
	wire = play(m, potShot(m, 3))
	expect(
		sameList(wire.overrides.Targets, { 1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15 }),
		"open table: every ball but the 8 and the cue ball"
	)
end

function tests.the_eight_is_a_target_only_on_the_legal_eight_shot()
	local m = midGame(1)
	for id = 1, 7 do
		Sim.findBall(m.state, id).pocketed = true
	end
	-- The call first (the 8 is on), then the ult.
	m.phase = "PocketChoice"
	local pocket = sidePocket(m)
	local call = { kind = "Pocket", pocket = pocket, epoch = m.epoch, turnId = m.turnId }
	expect(E.action(m, 11, call, m.phaseStartedAt))
	expect(m.phase == "Aiming" and m.calledPocket == pocket)
	full(m, 11)
	armNow(m, 11)
	local wire = shoot(m, potShot(m, 8))
	expect(wire ~= nil)
	expect(sameList(wire.overrides.Targets, { 8 }) and wire.overrides.EightPocket == pocket)
	-- With solids still up the 8 is never one.
	m = midGame(1)
	full(m, 11)
	armNow(m, 11)
	wire = shoot(m, potShot(m, 2))
	expect(not table.find(wire.overrides.Targets, 8) and wire.overrides.EightPocket == nil)
end

function tests.fouls_still_count_on_an_ult_shot()
	local m = midGame(1)
	full(m, 11)
	armNow(m, 11)
	table.clear(m.ultFeed)
	local wire = play(m, scratchShot(m))
	expect(wire.ult ~= nil, "it was the ult shot")
	expect(m.phase == "Foul" and m.foul.reason == "Scratch", "a scratch is still a foul")
	for _, g in m.ultFeed do
		expect(g.userId ~= 11, "a foul's turn end gives the shooter nothing")
	end
	expect(m.ults.armed == nil and bar(m, 11).used == 1)
	expire(m)
	expect(m.shooter == 21 and m.ballInHand, "ball in hand for the other side")
end

function tests.the_shot_clock_running_out_while_armed_spends_it()
	local m = midGame(1)
	full(m, 11)
	armNow(m, 11)
	table.clear(m.ultFeed)
	E.advance(m, m.deadline)
	expect(m.phase == "Foul" and m.foul.reason == "Timeout")
	expect(m.ults.armed == nil and bar(m, 11).used == 1 and bar(m, 11).bar == 0, "spent")
	expect(#m.ultFeed == 1 and m.ultFeed[1].userId == 21 and m.ultFeed[1].reason == "OpponentTurn")
	expect(m.ultFeed[1].amount == U.Fill.OppTurn and m.ultFeed[1].at == m.phaseStartedAt)
	-- A death or a departure with an armed ult spends it too.
	m = midGame(1)
	full(m, 11)
	armNow(m, 11)
	E.death(m, 11, m.phaseStartedAt + PAUSE + 1)
	expect(m.phase == "Foul" and m.ults.armed == nil)
	m = midGame(1)
	full(m, 11)
	expect(Match.activate(m, 11, "Magnet", m.phaseStartedAt))
	E.remove(m, 11, m.phaseStartedAt + 1)
	expect(m.ults.armed == nil and m.ults.pausedUntil == nil, "cleared when the game ends")
end

function tests.four_opponent_balls_and_a_miss_fill_the_other_bar_by_their_turn()
	local m = midGame(1, true) -- Classic, x1.3
	local shots = {}
	for _, id in { 1, 2, 3, 4 } do
		table.clear(m.ultFeed)
		local wire = play(m, potShot(m, id))
		expect(m.shooter == 11 and m.phase == "Aiming", "11 keeps the table")
		table.insert(shots, { wire = wire, feed = table.clone(m.ultFeed) })
	end
	-- 11's own run: 10, 8, 6, 5 x1.3 = 13, 10, 8, 7. 21's: 8 + 7 per ball behind (15, 22, 29,
	-- 36) x1.3 = 20, 29, 38, 47, cut at 100.
	expect(bar(m, 11).bar == 38, "own run " .. bar(m, 11).bar)
	expect(bar(m, 21).bar == 100, "the opponent's bar is full")
	-- Gains land with the drop times, in the feed.
	local first = shots[1]
	expect(#first.feed == 2, "one for each bar")
	local own, opp = first.feed[1], first.feed[2]
	expect(own.userId == 11 and own.reason == "Own" and own.amount == 13 and own.ball == 1)
	expect(opp.userId == 21 and opp.reason == "Opponent" and opp.amount == 20 and opp.ball == 1)
	expect(own.at > first.wire.startedAt and own.at == opp.at, "at the ball's drop")
	expect(own.at < first.wire.startedAt + first.wire.duration + 0.001)
	expect(own.seq == opp.seq, "one message")
	-- The miss: 11's legal turn end (+15 x1.3 = 20); 21 is full already.
	table.clear(m.ultFeed)
	local miss = shoot(m, missShot(m, 5))
	expect(miss ~= nil and m.pending.judgement.foul == nil, "a legal miss")
	expect(#m.ultFeed == 1 and m.ultFeed[1].userId == 11 and m.ultFeed[1].reason == "Turn")
	expect(m.ultFeed[1].amount == 20 and m.ultFeed[1].at == miss.startedAt)
	expire(m)
	expect(m.shooter == 21, "21's turn")
	local view = E.snapshot(m).ults
	expect(view.bars["21"].bar == 100 and view.bars["21"].ready, "full at the start of the turn")
	expect(view.bars["11"].bar == 58 and not view.bars["11"].ready)
	expect(m.ults.run == 0, "the run ended with the turn")
	expect(Match.activate(m, 21, "Magnet", m.phaseStartedAt))
end

function tests.an_ult_shot_fills_nothing_for_its_user()
	local m = midGame(1)
	full(m, 11)
	armNow(m, 11)
	table.clear(m.ultFeed)
	play(m, potShot(m, 3))
	expect(#m.ultFeed == 1 and m.ultFeed[1].userId == 21 and m.ultFeed[1].reason == "Opponent")
	expect(bar(m, 11).bar == 0 and m.ults.run == 1, "nothing for the user; the run still counts")
end

function tests.a_rematch_and_a_new_game_reset_the_bars()
	local m = midGame(1)
	full(m, 11)
	expect(Match.setBar(m, 21, 40))
	expect(E.action(m, 21, { kind = "Surrender", epoch = m.epoch, turnId = m.turnId }, 10))
	expect(m.phase == "Result" and m.rematch ~= nil)
	for _, user in { 11, 21 } do
		expect(E.action(m, user, { kind = "Rematch", epoch = m.epoch, turnId = m.turnId }, 11))
	end
	E.advance(m, 12)
	expect(m.phase == "Intro" and m.epoch == 2)
	expect(next(m.ults.bars) == nil and m.ults.seq == 0 and #m.ultFeed == 0, "fresh")
	local view = E.snapshot(m).ults
	expect(view.on and view.bars["11"].bar == 0 and view.bars["21"].bar == 0)
	-- A game that ends with no rematch frees the table with fresh ults too.
	full(m, 11)
	expect(E.action(m, 21, { kind = "Surrender", epoch = m.epoch, turnId = m.turnId }, 20))
	expect(E.action(m, 21, { kind = "Decline", epoch = m.epoch, turnId = m.turnId }, 21))
	E.advance(m, 21)
	expect(m.phase == "Waiting" and m.ults ~= nil and next(m.ults.bars) == nil)
	expect(m.ultFeed ~= nil and #m.ultFeed == 0)
end

function tests.teams_a_teammates_ball_gives_two_and_each_player_has_a_bar()
	local m = midGame(2)
	expect(m.shooter == 11)
	table.clear(m.ultFeed)
	play(m, potShot(m, 3))
	local by = {}
	for _, g in m.ultFeed do
		by[g.userId] = g
	end
	expect(by[11].reason == "Own" and by[11].amount == U.Fill.Own[1])
	expect(by[12].reason == "Teammate" and by[12].amount == U.Fill.Teammate, "+2")
	local opp = U.Fill.OppBase + U.Fill.OppPerBehind
	expect(by[21].reason == "Opponent" and by[21].amount == opp)
	expect(by[22].reason == "Opponent" and by[22].amount == opp, "behind compares sides")
	local view = E.snapshot(m).ults
	for _, user in { "11", "12", "21", "22" } do
		expect(view.bars[user] ~= nil, "a bar for " .. user)
	end
end

function tests.the_pc_uses_its_ult_when_behind_or_with_no_easy_shot()
	local m = midGame(1)
	expect(not Match.pcShouldActivate(m, 11, false), "an empty bar never")
	full(m, 11)
	expect(not Match.pcShouldActivate(m, 11, true), "level with an easy shot: hold it")
	expect(Match.pcShouldActivate(m, 11, false), "no easy shot: use it")
	Sim.findBall(m.state, 9).pocketed = true -- stripes lead: 11 is behind
	expect(Match.pcShouldActivate(m, 11, true), "behind: use it")
	full(m, 21)
	expect(not Match.pcShouldActivate(m, 21, false), "not its turn")
	expect(Match.activate(m, 11, "Magnet", m.phaseStartedAt))
	expect(not Match.pcShouldActivate(m, 11, false), "already armed")
	local b = playing(1)
	full(b, 11)
	expect(not Match.pcShouldActivate(b, 11, false), "never on the break")
end

function tests.the_snapshot_carries_the_ults_contract()
	local m = midGame(1)
	expect(Match.setBar(m, 11, 100))
	expect(Match.setBar(m, 21, 37))
	local view = E.snapshot(m).ults
	expect(view.on == true and view.armed == nil and view.pausedUntil == nil)
	local a, b = view.bars["11"], view.bars["21"]
	expect(a.bar == 100 and a.used == 0 and a.ready == true)
	expect(b.bar == 37 and b.used == 0 and b.ready == false)
	expect(a.turnFill == nil, "only bar, used and ready")
	local now = m.phaseStartedAt
	expect(Match.activate(m, 11, "Magnet", now))
	view = E.snapshot(m).ults
	local armed = view.armed
	expect(armed.by == 11 and armed.id == "Magnet" and armed.stage == "Arming")
	expect(armed.at == now and armed.readyAt == now + PAUSE and armed.seq == 1)
	expect(armed.practice == false and view.pausedUntil == now + PAUSE)
	expect(view.bars["11"].bar == 0 and view.bars["11"].used == 1 and not view.bars["11"].ready)
	expect(armed ~= m.ults.armed, "a copy")
end

function tests.a_placeholder_arms_and_does_nothing()
	local m = midGame(1)
	full(m, 11)
	armNow(m, 11, "EaglesEye")
	expect(m.ults.armed.id == "EaglesEye")
	local wire = play(m, potShot(m, 3))
	expect(wire.ult ~= nil and wire.ult.id == "EaglesEye")
	expect(wire.overrides == nil or wire.overrides.Effect == nil, "no effect")
	expect(m.ults.armed == nil and bar(m, 11).used == 1)
	-- An unknown id plays as the default.
	m = midGame(1)
	full(m, 11)
	expect(Match.activate(m, 11, "NoSuchUlt", m.phaseStartedAt))
	expect(m.ults.armed.id == U.Default)
end

function tests.dev_arm_skips_the_cutscene_wait()
	local m = midGame(1)
	local deadline = m.deadline
	expect(Match.devArm(m, 11, "Magnet", m.phaseStartedAt))
	expect(m.ults.armed.stage == "Armed" and m.ults.pausedUntil == nil)
	expect(m.deadline == deadline and bar(m, 11).used == 1)
	local wire = shoot(m, potShot(m, 3))
	expect(wire ~= nil and wire.ult ~= nil)
end

function tests.the_same_shots_give_the_same_gains()
	local function run(): { any }
		local m = midGame(1, true)
		local out = {}
		for _, id in { 1, 2 } do
			play(m, potShot(m, id))
			for _, g in m.ultFeed do
				table.insert(out, g)
			end
			table.clear(m.ultFeed)
		end
		return out
	end
	local a, b = run(), run()
	expect(#a == #b and #a > 0)
	for i = 1, #a do
		expect(a[i].userId == b[i].userId and a[i].amount == b[i].amount and a[i].at == b[i].at)
	end
end

return tests
