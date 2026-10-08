--!strict
-- ShopMystery: the Shop's Mystery Lucky Block card under "- BLOCKS -" (the designer's pick A on
-- the mock page, 2026-10-08). On a pale panel with its navy title pill: the block (its purple
-- glow, turning rays and twinkles; the sky-blue "i" opens every rarity's chance per Mystery
-- block, adding up to 100%), the ladder of the six tiers it can climb to with their chances
-- (BlockDrop.tiers: it starts Standard and climbs on the upgrade screen's presses), the x1 and x10
-- columns (the purple gift square and the green Robux price, then the gold money price; the
-- launch bonus's "13 for 10!" ribbon on x10 while it runs) and the Epic guarantee strip (the
-- server's pity count). Money buys through ItemRequest "BuyBlocks" (the Mystery deal), Robux
-- through StoreRequest "Buy" (Mystery1, Mystery10); both are refused by the server where paid
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
local ShopOdds = require(script.Parent.ShopOdds)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local M = B.Mystery
local P = B.Panel
local DEAL = Config.Shop.Deals.Mystery
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Blocks
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local BULK = Config.Shop.Mystery.BulkCount -- the x10 deal
local COUNTS = { 1, BULK }
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- Mystery1 or Mystery10
	money: (count: number) -> (), -- 1 or BULK for money (the Mystery deal)
	gift: (key: string) -> (), -- the gift square: gift that product to someone here
}

type Row = {
	strip: Frame,
	corner: UICorner,
	icon: ImageLabel,
	name: TextLabel,
	value: TextLabel,
}
type Column = {
	box: ShopCards.Box,
	count: TextLabel,
	green: TextButton,
	gift: TextButton,
	gold: TextButton,
	key: string,
}

local ShopMystery = {}
ShopMystery.__index = ShopMystery

--- Every rarity's chance per Mystery block (the tier roll times each tier's row), bottom first.
local function outcomes(): { ShopOdds.Outcome }
	local list: { ShopOdds.Outcome } = {}
	for _, row in BlockDrop.rarityOdds() do
		table.insert(list, {
			name = RARITIES[row.rarity] or row.rarity,
			display = row.display,
			percent = row.percent,
			tint = ShopCards.rarityColor(row.rarity),
		})
	end
	return list
end

