--!strict
-- UltSlots: the three slot cards on the left of the ult spin screen (docs/prompts/
-- ULTIMATES_PROMPT.md sections 8 and 9.3; reference 09). Each is a white kit card: the ult's
-- icon top left (ABILITIES_PROMPT 5.1), its name (white, ink outline) and a strip in its rarity
-- colour to the icon's right, and along the bottom EQUIPPED (green,
-- the selected slot: the one played in matches) or SELECT (blue); a lock toggle top right (a
-- locked slot cannot be spun into). A slot not owned yet reads NONE with a green PURCHASE and
-- its R$ price (and a small "Soon" while the pass's id is 0). The whole card is the button:
-- a press selects an owned slot or asks to buy one not owned; the lock is its own button. On a
-- phone the cards are small and stacked in a compact column (Config.UI.UltScreen.Short).
--
-- Every press goes to the server through the screen's hooks (Select, Lock, BuyProduct).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local W = Strings.Ults.Screen
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local GREEN = HudParts.tone("Green")

export type Hooks = {
	select: (slot: number) -> (),
	lock: (slot: number, locked: boolean) -> (),
	purchase: (slot: number) -> (),
}

type Card = {
	slot: number,
	button: TextButton,
	body: Frame, -- everything drawn: it grows when hovered or selected
	edge: UIStroke,
	icon: ImageLabel, -- the ult's icon (hidden on an empty or unowned slot)
	name: TextLabel,
	strip: Frame,
	pill: Frame,
	pillText: TextLabel,
	soon: Frame,
	soonText: TextLabel,
	lock: TextButton,
	lockIcon: ImageLabel,
	lit: boolean,
	lockLit: boolean,
	owned: boolean,
	selected: boolean,
	locked: boolean,
}

local UltSlots = {}
UltSlots.__index = UltSlots

-- The card's outline: gold while hovered or selected by a gamepad, green on the equipped slot.
local function paintEdge(card: Card)
	if card.lit then
		card.edge.Color = GOLD
		card.edge.Thickness = K.SelectedStrokePx
	elseif card.selected then
		card.edge.Color = GREEN
		card.edge.Thickness = K.SelectedStrokePx
	else
		card.edge.Color = INK
		card.edge.Thickness = K.PanelStrokePx
	end
	UIAnim.scaleOf(card.body).Scale = if card.lit then K.SelectedScale else 1
end

local function paintLock(card: Card)
	card.lockIcon.ImageTransparency = if card.locked then 0 else C.LockOffTransparency
	card.lockIcon.ImageColor3 = if card.lockLit then GOLD else Color3.new(1, 1, 1)
	UIAnim.scaleOf(card.lockIcon).Scale = if card.lockLit then 1.2 else 1
end

--- The three cards in `parent` (the screen's root).
function UltSlots.new(parent: Instance, hooks: Hooks): any
	local self: any = setmetatable({}, UltSlots)
	self.hooks = hooks
	self.cards = {} :: { Card }
	local holder = HudParts.frame(parent, "Slots")
	holder.ZIndex = 5
	self.holder = holder
	for slot = 1, Config.Ults.Slots do
		table.insert(self.cards, self:build(holder, slot))
	end
	return self
end

function UltSlots.build(self: any, parent: Instance, slot: number): Card
	local button = Instance.new("TextButton")
	button.Name = "Slot" .. slot
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Selectable = true
	button.SelectionImageObject = Parts.noBox()
	button.ZIndex = 2
	button.Parent = parent
	local body = HudParts.frame(button, "Body")
	body.Size = UDim2.fromScale(1, 1)
	local cardFrame = HudParts.card(body, "Card", K.ButtonCornerPx + 2)
	cardFrame.Size = UDim2.fromScale(1, 1)
	local fill = cardFrame:FindFirstChild("Fill") :: Frame
	local edge = fill:FindFirstChild("Edge") :: UIStroke
	local icon = HudParts.icon(body, "", "UltIcon")
	icon.Visible = false
	icon.ZIndex = 3
	local name = HudParts.text(body, "Name", C.Full.SlotNameTextPx, W.None)
	name.ZIndex = 3
	local strip = HudParts.frame(body, "Strip")
	strip.BackgroundTransparency = 0
	strip.ZIndex = 3
	HudParts.corner(strip, K.PillCornerPx)
	local pill = HudParts.pill(body, "Pill", GREEN)
	pill.ZIndex = 3
	local pillText = HudParts.text(pill, "Words", C.Full.SlotPillTextPx, "")
	pillText.TextWrapped = false
	pillText.ZIndex = 4
	local soon = HudParts.pill(body, "Soon", GOLD)
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.ZIndex = 5
	soon.Visible = false
	local soonText = HudParts.text(soon, "Words", K.Text.Min, W.Soon)
	soonText.TextWrapped = false
	soonText.Size = UDim2.fromScale(1, 1)
	soonText.ZIndex = 6

	local lock = Instance.new("TextButton")
	lock.Name = "Lock"
	lock.Text = ""
	lock.AutoButtonColor = false
	lock.BackgroundTransparency = 1
	lock.BorderSizePixel = 0
	lock.Selectable = true
	lock.SelectionImageObject = Parts.noBox()
	lock.ZIndex = 6
	lock.Parent = button
	local lockIcon = HudParts.icon(lock, "Lock", "Icon")
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.Position = UDim2.fromScale(0.5, 0.5)
	lockIcon.Size = UDim2.fromScale(1, 1)
	lockIcon.ZIndex = 7
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(C.TouchPx, C.TouchPx)
	-- The lock's touch area: at least TouchPx, centred on the icon (a clear child button).
	local hit = Parts.catcher(lock, "Hit")
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.ZIndex = 8
	least.Parent = hit

	local card: Card = {
		slot = slot,
		button = button,
		body = body,
		edge = edge,
		icon = icon,
		name = name,
		strip = strip,
		pill = pill,
		pillText = pillText,
		soon = soon,
		soonText = soonText,
		lock = lock,
		lockIcon = lockIcon,
		lit = false,
		lockLit = false,
		owned = slot == 1,
		selected = false,
		locked = false,
	}
	local function light(on: boolean)
		card.lit = on
		paintEdge(card)
		UIAnim.sway(body, on, nil, button)
	end
	button.MouseEnter:Connect(function()
		light(true)
	end)
	button.MouseLeave:Connect(function()
		light(false)
	end)
	button.SelectionGained:Connect(function()
		light(true)
	end)
	button.SelectionLost:Connect(function()
		light(false)
	end)
	button.Activated:Connect(function()
		UISound.play("Click")
		UIAnim.bounce(body)
		if card.owned then
			if not card.selected then
				self.hooks.select(slot)
			end
		else
			self.hooks.purchase(slot)
		end
	end)
	local function lockLight(on: boolean)
		card.lockLit = on
		paintLock(card)
	end
	local function pressLock()
		if not card.owned then
			return
		end
		UISound.play("Click")
		UIAnim.bounce(lockIcon)
		self.hooks.lock(slot, not card.locked)
	end
	lock.SelectionGained:Connect(function()
		lockLight(true)
	end)
	lock.SelectionLost:Connect(function()
		lockLight(false)
	end)
	lock.MouseEnter:Connect(function()
		lockLight(true)
	end)
	lock.MouseLeave:Connect(function()
		lockLight(false)
	end)
	lock.Activated:Connect(pressLock)
	hit.Activated:Connect(pressLock)
	hit.MouseEnter:Connect(function()
		lockLight(true)
	end)
	hit.MouseLeave:Connect(function()
		lockLight(false)
	end)
	paintEdge(card)
	paintLock(card)
	return card
end

--- Draw an UltState: each slot's ult (or NONE), its rarity strip, EQUIPPED / SELECT or
--- PURCHASE with the pass's price, and its lock.
function UltSlots.draw(self: any, state: any)
	local slots = if type(state.slots) == "table" then state.slots else {}
	local owned = if type(state.owned) == "table" then state.owned else {}
	local locked = if type(state.locked) == "table" then state.locked else {}
	local passes = if type(state.slotPasses) == "table" then state.slotPasses else {}
	local products = if type(state.products) == "table" then state.products else {}
	for _, card: Card in self.cards do
		local slot = card.slot
		local id = slots[slot]
		local has = type(id) == "string" and Catalog.exists(id)
		card.owned = owned[slot] == true
		card.selected = card.owned and state.selected == slot
		card.locked = locked[slot] == true
		card.name.Text = if card.owned and has then string.upper(Catalog.name(id)) else W.None
		card.icon.Image = if card.owned and has then Catalog.icon(id) else ""
		card.icon.Visible = card.icon.Image ~= ""
		local rarity = if card.owned and has then Catalog.rarity(id) else nil
		card.strip.Visible = rarity ~= nil
		if rarity then
			Parts.paint(card.strip, rarity)
		end
		local soon = false
		if card.owned then
			card.pill.BackgroundColor3 = if card.selected then GREEN else HudParts.tone("Blue")
			card.pillText.Text = if card.selected then W.Equipped else W.Select
		else
			local product = products[passes[slot] or ""]
			local price = if type(product) == "table" and type(product.robux) == "number"
				then product.robux
				else 0
			card.pill.BackgroundColor3 = GREEN
			card.pillText.Text = if price > 0
				then W.Purchase:format(Parts.robux(price))
				else W.Purchase:format("")
			soon = type(product) == "table" and product.available == false
		end
		card.soon.Visible = soon
		card.lock.Visible = card.owned
		card.lock.Selectable = card.owned
		paintEdge(card)
		paintLock(card)
	end
end

--- Size and place the column at (x, y) for the layout `g`; returns its size. Lay out again
--- after draw: a card with an icon moves its name and strip right of it.
function UltSlots.layout(self: any, g: Parts.Geo, x: number, y: number): Vector2
	local w, h = g.px("SlotWidthPx"), g.px("SlotHeightPx")
	local gap = g.px("SlotGapPx")
	local pad = math.max(4, math.floor(h * 0.08))
	local lockPx = g.px("LockPx")
	local nameText = g.text("SlotNameTextPx")
	local pillH = g.px("SlotPillHeightPx")
	local pillText = g.text("SlotPillTextPx")
	local stripH = g.px("SlotStripPx")
	local iconWant = g.px("SlotIconPx")
	local count = #self.cards
	self.holder.Position = UDim2.fromOffset(x, y)
	self.holder.Size = UDim2.fromOffset(w, count * h + (count - 1) * gap)
	for index, card: Card in self.cards do
		card.button.Position = UDim2.fromOffset(0, (index - 1) * (h + gap))
		card.button.Size = UDim2.fromOffset(w, h)
		card.lock.Position = UDim2.fromOffset(w - pad - lockPx, pad)
		card.lock.Size = UDim2.fromOffset(lockPx, lockPx)
		local pillY = h - pad - pillH
		card.pill.Position = UDim2.fromOffset(pad, pillY)
		card.pill.Size = UDim2.fromOffset(w - 2 * pad, pillH)
		HudParts.setTextSize(card.pillText, pillText)
		card.pillText.Position = UDim2.fromOffset(4, 0)
		card.pillText.Size = UDim2.new(1, -8, 1, 0)
		local soonH = math.max(K.Text.Min + 4, math.floor(pillH * 0.8))
		local soonW = math.ceil(Parts.textWidth(W.Soon, K.Text.Min)) + 12
		card.soon.Size = UDim2.fromOffset(soonW, soonH)
		card.soon.Position = UDim2.fromOffset(w - pad + 4, pillY)
		local stripY = pillY - math.max(2, math.floor(pad / 2)) - stripH
		-- The icon top left, from the card's top down to just over the pill (the name's row and
		-- the strip's); the name and the strip move right of it.
		local iconPx = if card.icon.Visible then math.min(iconWant, pillY - pad - 2) else 0
		card.icon.Position = UDim2.fromOffset(pad, pad)
		card.icon.Size = UDim2.fromOffset(iconPx, iconPx)
		local left = if iconPx > 0 then pad + iconPx + math.max(2, math.floor(pad / 2)) else pad
		local stripLeft = if iconPx > 0 then left else pad * 2
		card.strip.Position = UDim2.fromOffset(stripLeft, stripY)
		card.strip.Size = UDim2.fromOffset(math.max(1, w - 2 * pad - stripLeft), stripH)
		HudParts.setTextSize(card.name, nameText)
		card.name.Position = UDim2.fromOffset(left, pad)
		card.name.Size =
			UDim2.fromOffset(math.max(1, w - left - pad - lockPx), math.max(1, stripY - pad - 2))
	end
	return Vector2.new(w, count * h + (count - 1) * gap)
end

--- The card buttons (for the gamepad's order), top to bottom.
function UltSlots.buttons(self: any): { TextButton }
	local list: { TextButton } = {}
	for _, card: Card in self.cards do
		table.insert(list, card.button)
	end
	return list
end

--- A gamepad on the equipped card (or the first).
function UltSlots.focus(self: any)
	for _, card: Card in self.cards do
		if card.selected then
			GuiService.SelectedObject = card.button
			return
		end
	end
	GuiService.SelectedObject = self.cards[1].button
end

return UltSlots
