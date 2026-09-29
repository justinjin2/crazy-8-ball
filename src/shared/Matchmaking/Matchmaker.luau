--!strict
-- Matchmaker: who plays whom in the global queue (designer, 2026-09-28). Pure: tickets and
-- the time come in, pairs go out, in the same order every time (no hash-order iteration),
-- so the leader server decides the same thing a Lune test does.
--
-- A ticket is one side: a single player on 1v1, a whole team on 2v2 and 3v3 (the host and
-- the next on their pad). Its rating is its rank in divisions (Matchmaker.rating), a team's
-- the average. Two tickets of the same mode may meet when their ranks are within the range
-- of whichever has searched longer (Config.GlobalQueue.Window): the closest rank first,
-- anyone after 10 s. The oldest search is served first, with the closest rank in range.
-- Each ticket names its pool, Ults On or Off (designer, 2026-09-28): two pools share the one
-- queue, and a search only ever meets one of its own pool.
local Config = require(script.Parent.Parent.Config)
local Ranks = require(script.Parent.Parent.Progression.Ranks)

local G = Config.GlobalQueue
local Matchmaker = {}

export type Candidate = {
	id: string,
	mode: number,
	users: { number },
	rating: number,
	at: number, -- when it started searching (the servers' shared clock, seconds)
	avoid: { number }?, -- players it should not meet while young (the last opponent)
	ults: boolean?, -- its pool: false for No ults; true or missing for ults on
}

export type Pair = {
	a: any, -- the older search: team 1
	b: any, -- team 2
	gap: number, -- divisions apart
}

--- How many divisions apart a search `waited` seconds old may be matched.
function Matchmaker.window(waited: number): number
	local divisions = 0
	for _, step in G.Window do
		if waited >= step.After then
			divisions = step.Divisions
		end
	end
	return divisions
end

--- A player's rating: their division (Bronze I is 1) plus how far into it they are, so two
--- players in one division still meet the closer first. Unranked counts as Bronze I.
function Matchmaker.rating(rankXp: number, rated: boolean): number
	local rank = Ranks.fromXp(rankXp, rated)
	if rank.index <= 0 then
		return 1
	end
	local width = rank.width
	local into = if width and width > 0 then math.clamp(rank.xpInDivision / width, 0, 0.999) else 0
	return rank.index + into
end

--- A team's rating: the average of its players'.
function Matchmaker.teamRating(ratings: { number }): number
	if #ratings == 0 then
		return 1
	end
	local sum = 0
	for _, r in ratings do
		sum += r
	end
	return sum / #ratings
end

local function older(a: Candidate, b: Candidate): boolean
	if a.at ~= b.at then
		return a.at < b.at
	end
	return a.id < b.id
end

--- A search's pool: ults on unless it says exactly false (a ticket from before the choice).
function Matchmaker.pool(c: any): boolean
	return c.ults ~= false
end

local function shares(a: Candidate, b: Candidate): boolean
	for _, u in a.users do
		if table.find(b.users, u) then
			return true
		end
	end
	return false
end

-- Whether `from` still refuses to meet `other`: while it is younger than AvoidRecentSeconds
-- and `other` holds someone on its avoid list.
local function avoids(from: Candidate, other: Candidate, now: number): boolean
	if not from.avoid or now - from.at >= G.AvoidRecentSeconds then
		return false
	end
	for _, u in other.users do
		if table.find(from.avoid, u) then
			return true
		end
	end
	return false
end

--- The pairs to make now, from every waiting ticket. Each ticket is in at most one pair and
--- no player is in two, and both of a pair share a mode and a pool. Deterministic for any
--- input order.
function Matchmaker.pair(tickets: { Candidate }, now: number): { Pair }
	local order = table.clone(tickets)
	table.sort(order, older)
	local used: { [string]: boolean } = {}
	local busy: { [number]: boolean } = {}
	local function free(t: Candidate): boolean
		if used[t.id] then
			return false
		end
		for _, u in t.users do
			if busy[u] then
				return false
			end
		end
		return true
	end
	local pairs: { Pair } = {}
	for _, a in order do
		if not free(a) then
			continue
		end
		local reachA = Matchmaker.window(now - a.at)
		local best: Candidate? = nil
		local bestGap = math.huge
		for _, b in order do
			if
				b ~= a
				and b.mode == a.mode
				and Matchmaker.pool(b) == Matchmaker.pool(a)
				and free(b)
				and not shares(a, b)
				and not avoids(a, b, now)
				and not avoids(b, a, now)
			then
				local gap = math.abs(a.rating - b.rating)
				local reach = math.max(reachA, Matchmaker.window(now - b.at))
				-- Strictly closer only: on a tie the older (earlier in `order`) keeps it.
				if gap <= reach and gap < bestGap then
					best, bestGap = b, gap
				end
			end
		end
		if best then
			used[a.id], used[best.id] = true, true
			for _, u in a.users do
				busy[u] = true
			end
			for _, u in best.users do
				busy[u] = true
			end
			table.insert(pairs, { a = a, b = best, gap = bestGap })
		end
	end
	return pairs
end

return Matchmaker
