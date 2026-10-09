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
-- reads newCount through deps.shopNew. The jump buttons themselves are JumpRail's (shared
-- with the Free Reward menu). Nothing here ever opens the Shop by itself.
--
-- One page scrolls under the jump buttons: "- FEATURED -" and the Grand Opening card
-- (GrandOpeningCard), then "- BLOCKS -" with the Mystery Lucky Block (ShopMystery), the restock
-- (ShopRestock) and, while they are on, the Starter Pack and VIP (ShopOffers): the designer's
-- picks on the mock page, 2026-10-08; then "- MONEY -" with the money packs (ShopMoney, pick
-- B) and "- PASSES -" with VIP, the ability slots, Money Party and Roblox Plus (ShopPasses, pick
-- B). A jump button scrolls to its group's top and staggers that group's pieces in again
-- (Config.UI.Shop.Page.JumpSeconds); scrolling lights the group in view. Opened on a section
-- (the HUD's offer chips: "Offer", "Vip"), the Shop jumps to the group holding it, and to the
-- section itself when it has its own place on the page. The buttons buy
-- through the server (ItemRequest "BuyBlocks" or "BuyRestock" for money, StoreRequest "Buy" for
-- Robux, which shows Roblox's own dialog; "RobloxPlus" for Roblox's subscription prompt); a
-- refusal shows the server's reason as a notice. The purple gift square beside a Robux button
-- opens the Gift Player popup (ShopGift; StoreRequest "Gift").
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local GrandOpeningCard = require(script.Parent.GrandOpeningCard)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local JumpRail = require(script.Parent.JumpRail)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local OddsDetails = require(script.Parent.OddsDetails)
local ShopGift = require(script.Parent.ShopGift)
local ShopMoney = require(script.Parent.ShopMoney)
local ShopMystery = require(script.Parent.ShopMystery)
local ShopMysteryOdds = require(script.Parent.ShopMysteryOdds)
local ShopOffers = require(script.Parent.ShopOffers)
local ShopParts = require(script.Parent.ShopParts)
local ShopPasses = require(script.Parent.ShopPasses)
local ShopRestock = require(script.Parent.ShopRestock)
local UISound = require(script.Parent.UISound)

local NAME = "Shop"
local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local SB = Config.UI.ShopBlocks
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local JUMPS: { { Key: string, Icon: string, Sections: { string } } } = P.Jump :: any
local round = ShopParts.round

local ShopMenu = {}
ShopMenu.__index = ShopMenu

-- The jump group showing `section`: a group's own key, or one of its Sections.
local function groupOf(section: string): string?
	for _, jump in JUMPS do
		if jump.Key == section or table.find(jump.Sections, section) then
			return jump.Key
		end
	end
	return nil
end

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
	self.seen = {} :: { [string]: any } -- what the badges count as seen (by group)
	self.busy = {} :: { [string]: boolean } -- buy requests in flight, by button
	self.openedOn = nil :: string? -- the group the Shop was opened on (a late layout jumps again)
	self.openedAt = 0

	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Shop,
		icon = if K.Icons.ShopBasket ~= "" then "ShopBasket" else "Shop",
		money = true,
		-- The money pill's "+" goes to the money packs, as the money HUD's does (designer,
		-- 2026-10-06; the Money group's page comes with its section).
		moneyPlus = function()
			self.jumpRail:jump("Money")
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
		odds = function()
			self.odds:block("GrandOpening")
		end,
	})
	self.gift = ShopGift.new(self, frame)
	-- Every lucky block's dice opens one "Odds & Details" popup over the pages.
	self.odds = OddsDetails.new(frame)
	self.mysteryOdds = ShopMysteryOdds.new(self.odds, "mysteryOdds")
	local function odds(kind: string)
		self.odds:block(kind)
	end
	-- Studio only: GuiQA:Invoke("blockOdds", kind) presses that block's dice (the open Shop's).
	GuiQA.add("blockOdds", function(kind: string)
		odds(kind)
		return #self.odds.items
	end)
	-- The Blocks group under the card: its header first (it peeks in at the bottom of the first
	-- screen), then the Mystery block, the restock and the offers.
	local blocks = HudParts.frame(scroll, "Blocks")
	blocks.ZIndex = 2
	self.blocks = blocks
	self.blocksHead = GrandOpeningCard.header(blocks, COPY.BlocksHeader)
	local function buyProduct(key: string)
		self:buyProduct(key)
	end
	local function gift(key: string)
		if self:productReady(key) then
			self.gift:open(key)
		end
	end
	self.mystery = ShopMystery.new(blocks, {
		robux = buyProduct,
		money = function(count: number)
			self:buyBlocks("Mystery", count)
		end,
		gift = gift,
		odds = function()
			self.mysteryOdds:open()
		end,
	})
	self.restock = ShopRestock.new(blocks, {
		robux = buyProduct,
		money = function(itemId: string, block: string)
			self:buyRestock(itemId, block)
		end,
		getVip = function()
			local state = ItemState.shop()
			local offers = if type(state) == "table" and type(state.offers) == "table"
				then state.offers
				else {}
			local offer = offers.VipOffer
			self:buyProduct(
				if type(offer) == "table" and offer.open == true then "VipOffer" else "Vip"
			)
		end,
		odds = odds,
	})
	self.offers = ShopOffers.new(blocks, { robux = buyProduct, gift = gift, odds = odds })
	-- Studio only: GuiQA:Invoke("offers", patch) draws the Starter Pack and VIP over the shop
	-- state with `patch`'s fields (restricted, vip, starterBought, offers); nil goes back.
	GuiQA.add("offers", function(patch: any)
		self.offers.fake = patch
		self:refresh()
		return self.offers.show
	end)
	-- The Money group: its header, then the packs.
	local moneyGroup = HudParts.frame(scroll, "Money")
	moneyGroup.ZIndex = 2
	self.moneyGroup = moneyGroup
	self.moneyHead = GrandOpeningCard.header(moneyGroup, COPY.MoneyHeader)
	self.money = ShopMoney.new(moneyGroup, { robux = buyProduct, gift = gift })
	-- The Passes group: its header, then the passes.
	local passesGroup = HudParts.frame(scroll, "Passes")
	passesGroup.ZIndex = 2
	self.passesGroup = passesGroup
	self.passesHead = GrandOpeningCard.header(passesGroup, COPY.PassesHeader)
	self.passes = ShopPasses.new(passesGroup, {
		robux = buyProduct,
		gift = gift,
		plus = function()
			self:getPlus()
		end,
	})
	local more = HudParts.note(scroll, "MoreBelow", P.MoreBelowTextPx, COPY.MoreBelow)
	more.AnchorPoint = Vector2.new(0.5, 0.5)
	more.ZIndex = 3
	self.more = more

	-- The jump buttons (in the panel, so a gamepad reaches them).
	local groups: { JumpRail.Group } = {}
	local words: { [string]: string } = COPY.Jump
	for _, jump in JUMPS do
		table.insert(
			groups,
			{ key = jump.Key, text = words[jump.Key] or jump.Key, icon = jump.Icon }
		)
	end
	self.jumpRail = JumpRail.new({
		frame = frame,
		scroll = scroll,
		groups = groups,
		badge = COPY.New,
		badgeShare = P.BadgeShare,
		action = "8ballShopJump",
		root = function(key: string): GuiObject?
			return if key == "Featured"
				then self.featured.root
				elseif key == "Blocks" then self.blocks
				elseif key == "Money" then self.moneyGroup
				elseif key == "Passes" then self.passesGroup
				else nil
		end,
	})
	-- Each built group's top on the page (pixels), and a section's with its own place ("Offer").
	self.tops = self.jumpRail.tops
	-- The lively frame's open: the jump buttons pop in top to bottom, each NEW badge just after
	-- its button (Config.UI.Shop.Open "Tab1".. and "Tab1Badge"..).
	local stage = frame.stage
	if stage then
		self.jumpRail:register(stage)
		local function keep(handle)
			frame:idle(handle)
		end
		self.featured:register(stage, keep)
		stage:add("BlocksHead", self.blocksHead.word)
		stage:add("BlocksLines", self.blocksHead.lines)
		self.mystery:register(stage, keep)
		self.restock:register(stage, keep)
		self.offers:register(stage, keep)
		stage:add("MoneyHead", self.moneyHead.word)
		stage:add("MoneyLines", self.moneyHead.lines)
		self.money:register(stage, keep)
		stage:add("PassesHead", self.passesHead.word)
		stage:add("PassesLines", self.passesHead.lines)
		self.passes:register(stage, keep)
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
		local pageW = width - (if self.jumpRail:outside(panelW) then 0 else self.jumpRail:room(nil))
		return GrandOpeningCard.heightFor(pageW - self.scroll.ScrollBarThickness) + P.PeekPx
	end
	ItemState.Changed.Shop:Connect(function()
		self:refresh()
	end)

	local handle: Menus.Handle = {
		open = function(tab: string?)
			frame:open()
			local group = if tab then groupOf(tab) else nil
			if tab and group then
				self.openedOn, self.openedAt = tab, os.clock()
				self.jumpRail:jump(group, true)
				self.jumpRail:scrollTo(tab, true)
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
	self.mystery:refresh(state)
	self.odds:refresh()
	self.restock:refresh(state)
	self.money:refresh(state)
	local passesChanged = self.passes:refresh(state)
	if self.offers:refresh(state) or passesChanged then
		self:layout() -- a card came or went
	end
end

function ShopMenu.layout(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not self.frame:isOpen() or geo == nil then
		return
	end
	local width = self.jumpRail:layout(geo)
	self.scroll.Size = UDim2.fromOffset(width, geo.content.Y)
	-- The card fits the page whole (designer, 2026-10-06: no scrolling on a phone).
	local height = self.featured:layout(width - self.scroll.ScrollBarThickness)
	-- Below the card the Blocks group: its header, the Mystery block, the restock, the offers.
	local k = self.featured.k
	local pageW = width - self.scroll.ScrollBarThickness
	local headH = GrandOpeningCard.headerHeight(k)
	self.tops.Featured = 0
	self.tops.Blocks = height
	GrandOpeningCard.layoutHeader(self.blocksHead, round(pageW / 2), round(headH / 2), k)
	local y = headH + round(SB.HeaderGapUnits * k)
	y += self.mystery:layout(pageW, k, y)
	y += round(SB.GapUnits * k)
	y += self.restock:layout(pageW, k, y)
	local offersH = self.offers:layout(pageW, k, y + round(SB.GapUnits * k))
	self.tops.Offer = nil
	self.tops.Vip = nil
	if offersH > 0 then
		self.tops.Offer = height + y
		self.tops.Vip = self.tops.Offer -- VIP is in the pair (the HUD's VIP chip)
		y += round(SB.GapUnits * k) + offersH
	end
	y += round(SB.GapUnits * k)
	self.blocks.Position = UDim2.fromOffset(0, height)
	self.blocks.Size = UDim2.fromOffset(pageW, y)
	height += y
	-- The Money group: its header and the packs.
	self.tops.Money = height
	GrandOpeningCard.layoutHeader(self.moneyHead, round(pageW / 2), round(headH / 2), k)
	y = headH + round(SB.HeaderGapUnits * k)
	y += self.money:layout(pageW, k, y)
	y += round(SB.GapUnits * k)
	self.moneyGroup.Position = UDim2.fromOffset(0, height)
	self.moneyGroup.Size = UDim2.fromOffset(pageW, y)
	height += y
	-- The Passes group: its header and the passes.
	self.tops.Passes = height
	GrandOpeningCard.layoutHeader(self.passesHead, round(pageW / 2), round(headH / 2), k)
	y = headH + round(SB.HeaderGapUnits * k)
	y += self.passes:layout(pageW, k, y)
	y += round(SB.GapUnits * k)
	self.passesGroup.Position = UDim2.fromOffset(0, height)
	self.passesGroup.Size = UDim2.fromOffset(pageW, y)
	height += y
	local more = math.max(P.MoreBelowPx, geo.content.Y - height)
	self.more.Position = UDim2.fromOffset(round(width / 2), round(height + more / 2))
	self.more.Size = UDim2.fromOffset(math.max(1, width - 16), math.max(1, more))
	ShopParts.setCanvas(self.scroll, height + more)
	self.gift:layout(geo)
	self.odds:layout(geo)
	-- A new width keeps the lit group's top in view...
	self.jumpRail:relaid(pageW)
	-- ...but opened on a group or a place in one ("Offer"), a layout soon after the open (a late
	-- geometry pass) jumps there again, after relaid: the first open's real width comes a frame
	-- late, and relaid alone would leave the HUD's Starter Pack chip on the Blocks group's top.
	local on = self.openedOn
	if on and os.clock() - self.openedAt <= P.JumpSettleSeconds then
		self.jumpRail:scrollTo(if self.tops[on] then on else groupOf(on) or on, true)
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
	for _, jump in JUMPS do
		local mark = marks[jump.Key]
		local keep = opening and table.find(pinned, jump.Key) ~= nil
		self.jumpRail:setBadge(jump.Key, keep or (mark ~= nil and self.seen[jump.Key] ~= mark))
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

--- Buy restock item `itemId` (Slot1 .. Slot3, Vip) with money; its `block` lands in the hotbar.
function ShopMenu.buyRestock(self: any, itemId: string, block: string)
	self:send("Restock" .. itemId, function()
		return ItemState.request("ItemRequest", "BuyRestock", itemId)
	end, function(reply)
		if reply.ok then
			UISound.play("Claim")
			local names: { [string]: string } = Strings.LuckyBlocks.Names
			self.frame:notice(string.format(COPY.Blocks.Bought, names[block] or block), "Green")
		elseif reply.reason == "NotEnoughMoney" and type(reply.need) == "number" then
			self.frame:notice(ShopParts.need(reply.need), "Red")
		else
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

--- Roblox Plus's Get: the server shows Roblox's subscription prompt.
function ShopMenu.getPlus(self: any)
	self:send("Plus", function()
		return ItemState.request("StoreRequest", "RobloxPlus")
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
	for _, button in self.jumpRail:buttons() do
		table.insert(buttons, button)
	end
	local target = ShopParts.firstSelectable(buttons)
	if target then
		GuiService.SelectedObject = target
	else
		frame:focus()
	end
end

function ShopMenu.opened(self: any)
	self:refresh()
	self.jumpRail:opened()
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
end

function ShopMenu.closed(self: any)
	self.jumpRail:closed()
	self.mystery:closed()
	self.money:closed()
	self.openedOn = nil
	self.gift:close()
	self.odds:close()
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
	self:markSeen()
end

return ShopMenu
