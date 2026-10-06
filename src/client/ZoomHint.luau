--!strict
-- ZoomHint: a small guide on the left, just above the spin button, whenever it is your turn
-- to aim (designer, 2026-09-26): an icon and the word "Zoom" beside it, nothing behind them.
-- On a computer the icon is a mouse with its wheel and an up-and-down arrow, on a phone or
-- tablet a hand pinching, so players know the camera zooms and tilts down to the cue (the
-- tutorial explains it further). It follows the last input used, so a laptop with a touch
-- screen shows whichever the player is using. Hidden on a gamepad: the controller guide
-- (PadGuide) covers zoom there.
--
-- Gone for the rest of the session once the player zooms (designer, 2026-09-27): that shows
-- they know how. It comes back only when they rejoin.
--
-- Not a kit card on purpose (designer): transparent, just the icon and outlined words, both
-- greyed out and faint, so it reads as a control guide rather than a button to press.

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)

local ZoomHint = {}
ZoomHint.__index = ZoomHint

export type ZoomHint = typeof(setmetatable(
	{} :: {
		screen: ScreenGui,
		root: Frame,
		icon: ImageLabel,
		words: TextLabel,
		mode: string, -- "mouse", "touch" or "gamepad"
		wanted: boolean,
		dismissed: boolean, -- the player has zoomed this session
	},
	ZoomHint
))

-- Which guide fits the input the player is using now.
local function currentMode(): string
	local last = UserInputService:GetLastInputType()
	if last.Name:match("^Gamepad") then
		return "gamepad"
	elseif last == Enum.UserInputType.Touch then
		return "touch"
	elseif
		last == Enum.UserInputType.None
		and UserInputService.TouchEnabled
		and not UserInputService.MouseEnabled
	then
		return "touch" -- a phone before its first touch
	end
	return "mouse"
end

function ZoomHint.new(screen: ScreenGui): ZoomHint
	local root = Instance.new("Frame")
	root.Name = "ZoomHint"
	root.BackgroundTransparency = 1
	root.Parent = screen
	root.AnchorPoint = Vector2.new(0, 1)
	root.Visible = false
	local icon = HudParts.icon(root, "ScrollZoom")
	local words = HudParts.text(root, "Words", Config.UI.ZoomHint.TextSize, Strings.ZoomHint)
	words.TextWrapped = false
	words.TextXAlignment = Enum.TextXAlignment.Left
	-- Greyed out: a guide, not a button.
	local Z = Config.UI.ZoomHint
	local tint = Color3.fromRGB(Z.Tint[1], Z.Tint[2], Z.Tint[3])
	icon.ImageColor3 = tint
	icon.ImageTransparency = Z.IconTransparency
	words.TextColor3 = tint
	words.TextTransparency = Z.TextTransparency
	local outline = words:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Transparency = Z.OutlineTransparency
	end
	local self = setmetatable({
		screen = screen,
		root = root,
		icon = icon,
		words = words,
		mode = "",
		wanted = false,
		dismissed = false,
	}, ZoomHint)
	-- Both pictures up front, so switching input never shows an empty card.
	task.spawn(function()
		pcall(function()
			local Icons = Config.UI.Kit.Icons
			ContentProvider:PreloadAsync({ Icons.ScrollZoom, Icons.PinchZoom })
		end)
	end)
	self:refresh()
	UserInputService.LastInputTypeChanged:Connect(function()
		self:refresh()
	end)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
	end)
	return self
end

--- Pick the guide for the input in use, and lay it out.
function ZoomHint.refresh(self: ZoomHint)
	local mode = currentMode()
	if mode == self.mode then
		return
	end
	self.mode = mode
	local touch = mode == "touch"
	HudParts.setIcon(self.icon, if touch then "PinchZoom" else "ScrollZoom")
	self:layout()
	self:setVisible(self.wanted)
end

--- Size it for the screen (smaller on a phone on its side) and place it over the spin button.
function ZoomHint.layout(self: ZoomHint)
	local Z, Spin = Config.UI.ZoomHint, Config.UI.Spin
	local short = self.screen.AbsoluteSize.Y < Config.Multiplayer.Style.ShortHeight
	local iconSize = if short then Z.ShortIconPx else Z.IconPx
	local textSize = if short then Z.ShortTextSize else Z.TextSize
	local pad = Z.PaddingPx
	HudParts.setTextSize(self.words, textSize, textSize)
	local wordsWidth = TextService:GetTextSize(
		self.words.Text,
		textSize,
		HudParts.measureFont(self.words),
		Vector2.new(1000, 100)
	).X
	-- The icon at the spin button's left edge, the word beside it; room for the outline.
	local height = iconSize
	local wordsBox = wordsWidth + 8
	self.icon.AnchorPoint = Vector2.new(0, 0.5)
	self.icon.Position = UDim2.fromOffset(0, height / 2)
	self.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	self.words.Position = UDim2.fromOffset(iconSize + pad, 0)
	self.words.Size = UDim2.fromOffset(wordsBox, height)
	self.root.Size = UDim2.fromOffset(iconSize + pad + wordsBox, height)
	self.root.Position = UDim2.new(0, Spin.ToggleMarginPx, 0.5, -(Spin.ToggleSizePx / 2 + Z.GapPx))
end

--- Shown while it is the player's turn to aim (Main); never on a gamepad for now.
function ZoomHint.setVisible(self: ZoomHint, visible: boolean)
	self.wanted = visible
	self.root.Visible = visible and self.mode ~= "gamepad" and not self.dismissed
end

--- The player zoomed (Main): they know how, so it stays hidden for the rest of the session.
function ZoomHint.dismiss(self: ZoomHint)
	self.dismissed = true
	self.root.Visible = false
end

return ZoomHint
