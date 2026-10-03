--!strict
-- The bot duel harness (docs/prompts/BOTS_PROMPT.md step 1): whole 8-ball games in our physics
-- between a tier's bot (src/shared/Bots/Brain) and a model player of the same rank, to tune
-- Config.Bots.Tiers until the player's win chance matches the designer's table.
--
-- A library, not a test file (the runner only runs *_test.luau): tests/bots_brain_test.luau
-- uses it and tools/bot_duel.luau is its command line.
--
-- * The model player is the "typical player of that rank": its best-scored pot (ShotFinder)
--   with Gaussian aim and power noise by rank (PLAYER_SKILL below), a soft hit with no pot,
--   ball in hand on the bot's own placement search. These are the harness's assumptions about
--   players, not game tuning, so they live here and not in Config.
-- * The player always breaks (as against every bot). Rules: Judge.resolve as the server calls
--   it (casual: no rail-after-contact rule), fouls give ball in hand, off-table balls go back
--   on the foot spot, the 8 down on the break is respotted.

local H = require("./harness")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Rack = H.require("Physics.Rack")
local TableGeometry = H.require("Physics.Table")
local Judge = H.require("Rules.ShotJudge")
local Placement = H.require("Rules.CuePlacement")
local Finder = H.require("Bots.ShotFinder")
local Brain = H.require("Bots.Brain")
local Rng = H.require("Bots.Rng")

local Duel = {}

-- A typical player of each rank: aim noise (sigma, degrees) and power noise (sigma, a share of
-- the speed). With the guideline showing the ghost ball, a careful player aims to a tenth of a
-- degree; the ranks differ in steadiness. Chosen so the model's pots drop about (on its best
-- pot each time, measured here): Bronze 50%, Silver 56, Gold 62, Platinum 67, Diamond 71,
-- Expert 75, Veteran 79, Master 82, Grandmaster 85, Reyes 88. An assumption about real
-- players: the bot-match analytics event checks it after launch.
Duel.PLAYER_SKILL = {
	Bronze = { aim = 0.4, power = 0.09 },
	Silver = { aim = 0.3, power = 0.08 },
	Gold = { aim = 0.22, power = 0.07 },
	Platinum = { aim = 0.18, power = 0.06 },
	Diamond = { aim = 0.15, power = 0.05 },
	Expert = { aim = 0.13, power = 0.05 },
	Veteran = { aim = 0.11, power = 0.045 },
	Master = { aim = 0.09, power = 0.04 },
	Grandmaster = { aim = 0.075, power = 0.035 },
	Reyes = { aim = 0.06, power = 0.03 },
} :: { [string]: { aim: number, power: number } }

Duel.MAX_SHOTS = 160

local geometry = TableGeometry.build({ pocketsOpen = true })
Duel.geometry = geometry

-- The model player's shot.
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

-- The table after a shot, ready for the next: balls at rest, off-table balls respotted, the
-- cue ball back on the cloth for ball in hand.
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
		-- Each on the nearest free spot to the foot spot (the 8's respot search, per ball).
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

export type GameResult = {
	winner: number, -- 1 the player, 2 the bot, 0 no result (shot cap)
	shots: number,
	botShots: number,
	botKinds: { [string]: number },
	reason: string?,
	tries: number, -- the player's pot attempts and how many dropped the ball aimed at
	pots: number,
}

--- One game: the player (side 1, breaks) against the bot of `botTier` (side 2).
function Duel.game(seed: number, botTier: string, playerTier: string, overrides: any?): GameResult
	local rng = Rng.new(Rng.seedOf(seed, 17))
	local skill = (overrides and overrides.skill) or Duel.PLAYER_SKILL[playerTier]
	local balls = Rack.newGame(geometry, seed)
	local groups: { [number]: string } = {}
	local shooter, breakShot, hand = 1, true, false
	local kinds: { [string]: number } = {}
	local botShots = 0
	local tries, pots = 0, 0
	for shot = 1, Duel.MAX_SHOTS do
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
			d = Brain.decide(
				view :: any,
				botTier,
				rng,
				{ ballInHand = hand, makeChance = overrides and overrides.make }
			)
			botShots += 1
			kinds[d.kind] = (kinds[d.kind] or 0) + 1
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
		if shooter == 1 and d.kind == "pot" then
			tries += 1
			for _, id in trial.pockets do
				if id == d.ball then
					pots += 1
				end
			end
		end
		if trial.winner then
			return {
				winner = trial.winner,
				shots = shot,
				botShots = botShots,
				botKinds = kinds,
				reason = if trial.winner == shooter then "LegalEight" else "Lost8",
				tries = tries,
				pots = pots,
			}
		end
		groups = trial.groups
		balls = settleTable(trial)
		if trial.foul and trial.foul ~= "Capped" then
			shooter, hand = 3 - shooter, true
		elseif trial.keep then
			hand = false
		else
			shooter, hand = 3 - shooter, false
		end
		breakShot = false
	end
	return {
		winner = 0,
		shots = Duel.MAX_SHOTS,
		botShots = botShots,
		botKinds = kinds,
		tries = tries,
		pots = pots,
	}
end

--- `games` games of the tier's bot against a player of the same rank: the player's win share
--- (no-result games left out) and the shot kinds the bot played.
function Duel.run(tier: string, games: number, seed: number, overrides: any?): any
	local wins, played, shots, tries, pots = 0, 0, 0, 0, 0
	local kinds: { [string]: number } = {}
	for i = 1, games do
		local r = Duel.game(
			Rng.seedOf(seed, i),
			tier,
			(overrides and overrides.player) or tier,
			overrides
		)
		if r.winner ~= 0 then
			played += 1
			if r.winner == 1 then
				wins += 1
			end
		end
		shots += r.shots
		tries += r.tries
		pots += r.pots
		for k, n in r.botKinds do
			kinds[k] = (kinds[k] or 0) + n
		end
	end
	return {
		tier = tier,
		games = games,
		played = played,
		playerWins = if played > 0 then wins / played else 0,
		meanShots = shots / games,
		playerPotRate = if tries > 0 then pots / tries else 0,
		kinds = kinds,
	}
end

local _ = Config
return Duel
