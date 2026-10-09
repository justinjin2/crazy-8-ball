--!strict
-- InventoryCues: the Cues menu's My Cues view (docs/prompts/CUES_LIVELY_PROMPT.md, concept 2,
-- approved round 2, 2026-10-08).
--
--   * A grid of cue cards (InventoryCard), Config.UI.Inventory.Columns a row: the picture, the
--     name, the rarity bar, the chance chip, "x3", NEW, Equipped, a copy number ("#412") over
--     the name. The menu is as tall as two whole rows with the third peeking (heightFor); a
--     screen too short for that shrinks the cards and the grid stays centred. The first cards
--     pop in with the open, by their place in reading order (Stage "Card1".."Card15").
--   * Sort and Sell dupes live on the rail beside the panel (CuesRail): Sort turns the order
--     (Config.UI.Inventory.SortOrders), Sell dupes sells every duplicate (the total worked out
--     here from BlockOdds.sellValue for show; the server's reply is the truth) and asks first.
--   * A card pressed slams in its big card over the page: the same card, bare (no pills: the
--     words beside it say them), and beside it the name, the rarity, "4.2% chance · 1,284
--     exist", "You own 3" (or a Unique's "Copy #412"), the padlock's "Can't be sold", Equip
--     and one "Sell" that opens a count chooser (- 1 +, Max; "Sell 3 for $360"; a confirm from
--     Config.BlockOdds.ConfirmSellFrom up). Every copy may be sold, the last one too (designer,
--     2026-10-09: "if they just want to delete common cues they dont like"), after a warning
--     that it is gone for good; the equipped cue keeps one (the server's rule). B, Escape, the
--     X or a press beside the card close it.
--
-- A gamepad landing on a card only moves the selection; A opens the card. NEW tags clear with
-- one MarkSeen each time the view is shown (the new ids, at most Config.Items.MarkSeenMax); the
-- pills stay up until the view is left, so the player sees what is new.
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
local UNITS = Config.UI.CueCard.Units
local WORDS = Strings.Menus.Inventory
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local COPIES_FOLDER = "CueCounts" -- ReplicatedStorage.CueCounts: copies in existence (Counters)
local IT = I.Items
local CLOSE_ACTION = "8ballInventoryCueClose"
local CLOSE_PRIORITY = Enum.ContextActionPriority.High.Value + 30 -- like a dialog's B
local OVERLAY_Z = 40

-- The Sort tile's orders, in its turn; the first is where it starts.
local SORTS: { string } = I.SortOrders
local SORT_NAMES: { [string]: string } = WORDS.SortOrders :: any

local InventoryCues = {}
InventoryCues.__index = InventoryCues

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
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

-- The copies of `row` that may be sold: all of them, but the equipped cue keeps one
-- (Inventory.canSell's "Equipped").
local function spareOf(ctx: any, row: any): number
	local items = ctx.lastItems
	local equipped = type(items) == "table" and items.equipped == row.id
	return countOf(row) - (if equipped then 1 else 0)
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

-- A cue's count on its card: "x3" for copies, else nothing.
local function countLine(row: any): string
	if type(row.copy) == "number" then
		return ""
	end
	local count = countOf(row)
	return if count > 1 then WORDS.Count:format(Format.commas(count)) else ""
end

-- A numbered copy's number over the card's name: "#412", else nothing.
local function copyLine(row: any): string
	return if type(row.copy) == "number"
		then WORDS.CopyShort:format(Format.commas(row.copy))
		else ""
end

-- The first week's day that gives cue `id` (the Week One Cue: 7), else nil.
local function firstWeekDay(id: string): number?
	for day, row in Config.Daily.FirstWeek do
		if row.Cues and table.find(row.Cues, id) then
			return day
		end
	end
	return nil
end

-- A rarity's chance per Mystery block as words: "4.2%" (two significant digits under 1%),
-- live during the Grand Opening Luck.
local function percentWords(rarity: string): string
	local luck = BlockDrop.luckLive(workspace:GetServerTimeNow())
	local p = BlockDrop.rarityPercent(rarity, { luck = luck })
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
--- block ("4.2%"), a Unique cue's chance in the Grand Opening block, the first week's day for
--- a login cue ("Day 7": the Week One Cue), nil for a cue no block drops (Ranked, Exclusive,
--- Classic).
function InventoryCues.chanceText(id: string): string?
	local cue = Catalog.get(id)
	local day = firstWeekDay(id)
	if not cue then
		return nil
	elseif day then
		return WORDS.FirstWeekChip:format(day)
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

--- A cue's odds line: "<font color>4.2%</font> chance" (rich text); a login cue's day ("Day 7 of
--- your first week").
function InventoryCues.oddsLine(id: string): string?
	local cue = Catalog.get(id)
	local day = firstWeekDay(id)
	if cue and day then
		return WORDS.FirstWeekOdds:format(day)
	elseif
		not cue
		or cue.Group == "Exclusive"
		or cue.Group == "Unique"
		or (cue.Group == "Block" and #cue.Blocks == 0) -- in no block (the Week One Cue)
	then
		return nil
	end
	local c = CueThumb.accentColor(cue.Rarity)
	local hex = ("#%02X%02X%02X"):format(round(c.R * 255), round(c.G * 255), round(c.B * 255))
	local percent = ('<font color="%s">%s</font>'):format(hex, percentWords(cue.Rarity))
	return WORDS.Odds:format(percent)
end

--- The line under a cue's rarity (the big card, the Index): its odds and how many copies
--- exist ("4.2% chance · 1,284 exist"), either alone, or nil with neither.
function InventoryCues.factsLine(id: string, copies: number?): string?
	local odds = InventoryCues.oddsLine(id)
	local exist = nil
	if copies and copies >= 1 then
		exist = (if copies == 1 then WORDS.ExistOne else WORDS.Exist):format(Format.commas(copies))
	end
	if odds and exist then
		return WORDS.Joined:format(odds, exist)
	end
	return odds or exist
end

-- The grid's card size for a grid `gridW` wide, `t` of the way from a phone to a full panel.
local function cellFor(gridW: number, t: number): (number, number, number)
	local gap = span(I.CardGapPx, t)
	local inner = gridW - 2 * SC.PadPx - SC.BarPx
	local cell = math.max(1, math.floor((inner - (I.Columns - 1) * gap) / I.Columns))
	return cell, round(cell * UNITS[2] / UNITS[1]), gap
end

--- The view's height for a grid `gridW` wide: two whole rows of cards and the third peeking
--- (the menu's frame.fitHeight).
function InventoryCues.heightFor(gridW: number, t: number): number
	local _, cellH, gap = cellFor(gridW, t)
	return SC.PadPx + 2 * (cellH + gap) + span(I.PeekPx, t)
end

--- My Cues, built into `page`. `ctx`: InventoryMenu's; `overlay` is where the chosen cue's big
--- card opens (the whole page).
function InventoryCues.new(page: Frame, ctx: any, overlay: Frame?): any
	local self: any = setmetatable({}, InventoryCues)
	self.page = page
	self.ctx = ctx
	self.sort = SORTS[1] -- every open starts on Rarest first (designer, 2026-10-08)
	self.chosen = nil :: string?
	-- The cards by their place in the grid (reading order): a card keeps its place and shows
	-- whichever cue is there, so the open's Stage ids (Card1..) stay on the same objects.
	self.slots = {} :: { InventoryCard.Card }
	self.rows = {} :: { [string]: any } -- the snapshot's rows by id, for the big card
	self.order = {} :: { string } -- the ids shown now, in order
	self.sticky = {} :: { [string]: boolean } -- NEW while the view is up, though already marked
	self.showing = false
	self.wantMark = false
	self.geo = nil :: MenuFrame.Geo?
	self.stage = nil :: any
	self.sellAllTotal = 0

	-- The grid.
	local gridHolder = HudParts.frame(page, "GridHolder")
	gridHolder.ZIndex = 2
	self.gridHolder = gridHolder
	-- MenuFrame's scroller (its padding, bar and gamepad scrolling) with a grid sized here.
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
			if name == self.chosen and self.detailOpen then
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
				if self.detailOpen then
					self:refreshDetail()
				end
			end
		end)
	end
	return self
end

--- The open's pieces: the first cards by their place (added as they are made, in `slot`).
function InventoryCues.register(self: any, stage: any)
	self.stage = stage
	for index, card in self.slots :: { InventoryCard.Card } do
		self:stageCard(index, card)
	end
end

-- Card `index` (among the first StagedCards) is a piece of the open; its motion runs again as
-- it lands (`hold` stilled it for the pop).
function InventoryCues.stageCard(self: any, index: number, card: InventoryCard.Card)
	if self.stage and index <= I.StagedCards then
		self.stage:add("Card" .. index, card.button, function()
			InventoryCard.hold(card, false)
		end)
	end
end

--- The staged cards are about to pop in (the open, a flip back to My Cues): their motion
--- waits until each lands, or its glows would show before the card.
function InventoryCues.hold(self: any)
	for index = 1, math.min(#self.slots, I.StagedCards) do
		InventoryCard.hold(self.slots[index], true)
	end
end

--------------------------------------------------------------------------------------------
-- The big card
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
	HudParts.dots(box) -- the lively sheet's tiny pool balls, not the big 8-balls
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.ZIndex = 2
	box.SelectionGroup = true
	box.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	box.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.detail = box

	-- The cue's own card, bare, on the left (it does not press or light up).
	local card = InventoryCard.new(box, {
		name = "BigCard",
		onPress = function() end,
	})
	card.button.Selectable = false
	card.button.Interactable = false
	card.button.ZIndex = 3
	self.bigCard = card

	-- The words and buttons beside it; they scroll when a short screen or a long translation
	-- needs more room.
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Scroll"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
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
	HudParts.padBack(self.closeButton) -- B closes the big card
	HudParts.setMinHit(self.closeButton, TOUCH)

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
	-- One "Sell": it opens the count chooser under it.
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

-- The chosen cue's card, words and buttons (then lays the big card out).
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
	InventoryCard.set(self.bigCard, { cueId = id, copy = copyLine(row), bare = true })
	self.nameLabel.Text = CueThumb.cueName(id)
	self.rarityLabel.Text = CueThumb.rarityName(cue.Rarity)
	self.rarityLabel.TextColor3 = CueThumb.cueColor(id)
	local facts = InventoryCues.factsLine(id, self:copies(id))
	self.existLabel.Text = facts or ""
	self.existLabel.Visible = facts ~= nil
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

	-- Sell: any copy (the equipped cue keeps one); the chooser keeps its count in range.
	-- An open chooser takes the button's place (one row less on a short screen).
	local extra = spareOf(ctx, row)
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

-- Lay the big card out: the cue's card on the left as tall as the popup allows (at most
-- Items.BigCardShare of its width), the words and buttons beside it, centred up and down,
-- clear of the X. Its column scrolls when it is taller than the popup.
function InventoryCues.arrangeDetail(self: any)
	local ctx = self.ctx
	local size = self.detailSize :: Vector2?
	if not size or size.X <= 0 then
		return
	end
	local span1 = ctx.span
	local pad, gap = span1(D.PadPx), span1(D.GapPx)
	local closeSize = math.min(44, span1(D.ButtonPx))
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(size.X - pad, pad)

	-- The card.
	local cardH = math.max(1, size.Y - 2 * pad)
	local cardW = round(cardH * UNITS[1] / UNITS[2])
	local maxW = round(size.X * IT.BigCardShare)
	if cardW > maxW then
		cardW = maxW
		cardH = round(cardW * UNITS[2] / UNITS[1])
	end
	self.bigCard.button.Position = UDim2.fromOffset(pad, round((size.Y - cardH) / 2))
	self.bigCard.button.Size = UDim2.fromOffset(cardW, cardH)

	-- The column beside it.
	local x0 = 2 * pad + cardW
	local colW = math.max(1, size.X - x0 - pad - closeSize - gap)
	local colH = size.Y
	self.detailScroll.Position = UDim2.fromOffset(x0, 0)
	self.detailScroll.Size = UDim2.fromOffset(colW + SC.BarPx, colH)
	local nameSize = math.max(span1(D.NameTextPx), round(K.Big.Heading * 0.8))
	local raritySize, lineSize = span1(D.RarityTextPx), span1(D.LineTextPx) + 2
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
		label.Position = UDim2.fromOffset(0, y)
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
		local lock = span1(D.LockPx)
		local words = math.ceil(textWidth(self.lockLabel.Text, lineSize)) + 6
		local rowW = math.min(colW, lock + 4 + words)
		self.lockRow.Position = UDim2.fromOffset(round((colW - rowW) / 2), y + 2)
		self.lockRow.Size = UDim2.fromOffset(rowW, math.max(lock, lineSize + 4))
		self.lockIcon.Size = UDim2.fromOffset(lock, lock)
		self.lockLabel.Position = UDim2.fromOffset(lock + 4, 0)
		self.lockLabel.Size =
			UDim2.fromOffset(math.max(1, rowW - lock - 4), math.max(lock, lineSize + 4))
		y += math.max(lock, lineSize + 4) + 2
	end
	y += gap

	-- The buttons, inset from the column's sides so their outline and their hover growth are
	-- never cut by its edge (designer, 2026-10-08: Equip's end was cut and it looked jammed
	-- against the card); the chooser's row (- 3 + Max) and its Sell under them.
	local buttonH, buttonText = span1(D.ButtonPx), span1(D.ButtonTextPx)
	local inset = math.ceil(K.SelectedStrokePx + colW * (K.SelectedScale - 1) / 2)
	local buttonW = math.max(1, colW - 2 * inset)
	for _, button in { self.equip, self.sellDupes } do
		if button.Visible then
			button.Position = UDim2.fromOffset(inset, y)
			button.Size = UDim2.fromOffset(buttonW, buttonH)
			HudParts.setButtonTextSize(button, buttonText)
			y += buttonH + gap
		end
	end
	if self.chooserRow.Visible then
		local rowH = span1(IT.ChooserPx)
		self.chooserRow.Position = UDim2.fromOffset(inset, y)
		self.chooserRow.Size = UDim2.fromOffset(buttonW, rowH)
		local maxBtnW = math.max(rowH * 2, math.ceil(textWidth(WORDS.Max, buttonText)) + 24)
		local countW = math.max(rowH, buttonW - 2 * rowH - maxBtnW - 3 * gap)
		self.minus.Position = UDim2.fromOffset(0, 0)
		self.minus.Size = UDim2.fromOffset(rowH, rowH)
		HudParts.setTextSize(self.countLabel, rowH - 6)
		self.countLabel.Position = UDim2.fromOffset(rowH + gap, 0)
		self.countLabel.Size = UDim2.fromOffset(countW, rowH)
		self.plus.Position = UDim2.fromOffset(rowH + countW + 2 * gap, 0)
		self.plus.Size = UDim2.fromOffset(rowH, rowH)
		self.maxButton.Position = UDim2.fromOffset(buttonW - maxBtnW, 0)
		self.maxButton.Size = UDim2.fromOffset(maxBtnW, rowH)
		HudParts.setButtonTextSize(self.minus, math.max(buttonText, rowH - 12)) -- a big - and +
		HudParts.setButtonTextSize(self.plus, math.max(buttonText, rowH - 12))
		HudParts.setButtonTextSize(self.maxButton, buttonText)
		y += rowH + gap
		self.sellConfirm.Position = UDim2.fromOffset(inset, y)
		self.sellConfirm.Size = UDim2.fromOffset(buttonW, buttonH)
		HudParts.setButtonTextSize(self.sellConfirm, buttonText)
		y += buttonH + gap
	end
	-- Centred up and down when it fits; else it scrolls from the top.
	local used = y - gap
	local base = math.max(pad, round((colH - used) / 2))
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
	self.detailScroll.CanvasSize = UDim2.fromOffset(0, base + used + pad)
end

--------------------------------------------------------------------------------------------
-- Drawing from the snapshot
--------------------------------------------------------------------------------------------

--- The red dot on the My Cues tile: how many owned cues are NEW.
function InventoryCues.dot(_self: any, items: any): number
	local n = 0
	for _, row in ownedRows(items) do
		if row.new == true then
			n += 1
		end
	end
	return n
end

-- The card in grid place `index`, made (and staged, among the first) when first needed.
function InventoryCues.slot(self: any, index: number): InventoryCard.Card
	local card = self.slots[index]
	if card then
		return card
	end
	local made: InventoryCard.Card
	made = InventoryCard.new(self.grid, {
		name = "Card" .. index,
		order = index,
		onPress = function()
			self:choose(made.cueId, true)
		end,
		onSelect = function()
			self:choose(made.cueId, false)
		end,
	})
	self.slots[index] = made
	self:stageCard(index, made)
	return made
end

-- The grid place showing cue `id`, or nil.
function InventoryCues.cardOf(self: any, id: string?): InventoryCard.Card?
	if not id then
		return nil
	end
	for index, shown in self.order :: { string } do
		if shown == id then
			return self.slots[index]
		end
	end
	return nil
end

--- Redraw from the snapshot (nil before the first: "Loading...").
function InventoryCues.redraw(self: any, items: any)
	local ctx = self.ctx
	local loaded = type(items) == "table"
	self.loading.Visible = not loaded
	self.gridHolder.Visible = loaded
	if not loaded then
		self:closeDetail()
		return
	end
	if self.wantMark and self.showing then
		self:markSeen()
	end

	-- The cards in their places; a place past the last cue goes.
	local rows = ownedRows(items)
	local byId: { [string]: any } = {}
	for _, row in rows do
		byId[row.id] = row
	end
	self.rows = byId
	local order = {}
	for index, row in sorted(rows, self.sort) do
		local id: string = row.id
		InventoryCard.set(self:slot(index), {
			cueId = id,
			count = countLine(row),
			copy = copyLine(row),
			new = row.new == true or self.sticky[id] == true,
			equipped = items.equipped == id,
			chance = InventoryCues.chanceText(id),
		})
		table.insert(order, id)
	end
	for index = #self.slots, #order + 1, -1 do
		InventoryCard.destroy(self.slots[index])
		self.slots[index] = nil
	end
	self.order = order
	-- The tutorial's Equip step points at the first card that is not the equipped cue.
	local unequipped: GuiObject? = nil
	for index, id in order do
		if id ~= items.equipped then
			unequipped = self.slots[index].button
			break
		end
	end
	TutorialAnchors.set("InventoryCue", unequipped)
	self.empty.Visible = #order == 0
	self.empty.Text = WORDS.Empty

	-- The chosen cue stays chosen while it is owned; else the first shown. Its big card closes
	-- once it is gone (its last copy sold) rather than turning into another cue's.
	if not self.chosen or not byId[self.chosen] then
		if self.chosen and self.detailOpen then
			self:closeDetail()
		end
		self.chosen = order[1] or (if rows[1] then rows[1].id else nil)
	end
	for index, card in self.slots :: { InventoryCard.Card } do
		InventoryCard.setChosen(card, order[index] == self.chosen)
	end

	-- Sell dupes: the total it would pay now (for show; the server decides).
	local total = 0
	for _, row in rows do
		local extra = countOf(row) - 1
		if extra > 0 then
			total += extra * BlockOdds.sellValue(row.id)
		end
	end
	self.sellAllTotal = total
	local rail = ctx.rail
	if rail then
		rail:setSell(Format.money(total), total > 0 and not ctx.isHeld(rail.sell))
		rail:setSort(SORT_NAMES[self.sort] or self.sort)
	end
	if self.detailOpen then
		self:refreshDetail()
	end
	self:arrange()
end

--- The pictures the first screen shows (the staged cards), to load before the menu opens.
function InventoryCues.pictures(self: any, items: any): { string }
	local list = {}
	for index, row in sorted(ownedRows(items), self.sort) do
		if index > I.StagedCards then
			break
		end
		local picture = CueThumb.pictureOf(row.id)
		if picture then
			table.insert(list, picture)
		end
	end
	return list
end

--- Sort: the next order, round. The chosen card stays chosen; the grid goes back to its top
--- so the new order reads from its start.
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
		for index, card in self.slots :: { InventoryCard.Card } do
			InventoryCard.setChosen(card, self.order[index] == id)
		end
	end
	if pressed then
		self:openDetail()
	end
end

--- Open cue `id`'s big card (a Studio check through GuiQA "cuesDetail"); false if not owned.
function InventoryCues.show(self: any, id: string): boolean
	if not self.rows[id] then
		return false
	end
	self:choose(id, true)
	return true
end

--- Slam the chosen cue's big card in over the page.
function InventoryCues.openDetail(self: any)
	if not self.chosen then
		return
	end
	local frame = self.ctx.frame
	self:refreshDetail()
	if not self.detailOpen then
		self.detailOpen = true
		self.layer.Visible = true
		-- Calm: no gold burst and a small nudge, as it opens on every card pressed (designer,
		-- 2026-10-08: "do not make it always shine yellow and less shake").
		UIAnim.slam(self.detail, nil, { burst = false, shake = "Nudge" })
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
		local card = self:cardOf(self.chosen)
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
	local extra = spareOf(self.ctx, row)
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

-- Place the grid and size the big card from the view's size (geo.content: the page less the
-- rail when the rail stands inside it).
function InventoryCues.arrange(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not geo then
		return
	end
	local t = geo.t
	local W, H = geo.content.X, geo.content.Y
	-- Columns cards a row across the view; when two rows and the peek do not fit its height,
	-- smaller cards, the grid centred.
	local cell, cellH, cellGap = cellFor(W, t)
	local peek = span(I.PeekPx, t)
	local roomH = H - SC.PadPx - 2 * cellGap - peek
	if 2 * cellH > roomH then
		cellH = math.max(1, math.floor(roomH / 2))
		cell = math.max(1, math.floor(cellH * UNITS[1] / UNITS[2]))
		cellH = round(cell * UNITS[2] / UNITS[1])
	end
	local used = I.Columns * cell + (I.Columns - 1) * cellGap + 2 * SC.PadPx + SC.BarPx
	local gridW = math.min(W, used)
	self.gridHolder.Position = UDim2.fromOffset(math.max(0, round((W - gridW) / 2)), 0)
	self.gridHolder.Size = UDim2.fromOffset(gridW, math.max(1, H))
	self.gridLayout.CellPadding = UDim2.fromOffset(cellGap, cellGap)
	self.gridLayout.CellSize = UDim2.fromOffset(cell, cellH)

	-- The big card: over the view, as big as it allows, a gap all round.
	local gap = span(I.GapPx, t)
	local cardW = math.max(1, math.min(IT.BigMaxWidthPx, W - 2 * gap))
	local cardH = math.max(1, H - 2 * gap)
	self.detail.Size = UDim2.fromOffset(cardW, cardH)
	self.detail.Position = UDim2.fromOffset(round(W / 2), round(H / 2))
	self.detail.AnchorPoint = Vector2.new(0.5, 0.5)
	self.detailSize = Vector2.new(cardW, cardH)
	self:arrangeDetail()
end

--------------------------------------------------------------------------------------------
-- The view showing, NEW tags
--------------------------------------------------------------------------------------------

function InventoryCues.opened(self: any)
	-- Every open starts with the first card chosen, sorted Rarest first (designer, 2026-10-08:
	-- "sort by is always default rarest first").
	self.chosen = nil
	self.sort = SORTS[1]
end

function InventoryCues.shown(self: any)
	if self.showing then
		return
	end
	self.showing = true
	self:markSeen()
	-- Pills left from the last time the view showed go, the ones just marked stay.
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
	self.sort = SORTS[1] -- so the next open's first pictures load in that order
end

-- Clear the NEW tags the view shows now: one MarkSeen with their ids (at most MarkSeenMax);
-- their pills stay up (sticky) until the view is left.
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

--- Where a gamepad starts on this view: the chosen card, else the first (nil with none: the
--- menu puts it on the view's tile).
function InventoryCues.first(self: any): GuiObject?
	local card = self:cardOf(self.chosen) or self.slots[1]
	if card and card.button.Visible then
		return card.button
	end
	return nil
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
			UISound.play("Equip")
			ctx.notice(WORDS.EquippedNotice:format(CueThumb.cueName(id)), "Green")
		else
			ctx.refuse(reply)
		end
	end)
end

--- Sell the chooser's count of the chosen cue: asks first from Config.BlockOdds.ConfirmSellFrom
--- up, and always when it is the last copy (gone for good; designer, 2026-10-09).
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
	local last = count >= countOf(row)
	if not last and not BlockOdds.needsConfirm(id) then
		sell()
		return
	end
	local name, money = CueThumb.cueName(id), Format.money(count * BlockOdds.sellValue(id))
	ctx.confirm({
		title = if last then WORDS.ConfirmLastTitle else WORDS.ConfirmSellTitle,
		text = if last
			then WORDS.ConfirmSellLast:format(Format.commas(count), name, money)
			else WORDS.ConfirmSellCount:format(Format.commas(count), name, money),
		yes = WORDS.SellYes,
		no = WORDS.SellNo,
	}, function(yes: boolean)
		if yes then
			sell()
		end
	end)
end

--- Sell dupes (the rail's tile): every duplicate, after a confirm.
function InventoryCues.askSellAll(self: any)
	local ctx = self.ctx
	local button: TextButton? = ctx.rail and ctx.rail.sell
	if self.sellAllTotal <= 0 or not button then
		ctx.notice(WORDS.NothingToSell)
		return
	end
	UISound.play("Click")
	ctx.confirm({
		title = WORDS.ConfirmAllTitle,
		text = WORDS.ConfirmAll:format(Format.money(self.sellAllTotal)),
		yes = WORDS.SellYes,
		no = WORDS.SellNo,
	}, function(yes: boolean)
		if not yes then
			return
		end
		ctx.hold(button, function()
			local reply = ctx.request("SellDuplicates")
			if reply.ok then
				local money = if type(reply.money) == "number" then reply.money else 0
				if money > 0 then
					ctx.flyMoney(money, button)
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
