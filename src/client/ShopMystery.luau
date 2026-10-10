--!strict
-- ShopMystery: the Shop's Mystery Lucky Block card under "- BLOCKS -" (the designer's pick A on
-- the mock page, 2026-10-08). On a pale panel with its navy title pill: the block (its purple
-- glow, turning rays and twinkles; the dice opens its "Odds & Details", ShopMysteryOdds: the
-- blocks it turns into, pity and each cue's chance over both steps), the rows of the blocks it
-- can turn into with their chances (economy v5.1, BlockDrop.turnTiers: Standard to Legendary),
-- the small dice after each row's name opening that block's own odds, the same list as the
-- restock's (it climbs from its name; designer, 2026-10-09), the x1 and x5
-- columns (the purple gift square and the green Robux price, then the gold money price; on x5
-- "35 R$ one by one" and the launch bonus's "6 for 5!" ribbon while it runs) and the pity strip:
-- Rare by the 10th and Epic by the 40th side by side, each with its bar (the server's pity
-- counts). Money buys through ItemRequest "BuyBlocks" (the Mystery deal), Robux
-- through StoreRequest "Buy" (Mystery1, Mystery5); both are refused by the server where paid
-- random items are restricted, so the buttons are off there. Sizes in
-- Config.UI.ShopBlocks.Mystery, words in Strings.Menus.Shop.Blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local Format = require(Progression:WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local M = B.Mystery
local P = B.Panel
local DEAL = Config.Shop.Deals.Mystery
local DROP = Config.BlockOdds.Drop
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Blocks
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local BULK = Config.Shop.Mystery.BulkCount -- the bundle (x5 since economy v5)
local COUNTS = { 1, BULK }
local COLUMN_ONE_KEY: string = DEAL.Products[1] -- the single block's product (Mystery1)
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- Mystery1 or Mystery5
	money: (count: number) -> (), -- 1 or BULK for money (the Mystery deal)
	gift: (key: string) -> (), -- the gift square: gift that product to someone here
	odds: () -> (), -- the dice badge: the "Odds & Details" (ShopMysteryOdds)
	tierOdds: (kind: string) -> (), -- a tier row's dice: that tier block's odds
}

type Row = {
	strip: Frame,
	corner: UICorner,
	icon: ImageLabel,
	name: TextLabel,
	value: TextLabel,
	dice: ShopCards.Badge,
}
type Column = {
	box: ShopCards.Box,
	count: TextLabel,
	oneByOne: TextLabel?, -- the bundle's "35 R$ one by one"
	green: TextButton,
	gift: TextButton,
	gold: TextButton,
	key: string,
}
-- One half of the pity strip: a tier's icon, its words and its bar.
type PityHalf = {
	rarity: string,
	count: number, -- Config.BlockOdds.Drop's PityRare or PityEpic
	icon: ImageLabel,
	words: TextLabel,
	track: Frame,
	edge: UIStroke,
	fill: Frame,
}

local ShopMystery = {}
ShopMystery.__index = ShopMystery

--- Build the card (closed) into `parent` (the Shop's Blocks group).
function ShopMystery.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopMystery)
	self.actions = actions
	self.k = 1
	self.shown = {} :: { [string]: any } -- what refresh last drew
	self.fakePity = nil :: any -- Studio only: stand-in pity counts (ShopMenu's GuiQA "shopPity")

	local root = HudParts.frame(parent, "Mystery")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "MysteryPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "MysteryTitle", COPY.MysteryTitle)

	-- The block.
	local kind = KINDS.Mystery
	self.art = ShopCards.art(card, "MysteryBlock", kind.Icon, rgb(M.GlowTint), 4)
	self.badge = ShopCards.oddsBadge(self.art.holder, "OddsBadge", 8)
	-- A click, a tap or A on the badge opens the "Odds & Details" over the Shop (too much for
	-- a hover card).
	self.badge.hit.Activated:Connect(function()
		UISound.play("Click")
		actions.odds()
	end)

	-- The ladder of tiers.
	local ladder = ShopCards.inner(card, "MysteryLadder", 3)
	self.ladder = ladder
	self.rows = {} :: { Row }
	local count = rgb(Config.UI.Kit.Numbers.Count)
	for index, tier in BlockDrop.turnTiers() do
		local strip = HudParts.frame(ladder.frame, "Row" .. index)
		strip.BackgroundTransparency = 0
		strip.BackgroundColor3 = rgb(M.RowColor)
		strip.AnchorPoint = Vector2.new(0.5, 0.5)
		strip.ZIndex = 4
		local corner = HudParts.corner(strip, 0)
		local row = KINDS[tier.tier]
		local icon = ShopCards.image(strip, "Icon", if row then row.Icon else "", 5)
		local name = ShopCards.label(
			strip,
			"Name",
			SHORT[tier.tier] or tier.tier,
			ShopCards.rarityColor(tier.tier),
			5
		)
		name.AnchorPoint = Vector2.new(0, 0.5)
		name.TextXAlignment = Enum.TextXAlignment.Left
		local value = ShopCards.label(strip, "Percent", tier.display, count, 5)
		value.AnchorPoint = Vector2.new(1, 0.5)
		value.TextXAlignment = Enum.TextXAlignment.Right
		local dice = ShopCards.oddsBadge(strip, "OddsBadge", 6)
		local tierKind = tier.tier
		dice.hit.Activated:Connect(function()
			UISound.play("Click")
			actions.tierOdds(tierKind)
		end)
		table.insert(
			self.rows,
			{ strip = strip, corner = corner, icon = icon, name = name, value = value, dice = dice }
		)
	end

	-- The x1 and x5 columns.
	self.columns = {} :: { Column }
	for index, n in COUNTS do
		local key = DEAL.Products[n]
		local box = ShopCards.inner(card, "MysteryX" .. n, 3)
		local countLabel = ShopCards.label(
			box.frame,
			"Count",
			string.format(COPY.Count, n),
			rgb(Config.UI.Kit.Numbers.Money),
			5
		)
		local green = ShopCards.robuxButton(box.frame, "Robux" .. n, function()
			self.actions.robux(key)
		end)
		local gift = ShopCards.giftButton(green, function()
			self.actions.gift(key)
		end)
		local gold = ShopCards.moneyButton(box.frame, "Money" .. n, function()
			self.actions.money(n)
		end)
		local oneByOne = if n > 1
			then ShopCards.label(box.frame, "OneByOne", "", rgb(Config.UI.Kit.Numbers.Count), 5)
			else nil
		self.columns[index] = {
			box = box,
			count = countLabel,
			oneByOne = oneByOne,
			green = green,
			gift = gift,
			gold = gold,
			key = key,
		}
	end
	-- The launch bonus's ribbon on x5 ("6 for 5!"), its pill shaking (as the hero card's NEW
	-- tag).
	local ribbon =
		ShopCards.tag(self.columns[2].box.frame, "Ribbon", "", rgb(Config.UI.Kit.Colors.Red), 6)
	ribbon.holder.Visible = false
	self.ribbon = ribbon

	-- The pity strip: Rare by the 10th and Epic by the 40th, side by side.
	local pity = ShopCards.inner(card, "MysteryPity", 3)
	self.pity = pity
	self.halves = {} :: { PityHalf }
	local guarantees: { { rarity: string, count: number } } = {
		{ rarity = "Rare", count = DROP.PityRare },
		{ rarity = "Epic", count = DROP.PityEpic },
	}
	for _, guarantee in guarantees do
		local rarity, blocks = guarantee.rarity, guarantee.count
		local row = KINDS[rarity]
		local icon = ShopCards.image(pity.frame, rarity .. "Icon", if row then row.Icon else "", 4)
		local words = ShopCards.label(pity.frame, rarity .. "Words", "", nil, 4)
		words.AnchorPoint = Vector2.new(0, 0.5)
		words.TextXAlignment = Enum.TextXAlignment.Left
		words.RichText = true
		local track = HudParts.frame(pity.frame, rarity .. "Track")
		track.BackgroundTransparency = 0
		track.BackgroundColor3 = rgb(M.PityTrack)
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.ZIndex = 4
		HudParts.corner(track, 99)
		local edge = Instance.new("UIStroke")
		edge.Color = rgb(Config.UI.Kit.Colors.Ink)
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.Parent = track
		local fill = HudParts.frame(track, "Fill")
		fill.BackgroundTransparency = 0
		fill.BackgroundColor3 = ShopCards.rarityColor(rarity)
		fill.Size = UDim2.fromScale(0, 1)
		fill.ZIndex = 5
		HudParts.corner(fill, 99)
		table.insert(self.halves, {
			rarity = rarity,
			count = blocks,
			icon = icon,
			words = words,
			track = track,
			edge = edge,
			fill = fill,
		})
	end
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The card's height at the scale `k` (its title pill's top half, then the panel).
function ShopMystery.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + M.Units[2]) * k)
end

