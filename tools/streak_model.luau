--!strict
-- How long pocketing streaks get, to price a streak money bonus. The bot duel's game loop
-- (tests/bot_duel.luau `Duel.game`, copied here unchanged in its shots and its rng order, so
-- the games are the same games): a model player of a rank (side 1, breaks) against the bot of
-- the same tier (side 2). Every shot of both sides is instrumented.
--
-- Which balls count is Money.luau's local `counts` exactly: nothing on a foul shot; never the
-- cue ball; the 8 only when it legally wins for the shooter; every object ball on the break;
-- otherwise a ball counts when the shooter has a group after the shot and (had none before it,
-- or the ball is in that group).
--
-- The streak, per side and per turn at the table: a break that drops a counted ball makes it 1
-- (every break ball recorded at n = 1); after that each counted ball, in drop order, raises it
-- by 1 and is recorded at its new n. A shot with no counted ball (a foul included) ends it, and
-- so does the turn passing.
--
-- Usage (from the repo root):
--   lune run tools/streak_model.luau                         # the 8 tiers, 200 games each
--   lune run tools/streak_model.luau Gold --games 50
--   lune run tools/streak_model.luau --out /path/results.json  # also the full numbers as JSON
--   lune run tools/streak_model.luau --jobs 1                # one process (default: a tier each,
--                                                              8 at once)

local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local task = require("@lune/task")

