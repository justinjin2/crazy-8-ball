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
-- Roadmap 1.5f makes the server the authority: the inputs come off the wire and the final
-- positions are reconciled against the server's, but the stepping below does not change.

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
		renderer: BallRenderer.BallRenderer,
		-- nil when the table is still; otherwise the shot in progress.
		shot: {
			elapsed: number, -- shot seconds the render clock has asked for so far
			steps: number,
			events: { Event },
			nextEvent: number,
			capped: boolean,
		}?,
		lastShot: Summary?,
		eventListeners: { (Event) -> () },
	},
	Match
))

function Match.new(renderer: BallRenderer.BallRenderer, p: Placement.Placement): Match
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local self = setmetatable({
		state = Simulation.newState(geometry, Rack.newGame(geometry)),
		placement = p,
		renderer = renderer,
		shot = nil,
		lastShot = nil,
		eventListeners = {},
	}, Match)
	self:renderState()
	return self
end

--- Listen for simulation events as they happen (audio, effects, rules).
function Match.onEvent(self: Match, listener: (Event) -> ())
	table.insert(self.eventListeners, listener)
end

function Match.renderState(self: Match)
	for _, b in self.state.balls do
		if b.pocketed then
			self.renderer:setVisible(b.id, false)
		else
			self.renderer:restore(b.id, b.x, b.y)
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

--- Put the cue ball on the head spot if it is off the table (test helper until rules exist).
function Match.ensureCueBall(self: Match)
	local cue = Simulation.findBall(self.state, 0)
	if cue and cue.pocketed then
		cue.pocketed = false
		cue.falling = false
		cue.pocket = nil
		cue.z = 0
		Ball.stop(cue)
		cue.x, cue.y = TableGeometry.headSpot(self.state.geometry)
		self.renderer:restore(0, cue.x, cue.y)
	end
end

--- Strike the cue ball and start stepping the shot. Returns false if one is already running.
function Match.fire(self: Match, shot: Shot): boolean
	if self.shot then
		return false
	end
	self:ensureCueBall()
	local strike = Simulation.strike(self.state, shot)
	self.shot = { elapsed = 0, steps = 0, events = { strike }, nextEvent = 1, capped = false }
	return true
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

	local dropDepth = Config.Table.PocketDropDepthInches
	for _, b in self.state.balls do
		self.renderer:step(b, dt)
		if b.z <= -dropDepth + 1e-6 then
			self.renderer:sink(b.id)
		end
	end

	local events = shot.events
	while shot.nextEvent <= #events and events[shot.nextEvent].t <= self.state.time do
		dispatch(self, events[shot.nextEvent])
		shot.nextEvent += 1
	end

	if shot.capped or Simulation.isAtRest(self.state) then
		finish(self, shot)
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
