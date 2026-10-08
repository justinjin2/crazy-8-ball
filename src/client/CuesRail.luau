--!strict
-- CuesRail: the tiles outside the Cues menu's right edge (docs/prompts/CUES_LIVELY_PROMPT.md,
-- concept 2, approved round 2; the switch split in two, designer 2026-10-08), top to bottom,
-- all the same size and evenly spaced:
--   * My Cues and Index: the two places, like the Shop's jump buttons: the one you are in is
--     blue with its icon rocking gently, the other white. Each wears its red dot: the NEW
--     count on My Cues, "!" on the Index while a row can be claimed.
--   * Sort: the grid's next order, the order's name hanging under it in a blue pill;
--   * Sell dupes: every duplicate sold (it asks first), the money it would pay hanging under
--     it in a gold pill; greyed out at nothing to sell.
-- Sort and Sell dupes step aside while the Index shows. Built in the panel (so a gamepad
-- reaches them) like the Shop's jump buttons: outside the panel's right edge when the screen
-- has room, else a column inside the page's right side. Sizes in Config.UI.Inventory.Rail,
-- words in Strings.Menus.Inventory and Strings.Menus.Tabs.Inventory.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local R = Config.UI.Inventory.Rail
local K = Config.UI.Kit
local L = Config.UI.Menu.Lively
local WORDS = Strings.Menus.Inventory
local VIEW_WORDS: { [string]: string } = Strings.Menus.Tabs.Inventory :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local VIEWS = { "Cues", "Index" }

export type Actions = {
	view: (key: string) -> (), -- My Cues or Index pressed
	sort: () -> (),
	sell: () -> (),
}

type Tab = { button: TextButton, dot: Frame, dotText: TextLabel }

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

--- The icon key the Cues menu shows for My Cues: the CUES icon (concept 2b, 2026-10-08; the
--- backpack only if its picture were missing).
function CuesRail.cuesIcon(): string
	local id = (K.Icons :: any).Cues
	return if type(id) == "string" and id ~= "" then "Cues" else "Inventory"
end

-- A red dot with a word ("3", "9+", "!") on a tile's top-right corner.
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
	self.rock = nil :: UIAnim.Handle?

	local holder = HudParts.frame(frame.panel, "Rail")
	holder.ZIndex = 4
	self.holder = holder

	-- My Cues and Index.
	self.tabs = {} :: { [string]: Tab }
	for _, key in VIEWS do
		local icon = if key == "Cues" then CuesRail.cuesIcon() else "Index"
		local button = HudParts.tile(holder, VIEW_WORDS[key] or key, function()
			actions.view(key)
		end, if key == self.view then "Blue" else "White", icon)
		button.Name = "Tab" .. key
		local dot, dotText = redDot(button)
		self.tabs[key] = { button = button, dot = dot, dotText = dotText }
	end

	-- Sort and Sell dupes, each with its hanging pill.
	self.sort = HudParts.tile(holder, WORDS.SortTile, function()
		UISound.play("Click")
		actions.sort()
	end, "White", "Sliders")
	self.sort.Name = "Sort"
	self.sortHang, self.sortHangText = hang(self.sort, R.SortTone)
	self.sell = HudParts.tile(holder, WORDS.SellDupesTile, function()
		actions.sell()
	end, "White", "Sell")
	self.sell.Name = "SellAll"
	self.sellHang, self.sellHangText = hang(self.sell, R.SellTone)
	self.sellAmount = 0
	return self
end

--- Add the rail's pieces to the menu's open (Config.UI.Inventory.Open "TabCues", "TabIndex",
--- "Sort", "Sell" and their badges: the red dots, the hanging pills).
function CuesRail.register(self: any, stage: any)
	for _, key in VIEWS do
		local tab: Tab = self.tabs[key]
		stage:add("Tab" .. key, tab.button)
		stage:add("Tab" .. key .. "Badge", tab.dot)
	end
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

