--!strict
-- The tutorial's game 1 (docs/prompts/TUTORIAL_V2_PROMPT.md 4.4): the rigged rack and break
-- (Tutorial/Break: the layout guard), the lessons Tutorial/Rig picks from the table
-- (Tutorial/Plan), the clock, ball in hand's spot, the hidden help with Fire Shot inside it,
-- the 8 guard, and the bot's later visits (Tutorial/BotPlan.leave).
local H = require("./harness")
local V = require("./ult_value")
local Config = H.require("Config")
local E = H.require("Rules.MatchEngine")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Simulation = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local NiceShot = H.require("Rules.NiceShot")
local Placement = H.require("Rules.CuePlacement")
local ShotInput = H.require("ShotInput")
local Rack = H.require("Physics.Rack")
local Break = H.require("Tutorial.Break")
local Rig = H.require("Tutorial.Rig")
local Plan = H.require("Tutorial.Plan")
local BotPlan = H.require("Tutorial.BotPlan")
local Brain = H.require("Bots.Brain")
local Script = H.require("Bots.Script")
local Rng = H.require("Bots.Rng")
local UltMatch = H.require("Ults.Match")
local expect = H.expect

local B = Config.Tutorial.Break
local PLAYER, BOT = 7, -1000
local geometry = TableGeometry.build({ pocketsOpen = true })
local D = 2 * Config.Balls.RadiusInches

