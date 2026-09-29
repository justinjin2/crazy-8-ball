--!strict
-- UltOdds: the odds and the code box of the ult spin screen (docs/prompts/ULTIMATES_PROMPT.md
-- sections 8 and 9.3; reference 09). A "Lucky odds" switch, then one collapsible bar per rarity
-- in its colour ("Common 55%" and a chevron; Mythic shimmers). Opening a bar lists its ults
-- with each one's share, or "Soon" for a placeholder that cannot be rolled yet. The shares are
-- the true current odds from UltState (built ults only, empty rarities passing theirs down),
-- written as the case Odds panel writes them. Under the bars a line on pity, then the code box
-- ("USE CODE ULTS FOR FREE SPINS", "NEXT CODE AT 100 LIKES", a text box and Redeem through the
-- Rewards service's codes). Everything sits in one scroller: on a computer it is the screen's
-- right column over the dark stage; on a phone the screen puts it in its Odds popup.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local W = Strings.Ults.Screen
local CODES = Strings.Menus.Rewards
local RARITY_WORDS: { [string]: string } = Strings.Ults.Rarities :: any
local RARITIES: { string } = Config.Ults.Rarities
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local GOLD_HEX = "#" .. GOLD:ToHex()
local MAX_LENGTH: number = Config.Daily.CodeMaxLength

export type Hooks = {
	-- Send a code (the Rewards service); `done` gets the answer's words and a Kit colour.
	redeem: (text: string, done: (text: string, toneName: string) -> ()) -> (),
	-- Something opened or closed: the scroller's contents changed height.
	relayout: () -> (),
}

type Row = { frame: Frame, name: TextLabel, share: TextLabel }
type Bar = {
	rarity: string,
	button: TextButton,
	body: Frame,
	fill: Frame,
	edge: UIStroke,
	label: TextLabel,
	chevron: ImageLabel,
	list: Frame,
	rows: { Row },
	open: boolean,
	lit: boolean,
}

local UltOdds = {}
UltOdds.__index = UltOdds

--- The odds and the code box in a new scroller in `parent`.
function UltOdds.new(parent: Instance, hooks: Hooks): any
	local self: any = setmetatable({}, UltOdds)
	self.hooks = hooks
	self.lucky = false
	self.state = nil :: any
	self.bars = {} :: { Bar }
	self.onWhite = false -- drawn on a white card (the phone's popup), not the dark stage

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Odds"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = HudParts.tone("Soft")
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.Selectable = false
	scroll.ZIndex = 5
	scroll.Parent = parent
	self.scroll = scroll

	self.switch = Parts.switch(scroll, W.LuckyOdds, function(on: boolean)
		self.lucky = on
		if self.state then
			self:draw(self.state)
		end
	end)
	self.switch.button.ZIndex = 3

	for index, rarity in RARITIES do
		table.insert(self.bars, self:buildBar(scroll, rarity, index))
	end

	local pity = HudParts.text(scroll, "PityNote", C.Full.CodeNoteTextPx, "")
	pity.ZIndex = 3
	self.pityNote = pity

	self:buildCode(scroll)
	return self
end

function UltOdds.buildBar(self: any, parent: Instance, rarity: string, index: number): Bar
	local button = Instance.new("TextButton")
	button.Name = "Bar" .. rarity
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Selectable = true
	button.SelectionImageObject = Parts.noBox()
	button.LayoutOrder = index
	button.ZIndex = 3
	button.Parent = parent
	local body = HudParts.frame(button, "Body")
	body.Size = UDim2.fromScale(1, 1)
	local fill = HudParts.frame(body, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundTransparency = 0
	fill.ZIndex = 1
	HudParts.corner(fill, K.ButtonCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = K.ButtonStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = fill
	if rarity == "Mythic" then
		-- Mythic's pastels over deep space (UI_STYLE 4).
		local space = HudParts.frame(body, "Space")
		space.Size = UDim2.fromScale(1, 1)
		space.BackgroundTransparency = 0
		space.BackgroundColor3 = HudParts.color(K.MythicSpace)
		space.ZIndex = 0
		HudParts.corner(space, K.ButtonCornerPx)
		fill.BackgroundTransparency = 0.35
	end
	Parts.paint(fill, rarity)
	-- A candy shine on the top half.
	local shine = HudParts.frame(fill, "Shine")
	shine.BackgroundTransparency = 0.72
	shine.BackgroundColor3 = Color3.new(1, 1, 1)
	shine.Position = UDim2.fromScale(0.02, 0.08)
	shine.Size = UDim2.fromScale(0.96, 0.38)
	HudParts.corner(shine, K.ButtonCornerPx)
	local label = HudParts.text(body, "Words", C.Full.BarTextPx, "")
	label.AutoLocalize = false -- a rarity and a number, from Strings
	label.TextWrapped = false
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 3
	local chevron = HudParts.icon(body, "ChevronDown", "Chevron")
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.ZIndex = 3
	local list = HudParts.card(parent, "List" .. rarity, K.ButtonCornerPx)
	list.Visible = false
	list.ZIndex = 2
	local bar: Bar = {
		rarity = rarity,
		button = button,
		body = body,
		fill = fill,
		edge = edge,
		label = label,
		chevron = chevron,
		list = list,
		rows = {},
		open = false,
		lit = false,
	}
	for _, id in Catalog.byRarity(rarity) do
		local row = HudParts.frame(list, "Row" .. id)
		row.ZIndex = 3
		local name = HudParts.note(row, "Name", C.Full.RowTextPx, Catalog.name(id))
		name.TextWrapped = false
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.ZIndex = 4
		name:SetAttribute("UltId", id)
		local share = HudParts.note(row, "Share", C.Full.RowTextPx, "")
		share.AutoLocalize = false
		share.TextWrapped = false
		share.TextXAlignment = Enum.TextXAlignment.Right
		share.ZIndex = 4
		table.insert(bar.rows, { frame = row, name = name, share = share })
	end
	local function light(on: boolean)
		bar.lit = on
		edge.Color = if on then GOLD else INK
		edge.Thickness = if on then K.SelectedStrokePx else K.ButtonStrokePx
		UIAnim.sway(body, on, nil, button)
	end
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
		UISound.play("Click")
		bar.open = not bar.open
		self.hooks.relayout()
	end)
	return bar
end

function UltOdds.buildCode(self: any, parent: Instance)
	local card = HudParts.card(parent, "Code")
	card.ZIndex = 2
	self.codeCard = card
	local line = HudParts.text(card, "Line", C.Full.CodeTextPx, "")
	line.RichText = true
	line.ZIndex = 3
	local next = HudParts.note(card, "Next", C.Full.CodeNoteTextPx, "")
	next.RichText = true
	next.ZIndex = 3
	self.codeLine, self.nextLine = line, next

	local box = HudParts.frame(card, "Box")
	box.BackgroundTransparency = 0
	box.BackgroundColor3 = Color3.new(1, 1, 1)
	box.ClipsDescendants = true
	box.ZIndex = 3
	HudParts.corner(box, K.ButtonCornerPx)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = K.ButtonStrokePx - 1
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = box
	local hint = HudParts.note(box, "Hint", C.Full.CodeTextPx, CODES.CodeHint)
	hint.TextTransparency = 0.5
	hint.TextWrapped = false
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.ZIndex = 4
	local input = Instance.new("TextBox")
	input.Name = "Input"
	input.BackgroundTransparency = 1
	input.BorderSizePixel = 0
	input.Font = FONT
	input.TextColor3 = INK
	input.TextXAlignment = Enum.TextXAlignment.Left
	input.ClearTextOnFocus = false
	input.PlaceholderText = "" -- the hint is a label, so it can be translated
	input.Text = ""
	input.AutoLocalize = false -- what the player types
	input.Selectable = true
	input.SelectionImageObject = Parts.noBox()
	input.ZIndex = 5
	input.Parent = box
	self.box, self.boxStroke, self.hint, self.input = box, stroke, hint, input

	local redeem = HudParts.candy(card, CODES.Redeem, function()
		self:redeem()
	end, "Green")
	redeem.Name = "Redeem"
	redeem.ZIndex = 3
	HudParts.setMinHit(redeem, C.TouchPx)
	self.redeemButton = redeem
	input.NextSelectionRight = redeem
	redeem.NextSelectionLeft = input

	local answer = HudParts.text(card, "Answer", C.Full.CodeNoteTextPx, "")
	answer.ZIndex = 3
	answer.Visible = false
	self.answer = answer

	local lit = false
	local function light()
		local on = lit or input:IsFocused()
		stroke.Color = if on then GOLD else INK
		stroke.Thickness = if on then K.SelectedStrokePx else K.ButtonStrokePx - 1
	end
	input.SelectionGained:Connect(function()
		lit = true
		light()
	end)
	input.SelectionLost:Connect(function()
		lit = false
		light()
	end)
	input.Focused:Connect(light)
	input.FocusLost:Connect(function(enter: boolean)
		light()
		if enter then
			self:redeem()
		end
	end)
	-- A gamepad's A on the selected box starts typing (the console's keyboard comes up).
	input.InputBegan:Connect(function(object: InputObject)
		if object.KeyCode == Enum.KeyCode.ButtonA and not input:IsFocused() then
			task.defer(function()
				if input.Parent and not input:IsFocused() then
					input:CaptureFocus()
				end
			end)
		end
	end)
	input:GetPropertyChangedSignal("Text"):Connect(function()
		if #input.Text > MAX_LENGTH then
			input.Text = string.sub(input.Text, 1, MAX_LENGTH)
			return
		end
		hint.Visible = input.Text == ""
		if input.Text ~= "" and answer.Visible then
			answer.Visible = false
		end
	end)
end

function UltOdds.showAnswer(self: any, text: string, toneName: string)
	self.answer.Text = text
	self.answer.TextColor3 = HudParts.tone(toneName)
	self.answer.Visible = text ~= ""
end

--- Send the typed code (nothing typed: a reminder to type one).
function UltOdds.redeem(self: any)
	if self.redeeming then
		return
	end
	local text: string = self.input.Text
	UISound.play("Click")
	if string.match(text, "^%s*$") then
		self:showAnswer(CODES.NoCode, "Red")
		return
	end
	self.redeeming = true
	HudParts.setEnabled(self.redeemButton, false)
	self:showAnswer("", "Green")
	self.hooks.redeem(text, function(words: string, toneName: string)
		self.redeeming = false
		HudParts.setEnabled(self.redeemButton, true)
		self:showAnswer(words, toneName)
		if toneName == "Green" then
			self.input.Text = ""
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Drawing and layout
--------------------------------------------------------------------------------------------

--- Draw an UltState: the shares of the table the switch shows, the pity line, the code box.
function UltOdds.draw(self: any, state: any)
	self.state = state
	local odds = if type(state.odds) == "table" then state.odds else {}
	local tableOdds = if self.lucky then odds.lucky else odds.normal
	local rarities: { [string]: number } = {}
	local ults: { [string]: number } = {}
	if type(tableOdds) == "table" then
		for _, row in (if type(tableOdds.rarities) == "table" then tableOdds.rarities else {}) do
			if
				type(row) == "table"
				and type(row.rarity) == "string"
				and type(row.ppm) == "number"
			then
				rarities[row.rarity] = row.ppm
			end
		end
		for _, row in (if type(tableOdds.ults) == "table" then tableOdds.ults else {}) do
			if type(row) == "table" and type(row.id) == "string" and type(row.ppm) == "number" then
				ults[row.id] = row.ppm
			end
		end
	end
	for _, bar: Bar in self.bars do
		bar.label.Text = W.OddsBar:format(
			RARITY_WORDS[bar.rarity] or bar.rarity,
			Parts.percent(rarities[bar.rarity] or 0)
		)
		for _, row in bar.rows do
			local id = row.name:GetAttribute("UltId")
			local ppm = if type(id) == "string" then ults[id] else nil
			if ppm ~= nil then
				row.share.Text = Parts.percent(ppm)
				row.share.TextColor3 = INK
				row.name.TextTransparency = 0
			else
				row.share.Text = W.OddsSoon
				row.share.TextColor3 = HudParts.color(K.Buttons.Yellow.Lip)
				row.name.TextTransparency = C.PlaceholderTransparency
			end
		end
	end
	self.switch.set(self.lucky)
	local pityAt = if type(state.pityAt) == "number" then state.pityAt else Config.Ults.Roll.PityAt
	self.pityNote.Text = W.PityNote:format(pityAt)
	local code = if type(state.code) == "table" then state.code else {}
	local active = if type(code.active) == "string"
		then code.active
		else Config.Ults.CodeBanner.ActiveCode
	local likes = if type(code.nextGoalLikes) == "number"
		then code.nextGoalLikes
		else Config.Ults.CodeBanner.NextGoalLikes
	local gold = ('<font color="%s">%%s</font>'):format(GOLD_HEX)
	self.codeLine.Text = W.CodeLine:format(gold:format(active))
	self.nextLine.Text = W.NextCode:format(gold:format(tostring(likes)))
end

-- The height `text` wraps to at `size` in `width` (one line at least, `maxLines` at most).
local function wrapHeight(text: string, size: number, width: number, maxLines: number): number
	local plain = string.gsub(text, "<[^>]->", "")
	local one = Parts.textWidth(plain, size)
	local lines = math.clamp(math.ceil(one / math.max(1, width - 8)), 1, maxLines)
	return lines * (size + 4)
end

--- Lay the contents out `width` wide for layout `g` (onWhite: in the phone's white popup);
--- sets the scroller's canvas and returns the contents' height.
function UltOdds.layout(self: any, g: Parts.Geo, width: number, onWhite: boolean): number
	self.onWhite = onWhite
	local gap = g.px("BarGapPx")
	local barH = g.px("BarHeightPx")
	local barText = g.text("BarTextPx")
	local rowH = g.px("RowHeightPx")
	local rowText = g.text("RowTextPx")
	local inner = width - 8 -- room for the scroll bar and the outlines
	local x = 3
	local y = 3
	local switchH = g.px("SwitchHeightPx")
	local switch = self.switch.button
	HudParts.setButtonTextSize(switch, g.text("BarTextPx"))
	local switchW =
		math.min(inner, HudParts.candyWidth(switch, switchH, g.text("BarTextPx")) + switchH)
	switch.Position = UDim2.fromOffset(x + inner - switchW, y)
	switch.Size = UDim2.fromOffset(switchW, switchH)
	y += switchH + gap
	for _, bar: Bar in self.bars do
		bar.button.Position = UDim2.fromOffset(x, y)
		bar.button.Size = UDim2.fromOffset(inner, barH)
		HudParts.setTextSize(bar.label, barText)
		local pad = math.floor(barH * 0.3)
		bar.label.Position = UDim2.fromOffset(pad, 0)
		bar.label.Size = UDim2.fromOffset(math.max(1, inner - 2 * pad - barH), barH)
		local chevron = math.floor(barH * 0.6)
		bar.chevron.Size = UDim2.fromOffset(chevron, chevron)
		bar.chevron.Position = UDim2.fromOffset(inner - pad, math.floor(barH / 2))
		bar.chevron.Rotation = if bar.open then 180 else 0
		y += barH
		if bar.open and #bar.rows > 0 then
			local listPad = math.max(4, math.floor(rowH * 0.2))
			local listH = #bar.rows * rowH + 2 * listPad
			bar.list.Position = UDim2.fromOffset(x + pad, y + 4)
			bar.list.Size = UDim2.fromOffset(inner - 2 * pad, listH)
			for index, row in bar.rows do
				row.frame.Position = UDim2.fromOffset(listPad, listPad + (index - 1) * rowH)
				row.frame.Size = UDim2.fromOffset(inner - 2 * pad - 2 * listPad, rowH)
				HudParts.setTextSize(row.name, rowText)
				HudParts.setTextSize(row.share, rowText)
				local shareW = math.ceil(Parts.textWidth(row.share.Text, rowText)) + 8
				row.share.Position = UDim2.new(1, -shareW, 0, 0)
				row.share.Size = UDim2.fromOffset(shareW, rowH)
				row.name.Size = UDim2.new(1, -shareW - 4, 1, 0)
			end
			bar.list.Visible = true
			y += listH + 8
		else
			bar.list.Visible = false
		end
		y += gap
	end
	-- The pity line: soft white on the dark stage, ink on the white popup.
	local noteText = g.text("CodeNoteTextPx")
	HudParts.setTextSize(self.pityNote, noteText)
	self.pityNote.TextColor3 = if onWhite then INK else HudParts.tone("Soft")
	local pityH = wrapHeight(self.pityNote.Text, noteText, inner, 3)
	self.pityNote.Position = UDim2.fromOffset(x, y)
	self.pityNote.Size = UDim2.fromOffset(inner, pityH)
	y += pityH + gap

	-- The code box card.
	local pad = g.px("GapPx")
	local codeText = g.text("CodeTextPx")
	local cardInner = inner - 2 * pad
	local cy = pad
	HudParts.setTextSize(self.codeLine, codeText)
	local lineH = wrapHeight(self.codeLine.Text, codeText, cardInner, 2)
	self.codeLine.Position = UDim2.fromOffset(pad, cy)
	self.codeLine.Size = UDim2.fromOffset(cardInner, lineH)
	cy += lineH + 2
	HudParts.setTextSize(self.nextLine, noteText)
	local nextH = wrapHeight(self.nextLine.Text, noteText, cardInner, 2)
	self.nextLine.Position = UDim2.fromOffset(pad, cy)
	self.nextLine.Size = UDim2.fromOffset(cardInner, nextH)
	cy += nextH + pad
	local boxH = g.px("CodeBoxPx")
	local redeemW = math.min(g.px("RedeemWidthPx"), math.floor(cardInner * 0.4))
	local boxW = math.max(1, cardInner - redeemW - pad)
	self.box.Position = UDim2.fromOffset(pad, cy)
	self.box.Size = UDim2.fromOffset(boxW, boxH)
	local inset = math.max(6, math.floor(boxH * 0.22))
	self.input.TextSize = codeText
	self.input.Position = UDim2.fromOffset(inset, 0)
	self.input.Size = UDim2.fromOffset(math.max(1, boxW - 2 * inset), boxH)
	HudParts.setTextSize(self.hint, codeText)
	self.hint.Position = UDim2.fromOffset(inset, 0)
	self.hint.Size = UDim2.fromOffset(math.max(1, boxW - 2 * inset), boxH)
	self.redeemButton.Position = UDim2.fromOffset(pad + boxW + pad, cy)
	self.redeemButton.Size = UDim2.fromOffset(redeemW, boxH)
	HudParts.setButtonTextSize(self.redeemButton, g.text("CodeTextPx"))
	cy += boxH + 4
	HudParts.setTextSize(self.answer, noteText)
	self.answer.Position = UDim2.fromOffset(pad, cy)
	self.answer.Size = UDim2.fromOffset(cardInner, 2 * (noteText + 4))
	cy += 2 * (noteText + 4) + pad
	self.codeCard.Position = UDim2.fromOffset(x, y)
	self.codeCard.Size = UDim2.fromOffset(inner, cy)
	y += cy + 6
	self.scroll.CanvasSize = UDim2.fromOffset(0, y)
	return y
end

--- The gamepad's way in: the Lucky odds switch.
function UltOdds.first(self: any): GuiObject
	return self.switch.button
end

--- Put a gamepad on the first bar.
function UltOdds.focus(self: any)
	GuiService.SelectedObject = self.switch.button
end

return UltOdds
