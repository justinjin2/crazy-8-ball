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
--
-- The Featured page is the Grand Opening card (GrandOpeningCard): its buttons buy through the
-- server (ItemRequest "BuyBlocks" for money, StoreRequest "Buy" for Robux, which shows Roblox's
-- own dialog); a refusal shows the server's reason as a notice. The purple gift square beside a
-- Robux button opens the Gift Player popup (ShopGift; StoreRequest "Gift").
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local GrandOpeningCard = require(script.Parent.GrandOpeningCard)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local ShopGift = require(script.Parent.ShopGift)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
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
	self.rock = nil :: UIAnim.Handle? -- the lit jump button's icon rocking (the lively frame)
	self.busy = {} :: { [string]: boolean } -- buy requests in flight, by button

	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Shop,
		icon = if K.Icons.ShopBasket ~= "" then "ShopBasket" else "Shop",
		money = true,
		-- The money pill's "+" goes to the money packs, as the money HUD's does (designer,
		-- 2026-10-06; the Money group's page comes with its section).
		moneyPlus = function()
			self:jump("Money")
		end,
	})
	self.frame = frame
	local page = frame:page()
	self.placeholder = MenuFrame.placeholder(page)
	local scroll = ShopParts.scroller(page, "Page")
	self.scroll = scroll
	self.featured = GrandOpeningCard.new(scroll, {
		robux = function(key: string)
			self:buyProduct(key)
		end,
		money = function(count: number)
			self:buyBlocks("GrandOpening", count)
		end,
		gift = function(key: string)
			if self:productReady(key) then
				self.gift:open(key)
			end
		end,
	})
	self.gift = ShopGift.new(self, frame)
	-- The white sheet below the card, where the other groups' sections will go: the next
	-- section's header first (it peeks in at the bottom of the first screen).
	self.blocksHead = GrandOpeningCard.header(scroll, COPY.BlocksHeader)
	local more = HudParts.note(scroll, "MoreBelow", P.MoreBelowTextPx, COPY.MoreBelow)
	more.AnchorPoint = Vector2.new(0.5, 0.5)
	more.ZIndex = 3
	self.more = more

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
	-- The lively frame's open: the jump buttons pop in top to bottom, each NEW badge just after
	-- its button (Config.UI.Shop.Open "Tab1".. and "Tab1Badge"..).
	local stage = frame.stage
	if stage then
		for index, jump in self.jumps :: { Jump } do
			stage:add("Tab" .. index, jump.button)
			stage:add("Tab" .. index .. "Badge", jump.badge)
		end
		self.featured:register(stage, function(handle)
			frame:idle(handle)
		end)
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
	-- The panel is as tall as the Grand Opening card (designer, 2026-10-06); the page scrolls
	-- on below it.
	frame.fitHeight = function(width: number, panelW: number): number
		local pageW = width - (if self:railOutside(panelW) then 0 else self:railRoom(nil))
		return GrandOpeningCard.heightFor(pageW - self.scroll.ScrollBarThickness) + P.PeekPx
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
	self.featured:refresh(state)
end

-- Whether the jump buttons fit outside a panel `panelW` wide (else a column in the page).
function ShopMenu.railOutside(self: any, panelW: number): boolean
	local geo: MenuFrame.Geo? = self.geo
	local t = if geo then geo.t else 0
	local room = (self.frame.root.AbsoluteSize.X - panelW) / 2
	return room >= span(P.RailWidthPx, t) + 2 * P.RailOutsidePx
end

