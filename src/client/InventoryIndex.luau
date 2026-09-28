--!strict
-- InventoryIndex: the Inventory's Index tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11,
-- ECONOMY section 18).
--
--   * On top, the titles earned (gold pills, from the snapshot's `titles`), or a line saying
--     how to earn one.
--   * Then a card per row: the rarities Common ... Secret, then Exclusive and Unique (no
--     reward for those two). Its header: the rarity's name in its colour, "5 / 7" (cues of it
--     ever owned), the reward (the money and the title, from the snapshot's `rows`) and Claim
--     once the row is complete (it breathes while it can be claimed; "Claimed" with a check
--     after). Under it every catalog cue of that rarity as a small card (InventoryCard):
--     ever-owned cues in colour with their names, never-owned ones as dark silhouettes with
--     "?" and no name. A cue counts once ever owned (the snapshot's `seen`), sold or not.
--
-- Claim asks the server (ItemRequest "ClaimIndexRow"); its money flies into the header's cash
-- and the title shows at the top once the snapshot follows. Pressing a cue says its name and
-- rarity (a found one) or that it is not found yet.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Catalog = require(Progression:WaitForChild("Catalog"))
local Format = require(Progression:WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local I = Config.UI.Inventory
local SC = Config.UI.Menu.Scroll
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local TITLE_NAMES: { [string]: string } = Strings.Items.Titles :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx

-- The rows, top to bottom (as Progression/Inventory.indexRows).
local GROUPS: { string } = table.clone(Config.Cases.Rarities)
table.insert(GROUPS, "Exclusive")
table.insert(GROUPS, "Unique")

type Section = {
	rarity: string,
	box: Frame,
	name: TextLabel,
	progress: TextLabel,
	money: Frame,
	moneyIcon: ImageLabel,
	moneyText: TextLabel,
	title: Frame,
	titleText: TextLabel,
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

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
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
	local scroll, _ = MenuFrame.scroller(page, { name = "Index" })
	self.scroll = scroll

	-- The titles earned.
	local titles = InventoryCard.box(scroll, "Titles")
	titles.LayoutOrder = 0
	titles.ZIndex = 2
	self.titles = titles
	self.titlesHeading = HudParts.text(titles, "Heading", I.HeaderTextPx[2], WORDS.Titles)
	self.titlesHeading.TextWrapped = false
	self.titlesHeading.TextXAlignment = Enum.TextXAlignment.Left
	self.titlesHeading.ZIndex = 3
	self.titlesNote = HudParts.note(titles, "None", I.TitleTextPx[2], WORDS.NoTitles)
	self.titlesNote.TextXAlignment = Enum.TextXAlignment.Left
	self.titlesNote.ZIndex = 3
	self.titlePills = {} :: { { pill: Frame, text: TextLabel } }

	self.sections = {} :: { Section }
	for index, rarity in GROUPS do
		table.insert(self.sections, self:buildSection(rarity, index))
	end
	self.loading = MenuFrame.placeholder(page)
	return self
end

function InventoryIndex.buildSection(self: any, rarity: string, order: number): Section
	local box = InventoryCard.box(self.scroll, "Row" .. rarity)
	box.LayoutOrder = order
	box.ZIndex = 2
	local name = HudParts.text(
		box,
		"Rarity",
		I.HeaderTextPx[2],
		CueThumb.rarityName(rarity),
		CueThumb.accentColor(rarity)
	)
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local progress = HudParts.note(box, "Progress", I.ProgressTextPx[2], "")
	progress.TextWrapped = false
	progress.TextXAlignment = Enum.TextXAlignment.Left
	progress.ZIndex = 3
	-- The reward: the money (a white pill, the cash and green words) and the title (gold).
	local money = HudParts.pill(box, "Money", HudParts.tone("White"))
	money.ZIndex = 3
	local moneyIcon = HudParts.icon(money, "CashSingle", "Cash")
	moneyIcon.ZIndex = 4
	local moneyText = HudParts.text(money, "Amount", I.RewardTextPx[2], "", HudParts.tone("Green"))
	moneyText.AutoLocalize = false -- a number
	moneyText.TextWrapped = false
	moneyText.ZIndex = 4
	local title, titleText = InventoryCard.pill(box, "Title", HudParts.tone("Gold"), "")
	title.ZIndex = 3
	titleText.ZIndex = 4
	local section: Section
	local claim = HudParts.candy(box, WORDS.Claim, function()
		self:claim(section)
	end, "Green")
	claim.Name = "Claim"
	claim.ZIndex = 3
	HudParts.setMinHit(claim, TOUCH)
	local claimed = HudParts.frame(box, "Claimed")
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
					self:tell(id)
				end,
			})
		)
	end
	section = {
		rarity = rarity,
		box = box,
		name = name,
		progress = progress,
		money = money,
		moneyIcon = moneyIcon,
		moneyText = moneyText,
		title = title,
		titleText = titleText,
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

local function claimable(row: any): boolean
	return row ~= nil
		and row.complete == true
		and row.claimed ~= true
		and type(row.reward) == "table"
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

--- Redraw from the snapshot (nil before the first: "Loading...").
function InventoryIndex.redraw(self: any, items: any)
	local ctx = self.ctx
	local loaded = type(items) == "table"
	self.loading.Visible = not loaded
	self.scroll.Visible = loaded
	if not loaded then
		self:stopPulses()
		return
	end
	local seen: { [string]: boolean } = {}
	for _, id in list(items.seen) do
		if type(id) == "string" then
			seen[id] = true
		end
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
			InventoryCard.set(section.cells[i], { cueId = id, silhouette = not owned })
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
		local title = if reward then titleName(reward.title) else ""
		section.title.Visible = title ~= ""
		section.titleText.Text = title
		section.claimable = claimable(row)
		section.claim.Visible = section.claimable
		HudParts.setEnabled(section.claim, not ctx.isHeld(section.claim))
		section.claimed.Visible = row ~= nil and row.claimed == true
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
	self.titlesNote.Visible = #names == 0
	self:refreshPulses()
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
	local span = self.ctx.span
	local W = math.max(1, geo.content.X - 2 * SC.PadPx - SC.BarPx) -- a card's width
	local pad = span(I.SectionPadPx)
	local gap = span(I.CellGapPx)
	local inner = math.max(1, W - 2 * pad)
	local headerH = span(I.HeaderPx)
	local headText = span(I.HeaderTextPx)
	local progText = span(I.ProgressTextPx)
	local rewardH = span(I.RewardPx)
	local rewardText = span(I.RewardTextPx)
	local claimW = span(I.ClaimWidthPx)

	-- The titles: the heading, then the pills flowing left to right, wrapping.
	HudParts.setTextSize(self.titlesHeading, headText)
	self.titlesHeading.Position = UDim2.fromOffset(pad, pad)
	self.titlesHeading.Size = UDim2.fromOffset(inner, headerH)
	local y = pad + headerH
	local pillH = span(I.TitlePillPx)
	local pillText = span(I.TitleTextPx)
	if self.titlesNote.Visible then
		HudParts.setTextSize(self.titlesNote, pillText)
		self.titlesNote.Position = UDim2.fromOffset(pad, y)
		self.titlesNote.Size = UDim2.fromOffset(inner, pillH)
		y += pillH
	else
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

	-- The rows.
	local cellMin = span(I.CellMinPx)
	local columns = math.max(1, math.floor((inner + gap) / (cellMin + gap)))
	local cellW = math.max(1, math.floor((inner - (columns - 1) * gap) / columns))
	local cellH = round(cellW * I.CellAspect)
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
		if section.title.Visible then
			HudParts.setTextSize(section.titleText, rewardText)
			local width = math.min(
				inner,
				InventoryCard.pillWidth(section.titleText.Text, rewardH, rewardText)
			)
			table.insert(chips, { frame = section.title, width = width })
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

		-- The cues, in rows of as many cells as fit.
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

-- A cue pressed: its name and rarity, or that it is not found yet.
function InventoryIndex.tell(self: any, id: string)
	local items = self.ctx.lastItems
	local found = false
	for _, seenId in list(items and items.seen) do
		if seenId == id then
			found = true
			break
		end
	end
	if found then
		local cue = Catalog.get(id)
		local rarity = if cue then CueThumb.rarityName(cue.Rarity) else ""
		self.ctx.notice(WORDS.CueInfo:format(CueThumb.cueName(id), rarity))
	else
		self.ctx.notice(WORDS.NotFound)
	end
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
			local title = titleName(reply.title)
			if title ~= "" then
				ctx.notice(WORDS.TitleEarned:format(title), "Green")
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

function InventoryIndex.opened(_self: any) end

function InventoryIndex.shown(self: any)
	self.showing = true
	self:refreshPulses()
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
