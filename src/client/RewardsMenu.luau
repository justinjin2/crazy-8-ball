--!strict
-- RewardsMenu: the Rewards (docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened from the left
-- column's Rewards tile (or the D-pad's down in the hub) through Menus. Tabs, each its own
-- module:
-- - Daily (RewardsDaily): the week's seven day tiles, claimed ones with a check, today's
--   glowing with Claim, later ones dimmer; "Week 1 of 4: a Legendary Lucky Block on day 28".
-- - Playtime (RewardsPlaytime): $100, lucky blocks and the day's last ult spin, with
--   progress bars from the server's playtime today, Claim when due.
-- - Codes (RewardsCodes): a text box and Redeem; the server's answer under the box.
-- A tab with something to claim wears a small red "!" and the menu opens on it when opened
-- without a tab. An Index row's reward (the Rewards tile's dot counts it, the Inventory's Index
-- tab claims it) shows as a banner on the Daily tab with Open Index, which closes this menu and
-- opens the Inventory on its Index tab (ItemState's "Items" snapshot says when). What a claim
-- gave flies out of its button (RewardsFlyer): money into the money HUD, each lucky block to
-- the hotbar (or the column's Inventory tile), ult spins to its Ults button (the Rewards tile
-- without one), with the Claim sound. Nothing is ever claimed by itself and nothing pops up
-- (designer, 2026-10-04: every reward is claimed here).
--
-- Data: ItemState's "Rewards" snapshot (RewardState, src/shared/Net.luau), redrawn on every
-- ItemState.Changed.Rewards; claims through ItemState.request("RewardRequest", action, arg)
-- carrying only the action, a gift's index or the typed code. A button is off while its
-- request is on its way, and stays off after a claim until the next state arrives (so a quick
-- second press never asks twice); a refusal shows frame:notice(MenuFrame.reason(reply), "Red").
--
-- Gamepad: opening lands on the tab's main button (today's Claim, Open Index, a due gift's
-- Claim, the code box) when there is one, else on the tab; LB and RB switch tabs; B closes
-- (MenuFrame, Menus).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local RewardsCodes = require(script.Parent.RewardsCodes)
local RewardsDaily = require(script.Parent.RewardsDaily)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local RewardsParts = require(script.Parent.RewardsParts)
local RewardsPlaytime = require(script.Parent.RewardsPlaytime)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Rewards
local NAME = "Rewards"
local TABS = { "Daily", "Playtime", "Codes" }
-- Each tab's icon (Config.UI.Kit.Icons; an empty id shows none).
local TAB_ICONS: { [string]: string } =
	{ Daily = "Calendar", Playtime = "Stopwatch", Codes = "Code" }

local RewardsMenu = {}

