--!strict
-- ReelMath: the lucky block reel's showcase tile (economy v4 plan section 4, "the spin reel";
-- designer 2026-10-08: rare cues pass by more often, with safeguards). Each spin gets one
-- showcase tile, a cue from Epic up out of that block's own pool, placed in the strip's first
-- two-thirds and never within a few cards of where the reel stops, so it is never a near
-- miss; every other card is drawn at the real odds. Pure: the caller passes rng(n) -> 1..n
-- and the ranks (Catalog.rarityRank), so the Lune tests run it without Roblox.
local ReelMath = {}

export type Cue = { id: string, rarity: string, percent: number }

--- The showcase's slot on a strip of `cards` cards that stops on `prizeSlot`: picked evenly
--- from `first` up to the last slot inside the strip's first `share` and more than `gap` cards
--- before the stop. nil when no slot qualifies (a strip too short for one).
function ReelMath.showcaseSlot(
	rng: (number) -> number,
	cards: number,
	prizeSlot: number,
	first: number,
	share: number,
	gap: number
): number?
	local last = math.min(math.floor(cards * share), prizeSlot - gap - 1)
	if last < first then
		return nil
	end
	return first + rng(last - first + 1) - 1
end

--- The showcase's cue: a rarity picked evenly among the pool's rarities ranked `fromRank` or
--- higher (`rank(rarity)`), then one of that rarity's cues evenly, so a block's rarest cue
--- shows as often as its Epics. nil when the pool has none that high.
function ReelMath.showcaseCue(
	pool: { Cue },
	rank: (string) -> number,
	fromRank: number,
	rng: (number) -> number
): Cue?
	local rarities: { string } = {}
	local byRarity: { [string]: { Cue } } = {}
	for _, cue in pool do
		if cue.percent > 0 and rank(cue.rarity) >= fromRank then
			local list = byRarity[cue.rarity]
			if list == nil then
				list = {}
				byRarity[cue.rarity] = list
				table.insert(rarities, cue.rarity)
			end
			table.insert(list, cue)
		end
	end
	if #rarities == 0 then
		return nil
	end
	local list = byRarity[rarities[rng(#rarities)]]
	return list[rng(#list)]
end

return ReelMath
