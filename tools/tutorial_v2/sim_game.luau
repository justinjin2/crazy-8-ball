--!strict
-- Tutorial v2's new-player simulation (docs/prompts/TUTORIAL_V2_PROMPT.md 5.2): whole game 1s
-- played on the real MatchEngine with the production rig (Tutorial/Rig picks each turn's
-- lesson and arms the hidden help, Tutorial/Assist, Fire Shot inside it), the bot playing as
-- Bots/Driver does (Tutorial/BotPlan) and the new-player model (player.luau) answering the
-- lessons. Each game is one JSON line: what each lesson shot did, the misses, ball in hand,
-- the 8's incidents, the turns and the seconds.
--
--   lune run tools/tutorial_v2/sim_game.luau <options.json> <firstSeed> <games> <out.jsonl>
--
-- options.json (every field optional; see DEFAULTS): the break (seed, cueX, cueY, angle,
-- power, layout) and the player's habits being tried.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local process = require("@lune/process")
local Sim = require("./sim")
local Player = require("./player")
local H = Sim.H
local Config = Sim.Config
local E = H.require("Rules.MatchEngine")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local NiceShot = H.require("Rules.NiceShot")
local Break = H.require("Tutorial.Break")
local Rig = H.require("Tutorial.Rig")
local Plan = H.require("Tutorial.Plan")
local Assist = H.require("Tutorial.Assist")
local BotPlan = H.require("Tutorial.BotPlan")
local Script = H.require("Bots.Script")
local Look = H.require("Bots.Look")
local Rng = H.require("Bots.Rng")
local UltMatch = H.require("Ults.Match")

-- How far the help bent things on each of the player's shots (degrees; Assist's own fx
-- record, read as the shot finishes): the most any ball was pulled, the cue ball's guard, the
-- combination's steer and the aim help. The game being played collects them.
local helpShots: { any }? = nil
do
	local finish = Assist.finish
	Assist.finish = function(state: any, events: { any }, ops: any)
		finish(state, events, ops)
		local fx = state.fx
		if helpShots and fx then
			local pull = 0
			for _, v in fx.pulled or {} do
				pull = math.max(pull, v)
			end
			local function deg(v: number?): number
				return math.floor(math.deg(v or 0) * 10 + 0.5) / 10
			end
			table.insert(helpShots, {
				pull = deg(pull),
				guard = deg(fx.guarded),
				combo = deg(fx.comboTurned),
				aim = deg(fx.aimed),
			})
		end
	end
end

local optionsFile = process.args[1]
local firstSeed = tonumber(process.args[2]) or 1
local games = tonumber(process.args[3]) or 10
local out = process.args[4] or "games.jsonl"

local DEFAULTS = {
	breakShot = nil, -- { seed, cueX, cueY, angle, power, layout }: nil keeps Config.Tutorial.Break
	fireAimFactor = 0.6, -- Fire Shot's full lines: the aim error times this
	comboFollow = { careful = 0.9, sloppy = 0.8, wild = 0.6, ignore = 1 }, -- play the combination
	abilityUse = 0.9, -- "Press G": share who use it
	maxSeconds = 900, -- a game still going after this is a dead end
	maxTurns = 60,
}

local opts: any = table.clone(DEFAULTS)
if optionsFile and optionsFile ~= "-" then
	for k, v in serde.decode("json", fs.readFile(optionsFile)) do
		opts[k] = v
	end
end

local B = Config.Tutorial.Break
if opts.breakShot then
	B.Seed = opts.breakShot.seed
	B.CueX = opts.breakShot.cueX
	B.CueY = opts.breakShot.cueY
	B.Angle = opts.breakShot.angle
	B.Power = opts.breakShot.power
	B.Layout = opts.breakShot.layout
end

local PLAYER, BOT = 7, -1000
local geometry = Sim.geometry

-- Think times (seconds) by kind for an ordinary turn, and what each lesson adds (reading the
-- prompt, the gesture it asks for). Guesses, written down for the plan page.
local THINK = { careful = { 6, 14 }, sloppy = { 4, 9 }, wild = { 2, 5 }, ignore = { 2, 4 } }
local LESSON = {
	breakShot = { 4, 8 },
	aim = { 6, 12 }, -- adjust, zoom out, "you can zoom"
	combo = { 3, 6 }, -- the pointer at the two balls
	ability = { 4, 8 }, -- press G, the ignition
	hand = { 5, 10 }, -- "move the white ball anywhere", the drag
	eight = { 3, 6 }, -- SELECT WHICH POCKET
}
local AWAY = { 20, 60 } -- an AFK player's second away turn (no clock): back after this long

