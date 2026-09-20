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
		eventListeners: { (Event) -> () },
		-- The sequence number of the shot being replayed, and where the server says the
		-- balls finish, so the table can settle onto the truth when the motion stops.
		seq: number,
		pendingFinal: { number }?,
		pendingChecksum: number?,
	},
	Match
))

function Match.new(p: Placement.Placement, renderer: BallRenderer.BallRenderer?): Match
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local self = setmetatable({
		state = Simulation.newState(geometry, Rack.newGame(geometry)),
		placement = p,
		renderer = renderer,
		shot = nil,
		lastShot = nil,
		eventListeners = {},
		seq = 0,
		pendingFinal = nil,
		pendingChecksum = nil,
	}, Match)
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

--- Listen for simulation events as they happen (audio, effects, rules).
function Match.onEvent(self: Match, listener: (Event) -> ())
	table.insert(self.eventListeners, listener)
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

--- Put all 16 balls back for a new game.
function Match.rerack(self: Match)
	if self.shot then
		return
	end
	self.state.balls = Rack.newGame(self.state.geometry)
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

--- Replay the shot the server has just run. `seed` is the cue ball's state immediately
--- after the strike; `startedAt` is the server clock reading when it began, so a client
--- that joined late or hitched can work out how far in it already is rather than starting
--- the whole shot from the beginning.
function Match.replay(
	self: Match,
	seq: number,
	seed: { vx: number, vy: number, wx: number, wy: number, wz: number },
	startedAt: number,
	final: { number },
	checksum: number
)
	self:ensureCueBall()
	local cue = Simulation.findBall(self.state, 0)
	if cue == nil then
		return
	end
	-- Start from the server's numbers exactly. Nothing here recomputes the strike.
	cue.vx, cue.vy = seed.vx, seed.vy
	cue.wx, cue.wy, cue.wz = seed.wx, seed.wy, seed.wz
	self.state.time = 0
	self.seq = seq
	self.pendingFinal = final
	self.pendingChecksum = checksum
	-- If this arrived late, catch up to where the shot already is instead of replaying it
	-- from the start and finishing several seconds after everyone else.
	local behind = math.max(workspace:GetServerTimeNow() - startedAt, 0)
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
		Ball.stop(b)
	end
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
	self:renderState()
end

local function dispatch(self: Match, ev: Event)
	for _, listener in self.eventListeners do
		listener(ev)
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

	while self.state.time < shot.elapsed and not Simulation.isAtRest(self.state) do
		if shot.steps >= maxSteps then
			shot.capped = true
			for _, b in self.state.balls do
				Ball.stop(b)
				b.falling = false
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
			renderer:step(b, simulated)
			if b.z <= -dropDepth + 1e-6 then
				renderer:sink(b.id)
			end
		end
	end

	local events = shot.events
	while shot.nextEvent <= #events and events[shot.nextEvent].t <= self.state.time do
		dispatch(self, events[shot.nextEvent])
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
	return TableBuilder.toWorld(self.placement, x, y, Config.Balls.RadiusInches + z)
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
