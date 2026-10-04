--!strict
-- ShopParts: the building blocks the Shop shares (ShopMenu, ShopCards, ShopPage, ShopNeed,
-- ShopOdds; docs/prompts/ECONOMY_UI_PROMPT.md section 11):
--
--   * the sizes of one layout, from MenuFrame's geo (phone to full size, Config.UI.Shop);
--   * a plain card (white, a pale edge, like reference 03's reward tiles) that is not a button;
--   * a price (the cash bundle and "$1,500", or a Robux price with Roblox's own glyph in the
--     text, and the old price struck through during a sale or an offer);
--   * pills ("20% OFF", "+7%", "Owned #412"), buy buttons (candy buttons whose words may wrap
--     onto two lines, so "Need $12,000 more" is never cut off), countdown words;
--   * a manual scroller and the grid fit every page uses: as many columns as keep the cards
--     wide enough, the fewest rows whose cards are still tall enough, centred when they fit.
--
-- Times are unix seconds on the server's clock (workspace:GetServerTimeNow()), as ShopState's.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)

local U = Config.UI.Shop
local K = Config.UI.Kit
local CARD = Config.UI.Menu.Card
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local color = HudParts.color
local tone = HudParts.tone
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local TIME: { [string]: string } = Strings.Menus :: any

local ShopParts = {}

-- The sizes of one layout (ShopParts.sizes), in whole pixels.
export type Sizes = {
	t: number, -- 0 on a phone-sized panel, 1 on a full one
	pad: number, -- inside a card
	gap: number, -- between cards
	lineGap: number, -- between lines of text in a card
	scrollPad: number,
	button: number, -- a buy button's height
	buttonText: number,
	name: number, -- text sizes
	price: number,
	old: number,
	line: number,
	pill: number, -- a pill's height
	pillText: number,
}

export type Price = {
	root: Frame,
	cash: ImageLabel,
	now: TextLabel,
	old: TextLabel,
}

export type Pill = { root: Frame, label: TextLabel }

export type Fit = {
	cols: number,
	rows: number,
	w: number, -- one cell
	h: number,
	height: number, -- everything, top to bottom (the canvas)
	x: { number }, -- each cell's left and top, in order
	y: { number },
}

--------------------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------------------

local function round(n: number): number
	return math.floor(n + 0.5)
end
ShopParts.round = round

--- A { phone, full } pair at t, in whole pixels.
function ShopParts.span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end
local span = ShopParts.span

--- This layout's sizes, from MenuFrame's geo (nil geo: the phone sizes).
function ShopParts.sizes(geo: any?): Sizes
	local t = if geo and type(geo.t) == "number" then geo.t else 0
	local least = K.Text.Min
	return {
		t = t,
		pad = span(U.CardPadPx, t),
		gap = span(U.CardGapPx, t),
		lineGap = span(U.LineGapPx, t),
		scrollPad = U.ScrollPadPx,
		button = math.max(Config.UI.Menu.Frame.TouchMinPx, span(U.ButtonPx, t)),
		buttonText = math.max(least, span(U.ButtonTextPx, t)),
		name = math.max(least, span(U.NameTextPx, t)),
		price = math.max(least, span(U.PriceTextPx, t)),
		old = math.max(least, span(U.OldPriceTextPx, t)),
		line = math.max(least, span(U.LineTextPx, t)),
		pill = span(U.PillPx, t),
		pillText = math.max(least, span(U.PillTextPx, t)),
	}
end

function ShopParts.textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- How tall `text` wraps at `size` in `width` (plain text; pass a label's ContentText), with
--- a little room, at least one line and at most `maxLines`.
function ShopParts.wrapHeight(text: string, size: number, width: number, maxLines: number?): number
	local one = TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).Y
	local wrapped =
		TextService:GetTextSize(text, size, FONT, Vector2.new(math.max(1, width), 10000)).Y
	local lines = if one > 0 then math.max(1, round(wrapped / one)) else 1
	return (size + 4) * math.min(lines, maxLines or 3)
end

--- The server's clock (unix seconds), which every end time in ShopState uses.
function ShopParts.now(): number
	return workspace:GetServerTimeNow()
end

