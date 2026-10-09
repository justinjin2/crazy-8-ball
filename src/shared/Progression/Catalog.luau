--!strict
-- The cue catalog (GDD section 12, ECONOMY sections 6 and 18): every cue in the game as a data
-- row, plus small lookups. Like Config it is data: adding a cue is adding a row (and its name in
-- Strings.Items.Cues), never code. Pure: no Instances, and every list here is an array walked
-- in order, so nothing depends on hash order.
--
-- A row:
--   Id        stable catalog id (saved; never renamed)
--   Rarity    Common ... Secret for block cues and Classic (a Common, designer 2026-09-30);
--             "Ranked" for the ten rank cues (designer, 2026-10-08), "Exclusive" or "Unique"
--   Group     "Block" (drops from lucky blocks), "Exclusive" (one special way each), "Unique"
--             (numbered Limited copies) or "Default"
--   Tradable  may be traded (trading is a later session; the flag is stored now): block and
--             Unique cues and the Starter Cue yes; the other Exclusive cues and Classic never
--   Sellable  may be sold back (block cues only)
--   Blocks    the odds rows (Config.BlockOdds) that drop it (block cues only; none: it drops
--             from nothing, the Week One Cue)
--   Vaulted   true stops it dropping (ECONOMY 12); it stays in the Index and in saves
--   Tier      the rank tier whose reward it is (rank cues)
--   Effect    the Config.Effects.Styles tier row for its trail and pocket burst, used where
--             its skin (CueSkins) sets none
--   Look      flat colours (the 2D power-bar cue, and the band cue where it has no skin):
--             Shaft, Forearm, Wrap, Ring, and optional Tip, Cap, Accent (a band in the
--             forearm) and Rainbow (the forearm in the house rainbow). A skinned cue's comes
--             from its colour map (CueSkins.Index, generated); its real look is its skin.
--
-- The cues are the cue-skins run's (2026-09-30, docs/prompts/CUE_SKINS_REPORT.md): every block,
-- rank and Exclusive cue has a skin; the Unique cues keep placeholder bands until theirs exist.
local Config = require(script.Parent.Parent.Config)
local SkinIndex = require(script.Parent.Parent.CueSkins.Index)

export type Look = {
	Shaft: { number },
	Forearm: { number },
	Wrap: { number },
	Ring: { number },
	Tip: { number }?,
	Cap: { number }?,
	Accent: { number }?,
	Rainbow: boolean?,
}

export type Cue = {
	Id: string,
	Rarity: string,
	Group: string,
	Tradable: boolean,
	Sellable: boolean,
	Blocks: { string },
	Vaulted: boolean,
	Tier: string?,
	Effect: string,
	Look: Look,
}

local Catalog = {}

--- The default cue: always owned, never counted in the inventory, never sold or traded.
Catalog.Default = "Classic"

-- Every odds row the launch block cues drop from (each row drops the rarities it has odds
-- for): the whole ladder, so every cue of a rarity has an equal share in every row with that
-- rarity.
local ALL_ROWS: { string } = table.clone(Config.BlockOdds.Order)

-- A skinned cue's flat colours (CueSkins.Index, sampled from its colour map).
local function skinLook(id: string): Look
	local row = assert(SkinIndex[id], "Catalog: no cue skin for " .. id)
	return row.Look
end

local function blockCue(id: string, rarity: string): Cue
	return {
		Id = id,
		Rarity = rarity,
		Group = "Block",
		Tradable = true,
		Sellable = true,
		Blocks = ALL_ROWS,
		Vaulted = false,
		Effect = rarity,
		Look = skinLook(id),
	}
end

local function rankCue(id: string, tier: string, effect: string): Cue
	return {
		Id = id,
		-- One rarity for all ten (designer, 2026-10-08), each card in its tier's colours. The
		-- group stays Exclusive: trading, selling, the padlock and one copy each read Group.
		Rarity = "Ranked",
		Group = "Exclusive",
		Tradable = false, -- a Reyes Cue proves Reyes (ECONOMY 4.8)
		Sellable = false,
		Blocks = {},
		Vaulted = false,
		Tier = tier,
		Effect = effect,
		Look = skinLook(id),
	}
end

