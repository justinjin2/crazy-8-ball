--!strict
-- RankClaim: rank rewards held until the player claims them in Rank (designer, 2026-10-03;
-- docs/prompts/TUTORIAL_PROMPT.md, "Rule changes for everyone"). The save keeps the last
-- division whose rewards were claimed (Flags.RankClaimed); everything between it and the
-- peak is pending, except the Case Drops of the tiers in Config.Tutorial.RankClaim
-- .DropsAtOnce, which are given with the rank-up itself (Bronze's 1 drop follows the first
-- win). Pure: no Instances, no clocks, arrays walked in order.
local Config = require(script.Parent.Parent.Config)
local Ranks = require(script.Parent.Parent.Progression.Ranks)

local AT_ONCE: { [string]: boolean } = Config.Tutorial.RankClaim.DropsAtOnce
local CASE_ORDER: { string } = Config.Cases.Order

local RankClaim = {}

-- One division's held rewards, for the claim block's chips and the fly animation.
export type Row = {
	index: number,
	money: number,
	cases: { [string]: number },
	drops: number,
	cue: string?,
	spins: number,
}

-- Everything pending, added up, plus the rows it came from (bottom first).
export type Pending = {
	money: number,
	cases: { [string]: number },
	drops: number,
	cues: { string },
	spins: number,
	rows: { Row },
}

-- Whether a division's Case Drops are given at once (its tier is in DropsAtOnce).
local function dropsAtOnce(index: number): boolean
	local tier = Ranks.at(index)
	return AT_ONCE[tier] == true
end

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

--- The Case Drops given at once with a rank-up from peak `before` to peak `after`.
function RankClaim.dropsAtOnce(before: number, after: number): number
	local drops = 0
	for _, reward in Ranks.rewardsBetween(whole(before), whole(after)) do
		if dropsAtOnce(reward.index) then
			drops += reward.drops
		end
	end
	return drops
end

--- What is held between the claimed division and the peak (nothing when the claimed one is
--- at or past the peak). A missing claimed value counts as the peak: nothing pending, so an
--- unknown save never pays twice.
function RankClaim.pending(claimed: number?, peak: number): Pending
	local valid = type(claimed) == "number" and claimed == claimed and math.abs(claimed) < math.huge
	local from = if valid then whole(claimed) else whole(peak)
	local out: Pending = { money = 0, cases = {}, drops = 0, cues = {}, spins = 0, rows = {} }
	for _, reward in Ranks.rewardsBetween(from, whole(peak)) do
		local drops = if dropsAtOnce(reward.index) then 0 else reward.drops
		local row: Row = {
			index = reward.index,
			money = reward.money,
			cases = table.clone(reward.cases),
			drops = drops,
			cue = reward.cue,
			spins = reward.spins,
		}
		out.money += row.money
		out.drops += drops
		out.spins += row.spins
		for _, id in CASE_ORDER do
			local count = row.cases[id]
			if count then
				out.cases[id] = (out.cases[id] or 0) + count
			end
		end
		if row.cue then
			table.insert(out.cues, row.cue)
		end
		if
			row.money > 0
			or drops > 0
			or row.spins > 0
			or row.cue ~= nil
			or next(row.cases) ~= nil
		then
			table.insert(out.rows, row)
		end
	end
	return out
end

--- Whether anything is waiting to be claimed.
function RankClaim.any(p: Pending): boolean
	return #p.rows > 0
end

--- The pending rewards in PlayerData's Reward shape (money, cases, drops, cues, spins), or
--- nil when nothing is pending.
function RankClaim.reward(p: Pending): any
	if not RankClaim.any(p) then
		return nil
	end
	local reward: any =
		{ money = p.money, cases = table.clone(p.cases), cues = table.clone(p.cues) }
	if p.spins > 0 then
		reward.spins = p.spins
	end
	if p.drops > 0 then
		reward.drops = p.drops
	end
	return reward
end

--- The tier whose chat tag a player shows: the claimed division's tier (the tag is one of
--- the held rewards), "Unranked" below Bronze I.
function RankClaim.tagTier(claimed: number?): string
	local tier = Ranks.at(whole(claimed))
	return tier
end

return RankClaim
