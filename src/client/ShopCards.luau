--!strict
-- ShopCards: the parts the Shop's Blocks group shares (ShopMystery, ShopRestock, ShopOffers;
-- the designer's picks on the mock page, 2026-10-08): a section's pale panel and the white boxes
-- in it, the navy title pill on a panel's top edge, a block picture with its rarity's glow,
-- turning rays and twinkles (the picture stays still: "the small decorative part moves, not the
-- hero"), the sky-blue odds badge, and the buy buttons (the purple gift square and the green
-- Robux price, which shines; the gold money price, which never does). Everything is placed in
-- the Grand Opening card's units and scaled by its k (ShopCards.put), so the whole Shop page
-- reads as one. Sizes in Config.UI.ShopBlocks, words in Strings.Menus.Shop.Blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local StageMath = require(Shared:WaitForChild("StageMath"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local Quality = require(script.Parent.Quality)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local K = Config.UI.Kit
local FX = Config.UI.Effects
local MIN_TEXT = Config.UI.GrandOpeningCard.Layout.MinTextPx
local GLOW_IMAGE = Config.UI.GrandOpeningCard.Images.BlockGlow
local SHOP_COPY: { [string]: any } = Strings.Menus.Shop :: any
local FEATURED_COPY: { [string]: any } = SHOP_COPY.Featured

local ShopCards = {}

function ShopCards.rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local rgb = ShopCards.rgb

function ShopCards.round(x: number): number
	return math.floor(x + 0.5)
end
local round = ShopCards.round

--- `units` at the scale `k`, in whole pixels.
function ShopCards.px(units: number, k: number): number
	return round(units * k)
end

--- A text size of `units` at the scale `k`, never under the card's smallest text.
function ShopCards.textPx(units: number, k: number): number
	return math.max(MIN_TEXT, round(units * k))
end

--- Centre `object` at (x, y) units in its parent and size it w x h units, at the scale `k`.
function ShopCards.put(object: GuiObject, k: number, x: number, y: number, w: number, h: number)
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromOffset(round(x * k), round(y * k))
	object.Size = UDim2.fromOffset(round(w * k), round(h * k))
end

--- Centre `object` at (x, y) pixels in its parent and size it w x h pixels.
function ShopCards.putPx(object: GuiObject, x: number, y: number, w: number, h: number)
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromOffset(round(x), round(y))
	object.Size = UDim2.fromOffset(round(w), round(h))
end

--- Place a line of words `w` units wide centred on (x, y) units at the scale `k`, its box as
--- tall as its words (`textPx`) and their ink outline, and set their size.
function ShopCards.line(
	label: TextLabel,
	k: number,
	x: number,
	y: number,
	w: number,
	textPx: number
)
	ShopCards.putPx(label, x * k, y * k, w * k, textPx + B.TextBoxPx)
	HudParts.setTextSize(label, textPx)
end

--- Where something `hUnits` tall holding words `textPx` tall (with `pad` pixels round them)
--- goes so it sits at `y` units yet ends above `limitPx`: its centre and height in pixels. On
--- a small screen the words keep the smallest text size while the units shrink, so it grows
--- to hold them and moves up clear of what is under it.
function ShopCards.above(
	y: number,
	hUnits: number,
	textPx: number,
	pad: number,
	limitPx: number,
	k: number
): (number, number)
	local h = math.max(round(hUnits * k), textPx + 2 * pad)
	return math.min(round(y * k), math.floor(limitPx - B.TextGapPx - h / 2)), h
end

--- A buy button's height in pixels: `hUnits` at the scale `k`, never under MinButtonPx.
function ShopCards.buttonPx(hUnits: number, k: number): number
	return math.max(B.MinButtonPx, round(hUnits * k))
end

--- A small pill's ink edge at the scale `k`.
function ShopCards.strokePx(k: number): number
	return math.max(B.MinStrokePx, B.StrokeUnits * k)
end

--- How wide `text` is at `px`, with a little room.
function ShopCards.measure(text: string, px: number): number
	return math.ceil(ShopParts.textWidth(text, px)) + 4
end

--- A rarity's colour (a Mystery tier's too: Standard is Common's grey). Secret's near-black does
--- not read on white: its red glow does.
function ShopCards.rarityColor(rarity: string): Color3
	if rarity == "Secret" then
		return rgb(K.SecretGlow)
	elseif rarity == "Standard" then
		return rgb(K.Rarity.Common)
	end
	return rgb((K.Rarity :: any)[rarity] or K.Rarity.Default)
end

--- "6d 23h", "23h 59m", "59:59": the time left on a countdown.
function ShopCards.timeLeft(seconds: number): string
	return StageMath.timeLeft(seconds, FEATURED_COPY)
end

--------------------------------------------------------------------------------------------
-- Small builders
--------------------------------------------------------------------------------------------

function ShopCards.image(parent: Instance, name: string, id: string, z: number): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = id
	label.ScaleType = Enum.ScaleType.Fit
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.ZIndex = z
	label.Parent = parent
	return label
end

--- Kit text (white, or `tint`, with the ink outline) on one line, centred on its position.
function ShopCards.label(
	parent: Instance,
	name: string,
	text: string,
	tint: Color3?,
	z: number
): TextLabel
	local made = HudParts.text(parent, name, MIN_TEXT, text, tint)
	made.TextWrapped = false
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.ZIndex = z
	return made
end

--- Small ink words with no outline (a note on a white box), centred on their position.
function ShopCards.note(parent: Instance, name: string, text: string, z: number): TextLabel
	local made = HudParts.note(parent, name, MIN_TEXT, text)
	made.TextWrapped = false
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.ZIndex = z
	return made
end

--- A rounded pill in `tint` with an ink outline and its words.
function ShopCards.pill(
	parent: Instance,
	name: string,
	text: string,
	tint: Color3,
	z: number
): (Frame, TextLabel)
	local made = HudParts.pill(parent, name, tint)
	made.AnchorPoint = Vector2.new(0.5, 0.5)
	made.ZIndex = z
	local words = ShopCards.label(made, "Words", text, nil, z + 1)
	words.Position = UDim2.fromScale(0.5, 0.5)
	words.Size = UDim2.fromScale(0.9, 0.86)
	return made, words
end

-- A pill's (or box's) border stroke, to thicken with the layout.
local function strokeOf(object: Instance): UIStroke?
	for _, child in object:GetChildren() do
		if child:IsA("UIStroke") then
			return child
		end
	end
	return nil
end
ShopCards.strokeOf = strokeOf

export type Box = { frame: Frame, corner: UICorner, edge: UIStroke }

--- A rounded box: `fill` with an `edge` line round it.
function ShopCards.box(parent: Instance, name: string, fill: Color3, edge: Color3, z: number): Box
	local frame = HudParts.frame(parent, name)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = fill
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = z
	local corner = HudParts.corner(frame, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.Color = edge
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return { frame = frame, corner = corner, edge = stroke }
end

--- Round a box's corners and thicken its edge for the scale `k`.
function ShopCards.sizeBox(box: Box, k: number, cornerUnits: number, edgeUnits: number)
	box.corner.CornerRadius = UDim.new(0, round(cornerUnits * k))
	box.edge.Thickness = math.max(B.MinEdgePx, edgeUnits * k)
end

--- A section's pale panel (Config.UI.ShopBlocks.Panel).
function ShopCards.panel(parent: Instance, name: string): Box
	local P = B.Panel
	return ShopCards.box(parent, name, rgb(P.Color), rgb(P.Edge), 2)
end

--- A white box inside a panel.
function ShopCards.inner(parent: Instance, name: string, z: number): Box
	local P = B.Panel
	return ShopCards.box(parent, name, rgb(P.Inner), rgb(P.InnerEdge), z)
end

--------------------------------------------------------------------------------------------
-- The title pill
--------------------------------------------------------------------------------------------

export type TitlePill = {
	pill: Frame,
	word: TextLabel,
	icon: ImageLabel?,
	time: TextLabel?,
	sample: string, -- the widest time it shows, so it never jumps as it counts
	k: number,
}

--- The navy pill on a panel's top edge: its gold word, and with `timer` a stopwatch and a time.
function ShopCards.titlePill(
	parent: Instance,
	name: string,
	text: string,
	timer: boolean?
): TitlePill
	local T = B.TitlePill
	local pill = HudParts.frame(parent, name)
	pill.BackgroundTransparency = 0
	pill.BackgroundColor3 = rgb(T.Color)
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.ZIndex = 6
	HudParts.corner(pill, 99)
	local rim = Instance.new("UIStroke")
	rim.Name = "Rim"
	rim.Color = rgb(T.Rim)
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Parent = pill
	local word = ShopCards.label(pill, "Word", text, rgb(T.TextColor), 7)
	local t: TitlePill =
		{ pill = pill, word = word, icon = nil, time = nil, sample = T.TimeSample, k = 1 }
	if timer then
		local icon = HudParts.icon(pill, "Stopwatch", "Stopwatch")
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.ZIndex = 7
		t.icon = icon
		t.time = ShopCards.label(pill, "Time", "", rgb(T.TimeColor), 7)
	end
	return t
end

--- Show or hide the title pill's stopwatch and time (the pill lays out again to fit).
function ShopCards.showTitleTime(t: TitlePill, on: boolean, x: number, y: number)
	if t.icon and t.time and t.time.Visible ~= on then
		t.icon.Visible = on
		t.time.Visible = on
		ShopCards.layoutTitlePill(t, t.k, x, y)
	end
end

--- Lay the title pill out centred on (x, y) units at the scale `k`, as wide as its words (and
--- its time, while that shows).
function ShopCards.layoutTitlePill(t: TitlePill, k: number, x: number, y: number)
	local T = B.TitlePill
	t.k = k
	local px = ShopCards.textPx(T.TextUnits, k)
	local h = round(T.HeightUnits * k)
	local pad, gap = round(T.PadUnits * k), round(T.GapUnits * k)
	local wordW = ShopCards.measure(t.word.Text, px)
	local width = pad * 2 + wordW
	local iconPx = round(T.IconUnits * k)
	local timeW = 0
	local timed = t.icon ~= nil and t.time ~= nil and t.time.Visible
	if timed then
		-- Room for the widest time it shows ("59:59", "20d 23h"): it never jumps as it counts.
		timeW = ShopCards.measure(t.sample, px)
		width += gap + iconPx + math.floor(gap / 2) + timeW
	end
	t.pill.Position = UDim2.fromOffset(round(x * k), round(y * k))
	t.pill.Size = UDim2.fromOffset(width, h)
	local rim = t.pill:FindFirstChild("Rim") :: UIStroke?
	if rim then
		rim.Thickness = math.max(B.MinStrokePx, T.RimUnits * k)
	end
	t.word.Position = UDim2.fromOffset(pad + round(wordW / 2), round(h / 2))
	t.word.Size = UDim2.fromOffset(wordW, px + B.TextBoxPx)
	HudParts.setTextSize(t.word, px)
	if timed and t.icon and t.time then
		local at = pad + wordW + gap
		t.icon.Position = UDim2.fromOffset(at + round(iconPx / 2), round(h / 2))
		t.icon.Size = UDim2.fromOffset(iconPx, iconPx)
		at += iconPx + math.floor(gap / 2)
		t.time.Position = UDim2.fromOffset(at + round(timeW / 2), round(h / 2))
		t.time.Size = UDim2.fromOffset(timeW, px + B.TextBoxPx)
		HudParts.setTextSize(t.time, px)
	end
end

--------------------------------------------------------------------------------------------
-- A block's picture
--------------------------------------------------------------------------------------------

export type Art = {
	holder: Frame,
	glow: ImageLabel,
	rays: ImageLabel,
	picture: ImageLabel,
	twinkles: { ImageLabel },
}

--- A block picture with its glow and rays behind (tinted `tint`) and twinkles round it.
function ShopCards.art(parent: Instance, name: string, image: string, tint: Color3, z: number): Art
	local A = B.Art
	local holder = HudParts.frame(parent, name)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.ZIndex = z
	local glow = ShopCards.image(holder, "Glow", GLOW_IMAGE, z)
	glow.ImageColor3 = tint
	glow.ImageTransparency = A.GlowTransparency[1]
	glow.Position = UDim2.fromScale(0.5, 0.5)
	local rays = ShopCards.image(holder, "Rays", FX.Rays, z)
	rays.ImageColor3 = tint
	rays.ImageTransparency = A.RaysTransparency
	rays.Position = UDim2.fromScale(0.5, 0.5)
	local picture = ShopCards.image(holder, "Picture", image, z + 1)
	picture.Position = UDim2.fromScale(0.5, 0.5)
	picture.Size = UDim2.fromScale(1, 1)
	local twinkles: { ImageLabel } = {}
	for i = 1, A.Twinkles do
		local twinkle = ShopCards.image(holder, "Twinkle" .. i, FX.Sparkle.Image, z + 2)
		twinkle.ImageColor3 = rgb(A.TwinkleTint)
		twinkle.Visible = false
		table.insert(twinkles, twinkle)
	end
	return { holder = holder, glow = glow, rays = rays, picture = picture, twinkles = twinkles }
end

--- Size a picture `size` units square at (x, y) units, its glow `glow` and rays `rays` wide.
function ShopCards.layoutArt(
	a: Art,
	k: number,
	x: number,
	y: number,
	size: number,
	glow: number,
	rays: number
)
	ShopCards.put(a.holder, k, x, y, size, size)
	a.glow.Size = UDim2.fromOffset(round(glow * k), round(glow * k))
	a.rays.Size = UDim2.fromOffset(round(rays * k), round(rays * k))
	local px = round(size * B.Art.TwinkleShare * k)
	local spots = B.Art.TwinkleAt
	for i, twinkle in a.twinkles do
		local at = spots[(i - 1) % #spots + 1]
		twinkle.Position = UDim2.fromScale(0.5 + at[1], 0.5 + at[2])
		twinkle.Size = UDim2.fromOffset(px, px)
	end
end

--- Change a picture and its tint (a restock slot's block changes every restock).
function ShopCards.setArt(a: Art, image: string, tint: Color3)
	if a.picture.Image ~= image then
		a.picture.Image = image
	end
	a.glow.ImageColor3 = tint
	a.rays.ImageColor3 = tint
end

--- Many idle loops as one handle.
function ShopCards.all(list: { UIAnim.Handle }): UIAnim.Handle
	return {
		stop = function()
			for _, h in list do
				h.stop()
			end
		end,
	}
end

--- The picture's idle loops: the glow breathes, the rays turn, the twinkles pop now and then
--- (fewer with Lower effects). The picture itself stays still.
function ShopCards.artLoops(a: Art): UIAnim.Handle
	local A = B.Art
	local list: { UIAnim.Handle } = {
		UIAnim.glowPulse(a.glow, A.GlowTransparency[1], A.GlowTransparency[2], A.GlowSeconds),
		UIAnim.turn(a.rays, A.RaysTurnPerSecond),
	}
	for i, twinkle in a.twinkles do
		if not Quality.isLow() or i == 1 then
			table.insert(
				list,
				UIAnim.burstLoop(
					twinkle,
					FX.Sparkle,
					A.TwinkleEvery + (i - 1) * A.TwinkleStaggerSeconds
				)
			)
		end
	end
	return ShopCards.all(list)
end

--------------------------------------------------------------------------------------------
-- Tilted tags ("13 for 10!", "+30%", "BEST VALUE")
--------------------------------------------------------------------------------------------

export type Tag = { holder: Frame, pill: Frame, words: TextLabel }

--- A tilted pill on a card's corner (Config.UI.ShopBlocks.CornerTagDegrees): the holder keeps
--- the tilt, so the pill inside may shake (UIAnim.shake owns its Rotation).
function ShopCards.tag(parent: Instance, name: string, text: string, tint: Color3, z: number): Tag
	local holder = HudParts.frame(parent, name)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Rotation = B.CornerTagDegrees
	holder.ZIndex = z
	local pill, words = ShopCards.pill(holder, "Pill", text, tint, z)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(1, 1)
	return { holder = holder, pill = pill, words = words }
end

--- Place a tag w x h units centred on (x, y) units, its words `textUnits` tall.
function ShopCards.layoutTag(
	tag: Tag,
	k: number,
	x: number,
	y: number,
	w: number,
	h: number,
	textUnits: number
)
	local px = ShopCards.textPx(textUnits, k)
	-- On a small screen the words keep the smallest text size: the tag grows round them.
	local width = math.max(round(w * k), ShopCards.measure(tag.words.Text, px) + 4 * B.PillPadPx)
	local height = math.max(round(h * k), px + 2 * B.PillPadPx)
	ShopCards.putPx(tag.holder, x * k, y * k, width, height)
	HudParts.setTextSize(tag.words, px)
	local stroke = strokeOf(tag.pill)
	if stroke then
		stroke.Thickness = ShopCards.strokePx(k)
	end
end

--------------------------------------------------------------------------------------------
-- Gradient cards and their rows (the Starter Pack, VIP, the best-value money pack)
--------------------------------------------------------------------------------------------

-- A card's colours (Config.UI.ShopBlocks.Offers.Starter / .Vip, Config.UI.ShopMoney.Hero...).
export type Look = {
	Top: { number },
	Bottom: { number },
	Edge: { number },
	Row: { number },
	RowTransparency: number,
}

--- A card in `look`'s colours, top to bottom, with its edge.
function ShopCards.gradientCard(parent: Instance, name: string, look: Look, z: number): Box
	local frame = HudParts.frame(parent, name)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = z
	local corner = HudParts.corner(frame, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(rgb(look.Top), rgb(look.Bottom))
	gradient.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = rgb(look.Edge)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = frame
	return { frame = frame, corner = corner, edge = edge }
end

export type Row = { strip: Frame, corner: UICorner, icon: ImageLabel, words: TextLabel }

--- One line on a gradient card: a see-through white strip with its icon and words.
function ShopCards.row(parent: Instance, name: string, image: string, look: Look, z: number): Row
	local strip = HudParts.frame(parent, name)
	strip.BackgroundTransparency = look.RowTransparency
	strip.BackgroundColor3 = rgb(look.Row)
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.ZIndex = z
	local corner = HudParts.corner(strip, 0)
	local icon = ShopCards.image(strip, "Icon", image, z + 1)
	local words = ShopCards.label(strip, "Words", "", nil, z + 1)
	words.AnchorPoint = Vector2.new(0, 0.5)
	words.TextXAlignment = Enum.TextXAlignment.Left
	return { strip = strip, corner = corner, icon = icon, words = words }
end

-- A row's sizes (Config.UI.ShopBlocks.Offers has them all).
export type RowSizes = {
	RowIconUnits: number,
	RowIconLeftUnits: number,
	RowWordsGapUnits: number,
	RowWordsRightUnits: number,
	RowTextUnits: number,
	RowCornerUnits: number,
}

--- Place a row w x h units centred on (x, y) units, sized by `R`.
function ShopCards.layoutRow(
	row: Row,
	k: number,
	x: number,
	y: number,
	w: number,
	h: number,
	R: RowSizes
)
	local iconU = R.RowIconUnits
	local wordsLeft = R.RowIconLeftUnits + iconU + R.RowWordsGapUnits
	local textPx = ShopCards.textPx(R.RowTextUnits, k)
	ShopCards.put(row.strip, k, x, y, w, h)
	row.corner.CornerRadius = UDim.new(0, round(R.RowCornerUnits * k))
	ShopCards.put(row.icon, k, R.RowIconLeftUnits + iconU / 2, h / 2, iconU, iconU)
	row.words.Position = UDim2.fromOffset(round(wordsLeft * k), round(h / 2 * k))
	row.words.Size =
		UDim2.fromOffset(round((w - wordsLeft - R.RowWordsRightUnits) * k), textPx + B.TextBoxPx)
	HudParts.setTextSize(row.words, textPx)
end

--------------------------------------------------------------------------------------------
-- The odds badge
--------------------------------------------------------------------------------------------

export type Badge = { badge: Frame, words: TextLabel, hit: TextButton }

--- The sky-blue "i" (Roblox's rule: the odds one press away). Only it opens the odds, never the
--- picture it sits on; its press area is at least a touch target round the small badge.
function ShopCards.oddsBadge(parent: Instance, name: string, z: number): Badge
	local badge, words =
		ShopCards.pill(parent, name, FEATURED_COPY.OddsBadge, rgb(B.OddsBadgeColor), z)
	local hit = Instance.new("TextButton")
	hit.Name = "OddsHit"
	hit.Text = ""
	hit.BackgroundTransparency = 1
	hit.AutoButtonColor = false
	hit.Selectable = true
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = z + 3
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(Config.UI.Menu.Frame.TouchMinPx, Config.UI.Menu.Frame.TouchMinPx)
	least.Parent = hit
	hit.Parent = badge
	return { badge = badge, words = words, hit = hit }
end

--- Size the badge `size` units round at (x, y) units.
function ShopCards.layoutBadge(b: Badge, k: number, x: number, y: number, size: number)
	local px = math.max(MIN_TEXT + B.BadgePadPx, round(size * k))
	b.badge.AnchorPoint = Vector2.new(0.5, 0.5)
	b.badge.Position = UDim2.fromOffset(round(x * k), round(y * k))
	b.badge.Size = UDim2.fromOffset(px, px)
	HudParts.setTextSize(b.words, math.max(MIN_TEXT, round(px * B.BadgeTextShare)))
end

--------------------------------------------------------------------------------------------
-- Buy buttons
--------------------------------------------------------------------------------------------

--- A Robux price: the glyph and the number, and the old one struck through in red.
function ShopCards.robuxText(robux: number, was: number?): string
	local text = string.format(SHOP_COPY.Robux, Format.commas(robux))
	if was and was > robux then
		text ..= string.format(
			' <font color="#%s"><s>%s</s></font>',
			rgb(K.Numbers.Old):ToHex(),
			Format.commas(was)
		)
	end
	return text
end

--- The green Robux button (its words may hold a struck-through old price).
function ShopCards.robuxButton(parent: Instance, name: string, onPress: () -> ()): TextButton
	local green = HudParts.candy(parent, "", onPress, "Green")
	green.Name = name
	green.AnchorPoint = Vector2.new(0.5, 0.5)
	green.ZIndex = 5
	local parts = HudParts.candyParts(green)
	if parts then
		parts.label.RichText = true
	end
	return green
end

--- The purple gift square at a Robux button's left (a child, so it moves and fades with it).
function ShopCards.giftButton(green: TextButton, onPress: () -> ()): TextButton
	local gift = HudParts.candy(green, "", onPress, "Purple", "Gift")
	gift.Name = "Gift"
	gift.AnchorPoint = Vector2.new(1, 0.5)
	gift.ZIndex = 5
	return gift
end

--- The gold money button with its cash bundle.
function ShopCards.moneyButton(parent: Instance, name: string, onPress: () -> ()): TextButton
	local gold = HudParts.candy(parent, "", onPress, "Yellow", "CashSingle")
	gold.Name = name
	gold.AnchorPoint = Vector2.new(0.5, 0.5)
	gold.ZIndex = 5
	return gold
end

--- Place a Robux button (with its gift square, when it has one) across a row `w` units wide,
--- centred on (x, y) units, `h` units tall.
function ShopCards.layoutRobuxRow(
	green: TextButton,
	gift: TextButton?,
	k: number,
	x: number,
	y: number,
	w: number,
	h: number,
	giftUnits: number,
	gapUnits: number,
	textUnits: number
)
	local rowW, rowH = round(w * k), ShopCards.buttonPx(h, k)
	local giftPx = if gift then math.max(B.MinGiftPx, round(giftUnits * k)) else 0
	local gap = if gift then round(gapUnits * k) else 0
	local greenW = rowW - giftPx - gap
	green.AnchorPoint = Vector2.new(0.5, 0.5)
	green.Position = UDim2.fromOffset(round(x * k) + round((giftPx + gap) / 2), round(y * k))
	green.Size = UDim2.fromOffset(greenW, rowH)
	HudParts.setButtonTextSize(green, ShopCards.textPx(textUnits, k))
	local touch = Config.UI.Menu.Frame.TouchMinPx
	HudParts.setMinHit(green, touch)
	if gift then
		gift.Position = UDim2.new(0, -gap, 0.5, 0)
		gift.Size = UDim2.fromOffset(giftPx, giftPx)
		HudParts.setMinHit(gift, touch)
	end
end

--- Place a money button `w` x `h` units centred on (x, y) units.
function ShopCards.layoutMoney(
	gold: TextButton,
	k: number,
	x: number,
	y: number,
	w: number,
	h: number,
	textUnits: number,
	iconShare: number
)
	gold.AnchorPoint = Vector2.new(0.5, 0.5)
	gold.Position = UDim2.fromOffset(round(x * k), round(y * k))
	gold.Size = UDim2.fromOffset(round(w * k), ShopCards.buttonPx(h, k))
	HudParts.setButtonTextSize(gold, ShopCards.textPx(textUnits, k))
	HudParts.setIconShare(gold, iconShare)
	HudParts.setMinHit(gold, Config.UI.Menu.Frame.TouchMinPx)
end

--- A shine across a button's face every `every` seconds, starting `delay` in (only Robux
--- buttons shine: designer, 2026-10-06), never while it cannot be pressed (owned, sold out).
function ShopCards.buttonShine(button: TextButton, every: number, delay: number): UIAnim.Handle
	local body = button:FindFirstChild("Body")
	local face = body and body:FindFirstChild("Face") :: GuiObject?
	local last = -1
	return UIAnim.loop(button, function(clock)
		if face == nil or UIAnim.reduced() or clock < delay or not button.Active then
			return
		end
		local n = (clock - delay) // (every / math.max(B.ShineMinRate, Quality.rate()))
		if n ~= last then
			last = n
			UIAnim.shine(face)
		end
	end)
end

--- A Robux button's words only when they change (they may hold rich text).
function ShopCards.setButtonWords(button: TextButton, text: string)
	HudParts.setText(button, text)
end

return ShopCards
