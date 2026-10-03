--!strict
-- BotCues: the cue a bot carries, by its rank tier (Config.BotCues; the approved economy plan,
-- 2026-10-02, section 3), so a bot's cue is as rare as real players' at that rank. The Bots
-- lane's Look.cue calls BotCues.pick(tier, Rng.uniform(rng)).
--
-- One roll in [0, 1) picks the rarity (Common, Uncommon, Rare by the Case Drop's odds below
-- the tier's Epic+ chance; then Epic, Legendary, Mythic by the tier's bands) and, inside that
-- rarity's band, an equal share of its case cues (not vaulted). Pure: no Instances, no clocks,
-- no randomness of its own; every loop walks an array. Lune-tested (tests/botcues_test.luau).
local Config = require(script.Parent.Parent.Config)
local Catalog = require(script.Parent.Catalog)
local CaseDrop = require(script.Parent.CaseDrop)

local TIERS: { string } = Config.Ranks.Tiers
local ROWS: { [string]: { EpicPlus: number, LegendaryPlus: number, MythicPlus: number } } =
	Config.BotCues :: any
local BELOW = { "Common", "Uncommon", "Rare" }

export type Share = { rarity: string, share: number }

-- BotCues.shares per tier, built on first use by pick.
local sharesOf: { [string]: { Share } } = {}

local BotCues = {}

-- The case cues a bot may carry at one rarity, in catalog order (built once per rarity).
local pools: { [string]: { string } } = {}
local function pool(rarity: string): { string }
	local list = pools[rarity]
	if list == nil then
		list = {}
		for _, cue in Catalog.ofRarity(rarity) do
			if cue.Group == "Case" and not cue.Vaulted then
				table.insert(list, cue.Id)
			end
		end
		pools[rarity] = list
	end
	return list
end

--- Each rarity's chance for a bot of `tier` (an unknown tier reads as the bottom one), in
--- rarity order; the shares add to 1.
function BotCues.shares(tier: string): { Share }
	local row = ROWS[tier] or ROWS[TIERS[1]]
	local below = 1 - row.EpicPlus
	local weight = 0
	for _, rarity in BELOW do
		weight += CaseDrop.rarityPercent(rarity)
	end
	local list: { Share } = {}
	for _, rarity in BELOW do
		table.insert(
			list,
			{ rarity = rarity, share = below * CaseDrop.rarityPercent(rarity) / weight }
		)
	end
	table.insert(list, { rarity = "Epic", share = row.EpicPlus - row.LegendaryPlus })
	table.insert(list, { rarity = "Legendary", share = row.LegendaryPlus - row.MythicPlus })
	table.insert(list, { rarity = "Mythic", share = row.MythicPlus })
	return list
end

--- The cue id a bot of `tier` carries for a roll in [0, 1) (anything outside is clamped).
function BotCues.pick(tier: string, roll: number): string
	local r = if type(roll) == "number" and roll == roll then math.clamp(roll, 0, 1 - 1e-12) else 0
	local start = 0
	local last: { string }? = nil -- the last rarity with cues reached (rounding falls there)
	local shares = sharesOf[tier]
	if shares == nil then
		shares = BotCues.shares(tier)
		sharesOf[tier] = shares
	end
	for _, entry in shares do
		local cues = pool(entry.rarity)
		if #cues > 0 then
			last = cues
			if entry.share > 0 and r < start + entry.share then
				local inside = (r - start) / entry.share
				return cues[math.clamp(math.floor(inside * #cues) + 1, 1, #cues)]
			end
		end
		start += entry.share
	end
	return if last ~= nil then last[#last] else Catalog.Default
end

--- Problems with Config.BotCues (empty when fine): every tier has a row whose chances fall
--- from Epic+ to Mythic+ inside 0..1.
function BotCues.validate(): { string }
	local problems: { string } = {}
	for _, tier in TIERS do
		local row = ROWS[tier]
		if row == nil then
			table.insert(problems, tier .. " has no row")
		elseif
			not (
				row.EpicPlus <= 1
				and row.EpicPlus >= row.LegendaryPlus
				and row.LegendaryPlus >= row.MythicPlus
				and row.MythicPlus >= 0
			)
		then
			table.insert(problems, tier .. "'s chances do not fall from Epic+ to Mythic+")
		end
	end
	return problems
end

return BotCues
