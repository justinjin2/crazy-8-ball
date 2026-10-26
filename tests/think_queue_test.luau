--!strict
-- Bots think inside one budget a server frame (2026-10-25, src/shared/Bots/ThinkQueue): bots
-- wait in line between tries, a frame lets them go on in order while its bot time lasts and
-- always at least one, so nobody waits forever and no frame holds every bot's try at once.
local H = require("./harness")
local Config = H.require("Config")
local ThinkQueue = H.require("Bots.ThinkQueue")
local expect = H.expect

local tests = {}

-- A fake clock each try advances by `cost` seconds; resume is a plain coroutine.resume.
local function setup(budget: number, cost: number)
	local now = 0
	local q = ThinkQueue.new(budget, function()
		return now
	end, function(thread)
		local ok, err = coroutine.resume(thread)
		assert(ok, err)
	end)
	-- A bot that runs `tries` tries, waiting in line after each, and notes each try's frame.
	local frame = 0
	local log: { { bot: string, frame: number } } = {}
	local function bot(name: string, tries: number): thread
		local thread = coroutine.create(function()
			for _ = 1, tries do
				now += cost
				table.insert(log, { bot = name, frame = frame })
				q:wait()
			end
		end)
		coroutine.resume(thread)
		return thread
	end
	local function step(): number
		frame += 1
		return q:step()
	end
	return q, bot, step, log
end

tests["the switch is on with a budget well under a 60 FPS frame"] = function()
	local T = Config.Bots.Think
	expect(T.Enabled == true, "on")
	expect(T.FrameBudgetMs > 0 and T.FrameBudgetMs < 1000 / 60, "under one frame")
end

tests["slow tries: one bot's try a frame, however many bots think"] = function()
	local q, bot, step, log = setup(0.008, 0.040)
	for i = 1, 4 do
		bot("b" .. i, 3)
	end
	expect(#log == 4 and q:size() == 4, "each bot's first try ran as it started, then it waits")
	for _ = 1, 8 do
		expect(step() == 1, "one try a frame when a try is over budget")
	end
	-- 4 bots x 2 more tries = 8 frames, in turn: b1, b2, b3, b4, b1, ...
	for k = 5, 12 do
		local expected = "b" .. ((k - 5) % 4 + 1)
		expect(log[k].bot == expected, ("try %d is %s's, got %s"):format(k, expected, log[k].bot))
	end
	expect(step() == 4 and q:size() == 0, "the last waits end the threads")
	expect(step() == 0, "nothing waiting, nothing run")
end

tests["fast tries: several fit in one frame, up to the budget"] = function()
	local q, bot, step, log = setup(0.008, 0.003)
	for i = 1, 5 do
		bot("b" .. i, 2)
	end
	-- 3 ms tries: after 3 of them (9 ms) the 8 ms budget is spent.
	expect(step() == 3, "three tries fit")
	expect(q:size() == 5, "the two left keep their places ahead of the three that wait again")
	-- b4 and b5 try (6 ms), then b1 to b3 have no tries left and just finish (no time).
	expect(step() == 5, "the two left go first, then the three finish")
	local order = {}
	for k = 6, #log do
		table.insert(order, log[k].bot)
	end
	expect(table.concat(order, ",") == "b1,b2,b3,b4,b5", "first come, first served")
	expect(step() == 2 and q:size() == 0, "b4 and b5 finish")
end

tests["a cancelled bot is skipped"] = function()
	local q, bot, step = setup(0.008, 0.040)
	local a = bot("a", 3)
	bot("b", 3)
	coroutine.close(a)
	expect(step() == 1, "only b ran")
	expect(q:size() == 1, "b waits again; a is gone")
end

return tests
