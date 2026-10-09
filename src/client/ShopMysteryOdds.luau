--!strict
-- ShopMysteryOdds: the Mystery Lucky Block's "Odds & Details" list (economy v4 plan 3.2 and 13,
-- the GUI hand-off item 13), shown in a menu's OddsDetails popup by a Mystery block's dice (the
-- Shop's Mystery card, the Free Reward days that give one): what Roblox's paid-random-items
-- rules ask for before buying, as the Cues menu's rarity bars (designer, 2026-10-08):
-- - "The result is decided when you open it; the presses reveal it."
-- - Pity: Rare or better within 10 and Epic or better within 100, each with the blocks to go
--   (the server's count, ShopState's pity). Once a guarantee is the very next block a gold line
--   says so and the bars under it show the live odds (the guaranteed tier, while it is live).
-- - The final tier's chances (BlockDrop.tiers), each bar with its block's picture.
-- - Each rarity's chance per Mystery block (BlockDrop.cueGroups), adding to 100%, and the line
--   that every cue in a rarity has the same odds.
-- Words in Strings.OddsDetails.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local GuiQA = require(script.Parent.GuiQA)
local ItemState = require(script.Parent.ItemState)
local ShopCards = require(script.Parent.ShopCards)

local O = Config.UI.OddsDetails
local D = Config.BlockOdds.Drop
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: string } = Strings.OddsDetails :: any
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local rgb = ShopCards.rgb

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
	d:add("Row", COPY.PityRare:format(D.PityRare), ShopCards.rarityColor("Rare"), toGo(left.rare))
	d:add("Row", COPY.PityEpic:format(D.PityEpic), ShopCards.rarityColor("Epic"), toGo(left.epic))
	-- The final tier (with pity's floor while it is live), each bar with its block.
	d:add("Head", if floor then COPY.TiersLive else COPY.Tiers)
	for _, tier in BlockDrop.tiers(floor) do
		local row = KINDS[tier.tier]
		-- A Standard block wears Common's colours, as on the Mystery card.
		local look = if tier.tier == "Standard" then "Common" else tier.tier
		local icon = if row then row.Icon else nil
		d:bar(look, SHORT[tier.tier] or tier.tier, d:chance(tier.percent), icon)
	end
	-- Each rarity per Mystery block (the next one's, with pity's floor while it is live).
	d:add("Head", if floor then COPY.RaritiesLive else COPY.Rarities)
	for _, group in BlockDrop.cueGroups(floor) do
		d:bar(group.rarity, RARITIES[group.rarity] or group.rarity, d:chance(group.percent))
	end
	d:finish()
end

return ShopMysteryOdds
