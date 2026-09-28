--!strict
-- The cue catalog (GDD section 12, ECONOMY sections 6 and 18): every cue in the game as a data
-- row, plus small lookups. Like Config it is data: adding a cue is adding a row (and its name in
-- Strings.Items.Cues), never code. Pure: no Instances, and every list here is an array walked
-- in order, so nothing depends on hash order.
--
-- A row:
--   Id        stable catalog id (saved; never renamed)
--   Rarity    Common ... Secret for case cues; "Exclusive", "Unique", or "Default" (Classic)
--   Group     "Case" (drops from cases), "Exclusive" (one special way each), "Unique"
--             (numbered Limited copies) or "Default"
--   Tradable  may be traded (trading is a later session; the flag is stored now)
--   Sellable  may be sold back (case cues only)
--   Cases     the case ids that drop it (case cues only)
--   Vaulted   true stops it dropping (ECONOMY 12); it stays in the Index and in saves
--   Tier      the rank tier whose reward it is (rank cues)
--   Effect    the Config.Effects.Styles name that gives its trail and pocket burst
--   Look      placeholder colours (CueStickBuilder, PowerCue and the thumbnails): Shaft,
--             Forearm, Wrap, Ring, and optional Tip, Cap, Accent (a band in the forearm) and
--             Rainbow (the forearm in the house rainbow, for the VIP and Reyes cues). Real
--             models later only change the rows.
--
-- Placeholder names and looks (2026-09-28, overnight): listed in the morning report.
local Config = require(script.Parent.Parent.Config)

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
	Cases: { string },
	Vaulted: boolean,
	Tier: string?,
	Effect: string,
	Look: Look,
}

local Catalog = {}

--- The default cue: always owned, never counted in the inventory, never sold or traded.
Catalog.Default = "Classic"

-- Every case the launch case cues drop from (each case drops the rarities it has odds for).
local ALL_CASES = { "Standard", "Rare", "Epic", "Legendary", "Event" }

local function caseCue(id: string, rarity: string, look: Look): Cue
	return {
		Id = id,
		Rarity = rarity,
		Group = "Case",
		Tradable = true,
		Sellable = true,
		Cases = ALL_CASES,
		Vaulted = false,
		Effect = rarity,
		Look = look,
	}
end

local function rankCue(id: string, tier: string, effect: string, look: Look): Cue
	return {
		Id = id,
		Rarity = "Exclusive",
		Group = "Exclusive",
		Tradable = false, -- a Reyes Cue proves Reyes (ECONOMY 4.8)
		Sellable = false,
		Cases = {},
		Vaulted = false,
		Tier = tier,
		Effect = effect,
		Look = look,
	}
end

local function specialCue(id: string, group: string, effect: string, look: Look): Cue
	return {
		Id = id,
		Rarity = group,
		Group = group,
		Tradable = true, -- VIP, Starter and Unique cues trade (ECONOMY 6)
		Sellable = false,
		Cases = {},
		Vaulted = false,
		Effect = effect,
		Look = look,
	}
end

-- Tier cue looks: the forearm in the tier's colour, a dark wrap, a light ring.
local function tierLook(
	forearm: { number },
	wrap: { number },
	ring: { number },
	accent: { number }?
): Look
	return {
		Shaft = { 232, 214, 180 },
		Forearm = forearm,
		Wrap = wrap,
		Ring = ring,
		Accent = accent,
	}
end