-- A red dot's size for its words.
function CuesRail.sizeDot(self: any, tab: Tab)
	local t = if self.geo then self.geo.t else 0
	local dotPx = span(R.DotPx, t)
	local textPx = span(R.DotTextPx, t)
	local w = math.ceil(textWidth(tab.dotText.Text, textPx)) + 10
	tab.dot.Size = UDim2.fromOffset(math.max(dotPx, w), dotPx)
	HudParts.setTextSize(tab.dotText, textPx, textPx)
end

--- Lay the rail out beside the panel (or in the page); returns the page width it leaves.
function CuesRail.layout(self: any, geo: MenuFrame.Geo): number
	self.geo = geo
	local t = geo.t
	local frame = self.frame
	local panel: Frame = frame.panel
	local gap = span(R.GapPx, t)
	local hangH = span(R.HangPx, t)
	-- A hanging pill reaches this far under its tile; the next tile starts a gap below it, so
	-- every clear space down the rail is the same.
	local drop = math.ceil(hangH / 2)
	-- Offsets, not absolute sizes: the panel may be mid pop-in (scaled) when this runs.
	local panelW, panelH = panel.Size.X.Offset, panel.Size.Y.Offset
	local content: Frame = frame.content
	local contentTop = content.Position.Y.Offset
	local outside = self:outside(panelW, t)
	-- Four tiles, three gaps and two hanging pills; the tiles shrink (to MinTilePx) when the
	-- panel is shorter than that.
	local room = if outside then panelH else geo.content.Y
	local tile = span(R.TilePx, t)
	tile = math.max(R.MinTilePx, math.min(tile, math.floor((room - 3 * gap - 2 * drop) / 4)))
	local railH = 4 * tile + 3 * gap + 2 * drop
	local width = geo.content.X
	local x, y
	if outside then
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

	local textPx = span(R.TextPx, t)
	local hangText = span(R.HangTextPx, t)
	local at = 0
	for _, key in VIEWS do
		local tab: Tab = self.tabs[key]
		tab.button.Position = UDim2.fromOffset(0, at)
		tab.button.Size = UDim2.fromOffset(tile, tile)
		HudParts.setButtonTextSize(tab.button, textPx)
		tab.dot.Position = UDim2.fromOffset(tile - 6, 6)
		self:sizeDot(tab)
		at += tile + gap
	end
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
		at += tile + drop + gap
	end
	return width
end

-- The lit tile's icon rocks gently (as the Shop's lit jump button).
function CuesRail.rockLit(self: any)
	if self.rock then
		self.rock.stop()
		self.rock = nil
	end
	local body = self.tabs[self.view].button:FindFirstChild("Body")
	local icon = body and body:FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		self.rock = UIAnim.turn(icon, 0, L.TabRockDegrees, L.RockSeconds)
	end
end

--- Show which view is chosen: its tile turns blue (the other white) and its icon rocks, and
--- Sort and Sell dupes step aside in the Index (at once with `instant`).
function CuesRail.setView(self: any, view: string, instant: boolean?)
	local changed = self.view ~= view
	self.view = view
	for key, tab in self.tabs :: { [string]: Tab } do
		HudParts.setTone(tab.button, if key == view then "Blue" else "White")
	end
	if changed or not self.rock then
		self:rockLit()
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

--- The tile of the view showing (where a gamepad lands when nothing else is chosen).
function CuesRail.current(self: any): TextButton
	return self.tabs[self.view].button
end

--- The red dots: the NEW count on My Cues, "!" on the Index (nil: none).
function CuesRail.setDots(self: any, cues: string?, index: string?)
	local words: { [string]: string } = { Cues = cues or "", Index = index or "" }
	for key, value in words do
		local tab: Tab = self.tabs[key]
		local show = value ~= ""
		if show and tab.dotText.Text ~= value then
			tab.dotText.Text = value
			self:sizeDot(tab)
		end
		tab.dot.Visible = show
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

--- The money Sell dupes would pay (`amount` as words), greyed out with nothing to sell.
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
	local list: { GuiObject } = { self.tabs.Cues.button, self.tabs.Index.button }
	if self.view ~= "Index" then
		table.insert(list, self.sort)
		if self.sell.Selectable then
			table.insert(list, self.sell)
		end
	end
	return list
end

return CuesRail
