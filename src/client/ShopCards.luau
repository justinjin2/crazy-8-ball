--!strict
-- ShopCards: the cards of the one scrolling Shop page (GUI lane, designer 2026-10-03; refs 01
-- and 08 in docs/prompts/GUI_PROMPT.md). Big and simple: huge numbers in the number palette
-- (gold money, green gains, sky-blue counts and timers), one big before -> after arrow, a red
-- crossed-out price above Buy where a real old price exists, a tilted corner sticker ("BEST
-- VALUE", "30% OFF"), and always something moving (the art floats, deal titles flow in
-- rainbow, lucky items sparkle).
--
-- A card is drawn from a Spec (ShopPage builds them from ShopState); the Shop keeps one card
-- per spec id and paints it again on every redraw, so nothing is rebuilt while it is open.
-- Shapes:
--   * "Hero": a wide row: the art square at the left, title / huge numbers / a line / a
--     countdown in the middle, the old price and Buy (one or two buttons) at the right.
--   * "Tile": a grid cell: the art on top, the name, the huge number, a line, then the old
--     price and Buy at the bottom.
--   * "Note": a pale gold card with one centred line (paid random items where restricted).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)

local P = Config.UI.Shop.Page
local K = Config.UI.Kit
local color = HudParts.color
local span = ShopParts.span
local round = ShopParts.round

local ShopCards = {}

export type Button = {
	text: string,
	tone: string, -- a kit candy tone: Green, Yellow, Blue, Grey ...
	enabled: boolean,
	icon: string?,
	action: () -> (),
}

export type Spec = {
	id: string, -- stable across redraws ("Vip", "Pack4", "Restock:Rare")
	shape: string, -- "Hero" | "Tile" | "Note"
	icon: string?, -- a Config.UI.Kit.Icons key for the art
	cue: string?, -- or a cue's picture
	title: string,
	titleStyle: string?, -- "Rainbow" (deals), "Vip" (gold shimmer), nil (white)
	from: string?, -- before -> after: the "before" (white), then the arrow, then `big`
	big: string?, -- the huge number
	bigTint: string?, -- a Config.UI.Kit.Numbers key (Money by default)
	after: string?, -- a word after the big number ("MONEY")
	line: string?, -- one short ink line
	timerEnds: number?, -- a countdown (sky blue): unix end
	timerWords: string?, -- its sentence ("Ends in %s")
	sticker: string?, -- the tilted corner sticker
	stickerTone: string?, -- its kit colour (Red by default)
	old: string?, -- the crossed-out price above Buy (a real old price only)
	buttons: { Button }?,
	status: string?, -- instead of Buy: "Owned", "Sold out"
	statusTone: string?,
	shine: boolean?, -- sparkles over the card
	lit: boolean?, -- the gold breathing edge (the pack that covers what you need)
}

export type Card = {
	id: string,
	shape: string,
	root: Frame,
	fill: Frame,
	artSlot: Frame,
	art: ImageLabel,
	thumb: Frame?,
	title: TextLabel,
	from: TextLabel,
	arrow: ImageLabel,
	big: TextLabel,
	after: TextLabel,
	line: TextLabel,
	timer: TextLabel,
	sticker: Frame,
	stickerText: TextLabel,
	old: TextLabel,
	buttons: { TextButton },
	actions: { () -> () },
	status: ShopParts.Pill,
	spec: Spec?,
	style: string?, -- the title style drawn now
	titleAnim: UIAnim.Handle?,
	vipGradient: UIGradient?,
	sparkles: UIAnim.Handle?,
	pulse: UIAnim.Handle?,
	height: number, -- what its last layout needed
}

local MAX_BUTTONS = 2

local function numberColor(key: string?): Color3
	local values = K.Numbers[key or "Money"] or K.Numbers.Money
	return color(values)
end

--------------------------------------------------------------------------------------------
-- Build
--------------------------------------------------------------------------------------------

