--!strict
-- UI: the in-match screen elements. Power bar (press, pull down, release), fine-aim nudge
-- buttons, and a small status line. Built to work with one thumb on a phone.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UI = {}

local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
local powerFill: Frame? = nil
local powerText: TextLabel? = nil
local playControls: { GuiObject } = {}
local leaveButton: TextButton? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ensureGui(): ScreenGui
	if gui then
		return gui
	end
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "PoolHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false -- keep clear of Roblox's top bar on phones
	screen.Parent = player:WaitForChild("PlayerGui")
	gui = screen
	return screen
end

local function styleButton(button: TextButton)
	button.BackgroundColor3 = rgb(Config.UI.Panel)
	button.BackgroundTransparency = Config.UI.PanelTransparency
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 22
	button.AutoButtonColor = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
end

--- Status line in the top-left corner.
function UI.setStatus(text: string)
	if not statusLabel then
		local label = Instance.new("TextLabel")
		label.Name = "Status"
		label.BackgroundColor3 = rgb(Config.UI.Panel)
		label.BackgroundTransparency = Config.UI.PanelTransparency
		label.TextColor3 = Color3.new(1, 1, 1)
		label.Font = Enum.Font.Gotham
		label.TextSize = 16
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Position = UDim2.fromOffset(12, 12)
		label.Size = UDim2.fromOffset(360, 64)
		label.Parent = ensureGui()
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, 8)
		padding.PaddingTop = UDim.new(0, 6)
		padding.Parent = label
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = label
		statusLabel = label
	end
	(statusLabel :: TextLabel).Text = text
end

--- Show or hide everything that only makes sense while playing at the table.
function UI.setPlayControlsVisible(visible: boolean)
	for _, item in playControls do
		item.Visible = visible
	end
	if statusLabel then
		statusLabel.Visible = visible
	end
	if leaveButton then
		leaveButton.Visible = visible
	end
end

--- A "Leave table" button in the top-right corner.
function UI.createLeaveButton(onLeave: () -> ())
	local button = Instance.new("TextButton")
	button.Name = "Leave"
	button.Text = "Leave table"
	button.AnchorPoint = Vector2.new(1, 0)
	button.Position = UDim2.new(1, -18, 0, 12)
	button.Size = UDim2.fromOffset(120, 40)
	styleButton(button)
	button.TextSize = 16
	button.Visible = false
	button.Parent = ensureGui()
	button.Activated:Connect(onLeave)
	leaveButton = button
end

--- Power bar on the right edge. onPull(0..1) while pulling, onRelease() when let go.
function UI.createPowerBar(onPull: (number) -> (), onRelease: () -> ())
	local U = Config.UI
	local bar = Instance.new("TextButton")
	bar.Name = "PowerBar"
	bar.Text = ""
	bar.AnchorPoint = Vector2.new(1, 0.5)
	bar.Position = UDim2.new(1, -U.PowerBarRightMarginPx, 0.5, 0)
	-- Height follows the screen so the whole bar (and the full pull) fits a phone.
	bar.Size = UDim2.new(0, U.PowerBarWidthPx, U.PowerBarHeightFraction, 0)
	local sizeLimit = Instance.new("UISizeConstraint")
	sizeLimit.MinSize = Vector2.new(U.PowerBarWidthPx, U.PowerBarMinHeightPx)
	sizeLimit.MaxSize = Vector2.new(U.PowerBarWidthPx, U.PowerBarMaxHeightPx)
	sizeLimit.Parent = bar
	bar.BackgroundColor3 = rgb(U.Panel)
	bar.BackgroundTransparency = U.PanelTransparency
	bar.AutoButtonColor = false
	bar.Parent = ensureGui()
	table.insert(playControls, bar)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = bar
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = bar

	-- Fill grows from the top as the player pulls down.
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = rgb(U.Accent)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(1, 0)
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 12)
	fillCorner.Parent = fill
	powerFill = fill

	local text = Instance.new("TextLabel")
	text.Name = "Percent"
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, 0, 0, 24)
	text.Position = UDim2.new(0, 0, 1, 4)
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Font = Enum.Font.GothamBold
	text.TextSize = 14
	text.Text = "PULL"
	text.Parent = bar
	powerText = text

	local active: InputObject? = nil
	local startY = 0

	bar.InputBegan:Connect(function(input: InputObject)
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
		local same = input == a
			or (
				a.UserInputType == Enum.UserInputType.MouseButton1
				and input.UserInputType == Enum.UserInputType.MouseMovement
			)
		if same then
			local pullDistance = bar.AbsoluteSize.Y * Config.Input.PowerPullBarFraction
			local pull = math.clamp((input.Position.Y - startY) / pullDistance, 0, 1)
			onPull(pull)
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

--- Reflect the current pull on the bar (nil = idle).
function UI.setPower(pull: number?)
	if powerFill then
		powerFill.Size = UDim2.fromScale(1, pull or 0)
	end
	if powerText then
		powerText.Text = if pull then ("%d%%"):format(math.floor(pull * 100 + 0.5)) else "PULL"
	end
end

--- Two nudge buttons at the bottom centre. onNudge(-1 or 1) per tap, repeating while held.
function UI.createNudgeButtons(onNudge: (number) -> ())
	local size = Config.UI.NudgeButtonPx
	for _, dir in { -1, 1 } do
		local button = Instance.new("TextButton")
		button.Name = if dir < 0 then "NudgeLeft" else "NudgeRight"
		button.Text = if dir < 0 then "<" else ">"
		button.AnchorPoint = Vector2.new(0.5, 1)
		button.Position = UDim2.new(0.5, dir * (size * 0.75), 1, -18)
		button.Size = UDim2.fromOffset(size, size)
		styleButton(button)
		button.Parent = ensureGui()
		table.insert(playControls, button)

		local holding = false
		button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType ~= Enum.UserInputType.MouseButton1
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			holding = true
			-- Screen-left button turns the aim clockwise (negative), matching a drag to the left.
			onNudge(-dir)
			task.spawn(function()
				task.wait(Config.Input.NudgeRepeatDelay)
				while holding do
					onNudge(-dir)
					task.wait(Config.Input.NudgeRepeatInterval)
				end
			end)
		end)
		local function stop()
			holding = false
		end
		button.InputEnded:Connect(stop)
		button.MouseLeave:Connect(stop)
	end
end

return UI
