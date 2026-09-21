--!strict
-- UI: the in-match screen elements. Fine-aim nudge buttons, the leave button and a small
-- status line. Built to work with one thumb on a phone.
--
-- The power control is NOT here: it is a cue you drag, and it lives in PowerCue.luau. This
-- module owns the shared ScreenGui that it and everything else parents into.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UI = {}

local gui: ScreenGui? = nil
local statusLabel: TextLabel? = nil
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

--- The shared HUD layer. PowerCue parents into this rather than making a second ScreenGui,
--- so there is one place that decides what is on screen during a match.
function UI.screen(): ScreenGui
	return ensureGui()
end

--- Register a control built elsewhere so it hides and shows with the rest of the HUD.
function UI.addPlayControl(object: GuiObject)
	table.insert(playControls, object)
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