-- The page width a column of jump buttons inside the page takes.
function ShopMenu.railRoom(self: any, geo: MenuFrame.Geo?): number
	local t = if geo then geo.t elseif self.geo then self.geo.t else 0
	return span(P.RailWidthPx, t) + span(P.RailGapPx, t)
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
	local panelW = panel.Size.X.Offset
	local panelH = panel.Size.Y.Offset
	local outside = not geo.short and self:railOutside(panelW)
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
	-- The card fits the page whole (designer, 2026-10-06: no scrolling on a phone).
	local height = self.featured:layout(width - self.scroll.ScrollBarThickness)
	-- Below the card the white sheet goes on (the other groups' sections will be there).
	local k = self.featured.k
	local headH = GrandOpeningCard.headerHeight(k)
	GrandOpeningCard.layoutHeader(self.blocksHead, round(width / 2), round(height + headH / 2), k)
	height += headH
	local more = math.max(P.MoreBelowPx, geo.content.Y - height)
	self.more.Position = UDim2.fromOffset(round(width / 2), round(height + more / 2))
	self.more.Size = UDim2.fromOffset(math.max(1, width - 16), math.max(1, more))
	ShopParts.setCanvas(self.scroll, height + more)
	self.gift:layout(geo)
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
	local changed = self.current ~= key
	self.current = key
	for _, jump in self.jumps :: { Jump } do
		HudParts.setTone(jump.button, if jump.key == key then "Blue" else "White")
	end
	self:rockLit()
	-- A tab switch staggers the page's pieces in again (not during the open: it shows them).
	local stage = self.frame.stage
	if changed and stage and self.frame:isOpen() and stage:busy() ~= "play" then
		local ids = stage:idsUnder(self.scroll)
		if #ids > 0 then
			stage:replay(ids)
		end
	end
	if ShopParts.gamepad() then
		for _, jump in self.jumps :: { Jump } do
			if jump.key == key then
				GuiService.SelectedObject = jump.button
			end
		end
	end
end

-- The lit jump button's icon rocks gently while the Shop is open (the lively frame).
function ShopMenu.rockLit(self: any)
	if self.rock then
		self.rock.stop()
		self.rock = nil
	end
	if not self.frame.stage or not self.frame:isOpen() then
		return
	end
	local L = Config.UI.Menu.Lively
	for _, jump in self.jumps :: { Jump } do
		local body = jump.button:FindFirstChild("Body")
		local icon = body and body:FindFirstChild("Icon")
		if jump.key == self.current and icon and icon:IsA("GuiObject") then
			self.rock = UIAnim.turn(icon, 0, L.TabRockDegrees, L.RockSeconds)
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
-- Buying
--------------------------------------------------------------------------------------------

-- Ask the server once at a time per button; `done` gets the reply.
function ShopMenu.send(self: any, key: string, ask: () -> any, done: (any) -> ())
	if self.busy[key] then
		return
	end
	self.busy[key] = true
	task.spawn(function()
		local reply = ask()
		self.busy[key] = nil
		done(reply)
	end)
end

--- Buy `count` lucky blocks of deal `dealId` (Config.Shop.Deals) with money; they land in the
--- hotbar.
function ShopMenu.buyBlocks(self: any, dealId: string, count: number)
	self:send("Blocks" .. dealId .. count, function()
		return ItemState.request("ItemRequest", "BuyBlocks", dealId, count)
	end, function(reply)
		if reply.ok then
			UISound.play("Claim")
			self.frame:notice(GrandOpeningCard.boughtText(count), "Green")
		elseif reply.reason == "NotEnoughMoney" and type(reply.need) == "number" then
			self.frame:notice(ShopParts.need(reply.need), "Red")
		else
			self.frame:notice(MenuFrame.reason(reply), "Red")
		end
	end)
end

--- Whether Robux product `key` is on sale (made on Roblox); if not, says "Coming soon".
function ShopMenu.productReady(self: any, key: string): boolean
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local product = products[key]
	if type(product) ~= "table" or product.available ~= true then
		self.frame:notice(COPY.ComingSoon, "Ink")
		return false
	end
	return true
end

--- Whether a buy request with this busy key is in flight ("Gift" for gifts).
function ShopMenu.isBusy(self: any, key: string): boolean
	return self.busy[key] == true
end

--- Gift a Robux product (a Config.Products key) to the player `userId` here: the server
--- checks both players and shows Roblox's purchase dialog; the receipt grants it to them.
function ShopMenu.sendGift(self: any, key: string, userId: number, _name: string)
	self:send("Gift", function()
		return ItemState.request("StoreRequest", "Gift", key, userId)
	end, function(reply)
		if not reply.ok then
			self.frame:notice(MenuFrame.reason(reply), "Red")
		end
	end)
end

--- Buy a Robux product (a Config.Products key): the server checks it and shows Roblox's
--- purchase dialog; a product not made yet says "Coming soon".
function ShopMenu.buyProduct(self: any, key: string)
	if not self:productReady(key) then
		return
	end
	self:send("Product" .. key, function()
		return ItemState.request("StoreRequest", "Buy", key)
	end, function(reply)
		if not reply.ok then
			self.frame:notice(MenuFrame.reason(reply), "Red")
		end
	end)
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
	else
		self:rockLit()
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
	self.featured:closed()
	self.gift:close()
	if self.rock then
		self.rock.stop()
		self.rock = nil
	end
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
	self:markSeen()
end

return ShopMenu