--- Lay the card out across `width` pixels at the scale `k`, its top `y` pixels down the page;
--- returns its height.
function ShopMystery.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local W, H = M.Units[1], M.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(W * k)
	local height = ShopMystery.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	local put = function(object: GuiObject, x: number, y: number, w: number, h: number)
		ShopCards.put(object, k, x, y, w, h)
	end
	put(self.panel.frame, W / 2, top + H / 2, W, H)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, W / 2, top)

	-- The block and its badge (the badge's place is in the panel's units; it sits in the
	-- block's holder, so it moves with the block).
	ShopCards.layoutArt(self.art, k, M.Block[1], M.Block[2], M.Block[3], M.Glow, M.Rays)
	local blockHalf = M.Block[3] / 2
	ShopCards.layoutBadge(
		self.badge,
		k,
		M.OddsBadge[1] - M.Block[1] + blockHalf,
		M.OddsBadge[2] - M.Block[2] + blockHalf,
		M.OddsBadge[3]
	)

	-- The ladder.
	local lx, ly, lw, lh = M.Ladder[1], M.Ladder[2], M.Ladder[3], M.Ladder[4]
	put(self.ladder.frame, lx + lw / 2, ly + lh / 2, lw, lh)
	ShopCards.sizeBox(self.ladder, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	local stripW = lw - 2 * M.RowInsetUnits
	local namePx = ShopCards.textPx(M.NameUnits, k)
	local valuePx = ShopCards.textPx(M.PercentUnits, k)
	local h, iconU = M.RowHeightUnits, M.IconUnits
	local nameLeft = M.RowIconLeftUnits + iconU + M.RowNameGapUnits
	-- Each row's dice sits just after its tier's name (designer, 2026-10-09).
	local diceU = M.RowDiceUnits
	local valueRight = M.ValueRightUnits
	local nameW = stripW - nameLeft - M.ValueUnits - valueRight - M.RowDiceGapUnits - diceU
	for index, row in self.rows do
		local cy = M.RowTop + h / 2 + (index - 1) * M.RowUnits
		put(row.strip, lw / 2, cy, stripW, h)
		row.corner.CornerRadius = UDim.new(0, round(M.RowCornerUnits * k))
		ShopCards.put(row.icon, k, M.RowIconLeftUnits + iconU / 2, h / 2, iconU, iconU)
		row.name.Position = UDim2.fromOffset(round(nameLeft * k), round(h / 2 * k))
		row.name.Size = UDim2.fromOffset(round(nameW * k), namePx + B.TextBoxPx)
		HudParts.setTextSize(row.name, namePx)
		row.value.Position = UDim2.fromOffset(round((stripW - valueRight) * k), round(h / 2 * k))
		row.value.Size = UDim2.fromOffset(round(M.ValueUnits * k), valuePx + B.TextBoxPx)
		HudParts.setTextSize(row.value, valuePx)
		local wordsU = math.min(nameW, ShopCards.measure(row.name.Text, namePx) / k)
		local diceX = nameLeft + wordsU + M.RowDiceGapUnits + diceU / 2
		ShopCards.layoutBadge(row.dice, k, diceX, h / 2, diceU)
	end

	-- The columns.
	local greenPx, goldPx = M.GreenTextUnits, M.GoldTextUnits
	for index, column in self.columns do
		local c = M.Columns[index]
		local cw, ch = c[3], c[4]
		put(column.box.frame, c[1] + cw / 2, c[2] + ch / 2, cw, ch)
		ShopCards.sizeBox(column.box, k, P.InnerCornerUnits, P.InnerEdgeUnits)
		local countPx = ShopCards.textPx(M.CountUnits, k)
		ShopCards.line(column.count, k, cw / 2, M.CountY, cw - 2 * M.CountSideUnits, countPx)
		if column.oneByOne then
			local notePx = ShopCards.textPx(M.OneByOneUnits, k)
			ShopCards.line(
				column.oneByOne,
				k,
				cw / 2,
				M.OneByOneY,
				cw - 2 * M.CountSideUnits,
				notePx
			)
		end
		local inner = cw - 2 * M.ButtonInsetUnits
		ShopCards.layoutRobuxRow(
			column.green,
			column.gift,
			k,
			cw / 2,
			M.GreenY,
			inner,
			M.GreenUnits,
			M.GiftUnits,
			M.GiftGapUnits,
			greenPx
		)
		ShopCards.layoutMoney(
			column.gold,
			k,
			cw / 2,
			M.GoldY,
			inner,
			M.GoldUnits,
			goldPx,
			M.CashIconShare
		)
	end
	local rw, rh = M.RibbonUnits[1], M.RibbonUnits[2]
	ShopCards.layoutTag(self.ribbon, k, M.Columns[2][3] / 2, M.RibbonY, rw, rh, M.RibbonTextUnits)

	-- The pity strip: each half its tier's icon, its words and its bar at its right end.
	local px, cy, pw, ph = M.Pity[1], M.Pity[2], M.Pity[3], M.Pity[4]
	put(self.pity.frame, px + pw / 2, cy, pw, ph)
	ShopCards.sizeBox(self.pity, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	local pityIconU = M.PityIconUnits
	local textPx = ShopCards.textPx(M.PityTextUnits, k)
	local barW, barH = M.PityBar[1], M.PityBar[2]
	local halfW = pw / #self.halves
	for index, half in self.halves do
		local left = (index - 1) * halfW
		ShopCards.put(
			half.icon,
			k,
			left + M.PityIconLeftUnits + pityIconU / 2,
			ph / 2,
			pityIconU,
			pityIconU
		)
		local textLeft = left + M.PityIconLeftUnits + pityIconU + M.PityTextGapUnits
		local barRight = left + halfW - M.PityBarRightUnits
		local textW = barRight - barW - M.PityBarGapUnits - textLeft
		half.words.Position = UDim2.fromOffset(round(textLeft * k), round(ph / 2 * k))
		half.words.Size = UDim2.fromOffset(round(textW * k), textPx + B.TextBoxPx)
		HudParts.setTextSize(half.words, textPx)
		half.track.Position = UDim2.fromOffset(round(barRight * k), round(ph / 2 * k))
		half.track.Size =
			UDim2.fromOffset(round(barW * k), math.max(M.MinPityBarPx, round(barH * k)))
		half.edge.Thickness = math.max(B.MinEdgePx, M.PityTrackEdgeUnits * k)
	end
	return height
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

-- Set a text only when it changed (refresh runs a few times a second).
local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

--- Draw the shop state: the live Robux prices, the money prices, the launch bonus, the
--- guarantee and whether this player may buy paid random items at all.
function ShopMystery.refresh(self: any, state: any)
	if type(state) ~= "table" then
		return
	end
	local products = if type(state.products) == "table" then state.products else {}
	local mystery = if type(state.mystery) == "table" then state.mystery else {}
	local bonus = if type(state.launchBonus) == "table" then state.launchBonus else {}
	local restricted = state.restricted == true
	-- The live Robux price (ShopState: what Roblox charges this player).
	local function robuxOf(key: string): number
		local product = products[key]
		return if type(product) == "table" and type(product.robux) == "number"
			then product.robux
			else (Config.Products.List :: any)[key].Robux
	end
	for index, column in self.columns do
		local n = COUNTS[index]
		local product = products[column.key]
		local words = ShopCards.robuxText(robuxOf(column.key))
		if self.shown["robux" .. n] ~= words then
			self.shown["robux" .. n] = words
			ShopCards.setButtonWords(column.green, words)
		end
		-- The bundle's saving: the single block's price times its count, never crossed out.
		if column.oneByOne then
			local single = robuxOf(COLUMN_ONE_KEY)
			setText(
				column.oneByOne,
				string.format((Strings :: any).ShopV4.OneByOne, Format.commas(single * n))
			)
		end
		-- Off sale (Roblox says so, or its product is not made): the price shows, greyed.
		local offSale = (type(product) == "table" and product.available == false)
			or (Config.Products.List :: any)[column.key].Id == 0
		local money = if n == 1
			then (if type(mystery.price) == "number" then mystery.price else DEAL.Money[1])
			else (if type(mystery.bulkPrice) == "number"
				then mystery.bulkPrice
				else DEAL.Money[BULK])
		local cash = Format.money(money)
		if self.shown["money" .. n] ~= cash then
			self.shown["money" .. n] = cash
			HudParts.setText(column.gold, cash)
		end
		local robuxOn = not restricted and not offSale
		if self.shown["on" .. n] ~= robuxOn then
			self.shown["on" .. n] = robuxOn
			HudParts.setEnabled(column.green, robuxOn)
			HudParts.setEnabled(column.gift, robuxOn)
		end
		if self.shown.restricted ~= restricted then
			HudParts.setEnabled(column.gold, not restricted)
		end
	end
	self.shown.restricted = restricted
	-- "6 for 5!" while the launch bonus runs.
	local bonusOn = bonus.open == true
		and type(bonus.bulkCount) == "number"
		and bonus.bulkCount > BULK
	self.ribbon.holder.Visible = bonusOn
	if bonusOn then
		setText(self.ribbon.words, string.format(COPY.Bonus, bonus.bulkCount, BULK))
	end
	-- Pity: blocks left until each guarantee (1: the next one is; a new save starts part way:
	-- Config.BlockOdds.Drop.PityStart), each bar filled by the blocks opened since.
	local pity = self.fakePity or (if type(state.pity) == "table" then state.pity else {})
	self.pity.frame.Visible = type(pity.rare) == "number" or type(pity.epic) == "number"
	for _, half in self.halves do
		local raw = if half.rarity == "Rare" then pity.rare else pity.epic
		local left = if type(raw) == "number" then math.max(1, math.floor(raw)) else half.count
		local hex = ShopCards.rarityColor(half.rarity):ToHex()
		local name =
			string.format('<font color="#%s">%s</font>', hex, SHORT[half.rarity] or half.rarity)
		setText(
			half.words,
			if left <= 1
				then string.format(COPY.PityNext, name)
				else string.format(COPY.Pity, name, left)
		)
		local share = math.clamp((half.count - left) / math.max(1, half.count - 1), 0, 1)
		local want = UDim2.fromScale(share, 1)
		if half.fill.Size ~= want then
			half.fill.Size = want
		end
	end
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds a piece's idle loops (started as it lands) until the Shop closes.
function ShopMystery.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	stage:add("MysteryPanel", self.panel.frame)
	stage:add("MysteryTitle", self.title.pill)
	stage:add("MysteryBlock", self.art.holder, function()
		keep(ShopCards.artLoops(self.art))
	end)
	stage:add("MysteryLadder", self.ladder.frame)
	for index, row in self.rows do
		stage:add("MysteryRow" .. index, row.strip)
	end
	for index, column in self.columns do
		local n = COUNTS[index]
		stage:add("MysteryX" .. n, column.box.frame)
		stage:add("MysteryRobux" .. n, column.green, function()
			keep(
				ShopCards.buttonShine(
					column.green,
					B.ButtonShineEvery,
					(index - 1) * B.ShineStaggerSeconds
				)
			)
		end)
		-- The money buttons never shine (designer, 2026-10-06: only the Robux options).
		stage:add("MysteryMoney" .. n, column.gold)
	end
	stage:add("MysteryRibbon", self.ribbon.holder, function()
		keep(UIAnim.shake(self.ribbon.pill, "Text"))
	end)
	stage:add("MysteryPity", self.pity.frame)
end

--- The Shop closed (its "Odds & Details" is the Shop's, closed with it).
function ShopMystery.closed(_self: any) end

return ShopMystery
