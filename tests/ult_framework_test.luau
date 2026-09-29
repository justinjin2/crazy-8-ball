--!strict
-- The ability framework's physics hooks (docs/prompts/ABILITIES_PROMPT.md 5.2): an effect's
-- `after` hook sees the cue ball's first contact the step it happens; Ops.remove takes a ball
-- out of play counted as pocketed (ShotJudge); per-ball filters (PhaseCue, fx.ghost); the cue
-- ball's own material; Ops.halt pauses a shot so it can be continued to the same bits;
-- Ops.teleport; finish at rest; and nothing leaks into the next shot.
--
-- The test effects are put into the registry here (the harness caches modules, so the table
-- Simulation reads is this one) and removed again after each test.

local H = require("./harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Simulation = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local Effects = H.require("Ults.Effects")
local Catalog = H.require("Ults.Catalog")

local geometry = TableGeometry.build({ pocketsOpen = true })
local R = Config.Balls.RadiusInches
local DT = Config.Physics.FixedStep

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function state(spots: { { number } }): any
	local balls = {}
	for _, spot in spots do
		table.insert(balls, Ball.new(spot[1], spot[2], spot[3]))
	end
	return Simulation.newState(geometry, balls)
end

-- A rolling strike along +x (or `vx, vy`) on the cue ball of `s`.
local function roll(s: any, vx: number, vy: number?)
	local cue = assert(Simulation.findBall(s, 0))
	cue.vx, cue.vy = vx, vy or 0
	cue.wx, cue.wy = -(vy or 0) / R, vx / R
	s.time = 0
	s.fx = nil
	s.halted = nil
end

local function run(s: any, overrides: any?): any
	s.overrides = overrides
	return Simulation.settle(s, { { t = 0, type = "cueStrike", ball = 0, speed = 1 } })
end

local function with(name: string, effect: any, body: () -> ())
	Effects[name] = effect
	local ok, err = pcall(body)
	Effects[name] = nil
	if not ok then
		error(err, 0)
	end
end

local function count(events: { any }, kind: string, ball: number?): number
	local n = 0
	for _, ev in events do
		if ev.type == kind and (ball == nil or ev.ball == ball or ev.other == ball) then
			n += 1
		end
	end
	return n
end

-- Removes the first ball the cue ball touches, the step it touches it.
local SHATTER = {
	after = function(s: any, _dt: number, events: { any }, ops: any)
		if s.fx.done then
			return
		end
		for _, ev in events do
			if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				local id = if ev.ball == 0 then ev.other else ev.ball
				s.fx.done = true
				ops.remove(s, events, assert(Simulation.findBall(s, id)), "shatter")
				ops.emit(s, events, "shatter", id)
				return
			end
		end
	end,
}

local tests = {}

function tests.a_removed_ball_counts_as_pocketed_for_its_owner_and_stops_colliding()
	with("TestShatter", SHATTER, function()
		local s = state({ { 0, -20, 0 }, { 3, 0, 0 }, { 11, 10, 0 } })
		local before = Ball.cloneList(s.balls)
		roll(s, 60)
		local out = run(s, { Effect = "TestShatter", Targets = { 3 } })
		check(count(out.events, "removed", 3) == 1, "ball 3 should be removed once")
		check(count(out.events, "ult") == 1, "the effect's look event")
		local three = assert(Simulation.findBall({ balls = out.finalBalls } :: any, 3))
		check(three.pocketed and not three.offTable and three.pocket == nil, "removed = pocketed")
		check(three.x > -1 and three.x < 1 and three.y == 0, "it stays where it was taken")
		-- The cue ball met ball 3 once and nothing after: it went on through where 3 was.
		check(count(out.events, "ballHit", 3) == 1, "no contact with a removed ball")
		local j = Judge.resolve(before, out, { "solids", "stripes" }, 1, false, nil, false)
		check(j.foul == nil, "a legal first contact")
		check(j.keep == true, "your own ball removed keeps the turn")
		check(#j.drops == 1 and j.drops[1].ball == 3, "counted as a drop")
	end)
end

function tests.an_opponents_removed_ball_is_theirs_and_gives_no_turn()
	with("TestShatter", SHATTER, function()
		local s = state({ { 0, -20, 0 }, { 11, 0, 0 } })
		local before = Ball.cloneList(s.balls)
		roll(s, 60)
		local out = run(s, { Effect = "TestShatter", Targets = {} })
		local j = Judge.resolve(before, out, { "solids", "stripes" }, 1, false, nil, false)
		check(j.foul == "WrongContact", "a wrong first ball is still a foul")
		check(j.keep == false, "no turn from an opponent's ball")
		check(j.pockets[1] == 11, "still counted as pocketed (for its owner)")
	end)
end

function tests.the_eight_removed_follows_the_eight_rules()
	with("TestShatter", SHATTER, function()
		-- Early: a loss.
		local s = state({ { 0, -20, 0 }, { 8, 0, 0 }, { 2, 20, 10 } })
		local before = Ball.cloneList(s.balls)
		roll(s, 60)
		local out = run(s, { Effect = "TestShatter", Targets = {} })
		local j = Judge.resolve(before, out, { "solids", "stripes" }, 1, false, nil, false)
		check(j.winner == 2, "an early 8 loses")
		-- The legal 8 shot: a win, whatever the call (it went in no pocket).
		s = state({ { 0, -20, 0 }, { 8, 0, 0 } })
		before = Ball.cloneList(s.balls)
		for id = 1, 7 do
			local b = Ball.new(id, 0, 0)
			b.pocketed = true
			table.insert(before, b)
			table.insert(s.balls, Ball.clone(b))
		end
		roll(s, 60)
		out = run(s, { Effect = "TestShatter", Targets = { 8 }, EightPocket = 3 })
		j = Judge.resolve(before, out, { "solids", "stripes" }, 1, false, 3, false)
		check(j.winner == 1 and j.reason == "LegalEight", "the legal 8 removed wins")
	end)
end

function tests.the_cue_ball_phases_through_listed_balls_only()
	local s = state({ { 0, -20, 0 }, { 9, 0, 0 }, { 3, 12, 0 } })
	local before = Ball.cloneList(s.balls)
	roll(s, 80)
	local out = run(s, { PhaseCue = { 9 } })
	check(count(out.events, "ballHit", 9) == 0, "no contact with a phased ball")
	check(out.firstContact == 3, "the first contact is the next real ball")
	local nine = assert(Simulation.findBall({ balls = out.finalBalls } :: any, 9))
	check(nine.x == 0 and nine.y == 0, "the phased ball never moved")
	local j = Judge.resolve(before, out, { "solids", "stripes" }, 1, false, nil, false)
	check(j.foul == nil, "passing through is not a contact")
	-- Without the filter the same shot hits 9 first.
	s = state({ { 0, -20, 0 }, { 9, 0, 0 }, { 3, 12, 0 } })
	roll(s, 80)
	out = run(s, nil)
	check(out.firstContact == 9, "normally 9 is hit")
end

function tests.a_ghost_ball_takes_part_in_no_contact_while_it_moves()
	local GHOST = {
		step = function(s: any, _dt: number)
			s.fx.ghost = s.fx.ghost or { [3] = true }
		end,
	}
	with("TestGhost", GHOST, function()
		local s = state({ { 0, -30, 0 }, { 3, -20, 0 }, { 9, 0, 0 } })
		local three = assert(Simulation.findBall(s, 3))
		three.vx, three.wy = 80, 80 / R
		s.time, s.fx = 0, nil
		local out = run(s, { Effect = "TestGhost", Targets = {} })
		check(count(out.events, "ballHit") == 0, "the ghost ball touched nothing")
		local after = assert(Simulation.findBall({ balls = out.finalBalls } :: any, 3))
		check(after.x > 5 or after.pocketed, "it went on through the 9")
	end)
end

function tests.the_cue_material_lasts_until_its_time_then_normal()
	local function distance(overrides: any?): number
		local s = state({ { 0, -45, 0 } })
		roll(s, 12)
		local out = run(s, overrides)
		return assert(Simulation.findBall({ balls = out.finalBalls } :: any, 0)).x + 45
	end
	local mu = Config.Physics.RollingFriction * 0.5
	local plain = distance(nil)
	local slick = distance({ CueRollingFriction = mu, CueUntil = 30 })
	local brief = distance({ CueRollingFriction = mu, CueUntil = 0.5 })
	check(slick > plain * 1.5, ("less friction rolls further (%.1f vs %.1f)"):format(slick, plain))
	check(brief < slick and brief > plain, "the material ends at CueUntil")
end

function tests.super_bouncy_cushions_act_on_the_cue_ball_only()
	local s = state({ { 0, 0, 0 } })
	roll(s, 0, 60)
	local out = run(s, { CueRailRestitution = 1, CueRailFriction = 0, CueUntil = 1 })
	local rails = 0
	for _, ev in out.events do
		if ev.type == "railHit" and ev.ball == 0 and ev.t < 1 then
			rails += 1
		end
	end
	local s2 = state({ { 0, 0, 0 } })
	roll(s2, 0, 60)
	local plain = run(s2, nil)
	local plainRails = 0
	for _, ev in plain.events do
		if ev.type == "railHit" and ev.t < 1 then
			plainRails += 1
		end
	end
	check(rails >= plainRails, "at least as many cushions in the first second")
end

function tests.a_halted_shot_continues_to_the_same_bits()
	local HALT = {
		after = function(s: any, _dt: number, _events: { any }, ops: any)
			if not s.fx.halted and s.time >= 0.5 then
				s.fx.halted = true
				ops.halt(s)
			end
		end,
	}
	with("TestHalt", HALT, function()
		local spots = { { 0, -30, 2 }, { 1, 0, 0 }, { 2, 3, 1.3 }, { 3, 3, -1.3 }, { 11, 20, 7 } }
		local a = state(spots)
		roll(a, 150, 5)
		local first = run(a, { Effect = "TestHalt", Targets = {} })
		check(first.halted == true, "the shot halted")
		check(not Simulation.isAtRest(a), "balls still moving at the halt")
		check(a.overrides ~= nil and a.fx ~= nil, "a halted state keeps its overrides and scratch")
		local rest = Simulation.settle(a, first.events)
		check(not rest.halted, "then settles to rest")
		check(a.overrides == nil and a.fx == nil and a.halted == nil, "cleared at rest")
		-- The same shot never halted (the effect's hook is the same, the halt ignored).
		local b = state(spots)
		roll(b, 150, 5)
		b.overrides = { Effect = "TestHalt", Targets = {} }
		b.fx = { halted = true }
		local whole = Simulation.settle(b, { { t = 0, type = "cueStrike", ball = 0, speed = 1 } })
		check(
			Simulation.checksum(rest.finalBalls) == Simulation.checksum(whole.finalBalls),
			"halting and continuing lands on the same bits"
		)
	end)
end

function tests.a_teleported_ball_keeps_its_motion_and_strikes_a_ball_it_lands_on()
	local PORTAL = {
		after = function(s: any, _dt: number, events: { any }, ops: any)
			local b = assert(Simulation.findBall(s, 5))
			if not s.fx.done and b.x >= -10 then
				s.fx.done = true
				ops.teleport(s, events, b, 20, 0)
			end
		end,
	}
	with("TestPortal", PORTAL, function()
		local s = state({ { 0, -40, 15 }, { 5, -30, 0 }, { 12, 20 + 2 * R - 0.2, 0 } })
		local five = assert(Simulation.findBall(s, 5))
		five.vx, five.wy = 50, 50 / R
		s.time = 0
		local out = run(s, { Effect = "TestPortal", Targets = {} })
		local hit = false
		for _, ev in out.events do
			if ev.type == "ballHit" and ev.ball == 5 and ev.other == 12 then
				hit = true
			end
		end
		check(hit, "it struck the ball at the exit")
		local twelve = assert(Simulation.findBall({ balls = out.finalBalls } :: any, 12))
		check(twelve.x > 22 or twelve.pocketed, "the struck ball moved on")
	end)
end

function tests.finish_runs_once_at_rest_and_the_client_loop_matches_the_settle()
	local FINISH = {
		after = SHATTER.after,
		finish = function(s: any, _events: { any }, _ops: any)
			s.fx.finished = (s.fx.finished or 0) + 1
			local cue = assert(Simulation.findBall(s, 0))
			cue.x += 1 -- a visible nudge, so both sides must run it
		end,
	}
	with("TestFinish", FINISH, function()
		local spots = { { 0, -30, 3 }, { 4, 0, 0 }, { 6, 10, -6 }, { 13, 25, 10 } }
		local a = state(spots)
		roll(a, 120, -8)
		local server = run(a, { Effect = "TestFinish", Targets = { 4 } })
		-- The client's replay: step by step, finish at rest (Match.update's order).
		local b = state(spots)
		roll(b, 120, -8)
		b.overrides = { Effect = "TestFinish", Targets = { 4 } }
		local events = {}
		local guard = 0
		while not Simulation.isAtRest(b) and guard < 20000 do
			Simulation.step(b, DT, events)
			guard += 1
		end
		Simulation.finishShot(b, events)
		check(b.fx.finished == 1, "finish ran once")
		check(
			Simulation.checksum(server.finalBalls) == Simulation.checksum(b.balls),
			"the client's replay matches the server's settle"
		)
	end)
end

function tests.nothing_an_effect_set_leaks_into_the_next_shot()
	with("TestShatter", SHATTER, function()
		local s = state({ { 0, -20, 0 }, { 3, 0, 0 }, { 5, 20, 10 } })
		roll(s, 60)
		run(s, { Effect = "TestShatter", Targets = { 3 }, PhaseCue = { 5 }, CueUntil = 9 })
		check(s.overrides == nil and s.fx == nil and s.halted == nil, "all cleared")
		-- A plain strike on a used state starts clean.
		Simulation.strike(s, { angle = 0, power = 0.2, spin = { x = 0, y = 0 } })
		check(s.overrides == nil and s.fx == nil, "strike clears them")
	end)
end

function tests.slow_moments_add_their_wall_seconds_to_the_outcome()
	local SLOW = {
		after = function(s: any, _dt: number, events: { any }, ops: any)
			if not s.fx.slowed then
				s.fx.slowed = true
				ops.emit(s, events, "slow", 0, nil, 0.3, nil, 0.9)
			end
		end,
	}
	with("TestSlow", SLOW, function()
		local s = state({ { 0, -20, 0 } })
		roll(s, 30)
		local out = run(s, { Effect = "TestSlow", Targets = {} })
		check(math.abs((out.extraSeconds or 0) - 0.9) < 1e-12, "0.9 s more for the clients")
	end)
end

function tests.every_ult_has_its_uploaded_icon()
	for _, id in Config.Ults.Order do
		local icon = Catalog.icon(id)
		check(icon:match("^rbxassetid://%d+$") ~= nil, id .. " has an icon image id")
	end
	check(Catalog.icon("Nope") == "", "an unknown id has none")
end

return tests
