--!strict
-- ShopMenu: the Shop (docs/prompts/ECONOMY_UI_PROMPT.md sections 11 and 12; ECONOMY 7, 9 and
-- 11), opened from the left column's Shop tile (or the D-pad's up in the hub) through Menus,
-- and by other menus on a tab (Menus.open("Shop", "Cases")). Tabs, each its own module:
-- - Cases (ShopCases): a card per case with Buy, Buy 10 (for the price of 9) and "Odds"
--   (ShopOdds: every cue's %, grouped by rarity, totalling 100); a sale's struck price and
--   countdown; the paid-random-items note instead of Buy where that is restricted.
-- - Limited (ShopLimited): the numbered Unique cues with "412 of 1,000 sold", a countdown, one
--   per player, "Owned #412".
-- - Money (ShopMoney): the seven packs with their Robux prices and the first-purchase double.
-- - VIP (ShopVip): VIP (or its welcome offer), the Starter Pack, Money Party, Fast Open.
-- Shared pieces (prices, pills, the grid fit, countdown words) are in ShopParts.
--
-- The server decides everything: this sends ids, counts and product keys only
-- (ItemState.request "ItemRequest" BuyCase / BuyLimited, "StoreRequest" Buy) and draws what
-- ShopState, the inventory snapshot and the money attribute say. A button is faded while its
-- request is on its way; a refusal shows its reason at the bottom (MenuFrame.reason). A buy the
-- money does not cover says "Need $X more" on the button itself (from the money attribute; a
-- refusal's `need` wins while the money is unchanged) and pressing it jumps to the Money tab
-- with the smallest pack that covers the gap lit (Shop.packForGap). Nothing here ever opens
-- the Shop by itself (never after a lost match). A bought case offers "Open now"
-- (deps.caseOpening:open). Countdowns tick here from the end times while the menu is open. A
-- gamepad on a button a redraw hides (a Buy turned "Owned") moves to the page's first button.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Net = require(Shared:WaitForChild("Net"))
local Progression = Shared:WaitForChild("Progression")
local Cases = require(Progression:WaitForChild("Cases"))
local Format = require(Progression:WaitForChild("Format"))
local Shop = require(Progression:WaitForChild("Shop"))
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local ShopCases = require(script.Parent.ShopCases)
local ShopLimited = require(script.Parent.ShopLimited)
local ShopMoney = require(script.Parent.ShopMoney)
local ShopOdds = require(script.Parent.ShopOdds)
local ShopParts = require(script.Parent.ShopParts)
local ShopVip = require(script.Parent.ShopVip)
local UISound = require(script.Parent.UISound)

local NAME = "Shop"
local TABS = { "Cases", "Limited", "Money", "Vip" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } = {
	Cases = "CaseStandard",
	Limited = "Limited",
	Money = "CashStack",
	Vip = "Vip",
}
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local REASONS: { [string]: string } = Strings.Menus.Reasons :: any
local CUE_NAMES: { [string]: string } = Strings.Items.Cues :: any

local ShopMenu = {}
ShopMenu.__index = ShopMenu

-- Whether `object` and every frame above it are visible.
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
-- Keys for the requests in flight and the server's last word on a price
--------------------------------------------------------------------------------------------

function ShopMenu.caseKey(caseId: string, count: number): string
	return ("Case:%s:%d"):format(caseId, count)
end

function ShopMenu.limitedKey(cueId: string): string
	return "Limited:" .. cueId
end

function ShopMenu.productKey(key: string): string
	return "Product:" .. key
end

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

--- Build the Shop (closed) and register it with Menus. `deps` is Progression's shared table:
--- money (MoneyHud), flyer (CashFlyer), column (MenuColumn), caseOpening (CaseOpening),
--- rankHud; a field may be filled after this returns, so it is read when used.
function ShopMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local self: any = setmetatable({}, ShopMenu)
	self.deps = deps
	self.busy = {} :: { [string]: boolean } -- request keys on their way
	self.told = {} :: { [string]: { need: number, money: number } } -- NotEnoughMoney replies
	self.dirty = true
	self.queued = false
	self.sizes = ShopParts.sizes(nil)
	self.content = Vector2.new(1, 1)
	self.ticker = nil :: RBXScriptConnection?
	self.nextTick = 0

	local words: { [string]: string } = Strings.Menus.Tabs.Shop :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Shop,
		icon = "Shop",
		tabs = tabs,
		money = true,
	})
	self.frame = frame
	-- "Loading..." on every page until the first ShopState.
	self.placeholders = {} :: { TextLabel }
	for _, key in TABS do
		table.insert(self.placeholders, MenuFrame.placeholder(frame:page(key)))
	end
	self.cases = ShopCases.new(self, frame:page("Cases"))
	self.limited = ShopLimited.new(self, frame:page("Limited"))
	self.moneyPage = ShopMoney.new(self, frame:page("Money"))
	self.vip = ShopVip.new(self, frame:page("Vip"))
	self.pages = { self.cases, self.limited, self.moneyPage, self.vip }
	self.byTab =
		{ Cases = self.cases, Limited = self.limited, Money = self.moneyPage, Vip = self.vip }
	self.odds = ShopOdds.new(self, frame)

	frame.onOpen = function()
		self:opened()
	end
	frame.onClose = function()
		self:closed()
	end
	frame.onTab = function(key: string)
		self:tabbed(key)
	end
	frame.onLayout = function(geo: MenuFrame.Geo)
		self.sizes = ShopParts.sizes(geo)
		self.content = geo.content
		self:layout()
	end
	self:listen()

	local handle: Menus.Handle = {
		open = function(tab: string?)
			frame:open(tab)
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
	return handle
end

-- Everything that changes what the Shop shows: the snapshots, the money, the party, the
-- Limited counts. Each asks for one redraw (at most one a frame; none while closed).
function ShopMenu.listen(self: any)
	local function changed()
		self:refresh()
	end
	ItemState.Changed.Shop:Connect(changed)
	ItemState.Changed.Items:Connect(changed)
	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Money"):Connect(changed)
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

--- Redraw soon (once this frame), or when the menu next opens.
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

-- Every page from the latest state, then the layout (which depends on what shows).
function ShopMenu.redraw(self: any)
	self.dirty = false
	local state = ItemState.shop()
	local ready = type(state) == "table"
	for _, label in self.placeholders :: { TextLabel } do
		label.Visible = not ready
	end
	for _, page in self.pages do
		page.root.Visible = ready
		if ready then
			page:refresh(state)
		end
	end
	self:layout()
	self:ensureSelection()
end

function ShopMenu.layout(self: any)
	if not self.frame:isOpen() then
		return
	end
	for _, page in self.pages do
		page:layout(self.sizes, self.content)
	end
	self.odds:layout(self.sizes)
end

-- The countdowns, a few times a second while open; a window that ran out redraws.
function ShopMenu.tick(self: any)
	local now = ShopParts.now()
	local crossed = false
	for _, page in self.pages do
		if page:tick(now) then
			crossed = true
		end
	end
	if crossed then
		self:refresh()
	end
end

--- Put a gamepad somewhere sensible when its selection is gone or hidden (a Buy that turned
--- into "Owned", the case opening over the Shop closed) or stays off after its answer (Money
--- Party full): the page's first button, else its tab. A button only off while its request is
--- out keeps it. Never while a dialog or the case opening is up.
function ShopMenu.ensureSelection(self: any)
	local frame = self.frame
	if not frame:isOpen() or #frame.dialogs > 0 or not ShopParts.gamepad() then
		return
	end
	local opener = self.deps and self.deps.caseOpening
	if opener and opener:isOpen() then
		return -- its own buttons have the gamepad; this runs again as it closes
	end
	local selected = GuiService.SelectedObject
	if selected ~= nil then
		if selected.Parent == nil then
			selected = nil
		elseif not selected:IsDescendantOf(frame.root) then
			return -- somewhere else on purpose
		end
	end
	if selected ~= nil then
		if ShopParts.firstSelectable({ selected }) ~= nil then
			return -- it shows and works
		end
		if shows(selected) and next(self.busy) ~= nil then
			return -- off only while a request is out: it comes back on
		end
	end
	local page = self.byTab[frame:currentTab()]
	local target = if page then page:first() else nil
	if target then
		GuiService.SelectedObject = target
	else
		frame:focus()
	end
end

function ShopMenu.opened(self: any)
	self:redraw()
	if not self.ticker then
		self.ticker = RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if clock >= self.nextTick then
				self.nextTick = clock + Config.UI.Shop.TickSeconds
				self:tick()
			end
		end)
	end
