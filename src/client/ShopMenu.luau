--!strict
-- ShopMenu: the Shop, emptied for the GUI overhaul (designer, 2026-10-04). It is opened from
-- the left column's Shop tile (or the D-pad's up in the hub, or the money HUD's "+") through
-- Menus and shows the frame (MenuFrame: the title, the money, the red X), its background and
-- the four jump buttons down the right side (Featured, Blocks, Money, Passes;
-- Config.UI.Shop.Page.Jump). The sections, cards and buy flows went with the old page; they
-- come back with the new design. The server-side shop (products, receipts, restock, gifting,
-- VIP) is untouched.
--
-- The jump buttons keep their red NEW badges: a group with something new since the Shop was
-- last open (a new restock, a deal, an offer) shows one, and the pinned groups keep theirs
-- all through the Grand Opening (Config.UI.Shop.Page.PinnedBadges). The Shop tile's red dot
-- reads newCount through deps.shopNew. jump / jumpTo only light the chosen button for now
-- (HubCorners and the money HUD still open the Shop on a tab). Nothing here ever opens the
-- Shop by itself.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local NAME = "Shop"
local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local JUMPS: { { Key: string, Icon: string, Sections: { string } } } = P.Jump :: any
local JUMP_PRIORITY = Enum.ContextActionPriority.High.Value + 20 -- like the menus' LB / RB
local span = ShopParts.span
local round = ShopParts.round

type Jump = { key: string, button: TextButton, badge: Frame }

local ShopMenu = {}
ShopMenu.__index = ShopMenu

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

--- Build the Shop (closed) and register it with Menus. `deps` is Progression's shared table
--- (money, flyer, column, rankHud, lostAt); read when used.
function ShopMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local self: any = setmetatable({}, ShopMenu)
	self.deps = deps
	self.geo = nil :: MenuFrame.Geo?
	self.ticker = nil :: RBXScriptConnection?
	self.nextTick = 0
	self.current = nil :: string? -- the lit jump button
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

	-- The jump buttons (in the panel, so a gamepad reaches them).
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

	frame.onOpen = function()
		self:opened()
	end
	frame.onClose = function()
		self:closed()
	end
	frame.onLayout = function(geo: MenuFrame.Geo)
		self.geo = geo
		self:layout()
	end
	ItemState.Changed.Shop:Connect(function()
		self:refresh()
	end)

	local handle: Menus.Handle = {
		open = function(tab: string?)
			frame:open()
			if tab then
				self:jump(tab)
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

--------------------------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------------------------

function ShopMenu.refresh(self: any)
	if not self.frame:isOpen() then
		return
	end
	local state = ItemState.shop()
	self.placeholder.Visible = false
	if type(state) == "table" then
		self:refreshBadges(state)
	end
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
	local width = self:layoutRail(geo)
	self.scroll.Size = UDim2.fromOffset(width, geo.content.Y)
	ShopParts.setCanvas(self.scroll, 0)
end

--------------------------------------------------------------------------------------------
-- The jump buttons
--------------------------------------------------------------------------------------------

--- Light a jump group's button (the page has nothing to scroll to yet). `_instant` is kept
--- for the callers that pass it.
function ShopMenu.jump(self: any, key: string, _instant: boolean?)
	local found = false
	for _, jump in JUMPS do
		if jump.Key == key then
			found = true
		end
	end
	if not found then
		return
	end
	self.current = key
	for _, jump in self.jumps :: { Jump } do
		HudParts.setTone(jump.button, if jump.key == key then "Blue" else "White")
	end
	if ShopParts.gamepad() then
		for _, jump in self.jumps :: { Jump } do
			if jump.key == key then
				GuiService.SelectedObject = jump.button
			end
		end
	end
end

--- Light one section's group (another section's button: "VIP only" goes to VIP).
function ShopMenu.jumpTo(self: any, section: string)
	for _, jump in JUMPS do
		if jump.Key == section or table.find(jump.Sections, section) then
			self:jump(jump.Key)
			return
		end
	end
end

-- What makes a group "new": the restock slot (Blocks), the open Limited rows and offers
-- (Featured). Seen when the Shop opens.
local function newMarks(state: any): { [string]: string }
	local marks: { [string]: string } = {}
	local restock = if type(state.restock) == "table" then state.restock else {}
	if type(restock.slot) == "number" then
		marks.Blocks = tostring(restock.slot)
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
	for key, deal in (if type(state.deals) == "table" then state.deals else {}) do
		if type(deal) == "table" and deal.timed == true and deal.open == true then
			table.insert(deals, "Deal:" .. tostring(key))
		end
	end
	table.sort(deals)
	if #deals > 0 then
		marks.Featured = table.concat(deals, ",")
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
	local deals = if type(state.deals) == "table" then state.deals else {}
	local opening = type(deals.GrandOpening) == "table" and deals.GrandOpening.open == true
	local pinned: { string } = P.PinnedBadges :: any
	for _, jump in self.jumps :: { Jump } do
		local mark = marks[jump.key]
		local keep = opening and table.find(pinned, jump.key) ~= nil
		jump.badge.Visible = keep or (mark ~= nil and self.seen[jump.key] ~= mark)
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

--- Put a gamepad on the lit jump button when its selection is gone or hidden.
function ShopMenu.ensureSelection(self: any)
	local frame = self.frame
	if not frame:isOpen() or #frame.dialogs > 0 or not ShopParts.gamepad() then
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
	if selected ~= nil and ShopParts.firstSelectable({ selected }) ~= nil then
		return
	end
	local buttons: { GuiObject? } = {}
	for _, jump in self.jumps :: { Jump } do
		table.insert(buttons, jump.button)
	end
	local target = ShopParts.firstSelectable(buttons)
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
	local next = math.clamp(at + dir, 1, #JUMPS)
	self:jump(JUMPS[next].Key)
end

function ShopMenu.opened(self: any)
	self:refresh()
	if self.current == nil then
		self:jump(JUMPS[1].Key)
	end
	self:markSeen()
	if not self.ticker then
		self.ticker = RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if clock >= self.nextTick then
				self.nextTick = clock + Config.UI.Shop.TickSeconds
				self:refresh()
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
	ContextActionService:UnbindAction("8ballShopJump")
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
	self:markSeen()
end

return ShopMenu
