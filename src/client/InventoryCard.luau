--!strict
-- InventoryCard: a cue's card in the Inventory (docs/prompts/ECONOMY_UI_PROMPT.md section 11),
-- for the Cues tab's grid and the Index's cells, plus the plain pale-edged box the Inventory's
-- panels and rows sit in.
--
-- A card is a white rounded card like MenuFrame.tile, dressed in the cue's rarity
-- (CueThumb.dress: a coloured edge, a wash and a strip; Mythic's shimmer, Secret's glow; a rank
-- cue in its tier's colour), with the cue's tinted thumbnail (CueThumb) on top and its name
-- under it on up to two lines (it wraps rather than shrinks, so a longer translation still
-- fits). Pills sit over the top corners: a gold NEW top left; top right a padlock on Exclusive
-- and Unique cues and the count ("x3", or a Unique cue's "#412"); and a green "Equipped" on
-- the picture's bottom, just over the name. A never-owned cue in the Index is a big "?" in its
-- rarity's colour where the picture goes (designer, 2026-09-28: the look stays hidden until
-- the cue is found; the Index's detail panel shows its black 3D shape), no name, no dressing
-- and no pills.
--
-- It behaves like the kit's buttons: hover and gamepad selection give the gold outline and a
-- small grow, a press squishes it and plays the Click sound. `onSelect` runs when a gamepad
-- lands on it. The card whose details show (setChosen) keeps a thick blue outline (the house
-- accent for whatever is chosen, UI_STYLE section 4). Sizes in Config.UI.Inventory.Card.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Progression"):WaitForChild("Catalog"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local MenuFrame = require(script.Parent.MenuFrame)
local UISound = require(script.Parent.UISound)

local IC = Config.UI.Inventory.Card
local CARD = Config.UI.Menu.Card
local K = Config.UI.Kit
local WORDS = Strings.Menus.Inventory
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local QUICK = Config.Multiplayer.Style.QuickMotion
local color = HudParts.color
local tone = HudParts.tone
local WHITE = tone("White")
local EDGE = color(CARD.EdgeColor)

export type Fields = {
	cueId: string,
	silhouette: boolean?, -- the Index: never owned (a big "?", no name)
	count: string?, -- "x3", "#412", or nil / "" for none
	new: boolean?, -- the gold NEW pill
	equipped: boolean?, -- the green Equipped pill
}

export type Options = {
	name: string?, -- the Instance's name
	order: number?, -- LayoutOrder in a grid
	onPress: () -> (),
	onSelect: (() -> ())?, -- a gamepad landed on it
	lines: number?, -- lines the name may wrap to (Card.NameLines by default)
}

export type Card = {
	button: TextButton,
	body: Frame,
	fill: Frame,
	edge: UIStroke,
	art: Frame,
	thumb: Frame,
	name: TextLabel,
	unknown: TextLabel,
	newPill: Frame,
	newText: TextLabel,
	countPill: Frame,
	countText: TextLabel,
	equipPill: Frame,
	equipText: TextLabel,
	lock: ImageLabel,
	dressing: CueThumb.Dressing?,
	dressKey: string, -- what the dressing shows now ("" for none)
	cueId: string,
	silhouette: boolean,
	lines: number, -- lines the name may wrap to
	lit: boolean, -- hovered or selected by a gamepad
	chosen: boolean, -- its details show
	down: boolean,
	tween: Tween?,
	press: UIScale,
}

local InventoryCard = {}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function textWidth(text: string, size: number): number
	return TextService:GetTextSize(text, size, FONT, Vector2.new(4000, 400)).X
end

--- The plain box the Inventory's panels and rows sit in: a white rounded card with a pale edge
--- and a soft fade (like the roadmap's reward tiles and MenuFrame.tile), no shadow or ink.
function InventoryCard.box(parent: Instance, name: string): Frame
	local box = HudParts.frame(parent, name)
	box.BackgroundTransparency = 0
	box.BackgroundColor3 = WHITE
	HudParts.corner(box, IC.CornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = EDGE
	edge.Thickness = IC.StrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = box
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, color(K.PanelFade))
	fade.Parent = box
	return box
end

--- A small pill with one word (NEW, Equipped, "x3"): `tint` its fill; white words with an ink
--- outline, or ink words (`inkWords`) on a white pill.
function InventoryCard.pill(
	parent: Instance,
	name: string,
	tint: Color3,
	text: string,
	inkWords: boolean?
): (Frame, TextLabel)
	local pill = HudParts.pill(parent, name, tint)
	local words = if inkWords
		then HudParts.note(pill, "Words", IC.PillTextPx, text)
		else HudParts.text(pill, "Words", IC.PillTextPx, text)
	words.TextWrapped = false
	words.Size = UDim2.fromScale(1, 1)
	words.ZIndex = 2
	return pill, words
end

--- A pill's width for its words at `size` (Card.PillTextPx by default) with room each side.
function InventoryCard.pillWidth(text: string, height: number, size: number?): number
	return math.max(height, math.ceil(textWidth(text, size or IC.PillTextPx)) + 2 * IC.PillPadPx)
end

-- The outline: gold while hovered or selected, blue while chosen, else pale.
local function paintEdge(card: Card)
	if card.lit then
		card.edge.Color = tone("Gold")
		card.edge.Thickness = K.SelectedStrokePx
	elseif card.chosen then
		card.edge.Color = tone("Blue")
		card.edge.Thickness = IC.ChosenStrokePx
	else
		card.edge.Color = EDGE
		card.edge.Thickness = IC.StrokePx
	end
end

local function settle(card: Card)
	if card.tween then
		card.tween:Cancel()
	end
	local scale = if card.down then K.PressedScale elseif card.lit then K.SelectedScale else 1
	local tween = TweenService:Create(
		card.press,
		TweenInfo.new(QUICK, Enum.EasingStyle.Quad),
		{ Scale = scale }
	)
	card.tween = tween
	tween:Play()
end

--- Lay the card's parts out from its size (it does this itself when its size changes).
function InventoryCard.layout(card: Card)
	local size = card.button.AbsoluteSize / MenuFrame.scaleOf(card.button)
	local w, h = size.X, size.Y
	if w <= 0 or h <= 0 then
		return
	end
	local pad = math.max(3, round(w * IC.PadShare))
	local lineH = IC.NameTextPx + 3
	local nameH = lineH * card.lines
	local bottom = round(h * IC.BottomShare)
	local art =
		math.max(1, math.min(w - 2 * pad, round(h * IC.ArtShare), h - pad - nameH - bottom - 2))
	card.art.Size = UDim2.fromOffset(art, art)
	card.art.Position = UDim2.fromOffset(round(w / 2), pad)
	local nameTop = pad + art + 2
	local nameBox = math.max(lineH, h - nameTop - bottom)
	card.name.Position = UDim2.fromOffset(pad, nameTop)
	card.name.Size = UDim2.fromOffset(math.max(1, w - 2 * pad), nameBox)
	-- The "?" fills the picture's place (and the name's, which it has none of).
	local mark = math.max(1, math.min(w - 2 * pad, h - 2 * pad - bottom))
	card.unknown.Position = UDim2.fromOffset(round(w / 2), round((h - bottom) / 2))
	card.unknown.Size = UDim2.fromOffset(mark, mark)
	HudParts.setTextSize(card.unknown, math.max(IC.NameTextPx, round(mark * IC.UnknownShare)))

	-- The pills: NEW top left; the lock and the count top right; Equipped on the picture's
	-- bottom, a little over the name.
	local inset = IC.InsetPx
	local pillH = IC.PillPx
	card.newPill.Position = UDim2.fromOffset(inset, inset)
	card.newPill.Size = UDim2.fromOffset(InventoryCard.pillWidth(card.newText.Text, pillH), pillH)
	local right = w - inset
	if card.lock.Visible then
		card.lock.Position = UDim2.fromOffset(right - IC.LockPx, inset)
		card.lock.Size = UDim2.fromOffset(IC.LockPx, IC.LockPx)
		right -= IC.LockPx + 2
	end
	local countW = InventoryCard.pillWidth(card.countText.Text, pillH)
	card.countPill.Position = UDim2.fromOffset(right - countW, inset)
	card.countPill.Size = UDim2.fromOffset(countW, pillH)
	local equipW = math.min(w - 2 * inset, InventoryCard.pillWidth(card.equipText.Text, pillH))
	card.equipPill.Position = UDim2.fromOffset(round(w / 2), nameTop - IC.EquipGapPx)
	card.equipPill.Size = UDim2.fromOffset(equipW, pillH)
end

--- A card (empty until set). Size it yourself or put it in a grid.
function InventoryCard.new(parent: Instance, opts: Options): Card
	local button = Instance.new("TextButton")
	button.Name = opts.name or "Card"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.LayoutOrder = opts.order or 0
	button.Selectable = true
	local noBox = Instance.new("Frame") -- the gold outline shows selection, not Roblox's box
	noBox.BackgroundTransparency = 1
	button.SelectionImageObject = noBox
	local body = HudParts.frame(button, "Body")
	body.AnchorPoint = Vector2.new(0.5, 0.5)
	body.Position = UDim2.fromScale(0.5, 0.5)
	body.Size = UDim2.fromScale(1, 1)
	local press = Instance.new("UIScale")
	press.Name = "Press"
	press.Parent = body
	local fill = InventoryCard.box(body, "Fill")
	fill.Size = UDim2.fromScale(1, 1)
	fill.ZIndex = 0
	local edge = fill:FindFirstChild("Edge") :: UIStroke
	local art = HudParts.frame(body, "Art")
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.ZIndex = 3
	local thumb = CueThumb.new(art, Catalog.Default)
	local name = HudParts.text(body, "Name", IC.NameTextPx, "")
	name.TextWrapped = true
	name.TextYAlignment = Enum.TextYAlignment.Top
	name.ZIndex = 4
	local unknown = HudParts.text(body, "Unknown", IC.NameTextPx, WORDS.Unknown)
	unknown.TextWrapped = false
	unknown.AnchorPoint = Vector2.new(0.5, 0.5)
	unknown.ZIndex = 4
	unknown.Visible = false
	local newPill, newText = InventoryCard.pill(body, "New", tone("Gold"), WORDS.New)
	newPill.ZIndex = 6
	newPill.Visible = false
	local countPill, countText = InventoryCard.pill(body, "Count", WHITE, "", true)
	countText.AutoLocalize = false -- a number
	countPill.ZIndex = 6
	countPill.Visible = false
	local equipPill, equipText = InventoryCard.pill(body, "Equipped", tone("Green"), WORDS.Equipped)
	equipPill.AnchorPoint = Vector2.new(0.5, 1)
	equipPill.ZIndex = 6
	equipPill.Visible = false
	local lock = HudParts.icon(body, "Lock", "Lock")
	lock.ZIndex = 6
	lock.Visible = false
	button.Parent = parent

	local card: Card = {
		button = button,
		body = body,
		fill = fill,
		edge = edge,
		art = art,
		thumb = thumb,
		name = name,
		unknown = unknown,
		newPill = newPill,
		newText = newText,
		countPill = countPill,
		countText = countText,
		equipPill = equipPill,
		equipText = equipText,
		lock = lock,
		dressing = nil,
		dressKey = "",
		cueId = "",
		silhouette = false,
		lines = opts.lines or IC.NameLines,
		lit = false,
		chosen = false,
		down = false,
		tween = nil,
		press = press,
	}
	button:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		InventoryCard.layout(card)
	end)

	-- Hover, gamepad selection and press, like the kit's candy buttons.
	local function light(on: boolean)
		card.lit = on
		paintEdge(card)
		settle(card)
	end
	button.MouseEnter:Connect(function()
		light(true)
	end)
	button.MouseLeave:Connect(function()
		card.down = false
		light(false)
	end)
	button.SelectionGained:Connect(function()
		light(true)
		if opts.onSelect then
			opts.onSelect()
		end
	end)
	button.SelectionLost:Connect(function()
		light(false)
	end)
	button.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
			or input.KeyCode == Enum.KeyCode.ButtonA
		then
			card.down = true
			settle(card)
		end
	end)
	button.InputEnded:Connect(function()
		card.down = false
		settle(card)
	end)
	button.Activated:Connect(function()
		UISound.play("Click")
		opts.onPress()
	end)
	InventoryCard.layout(card)
	return card
