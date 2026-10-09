--!strict
-- InventoryMenu: the Cues menu ("Inventory" in code: Menus, the column, the tutorial and the
-- saves keep that name) (docs/prompts/CUES_LIVELY_PROMPT.md, concept 2, approved round 2,
-- 2026-10-08), opened from the left column's CUES tile (or the D-pad's right in the hub)
-- through Menus. It wears the lively frame (MenuFrame: the panel unrolls, the header's
-- 8-balls, the money pill and its "+", the 8-ball flair) with no tab row: one page holding two
-- views, chosen by the My Cues and Index tiles outside the panel's right edge (CuesRail) or
-- by LB / RB:
-- - My Cues (InventoryCues): the grid, 5 cards a row, the panel as tall as two whole rows with
--   the third peeking; a card pressed slams in its big card with Equip and Sell duplicates.
--   NEW tags clear with MarkSeen when the view is shown.
-- - Index (InventoryIndex): every cue by rarity, never-owned ones locked, "5 / 7" per
--   row with its reward and Claim, titles earned at the top, the chosen cue's card.
-- The title and the header's icon say which view shows. B goes back one step: the big card
-- closes, then the Index goes back to My Cues, then the menu closes (Escape the same).
--
-- This module builds the frame, the rail and the views, registers with Menus and gives the
-- views what they share (the `ctx` table): the server's snapshot (ItemState "Items"; every view
-- redraws from ItemState.Changed.Items), requests (ItemState.request("ItemRequest", ...), which
-- waits for one already on its way; a button disabled while its own is out), the money flying
-- out of a button into the header's cash (the kit's CashFlyer drawn over this menu; the money
-- HUD under it counts too), notices (a refusal: MenuFrame.reason in red), the confirm dialog,
-- and the gamepad's selection (a sensible stop when a view opens or a redraw takes the selected
-- button away). Red dots on the tiles: new cues on My Cues, "!" on the Index while a row can
-- be claimed.
--
-- The server decides everything: the client sends ids and counts, and only animates the
-- replies and snapshots. Sizes in Config.UI.Inventory, words in Strings.Menus.Inventory.
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CashFlyer = require(script.Parent.CashFlyer)
local CuesRail = require(script.Parent.CuesRail)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local InventoryCues = require(script.Parent.InventoryCues)
local InventoryIndex = require(script.Parent.InventoryIndex)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Inventory.Rail
local TITLES = Strings.Menus.Titles

local NAME = "Inventory"
-- The two views, My Cues first; RewardsMenu opens the Index by name.
local VIEWS = { "Cues", "Index" }
local VIEW_ACTION = "8ballCuesView" -- LB / RB
local VIEW_PRIORITY = Enum.ContextActionPriority.High.Value + 20 -- like the menus' LB / RB
local BACK_ACTION = "8ballCuesBack" -- B in the Index: back to My Cues
local BACK_PRIORITY = Enum.ContextActionPriority.High.Value + 25 -- under the big card's B (+30)

local InventoryMenu = {}

