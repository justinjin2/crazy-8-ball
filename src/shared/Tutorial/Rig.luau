--!strict
-- Rig: what makes game 1 of the tutorial play the way the designer set (docs/prompts/
-- TUTORIAL_V2_PROMPT.md 4.4). The match engine calls these only for a table that carries
-- `t.tutorial` (TutorialGames sets it, Rig.new, when the player waits alone on their pad):
--
-- - The break: the cue ball stands on its fixed spot (no ball in hand), and whatever the
--   player aims or pulls, the break is Break's shot (Config.Tutorial.Break).
-- - The lessons: at each of the player's turns turnBegan picks this turn's lesson from the
--   table as it is (Tutorial/Plan): Break, then Aim (turn 2), Combo (the combination, when a
--   pair is lined up with a clear line), Ability (their bar filled; it waits for a good setup).
--   The server shows them (TutorialGames); shotDone marks them done.
-- - The clock: none while a lesson shows (the break, a lesson turn, SELECT WHICH POCKET, the
--   first ball in hand), and none on a turn right after one they let run out (away: two
--   timeouts in a row would lose). Every other turn has the usual clock.
-- - Ball in hand starts on a good spot (Plan.handSpot), lined up for the combination while it
--   waits (Plan.comboSpot: its lesson shows after the ball-in-hand one); they may move it.
-- - The hidden help (Tutorial/Assist, "TutorialAssist"): on every shot of theirs but the
--   break, nothing drawn. An ability they armed (Fire Shot) runs inside it (Inner). On the
--   aim lesson, the combination and the 8 the cue ball bends toward the planned ghost point
--   when the shot is on its line (a 2-degree miss onto a combination's back ball sends it 30
--   degrees wide: no bend on the balls themselves could save that), and the ball they are
--   sinking rolls a little farther on its way into the pocket (Carry).
-- - The 8 guard: the player cannot lose on the 8. A shot that would (an early 8, the wrong
--   pocket, a foul on the 8, the 8 off the table) puts the 8 back where it was and is a plain
--   foul ("EightBack"): the bot gets the table.
--
-- Pure: plain data in, plain data out; deterministic like the engine.

local Config = require(script.Parent.Parent.Config)
local Arming = require(script.Parent.Parent.Ults.Arming)
local UltMatch = require(script.Parent.Parent.Ults.Match)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local Plan = require(script.Parent.Plan)

local B = Config.Tutorial.Break
local P = Config.Tutorial.Plan
local A = Config.Tutorial.Assist

local Rig = {}

--- Game 1's state on the table (`t.tutorial`).
export type State = {
	player: number, -- the tutorial player's user id
	lesson: string?, -- this turn's lesson: "Break", "Aim", "Combo", "Ability" or nil
	plan: any?, -- its plan: a Plan.Pot (Aim, Ability) or a Plan.Combo
	done: { [string]: boolean }, -- the lessons played (or dropped)
	waited: { [string]: number }, -- turns a lesson waited for its setup
	prompted: number, -- turns the ability lesson showed and was not used
	handTurn: boolean, -- this turn began with ball in hand
	misses: number, -- the player's misses in a row
	shots: number, -- the player's shots (the break is the first)
}

--- A fresh game 1 for `player` (a user id).
function Rig.new(player: number): State
	return {
		player = player,
		lesson = nil,
		plan = nil,
		done = {},
		waited = {},
		prompted = 0,
		handTurn = false,
		misses = 0,
		shots = 0,
	}
end

-- The table's game-1 state, with any missing field filled in.
local function stateOf(t: any): State
	local rig = t.tutorial
	rig.done = rig.done or {}
	rig.waited = rig.waited or {}
	rig.prompted = rig.prompted or 0
	rig.misses = rig.misses or 0
	rig.shots = rig.shots or 0
	return rig
end

--- The player's seat team at a rigged table (nil when not rigged or not seated).
function Rig.playerTeam(t: any): number?
	local rig = t.tutorial
	if rig == nil then
		return nil
	end
	for _, s in t.seats do
		if s.userId == rig.player and s.connected then
			return s.team
		end
	end
	return nil
end

--- The group the player plays: theirs once chosen, else the opposite of the bot's, else
--- solids (the rigged break drops solids).
function Rig.playerGroup(t: any): string
	local team = Rig.playerTeam(t)
	if team == nil then
		return "solids"
	end
	local mine = t.groups[team]
	if mine then
		return mine
	end
	local other = t.groups[3 - team]
	return if other then Judge.opposite(other) else "solids"
end

--- Whether `userId` is the rigged table's player.
function Rig.isPlayer(t: any, userId: number?): boolean
	return t.tutorial ~= nil and userId ~= nil and t.tutorial.player == userId
end

