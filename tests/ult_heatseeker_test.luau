--!strict
-- Heat Seeker (docs/prompts/ABILITIES_PROMPT.md 7.5): whatever direction the shot goes, the
-- cue ball homes on the locked ball (overrides.Pick) and its first contact is that ball unless
-- it is boxed in; a direct aim's cut is turned toward the best pocket (capped); no pick, no
-- homing; and the client's replay matches the server's settle.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Magnet = H.require("Ults.Effects.Magnet")

local geometry = V.geometry
local R = Config.Balls.RadiusInches

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

local function shoot(balls: { any }, payload: any, pick: { number }?): (any, any)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "a valid shot"))
	if pick then
		Simulation.armEffect(sim, "HeatSeeker", { 1, 2, 3 }, nil, { Pick = pick })
	end
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "a cue ball"))
	return sim, Simulation.settle(sim, { strike })
end

local tests = {}

function tests.from_every_direction_it_hits_the_locked_ball()
	-- The 1 mid-table right, a few other balls about; 16 headings at three powers.
	local balls = {
		Ball.new(0, -25, 0),
		Ball.new(1, 20, 5),
		Ball.new(2, -30, 15),
		Ball.new(9, 0, -15),
		Ball.new(12, 35, -12),
	}
	local hits, total = 0, 0
	for i = 0, 15 do
		for _, power in { 0.25, 0.55, 0.9 } do
			local _, outcome = shoot(balls, { angle = i * math.pi / 8, power = power }, { 1 })
			total += 1
			if outcome.firstContact == 1 then
				hits += 1
			end
		end
	end
	check(hits == total, ("the 1 first on %d of %d shots"):format(hits, total))
end

function tests.on_random_tables_and_aims_it_nearly_always_arrives()
	-- The misses left are a cue ball aimed straight into a ball or pocket right beside it, or
	-- a locked ball boxed in: at least 90% arrive.
	local states = V.states(40, 7)
	local r = V.rng(3)
	local hits, total = 0, 0
	for _, ts in states do
		local own = {}
		for _, b in ts.balls do
			if b.id >= 1 and b.id <= 7 and not b.pocketed then
				table.insert(own, b.id)
			end
		end
		for k = 1, math.min(#own, 4) do
			local payload =
				{ angle = V.uniform(r) * 2 * math.pi, power = 0.15 + V.uniform(r) * 0.8 }
			local _, outcome = shoot(ts.balls, payload, { own[k] })
			total += 1
			if outcome.firstContact == own[k] then
				hits += 1
			end
		end
	end
	check(total >= 100, "enough shots: " .. total)
	check(hits >= 0.9 * total, ("the locked ball first on %d of %d"):format(hits, total))
end

function tests.it_goes_round_a_wall_it_cannot_pass()
	-- The Studio setup: the 1 behind the 9 and 10, too close together for the cue ball.
	local balls = {
		Ball.new(0, -20, 0),
		Ball.new(1, 30, 14),
		Ball.new(9, 20, 12.5),
		Ball.new(10, 20, 9.6),
	}
	local aim = math.atan2(14, 50)
	local _, plain = shoot(balls, { angle = aim, power = 0.5 }, nil)
	check(plain.firstContact == 10 or plain.firstContact == 9, "without it the wall is hit")
	local _, homed = shoot(balls, { angle = aim, power = 0.5 }, { 1 })
	check(homed.firstContact == 1, "with it the 1 is hit: " .. tostring(homed.firstContact))
end

-- The 1's heading just after the cue ball's first contact (degrees), stepping the shot.
local function headingAfterHit(balls: { any }, payload: any, pick: { number }?): number?
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	Simulation.strike(sim, assert(ShotInput.validate(payload, nil), "a valid shot"))
	if pick then
		Simulation.armEffect(sim, "HeatSeeker", { 1 }, nil, { Pick = pick })
	end
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "a cue ball"))
	for _ = 1, 4000 do
		local events = {}
		Simulation.step(sim, Config.Physics.FixedStep, events)
		if Simulation.firstContact(events) == 1 then
			local one = assert(Simulation.findBall(sim, 1), "the 1")
			return math.deg(math.atan2(one.vy, one.vx))
		end
	end
	return nil
