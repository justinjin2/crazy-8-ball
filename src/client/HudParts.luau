--!strict
-- HudParts: the UI kit every screen is built from, so they all share one look
-- (docs/UI_STYLE.md, tokens in Config.UI.Kit): white cards with a thick ink outline, a soft
-- shadow and a faint pool-ball pattern; Fredoka One text, white with an ink outline; raised
-- candy buttons in traffic colours that squish when pressed; glossy icons; and the HUD balls.
--
-- Frames and buttons are Roblox shapes (UICorner, UIStroke, UIGradient) so they stay sharp and
-- recolour with one value; images are only icons and effects. The ScreenGui uses Sibling
-- ZIndex, so a card's Shadow (-1) and Fill (0) always draw under whatever is put in it (1+).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UIAnim = require(script.Parent.UIAnim)
local S = Config.Multiplayer.Style
local K = Config.UI.Kit
local HudParts = {}

local FONT: Enum.Font = (Enum.Font :: any)[K.Font]

function HudParts.color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

local color = HudParts.color
local INK = color(K.Colors.Ink)

--- A kit colour by name (Config.UI.Kit.Colors): Ink, White, Soft, Green, Red, Blue, Gold, Grey.
function HudParts.tone(name: string): Color3
	return color(K.Colors[name])
end

function HudParts.frame(parent: Instance, name: string): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundTransparency = 1
	object.Parent = parent
	return object
end

function HudParts.corner(parent: Instance, radius: number): UICorner
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
	return object
end

local function inkStroke(parent: Instance, thickness: number, mode: Enum.ApplyStrokeMode): UIStroke
	local object = Instance.new("UIStroke")
	object.Name = if mode == Enum.ApplyStrokeMode.Border then "Edge" else "Outline"
	object.Color = INK
	object.Thickness = thickness
	object.LineJoinMode = Enum.LineJoinMode.Round
	object.ApplyStrokeMode = mode
	object.Parent = parent
	return object
end

local function outlineFor(size: number): number
	if size < K.TextOutlineThinBelowPx then
		return K.TextOutlineThinPx -- small text: a thin outline keeps the letters' holes open
	end
	return math.max(K.TextOutlineMinPx, math.floor(size * K.TextOutlineRatio + 0.5))
end

--------------------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------------------

--- Fredoka One, white (or `tint`), outlined in ink. It shrinks to fit its box, never below
--- the kit minimum (or `size`, if that is smaller), so longer translations are not cut off.
function HudParts.text(
	parent: Instance,
	name: string,
	size: number,
	text: string,
	tint: Color3?
): TextLabel
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Font = FONT
	object.Text = text
	object.TextColor3 = tint or color(K.Colors.White)
	object.TextScaled = true
	object.TextWrapped = true
	local limit = Instance.new("UITextSizeConstraint")
	limit.Parent = object
	inkStroke(object, 2, Enum.ApplyStrokeMode.Contextual)
	HudParts.setTextSize(object, size)
	object.Parent = parent
	return object
end

--- Small descriptive text (a description, a note, a detail line): dark ink with no outline,
--- sitting cleanly on the white card. An outline on small text squeezes the letters together
--- and fills the o's and a's (designer, 2026-09-26); titles, names and buttons keep theirs.
function HudParts.note(parent: Instance, name: string, size: number, text: string): TextLabel
	local object = HudParts.text(parent, name, size, text, INK)
	local outline = object:FindFirstChild("Outline")
	if outline then
		outline:Destroy()
	end
	return object
end

--- Change a kit text's size: its largest size, its floor and its outline together. `floor`
--- lowers the smallest it may shrink to (player names, which are data, not reading text).
function HudParts.setTextSize(object: TextLabel, size: number, floor: number?)
	local limit = object:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then
		limit.MaxTextSize = math.max(1, math.floor(size))
		limit.MinTextSize = math.max(1, math.floor(math.min(size, floor or K.Text.Min)))
	end
	object.TextSize = size
	local stroke = object:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Thickness = outlineFor(size)
	end
end

-- Each text's test font and how specific its claim is (useFont): a deeper claim wins.
local fontClaims: { [Instance]: { depth: number, face: Font } } = setmetatable({}, { __mode = "k" }) :: any