local function specialCue(id: string, group: string, effect: string, look: Look): Cue
	return {
		Id = id,
		Rarity = group,
		Group = group,
		-- Unique cues trade; of the Exclusive cues only the Starter Cue does (designer,
		-- 2026-09-29); it is still never sold back
		Tradable = group == "Unique" or id == "StarterCue",
		Sellable = false,
		Blocks = {},
		Vaulted = false,
		Effect = effect,
		-- A Unique cue keeps its placeholder bands until its skin is built; once the Index has
		-- the skin, the power-bar cue takes the skin's colours (designer, 2026-10-04).
		Look = if SkinIndex[id] then SkinIndex[id].Look else look,
	}
end

-- The rows, in the Index's order: Classic, then block cues bottom rarity first, then the
-- Exclusive and Unique groups.
local CUES: { Cue } = {
	{
		-- Shown as a Common (designer, 2026-09-30) but still everyone's free default: owned from
		-- the start, in no block, never traded or sold (Group "Default").
		Id = "Classic",
		Rarity = "Common",
		Group = "Default",
		Tradable = false,
		Sellable = false,
		Blocks = {},
		Vaulted = false,
		Effect = "Default",
		Look = {
			Shaft = { 214, 176, 124 },
			Forearm = { 86, 46, 34 },
			Wrap = { 32, 32, 36 },
			Ring = { 176, 180, 188 },
			Tip = { 34, 44, 74 },
			Cap = { 20, 20, 22 },
		},
	},
	-- Common (8, Classic counted): real cues from the real world: wood, carbon, lacquer.
	blockCue("MidnightCue", "Common"),
	blockCue("ArcticCue", "Common"),
	blockCue("CherryCue", "Common"),
	blockCue("CarbonCue", "Common"),
	blockCue("HeritageCue", "Common"),
	blockCue("MonarchCue", "Common"),
	blockCue("CobaltCue", "Common"),
	-- Uncommon (9): bold colours and patterns, one glowing ring.
	blockCue("GummyCue", "Uncommon"),
	blockCue("FlareCue", "Uncommon"),
	blockCue("HornetCue", "Uncommon"),
	blockCue("VenomCue", "Uncommon"),
	blockCue("LagoonCue", "Uncommon"),
	blockCue("SpliceCue", "Uncommon"),
	blockCue("CosmoCue", "Uncommon"),
	blockCue("GildedCue", "Uncommon"),
	blockCue("PixelCue", "Uncommon"),
	-- Rare (10): the first aura.
	blockCue("HoneycombCue", "Rare"),
	blockCue("NeonCue", "Rare"),
	blockCue("NatureCue", "Rare"),
	blockCue("CandyCue", "Rare"),
	blockCue("FrostbiteCue", "Rare"),
	blockCue("PlasmaCue", "Rare"),
	blockCue("BlazeCue", "Rare"),
	blockCue("PhantomCue", "Rare"),
	blockCue("TidalCue", "Rare"),
	blockCue("SakuraCue", "Rare"),
	-- Epic (9): a moving material and an aura.
	blockCue("VoidCue", "Epic"),
	blockCue("ShootingStarCue", "Epic"),
	blockCue("MagmaCue", "Epic"),
	blockCue("ToxicCue", "Epic"),
	blockCue("BloodMoonCue", "Epic"),
	blockCue("PrismCue", "Epic"),
	blockCue("AuroraCue", "Epic"),
	blockCue("DiscoCue", "Epic"),
	blockCue("HackedCue", "Epic"),
	-- Legendary (7): a stronger aura, its own ball trail and pocket finisher.
	blockCue("ChromaCue", "Legendary"),
	blockCue("ThunderstrikeCue", "Legendary"),
	blockCue("PhoenixCue", "Legendary"),
	blockCue("KrakenCue", "Legendary"),
	blockCue("SeraphCue", "Legendary"),
	blockCue("InfernalCue", "Legendary"),
	blockCue("ClockworkCue", "Legendary"),
	-- The Week One Cue (economy v5 plan section 5): a Legendary in no block (no rows, so no
	-- pool, reel, restock or odds list has it), given on the first week's day 7 (and by its
	-- Claim All). Tradable and sold back like any Legendary; counted in the Index's Legendary
	-- row. The default cue's look until its art exists (hand-off 11.4).
	{
		Id = "WeekOneCue",
		Rarity = "Legendary",
		Group = "Block",
		Tradable = true,
		Sellable = true,
		Blocks = {},
		Vaulted = false,
		Effect = "Legendary",
		Look = {
			Shaft = { 214, 176, 124 },
			Forearm = { 86, 46, 34 },
			Wrap = { 32, 32, 36 },
			Ring = { 176, 180, 188 },
			Tip = { 34, 44, 74 },
			Cap = { 20, 20, 22 },
		},
	},
	-- Mythic (3): a moving 3D piece and everything at full strength.
	blockCue("CelestialDragonCue", "Mythic"),
	blockCue("KitsuneCue", "Mythic"),
	blockCue("ApexCue", "Mythic"),
	-- Secret (1): one of a kind.
	blockCue("EclipseCue", "Secret"),
	-- Ranked (group Exclusive): the ten rank cues, in their tier colours (Reyes in the house
	-- rainbow).
	rankCue("BronzeCue", "Bronze", "Uncommon"),
	rankCue("SilverCue", "Silver", "Uncommon"),
	rankCue("GoldCue", "Gold", "Uncommon"),
	rankCue("PlatinumCue", "Platinum", "Rare"),
	rankCue("DiamondCue", "Diamond", "Rare"),
	rankCue("ExpertCue", "Expert", "Epic"),
	rankCue("VeteranCue", "Veteran", "Epic"),
	rankCue("MasterCue", "Master", "Epic"),
	rankCue("GrandmasterCue", "Grandmaster", "Legendary"),
	rankCue("ReyesCue", "Reyes", "Mythic"),
	-- Exclusive: VIP (rainbow) and the Starter Pack's cue.
	specialCue("VipCue", "Exclusive", "Legendary", skinLook("VipCue")),
	specialCue("StarterCue", "Exclusive", "Uncommon", skinLook("StarterCue")),
	-- Unique: numbered copies, only these two, both from the Grand Opening block (designer,
	-- 2026-10-05: there is no Founder's Cue, ever).
	-- The Grand Opening's Limited (placeholder colours until its skin: black shaft, gold
	-- rings, felt-green wrap; designer, 2026-10-03).
	specialCue("FireworkCue", "Unique", "Legendary", {
		Shaft = { 22, 22, 24 },
		Forearm = { 34, 34, 38 },
		Wrap = { 30, 110, 62 },
		Ring = { 255, 200, 60 },
		Accent = { 255, 200, 60 },
	}),
	specialCue("BetaCue", "Unique", "Epic", {
		Shaft = { 235, 230, 240 },
		Forearm = { 30, 30, 40 },
		Wrap = { 255, 92, 184 },
		Ring = { 255, 255, 255 },
		Accent = { 255, 92, 184 },
	}),
}

