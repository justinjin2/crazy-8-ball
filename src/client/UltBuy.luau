--!strict
-- UltBuy: the bottom right of the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md sections
-- 9.3 and 10; reference 09): "Pity: N / 100", the money, and the buy row: BUY 1, 5, 10 and 50
-- with an R$ / $ toggle. In R$ mode each price is Robux (a bulk deal shows its original price
-- crossed out in red above it; a product whose id is still 0 keeps its price and a small
-- "Soon"), and BUY LUCKY 1 and 3 sit under the row. In $ mode every spin is $1,750 (no bulk
-- discount); a pack the money does not cover says "Need $X more" over its button, and pressing
-- it jumps to the Shop's Money tab as the shop's own buttons do. Where paid random items are
-- restricted the rows are hidden and the note shows instead (free spins still work).
--
-- Two frames: `status` (pity and money) always on the screen, and `rows` (the toggle, the
-- buttons, the note), which the screen puts on the stage on a computer and in its "Buy spins"
-- popup on a phone. The server checks every price and balance; this only names a pack or a
-- product key.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local E = Config.Ults.Earn
local W = Strings.Ults.Screen
local SHOP = Strings.Menus.Shop
local RED = HudParts.tone("Red")
local GOLD = HudParts.tone("Gold")

export type Hooks = {
	buyMoney: (pack: number) -> (), -- BuySpins with money
	buyProduct: (key: string) -> (), -- a Robux spin pack or Lucky pack
	jumpToMoney: (gap: number) -> (), -- "Need $X more" pressed
}

type Cell = {
	key: string, -- a product key, or "Money<n>"
	pack: number, -- spins (or Lucky Spins) it adds
	lucky: boolean,
	frame: Frame,
	button: TextButton,
	price: TextLabel,
	old: TextLabel,
	soon: Frame,
	gap: number, -- $ mode: money still missing (0 when covered)
}

local UltBuy = {}
UltBuy.__index = UltBuy

-- Robux mode is the default: it is where the deals are (overnight assumption, 2026-09-28).
local robuxMode = true

--- The pity line, the money and the buy rows in `parent` (the screen's root).
function UltBuy.new(parent: Instance, hooks: Hooks): any
	local self: any = setmetatable({}, UltBuy)
	self.hooks = hooks
	self.state = nil :: any
	self.restricted = false

	local status = HudParts.frame(parent, "BuyStatus")
	status.ZIndex = 5
	self.status = status
	local pity = HudParts.text(status, "Pity", C.Full.PityTextPx, "")
	pity.AutoLocalize = false
	pity.TextWrapped = false
	pity.TextXAlignment = Enum.TextXAlignment.Right
	pity.ZIndex = 2
	self.pity = pity
	local money = HudParts.pill(status, "Money")
	money.ZIndex = 2
	local cash = HudParts.icon(status, "CashStack", "Cash")
	cash.AnchorPoint = Vector2.new(0.5, 0.5)
	cash.ZIndex = 4
	local moneyText = HudParts.text(money, "Amount", C.Full.MoneyTextPx, "")
	moneyText.AutoLocalize = false
	moneyText.TextWrapped = false
	moneyText.TextXAlignment = Enum.TextXAlignment.Right
	moneyText.ZIndex = 3
	self.moneyPill, self.cash, self.moneyText = money, cash, moneyText

	local rows = HudParts.frame(parent, "BuyRows")
	rows.ZIndex = 5
	self.rows = rows
	local toggleRobux = HudParts.candy(rows, W.Robux, function()
		self:setMode(true)
	end, "Blue")
	toggleRobux.Name = "ToggleRobux"
	toggleRobux.ZIndex = 2
	local toggleMoney = HudParts.candy(rows, W.Money, function()
		self:setMode(false)
	end, "White")
	toggleMoney.Name = "ToggleMoney"
	toggleMoney.ZIndex = 2
	self.toggleRobux, self.toggleMoney = toggleRobux, toggleMoney

	self.cells = {} :: { Cell }
	for index, pack in E.MoneyPacks do
		local key = E.RobuxPacks[index] or ""
		table.insert(self.cells, self:buildCell(rows, key, pack, false))
	end
	self.luckyCells = {} :: { Cell }
	for _, key in E.LuckyPacks do
		local row = (Config.Products.List :: any)[key]
		local count = if row and type(row.Lucky) == "number" then row.Lucky else 1
		table.insert(self.luckyCells, self:buildCell(rows, key, count, true))
	end

	local note = HudParts.card(rows, "Restricted", K.ButtonCornerPx)
	note.Visible = false
	note.ZIndex = 2
	local noteText =
		HudParts.note(note, "Words", C.Full.PriceTextPx, Strings.Ults.Spins.Reasons.Restricted)
	noteText.ZIndex = 3
	self.note, self.noteText = note, noteText

	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Money"):Connect(function()
			if self.state then
				self:draw(self.state)
				if self.onRelayout then
					self.onRelayout() -- the money pill fits its new number
				end
			end
		end)
	end
	return self
