--!strict
-- UI: screen elements. Milestone 1 has only a small debug readout in the corner.

local Players = game:GetService("Players")

local UI = {}

local debugLabel: TextLabel? = nil

local function ensureGui(): TextLabel
	if debugLabel then
		return debugLabel
	end
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "PoolHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = player:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Debug"
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Code
	label.TextSize = 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Position = UDim2.fromOffset(12, 12)
	label.Size = UDim2.fromOffset(360, 84)
	label.Text = ""
	label.Parent = gui

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 6)
	padding.Parent = label

	debugLabel = label
	return label
end

function UI.setDebugText(text: string)
	ensureGui().Text = text
end

return UI
