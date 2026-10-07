--!strict
-- UltsChoice: the global queue's Ults: On / Off (designer, 2026-09-28). The host's card has
-- a toggle (on by default, kept in the save as Ults.QueueUlts), and a search only meets
-- searches on the same setting: two pools in the one queue (Ticket.pool). A No-ults search
-- that has found nobody in Config.GlobalQueue.NoUltsFallbackSeconds is offered the ults-on
-- pool, keeping its search time. Lobby tables and vs PC always play with ults on.
--
-- Pure: the checks the server makes before it takes either press (TableService), which the
-- host's card used to show them (QueueMenu, gone 2026-10-07). `t` is a table's engine
-- state or its snapshot: both carry phase, fixed, hostId and search ({ at, found }).
local Config = require(script.Parent.Parent.Config)

local G = Config.GlobalQueue
local UltsChoice = {}

--- A saved choice, a ticket's or a record's pool: ults on unless it is exactly false.
function UltsChoice.pool(value: any): boolean
	return value ~= false
end

--- Whether `userId` may set the choice to `value` now (SetQueueUlts): a boolean, the pad's
--- host, a lobby table waiting (an arena's has no card), and no search on the pad (the
--- choice a running search was posted with stays its pool; the fallback moves it).
function UltsChoice.canSet(t: any, userId: any, value: any): boolean
	return type(value) == "boolean"
		and type(t) == "table"
		and t.phase == "Waiting"
		and not t.fixed
		and t.hostId ~= nil
		and t.hostId == userId
		and t.search == nil
end

--- Whether the "Search with ults on?" offer stands for `userId` (SearchWithUlts): the pad's
--- host, the pad searching and not matched yet, the search in the No-ults pool
--- (`searchUlts` false), for at least NoUltsFallbackSeconds by `now` (the search's clock).
--- `slack` lets the server take a Yes that much early.
function UltsChoice.canFallback(
	t: any,
	userId: any,
	searchUlts: any,
	now: number,
	slack: number?
): boolean
	if type(t) ~= "table" or t.phase ~= "Waiting" or t.fixed then
		return false
	end
	if t.hostId == nil or t.hostId ~= userId or searchUlts ~= false then
		return false
	end
	local search = t.search
	if type(search) ~= "table" or search.found or type(search.at) ~= "number" then
		return false
	end
	return now - search.at >= G.NoUltsFallbackSeconds - (slack or 0)
end

return UltsChoice