--- A card of `shape` inside `parent` (the page's scroller).
function ShopCards.new(parent: Instance, id: string, shape: string): Card
	local root, fill = ShopParts.card(parent, id)
	HudParts.corner(fill, P.CardCornerPx)
	local artSlot = HudParts.frame(root, "ArtSlot")
	artSlot.ZIndex = 3
	local art = HudParts.icon(artSlot, "Case", "Art")
	art.AnchorPoint = Vector2.new(0.5, 0.5)
	art.Position = UDim2.fromScale(0.5, 0.5)
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 3
	art.ScaleType = Enum.ScaleType.Fit
	UIAnim.bob(art)

	local title = HudParts.text(root, "Title", P.HeroTitlePx[1], "")
	title.TextWrapped = false
	title.ZIndex = 4
	local from = HudParts.text(root, "From", P.HeroBigPx[1], "")
	from.AutoLocalize = false
	from.TextWrapped = false
	from.ZIndex = 4
	local arrow = HudParts.icon(root, "Arrow", "Arrow")
	arrow.ZIndex = 4
	arrow.ImageColor3 = color(K.Colors.Red)
	local big = HudParts.text(root, "Big", P.HeroBigPx[1], "")
	big.AutoLocalize = false
	big.TextWrapped = false
	big.ZIndex = 4
	local after = HudParts.text(root, "After", P.HeroTitlePx[1], "")
	after.TextWrapped = false
	after.ZIndex = 4
	local line = HudParts.note(root, "Line", P.HeroLinePx[1], "")
	line.ZIndex = 4
	local timer = HudParts.text(root, "Timer", P.HeroLinePx[1], "", numberColor("Count"))
	timer.AutoLocalize = false
	timer.TextWrapped = false
	timer.ZIndex = 4

	-- The sticker: a tilted pill over the top-right corner.
	local sticker = HudParts.pill(root, "Sticker", HudParts.tone("Red"))
	sticker.AnchorPoint = Vector2.new(0.5, 0.5)
	sticker.Rotation = P.StickerDegrees
	sticker.ZIndex = 8
	sticker.Visible = false
	local stickerText = HudParts.text(sticker, "Words", P.StickerTextPx[1], "")
	stickerText.TextWrapped = false
	stickerText.Size = UDim2.fromScale(1, 1)
	stickerText.ZIndex = 9

	-- The old price: red, struck through.
	local old = HudParts.text(root, "Old", P.OldPx[1], "", numberColor("Old"))
	old.AutoLocalize = false
	old.RichText = true
	old.TextWrapped = false
	old.ZIndex = 4

	local card: Card
	local buttons: { TextButton } = {}
	local actions: { () -> () } = {}
	for i = 1, MAX_BUTTONS do
		actions[i] = function() end
		local button = ShopParts.button(root, "Buy" .. i, function()
			actions[i]()
		end)
		button.ZIndex = 5
		button.Visible = false
		buttons[i] = button
	end
	local status = ShopParts.pill(root, "Status", "Green")
	status.root.Visible = false

	card = {
		id = id,
		shape = shape,
		root = root,
		fill = fill,
		artSlot = artSlot,
		art = art,
		thumb = nil,
		title = title,
		from = from,
		arrow = arrow,
		big = big,
		after = after,
		line = line,
		timer = timer,
		sticker = sticker,
		stickerText = stickerText,
		old = old,
		buttons = buttons,
		actions = actions,
		status = status,
		spec = nil,
		style = nil,
		titleAnim = nil,
		vipGradient = nil,
		sparkles = nil,
		pulse = nil,
		height = 0,
	}
	return card
end

--------------------------------------------------------------------------------------------
-- Paint
--------------------------------------------------------------------------------------------

-- The title's look: rainbow flowing letters (deals), VIP's gold shimmer, or plain white.
local function setStyle(card: Card, style: string?)
	if card.style == style then
		return
	end
	card.style = style
	if card.titleAnim then
		card.titleAnim.stop()
		card.titleAnim = nil
	end
	if card.vipGradient then
		card.vipGradient:Destroy()
		card.vipGradient = nil
	end
	if style == "Rainbow" then
		card.titleAnim = UIAnim.rainbow(card.title)
	elseif style == "Vip" then
		local keys = {}
		local colors: { { number } } = K.Vip.Colors :: any
		for i, c in colors do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color(c)))
		end
		local gradient = Instance.new("UIGradient")
		gradient.Name = "VipGold"
		gradient.Color = ColorSequence.new(keys)
		gradient.Parent = card.title
		card.vipGradient = gradient
		-- The gold slides slowly along the letters.
		card.titleAnim = UIAnim.loop(card.title, function(clock)
			gradient.Offset = Vector2.new(math.sin(clock * 1.6) * 0.35, 0)
		end)
	end
