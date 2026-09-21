--!strict
-- PowerCue: the power bar, with a cue lying in it.
--
-- A vertical panel on the right that you press and drag down. The fill charges up behind it
-- as before, and a top-down cue lies inside the bar and slides down as you pull, so the
-- control shows the thing it controls.
--
-- The cue is drawn from Config.Cue.Styles through CueArt, so the cue a player has equipped is
-- the cue they pull back - and a collectible cue is a data row, never new code here
-- (Roadmap 5.2). CueArt does the arithmetic and is Lune-tested; this module only turns its
-- slices into Frames.
--
-- A Frame cannot be a trapezoid, so the taper is built from thin bands stacked tip to butt.
-- Every position and size is in SCALE rather than pixels, so the whole control is resolution
-- independent and the pull reads the same on a phone and a monitor.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CueArt = require(Shared:WaitForChild("CueArt"))

local PowerCue = {}
PowerCue.__index = PowerCue

export type PowerCue = typeof(setmetatable(
	{} :: {
		root: TextButton,
		fill: Frame,
		text: TextLabel,
		cue: Frame,
		styleName: string,
		pull: number,
	},
	PowerCue
))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- The cue is shorter than the bar by exactly the distance it travels, so a full pull lands
-- its butt at the bottom of the bar and never outside it.
local function cueLengthScale(): number
	return 1 / (1 + Config.UI.PowerCueTravelFraction)
end

local function travelScale(): number
	local t = Config.UI.PowerCueTravelFraction
	return t / (1 + t)
end

--- Build the cue out of slices. Called once; pulling only moves the container.
local function buildCue(parent: GuiObject, styleName: string): Frame
	local U = Config.UI
	local style = CueArt.styleFor(Config.Cue.Styles, Config.Cue.DefaultStyle, styleName)

	local cue = Instance.new("Frame")
	cue.Name = "Cue"
	cue.AnchorPoint = Vector2.new(0.5, 0)
	cue.Position = UDim2.fromScale(0.5, 0)
	cue.Size = UDim2.new(0, U.PowerCueWidthPx, cueLengthScale(), 0)
	cue.BackgroundTransparency = 1
	-- Above the fill. Equal ZIndex would fall back to creation order, which works today and
	-- would quietly stop working the moment the fill is rebuilt or reordered.
	cue.ZIndex = 2
	cue.Parent = parent

	local slices = CueArt.slices(style, U.PowerCueSlices)
	for i, slice in slices do
		local band = Instance.new("Frame")
		band.Name = ("Slice%02d"):format(i)
		band.AnchorPoint = Vector2.new(0.5, 0)
		band.Position = UDim2.fromScale(0.5, slice.offset)
		-- One pixel of overlap, or rounding between bands leaves hairline gaps down the cue.
		band.Size =
			UDim2.new(0, math.max(1, math.round(slice.width * U.PowerCueWidthPx)), slice.length, 1)
		band.BackgroundColor3 = rgb(slice.color)
		band.BorderSizePixel = 0
		band.ZIndex = 2
		band.Parent = cue

		-- Round the two ends only: a cue is blunt at the butt and domed at the tip.
		if i == 1 or i == #slices then
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = band
		end
	end
	return cue
end

function PowerCue.new(screen: ScreenGui, styleName: string?): PowerCue
	local U = Config.UI

	-- The bar is the drag target, so it is a button rather than a frame.
	local bar = Instance.new("TextButton")
	bar.Name = "PowerBar"
	bar.Text = ""
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.new(1, -U.PowerBarRightMarginPx, 0.5, 0)
	-- Height follows the screen so the whole bar, and the whole pull, fits a phone.
	bar.Size = UDim2.new(0, U.PowerBarWidthPx, U.PowerBarHeightFraction, 0)
	bar.BackgroundColor3 = rgb(U.Panel)
	bar.BackgroundTransparency = U.PanelTransparency
	bar.AutoButtonColor = false
	bar.Parent = screen

	local limit = Instance.new("UISizeConstraint")
	limit.MinSize = Vector2.new(U.PowerBarWidthPx, U.PowerBarMinHeightPx)
	limit.MaxSize = Vector2.new(U.PowerBarWidthPx, U.PowerBarMaxHeightPx)
	limit.Parent = bar

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = bar

	-- Fill charges from the top as the player pulls down, behind the cue.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = rgb(U.Accent)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 0)
	fill.ZIndex = 1
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 12)
	fillCorner.Parent = fill

	local cue = buildCue(bar, styleName or Config.Cue.DefaultStyle)

	local text = Instance.new("TextLabel")
	text.Name = "Percent"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, 24)
	text.Position = UDim2.new(0, 0, 1, 4)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.Text = "PULL"
	text.Size = UDim2.new(1, 0, 0, 24)
	text.Position = UDim2.new(0, 0, 1, 4)
	text.Parent = bar

	return setmetatable({
		root = bar,
		fill = fill,
		text = text,
		cue = cue,
		styleName = styleName or Config.Cue.DefaultStyle,
		pull = 0,
	}, PowerCue)
end

--- Show this pull: the cue slides down, the fill charges up behind it, the label follows.
--- nil means idle, which is the same place as zero.
function PowerCue.setPull(self: PowerCue, pull: number?)
	local value = math.clamp(pull or 0, 0, 1)
	self.pull = value
	self.cue.Position = UDim2.fromScale(0.5, value * travelScale())
	self.fill.Size = UDim2.fromScale(1, value)
	self.text.Text = if pull then ("%d%%"):format(math.floor(value * 100 + 0.5)) else "PULL"
end

--- Rebuild for a different cue. Roadmap 5.2 calls this when a player equips one.
function PowerCue.setStyle(self: PowerCue, styleName: string)
	if styleName == self.styleName then
		return
	end
	self.styleName = styleName
	self.cue:Destroy()
	self.cue = buildCue(self.root, styleName)
	self:setPull(self.pull)
end

function PowerCue.setVisible(self: PowerCue, visible: boolean)
	self.root.Visible = visible
	if not visible then
		self:setPull(nil)
	end
end

--- Press the bar and drag down to pull back. `onPull` fires with 0..1 while dragging,
--- `onRelease` when the finger lifts.
function PowerCue.onDrag(self: PowerCue, onPull: (number) -> (), onRelease: () -> ())
	local active: InputObject? = nil
	local startY = 0

	self.root.InputBegan:Connect(function(input: InputObject)
		if active then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			active = input
			startY = input.Position.Y
			onPull(0)
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		local a = active
		if a == nil then
			return
		end
		-- A mouse reports its drag as MouseMovement rather than as the button that started
		-- it, so the two have to be treated as the same gesture.
		local same = input == a
			or (
				a.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if same then
			local travel = self.root.AbsoluteSize.Y * Config.Input.PowerPullBarFraction
			onPull(math.clamp((input.Position.Y - startY) / math.max(travel, 1), 0, 1))
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		local a = active
		if a == nil then
			return
		end
		if
			input == a
			or (
				a.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseButton1
			)
		then
			active = nil
			onRelease()
		end
	end)
end

return PowerCue
