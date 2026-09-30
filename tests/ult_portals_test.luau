--!strict
-- Portals (docs/prompts/ABILITIES_PROMPT.md 7.9): any ball whose centre passes through a
-- portal's inner circle comes out of the other one with the same motion, exactly; a fast ball
-- cannot skip one; a loop through both ends; a ball on the exit is struck; the cue ball can go
-- through into a pocket (a scratch); no pick, no portals; the client's replay matches the
-- server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Arming = H.require("Ults.Arming")

local geometry = V.geometry
local P = Config.Ults.Portals
local R = Config.Balls.RadiusInches
local DT = Config.Physics.FixedStep

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function table_(spots: { { number } }): { any }
	local balls = {}
	for _, s in spots do
		table.insert(balls, Ball.new(s[1], s[2], s[3]))
	end
	return balls
end

local function rolling(b: any, vx: number, vy: number)
	b.vx, b.vy = vx, vy
	b.wx, b.wy = -vy / R, vx / R
end

-- A state with the portals armed at A (ax, ay) and B (bx, by).
local function armed(balls: { any }, pick: { number }?): any
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.armEffect(sim, "Portals", {}, nil, { OppTargets = {}, Pick = pick })
	return sim
end

-- Step until rest (or `until` returns true after a step). Returns every event.
local function run(sim: any, stop: ((events: { any }) -> boolean)?): { any }
	local all = {}
	for _ = 1, 40000 do
		if Simulation.isAtRest(sim) then
			break
		end
		local events = {}
		Simulation.step(sim, DT, events)
		for _, ev in events do
			table.insert(all, ev)
		end
		if stop and stop(events) then
			break
		end
	end
	return all
end

local function ultEvents(events: { any }, kind: string): { any }
	local out = {}
	for _, ev in events do
		if ev.type == "ult" and ev.kind == kind then
			table.insert(out, ev)
		end
	end
	return out
end

local tests = {}

function tests.a_ball_comes_out_of_the_other_portal_with_the_same_motion()
	-- The 3 rolls along y = 0 into A at (-10, 0); B is at (20, 15).
	local balls = table_({ { 0, -40, -20 }, { 3, -25, 0 } })
	rolling(balls[2], 60, 0)
	local sim = armed(balls, { -10, 0, 20, 15 })
	local before: any = nil
	run(sim, function(events)
		for _, ev in events do
			if ev.type == "ult" and ev.kind == "exit" then
				return true
			end
		end
		before = Ball.clone(assert(Simulation.findBall(sim, 3), "the 3"))
		return false
	end)
	local b = assert(Simulation.findBall(sim, 3), "the 3")
	check(b.x == 20 and b.y == 15, ("out at B: %.3f, %.3f"):format(b.x, b.y))
	-- One step of rolling friction since `before`: the heading and the spin agree with it.
	check(b.vy == 0 and b.vx > 0 and b.vx <= before.vx, "same heading, same speed")
	check(math.abs(b.wy - b.vx / R) < 1e-9 and b.wx == 0, "the spin carried over")
end

