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
local M = Config.Multiplayer
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
	t.hostId = nil
	for _, s in t.seats do
		s.host = false
		if s.connected and t.hostId == nil then
			t.hostId, s.host = s.userId, true
		end
	end
end

--- How many players the table's pad holds: both teams.
function Engine.capacity(t: any): number
	return t.teamSize * 2
end

--- Step onto the table's pad. Only while the table waits, and only while it has room. The
--- seat has no team or slot until the host starts; nothing starts by itself.
function Engine.join(
	t: any,
	userId: number,
	name: string,
	displayName: string,
	now: number
): boolean
	if t.phase ~= "Waiting" then
		return false
	end
	if Engine.seat(t, userId) or Engine.count(t) >= Engine.capacity(t) then
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

local function finish(t: any, winner: number?, reason: string, now: number)
	if t.phase == "Result" or t.phase == "Waiting" then
		return
	end
	t.result = { winner = winner, reason = reason }
	t.vote = nil
	t.shot = nil
	t.pending = nil
	phase(t, "Result", now, M.ResultSeconds)
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

-- The call for the 8 comes before ball in hand: the pocket is chosen from the top-down view,
-- then the ball is placed and shot in the 3D one. Solo has no clock: these wait for the player.
local function setup(t: any, now: number)
	local timed = t.solo == nil
	if needsCall(t) then
		phase(t, "PocketChoice", now, if timed then M.PocketChoiceSeconds else nil)
	elseif t.ballInHand then
		phase(t, "Placement", now, if timed then M.PlacementSeconds else nil)
	else
		phase(t, "Aiming", now, if timed then M.ShotSeconds else nil)
	end
end

local function beginTurn(t: any, team: number, now: number, hand: boolean, skipIntro: boolean?)
	local s = choose(t, team)
	if not s then
		finish(t, 3 - team, "EmptyTeam", now)
		return
	end
	t.activeTeam, t.shooter = team, s.userId
	t.lastOrder[team] = s.order
	t.turnId += 1
	t.calledPocket = nil
	t.ballInHand = hand
	t.placeSeq = 0 -- the shooter's placement counter; never part of the snapshot
	t.foul = nil
	if hand then
		local x, y = Placement.fallback(t.state, 0, t.breakShot)
		Placement.set(t.state, 0, x, y)
	end
	if skipIntro then
		setup(t, now)
	else
		phase(t, "Intro", now, M.IntroSeconds)
	end
end

local function foul(t: any, reason: string, now: number)
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
		)
	then
		foul(t, "Departure", now)
	end
	return true
end

function Engine.death(t: any, userId: number, now: number)
	if
		t.shooter == userId
		and (
			t.phase == "Intro"
			or t.phase == "Placement"
			or t.phase == "PocketChoice"
			or t.phase == "Aiming"
		)
	then
		foul(t, "Reset", now)
	end
end

-- Private bonus stings for the accepted shot, one per owned ball that drops. Decided at
-- acceptance so each can sound the moment its ball drops in the replay. Owners come from the
-- groups AFTER this shot, so the ball that picks the colors earns one too; a table that stays
-- open (break, foul, early eight) has no groups and awards nothing. Only a winning eight pays.
-- Solo plays both groups, so once the colors exist every group ball is the solo player's.
function Engine.awards(t: any, j: any, now: number)
	local solo = if t.solo and j.groups[t.solo.team] then t.solo.team else nil
	for _, drop in j.drops do -- deduped, chronological, never the cue ball
		local group = Judge.group(drop.ball)
		local owner = if group and solo
			then solo
			elseif group and group == j.groups[1] then 1
			elseif group and group == j.groups[2] then 2
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

local function resolve(t: any, now: number)
	local pending = t.pending
	if not pending then
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
	if t.vote then
		local unanimous = true
		for _, s in t.seats do
			if s.connected and s.team == t.vote.team and not t.vote.yes[tostring(s.userId)] then
				unanimous = false
			end
		end
		if unanimous then
			finish(t, 3 - t.vote.team, "Surrender", now)
		elseif now >= t.vote.deadline then
			t.vote = nil
			t.revision += 1
		end
	end
	if not t.deadline or now < t.deadline then
		return
	end
	if t.phase == "CoinFlip" then
		beginTurn(t, t.activeTeam, now, true)
	elseif t.phase == "Intro" then
		setup(t, now)
	elseif t.phase == "Placement" then
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
	elseif t.phase == "Aiming" then
		t.timeouts[t.activeTeam] += 1
		if t.timeouts[t.activeTeam] >= M.TimeoutLimit then
			finish(t, 3 - t.activeTeam, "Timeouts", now)
		else
			foul(t, "Timeout", now)
		end
	elseif t.phase == "Resolving" then
		resolve(t, now)
	elseif t.phase == "Foul" then
		beginTurn(t, t.nextTeam, now, true, t.solo ~= nil)
	elseif t.phase == "Result" then
		local fresh = Engine.new(t.id, t.teamSize, nextSeed or t.rackSeed + 1)
		fresh.epoch = t.epoch + 1
		fresh.revision = t.revision + 1
		fresh.phaseStartedAt = now
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
			}
		do
			t[key] = fresh[key]
		end
	end
end

