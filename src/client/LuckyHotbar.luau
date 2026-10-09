--!strict
-- LuckyHotbar: the lucky block hotbar and its bag (designer, 2026-10-03), Roblox-style and in
-- the kit's look. Along the bottom: one slot per block (the first Config.LuckyBlocks
-- .HotbarSlots of the list; a phone only the first UI.PhoneHotbarSlots), each the block's 2D icon (its Icon; else a slowly turning 3D model) with its number and, on
-- a timer, its countdown; the held block's slot has a thick gold outline. Keys 1-9, a tap or a
-- click hold a block (LuckyClient); an unclimbed block (economy v5: every new block) wears the
-- climb mark in its top-right corner, its ready slot says OPEN! and a tap opens its climb
-- screen instead (MysteryReveal). The bag button at the end ("+12": blocks waiting) and the `
-- key open the bag: a grid of every block. A click on a block there equips it like Roblox's
-- backpack (the bag stays open; an unclimbed block climbs instead); drag a block onto a hotbar
-- slot to put it there (mouse and touch).
--
-- A throw of a block still on its timer (it stays in the hands: 2026-10-09), an unclimbed
-- block's tap during its wait (the Gift), or an open refused asks about the skip (economy v4 plan 18.1 item 8) in the kit's dialog over the screen (MenuFrame.ask): the block's name,
-- "Ready in 4:32. Skip the wait?", Wait and the green "Skip · 4" with the price for the time
-- left right now (4 / 9 / 15 R$, Config.LuckyBlocks.Skips; the live price from the shop's
-- view). Skip asks the server, which prompts that same tier's product. Where the shop says the
-- skip cannot be bought it says why instead. The skip is a paid random item (economy v4 plan
-- 13), so the dialog wears the block's dice: the question steps aside for the block's Odds &
-- Details (OddsDetails over the screen) and comes back when that closes.
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
local ReelFx = require(script.Parent.ReelFx)
local HudParts = require(script.Parent.HudParts)
local BlockIcon = require(script.Parent.BlockIcon)
local ItemState = require(script.Parent.ItemState)
local MenuFrame = require(script.Parent.MenuFrame)
local Menus = require(script.Parent.Menus)
local OddsDetails = require(script.Parent.OddsDetails)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local TutorialAnchors = require(script.Parent.TutorialAnchors)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local L = Config.LuckyBlocks
local U = L.UI
local W = Strings.LuckyBlocks
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local WHITE = HudParts.tone("White")
local BAG = "LuckyBag" -- its name in Menus
local SKIPS: { { UpTo: number?, Product: string } } = L.Skips :: any
local NAMES: { [string]: string } = W.Names

-- climbed: the block climbed already (BlockState's `climbed`, economy v5); nil for an
-- unclimbed block of a climbing kind, or a kind that never climbs.
export type Entry = { id: number, kind: string, readyAt: number, climbed: boolean? }
export type Handlers = {
	select: (id: number) -> (), -- hold (or put away) this block
	reveal: (id: number) -> (), -- open this unclimbed block's climb screen (MysteryReveal)
	move: (id: number, to: number) -> (), -- put this block at this place in the list
	skip: (id: number) -> (), -- the skip dialog's Skip: ask the server to prompt this block's skip
}

-- picture: the kind's 2D icon (an ImageLabel) or its 3D view (a ViewportFrame); both have
-- ImageTransparency, which the countdown dims.
type Icon = { picture: any, model: Model?, base: CFrame, aura: UIAnim.Handle? }
type Tile = {
	entry: Entry,
	button: TextButton,
	icon: Icon,
	edge: UIStroke,
	number: TextLabel?,
	timer: TextLabel,
	open: TextLabel?, -- an unclimbed block's OPEN! (designer, 2026-10-07; every block since v5)
	mark: Frame?, -- an unclimbed block's climb mark
}

local Hotbar = {}
Hotbar.__index = Hotbar

--- Whether `entry`'s block still climbs (economy v5): a climbing kind not yet climbed. Its tap
--- opens the climb screen; it is never held as it is.
function Hotbar.unclimbed(entry: Entry?): boolean
	return entry ~= nil and entry.climbed ~= true and LuckyBlocks.climbs(entry.kind)
end

-- A phone's screen (narrower than UI.PhoneWidthPx): smaller slots, fewer of them.
local function phone(gui: ScreenGui): boolean
	return gui.AbsoluteSize.X < U.PhoneWidthPx
end

local function now(): number
	return workspace:GetServerTimeNow()
end

-- The kind's 2D icon (Config.LuckyBlocks.Kinds[kind].Icon), else a slowly turning 3D picture
-- of the block (no particles or lights: a ViewportFrame draws parts).
local function makeIcon(parent: Instance, kind: string): Icon
	local row = LuckyBlocks.kind(kind)
	if row and row.Icon and row.Icon ~= "" then
		local image = Instance.new("ImageLabel")
		image.Name = "Icon"
		image.BackgroundTransparency = 1
		image.Image = row.Icon
		image.ScaleType = Enum.ScaleType.Fit
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(U.IconImageShare, U.IconImageShare)
		image.ZIndex = 2
		image.Parent = parent
		local picture: Icon = { picture = image, model = nil, base = CFrame.identity, aura = nil }
		if row.Rainbow == true and parent:IsA("GuiObject") then
			picture.aura = BlockIcon.aura(parent, image.ZIndex - 1)
		end
		return picture
	end
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
	local ambient = if row and row.IconAmbient then row.IconAmbient else U.IconAmbient
	local light = if row and row.IconLight then row.IconLight else U.IconLight
	viewport.Ambient = Color3.new(ambient, ambient, ambient)
	viewport.LightColor = Color3.new(light, light, light)
	local folder = ReplicatedStorage:FindFirstChild(L.ModelFolder)
	local source = if row and folder then folder:FindFirstChild(row.Model) else nil
	local icon: Icon = { picture = viewport, model = nil, base = CFrame.identity, aura = nil }
	if row and row.Rainbow == true and parent:IsA("GuiObject") then
		icon.aura = BlockIcon.aura(parent, viewport.ZIndex - 1)
	end
	if not (source and source:IsA("Model")) then
		-- No model in the place yet: the kind's kit icon stands in (BlockIcon's fallback).
		local image = HudParts.icon(viewport, BlockIcon.fallbackKey(kind), "Fallback")
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position = UDim2.fromScale(0.5, 0.5)
		image.Size = UDim2.fromScale(0.86, 0.86)
		image.ZIndex = viewport.ZIndex + 1
	end
	if source and source:IsA("Model") then
		local model = source:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:FindFirstChildOfClass("SurfaceAppearance") then
				-- The pack's grey base bleeds through its Overlay colour map (a part-built
				-- block, the Lucky 8, keeps its own colours).
				d.Color = Color3.new(1, 1, 1)
			elseif d:IsA("SurfaceAppearance") then
				d.EmissiveStrength = if row and row.EmissiveStrength
					then row.EmissiveStrength
					else L.Look.EmissiveStrength
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
		-- The block's box centred on the origin (its pivot may sit off the middle), the camera
		-- a little above, looking at the middle (the same framing as BlockIcon).
		model:PivotTo(CFrame.identity)
		local box, size = model:GetBoundingBox()
		model:PivotTo(CFrame.new(-box.Position))
		local edge = math.max(size.X, size.Y, size.Z)
		model.Parent = viewport
		icon.model = model
		icon.base = model:GetPivot()
		local distance = edge * U.IconDistance / (if row then row.IconScale or 1 else 1)
		camera.CFrame =
			CFrame.lookAt(Vector3.new(0, edge * U.IconAboveShare, distance), Vector3.zero)
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
	button.SelectionImageObject = ReelFx.noBox()
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
	-- An unclimbed block says OPEN! along its bottom once it is ready, and pulses: a tap opens
	-- its climb screen. It wears the climb mark meanwhile (the climb screen's up arrow).
	local openLabel: TextLabel? = nil
	local mark: Frame? = nil
	if Hotbar.unclimbed(entry) then
		local M = U.ClimbMark
		local disc = HudParts.frame(button, "ClimbMark")
		disc.AnchorPoint = Vector2.new(1, 0)
		disc.Position = UDim2.new(1, -M.InsetPx, 0, M.InsetPx)
		disc.SizeConstraint = Enum.SizeConstraint.RelativeXX
		disc.Size = UDim2.fromScale(M.Share, M.Share)
		disc.BackgroundTransparency = 0
		disc.BackgroundColor3 = INK
		disc.ZIndex = 5
		HudParts.corner(disc, 999)
		local ring = Instance.new("UIStroke")
		ring.Color = WHITE
		ring.Thickness = M.RingPx
		ring.Parent = disc
		local least = Instance.new("UISizeConstraint")
		least.MinSize = Vector2.new(M.MinPx, M.MinPx)
		least.Parent = disc
		local arrow = HudParts.icon(disc, "ChevronUp", "Arrow")
		arrow.AnchorPoint = Vector2.new(0.5, 0.5)
		arrow.Position = UDim2.fromScale(0.5, 0.5)
		arrow.Size = UDim2.fromScale(M.ArrowShare, M.ArrowShare)
		arrow.ImageColor3 = GOLD
		arrow.ZIndex = 6
		mark = disc
		local label = HudParts.text(button, "Open", U.OpenPx, W.OpenSlot, GOLD)
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, 2)
		label.Size = UDim2.new(1, 6, 0, U.OpenPx + 4)
		label.TextWrapped = false
		label.Visible = false
		label.ZIndex = 5
		UIAnim.pulse(label)
		openLabel = label
	end
	return {
		entry = entry,
		button = button,
		icon = icon,
		edge = edge,
		number = numberLabel,
		timer = timer,
		open = openLabel,
		mark = mark,
	}
end

function Hotbar.new(screen: ScreenGui, handlers: Handlers): any
	local self: any = setmetatable({}, Hotbar)
	self.handlers = handlers
	self.entries = {} :: { Entry }
	self.heldId = nil :: number?
	self.hiddenIds = {} :: { [number]: boolean } -- a thrown block on the floor: not in the bar meanwhile
	self.masked = {} :: { [number]: boolean } -- a Mystery block out on its upgrade screen
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

	-- The skip dialog's room (offerSkip): the whole screen, the dialog in its middle.
	local layer = HudParts.frame(gui, "Dialogs")
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 10
	self.layer = layer
	self.skipDialog = nil :: MenuFrame.Dialog?
	self.skipId = nil :: number? -- the block the skip dialog asks about
	-- The skip dialog's dice: a block's Odds & Details over the screen (a menu's host: its
	-- room, its dialogs and its sizes, set as it opens).
	self.oddsHost = { content = layer, dialogs = {}, geo = nil :: MenuFrame.Geo? }
	self.odds = OddsDetails.new(self.oddsHost)

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
		-- A phone shows fewer slots: rebuild when the screen crosses the line.
		if phone(gui) ~= self.wasPhone then
			self:rebuild()
		else
			self:layout()
		end
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

function Hotbar.slotPx(self: any): number
	return if phone(self.gui) then U.PhoneSlotPx else U.SlotPx
end

-- The blocks the bar shows: the list without the one on the floor, first HotbarSlots (a
-- phone's fewer).
function Hotbar.shown(self: any): ({ Entry }, number)
	local list = {}
	for _, entry in self.entries do
		if not self.hiddenIds[entry.id] then
			table.insert(list, entry)
		end
	end
	local slots = if phone(self.gui)
		then math.min(L.HotbarSlots, U.PhoneHotbarSlots)
		else L.HotbarSlots
	return list, math.min(#list, slots)
end

--- The player's blocks (BlockState's list), the held block's id and the thrown one's (hidden
--- from the bar while it is on the floor).
function Hotbar.set(
	self: any,
	entries: { Entry },
	heldId: number?,
	hiddenIds: { [number]: boolean }
)
	self.entries = entries
	self.heldId = heldId
	self.hiddenIds = hiddenIds
	local parts = {}
	for _, e in entries do
		table.insert(
			parts,
			e.id
				.. ":"
				.. e.kind
				.. ":"
				.. e.readyAt
				.. ":"
				.. tostring(e.climbed)
				.. ":"
				.. tostring(hiddenIds[e.id])
		)
	end
	local key = table.concat(parts, ",")
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
	self.wasPhone = phone(self.gui)
	local list, inBar = self:shown()
	for i = 1, inBar do
		local entry = list[i]
		local tile = makeTile(self.bar, entry, i)
		self:wire(tile, i)
		self.slots[i] = tile
	end
	-- The tutorial's hand points at a slot ("HotbarSlot1"...).
	for i = 1, L.HotbarSlots do
		local tile = self.slots[i]
		TutorialAnchors.set("HotbarSlot" .. i, if tile then tile.button else nil)
	end
	-- The bag lists every block but the thrown ones (it can stay open while one is thrown).
	for i, entry in list do
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
		-- A bag tile (designer, 2026-10-07), like Roblox's backpack: a click equips it (held
		-- out; again puts it away) and the bag stays open; an unclimbed block closes the bag
		-- and opens its climb screen. Dragging still moves a block into the hotbar.
		if Hotbar.unclimbed(self:find(id)) then
			if self.bagOpen then
				Menus.close(BAG)
			end
			self.handlers.reveal(id)
		else
			self.handlers.select(id)
		end
		return
	end
	if self.pickedId then
		local picked = self.pickedId
		self.pickedId = nil
		self.handlers.move(picked, self:placeOfSlot(slot))
		self:refreshSelection()
		return
	end
	if Hotbar.unclimbed(self:find(id)) then
		self.handlers.reveal(id)
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
		icon.picture.ZIndex = 21
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
		local marked = tile.entry.id == self.heldId or tile.entry.id == self.pickedId
		tile.edge.Color = if marked then GOLD else WHITE
		tile.edge.Thickness = if marked then U.SelectedStrokePx else U.SlotStrokePx
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
	-- The skip's Odds & Details, over the whole screen.
	if self.odds:isOpen() then
		self.oddsHost.geo = MenuFrame.screenGeo(self.layer)
		self.odds:layout(self.oddsHost.geo)
	end

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
		self.bagHint.Text = if ReelFx.gamepad() then W.BagHintPad else W.BagHint
		self.bagEmpty.Visible = #self.entries == 0
		self.grid.CanvasPosition = Vector2.zero -- at the top, as every menu (designer, 2026-10-08)
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
		if self.skipDialog then
			self.skipDialog.cancel()
		end
		self.odds:close()
		if self.bagOpen then
			Menus.close(BAG)
		end
	end
	self:layout()
end

function Hotbar.isVisible(self: any): boolean
	return self.visible
end

--- The bar's middle in absolute pixels while it shows (where a block flies to), else nil.
function Hotbar.center(self: any): Vector2?
	if not self.visible then
		return nil
	end
	local bar: Frame = self.bar
	return bar.AbsolutePosition + bar.AbsoluteSize / 2
end

--- Where block `id` sits while the bar shows: its slot's middle (absolute pixels) and size,
--- or the bag button's for a block in the bag; nil while the bar is hidden.
function Hotbar.slotOf(self: any, id: number): (Vector2?, number?)
	if not self.visible then
		return nil, nil
	end
	for _, tile in self.slots do
		if tile.entry.id == id then
			local b: GuiObject = tile.button
			return b.AbsolutePosition + b.AbsoluteSize / 2, b.AbsoluteSize.X
		end
	end
	if self.bagOpen then
		for _, tile in self.tiles do
			if tile.entry.id == id then
				local b: GuiObject = tile.button
				return b.AbsolutePosition + b.AbsoluteSize / 2, b.AbsoluteSize.X
			end
		end
	end
	local bag: GuiObject = self.bagButton
	return bag.AbsolutePosition + bag.AbsoluteSize / 2, bag.AbsoluteSize.X
end

--- Block `id`'s slot shows nothing while its block is out on the upgrade screen (true), or
--- its block again (false).
function Hotbar.mask(self: any, id: number, on: boolean)
	self.masked[id] = if on then true else nil
end

--- Block `id` landed back in its slot: the slot bounces with a glow in `tint`.
function Hotbar.landed(self: any, id: number, tint: Color3?)
	for _, tile in self.slots do
		if tile.entry.id == id then
			UIAnim.bounce(tile.button)
			UIAnim.glowBurst(tile.button, tint)
			return
		end
	end
	UIAnim.bounce(self.bagButton)
end

--- A block landed in the bar: it bounces.
function Hotbar.bump(self: any)
	if self.visible then
		UIAnim.bounce(self.bar)
	end
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

-- The skip product for a timer with `left` seconds to go (Config.LuckyBlocks.Skips) and its
-- Robux price: the live one from the shop's view, else Config's.
local function skipFor(left: number): (string, number, any)
	local key = SKIPS[LuckyBlocks.skipTierFor(left)].Product
	local shop = ItemState.shop()
	local products = if type(shop) == "table" and type(shop.products) == "table"
		then shop.products
		else {}
	local product = products[key]
	return key, ShopParts.robuxOf(product, key), product
end

--- Ask about the skip for block `id`, still on its timer (economy v4 plan 18.1 item 8): its
--- name, "Ready in 4:32. Skip the wait?", Wait and "Skip · 4" with the price for the time left
--- right now. Where the shop says the skip cannot be bought (paid random items restricted) it
--- says why instead. Nothing for a block that is ready or unknown, or while one is asked.
function Hotbar.offerSkip(self: any, id: number)
	local entry = self:find(id)
	local left = if entry then entry.readyAt - now() else 0
	if entry == nil or left <= 0 or self.skipDialog ~= nil then
		return
	end
	local _, robux, product = skipFor(left)
	if type(product) == "table" and product.canBuy == false then
		self:say(W.SkipUnavailable)
		return
	end
	self.notice.Visible = false
	self.skipId = id
	self.skipDialog = MenuFrame.ask(self.layer, {
		title = NAMES[entry.kind] or entry.kind,
		text = W.SkipAsk:format(LuckyBlocks.clockText(left)),
		yes = W.Skip:format(ShopParts.robux(robux)),
		yesTone = "Green",
		no = W.SkipNo,
		noTone = "Blue",
		corner = function(card: Frame): GuiObject
			local badge = ShopCards.oddsBadge(card, "OddsBadge", 3)
			badge.hit.Activated:Connect(function()
				UISound.play("Click")
				self:skipOdds(id, entry.kind)
			end)
			return badge.badge
		end,
	}, function(yes: boolean)
		self.skipDialog = nil
		if yes then
			self.handlers.skip(id)
		end
	end)
end

--- The skip dialog's dice: the question steps aside for block `id`'s Odds & Details (its
--- `kind`'s list) and is asked again when that closes (the price for the time left then).
function Hotbar.skipOdds(self: any, id: number, kind: string)
	if self.skipDialog then
		self.skipDialog.cancel()
	end
	local spec = OddsDetails.blockSpec(kind)
	spec.closed = function()
		-- After the list has put the gamepad's selection back, so the question takes it.
		task.defer(function()
			if self.visible then
				self:offerSkip(id)
			end
		end)
	end
	self.oddsHost.geo = MenuFrame.screenGeo(self.layer)
	self.odds:show(spec)
end

function Hotbar.isBagOpen(self: any): boolean
	return self.bagOpen
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
	-- The skip's question goes once its block is ready (its timer ran out, or VIP came).
	if self.skipDialog and self.skipId then
		local asked = self:find(self.skipId)
		if asked == nil or asked.readyAt <= t then
			self.skipDialog.cancel()
		end
	end
	local turn = math.rad(os.clock() * U.IconTurnDegreesPerSecond)
	local function update(tile: Tile)
		local icon = tile.icon
		if icon.model then
			icon.model:PivotTo(CFrame.Angles(0, turn, 0) * icon.base)
		end
		local masked = self.masked[tile.entry.id] == true
		if tile.mark then
			tile.mark.Visible = not masked
		end
		if masked then
			icon.picture.ImageTransparency = 1
			tile.timer.Visible = false
			if tile.open then
				tile.open.Visible = false
			end
			return
		end
		local left = tile.entry.readyAt - t
		if tile.open then
			tile.open.Visible = left <= 0
		end
		if left > 0 then
			tile.timer.Visible = true
			tile.timer.Text = LuckyBlocks.clockText(left)
			tile.timer.TextColor3 = HudParts.tone("White")
			icon.picture.ImageTransparency = 0.35
		else
			-- Ready: READY! in green (an unclimbed block says OPEN! instead); a VIP's blocks say it
			-- from the moment they arrive (the designer, 2026-10-09).
			tile.timer.Visible = tile.open == nil
			tile.timer.Text = W.Ready
			tile.timer.TextColor3 = HudParts.tone("Green")
			icon.picture.ImageTransparency = 0
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
