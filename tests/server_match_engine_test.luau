--!strict
-- Acceptance regressions against the exact pure engine used by TableService/ShotService.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local M = H.require("Config").Multiplayer
local Ball = H.require("Physics.Ball")
local Sim = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local TableGeometry = H.require("Physics.Table")
local expect = H.expect
local tests = {}
local function queue(size: number, id: number?): any
	local m = E.new(id or 1, size)
	for slot = 1, size do
		for team = 1, 2 do
			local user = team * 10 + slot
			expect(E.join(m, user, tostring(user), tostring(user), team, slot, slot - 1))
		end
	end
	return m
end
local function expire(m: any)
	expect(m.deadline ~= nil)
	E.advance(m, m.deadline, 1)
end
local function playing(size: number, id: number?): any
	local m = queue(size, id)
	expire(m)
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 11)
	return m
end
local function aim(m: any)
	while
		m.phase == "Intro"
		or m.phase == "Placement"
		or m.phase == "PocketChoice"
		or m.phase == "Foul"
	do
		expire(m)
	end
	expect(m.phase == "Aiming")
end
local function request(m: any, kind: string, extra: any?): any
	local action = extra or {}
	action.kind, action.tableId, action.epoch, action.turnId = kind, m.id, m.epoch, m.turnId
	return action
end
local function action(m: any, user: number, kind: string, extra: any?, timestamp: number?): boolean
	return E.action(m, user, request(m, kind, extra), timestamp or m.phaseStartedAt)
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
local function shotPayload(m: any, extra: any?): any
	local payload = extra or {}
	payload.tableId, payload.epoch, payload.turnId = m.id, m.epoch, m.turnId
	payload.angle, payload.power = 0, 0.05
	return payload
end
-- Line `id` up for the +y side pocket with the cue ball straight behind it; a soft straight
-- shot (angle pi/2, power 0.12) drops it and leaves the cue ball on the table.
local function sidePocketShot(m: any, id: number): any
	local ball = Sim.findBall(m.state, id)
	local cue = Sim.findBall(m.state, 0)
	ball.x, ball.y = 0, m.state.geometry.halfWidth - 5
	cue.x, cue.y = 0, ball.y - 8
	local payload = shotPayload(m)
	payload.angle, payload.power = math.pi / 2, 0.12
	return payload
end
-- A synthetic outcome for the pure judge, as the rules tests build them.
local function fakeOutcome(m: any, events: { any }): any
	return {
		events = events,
		finalBalls = Ball.cloneList(m.state.balls),
		firstContact = Sim.firstContact(events),
		duration = 4,
		steps = 960,
		capped = false,
	}
end
function tests.balls_that_flew_off_are_respotted_and_the_cue_ball_comes_back_in_hand()
	local m = playing(1)
	for _, id in { 0, 5 } do
		local b = Sim.findBall(m.state, id)
		b.pocketed, b.offTable = true, true
	end
	m.pending = {
		outcome = { finalBalls = Ball.cloneList(m.state.balls), events = {} },
		judgement = {
			groups = m.groups,
			keep = false,
			foul = "OffTable",
			pockets = {},
			respot = { 5 },
		},
	}
	m.phase = "Resolving"
	m.deadline = m.phaseStartedAt + 1
	expire(m)
	local five = Sim.findBall(m.state, 5)
	local fx = TableGeometry.footSpot(m.state.geometry)
	expect(not five.pocketed and not five.offTable, "the ball is back on the table")
	expect(math.abs(five.x - fx) < 30, "near the foot spot")
	expect(m.phase == "Foul" and m.foul.reason == "OffTable")
	expire(m)
	local cue = Sim.findBall(m.state, 0)
	expect(not cue.pocketed and not cue.offTable and m.ballInHand, "cue ball back, in hand")
end
function tests.queue_reassigns_host_cancels_and_restarts_countdown()
	local m = queue(2)
	expect(m.hostId == 11 and m.phase == "Countdown")
	local stale = m.deadline
	expect(E.remove(m, 11, 2))
	expect(m.hostId == 21 and m.phase == "Waiting" and m.deadline == nil)
	E.advance(m, stale, 1)
	expect(m.phase == "Waiting")
	expect(E.join(m, 14, "14", "14", 1, 1, 10))
	expect(m.deadline == 10 + M.CountdownSeconds)
	expire(m)
	expect(m.phase == "CoinFlip" and m.coin.headsTeam == 2 and m.coin.breaker == 12)
end
function tests.rejects_duplicate_seats_occupied_slots_and_active_match_rejoins()
	local m = queue(2)
	expect(not E.join(m, 11, "x", "x", 1, 2, 5))
	expect(not E.join(m, 99, "x", "x", 2, 2, 5))
	expect(not E.join(m, 99, "x", "x", 3, 1, 5))
	expect(not E.join(m, 99, "x", "x", 1, 0, 5))
	expire(m)
	expect(not E.join(m, 99, "x", "x", 1, 1, 10))
end
function tests.every_mode_rotates_after_each_shot_and_keeps_independent_team_cursor()
	for size = 1, 3 do
		local m = playing(size)
		resolveFixture(m, true, nil)
		expect(m.shooter == (if size == 1 then 11 else 12))
		expect(m.phase == (if size == 1 then "Aiming" else "Intro"))
		resolveFixture(m, false, nil)
		expect(m.shooter == 21)
		resolveFixture(m, false, nil)
		expect(m.shooter == (if size == 3 then 13 else 11))
	end
