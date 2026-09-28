--!strict
-- ShopLimited: the Shop's Limited tab (ECONOMY 9; docs/prompts/ECONOMY_UI_PROMPT.md section 11).
-- A card per ShopState.limited row, in its order: the cue's thumbnail on a Unique card, its
-- name, "Unique", "412 of 1,000 sold" (ReplicatedStorage.LimitedSold's attribute, else the
-- row's `sold`), a real countdown ("Ends in 29d 4h", or "Starts in" before it opens), "One per
-- player", the price, and Buy:
--   * a money row (the Beta Cue, $40,000) buys through ItemRequest "BuyLimited"; money short:
--     "Need $X more", which jumps to the Money tab (ShopMenu.buyLimited);
--   * a Robux row (the Founder's Cue) buys through StoreRequest "Buy" with its product key;
--     "Coming soon" while its product's Id is 0 (ShopState products[key].available).
-- Once bought the button gives way to a green "Owned #412"; sold out and ended rows say so.
-- Cards fit side by side when they can (ShopParts.fit), else they stack and scroll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local L = Config.UI.Shop.Limited
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local span = ShopParts.span
local round = ShopParts.round

type Card = {
	cue: string,
	root: Frame,
	fill: Frame,
	art: Frame, -- the thumbnail's own rounded card, dressed Unique
	thumb: Frame,
	name: TextLabel,
	rarity: TextLabel,
	sold: TextLabel,
	timer: TextLabel,
	once: TextLabel, -- "One per player"
	price: ShopParts.Price,
	buy: TextButton,
	status: ShopParts.Pill, -- "Owned #412", "Sold out", "Ended", "Soon"
	-- For the countdown: the row's times and whether it is on sale now.
	startsAt: number,
	endsAt: number,
	live: boolean, -- started, not ended, not sold out, not owned
	waiting: boolean, -- not started yet (redraws once it starts)
	order: number,
}

local ShopLimited = {}
ShopLimited.__index = ShopLimited

-- Copies sold everywhere: the server's attribute (fresh after every take), else the row's.
local function soldOf(row: any): number?
	local folder = ReplicatedStorage:FindFirstChild("LimitedSold")
	local value = if folder then folder:GetAttribute(row.cue) else nil
	if type(value) == "number" then
		return value
	end
	return if type(row.sold) == "number" then row.sold else nil
end

--- The Limited page inside `page`. `shop` is the ShopMenu.
function ShopLimited.new(shop: any, page: Frame): any
	local self: any = setmetatable({}, ShopLimited)
	self.shop = shop
	self.page = page
	local scroll = ShopParts.scroller(page, "Limited")
	self.root = scroll
	self.scroll = scroll
	self.cards = {} :: { [string]: Card }
	self.list = {} :: { Card } -- shown now, in the shelf's order
	self.empty = HudParts.note(scroll, "Empty", Config.UI.Shop.LineTextPx[2], COPY.LimitedEmpty)
	self.empty.ZIndex = 3
	self.empty.Visible = false
	return self
end

function ShopLimited.buildCard(self: any, cueId: string): Card
	local shop = self.shop
	local root, fill = ShopParts.card(self.scroll, "Limited" .. cueId)
	local art = HudParts.frame(root, "Art")
	art.BackgroundTransparency = 0
	art.BackgroundColor3 = HudParts.tone("White")
	art.ZIndex = 3
	HudParts.corner(art, L.ArtCornerPx)
	local rarity = CueThumb.rarityOf(cueId)
	CueThumb.dress(art, rarity, CueThumb.cueColor(cueId))
	local thumb = CueThumb.new(art, cueId)
	thumb.ZIndex = 2
	local name = ShopParts.name(root, "Name")
	name.Text = CueThumb.cueName(cueId)
	local rarityLine = HudParts.text(
		root,
		"Rarity",
		Config.UI.Shop.LineTextPx[1],
		"",
		CueThumb.accentColor(rarity)
	)
	rarityLine.Text = CueThumb.rarityName(rarity)
	rarityLine.TextWrapped = false
	rarityLine.TextXAlignment = Enum.TextXAlignment.Left
	rarityLine.ZIndex = 3
	local sold = ShopParts.line(root, "Sold")
	sold.AutoLocalize = false
	local timer = ShopParts.line(root, "Timer")
	local once = ShopParts.line(root, "Once")
	once.Text = COPY.OnePerPlayer
	local price = ShopParts.price(root, "Price")
	local buy = ShopParts.button(root, "Buy", function()
		UISound.play("Click")
		shop:buyLimited(cueId)
	end)
	local status = ShopParts.pill(root, "Status", "Green")
	status.label.AutoLocalize = false
	status.root.Visible = false
	return {
		cue = cueId,
		root = root,
		fill = fill,
		art = art,
		thumb = thumb,
		name = name,
		rarity = rarityLine,
		sold = sold,
		timer = timer,
		once = once,
		price = price,
		buy = buy,
		status = status,
		startsAt = 0,
		endsAt = 0,
		live = false,
		waiting = false,
		order = 0,
	}
end

-- A status pill in place of the button.
local function showStatus(card: Card, text: string, toneName: string)
	card.buy.Visible = false
	card.status.root.Visible = true
	card.status.root.BackgroundColor3 = HudParts.tone(toneName)
	card.status.label.Text = text
end

--- Redraw from the shop's state.
function ShopLimited.refresh(self: any, state: any)
	local shop = self.shop
	local rows = if type(state) == "table" and type(state.limited) == "table"
		then state.limited
		else {}
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local now = ShopParts.now()
	local shown: { [string]: boolean } = {}
	table.clear(self.list)
	for index, row in rows do
		if type(row) ~= "table" or type(row.cue) ~= "string" then
			continue
		end
		local card: Card = self.cards[row.cue] or self:buildCard(row.cue)
		self.cards[row.cue] = card
		shown[row.cue] = true
		card.order = index
		table.insert(self.list, card)
		card.startsAt = if type(row.startsAt) == "number" then row.startsAt else 0
		card.endsAt = if type(row.endsAt) == "number" then row.endsAt else 0

		-- "412 of 1,000 sold" (or "412 sold" with no cap); hidden before the first read.
		local sold = soldOf(row)
		card.sold.Visible = sold ~= nil
		if sold then
			card.sold.Text = if type(row.cap) == "number"
				then COPY.Sold:format(Format.commas(sold), Format.commas(row.cap))
				else COPY.SoldNoCap:format(Format.commas(sold))
		end

		-- The price: money with the cash bundle, or Robux with its glyph.
		local key = row.product
		local product = if type(key) == "string" then products[key] else nil
		if type(row.price) == "number" then
			ShopParts.setPrice(card.price, Format.money(row.price), nil, true)
		elseif type(product) == "table" and type(product.robux) == "number" then
			ShopParts.setPrice(card.price, ShopParts.robux(product.robux), nil, false)
		else
			ShopParts.setPrice(card.price, "", nil, false)
		end

		-- The button, or what stands in its place.
		local owned = row.owned == true
		local copy = if type(row.copy) == "number" then row.copy else nil
		if owned and copy == nil then
			local have = ItemState.cue(row.cue)
			copy = if have and type(have.copy) == "number" then have.copy else nil
		end
		local soldOut = row.soldOut == true
		local started = now >= card.startsAt
		local ended = card.endsAt > 0 and now >= card.endsAt
		card.live = false
		card.waiting = false
		card.status.root.Visible = false
		card.buy.Visible = true
		if owned then
			showStatus(
				card,
				if copy then COPY.OwnedCopy:format(Format.commas(copy)) else COPY.OwnedWord,
				"Green"
			)
		elseif soldOut then
			showStatus(card, COPY.SoldOut, "Grey")
		elseif ended then
			showStatus(card, COPY.Ended, "Grey")
		elseif not started then
			card.waiting = true
			showStatus(card, COPY.Soon, "Grey")
		else
			card.live = true
			local busy = shop:isBusy(shop.limitedKey(row.cue))
			if type(row.price) == "number" then
				local gap = shop:needFor(shop.limitedKey(row.cue), row.price)
				if gap > 0 then
					ShopParts.setButton(card.buy, ShopParts.need(gap), "Yellow", not busy)
				else
					ShopParts.setButton(card.buy, COPY.Buy, "Green", not busy)
				end
			elseif type(product) == "table" and product.available == true then
				ShopParts.setButton(card.buy, COPY.Buy, "Green", not busy)
			else
				ShopParts.setButton(card.buy, COPY.ComingSoon, "Yellow", true)
			end
		end
		card.root.Visible = true
	end
	for cue, card in self.cards :: { [string]: Card } do
		if not shown[cue] then
			card.root.Visible = false
		end
	end
	self.empty.Visible = #self.list == 0
	self:tick(now)
end

--- The countdowns. True when a card's window just opened or closed here (the menu redraws).
function ShopLimited.tick(self: any, now: number): boolean
	local crossed = false
	for _, card in self.list :: { Card } do
		if now < card.startsAt then
			card.timer.Visible = true
			card.timer.Text = COPY.StartsIn:format(ShopParts.timeLeft(card.startsAt - now))
		elseif card.live and card.endsAt > 0 then
			card.timer.Visible = true
			card.timer.Text = COPY.EndsIn:format(ShopParts.timeLeft(card.endsAt - now))
			if now >= card.endsAt then
				crossed = true
			end
		else
			card.timer.Visible = false
		end
		if card.waiting and now >= card.startsAt then
			crossed = true
		end
	end
	return crossed
end

--- Lay the page out for this size at these sizes.
function ShopLimited.layout(self: any, s: ShopParts.Sizes, size: Vector2)
	local inner = ShopParts.inner(size, s)
	local list: { Card } = self.list
	if #list == 0 then
		HudParts.setTextSize(self.empty, s.name)
		self.empty.Position = UDim2.fromOffset(s.scrollPad, s.scrollPad)
		self.empty.Size = UDim2.fromOffset(inner.X, inner.Y)
		ShopParts.setCanvas(self.scroll, 0)
		return
	end
	local t = s.t
	local pad, lineGap = s.pad, s.lineGap
	local nameH = s.name + 6
	local priceH = s.price + 6
	local details = { "rarity", "sold", "timer", "once" }
	-- The words' column in a card `w` wide: the art's slot at the left, then the name, the
	-- detail lines (each wrapped when it must: a long translation takes two), the price and
	-- the button.
	local function slotOf(w: number): number
		return round(w * L.ArtShare)
	end
	local function widthOf(w: number): number
		return math.max(1, w - 2 * pad - slotOf(w) - s.gap)
	end
	local function heightsOf(card: Card, tw: number): { number }
		local heights: { number } = {}
		for index, key in details do
			local label: TextLabel = (card :: any)[key]
			heights[index] = ShopParts.wrapHeight(label.ContentText, s.line, tw, 2)
		end
		return heights
	end
	local function textHeight(heights: { number }): number
		local total = nameH + lineGap + priceH + s.gap + s.button
		for _, height in heights do
			total += height
		end
		return total
	end
	local function fitFor(needH: number): ShopParts.Fit
		return ShopParts.fit(#list, inner, {
			gap = s.gap,
			minW = span(L.MinWidthPx, t),
			maxW = span(L.MaxWidthPx, t),
			needH = needH,
			maxH = needH + L.ExtraHeightPx,
			aspect = L.Aspect,
		})
	end
	-- Fit with one line each, then again if a card's lines wrap at the width that gave.
	local base = nameH + 4 * (s.line + 4) + lineGap + priceH + s.gap + s.button
	local fit = fitFor(base + 2 * pad)
	local most = base
	for _, card in list do
		most = math.max(most, textHeight(heightsOf(card, widthOf(fit.w))))
	end
	if most > base then
		fit = fitFor(most + 2 * pad)
	end
	for index, card in list do
		local x, y, w, h = s.scrollPad + fit.x[index], s.scrollPad + fit.y[index], fit.w, fit.h
		card.root.Position = UDim2.fromOffset(x, y)
		card.root.Size = UDim2.fromOffset(w, h)
		-- The art on the left, square, as big as its slot and the card let it.
		local slot = slotOf(w)
		local art = math.max(1, math.min(h - 2 * pad, slot))
		card.art.Size = UDim2.fromOffset(art, art)
		card.art.Position = UDim2.fromOffset(pad + round((slot - art) / 2), round((h - art) / 2))
		local inset = round(art * L.ThumbInsetShare)
		card.thumb.Position = UDim2.fromOffset(inset, inset)
		card.thumb.Size = UDim2.fromOffset(art - 2 * inset, art - 2 * inset)
		local tx = pad + slot + s.gap
		local tw = widthOf(w)
		local heights = heightsOf(card, tw)
		local at = math.max(pad, round((h - textHeight(heights)) / 2))
		HudParts.setTextSize(card.name, s.name)
		card.name.Position = UDim2.fromOffset(tx, at)
		card.name.Size = UDim2.fromOffset(tw, nameH)
		at += nameH
		for i, key in details do
			local label: TextLabel = (card :: any)[key]
			HudParts.setTextSize(label, s.line)
			label.Position = UDim2.fromOffset(tx, at)
			label.Size = UDim2.fromOffset(tw, heights[i])
			at += heights[i]
		end
		at += lineGap
		ShopParts.layoutPrice(card.price, priceH, s.price, s.old, tw)
		card.price.root.Position = UDim2.fromOffset(tx, at)
		at += priceH + s.gap
		HudParts.setButtonTextSize(card.buy, s.buttonText)
		card.buy.Position = UDim2.fromOffset(tx, at)
		card.buy.Size = UDim2.fromOffset(tw, s.button)
		ShopParts.setPill(card.status, card.status.label.Text, s.button - 8, s.buttonText, tw)
		card.status.root.AnchorPoint = Vector2.new(0, 0.5)
		card.status.root.Position = UDim2.fromOffset(tx, at + round(s.button / 2))
	end
	ShopParts.setCanvas(self.scroll, s.scrollPad + fit.height + s.scrollPad)
end

--- The first button a gamepad lands on in this page.
function ShopLimited.first(self: any): GuiObject?
	local list: { GuiObject? } = {}
	for _, card in self.list :: { Card } do
		table.insert(list, card.buy)
	end
	return ShopParts.firstSelectable(list)
end

return ShopLimited
