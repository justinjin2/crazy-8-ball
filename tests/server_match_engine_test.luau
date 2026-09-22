--!strict
-- Acceptance regressions against the exact pure engine used by TableService/ShotService.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local M = H.require("Config").Multiplayer
local Ball = H.require("Physics.Ball")
local Sim = H.require("Physics.Simulation")
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
function tests.foul_introduction_placement_aim_order_and_early_confirm()
	local m = playing(3)
	resolveFixture(m, true, "Scratch")
	expect(m.phase == "Foul" and m.foul.by == 11 and m.foul.team == 1)
	expire(m)
	expect(m.phase == "Intro" and m.shooter == 21 and m.ballInHand)
	expire(m)
	expect(m.phase == "Placement")
	expect(action(m, 21, "ConfirmPlacement"))
	expect(m.phase == "Aiming" and not m.ballInHand)
	expect(not action(m, 21, "ConfirmPlacement"))
end
function tests.setup_deadlines_autocomplete_without_shooting_timeout()
	local m = playing(1)
	expire(m)
	expect(m.phase == "Placement")
	expire(m)
	expect(m.phase == "Aiming" and m.timeouts[1] == 0)
	expect(m.deadline - m.phaseStartedAt == M.ShotSeconds)
end
function tests.eligible_ball_in_hand_requires_placement_then_call_and_no_early_eight()
	local m = playing(2)
	m.groups = { "solids", "stripes" }
	for _, ball in m.state.balls do
		if ball.id >= 9 then
			ball.pocketed = true
		end
	end
	resolveFixture(m, false, "Scratch")
	expire(m)
	local early = E.acceptShot(m, 21, shotPayload(m), m.phaseStartedAt)
	expect(early == nil)
	expire(m)
	expect(m.phase == "Placement")
	expect(action(m, 21, "ConfirmPlacement"))
	expect(m.phase == "PocketChoice")
	expect(not action(m, 11, "Pocket", { pocket = 1 }))
	expect(action(m, 21, "Pocket", { pocket = 2 }))
	local deadline = m.deadline
	expect(m.phase == "Aiming" and m.calledPocket == 2)
	expect(action(m, 21, "Pocket", { pocket = 3 }))
	expect(m.calledPocket == 3 and m.deadline == deadline)
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
	expire(m)
	expect(m.phase == "PocketChoice")
	expire(m)
	expect(m.calledPocket == pocket.id and m.phase == "Aiming")
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
		expire(m)
		expect(
			m.phase == "Result" and m.result.winner == 1,
			"legal called eight should win mode " .. size
		)
		expect(#m.feedback > 0, "winning eight should award bonus")
		expire(m)
		expect(m.phase == "Waiting" and E.count(m) == 0 and not Sim.findBall(m.state, 8).pocketed)
	end
end
return tests
