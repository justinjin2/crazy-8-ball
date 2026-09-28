--!strict
-- ShopMoney: the Shop's Money tab (ECONOMY 11.1; docs/prompts/ECONOMY_UI_PROMPT.md sections 11
-- and 12). The seven money packs (Shop.packs(): icons Pack1 to Pack7, the pack's name, its
-- money, a green "+7%" bonus pill) with their Robux price on the Buy button (the live price
-- from ShopState, Roblox's Robux glyph in the text). A gold "First purchase: double money!"
-- ribbon across the top, and "x2" on every pack, until the first pack is bought. Buy asks the
-- server (StoreRequest "Buy" with the pack's key), which shows Roblox's purchase dialog
-- itself. While a pack's product Id is 0 its price still shows and a gold "Coming soon" tag
-- ("Soon" where the card is too narrow for it) sits over its icon; Buy then only says so.
--
-- "Need $X more" elsewhere jumps here with the smallest pack that covers the gap lit in gold,
-- breathing, with a "Best pick" pill (ShopMenu.jumpToMoney; Shop.packForGap).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Format = require(Progression:WaitForChild("Format"))
local Shop = require(Progression:WaitForChild("Shop"))
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local M = Config.UI.Shop.Money
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local PACK_NAMES: { [string]: string } = COPY.Packs
local span = ShopParts.span
local round = ShopParts.round

type Card = {
	key: string,
	root: Frame,
	fill: Frame,
	icon: ImageLabel,
	name: TextLabel,
	amount: TextLabel,
	bonus: ShopParts.Pill, -- "+7%"
	double: ShopParts.Pill, -- "x2" while the first purchase is unused
	best: ShopParts.Pill, -- "Best pick" on the lit pack
	soon: ShopParts.Pill, -- "Coming soon" over the icon while the product is not made yet
	buy: TextButton,
}

local ShopMoney = {}
ShopMoney.__index = ShopMoney

--- The Money page inside `page`. `shop` is the ShopMenu.
function ShopMoney.new(shop: any, page: Frame): any
	local self: any = setmetatable({}, ShopMoney)
	self.shop = shop
	self.page = page
	local scroll = ShopParts.scroller(page, "Money")
	self.root = scroll
	self.scroll = scroll
	self.lit = nil :: string?
	self.pulse = nil :: UIAnim.Handle?
	self.doubled = false

	-- The ribbon: a gold pill across the top with the cash stack.
	local ribbon = HudParts.pill(scroll, "FirstDouble", HudParts.tone("Gold"))
	ribbon.ZIndex = 3
	ribbon.Visible = false
	local ribbonIcon = HudParts.icon(ribbon, "CashStack", "Cash")
	ribbonIcon.ZIndex = 4
	local ribbonText =
		HudParts.text(ribbon, "Words", Config.UI.Shop.NameTextPx[1], COPY.FirstDouble)
	ribbonText.TextWrapped = false
	ribbonText.ZIndex = 4
	self.ribbon, self.ribbonIcon, self.ribbonText = ribbon, ribbonIcon, ribbonText

	self.cards = {} :: { Card }
	for _, pack in Shop.packs() do
		table.insert(self.cards, self:buildCard(pack.key, pack.money, pack.bonus))
	end
	return self
end

function ShopMoney.buildCard(self: any, key: string, money: number, bonus: number): Card
	local shop = self.shop
	local root, fill = ShopParts.card(self.scroll, key)
	local icon = HudParts.icon(root, key, "Icon")
	icon.ZIndex = 3
	local name = HudParts.note(root, "Name", Config.UI.Shop.LineTextPx[1], PACK_NAMES[key] or key)
	name.TextWrapped = false
	name.ZIndex = 3
	local amount = HudParts.text(root, "Amount", Config.UI.Shop.PriceTextPx[1], Format.money(money))
	amount.AutoLocalize = false
	amount.TextWrapped = false
	amount.ZIndex = 3
	local bonusPill = ShopParts.pill(root, "Bonus", "Green")
	bonusPill.label.AutoLocalize = false
	bonusPill.label.Text = COPY.Bonus:format(bonus)
	bonusPill.root.Visible = bonus > 0
	local double = ShopParts.pill(root, "Double", "Gold")
	double.label.Text = COPY.Double
	double.root.Visible = false
	local best = ShopParts.pill(root, "Best", "Gold")
	best.label.Text = COPY.BestPick
	best.root.Visible = false
	local soon = ShopParts.pill(root, "Soon", "Gold")
	soon.root.Visible = false
	local buy = ShopParts.button(root, "Buy", function()
		UISound.play("Click")
		shop:buyProduct(key)
	end)
	return {
		key = key,
		root = root,
		fill = fill,
		icon = icon,
		name = name,
		amount = amount,
		bonus = bonusPill,
		double = double,
		best = best,
		soon = soon,
		buy = buy,
	}
end

--- Redraw from the shop's state (live prices, availability, the first purchase double).
function ShopMoney.refresh(self: any, state: any)
	local shop = self.shop
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	self.doubled = type(state) == "table" and state.firstPackBought ~= true
	self.ribbon.Visible = self.doubled
	for _, card in self.cards :: { Card } do
		card.double.root.Visible = self.doubled
		-- Buy always shows the Robux price; a product not made yet (Id 0) is marked "Coming
		-- soon" on the card, and pressing Buy only says so (ShopMenu.buyProduct).
		local product = products[card.key]
		local busy = shop:isBusy(shop.productKey(card.key))
		local price = ShopParts.robux(ShopParts.robuxOf(product, card.key))
		ShopParts.setButton(card.buy, price, "Green", not busy)
		card.soon.root.Visible = not (type(product) == "table" and product.available == true)
	end
end

function ShopMoney.tick(_self: any, _now: number): boolean
	return false
end

--- Light the pack that covers what you need (nil: none): a gold edge, a breath, "Best pick".
function ShopMoney.highlight(self: any, key: string?)
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.lit = key
	for _, card in self.cards :: { Card } do
		local on = card.key == key
		ShopParts.setLit(card.fill, on)
		card.best.root.Visible = on
		if on then
			self.pulse = UIAnim.pulse(card.root)
		end
	end
end

--- The Buy button of a pack (the jump puts a gamepad on it).
function ShopMoney.buttonFor(self: any, key: string): TextButton?
	for _, card in self.cards :: { Card } do
		if card.key == key then
			return card.buy
		end
	end
	return nil
end

--- Lay the page out for this size at these sizes.
function ShopMoney.layout(self: any, s: ShopParts.Sizes, size: Vector2)
	local t = s.t
	local inner = ShopParts.inner(size, s)
	local pad, lineGap = s.pad, s.lineGap
	local x0, y0 = s.scrollPad, s.scrollPad

	-- The ribbon, centred across the top, as wide as its words.
	local top = 0
	if self.ribbon.Visible then
		local ribbonH = span(M.RibbonPx, t)
		local textSize = s.name
		HudParts.setTextSize(self.ribbonText, textSize)
		local iconSize = round(ribbonH * M.RibbonIconShare)
		local words = math.ceil(ShopParts.textWidth(self.ribbonText.Text, textSize)) + 8
		local width = math.min(inner.X, iconSize + words + 3 * pad)
		self.ribbon.Size = UDim2.fromOffset(width, ribbonH)
		self.ribbon.Position = UDim2.fromOffset(x0 + round((inner.X - width) / 2), y0)
		self.ribbonIcon.Size = UDim2.fromOffset(iconSize, iconSize)
		self.ribbonIcon.Position = UDim2.fromOffset(pad, round((ribbonH - iconSize) / 2))
		self.ribbonText.Position = UDim2.fromOffset(pad + iconSize + round(pad / 2), 0)
		self.ribbonText.Size = UDim2.fromOffset(math.max(1, width - iconSize - 2 * pad), ribbonH)
		top = ribbonH + s.gap
	end

	-- A pack: the icon, its name, its money, then Buy with the Robux price.
	local nameH = s.line + 4
	local amountH = s.price + 6
	local fixed = pad + lineGap + nameH + amountH + s.gap + s.button + pad
	local cards: { Card } = self.cards
	local fit = ShopParts.fit(#cards, inner, {
		gap = s.gap,
		minW = span(M.MinWidthPx, t),
		maxW = M.MaxWidthPx,
		needH = fixed + M.IconMinPx,
		maxH = fixed + M.IconMaxPx,
		aspect = M.Aspect,
		top = top,
	})
	for index, card in cards do
		local x, y, w, h = x0 + fit.x[index], y0 + fit.y[index], fit.w, fit.h
		card.root.Position = UDim2.fromOffset(x, y)
		card.root.Size = UDim2.fromOffset(w, h)
		local iw = w - 2 * pad
		local iconSize = math.clamp(h - fixed, M.IconMinPx, math.min(M.IconMaxPx, iw))
		local used = fixed + iconSize
		local at = math.max(pad, round((h - used) / 2) + pad)
		card.icon.Size = UDim2.fromOffset(iconSize, iconSize)
		card.icon.Position = UDim2.fromOffset(round((w - iconSize) / 2), at)
		-- "Coming soon" (or "Soon" on a narrow card) over the icon's bottom, sized to its words.
		if card.soon.root.Visible then
			local room = w - 4
			local words = ShopParts.soonText(room, s.pillText)
			ShopParts.setPill(card.soon, words, s.pill, s.pillText, room)
			card.soon.root.AnchorPoint = Vector2.new(0.5, 1)
			card.soon.root.Position = UDim2.fromOffset(round(w / 2), at + iconSize)
		end
		at += iconSize + lineGap
		HudParts.setTextSize(card.name, s.line)
		card.name.Position = UDim2.fromOffset(pad, at)
		card.name.Size = UDim2.fromOffset(iw, nameH)
		at += nameH
		HudParts.setTextSize(card.amount, s.price)
		card.amount.Position = UDim2.fromOffset(pad, at)
		card.amount.Size = UDim2.fromOffset(iw, amountH)
		at += amountH + s.gap
		HudParts.setButtonTextSize(card.buy, s.buttonText)
		card.buy.Position = UDim2.fromOffset(pad, at)
		card.buy.Size = UDim2.fromOffset(iw, s.button)
		-- The pills: the bonus at the top right, x2 at the top left, Best pick on Buy's top edge.
		local half = round(s.pill / 2)
		ShopParts.setPill(card.bonus, card.bonus.label.Text, s.pill, s.pillText, round(iw * 0.6))
		card.bonus.root.AnchorPoint = Vector2.new(1, 0.5)
		card.bonus.root.Position = UDim2.fromOffset(w - round(pad / 2), round(pad / 2) + half)
		ShopParts.setPill(card.double, card.double.label.Text, s.pill, s.pillText, round(iw * 0.4))
		card.double.root.AnchorPoint = Vector2.new(0, 0.5)
		card.double.root.Position = UDim2.fromOffset(round(pad / 2), round(pad / 2) + half)
		ShopParts.setPill(card.best, card.best.label.Text, s.pill, s.pillText, w)
		card.best.root.AnchorPoint = Vector2.new(0.5, 0.5)
		card.best.root.Position = UDim2.fromOffset(round(w / 2), at)
	end
	ShopParts.setCanvas(self.scroll, y0 + fit.height + s.scrollPad)
end

--- The first button a gamepad lands on in this page.
function ShopMoney.first(self: any): GuiObject?
	local list: { GuiObject? } = {}
	if self.lit then
		table.insert(list, self:buttonFor(self.lit))
	end
	for _, card in self.cards :: { Card } do
		table.insert(list, card.buy)
	end
	return ShopParts.firstSelectable(list)
end

return ShopMoney
