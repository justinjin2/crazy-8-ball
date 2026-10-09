--!strict
-- Purchased: what a Robux purchase feels like (the designer, 2026-10-08: "a satisfying thank
-- you for your purchase in big text just like tutorial text but in rainbow and like a impact
-- frame/vfx effects ... whenever you buy anything you should see it go to your account").
--
-- The server's PurchaseDone (Net) says what landed. Then: a white impact flash over the
-- screen, a big "THANK YOU!" in the tutorial's text (white Fredoka, the ink outline) flowing
-- through the house rainbow, slamming in with a burst and a jolt, the item under it ("VIP",
-- "+$250,000", "+10 Mystery Lucky Blocks"), the cue-equip sound, and what was bought flying to
-- where it lives: money to the money HUD (counting up as it lands), lucky blocks to the hotbar,
-- ability spins to the Abilities button (RewardsFlyer). VIP also slams its perks card in over
-- the VIP tag (VipTag.showPerks). A gift: the giver is thanked ("Gift sent to Sam!"), the
-- receiver sees the item fly in with no thank-you. Money bought with in-game money gets no
-- thank-you: only the flight and the same sound (flow, from ShopMenu).
--
-- Everything sits in its own ScreenGui over the menus. Purely visual: the server already put
-- the purchase in the save. Sizes in Config.UI.Purchased, words in Strings.Purchased.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local U = Config.UI.Purchased
local COPY = Strings.Purchased
local SHOP: { [string]: any } = Strings.Menus.Shop :: any
local DIM = Config.UI.Progress.Roadmap -- a menu's ScreenGui sits DisplayOrderAbove the HUD's

local Purchased = {}
Purchased.__index = Purchased

-- The words under THANK YOU!: the item by name where it has one, else what it gave.
local function itemText(message: { [string]: any }): string
	local key = message.key
	local names: { [string]: string } = SHOP.Passes.Names
	if message.vip == true then
		return COPY.Vip
	elseif key == "StarterPack" then
		return SHOP.Blocks.StarterName
	elseif names[key] then
		return names[key]
	elseif message.party == true then
		return names.MoneyParty or COPY.Party
	elseif message.claimAll == true then
		return COPY.ClaimAll
	elseif message.skip == true then
		return COPY.Skip
	end
	local gains = RewardsParts.gains(RewardsParts.reward(message))
	return if gains ~= "" then gains else COPY.Thanks
end

--- Build it (closed) over `screen` (the HUD's ScreenGui) with Progression's `deps` (money,
--- column, hotbarCenter, vipTag), and listen for purchases.
function Purchased.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, Purchased)
	self.deps = deps
	self.flyer = RewardsFlyer.new(screen, deps)
	self.token = 0
	self.loops = {} :: { UIAnim.Handle }

	local gui = Instance.new("ScreenGui")
	gui.Name = "Purchased"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + DIM.DisplayOrderAbove + U.DisplayOrderAbove
	gui.Parent = screen.Parent
	self.gui = gui

	-- The impact flash: the whole screen white, gone in a moment.
	local flash = HudParts.frame(gui, "Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 1
	self.flash = flash

	local thanks = HudParts.text(gui, "Thanks", U.ThanksPx, COPY.Thanks)
	thanks.TextWrapped = false
	thanks.AnchorPoint = Vector2.new(0.5, 0.5)
	thanks.Visible = false
	thanks.ZIndex = 3
	self.thanks = thanks
	local item = HudParts.text(gui, "Item", U.ItemPx, "")
	item.TextWrapped = true
	item.AnchorPoint = Vector2.new(0.5, 0)
	item.Visible = false
	item.ZIndex = 3
	self.item = item

	self:layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	Net.get("PurchaseDone").OnClientEvent:Connect(function(message: any)
		if type(message) == "table" then
			self:show(message)
		end
	end)
	-- Studio only: GuiQA:Invoke("purchased", message) plays one as if the server sent it.
	GuiQA.add("purchased", function(message: any)
		if type(message) == "table" then
			self:show(message)
		end
		return true
	end)
	return self
end

-- The words' sizes: smaller on a short screen (a phone on its side).
function Purchased.layout(self: any)
	local size = self.gui.AbsoluteSize
	if size.Y <= 0 then
		return
	end
	local short = size.Y < Config.Multiplayer.Style.ShortHeight
	local thanksPx = if short then U.ShortThanksPx else U.ThanksPx
	local itemPx = if short then U.ShortItemPx else U.ItemPx
	HudParts.setTextSize(self.thanks, thanksPx)
	HudParts.setTextSize(self.item, itemPx)
	local y = size.Y * U.CentreShare
	self.thanks.Position = UDim2.fromOffset(size.X / 2, y)
	self.thanks.Size = UDim2.fromOffset(size.X * U.WidthShare, thanksPx * 1.3)
	self.item.Position = UDim2.fromOffset(size.X / 2, y + thanksPx * 0.65 + U.GapPx)
	self.item.Size = UDim2.fromOffset(size.X * U.WidthShare, itemPx * 2.6)
end

-- Where things fly from: under the words, the screen's middle.
function Purchased.centre(self: any): Vector2
	local size = self.gui.AbsoluteSize
	return Vector2.new(size.X / 2, size.Y * U.CentreShare)
end

--- Fly what was bought to where it lives (money, blocks, spins), from `from` (absolute
--- pixels; nil: the screen's middle), with the cue-equip sound. A money purchase's only effect.
function Purchased.flow(self: any, reward: any, from: Vector2?)
	UISound.play("Equip")
	self.flyer:reward(reward, from or self.centre(self))
end

-- The impact: the flash, then THANK YOU! slamming in through the rainbow, the item popping
-- under it; both gone after HoldSeconds.
function Purchased.thank(self: any, words: string)
	self.token += 1
	local token = self.token
	for _, handle in self.loops :: { UIAnim.Handle } do
		handle.stop()
	end
	table.clear(self.loops)
	if not UIAnim.reduced() then
		self.flash.BackgroundTransparency = U.FlashFrom
		TweenService:Create(
			self.flash,
			TweenInfo.new(U.FlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end
	self:layout()
	self.item.Text = words
	self.item.Visible = false
	UIAnim.slam(self.thanks, nil, { shake = "Jolt" })
	table.insert(self.loops, UIAnim.rainbow(self.thanks))
	task.delay(U.ItemAfterSeconds, function()
		if self.token == token then
			UIAnim.popIn(self.item)
		end
	end)
	task.delay(U.HoldSeconds, function()
		if self.token == token then
			UIAnim.popOut(self.thanks)
			UIAnim.popOut(self.item)
			task.delay(Config.UI.Motion.PopSeconds, function()
				if self.token == token then
					for _, handle in self.loops :: { UIAnim.Handle } do
						handle.stop()
					end
					table.clear(self.loops)
				end
			end)
		end
	end)
end

--- One purchase from the server (see Net PurchaseDone).
function Purchased.show(self: any, message: { [string]: any })
	local reward = RewardsParts.reward(message)
	if type(message.from) == "string" then
		-- A gift to us: it flies in, no thank-you.
		self:flow(reward)
		return
	end
	local words = itemText(message)
	if type(message.to) == "string" then
		self:thank(string.format(COPY.GiftSent, message.to, words))
		UISound.play("Equip")
		return -- it went to them: nothing flies here
	end
	self:thank(words)
	task.delay(U.FlowAfterSeconds, function()
		if reward.money > 0 or #reward.blocks > 0 or reward.spins > 0 then
			self:flow(reward)
		else
			UISound.play("Equip")
		end
		local tag = self.deps and self.deps.vipTag
		if message.vip == true and tag then
			tag:showPerks()
		end
	end)
end

return Purchased
