--!strict
-- A bot's turn at its table, played like a person (the Bots lane; the designer, 2026-10-02):
-- the cue drifts while it "thinks" (src/shared/Bots/Brain, spread over frames), then it may
-- use its ability, calls the 8's pocket, drags its ball in hand into place, lines up with a
-- little left-right adjustment (Bots/Look's timeline, sent on the aim stream like a person's)
-- and shoots through the same server path as ShotFired. The whole shot takes 2 to 4 seconds
-- (plus 2 with ball in hand), the ability's cutscene extra.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Ball = require(Shared.Physics.Ball)
local Engine = require(Shared.Rules.MatchEngine)
local Judge = require(Shared.Rules.ShotJudge)
local Match = require(Shared.Ults.Match)
local Arming = require(Shared.Ults.Arming)
local Magnet = require(Shared.Ults.Effects.Magnet)
local Finder = require(Shared.Bots.ShotFinder)
local Brain = require(Shared.Bots.Brain)
local BotScript = require(Shared.Bots.Script)
local BotPlan = require(Shared.Tutorial.BotPlan)
local Look = require(Shared.Bots.Look)
local Rng = require(Shared.Bots.Rng)
local Tables = require(script.Parent.Parent.TableService)
local ShotService = require(script.Parent.Parent.ShotService)
local UltService = require(script.Parent.Parent.UltService)

local B = Config.Bots

local Driver = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The table as the brain sees it: the balls exactly as the server holds them (a frozen
-- table's stopped where they are), whose group is whose, and the bot's side.
local function viewOf(e: any, team: number): Finder.View
	local balls = Ball.cloneList(e.state.balls)
	if e.phase == "Frozen" then
		for _, b in balls do
			Ball.stop(b)
		end
	end
	return {
		geometry = e.state.geometry,
		balls = balls,
		groups = table.clone(e.groups),
		team = team,
		called = e.calledPocket,
		breakShot = e.breakShot == true,
		-- The engine's own rail rule for this table (MatchEngine's resolve).
		requireRail = if e.ranked
			then Config.Multiplayer.RailAfterContact.Ranked
			else Config.Multiplayer.RailAfterContact.Casual,
	} :: any
end

