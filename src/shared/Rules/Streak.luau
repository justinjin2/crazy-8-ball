--!strict
-- The ball streak (designer, 2026-10-09): how many balls the shooting team has potted in a row
-- in its turn at the table, "STREAK x1" up to x8 on everyone's screen (StreakHud), with a spray
-- and, from x3, a little money on each ball (Money.shotPay, ECONOMY 3.1). Pure and deterministic.
--
-- Which balls count is `Streak.counts`, the one rule the pay uses too (a ball counts exactly
-- when it pays its $100), so the screen and the money never disagree:
-- - nothing on a foul shot (designer: a foul that also pots your ball ends the streak, its
--   ball does not raise it);
-- - every object ball on the break, but the break as a whole is x1 however many drop;
-- - the legal pot that picks the colours, and after that only the team's own group;
-- - the 8 only when it wins the game for the shooter;
-- - in Solo every object ball (the player has both groups), so Solo can pass x8.
--
-- Each later counted ball adds one, in the order the balls dropped: two balls in one shot step
-- up twice. A shot with no counted ball, a foul (judged or not: a timeout, a reset), or the
-- table passing to the other team ends the streak. In 2v2 and 3v3 the shooter rotates every
-- shot, so the streak belongs to the team's turn and teammates carry it on.
local Judge = require(script.Parent.ShotJudge)

export type State = { team: number, count: number }

-- One counted ball of a shot and the streak it brings the team to.
export type Step = { index: number, ball: number, level: number }

export type Context = {
	foul: boolean,
	breakShot: boolean,
	groupsBefore: { [number]: string? }, -- team -> "solids"/"stripes" before the shot
	groupsAfter: { [number]: string? }, -- the judgement's groups
	team: number, -- the shooting team
	winner: number?,
	reason: string?, -- "LegalEight" = the 8 won it
	solo: boolean, -- a solo game: both groups are the player's
}

local Streak = {}

--- Whether ball `ball` dropping on this shot counts for the shooting team (ECONOMY 3.1's "each
--- ball that counts for you").
function Streak.counts(ball: number, ctx: Context): boolean
	if ctx.foul or ball == 0 then
		return false
	end
	if ball == 8 then
		return ctx.reason == "LegalEight" and ctx.winner == ctx.team
	end
	local group = Judge.group(ball)
	if group == nil then
		return false
	end
	if ctx.breakShot then
		return true
	end
	local mine = ctx.groupsAfter[ctx.team]
	if mine == nil then
		return false -- still open after the shot: an early 8, never a legal pot
	end
	return ctx.solo or ctx.groupsBefore[ctx.team] == nil or group == mine
end

--- The streak after one accepted shot, and the step each counted ball makes. `drops` are the
--- judgement's drops (deduped, in the order they dropped). `state` is the streak before the
--- shot (nil: none). The returned state is nil when the shot ended the streak.
function Streak.step(
	state: State?,
	drops: { { ball: number, index: number, t: number } },
	ctx: Context
): (State?, { Step })
	local steps: { Step } = {}
	local count = if state and state.team == ctx.team then state.count else 0
	if ctx.breakShot then
		count = 0 -- a new game's first shot: nothing carries over
	end
	local any = false
	for _, drop in drops do
		if Streak.counts(drop.ball, ctx) then
			if ctx.breakShot then
				count = 1 -- the break is x1 however many balls it drops
			else
				count += 1
			end
			any = true
			table.insert(steps, { index = drop.index, ball = drop.ball, level = count })
		end
	end
	if not any then
		return nil, steps
	end
	return { team = ctx.team, count = count }, steps
end

return Streak
