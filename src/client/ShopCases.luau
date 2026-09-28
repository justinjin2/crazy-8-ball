--!strict
-- ShopCases: the Shop's Cases tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11; ECONOMY 7
-- and 9.1). A card per case sold (Cases.list: the chest, its name, "Guaranteed Uncommon or
-- better" from its lowest rarity, the price with the cash bundle), Buy and Buy 10 (a "Pay for
-- 9" pill: 10 for the price of 9), and an "Odds" button (the word, with the pie icon) that
-- opens every cue's % (ShopOdds). "x3" on the chest counts the cases of that type you have.
--
-- A sale (ShopState.sale) shows "20% OFF", the old price struck through and a real countdown.
-- A buy the money does not cover says "Need $X more" on the button itself (worked out from the
-- money attribute; a refusal's `need` wins while the money is unchanged) and pressing it jumps
-- to the Money tab (ShopMenu.buyCase). ShopState.restricted (paid random items): a short note
-- at the top instead of the Buy buttons; the Odds stay.
--
-- Two layouts from the page's size: standing cards side by side (the chest on top, the buttons
-- at the bottom) when they fit, else one row per case (a phone on its side), which scrolls.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Cases = require(Progression:WaitForChild("Cases"))
local Format = require(Progression:WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local C = Config.UI.Shop.Cases
local BULK = Config.Cases.BulkCount
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local BOTTOM_RARITY = Config.Cases.Rarities[1]
local span = ShopParts.span
local round = ShopParts.round

type Card = {
	id: string,
	root: Frame,
	fill: Frame,
	icon: ImageLabel,
	count: ShopParts.Pill, -- "x3": cases of this type you have
	sale: ShopParts.Pill, -- "20% OFF"
	name: TextLabel,
	guarantee: TextLabel,
	price: ShopParts.Price,
	saleLine: TextLabel, -- "Sale ends in 2:59:12"
	odds: TextButton,
	buy: TextButton,
	buy10: TextButton,
	bulk: ShopParts.Pill, -- "Pay for 9" on Buy 10
	saleEnds: number?, -- the sale's end while this case is on sale
}

local ShopCases = {}
ShopCases.__index = ShopCases

-- "Guaranteed <Uncommon> or better", the rarity in its colour; the bottom case says any.
local function guaranteeText(caseId: string): string
	local rarity = Cases.minRarity(caseId)
	if rarity == nil or rarity == BOTTOM_RARITY then
		return COPY.GuaranteeAll
	end
	local hex = CueThumb.accentColor(rarity):ToHex()
	local word = ('<font color="#%s">%s</font>'):format(hex, CueThumb.rarityName(rarity))
	return COPY.Guarantee:format(word)
end

--- The Cases page inside `page`. `shop` is the ShopMenu (state, prices, requests).
function ShopCases.new(shop: any, page: Frame): any
	local self: any = setmetatable({}, ShopCases)
	self.shop = shop
	self.page = page
	local scroll = ShopParts.scroller(page, "Cases")
	self.root = scroll
	self.scroll = scroll
	self.restricted = false
	self.anySale = false
	-- The paid-random-items note (ShopState.restricted), across the top.
	local note, noteFill = ShopParts.card(scroll, "Restricted")
	noteFill.BackgroundColor3 = HudParts.color(C.NoteColor)
	local gradient = noteFill:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient:Destroy()
	end
	note.Visible = false
	local noteText = HudParts.note(note, "Words", Config.UI.Shop.LineTextPx[1], COPY.Restricted)
	noteText.ZIndex = 3
	self.note, self.noteText = note, noteText

	self.cards = {} :: { Card }
	for index, case in Cases.list() do
		table.insert(self.cards, self:buildCard(case.Id, index))
	end
	return self
end

function ShopCases.buildCard(self: any, caseId: string, index: number): Card
	local shop = self.shop
	local root, fill = ShopParts.card(self.scroll, "Case" .. caseId)
	root.LayoutOrder = index
	local icon = HudParts.icon(root, "Case" .. caseId, "Chest")
	icon.ZIndex = 3
	local count = ShopParts.pill(root, "Count", "White")
	count.label.AutoLocalize = false
	local sale = ShopParts.pill(root, "Sale", "Red")
	local name = ShopParts.name(root, "Name")
	name.Text = CASE_NAMES[caseId] or caseId
	local guarantee = ShopParts.line(root, "Guarantee")
	guarantee.RichText = true
	guarantee.Text = guaranteeText(caseId)
	local price = ShopParts.price(root, "Price")
	local saleLine = ShopParts.line(root, "SaleEnds")
	saleLine.TextColor3 = HudParts.tone("Red") -- the sale's countdown
	saleLine.Visible = false
	local odds = HudParts.candy(root, COPY.Odds, function()
		UISound.play("Click")
		shop:openOdds(caseId)
	end, "White", "Odds")
	odds.Name = "Odds"
	odds.ZIndex = 3
	HudParts.setMinHit(odds, Config.UI.Menu.Frame.TouchMinPx)
	local buy = ShopParts.button(root, "Buy", function()
		UISound.play("Click")
		shop:buyCase(caseId, 1)
	end)
	local buy10 = ShopParts.button(root, "Buy10", function()
		UISound.play("Click")
		shop:buyCase(caseId, BULK)
	end)
	HudParts.setTone(buy10, "Blue")
	local bulk = ShopParts.pill(root, "Bulk", "Gold")
	return {
		id = caseId,
		root = root,
		fill = fill,
		icon = icon,
		count = count,
		sale = sale,
		name = name,
		guarantee = guarantee,
		price = price,
		saleLine = saleLine,
		odds = odds,
		buy = buy,
		buy10 = buy10,
		bulk = bulk,
		saleEnds = nil,
	}
end

-- One buy button's words and colour: Buy, or "Need $X more" (yellow; it jumps to the Money
-- tab), faded while its request is on its way.
function ShopCases.paintBuy(
	self: any,
	button: TextButton,
	caseId: string,
	count: number,
	words: string
)
	local shop = self.shop
	local key = shop.caseKey(caseId, count)
	local price = shop:casePrice(caseId, count)
	local gap = shop:needFor(key, price)
	local busy = shop:isBusy(key)
	if gap > 0 then
		ShopParts.setButton(button, ShopParts.need(gap), "Yellow", not busy)
	else
		ShopParts.setButton(button, words, if count > 1 then "Blue" else "Green", not busy)
	end
end

--- Redraw from the shop's state (prices, the sale, the restriction, what you have).
function ShopCases.refresh(self: any, state: any)
	local shop = self.shop
	local now = ShopParts.now()
	self.restricted = type(state) == "table" and state.restricted == true
	self.note.Visible = self.restricted
	self.anySale = false
	for _, card in self.cards :: { Card } do
		local id = card.id
		local have = ItemState.caseCount(id)
		card.count.root.Visible = have > 0
		card.count.label.Text = COPY.Owned:format(have)
		local sale = shop:saleFor(id, now)
		local one, _, onSale = shop:casePrice(id, 1)
		local base = Cases.get(id)
		ShopParts.setPrice(
			card.price,
			Format.money(one),
			if onSale and base then Format.money(base.Price) else nil,
			true
		)
		card.sale.root.Visible = onSale
		card.saleLine.Visible = onSale
		card.saleEnds = if onSale and sale then sale.EndsAt else nil
		if onSale and sale then
			self.anySale = true
			card.sale.label.Text = COPY.SaleOff:format(round(sale.Percent))
		end
		card.buy.Visible = not self.restricted
		card.buy10.Visible = not self.restricted
		card.bulk.root.Visible = not self.restricted
		if not self.restricted then
			self:paintBuy(card.buy, id, 1, COPY.Buy)
			self:paintBuy(card.buy10, id, BULK, COPY.BuyMany:format(BULK))
		end
	end
	self:tick(now)
end

--- The countdowns. True when a sale just ended here (the menu redraws).
function ShopCases.tick(self: any, now: number): boolean
	local ended = false
	for _, card in self.cards :: { Card } do
		local ends = card.saleEnds
		if ends then
			if now >= ends then
				ended = true
			end
			card.saleLine.Text = COPY.SaleEnds:format(ShopParts.timeLeft(ends - now))
		end
	end
	return ended
end

-- Place a pill's centre-right on a card: its right edge `right` px from the card's left, its
-- middle at `y`.
local function placePill(
	pill: ShopParts.Pill,
	s: ShopParts.Sizes,
	text: string,
	x: number,
	y: number,
	anchorX: number
)
	local width = ShopParts.setPill(pill, text, s.pill, s.pillText)
	pill.root.AnchorPoint = Vector2.new(anchorX, 0.5)
	pill.root.Position = UDim2.fromOffset(x, y)
	return width
end

--- Lay the page out for this size (MenuFrame's geo.content) at these sizes.
function ShopCases.layout(self: any, s: ShopParts.Sizes, size: Vector2)
	local cards: { Card } = self.cards
	local n = #cards
	if n == 0 then
		return
	end
	local t = s.t
	local inner = ShopParts.inner(size, s)
	local pad, gap, lineGap = s.pad, s.gap, s.lineGap
	local x0, y0 = s.scrollPad, s.scrollPad

	-- The note across the top while restricted.
	local top = 0
	if self.restricted then
		local noteH = 2 * (s.line + 4) + 2 * pad
		self.note.Position = UDim2.fromOffset(x0, y0)
		self.note.Size = UDim2.fromOffset(inner.X, noteH)
		HudParts.setTextSize(self.noteText, s.line)
		self.noteText.Position = UDim2.fromOffset(pad, pad)
		self.noteText.Size = UDim2.fromOffset(inner.X - 2 * pad, noteH - 2 * pad)
		top = noteH + gap
	end
	local availH = inner.Y - top

	local oddsW, oddsH = span(C.OddsWidthPx, t), span(C.OddsHeightPx, t)
	local nameH = s.name + 6
	local lineH = s.line + 4
	local saleH = if self.anySale then lineH else 0
	local buttonsH = if self.restricted then 0 else 2 * s.button + gap
	local w = math.floor((inner.X - (n - 1) * gap) / n)
	-- A standing card: the chest, the name, the guarantee (up to two lines), Odds, the price,
	-- the sale's countdown, then Buy over Buy 10.
	local fixed = pad
		+ lineGap
		+ nameH
		+ 2 * lineH
		+ gap
		+ oddsH
		+ gap
		+ (s.price + 6)
		+ saleH
		+ (if buttonsH > 0 then gap + buttonsH else 0)
		+ pad
	local iconRoom = math.min(availH, C.TallMaxPx) - fixed
	local tall = w >= C.TallMinWidthPx and iconRoom >= C.IconMinPx

	local canvas: number
	if tall then
		local iconSize = math.clamp(iconRoom, C.IconMinPx, math.min(C.IconMaxPx, w - 2 * pad))
		local cardH = fixed + iconSize
		local rowW = n * w + (n - 1) * gap
		local cx = x0 + math.floor((inner.X - rowW) / 2)
		local cy = y0 + top + math.max(0, math.floor((availH - cardH) / 2))
		for index, card in cards do
			self:layoutTall(card, s, cx + (index - 1) * (w + gap), cy, w, cardH, iconSize, {
				nameH = nameH,
				lineH = lineH,
				saleH = saleH,
				oddsW = oddsW,
				oddsH = oddsH,
			})
		end
		canvas = cy + cardH + s.scrollPad
	else
		-- One row per case: the chest, the words, Odds, then Buy over Buy 10 at the right.
		local textH = nameH + lineGap + 2 * lineH + lineGap + (s.price + 6) + saleH
		local rowH = math.max(textH, buttonsH, oddsH) + 2 * pad
		local total = n * rowH + (n - 1) * gap
		local cy = y0 + top + math.max(0, math.floor((availH - total) / 2))
		for index, card in cards do
			self:layoutRow(card, s, x0, cy + (index - 1) * (rowH + gap), inner.X, rowH, {
				nameH = nameH,
				lineH = lineH,
				saleH = saleH,
				oddsW = oddsW,
				oddsH = oddsH,
				buttonsW = span(C.RowButtonsPx, t),
			})
		end
		canvas = cy + total + s.scrollPad
	end
	ShopParts.setCanvas(self.scroll, canvas)
end

type Parts = {
	nameH: number,
	lineH: number,
	saleH: number,
	oddsW: number,
	oddsH: number,
	buttonsW: number?,
}

-- Size the texts on a card.
local function textSizes(card: Card, s: ShopParts.Sizes)
	HudParts.setTextSize(card.name, s.name)
	HudParts.setTextSize(card.guarantee, s.line)
	HudParts.setTextSize(card.saleLine, s.line)
	HudParts.setButtonTextSize(card.odds, s.buttonText)
	HudParts.setButtonTextSize(card.buy, s.buttonText)
	HudParts.setButtonTextSize(card.buy10, s.buttonText)
end

-- The pills every layout shares: the sale at the card's top left, "x3" on the chest's bottom
-- right, "Pay for 9" on Buy 10's top right.
function ShopCases.placePills(
	_self: any,
	card: Card,
	s: ShopParts.Sizes,
	iconRight: number,
	iconBottom: number
)
	if card.sale.root.Visible then
		placePill(card.sale, s, card.sale.label.Text, s.pad, s.pad + round(s.pill / 2), 0)
	end
	if card.count.root.Visible then
		placePill(
			card.count,
			s,
			card.count.label.Text,
			iconRight,
			iconBottom - round(s.pill / 2),
			1
		)
	end
	if card.bulk.root.Visible then
		local buy10 = card.buy10
		local right = buy10.Position.X.Offset + buy10.Size.X.Offset + round(s.pad / 2)
		placePill(
			card.bulk,
			s,
			COPY.BulkDeal:format(Config.Cases.BulkPayFor),
			right,
			buy10.Position.Y.Offset,
			1
		)
	end
end

function ShopCases.layoutTall(
	self: any,
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number,
	iconSize: number,
	p: Parts
)
	textSizes(card, s)
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	local pad, lineGap = s.pad, s.lineGap
	local iw = w - 2 * pad
	local at = pad
	card.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	card.icon.Position = UDim2.fromOffset(round((w - iconSize) / 2), at)
	local iconRight, iconBottom = round((w + iconSize) / 2), at + iconSize
	at += iconSize + lineGap
	card.name.TextXAlignment = Enum.TextXAlignment.Center
	card.name.Position = UDim2.fromOffset(pad, at)
	card.name.Size = UDim2.fromOffset(iw, p.nameH)
	at += p.nameH
	card.guarantee.TextXAlignment = Enum.TextXAlignment.Center
	card.guarantee.Position = UDim2.fromOffset(pad, at)
	card.guarantee.Size = UDim2.fromOffset(iw, 2 * p.lineH)
	at += 2 * p.lineH + s.gap
	-- Odds, centred under the guarantee it explains, then the price centred.
	local oddsW = math.min(p.oddsW, iw)
	card.odds.Size = UDim2.fromOffset(oddsW, p.oddsH)
	card.odds.Position = UDim2.fromOffset(round((w - oddsW) / 2), at)
	at += p.oddsH + s.gap
	local priceH = s.price + 6
	ShopParts.layoutPrice(card.price, priceH, s.price, s.old, iw, true)
	card.price.root.Position = UDim2.fromOffset(pad, at)
	at += priceH
	if p.saleH > 0 then
		card.saleLine.TextXAlignment = Enum.TextXAlignment.Center
		card.saleLine.Position = UDim2.fromOffset(pad, at)
		card.saleLine.Size = UDim2.fromOffset(iw, p.lineH)
		at += p.saleH
	end
	if card.buy.Visible then
		at += s.gap
		card.buy.Position = UDim2.fromOffset(pad, at)
		card.buy.Size = UDim2.fromOffset(iw, s.button)
		at += s.button + s.gap
		card.buy10.Position = UDim2.fromOffset(pad, at)
		card.buy10.Size = UDim2.fromOffset(iw, s.button)
	end
	self:placePills(card, s, iconRight, iconBottom)
end

function ShopCases.layoutRow(
	self: any,
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number,
	p: Parts
)
	textSizes(card, s)
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	local pad, gap, lineGap = s.pad, s.gap, s.lineGap
	local iconSize = math.min(h - 2 * pad, C.IconMaxPx)
	card.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	card.icon.Position = UDim2.fromOffset(pad, round((h - iconSize) / 2))
	local iconRight, iconBottom = pad + iconSize, round((h + iconSize) / 2)

	-- From the right: Buy over Buy 10, then Odds.
	local right = w - pad
	if card.buy.Visible then
		local bw = p.buttonsW or 150
		local stack = 2 * s.button + gap
		local by = round((h - stack) / 2)
		card.buy.Position = UDim2.fromOffset(right - bw, by)
		card.buy.Size = UDim2.fromOffset(bw, s.button)
		card.buy10.Position = UDim2.fromOffset(right - bw, by + s.button + gap)
		card.buy10.Size = UDim2.fromOffset(bw, s.button)
		right -= bw + gap
	end
	card.odds.Size = UDim2.fromOffset(p.oddsW, p.oddsH)
	card.odds.Position = UDim2.fromOffset(right - p.oddsW, round((h - p.oddsH) / 2))
	right -= p.oddsW + gap

	-- The words between the chest and Odds, centred up and down.
	local tx = pad + iconSize + gap
	local tw = math.max(1, right - tx)
	local priceH = s.price + 6
	local textH = p.nameH + lineGap + 2 * p.lineH + lineGap + priceH + p.saleH
	-- One guarantee line when it fits on one (the row gets shorter words' room back).
	local guaranteeLines = if ShopParts.textWidth(card.guarantee.ContentText, s.line) + 4 <= tw
		then 1
		else 2
	textH -= (2 - guaranteeLines) * p.lineH
	local at = math.max(pad, round((h - textH) / 2))
	card.name.TextXAlignment = Enum.TextXAlignment.Left
	card.name.Position = UDim2.fromOffset(tx, at)
	card.name.Size = UDim2.fromOffset(tw, p.nameH)
	at += p.nameH + lineGap
	card.guarantee.TextXAlignment = Enum.TextXAlignment.Left
	card.guarantee.Position = UDim2.fromOffset(tx, at)
	card.guarantee.Size = UDim2.fromOffset(tw, guaranteeLines * p.lineH)
	at += guaranteeLines * p.lineH + lineGap
	ShopParts.layoutPrice(card.price, priceH, s.price, s.old, tw)
	card.price.root.Position = UDim2.fromOffset(tx, at)
	at += priceH
	if p.saleH > 0 then
		card.saleLine.TextXAlignment = Enum.TextXAlignment.Left
		card.saleLine.Position = UDim2.fromOffset(tx, at)
		card.saleLine.Size = UDim2.fromOffset(tw, p.lineH)
	end
	self:placePills(card, s, iconRight, iconBottom)
end

--- The first button a gamepad lands on in this page.
function ShopCases.first(self: any): GuiObject?
	local list: { GuiObject? } = {}
	for _, card in self.cards :: { Card } do
		table.insert(list, card.buy)
		table.insert(list, card.odds)
	end
	return ShopParts.firstSelectable(list)
end

--- A case's Odds button (the odds panel gives the selection back to it).
function ShopCases.oddsButton(self: any, caseId: string): TextButton?
	for _, card in self.cards :: { Card } do
		if card.id == caseId then
			return card.odds
		end
	end
	return nil
end

return ShopCases
