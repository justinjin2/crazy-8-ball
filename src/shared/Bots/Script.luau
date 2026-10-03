--!strict
-- Scripted shots for the tutorial bot (the designer, 2026-10-02): in its first visit it pots
-- one of its balls and then scratches, so the new player sees a scratch and ball in hand; in
-- its next visit it aims at one of its own balls and knocks the 8 in by accident, losing the
-- game. Every shot is searched for in our physics, so it really happens; pure and seeded.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Finder = require(script.Parent.ShotFinder)
local Brain = require(script.Parent.Brain)
local Rng = require(script.Parent.Rng)

type Ball = Ball.Ball
type Rng = Rng.Rng
type View = Finder.View
type Decision = Brain.Decision

local D = 2 * Config.Balls.RadiusInches

local Script = {}

-- The visits, in order (the server counts the bot's visits).
Script.Visits = { "PotThenScratch", "EightBlunder" }

local function decision(
	kind: any,
	angle: number,
	power: number,
	cueX: number?,
	cueY: number?,
	ball: number?,
	called: number?
): Decision
	return {
		kind = kind,
		angle = angle,
		power = math.clamp(power, Config.Input.MinPowerToShoot, 1),
		cueX = cueX,
		cueY = cueY,
		called = called,
		ball = ball,
		pocket = nil,
		easy = true,
	}
end

--- A pot it really makes (nil when it has no pot at all).
function Script.pot(view: View, rng: Rng, ballInHand: boolean?, yield: (() -> ())?): Decision?
	local d = Brain.decide(
		view,
		"Reyes",
		rng,
		{ forceMake = true, ballInHand = ballInHand, yield = yield }
	)
	if d.kind ~= "make" and d.kind ~= "eight" then
		return nil
	end
	local trial = Brain.simulate(view, d, d.cueX, d.cueY, d.called)
	if trial.foul ~= nil or not trial.keep then
		return nil
	end
	return d
end

--- A scratch that looks like a try: aimed at one of its balls, the cue ball drops (with no
--- 8). Failing that, the cue ball sent into the nearest open pocket.
function Script.scratch(view: View, rng: Rng, ballInHand: boolean?, yield: (() -> ())?): Decision
	local cue = Finder.findBall(view.balls, 0) :: Ball
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng, yield)
	end
	local fromX, fromY = cueX or cue.x, cueY or cue.y
	local plans = Finder.pots(view, 3, cueX, cueY, yield)
	if #plans == 0 then
		table.insert(plans, Finder.safePlan(view, fromX, fromY))
	end
	for _, plan in plans do
		local a, p = Brain.scratch(view, plan, rng, yield)
		if a and p then
			local trial = Brain.simulate(view, { angle = a, power = p }, cueX, cueY, plan.called)
			if trial.winner == nil then
				return decision("scratch", a, p, cueX, cueY, plan.ball, plan.called)
			end
		end
	end
	-- A straight line into a pocket the cue ball can reach.
	local best, bestD = nil, math.huge
	for _, pk in Finder.pockets(view.geometry) do
		local clear = true
		for _, b in view.balls do
			if
				not b.pocketed
				and b.id ~= 0
				and Finder.segmentDistance(b.x, b.y, fromX, fromY, pk.mx, pk.my) < D
			then
				clear = false
				break
			end
		end
		local d = math.sqrt((pk.mx - fromX) ^ 2 + (pk.my - fromY) ^ 2)
		if clear and d < bestD then
			best, bestD = pk, d
		end
	end
	if best then
		local angle = math.atan2(best.my - fromY, best.mx - fromX)
		return decision("scratch", angle, Finder.powerForSpeed(80 + bestD), cueX, cueY, nil, nil)
	end
	-- Nowhere open (never on a real table): a hard hit at its nearest ball.
	local plan = Finder.safePlan(view, fromX, fromY)
	return decision("scratch", plan.angle, 1, cueX, cueY, plan.ball, plan.called)
