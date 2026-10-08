--!strict
-- UltSlots: the three slot cards on the left of the ult spin screen (docs/prompts/
-- ULTIMATES_PROMPT.md sections 8 and 9.3; pick "abilities A", 2026-10-08). Each is a white kit
-- card: the ability's icon at the left, its name (white, ink outline) and a strip in its rarity
-- colour to the icon's right, and along the foot a candy button: EQUIPPED (green, the selected
-- slot: the one played in matches) or SELECT (blue); a lock toggle top right (a locked slot
-- cannot be spun into). An owned slot with no ability yet reads "Empty". A slot not bought
-- yet shows a padlock, "Locked" and its R$ price on a green button that shines (a small "Soon"
-- while the pass's id is 0). The button is what a gamepad selects; a press anywhere on the card
-- does the same (a big target on a phone). On a phone the cards are small and stacked in a
-- compact column (Config.UI.UltScreen.Short).
--
-- Every press goes to the server through the screen's hooks (Select, Lock, BuyProduct).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)
local Parts = require(script.Parent.UltScreenParts)

local C = Config.UI.UltScreen
local K = Config.UI.Kit
local W = Strings.Ults.Screen
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local GREEN = HudParts.tone("Green")
-- A card at rest: pale blue when the Abilities page is in Config.UI.Menu.PaleEdgeMenus.
local REST = if HudParts.paleEdged(C.Column.Name) then HudParts.color(K.PaleEdge) else INK

export type Hooks = {
	select: (slot: number) -> (),
	lock: (slot: number, locked: boolean) -> (),
	purchase: (slot: number) -> (),
}

type Card = {
	slot: number,
	button: TextButton, -- the whole card: a press does what its button says
	body: Frame, -- everything drawn
	edge: UIStroke,
	icon: ImageLabel, -- the ability's icon, the padlock while not bought, hidden while empty
	name: TextLabel,
	strip: Frame,
	pill: TextButton, -- the candy along the foot
	soon: Frame,
	lock: TextButton,
	lockIcon: ImageLabel,
	lockLit: boolean,
	owned: boolean,
	selected: boolean,
	locked: boolean,
	shine: UIAnim.Handle?, -- the price button's shine while the slot is for sale
}

local UltSlots = {}
UltSlots.__index = UltSlots

-- The card's outline: green on the equipped slot, else REST.
local function paintEdge(card: Card)
	if card.selected then
		card.edge.Color = GREEN
		card.edge.Thickness = K.SelectedStrokePx
	else
		card.edge.Color = REST
		card.edge.Thickness = K.PanelStrokePx
	end
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
	self.shining = false
	local holder = HudParts.frame(parent, "Slots")
	holder.ZIndex = 5
	self.holder = holder
	for slot = 1, Config.Ults.Slots do
		table.insert(self.cards, self:build(holder, slot))
	end
	return self
end

function UltSlots.build(self: any, parent: Instance, slot: number): Card
	local button = Parts.catcher(parent, "Slot" .. slot)
	button.Size = UDim2.fromOffset(0, 0)
	button.ZIndex = 2
	local body = HudParts.frame(button, "Body")
	body.Size = UDim2.fromScale(1, 1)
	local cardFrame = HudParts.card(body, "Card", K.ButtonCornerPx + 2)
	cardFrame.Size = UDim2.fromScale(1, 1)
	local fill = cardFrame:FindFirstChild("Fill") :: Frame
	local edge = fill:FindFirstChild("Edge") :: UIStroke
	local icon = HudParts.icon(body, "", "UltIcon")
	icon.Visible = false
	icon.ZIndex = 3
	local name = HudParts.text(body, "Name", C.Full.SlotNameTextPx, W.Locked)
	name.TextWrapped = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 3
	local strip = HudParts.frame(body, "Strip")
	strip.BackgroundTransparency = 0
	strip.ZIndex = 3
	HudParts.corner(strip, K.PillCornerPx)
	local card: Card
	local function press()
		UISound.play("Click")
		UIAnim.bounce(body)
		if card.owned then
			if not card.selected then
				self.hooks.select(slot)
			end
		else
			self.hooks.purchase(slot)
		end
	end
	local pill = HudParts.candy(body, "", press, "Green")
	pill.Name = "Button"
	pill.ZIndex = 4
	local soon = HudParts.pill(body, "Soon", GOLD)
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.ZIndex = 8
	soon.Visible = false
	local soonText = HudParts.text(soon, "Words", K.Text.Min, W.Soon)
	soonText.TextWrapped = false
	soonText.Size = UDim2.fromScale(1, 1)
	soonText.ZIndex = 9

	local lock = Parts.catcher(button, "Lock")
	lock.Selectable = true
	lock.SelectionImageObject = Parts.noBox()
	lock.Size = UDim2.fromOffset(0, 0)
	lock.ZIndex = 6
	local lockIcon = HudParts.icon(lock, "Lock", "Icon")
	lockIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	lockIcon.Position = UDim2.fromScale(0.5, 0.5)
	lockIcon.Size = UDim2.fromScale(1, 1)
	lockIcon.ZIndex = 7
	-- The lock's touch area: at least TouchPx, centred on the icon (a clear child button).
	local hit = Parts.catcher(lock, "Hit")
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.ZIndex = 8
	local least = Instance.new("UISizeConstraint")
	least.MinSize = Vector2.new(C.TouchPx, C.TouchPx)
	least.Parent = hit

	card = {
		slot = slot,
		button = button,
		body = body,
		edge = edge,
		icon = icon,
		name = name,
		strip = strip,
		pill = pill,
		soon = soon,
		lock = lock,
		lockIcon = lockIcon,
		lockLit = false,
		owned = slot == 1,
		selected = false,
		locked = false,
		shine = nil,
	}
	button.Activated:Connect(press)
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

-- The price button's shine: only while the slot is for sale and the screen shows it.
local function setShine(card: Card, on: boolean)
	if on and not card.shine then
		local B = Config.UI.ShopBlocks
		card.shine = ShopCards.buttonShine(card.pill, B.ButtonShineEvery, 0.1 * card.slot)
	elseif not on and card.shine then
		card.shine.stop()
		card.shine = nil
	end
end

--- Draw an UltState: each slot's ability (or Empty, or Locked), its rarity strip, EQUIPPED /
--- SELECT or the pass's R$ price, and its lock.
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
		local rarity = if card.owned and has then Catalog.rarity(id) else nil
		if card.owned then
			card.name.Text = if has then Catalog.name(id) else W.Empty
			card.icon.Image = if has then Catalog.icon(id) else ""
		else
			card.name.Text = W.Locked
			card.icon.Image = K.Icons.Lock
		end
		card.icon.Visible = card.icon.Image ~= ""
		card.strip.Visible = rarity ~= nil
		if rarity then
			Parts.paint(card.strip, rarity)
		end
		local soon = false
		if card.owned then
			HudParts.setTone(card.pill, if card.selected then "Green" else "Blue")
			HudParts.setText(card.pill, if card.selected then W.Equipped else W.Select)
		else
			local product = products[passes[slot] or ""]
			local price = if type(product) == "table" and type(product.robux) == "number"
				then product.robux
				else 0
			HudParts.setTone(card.pill, "Green")
			HudParts.setText(card.pill, if price > 0 then Parts.robux(price) else W.Locked)
			soon = type(product) == "table" and product.available == false
		end
		card.soon.Visible = soon
		card.lock.Visible = card.owned
		card.lock.Selectable = card.owned
		setShine(card, self.shining and not card.owned)
		paintEdge(card)
		paintLock(card)
	end
end

--- Start (or stop) the price buttons' shines: the screen starts them once the cards have
--- landed in its open and stops them when it closes.
function UltSlots.setShining(self: any, on: boolean)
	self.shining = on
	for _, card: Card in self.cards do
		setShine(card, on and not card.owned)
	end
end

--- Size and place the column at (x, y) for the layout `g`; returns its size. Lay out again
--- after draw: a card with an icon moves its name and strip right of it.
function UltSlots.layout(self: any, g: Parts.Geo, x: number, y: number): Vector2
	local w, h = g.px("SlotWidthPx"), g.px("SlotHeightPx")
	local gap = g.px("SlotGapPx")
	local pad = g.px("SlotPadPx")
	local lockPx = g.px("LockPx")
	local nameText = g.text("SlotNameTextPx")
	local pillH = math.min(g.px("SlotPillHeightPx"), math.floor(h * 0.45))
	local pillText = g.text("SlotPillTextPx")
	local stripH = g.px("SlotStripPx")
	local iconWant = g.px("SlotIconPx")
	local count = #self.cards
	self.holder.Position = UDim2.fromOffset(x, y)
	self.holder.Size = UDim2.fromOffset(w, count * h + (count - 1) * gap)
	for index, card: Card in self.cards do
		card.button.Position = UDim2.fromOffset(0, (index - 1) * (h + gap))
		card.button.Size = UDim2.fromOffset(w, h)
		-- The button along the foot, as wide as the card's inside.
		local pillY = h - pad - pillH
		card.pill.Position = UDim2.fromOffset(pad, pillY)
		card.pill.Size = UDim2.fromOffset(w - 2 * pad, pillH)
		HudParts.setButtonTextSize(card.pill, pillText)
		local soonH = math.max(K.Text.Min + 4, math.floor(pillH * 0.7))
		local soonW = math.ceil(Parts.textWidth(W.Soon, K.Text.Min)) + 12
		card.soon.Size = UDim2.fromOffset(soonW, soonH)
		card.soon.Position = UDim2.fromOffset(w - pad + 4, pillY)
		-- Over it: the icon at the left, the name (and the strip under it) beside it, centred
		-- top to bottom in the room; the lock in the top right corner.
		local roomTop = pad
		local roomH = math.max(1, pillY - math.max(2, math.floor(pad / 2)) - roomTop)
		local iconPx = if card.icon.Visible then math.min(iconWant, roomH) else 0
		card.icon.Position = UDim2.fromOffset(pad, roomTop + math.floor((roomH - iconPx) / 2))
		card.icon.Size = UDim2.fromOffset(iconPx, iconPx)
		local left = if iconPx > 0
			then pad + iconPx + math.max(4, math.floor(pad * 0.8))
			else pad * 2
		local lockRoom = if card.lock.Visible then lockPx + 2 else 0
		local nameW = math.max(1, w - left - pad - lockRoom)
		local nameH = nameText + 6
		local stripGap = math.max(2, math.floor(pad / 3))
		local block = nameH + (if card.strip.Visible then stripGap + stripH else 0)
		local nameY = roomTop + math.floor((roomH - block) / 2)
		HudParts.setTextSize(card.name, nameText)
		card.name.Position = UDim2.fromOffset(left, nameY)
		card.name.Size = UDim2.fromOffset(nameW, nameH)
		card.strip.Position = UDim2.fromOffset(left, nameY + nameH + stripGap)
		card.strip.Size = UDim2.fromOffset(
			math.max(1, math.min(nameW, math.ceil(Parts.textWidth(card.name.Text, nameText)) + 8)),
			stripH
		)
		card.lock.Position = UDim2.fromOffset(w - pad - lockPx, math.max(2, math.floor(pad / 2)))
		card.lock.Size = UDim2.fromOffset(lockPx, lockPx)
	end
	return Vector2.new(w, count * h + (count - 1) * gap)
end

--- The cards' buttons (for the gamepad's order), top to bottom.
function UltSlots.buttons(self: any): { TextButton }
	local list: { TextButton } = {}
	for _, card: Card in self.cards do
		table.insert(list, card.pill)
	end
	return list
end

--- The cards (the screen stages them as Slot1, Slot2, Slot3), top to bottom.
function UltSlots.frames(self: any): { TextButton }
	local list: { TextButton } = {}
	for _, card: Card in self.cards do
		table.insert(list, card.button)
	end
	return list
end

--- A gamepad on the equipped card's button (or the first).
function UltSlots.focus(self: any)
	for _, card: Card in self.cards do
		if card.selected then
			GuiService.SelectedObject = card.pill
			return
		end
	end
	GuiService.SelectedObject = self.cards[1].pill
end

return UltSlots
