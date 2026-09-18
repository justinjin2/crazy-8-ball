--!strict
-- Match: client-side glue for the solo MVP. Owns the current table state, runs a shot
-- through the simulation, and plays the recorded frames back over time to the renderer,
-- firing each recorded event (rail hit, ball hit, pocket) at its moment so audio and
-- effects can react. Milestone 8 grows this into turns and rules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Physics = Shared:WaitForChild("Physics")
local Ball = require(Physics:WaitForChild("Ball"))
local Cue = require(Physics:WaitForChild("Cue"))
local Rack = require(Physics:WaitForChild("Rack"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableGeometry = require(Physics:WaitForChild("Table"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))

type Shot = Cue.Shot
type ShotResult = Simulation.ShotResult
type State = Simulation.State
type Event = Simulation.Event

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable(
	{} :: {
		state: State,
		renderer: BallRenderer.BallRenderer,
		playback: {
			result: ShotResult,
			elapsed: number,
			frameIndex: number,
			nextEvent: number,
			wall: number,
			maxDt: number,
		}?,
		lastResult: ShotResult?,
		eventListeners: { (Event) -> () },
	},
	Match
))

function Match.new(renderer: BallRenderer.BallRenderer): Match
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local self = setmetatable({
		state = Simulation.newState(geometry, Rack.newGame(geometry)),
		renderer = renderer,
		playback = nil,
		lastResult = nil,
		eventListeners = {},
	}, Match)
	self:renderState()
	return self
end

--- Listen for simulation events as they play back (audio, effects, rules).
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
	return self.playback ~= nil
end

--- Put all 16 balls back for a new game.
function Match.rerack(self: Match)
	if self.playback then
		return
	end
	self.state.balls = Rack.newGame(self.state.geometry)
	self:renderState()
end

--- Put the cue ball on the head spot if it is off the table (test helper until rules exist).
function Match.ensureCueBall(self: Match)
	local cue = Simulation.findBall(self.state, 0)
	if cue and cue.pocketed then
		cue.pocketed = false
		Ball.stop(cue)
		cue.x, cue.y = TableGeometry.headSpot(self.state.geometry)
		self.renderer:restore(0, cue.x, cue.y)
	end
end

--- Run the shot instantly and start playing it back.
function Match.fire(self: Match, shot: Shot): ShotResult?
	if self.playback then
		return nil
	end
	self:ensureCueBall()
	local result = Simulation.run(self.state, shot)
	self.lastResult = result
	self.playback =
		{ result = result, elapsed = 0, frameIndex = 1, nextEvent = 1, wall = 0, maxDt = 0 }
	if Config.Debug.LogEvents then
		for _, ev in result.events do
			print(("[8ball] %.3fs %s ball %d speed %.1f"):format(ev.t, ev.type, ev.ball, ev.speed))
		end
	end
	return result
end

local function dispatch(self: Match, ev: Event)
	if ev.type == "pocket" then
		local pocket = self.state.geometry.pockets[ev.other or 0]
		if pocket then
			self.renderer:sink(ev.ball, pocket.x, pocket.y)
		end
	end
	for _, listener in self.eventListeners do
		listener(ev)
	end
end

--- Advance playback by dt seconds of wall time. Returns true while a shot is playing.
function Match.update(self: Match, dt: number): boolean
	local playback = self.playback
	if not playback then
		return false
	end
	-- Never advance more than a short step per frame: a hitch (or the first frame after a
	-- long simulation) must not skip the whole shot.
	local step = math.min(dt, Config.Debug.MaxPlaybackStepSeconds)
	playback.elapsed += step
	playback.wall += dt
	if dt > playback.maxDt then
		playback.maxDt = dt
	end
	local frames = playback.result.frames
	local events = playback.result.events
	local index = math.floor(playback.elapsed / Config.Physics.FixedStep) + 1
	local finished = index >= #frames
	if finished then
		index = #frames
	end
	playback.frameIndex = index
	local frameTime = frames[index].t
	local positions = frames[index].positions
	for i, b in self.state.balls do
		self.renderer:place(b.id, positions[2 * i - 1], positions[2 * i])
	end
	while playback.nextEvent <= #events and events[playback.nextEvent].t <= frameTime do
		dispatch(self, events[playback.nextEvent])
		playback.nextEvent += 1
	end
	if finished then
		self.state.balls = Ball.cloneList(playback.result.finalBalls)
		self.playback = nil
		if Config.Debug.LogPlayback then
			print(
				("[8ball] playback done: %.2fs of shot in %.2fs wall, longest frame %.3fs"):format(
					frameTime,
					playback.wall,
					playback.maxDt
				)
			)
		end
		return false
	end
	return true
end

--- Speed of the cue ball at the current playback frame, for the debug readout.
function Match.cueBallSpeedNow(self: Match): number
	local playback = self.playback
	if not playback then
		return 0
	end
	local frames = playback.result.frames
	local i = playback.frameIndex
	if i < 2 then
		return 0
	end
	local a, b = frames[i - 1].positions, frames[i].positions
	local dx, dy = b[1] - a[1], b[2] - a[2]
	return math.sqrt(dx * dx + dy * dy) / Config.Physics.FixedStep
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
