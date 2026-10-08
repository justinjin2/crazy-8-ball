--!strict
-- Look Over There! in the match engine (the abilities rework, designer 2026-10-08): once armed
-- it opens the Sneak phase instead of a shot; the shooter's one drop pots one of their balls or
-- moves it, inside the drag window; SneakReveal, then the turn's run-up again.
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

local PAUSE = U.CutsceneSeconds + U.ArmDelaySeconds
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

-- Activates Look Over There! for 11 and runs the clock to the end of its cutscene.
local function sneakNow(m: any): number
	expect(Match.setBar(m, 11, U.BarMax))
	local ok, why = Match.activate(m, 11, ID, m.phaseStartedAt)
	expect(ok, "activation: " .. tostring(why))
	local at = m.phaseStartedAt + PAUSE
	E.advance(m, at)
	return at
end

local function drop(m: any, at: number, fields: { [string]: any }): boolean
	local r: any = { kind = "Sneak", epoch = m.epoch, turnId = m.turnId }
	for k, v in fields do
		r[k] = v
	end
	return E.action(m, 11, r, at)
end

local function ball(m: any, id: number): any
	return Sim.findBall(m.state, id)
end

function tests.once_armed_it_opens_the_sneak_phase_with_its_own_clock()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		expect(m.phase == "Sneak", "the Sneak phase, got " .. m.phase)
		local windowEnd = at + S.SneakIntroSeconds + S.SneakDragSeconds + S.SneakGraceSeconds
		expect(math.abs(m.deadline - windowEnd) < 1e-9, "intro + drag + grace")
		local snap = E.snapshot(m)
		expect(snap.sneak ~= nil and snap.sneak.by == 11, "the snapshot carries the sneak")
		expect(math.abs(snap.sneak.dragAt - (at + S.SneakIntroSeconds)) < 1e-9, "dragAt")
		expect(snap.sneak.seq == m.ults.armed.seq, "the ult's seq")
		expect(E.shooterLocked("Sneak", nil) and E.shooterLocked("SneakReveal", nil))
	end)
end

function tests.a_drop_in_a_pocket_pots_the_ball_and_the_turn_goes_on()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		local from = { x = ball(m, 3).x, y = ball(m, 3).y }
		local dragAt = at + S.SneakIntroSeconds
		expect(drop(m, dragAt + 1, { ball = 3, pocket = 2 }), "the drop is taken")
		local b = ball(m, 3)
		expect(b.pocketed and b.pocket == 2, "the 3 is down in pocket 2")
		expect(m.phase == "SneakReveal", "the reveal")
		expect(m.ults.armed == nil, "the ult is spent")
		expect(m.sneak.ball == 3 and m.sneak.pocket == 2, "what was sneaked")
		expect(m.sneak.fromX == from.x and m.sneak.fromY == from.y, "from where")
		expect(not drop(m, dragAt + 1.1, { ball = 4, pocket = 2 }), "one drop only")
		local revealAt = m.phaseStartedAt
		expire(m)
		expect(m.phase == "Aiming" and m.shooter == 11, "the same shooter aims")
		expect(math.abs(m.deadline - revealAt - S.SneakRevealSeconds - M.ShotSeconds) < 1e-9)
		expect(m.sneak == nil and E.snapshot(m).sneak == nil, "the sneak is over")
		expect(m.groups[1] == "solids", "groups kept")
		expect(m.foul == nil, "no foul")
	end)
end

function tests.only_your_own_balls_never_the_eight_or_the_cue_ball()
	built(function()
		local m = midGame()
		local at = sneakNow(m) + S.SneakIntroSeconds
		expect(not drop(m, at, { ball = 9, pocket = 1 }), "an opponent's stripe")
		expect(not drop(m, at, { ball = 8, pocket = 1 }), "the 8")
		expect(not drop(m, at, { ball = 0, pocket = 1 }), "the cue ball")
		expect(not drop(m, at, { ball = 3.5, pocket = 1 }), "not a ball")
		expect(not drop(m, at, { ball = 3, pocket = 7 }), "no pocket 7")
		expect(not drop(m, at, { ball = 3 }), "neither a pocket nor a spot")
		expect(m.phase == "Sneak", "still waiting for a drop")
		expect(drop(m, at, { ball = 3, pocket = 1 }), "a solid is fine")
	end)
end

function tests.the_drop_is_only_taken_inside_the_drag_window()
	built(function()
		local m = midGame()
		local at = sneakNow(m)
		expect(not drop(m, at, { ball = 3, pocket = 1 }), "during the intro")
		expect(not drop(m, m.deadline, { ball = 3, pocket = 1 }), "after the grace")
		local late = at + S.SneakIntroSeconds + S.SneakDragSeconds + S.SneakGraceSeconds * 0.5
		expect(drop(m, late, { ball = 3, pocket = 1 }), "inside the grace")
	end)
end

function tests.a_drop_on_the_cloth_moves_the_ball_to_a_free_spot()
	built(function()
		local m = midGame()
		local at = sneakNow(m) + S.SneakIntroSeconds
		local five = ball(m, 5)
		expect(not drop(m, at, { ball = 3, x = five.x, y = five.y }), "not onto another ball")
		expect(not drop(m, at, { ball = 3, x = 0 / 0, y = 0 }), "not NaN")
		expect(not drop(m, at, { ball = 3, x = 1000, y = 0 }), "not off the table")
		expect(drop(m, at, { ball = 3, x = -30, y = 10 }), "a free spot")
		local b = ball(m, 3)
		expect(not b.pocketed and b.x == -30 and b.y == 10, "moved there")
		expect(m.phase == "SneakReveal" and m.sneak.pocket == nil, "a move, not a pot")
	end)
