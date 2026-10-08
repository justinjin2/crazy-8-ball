--!strict
-- Time Stop's Rare+ buff (2026-10-08): a ball of yours the cue ball touches in stopped time is
-- sent (a `sent` event the moment it is touched) and, when time resumes, its stored motion is
-- dropped and it rolls down a clear line into that pocket. The opponent's resumes as before:
-- its stored motion added to what the strike gave it.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Cue = H.require("Physics.Cue")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local TimeStop = H.require("Ults.Effects.TimeStop")

local geometry = V.geometry
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

local function ultEvents(events: { any }, kind: string): { any }
	local out = {}
	for _, ev in events do
		if ev.type == "ult" and ev.kind == kind then
			table.insert(out, ev)
		end
	end
	return out
end

-- Step until rest or a halt.
local function run(sim: any, events: { any })
	for _ = 1, 40000 do
		if Simulation.isAtRest(sim) or sim.halted then
			return
		end
		Simulation.step(sim, DT, events)
	end
	error("never settled")
end

-- The cue ball at (-30, 0) strikes the 3 at (-15, 0) straight along +x (the shot), which
-- freezes FreezeAfterSeconds after the contact with the 3 still rolling. In stopped time the
-- cue ball is struck at where the 3 froze. Returns the state at the second halt (after the
-- stopped-time strike, before time resumes) and the events so far.
local function struckInStoppedTime(own: { number }, opp: { number }): (any, { any })
	local sim =
		Simulation.newState(geometry, table_({ { 0, -30, 0 }, { 3, -15, 0 }, { 1, -40, 18 } }))
	local events = {}
	table.insert(
		events,
		Simulation.strike(sim, assert(ShotInput.validate({ angle = 0, power = 0.2 }, nil), "shot"))
	)
	Simulation.armEffect(sim, "TimeStop", own, nil, { OppTargets = opp })
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
	run(sim, events)
	check(sim.halted and TimeStop.isFrozen(sim), "frozen after the first contact")
	local three = assert(Simulation.findBall(sim, 3), "the 3")
	check(three.vx > 0, "the 3 frozen mid-roll")
	local cue = assert(Simulation.findBall(sim, 0), "cue")
	local probe = Ball.clone(cue)
	local angle = math.atan2(three.y - cue.y, three.x - cue.x)
	Cue.strike(probe, assert(ShotInput.validate({ angle = angle, power = 0.15 }, nil), "strike"))
	TimeStop.beginStrike(sim, ShotInput.quantiseSeed(probe))
	run(sim, events)
	check(sim.halted, "the strike's part halts")
	check(#ultEvents(events, "strikeFrozen") == 1, "the cue ball touched the 3")
	return sim, events
end

local tests = {}

function tests.yours_struck_in_stopped_time_rolls_into_its_pocket()
	local sim, events = struckInStoppedTime({ 3 }, {})
	local sent = ultEvents(events, "sent")
	check(#sent == 1 and sent[1].ball == 3 and sent[1].other ~= nil, "the 3 sent")
	local pocket = geometry.pockets[sent[1].other]
	TimeStop.resume(sim)
	local three = assert(Simulation.findBall(sim, 3), "the 3")
	-- Down the line into that pocket, rolling: its stored motion dropped.
	local dx, dy = pocket.x - three.x, pocket.y - three.y
	local d = math.sqrt(dx * dx + dy * dy)
	local speed = math.sqrt(three.vx ^ 2 + three.vy ^ 2)
	check((three.vx * dx + three.vy * dy) / (speed * d) > 0.99, "heading for its pocket")
	check(math.abs(three.wy - three.vx / Config.Balls.RadiusInches) < 1e-9, "rolling")
	run(sim, events)
	Simulation.finishShot(sim, events)
	local into = nil
	for _, ev in events do
		if ev.type == "pocket" and ev.ball == 3 then
			into = ev.other
		end
	end
	check(into == pocket.id, ("dropped into pocket %d: %s"):format(pocket.id, tostring(into)))
end

function tests.theirs_struck_in_stopped_time_resumes_as_before()
	local sim, events = struckInStoppedTime({ 1 }, { 3 })
	check(#ultEvents(events, "sent") == 0, "nothing sent")
	local index, three = 0, nil
	for i, b in sim.balls do
		if b.id == 3 then
			index, three = i, b
		end
	end
	assert(three, "the 3")
	local stored = sim.fx.stored[index]
	local vx, vy = three.vx + stored[1], three.vy + stored[2]
	TimeStop.resume(sim)
	check(three.vx == vx and three.vy == vy, "its stored motion added to the strike's push")
end

return tests