local function isGamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- Build the Cues menu (closed) and register it with Menus. `deps` is Progression's shared
--- table: money (MoneyHud), flyer (CashFlyer), column (MenuColumn), rankHud; a field may be
--- filled after this returns, so read it when used.
function InventoryMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = TITLES.Inventory,
		icon = CuesRail.cuesIcon(),
		money = true,
		-- The money pill's "+" goes to the money packs, as the money HUD's does.
		moneyPlus = function()
			Menus.open("Shop", "Money")
		end,
	})

	--------------------------------------------------------------------------------------------
	-- What the views share
	--------------------------------------------------------------------------------------------

	-- lastItems: the snapshot the views last drew (nil before the first).
	local ctx: any = { frame = frame, deps = deps, lastItems = nil }
	local pages: { [string]: any } = {}
	local held: { [Instance]: boolean } = {}
	local view = "Cues" -- the view showing
	local stale: { [string]: boolean } = {} -- views whose snapshot changed while hidden
	local rail: any -- built once the views exist
	local views: { [string]: Frame } = {}

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

	--- Ask the server (ids and counts only). Another ItemRequest of this player's on its way
	--- goes first (ItemState waits for it). Never errors.
	function ctx.request(action: string, a: any?, b: any?): ItemState.Reply
		return ItemState.request("ItemRequest", action, a, b)
	end

	function ctx.isHeld(button: Instance): boolean
		return held[button] == true
	end

	--- Run `fn` (which asks the server) with `button` disabled until it returns, then let the
	--- views redraw its state; a gamepad that was on it stays on it.
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
			warn("[8ball] Cues: " .. tostring(err))
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
			-- The header's cash swells smoothly (the whole pill jumping in one frame looked
			-- choppy, 2026-10-08).
			local cash: GuiObject? = frame.moneyCash
			if cash and frame:isOpen() then
				UIAnim.thump(cash)
			end
		end,
	}
	-- The chips fly in their own small ScreenGui just over the menu (as the Rewards menu's,
	-- RewardsFlyer). Drawn inside the menu's own ScreenGui (thousands of cards' parts) they
	-- were redrawn only every other frame, so they stepped along at 30 a second while the rest
	-- moved at 60 (designer, 2026-10-08: "still choppy ... as if it's lagging the entire screen").
	local flyGui = Instance.new("ScreenGui")
	flyGui.Name = "CuesCashFlyer" -- kept on by HudFocus (Config.UI.Menu.Focus.Keep)
	flyGui.ResetOnSpawn = false
	flyGui.IgnoreGuiInset = true
	flyGui.ScreenInsets = Enum.ScreenInsets.None
	flyGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	flyGui.DisplayOrder = frame.gui.DisplayOrder + 1
	flyGui.Parent = frame.gui.Parent
	local chips = CashFlyer.new(flyGui, moneyProxy, function(_tableId: number, _pocket: number)
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

	--- Put a gamepad somewhere sensible when its selection is gone or hidden (a view opened,
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
		GuiService.SelectedObject = pages[view]:first() or rail:current()
	end

	--------------------------------------------------------------------------------------------
	-- The views, the rail
	--------------------------------------------------------------------------------------------

	local page = frame:page()
	for _, key in VIEWS do
		local holder = HudParts.frame(page, key .. "View")
		holder.Size = UDim2.fromScale(1, 1)
		holder.ZIndex = 2
		holder.Visible = key == view
		views[key] = holder
	end
	-- The big card opens over the whole page.
	pages.Cues = InventoryCues.new(views.Cues, ctx, page)
	pages.Index = InventoryIndex.new(views.Index, ctx)

	local setView: (key: string, instant: boolean?) -> ()
	rail = CuesRail.new(frame, {
		view = function(key: string)
			if key == view then
				UISound.play("Click") -- already there (setView clicks on a change)
			end
			setView(key)
		end,
		sort = function()
			pages.Cues:nextSort()
		end,
		sell = function()
			pages.Cues:askSellAll()
		end,
	})
	ctx.rail = rail

	-- The lively open: the rail's tiles and the views' first pieces (Config.UI.Inventory.Open).
	local stage = frame.stage
	if stage then
		rail:register(stage)
		pages.Cues:register(stage)
		pages.Index:register(stage)
	end

	local function countText(n: number): string?
		if n <= 0 then
			return nil
		end
		return if n > R.DotMax then Strings.Menus.DotMore:format(R.DotMax) else tostring(n)
	end

	local function refreshDots(items: any)
		local new = pages.Cues:dot(items)
		rail:setDots(countText(if type(new) == "number" then new else 0), pages.Index:dot(items))
	end

	-- Studio only (GuiQA "cuesCopies"): a stand-in copy number on every Rare-or-rarer cue, to
	-- see the numbered card's chip before copy numbers exist.
	local fakeCopies = false
	local function withFakeCopies(items: any): any
		if not fakeCopies or type(items) ~= "table" or type(items.cues) ~= "table" then
			return items
		end
		local fake = table.clone(items)
		fake.cues = {}
		for index, row in items.cues do
			local copy = table.clone(row)
			local cue = Catalog.get(row.id)
			if cue and Catalog.rarityRank(cue.Rarity) >= Catalog.rarityRank("Rare") then
				copy.copy = (index * 37) % 100 + 1
			end
			fake.cues[index] = copy
		end
		return fake
	end

	--- Redraw from the latest snapshot (`always`: both views, even while closed, just before an
	--- open, so the open shows the cards it staggers in). Otherwise only the view showing
	--- redraws; the other one does as it is shown, so a sale never rebuilds the Index's grid in
	--- the frames its money chip flies (designer, 2026-10-08: it looked laggy).
	function ctx.refresh(always: boolean?)
		if not frame:isOpen() and not always then
			return
		end
		local items = withFakeCopies(ItemState.items())
		ctx.lastItems = items
		for _, key in VIEWS do
			if always or key == view then
				pages[key]:redraw(items)
				stale[key] = nil
			else
				stale[key] = true
			end
		end
		refreshDots(items)
	end

	-- B (and Escape) in the Index goes back to My Cues, under the big card's own B.
	local backBound = false
	local escape: RBXScriptConnection? = nil
	local function bindBack(on: boolean)
		if on == backBound then
			return
		end
		backBound = on
		if on then
			ContextActionService:BindActionAtPriority(
				BACK_ACTION,
				function(_name: string, state: Enum.UserInputState)
					if state == Enum.UserInputState.Begin and #frame.dialogs == 0 then
						setView("Cues")
						return Enum.ContextActionResult.Sink
					end
					return Enum.ContextActionResult.Pass
				end,
				false,
				BACK_PRIORITY,
				Enum.KeyCode.ButtonB
			)
			escape = UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape and #frame.dialogs == 0 then
					Menus.swallowEscape(input)
					setView("Cues")
				end
			end)
		else
			ContextActionService:UnbindAction(BACK_ACTION)
			if escape then
				escape:Disconnect()
				escape = nil
			end
		end
	end

	-- Run the views' shown / hidden as the old tabs did.
	local function showViews()
		for _, key in VIEWS do
			if key ~= view and pages[key].hidden then
				pages[key]:hidden()
			end
		end
		if pages[view].shown then
			pages[view]:shown()
		end
	end

	--- Show a view (`instant`: no replay, as when opening on it).
	function setView(key: string, instant: boolean?)
		if not views[key] then
			return
		end
		local changed = key ~= view
		view = key
		for name, holder in views do
			holder.Visible = name == key
		end
		rail:setView(key, instant)
		HudParts.setIcon(frame.icon, if key == "Index" then "Index" else CuesRail.cuesIcon())
		frame:setTitle(if key == "Index" then TITLES.Index else TITLES.Inventory) -- lays out
		if not frame:isOpen() then
			return
		end
		bindBack(key == "Index")
		if not changed then
			return
		end
		UISound.play("Click")
		if stale[key] then
			stale[key] = nil
			pages[key]:redraw(ctx.lastItems)
		end
		showViews()
		-- The view's pieces stagger in again (not during the open: it shows them).
		if stage and not instant and stage:busy() ~= "play" then
			local ids = stage:idsUnder(views[key])
			if #ids > 0 then
				pages[key]:hold()
				stage:replay(ids)
			end
		end
		-- A gamepad whose selection was in the view just hidden moves into this one.
		local selected = GuiService.SelectedObject
		if
			isGamepad()
			and selected ~= nil
			and selected:IsDescendantOf(frame.root)
			and not ctx.isShown(selected)
		then
			GuiService.SelectedObject = pages[key]:first() or rail:current()
		end
	end

	frame.onLayout = function(geo: MenuFrame.Geo)
		local width = rail:layout(geo)
		local viewGeo = table.clone(geo)
		viewGeo.content = Vector2.new(width, geo.content.Y)
		pages.Cues:layout(viewGeo)
		pages.Index:layout(viewGeo)
	end
	-- The panel is two whole rows of cards tall with the third peeking.
	frame.fitHeight = function(width: number, panelW: number): number
		local t = if frame.geo then frame.geo.t else 0
		local gridW = width - (if rail:outside(panelW, t) then 0 else rail:room(t))
		return InventoryCues.heightFor(gridW, t)
	end
	frame.onOpen = function()
		for _, key in VIEWS do
			if pages[key].opened then
				pages[key]:opened()
			end
		end
		ctx.refresh()
		bindBack(view == "Index")
		ContextActionService:BindActionAtPriority(
			VIEW_ACTION,
			function(_name: string, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin and #frame.dialogs == 0 then
					setView(if view == "Cues" then "Index" else "Cues")
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			VIEW_PRIORITY,
			Enum.KeyCode.ButtonL1,
			Enum.KeyCode.ButtonR1
		)
	end
	-- The frame has one page ("Main"): this runs once on open, for the view showing.
	frame.onTab = function(_key: string)
		showViews()
		if isGamepad() then
			ctx.ensureSelection()
		end
	end
	frame.onClose = function()
		ContextActionService:UnbindAction(VIEW_ACTION)
		bindBack(false)
		for _, key in VIEWS do
			if pages[key].hidden then
				pages[key]:hidden()
			end
			pages[key]:closed()
		end
	end

	-- The pictures the views' first screens show load in the background once the first
	-- snapshot is here (an image loads only when first drawn, so the open's cards and the first
	-- flip to the Index would pop in empty and fill in a moment later).
	local preloaded = false
	local function preload(items: any)
		if preloaded or type(items) ~= "table" then
			return
		end
		preloaded = true
		local list: { string } = {}
		for _, key in VIEWS do
			for _, picture in pages[key]:pictures(items) do
				table.insert(list, picture)
			end
		end
		if #list > 0 then
			task.spawn(function()
				pcall(function()
					ContentProvider:PreloadAsync(list :: { any })
				end)
			end)
		end
	end
	preload(ItemState.items())

	ItemState.Changed.Items:Connect(function(items: any)
		preload(items)
		if frame:isOpen() then
			ctx.refresh()
			ctx.ensureSelection()
		end
	end)

	--- Open on a view ("Cues" or "Index"; none: My Cues).
	local function open(tab: string?)
		local key = if tab and views[tab] then tab else "Cues"
		if frame:isOpen() then
			setView(key)
			return
		end
		setView(key, true)
		-- Drawn before the open plays, so the cards it staggers in are the ones it shows.
		ctx.refresh(true)
		if stage then
			for _, name in VIEWS do
				pages[name]:hold()
			end
		end
		frame:open()
	end

	local handle: Menus.Handle = {
		open = open,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
		ensureSelection = ctx.ensureSelection,
		notice = ctx.notice,
	}
	Menus.register(NAME, handle)

	-- Studio-only checks through the MCP (GuiQA): the view, a cue's big card.
	GuiQA.add("cuesView", function(key: string)
		Menus.open(NAME, key)
		return view
	end)
	GuiQA.add("cuesDetail", function(cueId: string)
		Menus.open(NAME, "Cues")
		return pages.Cues:show(cueId)
	end)
	-- The Index with `cueId` chosen (its panel: the card, the rarity, the odds or day line).
	GuiQA.add("cuesIndex", function(cueId: string)
		Menus.open(NAME, "Index")
		pages.Index:choose(cueId)
		return pages.Index.chosen
	end)
	-- `amount` money flies out of Sell dupes into the header's cash, as after a sale (the server
	-- pays nothing: the count only rises as far as the true total).
	GuiQA.add("cuesFly", function(amount: number?)
		Menus.open(NAME, "Cues")
		ctx.flyMoney(amount or 250, rail.sell)
		return true
	end)
	-- How long the showing view's redraw takes, in milliseconds (what a sale or a claim costs
	-- in the frame its money chip flies).
	GuiQA.add("cuesRedrawMs", function()
		local started = os.clock()
		pages[view]:redraw(ctx.lastItems)
		return (os.clock() - started) * 1000
	end)
	GuiQA.add("cuesCopies", function(on: boolean?)
		fakeCopies = on ~= false
		ctx.refresh(true)
		return fakeCopies
	end)
	return handle
end

return InventoryMenu
