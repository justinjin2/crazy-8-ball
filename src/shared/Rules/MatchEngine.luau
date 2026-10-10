--!strict
-- Authoritative match lifecycle. Plain data and explicit time inputs make every phase
-- testable in Lune. The Roblox adapter supplies identity, proximity, clock and coin RNG.
local Config = require(script.Parent.Parent.Config)
local Ball = require(script.Parent.Parent.Physics.Ball)
local Flight = require(script.Parent.Parent.Physics.Flight)
local Geometry = require(script.Parent.Parent.Physics.Table)
local Rack = require(script.Parent.Parent.Physics.Rack)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local ShotInput = require(script.Parent.Parent.ShotInput)
local Judge = require(script.Parent.ShotJudge)
local Placement = require(script.Parent.CuePlacement)
local Ults = require(script.Parent.Parent.Ults.Match)
local Arming = require(script.Parent.Parent.Ults.Arming)
local Catalog = require(script.Parent.Parent.Ults.Catalog)
local TimeStop = require(script.Parent.Parent.Ults.Effects.TimeStop)
local Cue = require(script.Parent.Parent.Physics.Cue)
local TutorialRig = require(script.Parent.Parent.Tutorial.Rig)
local M = Config.Multiplayer
local S = Config.Ults.Shared
local Engine = {}

-- A table's queue settings, as the host last left them. Fresh for every new box and game.
local function defaultSettings(): any
	return { difficulty = Config.Difficulty.Default, abilities = true }
end

function Engine.pack(balls: { any }): { number }
	local out = {}
	for _, b in balls do
		local i = b.id * 4
		out[i + 1], out[i + 2], out[i + 3], out[i + 4] = b.x, b.y, b.z, if b.pocketed then 1 else 0
	end
	return out
end

local function phase(t: any, name: string, now: number, duration: number?)
	t.phase, t.phaseStartedAt, t.deadline = name, now, if duration then now + duration else nil
	t.revision += 1
end

--- A fresh table. Every table plays one mode (designer, 2026-09-26): `teamSize` players a
--- side, 1 for 1v1, 2 for 2v2, 3 for 3v3 (Config.Hub.Tables), so its pad holds twice that.
--- `seed` picks the rack's tiny offsets; the server passes a random one so no two games open
--- on the same rack. Without it (tests) the table's fixed default is used.
function Engine.new(id: number, teamSize: number, seed: number?): any
	local geometry = Geometry.build({ pocketsOpen = true })
	seed = Rack.normalizeSeed(seed or Config.Rack.DefaultSeed + id)
	local t: any = {
		id = id,
		teamSize = teamSize,
		settings = defaultSettings(),
		epoch = 1,
		revision = 1,
		phase = "Waiting",
		phaseStartedAt = 0,
		seats = {},
		groups = {},
		timeouts = { 0, 0 },
		lastOrder = { 0, 0 },
		joinOrder = 0,
		shotSeq = 0,
		turnId = 0,
		rackSeed = seed,
		feedback = {},
		voteNextAt = { 0, 0 },
		state = Simulation.newState(geometry, Rack.newGame(geometry, seed)),
		-- The ult bars and the armed ult (Ults/Match), fresh every game, and the gains waiting
		-- to go to each bar's owner (UltService), like feedback.
		ults = Ults.new(),
		ultFeed = {},
	}
	return t
end

function Engine.seat(t: any, userId: number): any
	for _, s in t.seats do
		if s.userId == userId and s.connected then
			return s
		end
	end
	return nil
end

function Engine.count(t: any, team: number?): number
	local n = 0
	for _, s in t.seats do
		if s.connected and (team == nil or s.team == team) then
			n += 1
		end
	end
	return n
end

local function choose(t: any, team: number): any
	local first = nil
	for _, s in t.seats do
		if s.connected and s.team == team then
			first = first or s
			if s.order > t.lastOrder[team] then
				return s
			end
		end
	end
	return first
end

local function rehost(t: any)
	local old = t.hostId
	t.hostId = nil
	for _, s in t.seats do
		s.host = false
		if s.connected and t.hostId == nil then
			t.hostId, s.host = s.userId, true
		end
	end
	-- A new host asks for players themselves: the old one's request does not carry over.
	if t.hostId ~= old then
		t.requestedAt = nil
		t.lastRequestAt = nil
	end
end

--- How many players the table's pad holds: both teams.
function Engine.capacity(t: any): number
	return t.teamSize * 2
end

--- Step onto the table's pad. Only while the table waits, and only while it has room. The
--- seat has no team or slot until the game starts. An arena's table (`t.fixed`) seats each
--- player on the `team` the global queue matched them in (designer, 2026-09-28).
function Engine.join(
	t: any,
	userId: number,
	name: string,
	displayName: string,
	now: number,
	team: number?
): boolean
	if t.phase ~= "Waiting" then
		return false
	end
	if Engine.seat(t, userId) or Engine.count(t) >= Engine.capacity(t) then
		return false
	end
	if t.fixed and team ~= 1 and team ~= 2 then
		return false
	end
	if team and Engine.count(t, team) >= t.teamSize then
		return false
	end
	t.joinOrder += 1
	table.insert(t.seats, {
		userId = userId,
		name = name,
		displayName = displayName,
		joinedAt = now,
		order = t.joinOrder,
		connected = true,
		host = false,
		team = team,
	})
	rehost(t)
	t.revision += 1
	return true
end

--- Whether the players on a pad can start a game of `teamSize` a side, and if not why:
--- "Alone" (on a 1v1 table the host is offered solo instead), or "Short" with how many more
--- are needed. A game needs the pad full. Pure over a seat list, so the queue menu greys its
--- Start button from the snapshot with the same rule the server enforces.
function Engine.startState(seats: { any }, teamSize: number): (boolean, string?, number)
	local n = 0
	for _, s in seats do
		if s.connected ~= false then
			n += 1
		end
	end
	local missing = teamSize * 2 - n
	if missing <= 0 then
		return true, nil, 0
	elseif n <= 1 and teamSize == 1 then
		return false, "Alone", missing
	end
	return false, "Short", missing
end

--- When a waiting table begins by itself (designer, 2026-09-27: no Start button): once its
--- pad is full, Queue.ReadyGraceSeconds after the last one stepped on, so someone who walked
--- on by accident can step off again. Nil while the pad is not full.
function Engine.startsAt(t: any): number?
	if t.phase ~= "Waiting" or t.fixed or not Engine.startState(t.seats, t.teamSize) then
		return nil
	end
	-- A pad whose search just found a match worldwide: its players are on their way.
	if t.search and t.search.found then
		return nil
	end
	local last = -math.huge
	for _, s in t.seats do
		if s.connected and s.joinedAt > last then
			last = s.joinedAt
		end
	end
	return last + M.Queue.ReadyGraceSeconds
end

local start: (t: any, host: any, now: number, coinWinner: number?) -> ()
local rematch: (t: any, now: number, nextSeed: number?) -> ()
local finalizeShot: (t: any, before: { any }, outcome: any, now: number, from: number, redo: any?) -> ()
local strikeFrozen: (t: any, userId: number, payload: any, now: number) -> (any?, string?)
local resumeFrozen: (t: any, now: number) -> ()

