--!strict
-- Purchased: what a Robux purchase feels like (the designer, 2026-10-08: "a satisfying thank
-- you for your purchase in big text ... and like a impact frame/vfx effects ... whenever you
-- buy anything you should see it go to your account"; 2026-10-09: "it should look roughly like
-- this", one big line "Thank you! +x" at the top of the screen, Fredoka, "colored variants
-- letters", and a flash over the whole screen, yellow or green).
--
-- The server's PurchaseDone (Net) says what landed. Then: the whole screen flashes (gold for a
-- Robux item, green for a money pack), one big line slams in near the top, "Thank you! +5
-- Mystery Lucky Blocks" ("+VIP", "+$250,000", "+Ability Slot 2"), each letter its own colour
-- (Config.UI.Purchased.Letters, round and round) in the kit's straight title (ArchTitle: the
-- navy outline), and what was bought flies to where it lives: money to the money HUD
-- (counting up as it lands), lucky blocks to the hotbar, ability spins to Abilities
-- (RewardsFlyer). A money pack plays the slot machine's payout, every other Robux item the
-- achievement chime. VIP also slams its perks card in over the VIP tag (VipTag.showPerks). A
-- gift: the giver is thanked ("Thank you! Gift sent to Sam!"), the receiver sees the item fly
-- in with no thank-you. Money bought with in-game money gets no thank-you: only the flight
-- and the cue-equip sound (flow, from ShopMenu).
--
-- Roblox's own "purchase succeeded" box covers the screen after a purchase, and the receipt
-- usually lands while it is still up (the designer never saw the first thank-you): a thank-you
-- waits for Roblox's prompt to close (MarketplaceService's Prompt...PurchaseFinished on this
-- client), or plays at once when it closed a moment ago, or after PromptWaitSeconds when no
-- prompt was seen (a dev grant).
--
-- Everything sits in its own ScreenGui over the menus. Purely visual: the server already put
-- the purchase in the save. Sizes in Config.UI.Purchased, words in Strings.Purchased.
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local ArchTitle = require(script.Parent.ArchTitle)
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local U = Config.UI.Purchased
local COPY = Strings.Purchased
local SHOP: { [string]: any } = Strings.Menus.Shop :: any
local LIST: { [string]: any } = Config.Products.List :: any
local DIM = Config.UI.Progress.Roadmap -- a menu's ScreenGui sits DisplayOrderAbove the HUD's

local Purchased = {}
Purchased.__index = Purchased

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- What was bought, after "Thank you!": the item by name ("+VIP") where it has one, else what
-- it gave ("+$250,000", "+5 Mystery Lucky Blocks").
local function itemText(message: { [string]: any }): string
	local key = message.key
	local names: { [string]: string } = SHOP.Passes.Names
	if message.vip == true then
		return string.format(COPY.Named, COPY.Vip)
	elseif key == "StarterPack" then
		return string.format(COPY.Named, SHOP.Blocks.StarterName)
	elseif names[key] then
		return string.format(COPY.Named, names[key])
	elseif message.party == true then
		return string.format(COPY.Named, names.MoneyParty or COPY.Party)
	elseif message.claimAll == true then
		return COPY.ClaimAll
	elseif message.skip == true then
		return COPY.Skip
	end
	return RewardsParts.gains(RewardsParts.reward(message))
end

-- A money pack (Config.Products.List: its Money): the slot machine and the green flash.
local function isMoneyPack(message: { [string]: any }): boolean
	local row = LIST[message.key]
	return row ~= nil and row.Money ~= nil
end

