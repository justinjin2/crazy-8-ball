--!strict
-- Match: the client's view of one table. It owns a live simulation state and, while a shot
-- is running, steps that state forward a little every rendered frame, handing the balls to
-- the renderer as they move.
--
-- It deliberately does NOT call Simulation.run. That function simulates the whole shot to
-- rest before it returns: up to 9,600 fixed steps of an O(balls^2) search, which is tens of
-- milliseconds on a desktop and several times that on a phone, all of it inside one frame.
-- With twelve tables in a lounge and a shot landing on any of them, that is a visible freeze
-- every break. Stepping forward from the render loop spreads exactly the same work over the
-- time the shot takes anyway (about four steps per frame) and never blocks.
--
-- Stepping live also means the renderer sees real Ball values, including the angular
-- velocity, which is what lets a skidding ball look like it is skidding.
--
-- The server is the authority. A shot does not start here: the inputs go up, the server
-- decides what happened, and what comes back is a SEED (the cue ball's velocity and spin
-- just after the strike) plus the final positions. Every client, including the one that
-- took the shot, replays from that same seed, so nobody sees a different break.
--
-- The seed matters rather than {angle, power} because Cue.strike goes through math.cos,
-- math.sin and a fractional power, none of which are correctly rounded across platforms.
-- See the note at the top of src/server/ShotService.luau.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Placement = require(Shared:WaitForChild("Placement"))
local Physics = Shared:WaitForChild("Physics")
local Ball = require(Physics:WaitForChild("Ball"))
local Cue = require(Physics:WaitForChild("Cue"))
local Rack = require(Physics:WaitForChild("Rack"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableGeometry = require(Physics:WaitForChild("Table"))
local TableBuilder = require(Shared:WaitForChild("TableBuilder"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))

type Shot = Cue.Shot
type State = Simulation.State
type Event = Simulation.Event

-- What a finished shot did, for the log and (later) the rules.
export type Summary = {
	events: { Event },
	duration: number,
	steps: number,
	capped: boolean,
}

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable(
	{} :: {
		state: State,
		rackSeed: number,
		rackConfirmed: boolean,
		pendingRack: { seed: number, positions: { number } }?,
		placement: Placement.Placement,
		-- nil while this table is too far away to be worth drawing. The simulation still
		-- runs; only the parts are gone. See src/client/Lounge.luau.
		renderer: BallRenderer.BallRenderer?,
		-- nil when the table is still; otherwise the shot in progress.
		shot: {
			elapsed: number, -- shot seconds the render clock has asked for so far
			steps: number,
			events: { Event },
			nextEvent: number,
			capped: boolean,
			startedAt: number,
		}?,
		lastShot: Summary?,
		eventListeners: { (Event, number) -> () },
		-- The sequence number of the shot being replayed, and where the server says the
		-- balls finish, so the table can settle onto the truth when the motion stops.
		seq: number,
		epoch: number,
		pendingFinal: { number }?,
		pendingChecksum: number?,
		-- Balls shown as down. A replay marks a ball when its pocket event is dispatched,
		-- not when b.pocketed turns on at the rim a few tenths of a second earlier; at rest
		-- it mirrors the state. `downVersion` goes up whenever this or `assign` changes.
		sunk: { [number]: boolean },
		downVersion: number,
		-- The shot being replayed picks the colors: the groups it produces, and the ball
		-- whose drop reveals them. Cleared once the server's snapshot carries the groups.
		assign: { groups: { [number]: string }, ball: number, index: number }?,
		-- Where the local shooter is holding the cue ball in hand. Snapshots and echoes of
		-- older spots keep arriving while they drag; this is re-applied over them so the
		-- ball never snaps back. It lasts for this turn's Intro and Placement only.
		cueHold: { epoch: number, turnId: number, x: number, y: number }?,
	},
	Match
))

-- The rest state is authoritative: whatever it says is down is shown down.
local function resync(self: Match)
	table.clear(self.sunk)
	for _, b in self.state.balls do
		if b.pocketed then
			self.sunk[b.id] = true
		end
	end
	self.downVersion += 1
end

function Match.new(
	p: Placement.Placement,
	renderer: BallRenderer.BallRenderer?,
	rackSeed: number?
): Match
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local seed = Rack.normalizeSeed(rackSeed)
	local self = setmetatable({
		state = Simulation.newState(geometry, Rack.newGame(geometry, seed)),
		rackSeed = seed,
		rackConfirmed = false,
		pendingRack = nil,
		placement = p,
		renderer = renderer,
		shot = nil,
		lastShot = nil,
		eventListeners = {},
		seq = 0,
		epoch = 0,
		pendingFinal = nil,
		pendingChecksum = nil,
		sunk = {},
		downVersion = 0,
		assign = nil,
		cueHold = nil,
	}, Match)
	resync(self)
	self:renderState()
	return self
end

--- Give this table a renderer and draw its current state. Used when the player walks close
--- enough for the table to be worth drawing.
function Match.attach(self: Match, renderer: BallRenderer.BallRenderer)
	self.renderer = renderer
	self:renderState()
end

--- Drop the renderer. The simulation carries on; only the parts go away.
function Match.detach(self: Match)
	self.renderer = nil
end

--- Listen for simulation events as they happen (audio, effects, rules). The second argument
--- is the event's index in the shot's log, which matches the server's outcome.events index
--- for the same replay. `epoch` and `seq` already name the shot when any event arrives.
function Match.onEvent(self: Match, listener: (Event, number) -> ())
	table.insert(self.eventListeners, listener)
end

--- The groups to show while a shot is being replayed: the ones it assigns, from the moment
--- its assigning ball drops (or the replay ends), or nil to use the snapshot's own.
function Match.revealedGroups(self: Match): { [number]: string }?
	local a = self.assign
	return if a and (self.shot == nil or self.sunk[a.ball]) then a.groups else nil
end

--- A presentation copy of `snapshot` for the HUD and highlights: the pocketed flags are the
--- balls shown down right now, and the groups are revealed as soon as they are decided. The
--- positions are left as the server sent them; nothing presentational reads them.
function Match.view(self: Match, snapshot: any): any
	local v = table.clone(snapshot)
	local packed = table.clone(snapshot.balls)
	for _, b in self.state.balls do
		packed[b.id * 4 + 4] = if self.sunk[b.id] then 1 else 0
	end
	v.balls = packed
	v.groups = self:revealedGroups() or snapshot.groups
	return v
end

function Match.renderState(self: Match)
	local renderer = self.renderer
	if renderer == nil then
		return
	end
	for _, b in self.state.balls do
		if b.pocketed then
			renderer:setVisible(b.id, false)
		else
			renderer:restore(b.id, b.x, b.y)
		end
	end
end

function Match.isBusy(self: Match): boolean
	return self.shot ~= nil
end

--- Apply the server's rack once per seed. Exact positions avoid recomputing its layout.
function Match.applyRack(self: Match, seed: number, positions: { number })
	if self.shot then
		if seed ~= self.rackSeed then
			-- A slow client can still be replaying when the server resets. Apply the new
			-- authoritative rack immediately after that replay, rather than losing it.
			self.pendingRack = { seed = seed, positions = table.clone(positions) }
		end
		return
	end
	if seed == self.rackSeed and self.rackConfirmed then
		return
	end
	if seed == self.rackSeed and self.seq > 0 then
		self.rackConfirmed = true
		return -- a delayed initial rack snapshot must not overwrite a replayed shot
	end
	local balls = Rack.newGame(self.state.geometry, seed)
	if #positions ~= #balls * 2 then
		return
	end
	for i, ball in balls do
		ball.x, ball.y = positions[2 * i - 1], positions[2 * i]
	end
	self.rackSeed, self.rackConfirmed = seed, true
	self.state.balls, self.state.time, self.state.overrides = balls, 0, nil
	resync(self)
	self:renderState()
end

--- The cue ball's current state (nil if somehow missing).
function Match.findCueBall(self: Match)
	return Simulation.findBall(self.state, 0)
end

--- Put the cue ball on the head spot if it is off the table. The server does exactly the
--- same thing to its own copy after every shot (ShotService), through the same helper, so
--- the two cannot drift apart.
function Match.ensureCueBall(self: Match)
	if Simulation.respotCueBall(self.state) then
		local cue = Simulation.findBall(self.state, 0)
		if cue and self.renderer then
			self.renderer:restore(0, cue.x, cue.y)
		end
	end
end

--- Put the cue ball in hand at (x, y) and redraw only it: a drag moves it every frame, and
--- redrawing all sixteen balls for that would be waste.
function Match.setCue(self: Match, x: number, y: number)
	local cue = Simulation.findBall(self.state, 0)
	if cue == nil then
		return
	end
	Ball.stop(cue)
	cue.x, cue.y, cue.z, cue.vz = x, y, 0, 0
	cue.pocketed, cue.falling, cue.pocket, cue.tip = false, false, nil, nil
	if self.renderer then
		self.renderer:restore(0, x, y)
	end
end

--- The local shooter moved the cue ball in hand: show it there now, and keep showing it
--- there over any snapshot for the same turn until the hold is released.
function Match.holdCue(self: Match, epoch: number, turnId: number, x: number, y: number)
	self.cueHold = { epoch = epoch, turnId = turnId, x = x, y = y }
	self:setCue(x, y)
end

function Match.releaseCue(self: Match)
	self.cueHold = nil
end

-- Install a complete authoritative state, including on a late join or new rack.
function Match.applyBalls(self: Match, packed: { number })
	if #packed ~= #self.state.balls * 4 then
		return
	end
	for _, b in self.state.balls do
		local i = b.id * 4
		b.x, b.y, b.z, b.pocketed = packed[i + 1], packed[i + 2], packed[i + 3], packed[i + 4] == 1
		b.falling, b.tip, b.pocket, b.offTable = false, nil, nil, false
		Ball.stop(b)
	end
	local hold = self.cueHold
	local cue = Simulation.findBall(self.state, 0)
	if hold and cue then
		cue.x, cue.y, cue.z, cue.pocketed = hold.x, hold.y, 0, false
	end
	self.state.time, self.state.overrides = 0, nil
	self:renderState()
	resync(self)
end

function Match.receive(self: Match, msg: any)
	if msg.epoch < self.epoch or (msg.epoch == self.epoch and msg.seq <= self.seq) then
		return
	end
	if msg.epoch ~= self.epoch then
		self.epoch, self.seq = msg.epoch, 0
	end
	self.cueHold = nil -- the shot starts from the server's spot
	self.shot = nil
	self:applyBalls(msg.start)
	self:replay(msg.seq, msg.seed, msg.startedAt, msg.final, msg.checksum, msg.overrides)
	if self.seq == msg.seq then
		self.assign = msg.assign
		self.downVersion += 1
	end
end

function Match.snapshot(self: Match, snapshot: any)
	if snapshot.epoch < self.epoch then
		return
	end
	-- A held cue ball outlives only its own turn's placement: the snapshot that ends it
	-- installs the server's spot.
	local hold = self.cueHold
	if
		hold
		and not (
			hold.epoch == snapshot.epoch
			and hold.turnId == snapshot.turnId
			and snapshot.ballInHand == true
			and (snapshot.phase == "Intro" or snapshot.phase == "Placement")
		)
	then
		self.cueHold = nil
	end
	if snapshot.epoch ~= self.epoch then
		self.epoch, self.seq = snapshot.epoch, 0
		self.shot = nil
		self.pendingFinal = nil
		self.pendingChecksum = nil
		self.pendingRack = nil
		self.assign = nil
	end
	self.rackSeed, self.rackConfirmed = snapshot.rackSeed, true
	if snapshot.shot then
		self:receive(snapshot.shot)
	elseif snapshot.shotSeq >= self.seq then
		-- The server's next phase always wins over a slow client's replay; no player's
		-- clock depends on a spectator completing an animation.
		self.shot = nil
		self.pendingFinal = nil
		self.pendingChecksum = nil
		self.seq = snapshot.shotSeq
		self.assign = nil -- the snapshot's own groups now include any assignment
		self:applyBalls(snapshot.balls)
	end
end

--- Replay the shot the server has just run. `seed` is the cue ball's state immediately
--- after the strike; `startedAt` is the server clock reading when it began, so a client
--- that joined late or hitched can work out how far in it already is rather than starting
--- the whole shot from the beginning.
function Match.replay(
	self: Match,
	seq: number,
	seed: { vx: number, vy: number, vz: number?, wx: number, wy: number, wz: number },
	startedAt: number,
	final: { number },
	checksum: number,
	overrides: Simulation.Overrides?
)
	if seq <= self.seq then
		return
	end
	local cue = Simulation.findBall(self.state, 0)
	if cue == nil then
		return
	end
	-- Start from the server's numbers exactly. Nothing here recomputes the strike.
	cue.vx, cue.vy, cue.vz, cue.z = seed.vx, seed.vy, seed.vz or 0, 0
	cue.wx, cue.wy, cue.wz = seed.wx, seed.wy, seed.wz
	self.state.time = 0
	self.state.overrides = if overrides then table.clone(overrides) else nil
	self.seq = seq
	self.pendingFinal = final
	self.pendingChecksum = checksum
	-- If this arrived late, catch up to where the shot already is instead of replaying it
	-- from the start and finishing several seconds after everyone else.
	local behind =
		math.clamp(workspace:GetServerTimeNow() - startedAt, 0, Config.Physics.MaxShotSeconds)
	self.shot = {
		elapsed = behind,
		steps = 0,
		events = { { t = 0, type = "cueStrike", ball = 0, speed = Ball.speed(cue) } },
		nextEvent = 1,
		capped = false,
		startedAt = startedAt,
	}
end

--- Settle onto the server's final positions. Called when the replay stops moving.
function Match.reconcile(self: Match)
	self.state.overrides = nil
	local final = self.pendingFinal
	self.pendingFinal = nil
	if final == nil then
		return
	end
	-- Fingerprint the REPLAY before the server's answer is written over it. Hashing after
	-- the loop below hashes the numbers just copied out of `final`, which always matches
	-- and made this check structurally incapable of failing.
	local mine = Simulation.checksum(self.state.balls)
	local drift = 0
	for i, b in self.state.balls do
		local x, y, z = final[4 * i - 3], final[4 * i - 2], final[4 * i - 1]
		if x == nil then
			break
		end
		local dx, dy = b.x - x, b.y - y
		drift = math.max(drift, math.sqrt(dx * dx + dy * dy))
		b.x, b.y, b.z = x, y, z
		b.pocketed = final[4 * i] == 1
		b.offTable = b.offTable and b.pocketed
		b.falling = false
		b.tip = nil
		Ball.stop(b)
	end
	resync(self)
	-- The state the guideline and the next shot are built from must be the server's, not
	-- this client's replay of it, or the aim would quietly lie.
	if
		Config.Debug.LogChecksumMismatch
		and self.pendingChecksum
		and mine ~= self.pendingChecksum
	then
		warn(
			("[8ball] replay drifted from the server by %.3f in (replay %d, server %d)"):format(
				drift,
				mine,
				self.pendingChecksum
			)
		)
	end
	self.pendingChecksum = nil
	local pending = self.pendingRack
	self.pendingRack = nil
	if pending then
		self:applyRack(pending.seed, pending.positions)
	else
		self:renderState()
	end
end

-- `index` is the event's place in the shot's log. A pocket marks its ball down BEFORE the
-- listeners run, so anything they refresh already shows it.
local function dispatch(self: Match, ev: Event, index: number)
	if ev.type == "pocket" and not self.sunk[ev.ball] then
		self.sunk[ev.ball] = true
		self.downVersion += 1
	elseif ev.type == "offTable" then
		-- Out of play, but not pocketed: the server puts it back (or it is the cue ball, in
		-- hand). Only the drawn cue's clearance needs to know the table changed.
		self.downVersion += 1
	end
	for _, listener in self.eventListeners do
		listener(ev, index)
	end
end

local function finish(self: Match, shot: any)
	self.lastShot = {
		events = shot.events,
		duration = self.state.time,
		steps = shot.steps,
		capped = shot.capped,
	}
	self.shot = nil
	if Config.Debug.LogPlayback then
		print(
			("[8ball] shot done: %.2fs of play in %d steps%s"):format(
				self.state.time,
				shot.steps,
				if shot.capped then " (capped)" else ""
			)
		)
	end
end

--- Advance the shot by dt seconds of wall time. Returns true while a shot is running.
function Match.update(self: Match, dt: number): boolean
	local shot = self.shot
	if not shot then
		return false
	end
	local P = Config.Physics
	-- Never simulate more than a short slice per frame: a hitch must not fast-forward the
	-- shot, and one frame must never be asked to do unbounded work.
	shot.elapsed += math.min(dt, Config.Debug.MaxPlaybackStepSeconds)
	local maxSteps = math.floor(P.MaxShotSeconds / P.FixedStep)
	local timeBefore = self.state.time
	local frameSteps = 0

	while
		self.state.time < shot.elapsed
		and not Simulation.isAtRest(self.state)
		and frameSteps < Config.Multiplayer.MaxReplayStepsPerFrame
	do
		frameSteps += 1
		if shot.steps >= maxSteps then
			shot.capped = true
			for _, b in self.state.balls do
				Ball.stop(b)
				b.falling = false
				b.tip = nil
			end
			break
		end
		Simulation.step(self.state, P.FixedStep, shot.events)
		shot.steps += 1
	end

	local renderer = self.renderer
	if renderer then
		-- How much SHOT time passed, which is not the render dt: a long frame is capped at
		-- MaxPlaybackStepSeconds, and the loop above overshoots by up to one fixed step.
		-- Turning the balls by the render dt instead would over-rotate them on any hitch,
		-- so the roll would drift out of step with the travel.
		local simulated = self.state.time - timeBefore
		local dropDepth = Config.Table.PocketDropDepthInches
		for _, b in self.state.balls do
			if b.offTable then
				renderer:flyOff(b)
			end
			renderer:step(b, simulated)
			if b.z <= -dropDepth + 1e-6 then
				renderer:sink(b.id, b.x, b.y)
			end
		end
	end

	local events = shot.events
	while shot.nextEvent <= #events and events[shot.nextEvent].t <= self.state.time do
		dispatch(self, events[shot.nextEvent], shot.nextEvent)
		shot.nextEvent += 1
	end

	if shot.capped or Simulation.isAtRest(self.state) then
		finish(self, shot)
		self:reconcile()
		return false
	end
	return true
end

--- Speed of the cue ball right now, for the debug readout.
function Match.cueBallSpeedNow(self: Match): number
	local cue = Simulation.findBall(self.state, 0)
	return if cue then Ball.speed(cue) else 0
end

--- World position of the cue ball right now.
function Match.cueBallWorldNow(self: Match): Vector3
	local cue = Simulation.findBall(self.state, 0)
	local x, y, z = 0, 0, 0
	if cue then
		x, y, z = cue.x, cue.y, cue.z
	end
	return TableBuilder.toWorld(self.placement, x, y, Config.Balls.RenderRadiusInches + z)
end

--- Number of balls still on the table (excluding the cue ball).
function Match.ballsRemaining(self: Match): number
	local n = 0
	for _, b in self.state.balls do
		if b.id ~= 0 and not b.pocketed then
			n += 1
		end
	end
	return n
end

return Match
