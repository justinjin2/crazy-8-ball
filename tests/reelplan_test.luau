--!strict
-- The case reel's near-miss plan (Progression/ReelPlan; designer 2026-10-03, D15): about 1 roll
-- in 5 teases a rarer cue beside the prize, and the reel always ends on the server's prize.

local H = require("./harness")

local function load()
	return H.require("Progression.ReelPlan"), H.require("Config")
end

local POOL = {
	{ id = "a", rarity = "Common" },
	{ id = "b", rarity = "Common" },
	{ id = "c", rarity = "Rare" },
	{ id = "d", rarity = "Epic" },
	{ id = "e", rarity = "Epic" },
	{ id = "f", rarity = "Mythic" },
}

return {
	["a roll under the chance teases the next rarer rarity the pool has"] = function()
		local ReelPlan, Config = load()
		local order = Config.Cases.Rarities
		local t = ReelPlan.tease({ chance = 0.1, side = 0.2, pick = 0 }, "Common", POOL, order, 0.2)
		H.expect(t ~= nil and t.id == "c" and t.rarity == "Rare" and t.side == -1, "Rare, before")
		t = ReelPlan.tease({ chance = 0.1, side = 0.9, pick = 0.99 }, "Rare", POOL, order, 0.2)
		H.expect(t ~= nil and t.id == "e" and t.side == 1, "Epic (the second), after")
		t = ReelPlan.tease({ chance = 0.1, side = 0.9, pick = 0 }, "Epic", POOL, order, 0.2)
		H.expect(t ~= nil and t.rarity == "Mythic", "skips Legendary when the pool has none")
	end,

	["no tease above the chance, or with nothing rarer"] = function()
		local ReelPlan, Config = load()
		local order = Config.Cases.Rarities
		H.expect(
			ReelPlan.tease({ chance = 0.2, side = 0, pick = 0 }, "Common", POOL, order, 0.2) == nil,
			"missed"
		)
		H.expect(
			ReelPlan.tease({ chance = 0, side = 0, pick = 0 }, "Mythic", POOL, order, 0.2) == nil,
			"top"
		)
		H.expect(
			ReelPlan.tease({ chance = 0, side = 0, pick = 0 }, "Nope", POOL, order, 0.2) == nil,
			"unknown"
		)
	end,

	["about 1 roll in 5 teases, and every reel ends on the prize"] = function()
		local ReelPlan, Config = load()
		local order = Config.Cases.Rarities
		local chance = Config.UI.CaseOpening.Reel.NearMissChance
		H.expect(math.abs(chance - 0.2) < 1e-9, "1 in 5")
		local seed = 12345
		local function roll(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local teased = 0
		local n = 20000
		for i = 1, n do
			local prize = POOL[(i % 3) + 1] -- Common, Common, Rare prizes
			local t = ReelPlan.tease(
				{ chance = roll(), side = roll(), pick = roll() },
				prize.rarity,
				POOL,
				order,
				chance
			)
			if t then
				teased += 1
				H.expect(table.find(order, t.rarity) > table.find(order, prize.rarity), "rarer")
			end
			local centre = 1000 + i
			local first, last = ReelPlan.stops(centre, 160, t, 0.85)
			H.expect(last == centre, "ends on the prize")
			if t then
				H.expect(math.abs(first - (centre + t.side * 160)) < 80, "stops on the teased card")
			else
				H.expect(first == centre, "no tease: one stop")
			end
		end
		local share = teased / n
		H.expect(share > 0.18 and share < 0.22, "about 20%: " .. share)
	end,
}