--- Put every text under `root` in another font, now and as texts are added (a font test
--- over a whole page or one part of it; FontTest). It holds: a screen that sets its own font
--- after building a text gets this one back. `spec`: a font family file and an
--- Enum.FontWeight name. `depth`: how specific the claim is; a text claimed twice keeps the
--- deeper one (a part's font over its screen's), whichever ran first.
function HudParts.useFont(root: Instance, spec: { Family: string, Weight: string }, depth: number?)
	local face = Font.new(spec.Family, (Enum.FontWeight :: any)[spec.Weight])
	local mine = depth or 0
	local function apply(object: Instance)
		if not (object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox")) then
			return
		end
		local text = object :: any
		local claim = fontClaims[object]
		if claim then
			if mine >= claim.depth then
				claim.depth = mine
				claim.face = face
				text.FontFace = face
			end
			return
		end
		local held = { depth = mine, face = face }
		fontClaims[object] = held
		text.FontFace = face
		object:GetPropertyChangedSignal("FontFace"):Connect(function()
			if text.FontFace ~= held.face then
				text.FontFace = held.face
			end
		end)
	end
	for _, object in root:GetDescendants() do
		apply(object)
	end
	root.DescendantAdded:Connect(apply)
end

--- The font to measure `object`'s words with (TextService:GetTextSize takes only an
--- Enum.Font): its own, or the kit's when its font has none (a test font from FontTest, such
--- as Builder Extended). Kit texts shrink to fit, so a wider font still fits its box.
function HudParts.measureFont(object: TextLabel | TextButton): Enum.Font
	local font = object.Font
	if font == Enum.Font.Unknown then
		return (Enum.Font :: any)[K.Font]
	end
	return font
end

--- Fade a kit text with its outline.
function HudParts.setTextTransparency(object: TextLabel, transparency: number)
	object.TextTransparency = transparency
	local stroke = object:FindFirstChild("Outline")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Transparency = transparency
	end
end

--------------------------------------------------------------------------------------------
-- Cards, pills, icons
--------------------------------------------------------------------------------------------

--- A white card: a soft shadow, the white-to-pale-blue fill with its ink outline and the
--- faint pool-ball pattern. Returns the (clear) container; put content straight into it. A
--- card that lays out a list should put the list in a child frame, or the list would take
--- the shadow and fill as items too.
-- The faint 8-ball pattern, tiled over `parent` and clipped to its round corners. It stays
-- still (designer, 2026-10-03: the slow drift looked choppy, as Roblox moves a GUI in whole
-- pixels).
local function pattern(parent: Instance, cornerPx: number)
	local tiles = Instance.new("ImageLabel")
	tiles.Name = "Pattern"
	tiles.BackgroundTransparency = 1
	tiles.Image = K.PatternImage
	tiles.ImageColor3 = color(K.PatternColor)
	tiles.ImageTransparency = K.PatternTransparency
	tiles.ScaleType = Enum.ScaleType.Tile
	tiles.TileSize = UDim2.fromOffset(K.PatternTilePx, K.PatternTilePx)
	tiles.Size = UDim2.fromScale(1, 1)
	tiles.Parent = parent
	HudParts.corner(tiles, cornerPx) -- clips the tiles to the round corners
end

