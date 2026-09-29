--!strict
-- The ability framework in the match engine (docs/prompts/ABILITIES_PROMPT.md 5.2): Rewind's
-- snapshot and restore, Time Stop's frozen phase with its second strike and server timeout,
-- and the aim-phase picks (Heat Seeker's ball, Portals' spots). The rows are switched to Built
-- here for the test only (their own steps build them for real).
local H = require("./harness")
local E = H.require("Rules.MatchEngine")
local Match = H.require("Ults.Match")
local Config = H.require("Config")
local Sim = H.require("Physics.Simulation")
local Ball = H.require("Physics.Ball")
local TimeStop = H.require("Ults.Effects.TimeStop")
local U = Config.Ults
local S = U.Shared
local expect = H.expect
local tests = {}

local PAUSE = U.CutsceneSeconds + U.ArmDelaySeconds
local DT = Config.Physics.FixedStep

local function built(id: string, body: () -> ())
	local row = U.Catalog[id]
	local was, effect = row.Built, row.Effect
	row.Built = true
	-- A pick ability's overrides need an effect name (an unknown one steps nothing).
	row.Effect = effect or id
	local ok, err = pcall(body)
	row.Built, row.Effect = was, effect
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
	m.settings.difficulty = "Difficult"
	m.breakShot, m.ballInHand = false, false
	m.groups = { "solids", "stripes" }
	expire(m) -- the introduction
	expect(m.phase == "Aiming" and m.shooter == 11)
	return m
end

local function payload(m: any, angle: number, power: number): any
	return { tableId = m.id, epoch = m.epoch, turnId = m.turnId, angle = angle, power = power }
end

local function place(m: any, id: number, x: number, y: number)
	local b = Sim.findBall(m.state, id)
	b.x, b.y, b.pocketed = x, y, false
end

-- A soft hit that drops nothing.
local function missShot(m: any): any
	place(m, 3, -15, 0)
	place(m, 0, -7, 0)
	return payload(m, math.pi, 0.06)
end

-- Ball `id` in front of the +y side pocket, the cue ball behind it: drops it.
local function potShot(m: any, id: number): any
	local y = m.state.geometry.halfWidth - 5
	place(m, id, 0, y)
	place(m, 0, 0, y - 8)
	return payload(m, math.pi / 2, 0.12)
end

local function armNow(m: any, id: string)
	local ok, why = Match.setBar(m, 11, U.BarMax), nil
	expect(ok)
	ok, why = Match.activate(m, 11, id, m.phaseStartedAt)
	expect(ok, "activation: " .. tostring(why))
	E.advance(m, m.phaseStartedAt + PAUSE)
	expect(m.ults.armed.stage == "Armed")
end

local function sameBalls(a: { any }, b: { any }): boolean
	for i, x in a do
		local y = b[i]
		if x.id ~= y.id or x.x ~= y.x or x.y ~= y.y or x.pocketed ~= y.pocketed or x.z ~= y.z then
			return false
		end
	end
	return #a == #b
end

-- Every field of every ball the same, bit for bit (positions, motion, spin, flags).
local function identical(a: { any }, b: { any }): (boolean, string?)
	if #a ~= #b then
		return false, "ball count"
	end
	for i, x in a do
		local y = b[i]
		for key, value in x do
			if y[key] ~= value then
				return false,
					("ball %d %s: %s vs %s"):format(x.id, key, tostring(value), tostring(y[key]))
			end
		end
		for key in y do
			if x[key] == nil then
				return false, ("ball %d gained %s"):format(y.id, key)
			end
		end
	end
	return true
end

---------------------------------------------------------------------------------------------
-- Rewind
---------------------------------------------------------------------------------------------

