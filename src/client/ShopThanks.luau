--!strict
-- ShopThanks: the thank-you burst after every Robux purchase (GUI lane, designer 2026-10-03,
-- C4): when a product, pass or Roblox Plus prompt ends bought, confetti bursts, the item's
-- icon slams into the middle of the screen and a big rainbow "THANK YOU!" shakes over "Enjoy
-- your VIP!", then it all pops away (Config.UI.Shop.Thanks). It only says thanks: the grant
-- itself comes from the server (ProcessReceipt) as a new ShopState.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local GuiQA = require(script.Parent.GuiQA)
local BlockIcon = require(script.Parent.BlockIcon)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local T = Config.UI.Shop.Thanks
local K = Config.UI.Kit
local ICONS: { [string]: string } = Config.UI.Shop.ProductIcons :: any
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local LIST: { [string]: { Kind: string, Id: number, Money: number? } } = Config.Products.List :: any

local ShopThanks = {}

-- Config.Products keys by their Roblox id, per kind.
local byId: { [string]: { [number]: string } } = { Pass = {}, Product = {} }
for key, row in LIST do
	if type(row.Id) == "number" and row.Id > 0 and byId[row.Kind] then
		byId[row.Kind][row.Id] = key
	end
end

local gui: ScreenGui? = nil
local playing = 0 -- the burst showing now (a newer one replaces it)
-- A gift being bought: the product key and who gets it (the burst says so instead).
local giftKey: string? = nil
local giftName: string? = nil

local function nameOf(key: string): string
	local names: { [string]: string } = COPY.Names
	if names[key] then
		return names[key]
	end
	local row = LIST[key]
	if row and type(row.Money) == "number" then
		return COPY.MoneyName
	end
	return COPY.Purchase
end

--- The next purchase of `key` is a gift for `name` (nil forgets it): its burst says "GIFT
--- SENT!" instead of thanks.
function ShopThanks.giftTo(key: string, name: string?)
	giftKey, giftName = (if name ~= nil then key else nil), name
end

