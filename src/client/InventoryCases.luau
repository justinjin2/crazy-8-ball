--!strict
-- InventoryCases: the Inventory's Cases tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11).
--
--   * A line on top ("Open a case to win a cue!") and "Buy more", which jumps to the Shop's
--     Cases tab (Menus.open("Shop", "Cases")).
--   * A row per case type owned, in shop order as the snapshot sends them: the case's chest
--     (Config.UI.Kit.Icons CaseStandard ... CaseEvent), its name and "x4", then Open (one, on
--     CaseOpening's reel) and, for Fast Open owners (the player's FastOpen attribute) holding
--     at least Config.Cases.FastOpenCount, "Open 10" (CaseOpening's grid).
--   * No cases: the chest, a friendly line and Buy more, in the middle of the page.
--
-- The case opening (deps.caseOpening) asks the server and draws the result over this menu;
-- this page only starts it, and the rows redraw from the snapshot that follows.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)

local I = Config.UI.Inventory
local SC = Config.UI.Menu.Scroll
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local ICONS: { [string]: string } = K.Icons :: any
local CASES: { [string]: any } = Config.Cases.List :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local MANY = Config.Cases.FastOpenCount

type Row = {
	caseId: string,
	box: Frame,
	icon: ImageLabel,
	name: TextLabel,
	count: TextLabel,
	open: TextButton,
	openMany: TextButton,
}

local InventoryCases = {}
InventoryCases.__index = InventoryCases

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

local function textHeight(text: string, size: number, width: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(math.max(1, width), 4000)).Y
end

-- The case's chest icon key: "CaseRare", or the plain chest for a case with no icon of its own.
local function iconKey(caseId: string): string
	local key = "Case" .. caseId
	return if type(ICONS[key]) == "string" and ICONS[key] ~= "" then key else "Case"
end

local function fastOpen(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("FastOpen") == true
end

-- The snapshot's cases ({ id, count }), only known case types with at least one.
local function ownedCases(items: any): { any }
	local rows = {}
	local cases = if type(items) == "table" then items.cases else nil
	if type(cases) ~= "table" then
		return rows
	end
	for _, row in cases do
		if
			type(row) == "table"
			and type(row.id) == "string"
			and CASES[row.id] ~= nil
			and type(row.count) == "number"
			and row.count > 0
		then
			table.insert(rows, row)
		end
	end
	return rows
end

--- The Cases page, built into `page`. `ctx`: InventoryMenu's.
function InventoryCases.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, InventoryCases)
	self.page = page
	self.ctx = ctx
	self.rows = {} :: { [string]: Row }
	self.order = {} :: { string }
	self.geo = nil :: MenuFrame.Geo?

	local function jump()
		Menus.open("Shop", "Cases")
	end

	-- The top line and Buy more.
	local top = HudParts.frame(page, "Top")
	top.ZIndex = 2
	self.top = top
	self.hint = HudParts.note(top, "Hint", I.HintTextPx[2], WORDS.CasesHint)
	self.hint.TextXAlignment = Enum.TextXAlignment.Left
	self.hint.ZIndex = 2
	self.buyMore = HudParts.candy(top, WORDS.BuyMore, jump, "Blue", "Shop")
	self.buyMore.Name = "BuyMore"
	self.buyMore.ZIndex = 2
	HudParts.setMinHit(self.buyMore, TOUCH)

	-- The rows.
	local holder = HudParts.frame(page, "ListHolder")
	holder.ZIndex = 2
	self.holder = holder
	local scroll, _ = MenuFrame.scroller(holder, { name = "Cases" })
	self.scroll = scroll

	-- The empty state: the chest, a line, Buy more.
	local empty = HudParts.frame(page, "Empty")
	empty.ZIndex = 2
	empty.Visible = false
	self.empty = empty
	self.emptyIcon = HudParts.icon(empty, "CaseStandard", "Chest")
	self.emptyIcon.ZIndex = 2
	self.emptyLine = HudParts.note(empty, "Line", I.EmptyTextPx[2], WORDS.CasesEmpty)
	self.emptyLine.ZIndex = 2
	self.emptyBuy = HudParts.candy(empty, WORDS.BuyMore, jump, "Blue", "Shop")
	self.emptyBuy.Name = "BuyMore"
	self.emptyBuy.ZIndex = 2
	HudParts.setMinHit(self.emptyBuy, TOUCH)

	self.loading = MenuFrame.placeholder(page)

	local player = Players.LocalPlayer
	if player then
		-- Open 10 comes and goes with Fast Open.
		player:GetAttributeChangedSignal("FastOpen"):Connect(function()
			if ctx.isOpen() then
				self:redraw(ctx.lastItems)
			end
		end)
	end
	return self
end

