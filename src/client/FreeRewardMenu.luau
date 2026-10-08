--!strict
-- FreeRewardMenu: the Free Reward menu (the designer's picks "daily A" and "free_other A" on the
-- mock page, 2026-10-08: every free reward in one menu; the old Rewards menu is merged into
-- it), opened from the left column's Free Reward tile (or the D-pad's down in the hub) through
-- Menus. The lively frame (MenuFrame: the panel unrolls, the money pill whose "+" opens the
-- Shop's money packs, the red X) and one page that scrolls under four jump buttons down the
-- right side (JumpRail, as the Shop's): Daily, Playtime, Track and Group, each wearing a red
-- "!" while its section has something to claim. The page, in the Grand Opening card's units
-- like the Shop's:
-- - "- DAILY -": the login row's seven days and Claim All (FreeDaily);
-- - "- PLAYTIME -": the day's five playtime gifts (FreePlaytime);
-- - "- TRACK -": the 28-day track (FreeTrack);
-- - "- GROUP -": join the group, favorite the game, invite a friend (FreeSocial).
-- Opened with no section it jumps to the first one with something to claim. The panel is as
-- tall as the Daily section, the next header peeking in under it (Config.UI.Shop.Page.PeekPx).
-- Codes are typed in Settings (and the Abilities screen).
--
-- Data: ItemState's "Rewards" snapshot (RewardState, src/shared/Net.luau), redrawn on every
-- ItemState.Changed.Rewards; claims through ItemState.request("RewardRequest", action, arg)
-- carrying only the action and a gift's index. What a claim gave flies out of its button
-- (RewardsFlyer): money into the money HUD, blocks to the hotbar, ability spins to the
-- Abilities tile. A button is off while its request is on its way, and stays off after a
-- claim until the next state arrives (so a quick second press never asks twice); a refusal
-- shows the server's reason as a notice. Claim All is a Robux product (StoreRequest "Buy":
-- Roblox's own dialog; "Coming soon" until the product is on sale).
--
-- Gamepad: opening lands on the first Claim (today's, a gift's, the group's), else on the lit
-- jump button; LB and RB step through the sections; B closes the odds pop-up, then the menu.
-- Sizes in Config.UI.FreeReward, words in Strings.FreeReward.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local FreeDaily = require(script.Parent.FreeDaily)
local FreePlaytime = require(script.Parent.FreePlaytime)
local FreeSocial = require(script.Parent.FreeSocial)
local FreeTrack = require(script.Parent.FreeTrack)
local GrandOpeningCard = require(script.Parent.GrandOpeningCard)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local JumpRail = require(script.Parent.JumpRail)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local ShopOdds = require(script.Parent.ShopOdds)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "FreeReward"
local F = Config.UI.FreeReward
local P = Config.UI.Shop.Page
local UNITS = Config.UI.GrandOpeningCard.Layout.Card[1] -- the page's width in units
local W = Strings.FreeReward
local JUMPS: { { Key: string, Icon: string } } = F.Jump :: any
local round = ShopParts.round

local FreeRewardMenu = {}

--- Build the menu (closed) and register it with Menus. `deps`: Progression's shared table
--- (money, flyer, column, rankHud); a field may be filled after this returns.
function FreeRewardMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.FreeReward,
		icon = "FreeReward",
		money = true,
		-- The money pill's "+" opens the Shop's money packs, as the money HUD's does.
		moneyPlus = function()
			Menus.open("Shop", "Money")
		end,
	})
	local flyer = deps.rewardsFlyer or RewardsFlyer.new(screen, deps)
	deps.rewardsFlyer = flyer
	local page = frame:page()
	local placeholder = MenuFrame.placeholder(page)
	local scroll = ShopParts.scroller(page, "Page")
	local geo: MenuFrame.Geo? = nil
	local state: any = ItemState.rewards()
	local openedOn: string? = nil -- the section the menu was opened on (a late layout jumps again)
	local openedAt = 0
	local ticker: RBXScriptConnection? = nil
	local nextTick = 0

	-- Requests on their way, and claims answered but not yet seen in a state, by key ("Daily",
	-- "Gift1", "Group", "Favorite", "ClaimAll").
	local inFlight: { [string]: boolean } = {}
	local claimedAt: { [string]: number } = {}
	local version = 0 -- counts the RewardStates seen

	local refresh: () -> ()
	local keepSelection: () -> ()
	local ctx: any = {}

	function ctx.busy(key: string): boolean
		return inFlight[key] == true or claimedAt[key] == version
	end

	function ctx.notice(text: string, toneName: string?)
		if frame:isOpen() then
			frame:notice(text, toneName)
		end
	end

	--- Ask the server for a claim (`action` and `arg` as Net.luau's RewardRequest), with the
	--- button that asked (the reward flies from there).
	function ctx.claim(action: string, arg: any, key: string, button: GuiObject)
		if inFlight[key] then
			return
		end
		inFlight[key] = true
		UISound.play("Click")
		refresh()
		task.spawn(function()
			local reply = ItemState.request("RewardRequest", action, arg)
			inFlight[key] = nil
			if type(reply) == "table" and reply.ok then
				claimedAt[key] = version
				UISound.play("Claim")
				local from = button.AbsolutePosition + button.AbsoluteSize / 2
				flyer:reward(reply, from)
			elseif type(reply) == "table" and reply.reason == "NotMember" then
				ctx.notice(W.NotMember, "Red")
			else
				ctx.notice(MenuFrame.reason(reply), "Red")
			end
			refresh()
			keepSelection()
		end)
	end

	--- Buy a Robux product (Claim All): the server checks it and shows Roblox's dialog; a
	--- product not on sale yet says "Coming soon".
	function ctx.buy(product: string)
		local shop = ItemState.shop()
		local products = if type(shop) == "table" and type(shop.products) == "table"
			then shop.products
			else {}
		local row = products[product]
		if type(row) ~= "table" or row.available ~= true then
			ctx.notice(W.ComingSoon, "Ink")
			return
		end
		local key = "ClaimAll"
		if inFlight[key] then
			return
		end
		inFlight[key] = true
		UISound.play("Click")
		refresh()
		task.spawn(function()
			local reply = ItemState.request("StoreRequest", "Buy", product)
			inFlight[key] = nil
			if not (type(reply) == "table" and reply.ok) then
				ctx.notice(MenuFrame.reason(reply), "Red")
			end
			refresh()
		end)
	end

	-- The four sections, each in its group under its header.
	local groups: { [string]: Frame } = {}
	local headers: { [string]: any } = {}
	local function group(key: string): Frame
		local made = HudParts.frame(scroll, key)
		made.ZIndex = 2
		groups[key] = made
		headers[key] = GrandOpeningCard.header(made, W.Headers[key] or key)
		return made
	end
	local daily = FreeDaily.new(group("Daily"), ctx)
	local playtime = FreePlaytime.new(group("Playtime"), ctx)
	local track = FreeTrack.new(group("Track"))
	local social = FreeSocial.new(group("Group"), ctx)
	local sections: { [string]: any } =
		{ Daily = daily, Playtime = playtime, Track = track, Group = social }

	local jumps: { JumpRail.Group } = {}
	for _, jump in JUMPS do
		table.insert(
			jumps,
			{ key = jump.Key, text = W.Jump[jump.Key] or jump.Key, icon = jump.Icon }
		)
	end
	local rail = JumpRail.new({
		frame = frame,
		scroll = scroll,
		groups = jumps,
		badge = W.Badge,
		badgeShare = F.BadgeShare,
		action = "8ballFreeRewardJump",
		root = function(key: string): GuiObject?
			return groups[key]
		end,
	})

	-- The lively frame's open (Config.UI.FreeReward.Open).
	local stage = frame.stage
	if stage then
		local function keep(handle: UIAnim.Handle)
			frame:idle(handle)
		end
		rail:register(stage)
		for _, jump in JUMPS do
			local key = jump.Key
			stage:add(key .. "Head", headers[key].word)
			stage:add(key .. "Lines", headers[key].lines)
			sections[key]:register(stage, keep)
		end
	end

	-- Lay the page out: each section under its header, one scale k for the whole page.
	local function layout()
		local g = geo
		if not frame:isOpen() or g == nil then
			return
		end
		local width = rail:layout(g)
		scroll.Size = UDim2.fromOffset(width, g.content.Y)
		local pageW = width - scroll.ScrollBarThickness
		local k = pageW / UNITS
		local headH = GrandOpeningCard.headerHeight(k)
		local gap = round(F.GapUnits * k)
		local y = 0
		for _, jump in JUMPS do
			local key = jump.Key
			rail.tops[key] = y
			GrandOpeningCard.layoutHeader(headers[key], round(pageW / 2), round(headH / 2), k)
			local h = headH + round(F.HeaderGapUnits * k)
			h += sections[key]:layout(pageW, k, h)
			groups[key].Position = UDim2.fromOffset(0, y)
			groups[key].Size = UDim2.fromOffset(pageW, h)
			y += h + gap
		end
		-- Room under the last section so it can scroll up to its header.
		ShopParts.setCanvas(scroll, math.max(y, rail.tops.Group + g.content.Y))
		-- Opened on a section: a layout soon after the open jumps there again.
		local on = openedOn
		if on and os.clock() - openedAt <= P.JumpSettleSeconds then
			rail:scrollTo(on, true)
		end
		rail:relaid(pageW)
	end

	-- Draw everything from the latest state, and the jump buttons' "!".
	refresh = function()
		placeholder.Visible = type(state) ~= "table"
		scroll.Visible = type(state) == "table"
		for _, section in sections do
			section:refresh(state)
		end
		for _, jump in JUMPS do
			local section = sections[jump.Key]
			rail:setBadge(jump.Key, section.claimable ~= nil and section:claimable())
		end
	end

	-- The first button a gamepad should land on: a Claim, else nothing.
	local function primary(): GuiObject?
		return daily:primary() or playtime:primary() or social:primary()
	end

	-- A claim button that was just switched off hands a gamepad's selection to the next Claim,
	-- else to the lit jump button.
	keepSelection = function()
		if not frame:isOpen() or not ShopParts.gamepad() or #frame.dialogs > 0 then
			return
		end
		local selected = GuiService.SelectedObject
		if
			selected
			and selected:IsDescendantOf(frame.root)
			and (not selected.Selectable or not selected.Visible)
		then
			local target = primary() or ShopParts.firstSelectable(rail:buttons() :: any)
			if target then
				GuiService.SelectedObject = target
			else
				frame:focus()
			end
		end
	end

	-- Opened with no section: the first with something to claim, else Daily.
	local function bestSection(): string
		for _, jump in JUMPS do
			local section = sections[jump.Key]
			if section.claimable ~= nil and section:claimable() then
				return jump.Key
			end
		end
		return JUMPS[1].Key
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
	end
	-- The panel is as tall as the Daily section; the next header peeks in under it.
	frame.fitHeight = function(width: number, panelW: number): number
		local pageW = width - (if rail:outside(panelW) then 0 else rail:room(nil))
		local k = (pageW - scroll.ScrollBarThickness) / UNITS
		return GrandOpeningCard.headerHeight(k)
			+ round(F.HeaderGapUnits * k)
			+ FreeDaily.heightFor(k)
			+ round(F.GapUnits * k)
			+ P.PeekPx
	end
	frame.onOpen = function()
		daily:setOpen(true)
		playtime:setOpen(true)
		refresh()
		rail:opened()
		if not ticker then
			ticker = RunService.Heartbeat:Connect(function()
				local clock = os.clock()
				if clock < nextTick then
					return
				end
				nextTick = clock + F.TickSeconds
				local now = workspace:GetServerTimeNow()
				daily:tick(now)
				playtime:tick(now)
				rail:setBadge("Playtime", playtime:claimable())
			end)
		end
		if ShopParts.gamepad() then
			local target = primary()
			if target then
				GuiService.SelectedObject = target
			end
		end
	end
	frame.onClose = function()
		rail:closed()
		daily:setOpen(false)
		playtime:setOpen(false)
		social:closed()
		ShopOdds.closeAll()
		openedOn = nil
		if ticker then
			ticker:Disconnect()
			ticker = nil
		end
	end

	-- Drawn even while closed: the open reads every piece's look as it starts.
	ItemState.Changed.Rewards:Connect(function(payload: any)
		state = payload
		version += 1
		refresh()
		keepSelection()
	end)
	-- Claim All's live price.
	ItemState.Changed.Shop:Connect(function()
		if frame:isOpen() then
			daily:refresh(state)
		end
	end)

	refresh()

	local handle: Menus.Handle = {
		open = function(tab: string?)
			if not frame:isOpen() then
				state = ItemState.rewards()
				refresh()
			end
			frame:open()
			local key = if tab and rail:has(tab) then tab else bestSection()
			openedOn, openedAt = key, os.clock()
			rail:jump(key, true)
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
		notice = function(text: string, toneName: string?)
			ctx.notice(text, toneName)
		end,
	}
	Menus.register(NAME, handle)
	return handle
end

return FreeRewardMenu
