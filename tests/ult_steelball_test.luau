--!strict
-- Steel Ball (docs/prompts/ABILITIES_PROMPT.md 7.10): the first ball the cue ball hits, if it
-- is yours, always goes in; the cue ball then curves to your next nearest ball and lines it up
-- (never in, even beside a pocket: one pot a use) and stops behind it; with your group gone the
-- 8 is lined up, never potted; the legal 8 goes into the called pocket; the opponent's first
-- ball guides nothing; never a scratch from the guidance; the client's replay matches the
-- server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")

local geometry = V.geometry
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

local function armed(balls: { any }, targets: { number }, eightPocket: number?): any
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.armEffect(sim, "SteelBall", targets, eightPocket, { OppTargets = {} })
	return sim
end

local function run(sim: any): { any }
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

local function ball(sim: any, id: number): any
	return assert(Simulation.findBall(sim, id), "ball " .. id)
end

local function firstContact(events: { any }): number?
	for _, ev in events do
		if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
			return if ev.ball == 0 then ev.other else ev.ball
		end
	end
	return nil
end

local tests = {}

function tests.your_first_ball_always_goes_in_and_the_cue_ball_never_scratches()
	local r = V.rng(5)
	local own, scratched = 0, 0
	for _, ts in V.states(60, 23) do
		local plan = V.shots(ts, 1)[1]
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, V.noisy(plan, 2, V.gauss(r), V.gauss(r)))
		local ids = V.ownIds(ts)
		Simulation.armEffect(sim, "SteelBall", ids, nil, { OppTargets = {} })
		local outcome = Simulation.settle(sim, { strike })
		local first = firstContact(outcome.events)
		if first and first ~= 8 and table.find(ids, first) then
			own += 1
			check(ball(sim, first).pocketed, "the first ball " .. first .. " went in")
			if ball(sim, 0).pocketed then
				scratched += 1
			end
			check(not ball(sim, 8).pocketed, "the 8 stays up")
		end
	end
	check(own >= 40, "enough first contacts with your ball: " .. own)
	check(scratched == 0, "no scratch: " .. scratched)
end