function InventoryCases.buildRow(self: any, caseId: string): Row
	local box = InventoryCard.box(self.scroll, "Case" .. caseId)
	box.ZIndex = 2
	local icon = HudParts.icon(box, iconKey(caseId), "Chest")
	icon.ZIndex = 3
	local name = HudParts.text(box, "Name", I.CaseNameTextPx[2], CASE_NAMES[caseId] or caseId)
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local count = HudParts.note(box, "Count", I.CaseCountTextPx[2], "")
	count.TextWrapped = false
	count.TextXAlignment = Enum.TextXAlignment.Left
	count.ZIndex = 3
	local open = HudParts.candy(box, WORDS.Open, function()
		self:openCases(caseId, 1, self.rows[caseId].open)
	end, "Green")
	open.Name = "Open"
	open.ZIndex = 3
	HudParts.setMinHit(open, TOUCH)
	local openMany = HudParts.candy(box, WORDS.OpenMany:format(tostring(MANY)), function()
		self:openCases(caseId, MANY, self.rows[caseId].openMany)
	end, "Yellow", "FastOpen")
	openMany.Name = "OpenMany"
	openMany.ZIndex = 3
	HudParts.setMinHit(openMany, TOUCH)
	return {
		caseId = caseId,
		box = box,
		icon = icon,
		name = name,
		count = count,
		open = open,
		openMany = openMany,
	}
end

--- The tab's red dot: every unopened case.
function InventoryCases.dot(_self: any, items: any): number
	local total = 0
	for _, row in ownedCases(items) do
		total += math.floor(row.count)
	end
	return total
end

--- Redraw from the snapshot (nil before the first: "Loading...").
function InventoryCases.redraw(self: any, items: any)
	local ctx = self.ctx
	local loaded = type(items) == "table"
	self.loading.Visible = not loaded
	if not loaded then
		self.top.Visible, self.holder.Visible, self.empty.Visible = false, false, false
		return
	end
	local owned = ownedCases(items)
	local keep: { [string]: boolean } = {}
	local order = {}
	local fast = fastOpen()
	for index, entry in owned do
		local caseId: string = entry.id
		keep[caseId] = true
		table.insert(order, caseId)
		local row: Row = self.rows[caseId] or self:buildRow(caseId)
		self.rows[caseId] = row
		row.box.LayoutOrder = index
		row.count.Text = WORDS.Count:format(Format.commas(entry.count))
		row.openMany.Visible = fast and entry.count >= MANY
		HudParts.setEnabled(row.open, not ctx.isHeld(row.open))
		HudParts.setEnabled(row.openMany, not ctx.isHeld(row.openMany))
	end
	for caseId, row in self.rows do
		if not keep[caseId] then
			row.box:Destroy()
			self.rows[caseId] = nil
		end
	end
	self.order = order
	local any = #order > 0
	self.top.Visible = any
	self.holder.Visible = any
	self.empty.Visible = not any
	self:arrange()
end

