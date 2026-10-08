--!strict
-- CuesRail: the tiles outside the Cues menu's right edge (docs/prompts/CUES_LIVELY_PROMPT.md,
-- concept 2, approved round 2, 2026-10-08), top to bottom:
--   * the switch: one button in two halves, My Cues over Index, a blue knob on the half you
--     are in; a press (or A) flips to the other. Each half wears its red dot: the NEW count on
--     My Cues, "!" on the Index while a row can be claimed. Hover and a gamepad give it the
--     kit's gold outline and a small grow, a press squishes it, as the candy buttons.
--   * Sort: the grid's next order, the order's name hanging under it in a blue pill;
--   * Sell all: every duplicate sold (it asks first), the money it would pay hanging under it
--     in a gold pill; greyed out at nothing to sell.
-- Sort and Sell all step aside while the Index shows. Built in the panel (so a gamepad reaches
-- them) like the Shop's jump buttons: outside the panel's right edge when the screen has room,
-- else a column inside the page's right side. Sizes in Config.UI.Inventory.Rail, words in
-- Strings.Menus.Inventory and Strings.Menus.Tabs.Inventory.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Inventory.Rail
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local VIEW_WORDS: { [string]: string } = Strings.Menus.Tabs.Inventory :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local QUICK = Config.Multiplayer.Style.QuickMotion
local INK = HudParts.tone("Ink")
local VIEWS = { "Cues", "Index" }

export type Actions = {
	flip: () -> (), -- the switch: the other view
	sort: () -> (),
	sell: () -> (),
}

type Half = { frame: Frame, icon: ImageLabel, word: TextLabel, dot: Frame, dotText: TextLabel }

local CuesRail = {}
CuesRail.__index = CuesRail

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function span(pair: { number }, t: number): number
	return round(pair[1] + (pair[2] - pair[1]) * t)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- The icon key the Cues menu shows for My Cues (the backpack until the CUES icon is made).
function CuesRail.cuesIcon(): string
	local id = (K.Icons :: any).Cues
	return if type(id) == "string" and id ~= "" then "Cues" else "Inventory"
end

-- A red dot with a word ("3", "9+", "!").
local function redDot(parent: Instance): (Frame, TextLabel)
	local dot = HudParts.pill(parent, "Dot", HudParts.tone("Red"))
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.ZIndex = 8
	dot.Visible = false
	local text = HudParts.text(dot, "Count", K.Text.Min, "")
	text.AutoLocalize = false -- a number
	text.TextWrapped = false
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 9
	return dot, text
end

-- A pill hanging under a tile's bottom edge.
local function hang(parent: Instance, tone: string): (Frame, TextLabel)
	local tint = K.Buttons[tone] or K.Buttons.White
	local pill = HudParts.pill(parent, "Hang", HudParts.color(tint.Mid))
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.ZIndex = 7
	local text = HudParts.text(pill, "Words", K.Text.Min, "")
	text.AutoLocalize = false -- a name from Strings or a sum of money
	text.TextWrapped = false
	text.Size = UDim2.fromScale(1, 1)
	text.ZIndex = 8
	return pill, text
end