end

function tests.no_drop_in_time_moves_nothing_and_spends_the_ult()
	built(function()
		local m = midGame()
		sneakNow(m)
		local before = Sim.cloneState(m.state).balls
		expire(m)
		expect(m.phase == "SneakReveal" and m.sneak.ball == nil, "the reveal, nothing sneaked")
		expect(m.ults.armed == nil, "spent")
		for i, b in m.state.balls do
			expect(b.x == before[i].x and b.y == before[i].y and b.pocketed == before[i].pocketed)
		end
		expire(m)
		expect(m.phase == "Aiming" and m.shooter == 11, "the shot as normal")
	end)
end

function tests.no_shot_while_the_sneak_is_due_or_playing()
	built(function()
		local m = midGame()
		expect(Match.setBar(m, 11, U.BarMax))
		expect(Match.activate(m, 11, ID, m.phaseStartedAt))
		local p = { tableId = m.id, epoch = m.epoch, turnId = m.turnId, angle = 0, power = 0.3 }
		local at = m.phaseStartedAt + PAUSE
		local wire, why = E.acceptShot(m, 11, p, at)
		expect(wire == nil and why == "UltArming", "armed but not yet sneaking: " .. tostring(why))
		E.advance(m, at)
		wire, why = E.acceptShot(m, 11, p, at + 0.1)
		expect(wire == nil and why == "WrongPhase", "mid-sneak: " .. tostring(why))
		local ok, reason = Match.check(m, 11)
		expect(not ok and reason == "NotYourTurn", "no second ability mid-sneak")
	end)
end

function tests.on_an_open_table_a_sneaked_pot_claims_its_group()
	built(function()
		local m = midGame()
		m.groups = {}
		local at = sneakNow(m) + S.SneakIntroSeconds
		expect(drop(m, at, { ball = 12, pocket = 4 }), "any ball but the 8 while open")
		expect(m.groups[1] == "stripes" and m.groups[2] == "solids", "the sneaker is stripes")
		expect(E.snapshot(m).groups[1] == "stripes")
	end)
end

function tests.solo_sneak_claims_its_group_and_moves_on_when_it_clears_it()
	built(function()
		local s = E.new(2, 1)
		expect(E.join(s, 11, "s", "s", 0))
		expect(E.action(s, 11, { kind = "StartSolo", epoch = s.epoch, turnId = s.turnId }, 0))
		s.breakShot, s.ballInHand = false, false
		-- Only the 7 is left of the solids; the stripes are all up.
		for id = 1, 6 do
			ball(s, id).pocketed = true
		end
		s.solo.first = "solids"
		s.groups = { "solids", "stripes" }
		s.phase = "Aiming"
		local ok, why = Match.practice(s, 11, ID, s.phaseStartedAt)
		expect(ok, "practice: " .. tostring(why))
		local at = s.phaseStartedAt + PAUSE
		E.advance(s, at)
		expect(s.phase == "Sneak", "sneaking, got " .. s.phase)
		expect(drop(s, at + S.SneakIntroSeconds, { ball = 7, pocket = 3 }))
		expect(s.groups[1] == "stripes", "the solids done: on to the stripes")
	end)
end

function tests.sneaking_your_last_ball_brings_the_call_for_the_eight()
	built(function()
		local m = midGame()
		for id = 1, 6 do
			ball(m, id).pocketed = true
		end
		local at = sneakNow(m) + S.SneakIntroSeconds
		expect(drop(m, at, { ball = 7, pocket = 6 }))
		expire(m)
		expect(m.phase == "PocketChoice" and m.shooter == 11, "now on the 8: " .. m.phase)
	end)
end

function tests.refused_on_the_break_and_with_nothing_to_sneak()
	built(function()
		local m = midGame()
		expect(Match.setBar(m, 11, U.BarMax))
		for id = 1, 7 do
			ball(m, id).pocketed = true
		end
		local ok, why = Match.activate(m, 11, ID, m.phaseStartedAt)
		expect(not ok and why == "NoBall", "on the 8: " .. tostring(why))
		expect(m.ults.bars["11"].bar == U.BarMax, "the bar is not spent")
		local s = E.new(2, 1)
		expect(E.join(s, 11, "s", "s", 0))
		expect(E.action(s, 11, { kind = "StartSolo", epoch = s.epoch, turnId = s.turnId }, 0))
		ok, why = Match.practice(s, 11, ID, s.phaseStartedAt)
		expect(not ok and why == "Break", "the solo break: " .. tostring(why))
	end)
end

function tests.ball_in_hand_is_kept_through_the_sneak()
	built(function()
		local m = midGame()
		m.ballInHand = true
		m.phase = "Placement"
		sneakNow(m)
		expect(m.phase == "Sneak")
		expire(m)
		expire(m)
		expect(m.phase == "Placement" and m.ballInHand == true, "ball in hand again")
		expect(math.abs(m.deadline - m.phaseStartedAt - M.PlacementSeconds) < 1e-9)
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
