--!strict
-- ReelMath (src/shared/ReelMath): the lucky block reel's showcase tile (economy v4 plan
-- section 4): one cue from Epic up out of the block's own pool, in the strip's first
-- two-thirds and never within 8 cards of the stop.

local H = require("./harness")

local function load()
	return H.require("ReelMath"), H.require("Config"), H.require("Progression.Catalog")
end

-- Every outcome of rng in turn: rng(n) gives 1, 2, ..., n, 1, ...
local function cycling(): (number) -> number
	local i = 0
	return function(n: number): number
		i += 1
		return (i - 1) % n + 1
	end
end

return {
	["the showcase's slot: the first two-thirds, never within 8 cards of the stop"] = function()
		local ReelMath, Config = load()
		local R = Config.UI.Reel.Reel
		local seen: { [number]: boolean } = {}
		local rng = cycling()
		for _ = 1, 200 do
			local slot = ReelMath.showcaseSlot(
				rng,
				R.Cards,
				R.PrizeSlot,
				R.ShowcaseFirstSlot,
				R.ShowcaseShare,
				R.ShowcaseGapCards
			)
			assert(slot, "a slot on the game's strip")
			seen[slot] = true
			H.expect(slot >= R.ShowcaseFirstSlot, "not before the first slot")
			H.expect(slot <= math.floor(R.Cards * 2 / 3), "inside the first two-thirds")
			H.expect(R.PrizeSlot - slot > 8, ("slot %d is near the stop"):format(slot))
		end
		local last =
			math.min(math.floor(R.Cards * R.ShowcaseShare), R.PrizeSlot - R.ShowcaseGapCards - 1)
		for slot = R.ShowcaseFirstSlot, last do
			H.expect(seen[slot] == true, ("slot %d never chosen"):format(slot))
		end
		H.expect(R.ShowcaseGapCards >= 8 and R.ShowcaseShare <= 2 / 3, "the plan's safeguards")
		H.expect(ReelMath.showcaseSlot(rng, 12, 10, 8, 2 / 3, 8) == nil, "too short: none")
	end,

	["the showcase's cue: Epic up from the pool, each rarity as often"] = function()
		local ReelMath, _, Catalog = load()
		local pool = {
			{ id = "c1", rarity = "Common", percent = 70 },
			{ id = "r1", rarity = "Rare", percent = 20 },
			{ id = "e1", rarity = "Epic", percent = 5 },
			{ id = "e2", rarity = "Epic", percent = 4 },
			{ id = "l1", rarity = "Legendary", percent = 0.9 },
			{ id = "s1", rarity = "Secret", percent = 0.1 },
			{ id = "u1", rarity = "Unique", percent = 0 }, -- no chance: never shown
		}
		local counts: { [string]: number } = {}
		local rng = cycling()
		local from = Catalog.rarityRank("Epic")
		for _ = 1, 600 do
			local cue = ReelMath.showcaseCue(pool, Catalog.rarityRank, from, rng)
			assert(cue, "a cue")
			H.expect(Catalog.rarityRank(cue.rarity) >= from, cue.id .. " is under Epic")
			counts[cue.rarity] = (counts[cue.rarity] or 0) + 1
		end
		H.expect(counts.Epic == 200 and counts.Legendary == 200 and counts.Secret == 200, "even")
		H.expect(counts.Unique == nil, "a row with no chance is never shown")
		local low = { { id = "c1", rarity = "Common", percent = 100 } }
		H.expect(ReelMath.showcaseCue(low, Catalog.rarityRank, from, rng) == nil, "none: nil")
	end,
}