--- Build the card (closed) into `parent` (the Shop's Blocks group).
function ShopMystery.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopMystery)
	self.actions = actions
	self.k = 1
	self.shown = {} :: { [string]: any } -- what refresh last drew

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
	self.odds = ShopOdds.new(card, function(w: number, h: number): Vector2
		-- Beside the block, inside the panel.
		local k = self.k
		local x = round((M.Block[1] + M.Block[3] / 2) * k)
		local y = round(M.Block[2] * k - h / 2)
		local margin = B.PopupMarginPx
		return Vector2.new(math.min(x, card.AbsoluteSize.X - w - margin), math.max(margin, y))
	end)
	self.odds:attach(self.badge.hit, outcomes)

	-- The ladder of tiers.
	local ladder = ShopCards.inner(card, "MysteryLadder", 3)
	self.ladder = ladder
	self.rows = {} :: { Row }
	local count = rgb(Config.UI.Kit.Numbers.Count)
	for index, tier in BlockDrop.tiers() do
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
		table.insert(
			self.rows,
			{ strip = strip, corner = corner, icon = icon, name = name, value = value }
		)
	end
	-- Its words are chosen as it lays out: the short ones where the long ones do not fit.
	self.climb = ShopCards.note(ladder.frame, "Climb", "", 5)

	-- The x1 and x10 columns.
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
		self.columns[index] = {
			box = box,
			count = countLabel,
			green = green,
			gift = gift,
			gold = gold,
			key = key,
		}
	end
	-- The launch bonus's ribbon on x10 ("13 for 10!").
	-- A tilted holder, its pill shaking inside (as the hero card's NEW tag).
	local ribbon = HudParts.frame(self.columns[2].box.frame, "Ribbon")
	ribbon.AnchorPoint = Vector2.new(0.5, 0.5)
	ribbon.Rotation = B.CornerTagDegrees
	ribbon.ZIndex = 6
	ribbon.Visible = false
	local pill, ribbonWords = ShopCards.pill(ribbon, "Pill", "", rgb(Config.UI.Kit.Colors.Red), 6)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	self.ribbon, self.ribbonPill, self.ribbonWords = ribbon, pill, ribbonWords

	-- The Epic guarantee strip.
	local pity = ShopCards.inner(card, "MysteryPity", 3)
	self.pity = pity
	local epic = KINDS.Epic
	self.pityIcon = ShopCards.image(pity.frame, "Icon", if epic then epic.Icon else "", 4)
	self.pityText = ShopCards.label(pity.frame, "Words", "", nil, 4)
	self.pityText.AnchorPoint = Vector2.new(0, 0.5)
	self.pityText.TextXAlignment = Enum.TextXAlignment.Left
	self.pityText.RichText = true
	local track = HudParts.frame(pity.frame, "Track")
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = rgb(M.PityTrack)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.ZIndex = 4
	HudParts.corner(track, 99)
	local trackEdge = Instance.new("UIStroke")
	trackEdge.Color = rgb(Config.UI.Kit.Colors.Ink)
	trackEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	trackEdge.Parent = track
	self.track, self.trackEdge = track, trackEdge
	local fill = HudParts.frame(track, "Fill")
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = rgb(M.PityFill)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 5
	HudParts.corner(fill, 99)
	self.fill = fill
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
	local half = M.Block[3] / 2
	ShopCards.layoutBadge(
		self.badge,
		k,
		M.OddsBadge[1] - M.Block[1] + half,
		M.OddsBadge[2] - M.Block[2] + half,
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
	local nameW = stripW - nameLeft - M.ValueUnits - M.ValueRightUnits
	for index, row in self.rows do
		local cy = M.RowTop + h / 2 + (index - 1) * M.RowUnits
		put(row.strip, lw / 2, cy, stripW, h)
		row.corner.CornerRadius = UDim.new(0, round(M.RowCornerUnits * k))
		ShopCards.put(row.icon, k, M.RowIconLeftUnits + iconU / 2, h / 2, iconU, iconU)
		row.name.Position = UDim2.fromOffset(round(nameLeft * k), round(h / 2 * k))
		row.name.Size = UDim2.fromOffset(round(nameW * k), namePx + B.TextBoxPx)
		HudParts.setTextSize(row.name, namePx)
		row.value.Position =
			UDim2.fromOffset(round((stripW - M.ValueRightUnits) * k), round(h / 2 * k))
		row.value.Size = UDim2.fromOffset(round(M.ValueUnits * k), valuePx + B.TextBoxPx)
		HudParts.setTextSize(row.value, valuePx)
	end
	-- The climb note: the short words when a small screen's smallest text is too wide.
	local notePx = ShopCards.textPx(M.NoteUnits, k)
	local noteW = lw - 2 * M.NoteSideUnits
	local clicks = Config.BlockOdds.Drop.Upgrade.Clicks
	local long = string.format(COPY.Climb, clicks)
	self.climb.Text = if ShopCards.measure(long, notePx) <= noteW * k
		then long
		else string.format(COPY.ClimbShort, clicks)
	ShopCards.line(self.climb, k, lw / 2, M.NoteY, noteW, notePx)

	-- The columns.
	local greenPx, goldPx = M.GreenTextUnits, M.GoldTextUnits
	for index, column in self.columns do
		local c = M.Columns[index]
		local cw, ch = c[3], c[4]
		put(column.box.frame, c[1] + cw / 2, c[2] + ch / 2, cw, ch)
		ShopCards.sizeBox(column.box, k, P.InnerCornerUnits, P.InnerEdgeUnits)
		local countPx = ShopCards.textPx(M.CountUnits, k)
		ShopCards.line(column.count, k, cw / 2, M.CountY, cw - 2 * M.CountSideUnits, countPx)
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
	put(self.ribbon, M.Columns[2][3] / 2, M.RibbonY, rw, rh)
	HudParts.setTextSize(self.ribbonWords, ShopCards.textPx(M.RibbonTextUnits, k))
	local ribbonStroke = ShopCards.strokeOf(self.ribbonPill)
	if ribbonStroke then
		ribbonStroke.Thickness = ShopCards.strokePx(k)
	end

	-- The guarantee strip.
	local px, cy, pw, ph = M.Pity[1], M.Pity[2], M.Pity[3], M.Pity[4]
	put(self.pity.frame, px + pw / 2, cy, pw, ph)
	ShopCards.sizeBox(self.pity, k, P.InnerCornerUnits, P.InnerEdgeUnits)
	local pityIconU = M.PityIconUnits
	ShopCards.put(
		self.pityIcon,
		k,
		M.PityIconLeftUnits + pityIconU / 2,
		ph / 2,
		pityIconU,
		pityIconU
	)
	local textPx = ShopCards.textPx(M.PityTextUnits, k)
	local barW, barH = M.PityBar[1], M.PityBar[2]
	local textLeft = M.PityIconLeftUnits + pityIconU + M.PityTextGapUnits
	local textW = pw - textLeft - M.PityBarGapUnits - barW - M.PityBarRightUnits
	self.pityText.Position = UDim2.fromOffset(round(textLeft * k), round(ph / 2 * k))
	self.pityText.Size = UDim2.fromOffset(round(textW * k), textPx + B.TextBoxPx)
	HudParts.setTextSize(self.pityText, textPx)
	self.track.Position = UDim2.fromOffset(round((pw - M.PityBarRightUnits) * k), round(ph / 2 * k))
	self.track.Size = UDim2.fromOffset(round(barW * k), math.max(M.MinPityBarPx, round(barH * k)))
	self.trackEdge.Thickness = math.max(B.MinEdgePx, M.PityTrackEdgeUnits * k)
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
	for index, column in self.columns do
		local n = COUNTS[index]
		local product = products[column.key]
		local robux = if type(product) == "table" and type(product.robux) == "number"
			then product.robux
			else (Config.Products.List :: any)[column.key].Robux
		local words = ShopCards.robuxText(robux)
		if self.shown["robux" .. n] ~= words then
			self.shown["robux" .. n] = words
			ShopCards.setButtonWords(column.green, words)
		end
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
		if self.shown.restricted ~= restricted then
			HudParts.setEnabled(column.green, not restricted)
			HudParts.setEnabled(column.gift, not restricted)
			HudParts.setEnabled(column.gold, not restricted)
		end
	end
	self.shown.restricted = restricted
	-- "13 for 10!" while the launch bonus runs.
	local bonusOn = bonus.open == true
		and type(bonus.bulkCount) == "number"
		and bonus.bulkCount > BULK
	self.ribbon.Visible = bonusOn
	if bonusOn then
		setText(self.ribbonWords, string.format(COPY.Bonus, bonus.bulkCount, BULK))
	end
	-- The Epic guarantee: blocks left until one is Epic (1: the next one is).
	local pity = if type(state.pity) == "table" then state.pity else {}
	local left = if type(pity.epic) == "number" then math.max(1, math.floor(pity.epic)) else nil
	local total = Config.BlockOdds.Drop.PityEpic
	self.pity.frame.Visible = left ~= nil
	if left ~= nil then
		local epic = ShopCards.rarityColor("Epic"):ToHex()
		local name = string.format('<font color="#%s">%s</font>', epic, SHORT.Epic or "Epic")
		setText(
			self.pityText,
			if left <= 1
				then string.format(COPY.PityNext, name)
				else string.format(COPY.Pity, name, left)
		)
		local share = math.clamp((total - left) / math.max(1, total - 1), 0, 1)
		local want = UDim2.fromScale(share, 1)
		if self.fill.Size ~= want then
			self.fill.Size = want
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
	stage:add("MysteryClimb", self.climb)
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
	stage:add("MysteryRibbon", self.ribbon, function()
		keep(UIAnim.shake(self.ribbonPill, "Text"))
	end)
	stage:add("MysteryPity", self.pity.frame)
end

--- The Shop closed: the odds pop-up goes too.
function ShopMystery.closed(self: any)
	self.odds:close()
end

return ShopMystery
