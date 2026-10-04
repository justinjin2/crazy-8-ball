--!strict
-- ShopBlockCards: the Shop's lucky block cards (designer, 2026-10-04; the ChatGPT mockups in
-- 8ball-refs/gui-v3/mockups/chatgpt-2026-10-04). Each shows its turning 3D block
-- (BlockIcon) and its odds always, with no odds button:
--   * "Opening": the Grand Opening band: the block, the rainbow title, the two Unique cues
--     it could pull (a chase row each: picture, UNIQUE tag, chance), three buy columns (x1,
--     x3, x10: a Robux button with the old price crossed out, a money button, "save 12%"),
--     the guarantee line and the countdown. "VAULTED" once the deal has ended.
--   * "Mystery": the Mystery block: "Always in stock", the six tiers' odds strip and two buy
--     columns (x1, x10: money, then Robux with the sale sticker).
--   * "Slot": a restock slot (or the Starter Pack): the block, its name in its rarity's
--     colour, the odds strip, a money and a Robux button, "3 left for you". The VIP slot for
--     a non-VIP is a grey, locked tile with a Get VIP button.
-- Like ShopCards: one card per spec id, painted again on every redraw, laid out by the Shop.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local BlockIcon = require(script.Parent.BlockIcon)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)

local P = Config.UI.Shop.Page
local B = P.Block
local K = Config.UI.Kit
local RARITY: { [string]: { number } } = K.Rarity :: any
local RAINBOW: { { number } } = Config.Ranks.ChatRainbow :: any -- Secret's rim
local OPENING: { [string]: string } = Strings.Menus.Shop.Opening :: any
local color = HudParts.color
local span = ShopParts.span
local round = ShopParts.round

local ShopBlockCards = {}

export type Button = ShopCards.Button

-- A column of buttons under a count ("x3"; none on the Grand Opening band, whose Robux
-- buttons say the count): the Robux button (its old price crossed out above), the money
-- button, a note under ("save 12%").
export type Column = {
	label: string?,
	buttons: { Button },
	old: string?,
	note: string?,
	sticker: string?, -- a red sticker over the column's bottom ("-30% SALE")
}

-- One row of an odds strip: a rarity's (or a tier's) name and chance, in a rarity's colour;
-- `kind` (a block kind) puts that block's small picture on the row (the "Icons" style).
export type OddsRow = { name: string, display: string, rarity: string, kind: string? }

-- A chase row: a Unique cue the block could pull.
export type Chase = { cue: string, display: string }

-- A perk row on a pass band: a kit icon and a few words.
export type Perk = { icon: string, text: string }

