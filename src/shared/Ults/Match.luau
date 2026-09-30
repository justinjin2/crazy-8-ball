--!strict
-- The ult rules in a match (docs/prompts/ULTIMATES_PROMPT.md section 4), on the match engine's
-- plain table `t` (Rules/MatchEngine). Pure: no Instances, no Roblox APIs, no clocks (the
-- caller passes `now`), no randomness, and every list is walked as an array (seats in their
-- order, drops in time order), never hash order. MatchEngine calls it at its hook points; the
-- server's UltService calls `activate` / `practice` for the UltActivate remote and sends
-- `t.ultFeed` to each bar's owner.
--
-- Per game (fresh every game and rematch, Match.new): `t.ults` = {
--   bars = { [tostring(userId)] = Fill.Bar }, -- made when a player first needs one
--   run, -- the current turn's own balls so far (Fill's run), 0 when the turn passes
--   openPotted = { side 1, side 2 }, -- balls each side pocketed while the table was open
--   armed = { by, id, stage = "Arming" | "Armed", at, readyAt, seq, practice }?,
--   seq, -- ults armed this game (the cutscene plays once per armed.seq)
--   feedSeq, -- gain messages this game (UltGain's seq)
--   pausedUntil?, -- the shot clock is paused until then (the cutscene plus the arm delay)
--   kept?, -- a Turn ult (Portals) spent on a shot its shooter kept the table with: it acts on
--          -- each of their shots for the rest of the turn, the same pick (Armed's shape)
-- } and `t.ultFeed` = gains waiting to be sent, like t.feedback: { { userId, amount, reason,
-- ball?, at, seq } } (`at` = the server time the ball drops in the replay, or now).
--
-- The rules:
-- * Ults are on at a table when Config.Ults.Enabled, the table's settings.abilities is not
--   false, and it is not solo (solo has no bar; Match.practice arms for free instead).
-- * Only the shooter, on their own turn, before the shot, with the balls at rest: the
--   introduction, the pocket call, ball in hand and aiming (a turn's whole run-up before the
--   shot). Never on the break, only with a full bar, at most MaxPerMatch a game, and not while
--   one is already armed. Activating spends the bar at once (it cannot be cancelled), and the
--   shot clock pauses for both sides until the ult is armed: the table's deadline moves by
--   CutsceneSeconds + ArmDelaySeconds.
-- * A shot while the ult is still arming is refused ("UltArming"). The shooter's next shot
--   once it is armed is the ult shot: a built ult with an Effect gets the physics overrides
--   (Match.shotOverrides), a placeholder gets none (the cutscene, then nothing). Fouls count as
--   normal. The shot spends the armed ult.
-- * The shot clock running out while armed spends it; so does any foul or turn change, and
--   the end of the game.
-- * A Turn ult (Portals, 7.9) keeps acting after its shot: while its shooter keeps the table
--   (a legal pot), each of their next shots is an ult shot again with the same pick (`kept`),
--   until the turn passes, a foul, or the game ends.
local Config = require(script.Parent.Parent.Config)
local Judge = require(script.Parent.Parent.Rules.ShotJudge)
local NiceShot = require(script.Parent.Parent.Rules.NiceShot)
local Arming = require(script.Parent.Arming)
local Catalog = require(script.Parent.Catalog)
local Fill = require(script.Parent.Fill)

local U = Config.Ults

local Match = {}

export type Armed = {
	by: number, -- the userId who activated it
	id: string, -- the ult (Config.Ults.Catalog)
	stage: string, -- "Arming" (the cutscene and the wait) or "Armed" (the next shot is the ult)
	at: number, -- server time it was activated
	readyAt: number, -- server time it becomes Armed
	seq: number, -- the game's ult counter: clients play the cutscene once per seq
	practice: boolean, -- solo's free Practice ult: pays nothing, counts nothing
	-- The aim-phase pick, once made and checked (Arming.pick): { ballId } or the two portal
	-- spots { ax, ay, bx, by }. Nil until then (a pick ult's shot waits for it).
	pick: { number }?,
}

export type State = {
	bars: { [string]: Fill.Bar },
	run: number,
	openPotted: { number },
	armed: Armed?,
	kept: Armed?,
	seq: number,
	feedSeq: number,
	pausedUntil: number?,
}

export type FeedEntry = {
	userId: number,
	amount: number,
	reason: string,
	ball: number?,
	at: number, -- server time: the ball's drop in the replay, or now for a turn end
	seq: number, -- the message it goes out in (one per shot or timeout)
}

export type Overrides = {
	Effect: string,
	Targets: { number },
	EightPocket: number?,
	extra: { [string]: any }, -- everything else for Simulation.armEffect (OppTargets, Pick ...)
}

-- The phases in which the shooter may activate: before their shot, balls at rest.
local BEFORE_SHOT: { [string]: boolean } =
	{ Intro = true, PocketChoice = true, Placement = true, Aiming = true }

--- A game's ult state: no bars yet (each starts at 0), nothing armed.
function Match.new(): State
	return {
		bars = {},
		run = 0,
		openPotted = { 0, 0 },
		armed = nil,
		kept = nil,
		seq = 0,
		feedSeq = 0,
		pausedUntil = nil,
	}
end

-- The table's ult state, made if a fixture built the table without one.
local function stateOf(t: any): State
	if t.ults == nil then
		t.ults = Match.new()
	end
	if t.ultFeed == nil then
		t.ultFeed = {}
	end
	return t.ults
end

-- The connected seat of `userId` with a team (in the game), or nil.
local function seatOf(t: any, userId: number): any
	for _, s in t.seats do
		if s.userId == userId and s.connected and s.team ~= nil then
			return s
		end
	end
	return nil
end

-- The players still in the game, in seat order, as Fill takes them.
local function players(t: any): { Fill.Seat }
	local list: { Fill.Seat } = {}
	for _, s in t.seats do
		if s.connected and s.team ~= nil then
			table.insert(list, { userId = s.userId, team = s.team })
		end
	end
	return list
end

-- The player's bar, made if missing.
local function barOf(ults: State, userId: number): Fill.Bar
	local key = tostring(userId)
	local bar = ults.bars[key]
	if bar == nil then
		bar = Fill.newBar()
		ults.bars[key] = bar
	end
	return bar
end

local function pause(): number
	return U.CutsceneSeconds + U.ArmDelaySeconds
end

--- Whether ults are on at this table: Config.Ults.Enabled, the table's settings.abilities is
--- not false (the global queue's No ults), and not solo (solo has no bar).
function Match.enabled(t: any): boolean
	return U.Enabled == true
		and not (type(t.settings) == "table" and t.settings.abilities == false)
		and t.solo == nil
end

-- The checks every activation shares (the turn, the phase, the break, nothing armed), without
-- changing anything. Returns ok, or false and the reason.
local function allowedNow(t: any, userId: number): (boolean, string?)
	local ults = stateOf(t)
	if t.shooter ~= userId or seatOf(t, userId) == nil then
		return false, "NotYourTurn"
	elseif t.phase == "Resolving" then
		return false, "Moving"
	elseif not BEFORE_SHOT[t.phase] then
		return false, "NotYourTurn"
	elseif t.breakShot then
		return false, "Break"
	elseif ults.armed ~= nil then
		return false, "Armed"
	end
	return true, nil
end

--- Whether `userId` may activate their ult now, and if not why: "Off" (ults are off here, or
--- solo), "NotYourTurn", "Moving" (the balls are rolling), "Break", "Armed" (one is armed
--- already), "Used" (MaxPerMatch used), "NotReady" (the bar is not full). Changes nothing.
function Match.check(t: any, userId: number): (boolean, string?)
	if not Match.enabled(t) then
		return false, "Off"
	end
	local ok, reason = allowedNow(t, userId)
	if not ok then
		return false, reason
	end
	local bar = barOf(stateOf(t), userId)
	if bar.used >= U.MaxPerMatch then
		return false, "Used"
	elseif not Fill.ready(bar) then
		return false, "NotReady"
	end
	return true, nil
end

-- Arms `ultId` for `userId` from `now`: the Arming stage, the paused clock, a new seq.
local function arm(t: any, userId: number, ultId: string, now: number, practice: boolean)
	local ults = stateOf(t)
	ults.seq += 1
	local readyAt = now + pause()
	ults.armed = {
		by = userId,
		id = if Catalog.exists(ultId) then ultId else U.Default,
		stage = "Arming",
		at = now,
		readyAt = readyAt,
		seq = ults.seq,
		practice = practice,
	}
	if t.deadline ~= nil then
		t.deadline += pause()
	end
	ults.pausedUntil = readyAt
	t.revision += 1
end

-- A deadline that has passed is the turn's end, which the next advance applies.
local function expired(t: any, now: number): boolean
	return t.deadline ~= nil and now >= t.deadline
end

--- `userId` activates `ultId` (the server picked it from their equipped slot) at `now`.
--- Returns true, or false and a reason from Match.check. On success the bar is spent
--- (Fill.spend), the ult is Arming until now + CutsceneSeconds + ArmDelaySeconds, and the shot
--- clock pauses for both sides (the deadline moves by as much).
function Match.activate(t: any, userId: number, ultId: string, now: number): (boolean, string?)
	local ok, reason = Match.check(t, userId)
	if not ok then
		return false, reason
	elseif expired(t, now) then
		return false, "NotYourTurn"
	end
	Fill.spend(barOf(stateOf(t), userId))
	arm(t, userId, ultId, now, false)
	return true, nil
end

--- Solo's Practice ult: the shooter arms `ultId` for free, any number of times (the same
--- stages; `practice = true`). No bar, no pay, no count. "Off" outside solo (or with
--- Config.Ults.PracticeInSolo false); otherwise the reasons of Match.check.
function Match.practice(t: any, userId: number, ultId: string, now: number): (boolean, string?)
	if t.solo == nil or U.PracticeInSolo ~= true or U.Enabled ~= true then
		return false, "Off"
	end
	local ok, reason = allowedNow(t, userId)
	if not ok then
		return false, reason
	elseif expired(t, now) then
		return false, "NotYourTurn"
	end
	arm(t, userId, ultId, now, true)
	return true, nil
end

--- The clock: an Arming ult becomes Armed at its readyAt, and the pause ends.
function Match.tick(t: any, now: number)
	local ults = stateOf(t)
	local armed = ults.armed
	if armed ~= nil and armed.stage == "Arming" and now >= armed.readyAt then
		armed.stage = "Armed"
		ults.pausedUntil = nil
		t.revision += 1
	elseif armed == nil and ults.pausedUntil ~= nil then
		ults.pausedUntil = nil
	end
end

--- True while an ult is still arming: a shot now is refused ("UltArming").
function Match.arming(t: any): boolean
	local armed = stateOf(t).armed
	return armed ~= nil and armed.stage == "Arming"
end

-- The armed ult if the table's shooter's next shot is it (armed by them, stage Armed), else
-- the kept Turn ult still acting for them this turn.
local function shotArmed(t: any): Armed?
	local ults = stateOf(t)
	local armed = ults.armed
	if armed ~= nil and armed.stage == "Armed" and armed.by == t.shooter then
		return armed
	end
	local kept = ults.kept
	if armed == nil and kept ~= nil and kept.by == t.shooter then
		return kept
	end
	return nil
end

--- The physics overrides for the shooter's ult shot, or nil (no ult armed for this shot, or a
--- placeholder with no Effect). `before` is the table just before the strike (Arming.targets,
--- 5.7): Targets are the shooter's balls still on the table (every ball but the 8 on an open
--- table; on the legal 8 shot the 8 too, with EightPocket = the called pocket), and
--- `extra.OppTargets` the opponent's. Never the cue ball. `extra` also carries the pick and
--- the ability's own overrides (Arming.extras).
function Match.shotOverrides(t: any, before: { any }): Overrides?
	local armed = shotArmed(t)
	if armed == nil then
		return nil
	end
	local ult = Catalog.get(armed.id)
	if ult == nil or not ult.Built or type(ult.Effect) ~= "string" then
		return nil
	end
	local groups = if type(t.groups) == "table" then t.groups else nil
	local own, opp, eightPocket, legalEight =
		Arming.targets(groups, t.activeTeam, t.calledPocket, before)
	local extra = Arming.extras(ult.Effect :: string, {
		own = own,
		opp = opp,
		eightPocket = eightPocket,
		legalEight = legalEight,
		open = groups == nil or groups[t.activeTeam] == nil,
		pick = armed.pick,
		balls = before,
	})
	extra.OppTargets = opp
	if armed.pick then
		extra.Pick = table.clone(armed.pick)
	end
	return {
		Effect = ult.Effect :: string,
		Targets = own,
		EightPocket = eightPocket,
		extra = extra,
	}