end

--- Draw `spec` on `card` (words, art, buttons, effects). Layout comes after.
function ShopCards.paint(card: Card, spec: Spec)
	card.spec = spec
	if spec.cue then
		local thumb = card.thumb
		if thumb then
			CueThumb.set(thumb, spec.cue)
		else
			thumb = CueThumb.new(card.art, spec.cue)
			card.thumb = thumb
		end
		card.art.Image = ""
		card.art.Visible = true
	else
		if card.thumb then
			card.thumb:Destroy()
			card.thumb = nil
		end
		HudParts.setIcon(card.art, spec.icon or "Case")
	end
	card.title.Text = spec.title
	setStyle(card, spec.titleStyle)
	card.from.Text = spec.from or ""
	card.from.Visible = spec.from ~= nil
	card.arrow.Visible = spec.from ~= nil
	card.big.Text = spec.big or ""
	card.big.Visible = spec.big ~= nil
	card.big.TextColor3 = numberColor(spec.bigTint)
	card.after.Text = spec.after or ""
	card.after.Visible = spec.after ~= nil
	card.line.Text = spec.line or ""
	card.line.Visible = spec.line ~= nil
	card.timer.Visible = spec.timerEnds ~= nil
	card.sticker.Visible = spec.sticker ~= nil
	card.stickerText.Text = spec.sticker or ""
	card.sticker.BackgroundColor3 = HudParts.tone(spec.stickerTone or "Red")
	card.old.Text = if spec.old then ("<s>%s</s>"):format(spec.old) else ""
	card.old.Visible = spec.old ~= nil

	local buttons = spec.buttons or {}
	local showStatus = spec.status ~= nil
	for i, button in card.buttons do
		local b = buttons[i]
		if b and not showStatus then
			ShopParts.setButton(button, b.text, b.tone, b.enabled, b.icon)
			card.actions[i] = b.action
			button.Visible = true
		else
			card.actions[i] = function() end
			button.Visible = false
		end
	end
	card.status.root.Visible = showStatus
	if showStatus then
		card.status.label.Text = spec.status or ""
		card.status.root.BackgroundColor3 = HudParts.tone(spec.statusTone or "Green")
	end

	-- Sparkles on a shining card; the gold breathing edge on a lit one.
	if spec.shine and not card.sparkles then
		card.sparkles = UIAnim.sparkle(card.root, numberColor("Money"))
	elseif not spec.shine and card.sparkles then
		card.sparkles.stop()
		card.sparkles = nil
	end
	ShopParts.setLit(card.fill, spec.lit == true)
	if spec.lit and not card.pulse then
		card.pulse = UIAnim.pulse(card.root)
	elseif not spec.lit and card.pulse then
		card.pulse.stop()
		card.pulse = nil
	end
	ShopCards.tick(card, ShopParts.now())
end

--- The countdown. True when it just ran out (the Shop redraws).
function ShopCards.tick(card: Card, now: number): boolean
	local spec = card.spec
	if not spec or not spec.timerEnds then
		return false
	end
	local words = spec.timerWords or "%s"
	card.timer.Text = words:format(ShopParts.timeLeft(spec.timerEnds - now))
	return now >= spec.timerEnds
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- The width a label's words take at `size` (plus a little room for the outline).
local function widthOf(label: TextLabel, size: number): number
	return math.ceil(ShopParts.textWidth(label.ContentText, size)) + 8
