--!strict
-- Bot thinking frames benchmark (2026-10-25, Config.Bots.Think): several bots think at once,
-- as on a full live server, and each "server frame" is timed. Before: each bot waited one
-- frame after each try, so every thinking bot tried in the same next frame. After: the bots
-- wait in one line (src/shared/Bots/ThinkQueue) inside FrameBudgetMs a frame.
--   lune run tools/bench_bot_frames.luau          # 6 bots, interpreted and native
--   lune run tools/bench_bot_frames.luau 10       # 10 bots
-- A Roblox server is a different machine: read the ratio and the shape, not the milliseconds.

local process = require("@lune/process")
local H = require("../tests/harness")
local V = require("../tests/ult_value")

local bots = tonumber(process.args[1] or "") or 6

local function report(label: string, frames: { number }, total: number)
	table.sort(frames)
	local n = #frames
	local slow = 0
	for _, f in frames do
		if f > 1000 / 30 then
			slow += 1
		end
	end
	print(
		("%-24s frames %4d  p50 %6.1f  p90 %6.1f  worst %6.1f ms  over 33 ms: %3d  bot time %6.0f ms"):format(
			label,
			n,
			frames[math.max(1, math.ceil(0.5 * n))],
			frames[math.max(1, math.ceil(0.9 * n))],
			frames[n],
			slow,
			total
		)
	)
end

-- Runs `bots` bot decisions at once, frame by frame, and returns each frame's milliseconds.
local function run(queued: boolean): ({ number }, number)
	local Config = H.require("Config")
	local Ball = H.require("Physics.Ball")
	local TableGeometry = H.require("Physics.Table")
	local Brain = H.require("Bots.Brain")
	local Rng = H.require("Bots.Rng")
	local ThinkQueue = H.require("Bots.ThinkQueue")
	local geometry = TableGeometry.build({ pocketsOpen = true })
	local q = ThinkQueue.new(Config.Bots.Think.FrameBudgetMs / 1000, os.clock, function(thread)
		assert(coroutine.resume(thread))
	end)
	local waiting: { thread } = {}
	local yield = if queued
		then function()
			q:wait()
		end
		else function()
			table.insert(waiting, coroutine.running())
			coroutine.yield()
		end
	local threads = {}
	local started = os.clock()
	for i = 1, bots do
		local ts = V.tableState(11, i, "fresh")
		local view = {
			geometry = geometry,
			balls = Ball.cloneList(ts.balls),
			groups = table.clone(ts.groups),
			team = 1,
			requireRail = false,
		}
		table.insert(
			threads,
			coroutine.create(function()
				-- Several turns each, from a freshly broken rack (the costliest tables to think on).
				for turn = 1, 4 do
					Brain.decide(view :: any, "Gold", Rng.new(40 + 10 * i + turn), { yield = yield })
				end
			end)
		)
	end
	-- Frame 1: every bot starts thinking in the same frame (a full server's turns line up).
	local frames = {}
	local t0 = os.clock()
	for _, th in threads do
		assert(coroutine.resume(th))
	end
	table.insert(frames, (os.clock() - t0) * 1000)
	local function busy(): boolean
		for _, th in threads do
			if coroutine.status(th) ~= "dead" then
				return true
			end
		end
		return false
	end
	while busy() do
		local f0 = os.clock()
		if queued then
			q:step()
		else
			local line = waiting
			waiting = {}
			for _, th in line do
				assert(coroutine.resume(th))
			end
		end
		table.insert(frames, (os.clock() - f0) * 1000)
	end
	return frames, (os.clock() - started) * 1000
end

print(("%d bots thinking at once (Gold), FrameBudgetMs %d"):format(bots, H.require("Config").Bots.Think.FrameBudgetMs))
for _, native in { false, true } do
	local tag = if native then "native" else "interpreted"
	for _, queued in { false, true } do
		local r = H.isolated(native, function()
			local frames, total = run(queued)
			return { frames = frames, total = total }
		end)
		report(tag .. (if queued then ", queue" else ", before"), r.frames, r.total)
	end
end