end

--- The pick the armed ult still needs before its shot ("OwnBall", "Portals"), or nil: none
--- needed, or already made. A shot is refused ("PickRequired") while one is owed.
function Match.pickNeeded(t: any): string?
	local armed = shotArmed(t)
	if armed == nil or armed.pick ~= nil then
		return nil
	end
	local ult = Catalog.get(armed.id)
	if ult == nil or not ult.Built then
		return nil
	end
	return ult.Pick
end

--- The shooter's pick for their armed ult (the UltPick table action), checked by
--- Arming.pick. A pick may be changed until the shot. Returns ok, or false and why.
function Match.pick(t: any, userId: number, request: any): (boolean, string?)
	local armed = stateOf(t).armed
	if armed == nil or armed.by ~= userId or t.shooter ~= userId then
		return false, "NotArmed"
	elseif armed.stage ~= "Armed" then
		return false, "Arming"
	elseif not BEFORE_SHOT[t.phase] then
		return false, "NotYourTurn"
	end
	local ult = Catalog.get(armed.id)
	if ult == nil or not ult.Built or ult.Pick == nil then
		return false, "NoPick"
	end
	local pick, why = Arming.pick(
		ult.Pick :: string,
		request,
		t.state.geometry,
		t.groups,
		t.activeTeam,
		t.state.balls
	)
	if pick == nil then
		return false, why
	end
	armed.pick = pick
	t.revision += 1
	return true, nil