--- Build the rail into `frame.panel` (closed with the menu). `actions` run on a press.
function CuesRail.new(frame: any, actions: Actions): any
	local self: any = setmetatable({}, CuesRail)
	self.frame = frame
	self.view = "Cues"
	self.geo = nil :: MenuFrame.Geo?
	self.lit = false
	self.down = false
	self.pressTween = nil :: Tween?
	self.knobTween = nil :: Tween?
	self.half = 0 -- a half's height at the last layout

	local holder = HudParts.frame(frame.panel, "Rail")
	holder.ZIndex = 4
	self.holder = holder

	-- The switch: a white track with an ink outline, the blue knob, the two halves.
	local switch = Instance.new("TextButton")
	switch.Name = "Switch"
	switch.Text = ""
	switch.AutoButtonColor = false
	switch.BackgroundTransparency = 1
	switch.BorderSizePixel = 0
	switch.Selectable = true
	switch.ZIndex = 4
	local noBox = Instance.new("Frame") -- the gold outline shows selection, not Roblox's box
	noBox.BackgroundTransparency = 1
	switch.SelectionImageObject = noBox
	switch.Parent = holder
	self.switch = switch
	local body = HudParts.frame(switch, "Body")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 4
	self.body = body
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = body
	self.press = press
	local track = HudParts.frame(body, "Track")
	track.Size = UDim2.fromScale(1, 1)
	track.BackgroundTransparency = 0
	track.BackgroundColor3 = HudParts.tone("White")
	track.ClipsDescendants = true
	track.ZIndex = 4
	local trackRound = Instance.new("UICorner")
	trackRound.Parent = track
	self.trackRound = trackRound
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(HudParts.tone("White"), HudParts.color(K.PanelFade))
	fade.Parent = track
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = INK
	edge.Thickness = K.ButtonStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = track
	self.edge = edge
	local knob = HudParts.frame(track, "Knob")
	knob.BackgroundTransparency = 0
	knob.BackgroundColor3 = HudParts.tone("White")
	knob.ZIndex = 5
	local knobRound = Instance.new("UICorner")
	knobRound.Parent = knob
	self.knobRound = knobRound
	local knobColors = K.Buttons.Blue
	local knobFill = Instance.new("UIGradient")
	knobFill.Rotation = 90
	knobFill.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HudParts.color(knobColors.Top)),
		ColorSequenceKeypoint.new(0.45, HudParts.color(knobColors.Mid)),
		ColorSequenceKeypoint.new(1, HudParts.color(knobColors.Lip)),
	})
	knobFill.Parent = knob
	local knobEdge = Instance.new("UIStroke")
	knobEdge.Color = INK
	knobEdge.Thickness = 2
	knobEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	knobEdge.Parent = knob
	local shine = HudParts.frame(knob, "Shine")
	shine.BackgroundTransparency = 0.6
	shine.BackgroundColor3 = HudParts.tone("White")
	shine.Position = UDim2.fromScale(0.1, 0.09)
	shine.Size = UDim2.fromScale(0.8, 0.2)
	shine.ZIndex = 6
	local shineRound = Instance.new("UICorner")
	shineRound.CornerRadius = UDim.new(0.5, 0)
	shineRound.Parent = shine
	self.knob = knob
	local split = HudParts.frame(track, "Split")
	split.BackgroundTransparency = 0.78
	split.BackgroundColor3 = INK
	split.ZIndex = 5
	self.split = split

	-- The halves (over the knob), each with its red dot on the switch's right edge.
	local dots = HudParts.frame(switch, "Dots")
	dots.Size = UDim2.fromScale(1, 1)
	dots.ZIndex = 8
	self.dots = dots
	self.halves = {} :: { [string]: Half }
	for _, key in VIEWS do
		local frameHalf = HudParts.frame(track, "Half" .. key)
		frameHalf.ZIndex = 6
		local icon =
			HudParts.icon(frameHalf, if key == "Cues" then CuesRail.cuesIcon() else "Index", "Icon")
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.ZIndex = 7
		local word = HudParts.text(frameHalf, "Word", K.Text.Min, VIEW_WORDS[key] or key)
		word.TextWrapped = false
		word.ZIndex = 7
		local dot, dotText = redDot(dots)
		dot.Name = "Dot" .. key
		self.halves[key] =
			{ frame = frameHalf, icon = icon, word = word, dot = dot, dotText = dotText }
	end

	local function settle()
		if self.pressTween then
			self.pressTween:Cancel()
		end
		local scale = if self.down then K.PressedScale elseif self.lit then K.SelectedScale else 1
		self.pressTween = TweenService:Create(
			press,
			TweenInfo.new(QUICK, Enum.EasingStyle.Quad),
			{ Scale = scale }
		)
		self.pressTween:Play()
	end
	local function light(on: boolean)
		self.lit = on
		edge.Color = if on then HudParts.tone("Gold") else INK
		edge.Thickness = if on then K.SelectedStrokePx else K.ButtonStrokePx
		settle()
		UIAnim.sway(body, on, nil, switch)
	end
	switch.MouseEnter:Connect(function()
		light(true)
	end)
	switch.MouseLeave:Connect(function()
		self.down = false
		light(false)
	end)
	switch.SelectionGained:Connect(function()
		light(true)
	end)
	switch.SelectionLost:Connect(function()
		light(false)
	end)
	switch.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			self.down = true
			settle()
		end
	end)
	switch.InputEnded:Connect(function()
		self.down = false
		settle()
	end)
	switch.Activated:Connect(function()
		UISound.play("Click")
		UIAnim.glowBurst(body, HudParts.color(knobColors.Mid))
		actions.flip()
	end)

	-- Sort and Sell all, each with its hanging pill.
	self.sort = HudParts.tile(holder, WORDS.SortTile, function()
		UISound.play("Click")
		actions.sort()
	end, "White", "Sliders")
	self.sort.Name = "Sort"
	self.sortHang, self.sortHangText = hang(self.sort, R.SortTone)
	self.sell = HudParts.tile(holder, WORDS.SellAllTile, function()
		actions.sell()
	end, "White", "Sell")
	self.sell.Name = "SellAll"
	self.sellHang, self.sellHangText = hang(self.sell, R.SellTone)
	self.sellAmount = 0
	return self
