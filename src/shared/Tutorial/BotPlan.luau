--!strict
-- BotPlan: the tutorial bot's shots in game 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4; the
-- designer's pick A, 2026-10-09). Every shot is a real shot searched in our own physics
-- (Bots/Brain.simulate), so it really happens on the table:
--
-- - potScratch: its first visit's second shot pots one of its balls and the cue ball follows
--   it down (a scratch), which hands the player ball in hand. Nil when no such shot exists
--   (the caller falls back to Bots/Script.scratch).
-- - leave: every later visit. It never pots. About half its shots are near misses (its ball
--   stops by the pocket or rattles in the jaws); the rest are quiet soft touches. Either way
--   it leaves the player a makeable shot (Break.lesson finds one) without touching the
--   player's balls or the 8 (unless it nudges the 8 to its spot by a pocket), and never blocks
--   an open 8 (Plan.eightOpen: none of its balls parked where the 8 must be hit from). The
--   best leave is close and good, never a dead-straight hanger: it looks like luck, not a
--   gift. While the player's combination lesson waits, a leave lined up for it scores best.
-- - cleanScratch: the cue ball down and nothing else (or, when no such shot exists, a soft
--   shot that touches nothing): ball in hand for the player, none of their balls moved.
-- - unjam: when even ball in hand could not line up any of their balls, a soft foul that
--   nudges one of them into the open (the jam breaker's first try).
--
-- Pure and seeded (Bots/Rng): no Instances, no clocks.

local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Finder = require(script.Parent.Parent.Bots.ShotFinder)
local Brain = require(script.Parent.Parent.Bots.Brain)
local Placement = require(script.Parent.Parent.Rules.CuePlacement)
local Rng = require(script.Parent.Parent.Bots.Rng)
local Break = require(script.Parent.Break)
local Plan = require(script.Parent.Plan)

type Ball = Ball.Ball
type Rng = Rng.Rng
type View = Finder.View
type Decision = Brain.Decision

local P = Config.Tutorial.BotPlan
local D = 2 * Config.Balls.RadiusInches

local BotPlan = {}

local function decision(
	kind: any,
	angle: number,
	power: number,
	cueX: number?,
	cueY: number?,
	ball: number?,
	spin: any?
): any
	return {
		kind = kind,
		angle = angle,
		power = math.clamp(power, Config.Input.MinPowerToShoot, 1),
		cueX = cueX,
		cueY = cueY,
		called = nil,
		ball = ball,
		pocket = nil,
		easy = true,
		spin = spin,
	}
end

-- The bot's balls and the player's group in this view (the bot plays the other colour).
local function sides(view: View): (string, string)
	local mine = view.groups[view.team] or "stripes"
	return mine, Judge.opposite(mine :: any)
end

-- How far the balls in `watched` moved between two lists (pocketed: 100 each).
local function moved(before: { Ball }, after: { Ball }, watched: { [number]: boolean }): number
	local total = 0
	for _, b in before do
		if watched[b.id] and not b.pocketed then
			local a = Finder.findBall(after, b.id) :: Ball
			if a.pocketed then
				total += 100
			else
				total += math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
			end
		end
	end
	return total
end

--- The first visit's first shot: one of its own balls down, nothing else (none of the
--- player's, never the 8, no scratch), so it keeps the table. Nil when it has no such pot.
function BotPlan.pot(view: View, rng: Rng, ballInHand: boolean?, yield: (() -> ())?): Decision?
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng, yield)
	end
	local mine = sides(view)
	for _, plan in Finder.pots(view, P.PotScratchPlans, cueX, cueY, yield) do
		for _, k in P.PotPower do
			local shot = { angle = plan.angle, power = math.clamp(plan.power * k, 0.05, 1) }
			local trial = Brain.simulate(view, shot, cueX, cueY, nil)
			if yield then
				yield()
			end
			if trial.scratch or trial.winner ~= nil or trial.foul ~= nil or not trial.keep then
				continue
			end
			local clean = #trial.pockets > 0
			for _, id in trial.pockets do
				if Judge.group(id) ~= mine then
					clean = false
				end
			end
			if clean then
				return decision("make", shot.angle, shot.power, cueX, cueY, plan.ball)
			end
		end
	end
	return nil
end

