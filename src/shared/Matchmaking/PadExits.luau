--!strict
-- PadExits: whose wait on a 2v2 or 3v3 pad ended, after how long, and how, for the TeamPad
-- analytics event (designer, 2026-10-26: measure the team queue, then change it). Pure: the
-- server hands in the table's engine each time it refreshes the pad, and `since` (kept per
-- table) remembers when each real player on the pad started waiting.
--
-- How a wait ends: "Global" (their side's global search found a match: they are on their
-- way), "PcFill" (the host filled the empty seats with PC players, Engine's `pcFill`),
-- "Started" (the pad filled and the game began) or "Left" (stepped off, left the game, or
-- the pad was emptied some other way).
local PadExits = {}

export type Exit = {
	userId: number,
	seconds: number,
	outcome: string,
}

-- Whether `userId` is in the pad's found global search.
local function found(e: any, userId: number): boolean
	return e.search ~= nil and e.search.found == true and table.find(e.search.users, userId) ~= nil
end

--- The waits on table engine `e`'s pad that ended since the last call, at `now`; `since`
--- (userId -> when they started waiting) is updated in place. Only a lobby team table counts
--- (teamSize 2 or 3, not an arena's); bots (ids below 1) never do.
function PadExits.step(since: { [number]: number }, e: any, now: number): { Exit }
	local exits: { Exit } = {}
	local waiting = e.phase == "Waiting"
	for userId, at in since do
		local seat = nil
		for _, s in e.seats do
			if s.userId == userId and s.connected then
				seat = s
			end
		end
		local outcome = nil
		if found(e, userId) then
			outcome = "Global"
		elseif seat == nil then
			outcome = "Left"
		elseif not waiting then
			outcome = if e.pcFill then "PcFill" else "Started"
		end
		if outcome then
			since[userId] = nil
			table.insert(
				exits,
				{ userId = userId, seconds = math.max(0, now - at), outcome = outcome }
			)
		end
	end
	if waiting and e.teamSize >= 2 and not e.fixed then
		for _, s in e.seats do
			if
				s.connected
				and s.userId > 0
				and since[s.userId] == nil
				and not found(e, s.userId)
			then
				since[s.userId] = s.joinedAt or now
			end
		end
	end
	table.sort(exits, function(a, b)
		return a.userId < b.userId
	end)
	return exits
end

return PadExits
