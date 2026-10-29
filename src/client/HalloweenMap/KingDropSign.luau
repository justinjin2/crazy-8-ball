--!strict
-- KingDropSign (Halloween 2026, hw-map lane): the sign over the Pumpkin King on his stage
-- (designer, 2026-10-29: "a popup near him showing the drop rate"): the drop cue's card art,
-- BEAT ME!, its chance and its name. Built here, on the client, on his throne figure (tagged
-- PumpkinKing by KingLook, named ThroneKing), so it goes when he leaves. Shown only while
-- Rules.kingDrop() is on (Config.Halloween.KingDrop, hw-core's) and hidden for a player who owns
-- the cue, rechecked on every Items snapshot (a win that drops it hides it at once). One looped
-- tween on the art tile (none with Reduce Motion); nothing per frame. Config.HalloweenMap.KingSign.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Rules = require(Shared:WaitForChild("HalloweenMap"):WaitForChild("Rules"))
local ItemState = require(script.Parent.Parent:WaitForChild("ItemState"))
local UIAnim = require(script.Parent.Parent:WaitForChild("UIAnim"))

local KS = Config.HalloweenMap.KingSign
local TAG = "PumpkinKing"

local KingDropSign = {}

type Sign = { gui: BillboardGui, pulse: Tween? }
local signs: { [Instance]: Sign } = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local INK = rgb(Config.UI.Kit.Colors.Ink)

-- Whether this player should see the sign: the Items snapshot has arrived and holds no copy of
-- the cue (an owner sees nothing to win; before the snapshot the sign waits hidden).
local function wanted(cue: string): boolean
	return ItemState.items() ~= nil and ItemState.cueCount(cue) == 0
end

local function label(
	parent: Instance,
	name: string,
	text: string,
	y: number,
	h: number,
	colour: Color3,
	stroke: number
)
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0.33, y)
	t.Size = UDim2.fromScale(0.63, h)
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = colour
	local outline = Instance.new("UIStroke")
	outline.Color = INK
	outline.Thickness = stroke
	outline.Parent = t
	t.Parent = parent
end