--- The first visit's second shot: one of its balls down and the cue ball after it.
function BotPlan.potScratch(
	view: View,
	rng: Rng,
	ballInHand: boolean?,
	yield: (() -> ())?
): Decision?
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng, yield)
	end
	local mine, theirs = sides(view)
	local plans = Finder.pots(view, P.PotScratchPlans, cueX, cueY, yield)
	for _, plan in plans do
		for _, follow in P.PotScratchFollow do
			for _, k in P.PotScratchPower do
				for _, deg in P.PotScratchTurns do
					local shot = {
						angle = plan.angle + math.rad(deg),
						power = math.clamp(plan.power * k, 0.05, 1),
						spin = { x = 0, y = follow },
					}
					local trial = Brain.simulate(view, shot, cueX, cueY, nil)
					if yield then
						yield()
					end
					if not trial.scratch or trial.winner ~= nil then
						continue
					end
					local own, other = 0, 0
					for _, id in trial.pockets do
						local g = Judge.group(id)
						if id == 8 or g == theirs then
							other += 1
						elseif g == mine then
							own += 1
						end
					end
					if own == 1 and other == 0 then
						return decision(
							"scratch",
							shot.angle,
							shot.power,
							cueX,
							cueY,
							plan.ball,
							shot.spin
						)
					end
				end
			end
		end
	end
	return nil
end

--- The player's next shot after a trial: the easiest straight pot of their group (Break
--- .lesson; the 8 once their group is cleared), and how good a leave it is (higher is better;
--- nil when they have none), with that pot.
function BotPlan.leaveScore(geometry: any, balls: { Ball }, playerGroup: string): (number?, any?)
	local group = if Judge.remaining(balls, playerGroup :: any) == 0 then "eight" else playerGroup
	local lesson = Break.lesson(geometry, balls, group)
	local base = 100
	if lesson == nil or lesson.distance > P.LeaveMaxInches then
		-- No gentle pot: a wider cut still beats a blocked table, scored lower.
		lesson = Break.lesson(geometry, balls, group, false, P.WideCutDegrees)
		base = P.WideScore
		if lesson == nil or lesson.distance > P.LeaveMaxInches then
			return nil, nil
		end
	end
	local pot = lesson :: Break.Lesson
	-- Good but not gifted: a small cut and a short shot score best, a dead-straight hanger
	-- with the cue ball right behind it a little less.
	local score = base - pot.cutDegrees - pot.distance * 0.5
	if pot.cutDegrees < P.GiftCutDegrees and pot.distance < P.GiftInches then
		score -= P.GiftPenalty
	end
	return score, pot
end

