--!strict
-- ShopNeed: the need-money popup over the Shop (GUI lane, designer 2026-10-03): a money buy the
-- money does not cover opens it with "You need $X more" and the smallest money pack that
-- covers the gap as one big lit tile (its money, the first-buy double, its Robux price on Buy;
-- Shop.packForGap). The Shop never opens it after a loss (ShopMenu.needMoney checks), and it
-- only ever opens from a press. B, Escape, the X or a press outside the card close it.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Format = require(Progression:WaitForChild("Format"))
local Shop = require(Progression:WaitForChild("Shop"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local N = Config.UI.Shop.Need
local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local ACTION = "8ballShopNeedClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- over the menus' B, like a dialog
local ZINDEX = 52 -- over the pages and the odds panel, under notices (55) and dialogs (60)
local span = ShopParts.span
local round = ShopParts.round

local ShopNeed = {}
ShopNeed.__index = ShopNeed

--- The popup (closed) over `frame`'s pages. `shop` is the ShopMenu.
function ShopNeed.new(shop: any, frame: any): any
	local self: any = setmetatable({}, ShopNeed)
	self.shop = shop
	self.frame = frame
	self.opened = false
	self.gap = 0
	self.pack = nil :: string?
	self.connections = {} :: { RBXScriptConnection }

	-- A clear layer over the pages: a press outside the card closes it.
	local layer = Instance.new("TextButton")
	layer.Name = "NeedMoney"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = ZINDEX
	layer.Visible = false
	layer.Parent = frame.content
	layer.Activated:Connect(function()
		self:close()
	end)
	self.layer = layer
	local card = HudParts.popupCard(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 2
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.card = card
	local title = HudParts.text(card, "Title", K.Big.Heading, COPY.NeedTitle)
	title.TextWrapped = false
	title.ZIndex = 3
	self.title = title
	UIAnim.shake(title, "Text")
	local line = HudParts.text(card, "Line", K.Big.Body, "", HudParts.color(K.Numbers.Money))
	line.AutoLocalize = false
	line.TextWrapped = false
	line.ZIndex = 3
	self.line = line
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.setMinHit(close, Config.UI.Menu.Frame.TouchMinPx)
	self.closeButton = close
	self.tile = ShopCards.new(card, "NeedPack", "Tile")
	self.tile.root.ZIndex = 3
	return self
end

function ShopNeed.isOpen(self: any): boolean
	return self.opened
end

-- The pack's tile: its money (the first-buy double counted, as the server would pay), its
-- Robux price on Buy, lit gold with "This covers it!".
function ShopNeed.paint(self: any)
	local key = self.pack
	if key == nil then
		return
	end
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local sale = if type(state) == "table" and type(state.releaseSale) == "table"
		then state.releaseSale
		else {}
	local saleKey = if type(sale.swap) == "table" then sale.swap[key] else nil
	local buyKey = if sale.open == true
			and type(saleKey) == "string"
			and products[saleKey]
		then saleKey
		else key
	local product = if type(products[buyKey]) == "table" then products[buyKey] else {}
	local money = 0
	for _, pack in Shop.packs() do
		if pack.key == key then
			money = pack.money
		end
	end
	if type(product.money) == "number" and product.money > 0 then
		money = product.money
	end
	local shop = self.shop
	local packs: { [string]: string } = COPY.Packs
	ShopCards.paint(self.tile, {
		id = "NeedPack",
		shape = "Tile",
		icon = key,
		title = packs[key] or key,
		big = Format.money(money),
		line = COPY.NeedPack,
		sticker = if type(state) == "table" and state.firstPackBought ~= true
			then COPY.FirstBuy
			else nil,
		stickerTone = "Gold",
		buttons = {
			{
				text = ShopParts.robux(ShopParts.robuxOf(products[buyKey], buyKey)),
				tone = "Green",
				enabled = not shop:isBusy(shop.productKey(buyKey)),
				action = function()
					UISound.play("Click")
					shop:buyProduct(buyKey)
					self:close()
				end,
			},
		},
		lit = true,
		shine = true,
	})
	self.line.Text = COPY.NeedLine:format(Format.money(self.gap))
end

--- Open it for a gap of `gap` money, offering `pack` (a Config.Products key).
function ShopNeed.open(self: any, gap: number, pack: string)
	self.gap = gap
	self.pack = pack
	self:paint()
	if not self.opened then
		self.opened = true
		self.previous = GuiService.SelectedObject
		self.layer.Visible = true
		UIAnim.popIn(self.card)
		UIAnim.glowBurst(self.card, HudParts.color(K.Numbers.Money), 0.3)
		self.dialog = {
			cancel = function()
				self:close()
			end,
			isOpen = function(): boolean
				return self.opened
			end,
		}
		table.insert(self.frame.dialogs, self.dialog)
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, state: Enum.UserInputState, _input: InputObject)
				if state == Enum.UserInputState.Begin then
					self:close()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			PRIORITY,
			Enum.KeyCode.ButtonB
		)
		table.insert(
			self.connections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape then
					Menus.swallowEscape(input)
					self:close()
				end
			end)
		)
	end
	local geo = self.shop.geo
	if geo then
		self:layout(self.shop.sizes, geo)
	end
	if ShopParts.gamepad() then
		local first = ShopParts.firstSelectable(ShopCards.selectables(self.tile))
		GuiService.SelectedObject = first or self.closeButton
	end
end

function ShopNeed.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	local at = table.find(self.frame.dialogs, self.dialog)
	if at then
		table.remove(self.frame.dialogs, at)
	end
	ContextActionService:UnbindAction(ACTION)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.layer) then
		local previous = self.previous
		GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
			then previous
			else nil
	end
	self.previous = nil
	UIAnim.popOut(self.card, function()
		if not self.opened then
			self.layer.Visible = false
		end
	end)
end

--- Lay the card out for the page's size.
function ShopNeed.layout(self: any, s: ShopParts.Sizes, geo: any)
	if not self.opened then
		return
	end
	local t = s.t
	local w = math.min(span(N.WidthPx, t), geo.content.X - 8)
	local tileH = ShopCards.tileNeed(self.tile, s, math.min(w - 2 * s.pad, P.TileMaxWidthPx))
	local titleH = math.max(K.Text.Min, round(K.Big.Heading * (0.75 + 0.25 * t)))
	local lineH = math.max(K.Text.Min, round(K.Big.Body * (0.85 + 0.15 * t)))
	local sticker = round(span(P.StickerPx, t) / 2) + 2 -- the tile's sticker pokes above it
	local h =
		math.min(s.pad + titleH + 4 + lineH + s.gap + sticker + tileH + s.pad, geo.content.Y - 8)
	self.card.Size = UDim2.fromOffset(w, h)
	local closeSize = math.min(titleH + 8, 44)
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - s.pad, s.pad)
	HudParts.setTextSize(self.title, titleH)
	self.title.Position = UDim2.fromOffset(s.pad + closeSize, s.pad)
	self.title.Size = UDim2.fromOffset(math.max(1, w - 2 * (s.pad + closeSize)), titleH + 4)
	HudParts.setTextSize(self.line, lineH)
	self.line.Position = UDim2.fromOffset(s.pad, s.pad + titleH + 4)
	self.line.Size = UDim2.fromOffset(w - 2 * s.pad, lineH + 4)
	local tileW = math.min(w - 2 * s.pad, P.TileMaxWidthPx)
	ShopCards.layoutTile(self.tile, s, round((w - tileW) / 2), h - s.pad - tileH, tileW, tileH)
end

return ShopNeed
