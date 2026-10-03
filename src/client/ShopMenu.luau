--!strict
-- ShopMenu: the Shop, one scrolling page (GUI lane, designer 2026-10-03; ref 01: Steal an
-- Egg's format), opened from the left column's Shop tile (or the D-pad's up in the hub)
-- through Menus. Sections in Config.Shop.Order (ShopPage words them from ShopState; ShopCards
-- draws them): the personal offer, VIP, Limited, the restock, Mystery Cases, money packs,
-- boosts, Roblox Plus, each under a big yellow "— VIP —" header.
--
-- Four big jump buttons down the right side (Deals, Cases, Money, Passes;
-- Config.UI.Shop.Page.Jump): outside the panel on a computer with room for them, a column
-- inside the page on a phone. Each scrolls to its first section; the one whose section is at
-- the top glows blue. A red NEW badge marks a group with something new since the Shop was last
-- open (a new restock, a Limited, an offer). Gamepad: LB / RB jump up and down the groups.
--
-- The server decides everything: this sends ids, counts and product keys only (ItemRequest
-- BuyLimited / BuyMystery / BuyRestock, StoreRequest Buy / RobloxPlus) and draws what ShopState
-- and the money attribute say. A button is faded while its request is on its way; a refusal
-- shows its reason at the bottom. A money buy the money does not cover says "Need $X more";
-- pressing it opens the need-money popup with the smallest covering pack (ShopNeed), or only
-- the notice when the player lost a match in the last Config.UI.Shop.Need.AfterLossSeconds.
-- Nothing here ever opens the Shop by itself.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Format = require(Progression:WaitForChild("Format"))
local Shop = require(Progression:WaitForChild("Shop"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local ShopCards = require(script.Parent.ShopCards)
local ShopNeed = require(script.Parent.ShopNeed)
local ShopOdds = require(script.Parent.ShopOdds)
local ShopPage = require(script.Parent.ShopPage)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "Shop"
local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local CUE_NAMES: { [string]: string } = Strings.Items.Cues :: any
local REASONS: { [string]: string } = Strings.Menus.Reasons :: any
local JUMPS: { { Key: string, Icon: string, Sections: { string } } } = P.Jump :: any
local JUMP_PRIORITY = Enum.ContextActionPriority.High.Value + 20 -- like the menus' LB / RB
local span = ShopParts.span
local round = ShopParts.round

-- The jump group of each section.
local GROUP_OF: { [string]: string } = {}
for _, jump in JUMPS do
	for _, section in jump.Sections do
		GROUP_OF[section] = jump.Key
	end
end

type Header = { root: Frame, title: TextLabel, line: TextLabel, shake: UIAnim.Handle }
type Jump = { key: string, button: TextButton, badge: Frame }

local ShopMenu = {}
ShopMenu.__index = ShopMenu

local function shows(object: GuiObject): boolean
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

--------------------------------------------------------------------------------------------
-- Keys for the requests in flight
--------------------------------------------------------------------------------------------

function ShopMenu.limitedKey(cueId: string): string
	return "Limited:" .. cueId
end

function ShopMenu.productKey(key: string): string
	return "Product:" .. key
end

function ShopMenu.mysteryKey(count: number): string
	return "Mystery:" .. count
end

function ShopMenu.restockKey(id: string): string
	return "Restock:" .. id
end

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

--- Build the Shop (closed) and register it with Menus. `deps` is Progression's shared table
--- (money, flyer, column, caseOpening, rankHud, lostAt); read when used.
function ShopMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local self: any = setmetatable({}, ShopMenu)
	self.deps = deps
	self.busy = {} :: { [string]: boolean }
	self.told = {} :: { [string]: { need: number, money: number } }
	self.dirty = true
	self.queued = false
	self.sizes = ShopParts.sizes(nil)
	self.geo = nil :: MenuFrame.Geo?
	self.ticker = nil :: RBXScriptConnection?
	self.nextTick = 0
	self.lit = nil :: string? -- the money pack lit by the need flow
	self.sections = {} :: { ShopPage.Section }
	self.cards = {} :: { [string]: ShopCards.Card }
	self.headers = {} :: { [string]: Header }
	self.tops = {} :: { [string]: number } -- each shown section's top in the canvas
	self.current = nil :: string? -- the jump group at the top now
	self.scrollTween = nil :: Tween?
	self.seen = {} :: { [string]: any } -- what the badges count as seen (by group)

	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Shop,
		icon = if K.Icons.ShopBasket ~= "" then "ShopBasket" else "Shop",
		money = true,
	})
	self.frame = frame
	local page = frame:page()
	self.placeholder = MenuFrame.placeholder(page)
	local scroll = ShopParts.scroller(page, "Page")
	self.scroll = scroll
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		self:updateCurrent()
	end)

	-- The jump buttons (in the panel, so a gamepad reaches them from the cards).
	local rail = HudParts.frame(frame.panel, "Jumps")
	rail.ZIndex = 4
	self.rail = rail
	self.jumps = {} :: { Jump }
	local words: { [string]: string } = COPY.Jump
	for _, jump in JUMPS do
		local key = jump.Key
		local icon = if K.Icons[jump.Icon] and K.Icons[jump.Icon] ~= "" then jump.Icon else "Shop"
		local button = HudParts.tile(rail, words[key] or key, function()
			UISound.play("Click")
			self:jump(key)
		end, "White", icon)
		button.Name = "Jump" .. key
		local badge = HudParts.pill(button, "New", HudParts.tone("Red"))
		badge.AnchorPoint = Vector2.new(0.5, 0.5)
		badge.ZIndex = 8
		badge.Visible = false
		local badgeText = HudParts.text(badge, "Words", K.Text.Min, COPY.New)
		badgeText.TextWrapped = false
		badgeText.Size = UDim2.fromScale(1, 1)
		badgeText.ZIndex = 9
		table.insert(self.jumps, { key = key, button = button, badge = badge })
	end

	self.odds = ShopOdds.new(self, frame)
	self.need = ShopNeed.new(self, frame)

	frame.onOpen = function()
		self:opened()
	end
	frame.onClose = function()
		self:closed()
	end
	frame.onLayout = function(geo: MenuFrame.Geo)
		self.geo = geo
		self.sizes = ShopParts.sizes(geo)
		self:layout()
	end
	self:listen()

	local handle: Menus.Handle = {
		open = function(tab: string?)
			frame:open()
			if tab then
				task.defer(function()
					self:jump(tab, true)
				end)
			end
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
		ensureSelection = function()
			self:ensureSelection()
		end,
		notice = function(text: string, toneName: string?)
			if frame:isOpen() then
				frame:notice(text, toneName)
			end
		end,
	}
	Menus.register(NAME, handle)
	deps.shopNew = function(): number
		return self:newCount()
	end
	return handle
end

function ShopMenu.listen(self: any)
	local function changed()
		self:refresh()
	end
	ItemState.Changed.Shop:Connect(changed)
	ItemState.Changed.Items:Connect(changed)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Money"):Connect(changed)
		player:GetPropertyChangedSignal("MembershipType"):Connect(changed)
	end
	workspace:GetAttributeChangedSignal("MoneyPartyEndsAt"):Connect(changed)
	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("LimitedSold", 60)
		if folder then
			folder.AttributeChanged:Connect(changed)
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------

function ShopMenu.refresh(self: any)
	if not self.frame:isOpen() then
		self.dirty = true
		return
	end
	if self.queued then
		return
	end
	self.queued = true
	task.defer(function()
		self.queued = false
		self:redraw()
	end)
end

function ShopMenu.header(self: any, key: string): Header
	local header = self.headers[key]
	if header then
		return header
	end
	local root = HudParts.frame(self.scroll, "Header" .. key)
	root.ZIndex = 2
	local words: { [string]: string } = COPY.Sections
	local title = HudParts.text(
		root,
		"Title",
		P.HeaderTextPx[1],
		COPY.Header:format(words[key] or key),
		HudParts.color(P.HeaderColor)
	)
	title.TextWrapped = false
	title.ZIndex = 3
	local line =
		HudParts.text(root, "Line", P.HeaderLineTextPx[1], "", HudParts.color(K.Numbers.Count))
	line.AutoLocalize = false
	line.TextWrapped = false
	line.ZIndex = 3
	header = { root = root, title = title, line = line, shake = UIAnim.shake(title, "Text") }
	self.headers[key] = header
	return header
end

function ShopMenu.redraw(self: any)
	self.dirty = false
	local state = ItemState.shop()
	local ready = type(state) == "table"
	self.placeholder.Visible = not ready
	self.scroll.Visible = ready
	self.rail.Visible = ready
	if not ready then
		return
	end
	local now = ShopParts.now()
	local sections = ShopPage.build(self, state, now)
	self.sections = sections
	local used: { [string]: boolean } = {}
	local shownHeaders: { [string]: boolean } = {}
	for _, section in sections do
		shownHeaders[section.key] = true
		local header = self:header(section.key)
		header.root.Visible = true
		for _, spec in section.cards do
			used[spec.id] = true
			local card = self.cards[spec.id]
			if card == nil or card.shape ~= spec.shape then
				if card then
					ShopCards.destroy(card)
				end
				card = ShopCards.new(self.scroll, spec.id, spec.shape)
				self.cards[spec.id] = card
			end
			ShopCards.paint(card, spec)
			card.root.Visible = true
		end
	end
	for id, card in self.cards :: { [string]: ShopCards.Card } do
		if not used[id] then
			card.root.Visible = false
		end
	end
	for key, header in self.headers :: { [string]: Header } do
		if not shownHeaders[key] then
			header.root.Visible = false
		end
	end
	self:tick()
	self:refreshBadges(state)
	self:layout()
	self:ensureSelection()
end

-- Where the jump buttons go: outside the panel's right edge when the screen has room for
-- them, else a column at the right of the page. Returns the page width they leave.
function ShopMenu.layoutRail(self: any, geo: MenuFrame.Geo): number
	local t = geo.t
	local frame = self.frame
	local panel: Frame = frame.panel
	local railW = span(P.RailWidthPx, t)
	local buttonH = span(P.RailButtonPx, t)
	local gap = span(P.RailGapPx, t)
	local textSize = math.max(K.Text.Min, span(P.RailTextPx, t))
	local n = #self.jumps
	local railH = n * buttonH + (n - 1) * gap
	-- Offsets, not absolute sizes: the panel may be mid pop-in (scaled) when this runs.
	local screenW = frame.root.AbsoluteSize.X
	local panelW = panel.Size.X.Offset
	local panelH = panel.Size.Y.Offset
	local room = (screenW - panelW) / 2
	local outside = not geo.short and room >= railW + 2 * P.RailOutsidePx
	local content: Frame = frame.content
	local contentTop = content.Position.Y.Offset
	local width = geo.content.X
	if outside then
		self.rail.Position =
			UDim2.fromOffset(panelW + P.RailOutsidePx, math.max(0, round((panelH - railH) / 2)))
	else
		local contentLeft = content.Position.X.Offset
		width = math.max(1, geo.content.X - railW - gap)
		self.rail.Position = UDim2.fromOffset(
			contentLeft + width + gap,
			contentTop + math.max(0, round((geo.content.Y - railH) / 2))
		)
	end
	self.rail.Size = UDim2.fromOffset(railW, railH)
	for index, jump in self.jumps :: { Jump } do
		jump.button.Position = UDim2.fromOffset(0, (index - 1) * (buttonH + gap))
		jump.button.Size = UDim2.fromOffset(railW, buttonH)
		HudParts.setButtonTextSize(jump.button, textSize)
		local badgeH = math.max(18, round(buttonH * 0.3))
		jump.badge.Size = UDim2.fromOffset(round(badgeH * 1.9), badgeH)
		jump.badge.Position = UDim2.fromOffset(railW - 6, 6)
	end
	return width
end

function ShopMenu.layout(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not self.frame:isOpen() or geo == nil then
		return
	end
	local s = self.sizes
	local t = s.t
	local width = self:layoutRail(geo)
	self.scroll.Size = UDim2.fromOffset(width, geo.content.Y)
	local inner = ShopParts.inner(Vector2.new(width, geo.content.Y), s)
	local x0, w = s.scrollPad, inner.X
	local y = s.scrollPad
	local headerH = span(P.HeaderPx, t)
	local headerText = math.max(K.Text.Min, span(P.HeaderTextPx, t))
	local lineText = math.max(K.Text.Min, span(P.HeaderLineTextPx, t))
	local sectionGap = span(P.SectionGapPx, t)
	table.clear(self.tops)
	for index, section in self.sections :: { ShopPage.Section } do
		if index > 1 then
			y += sectionGap
		end
		self.tops[section.key] = y
		local header: Header = self.headers[section.key]
		local hasLine = section.line ~= nil or section.lineEnds ~= nil
		local h = headerH + (if hasLine then lineText + 6 else 0)
		header.root.Position = UDim2.fromOffset(x0, y)
		header.root.Size = UDim2.fromOffset(w, h)
		HudParts.setTextSize(header.title, headerText)
		header.title.Position = UDim2.fromOffset(0, 0)
		header.title.Size = UDim2.fromOffset(w, headerH)
		header.line.Visible = hasLine
		HudParts.setTextSize(header.line, lineText)
		header.line.Position = UDim2.fromOffset(0, headerH)
		header.line.Size = UDim2.fromOffset(w, lineText + 6)
		y += h + round(s.gap / 2)
		-- Room for the tilted stickers that poke above a card's top edge.
		for _, spec in section.cards do
			if spec.sticker then
				y += round(span(P.StickerPx, t) / 2)
				break
			end
		end
		if section.grid then
			y = self:layoutGrid(section, x0, y, w)
		else
			for _, spec in section.cards do
				local card: ShopCards.Card = self.cards[spec.id]
				local cardH = if spec.shape == "Note"
					then ShopCards.layoutNote(card, s, x0, y, w)
					else ShopCards.layoutHero(card, s, x0, y, w)
				y += cardH + s.gap
			end
			y -= s.gap
		end
	end
	ShopParts.setCanvas(self.scroll, y + s.scrollPad + round(geo.content.Y * 0.25))
	self.odds:layout(s)
	self.need:layout(s, geo)
	self:updateCurrent()
end

-- Tiles in rows: as many columns as keep each at least TileMinWidth wide; every tile in a row
-- as tall as the tallest. Returns the y under the grid.
function ShopMenu.layoutGrid(
	self: any,
	section: ShopPage.Section,
	x0: number,
	y: number,
	w: number
): number
	local s = self.sizes
	local gap = s.gap
	local minW = span(P.TileMinWidthPx, s.t)
	local n = #section.cards
	local cols = math.max(1, math.min(n, math.floor((w + gap) / (minW + gap))))
	local tileW = math.min(P.TileMaxWidthPx, math.floor((w - (cols - 1) * gap) / cols))
	local index = 1
	while index <= n do
		local inRow = math.min(cols, n - index + 1)
		local rowH = 0
		for i = index, index + inRow - 1 do
			local card: ShopCards.Card = self.cards[section.cards[i].id]
			rowH = math.max(rowH, ShopCards.tileNeed(card, s, tileW))
		end
		local rowW = inRow * tileW + (inRow - 1) * gap
		local x = x0 + math.floor((w - rowW) / 2)
		for i = index, index + inRow - 1 do
			local card: ShopCards.Card = self.cards[section.cards[i].id]
			ShopCards.layoutTile(card, s, x, y, tileW, rowH)
			x += tileW + gap
		end
		y += rowH + gap
		index += inRow
	end
	return y - gap
end

-- The countdowns, a few times a second while open; a window that ran out redraws.
function ShopMenu.tick(self: any)
	local now = ShopParts.now()
	local crossed = false
	for _, section in self.sections :: { ShopPage.Section } do
		local header: Header? = self.headers[section.key]
		if header then
			if section.lineEnds and section.lineWords then
				local left = ShopParts.timeLeft(section.lineEnds - now)
				local text = section.lineWords:format(left)
				header.line.Text = if section.line then section.line .. "  ·  " .. text else text
				crossed = crossed or now >= section.lineEnds
			else
				header.line.Text = section.line or ""
			end
		end
		for _, spec in section.cards do
			local card: ShopCards.Card? = self.cards[spec.id]
			if card and ShopCards.tick(card, now) then
				crossed = true
			end
		end
	end
	if crossed then
		self:refresh()
	end
end

--------------------------------------------------------------------------------------------
-- Jumps and badges
--------------------------------------------------------------------------------------------

-- The first shown section of a jump group (or a section key itself).
function ShopMenu.targetOf(self: any, key: string): string?
	if self.tops[key] then
		return key
	end
	for _, jump in JUMPS do
		if jump.Key == key then
			for _, section in jump.Sections do
				if self.tops[section] then
					return section
				end
			end
		end
	end
	return nil
end

--- Scroll to a jump group's (or a section's) first section. `instant` skips the glide.
function ShopMenu.jump(self: any, key: string, instant: boolean?)
	local section = self:targetOf(key)
	if section == nil then
		return
	end
	local scroll: ScrollingFrame = self.scroll
	local maxY = math.max(0, scroll.AbsoluteCanvasSize.Y - scroll.AbsoluteWindowSize.Y)
	local target = Vector2.new(0, math.clamp(self.tops[section] - self.sizes.scrollPad, 0, maxY))
	if self.scrollTween then
		self.scrollTween:Cancel()
	end
	if instant then
		scroll.CanvasPosition = target
	else
		local tween = TweenService:Create(
			scroll,
			TweenInfo.new(P.JumpSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CanvasPosition = target }
		)
		self.scrollTween = tween
		tween:Play()
	end
	-- A gamepad lands on that section's first button.
	if ShopParts.gamepad() then
		local first = self:firstIn(section)
		if first then
			GuiService.SelectedObject = first
		end
	end
end

--- Scroll to one section (another section's button: "VIP only" goes to VIP).
function ShopMenu.jumpTo(self: any, section: string)
	self:jump(section)
end

-- The jump group at the top of the view now: its button glows blue.
function ShopMenu.updateCurrent(self: any)
	local y = self.scroll.CanvasPosition.Y + span(P.HeaderPx, self.sizes.t)
	local current: string? = nil
	local best = -math.huge
	for key, top in self.tops :: { [string]: number } do
		if top <= y + 1 and top > best then
			best = top
			current = GROUP_OF[key]
		end
	end
	if current == nil then
		current = JUMPS[1].Key
	end
	if current == self.current then
		return
	end
	self.current = current
	for _, jump in self.jumps :: { Jump } do
		HudParts.setTone(jump.button, if jump.key == current then "Blue" else "White")
	end
end

-- What makes a group "new": the restock slot (Cases), the open Limited rows and offers
-- (Deals). Seen when the Shop opens.
local function newMarks(state: any): { [string]: string }
	local marks: { [string]: string } = {}
	local restock = if type(state.restock) == "table" then state.restock else {}
	if type(restock.slot) == "number" then
		marks.Cases = tostring(restock.slot)
	end
	local deals = {}
	for _, row in (if type(state.limited) == "table" then state.limited else {}) do
		if type(row) == "table" and row.open == true and row.owned ~= true then
			table.insert(deals, row.cue)
		end
	end
	for key, offer in (if type(state.offers) == "table" then state.offers else {}) do
		if type(offer) == "table" and offer.open == true then
			table.insert(deals, key)
		end
	end
	local sale = if type(state.releaseSale) == "table" then state.releaseSale else {}
	if sale.open == true then
		table.insert(deals, "Sale")
	end
	table.sort(deals)
	if #deals > 0 then
		marks.Deals = table.concat(deals, ",")
	end
	return marks
end

--- How many jump groups hold something new since the Shop was last open (the Shop tile's red
--- dot reads it).
function ShopMenu.newCount(self: any): number
	local state = ItemState.shop()
	if type(state) ~= "table" then
		return 0
	end
	local count = 0
	for group, mark in newMarks(state) do
		if self.seen[group] ~= mark then
			count += 1
		end
	end
	return count
end

function ShopMenu.refreshBadges(self: any, state: any)
	local marks = newMarks(state)
	for _, jump in self.jumps :: { Jump } do
		local mark = marks[jump.key]
		jump.badge.Visible = mark ~= nil and self.seen[jump.key] ~= mark
	end
end

-- Opening the Shop sees everything (the badges stay up while it is open, then clear).
function ShopMenu.markSeen(self: any)
	local state = ItemState.shop()
	if type(state) == "table" then
		for group, mark in newMarks(state) do
			self.seen[group] = mark
		end
	end
	local column = self.deps and self.deps.column
	if column and column.refreshDots then
		column:refreshDots()
	end
end

--------------------------------------------------------------------------------------------
-- Gamepad
--------------------------------------------------------------------------------------------

function ShopMenu.firstIn(self: any, sectionKey: string): GuiObject?
	for _, section in self.sections :: { ShopPage.Section } do
		if section.key == sectionKey then
			for _, spec in section.cards do
				local card: ShopCards.Card? = self.cards[spec.id]
				if card then
					local first = ShopParts.firstSelectable(ShopCards.selectables(card))
					if first then
						return first
					end
				end
			end
		end
	end
	return nil
end

function ShopMenu.first(self: any): GuiObject?
	for _, section in self.sections :: { ShopPage.Section } do
		local first = self:firstIn(section.key)
		if first then
			return first
		end
	end
	return nil
end

--- Put a gamepad on the page's first button when its selection is gone or hidden.
function ShopMenu.ensureSelection(self: any)
	local frame = self.frame
	if not frame:isOpen() or #frame.dialogs > 0 or not ShopParts.gamepad() then
		return
	end
	if self.need:isOpen() then
		return
	end
	local opener = self.deps and self.deps.caseOpening
	if opener and opener:isOpen() then
		return
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil then
		if selected.Parent == nil then
			selected = nil
		elseif not selected:IsDescendantOf(frame.root) then
			return
		end
	end
	if selected ~= nil then
		if ShopParts.firstSelectable({ selected }) ~= nil then
			return
		end
		if shows(selected) and next(self.busy) ~= nil then
			return
		end
	end
	local target = self:first()
	if target then
		GuiService.SelectedObject = target
	else
		frame:focus()
	end
end

-- LB / RB: the previous / next jump group.
function ShopMenu.step(self: any, dir: number)
	local at = 1
	for index, jump in JUMPS do
		if jump.Key == self.current then
			at = index
		end
	end
	for i = at + dir, (if dir > 0 then #JUMPS else 1), dir do
		if self:targetOf(JUMPS[i].Key) then
			self:jump(JUMPS[i].Key)
			return
		end
	end
end

function ShopMenu.opened(self: any)
	self:redraw()
	self.scroll.CanvasPosition = Vector2.zero
	self:markSeen()
	if not self.ticker then
		self.ticker = RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if clock >= self.nextTick then
				self.nextTick = clock + Config.UI.Shop.TickSeconds
				self:tick()
			end
		end)
	end
	ContextActionService:BindActionAtPriority(
		"8ballShopJump",
		function(_name: string, state: Enum.UserInputState, input: InputObject)
			if state == Enum.UserInputState.Begin and #self.frame.dialogs == 0 then
				self:step(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		JUMP_PRIORITY,
		Enum.KeyCode.ButtonL1,
		Enum.KeyCode.ButtonR1
	)
end

function ShopMenu.closed(self: any)
	self.odds:close()
	self.need:close()
	self.lit = nil
	ContextActionService:UnbindAction("8ballShopJump")
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
	self:markSeen()
end

--------------------------------------------------------------------------------------------
-- Prices and what is missing
--------------------------------------------------------------------------------------------

--- How much money is missing for a price (0 or less: none): the server's `need` from its last
--- refusal of this button while the money has not changed since, else the money attribute's.
function ShopMenu.needFor(self: any, key: string, price: number): number
	local money = ShopParts.money()
	local told = self.told[key]
	if told and told.money == money then
		return told.need
	end
	self.told[key] = nil
	return price - money
end

function ShopMenu.isBusy(self: any, key: string): boolean
	return self.busy[key] == true
end

-- Whether the player lost a match too recently for the need-money popup.
function ShopMenu.lostRecently(self: any): boolean
	local lostAt = self.deps and self.deps.lostAt
	return type(lostAt) == "number" and os.clock() - lostAt < Config.UI.Shop.Need.AfterLossSeconds
end

--- A money buy the money does not cover was pressed: the need-money popup with the smallest
--- pack that covers `gap` (the pack lit on the page too), or only the notice right after a
--- loss.
function ShopMenu.needMoney(self: any, _key: string, gap: number)
	local state = ItemState.shop()
	local first = type(state) == "table" and state.firstPackBought == true
	local pack = Shop.packForGap(gap, first)
	if self:lostRecently() or pack == nil then
		self.frame:notice(ShopParts.need(gap), "Red")
		return
	end
	self.lit = pack
	self:refresh()
	self.need:open(gap, pack)
end

--------------------------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------------------------

function ShopMenu.send(
	self: any,
	key: string,
	ask: () -> ItemState.Reply,
	done: (ItemState.Reply) -> ()
)
	if self.busy[key] then
		return
	end
	self.busy[key] = true
	self:refresh()
	task.spawn(function()
		local reply = ask()
		self.busy[key] = nil
		done(reply)
		self:refresh()
	end)
end

function ShopMenu.refused(self: any, key: string, reply: ItemState.Reply)
	if reply.reason == "NotEnoughMoney" and type(reply.need) == "number" then
		self.told[key] = { need = reply.need, money = ShopParts.money() }
		self:needMoney(key, reply.need)
	else
		self.frame:notice(MenuFrame.reason(reply), "Red")
	end
end

--- Buy a Limited cue: a money row through ItemRequest "BuyLimited", a Robux row through its
--- product.
function ShopMenu.buyLimited(self: any, cueId: string)
	local state = ItemState.shop()
	local rows = if type(state) == "table" and type(state.limited) == "table"
		then state.limited
		else {}
	local row: any = nil
	for _, entry in rows do
		if type(entry) == "table" and entry.cue == cueId then
			row = entry
			break
		end
	end
	if row == nil then
		return
	end
	if type(row.product) == "string" then
		self:buyProduct(row.product, ShopMenu.limitedKey(cueId))
		return
	end
	local key = ShopMenu.limitedKey(cueId)
	self:send(key, function()
		return ItemState.request("ItemRequest", "BuyLimited", cueId)
	end, function(reply)
		if reply.ok then
			self.told[key] = nil
			UISound.play("Claim")
			local copy = if type(reply.copy) == "number" then Format.commas(reply.copy) else "?"
			self.frame:notice(COPY.LimitedBought:format(CUE_NAMES[cueId] or cueId, copy), "Green")
		else
			self:refused(key, reply)
		end
	end)
end

--- Buy `count` Mystery Cases with money; their reveals come on the CaseDrop remote.
function ShopMenu.buyMystery(self: any, count: number)
	local key = ShopMenu.mysteryKey(count)
	self:send(key, function()
		return ItemState.request("ItemRequest", "BuyMystery", count)
	end, function(reply)
		if reply.ok then
			self.told[key] = nil
			UISound.play("Claim")
		else
			self:refused(key, reply)
		end
	end)
end

--- Buy an item of the restock shown now with money; its case lands on its timer.
function ShopMenu.buyRestock(self: any, id: string)
	local key = ShopMenu.restockKey(id)
	self:send(key, function()
		return ItemState.request("ItemRequest", "BuyRestock", id)
	end, function(reply)
		if reply.ok then
			self.told[key] = nil
			UISound.play("Claim")
			local state = ItemState.shop()
			local restock = if type(state) == "table" and type(state.restock) == "table"
				then state.restock
				else {}
			for _, item in (if type(restock.items) == "table" then restock.items else {}) do
				if type(item) == "table" and item.id == id and type(item.case) == "string" then
					local name = CASE_NAMES[item.case] or item.case
					self.frame:notice(COPY.BoughtOne:format(name), "Green")
				end
			end
		else
			self:refused(key, reply)
		end
	end)
end

--- Buy a Robux product or pass (a Config.Products key): the server checks it and shows
--- Roblox's purchase dialog. `busyKey` fades another button instead (a Limited's).
function ShopMenu.buyProduct(self: any, key: string, busyKey: string?)
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local product = products[key]
	if type(product) ~= "table" or product.available ~= true then
		self.frame:notice(REASONS.ComingSoon, "Ink")
		return
	end
	local flight = busyKey or ShopMenu.productKey(key)
	self:send(flight, function()
		return ItemState.request("StoreRequest", "Buy", key)
	end, function(reply)
		if not reply.ok then
			self:refused(flight, reply)
		end
	end)
end

--- The Roblox Plus subscription prompt (the server shows it).
function ShopMenu.robloxPlus(self: any)
	self:send("RobloxPlus", function()
		return ItemState.request("StoreRequest", "RobloxPlus")
	end, function(reply)
		if not reply.ok then
			self.frame:notice(MenuFrame.reason(reply), "Red")
		end
	end)
end

--- Open the odds panel of a case.
function ShopMenu.openOdds(self: any, caseId: string)
	self.odds:open(caseId)
end

return ShopMenu