local Duel = require("../tests/bot_duel")
local H = require("../tests/harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Rack = H.require("Physics.Rack")
local Judge = H.require("Rules.ShotJudge")
local Placement = H.require("Rules.CuePlacement")
local Finder = H.require("Bots.ShotFinder")
local Brain = H.require("Bots.Brain")
local Rng = H.require("Bots.Rng")

local BALL_PAY: number = (Config.Economy :: any).BallPay
local DEFAULT_TIERS =
	{ "Bronze", "Silver", "Gold", "Platinum", "Diamond", "Expert", "Master", "Reyes" }
local BUCKETS = 8 -- n = 1..7, then 8+
local PEAKS = { 3, 5, 8 }

-- The candidate bonus curves: the bonus on a ball recorded at streak n, as a share of BallPay.
local CURVES: { { name: string, rule: string, share: (n: number) -> number } } = {
	{
		name = "A",
		rule = "n>=2: 0.10*(n-1)",
		share = function(n)
			return if n >= 2 then 0.10 * (n - 1) else 0
		end,
	},
	{
		name = "B",
		rule = "n>=3: 0.25*(n-2)",
		share = function(n)
			return if n >= 3 then 0.25 * (n - 2) else 0
		end,
	},
	{
		name = "C",
		rule = "n>=2: 0.25*(n-1)",
		share = function(n)
			return if n >= 2 then 0.25 * (n - 1) else 0
		end,
	},
}

local geometry = Duel.geometry

---------------------------------------------------------------------------------------------
-- The duel's game loop (copied from tests/bot_duel.luau; keep the shots and rng calls equal)
---------------------------------------------------------------------------------------------

local function playerShot(
	view: any,
	skill: { aim: number, power: number },
	rng: any,
	ballInHand: boolean
): any
	if view.breakShot then
		local d = Brain.breakShot(view, rng)
		return d
	end
	local cueX, cueY = nil, nil
	if ballInHand then
		cueX, cueY = Brain.placeCue(view, Brain.tier("Gold"), rng)
	end
	local plan = Finder.pots(view, 1, cueX, cueY)[1]
	local cue = Finder.findBall(view.balls, 0)
	if plan == nil then
		plan = Finder.safePlan(view, cueX or cue.x, cueY or cue.y)
	end
	local speedShare = 1 + skill.power * Rng.gauss(rng)
	return {
		angle = plan.angle + math.rad(skill.aim) * Rng.gauss(rng),
		power = math.clamp(plan.power * math.max(0.3, speedShare), 0.04, 1),
		cueX = cueX,
		cueY = cueY,
		called = plan.called,
		ball = plan.ball,
		kind = if plan.safe then "safe" else "pot",
	}
end

local function settleTable(trial: any): { any }
	local balls = Ball.cloneList(trial.balls)
	for _, b in balls do
		b.falling, b.tip = false, nil
		if not b.pocketed then
			b.z = 0
		end
		Ball.stop(b)
	end
	for _, id in trial.respot do
		local b = Finder.findBall(balls, id)
		if b then
			b.pocketed, b.offTable = false, false
			b.z = 0
		end
	end
	if #trial.respot > 0 then
		for _, id in trial.respot do
			local b = Finder.findBall(balls, id)
			local state = { balls = balls, geometry = geometry, time = 0 }
			local x, y = Placement.fallback(state :: any, id, false)
			b.x, b.y = x, y
		end
	end
	if trial.respotEight then
		local eight = Finder.findBall(balls, 8)
		eight.pocketed, eight.offTable, eight.z = false, false, 0
		Placement.respotEight(balls, geometry)
	end
	local cue = Finder.findBall(balls, 0)
	if cue.pocketed or cue.offTable then
		cue.pocketed, cue.offTable, cue.z = false, false, 0
		local x, y = Placement.fallback(balls, geometry, false)
		cue.x, cue.y = x, y
	end
	return balls
end

---------------------------------------------------------------------------------------------
-- Counting and the streak
---------------------------------------------------------------------------------------------

-- The balls of this shot that count for the shooter, in drop order (Money.luau `counts`).
-- `trial.winner == shooter` only ever comes from Judge's "LegalEight".
local function countedBalls(
	trial: any,
	groupsBefore: any,
	shooter: number,
	breakShot: boolean
): { number }
	local out = {}
	if trial.foul then
		return out
	end
	for _, id in trial.pockets do
		if id == 0 then
			continue
		end
		if id == 8 then
			if trial.winner == shooter then
				table.insert(out, id)
			end
			continue
		end
		local group = Judge.group(id)
		if group == nil then
			continue
		end
		if breakShot then
			table.insert(out, id)
			continue
		end
		local mine = trial.groups[shooter]
		if mine == nil then
			continue
		end
		if groupsBefore[shooter] == nil or group == mine then
			table.insert(out, id)
		end
	end
	return out
end

type Side = {
	balls: number, -- counted balls
	at: { number }, -- counted balls recorded at n = 1..7, 8+ (index 8)
	peak: number,
	bonus: { number }, -- per curve, the sum of shares of BallPay
	breakBalls: number, -- counted on the break
	openBalls: number, -- counted on the shot that picked the groups
	openCross: number, -- of those, balls of the group the shooter did NOT get
	runs: number, -- turns at the table with at least one counted ball
}

local function newSide(): Side
	local at, bonus = {}, {}
	for i = 1, BUCKETS do
		at[i] = 0
	end
	for i = 1, #CURVES do
		bonus[i] = 0
	end
	return {
		balls = 0,
		at = at,
		peak = 0,
		bonus = bonus,
		breakBalls = 0,
		openBalls = 0,
		openCross = 0,
		runs = 0,
	}
end

local function record(side: Side, n: number)
	side.balls += 1
	local k = math.min(n, BUCKETS)
	side.at[k] += 1
	for i, curve in CURVES do
		side.bonus[i] += curve.share(n)
	end
end

--- One game (Duel.game's loop) with every shot of both sides counted.
local function game(seed: number, tier: string): any
	local rng = Rng.new(Rng.seedOf(seed, 17))
	local skill = Duel.PLAYER_SKILL[tier]
	local balls = Rack.newGame(geometry, seed)
	local groups: { [number]: string } = {}
	local shooter, breakShot, hand = 1, true, false
	local sides = { newSide(), newSide() }
	local streak = 0
	local capped = 0
	local winner = 0
	local shots = 0
	for _ = 1, Duel.MAX_SHOTS do
		shots += 1
		local view = {
			geometry = geometry,
			balls = balls,
			groups = groups,
			team = shooter,
			breakShot = breakShot,
			requireRail = false,
		}
		local d
		if shooter == 2 then
			d = Brain.decide(view :: any, tier, rng, { ballInHand = hand })
		else
			d = playerShot(view, skill, rng, hand)
		end
		local mine = groups[shooter]
		local called = d.called
		if called == nil and mine ~= nil and Judge.eligible(balls, mine) then
			local eight = Finder.findBall(balls, 8)
			called = Finder.nearestPocket(geometry, eight.x, eight.y)
		end
		local trial = Brain.simulate(view :: any, d, d.cueX, d.cueY, called)

		-- The streak.
		local side = sides[shooter]
		local counted = countedBalls(trial, groups, shooter, breakShot)
		if trial.foul == "Capped" then
			capped += 1
		end
		if #counted == 0 then
			streak = 0
		else
			if streak == 0 then
				side.runs += 1
			end
			local picked = not breakShot and groups[shooter] == nil
			for _, id in counted do
				if breakShot then
					streak = 1
					side.breakBalls += 1
				else
					streak += 1
					if picked then
						side.openBalls += 1
						if id ~= 8 and Judge.group(id) ~= trial.groups[shooter] then
							side.openCross += 1
						end
					end
				end
				record(side, streak)
			end
			side.peak = math.max(side.peak, streak)
		end

		if trial.winner then
			winner = trial.winner
			break
		end
		groups = trial.groups
		balls = settleTable(trial)
		local before = shooter
		if trial.foul and trial.foul ~= "Capped" then
			shooter, hand = 3 - shooter, true
		elseif trial.keep then
			hand = false
		else
			shooter, hand = 3 - shooter, false
		end
		if shooter ~= before then
			streak = 0
		end
		breakShot = false
	end
	return { sides = sides, winner = winner, capped = capped, shots = shots }
end

---------------------------------------------------------------------------------------------
-- Summaries
---------------------------------------------------------------------------------------------

local function newTotals(): any
	local t = newSide()
	local totals: any = t
	totals.games = 0
	totals.peakAtLeast = {}
	for i = 1, #PEAKS do
		totals.peakAtLeast[i] = 0
	end
	totals.peakSum = 0
	return totals
end

local function add(totals: any, side: Side)
	totals.games += 1
	totals.balls += side.balls
	for i = 1, BUCKETS do
		totals.at[i] += side.at[i]
	end
	for i = 1, #CURVES do
		totals.bonus[i] += side.bonus[i]
	end
	totals.breakBalls += side.breakBalls
	totals.openBalls += side.openBalls
	totals.openCross += side.openCross
	totals.runs += side.runs
	totals.peakSum += side.peak
	for i, p in PEAKS do
		if side.peak >= p then
			totals.peakAtLeast[i] += 1
		end
	end
end

local function summary(t: any): any
	local g = math.max(1, t.games)
	local b = math.max(1, t.balls)
	local shares = {}
	local atLeast3, atLeast5 = 0, 0
	for i = 1, BUCKETS do
		shares[i] = t.at[i] / b
		if i >= 3 then
			atLeast3 += t.at[i]
		end
		if i >= 5 then
			atLeast5 += t.at[i]
		end
	end
	local peaks = {}
	for i, p in PEAKS do
		peaks[("atLeast%d"):format(p)] = t.peakAtLeast[i] / g
	end
	local curves = {}
	for i, curve in CURVES do
		curves[curve.name] = {
			rule = curve.rule,
			perBallShare = t.bonus[i] / b,
			dollarsPerGame = t.bonus[i] * BALL_PAY / g,
		}
	end
	return {
		games = t.games,
		ballsPerGame = t.balls / g,
		shareAtN = shares, -- index 1..7 = n, index 8 = 8+
		shareAtLeast3 = atLeast3 / b,
		shareAtLeast5 = atLeast5 / b,
		peakShare = peaks,
		meanPeak = t.peakSum / g,
		curves = curves,
		breakBallsPerGame = t.breakBalls / g,
		openBallsPerGame = t.openBalls / g,
		openCrossPerGame = t.openCross / g,
		runsPerGame = t.runs / g,
		ballsPerRun = if t.runs > 0 then t.balls / t.runs else 0,
	}
end

-- Equal-weight mean of a list of summaries (numbers and nested tables of numbers).
local function average(list: { any }): any
	local function mean(values: { any }): any
		local first = values[1]
		if type(first) == "number" then
			local s = 0
			for _, v in values do
				s += v
			end
			return s / #values
		elseif type(first) == "table" then
			local out = {}
			for k in first do
				local column = {}
				for _, v in values do
					table.insert(column, v[k])
				end
				out[k] = mean(column)
			end
			return out
		end
		return first
	end
	return mean(list)
end

local function pct(x: number): string
	return ("%4.1f"):format(x * 100)
end

local function row(label: string, s: any): string
	local parts = { ("%-12s %5.2f "):format(label, s.ballsPerGame) }
	for i = 1, BUCKETS do
		table.insert(parts, pct(s.shareAtN[i]))
	end
	table.insert(
		parts,
		(" | %s %s | %s %s %s | %4.2f"):format(
			pct(s.shareAtLeast3),
			pct(s.shareAtLeast5),
			pct(s.peakShare.atLeast3),
			pct(s.peakShare.atLeast5),
			pct(s.peakShare.atLeast8),
			s.meanPeak
		)
	)
	for _, curve in CURVES do
		table.insert(
			parts,
			(" | %s %5.3f %6.1f"):format(
				curve.name,
				s.curves[curve.name].perBallShare,
				s.curves[curve.name].dollarsPerGame
			)
		)
	end
	return table.concat(parts, " ")
end

local HEADER = "side          b/g   n=1  n=2  n=3  n=4  n=5  n=6  n=7  8+  | >=3  >=5  | pk3  pk5  pk8 | pkμ "
	.. " | curve: bonus/ball (xBallPay), $/game"

---------------------------------------------------------------------------------------------
-- Command line
---------------------------------------------------------------------------------------------

-- One tier's games, summed and summarised.
local function runTier(tier: string, games: number, seed: number): any
	local started = os.clock()
	local totals = { newTotals(), newTotals() }
	local wins, noResult, capped, shots = 0, 0, 0, 0
	for g = 1, games do
		local r = game(Rng.seedOf(seed, g), tier)
		add(totals[1], r.sides[1])
		add(totals[2], r.sides[2])
		if r.winner == 1 then
			wins += 1
		elseif r.winner == 0 then
			noResult += 1
		end
		capped += r.capped
		shots += r.shots
	end
	return {
		player = summary(totals[1]),
		bot = summary(totals[2]),
		playerWins = wins / math.max(1, games - noResult),
		noResult = noResult,
		cappedShots = capped,
		shotsPerGame = shots / math.max(1, games),
		seconds = os.clock() - started,
	}
end

local function printTier(tier: string, r: any)
	print(
		("\n%s  (player wins %.1f%%, %.0f shots/game, %d no result, %d capped shots, %.0fs)"):format(
			tier,
			r.playerWins * 100,
			r.shotsPerGame,
			r.noResult,
			r.cappedShots,
			r.seconds
		)
	)
	print(HEADER)
	print(row("player", r.player))
	print(row("bot", r.bot))
	for _, who in { "player", "bot" } do
		local s = r[who]
		print(
			("  %-6s break balls/g %.2f, group-picking-shot balls/g %.2f (of the other group %.2f), runs/g %.2f, balls/run %.2f"):format(
				who,
				s.breakBallsPerGame,
				s.openBallsPerGame,
				s.openCrossPerGame,
				s.runsPerGame,
				s.ballsPerRun
			)
		)
	end
end

local tiers: { string } = {}
local games, seed, jobs = 200, 1, 8
local outPath: string? = nil
local child = false
local args = process.args
local i = 1
while i <= #args do
	local a = args[i]
	if a == "--games" then
		games = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--seed" then
		seed = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--jobs" then
		jobs = tonumber(args[i + 1]) :: number
		i += 1
	elseif a == "--out" then
		outPath = args[i + 1]
		i += 1
	elseif a == "--child" then
		child = true
	else
		table.insert(tiers, a)
	end
	i += 1
end
if #tiers == 0 then
	tiers = table.clone(DEFAULT_TIERS)
end

-- A child process (the --jobs path): one tier, its result as JSON on stdout, nothing else.
if child then
	print(serde.encode("json", runTier(tiers[1], games, seed)))
	process.exit(0)
end

print(
	("Streak model: %d games a tier, seed %d, BallPay $%d, %d jobs"):format(
		games,
		seed,
		BALL_PAY,
		jobs
	)
)
local wallStarted = DateTime.now().unixTimestampMillis
local byTier: { [string]: any } = {}
if jobs > 1 and #tiers > 1 then
	-- Each tier in its own `lune run` (from the repo root), up to `jobs` at once.
	local running, nextTier = 0, 1
	local failed: string? = nil
	while nextTier <= #tiers or running > 0 do
		if nextTier <= #tiers and running < jobs then
			local tier = tiers[nextTier]
			nextTier += 1
			running += 1
			task.spawn(function()
				local r = process.exec("lune", {
					"run",
					"tools/streak_model.luau",
					tier,
					"--games",
					tostring(games),
					"--seed",
					tostring(seed),
					"--child",
				})
				if r.ok then
					byTier[tier] = serde.decode("json", r.stdout)
				else
					failed = tier .. ": " .. r.stderr
				end
				running -= 1
			end)
		else
			task.wait(0.2)
		end
	end
	if failed then
		error(failed)
	end
else
	for _, tier in tiers do
		byTier[tier] = runTier(tier, games, seed)
	end
end

local results: any = {
	games = games,
	seed = seed,
	ballPay = BALL_PAY,
	buckets = { "1", "2", "3", "4", "5", "6", "7", "8+" },
	curves = {},
	tiers = byTier,
	order = tiers,
}
for _, curve in CURVES do
	results.curves[curve.name] = curve.rule
end
local playerSummaries = {}
for _, tier in tiers do
	printTier(tier, byTier[tier])
	table.insert(playerSummaries, byTier[tier].player)
end
local avg = average(playerSummaries)
avg.games = nil
results.playerAllTierAverage = avg
results.wallSeconds = (DateTime.now().unixTimestampMillis - wallStarted) / 1000
print(
	("\nAll tiers, model player, equal weight per tier (%.0fs wall in all)"):format(
		results.wallSeconds
	)
)
print(HEADER)
print(row("player avg", avg))

if outPath then
	fs.writeFile(outPath, serde.encode("json", results, true))
	print("wrote " .. outPath)
end