end

function UltBuy.buildCell(
	self: any,
	parent: Instance,
	key: string,
	pack: number,
	lucky: boolean
): Cell
	local frame = HudParts.frame(parent, "Cell" .. (if lucky then key else tostring(pack)))
	frame.ZIndex = 2
	local cell: Cell
	local button = HudParts.candy(frame, "", function()
		UISound.play("Click")
		self:press(cell)
	end, if lucky then "Green" else "Yellow", if lucky then "Lucky" else nil)
	button.Name = "Buy"
	button.ZIndex = 2
	HudParts.setMinHit(button, C.TouchPx)
	local price = HudParts.text(frame, "Price", C.Full.PriceTextPx, "")
	price.AutoLocalize = false
	price.ZIndex = 3
	local old = HudParts.text(frame, "Old", C.Full.PriceTextPx, "", RED)
	old.AutoLocalize = false
	old.RichText = true -- <s> crosses it out
	old.TextWrapped = false
	old.ZIndex = 3
	local soon = HudParts.pill(frame, "Soon", GOLD)
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.ZIndex = 6
	soon.Visible = false
	local soonText = HudParts.text(soon, "Words", K.Text.Min, W.Soon)
	soonText.TextWrapped = false
	soonText.Size = UDim2.fromScale(1, 1)
	soonText.ZIndex = 7
	cell = {
		key = key,
		pack = pack,
		lucky = lucky,
		frame = frame,
		button = button,
		price = price,
		old = old,
		soon = soon,
		gap = 0,
	}
	HudParts.setText(button, if lucky then W.BuyLucky:format(pack) else W.Buy:format(pack))
	return cell
end

function UltBuy.press(self: any, cell: Cell)
	if cell.lucky or robuxMode then
		self.hooks.buyProduct(cell.key)
	elseif cell.gap > 0 then
		self.hooks.jumpToMoney(cell.gap)
	else
		self.hooks.buyMoney(cell.pack)
	end
end

function UltBuy.setMode(self: any, robux: boolean)
	UISound.play("Click")
	if robuxMode == robux then
		return
	end
	robuxMode = robux
	if self.state then
		self:draw(self.state)
	end
	if self.onRelayout then
		self.onRelayout()
	end
end

function UltBuy.isRobux(_self: any): boolean
	return robuxMode
end

-- A product's view from UltState (products[key]), or nil.
local function productOf(state: any, key: string): any?
	local products = if type(state.products) == "table" then state.products else nil
	local product = if products then products[key] else nil
	return if type(product) == "table" then product else nil
end

