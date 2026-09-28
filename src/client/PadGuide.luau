--!strict
-- PadGuide: the controller guide (designer, 2026-09-27). While it is your turn to aim and the
-- last input was a gamepad, a faint strip at the bottom left, just above the money HUD, shows
-- what the controller does:
--
--   (L-stick) <> Turn   (D-pad) <> Fine aim   (R-stick) ^v Zoom
--   (L1) Spin & angle   (X) Shoot
--
-- and while L1 holds the spin panel open (designer, 2026-09-27), the spin controls instead:
--
--   (L-stick) Spin   (R-stick) ^v Angle   (Y) Center spin
--
-- and a Circle beside the Leave door in the top bar. The button pictures are Roblox's own
-- (UserInputService:GetImageForKeyCode), so they are PlayStation or Xbox glyphs to match the
-- controller in use; the arrows beside the sticks are the kit's white chevrons (separate
-- images: a turned image does not draw turned inside the strip's list layout).
--
-- Like the zoom guide it is not a kit card (UI_STYLE's decided exception): icons and outlined
-- words with nothing behind them, lightly greyed, so it reads as a guide and not a button.
-- It takes no input. The zoom guide stays hidden on a gamepad; this one covers zoom.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)

local P = Config.UI.PadGuide
local Copy = Strings.PadGuide

type Item = {
	set: string, -- "aim" (the turn) or "spin" (while L1 holds the spin panel open)
	row: number,
	keys: { Enum.KeyCode },
	arrows: string?, -- "sideways" or "updown"
	words: string,
}

-- The strip's contents, in reading order.
local ITEMS: { Item } = {
	{
		set = "aim",
		row = 1,
		keys = { Enum.KeyCode.Thumbstick1 },
		arrows = "sideways",
		words = Copy.Turn,
	},
	{
		set = "aim",
		row = 1,
		keys = { Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight },
		words = Copy.FineAim,
	},
	{
		set = "aim",
		row = 1,
		keys = { Enum.KeyCode.Thumbstick2 },
		arrows = "updown",
		words = Copy.Zoom,
	},
	{ set = "aim", row = 2, keys = { Enum.KeyCode.ButtonL1 }, words = Copy.SpinAngle },
	{
		set = "aim",
		row = 2,
		keys = { Enum.KeyCode.ButtonA },
		words = Copy.Shoot,
	},
	{ set = "spin", row = 1, keys = { Enum.KeyCode.Thumbstick1 }, words = Copy.Spin },
	{
		set = "spin",
		row = 1,
		keys = { Enum.KeyCode.Thumbstick2 },
		arrows = "updown",
		words = Copy.Angle,
	},
	{ set = "spin", row = 1, keys = { Enum.KeyCode.ButtonY }, words = Copy.CenterSpin },
}

local PadGuide = {}
PadGuide.__index = PadGuide

local function isGamepad(): boolean
	return UserInputService:GetLastInputType().Name:match("^Gamepad") ~= nil
end

local function tint(): Color3
	return HudParts.color(P.Tint)
end

-- A small white chevron beside a stick (`key`: ChevronLeft, Right, Up or Down).
local function arrow(parent: Instance, key: string, order: number): ImageLabel
	local image = HudParts.icon(parent, key, key)
	image.ImageColor3 = tint()
	image.ImageTransparency = P.IconTransparency
	image.LayoutOrder = order
	return image
end

local function row(parent: Instance, name: string, gap: number, order: number): Frame
	local frame = HudParts.frame(parent, name)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.LayoutOrder = order
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, gap)
	list.Parent = frame
	return frame
end