--- A turn begins with `hand` (ball in hand): on the player's break the cue ball goes to the
--- break's spot instead and stays there. Returns the hand the turn really has.
function Rig.turnHand(t: any, hand: boolean, set: (number, number) -> boolean): boolean
	if hand and t.breakShot and Rig.isPlayer(t, t.shooter) then
		set(B.CueX, B.CueY)
		return false
	end
	return hand
end

--- The player's ball in hand starts on a good spot, set through `set`: lined up for the
--- combination while it waits (Plan.comboSpot), else straight behind their easiest ball
--- (Plan.handSpot).
function Rig.placeHand(t: any, set: (number, number) -> boolean)
	if not (t.ballInHand and not t.breakShot and Rig.isPlayer(t, t.shooter)) then
		return
	end
	local rig = stateOf(t)
	local geometry, balls, group = t.state.geometry, t.state.balls, Rig.playerGroup(t)
	local x, y = nil, nil
	if not rig.done.Combo and rig.done.Aim then
		x, y = Plan.comboSpot(geometry, balls, group)
	end
	if x == nil then
		x, y = Plan.handSpot(geometry, balls, group, t.calledPocket)
	end
	if x and y then
		set(x, y)
	end
end

--- The cue ball was moved (ball in hand): the combination's plan follows it (none from a spot
--- with no line onto the pair: no lesson this turn).
function Rig.cueMoved(t: any)
	local rig = t.tutorial
	if rig == nil or rig.lesson ~= "Combo" or not Rig.isPlayer(t, t.shooter) then
		return
	end
	local combo = Plan.combo(t.state.geometry, t.state.balls, Rig.playerGroup(t))
	if combo then
		rig.plan = combo
	else
		rig.lesson, rig.plan = nil, nil
	end
end

--- Picks this turn's lesson (t.tutorial.lesson and .plan), when the player's turn begins
--- (after the cue ball is placed). The ability lesson fills their bar.
function Rig.turnBegan(t: any)
	local rig = stateOf(t)
	rig.lesson, rig.plan = nil, nil
	rig.handTurn = false
	if not Rig.isPlayer(t, t.shooter) then
		return
	end
	rig.handTurn = t.ballInHand == true and not t.breakShot
	if t.breakShot then
		rig.lesson = "Break"
		return
	end
	local geometry, balls = t.state.geometry, t.state.balls
	local group = Rig.playerGroup(t)
	if Judge.eligible(balls, group :: any) then
		return -- on the 8: SELECT WHICH POCKET (the server shows it); no more lessons
	end
	if not rig.done.Aim then
		rig.lesson, rig.plan = "Aim", Plan.aim(geometry, balls, group)
		return
	end
	if not rig.done.Combo then
		local combo = Plan.combo(geometry, balls, group) -- with ball in hand: from comboSpot
		if combo then
			rig.lesson, rig.plan = "Combo", combo
			return
		end
		rig.waited.Combo = (rig.waited.Combo or 0) + 1
		if rig.waited.Combo > P.ComboWaitTurns then
			rig.done.Combo = true -- the pair is gone or blocked: no combination this game
		end
	end
	if not rig.done.Ability and not t.ballInHand then
		local fire = Plan.fire(geometry, balls, group)
		local ready = Plan.fireGood(fire) or (rig.waited.Ability or 0) >= P.AbilityWaitTurns
		local pot = fire or Plan.choices(geometry, balls, group)[1]
		if ready and pot then
			rig.lesson, rig.plan = "Ability", pot
			UltMatch.setBar(t, rig.player, Config.Ults.BarMax)
			return
		end
		rig.waited.Ability = (rig.waited.Ability or 0) + 1
	end
end

--- Whether this turn's phase has a shot clock. `kind` is the phase it starts: "Aiming",
--- "Placement" or "PocketChoice".
function Rig.timed(t: any, kind: string?): boolean
	if t.tutorial == nil then
		return true
	end
	if not Rig.isPlayer(t, t.shooter) then
		return true
	end
	local rig = stateOf(t)
	if rig.lesson ~= nil or kind == "PocketChoice" then
		return false -- a lesson on screen
	end
	if rig.handTurn and not rig.done.Hand then
		return false -- the first ball in hand: "drag the white ball anywhere"
	end
	local team = Rig.playerTeam(t)
	if team ~= nil and (t.timeouts[team] or 0) >= 1 then
		return false -- away last turn: this one waits for them
	end
	return true
end

--- The shot the engine plays for `userId`'s `shot`: the player's break is Break's shot (and
--- the cue ball its spot, through `set`); anything else is theirs.
function Rig.shot(t: any, userId: number, shot: any, set: (number, number) -> boolean): any
	if not (t.breakShot and Rig.isPlayer(t, userId)) then
		return shot
	end
	set(B.CueX, B.CueY)
	local s = table.clone(shot)
	s.angle = B.Angle % (2 * math.pi)
	s.power = B.Power
	s.spin = { x = 0, y = 0 }
	s.elevation = Config.Cue.CueElevationDegrees
	return s
