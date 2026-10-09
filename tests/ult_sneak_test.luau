--!strict
-- Look Over There! in the match engine (the designer's second rework round, 2026-10-08): it
-- arms at once (no cutscene: nobody may be warned) and opens the Sneak phase instead of a shot;
-- inside the drag window the shooter moves the cue ball anywhere on the cloth (ball in hand's
-- own Place and stream, its rules); the window's end spends it, SneakReveal, then the turn's
-- run-up again from the new spot.
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local Match = H.require("Ults.Match")
local Config = H.require("Config")
local Sim = H.require("Physics.Simulation")
local U = Config.Ults
local S = U.Shared
local M = Config.Multiplayer
local expect = H.expect
local tests = {}

local ID = "LookOverThere"

local function built(body: () -> ())
	local row = U.Catalog[ID]
	local was = row.Built
	row.Built = true
	local ok, err = pcall(body)
	row.Built = was
	if not ok then
		error(err, 0)
	end
end

local function expire(m: any)
	expect(m.deadline ~= nil, "a deadline to expire")
	E.advance(m, m.deadline)
end

local function midGame(): any
	local m = E.new(1, 1)
	expect(E.join(m, 11, "11", "11", 0))
	expect(E.join(m, 21, "21", "21", 0))
	expect(E.action(m, 11, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 1))
	expire(m) -- the coin
	m.breakShot, m.ballInHand = false, false
	m.groups = { "solids", "stripes" }
	expire(m) -- the introduction
	expect(m.phase == "Aiming" and m.shooter == 11)
	return m
end

-- Activates Look Over There! for 11; it is armed at once, so the next advance (the same
-- moment) opens the Sneak phase. Returns that moment.
local function sneakNow(m: any): number
	expect(Match.setBar(m, 11, U.BarMax))
	local at = m.phaseStartedAt + 0.5
	local ok, why = Match.activate(m, 11, ID, at)
	expect(ok, "activation: " .. tostring(why))
	E.advance(m, at)
	return at
end

local function place(m: any, at: number, x: any, y: any, seq: number?): boolean
	local r: any = { kind = "Place", epoch = m.epoch, turnId = m.turnId, x = x, y = y, seq = seq }
	return E.action(m, 11, r, at)
end

local function ball(m: any, id: number): any
	return Sim.findBall(m.state, id)
end

function tests.it_arms_at_once_and_opens_the_sneak_phase_with_its_own_clock()
	built(function()
		local m = midGame()
		local deadline = m.deadline
		local at = sneakNow(m)
		expect(m.phase == "Sneak", "the Sneak phase, got " .. m.phase)
		expect(
			m.ults.armed ~= nil and m.ults.armed.at == at and m.ults.armed.readyAt == at,
			"no wait"
		)
		local windowEnd = at + S.SneakIntroSeconds + S.SneakDragSeconds + S.SneakGraceSeconds
		expect(math.abs(m.deadline - windowEnd) < 1e-9, "intro + drag + grace")
		expect(deadline ~= nil, "the shot clock was running before")
		local snap = E.snapshot(m)
		expect(snap.sneak ~= nil and snap.sneak.by == 11, "the snapshot carries the sneak")
		expect(math.abs(snap.sneak.dragAt - (at + S.SneakIntroSeconds)) < 1e-9, "dragAt")
		expect(snap.sneak.seq == m.ults.armed.seq, "the ult's seq")
		local cue = ball(m, 0)
		expect(snap.sneak.fromX == cue.x and snap.sneak.fromY == cue.y, "where the cue ball was")
		expect(E.shooterLocked("Sneak", nil) and E.shooterLocked("SneakReveal", nil))
	end)
end

function tests.the_cue_ball_moves_anywhere_free_in_the_window_and_the_turn_goes_on_from_there()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		local dragAt = at + S.SneakIntroSeconds
		expect(place(m, dragAt + 0.5, -30, 10, 1), "a free spot")
		expect(place(m, dragAt + 1.5, 20, -12, 2), "and again: as often as they like")
		local cue = ball(m, 0)
		expect(cue.x == 20 and cue.y == -12 and not cue.pocketed, "the cue ball moved there")
		expect(m.phase == "Sneak", "the window stays open to its end")
		expire(m)
		expect(m.phase == "SneakReveal", "the reveal")
		expect(m.ults.armed == nil, "the ult is spent")
		expect(m.sneak.x == 20 and m.sneak.y == -12 and m.sneak.moved == true, "where it went")
		local revealAt = m.phaseStartedAt
		expire(m)
		expect(m.phase == "Aiming" and m.shooter == 11, "the same shooter aims")
		expect(math.abs(m.deadline - revealAt - S.SneakRevealSeconds - M.ShotSeconds) < 1e-9)
		expect(m.sneak == nil and E.snapshot(m).sneak == nil, "the sneak is over")
		expect(ball(m, 0).x == 20 and ball(m, 0).y == -12, "it stays there for the shot")
		expect(m.ballInHand == false, "no ball in hand after it")
		expect(m.groups[1] == "solids" and m.foul == nil, "groups kept, no foul")
		local p = { tableId = m.id, epoch = m.epoch, turnId = m.turnId, angle = 0, power = 0.3 }
		p.cueX, p.cueY = 0, 0
		local wire, why = E.acceptShot(m, 11, p, m.phaseStartedAt + 1)
		expect(
			wire == nil and why == "InvalidPlacement",
			"no moving it with the shot: " .. tostring(why)
		)
	end)