--- Play the burst for a Config.Products key ("RobloxPlus" for the subscription). `words`
--- and `line` replace the thanks (a gift sent or received).
function ShopThanks.play(key: string, words: string?, lineText: string?)
	local screen = gui
	if not screen then
		return
	end
	playing += 1
	local mine = playing
	screen:ClearAllChildren()
	screen.Enabled = true
	local size = screen.AbsoluteSize
	local t = math.clamp((size.Y - 360) / (1080 - 360), 0, 1)
	local function span(pair: { number }): number
		return math.floor(pair[1] + (pair[2] - pair[1]) * t + 0.5)
	end
	local root = HudParts.frame(screen, "Burst")
	root.Size = UDim2.fromScale(1, 1)
	local iconSize = span(T.IconPx)
	local textSize = span(T.TextPx)
	-- A product that gives lucky blocks shows the block itself (turning), else its kit icon.
	local products: { [string]: any } = Config.Products.List :: any
	local row = products[key]
	local blockKind: string? = nil
	if type(row) == "table" then
		if type(row.Blocks) == "table" and type(row.Blocks.Kind) == "string" then
			blockKind = row.Blocks.Kind
		elseif type(row.Restock) == "string" then
			blockKind = row.Restock
		end
	end
	local icon: GuiObject
	if blockKind then
		icon = HudParts.frame(root, "Item")
		BlockIcon.new(icon, blockKind)
	else
		local iconKey = if key == "RobloxPlus" then "RobloxPlus" else (ICONS[key] or "CashStack")
		icon = HudParts.icon(root, iconKey, "Item")
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.36)
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	icon.ZIndex = 3
	local heart = HudParts.icon(root, "Heart", "Heart")
	heart.AnchorPoint = Vector2.new(0.5, 0.5)
	heart.Position = UDim2.new(0.5, math.floor(iconSize * 0.55), 0.36, -math.floor(iconSize * 0.4))
	heart.Size = UDim2.fromOffset(math.floor(iconSize * 0.45), math.floor(iconSize * 0.45))
	heart.ZIndex = 4
	local words = HudParts.text(root, "Thanks", textSize, words or COPY.Thanks)
	words.AnchorPoint = Vector2.new(0.5, 0)
	words.Position = UDim2.new(0.5, 0, 0.36, math.floor(iconSize * 0.55))
	words.Size = UDim2.fromOffset(math.min(size.X - 32, textSize * 9), textSize + 8)
	words.TextWrapped = false
	words.ZIndex = 3
	local line = HudParts.text(root, "Line", math.max(K.Text.Min, math.floor(textSize * 0.42)), "")
	line.Text = lineText
		or COPY.ThanksLine:format(
			if key == "RobloxPlus" then COPY.Sections.RobloxPlus else nameOf(key)
		)
	line.AnchorPoint = Vector2.new(0.5, 0)
	line.Position = UDim2.new(0.5, 0, 0.36, math.floor(iconSize * 0.55) + textSize + 12)
	line.Size =
		UDim2.fromOffset(math.min(size.X - 32, textSize * 9), math.floor(textSize * 0.5) + 6)
	line.TextWrapped = false
	line.ZIndex = 3

	UISound.play("Claim")
	UIAnim.slam(icon, HudParts.color(K.Numbers.Money))
	UIAnim.slam(words)
	line.Visible = false
	heart.Visible = false
	UIAnim.popIn(line)
	UIAnim.popIn(heart)
	local rainbow = UIAnim.rainbow(words)
	local shake = UIAnim.shake(words, "Wiggle")
	local spin = UIAnim.bob(heart)
	UIAnim.confetti(root, Vector2.new(size.X / 2, size.Y * 0.36), nil, 1.6)
	task.delay(0.35, function()
		if playing == mine then
			UIAnim.confetti(root, Vector2.new(size.X * 0.25, size.Y * 0.5), nil, 1.1)
			UIAnim.confetti(root, Vector2.new(size.X * 0.75, size.Y * 0.5), nil, 1.1)
		end
	end)
	task.delay(T.Seconds, function()
		if playing ~= mine then
			return
		end
		rainbow.stop()
		shake.stop()
		spin.stop()
		for _, object: GuiObject in { icon :: GuiObject, words, line, heart } do
			UIAnim.popOut(object)
		end
		task.delay(0.4, function()
			if playing == mine then
				screen:ClearAllChildren()
				screen.Enabled = false
			end
		end)
	end)
end

--- Listen for finished purchase prompts (once). `screen` is the HUD's ScreenGui (the burst
--- gets its own over it).
function ShopThanks.start(screen: ScreenGui)
	if gui then
		return
	end
	local burst = Instance.new("ScreenGui")
	burst.Name = "ThanksBurst"
	burst.ResetOnSpawn = false
	burst.IgnoreGuiInset = true
	burst.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	burst.DisplayOrder = screen.DisplayOrder + T.DisplayOrderAbove
	burst.Enabled = false
	burst.Parent = screen.Parent
	gui = burst
	GuiQA.add("thanks", function(key: string?)
		ShopThanks.play(key or "Vip")
		return true
	end)
	local player = Players.LocalPlayer
	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, id: number, bought: boolean)
			if bought and player and userId == player.UserId then
				local key = byId.Product[id]
				if key and giftKey == key and giftName ~= nil then
					local name = giftName
					giftKey, giftName = nil, nil
					ShopThanks.play(key, COPY.GiftSent, COPY.GiftSentLine:format(name, nameOf(key)))
				elseif key then
					ShopThanks.play(key)
				end
			end
		end
	)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(who: Player, id: number, bought: boolean)
			if bought and who == player then
				local key = byId.Pass[id]
				if key then
					ShopThanks.play(key)
				end
			end
		end
	)
	if player then
		local wasMember = player.MembershipType == Enum.MembershipType.Premium
		player:GetPropertyChangedSignal("MembershipType"):Connect(function()
			local member = player.MembershipType == Enum.MembershipType.Premium
			if member and not wasMember then
				ShopThanks.play("RobloxPlus")
			end
			wasMember = member
		end)
	end
end

return ShopThanks