end

--- What the replay carries about this shot's ult: { id, by, practice }, or nil.
function Match.shotTag(t: any): any
	local armed = shotArmed(t)
	if armed == nil then
		return nil
	end
	return { id = armed.id, by = armed.by, practice = armed.practice }
end

--- A turn began (MatchEngine's beginTurn, the shooter already set): a kept Turn ult lasts only
--- while its own shooter keeps the table.
function Match.turnBegan(t: any, kept: boolean)
	local ults = stateOf(t)
	if ults.kept ~= nil and (not kept or ults.kept.by ~= t.shooter) then
		ults.kept = nil
		t.revision += 1
	end
end

--- Ends a kept Turn ult (the game ended).
function Match.clearKept(t: any)
	local ults = stateOf(t)
	if ults.kept ~= nil then
		ults.kept = nil
		t.revision += 1
	end
end

--- Clears an armed ult (spent: the bar was paid at activation) and the pause.
function Match.clearArmed(t: any)
	local ults = stateOf(t)
	if ults.armed ~= nil or ults.pausedUntil ~= nil then
		ults.armed = nil
		ults.pausedUntil = nil
		t.revision += 1
	end
end

-- Appends Fill's gains to t.ultFeed as one message (a new feedSeq), each with the server time
-- it lands: a ball's drop in the replay, else `now`.
local function feed(t: any, gains: { Fill.Gain }, now: number)
	if #gains == 0 then
		return
	end
	local ults = stateOf(t)
	ults.feedSeq += 1
	for _, g in gains do
		table.insert(t.ultFeed, {
			userId = g.userId,
			amount = g.amount,
			reason = g.reason,
			ball = g.ball,
			at = if g.t ~= nil then now + g.t else now,
			seq = ults.feedSeq,
		})
	end
	t.revision += 1
end

-- Whether ball `ball` dropping counts as the shooter's own pot (as Progression/Money's shot
-- pay decides it): no foul, a group ball (the 8 only when it wins), any ball on the break,
-- else a ball of the shooter's group after the shot (every group ball on the shot that picks
-- the colors).
local function ownPot(t: any, j: any, ball: number): boolean
	if j.foul ~= nil or ball == 0 then
		return false
	end
	if ball == 8 then
		return j.reason == "LegalEight" and j.winner == t.activeTeam
	end
	local group = Judge.group(ball)
	if group == nil then
		return false
	end
	if t.breakShot then
		return true
	end
	local mine = if type(j.groups) == "table" then j.groups[t.activeTeam] else nil
	if mine == nil then
		return false
	end
	return t.groups[t.activeTeam] == nil or group == mine