end
function tests.foul_intro_placement_then_aim_without_confirm()
	local m = playing(3)
	resolveFixture(m, true, "Scratch")
	expect(m.phase == "Foul" and m.foul.by == 11 and m.foul.team == 1)
	expect(not action(m, 11, "Place", { x = -30, y = 3 }), "the fouler cannot place")
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 21 and m.ballInHand)
	expect(action(m, 21, "Place", { x = -30, y = 3 }), "the introduction already allows placing")
	expire(m)
	expect(m.phase == "Placement")
	expect(action(m, 21, "Place", { x = -32, y = -4 }))
	expect(not action(m, 21, "ConfirmPlacement"), "there is no lock button")
	expect(m.phase == "Placement" and m.ballInHand)
	expire(m)
	local cue = Sim.findBall(m.state, 0)
	expect(m.phase == "Aiming" and not m.ballInHand and m.timeouts[2] == 0)
	expect(cue.x == -32 and cue.y == -4, "the ball stays at the last placed spot")
	H.near(m.deadline - m.phaseStartedAt, M.ShotSeconds, 1e-9, "aiming clock")
	expect(not action(m, 21, "Place", { x = -30, y = 0 }), "locked once the window closes")
end
function tests.setup_deadlines_autocomplete_without_shooting_timeout()
	local m = playing(1)
	expire(m)
	expect(m.phase == "Placement")
	expire(m)
	expect(m.phase == "Aiming" and m.timeouts[1] == 0)
	expect(m.deadline - m.phaseStartedAt == M.ShotSeconds)
end
function tests.eligible_ball_in_hand_calls_before_placement()
	local m = playing(2)
	m.groups = { "solids", "stripes" }
	for _, ball in m.state.balls do
		if ball.id >= 9 then
			ball.pocketed = true
		end
	end
	resolveFixture(m, false, "Scratch")
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 21 and m.ballInHand)
	local early, why = E.acceptShot(m, 21, shotPayload(m), m.phaseStartedAt)
	expect(early == nil and why == "CallRequired")
	expect(not action(m, 21, "Place", { x = -30, y = 3 }), "the call comes first")
	expire(m)
	expect(m.phase == "PocketChoice")
	local now = m.phaseStartedAt + 1
	expect(not action(m, 11, "Pocket", { pocket = 1 }, now))
	expect(action(m, 21, "Pocket", { pocket = 2 }, now))
	expect(m.phase == "Placement" and m.ballInHand and m.calledPocket == 2)
	expect(m.deadline == now + M.PlacementSeconds)
	local deadline = m.deadline
	expect(action(m, 21, "Place", { x = -30, y = 3 }, now))
	expect(not action(m, 21, "Pocket", { pocket = 3 }, now + 1), "the call is final")
	expect(m.phase == "Placement" and m.calledPocket == 2 and m.deadline == deadline)
	local wire = E.acceptShot(m, 21, shotPayload(m, { cueX = -28, cueY = 2 }), now + 1)
	expect(wire ~= nil and wire.start[1] == -28 and wire.start[2] == 2)
end
function tests.call_timeout_chooses_pocket_nearest_eight()
	local m = playing(1)
	m.groups = { "solids", "stripes" }
	for _, ball in m.state.balls do
		if ball.id >= 1 and ball.id <= 7 then
			ball.pocketed = true
		end
	end
	local eight = Sim.findBall(m.state, 8)
	local pocket = m.state.geometry.pockets[6]
	eight.x, eight.y = pocket.x + 2, pocket.y + 2
	expire(m)
	expect(m.phase == "PocketChoice" and m.ballInHand)
	expire(m)
	expect(m.calledPocket == pocket.id and m.phase == "Placement" and m.ballInHand)
	expire(m)
	expect(m.phase == "Aiming" and not m.ballInHand and m.calledPocket == pocket.id)
end
function tests.pocket_choice_then_placement_timeouts_chain_without_shooting_timeout()
	local m = playing(1)
	m.groups = { "solids", "stripes" }
	for _, ball in m.state.balls do
		if ball.id >= 1 and ball.id <= 7 then
			ball.pocketed = true
		end
	end
	expire(m)
	expect(m.phase == "PocketChoice")
	H.near(m.deadline - m.phaseStartedAt, M.PocketChoiceSeconds, 1e-9, "call window")
	expire(m)
	expect(m.phase == "Placement" and m.timeouts[1] == 0)
	H.near(m.deadline - m.phaseStartedAt, M.PlacementSeconds, 1e-9, "placement window")
	expire(m)
	expect(m.phase == "Aiming")
	H.near(m.deadline - m.phaseStartedAt, M.ShotSeconds, 1e-9, "aiming clock")
	expect(m.timeouts[1] == 0 and m.calledPocket ~= nil)
end
function tests.placement_open_truth_table()
	local phases = {
		"Waiting",
		"Countdown",
		"CoinFlip",
		"Intro",
		"Placement",
		"PocketChoice",
		"Aiming",
		"Resolving",
		"Foul",
		"Result",
	}
	for _, name in phases do
		for _, hand in { true, false } do
			for _, call in { true, false } do
				local open = hand and (name == "Placement" or (name == "Intro" and not call))
				expect(
					E.placementOpen(name, hand, call) == open,
					("%s hand=%s call=%s"):format(name, tostring(hand), tostring(call))
				)
			end
		end
		expect(not E.placementOpen(name, nil, false), "no ball in hand, no placing")
	end
	expect(not E.placementOpen("Foul", true, false), "the fouler never places")