--- Draw an UltState: pity, money, the prices for the toggle's mode, the Soon tags, the note.
function UltBuy.draw(self: any, state: any)
	self.state = state
	local pity = if type(state.pity) == "number" then state.pity else 0
	local pityAt = if type(state.pityAt) == "number" then state.pityAt else Config.Ults.Roll.PityAt
	self.pity.Text = W.Pity:format(Format.commas(pity), Format.commas(pityAt))
	local money = Parts.money()
	self.moneyText.Text = Format.money(money)
	self.restricted = state.restricted == true
	HudParts.setTone(self.toggleRobux, if robuxMode then "Blue" else "White")
	HudParts.setTone(self.toggleMoney, if robuxMode then "White" else "Blue")
	local perSpin = if type(state.moneyPerSpin) == "number"
		then state.moneyPerSpin
		else E.MoneyPerSpin
	for _, cell: Cell in self.cells do
		cell.gap = 0
		if robuxMode then
			local product = productOf(state, cell.key)
			local robux = if product and type(product.robux) == "number" then product.robux else 0
			local was = if product and type(product.was) == "number" then product.was else nil
			cell.price.Text = Parts.robux(robux)
			cell.price.TextColor3 = Color3.new(1, 1, 1)
			cell.old.Text = if was then ("<s>%s</s>"):format(Parts.robux(was)) else ""
			cell.soon.Visible = product ~= nil and product.available == false
			HudParts.setTone(cell.button, "Yellow")
		else
			local price = cell.pack * perSpin
			cell.gap = math.max(0, price - money)
			cell.old.Text = ""
			cell.soon.Visible = false
			if cell.gap > 0 then
				cell.price.Text = SHOP.Need:format(Format.money(cell.gap))
				cell.price.TextColor3 = GOLD
			else
				cell.price.Text = Format.money(price)
				cell.price.TextColor3 = Color3.new(1, 1, 1)
			end
			HudParts.setTone(cell.button, if cell.gap > 0 then "Grey" else "Yellow")
		end
	end
	for _, cell: Cell in self.luckyCells do
		local product = productOf(state, cell.key)
		local robux = if product and type(product.robux) == "number" then product.robux else 0
		local was = if product and type(product.was) == "number" then product.was else nil
		cell.price.Text = Parts.robux(robux)
		cell.old.Text = if was then ("<s>%s</s>"):format(Parts.robux(was)) else ""
		cell.soon.Visible = product ~= nil and product.available == false
		cell.frame.Visible = robuxMode and not self.restricted
	end
	for _, cell: Cell in self.cells do
		cell.frame.Visible = not self.restricted
	end
	self.toggleRobux.Visible = not self.restricted
	self.toggleMoney.Visible = not self.restricted
	self.note.Visible = self.restricted
end

-- One cell `w` wide: the crossed-out price, the price (two lines for "Need $X more"), the
-- button. Returns its height.
local function layoutCell(cell: Cell, w: number, g: Parts.Geo): number
	local priceText = g.text("PriceTextPx")
	local buyH = g.px("BuyHeightPx")
	local line = priceText + 4
	HudParts.setTextSize(cell.old, priceText)
	HudParts.setTextSize(cell.price, priceText)
	cell.old.Position = UDim2.fromOffset(0, 0)
	cell.old.Size = UDim2.fromOffset(w, line)
	cell.price.Position = UDim2.fromOffset(0, line)
	cell.price.Size = UDim2.fromOffset(w, line)
	cell.price.TextWrapped = true
	cell.button.Position = UDim2.fromOffset(0, 2 * line + 2)
	cell.button.Size = UDim2.fromOffset(w, buyH)
	HudParts.setButtonTextSize(cell.button, g.text("BuyTextPx"))
	local soonH = K.Text.Min + 4
	local soonW = math.ceil(Parts.textWidth(W.Soon, K.Text.Min)) + 12
	cell.soon.Size = UDim2.fromOffset(soonW, soonH)
	cell.soon.Position = UDim2.fromOffset(w + 4, 2 * line + 2)
	local height = 2 * line + 2 + buyH
	cell.frame.Size = UDim2.fromOffset(w, height)
	return height
end

--- The rows' width for layout `g`.
function UltBuy.width(_self: any, g: Parts.Geo): number
	local count = #E.MoneyPacks
	return count * g.px("BuyWidthPx") + (count - 1) * g.px("GapPx")
end

