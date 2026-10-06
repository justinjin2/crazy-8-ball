--!strict
-- MenuFrame: the one frame every full menu is built on (docs/prompts/ECONOMY_UI_PROMPT.md
-- section 5.1; the Shop, Inventory, Rewards and Trade reuse it), laid out like the roadmap
-- (reference 03, UI_STYLE section 2):
--
--   * a kit menu card (HudParts.menuCard) over the roadmap's slight dim (the one dim UI_STYLE
--     allows; a full menu is the same kind of screen as the roadmap, overnight assumption
--     2026-09-28); a tap on the dim closes the menu;
--   * the pale-blue header band: the menu's icon, its title (Fredoka, white, ink outline), an
--     optional money pill and the red X (a 44 px touch area);
--   * a row of tabs as candy buttons (blue when selected, white otherwise), each switching a
--     page; on a phone they share the title row when they fit there;
--   * the pages on the sheet: each tab's page is an empty Frame the menu fills.
--
-- Phone first: on a phone-sized screen (750 x 361) the panel takes the whole screen, its title
-- in Roblox's top bar row right of Roblox's buttons, and every button keeps a 44 px touch area;
-- on a computer it is a capped panel centred under the top bar, its rows and text growing from
-- their phone sizes to their full sizes with the panel (Config.UI.Menu.Frame).
--
-- It pops in and out with UIAnim, lives in its own ScreenGui just over the HUD's (like the
-- roadmap), and routes its red X and dim to Menus (which closes it and puts the gamepad's
-- selection back). Gamepad: the selection opens on the chosen tab, LB and RB switch tabs, B
-- closes (Menus); the panel is a selection group that stops at its edges.
--
-- Also here, for the menus' contents: a vertical scroller with a list or a self-fitting grid
-- (MenuFrame.scroller), a card tile like reference 03's reward tiles (MenuFrame.tile), the
-- kit's confirm dialog with no dim (MenuFrame.confirm: red for sell, blue for keep) and a short
-- notice line for the server's answers (MenuFrame.notice, MenuFrame.reason).
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local ScreenBlur = require(script.Parent.ScreenBlur)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local F = Config.UI.Menu.Frame
local SC = Config.UI.Menu.Scroll
local CARD = Config.UI.Menu.Card
local CONFIRM = Config.UI.Menu.Confirm
local NOTICE = Config.UI.Menu.Notice
local DIM = Config.UI.Progress.Roadmap -- the roadmap's slight dim, reused as it is
local K = Config.UI.Kit
local ICONS: { [string]: string } = K.Icons :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color
local tone = HudParts.tone
local INK = tone("Ink")
local WHITE = tone("White")
local GOLD = tone("Gold")
local QUICK = Config.Multiplayer.Style.QuickMotion
-- Over the roadmap's B (High + 10) like Menus' B, for LB and RB; a dialog's B sits above both.
local TAB_PRIORITY = Enum.ContextActionPriority.High.Value + 20
local DIALOG_PRIORITY = Enum.ContextActionPriority.High.Value + 30

export type Tab = { key: string, text: string, icon: string? }

export type Options = {
	name: string, -- the Menus name ("Shop"); the ScreenGui is "<name>Menu"
	title: string, -- from Strings
	icon: string?, -- a Config.UI.Kit.Icons key for the header
	tabs: { Tab }?, -- none: one page, "Main"
	money: boolean?, -- show the player's money in the header (the Shop, the Inventory)
}

-- The sizes of the last layout, for the pages (onLayout).
export type Geo = {
	t: number, -- 0 on a phone-sized panel, 1 on a full-size one
	short: boolean, -- a phone: the panel takes the whole screen
	pad: number,
	gap: number,
	title: number, -- text sizes, never under the kit's minimum
	heading: number,
	body: number,
	button: number,
	content: Vector2, -- the pages' size in pixels
}

export type Tile = {
	button: TextButton, -- the whole card: press, hover, gamepad
	body: Frame, -- everything drawn, grown on hover and squished on press
	fill: Frame, -- the white card face (CueThumb.dress puts a rarity on it)
	art: Frame, -- the square picture box: holds the icon, or put a CueThumb in it
	icon: ImageLabel,
	title: TextLabel, -- the name (white, ink outline)
	count: TextLabel, -- the count line ("x3"), ink
	badge: Frame, -- the top-right slot for pills (NEW, Equipped), laid out right to left
	edge: UIStroke,
}

export type TileOptions = {
	icon: string?, -- a Config.UI.Kit.Icons key
	title: string?,
	count: string?,
	onPress: (() -> ())?, -- none: the card is only a picture (not selectable)
	name: string?, -- the Instance's name
	order: number?, -- LayoutOrder in a list or grid
}

export type ScrollOptions = {
	kind: string?, -- "List" (default) or "Grid"
	name: string?,
	gap: number?, -- between cards (Scroll.GapPx)
	pad: number?, -- inside the scroller (Scroll.PadPx)
	minCell: number?, -- a grid: each card at least this wide (Scroll.GridMinCellPx)
	aspect: number?, -- a grid: a card's height, of its width (Scroll.GridAspect)
	cellHeight: number?, -- a grid: a fixed card height instead of the aspect
}

export type ConfirmOptions = {
	title: string?, -- a heading over the question (white, ink outline)
	text: string, -- the question (ink)
	yes: string?, -- the button that acts ("Sell"); Strings.Menus.Yes
	no: string?, -- the button that keeps things as they are ("Keep"); Strings.Menus.No
	yesTone: string?, -- a Kit.Buttons tone: "Red" (the default) for selling
	noTone: string?, -- "Blue" (the default) for keeping
}

export type Dialog = {
	cancel: () -> (), -- close it as if No was pressed (nothing happens if it already closed)
	isOpen: () -> boolean,
}

