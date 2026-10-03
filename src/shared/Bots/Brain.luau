--!strict
-- The bot's brain: what to do with one shot. Pure and seeded (src/shared/Bots/Rng), so a
-- bot plays the same way from the same seed, in Lune and on the server.
--
-- Every shot it finds its pots (ShotFinder), picks one (higher tiers weigh where the cue ball
-- stops), then decides afresh whether to really make it (its tier's Make chance, more when it
-- is behind) or to play a near miss: the aim moved off the line just enough that the ball
-- stays up, preferably stopping by the pocket, never a foul. Both are checked in our physics.
-- Low tiers also blunder (a full-ball hit with no real angle) and scratch by accident.
-- With no pot it plays a soft hit (or, from Diamond, a real safety); with ball in hand it
-- places the cue ball where its best pot is easiest.
--
-- Numbers: Config.Bots.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local TableGeometry = require(script.Parent.Parent.Physics.Table)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Placement = require(script.Parent.Parent.Rules.CuePlacement)
local Finder = require(script.Parent.ShotFinder)
local Rng = require(script.Parent.Rng)

type Ball = Ball.Ball
type Rng = Rng.Rng
type View = Finder.View
type Plan = Finder.Plan

local B = Config.Bots
local D = 2 * Config.Balls.RadiusInches

local Brain = {}

export type Tier = typeof(Config.Bots.Tiers.Bronze)

export type Kind = "make" | "miss" | "safe" | "blunder" | "scratch" | "break" | "eight"