function HudParts.card(parent: Instance, name: string, radius: number?): Frame
	local cornerPx = radius or K.PanelCornerPx
	local root = HudParts.frame(parent, name)
	local shadow = Instance.new("ImageLabel")
	shadow.Name = "Shadow"
	shadow.BackgroundTransparency = 1
	shadow.Image = K.ShadowImage
	shadow.ImageColor3 = INK
	shadow.ImageTransparency = K.ShadowTransparency
	shadow.ScaleType = Enum.ScaleType.Slice
	local s = K.ShadowSlice
	shadow.SliceCenter = Rect.new(s[1], s[2], s[3], s[4])
	local spread = K.ShadowSpreadPx
	shadow.Position = UDim2.fromOffset(-spread, -spread + K.ShadowDropPx)
	shadow.Size = UDim2.new(1, spread * 2, 1, spread * 2)
	shadow.ZIndex = -1
	shadow.Parent = root
	local fill = HudParts.frame(root, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.BackgroundColor3 = color(K.Colors.White)
	fill.ZIndex = 0
	HudParts.corner(fill, cornerPx)
	inkStroke(fill, K.PanelStrokePx, Enum.ApplyStrokeMode.Border)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(color(K.Colors.White), color(K.PanelFade))
	fade.Parent = fill
	pattern(fill, cornerPx)
	return root
end

--- A popup's card (a kit card).
function HudParts.popupCard(parent: Instance, name: string, radius: number?): Frame
	return HudParts.card(parent, name, radius)
end

--- A menu's panel (the roadmap, the host menu, later the shop; UI_STYLE section 2): a kit
--- card whose top is a pale-blue header band for the title and close button, and whose
--- content sits on a near-white sheet with big rounded top corners and a thin light-blue
--- edge, the 8-ball pattern on both. Place the sheet's top from the screen's layout with
--- setSheetTop; content goes straight into the returned card, as with card.
function HudParts.menuCard(parent: Instance, name: string, radius: number?): Frame
	local root = HudParts.card(parent, name, radius)
	local fill = root:FindFirstChild("Fill") :: Frame
	local band = fill:FindFirstChildOfClass("UIGradient") :: UIGradient
	band.Color = ColorSequence.new(color(K.HeaderTop), color(K.HeaderBottom))
	local sheet = HudParts.frame(fill, "Sheet")
	sheet.BackgroundTransparency = 0
	sheet.BackgroundColor3 = Color3.new(1, 1, 1)
	sheet.ZIndex = 2 -- over the band's pattern; still under everything put in the card
	HudParts.corner(sheet, K.SheetCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = color(K.SheetEdge)
	edge.Thickness = K.SheetEdgePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = sheet
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(color(K.SheetTop), color(K.SheetBottom))
	fade.Parent = sheet
	pattern(sheet, K.SheetCornerPx)
	HudParts.setSheetTop(root, 0)
	return root
end

--- Whether the menu `name` (as Menus.register) has the lively frame (Config.UI.Menu.LivelyMenus).
function HudParts.lively(name: string): boolean
	return table.find(Config.UI.Menu.LivelyMenus, name) ~= nil
end

--- Turn a menu card (menuCard) into the lively frame (docs/prompts/SHOP_LIVELY_PROMPT.md
--- section 5): the header band's 8-balls scroll up-left at 45 degrees (a window sliding over a
--- seamless picture, gate 1: smooth however slow) and the white sheet shows the still dots.
--- Returns the header's pattern (Stage fades it in as "Header"); setSheetTop sizes it.
function HudParts.livelyCard(card: Frame): ImageLabel
	local L = Config.UI.Menu.Lively
	local fill = card:FindFirstChild("Fill") :: Frame
	local band = fill:FindFirstChild("Pattern") :: ImageLabel
	band.Image = L.HeaderImage
	band.ImageColor3 = Color3.new(1, 1, 1)
	band.ImageTransparency = L.HeaderTransparency
	band.ScaleType = Enum.ScaleType.Stretch
	band.Size = UDim2.new(1, 0, 0, K.SheetCornerPx)
	UIAnim.scrollTile(
		band,
		L.HeaderPeriod,
		L.HeaderTilePx,
		L.HeaderPxPerSecond,
		Vector2.new(-1, -1),
		L.HeaderSheetPx
	)
	local sheet = fill:FindFirstChild("Sheet") :: Frame
	local dots = sheet:FindFirstChild("Pattern") :: ImageLabel
	dots.Image = L.DotsImage
	dots.ImageColor3 = color(L.DotsColor)
	dots.ImageTransparency = L.DotsTransparency
	dots.TileSize = UDim2.fromOffset(L.DotsTilePx, L.DotsTilePx)
	card:SetAttribute("Lively", true)
	return band
end

--- The lively sheet's still tiny pool-ball dots (Config.UI.Menu.Lively.Dots*) on a card in a
--- lively menu (designer, 2026-10-08: the Cues menu's big card and the Index's panel, "just like
--- shop frame"): a kit card's 8-ball pattern becomes them; a plain frame (InventoryCard.box) gets
--- them as a layer under its contents, its corners rounded by `cornerPx`.
function HudParts.dots(card: Frame, cornerPx: number?)
	local L = Config.UI.Menu.Lively
	local fill = card:FindFirstChild("Fill")
	local tiles = if fill then fill:FindFirstChild("Pattern") else nil
	if not tiles then
		pattern(card, cornerPx or 0)
		tiles = card:FindFirstChild("Pattern")
	end
	local image = tiles :: ImageLabel
	image.Image = L.DotsImage
	image.ImageColor3 = color(L.DotsColor)
	image.ImageTransparency = L.DotsTransparency
	image.TileSize = UDim2.fromOffset(L.DotsTilePx, L.DotsTilePx)
end

--- Whether the menu `name` (as Menus.register) outlines its panel and cards in pale blue.
function HudParts.paleEdged(name: string): boolean
	return table.find(Config.UI.Menu.PaleEdgeMenus, name) ~= nil
end

--- A card's (or menu card's) outline in Kit.PaleEdge instead of ink.
function HudParts.paleEdge(card: Instance)
	local fill = card:FindFirstChild("Fill")
	local edge = fill and fill:FindFirstChild("Edge")
	if edge and edge:IsA("UIStroke") then
		edge.Color = color(K.PaleEdge)
	end
end

--- Every card under `root` still outlined in ink takes Kit.PaleEdge, now and as cards are
--- added (a whole screen of cards, as the Abilities page). Gold or green outlines stay.
function HudParts.paleEdgeAll(root: Instance)
	local pale = color(K.PaleEdge)
	local function consider(object: Instance)
		if
			object.Name == "Edge"
			and object:IsA("UIStroke")
			and object.Parent
			and object.Parent.Name == "Fill"
			and object.Color == INK
		then
			object.Color = pale
		end
	end
	for _, object in root:GetDescendants() do
		consider(object)
	end
	root.DescendantAdded:Connect(consider)
end

--- Where a menu card's sheet starts, in pixels from the card's top (just under its header);
--- it runs to the card's bottom, inset by Kit.SheetInsetPx at the sides and bottom.
function HudParts.setSheetTop(card: Frame, topPx: number)
	local fill = card:FindFirstChild("Fill")
	local sheet = fill and fill:FindFirstChild("Sheet") :: Frame?
	if not sheet then
		return
	end
	local inset = K.SheetInsetPx
	sheet.Position = UDim2.fromOffset(inset, topPx)
	sheet.Size = UDim2.new(1, -inset * 2, 1, -topPx - inset)
	if card:GetAttribute("Lively") then
		-- The scrolling header only needs to reach under the sheet's round top corners.
		local band = (fill :: Frame):FindFirstChild("Pattern") :: ImageLabel
		band.Size = UDim2.new(1, 0, 0, topPx + K.SheetCornerPx)
	end
end

--- A small rounded tag (a status, a count, the clock): a flat fill with an ink outline.
function HudParts.pill(parent: Instance, name: string, tint: Color3?): Frame
	local object = HudParts.frame(parent, name)
	object.BackgroundTransparency = 0
	object.BackgroundColor3 = tint or color(K.Colors.White)
	HudParts.corner(object, K.PillCornerPx)
	inkStroke(object, K.ButtonStrokePx - 0.5, Enum.ApplyStrokeMode.Border)
	return object
end

--- One of the glossy icons (Config.UI.Kit.Icons) by key, fitted into its box.
function HudParts.icon(parent: Instance, key: string, name: string?): ImageLabel
	local object = Instance.new("ImageLabel")
	object.Name = name or (key .. "Icon")
	object.BackgroundTransparency = 1
	object.ScaleType = Enum.ScaleType.Fit
	object.Image = K.Icons[key] or ""
	object.Parent = parent
	return object
end

function HudParts.setIcon(object: ImageLabel, key: string?)
	object.Image = if key then K.Icons[key] or "" else ""
	object.Visible = key ~= nil
end

--------------------------------------------------------------------------------------------
-- Candy buttons
--------------------------------------------------------------------------------------------

type Candy = {
	body: Frame,
	face: Frame,
	gradient: UIGradient,
	edge: UIStroke,
	label: TextLabel,
	icon: ImageLabel,
	press: UIScale,
	tone: string,
	textSize: number,
	enabled: boolean,
	lit: boolean,
	vertical: boolean,
	action: () -> (),
	squish: (boolean) -> (),
	light: (boolean) -> (),
	hit: TextButton?,
	onLit: ((boolean) -> ())?, -- told when the candy lights up or goes out (HudParts.onLit)
	iconShare: number?, -- its icon's share of the height beside words (HudParts.setIconShare)
	rightInset: number?, -- room kept clear at its right, in pixels (HudParts.setRightInset)
}

-- Held strongly and cleared on Destroying: a weak table keyed on Instances can lose entries.
local candies: { [TextButton]: Candy } = {}

local function candyColors(tone: string): ColorSequence
	local c = K.Buttons[tone] or K.Buttons.White
	local lip = 1 - K.ButtonLipShare
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, color(c.Top)),
		ColorSequenceKeypoint.new(0.42, color(c.Mid)),
		ColorSequenceKeypoint.new(lip - 0.001, color(c.Mid)),
		ColorSequenceKeypoint.new(lip, color(c.Lip)),
		ColorSequenceKeypoint.new(1, color(c.Lip)),
	})
