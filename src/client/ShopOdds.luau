--!strict
-- ShopOdds: the odds pop-up behind the Blocks group's sky-blue "i" badges (the Mystery block,
-- each restock slot): a kit card listing every outcome in its colour and the total (Roblox's
-- paid-random-items rule: all of them, adding up to 100%, one press away before buying), as the
-- Grand Opening card's. The badge opens it by hover (it closes when the mouse leaves), or by a
-- click, tap or gamepad A (it stays until B, a tap away or another press). One pop-up shows at
-- a time on the page: opening one closes any other. Sizes as the hero card's
-- (Config.UI.GrandOpeningCard.Layout: OddsCardPx, OddsRowPx, OddsTitlePx), words in
-- Strings.Menus.Shop.Featured.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BlockOdds = require(Shared:WaitForChild("Progression"):WaitForChild("BlockOdds"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)

local L = Config.UI.GrandOpeningCard.Layout
local K = Config.UI.Kit
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Featured
local B_PRIORITY = Enum.ContextActionPriority.High.Value + 40 -- over the menus' B

export type Outcome = { name: string, display: string, percent: number, tint: Color3 }

type Row = { name: TextLabel, value: TextLabel }

local ShopOdds = {}
ShopOdds.__index = ShopOdds

-- The pop-up open on the page now (one at a time).
local current: any = nil

--- A pop-up in `parent` (hidden). `place(width, height)` says where its top-left goes in
--- `parent`'s pixels each time it opens, so it can sit beside its badge.
function ShopOdds.new(parent: GuiObject, place: (number, number) -> Vector2): any
	local self: any = setmetatable({}, ShopOdds)
	self.place = place
	self.open = false
	self.byHover = false
	self.hit = nil :: TextButton?
	self.connection = nil :: RBXScriptConnection?
	self.rows = {} :: { Row }
	local card = HudParts.card(parent, "OddsCard")
	card.ZIndex = 20
	card.Visible = false
	self.card = card
	local heading = HudParts.text(card, "Title", L.OddsTitlePx, COPY.OddsTitle)
	heading.ZIndex = 21
	self.heading = heading
	local sum = HudParts.note(card, "Total", L.MinTextPx, "")
	sum.TextXAlignment = Enum.TextXAlignment.Right
	sum.ZIndex = 21
	self.sum = sum
	return self
end

--- Fill the pop-up with `list` (bottom rarity first), rebuilding its rows.
function ShopOdds.fill(self: any, list: { Outcome })
	for _, row in self.rows do
		row.name:Destroy()
		row.value:Destroy()
	end
	table.clear(self.rows)
	local count = Color3.fromRGB(K.Numbers.Count[1], K.Numbers.Count[2], K.Numbers.Count[3])
	local total = 0
	for index, outcome in list do
		local name =
			HudParts.text(self.card, "Name" .. index, L.MinTextPx, outcome.name, outcome.tint)
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextWrapped = false
		name.ZIndex = 21
		local value =
			HudParts.text(self.card, "Percent" .. index, L.MinTextPx, outcome.display, count)
		value.TextXAlignment = Enum.TextXAlignment.Right
		value.TextWrapped = false
		value.ZIndex = 21
		table.insert(self.rows, { name = name, value = value })
		total += outcome.percent
	end
	self.sum.Text = string.format(COPY.OddsTotal, BlockOdds.percentText(total))
	self:size(math.huge)
end

-- Size the card: Layout.OddsRowPx rows, shrunk to fit `maxH` pixels.
function ShopOdds.size(self: any, maxH: number)
	local rows = self.rows
	local rowH = math.min(L.OddsRowPx, math.floor(maxH / (#rows + 3.1)))
	local f = rowH / L.OddsRowPx
	local function at(n: number): number
		return math.floor(n * f + 0.5)
	end
	local width = at(L.OddsCardPx)
	local top = at(40)
	local textPx = math.max(L.MinTextPx, at(16))
	self.card.Size = UDim2.fromOffset(width, at(44) + #rows * rowH + at(30))
	self.heading.Position = UDim2.fromOffset(at(12), at(8))
	self.heading.Size = UDim2.fromOffset(width - at(24), at(28))
	HudParts.setTextSize(self.heading, math.max(L.MinTextPx, at(L.OddsTitlePx)))
	for index, row in rows do
		local y = top + (index - 1) * rowH
		row.name.Position = UDim2.fromOffset(at(14), y)
		row.name.Size = UDim2.fromOffset(width - at(104), rowH)
		row.value.Position = UDim2.fromOffset(width - at(96), y)
		row.value.Size = UDim2.fromOffset(at(82), rowH)
		HudParts.setTextSize(row.name, textPx)
		HudParts.setTextSize(row.value, textPx)
	end
	self.sum.Position = UDim2.fromOffset(at(14), at(44) + #rows * rowH)
	self.sum.Size = UDim2.fromOffset(width - at(28), at(24))
	HudParts.setTextSize(self.sum, textPx)
end

--- Let the badge's press area `hit` open this pop-up with the outcomes `list()` gives then.
function ShopOdds.attach(self: any, hit: TextButton, list: () -> { Outcome })
	hit.MouseEnter:Connect(function()
		if not (self.open and self.hit == hit) then
			self:show(hit, list(), true)
		end
	end)
	hit.MouseLeave:Connect(function()
		if self.open and self.byHover and self.hit == hit then
			self:close()
		end
	end)
	hit.Activated:Connect(function()
		if self.open and self.hit == hit and not self.byHover then
			self:close()
		else
			self:show(hit, list(), false)
		end
	end)
end

--- Open the pop-up for the badge `hit` with `list`.
function ShopOdds.show(self: any, hit: TextButton, list: { Outcome }, byHover: boolean)
	if current and current ~= self then
		current:close()
	end
	current = self
	self:fill(list)
	local size = self.card.Size
	local at = self.place(size.X.Offset, size.Y.Offset)
	self.card.Position = UDim2.fromOffset(at.X, at.Y)
	self.hit = hit
	self.byHover = byHover
	self:unbind()
	if not self.open then
		self.open = true
		UIAnim.popIn(self.card)
	end
	-- B closes it (before the Shop's own B).
	ContextActionService:BindActionAtPriority("8ballShopBlockOdds", function(_, state)
		if state == Enum.UserInputState.Begin then
			self:close()
		end
		return Enum.ContextActionResult.Sink
	end, false, B_PRIORITY, Enum.KeyCode.ButtonB)
	-- A tap or click anywhere off the badge and the pop-up closes it.
	self.connection = UserInputService.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		-- The input is below Roblox's top bar; the Shop's ScreenGui ignores that inset.
		local at = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
		for _, object in { self.card, hit } do
			local from = object.AbsolutePosition
			local to = from + object.AbsoluteSize
			if at.X >= from.X and at.X <= to.X and at.Y >= from.Y and at.Y <= to.Y then
				return
			end
		end
		self:close()
	end)
end

function ShopOdds.unbind(self: any)
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
	ContextActionService:UnbindAction("8ballShopBlockOdds")
end

--- Close the pop-up (the Shop closing, B, a tap away).
function ShopOdds.close(self: any)
	self:unbind()
	if current == self then
		current = nil
	end
	if not self.open then
		return
	end
	self.open = false
	self.hit = nil
	UIAnim.popOut(self.card)
end

--- Close whichever pop-up is open on the page.
function ShopOdds.closeAll()
	if current then
		current:close()
	end
end

--- Every rarity (and capped Unique cue) of the block odds row `oddsId`, bottom first.
function ShopOdds.blockOutcomes(oddsId: string): { Outcome }
	local rarities: { [string]: string } = Strings.Items.Rarities :: any
	local cues: { [string]: string } = Strings.Items.Cues :: any
	local list: { Outcome } = {}
	for _, row in BlockOdds.odds(oddsId) do
		table.insert(list, {
			name = rarities[row.rarity] or row.rarity,
			display = row.display,
			percent = row.percent,
			tint = if row.rarity == "Secret"
				then Color3.fromRGB(K.SecretGlow[1], K.SecretGlow[2], K.SecretGlow[3])
				else HudParts.color((K.Rarity :: any)[row.rarity] or K.Rarity.Default),
		})
	end
	local uniques = BlockOdds.uniqueRows(oddsId)
	table.sort(uniques, function(a, b)
		return a.weight > b.weight
	end)
	for _, row in uniques do
		table.insert(list, {
			name = cues[row.cue] or row.cue,
			display = row.display,
			percent = row.percent,
			tint = HudParts.color(K.Rarity.Unique),
		})
	end
	return list
end

return ShopOdds
