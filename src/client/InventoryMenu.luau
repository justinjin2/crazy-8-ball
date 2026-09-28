--!strict
-- InventoryMenu: the Inventory (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the
-- left column's Inventory tile (or the D-pad's right in the hub) through Menus. Tabs:
-- - Cues (InventoryCues): a grid of cue cards (InventoryCard) with rarity filter chips, "Sell
--   all duplicates" with the total it pays, and the chosen cue's details: Equip, Sell, Sell
--   duplicates, "1,284 exist". NEW tags clear with MarkSeen when the tab is shown.
-- - Cases (InventoryCases): a row per case type owned with Open (and Open 10 with Fast Open)
--   into CaseOpening, and "Buy more" (the Shop's Cases tab). Empty state: a line and the jump.
-- - Index (InventoryIndex): every cue by rarity, never-owned ones as silhouettes with "?",
--   "5 / 7" per row with its reward and Claim, titles earned at the top.
--
-- This module builds the frame (MenuFrame), registers it with Menus and gives the pages what
-- they share (the `ctx` table): the server's snapshot (ItemState "Items"; every page redraws
-- from ItemState.Changed.Items), requests (ItemState.request("ItemRequest", ...), waiting for
-- one already on its way, a button disabled while its own is out), the money flying out of a
-- button into the header's cash (the kit's CashFlyer drawn over this menu; the money HUD
-- under it counts too), notices (a refusal: MenuFrame.reason in red), the confirm dialog, and
-- the gamepad's selection (a sensible stop when a page opens or a redraw takes the selected
-- button away). Red dots on the tab buttons: new cues on Cues, unopened cases on Cases, "!" on
-- Index while a row can be claimed. The column's own Inventory dot is MenuColumn's.
--
-- The server decides everything: the client sends ids and counts, and only animates the
-- replies and snapshots. Sizes in Config.UI.Inventory, words in Strings.Menus.Inventory.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local CashFlyer = require(script.Parent.CashFlyer)
local HudParts = require(script.Parent.HudParts)
local InventoryCases = require(script.Parent.InventoryCases)
local InventoryCues = require(script.Parent.InventoryCues)
local InventoryIndex = require(script.Parent.InventoryIndex)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local I = Config.UI.Inventory
local K = Config.UI.Kit
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]

local NAME = "Inventory"
local TABS = { "Cues", "Cases", "Index" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } = { Cues = "Cue", Cases = "CaseStandard", Index = "Index" }

local InventoryMenu = {}