-- `forfeit` names the team that gave the match up (surrendered or ran out of timeouts), for
-- the rank and money rules (Ranking). `seconds` is the server-tracked match time from the
-- break (GDD section 13's one-minute mark); 0 when the break was never taken.
local function finish(t: any, winner: number?, reason: string, now: number, forfeit: number?)
	if t.phase == "Result" or t.phase == "Waiting" then
		return
	end
	t.result = {
		winner = winner,
		reason = reason,
		forfeit = forfeit,
		seconds = if t.brokeAt then math.max(0, now - t.brokeAt) else 0,
	}
	t.vote = nil
	t.shot = nil
	t.pending = nil
	t.sneak = nil
	Ults.clearArmed(t) -- an ult armed when the game ended is spent
	Ults.clearKept(t)
	-- A two-sided game counts in the series and offers a rematch while both sides are still
	-- here (designer, 2026-09-28); solo keeps its short hold.
	local rematch = false
	if not t.solo then
		local series = t.series or { wins = { 0, 0 }, games = 0 }
		series.games += 1
		if winner == 1 or winner == 2 then
			series.wins[winner] += 1
		end
		t.series = series
		rematch = Engine.count(t, 1) > 0 and Engine.count(t, 2) > 0
	end
	t.rematch = if rematch then { yes = {} } else nil
	phase(t, "Result", now, if rematch then M.RematchSeconds else M.ResultSeconds)
end

local function needsCall(t: any): boolean
	return Judge.eligible(t.state.balls, t.groups[t.activeTeam]) and t.calledPocket == nil
end

--- Whether the shooter may move the cue ball right now: ball in hand, and either the
--- placement window or the introduction before it. An owed call for the 8 comes first, so
--- the introduction stays closed until PocketChoice has been answered.
function Engine.placementOpen(phase: string, ballInHand: boolean?, callNeeded: boolean): boolean
	return ballInHand == true and (phase == "Placement" or (phase == "Intro" and not callNeeded))
end

--- Whether the table's shooter is the table's in this phase: every client poses them (the
--- aim, the stroke), and the server may hold them (Engine.shooterHeld). From the introduction
--- through the shot's resolution, and through a foul too when playing solo, because then
--- nobody else takes the table. The coin flip has no shooter yet. `solo` is the table's (or
--- snapshot's) solo record, or nil.
function Engine.shooterLocked(phase: string, solo: any): boolean
	return phase == "Intro"
		or phase == "Placement"
		or phase == "PocketChoice"
		or phase == "Aiming"
		or phase == "Resolving"
		or phase == "Frozen"
		or phase == "Rewinding"
		or phase == "Sneak"
		or phase == "SneakReveal"
		or (phase == "Foul" and solo ~= nil and solo ~= false)
end

--- Whether the server holds the table's shooter now (their root anchored where the stance
--- puts it, walking off): whenever they are locked, except while the balls roll after their
--- shot, once Multiplayer.Stance.HoldAfterShotSeconds have passed since it was accepted, so
--- the stroke plays out on every screen and then the player may walk while they watch
--- (designer, 2026-09-25). `secondsSinceShot` nil (the shot's time unknown): free to walk.
function Engine.shooterHeld(phase: string, solo: any, secondsSinceShot: number?): boolean
	if phase == "Resolving" then
		return secondsSinceShot ~= nil and secondsSinceShot < M.Stance.HoldAfterShotSeconds
	end
	return Engine.shooterLocked(phase, solo)
end

--- Whether `phase` runs the shot clock, whose end is a timeout foul: aiming, and the break's
--- placement (moving along the line and shooting share Multiplayer.BreakSeconds). Ball in hand
--- elsewhere has its own moving time first (PlacementSeconds), then aiming.
function Engine.isShotClock(phase: string, breakShot: boolean?): boolean
	return phase == "Aiming" or (phase == "Placement" and breakShot == true)
end

-- The call for the 8 comes before ball in hand: the pocket is chosen from the top-down view,
-- then the ball is placed and shot in the 3D one. Solo has no clock: these wait for the player.
local function setup(t: any, now: number)
	local kind = if needsCall(t)
		then "PocketChoice"
		elseif t.ballInHand then "Placement"
		else "Aiming"
	local timed = t.solo == nil and TutorialRig.timed(t, kind)
	if needsCall(t) then
		phase(t, "PocketChoice", now, if timed then M.PocketChoiceSeconds else nil)
	elseif t.ballInHand then
		local seconds = if t.breakShot then M.BreakSeconds else M.PlacementSeconds
		phase(t, "Placement", now, if timed then seconds else nil)
	else
		-- Rewind's redo has its own short clock (Shared.RewindRedoSeconds).
		local seconds = if t.redoClock then S.RewindRedoSeconds else M.ShotSeconds
		phase(t, "Aiming", now, if timed then seconds else nil)
	end
end

local function beginTurn(t: any, team: number, now: number, hand: boolean, skipIntro: boolean?)
	local s = choose(t, team)
	if not s then
		finish(t, 3 - team, "EmptyTeam", now)
		return
	end
	local before = t.activeTeam
	t.activeTeam, t.shooter = team, s.userId
	t.lastOrder[team] = s.order
	t.turnId += 1
	t.calledPocket = nil
	if t.tutorial then
		-- The tutorial's game 1 (Tutorial/Rig): the player breaks from a fixed spot.
		hand = TutorialRig.turnHand(t, hand, function(x: number, y: number): boolean
			return Placement.set(t.state, 0, x, y)
		end)
	end
	t.ballInHand = hand
	t.placeSeq = 0 -- the shooter's placement counter; never part of the snapshot
	t.foul = nil
	t.redoClock = nil
	t.redosLeft = nil
	t.redoPractice = nil
	t.sneak = nil
	Ults.clearArmed(t) -- an armed ult never outlives its shooter's turn
	Ults.turnBegan(t, team == before) -- a kept Turn ult (Portals) only while its shooter keeps it
	if hand then
		local x, y = Placement.fallback(t.state, 0, t.breakShot)
		Placement.set(t.state, 0, x, y)
	end
	if t.tutorial then
		-- The tutorial's game 1 (Tutorial/Rig): ball in hand starts on a good spot, and the
		-- turn's lesson is picked from the table.
		TutorialRig.placeHand(t, function(x: number, y: number): boolean
			return Placement.set(t.state, 0, x, y)
		end)
		TutorialRig.turnBegan(t)
	end
	-- A shooter who owes the call for the 8 picks the pocket at once: the introduction would
	-- only hold the rings back (the top-down view and the prompt are already up; designer,
	-- 2026-10-05).
	if skipIntro or needsCall(t) then
		setup(t, now)
	else
		phase(t, "Intro", now, M.IntroSeconds)
	end
end

local function foul(t: any, reason: string, now: number)
	-- Any foul ends the turn: its run, and an armed ult is spent (a timeout, a death, a
	-- departure; a judged foul's shot already spent it).
	Ults.onTurnLost(t)
	t.sneak = nil
	t.foul = { by = t.shooter, team = t.activeTeam, reason = reason }
	-- Solo has nobody to hand the table to: the fouler takes ball in hand themselves.
	t.nextTeam = if t.solo then t.activeTeam else 3 - t.activeTeam
	t.breakShot = false
	t.ballInHand = true
	phase(t, "Foul", now, M.FoulSeconds)
end

function Engine.remove(t: any, userId: number, now: number): boolean
	local s = Engine.seat(t, userId)
	if not s then
		return false
	end
	if t.phase == "Waiting" then
		for i, v in t.seats do
			if v == s then
				table.remove(t.seats, i)
				break
			end
		end
		-- A party member off the pad ends the search (the server cancels it); once a match is
		-- found it stands and whoever is still in the server goes.
		if t.search and not t.search.found and table.find(t.search.users, userId) then
			t.search = nil
		end
		rehost(t)
		-- The host's choices outlive the host (the next in takes over), not the box emptying.
		if Engine.count(t) == 0 then
			t.settings = defaultSettings()
		end
		phase(t, "Waiting", now, nil)
		return true
	end
	s.connected = false
	rehost(t)
	t.revision += 1
	-- Leaving after a game says no to the rematch, and the table frees.
	if t.phase == "Result" and t.rematch and not t.rematch.declined then
		t.rematch.declined = userId
		t.deadline = now
	end
	if Engine.count(t, s.team) == 0 then
		if t.phase ~= "Resolving" then
			finish(t, if Engine.count(t, 3 - s.team) > 0 then 3 - s.team else nil, "EmptyTeam", now)
		end
	elseif
		t.shooter == userId
		and (
			t.phase == "Intro"
			or t.phase == "Placement"
			or t.phase == "PocketChoice"
			or t.phase == "Aiming"
			-- Rewind's table is already back: the redo would be theirs.
			or t.phase == "Rewinding"
			-- Look Over There!: what they sneaked stays sneaked; the turn passes.
			or t.phase == "Sneak"
			or t.phase == "SneakReveal"
		)
	then
		foul(t, "Departure", now)
	end
	return true
end

function Engine.death(t: any, userId: number, now: number)
	if
		t.shooter == userId
		and not TutorialRig.isPlayer(t, userId) -- game 1 (the rig) keeps its lesson on a reset
		and (
			t.phase == "Intro"
			or t.phase == "Placement"
			or t.phase == "PocketChoice"
			or t.phase == "Aiming"
			or t.phase == "Rewinding"
			or t.phase == "Sneak"
			or t.phase == "SneakReveal"
		)
	then
		foul(t, "Reset", now)
	end
end

-- Private bonus stings for the accepted shot, one per owned ball that drops. Decided at
-- acceptance so each can sound the moment its ball drops in the replay. Owners come from the
-- groups AFTER this shot, so the ball that picks the colors earns one too. The break keeps the
-- table open, so no ball is anyone's yet: every object ball it drops earns the breaker's team
-- one (designer, 2026-09-26), foul or not, as an owned ball does. Any other shot that leaves
-- the table open (a foul, an early eight) awards nothing. Only a winning eight pays.
-- Solo plays both groups, so once the colors exist every group ball is the solo player's.
function Engine.awards(t: any, j: any, now: number)
	local solo = if t.solo and j.groups[t.solo.team] then t.solo.team else nil
	local breaker = if t.breakShot then t.activeTeam else nil
	for _, drop in j.drops do -- deduped, chronological, never the cue ball
		local group = Judge.group(drop.ball)
		local owner = if group and solo
			then solo
			elseif group and group == j.groups[1] then 1
			elseif group and group == j.groups[2] then 2
			elseif group and breaker then breaker
			else nil
		if drop.ball == 8 and j.reason == "LegalEight" then
			owner = j.winner
		end
		if owner then
			table.insert(t.feedback, {
				id = ("%d:%d:%d:%d"):format(t.id, t.epoch, t.shotSeq, drop.index),
				team = owner,
				ball = drop.ball,
				seq = t.shotSeq,
				index = drop.index,
				at = now + drop.t,
			})
		end
	end
end

-- Look Over There! (the designer's second rework round, 2026-10-08): the armed Sneak ult opens
-- the Sneak phase instead of a shot. The opponents turn away (Shared.SneakIntroSeconds), then
-- the shooter has SneakDragSeconds (plus SneakGraceSeconds for the network) to move the cue
-- ball anywhere on the cloth: ball in hand's own drag and rules (placeCue, Engine.sneakOpen).
-- The window's end spends the ult and opens SneakReveal (the opponents turn back to see it);
-- after it the turn's run-up starts over (`setup`: a fresh clock) from wherever the cue ball
-- was left. `t.sneak` = { by, seq (the ult's), at, dragAt, dragEnd, fromX, fromY (the cue
-- ball before) } and, at the reveal, { revealAt, x, y (where it was left), moved }.
local function beginSneak(t: any, now: number)
	local armed = (t.ults :: any).armed
	local cue = Simulation.findBall(t.state, 0)
	t.sneak = {
		by = t.shooter,
		seq = armed.seq,
		at = now,
		dragAt = now + S.SneakIntroSeconds,
		dragEnd = now + S.SneakIntroSeconds + S.SneakDragSeconds,
		fromX = if cue then cue.x else nil,
		fromY = if cue then cue.y else nil,
	}
	phase(t, "Sneak", now, S.SneakIntroSeconds + S.SneakDragSeconds + S.SneakGraceSeconds)
end

local function revealSneak(t: any, now: number)
	Ults.clearArmed(t) -- spent: the bar was paid at activation
	local sneak = t.sneak
	local cue = Simulation.findBall(t.state, 0)
	sneak.revealAt = now
	if cue then
		sneak.x, sneak.y = cue.x, cue.y
		local dx, dy = cue.x - (sneak.fromX or cue.x), cue.y - (sneak.fromY or cue.y)
		sneak.moved = dx * dx + dy * dy > 1e-6
	end
	phase(t, "SneakReveal", now, S.SneakRevealSeconds)
end

--- Whether Look Over There!'s shooter may move the cue ball at `now`: the Sneak phase's drag
--- window (`sneak` the table's or the snapshot's), from its opening (less the grace, for the
--- clocks' drift) to its end plus the grace. A client stops a little sooner, so its last spot
--- arrives in time.
function Engine.sneakOpen(phaseName: string, sneak: any, now: number): boolean
	return phaseName == "Sneak"
		and type(sneak) == "table"
		and type(sneak.dragAt) == "number"
		and type(sneak.dragEnd) == "number"
		and now >= sneak.dragAt - S.SneakGraceSeconds
		and now < sneak.dragEnd + S.SneakGraceSeconds
end

-- Rewind (7.6): the table goes back to exactly before the shot (every ball, ball in hand,
-- groups, the call) for everyone to watch rewind, then the same shooter shoots again on a
-- RewindRedoSeconds clock. The redo is a plain shot that rewinds again the same way while
-- redos are left (Shared.RewindRedos a Rewind).
local function rewindTo(t: any, redo: any, now: number)
	t.state.balls = Ball.cloneList(redo.balls)
	t.state.time = 0
	t.state.overrides = nil
	t.state.fx = nil
	t.pending = nil
	t.shot = nil
	t.groups = table.clone(redo.groups)
	t.calledPocket = redo.calledPocket
	t.ballInHand = redo.ballInHand
	t.breakShot = redo.breakShot
	t.foul = nil
	t.redoClock = true
	t.redosLeft = redo.left - 1
	t.redoPractice = redo.practice
	t.rewound = { at = now, seq = t.shotSeq }
	phase(t, "Rewinding", now, S.RewindSeconds)
end

local function resolve(t: any, now: number)
	local pending = t.pending
	if not pending then
		return
	end
	-- No rewind once a side has emptied (its shooter left mid-shot): the game ends below.
	local emptied = if t.solo
		then Engine.count(t, t.solo.team) == 0
		else Engine.count(t, 1) == 0 or Engine.count(t, 2) == 0
	if pending.redo and not emptied then
		rewindTo(t, pending.redo, now)
		return
	end
	t.state.balls = Ball.cloneList(pending.outcome.finalBalls)
	t.state.time = 0
	t.state.overrides = nil
	t.pending = nil
	t.shot = nil
	local j = pending.judgement
	t.groups = j.groups
	if j.respotEight then
		local x, y = Placement.fallback(t.state, 8, false)
		Placement.set(t.state, 8, x, y)
	end
	-- The tutorial's 8 guard (Tutorial/Rig): the 8 back where it stood, or the nearest free spot.
	if j.eightBack then
		if not Placement.set(t.state, 8, j.eightBack.x, j.eightBack.y) then
			local x, y = Placement.fallback(t.state, 8, false)
			Placement.set(t.state, 8, x, y)
		end
	end
	-- Object balls that flew off the table go back on, in number order.
	for _, id in j.respot or {} do
		local x, y = Placement.fallback(t.state, id, false)
		Placement.set(t.state, id, x, y)
	end
	local solo = t.solo
	if solo then
		-- The first group picked is played first, then the other; the empty second team holds
		-- whichever is left, so every group check (first contact, the 8, the call) just works.
		-- Fouls that clear both groups while the table is still open never pick one: then
		-- only the 8 is left and it is on.
		solo.first = solo.first
			or j.groups[solo.team]
			or (
				if Judge.remaining(t.state.balls, "solids")
							+ Judge.remaining(t.state.balls, "stripes")
						== 0
					then "solids"
					else nil
			)
		local current = Judge.soloGroup(t.state.balls, solo.first)
		if current then
			t.groups = {}
			t.groups[solo.team], t.groups[3 - solo.team] = current, Judge.opposite(current)
		end
		if Engine.count(t, solo.team) == 0 then
			finish(t, nil, "EmptyTeam", now)
			return
		end
	elseif Engine.count(t, 1) == 0 or Engine.count(t, 2) == 0 then
		local winner = if Engine.count(t, 1) > 0 then 1 elseif Engine.count(t, 2) > 0 then 2 else nil
		finish(t, winner, "EmptyTeam", now)
		return
	end
	if j.winner then
		finish(t, j.winner, j.reason, now)
		return
	end
	t.breakShot = false
	if j.foul then
		foul(t, j.foul, now)
		return
	end
	-- Solo always keeps the table and, after the break, never repeats the introduction.
	local keep = j.keep or solo ~= nil
	local team = if keep then t.activeTeam else 3 - t.activeTeam
	beginTurn(
		t,
		team,
		now,
		false,
		solo ~= nil or (keep and t.teamSize == 1 and Engine.seat(t, t.shooter) ~= nil)
	)
end

--- `nextSeed` is the server's randomness (the next game's rack), passed in so this stays
--- deterministic; tests may omit it.
function Engine.advance(t: any, now: number, nextSeed: number?)
	-- An arming ult becomes armed (the shot clock's pause ends); Look Over There!'s opens the
	-- Sneak phase.
	Ults.tick(t, now)
	if Ults.sneakDue(t) then
		beginSneak(t, now)
	end
	if t.vote then
		local unanimous = true
		for _, s in t.seats do
			if s.connected and s.team == t.vote.team and not t.vote.yes[tostring(s.userId)] then
				unanimous = false
			end
		end
		if unanimous then
			finish(t, 3 - t.vote.team, "Surrender", now, t.vote.team)
		elseif now >= t.vote.deadline then
			t.vote = nil
			t.revision += 1
		end
	end
	-- Everyone still here pressed Rematch: the same players again at once.
	if t.phase == "Result" and Engine.rematchReady(t) then
		rematch(t, now, nextSeed)
		return
	end
	-- A full pad starts by itself after the join grace. The coin comes from the next rack
	-- seed, so this stays deterministic.
	local startsAt = Engine.startsAt(t)
	if startsAt and now >= startsAt then
		local host = Engine.seat(t, t.hostId)
		if host then
			start(t, host, now, if nextSeed and nextSeed % 2 == 1 then 2 else 1)
			return
		end
	end
	if not t.deadline or now < t.deadline then
		return
	end
	if t.phase == "CoinFlip" then
		beginTurn(t, t.activeTeam, now, true)
	elseif t.phase == "Rewinding" and not (Engine.seat(t, t.shooter) or {} :: any).connected then
		-- Rewind's shooter left while the shot resolved (a team game goes on): the redo is
		-- nobody's, so the turn passes as a departure.
		foul(t, "Departure", now)
	elseif t.phase == "Intro" or t.phase == "Rewinding" then
		-- After the introduction, or after Rewind's table went back (its redo clock is set).
		setup(t, now)
	elseif t.phase == "Placement" and not t.breakShot then
		t.ballInHand = false
		setup(t, now)
	elseif t.phase == "PocketChoice" then
		local eight = assert(Simulation.findBall(t.state, 8))
		local best, bestD = nil, math.huge
		for _, p in t.state.geometry.pockets do
			local d = (p.x - eight.x) ^ 2 + (p.y - eight.y) ^ 2
			if d < bestD then
				best, bestD = p.id, d
			end
		end
		t.calledPocket = best
		setup(t, now)
	elseif t.phase == "Sneak" then
		-- The window closed: the cue ball stays where it was left, and the ult is spent.
		revealSneak(t, now)
	elseif t.phase == "SneakReveal" then
		t.sneak = nil
		setup(t, now)
	elseif Engine.isShotClock(t.phase, t.breakShot) then
		-- The other side's turn-end fill; an armed ult is spent (it was pressed).
		Ults.onTimeout(t, now)
		t.timeouts[t.activeTeam] += 1
		if t.timeouts[t.activeTeam] >= M.TimeoutLimit then
			finish(t, 3 - t.activeTeam, "Timeouts", now, t.activeTeam)
		else
			foul(t, "Timeout", now)
		end
	elseif t.phase == "Resolving" then
		resolve(t, now)
	elseif t.phase == "Frozen" then
		resumeFrozen(t, now)
	elseif t.phase == "Foul" then
		beginTurn(t, t.nextTeam, now, true, t.solo ~= nil)
	elseif t.phase == "Result" then
		local fresh = Engine.new(t.id, t.teamSize, nextSeed or t.rackSeed + 1)
		fresh.epoch = t.epoch + 1
		fresh.revision = t.revision + 1
		fresh.phaseStartedAt = now
		fresh.fixed = t.fixed -- an arena's table stays one; the series ends with the pairing
		table.clear(t)
		for _, key in
			{
				"id",
				"teamSize",
				"settings",
				"epoch",
				"revision",
				"phase",
				"phaseStartedAt",
				"seats",
				"groups",
				"timeouts",
				"lastOrder",
				"joinOrder",
				"shotSeq",
				"turnId",
				"rackSeed",
				"feedback",
				"voteNextAt",
				"state",
				"fixed",
				"ults",
				"ultFeed",
			}
		do
			t[key] = fresh[key]
		end
	end
end

-- Move the cue ball for ball in hand, or in Look Over There!'s sneak. `seq` is the shooter's
-- per-turn counter: unreliable packets can arrive late or out of order, so anything not newer
-- than the last applied move is dropped. A Place without one (older clients, tests) is still
-- judged on its own.
local function placeCue(t: any, x: any, y: any, seq: any, now: number): boolean
	if
		not Engine.placementOpen(t.phase, t.ballInHand, needsCall(t))
		and not Engine.sneakOpen(t.phase, t.sneak, now)
	then
		return false
	end
	if t.phase == "Placement" and t.deadline and now >= t.deadline then
		return false
	end
	if seq ~= nil and (not ShotInput.isFinite(seq) or seq % 1 ~= 0 or seq <= (t.placeSeq or 0)) then
		return false
	end
	if not Placement.valid(t.state, x, y, t.breakShot) then
		return false
	end
	Placement.set(t.state, 0, x, y)
	if seq ~= nil then
		t.placeSeq = seq
	end
	if t.tutorial then
		TutorialRig.cueMoved(t)
	end
	return true
end

--- The unreliable ball-in-hand stream (AimUpdate). Same rules as Place, but no revision bump,
--- so a drag never triggers a snapshot broadcast; the periodic snapshot and the drag's final
--- reliable Place carry the spot. seq is required, because the stream can reorder.
function Engine.moveCue(t: any, userId: number, request: any, now: number): boolean
	if not Engine.seat(t, userId) or userId ~= t.shooter then
		return false
	end
	if request.epoch ~= t.epoch or request.turnId ~= t.turnId or request.seq == nil then
		return false
	end
	return placeCue(t, request.x, request.y, request.seq, now)
end

-- The host's Start: teams from the box, then the coin at once (no countdown, designer
-- 2026-09-25). Two players split by who came first, the host being team A; four or six by
-- the half each stands in, slots in the order they came. The host's team calls heads.
function start(t: any, host: any, now: number, coinWinner: number?)
	local seats = {}
	for _, s in t.seats do
		if s.connected then
			table.insert(seats, s)
		end
	end
	table.sort(seats, function(a: any, b: any)
		return a.order < b.order
	end)
	-- Teams by arrival: the first in (the host) is team A, the next team B, and so on
	-- alternately (designer, 2026-09-26). An arena's teams were set by the global queue.
	local slots = { 0, 0 }
	for i, s in seats do
		-- A lobby Fill with PC (the Bots lane) sets each seat's side beforehand (`presetTeam`):
		-- the real players together, the PC robots on the other side. Used once.
		local team = if t.fixed and s.team
			then s.team
			elseif s.presetTeam == 1 or s.presetTeam == 2 then s.presetTeam
			else (i - 1) % 2 + 1
		s.presetTeam = nil
		slots[team] += 1
		s.team, s.slot = team, slots[team]
	end
	local winner = if coinWinner == 2 then 2 else 1
	-- Against bots the real player always breaks (the Bots lane, designer 2026-10-02): the coin
	-- is still shown, landing for their side. `breakFor` is that player's seat id.
	local breaker = if t.breakFor then Engine.seat(t, t.breakFor) else nil
	if breaker and (breaker.team == 1 or breaker.team == 2) then
		winner = breaker.team
	end
	-- Every game's bars start at 0.
	t.ults, t.ultFeed = Ults.new(), {}
	t.search = nil
	t.requestedAt = nil
	t.series = t.series or { wins = { 0, 0 }, games = 0 }
	t.series.breaker = winner
	t.activeTeam, t.breakShot = winner, true
	t.coin = {
		headsTeam = host.team,
		winnerTeam = winner,
		breaker = choose(t, winner).userId,
	}
	phase(t, "CoinFlip", now, M.CoinSeconds)
end

--- Whether everyone still at a finished table has pressed Rematch (designer, 2026-09-28):
--- both sides still here, nobody said no, and every connected player with a team said yes.
function Engine.rematchReady(t: any): boolean
	local r = t.rematch
	if t.phase ~= "Result" or not r or r.declined then
		return false
	end
	if Engine.count(t, 1) == 0 or Engine.count(t, 2) == 0 then
		return false
	end
	for _, s in t.seats do
		if s.connected and s.team and not r.yes[tostring(s.userId)] then
			return false
		end
	end
	return true
end

-- The same players play again: a new game (new epoch, fresh rack, every per-game record
-- cleared), the same teams and slots, host and settings, and the series goes on. The side
-- that did not break last game breaks now, with no coin (designer, 2026-09-28).
function rematch(t: any, now: number, nextSeed: number?)
	local seats = {}
	for _, s in t.seats do
		if s.connected then
			table.insert(seats, s)
		end
	end
	local keep = {
		settings = t.settings,
		joinOrder = t.joinOrder,
		series = t.series,
		fixed = t.fixed,
		epoch = t.epoch,
		revision = t.revision,
		breakFor = t.breakFor,
	}
	local fresh = Engine.new(t.id, t.teamSize, nextSeed or t.rackSeed + 1)
	table.clear(t)
	for key, value in fresh do
		t[key] = value
	end
	t.seats = seats
	t.settings = keep.settings
	t.joinOrder = keep.joinOrder
	t.fixed = keep.fixed
	t.breakFor = keep.breakFor
	t.epoch = keep.epoch + 1
	t.revision = keep.revision + 1
	t.phaseStartedAt = now
	rehost(t)
	local series = keep.series or { wins = { 0, 0 }, games = 0 }
	local team = if series.breaker then 3 - series.breaker else 1
	-- Against bots the real player breaks every game (start's `breakFor`).
	local breaker = if t.breakFor then Engine.seat(t, t.breakFor) else nil
	if breaker and (breaker.team == 1 or breaker.team == 2) then
		team = breaker.team
	end
	series.breaker = team
	t.series = series
	t.activeTeam, t.breakShot = team, true
	beginTurn(t, team, now, true)
end

--- An arena's game starts once both sides have someone seated (everyone arrived, or the
--- arrival time ran out): the teams are the ones the queue matched, then the coin as usual.
function Engine.startFixed(t: any, now: number, coinWinner: number?): boolean
	if not t.fixed or t.phase ~= "Waiting" then
		return false
	end
	if Engine.count(t, 1) == 0 or Engine.count(t, 2) == 0 then
		return false
	end
	local host = Engine.seat(t, t.hostId)
	if not host then
		return false
	end
	start(t, host, now, coinWinner)
	return true
end

--- The players a global search takes from a pad: the first `teamSize` on it by arrival (the
--- host first). Anyone else stays and hosts the pad (designer, 2026-09-28).
function Engine.searchParty(t: any): { number }
	local seats = {}
	for _, s in t.seats do
		if s.connected then
			table.insert(seats, s)
		end
	end
	table.sort(seats, function(a: any, b: any): boolean
		return a.order < b.order
	end)
	local users = {}
	for i = 1, math.min(t.teamSize, #seats) do
		table.insert(users, seats[i].userId)
	end
	return users
end

--- Whether the host may start a global search now: waiting, a whole side on the pad (1v1
--- alone; 2 for 2v2, 3 for 3v3) and room left for the local game, no search yet.
function Engine.canSearch(t: any, userId: number): boolean
	local n = Engine.count(t)
	return t.phase == "Waiting"
		and not t.fixed
		and not t.search
		and t.hostId == userId
		and n >= t.teamSize
		and n < Engine.capacity(t)
end

--- The search began (the server has put it in the queue). Returns its players.
function Engine.setSearch(t: any, now: number): { number }
	local users = Engine.searchParty(t)
	t.search = { at = now, users = users, found = false }
	t.revision += 1
	return users
end

--- The search ended without a match (cancelled, or it failed).
function Engine.clearSearch(t: any): boolean
	if not t.search then
		return false
	end
	t.search = nil
	t.revision += 1
	return true
end

--- The search found a match: its players teleport, and the pad does not start while they
--- go. `users` stands in for a search a party member's step-off already cleared.
function Engine.searchFound(t: any, users: { number }, now: number)
	if t.phase ~= "Waiting" then
		return
	end
	t.search = t.search or { at = now, users = table.clone(users), found = true }
	t.search.found = true
	t.revision += 1
end

--- `coinWinner` is the server's coin for a Start (1 or 2), passed in like advance's seed so
--- this stays deterministic; tests may omit it.
function Engine.action(
	t: any,
	userId: number,
	request: any,
	now: number,
	coinWinner: number?
): boolean
	local s = Engine.seat(t, userId)
	if not s or request.epoch ~= t.epoch or request.turnId ~= t.turnId then
		return false
	end
	local kind = request.kind
	if kind == "Rematch" or kind == "Decline" then
		-- After a two-sided game (designer, 2026-09-28): everyone must say yes for a rematch;
		-- one no (or a leaver) frees the table at once.
		local r = t.rematch
		if t.phase ~= "Result" or not r or r.declined or not s.team then
			return false
		end
		if kind == "Rematch" then
			if r.yes[tostring(userId)] then
				return false
			end
			r.yes[tostring(userId)] = true
		else
			r.declined = userId
			t.deadline = now
		end
		t.revision += 1
		return true
	end
	-- An arena's table has no queue menu: its players were matched by the global queue.
	if t.fixed and t.phase == "Waiting" then
		return false
	end
	if kind == "LeaveQueue" then
		if t.phase == "Waiting" then
			return Engine.remove(t, userId, now)
		end
		return false
	elseif
		kind == "Start"
		or kind == "RequestOpponent"
		or kind == "CancelRequest"
		or kind == "StartSolo"
		or kind == "SetDifficulty"
		or kind == "SetAbilities"
	then
		-- The queue menu: the host's alone, and only before the game.
		if t.phase ~= "Waiting" or t.hostId ~= userId then
			return false
		end
		-- While the pad searches worldwide it does not start or ask by other means: a found
		-- match must find its players still waiting here.
		local starts = kind == "Start" or kind == "StartSolo" or kind == "RequestOpponent"
		if t.search and starts then
			return false
		end
		if kind == "Start" then
			-- A full pad starts by itself (Engine.startsAt); the menu has no Start button
			-- (designer, 2026-09-27). This skips the join grace on a full pad, for tests and
			-- developer tools.
			if not Engine.startState(t.seats, t.teamSize) then
				return false
			end
			start(t, s, now, coinWinner)
		elseif kind == "RequestOpponent" then
			-- While the pad has room, the host may ask everyone free in the server to join
			-- (designer, 2026-09-27: an opponent on 1v1, players on the team tables); the
			-- server sends the asks (TableService). Not more often than
			-- Queue.RequestSeconds while one stands, nor within Queue.RerequestSeconds of the
			-- last one after a cancel, so Request and Cancel cannot flood everyone with popups.
			if
				Engine.count(t) >= Engine.capacity(t)
				or (t.requestedAt and now - t.requestedAt < M.Queue.RequestSeconds)
				or (t.lastRequestAt and now - t.lastRequestAt < M.Queue.RerequestSeconds)
			then
				return false
			end
			t.requestedAt = now
			t.lastRequestAt = now
			t.revision += 1
		elseif kind == "CancelRequest" then
			-- The host takes a standing request back (designer, 2026-09-27): the snapshot
			-- loses requestedAt, which closes everyone's popup and refuses a late Join.
			if not t.requestedAt or now - t.requestedAt >= M.Queue.RequestSeconds then
				return false
			end
			t.requestedAt = nil
			t.revision += 1
		elseif kind == "StartSolo" then
			-- The host alone plays the table by themselves at once: no coin, and nobody can
			-- join until it ends. The break opens with ball in hand as usual. Only on a 1v1
			-- table: the team tables are kept for team games (designer, 2026-09-26).
			if Engine.count(t) ~= 1 or t.teamSize ~= 1 then
				return false
			end
			s.team, s.slot = 1, 1
			t.solo = { team = s.team }
			t.ults, t.ultFeed = Ults.new(), {}
			t.activeTeam, t.breakShot, t.coin = s.team, true, nil
			beginTurn(t, s.team, now, true)
		elseif kind == "SetDifficulty" then
			if type(request.value) ~= "string" or not Config.Difficulty.Levels[request.value] then
				return false
			end
			t.settings.difficulty = request.value
			t.revision += 1
		else
			-- SetAbilities: lobby tables always play with ults on (GDD section 9, 2026-09-28);
			-- only the global queue's No-ults arena turns them off, from its server record.
			return false
		end
		return true
	end
	if t.phase == "Waiting" or t.phase == "Result" then
		return false
	end
	if kind == "Surrender" then
		if t.solo then
			finish(t, nil, "Surrender", now) -- leaving a solo game has no winner
			return true
		end
		if t.teamSize == 1 then
			finish(t, 3 - s.team, "Surrender", now, s.team)
			return true
		end
		if t.vote or now < t.voteNextAt[s.team] then
			return false
		end
		t.vote =
			{ team = s.team, deadline = now + M.VoteSeconds, yes = { [tostring(userId)] = true } }
		t.voteNextAt[s.team] = now + M.VoteCooldownSeconds
		t.revision += 1
		return true
	elseif kind == "Vote" then
		if not t.vote or t.vote.team ~= s.team or type(request.yes) ~= "boolean" then
			return false
		end
		if request.yes then
			t.vote.yes[tostring(userId)] = true
		else
			t.vote = nil
		end
		t.revision += 1
		Engine.advance(t, now)
		return true
	end
	if userId ~= t.shooter then
		return false
	end
	if kind == "Place" then
		if not placeCue(t, request.x, request.y, request.seq, now) then
			return false
		end
	elseif kind == "Pocket" then
		-- The call is made once, in PocketChoice, and is final: it cannot be changed while
		-- placing or aiming.
		if
			t.phase ~= "PocketChoice" or not Judge.eligible(t.state.balls, t.groups[t.activeTeam])
		then
			return false
		end
		local found = false
		for _, p in t.state.geometry.pockets do
			if p.id == request.pocket then
				found = true
			end
		end
		if not found then
			return false
		end
		t.calledPocket = request.pocket
		setup(t, now)
	elseif kind == "UltPick" then
		-- The armed ult's aim-phase pick (Heat Seeker's ball, Portals' spots), checked there.
		return (Ults.pick(t, userId, request))
	else
		return false
	end
	t.revision += 1
	return true
end

-- Judges a settled shot and moves the table to Resolving: the verdict, the replay's final
-- positions, the pocket stings and the ult bars; or, for Rewind (`redo`) when none of the
-- shooter's balls dropped, the rewind instead (no stings, no fill, the table goes back at
-- resolution). `from` is the shot time the clients' replay resumes from now (0, or Time
-- Stop's resume), so the times handed on are measured from it.
function finalizeShot(t: any, before: { any }, outcome: any, now: number, from: number, redo: any?)
	-- Casual tables (every table until ranked exists) drop the rail-after-contact rule.
	local requireRail = if t.ranked then M.RailAfterContact.Ranked else M.RailAfterContact.Casual
	local j = Judge.resolve(
		before,
		outcome,
		t.groups,
		t.activeTeam,
		t.breakShot,
		t.calledPocket,
		requireRail
	)
	if t.tutorial then
		j = TutorialRig.judge(t, before, j) -- game 1: no loss on the 8 (Tutorial/Rig)
		TutorialRig.shotDone(t, t.shot, j)
	end
	local shot = t.shot
	shot.final = Engine.pack(outcome.finalBalls)
	shot.checksum = Simulation.checksum(outcome.finalBalls)
	-- Only on the shot that picks the colors. t.groups still changes at resolution; clients
	-- reveal both teams' groups when their replay drops this ball.
	shot.assign = if j.assign
		then { groups = table.clone(j.groups), ball = j.assign.ball, index = j.assign.index }
		else nil
	-- Whether this shot's 8 wins the game: only then does its drop get the pocket burst and
	-- NICE SHOT! (designer, 2026-09-27: never for an early, wrong-pocket or foul 8).
	shot.eightWins = j.reason == "LegalEight"
	local base = now - from
	local rewind = false
	if redo then
		rewind = j.winner ~= t.activeTeam
		for _, d in j.drops do
			if table.find(redo.own, d.ball) then
				rewind = false
			end
		end
	end
	if rewind then
		-- Nothing of this try counts: no stings, no fill, no groups, no win or loss.
		shot.rewind = true
		shot.eightWins = false
		shot.assign = nil
		t.pending = { outcome = outcome, judgement = j, redo = redo }
		Ults.onShot(t, j, before, base, outcome.events, true)
	else
		t.pending = { outcome = outcome, judgement = j }
		Engine.awards(t, j, base)
		-- The ult bars fill (and an armed ult is spent) while groups are still the shot's own.
		Ults.onShot(t, j, before, base, outcome.events)
	end
	local pocketed = false
	local settle = outcome.duration - from
	local extra = 0
	for _, ev in outcome.events do
		if ev.t < from then
			continue
		end
		if ev.type == "pocket" or ev.type == "removed" then
			pocketed = true
		elseif ev.type == "ult" and ev.kind == "slow" and ev.value then
			extra += ev.value
		elseif ev.type == "offTable" then
			-- Everyone watches it drop to the floor and roll before the foul is called.
			local ball = Simulation.findBall({ balls = outcome.finalBalls } :: any, ev.ball)
			if ball then
				local E = Config.Effects
				settle = math.max(
					settle,
					ev.t
						- from
						+ Flight.floorTime(ball.z, ball.vz)
						+ E.FlyOffRollSeconds
						+ E.FlyOffFadeSeconds
				)
			end
		end
	end
	phase(t, "Resolving", now, settle + extra + (if pocketed then M.PocketSettleSeconds else 0))
end

function Engine.acceptShot(t: any, userId: number, payload: any, now: number): (any?, string?)
	if not Engine.seat(t, userId) or t.shooter ~= userId then
		return nil, "NotShooter"
	end
	if payload.epoch ~= t.epoch or payload.turnId ~= t.turnId then
		return nil, "StaleTurn"
	end
	if t.phase == "Frozen" then
		return strikeFrozen(t, userId, payload, now)
	end
	if t.phase ~= "Intro" and t.phase ~= "Placement" and t.phase ~= "Aiming" then
		return nil, "WrongPhase"
	end
	-- An ult still in its cutscene: the shot waits until it is armed. Look Over There! armed
	-- is no shot at all: its Sneak phase opens at the next advance.
	Ults.tick(t, now)
	if Ults.arming(t) or Ults.sneakDue(t) then
		return nil, "UltArming"
	end
	if t.deadline and now >= t.deadline then
		return nil, "Expired"
	end
	if needsCall(t) then
		return nil, "CallRequired"
	end
	-- A pick ult (Heat Seeker's ball, Portals' spots) waits for its pick.
	if Ults.pickNeeded(t) then
		return nil, "PickRequired"
	end
	local shot, why = ShotInput.validate(payload, nil)
	if not shot then
		return nil, why
	end
	local sim = Simulation.cloneState(t.state)
	if t.tutorial then
		-- The tutorial's game 1 (Tutorial/Rig): the player's break is the rigged one.
		shot = TutorialRig.shot(t, userId, shot, function(x: number, y: number): boolean
			return Placement.set(sim, 0, x, y)
		end)
		if t.breakShot and TutorialRig.isPlayer(t, userId) then
			payload = table.clone(payload)
			payload.cueX, payload.cueY = nil, nil
		end
	end
	if payload.cueX ~= nil or payload.cueY ~= nil then
		if t.ballInHand then
			if not Placement.valid(sim, payload.cueX, payload.cueY, t.breakShot) then
				return nil, "InvalidPlacement"
			end
			Placement.set(sim, 0, payload.cueX, payload.cueY)
		else
			-- The window closed while this shot was in flight. Repeating the spot the ball
			-- was locked at is fine; moving it is not.
			local cue, eps = Simulation.findBall(sim, 0), M.PlacementEchoEpsilonInches
			if
				not (
					cue
					and ShotInput.isFinite(payload.cueX)
					and ShotInput.isFinite(payload.cueY)
					and math.abs(payload.cueX - cue.x) <= eps
					and math.abs(payload.cueY - cue.y) <= eps
				)
			then
				return nil, "InvalidPlacement"
			end
		end
	end
	local start = Engine.pack(sim.balls)
	local before = Ball.cloneList(sim.balls)
	local strike = Simulation.strike(sim, shot)
	-- The shooter's armed ult: its effect steps with the physics for this whole shot (a
	-- placeholder has none), and the replay carries it in overrides.
	local ult = Ults.shotOverrides(t, before)
	if t.tutorial then
		-- Game 1's hidden help (Tutorial/Rig), with their armed ability inside it.
		ult = TutorialRig.assist(t, userId, before, shot, ult)
	end
	if ult then
		Simulation.armEffect(sim, ult.Effect, ult.Targets, ult.EightPocket, ult.extra)
	end
	local cue = Simulation.findBall(sim, 0)
	assert(cue, "Missing cue ball")
	local seed = ShotInput.quantiseSeed(cue)
	local outcome = Simulation.settle(sim, { strike })
	-- A capped simulation cannot safely award a result. Reject without changing state.
	if outcome.capped then
		return nil, "SimulationLimit"
	end
	-- The match clock for the one-minute mark starts at the break (the first accepted shot;
	-- a shot turned down above never starts it).
	t.brokeAt = t.brokeAt or now
	local tag = Ults.shotTag(t)
	-- Solo's free Practice ult pays nothing: its own shot, and the redos a practice Rewind
	-- gives (plain shots with no ult tag).
	local practice = (tag ~= nil and tag.practice == true)
		or (t.redoClock == true and t.redoPractice == true)
	-- Rewind (7.6): the exact table before this shot, to go back to if none of the shooter's
	-- balls drop: the Rewind shot itself, then each redo while redos are left.
	local row = if tag then Catalog.get(tag.id) else nil
	local redo = nil
	local left = nil
	if row and row.Built and row.Redo then
		left = S.RewindRedos
	elseif t.redoClock and (t.redosLeft or 0) > 0 then
		left = t.redosLeft
	end
	if left then
		local own = Arming.targets(t.groups, t.activeTeam, t.calledPocket, before)
		redo = {
			balls = Ball.cloneList(before),
			ballInHand = t.ballInHand,
			groups = table.clone(t.groups),
			calledPocket = t.calledPocket,
			breakShot = t.breakShot,
			own = own,
			left = left,
			practice = practice,
		}
	end
	t.state.balls = before
	t.shotSeq += 1
	t.timeouts[t.activeTeam] = 0
	t.ballInHand = false
	t.redoClock = nil
	t.redoPractice = nil
	t.shot = {
		tableId = t.id,
		epoch = t.epoch,
		turnId = t.turnId,
		seq = t.shotSeq,
		shooter = userId,
		startedAt = now,
		seed = seed,
		start = start,
		duration = outcome.duration,
		overrides = outcome.overrides,
		-- The ult this shot is: { id, by, practice }, or nil.
		ult = tag,
		-- A practice shot (see `practice` above): Economy pays it nothing.
		practice = if practice then true else nil,
	}
	if outcome.halted then
		-- Time Stop's freeze (7.7): everyone replays up to it; the shooter may strike the cue
		-- ball once more while it lasts (Engine.acceptShot in the Frozen phase), then the shot
		-- settles on and is judged as one.
		local extra = outcome.extraSeconds or 0
		t.shot.halted = true
		t.shot.parts = {}
		t.pending = {
			frozen = {
				sim = sim,
				before = before,
				events = outcome.events,
				freezeAt = now + outcome.duration + extra,
			},
		}
		phase(t, "Frozen", now, outcome.duration + extra + S.FrozenSeconds)
		return t.shot, nil
	end
	finalizeShot(t, before, outcome, now, 0, redo)
	return t.shot, nil
end

-- The shooter's strikes in stopped time (Time Stop, 7.7), through the same ShotFired as any
-- shot: only while frozen, up to Shared.TimeStopStrikes, each after the replay has reached the
-- freeze (or the last strike's end). The cue ball alone moves until it touches something
-- (Ults/Effects/TimeStop); then, with a strike left and the cue ball still up, a fresh
-- FrozenSeconds for the next, otherwise time resumes Shared.ResumeAfterStrikeSeconds after
-- that part ends. Each strike's part goes to the clients in order (shot.parts.strikes).
function strikeFrozen(t: any, userId: number, payload: any, now: number): (any?, string?)
	local frozen = t.pending and t.pending.frozen
	if userId ~= t.shooter then
		return nil, "NotShooter"
	elseif not frozen or not TimeStop.isFrozen(frozen.sim) then
		return nil, "NotFrozen"
	end
	if now < frozen.freezeAt then
		return nil, "NotFrozenYet"
	end
	if t.deadline and now >= t.deadline then
		return nil, "Expired"
	end
	local shot, why = ShotInput.validate(payload, nil)
	if not shot then
		return nil, why
	end
	local sim = frozen.sim
	local cue = Simulation.findBall(sim, 0)
	if cue == nil or cue.pocketed then
		return nil, "NoCueBall"
	end
	local from = sim.time
	-- Strike a copy of the cue ball for its seed, exactly as a first strike is struck.
	local probe = Ball.clone(cue)
	Cue.strike(probe, shot)
	local seed = ShotInput.quantiseSeed(probe)
	TimeStop.beginStrike(sim, seed)
	table.insert(
		frozen.events,
		{ t = sim.time, type = "cueStrike", ball = 0, speed = math.sqrt(seed.vx ^ 2 + seed.vy ^ 2) }
	)
	local part = Simulation.settle(sim, frozen.events)
	if part.capped then
		return nil, "SimulationLimit"
	end
	local length = sim.time - from
	t.shot.parts = t.shot.parts or {}
	t.shot.parts.strikes = t.shot.parts.strikes or {}
	table.insert(t.shot.parts.strikes, { seed = seed, startedAt = now, duration = length })
	local after = Simulation.findBall(sim, 0)
	if TimeStop.isFrozen(sim) and after and not after.pocketed then
		frozen.freezeAt = now + length
		phase(t, "Frozen", now, length + S.FrozenSeconds)
	else
		phase(t, "Frozen", now, length + S.ResumeAfterStrikeSeconds)
	end
	return t.shot, nil
end

-- Time resumes (the deadline of the freeze, or of the second strike's part): every stored
-- motion comes back and the shot settles to rest, then it is judged as one shot.
function resumeFrozen(t: any, now: number)
	local frozen = t.pending.frozen
	local sim = frozen.sim
	local from = sim.time
	TimeStop.resume(sim)
	t.shot.parts = t.shot.parts or {}
	t.shot.parts.resume = { startedAt = now, at = from }
	local outcome = Simulation.settle(sim, frozen.events)
	if outcome.capped then
		-- Past the step cap (all but unreachable: each part has its own): every ball stops where
		-- it is and the shot is judged as the balls lie.
		for _, b in sim.balls do
			Ball.stop(b)
		end
	end
	outcome.overrides = t.shot.overrides
	t.shot.duration = outcome.duration
	finalizeShot(t, frozen.before, outcome, now, from, nil)
	-- The server's adapter pays and sends this shot now (Engine.takeLateShot).
	t.lateShot = t.shotSeq
end

--- A shot judged by the clock rather than by ShotFired (a Time Stop shot's resume): its seq
--- once, then nil, so the server's adapter pays it and sends it on.
function Engine.takeLateShot(t: any): number?
	local seq = t.lateShot
	t.lateShot = nil
	return seq
end

function Engine.snapshot(t: any): any
	local seats = {}
	for _, s in t.seats do
		table.insert(seats, table.clone(s))
	end
	local rackPositions = {}
	for _, b in Rack.newGame(t.state.geometry, t.rackSeed, t.rackLayout) do
		table.insert(rackPositions, b.x)
		table.insert(rackPositions, b.y)
	end
	return {
		id = t.id,
		epoch = t.epoch,
		revision = t.revision,
		teamSize = t.teamSize,
		phase = t.phase,
		phaseStartedAt = t.phaseStartedAt,
		deadline = t.deadline,
		seats = seats,
		hostId = t.hostId,
		activeTeam = t.activeTeam,
		shooter = t.shooter,
		turnId = t.turnId,
		breakShot = t.breakShot,
		ballInHand = t.ballInHand,
		groups = table.clone(t.groups),
		calledPocket = t.calledPocket,
		coin = t.coin,
		foul = t.foul,
		result = t.result,
		vote = t.vote,
		balls = Engine.pack(t.state.balls),
		shotSeq = t.shotSeq,
		rackSeed = t.rackSeed,
		rackPositions = rackPositions,
		shot = t.shot,
		solo = if t.solo then table.clone(t.solo) else nil,
		settings = table.clone(t.settings),
		requestedAt = t.requestedAt,
		startsAt = Engine.startsAt(t),
		fixed = t.fixed,
		series = if t.series
			then {
				wins = table.clone(t.series.wins),
				games = t.series.games,
				breaker = t.series.breaker,
			}
			else nil,
		rematch = if t.rematch then Engine.rematchView(t.rematch) else nil,
		search = if t.search
			then { at = t.search.at, users = table.clone(t.search.users), found = t.search.found }
			else nil,
		ults = Ults.view(t),
		-- The last Rewind (7.6): clients play the table going back from `at`.
		rewound = t.rewound,
		-- This turn's clock is Rewind's short redo clock (the HUD's SECOND CHANCE pill).
		redoClock = t.redoClock == true,
		-- Look Over There!'s sneak while it plays (Sneak, SneakReveal): see beginSneak.
		sneak = if t.sneak then table.clone(t.sneak) else nil,
	}
end

--- The rematch vote as the snapshot carries it: who said yes (a sorted list) and who said
--- no, if anyone.
function Engine.rematchView(r: any): any
	local yes = {}
	for id in r.yes do
		table.insert(yes, tonumber(id))
	end
	table.sort(yes)
	return { yes = yes, declined = r.declined }
end

return Engine