end
-- The helper TableService.constrain and the watchers share must lock exactly what constrain
-- locks today: a shooter outside Waiting, Countdown and Result, except in a Foul that is not
-- solo. The one phase the two are written differently for is the coin flip, where constrain
-- would lock the shooter but the engine never has one; that is checked on real tables.
function tests.shooter_locked_matches_the_server_lock()
	local phases = {
		"Waiting",
		"Countdown",
		"CoinFlip",
		"Intro",
		"Placement",
		"PocketChoice",
		"Aiming",
		"Resolving",
		"Foul",
		"Result",
	}
	-- TableService.constrain's rule, transcribed, for the table's shooter.
	local function constrainLocks(name: string, solo: any): boolean
		if name == "Waiting" or name == "Countdown" or name == "Result" then
			return false
		end
		return name ~= "Foul" or solo ~= nil
	end
	-- A flag rather than { nil, solo }: iterating a table skips a nil, so that loop would never
	-- try the table without a solo record.
	local tried = 0
	for _, name in phases do
		for _, isSolo in { false, true } do
			local solo = if isSolo then { team = 1 } else nil
			if name ~= "CoinFlip" then
				tried += 1
				expect(
					E.shooterLocked(name, solo) == constrainLocks(name, solo),
					("%s solo=%s"):format(name, tostring(isSolo))
				)
			end
		end
	end
	expect(tried == 2 * (#phases - 1), "every phase, with and without a solo record")
	expect(not E.shooterLocked("Foul", nil), "a 1v1 fouler is released: the turn passes")
	expect(E.shooterLocked("Foul", { team = 1 }), "a solo fouler keeps the table")
	expect(not E.shooterLocked("CoinFlip", nil), "nobody to lock during the coin flip")
	-- The coin flip really has no shooter: a first game, and a game after a Result.
	local m = queue(1)
	expire(m)
	expect(m.phase == "CoinFlip" and m.shooter == nil, "a first coin flip")
	expire(m)
	expect(m.phase == "Intro" and m.shooter ~= nil, "the shooter arrives with the intro")
	expect(action(m, 11, "Surrender"))
	expire(m)
	expect(E.join(m, 11, "a", "a", 1, 1, m.phaseStartedAt))
	expect(E.join(m, 21, "b", "b", 2, 1, m.phaseStartedAt))
	expire(m)
	expect(m.phase == "CoinFlip" and m.shooter == nil, "the next game's coin flip")
end
local function move(m: any, user: number, seq: any, x: number, y: number, now: number?): boolean
	local request = { epoch = m.epoch, turnId = m.turnId, seq = seq, x = x, y = y }
	return E.moveCue(m, user, request, now or m.phaseStartedAt)
end
function tests.stream_move_updates_without_revision_and_rejects_stale_seq()
	local m = playing(1)
	expire(m)
	expect(m.phase == "Placement" and m.breakShot)
	local X = M.BreakLineX
	local cue = Sim.findBall(m.state, 0)
	local revision = m.revision
	expect(move(m, 11, 1, X, 3))
	expect(cue.y == 3 and m.revision == revision, "the stream never forces a snapshot")
	expect(not move(m, 11, 1, X, 4) and cue.y == 3, "a repeated seq is dropped")
	expect(move(m, 11, 3, X, 5))
	expect(not move(m, 11, 2, X, 6) and cue.y == 5, "a late packet cannot drag the ball back")
	expect(not move(m, 11, 3.5, X, 6) and not move(m, 11, 0 / 0, X, 6))
	expect(not move(m, 21, 4, X, 6), "only the shooter")
	expect(
		not E.moveCue(m, 11, { epoch = m.epoch, turnId = m.turnId - 1, seq = 4, x = X, y = 6 }, 0)
	)
	expect(not E.moveCue(m, 11, { epoch = m.epoch, turnId = m.turnId, x = X, y = 6 }, 0))
	local object = Sim.findBall(m.state, 2)
	object.x, object.y = X, 12
	local checksum = Sim.checksum(m.state.balls)
	expect(not move(m, 11, 4, X, 12), "an overlap is rejected")
	expect(not move(m, 11, 4, X + 1, 0), "off the head string is rejected")
	expect(Sim.checksum(m.state.balls) == checksum and m.placeSeq == 3)
	expect(not action(m, 11, "Place", { x = X, y = 1, seq = 3 }), "Place shares the counter")
	expect(action(m, 11, "Place", { x = X, y = 1 }), "a Place without seq is judged alone")
	expect(action(m, 11, "Place", { x = X, y = 2, seq = 4 }) and m.placeSeq == 4)
	expect(m.revision > revision and cue.y == 2)
	expect(E.snapshot(m).placeSeq == nil)
end
function tests.moves_after_placement_deadline_rejected_before_advance()
	local m = playing(1)
	expire(m)
	local X, deadline = M.BreakLineX, m.deadline
	expect(not move(m, 11, 1, X, 3, deadline))
	expect(not action(m, 11, "Place", { x = X, y = 3 }, deadline))
	expect(m.phase == "Placement" and Sim.findBall(m.state, 0).y ~= 3)
	expect(move(m, 11, 1, X, 3, deadline - 0.01))
end
function tests.late_shot_repeating_locked_spot_is_accepted_moved_spot_is_not()
	local m = playing(1)
	expire(m)
	local X = M.BreakLineX
	expect(action(m, 11, "Place", { x = X, y = 4, seq = 1 }))
	expire(m)
	expect(m.phase == "Aiming" and not m.ballInHand)
	local now = m.phaseStartedAt
	local moved, why = E.acceptShot(m, 11, shotPayload(m, { cueX = X, cueY = 6 }), now)
	expect(moved == nil and why == "InvalidPlacement")
	expect(E.acceptShot(m, 11, shotPayload(m, { cueX = X }), now) == nil)
	expect(E.acceptShot(m, 11, shotPayload(m, { cueX = X, cueY = 0 / 0 }), now) == nil)
	local echo = 4 + M.PlacementEchoEpsilonInches / 2
	local wire = E.acceptShot(m, 11, shotPayload(m, { cueX = X, cueY = echo }), now)
	expect(wire ~= nil and wire.start[1] == X and wire.start[2] == 4, "the locked spot is used")
end
function tests.resolved_drag_spots_are_always_accepted_by_place()
	local P = H.require("Rules.CuePlacement")
	local m = playing(1)
	expire(m)
	local g = m.state.geometry
	local seq = 0
	-- Break first, then ordinary ball in hand after a foul; a 7-inch sweep past every rail.
	for _, isBreak in { true, false } do
		if not isBreak then
			resolveFixture(m, true, "Scratch")
			expire(m)
			expire(m)
			expect(m.phase == "Placement" and not m.breakShot)
			seq = 0
		end
		local cue = Sim.findBall(m.state, 0)
		for wy = -g.halfWidth - 7, g.halfWidth + 7, 7 do
			for wx = -g.halfLength - 7, g.halfLength + 7, 7 do
				local x, y = P.resolve(m.state, wx, wy, m.breakShot, cue.x, cue.y)
				seq += 1
				expect(
					action(m, m.shooter, "Place", { x = x, y = y, seq = seq }),
					("Place refused a resolved spot for %.1f, %.1f"):format(wx, wy)
				)
				expect(cue.x == x and cue.y == y)
			end
		end
	end
end
function tests.placement_seq_resets_each_turn()
	local m = playing(1)
	expire(m)
	expect(action(m, 11, "Place", { x = M.BreakLineX, y = 4, seq = 5 }) and m.placeSeq == 5)
	resolveFixture(m, true, "Scratch")
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 21 and m.placeSeq == 0)
	expect(action(m, 21, "Place", { x = -30, y = 3, seq = 1 }))
end
function tests.two_team_timeouts_forfeit_but_accepted_shot_clears_streak()
	local m = playing(2)
	aim(m)
	expire(m)
	expect(m.phase == "Foul" and m.timeouts[1] == 1)
	aim(m)
	resolveFixture(m, false, nil)
	aim(m)
	expire(m)
	expect(m.phase == "Result" and m.result.winner == 2 and m.result.reason == "Timeouts")
	local n = playing(2)
	aim(n)
	expire(n)
	aim(n)
	resolveFixture(n, false, nil)
	aim(n)
	local wire = E.acceptShot(n, n.shooter, shotPayload(n), n.phaseStartedAt)
	expect(wire ~= nil and n.timeouts[1] == 0)
end
function tests.accepted_shot_has_complete_wire_state_and_cannot_repeat()
	local m = playing(1)
	local payload = shotPayload(m)
	local wire = E.acceptShot(m, 11, payload, m.phaseStartedAt)
	expect(wire ~= nil and m.phase == "Resolving" and not m.ballInHand)
	expect(
		#wire.start == 64
			and #wire.final == 64
			and wire.epoch == m.epoch
			and wire.seq == 1
			and wire.turnId == m.turnId
	)
	expect(wire.seed.vx ~= nil and wire.checksum ~= nil)
	local duplicate = E.acceptShot(m, 11, payload, m.phaseStartedAt)
	expect(duplicate == nil and m.shotSeq == 1)
	local snapshot = E.snapshot(m)
	expect(snapshot.shot.seq == wire.seq and snapshot.balls[1] == wire.start[1])
	E.advance(m, m.deadline - 0.01, 2)
	expect(m.phase == "Resolving" and m.timeouts[1] == 0)
	expire(m)
	expect(m.phase == "Foul" and m.shot == nil)
end
function tests.stale_versions_wrong_shooter_and_invalid_atomic_placement_do_not_mutate()
	local m = playing(2)
	local checksum = Sim.checksum(m.state.balls)
	local payload = shotPayload(m)
	payload.epoch -= 1
	expect(E.acceptShot(m, 11, payload, m.phaseStartedAt) == nil)
	payload.epoch = m.epoch
	payload.turnId -= 1
	expect(E.acceptShot(m, 11, payload, m.phaseStartedAt) == nil)
	payload.turnId = m.turnId
	expect(E.acceptShot(m, 12, payload, m.phaseStartedAt) == nil)
	payload.cueX, payload.cueY = 1000, 1000
	expect(E.acceptShot(m, 11, payload, m.phaseStartedAt) == nil)
	expect(Sim.checksum(m.state.balls) == checksum and m.shotSeq == 0)
	expect(not action(m, 12, "Place", { x = M.BreakLineX, y = 5 }))
	expect(not action(m, 11, "Place", { x = 0 / 0, y = 5 }))
end
function tests.atomic_break_placement_uses_same_replay_start_without_preaccepted_mutation()
	local m = playing(1)
	local payload = shotPayload(m, { cueX = M.BreakLineX, cueY = 5 })
	local wire = E.acceptShot(m, 11, payload, m.phaseStartedAt)
	expect(wire ~= nil and wire.start[1] == M.BreakLineX and wire.start[2] == 5)
	expect(m.state.balls[1].y == 5)
end
function tests.surrender_unanimous_reject_no_cooldown_expiry_and_opponent_vote()
	local m = playing(3)
	local now = m.phaseStartedAt
	local deadline = m.deadline
	expect(action(m, 11, "Surrender", nil, now))
	expect(m.deadline == deadline)
	expect(not action(m, 21, "Vote", { yes = true }, now))
	expect(action(m, 12, "Vote", { yes = false }, now))
	expect(m.vote == nil and not action(m, 11, "Surrender", nil, now + 1))
	expect(action(m, 11, "Surrender", nil, now + M.VoteCooldownSeconds))
	E.advance(m, now + M.VoteCooldownSeconds + M.VoteSeconds, 1)
	expect(m.vote == nil and m.phase ~= "Result")
	local later = now + 2 * M.VoteCooldownSeconds
	expect(action(m, 11, "Surrender", nil, later))
	expect(action(m, 12, "Vote", { yes = true }, later))
	expect(m.phase ~= "Result")
	expect(action(m, 13, "Vote", { yes = true }, later))
	expect(m.phase == "Result" and m.result.winner == 2)
end
function tests.one_on_one_surrender_resets_rack_epoch_and_releases_all_seats()
	local m = playing(1)
	local seed, epoch = m.rackSeed, m.epoch
	expect(action(m, 11, "Surrender"))
	expect(m.phase == "Result" and m.result.winner == 2)
	expire(m)
	expect(
		m.phase == "Waiting" and #m.seats == 0 and m.epoch == epoch + 1 and m.rackSeed == seed + 1
	)
	expect(m.turnId == 0 and m.vote == nil and m.shot == nil and m.pending == nil)
	expect(E.join(m, 11, "again", "again", 1, 1, m.phaseStartedAt))
	expect(E.join(m, 21, "again", "again", 2, 1, m.phaseStartedAt))
	expect(m.phase == "Countdown")
end
function tests.disconnect_shorthanded_rotation_skips_absent_and_empty_team_forfeits()
	local m = playing(3)
	expect(E.remove(m, 11, m.phaseStartedAt))
	expect(m.phase == "Foul")
	expect(not E.remove(m, 11, m.phaseStartedAt))
	expire(m)
	resolveFixture(m, false, nil)
	expect(m.shooter == 12)
	E.remove(m, 13, m.phaseStartedAt)
	E.remove(m, 12, m.phaseStartedAt)
	expect(m.phase == "Result" and m.result.winner == 2)
end
function tests.departed_shooter_accepted_shot_continues_to_resolution()
	local m = playing(3)
	local wire = E.acceptShot(m, 11, shotPayload(m), m.phaseStartedAt)
	expect(wire ~= nil)
	E.remove(m, 11, m.phaseStartedAt + 0.1)
	expect(m.phase == "Resolving")
	expire(m)
	expect(m.phase == "Foul" and m.foul.reason ~= "Departure")
	expire(m)
	expect(m.shooter == 21)
end
function tests.reset_retains_seat_and_duplicate_death_fouls_only_once()
	local m = playing(2)
	E.death(m, 11, m.phaseStartedAt)
	expect(m.phase == "Foul" and E.seat(m, 11) ~= nil and E.count(m) == 4)
	local revision = m.revision
	E.death(m, 11, m.phaseStartedAt)
	expect(m.revision == revision)
	expire(m)
	E.acceptShot(m, 21, shotPayload(m), m.phaseStartedAt)
	E.death(m, 21, m.phaseStartedAt + 0.01)
	expect(m.phase == "Resolving")
end
function tests.three_simultaneous_tables_preserve_state_replay_and_lifecycle_independently()
	local a, b, c = playing(1, 1), playing(2, 2), playing(3, 3)
	local aStart = Sim.checksum(a.state.balls)
	local cStart = Sim.checksum(c.state.balls)
	local deadline = c.deadline
	E.acceptShot(b, 11, shotPayload(b), b.phaseStartedAt)
	expect(b.phase == "Resolving" and a.phase == "Intro" and c.phase == "Intro")
	expect(
		Sim.checksum(a.state.balls) == aStart
			and Sim.checksum(c.state.balls) == cStart
			and c.deadline == deadline
	)
	expect(action(a, 11, "Surrender"))
	expect(a.phase == "Result" and b.phase == "Resolving" and c.phase == "Intro")
	expect(E.count(a) == 2 and E.count(b) == 4 and E.count(c) == 6)
end
function tests.complete_synthetic_eight_games_every_mode_release_and_allow_table_reuse()
	for size = 1, 3 do
		local m = playing(size)
		m.groups = { "solids", "stripes" }
		m.breakShot = false
		for _, b in m.state.balls do
			if b.id ~= 0 and b.id ~= 8 then
				b.pocketed = true
			end
		end
		local eight = Sim.findBall(m.state, 8)
		local cue = Sim.findBall(m.state, 0)
		cue.x, cue.y = -10, 0
		eight.x, eight.y = 0, m.state.geometry.halfWidth - 5
		m.ballInHand = false
		expire(m)
		expect(m.phase == "PocketChoice")
		local pocket = nil
		for _, p in m.state.geometry.pockets do
			if p.x == 0 and p.y > 0 then
				pocket = p.id
			end
		end
		expect(pocket ~= nil and action(m, 11, "Pocket", { pocket = pocket }))
		-- The fixture controls position only; real strike, collision, pocket and rule
		-- resolution determine the winner, exercising production engine end to end.
		cue.x, cue.y = 0, eight.y - 8
		local payload = shotPayload(m)
		payload.angle, payload.power = math.pi / 2, 0.12
		local wire = E.acceptShot(m, 11, payload, m.phaseStartedAt)
		expect(wire ~= nil)
		-- The winner's bonus is decided at acceptance, timed to the eight's drop.
		expect(#m.feedback == 1, "winning eight should award one bonus")
		local f = m.feedback[1]
		local ev = m.pending.outcome.events[f.index]
		expect(f.ball == 8 and f.team == 1 and f.seq == wire.seq)
		expect(ev.type == "pocket" and ev.ball == 8 and f.at == wire.startedAt + ev.t)
		expire(m)
		expect(
			m.phase == "Result" and m.result.winner == 1,
			"legal called eight should win mode " .. size
		)
		expect(#m.feedback == 1, "resolution adds no second bonus")
		expire(m)
		expect(m.phase == "Waiting" and E.count(m) == 0 and not Sim.findBall(m.state, 8).pocketed)
	end
end
function tests.assignment_shot_awards_at_acceptance_not_resolution()
	local m = playing(1)
	m.breakShot, m.ballInHand = false, false
	expire(m)
	expect(m.phase == "Aiming" and m.groups[1] == nil)
	local payload = sidePocketShot(m, 3)
	local wire = E.acceptShot(m, 11, payload, m.phaseStartedAt)
	expect(wire ~= nil and wire.assign ~= nil and wire.assign.ball == 3)
	expect(wire.assign.groups[1] == "solids" and wire.assign.groups[2] == "stripes")
	local ev = m.pending.outcome.events[wire.assign.index]
	expect(ev.type == "pocket" and ev.ball == 3, "assign.index is the drop's event index")
	-- The snapshot keeps the open table until resolution; only the replay reveals early.
	local snapshot = E.snapshot(m)
	expect(snapshot.groups[1] == nil and snapshot.groups[2] == nil)
	expect(snapshot.shot.assign.index == wire.assign.index)
	expect(#m.feedback == 1, "the assigning ball earns its bonus at acceptance")
	local f = m.feedback[1]
	expect(f.team == 1 and f.ball == 3 and f.seq == wire.seq and f.index == wire.assign.index)
	expect(f.id == ("%d:%d:%d:%d"):format(m.id, m.epoch, wire.seq, wire.assign.index))
	expect(f.at == wire.startedAt + ev.t)
	table.clear(m.feedback)
	expire(m)
	expect(#m.feedback == 0, "resolution never grants the assignment bonus again")
	expect(m.groups[1] == "solids" and m.groups[2] == "stripes")
end
function tests.legal_break_pocket_neither_assigns_nor_awards()
	local m = playing(1)
	expect(m.breakShot)
	-- The apex drops on the break: a legal break that keeps the table open.
	local wire = E.acceptShot(m, 11, sidePocketShot(m, 1), m.phaseStartedAt)
	expect(wire ~= nil and wire.assign == nil and #m.feedback == 0)
	local dropped = false
	for _, ev in m.pending.outcome.events do
		dropped = dropped or (ev.type == "pocket" and ev.ball == 1)
	end
	expect(dropped and m.pending.judgement.foul == nil and m.pending.judgement.keep)
	expect(E.snapshot(m).shot.assign == nil)
	expire(m)
	expect(m.groups[1] == nil and m.groups[2] == nil and #m.feedback == 0 and m.shooter == 11)
end
function tests.awards_use_post_assignment_groups_for_both_teams()
	local m = playing(1)
	m.shotSeq = 4
	E.awards(m, {
		groups = { "stripes", "solids" },
		drops = {
			{ ball = 10, index = 5, t = 1.5 },
			{ ball = 2, index = 7, t = 2 },
			{ ball = 8, index = 9, t = 2.5 },
		},
	}, 100)
	expect(#m.feedback == 2, "each ball goes to its owners; an unwon eight to nobody")
	local a, b = m.feedback[1], m.feedback[2]
	expect(a.team == 1 and a.ball == 10 and a.at == 101.5 and a.seq == 4 and a.index == 5)
	expect(a.id == ("%d:%d:4:5"):format(m.id, m.epoch))
	expect(b.team == 2 and b.ball == 2 and b.at == 102 and b.index == 7)
	table.clear(m.feedback)
	E.awards(m, {
		groups = { "solids", "stripes" },
		reason = "LegalEight",
		winner = 2,
		drops = { { ball = 8, index = 3, t = 1 } },
	}, 100)
	expect(#m.feedback == 1 and m.feedback[1].team == 2 and m.feedback[1].ball == 8)
end
function tests.open_table_fouls_award_nothing()
	local m = playing(1)
	local contact = { t = 1, type = "ballHit", ball = 0, other = 1, speed = 10 }
	local function drop(id: number, t: number): any
		return { t = t, type = "pocket", ball = id, other = 1, speed = 10 }
	end
	for _, events in
		{
			{ contact, drop(2, 2), drop(0, 3) }, -- scratch
			{ contact, drop(1, 2), drop(8, 3) }, -- early eight
			{ drop(9, 2) }, -- no contact
		}
	do
		local j = Judge.resolve(m.state.balls, fakeOutcome(m, events), {}, 1, false, nil)
		expect(j.assign == nil and j.groups[1] == nil and #j.drops > 0)
		E.awards(m, j, 0)
		expect(#m.feedback == 0)
	end
end
function tests.resolution_never_emits_feedback()
	local m = playing(1)
	m.breakShot = false
	local drop = { t = 0.5, type = "pocket", ball = 3, other = 1, speed = 10 }
	m.pending = {
		outcome = { finalBalls = Ball.cloneList(m.state.balls), events = { drop } },
		judgement = {
			groups = { "solids", "stripes" },
			assign = { ball = 3, index = 1 },
			keep = true,
			pockets = { 3 },
			drops = { { ball = 3, index = 1, t = 0.5 } },
		},
	}
	m.phase = "Resolving"
	m.deadline = m.phaseStartedAt + 1
	expire(m)
	expect(#m.feedback == 0 and m.groups[1] == "solids")
end
function tests.each_game_racks_from_the_seed_the_server_supplies()
	local m = E.new(1, 1, 123456)
	expect(m.rackSeed == 123456, "the server's seed opens the first game")
	expect(E.snapshot(m).rackSeed == 123456, "clients rebuild the rack from the snapshot's seed")
	local function finish(nextSeed: number?)
		for team = 1, 2 do
			if not E.seat(m, team * 10 + 1) then
				expect(E.join(m, team * 10 + 1, "p", "p", team, 1, m.phaseStartedAt))
			end
		end
		expire(m) -- countdown
		expire(m) -- coin
		expect(action(m, 11, "Surrender"))
		expect(m.phase == "Result")
		E.advance(m, m.deadline, 1, nextSeed)
	end
	finish(987654)
	expect(m.phase == "Waiting" and m.rackSeed == 987654, "the next game takes a fresh seed")
	local other = E.new(1, 1, 987655)
	local moved = false
	for i, b in m.state.balls do
		local o = other.state.balls[i]
		if b.x ~= o.x or b.y ~= o.y then
			moved = true
		end
	end
	expect(moved, "a different seed gives a different rack")
	finish(nil)
	expect(
		m.rackSeed == 987655,
		"without a supplied seed the engine still advances deterministically"
	)
end

-- Solo: player `side * 10 + 1` stands alone in slot 1 of their side and presses Play Solo.
local function solo(size: number, side: number?): any
	local team = side or 1
	local m = E.new(1, size)
	local user = team * 10 + 1
	expect(E.join(m, user, "solo", "solo", team, 1, 0))
	expect(action(m, user, "StartSolo"))
	return m
end
-- Leave the solo break behind: an open table with the cue ball placed, aiming, no clock.
local function soloAiming(m: any)
	m.breakShot, m.ballInHand = false, false
	expire(m) -- the introduction is the only timed phase before a shot
	expect(m.phase == "Aiming" and m.deadline == nil)
end
local function sidePocket(m: any): number
	for _, p in m.state.geometry.pockets do
		if p.x == 0 and p.y > 0 then
			return p.id
		end
	end
	error("no +y side pocket")
end
local function pocketAll(m: any, first: number, last: number)
	for _, b in m.state.balls do
		if b.id >= first and b.id <= last then
			b.pocketed = true
		end
	end
end
-- Resolve a shot judged by the real ShotJudge from synthetic events.
local function judged(m: any, events: { any })
	local before = Ball.cloneList(m.state.balls)
	local outcome = fakeOutcome(m, events)
	for _, ev in events do
		if ev.type == "pocket" then
			outcome.finalBalls[ev.ball + 1].pocketed = true
		end
	end
	local j = Judge.resolve(before, outcome, m.groups, m.activeTeam, m.breakShot, m.calledPocket)
	m.pending = { outcome = outcome, judgement = j }
	m.phase = "Resolving"
	m.deadline = m.phaseStartedAt + 1
	expire(m)
end
function tests.solo_starts_only_for_a_lone_seated_player_in_waiting()
	local m = E.new(1, 2)
	expect(E.join(m, 11, "a", "a", 1, 1, 0) and E.join(m, 21, "b", "b", 2, 1, 0))
	expect(not action(m, 11, "StartSolo"), "two seats: no solo")
	expect(E.remove(m, 21, 1))
	expect(not action(m, 99, "StartSolo"), "only a seated player")
	expect(not E.action(m, 11, { kind = "StartSolo", epoch = m.epoch + 1, turnId = m.turnId }, 1))
	expect(action(m, 11, "StartSolo") and m.solo.team == 1 and m.solo.first == nil)
	expect(m.phase == "Intro" and m.shooter == 11 and m.breakShot and m.ballInHand)
	expect(m.coin == nil and m.activeTeam == 1)
	expect(not action(m, 11, "StartSolo"), "already playing")
	expect(not E.join(m, 21, "b", "b", 2, 1, 2), "nobody joins a solo game")
	expect(not E.join(m, 12, "c", "c", 1, 2, 2))
	local snapshot = E.snapshot(m)
	expect(snapshot.solo.team == 1 and snapshot.solo ~= m.solo, "the snapshot has a copy")
	local full = queue(1)
	expect(full.phase == "Countdown" and not action(full, 11, "StartSolo"), "not in countdown")
end
function tests.solo_has_no_clock_and_fouls_return_ball_in_hand_to_the_player()
	local m = solo(1)
	expect(m.deadline == m.phaseStartedAt + M.IntroSeconds, "the break opens with YOUR TURN")
	expire(m)
	expect(m.phase == "Placement" and m.deadline == nil)
	E.advance(m, 1e9, 1)
	expect(m.phase == "Placement", "no placement clock")
	resolveFixture(m, false, "IllegalBreak")
	expect(m.phase == "Foul" and m.foul.by == 11 and m.nextTeam == 1)
	expect(m.deadline == m.phaseStartedAt + M.FoulSeconds, "the foul notice still moves on")
	local turn = m.turnId
	expire(m)
	expect(m.phase == "Placement" and m.shooter == 11 and m.ballInHand and not m.breakShot)
	expect(m.deadline == nil and m.turnId == turn + 1, "no introduction after the break")
	expect(action(m, 11, "Place", { x = -30, y = 3 }))
	resolveFixture(m, false, nil)
	expect(m.phase == "Aiming" and m.shooter == 11 and m.deadline == nil, "a miss keeps the table")
	E.advance(m, 1e9, 1)
	expect(m.phase == "Aiming" and m.timeouts[1] == 0, "no shooting clock")
	E.death(m, 11, 1e9)
	expect(m.phase == "Foul")
	expire(m)
	expect(m.phase == "Placement" and m.shooter == 11, "a reset is an ordinary solo foul")
end
function tests.solo_plays_first_group_then_the_other_then_the_eight()
	local m = solo(1)
	soloAiming(m)
	local wire = E.acceptShot(m, 11, sidePocketShot(m, 3), m.phaseStartedAt)
	expect(wire ~= nil and wire.assign ~= nil and wire.assign.ball == 3)
	expect(wire.assign.groups[1] == "solids" and wire.assign.groups[2] == "stripes")
	expect(#m.feedback == 1 and m.feedback[1].team == 1 and m.feedback[1].ball == 3)
	expire(m)
	expect(m.solo.first == "solids" and m.groups[1] == "solids" and m.groups[2] == "stripes")
	expect(m.phase == "Aiming" and m.shooter == 11 and m.deadline == nil)
	-- The last solid drops: stripes are next and the 8 stays locked.
	pocketAll(m, 1, 6)
	table.clear(m.feedback)
	wire = E.acceptShot(m, 11, sidePocketShot(m, 7), m.phaseStartedAt)
	expect(wire ~= nil and wire.assign == nil and #m.feedback == 1 and m.feedback[1].team == 1)
	expire(m)
	expect(m.solo.first == "solids" and m.groups[1] == "stripes" and m.groups[2] == "solids")
	expect(m.phase == "Aiming" and m.calledPocket == nil)
	expect(not Judge.legalTarget(m.state.balls, m.groups[1], 8), "the 8 waits for the stripes")
	expect(not Judge.legalTarget(m.state.balls, m.groups[1], 2), "solids are done")
	-- Every group ball is the solo player's bonus, even the other group's.
	table.clear(m.feedback)
	E.awards(m, {
		groups = m.groups,
		drops = { { ball = 10, index = 1, t = 1 }, { ball = 2, index = 2, t = 2 } },
	}, 0)
	expect(#m.feedback == 2 and m.feedback[1].team == 1 and m.feedback[2].team == 1)
	-- All fourteen down: the call, with no clock, then the 8 wins.
	pocketAll(m, 9, 15)
	resolveFixture(m, false, nil)
	expect(m.groups[1] == "stripes" and m.phase == "PocketChoice" and m.deadline == nil)
	E.advance(m, 1e9, 1)
	expect(m.phase == "PocketChoice" and m.calledPocket == nil, "no call timeout")
	expect(action(m, 11, "Pocket", { pocket = sidePocket(m) }))
	expect(m.phase == "Aiming" and m.deadline == nil)
	table.clear(m.feedback)
	wire = E.acceptShot(m, 11, sidePocketShot(m, 8), m.phaseStartedAt)
	expect(wire ~= nil and #m.feedback == 1 and m.feedback[1].ball == 8)
	expire(m)
	expect(m.phase == "Result" and m.result.winner == 1 and m.result.reason == "LegalEight")
	expire(m)
	expect(m.phase == "Waiting" and m.solo == nil and E.snapshot(m).solo == nil and #m.seats == 0)
end
function tests.solo_loses_on_early_foul_or_wrong_pocket_eights()
	local contact = { t = 1, type = "ballHit", ball = 0, other = 10, speed = 10 }
	local function drop(id: number, t: number, pocket: number?): any
		return { t = t, type = "pocket", ball = id, other = pocket or 1, speed = 10 }
	end
	-- Early: stripes first, the 8 drops with stripes still up.
	local m = solo(1)
	soloAiming(m)
	m.solo.first, m.groups = "stripes", { "stripes", "solids" }
	judged(m, { contact, drop(10, 2), drop(8, 3) })
	expect(m.phase == "Result" and m.result.winner == 2 and m.result.reason == "EarlyEight")
	-- Early even with the first group cleared: the second group must go too.
	m = solo(1)
	soloAiming(m)
	pocketAll(m, 9, 15)
	m.solo.first, m.groups = "stripes", { "solids", "stripes" }
	contact = { t = 1, type = "ballHit", ball = 0, other = 1, speed = 10 }
	judged(m, { contact, drop(1, 2), drop(8, 3) })
	expect(m.phase == "Result" and m.result.winner == 2 and m.result.reason == "EarlyEight")
	-- A foul on the 8, and the 8 in a pocket that was not called.
	for _, case in { "FoulEight", "WrongPocket" } do
		m = solo(1)
		soloAiming(m)
		pocketAll(m, 1, 15)
		Sim.findBall(m.state, 8).pocketed = false
		resolveFixture(m, false, nil)
		expect(m.phase == "PocketChoice")
		expect(action(m, 11, "Pocket", { pocket = 3 }))
		contact = { t = 1, type = "ballHit", ball = 0, other = 8, speed = 10 }
		local events = if case == "FoulEight"
			then { contact, drop(8, 2, 3), drop(0, 3) }
			else { contact, drop(8, 2, 4) }
		judged(m, events)
		expect(m.phase == "Result" and m.result.winner == 2 and m.result.reason == case, case)
	end
end
function tests.solo_surrender_and_departure_end_with_no_winner()
	for size = 1, 3 do
		local m = solo(size)
		expect(action(m, 11, "Surrender"))
		expect(m.phase == "Result" and m.result.winner == nil and m.result.reason == "Surrender")
		expect(m.vote == nil)
		expire(m)
		expect(m.phase == "Waiting" and m.solo == nil and E.count(m) == 0)
	end
	local m = solo(1)
	expect(E.remove(m, 11, 1))
	expect(m.phase == "Result" and m.result.winner == nil and m.result.reason == "EmptyTeam")
end
function tests.solo_runs_on_team_tables_from_either_side()
	for size = 2, 3 do
		for side = 1, 2 do
			local m = solo(size, side)
			local user = side * 10 + 1
			expect(m.solo.team == side and m.activeTeam == side and m.shooter == user)
			expire(m)
			resolveFixture(m, true, nil)
			expect(m.phase == "Aiming" and m.shooter == user, "the break keeps the table")
			resolveFixture(m, false, "Scratch")
			expire(m)
			expect(m.phase == "Placement" and m.shooter == user and m.activeTeam == side)
			resolveFixture(m, false, nil)
			expect(m.phase == "Aiming" and m.shooter == user and m.deadline == nil)
		end
	end
end

function tests.soft_tap_is_legal_on_casual_tables_and_a_foul_on_ranked()
	for _, ranked in { false, true } do
		local m = playing(1)
		m.breakShot, m.ballInHand = false, false
		aim(m)
		m.groups = { "solids", "stripes" }
		m.ranked = ranked
		for _, b in m.state.balls do
			b.pocketed = b.id ~= 0 and b.id ~= 3 and b.id ~= 8
		end
		local cue, three = Sim.findBall(m.state, 0), Sim.findBall(m.state, 3)
		cue.x, cue.y = -10, 0
		three.x, three.y = -5, 0 -- in the open, far from every rail and pocket
		local payload = shotPayload(m)
		payload.power = 0.06
		local wire = E.acceptShot(m, 11, payload, m.phaseStartedAt)
		expect(wire ~= nil, "shot accepted")
		expect(m.pending.judgement.foul == (if ranked then "NoRail" else nil), "rail rule by table")
	end
end

return tests