--- The player's money, from the save's attribute (the server's truth; 0 before it loads).
function ShopParts.money(): number
	local player = Players.LocalPlayer
	local value = if player then player:GetAttribute("Money") else nil
	return if type(value) == "number" and value == value then value else 0
end

--- Time left, as the column's timer says it: "6d 4h" from a day, "2:59:12" from an hour,
--- else "14:32".
function ShopParts.timeLeft(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	if s >= U.DaysFromSeconds then
		return TIME.TimeDays:format(s // 86400, (s % 86400) // 3600)
	end
	if s >= 3600 then
		return TIME.TimeHours:format(s // 3600, (s % 3600) // 60, s % 60)
	end
	return TIME.TimeMinutes:format(s // 60, s % 60)
end

--- A Robux price: Roblox's Robux glyph (U+E002, in Strings) and the number with commas.
function ShopParts.robux(amount: number): string
	return COPY.Robux:format(Format.commas(amount))
end

--- A product's Robux price: the live one from ShopState's products[key], else Config's
--- fallback (shown even while the product is not made yet, marked "Coming soon").
function ShopParts.robuxOf(product: any, key: string): number
	if type(product) == "table" and type(product.robux) == "number" and product.robux > 0 then
		return product.robux
	end
	local list: { [string]: { Robux: number } } = Config.Products.List :: any
	local row = list[key]
	return if row and type(row.Robux) == "number" then row.Robux else 0
end

--- The words of a "Coming soon" tag that fit `width` at `size` with the pill's room: "Coming
--- soon", or the kit's short "Soon" where that would not fit (never cut, never under the text
--- minimum).
function ShopParts.soonText(width: number, size: number): string
	if ShopParts.textWidth(COPY.ComingSoon, size) + 2 * U.PillPadPx <= width then
		return COPY.ComingSoon
	end
	return COPY.Soon
end

--- "Need $1,200 more".
function ShopParts.need(gap: number): string
	return COPY.Need:format(Format.money(math.max(0, gap)))
end

--------------------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------------------

--- A plain card: a clear frame (place and size it) holding a white face with a pale edge and
--- a soft fade, like reference 03's reward tiles. Put its contents in `root` at ZIndex 2 up.
function ShopParts.card(parent: Instance, name: string): (Frame, Frame)
	local root = HudParts.frame(parent, name)
	root.ZIndex = 2
	local fill = HudParts.frame(root, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = tone("White")
	fill.ZIndex = 1
	HudParts.corner(fill, U.CardCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = color(CARD.EdgeColor)
	edge.Thickness = U.CardStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(tone("White"), color(K.PanelFade))
	fade.Parent = fill
	return root, fill
end

--- Light a card's edge in the kit's gold (the pack that covers what you need), or put it back.
function ShopParts.setLit(fill: Frame, on: boolean)
	local edge = fill:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = if on then tone("Gold") else color(CARD.EdgeColor)
		edge.Thickness = if on then K.SelectedStrokePx else U.CardStrokePx
	end
end

--- An ink line of small text (a detail: the guarantee, "412 of 1,000 sold"), left aligned.
function ShopParts.line(parent: Instance, name: string): TextLabel
	local label = HudParts.note(parent, name, U.LineTextPx[1], "")
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	return label
end

--- A white name with an ink outline, left aligned, on one line (it shrinks to fit).
function ShopParts.name(parent: Instance, name: string): TextLabel
	local label = HudParts.text(parent, name, U.NameTextPx[1], "")
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	return label
end

--------------------------------------------------------------------------------------------
-- Pills
--------------------------------------------------------------------------------------------

--- A small pill in a kit colour ("Gold", "Red", "Green", "Blue"; "White" writes in ink).
function ShopParts.pill(parent: Instance, name: string, toneName: string): Pill
	local root = HudParts.pill(parent, name, tone(toneName))
	root.ZIndex = 5
	local label = if toneName == "White"
		then HudParts.note(root, "Words", U.PillTextPx[1], "")
		else HudParts.text(root, "Words", U.PillTextPx[1], "")
	label.TextWrapped = false
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 6
	return { root = root, label = label }
end

--- Set a pill's words and size it round them (at most `maxWidth` wide; they shrink to fit).
--- Returns its width.
function ShopParts.setPill(
	pill: Pill,
	text: string,
	height: number,
	textSize: number,
	maxWidth: number?
): number
	pill.label.Text = text
	HudParts.setTextSize(pill.label, textSize)
	local width = math.ceil(ShopParts.textWidth(text, textSize)) + 2 * U.PillPadPx
	width = math.max(height, width)
	if maxWidth then
		width = math.min(width, math.max(height, maxWidth))
	end
	pill.root.Size = UDim2.fromOffset(width, height)
	pill.label.Position = UDim2.fromOffset(U.PillPadPx / 2, 0)
	pill.label.Size = UDim2.new(1, -U.PillPadPx, 1, 0)
	return width
end

--------------------------------------------------------------------------------------------
-- Prices
--------------------------------------------------------------------------------------------

--- A price: the cash bundle, the price (white, ink outline) and the old price struck through.
function ShopParts.price(parent: Instance, name: string): Price
	local root = HudParts.frame(parent, name)
	root.ZIndex = 3
	local cash = HudParts.icon(root, "CashSingle", "Cash")
	cash.AnchorPoint = Vector2.new(0, 0.5)
	cash.ZIndex = 3
	local now = HudParts.text(root, "Now", U.PriceTextPx[1], "")
	now.AutoLocalize = false -- a number
	now.TextWrapped = false
	now.TextXAlignment = Enum.TextXAlignment.Left
	now.ZIndex = 4
	local old = HudParts.note(root, "Old", U.OldPriceTextPx[1], "")
	old.AutoLocalize = false
	old.RichText = true -- <s> strikes it through
	old.TextWrapped = false
	old.TextXAlignment = Enum.TextXAlignment.Left
	old.ZIndex = 4
	return { root = root, cash = cash, now = now, old = old }
end

--- Set a price's words: `now` ("$1,200" or a Robux price), `old` (struck through; nil for
--- none) and whether the cash bundle shows (money, not Robux).
function ShopParts.setPrice(price: Price, now: string, old: string?, cash: boolean)
	price.now.Text = now
	price.now.Visible = now ~= ""
	price.old.Text = if old then ("<s>%s</s>"):format(old) else ""
	price.old.Visible = old ~= nil
	price.cash.Visible = cash
	price.root:SetAttribute("OldText", old)
end

--- Lay a price out in a row `height` tall at these text sizes, at most `maxWidth` wide, left
--- aligned (or centred with `centre`). Returns the width it takes.
function ShopParts.layoutPrice(
	price: Price,
	height: number,
	nowSize: number,
	oldSize: number,
	maxWidth: number,
	centre: boolean?
): number
	HudParts.setTextSize(price.now, nowSize)
	HudParts.setTextSize(price.old, oldSize)
	local cashSize = if price.cash.Visible then round(nowSize * U.CashShare) else 0
	local gap = math.max(3, round(nowSize * 0.2))
	local shown = price.now.Visible and price.now.Text ~= ""
	local nowW = if shown then math.ceil(ShopParts.textWidth(price.now.Text, nowSize)) + 6 else 0
	local oldText = price.root:GetAttribute("OldText")
	local oldW = if price.old.Visible and type(oldText) == "string"
		then math.ceil(ShopParts.textWidth(oldText, oldSize)) + 4
		else 0
	local total = (if cashSize > 0 then cashSize + gap else 0)
		+ nowW
		+ (if oldW > 0 and nowW > 0 then gap else 0)
		+ oldW
	-- Too wide: the numbers give up the room (their text shrinks to fit, never under the min).
	local squeeze = if total > maxWidth then maxWidth / total else 1
	nowW = math.floor(nowW * squeeze)
	oldW = math.floor(oldW * squeeze)
	total = math.min(total, maxWidth)
	local x = if centre then round((maxWidth - total) / 2) else 0
	price.root.Size = UDim2.fromOffset(maxWidth, height)
	if cashSize > 0 then
		price.cash.Size = UDim2.fromOffset(cashSize, cashSize)
		price.cash.Position = UDim2.fromOffset(x, round(height / 2))
		x += cashSize + gap
	end
	price.now.Position = UDim2.fromOffset(x, 0)
	price.now.Size = UDim2.fromOffset(math.max(1, nowW), height)
	x += if nowW > 0 then nowW + gap else 0
	price.old.Position = UDim2.fromOffset(x, 0)
	price.old.Size = UDim2.fromOffset(math.max(1, oldW), height)
	return total
end

--------------------------------------------------------------------------------------------
-- Buttons
--------------------------------------------------------------------------------------------

--- A candy buy button (Green to start). Its words may wrap onto a second line, so a long
--- "Need $12,000 more" or a translation shrinks and wraps instead of being cut off. It plays
--- the Click sound itself only through `action` (the caller's), like the menus' own buttons.
function ShopParts.button(parent: Instance, name: string, action: () -> ()): TextButton
	local button = HudParts.candy(parent, "", action, "Green")
	button.Name = name
	button.ZIndex = 3
	local parts = HudParts.candyParts(button)
	if parts then
		parts.label.TextWrapped = true
		parts.label.RichText = true -- a struck-through old price inside the words
	end
	return button
end

-- The gift squares beside Robux buttons (Config.UI.Shop.Gift), by their button.
local gifts: { [TextButton]: { square: TextButton, action: (() -> ())? } } = {}
local G = Config.UI.Shop.Gift

--- Give (or take away) `button` a gift square at its left: a small candy with the gift icon
--- that runs `action` (opens the Gift Player popup). Nil takes it away. The square is a
--- sibling of the button, laid out by ShopParts.placeButton.
function ShopParts.setGift(button: TextButton, action: (() -> ())?)
	local entry = gifts[button]
	if entry == nil then
		local parent = button.Parent
		if action == nil or parent == nil then
			return
		end
		local square = HudParts.candy(parent, "", function()
			local now = gifts[button]
			if now and now.action then
				now.action()
			end
		end, G.SquareTone, "Gift")
		square.Name = button.Name .. "Gift"
		square.ZIndex = button.ZIndex
		entry = { square = square, action = nil }
		gifts[button] = entry
		button.Destroying:Connect(function()
			gifts[button] = nil
			square:Destroy()
		end)
		button:GetPropertyChangedSignal("Visible"):Connect(function()
			local e = gifts[button]
			if e then
				e.square.Visible = button.Visible and e.action ~= nil
			end
		end)
	end
	entry.action = action
	entry.square.Visible = button.Visible and action ~= nil
end

--- The gift square beside `button` while it shows (a gamepad lands on it too), or nil.
function ShopParts.giftOf(button: TextButton): TextButton?
	local entry = gifts[button]
	if entry ~= nil and entry.action ~= nil and button.Visible then
		return entry.square
	end
	return nil
end

--- Place a buy button in the box (x, y, w, h); its gift square, when it has one, takes the
--- left end of the box (a square `h` tall) and the button the rest.
function ShopParts.placeButton(button: TextButton, x: number, y: number, w: number, h: number)
	local square = ShopParts.giftOf(button)
	if square ~= nil then
		local side = math.min(h, math.floor(w * 0.4))
		square.Position = UDim2.fromOffset(x, y + math.floor((h - side) / 2))
		square.Size = UDim2.fromOffset(side, side)
		HudParts.setMinHit(square, Config.UI.Menu.Frame.TouchMinPx)
		x += side + G.SquareGapPx
		w = math.max(1, w - side - G.SquareGapPx)
	end
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
end

--- A buy button's words, colour and whether it may be pressed (a disabled one is faded and
--- not selectable). An icon key puts that icon left of the words.
function ShopParts.setButton(
	button: TextButton,
	text: string,
	toneName: string,
	enabled: boolean,
	icon: string?
)
	HudParts.setText(button, text)
	HudParts.setTone(button, toneName)
	HudParts.setButtonIcon(button, icon)
	HudParts.setEnabled(button, enabled)
end

--------------------------------------------------------------------------------------------
-- Scrolling and fitting
--------------------------------------------------------------------------------------------

--- A vertical scroller filling `parent`, laid out by hand: put cards in it at offsets and set
--- its canvas height with setCanvas. A gamepad selection inside scrolls itself into view.
function ShopParts.scroller(parent: Instance, name: string): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.CanvasSize = UDim2.new()
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.None
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.ScrollBarThickness = U.ScrollBarPx
	scroll.ScrollBarImageColor3 = color(Config.UI.Menu.Scroll.BarColor)
	-- Always inset, so the cards' width never jumps when the bar comes and goes.
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = parent
	return scroll
end

--- The width and height cards may use inside a scroller of this size (its pad and bar out).
function ShopParts.inner(size: Vector2, s: Sizes): Vector2
	return Vector2.new(
		math.max(1, size.X - 2 * s.scrollPad - U.ScrollBarPx),
		math.max(1, size.Y - 2 * s.scrollPad)
	)
end

function ShopParts.setCanvas(scroll: ScrollingFrame, height: number)
	scroll.CanvasSize = UDim2.fromOffset(0, math.ceil(height))
end

export type FitOptions = {
	gap: number,
	minW: number, -- a card at least this wide (fewer columns otherwise)
	maxW: number?, -- and at most this wide (the row is centred)
	needH: number, -- a card needs this height (the page scrolls rather than squash it)
	maxH: number?, -- and never grows past this
	aspect: number?, -- the height / width the fit prefers (1.2 by default)
	top: number?, -- room kept above the grid (a banner), inside `size`
}

--- Fit n cards into `size` (a page's inner size): every choice of rows 1..n with as many
--- columns as that needs, preferring cards that need no scrolling, then the shape closest to
--- `aspect`. The last row is centred; the whole grid is centred when it fits. Positions are
--- offsets from the inner area's top left (add the scroller's pad).
function ShopParts.fit(n: number, size: Vector2, o: FitOptions): Fit
	local count = math.max(1, n)
	local gap = o.gap
	local top = o.top or 0
	local width, height = size.X, size.Y - top
	local aspect = o.aspect or 1.2
	local best: { cols: number, rows: number, w: number, h: number, score: number }? = nil
	local lastCols = -1
	for rows = 1, count do
		local cols = math.ceil(count / rows)
		if cols == lastCols then
			continue
		end
		lastCols = cols
		local w = math.floor((width - (cols - 1) * gap) / cols)
		if w < o.minW and cols > 1 then
			continue
		end
		if o.maxW then
			w = math.min(w, o.maxW)
		end
		local h = math.floor((height - (rows - 1) * gap) / rows)
		local scrolls = h < o.needH
		h = math.max(h, o.needH)
		if o.maxH then
			h = math.max(o.needH, math.min(h, o.maxH))
		end
		local score = math.abs(math.log((h / math.max(1, w)) / aspect))
		if scrolls then
			score += 100 + rows -- scrolling only when nothing else fits, and the fewest rows then
		end
		if best == nil or score < best.score then
			best = { cols = cols, rows = rows, w = w, h = h, score = score }
		end
	end
	local chosen = best or { cols = 1, rows = count, w = width, h = o.needH, score = 0 }
	local cols, rows, w, h = chosen.cols, chosen.rows, math.max(1, chosen.w), chosen.h
	local total = rows * h + (rows - 1) * gap
	local y0 = top + math.max(0, math.floor((height - total) / 2))
	local xs, ys = {}, {}
	for i = 1, count do
		local row = (i - 1) // cols
		local col = (i - 1) % cols
		local inRow = math.min(cols, count - row * cols)
		local rowW = inRow * w + (inRow - 1) * gap
		local x0 = math.floor((width - rowW) / 2)
		xs[i] = x0 + col * (w + gap)
		ys[i] = y0 + row * (h + gap)
	end
	return {
		cols = cols,
		rows = rows,
		w = w,
		h = h,
		height = y0 + total,
		x = xs,
		y = ys,
	}
end

--------------------------------------------------------------------------------------------
-- Gamepad
--------------------------------------------------------------------------------------------

--- Whether a gamepad was the last input.
function ShopParts.gamepad(): boolean
	return string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
end

--- The first of these that a gamepad may select now (visible, selectable, shown on screen).
function ShopParts.firstSelectable(list: { GuiObject? }): GuiObject?
	for _, object in list do
		if object and object.Selectable and object.Visible and object.Parent then
			local shown = true
			local node: Instance? = object.Parent
			while node and node:IsA("GuiObject") do
				if not node.Visible then
					shown = false
					break
				end
				node = node.Parent
			end
			if shown then
				return object
			end
		end
	end
	return nil
end

--- MenuFrame's scale divider, re-exported so pages need one module for layout.
ShopParts.scaleOf = MenuFrame.scaleOf

return ShopParts
