--!strict
-- Chain Lightning (docs/prompts/ABILITIES_PROMPT.md 7.8, the skill rule 5.7): the first ball
-- of yours hit is charged (sent down a clear line into a pocket, sped up; with no clear line
-- turned toward its best pocket by at most the cap), then
-- the lightning jumps ball to ball, whoever's, never the cue ball or the 8 (unless it is your
-- legal 8), at most 2 of theirs, each struck ball pushed toward its pocket, theirs at half.
-- The first ball not yours: nothing. The client's step-by-step replay matches the settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Arming = H.require("Ults.Arming")
local ChainLightning = H.require("Ults.Effects.ChainLightning")

local geometry = V.geometry
local C = Config.Ults.ChainLightning
local S = Config.Ults.Shared
local DT = Config.Physics.FixedStep

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function near(a: number, b: number, tolerance: number): boolean
	return math.abs(a - b) <= tolerance
end

local function table_(spots: { { number } }): { any }
	local balls = {}
	for _, s in spots do
		table.insert(balls, Ball.new(s[1], s[2], s[3]))
	end
	return balls
end

-- A shot straight from the cue ball at ball `at`, armed with Chain Lightning (or not), stepped
-- to rest the way a client replays it. Returns the state and every event.
local function shoot(
	balls: { any },
	at: number,
	power: number,
	on: boolean,
	own: { number },
	opp: { number },
	eightPocket: number?
): (any, { any })
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local cue = assert(Simulation.findBall(sim, 0), "a cue ball")
	local target = assert(Simulation.findBall(sim, at), "the target")
	local angle = math.atan2(target.y - cue.y, target.x - cue.x)
	local events = {}
	table.insert(
		events,
		Simulation.strike(
			sim,
			assert(ShotInput.validate({ angle = angle, power = power }, nil), "shot")
		)
	)
	if on then
		Simulation.armEffect(sim, "ChainLightning", own, eightPocket, { OppTargets = opp })
	end
	ShotInput.quantiseSeed(cue)
	local steps = 0
	while not Simulation.isAtRest(sim) and steps < 40000 do
		Simulation.step(sim, DT, events)
		steps += 1
	end
	Simulation.finishShot(sim, events)
	return sim, events
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

local function pocketed(events: { any }, id: number): boolean
	for _, ev in events do
		if ev.type == "pocket" and ev.ball == id then
			return true
		end
	end
	return false
end

local tests = {}

function tests.the_reach_stays_under_the_cap()
	check(C.ReachInches <= S.MaxReachShare * 2 * geometry.halfLength + 1e-9, "reach capped")
	check(C.Links >= 1 and C.Boost >= 1 and C.SteerTan > 0, "sane numbers")
end