end

-- The before -> after row centred in (or left from) `x`, `w` wide, `h` tall at `y`.
local function layoutBig(card: Card, x: number, y: number, w: number, h: number, centre: boolean)
	local size = h
	local parts: { { object: GuiObject, w: number } } = {}
	local gap = math.max(4, round(size * 0.15))
	if card.from.Visible then
		HudParts.setTextSize(card.from, size)
		table.insert(parts, { object = card.from :: GuiObject, w = widthOf(card.from, size) })
		local arrowSize = round(size * P.ArrowShare)
		card.arrow.Size = UDim2.fromOffset(arrowSize, arrowSize)
		table.insert(parts, { object = card.arrow :: GuiObject, w = arrowSize })
	end
	if card.big.Visible then
		HudParts.setTextSize(card.big, size)
		table.insert(parts, { object = card.big :: GuiObject, w = widthOf(card.big, size) })
	end
	if card.after.Visible then
		local afterSize = math.max(K.Text.Min, round(size * 0.62))
		HudParts.setTextSize(card.after, afterSize)
		table.insert(
			parts,
			{ object = card.after :: GuiObject, w = widthOf(card.after, afterSize) }
		)
	end
	local total = (#parts - 1) * gap
	for _, part in parts do
		total += part.w
	end
	-- Too wide: every part gives up the same share (their words shrink to fit).
	local squeeze = if total > w then w / total else 1
	local at = x + (if centre then math.max(0, round((w - total * squeeze) / 2)) else 0)
	for _, part in parts do
		local pw = math.floor(part.w * squeeze)
		local object = part.object
		if object == card.arrow then
			local a = math.floor(card.arrow.Size.X.Offset * squeeze)
			card.arrow.Size = UDim2.fromOffset(a, a)
			card.arrow.Position = UDim2.fromOffset(at, y + round((h - a) / 2))
		else
			object.Position = UDim2.fromOffset(at, y)
			object.Size = UDim2.fromOffset(math.max(1, pw), h)
		end
		at += pw + math.floor(gap * squeeze)
	end
end

-- The sticker over the top-right corner, sized round its words.
local function layoutSticker(card: Card, s: ShopParts.Sizes, w: number)
	if not card.sticker.Visible then
		return
	end
	local h = span(P.StickerPx, s.t)
	local size = math.max(K.Text.Min, span(P.StickerTextPx, s.t))
	HudParts.setTextSize(card.stickerText, size)
	local sw = math.min(widthOf(card.stickerText, size) + 14, math.max(h, w - 16))
	card.sticker.Size = UDim2.fromOffset(sw, h)
	card.sticker.Position = UDim2.fromOffset(w - round(sw / 2) + 4, 4)
	card.stickerText.Position = UDim2.fromOffset(5, 0)
	card.stickerText.Size = UDim2.new(1, -10, 1, 0)
end

-- How many buttons show.
local function buttonCount(card: Card): number
	local n = 0
	for _, button in card.buttons do
		if button.Visible then
			n += 1
		end
	end
	return n
end

-- The bottom-right (Hero) or bottom (Tile) stack: the old price, then the buttons, or the
-- status pill. `x`, `w`: the column; `bottom`: its lowest pixel. Returns the stack's top.
local function layoutBuy(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	w: number,
	bottom: number
): number
	local n = buttonCount(card)
	local gap = round(s.gap / 2)
	local at = bottom
	if card.status.root.Visible then
		local h = s.button - 6
		ShopParts.setPill(card.status, card.status.label.Text, h, s.buttonText, w)
		card.status.root.AnchorPoint = Vector2.new(0.5, 1)
		card.status.root.Position = UDim2.fromOffset(x + round(w / 2), at)
		at -= h
	else
		for i = MAX_BUTTONS, 1, -1 do
			local button = card.buttons[i]
			if button.Visible then
				HudParts.setButtonTextSize(button, s.buttonText)
				button.Size = UDim2.fromOffset(w, s.button)
				button.Position = UDim2.fromOffset(x, at - s.button)
				at -= s.button + (if i > 1 then gap else 0)
			end
		end
		if n == 0 then
			at = bottom
		end
	end
	if card.old.Visible then
		local size = math.max(K.Text.Min, span(P.OldPx, s.t))
		HudParts.setTextSize(card.old, size)
		at -= 2
		card.old.Position = UDim2.fromOffset(x, at - size - 4)
		card.old.Size = UDim2.fromOffset(w, size + 4)
		at -= size + 4
	end
	return at
end

-- The buy stack's height (for a tile's need).
local function buyHeight(card: Card, s: ShopParts.Sizes): number
	local n = buttonCount(card)
	local h = if card.status.root.Visible
		then s.button - 6
		else n * s.button + math.max(0, n - 1) * round(s.gap / 2)
	if card.old.Visible then
		h += math.max(K.Text.Min, span(P.OldPx, s.t)) + 6
	end
	return h
