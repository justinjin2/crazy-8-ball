--!strict
-- RarityBar: the Cues menu's rarity bar (the cue card's, InventoryCard) on its own, for lists:
-- the Odds & Details' chances (designer, 2026-10-08: "just use the same bar as the cues
-- inventory with the odds next to it"). A round bar in its look's colours (Config.UI.CueCard
-- .Looks: Bar's top and bottom colours, or the colours a flowing bar goes through, Mythic's),
-- the card bar's thin ink ring and the white highlight along its top, its word at the left and
-- a value at the right, both white with the ink outline. An optional picture sits over the
-- bar's left end (a tier's block in the Mystery list), as a Ranked card's badge does.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CardMath = require(Shared:WaitForChild("CardMath"))
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)

local L = Config.UI.CueCard.Layout
local K = Config.UI.Kit

local RarityBar = {}

export type Bar = {
	frame: Frame,
	gradient: UIGradient,
	ring: UIStroke,
	highlight: Frame,
	word: TextLabel,
	value: TextLabel,
	icon: ImageLabel?,
}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

--- A bar (unpainted) in `parent`; `icon` puts a picture over its left end.
function RarityBar.new(parent: Instance, name: string, zIndex: number, icon: string?): Bar
	local frame = HudParts.frame(parent, name)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.ZIndex = zIndex
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Parent = frame
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Color = HudParts.color(K.Colors.Ink)
	ring.Transparency = L.BarRingTransparency
	ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ring.Parent = frame
	local highlight = HudParts.frame(frame, "Highlight")
	highlight.BackgroundTransparency = L.BarHighlight[4]
	highlight.BackgroundColor3 = Color3.new(1, 1, 1)
	highlight.Position = UDim2.fromScale(L.BarHighlight[1], L.BarHighlight[2])
	highlight.Size = UDim2.fromScale(1 - 2 * L.BarHighlight[1], L.BarHighlight[3])
	highlight.ZIndex = zIndex + 1
	local highlightRound = Instance.new("UICorner")
	highlightRound.CornerRadius = UDim.new(0.5, 0)
	highlightRound.Parent = highlight
	local word = HudParts.text(frame, "Word", K.Text.Min, "")
	word.TextXAlignment = Enum.TextXAlignment.Left
	word.TextWrapped = false
	word.TextTruncate = Enum.TextTruncate.AtEnd
	word.ZIndex = zIndex + 2
	local value = HudParts.text(frame, "Value", K.Text.Min, "")
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextWrapped = false
	value.ZIndex = zIndex + 2
	local bar: Bar = {
		frame = frame,
		gradient = gradient,
		ring = ring,
		highlight = highlight,
		word = word,
		value = value,
		icon = nil,
	}
	if icon and icon ~= "" then
		local picture = Instance.new("ImageLabel")
		picture.Name = "Icon"
		picture.BackgroundTransparency = 1
		picture.Image = icon
		picture.ScaleType = Enum.ScaleType.Fit
		picture.AnchorPoint = Vector2.new(0.5, 0.5)
		picture.ZIndex = zIndex + 3
		picture.Parent = parent
		bar.icon = picture
	end
	return bar
end

--- Colour the bar as a card of look `key` (a Config.UI.CueCard.Looks key: a rarity, Unique)
--- and set its words (the word in capitals, as the card's, unless `keepCase`).
function RarityBar.paint(bar: Bar, key: string, word: string, value: string, keepCase: boolean?)
	local look = CardMath.look(key)
	if look.Flow then
		local flow = {}
		for i, c in look.Flow do
			table.insert(flow, ColorSequenceKeypoint.new((i - 1) / (#look.Flow - 1), hex(c)))
		end
		bar.gradient.Color = ColorSequence.new(flow)
		bar.gradient.Rotation = 0
	else
		bar.gradient.Color = ColorSequence.new(hex(look.Bar[1]), hex(look.Bar[2]))
		bar.gradient.Rotation = 90
	end
	bar.word.Text = if keepCase then word else string.upper(word)
	bar.value.Text = value
end

--- Place the bar at (x, y), `w` by `h` pixels, its words `textPx` and `pad` in from its ends
--- (the picture, if any, centred on its left end and `iconPx` square).
function RarityBar.layout(
	bar: Bar,
	x: number,
	y: number,
	w: number,
	h: number,
	textPx: number,
	pad: number,
	iconPx: number?
)
	bar.frame.Position = UDim2.fromOffset(x, y)
	bar.frame.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
	bar.ring.Thickness = math.max(1, math.floor(h / 20 + 0.5))
	HudParts.setTextSize(bar.word, textPx)
	HudParts.setTextSize(bar.value, textPx)
	local valueW = math.ceil(ShopParts.textWidth(bar.value.Text, textPx)) + 6
	local left = pad
	local icon = bar.icon
	if icon and iconPx then
		icon.Position = UDim2.fromOffset(x + math.floor(h / 2 + 0.5), y + math.floor(h / 2 + 0.5))
		icon.Size = UDim2.fromOffset(iconPx, iconPx)
		left = math.floor(h / 2 + iconPx / 2 + 4)
	end
	bar.word.Position = UDim2.fromOffset(left, 0)
	bar.word.Size = UDim2.new(0, math.max(1, w - left - pad - valueW - 4), 1, 0)
	bar.value.Position = UDim2.new(1, -(pad + valueW), 0, 0)
	bar.value.Size = UDim2.new(0, valueW, 1, 0)
end

local STACK_INSET = 6 -- a small pill's words are this much narrower than it (pixels)

--- Whether a small pill `w` pixels wide holds its word and its value at `textPx` on one line
--- each (RarityBar.layoutStacked).
function RarityBar.stackedFits(bar: Bar, w: number, textPx: number): boolean
	local widest = math.max(
		ShopParts.textWidth(bar.word.Text, textPx),
		ShopParts.textWidth(bar.value.Text, textPx)
	)
	return widest <= w - STACK_INSET
end

--- Place the bar as a small pill (the Starter Pack's odds): its word over its value, both
--- centred, `textPx` tall.
function RarityBar.layoutStacked(
	bar: Bar,
	x: number,
	y: number,
	w: number,
	h: number,
	textPx: number
)
	bar.frame.Position = UDim2.fromOffset(x, y)
	bar.frame.Size = UDim2.fromOffset(math.max(1, w), math.max(1, h))
	bar.ring.Thickness = math.max(1, math.floor(h / 26 + 0.5))
	for index, label in { bar.word, bar.value } do
		HudParts.setTextSize(label, textPx)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(0.5, if index == 1 then 0.3 else 0.7)
		label.Size = UDim2.new(1, -STACK_INSET, 0.42, 0)
	end
end

--- Remove the bar and its picture.
function RarityBar.destroy(bar: Bar)
	bar.frame:Destroy()
	if bar.icon then
		bar.icon:Destroy()
	end
end

return RarityBar