end

function ShopMenu.closed(self: any)
	self.odds:close()
	self.moneyPage:highlight(nil)
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
end

function ShopMenu.tabbed(self: any, key: string)
	self.odds:close()
	if key ~= "Money" then
		self.moneyPage:highlight(nil)
	end
	-- A gamepad whose selection was on the page that just hid lands on the new page's first
	-- button (LB and RB from inside a page stay inside), else on the tab.
	if ShopParts.gamepad() then
		local selected = GuiService.SelectedObject
		local lost = selected == nil
			or (
				selected:IsDescendantOf(self.frame.content)
				and ShopParts.firstSelectable({ selected }) == nil
			)
		if lost then
			local page = self.byTab[key]
			local target = if selected ~= nil and page then page:first() else nil
			if target then
				GuiService.SelectedObject = target
			else
				self.frame:focus()
			end
		end
	end
end

--------------------------------------------------------------------------------------------
-- Prices and what is missing
--------------------------------------------------------------------------------------------

--- The case sale running now for `caseId`, in Config.Cases.Sale's shape, or nil.
function ShopMenu.saleFor(_self: any, caseId: string, now: number): Cases.Sale?
	local state = ItemState.shop()
	local sale = if type(state) == "table" then state.sale else nil
	if
		type(sale) == "table"
		and sale.case == caseId
		and type(sale.percent) == "number"
		and type(sale.endsAt) == "number"
		and now < sale.endsAt
	then
		return { Case = caseId, Percent = sale.percent, EndsAt = sale.endsAt }
	end
	return nil
