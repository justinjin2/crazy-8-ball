--!strict
-- ReelPlan: the case reel's near-miss (GUI lane; designer 2026-10-03, D15: about 1 roll in 5 on
-- every case, the real odds unchanged). Purely visual and pure: the client's reel asks it
-- whether this roll teases, which rarer cue sits next to the prize, and on which side; the reel
-- then slows onto that cue and ticks over onto the prize. The prize is always the server's pick
-- and always where the reel ends: a tease only chooses what the card beside it shows.
-- Rolls come in as numbers in [0, 1) (the client's Random), so tests can pin them.

local ReelPlan = {}

export type Entry = { id: string, rarity: string }
export type Tease = {
	id: string, -- the rarer cue shown beside the prize
	rarity: string,
	side: number, -- -1: it sits before the prize (the reel stops short, then creeps on);
	-- 1: after it (the reel overshoots, then ticks back)
}
export type Rolls = { chance: number, side: number, pick: number }

local function rank(order: { string }, rarity: string): number
	return table.find(order, rarity) or 0
end

--- The tease for this roll, or nil (no tease: the roll missed `chance`, or nothing in the case's
--- pool is rarer than the prize). The tease is a cue of the next rarer rarity the pool has,
--- picked evenly among that rarity's cues.
function ReelPlan.tease(
	rolls: Rolls,
	prizeRarity: string,
	pool: { Entry },
	order: { string },
	chance: number
): Tease?
	if rolls.chance >= chance then
		return nil
	end
	local prizeRank = rank(order, prizeRarity)
	if prizeRank == 0 then
		return nil
	end
	local best = math.huge
	for _, entry in pool do
		local r = rank(order, entry.rarity)
		if r > prizeRank and r < best then
			best = r
		end
	end
	if best == math.huge then
		return nil
	end
	local candidates = {}
	for _, entry in pool do
		if rank(order, entry.rarity) == best then
			table.insert(candidates, entry)
		end
	end
	table.sort(candidates, function(a, b)
		return a.id < b.id
	end)
	local index = math.clamp(math.floor(rolls.pick * #candidates) + 1, 1, #candidates)
	local chosen = candidates[index]
	return {
		id = chosen.id,
		rarity = chosen.rarity,
		side = if rolls.side < 0.5 then -1 else 1,
	}
end

--- Where the reel first stops for a tease (`stopShare` of a card's pitch from the prize's
--- middle, onto the teased card) and where it ends (the prize's middle). Without a tease the
--- first stop is the end.
function ReelPlan.stops(
	prizeCentre: number,
	pitch: number,
	tease: Tease?,
	stopShare: number
): (number, number)
	if not tease then
		return prizeCentre, prizeCentre
	end
	return prizeCentre + tease.side * pitch * stopShare, prizeCentre
end

return ReelPlan