end

--- Lay a hero card out `w` wide at (x, y). Returns its height.
function ShopCards.layoutHero(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number
): number
	local t = s.t
	local pad = s.pad
	local h = span(P.HeroPx, t)
	-- A card with two buttons and an old price needs more room in its buy column.
	h = math.max(h, buyHeight(card, s) + 2 * pad)
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	local artSize = math.min(h - 2 * pad, span(P.HeroPx, t) - 2 * pad)
	card.artSlot.Position = UDim2.fromOffset(pad, round((h - artSize) / 2))
	card.artSlot.Size = UDim2.fromOffset(artSize, artSize)
	local bw = math.min(span(P.HeroButtonWidthPx, t), round(w * 0.3))
	local bx = w - pad - bw
	layoutBuy(card, s, bx, bw, h - round((h - buyHeight(card, s)) / 2))
	-- The middle column, centred vertically.
	local mx = pad + artSize + s.gap
	local mw = math.max(1, bx - s.gap - mx)
	local titleH = math.max(K.Text.Min, span(P.HeroTitlePx, t))
	local bigH = if card.big.Visible or card.from.Visible
		then math.max(K.Text.Min, span(P.HeroBigPx, t))
		else 0
	local lineSize = math.max(K.Text.Min, span(P.HeroLinePx, t))
	local lineH = if card.line.Visible
		then ShopParts.wrapHeight(card.line.ContentText, lineSize, mw, 2)
		else 0
	local timerH = if card.timer.Visible then lineSize + 4 else 0
	local block = titleH + 4 + bigH + lineH + timerH
	local at = math.max(pad, round((h - block) / 2))
	HudParts.setTextSize(card.title, titleH)
	card.title.TextXAlignment = Enum.TextXAlignment.Left
	card.title.Position = UDim2.fromOffset(mx, at)
	card.title.Size = UDim2.fromOffset(mw, titleH + 4)
	at += titleH + 4
	if bigH > 0 then
		layoutBig(card, mx, at, mw, bigH, false)
		at += bigH
	end
	HudParts.setTextSize(card.line, lineSize)
	card.line.TextXAlignment = Enum.TextXAlignment.Left
	card.line.Position = UDim2.fromOffset(mx, at)
	card.line.Size = UDim2.fromOffset(mw, math.max(1, lineH))
	at += lineH
	HudParts.setTextSize(card.timer, lineSize)
	card.timer.TextXAlignment = Enum.TextXAlignment.Left
	card.timer.Position = UDim2.fromOffset(mx, at)
	card.timer.Size = UDim2.fromOffset(mw, math.max(1, timerH))
	layoutSticker(card, s, w)
	card.height = h
	return h
end