end

-- How much the UIScales on an object and its ancestors shrink or grow it. AbsoluteSize
-- includes them, but offsets inside are scaled again, so layout must divide them out.
local function scaleOf(object: Instance): number
	local total = 1
	local node: Instance? = object
	while node and not node:IsA("LayerCollector") do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then
				total *= child.Scale
			end
		end
		node = node.Parent
	end
	return if total > 0 then total else 1
end

-- Place the icon and the words above the lip, the icon to the left of the words.
-- A candy button's face above its lip, and the room at its ends, for a button `height` tall.
local function candyRoom(height: number): (number, number)
	local usable = height - math.floor(height * K.ButtonLipShare + 0.5)
	return usable, math.max(6, math.floor(usable * 0.18))
end

local function layoutCandy(button: TextButton, c: Candy)
	local size = button.AbsoluteSize / scaleOf(button)
	if size.Y <= 0 then
		return
	end
	local usable, pad = candyRoom(size.Y)
	if c.vertical then
		-- A tile: the icon big on top, the words under it.
		local labelHeight = math.floor(usable * 0.3)
		local iconSize = math.floor(math.min(size.X - pad * 2, usable - labelHeight - pad * 0.8))
		c.icon.AnchorPoint = Vector2.new(0.5, 0)
		c.icon.Position = UDim2.fromOffset(size.X / 2, math.floor(pad * 0.5))
		c.icon.Size = UDim2.fromOffset(iconSize, iconSize)
		c.label.Position = UDim2.fromOffset(4, usable - labelHeight - 2)
		c.label.Size = UDim2.fromOffset(math.max(1, size.X - 8), labelHeight)
		return
	end
	local hasIcon = c.icon.Visible
	local hasText = c.label.Text ~= ""
	local share = if hasText then c.iconShare or K.ButtonIconShare else K.ButtonIconOnlyShare
	local iconSize = if hasIcon then math.floor(usable * share) else 0
	if hasIcon and not hasText then
		c.icon.AnchorPoint = Vector2.new(0.5, 0.5)
		c.icon.Position = UDim2.fromOffset(size.X / 2, usable / 2)
	else
		c.icon.AnchorPoint = Vector2.new(0, 0.5)
		c.icon.Position = UDim2.fromOffset(pad, usable / 2)
	end
	c.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local left = if hasIcon then pad + iconSize + math.floor(pad / 2) else pad
	local right = pad + (c.rightInset or 0)
	c.label.Position = UDim2.fromOffset(left, 2)
	c.label.Size = UDim2.fromOffset(math.max(1, size.X - left - right), math.max(1, usable - 2))
