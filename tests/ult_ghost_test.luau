--!strict
-- Ghost (docs/prompts/ABILITIES_PROMPT.md 7.4): the cue ball passes through the opponent's
-- balls and the 8 (unless it is the shooter's legal 8), armed the way the server arms it
-- (Arming.extras' PhaseCue). No contact is ever registered with a phased ball, the cue ball
-- never comes to rest inside a ball, and the client's replay matches the server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Arming = H.require("Ults.Arming")
local Judge = H.require("Rules.ShotJudge")

local geometry = V.geometry
local R = Config.Balls.RadiusInches

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function ctx(own: { number }, opp: { number }, legalEight: boolean): any
	return {
		own = own,
		opp = opp,
		eightPocket = if legalEight then 1 else nil,
		legalEight = legalEight,
		open = #opp == 0,
		pick = nil,
		balls = {},
	}
end

-- The shooter's balls and the opponent's in a harness table state, and Ghost's overrides.
local function arming(ts: any): ({ number }, any)
	local own, opp, eightPocket, legalEight = Arming.targets(ts.groups, 1, 1, ts.balls)
	return own,
		Arming.extras("Ghost", {
			own = own,
			opp = opp,
			eightPocket = eightPocket,
			legalEight = legalEight,
			open = ts.groups == nil,
			pick = nil,
			balls = ts.balls,
		})
end

local function shoot(balls: { any }, payload: any, own: { number }, extra: any): (any, any)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "a valid shot"))
	Simulation.armEffect(sim, "Ghost", own, nil, extra)
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "a cue ball"))
	return sim, Simulation.settle(sim, { strike })
end

local tests = {}

function tests.it_phases_the_opponents_balls_and_the_8_unless_it_is_yours()
	local a = Arming.extras("Ghost", ctx({ 1, 2, 3 }, { 9, 12 }, false))
	check(#a.PhaseCue == 3 and a.PhaseCue[1] == 8 and a.PhaseCue[2] == 9, "the 9, 12 and the 8")
	local b = Arming.extras("Ghost", ctx({ 8 }, { 9, 12 }, true))
	check(#b.PhaseCue == 2 and not table.find(b.PhaseCue, 8), "your legal 8 is hit")
	local c = Arming.extras("Ghost", ctx({ 1, 2, 9 }, {}, false))
	check(#c.PhaseCue == 1 and c.PhaseCue[1] == 8, "an open table: only the 8")
end

function tests.a_blocked_pot_goes_through_the_opponents_ball()
	-- The 9 (theirs) sits on the line to the 1: without Ghost the 9 is hit first (a foul),
	-- with it the cue ball passes through and the 1 is hit first.
	local balls = { Ball.new(0, -30, 0), Ball.new(9, -15, 0), Ball.new(1, 0, 0) }
	local before = Ball.cloneList(balls)
	local groups = { "solids", "stripes" }
	local payload = { angle = 0, power = 0.5 }
	local ts = { balls = balls, groups = groups }
	local own, extra = arming(ts)
	local sim, outcome = shoot(balls, payload, own, extra)
	check(outcome.firstContact == 1, "the 1 is the first contact")
	for _, ev in outcome.events do
		check(
			not (
					ev.type == "ballHit"
					and (ev.ball == 9 or ev.other == 9)
					and (ev.ball == 0 or ev.other == 0)
				),
			"no contact with the 9"
		)
	end
	local nine = assert(Simulation.findBall(sim, 9), "the 9")
	check(nine.x == -15 and nine.y == 0, "the 9 never moved")
	local verdict = Judge.resolve(before, outcome, groups, 1, false, nil, true)
	check(verdict.foul == nil, "no foul")
end

function tests.no_contact_ever_with_a_phased_ball_and_never_resting_inside_one()
	local states = V.states(40, 17)
	local r = V.rng(5)
	local shots, phasedPasses = 0, 0
	for _, ts in states do
		local own, extra = arming(ts)
		local phased = {}
		for _, id in extra.PhaseCue do
			phased[id] = true
		end
		for _ = 1, 3 do
			local payload = {
				angle = V.uniform(r) * 2 * math.pi,
				power = 0.3 + V.uniform(r) * 0.7,
				spin = { x = V.uniform(r) * 1.2 - 0.6, y = V.uniform(r) * 1.2 - 0.6 },
			}
			local sim, outcome = shoot(ts.balls, payload, own, extra)
			if outcome.capped then
				continue
			end
			shots += 1
			for _, ev in outcome.events do
				if ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
					local other = if ev.ball == 0 then ev.other else ev.ball
					check(not phased[other], "the cue ball touched phased ball " .. tostring(other))
				end
			end
			local cue = assert(Simulation.findBall(sim, 0), "a cue ball")
			if not cue.pocketed then
				for _, b in sim.balls do
					if b.id ~= 0 and not b.pocketed then
						local dx, dy = b.x - cue.x, b.y - cue.y
						check(
							dx * dx + dy * dy >= 4 * R * R - 1e-9,
							"the cue ball rests inside " .. b.id
						)
					end
				end
			end
			-- Count the shots where the cue ball's path really crossed a phased ball.
			local plain = Simulation.newState(geometry, Ball.cloneList(ts.balls))
			local st = Simulation.strike(plain, assert(ShotInput.validate(payload, nil), "shot"))
			ShotInput.quantiseSeed(assert(Simulation.findBall(plain, 0), "cue"))
			local first = Simulation.settle(plain, { st }).firstContact
			if first and phased[first] then
				phasedPasses += 1
			end
		end
	end
	check(shots >= 100, "enough shots: " .. shots)
	check(phasedPasses >= 10, "enough shots that would have hit a phased ball: " .. phasedPasses)
end

function tests.a_cue_ball_stopping_inside_a_phased_ball_is_moved_off_it()
	-- At rest with the cue ball half inside the 9 (theirs): finish moves it straight away from
	-- the 9's centre to just clear of it.
	local s = Simulation.newState(geometry, { Ball.new(0, -23, 0), Ball.new(9, -24, 0) })
	Simulation.armEffect(s, "Ghost", {}, nil, { PhaseCue = { 9 } })
	Simulation.finishShot(s, {})
	local cue = assert(Simulation.findBall(s, 0), "cue")
	local clear = 2 * R + Config.Ults.Ghost.ClearGapInches
	check(math.abs(cue.x - (-24 + clear)) < 1e-9 and cue.y == 0, "moved straight off the 9")
	-- Against a cushion: that way is blocked, so the first free heading round the 9.
	local HL = geometry.halfLength
	s = Simulation.newState(geometry, { Ball.new(0, HL - R, 5), Ball.new(9, HL - R - 1, 5) })
	Simulation.armEffect(s, "Ghost", {}, nil, { PhaseCue = { 9 } })
	Simulation.finishShot(s, {})
	cue = assert(Simulation.findBall(s, 0), "cue")
	local dx, dy = cue.x - (HL - R - 1), cue.y - 5
	check(math.abs(math.sqrt(dx * dx + dy * dy) - clear) < 1e-9, "just clear of the 9")
	check(cue.x <= HL - R, "inside the cushions")
	-- A ball it never phased is left alone (finish only fixes its own overlaps).
	s = Simulation.newState(geometry, { Ball.new(0, -23, 0), Ball.new(3, -24, 0) })
	Simulation.armEffect(s, "Ghost", {}, nil, { PhaseCue = { 9 } })
	Simulation.finishShot(s, {})
	check(assert(Simulation.findBall(s, 0), "cue").x == -23, "not moved for the 3")
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 23)
	local r = V.rng(8)
	local compared = 0
	for _, ts in states do
		local own, extra = arming(ts)
		local payload = { angle = V.uniform(r) * 2 * math.pi, power = 0.3 + V.uniform(r) * 0.6 }
		local sim, outcome = shoot(ts.balls, payload, own, extra)
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "a valid shot"))
		Simulation.armEffect(replay, "Ghost", own, nil, extra)
		ShotInput.quantiseSeed(assert(Simulation.findBall(replay, 0), "a cue ball"))
		local steps = 0
		while not Simulation.isAtRest(replay) and steps < 20000 do
			Simulation.step(replay, Config.Physics.FixedStep, {})
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
end