function tests.no_lightning_when_the_first_ball_is_theirs()
	-- The cue ball hits the 9 (theirs) first, with the 1 (yours) beside it.
	local balls = table_({ { 0, -20, 0 }, { 9, 0, 0 }, { 1, 5, 8 }, { 2, 10, -6 } })
	local plain = shoot(balls, 9, 0.35, false, { 1, 2 }, { 9 })
	local sim, events = shoot(balls, 9, 0.35, true, { 1, 2 }, { 9 })
	check(#ultEvents(events, "charge") == 0 and #ultEvents(events, "link") == 0, "no lightning")
	for i, b in sim.balls do
		check(b.x == plain.balls[i].x and b.y == plain.balls[i].y, "ball " .. b.id .. " unchanged")
	end
end

function tests.the_8_first_off_the_legal_8_shot_is_not_charged()
	local balls = table_({ { 0, -20, 0 }, { 8, 0, 0 }, { 1, 5, 8 } })
	local _, events = shoot(balls, 8, 0.35, true, { 1 }, {})
	check(#ultEvents(events, "charge") == 0, "no charge on the 8")
end

-- Struck by the cue ball at `angle`, `power` and stepped by hand to the contact: the ball `id`
-- at the charge step, and whether the charge event came, plain (`on` false) or charged.
local function atContact(
	balls: { any },
	id: number,
	angle: number,
	power: number,
	on: boolean,
	own: { number },
	eightPocket: number?
): (any, boolean)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.strike(
		sim,
		assert(ShotInput.validate({ angle = angle, power = power }, nil), "shot")
	)
	if on then
		Simulation.armEffect(sim, "ChainLightning", own, eightPocket, { OppTargets = {} })
	end
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
	for _ = 1, 4000 do
		local events = {}
		Simulation.step(sim, DT, events)
		for _, ev in events do
			if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				return assert(Simulation.findBall(sim, id), "the ball"),
					#ultEvents(events, "charge") == 1
			end
		end
	end
	error("no contact")
end

function tests.the_charge_drives_your_ball_down_a_clear_line_and_it_drops()
	-- The 1 is cut toward the right rail; the bolt sends it down the clear line into the pocket
	-- nearest that heading, rolling, at least the boosted speed, and it drops there.
	local balls = table_({ { 0, -30, -5 }, { 1, 0, 0 } })
	local plain = atContact(balls, 1, 0.17, 0.4, false, { 1 })
	local charged, emitted = atContact(balls, 1, 0.17, 0.4, true, { 1 })
	check(emitted, "the charge event")
	local s0 = math.sqrt(plain.vx ^ 2 + plain.vy ^ 2)
	local s1 = math.sqrt(charged.vx ^ 2 + charged.vy ^ 2)
	check(s1 >= s0 * C.Boost - 1e-6, ("at least boosted: %.4f vs %.4f"):format(s1, s0 * C.Boost))
	-- The line it was sent down is the one lineUp finds from there along the plain heading.
	local probe = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.armEffect(probe, "ChainLightning", { 1 }, nil, { OppTargets = {} })
	local b = assert(Simulation.findBall(probe, 1), "the 1")
	b.x, b.y = charged.x, charged.y
	local pocket, ux, uy = ChainLightning.lineUp(probe, b, plain.vx / s0, plain.vy / s0)
	check(pocket ~= nil, "a clear line")
	check(near(charged.vx / s1, ux, 1e-9) and near(charged.vy / s1, uy, 1e-9), "down that line")
	check(near(charged.wy, charged.vx / Config.Balls.RadiusInches, 1e-9), "rolling")
	local _, events = shoot(balls, 1, 0.4, true, { 1 }, {})
	local charge = ultEvents(events, "charge")
	check(#charge == 1 and charge[1].other == pocket, "charged toward that pocket")
	local into = nil
	for _, ev in events do
		if ev.type == "pocket" and ev.ball == 1 then
			into = ev.other
		end
	end
	check(
		into == pocket,
		("dropped into pocket %s (wanted %s)"):format(tostring(into), tostring(pocket))
	)
end

function tests.with_no_clear_line_the_charge_turns_by_at_most_the_cap_and_boosts()
	-- On the 8, toward pocket 3 (top right) only, with the 9 sitting on the line in: no clear
	-- line, so the 8 is turned toward it by the cap and boosted, as before the buff.
	local balls = table_({ { 0, -30, 0 }, { 8, 0, 0 }, { 9, 25.5, 13 } })
	local plain = atContact(balls, 8, 0.05, 0.4, false, { 8 }, 3)
	local charged, emitted = atContact(balls, 8, 0.05, 0.4, true, { 8 }, 3)
	check(emitted, "the charge event")
	local s0 = math.sqrt(plain.vx ^ 2 + plain.vy ^ 2)
	local s1 = math.sqrt(charged.vx ^ 2 + charged.vy ^ 2)
	check(near(s1, s0 * C.Boost, 1e-6), ("boosted: %.4f vs %.4f"):format(s1, s0 * C.Boost))
	local cos = (plain.vx * charged.vx + plain.vy * charged.vy) / (s0 * s1)
	local capCos = 1 / math.sqrt(1 + C.SteerTan * C.SteerTan)
	check(cos >= capCos - 1e-9, "turned no more than the cap")
	check(cos < 1 - 1e-6, "but turned")
end

-- Around the 1: the 8 closest, then three of theirs, then two of yours further out.
local function chainRules()
	local balls = table_({
		{ 0, -12, 0 },
		{ 1, 0, 0 },
		{ 8, 3.5, 3 },
		{ 9, 5, -4 },
		{ 10, 9, -6 },
		{ 11, 11, 4 },
		{ 2, 16, -9 },
		{ 3, 18, 8 },
	})
	local _, events = shoot(balls, 1, 0.2, true, { 1, 2, 3 }, { 9, 10, 11 })
	local links = ultEvents(events, "link")
	check(#links >= 2, "a chain: " .. #links)
	local theirs = 0
	for _, ev in links do
		check(ev.other ~= 0 and ev.other ~= 8, "never the cue ball or the 8")
		if ev.other >= 9 then
			theirs += 1
			check(ev.value == S.OpponentFactor, "theirs at the opponent's factor")
		else
			check(ev.value == 1, "yours at full")
		end
	end
	check(
		theirs <= Config.Ults.ChainLightning.MaxOpp,
		"at most " .. Config.Ults.ChainLightning.MaxOpp .. " of theirs"
	)
	check(#links <= C.Links, "at most Links jumps")
end

function tests.the_chain_never_touches_the_cue_ball_or_the_8_and_takes_at_most_two_of_theirs()
	-- The rules for a longer chain than the tuned one (Links 1 since the Rare+ buff): three
	-- jumps.
	local links0 = C.Links
	C.Links = 3
	local ok, err = pcall(chainRules)
	C.Links = links0
	if not ok then
		error(err, 0)
	end
end

function tests.the_legal_8_is_yours_and_pushed_to_the_called_pocket()
	-- On the 8: the 8 is the shooter's, toward pocket 3 (top right) only.
	local balls = table_({ { 0, 10, 12 }, { 8, 30, 12 } })
	local _, events = shoot(balls, 8, 0.3, true, { 8 }, {}, 3)
	local charge = ultEvents(events, "charge")
	check(#charge == 1 and charge[1].other == 3, "the 8 charged toward the called pocket")
end

function tests.theirs_get_half_the_push()
	-- The same ball as yours, then as theirs: pushed at the opponent's factor of the speed.
	local balls = table_({ { 0, -30, 0 }, { 1, -10, 0 }, { 5, -2, -14 } })
	local function pushSpeed(opp: boolean): number
		local own = if opp then { 1 } else { 1, 5 }
		local sim = Simulation.newState(geometry, Ball.cloneList(balls))
		Simulation.strike(sim, assert(ShotInput.validate({ angle = 0, power = 0.2 }, nil), "shot"))
		Simulation.armEffect(
			sim,
			"ChainLightning",
			own,
			nil,
			{ OppTargets = if opp then { 5 } else {} }
		)
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		for _ = 1, 4000 do
			local events = {}
			Simulation.step(sim, DT, events)
			if #ultEvents(events, "link") > 0 then
				local b = assert(Simulation.findBall(sim, 5), "the 5")
				return math.sqrt(b.vx ^ 2 + b.vy ^ 2)
			end
		end
		error("no link")
	end
	local mine, theirs = pushSpeed(false), pushSpeed(true)
	check(mine > 0, "pushed")
	-- Both measured one step after the push, so allow that step's friction.
	check(near(theirs / mine, S.OpponentFactor, 0.02), ("ratio %.3f"):format(theirs / mine))
end

function tests.a_ball_near_an_open_pocket_is_pushed_in()
	-- The 1 is charged away toward the bottom right; the 2, 15 in from it, has an open line
	-- into the top-right corner.
	local balls = table_({ { 0, 10, 5 }, { 1, 28, -5 }, { 2, 32, 10 } })
	local _, events = shoot(balls, 1, 0.2, true, { 1, 2 }, {})
	local links = ultEvents(events, "link")
	check(#links >= 1 and links[1].other == 2, "the 2 struck")
	check(pocketed(events, 2), "the 2 dropped")
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 31)
	local r = V.rng(5)
	local compared, charged = 0, 0
	for _, ts in states do
		local own, opp, eightPocket = Arming.targets(ts.groups, 1, nil, ts.balls)
		local payload = { angle = V.uniform(r) * 2 * math.pi, power = 0.3 + V.uniform(r) * 0.6 }
		local sim = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(sim, "ChainLightning", own, eightPocket, { OppTargets = opp })
		ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
		local outcome = Simulation.settle(sim, { strike })
		if outcome.capped then
			continue
		end
		if #ultEvents(outcome.events, "charge") > 0 then
			charged += 1
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "shot"))
		Simulation.armEffect(replay, "ChainLightning", own, eightPocket, { OppTargets = opp })
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "cue"))
		local steps = 0
		while not Simulation.isAtRest(replay) and steps < 40000 do
			Simulation.step(replay, DT, {})
			steps += 1
		end
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
	check(charged >= 3, "some shots charged: " .. charged)
end

return tests