function tests.a_fast_ball_cannot_skip_a_portal()
	-- At full speed a ball moves about 2 in a step, as wide as the inner circle: it still goes in
	-- when its path passes 1 in from the centre.
	local balls = table_({ { 0, -40, -20 }, { 3, -30, 1 } })
	rolling(balls[2], 440, 0)
	local sim = armed(balls, { 0, 0, 30, -15 })
	local events = run(sim, function(evs)
		return #ultEvents(evs, "exit") > 0
	end)
	check(#ultEvents(events, "enter") == 1, "went in")
end

function tests.a_ball_passing_outside_the_inner_circle_is_untouched()
	local balls = table_({ { 0, -40, -20 }, { 3, -30, P.InnerRadiusInches + 0.3 } })
	rolling(balls[2], 80, 0)
	local sim = armed(balls, { 0, 0, 30, -15 })
	local events = run(sim)
	check(#ultEvents(events, "enter") == 0, "not in")
end

function tests.a_loop_through_both_portals_ends()
	-- A at (0, 0), B at (-20, 0), the ball rolling +x: out of B it runs back into A, round and
	-- round until friction stops it.
	local balls = table_({ { 0, -40, -20 }, { 3, -30, 0 } })
	rolling(balls[2], 150, 0)
	local sim = armed(balls, { 0, 0, -20, 0 })
	local events = run(sim)
	check(Simulation.isAtRest(sim), "came to rest")
	local enters = #ultEvents(events, "enter")
	check(enters >= 3, "looped a few times: " .. enters)
	-- Never straight back in: consecutive passes are at least the cooldown apart.
	local last = -math.huge
	for _, ev in ultEvents(events, "enter") do
		check(ev.t - last >= P.CooldownSeconds - 1e-9, "the cooldown holds")
		last = ev.t
	end
end

function tests.a_ball_on_the_exit_is_struck()
	-- The 5 rests on B; the 3 comes through and hits it at once.
	local balls = table_({ { 0, -40, -20 }, { 3, -25, 0 }, { 5, 20.5, 15 } })
	rolling(balls[2], 60, 0)
	local sim = armed(balls, { -10, 0, 20, 15 })
	local events = run(sim)
	local struck = false
	for _, ev in events do
		if
			ev.type == "ballHit"
			and ((ev.ball == 3 and ev.other == 5) or (ev.ball == 5 and ev.other == 3))
		then
			struck = true
		end
	end
	check(struck, "the 5 was struck")
	local a, b = assert(Simulation.findBall(sim, 3), "3"), assert(Simulation.findBall(sim, 5), "5")
	local dx, dy = a.x - b.x, a.y - b.y
	check(a.pocketed or b.pocketed or dx * dx + dy * dy >= 4 * R * R - 1e-6, "not left overlapping")
end

function tests.the_cue_ball_through_a_portal_into_a_pocket()
	-- The cue ball rolls diagonally into A; B sits on the top-right corner's diagonal, so it
	-- comes out heading straight for that pocket.
	local balls = table_({ { 0, -30, 0 }, { 1, -30, -20 } })
	local sim = armed(balls, { -20, 10, 40, 15 })
	rolling(assert(Simulation.findBall(sim, 0), "cue"), 50, 50)
	local events = run(sim)
	check(#ultEvents(events, "enter") >= 1, "through the portal")
	local scratched = false
	for _, ev in events do
		if ev.type == "pocket" and ev.ball == 0 then
			scratched = true
		end
	end
	check(scratched, "the cue ball dropped")
	check(Simulation.findBall(sim, 0).pocketed, "pocketed")
end

function tests.no_pick_no_portals()
	local balls = table_({ { 0, -40, -20 }, { 3, -30, 0 } })
	rolling(balls[2], 80, 0)
	local sim = armed(balls, nil)
	local events = run(sim)
	check(#ultEvents(events, "enter") == 0, "nothing")
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 41)
	local r = V.rng(6)
	local compared, used = 0, 0
	for _, ts in states do
		-- Two clear spots from the harness's own planner-style scan.
		local pick = nil
		for _ = 1, 60 do
			local request = {
				ax = (V.uniform(r) * 2 - 1) * 40,
				ay = (V.uniform(r) * 2 - 1) * 20,
				bx = (V.uniform(r) * 2 - 1) * 40,
				by = (V.uniform(r) * 2 - 1) * 20,
			}
			pick = Arming.pick("Portals", request, geometry, ts.groups, 1, ts.balls)
			if pick then
				break
			end
		end
		if pick == nil then
			continue
		end
		local payload = { angle = V.uniform(r) * 2 * math.pi, power = 0.4 + V.uniform(r) * 0.6 }
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "Portals", {}, nil, { OppTargets = {}, Pick = pick })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		if #ultEvents(outcome.events, "enter") > 0 then
			used += 1
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "Portals", {}, nil, { OppTargets = {}, Pick = pick })
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "cue"))
		run(replay)
		Simulation.finishShot(replay, {})
		for i, b in sim.balls do
			local c = replay.balls[i]
			check(
				b.x == c.x and b.y == c.y and b.pocketed == c.pocketed,
				"ball " .. b.id .. " matches"
			)
		end
		compared += 1
	end
	check(compared >= 10, "enough shots compared: " .. compared)
	check(used >= 2, "some went through a portal: " .. used)
end

function tests.your_ball_comes_out_turned_toward_a_pocket()
	-- The 1 rolls into A heading +x and comes out of B (20, 10) still heading +x; the
	-- top-right corner is about 27 degrees to the left of that: yours is turned toward it by
	-- the cap (ExitSteerTan), the opponent's (and a ball of nobody's) not at all.
	local function exitAngle(targets: { number }, opp: { number }): number
		local sim = Simulation.newState(geometry, table_({ { 0, -40, -20 }, { 1, -30, 0 } }))
		Simulation.armEffect(
			sim,
			"Portals",
			targets,
			nil,
			{ OppTargets = opp, Pick = { -20, 0, 20, 10 } }
		)
		rolling(sim.balls[2], 60, 0)
		run(sim, function(events)
			return #ultEvents(events, "exit") > 0
		end)
		local b = sim.balls[2]
		return math.deg(math.atan2(b.vy, b.vx))
	end
	local cap = math.deg(math.atan(P.ExitSteerTan))
	local mine = exitAngle({ 1 }, {})
	check(math.abs(mine - cap) < 0.5, ("yours turned %.2f degrees (cap %.2f)"):format(mine, cap))
	check(math.abs(exitAngle({}, { 1 })) < 1e-9, "the opponent's comes out as it went in")
	check(math.abs(exitAngle({}, {})) < 1e-9, "a ball of nobody's too")
end

return tests
