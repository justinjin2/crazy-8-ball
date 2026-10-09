--!strict
-- UltBuy: the buy panel at the bottom right of the ult spin screen (docs/prompts/
-- ULTIMATES_PROMPT.md sections 9.3 and 10; pick "abilities A", 2026-10-08): a white kit card
-- with one row of four green Robux buttons, "Buy 1" over its price (9 / 39 / 75 / 299 R$, economy
-- v4), each shining now and then (only Robux buttons shine), and under them one gold money button,
-- "$12,500 - 1 spin" (Config.Ults.Earn.MoneyPerSpin). A product whose id is still 0 keeps its
-- price and a small "Soon". The money button never greys: short of money, a press jumps to the
-- Shop's Money tab with what is missing, as the shop's own buttons do. Where paid random items
-- are restricted the buttons are hidden and the note shows instead (free spins still work).
--
-- The buttons sit in `rows`: on a computer inside the panel, on a phone in the screen's
-- "Buy spins" popup (the panel hides). The server checks every price and balance; this only
-- names a pack or a product key.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local E = Config.Ults.Earn
local W = Strings.Ults.Screen
local GOLD = HudParts.tone("Gold")

export type Hooks = {
	buyMoney: (pack: number) -> (), -- BuySpins with money
	buyProduct: (key: string) -> (), -- a Robux spin pack
	jumpToMoney: (gap: number) -> (), -- the money button pressed without the money
}

type Cell = {
	key: string, -- the product key (Spin1, Spin5, ...)
	pack: number, -- spins it adds
	button: TextButton, -- the green candy: its own words are empty, `top` and `price` draw them
	top: TextLabel, -- "Buy 5"
	price: TextLabel, -- the R$ price
	soon: Frame,
}

local UltBuy = {}
UltBuy.__index = UltBuy

