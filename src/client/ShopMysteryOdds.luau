--!strict
-- ShopMysteryOdds: the Mystery Lucky Block's "Odds & Details" list (economy v4 plan 3.2 and 13,
-- the GUI hand-off item 13), shown in a menu's OddsDetails popup by a Mystery block's dice (the
-- Shop's Mystery card, the Free Reward days that give one): what Roblox's paid-random-items
-- rules ask for before buying, as the Cues menu's rarity bars (designer, 2026-10-08: the tiers
-- first, then pity, plainly; no description line):
-- - The final tier's chances (BlockDrop.tiers; live during the Grand Opening Luck), each bar
--   with its block's picture (the Secret, which has no block: the Mythic block darkened, as on
--   the climb screen's ladder).
-- - Pity as two meters (economy v5: Rare by the 10th, Epic by the 40th, exactly that rarity;
--   a new save starts at 2/10 and 10/40): "Rare guaranteed 3/10" and "Epic guaranteed 12/40",
--   the blocks opened since the last one of the count (the server's ShopState pity counts down
--   the blocks left: 1 is the very next). Once a guarantee is the very next block a gold line
--   says so and the tier bars show the live odds (the guaranteed tier).
-- - Each cue with its chance and "1 in N" (OddsDetails.cues): the tier a climb ends on is the
--   cue's rarity (economy v5).
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
local SECRET = Config.LuckyBlocks.Reveal.Secret
local D = Config.BlockOdds.Drop
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: string } = Strings.OddsDetails :: any
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local rgb = ShopCards.rgb

local ShopMysteryOdds = {}
ShopMysteryOdds.__index = ShopMysteryOdds

-- A pity meter's blocks opened of `count` (ShopState's pity counts down the blocks left: 1 is
-- the very next one, `count` none opened yet).
local function opened(left: any, count: number): number
	if type(left) ~= "number" then
		return 0
	end
	return math.clamp(count - math.floor(left), 0, count - 1)
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
				"Mystery|%s|%s|%s",
				tostring(if pity then pity.rare else nil),
				tostring(if pity then pity.epic else nil),
				tostring(BlockDrop.luckLive(workspace:GetServerTimeNow()))
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
	-- The final tier (with pity's floor while it is live), each bar with its block.
	d:add("Head", if floor then COPY.TiersLive else COPY.Tiers)
	-- Live during the Grand Opening Luck (economy v5; Roblox's live-odds rule).
	local luck = BlockDrop.luckLive(workspace:GetServerTimeNow())
	for _, tier in BlockDrop.tiers(floor, { luck = luck }) do
		local secret = tier.tier == "Secret"
		local row = KINDS[tier.tier]
		-- A Standard block wears Common's colours, as on the Mystery card.
		local look = if tier.tier == "Standard" then "Common" else tier.tier
		local icon = if secret then SECRET.Icon elseif row then row.Icon else nil
		d:bar(look, SHORT[tier.tier] or tier.tier, d:chance(tier.percent), icon)
		local bar = d.items[#d.items].bar
		if secret and bar and bar.icon then
			bar.icon.ImageColor3 = ShopCards.rgb(SECRET.Tint)
		end
	end
	-- Pity: two meters, then the live line once a guarantee is the very next block.
	d:add("Head", COPY.Pity)
	local left = if type(pity) == "table" then pity else {}
	local function meter(rarity: string, count: number, blocksLeft: any, word: string)
		local done = opened(blocksLeft, count)
		d:meter(rarity, word, COPY.PityCount:format(done, count), done / count)
	end
	meter("Rare", D.PityRare, left.rare, COPY.PityRare)
	meter("Epic", D.PityEpic, left.epic, COPY.PityEpic)
	if floor then
		d:add("Live", COPY.Live:format(SHORT[floor] or floor), rgb(O.LiveColor))
	end
	d:cues(BlockDrop.cueGroups(floor, { luck = luck }))
	d:finish()
end

return ShopMysteryOdds