export type Spec = {
	id: string,
	shape: string, -- "Opening" | "Mystery" | "Slot" | "Pass"
	kind: string, -- the lucky block kind drawn (BlockIcon)
	title: string,
	titleStyle: string?, -- "Rainbow", or nil
	titleTint: Color3?, -- a slot's name in its rarity's colour
	subtitle: string?,
	line: string?, -- an ink line under the title
	big: string?, -- a huge gold number (the Starter Pack's money)
	bigRich: boolean?, -- the big text is rich text (VIP's "x1 -> x2 MONEY")
	perks: { Perk }?, -- a pass band's perk list, in two columns
	tint: string?, -- a pass band's fill: "Cream" (VIP), else white
	pill: string?, -- a pill by the title ("Always in stock")
	pillTone: string?,
	odds: { OddsRow }?,
	oddsStyle: string?, -- "Icons": pale rows with a block picture and a coloured name (Mystery)
	oddsNote: string?, -- under the strip ("Epic cue or better: 0.13%")
	chase: { Chase }?,
	columns: { Column }?,
	buttons: { Button }?, -- a slot's buttons (money, then Robux)
	old: string?, -- the slot's crossed-out price
	note: string?, -- under the buttons ("3 left for you")
	status: string?, -- instead of the buttons ("VAULTED", "Sold out")
	statusTone: string?,
	timerEnds: number?,
	timerWords: string?,
	sticker: string?,
	stickerTone: string?,
	locked: boolean?, -- the VIP slot for a non-VIP: grey, a padlock, lockLine, one button
	lockLine: string?,
	shine: boolean?,
	dark: boolean?, -- the Grand Opening's festive navy fill (white words on it)
}

type OddsStrip = {
	root: Frame,
	rows: {
		{
			root: Frame,
			name: TextLabel,
			pct: TextLabel,
			rim: UIStroke,
			art: Frame,
			icon: BlockIcon.Icon?,
		}
	},
}
type PerkRow = { root: Frame, icon: ImageLabel, text: TextLabel }
-- A chase card: the cue's name in its colour, UNIQUE and LIMITED tags, the cue's picture at
-- the right, its chance in a rimmed pill at the bottom right.
type ChaseRow = {
	root: Frame,
	thumb: Frame?,
	name: TextLabel,
	tag: ShopParts.Pill,
	tag2: ShopParts.Pill,
	pct: ShopParts.Pill,
}
type ColumnUi = {
	root: Frame,
	box: UIStroke, -- the Mystery columns sit in a pale box
	label: TextLabel,
	old: TextLabel,
	buttons: { TextButton },
	actions: { () -> () },
	note: TextLabel,
	sticker: ShopParts.Pill,
}

export type Card = {
	id: string,
	shape: string,
	root: Frame,
	fill: Frame,
	artSlot: Frame,
	icon: BlockIcon.Icon?,
	title: TextLabel,
	subtitle: TextLabel,
	line: TextLabel,
	big: TextLabel,
	pill: ShopParts.Pill,
	odds: OddsStrip,
	oddsNote: TextLabel,
	chase: { ChaseRow },
	perks: { PerkRow },
	edgeColor: Color3, -- the card's usual edge (a tint swaps it)
	columns: { ColumnUi },
	buttons: { TextButton },
	actions: { () -> () },
	old: TextLabel,
	note: TextLabel,
	status: ShopParts.Pill,
	timer: TextLabel,
	sticker: Frame,
	stickerText: TextLabel,
	lock: ImageLabel,
	lockLine: TextLabel,
	stars: { ImageLabel }, -- the Grand Opening title's two stars
	spec: Spec?,
	style: string?,
	titleAnim: UIAnim.Handle?,
	sparkles: UIAnim.Handle?,
	height: number,
}

local MAX_ODDS = 8
local MAX_CHASE = 2
local MAX_PERKS = 6
local MAX_COLUMNS = 3
local MAX_BUTTONS = 2

local function numberColor(key: string): Color3
	return color(K.Numbers[key] or K.Numbers.Money)
end

local function rarityColor(rarity: string): Color3
	return color(RARITY[rarity] or RARITY.Default)
end

local function noop() end

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

local function makeOdds(parent: Instance): OddsStrip
	local root = HudParts.frame(parent, "Odds")
	root.ZIndex = 3
	local rows = {}
	for i = 1, MAX_ODDS do
		local row = HudParts.pill(root, "Row" .. i, rarityColor("Common"))
		row.ZIndex = 3
		row.Visible = false
		local name = HudParts.text(row, "Name", B.OddsTextPx[1], "")
		name.TextWrapped = false
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 4
		local pct = HudParts.text(row, "Pct", B.OddsTextPx[1], "")
		pct.AutoLocalize = false
		pct.TextWrapped = false
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.ZIndex = 4
		-- Secret's rainbow rim (a pass band's pills).
		local rim = Instance.new("UIStroke")
		rim.Name = "Rim"
		rim.Thickness = 2
		rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		rim.Enabled = false
		rim.Parent = row
		local rainbow = Instance.new("UIGradient")
		local stops = {}
		local n = #RAINBOW
		for j, c in RAINBOW do
			table.insert(stops, ColorSequenceKeypoint.new((j - 1) / math.max(1, n - 1), color(c)))
		end
		rainbow.Color = ColorSequence.new(stops)
		rainbow.Parent = rim
		local art = HudParts.frame(row, "Art")
		art.ZIndex = 4
		art.Visible = false
		rows[i] = { root = row, name = name, pct = pct, rim = rim, art = art, icon = nil }
	end
	return { root = root, rows = rows }
end

local function makeChase(parent: Instance, i: number): ChaseRow
	local root = HudParts.frame(parent, "Chase" .. i)
	root.BackgroundTransparency = 0
	root.BackgroundColor3 = HudParts.tone("Ink")
	root.ZIndex = 3
	root.Visible = false
	HudParts.corner(root, P.CardCornerPx - 4)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = rarityColor("Unique")
	edge.Thickness = 2
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = root
	local name = HudParts.text(root, "Name", B.ChaseNamePx[1], "")
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 5
	local tag = ShopParts.pill(root, "Tag", "Red")
	tag.root.BackgroundColor3 = rarityColor("Unique")
	tag.label.Text = OPENING.Unique
	local tag2 = ShopParts.pill(root, "Tag2", "Gold")
	tag2.label.Text = OPENING.Limited
	-- The chance: a dark pill with the Unique pink rim, like the card's.
	local pct = ShopParts.pill(root, "Pct", "Red")
	pct.root.BackgroundColor3 = HudParts.tone("Ink")
	pct.label.AutoLocalize = false
	local rim = pct.root:FindFirstChildOfClass("UIStroke")
	if rim then
		rim.Color = rarityColor("Unique")
	end
	return { root = root, thumb = nil, name = name, tag = tag, tag2 = tag2, pct = pct }
end

local function makePerk(parent: Instance, i: number): PerkRow
	local root = HudParts.frame(parent, "Perk" .. i)
	root.ZIndex = 3
	root.Visible = false
	local icon = HudParts.icon(root, "Star", "Icon")
	icon.ZIndex = 4
	local text = HudParts.note(root, "Words", B.PerkTextPx[1], "")
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.ZIndex = 4
	return { root = root, icon = icon, text = text }
end

local function makeButtons(parent: Instance, prefix: string): ({ TextButton }, { () -> () })
	local buttons: { TextButton } = {}
	local actions: { () -> () } = {}
	for i = 1, MAX_BUTTONS do
		actions[i] = noop
		local button = ShopParts.button(parent, prefix .. i, function()
			actions[i]()
		end)
		button.ZIndex = 5
		button.Visible = false
		buttons[i] = button
	end
	return buttons, actions
end

local function makeColumn(parent: Instance, i: number): ColumnUi
	local root = HudParts.frame(parent, "Column" .. i)
	root.ZIndex = 3
	root.Visible = false
	root.BackgroundColor3 = HudParts.tone("White")
	HudParts.corner(root, P.CardCornerPx - 4)
	local box = Instance.new("UIStroke")
	box.Name = "Edge"
	box.Color = color(Config.UI.Menu.Card.EdgeColor)
	box.Thickness = Config.UI.Shop.CardStrokePx
	box.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	box.Enabled = false
	box.Parent = root
	local sticker = ShopParts.pill(root, "Sticker", "Red")
	sticker.root.ZIndex = 8
	sticker.label.ZIndex = 9
	sticker.root.Visible = false
	local label = HudParts.text(root, "Label", B.ColumnLabelPx[1], "", numberColor("Count"))
	label.AutoLocalize = false
	label.TextWrapped = false
	label.ZIndex = 4
	local old = HudParts.text(root, "Old", P.OldPx[1], "", numberColor("Old"))
	old.AutoLocalize = false
	old.RichText = true
	old.TextWrapped = false
	old.ZIndex = 4
	local buttons, actions = makeButtons(root, "Buy")
	local note = HudParts.note(root, "Note", B.NotePx[1], "")
	note.ZIndex = 4
	return {
		root = root,
		box = box,
		label = label,
		old = old,
		buttons = buttons,
		actions = actions,
		note = note,
		sticker = sticker,
	}
end

--- A card of `shape` inside `parent` (the page's scroller).
function ShopBlockCards.new(parent: Instance, id: string, shape: string): Card
	local root, fill = ShopParts.card(parent, id)
	HudParts.corner(fill, P.CardCornerPx)
	local artSlot = HudParts.frame(root, "ArtSlot")
	artSlot.ZIndex = 3
	local title = HudParts.text(root, "Title", B.TitlePx[1], "")
	title.TextWrapped = false
	title.ZIndex = 4
	local subtitle = HudParts.text(root, "Subtitle", B.SubtitlePx[1], "")
	subtitle.TextWrapped = false
	subtitle.ZIndex = 4
	local line = HudParts.note(root, "Line", B.LinePx[1], "")
	line.ZIndex = 4
	local big = HudParts.text(root, "Big", P.TileBigPx[1], "", numberColor("Money"))
	big.AutoLocalize = false
	big.TextWrapped = false
	big.ZIndex = 4
	local pill = ShopParts.pill(root, "Pill", "Green")
	pill.root.Visible = false
	local oddsNote = HudParts.note(root, "OddsNote", B.LinePx[1], "")
	oddsNote.ZIndex = 4
	local chase = {}
	for i = 1, MAX_CHASE do
		chase[i] = makeChase(root, i)
	end
	local columns = {}
	for i = 1, MAX_COLUMNS do
		columns[i] = makeColumn(root, i)
	end
	local perks = {}
	for i = 1, MAX_PERKS do
		perks[i] = makePerk(root, i)
	end
	local edge = fill:FindFirstChild("Edge")
	local edgeColor = if edge and edge:IsA("UIStroke") then edge.Color else HudParts.tone("Ink")
	local buttons, actions = makeButtons(root, "Buy")
	local old = HudParts.text(root, "Old", P.OldPx[1], "", numberColor("Old"))
	old.AutoLocalize = false
	old.RichText = true
	old.TextWrapped = false
	old.ZIndex = 4
	local note = HudParts.note(root, "Note", B.NotePx[1], "")
	note.ZIndex = 4
	local status = ShopParts.pill(root, "Status", "Grey")
	status.root.Visible = false
	local timer = HudParts.text(root, "Timer", B.LinePx[1], "", numberColor("Count"))
	timer.AutoLocalize = false
	timer.TextWrapped = false
	timer.ZIndex = 4
	local sticker = HudParts.pill(root, "Sticker", HudParts.tone("Red"))
	sticker.AnchorPoint = Vector2.new(0.5, 0.5)
	sticker.Rotation = P.StickerDegrees
	sticker.ZIndex = 8
	sticker.Visible = false
	local stickerText = HudParts.text(sticker, "Words", P.StickerTextPx[1], "")
	stickerText.TextWrapped = false
	stickerText.Size = UDim2.fromScale(1, 1)
	stickerText.ZIndex = 9
	local lock = HudParts.icon(root, "Lock", "Lock")
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.ZIndex = 6
	lock.Visible = false
	local lockLine = HudParts.text(root, "LockLine", B.TileTitlePx[1], "", numberColor("Money"))
	lockLine.ZIndex = 4
	lockLine.Visible = false
	local stars = {}
	for i = 1, 2 do
		local star = HudParts.icon(root, "Star", "Star" .. i)
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.ZIndex = 5
		star.Visible = false
		stars[i] = star
	end

	return {
		id = id,
		shape = shape,
		root = root,
		fill = fill,
		artSlot = artSlot,
		icon = nil,
		title = title,
		subtitle = subtitle,
		line = line,
		big = big,
		pill = pill,
		odds = makeOdds(root),
		oddsNote = oddsNote,
		chase = chase,
		columns = columns,
		perks = perks,
		edgeColor = edgeColor,
		buttons = buttons,
		actions = actions,
		old = old,
		note = note,
		status = status,
		timer = timer,
		sticker = sticker,
		stickerText = stickerText,
		lock = lock,
		lockLine = lockLine,
		stars = stars,
		spec = nil,
		style = nil,
		titleAnim = nil,
		sparkles = nil,
		height = 0,
	}
end

--------------------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------------------

local function setStyle(card: Card, style: string?)
	if card.style == style then
		return
	end
	card.style = style
	if card.titleAnim then
		card.titleAnim.stop()
		card.titleAnim = nil
	end
	if style == "Rainbow" then
		card.titleAnim = UIAnim.rainbow(card.title)
	end
end

local function paintButtons(buttons: { TextButton }, actions: { () -> () }, specs: { Button }?)
	for i, button in buttons do
		local b = if specs then specs[i] else nil
		if b then
			ShopParts.setButton(button, b.text, b.tone, b.enabled, b.icon)
			ShopParts.setGift(button, b.gift)
			actions[i] = b.action
			button.Visible = true
		else
			ShopParts.setGift(button, nil)
			actions[i] = noop
			button.Visible = false
		end
	end
end

local function strike(text: string?): string
	return if text then ("<s>%s</s>"):format(text) else ""
end

--- Draw `spec` on `card`. Layout comes after.
function ShopBlockCards.paint(card: Card, spec: Spec)
	card.spec = spec
	-- The block: made once per kind (a redraw keeps the turning model).
	local icon = card.icon
	if icon == nil or icon.kind ~= spec.kind then
		if icon then
			icon:destroy()
		end
		card.icon = BlockIcon.new(card.artSlot, spec.kind)
	end
	card.title.Text = spec.title
	card.title.TextColor3 = spec.titleTint or HudParts.tone("White")
	setStyle(card, spec.titleStyle)
	card.subtitle.Text = spec.subtitle or ""
	card.subtitle.Visible = spec.subtitle ~= nil
	card.line.Text = spec.line or ""
	card.line.Visible = spec.line ~= nil
	card.big.RichText = spec.bigRich == true
	card.big.Text = spec.big or ""
	card.big.Visible = spec.big ~= nil
	card.pill.root.Visible = spec.pill ~= nil
	if spec.pill then
		card.pill.label.Text = spec.pill
		card.pill.root.BackgroundColor3 = HudParts.tone(spec.pillTone or "Green")
	end
	-- The odds strip: coloured rows with white words, or (the "Icons" style) pale rows with
	-- a small block and the kind's name in its colour.
	local odds = spec.odds or {}
	local icons = spec.oddsStyle == "Icons"
	for i, row in card.odds.rows do
		local o = odds[i]
		if o then
			row.root.Visible = true
			row.root.BackgroundColor3 = if icons
				then HudParts.tone("White")
				else rarityColor(o.rarity)
			local edge = row.root:FindFirstChild("Edge")
			if edge and edge:IsA("UIStroke") then
				edge.Color = if icons then card.edgeColor else HudParts.tone("Ink")
			end
			row.name.Text = o.name
			row.name.TextColor3 = if icons
				then CueThumb.accentColor(o.rarity)
				else HudParts.tone("White")
			row.pct.Text = o.display
			row.pct.TextColor3 = if icons then HudParts.tone("Ink") else HudParts.tone("White")
			local outline = row.pct:FindFirstChild("Outline")
			if outline and outline:IsA("UIStroke") then
				outline.Enabled = not icons
			end
			row.rim.Enabled = o.rarity == "Secret" and card.shape == "Pass"
			local kind = if icons then o.kind else nil
			if kind ~= nil then
				local icon = row.icon
				if icon == nil or icon.kind ~= kind then
					if icon then
						icon:destroy()
					end
					row.icon = BlockIcon.new(row.art, kind, true)
				end
				row.art.Visible = true
			else
				if row.icon then
					row.icon:destroy()
					row.icon = nil
				end
				row.art.Visible = false
			end
		else
			row.root.Visible = false
		end
	end
	card.odds.root.Visible = #odds > 0
	card.oddsNote.Text = spec.oddsNote or ""
	card.oddsNote.Visible = spec.oddsNote ~= nil
	-- The chase rows.
	local chase = spec.chase or {}
	for i, row in card.chase do
		local c = chase[i]
		if c then
			row.root.Visible = true
			local thumb = row.thumb
			if thumb then
				CueThumb.set(thumb, c.cue)
			else
				local made = CueThumb.new(row.root, c.cue)
				made.ZIndex = 5
				row.thumb = made
			end
			row.name.Text = string.upper(CueThumb.cueName(c.cue))
			row.name.TextColor3 = CueThumb.cueColor(c.cue)
			row.pct.label.Text = c.display
		else
			row.root.Visible = false
		end
	end
	-- The perk list.
	local perks = spec.perks or {}
	for i, row in card.perks do
		local perk = perks[i]
		if perk then
			row.root.Visible = true
			HudParts.setIcon(row.icon, perk.icon)
			row.text.Text = perk.text
		else
			row.root.Visible = false
		end
	end
	-- The buy columns (boxed, with gold count labels, on the Mystery band).
	local columns = spec.columns or {}
	local showStatus = spec.status ~= nil
	local boxed = card.shape == "Mystery"
	for i, ui in card.columns do
		local c = columns[i]
		if c and not showStatus then
			ui.root.Visible = true
			ui.root.BackgroundTransparency = if boxed then 0 else 1
			ui.box.Enabled = boxed
			ui.label.Text = c.label or ""
			ui.label.Visible = c.label ~= nil
			ui.label.TextColor3 = if boxed then color(B.ColumnLabelColor) else numberColor("Count")
			ui.sticker.label.Text = c.sticker or ""
			ui.sticker.root.Visible = c.sticker ~= nil
			ui.old.Text = strike(c.old)
			ui.old.Visible = c.old ~= nil
			ui.note.Text = c.note or ""
			ui.note.Visible = c.note ~= nil
			paintButtons(ui.buttons, ui.actions, c.buttons)
		else
			ui.root.Visible = false
			paintButtons(ui.buttons, ui.actions, nil)
		end
	end
	paintButtons(card.buttons, card.actions, if showStatus then nil else spec.buttons)
	card.old.Text = strike(spec.old)
	card.old.Visible = spec.old ~= nil and not showStatus
	card.note.Text = spec.note or ""
	card.note.Visible = spec.note ~= nil
	card.status.root.Visible = showStatus
	if showStatus then
		card.status.label.Text = spec.status or ""
		card.status.root.BackgroundColor3 = HudParts.tone(spec.statusTone or "Grey")
	end
	card.timer.Visible = spec.timerEnds ~= nil
	card.sticker.Visible = spec.sticker ~= nil
	card.stickerText.Text = spec.sticker or ""
	card.sticker.BackgroundColor3 = HudParts.tone(spec.stickerTone or "Red")
	-- Locked (the VIP slot): a grey card, the padlock over the block, the lock line. Dark (the
	-- Grand Opening): the festive navy, white words.
	local locked = spec.locked == true
	local dark = spec.dark == true
	card.fill.BackgroundColor3 = if locked
		then color(B.LockedColor)
		elseif dark then color(B.FestiveFill)
		elseif spec.tint == "Cream" then color(B.CreamFill)
		else HudParts.tone("White")
	local fade = card.fill:FindFirstChildOfClass("UIGradient")
	if fade then
		fade.Color = if dark
			then ColorSequence.new(color(B.FestiveFill), color(B.FestiveFade))
			else ColorSequence.new(HudParts.tone("White"), color(K.PanelFade))
	end
	local edge = card.fill:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = if spec.tint == "Cream" and not locked
			then color(B.CreamEdge)
			elseif dark then color(B.FestiveEdge)
			else card.edgeColor
	end
	local words = if dark then HudParts.tone("White") else HudParts.tone("Ink")
	card.line.TextColor3 = words
	card.oddsNote.TextColor3 = words
	for _, ui in card.columns do
		ui.note.TextColor3 = words
	end
	card.note.TextColor3 = words
	if spec.titleStyle == nil and spec.shape == "Opening" then
		card.title.TextColor3 = numberColor("Money")
	end
	for _, star in card.stars do
		star.Visible = spec.shape == "Opening" and not locked
	end
	card.lock.Visible = locked
	card.lockLine.Visible = locked and spec.lockLine ~= nil
	card.lockLine.Text = spec.lockLine or ""
	if card.icon then
		card.icon.root.Visible = true
	end
	if spec.shine and not card.sparkles then
		card.sparkles = UIAnim.sparkle(card.root, numberColor("Money"))
	elseif not spec.shine and card.sparkles then
		card.sparkles.stop()
		card.sparkles = nil
	end
	ShopBlockCards.tick(card, ShopParts.now())
end

--- The countdown. True when it just ran out (the Shop redraws).
function ShopBlockCards.tick(card: Card, now: number): boolean
	local spec = card.spec
	if not spec or not spec.timerEnds then
		return false
	end
	local words = spec.timerWords or "%s"
	card.timer.Text = words:format(ShopParts.timeLeft(spec.timerEnds - now))
	return now >= spec.timerEnds
end

--- The block's little pop (the Shop calls it now and then).
function ShopBlockCards.pop(card: Card)
	if card.icon then
		card.icon:pop()
	end
end

--------------------------------------------------------------------------------------------
-- Layout pieces
--------------------------------------------------------------------------------------------

local function widthOf(label: TextLabel, size: number): number
	return math.ceil(ShopParts.textWidth(label.ContentText, size)) + 8
end

local function place(object: GuiObject, x: number, y: number, w: number, h: number)
	object.Position = UDim2.fromOffset(x, y)
	object.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
end

-- Whether the strip is in the "Icons" style (a block picture on each row).
local function oddsIcons(card: Card): boolean
	return card.spec ~= nil and card.spec.oddsStyle == "Icons"
end

-- The odds strip's height at these sizes.
local function oddsHeight(card: Card, t: number): number
	local n = 0
	for _, row in card.odds.rows do
		if row.root.Visible then
			n += 1
		end
	end
	if n == 0 then
		return 0
	end
	local rowH = span(if oddsIcons(card) then B.OddsIconRowPx else B.OddsRowPx, t)
	return n * rowH + (n - 1) * span(B.OddsGapPx, t)
end

-- Lay the strip out at (x, y), `w` wide. Returns its height.
local function layoutOdds(card: Card, t: number, x: number, y: number, w: number): number
	local icons = oddsIcons(card)
	local rowH = span(if icons then B.OddsIconRowPx else B.OddsRowPx, t)
	local gap = span(B.OddsGapPx, t)
	local textSize =
		math.max(K.Text.Min - 2, span(if icons then B.OddsIconTextPx else B.OddsTextPx, t))
	local at = 0
	for _, row in card.odds.rows do
		if row.root.Visible then
			place(row.root, 0, at, w, rowH)
			HudParts.setTextSize(row.name, textSize, textSize)
			HudParts.setTextSize(row.pct, textSize, textSize)
			local pctW = math.min(round(w * 0.45), widthOf(row.pct, textSize))
			local nx = 8
			if row.art.Visible then
				local artPx = rowH + 4 -- the block pokes a little over the row
				place(row.art, 6, -2, artPx, artPx)
				nx = 6 + artPx + 6
			end
			place(row.name, nx, 0, w - pctW - nx - 8, rowH)
			place(row.pct, w - pctW - 8, 0, pctW, rowH)
			at += rowH + gap
		end
	end
	local h = math.max(0, at - gap)
	place(card.odds.root, x, y, w, h)
	return h
end

-- A pill's layout: words sized round, at (x, y). Returns its width.
local function layoutPill(
	pill: ShopParts.Pill,
	t: number,
	x: number,
	y: number,
	maxW: number
): number
	local h = span(B.PillPx, t)
	local size = math.max(K.Text.Min, span(B.PillTextPx, t))
	local w = ShopParts.setPill(pill, pill.label.Text, h, size, maxW)
	pill.root.AnchorPoint = Vector2.new(0, 0)
	pill.root.Position = UDim2.fromOffset(x, y)
	return w
end

-- The tilted sticker over the card's top right corner (or its top left with `left`).
local function layoutSticker(card: Card, t: number, w: number, left: boolean?)
	if not card.sticker.Visible then
		return
	end
	local h = span(P.StickerPx, t)
	local size = math.max(K.Text.Min, span(P.StickerTextPx, t))
	HudParts.setTextSize(card.stickerText, size)
	local sw = math.min(widthOf(card.stickerText, size) + 14, math.max(h, w - 16))
	card.sticker.Size = UDim2.fromOffset(sw, h)
	card.sticker.Rotation = if left then -P.StickerDegrees else P.StickerDegrees
	card.sticker.Position = if left
		then UDim2.fromOffset(round(sw / 2) + 6, 4)
		else UDim2.fromOffset(w - round(sw / 2) + 4, 4)
	card.stickerText.Position = UDim2.fromOffset(5, 0)
	card.stickerText.Size = UDim2.new(1, -10, 1, 0)
end

-- A chase card at (x, y), `w` by `h` (reference 12): the cue's name and its UNIQUE and
-- LIMITED tags at the top left, the cue's picture filling the right side, the chance in a
-- rimmed pill at the bottom right.
local function layoutChase(
	row: ChaseRow,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	local t = s.t
	place(row.root, x, y, w, h)
	local pad = round(s.pad * 0.6)
	local artW = round(w * B.ChaseThumbShare)
	if row.thumb then
		place(row.thumb, w - artW - pad, pad, artW, h - 2 * pad)
	end
	local nameH = math.max(K.Text.Min, span(B.ChaseNamePx, t))
	local tw = w - artW - 2 * pad
	HudParts.setTextSize(row.name, nameH)
	place(row.name, pad, pad, tw, nameH + 4)
	local tagH = span(B.PillPx, t) - 4
	local tagText = math.max(K.Text.Min, span(B.PillTextPx, t)) - 1
	local at = pad + nameH + 6
	local tagW = ShopParts.setPill(row.tag, row.tag.label.Text, tagH, tagText, tw)
	row.tag.root.AnchorPoint = Vector2.new(0, 0)
	row.tag.root.Position = UDim2.fromOffset(pad, at)
	local left = tw - tagW - 4
	row.tag2.root.Visible = left >= tagH
	if left >= tagH then
		ShopParts.setPill(row.tag2, row.tag2.label.Text, tagH, tagText, left)
		row.tag2.root.AnchorPoint = Vector2.new(0, 0)
		row.tag2.root.Position = UDim2.fromOffset(pad + tagW + 4, at)
	end
	local pctH = span(B.PillPx, t)
	ShopParts.setPill(row.pct, row.pct.label.Text, pctH, math.max(K.Text.Min, nameH - 2), tw)
	row.pct.root.AnchorPoint = Vector2.new(1, 1)
	row.pct.root.Position = UDim2.fromOffset(w - pad, h - pad)
end

-- A column's height at these sizes: the label, the old price, its buttons and the note.
local function columnHeight(ui: ColumnUi, s: ShopParts.Sizes): number
	local t = s.t
	local h = if ui.label.Visible then math.max(K.Text.Min, span(B.ColumnLabelPx, t)) + 4 else 0
	if ui.old.Visible then
		h += math.max(K.Text.Min, span(P.OldPx, t)) + 2
	end
	local n = 0
	for _, button in ui.buttons do
		if button.Visible then
			n += 1
		end
	end
	h += n * s.button + math.max(0, n - 1) * round(s.gap / 2)
	if ui.note.Visible then
		h += math.max(K.Text.Min - 2, span(B.NotePx, t)) + 6
	end
	if ui.box.Enabled then
		h += 2 * round(s.pad * 0.6) -- the box's padding
	end
	if ui.sticker.root.Visible then
		h += round(span(P.StickerPx, t) / 2) -- the sticker pokes below the last button
	end
	return h
end

local function layoutColumn(
	ui: ColumnUi,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	local t = s.t
	place(ui.root, x, y, w, h)
	local inset = if ui.box.Enabled then round(s.pad * 0.6) else 0
	local iw = w - 2 * inset
	local at = inset
	if ui.label.Visible then
		local labelH = math.max(K.Text.Min, span(B.ColumnLabelPx, t))
		HudParts.setTextSize(ui.label, labelH)
		place(ui.label, inset, at, iw, labelH + 4)
		at += labelH + 4
	end
	if ui.old.Visible then
		local oldH = math.max(K.Text.Min, span(P.OldPx, t))
		HudParts.setTextSize(ui.old, oldH)
		place(ui.old, inset, at, iw, oldH + 2)
		at += oldH + 2
	end
	local lastBottom = at
	for _, button in ui.buttons do
		if button.Visible then
			HudParts.setButtonTextSize(button, s.buttonText)
			ShopParts.placeButton(button, inset, at, iw, s.button)
			lastBottom = at + s.button
			at += s.button + round(s.gap / 2)
		end
	end
	if ui.sticker.root.Visible then
		-- Centred over the last button's bottom edge, tilted like the card stickers.
		local sh = span(P.StickerPx, t)
		local size = math.max(K.Text.Min, span(P.StickerTextPx, t))
		ShopParts.setPill(ui.sticker, ui.sticker.label.Text, sh, size, iw)
		ui.sticker.root.AnchorPoint = Vector2.new(0.5, 0.5)
		ui.sticker.root.Rotation = -P.StickerDegrees
		ui.sticker.root.Position = UDim2.fromOffset(round(w / 2), lastBottom)
		at += round(sh / 2)
	end
	if ui.note.Visible then
		local noteH = math.max(K.Text.Min - 2, span(B.NotePx, t))
		HudParts.setTextSize(ui.note, noteH, noteH)
		place(ui.note, inset, at, iw, noteH + 6)
	end
end

-- The status pill centred in a row at (x, y) `w` wide. Returns its height.
local function layoutStatus(card: Card, s: ShopParts.Sizes, x: number, y: number, w: number): number
	if not card.status.root.Visible then
		return 0
	end
	local h = s.button - 6
	ShopParts.setPill(card.status, card.status.label.Text, h, s.buttonText, w)
	card.status.root.AnchorPoint = Vector2.new(0.5, 0)
	card.status.root.Position = UDim2.fromOffset(x + round(w / 2), y)
	return h
end

--------------------------------------------------------------------------------------------
-- Bands (Opening, Mystery)
--------------------------------------------------------------------------------------------

-- The header row shared by the bands: the block at the left; the pill, title, subtitle, line
-- and timer at its right. Returns the row's height.
local function layoutHeader(card: Card, s: ShopParts.Sizes, w: number): number
	local t = s.t
	local pad = s.pad
	local art = span(B.ArtPx, t)
	local tx = pad + art + s.gap
	local tw = w - tx - pad
	local at = pad
	if card.pill.root.Visible then
		layoutPill(card.pill, t, tx, at, tw)
		at += span(B.PillPx, t) + 4
	end
	local titleH = math.max(K.Text.Min, span(B.TitlePx, t))
	HudParts.setTextSize(card.title, titleH)
	card.title.TextXAlignment = Enum.TextXAlignment.Left
	place(card.title, tx, at, tw, titleH + 4)
	at += titleH + 4
	if card.subtitle.Visible then
		local subH = math.max(K.Text.Min, span(B.SubtitlePx, t))
		HudParts.setTextSize(card.subtitle, subH)
		card.subtitle.TextXAlignment = Enum.TextXAlignment.Left
		place(card.subtitle, tx, at, tw, subH + 4)
		at += subH + 4
	end
	local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
	if card.line.Visible then
		local lineH = ShopParts.wrapHeight(card.line.ContentText, lineSize, tw, 2)
		HudParts.setTextSize(card.line, lineSize, lineSize)
		card.line.TextXAlignment = Enum.TextXAlignment.Left
		place(card.line, tx, at, tw, lineH)
		at += lineH
	end
	if card.timer.Visible then
		HudParts.setTextSize(card.timer, lineSize + 2)
		card.timer.TextXAlignment = Enum.TextXAlignment.Left
		place(card.timer, tx, at, tw, lineSize + 8)
		at += lineSize + 8
	end
	local h = math.max(art + 2 * pad, at + pad)
	place(card.artSlot, pad, round((h - art) / 2), art, art)
	return h
end

-- The buy columns side by side at (x, y), `w` wide. Returns their height.
local function layoutColumns(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number
): number
	local shown = {}
	for _, ui in card.columns do
		if ui.root.Visible then
			table.insert(shown, ui)
		end
	end
	if #shown == 0 then
		return layoutStatus(card, s, x, y, w)
	end
	local gap = s.gap
	local cw = math.floor((w - (#shown - 1) * gap) / #shown)
	local h = 0
	for _, ui in shown do
		h = math.max(h, columnHeight(ui, s))
	end
	for i, ui in shown do
		layoutColumn(ui, s, x + (i - 1) * (cw + gap), y, cw, h)
	end
	return h
end

local function hideSlotParts(card: Card)
	for _, row in card.perks do
		row.root.Visible = false
	end
	card.big.Visible = false
	card.lock.Visible = false
	card.lockLine.Visible = false
	for _, button in card.buttons do
		button.Visible = false
	end
	card.old.Visible = false
	card.note.Visible = false
end

-- The Grand Opening band (reference 12), `w` wide at (x, y): the NEW sticker, the crowned
-- block and its countdown down the left; the gold title between two stars, "YOU COULD
-- PULL...", the two chase cards, the three buy columns and the guarantee line at the right
-- (under the block on a narrow card). Returns its height.
local function layoutOpening(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number
): number
	local t = s.t
	local pad = s.pad
	local gap = s.gap
	hideSlotParts(card)
	card.pill.root.Visible = false
	card.line.Visible = false
	card.root.Position = UDim2.fromOffset(x, y)
	local art = span(B.OpeningArtPx, t)
	local wide = w >= B.WideMinPx
	local stickerRoom = if card.sticker.Visible then round(span(P.StickerPx, t) * 0.6) else 0
	local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
	local timerH = if card.timer.Visible then lineSize + 8 else 0
	local leftH = stickerRoom + art + timerH
	local lx = pad
	local rx, rw, ry
	if wide then
		rx, rw, ry = pad + art + gap, w - art - gap - 2 * pad, pad
	else
		rx, rw, ry = pad, w - 2 * pad, pad + leftH + round(gap / 2)
		lx = round((w - art) / 2)
	end
	place(card.artSlot, lx, pad + stickerRoom, art, art)
	if card.timer.Visible then
		HudParts.setTextSize(card.timer, lineSize + 2)
		card.timer.TextXAlignment = Enum.TextXAlignment.Center
		local tw = art + 2 * pad
		place(card.timer, math.max(0, lx - pad), pad + stickerRoom + art, tw, timerH)
	end
	-- The title between its stars.
	local at = ry
	local titleH = math.max(K.Text.Min, span(B.OpeningTitlePx, t))
	HudParts.setTextSize(card.title, titleH)
	card.title.TextXAlignment = Enum.TextXAlignment.Center
	local starPx = round(titleH * B.StarShare)
	local titleW = math.max(1, rw - 2 * (starPx + 6))
	place(card.title, rx + starPx + 6, at, titleW, titleH + 4)
	local textW = math.min(titleW, ShopParts.textWidth(card.title.ContentText, titleH) + 4)
	local cx = rx + round(rw / 2)
	local cy = at + round((titleH + 4) / 2)
	local reach = round(textW / 2) + round(starPx / 2) + 4
	card.stars[1].Size = UDim2.fromOffset(starPx, starPx)
	card.stars[2].Size = UDim2.fromOffset(starPx, starPx)
	card.stars[1].Position = UDim2.fromOffset(cx - reach, cy)
	card.stars[2].Position = UDim2.fromOffset(cx + reach, cy)
	at += titleH + 4
	if card.subtitle.Visible then
		local subH = math.max(K.Text.Min, span(B.SubtitlePx, t))
		HudParts.setTextSize(card.subtitle, subH)
		card.subtitle.TextXAlignment = Enum.TextXAlignment.Center
		place(card.subtitle, rx, at, rw, subH + 4)
		at += subH + 4
	end
	at += round(gap / 2)
	-- The chase cards, side by side.
	local shown = {}
	for _, row in card.chase do
		if row.root.Visible then
			table.insert(shown, row)
		end
	end
	if #shown > 0 then
		local ch = span(B.ChasePx, t)
		local cw = math.floor((rw - (#shown - 1) * gap) / #shown)
		for i, row in shown do
			layoutChase(row, s, rx + (i - 1) * (cw + gap), at, cw, ch)
		end
		at += ch + gap
	end
	at += layoutColumns(card, s, rx, at, rw)
	if card.oddsNote.Visible then
		-- The guarantee line.
		local size = math.max(K.Text.Min - 2, span(B.LinePx, t))
		local h = ShopParts.wrapHeight(card.oddsNote.ContentText, size, rw, 2)
		HudParts.setTextSize(card.oddsNote, size, size)
		card.oddsNote.TextXAlignment = Enum.TextXAlignment.Center
		place(card.oddsNote, rx, at + 4, rw, h)
		at += h + 4
	end
	local h = math.max(pad + leftH, at) + pad
	card.root.Size = UDim2.fromOffset(w, h)
	layoutSticker(card, t, w, true)
	card.height = h
	return h
end

--- Lay a band (Opening or Mystery) out `w` wide at (x, y). Returns its height.
function ShopBlockCards.layoutBand(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number
): number
	if card.shape == "Opening" then
		return layoutOpening(card, s, x, y, w)
	end
	local t = s.t
	local pad = s.pad
	local gap = s.gap
	hideSlotParts(card)
	card.root.Position = UDim2.fromOffset(x, y)
	local at = layoutHeader(card, s, w)
	local iw = w - 2 * pad
	do
		-- Mystery: the odds strip beside the buy columns (under them on a narrow card).
		local oddsH = oddsHeight(card, t)
		local noteSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
		local noteH = if card.oddsNote.Visible then noteSize + 6 else 0
		local wide = w >= B.WideMinPx and oddsH > 0
		if wide then
			local ow = math.min(B.OddsMaxWidthPx, round(iw * 0.5))
			layoutOdds(card, t, pad, at, ow)
			if card.oddsNote.Visible then
				HudParts.setTextSize(card.oddsNote, noteSize, noteSize)
				card.oddsNote.TextXAlignment = Enum.TextXAlignment.Center
				place(card.oddsNote, pad, at + oddsH + 2, ow, noteH)
			end
			local cx = pad + ow + gap
			local colH = layoutColumns(card, s, cx, at, w - cx - pad)
			at += math.max(oddsH + noteH + 2, colH)
		else
			if oddsH > 0 then
				layoutOdds(card, t, pad, at, iw)
				at += oddsH
				if card.oddsNote.Visible then
					HudParts.setTextSize(card.oddsNote, noteSize, noteSize)
					card.oddsNote.TextXAlignment = Enum.TextXAlignment.Center
					place(card.oddsNote, pad, at + 2, iw, noteH)
					at += noteH + 2
				end
				at += gap
			end
			at += layoutColumns(card, s, pad, at, iw)
		end
	end
	local h = at + pad
	card.root.Size = UDim2.fromOffset(w, h)
	layoutSticker(card, t, w)
	card.height = h
	return h
end

--------------------------------------------------------------------------------------------
-- Slot tiles
--------------------------------------------------------------------------------------------

local function slotButtonsHeight(card: Card, s: ShopParts.Sizes): number
	local n = 0
	for _, button in card.buttons do
		if button.Visible then
			n += 1
		end
	end
	local h = if card.status.root.Visible
		then s.button - 6
		else n * s.button + math.max(0, n - 1) * round(s.gap / 2)
	if card.old.Visible then
		h += math.max(K.Text.Min, span(P.OldPx, s.t)) + 4
	end
	return h
end

--------------------------------------------------------------------------------------------
-- Pass bands (Starter Pack, VIP): side by side in the Offer grid
--------------------------------------------------------------------------------------------

-- The odds pills in rows: as many per row as stay OddsPillMinPx wide. Returns the rows'
-- total height (0 without odds) and the pills per row.
local function oddsPillRows(card: Card, t: number, w: number): (number, number)
	local n = 0
	for _, row in card.odds.rows do
		if row.root.Visible then
			n += 1
		end
	end
	if n == 0 then
		return 0, 0
	end
	local gap = span(B.OddsPillGapPx, t)
	local perRow = math.max(1, math.min(n, math.floor((w + gap) / (B.OddsPillMinPx + gap))))
	local rows = math.ceil(n / perRow)
	return rows * span(B.OddsPillPx, t) + (rows - 1) * gap, perRow
end

-- Lay the pills out at (x, y), `w` wide: the name over the chance, centred. Returns the height.
local function layoutOddsPills(card: Card, t: number, x: number, y: number, w: number): number
	local h, perRow = oddsPillRows(card, t, w)
	if h == 0 then
		return 0
	end
	local gap = span(B.OddsPillGapPx, t)
	local pillH = span(B.OddsPillPx, t)
	local pillW = math.floor((w - (perRow - 1) * gap) / perRow)
	local textSize = math.max(K.Text.Min - 2, span(B.OddsTextPx, t))
	local i = 0
	for _, row in card.odds.rows do
		if row.root.Visible then
			local col = i % perRow
			local line = math.floor(i / perRow)
			place(row.root, col * (pillW + gap), line * (pillH + gap), pillW, pillH)
			HudParts.setTextSize(row.name, textSize, textSize)
			HudParts.setTextSize(row.pct, textSize, textSize)
			row.name.TextXAlignment = Enum.TextXAlignment.Center
			row.pct.TextXAlignment = Enum.TextXAlignment.Center
			local half = round(pillH / 2)
			place(row.name, 2, 1, pillW - 4, half)
			place(row.pct, 2, half - 1, pillW - 4, pillH - half)
			i += 1
		end
	end
	place(card.odds.root, x, y, w, h)
	return h
end

-- The perk list's height `w` wide: two columns when each has PerkColumnMinPx.
local function perksHeight(card: Card, t: number, w: number): (number, number)
	local n = 0
	for _, row in card.perks do
		if row.root.Visible then
			n += 1
		end
	end
	if n == 0 then
		return 0, 0
	end
	local cols = if w >= 2 * B.PerkColumnMinPx then 2 else 1
	local lines = math.ceil(n / cols)
	return lines * span(B.PerkRowPx, t), cols
end

local function layoutPerks(card: Card, t: number, x: number, y: number, w: number): number
	local h, cols = perksHeight(card, t, w)
	if h == 0 then
		return 0
	end
	local rowH = span(B.PerkRowPx, t)
	local colW = math.floor(w / cols)
	local textSize = math.max(K.Text.Min - 2, span(B.PerkTextPx, t))
	local iconPx = rowH - 4
	local i = 0
	for _, row in card.perks do
		if row.root.Visible then
			local col = i % cols
			local line = math.floor(i / cols)
			place(row.root, x + col * colW, y + line * rowH, colW, rowH)
			place(row.icon, 0, 2, iconPx, iconPx)
			HudParts.setTextSize(row.text, textSize, textSize)
			place(row.text, iconPx + 6, 0, colW - iconPx - 8, rowH)
			i += 1
		end
	end
	return h
end

-- The header's stack beside the art: the title, the big number, the line. Returns the height
-- of the stack (laid out when `lay`).
local function passStack(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	lay: boolean
): number
	local t = s.t
	local at = 0
	local titleH = math.max(K.Text.Min, span(B.PassTitlePx, t))
	if lay then
		HudParts.setTextSize(card.title, titleH)
		card.title.TextXAlignment = Enum.TextXAlignment.Left
		place(card.title, x, y + at, w, titleH + 4)
	end
	at += titleH + 2
	if card.big.Visible then
		local bigH = math.max(K.Text.Min, span(B.PassBigPx, t))
		if lay then
			HudParts.setTextSize(card.big, bigH)
			card.big.TextXAlignment = Enum.TextXAlignment.Left
			place(card.big, x, y + at, w, bigH + 4)
		end
		at += bigH + 4
	end
	local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
	if card.line.Visible then
		local lineH = ShopParts.wrapHeight(card.line.ContentText, lineSize, w, 3)
		if lay then
			HudParts.setTextSize(card.line, lineSize, lineSize)
			card.line.TextXAlignment = Enum.TextXAlignment.Left
			place(card.line, x, y + at, w, lineH)
		end
		at += lineH + 2
	end
	return at
end

-- The bottom row's height: the buttons (or the status) at the right, the timer or the ribbon
-- and old price at the left.
local function passBottomHeight(card: Card, s: ShopParts.Sizes): number
	local n = 0
	for _, button in card.buttons do
		if button.Visible then
			n += 1
		end
	end
	local h = if card.status.root.Visible
		then s.button - 6
		else math.max(s.button, n * s.button + math.max(0, n - 1) * round(s.gap / 2))
	return math.max(h, span(B.PillPx, s.t))
end

local function passNeed(card: Card, s: ShopParts.Sizes, w: number): number
	local t = s.t
	local pad = s.pad
	local iw = w - 2 * pad
	local art = span(B.PassArtPx, t)
	local tw = iw - art - s.gap
	local stack = passStack(card, s, 0, 0, tw, false)
	local h = pad + math.max(art, stack) + round(s.gap / 2)
	local odds = oddsPillRows(card, t, iw)
	if odds > 0 then
		h += odds + round(s.gap / 2)
	end
	local perks = perksHeight(card, t, iw)
	if perks > 0 then
		h += perks + round(s.gap / 2)
	end
	h += passBottomHeight(card, s)
	if card.note.Visible then
		h += math.max(K.Text.Min - 2, span(B.NotePx, t)) + 6
	end
	return h + pad
end

local function layoutPass(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	local t = s.t
	local pad = s.pad
	local iw = w - 2 * pad
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	for _, ui in card.columns do
		ui.root.Visible = false
	end
	for _, row in card.chase do
		row.root.Visible = false
	end
	card.subtitle.Visible = false
	card.lock.Visible = false
	card.lockLine.Visible = false
	card.oddsNote.Visible = false
	local art = span(B.PassArtPx, t)
	local tx = pad + art + s.gap
	local tw = iw - art - s.gap
	local stack = passStack(card, s, tx, pad, tw, true)
	local headH = math.max(art, stack)
	place(card.artSlot, pad, pad + round((headH - art) / 2), art, art)
	local at = pad + headH + round(s.gap / 2)
	local odds = layoutOddsPills(card, t, pad, at, iw)
	if odds > 0 then
		at += odds + round(s.gap / 2)
	end
	local perks = layoutPerks(card, t, pad, at, iw)
	if perks > 0 then
		at += perks + round(s.gap / 2)
	end
	-- The bottom row sits at the bottom (rows of bands even out): the button(s) at the right,
	-- the timer, or the ribbon and the crossed-out price, at the left.
	local bottom = h - pad
	if card.note.Visible then
		local noteH = math.max(K.Text.Min - 2, span(B.NotePx, t))
		HudParts.setTextSize(card.note, noteH, noteH)
		card.note.TextXAlignment = Enum.TextXAlignment.Center
		place(card.note, pad, bottom - noteH - 4, iw, noteH + 4)
		bottom -= noteH + 6
	end
	local rowH = passBottomHeight(card, s)
	local top = bottom - rowH
	local bw = math.max(s.button * 2, round(iw * 0.42))
	local bx = pad + iw - bw
	if card.status.root.Visible then
		local sh = s.button - 6
		layoutStatus(card, s, bx, top + round((rowH - sh) / 2), bw)
	else
		local by = top
		for _, button in card.buttons do
			if button.Visible then
				HudParts.setButtonTextSize(button, s.buttonText)
				ShopParts.placeButton(button, bx, by, bw, s.button)
				by += s.button + round(s.gap / 2)
			end
		end
	end
	local lx, lw = pad, bx - pad - s.gap
	if card.pill.root.Visible then
		local pw = layoutPill(card.pill, t, lx, top + round((rowH - span(B.PillPx, t)) / 2), lw)
		lx += pw + s.gap
		lw -= pw + s.gap
	end
	if card.old.Visible then
		local oldH = math.max(K.Text.Min, span(P.OldPx, t))
		HudParts.setTextSize(card.old, oldH)
		card.old.TextXAlignment = Enum.TextXAlignment.Right
		place(card.old, lx, top + round((rowH - oldH) / 2), math.max(1, lw), oldH + 2)
	end
	if card.timer.Visible then
		local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
		HudParts.setTextSize(card.timer, lineSize + 2)
		card.timer.TextXAlignment = Enum.TextXAlignment.Left
		place(card.timer, lx, top, math.max(1, lw), rowH)
	end
	layoutSticker(card, t, w)
	card.height = h
end

--- A slot tile's (or a pass band's) height `w` wide at these sizes (before its row evens
--- them out).
function ShopBlockCards.tileNeed(card: Card, s: ShopParts.Sizes, w: number): number
	if card.shape == "Pass" then
		return passNeed(card, s, w)
	end
	local t = s.t
	local pad = s.pad
	local iw = w - 2 * pad
	local h = pad + span(B.TileArtPx, t) + round(s.gap / 2)
	h += math.max(K.Text.Min, span(B.TileTitlePx, t)) + 4
	if card.big.Visible then
		h += math.max(K.Text.Min, span(P.TileBigPx, t)) + 2
	end
	local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
	if card.timer.Visible then
		h += lineSize + 4
	end
	if card.line.Visible then
		h += ShopParts.wrapHeight(card.line.ContentText, lineSize, iw, 3) + 2
	end
	if card.lockLine.Visible then
		h += ShopParts.wrapHeight(card.lockLine.ContentText, lineSize + 2, iw, 3) + 2
	end
	local odds = oddsHeight(card, t)
	if odds > 0 then
		h += odds + round(s.gap / 2)
	end
	h += round(s.gap / 2) + slotButtonsHeight(card, s)
	if card.note.Visible then
		h += math.max(K.Text.Min - 2, span(B.NotePx, t)) + 6
	end
	return h + pad
end

--- Lay a slot tile out at (x, y), `w` by `h`: the block, the name, the odds, the buttons at
--- the bottom.
function ShopBlockCards.layoutTile(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	if card.shape == "Pass" then
		layoutPass(card, s, x, y, w, h)
		return
	end
	local t = s.t
	local pad = s.pad
	local iw = w - 2 * pad
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	for _, ui in card.columns do
		ui.root.Visible = false
	end
	for _, row in card.chase do
		row.root.Visible = false
	end
	card.subtitle.Visible = false
	card.pill.root.Visible = false
	local art = span(B.TileArtPx, t)
	place(card.artSlot, round((w - art) / 2), pad, art, art)
	if card.lock.Visible then
		local lockPx = span(B.LockPx, t)
		card.lock.Position = UDim2.fromOffset(round(w / 2), pad + round(art * 0.62))
		card.lock.Size = UDim2.fromOffset(lockPx, lockPx)
	end
	local at = pad + art + round(s.gap / 2)
	local titleH = math.max(K.Text.Min, span(B.TileTitlePx, t))
	HudParts.setTextSize(card.title, titleH)
	card.title.TextXAlignment = Enum.TextXAlignment.Center
	place(card.title, pad, at, iw, titleH + 4)
	at += titleH + 4
	if card.big.Visible then
		local bigH = math.max(K.Text.Min, span(P.TileBigPx, t))
		HudParts.setTextSize(card.big, bigH)
		place(card.big, pad, at, iw, bigH + 2)
		at += bigH + 2
	end
	local lineSize = math.max(K.Text.Min - 2, span(B.LinePx, t))
	if card.timer.Visible then
		-- A tile's timer is a centred line under the title (a band's sits by the subtitle).
		HudParts.setTextSize(card.timer, lineSize)
		card.timer.TextXAlignment = Enum.TextXAlignment.Center
		place(card.timer, pad, at, iw, lineSize + 4)
		at += lineSize + 4
	end
	if card.line.Visible then
		local lineH = ShopParts.wrapHeight(card.line.ContentText, lineSize, iw, 3)
		HudParts.setTextSize(card.line, lineSize, lineSize)
		card.line.TextXAlignment = Enum.TextXAlignment.Center
		place(card.line, pad, at, iw, lineH)
		at += lineH + 2
	end
	if card.lockLine.Visible then
		local lineH = ShopParts.wrapHeight(card.lockLine.ContentText, lineSize + 2, iw, 3)
		HudParts.setTextSize(card.lockLine, lineSize + 2)
		card.lockLine.TextXAlignment = Enum.TextXAlignment.Center
		place(card.lockLine, pad, at, iw, lineH)
		at += lineH + 2
	end
	local odds = oddsHeight(card, t)
	if odds > 0 then
		layoutOdds(card, t, pad, at, iw)
		at += odds + round(s.gap / 2)
	end
	card.oddsNote.Visible = false
	-- The buttons sit at the bottom; the note under them.
	local bottom = h - pad
	if card.note.Visible then
		local noteH = math.max(K.Text.Min - 2, span(B.NotePx, t))
		HudParts.setTextSize(card.note, noteH, noteH)
		card.note.TextXAlignment = Enum.TextXAlignment.Center
		place(card.note, pad, bottom - noteH - 4, iw, noteH + 4)
		bottom -= noteH + 6
	end
	if card.status.root.Visible then
		local sh = s.button - 6
		layoutStatus(card, s, pad, bottom - sh, iw)
	else
		for i = MAX_BUTTONS, 1, -1 do
			local button = card.buttons[i]
			if button.Visible then
				HudParts.setButtonTextSize(button, s.buttonText)
				ShopParts.placeButton(button, pad, bottom - s.button, iw, s.button)
				bottom -= s.button + round(s.gap / 2)
			end
		end
		if card.old.Visible then
			local oldH = math.max(K.Text.Min, span(P.OldPx, t))
			HudParts.setTextSize(card.old, oldH)
			card.old.TextXAlignment = Enum.TextXAlignment.Center
			place(card.old, pad, bottom - oldH - 2, iw, oldH + 2)
		end
	end
	layoutSticker(card, t, w)
	card.height = h
end

--- The card's buttons a gamepad may land on, in order.
function ShopBlockCards.selectables(card: Card): { GuiObject }
	local list: { GuiObject } = {}
	local function add(button: TextButton)
		if button.Visible then
			local square = ShopParts.giftOf(button)
			if square then
				table.insert(list, square)
			end
			table.insert(list, button)
		end
	end
	for _, ui in card.columns do
		if ui.root.Visible then
			for _, button in ui.buttons do
				add(button)
			end
		end
	end
	for _, button in card.buttons do
		add(button)
	end
	return list
end

function ShopBlockCards.destroy(card: Card)
	for _, row in card.odds.rows do
		if row.icon then
			row.icon:destroy()
		end
	end
	if card.titleAnim then
		card.titleAnim.stop()
	end
	if card.sparkles then
		card.sparkles.stop()
	end
	if card.icon then
		card.icon:destroy()
	end
	card.root:Destroy()
end

return ShopBlockCards