-- Move the cue ball for ball in hand. `seq` is the shooter's per-turn counter: unreliable
-- packets can arrive late or out of order, so anything not newer than the last applied move
-- is dropped. A Place without one (older clients, tests) is still judged on its own.
local function placeCue(t: any, x: any, y: any, seq: any, now: number): boolean
	if not Engine.placementOpen(t.phase, t.ballInHand, needsCall(t)) then
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
local function start(t: any, host: any, now: number, coinWinner: number?)
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
	-- alternately (designer, 2026-09-26).
	local slots = { 0, 0 }
	for i, s in seats do
		local team = (i - 1) % 2 + 1
		slots[team] += 1
		s.team, s.slot = team, slots[team]
	end
	local winner = if coinWinner == 2 then 2 else 1
	t.activeTeam, t.breakShot = winner, true
	t.coin = {
		headsTeam = host.team,
		winnerTeam = winner,
		breaker = choose(t, winner).userId,
	}
	phase(t, "CoinFlip", now, M.CoinSeconds)
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
	if kind == "LeaveQueue" then
		if t.phase == "Waiting" then
			return Engine.remove(t, userId, now)
		end
		return false
	elseif
		kind == "Start"
		or kind == "StartSolo"
		or kind == "SetDifficulty"
		or kind == "SetAbilities"
	then
		-- The queue menu: the host's alone, and only before the game.
		if t.phase ~= "Waiting" or t.hostId ~= userId then
			return false
		end
		if kind == "Start" then
			if not Engine.startState(t.seats, t.teamSize) then
				return false
			end
			start(t, s, now, coinWinner)
		elseif kind == "StartSolo" then
			-- The host alone plays the table by themselves at once: no coin, and nobody can
			-- join until it ends. The break opens with ball in hand as usual. Only on a 1v1
			-- table: the team tables are kept for team games (designer, 2026-09-26).
			if Engine.count(t) ~= 1 or t.teamSize ~= 1 then
				return false
			end
			s.team, s.slot = 1, 1
			t.solo = { team = s.team }
			t.activeTeam, t.breakShot, t.coin = s.team, true, nil
			beginTurn(t, s.team, now, true)
		elseif kind == "SetDifficulty" then
			if type(request.value) ~= "string" or not Config.Difficulty.Levels[request.value] then
				return false
			end
			t.settings.difficulty = request.value
			t.revision += 1
		else
			if type(request.value) ~= "boolean" then
				return false
			end
			t.settings.abilities = request.value
			t.revision += 1
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
			finish(t, 3 - s.team, "Surrender", now)
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
	else
		return false
	end
	t.revision += 1
	return true
end

function Engine.acceptShot(t: any, userId: number, payload: any, now: number): (any?, string?)
	if not Engine.seat(t, userId) or t.shooter ~= userId then
		return nil, "NotShooter"
	end
	if payload.epoch ~= t.epoch or payload.turnId ~= t.turnId then
		return nil, "StaleTurn"
	end
	if t.phase ~= "Intro" and t.phase ~= "Placement" and t.phase ~= "Aiming" then
		return nil, "WrongPhase"
	end
	if t.deadline and now >= t.deadline then
		return nil, "Expired"
	end
	if needsCall(t) then
		return nil, "CallRequired"
	end
	local shot, why = ShotInput.validate(payload, nil)
	if not shot then
		return nil, why
	end
	local sim = Simulation.cloneState(t.state)
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
	local cue = Simulation.findBall(sim, 0)
	assert(cue, "Missing cue ball")
	local seed = ShotInput.quantiseSeed(cue)
	local outcome = Simulation.settle(sim, { strike })
	-- A capped simulation cannot safely award a result. Reject without changing state.
	if outcome.capped then
		return nil, "SimulationLimit"
	end
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
	t.state.balls = before
	t.shotSeq += 1
	t.timeouts[t.activeTeam] = 0
	t.ballInHand = false
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
		final = Engine.pack(outcome.finalBalls),
		checksum = Simulation.checksum(outcome.finalBalls),
		overrides = outcome.overrides,
		-- Only on the shot that picks the colors. t.groups still changes at resolution;
		-- clients reveal both teams' groups when their replay drops this ball.
		assign = if j.assign
			then { groups = table.clone(j.groups), ball = j.assign.ball, index = j.assign.index }
			else nil,
	}
	t.pending = { outcome = outcome, judgement = j }
	Engine.awards(t, j, now)
	local pocketed = false
	local settle = outcome.duration
	for _, ev in outcome.events do
		if ev.type == "pocket" then
			pocketed = true
		elseif ev.type == "offTable" then
			-- Everyone watches it drop to the floor and roll before the foul is called.
			local ball = Simulation.findBall({ balls = outcome.finalBalls } :: any, ev.ball)
			if ball then
				local E = Config.Effects
				settle = math.max(
					settle,
					ev.t
						+ Flight.floorTime(ball.z, ball.vz)
						+ E.FlyOffRollSeconds
						+ E.FlyOffFadeSeconds
				)
			end
		end
	end
	phase(t, "Resolving", now, settle + (if pocketed then M.PocketSettleSeconds else 0))
	return t.shot, nil
end

function Engine.snapshot(t: any): any
	local seats = {}
	for _, s in t.seats do
		table.insert(seats, table.clone(s))
	end
	local rackPositions = {}
	for _, b in Rack.newGame(t.state.geometry, t.rackSeed) do
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
	}
end

return Engine