end

--- An accepted shot: call it at acceptance, after the judgement and before the table's groups
--- change (t.groups, t.breakShot and t.activeTeam are still the shot's). It spends the armed
--- ult if this was the ult shot, then fills the bars (Fill.shot) and appends the gains to
--- t.ultFeed. `events` are the shot's ordered events (default t.pending.outcome.events), read
--- for NICE SHOT! (the shooter's own pots, never on the break). Does nothing more when ults are
--- off or in solo.
function Match.onShot(
	t: any,
	j: any,
	before: { any },
	now: number,
	events: { any }?,
	rewound: boolean?
)
	local ults = stateOf(t)
	local armed = shotArmed(t)
	local ultShot = armed ~= nil and not armed.practice
	Match.clearArmed(t)
	-- A Turn ult (Portals) goes on acting while its shooter keeps the table with this shot.
	local row = if armed then Catalog.get(armed.id) else nil
	local keeps = not rewound and j.keep == true and j.foul == nil and j.winner == nil
	if armed and row and row.Built and row.Turn and keeps then
		if ults.kept ~= armed then
			ults.kept = armed
			t.revision += 1
		end
	elseif ults.kept ~= nil and not rewound then
		ults.kept = nil
		t.revision += 1
	end
	-- A rewound shot (Rewind, 7.6) never happened: it fills nothing for anyone.
	if not Match.enabled(t) or rewound then
		return
	end
	local list: { any } = events
		or (if t.pending and t.pending.outcome then t.pending.outcome.events else nil)
		or {}
	local pockets = t.state.geometry.pockets
	local drops: { Fill.Drop } = {}
	for _, d in j.drops or {} do
		local nice = not t.breakShot
			and ownPot(t, j, d.ball)
			and NiceShot.isNice(list, d.ball, d.index, pockets)
		table.insert(drops, { ball = d.ball, t = d.t, nice = nice })
	end
	local groups = t.groups or {}
	local open = groups[t.activeTeam] == nil or groups[3 - t.activeTeam] == nil
	local turnEnds = not j.keep and j.winner == nil
	local result = Fill.shot({
		seats = players(t),
		bars = ults.bars,
		shooter = t.shooter,
		team = t.activeTeam,
		difficulty = if type(t.settings) == "table"
			then t.settings.difficulty or Config.Difficulty.Default
			else Config.Difficulty.Default,
		breakShot = t.breakShot == true,
		groupsBefore = groups,
		groupsAfter = j.groups,
		ballsBefore = before,
		openPotted = ults.openPotted,
		drops = drops,
		run = ults.run,
		turnEnds = turnEnds,
		legal = j.foul == nil,
		ultShot = ultShot,
	})
	ults.run = result.run
	if open then
		for _, d in drops do
			if Judge.group(d.ball) ~= nil then
				ults.openPotted[t.activeTeam] += 1
			end
		end
	end
	feed(t, result.gains, now)
end

--- The shot clock ran out on the shooter: the other side's turn-end fill (Fill.timeout), the
--- run ends, and an armed ult is spent. Call it before the timeout's foul.
function Match.onTimeout(t: any, now: number)
	local ults = stateOf(t)
	Match.clearArmed(t)
	ults.run = 0
	if not Match.enabled(t) or t.shooter == nil or t.activeTeam == nil then
		return
	end
	local result = Fill.timeout({
		seats = players(t),
		bars = ults.bars,
		shooter = t.shooter,
		team = t.activeTeam,
		difficulty = if type(t.settings) == "table"
			then t.settings.difficulty or Config.Difficulty.Default
			else Config.Difficulty.Default,
	})
	feed(t, result.gains, now)
end

--- The turn passed with no shot judged (a foul called by the server: a death, a departure):
--- the run ends and an armed ult is spent.
function Match.onTurnLost(t: any)
	Match.clearArmed(t)
	Match.clearKept(t)
	stateOf(t).run = 0
end

--- The snapshot's `ults`: { on, bars = { [tostring(userId)] = { bar, used, ready } } (every
--- player in the game while ults are on; empty otherwise), armed = { by, id, stage, at,
--- readyAt, seq, practice }?, pausedUntil? }.
function Match.view(t: any): any
	local ults = stateOf(t)
	local on = Match.enabled(t)
	local bars = {}
	if on then
		for _, s in t.seats do
			if s.team ~= nil then
				local bar = ults.bars[tostring(s.userId)] or Fill.newBar()
				bars[tostring(s.userId)] =
					{ bar = bar.bar, used = bar.used, ready = Fill.ready(bar) }
			end
		end
	end
	local armed = ults.armed
	return {
		on = on,
		bars = bars,
		armed = if armed
			then {
				by = armed.by,
				id = armed.id,
				stage = armed.stage,
				at = armed.at,
				readyAt = armed.readyAt,
				seq = armed.seq,
				practice = armed.practice,
				pick = if armed.pick then table.clone(armed.pick) else nil,
			}
			else nil,
		pausedUntil = ults.pausedUntil,
		-- A Turn ult still acting for its shooter this turn (Portals): { by, id, pick }.
		kept = if ults.kept
			then {
				by = ults.kept.by,
				id = ults.kept.id,
				pick = if ults.kept.pick then table.clone(ults.kept.pick) else nil,
			}
			else nil,
	}
