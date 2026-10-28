--!strict
-- Track: the Halloween event's prize track (Config.Halloween.Track.Steps). Pure.
--
-- The track counts all Candy (Earned + Bought). Each step is granted the moment the total
-- reaches its At, once (the save's Given["<index>"]), never by a claim, so nobody loses a prize.
-- A cue step waits (stays ungiven) while its cue is not ready (Catalog.ready); the caller grants
-- the rest and tries the held ones again later.
local Config = require(script.Parent.Parent.Config)

local Track = {}

export type Step = { At: number, Cue: string?, Spins: number?, Money: number? }

function Track.steps(): { Step }
	return Config.Halloween.Track.Steps :: any
end

-- The save's key for step `index`.
function Track.key(index: number): string
	return tostring(index)
end

-- The indices of the steps reached by `total` and not yet given, in track order.
function Track.due(total: number, given: { [string]: boolean }): { number }
	local due = {}
	for index, step in Track.steps() do
		if total >= step.At and given[Track.key(index)] ~= true then
			table.insert(due, index)
		end
	end
	return due
end

-- The next step not reached yet (index and step), or nil past the last.
function Track.next(total: number): (number?, Step?)
	for index, step in Track.steps() do
		if total < step.At then
			return index, step
		end
	end
	return nil, nil
end

-- The kind of a step's prize: "Cue", "Spins" or "Money".
function Track.kind(step: Step): string
	if step.Cue ~= nil then
		return "Cue"
	elseif step.Spins ~= nil then
		return "Spins"
	end
	return "Money"
end

return Track
