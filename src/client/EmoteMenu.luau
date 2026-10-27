--!strict
-- EmoteMenu: the emote tray (designer's pick 2A, 2026-10-26; Config.EmoteMenu.Tray). It grows
-- up out of the EMOTE button with no blur, so the player still sees their character, a small
-- arrow under it pointing at the button (a dropdown; it never reaches below the arrow):
-- - A header (the hand-drawn noob, EMOTES, the red X) over a sheet of cards, three across, two
--   rows and a peek of the third so players know to scroll.
-- - A card: its dance looping as a dark silhouette (EmotePreview; only the cards in view move),
--   its short name, and a star. A favourite's star is gold, its card yellow, and it comes first.
-- - The credit strip at the bottom names the card in focus and its maker ("by Voxelates"),
--   with one small Avatar Shop link (MarketplaceService:PromptPurchase on its catalog item):
--   the dances are borrowed here, theirs to keep only from the shop (designer: no prices, no
--   Buy on the cards). Our own emotes (no catalog item: Popcorn, Bullseye) have no link.
-- - A card pressed starts its dance and the tray closes (designer: "Menu closes").
-- - Controller: the first card is selected on open; the stick or D-pad moves; A dances; Y
--   stars; X opens the shop link; B (or R3 again) closes. Touch and mouse: tap or click.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local LocalizationService = game:GetService("LocalizationService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local EmoteSync = require(Shared:WaitForChild("EmoteSync"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local EmotePlayer = require(script.Parent.EmotePlayer)
local EmotePreview = require(script.Parent.EmotePreview)
local HudParts = require(script.Parent.HudParts)
local PadMode = require(script.Parent.PadMode)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local E = Config.EmoteMenu
local T = E.Tray
local K = Config.UI.Kit
local W = Strings.Emotes
local ACTION = "8ballEmoteTray"

local EmoteMenu = {}
EmoteMenu.__index = EmoteMenu

type Card = {
	row: EmoteSync.Row,
	button: TextButton,
	well: Frame,
	star: ImageButton,
	name: TextLabel,
	preview: EmotePreview.Preview,
	hidden: boolean,
}

local function color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

-- Text made safe for a rich-text label.
local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A controller's selection on a card: a gold outline round it.
local function padRing(radius: number): Frame
	local ring = Instance.new("Frame")
	ring.Name = "PadRing"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	HudParts.corner(ring, radius)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.color(K.Colors.Gold)
	stroke.Thickness = K.SelectedStrokePx
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = ring
	return ring
end

function EmoteMenu.new(screen: ScreenGui, icon: string)
	local self = setmetatable({}, EmoteMenu) :: any
	self.screen = screen
	self.open = false
	self.cards = {} :: { [string]: Card }
	self.focus = nil :: string?
	self.anchor = Vector2.new(0, 0) -- the button's top centre, in pixels
	self.phone = false

	-- The tray: the card and the arrow under it. It grows out of the arrow's tip (layout puts
	-- the root's AnchorPoint there, the point a UIScale grows from).
	local root = HudParts.frame(screen, "EmoteTray")
	root.Visible = false
	root.ZIndex = 20
	root.SelectionGroup = true -- the stick stays among the cards
	self.root = root
	local arrow = HudParts.frame(root, "Arrow")
	arrow.BackgroundTransparency = 0
	arrow.BackgroundColor3 = color(K.Colors.White)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Rotation = 45
	arrow.ZIndex = 1 -- behind the card: only its lower half shows, a point under the card
	local arrowEdge = Instance.new("UIStroke")
	arrowEdge.Color = HudParts.color(K.Colors.Ink)
	arrowEdge.Thickness = K.PanelStrokePx
	arrowEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	arrowEdge.Parent = arrow
	self.arrow = arrow
	local panel = HudParts.menuCard(root, "Card", K.PanelCornerPx)
	panel.ZIndex = 2
	self.panel = panel

	local header = HudParts.frame(panel, "Header")
	header.ZIndex = 3
	self.header = header
	local art = Instance.new("ImageLabel")
	art.Name = "Icon"
	art.BackgroundTransparency = 1
	art.ScaleType = Enum.ScaleType.Fit
	art.Image = icon
	art.ZIndex = 3
	art.Parent = header
	self.art = art
	local title = HudParts.text(header, "Title", K.Text.Title, W.Title)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.title = title
	local close = HudParts.candy(header, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.Selectable = false
	HudParts.setMinHit(close, 44)
	HudParts.padBack(close)
	self.closeButton = close

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Cards"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = 5
	scroll.ScrollBarImageColor3 = HudParts.color(K.Colors.Ink)
	scroll.ScrollBarImageTransparency = 0.6
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = panel
	self.scroll = scroll
	local grid = Instance.new("UIGridLayout")
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	self.grid = grid
	local padding = Instance.new("UIPadding")
	padding.Parent = scroll
	self.padding = padding

	-- The credit strip.
	local credit = HudParts.frame(panel, "Credit")
	credit.BackgroundTransparency = 0
	credit.BackgroundColor3 = color(K.Colors.White)
	credit.ZIndex = 3
	self.credit = credit
	local edge = HudParts.frame(credit, "Edge")
	edge.BackgroundTransparency = 0
	edge.BackgroundColor3 = HudParts.color(K.Colors.Ink)
	edge.Size = UDim2.new(1, 0, 0, 3)
	edge.ZIndex = 4
	-- One line, so the name and its maker never run into each other: "Rat Dance by
	-- Voxelates", the maker smaller and grey (rich text), cut short with "..." when narrow.
	local name = HudParts.note(credit, "Name", T.CreditNamePx, "")
	name.TextScaled = false
	name.RichText = true
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextWrapped = false
	name.AutoLocalize = false -- a maker's name is never translated
	name.ZIndex = 4
	self.creditName = name
	local shop = Instance.new("TextButton")
	shop.Name = "Shop"
	shop.AutoButtonColor = false
	shop.Text = ""
	shop.Selectable = false
	shop.BackgroundColor3 = color(K.Colors.White)
	shop.ZIndex = 4
	shop.Parent = credit
	HudParts.corner(shop, 999)
	local ring = Instance.new("UIStroke")
	ring.Color = HudParts.color(K.Colors.Ink)
	ring.Thickness = 2
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = shop
	local shopWord = HudParts.note(shop, "Word", 13, W.Shop)
	shopWord.TextWrapped = false
	shopWord.Size = UDim2.new(1, -10, 1, -4)
	shopWord.Position = UDim2.fromOffset(5, 2)
	shopWord.ZIndex = 5
	HudParts.padKey(shop, Enum.KeyCode.ButtonX, K.PadBack)
	shop.Activated:Connect(function()
		self:shopFocus()
	end)
	self.shop = shop

	for index, row in E.List do
		self.cards[row.Id] = self:makeCard(row, index)
	end
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:refreshActive()
	end)
	EmotePlayer.Changed:Connect(function()
		self:refreshFavorites()
	end)
	self:refreshFavorites()
	-- The credit strip's dance name is translated like the cards' (Roblox's
	-- automatic translation) through the game's translator, fetched once; English needs none.
	if string.sub(string.lower(Players.LocalPlayer.LocaleId), 1, 2) ~= "en" then
		task.spawn(function()
			local ok, translator = pcall(function()
				return LocalizationService:GetTranslatorForPlayerAsync(Players.LocalPlayer)
			end)
			if ok and translator then
				self.translator = translator
				self:layoutCredit()
			end
		end)
	end
	return self
end

function EmoteMenu.makeCard(self: any, row: EmoteSync.Row, index: number): Card
	local button = Instance.new("TextButton")
	button.Name = row.Id
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.BackgroundColor3 = color(K.Colors.White)
	button.LayoutOrder = index
	button.ZIndex = 3
	button.SelectionImageObject = padRing(14)
	button.Parent = self.scroll
	HudParts.corner(button, 14)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.color(K.Colors.Ink)
	stroke.Thickness = 3
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = button
	local well = HudParts.frame(button, "Well")
	well.BackgroundTransparency = 0
	well.BackgroundColor3 = color(T.Well)
	well.ZIndex = 4
	HudParts.corner(well, 10)
	local name = HudParts.text(button, "Name", T.NamePx, W.Names[row.Id] or row.Id)
	name.TextWrapped = false
	name.ZIndex = 5
	local star = Instance.new("ImageButton")
	star.Name = "Star"
	star.BackgroundTransparency = 1
	star.Image = K.Icons.Star or ""
	star.ScaleType = Enum.ScaleType.Fit
	star.Selectable = false
	star.AnchorPoint = Vector2.new(0.5, 0.5)
	star.ZIndex = 7
	star.Parent = button
	local card: Card = {
		row = row,
		button = button,
		well = well,
		star = star,
		name = name,
		preview = nil :: any,
		hidden = false,
	}
	card.preview = EmotePreview.new(well, row, function()
		-- The creator removed or changed it: the card goes (the rest close up).
		card.hidden = true
		button.Visible = false
	end)
	button.Activated:Connect(function()
		self:pick(row.Id)
	end)
	star.Activated:Connect(function()
		self:toggleFavorite(row.Id)
	end)
	button.MouseEnter:Connect(function()
		self:setFocus(row.Id)
	end)
	button.SelectionGained:Connect(function()
		self:setFocus(row.Id)
	end)
	return card
end

-- The cards' colours and order from the favourites.
function EmoteMenu.refreshFavorites(self: any)
	local favorites = EmotePlayer.favorites()
	for order, id in EmoteSync.order(E.List, favorites) do
		local card = self.cards[id]
		if card then
			local on = favorites[id] == true
			card.button.LayoutOrder = order
			card.button.BackgroundColor3 = if on
				then color(T.FavoriteFill)
				else color(K.Colors.White)
			card.well.BackgroundColor3 = if on then color(T.FavoriteWell) else color(T.Well)
			card.star.ImageColor3 = if on then Color3.new(1, 1, 1) else color(T.StarOff)
			card.star.ImageTransparency = if on then 0 else T.StarOffFade
		end
	end
	self:refreshActive()
end

function EmoteMenu.toggleFavorite(self: any, id: string)
	local on = not (EmotePlayer.favorites()[id] == true)
	UISound.play("Click")
	EmotePlayer.setFavorite(id, on)
	local card = self.cards[id]
	if card then
		UIAnim.bounce(card.star)
	end
end

-- The credit strip shows the card in focus: hovered or selected, else the dance you are doing
-- (a touch screen has no hover: its Avatar Shop link is for the dance you just tried), else
-- the first card.
function EmoteMenu.setFocus(self: any, id: string?)
	local row = EmoteSync.find(E.List, id or EmotePlayer.current())
	if row == nil then
		local first = EmoteSync.order(E.List, EmotePlayer.favorites())[1]
		row = EmoteSync.find(E.List, first)
	end
	if row == nil then
		return
	end
	self.focus = row.Id
	self.creditRow = row
	self:layoutCredit()
end

function EmoteMenu.shopFocus(self: any)
	local row = if self.focus then EmoteSync.find(E.List, self.focus) else nil
	local catalog = row and row.Catalog
	if catalog == nil then
		return -- our own: not for sale
	end
	UISound.play("Click")
	pcall(function()
		MarketplaceService:PromptPurchase(Players.LocalPlayer, catalog)
	end)
end

function EmoteMenu.pick(self: any, id: string)
	UISound.play("Click")
	self:close()
	task.spawn(function()
		local ok = EmotePlayer.play(id)
		if not ok then
			UISound.play("Click", 0.7)
		end
	end)
end

-- Only the cards inside the tray's window dance.
function EmoteMenu.refreshActive(self: any)
	local scroll = self.scroll
	local top = scroll.AbsolutePosition.Y
	local bottom = top + scroll.AbsoluteSize.Y
	for _, card in self.cards do
		local y = card.button.AbsolutePosition.Y
		local h = card.button.AbsoluteSize.Y
		local seen = self.open and not card.hidden and y + h > top and y < bottom
		if card.preview.active ~= seen then
			card.preview:setActive(seen)
		end
	end
end

--- Lay the tray out for a screen of `size` with the button's top centre at `anchor`.
function EmoteMenu.layout(self: any, size: Vector2, anchor: Vector2, phone: boolean)
	self.anchor, self.phone = anchor, phone
	local width = math.min(if phone then T.PhoneWidthPx else T.WidthPx, size.X - 24)
	if width < 1 then
		return
	end
	local header = if phone then T.PhoneHeaderPx else T.HeaderPx
	local creditPx = if phone then T.PhoneCreditPx else T.CreditPx
	local pad = if phone then math.floor(T.PadPx * 0.6) else T.PadPx
	local gap = if phone then T.PhoneGapPx else T.GapPx
	local cols = T.Columns
	local inner = width - pad * 2 - 6 -- the scroll bar's room
	local cardW = math.floor((inner - gap * (cols - 1)) / cols)
	local namePx = if phone then T.PhoneNamePx else T.NamePx
	local cardH = cardW + namePx + 12
	local rows = 2 + T.PeekShare
	local wanted = header + pad + round(cardH * rows + gap * 2) + creditPx
	local arrowPx = if phone then T.PhoneArrowPx else T.ArrowPx
	local tipY = anchor.Y - (if phone then T.PhoneButtonGapPx else T.ButtonGapPx)
	local height = math.max(
		header + creditPx + cardH,
		math.min(wanted, math.floor(size.Y * T.MaxHeightShare), tipY - arrowPx - T.TopMarginPx)
	)
	-- Above the button and kept on screen, the arrow's tip over the button's centre.
	local left = math.clamp(anchor.X - width / 2, 12, size.X - width - 12)
	local inset = math.min(K.PanelCornerPx + arrowPx, width / 2) -- clear of the round corners
	local tipX = math.clamp(anchor.X - left, inset, width - inset)
	local root = self.root
	root.Size = UDim2.fromOffset(width, height + arrowPx)
	root.AnchorPoint = Vector2.new(tipX / width, 1)
	root.Position = UDim2.fromOffset(round(left + tipX), round(tipY))
	local side = arrowPx * math.sqrt(2) -- a square turned 45 degrees: its lower half shows
	self.arrow.Size = UDim2.fromOffset(side, side)
	self.arrow.Position = UDim2.fromOffset(tipX, height)
	local panel = self.panel
	panel.Size = UDim2.fromOffset(width, height)
	HudParts.setSheetTop(panel, header)
	local h = self.header
	h.Position = UDim2.fromOffset(0, 0)
	h.Size = UDim2.new(1, 0, 0, header)
	local art = self.art
	art.Position = UDim2.fromOffset(pad - 2, 4)
	art.Size = UDim2.fromOffset(header - 8, header - 8)
	local closePx = header - 16
	self.closeButton.AnchorPoint = Vector2.new(1, 0.5)
	self.closeButton.Position = UDim2.new(1, -pad, 0.5, 0)
	self.closeButton.Size = UDim2.fromOffset(closePx, closePx)
	self.title.Position = UDim2.fromOffset(pad + header - 4, 0)
	self.title.Size = UDim2.new(1, -(pad * 2 + header + closePx), 1, 0)
	HudParts.setTextSize(self.title, if phone then 22 else K.Text.Title)
	local scroll = self.scroll
	scroll.Position = UDim2.fromOffset(0, header)
	scroll.Size = UDim2.new(1, 0, 1, -(header + creditPx))
	self.padding.PaddingLeft = UDim.new(0, pad)
	self.padding.PaddingRight = UDim.new(0, pad + 6)
	self.padding.PaddingTop = UDim.new(0, pad)
	self.padding.PaddingBottom = UDim.new(0, pad)
	self.grid.CellSize = UDim2.fromOffset(cardW, cardH)
	self.grid.CellPadding = UDim2.fromOffset(gap, gap)
	local starPx = math.max(18, math.floor(cardW * 0.3))
	for _, card in self.cards do
		card.well.Position = UDim2.fromOffset(4, 4)
		card.well.Size = UDim2.new(1, -8, 0, cardW - 8)
		card.name.Position = UDim2.fromOffset(2, cardW - 2)
		card.name.Size = UDim2.new(1, -4, 0, namePx + 8)
		HudParts.setTextSize(card.name, namePx, math.min(namePx, 10))
		card.star.Position = UDim2.new(1, -starPx * 0.25, 0, starPx * 0.2)
		card.star.Size = UDim2.fromOffset(starPx, starPx)
	end
	local credit = self.credit
	credit.Position = UDim2.new(0, 0, 1, -creditPx)
	credit.Size = UDim2.new(1, 0, 0, creditPx)
	HudParts.corner(credit, 0)
	self:layoutCredit()
	self:refreshActive()
end

function EmoteMenu.layoutCredit(self: any)
	local phone = self.phone
	local pad = if phone then 8 else 12
	local shopW = if phone then T.PhoneShopPx else T.ShopPx
	self.shop.AnchorPoint = Vector2.new(1, 0.5)
	self.shop.Position = UDim2.new(1, -pad, 0.5, 1)
	self.shop.Size = UDim2.new(0, shopW, 0.62, 0) -- of the strip's height
	local row = self.creditRow
	-- Our own emotes are not for sale: no Avatar Shop link, the name takes the strip.
	local forSale = row == nil or row.Catalog ~= nil
	self.shop.Visible = forSale
	local name = self.creditName
	name.TextSize = if phone then T.PhoneCreditNamePx else T.CreditNamePx
	name.Position = UDim2.fromOffset(pad, 3)
	name.Size = UDim2.new(1, -(pad * 2 + (if forSale then shopW + 6 else 0)), 1, -3)
	if row == nil then
		name.Text = ""
		return
	end
	local title = W.Names[row.Id] or row.Id
	local translator = self.translator
	if translator then
		local ok, text = pcall(translator.Translate, translator, game, title)
		if ok and type(text) == "string" and text ~= "" then
			title = text
		end
	end
	name.Text = ('%s  <font size="%d" color="#%s">%s</font>'):format(
		escape(title),
		if phone then T.PhoneCreditByPx else T.CreditByPx,
		color(T.CreditBy):ToHex(),
		escape(W.By:format(row.Creator))
	)
end

function EmoteMenu.isOpen(self: any): boolean
	return self.open
end

--- Open the tray (the button or R3).
function EmoteMenu.show(self: any)
	if self.open then
		return
	end
	self.open = true
	EmotePlayer.preloadMusic()
	-- Out of the arrow, like a dropdown: never past the button (a slam from big reached over it).
	self.root.Visible = true
	UIAnim.expandIn(self.root, 0, T.OpenFromScale)
	local order = EmoteSync.order(E.List, EmotePlayer.favorites())
	for i, id in order do
		local card = self.cards[id]
		if card and i <= T.Columns * 2 then
			UIAnim.expandIn(card.button, 0.06 + i * 0.025, 0.4)
		end
	end
	self.scroll.CanvasPosition = Vector2.zero
	self:setFocus(nil)
	task.defer(function()
		self:layoutCredit()
		self:refreshActive()
	end)
	ContextActionService:BindActionAtPriority(
		ACTION,
		function(_, inputState, input)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Sink
			end
			local key = input.KeyCode
			if key == Enum.KeyCode.ButtonB or key == Enum.KeyCode.Escape then
				UISound.play("Click")
				self:close()
			elseif key == Enum.KeyCode.ButtonY then
				local selected = GuiService.SelectedObject
				for id, card in self.cards do
					if selected == card.button then
						self:toggleFavorite(id)
					end
				end
			elseif key == Enum.KeyCode.ButtonX then
				self:shopFocus()
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value + 30,
		Enum.KeyCode.ButtonB,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.Escape
	)
	-- A controller lands on the first card.
	local first = self.cards[order[1]]
	if first and UserInputService.GamepadEnabled and PadMode.active() then
		GuiService.SelectedObject = first.button
	end
	task.spawn(function()
		pcall(function()
			Net.get("EmoteRequest"):InvokeServer("Open")
		end)
	end)
end

--- Close the tray.
function EmoteMenu.close(self: any)
	if not self.open then
		return
	end
	self.open = false
	ContextActionService:UnbindAction(ACTION)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.root) then
		GuiService.SelectedObject = nil
	end
	self:refreshActive()
	UIAnim.popOut(self.root)
end

return EmoteMenu
