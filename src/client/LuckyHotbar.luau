--!strict
-- LuckyHotbar: the lucky block hotbar and its bag (designer, 2026-10-03), Roblox-style and in
-- the kit's look. Along the bottom: one slot per block (the first Config.LuckyBlocks
-- .HotbarSlots of the list), each a slowly turning 3D icon of the block with its number and, on
-- a timer, its countdown; the held block's slot has a thick gold outline. Keys 1-9, a tap or a
-- click hold a block (LuckyClient). The bag button at the end ("+12": blocks waiting) and the `
-- key open the bag: a grid of every block. Drag a block onto a hotbar slot to put it there (mouse
-- and touch), or pick it and then pick the slot (any device, the gamepad's way).
--
-- Its own ScreenGui inside Roblox's top bar inset, so a pointer's position and the slots'
-- positions share one space. It sets BottomLift while it shows. Tuning in
-- Config.LuckyBlocks.UI.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local LuckyBlocks = require(Shared:WaitForChild("Progression"):WaitForChild("LuckyBlocks"))
local BottomLift = require(script.Parent.BottomLift)
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local HudParts = require(script.Parent.HudParts)
local Menus = require(script.Parent.Menus)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local L = Config.LuckyBlocks
local U = L.UI
local W = Strings.LuckyBlocks
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local WHITE = HudParts.tone("White")
local BAG = "LuckyBag" -- its name in Menus

export type Entry = { id: number, kind: string, readyAt: number }
export type Handlers = {
	select: (id: number) -> (), -- hold (or put away) this block
	move: (id: number, to: number) -> (), -- put this block at this place in the list
}

type Icon = { viewport: ViewportFrame, model: Model?, base: CFrame }
type Tile = {
	entry: Entry,
	button: TextButton,
	icon: Icon,
	edge: UIStroke,
	number: TextLabel?,
	timer: TextLabel,
}

local Hotbar = {}
Hotbar.__index = Hotbar

local function now(): number
	return workspace:GetServerTimeNow()
end

-- A slowly turning 3D picture of a block (no particles or lights: a ViewportFrame draws parts).
local function makeIcon(parent: Instance, kind: string): Icon
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Icon"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.new(U.IconAmbient, U.IconAmbient, U.IconAmbient)
	viewport.LightColor = Color3.new(U.IconLight, U.IconLight, U.IconLight)
	viewport.LightDirection = Vector3.new(table.unpack(U.IconLightDirection))
	viewport.ZIndex = 2
	viewport.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = U.IconFieldOfView
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	local row = LuckyBlocks.kind(kind)
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local source = if row and folder then folder:FindFirstChild(row.Model) else nil
	local icon: Icon = { viewport = viewport, model = nil, base = CFrame.identity }
	if source and source:IsA("Model") then
		local model = source:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				-- The pack's grey base bleeds through its Overlay colour map.
				d.Color = Color3.new(1, 1, 1)
			end
			if
				d:IsA("ParticleEmitter")
				or d:IsA("Light")
				or d:IsA("AnimationController")
				or d:IsA("LuaSourceContainer")
			then
				d:Destroy()
			end
		end
		local _, size = model:GetBoundingBox()
		local edge = math.max(size.X, size.Y, size.Z)
		model:PivotTo(CFrame.new(0, -edge / 2, 0))
		model.Parent = viewport
		icon.model = model
		icon.base = model:GetPivot()
		local distance = edge * U.IconDistance
		camera.CFrame = CFrame.lookAt(Vector3.new(0, edge * 0.55, distance), Vector3.new(0, 0, 0))
	end
	return icon
end

-- A square tile for a block: the ink see-through face, its icon, a number (hotbar only) and the
-- countdown along its bottom.
local function makeTile(parent: Instance, entry: Entry, number: number?): Tile
	local button = Instance.new("TextButton")
	button.Name = "Block" .. entry.id
	button.Text = ""
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = INK
	button.BackgroundTransparency = U.SlotFillTransparency
	-- Lobby buttons never take the gamepad's selection (it would take the stick from walking);
	-- the bag makes them selectable while it is open.
	button.Selectable = false
	button.SelectionImageObject = CaseOpeningFx.noBox()
	button.Parent = parent
	HudParts.corner(button, U.SlotCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = WHITE
	edge.Thickness = U.SlotStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	local icon = makeIcon(button, entry.kind)
	local numberLabel: TextLabel? = nil
	if number then
		local label = HudParts.text(button, "Number", U.NumberPx, tostring(number))
		label.AutoLocalize = false
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Position = UDim2.fromOffset(5, 2)
		label.Size = UDim2.fromOffset(U.NumberPx + 4, U.NumberPx + 2)
		label.ZIndex = 4
		numberLabel = label
	end
	local timer = HudParts.text(button, "Timer", U.TimerPx, "")
	timer.AutoLocalize = false
	timer.AnchorPoint = Vector2.new(0.5, 1)
	timer.Position = UDim2.new(0.5, 0, 1, -2)
	timer.Size = UDim2.new(1, -4, 0, U.TimerPx + 2)
	timer.TextWrapped = false
	timer.Visible = false
	timer.ZIndex = 4
	return {
		entry = entry,
		button = button,
		icon = icon,
		edge = edge,
		number = numberLabel,
		timer = timer,
	}
end

function Hotbar.new(screen: ScreenGui, handlers: Handlers): any
	local self: any = setmetatable({}, Hotbar)
	self.handlers = handlers
	self.entries = {} :: { Entry }
	self.heldId = nil :: number?
	self.hiddenId = nil :: number? -- a thrown block on the floor: not in the bar meanwhile
	self.visible = false
	self.slots = {} :: { Tile }
	self.tiles = {} :: { Tile } -- the bag's
	self.pickedId = nil :: number?
	self.bagOpen = false
	self.drag = nil :: any
	self.suppressUntil = 0
	self.listKey = ""

	local gui = Instance.new("ScreenGui")
	gui.Name = "LuckyHotbar"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + 1
	gui.Parent = screen.Parent
	self.gui = gui

	local bar = HudParts.frame(gui, "Bar")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Visible = false
	self.bar = bar

	local bagButton = Instance.new("TextButton")
	bagButton.Name = "BagButton"
	bagButton.Text = ""
	bagButton.AutoButtonColor = false
	bagButton.BorderSizePixel = 0
	bagButton.BackgroundColor3 = INK
	bagButton.BackgroundTransparency = U.SlotFillTransparency
	bagButton.Selectable = false
	bagButton.Parent = bar
	HudParts.corner(bagButton, U.SlotCornerPx)
	local bagEdge = Instance.new("UIStroke")
	bagEdge.Color = WHITE
	bagEdge.Thickness = U.SlotStrokePx
	bagEdge.Parent = bagButton
	local bagIcon = HudParts.icon(bagButton, "Inventory", "BagIcon")
	bagIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	bagIcon.Position = UDim2.fromScale(0.5, 0.45)
	bagIcon.Size = UDim2.fromScale(0.62, 0.62)
	bagIcon.ZIndex = 2
	local bagCount = HudParts.text(bagButton, "Count", U.BagCountPx, "")
	bagCount.AutoLocalize = false
	bagCount.AnchorPoint = Vector2.new(0.5, 1)
	bagCount.Position = UDim2.new(0.5, 0, 1, -1)
	bagCount.Size = UDim2.new(1, 0, 0, U.BagCountPx + 2)
	bagCount.TextWrapped = false
	bagCount.ZIndex = 3
	bagButton.Activated:Connect(function()
		UISound.play("Click")
		Menus.toggle(BAG)
	end)
	self.bagButton, self.bagCount = bagButton, bagCount

	-- "Ready in 1:42" and the server's refusals, over the bar.
	local notice = HudParts.text(gui, "Notice", U.NoticePx, "")
	notice.AnchorPoint = Vector2.new(0.5, 1)
	notice.TextWrapped = false
	notice.Visible = false
	self.notice = notice

	self:buildBag()
	Menus.register(BAG, {
		open = function()
			self:setBag(true)
		end,
		close = function()
			self:setBag(false)
		end,
		isOpen = function(): boolean
			return self.bagOpen
		end,
		root = self.panel,
	})

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		self:dragMoved(input)
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		self:dragEnded(input)
	end)
	RunService.RenderStepped:Connect(function()
		self:step()
	end)
	return self
end

function Hotbar.buildBag(self: any)
	local panel = HudParts.card(self.gui, "Bag", Config.UI.Kit.PanelCornerPx)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Visible = false
	self.panel = panel
	-- A press on the panel's empty parts stays on it (nothing behind reacts).
	local floor = Instance.new("TextButton")
	floor.Name = "Floor"
	floor.Text = ""
	floor.AutoButtonColor = false
	floor.BackgroundTransparency = 1
	floor.Selectable = false
	floor.Size = UDim2.fromScale(1, 1)
	floor.ZIndex = 1
	floor.Parent = panel
	local title = HudParts.text(panel, "Title", U.BagTitlePx, W.Bag)
	title.TextWrapped = false
	title.Position = UDim2.fromOffset(U.BagPadPx, U.BagPadPx / 2)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	self.bagTitle = title
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 6
	grid.ScrollBarImageColor3 = INK
	grid.ScrollingDirection = Enum.ScrollingDirection.Y
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.ZIndex = 2
	grid.Parent = panel
	local layout = Instance.new("UIGridLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 4)
	pad.Parent = grid
	self.grid, self.gridLayout = grid, layout
	local hint = HudParts.note(panel, "Hint", U.BagHintPx, W.BagHint)
	hint.TextWrapped = false
	hint.ZIndex = 3
	self.bagHint = hint
	local empty = HudParts.note(panel, "Empty", U.BagHintPx + 2, W.BagEmpty)
	empty.ZIndex = 3
	empty.Visible = false
	self.bagEmpty = empty
end

local function phone(gui: ScreenGui): boolean
	return gui.AbsoluteSize.X < U.PhoneWidthPx
end

function Hotbar.slotPx(self: any): number
	return if phone(self.gui) then U.PhoneSlotPx else U.SlotPx
end

-- The blocks the bar shows: the list without the one on the floor, first HotbarSlots.
function Hotbar.shown(self: any): ({ Entry }, number)
	local list = {}
	for _, entry in self.entries do
		if entry.id ~= self.hiddenId then
			table.insert(list, entry)
		end
	end
	local inBar = math.min(#list, L.HotbarSlots)
	return list, inBar
end

--- The player's blocks (BlockState's list), the held block's id and the thrown one's (hidden
--- from the bar while it is on the floor).
function Hotbar.set(self: any, entries: { Entry }, heldId: number?, hiddenId: number?)
	self.entries = entries
	self.heldId = heldId
	self.hiddenId = hiddenId
	local parts = {}
	for _, e in entries do
		table.insert(parts, e.id .. ":" .. e.kind)
	end
	local key = table.concat(parts, ",") .. "|" .. tostring(hiddenId)
	if key ~= self.listKey then
		self.listKey = key
		self:rebuild()
	else
		self:refreshSelection()
	end
end

-- The list's place of the block in hotbar slot `index` (the thrown block is skipped).
function Hotbar.placeOfSlot(self: any, index: number): number
	local list = self:shown()
	local entry = list[index]
	if entry == nil then
		return index
	end
	for i, e in self.entries do
		if e.id == entry.id then
			return i
		end
	end
	return index
end

function Hotbar.rebuild(self: any)
	for _, tile in self.slots do
		tile.button:Destroy()
	end
	for _, tile in self.tiles do
		tile.button:Destroy()
	end
	self.slots, self.tiles = {}, {}
	local list, inBar = self:shown()
	for i = 1, inBar do
		local entry = list[i]
		local tile = makeTile(self.bar, entry, i)
		self:wire(tile, i)
		self.slots[i] = tile
	end
	for i, entry in self.entries do
		local tile = makeTile(self.grid, entry, nil)
		tile.button.LayoutOrder = i
		self:wire(tile, nil)
		table.insert(self.tiles, tile)
	end
	if self.pickedId and not self:find(self.pickedId) then
		self.pickedId = nil
	end
	self:layout()
	self:refreshSelection()
end

function Hotbar.find(self: any, id: number): Entry?
	for _, e in self.entries do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- A tile's presses: a click picks or holds; a press that moves is a drag.
function Hotbar.wire(self: any, tile: Tile, slot: number?)
	tile.button.Activated:Connect(function()
		if os.clock() < self.suppressUntil then
			return -- the end of a drag
		end
		self:pressed(tile.entry.id, slot)
	end)
	tile.button.InputBegan:Connect(function(input: InputObject)
		local kind = input.UserInputType
		if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
			self.drag = {
				id = tile.entry.id,
				kind = tile.entry.kind,
				from = Vector2.new(input.Position.X, input.Position.Y),
				input = input,
				ghost = nil,
			}
		end
	end)
end

function Hotbar.pressed(self: any, id: number, slot: number?)
	UISound.play("Click")
	if slot == nil then
		-- A bag tile: pick it (again: unpick), then a hotbar slot puts it there.
		self.pickedId = if self.pickedId == id then nil else id
		self:refreshSelection()
		return
	end
	if self.pickedId then
		local picked = self.pickedId
		self.pickedId = nil
		self.handlers.move(picked, self:placeOfSlot(slot))
		self:refreshSelection()
		return
	end
	self.handlers.select(id)
end

function Hotbar.dragMoved(self: any, input: InputObject)
	local drag = self.drag
	if drag == nil then
		return
	end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseMovement and input ~= drag.input then
		return
	end
	local at = Vector2.new(input.Position.X, input.Position.Y)
	if drag.ghost == nil then
		if (at - drag.from).Magnitude < U.DragThresholdPx then
			return
		end
		local size = self:slotPx()
		local ghost = HudParts.frame(self.gui, "DragGhost")
		ghost.AnchorPoint = Vector2.new(0.5, 0.5)
		ghost.Size = UDim2.fromOffset(size, size)
		ghost.BackgroundColor3 = INK
		ghost.BackgroundTransparency = U.SlotFillTransparency
		ghost.ZIndex = 20
		HudParts.corner(ghost, U.SlotCornerPx)
		local icon = makeIcon(ghost, drag.kind)
		icon.viewport.ZIndex = 21
		drag.ghost = ghost
	end
	drag.ghost.Position = UDim2.fromOffset(at.X, at.Y)
end

local function inside(object: GuiObject, at: Vector2): boolean
	local p, s = object.AbsolutePosition, object.AbsoluteSize
	return at.X >= p.X and at.X <= p.X + s.X and at.Y >= p.Y and at.Y <= p.Y + s.Y
end

function Hotbar.dragEnded(self: any, input: InputObject)
	local drag = self.drag
	if drag == nil then
		return
	end
	local kind = input.UserInputType
	if kind ~= Enum.UserInputType.MouseButton1 and input ~= drag.input then
		return
	end
	self.drag = nil
	if drag.ghost == nil then
		return -- a click: Activated handles it
	end
	drag.ghost:Destroy()
	self.suppressUntil = os.clock() + 0.1
	local at = Vector2.new(input.Position.X, input.Position.Y)
	for i, tile in self.slots do
		if inside(tile.button, at) then
			UISound.play("Click")
			self.handlers.move(drag.id, self:placeOfSlot(i))
			return
		end
	end
	if self.bagOpen and inside(self.panel, at) then
		self.handlers.move(drag.id, #self.entries)
	end
end

function Hotbar.refreshSelection(self: any)
	for _, tile in self.slots do
		local held = tile.entry.id == self.heldId
		tile.edge.Color = if held then GOLD else WHITE
		tile.edge.Thickness = if held then U.SelectedStrokePx else U.SlotStrokePx
		tile.button.Selectable = self.bagOpen
	end
	for _, tile in self.tiles do
		local picked = tile.entry.id == self.pickedId
		tile.edge.Color = if picked then GOLD else WHITE
		tile.edge.Thickness = if picked then U.SelectedStrokePx else U.SlotStrokePx
		tile.button.Selectable = self.bagOpen
	end
	local list, inBar = self:shown()
	local waiting = #list - inBar
	self.bagCount.Text = if waiting > 0 then W.BagCount:format(waiting) else ""
end

function Hotbar.layout(self: any)
	local size = self:slotPx()
	local gap = U.SlotGapPx
	local n = #self.slots
	local width = n * size + n * gap + size
	self.bar.Size = UDim2.fromOffset(width, size)
	self.bar.Position = UDim2.new(0.5, 0, 1, -U.BottomPx)
	for i, tile in self.slots do
		tile.button.Size = UDim2.fromOffset(size, size)
		tile.button.Position = UDim2.fromOffset((i - 1) * (size + gap), 0)
	end
	self.bagButton.Size = UDim2.fromOffset(size, size)
	self.bagButton.Position = UDim2.fromOffset(n * (size + gap), 0)
	self.notice.Position = UDim2.new(0.5, 0, 1, -U.BottomPx - size - 8)
	self.notice.Size = UDim2.fromOffset(math.max(width, 300), U.NoticePx + 6)

	-- The bag: BagColumns tiles across, BagRowsShown rows tall, over the bar.
	local cols, pad = U.BagColumns, U.BagPadPx
	local gridW = cols * size + (cols - 1) * gap + 8
	local gridH = U.BagRowsShown * size + (U.BagRowsShown - 1) * gap + 8
	local titleH = U.BagTitlePx + 8
	local hintH = U.BagHintPx + 8
	local panelW = gridW + 2 * pad + 6
	local panelH = pad / 2 + titleH + gridH + hintH + pad / 2
	self.panel.Size = UDim2.fromOffset(panelW, panelH)
	self.panel.Position = UDim2.new(0.5, 0, 1, -U.BottomPx - size - U.BagGapAbovePx)
	self.bagTitle.Size = UDim2.fromOffset(panelW - 2 * pad, titleH)
	self.grid.Position = UDim2.fromOffset(pad, pad / 2 + titleH)
	self.grid.Size = UDim2.fromOffset(gridW + 6, gridH)
	self.gridLayout.CellSize = UDim2.fromOffset(size, size)
	self.gridLayout.CellPadding = UDim2.fromOffset(gap, gap)
	self.bagHint.Position = UDim2.fromOffset(pad, pad / 2 + titleH + gridH)
	self.bagHint.Size = UDim2.fromOffset(panelW - 2 * pad, hintH)
	self.bagEmpty.Position = self.grid.Position
	self.bagEmpty.Size = self.grid.Size
	BottomLift.set(
		if self.visible then (if phone(self.gui) then U.PhoneLiftPx else U.LiftPx) else 0
	)
end

function Hotbar.setBag(self: any, open: boolean)
	if self.bagOpen == open then
		return
	end
	self.bagOpen = open
	self.pickedId = nil
	self.panel.Visible = open
	if open then
		self.bagHint.Text = if CaseOpeningFx.gamepad() then W.BagHintPad else W.BagHint
		self.bagEmpty.Visible = #self.entries == 0
		UIAnim.popIn(self.panel)
	end
	self:refreshSelection()
end

--- Show or hide the bar (lobby only, no screen or menu over it but the bag); hiding closes the
--- bag.
function Hotbar.setVisible(self: any, visible: boolean)
	visible = visible and #self.entries > 0
	if self.visible == visible then
		return
	end
	self.visible = visible
	self.bar.Visible = visible
	if not visible then
		self.notice.Visible = false
		if self.bagOpen then
			Menus.close(BAG)
		end
	end
	self:layout()
end

function Hotbar.isVisible(self: any): boolean
	return self.visible
end

--- How many blocks the bar shows (the slots keys 1-9 reach).
function Hotbar.slotCount(self: any): number
	return #self.slots
end

--- The block in hotbar slot `index`, or nil.
function Hotbar.slotEntry(self: any, index: number): Entry?
	local tile = self.slots[index]
	return if tile then tile.entry else nil
end

--- The held block's slot shakes and a line shows over the bar for a moment.
function Hotbar.shake(self: any, id: number?, text: string)
	for _, tile in self.slots do
		if tile.entry.id == id then
			UIAnim.shake(tile.button)
		end
	end
	self:say(text)
end

function Hotbar.say(self: any, text: string)
	self.notice.Text = text
	self.notice.Visible = self.visible
	self.noticeUntil = os.clock() + U.ShakeWords
end

function Hotbar.toggleBag(self: any)
	if self.visible then
		Menus.toggle(BAG)
	end
end

function Hotbar.step(self: any)
	if not self.visible and not self.bagOpen then
		return
	end
	local t = now()
	local turn = math.rad(os.clock() * U.IconTurnDegreesPerSecond)
	local function update(tile: Tile)
		local icon = tile.icon
		if icon.model then
			icon.model:PivotTo(CFrame.Angles(0, turn, 0) * icon.base)
		end
		local left = tile.entry.readyAt - t
		if left > 0 then
			tile.timer.Visible = true
			tile.timer.Text = LuckyBlocks.clockText(left)
			icon.viewport.ImageTransparency = 0.35
		elseif tile.timer.Visible then
			tile.timer.Visible = false
			icon.viewport.ImageTransparency = 0
		end
	end
	for _, tile in self.slots do
		update(tile)
	end
	if self.bagOpen then
		for _, tile in self.tiles do
			update(tile)
		end
	end
	if self.notice.Visible and os.clock() > (self.noticeUntil or 0) then
		self.notice.Visible = false
	end
end

return Hotbar