function tests.rewind_restores_the_table_and_gives_a_ten_second_redo()
	built("Rewind", function()
		local m = midGame()
		armNow(m, "Rewind")
		local p = missShot(m)
		local before = Ball.cloneList(m.state.balls)
		table.clear(m.ultFeed)
		local now = m.phaseStartedAt
		local wire = E.acceptShot(m, 11, p, now)
		expect(wire and wire.rewind == true, "a shot that drops none of yours rewinds")
		expect(#m.ultFeed == 0, "the rewound try fills nothing")
		expect(#m.feedback == 0, "and gets no stings")
		expire(m) -- the replay
		expect(m.phase == "Rewinding" and m.rewound ~= nil, "everyone watches it rewind")
		expect(E.snapshot(m).rewound ~= nil, "the snapshot says so")
		expect(sameBalls(m.state.balls, before), "the exact table before the shot")
		local same, why = identical(m.state.balls, before)
		expect(same, "bit-identical: " .. tostring(why))
		expect(
			m.groups[1] == "solids" and m.groups[2] == "stripes" and m.foul == nil,
			"groups kept"
		)
		expect(m.shooter == 11 and m.ults.armed == nil, "the same shooter; the ability is spent")
		local at = m.deadline
		expire(m)
		expect(m.phase == "Aiming" and m.shooter == 11, "the redo")
		expect(math.abs(m.deadline - at - S.RewindRedoSeconds) < 1e-9, "on a 10 s clock")
		-- The redo is a plain shot: it never rewinds again.
		local redo = E.acceptShot(m, 11, missShot(m), m.phaseStartedAt)
		expect(redo and redo.rewind == nil and redo.ult == nil, "a plain shot")
		expire(m)
		expect(m.shooter == 21, "a miss on the redo passes the turn")
	end)
end

function tests.rewind_erases_a_scratch_and_keeps_ball_in_hand()
	built("Rewind", function()
		local m = midGame()
		-- Ball in hand: move the cue ball to the scratch spot as the shot's placement.
		m.ballInHand = true
		m.phase = "Placement"
		m.deadline = m.phaseStartedAt + 30
		armNow(m, "Rewind")
		local y = m.state.geometry.halfWidth - 6
		local p = payload(m, math.pi / 2, 0.12)
		p.cueX, p.cueY = 0, y
		-- The table as the shot starts from it: the cue ball where it was placed.
		place(m, 0, 0, y)
		local before = Ball.cloneList(m.state.balls)
		local wire = E.acceptShot(m, 11, p, m.phaseStartedAt)
		expect(wire and wire.rewind == true, "a scratch with none of yours down rewinds")
		local final = wire.final
		expect(final[4] == 1, "the cue ball went down")
		expire(m)
		expect(m.phase == "Rewinding" and m.foul == nil, "the foul is erased")
		local same, why = identical(m.state.balls, before)
		expect(same, "bit-identical after the scratch: " .. tostring(why))
		expire(m)
		expect(m.ballInHand == true and m.phase == "Placement", "ball in hand as before")
		expect(E.snapshot(m).redoClock == true, "the HUD is told it is the redo")
		-- The usual time to move the cue ball, then the redo's 10 s shot clock.
		local at = m.deadline
		expire(m)
		expect(m.phase == "Aiming", "aiming after the move time")
		expect(math.abs(m.deadline - at - S.RewindRedoSeconds) < 1e-9, "on the 10 s clock")
	end)
end

function tests.rewind_saves_an_early_eight_but_not_a_dropped_ball()
	built("Rewind", function()
		local m = midGame()
		armNow(m, "Rewind")
		local wire = E.acceptShot(m, 11, potShot(m, 8), m.phaseStartedAt)
		expect(wire and wire.rewind == true and wire.eightWins == false, "the early 8 rewinds")
		expire(m)
		expect(m.phase == "Rewinding" and m.result == nil, "the game goes on")
		-- One of yours drops: nothing happens, the shot stands.
		m = midGame()
		armNow(m, "Rewind")
		wire = E.acceptShot(m, 11, potShot(m, 2), m.phaseStartedAt)
		expect(wire and wire.rewind == nil, "no rewind")
		expire(m)
		expect(m.shooter == 11 and m.phase ~= "Rewinding", "the pot keeps the turn")
	end)
end

---------------------------------------------------------------------------------------------
-- Time Stop
---------------------------------------------------------------------------------------------

-- The client's replay of a Time Stop shot: part one to the halt, the strike (if any), resume,
-- to rest. Returns the final balls.
local function replay(start: { any }, wire: any): { any }
	local geometry = H.require("Physics.Table").build({ pocketsOpen = true })
	local state = Sim.newState(geometry, Ball.cloneList(start))
	local cue = assert(Sim.findBall(state, 0))
	local seed = wire.seed
	cue.vx, cue.vy, cue.vz, cue.wx, cue.wy, cue.wz =
		seed.vx, seed.vy, seed.vz or 0, seed.wx, seed.wy, seed.wz
	state.overrides = table.clone(wire.overrides)
	local events = {}
	local guard = 0
	local function run()
		while not Sim.isAtRest(state) and not state.halted and guard < 40000 do
			Sim.step(state, DT, events)
			guard += 1
		end
	end
	run()
	expect(state.halted, "part one halts")
	if wire.parts.strike then
		TimeStop.beginStrike(state, wire.parts.strike.seed)
		run()
		expect(state.halted, "the strike's part halts")
	end
	TimeStop.resume(state)
	run()
	Sim.finishShot(state, events)
	return state.balls
end

local function frozenShot(m: any): (any, { any })
	place(m, 3, -15, 0)
	place(m, 5, -30, 10)
	place(m, 0, -5, 0)
	local start = Ball.cloneList(m.state.balls)
	local wire = E.acceptShot(m, 11, payload(m, math.pi, 0.35), m.phaseStartedAt)
	expect(wire and wire.halted == true, "the shot freezes after its first contact")
	expect(m.phase == "Frozen", "the Frozen phase")
	return wire, start
end

function tests.time_stop_freezes_takes_one_second_strike_and_replays_to_the_same_bits()
	built("TimeStop", function()
		local m = midGame()
		armNow(m, "TimeStop")
		local shotAt = m.phaseStartedAt
		local wire, start = frozenShot(m)
		local freezeAt = m.pending.frozen.freezeAt
		local second = payload(m, math.pi / 2, 0.3)
		local early, why = E.acceptShot(m, 11, second, freezeAt - 0.1)
		expect(early == nil and why == "NotFrozenYet", "not before the replay reaches the freeze")
		local other = E.acceptShot(m, 21, second, freezeAt + 1)
		expect(other == nil, "only the shooter")
		local ok = E.acceptShot(m, 11, second, freezeAt + 1)
		expect(ok and ok.parts.strike ~= nil, "the second strike")
		local again = E.acceptShot(m, 11, second, freezeAt + 1.1)
		expect(again == nil, "only one")
		expire(m) -- time resumes
		expect(m.phase == "Resolving" or m.phase == "Foul", "judged as one shot")
		expect(E.takeLateShot(m) == wire.seq and E.takeLateShot(m) == nil, "sent once")
		expect(wire.checksum ~= nil and wire.final ~= nil, "the final positions")
		local mine = replay(start, wire)
		expect(Sim.checksum(mine) == wire.checksum, "the replay across the split matches")
		expect(shotAt <= freezeAt)
	end)
end

function tests.time_stop_without_a_strike_resumes_at_the_timeout()
	built("TimeStop", function()
		local m = midGame()
		armNow(m, "TimeStop")
		local wire, start = frozenShot(m)
		local deadline = m.deadline
		expect(
			math.abs(deadline - m.pending.frozen.freezeAt - S.FrozenSeconds) < 1e-9,
			"5 s of stopped time"
		)
		expire(m)
		expect(m.phase == "Resolving" or m.phase == "Foul", "resumed and judged")
		expect(wire.parts.strike == nil)
		expect(Sim.checksum(replay(start, wire)) == wire.checksum, "the replay matches")
		-- Twice gives the same bits.
		local m2 = midGame()
		armNow(m2, "TimeStop")
		local wire2 = frozenShot(m2)
		expire(m2)
		expect(wire2.checksum == wire.checksum, "deterministic")
	end)
end

function tests.time_stop_refuses_a_strike_after_its_five_seconds()
	built("TimeStop", function()
		local m = midGame()
		armNow(m, "TimeStop")
		frozenShot(m)
		local late, why = E.acceptShot(m, 11, payload(m, math.pi / 2, 0.3), m.deadline + 0.01)
		expect(late == nil and why == "Expired", "the server holds the 5 s: " .. tostring(why))
		local stale = payload(m, math.pi / 2, 0.3)
		stale.turnId += 1
		local forged = E.acceptShot(m, 11, stale, m.pending.frozen.freezeAt + 0.5)
		expect(forged == nil, "a stale turn is refused")
	end)
end

function tests.time_stop_with_no_contact_is_a_plain_shot()
	built("TimeStop", function()
		local m = midGame()
		armNow(m, "TimeStop")
		place(m, 0, -5, 0)
		for _, b in m.state.balls do
			if b.id ~= 0 then
				b.x, b.y = 40, -20 + b.id * 0.001
				b.pocketed = b.id ~= 3
			end
		end
		place(m, 3, 40, 20)
		local wire = E.acceptShot(m, 11, payload(m, math.pi, 0.2), m.phaseStartedAt)
		expect(wire and wire.halted == nil and m.phase == "Resolving", "no freeze")
	end)
end

---------------------------------------------------------------------------------------------
-- Picks
---------------------------------------------------------------------------------------------

local function pick(m: any, request: any): boolean
	request.kind = "UltPick"
	request.epoch, request.turnId = m.epoch, m.turnId
	return E.action(m, 11, request, m.phaseStartedAt)
end

function tests.heat_seeker_needs_one_of_your_balls_picked_first()
	built("HeatSeeker", function()
		local m = midGame()
		armNow(m, "HeatSeeker")
		local wire, why = E.acceptShot(m, 11, missShot(m), m.phaseStartedAt)
		expect(wire == nil and why == "PickRequired", "the shot waits for the pick")
		expect(not pick(m, { ball = 11 }), "not an opponent's ball")
		expect(not pick(m, { ball = 8 }), "not the 8 before your legal 8 shot")
		expect(not pick(m, { ball = 0 }), "not the cue ball")
		expect(not pick(m, { ball = "3" }), "not a forged value")
		expect(
			not E.action(
				m,
				21,
				{ kind = "UltPick", ball = 3, epoch = m.epoch, turnId = m.turnId },
				0
			)
		)
		expect(pick(m, { ball = 3 }), "one of yours")
		expect(E.snapshot(m).ults.armed.pick[1] == 3, "everyone sees the pick")
		wire = E.acceptShot(m, 11, missShot(m), m.phaseStartedAt)
		expect(wire and wire.overrides.Pick[1] == 3, "the pick rides in the overrides")
	end)
end

function tests.portals_must_be_clear_of_cushions_pockets_balls_and_each_other()
	built("Portals", function()
		local m = midGame()
		armNow(m, "Portals")
		for _, b in m.state.balls do
			if b.id ~= 0 then
				b.pocketed = b.id ~= 3
			end
		end
		place(m, 3, 20, 0)
		place(m, 0, -20, 0)
		local g = m.state.geometry
		expect(not pick(m, { ax = 0, ay = g.halfWidth - 0.5, bx = -30, by = 0 }), "on a cushion")
		expect(
			not pick(m, { ax = g.halfLength - 2, ay = g.halfWidth - 2, bx = -30, by = 0 }),
			"a pocket"
		)
		expect(not pick(m, { ax = 20.5, ay = 0, bx = -30, by = 10 }), "on a ball")
		expect(not pick(m, { ax = 0, ay = 0, bx = 5, by = 0 }), "too close together")
		expect(not pick(m, { ax = 0 / 0, ay = 0, bx = 5, by = 0 }), "a forged value")
		expect(pick(m, { ax = 0, ay = 10, bx = -30, by = -10 }), "a good pair")
		local wire = E.acceptShot(m, 11, payload(m, 0, 0.1), m.phaseStartedAt)
		expect(wire and #wire.overrides.Pick == 4, "the spots ride in the overrides")
	end)
end

function tests.area_abilities_get_the_opponents_balls_and_never_the_eight_or_cue()
	local m = midGame()
	armNow(m, "Magnet")
	local wire = E.acceptShot(m, 11, missShot(m), m.phaseStartedAt)
	local opp = wire.overrides.OppTargets
	expect(opp ~= nil and #opp == 7, "the stripes")
	for _, id in opp do
		expect(id >= 9, "only stripes")
	end
	for _, id in wire.overrides.Targets do
		expect(id >= 1 and id <= 7, "yours are the solids")
	end
end

return tests
