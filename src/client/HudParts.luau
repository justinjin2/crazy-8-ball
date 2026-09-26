--!strict
-- HudParts: the building blocks every match screen is made of (MatchHUD, QueueMenu), so
-- they share one look: dark gradient panels, rounded corners, thin borders, and buttons
-- that press in and light their border when hovered or selected with a gamepad.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local S = Config.Multiplayer.Style
local HudParts = {}

function HudParts.color(values: { number }): Color3
	return Color3.fromRGB(values[1], values[2], values[3])
end

function HudParts.frame(parent: Instance, name: string): Frame
	local object = Instance.new("Frame")
	object.Name = name
	object.BorderSizePixel = 0
	object.BackgroundTransparency = 1
	object.Parent = parent
	return object
end

function HudParts.corner(parent: Instance, radius: number)
	local object = Instance.new("UICorner")
	object.CornerRadius = UDim.new(0, radius)
	object.Parent = parent
end

function HudParts.outline(parent: Instance, tint: Color3, thickness: number): UIStroke
	local object = Instance.new("UIStroke")
	object.Color = tint
	object.Thickness = thickness
	object.Transparency = 0.3
	object.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	object.Parent = parent
	return object
end

function HudParts.label(parent: Instance, name: string, size: number, text: string): TextLabel
	local object = Instance.new("TextLabel")
	object.Name = name
	object.BackgroundTransparency = 1
	object.Font = Enum.Font.GothamMedium
	object.TextSize = size
	object.TextColor3 = HudParts.color(S.Text)
	object.Text = text
	object.TextTruncate = Enum.TextTruncate.AtEnd
	object.Parent = parent
	return object
end

function HudParts.panel(parent: Instance, name: string): Frame
	local object = HudParts.frame(parent, name)
	object.BackgroundTransparency = 0.06
	object.BackgroundColor3 = HudParts.color(S.Panel)
	HudParts.corner(object, S.Radius)
	HudParts.outline(object, HudParts.color(S.Border), 1)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(HudParts.color(S.PanelTop), HudParts.color(S.Panel))
	gradient.Rotation = 90
	gradient.Parent = object
	return object
end

function HudParts.button(parent: Instance, text: string, action: () -> ()): TextButton
	local object = Instance.new("TextButton")
	object.BackgroundColor3 = HudParts.color(S.PanelTop)
	object.BorderSizePixel = 0
	object.AutoButtonColor = false
	object.Font = Enum.Font.GothamBold
	object.TextSize = S.StatusSize
	object.TextColor3 = HudParts.color(S.Text)
	object.Text = text
	object.Selectable = true
	object.Parent = parent
	HudParts.corner(object, S.Radius / 2)
	local border = HudParts.outline(object, HudParts.color(S.Border), 1)
	local pressScale = Instance.new("UIScale")
	pressScale.Parent = object
	local pressTween: Tween? = nil
	local function pressed(down: boolean)
		if pressTween then
			pressTween:Cancel()
		end
		local nextTween = TweenService:Create(
			pressScale,
			TweenInfo.new(S.QuickMotion),
			{ Scale = if down then S.PressedScale else 1 }
		)
		pressTween = nextTween
		nextTween:Play()
	end
	object.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			pressed(true)
		end
	end)
	object.InputEnded:Connect(function()
		pressed(false)
	end)
	object.MouseLeave:Connect(function()
		pressed(false)
	end)
	local running: Tween? = nil
	local function highlight(selected: boolean)
		if running then
			running:Cancel()
		end
		local nextTween = TweenService:Create(border, TweenInfo.new(S.QuickMotion), {
			Color = HudParts.color(if selected then S.Selected else S.Border),
			Transparency = if selected then 0 else 0.3,
		})
		running = nextTween
		nextTween:Play()
	end
	object.MouseEnter:Connect(function()
		highlight(true)
	end)
	object.MouseLeave:Connect(function()
		highlight(false)
	end)
	object.SelectionGained:Connect(function()
		highlight(true)
	end)
	object.SelectionLost:Connect(function()
		highlight(false)
	end)
	object.Activated:Connect(action)
	return object
end

return HudParts