-- A rigged 1v1 table: the player, then the bot; the game begun up to the player's break.
local function rigged(): any
	local m = E.new(1, 1)
	expect(E.join(m, PLAYER, "Real", "Real", 0))
	expect(E.join(m, BOT, "Bot", "Bot", 0.1))
	local shot = Break.shot()
	m.breakFor = PLAYER
	m.tutorial = Rig.new(PLAYER)
	m.rackSeed = shot.seed
	m.rackLayout = shot.layout
	m.state = Simulation.newState(geometry, Break.rack(geometry, shot))
	expect(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	E.advance(m, m.deadline) -- the coin
	return m
end

local function find(balls: { any }, id: number): any
	for _, b in balls do
		if b.id == id then
			return b
		end
	end
	return nil
end

-- Plays `payload` for `uid` at `now` and settles the shot; returns the judgement, the outcome.
local function shoot(m: any, uid: number, payload: any, now: number): (any, any)
	payload.epoch, payload.turnId = m.epoch, m.turnId
	payload.spin = payload.spin or { x = 0, y = 0 }
	local shot, why = E.acceptShot(m, uid, payload, now)
	expect(shot ~= nil, "the shot is accepted: " .. tostring(why))
	return m.pending.judgement, m.pending.outcome
end

-- Moves the game on to the next turn's Aiming (or Placement, PocketChoice) phase.
local function settle(m: any, now: number): number
	for _ = 1, 20 do
		local phase = m.phase
		if
			phase == "Aiming"
			or phase == "Placement"
			or phase == "PocketChoice"
			or phase == "Result"
		then
			return now
		end
		now = math.max(now, m.deadline or now)
		E.advance(m, now)
	end
	return now
end

local tests = {}

tests["the layout guard: the break, the 8, the aim lesson and the combination"] = function()
	-- The rack looks normal: every number once, the 8 in the middle, one of each in the back
	-- corners, and the break within "invisible" of the head spot and straight at the apex.
	local layout = B.Layout or Config.Rack.Layout
	local seen = {}
	for _, row in layout do
		for _, id in row do
			expect(seen[id] == nil and id >= 1 and id <= 15, "each number once: " .. id)
			seen[id] = true
		end
	end
	expect(layout[3][2] == 8, "the 8 in the middle")
	local back = layout[#layout]
	expect(
		Judge.group(back[1]) ~= Judge.group(back[#back]),
		"the back corners are one solid and one stripe"
	)
	local hx, hy = TableGeometry.headSpot(geometry)
	local fx, fy = TableGeometry.footSpot(geometry)
	expect(math.abs(B.CueX - hx) <= 0.25 and math.abs(B.CueY - hy) <= 0.25, "on the head spot")
	local straight = math.atan2(fy - B.CueY, fx - B.CueX)
	expect(math.abs(math.deg(B.Angle - straight)) <= 0.2, "aimed at the apex")

	-- Exactly Solids solids drop, nothing else; the player keeps the table.
	local r = Break.play(geometry, Break.shot())
	expect(not r.scratch, "no scratch")
	expect(#r.pocketed == B.Solids, ("%d balls down"):format(#r.pocketed))
	for _, id in r.pocketed do
		expect(Judge.group(id) == "solids", "only solids: " .. id)
	end
	expect(r.judgement.keep and r.judgement.foul == nil, "the player keeps the table")

	-- The 8 by a pocket, out of the lessons' way.
	expect(Break.eightPlaced(geometry, r.balls), "the 8 stops by a pocket")

	-- The aim lesson's pot, and the combination pair kept clear of it.
	local aim = Plan.aim(geometry, r.balls, "solids")
	expect(aim ~= nil, "an aim lesson pot")
	local pair = Plan.pairs(geometry, r.balls, "solids")[1]
	expect(pair ~= nil, "a combination pair")
	expect(aim.ball ~= pair.a and aim.ball ~= pair.b, "the aim lesson leaves the pair alone")

	-- The aim lesson played straight at a middle power pots its ball and leaves the
	-- combination ready to play.
	local m = rigged()
	E.advance(m, m.deadline or 0) -- the intro
	shoot(m, PLAYER, { angle = 0, power = 1 }, 1)
	local now = settle(m, 1)
	expect(m.tutorial.lesson == "Aim", "turn 2 is the aim lesson")
	local j = shoot(m, PLAYER, { angle = m.tutorial.plan.angle, power = 0.45 }, now)
	expect(j.keep and j.foul == nil, "the aim lesson's pot goes in")
	now = settle(m, now)
	expect(m.tutorial.lesson == "Combo", "then the combination")
end

tests["the second ball of the break creeps on the lip"] = function()
	-- Traced like Break.play: the last ball to drop spends at least CreepSeconds within 2 in of
	-- where it falls ("to edge the player").
	local shot = Break.shot()
	local sim = Simulation.newState(geometry, Rack.newGame(geometry, shot.seed, shot.layout))
	Placement.set(sim, 0, shot.cueX, shot.cueY)
	local input = ShotInput.validate(
		{ angle = shot.angle, power = shot.power, spin = { x = 0, y = 0 } },
		nil
	) :: any
	local events = { Simulation.strike(sim, input) }
	for _, b in sim.balls do
		if b.id == 0 then
			ShotInput.quantiseSeed(b)
		end
	end
	local paths: { [number]: { { number } } } = {}
	local P = Config.Physics
	local steps = 0
	while not Simulation.isAtRest(sim) and steps < P.MaxShotSeconds / P.FixedStep do
		Simulation.step(sim, P.FixedStep, events)
		steps += 1
		for _, b in sim.balls do
			if b.id ~= 0 and (not b.pocketed or b.tip ~= nil) then
				local path = paths[b.id] or {}
				paths[b.id] = path
				table.insert(path, { sim.time, b.x, b.y, if b.tip ~= nil then 1 else 0 })
			end
		end
	end
	local last, lastT = nil, -1
	for _, ev in events do
		if ev.type == "pocket" and ev.ball ~= 0 and ev.t > lastT then
			last, lastT = ev.ball, ev.t
		end
	end
	expect(last ~= nil, "a ball dropped")
	local path = paths[last :: number]
	local capture = #path
	for i, row in path do
		if row[4] == 1 then
			capture = i
			break
		end
	end
	local cx, cy, t1 = path[capture][2], path[capture][3], path[capture][1]
	local t0 = t1
	for i = capture, 1, -1 do
		if math.sqrt((path[i][2] - cx) ^ 2 + (path[i][3] - cy) ^ 2) > 2 then
			break
		end
		t0 = path[i][1]
	end
	expect(t1 - t0 >= B.CreepSeconds, ("it creeps %.2f s"):format(t1 - t0))
end

tests["the player's break is the rigged one, whatever they aim or pull"] = function()
	local m = rigged()
	expect(m.shooter == PLAYER and m.breakShot, "the player breaks")
	expect(not m.ballInHand, "no ball in hand: the cue ball stands on the break spot")
	expect(m.tutorial.lesson == "Break", "the break lesson")
	E.advance(m, m.deadline or 0) -- the intro
	expect(m.deadline == nil, "no shot clock while the lesson shows")
	local cue = find(m.state.balls, 0)
	expect(cue.x == B.CueX and cue.y == B.CueY, "on the spot")
	local j, outcome =
		shoot(m, PLAYER, { angle = 2.5, power = 0.2, spin = { x = 0.5, y = -0.5 } }, 1)
	local down = {}
	for _, b in outcome.finalBalls do
		if b.pocketed then
			table.insert(down, b.id)
		end
	end
	local expected = Break.play(geometry, Break.shot()).pocketed
	table.sort(down)
	table.sort(expected)
	expect(table.concat(down, ",") == table.concat(expected, ","), "the same balls drop")
	expect(j.keep and j.foul == nil)
end

tests["the lessons come in order and the combination earns NICE SHOT!"] = function()
	local m = rigged()
	E.advance(m, m.deadline or 0)
	shoot(m, PLAYER, { angle = 0, power = 1 }, 1)
	local now = settle(m, 1)
	-- Turn 2: the aim lesson, its pot played straight.
	expect(m.tutorial.lesson == "Aim" and m.deadline == nil, "the aim lesson, no clock")
	shoot(m, PLAYER, { angle = m.tutorial.plan.angle, power = 0.45 }, now)
	now = settle(m, now)
	-- The combination, played on its line: the front ball drops, knocked in by the back one.
	local rig = m.tutorial
	expect(rig.lesson == "Combo" and m.deadline == nil, "the combination, no clock")
	local plan = rig.plan
	local made, nice = 0, 0
	-- A few powers a new player might use, each from this same table.
	for _, power in { 0.3, 0.45, 0.6 } do
		local copy = Simulation.cloneState(m.state)
		local ult = Rig.assist(m, PLAYER, copy.balls, { angle = plan.angle }, nil)
		local strike = Simulation.strike(
			copy,
			ShotInput.validate({ angle = plan.angle, power = power, spin = { x = 0, y = 0 } }, nil) :: any
		)
		Simulation.armEffect(copy, ult.Effect, ult.Targets, ult.EightPocket, ult.extra)
		local outcome = Simulation.settle(copy, { strike })
		local b = find(outcome.finalBalls, plan.b)
		if b.pocketed and not find(outcome.finalBalls, 0).pocketed then
			made += 1
			for i, ev in outcome.events do
				if ev.type == "pocket" and ev.ball == plan.b then
					if NiceShot.kind(outcome.events, plan.b, i, geometry.pockets) == "Combo" then
						nice += 1
					end
				end
			end
		end
	end
	expect(made == 3, ("the combination drops at every power (%d/3)"):format(made))
	expect(nice == made, "every one a Combo: NICE SHOT!")
	local j = shoot(m, PLAYER, { angle = plan.angle, power = 0.45 }, now)
	expect(j.keep and j.foul == nil, "played for real, it goes in")
	expect(rig.done.Combo, "the combination is done")
	now = settle(m, now)
	-- The ability lesson: their bar is full.
	expect(rig.lesson == "Ability", "then the ability lesson")
	local view = UltMatch.view(m)
	expect(view.bars[tostring(PLAYER)].ready, "the bar is full")
end

tests["the clock: none on lessons or after a timeout, the usual one otherwise"] = function()
	local m = rigged()
	local team = (E.seat(m, PLAYER) :: any).team
	m.breakShot = false
	m.tutorial.done = { Break = true, Aim = true, Combo = true, Ability = true, Hand = true }
	m.tutorial.lesson = nil
	m.shooter, m.activeTeam = PLAYER, team
	expect(Rig.timed(m, "Aiming"), "an ordinary turn has the clock")
	expect(not Rig.timed(m, "PocketChoice"), "SELECT WHICH POCKET has none")
	m.tutorial.lesson = "Combo"
	expect(not Rig.timed(m, "Aiming"), "a lesson turn has none")
	m.tutorial.lesson = nil
	m.timeouts[team] = 1
	expect(not Rig.timed(m, "Aiming"), "the turn after a timeout waits for them")
	m.timeouts[team] = 0
	m.tutorial.handTurn, m.tutorial.done.Hand = true, false
	expect(not Rig.timed(m, "Placement") and not Rig.timed(m, "Aiming"), "the first ball in hand")
	m.shooter = BOT
	expect(Rig.timed(m, "Aiming"), "the bot's turns keep their clock")
end

tests["ball in hand starts straight behind an easy ball of theirs"] = function()
	for i = 1, 6 do
		local balls = Ball.cloneList(V.tableState(31, i, "mid").balls)
		local x, y = Plan.handSpot(geometry, balls, "solids", nil)
		if x == nil or y == nil then
			continue
		end
		expect(Placement.valid(balls, geometry, x, y, false), "a legal spot")
		local cue = find(balls, 0)
		cue.x, cue.y, cue.pocketed = x, y, false
		local straight = false
		for _, pot in Plan.pots(geometry, balls, "solids") do
			if pot.clear and pot.cut < 1 then
				straight = true
			end
		end
		expect(straight, "a clear straight pot from there")
	end
end

tests["no planned pot runs along the rail into a side pocket"] = function()
	-- Ball 2 a hand's width off the side pocket, close to the rail (the Studio case of
	-- 2026-10-09): a straight hit from behind it on the rail line hits the jaw, so neither the
	-- pots nor ball in hand's spot may use that pocket for it.
	local side = nil
	for _, p in geometry.pockets do
		if p.x == 0 and p.y > 0 then
			side = p
		end
	end
	local balls = {}
	for id = 0, 15 do
		local b = Ball.new(id, 0, 0)
		b.pocketed = true
		table.insert(balls, b)
	end
	local function put(id: number, x: number, y: number)
		local b = find(balls, id)
		b.x, b.y, b.pocketed = x, y, false
	end
	local HW = geometry.halfWidth
	put(0, -22, HW - 4)
	put(2, -10, HW - 2)
	put(12, 30, -10)
	put(8, -40, -15)
	for _, pot in Plan.pots(geometry, balls, "solids") do
		expect(pot.pocket ~= side.id, "no pot of 2 into the side pocket along the rail")
	end
	local x, y = Plan.handSpot(geometry, balls, "solids", nil)
	expect(x ~= nil and y ~= nil, "a spot for ball in hand")
	local cue = find(balls, 0)
	cue.x, cue.y = x :: number, y :: number
	local straight = nil
	for _, pot in Plan.pots(geometry, balls, "solids") do
		if pot.clear and pot.cut < 1 then
			straight = pot
		end
	end
	expect(straight ~= nil and straight.pocket ~= side.id, "lined up on another pocket")
	-- The premise: that rail line into the side pocket does not drop.
	local two = find(balls, 2)
	local ux, uy = side.x - two.x, side.y - two.y
	local len = math.sqrt(ux * ux + uy * uy)
	ux, uy = ux / len, uy / len
	for _, power in { 0.2, 0.4, 0.6 } do
		cue.x, cue.y = two.x - ux * (D + 10), two.y - uy * (D + 10)
		local state = Simulation.newState(geometry, Ball.cloneList(balls))
		local strike = Simulation.strike(
			state,
			ShotInput.validate(
				{ angle = math.atan2(uy, ux), power = power, spin = { x = 0, y = 0 } },
				nil
			) :: any
		)
		local outcome = Simulation.settle(state, { strike })
		expect(not find(outcome.finalBalls, 2).pocketed, "the rail line misses at " .. power)
	end
end

tests["ball in hand lines up a waiting combination, and it follows the cue ball"] = function()
	-- A pair by a corner pocket: 5 (the front ball) 14 in from the mouth, 3 behind it on the
	-- line; another solid and a stripe far off, the 8 on the other side.
	local Magnet = H.require("Ults.Effects.Magnet")
	local corner = nil
	for _, p in geometry.pockets do
		if p.x > 0 and p.y > 0 then
			corner = p
		end
	end
	local mx, my = Magnet.mouthPoint(geometry, corner)
	local len = math.sqrt(mx * mx + my * my)
	local ux, uy = -mx / len, -my / len -- from the mouth toward the middle
	local balls = {}
	for id = 0, 15 do
		local b = Ball.new(id, 0, 0)
		b.pocketed = true
		table.insert(balls, b)
	end
	local function put(id: number, x: number, y: number)
		local b = find(balls, id)
		b.x, b.y, b.pocketed = x, y, false
	end
	put(5, mx + ux * 14, my + uy * 14)
	put(3, mx + ux * (14 + D + 1.5), my + uy * (14 + D + 1.5))
	put(1, -30, -15)
	put(12, -35, 15)
	put(8, 10, -18)
	local t: any = {
		breakShot = false,
		ballInHand = true,
		tutorial = Rig.new(PLAYER),
		seats = {
			{ userId = PLAYER, team = 1, connected = true },
			{ userId = BOT, team = 2, connected = true },
		},
		groups = { "solids", "stripes" },
		activeTeam = 1,
		timeouts = { 0, 0 },
		shooter = PLAYER,
		state = Simulation.newState(geometry, balls),
	}
	t.tutorial.done.Aim = true
	local cue = find(t.state.balls, 0)
	Rig.placeHand(t, function(x: number, y: number): boolean
		cue.x, cue.y, cue.pocketed = x, y, false
		return true
	end)
	expect(not cue.pocketed, "the cue ball is placed")
	Rig.turnBegan(t)
	local rig = t.tutorial
	expect(rig.lesson == "Combo", "the combination is this turn's lesson")
	local plan = rig.plan
	expect(plan.a == 3 and plan.b == 5 and plan.cueCut < 1, "lined up straight behind the pair")
	expect(not Rig.timed(t, "Placement"), "no clock")
	local made, nice = 0, 0
	for _, power in { 0.3, 0.45, 0.6 } do
		local copy = Simulation.cloneState(t.state)
		local ult = Rig.assist(t, PLAYER, copy.balls, { angle = plan.angle + math.rad(2) }, nil)
		local strike = Simulation.strike(
			copy,
			ShotInput.validate(
				{ angle = plan.angle + math.rad(2), power = power, spin = { x = 0, y = 0 } },
				nil
			) :: any
		)
		Simulation.armEffect(copy, ult.Effect, ult.Targets, ult.EightPocket, ult.extra)
		local outcome = Simulation.settle(copy, { strike })
		if find(outcome.finalBalls, 5).pocketed and not find(outcome.finalBalls, 0).pocketed then
			made += 1
			for i, ev in outcome.events do
				if ev.type == "pocket" and ev.ball == 5 then
					if NiceShot.kind(outcome.events, 5, i, geometry.pockets) == "Combo" then
						nice += 1
					end
				end
			end
		end
	end
	expect(
		made == 3 and nice == 3,
		("2 degrees off, it still drops for NICE SHOT! (%d/3)"):format(nice)
	)
	-- They drag the ball: the plan follows it, or the lesson goes when no line is left.
	cue.x, cue.y = cue.x + uy * 6, cue.y - ux * 6
	Rig.cueMoved(t)
	expect(rig.lesson == "Combo" and rig.plan.angle ~= plan.angle, "the plan follows the cue ball")
	cue.x, cue.y = mx + ux * 8, my + uy * 8 -- between the pair and the pocket
	Rig.cueMoved(t)
	expect(rig.lesson == nil, "no line onto the pair: no lesson")
end

tests["the player's shots carry the hidden help, their ability inside it"] = function()
	local m = rigged()
	m.breakShot = false
	m.phase = "Aiming"
	m.deadline = nil
	local before = Ball.cloneList(m.state.balls)
	local help = Rig.assist(m, PLAYER, before, { angle = 0 }, nil)
	expect(help ~= nil and help.Effect == "TutorialAssist", "the hidden help")
	expect(help.extra.Hidden == true and help.extra.Guard == true, "drawn by nothing, guarded")
	for _, id in help.Targets do
		expect(Judge.group(id) == "solids", "only the player's colour on an open table")
	end
	local fire = { Effect = "FireShot", Targets = {}, extra = { OppTargets = { 9 } } }
	local wrapped = Rig.assist(m, PLAYER, before, { angle = 0 }, fire)
	expect(
		wrapped.Effect == "TutorialAssist" and wrapped.extra.Inner == "FireShot",
		"Fire Shot inside"
	)
	expect(#wrapped.extra.OppTargets == 0, "the help's own pull stays on their balls")
	expect(Rig.assist(m, BOT, before, nil, nil) == nil, "never the bot's shots")
	expect(Rig.assist(m, BOT, before, nil, fire) == fire, "the bot's own ability is its own")
end

tests["the 8 guard: the player cannot lose on the 8"] = function()
	local m = rigged()
	local team = (E.seat(m, PLAYER) :: any).team
	m.activeTeam = team
	local before = Ball.cloneList(m.state.balls)
	local eight = find(before, 8)
	local lost = { winner = 3 - team, reason = "EarlyEight", foul = nil, keep = false }
	local j = Rig.judge(m, before, lost)
	expect(j.winner == nil and j.foul == "EightBack", "a plain foul instead")
	expect(j.eightBack.x == eight.x and j.eightBack.y == eight.y, "the 8 goes back where it was")
	local won = { winner = team, reason = "LegalEight", keep = false }
	expect(Rig.judge(m, before, won) == won, "a win stays a win")
	m.activeTeam = 3 - team
	local botLost = { winner = team, reason = "EarlyEight", keep = false }
	expect(Rig.judge(m, before, botLost) == botLost, "the bot's own 8 is still the bot's loss")
end

tests["the bot's later visits never pot and leave the player's balls alone"] = function()
	local checked = 0
	for i = 1, 6 do
		local view = Script.tutorialView({
			geometry = geometry,
			balls = Ball.cloneList(V.tableState(21, i, "mid").balls),
			groups = { [1] = "solids" },
			team = 2,
			requireRail = false,
		} :: any)
		expect(view.groups[2] == "stripes", "the bot plays the other colour")
		local d = BotPlan.leave(view, Rng.new(i))
		local trial = Brain.simulate(view, d, d.cueX, d.cueY)
		expect(trial.winner == nil, "nobody wins")
		local moved = false
		for _, b in view.balls do
			if not b.pocketed and Judge.group(b.id) == "solids" then
				local a = find(trial.balls, b.id)
				local gap = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
				if a.pocketed or gap > Config.Tutorial.BotPlan.StillInches then
					moved = true
				end
			end
		end
		local theirs = 0
		for _, id in trial.pockets do
			if id ~= 0 and Judge.group(id) == "solids" then
				theirs += 1
			end
		end
		expect(theirs == 0, "never pots one of the player's")
		if not moved then
			checked += 1
		end
	end
	expect(checked >= 5, "almost always leaves their balls still (" .. checked .. "/6)")
end

tests["the 8 stays open: a later visit never parks a ball where the 8 must be hit from"] = function()
	-- The Studio case of 2026-10-09: the 8 by its corner, the bot's 9 right behind it on the
	-- rail, so the cue ball cannot reach the spot it must hit the 8 from.
	local balls = {}
	for id = 0, 15 do
		local b = Ball.new(id, 0, 0)
		b.pocketed = true
		table.insert(balls, b)
	end
	local function put(id: number, x: number, y: number)
		local b = find(balls, id)
		b.x, b.y, b.pocketed = x, y, false
	end
	put(0, 35, -22)
	put(8, -43, -22)
	put(9, -41, -22)
	put(12, -27, 12)
	expect(not Plan.eightOpen(geometry, balls), "the 9 blocks the 8")
	put(9, -30, 5)
	expect(Plan.eightOpen(geometry, balls), "the 9 moved off: the 8 is open")
	-- The bot's leaves keep an open 8 open.
	local checked = 0
	for i = 1, 8 do
		local view = Script.tutorialView({
			geometry = geometry,
			balls = Ball.cloneList(V.tableState(41, i, "mid").balls),
			groups = { [1] = "solids" },
			team = 2,
			requireRail = false,
		} :: any)
		if not Plan.eightOpen(geometry, view.balls) then
			continue
		end
		local d = BotPlan.leave(view, Rng.new(i))
		local trial = Brain.simulate(view, d, d.cueX, d.cueY)
		expect(Plan.eightOpen(geometry, trial.balls), "the 8 is still open after leave " .. i)
		checked += 1
	end
	expect(checked >= 4, "enough tables with an open 8 (" .. checked .. ")")
end

-- A table of `spots` ({ id, x, y }), every other ball down.
local function laid(spots: { { number } }): { any }
	local balls = {}
	for id = 0, 15 do
		local b = Ball.new(id, 0, 0)
		b.pocketed = true
		table.insert(balls, b)
	end
	for _, s in spots do
		local b = find(balls, s[1])
		b.x, b.y, b.pocketed = s[2], s[3], false
	end
	return balls
end

tests["the 8 into the called pocket gets the aim help and the carry"] = function()
	-- Their group cleared, the 8 20 in off a corner, the cue ball 30 in back at a 15-degree cut.
	local Magnet = H.require("Ults.Effects.Magnet")
	local corner = nil
	for _, p in geometry.pockets do
		if p.x > 0 and p.y > 0 then
			corner = p
		end
	end
	local mx, my = Magnet.mouthPoint(geometry, corner)
	local len = math.sqrt(mx * mx + my * my)
	local ux, uy = mx / len, my / len -- toward the pocket
	local ex, ey = mx - ux * 20, my - uy * 20
	local gx, gy = ex - ux * D, ey - uy * D
	local a = math.atan2(uy, ux) + math.rad(15)
	local cx, cy = gx - math.cos(a) * 30, gy - math.sin(a) * 30
	local balls = laid({ { 0, cx, cy }, { 8, ex, ey }, { 12, -35, 15 }, { 14, -30, -18 } })
	local t: any = {
		breakShot = false,
		ballInHand = false,
		tutorial = Rig.new(PLAYER),
		seats = {
			{ userId = PLAYER, team = 1, connected = true },
			{ userId = BOT, team = 2, connected = true },
		},
		groups = { "solids", "stripes" },
		activeTeam = 1,
		timeouts = { 0, 0 },
		shooter = PLAYER,
		calledPocket = corner.id,
		state = Simulation.newState(geometry, balls),
	}
	local aim = math.atan2(gy - cy, gx - cx)
	local made = 0
	for _, off in { -3, 3 } do
		for _, power in { 0.35, 0.55 } do
			local angle = aim + math.rad(off)
			local ult = Rig.assist(t, PLAYER, t.state.balls, { angle = angle }, nil)
			expect(ult.extra.AimAt ~= nil, "the aim help on the 8's line")
			expect(ult.extra.Carry and ult.extra.Carry.ball == 8, "the 8 carried to its pocket")
			local copy = Simulation.cloneState(t.state)
			local strike = Simulation.strike(
				copy,
				ShotInput.validate({ angle = angle, power = power, spin = { x = 0, y = 0 } }, nil) :: any
			)
			Simulation.armEffect(copy, ult.Effect, ult.Targets, ult.EightPocket, ult.extra)
			local outcome = Simulation.settle(copy, { strike })
			if
				find(outcome.finalBalls, 8).pocketed and not find(outcome.finalBalls, 0).pocketed
			then
				made += 1
			end
		end
	end
	expect(made == 4, ("3 degrees off either way, the 8 still drops (%d/4)"):format(made))
end

tests["the jam breaker: a ball no ball in hand can line up is nudged into the open"] = function()
	-- A simulated game's jam (2026-10-09, seed 254): their last solid 3 by a corner whose jaws
	-- hold the 8, every other line blocked or from off the table; every clean scratch handed
	-- them ball in hand with nothing to line up.
	local balls = laid({
		{ 0, -25, 0 },
		{ 3, 46.2, 22.3 },
		{ 8, 48.9, 25 },
		{ 10, 5.2, -4 },
		{ 11, -39.5, -12.7 },
		{ 12, -27, -14.6 },
		{ 13, 35.8, 14.2 },
		{ 14, 45.9, -5.4 },
	})
	expect(Plan.handSpot(geometry, balls, "solids", nil) == nil, "no spot lines ball 3 up")
	local view = Script.tutorialView({
		geometry = geometry,
		balls = balls,
		groups = { [1] = "solids" },
		team = 2,
		requireRail = false,
	} :: any)
	local d = BotPlan.leave(view, Rng.new(1), true, nil, true)
	local trial = Brain.simulate(view, d, d.cueX, d.cueY)
	expect(trial.winner == nil, "nobody wins")
	for _, id in trial.pockets do
		expect(id == 0, "nothing of theirs or the 8 drops")
	end
	expect(trial.foul ~= nil, "a foul: ball in hand for them")
	expect(Plan.handSpot(geometry, trial.balls, "solids", nil) ~= nil, "now a spot lines it up")
	-- Seed 785's jam: their group cleared, the 8 frozen on the top rail, the bot's 15 in the
	-- jaws of the one corner the 8 could roll into.
	balls = laid({
		{ 0, 24.7, -19.9 },
		{ 8, 19.4, 23.8 },
		{ 10, -9.9, 23.5 },
		{ 11, 23.7, -15.5 },
		{ 12, 48.4, -6.8 },
		{ 13, 8.8, -23.2 },
		{ 14, -43.9, 5.7 },
		{ 15, 49.2, 23.7 },
	})
	expect(Plan.handSpot(geometry, balls, "solids", nil) == nil, "no spot lines the 8 up")
	view.balls = balls
	d = BotPlan.leave(view, Rng.new(1), true, nil, true)
	trial = Brain.simulate(view, d, d.cueX, d.cueY)
	expect(trial.winner == nil, "nobody wins")
	for _, id in trial.pockets do
		expect(id == 0, "nothing but the cue ball drops")
	end
	expect(trial.foul ~= nil, "a foul: ball in hand for them")
	expect(Plan.handSpot(geometry, trial.balls, "solids", nil) ~= nil, "now a spot lines the 8 up")
end

local _ = D
return tests