end

function tests.only_legal_spots_like_ball_in_hand()
	built(function()
		local m = midGame()
		local at = sneakNow(m) + S.SneakIntroSeconds
		local five = ball(m, 5)
		expect(not place(m, at, five.x, five.y), "not onto another ball")
		expect(not place(m, at, 0 / 0, 0), "not NaN")
		expect(not place(m, at, 1000, 0), "not off the table")
		local cue = ball(m, 0)
		expect(cue.x ~= five.x, "nothing moved")
		expect(place(m, at, -30, 10), "a free spot")
	end)
end

function tests.the_move_is_only_taken_inside_the_drag_window()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		expect(not place(m, at, -30, 10), "during the intro, before the grace")
		local early = at + S.SneakIntroSeconds - S.SneakGraceSeconds * 0.5
		expect(place(m, early, -30, 10), "inside the early grace")
		local late = at + S.SneakIntroSeconds + S.SneakDragSeconds + S.SneakGraceSeconds * 0.5
		expect(place(m, late, -31, 10), "inside the late grace")
		expect(not place(m, m.deadline, -32, 10), "after the grace")
	end)
end

function tests.a_late_stream_packet_never_drags_it_back()
	built(function()
		local m = midGame()
		local at = sneakNow(m) + S.SneakIntroSeconds
		expect(place(m, at, -30, 10, 5))
		local r = { epoch = m.epoch, turnId = m.turnId, x = 0, y = 0, seq = 4 }
		expect(not E.moveCue(m, 11, r, at + 0.1), "an older stream packet")
		r.seq = 6
		expect(E.moveCue(m, 11, r, at + 0.2), "a newer one")
		expect(ball(m, 0).x == 0 and ball(m, 0).y == 0)
		expect(
			not E.moveCue(m, 21, { epoch = m.epoch, turnId = m.turnId, x = 5, y = 5, seq = 9 }, at),
			"the opponent"
		)
	end)
end

function tests.no_move_in_time_leaves_the_cue_ball_and_spends_the_ult()
	built(function()
		local m = midGame()
		sneakNow(m)
		local before = Sim.cloneState(m.state).balls
		expire(m)
		expect(m.phase == "SneakReveal" and m.sneak.moved == false, "the reveal, nothing moved")
		expect(m.ults.armed == nil, "spent")
		for i, b in m.state.balls do
			expect(b.x == before[i].x and b.y == before[i].y and b.pocketed == before[i].pocketed)
		end
		expire(m)
		expect(m.phase == "Aiming" and m.shooter == 11, "the shot as normal")
	end)
end

function tests.no_shot_while_the_sneak_plays()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		local p = { tableId = m.id, epoch = m.epoch, turnId = m.turnId, angle = 0, power = 0.3 }
		local wire, why = E.acceptShot(m, 11, p, at + 0.1)
		expect(wire == nil and why == "WrongPhase", "mid-sneak: " .. tostring(why))
		local ok, reason = Match.check(m, 11)
		expect(not ok and reason == "NotYourTurn", "no second ability mid-sneak")
	end)
end

function tests.allowed_on_the_8_refused_on_the_break_and_with_ball_in_hand()
	built(function()
		local m = midGame()
		for id = 1, 7 do
			ball(m, id).pocketed = true
		end
		expect(Match.setBar(m, 11, U.BarMax))
		local ok, why = Match.activate(m, 11, ID, m.phaseStartedAt)
		expect(ok, "on the 8 it is fine: " .. tostring(why))

		local h = midGame()
		h.ballInHand = true
		h.phase = "Placement"
		expect(Match.setBar(h, 11, U.BarMax))
		ok, why = Match.activate(h, 11, ID, h.phaseStartedAt)
		expect(not ok and why == "BallInHand", "with ball in hand: " .. tostring(why))
		expect(h.ults.bars["11"].bar == U.BarMax, "the bar is not spent")

		local s = E.new(2, 1)
		expect(E.join(s, 11, "s", "s", 0))
		expect(E.action(s, 11, { kind = "StartSolo", epoch = s.epoch, turnId = s.turnId }, 0))
		ok, why = Match.practice(s, 11, ID, s.phaseStartedAt)
		expect(not ok and why == "Break", "the solo break: " .. tostring(why))
	end)
end

function tests.a_shooter_reset_mid_sneak_loses_the_turn()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		E.death(m, 11, at + 0.5)
		expect(m.phase == "Foul" and m.foul.reason == "Reset", "a foul")
		expect(m.sneak == nil and m.ults.armed == nil, "the sneak is over and spent")
	end)
end

return tests