local byId: { [string]: Cue } = {}
for _, cue in CUES do
	assert(byId[cue.Id] == nil, "Catalog: duplicate cue id " .. cue.Id)
	byId[cue.Id] = cue
end

-- Rarity -> its place in the ladder (1 = Common ... 7 = Secret), for sorting.
local RARITY_ORDER: { [string]: number } = {}
for i, rarity in Config.BlockOdds.Rarities do
	RARITY_ORDER[rarity] = i
end
-- Outside the ladder: Exclusive halfway between Config.BlockOdds.ExclusiveRanksAbove and the next
-- rarity up (Epic 4.5 Legendary), Unique above them all, "Default" (no rarity) below them all.
RARITY_ORDER.Exclusive = assert(
	RARITY_ORDER[Config.BlockOdds.ExclusiveRanksAbove],
	"Catalog: ExclusiveRanksAbove names no rarity"
) + 0.5
-- Ranked (the rank cues) sorts where Exclusive does, ahead of VIP and Starter on the catalog tie.
RARITY_ORDER.Ranked = RARITY_ORDER.Exclusive
RARITY_ORDER.Unique = #Config.BlockOdds.Rarities + 1
RARITY_ORDER.Default = 0

--- Every cue, in the Index's order (Classic, block cues by rarity, Exclusive, Unique).
function Catalog.list(): { Cue }
	return CUES
end

