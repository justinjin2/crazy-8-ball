--!strict
-- Predict: Eagle's Eye's full path (docs/prompts/ABILITIES_PROMPT.md 7.2). The shot the aim
-- would make, run through the real simulation exactly as the server runs it (ShotInput's
-- validation, the strike, the seed quantised in place, then fixed steps), recording what the
-- guideline draws: the cue ball's path through every cushion until it stops or drops, and the
-- first object ball it hits, from that contact to rest or a pocket. Only those two balls are
-- drawn, however many the shot then moves.
--
-- It runs to rest like the server (a ball that stopped can still be knocked on). A job runs a
-- bounded number of steps at a time (`advance`), so the client can spread one prediction over
-- several frames while aiming on a phone; `Predict.path` runs one to the end.
-- Pure Luau like Physics: no Instances, no clocks, no randomness. The prediction and the
-- server's settle are the same arithmetic on the same numbers, so they agree to the bit
-- (tests/ult_predict_test.luau).

local Config = require(script.Parent.Parent.Config)
local Simulation = require(script.Parent.Parent.Physics.Simulation)
local ShotInput = require(script.Parent.Parent.ShotInput)

local E = Config.Ults.EaglesEye

local Predict = {}

-- One drawn ball's path: flat x, y pairs (inches, table space), its cushion bounces (the
-- ball's centre at each hit), and where it ended.
export type Track = {
	points: { number },
	bounces: { number },
	pocket: number?, -- the pocket it dropped into
	cut: boolean, -- stopped drawing at MaxRails (the path goes on past the last point)
}

export type Path = {
	cue: Track,
	object: number?, -- the first ball the cue ball hit, if it hit one
	objectTrack: Track?,
	capped: boolean, -- the shot ran past MaxShotSeconds (the server refuses such a shot)
}

export type Job = {
	state: any,
	path: Path,
	done: boolean,
	steps: number,
	advance: (self: Job, maxSteps: number) -> boolean,
}

local function newTrack(x: number, y: number): Track
	return { points = { x, y }, bounces = {}, pocket = nil, cut = false }
end

local function push(track: Track, x: number, y: number)
	local n = #track.points
	if n >= 2 and track.points[n - 1] == x and track.points[n] == y then
		return -- at rest: no repeated points
	end
	if not track.cut and track.pocket == nil then
		table.insert(track.points, x)
		table.insert(track.points, y)
	end
end

-- One fixed step's events for a drawn ball: its cushion bounces (cut at MaxRails), its drop.
local function note(track: Track, id: number, ev: any)
	if ev.ball ~= id or track.cut or track.pocket ~= nil then
		return
	end
	if ev.type == "railHit" and ev.x and ev.y then
		push(track, ev.x, ev.y)
		table.insert(track.bounces, ev.x)
		table.insert(track.bounces, ev.y)
		if E.MaxRails and #track.bounces / 2 >= E.MaxRails then
			track.cut = true
		end
	elseif ev.type == "pocket" then
		track.pocket = ev.other
	end
end

local function advance(self: Job, maxSteps: number): boolean
	if self.done then
		return true
	end
	local state, path = self.state, self.path
	local dt = Config.Physics.FixedStep
	local maxSteps_ = math.max(1, maxSteps)
	local cap = math.floor(Config.Physics.MaxShotSeconds / dt + 0.5)
	for _ = 1, maxSteps_ do
		if Simulation.isAtRest(state) then
			self.done = true
			break
		end
		if self.steps >= cap then
			path.capped = true
			self.done = true
			break
		end
		local events = {}
		Simulation.step(state, dt, events)
		self.steps += 1
		local cue = Simulation.findBall(state, 0)
		for _, ev in events do
			if path.object == nil and ev.type == "ballHit" and (ev.ball == 0 or ev.other == 0) then
				local id = if ev.ball == 0 then ev.other else ev.ball
				local hit = if id then Simulation.findBall(state, id) else nil
				if hit then
					path.object = id
					-- The object ball's path starts where it was struck: its centre this step,
					-- walked back along its new heading to the moment of contact.
					local back = state.time - ev.t
					path.objectTrack = newTrack(hit.x - hit.vx * back, hit.y - hit.vy * back)
					if cue then
						push(path.cue, cue.x - cue.vx * back, cue.y - cue.vy * back)
					end
				end
			end
			note(path.cue, 0, ev)
			if path.object and path.objectTrack then
				note(path.objectTrack, path.object, ev)
			end
		end
		-- The curve between events, sampled every SampleSteps steps.
		if self.steps % E.SampleSteps == 0 then
			if cue and not cue.pocketed then
				push(path.cue, cue.x, cue.y)
			end
			if path.object and path.objectTrack then
				local b = Simulation.findBall(state, path.object)
				if b and not b.pocketed then
					push(path.objectTrack, b.x, b.y)
				end
			end
		end
	end
	if self.done then
		-- The resting spots (the last sample may be a few steps short of them).
		local cue = Simulation.findBall(state, 0)
		if cue and not cue.pocketed then
			push(path.cue, cue.x, cue.y)
		end
		if path.object and path.objectTrack then
			local b = Simulation.findBall(state, path.object)
			if b and not b.pocketed then
				push(path.objectTrack, b.x, b.y)
			end
		end
	end
	return self.done
end

--- A prediction job for the shot `payload` (the ShotFired fields: angle, power, spin,
--- elevation) from `table` (a Simulation state: geometry and the balls at rest; never
--- changed). Nil when the payload would be refused, or there is no cue ball on the table.
function Predict.new(table_: any, payload: any): Job?
	local shot = ShotInput.validate(payload, nil)
	if shot == nil then
		return nil
	end
	local state = Simulation.newState(table_.geometry, Simulation.cloneState(table_).balls)
	local cue = Simulation.findBall(state, 0)
	if cue == nil or cue.pocketed then
		return nil
	end
	local x, y = cue.x, cue.y
	Simulation.strike(state, shot)
	ShotInput.quantiseSeed(cue)
	local job: Job = {
		state = state,
		path = { cue = newTrack(x, y), object = nil, objectTrack = nil, capped = false },
		done = false,
		steps = 0,
		advance = advance,
	}
	return job
end

--- The whole prediction at once (tests, or a fast device).
function Predict.path(table_: any, payload: any): Path?
	local job = Predict.new(table_, payload)
	if job == nil then
		return nil
	end
	local done = false
	repeat
		done = job:advance(4096)
	until done
	return job.path
end

return Predict