local function isGamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- Build the Inventory (closed) and register it with Menus. `deps` is Progression's shared
--- table: money (MoneyHud), flyer (CashFlyer), column (MenuColumn), caseOpening
--- (CaseOpening), rankHud; a field may be filled after this returns, so read it when used.
function InventoryMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local words: { [string]: string } = Strings.Menus.Tabs.Inventory :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Inventory,
		icon = "Inventory",
		tabs = tabs,
		money = true,
	})

	--------------------------------------------------------------------------------------------
	-- What the pages share
	--------------------------------------------------------------------------------------------

	-- lastItems: the snapshot the pages last drew (nil before the first).
	local ctx: any = { frame = frame, deps = deps, lastItems = nil }
	local pages: { [string]: any } = {}
	local held: { [Instance]: boolean } = {}

	--- A { phone, full } pair at the last layout's size, in whole pixels.
	function ctx.span(pair: { number }): number
		local geo = frame.geo
		local t = if geo then geo.t else 0
		return math.floor(pair[1] + (pair[2] - pair[1]) * t + 0.5)
	end

	function ctx.gamepad(): boolean
		return isGamepad()
	end

	function ctx.isOpen(): boolean
		return frame:isOpen()
	end

	--- Whether `object` shows now: it and every frame above it in this menu are visible.
	function ctx.isShown(object: Instance): boolean
		local node: Instance? = object
		while node and node ~= frame.gui do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return node == frame.gui
	end

	--- Ask the server (ids and counts only). Waits a moment for another ItemRequest of this
	--- player's to come back first (ItemState would answer Busy). Never errors.
	function ctx.request(action: string, a: any?, b: any?): ItemState.Reply
		local waited = 0
		while ItemState.isBusy("ItemRequest") and waited < I.RequestWaitSeconds do
			waited += task.wait(I.RequestPollSeconds)
		end
		return ItemState.request("ItemRequest", action, a, b)
	end

	function ctx.isHeld(button: Instance): boolean
		return held[button] == true
	end

	--- Run `fn` (which asks the server) with `button` disabled until it returns, then let the
	--- pages redraw its state; a gamepad that was on it stays on it.
	function ctx.hold(button: TextButton, fn: () -> ())
		if held[button] then
			return
		end
		held[button] = true
		local wasSelected = GuiService.SelectedObject == button
		HudParts.setEnabled(button, false, false)
		local ok, err = pcall(fn :: any)
		held[button] = nil
		if not ok then
			warn("[8ball] Inventory: " .. tostring(err))
		end
		ctx.refresh()
		if
			wasSelected
			and frame:isOpen()
			and GuiService.SelectedObject == nil
			and button.Parent ~= nil
			and button.Selectable
			and ctx.isShown(button)
		then
			GuiService.SelectedObject = button
		end
		ctx.ensureSelection()
	end

	--- A short line at the bottom of the menu ("Ink", "Green" or "Red" pill).
	function ctx.notice(text: string, toneName: string?)
		if frame:isOpen() then
			frame:notice(text, toneName)
		end
	end

	--- A request that did not work: its reason, in red.
	function ctx.refuse(reply: any)
		ctx.notice(MenuFrame.reason(reply), "Red")
	end

	--- Ask first (MenuFrame's dialog: the red button sells, the blue one keeps).
	function ctx.confirm(opts: MenuFrame.ConfirmOptions, callback: (boolean) -> ())
		frame:confirm(opts, callback)
	end

	-- The flying money: the kit's CashFlyer, drawn in this menu's own ScreenGui (over the
	-- panel) and landing on the header's cash; each landing also lands in the money HUD under
	-- the menu (it was told to expect it), so the two never disagree.
	local moneyProxy = {
		iconCenter = function(_self: any): Vector2
			local point = frame:moneyCenter()
			if point then
				return point
			end
			local money = deps.money
			return if money then money:iconCenter() else Vector2.zero
		end,
		expect = function(_self: any, amount: number)
			local money = deps.money
			if money then
				money:expect(amount)
			end
		end,
		land = function(_self: any, amount: number)
			local money = deps.money
			if money then
				money:land(amount)
			else
				UISound.play("CashLand")
			end
			local pill: Frame? = frame.moneyPill
			if pill and frame:isOpen() then
				UIAnim.bounce(pill)
			end
		end,
	}
	local chips = CashFlyer.new(frame.gui, moneyProxy, function(_tableId: number, _pocket: number)
		return nil
	end)

	--- `amount` money flies out of `from` (a button) into the header's cash: green for a sale,
	--- gold for a reward (`kind` "Reward"). The server already paid it; this only shows it.
	function ctx.flyMoney(amount: number, from: GuiObject, kind: string?)
		if type(amount) ~= "number" or amount <= 0 then
			return
		end
		local point = from.AbsolutePosition + from.AbsoluteSize / 2
		if frame:isOpen() then
			moneyProxy:expect(amount)
			chips:fly(amount, point, kind, 0)
		elseif deps.flyer and deps.money then
			-- The menu closed while the server answered: into the HUD itself.
			deps.money:expect(amount)
			deps.flyer:fly(amount, point, kind, 0)
		end
	end

	--- The page showing now.
	local function current(): any
		return pages[frame:currentTab()]
	end

	--- Put a gamepad somewhere sensible when its selection is gone or hidden (a page opened,
	--- a redraw took the selected button away). Never while a dialog is up.
	function ctx.ensureSelection()
		if not frame:isOpen() or #frame.dialogs > 0 or not isGamepad() then
			return
		end
		local selected = GuiService.SelectedObject
		if selected ~= nil then
			if selected.Parent == nil then
				selected = nil
			elseif not selected:IsDescendantOf(frame.root) then
				return -- somewhere else on purpose
			elseif ctx.isShown(selected) and selected.Selectable then
				return
			end
		end
		local page = current()
		local first = if page then page:first() else nil
		GuiService.SelectedObject = first or frame:tabButton(frame:currentTab())
	end

	--------------------------------------------------------------------------------------------
	-- The red dots on the tab buttons
	--------------------------------------------------------------------------------------------

	local dots: { [string]: { dot: Frame, text: TextLabel } } = {}
	for _, key in TABS do
		local button = frame:tabButton(key)
		if button then
			local dot = HudParts.pill(button, "Dot", HudParts.tone("Red"))
			dot.AnchorPoint = Vector2.new(0.5, 0.5)
			dot.Position = UDim2.new(1, -I.TabDotPx / 4, 0, I.TabDotPx / 4)
			dot.ZIndex = 8
			dot.Visible = false
			local text = HudParts.text(dot, "Count", I.TabDotTextPx, "")
			text.AutoLocalize = false -- a number
			text.TextWrapped = false
			text.Size = UDim2.fromScale(1, 1)
			text.ZIndex = 9
			dots[key] = { dot = dot, text = text }
		end
	end

	local function setDot(key: string, value: string?)
		local entry = dots[key]
		if not entry then
			return
		end
		local show = value ~= nil and value ~= ""
		if show then
			local text = value :: string
			if entry.text.Text ~= text then
				entry.text.Text = text
				local width =
					TextService:GetTextSize(text, I.TabDotTextPx, FONT, Vector2.new(200, 100)).X
				entry.dot.Size =
					UDim2.fromOffset(math.max(I.TabDotPx, math.ceil(width) + 10), I.TabDotPx)
			end
		end
		entry.dot.Visible = show
	end

	local function countText(n: number): string?
		if n <= 0 then
			return nil
		end
		return if n > I.TabDotMax then Strings.Menus.DotMore:format(I.TabDotMax) else tostring(n)
	end

	local function refreshDots(items: any)
		for key, page in pages do
			local value = if type(page.dot) == "function" then page:dot(items) else nil
			if type(value) == "number" then
				setDot(key, countText(value))
			elseif type(value) == "string" then
				setDot(key, value)
			else
				setDot(key, nil)
			end
		end
	end

	--------------------------------------------------------------------------------------------
	-- The pages
	--------------------------------------------------------------------------------------------

	pages.Cues = InventoryCues.new(frame:page("Cues"), ctx)
	pages.Cases = InventoryCases.new(frame:page("Cases"), ctx)
	pages.Index = InventoryIndex.new(frame:page("Index"), ctx)

	-- The chosen tab's button leads a gamepad down into its page; the others go the usual way.
	local function linkTabs()
		local key = frame:currentTab()
		for name in pages do
			local button = frame:tabButton(name)
			if button then
				local page = pages[name]
				button.NextSelectionDown = if name == key then page:first() else nil
			end
		end
	end

	--- Redraw every page from the latest snapshot (the menu must be open; a closed menu
	--- redraws when it opens).
	function ctx.refresh()
		if not frame:isOpen() then
			return
		end
		local items = ItemState.items()
		ctx.lastItems = items
		for _, key in TABS do
			pages[key]:redraw(items)
		end
		refreshDots(items)
		linkTabs()
	end

	frame.onLayout = function(geo: MenuFrame.Geo)
		for _, key in TABS do
			pages[key]:layout(geo)
		end
	end
	frame.onOpen = function()
		for _, key in TABS do
			pages[key]:opened()
		end
		ctx.refresh()
	end
	frame.onTab = function(key: string)
		for _, name in TABS do
			if name ~= key then
				pages[name]:hidden()
			end
		end
		pages[key]:shown()
		linkTabs()
		-- A gamepad whose selection was in the page just hidden moves into this one.
		local selected = GuiService.SelectedObject
		if
			isGamepad()
			and selected ~= nil
			and selected:IsDescendantOf(frame.root)
			and not ctx.isShown(selected)
		then
			GuiService.SelectedObject = pages[key]:first() or frame:tabButton(key)
		end
	end
	frame.onClose = function()
		for _, key in TABS do
			pages[key]:hidden()
			pages[key]:closed()
		end
	end

	ItemState.Changed.Items:Connect(function(_items: any)
		if frame:isOpen() then
			ctx.refresh()
			ctx.ensureSelection()
		end
	end)

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
	}
	Menus.register(NAME, handle)
	return handle
end

return InventoryMenu
