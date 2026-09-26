--!strict
-- A full-disc spin control with pointer dragging and a gamepad modifier, and beside it the
-- cue-angle slider for jump shots (tap or drag the track; arrow keys or L1 + D-pad step it).
-- Input owns the chosen spin, cue angle and modal lock; this module only draws and edits them.
-- Drawn in the UI kit's look (HudParts): a white card, an inked glossy cue ball, candy buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Input = require(script.Parent.Input)
local HudParts = require(script.Parent.HudParts)
local K = Config.UI.Kit

local SpinSelector = {}
SpinSelector.__index = SpinSelector

export type SpinSelector = typeof(setmetatable(
	{} :: {
		root: Frame,
		toggle: TextButton,
		badge: TextLabel,
		input: Input.Input,
		enabled: boolean,
	},
	SpinSelector
))

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function corner(object: GuiObject, radius: UDim)
	local item = Instance.new("UICorner")
	item.CornerRadius = radius
	item.Parent = object
end

-- The kit's ink outline round a shape.
local function ink(object: GuiObject, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = rgb(K.Colors.Ink)
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = object
	return stroke
end

-- A bare button (the backdrop, the toggle, the ball and the slider are drawn over it).
local function button(parent: GuiObject, name: string, text: string): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Text = text
	item.TextSize = Config.UI.Spin.TextSizePx
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Font = (Enum.Font :: any)[K.Font]
	item.BackgroundColor3 = rgb(K.Colors.White)
	item.BorderSizePixel = 0
	item.Active = true
	item.ZIndex = parent.ZIndex + 1
	item.Parent = parent
	corner(item, UDim.new(0, Config.UI.Spin.CornerRadiusPx))
	return item
end

local function ball(parent: GuiObject, name: string, size: number): TextButton
	local item = button(parent, name, "")
	item.AutoButtonColor = false
	item.Size = UDim2.fromOffset(size, size)
	item.BackgroundColor3 = rgb(Config.UI.Spin.BallColor)
	local rounding = item:FindFirstChildOfClass("UICorner") :: UICorner
	rounding.CornerRadius = UDim.new(0.5, 0)
	ink(item, K.ButtonStrokePx)
	-- The same shine as the HUD balls.
	local gloss = Instance.new("ImageLabel")
	gloss.Name = "Gloss"
	gloss.BackgroundTransparency = 1
	gloss.Image = K.Art.BallGloss
	gloss.Size = UDim2.fromScale(1, 1)
	gloss.ZIndex = item.ZIndex + 1
	gloss.Active = false
	gloss.Parent = item
	return item
end

local function dot(parent: GuiObject, diameter: number): Frame
	local item = Instance.new("Frame")
	item.Name = "StrikePoint"
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Size = UDim2.fromOffset(diameter, diameter)
	item.BackgroundColor3 = rgb(Config.UI.Spin.DotColor)
	item.BorderSizePixel = 0
	item.ZIndex = parent.ZIndex + 2
	item.Parent = parent
	corner(item, UDim.new(0.5, 0))
	return item
end

local function isPointer(object: InputObject): boolean
	return object.UserInputType == Enum.UserInputType.MouseButton1
		or object.UserInputType == Enum.UserInputType.Touch
end

function SpinSelector.new(screen: ScreenGui, input: Input.Input): SpinSelector
	local C, S = Config.UI.Spin, Strings.Spin
	local root = Instance.new("Frame")
	root.Name = "SpinSelector"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.ZIndex = 10
	root.Visible = false
	root.Parent = screen

	-- A fullscreen button absorbs table/power gestures while the target is open.
	local blocker = button(root, "ModalBlocker", "")
	blocker.Size = UDim2.fromScale(1, 1)
	blocker.BackgroundColor3 = rgb(K.Colors.Ink)
	blocker.BackgroundTransparency = C.OverlayTransparency
	blocker.AutoButtonColor = false
	blocker.Selectable = false
	blocker.Visible = false

	local toggle = button(root, "SpinToggle", "")
	toggle.AnchorPoint = Vector2.new(0, 0.5)
	toggle.Position = UDim2.new(0, C.ToggleMarginPx, 0.5, 0)
	toggle.BackgroundTransparency = 1
	toggle.Size = UDim2.fromOffset(C.ToggleSizePx, C.ToggleSizePx)
	toggle.ZIndex = blocker.ZIndex + 1
	local iconSize = C.ToggleSizePx
	local icon = Instance.new("Frame")
	icon.Name = "CueBall"
	icon.Size = UDim2.fromOffset(iconSize, iconSize)
	icon.BackgroundColor3 = rgb(C.BallColor)
	icon.BorderSizePixel = 0
	icon.ZIndex = toggle.ZIndex + 1
	icon.Parent = toggle
	corner(icon, UDim.new(0.5, 0))
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	ink(icon, K.ButtonStrokePx)
	local iconGloss = Instance.new("ImageLabel")
	iconGloss.Name = "Gloss"
	iconGloss.BackgroundTransparency = 1
	iconGloss.Image = K.Art.BallGloss
	iconGloss.Size = UDim2.fromScale(1, 1)
	iconGloss.ZIndex = icon.ZIndex + 1
	iconGloss.Parent = icon
	-- The decoration must not steal the toggle's pointer or gamepad selection.
	icon.Active = false
	icon.Selectable = false
	local iconDot = dot(icon, C.IconDotSizePx)
	-- A raised cue is easy to forget once the panel closes: its angle sits under the toggle.
	local badge = HudParts.text(toggle, "CueAngle", C.TextSizePx, "")
	badge.TextWrapped = false
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 1, 6)
	badge.Size = UDim2.new(1, 0, 0, C.AngleBadgeHeightPx)
	badge.BackgroundTransparency = 0
	badge.BackgroundColor3 = rgb(K.Colors.Blue)
	badge.BorderSizePixel = 0
	badge.ZIndex = toggle.ZIndex + 1
	badge.Visible = false
	corner(badge, UDim.new(0.5, 0))
	ink(badge, K.ButtonStrokePx - 0.5)

	local panel = HudParts.card(root, "SpinPanel")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Active = false -- empty space lets the backdrop receive outside clicks
	panel.ZIndex = toggle.ZIndex + 1
	panel.Visible = false
	panel.Parent = root
	local rowWidth = C.BallSizePx + C.GapPx + C.AngleColumnPx
	local panelWidth = math.max(C.PanelWidthPx, rowWidth + C.MarginPx * 2)
	local y = C.MarginPx
	local target = ball(panel, "StrikeTarget", C.BallSizePx)
	target.Selectable = false
	local strikeDot = dot(target, C.DotSizePx)

	-- The cue-angle slider: a track the height of the ball, filled from the bottom up to a
	-- thumb that reads the angle. Top is the steepest cue.
	local column = button(panel, "CueAngle", "")
	column.BackgroundTransparency = 1
	column.AutoButtonColor = false
	column.Selectable = false
	local track = Instance.new("Frame")
	track.Name = "Track"
	track.AnchorPoint = Vector2.new(0.5, 0)
	track.BackgroundColor3 = rgb(K.Colors.White)
	track.BorderSizePixel = 0
	track.Active = false
	track.ZIndex = column.ZIndex + 1
	track.Parent = column
	corner(track, UDim.new(0.5, 0))
	ink(track, K.ButtonStrokePx - 0.5)
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = rgb(K.Colors.Blue)
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.ZIndex = track.ZIndex + 1
	fill.Parent = track
	corner(fill, UDim.new(0.5, 0))
	local thumb = HudParts.text(column, "Thumb", C.TextSizePx, "")
	thumb.TextWrapped = false
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Size = UDim2.new(1, 0, 0, C.AngleThumbHeightPx)
	thumb.BackgroundTransparency = 0
	thumb.BackgroundColor3 = rgb(K.Colors.Blue)
	thumb.BorderSizePixel = 0
	thumb.Active = false
	thumb.ZIndex = track.ZIndex + 2
	corner(thumb, UDim.new(0, C.CornerRadiusPx))
	ink(thumb, K.ButtonStrokePx - 0.5)
	y += C.BallSizePx + C.GapPx

	local actionWidth = (panelWidth - C.MarginPx * 2 - C.GapPx) / 2
	-- Center and Done: candy buttons; their presses are connected below.
	local reset = HudParts.candy(panel, S.Center, function() end, "Blue")
	reset.Name = "Center"
	reset.ZIndex = panel.ZIndex + 1
	reset.Position = UDim2.fromOffset(C.MarginPx, y)
	reset.Size = UDim2.fromOffset(actionWidth, C.ButtonSizePx)
	local done = HudParts.candy(panel, S.Done, function() end, "Green")
	done.Name = "Done"
	done.ZIndex = panel.ZIndex + 1
	done.Position = UDim2.fromOffset(C.MarginPx + actionWidth + C.GapPx, y)
	done.Size = UDim2.fromOffset(actionWidth, C.ButtonSizePx)
	local actionsY = y
	local fullHeight = y + C.ButtonSizePx + C.MarginPx
	local function layout()
		local small = root.AbsoluteSize.X < Config.Multiplayer.Style.MobileBreakpoint
			or root.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
		local size = if small then Config.Multiplayer.Style.PlacementHandleSize else C.ToggleSizePx
		toggle.Size = UDim2.fromOffset(size, size)
		icon.Size = UDim2.fromOffset(size, size)
		-- Shrink only the ball on short landscape phones; button targets remain 44 px.
		local ballSize = math.clamp(
			root.AbsoluteSize.Y - (fullHeight - C.BallSizePx) - C.MarginPx * 2,
			C.ButtonSizePx,
			C.BallSizePx
		)
		local delta = ballSize - C.BallSizePx
		target.Size = UDim2.fromOffset(ballSize, ballSize)
		local left = (panelWidth - (rowWidth + delta)) / 2
		target.Position = UDim2.fromOffset(left, C.MarginPx)
		column.Position = UDim2.fromOffset(left + ballSize + C.GapPx, C.MarginPx)
		column.Size = UDim2.fromOffset(C.AngleColumnPx, ballSize)
		local thumbHalf = C.AngleThumbHeightPx / 2
		track.Position = UDim2.new(0.5, 0, 0, thumbHalf)
		track.Size = UDim2.new(0, C.AngleTrackWidthPx, 1, -C.AngleThumbHeightPx)
		reset.Position = UDim2.new(reset.Position.X, UDim.new(0, actionsY + delta))
		done.Position = UDim2.new(done.Position.X, UDim.new(0, actionsY + delta))
		panel.Size = UDim2.fromOffset(panelWidth, fullHeight + delta)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	local self = setmetatable({
		root = root,
		toggle = toggle,
		badge = badge,
		input = input,
		enabled = true,
	}, SpinSelector)
	local active: InputObject? = nil
	local function refresh(x: number, sy: number)
		-- The full white disc represents the legal spin range, not literal cue-tip position.
		-- Keep the entire dot inside either ball, including when layout shrinks the target.
		local nx, ny = x / Config.Cue.MaxSpinOffset, sy / Config.Cue.MaxSpinOffset
		local dotRadius = C.DotSizePx / 2
		local position = UDim2.new(0.5 + nx / 2, -nx * dotRadius, 0.5 - ny / 2, ny * dotRadius)
		strikeDot.Position = position
		local iconDotRadius = C.IconDotSizePx / 2
		iconDot.Position =
			UDim2.new(0.5 + nx / 2, -nx * iconDotRadius, 0.5 - ny / 2, ny * iconDotRadius)
	end
	input:onSpin(refresh)
	refresh(input.spinX, input.spinY)

	local Cue = Config.Cue
	local lowest, steepest = Cue.CueElevationDegrees, Cue.MaxElevationDegrees
	local function showAngle(degrees: number)
		local fraction = (degrees - lowest) / (steepest - lowest)
		local text = string.format(S.Degrees, degrees)
		thumb.Text = text
		-- The thumb's centre runs the track's length: half a thumb in from each end.
		thumb.Position = UDim2.new(
			0.5,
			0,
			1 - fraction,
			C.AngleThumbHeightPx / 2 - (1 - fraction) * C.AngleThumbHeightPx
		)
		fill.Size = UDim2.fromScale(1, fraction)
		badge.Text = text
		badge.Visible = self.enabled and degrees > lowest
	end
	input:onElevation(showAngle)
	showAngle(input:getElevation())
	input:onSpinEditing(function(editing)
		blocker.Visible = editing
		panel.Visible = editing
		active = nil
	end)
	toggle.Activated:Connect(function()
		if self.enabled then
			input:setSpinEditing(not input.spinEditing)
		end
	end)
	reset.Activated:Connect(function()
		if input.spinEditing then
			input:resetSpin()
		end
	end)
	local function close()
		input:setSpinEditing(false)
	end
	done.Activated:Connect(close)
	-- Close on release so this click cannot start a table drag or a power pull.
	blocker.Activated:Connect(close)

	local function choose(position: Vector3)
		-- InputObject.Position already uses the same inset-adjusted space as AbsolutePosition.
		local localPoint = Vector2.new(position.X, position.Y) - target.AbsolutePosition
		local radius = target.AbsoluteSize.X / 2
		local travel = radius - C.DotSizePx / 2
		if travel > 0 then
			local scale = Config.Cue.MaxSpinOffset / travel
			input:setSpin((localPoint.X - radius) * scale, (radius - localPoint.Y) * scale)
		end
	end
	local function chooseAngle(position: Vector3)
		local travel = column.AbsoluteSize.Y - C.AngleThumbHeightPx
		if travel > 0 then
			local fromTop = position.Y - column.AbsolutePosition.Y - C.AngleThumbHeightPx / 2
			local fraction = 1 - math.clamp(fromTop / travel, 0, 1)
			input:setElevation(lowest + fraction * (steepest - lowest))
		end
	end
	-- One drag at a time, on either control; `onAngle` says which.
	local onAngle = false
	target.InputBegan:Connect(function(object: InputObject)
		if self.enabled and input.spinEditing and active == nil and isPointer(object) then
			active, onAngle = object, false
			choose(object.Position)
		end
	end)
	column.InputBegan:Connect(function(object: InputObject)
		if self.enabled and input.spinEditing and active == nil and isPointer(object) then
			active, onAngle = object, true
			chooseAngle(object.Position)
		end
	end)
	-- Arrow keys step the angle while the panel is open (held repeats, like the D-pad).
	local heldKey: Enum.KeyCode? = nil
	UserInputService.InputBegan:Connect(function(object: InputObject)
		local code = object.KeyCode
		if
			self.enabled
			and input.spinEditing
			and (code == Enum.KeyCode.Up or code == Enum.KeyCode.Down)
		then
			heldKey = code
			input:holdElevation(if code == Enum.KeyCode.Up then 1 else -1)
		end
	end)
	UserInputService.InputChanged:Connect(function(object: InputObject)
		local drag = active
		if drag == nil or not self.enabled or not input.spinEditing then
			return
		end
		if
			object == drag
			or (
				drag.UserInputType == Enum.UserInputType.MouseButton1
				and object.UserInputType == Enum.UserInputType.MouseMovement
			)
		then
			if onAngle then
				chooseAngle(object.Position)
			else
				choose(object.Position)
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(object: InputObject)
		if object == active then
			active = nil
		end
		if heldKey ~= nil and object.KeyCode == heldKey then
			heldKey = nil
			input:holdElevation(0)
		end
	end)
	return self
end

function SpinSelector.setEnabled(self: SpinSelector, enabled: boolean)
	self.enabled = enabled
	self.toggle.Visible = enabled
	self.badge.Visible = enabled and self.input:getElevation() > Config.Cue.CueElevationDegrees
	if not enabled then
		self.input:setSpinEditing(false)
	end
end

return SpinSelector
