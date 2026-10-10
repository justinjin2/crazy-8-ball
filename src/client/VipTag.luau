--!strict
-- VipTag: a small VIP tag over the money pill, bottom left, for a VIP only (the designer,
-- 2026-10-08: "add a VIP tag above their money or something that is animated and when
-- hovering/clicking on it tells the benefits/perks activated"). A navy pill with a gold rim:
-- the crown rocking gently and "VIP" in the house rainbow (the chat tag's, UIAnim.rainbow).
-- Hovering shows the perks card over it ("VIP perks active" and a ticked line per perk); a click
-- or tap pins it open for PinSeconds (a second press closes it). Bought VIP just now: the card
-- slams in by itself (showPerks, the purchase thank-you), so a new VIP sees what they got.
--
-- It lives inside the money HUD's root (it moves with it); MenuColumn measures the money HUD's
-- top from this tag while it shows. VIP is the player's `Vip` attribute (the Store sets it);
-- where paid random items are restricted the daily block's line says money (ItemState's shop
-- state). Sizes in Config.UI.VipTag, words in Strings.VipTag and Strings.Menus.Shop.Blocks.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local V = Config.UI.VipTag
local COPY = Strings.VipTag
local BLOCKS: { [string]: any } = (Strings.Menus.Shop :: any).Blocks

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local VipTag = {}
VipTag.__index = VipTag

-- The perks, top to bottom: the Shop's list, the daily block's line as money where paid random
-- items are restricted.
local function perkLines(): { string }
	local lines = table.clone(BLOCKS.VipPerks :: { string })
	local state = ItemState.shop()
	if type(state) == "table" and state.restricted == true then
		lines[V.RestrictedLine] = BLOCKS.VipPerkRestricted
	end
	return lines
end

--- Build the tag (hidden) in `money`'s root (the MoneyHud).
function VipTag.new(money: any): any
	local self: any = setmetatable({}, VipTag)
	self.money = money
	self.loops = {} :: { UIAnim.Handle }
	self.pinToken = 0
	self.hovered = false
	self.pinned = false
	self.on = false

	local tag = Instance.new("TextButton")
	tag.Name = "VipTag"
	tag.Text = ""
	tag.Selectable = false -- a lobby button is never a gamepad stop (it takes the stick)
	tag.AutoButtonColor = false
	tag.BorderSizePixel = 0
	tag.BackgroundColor3 = rgb(V.Color)
	tag.AnchorPoint = Vector2.new(0, 1)
	tag.Visible = false
	tag.ZIndex = V.ZIndex
	tag.Parent = money.root
	HudParts.corner(tag, 99)
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = rgb(V.Rim)
	rim.Thickness = V.RimPx
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = tag
	self.tag = tag
	local crown = HudParts.icon(tag, "Crown", "Crown")
	crown.AnchorPoint = Vector2.new(0.5, 0.5)
	crown.ZIndex = V.ZIndex + 1
	self.crown = crown
	local word = HudParts.text(tag, "Word", V.TextPx, COPY.Word)
	word.TextWrapped = false
	word.AnchorPoint = Vector2.new(0, 0.5)
	word.ZIndex = V.ZIndex + 1
	self.word = word

	-- The perks card over the tag.
	local card = HudParts.popupCard(tag, "Perks", V.Card.CornerPx)
	card.AnchorPoint = Vector2.new(0, 1)
	card.Visible = false
	card.ZIndex = V.ZIndex + 2
	self.card = card
	local title = HudParts.text(card, "Title", V.Card.TitlePx, COPY.Title, rgb(V.Card.TitleColor))
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = V.ZIndex + 3
	self.title = title
	self.rows = {} :: { { check: ImageLabel, words: TextLabel } }
	for index in BLOCKS.VipPerks :: { string } do
		local check = HudParts.icon(card, "Check", "Check" .. index)
		check.ZIndex = V.ZIndex + 3
		local words = HudParts.note(card, "Perk" .. index, V.Card.TextPx, "")
		words.TextWrapped = false
		words.TextXAlignment = Enum.TextXAlignment.Left
		words.ZIndex = V.ZIndex + 3
		table.insert(self.rows, { check = check, words = words })
	end

	tag.MouseEnter:Connect(function()
		self.hovered = true
		self:showCard(false)
	end)
	tag.MouseLeave:Connect(function()
		self.hovered = false
		if not self.pinned then
			self:hideCard()
		end
	end)
	tag.Activated:Connect(function()
		UISound.play("Click")
		if self.pinned then
			self.pinned = false
			self:hideCard()
		else
			self:pin(V.PinSeconds)
		end
	end)

	local player = Players.LocalPlayer
	if player then
		player:GetAttributeChangedSignal("Vip"):Connect(function()
			self:refresh()
		end)
	end
	money.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	self:layout()
	self:refresh()
	return self
end

-- The screen is short (a phone on its side): the smaller sizes.
function VipTag.short(self: any): boolean
	local screen = self.money.screen
	return screen ~= nil and screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
end

function VipTag.layout(self: any)
	local short = self:short()
	local h = if short then V.ShortHeightPx else V.HeightPx
	local textPx = if short then V.ShortTextPx else V.TextPx
	local crownPx = math.floor(h * V.CrownShare)
	HudParts.setTextSize(self.word, textPx)
	local wordW = math.ceil(ShopParts.textWidth(COPY.Word, textPx)) + 4
	local w = V.PadPx + crownPx + V.InnerGapPx + wordW + V.PadPx
	self.tag.Position = UDim2.fromOffset(V.LeftPx, -V.GapPx)
	self.tag.Size = UDim2.fromOffset(w, h)
	HudParts.setMinHit(self.tag, Config.UI.Menu.Frame.TouchMinPx)
	self.crown.Position = UDim2.new(0, V.PadPx + crownPx / 2, 0.5, 0)
	self.crown.Size = UDim2.fromOffset(crownPx, crownPx)
	self.word.Position = UDim2.new(0, V.PadPx + crownPx + V.InnerGapPx, 0.5, 0)
	self.word.Size = UDim2.fromOffset(wordW, h)

	-- The card: the title, then a ticked row per perk, as wide as its widest words.
	local C = V.Card
	local widest = ShopParts.textWidth(COPY.Title, C.TitlePx)
	for _, row in self.rows do
		widest =
			math.max(widest, C.CheckPx + C.GapPx + ShopParts.textWidth(row.words.Text, C.TextPx))
	end
	local cardW = math.ceil(widest) + 2 * C.PadPx + 4
	local y = C.PadPx
	self.title.Position = UDim2.fromOffset(C.PadPx, y)
	self.title.Size = UDim2.fromOffset(cardW - 2 * C.PadPx, C.TitlePx + 4)
	y += C.TitlePx + 4 + C.GapPx
	for _, row in self.rows do
		row.check.Position = UDim2.fromOffset(C.PadPx, y + (C.RowPx - C.CheckPx) / 2)
		row.check.Size = UDim2.fromOffset(C.CheckPx, C.CheckPx)
		row.words.Position = UDim2.fromOffset(C.PadPx + C.CheckPx + C.GapPx, y)
		row.words.Size = UDim2.fromOffset(cardW - 2 * C.PadPx - C.CheckPx - C.GapPx, C.RowPx)
		y += C.RowPx
	end
	self.card.Position = UDim2.fromOffset(0, -C.AbovePx)
	self.card.Size = UDim2.fromOffset(cardW, y + C.PadPx)
end

--- Show or hide the tag with the `Vip` attribute.
function VipTag.refresh(self: any)
	local player = Players.LocalPlayer
	local on = player ~= nil and player:GetAttribute("Vip") == true
	if on == self.on then
		return
	end
	self.on = on
	if on then
		UIAnim.popIn(self.tag)
		self:startLoops()
	else
		self:stopLoops()
		self.pinned = false
		self.card.Visible = false
		UIAnim.popOut(self.tag)
	end
	self:layout()
end

--- The tag's top edge in screen pixels while it shows (MenuColumn keeps above it), else nil.
function VipTag.top(self: any): number?
	if self.on and self.tag.Visible and self.tag.AbsoluteSize.Y > 0 then
		return self.tag.AbsolutePosition.Y
	end
	return nil
end

-- The crown rocks; "VIP" flows through the rainbow (Reduce Motion: still colours).
function VipTag.startLoops(self: any)
	self:stopLoops()
	local R = V.CrownRock
	table.insert(self.loops, UIAnim.turn(self.crown, 0, R[1], R[2]))
	if not UIAnim.reduced() then
		table.insert(self.loops, UIAnim.rainbow(self.word))
	end
end

function VipTag.stopLoops(self: any)
	for _, handle in self.loops :: { UIAnim.Handle } do
		handle.stop()
	end
	table.clear(self.loops)
end

-- The perks card in: popped for a hover, slammed when `big` (a purchase).
function VipTag.showCard(self: any, big: boolean)
	if not self.on then
		return
	end
	for index, text in perkLines() do
		local row = self.rows[index]
		if row then
			row.words.Text = text
		end
	end
	self:layout()
	if big then
		UIAnim.slam(self.card, nil, { burst = false, shake = "Nudge" })
	elseif not self.card.Visible then
		UIAnim.popIn(self.card)
	end
end

function VipTag.hideCard(self: any)
	if self.card.Visible then
		UIAnim.popOut(self.card)
	end
end

-- Open the card for `seconds`, then close it unless the pointer is on the tag.
function VipTag.pin(self: any, seconds: number, big: boolean?)
	self.pinned = true
	self.pinToken += 1
	local token = self.pinToken
	self:showCard(big == true)
	task.delay(seconds, function()
		if self.pinToken == token and self.pinned then
			self.pinned = false
			if not self.hovered then
				self:hideCard()
			end
		end
	end)
end

--- VIP was just bought: the tag shows at once and the perks card slams in for a while.
function VipTag.showPerks(self: any)
	self:refresh()
	if not self.on then
		-- The attribute may land a moment after the purchase's message.
		self.on = true
		UIAnim.popIn(self.tag)
		self:startLoops()
	end
	self:pin(V.PurchaseSeconds, true)
end

return VipTag