local MenuFrame = {}
MenuFrame.__index = MenuFrame

--------------------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------------------

local function round(n: number): number
	return math.floor(n + 0.5)
end

-- A { phone, full } pair at t (0 a phone-sized panel, 1 a full one), in whole pixels.
local function span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

local function hasIcon(key: string?): boolean
	return key ~= nil and type(ICONS[key]) == "string" and ICONS[key] ~= ""
end

local function isGamepad(kind: Enum.UserInputType): boolean
	return string.sub(kind.Name, 1, 7) == "Gamepad"
end

local function gamepadInUse(): boolean
	return isGamepad(UserInputService:GetLastInputType())
end

--- How much the UIScales on an object and its ancestors grow or shrink it (a panel popping in,
--- a card hovered). AbsoluteSize includes them but offsets inside are scaled again, so a
--- layout from AbsoluteSize divides them out.
function MenuFrame.scaleOf(object: Instance): number
	local total = 1
	local node: Instance? = object
	while node and not node:IsA("LayerCollector") do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then
				total *= child.Scale
			end
		end
		node = node.Parent
	end
	return if total > 0 then total else 1
end

-- A clear button that swallows presses: the dim (which closes) and the panel's floor (so a
-- press on the panel's empty parts does not reach the dim).
local function catcher(parent: Instance, name: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = ""
	button.AutoButtonColor = false
	button.Selectable = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.Parent = parent
	return button
end

-- An empty selection box: the kit draws its own gold outline on whatever is selected.
local function noBox(): Frame
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	return box
end

-- The free part of Roblox's top bar, measured once for every menu (as the roadmap does): a
-- ScreenGui with ScreenInsets.TopbarSafeInsets and a frame filling it.
local probeArea: Frame? = nil
local function topbarArea(parent: Instance): Frame
	local area = probeArea
	if area and area.Parent and area.Parent.Parent then
		return area
	end
	local probe = Instance.new("ScreenGui")
	probe.Name = "MenuTopbar"
	probe.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	probe.ResetOnSpawn = false
	probe.Parent = parent
	local made = HudParts.frame(probe, "Area")
	made.Size = UDim2.fromScale(1, 1)
	probeArea = made
	return made
end

--------------------------------------------------------------------------------------------
-- The frame
--------------------------------------------------------------------------------------------

--- Build a menu's frame (closed). `screen` is the shared HUD ScreenGui: the menu makes its own
--- ScreenGui beside it, just above it (over the rank and money HUDs, like the roadmap).
---
--- Fields a menu uses: `root` (the full-screen frame everything is in), `panel`, `card`,
--- `geo` (the last layout's sizes), and the callbacks it may set: `onTab(key)` (a page is
--- shown: on every tab switch and every open), `onOpen()`, `onClose()`, `onLayout(geo)` (the
--- screen changed size; re-fit the pages).
function MenuFrame.new(screen: ScreenGui, opts: Options): any
	local self: any = setmetatable({}, MenuFrame)
	self.name = opts.name
	self.titleText = opts.title
	self.iconKey = opts.icon
	self.showMoney = opts.money == true
	self.opened = false
	self.alive = true
	self.selected = nil :: string?
	self.connections = {} :: { RBXScriptConnection }
	self.openConnections = {} :: { RBXScriptConnection }
	self.tabsBound = false
	self.dialogs = {} :: { Dialog }
	self.dimTween = nil :: Tween?
	self.geo = nil :: Geo?
	self.onTab = nil :: ((string) -> ())?
	self.onOpen = nil :: (() -> ())?
	self.onClose = nil :: (() -> ())?
	self.onLayout = nil :: ((Geo) -> ())?

	local tabs: { Tab } = opts.tabs or {}
	self.tabs = tabs
	self.tabKeys = {} :: { string }
	for _, tab in tabs do
		table.insert(self.tabKeys, tab.key)
	end
	if #self.tabKeys == 0 then
		table.insert(self.tabKeys, "Main")
	end

	local parent = screen.Parent
	-- Over the whole screen, Roblox's top bar row included, so the dim covers everything and a
	-- phone's panel can use that row (as the roadmap). Coordinates stay shared with every
	-- ScreenGui.
	local gui = Instance.new("ScreenGui")
	gui.Name = opts.name .. "Menu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + DIM.DisplayOrderAbove
	gui.Enabled = false
	gui.Parent = parent
	self.gui = gui
	self.area = if parent then topbarArea(parent) else nil

	local root = HudParts.frame(gui, "Root")
	root.Size = UDim2.fromScale(1, 1)
	self.root = root
	local dim = catcher(root, "Backdrop")
	dim.BackgroundColor3 = INK
	dim.Activated:Connect(function()
		self:dismiss()
	end)
	self.dim = dim

	local panel = HudParts.frame(root, "Panel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.ZIndex = 2
	panel.Visible = false
	panel.SelectionGroup = true
	panel.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	panel.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.panel = panel
	catcher(panel, "Floor").ZIndex = 0
	local card = HudParts.menuCard(panel, "Card")
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 1
	if HudParts.paleEdged(opts.name) then
		HudParts.paleEdge(card)
	end
	self.card = card

	-- The header: icon, title, (money), red X.
	local header = HudParts.frame(card, "Header")
	header.ZIndex = 2
	self.header = header
	local icon = HudParts.icon(header, opts.icon or "Trophy", "Icon")
	icon.Visible = hasIcon(opts.icon)
	self.icon = icon
	local title = HudParts.text(header, "Title", K.Text.Title, opts.title)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	self.title = title
	local close = HudParts.candy(header, "", function()
		UISound.play("Click")
		self:dismiss()
	end, "Red", "X")
	close.Name = "Close"
	HudParts.setMinHit(close, F.TouchMinPx)
	self.closeButton = close
	if self.showMoney then
		local pill = HudParts.pill(header, "Money", WHITE)
		local cash = HudParts.icon(pill, "CashSingle", "Cash")
		cash.AnchorPoint = Vector2.new(0, 0.5)
		cash.ZIndex = 2
		local amount = HudParts.text(pill, "Amount", K.Text.Body, "")
		amount.AutoLocalize = false -- a number
		amount.TextWrapped = false
		amount.TextXAlignment = Enum.TextXAlignment.Left
		amount.ZIndex = 2
		self.moneyPill, self.moneyCash, self.moneyAmount = pill, cash, amount
		self:refreshMoney()
	end

	-- The tabs.
	local tabRow = HudParts.frame(card, "Tabs")
	tabRow.ZIndex = 2
	self.tabRow = tabRow
	self.tabButtons = {} :: { [string]: TextButton }
	for index, tab in tabs do
		local key = tab.key
		local button = HudParts.candy(tabRow, tab.text, function()
			if self.selected ~= key then
				UISound.play("Click")
			end
			self:selectTab(key)
		end, if index == 1 then "Blue" else "White", if hasIcon(tab.icon) then tab.icon else nil)
		button.Name = "Tab" .. key
		button.NextSelectionUp = close
		self.tabButtons[key] = button
	end
	close.NextSelectionUp = close
	close.NextSelectionRight = close

	-- The pages, one per tab, on the sheet.
	local content = HudParts.frame(card, "Content")
	content.ZIndex = 2
	self.content = content
	self.pages = {} :: { [string]: Frame }
	for index, key in self.tabKeys do
		local page = HudParts.frame(content, "Page" .. key)
		page.Size = UDim2.fromScale(1, 1)
		page.ZIndex = 2
		page.Visible = index == 1
		self.pages[key] = page
	end
	self.selected = self.tabKeys[1]

	local function resized()
		if self.opened then
			self:layout()
		end
	end
	table.insert(self.connections, root:GetPropertyChangedSignal("AbsoluteSize"):Connect(resized))
	local area = self.area
	if area then
		for _, property in { "AbsoluteSize", "AbsolutePosition" } do
			table.insert(self.connections, area:GetPropertyChangedSignal(property):Connect(resized))
		end
	end
	return self
end

--- A tab's page (the menu fills it); `key` defaults to the first tab ("Main" with no tabs).
function MenuFrame.page(self: any, key: string?): Frame
	return self.pages[key or self.tabKeys[1]]
end

--- A tab's button (to jump the gamepad there, or add a red dot to it).
function MenuFrame.tabButton(self: any, key: string): TextButton?
	return self.tabButtons[key]
end

--- The tab showing now.
function MenuFrame.currentTab(self: any): string
	return self.selected
end

--- Show a tab's page. Calls onTab(key) when the page changes (and the menu is open).
function MenuFrame.selectTab(self: any, key: string)
	if not self.pages[key] then
		return
	end
	local changed = self.selected ~= key
	self.selected = key
	for name, page in self.pages do
		page.Visible = name == key
	end
	for name, button in self.tabButtons do
		HudParts.setTone(button, if name == key then "Blue" else "White")
	end
	local chosen = self.tabButtons[key]
	if chosen then
		self.closeButton.NextSelectionDown = chosen
	end
	if changed and self.opened and self.onTab then
		self.onTab(key)
	end
end

-- LB (-1) and RB (+1): the tab before or after, wrapping; a gamepad on a tab follows.
function MenuFrame.stepTab(self: any, dir: number)
	local keys: { string } = self.tabKeys
	if #self.tabs < 2 then
		return
	end
	local at = table.find(keys, self.selected) or 1
	local key = keys[(at - 1 + dir) % #keys + 1]
	local selected = GuiService.SelectedObject
	local onTab = selected ~= nil and selected:IsDescendantOf(self.tabRow)
	UISound.play("Click")
	self:selectTab(key)
	if onTab then
		GuiService.SelectedObject = self.tabButtons[key]
	end
end

function MenuFrame.setTitle(self: any, text: string)
	self.titleText = text
	self.title.Text = text
	if self.opened then
		self:layout()
	end
end

-- The money pill's number, from the save's attribute (the server's truth).
function MenuFrame.refreshMoney(self: any)
	local amount: TextLabel? = self.moneyAmount
	if not amount then
		return
	end
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("Money") else nil
	local words = Format.money(if type(value) == "number" and value == value then value else 0)
	if amount.Text ~= words then
		local grew = #amount.Text ~= #words
		amount.Text = words
		if grew and self.opened then
			self:layout()
		end
	end
end

--- Where money chips can land in this menu (the header's cash), in absolute pixels; nil when
--- the menu shows no money.
function MenuFrame.moneyCenter(self: any): Vector2?
	local cash: ImageLabel? = self.moneyCash
	if not cash then
		return nil
	end
	return cash.AbsolutePosition + cash.AbsoluteSize / 2
end

--------------------------------------------------------------------------------------------
-- Layout (from the screen's size; on open and when the screen changes)
--------------------------------------------------------------------------------------------

-- Roblox's top bar in the root's pixels: its free part's left and right edges and the row's
-- bottom (fallbacks when Roblox does not say).
function MenuFrame.topbar(self: any, size: Vector2): (number, number, number)
	local area: Frame? = self.area
	local probe = area and area.Parent
	if area and probe and probe.Parent and area.AbsoluteSize.Y > 0 then
		local origin = self.root.AbsolutePosition
		local left = area.AbsolutePosition.X - origin.X
		local top = math.max(0, area.AbsolutePosition.Y - origin.Y)
		return left, left + area.AbsoluteSize.X, top + area.AbsoluteSize.Y
	end
	return F.TopbarLeftFallbackPx, size.X, GuiService:GetGuiInset().Y
end

-- Each tab's natural width at this height and text size (as the candy lays out its words).
function MenuFrame.tabWidths(self: any, height: number, textSize: number): ({ number }, number)
	local widths: { number } = {}
	local total = 0
	local usable = height - math.floor(height * K.ButtonLipShare + 0.5)
	local pad = math.max(6, math.floor(usable * 0.18))
	for index, tab in self.tabs do
		local left = pad
		if hasIcon(tab.icon) then
			left = pad + math.floor(usable * K.ButtonIconShare) + math.floor(pad / 2)
		end
		-- The words, their outline each side, and the pad after them.
		local width = left + math.ceil(textWidth(tab.text, textSize)) + 6 + pad
		width = math.max(F.TabMinWidthPx, width)
		widths[index] = width
		total += width
	end
	return widths, total
end

--- Size and place the panel and its rows from the screen's size. False while the screen has
--- no size yet.
function MenuFrame.layout(self: any): boolean
	local size: Vector2 = self.root.AbsoluteSize
	if size.X < 1 or size.Y < 1 then
		return false
	end
	local barLeft, barRight, barBottom = self:topbar(size)
	local margin = F.MarginPx
	local short = size.Y - barBottom < F.ShortScreenPx
	local roomTop = if short then 0 else barBottom
	-- A computer: centred on the whole screen (not just under the bar), clear of the bar, and
	-- never closer than BottomGapPx to the bottom edge, shadow included (designer, 2026-10-03).
	local roomBottom = if short then size.Y else size.Y - F.BottomGapPx
	local roomHeight = roomBottom - roomTop
	local w = math.floor(math.min(size.X - 2 * margin, F.MaxSizePx[1]))
	local h = math.floor(math.min(roomHeight - 2 * margin, F.MaxSizePx[2]))
	local left = math.floor((size.X - w) / 2)
	local top = if short
		then math.floor(roomTop + (roomHeight - h) / 2)
		else math.floor(
			math.clamp((size.Y - h) / 2, roomTop + margin, roomBottom - margin - h)
		)
	self.panel.Size = UDim2.fromOffset(w, h)
	self.panel.Position = UDim2.fromOffset(left + w / 2, top + h / 2)

	-- Rows run from their phone size to their full size as the panel grows.
	local k = math.clamp(h / F.DesignHeightPx, F.MinScale, 1)
	local t = (k - F.MinScale) / (1 - F.MinScale)
	local pad = span(F.PaddingPx, t)
	local gap = span(F.GapPx, t)
	local iw = w - 2 * pad
	local titleSize = math.max(K.Text.Min, round(K.Text.Title * F.TitleScale * k))
	local heading = math.max(K.Text.Min, round(K.Text.Heading * k))
	local body = math.max(K.Text.Min, round(K.Text.Body * k))
	local buttonText = math.max(K.Text.Min, round(K.Text.Button * k))
	local tabH = math.max(F.TouchMinPx, span(F.TabPx, t))
	local tabText = math.max(K.Text.Min, span(F.TabTextPx, t))

	-- The title row; on a phone it is Roblox's top bar row, right of Roblox's buttons.
	local headerH, headLeft, headRight = span(F.HeaderPx, t), 0, 0
	if short then
		headerH = math.max(F.TouchMinPx, barBottom - top - pad)
		headLeft = math.max(0, barLeft - left - pad + gap)
		headRight = math.max(0, left + w - pad - barRight)
	end
	self.header.Position = UDim2.fromOffset(pad, pad)
	self.header.Size = UDim2.fromOffset(iw, headerH)

	-- Right to left: the X, then the money pill.
	local closeSize = math.min(headerH, F.CloseMaxPx)
	local close: TextButton = self.closeButton
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Size = UDim2.fromOffset(closeSize, closeSize)
	close.Position = UDim2.fromOffset(iw - headRight, round(headerH / 2))
	local right = iw - headRight - closeSize - gap -- where the left group must end
	local pill: Frame? = self.moneyPill
	if pill then
		local mh = math.min(headerH, span(F.MoneyPx, t))
		local mt = math.max(K.Text.Min, span(F.MoneyTextPx, t))
		local cash = round(mh * F.MoneyIconShare)
		local over = round(cash * 0.35) -- the bundle pokes out past the pill's left end
		local amount: TextLabel = self.moneyAmount
		HudParts.setTextSize(amount, mt)
		local words = math.ceil(textWidth(amount.Text, mt)) + 6
		local mw = cash - over + 4 + words + 8
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Size = UDim2.fromOffset(mw, mh)
		pill.Position = UDim2.fromOffset(right, round(headerH / 2))
		self.moneyCash.Size = UDim2.fromOffset(cash, cash)
		self.moneyCash.Position = UDim2.new(0, -over, 0.5, 0)
		amount.Position = UDim2.fromOffset(cash - over + 4, 0)
		amount.Size = UDim2.fromOffset(words, mh)
		right -= mw + over + gap
	end

	-- Left to right: the icon, the title.
	local x = headLeft
	local icon: ImageLabel = self.icon
	if icon.Visible then
		local iconSize = math.min(headerH, round(titleSize * F.IconShare))
		icon.Size = UDim2.fromOffset(iconSize, iconSize)
		icon.Position = UDim2.fromOffset(x, round((headerH - iconSize) / 2))
		x += iconSize + gap
	end
	HudParts.setTextSize(self.title, titleSize)
	local titleW =
		math.max(1, math.min(math.ceil(textWidth(self.titleText, titleSize)) + 8, right - x))
	self.title.Position = UDim2.fromOffset(x, 0)
	self.title.Size = UDim2.fromOffset(titleW, headerH)
	x += titleW + gap

	-- The tabs: beside the title on a phone when they fit there, else a row under it.
	local sheetTop = pad + headerH + round(gap / 2)
	local tabRow: Frame = self.tabRow
	if #self.tabs > 0 then
		local tabGap = span(F.TabGapPx, t)
		local widths, total = self:tabWidths(tabH, tabText)
		total += tabGap * (#widths - 1)
		local beside = short and F.TabsBesideTitle and tabH <= headerH and total <= right - x
		local rowW, rowX, rowY
		if beside then
			rowX, rowY, rowW = pad + x, pad + round((headerH - tabH) / 2), total
		else
			rowX, rowY, rowW = pad, pad + headerH + gap, iw
			sheetTop = rowY + tabH + round(gap / 2)
			if total > iw then
				-- Too wide (a long translation): every tab gives up the same share, and its
				-- words shrink to fit (never under the kit's minimum).
				local share = (iw - tabGap * (#widths - 1)) / (total - tabGap * (#widths - 1))
				for i, width in widths do
					widths[i] = math.floor(width * share)
				end
			end
		end
		tabRow.Position = UDim2.fromOffset(rowX, rowY)
		tabRow.Size = UDim2.fromOffset(rowW, tabH)
		local at = 0
		for index, tab in self.tabs do
			local button: TextButton = self.tabButtons[tab.key]
			button.Position = UDim2.fromOffset(at, 0)
			button.Size = UDim2.fromOffset(widths[index], tabH)
			HudParts.setButtonTextSize(button, tabText)
			at += widths[index] + tabGap
		end
		tabRow.Visible = true
	else
		tabRow.Visible = false
	end
	HudParts.setSheetTop(self.card, sheetTop)

	-- The pages, on the sheet (inset from the panel's outline), padded inside it.
	local inset = K.SheetInsetPx
	local cp = span(F.ContentPadPx, t)
	local cw = math.max(1, w - 2 * (inset + cp))
	local ch = math.max(1, h - sheetTop - inset - 2 * cp)
	self.content.Position = UDim2.fromOffset(inset + cp, sheetTop + cp)
	self.content.Size = UDim2.fromOffset(cw, ch)

	local geo: Geo = {
		t = t,
		short = short,
		pad = pad,
		gap = gap,
		title = titleSize,
		heading = heading,
		body = body,
		button = buttonText,
		content = Vector2.new(cw, ch),
	}
	self.geo = geo
	if self.onLayout then
		self.onLayout(geo)
	end
	return true
end

--------------------------------------------------------------------------------------------
-- Open and close
--------------------------------------------------------------------------------------------

-- The red X and the dim: through Menus (which puts the gamepad's selection back), or straight
-- closed when this frame was never registered.
function MenuFrame.dismiss(self: any)
	if Menus.isRegistered(self.name) then
		Menus.close(self.name)
	else
		self:close()
	end
end

--- Put the gamepad on the chosen tab (the X when there are no tabs).
function MenuFrame.focus(self: any)
	GuiService.SelectedObject = self.tabButtons[self.selected] or self.closeButton
end

function MenuFrame.focused(self: any): boolean
	local selected = GuiService.SelectedObject
	return selected ~= nil and selected:IsDescendantOf(self.root)
end

function MenuFrame.listen(self: any)
	local list = self.openConnections
	-- A gamepad picked up while the menu is open lands on the chosen tab.
	table.insert(
		list,
		UserInputService.LastInputTypeChanged:Connect(function(kind)
			if isGamepad(kind) and not self:focused() and #self.dialogs == 0 then
				self:focus()
			end
		end)
	)
	local player = Players.LocalPlayer
	if self.moneyPill and player then
		table.insert(
			list,
			player:GetAttributeChangedSignal("Money"):Connect(function()
				self:refreshMoney()
			end)
		)
	end
	if #self.tabs > 1 then
		ContextActionService:BindActionAtPriority(
			"8ballMenuTabs" .. self.name,
			function(_name: string, state: Enum.UserInputState, input: InputObject)
				if state == Enum.UserInputState.Begin and #self.dialogs == 0 then
					self:stepTab(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			TAB_PRIORITY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1
		)
		self.tabsBound = true
	end
end

function MenuFrame.unlisten(self: any)
	for _, connection in self.openConnections do
		connection:Disconnect()
	end
	table.clear(self.openConnections)
	if self.tabsBound then
		self.tabsBound = false
		ContextActionService:UnbindAction("8ballMenuTabs" .. self.name)
	end
end

--- Pop the menu in (on `tab`, if given). A gamepad lands on the chosen tab. Menus.open is how
--- the game opens a menu; this is what its handle calls.
function MenuFrame.open(self: any, tab: string?)
	if not self.alive then
		return
	end
	if tab and self.pages[tab] and tab ~= self.selected then
		self:selectTab(tab)
	end
	if self.opened then
		return
	end
	self.opened = true
	self.gui.Enabled = true
	self.dim.Modal = true -- frees a mouse that shift-lock (or the camera) holds
	self:refreshMoney()
	self:layout()
	if self.dimTween then
		self.dimTween:Cancel()
	end
	self.dimTween = TweenService:Create(
		self.dim,
		TweenInfo.new(DIM.DimSeconds),
		{ BackgroundTransparency = DIM.DimTransparency }
	)
	self.dimTween:Play()
	ScreenBlur.set(self, true)
	UIAnim.popIn(self.panel)
	UIAnim.glowBurst(self.panel, nil, 0.15) -- a bigger open (UI_STYLE 13)
	self:listen()
	if gamepadInUse() then
		self:focus()
	end
	if self.onOpen then
		self.onOpen()
	end
	if self.onTab then
		self.onTab(self.selected)
	end
end

--- Pop the menu out. An open confirm dialog is answered No; a selection inside it is dropped
--- (Menus puts back the one from before).
function MenuFrame.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	self.dim.Modal = false
	self:unlisten()
	local dialogs: { Dialog } = table.clone(self.dialogs)
	for _, dialog in dialogs do
		dialog.cancel()
	end
	table.clear(self.dialogs)
	if self:focused() then
		GuiService.SelectedObject = nil
	end
	if self.dimTween then
		self.dimTween:Cancel()
	end
	self.dimTween =
		TweenService:Create(self.dim, TweenInfo.new(DIM.DimSeconds), { BackgroundTransparency = 1 })
	self.dimTween:Play()
	ScreenBlur.set(self, false)
	UIAnim.popOut(self.panel, function()
		if not self.opened and self.alive then
			self.gui.Enabled = false
		end
	end)
	if self.onClose then
		self.onClose()
	end
end

function MenuFrame.isOpen(self: any): boolean
	return self.opened
end

--- A short line from the server's answer at the bottom of this menu: frame:notice(text,
--- tone?). Also callable as MenuFrame.notice(parent, text, tone?) for any GuiObject (see
--- MenuFrame.showNotice).
function MenuFrame.notice(target: any, text: string, toneName: string?)
	if typeof(target) == "Instance" and target:IsA("GuiObject") then
		MenuFrame.showNotice(target, text, toneName)
		return
	end
	MenuFrame.showNotice(target.panel, text, toneName)
end

--- Ask before doing something, over this menu: frame:confirm(opts, callback). A gamepad goes
--- to No; closing the menu answers No. Also callable as MenuFrame.confirm(parent, opts,
--- callback) over any GuiObject (MenuFrame.ask).
function MenuFrame.confirm(target: any, opts: ConfirmOptions, callback: (boolean) -> ()): Dialog
	if typeof(target) == "Instance" and target:IsA("GuiObject") then
		return MenuFrame.ask(target, opts, callback)
	end
	local self = target
	local dialog: Dialog
	dialog = MenuFrame.ask(self.panel, opts, function(yes: boolean)
		local at = table.find(self.dialogs, dialog)
		if at then
			table.remove(self.dialogs, at)
		end
		callback(yes)
	end)
	table.insert(self.dialogs, dialog)
	return dialog
end

function MenuFrame.destroy(self: any)
	if not self.alive then
		return
	end
	self:close()
	self.alive = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.gui:Destroy()
end

--------------------------------------------------------------------------------------------
-- Helpers for the menus' contents
--------------------------------------------------------------------------------------------

--- A centred ink line on an empty page ("Loading...", or an empty state's words).
function MenuFrame.placeholder(page: Instance, text: string?): TextLabel
	local label =
		HudParts.note(page, "Placeholder", F.PlaceholderTextPx, text or Strings.Menus.Loading)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -16, 0, F.PlaceholderTextPx * 3)
	label.ZIndex = 3
	return label
end

--- A vertical scroller filling `parent`, with a list (cards stacked, centred) or a grid that
--- fits as many columns as keep each card `minCell` wide. Returns the ScrollingFrame (put the
--- cards in it, ordered by LayoutOrder) and its layout. The canvas grows with its contents;
--- a gamepad selection inside scrolls itself into view.
function MenuFrame.scroller(
	parent: Instance,
	opts: ScrollOptions?
): (ScrollingFrame, UIGridStyleLayout)
	local o: ScrollOptions = opts or {}
	local gap = o.gap or SC.GapPx
	local pad = o.pad or SC.PadPx
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = o.name or "Scroller"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SC.BarPx
	scroll.ScrollBarImageColor3 = color(SC.BarColor)
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = parent
	-- Room round the cards for a hovered card's grow and its gold outline.
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, pad)
	padding.PaddingBottom = UDim.new(0, pad)
	padding.PaddingLeft = UDim.new(0, pad)
	padding.PaddingRight = UDim.new(0, pad)
	padding.Parent = scroll
	if o.kind == "Grid" then
		local grid = Instance.new("UIGridLayout")
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.CellPadding = UDim2.fromOffset(gap, gap)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Left
		grid.Parent = scroll
		local minCell = o.minCell or SC.GridMinCellPx
		local aspect = o.aspect or SC.GridAspect
		local function fit()
			local width = scroll.AbsoluteSize.X / MenuFrame.scaleOf(scroll) - 2 * pad - SC.BarPx
			if width <= 0 then
				return
			end
			local columns = math.max(1, math.floor((width + gap) / (minCell + gap)))
			local cell = math.floor((width - (columns - 1) * gap) / columns)
			local height = o.cellHeight or round(cell * aspect)
			grid.CellSize = UDim2.fromOffset(cell, height)
		end
		scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		fit()
		return scroll, grid
	end
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, gap)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = scroll
	return scroll, list
end

-- Lay a tile's parts out from its size (the art on top, the name, the count line).
local function layoutTile(tile: Tile)
	local size = tile.button.AbsoluteSize / MenuFrame.scaleOf(tile.button)
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return
	end
	local pad = math.max(3, round(h * CARD.PadShare))
	local nameH = round(h * CARD.NameShare)
	local countH = if tile.count.Text ~= "" then round(h * CARD.CountShare) else 0
	local art =
		math.max(1, math.min(w - 2 * pad, h - 2 * pad - nameH - countH, round(h * CARD.IconShare)))
	local used = art + nameH + countH
	local y = math.max(pad, round((h - used) / 2))
	tile.art.Size = UDim2.fromOffset(art, art)
	tile.art.Position = UDim2.fromOffset(round(w / 2), y)
	tile.title.Position = UDim2.fromOffset(pad, y + art)
	tile.title.Size = UDim2.fromOffset(math.max(1, w - 2 * pad), nameH)
	tile.count.Visible = countH > 0
	tile.count.Position = UDim2.fromOffset(pad, y + art + nameH)
	tile.count.Size = UDim2.fromOffset(math.max(1, w - 2 * pad), countH)
	local badgeH = math.max(K.Text.Min + 4, round(h * CARD.BadgeShare))
	tile.badge.Position = UDim2.fromOffset(w - round(pad / 2), round(pad / 2))
	tile.badge.Size = UDim2.fromOffset(round(w * 0.9), badgeH)
end

--- A card like reference 03's reward tiles: a white rounded card with a pale edge, a picture
--- (a kit icon, or a CueThumb put in `art`), a name and a count line ("x3"). With `onPress`
--- it is a button: hover and gamepad selection give it the kit's gold outline and a small
--- grow, a press squishes it, and it plays the Click sound. Size it yourself (a grid does).
function MenuFrame.tile(parent: Instance, opts: TileOptions?): Tile
	local o: TileOptions = opts or {}
	local button = Instance.new("TextButton")
	button.Name = o.name or "Tile"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.LayoutOrder = o.order or 0
	button.SelectionImageObject = noBox()
	local pressable = o.onPress ~= nil
	button.Active = pressable
	button.Selectable = pressable
	local body = HudParts.frame(button, "Body")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = body
	local fill = HudParts.frame(body, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	fill.ZIndex = 0
	HudParts.corner(fill, CARD.CornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = color(CARD.EdgeColor)
	edge.Thickness = CARD.StrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, color(K.PanelFade))
	fade.Parent = fill
	local art = HudParts.frame(body, "Art")
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.ZIndex = 3
	local icon = HudParts.icon(art, o.icon or "Trophy", "Icon")
	icon.Size = UDim2.fromScale(1, 1)
	icon.Visible = hasIcon(o.icon)
	icon.ZIndex = 3
	local title = HudParts.text(body, "Title", CARD.NameTextPx, o.title or "")
	title.TextWrapped = false
	title.ZIndex = 4
	local count = HudParts.note(body, "Count", CARD.CountTextPx, o.count or "")
	count.TextWrapped = false
	count.ZIndex = 4
	local badge = HudParts.frame(body, "Badge")
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.ZIndex = 5
	local row = Instance.new("UIListLayout")
	row.FillDirection = Enum.FillDirection.Horizontal
	row.HorizontalAlignment = Enum.HorizontalAlignment.Right
	row.SortOrder = Enum.SortOrder.LayoutOrder
	row.Padding = UDim.new(0, 4)
	row.Parent = badge
	button.Parent = parent
	local tile: Tile = {
		button = button,
		body = body,
		fill = fill,
		art = art,
		icon = icon,
		title = title,
		count = count,
		badge = badge,
		edge = edge,
	}
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutTile(tile)
	end)
	layoutTile(tile)

	-- Hover, gamepad selection and press, like the kit's candy buttons.
	local lit, down = false, false
	local tween: Tween? = nil
	local function settle()
		if tween then
			tween:Cancel()
		end
		local scale = if down then K.PressedScale elseif lit then K.SelectedScale else 1
		local made = TweenService:Create(
			press,
			TweenInfo.new(QUICK, Enum.EasingStyle.Quad),
			{ Scale = scale }
		)
		tween = made
		made:Play()
	end
	local function light(on: boolean)
		lit = on and pressable
		edge.Color = if lit then GOLD else color(CARD.EdgeColor)
		edge.Thickness = if lit then K.SelectedStrokePx else CARD.StrokePx
		settle()
		UIAnim.sway(body, lit, nil, button)
	end
	if pressable then
		button.MouseEnter:Connect(function()
			light(true)
		end)
		button.MouseLeave:Connect(function()
			down = false
			light(false)
		end)
		button.SelectionGained:Connect(function()
			light(true)
		end)
		button.SelectionLost:Connect(function()
			light(false)
		end)
		button.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
				or input.KeyCode == Enum.KeyCode.ButtonA
			then
				down = true
				settle()
			end
		end)
		button.InputEnded:Connect(function()
			down = false
			settle()
		end)
		local onPress = o.onPress :: () -> ()
		button.Activated:Connect(function()
			UISound.play("Click")
			onPress()
		end)
	end
	return tile
end

--- Change a tile's picture, name or count line (nil leaves one as it is; "" clears it).
function MenuFrame.setTile(tile: Tile, fields: { icon: string?, title: string?, count: string? })
	if fields.icon ~= nil then
		tile.icon.Image = ICONS[fields.icon] or ""
		tile.icon.Visible = hasIcon(fields.icon)
	end
	if fields.title ~= nil then
		tile.title.Text = fields.title
	end
	if fields.count ~= nil then
		local had = tile.count.Text ~= ""
		tile.count.Text = fields.count
		if had ~= (fields.count ~= "") then
			layoutTile(tile)
		end
	end
end

--- The words for a request that did not work: Strings.Menus.Reasons[reply.reason], or its
--- Default. Takes the reply table (or a reason string).
function MenuFrame.reason(reply: any): string
	local reasons: { [string]: string } = Strings.Menus.Reasons :: any
	local key = if type(reply) == "table"
		then reply.reason
		elseif type(reply) == "string" then reply
		else nil
	if type(key) == "string" and reasons[key] then
		return reasons[key]
	end
	return reasons.Default
end

--- A short line (a server's answer: "Equip another cue first") at the bottom middle of
--- `parent`, on a pill in `toneName` (a Kit colour: "Ink" by default, "Red" for a refusal,
--- "Green" for good news), for Notice.Seconds. A new one replaces the one showing.
function MenuFrame.showNotice(parent: GuiObject, text: string, toneName: string?)
	local old = parent:FindFirstChild("Notice")
	if old then
		old:Destroy()
	end
	local width = math.min(
		NOTICE.MaxWidthPx,
		parent.AbsoluteSize.X / MenuFrame.scaleOf(parent) - 2 * NOTICE.PadPx,
		math.ceil(textWidth(text, NOTICE.TextPx)) + 2 * NOTICE.PadPx
	)
	local pill = HudParts.pill(parent, "Notice", tone(toneName or "Ink"))
	pill.AnchorPoint = Vector2.new(0.5, 1)
	pill.Position = UDim2.new(0.5, 0, 1, -NOTICE.BottomPx)
	pill.Size = UDim2.fromOffset(math.max(NOTICE.HeightPx * 2, width), NOTICE.HeightPx)
	pill.ZIndex = NOTICE.ZIndex
	local words = HudParts.text(pill, "Words", NOTICE.TextPx, text)
	words.TextWrapped = false
	words.Position = UDim2.fromOffset(NOTICE.PadPx / 2, 0)
	words.Size = UDim2.new(1, -NOTICE.PadPx, 1, 0)
	words.ZIndex = NOTICE.ZIndex + 1
	pill.Visible = false
	UIAnim.popIn(pill)
	task.delay(NOTICE.Seconds, function()
		if pill.Parent then
			UIAnim.popOut(pill, function()
				pill:Destroy()
			end)
		end
	end)
end

local dialogCount = 0

--- The kit's confirm dialog over `parent` (a menu's panel: MenuFrame:confirm does that): the
--- question, No (blue, keeps things as they are) on the left and Yes (red, sells) on the
--- right. No dim (UI_STYLE 2); a clear layer under it still stops presses reaching the menu.
--- A gamepad goes to No; B or Escape answer No. `callback` runs once with the answer.
function MenuFrame.ask(parent: GuiObject, opts: ConfirmOptions, callback: (boolean) -> ()): Dialog
	dialogCount += 1
	local action = "8ballMenuConfirm" .. dialogCount
	local open = true
	local previous = GuiService.SelectedObject
	local layer = catcher(parent, "Confirm")
	layer.ZIndex = CONFIRM.ZIndex
	local card = HudParts.card(layer, "Dialog")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = CONFIRM.ZIndex + 1
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	local heading: TextLabel? = nil
	if opts.title and opts.title ~= "" then
		local made = HudParts.text(card, "Title", CONFIRM.TitleTextPx, opts.title)
		made.ZIndex = 2
		heading = made
	end
	local question = HudParts.note(card, "Question", CONFIRM.TextPx, opts.text)
	question.ZIndex = 2

	local finish: (boolean) -> ()
	local no = HudParts.candy(card, opts.no or Strings.Menus.No, function()
		UISound.play("Click")
		finish(false)
	end, opts.noTone or "Blue")
	no.Name = "No"
	no.ZIndex = 2
	local yes = HudParts.candy(card, opts.yes or Strings.Menus.Yes, function()
		UISound.play("Click")
		finish(true)
	end, opts.yesTone or "Red")
	yes.Name = "Yes"
	yes.ZIndex = 2
	no.NextSelectionRight = yes
	yes.NextSelectionLeft = no

	-- Sized from its words: the question wraps at the card's width.
	local room = parent.AbsoluteSize.X / MenuFrame.scaleOf(parent) - 2 * CONFIRM.MarginPx
	local width = math.max(200, math.min(CONFIRM.WidthPx, room))
	local pad, gap = CONFIRM.PadPx, CONFIRM.GapPx
	local inner = width - 2 * pad
	local y = pad
	if heading then
		heading.Position = UDim2.fromOffset(pad, y)
		heading.Size = UDim2.fromOffset(inner, CONFIRM.TitleTextPx + 8)
		y += CONFIRM.TitleTextPx + 8 + gap / 2
	end
	local textH = TextService:GetTextSize(opts.text, CONFIRM.TextPx, FONT, Vector2.new(inner, 2000)).Y
		+ 4
	question.Position = UDim2.fromOffset(pad, y)
	question.Size = UDim2.fromOffset(inner, textH)
	y += textH + gap
	local half = (inner - gap) / 2
	no.Position = UDim2.fromOffset(pad, y)
	no.Size = UDim2.fromOffset(half, CONFIRM.ButtonPx)
	yes.Position = UDim2.fromOffset(pad + half + gap, y)
	yes.Size = UDim2.fromOffset(half, CONFIRM.ButtonPx)
	card.Size = UDim2.fromOffset(width, y + CONFIRM.ButtonPx + pad)
	card.Visible = false
	UIAnim.popIn(card)

	local escape: RBXScriptConnection? = nil
	finish = function(answer: boolean)
		if not open then
			return
		end
		open = false
		ContextActionService:UnbindAction(action)
		if escape then
			escape:Disconnect()
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(layer) then
			GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
				then previous
				else nil
		end
		layer.Active = false
		UIAnim.popOut(card, function()
			layer:Destroy()
		end)
		callback(answer)
	end
	-- B answers No before the menu (or the table) hears it.
	ContextActionService:BindActionAtPriority(
		action,
		function(_name: string, state: Enum.UserInputState, _input: InputObject)
			if state == Enum.UserInputState.Begin then
				finish(false)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		DIALOG_PRIORITY,
		Enum.KeyCode.ButtonB
	)
	escape = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			Menus.swallowEscape(input) -- the menu under the dialog stays open
			finish(false)
		end
	end)
	if gamepadInUse() then
		GuiService.SelectedObject = no
	end
	return {
		cancel = function()
			finish(false)
		end,
		isOpen = function(): boolean
			return open
		end,
	}
end

return MenuFrame
