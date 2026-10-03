--!strict
-- Rig: what makes game 1 of the tutorial play the way the designer set (docs/prompts/
-- TUTORIAL_PROMPT.md step 4; 2026-10-03). The match engine calls these only for a table that
-- carries `t.tutorial` (TutorialGames sets it when the player requests the tutorial bot):
--
--   t.tutorial = { player = userId, bot = userId }
--
-- - The break: the cue ball stands on its fixed spot (no ball in hand), and whatever the
--   player aims or pulls, the break is Break's shot (Config.Tutorial.Break).
-- - No shot clock (a first game, no hurry).
-- - The assist: the player's other shots get Magnet's pull on the first ball hit if it is
--   one of theirs (the 8 only toward the called pocket), with nothing drawn (`Hidden`).
-- - The 8 guard: the player cannot lose on the 8. A shot that would (an early 8, the wrong
--   pocket, a foul on the 8, the 8 off the table) puts the 8 back where it was and is a plain
--   foul ("EightBack"): the bot gets the table.
--
-- Pure: plain data in, plain data out; deterministic like the engine.

local Config = require(script.Parent.Parent.Config)
local Arming = require(script.Parent.Parent.Ults.Arming)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)

local B = Config.Tutorial.Break

local Rig = {}

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

--- Whether the table's turns have a shot clock.
function Rig.timed(t: any): boolean
	return t.tutorial == nil
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

--- The hidden assist for the player's shot (in the shape of Ults.Match.shotOverrides), or nil
--- (not the player, the break, or an ult of their own already armed).
function Rig.assist(t: any, userId: number, before: { any }): any?
	if t.breakShot or not Rig.isPlayer(t, userId) then
		return nil
	end
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
	return { Effect = "Magnet", Targets = own, EightPocket = eightPocket, extra = extra }
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

return Rig