-- The rows, in the Index's order: Classic, then case cues bottom rarity first, then the
-- Exclusive and Unique groups.
local CUES: { Cue } = {
	{
		Id = "Classic",
		Rarity = "Default",
		Group = "Default",
		Tradable = false,
		Sellable = false,
		Cases = {},
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
	-- Common (7): plain woods and soft colours.
	caseCue("ChalkDust", "Common", {
		Shaft = { 230, 226, 214 },
		Forearm = { 120, 160, 200 },
		Wrap = { 60, 70, 90 },
		Ring = { 200, 205, 215 },
		Tip = { 70, 110, 190 },
	}),
	caseCue("CornerPocket", "Common", {
		Shaft = { 214, 176, 124 },
		Forearm = { 40, 40, 44 },
		Wrap = { 30, 30, 32 },
		Ring = { 176, 180, 188 },
	}),
	caseCue("RooftopBreeze", "Common", {
		Shaft = { 220, 200, 160 },
		Forearm = { 150, 190, 210 },
		Wrap = { 70, 90, 110 },
		Ring = { 230, 230, 235 },
	}),
	caseCue("RackRunner", "Common", {
		Shaft = { 210, 170, 120 },
		Forearm = { 140, 60, 40 },
		Wrap = { 40, 36, 34 },
		Ring = { 200, 170, 90 },
	}),
	caseCue("SideSpin", "Common", {
		Shaft = { 225, 205, 170 },
		Forearm = { 90, 90, 100 },
		Wrap = { 160, 40, 40 },
		Ring = { 220, 220, 225 },
	}),
	caseCue("FeltGreen", "Common", {
		Shaft = { 215, 185, 140 },
		Forearm = { 30, 110, 70 },
		Wrap = { 20, 50, 35 },
		Ring = { 200, 200, 200 },
	}),
	caseCue("BankShot", "Common", {
		Shaft = { 200, 160, 110 },
		Forearm = { 95, 60, 40 },
		Wrap = { 180, 150, 90 },
		Ring = { 60, 60, 60 },
	}),
	-- Uncommon (6): brighter, a coloured ring.
	caseCue("Skyline", "Uncommon", {
		Shaft = { 235, 225, 205 },
		Forearm = { 70, 120, 200 },
		Wrap = { 30, 40, 70 },
		Ring = { 255, 210, 90 },
		Accent = { 255, 255, 255 },
	}),
	caseCue("TikiTorch", "Uncommon", {
		Shaft = { 220, 180, 120 },
		Forearm = { 200, 90, 40 },
		Wrap = { 80, 40, 20 },
		Ring = { 255, 190, 60 },
	}),
	caseCue("PalmShade", "Uncommon", {
		Shaft = { 225, 210, 170 },
		Forearm = { 60, 170, 100 },
		Wrap = { 30, 80, 50 },
		Ring = { 240, 220, 120 },
	}),
	caseCue("SunsetRail", "Uncommon", {
		Shaft = { 240, 215, 180 },
		Forearm = { 240, 120, 80 },
		Wrap = { 120, 50, 90 },
		Ring = { 255, 200, 120 },
	}),
	caseCue("KickShot", "Uncommon", {
		Shaft = { 230, 220, 200 },
		Forearm = { 240, 240, 245 },
		Wrap = { 60, 190, 120 },
		Ring = { 40, 40, 50 },
	}),
	caseCue("CushionCrusher", "Uncommon", {
		Shaft = { 210, 190, 160 },
		Forearm = { 120, 60, 160 },
		Wrap = { 40, 30, 60 },
		Ring = { 200, 200, 210 },
	}),
	-- Rare (6): bold colours with an accent band.
	caseCue("HarborLights", "Rare", {
		Shaft = { 240, 235, 220 },
		Forearm = { 20, 60, 140 },
		Wrap = { 10, 20, 50 },
		Ring = { 255, 220, 100 },
		Accent = { 80, 200, 255 },
	}),
	caseCue("Masse", "Rare", {
		Shaft = { 245, 240, 230 },
		Forearm = { 230, 60, 60 },
		Wrap = { 30, 30, 40 },
		Ring = { 255, 255, 255 },
		Accent = { 255, 255, 255 },
	}),
	caseCue("NeonPocket", "Rare", {
		Shaft = { 40, 40, 50 },
		Forearm = { 40, 255, 200 },
		Wrap = { 20, 20, 30 },
		Ring = { 255, 60, 200 },
		Tip = { 40, 255, 200 },
	}),
	caseCue("OceanBreak", "Rare", {
		Shaft = { 220, 240, 250 },
		Forearm = { 30, 150, 220 },
		Wrap = { 10, 70, 120 },
		Ring = { 230, 250, 255 },
		Accent = { 255, 255, 255 },
	}),
	caseCue("RailRider", "Rare", {
		Shaft = { 235, 215, 180 },
		Forearm = { 50, 110, 230 },
		Wrap = { 240, 240, 240 },
		Ring = { 255, 200, 40 },
	}),
	caseCue("Tidewater", "Rare", {
		Shaft = { 210, 235, 240 },
		Forearm = { 20, 120, 130 },
		Wrap = { 10, 50, 60 },
		Ring = { 140, 230, 230 },
		Accent = { 140, 230, 230 },
	}),
	-- Epic (5): strong contrasts.
	caseCue("ThunderBreak", "Epic", {
		Shaft = { 40, 40, 60 },
		Forearm = { 255, 220, 40 },
		Wrap = { 30, 30, 40 },
		Ring = { 160, 90, 255 },
		Accent = { 255, 255, 255 },
		Tip = { 255, 220, 40 },
	}),
	caseCue("VioletVortex", "Epic", {
		Shaft = { 230, 210, 255 },
		Forearm = { 140, 60, 230 },
		Wrap = { 60, 20, 110 },
		Ring = { 255, 120, 230 },
		Accent = { 255, 255, 255 },
	}),
	caseCue("Penthouse", "Epic", {
		Shaft = { 20, 20, 24 },
		Forearm = { 230, 230, 235 },
		Wrap = { 20, 20, 24 },
		Ring = { 255, 200, 60 },
		Accent = { 20, 20, 24 },
	}),
	caseCue("Nightcap", "Epic", {
		Shaft = { 30, 30, 60 },
		Forearm = { 70, 50, 150 },
		Wrap = { 15, 15, 35 },
		Ring = { 180, 220, 255 },
		Accent = { 255, 255, 255 },
	}),
	caseCue("JumpJet", "Epic", {
		Shaft = { 240, 240, 245 },
		Forearm = { 255, 80, 60 },
		Wrap = { 40, 40, 50 },
		Ring = { 255, 200, 40 },
		Accent = { 255, 255, 255 },
	}),
	-- Legendary (3): gold and fire.
	caseCue("GoldenBreak", "Legendary", {
		Shaft = { 255, 230, 150 },
		Forearm = { 242, 178, 0 },
		Wrap = { 120, 70, 0 },
		Ring = { 255, 255, 220 },
		Accent = { 255, 245, 200 },
		Tip = { 242, 178, 0 },
	}),
	caseCue("SolarFlare", "Legendary", {
		Shaft = { 255, 210, 120 },
		Forearm = { 255, 110, 20 },
		Wrap = { 160, 30, 20 },
		Ring = { 255, 240, 120 },
		Accent = { 255, 220, 60 },
	}),
	caseCue("CrownJewel", "Legendary", {
		Shaft = { 250, 240, 210 },
		Forearm = { 140, 20, 60 },
		Wrap = { 40, 10, 20 },
		Ring = { 255, 200, 40 },
		Accent = { 255, 215, 80 },
	}),
	-- Mythic (2): the pale holographic shimmer on deep space (UI_STYLE 4).
	caseCue("Starfall", "Mythic", {
		Shaft = { 220, 240, 255 },
		Forearm = { 26, 20, 70 },
		Wrap = { 183, 156, 255 },
		Ring = { 127, 231, 255 },
		Accent = { 255, 156, 230 },
		Tip = { 127, 231, 255 },
	}),
	caseCue("Nebula", "Mythic", {
		Shaft = { 240, 220, 255 },
		Forearm = { 60, 30, 120 },
		Wrap = { 26, 20, 70 },
		Ring = { 255, 156, 230 },
		Accent = { 127, 231, 255 },
		Tip = { 183, 156, 255 },
	}),
	-- Secret (1): near-black with red (UI_STYLE 4's open suggestion).
	caseCue("Eclipse", "Secret", {
		Shaft = { 20, 18, 22 },
		Forearm = { 10, 8, 10 },
		Wrap = { 140, 0, 20 },
		Ring = { 255, 40, 50 },
		Accent = { 255, 255, 255 },
		Tip = { 255, 40, 50 },
	}),
	-- Exclusive: the ten rank cues, in their tier colours (Reyes in the house rainbow).
	rankCue(
		"BronzeCue",
		"Bronze",
		"Uncommon",
		tierLook({ 205, 127, 70 }, { 90, 50, 25 }, { 240, 200, 160 })
	),
	rankCue(
		"SilverCue",
		"Silver",
		"Uncommon",
		tierLook({ 170, 182, 200 }, { 70, 76, 90 }, { 240, 245, 255 })
	),
	rankCue(
		"GoldCue",
		"Gold",
		"Uncommon",
		tierLook({ 255, 196, 40 }, { 130, 90, 10 }, { 255, 250, 210 })
	),
	rankCue(
		"PlatinumCue",
		"Platinum",
		"Rare",
		tierLook({ 120, 176, 230 }, { 40, 70, 110 }, { 230, 245, 255 })
	),
	rankCue(
		"DiamondCue",
		"Diamond",
		"Rare",
		tierLook({ 60, 214, 230 }, { 10, 90, 110 }, { 220, 255, 255 })
	),
	rankCue(
		"ExpertCue",
		"Expert",
		"Epic",
		tierLook({ 232, 64, 72 }, { 90, 20, 25 }, { 255, 200, 60 })
	),
	rankCue(
		"VeteranCue",
		"Veteran",
		"Epic",
		tierLook({ 64, 196, 96 }, { 20, 80, 40 }, { 255, 200, 60 })
	),
	rankCue(
		"MasterCue",
		"Master",
		"Epic",
		tierLook({ 158, 92, 230 }, { 60, 30, 100 }, { 255, 200, 60 })
	),
	rankCue(
		"GrandmasterCue",
		"Grandmaster",
		"Legendary",
		tierLook({ 60, 56, 70 }, { 20, 18, 24 }, { 255, 196, 40 }, { 255, 196, 40 })
	),
	rankCue("ReyesCue", "Reyes", "Mythic", {
		Shaft = { 245, 240, 230 },
		Forearm = { 255, 255, 255 },
		Wrap = { 30, 30, 40 },
		Ring = { 255, 255, 255 },
		Rainbow = true,
	}),
	-- Exclusive: VIP (rainbow) and the Starter Pack's cue.
	specialCue("VipCue", "Exclusive", "Legendary", {
		Shaft = { 250, 245, 235 },
		Forearm = { 255, 255, 255 },
		Wrap = { 27, 32, 51 },
		Ring = { 255, 215, 80 },
		Rainbow = true,
	}),
	specialCue("StarterCue", "Exclusive", "Uncommon", {
		Shaft = { 230, 215, 185 },
		Forearm = { 59, 155, 255 },
		Wrap = { 255, 201, 40 },
		Ring = { 255, 255, 255 },
	}),
	-- Unique: numbered Limited copies (the Limited shelf, Config.Shop.Limited).
	specialCue("FoundersCue", "Unique", "Legendary", {
		Shaft = { 250, 235, 245 },
		Forearm = { 255, 92, 184 },
		Wrap = { 40, 20, 40 },
		Ring = { 255, 215, 80 },
		Accent = { 255, 255, 255 },
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
for i, rarity in Config.Cases.Rarities do
	RARITY_ORDER[rarity] = i
end
-- Outside the ladder: shown after it (Exclusive, then Unique), Classic first of all.
RARITY_ORDER.Exclusive = #Config.Cases.Rarities + 1
RARITY_ORDER.Unique = #Config.Cases.Rarities + 2
RARITY_ORDER.Default = 0

--- Every cue, in the Index's order (Classic, case cues by rarity, Exclusive, Unique).
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

--- A rarity's (or group's) place for sorting: 1 Common ... 7 Secret, 8 Exclusive, 9
--- Unique, 0 Default; unknown names 0.
function Catalog.rarityRank(rarity: string): number
	return RARITY_ORDER[rarity] or 0
end

--- The cues of one rarity or group, in catalog order ("Common", ..., "Exclusive", "Unique").
function Catalog.ofRarity(rarity: string): { Cue }
	local list = {}
	for _, cue in CUES do
		if cue.Rarity == rarity then
			table.insert(list, cue)
		end
	end
	return list
end

--- The cues a case can drop at one rarity, in catalog order: case cues of that rarity that
--- list the case and are not vaulted.
function Catalog.droppable(caseId: string, rarity: string): { Cue }
	local list = {}
	for _, cue in CUES do
		if
			cue.Group == "Case"
			and cue.Rarity == rarity
			and not cue.Vaulted
			and table.find(cue.Cases, caseId)
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