end

--- The PC opponent's rule (section 4): activate when its bar is full, it may activate now, and
--- it is behind (Fill.behind: its side has more balls left) or its shot finder sees no easy
--- shot (Config.Ults.Pc says which of the two apply).
function Match.pcShouldActivate(t: any, userId: number, easyShot: boolean): boolean
	if not Match.check(t, userId) then
		return false
	end
	local seat = seatOf(t, userId)
	if seat == nil then
		return false
	end
	local ults = stateOf(t)
	local behind = Fill.behind(t.groups or {}, t.state.balls, seat.team, ults.openPotted) > 0
	return (U.Pc.WhenBehind and behind) or (U.Pc.WhenNoEasyShot and not easyShot)
end

--- Sets `userId`'s bar to `n` (clamped to 0..BarMax, whole) for the developer tools. False
--- when ults are off here or the player is not in the game. A bar at MaxPerMatch stays 0.
function Match.setBar(t: any, userId: number, n: number): boolean
	if not Match.enabled(t) or type(n) ~= "number" or n ~= n then
		return false
	end
	local seat = nil
	for _, s in t.seats do
		if s.userId == userId and s.team ~= nil then
			seat = s
		end
	end
	if seat == nil then
		return false
	end
	local bar = barOf(stateOf(t), userId)
	bar.bar = if bar.used >= U.MaxPerMatch then 0 else math.clamp(math.floor(n + 0.5), 0, U.BarMax)
	t.revision += 1
	return true
end

--- Developer tools (`/ultarm`, UltQA's arm): fills the bar and activates as usual (practice in
--- solo), then skips the cutscene wait: the ult is Armed at once and the pause ends.
function Match.devArm(t: any, userId: number, ultId: string, now: number): (boolean, string?)
	local ok, reason
	if t.solo ~= nil then
		ok, reason = Match.practice(t, userId, ultId, now)
	else
		if Match.enabled(t) then
			local bar = barOf(stateOf(t), userId)
			if bar.used < U.MaxPerMatch then
				bar.bar = U.BarMax
			end
		end
		ok, reason = Match.activate(t, userId, ultId, now)
	end
	if not ok then
		return false, reason
	end
	local ults = stateOf(t)
	local armed = ults.armed :: Armed
	if t.deadline ~= nil then
		t.deadline -= armed.readyAt - now -- no wait, so no pause
	end
	armed.readyAt = now
	Match.tick(t, now)
	return true, nil
end

return Match
