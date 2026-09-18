--!strict
-- Match: client-side glue for the solo MVP. Owns the current table state, runs a shot
-- through the simulation, and plays the recorded frames back over time to the renderer.
-- Milestone 8 grows this into turns and rules; the shot boundary stays the same.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Physics = Shared:WaitForChild("Physics")
local Ball = require(Physics:WaitForChild("Ball"))
local Cue = require(Physics:WaitForChild("Cue"))
local Simulation = require(Physics:WaitForChild("Simulation"))
local TableGeometry = require(Physics:WaitForChild("Table"))
local BallRenderer = require(script.Parent:WaitForChild("BallRenderer"))

type Shot = Cue.Shot
type ShotResult = Simulation.ShotResult
type State = Simulation.State

local Match = {}
Match.__index = Match

export type Match = typeof(setmetatable(
	{} :: {
		state: State,
		renderer: BallRenderer.BallRenderer,
		playback: { result: ShotResult, elapsed: number, frameIndex: number }?,
		lastResult: ShotResult?,
	},
	Match
))

function Match.new(renderer: BallRenderer.BallRenderer): Match
	local geometry = TableGeometry.build({ pocketsOpen = false })
	local balls = { Ball.new(0, -Config.Table.LengthInches / 4, 0) }
	local self = setmetatable({
		state = Simulation.newState(geometry, balls),
		renderer = renderer,
		playback = nil,
		lastResult = nil,
	}, Match)
	self:renderState()
	return self
end

function Match.renderState(self: Match)
	for _, b in self.state.balls do
		self.renderer:place(b.id, b.x, b.y)
		self.renderer:setVisible(b.id, not b.pocketed)
	end
end

function Match.isBusy(self: Match): boolean
	return self.playback ~= nil
end

--- Run the shot instantly and start playing it back.
function Match.fire(self: Match, shot: Shot): ShotResult?
	if self.playback then
		return nil
	end
	local result = Simulation.run(self.state, shot)
	self.lastResult = result
	self.playback = { result = result, elapsed = 0, frameIndex = 1 }
	if Config.Debug.LogEvents then
		for _, ev in result.events do
			print(("[8ball] %.3fs %s ball %d speed %.1f"):format(ev.t, ev.type, ev.ball, ev.speed))
		end
	end
	return result
end

--- Advance playback by dt seconds of wall time. Returns true while a shot is playing.
function Match.update(self: Match, dt: number): boolean
	local playback = self.playback
	if not playback then
		return false
	end
	playback.elapsed += dt
	local frames = playback.result.frames
	local index = math.floor(playback.elapsed / Config.Physics.FixedStep) + 1
	if index >= #frames then
		self.state.balls = Ball.cloneList(playback.result.finalBalls)
		self.playback = nil
		self:renderState()
		return false
	end
	playback.frameIndex = index
	local positions = frames[index].positions
	for i, b in self.state.balls do
		self.renderer:place(b.id, positions[2 * i - 1], positions[2 * i])
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

return Match
