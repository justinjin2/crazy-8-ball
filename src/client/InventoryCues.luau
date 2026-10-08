--!strict
-- InventoryCues: the Inventory's Cues tab (docs/prompts/ECONOMY_UI_PROMPT.md
-- section 11; reworked by the GUI lane, designer 2026-10-03, C6).
--
--   * A strip on top: the sort button ("Sort: Rarest first"; each press moves to the next of
--     Config.UI.Inventory.SortOrders) and "Sell all duplicates: $1,234" (the total worked out
--     here from BlockOdds.sellValue for show; the server's reply is the truth), which asks first.
--   * A grid of big cue cards (InventoryCard), the whole page wide: the picture, the name,
--     "4.2% chance" (its rarity's share per Mystery block, in the rarity's colour; the copies in
--     existence left off, designer 2026-10-03), "x3", NEW, Equipped; rarer cards shimmer and
--     sparkle.
--   * A card pressed opens the cue big over the page (ref 07's size): the picture on its
--     dressed card, name, rarity, the odds line, "You own 3", Equip, and one "Sell duplicates"
--     that opens a count chooser (- 1 +, Max; "Sell 3 for $360"; a confirm from
--     Config.BlockOdds.ConfirmSellFrom up). Exclusive, Unique and Classic cues show a padlock and
--     "Can't be sold". B, Escape, the X or a press beside the card close it.
--
-- A gamepad landing on a card only moves the selection; A opens the card. NEW tags clear with
-- one MarkSeen each time the tab is shown (the new ids, at most Config.Items.MarkSeenMax); the
-- pills stay up until the tab is left, so the player sees what is new.
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local GuiService = game:GetService("GuiService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockDrop = require(Progression:WaitForChild("BlockDrop"))
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Catalog = require(Progression:WaitForChild("Catalog"))
local Format = require(Progression:WaitForChild("Format"))
local CueAssets = require(script.Parent.CueAssets)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local I = Config.UI.Inventory
local D = I.Detail
local SC = Config.UI.Menu.Scroll
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local COPIES_FOLDER = "CueCounts" -- ReplicatedStorage.CueCounts: copies in existence (Counters)
local IT = I.Items
local CLOSE_ACTION = "8ballInventoryCueClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- like a dialog's B
local OVERLAY_Z = 40

-- The sort button's orders, in its turn; the first is where it starts.
local SORTS: { string } = I.SortOrders
local SORT_NAMES: { [string]: string } = WORDS.SortOrders :: any

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

-- The rows in `sort`'s order. Ties (and "RarestFirst") keep the snapshot's order: rarest
-- first, then catalog order (rank cues highest tier first). "CommonFirst" turns the rank cues
-- round too, lowest tier first.
local function sorted(rows: { any }, sort: string): { any }
	local keyed = {}
	for index, row in rows do
		local cue = Catalog.get(row.id)
		table.insert(keyed, {
			row = row,
			index = index,
			rank = if cue then Catalog.rarityRank(cue.Rarity) else 0,
			tier = if cue and cue.Tier then table.find(Config.Ranks.Tiers, cue.Tier) else nil,
			count = countOf(row),
			name = string.lower(CueThumb.cueName(row.id)),
		})
	end
	table.sort(keyed, function(a, b)
		if sort == "CommonFirst" and a.rank ~= b.rank then
			return a.rank < b.rank
		elseif sort == "CommonFirst" and a.tier and b.tier and a.tier ~= b.tier then
			return a.tier < b.tier
		elseif sort == "MostCopies" and a.count ~= b.count then
			return a.count > b.count
		elseif sort == "NameAZ" and a.name ~= b.name then
			return a.name < b.name
		end
		return a.index < b.index
	end)
	local out = {}
	for _, entry in keyed do
		table.insert(out, entry.row)
	end
	return out
end

local function sortWords(sort: string): string
	return WORDS.Sort:format(SORT_NAMES[sort] or sort)
end

-- A cue's count line: "#412" for a Unique copy, "x3" for copies, else nothing.
local function countLine(row: any): string
	if type(row.copy) == "number" then
		return WORDS.CopyShort:format(Format.commas(row.copy))
	end
	local count = countOf(row)
	return if count > 1 then WORDS.Count:format(Format.commas(count)) else ""
end

-- A rarity's chance per Mystery block as words: "4.2%" (two significant digits under 1%).
local function percentWords(rarity: string): string
	local p = BlockDrop.rarityPercent(rarity)
	if p <= 0 then
		return "0%"
	elseif p >= 10 then
		return ("%d%%"):format(round(p))
	elseif p >= 1 then
		return (("%.1f"):format(p):gsub("%.0$", "")) .. "%"
	end
	local digits = math.max(1, -math.floor(math.log10(p)) + 1)
	return (("%." .. digits .. "f"):format(p):gsub("0+$", "")) .. "%"
end

--- A cue's chance chip on its card (concept 1, 2026-10-08): its rarity's chance per Mystery
--- block ("4.2%"), a Unique cue's chance in the Grand Opening block, nil for a cue no block
--- drops (Ranked, Exclusive, Classic).
function InventoryCues.chanceText(id: string): string?
	local cue = Catalog.get(id)
	if not cue then
		return nil
	elseif cue.Group == "Unique" then
		for _, row in BlockOdds.uniqueRows("GrandOpening") do
			if row.cue == id then
				return row.display
			end
		end
		return nil
	elseif cue.Group ~= "Block" then
		return nil
	end
	return percentWords(cue.Rarity)
end

--- A cue's odds line: "<font color>4.2%</font> chance" (rich text).
function InventoryCues.oddsLine(id: string): string?
	local cue = Catalog.get(id)
	if not cue or cue.Group == "Exclusive" or cue.Group == "Unique" then
		return nil
	end
	local c = CueThumb.accentColor(cue.Rarity)
	local hex = ("#%02X%02X%02X"):format(round(c.R * 255), round(c.G * 255), round(c.B * 255))
	local percent = ('<font color="%s">%s</font>'):format(hex, percentWords(cue.Rarity))
	return WORDS.Odds:format(percent)
end

--- The Cues page, built into `page` (the Cues tab). `ctx`: InventoryMenu's;
--- `overlay` is where the chosen cue's big card opens (the whole page).
function InventoryCues.new(page: Frame, ctx: any, overlay: Frame?): any
	local self: any = setmetatable({}, InventoryCues)
	self.page = page
	self.ctx = ctx
	self.sort = SORTS[1] -- kept while the player is in the server
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

	-- The strip: the sort button and Sell all duplicates.
	local strip = HudParts.frame(page, "Strip")
	strip.ZIndex = 2
	self.strip = strip
	self.sortButton = HudParts.candy(strip, sortWords(self.sort), function()
		self:nextSort()
	end, "Blue", "Sliders")
	self.sortButton.Name = "Sort"
	HudParts.setMinHit(self.sortButton, TOUCH)
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

	self.overlayParent = overlay or page
	self.detailOpen = false
	self.chooser = 0 -- copies the chooser would sell (0: chooser closed)
	self.closeConnections = {} :: { RBXScriptConnection }
	self:buildDetail(self.overlayParent)
	self.loading = MenuFrame.placeholder(page)

	-- Copies in existence: the attribute on ReplicatedStorage.CueCounts (made by the server).
	self.counts = ReplicatedStorage:FindFirstChild(COPIES_FOLDER)
	local function watchCounts(folder: Instance)
		self.counts = folder
		folder.AttributeChanged:Connect(function(name: string)
			if name == self.chosen then
				self:refreshDetail()
			end
			local card = self.cards[name]
			if card and self.ctx.isOpen() then
				self:redraw(self.ctx.lastItems)
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
	-- A clear layer over the page: a press beside the card closes it.
	local layer = Instance.new("TextButton")
	layer.Name = "CueDetail"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BackgroundTransparency = 1 -- no second dim (UI_STYLE 2)
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = OVERLAY_Z
	layer.Visible = false
	layer.Parent = page
	layer.Activated:Connect(function()
		self:closeDetail()
	end)
	self.layer = layer
	local box = HudParts.popupCard(layer, "Detail")
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.ZIndex = 2
	box.SelectionGroup = true
	box.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
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
	scroll.ZIndex = 3
	scroll.Parent = box
	self.detailScroll = scroll

	self.closeButton = HudParts.candy(box, "", function()
		UISound.play("Click")
		self:closeDetail()
	end, "Red", "X")
	self.closeButton.Name = "Close"
	self.closeButton.AnchorPoint = Vector2.new(1, 0)
	self.closeButton.ZIndex = 6
	HudParts.padBack(self.closeButton) -- B closes the detail
	HudParts.setMinHit(self.closeButton, TOUCH)

	-- The picture, big, on its dressed card (ref 07).
	local artBox = InventoryCard.box(scroll, "ArtBox")
	artBox.ZIndex = 3
	self.artBox = artBox
	local thumb = CueThumb.new(artBox, Catalog.Default)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.Size = UDim2.fromScale(D.ThumbShare, D.ThumbShare)
	thumb.ZIndex = 4
	self.thumb = thumb
	self.artDressing = nil :: any
	self.artKey = ""
	self.artSparkle = nil :: UIAnim.Handle?

	self.nameLabel = HudParts.text(scroll, "Name", D.NameTextPx[2], "")
	self.nameLabel.ZIndex = 4
	self.rarityLabel = HudParts.text(scroll, "Rarity", D.RarityTextPx[2], "")
	self.rarityLabel.TextWrapped = false
	self.rarityLabel.ZIndex = 4
	self.existLabel = HudParts.note(scroll, "Exist", D.LineTextPx[2], "")
	self.existLabel.TextWrapped = false
	self.existLabel.RichText = true
	self.existLabel.AutoLocalize = false
	self.existLabel.ZIndex = 4
	self.ownedLabel = HudParts.note(scroll, "Owned", D.LineTextPx[2], "")
	self.ownedLabel.TextWrapped = false
	self.ownedLabel.ZIndex = 4
	local lockRow = HudParts.frame(scroll, "LockRow")
	lockRow.ZIndex = 4
	self.lockRow = lockRow
	self.lockIcon = HudParts.icon(lockRow, "Lock", "Lock")
	self.lockIcon.ZIndex = 4
	self.lockLabel = HudParts.note(lockRow, "Words", D.LineTextPx[2], WORDS.CantSell)
	self.lockLabel.TextWrapped = false
	self.lockLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.lockLabel.ZIndex = 4

	self.equip = HudParts.candy(scroll, WORDS.Equip, function()
		self:doEquip()
	end, "Green")
	self.equip.Name = "Equip"
	self.equip.ZIndex = 4
	TutorialAnchors.set("InventoryEquip", self.equip) -- the tutorial's Equip step
	HudParts.setMinHit(self.equip, TOUCH)
	-- One "Sell duplicates": it opens the count chooser under it.
	self.sellDupes = HudParts.candy(scroll, WORDS.SellSome, function()
		self:toggleChooser()
	end, "Yellow", "Sell")
	self.sellDupes.Name = "SellDuplicates"
	self.sellDupes.ZIndex = 4
	HudParts.setMinHit(self.sellDupes, TOUCH)
	local chooser = HudParts.frame(scroll, "Chooser")
	chooser.ZIndex = 4
	chooser.Visible = false
	self.chooserRow = chooser
	self.minus = HudParts.candy(chooser, "-", function()
		self:setChooser(self.chooser - 1)
	end, "Blue")
	self.minus.ZIndex = 4
	self.countLabel =
		HudParts.text(chooser, "Count", D.NameTextPx[2], "1", HudParts.color(K.Numbers.Count))
	self.countLabel.AutoLocalize = false
	self.countLabel.TextWrapped = false
	self.countLabel.ZIndex = 4
	self.plus = HudParts.candy(chooser, "+", function()
		self:setChooser(self.chooser + 1)
	end, "Blue")
	self.plus.ZIndex = 4
	self.maxButton = HudParts.candy(chooser, WORDS.Max, function()
		self:setChooser(math.huge)
	end, "Blue")
	self.maxButton.ZIndex = 4
	self.sellConfirm = HudParts.candy(scroll, "", function()
		self:askSellCount()
	end, "Red", "Sell")
	self.sellConfirm.Name = "SellCount"
	self.sellConfirm.ZIndex = 4
	self.sellConfirm.Visible = false
	HudParts.setMinHit(self.sellConfirm, TOUCH)
	for _, button in { self.minus, self.plus, self.maxButton } do
		HudParts.setMinHit(button, TOUCH)
	end
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

-- The chosen cue's words, buttons and picture (then lays the card out).
function InventoryCues.refreshDetail(self: any)
	local ctx = self.ctx
	local id: string? = self.chosen
	local row = if id then self.rows[id] else nil
	if not id or not row then
		self:closeDetail()
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
		if self.artSparkle then
			self.artSparkle.stop()
			self.artSparkle = nil
		end
		local tint = if cue.Tier then CueThumb.cueColor(id) else nil
		self.artDressing = CueThumb.dress(self.artBox, cue.Rarity, tint)
		if Catalog.rarityRank(cue.Rarity) >= Catalog.rarityRank(IT.ShimmerFromRarity) then
			self.artSparkle = UIAnim.sparkle(self.artBox, CueThumb.accentColor(cue.Rarity))
		end
		self.artKey = key
	end
	self.nameLabel.Text = CueThumb.cueName(id)
	self.rarityLabel.Text = CueThumb.rarityName(cue.Rarity)
	self.rarityLabel.TextColor3 = CueThumb.cueColor(id)
	local copies = self:copies(id)
	local odds = InventoryCues.oddsLine(id)
	if odds == nil and copies ~= nil and copies >= 1 then
		odds = (if copies == 1 then WORDS.ExistOne else WORDS.Exist):format(Format.commas(copies))
	end
	self.existLabel.Text = odds or ""
	self.existLabel.Visible = odds ~= nil
	local count = countOf(row)
	self.ownedLabel.Text = if type(row.copy) == "number"
		then WORDS.Copy:format(Format.commas(row.copy))
		else WORDS.Owned:format(Format.commas(count))
	local value = BlockOdds.sellValue(id)
	local sellable = value > 0
	self.lockRow.Visible = not sellable

	-- Equip: grey and still once this cue is the equipped one.
	local items = ctx.lastItems
	local equipped = type(items) == "table" and items.equipped == id
	HudParts.setText(self.equip, if equipped then WORDS.Equipped else WORDS.Equip)
	HudParts.setTone(self.equip, if equipped then "Grey" else "Green")
	HudParts.setButtonIcon(self.equip, if equipped then "Check" else nil)
	HudParts.setEnabled(self.equip, not equipped and not ctx.isHeld(self.equip))

	-- Sell duplicates: only with a copy to spare; the chooser keeps its count in range.
	-- An open chooser takes the button's place (one row less on a short screen).
	local extra = count - 1
	local canSell = sellable and extra > 0
	if not canSell then
		self.chooser = 0
	elseif self.chooser > 0 then
		self.chooser = math.clamp(self.chooser, 1, extra)
	end
	local open = self.chooser > 0
	self.sellDupes.Visible = canSell and not open
	HudParts.setEnabled(self.sellDupes, not ctx.isHeld(self.sellConfirm))
	self.chooserRow.Visible = open
	self.sellConfirm.Visible = open
	if open then
		self.countLabel.Text = Format.commas(self.chooser)
		HudParts.setText(
			self.sellConfirm,
			WORDS.SellCount:format(Format.commas(self.chooser), Format.money(self.chooser * value))
		)
		HudParts.setEnabled(self.minus, self.chooser > 1)
		HudParts.setEnabled(self.plus, self.chooser < extra)
		HudParts.setEnabled(self.maxButton, self.chooser < extra)
		HudParts.setEnabled(self.sellConfirm, not ctx.isHeld(self.sellConfirm))
	end
	self:arrangeDetail()
end

-- Lay the big card out: the picture on top, the words centred under it, the buttons full
-- width; on a wide card (a landscape phone, a short PC window) the picture fills the left and
-- the words and buttons stand beside it. Its canvas grows to fit.
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
	local closeSize = math.min(44, span(D.ButtonPx))
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(size.X - pad, pad)
	-- The words and buttons are laid out first from y = 0; the picture takes what is left (up
	-- to its share), so an open chooser on a short screen shrinks the picture, not the buttons.
	local wide = self.detailWide == true
	local maxArt = if wide
		then math.min(size.Y - 2 * pad, IT.BigWideArtMaxPx, round(w * IT.BigWideArtShare))
		else math.min(inner - 2 * closeSize, round(size.Y * IT.BigArtShare))
	-- The words' column: under the picture, or beside it (clear of the X).
	local x0 = if wide then pad * 2 + maxArt else pad
	local colW = if wide then w - x0 - pad - closeSize - gap else inner
	local nameSize =
		math.max(span(D.NameTextPx), round(K.Big.Heading * (0.8 + 0.2 * (maxArt / 300))))
	local raritySize, lineSize = span(D.RarityTextPx), span(D.LineTextPx) + 2
	HudParts.setTextSize(self.nameLabel, nameSize)
	HudParts.setTextSize(self.rarityLabel, raritySize)
	HudParts.setTextSize(self.existLabel, lineSize)
	HudParts.setTextSize(self.ownedLabel, lineSize)
	HudParts.setTextSize(self.lockLabel, lineSize)
	for _, label in { self.nameLabel, self.rarityLabel, self.existLabel, self.ownedLabel } do
		label.TextXAlignment = Enum.TextXAlignment.Center
	end
	local y = 0
	local function place(label: TextLabel, height: number)
		label.Position = UDim2.fromOffset(x0, y)
		label.Size = UDim2.fromOffset(colW, height)
		y += height
	end
	place(self.nameLabel, math.ceil(textHeight(self.nameLabel.Text, nameSize, colW - 4)) + 4)
	place(self.rarityLabel, raritySize + 6)
	if self.existLabel.Visible then
		place(self.existLabel, lineSize + 4)
	end
	place(self.ownedLabel, lineSize + 4)
	if self.lockRow.Visible then
		local lock = span(D.LockPx)
		local words = math.ceil(textWidth(self.lockLabel.Text, lineSize)) + 6
		local rowW = math.min(colW, lock + 4 + words)
		self.lockRow.Position = UDim2.fromOffset(x0 + round((colW - rowW) / 2), y + 2)
		self.lockRow.Size = UDim2.fromOffset(rowW, math.max(lock, lineSize + 4))
		self.lockIcon.Size = UDim2.fromOffset(lock, lock)
		self.lockLabel.Position = UDim2.fromOffset(lock + 4, 0)
		self.lockLabel.Size =
			UDim2.fromOffset(math.max(1, rowW - lock - 4), math.max(lock, lineSize + 4))
		y += math.max(lock, lineSize + 4) + 2
	end
	y += gap

	-- The buttons, full width; the chooser's row (- 3 + Max) and its Sell under them.
	local buttonH, buttonText = span(D.ButtonPx), span(D.ButtonTextPx)
	for _, button in { self.equip, self.sellDupes } do
		if button.Visible then
			button.Position = UDim2.fromOffset(x0, y)
			button.Size = UDim2.fromOffset(colW, buttonH)
			HudParts.setButtonTextSize(button, buttonText)
			y += buttonH + gap
		end
	end
	if self.chooserRow.Visible then
		local rowH = span(IT.ChooserPx)
		self.chooserRow.Position = UDim2.fromOffset(x0, y)
		self.chooserRow.Size = UDim2.fromOffset(colW, rowH)
		local maxW = math.max(rowH * 2, math.ceil(textWidth(WORDS.Max, buttonText)) + 24)
		local countW = math.max(rowH, colW - 2 * rowH - maxW - 3 * gap)
		self.minus.Position = UDim2.fromOffset(0, 0)
		self.minus.Size = UDim2.fromOffset(rowH, rowH)
		HudParts.setTextSize(self.countLabel, rowH - 6)
		self.countLabel.Position = UDim2.fromOffset(rowH + gap, 0)
		self.countLabel.Size = UDim2.fromOffset(countW, rowH)
		self.plus.Position = UDim2.fromOffset(rowH + countW + 2 * gap, 0)
		self.plus.Size = UDim2.fromOffset(rowH, rowH)
		self.maxButton.Position = UDim2.fromOffset(colW - maxW, 0)
		self.maxButton.Size = UDim2.fromOffset(maxW, rowH)
		HudParts.setButtonTextSize(self.minus, math.max(buttonText, rowH - 12)) -- a big - and +
		HudParts.setButtonTextSize(self.plus, math.max(buttonText, rowH - 12))
		HudParts.setButtonTextSize(self.maxButton, buttonText)
		y += rowH + gap
		self.sellConfirm.Position = UDim2.fromOffset(x0, y)
		self.sellConfirm.Size = UDim2.fromOffset(colW, buttonH)
		HudParts.setButtonTextSize(self.sellConfirm, buttonText)
		y += buttonH + gap
	end
	local below = y - gap
	local base
	if wide then
		self.artBox.Position = UDim2.fromOffset(pad, math.max(pad, round((size.Y - maxArt) / 2)))
		self.artBox.Size = UDim2.fromOffset(maxArt, maxArt)
		base = math.max(pad, round((size.Y - below) / 2))
	else
		local art = math.max(
			math.min(maxArt, IT.BigArtMinPx),
			math.min(maxArt, size.Y - 2 * pad - gap - below)
		)
		self.artBox.Position = UDim2.fromOffset(round((w - art) / 2), pad)
		self.artBox.Size = UDim2.fromOffset(art, art)
		base = pad + art + gap
	end
	for _, object in
		{
			self.nameLabel,
			self.rarityLabel,
			self.existLabel,
			self.ownedLabel,
			self.lockRow,
			self.equip,
			self.sellDupes,
			self.chooserRow,
			self.sellConfirm,
		} :: { GuiObject }
	do
		if object.Visible then -- a hidden one was not placed this time
			object.Position =
				UDim2.fromOffset(object.Position.X.Offset, object.Position.Y.Offset + base)
		end
	end
	self.detailScroll.CanvasSize =
		UDim2.fromOffset(0, math.max(base + below + pad, if wide then maxArt + 2 * pad else 0))
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
		self:closeDetail()
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
	for index, row in sorted(rows, self.sort) do
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
			chance = InventoryCues.chanceText(id),
		})
		table.insert(order, id)
	end
	self.order = order
	-- The tutorial's Equip step points at the first card that is not the equipped cue.
	local unequipped: GuiObject? = nil
	for _, id in order do
		if id ~= items.equipped then
			unequipped = self.cards[id].button
			break
		end
	end
	TutorialAnchors.set("InventoryCue", unequipped)
	self.empty.Visible = #order == 0
	self.empty.Text = WORDS.Empty

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
			total += extra * BlockOdds.sellValue(row.id)
		end
	end
	self.sellAllTotal = total
	HudParts.setText(
		self.sellAll,
		if total > 0 then WORDS.SellAll:format(Format.money(total)) else WORDS.NoDuplicates
	)
	HudParts.setEnabled(self.sellAll, total > 0 and not ctx.isHeld(self.sellAll))
	HudParts.setText(self.sortButton, sortWords(self.sort))
	if self.detailOpen then
		self:refreshDetail()
	end
	self:arrange()
end

--- The sort button: the next order, round. The chosen card stays chosen; the grid goes back
--- to its top so the new order reads from its start.
function InventoryCues.nextSort(self: any)
	local index = table.find(SORTS, self.sort) or 0
	self.sort = SORTS[index % #SORTS + 1]
	self:redraw(self.ctx.lastItems)
	self.grid.CanvasPosition = Vector2.zero
end

--- Choose a cue: `pressed` (a tap, click or A) opens it big; a gamepad landing on its card
--- only marks it.
function InventoryCues.choose(self: any, id: string, pressed: boolean)
	if not self.rows[id] then
		return
	end
	if self.chosen ~= id then
		self.chosen = id
		self.chooser = 0
		-- Download its look while the details are read, so Equip shows it at once.
		CueAssets.preload(id)
		for cardId, card in self.cards do
			InventoryCard.setChosen(card, cardId == id)
		end
	end
	if pressed then
		self:openDetail()
	end
end

--- Open the chosen cue's big card over the page.
function InventoryCues.openDetail(self: any)
	if not self.chosen then
		return
	end
	local frame = self.ctx.frame
	self:refreshDetail()
	if not self.detailOpen then
		self.detailOpen = true
		self.layer.Visible = true
		self.detail.Visible = false
		UIAnim.popIn(self.detail)
		UIAnim.glowBurst(self.detail, HudParts.tone("Gold"), 0.25)
		self.previous = GuiService.SelectedObject
		self.dialog = {
			cancel = function()
				self:closeDetail()
			end,
			isOpen = function(): boolean
				return self.detailOpen
			end,
		}
		table.insert(frame.dialogs, self.dialog)
		ContextActionService:BindActionAtPriority(
			CLOSE_ACTION,
			function(_name: string, state: Enum.UserInputState)
				if state == Enum.UserInputState.Begin then
					self:closeDetail()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			CLOSE_PRIORITY,
			Enum.KeyCode.ButtonB
		)
		table.insert(
			self.closeConnections,
			UserInputService.InputBegan:Connect(function(input: InputObject)
				if input.KeyCode == Enum.KeyCode.Escape then
					Menus.swallowEscape(input)
					self:closeDetail()
				end
			end)
		)
	end
	self:arrange()
	if self.ctx.gamepad() then
		for _, button in { self.equip, self.sellDupes, self.closeButton } do
			if button.Visible and button.Selectable then
				GuiService.SelectedObject = button
				return
			end
		end
	end
end

--- Close the big card (nothing happens if it is closed); a gamepad goes back to the card.
function InventoryCues.closeDetail(self: any)
	if not self.detailOpen then
		return
	end
	self.detailOpen = false
	self.chooser = 0
	local frame = self.ctx.frame
	local at = table.find(frame.dialogs, self.dialog)
	if at then
		table.remove(frame.dialogs, at)
	end
	ContextActionService:UnbindAction(CLOSE_ACTION)
	for _, connection in self.closeConnections do
		connection:Disconnect()
	end
	table.clear(self.closeConnections)
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.layer) then
		local card = if self.chosen then self.cards[self.chosen] else nil
		GuiService.SelectedObject = if card and card.button.Parent then card.button else nil
	end
	UIAnim.popOut(self.detail, function()
		if not self.detailOpen then
			self.layer.Visible = false
		end
	end)
end

--- The count chooser: open at 1, or closed again.
function InventoryCues.toggleChooser(self: any)
	UISound.play("Click")
	self.chooser = if self.chooser > 0 then 0 else 1
	self:refreshDetail()
	if self.chooser > 0 then
		-- The Sell button in view (a short card scrolls).
		local scroll = self.detailScroll :: ScrollingFrame
		scroll.CanvasPosition = Vector2.new(0, math.max(0, scroll.AbsoluteCanvasSize.Y))
		if self.ctx.gamepad() then
			GuiService.SelectedObject = self.sellConfirm
		end
	end
end

--- Set the chooser's count (kept between 1 and the copies to spare; math.huge is Max).
function InventoryCues.setChooser(self: any, n: number)
	local row = if self.chosen then self.rows[self.chosen] else nil
	if not row then
		return
	end
	UISound.play("Click")
	local extra = countOf(row) - 1
	self.chooser = math.clamp(if n == math.huge then extra else n, 1, math.max(1, extra))
	self:refreshDetail()
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
	self.stacked = true
	local gridW = math.max(1, W)
	local stripW = W
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
	local units = Config.UI.CueCard.Units
	self.gridLayout.CellSize = UDim2.fromOffset(cell, round(cell * units[2] / units[1]))
	-- The big card: ref 07's size, as big as the page allows.
	local parent: Frame = self.overlayParent
	local scale = MenuFrame.scaleOf(parent)
	local area = parent.AbsoluteSize / scale
	if area.X <= 1 then
		area = Vector2.new(W, H)
	end
	local cardH = math.max(1, area.Y - 2 * gap)
	local wide = area.X - 2 * gap >= cardH * IT.BigWideRatio
	self.detailWide = wide
	local cardW =
		math.min(if wide then IT.BigWideMaxWidthPx else IT.BigCardMaxWidthPx, area.X - 2 * gap)
	self.detail.Size = UDim2.fromOffset(cardW, cardH)
	self.detailSize = Vector2.new(cardW, cardH)

	-- The strip: the sort button at the left, as wide as its longest words so it keeps still as
	-- it turns; Sell all at the right, sized to its words (each at most a share of the strip).
	-- Both are drawn at the strip's height, touch area 44.
	local textPx = span(I.StripTextPx)
	local lip = math.floor(stripH * K.ButtonLipShare + 0.5)
	local usable = stripH - lip
	local bpad = math.max(6, math.floor(usable * 0.18))
	local icon = math.floor(usable * K.ButtonIconShare)
	local sellText = if self.sellAllTotal > 0
		then WORDS.SellAll:format(Format.money(self.sellAllTotal))
		else WORDS.NoDuplicates
	local function buttonWidth(words: string): number
		return bpad + icon + math.floor(bpad / 2) + math.ceil(textWidth(words, textPx)) + 6 + bpad
	end
	local sellW = math.min(buttonWidth(sellText), round(stripW * I.SellAllMaxShare))
	self.sellAll.AnchorPoint = Vector2.new(1, 0)
	self.sellAll.Position = UDim2.fromOffset(stripW, 0)
	self.sellAll.Size = UDim2.fromOffset(sellW, stripH)
	HudParts.setButtonTextSize(self.sellAll, textPx)
	local sortW = 0
	for _, sort in SORTS do
		sortW = math.max(sortW, buttonWidth(sortWords(sort)))
	end
	sortW = math.min(sortW, round(stripW * I.SortMaxShare), math.max(1, stripW - sellW - gap))
	self.sortButton.Position = UDim2.fromOffset(0, 0)
	self.sortButton.Size = UDim2.fromOffset(sortW, stripH)
	HudParts.setButtonTextSize(self.sortButton, textPx)
	self:arrangeDetail()
end

--------------------------------------------------------------------------------------------
-- The tab showing, NEW tags
--------------------------------------------------------------------------------------------

function InventoryCues.opened(self: any)
	-- Every open starts with the first card chosen (the order stays as the player left it).
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
	self:closeDetail()
end

function InventoryCues.closed(self: any)
	self:closeDetail()
end

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

--- Where a gamepad starts on this page: the chosen card, else the sort button.
function InventoryCues.first(self: any): GuiObject?
	local card = if self.chosen then self.cards[self.chosen] else nil
	if card and card.button.Visible then
		return card.button
	end
	local firstId = self.order[1]
	if firstId and self.cards[firstId] then
		return self.cards[firstId].button
	end
	return self.sortButton
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

--- Sell the chooser's count of the chosen cue (asks first from Config.BlockOdds.ConfirmSellFrom).
function InventoryCues.askSellCount(self: any)
	local ctx = self.ctx
	local id = self.chosen
	local row = if id then self.rows[id] else nil
	local count = self.chooser
	if not id or not row or count < 1 then
		return
	end
	local function sell()
		ctx.hold(self.sellConfirm, function()
			local reply = ctx.request("SellCue", id, count)
			if reply.ok then
				local money = if type(reply.money) == "number" then reply.money else 0
				ctx.flyMoney(money, self.sellConfirm)
				ctx.notice(WORDS.Sold:format(Format.money(money)), "Green")
				self.chooser = 0
			else
				ctx.refuse(reply)
			end
		end)
	end
	if not BlockOdds.needsConfirm(id) then
		sell()
		return
	end
	ctx.confirm({
		title = WORDS.ConfirmDuplicatesTitle,
		text = WORDS.ConfirmSellCount:format(
			Format.commas(count),
			CueThumb.cueName(id),
			Format.money(count * BlockOdds.sellValue(id))
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