end

-- Whether a trial loses on the 8 with an own ball hit first (it looks like a try at its ball).
local function eightLoss(view: View, trial: Brain.Trial): boolean
	if trial.winner ~= 3 - view.team then
		return false
	end
	for _, id in trial.pockets do
		if id == 8 then
			return trial.foul ~= "WrongContact"
		end
	end
	return false
end

--- The blunder: aimed at one of its balls, the 8 goes down early and it loses. Searched in
--- order: combinations (its ball into the 8 into a pocket), then a sweep across each of its
--- balls at several powers, then (never seen on a normal table) a pot of the 8 itself.
function Script.eightBlunder(
	view: View,
	rng: Rng,
	ballInHand: boolean?,
	yield: (() -> ())?
): Decision
	local cue = Finder.findBall(view.balls, 0) :: Ball
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng, yield)
	end
	local cx, cy = cueX or cue.x, cueY or cue.y
	local eight = Finder.findBall(view.balls, 8)
	local own = Finder.ownIds(view)
	local tries: { { number } } = {}
	if eight and not eight.pocketed then
		-- Combinations: its ball b sent at the 8's ghost ball for each pocket.
		for _, pk in Finder.pockets(view.geometry) do
			local ux, uy = pk.mx - eight.x, pk.my - eight.y
			local du = math.sqrt(ux * ux + uy * uy)
			if du < 1e-6 then
				continue
			end
			local g8x, g8y = eight.x - ux / du * D, eight.y - uy / du * D
			for _, id in own do
				local b = Finder.findBall(view.balls, id) :: Ball
				local vx, vy = g8x - b.x, g8y - b.y
				local dv = math.sqrt(vx * vx + vy * vy)
				if dv < 1e-6 then
					continue
				end
				local gbx, gby = b.x - vx / dv * D, b.y - vy / dv * D
				local angle = math.atan2(gby - cy, gbx - cx)
				for _, power in { 0.55, 0.7, 0.85, 1 } do
					table.insert(tries, { angle, power, id })
				end
			end
		end
	end
	-- Sweeps across each of its balls, from a thin hit on one side to the other.
	for _, id in own do
		local b = Finder.findBall(view.balls, id) :: Ball
		local base = math.atan2(b.y - cy, b.x - cx)
		local dist = math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2)
		local half = math.asin(math.clamp(D * 0.95 / math.max(dist, D), 0, 1))
		for i = 0, 10 do
			for _, power in { 0.6, 0.85, 1 } do
				table.insert(tries, { base + half * (i / 5 - 1), power, id })
			end
		end
	end
	for _, t in tries do
		local trial = Brain.simulate(view, { angle = t[1], power = t[2] }, cueX, cueY)
		if yield then
			yield()
		end
		if eightLoss(view, trial) then
			return decision("eight", t[1], t[2], cueX, cueY, t[3], nil)
		end
	end
	-- Nothing of its own sends the 8 down: pot the 8 itself (it still loses the game).
	if eight and not eight.pocketed then
		local v = table.clone(view)
		v.groups = table.clone(view.groups)
		local mine = view.groups[view.team]
		if mine then
			-- Pretend its group is cleared so the finder offers the 8.
			local balls = Ball.cloneList(view.balls)
			for _, b in balls do
				if Judge.group(b.id) == mine then
					b.pocketed = true
				end
			end
			v.balls = balls
		end
		for _, plan in Finder.candidates(v, cueX, cueY) do
			if plan.ball == 8 and Finder.calibrate(v, plan) then
				return decision("eight", plan.angle, plan.power, cueX, cueY, 8, nil)
			end
		end
		return decision("eight", math.atan2(eight.y - cy, eight.x - cx), 1, cueX, cueY, 8, nil)
	end
	return decision("eight", 0, 0.5, cueX, cueY, nil, nil)
end

local _ = Rng
return Script