--- Open cases on the reel (or Fast Open's grid): CaseOpening asks the server and shows it.
function InventoryCases.openCases(self: any, caseId: string, count: number, button: TextButton)
	local ctx = self.ctx
	local opening = ctx.deps.caseOpening
	if not opening or opening:isOpen() then
		return
	end
	ctx.hold(button, function()
		opening:open(caseId, count)
	end)
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

function InventoryCases.layout(self: any, geo: MenuFrame.Geo)
	self.geo = geo
	self:arrange()
end

function InventoryCases.arrange(self: any)
	local geo: MenuFrame.Geo? = self.geo
	if not geo then
		return
	end
	local span = self.ctx.span
	local W, H = geo.content.X, geo.content.Y
	local gap = span(I.GapPx)
	local buttonH = span(I.CaseButtonPx)
	local buttonText = span(I.CaseButtonTextPx)

	-- The top: the line, and Buy more at the right.
	local buyW =
		math.max(span(I.BuyMoreWidthPx), self:buttonWidth(WORDS.BuyMore, buttonH, buttonText, true))
	self.top.Position = UDim2.fromOffset(0, 0)
	self.top.Size = UDim2.fromOffset(W, buttonH)
	self.buyMore.AnchorPoint = Vector2.new(1, 0)
	self.buyMore.Position = UDim2.fromOffset(W - SC.PadPx, 0)
	self.buyMore.Size = UDim2.fromOffset(buyW, buttonH)
	HudParts.setButtonTextSize(self.buyMore, buttonText)
	HudParts.setTextSize(self.hint, span(I.HintTextPx))
	self.hint.Position = UDim2.fromOffset(SC.PadPx, 0)
	self.hint.Size = UDim2.fromOffset(math.max(1, W - buyW - 2 * SC.PadPx - gap), buttonH)
	self.holder.Position = UDim2.fromOffset(0, buttonH + gap)
	self.holder.Size = UDim2.fromOffset(W, math.max(1, H - buttonH - gap))

	-- A row: the chest, the name over "x4", then Open 10 and Open at the right.
	local rowW = W - 2 * SC.PadPx - SC.BarPx
	local rowH = span(I.CaseRowPx)
	local pad = math.max(4, round(rowH * I.CaseRowPadShare))
	local iconS = round(rowH * I.CaseIconShare)
	local nameText, countText = span(I.CaseNameTextPx), span(I.CaseCountTextPx)
	local openW = span(I.CaseButtonWidthPx)
	local rowButtonH = math.min(buttonH, rowH - 2 * pad)
	for _, row in self.rows do
		row.box.Size = UDim2.fromOffset(rowW, rowH)
		row.icon.Size = UDim2.fromOffset(iconS, iconS)
		row.icon.Position = UDim2.fromOffset(pad, round((rowH - iconS) / 2))
		local right = rowW - pad
		for _, button in { row.open, row.openMany } do
			if button.Visible then
				local words = HudParts.candyParts(button)
				local text = if words then words.label.Text else ""
				local width = math.max(
					openW,
					self:buttonWidth(text, rowButtonH, buttonText, button == row.openMany)
				)
				button.Position = UDim2.fromOffset(right - width, round((rowH - rowButtonH) / 2))
				button.Size = UDim2.fromOffset(width, rowButtonH)
				HudParts.setButtonTextSize(button, buttonText)
				right -= width + gap
			end
		end
		local x = pad + iconS + gap
		local wordsW = math.max(1, right - x)
		local nameH = nameText + 6
		local countH = countText + 4
		local y = round((rowH - nameH - countH) / 2)
		HudParts.setTextSize(row.name, nameText)
		HudParts.setTextSize(row.count, countText)
		row.name.Position = UDim2.fromOffset(x, y)
		row.name.Size = UDim2.fromOffset(wordsW, nameH)
		row.count.Position = UDim2.fromOffset(x, y + nameH)
		row.count.Size = UDim2.fromOffset(wordsW, countH)
	end

	-- The empty state, centred: the chest, the line, Buy more.
	local iconPx = span(I.EmptyIconPx)
	local lineText = span(I.EmptyTextPx)
	local lineW = math.min(W - 2 * SC.PadPx, I.EmptyLineMaxPx)
	HudParts.setTextSize(self.emptyLine, lineText)
	local lineH = math.ceil(textHeight(self.emptyLine.Text, lineText, lineW - 4)) + 6
	local total = iconPx + gap + lineH + gap + buttonH
	local y = math.max(0, round((H - total) / 2))
	self.empty.Position = UDim2.fromOffset(0, 0)
	self.empty.Size = UDim2.fromOffset(W, H)
	self.emptyIcon.Position = UDim2.fromOffset(round((W - iconPx) / 2), y)
	self.emptyIcon.Size = UDim2.fromOffset(iconPx, iconPx)
	self.emptyLine.Position = UDim2.fromOffset(round((W - lineW) / 2), y + iconPx + gap)
	self.emptyLine.Size = UDim2.fromOffset(lineW, lineH)
	self.emptyBuy.Position = UDim2.fromOffset(round((W - buyW) / 2), y + iconPx + gap + lineH + gap)
	self.emptyBuy.Size = UDim2.fromOffset(buyW, buttonH)
	HudParts.setButtonTextSize(self.emptyBuy, buttonText)
end

-- A candy's natural width for its words at this height and text size (as the kit lays it
-- out), with room for an icon.
function InventoryCases.buttonWidth(
	_self: any,
	text: string,
	height: number,
	size: number,
	icon: boolean
): number
	local usable = height - math.floor(height * K.ButtonLipShare + 0.5)
	local pad = math.max(6, math.floor(usable * 0.18))
	local left = if icon
		then pad + math.floor(usable * K.ButtonIconShare) + math.floor(pad / 2)
		else pad
	return left + math.ceil(textWidth(text, size)) + 6 + pad
end

--------------------------------------------------------------------------------------------
-- The tab showing
--------------------------------------------------------------------------------------------

function InventoryCases.opened(_self: any) end

function InventoryCases.shown(_self: any) end

function InventoryCases.hidden(_self: any) end

function InventoryCases.closed(_self: any) end

--- Where a gamepad starts on this page: the first case's Open, else Buy more.
function InventoryCases.first(self: any): GuiObject?
	local firstId = self.order[1]
	local row: Row? = if firstId then self.rows[firstId] else nil
	if row and row.open.Selectable then
		return row.open
	end
	if self.empty.Visible then
		return self.emptyBuy
	end
	return self.buyMore
end

return InventoryCases