--- A tile's height `w` wide at these sizes (before the row evens them out).
function ShopCards.tileNeed(card: Card, s: ShopParts.Sizes, w: number): number
	local t = s.t
	local base = span(P.TilePx, t)
	local pad = s.pad
	local nameH = math.max(K.Text.Min, span(P.TileNamePx, t)) + 4
	local bigH = if card.big.Visible or card.from.Visible
		then math.max(K.Text.Min, span(P.TileBigPx, t))
		else 0
	local lineSize = math.max(K.Text.Min, span(P.TileLinePx, t))
	local lineH = if card.line.Visible
		then ShopParts.wrapHeight(card.line.ContentText, lineSize, w - 2 * pad, 2)
		else 0
	local timerH = if card.timer.Visible then lineSize + 4 else 0
	local art = round(base * P.TileArtShare)
	local need = pad + art + nameH + bigH + lineH + timerH + s.gap + buyHeight(card, s) + pad
	return math.max(base, need)
end

--- Lay a tile out at (x, y), `w` by `h`.
function ShopCards.layoutTile(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	local t = s.t
	local pad = s.pad
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	local base = span(P.TilePx, t)
	local art = round(base * P.TileArtShare)
	card.artSlot.Position = UDim2.fromOffset(round((w - art) / 2), pad)
	card.artSlot.Size = UDim2.fromOffset(art, art)
	local iw = w - 2 * pad
	local at = pad + art
	local nameH = math.max(K.Text.Min, span(P.TileNamePx, t))
	HudParts.setTextSize(card.title, nameH)
	card.title.TextXAlignment = Enum.TextXAlignment.Center
	card.title.Position = UDim2.fromOffset(pad, at)
	card.title.Size = UDim2.fromOffset(iw, nameH + 4)
	at += nameH + 4
	if card.big.Visible or card.from.Visible then
		local bigH = math.max(K.Text.Min, span(P.TileBigPx, t))
		layoutBig(card, pad, at, iw, bigH, true)
		at += bigH
	end
	local lineSize = math.max(K.Text.Min, span(P.TileLinePx, t))
	local lineH = if card.line.Visible
		then ShopParts.wrapHeight(card.line.ContentText, lineSize, iw, 2)
		else 0
	HudParts.setTextSize(card.line, lineSize)
	card.line.TextXAlignment = Enum.TextXAlignment.Center
	card.line.Position = UDim2.fromOffset(pad, at)
	card.line.Size = UDim2.fromOffset(iw, math.max(1, lineH))
	at += lineH
	HudParts.setTextSize(card.timer, lineSize)
	card.timer.TextXAlignment = Enum.TextXAlignment.Center
	card.timer.Position = UDim2.fromOffset(pad, at)
	card.timer.Size = UDim2.fromOffset(iw, lineSize + 4)
	layoutBuy(card, s, pad, iw, h - pad)
	layoutSticker(card, s, w)
	card.height = h
end

--- Lay a note card out `w` wide at (x, y). Returns its height.
function ShopCards.layoutNote(
	card: Card,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number
): number
	local size = math.max(K.Text.Min, span(P.HeroLinePx, s.t))
	local iw = w - 2 * s.pad
	local lineH = ShopParts.wrapHeight(card.line.ContentText, size, iw, 3)
	local h = lineH + 2 * s.pad
	card.root.Position = UDim2.fromOffset(x, y)
	card.root.Size = UDim2.fromOffset(w, h)
	card.fill.BackgroundColor3 = color(P.NoteColor)
	card.artSlot.Visible = false
	card.title.Visible = false
	HudParts.setTextSize(card.line, size)
	card.line.TextXAlignment = Enum.TextXAlignment.Center
	card.line.Position = UDim2.fromOffset(s.pad, s.pad)
	card.line.Size = UDim2.fromOffset(iw, lineH)
	card.height = h
	return h
end

--- The card's buttons a gamepad may land on, in order.
function ShopCards.selectables(card: Card): { GuiObject }
	local list: { GuiObject } = {}
	for _, button in card.buttons do
		if button.Visible then
			table.insert(list, button)
		end
	end
	return list
end

function ShopCards.destroy(card: Card)
	if card.titleAnim then
		card.titleAnim.stop()
	end
	if card.sparkles then
		card.sparkles.stop()
	end
	if card.pulse then
		card.pulse.stop()
	end
	card.root:Destroy()
end

return ShopCards