end

--- What `count` cases of `caseId` cost now (the sale and the bulk deal counted, as the server
--- prices them): total, per case, on sale.
function ShopMenu.casePrice(self: any, caseId: string, count: number): (number, number, boolean)
	local now = ShopParts.now()
	return Cases.price(caseId, count, now, self:saleFor(caseId, now))
end

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

--------------------------------------------------------------------------------------------
-- Requests
--------------------------------------------------------------------------------------------

-- Send one request (its buttons fade until the answer), then `done(reply)`.
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

-- A refusal: "Need $X more" on the button (the server's number), or the reason's words.
function ShopMenu.refused(self: any, key: string, reply: ItemState.Reply)
	if reply.reason == "NotEnoughMoney" and type(reply.need) == "number" then
		self.told[key] = { need = reply.need, money = ShopParts.money() }
		self.frame:notice(ShopParts.need(reply.need), "Red")
	else
		self.frame:notice(MenuFrame.reason(reply), "Red")
	end
end

--- Buy `count` cases (1 or Config.Cases.BulkCount): money short, the jump to Money instead.
function ShopMenu.buyCase(self: any, caseId: string, count: number)
	local key = ShopMenu.caseKey(caseId, count)
	local price = self:casePrice(caseId, count)
	local gap = self:needFor(key, price)
	if gap > 0 then
		self:jumpToMoney(gap)
		return
	end
	self:send(key, function()
		return ItemState.request("ItemRequest", "BuyCase", caseId, count)
	end, function(reply)
		if reply.ok then
			self.told[key] = nil
			UISound.play("Claim")
			local got = if type(reply.count) == "number" then reply.count else count
			self:offerOpen(if type(reply.caseId) == "string" then reply.caseId else caseId, got)
		else
			self:refused(key, reply)
		end
	end)
end

--- Buy a Limited cue: a money row through ItemRequest "BuyLimited" (money short: the jump to
--- Money), a Robux row through its product (StoreRequest).
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
	local price = if type(row.price) == "number" then row.price else 0
	local gap = self:needFor(key, price)
	if gap > 0 then
		self:jumpToMoney(gap)
		return
	end
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

--- Buy a Robux product or pass (a Config.Products key): the server checks it and shows
--- Roblox's purchase dialog; the grant arrives later as a new ShopState. "Coming soon" while
--- its Id is 0 (nothing is sent). `busyKey` fades another button instead (a Limited's).
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

-- After a case purchase: "Open now" (the reel; ten at once with Fast Open after Buy 10) or
-- later. The dialog sits over the Shop, which stays open under the case opening.
function ShopMenu.offerOpen(self: any, caseId: string, count: number)
	if not self.frame:isOpen() then
		return
	end
	local name = CASE_NAMES[caseId] or caseId
	local text = if count > 1
		then COPY.BoughtMany:format(name, count)
		else COPY.BoughtOne:format(name)
	self.frame:confirm({
		title = COPY.Bought,
		text = text,
		yes = COPY.OpenNow,
		no = COPY.Later,
		yesTone = "Green",
		noTone = "Blue",
	}, function(yes: boolean)
		local opener = self.deps and self.deps.caseOpening
		if not yes or not opener then
			return
		end
		local state = ItemState.shop()
		local fast = type(state) == "table" and state.fastOpen == true
		local open = if fast and count >= Config.Cases.FastOpenCount
			then Config.Cases.FastOpenCount
			else 1
		opener:open(caseId, open)
	end)
end

--- "Need $X more" was pressed: the Money tab with the smallest pack that covers `gap` lit
--- (a gamepad lands on it) and a line saying how much is missing. Only ever from a press.
function ShopMenu.jumpToMoney(self: any, gap: number)
	local state = ItemState.shop()
	local first = type(state) == "table" and state.firstPackBought == true
	local pack = Shop.packForGap(gap, first)
	self.frame:selectTab("Money")
	self.moneyPage:highlight(pack)
	self.frame:notice(COPY.NeedNotice:format(Format.money(gap)), "Ink")
	if ShopParts.gamepad() and pack then
		local button = self.moneyPage:buttonFor(pack)
		if button and button.Selectable then
			GuiService.SelectedObject = button
		end
	end
end

--- Open the odds panel of a case.
function ShopMenu.openOdds(self: any, caseId: string)
	Net.get("TutorialEvent"):FireServer("ShopViewed") -- the shop funnel (the tutorial lane)
	self.odds:open(caseId)
end

return ShopMenu