-- What the bot plays this shot: its tutorial script's visit, or its brain at its skill.
local function decide(
	bot: any,
	view: any,
	rng: Rng.Rng,
	hand: boolean,
	yield: () -> ()
): Brain.Decision
	if bot.script == "Tutorial" and not view.breakShot then
		-- Game 1's bot (Tutorial/BotPlan; the designer's pick A): it never takes the player's
		-- colour. Its first visit pots one of its balls, then pots another and scratches (ball
		-- in hand for the player); every later visit misses, leaving the player a makeable
		-- shot, and after StuckMisses misses of theirs in a row it hands them ball in hand
		-- (BotPlan's jam breaker).
		view = BotScript.tutorialView(view)
		if bot.visit == 1 then
			if bot.shotInVisit == 1 then
				local d = BotPlan.pot(view, rng, hand, yield)
				if d then
					return d
				end
			end
			return BotPlan.potScratch(view, rng, hand, yield)
				or BotPlan.cleanScratch(view, rng, hand, yield)
		end
		local rig = bot.t and bot.t.engine.tutorial
		local misses = if rig then rig.misses or 0 else 0
		local stuck = misses > 0 and misses % Config.Tutorial.BotPlan.StuckMisses == 0
		-- The player's combination lesson waits: leave them lined up for it.
		local combo = rig ~= nil and rig.done.Aim == true and not rig.done.Combo
		return BotPlan.leave(view, rng, hand, yield, stuck, combo)
	end
	return Brain.decide(view, bot.skill, rng, { ballInHand = hand, yield = yield })
end

-- Picks for an armed ult that needs one (Heat Seeker's ball, Portals' spots), best first.
local function pickRequests(kind: string, e: any, view: any, d: Brain.Decision): { any }
	local out: { any } = {}
	if kind == "OwnBall" then
		if d.ball then
			table.insert(out, { ball = d.ball })
		end
		for _, id in Finder.ownIds(view) do
			table.insert(out, { ball = id })
		end
	elseif kind == "Portals" then
		local geometry = e.state.geometry
		local ob = if d.ball then Finder.findBall(view.balls, d.ball) else nil
		local pk = nil
		for _, p in geometry.pockets do
			if p.id == d.pocket then
				pk = p
			end
		end
		if ob and pk then
			local mx, my = Magnet.mouthPoint(geometry, pk)
			local dx, dy = mx - ob.x, my - ob.y
			local len = math.sqrt(dx * dx + dy * dy)
			if len > 1e-6 then
				local ux, uy = dx / len, dy / len
				for _, pair in { { 4.5, 7 }, { 6, 10 }, { 4.5, 12 } } do
					table.insert(out, {
						ax = ob.x + ux * pair[1],
						ay = ob.y + uy * pair[1],
						bx = mx - ux * pair[2],
						by = my - uy * pair[2],
					})
				end
			end
		end
		-- A pair parked out of the way (always owed before the shot).
		local HL, HW = geometry.halfLength, geometry.halfWidth
		for _, a in { { -HL + 6, -HW + 6 }, { HL - 6, HW - 6 }, { -HL + 6, HW - 6 } } do
			for _, b in { { HL - 6, -HW + 6 }, { 0, HW - 6 }, { 0, -HW + 6 } } do
				table.insert(out, { ax = a[1], ay = a[2], bx = b[1], by = b[2] })
			end
		end
	end
	local _ = Arming
	return out
end

-- Look Over There!'s sneak (the Sneak phase): sneaky ball in hand. The bot puts the cue ball
-- where its brain would with ball in hand (Brain.placeCue's spot), dragged there a beat into
-- the drag window like a person's, then waits out the reveal. Returns once the table is back
-- to its run-up (the caller thinks again from the new spot).
local function sneakFor(bot: any, t: any, uid: number, rng: Rng.Rng, team: number, yield: () -> ())
	local e = t.engine
	local sneak = e.sneak
	if e.phase ~= "Sneak" or sneak == nil or sneak.by ~= uid then
		return
	end
	local ok, d = pcall(decide, bot, viewOf(e, team), rng, true, yield)
	local toX = if ok then d.cueX else nil
	local toY = if ok then d.cueY else nil
	local epoch, turnId = e.epoch, e.turnId
	local function same(): boolean
		return bot.t == t and e.epoch == epoch and e.turnId == turnId and e.shooter == uid
	end
	local span = B.SneakMoveSeconds
	local moveAt = sneak.dragAt + Rng.range(rng, span[1], span[2])
	while same() and e.phase == "Sneak" and now() < moveAt do
		task.wait(0.05)
		Tables.advance(t, now())
	end
	local cue = Finder.findBall(e.state.balls, 0)
	if same() and e.phase == "Sneak" and cue and toX and toY then
		local fromX, fromY = cue.x, cue.y
		local steps = math.max(1, math.floor(B.DragSeconds * B.Aim.AimSendsPerSecond))
		bot.seq = (bot.seq or 0) + 1
		for i = 1, steps do
			if not (same() and e.phase == "Sneak") then
				break
			end
			local f = i / steps
			local k = f * f * (3 - 2 * f)
			bot.seq += 1
			Tables.moveBotCue(t, uid, bot.seq, fromX + (toX - fromX) * k, fromY + (toY - fromY) * k)
			task.wait(1 / B.Aim.AimSendsPerSecond)
		end
		if same() and e.phase == "Sneak" then
			local request = { kind = "Place", x = toX, y = toY, epoch = epoch, turnId = turnId }
			Tables.advance(t, now())
			Engine.action(e, uid, request, now())
			Tables.broadcast(t)
		end
	end
	while same() and (e.phase == "Sneak" or e.phase == "SneakReveal") do
		task.wait(0.1)
		Tables.advance(t, now())
	end
end

-- The angle at a ball of its own (where the cue drifts while it thinks).
local function roughAngle(view: any): number
	local cue = Finder.findBall(view.balls, 0)
	if cue == nil then
		return 0
	end
	local best, bestD = nil, math.huge
	for _, id in Finder.ownIds(view) do
		local b = Finder.findBall(view.balls, id) :: any
		local d = (b.x - cue.x) ^ 2 + (b.y - cue.y) ^ 2
		if d < bestD then
			best, bestD = b, d
		end
	end
	if best == nil then
		return 0
	end
	return math.atan2(best.y - cue.y, best.x - cue.x)
end

local function pullFor(power: number): number
	return math.clamp(0.2 + 0.8 * power, 0, 1)
end

--- Plays the bot's current turn at its table (yields for seconds; run in its own thread).
--- `seed` makes its choices; nothing is done once the turn is no longer its.
function Driver.turn(bot: any, seed: number)
	local t = bot.t
	if not t then
		return
	end
	local e = t.engine
	local uid = bot.id
	local epoch, turnId = e.epoch, e.turnId
	local seat = Engine.seat(e, uid)
	if not seat or type(seat.team) ~= "number" then
		return
	end
	local frozen = e.phase == "Frozen"
	local function live(): boolean
		return bot.t == t
			and e.epoch == epoch
			and e.turnId == turnId
			and e.shooter == uid
			and (
				e.phase == "Intro"
				or e.phase == "Placement"
				or e.phase == "PocketChoice"
				or e.phase == "Aiming"
				or e.phase == "Frozen"
			)
	end
	local rng = Rng.new(seed)
	local hand = e.ballInHand == true and not frozen
	local seconds = if frozen then 1.2 else Look.shotSeconds(rng, hand)
	local view = viewOf(e, seat.team)

	-- Thinking: the cue drifts at one of its balls, a little to and fro.
	local rough = roughAngle(view)
	local thinking = true
	task.spawn(function()
		local k = 0
		while thinking and live() do
			k += 1
			Tables.setBotAim(t, uid, rough + math.rad(4) * math.sin(k * 0.35), 0)
			task.wait(1 / B.Aim.AimSendsPerSecond)
		end
	end)
	local count = 0
	local function yield()
		count += 1
		if count % B.YieldEvery == 0 then
			task.wait()
		end
	end
	local ok, d = pcall(decide, bot, view, rng, hand, yield)
	thinking = false
	if not ok then
		warn("[8ball] bot brain failed: " .. tostring(d))
		local plan = Finder.safePlan(view)
		d = {
			kind = "safe",
			angle = plan.angle,
			power = plan.power,
			easy = false,
			called = plan.called,
			ball = plan.ball,
		} :: any
	end
	local decision: Brain.Decision = d
	-- The 2 to 4 seconds count from the end of the turn's intro (what a player sees as its
	-- turn); the brain's thinking may run through the intro.
	while live() and e.phase == "Intro" do
		task.wait(0.05)
		Tables.advance(t, now())
	end
	if not live() then
		return
	end
	local aimStartedAt = os.clock() - math.max(0, now() - e.phaseStartedAt)

	-- Its ability: Config.Ults.Pc's rule (bar full and behind, or no easy shot). Never in the
	-- tutorial's game 1 (its planned shots are worked out without one: Tutorial/BotPlan).
	local scripted = bot.script == "Tutorial" and e.tutorial ~= nil
	if
		not frozen
		and bot.ult
		and not scripted
		and Match.pcShouldActivate(e, uid, decision.easy)
	then
		UltService.activateFor(t, uid)
		local deadline = os.clock() + 4
		while live() and Match.arming(e) and os.clock() < deadline do
			task.wait(0.1)
			Tables.advance(t, now())
		end
		-- Look Over There!: no shot but the Sneak phase (sneaky ball in hand); then the cue
		-- ball has moved, so the bot thinks again from there.
		Tables.advance(t, now())
		local sneaked = e.phase == "Sneak" and e.shooter == uid
		if sneaked then
			sneakFor(bot, t, uid, rng, seat.team, yield)
			if not live() then
				return
			end
			view = viewOf(e, seat.team)
			local again, d2 = pcall(decide, bot, view, rng, hand, yield)
			if again then
				decision = d2
			end
		end
		local kind = Match.pickNeeded(e)
		if kind and live() then
			for _, request in pickRequests(kind, e, view, decision) do
				request.kind, request.epoch, request.turnId = "UltPick", e.epoch, e.turnId
				if Engine.action(e, uid, request, now()) then
					break
				end
			end
			Tables.broadcast(t)
		end
		if not sneaked then
			seconds += Config.Ults.CutsceneSeconds + Config.Ults.ArmDelaySeconds
		end
	end

	-- The 8's pocket, called before anything else (PocketChoice).
	if live() and e.phase == "PocketChoice" then
		local eight = Finder.findBall(view.balls, 8)
		local pocket = decision.called
			or (if eight then Finder.nearestPocket(view.geometry, eight.x, eight.y) else 1)
		Tables.advance(t, now())
		Engine.action(
			e,
			uid,
			{ kind = "Pocket", pocket = pocket, epoch = e.epoch, turnId = e.turnId },
			now()
		)
		Tables.broadcast(t)
	end

	-- Ball in hand: dragged from where it is to its spot while the cue turns toward the shot.
	local cue = Finder.findBall(view.balls, 0)
	local toX, toY = decision.cueX, decision.cueY
	if hand and cue and toX and toY and live() then
		local fromX, fromY = cue.x, cue.y
		local steps = math.max(1, math.floor(B.DragSeconds * B.Aim.AimSendsPerSecond))
		bot.seq = (bot.seq or 0) + 1
		for i = 1, steps do
			if not live() then
				return
			end
			local f = i / steps
			local s = f * f * (3 - 2 * f)
			bot.seq += 1
			Tables.moveBotCue(t, uid, bot.seq, fromX + (toX - fromX) * s, fromY + (toY - fromY) * s)
			Tables.setBotAim(t, uid, rough + Finder.wrap(decision.angle - rough) * s, 0)
			task.wait(1 / B.Aim.AimSendsPerSecond)
		end
		Tables.advance(t, now())
		Engine.action(
			e,
			uid,
			{ kind = "Place", x = toX, y = toY, epoch = e.epoch, turnId = e.turnId },
			now()
		)
		Tables.broadcast(t)
	end

	-- Lining up, then the strike.
	local from = if t.aim and t.aim.by == uid then t.aim.angle else rough
	local remaining = math.max(1.2, seconds - (os.clock() - aimStartedAt))
	local keys = Look.timeline(rng, decision.angle, remaining, pullFor(decision.power), from)
	local t0 = os.clock()
	while live() do
		local elapsed = os.clock() - t0
		if elapsed >= remaining then
			break
		end
		local a, pull = Look.sample(keys, elapsed)
		Tables.setBotAim(t, uid, a, pull)
		task.wait(1 / B.Aim.AimSendsPerSecond)
	end
	if not live() then
		return
	end
	local payload: any = {
		tableId = e.id,
		epoch = e.epoch,
		turnId = e.turnId,
		angle = decision.angle,
		power = decision.power,
		-- The planned spin (the tutorial bot's pot-and-scratch follows its ball down).
		spin = decision.spin or { x = 0, y = 0 },
	}
	if e.ballInHand then
		local c = Finder.findBall(e.state.balls, 0)
		payload.cueX = toX or (c and c.x)
		payload.cueY = toY or (c and c.y)
	end
	local result, reason = ShotService.submitFor(t, uid, payload, function()
		if bot.model then
			Tables.botShotAccepted(t, bot.model, decision.angle, payload.spin, nil)
		end
	end)
	if not result then
		warn(("[8ball] bot %s shot refused: %s"):format(tostring(bot.name), tostring(reason)))
	elseif RunService:IsStudio() then
		-- What the bot meant and what the table made of it (Studio only, for tuning).
		local j = e.pending and e.pending.judgement
		print(
			("[8ball] bot %s (%s) played %s: %s"):format(
				tostring(bot.name),
				tostring(bot.skill),
				decision.kind,
				if j then tostring(j.reason or (if j.foul then "foul" else "ok")) else "?"
			)
		)
	end
	local _ = Judge
end

return Driver
