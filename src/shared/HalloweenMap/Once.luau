--!strict
-- Once (Halloween 2026, hw-map lane): a build that runs one time however many callers ask for
-- it at once. The throne and the rooftop's props wait on the event's meshes while they build,
-- and a server that starts while the event is Live can ask twice in that wait; the second
-- caller now waits for the first build instead of starting another. The build returns true
-- when it is done; false (or an error, passed on to the caller that ran it) leaves it unbuilt,
-- so the next call tries again. Waiting callers are parked with coroutines (no task library),
-- so the same code runs in Lune.

local Once = {}
Once.__index = Once

export type Once = typeof(setmetatable(
	{} :: {
		build: () -> boolean,
		done: boolean,
		building: boolean,
		waiting: { thread },
	},
	Once
))

--- A build to run once (`build` yields as long as it needs; true when built).
function Once.new(build: () -> boolean): Once
	return setmetatable({ build = build, done = false, building = false, waiting = {} }, Once)
end

--- Build it if it is not built yet; while another caller builds it, wait for that build.
--- True once built.
function Once.run(self: Once): boolean
	if self.done then
		return true
	end
	if self.building then
		table.insert(self.waiting, coroutine.running())
		coroutine.yield()
		return self.done
	end
	self.building = true
	local ok, result = pcall(self.build)
	self.building = false
	self.done = ok and result == true
	local waiting = self.waiting
	self.waiting = {}
	for _, thread in waiting do
		coroutine.resume(thread)
	end
	if not ok then
		error(result, 0)
	end
	return self.done
end

return Once
