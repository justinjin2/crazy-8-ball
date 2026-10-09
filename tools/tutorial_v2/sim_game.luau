--!strict
-- Tutorial v2's new-player simulation (docs/prompts/TUTORIAL_V2_PROMPT.md 5.2): whole game 1s
-- played on the real MatchEngine (the rigged break, Tutorial/Rig's hooks, the 8 guard), the
-- hidden help (Tutorial/Assist: Magnet, the ricochet's steer, Fire Shot inside it), the bot's
-- script (Bots/Script.pot, then Tutorial/BotPlan.potScratch, then BotPlan.leave) and the
-- new-player model (player.luau). Each game is one JSON line: what each lesson shot did, the
-- misses, ball in hand, the 8's incidents, the turns and the seconds.
--
--   lune run tools/tutorial_v2/sim_game.luau <options.json> <firstSeed> <games> <out.jsonl>
--
-- options.json (every field optional; see DEFAULTS): the break (seed, cueX, cueY, angle,
-- power), the turn-2 plan (ball, pocket, second ball and pocket for the ricochet, whether the
-- pocket is off screen at the home view) and the switches being tuned.
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
local Placement = H.require("Rules.CuePlacement")
local Break = H.require("Tutorial.Break")
local Rig = H.require("Tutorial.Rig")
local Assist = H.require("Tutorial.Assist")
local BotPlan = H.require("Tutorial.BotPlan")
local Script = H.require("Bots.Script")
local Brain = H.require("Bots.Brain")
local Look = H.require("Bots.Look")
local Rng = H.require("Bots.Rng")
local Effects = H.require("Ults.Effects")

-- The hidden help's effect, registered here as the build will in Ults/Effects.
Effects.TutorialAssist = Assist

local optionsFile = process.args[1]
local firstSeed = tonumber(process.args[2]) or 1
local games = tonumber(process.args[3]) or 10
local out = process.args[4] or "games.jsonl"

local DEFAULTS = {
	breakShot = nil, -- { seed, cueX, cueY, angle, power }: nil keeps Config.Tutorial.Break
	turn2 = nil, -- { ball, pocket, second, secondPocket, hidden }: nil picks the easiest pot
	aimOffsetDegrees = 3, -- turn 2's aim opens this far off the pot line
	assist = true, -- the hidden Magnet on the player's shots
	steer = true, -- turn 2's ricochet steer
	turn4Assist = true, -- the hidden help on the shot after Fire Shot ("a bit harder")
	fireAimFactor = 0.6, -- Fire Shot's full lines: the aim error times this
	abilityWithHand = false, -- true: the ability lesson can share a ball-in-hand turn
	guard = true, -- the cue-ball guard on the player's game-1 shots (Assist's Guard)
	botPot = "plan", -- the first visit's pot: "plan" (BotPlan.pot) or "script" (Bots/Script.pot)
	abilityMaxGhost = 30, -- the ability lesson waits for a ball this close (inches) with a clean pot
	abilityWaitTurns = 2, -- ... for at most this many turns
	glow = "shot", -- the 8's glowing pocket: "shot" (pottable from the cue ball) or "near"
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
end

local PLAYER, BOT = 7, -1000
local geometry = Sim.geometry
local D = Sim.D

-- Think times (seconds) by kind for an ordinary turn, and what each lesson adds (reading the
-- prompt, the gesture it asks for). Guesses, written down for the plan page.
local THINK = { careful = { 6, 14 }, sloppy = { 4, 9 }, wild = { 2, 5 }, ignore = { 2, 4 } }
local LESSON = {
	breakShot = { 4, 8 },
	aim = { 6, 12 }, -- adjust, zoom out, "you can zoom"
	ability = { 4, 8 }, -- press G, the ignition
	hand = { 5, 10 }, -- "move the white ball anywhere", the drag
	eight = { 3, 6 }, -- SELECT WHICH POCKET
}
local AWAY = { 20, 60 } -- an AFK player's second away turn (no clock): back after this long

---------------------------------------------------------------------------------------------
-- Table reading
---------------------------------------------------------------------------------------------

local function seatTeam(m: any, uid: number): number
	return (E.seat(m, uid) :: any).team
end

local function playerGroup(m: any): string
	return Rig.playerGroup(m)
end

local choices = Sim.choices
local firePlan = Sim.firePlan

-- The glowing pocket for the 8 (SELECT WHICH POCKET): the easiest pot of the 8 from where
-- the cue ball is (opts.glow == "shot"), else the 8's own pocket (Break.eightPocket). With
-- ball in hand the 8's own pocket (the cue ball can go anywhere).
local function eightGlow(balls: { any }, hand: boolean): number
	if opts.glow == "shot" and not hand then
		local lesson = Break.lesson(geometry, balls, "eight", false, 60)
		if lesson then
			return lesson.pocket
		end
	end
	return Break.eightPocket(geometry, balls) :: number
end

-- A good spot for ball in hand: straight behind the easiest of their balls (the 8 into
-- `called` once theirs are gone), a short way back from its ghost ball. Nil when none is free.
local function handSpot(m: any, balls: { any }, group: string): (number?, number?)
	local targets = {}
	for _, b in balls do
		if not b.pocketed and Judge.group(b.id) == group then
			table.insert(targets, b)
		end
	end
	local eightOnly = #targets == 0
	if eightOnly then
		table.insert(targets, Sim.find(balls, 8))
	end
	local probe = Simulation.cloneState(m.state)
	local best, bx, by = math.huge, nil, nil
	for _, b in targets do
		for _, p in geometry.pockets do
			if eightOnly and m.calledPocket ~= nil and p.id ~= m.calledPocket then
				continue
			end
			local mx, my = Sim.mouth(p)
			if not Sim.clear(balls, { [0] = true, [b.id] = true }, b.x, b.y, mx, my) then
				continue
			end
			local ux, uy = mx - b.x, my - b.y
			local len = math.sqrt(ux * ux + uy * uy)
			if len < D then
				ux, uy = Break.throat(p) -- in the jaws: straight down the throat
			else
				ux, uy = ux / len, uy / len
			end
			local gx, gy = b.x - ux * D, b.y - uy * D
			for _, back in { 10, 16, 24 } do
				local x, y = gx - ux * back, gy - uy * back
				if
					Placement.valid(probe, x, y, false)
					and Sim.clear(balls, { [0] = true, [b.id] = true }, x, y, gx, gy)
				then
					local cost = len * 0.3 + back * 0.3
					if cost < best then
						best, bx, by = cost, x, y
					end
					break
				end
			end
		end
	end
	return bx, by
end

-- The pot into the called pocket with the 8.
local function eightPot(balls: { any }, pocket: number): any?
	local cue = Sim.find(balls, 0) :: any
	local eight = Sim.find(balls, 8) :: any
	if cue == nil or eight == nil or eight.pocketed then
		return nil
	end
	return Sim.pot(balls, cue.x, cue.y, eight, Sim.pocket(pocket))
end

-- The ghost point for ball `id` into pocket `pocket`: where the cue ball's centre must be when
-- it meets the ball to send it at the pocket's mouth.
local function ghost(balls: { any }, id: number, pocket: number): any?
	local b = Sim.find(balls, id)
	if b == nil or b.pocketed then
		return nil
	end
	local mx, my = Sim.mouth(Sim.pocket(pocket))
	local ux, uy = mx - b.x, my - b.y
	local len = math.sqrt(ux * ux + uy * uy)
	return { x = b.x - ux / len * D, y = b.y - uy / len * D }
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

---------------------------------------------------------------------------------------------
-- One game
---------------------------------------------------------------------------------------------

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
	}

	local m = E.new(1, 1)
	assert(E.join(m, PLAYER, "Real", "Real", 0))
	assert(E.join(m, BOT, "Bot", "Bot", 0.1))
	m.breakFor = PLAYER
	m.tutorial = { player = PLAYER }
	m.rackSeed = B.Seed
	m.state = Simulation.newState(geometry, Break.rack(geometry))
	assert(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	local now = m.deadline or 0
	E.advance(m, now) -- the coin

	-- The hidden help for this shot, set before each of the player's shots (Rig.assist's
	-- shape, wrapped as the build will: TutorialAssist with its Inner and Ricochet).
	local shotHelp: any = nil
	local baseAssist = Rig.assist;
	(Rig :: any).assist = function(t: any, userId: number, before: { any }): any?
		if shotHelp == nil or shotHelp.off then
			return nil
		end
		local base = baseAssist(t, userId, before)
		if base == nil then
			return nil
		end
		base.Effect = "TutorialAssist"
		base.extra.Inner = shotHelp.inner
		base.extra.Ricochet = shotHelp.ricochet
		base.extra.Guard = if opts.guard then true else nil
		base.extra.AimAt = shotHelp.aimAt
		return base
	end

	local lessonsDone = { aim = false, ability = false, hand = false, eight = false }
	local playerTurnIndex = 0 -- the player's turns after the break
	local lastTurnId = -1
	local botVisit = 0
	local botShotInVisit = 0
	local lastShooter = nil
	local brokeAt = nil
	local awayDone = false
	local awayTurn = if p.afk then Rng.int(rng, 3, 6) else -1
	local wasAway = false
	local lessonAfterAbility = false
	local abilityWaited = 0 -- turns the ability lesson waited for a good setup
	local missStreak = 0 -- the player's misses in a row (BotPlan's StuckMisses)

	local function think(range: { number }): number
		return Rng.range(rng, range[1], range[2])
	end

	local function shoot(uid: number, payload: any): (any?, string?)
		payload.epoch, payload.turnId = m.epoch, m.turnId
		local shot, why = E.acceptShot(m, uid, payload, now)
		return shot, why
	end

	for _ = 1, 400 do
		if m.phase == "Result" then
			break
		end
		if brokeAt and now - brokeAt > opts.maxSeconds then
			rec.dead = "time"
			break
		end
		if rec.playerTurns + rec.botVisits > opts.maxTurns then
			rec.dead = "turns"
			break
		end
		local phase = m.phase
		if phase == "Intro" or phase == "Resolving" or phase == "Foul" or phase == "CoinFlip" then
			now = math.max(now, m.deadline or now)
			E.advance(m, now)
			continue
		end
		if phase ~= "Aiming" and phase ~= "Placement" and phase ~= "PocketChoice" then
			rec.dead = "phase " .. tostring(phase)
			break
		end

		local uid = m.shooter
		if uid == PLAYER then
			local newTurn = m.turnId ~= lastTurnId
			if newTurn then
				lastTurnId = m.turnId
				if not m.breakShot then
					playerTurnIndex += 1
					rec.playerTurns += 1
				end
				botShotInVisit = 0
			end
			lastShooter = PLAYER
			local balls = m.state.balls
			local group = playerGroup(m)

			-- AFK: away on one turn (the clock runs out: a timeout), then away again (the
			-- clock stops, the prompt pulses) until they come back.
			if newTurn and playerTurnIndex == awayTurn and not awayDone and not m.breakShot then
				awayDone = true
				wasAway = true
				m.deadline = now + Config.Multiplayer.ShotSeconds
				m.phase = "Aiming"
				now = m.deadline
				E.advance(m, now) -- the timeout foul
				rec.timeouts = (rec.timeouts or 0) + 1
				continue
			end
			if newTurn and wasAway then
				wasAway = false
				now += think(AWAY)
			end

			if phase == "PocketChoice" then
				-- SELECT WHICH POCKET: the glowing one (the 8's own pocket) most of the time.
				local glow = eightGlow(balls, m.ballInHand == true)
				local pick = glow
				if Rng.chance(rng, 0.1) then
					pick = Rng.int(rng, 1, 6)
				end
				now += think(if lessonsDone.eight then THINK[p.kind] else LESSON.eight)
				lessonsDone.eight = true
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

			local cueX, cueY = nil, nil
			if m.ballInHand and not m.breakShot then
				rec.hand = true
				now += think(if lessonsDone.hand then { 2, 5 } else LESSON.hand)
				lessonsDone.hand = true
				-- Game 1 sets the cue ball down on a good spot (straight behind an easy ball);
				-- most players move it there themselves anyway, the rest keep it.
				cueX, cueY = handSpot(m, balls, group)
				if cueX and cueY then
					local probe = Simulation.cloneState(m.state)
					if Placement.valid(probe, cueX, cueY, false) then
						Placement.set(m.state, 0, cueX, cueY)
					else
						cueX, cueY = nil, nil
					end
				end
				balls = m.state.balls
			end

			local cue = Sim.find(balls, 0) :: any
			local shot: any
			local lesson = nil
			local target: any = nil
			if m.breakShot then
				lesson = "break"
				now += think(LESSON.breakShot)
				-- Any pull of half or more plays the rigged break.
				shot = { angle = 0, power = 1 }
				shotHelp = nil
			elseif m.calledPocket ~= nil and Judge.eligible(balls, group) then
				-- On the 8: aim at it into the called pocket.
				local pot = eightPot(balls, m.calledPocket)
				now += think(THINK[p.kind])
				target = pot
				local want = if pot then pot.angle else 0
				shot = { angle = Player.aim(p, want, want, true), power = Player.power(p) }
				shotHelp = if opts.assist then {} else { off = true }
				lesson = "eight"
			elseif not lessonsDone.aim then
				lesson = "aim"
				lessonsDone.aim = true
				local plan = opts.turn2
				local pot = nil
				if plan then
					local b = Sim.find(balls, plan.ball)
					if b and not b.pocketed then
						pot = Sim.pot(balls, cue.x, cue.y, b, Sim.pocket(plan.pocket))
					end
				end
				pot = pot or choices(balls, group)[1]
				target = pot
				now += think(THINK[p.kind]) + think(LESSON.aim)
				local start = pot.angle + math.rad(opts.aimOffsetDegrees)
				local seen = if plan and plan.hidden then p.zooms else true
				shot = { angle = Player.aim(p, pot.angle, start, seen), power = Player.power(p) }
				if plan and plan.power then
					shot.power = plan.power -- the lesson plays its planned power (they only aim)
				end
				local ricochet = nil
				if opts.steer and plan and plan.second then
					ricochet = ghost(balls, plan.second, plan.secondPocket)
					if ricochet then
						ricochet.ball = plan.second
					end
				end
				shotHelp = if opts.assist then { ricochet = ricochet } else { off = true }
				rec.aim =
					{ ball = pot.ball, pocket = pot.pocket, cut = pot.cut, power = shot.power }
			elseif
				not lessonsDone.ability
				and (opts.abilityWithHand or not m.ballInHand)
				and cueX == nil
				and (firePlan(balls, group) or choices(balls, group)[1]) ~= nil
				and (
					abilityWaited >= opts.abilityWaitTurns
					or (function()
						local fp = firePlan(balls, group)
						return fp ~= nil and fp.toGhost <= opts.abilityMaxGhost
					end)()
				)
			then
				lesson = "ability"
				lessonsDone.ability = true
				lessonAfterAbility = true
				local pot = firePlan(balls, group) or choices(balls, group)[1]
				target = pot
				if process.env.TUT_DEBUG then
					print(
						("ability: target %d -> %d cut %.1f ghost %.1f"):format(
							pot.ball,
							pot.pocket,
							pot.cut,
							pot.toGhost
						)
					)
					for _, b in balls do
						if not b.pocketed then
							print(
								("  ball %2d  %.2f %.2f  (%.2f from cue)"):format(
									b.id,
									b.x,
									b.y,
									math.sqrt((b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2)
								)
							)
						end
					end
				end
				now += think(THINK[p.kind]) + think(LESSON.ability)
				-- The aim opens on the pot; Fire Shot's full lines show it all the way in.
				local saved = Player.AimSdDegrees[p.kind]
				Player.AimSdDegrees[p.kind] = saved * opts.fireAimFactor
				shot =
					{ angle = Player.aim(p, pot.angle, pot.angle, true), power = Player.power(p) }
				Player.AimSdDegrees[p.kind] = saved
				shotHelp = if opts.assist
					then { inner = "FireShot" }
					else { off = true, inner = "FireShot" }
				rec.ability = {
					ball = pot.ball,
					pocket = pot.pocket,
					cut = pot.cut,
					toPocket = pot.toPocket,
					power = shot.power,
				}
			else
				local list = choices(balls, group)
				local pick = list[1]
				if p.kind == "sloppy" and #list > 1 and Rng.chance(rng, 0.5) then
					pick = list[2]
				elseif p.kind == "wild" and #list > 1 then
					pick = list[Rng.int(rng, 1, math.min(4, #list))]
				end
				now += think(THINK[p.kind])
				target = pick
				if lessonsDone.aim and not lessonsDone.ability then
					abilityWaited += 1
				end
				if pick == nil then
					-- No pot at all (all blocked): a hit at their nearest ball.
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
					shot = { angle = a, power = Player.power(p) }
				else
					local start = if p.kind == "ignore"
						then pick.angle + math.rad(Rng.range(rng, -4, 4))
						else pick.angle
					shot =
						{ angle = Player.aim(p, pick.angle, start, true), power = Player.power(p) }
				end
				local help = opts.assist
				if lessonAfterAbility then
					lesson = "after"
					lessonAfterAbility = false
					help = help and opts.turn4Assist
				end
				shotHelp = if help then {} else { off = true }
			end
			-- The escalation: after many misses in a row, the aim help toward this pot.
			if
				shotHelp
				and not shotHelp.off
				and target
				and missStreak >= Config.Tutorial.Assist.Aim.AfterMisses
			then
				shotHelp.aimAt = { x = target.ghostX, y = target.ghostY }
				rec.aimHelp = (rec.aimHelp or 0) + 1
			end
			if phase == "Placement" and m.breakShot then
				-- The break's spot is locked: nothing to place.
				cueX, cueY = nil, nil
			end
			local before = Ball.cloneList(m.state.balls)
			local payload = {
				angle = shot.angle,
				power = math.clamp(shot.power, 0.05, 1),
				spin = { x = 0, y = 0 },
			}
			if process.env.TUT_JAWS and target and target.toPocket < 3 then
				local tb = Sim.find(before, target.ball) :: any
				local pk = Sim.pocket(target.pocket)
				local c0 = Sim.find(before, 0) :: any
				local fields = {}
				for k, v in tb do
					table.insert(fields, tostring(k) .. "=" .. tostring(v))
				end
				table.sort(fields)
				print("JAWSBALL " .. table.concat(fields, " "))
				print(
					("JAWS turn %d ball %d at %.3f %.3f z %s tip %s | pocket %d centre %.2f %.2f | cue %.2f %.2f -> place %s %s | angle %.4f power %.2f"):format(
						playerTurnIndex,
						target.ball,
						tb.x,
						tb.y,
						tostring(tb.z),
						tostring(tb.tip),
						pk.id,
						pk.x,
						pk.y,
						c0.x,
						c0.y,
						tostring(cueX),
						tostring(cueY),
						shot.angle,
						payload.power
					)
				)
			end
			if cueX then
				payload.cueX, payload.cueY = cueX, cueY
			end
			local accepted, why = shoot(uid, payload)
			if accepted == nil then
				rec.dead = "player shot refused: " .. tostring(why)
				break
			end
			rec.shots += 1
			brokeAt = brokeAt or now
			local j = m.pending.judgement
			local outcome = m.pending.outcome
			local down, scr = Sim.down(outcome)
			local fresh = {}
			for _, id in down do
				if not (Sim.find(before, id) :: any).pocketed then
					table.insert(fresh, id)
				end
			end
			down = fresh
			local mine = 0
			for _, id in down do
				local was = Sim.find(before, id) :: any
				if not was.pocketed and Judge.group(id) == group then
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
			if not m.breakShot then
				missStreak = if missed then missStreak + 1 else 0
			end
			if missed and not m.breakShot then
				rec.misses += 1
				rec.firstMissTurn = rec.firstMissTurn or playerTurnIndex
			end
			rec.log = rec.log or {}
			table.insert(rec.log, {
				turn = playerTurnIndex,
				lesson = lesson,
				ball = target and target.ball,
				pocket = target and target.pocket,
				cut = target and math.floor(target.cut + 0.5),
				toGhost = target and math.floor(target.toGhost + 0.5),
				toPocket = target and math.floor(target.toPocket + 0.5),
				err = target and math.floor(math.deg(shot.angle - target.angle) * 100 + 0.5) / 100,
				power = math.floor(payload.power * 100 + 0.5) / 100,
				hand = cueX ~= nil,
				down = down,
				first = outcome.firstContact,
				foul = j.foul,
				keep = j.keep,
			})
			if lesson == "break" then
				rec.breakDown = down
			elseif lesson == "aim" then
				local target = rec.aim.ball
				local got = false
				for _, id in down do
					if id == target then
						got = true
					end
				end
				rec.aim.pot = got and j.keep and j.foul == nil
				rec.aim.mine = mine
				rec.aim.ricochet = rec.aim.pot and mine >= 2
				rec.aim.scratch = scr
				if opts.turn2 and opts.turn2.second then
					local second = false
					for _, id in down do
						if id == opts.turn2.second then
							second = true
						end
					end
					rec.aim.plannedSecond = second
				end
			elseif lesson == "ability" then
				local got = false
				for _, id in down do
					if id == rec.ability.ball then
						got = true
					end
				end
				rec.ability.pot = got and j.keep and j.foul == nil
				rec.ability.anyPot = mine > 0 and j.keep and j.foul == nil
				rec.ability.scratch = scr
			elseif lesson == "after" then
				rec.after = { pot = j.keep and j.foul == nil and mine > 0 }
			end
			now += 0 -- the shot's roll is the Resolving phase's deadline
			continue
		end

		-- The bot.
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
			-- Never on the tutorial table (it never pots its last ball).
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
				d = if opts.botPot == "plan"
					then BotPlan.pot(view, botRng, hand)
					else Script.pot(view, botRng, hand)
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
			-- Every StuckMisses misses in a row (3, 6, ...): ball in hand ends any jam.
			local stuck = missStreak > 0 and missStreak % Config.Tutorial.BotPlan.StuckMisses == 0
			d = BotPlan.leave(view, botRng, hand, nil, stuck)
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
		local down, scr = Sim.down(outcome)
		local fresh = {}
		for _, id in down do
			if not (Sim.find(before, id) :: any).pocketed then
				table.insert(fresh, id)
			end
		end
		down = fresh
		local e0 = Sim.find(before, 8) :: any
		local e1 = Sim.find(outcome.finalBalls, 8) :: any
		if e1.pocketed or math.sqrt((e1.x - e0.x) ^ 2 + (e1.y - e0.y) ^ 2) > 0.3 then
			rec.eightMovedByBot += 1
		end
		local playerBallsDown = 0
		for _, id in down do
			if Judge.group(id) == playerGroup(m) and not (Sim.find(before, id) :: any).pocketed then
				playerBallsDown += 1
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
			theirs = playerBallsDown,
		})
	end

	rec.seconds = if brokeAt then now - brokeAt else 0
	if m.phase == "Result" then
		local winner = m.winner or (m.result and m.result.winner)
		rec.winner = winner
		rec.won = winner == seatTeam(m, PLAYER)
		rec.lost = winner ~= nil and not rec.won
	end
	-- The winning shot's roll.
	rec.ballInHandSeen = rec.hand
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