end

function tests.a_direct_aim_cuts_better_but_not_perfectly()
	-- A cut of the 1 into the top-right corner, aimed a little off the perfect ghost ball.
	local balls = { Ball.new(0, 0, 0), Ball.new(1, 30, 12) }
	local mx, my = 0, 0
	for _, p in geometry.pockets do
		if p.x > 0 and p.y > 0 then
			mx, my = Magnet.mouthPoint(geometry, p)
		end
	end
	local ux, uy = mx - 30, my - 12
	local ul = math.sqrt(ux * ux + uy * uy)
	local potLine = math.deg(math.atan2(uy, ux))
	local gx, gy = 30 - ux / ul * 2 * R, 12 - uy / ul * 2 * R
	local perfect = math.atan2(gy, gx)
	local cap = math.deg(math.atan(Config.Ults.HeatSeeker.CutCorrectionTan))
	local beyond = 0
	for _, off in { -0.05, -0.03, 0.03, 0.05 } do
		local payload = { angle = perfect + off, power = 0.35 }
		local plain = assert(headingAfterHit(balls, payload, nil), "the 1 is hit")
		local homed = assert(headingAfterHit(balls, payload, { 1 }), "the 1 is hit homing")
		local before, after = math.abs(plain - potLine), math.abs(homed - potLine)
		check(
			after < before,
			("off %.2f: %.1f from the pot line, was %.1f"):format(off, after, before)
		)
		-- By at most the cap (plus a little throw), and so not onto the line from this far off.
		check(
			before - after <= cap + 1,
			("off %.2f: corrected %.1f degrees"):format(off, before - after)
		)
		-- Further off than the cap can turn: never made perfect.
		if before > cap + 2 then
			beyond += 1
			check(after > 1, ("off %.2f: not made perfect"):format(off))
		end
	end
	check(beyond > 0, "some aims are further off than the cap")
end

function tests.no_pick_no_homing()
	local balls = { Ball.new(0, -25, 0), Ball.new(1, 20, 5) }
	local plain = shoot(balls, { angle = math.pi, power = 0.4 }, nil)
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local st = Simulation.strike(
		sim,
		assert(ShotInput.validate({ angle = math.pi, power = 0.4 }, nil), "shot")
	)
	Simulation.armEffect(sim, "HeatSeeker", { 1 }, nil, {})
	ShotInput.quantiseSeed(assert(Simulation.findBall(sim, 0), "cue"))
	Simulation.settle(sim, { st })
	for i, b in plain.balls do
		check(b.x == sim.balls[i].x and b.y == sim.balls[i].y, "ball " .. b.id .. " as without it")
	end
end

function tests.the_replay_matches_the_settle()
	local states = V.states(12, 31)
	local r = V.rng(4)
	local compared = 0
	for _, ts in states do
		local own = {}
		for _, b in ts.balls do
			if b.id >= 1 and b.id <= 7 and not b.pocketed then
				table.insert(own, b.id)
			end
		end
		if #own == 0 then
			continue
		end
		local payload = { angle = V.uniform(r) * 2 * math.pi, power = 0.2 + V.uniform(r) * 0.7 }
		local sim, outcome = shoot(ts.balls, payload, { own[1] })
		if outcome.capped then
			continue
		end
		local replay = Simulation.newState(geometry, Ball.cloneList(ts.balls))
		Simulation.strike(replay, assert(ShotInput.validate(payload, nil), "a valid shot"))
		Simulation.armEffect(replay, "HeatSeeker", { 1, 2, 3 }, nil, { Pick = { own[1] } })
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
	check(compared >= 8, "enough shots compared: " .. compared)
end

return tests