--- What the bot plays: a shot in the ShotFired payload's terms, plus why.
export type Decision = {
	kind: Kind,
	angle: number,
	power: number,
	cueX: number?, -- ball in hand: where it puts the cue ball
	cueY: number?,
	called: number?, -- the 8's pocket, when it must call one
	ball: number?, -- the ball it aims at
	pocket: number?, -- the pocket it means (or pretends) to send it to
	easy: boolean, -- it had an easy pot (the ability policy's "no easy shot")
}

export type Options = {
	ballInHand: boolean?,
	forceMake: boolean?, -- a scripted visit
	forceMiss: boolean?,
	makeChance: number?, -- overrides the tier's chance (tests, scripts)
	yield: (() -> ())?, -- called between simulations so the server can spread the work
}

--- The tier's numbers (an unknown tier plays Bronze).
function Brain.tier(name: string?): Tier
	local rows: { [string]: Tier } = B.Tiers :: any
	return rows[name or "Bronze"] or B.Tiers.Bronze
end

local function cueOf(view: View): Ball
	return Finder.findBall(view.balls, 0) :: Ball
end

local function requireRail(view: View): boolean
	local v = (view :: any).requireRail
	if v ~= nil then
		return v
	end
	return Config.Multiplayer.RailAfterContact.Casual
end

export type Trial = {
	foul: string?,
	winner: number?,
	keep: boolean,
	pockets: { number },
	balls: { Ball },
	scratch: boolean,
	groups: { [number]: string }, -- the groups after the shot
	respot: { number }, -- object balls that flew off (back on the foot spot)
	respotEight: boolean, -- the 8 went down or off on the break
}

--- Plays `shot` on a copy of the table (the cue ball at (cueX, cueY) when given) and judges
--- it by the real rules.
function Brain.simulate(view: View, shot: any, cueX: number?, cueY: number?, called: number?): Trial
	local before = Ball.cloneList(view.balls)
	local balls = Ball.cloneList(view.balls)
	if cueX and cueY then
		local cue = Finder.findBall(balls, 0) :: Ball
		cue.x, cue.y, cue.pocketed = cueX, cueY, false
		Ball.stop(cue)
		local c0 = Finder.findBall(before, 0) :: Ball
		c0.x, c0.y, c0.pocketed = cueX, cueY, false
	end
	local out = Simulation.runHeadless(Simulation.newState(view.geometry, balls), {
		angle = shot.angle,
		power = shot.power,
		spin = shot.spin,
	})
	local verdict = Judge.resolve(
		before,
		out,
		view.groups :: any,
		view.team,
		view.breakShot == true,
		called or view.called,
		requireRail(view)
	)
	local scratch = false
	for _, b in out.finalBalls do
		if b.id == 0 and b.pocketed then
			scratch = true
		end
	end
	return {
		foul = if out.capped then "Capped" else verdict.foul,
		winner = verdict.winner,
		keep = verdict.keep,
		pockets = verdict.pockets,
		balls = out.finalBalls,
		scratch = scratch,
		groups = verdict.groups :: any,
		respot = verdict.respot,
		respotEight = verdict.respotEight,
	}
end

local function dropped(trial: Trial, id: number): boolean
	for _, p in trial.pockets do
		if p == id then
			return true
		end
	end
	return false
end

-- A decision from a plan and a shot.
local function decision(
	kind: Kind,
	plan: Plan?,
	angle: number,
	power: number,
	easy: boolean,
	cueX: number?,
	cueY: number?
): Decision
	return {
		kind = kind,
		angle = angle,
		power = math.clamp(power, Config.Input.MinPowerToShoot, 1),
		cueX = cueX,
		cueY = cueY,
		called = if plan then plan.called else nil,
		ball = if plan then plan.ball else nil,
		pocket = if plan then plan.pocket else nil,
		easy = easy,
	}
end

-- The best pot's score from the cue ball at (x, y) on `balls` (0: none).
local function bestScore(view: View, balls: { Ball }, x: number?, y: number?): number
	local v = table.clone(view)
	v.balls = balls
	local list = Finder.candidates(v, x, y)
	return if list[1] then list[1].score else 0
end

--- The chance it makes the pot it goes for: its tier's Make, plus Behind while it has
--- BehindBalls or more balls left than the opponent.
function Brain.makeChance(view: View, tier: Tier): number
	local p = tier.Make
	local mine, theirs = Finder.left(view)
	if mine and theirs and mine - theirs >= B.BehindBalls then
		p += tier.Behind
	end
	return math.min(p, B.MaxMake)
end

--- Where to put the cue ball with ball in hand: the legal spot (straight-in spots behind its
--- balls, a few for low tiers) whose best pot scores highest. Nil: leave it where it is.
function Brain.placeCue(view: View, tier: Tier, rng: Rng, yield: (() -> ())?): (number?, number?)
	local spots = {}
	for _, id in Finder.ownIds(view) do
		local ob = Finder.findBall(view.balls, id) :: Ball
		for _, pk in Finder.pockets(view.geometry) do
			local ox, oy = pk.mx - ob.x, pk.my - ob.y
			local d = math.sqrt(ox * ox + oy * oy)
			if d < 1e-6 then
				continue
			end
			for _, back in { 7, 14 } do
				local x, y = ob.x - ox / d * (D + back), ob.y - oy / d * (D + back)
				if Placement.valid(view.balls, view.geometry, x, y, false) then
					table.insert(spots, { x, y })
				end
			end
		end
	end
	-- A few random legal spots too, so a weak bot does not always find the perfect one.
	local HL, HW = view.geometry.halfLength, view.geometry.halfWidth
	for _ = 1, 4 do
		local x, y = Rng.range(rng, -HL + 4, HL - 4), Rng.range(rng, -HW + 4, HW - 4)
		if Placement.valid(view.balls, view.geometry, x, y, false) then
			table.insert(spots, { x, y })
		end
	end
	if #spots == 0 then
		return nil, nil
	end
	-- A low tier only weighs PlaceSamples of them, picked at random.
	while #spots > tier.PlaceSamples do
		table.remove(spots, Rng.int(rng, 1, #spots))
	end
	local best, bestScoreSeen = nil, -1
	for _, s in spots do
		local score = bestScore(view, view.balls, s[1], s[2])
		if score > bestScoreSeen then
			best, bestScoreSeen = s, score
		end
		if yield then
			yield()
		end
	end
	if best == nil then
		return nil, nil
	end
	return best[1], best[2]
end

--- A shot that really pots `plan`: a little natural spread, checked in our physics.
function Brain.make(view: View, plan: Plan, rng: Rng, yield: (() -> ())?): (number, number, boolean)
	for _ = 1, B.MakeTries do
		local angle = plan.angle + math.rad(B.MakeAimSigmaDegrees) * Rng.gauss(rng)
		local power = math.clamp(plan.power * (1 + B.MakePowerSigma * Rng.gauss(rng)), 0.04, 1)
		local trial = Brain.simulate(
			view,
			{ angle = angle, power = power },
			plan.cueX,
			plan.cueY,
			plan.called
		)
		if yield then
			yield()
		end
		if
			trial.foul == nil
			and dropped(trial, plan.ball)
			and (trial.winner == nil or trial.winner == view.team)
		then
			return angle, power, true
		end
	end
	local trial = Brain.simulate(
		view,
		{ angle = plan.angle, power = plan.power },
		plan.cueX,
		plan.cueY,
		plan.called
	)
	return plan.angle, plan.power, trial.foul == nil and dropped(trial, plan.ball)
end

-- How far a ball at (x, y) is from the pocket's mouth.
local function fromMouth(view: View, pocketId: number?, x: number, y: number): number
	local pk = if pocketId then Finder.pocket(view.geometry, pocketId) else nil
	if pk == nil then
		return math.huge
	end
	return math.sqrt((pk.mx - x) ^ 2 + (pk.my - y) ^ 2)
end

--- A near miss of `plan`: the aim moved off the line by the smallest offset (NearMissDegrees,
--- both sides, the side drawn at random) that keeps the ball up with no foul, none of its
--- balls dropping and the 8 staying up; one that stops within NearInches of the pocket wins.
--- Nil when every offset pots or fouls.
function Brain.nearMiss(view: View, plan: Plan, rng: Rng, yield: (() -> ())?): (number?, number?)
	local first = if Rng.chance(rng, 0.5) then 1 else -1
	local fallback: { number }? = nil
	local fallbackDist = math.huge
	for _, deg in B.NearMissDegrees do
		for _, sign in { first, -first } do
			local angle = plan.angle + sign * math.rad(deg)
			local power = plan.power * (1 + 0.5 * B.MakePowerSigma * Rng.gauss(rng))
			local trial = Brain.simulate(
				view,
				{ angle = angle, power = power },
				plan.cueX,
				plan.cueY,
				plan.called
			)
			if yield then
				yield()
			end
			if
				trial.foul ~= nil
				or trial.keep
				or trial.winner ~= nil
				or dropped(trial, plan.ball)
			then
				continue
			end
			local ob = Finder.findBall(trial.balls, plan.ball)
			local dist = if ob and not ob.pocketed
				then fromMouth(view, plan.pocket, ob.x, ob.y)
				else math.huge
			if dist <= B.NearInches then
				return angle, power
			end
			if dist < fallbackDist then
				fallback, fallbackDist = { angle, power }, dist
			end
		end
	end
	if fallback then
		return fallback[1], fallback[2]
	end
	return nil, nil
end

--- An accidental scratch (low tiers): a shot near `plan` whose cue ball drops. Nil if none of
--- the variants tried does (then it simply plays on).
function Brain.scratch(view: View, plan: Plan, rng: Rng, yield: (() -> ())?): (number?, number?)
	for _, k in { 1.25, 1.5, 1.8, 2.2 } do
		for _, deg in { 0, 1.5, -1.5, 3, -3 } do
			local angle = plan.angle + math.rad(deg)
			local power = math.clamp(plan.power * k, 0.04, 1)
			local trial = Brain.simulate(
				view,
				{ angle = angle, power = power },
				plan.cueX,
				plan.cueY,
				plan.called
			)
			if yield then
				yield()
			end
			if trial.scratch and trial.winner == nil then
				return angle, power
			end
		end
	end
	local _ = rng
	return nil, nil
end

--- A real safety (Safety tiers): soft hits at its balls, kept when legal and the 8 stays up,
--- scored by how hard the opponent's best pot is from where the cue ball stops.
function Brain.safety(
	view: View,
	rng: Rng,
	cueX: number?,
	cueY: number?,
	yield: (() -> ())?
): Decision?
	local cue = cueOf(view)
	local cx, cy = cueX or cue.x, cueY or cue.y
	local oppView = table.clone(view)
	oppView.team = 3 - view.team
	local best: Decision? = nil
	local bestLeft = math.huge
	for _, id in Finder.ownIds(view) do
		local ob = Finder.findBall(view.balls, id) :: Ball
		local base = math.atan2(ob.y - cy, ob.x - cx)
		local d = math.sqrt((ob.x - cx) ^ 2 + (ob.y - cy) ^ 2)
		-- The half angle that still meets the ball (a thin hit up to a full one).
		local half = math.asin(math.clamp(D * 0.9 / math.max(d, D), 0, 1))
		for i = 1, B.SafetyAngles do
			local a = base + half * (2 * (i - 1) / math.max(B.SafetyAngles - 1, 1) - 1)
			for _, power in B.SafetyPowers do
				local trial = Brain.simulate(view, { angle = a, power = power }, cueX, cueY)
				if yield then
					yield()
				end
				if trial.foul ~= nil or trial.winner ~= nil then
					continue
				end
				oppView.balls = trial.balls
				local c = Finder.findBall(trial.balls, 0) :: Ball
				local left = bestScore(oppView, trial.balls, c.x, c.y) + Rng.uniform(rng) * 1e-6
				if left < bestLeft then
					bestLeft = left
					local plan = Finder.hitPlan(view, id, cx, cy)
					best = decision("safe", plan, a, power, false, cueX, cueY)
				end
			end
		end
	end
	return best
end

--- A full-ball hit with no real angle (a blunder): straight at the ball, a middling power.
function Brain.blunder(view: View, plan: Plan, rng: Rng): Decision
	local ob = Finder.findBall(view.balls, plan.ball) :: Ball
	local angle = math.atan2(ob.y - plan.cueY, ob.x - plan.cueX)
	local power = Rng.range(rng, B.BlunderPower[1], B.BlunderPower[2])
	return decision("blunder", plan, angle, power, false, nil, nil)
end

--- The break (a bot-vs-bot game: the real player always breaks against a bot): from the
--- head string at the rack, hard, with a little aim noise.
function Brain.breakShot(view: View, rng: Rng): Decision
	local cue = cueOf(view)
	local fx, fy = TableGeometry.footSpot(view.geometry)
	local x = Config.Multiplayer.BreakLineX
	local y = cue.y
	if not Placement.valid(view.balls, view.geometry, x, y, true) then
		y = 0
	end
	local angle = math.atan2(fy - y, fx - x) + math.rad(B.BreakAimSigmaDegrees) * Rng.gauss(rng)
	local power = Rng.range(rng, B.BreakPower[1], B.BreakPower[2])
	return {
		kind = "break",
		angle = angle,
		power = power,
		cueX = x,
		cueY = y,
		easy = true,
	}
end

--- Picks the pot to play: the best scored, or (Position > 1) the one of its best few that
--- also leaves the best next pot, checked in our physics.
function Brain.choose(view: View, pots: { Plan }, tier: Tier, yield: (() -> ())?): Plan
	if tier.Position <= 1 or #pots <= 1 then
		return pots[1]
	end
	local best, bestValue = pots[1], -math.huge
	for i = 1, math.min(tier.Position, #pots) do
		local plan = pots[i]
		local trial = Brain.simulate(
			view,
			{ angle = plan.angle, power = plan.power },
			plan.cueX,
			plan.cueY,
			plan.called
		)
		if yield then
			yield()
		end
		if trial.foul ~= nil or not dropped(trial, plan.ball) then
			continue
		end
		local c = Finder.findBall(trial.balls, 0) :: Ball
		local nextView = table.clone(view)
		nextView.balls = trial.balls
		local value = plan.score + bestScore(nextView, trial.balls, c.x, c.y)
		if value > bestValue then
			best, bestValue = plan, value
		end
	end
	return best
end

--- The whole decision for one shot.
function Brain.decide(view: View, tierName: string?, rng: Rng, options: Options?): Decision
	local o: Options = options or {}
	local yield = o.yield
	local tier = Brain.tier(tierName)
	if view.breakShot then
		return Brain.breakShot(view, rng)
	end
	local cueX, cueY = nil, nil
	if o.ballInHand then
		cueX, cueY = Brain.placeCue(view, tier, rng, yield)
	end
	local pots = Finder.pots(view, math.max(tier.Position, 2), cueX, cueY, yield)
	local easy = pots[1] ~= nil and pots[1].score >= B.EasyScore
	local cue = cueOf(view)
	local fromX, fromY = cueX or cue.x, cueY or cue.y

	-- An accidental scratch (Bronze, Silver, a little Gold).
	if not o.forceMake and tier.Scratch > 0 and Rng.chance(rng, tier.Scratch) then
		local plan = pots[1] or Finder.safePlan(view, cueX, cueY)
		local a, p = Brain.scratch(view, plan, rng, yield)
		if a and p then
			return decision("scratch", plan, a, p, easy, cueX, cueY)
		end
	end

	if #pots == 0 then
		if tier.Safety and not o.forceMake then
			local safe = Brain.safety(view, rng, cueX, cueY, yield)
			if safe then
				return safe
			end
		end
		local plan = Finder.safePlan(view, fromX, fromY)
		local angle = plan.angle + math.rad(B.MakeAimSigmaDegrees) * Rng.gauss(rng)
		return decision("safe", plan, angle, plan.power, false, cueX, cueY)
	end

	if not o.forceMake and tier.Blunder > 0 and Rng.chance(rng, tier.Blunder) then
		local d = Brain.blunder(view, pots[1], rng)
		local trial = Brain.simulate(view, d, cueX, cueY, d.called)
		if trial.winner == nil then
			d.cueX, d.cueY, d.easy = cueX, cueY, easy
			return d
		end
	end

	local plan = Brain.choose(view, pots, tier, yield)
	local p = o.makeChance or Brain.makeChance(view, tier)
	local wantMake = o.forceMake or (not o.forceMiss and Rng.chance(rng, p))
	local kind: Kind = if plan.ball == 8 then "eight" else "make"
	if wantMake then
		local a, pw = Brain.make(view, plan, rng, yield)
		return decision(kind, plan, a, pw, easy, cueX, cueY)
	end
	local a, pw = Brain.nearMiss(view, plan, rng, yield)
	if a and pw then
		return decision("miss", plan, a, pw, easy, cueX, cueY)
	end
	-- Every near miss fouls or pots: a soft safe hit instead (never a wild shot).
	local safe = Finder.safePlan(view, fromX, fromY)
	return decision("safe", safe, safe.angle, safe.power, easy, cueX, cueY)
end

return Brain
