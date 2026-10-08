--!strict
-- ShopMysteryOdds: the Mystery Lucky Block's "Odds & Details" (economy v4 plan 3.2 and the GUI
-- hand-off item 13). The Shop's Mystery card's sky-blue "i" opens it over the Shop as the Gift
-- Player popup (ShopGift): a kit card with its title and the red X over a list that scrolls,
-- every number Roblox's paid-random-items rules ask for before buying:
-- - "The result is decided when you open it; the presses reveal it."
-- - Pity: Rare or better within 10 and Epic or better within 100, each with the blocks to go
--   (the server's count, ShopState's pity). Once a guarantee is the very next block a gold line
--   says so and the tables under it show the live odds (the guaranteed tier, while it is live).
-- - The final tier's chances (BlockDrop.tiers), each with its block's picture.
-- - Each tier block's odds (BlockOdds.odds of each tier's row).
-- - Each rarity's chance per Mystery block (BlockDrop.rarityOdds), adding to 100%.
-- Chances under OneInUnderPercent show "1 in N" beside them (BlockOdds.oneIn, rounded up so it
-- never looks better than true). B, Escape, the X or a press outside the card close it; a
-- gamepad lands on the list and scrolls it. Sizes in Config.UI.Shop.MysteryOdds, words in
-- Strings.Menus.Shop.Blocks.Odds.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Format = require(Progression:WaitForChild("Format"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Menus = require(script.Parent.Menus)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local O = Config.UI.Shop.MysteryOdds
local K = Config.UI.Kit
local D = Config.BlockOdds.Drop
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local COPY: { [string]: string } = (Strings.Menus.Shop :: any).Blocks.Odds
local SHORT: { [string]: string } = Strings.LuckyBlocks.Short
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local ACTION = "8ballMysteryOddsClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- over the menus' B, like a dialog
local ZINDEX = 52 -- as the Gift Player popup's: over the pages, under notices and dialogs
local span = ShopParts.span
local round = ShopParts.round
local rgb = ShopCards.rgb

-- One line of the list: a note, a section's heading, the live pity line, a tier block's name,
-- a row (a name, its "1 in N" and its chance) or the total.
type Item = {
	kind: string, -- "Note", "Head", "Live", "Sub", "Row", "Total"
	main: TextLabel,
	oneIn: TextLabel?,
	value: TextLabel?,
	icon: ImageLabel?,
}

local ShopMysteryOdds = {}
ShopMysteryOdds.__index = ShopMysteryOdds

-- "1 in 2,000" beside a chance under OneInUnderPercent, else "".
local function oneInText(percent: number): string
	if percent >= O.OneInUnderPercent then
		return ""
	end
	local n = BlockOdds.oneIn(percent)
	return if n then Strings.LuckyBlocks.OneIn:format(Format.commas(n)) else ""
end

-- The blocks to go before a guarantee (ShopState's pity: 1 is the very next block).
local function toGo(left: any): string
	if type(left) ~= "number" then
		return ""
	end
	return if left <= 1 then COPY.Next else COPY.ToGo:format(math.floor(left))
end

--- The popup (closed) over `frame`'s pages. `shop` is the ShopMenu.
function ShopMysteryOdds.new(shop: any, frame: any): any
	local self: any = setmetatable({}, ShopMysteryOdds)
	self.shop = shop
	self.frame = frame
	self.opened = false
	self.items = {} :: { Item }
	self.painted = nil :: string?
	self.connections = {} :: { RBXScriptConnection }
	self.fakePity = nil :: any -- the Studio hook's stand-in pity

	-- A clear layer over the pages: a press outside the card closes it.
	local layer = Instance.new("TextButton")
	layer.Name = "MysteryOdds"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = ZINDEX
	layer.Visible = false
	layer.Parent = frame.content
	layer.Activated:Connect(function()
		self:close()
	end)
	self.layer = layer
	local card = HudParts.popupCard(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.ZIndex = 2
	card.Active = true -- a press on the card is not a press outside it
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.card = card
	local mystery = KINDS.Mystery
	local heading = ShopCards.image(card, "Heading", if mystery then mystery.Icon else "", 3)
	heading.AnchorPoint = Vector2.new(0, 0)
	self.headingIcon = heading
	local title = HudParts.text(card, "Title", K.Big.Heading, COPY.Title)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.title = title
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 4
	HudParts.setMinHit(close, Config.UI.Menu.Frame.TouchMinPx)
	HudParts.padBack(close) -- B closes it
	self.closeButton = close
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = O.ScrollBarPx
	list.ScrollBarImageColor3 = HudParts.color(K.Colors.Ink)
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Selectable = true -- a gamepad lands here and scrolls it with the stick
	list.SelectionImageObject = Instance.new("Frame")
	list.ZIndex = 3
	list.ClipsDescendants = true
	list.Parent = card
	self.list = list
	-- Studio only: GuiQA:Invoke("mysteryOdds", rare?, epic?) opens it as if that many blocks
	-- were left to each guarantee (1: the very next; nothing: the server's count).
	GuiQA.add("mysteryOdds", function(rare: number?, epic: number?)
		self.fakePity = if rare or epic
			then { rare = rare or D.PityRare, epic = epic or D.PityEpic }
			else nil
		self.painted = nil
		self:open()
		return #self.items
	end)
	return self
end

function ShopMysteryOdds.isOpen(self: any): boolean
	return self.opened
end

-- Make one list item's labels.
function ShopMysteryOdds.add(
	self: any,
	kind: string,
	text: string,
	tint: Color3?,
	oneIn: string?,
	value: string?,
	icon: string?
)
	local list = self.list
	local n = #self.items + 1
	local main: TextLabel
	if kind == "Note" or kind == "Total" then
		main = HudParts.note(list, kind .. n, K.Text.Min, text)
		main.TextXAlignment = if kind == "Total"
			then Enum.TextXAlignment.Right
			else Enum.TextXAlignment.Left
		main.TextWrapped = kind == "Note"
	else
		main = HudParts.text(list, kind .. n, K.Text.Min, text, tint)
		main.TextXAlignment = Enum.TextXAlignment.Left
		main.TextWrapped = kind == "Live"
	end
	main.ZIndex = 4
	local item: Item = { kind = kind, main = main, oneIn = nil, value = nil, icon = nil }
	if kind == "Row" then
		local small = HudParts.note(list, "OneIn" .. n, K.Text.Min, oneIn or "")
		small.TextColor3 = rgb(O.OneInColor)
		small.TextXAlignment = Enum.TextXAlignment.Right
		small.TextWrapped = false
		small.ZIndex = 4
		item.oneIn = small
		local chance =
			HudParts.text(list, "Chance" .. n, K.Text.Min, value or "", rgb(K.Numbers.Count))
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.TextWrapped = false
		chance.ZIndex = 4
		item.value = chance
	end
	if icon and icon ~= "" then
		local picture = ShopCards.image(list, "Icon" .. n, icon, 4)
		picture.AnchorPoint = Vector2.new(0, 0.5)
		item.icon = picture
	end
	table.insert(self.items, item)
end

-- The pity counts shown: the Studio hook's, else the server's.
function ShopMysteryOdds.pity(self: any): any
	if self.fakePity then
		return self.fakePity
	end
	local state = ItemState.shop()
	return if type(state) == "table" and type(state.pity) == "table" then state.pity else nil
end

--- Fill the list for the pity counts now (only when they changed).
function ShopMysteryOdds.paint(self: any)
	local pity = self:pity()
	local floor = BlockDrop.floorOf(pity)
	local key = string.format(
		"%s|%s",
		tostring(if pity then pity.rare else nil),
		tostring(if pity then pity.epic else nil)
	)
	if key == self.painted then
		return
	end
	self.painted = key
	for _, item in self.items :: { Item } do
		item.main:Destroy()
		for _, part in { item.oneIn, item.value, item.icon } :: { Instance? } do
			if part then
				part:Destroy()
			end
		end
	end
	table.clear(self.items)

	self:add("Note", Strings.LuckyBlocks.Reveal.Decided)
	-- Pity, with the live line once a guarantee is the very next block.
	self:add("Head", COPY.Pity)
	if floor then
		self:add("Live", COPY.Live:format(SHORT[floor] or floor), rgb(O.LiveColor))
	end
	local left = if type(pity) == "table" then pity else {}
	self:add(
		"Row",
		COPY.PityRare:format(D.PityRare),
		ShopCards.rarityColor("Rare"),
		"",
		toGo(left.rare)
	)
	self:add(
		"Row",
		COPY.PityEpic:format(D.PityEpic),
		ShopCards.rarityColor("Epic"),
		"",
		toGo(left.epic)
	)
	-- The final tier (with pity's floor while it is live).
	self:add("Head", if floor then COPY.TiersLive else COPY.Tiers)
	for _, tier in BlockDrop.tiers(floor) do
		local row = KINDS[tier.tier]
		self:add(
			"Row",
			SHORT[tier.tier] or tier.tier,
			ShopCards.rarityColor(tier.tier),
			oneInText(tier.percent),
			tier.display,
			if row then row.Icon else nil
		)
	end
	-- Each tier block's own odds.
	self:add("Head", COPY.Blocks)
	for _, tier in BlockDrop.tiers() do
		local row = KINDS[tier.tier]
		self:add(
			"Sub",
			NAMES[tier.tier] or tier.tier,
			ShopCards.rarityColor(tier.tier),
			nil,
			nil,
			if row then row.Icon else nil
		)
		for _, odds in BlockOdds.odds(tier.tier) do
			self:add(
				"Row",
				RARITIES[odds.rarity] or odds.rarity,
				ShopCards.rarityColor(odds.rarity),
				oneInText(odds.percent),
				odds.display
			)
		end
	end
	-- Each rarity per Mystery block (the next one's, with pity's floor while it is live).
	self:add("Head", if floor then COPY.RaritiesLive else COPY.Rarities)
	local total = 0
	for _, odds in BlockDrop.rarityOdds(floor) do
		self:add(
			"Row",
			RARITIES[odds.rarity] or odds.rarity,
			ShopCards.rarityColor(odds.rarity),
			oneInText(odds.percent),
			odds.display
		)
		total += odds.percent
	end
	self:add("Total", COPY.Total:format(BlockOdds.percentText(total)))
end

--- Open it (the "i" badge), or bring it up to date while open.
function ShopMysteryOdds.open(self: any)
	self:paint()
	if not self.opened then
		self.opened = true
		self.previous = GuiService.SelectedObject
		self.layer.Visible = true
		self.list.CanvasPosition = Vector2.zero
		UIAnim.popIn(self.card)
		self.dialog = {
			cancel = function()
				self:close()
			end,
			isOpen = function(): boolean
				return self.opened
			end,
		}
		table.insert(self.frame.dialogs, self.dialog)
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, state: Enum.UserInputState, _input: InputObject)
				if state == Enum.UserInputState.Begin then
					self:close()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			PRIORITY,
			Enum.KeyCode.ButtonB
		)
		table.insert(
			self.connections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape then
					Menus.swallowEscape(input)
					self:close()
				end
			end)
		)
	end
	local geo = self.shop.geo
	if geo then
		self:layout(geo)
	end
	if ShopParts.gamepad() then
		GuiService.SelectedObject = self.list
	end
end

--- The shop's state changed: the pity counts may have moved.
function ShopMysteryOdds.refresh(self: any)
	if not self.opened then
		return
	end
	local before = self.painted
	self:paint()
	local geo = self.shop.geo
	if self.painted ~= before and geo then
		self:layout(geo)
	end
end

function ShopMysteryOdds.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	self.fakePity = nil
	local at = table.find(self.frame.dialogs, self.dialog)
	if at then
		table.remove(self.frame.dialogs, at)
	end
	ContextActionService:UnbindAction(ACTION)
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.layer) then
		local previous = self.previous
		GuiService.SelectedObject = if previous and previous:IsDescendantOf(game)
			then previous
			else nil
	end
	self.previous = nil
	UIAnim.popOut(self.card, function()
		if not self.opened then
			self.layer.Visible = false
		end
	end)
end

--- Lay the card out for the page's size (MenuFrame's geo).
function ShopMysteryOdds.layout(self: any, geo: any)
	if not self.opened then
		return
	end
	local s = ShopParts.sizes(geo)
	local t = s.t
	local pad = s.pad
	local w = math.min(span(O.WidthPx, t), geo.content.X - 8)
	local titleH = math.max(K.Text.Min, round(K.Big.Heading * (0.75 + 0.25 * t)))
	local closeSize = math.min(titleH + 8, 44)
	local iw = w - 2 * pad
	local rowH = span(O.RowPx, t)
	local textPx = span(O.TextPx, t)
	local headPx = span(O.HeadPx, t)
	local subPx = span(O.SubPx, t)
	local notePx = span(O.NotePx, t)
	local sectionGap = span(O.SectionGapPx, t)
	local inset = span(O.RowInsetPx, t)
	local listW = iw - O.ScrollBarPx - 4 -- room for the scroll bar
	local valueW = round(listW * O.ValueShare)
	local oneInW = round(listW * O.OneInShare)

	-- The list's items, top to bottom.
	local y = 0
	for index, item in self.items :: { Item } do
		local kind = item.kind
		if kind == "Note" then
			local h = ShopParts.wrapHeight(item.main.Text, notePx, listW, 3)
			HudParts.setTextSize(item.main, notePx)
			item.main.Position = UDim2.fromOffset(0, y)
			item.main.Size = UDim2.fromOffset(listW, h)
			y += h
		elseif kind == "Head" then
			if index > 1 then
				y += sectionGap
			end
			HudParts.setTextSize(item.main, headPx)
			item.main.Position = UDim2.fromOffset(0, y)
			item.main.Size = UDim2.fromOffset(listW, headPx + 6)
			y += headPx + 6
		elseif kind == "Live" then
			local h = ShopParts.wrapHeight(item.main.Text, textPx, listW - inset, 2)
			HudParts.setTextSize(item.main, textPx)
			item.main.Position = UDim2.fromOffset(inset, y)
			item.main.Size = UDim2.fromOffset(listW - inset, h)
			y += h
		elseif kind == "Sub" then
			y += round(sectionGap / 2)
			local side = subPx + 6
			local x = inset
			if item.icon then
				item.icon.Position = UDim2.fromOffset(x, y + round(side / 2))
				item.icon.Size = UDim2.fromOffset(side, side)
				x += side + 4
			end
			HudParts.setTextSize(item.main, subPx)
			item.main.Position = UDim2.fromOffset(x, y)
			item.main.Size = UDim2.fromOffset(math.max(1, listW - x), side)
			y += side
		elseif kind == "Row" then
			local x = inset
			if item.icon then
				local side = rowH - 2
				item.icon.Position = UDim2.fromOffset(x, y + round(rowH / 2))
				item.icon.Size = UDim2.fromOffset(side, side)
				x += side + 4
			end
			HudParts.setTextSize(item.main, textPx)
			item.main.Position = UDim2.fromOffset(x, y)
			item.main.Size = UDim2.fromOffset(math.max(1, listW - x - valueW - oneInW), rowH)
			local oneIn, value = item.oneIn, item.value
			if oneIn then
				HudParts.setTextSize(oneIn, notePx)
				oneIn.Position = UDim2.fromOffset(listW - valueW - oneInW, y)
				oneIn.Size = UDim2.fromOffset(oneInW - 6, rowH)
			end
			if value then
				HudParts.setTextSize(value, textPx)
				value.Position = UDim2.fromOffset(listW - valueW, y)
				value.Size = UDim2.fromOffset(valueW, rowH)
			end
			y += rowH
		elseif kind == "Total" then
			HudParts.setTextSize(item.main, notePx)
			item.main.Position = UDim2.fromOffset(0, y + 2)
			item.main.Size = UDim2.fromOffset(listW, notePx + 6)
			y += notePx + 8
		end
	end
	local contentH = y

	local top = pad + titleH + 4 + s.gap
	local h = math.min(top + contentH + pad, geo.content.Y - 8)
	self.card.Size = UDim2.fromOffset(w, h)
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - pad, pad)
	self.headingIcon.Position = UDim2.fromOffset(pad, pad - 2)
	self.headingIcon.Size = UDim2.fromOffset(titleH + 8, titleH + 8)
	HudParts.setTextSize(self.title, titleH)
	self.title.Position = UDim2.fromOffset(pad + titleH + 14, pad)
	self.title.Size =
		UDim2.fromOffset(math.max(1, w - 2 * pad - titleH - 14 - closeSize), titleH + 4)
	local list: ScrollingFrame = self.list
	list.Position = UDim2.fromOffset(pad, top)
	list.Size = UDim2.fromOffset(iw, math.max(1, h - top - pad))
	list.CanvasSize = UDim2.fromOffset(0, contentH)
end

return ShopMysteryOdds