--- A cue's row, or nil for an unknown id (anything that is not a known string).
function Catalog.get(id: any): Cue?
	if type(id) ~= "string" then
		return nil
	end
	return byId[id]
end

--- True for a known cue id.
function Catalog.exists(id: any): boolean
	return Catalog.get(id) ~= nil
end

--- A rarity's (or group's) place for sorting: 1 Common ... 7 Secret, 4.5 Ranked and Exclusive
--- (between Epic and Legendary), 8 Unique, 0 Default; unknown names 0.
function Catalog.rarityRank(rarity: string): number
	return RARITY_ORDER[rarity] or 0
end

--- The cues of one rarity or group, in catalog order ("Common", ..., "Ranked", "Exclusive",
--- "Unique").
function Catalog.ofRarity(rarity: string): { Cue }
	local list = {}
	for _, cue in CUES do
		if cue.Rarity == rarity then
			table.insert(list, cue)
		end
	end
	return list
end

--- The cues an odds row can drop at one rarity, in catalog order: block cues of that rarity
--- that list the row and are not vaulted. A block cue with no rows (the Week One Cue) drops
--- from nothing.
function Catalog.droppable(oddsId: string, rarity: string): { Cue }
	local list = {}
	-- The tables outside the ladder (Config.BlockOdds.Extra) roll the whole core pool: every
	-- block cue that drops from some row.
	local core = table.find(Config.BlockOdds.Extra or {}, oddsId) ~= nil
	for _, cue in CUES do
		if
			cue.Group == "Block"
			and cue.Rarity == rarity
			and not cue.Vaulted
			and ((core and #cue.Blocks > 0) or table.find(cue.Blocks, oddsId) ~= nil)
		then
			table.insert(list, cue)
		end
	end
	return list
end

--- The rank tier's cue id ("Gold" -> "GoldCue"), or nil.
function Catalog.tierCue(tier: string): string?
	for _, cue in CUES do
		if cue.Tier == tier then
			return cue.Id
		end
	end
	return nil
end

-- The house rainbow (UI_STYLE 4), for Look.Rainbow.
local RAINBOW = {
	{ 255, 77, 77 },
	{ 255, 159, 28 },
	{ 255, 225, 77 },
	{ 61, 214, 107 },
	{ 59, 155, 255 },
	{ 162, 89, 255 },
}

local FERRULE = { 242, 238, 226 }

local function darker(color: { number }, share: number): { number }
	return {
		math.floor(color[1] * share + 0.5),
		math.floor(color[2] * share + 0.5),
		math.floor(color[3] * share + 0.5),
	}
end

--- A cue's drawn style for CueArt (CueStickBuilder, PowerCue): the segments tip to butt, in
--- the same proportions as the Classic cue, coloured from the row's Look. An unknown id
--- draws as Classic.
function Catalog.style(id: string): any
	local cue = Catalog.get(id) or byId[Catalog.Default]
	local look = cue.Look
	local tip = look.Tip or { 34, 44, 74 }
	local cap = look.Cap or darker(look.Wrap, 0.6)
	local segments = {
		{ Length = 0.015, Color = tip },
		{ Length = 0.02, Color = FERRULE },
		{ Length = 0.48, Color = look.Shaft },
		{ Length = 0.025, Color = look.Ring },
	}
	if look.Rainbow then
		for _, color in RAINBOW do
			table.insert(segments, { Length = 0.22 / #RAINBOW, Color = color })
		end
	elseif look.Accent then
		table.insert(segments, { Length = 0.09, Color = look.Forearm })
		table.insert(segments, { Length = 0.04, Color = look.Accent })
		table.insert(segments, { Length = 0.09, Color = look.Forearm })
	else
		table.insert(segments, { Length = 0.22, Color = look.Forearm })
	end
	table.insert(segments, { Length = 0.015, Color = look.Ring })
	table.insert(segments, { Length = 0.17, Color = look.Wrap })
	table.insert(segments, { Length = 0.055, Color = cap })
	return { Segments = segments, TipWidth = 0.42, ButtWidth = 1 }
end

--- The house rainbow's colours (for thumbnails of Look.Rainbow cues).
function Catalog.rainbow(): { { number } }
	return RAINBOW
end

return Catalog