end

--- A raised candy button: a light top, its colour, a darker lip along the bottom, an ink
--- outline, an optional icon left of the words. It squishes when pressed and grows with a
--- thick gold outline when hovered or selected by a gamepad. `tone` is a Config.UI.Kit.Buttons
--- name (Green, Red, Blue, Yellow, Grey, White). Change it with the set* functions below,
--- never through the TextButton's own Text or colours (it draws nothing itself).
function HudParts.candy(
	parent: Instance,
	text: string,
	action: () -> (),
	tone: string?,
	iconKey: string?
): TextButton
	local button = Instance.new("TextButton")
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	-- Our own highlight shows selection; hide Roblox's default selection box.
	local noBox = Instance.new("Frame")
	noBox.BackgroundTransparency = 1
	button.SelectionImageObject = noBox
	local body = HudParts.frame(button, "Body")
	body.Size = UDim2.fromScale(1, 1)
	local press = Instance.new("UIScale")
	press.Parent = body
	local face = HudParts.frame(body, "Face")
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundTransparency = 0
	face.BackgroundColor3 = color(K.Colors.White)
	face.ZIndex = 0
	HudParts.corner(face, K.ButtonCornerPx)
	local edge = inkStroke(face, K.ButtonStrokePx, Enum.ApplyStrokeMode.Border)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = face
	local label = HudParts.text(body, "Label", K.Text.Button, text)
	label.ZIndex = 2
	label.TextWrapped = false -- a button's words shrink to fit on one line
	local icon = HudParts.icon(body, iconKey or "Play", "Icon")
	icon.ZIndex = 2
	icon.Visible = iconKey ~= nil
	local c: Candy = {
		body = body,
		face = face,
		gradient = gradient,
		edge = edge,
		label = label,
		icon = icon,
		press = press,
		tone = tone or "White",
		textSize = K.Text.Button,
		enabled = true,
		lit = false,
		vertical = false,
		action = action,
		squish = function(_: boolean) end,
		light = function(_: boolean) end,
		hit = nil,
	}
	candies[button] = c
	button.Destroying:Connect(function()
		candies[button] = nil
	end)
	gradient.Color = candyColors(c.tone)
	button.Parent = parent
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layoutCandy(button, c)
	end)
	local pressTween: Tween? = nil
	local function squish(down: boolean)
		if pressTween then
			pressTween:Cancel()
		end
		local scale = if down and c.enabled
			then K.PressedScale
			elseif c.lit then K.SelectedScale
			else 1
		local nextTween = TweenService:Create(
			press,
			TweenInfo.new(S.QuickMotion, Enum.EasingStyle.Quad),
			{ Scale = scale }
		)
		pressTween = nextTween
		nextTween:Play()
	end
	local function light(on: boolean)
		c.lit = on and c.enabled
		edge.Color = if c.lit then color(K.Colors.Gold) else INK
		edge.Thickness = if c.lit then K.SelectedStrokePx else K.ButtonStrokePx
		squish(false)
		UIAnim.sway(body, c.lit, nil, button)
		local onLit = c.onLit
		if onLit then
			onLit(c.lit)
		end
	end
	c.squish, c.light = squish, light
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			squish(true)
		end
	end)
	button.InputEnded:Connect(function()
		squish(false)
	end)
	button.MouseEnter:Connect(function()
		light(true)
	end)
	button.MouseLeave:Connect(function()
		light(false)
	end)
	button.SelectionGained:Connect(function()
		light(true)
	end)
	button.SelectionLost:Connect(function()
		light(false)
	end)
	button.Activated:Connect(function()
		if c.enabled then
			-- A bigger click (designer, 2026-10-03): a glow bursts from behind the button.
			local tint = K.Buttons[c.tone] or K.Buttons.White
			UIAnim.glowBurst(body, color(tint.Mid))
			action()
		end
	end)
	layoutCandy(button, c)
	return button
