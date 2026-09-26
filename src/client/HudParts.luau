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
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
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

function HudParts.corner(parent: Instance, radius: number)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
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
	local pattern = Instance.new("ImageLabel")
	pattern.Name = "Pattern"
	pattern.BackgroundTransparency = 1
	pattern.Image = K.PatternImage
	pattern.ImageColor3 = color(K.PatternColor)
	pattern.ImageTransparency = K.PatternTransparency
	pattern.ScaleType = Enum.ScaleType.Tile
	pattern.TileSize = UDim2.fromOffset(K.PatternTilePx, K.PatternTilePx)
	pattern.Size = UDim2.fromScale(1, 1)
	pattern.Parent = fill
	HudParts.corner(pattern, cornerPx) -- clips the tiles to the card's round corners
	return root
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
local function layoutCandy(button: TextButton, c: Candy)
	local size = button.AbsoluteSize / scaleOf(button)
	if size.Y <= 0 then
		return
	end
	local lip = math.floor(size.Y * K.ButtonLipShare + 0.5)
	local usable = size.Y - lip
	local pad = math.max(6, math.floor(usable * 0.18))
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
	local iconSize = if hasIcon then math.floor(usable * K.ButtonIconShare) else 0
	local hasText = c.label.Text ~= ""
	if hasIcon and not hasText then
		c.icon.AnchorPoint = Vector2.new(0.5, 0.5)
		c.icon.Position = UDim2.fromOffset(size.X / 2, usable / 2)
	else
		c.icon.AnchorPoint = Vector2.new(0, 0.5)
		c.icon.Position = UDim2.fromOffset(pad, usable / 2)
	end
	c.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	local left = if hasIcon then pad + iconSize + math.floor(pad / 2) else pad
	c.label.Position = UDim2.fromOffset(left, 2)
	c.label.Size = UDim2.fromOffset(math.max(1, size.X - left - pad), math.max(1, usable - 2))
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
	end
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

function HudParts.setText(button: TextButton, text: string)
	local c = candies[button]
	if c and c.label.Text ~= text then
		c.label.Text = text
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

function HudParts.setButtonTextSize(button: TextButton, size: number)
	local c = candies[button]
	if c and c.textSize ~= size then
		c.textSize = size
		HudParts.setTextSize(c.label, size)
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
