--!strict
-- A full-disc spin control with pointer dragging and a gamepad modifier.
-- Input owns the chosen spin and modal lock; this module only draws and edits that value.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Input = require(script.Parent.Input)

local SpinSelector = {}
SpinSelector.__index = SpinSelector

export type SpinSelector = typeof(setmetatable(
	{} :: {
		root: Frame,
		toggle: TextButton,
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

local function button(parent: GuiObject, name: string, text: string): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Text = text
	item.TextSize = Config.UI.Spin.TextSizePx
	item.TextColor3 = Color3.new(1, 1, 1)
	item.Font = Enum.Font.GothamBold
	item.BackgroundColor3 = rgb(Config.UI.Panel)
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
	return item
end

local function dot(parent: GuiObject): Frame
	local item = Instance.new("Frame")
	item.Name = "StrikePoint"
	item.AnchorPoint = Vector2.new(0.5, 0.5)
	item.Size = UDim2.fromOffset(Config.UI.Spin.DotSizePx, Config.UI.Spin.DotSizePx)
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
	blocker.BackgroundColor3 = Color3.new(0, 0, 0)
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
	-- The decoration must not steal the toggle's pointer or gamepad selection.
	icon.Active = false
	icon.Selectable = false
	local iconDot = dot(icon)

	local panel = Instance.new("Frame")
	panel.Name = "SpinPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.BorderSizePixel = 0
	panel.Active = false -- empty space lets the backdrop receive outside clicks
	panel.ZIndex = toggle.ZIndex + 1
	panel.Visible = false
	panel.Parent = root
	local panelWidth = C.PanelWidthPx
	local y = C.MarginPx
	local target = ball(panel, "StrikeTarget", C.BallSizePx)
	target.AnchorPoint = Vector2.new(0.5, 0)
	target.Position = UDim2.new(0.5, 0, 0, y)
	target.Selectable = false
	local strikeDot = dot(target)
	y += C.BallSizePx + C.GapPx

	local actionWidth = (panelWidth - C.MarginPx * 2 - C.GapPx) / 2
	local reset = button(panel, "Center", S.Center)
	reset.Position = UDim2.fromOffset(C.MarginPx, y)
	reset.Size = UDim2.fromOffset(actionWidth, C.ButtonSizePx)
	reset.BackgroundColor3 = rgb(C.CenterColor)
	local done = button(panel, "Done", S.Done)
	done.Position = UDim2.fromOffset(C.MarginPx + actionWidth + C.GapPx, y)
	done.Size = UDim2.fromOffset(actionWidth, C.ButtonSizePx)
	done.BackgroundColor3 = rgb(Config.UI.Accent)
	done.TextColor3 = rgb(Config.UI.Panel)
	local actionsY = y
	local fullHeight = y + C.ButtonSizePx + C.MarginPx
	local function layout()
		-- Shrink only the ball on short landscape phones; button targets remain 44 px.
		local ballSize = math.clamp(
			root.AbsoluteSize.Y - (fullHeight - C.BallSizePx) - C.MarginPx * 2,
			C.ButtonSizePx,
			C.BallSizePx
		)
		local delta = ballSize - C.BallSizePx
		target.Size = UDim2.fromOffset(ballSize, ballSize)
		reset.Position = UDim2.new(reset.Position.X, UDim.new(0, actionsY + delta))
		done.Position = UDim2.new(done.Position.X, UDim.new(0, actionsY + delta))
		panel.Size = UDim2.fromOffset(panelWidth, fullHeight + delta)
	end
	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()

	local self = setmetatable({
		root = root,
		toggle = toggle,
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
		iconDot.Position = position
	end
	input:onSpin(refresh)
	refresh(input.spinX, input.spinY)
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
	target.InputBegan:Connect(function(object: InputObject)
		if self.enabled and input.spinEditing and active == nil and isPointer(object) then
			active = object
			choose(object.Position)
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
			choose(object.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(object: InputObject)
		if object == active then
			active = nil
		end
	end)
	return self
end

function SpinSelector.setEnabled(self: SpinSelector, enabled: boolean)
	self.enabled = enabled
	self.toggle.Visible = enabled
	if not enabled then
		self.input:setSpinEditing(false)
	end
end

return SpinSelector
