--!strict
-- InventoryCues: the Inventory's Cues tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11).
--
--   * A strip on top: rarity filter chips (All, Common ... Secret, Exclusive, Unique; the chosen
--     one blue, the others white with the rarity's colour in their word), sliding sideways
--     when they do not all fit, and "Sell all duplicates: $1,234" (the total worked out here
--     from Cases.sellValue for show; the server's reply is the truth), which asks first.
--   * A grid of cue cards (InventoryCard), rarest first as the snapshot sends them, Classic
--     always there and last: the tinted thumbnail, the name, the rarity's dressing, "x3" for
--     copies (a Unique cue's "#412"), a gold NEW until seen, a green Equipped, a padlock on
--     Exclusive and Unique cues.
--   * The chosen cue's details: the bigger thumbnail, name, rarity, "1,284 exist" (the
--     ReplicatedStorage.CueCounts attribute named by the cue's id; the line hides while it is
--     unknown), "You own 3" (a Unique cue: "Copy #412"), then Equip, "Sell $120" and "Sell
--     duplicates: $240" (a confirm from Config.Cases.ConfirmSellFrom up: red sells, blue keeps).
--     Exclusive, Unique and Classic cues show a padlock and "Can't be sold" instead of the sells.
--     A tall page (a computer) stacks it: the picture on top, beside the strip and the grid. A
--     short one (a phone) puts the picture left of the words, under a strip across the page.
--
-- Choosing: a tap or click on a card shows its details; a gamepad shows them as it lands on a
-- card, and A then moves it to the details' first button. NEW tags clear with one MarkSeen
-- each time the tab is shown (the new ids, at most Config.Items.MarkSeenMax); the pills stay
-- up until the tab is left, so the player sees what is new.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Cases = require(Progression:WaitForChild("Cases"))
local Catalog = require(Progression:WaitForChild("Catalog"))
local Format = require(Progression:WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local MenuFrame = require(script.Parent.MenuFrame)

local I = Config.UI.Inventory
local D = I.Detail
local SC = Config.UI.Menu.Scroll
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local COPIES_FOLDER = "CueCounts" -- ReplicatedStorage.CueCounts: copies in existence (Counters)

-- The chips, left to right: every cue, the ladder, then the groups outside it.
local FILTERS: { string } = { "All" }
for _, rarity in Config.Cases.Rarities do
	table.insert(FILTERS, rarity)
end
table.insert(FILTERS, "Exclusive")
table.insert(FILTERS, "Unique")

local InventoryCues = {}
InventoryCues.__index = InventoryCues

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

local function textHeight(text: string, size: number, width: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(math.max(1, width), 4000)).Y
end

local function list(value: any): { any }
	return if type(value) == "table" then value else {}
end

-- The snapshot's owned cues ({ id, count, new, copy? }), only well-formed rows.
local function ownedRows(items: any): { any }
	local rows = {}
	for _, row in list(items and items.cues) do
		if type(row) == "table" and type(row.id) == "string" and Catalog.get(row.id) then
			table.insert(rows, row)
		end
	end
	return rows
end

local function countOf(row: any): number
	return if type(row.count) == "number" then row.count else 1
end

local function matches(filter: string, id: string): boolean
	if filter == "All" then
		return true
	end
	local cue = Catalog.get(id)
	return cue ~= nil and cue.Rarity == filter
end

-- A cue's count line: "#412" for a Unique copy, "x3" for copies, else nothing.
local function countLine(row: any): string
	if type(row.copy) == "number" then
		return WORDS.CopyShort:format(Format.commas(row.copy))
	end
	local count = countOf(row)
	return if count > 1 then WORDS.Count:format(Format.commas(count)) else ""
end

--- The Cues page, built into `page` (MenuFrame's page for the tab). `ctx`: InventoryMenu's.
function InventoryCues.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, InventoryCues)
	self.page = page
	self.ctx = ctx
	self.filter = "All"
	self.chosen = nil :: string?
	self.cards = {} :: { [string]: InventoryCard.Card }
	self.rows = {} :: { [string]: any } -- the snapshot's rows by id, for the details
	self.order = {} :: { string } -- the ids shown now, in order
	self.sticky = {} :: { [string]: boolean } -- NEW while the tab is up, though already marked
	self.showing = false
	self.wantMark = false
	self.geo = nil :: MenuFrame.Geo?
	self.stacked = true
	self.sellAllTotal = 0

	-- The strip: the chips (sliding sideways) and Sell all duplicates.
	local strip = HudParts.frame(page, "Strip")
	strip.ZIndex = 2
	self.strip = strip
	local chipScroll = Instance.new("ScrollingFrame")
	chipScroll.Name = "Chips"
	chipScroll.BackgroundTransparency = 1
	chipScroll.BorderSizePixel = 0
	chipScroll.ScrollingDirection = Enum.ScrollingDirection.X
	chipScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	chipScroll.CanvasSize = UDim2.new()
	-- A thin bar under the chips (in the room kept round them) when they do not all fit, so a
	-- mouse can reach the rest too; touch drags them and a gamepad scrolls to its selection.
	chipScroll.ScrollBarThickness = I.ChipBarPx
	chipScroll.ScrollBarImageColor3 = HudParts.color(SC.BarColor)
	chipScroll.HorizontalScrollBarInset = Enum.ScrollBarInset.None
	chipScroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	chipScroll.Selectable = false
	chipScroll.ZIndex = 2
	chipScroll.Parent = strip
	-- Room round the chips for a hovered chip's grow and gold outline.
	local chipPad = Instance.new("UIPadding")
	chipPad.PaddingLeft = UDim.new(0, SC.PadPx / 2)
	chipPad.PaddingRight = UDim.new(0, SC.PadPx / 2)
	chipPad.Parent = chipScroll
	local chipRow = Instance.new("UIListLayout")
	chipRow.FillDirection = Enum.FillDirection.Horizontal
	chipRow.VerticalAlignment = Enum.VerticalAlignment.Center
	chipRow.SortOrder = Enum.SortOrder.LayoutOrder
	chipRow.Parent = chipScroll
	self.chipScroll, self.chipRow = chipScroll, chipRow
	self.chips = {} :: { [string]: TextButton }
	for index, key in FILTERS do
		local label = if key == "All" then WORDS.All else CueThumb.rarityName(key)
		local chip = HudParts.candy(chipScroll, label, function()
			self:setFilter(key)
		end, if key == self.filter then "Blue" else "White")
		chip.Name = "Chip" .. key
		chip.LayoutOrder = index
		HudParts.setMinHit(chip, TOUCH)
		self.chips[key] = chip
	end
	self.sellAll = HudParts.candy(strip, "", function()
		self:askSellAll()
	end, "Yellow", "Sell")
	self.sellAll.Name = "SellAll"
	HudParts.setMinHit(self.sellAll, TOUCH)

	-- The grid.
	local gridHolder = HudParts.frame(page, "GridHolder")
	gridHolder.ZIndex = 2
	self.gridHolder = gridHolder
	-- MenuFrame's scroller (its padding, bar and gamepad scrolling) with a grid sized here, from
	-- the page's layout, so a computer's cards can be bigger than a phone's.
	local grid, stack = MenuFrame.scroller(gridHolder, { name = "Cards" })
	stack:Destroy()
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.Parent = grid
	self.grid, self.gridLayout = grid, gridLayout
	self.empty = MenuFrame.placeholder(gridHolder, "")
	self.empty.Visible = false

	self:buildDetail(page)
	self.loading = MenuFrame.placeholder(page)

	-- Copies in existence: the attribute on ReplicatedStorage.CueCounts (made by the server).
	self.counts = ReplicatedStorage:FindFirstChild(COPIES_FOLDER)
	local function watchCounts(folder: Instance)
		self.counts = folder
		folder.AttributeChanged:Connect(function(name: string)
			if name == self.chosen then
				self:refreshDetail()
			end
		end)
	end
	if self.counts then
		watchCounts(self.counts)
	else
		local added: RBXScriptConnection
		added = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == COPIES_FOLDER then
				added:Disconnect()
				watchCounts(child)
				self:refreshDetail()
			end
		end)
	end
	return self
end

--------------------------------------------------------------------------------------------
-- The detail panel
--------------------------------------------------------------------------------------------

function InventoryCues.buildDetail(self: any, page: Frame)
	local box = InventoryCard.box(page, "Detail")
	box.ZIndex = 2
	self.detail = box
	-- Its contents scroll when a short screen or a long translation needs more room.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = SC.BarPx
	scroll.ScrollBarImageColor3 = HudParts.color(SC.BarColor)
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = box
	self.detailScroll = scroll

	-- The picture, in a small dressed card.
	local artBox = InventoryCard.box(scroll, "ArtBox")
	artBox.ZIndex = 2
	self.artBox = artBox
	local thumb = CueThumb.new(artBox, Catalog.Default)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.Size = UDim2.fromScale(D.ThumbShare, D.ThumbShare)
	thumb.ZIndex = 3
	self.thumb = thumb
	self.artDressing = nil :: any
	self.artKey = ""

	self.nameLabel = HudParts.text(scroll, "Name", D.NameTextPx[2], "")
	self.nameLabel.ZIndex = 3
	self.rarityLabel = HudParts.text(scroll, "Rarity", D.RarityTextPx[2], "")
	self.rarityLabel.TextWrapped = false
	self.rarityLabel.ZIndex = 3
	self.existLabel = HudParts.note(scroll, "Exist", D.LineTextPx[2], "")
	self.existLabel.TextWrapped = false
	self.existLabel.ZIndex = 3
	self.ownedLabel = HudParts.note(scroll, "Owned", D.LineTextPx[2], "")
	self.ownedLabel.TextWrapped = false
	self.ownedLabel.ZIndex = 3
	local lockRow = HudParts.frame(scroll, "LockRow")
	lockRow.ZIndex = 3
	self.lockRow = lockRow
	self.lockIcon = HudParts.icon(lockRow, "Lock", "Lock")
	self.lockIcon.ZIndex = 3
	self.lockLabel = HudParts.note(lockRow, "Words", D.LineTextPx[2], WORDS.CantSell)
	self.lockLabel.TextWrapped = false
	self.lockLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.lockLabel.ZIndex = 3

	self.equip = HudParts.candy(scroll, WORDS.Equip, function()
		self:doEquip()
	end, "Green")
	self.equip.Name = "Equip"
	self.equip.ZIndex = 3
	HudParts.setMinHit(self.equip, TOUCH)
	self.sell = HudParts.candy(scroll, "", function()
		self:askSell()
	end, "Red", "Sell")
	self.sell.Name = "Sell"
	self.sell.ZIndex = 3
	HudParts.setMinHit(self.sell, TOUCH)
	self.sellDupes = HudParts.candy(scroll, "", function()
		self:askSellDuplicates()
	end, "Yellow", "Sell")
	self.sellDupes.Name = "SellDuplicates"
	self.sellDupes.ZIndex = 3
	HudParts.setMinHit(self.sellDupes, TOUCH)
end

-- Copies in existence of a cue, or nil while unknown.
function InventoryCues.copies(self: any, id: string): number?
	local folder: Instance? = self.counts
	if not folder then
		return nil
	end
	local value = folder:GetAttribute(id)
	return if type(value) == "number" and value == value then value else nil
end

-- The chosen cue's words, buttons and picture (then lays the panel out).
function InventoryCues.refreshDetail(self: any)
	local ctx = self.ctx
	local id: string? = self.chosen
	local row = if id then self.rows[id] else nil
	self.detail.Visible = row ~= nil
	if not id or not row then
		return
	end
	local cue = Catalog.get(id)
	if not cue then
		return
	end
	CueThumb.set(self.thumb, id, false)
	local key = cue.Rarity .. "/" .. (cue.Tier or "")
	if key ~= self.artKey then
		if self.artDressing then
			self.artDressing.destroy()
		end
		local tint = if cue.Tier then CueThumb.cueColor(id) else nil
		self.artDressing = CueThumb.dress(self.artBox, cue.Rarity, tint)
		self.artKey = key
	end
	self.nameLabel.Text = CueThumb.cueName(id)
	self.rarityLabel.Text = CueThumb.rarityName(cue.Rarity)
	self.rarityLabel.TextColor3 = CueThumb.cueColor(id)
	-- Hidden while unknown, and while the counter has not caught up with a new cue yet (0).
	local copies = self:copies(id)
	if copies ~= nil and copies < 1 then
		copies = nil
	end
	self.existLabel.Text = if copies
		then (if copies == 1 then WORDS.ExistOne else WORDS.Exist):format(Format.commas(copies))
		else ""
	self.existLabel.Visible = copies ~= nil
	local count = countOf(row)
	self.ownedLabel.Text = if type(row.copy) == "number"
		then WORDS.Copy:format(Format.commas(row.copy))
		else WORDS.Owned:format(Format.commas(count))
	local value = Cases.sellValue(id)
	local sellable = value > 0
	self.lockRow.Visible = not sellable

	-- Equip: grey and still once this cue is the equipped one.
	local items = ctx.lastItems
	local equipped = type(items) == "table" and items.equipped == id
	HudParts.setText(self.equip, if equipped then WORDS.Equipped else WORDS.Equip)
	HudParts.setTone(self.equip, if equipped then "Grey" else "Green")
	HudParts.setButtonIcon(self.equip, if equipped then "Check" else nil)
	HudParts.setEnabled(self.equip, not equipped and not ctx.isHeld(self.equip))

	self.sell.Visible = sellable
	HudParts.setText(self.sell, WORDS.Sell:format(Format.money(value)))
	HudParts.setEnabled(self.sell, not ctx.isHeld(self.sell))
	local extra = count - 1
	self.sellDupes.Visible = sellable and extra > 0
	HudParts.setText(self.sellDupes, WORDS.SellDuplicates:format(Format.money(extra * value)))
	HudParts.setEnabled(self.sellDupes, not ctx.isHeld(self.sellDupes))
	self:arrangeDetail()
end

-- Lay the detail panel out: stacked (the picture on top) on a tall page, else the picture left
-- of the words; the buttons under them, full width. Its canvas grows to fit.
function InventoryCues.arrangeDetail(self: any)
	local ctx = self.ctx
	local size = self.detailSize :: Vector2?
	if not size or size.X <= 0 then
		return
	end
	local span = ctx.span
	local pad, gap = span(D.PadPx), span(D.GapPx)
	local w = size.X - SC.BarPx
	local inner = w - 2 * pad
	local art = math.min(span(D.ArtPx), inner)
	local nameSize, raritySize, lineSize =
		span(D.NameTextPx), span(D.RarityTextPx), span(D.LineTextPx)
	HudParts.setTextSize(self.nameLabel, nameSize)
	HudParts.setTextSize(self.rarityLabel, raritySize)
	HudParts.setTextSize(self.existLabel, lineSize)
	HudParts.setTextSize(self.ownedLabel, lineSize)
	HudParts.setTextSize(self.lockLabel, lineSize)
	local stacked = self.stacked
	local align = if stacked then Enum.TextXAlignment.Center else Enum.TextXAlignment.Left
	for _, label in { self.nameLabel, self.rarityLabel, self.existLabel, self.ownedLabel } do
		label.TextXAlignment = align
	end

	-- The picture, and where the words start.
	local textX, textW, y
	if stacked then
		self.artBox.Position = UDim2.fromOffset(round((w - art) / 2), pad)
		textX, textW, y = pad, inner, pad + art + gap
	else
		self.artBox.Position = UDim2.fromOffset(pad, pad)
		textX = pad + art + gap
		textW = math.max(1, w - textX - pad)
		y = pad
	end
	self.artBox.Size = UDim2.fromOffset(art, art)

	-- The words, one under another (the name may wrap).
	local function place(label: TextLabel, height: number)
		label.Position = UDim2.fromOffset(textX, y)
		label.Size = UDim2.fromOffset(textW, height)
		y += height
	end
	place(self.nameLabel, math.ceil(textHeight(self.nameLabel.Text, nameSize, textW - 4)) + 4)
	place(self.rarityLabel, raritySize + 6)
	if self.existLabel.Visible then
		place(self.existLabel, lineSize + 4)
	end
	place(self.ownedLabel, lineSize + 4)
	if self.lockRow.Visible then
		local lock = span(D.LockPx)
		local words = math.ceil(textWidth(self.lockLabel.Text, lineSize)) + 6
		local rowW = math.min(textW, lock + 4 + words)
		local x = if stacked then textX + round((textW - rowW) / 2) else textX
		self.lockRow.Position = UDim2.fromOffset(x, y + 2)
		self.lockRow.Size = UDim2.fromOffset(rowW, math.max(lock, lineSize + 4))
		self.lockIcon.Size = UDim2.fromOffset(lock, lock)
		self.lockLabel.Position = UDim2.fromOffset(lock + 4, 0)
		self.lockLabel.Size =
			UDim2.fromOffset(math.max(1, rowW - lock - 4), math.max(lock, lineSize + 4))
		y += math.max(lock, lineSize + 4) + 2
	end
	if not stacked then
		y = math.max(y, pad + art)
	end
	y += gap

	-- The buttons, full width.
	local buttonH, buttonText = span(D.ButtonPx), span(D.ButtonTextPx)
	for _, button in { self.equip, self.sell, self.sellDupes } do
		if button.Visible then
			button.Position = UDim2.fromOffset(pad, y)
			button.Size = UDim2.fromOffset(inner, buttonH)
			HudParts.setButtonTextSize(button, buttonText)
			y += buttonH + gap
		end
	end
	self.detailScroll.CanvasSize = UDim2.fromOffset(0, y - gap + pad)
end

--------------------------------------------------------------------------------------------
-- Drawing from the snapshot
--------------------------------------------------------------------------------------------

--- The tab's red dot: how many owned cues are NEW.
function InventoryCues.dot(_self: any, items: any): number
	local n = 0
	for _, row in ownedRows(items) do
		if row.new == true then
			n += 1
		end
	end
	return n
end

--- Redraw from the snapshot (nil before the first: "Loading...").
function InventoryCues.redraw(self: any, items: any)
	local ctx = self.ctx
	local loaded = type(items) == "table"
	self.loading.Visible = not loaded
	self.strip.Visible = loaded
	self.gridHolder.Visible = loaded
	if not loaded then
		self.detail.Visible = false
		return
	end
	if self.wantMark and self.showing then
		self:markSeen()
	end

	-- The cards, one per owned cue, kept across redraws so a gamepad stays on its card.
	local rows = ownedRows(items)
	local byId: { [string]: any } = {}
	for _, row in rows do
		byId[row.id] = row
	end
	self.rows = byId
	for id, card in self.cards do
		if not byId[id] then
			InventoryCard.destroy(card)
			self.cards[id] = nil
		end
	end
	local order = {}
	for index, row in rows do
		local id: string = row.id
		local card = self.cards[id]
		if not card then
			card = InventoryCard.new(self.grid, {
				name = id,
				onPress = function()
					self:choose(id, true)
				end,
				onSelect = function()
					self:choose(id, false)
				end,
			})
			self.cards[id] = card
		end
		local made = card :: InventoryCard.Card
		made.button.LayoutOrder = index
		InventoryCard.set(made, {
			cueId = id,
			count = countLine(row),
			new = row.new == true or self.sticky[id] == true,
			equipped = items.equipped == id,
		})
		local show = matches(self.filter, id)
		made.button.Visible = show
		if show then
			table.insert(order, id)
		end
	end
	self.order = order
	self.empty.Visible = #order == 0
	if #order == 0 then
		local name = if self.filter == "All" then "" else CueThumb.rarityName(self.filter)
		self.empty.Text = WORDS.EmptyFilter:format(name)
	end

	-- The chosen cue stays chosen while it is owned; else the first shown.
	if not self.chosen or not byId[self.chosen] then
		self.chosen = order[1] or (if rows[1] then rows[1].id else nil)
	end
	for id, card in self.cards do
		InventoryCard.setChosen(card, id == self.chosen)
	end

	-- Sell all duplicates: the total it would pay now (for show; the server decides).
	local total = 0
	for _, row in rows do
		local extra = countOf(row) - 1
		if extra > 0 then
			total += extra * Cases.sellValue(row.id)
		end
	end
	self.sellAllTotal = total
	HudParts.setText(
		self.sellAll,
		if total > 0 then WORDS.SellAll:format(Format.money(total)) else WORDS.NoDuplicates
	)
	HudParts.setEnabled(self.sellAll, total > 0 and not ctx.isHeld(self.sellAll))
	self:refreshChips()
	self:refreshDetail()
	self:arrange()
end

function InventoryCues.refreshChips(self: any)
	for key, chip in self.chips do
		local chosen = key == self.filter
		HudParts.setTone(chip, if chosen then "Blue" else "White")
		local parts = HudParts.candyParts(chip)
		if parts then
			parts.label.TextColor3 = if chosen or key == "All"
				then HudParts.tone("White")
				else CueThumb.accentColor(key)
		end
	end
end

--- Show one rarity (or "All").
function InventoryCues.setFilter(self: any, key: string)
	if self.filter == key then
		return
	end
	self.filter = key
	local items = self.ctx.lastItems
	-- The chosen card stays if it is still shown, else the first of the new filter.
	if self.chosen and not matches(key, self.chosen) then
		self.chosen = nil
		for _, row in ownedRows(items) do
			if matches(key, row.id) then
				self.chosen = row.id
				break
			end
		end
	end
	self:redraw(items)
	self.ctx.ensureSelection()
end

--- Show a cue's details. `pressed`: a tap, click or A (a gamepad then moves to the buttons).
function InventoryCues.choose(self: any, id: string, pressed: boolean)
	if not self.rows[id] then
		return
	end
	if self.chosen ~= id then
		self.chosen = id
		for cardId, card in self.cards do
			InventoryCard.setChosen(card, cardId == id)
		end
		self:refreshDetail()
	end
	if pressed and self.ctx.gamepad() then
		for _, button in { self.equip, self.sell, self.sellDupes } do
			if button.Visible and button.Selectable then
				GuiService.SelectedObject = button
				return
			end
		end
	end
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

function InventoryCues.layout(self: any, geo: MenuFrame.Geo)
	self.geo = geo
	self:arrange()
end

-- Place the strip, the grid and the detail panel from the page's size.
function InventoryCues.arrange(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not geo then
		return
	end
	local span = self.ctx.span
	local W, H = geo.content.X, geo.content.Y
	local gap = span(I.GapPx)
	local stripH = span(I.StripPx)
	local stacked = H >= I.StackFromPx
	self.stacked = stacked
	local detailW = math.clamp(round(W * I.DetailShare), I.DetailMinPx, I.DetailMaxPx)
	detailW = math.min(detailW, math.max(1, round(W / 2)))
	local gridW = math.max(1, W - detailW - gap)
	local stripW = if stacked then gridW else W
	local below = stripH + gap
	self.strip.Position = UDim2.fromOffset(0, 0)
	self.strip.Size = UDim2.fromOffset(stripW, stripH)
	self.gridHolder.Position = UDim2.fromOffset(0, below)
	self.gridHolder.Size = UDim2.fromOffset(gridW, math.max(1, H - below))
	-- As many columns as keep each card CardMinPx wide (inside the scroller's padding and bar).
	local cellGap = span(I.CardGapPx)
	local inner = gridW - 2 * SC.PadPx - SC.BarPx
	local minCell = span(I.CardMinPx)
	local columns = math.max(1, math.floor((inner + cellGap) / (minCell + cellGap)))
	local cell = math.max(1, math.floor((inner - (columns - 1) * cellGap) / columns))
	self.gridLayout.CellPadding = UDim2.fromOffset(cellGap, cellGap)
	self.gridLayout.CellSize = UDim2.fromOffset(cell, round(cell * I.CardAspect))
	local detailTop = if stacked then 0 else below
	self.detail.Position = UDim2.fromOffset(gridW + gap, detailTop)
	self.detail.Size = UDim2.fromOffset(detailW, math.max(1, H - detailTop))
	self.detailSize = Vector2.new(detailW, H - detailTop)

	-- The strip: Sell all at the right, sized to its words (at most a share of the strip);
	-- the chips slide in the rest. Each is drawn at the strip's height, touch area 44.
	local textPx = span(I.ChipTextPx)
	local lip = math.floor(stripH * K.ButtonLipShare + 0.5)
	local usable = stripH - lip
	local bpad = math.max(6, math.floor(usable * 0.18))
	local icon = math.floor(usable * K.ButtonIconShare)
	local sellText = if self.sellAllTotal > 0
		then WORDS.SellAll:format(Format.money(self.sellAllTotal))
		else WORDS.NoDuplicates
	local sellW = bpad
		+ icon
		+ math.floor(bpad / 2)
		+ math.ceil(textWidth(sellText, textPx))
		+ 6
		+ bpad
	sellW = math.min(sellW, round(stripW * I.SellAllMaxShare))
	self.sellAll.AnchorPoint = Vector2.new(1, 0)
	self.sellAll.Position = UDim2.fromOffset(stripW, 0)
	self.sellAll.Size = UDim2.fromOffset(sellW, stripH)
	HudParts.setButtonTextSize(self.sellAll, textPx)
	-- The chips' scroller is a little taller than the chips: room for the gold outline.
	local room = SC.PadPx / 2
	self.chipScroll.Position = UDim2.fromOffset(0, -room)
	self.chipScroll.Size = UDim2.fromOffset(math.max(1, stripW - sellW - gap), stripH + 2 * room)
	self.chipRow.Padding = UDim.new(0, span(I.ChipGapPx))
	for _, chip in self.chips do
		local parts = HudParts.candyParts(chip)
		local words = if parts then parts.label.Text else ""
		local width =
			math.max(I.ChipMinWidthPx, math.ceil(textWidth(words, textPx)) + 6 + 2 * I.ChipPadPx)
		chip.Size = UDim2.fromOffset(width, stripH)
		HudParts.setButtonTextSize(chip, textPx)
	end
	self:arrangeDetail()
end

--------------------------------------------------------------------------------------------
-- The tab showing, NEW tags
--------------------------------------------------------------------------------------------

function InventoryCues.opened(self: any)
	-- Every open starts on every cue, with the first card chosen.
	self.filter = "All"
	self.chosen = nil
end

function InventoryCues.shown(self: any)
	if self.showing then
		return
	end
	self.showing = true
	self:markSeen()
	-- Pills left from the last time the tab showed go, the ones just marked stay.
	self:redraw(self.ctx.lastItems)
end

function InventoryCues.hidden(self: any)
	if not self.showing then
		return
	end
	self.showing = false
	self.wantMark = false
	table.clear(self.sticky)
end

function InventoryCues.closed(_self: any) end

-- Clear the NEW tags the tab shows now: one MarkSeen with their ids (at most MarkSeenMax);
-- their pills stay up (sticky) until the tab is left.
function InventoryCues.markSeen(self: any)
	local items = self.ctx.lastItems
	if type(items) ~= "table" then
		self.wantMark = true -- once the snapshot is here
		return
	end
	self.wantMark = false
	local ids = {}
	for _, row in ownedRows(items) do
		if row.new == true and #ids < Config.Items.MarkSeenMax then
			table.insert(ids, row.id)
			self.sticky[row.id] = true
		end
	end
	if #ids == 0 then
		return
	end
	local ctx = self.ctx
	task.spawn(function()
		local reply = ctx.request("MarkSeen", ids)
		if not reply.ok and (reply.reason == "Busy" or reply.reason == "TooFast") then
			task.wait(I.MarkSeenRetrySeconds)
			ctx.request("MarkSeen", ids)
		end
	end)
end

--- Where a gamepad starts on this page: the chosen card, else the first chip.
function InventoryCues.first(self: any): GuiObject?
	local card = if self.chosen then self.cards[self.chosen] else nil
	if card and card.button.Visible then
		return card.button
	end
	local firstId = self.order[1]
	if firstId and self.cards[firstId] then
		return self.cards[firstId].button
	end
	return self.chips[self.filter]
end

--------------------------------------------------------------------------------------------
-- Equip and sell (the server decides; the reply is animated)
--------------------------------------------------------------------------------------------

function InventoryCues.doEquip(self: any)
	local ctx = self.ctx
	local id = self.chosen
	if not id then
		return
	end
	ctx.hold(self.equip, function()
		local reply = ctx.request("EquipCue", id)
		if reply.ok then
			ctx.notice(WORDS.EquippedNotice:format(CueThumb.cueName(id)), "Green")
		else
			ctx.refuse(reply)
		end
	end)
end

function InventoryCues.askSell(self: any)
	local ctx = self.ctx
	local id = self.chosen
	local row = if id then self.rows[id] else nil
	if not id or not row then
		return
	end
	local items = ctx.lastItems
	-- The last copy of the equipped cue: the server would refuse it, so say why at once.
	if countOf(row) <= 1 and type(items) == "table" and items.equipped == id then
		ctx.refuse("Equipped")
		return
	end
	local function sell()
		ctx.hold(self.sell, function()
			local reply = ctx.request("SellCue", id, 1)
			if reply.ok then
				local money = if type(reply.money) == "number" then reply.money else 0
				ctx.flyMoney(money, self.sell)
				ctx.notice(WORDS.Sold:format(Format.money(money)), "Green")
			else
				ctx.refuse(reply)
			end
		end)
	end
	if not Cases.needsConfirm(id) then
		sell()
		return
	end
	ctx.confirm({
		title = WORDS.ConfirmSellTitle,
		text = WORDS.ConfirmSell:format(CueThumb.cueName(id), Format.money(Cases.sellValue(id))),
		yes = WORDS.SellYes,
		no = WORDS.SellNo,
	}, function(yes: boolean)
		if yes then
			sell()
		end
	end)
end

function InventoryCues.askSellDuplicates(self: any)
	local ctx = self.ctx
	local id = self.chosen
	local row = if id then self.rows[id] else nil
	if not id or not row then
		return
	end
	local extra = countOf(row) - 1
	if extra <= 0 then
		ctx.notice(WORDS.NothingToSell)
		return
	end
	local function sell()
		ctx.hold(self.sellDupes, function()
			local reply = ctx.request("SellDuplicates", id)
			if reply.ok then
				local money = if type(reply.money) == "number" then reply.money else 0
				if money > 0 then
					ctx.flyMoney(money, self.sellDupes)
					ctx.notice(WORDS.Sold:format(Format.money(money)), "Green")
				else
					ctx.notice(WORDS.NothingToSell)
				end
			else
				ctx.refuse(reply)
			end
		end)
	end
	if not Cases.needsConfirm(id) then
		sell()
		return
	end
	ctx.confirm({
		title = WORDS.ConfirmDuplicatesTitle,
		text = WORDS.ConfirmDuplicates:format(
			CueThumb.cueName(id),
			Format.money(extra * Cases.sellValue(id))
		),
		yes = WORDS.SellYes,
		no = WORDS.SellNo,
	}, function(yes: boolean)
		if yes then
			sell()
		end
	end)
end

function InventoryCues.askSellAll(self: any)
	local ctx = self.ctx
	if self.sellAllTotal <= 0 then
		ctx.notice(WORDS.NothingToSell)
		return
	end
	ctx.confirm({
		title = WORDS.ConfirmAllTitle,
		text = WORDS.ConfirmAll:format(Format.money(self.sellAllTotal)),
		yes = WORDS.SellYes,
		no = WORDS.SellNo,
	}, function(yes: boolean)
		if not yes then
			return
		end
		ctx.hold(self.sellAll, function()
			local reply = ctx.request("SellDuplicates")
			if reply.ok then
				local money = if type(reply.money) == "number" then reply.money else 0
				if money > 0 then
					ctx.flyMoney(money, self.sellAll)
					ctx.notice(WORDS.SoldAll:format(Format.money(money)), "Green")
				else
					ctx.notice(WORDS.NothingToSell)
				end
			else
				ctx.refuse(reply)
			end
		end)
	end)
end

return InventoryCues
