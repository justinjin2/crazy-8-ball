--!strict
-- ShopGift: the Gift Player popup over the Shop (designer, 2026-10-04; back 2026-10-06 with
-- the Grand Opening card's purple gift squares): the gift square by a Robux button opens it with the other players in this server, a headshot, display name,
-- @username and a Gift button each. Gift sends StoreRequest "Gift" (the same product
-- purchase, granted to that player when the receipt comes) and closes it. B, Escape, the X
-- or a press outside the card close it. The list follows players joining and leaving.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local G = Config.UI.Shop.Gift
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local ACTION = "8ballShopGiftClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- over the menus' B, like a dialog
local ZINDEX = 52 -- over the pages and the odds panel, under notices (55) and dialogs (60)
local span = ShopParts.span
local round = ShopParts.round

type Row = {
	root: Frame,
	face: ImageLabel,
	name: TextLabel,
	at: TextLabel,
	button: TextButton,
	userId: number,
}

type Person = { UserId: number, DisplayName: string, Name: string }
local fake: { Person }? = nil -- the Studio test hook's stand-in players

local ShopGift = {}
ShopGift.__index = ShopGift

--- The popup (closed) over `frame`'s pages. `shop` is the ShopMenu.
function ShopGift.new(shop: any, frame: any): any
	local self: any = setmetatable({}, ShopGift)
	self.shop = shop
	self.frame = frame
	self.opened = false
	self.key = nil :: string?
	self.rows = {} :: { Row }
	self.connections = {} :: { RBXScriptConnection }
	self.liveConnections = {} :: { RBXScriptConnection }

	-- A clear layer over the pages: a press outside the card closes it.
	local layer = Instance.new("TextButton")
	layer.Name = "GiftPlayer"
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
	local heading = HudParts.icon(card, "Gift", "Heading")
	heading.ZIndex = 3
	self.headingIcon = heading
	local title = HudParts.text(card, "Title", K.Big.Heading, COPY.GiftTitle)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.title = title
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.setMinHit(close, Config.UI.Menu.Frame.TouchMinPx)
	HudParts.padBack(close) -- B closes the gift list
	self.closeButton = close
	local nobody = HudParts.note(card, "Nobody", K.Big.Body, COPY.GiftNobody)
	nobody.ZIndex = 3
	nobody.Visible = false
	self.nobody = nobody
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = HudParts.color(K.Colors.Ink)
	list.ZIndex = 3
	list.ClipsDescendants = true
	list.Parent = card
	self.list = list
	-- Studio only: GuiQA:Invoke("gift", key?, n?) opens it with n made-up players (0 or
	-- nothing: the real ones).
	GuiQA.add("gift", function(key: string?, n: number?)
		if type(n) == "number" and n > 0 then
			local names = { "Spiderman12", "alphackui", "brian", "Marii2Raw", "Painicane" }
			local made: { Person } = {}
			for i = 1, n do
				table.insert(made, {
					UserId = 1000 + i,
					DisplayName = names[(i - 1) % #names + 1],
					Name = names[(i - 1) % #names + 1]:lower() .. i,
				})
			end
			fake = made
		else
			fake = nil
		end
		self:open(key or "GrandOpening1")
		return true
	end)
	return self
end

function ShopGift.isOpen(self: any): boolean
	return self.opened
end

-- A row for one player (made once, reused).
local function makeRow(self: any, i: number): Row
	local root = HudParts.frame(self.list, "Row" .. i)
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = HudParts.tone("White")
	root.ZIndex = 3
	HudParts.corner(root, K.ButtonCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = HudParts.color(K.Colors.Ink)
	edge.Thickness = 2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = root
	local face = Instance.new("ImageLabel")
	face.Name = "Face"
	face.BackgroundTransparency = 1
	face.ScaleType = Enum.ScaleType.Fit
	face.ZIndex = 4
	face.Parent = root
	local name = HudParts.text(root, "Name", G.NamePx[1], "")
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.AutoLocalize = false
	name.ZIndex = 4
	local at = HudParts.note(root, "At", G.AtPx[1], "")
	at.TextWrapped = false
	at.TextXAlignment = Enum.TextXAlignment.Left
	at.TextColor3 = HudParts.color(G.AtColor)
	at.AutoLocalize = false
	at.ZIndex = 4
	local row: Row =
		{ root = root, face = face, name = name, at = at, button = nil :: any, userId = 0 }
	local button = HudParts.candy(root, COPY.GiftButton, function()
		UISound.play("Click")
		self:give(row.userId, row.name.Text)
	end, "Green")
	button.Name = "Give"
	button.ZIndex = 5
	row.button = button
	return row
end

-- The other players here, by display name (the Studio test hook's stand-ins instead).
local function others(): { Person }
	local me = Players.LocalPlayer
	local out: { Person } = {}
	for _, player in (fake or Players:GetPlayers()) :: { any } do
		if player ~= me then
			table.insert(out, player)
		end
	end
	table.sort(out, function(a, b)
		return a.DisplayName:lower() < b.DisplayName:lower()
	end)
	return out
end

--- Fill the rows from the players here.
function ShopGift.paint(self: any)
	local players = others()
	for i, player in players do
		local row = self.rows[i]
		if row == nil then
			row = makeRow(self, i)
			self.rows[i] = row
		end
		row.userId = player.UserId
		row.face.Image = G.Headshot:format(player.UserId)
		row.name.Text = player.DisplayName
		row.at.Text = "@" .. player.Name
		HudParts.setEnabled(row.button, not self.shop:isBusy("Gift"))
		row.root.Visible = true
	end
	for i = #players + 1, #self.rows do
		self.rows[i].root.Visible = false
	end
	self.count = #players
	self.nobody.Visible = #players == 0
	self.list.Visible = #players > 0
end

--- Open it for Config.Products key `key`.
function ShopGift.open(self: any, key: string)
	self.key = key
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
		local function changed()
			if self.opened then
				self:paint()
				local geo = self.shop.geo
				if geo then
					self:layout(geo)
				end
			end
		end
		table.insert(self.connections, Players.PlayerAdded:Connect(changed))
		table.insert(self.connections, Players.PlayerRemoving:Connect(changed))
	end
	local geo = self.shop.geo
	if geo then
		self:layout(geo)
	end
	if ShopParts.gamepad() then
		local first = ShopParts.firstSelectable(self:selectables())
		GuiService.SelectedObject = first or self.closeButton
	end
end

--- The Gift buttons a gamepad may land on, in order.
function ShopGift.selectables(self: any): { GuiObject }
	local list: { GuiObject } = {}
	for _, row in self.rows :: { Row } do
		if row.root.Visible then
			table.insert(list, row.button)
		end
	end
	return list
end

-- Gift was pressed on a row: the Shop sends it; the popup closes.
function ShopGift.give(self: any, userId: number, name: string)
	local key = self.key
	if key == nil or userId == 0 then
		return
	end
	self:close()
	self.shop:sendGift(key, userId, name)
end

function ShopGift.close(self: any)
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

--- Lay the card out for the page's size (MenuFrame's geo).
function ShopGift.layout(self: any, geo: any)
	if not self.opened then
		return
	end
	local s = ShopParts.sizes(geo)
	local t = s.t
	local pad = s.pad
	local w = math.min(span(G.WidthPx, t), geo.content.X - 8)
	local titleH = math.max(K.Text.Min, round(K.Big.Heading * (0.75 + 0.25 * t)))
	local rowH = span(G.RowPx, t)
	local rowGap = span(G.RowGapPx, t)
	local n = self.count or 0
	local shown = math.min(n, G.MaxRows)
	local listH = if n == 0
		then math.max(K.Text.Min, round(K.Big.Body * (0.85 + 0.15 * t))) * 2 + 8
		else shown * rowH + math.max(0, shown - 1) * rowGap
	local h = math.min(pad + titleH + 4 + s.gap + listH + pad, geo.content.Y - 8)
	self.card.Size = UDim2.fromOffset(w, h)
	local closeSize = math.min(titleH + 8, 44)
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - pad, pad)
	self.headingIcon.Position = UDim2.fromOffset(pad, pad)
	self.headingIcon.Size = UDim2.fromOffset(titleH + 4, titleH + 4)
	HudParts.setTextSize(self.title, titleH)
	self.title.Position = UDim2.fromOffset(pad + titleH + 10, pad)
	self.title.Size =
		UDim2.fromOffset(math.max(1, w - 2 * pad - titleH - 10 - closeSize), titleH + 4)
	local top = pad + titleH + 4 + s.gap
	local iw = w - 2 * pad
	local innerH = h - top - pad
	self.nobody.Position = UDim2.fromOffset(pad, top)
	self.nobody.Size = UDim2.fromOffset(iw, math.max(1, innerH))
	HudParts.setTextSize(self.nobody, math.max(K.Text.Min, round(K.Big.Body * (0.85 + 0.15 * t))))
	local list: ScrollingFrame = self.list
	list.Position = UDim2.fromOffset(pad, top)
	list.Size = UDim2.fromOffset(iw, math.max(1, innerH))
	list.CanvasSize = UDim2.fromOffset(0, n * rowH + math.max(0, n - 1) * rowGap)
	local rw = iw - (if n > shown then 10 else 0)
	local nameH = span(G.NamePx, t)
	local atH = span(G.AtPx, t)
	local bw = span(G.ButtonWidthPx, t)
	local face = rowH - 8
	local y = 0
	for _, row in self.rows :: { Row } do
		if row.root.Visible then
			row.root.Position = UDim2.fromOffset(0, y)
			row.root.Size = UDim2.fromOffset(rw, rowH)
			row.face.Position = UDim2.fromOffset(4, 4)
			row.face.Size = UDim2.fromOffset(face, face)
			local tx = 4 + face + 8
			local tw = math.max(1, rw - tx - bw - 12)
			HudParts.setTextSize(row.name, nameH, nameH)
			row.name.Position = UDim2.fromOffset(tx, round((rowH - nameH - atH - 2) / 2))
			row.name.Size = UDim2.fromOffset(tw, nameH + 2)
			HudParts.setTextSize(row.at, atH, atH)
			row.at.Position = UDim2.fromOffset(tx, round((rowH - nameH - atH - 2) / 2) + nameH + 2)
			row.at.Size = UDim2.fromOffset(tw, atH + 2)
			local bh = math.min(s.button, rowH - 8)
			HudParts.setButtonTextSize(row.button, s.buttonText)
			row.button.Position = UDim2.fromOffset(rw - bw - 6, round((rowH - bh) / 2))
			row.button.Size = UDim2.fromOffset(bw, bh)
			y += rowH + rowGap
		end
	end
end

return ShopGift
