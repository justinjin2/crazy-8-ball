--!strict
-- InventoryCases: the cases at the top of the Inventory's Items tab (GUI lane, designer
-- 2026-10-03, C6): one strip of big tiles that scrolls sideways, owned cases first.
--   * A ready case (the snapshot's `cases`): its chest, name and "x4", then Open (one, on
--     CaseOpening's reel) and, for Quick Cases owners holding at least
--     Config.Cases.FastOpenCount, "Open 10" (CaseOpening's grid).
--   * A case on its timer (the snapshot's `timers`, soonest first): its chest, name and "Ready
--     in 5:12:03" counting down, then two skips: money ("$1,500": ShopState.skip, $25 a minute
--     left, at least $250; ItemRequest "SkipTimer") and Robux (the cheapest Skip product that
--     covers the time left; StoreRequest "Skip", which prompts it). Players where paid random
--     items are restricted see no skips.
-- The strip hides when there is nothing in it. The server decides everything; a reply's new
-- snapshot redraws the tiles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local InventoryCard = require(script.Parent.InventoryCard)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local RewardChips = require(script.Parent.RewardChips)
local ShopParts = require(script.Parent.ShopParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local I = Config.UI.Inventory
local IT = I.Items
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local CASE_NAMES: { [string]: string } = Strings.Items.Cases :: any
local CASES: { [string]: any } = Config.Cases.List :: any
local LIST: { [string]: any } = Config.Products.List :: any
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local MANY = Config.Cases.FastOpenCount

type Tile = {
	key: string, -- "Case:<id>" or "Timer:<id>:<readyAt>"
	box: Frame,
	icon: ImageLabel,
	name: TextLabel,
	line: TextLabel,
	first: TextButton,
	second: TextButton,
	caseId: string,
	readyAt: number?, -- a timer's
	count: number,
	bob: UIAnim.Handle?,
}

local InventoryCases = {}
InventoryCases.__index = InventoryCases

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function fastOpen(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute("FastOpen") == true
end

-- The snapshot's ready cases ({ id, count }) and timers ({ id, readyAt, paid }).
local function readyCases(items: any): { any }
	local rows = {}
	for _, row in
		(if type(items) == "table" and type(items.cases) == "table" then items.cases else {})
	do
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

local function timers(items: any): { any }
	local rows = {}
	for _, row in
		(if type(items) == "table" and type(items.timers) == "table" then items.timers else {})
	do
		if type(row) == "table" and type(row.id) == "string" and type(row.readyAt) == "number" then
			table.insert(rows, row)
		end
	end
	return rows
end

--- The money a skip costs with `seconds` left (ShopState.skip, else Config.Shop.Skip).
function InventoryCases.skipMoney(seconds: number): number
	local state = ItemState.shop()
	local skip = if type(state) == "table" and type(state.skip) == "table" then state.skip else {}
	local perMinute = if type(skip.moneyPerMinute) == "number"
		then skip.moneyPerMinute
		else Config.Shop.Skip.MoneyPerMinute
	local least = if type(skip.minMoney) == "number"
		then skip.minMoney
		else Config.Shop.Skip.MinMoney
	return math.max(least, math.ceil(math.max(0, seconds) / 60) * perMinute)
end

--- The Robux skip the server would prompt for `seconds` left: the cheapest Skip product whose
--- SkipSeconds covers it (its key and live price), or nil.
function InventoryCases.skipProduct(seconds: number): (string?, number)
	local state = ItemState.shop()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local best: string? = nil
	local bestRobux = math.huge
	for key, row in LIST do
		if type(row.SkipSeconds) == "number" and row.SkipSeconds >= seconds then
			local robux = ShopParts.robuxOf(products[key], key)
			if robux < bestRobux then
				best, bestRobux = key, robux
			end
		end
	end
	return best, if best then bestRobux else 0
end

--- The strip, built into `area` (the Items page's top). `ctx`: InventoryMenu's.
function InventoryCases.new(area: Frame, ctx: any): any
	local self: any = setmetatable({}, InventoryCases)
	self.area = area
	self.ctx = ctx
	self.tiles = {} :: { [string]: Tile }
	self.order = {} :: { string }
	self.geo = nil :: MenuFrame.Geo?
	self.ticker = nil :: RBXScriptConnection?
	self.nextTick = 0

	local header = HudParts.text(
		area,
		"Header",
		IT.HeaderTextPx[1],
		WORDS.CasesHeader,
		HudParts.color(Config.UI.Shop.Page.HeaderColor)
	)
	header.TextWrapped = false
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 3
	self.header = header
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Strip"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollingDirection = Enum.ScrollingDirection.X
	scroll.ScrollBarThickness = Config.UI.Menu.Scroll.BarPx
	scroll.ScrollBarImageColor3 = HudParts.color(Config.UI.Menu.Scroll.BarColor)
	scroll.HorizontalScrollBarInset = Enum.ScrollBarInset.Always
	scroll.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	scroll.Selectable = false
	scroll.ZIndex = 2
	scroll.Parent = area
	self.scroll = scroll
	return self
end

function InventoryCases.buildTile(self: any, key: string, caseId: string): Tile
	local box = InventoryCard.box(self.scroll, key)
	box.ZIndex = 2
	local icon = HudParts.icon(box, RewardChips.caseIcon(caseId), "Chest")
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.ZIndex = 3
	local name = HudParts.text(box, "Name", IT.CaseNameTextPx[1], CASE_NAMES[caseId] or caseId)
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local line =
		HudParts.text(box, "Line", IT.CaseTimerTextPx[1], "", HudParts.color(K.Numbers.Count))
	line.AutoLocalize = false
	line.TextWrapped = false
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.ZIndex = 3
	local tile: Tile
	local first = HudParts.candy(box, "", function()
		self:pressFirst(tile)
	end, "Green")
	first.Name = "First"
	first.ZIndex = 3
	HudParts.setMinHit(first, TOUCH)
	local second = HudParts.candy(box, "", function()
		self:pressSecond(tile)
	end, "Green")
	second.Name = "Second"
	second.ZIndex = 3
	HudParts.setMinHit(second, TOUCH)
	tile = {
		key = key,
		box = box,
		icon = icon,
		name = name,
		line = line,
		first = first,
		second = second,
		caseId = caseId,
		readyAt = nil,
		count = 0,
		bob = nil,
	}
	return tile
end

--- Whether there is anything in the strip (the Items page lays out round it).
function InventoryCases.any(self: any): boolean
	return #self.order > 0
end

--- The cases' red dot on the Items tab: every ready case.
function InventoryCases.dot(_self: any, items: any): number
	local total = 0
	for _, row in readyCases(items) do
		total += math.floor(row.count)
	end
	return total
end

function InventoryCases.redraw(self: any, items: any)
	local ctx = self.ctx
	local keep: { [string]: boolean } = {}
	local order: { string } = {}
	local fast = fastOpen()
	local state = ItemState.shop()
	local restricted = type(state) == "table" and state.restricted == true
	for _, row in readyCases(items) do
		local key = "Case:" .. row.id
		keep[key] = true
		table.insert(order, key)
		local tile: Tile = self.tiles[key] or self:buildTile(key, row.id)
		self.tiles[key] = tile
		tile.count = math.floor(row.count)
		tile.readyAt = nil
		tile.line.Text = WORDS.Count:format(Format.commas(tile.count))
		HudParts.setText(tile.first, WORDS.Open)
		HudParts.setTone(tile.first, "Green")
		HudParts.setButtonIcon(tile.first, nil)
		HudParts.setEnabled(tile.first, not ctx.isHeld(tile.first))
		tile.second.Visible = fast and tile.count >= MANY
		HudParts.setText(tile.second, WORDS.OpenMany:format(Format.commas(MANY)))
		HudParts.setTone(tile.second, "Blue")
		HudParts.setButtonIcon(tile.second, nil)
		HudParts.setEnabled(tile.second, not ctx.isHeld(tile.second))
		if not tile.bob then
			tile.bob = UIAnim.bob(tile.icon, 3)
		end
	end
	for index, row in timers(items) do
		-- Two cases can share a ready time: the place in the list keeps their keys apart.
		local key = ("Timer:%s:%d:%d"):format(row.id, row.readyAt, index)
		keep[key] = true
		table.insert(order, key)
		local tile: Tile = self.tiles[key] or self:buildTile(key, row.id)
		self.tiles[key] = tile
		tile.readyAt = row.readyAt
		tile.count = 1
		tile.first.Visible = not restricted
		tile.second.Visible = not restricted
		HudParts.setTone(tile.first, "Yellow")
		HudParts.setButtonIcon(tile.first, "CashSingle")
		HudParts.setTone(tile.second, "Green")
		HudParts.setEnabled(tile.first, not ctx.isHeld(tile.first))
		HudParts.setEnabled(tile.second, not ctx.isHeld(tile.second))
	end
	for key, tile in self.tiles :: { [string]: Tile } do
		if not keep[key] then
			if tile.bob then
				tile.bob.stop()
			end
			tile.box:Destroy()
			self.tiles[key] = nil
		end
	end
	self.order = order
	self:tick()
	self:arrange()
	if #order > 0 and not self.ticker then
		self.ticker = RunService.Heartbeat:Connect(function()
			local clock = os.clock()
			if clock >= self.nextTick then
				self.nextTick = clock + 0.5
				self:tick()
			end
		end)
	end
end

-- The timers' countdowns and their skip prices.
function InventoryCases.tick(self: any)
	if not self.ctx.isOpen() then
		if self.ticker then
			self.ticker:Disconnect()
			self.ticker = nil
		end
		return
	end
	local now = workspace:GetServerTimeNow()
	for _, key in self.order do
		local tile: Tile = self.tiles[key]
		local readyAt = tile.readyAt
		if readyAt then
			local left = readyAt - now
			tile.line.Text = WORDS.ReadyIn:format(ShopParts.timeLeft(left))
			HudParts.setText(tile.first, Format.money(InventoryCases.skipMoney(left)))
			local _, robux = InventoryCases.skipProduct(left)
			HudParts.setText(tile.second, ShopParts.robux(robux))
		end
	end
end

function InventoryCases.pressFirst(self: any, tile: Tile)
	local ctx = self.ctx
	UISound.play("Click")
	if tile.readyAt == nil then
		self:openCases(tile.caseId, 1, tile.first)
		return
	end
	local readyAt = tile.readyAt
	ctx.hold(tile.first, function()
		local reply = ctx.request("SkipTimer", tile.caseId, readyAt)
		if reply.ok then
			UISound.play("Claim")
			ctx.notice(WORDS.SkippedReady:format(CASE_NAMES[tile.caseId] or tile.caseId), "Green")
		else
			ctx.refuse(reply)
		end
	end)
end

function InventoryCases.pressSecond(self: any, tile: Tile)
	local ctx = self.ctx
	UISound.play("Click")
	if tile.readyAt == nil then
		self:openCases(tile.caseId, MANY, tile.second)
		return
	end
	local readyAt = tile.readyAt
	ctx.hold(tile.second, function()
		local reply = ItemState.request("StoreRequest", "Skip", tile.caseId, readyAt)
		if not reply.ok then
			ctx.refuse(reply)
		end
	end)
end

--- Open cases on the reel (or Quick Cases' grid): CaseOpening asks the server and shows it.
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

--- The strip's height on this page, or 0 with nothing in it.
function InventoryCases.height(self: any): number
	if #self.order == 0 then
		return 0
	end
	return self.ctx.span(IT.CaseStripPx) + self.ctx.span(IT.HeaderTextPx) + 6
end

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
	local any = #self.order > 0
	self.header.Visible = any
	self.scroll.Visible = any
	if not any then
		return
	end
	local W = self.area.AbsoluteSize.X / MenuFrame.scaleOf(self.area)
	if W <= 1 then
		W = geo.content.X
	end
	local headerH = span(IT.HeaderTextPx)
	HudParts.setTextSize(self.header, headerH)
	self.header.Position = UDim2.fromOffset(4, 0)
	self.header.Size = UDim2.fromOffset(W - 8, headerH + 4)
	local h = span(IT.CaseStripPx)
	local bar = Config.UI.Menu.Scroll.BarPx
	self.scroll.Position = UDim2.fromOffset(0, headerH + 6)
	self.scroll.Size = UDim2.fromOffset(W, h)
	local tileW = span(IT.CaseTileWidthPx)
	local tileH = h - bar - 4
	local gap = span(I.CardGapPx)
	local pad = math.max(4, round(tileH * 0.07))
	local buttonH = span(IT.CaseButtonPx)
	local buttonText = span(IT.CaseButtonTextPx)
	local nameSize = span(IT.CaseNameTextPx)
	local lineSize = span(IT.CaseTimerTextPx)
	local x = 2
	for _, key in self.order do
		local tile: Tile = self.tiles[key]
		tile.box.Position = UDim2.fromOffset(x, 2)
		tile.box.Size = UDim2.fromOffset(tileW, tileH)
		local shown = {}
		for _, button in { tile.first, tile.second } do
			if button.Visible then
				table.insert(shown, button)
			end
		end
		if tile.bob then
			tile.bob.stop() -- before placing: stopping puts the icon back where it was
		end
		-- The chest big on the left; the name, the timer and the buttons (side by side) beside it.
		local iconSize = math.max(24, math.min(tileH - pad * 2, round(tileW * IT.CaseIconShare)))
		tile.icon.Size = UDim2.fromOffset(iconSize, iconSize)
		tile.icon.Position =
			UDim2.fromOffset(pad + round(iconSize / 2), round((tileH - iconSize) / 2))
		if tile.bob then
			tile.bob = UIAnim.bob(tile.icon, 3)
		end
		local textX = pad * 2 + iconSize
		local textW = tileW - textX - pad
		local textH = nameSize + lineSize + 8
		local topH = tileH - pad * 3 - (if #shown > 0 then buttonH else 0)
		local y = pad + math.max(0, round((topH - textH) / 2))
		HudParts.setTextSize(tile.name, nameSize)
		tile.name.Position = UDim2.fromOffset(textX, y)
		tile.name.Size = UDim2.fromOffset(textW, nameSize + 4)
		y += nameSize + 4
		HudParts.setTextSize(tile.line, lineSize)
		tile.line.Position = UDim2.fromOffset(textX, y)
		tile.line.Size = UDim2.fromOffset(textW, lineSize + 4)
		local buttonW = if #shown > 0 then (textW - (#shown - 1) * 4) / #shown else 0
		for i, button in shown do
			button.Position =
				UDim2.fromOffset(round(textX + (i - 1) * (buttonW + 4)), tileH - pad - buttonH)
			button.Size = UDim2.fromOffset(round(buttonW), buttonH)
			HudParts.setButtonTextSize(button, buttonText)
		end
		x += tileW + gap
	end
	self.scroll.CanvasSize = UDim2.fromOffset(x, 0)
end

--- Where a gamepad starts in the strip: the first tile's first button.
function InventoryCases.first(self: any): GuiObject?
	for _, key in self.order do
		local tile: Tile = self.tiles[key]
		for _, button in { tile.first, tile.second } do
			if button.Visible and button.Selectable then
				return button
			end
		end
	end
	return nil
end

function InventoryCases.closed(self: any)
	if self.ticker then
		self.ticker:Disconnect()
		self.ticker = nil
	end
end

return InventoryCases