local function build(head: BasePart, drop: { Cue: string, Chance: number }): Sign
	local S = Strings.HalloweenMap
	local gui = Instance.new("BillboardGui")
	gui.Name = "KingDropSign"
	-- Anchored by its bottom edge on the name's centre; a clear strip of the name's half height
	-- plus GapPx under the card keeps it above the name's top at every distance (both in px).
	local name = head:FindFirstChild("KingName")
	local nameStuds, nameHalfPx = KS.NameFallback.Studs, KS.NameFallback.HalfPx
	if name and name:IsA("BillboardGui") then
		nameStuds = name.StudsOffsetWorldSpace.Y + name.Size.Y.Scale / 2
		nameHalfPx = name.Size.Y.Offset / 2
	end
	local clearPx = nameHalfPx + KS.GapPx
	gui.Size = UDim2.new(KS.SizeStuds[1], KS.MinPx[1], KS.SizeStuds[2], KS.MinPx[2] + clearPx)
	gui.SizeOffset = Vector2.new(0, 0.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, nameStuds, 0)
	gui.MaxDistance = KS.MaxDistance
	gui.LightInfluence = 0
	gui.Enabled = wanted(drop.Cue)

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, -clearPx)
	card.BackgroundColor3 = rgb(KS.Card)
	card.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.22, 0)
	corner.Parent = card
	local outline = Instance.new("UIStroke")
	outline.Color = INK
	outline.Thickness = KS.Strokes.Card
	outline.Parent = card
	local shade = Instance.new("UIGradient")
	shade.Color = ColorSequence.new(Color3.new(1, 1, 1), rgb(KS.Shade))
	shade.Rotation = 90
	shade.Parent = card

	-- the orange line just inside the ink
	local edge = Instance.new("Frame")
	edge.Name = "Edge"
	edge.BackgroundTransparency = 1
	edge.Size = UDim2.new(1, -10, 1, -10)
	edge.Position = UDim2.fromOffset(5, 5)
	edge.Parent = card
	local edgeCorner = Instance.new("UICorner")
	edgeCorner.CornerRadius = UDim.new(0.2, 0)
	edgeCorner.Parent = edge
	local edgeLine = Instance.new("UIStroke")
	edgeLine.Color = rgb(KS.Edge)
	edgeLine.Thickness = KS.Strokes.Edge
	edgeLine.Parent = edge

	-- the cue's card art on its tile, left
	local tile = Instance.new("Frame")
	tile.Name = "ArtTile"
	tile.BackgroundColor3 = rgb(KS.ArtTile)
	tile.Size = UDim2.fromScale(0.27, 0.8)
	tile.Position = UDim2.fromScale(0.035, 0.1)
	tile.Parent = card
	local tileCorner = Instance.new("UICorner")
	tileCorner.CornerRadius = UDim.new(0.25, 0)
	tileCorner.Parent = tile
	local tileLine = Instance.new("UIStroke")
	tileLine.Color = INK
	tileLine.Thickness = KS.Strokes.ArtTile
	tileLine.Parent = tile
	local art = Instance.new("ImageLabel")
	art.Name = "Art"
	art.BackgroundTransparency = 1
	art.Size = UDim2.fromScale(1.15, 1.15)
	art.Position = UDim2.fromScale(-0.075, -0.075)
	art.ScaleType = Enum.ScaleType.Fit
	art.Image = (Config.UI.Halloween.Art :: any)[drop.Cue] or ""
	art.Parent = tile
	local scale = Instance.new("UIScale")
	scale.Parent = tile

	local cueName = (Strings.Items.Cues :: any)[drop.Cue] or drop.Cue
	label(card, "Beat", S.KingDropBeat, 0.08, 0.25, rgb(KS.Beat), KS.Strokes.Beat)
	label(
		card,
		"Chance",
		S.KingDropChance:format(Rules.chanceText(drop.Chance)),
		0.32,
		0.34,
		rgb(KS.Chance),
		KS.Strokes.Chance
	)
	label(card, "Cue", string.upper(cueName), 0.66, 0.24, rgb(KS.CueName), KS.Strokes.CueName)

	local pulse: Tween? = nil
	if not UIAnim.reduced() then
		pulse = TweenService:Create(
			scale,
			TweenInfo.new(
				KS.PulseSeconds,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ Scale = KS.PulseScale }
		)
	end
	gui.Parent = head
	return { gui = gui, pulse = pulse }
end

-- Shows or hides every sign for this player (the pulse runs only while one shows).
local function refresh(drop: { Cue: string, Chance: number })
	local show = wanted(drop.Cue)
	for _, sign in signs do
		sign.gui.Enabled = show
		if sign.pulse then
			if show then
				sign.pulse:Play()
			else
				sign.pulse:Pause()
			end
		end
	end
end

local function attach(figure: Instance, drop: { Cue: string, Chance: number })
	if figure.Name ~= "ThroneKing" or signs[figure] then
		return
	end
	task.spawn(function()
		local head = figure:WaitForChild("Head", 5)
		if head then
			head:WaitForChild("KingName", 2) -- (the sign sits above it; a fallback without)
		end
		if
			not (head and head:IsA("BasePart"))
			or signs[figure]
			or not figure:IsDescendantOf(workspace)
		then
			return
		end
		signs[figure] = build(head, drop)
		refresh(drop)
	end)
end

local function detach(figure: Instance)
	local sign = signs[figure]
	if sign then
		signs[figure] = nil
		if sign.pulse then
			sign.pulse:Cancel()
		end
		sign.gui:Destroy()
	end
end

--- Watches for the King on his stage (MapClient calls it once, with the Boss on).
function KingDropSign.start()
	local drop = Rules.kingDrop()
	if not KS.Enabled or drop == nil then
		return
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(function(figure)
		attach(figure, drop)
	end)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(detach)
	for _, figure in CollectionService:GetTagged(TAG) do
		attach(figure, drop)
	end
	ItemState.Changed.Items:Connect(function()
		refresh(drop)
	end)
end

return KingDropSign
