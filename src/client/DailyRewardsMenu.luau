--!strict
-- DailyRewardsMenu: the Daily Rewards popup (the designer's mock "daily A", 2026-10-08; as a
-- popup of its own, 2026-10-09: "wheres the daily calendar popup"). The lively frame
-- (MenuFrame: the panel unrolls, "Daily Rewards" by the calendar, the red X, the 8-ball flair)
-- round the login row's seven days and Claim All: FreeDaily, the same section the Free Reward
-- menu shows under "- DAILY -", where the row lives day to day. The tutorial's soft part opens
-- it once, day 1 to claim and day 7's prize on show (TutorialSoft). Claims go as the Free
-- Reward menu's: RewardRequest through ItemState, what a claim gave flying out of its button
-- (RewardsFlyer), a refusal as a notice; Claim All is a Robux product. Gamepad: opening lands
-- on today's Claim!; B closes the Odds & Details, then the popup. Its open in
-- Config.UI.DailyRewards.Open, the section's sizes in Config.UI.FreeReward.Daily, words in
-- Strings.FreeReward.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local FreeDaily = require(script.Parent.FreeDaily)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local OddsDetails = require(script.Parent.OddsDetails)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local ShopMysteryOdds = require(script.Parent.ShopMysteryOdds)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local NAME = "DailyRewards"
local F = Config.UI.FreeReward
local UNITS = Config.UI.GrandOpeningCard.Layout.Card[1] -- the section's width in units
local W = Strings.FreeReward

local DailyRewardsMenu = {}

--- Build the popup (closed) and register it with Menus. `deps`: Progression's shared table
--- (the rewards flyer is shared with the Free Reward menu).
function DailyRewardsMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local frame = MenuFrame.new(screen, {
		name = NAME,
		title = Strings.Menus.Titles.DailyRewards,
		icon = "Calendar",
		money = false,
	})
	local flyer = deps.rewardsFlyer or RewardsFlyer.new(screen, deps)
	deps.rewardsFlyer = flyer
	local page = frame:page()
	local placeholder = MenuFrame.placeholder(page)
	local holder = HudParts.frame(page, "Daily")
	holder.ZIndex = 2
	local geo: MenuFrame.Geo? = nil
	local state: any = ItemState.rewards()
	local ticker: RBXScriptConnection? = nil
	local nextTick = 0
	-- Requests on their way, and claims answered but not yet seen in a state, by key.
	local inFlight: { [string]: boolean? } = {}
	local claimedAt: { [string]: number } = {}
	local version = 0
	local daily: any
	local ctx: any = {}

	local odds = OddsDetails.new(frame)
	ShopMysteryOdds.new(odds)
	function ctx.odds(kind: string)
		odds:block(kind)
	end
	function ctx.busy(key: string): boolean
		return inFlight[key] == true or claimedAt[key] == version
	end
	function ctx.notice(text: string, toneName: string?)
		if frame:isOpen() then
			frame:notice(text, toneName)
		end
	end
	local function refresh()
		placeholder.Visible = type(state) ~= "table"
		holder.Visible = type(state) == "table"
		daily:refresh(state)
	end
	-- After a claim: a gamepad's selection goes to the next Claim!, else the X.
	local function keepSelection()
		if not frame:isOpen() or not ShopParts.gamepad() or #frame.dialogs > 0 then
			return
		end
		local selected = GuiService.SelectedObject
		if selected and selected:IsDescendantOf(frame.root) and not selected.Selectable then
			local target = daily:primary()
			if target then
				GuiService.SelectedObject = target
			else
				frame:focus()
			end
		end
	end
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
				flyer:reward(reply, button.AbsolutePosition + button.AbsoluteSize / 2)
			else
				ctx.notice(MenuFrame.reason(reply), "Red")
			end
			refresh()
			keepSelection()
		end)
	end
	-- Claim All: the server checks it and shows Roblox's dialog ("Coming soon" until on sale).
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
		if inFlight.ClaimAll then
			return
		end
		inFlight.ClaimAll = true
		UISound.play("Click")
		refresh()
		task.spawn(function()
			local reply = ItemState.request("StoreRequest", "Buy", product)
			inFlight.ClaimAll = nil
			if not (type(reply) == "table" and reply.ok) then
				ctx.notice(MenuFrame.reason(reply), "Red")
			end
			refresh()
		end)
	end
	daily = FreeDaily.new(holder, ctx)

	local stage = frame.stage
	if stage then
		daily:register(stage, function(handle: UIAnim.Handle)
			frame:idle(handle)
		end)
	end

	local function layout()
		local g = geo
		if not frame:isOpen() or g == nil then
			return
		end
		local k = g.content.X / UNITS
		local height = daily:layout(g.content.X, k, 0)
		holder.Size = UDim2.fromOffset(g.content.X, height)
		holder.Position = UDim2.fromOffset(0, math.max(0, math.floor((g.content.Y - height) / 2)))
	end
	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
		odds:layout(g)
	end
	-- Just as tall as the section, with a little room under it.
	frame.fitHeight = function(width: number): number
		return FreeDaily.heightFor(width / UNITS) + Config.UI.DailyRewards.FootPx
	end
	frame.onOpen = function()
		daily:setOpen(true)
		refresh()
		if not ticker then
			ticker = RunService.Heartbeat:Connect(function()
				local clock = os.clock()
				if clock < nextTick then
					return
				end
				nextTick = clock + F.TickSeconds
				daily:tick(workspace:GetServerTimeNow())
			end)
		end
		if ShopParts.gamepad() then
			local target = daily:primary()
			if target then
				GuiService.SelectedObject = target
			end
		end
	end
	frame.onClose = function()
		daily:setOpen(false)
		odds:close()
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
	ItemState.Changed.Shop:Connect(function()
		if frame:isOpen() then
			daily:refresh(state)
			odds:refresh()
		end
	end)
	refresh()

	local handle: Menus.Handle = {
		open = function()
			if not frame:isOpen() then
				state = ItemState.rewards()
				refresh()
			end
			frame:open()
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

return DailyRewardsMenu
