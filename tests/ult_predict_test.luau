--!strict
-- Eagle's Eye's full path (src/shared/Ults/Predict.luau, docs/prompts/ABILITIES_PROMPT.md 7.2)
-- against the shot the server actually settles: for many realistic tables (the value
-- harness's fresh, mid and late states) and shots at every power, spin and elevation, the drawn
-- path must end exactly where the settled shot leaves the cue ball and the first ball it hits,
-- or in the same pocket, and name the same first ball.

local H = require("./harness")
local V = require("./ult_value")

local Config = H.require("Config")
local Ball = H.require("Physics.Ball")
local Simulation = H.require("Physics.Simulation")
local ShotInput = H.require("ShotInput")
local Predict = H.require("Ults.Predict")

local geometry = V.geometry

local function check(condition: any, message: string)
	if not condition then
		error(message, 2)
	end
end

-- The server's pipeline (MatchEngine.acceptShot): validate, strike, arm, quantise, settle.
local function settle(balls: { any }, payload: any): (any, any)
	local shot = assert(ShotInput.validate(payload, nil))
	local sim = Simulation.newState(geometry, Ball.cloneList(balls))
	local strike = Simulation.strike(sim, shot)
	Simulation.armEffect(sim, "EaglesEye", {}, nil)
	local cue = assert(Simulation.findBall(sim, 0))
	ShotInput.quantiseSeed(cue)
	return sim, Simulation.settle(sim, { strike })
end

local function lastPoint(track: any): (number, number)
	local n = #track.points
	return track.points[n - 1], track.points[n]
end

-- The drawn track agrees with the settled ball: the same pocket, or the same resting spot to
-- the bit.
local function agrees(track: any, ball: any, what: string)
	if ball.pocketed then
		check(
			track.pocket == ball.pocket,
			("%s: pocket %s drawn, %s settled"):format(
				what,
				tostring(track.pocket),
				tostring(ball.pocket)
			)
		)
	else
		check(track.pocket == nil, what .. ": drawn into a pocket it never reached")
		local x, y = lastPoint(track)
		check(
			x == ball.x and y == ball.y,
			("%s: drawn to (%.6f, %.6f), settled at (%.6f, %.6f)"):format(
				what,
				x,
				y,
				ball.x,
				ball.y
			)
		)
	end
end

local function shots(seed: number): { any }
	local r = V.rng(seed)
	local out = {}
	for _ = 1, 4 do
		table.insert(out, {
			angle = V.uniform(r) * 2 * math.pi,
			power = 0.15 + V.uniform(r) * 0.85,
			spin = { x = (V.uniform(r) * 2 - 1) * 0.8, y = (V.uniform(r) * 2 - 1) * 0.8 },
			elevation = Config.Cue.CueElevationDegrees
				+ math.floor(V.uniform(r) * 3) * Config.Cue.ElevationStepDegrees,
		})
	end
	return out
end

local tests = {}

function tests.the_drawn_path_ends_where_the_settled_shot_does()
	local states = V.states(45, 7)
	local count, withObject, cueDrops, objectDrops = 0, 0, 0, 0
	for i, ts in states do
		-- Aim straight at a ball too, so most shots make a first contact.
		local list = shots(1000 + i)
		local cue = assert(V.findBall(ts.balls, 0))
		for _, b in ts.balls do
			if b.id ~= 0 and not b.pocketed then
				table.insert(list, {
					angle = math.atan2(b.y - cue.y, b.x - cue.x),
					power = 0.55,
					spin = { x = 0, y = -0.3 },
				})
				break
			end
		end
		for _, payload in list do
			local sim, outcome = settle(ts.balls, payload)
			if outcome.capped then
				continue
			end
			local path = assert(Predict.path(Simulation.newState(geometry, ts.balls), payload))
			count += 1
			check(not path.capped, "a settled shot is never capped in the prediction")
			check(
				path.object == outcome.firstContact,
				("first ball: %s drawn, %s settled"):format(
					tostring(path.object),
					tostring(outcome.firstContact)
				)
			)
			local settledCue = assert(Simulation.findBall(sim, 0))
			agrees(path.cue, settledCue, "cue ball")
			if settledCue.pocketed then
				cueDrops += 1
			end
			if path.object then
				withObject += 1
				local b = assert(Simulation.findBall(sim, path.object))
				agrees(assert(path.objectTrack, "the object track"), b, "ball " .. path.object)
				if b.pocketed then
					objectDrops += 1
				end
			end
		end
	end
	check(count >= 200, "enough shots compared: " .. count)
	check(withObject >= count / 2, "most shots hit a ball: " .. withObject)
	check(objectDrops >= 10, "some object balls drop: " .. objectDrops)
	print(
		("        %d shots, %d with a first ball (%d dropped), %d scratches: all match"):format(
			count,
			withObject,
			objectDrops,
			cueDrops
		)
	)
end

function tests.bounces_are_marked_and_the_path_starts_at_the_cue_ball()
	-- The cue ball alone, hit hard along the table: it comes off cushions several times.
	local balls = { Ball.new(0, -30, 5) }
	local path = assert(Predict.path(Simulation.newState(geometry, balls), {
		angle = 0.3,
		power = 1,
		spin = { x = 0, y = 0 },
	}))
	check(path.cue.points[1] == -30 and path.cue.points[2] == 5, "starts at the cue ball")
	check(#path.cue.bounces >= 4, "cushion bounces marked: " .. #path.cue.bounces / 2)
	check(path.object == nil and path.objectTrack == nil, "no object ball")
	-- Every bounce is a point of the path too (the corners are exact).
	for k = 1, #path.cue.bounces, 2 do
		local found = false
		for j = 1, #path.cue.points, 2 do
			if
				path.cue.points[j] == path.cue.bounces[k]
				and path.cue.points[j + 1] == path.cue.bounces[k + 1]
			then
				found = true
				break
			end
		end
		check(found, "bounce " .. (k + 1) / 2 .. " is on the path")
	end
end

function tests.max_rails_cuts_the_drawn_path()
	local saved = Config.Ults.EaglesEye.MaxRails
	Config.Ults.EaglesEye.MaxRails = 2
	local ok, err = pcall(function()
		local balls = { Ball.new(0, -30, 5) }
		local path = assert(Predict.path(Simulation.newState(geometry, balls), {
			angle = 0.3,
			power = 1,
			spin = { x = 0, y = 0 },
		}))
		check(#path.cue.bounces == 4, "two bounces kept")
		check(path.cue.cut, "marked as cut")
		local x, y = lastPoint(path.cue)
		check(
			x == path.cue.bounces[3] and y == path.cue.bounces[4],
			"the path ends at the second bounce"
		)
	end)
	Config.Ults.EaglesEye.MaxRails = saved
	if not ok then
		error(err, 0)
	end
end

function tests.a_refused_payload_predicts_nothing()
	local s = Simulation.newState(geometry, { Ball.new(0, 0, 0) })
	check(Predict.path(s, { angle = 0, power = 2 }) == nil, "power out of range")
	check(Predict.path(s, { angle = 0 / 0, power = 0.5 }) == nil, "angle not finite")
	check(
		Predict.path(Simulation.newState(geometry, {}), { angle = 0, power = 0.5 }) == nil,
		"no cue ball"
	)
end

function tests.a_job_split_over_frames_gives_the_same_path()
	local ts = V.states(1, 3)[1]
	local payload = { angle = 1.1, power = 0.7, spin = { x = 0.2, y = 0.3 } }
	local whole = assert(Predict.path(Simulation.newState(geometry, ts.balls), payload))
	local job = assert(Predict.new(Simulation.newState(geometry, ts.balls), payload))
	local frames = 0
	while not job:advance(37) do
		frames += 1
	end
	check(frames > 3, "it took several frames")
	local a, b = whole.cue.points, job.path.cue.points
	check(#a == #b, "same number of points")
	for i = 1, #a do
		check(a[i] == b[i], "same point " .. i)
	end
end

return tests