function tests.after_the_first_contact_the_hit_ball_passes_through_theirs()
	-- The 1 is hit straight at the 9 (theirs): it passes through (no contact, the 9 never
	-- moves), and from the contact the cue ball passes through every ball.
	local balls =
		{ Ball.new(0, -30, 0), Ball.new(1, -20, 0), Ball.new(9, -5, 0), Ball.new(2, 10, 0) }
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.strike(sim, assert(ShotInput.validate({ angle = 0, power = 0.4 }, nil), "a shot"))
	Simulation.armEffect(sim, "Ghost", { 1, 2 }, nil, { PhaseCue = { 8, 9 } })
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "a cue ball"))
	local events = {}
	local checked = false
	for _ = 1, 20000 do
		if Simulation.isAtRest(sim) then
			break
		end
		Simulation.step(sim, Config.Physics.FixedStep, events)
		if not checked and sim.fx.touched then
			checked = true
			check(sim.fx.touched == 1, "the 1 was the first ball hit")
			local cue, one = sim.fx.passes[0], sim.fx.passes[1]
			check(cue[2] == true and cue[9] == true, "the cue ball: every ball")
			check(one[9] == true and one[2] == nil, "the 1: only what the cue ball passed")
		end
	end
	check(checked, "a contact")
	for _, ev in events do
		if ev.type == "ballHit" then
			local pair = { ev.ball, ev.other }
			check(not (table.find(pair, 1) and table.find(pair, 9)), "the 1 never touches the 9")
		end
	end
	local nine = assert(Simulation.findBall(sim, 9), "the 9")
	check(nine.x == -5 and nine.y == 0, "the 9 never moved")
end

function tests.the_ghostly_pull_drops_more_of_the_balls_it_hits()
	-- The same random shots with the pull on and off: the ball hit first drops more often.
	local G = Config.Ults.Ghost
	local was = G.PullFactor
	local states = V.states(40, 31)
	local r = V.rng(5)
	local shots = {}
	for _ in states do
		table.insert(
			shots,
			{ angle = V.uniform(r) * 2 * math.pi, power = 0.3 + V.uniform(r) * 0.5 }
		)
	end
	local function drops(factor: number): number
		G.PullFactor = factor
		local n = 0
		for i, ts in states do
			local own, extra = arming(ts)
			local _, outcome = shoot(ts.balls, shots[i], own, extra)
			local hit = nil
			for _, ev in outcome.events do
				if hit == nil and ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
					hit = if ev.ball == 0 then ev.other else ev.ball
				elseif hit and ev.type == "pocket" and ev.ball == hit and table.find(own, hit) then
					n += 1
				end
			end
		end
		return n
	end
	local ok, off, on = pcall(function()
		return drops(0), drops(1)
	end)
	G.PullFactor = was
	check(ok, tostring(off))
	print(
		("        the ball hit first dropped %d of 40 times without the pull, %d with"):format(
			off,
			on
		)
	)
	check(on > off, "the pull drops more")
end

return tests
