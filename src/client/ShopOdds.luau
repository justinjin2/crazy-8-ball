--!strict
-- ShopOdds: a case's odds (ECONOMY 7.3; docs/prompts/ECONOMY_UI_PROMPT.md section 11), opened
-- by the "Odds" button on a Shop case card. Every cue the case can drop with its %, grouped by
-- rarity from the bottom one up (each group's heading gives the rarity's own %), a line saying
-- every cue of a rarity has the same chance, and the total, exactly 100%. The numbers come
-- straight from Cases.odds and Cases.cueOdds, so vaulting a cue updates the list at once.
--
-- A kit card over the Shop's pages (not a separate screen: no dim, UI_STYLE 2), with the case's
-- chest, "Standard Case odds" and a red X. It closes with the X, B, Escape, a tab change or the
-- menu closing (it is one of the frame's dialogs, so LB and RB wait while it is up). Gamepad:
-- the X is selected on open and every cue row can be selected, so the D-pad walks (and
-- scrolls) the list; the selection goes back to the Odds button on close.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Cases = require(Shared:WaitForChild("Progression"):WaitForChild("Cases"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local O = Config.UI.Shop.Odds
local K = Config.UI.Kit
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local ACTION = "8ballShopOddsClose"
-- Over the menus' B (High + 20) and LB/RB, like MenuFrame's confirm dialog.
local PRIORITY = Enum.ContextActionPriority.High.Value + 30
local span = ShopParts.span
local round = ShopParts.round

type Row = {
	button: TextButton, -- a selectable row (nothing happens on press: it is for reading)
	edge: UIStroke,
	thumb: Frame,
	name: TextLabel,
	percent: TextLabel,
}

type Group = {
	title: TextLabel, -- the rarity's name, in its colour
	percent: TextLabel, -- the rarity's %
	rows: { Row },
}

local ShopOdds = {}
ShopOdds.__index = ShopOdds

-- An empty selection box: the rows light their own gold edge.
local function noBox(): Frame
	local box = Instance.new("Frame")
	box.BackgroundTransparency = 1
	box.BorderSizePixel = 0
	return box
end

--- The odds panel (closed) over `frame`'s pages. `shop` is the ShopMenu.
function ShopOdds.new(shop: any, frame: any): any
	local self: any = setmetatable({}, ShopOdds)
	self.shop = shop
	self.frame = frame
	self.caseId = nil :: string?
	self.opened = false
	self.groups = {} :: { Group }
	self.escape = nil :: RBXScriptConnection?
	self.watch = nil :: RBXScriptConnection?
	self.previous = nil :: GuiObject?

	-- A clear layer over the pages that swallows presses; the card fills it.
	local layer = Instance.new("TextButton")
	layer.Name = "Odds"
	layer.Text = ""
	layer.AutoButtonColor = false
	layer.Selectable = false
	layer.BackgroundTransparency = 1
	layer.BorderSizePixel = 0
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = O.ZIndex
	layer.Visible = false
	layer.Parent = frame.content
	self.layer = layer
	local card = HudParts.card(layer, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	card.ZIndex = 2
	card.SelectionGroup = true
	card.SelectionBehaviorUp = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorDown = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorLeft = Enum.SelectionBehavior.Stop
	card.SelectionBehaviorRight = Enum.SelectionBehavior.Stop
	self.card = card

	local icon = HudParts.icon(card, "CaseStandard", "Chest")
	icon.ZIndex = 3
	self.icon = icon
	local title = HudParts.text(card, "Title", O.TitleTextPx[2], "")
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.title = title
	local close = HudParts.candy(card, "", function()
		UISound.play("Click")
		self:close()
	end, "Red", "X")
	close.Name = "Close"
	close.ZIndex = 3
	HudParts.setMinHit(close, Config.UI.Menu.Frame.TouchMinPx)
	self.closeButton = close
	local note = HudParts.note(card, "Note", Config.UI.Shop.LineTextPx[1], COPY.OddsNote)
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.ZIndex = 3
	self.note = note
	local total = HudParts.text(card, "Total", Config.UI.Shop.NameTextPx[1], "")
	total.AutoLocalize = false
	total.TextWrapped = false
	total.TextXAlignment = Enum.TextXAlignment.Right
	total.ZIndex = 3
	self.total = total
	local scroll = ShopParts.scroller(card, "List")
	scroll.ZIndex = 3
	self.scroll = scroll
	return self
end

function ShopOdds.isOpen(self: any): boolean
	return self.opened
end

-- Build the list for a case: a heading per rarity, a row per cue.
function ShopOdds.fill(self: any, caseId: string)
	for _, child in self.scroll:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local groups: { Group } = {}
	local byRarity: { [string]: Group } = {}
	for _, entry in Cases.odds(caseId) do
		local tint = CueThumb.accentColor(entry.rarity)
		local heading =
			HudParts.text(self.scroll, "Rarity" .. entry.rarity, O.HeadingTextPx[1], "", tint)
		heading.Text = CueThumb.rarityName(entry.rarity)
		heading.TextWrapped = false
		heading.TextXAlignment = Enum.TextXAlignment.Left
		heading.ZIndex = 4
		local percent = HudParts.text(
			self.scroll,
			"Percent" .. entry.rarity,
			O.HeadingTextPx[1],
			entry.display,
			tint
		)
		percent.AutoLocalize = false
		percent.TextWrapped = false
		percent.TextXAlignment = Enum.TextXAlignment.Right
		percent.ZIndex = 4
		local group: Group = { title = heading, percent = percent, rows = {} }
		byRarity[entry.rarity] = group
		table.insert(groups, group)
	end
	for _, cue in Cases.cueOdds(caseId) do
		local group = byRarity[cue.rarity]
		if group then
			table.insert(group.rows, self:row(cue.id, cue.rarity, cue.display))
		end
	end
	self.groups = groups
	-- Every rarity's weight adds to exactly OddsTotal, so this reads "100%".
	local weight = 0
	for _, entry in Cases.odds(caseId) do
		weight += entry.weight
	end
	self.total.Text =
		COPY.OddsTotal:format(Cases.percentText(weight * 100 / Config.Cases.OddsTotal))
end

-- One cue's row: its thumbnail, name and %.
function ShopOdds.row(self: any, cueId: string, rarity: string, display: string): Row
	local button = Instance.new("TextButton")
	button.Name = "Cue" .. cueId
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundTransparency = 0
	button.BackgroundColor3 = HudParts.tone("White")
	button.Selectable = true
	button.SelectionImageObject = noBox()
	button.ZIndex = 4
	HudParts.corner(button, O.RowCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = CueThumb.accentColor(rarity)
	edge.Thickness = O.RowStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	button.SelectionGained:Connect(function()
		edge.Color = HudParts.tone("Gold")
		edge.Thickness = K.SelectedStrokePx
	end)
	button.SelectionLost:Connect(function()
		edge.Color = CueThumb.accentColor(rarity)
		edge.Thickness = O.RowStrokePx
	end)
	local thumb = CueThumb.new(button, cueId)
	thumb.ZIndex = 5 -- its layers keep their own order inside it (Sibling ZIndex)
	local name = HudParts.note(button, "Name", O.RowTextPx[1], CueThumb.cueName(cueId))
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 5
	local percent = HudParts.note(button, "Percent", O.RowTextPx[1], display)
	percent.AutoLocalize = false
	percent.TextWrapped = false
	percent.TextXAlignment = Enum.TextXAlignment.Right
	percent.ZIndex = 5
	button.Parent = self.scroll
	return { button = button, edge = edge, thumb = thumb, name = name, percent = percent }
end

--- Lay the panel out over the pages at these sizes.
function ShopOdds.layout(self: any, s: ShopParts.Sizes)
	if not self.opened then
		return
	end
	local size = self.layer.AbsoluteSize / ShopParts.scaleOf(self.layer)
	if size.X < 1 or size.Y < 1 then
		return
	end
	local t = s.t
	local pad = s.pad
	local w, h = size.X, size.Y
	local headerH = math.max(Config.UI.Menu.Frame.TouchMinPx, span(O.HeaderPx, t))
	local titleSize = math.max(K.Text.Min, span(O.TitleTextPx, t))
	local closeSize = math.min(headerH, O.CloseMaxPx)
	self.closeButton.AnchorPoint = Vector2.new(1, 0.5)
	self.closeButton.Size = UDim2.fromOffset(closeSize, closeSize)
	self.closeButton.Position = UDim2.fromOffset(w - pad, pad + round(headerH / 2))
	self.icon.Size = UDim2.fromOffset(headerH, headerH)
	self.icon.Position = UDim2.fromOffset(pad, pad)
	HudParts.setTextSize(self.title, titleSize)
	local titleX = pad + headerH + s.gap
	self.title.Position = UDim2.fromOffset(titleX, pad)
	self.title.Size = UDim2.fromOffset(math.max(1, w - titleX - closeSize - s.gap - pad), headerH)

	local lineH = s.line + 4
	HudParts.setTextSize(self.note, s.line)
	self.note.Position = UDim2.fromOffset(pad, pad + headerH)
	self.note.Size = UDim2.fromOffset(w - 2 * pad, lineH)
	local totalH = s.name + 8
	HudParts.setTextSize(self.total, s.name)
	self.total.Position = UDim2.fromOffset(pad, h - pad - totalH)
	self.total.Size = UDim2.fromOffset(w - 2 * pad, totalH)
	local listTop = pad + headerH + lineH + round(s.lineGap / 2)
	self.scroll.Position = UDim2.fromOffset(pad, listTop)
	self.scroll.Size = UDim2.fromOffset(w - 2 * pad, math.max(1, h - listTop - totalH - pad))

	-- The list: a heading, then the rarity's cues in as many columns as keep a row wide enough.
	local innerW = w - 2 * pad - Config.UI.Shop.ScrollBarPx - 2 * s.scrollPad
	local rowH = span(O.RowPx, t)
	local rowText = math.max(K.Text.Min, span(O.RowTextPx, t))
	local headingText = math.max(K.Text.Min, span(O.HeadingTextPx, t))
	local headingH = headingText + 8
	local cols = math.max(1, math.floor((innerW + s.gap) / (O.RowMinWidthPx + s.gap)))
	local cellW = math.floor((innerW - (cols - 1) * s.gap) / cols)
	local y = s.scrollPad
	local x0 = s.scrollPad
	for _, group in self.groups :: { Group } do
		HudParts.setTextSize(group.title, headingText)
		HudParts.setTextSize(group.percent, headingText)
		group.title.Position = UDim2.fromOffset(x0, y)
		group.title.Size = UDim2.fromOffset(round(innerW * 0.7), headingH)
		group.percent.Position = UDim2.fromOffset(x0 + innerW - round(innerW * 0.3), y)
		group.percent.Size = UDim2.fromOffset(round(innerW * 0.3), headingH)
		y += headingH + round(s.lineGap / 2)
		for index, row in group.rows do
			local col = (index - 1) % cols
			local line = (index - 1) // cols
			local rx = x0 + col * (cellW + s.gap)
			local ry = y + line * (rowH + s.lineGap)
			row.button.Position = UDim2.fromOffset(rx, ry)
			row.button.Size = UDim2.fromOffset(cellW, rowH)
			local thumbSize = rowH - 4
			row.thumb.Size = UDim2.fromOffset(thumbSize, thumbSize)
			row.thumb.Position = UDim2.fromOffset(4, 2)
			HudParts.setTextSize(row.name, rowText)
			HudParts.setTextSize(row.percent, rowText)
			local percentW = math.ceil(ShopParts.textWidth(row.percent.Text, rowText)) + 8
			row.percent.Position = UDim2.fromOffset(cellW - percentW - 8, 0)
			row.percent.Size = UDim2.fromOffset(percentW, rowH)
			local nameX = thumbSize + 10
			row.name.Position = UDim2.fromOffset(nameX, 0)
			row.name.Size = UDim2.fromOffset(math.max(1, cellW - nameX - percentW - 12), rowH)
		end
		local lines = math.ceil(#group.rows / cols)
		y += lines * (rowH + s.lineGap) + s.gap
	end
	ShopParts.setCanvas(self.scroll, y + s.scrollPad)
end

--- Open the odds of `caseId` (over whatever tab shows).
function ShopOdds.open(self: any, caseId: string)
	if self.opened and self.caseId == caseId then
		return
	end
	local frame = self.frame
	local wasOpen = self.opened
	self.caseId = caseId
	self:fill(caseId)
	HudParts.setIcon(self.icon, "Case" .. caseId)
	self.title.Text = COPY.OddsTitle:format(CASE_NAMES[caseId] or caseId)
	self.opened = true
	self.layer.Visible = true
	self.scroll.CanvasPosition = Vector2.zero
	if not wasOpen then
		self.previous = GuiService.SelectedObject
		UIAnim.popIn(self.card)
		self.dialog = {
			cancel = function()
				self:close()
			end,
			isOpen = function(): boolean
				return self.opened
			end,
		}
		table.insert(frame.dialogs, self.dialog)
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, state: Enum.UserInputState, _input: InputObject)
				if state == Enum.UserInputState.Begin then
					self:close()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			PRIORITY,
			Enum.KeyCode.ButtonB
		)
		self.escape = UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				Menus.swallowEscape(input) -- the Shop stays open
				self:close()
			end
		end)
		-- A gamepad picked up while it is open lands on its X.
		self.watch = UserInputService.LastInputTypeChanged:Connect(function()
			if ShopParts.gamepad() then
				local selected = GuiService.SelectedObject
				if selected == nil or not selected:IsDescendantOf(self.card) then
					GuiService.SelectedObject = self.closeButton
				end
			end
		end)
	end
	self:layout(self.shop.sizes)
	-- Once the layer has its size (the first open's AbsoluteSize may still be settling).
	task.defer(function()
		if self.opened then
			self:layout(self.shop.sizes)
		end
	end)
	if ShopParts.gamepad() then
		GuiService.SelectedObject = self.closeButton
	end
end

--- Close it (nothing happens if it is closed). The selection goes back to the Odds button.
function ShopOdds.close(self: any)
	if not self.opened then
		return
	end
	self.opened = false
	local frame = self.frame
	local at = table.find(frame.dialogs, self.dialog)
	if at then
		table.remove(frame.dialogs, at)
	end
	ContextActionService:UnbindAction(ACTION)
	if self.escape then
		self.escape:Disconnect()
		self.escape = nil
	end
	if self.watch then
		self.watch:Disconnect()
		self.watch = nil
	end
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(self.layer) then
		local previous = self.previous
		if previous and previous:IsDescendantOf(game) and frame:isOpen() then
			GuiService.SelectedObject = previous
		else
			GuiService.SelectedObject = nil
		end
	end
	self.previous = nil
	UIAnim.popOut(self.card, function()
		if not self.opened then
			self.layer.Visible = false
		end
	end)
end

return ShopOdds
