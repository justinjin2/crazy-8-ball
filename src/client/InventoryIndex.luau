--!strict
-- InventoryIndex: the Cues menu's Index view (docs/prompts/ECONOMY_UI_PROMPT.md section 11,
-- ECONOMY section 18; concept 2 of docs/prompts/CUES_LIVELY_PROMPT.md, 2026-10-08).
--
--   * On top, only for a player who holds one, their titles (gold pills, from the snapshot's
--     `titles`: the first Reyes'). The rows' "Collector" titles are gone (designer, 2026-09-28).
--   * Then a card per row: the rarities Common ... Secret, then Exclusive and Unique. Its
--     header: the rarity's name in its colour, "5 / 7" (cues of it ever owned), the reward
--     money (Common to Epic only, from the snapshot's `rows`) and Claim
--     once the row is complete (it breathes while it can be claimed; "Claimed" with a check
--     after). Under it every catalog cue of that rarity as a small card (InventoryCard),
--     Config.UI.Inventory.IndexColumns a row: ever-owned cues as their cards, never-owned
--     ones locked (the whole card, still, greyed, with a padlock; designer, 2026-10-08: they
--     were black silhouettes). A cue counts once ever owned (the snapshot's `seen`), sold or
--     not.
--   * On the right, on the lively sheet's dots, the chosen cue's card (bare: no pills),
--     standing still (designer, 2026-10-08: it swayed), locked until found. Its name, rarity,
--     "In your collection" or "Not found yet",
--     "4.2% chance · 1,284 exist", and for a cue not found yet the finder's money it pays
--     ("Find it for +$250", Config.Index.FindMoney). A tap or click on a card chooses it; a
--     gamepad chooses the card it lands on.
--   * The open (Config.UI.Inventory.Open): the panel, the first rows' headers and the first
--     cells pop in ("IndexDetail", "IndexHead1".., "IndexCell1"..).
--
-- Claim asks the server (ItemRequest "ClaimIndexRow"); its money flies into the header's cash.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Catalog = require(Progression:WaitForChild("Catalog"))
local Format = require(Progression:WaitForChild("Format"))
local Inventory = require(Progression:WaitForChild("Inventory"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local InventoryCues = require(script.Parent.InventoryCues)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local I = Config.UI.Inventory
local D = I.Detail
local SC = Config.UI.Menu.Scroll
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local TITLE_NAMES: { [string]: string } = Strings.Items.Titles :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local UNITS = Config.UI.CueCard.Units
local COPIES_FOLDER = "CueCounts" -- ReplicatedStorage.CueCounts: copies in existence (Counters)

-- How many headers and cells the open schedule names (Config.UI.Inventory.Open).
local INDEX_HEADS, INDEX_CELLS = 0, 0
for _, step in I.Open.Steps do
	for _, id in step.Ids do
		if string.match(id, "^IndexHead%d+$") then
			INDEX_HEADS += 1
		elseif string.match(id, "^IndexCell%d+$") then
			INDEX_CELLS += 1
		end
	end
end

-- The rows, top to bottom (as Progression/Inventory.indexRows).
local GROUPS: { string } = table.clone(Config.BlockOdds.Rarities)
table.insert(GROUPS, "Ranked")
table.insert(GROUPS, "Exclusive")
table.insert(GROUPS, "Unique")

type Section = {
	rarity: string,
	box: Frame,
	head: Frame, -- the header line (a piece of the open)
	name: TextLabel,
	progress: TextLabel,
	money: Frame,
	moneyIcon: ImageLabel,
	moneyText: TextLabel,
	claim: TextButton,
	claimed: Frame,
	claimedIcon: ImageLabel,
	claimedText: TextLabel,
	ids: { string },
	cells: { InventoryCard.Card },
	claimable: boolean,
	pulse: UIAnim.Handle?,
}

local InventoryIndex = {}
InventoryIndex.__index = InventoryIndex

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

local function titleName(id: any): string
	return if type(id) == "string" then TITLE_NAMES[id] or id else ""
end

--- The Index page, built into `page`. `ctx`: InventoryMenu's.
function InventoryIndex.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, InventoryIndex)
	self.page = page
	self.ctx = ctx
	self.geo = nil :: MenuFrame.Geo?
	self.showing = false
	self.chosen = nil :: string?
	self.seen = {} :: { [string]: boolean }
	-- The rows scroll on the left; the chosen cue's panel sits on the right.
	local list = HudParts.frame(page, "List")
	list.ZIndex = 2
	self.list = list
	local scroll, _ = MenuFrame.scroller(list, { name = "Index" })
	self.scroll = scroll

	-- The titles held (hidden when none).
	local titles = InventoryCard.box(scroll, "Titles")
	titles.LayoutOrder = 0
	titles.ZIndex = 2
	titles.Visible = false
	self.titles = titles
	self.titlesHeading = HudParts.text(titles, "Heading", I.HeaderTextPx[2], WORDS.Titles)
	self.titlesHeading.TextWrapped = false
	self.titlesHeading.TextXAlignment = Enum.TextXAlignment.Left
	self.titlesHeading.ZIndex = 3
	self.titlePills = {} :: { { pill: Frame, text: TextLabel } }

	self.sections = {} :: { Section }
	for index, rarity in GROUPS do
		table.insert(self.sections, self:buildSection(rarity, index))
	end
	self:buildDetail(page)
	self.loading = MenuFrame.placeholder(page)
	return self
end

-- The chosen cue's panel: its card, then its words.
function InventoryIndex.buildDetail(self: any, page: Frame)
	local box = InventoryCard.box(page, "Detail")
	HudParts.dots(box, Config.UI.Inventory.Card.CornerPx) -- the lively sheet's tiny pool balls
	box.ZIndex = 2
	box.Visible = false
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

	-- The cue's own card, bare (it does not press or light up).
	local card = InventoryCard.new(scroll, {
		name = "Card",
		onPress = function() end,
	})
	card.button.Selectable = false
	card.button.Interactable = false
	card.button.ZIndex = 3
	self.card = card

	self.nameLabel = HudParts.text(scroll, "Name", D.NameTextPx[2], "")
	self.nameLabel.ZIndex = 3
	self.rarityLabel = HudParts.text(scroll, "Rarity", D.RarityTextPx[2], "")
	self.rarityLabel.TextWrapped = false
	self.rarityLabel.ZIndex = 3
	self.stateLabel = HudParts.note(scroll, "State", D.LineTextPx[2], "")
	self.stateLabel.ZIndex = 3
	self.existLabel = HudParts.note(scroll, "Exist", D.LineTextPx[2], "")
	self.existLabel.TextWrapped = false
	self.existLabel.RichText = true
	self.existLabel.AutoLocalize = false
	self.existLabel.ZIndex = 3
	-- A cue not found yet: the cash and "Find it for +$250" in green.
	local findRow = HudParts.frame(scroll, "FindRow")
	findRow.ZIndex = 3
	self.findRow = findRow
	self.findIcon = HudParts.icon(findRow, "CashSingle", "Cash")
	self.findIcon.ZIndex = 3
	self.findLabel = HudParts.text(findRow, "Words", D.LineTextPx[2], "", HudParts.tone("Green"))
	self.findLabel.AutoLocalize = false -- carries a number (the sentence itself is in Strings)
	self.findLabel.TextWrapped = false
	self.findLabel.TextXAlignment = Enum.TextXAlignment.Left
	self.findLabel.ZIndex = 3
end

function InventoryIndex.buildSection(self: any, rarity: string, order: number): Section
	local box = InventoryCard.box(self.scroll, "Row" .. rarity)
	box.LayoutOrder = order
	box.ZIndex = 2
	local head = HudParts.frame(box, "Head")
	head.ZIndex = 3
	local name = HudParts.text(
		head,
		"Rarity",
		I.HeaderTextPx[2],
		CueThumb.rarityName(rarity),
		CueThumb.accentColor(rarity)
	)
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local progress = HudParts.note(head, "Progress", I.ProgressTextPx[2], "")
	progress.TextWrapped = false
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.ZIndex = 3
	-- The reward: the money (a white pill, the cash and green words).
	local money = HudParts.pill(head, "Money", HudParts.tone("White"))
	money.ZIndex = 3
	local moneyIcon = HudParts.icon(money, "CashSingle", "Cash")
	moneyIcon.ZIndex = 4
	local moneyText = HudParts.text(money, "Amount", I.RewardTextPx[2], "", HudParts.tone("Green"))
	moneyText.AutoLocalize = false -- a number
	moneyText.TextWrapped = false
	moneyText.ZIndex = 4
	local section: Section
	local claim = HudParts.candy(head, WORDS.Claim, function()
		self:claim(section)
	end, "Green")
	claim.Name = "Claim"
	claim.ZIndex = 3
	HudParts.setMinHit(claim, TOUCH)
	local claimed = HudParts.frame(head, "Claimed")
	claimed.ZIndex = 3
	local claimedIcon = HudParts.icon(claimed, "Check", "Check")
	claimedIcon.ZIndex = 3
	local claimedText =
		HudParts.text(claimed, "Words", I.ProgressTextPx[2], WORDS.Claimed, HudParts.tone("Green"))
	claimedText.TextWrapped = false
	claimedText.TextXAlignment = Enum.TextXAlignment.Left
	claimedText.ZIndex = 3

	-- Every catalog cue of the row, as small cards.
	local ids = {}
	local cells = {}
	for _, cue in Catalog.ofRarity(rarity) do
		local id = cue.Id
		table.insert(ids, id)
		table.insert(
			cells,
			InventoryCard.new(box, {
				name = id,
				lines = I.CellNameLines,
				onPress = function()
					self:choose(id)
				end,
				onSelect = function()
					self:choose(id)
				end,
			})
		)
	end
	section = {
		rarity = rarity,
		box = box,
		head = head,
		name = name,
		progress = progress,
		money = money,
		moneyIcon = moneyIcon,
		moneyText = moneyText,
		claim = claim,
		claimed = claimed,
		claimedIcon = claimedIcon,
		claimedText = claimedText,
		ids = ids,
		cells = cells,
		claimable = false,
		pulse = nil,
	}
	return section
end

--- The open's pieces: the panel, the first rows' headers and the first cells in reading order
--- (as many as the schedule names).
function InventoryIndex.register(self: any, stage: any)
	stage:add("IndexDetail", self.detail)
	local staged: { InventoryCard.Card } = {}
	local stagedIds: { string } = {}
	self.staged, self.stagedIds = staged, stagedIds
	for index, section in self.sections :: { Section } do
		if index <= INDEX_HEADS then
			stage:add("IndexHead" .. index, section.head)
		end
		for i, card in section.cells do
			if #staged >= INDEX_CELLS then
				return
			end
			table.insert(staged, card)
			table.insert(stagedIds, section.ids[i])
			-- Its motion runs again as it lands (`hold` stilled it for the pop).
			stage:add("IndexCell" .. #staged, card.button, function()
				InventoryCard.hold(card, false)
			end)
		end
	end
end

--- The staged cells are about to pop in (the open, a flip to the Index): their motion waits
--- until each lands.
function InventoryIndex.hold(self: any)
	for _, card in self.staged or {} do
		InventoryCard.hold(card, true)
	end
end

--------------------------------------------------------------------------------------------
-- Drawing from the snapshot
--------------------------------------------------------------------------------------------

-- The snapshot's rows by rarity.
local function rowsOf(items: any): { [string]: any }
	local rows: { [string]: any } = {}
	for _, row in list(items and items.rows) do
		if type(row) == "table" and type(row.rarity) == "string" then
			rows[row.rarity] = row
		end
	end
	return rows
end

-- Complete, not claimed yet (the same rule the Rewards menu's Index banner reads).
local function claimable(row: any): boolean
	return ItemState.indexRowReady(row)
end

--- The tab's red dot: "!" while a row can be claimed.
function InventoryIndex.dot(_self: any, items: any): string?
	for _, row in rowsOf(items) do
		if claimable(row) then
			return Strings.Menus.DotReady
		end
	end
	return nil
end

--- The pictures the first screen shows (the staged cells and the first cue's panel), to load
--- before the view first shows.
function InventoryIndex.pictures(self: any, _items: any): { string }
	local list = {}
	for _, id in self.stagedIds or {} do
		local picture = CueThumb.pictureOf(id)
		if picture then
			table.insert(list, picture)
		end
	end
	return list
end

--- Redraw from the snapshot (nil before the first: "Loading...").
function InventoryIndex.redraw(self: any, items: any)
	local ctx = self.ctx
	local loaded = type(items) == "table"
	self.loading.Visible = not loaded
	self.list.Visible = loaded
	if not loaded then
		self.detail.Visible = false
		self:stopPulses()
		return
	end
	local seen: { [string]: boolean } = {}
	for _, id in list(items.seen) do
		if type(id) == "string" then
			seen[id] = true
		end
	end
	self.seen = seen
	-- The chosen cue stays chosen; else the first one.
	if not self.chosen or not Catalog.get(self.chosen) then
		local first = self.sections[1]
		self.chosen = if first then first.ids[1] else nil
	end
	local rows = rowsOf(items)
	for _, section in self.sections do
		local row = rows[section.rarity]
		local have = 0
		for i, id in section.ids do
			local owned = seen[id] == true
			if owned then
				have += 1
			end
			InventoryCard.set(section.cells[i], { cueId = id, locked = not owned })
			InventoryCard.setChosen(section.cells[i], id == self.chosen)
		end
		local total = #section.ids
		if row then
			have = if type(row.have) == "number" then row.have else have
			total = if type(row.total) == "number" then row.total else total
		end
		section.progress.Text = WORDS.Progress:format(Format.commas(have), Format.commas(total))
		local reward = if row and type(row.reward) == "table" then row.reward else nil
		local money = if reward and type(reward.money) == "number" then reward.money else 0
		section.money.Visible = money > 0
		section.moneyText.Text = Format.money(money)
		section.claimable = claimable(row)
		section.claim.Visible = section.claimable
		HudParts.setEnabled(section.claim, not ctx.isHeld(section.claim))
		-- A row with no reward (Legendary and up) never shows "Claimed", though an old save
		-- claimed its dropped title.
		section.claimed.Visible = row ~= nil and row.claimed == true and money > 0
	end

	-- The titles at the top.
	local names = {}
	for _, id in list(items.titles) do
		local name = titleName(id)
		if name ~= "" then
			table.insert(names, name)
		end
	end
	for i, name in names do
		local entry = self.titlePills[i]
		if not entry then
			local pill, text =
				InventoryCard.pill(self.titles, "Title" .. i, HudParts.tone("Gold"), "")
			pill.ZIndex = 3
			text.ZIndex = 4
			entry = { pill = pill, text = text }
			self.titlePills[i] = entry
		end
		entry.text.Text = name
		entry.pill.Visible = true
	end
	for i = #names + 1, #self.titlePills do
		self.titlePills[i].pill.Visible = false
	end
	self.titles.Visible = #names > 0
	self:refreshPulses()
	self:refreshDetail()
	self:arrange()
end

-- Claim breathes while its row can be claimed and the tab shows.
function InventoryIndex.refreshPulses(self: any)
	for _, section in self.sections do
		local want = self.showing and section.claimable and not self.ctx.isHeld(section.claim)
		if want and not section.pulse then
			section.pulse = UIAnim.pulse(section.claim)
		elseif not want and section.pulse then
			section.pulse.stop()
			section.pulse = nil
		end
	end
end

function InventoryIndex.stopPulses(self: any)
	for _, section in self.sections do
		if section.pulse then
			section.pulse.stop()
			section.pulse = nil
		end
	end
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

function InventoryIndex.layout(self: any, geo: MenuFrame.Geo)
	self.geo = geo
	self:arrange()
end

function InventoryIndex.arrange(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not geo then
		return
	end
	local t = geo.t
	local function span1(pair: { number }): number
		return span(pair, t)
	end
	-- The list on the left, the chosen cue's panel on the right.
	local pageW, pageH = geo.content.X, geo.content.Y
	local pageGap = span1(I.GapPx)
	local detailW =
		math.clamp(round(pageW * I.IndexDetailShare), span1(I.IndexDetailMinPx), I.IndexDetailMaxPx)
	detailW = math.min(detailW, math.max(1, round(pageW / 2)))
	local listW = math.max(1, pageW - detailW - pageGap)
	self.list.Position = UDim2.fromOffset(0, 0)
	self.list.Size = UDim2.fromOffset(listW, pageH)
	self.detail.Position = UDim2.fromOffset(listW + pageGap, 0)
	self.detail.Size = UDim2.fromOffset(detailW, pageH)
	self.detailSize = Vector2.new(detailW, pageH)
	self:arrangeDetail()

	local W = math.max(1, listW - 2 * SC.PadPx - SC.BarPx) -- a card's width
	local pad = span1(I.SectionPadPx)
	local gap = span1(I.CellGapPx)
	local inner = math.max(1, W - 2 * pad)
	local headerH = span1(I.HeaderPx)
	local headText = span1(I.HeaderTextPx)
	local progText = span1(I.ProgressTextPx)
	local rewardH = span1(I.RewardPx)
	local rewardText = span1(I.RewardTextPx)
	local claimW = span1(I.ClaimWidthPx)

	-- The titles: the heading, then the pills flowing left to right, wrapping.
	HudParts.setTextSize(self.titlesHeading, headText)
	self.titlesHeading.Position = UDim2.fromOffset(pad, pad)
	self.titlesHeading.Size = UDim2.fromOffset(inner, headerH)
	local y = pad + headerH
	local pillH = span1(I.TitlePillPx)
	local pillText = span1(I.TitleTextPx)
	do
		local x = pad
		for _, entry in self.titlePills do
			if entry.pill.Visible then
				HudParts.setTextSize(entry.text, pillText)
				local width =
					math.min(inner, InventoryCard.pillWidth(entry.text.Text, pillH, pillText))
				if x > pad and x + width > pad + inner then
					x = pad
					y += pillH + gap
				end
				entry.pill.Position = UDim2.fromOffset(x, y)
				entry.pill.Size = UDim2.fromOffset(width, pillH)
				x += width + gap
			end
		end
		y += pillH
	end
	self.titles.Size = UDim2.fromOffset(W, y + pad)

	-- The rows: IndexColumns cells a row.
	local columns = I.IndexColumns
	local cellW = math.max(1, math.floor((inner - (columns - 1) * gap) / columns))
	local cellH = round(cellW * UNITS[2] / UNITS[1])
	for _, section in self.sections do
		-- Left: the rarity and "5 / 7".
		HudParts.setTextSize(section.name, headText)
		HudParts.setTextSize(section.progress, progText)
		local nameW = math.ceil(textWidth(section.name.Text, headText)) + 8
		local progW = math.ceil(textWidth(section.progress.Text, progText)) + 6
		section.name.Position = UDim2.fromOffset(pad, pad)
		section.name.Size = UDim2.fromOffset(math.min(nameW, inner), headerH)
		section.progress.Position = UDim2.fromOffset(pad + nameW + gap, pad)
		section.progress.Size = UDim2.fromOffset(progW, headerH)
		local left = nameW + gap + progW

		-- Right: Claim, or "Claimed".
		local right = 0
		if section.claim.Visible then
			local claimH = headerH
			section.claim.Position = UDim2.fromOffset(pad + inner - claimW, pad)
			section.claim.Size = UDim2.fromOffset(claimW, claimH)
			HudParts.setButtonTextSize(section.claim, progText)
			right = claimW
		end
		if section.claimed.Visible then
			HudParts.setTextSize(section.claimedText, progText)
			local check = rewardH
			local words = math.ceil(textWidth(section.claimedText.Text, progText)) + 6
			local width = check + 4 + words
			section.claimed.Position = UDim2.fromOffset(pad + inner - width, pad)
			section.claimed.Size = UDim2.fromOffset(width, headerH)
			section.claimedIcon.Size = UDim2.fromOffset(check, check)
			section.claimedIcon.Position = UDim2.fromOffset(0, round((headerH - check) / 2))
			section.claimedText.Position = UDim2.fromOffset(check + 4, 0)
			section.claimedText.Size = UDim2.fromOffset(words, headerH)
			right = math.max(right, width)
		end

		-- The reward chips: on the header line when they fit, else on a line of their own.
		local chips: { { frame: Frame, width: number } } = {}
		if section.money.Visible then
			HudParts.setTextSize(section.moneyText, rewardText)
			-- The cash pokes out past the pill's left end, as in the money HUD.
			local icon = round(rewardH * I.RewardIconShare)
			local over = round(icon * I.RewardIconOverShare)
			local words = math.ceil(textWidth(section.moneyText.Text, rewardText)) + 6
			local width = icon - over + words + 8
			section.moneyIcon.AnchorPoint = Vector2.new(0, 0.5)
			section.moneyIcon.Position = UDim2.new(0, -over, 0.5, 0)
			section.moneyIcon.Size = UDim2.fromOffset(icon, icon)
			section.moneyText.Position = UDim2.fromOffset(icon - over, 0)
			section.moneyText.Size = UDim2.fromOffset(words, rewardH)
			table.insert(chips, { frame = section.money, width = width })
		end
		local chipsW = 0
		for i, chip in chips do
			chipsW += chip.width + (if i > 1 then gap else 0)
		end
		local top = pad + headerH
		if #chips > 0 then
			local beside = left + gap + chipsW + (if right > 0 then gap + right else 0) <= inner
			local x, chipY
			if beside then
				x = pad + inner - (if right > 0 then right + gap else 0) - chipsW
				chipY = pad + round((headerH - rewardH) / 2)
			else
				x = pad
				chipY = top + round(gap / 2)
				top = chipY + rewardH
			end
			for _, chip in chips do
				chip.frame.Position = UDim2.fromOffset(x, chipY)
				chip.frame.Size = UDim2.fromOffset(chip.width, rewardH)
				x += chip.width + gap
			end
		end

		-- The header line holds what is above the cells (it pops in as one piece).
		section.head.Position = UDim2.fromOffset(0, 0)
		section.head.Size = UDim2.fromOffset(W, top)

		-- The cues, IndexColumns a row.
		top += gap
		for i, card in section.cells do
			local col = (i - 1) % columns
			local line = (i - 1) // columns
			card.button.Position =
				UDim2.fromOffset(pad + col * (cellW + gap), top + line * (cellH + gap))
			card.button.Size = UDim2.fromOffset(cellW, cellH)
		end
		local lines = math.max(1, math.ceil(#section.cells / columns))
		section.box.Size = UDim2.fromOffset(W, top + lines * cellH + (lines - 1) * gap + pad)
	end
end

--------------------------------------------------------------------------------------------
-- Pressing
--------------------------------------------------------------------------------------------

--- Show a cue in the panel (a tap, click or a gamepad landing on its card).
function InventoryIndex.choose(self: any, id: string)
	if self.chosen == id or not Catalog.get(id) then
		return
	end
	self.chosen = id
	for _, section in self.sections do
		for i, cellId in section.ids do
			InventoryCard.setChosen(section.cells[i], cellId == id)
		end
	end
	self:refreshDetail()
end

-- Copies in existence of a cue (ReplicatedStorage.CueCounts, from the server's counters), or
-- nil while unknown or not caught up yet (0).
local function copiesOf(id: string): number?
	local folder = ReplicatedStorage:FindFirstChild(COPIES_FOLDER)
	local value = if folder then folder:GetAttribute(id) else nil
	if type(value) ~= "number" or value ~= value or value < 1 then
		return nil
	end
	return value
end

-- The chosen cue's panel: its card (locked until found), the words.
function InventoryIndex.refreshDetail(self: any)
	local id: string? = self.chosen
	local cue = if id then Catalog.get(id) else nil
	self.detail.Visible = cue ~= nil and self.list.Visible
	if not id or not cue then
		return
	end
	local found = self.seen[id] == true
	InventoryCard.set(self.card, { cueId = id, bare = true, locked = not found })
	self.nameLabel.Text = CueThumb.cueName(id)
	self.rarityLabel.Text = CueThumb.rarityName(cue.Rarity)
	self.rarityLabel.TextColor3 = CueThumb.cueColor(id)
	self.stateLabel.Text = if found then WORDS.Found else WORDS.NotFound
	local facts = InventoryCues.factsLine(id, copiesOf(id))
	self.existLabel.Text = facts or ""
	self.existLabel.Visible = facts ~= nil
	local money = if found then 0 else Inventory.findMoney(id)
	self.findRow.Visible = money > 0
	self.findLabel.Text = WORDS.FindReward:format(Format.money(money))
	self:arrangeDetail()
end

-- Lay the panel out, stacked and centred: the card on top (at most IndexCardShare of the
-- page's height), then the words. Its canvas grows to fit.
function InventoryIndex.arrangeDetail(self: any)
	local size = self.detailSize :: Vector2?
	if not size or size.X <= 0 then
		return
	end
	local span = self.ctx.span
	local pad, gap = span(D.PadPx), span(D.GapPx)
	local w = size.X - SC.BarPx
	local inner = math.max(1, w - 2 * pad)
	local cardH =
		math.max(1, math.min(round(size.Y * I.IndexCardShare), round(inner * UNITS[2] / UNITS[1])))
	local cardW = math.max(1, round(cardH * UNITS[1] / UNITS[2]))
	self.card.button.Position = UDim2.fromOffset(round((w - cardW) / 2), pad)
	self.card.button.Size = UDim2.fromOffset(cardW, cardH)
	local y = pad + cardH + gap
	local nameSize, raritySize, lineSize =
		span(D.NameTextPx), span(D.RarityTextPx), span(D.LineTextPx)
	HudParts.setTextSize(self.nameLabel, nameSize)
	HudParts.setTextSize(self.rarityLabel, raritySize)
	HudParts.setTextSize(self.stateLabel, lineSize)
	HudParts.setTextSize(self.existLabel, lineSize)
	HudParts.setTextSize(self.findLabel, lineSize)
	local function place(label: TextLabel, height: number)
		label.Position = UDim2.fromOffset(pad, y)
		label.Size = UDim2.fromOffset(inner, height)
		y += height
	end
	place(self.nameLabel, math.ceil(textHeight(self.nameLabel.Text, nameSize, inner - 4)) + 4)
	place(self.rarityLabel, raritySize + 6)
	place(self.stateLabel, math.ceil(textHeight(self.stateLabel.Text, lineSize, inner - 4)) + 4)
	if self.existLabel.Visible then
		place(self.existLabel, lineSize + 4)
	end
	if self.findRow.Visible then
		local icon = round(lineSize * 1.5)
		local words = math.ceil(textWidth(self.findLabel.Text, lineSize)) + 6
		local rowW = math.min(inner, icon + 4 + words)
		local rowH = math.max(icon, lineSize + 4)
		self.findRow.Position = UDim2.fromOffset(pad + round((inner - rowW) / 2), y + 2)
		self.findRow.Size = UDim2.fromOffset(rowW, rowH)
		self.findIcon.Size = UDim2.fromOffset(icon, icon)
		self.findIcon.Position = UDim2.fromOffset(0, round((rowH - icon) / 2))
		self.findLabel.Position = UDim2.fromOffset(icon + 4, 0)
		self.findLabel.Size = UDim2.fromOffset(math.max(1, rowW - icon - 4), rowH)
		y += rowH + 2
	end
	self.detailScroll.CanvasSize = UDim2.fromOffset(0, y + pad)
end

function InventoryIndex.claim(self: any, section: Section)
	local ctx = self.ctx
	if not section.claimable then
		return
	end
	if section.pulse then
		section.pulse.stop()
		section.pulse = nil
	end
	ctx.hold(section.claim, function()
		local reply = ctx.request("ClaimIndexRow", section.rarity)
		if reply.ok then
			UISound.play("Claim")
			local money = if type(reply.money) == "number" then reply.money else 0
			if money > 0 then
				ctx.flyMoney(money, section.claim, "Reward")
			end
		else
			ctx.refuse(reply)
		end
	end)
	self:refreshPulses()
end

--------------------------------------------------------------------------------------------
-- The tab showing
--------------------------------------------------------------------------------------------

function InventoryIndex.opened(self: any)
	self.chosen = nil -- every open starts on the first cue
end

function InventoryIndex.shown(self: any)
	self.showing = true
	self:refreshPulses()
	self:refreshDetail() -- the copies in existence may have moved
end

function InventoryIndex.hidden(self: any)
	self.showing = false
	self:stopPulses()
end

function InventoryIndex.closed(self: any)
	self:stopPulses()
end

--- Where a gamepad starts on this page: a Claim that can be pressed, else the first cue.
function InventoryIndex.first(self: any): GuiObject?
	for _, section in self.sections do
		if section.claim.Visible and section.claim.Selectable then
			return section.claim
		end
	end
	local section = self.sections[1]
	local card = if section then section.cells[1] else nil
	return if card then card.button else nil
end

return InventoryIndex
