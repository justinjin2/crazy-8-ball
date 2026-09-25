--!strict
-- AimStream tests: the live aim's wire format and send policy.
--
-- The broadcast comes off the network, so a malformed group must be skipped without taking
-- the rest of the batch with it. The send policy is what keeps a resting thumb free and a
-- let-go instant; both are easy to break with one comparison the wrong way round.

local H = require("./harness")

local function setup()
	return H.require("Config"), H.require("AimStream")
end

-- Every row a batch holds, the way a watcher reads it.
local function readAll(AimStream: any, batch: { any }): { any }
	local rows = {}
	for i = 1, #batch, AimStream.Stride do
		local row = AimStream.read(batch, i)
		if row then
			table.insert(rows, row)
		end
	end
	return rows
end

return {
	["a row packs and reads back, seven values a table"] = function()
		local Config, AimStream = setup()
		H.expect(AimStream.Stride == 7, "stride")
		local batch = {}
		AimStream.pack(batch, 1, 111, 0.25, -12.5, 3.75, 0.5, 45)
		AimStream.pack(batch, 3, 333, 6.1, 40, -20, 0, 4)
		H.expect(#batch == 14, "two rows of seven")
		local rows = readAll(AimStream, batch)
		H.expect(#rows == 2, "both read back")
		local a, b = rows[1], rows[2]
		H.expect(a.id == 1 and a.by == 111 and a.angle == 0.25, "first row")
		H.expect(a.x == -12.5 and a.y == 3.75 and a.pull == 0.5, "first row, cue and pull")
		H.expect(b.id == 3 and b.by == 333 and b.angle == 6.1, "second row")
		H.expect(b.x == 40 and b.y == -20 and b.pull == 0, "second row, cue and pull")
		H.expect(a.elevation == 45 and b.elevation == 4, "cue angles")
		local wild = {}
		AimStream.pack(wild, 1, 1, 0, 0, 0, 0, 999.4)
		H.expect(
			(AimStream.read(wild, 1) :: any).elevation == Config.Cue.MaxElevationDegrees,
			"an angle off the end is clamped on read"
		)
		H.expect(Config.Aim.PullSteps == 50, "pull steps")
	end,

	["a malformed group is skipped and the rest are kept"] = function()
		local _, AimStream = setup()
		local batch: { any } = {}
		AimStream.pack(batch, 1, 11, 0.1, 0, 0, 0.2, 4)
		AimStream.pack(batch, 2, 22, 0.2, 0, 0, 0.4, 4)
		AimStream.pack(batch, 3, 33, 0.3, 0, 0, 0.6, 4)
		AimStream.pack(batch, 4, 44, 0.4, 0, 0, 0.8, 4)
		batch[1] = "1" -- a string id
		batch[10] = 0 / 0 -- a NaN angle
		batch[20] = math.huge -- an infinite pull
		table.insert(batch, 5) -- a short tail: the start of a sixth row
		table.insert(batch, 55)
		local rows = readAll(AimStream, batch)
		H.expect(#rows == 1 and rows[1].id == 4, ("kept %d rows"):format(#rows))
		H.expect(AimStream.read(batch, 29) == nil, "the short tail")
		H.expect(AimStream.read({}, 1) == nil, "an empty batch")
		local missing = {}
		AimStream.pack(missing, 9, 99, 1, 2, 3, 0.5, 4)
		missing[6] = nil
		H.expect(AimStream.read(missing, 1) == nil, "a missing pull")
		local noAngle = {}
		AimStream.pack(noAngle, 9, 99, 1, 2, 3, 0.5, 4)
		noAngle[7] = "4"
		H.expect(AimStream.read(noAngle, 1) == nil, "a cue angle that is not a number")
	end,

	["the pull is clamped and snapped to whole steps, and only numbers count"] = function()
		local Config, AimStream = setup()
		local step = 1 / Config.Aim.PullSteps
		H.expect(AimStream.quantizePull(0) == 0, "zero")
		H.expect(AimStream.quantizePull(1) == 1, "one")
		H.expect(AimStream.quantizePull(-0.3) == 0, "clamped below")
		H.expect(AimStream.quantizePull(7) == 1, "clamped above")
		H.near(AimStream.quantizePull(0.5 + step * 0.4) :: number, 0.5, 1e-12, "rounds down")
		H.near(AimStream.quantizePull(0.5 + step * 0.6) :: number, 0.5 + step, 1e-12, "rounds up")
		for i = 0, 200 do
			local q = AimStream.quantizePull(i / 200) :: number
			H.near(
				q * Config.Aim.PullSteps,
				math.floor(q * Config.Aim.PullSteps + 0.5),
				1e-9,
				"whole"
			)
		end
		H.expect(AimStream.quantizePull(0 / 0) == nil, "NaN")
		H.expect(AimStream.quantizePull(math.huge) == nil, "infinity")
		H.expect(AimStream.quantizePull(-math.huge) == nil, "minus infinity")
		H.expect(AimStream.quantizePull("0.5") == nil, "a string")
		H.expect(AimStream.quantizePull(nil) == nil, "nothing")
		-- A reader snaps again rather than trusting the sender.
		local batch = {}
		AimStream.pack(batch, 1, 1, 0, 0, 0, 0.5 + step * 0.3, 4)
		H.near((AimStream.read(batch, 1) :: any).pull, 0.5, 1e-12, "re-snapped on read")
	end,

	["angles across the seam are close together"] = function()
		local _, AimStream = setup()
		local tau = 2 * math.pi
		H.near(AimStream.angleDelta(0.001, tau - 0.001), 0.002, 1e-12, "forward across 0")
		H.near(AimStream.angleDelta(tau - 0.001, 0.001), -0.002, 1e-12, "back across 0")
		H.near(AimStream.angleDelta(1, 0.5), 0.5, 1e-12, "plain")
		H.near(AimStream.angleDelta(0.5 + 3 * tau, 0.5), 0, 1e-9, "whole turns vanish")
		for i = 0, 50 do
			local d = AimStream.angleDelta(i * 0.37, i * 1.91)
			H.expect(d >= -math.pi and d < math.pi, "in range")
		end
	end,

	["when to send: first, on change, never too fast, a let-go at once"] = function()
		local Config, AimStream = setup()
		local gap = 1 / Config.Aim.SendsPerSecond
		local small = Config.Aim.MinChangeRadians * 0.5
		local big = Config.Aim.MinChangeRadians * 2
		local step = 1 / Config.Aim.PullSteps
		-- The first send of a turn goes, once the rate allows.
		H.expect(AimStream.due(gap, 1, 0, nil, nil), "first send")
		H.expect(AimStream.due(gap, 1, 0, 1, nil), "no pull sent yet")
		-- Nothing changed: nothing to say.
		H.expect(not AimStream.due(gap * 5, 1, 0.4, 1, 0.4), "no change")
		H.expect(not AimStream.due(gap * 5, 1 + small, 0.4, 1, 0.4), "a tiny turn")
		-- A real turn, or one whole step of pull, goes.
		H.expect(AimStream.due(gap, 1 + big, 0.4, 1, 0.4), "a turn")
		H.expect(AimStream.due(gap, 1, 0.4 + step, 1, 0.4), "a pull-only change")
		H.expect(AimStream.due(gap, 1, 0.4 - step, 1, 0.4), "easing off")
		-- A tiny turn across the seam is still tiny.
		H.expect(not AimStream.due(gap, small / 2, 0.4, 2 * math.pi - small / 2, 0.4), "seam")
		-- Never faster than SendsPerSecond, whatever changed...
		H.expect(not AimStream.due(gap * 0.5, 1 + big, 0.4, 1, 0.4), "rate limit")
		H.expect(not AimStream.due(gap * 0.5, 1, 1, 1, 0.4), "rate limit on pull")
		H.expect(not AimStream.due(gap * 0.5, 1, 0, nil, nil), "rate limit on the first")
		-- ...except a let-go, which goes at once.
		H.expect(AimStream.due(0, 1, 0, 1, 0.4), "let-go inside the window")
		H.expect(AimStream.due(0, 1, 0, 1, step), "letting go of one step")
		H.expect(not AimStream.due(0, 1, 0, 1, 0), "already at rest is not a let-go")
	end,
}