end

--- The overrides for the player's shot (in the shape of Ults.Match.shotOverrides): the hidden
--- help, "TutorialAssist", with `ult` (their armed ability, if any) inside it. Anything else
--- (the bot, the break) keeps `ult`.
function Rig.assist(t: any, userId: number, before: { any }, shot: any?, ult: any?): any?
	if t.breakShot or not Rig.isPlayer(t, userId) then
		return ult
	end
	local rig = stateOf(t)
	local team = t.activeTeam
	local groups = {}
	groups[team] = Rig.playerGroup(t)
	groups[3 - team] = Judge.opposite(groups[team])
	local own, _, eightPocket, legalEight = Arming.targets(groups, team, t.calledPocket, before)
	local extra = Arming.extras("Magnet", {
		own = own,
		opp = {},
		eightPocket = eightPocket,
		legalEight = legalEight,
		open = false,
		pick = nil,
		balls = before,
	})
	extra.OppTargets = {}
	extra.Hidden = true
	extra.Guard = true
	if rig.lesson == "Aim" or rig.lesson == "Ability" then
		extra.Lesson = true
	end
	local plan = rig.plan
	if rig.lesson == "Combo" and plan then
		extra.Combo = { first = plan.a, ball = plan.b, x = plan.gx, y = plan.gy }
		extra.Carry = { ball = plan.b, pocket = plan.pocket }
	elseif rig.lesson == "Aim" and plan then
		extra.Carry = { ball = plan.ball, pocket = plan.pocket }
	elseif legalEight and t.calledPocket then
		extra.Carry = { ball = 8, pocket = t.calledPocket } -- the 8, toward the called pocket
	end
	-- The aim help: on a lesson's own line (within Plan.TargetDegrees of it) the cue ball bends
	-- toward the lesson's ghost point (the combination's: the back ball's), and on the 8's line
	-- into the called pocket toward its ghost point; after many misses in a row, toward the pot
	-- the shot is nearest.
	local angle = if shot and type(shot.angle) == "number" then shot.angle else nil
	local function near(planned: number): boolean
		local d = math.abs((angle :: number) - planned) % (2 * math.pi)
		return math.min(d, 2 * math.pi - d) <= math.rad(P.TargetDegrees)
	end
	if angle and plan and rig.lesson == "Combo" and near(plan.angle) then
		extra.AimAt = { x = plan.ax, y = plan.ay }
	elseif angle and plan and rig.lesson == "Aim" and near(plan.angle) then
		extra.AimAt = { x = plan.ghostX, y = plan.ghostY }
	elseif angle and (legalEight or rig.misses >= A.Aim.AfterMisses) then
		local pot = Plan.target(t.state.geometry, before, groups[team], t.calledPocket, angle)
		if pot then
			extra.AimAt = { x = pot.ghostX, y = pot.ghostY }
		end
	end
	if ult then
		extra.Inner = ult.Effect
		for key, value in ult.extra or {} do
			if extra[key] == nil then
				extra[key] = value
			end
		end
	end
	return { Effect = "TutorialAssist", Targets = own, EightPocket = eightPocket, extra = extra }
end

--- The judgement the engine keeps for a shot: a loss on the 8 for the player becomes a foul
--- with the 8 put back where it stood before the shot (`eightBack`).
function Rig.judge(t: any, before: { any }, j: any): any
	local team = Rig.playerTeam(t)
	if team == nil or t.activeTeam ~= team or j.winner == nil or j.winner == team then
		return j
	end
	local out = table.clone(j)
	out.winner = nil
	out.reason = nil
	out.foul = "EightBack"
	out.keep = false
	out.respotEight = false
	for _, b in before do
		if b.id == 8 then
			out.eightBack = { x = b.x, y = b.y }
		end
	end
	return out
end

--- After a shot is judged (`j`, Rig.judge's): the player's misses in a row and the lessons
--- played. `shot` is the engine's t.shot (its shooter and ult tag).
function Rig.shotDone(t: any, shot: any, j: any)
	if t.tutorial == nil or not Rig.isPlayer(t, shot.shooter) then
		return
	end
	local rig = stateOf(t)
	rig.shots += 1
	if rig.lesson == "Break" then
		rig.done.Break = true
		return
	end
	local missed = (not j.keep or j.foul ~= nil) and j.winner == nil
	rig.misses = if missed then rig.misses + 1 else 0
	if rig.lesson == "Aim" or rig.lesson == "Combo" then
		rig.done[rig.lesson :: string] = true
	end
	if rig.handTurn then
		rig.done.Hand = true
	end
	if shot.ult and shot.ult.by == rig.player then
		rig.done.Ability = true
	elseif rig.lesson == "Ability" then
		rig.prompted += 1
		if rig.prompted >= P.AbilityPromptTurns then
			rig.done.Ability = true -- they would rather play: no more asking
		end
	end
end

return Rig
