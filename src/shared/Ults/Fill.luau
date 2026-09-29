--!strict
-- The ult bar's fill (docs/prompts/ULTIMATES_PROMPT.md sections 4 and 5; every number is in
-- Config.Ults.Fill): events in, gains with their reasons out. Pure: no Instances, no Roblox
-- APIs, no clocks, no randomness, and every list is walked as an array (seats in their given
-- order, drops in time order), never hash order, so the same shot always gives the same gains
-- in the same order.
--
-- One bar per player: `{ bar, used, turnFill }` (Fill.newBar). The match rules keep one per
-- seat in a map keyed by `tostring(userId)` and pass that map in; Fill changes the bars in
-- place and also returns every gain, so the server can send each with its reason and the
-- client only animates.
--
-- How it is called (the match rules, at shot acceptance, with what the engine knows):
--   local result = Fill.shot({
--       seats = { { userId = 1, team = 1 }, { userId = 2, team = 2 } }, -- still in the match
--       bars = bars, shooter = 1, team = 1, difficulty = "Classic",
--       breakShot = false,
--       groupsBefore = { "solids", "stripes" }, groupsAfter = { ... }, -- ShotJudge's groups
--       ballsBefore = state.balls, -- { id, pocketed }: the table before the shot
--       openPotted = { 0, 0 }, -- balls each side pocketed while the table was open
--       drops = { { ball = 3, t = 1.2, nice = false } }, -- chronological, never the cue ball
--       run = runSoFar, turnEnds = not keep, legal = not foul, ultShot = armed,
--   })
--   -- result.gains: { { userId, amount, reason, ball?, t? } }; result.run: the next run.
-- and `Fill.timeout` when a turn ends with no shot (the shot clock ran out).
--
-- The rules, for each bar owner P on side s (a "side" is a team, 1 or 2):
-- * Whose ball: once groups exist (groupsBefore), a ball belongs to the side playing its group.
--   On an open table (the break included) every ball but the 8 that drops belongs to the
--   shooter's side: the break's balls are the breaker's own.
-- * The shooter's own-side ball gives the shooter the run fill: Own[1], Own[2], ... then
--   OwnAfter for each ball after, the run continuing across the shots of one turn (`run`), plus
--   Nice on top for a nice pot. It gives each teammate of the shooter Teammate.
-- * A ball of the other side than P's, whoever pocketed it, gives P OppBase + OppPerBehind x
--   (the balls P's side is behind after that ball; never negative).
-- * P's own side's balls pocketed on an opponent's shot give P nothing. The 8 fills nothing.
-- * "Behind": with groups, your side's balls left minus the other side's (a cleared group
--   counts 0 left). On an open table, the balls the other side has pocketed minus yours
--   (openPotted plus this shot's balls so far).
-- * Turn end (`turnEnds`, or Fill.timeout): the shooter gets TurnLegal when the shot was
--   `legal` (never on a timeout), and every player on the other side gets OppTurn. Both are
--   turn-end fill: `turnFill` counts what was given and never passes TurnCap (not scaled).
-- * Every gain x Difficulty[difficulty] (1 for an unknown difficulty); after a player's first
--   ult (used >= 1) x AfterFirst too, and their turn cap counts again from 0 (Fill.spend
--   resets turnFill). At MaxPerMatch ults used a bar stays 0 and gets nothing.
-- * An ult shot: balls pocketed on it fill nothing for its user (section 4: "Balls pocketed on
--   an ult shot fill nothing for the user"), neither the run, a nice shot nor an opponent's
--   ball; the run still counts them. Everyone else fills as normal, and the user's turn end
--   still counts.
-- * Each gain is rounded half up after its multipliers, cut so the bar never passes BarMax, and
--   dropped when that leaves 0.
local Config = require(script.Parent.Parent.Config)

local U = Config.Ults
local F = U.Fill

local Fill = {}

export type Bar = {
	bar: number, -- 0..Config.Ults.BarMax
	used: number, -- ults used this match
	turnFill: number, -- turn-end fill given since the match start or the last ult
}

export type Reason = "Own" | "Nice" | "Opponent" | "Teammate" | "Turn" | "OpponentTurn"

export type Gain = {
	userId: number,
	amount: number, -- whole, >= 1, what the bar actually rose by
	reason: Reason,
	ball: number?, -- the ball that gave it (not for turn ends)
	t: number?, -- that ball's drop time in the shot, so the client animates it as it drops
}

export type Seat = { userId: number, team: number }
export type BallLike = { id: number, pocketed: boolean }
export type Drop = { ball: number, t: number, nice: boolean? }

export type ShotContext = {
	seats: { Seat }, -- the players still in the match, both sides
	bars: { [string]: Bar }, -- tostring(userId) -> bar, changed in place (made if missing)
	shooter: number, -- the shooter's userId
	team: number, -- the shooter's side, 1 or 2
	difficulty: string, -- "Classic", "Difficult" or "Challenger"
	breakShot: boolean?,
	groupsBefore: { [number]: string }, -- side -> "solids" | "stripes" (ShotJudge's groups)
	groupsAfter: { [number]: string }?, -- not needed by the rules above; kept for callers
	ballsBefore: { BallLike }, -- the balls before the shot
	openPotted: { [number]: number }?, -- side -> balls pocketed while the table was open
	drops: { Drop }, -- chronological, never the cue ball
	run: number?, -- the shooter's own balls already pocketed this turn
	turnEnds: boolean?, -- the shot ends the shooter's turn and the game goes on
	legal: boolean?, -- no foul
	ultShot: boolean?, -- the shooter's ult is armed for this shot
}

export type TimeoutContext = {
	seats: { Seat },
	bars: { [string]: Bar },
	shooter: number, -- the player whose turn timed out
	team: number, -- their side
	difficulty: string,
}

export type ShotResult = {
	gains: { Gain },
	run: number, -- the run to pass to the shooter's next shot this turn (0 once the turn ends)
}

--- A new bar: empty, no ult used.
function Fill.newBar(): Bar
	return { bar = 0, used = 0, turnFill = 0 }
end

--- True when the bar is full and the player may still use an ult this match.
function Fill.ready(bar: Bar): boolean
	return bar.bar >= U.BarMax and bar.used < U.MaxPerMatch
end

--- The ult is used: the bar empties, `used` goes up by one and the turn cap counts again.
function Fill.spend(bar: Bar)
	bar.bar = 0
	bar.used += 1
	bar.turnFill = 0
end

-- A ball's group by number, as ShotJudge.group: 1-7 solids, 9-15 stripes, else nil.
local function groupOf(id: number): string?
	if id % 1 ~= 0 then
		return nil
	elseif id >= 1 and id <= 7 then
		return "solids"
	elseif id >= 9 and id <= 15 then
		return "stripes"
	end
	return nil
end

--- How many balls side `side` (1 or 2) is behind the other, never negative. With `groups`
--- (side -> "solids"/"stripes") it compares the balls each side has left on `balls` (a
--- cleared group counts 0); on an open table (no group for `side`) it compares `openPotted`,
--- the balls each side has pocketed.
function Fill.behind(
	groups: { [number]: string },
	balls: { BallLike },
	side: number,
	openPotted: { [number]: number }?
): number
	local mine = groups[side]
	local theirs = groups[3 - side]
	if mine ~= nil and theirs ~= nil then
		local left = { [mine] = 0, [theirs] = 0 }
		for _, ball in balls do
			local group = groupOf(ball.id)
			if group ~= nil and not ball.pocketed and left[group] ~= nil then
				left[group] += 1
			end
		end
		return math.max(0, left[mine] - left[theirs])
	end
	local potted = openPotted or {}
	return math.max(0, (potted[3 - side] or 0) - (potted[side] or 0))
end

-- Round half up, with a hair of slack so 5 x 1.3 (6.5000000000000004 or 6.4999999999999996)
-- always rounds the same way.
local function roundHalfUp(x: number): number
	return math.floor(x + 0.5 + 1e-9)
end

-- The multiplier for a table's difficulty (1 for an unknown one).
local function difficultyScale(difficulty: string): number
	local scales: { [string]: number } = F.Difficulty :: any
	return scales[difficulty] or 1
end

-- The player's bar in `bars`, made if missing.
local function barOf(bars: { [string]: Bar }, userId: number): Bar
	local key = tostring(userId)
	local bar = bars[key]
	if bar == nil then
		bar = Fill.newBar()
		bars[key] = bar
	end
	return bar
end

-- Gives `base` (before multipliers) to `userId`'s bar and records the gain. Turn-end gains
-- (`turnEnd`) also respect the turn cap. Returns nothing; a gain that comes to 0 is dropped.
local function give(
	gains: { Gain },
	bars: { [string]: Bar },
	scale: number,
	userId: number,
	base: number,
	reason: Reason,
	turnEnd: boolean,
	ball: number?,
	t: number?
)
	local bar = barOf(bars, userId)
	if bar.used >= U.MaxPerMatch then
		bar.bar = 0
		return
	end
	local amount = base * scale
	if bar.used >= 1 then
		amount *= F.AfterFirst
	end
	amount = roundHalfUp(amount)
	if turnEnd then
		amount = math.min(amount, F.TurnCap - bar.turnFill)
	end
	amount = math.min(amount, U.BarMax - bar.bar)
	if amount <= 0 then
		return
	end
	bar.bar += amount
	if turnEnd then
		bar.turnFill += amount
	end
	table.insert(gains, { userId = userId, amount = amount, reason = reason, ball = ball, t = t })
end

-- The turn-end fill: TurnLegal to the shooter when `legal`, OppTurn to the other side.
local function turnEnd(
	gains: { Gain },
	seats: { Seat },
	bars: { [string]: Bar },
	scale: number,
	shooter: number,
	team: number,
	legal: boolean
)
	for _, seat in seats do
		if seat.userId == shooter then
			if legal then
				give(gains, bars, scale, seat.userId, F.TurnLegal, "Turn", true)
			end
		elseif seat.team ~= team then
			give(gains, bars, scale, seat.userId, F.OppTurn, "OpponentTurn", true)
		end
	end
end

-- The run fill for the shooter's `n`-th own ball this turn (1-based).
local function runFill(n: number): number
	return F.Own[n] or F.OwnAfter
end

--- Fills the bars for one accepted shot (see the header for `ctx` and the rules). Returns every
--- gain in order (by drop, then seat order, then the turn end) and the shooter's run to pass to
--- their next shot of this turn (0 when `turnEnds`).
function Fill.shot(ctx: ShotContext): ShotResult
	local gains: { Gain } = {}
	local scale = difficultyScale(ctx.difficulty)
	local team = ctx.team
	local groups = ctx.groupsBefore or {}
	local open = groups[team] == nil or groups[3 - team] == nil
	local run = math.max(0, ctx.run or 0)

	-- The table as it changes ball by ball: groups left (with groups) or balls pocketed per
	-- side (open).
	local balls: { BallLike } = {}
	for _, ball in ctx.ballsBefore do
		table.insert(balls, { id = ball.id, pocketed = ball.pocketed })
	end
	local potted: { [number]: number } = { 0, 0 }
	if ctx.openPotted ~= nil then
		potted[1] = ctx.openPotted[1] or 0
		potted[2] = ctx.openPotted[2] or 0
	end

	for _, drop in ctx.drops do
		local id = drop.ball
		local group = groupOf(id)
		if group ~= nil then -- the 8 and the cue ball fill nothing
			-- Mark it pocketed (once) and find whose it is.
			for _, ball in balls do
				if ball.id == id then
					ball.pocketed = true
				end
			end
			local side: number
			if open then
				side = team
				potted[team] += 1
			else
				side = if groups[1] == group then 1 else 2
			end
			local own = side == team
			if own then
				run += 1
			end
			for _, seat in ctx.seats do
				local user = seat.userId
				local isUser = user == ctx.shooter
				if own and isUser then
					if not ctx.ultShot then
						give(gains, ctx.bars, scale, user, runFill(run), "Own", false, id, drop.t)
						if drop.nice then
							give(gains, ctx.bars, scale, user, F.Nice, "Nice", false, id, drop.t)
						end
					end
				elseif own and seat.team == team then
					give(gains, ctx.bars, scale, user, F.Teammate, "Teammate", false, id, drop.t)
				elseif seat.team ~= side and not (isUser and ctx.ultShot) then
					local behind = Fill.behind(groups, balls, seat.team, potted)
					local base = F.OppBase + F.OppPerBehind * behind
					give(gains, ctx.bars, scale, user, base, "Opponent", false, id, drop.t)
				end
			end
		end
	end

	if ctx.turnEnds then
		turnEnd(gains, ctx.seats, ctx.bars, scale, ctx.shooter, team, ctx.legal == true)
		run = 0
	end
	return { gains = gains, run = run }
end

--- A turn that ended with no shot (the shot clock ran out): the player who timed out gets
--- nothing, and every player on the other side gets OppTurn (turn-end fill, capped).
function Fill.timeout(ctx: TimeoutContext): { gains: { Gain } }
	local gains: { Gain } = {}
	turnEnd(
		gains,
		ctx.seats,
		ctx.bars,
		difficultyScale(ctx.difficulty),
		ctx.shooter,
		ctx.team,
		false
	)
	return { gains = gains }
end

return Fill