end

--- A tall candy tile: a big icon over its name (the difficulty choices).
function HudParts.tile(
	parent: Instance,
	text: string,
	action: () -> (),
	tone: string?,
	iconKey: string
): TextButton
	local button = HudParts.candy(parent, text, action, tone, iconKey)
	local c = candies[button]
	c.vertical = true
	layoutCandy(button, c)
	return button
end

--- Put the controller's back button (Circle, or B on Xbox: Roblox's own picture) on close button
--- `button`'s bottom-left corner, shown only while a gamepad is the last input (Kit.PadBack).
--- Only on a close that B really closes. It follows the controller in use and goes with the button.
function HudParts.padBack(button: GuiButton): Frame
	local cfg = K.PadBack
	local disc = Instance.new("Frame")
	disc.Name = "PadBack"
	disc.BackgroundColor3 = INK
	disc.BorderSizePixel = 0
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(cfg.At[1], cfg.At[2])
	disc.Size = UDim2.fromScale(cfg.Share, cfg.Share)
	disc.ZIndex = button.ZIndex + 6
	disc.Visible = false
	HudParts.corner(disc, 999)
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(cfg.GlyphShare, cfg.GlyphShare)
	glyph.ZIndex = disc.ZIndex + 1
	glyph.Parent = disc
	disc.Parent = button
	local function refresh()
		local pad = string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad"
		local image = ""
		if pad then
			local ok, found = pcall(function()
				return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
			end)
			image = if ok and type(found) == "string" then found else ""
		end
		glyph.Image = image
		disc.Visible = image ~= ""
	end
	local connections = {
		UserInputService.LastInputTypeChanged:Connect(refresh),
		UserInputService.GamepadConnected:Connect(refresh),
		UserInputService.GamepadDisconnected:Connect(refresh),
	}
	button.Destroying:Connect(function()
		for _, connection in connections do
			connection:Disconnect()
		end
	end)
	refresh()
	return disc
end