--- The panel with its buttons in `parent` (the screen's root).
function UltBuy.new(parent: Instance, hooks: Hooks): any
	local self: any = setmetatable({}, UltBuy)
	self.hooks = hooks
	self.state = nil :: any
	self.restricted = false
	self.shines = {} :: { UIAnim.Handle }

	local panel = HudParts.card(parent, "BuyPanel")
	panel.ZIndex = 5
	self.panel = panel
	local rows = HudParts.frame(panel, "BuyRows")
	rows.ZIndex = 2
	self.rows = rows

	self.cells = {} :: { Cell }
	for index, key in E.RobuxPacks do
		local pack = E.MoneyPacks[index] or 1
		table.insert(self.cells, self:buildCell(rows, key, pack))
	end
	local money = HudParts.candy(rows, "", function()
		UISound.play("Click")
		self:pressMoney()
	end, "Yellow", "CashStack")
	money.Name = "BuyMoney"
	money.ZIndex = 2
	HudParts.setMinHit(money, C.TouchPx)
	self.moneyButton = money

	local note = HudParts.card(rows, "Restricted", K.ButtonCornerPx)
	note.Visible = false
	note.ZIndex = 2
	local noteText =
		HudParts.note(note, "Words", C.Full.PriceTextPx, Strings.Ults.Spins.Reasons.Restricted)
	noteText.ZIndex = 3
	self.note, self.noteText = note, noteText
	return self
end

function UltBuy.buildCell(self: any, parent: Instance, key: string, pack: number): Cell
	local button = HudParts.candy(parent, "", function()
		UISound.play("RobuxBuy")
		self.hooks.buyProduct(key)
	end, "Green")
	button.Name = "Buy" .. pack
	button.ZIndex = 2
	HudParts.setMinHit(button, C.TouchPx)
	local body = button:FindFirstChild("Body") :: Frame
	local top = HudParts.text(body, "Top", C.Full.BuyTopTextPx, W.Buy:format(pack))
	top.AutoLocalize = false -- Strings' words with a number
	top.TextWrapped = false
	top.ZIndex = 3
	local price = HudParts.text(body, "Price", C.Full.BuyTextPx, "")
	price.AutoLocalize = false
	price.TextWrapped = false
	price.ZIndex = 3
	local soon = HudParts.pill(button, "Soon", GOLD)
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.ZIndex = 6
	soon.Visible = false
	local soonText = HudParts.text(soon, "Words", K.Text.Min, W.Soon)
	soonText.TextWrapped = false
	soonText.Size = UDim2.fromScale(1, 1)
	soonText.ZIndex = 7
	return {
		key = key,
		pack = pack,
		button = button,
		top = top,
		price = price,
		soon = soon,
	}
end

-- The money button: one spin, or the Shop's Money tab when the money does not cover it.
function UltBuy.pressMoney(self: any)
	local pack = C.MoneyPack
	local gap = pack * self:perSpin() - Parts.money()
	if gap > 0 then
		self.hooks.jumpToMoney(gap)
	else
		self.hooks.buyMoney(pack)
	end
end

function UltBuy.perSpin(self: any): number
	local state = self.state
	return if type(state) == "table" and type(state.moneyPerSpin) == "number"
		then state.moneyPerSpin
		else E.MoneyPerSpin
end

-- A product's view from UltState (products[key]), or nil.
local function productOf(state: any, key: string): any?
	local products = if type(state.products) == "table" then state.products else nil
	local product = if products then products[key] else nil
	return if type(product) == "table" then product else nil
end

--- Draw an UltState: the Robux prices, the money price, the Soon tags, the note.
function UltBuy.draw(self: any, state: any)
	self.state = state
	self.restricted = state.restricted == true
	for _, cell: Cell in self.cells do
		local product = productOf(state, cell.key)
		local robux = if product and type(product.robux) == "number" then product.robux else 0
		cell.price.Text = Parts.robux(robux)
		cell.soon.Visible = product ~= nil and product.available == false
		cell.button.Visible = not self.restricted
	end
	HudParts.setText(
		self.moneyButton,
		W.MoneySpin:format(Format.money(C.MoneyPack * self:perSpin()))
	)
	self.moneyButton.Visible = not self.restricted
	self.note.Visible = self.restricted
end

--- The panel's inside width for layout `g`: four Robux buttons and their gaps.
function UltBuy.width(_self: any, g: Parts.Geo): number
	local count = #E.RobuxPacks
	return count * g.px("BuyWidthPx") + (count - 1) * g.px("GapPx")
end

--- Lay the buttons (or the note) out `width` wide; returns their height.
function UltBuy.layoutRows(self: any, g: Parts.Geo, width: number): number
	local gap = g.px("GapPx")
	if self.restricted then
		local noteText = g.text("PriceTextPx")
		HudParts.setTextSize(self.noteText, noteText)
		local lines = math.clamp(
			math.ceil(Parts.textWidth(self.noteText.Text, noteText) / math.max(1, width - 2 * gap)),
			1,
			4
		)
		local h = lines * (noteText + 4) + 2 * gap
		self.note.Position = UDim2.fromOffset(0, 0)
		self.note.Size = UDim2.fromOffset(width, h)
		self.noteText.Position = UDim2.fromOffset(gap, gap)
		self.noteText.Size = UDim2.fromOffset(width - 2 * gap, h - 2 * gap)
		self.rows.Size = UDim2.fromOffset(width, h)
		return h
	end
	-- The Robux row: "Buy 5" small over the price, both inside the button, centred together.
	local count = #self.cells
	local cellW = math.floor((width - (count - 1) * gap) / count)
	local buyH = g.px("BuyHeightPx")
	local topPx, pricePx = g.text("BuyTopTextPx"), g.text("BuyTextPx")
	local lip = math.floor(buyH * K.ButtonLipShare)
	local both = topPx + pricePx + 2
	local y0 = math.max(2, math.floor((buyH - lip - both) / 2))
	for index, cell: Cell in self.cells do
		cell.button.Position = UDim2.fromOffset((index - 1) * (cellW + gap), 0)
		cell.button.Size = UDim2.fromOffset(cellW, buyH)
		HudParts.setTextSize(cell.top, topPx)
		cell.top.Position = UDim2.fromOffset(2, y0)
		cell.top.Size = UDim2.fromOffset(cellW - 4, topPx + 2)
		HudParts.setTextSize(cell.price, pricePx)
		cell.price.Position = UDim2.fromOffset(2, y0 + topPx + 2)
		cell.price.Size = UDim2.fromOffset(cellW - 4, pricePx + 2)
		local soonH = K.Text.Min + 4
		local soonW = math.ceil(Parts.textWidth(W.Soon, K.Text.Min)) + 12
		cell.soon.Size = UDim2.fromOffset(soonW, soonH)
		cell.soon.Position = UDim2.fromOffset(cellW + 2, 0)
	end
	local y = buyH + gap
	-- The money button under them, as wide as the row.
	local moneyH = g.px("MoneyButtonHeightPx")
	self.moneyButton.Position = UDim2.fromOffset(0, y)
	self.moneyButton.Size = UDim2.fromOffset(width, moneyH)
	HudParts.setButtonTextSize(self.moneyButton, g.text("MoneyButtonTextPx"))
	HudParts.setIconShare(self.moneyButton, C.MoneyIconShare)
	y += moneyH
	self.rows.Size = UDim2.fromOffset(width, y)
	return y
end

--- The panel at the bottom right corner `right`, `bottom` (a computer): the rows inside its
--- padding. Returns the panel's size.
function UltBuy.layoutPanel(self: any, g: Parts.Geo, right: number, bottom: number): Vector2
	local pad = g.px("BuyPadPx")
	local inner = self:width(g)
	self.rows.Parent = self.panel
	self.rows.Position = UDim2.fromOffset(pad, pad)
	local rowsH = self:layoutRows(g, inner)
	local size = Vector2.new(inner + 2 * pad, rowsH + 2 * pad)
	self.panel.Position = UDim2.fromOffset(right - size.X, bottom - size.Y)
	self.panel.Size = UDim2.fromOffset(size.X, size.Y)
	return size
end

--- Start (or stop) the Robux buttons' shines, one after the other: the screen starts them once
--- the buttons have landed in its open and stops them when it closes.
function UltBuy.setShining(self: any, on: boolean)
	for _, handle in self.shines do
		handle.stop()
	end
	table.clear(self.shines)
	if not on then
		return
	end
	local every = Config.UI.ShopBlocks.ButtonShineEvery
	for index, cell: Cell in self.cells do
		local delay = (index - 1) * C.BuyShineStaggerSeconds
		table.insert(self.shines, ShopCards.buttonShine(cell.button, every, delay))
	end
end

--- The buttons a gamepad can reach, left to right, then the money button.
function UltBuy.buttons(self: any): { GuiObject }
	local list: { GuiObject } = {}
	if self.restricted then
		return list
	end
	for _, cell: Cell in self.cells do
		table.insert(list, cell.button)
	end
	table.insert(list, self.moneyButton)
	return list
end

--- The pieces the screen stages, in order: Buy1 to Buy4, then BuyMoney.
function UltBuy.pieces(self: any): { GuiObject }
	local list: { GuiObject } = {}
	for _, cell: Cell in self.cells do
		table.insert(list, cell.button)
	end
	table.insert(list, self.moneyButton)
	return list
end

--- Put a gamepad on Buy 1.
function UltBuy.focus(self: any)
	local first = self.cells[1]
	if not self.restricted and first then
		GuiService.SelectedObject = first.button
	end
end

return UltBuy
