--!strict
-- LuckClover: the Grand Opening Luck's clover (economy v5 plan 3.4; the designer: "some clover
-- next to the money/VIP bars in the bottom left; clicking on it says extra luck for release"),
-- for everyone, only while the luck runs (BlockDrop.luckLive). A small navy badge with a green
-- rim over the money pill, right of the VIP tag (in the VIP tag's place for a player without
-- VIP), the four-leaf clover in it rocking gently. Hovering shows its card over it ("Extra luck
-- for the release!", each boosted step: "Rare to Epic: 27% instead of 18%", and the countdown);
-- a click or tap pins it open for PinSeconds (a second press closes it). The luck is the same
-- for everyone and the server reads the same clock, so it asks nothing.
--
-- It lives inside the money HUD's root, as the VIP tag does; MenuColumn keeps above it while it
-- shows. Studio only: GuiQA:Invoke("luck", startsAt?) runs the luck from `startsAt` (unix
-- seconds; nil: Config's again) on this client, and ServerStorage.LuckyBlockQA:Invoke("luck",
-- startsAt?) on the server (both, for a climb with it). Sizes in Config.UI.LuckClover, words in
-- Strings.LuckClover.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.LuckClover
local V = Config.UI.VipTag
local CLIMB = Config.BlockOdds.Climb
local COPY = Strings.LuckClover
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Config's own start of the luck's deal, for the Studio hook to go back to.
local configStartsAt: number = (Config.Shop.Deals :: any)[CLIMB.Luck.With].StartsAt

-- Each boosted step, bottom first: "Rare to Epic: 27% instead of 18%".
local function stepLines(): { string }
	local lines = {}
	local tiers: { string } = CLIMB.Tiers :: any
	for i, tier in tiers do
		local next = tiers[i + 1]
		if next and (CLIMB.Luck.Steps :: any)[tier] ~= nil then
			local with = BlockDrop.stepParts(tier, true) / Config.BlockOdds.OddsTotal * 100
			local without = BlockDrop.stepParts(tier, false) / Config.BlockOdds.OddsTotal * 100
			table.insert(
				lines,
				COPY.Step:format(
					SHORT[tier] or tier,
					SHORT[next] or next,
					BlockOdds.percentText(with),
					BlockOdds.percentText(without)
				)
			)
		end
	end
	return lines
end

local LuckClover = {}
LuckClover.__index = LuckClover

--- Build the clover (hidden) in `money`'s root (the MoneyHud), beside `vipTag` (VipTag).
function LuckClover.new(money: any, vipTag: any): any
	local self: any = setmetatable({}, LuckClover)
	self.money = money
	self.vipTag = vipTag
	self.loop = nil :: UIAnim.Handle?
	self.pinToken = 0
	self.hovered = false
	self.pinned = false
	self.on = false

	local badge = Instance.new("TextButton")
	badge.Name = "LuckClover"
	badge.Text = ""
	badge.Selectable = false -- a lobby button is never a gamepad stop (it takes the stick)
	badge.AutoButtonColor = false
	badge.BorderSizePixel = 0
	badge.BackgroundColor3 = rgb(C.Color)
	badge.AnchorPoint = Vector2.new(0, 1)
	badge.Visible = false
	badge.ZIndex = C.ZIndex
	badge.Parent = money.root
	HudParts.corner(badge, 99)
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = rgb(C.Rim)
	rim.Thickness = C.RimPx
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = badge
	self.badge = badge
	local clover = HudParts.icon(badge, "Lucky", "Clover")
	clover.AnchorPoint = Vector2.new(0.5, 0.5)
	clover.Position = UDim2.fromScale(0.5, 0.5)
	clover.Size = UDim2.fromScale(C.IconShare, C.IconShare)
	clover.ZIndex = C.ZIndex + 1
	self.clover = clover

	-- The card over the badge: the title, a clover per boosted step, then the countdown.
	local K = C.Card
	local card = HudParts.popupCard(badge, "Luck", K.CornerPx)
	card.AnchorPoint = Vector2.new(0, 1)
	card.Visible = false
	card.ZIndex = C.ZIndex + 2
	self.card = card
	local title = HudParts.text(card, "Title", K.TitlePx, COPY.Title, rgb(K.TitleColor))
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = C.ZIndex + 3
	self.title = title
	self.rows = {} :: { { icon: ImageLabel, words: TextLabel } }
	for index, line in stepLines() do
		local icon = HudParts.icon(card, "Lucky", "Step" .. index .. "Icon")
		icon.ZIndex = C.ZIndex + 3
		local words = HudParts.note(card, "Step" .. index, K.TextPx, line)
		words.TextWrapped = false
		words.TextXAlignment = Enum.TextXAlignment.Left
		words.ZIndex = C.ZIndex + 3
		table.insert(self.rows, { icon = icon, words = words })
	end
	local ends = HudParts.note(card, "Ends", K.TextPx, "")
	ends.TextWrapped = false
	ends.TextXAlignment = Enum.TextXAlignment.Left
	ends.ZIndex = C.ZIndex + 3
	self.ends = ends

	badge.MouseEnter:Connect(function()
		self.hovered = true
		self:showCard()
	end)
	badge.MouseLeave:Connect(function()
		self.hovered = false
		if not self.pinned then
			self:hideCard()
		end
	end)
	badge.Activated:Connect(function()
		UISound.play("Click")
		if self.pinned then
			self.pinned = false
			self:hideCard()
		else
			self:pin(C.PinSeconds)
		end
	end)

	money.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	-- Beside the VIP tag while it shows: follow it in and out.
	vipTag.tag:GetPropertyChangedSignal("Visible"):Connect(function()
		self:layout()
	end)
	vipTag.tag:GetPropertyChangedSignal("Size"):Connect(function()
		self:layout()
	end)
	-- The luck starts and ends on a clock: look each PollSeconds; the countdown ticks with it.
	task.spawn(function()
		while true do
			self:refresh()
			task.wait(C.PollSeconds)
		end
	end)
	GuiQA.add("luck", function(startsAt: number?)
		(Config.Shop.Deals :: any)[CLIMB.Luck.With].StartsAt = startsAt or configStartsAt
		self:refresh()
		return self.on
	end)
	GuiQA.add("luckCard", function(open: boolean?)
		if open == false then
			self.pinned = false
			self:hideCard()
		else
			self:pin(C.PinSeconds * 10)
		end
		return self.card.Visible
	end)
	self:layout()
	return self
end

-- The screen is short (a phone on its side): the smaller sizes.
function LuckClover.short(self: any): boolean
	local screen = self.money.screen
	return screen ~= nil and screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
end

function LuckClover.layout(self: any)
	local short = self:short()
	local side = if short then V.ShortHeightPx else V.HeightPx
	-- Right of the VIP tag while it shows (as it grows in too), else in its place.
	local vip = self.vipTag
	local x = V.LeftPx
	if vip.on and vip.tag.Visible then
		x += vip.tag.Size.X.Offset + C.GapPx
	end
	self.badge.Position = UDim2.fromOffset(x, -V.GapPx)
	self.badge.Size = UDim2.fromOffset(side, side)
	HudParts.setMinHit(self.badge, Config.UI.Menu.Frame.TouchMinPx)

	-- The card: the title, a row per step, the countdown, as wide as its widest words.
	local K = C.Card
	local widest = math.max(
		ShopParts.textWidth(COPY.Title, K.TitlePx),
		ShopParts.textWidth(self.ends.Text, K.TextPx)
	)
	for _, row in self.rows do
		widest =
			math.max(widest, K.IconPx + K.GapPx + ShopParts.textWidth(row.words.Text, K.TextPx))
	end
	local cardW = math.ceil(widest) + 2 * K.PadPx + 4
	local y = K.PadPx
	self.title.Position = UDim2.fromOffset(K.PadPx, y)
	self.title.Size = UDim2.fromOffset(cardW - 2 * K.PadPx, K.TitlePx + 4)
	y += K.TitlePx + 4 + K.GapPx
	for _, row in self.rows do
		row.icon.Position = UDim2.fromOffset(K.PadPx, y + (K.RowPx - K.IconPx) / 2)
		row.icon.Size = UDim2.fromOffset(K.IconPx, K.IconPx)
		row.words.Position = UDim2.fromOffset(K.PadPx + K.IconPx + K.GapPx, y)
		row.words.Size = UDim2.fromOffset(cardW - 2 * K.PadPx - K.IconPx - K.GapPx, K.RowPx)
		y += K.RowPx
	end
	self.ends.Position = UDim2.fromOffset(K.PadPx, y + K.GapPx)
	self.ends.Size = UDim2.fromOffset(cardW - 2 * K.PadPx, K.RowPx)
	y += K.GapPx + K.RowPx
	self.card.Position = UDim2.fromOffset(0, -K.AbovePx)
	self.card.Size = UDim2.fromOffset(cardW, y + K.PadPx)
end

--- Show or hide the clover with the luck, and tick the countdown.
function LuckClover.refresh(self: any)
	local now = workspace:GetServerTimeNow()
	local on = BlockDrop.luckLive(now)
	if on then
		local _, endsAt = BlockDrop.luckWindow()
		local text = COPY.EndsIn:format(ShopParts.timeLeft(endsAt - now))
		if text ~= self.ends.Text then
			self.ends.Text = text
			self:layout()
		end
	end
	if on == self.on then
		return
	end
	self.on = on
	if on then
		self:layout()
		UIAnim.popIn(self.badge)
		local R = C.Rock
		self.loop = UIAnim.turn(self.clover, 0, R[1], R[2])
	else
		if self.loop then
			self.loop.stop()
			self.loop = nil
		end
		self.pinned = false
		self.card.Visible = false
		UIAnim.popOut(self.badge)
	end
end

-- The card in, popped (a hover or a press).
function LuckClover.showCard(self: any)
	if not self.on then
		return
	end
	self:layout()
	if not self.card.Visible then
		UIAnim.popIn(self.card)
	end
end

function LuckClover.hideCard(self: any)
	if self.card.Visible then
		UIAnim.popOut(self.card)
	end
end

-- Open the card for `seconds`, then close it unless the pointer is on the badge.
function LuckClover.pin(self: any, seconds: number)
	self.pinned = true
	self.pinToken += 1
	local token = self.pinToken
	self:showCard()
	task.delay(seconds, function()
		if self.pinToken == token and self.pinned then
			self.pinned = false
			if not self.hovered then
				self:hideCard()
			end
		end
	end)
end

--- The badge's top edge in screen pixels while it shows (MenuColumn keeps above it), else nil.
function LuckClover.top(self: any): number?
	if self.on and self.badge.Visible and self.badge.AbsoluteSize.Y > 0 then
		return self.badge.AbsolutePosition.Y
	end
	return nil
end

return LuckClover