--- Give a small button a touch area of at least `minPx` square, centred on it, without
--- growing its look, so a compact button still meets the touch target (UI_STYLE section 5).
function HudParts.setMinHit(button: TextButton, minPx: number)
	local c = candies[button]
	if not c or c.hit then
		return
	end
	local hit = Instance.new("TextButton")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Selectable = false
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 10
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(minPx, minPx)
	least.Parent = hit
	hit.Parent = button
	hit.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			c.squish(true)
		end
	end)
	hit.InputEnded:Connect(function()
		c.squish(false)
	end)
	hit.MouseEnter:Connect(function()
		c.light(true)
	end)
	hit.MouseLeave:Connect(function()
		c.light(false)
	end)
	hit.Activated:Connect(function()
		if c.enabled then
			c.action()
		end
	end)
	c.hit = hit
end

function HudParts.setText(button: TextButton, text: string)
	local c = candies[button]
	if c and c.label.Text ~= text then
		c.label.Text = text
		layoutCandy(button, c)
	end
end

--- A candy's icon beside its words at `share` of the button's height instead of the kit's
--- ButtonIconShare (the Grand Opening card's big cash bundles).
function HudParts.setIconShare(button: TextButton, share: number)
	local c = candies[button]
	if c and c.iconShare ~= share then
		c.iconShare = share
		layoutCandy(button, c)
	end
end

--- Keep `px` clear at a candy's right for something drawn there (Auto Spin's switch): its words
--- centre in what is left.
function HudParts.setRightInset(button: TextButton, px: number)
	local c = candies[button]
	if c and c.rightInset ~= px then
		c.rightInset = px
		layoutCandy(button, c)
	end
end

function HudParts.setTone(button: TextButton, tone: string)
	local c = candies[button]
	if c and c.tone ~= tone then
		c.tone = tone
		c.gradient.Color = candyColors(tone)
	end
end

function HudParts.setButtonIcon(button: TextButton, key: string?)
	local c = candies[button]
	if c then
		HudParts.setIcon(c.icon, key)
		layoutCandy(button, c)
	end
end

--- How wide a (non-tile) candy button `height` tall wants to be so its words fit at `textPx`
--- with its icon: rows of buttons share their width by this, so long words get more room.
function HudParts.candyWidth(button: TextButton, height: number, textPx: number): number
	local c = candies[button]
	if not c then
		return 0
	end
	local usable, pad = candyRoom(height)
	local width = 2 * pad + (c.rightInset or 0)
	if c.label.Text ~= "" then
		width += math.ceil(
			TextService:GetTextSize(c.label.Text, textPx, FONT, Vector2.new(4000, 400)).X
		)
	end
	if c.icon.Visible then
		local share = if c.label.Text ~= ""
			then c.iconShare or K.ButtonIconShare
			else K.ButtonIconOnlyShare
		width += math.floor(usable * share) + math.floor(pad / 2)
	end
	return width
end

function HudParts.setButtonTextSize(button: TextButton, size: number, floor: number?)
	local c = candies[button]
	if c and c.textSize ~= size then
		c.textSize = size
		HudParts.setTextSize(c.label, size, floor)
	end
end

--- A button that may not be pressed stays on screen, faded, and cannot be selected. `faded`
--- false keeps a locked button's full look (the host's choice, seen by a guest).
function HudParts.setEnabled(button: TextButton, enabled: boolean, faded: boolean?)
	local c = candies[button]
	local fadeIt = if faded == nil then not enabled else faded
	if not c or (c.enabled == enabled and (c.face.BackgroundTransparency > 0) == fadeIt) then
		return
	end
	c.enabled = enabled
	button.Active = enabled
	button.Selectable = enabled
	local fade = if fadeIt then K.DisabledTransparency else 0
	c.face.BackgroundTransparency = fade
	c.edge.Transparency = fade
	HudParts.setTextTransparency(c.label, fade)
	c.icon.ImageTransparency = fade
	if not enabled then
		c.lit = false
		c.edge.Color = INK
		c.edge.Thickness = K.ButtonStrokePx
		c.press.Scale = 1
		UIAnim.sway(c.body, false)
		local onLit = c.onLit
		if onLit then
			onLit(false)
		end
	end
end

--- Run `fn(lit)` whenever a candy lights up (hover, a gamepad resting on it) or goes out: the
--- icon tiles show their sun rays then.
function HudParts.onLit(button: TextButton, fn: (boolean) -> ())
	local c = candies[button]
	if c then
		c.onLit = fn
	end