--- Every later visit: never a pot; about half near misses; the best leave for the player.
--- `combo`: the player's combination lesson is waiting, so a leave with a clear line onto
--- their pair (Plan.combo) scores ComboLeaveBonus more.
function BotPlan.leave(
	view: View,
	rng: Rng,
	ballInHand: boolean?,
	yield: (() -> ())?,
	stuck: boolean?,
	combo: boolean?
): Decision
	local mine, theirs = sides(view)
	-- Ball in hand ends a jam: a clean scratch, or, when no spot would line up any of their
	-- balls, a soft foul that nudges one into the open first.
	local function jamBreaker(): Decision
		if Plan.handSpot(view.geometry, view.balls, theirs, nil) == nil then
			local d = BotPlan.unjam(view, ballInHand, yield)
			if d then
				return d
			end
		end
		return BotPlan.cleanScratch(view, rng, ballInHand, yield)
	end
	-- The player has missed StuckMisses in a row.
	if stuck then
		return jamBreaker()
	end
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng, yield)
	end
	local cue = Finder.findBall(view.balls, 0) :: Ball
	local cx, cy = cueX or cue.x, cueY or cue.y
	local watched: { [number]: boolean } = {}
	for _, b in view.balls do
		if not b.pocketed and b.id ~= 0 and b.id ~= 8 and Judge.group(b.id) == theirs then
			watched[b.id] = true
		end
	end
	local placed = Break.eightPlaced(view.geometry, view.balls)
	local open = Plan.eightOpen(view.geometry, view.balls)
	local wantNear = Rng.chance(rng, P.NearMissShare)
	-- The search stops early at a good leave (with the combination waiting: one that sets it up).
	local good = if combo then P.GoodLeave + P.ComboLeaveBonus else P.GoodLeave

	-- A trial is usable when nothing drops, nobody fouls, the player's balls stay put and the
	-- 8 stays put (or is nudged to its spot by a pocket); its leave scores it.
	-- The player's side of the table, to check a leave in our physics.
	local playerView = table.clone(view)
	playerView.team = 3 - view.team
	playerView.breakShot = false
	local function judge(trial: any, beat: number): number?
		if trial.winner ~= nil or #trial.pockets > 0 or trial.foul ~= nil then
			return nil
		end
		if moved(view.balls, trial.balls, watched) > P.StillInches then
			return nil
		end
		local eight = moved(view.balls, trial.balls, { [8] = true })
		if
			eight > P.StillInches and (placed or not Break.eightPlaced(view.geometry, trial.balls))
		then
			return nil
		end
		if open and not Plan.eightOpen(view.geometry, trial.balls) then
			return nil -- one of its balls parked where the 8 must be hit from
		end
		local score, lesson = BotPlan.leaveScore(view.geometry, trial.balls, theirs)
		if score and combo and Plan.combo(view.geometry, trial.balls, theirs) then
			score += P.ComboLeaveBonus
		end
		if score == nil or score <= beat then
			return nil
		end
		-- The leave's pot must really go in (a ball deep in the jaws can look easy on paper).
		playerView.balls = trial.balls
		local onEight = lesson.ball == 8
		local check = Brain.simulate(
			playerView,
			{ angle = lesson.angle, power = P.CheckPower },
			nil,
			nil,
			if onEight then lesson.pocket else nil
		)
		if yield then
			yield()
		end
		local made = table.find(check.pockets, lesson.ball) ~= nil
		if
			not made
			or check.foul ~= nil
			or (check.winner ~= nil and check.winner ~= playerView.team)
		then
			return nil
		end
		return score
	end

	local best, bestScore = nil, -math.huge
	local trials = 0
	-- Near misses: its own pots, the aim a little off (Brain.nearMiss's offsets).
	if wantNear then
		for _, plan in Finder.pots(view, P.NearMissPlans, cueX, cueY, yield) do
			for _, deg in Config.Bots.NearMissDegrees do
				for _, sign in { 1, -1 } do
					if bestScore >= good or trials >= P.MaxTrials then
						break
					end
					trials += 1
					local angle = plan.angle + sign * math.rad(deg)
					local trial =
						Brain.simulate(view, { angle = angle, power = plan.power }, cueX, cueY, nil)
					if yield then
						yield()
					end
					local score = judge(trial, bestScore)
					local ob = Finder.findBall(trial.balls, plan.ball)
					if score and ob and not ob.pocketed and plan.pocket then
						local pk = Finder.pocket(view.geometry, plan.pocket)
						local gap = if pk
							then math.sqrt((ob.x - pk.mx) ^ 2 + (ob.y - pk.my) ^ 2)
							else math.huge
						if gap <= Config.Bots.NearInches and score > bestScore then
							best, bestScore =
								decision("miss", angle, plan.power, cueX, cueY, plan.ball), score
						end
					end
				end
			end
		end
	end
	if best then
		return best
	end
	-- Quiet touches: soft hits across each of its balls (Bots/Script.poor's sweep).
	local tries: { { number } } = {}
	for _, b in view.balls do
		if not b.pocketed and b.id ~= 0 and b.id ~= 8 and Judge.group(b.id) == mine then
			local base = math.atan2(b.y - cy, b.x - cx)
			local dist = math.sqrt((b.x - cx) ^ 2 + (b.y - cy) ^ 2)
			local half = math.asin(math.clamp(D * 0.9 / math.max(dist, D), 0, 1))
			for i = 0, P.Sweeps - 1 do
				local f = if P.Sweeps > 1 then i / (P.Sweeps - 1) * 2 - 1 else 0
				for _, power in P.Powers do
					table.insert(tries, { base + half * f, power, b.id })
				end
			end
		end
	end
	for i = #tries, 2, -1 do
		local k = Rng.int(rng, 1, i)
		tries[i], tries[k] = tries[k], tries[i]
	end
	for _, t in tries do
		if bestScore >= good or trials >= P.MaxTrials then
			break
		end
		trials += 1
		local trial = Brain.simulate(view, { angle = t[1], power = t[2] }, cueX, cueY, nil)
		if yield then
			yield()
		end
		local score = judge(trial, bestScore)
		if score and score > bestScore then
			best, bestScore = decision("miss", t[1], t[2], cueX, cueY, t[3]), score
		end
	end
	if best then
		return best
	end
	-- Nothing leaves a pot (the player would be stuck): ball in hand for them.
	return jamBreaker()
end

--- The jam breaker: ball in hand could not line up any of the player's balls (Plan.handSpot
--- finds no spot: say their last ball sits by a corner the 8 blocks, or the 8 is frozen on a
--- rail whose pocket one of the bot's balls blocks), so a clean scratch alone would not help.
--- The bot's cue ball nudges one of their balls (once their group is cleared, the 8) into the
--- open instead (a soft foul, which hands them ball in hand): nothing drops, the 8 otherwise
--- stays put, and afterwards a spot lines that ball up. With ball in hand the bot sets its cue
--- ball right beside the ball. Nil when no such shot is found.
function BotPlan.unjam(view: View, ballInHand: boolean?, yield: (() -> ())?): Decision?
	local U = P.Unjam
	local _, theirs = sides(view)
	local cue = Finder.findBall(view.balls, 0) :: Ball
	local placed = Break.eightPlaced(view.geometry, view.balls)
	-- Once their group is cleared the ball to free is the 8 itself.
	local onEight = Judge.remaining(view.balls, theirs :: any) == 0
	local trials = 0
	for _, b in view.balls do
		local target = if onEight
			then b.id == 8
			else b.id ~= 0 and b.id ~= 8 and Judge.group(b.id) == theirs
		if b.pocketed or not target then
			continue
		end
		local spots: { { number } } = {}
		if ballInHand then
			for _, back in U.BackInches do
				for k = 0, U.Spots - 1 do
					local a = 2 * math.pi * k / U.Spots
					local x, y = b.x + math.cos(a) * (D + back), b.y + math.sin(a) * (D + back)
					if Placement.valid(view.balls, view.geometry, x, y, false) then
						table.insert(spots, { x, y })
					end
				end
			end
		else
			spots = { { cue.x, cue.y } }
		end
		for _, spot in spots do
			local cueX, cueY =
				if ballInHand then spot[1] else nil, if ballInHand then spot[2] else nil
			local angle = math.atan2(b.y - spot[2], b.x - spot[1])
			for _, power in U.Powers do
				trials += 1
				if trials > U.MaxTrials then
					return nil
				end
				local trial =
					Brain.simulate(view, { angle = angle, power = power }, cueX, cueY, nil)
				if yield then
					yield()
				end
				if trial.winner ~= nil then
					continue
				end
				local dropped = false
				for _, id in trial.pockets do
					if id ~= 0 then
						dropped = true
					end
				end
				local eight = if onEight then 0 else moved(view.balls, trial.balls, { [8] = true })
				if
					dropped
					or (
						eight > P.StillInches
						and (placed or not Break.eightPlaced(view.geometry, trial.balls))
					)
				then
					continue
				end
				-- A foul hands them ball in hand: a spot must line a ball up now; otherwise
				-- they shoot from where the cue ball stopped.
				local ready = if trial.foul ~= nil
					then Plan.handSpot(view.geometry, trial.balls, theirs, nil) ~= nil
					else BotPlan.leaveScore(view.geometry, trial.balls, theirs) ~= nil
				if ready then
					return decision("miss", angle, power, cueX, cueY, b.id)
				end
			end
		end
	end
	return nil
end

--- A scratch that pots nothing else: the cue ball into a pocket, none of the player's balls
--- or the 8 down, so the player gets ball in hand (the first visit's fallback, and every
--- later visit's when no quiet shot leaves them a pot). Tries Bots/Script.scratch's shot,
--- then the cue ball straight at each pocket it can reach, nearest first.
function BotPlan.cleanScratch(
	view: View,
	rng: Rng,
	ballInHand: boolean?,
	yield: (() -> ())?
): Decision
	local Script = require(script.Parent.Parent.Bots.Script) :: any
	local first = Script.scratch(view, rng, ballInHand, yield)
	local cueX, cueY = first.cueX, first.cueY
	local cue = Finder.findBall(view.balls, 0) :: Ball
	local fromX, fromY = cueX or cue.x, cueY or cue.y
	local function clean(angle: number, power: number): boolean
		local trial = Brain.simulate(view, { angle = angle, power = power }, cueX, cueY, nil)
		if yield then
			yield()
		end
		if not trial.scratch or trial.winner ~= nil then
			return false
		end
		for _, id in trial.pockets do
			if id ~= 0 then
				return false
			end
		end
		return true
	end
	if clean(first.angle, first.power) then
		return first
	end
	local pockets = table.clone(Finder.pockets(view.geometry))
	table.sort(pockets, function(a, b)
		return (a.mx - fromX) ^ 2 + (a.my - fromY) ^ 2 < (b.mx - fromX) ^ 2 + (b.my - fromY) ^ 2
	end)
	for _, pk in pockets do
		local straight = math.atan2(pk.my - fromY, pk.mx - fromX)
		local dist = math.sqrt((pk.mx - fromX) ^ 2 + (pk.my - fromY) ^ 2)
		for _, turn in P.ScratchFanDegrees do
			local angle = straight + math.rad(turn)
			for _, extra in P.ScratchExtraSpeeds do
				local power = Finder.powerForSpeed(dist + extra)
				if clean(angle, power) then
					return decision("scratch", angle, power, cueX, cueY, nil)
				end
			end
		end
	end
	-- No clean scratch: a soft shot that touches nothing (a no-contact foul), so the player
	-- still gets ball in hand and none of their balls moves.
	local power = Finder.powerForSpeed(P.WhiffSpeed)
	for i = 0, P.WhiffSweeps - 1 do
		local angle = 2 * math.pi * i / P.WhiffSweeps
		local trial = Brain.simulate(view, { angle = angle, power = power }, cueX, cueY, nil)
		if yield then
			yield()
		end
		if trial.foul == "NoContact" and trial.winner == nil and #trial.pockets == 0 then
			return decision("scratch", angle, power, cueX, cueY, nil)
		end
	end
	return first
end

return BotPlan
