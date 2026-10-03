--!strict
-- The tutorial's game 1 (docs/prompts/TUTORIAL_PROMPT.md step 4): the rigged rack and break
-- (Tutorial/Break), the engine's rig (Tutorial/Rig: the fixed break, no clock, the hidden
-- assist, the 8 guard) and the tutorial bot's poor shots (Bots/Script.poor).
local H = require("./harness")
local V = require("./ult_value")
local Config = H.require("Config")
local E = H.require("Rules.MatchEngine")
local Ball = H.require("Physics.Ball")
local TableGeometry = H.require("Physics.Table")
local Simulation = H.require("Physics.Simulation")
local Judge = H.require("Rules.ShotJudge")
local Break = H.require("Tutorial.Break")
local Rig = H.require("Tutorial.Rig")
local Brain = H.require("Bots.Brain")
local Script = H.require("Bots.Script")
local Rng = H.require("Bots.Rng")
local expect = H.expect

local B = Config.Tutorial.Break
local PLAYER, BOT = 7, -1000
local geometry = TableGeometry.build({ pocketsOpen = true })

-- A rigged 1v1 table: the player, then the bot; the game begun up to the player's break.
local function rigged(): any
	local m = E.new(1, 1)
	expect(E.join(m, PLAYER, "Real", "Real", 0))
	expect(E.join(m, BOT, "Bot", "Bot", 0.1))
	m.breakFor = PLAYER
	m.tutorial = { player = PLAYER }
	m.rackSeed = B.Seed
	m.state = Simulation.newState(geometry, Break.rack(geometry))
	expect(E.action(m, m.hostId, { kind = "Start", epoch = m.epoch, turnId = m.turnId }, 0, 2))
	E.advance(m, m.deadline) -- the coin
	return m
end

local function cueOf(balls: { any }): any
	for _, b in balls do
		if b.id == 0 then
			return b
		end
	end
	return nil
end

local tests = {}

tests["the rigged break pots exactly 3 solids and leaves an easy corner pot"] = function()
	local r = Break.play(geometry, Break.shot())
	expect(not r.scratch, "no scratch")
	expect(#r.pocketed == B.Solids, "3 balls down")
	for _, id in r.pocketed do
		expect(Judge.group(id) == "solids", "only solids: " .. id)
	end
	expect(r.judgement.keep and r.judgement.foul == nil, "the player keeps the table")
	local lesson = Break.lesson(geometry, r.balls, "solids", true)
	expect(lesson ~= nil, "a straight corner pot is left")
	expect((lesson :: any).cutDegrees <= B.LessonMaxCutDegrees, "a small cut")
end

tests["the player's break is the rigged one, whatever they aim or pull"] = function()
	local m = rigged()
	expect(m.shooter == PLAYER and m.breakShot, "the player breaks")
	expect(not m.ballInHand, "no ball in hand: the cue ball stands on the break spot")
	expect(m.deadline == nil or m.phase == "Intro", "no shot clock")
	E.advance(m, m.deadline or 0) -- the intro
	local cue = cueOf(m.state.balls)
	expect(cue.x == B.CueX and cue.y == B.CueY, "on the spot")
	local shot, why = E.acceptShot(m, PLAYER, {
		epoch = m.epoch,
		turnId = m.turnId,
		angle = 2.5, -- anything at all
		power = 0.2,
		spin = { x = 0.5, y = -0.5 },
	}, 1)
	expect(shot ~= nil, "accepted: " .. tostring(why))
	local j = m.pending.judgement
	local down = {}
	for _, b in m.pending.outcome.finalBalls do
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

tests["the player's other shots carry the hidden Magnet pull"] = function()
	local m = rigged()
	m.breakShot = false
	m.phase = "Aiming"
	m.deadline = nil
	local before = Ball.cloneList(m.state.balls)
	local ult = Rig.assist(m, PLAYER, before)
	expect(ult ~= nil and ult.Effect == "Magnet", "Magnet")
	expect(ult.extra.Hidden == true, "drawn by nothing")
	for _, id in ult.Targets do
		expect(Judge.group(id) == "solids", "only the player's colour on an open table")
	end
	expect(Rig.assist(m, BOT, before) == nil, "never the bot's shots")
end

tests["the 8 guard: the player cannot lose on the 8"] = function()
	local m = rigged()
	local team = (E.seat(m, PLAYER) :: any).team
	m.activeTeam = team
	local before = Ball.cloneList(m.state.balls)
	local eight = nil
	for _, b in before do
		if b.id == 8 then
			eight = b
		end
	end
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

tests["the tutorial bot's poor shots never move the player's balls"] = function()
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
		local d = Script.poor(view, Rng.new(i))
		local trial = Brain.simulate(view, d, d.cueX, d.cueY)
		expect(trial.winner == nil, "nobody wins")
		local moved = false
		for _, b in view.balls do
			if not b.pocketed and (Judge.group(b.id) == "solids" or b.id == 8) then
				for _, a in trial.balls do
					if a.id == b.id then
						local gap = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
						if a.pocketed or gap > Config.Tutorial.BotPoor.StillInches then
							-- The 8 may move only to its spot by a pocket (the nudge).
							if b.id ~= 8 or not Break.eightPlaced(geometry, trial.balls) then
								moved = true
							end
						end
					end
				end
			end
		end
		if not moved and trial.foul == nil and #trial.pockets == 0 then
			checked += 1
		end
	end
	expect(checked >= 5, "almost always a quiet legal miss (" .. checked .. "/6)")
end

return tests