local function gamepadInUse(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- Build the Rewards (closed) and register it with Menus. `deps` is Progression's shared
--- table: money (MoneyHud), flyer (CashFlyer), column (MenuColumn), rankHud; a
--- field may be filled after this returns, so it is read when used.
function RewardsMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local words: { [string]: string } = Strings.Menus.Tabs.Rewards :: any
	local tabs: { MenuFrame.Tab } = {}
	for _, key in TABS do
		table.insert(tabs, { key = key, text = words[key], icon = TAB_ICONS[key] })
	end
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.Rewards,
		icon = "Rewards",
		tabs = tabs,
	})
	local flyer = RewardsFlyer.new(screen, deps)

	-- Requests on their way, and claims answered but not yet seen in a state, by key ("Daily",
	-- "Gift1", "Code").
	local inFlight: { [string]: boolean } = {}
	local claimedAt: { [string]: number } = {}
	local version = 0 -- counts the RewardStates seen
	local state: any = ItemState.rewards()
	local ctx: any = {}
	local pages: { [string]: any } = {}
	local loading: { [string]: TextLabel } = {}
	local dots: { [string]: Frame } = {}

	function ctx.busy(key: string): boolean
		return inFlight[key] == true or claimedAt[key] == version
	end

	--- Whether an Index row's reward waits (the Daily tab's banner).
	function ctx.indexReady(): boolean
		return ItemState.indexReady()
	end

	--- The banner's Open Index: this menu closes, the Inventory opens on its Index tab.
	function ctx.openIndex()
		UISound.play("Click")
		Menus.open("Inventory", "Index")
	end

	-- Draw every page from the latest state.
	local function render()
		for _, key in TABS do
			local page = pages[key]
			if page then
				page:set(state)
			end
		end
		-- "Loading..." until the first state (the Codes tab works at once).
		for _, label in loading do
			label.Visible = type(state) ~= "table"
		end
	end

	-- The red "!" on a tab with something to claim.
	local function refreshDots()
		for key, dot in dots do
			local page = pages[key]
			local show = page ~= nil and page:claimable()
			if show ~= dot.Visible then
				if show then
					UIAnim.popIn(dot)
				else
					dot.Visible = false
				end
			end
		end
	end

	-- Whether `object` and every frame above it in this menu are visible.
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

	-- A claim button that was just switched off (or the Index banner that just went) hands a
	-- gamepad's selection to the page's main button, else to its tab.
	local function keepSelection()
		local selected = GuiService.SelectedObject
		if
			selected
			and selected:IsDescendantOf(frame.root)
			and (not selected.Selectable or not shows(selected))
		then
			local page = pages[frame:currentTab()]
			local target = page and page:primary()
			if target and target.Selectable then
				GuiService.SelectedObject = target
			else
				frame:focus()
			end
		end
	end

	--- Ask the server for a claim (`action` and `arg` as Net.luau's RewardRequest), with the
	--- button that asked (it flies the reward from there). `onReply` hears every answer.
	function ctx.claim(
		action: string,
		arg: any,
		key: string,
		button: GuiObject,
		onReply: ((any) -> ())?
	)
		if inFlight[key] then
			return
		end
		inFlight[key] = true
		UISound.play("Click")
		render()
		keepSelection()
		task.spawn(function()
			local reply = ItemState.request("RewardRequest", action, arg)
			inFlight[key] = nil
			if reply.ok then
				if action ~= "Redeem" then
					claimedAt[key] = version
				end
				UISound.play("Claim")
				local from = button.AbsolutePosition + button.AbsoluteSize / 2
				flyer:reward(reply, from)
			elseif action ~= "Redeem" then
				frame:notice(MenuFrame.reason(reply), "Red")
			end
			if onReply then
				onReply(reply)
			end
			render()
			refreshDots()
			keepSelection()
		end)
	end

	pages.Daily = RewardsDaily.new(frame:page("Daily"), ctx)
	pages.Playtime = RewardsPlaytime.new(frame:page("Playtime"), ctx)
	pages.Codes = RewardsCodes.new(frame:page("Codes"), ctx)
	for _, key in { "Daily", "Playtime" } do
		loading[key] = MenuFrame.placeholder(frame:page(key))
		local button = frame:tabButton(key)
		if button then
			dots[key] = RewardsParts.tabDot(button)
		end
	end

	-- Which page's loops run: the one showing while the menu is open.
	local function activate()
		local current = frame:currentTab()
		for key, page in pages do
			page:setActive(frame:isOpen() and key == current)
		end
	end

	-- The countdowns and bars tick while the menu is open.
	local ticking = 0
	local function startTicking()
		ticking += 1
		local mine = ticking
		task.spawn(function()
			while ticking == mine and frame:isOpen() do
				local now = workspace:GetServerTimeNow()
				for _, page in pages do
					page:tick(now)
				end
				refreshDots()
				task.wait(R.TickSeconds)
			end
		end)
	end

	frame.onLayout = function(geo: MenuFrame.Geo)
		for _, page in pages do
			page:layout(geo)
		end
	end
	frame.onTab = function(key: string)
		activate()
		if not gamepadInUse() then
			return
		end
		-- On the page shown, or on the tabs (MenuFrame keeps LB and RB there): leave it.
		local selected = GuiService.SelectedObject
		if
			selected
			and (selected:IsDescendantOf(frame:page(key)) or selected:IsDescendantOf(frame.tabRow))
		then
			return
		end
		local page = pages[key]
		local target = page and page:primary()
		if target then
			GuiService.SelectedObject = target
		else
			frame:focus()
		end
	end
	frame.onOpen = function()
		render()
		refreshDots()
		startTicking()
		-- A gamepad lands on the tab's main button (MenuFrame put it on the tab).
		if gamepadInUse() then
			local page = pages[frame:currentTab()]
			local target = page and page:primary()
			if target then
				GuiService.SelectedObject = target
			end
		end
	end
	frame.onClose = function()
		ticking += 1
		activate()
	end

	ItemState.Changed.Rewards:Connect(function(payload: any)
		state = payload
		version += 1
		render()
		refreshDots()
		if frame:isOpen() then
			keepSelection()
		end
	end)
	-- The inventory says when an Index row's reward waits: the Daily tab's banner follows.
	local indexShown = ItemState.indexReady()
	ItemState.Changed.Items:Connect(function(_items: any)
		if ItemState.indexReady() == indexShown then
			return
		end
		indexShown = not indexShown
		pages.Daily:set(state)
		refreshDots()
		if frame:isOpen() then
			keepSelection()
		end
	end)
	render()

	-- Opened with no tab: the first tab with something to claim, else the one shown last.
	local function bestTab(): string?
		for _, key in TABS do
			local page = pages[key]
			if page and page:claimable() then
				return key
			end
		end
		return nil
	end

	local handle: Menus.Handle = {
		open = function(tab: string?)
			if not frame:isOpen() then
				-- The pages' clocks catch up before the first frame shows them.
				local now = workspace:GetServerTimeNow()
				for _, page in pages do
					page:tick(now)
				end
			end
			frame:open(tab or bestTab())
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

return RewardsMenu
