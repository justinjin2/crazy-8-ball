--!strict
-- ThinkQueue: every bot's thinking inside one shared budget a server frame (2026-10-25, the
-- Home surge: the worst tenth of live servers fell to 8 FPS, then under 2, as full servers
-- filled with Play against PC games). A bot thinks by simulating shots (~40 ms each on the
-- live server). Each bot used to wait one frame after each try, so every thinking bot woke in
-- the same next frame and their tries stacked: four bots, a ~160 ms frame for the whole server.
--
-- Now a bot waits in line between tries. Each frame `step` lets bots try in turn, first come
-- first served, while the frame's bot time stays under the budget (always at least one, so the
-- line keeps moving). A bot that wants another try goes to the back and waits for a later
-- frame. Bots think a little longer when many think at once (they already take 1.2 to 4 s to
-- aim), and no frame holds more than the budget plus one try.
--
-- Pure: the clock and the resume are passed in (the server's are os.clock and task.spawn).
local ThinkQueue = {}
ThinkQueue.__index = ThinkQueue

export type Queue = typeof(setmetatable(
	{} :: {
		waiting: { thread },
		budget: number, -- seconds of bot time a frame
		clock: () -> number,
		resume: (thread) -> (),
	},
	ThinkQueue
))

function ThinkQueue.new(budgetSeconds: number, clock: () -> number, resume: (thread) -> ()): Queue
	return setmetatable({
		waiting = {},
		budget = budgetSeconds,
		clock = clock,
		resume = resume,
	}, ThinkQueue)
end

--- Called from a bot's own thread between tries: waits in line until `step` lets it go on.
function ThinkQueue.wait(self: Queue)
	table.insert(self.waiting, coroutine.running())
	coroutine.yield()
end

--- How many bots are waiting.
function ThinkQueue.size(self: Queue): number
	return #self.waiting
end

--- One frame: lets waiting bots go on in order while the frame's budget lasts (at least one).
--- Returns how many went on. Bots that wait again during this step wait for a later frame.
function ThinkQueue.step(self: Queue): number
	local line = self.waiting
	if #line == 0 then
		return 0
	end
	self.waiting = {}
	local start = self.clock()
	local i = 1
	local ran = 0
	while i <= #line do
		local thread = line[i]
		i += 1
		-- A bot's thread cancelled while it waited is skipped.
		if coroutine.status(thread) == "suspended" then
			self.resume(thread)
			ran += 1
			if self.clock() - start >= self.budget then
				break
			end
		end
	end
	-- The rest keep their places, ahead of the bots that just waited again.
	if i <= #line then
		local rest = table.move(line, i, #line, 1, {})
		table.move(self.waiting, 1, #self.waiting, #rest + 1, rest)
		self.waiting = rest
	end
	return ran
end

return ThinkQueue