local function seatTeam(m: any, uid: number): number
	return (E.seat(m, uid) :: any).team
end

local function botView(m: any): any
	local view = {
		geometry = m.state.geometry,
		balls = Ball.cloneList(m.state.balls),
		groups = table.clone(m.groups),
		team = seatTeam(m, BOT),
		called = m.calledPocket,
		breakShot = m.breakShot == true,
		requireRail = Config.Multiplayer.RailAfterContact.Casual,
	}
	return Script.tutorialView(view :: any)
end

-- The balls that dropped in an outcome and were on the table before.
local function freshDown(before: { any }, outcome: any): ({ number }, boolean)
	local down, scratch = Sim.down(outcome)
	local fresh = {}
	for _, id in down do
		if not (Sim.find(before, id) :: any).pocketed then
			table.insert(fresh, id)
		end
	end
	return fresh, scratch
end

local function play(seed: number): any
	local p = Player.new(seed)
	local rng = p.rng
	local botRng = Rng.new(Rng.seedOf(seed, 202))
	local rec: any = {
		seed = seed,
		kind = p.kind,
		zooms = p.zooms,
		afk = p.afk,
		misses = 0,
		fouls = 0,
		botVisits = 0,
		botShots = {},
		hand = false,
		eightBack = 0,
		eightMovedByBot = 0,
		playerTurns = 0,
		shots = 0,
		timeouts = 0,
		help = {},
		lessons = {},
		log = {},
	}
	helpShots = rec.help

	local m = E.new(1, 1)
	assert(E.join(m, PLAYER, "Real", "Real", 0))
	assert(E.join(m, BOT, "Bot", "Bot", 0.1))
	local shot = Break.shot()
	m.breakFor = PLAYER
	m.tutorial = Rig.new(PLAYER)
	m.rackSeed = shot.seed
	m.rackLayout = shot.layout
	m.state = Simulation.newState(geometry, Break.rack(geometry, shot))
	assert(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	local now = m.deadline or 0
	E.advance(m, now) -- the coin

	local lastTurnId = -1
	local botVisit = 0
	local botShotInVisit = 0
	local lastShooter = nil
	local brokeAt = nil
	local awayDone = false
	local awayTurn = if p.afk then Rng.int(rng, 3, 6) else -1
	local seenLesson: { [string]: boolean } = {}

	local function think(range: { number }): number
		return Rng.range(rng, range[1], range[2])
	end

	local function shoot(uid: number, payload: any): (any?, string?)
		payload.epoch, payload.turnId = m.epoch, m.turnId
		return E.acceptShot(m, uid, payload, now)
	end

	for _ = 1, 600 do
		if m.phase == "Result" then
			break
		end
		if brokeAt and now - brokeAt > opts.maxSeconds then
			rec.dead = "time"
			break
		end
		if rec.playerTurns + rec.botVisits > opts.maxTurns then
			rec.dead = "turns"
			-- The jammed table, to look at: id, x, y of each ball still up.
			rec.table = {}
			for _, b in m.state.balls do
				if not b.pocketed then
					table.insert(rec.table, { b.id, math.floor(b.x * 10) / 10, math.floor(b.y * 10) / 10 })
				end
			end
			break
		end
		local phase = m.phase
		if
			phase == "Intro"
			or phase == "Resolving"
			or phase == "Foul"
			or phase == "CoinFlip"
			or phase == "Arming"
		then
			now = math.max(now, m.deadline or now)
			E.advance(m, now)
			continue
		end
		if phase ~= "Aiming" and phase ~= "Placement" and phase ~= "PocketChoice" then
			rec.dead = "phase " .. tostring(phase)
			break
		end

		local uid = m.shooter
		local rig = m.tutorial
		if uid == PLAYER then
			local newTurn = m.turnId ~= lastTurnId
			if newTurn then
				lastTurnId = m.turnId
				if not m.breakShot then
					rec.playerTurns += 1
				end
				botShotInVisit = 0
			end
			lastShooter = PLAYER
			local group = Rig.playerGroup(m)

			-- AFK: away for one turn (a timed turn runs out: a timeout; a lesson turn has no
			-- clock and simply waits), then away again on the next, which has no clock.
			if newTurn and rec.playerTurns == awayTurn and not awayDone and not m.breakShot then
				awayDone = true
				if m.deadline then
					now = m.deadline
					E.advance(m, now) -- the timeout foul
					rec.timeouts += 1
					continue
				end
				now += think(AWAY)
			elseif newTurn and (m.timeouts[seatTeam(m, PLAYER)] or 0) >= 1 then
				if m.deadline then
					rec.dead = "a clock on the turn after a timeout"
					break
				end
				now += think(AWAY)
			end

			if phase == "PocketChoice" then
				-- SELECT WHICH POCKET: the glowing one most of the time.
				local glow = Plan.eightGlow(geometry, m.state.balls, m.ballInHand == true)
				local pick = glow or 1
				if Rng.chance(rng, 0.1) then
					pick = Rng.int(rng, 1, 6)
				end
				now += think(if seenLesson.Eight then THINK[p.kind] else LESSON.eight)
				seenLesson.Eight = true
				assert(
					E.action(
						m,
						uid,
						{ kind = "Pocket", pocket = pick, epoch = m.epoch, turnId = m.turnId },
						now
					)
				)
				continue
			end

			if m.ballInHand and not m.breakShot then
				rec.hand = true
				-- The cue ball starts on its good spot (Rig.placeHand); they keep it there.
				now += think(if seenLesson.Hand then { 2, 5 } else LESSON.hand)
				seenLesson.Hand = true
			end
			local balls = m.state.balls
			local lesson = rig.lesson
			local plan = rig.plan
			local payload: any
			local target: any = nil
			local used = false
			if lesson == "Break" then
				now += think(LESSON.breakShot)
				payload = { angle = 0, power = 1 }
			elseif m.calledPocket ~= nil and Judge.eligible(balls, group :: any) then
				local pot = Plan.pots(geometry, balls, "eight", m.calledPocket)[1]
				now += think(THINK[p.kind])
				target = pot
				local want = if pot then pot.angle else 0
				payload = { angle = Player.aim(p, want, want, true), power = Player.power(p) }
			elseif lesson == "Aim" and plan then
				target = plan
				now += think(THINK[p.kind]) + think(LESSON.aim)
				local start = plan.angle + math.rad(Config.Tutorial.Lessons.AimOffsetDegrees)
				payload = {
					angle = Player.aim(p, plan.angle, start, p.zooms),
					power = Player.power(p),
				}
			elseif lesson == "Combo" and plan and Rng.chance(rng, opts.comboFollow[p.kind]) then
				target = plan
				now += think(THINK[p.kind]) + think(LESSON.combo)
				payload =
					{ angle = Player.aim(p, plan.angle, plan.angle, true), power = Player.power(p) }
			elseif lesson == "Ability" and plan and Rng.chance(rng, opts.abilityUse) then
				target = plan
				now += think(THINK[p.kind]) + think(LESSON.ability)
				local ok = UltMatch.devArm(m, PLAYER, Config.Ults.Default, now)
				used = ok
				local saved = Player.AimSdDegrees[p.kind]
				Player.AimSdDegrees[p.kind] = saved * opts.fireAimFactor
				payload =
					{ angle = Player.aim(p, plan.angle, plan.angle, true), power = Player.power(p) }
				Player.AimSdDegrees[p.kind] = saved
			else
				local list = Plan.choices(geometry, balls, group)
				local pick = list[1]
				if p.kind == "sloppy" and #list > 1 and Rng.chance(rng, 0.5) then
					pick = list[2]
				elseif p.kind == "wild" and #list > 1 then
					pick = list[Rng.int(rng, 1, math.min(4, #list))]
				end
				now += think(THINK[p.kind])
				target = pick
				local cue = Sim.find(balls, 0) :: any
				if pick == nil then
					-- No pot at all: a hit at their nearest ball.
					local best, bestD = nil, math.huge
					for _, b in balls do
						if not b.pocketed and Judge.group(b.id) == group then
							local d = math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
							if d < bestD then
								best, bestD = b, d
							end
						end
					end
					local a = if best then math.atan2(best.y - cue.y, best.x - cue.x) else 0
					payload = { angle = a, power = Player.power(p) }
				else
					local start = if p.kind == "ignore"
						then pick.angle + math.rad(Rng.range(rng, -4, 4))
						else pick.angle
					payload = {
						angle = Player.aim(p, pick.angle, start, true),
						power = Player.power(p),
					}
				end
			end
			payload.power = math.clamp(payload.power, 0.05, 1)
			payload.spin = { x = 0, y = 0 }
			if m.deadline and now >= m.deadline then
				-- They took longer than the clock: the turn runs out (a timeout foul).
				now = m.deadline
				E.advance(m, now)
				rec.timeouts += 1
				rec.slowTimeouts = (rec.slowTimeouts or 0) + 1
				continue
			end
			local before = Ball.cloneList(m.state.balls)
			local accepted, why = shoot(uid, payload)
			if accepted == nil then
				rec.dead = "player shot refused: " .. tostring(why)
				break
			end
			rec.shots += 1
			brokeAt = brokeAt or now
			local j = m.pending.judgement
			local outcome = m.pending.outcome
			if process.env.DEBUG_COMBO and lesson == "Combo" and target and target.b then
				local hits = {}
				for _, ev in outcome.events do
					if ev.type == "ballHit" or ev.type == "pocket" then
						table.insert(hits, ("%s %d-%s"):format(ev.type, ev.ball, tostring(ev.other)))
					end
				end
				local fx = m.state.fx or {}
				print(
					("combo %d->%d P%d back %.1f cut %.1f cueCut %.1f dist %.1f | angle err %.2f power %.2f | %s"):format(
						target.a,
						target.b,
						target.pocket,
						target.back,
						target.cut,
						target.cueCut,
						target.distance,
						math.deg(payload.angle - target.angle),
						payload.power,
						table.concat(hits, ", ")
					)
				)
				local _ = fx
			end
			local down, scr = freshDown(before, outcome)
			local mine = 0
			for _, id in down do
				if Judge.group(id) == group then
					mine += 1
				end
			end
			if j.foul == "EightBack" then
				rec.eightBack += 1
			end
			if j.foul then
				rec.fouls += 1
			end
			local missed = (not j.keep or j.foul ~= nil) and j.winner == nil
			if missed and lesson ~= "Break" then
				rec.misses += 1
				rec.firstMissTurn = rec.firstMissTurn or rec.playerTurns
			end
			local entry: any = {
				turn = rec.playerTurns,
				lesson = lesson,
				ball = target and (target.ball or target.b),
				pocket = target and target.pocket,
				power = math.floor(payload.power * 100 + 0.5) / 100,
				-- How far off the planned line the shot went (degrees), on a planned shot.
				err = if target and type(target.angle) == "number"
					then math.floor(
						math.deg(
							math.abs((payload.angle - target.angle + math.pi) % (2 * math.pi) - math.pi)
						) * 10 + 0.5
					) / 10
					else nil,
				-- The planned pot's cut (degrees), cue-to-ghost inches and clear lines.
				cut = if target and type(target.cut) == "number"
					then math.floor(target.cut + 0.5)
					else nil,
				dist = if target and type(target.toGhost) == "number"
					then math.floor(target.toGhost + 0.5)
					else nil,
				clear = if target then target.clear else nil,
				hand = rig.handTurn,
				down = down,
				foul = j.foul,
				keep = j.keep,
				ult = used,
			}
			if lesson == "Break" then
				rec.breakDown = down
			elseif lesson == "Aim" then
				local got = target ~= nil and table.find(down, target.ball) ~= nil
				rec.aim = {
					ball = target and target.ball,
					pocket = target and target.pocket,
					pot = got and j.keep and j.foul == nil,
					scratch = scr,
				}
			elseif lesson == "Combo" then
				rec.combo = rec.combo or { shown = true }
				-- Played: they followed the pointer (a combination plan has a front ball, b); a
				-- player who shot their own pot instead did not play it.
				rec.combo.played = target ~= nil and target.b ~= nil
				if rec.combo.played then
					local got = table.find(down, target.b) ~= nil
					local nice = false
					if got then
						for i, ev in outcome.events do
							if ev.type == "pocket" and ev.ball == target.b then
								nice = NiceShot.kind(outcome.events, target.b, i, geometry.pockets)
									== "Combo"
							end
						end
					end
					rec.combo.made = got and j.keep and j.foul == nil
					rec.combo.nice = nice and rec.combo.made
					rec.combo.scratch = scr
				end
			elseif lesson == "Ability" then
				rec.ability = rec.ability or {}
				rec.ability.used = used
				if used then
					local got = target ~= nil and table.find(down, target.ball) ~= nil
					rec.ability.pot = got and j.keep and j.foul == nil
					rec.ability.anyPot = mine > 0 and j.keep and j.foul == nil
					rec.ability.scratch = scr
				end
			end
			table.insert(rec.log, entry)
			continue
		end

		-- The bot, as Bots/Driver plays it.
		if uid ~= BOT then
			rec.dead = "unknown shooter"
			break
		end
		if lastShooter ~= BOT then
			botVisit += 1
			rec.botVisits += 1
			botShotInVisit = 0
		end
		lastShooter = BOT
		if phase == "PocketChoice" then
			rec.dead = "bot owes a call"
			break
		end
		local newTurn = m.turnId ~= lastTurnId
		if newTurn then
			lastTurnId = m.turnId
			botShotInVisit += 1
		end
		local view = botView(m)
		local hand = m.ballInHand == true
		local d: any = nil
		local plan = "leave"
		if botVisit == 1 then
			if botShotInVisit == 1 then
				d = BotPlan.pot(view, botRng, hand)
				plan = "pot"
			end
			if d == nil then
				d = BotPlan.potScratch(view, botRng, hand)
				plan = "potScratch"
				if d == nil then
					d = BotPlan.cleanScratch(view, botRng, hand)
					plan = "scratch"
				end
			end
		else
			local misses = rig.misses or 0
			local stuck = misses > 0 and misses % Config.Tutorial.BotPlan.StuckMisses == 0
			local combo = rig.done.Aim == true and not rig.done.Combo
			d = BotPlan.leave(view, botRng, hand, nil, stuck, combo)
			if stuck then
				plan = "stuck"
			end
		end
		now += Look.shotSeconds(botRng, hand)
		local before = Ball.cloneList(m.state.balls)
		local payload: any = { angle = d.angle, power = d.power, spin = d.spin or { x = 0, y = 0 } }
		if d.cueX and d.cueY and hand then
			payload.cueX, payload.cueY = d.cueX, d.cueY
		end
		local accepted, why = shoot(BOT, payload)
		if accepted == nil then
			rec.dead = "bot shot refused: " .. tostring(why)
			break
		end
		local j = m.pending.judgement
		local outcome = m.pending.outcome
		local down, scr = freshDown(before, outcome)
		local e0 = Sim.find(before, 8) :: any
		local e1 = Sim.find(outcome.finalBalls, 8) :: any
		if e1.pocketed or math.sqrt((e1.x - e0.x) ^ 2 + (e1.y - e0.y) ^ 2) > 0.3 then
			rec.eightMovedByBot += 1
		end
		local theirs = 0
		for _, id in down do
			if Judge.group(id) == Rig.playerGroup(m) then
				theirs += 1
			end
		end
		table.insert(rec.botShots, {
			visit = botVisit,
			plan = plan,
			kind = d.kind,
			down = #down,
			scratch = scr,
			foul = j.foul,
			winner = j.winner,
			theirs = theirs,
		})
	end

	rec.seconds = if brokeAt then now - brokeAt else 0
	if m.phase == "Result" then
		local winner = m.winner or (m.result and m.result.winner)
		rec.winner = winner
		rec.won = winner == seatTeam(m, PLAYER)
		rec.lost = winner ~= nil and not rec.won
	end
	for name in m.tutorial and m.tutorial.done or {} do
		rec.lessons[name] = true
	end
	return rec
end

local lines = {}
local clock = os.clock()
for i = 0, games - 1 do
	local ok, rec = pcall(play, firstSeed + i)
	if not ok then
		rec = { seed = firstSeed + i, dead = "error: " .. tostring(rec) }
	end
	table.insert(lines, Sim.json(rec))
end
fs.writeFile(out, table.concat(lines, "\n") .. (if #lines > 0 then "\n" else ""))
print(("%d games from %d in %.1f s"):format(games, firstSeed, os.clock() - clock))