function tests.the_opponents_first_ball_guides_nothing()
	-- The 9 (theirs) is hit first; the 1 (yours) is left alone.
	local balls = table_({ { 0, -20, 0 }, { 9, -10, 0 }, { 1, 20, 10 } })
	local sim = armed(balls, { 1 })
	rolling(ball(sim, 0), 60, 0)
	local events = run(sim)
	check(#ultEvents(events, "guide") == 0 and #ultEvents(events, "steel") == 0, "nothing")
end

function tests.the_next_ball_near_a_pocket_is_lined_up_not_potted()
	-- The 1 first; the 2 sits by the top-left corner with a clean line in.
	local balls = table_({ { 0, -20, -5 }, { 1, -10, -5 }, { 2, -40, 18 } })
	local sim = armed(balls, { 1, 2 })
	rolling(ball(sim, 0), 60, 0)
	local events = run(sim)
	check(ball(sim, 1).pocketed, "the 1 in")
	check(#ultEvents(events, "curve") == 1, "curved on to the 2")
	check(not ball(sim, 2).pocketed, "the 2 stays up")
	check(not ball(sim, 0).pocketed, "no scratch")
	local guides = ultEvents(events, "guide")
	check(#guides == 2 and guides[2].ball == 2 and guides[2].value == 0, "the 2 lined up")
end

function tests.a_far_ball_is_lined_up_and_the_cue_ball_stops_behind_it()
	local balls = table_({ { 0, -20, -5 }, { 1, -10, -5 }, { 2, -25, 10 } })
	local sim = armed(balls, { 1, 2 })
	rolling(ball(sim, 0), 60, 0)
	local events = run(sim)
	check(ball(sim, 1).pocketed, "the 1 in")
	local b2, cue = ball(sim, 2), ball(sim, 0)
	check(not b2.pocketed and not cue.pocketed, "the 2 and the cue ball stay up")
	local guides = ultEvents(events, "guide")
	local last = guides[#guides]
	check(last and last.ball == 2 and last.value == 0, "the 2 lined up")
	-- The cue ball, the 2 and the pocket nearly in a line (a straight shot next).
	local px, py = last.x, last.y
	local ax, ay = b2.x - cue.x, b2.y - cue.y
	local bx, by = px - b2.x, py - b2.y
	local cos = (ax * bx + ay * by) / math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by))
	check(cos > 0.97, ("lined up: cos %.3f"):format(cos))
	-- Closer to its pocket than it was, and stopped short of it.
	local d0 = math.sqrt((-25 - px) ^ 2 + (10 - py) ^ 2)
	local d1 = math.sqrt(bx * bx + by * by)
	check(d1 < d0 - 5, ("pushed closer: %.1f -> %.1f"):format(d0, d1))
end

function tests.with_your_group_gone_the_8_is_lined_up_never_potted()
	-- The 1 is your last ball; the 8 sits near the bottom-right corner.
	local balls = table_({ { 0, -20, -5 }, { 1, -10, -5 }, { 8, 40, -18 } })
	local sim = armed(balls, { 1 })
	rolling(ball(sim, 0), 60, 0)
	local events = run(sim)
	check(ball(sim, 1).pocketed, "the 1 in")
	check(not ball(sim, 8).pocketed, "the 8 stays up")
	check(not ball(sim, 0).pocketed, "no scratch")
	local guides = ultEvents(events, "guide")
	check(guides[#guides].ball == 8 and guides[#guides].value == 0, "the 8 lined up")
end

function tests.the_legal_8_goes_into_the_called_pocket()
	-- The 8 hit toward the bottom-right, called into the top-left (pocket 1).
	local balls = table_({ { 0, -20, 0 }, { 8, -10, 0 } })
	local sim = armed(balls, { 8 }, 1)
	rolling(ball(sim, 0), 60, -8)
	run(sim)
	check(ball(sim, 8).pocketed, "the 8 in")
	check(ball(sim, 8).pocket == 1, "the called pocket: " .. tostring(ball(sim, 8).pocket))
end

function tests.one_pot_a_use_however_many_are_close()
	-- Six of yours spread out, every one close to a corner with a clean line in.
	local balls = table_({
		{ 0, -20, -5 },
		{ 1, -10, -5 },
		{ 2, -40, 18 },
		{ 3, 40, 18 },
		{ 4, -40, -18 },
		{ 5, 40, -18 },
		{ 6, 30, 22 },
	})
	local sim = armed(balls, { 1, 2, 3, 4, 5, 6 })
	rolling(ball(sim, 0), 60, 0)
	local events = run(sim)
	local guides = ultEvents(events, "guide")
	check(#guides == 2 and guides[1].value == 1 and guides[2].value == 0, "one in, one lined up")
	check(Config.Ults.Catalog.SteelBall.MaxBalls == 1, "the catalog says one")
	local potted = 0
	for _, b in sim.balls do
		if b.id ~= 0 and b.pocketed then
			potted += 1
		end
	end
	check(potted == 1, "pots: " .. potted)
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 43)
	local r = V.rng(8)
	local compared, used = 0, 0
	for _, ts in states do
		local plan = V.shots(ts, 1)[1]
		local payload = V.noisy(plan, 2, V.gauss(r), V.gauss(r))
		local ids = V.ownIds(ts)
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "SteelBall", ids, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(ball(sim, 0))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		if #ultEvents(outcome.events, "guide") > 1 then
			used += 1
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "SteelBall", ids, nil, { OppTargets = {} })
		ShotInput.quantiseSeed(ball(replay, 0))
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
	check(used >= 3, "some curved on to a second ball: " .. used)
end

return tests
