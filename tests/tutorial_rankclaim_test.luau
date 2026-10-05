--!strict
-- RankClaim (Tutorial/RankClaim): rank rewards held until claimed in Rank, Bronze's lucky
-- block given at once (designer, 2026-10-03; cases retired for blocks 2026-10-04).

local H = require("./harness")

local function load()
	return H.require("Tutorial.RankClaim"), H.require("Progression.Ranks"), H.require("Config")
end

return {
	["bronze's block is given at once and nothing else"] = function()
		local RankClaim, Ranks = load()
		local bronze1 = Ranks.indexOf("Bronze", 1) :: number
		H.expect(RankClaim.blocksAtOnce(0, bronze1).Mystery == 1, "Bronze I's 1 block at once")
		H.expect(next(RankClaim.blocksAtOnce(bronze1, bronze1)) == nil, "no rise, nothing")
		local silver1 = Ranks.indexOf("Silver", 1) :: number
		H.expect(next(RankClaim.blocksAtOnce(bronze1, silver1)) == nil, "Silver gives none at once")
		H.expect(RankClaim.blocksAtOnce(0, silver1).Mystery == 1, "passing Bronze still gives it")
	end,

	["pending is everything between the claimed division and the peak"] = function()
		local RankClaim, Ranks = load()
		local bronze1 = Ranks.indexOf("Bronze", 1) :: number
		local p = RankClaim.pending(0, bronze1)
		H.expect(RankClaim.any(p), "something pending")
		H.expect(p.money == 2500 and p.spins == 1, "Bronze I's money and spin")
		H.expect(next(p.blocks) == nil, "its block was given at once")
		H.expect(#p.cues == 1 and p.cues[1] == "BronzeCue", "the Bronze Cue")
		local reward = RankClaim.reward(p)
		H.expect(
			reward.money == 2500 and reward.spins == 1 and next(reward.blocks) == nil,
			"the reward"
		)
		H.expect(reward.cues[1] == "BronzeCue", "the reward's cue")
		-- Two divisions at once add up, bottom first.
		local bronze3 = Ranks.indexOf("Bronze", 3) :: number
		local two = RankClaim.pending(0, bronze3)
		H.expect(#two.rows == 3 and two.rows[1].index == bronze1, "rows bottom first")
		H.expect(two.money == 2500 + 1000 + 1000, "money added up")
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
