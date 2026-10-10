--!strict
-- BotCues (Progression/BotCues): a bot's cue by its tier, against the economy v4 plan's table
-- (2026-10-08, section 11: the simulation's real players at day 60).

local H = require("./harness")

local function load()
	return H.require("Progression.BotCues"), H.require("Progression.Catalog"), H.require("Config")
end

-- The plan's table: { Epic+, Legendary+, Mythic+ }.
local PLAN: { [string]: { number } } = {
	Bronze = { 0.25, 0.045, 0.005 },
	Silver = { 0.8, 0.24, 0.03 },
	Gold = { 0.95, 0.36, 0.045 },
	Platinum = { 0.98, 0.45, 0.06 },
	Diamond = { 0.99, 0.58, 0.09 },
	Expert = { 0.99, 0.75, 0.15 },
	Veteran = { 0.99, 0.85, 0.25 },
	Master = { 0.99, 0.92, 0.35 },
	Grandmaster = { 0.99, 0.96, 0.5 },
	Reyes = { 0.99, 0.98, 0.65 },
}

-- A seeded xorshift32 giving rolls in [0, 1), the same sequence every run.
local function seeded(seed: number): () -> number
	local state = seed
	return function(): number
		state = bit32.bxor(state, bit32.lshift(state, 13))
		state = bit32.bxor(state, bit32.rshift(state, 17))
		state = bit32.bxor(state, bit32.lshift(state, 5))
		return state / 4294967296
	end
end

return {
	["the table is the plan's; the shares add to 1"] = function()
		local BotCues, _, Config = load()
		H.expect(#BotCues.validate() == 0, table.concat(BotCues.validate(), "; "))
		for tier, want in PLAN do
			local row = (Config.BotCues :: any)[tier]
			H.expect(
				row.EpicPlus == want[1]
					and row.LegendaryPlus == want[2]
					and row.MythicPlus == want[3],
				tier
			)
			local total = 0
			for _, entry in BotCues.shares(tier) do
				H.expect(entry.share >= 0, tier .. " " .. entry.rarity)
				total += entry.share
			end
			H.near(total, 1, 1e-9, tier .. " adds to 1")
		end
	end,

	["100,000 picks per tier land on the table; never the Secret cue"] = function()
		local BotCues, Catalog = load()
		local n = 100000
		for tier, want in PLAN do
			local roll = seeded(0x9E3779B1)
			local epic, legendary, mythic, below = 0, 0, 0, 0
			for _ = 1, n do
				local cue = Catalog.get(BotCues.pick(tier, roll()))
				assert(cue, "a catalog cue")
				H.expect(cue.Group == "Block" and not cue.Vaulted, "a block cue")
				H.expect(cue.Rarity ~= "Secret", "never the Secret cue")
				local rank = Catalog.rarityRank(cue.Rarity)
				if rank >= Catalog.rarityRank("Epic") then
					epic += 1
				else
					below += 1
				end
				if rank >= Catalog.rarityRank("Legendary") then
					legendary += 1
				end
				if rank >= Catalog.rarityRank("Mythic") then
					mythic += 1
				end
			end
			local function near(got: number, p: number, what: string)
				local tolerance = 4 * math.sqrt(n * p * (1 - p)) + 1
				H.expect(
					math.abs(got - n * p) <= tolerance,
					("%s %s: %d, expected %.0f +- %.0f"):format(tier, what, got, n * p, tolerance)
				)
			end
			near(epic, want[1], "Epic+")
			near(legendary, want[2], "Legendary+")
			near(mythic, want[3], "Mythic+")
			H.expect(epic + below == n, "every pick counted")
		end
	end,

	["below Epic follows the Mystery block's odds; within a rarity every cue is equal"] = function()
		local BotCues, Catalog = load()
		local BlockDrop = H.require("Progression.BlockDrop")
		local shares = BotCues.shares("Bronze")
		local mystery = { mystery = true }
		local function percent(rarity: string): number
			return BlockDrop.rarityPercent(rarity, mystery)
		end
		local weight = percent("Common") + percent("Uncommon") + percent("Rare")
		H.near(shares[1].share, 0.75 * percent("Common") / weight, 1e-12, "Common")
		H.near(shares[3].share, 0.75 * percent("Rare") / weight, 1e-12, "Rare")
		-- Evenly spaced rolls through the Common band give each Common cue the same count.
		local commons = 0
		for _, cue in Catalog.ofRarity("Common") do
			if cue.Group == "Block" and not cue.Vaulted then
				commons += 1
			end
		end
		local counts: { [string]: number } = {}
		local steps = commons * 100
		for i = 0, steps - 1 do
			local id = BotCues.pick("Bronze", (i + 0.5) / steps * shares[1].share)
			counts[id] = (counts[id] or 0) + 1
		end
		for id, count in counts do
			H.expect(count == 100, id .. " " .. count)
		end
	end,

	["the edges: 0, almost 1, junk and an unknown tier"] = function()
		local BotCues, Catalog = load()
		for _, tier in { "Bronze", "Reyes" } do
			for _, roll in { 0, 1 - 1e-15, 1, 2, -1, 0 / 0 } do
				H.expect(
					Catalog.get(BotCues.pick(tier, roll)) ~= nil,
					tier .. " " .. tostring(roll)
				)
			end
		end
		H.expect(Catalog.get(BotCues.pick("Bronze", 0)).Rarity == "Common", "0 is a Common")
		H.expect(Catalog.get(BotCues.pick("Reyes", 1 - 1e-15)).Rarity == "Mythic", "the top")
		H.expect(BotCues.pick("Nope", 0.5) == BotCues.pick("Bronze", 0.5), "unknown: Bronze")
	end,
}