--- Lay the rows out `width` wide (toggle, buttons, Lucky row, or the note); returns their height.
function UltBuy.layoutRows(self: any, g: Parts.Geo, width: number): number
	local gap = g.px("GapPx")
	local y = 0
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
	local toggleW, toggleH = g.px("ToggleWidthPx"), g.px("ToggleHeightPx")
	HudParts.setButtonTextSize(self.toggleRobux, g.text("BuyTextPx"))
	HudParts.setButtonTextSize(self.toggleMoney, g.text("BuyTextPx"))
	self.toggleMoney.Position = UDim2.fromOffset(width - toggleW, y)
	self.toggleMoney.Size = UDim2.fromOffset(toggleW, toggleH)
	self.toggleRobux.Position = UDim2.fromOffset(width - 2 * toggleW - 4, y)
	self.toggleRobux.Size = UDim2.fromOffset(toggleW, toggleH)
	y += toggleH + gap
	local count = #self.cells
	local cellW = math.floor((width - (count - 1) * gap) / count)
	local rowH = 0
	for index, cell: Cell in self.cells do
		rowH = layoutCell(cell, cellW, g)
		cell.frame.Position = UDim2.fromOffset((index - 1) * (cellW + gap), y)
	end
	y += rowH
	if robuxMode and #self.luckyCells > 0 then
		y += gap
		local luckyCount = #self.luckyCells
		local luckyW = math.floor((width - (luckyCount - 1) * gap) / math.max(1, luckyCount))
		for index, cell: Cell in self.luckyCells do
			rowH = layoutCell(cell, luckyW, g)
			cell.frame.Position = UDim2.fromOffset((index - 1) * (luckyW + gap), y)
		end
		y += rowH
	end
	self.rows.Size = UDim2.fromOffset(width, y)
	return y
end

--- Lay the status out (pity over the money pill), right-aligned in `width`; returns its height.
function UltBuy.layoutStatus(self: any, g: Parts.Geo, width: number): number
	local pityText = g.text("PityTextPx")
	local moneyH = g.px("MoneyHeightPx")
	local moneyText = g.text("MoneyTextPx")
	HudParts.setTextSize(self.pity, pityText)
	self.pity.Position = UDim2.fromOffset(0, 0)
	self.pity.Size = UDim2.fromOffset(width, pityText + 6)
	local y = pityText + 6 + 4
	HudParts.setTextSize(self.moneyText, moneyText)
	local textW = math.ceil(Parts.textWidth(self.moneyText.Text, moneyText)) + 12
	local cashPx = math.floor(moneyH * 1.5)
	local pillW = math.min(width - cashPx / 2, textW + cashPx * 0.6 + 8)
	self.moneyPill.Position = UDim2.fromOffset(width - pillW, y)
	self.moneyPill.Size = UDim2.fromOffset(pillW, moneyH)
	self.moneyText.Position = UDim2.fromOffset(cashPx * 0.5, 0)
	self.moneyText.Size = UDim2.new(1, -cashPx * 0.5 - 8, 1, 0)
	self.cash.Size = UDim2.fromOffset(cashPx, cashPx)
	self.cash.Position = UDim2.fromOffset(width - pillW, y + moneyH / 2)
	local height = y + moneyH
	self.status.Size = UDim2.fromOffset(width, height)
	return height
end

--- The buttons a gamepad can reach, left to right, top to bottom.
function UltBuy.buttons(self: any): { GuiObject }
	local list: { GuiObject } = {}
	if self.restricted then
		return list
	end
	table.insert(list, self.toggleRobux)
	table.insert(list, self.toggleMoney)
	for _, cell: Cell in self.cells do
		table.insert(list, cell.button)
	end
	if robuxMode then
		for _, cell: Cell in self.luckyCells do
			table.insert(list, cell.button)
		end
	end
	return list
end

--- Put a gamepad on BUY 1 (or the toggle).
function UltBuy.focus(self: any)
	local first = self.cells[1]
	if not self.restricted and first then
		GuiService.SelectedObject = first.button
	end
end

return UltBuy
