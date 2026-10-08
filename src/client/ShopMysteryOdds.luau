--!strict
-- ShopMysteryOdds: the Mystery Lucky Block's "Odds & Details" list (economy v4 plan 3.2 and 13,
-- the GUI hand-off item 13), shown in a menu's OddsDetails popup by a Mystery block's dice (the
-- Shop's Mystery card, the Free Reward days that give one):
-- every number Roblox's paid-random-items rules ask for before buying (the block is nested: a
-- tier block, then a cue):
-- - "The result is decided when you open it; the presses reveal it."
-- - Pity: Rare or better within 10 and Epic or better within 100, each with the blocks to go
--   (the server's count, ShopState's pity). Once a guarantee is the very next block a gold line
--   says so and the tables under it show the live odds (the guaranteed tier, while it is live).
-- - The final tier's chances (BlockDrop.tiers), each with its block's picture.
-- - Each tier block's odds (BlockOdds.odds of each tier's row).
-- - The cues: each rarity's named once (every tier block draws a rarity from the same cues).
-- - Each rarity's chance per Mystery block with each of its cues' (BlockDrop.cueGroups),
--   adding to 100%.
-- Chances under OneInUnderPercent show "1 in N" beside them (BlockOdds.oneIn, rounded up so it
-- never looks better than true); long ones are rounded to 5 significant digits with a line
-- saying so (BlockOdds.detailText). Words in Strings.OddsDetails.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local GuiQA = require(script.Parent.GuiQA)
local ItemState = require(script.Parent.ItemState)
local OddsDetails = require(script.Parent.OddsDetails)
local ShopCards = require(script.Parent.ShopCards)

local O = Config.UI.OddsDetails
local D = Config.BlockOdds.Drop
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: string } = Strings.OddsDetails :: any
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local rgb = ShopCards.rgb
local oneInText = OddsDetails.oneInText

local ShopMysteryOdds = {}
ShopMysteryOdds.__index = ShopMysteryOdds

-- The blocks to go before a guarantee (ShopState's pity: 1 is the very next block).
local function toGo(left: any): string
	if type(left) ~= "number" then
		return ""
	end
	return if left <= 1 then COPY.Next else COPY.ToGo:format(math.floor(left))
end

--- The Mystery block's list for a menu's OddsDetails `popup` (popup:block("Mystery") shows it).
--- `qa`: the Studio hook's name, for the one menu that has it.
function ShopMysteryOdds.new(popup: any, qa: string?): any
	local self: any = setmetatable({}, ShopMysteryOdds)
	self.popup = popup
	self.fakePity = nil :: any -- the Studio hook's stand-in pity
	local mystery = KINDS.Mystery
	self.spec = {
		icon = if mystery then mystery.Icon else nil,
		key = function(): string
			local pity = self:pity()
			return string.format(
				"Mystery|%s|%s",
				tostring(if pity then pity.rare else nil),
				tostring(if pity then pity.epic else nil)
			)
		end,
		paint = function(d: any)
			self:paint(d)
		end,
		closed = function()
			self.fakePity = nil
		end,
	}
	popup:provide("Mystery", self.spec)
	-- Studio only: GuiQA:Invoke(qa, rare?, epic?) opens it as if that many blocks were left to
	-- each guarantee (1: the very next; nothing: the server's count).
	if qa then
		GuiQA.add(qa, function(rare: number?, epic: number?)
			self.fakePity = if rare or epic
				then { rare = rare or D.PityRare, epic = epic or D.PityEpic }
				else nil
			self:open()
			return #popup.items
		end)
	end
	return self
end

--- Open the list (the Mystery card's dice).
function ShopMysteryOdds.open(self: any)
	self.popup:show(self.spec)
end

-- The pity counts shown: the Studio hook's, else the server's.
function ShopMysteryOdds.pity(self: any): any
	if self.fakePity then
		return self.fakePity
	end
	local state = ItemState.shop()
	return if type(state) == "table" and type(state.pity) == "table" then state.pity else nil
end

-- Fill the popup `d` for the pity counts now.
function ShopMysteryOdds.paint(self: any, d: any)
	local pity = self:pity()
	local floor = BlockDrop.floorOf(pity)
	d:add("Note", Strings.LuckyBlocks.Reveal.Decided)
	-- Pity, with the live line once a guarantee is the very next block.
	d:add("Head", COPY.Pity)
	if floor then
		d:add("Live", COPY.Live:format(SHORT[floor] or floor), rgb(O.LiveColor))
	end
	local left = if type(pity) == "table" then pity else {}
	d:add(
		"Row",
		COPY.PityRare:format(D.PityRare),
		ShopCards.rarityColor("Rare"),
		"",
		toGo(left.rare)
	)
	d:add(
		"Row",
		COPY.PityEpic:format(D.PityEpic),
		ShopCards.rarityColor("Epic"),
		"",
		toGo(left.epic)
	)
	-- The final tier (with pity's floor while it is live).
	d:add("Head", if floor then COPY.TiersLive else COPY.Tiers)
	for _, tier in BlockDrop.tiers(floor) do
		local row = KINDS[tier.tier]
		d:add(
			"Row",
			SHORT[tier.tier] or tier.tier,
			ShopCards.rarityColor(tier.tier),
			oneInText(tier.percent),
			d:chance(tier.percent),
			if row then row.Icon else nil
		)
	end
	-- Each tier block's own odds.
	d:add("Head", COPY.Blocks)
	for _, tier in BlockDrop.tiers() do
		local row = KINDS[tier.tier]
		d:add(
			"Sub",
			NAMES[tier.tier] or tier.tier,
			ShopCards.rarityColor(tier.tier),
			nil,
			nil,
			if row then row.Icon else nil
		)
		for _, odds in BlockOdds.odds(tier.tier) do
			d:add(
				"Row",
				RARITIES[odds.rarity] or odds.rarity,
				ShopCards.rarityColor(odds.rarity),
				oneInText(odds.percent),
				d:chance(odds.percent)
			)
		end
	end
	-- The cues, each rarity's once.
	local groups = BlockDrop.cueGroups(floor)
	d:add("Head", COPY.Cues)
	for _, group in groups do
		d:add("Sub", RARITIES[group.rarity] or group.rarity, ShopCards.rarityColor(group.rarity))
		d:add("Names", table.concat(OddsDetails.names(group), COPY.NameJoin))
	end
	-- Each rarity per Mystery block with each cue's chance (the next one's, with pity's floor
	-- while it is live).
	d:add("Head", if floor then COPY.RaritiesLive else COPY.Rarities)
	local total = 0
	for _, group in groups do
		d:add(
			"Row",
			RARITIES[group.rarity] or group.rarity,
			ShopCards.rarityColor(group.rarity),
			oneInText(group.percent),
			d:chance(group.percent)
		)
		local line = d:cuesLine(group, false)
		if line then
			d:add("Names", line)
		end
		total += group.percent
	end
	d:finish(total)
end

return ShopMysteryOdds