end

--- Add the rail's pieces to the menu's open (Config.UI.Inventory.Open "Switch", "Sort", "Sell"
--- and their badges: the switch's dots, the hanging pills).
function CuesRail.register(self: any, stage: any)
	stage:add("Switch", self.switch)
	stage:add("SwitchBadge", self.dots)
	stage:add("Sort", self.sort)
	stage:add("SortBadge", self.sortHang)
	stage:add("Sell", self.sell)
	stage:add("SellBadge", self.sellHang)
end

--- Whether the rail fits outside a panel `panelW` wide (else a column in the page).
function CuesRail.outside(self: any, panelW: number, t: number): boolean
	local room = (self.frame.root.AbsoluteSize.X - panelW) / 2
	return room >= span(R.TilePx, t) + 2 * R.OutsidePx
end

--- The page width a column of the rail inside the page takes.
function CuesRail.room(_self: any, t: number): number
	return span(R.TilePx, t) + span(R.GapPx, t)
end

-- The knob's place for a view (Cues on top, Index under it).
function CuesRail.knobAt(self: any, view: string): UDim2
	local inset = R.KnobInsetPx
	return UDim2.fromOffset(inset, if view == "Index" then self.half + 2 + inset else inset)
end

--- Lay the rail out beside the panel (or in the page); returns the page width it leaves.
function CuesRail.layout(self: any, geo: MenuFrame.Geo): number
	self.geo = geo
	local t = geo.t
	local frame = self.frame
	local panel: Frame = frame.panel
	local tile = span(R.TilePx, t)
	local half = round(tile * R.HalfShare)
	self.half = half
	local switchH = 2 * half + 2 + 2 * R.KnobInsetPx
	local gap = span(R.GapPx, t)
	local hangH = span(R.HangPx, t)
	local railH = switchH + 2 * (gap + tile) + math.ceil(hangH / 2)
	-- Offsets, not absolute sizes: the panel may be mid pop-in (scaled) when this runs.
	local panelW, panelH = panel.Size.X.Offset, panel.Size.Y.Offset
	local content: Frame = frame.content
	local contentTop = content.Position.Y.Offset
	local width = geo.content.X
	local x, y
	if self:outside(panelW, t) then
		x = panelW + R.OutsidePx
		-- Level with the page's top; pinned higher when the panel is shorter than the rail.
		y = contentTop
		if y + railH > panelH then
			y = math.max(0, panelH - railH)
		end
	else
		width = math.max(1, geo.content.X - tile - gap)
		x = content.Position.X.Offset + width + gap
		y = contentTop + math.max(0, round((geo.content.Y - railH) / 2))
	end
	self.holder.Position = UDim2.fromOffset(x, y)
	self.holder.Size = UDim2.fromOffset(tile, railH)

	-- The switch.
	local textPx = span(R.TextPx, t)
	self.switch.Position = UDim2.fromOffset(0, 0)
	self.switch.Size = UDim2.fromOffset(tile, switchH)
	self.trackRound.CornerRadius = UDim.new(0, round(tile * 0.2))
	self.knobRound.CornerRadius = UDim.new(0, round(tile * 0.15))
	local inner = tile - 2 * R.KnobInsetPx
	self.knob.Size = UDim2.fromOffset(inner, half - 2)
	if not self.knobTween then
		self.knob.Position = self:knobAt(self.view)
	end
	self.split.AnchorPoint = Vector2.new(0.5, 0.5)
	self.split.Position = UDim2.fromOffset(round(tile / 2), R.KnobInsetPx + half + 1)
	self.split.Size = UDim2.fromOffset(round(tile * 0.72), 2)
	local dotPx = span(R.DotPx, t)
	local dotText = span(R.DotTextPx, t)
	for index, key in VIEWS do
		local h: Half = self.halves[key]
		local top = R.KnobInsetPx + (index - 1) * (half + 2)
		h.frame.Position = UDim2.fromOffset(0, top)
		h.frame.Size = UDim2.fromOffset(tile, half)
		local icon = round(half * R.IconShare)
		-- A long word shrinks to fit the half, never under MinTextPx.
		local wordPx = textPx
		local word = h.word.Text
		while wordPx > R.MinTextPx and textWidth(word, wordPx) > tile - 10 do
			wordPx -= 1
		end
		local wordH = wordPx + 4
		local top0 = math.max(0, round((half - icon - wordH) / 2))
		h.icon.Position = UDim2.fromOffset(round(tile / 2), top0)
		h.icon.Size = UDim2.fromOffset(icon, icon)
		h.word.Position = UDim2.fromOffset(0, top0 + icon)
		h.word.Size = UDim2.fromOffset(tile, wordH)
		HudParts.setTextSize(h.word, wordPx, wordPx)
		h.dot.Position = UDim2.fromOffset(tile - 4, top + round(half * 0.3))
		local dotW = math.max(dotPx, math.ceil(textWidth(h.dotText.Text, dotText)) + 10)
		h.dot.Size = UDim2.fromOffset(dotW, dotPx)
		HudParts.setTextSize(h.dotText, dotText, dotText)
	end

	-- Sort and Sell all under it, each with its hanging pill.
	local hangText = span(R.HangTextPx, t)
	local at = switchH + gap
	for _, entry in
		{
			{ self.sort, self.sortHang, self.sortHangText },
			{ self.sell, self.sellHang, self.sellHangText },
		} :: { { any } }
	do
		local button: TextButton, pill: Frame, words: TextLabel = entry[1], entry[2], entry[3]
		button.Position = UDim2.fromOffset(0, at)
		button.Size = UDim2.fromOffset(tile, tile)
		HudParts.setButtonTextSize(button, textPx)
		local pillW = math.ceil(textWidth(words.Text, hangText)) + 2 * R.HangPadPx
		pill.Position = UDim2.new(0.5, 0, 1, -1)
		pill.Size = UDim2.fromOffset(math.max(hangH, pillW), hangH)
		HudParts.setTextSize(words, hangText, hangText)
		at += tile + gap
	end
	return width
end

--- Show which view is chosen: the knob slides there (at once with `instant` or Reduce
--- Motion), the other half's icon fades, and Sort and Sell all step aside in the Index.
function CuesRail.setView(self: any, view: string, instant: boolean?)
	local changed = self.view ~= view
	self.view = view
	for key, h in self.halves :: { [string]: Half } do
		h.icon.ImageTransparency = if key == view then 0 else R.IdleIconTransparency
	end
	if self.knobTween then
		self.knobTween:Cancel()
		self.knobTween = nil
	end
	local target = self:knobAt(view)
	if instant or not changed or UIAnim.reduced() or self.half <= 0 then
		self.knob.Position = target
	else
		local tween = TweenService:Create(
			self.knob,
			TweenInfo.new(R.KnobSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Position = target }
		)
		self.knobTween = tween
		tween.Completed:Connect(function()
			if self.knobTween == tween then
				self.knobTween = nil
			end
		end)
		tween:Play()
	end
	local index = view == "Index"
	for _, button in { self.sort, self.sell } do
		button.Selectable = not index and HudParts.candyParts(button).enabled
		if instant then
			button.Visible = not index
		elseif index then
			UIAnim.popOut(button)
		elseif not button.Visible then
			UIAnim.popIn(button)
		end
	end
end

--- The red dots: the NEW count on My Cues, "!" on the Index (nil: none).
function CuesRail.setDots(self: any, cues: string?, index: string?)
	local words: { [string]: string } = { Cues = cues or "", Index = index or "" }
	for key, value in words do
		local h: Half = self.halves[key]
		local show = value ~= ""
		if show and h.dotText.Text ~= value then
			h.dotText.Text = value
			if self.geo then
				local t = self.geo.t
				local dotPx = span(R.DotPx, t)
				local w = math.ceil(textWidth(value, span(R.DotTextPx, t))) + 10
				h.dot.Size = UDim2.fromOffset(math.max(dotPx, w), dotPx)
			end
		end
		h.dot.Visible = show
	end
end

--- The order's name under Sort.
function CuesRail.setSort(self: any, name: string)
	if self.sortHangText.Text ~= name then
		self.sortHangText.Text = name
		if self.geo then
			self:layout(self.geo)
		end
	end
end

--- The money Sell all would pay (`amount` as words), greyed out with nothing to sell.
function CuesRail.setSell(self: any, words: string, enabled: boolean)
	HudParts.setEnabled(self.sell, enabled)
	self.sell.Selectable = enabled and self.view ~= "Index"
	if self.sellHangText.Text ~= words then
		self.sellHangText.Text = words
		if self.geo then
			self:layout(self.geo)
		end
	end
end

--- The rail's buttons a gamepad can stop on, top to bottom.
function CuesRail.buttons(self: any): { GuiObject }
	local list: { GuiObject } = { self.switch }
	if self.view ~= "Index" then
		table.insert(list, self.sort)
		if self.sell.Selectable then
			table.insert(list, self.sell)
		end
	end
	return list
end

return CuesRail