-- Each letter its own colour, round the palette; spaces take none.
local function letterTints(text: string): { [number]: Color3 }
	local tints: { [number]: Color3 } = {}
	local palette: { { number } } = U.Letters :: any
	local at = 0
	local index = 0
	for _, code in utf8.codes(text) do
		index += 1
		if code ~= 32 then
			tints[index] = rgb(palette[at % #palette + 1])
			at += 1
		end
	end
	return tints
end

--- Build it (closed) over `screen` (the HUD's ScreenGui) with Progression's `deps` (money,
--- column, hotbarCenter, vipTag), and listen for purchases.
function Purchased.new(screen: ScreenGui, deps: any): any
	local self: any = setmetatable({}, Purchased)
	self.deps = deps
	self.flyer = RewardsFlyer.new(screen, deps)
	self.token = 0
	self.pending = {} :: { { [string]: any } } -- thank-yous waiting for Roblox's box to close
	self.closedAt = -math.huge -- os.clock() when a Roblox purchase prompt last closed

	local gui = Instance.new("ScreenGui")
	gui.Name = "Purchased"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + DIM.DisplayOrderAbove + U.DisplayOrderAbove
	gui.Parent = screen.Parent
	self.gui = gui

	-- The flash over the whole screen (its colour per purchase).
	local flash = HudParts.frame(gui, "Flash")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 1
	self.flash = flash

	-- The line's holder: it slams in and out; its letters are built again for each purchase.
	local line = HudParts.frame(gui, "Thanks")
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Visible = false
	line.ZIndex = 3
	self.line = line

	Net.get("PurchaseDone").OnClientEvent:Connect(function(message: any)
		if type(message) == "table" then
			self:arrive(message)
		end
	end)
	-- Roblox's purchase box closed: a thank-you waiting for it plays now.
	local function closed()
		self.closedAt = os.clock()
		self:flush()
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(closed)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(closed)
	-- Studio only: GuiQA:Invoke("purchased", message) plays one at once, as if the server sent it.
	GuiQA.add("purchased", function(message: any)
		if type(message) == "table" then
			self:show(message)
		end
		return true
	end)
	return self
end

-- Where things fly from: the line's middle.
function Purchased.centre(self: any): Vector2
	local size = self.gui.AbsoluteSize
	return Vector2.new(size.X / 2, size.Y * U.CentreShare)
end

--- Fly what was bought to where it lives (money, blocks, spins), from `from` (absolute
--- pixels; nil: the line's middle), with `sound` (default the cue-equip sound; false: none).
--- A money purchase's only effect.
function Purchased.flow(self: any, reward: any, from: Vector2?, sound: (string | boolean)?)
	if sound ~= false then
		UISound.play(if type(sound) == "string" then sound else "Equip")
	end
	self.flyer:reward(reward, from or self.centre(self))
end

-- A purchase from the server: now if Roblox's box closed a moment ago (or for a gift to us,
-- which had no box here), else once it closes, at most PromptWaitSeconds later.
function Purchased.arrive(self: any, message: { [string]: any })
	if type(message.from) == "string" or os.clock() - self.closedAt <= U.RecentCloseSeconds then
		self:show(message)
		return
	end
	table.insert(self.pending, message)
	task.delay(U.PromptWaitSeconds, function()
		local index = table.find(self.pending, message)
		if index then
			table.remove(self.pending, index)
			self:show(message)
		end
	end)
end

-- Play every thank-you that was waiting.
function Purchased.flush(self: any)
	local waiting = self.pending
	self.pending = {}
	for _, message in waiting do
		self:show(message)
	end
end

-- The words in their letters at `px`, smaller until they fit `maxW`. Returns the holder's size.
function Purchased.build(self: any, text: string, px: number, maxW: number): Vector2
	local line: Frame = self.line
	local tints = letterTints(text)
	local size = px
	local made: ArchTitle.Title? = nil
	for _ = 1, 3 do
		for _, child in line:GetChildren() do
			if not child:IsA("UIScale") then
				child:Destroy()
			end
		end
		made = ArchTitle.new(line, text, U.TitleStyle, size, tints)
		local width = (made :: ArchTitle.Title).width
		if width <= maxW or size <= U.MinPx then
			break
		end
		size = math.max(U.MinPx, math.floor(size * maxW / width))
	end
	local title = made :: ArchTitle.Title
	title.root.AnchorPoint = Vector2.new(0.5, 0.5)
	title.root.Position = UDim2.fromScale(0.5, 0.5)
	return Vector2.new(title.width, title.height)
end

-- The impact: the flash in `tint`, then the line slamming in; gone after HoldSeconds.
function Purchased.thank(self: any, words: string, tint: { number })
	self.token += 1
	local token = self.token
	if not UIAnim.reduced() then
		self.flash.BackgroundColor3 = rgb(tint)
		self.flash.BackgroundTransparency = U.FlashFrom
		TweenService:Create(
			self.flash,
			TweenInfo.new(U.FlashSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1 }
		):Play()
	end
	local screen = self.gui.AbsoluteSize
	local short = screen.Y < Config.Multiplayer.Style.ShortHeight
	local px = if short then U.ShortThanksPx else U.ThanksPx
	local text = if words ~= "" then string.format(COPY.Line, words) else COPY.Thanks
	local size = self:build(text, px, screen.X * U.WidthShare)
	self.line.Size = UDim2.fromOffset(size.X, size.Y)
	self.line.Position = UDim2.fromOffset(screen.X / 2, screen.Y * U.CentreShare)
	UIAnim.slam(self.line, nil, { shake = "Jolt" })
	task.delay(U.HoldSeconds, function()
		if self.token == token then
			UIAnim.popOut(self.line)
		end
	end)
end

--- One purchase, shown now (see Net PurchaseDone).
function Purchased.show(self: any, message: { [string]: any })
	local reward = RewardsParts.reward(message)
	if type(message.from) == "string" then
		-- A gift to us: it flies in, no thank-you.
		self:flow(reward)
		return
	end
	local money = isMoneyPack(message)
	local sound = if money then "MoneyPayout" else "RobuxThanks"
	local tint = if money then U.FlashMoney else U.FlashRobux
	local words = itemText(message)
	UISound.play(sound)
	if type(message.to) == "string" then
		self:thank(string.format(COPY.GiftSent, message.to), tint)
		return -- it went to them: nothing flies here
	end
	self:thank(words, tint)
	task.delay(U.FlowAfterSeconds, function()
		if reward.money > 0 or #reward.blocks > 0 or reward.spins > 0 then
			self:flow(reward, nil, false)
		end
		local tag = self.deps and self.deps.vipTag
		if message.vip == true and tag then
			tag:showPerks()
		end
	end)
end

return Purchased