end

--- Show a cue on the card (or its silhouette), with its pills.
function InventoryCard.set(card: Card, fields: Fields)
	local id = fields.cueId
	local silhouette = fields.silhouette == true
	if id ~= card.cueId or silhouette ~= card.silhouette then
		CueThumb.set(card.thumb, id, false)
		card.cueId, card.silhouette = id, silhouette
	end
	card.thumb.Visible = not silhouette
	local row = Catalog.get(id)
	local rarity = if row then row.Rarity else "Default"
	local tier = if row and row.Tier then row.Tier else ""
	local key = if silhouette then "" else rarity .. "/" .. tier
	if key ~= card.dressKey then
		if card.dressing then
			card.dressing.destroy()
			card.dressing = nil
		end
		if not silhouette then
			local tint = if tier ~= "" then CueThumb.cueColor(id) else nil
			card.dressing = CueThumb.dress(card.fill, rarity, tint)
		end
		card.dressKey = key
	end
	card.name.Text = if silhouette then "" else CueThumb.cueName(id)
	card.name.Visible = not silhouette
	card.unknown.Visible = silhouette
	card.unknown.TextColor3 = CueThumb.accentColor(rarity)
	local count = if silhouette then "" else fields.count or ""
	card.countText.Text = count
	card.countPill.Visible = count ~= ""
	card.newPill.Visible = fields.new == true and not silhouette
	card.equipPill.Visible = fields.equipped == true and not silhouette
	card.lock.Visible = not silhouette
		and row ~= nil
		and (row.Group == "Exclusive" or row.Group == "Unique")
	InventoryCard.layout(card)
end

--- Mark the card whose details show (a thick blue outline).
function InventoryCard.setChosen(card: Card, chosen: boolean)
	if card.chosen ~= chosen then
		card.chosen = chosen
		paintEdge(card)
	end
end

--- Take the card away (its dressing's loop stops with it).
function InventoryCard.destroy(card: Card)
	if card.dressing then
		card.dressing.destroy()
		card.dressing = nil
	end
	card.button:Destroy()
end

return InventoryCard
