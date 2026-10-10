--!strict
-- RankClaim: rank rewards held until the player claims them in Rank (designer, 2026-10-03;
-- docs/prompts/TUTORIAL_PROMPT.md, "Rule changes for everyone"). The save keeps the last
-- division whose rewards were claimed (Flags.RankClaimed); everything between it and the
-- peak is pending, except the lucky blocks of the tiers in Config.Tutorial.RankClaim
-- .BlocksAtOnce, which are given with the rank-up itself (none since tutorial v2: Bronze's
-- block waits in Rank too). Pure: no Instances, no clocks, arrays walked in order.
local Config = require(script.Parent.Parent.Config)
local Ranks = require(script.Parent.Parent.Progression.Ranks)

local AT_ONCE: { [string]: boolean } = Config.Tutorial.RankClaim.BlocksAtOnce
local BLOCK_ORDER: { string } = Config.LuckyBlocks.Order

local RankClaim = {}

-- One division's held rewards, for the claim block's chips and the fly animation.
export type Row = {
	index: number,
	money: number,
	blocks: { [string]: number },
	cue: string?,
	spins: number,
}

-- Everything pending, added up, plus the rows it came from (bottom first).
export type Pending = {
	money: number,
	blocks: { [string]: number },
	cues: { string },
	spins: number,
	rows: { Row },
}

-- Whether a division's lucky blocks are given at once (its tier is in BlocksAtOnce).
local function blocksAtOnce(index: number): boolean
	local tier = Ranks.at(index)
	return AT_ONCE[tier] == true
end

local function whole(n: any): number
	if type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge then
		return 0
	end
	return math.max(0, math.floor(n))
end

local function addBlocks(into: { [string]: number }, from: { [string]: number })
	for _, id in BLOCK_ORDER do
		local count = from[id]
		if count then
			into[id] = (into[id] or 0) + count
		end
	end
end

--- The lucky blocks given at once with a rank-up from peak `before` to peak `after`, by kind
--- (empty when none).
function RankClaim.blocksAtOnce(before: number, after: number): { [string]: number }
	local blocks: { [string]: number } = {}
	for _, reward in Ranks.rewardsBetween(whole(before), whole(after)) do
		if blocksAtOnce(reward.index) then
			addBlocks(blocks, reward.blocks)
		end
	end
	return blocks
end

--- What is held between the claimed division and the peak (nothing when the claimed one is
--- at or past the peak). A missing claimed value counts as the peak: nothing pending, so an
--- unknown save never pays twice.
function RankClaim.pending(claimed: number?, peak: number): Pending
	local valid = type(claimed) == "number" and claimed == claimed and math.abs(claimed) < math.huge
	local from = if valid then whole(claimed) else whole(peak)
	local out: Pending = { money = 0, blocks = {}, cues = {}, spins = 0, rows = {} }
	for _, reward in Ranks.rewardsBetween(from, whole(peak)) do
		local blocks = if blocksAtOnce(reward.index) then {} else table.clone(reward.blocks)
		local row: Row = {
			index = reward.index,
			money = reward.money,
			blocks = blocks,
			cue = reward.cue,
			spins = reward.spins,
		}
		out.money += row.money
		out.spins += row.spins
		addBlocks(out.blocks, row.blocks)
		if row.cue then
			table.insert(out.cues, row.cue)
		end
		if row.money > 0 or row.spins > 0 or row.cue ~= nil or next(row.blocks) ~= nil then
			table.insert(out.rows, row)
		end
	end
	return out
end

--- Whether anything is waiting to be claimed.
function RankClaim.any(p: Pending): boolean
	return #p.rows > 0
end

--- The pending rewards in PlayerData's Reward shape (money, blocks, cues, spins), or nil when
--- nothing is pending.
function RankClaim.reward(p: Pending): any
	if not RankClaim.any(p) then
		return nil
	end
	local reward: any =
		{ money = p.money, blocks = table.clone(p.blocks), cues = table.clone(p.cues) }
	if p.spins > 0 then
		reward.spins = p.spins
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