end

--- The parts of a candy button, for the few screens that animate them (UIAnim.shine).
function HudParts.candyParts(button: TextButton): any
	return candies[button]
end

--------------------------------------------------------------------------------------------
-- HUD balls
--------------------------------------------------------------------------------------------

--- A glossy numbered ball: a circle with a thick ink ring (so no ball, a stripe above all,
--- melts into the white panel), the band for stripes, the number disc, the shine, and a red
--- X shown once it is down. Size it with sizeBall and draw it with paintBall.
function HudParts.ball(parent: Instance): any
	local root = HudParts.frame(parent, "BallSlot")
	local sphere = HudParts.frame(root, "Ball")
	sphere.Size = UDim2.fromScale(1, 1)
	sphere.BackgroundTransparency = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = sphere
	local ring = inkStroke(sphere, K.Ball.StrokePx, Enum.ApplyStrokeMode.Border)
	local band = Instance.new("ImageLabel")
	band.Name = "Band"
	band.BackgroundTransparency = 1
	band.Image = K.Art.BallBand
	band.Size = UDim2.fromScale(1, 1)
	band.ZIndex = 1
	band.Parent = sphere
	local disc = HudParts.frame(sphere, "NumberDisc")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(K.Ball.DiscShare, K.Ball.DiscShare)
	disc.BackgroundTransparency = 0
	disc.BackgroundColor3 = color(K.Colors.White)
	disc.ZIndex = 2
	local discRound = Instance.new("UICorner")
	discRound.CornerRadius = UDim.new(0.5, 0)
	discRound.Parent = disc
	local number = Instance.new("TextLabel")
	number.Name = "Number"
	number.BackgroundTransparency = 1
	number.Font = FONT
	number.TextColor3 = INK
	number.AnchorPoint = Vector2.new(0.5, 0.5)
	number.Position = UDim2.fromScale(0.5, 0.52)
	number.Size = UDim2.fromScale(2, 2)
	number.ZIndex = 3
	number.Parent = disc
	local gloss = Instance.new("ImageLabel")
	gloss.Name = "Gloss"
	gloss.BackgroundTransparency = 1
	gloss.Image = K.Art.BallGloss
	gloss.Size = UDim2.fromScale(1, 1)
	gloss.ZIndex = 4
	gloss.Parent = sphere
	local cross = HudParts.icon(root, "X", "Pocketed")
	cross.AnchorPoint = Vector2.new(0.5, 0.5)
	cross.Position = UDim2.fromScale(0.5, 0.5)
	cross.Size = UDim2.fromScale(0.95, 0.95)
	cross.ZIndex = 5
	cross.Visible = false
	local scale = Instance.new("UIScale")
	scale.Parent = root
	return {
		root = root,
		sphere = sphere,
		ring = ring,
		band = band,
		disc = disc,
		number = number,
		cross = cross,
		scale = scale,
		down = false,
		changedAt = 0,
	}
end

--- Size a ball slot in pixels; the number follows.
function HudParts.sizeBall(ball: any, size: number)
	ball.root.Size = UDim2.fromOffset(size, size)
	ball.number.TextSize = math.max(7, math.floor(size * K.Ball.NumberShare + 0.5))
	ball.ring.Thickness = if size < 22 then K.Ball.StrokePx - 0.5 else K.Ball.StrokePx
end

--- Draw ball `id`: its own colours, or grey with the red X once it is down. The 8 is faded
--- while it may not be played yet and ringed green once it may.
function HudParts.paintBall(ball: any, id: number, down: boolean, ready: boolean?)
	local tint = color(Config.Balls.Colors[if id > 8 then id - 8 else id])
	ball.number.Text = tostring(id)
	ball.cross.Visible = down
	ball.band.Visible = id > 8 and not down
	ball.band.ImageColor3 = tint
	ball.disc.Visible = not down
	ball.sphere.BackgroundColor3 = if down
		then color(K.Colors.Grey)
		elseif id > 8 then color(K.Colors.White)
		else tint
	local eightReady = id == 8 and ready == true
	ball.ring.Color = if eightReady then color(K.Colors.Green) else INK
	ball.ring.Thickness = if eightReady then K.Ball.StrokePx + 1.5 else K.Ball.StrokePx
	ball.sphere.BackgroundTransparency = if id == 8 and ready == false and not down then 0.35 else 0
end

return HudParts
