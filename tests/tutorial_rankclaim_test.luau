--!strict
-- RankClaim (Tutorial/RankClaim): rank rewards held until claimed in Rank (designer,
-- 2026-10-03; cases retired for blocks 2026-10-04), Bronze's lucky block too (tutorial v2).

local H = require("./harness")

local function load()
	return H.require("Tutorial.RankClaim"), H.require("Progression.Ranks"), H.require("Config")
end

return {
	["no block is given at once, bronze's included"] = function()
		local RankClaim, Ranks = load()
		local bronze1 = Ranks.indexOf("Bronze", 1) :: number
		H.expect(next(RankClaim.blocksAtOnce(0, bronze1)) == nil, "Bronze I's block waits")
		H.expect(next(RankClaim.blocksAtOnce(bronze1, bronze1)) == nil, "no rise, nothing")
		local silver1 = Ranks.indexOf("Silver", 1) :: number
		H.expect(next(RankClaim.blocksAtOnce(0, silver1)) == nil, "passing Bronze: none either")
	end,

	["pending is everything between the claimed division and the peak"] = function()
		local RankClaim, Ranks, Config = load()
		local bronze1 = Ranks.indexOf("Bronze", 1) :: number
		local p = RankClaim.pending(0, bronze1)
		H.expect(RankClaim.any(p), "something pending")
		local bronze = Config.Ranks.Rewards.Tier.Bronze
		H.expect(
			p.money == bronze.Money and p.spins == Config.Ults.Earn.RankUp.Bronze,
			"money, spins"
		)
		H.expect(p.blocks.Mystery == bronze.Blocks.Mystery, "its block waits here too")
		H.expect(#p.cues == 1 and p.cues[1] == "BronzeCue", "the Bronze Cue")
		local reward = RankClaim.reward(p)
		H.expect(
			reward.money == bronze.Money
				and (reward.spins or 0) == Config.Ults.Earn.RankUp.Bronze
				and reward.blocks.Mystery == bronze.Blocks.Mystery,
			"the reward (no spins key when none)"
		)
		H.expect(reward.cues[1] == "BronzeCue", "the reward's cue")
		-- Two divisions at once add up, bottom first.
		local bronze3 = Ranks.indexOf("Bronze", 3) :: number
		local two = RankClaim.pending(0, bronze3)
		H.expect(#two.rows == 3 and two.rows[1].index == bronze1, "rows bottom first")
		H.expect(two.money == bronze.Money + 1000 + 1000, "money added up")
	end,

	["nothing pending once claimed, or for an unknown or broken save"] = function()
		local RankClaim, Ranks = load()
		local gold1 = Ranks.indexOf("Gold", 1) :: number
		local p = RankClaim.pending(gold1, gold1)
		H.expect(not RankClaim.any(p) and RankClaim.reward(p) == nil, "claimed: nothing")
		H.expect(not RankClaim.any(RankClaim.pending(nil, gold1)), "nil claimed counts as the peak")
		H.expect(not RankClaim.any(RankClaim.pending(gold1 + 3, gold1)), "past the peak")
		H.expect(not RankClaim.any(RankClaim.pending(0 / 0, gold1)), "NaN counts as the peak")
	end,

	["a later tier's blocks come with its claim"] = function()
		local RankClaim, Ranks, Config = load()
		local silver1 = Ranks.indexOf("Silver", 1) :: number
		local bronze5 = Ranks.indexOf("Bronze", 5) :: number
		local p = RankClaim.pending(bronze5, silver1)
		local want = Config.Ranks.Rewards.Tier.Silver
		H.expect(p.money == want.Money and p.blocks.Rare == want.Blocks.Rare, "Silver I's rewards")
		H.expect(
			p.cues[1] == "SilverCue" and p.spins == Config.Ults.Earn.RankUp.Silver,
			"cue, spins"
		)
	end,

	["the chat tag follows the claimed division"] = function()
		local RankClaim, Ranks = load()
		H.expect(RankClaim.tagTier(0) == "Unranked" and RankClaim.tagTier(nil) == "Unranked", "")
		H.expect(RankClaim.tagTier(Ranks.indexOf("Gold", 2)) == "Gold", "Gold")
	end,
}