function PadGuide.new(screen: ScreenGui): any
	local self: any = setmetatable({}, PadGuide)
	self.screen = screen
	self.wanted = false
	self.glyphs = {} :: { [ImageLabel]: Enum.KeyCode }
	self.arrows = {} :: { ImageLabel }
	self.words = {} :: { TextLabel }
	self.stacks = {} :: { Frame }
	self.leaveHint = nil :: ImageLabel?

	local root = HudParts.frame(screen, "PadGuide")
	root.AnchorPoint = Vector2.new(0, 1)
	root.AutomaticSize = Enum.AutomaticSize.XY
	root.Visible = false
	local rows = Instance.new("UIListLayout")
	rows.SortOrder = Enum.SortOrder.LayoutOrder
	rows.Padding = UDim.new(0, P.RowGapPx)
	rows.Parent = root
	self.root = root
	self.rowList = rows

	local rowFrames: { [string]: Frame } = {}
	self.rowSets = {} :: { [Frame]: string }
	self.set = "aim"
	for index, item in ITEMS do
		local key = item.set .. item.row
		local line: Frame? = rowFrames[key]
		if line == nil then
			local made = row(root, "Row" .. key, P.ItemGapPx, item.row)
			made.Visible = item.set == self.set
			rowFrames[key] = made
			self.rowSets[made] = item.set
			line = made
		end
		local entry = row(line :: Frame, "Item" .. index, P.PartGapPx, index)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		if item.arrows == "sideways" then
			table.insert(self.arrows, arrow(entry, "ChevronLeft", nextOrder()))
		end
		for _, key in item.keys do
			local glyph = Instance.new("ImageLabel")
			glyph.Name = key.Name
			glyph.BackgroundTransparency = 1
			glyph.ScaleType = Enum.ScaleType.Fit
			glyph.ImageTransparency = P.GlyphTransparency
			glyph.LayoutOrder = nextOrder()
			glyph.Parent = entry
			self.glyphs[glyph] = key
		end
		if item.arrows == "sideways" then
			table.insert(self.arrows, arrow(entry, "ChevronRight", nextOrder()))
		elseif item.arrows == "updown" then
			-- Up over down, in a narrow column beside the stick.
			local stack = HudParts.frame(entry, "UpDown")
			stack.LayoutOrder = nextOrder()
			local list = Instance.new("UIListLayout")
			list.SortOrder = Enum.SortOrder.LayoutOrder
			list.Parent = stack
			table.insert(self.arrows, arrow(stack, "ChevronUp", 1))
			table.insert(self.arrows, arrow(stack, "ChevronDown", 2))
			table.insert(self.stacks, stack)
		end
		local words = HudParts.text(entry, "Words", P.TextSize, item.words)
		words.TextWrapped = false
		words.TextXAlignment = Enum.TextXAlignment.Left
		words.AutomaticSize = Enum.AutomaticSize.X
		words.TextColor3 = tint()
		words.TextTransparency = P.TextTransparency
		words.LayoutOrder = nextOrder()
		local outline = words:FindFirstChildOfClass("UIStroke")
		if outline then
			outline.Transparency = P.OutlineTransparency
		end
		table.insert(self.words, words)
	end

	self:refreshGlyphs()
	self:layout()
	UserInputService.LastInputTypeChanged:Connect(function()
		self:refreshGlyphs()
		self:apply()
	end)
	UserInputService.GamepadConnected:Connect(function()
		self:refreshGlyphs()
	end)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	return self
end

--- The controller's own button pictures (PlayStation or Xbox), fetched again when the pad
--- or the input changes.
function PadGuide.refreshGlyphs(self: any)
	for glyph, key in self.glyphs do
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(key)
		end)
		glyph.Image = if ok and type(image) == "string" then image else ""
	end
	local hint = self.leaveHint
	if hint then
		local ok, image = pcall(function()
			return UserInputService:GetImageForKeyCode(Enum.KeyCode.ButtonB)
		end)
		hint.Image = if ok and type(image) == "string" then image else ""
	end
end

--- Size it for the screen (smaller on a phone on its side) and sit it just above the money
--- HUD at the bottom left.
function PadGuide.layout(self: any)
	local short = self.screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local glyph = if short then P.ShortGlyphPx else P.GlyphPx
	local text = if short then P.ShortTextSize else P.TextSize
	local arrowPx = math.floor(glyph * P.ArrowShare + 0.5)
	for image in self.glyphs do
		image.Size = UDim2.fromOffset(glyph, glyph)
	end
	for _, image in self.arrows do
		image.Size = UDim2.fromOffset(arrowPx, arrowPx)
	end
	for _, stack in self.stacks do
		stack.Size = UDim2.fromOffset(arrowPx, arrowPx * 2)
	end
	for _, words in self.words do
		HudParts.setTextSize(words, text, text)
		words.Size = UDim2.fromOffset(0, glyph)
	end
	local money = Config.UI.Progress.MoneyHud
	local margin = if short then money.ShortMarginPx else money.MarginPx
	local moneyIcon = if short then money.ShortIconSizePx else money.IconSizePx
	self.root.Position = UDim2.new(0, margin, 1, -(margin + moneyIcon + P.AboveMoneyPx))
end

function PadGuide.apply(self: any)
	local gamepad = isGamepad()
	self.root.Visible = self.wanted and gamepad
	if self.leaveHint then
		self.leaveHint.Visible = gamepad
	end
end

--- Which controls to show: "aim" for the turn, "spin" while L1 holds the spin panel open.
function PadGuide.setSet(self: any, set: string)
	if self.set == set then
		return
	end
	self.set = set
	for line, lineSet in self.rowSets do
		line.Visible = lineSet == set
	end
end

--- Shown while it is the player's turn to aim (Main), and only on a gamepad.
function PadGuide.setVisible(self: any, visible: boolean)
	if self.wanted == visible then
		return
	end
	self.wanted = visible
	self:apply()
end

--- Put the Circle (Xbox: B) just right of the Leave button, shown on a gamepad only.
function PadGuide.attachLeave(self: any, leave: GuiObject)
	local hint = Instance.new("ImageLabel")
	hint.Name = "PadLeaveHint"
	hint.BackgroundTransparency = 1
	hint.ScaleType = Enum.ScaleType.Fit
	hint.AnchorPoint = Vector2.new(0, 0.5)
	hint.Position = UDim2.new(1, P.LeaveGapPx, 0.5, 0)
	hint.Size = UDim2.fromScale(P.LeaveShare, P.LeaveShare)
	hint.ImageTransparency = P.GlyphTransparency
	hint.ZIndex = leave.ZIndex + 1
	hint.Parent = leave
	self.leaveHint = hint
	self:refreshGlyphs()
	self:apply()
end

return PadGuide
