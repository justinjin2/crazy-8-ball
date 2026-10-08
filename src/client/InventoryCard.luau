--!strict
-- InventoryCard: a cue's card (docs/prompts/CUES_LIVELY_PROMPT.md, concept 1 approved round 4,
-- 2026-10-08; Config.UI.CueCard), for the Cues grid and the Index's cells now and the lucky
-- block spin and YOU GOT next, plus the plain pale-edged box the Inventory's panels and rows
-- sit in.
--
-- The cue's picture fills the top of the card and its name sits under it (one line that
-- shrinks to Layout.MinTextPx, then wraps). The rarity bar along the bottom is in the rarity's
-- colour with its word inside, upper case; a rank cue's bar says RANKED with its tier's badge
-- whole over the bar's left end, and the card wears its tier's colours. Top left: the chance
-- chip (only on cues that drop from a block), then NEW and Equipped under it; top right the
-- count ("x3") and the padlock on Exclusive and Unique cues; a copy number ("#412") is a dark
-- chip with gold words just above the name, on the right (concept 2). A bare card (the big
-- card, whose words beside it say all that) shows no pills and no padlock. The card is filled in its
-- look's colours, rimmed by the rarity edge, with faint 8-balls drifting up-left behind the
-- cue; the rarer the cue, the more moves (CueCardFx). A never-found cue in the Index wears the
-- grey Silhouette look: its dark picture only.
--
-- It behaves like the kit's buttons: hover and gamepad selection give a gold ring and a small
-- grow, a press squishes it and plays the Click sound. `onSelect` runs when a gamepad lands on
-- it. The card whose details show (setChosen) keeps a blue ring (the house accent for whatever
-- is chosen, UI_STYLE section 4).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CardMath = require(Shared:WaitForChild("CardMath"))
local CueCardFx = require(script.Parent.CueCardFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local IC = Config.UI.Inventory.Card
local CC = Config.UI.CueCard
local L = CC.Layout
local UNITS = CC.Units
local CARD = Config.UI.Menu.Card
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local QUICK = Config.Multiplayer.Style.QuickMotion
local BADGES: { [string]: string } = Config.UI.Ranks.Badges :: any
local color = HudParts.color
local tone = HudParts.tone
local WHITE = tone("White")
local EDGE = color(CARD.EdgeColor)

export type Fields = {
	cueId: string,
	silhouette: boolean?, -- the Index: never found (the grey card, the dark picture, nothing else)
	count: string?, -- "x3", or nil / "" for none
	copy: string?, -- a copy number over the name: "#412", or nil / "" for none
	bare: boolean?, -- no pills and no padlock (the big card); the copy number stays
	new: boolean?, -- the gold NEW pill
	equipped: boolean?, -- the green Equipped pill
	chance: string?, -- the chance chip top left: "4.2%" (nil for a cue no block drops)
}

export type Options = {
	name: string?, -- the Instance's name
	order: number?, -- LayoutOrder in a grid
	onPress: () -> (),
	onSelect: (() -> ())?, -- a gamepad landed on it
	lines: number?, -- lines a long name may wrap to (2 by default)
}

export type Card = {
	button: TextButton,
	body: Frame,
	press: UIScale,
	face: Frame, -- the card's box (it clips its layers)
	fill: Frame,
	fillRound: UICorner,
	fillGradient: UIGradient,
	centre: ImageLabel, -- a radial look's light middle
	balls: ImageLabel,
	ballsRound: UICorner,
	art: Frame,
	thumb: Frame,
	name: TextLabel,
	bar: Frame,
	barGradient: UIGradient,
	barRing: UIStroke,
	barHighlight: Frame,
	barWord: TextLabel,
	edge: Frame,
	edgeRound: UICorner,
	edgeStroke: UIStroke,
	inner: Frame,
	innerRound: UICorner,
	innerStroke: UIStroke,
	badge: ImageLabel,
	chancePill: Frame,
	chanceText: TextLabel,
	newPill: Frame,
	newText: TextLabel,
	equipPill: Frame,
	equipText: TextLabel,
	countPill: Frame,
	countText: TextLabel,
	copyPill: Frame,
	copyText: TextLabel,
	lock: ImageLabel,
	ring: Frame,
	ringRound: UICorner,
	ringStroke: UIStroke,
	fx: CueCardFx.Fx?,
	held: boolean, -- its motion waits (the open's pop is fading it in: hold)
	laid: Vector2, -- the size it was last laid out at (unscaled, whole pixels)
	lookKey: string, -- the look showing ("" before the first set)
	ranked: boolean, -- it wears a tier (badge, RANKED)
	cueId: string,
	silhouette: boolean,
	lines: number, -- lines the name may wrap to
	lit: boolean, -- hovered or selected by a gamepad
	chosen: boolean, -- its details show
	down: boolean,
	tween: Tween?,
}

local InventoryCard = {}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

--- The plain box the Inventory's panels and rows sit in: a white rounded card with a pale edge
--- and a soft fade (like the roadmap's reward tiles and MenuFrame.tile), no shadow or ink.
function InventoryCard.box(parent: Instance, name: string): Frame
	local box = HudParts.frame(parent, name)
	box.BackgroundTransparency = 0
	box.BackgroundColor3 = WHITE
	HudParts.corner(box, IC.CornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = EDGE
	edge.Thickness = IC.StrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = box
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, color(K.PanelFade))
	fade.Parent = box
	return box
end

--- A small pill with one word (NEW, Equipped, "x3"): `tint` its fill; white words with an ink
--- outline, or ink words (`inkWords`) on a white pill.
function InventoryCard.pill(
	parent: Instance,
	name: string,
	tint: Color3,
	text: string,
	inkWords: boolean?
): (Frame, TextLabel)
	local pill = HudParts.pill(parent, name, tint)
	local words = if inkWords
		then HudParts.note(pill, "Words", IC.PillTextPx, text)
		else HudParts.text(pill, "Words", IC.PillTextPx, text)
	words.TextWrapped = false
	words.Size = UDim2.fromScale(1, 1)
	words.ZIndex = 2
	return pill, words
end

--- A pill's width for its words at `size` (Card.PillTextPx by default) with room each side.
function InventoryCard.pillWidth(text: string, height: number, size: number?): number
	return math.max(height, math.ceil(textWidth(text, size or IC.PillTextPx)) + 2 * IC.PillPadPx)
end

-- The ring round the card: gold while hovered or selected, blue while chosen, else none.
local function paintRing(card: Card)
	card.ringStroke.Enabled = card.lit or card.chosen
	card.ringStroke.Color = if card.lit then tone("Gold") else tone("Blue")
	card.ringStroke.Thickness = L.RingPx
end

local function settle(card: Card)
	if card.tween then
		card.tween:Cancel()
	end
	local scale = if card.down then K.PressedScale elseif card.lit then K.SelectedScale else 1
	local tween = TweenService:Create(
		card.press,
		TweenInfo.new(QUICK, Enum.EasingStyle.Quad),
		{ Scale = scale }
	)
	card.tween = tween
	tween:Play()
end

-- The name's text size and lines: as big as NameUnits allows on one line, shrinking to
-- MinTextPx, then wrapping (up to `maxLines`) at MinTextPx.
local function nameFit(
	text: string,
	maxPx: number,
	boxW: number,
	maxLines: number
): (number, number)
	if text == "" then
		return maxPx, 1
	end
	local width = textWidth(text, maxPx) + 2
	if width <= boxW then
		return maxPx, 1
	end
	local fit = math.floor(maxPx * boxW / width)
	if fit >= L.MinTextPx then
		return fit, 1
	end
	local wrapped =
		TextService:GetTextSize(text, L.MinTextPx, FONT, Vector2.new(math.max(1, boxW - 2), 4000))
	return L.MinTextPx, math.clamp(round(wrapped.Y / L.MinTextPx), 1, maxLines)
end

--- Lay the card's parts out from its size (it does this itself when its size changes). All in
--- card units, scaled by k = its width / Units[1].
function InventoryCard.layout(card: Card)
	local size = card.button.AbsoluteSize / MenuFrame.scaleOf(card.button)
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return
	end
	card.laid = Vector2.new(round(w), round(h))
	local k = w / UNITS[1]
	local function px(units: number): number
		return round(units * k)
	end

	-- The box, its edge (drawn outward from a frame inset by its thickness, so it lies inside
	-- the box), the white line inside the edge, and the hover ring outside.
	local cornerPx = px(L.CornerUnits)
	local edgePx = math.max(1, px(L.EdgeUnits))
	local innerPx = math.max(1, px(L.InnerUnits))
	card.fillRound.CornerRadius = UDim.new(0, cornerPx)
	card.ballsRound.CornerRadius = UDim.new(0, cornerPx)
	card.ringRound.CornerRadius = UDim.new(0, cornerPx)
	card.edge.Position = UDim2.fromOffset(edgePx, edgePx)
	card.edge.Size = UDim2.new(1, -2 * edgePx, 1, -2 * edgePx)
	card.edgeRound.CornerRadius = UDim.new(0, math.max(0, cornerPx - edgePx))
	card.edgeStroke.Thickness = edgePx
	local innerAt = edgePx + innerPx
	card.inner.Position = UDim2.fromOffset(innerAt, innerAt)
	card.inner.Size = UDim2.new(1, -2 * innerAt, 1, -2 * innerAt)
	card.innerRound.CornerRadius = UDim.new(0, math.max(0, cornerPx - innerAt))
	card.innerStroke.Thickness = innerPx
	local centre = CC.Motion.Centre
	card.centre.Position = UDim2.fromScale(centre.At[1], centre.At[2])
	card.centre.Size = UDim2.fromOffset(px(centre.Units[1]), px(centre.Units[2]))
	local sx, sy, offset = CardMath.ballsWindow(0, w, h, 0)
	card.balls.ImageRectSize = Vector2.new(sx, sy)
	card.balls.ImageRectOffset = Vector2.new(offset, offset)

	-- The rarity bar along the bottom, its word (right of the badge on a Ranked card).
	local B = L.BarUnits
	local barH = math.max(1, px(B[2]))
	local barTop = h - px(B[3]) - barH
	card.bar.Position = UDim2.fromOffset(px(B[1]), barTop)
	card.bar.Size = UDim2.fromOffset(math.max(1, w - 2 * px(B[1])), barH)
	card.barRing.Thickness = math.max(1, L.BarRingUnits * k)
	local HL = L.BarHighlight
	card.barHighlight.Position = UDim2.fromScale(HL[1], HL[2])
	card.barHighlight.Size = UDim2.fromScale(1 - 2 * HL[1], HL[3])
	local wordPx = math.max(L.MinTextPx, px(L.BarWordUnits))
	HudParts.setTextSize(card.barWord, wordPx, wordPx)
	local pad = if card.ranked then px(L.BarRankedPadUnits) else 0
	card.barWord.Position = UDim2.fromOffset(pad, 0)
	card.barWord.Size = UDim2.new(1, -pad, 1, 0)
	local G = L.BadgeUnits
	local badgeSide = px(G[3])
	card.badge.Position = UDim2.fromOffset(px(G[1]), h - px(G[2]) - badgeSide)
	card.badge.Size = UDim2.fromOffset(badgeSide, badgeSide)

	-- The name just over the bar; the picture above it (smaller on a short card).
	local sideW = px(L.NameSideUnits)
	local boxW = math.max(1, w - 2 * sideW)
	local maxPx = math.max(L.MinTextPx, px(L.NameUnits))
	local namePx, lines = nameFit(card.name.Text, maxPx, boxW, card.lines)
	local lineH = math.max(1, round(namePx * L.NameLineShare))
	local nameBottom = if card.bar.Visible then barTop - px(L.NameGapUnits) else h - px(B[3])
	card.name.TextWrapped = lines > 1
	card.name.Position = UDim2.fromOffset(sideW, nameBottom - lineH * lines)
	card.name.Size = UDim2.fromOffset(boxW, lineH * lines)
	HudParts.setTextSize(card.name, namePx, namePx)
	local A = L.ArtUnits
	local artTop = px(A[2])
	local art =
		math.max(1, math.min(px(A[3]), w - 2 * px(A[1]), barTop - px(L.ArtBarGapUnits) - artTop))
	card.art.Position = UDim2.fromOffset(round((w - art) / 2), artTop)
	card.art.Size = UDim2.fromOffset(art, art)

	-- The pills: down the left the chance chip, NEW and Equipped; the lock and the count top right.
	local P = L.PillUnits
	local pillPx = math.max(L.PillMinTextPx, px(L.PillTextUnits))
	local chancePx = math.max(L.PillMinTextPx, px(L.ChanceTextUnits))
	local pillH = math.max(px(P[3]), pillPx + 4)
	local padX = px(L.PillPadUnits)
	local left, top = px(P[1]), px(P[2])
	local stepY = px(L.SecondPillTopUnits - P[2])
	local row = 0
	for _, entry in
		{
			{ card.chancePill, card.chanceText, chancePx },
			{ card.newPill, card.newText, pillPx },
			{ card.equipPill, card.equipText, pillPx },
		} :: { { any } }
	do
		local pill: Frame, words: TextLabel, textPx: number = entry[1], entry[2], entry[3]
		if pill.Visible then
			local pw = math.min(w - 2 * left, math.ceil(textWidth(words.Text, textPx)) + 2 * padX)
			pill.Position = UDim2.fromOffset(left, top + row * stepY)
			pill.Size = UDim2.fromOffset(pw, pillH)
			HudParts.setTextSize(words, textPx, textPx)
			row += 1
		end
	end
	local right = w - px(P[1])
	if card.lock.Visible then
		local LK = L.LockUnits
		local side = px(LK[3])
		card.lock.Position = UDim2.fromOffset(w - px(LK[1]) - side, px(LK[2]))
		card.lock.Size = UDim2.fromOffset(side, side)
		right = w - px(LK[1]) - side - px(L.LockGapUnits)
	end
	if card.countPill.Visible then
		local cw = math.ceil(textWidth(card.countText.Text, pillPx)) + 2 * padX
		card.countPill.Position = UDim2.fromOffset(right - cw, top)
		card.countPill.Size = UDim2.fromOffset(cw, pillH)
		HudParts.setTextSize(card.countText, pillPx, pillPx)
	end
	-- The copy number just above the name, on the right.
	if card.copyPill.Visible then
		local CU = L.CopyUnits
		local copyH = math.max(px(CU[2]), pillPx + 2)
		local cw = math.ceil(textWidth(card.copyText.Text, pillPx)) + 2 * padX
		local nameTop = card.name.Position.Y.Offset
		card.copyPill.Position = UDim2.fromOffset(w - px(CU[1]) - cw, nameTop - px(CU[3]) - copyH)
		card.copyPill.Size = UDim2.fromOffset(cw, copyH)
		HudParts.setTextSize(card.copyText, pillPx, pillPx)
	end

	if card.fx then
		CueCardFx.layout(card.fx, k, cornerPx)
	end
end

-- A frame filling its parent, rounded (its radius set by layout).
local function layer(parent: Instance, name: string, z: number): (Frame, UICorner)
	local frame = HudParts.frame(parent, name)
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = z
	local roundCorner = Instance.new("UICorner")
	roundCorner.Parent = frame
	return frame, roundCorner
end

local function pillShape(pill: Frame)
	local roundCorner = pill:FindFirstChildOfClass("UICorner")
	if roundCorner then
		roundCorner.CornerRadius = UDim.new(0.5, 0)
	end
end

--- A card (empty until set). Size it yourself or put it in a grid.
function InventoryCard.new(parent: Instance, opts: Options): Card
	local button = Instance.new("TextButton")
	button.Name = opts.name or "Card"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.LayoutOrder = opts.order or 0
	button.Selectable = true
	local noBox = Instance.new("Frame") -- the gold ring shows selection, not Roblox's box
	noBox.BackgroundTransparency = 1
	button.SelectionImageObject = noBox
	local body = HudParts.frame(button, "Body")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = body

	-- The face: the card's box, clipping its layers. Bottom to top: the fill (1), a radial
	-- look's light middle (2), the 8-balls (3), the moving layers (CueCardFx: 4 to 7), the
	-- picture (8), embers, sparkles and the shine (9 to 11), the name (12), the bar (13).
	local face = HudParts.frame(body, "Face")
	face.Size = UDim2.fromScale(1, 1)
	face.ClipsDescendants = true
	face.ZIndex = 2
	local fill, fillRound = layer(face, "Fill", 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = WHITE
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90
	fillGradient.Parent = fill
	local centre = Instance.new("ImageLabel")
	centre.Name = "Centre"
	centre.BackgroundTransparency = 1
	centre.Image = K.Art.SoftGlow
	centre.AnchorPoint = Vector2.new(0.5, 0.5)
	centre.ZIndex = 2
	centre.Visible = false
	centre.Parent = face
	local balls = Instance.new("ImageLabel")
	balls.Name = "Balls"
	balls.BackgroundTransparency = 1
	balls.Image = CC.Images.Balls
	balls.Size = UDim2.fromScale(1, 1)
	balls.ZIndex = 3
	local ballsRound = Instance.new("UICorner")
	ballsRound.Parent = balls
	balls.Parent = face
	local art = HudParts.frame(face, "Art")
	art.ZIndex = 8
	local thumb = CueThumb.new(art, Catalog.Default)
	thumb.ZIndex = 1
	local name = HudParts.text(face, "Name", L.MinTextPx, "")
	name.TextWrapped = false
	name.ZIndex = 12
	local bar = HudParts.frame(face, "Bar")
	bar.BackgroundTransparency = 0
	bar.BackgroundColor3 = WHITE
	bar.ZIndex = 13
	local barRound = Instance.new("UICorner")
	barRound.CornerRadius = UDim.new(0.5, 0)
	barRound.Parent = bar
	local barGradient = Instance.new("UIGradient")
	barGradient.Rotation = 90
	barGradient.Parent = bar
	local barRing = Instance.new("UIStroke")
	barRing.Name = "Ring"
	barRing.Color = tone("Ink")
	barRing.Transparency = L.BarRingTransparency
	barRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barRing.Parent = bar
	local barHighlight = HudParts.frame(bar, "Highlight")
	barHighlight.BackgroundTransparency = L.BarHighlight[4]
	barHighlight.BackgroundColor3 = WHITE
	barHighlight.ZIndex = 2
	local highlightRound = Instance.new("UICorner")
	highlightRound.CornerRadius = UDim.new(0.5, 0)
	highlightRound.Parent = barHighlight
	local barWord = HudParts.text(bar, "Word", L.MinTextPx, "")
	barWord.TextWrapped = false
	barWord.ZIndex = 3

	-- Over the face: the edge and its inner line (3), the tier badge (4), the pills and the
	-- padlock (5), the hover ring (6).
	local edge, edgeRound = layer(body, "Edge", 3)
	local edgeStroke = Instance.new("UIStroke")
	edgeStroke.Name = "Stroke"
	edgeStroke.LineJoinMode = Enum.LineJoinMode.Round
	edgeStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edgeStroke.Parent = edge
	local inner, innerRound = layer(body, "Inner", 3)
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Name = "Stroke"
	innerStroke.Color = WHITE
	innerStroke.Transparency = L.InnerTransparency
	innerStroke.LineJoinMode = Enum.LineJoinMode.Round
	innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	innerStroke.Parent = inner
	local badge = Instance.new("ImageLabel")
	badge.Name = "Badge"
	badge.BackgroundTransparency = 1
	badge.ScaleType = Enum.ScaleType.Fit
	badge.ZIndex = 4
	badge.Visible = false
	badge.Parent = body
	local chancePill = HudParts.frame(body, "Chance")
	chancePill.BackgroundTransparency = L.ChanceTransparency
	chancePill.BackgroundColor3 = hex(L.ChanceColor)
	chancePill.ZIndex = 5
	chancePill.Visible = false
	local chanceRound = Instance.new("UICorner")
	chanceRound.CornerRadius = UDim.new(0.5, 0)
	chanceRound.Parent = chancePill
	local chanceText = HudParts.text(chancePill, "Words", L.PillMinTextPx, "")
	local chanceOutline = chanceText:FindFirstChild("Outline")
	if chanceOutline then
		chanceOutline:Destroy() -- coloured words on the dark chip, no outline (the concept's)
	end
	chanceText.AutoLocalize = false -- a number
	chanceText.TextWrapped = false
	chanceText.Size = UDim2.fromScale(1, 1)
	chanceText.ZIndex = 2
	local newPill, newText = InventoryCard.pill(body, "New", tone("Gold"), WORDS.New)
	pillShape(newPill)
	newPill.ZIndex = 5
	newPill.Visible = false
	local equipPill, equipText = InventoryCard.pill(body, "Equipped", tone("Green"), WORDS.Equipped)
	pillShape(equipPill)
	equipPill.ZIndex = 5
	equipPill.Visible = false
	local countPill, countText = InventoryCard.pill(body, "Count", WHITE, "", true)
	pillShape(countPill)
	countText.AutoLocalize = false -- a number
	countPill.ZIndex = 5
	countPill.Visible = false
	local copyPill = HudParts.frame(body, "Copy")
	copyPill.BackgroundTransparency = L.CopyTransparency
	copyPill.BackgroundColor3 = hex(L.CopyColor)
	copyPill.ZIndex = 5
	copyPill.Visible = false
	local copyRound = Instance.new("UICorner")
	copyRound.CornerRadius = UDim.new(0.5, 0)
	copyRound.Parent = copyPill
	local copyText = HudParts.text(copyPill, "Words", L.PillMinTextPx, "", hex(L.CopyTextColor))
	local copyOutline = copyText:FindFirstChild("Outline")
	if copyOutline then
		copyOutline:Destroy() -- gold words on the dark chip, no outline (as the chance chip)
	end
	copyText.AutoLocalize = false -- a number
	copyText.TextWrapped = false
	copyText.Size = UDim2.fromScale(1, 1)
	copyText.ZIndex = 2
	local lock = HudParts.icon(body, "Lock", "Lock")
	lock.ZIndex = 5
	lock.Visible = false
	local ring, ringRound = layer(body, "Ring", 6)
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Name = "Stroke"
	ringStroke.LineJoinMode = Enum.LineJoinMode.Round
	ringStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ringStroke.Enabled = false
	ringStroke.Parent = ring
	button.Parent = parent

	local card: Card = {
		button = button,
		body = body,
		press = press,
		face = face,
		fill = fill,
		fillRound = fillRound,
		fillGradient = fillGradient,
		centre = centre,
		balls = balls,
		ballsRound = ballsRound,
		art = art,
		thumb = thumb,
		name = name,
		bar = bar,
		barGradient = barGradient,
		barRing = barRing,
		barHighlight = barHighlight,
		barWord = barWord,
		edge = edge,
		edgeRound = edgeRound,
		edgeStroke = edgeStroke,
		inner = inner,
		innerRound = innerRound,
		innerStroke = innerStroke,
		badge = badge,
		chancePill = chancePill,
		chanceText = chanceText,
		newPill = newPill,
		newText = newText,
		equipPill = equipPill,
		equipText = equipText,
		countPill = countPill,
		countText = countText,
		copyPill = copyPill,
		copyText = copyText,
		lock = lock,
		ring = ring,
		ringRound = ringRound,
		ringStroke = ringStroke,
		fx = nil,
		lookKey = "",
		ranked = false,
		cueId = "",
		silhouette = false,
		held = false,
		laid = Vector2.zero,
		lines = opts.lines or 2,
		lit = false,
		chosen = false,
		down = false,
		tween = nil,
	}
	-- A new size lays it out again; a UIScale growing or shrinking it (a pop, a hover, the
	-- menu's contents showing again) leaves the layout as it is.
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local size = button.AbsoluteSize / MenuFrame.scaleOf(button)
		if size.X > 0 and Vector2.new(round(size.X), round(size.Y)) == card.laid then
			return
		end
		InventoryCard.layout(card)
	end)

	-- Hover, gamepad selection and press, like the kit's candy buttons.
	local function light(on: boolean)
		card.lit = on
		paintRing(card)
		settle(card)
		UIAnim.sway(body, on, nil, button)
	end
	button.MouseEnter:Connect(function()
		light(true)
	end)
	button.MouseLeave:Connect(function()
		card.down = false
		light(false)
	end)
	button.SelectionGained:Connect(function()
		light(true)
		if opts.onSelect then
			opts.onSelect()
		end
	end)
	button.SelectionLost:Connect(function()
		light(false)
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			card.down = true
			settle(card)
		end
	end)
	button.InputEnded:Connect(function()
		card.down = false
		settle(card)
	end)
	button.Activated:Connect(function()
		UISound.play("Click")
		opts.onPress()
	end)
	InventoryCard.layout(card)
	return card
end

-- Dress the card in a look (Config.UI.CueCard.Looks or Tiers): its colours, then its moving
-- parts (rebuilt, since where its sparkles sit comes from the cue's id).
local function dress(card: Card, key: string, ranked: boolean, id: string, silhouette: boolean)
	if card.fx then
		CueCardFx.stop(card.fx)
		card.fx = nil
	end
	local look = CardMath.look(key)
	card.lookKey = key
	card.ranked = ranked
	local keys = {}
	for i, c in look.Fill do
		table.insert(keys, ColorSequenceKeypoint.new(look.FillAt[i], hex(c)))
	end
	card.fillGradient.Color = ColorSequence.new(keys)
	card.fillGradient.Rotation = look.FillRotation or 90
	card.centre.Visible = look.Centre ~= nil
	if look.Centre then
		card.centre.ImageColor3 = hex(look.Centre)
	end
	local B = CC.Motion.Balls
	card.balls.ImageColor3 = hex(look.Balls)
	card.balls.ImageTransparency = if look.Dark then B.DarkTransparency else B.Transparency
	card.edgeStroke.Color = hex(look.Edge)
	if look.Flow then
		local flow = {}
		for i, c in look.Flow do
			table.insert(flow, ColorSequenceKeypoint.new((i - 1) / (#look.Flow - 1), hex(c)))
		end
		card.barGradient.Color = ColorSequence.new(flow)
		card.barGradient.Rotation = 0
	else
		card.barGradient.Color = ColorSequence.new(hex(look.Bar[1]), hex(look.Bar[2]))
		card.barGradient.Rotation = 90
	end
	card.chanceText.TextColor3 = hex(look.Chance)
	if ranked then
		local badgeKey = if key == "Reyes" then "reyes" else string.lower(key) .. "_1"
		card.badge.Image = BADGES[badgeKey] or ""
	end
	card.fx = CueCardFx.new({
		body = card.body,
		face = card.face,
		balls = card.balls,
		edgeStroke = card.edgeStroke,
		bar = card.bar,
		barGradient = card.barGradient,
		art = card.art,
		thumb = card.thumb,
		name = card.name,
	}, look, CardMath.seed(id), silhouette)
	CueCardFx.hold(card.fx :: CueCardFx.Fx, card.held)
end

--- Show a cue on the card (or its silhouette), with its pills.
function InventoryCard.set(card: Card, fields: Fields)
	local id = fields.cueId
	local silhouette = fields.silhouette == true
	local changed = id ~= card.cueId or silhouette ~= card.silhouette
	if changed then
		-- A never-found cue is its blacked-out silhouette (GUI lane, 2026-10-03).
		CueThumb.set(card.thumb, id, silhouette)
	end
	local row = Catalog.get(id)
	local rarity = if row then row.Rarity else "Default"
	local key, ranked = CardMath.lookKey(rarity, if row then row.Tier else nil, silhouette)
	card.cueId, card.silhouette = id, silhouette
	-- The words first: the moving parts note where the name rests.
	card.name.Text = if silhouette then "" else CueThumb.cueName(id)
	card.name.Visible = not silhouette
	card.bar.Visible = not silhouette
	card.barWord.Text = string.upper(CueThumb.rarityName(if ranked then "Ranked" else rarity))
	if changed or key ~= card.lookKey then
		dress(card, key, ranked, id, silhouette)
	end
	card.badge.Visible = ranked and not silhouette
	local pills = not silhouette and fields.bare ~= true
	local count = if pills then fields.count or "" else ""
	card.countText.Text = count
	card.countPill.Visible = count ~= ""
	local copy = if silhouette then "" else fields.copy or ""
	card.copyText.Text = copy
	card.copyPill.Visible = copy ~= ""
	card.newPill.Visible = fields.new == true and pills
	card.equipPill.Visible = fields.equipped == true and pills
	card.lock.Visible = pills and row ~= nil and (row.Group == "Exclusive" or row.Group == "Unique")
	local chance = if pills then fields.chance or "" else ""
	card.chanceText.Text = chance
	card.chancePill.Visible = chance ~= ""
	InventoryCard.layout(card)
end

--- Mark the card whose details show (a blue ring).
function InventoryCard.setChosen(card: Card, chosen: boolean)
	if card.chosen ~= chosen then
		card.chosen = chosen
		paintRing(card)
	end
end

--- Hold the card's motion still (`on`) while a Stage pop fades it in, or let it go again (its
--- piece's onLand): the motion's glows would show at full strength before the card does.
function InventoryCard.hold(card: Card, on: boolean)
	card.held = on
	if card.fx then
		CueCardFx.hold(card.fx, on)
	end
end

--- Take the card away (its motion stops with it).
function InventoryCard.destroy(card: Card)
	if card.fx then
		CueCardFx.stop(card.fx)
		card.fx = nil
	end
	card.button:Destroy()
end

return InventoryCard
