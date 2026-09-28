--!strict
-- CaseOpeningGrid: Fast Open's results (CaseOpening; docs/prompts/ECONOMY_UI_PROMPT.md section 11):
-- no reel, a grid of face-down cards (the house blue with the case's chest) that flip over one
-- after another quickly, rarest last, each with a soft tick; the last flip plays the reveal
-- sting of the best rarity (confetti from Legendary). A face is the cue's thumbnail on its
-- rarity's dressing, its name, and a gold NEW! pill for a cue never owned before; Epic and up
-- glow in their colour. A tap (or A or B) flips the rest at once.
--
-- Once every card is up, a card can be chosen (a tap, or the gamepad; the rarest is chosen to
-- start with, with a gold outline), and the row under the grid acts on it: Equip, Done, and
-- Open 10 again while ten cases of that type remain (Fast Open). The equipped cue's cards show
-- a green check. Built in natural pixels inside a CaseOpeningFx stage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Catalog = require(ProgressionRules:WaitForChild("Catalog"))
local Format = require(ProgressionRules:WaitForChild("Format"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CaseOpening
local G = C.Grid
local K = Config.UI.Kit
local INK = HudParts.tone("Ink")
local GOLD = HudParts.tone("Gold")
local WHITE = Color3.new(1, 1, 1)

export type Result = {
	cue: string,
	rarity: string,
	new: boolean,
	duplicate: boolean,
	count: number?,
	found: number?, -- the finder's money it paid (new to the Index), 0 or nil for none
}

export type Options = {
	onEquip: (result: Result) -> (),
	onDone: () -> (),
	onAgain: () -> (),
	onFlipped: () -> (), -- every card is up
}

type Slot = {
	result: Result,
	button: TextButton,
	body: Frame,
	back: Frame,
	face: Frame,
	faceEdge: UIStroke,
	halo: ImageLabel,
	check: ImageLabel,
	dressing: CueThumb.Dressing,
	up: boolean,
}

local Grid = {}
Grid.__index = Grid

local function words(): any
	return Strings.CaseOpening
end

-- Sort rarest last, keeping the server's order among equals.
local function ordered(results: { Result }): { Result }
	local indexed = {}
	for i, result in results do
		table.insert(indexed, { i = i, result = result })
	end
	table.sort(indexed, function(a, b)
		local ra = Catalog.rarityRank(a.result.rarity)
		local rb = Catalog.rarityRank(b.result.rarity)
		if ra ~= rb then
			return ra < rb
		end
		return a.i < b.i
	end)
	local list = {}
	for _, entry in indexed do
		table.insert(list, entry.result)
	end
	return list
end

-- The face-down side: the house blue, lighter at the top, an ink outline, the case's chest.
local function makeBack(parent: Instance, caseId: string): Frame
	local back = HudParts.frame(parent, "Back")
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundTransparency = 0
	back.BackgroundColor3 = WHITE
	back.ZIndex = 1
	HudParts.corner(back, G.CornerPx)
	local edge = Instance.new("UIStroke")
	edge.Color = INK
	edge.Thickness = G.StrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = back
	local blue = K.Buttons.Blue
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(HudParts.color(blue.Top), HudParts.color(blue.Lip))
	gradient.Parent = back
	local icon = HudParts.icon(back, "Case" .. caseId, "Chest")
	if icon.Image == "" then
		HudParts.setIcon(icon, "Case")
	end
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(G.BackIconShare, G.BackIconShare)
	icon.ZIndex = 2
	local square = Instance.new("UIAspectRatioConstraint")
	square.Parent = icon
	return back
end

--- Build the grid (every card face down) in `parent` (a stage) for a Fast Open's results. Place
--- its `root` (anchored at its middle), then start().
function Grid.new(parent: Instance, caseId: string, results: { Result }, opts: Options): any
	local self: any = setmetatable({}, Grid)
	self.caseId = caseId
	self.opts = opts
	self.alive = true
	self.flipping = false
	self.flipped = 0
	self.chosen = nil :: Slot?
	self.equipped = nil :: string?
	self.again = false
	self.connections = {} :: { RBXScriptConnection }
	local W = words()

	local root = HudParts.frame(parent, "Grid")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.ZIndex = 5
	self.root = root
	local cards = HudParts.frame(root, "Cards")
	cards.ZIndex = 1
	self.cards = cards

	self.slots = {} :: { Slot }
	for index, result in ordered(results) do
		local button = Instance.new("TextButton")
		button.Name = "Card" .. index
		button.Text = ""
		button.AutoButtonColor = false
		button.BackgroundTransparency = 1
		button.BorderSizePixel = 0
		button.Selectable = false
		button.Active = false
		button.SelectionImageObject = CaseOpeningFx.noBox()
		button.Size = UDim2.fromOffset(G.CardWidthPx, G.CardHeightPx)
		button.ZIndex = 1
		button.Parent = cards
		local halo = CaseOpeningFx.halo(button, "Halo")
		halo.ImageColor3 = CaseOpeningFx.color(result.rarity)
		halo.ZIndex = 0
		CaseOpeningFx.placeHalo(
			halo,
			Vector2.zero,
			Vector2.new(G.CardWidthPx, G.CardHeightPx),
			G.HaloSpreadPx
		)
		local body = HudParts.frame(button, "Body")
		body.AnchorPoint = Vector2.new(0.5, 0.5)
		body.Position = UDim2.fromScale(0.5, 0.5)
		body.Size = UDim2.fromScale(1, 1)
		body.ZIndex = 1
		local back = makeBack(body, caseId)
		local face = HudParts.frame(body, "Face")
		face.Size = UDim2.fromScale(1, 1)
		face.BackgroundTransparency = 0
		face.BackgroundColor3 = WHITE
		face.Visible = false
		face.ZIndex = 1
		HudParts.corner(face, G.CornerPx)
		local faceEdge = Instance.new("UIStroke")
		faceEdge.Color = INK
		faceEdge.Thickness = G.StrokePx
		faceEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		faceEdge.Parent = face
		local fade = Instance.new("UIGradient")
		fade.Rotation = 90
		fade.Color = ColorSequence.new(WHITE, HudParts.color(K.PanelFade))
		fade.Parent = face
		local dressing = CueThumb.dress(face, result.rarity)
		local thumb = CueThumb.new(face, result.cue)
		thumb.AnchorPoint = Vector2.new(0.5, 0)
		thumb.Position = UDim2.new(0.5, 0, 0, G.PadPx)
		thumb.Size = UDim2.fromOffset(G.ThumbPx, G.ThumbPx)
		thumb.ZIndex = 2
		local name = HudParts.text(face, "Name", G.NamePx, CueThumb.cueName(result.cue))
		name.AnchorPoint = Vector2.new(0.5, 1)
		name.Position = UDim2.new(0.5, 0, 1, -G.PadPx)
		name.Size = UDim2.fromOffset(G.CardWidthPx - 2 * G.PadPx, G.NameHeightPx)
		name.ZIndex = 3
		if result.new then
			local pill = HudParts.pill(face, "New", GOLD)
			pill.AnchorPoint = Vector2.new(1, 0)
			pill.Position = UDim2.fromOffset(G.CardWidthPx - G.PillInsetPx, G.PillInsetPx)
			local text = W.New
			local width = math.ceil(CaseOpeningFx.textWidth(text, G.PillTextPx)) + 2 * G.PillPadPx
			pill.Size = UDim2.fromOffset(width, G.PillPx)
			pill.ZIndex = 4
			local label = HudParts.text(pill, "Words", G.PillTextPx, text)
			label.TextWrapped = false
			label.Size = UDim2.fromScale(1, 1)
			label.ZIndex = 5
		end
		local check = HudParts.icon(face, "Check", "Equipped")
		check.Position = UDim2.fromOffset(G.PillInsetPx, G.PillInsetPx)
		check.Size = UDim2.fromOffset(G.CheckPx, G.CheckPx)
		check.Visible = false
		check.ZIndex = 4
		local slot: Slot = {
			result = result,
			button = button,
			body = body,
			back = back,
			face = face,
			faceEdge = faceEdge,
			halo = halo,
			check = check,
			dressing = dressing,
			up = false,
		}
		table.insert(self.slots, slot)
		table.insert(
			self.connections,
			button.Activated:Connect(function()
				if slot.up and not self.flipping then
					UISound.play("Click")
					self:choose(slot)
				end
			end)
		)
		table.insert(
			self.connections,
			button.SelectionGained:Connect(function()
				if slot.up and not self.flipping and self.chosen ~= slot then
					self:choose(slot)
				end
			end)
		)
	end

	-- The row under the grid.
	local row = HudParts.frame(root, "Buttons")
	row.ZIndex = 2
	self.row = row
	self.equip = HudParts.candy(row, W.Equip, function()
		UISound.play("Click")
		local chosen: Slot? = self.chosen
		if chosen then
			opts.onEquip(chosen.result)
		end
	end, "Blue")
	self.equip.Name = "Equip"
	self.done = HudParts.candy(row, W.Done, function()
		UISound.play("Click")
		opts.onDone()
	end, "Green")
	self.done.Name = "Done"
	self.againButton = HudParts.candy(
		row,
		string.format(W.OpenAgain, Format.commas(Config.Cases.FastOpenCount)),
		function()
			UISound.play("Click")
			opts.onAgain()
		end,
		"Green",
		"Case" .. caseId
	)
	self.againButton.Name = "Again"
	self.againButton.Visible = false
	for _, button in { self.equip, self.done, self.againButton } do
		HudParts.setEnabled(button, false)
	end
	self:layout()
	return self
end

--- The grid's size (natural pixels).
function Grid.size(self: any): Vector2
	return self.natural
end

-- Lay the cards out in rows of Columns, centred, and the row of buttons under them.
function Grid.layout(self: any)
	local n = #self.slots
	local columns = math.max(1, math.min(G.Columns, n))
	local rows = math.max(1, math.ceil(n / columns))
	local w = columns * G.CardWidthPx + (columns - 1) * G.GapPx
	local h = rows * G.CardHeightPx + (rows - 1) * G.GapPx
	for index, slot in self.slots do
		local rowIndex = math.floor((index - 1) / columns)
		local inRow = math.min(columns, n - rowIndex * columns)
		local rowWidth = inRow * G.CardWidthPx + (inRow - 1) * G.GapPx
		local col = (index - 1) % columns
		local x = (w - rowWidth) / 2 + col * (G.CardWidthPx + G.GapPx)
		slot.button.Position =
			UDim2.fromOffset(math.floor(x), rowIndex * (G.CardHeightPx + G.GapPx))
	end
	self.cards.Size = UDim2.fromOffset(w, h)
	local buttons = { self.equip, self.done }
	if self.again then
		table.insert(buttons, self.againButton)
	end
	local rowW = #buttons * G.ButtonWidthPx + (#buttons - 1) * G.ButtonGapPx
	local width = math.max(w, rowW)
	self.cards.Position = UDim2.fromOffset(math.floor((width - w) / 2), 0)
	for i, button in buttons do
		button.Position = UDim2.fromOffset((i - 1) * (G.ButtonWidthPx + G.ButtonGapPx), 0)
		button.Size = UDim2.fromOffset(G.ButtonWidthPx, G.ButtonPx)
		HudParts.setButtonTextSize(button, G.ButtonTextPx)
	end
	self.againButton.Visible = self.again
	self.row.Position = UDim2.fromOffset(math.floor((width - rowW) / 2), h + G.ButtonsAbovePx)
	self.row.Size = UDim2.fromOffset(rowW, G.ButtonPx)
	self.natural = Vector2.new(width, h + G.ButtonsAbovePx + G.ButtonPx)
	self.root.Size = UDim2.fromOffset(self.natural.X, self.natural.Y)
end

-- Turn one card face up: a quick squeeze to nothing and back, the face showing on the way out.
function Grid.flip(self: any, slot: Slot, instant: boolean?)
	if slot.up then
		return
	end
	slot.up = true
	local glows = CaseOpeningFx.atLeast(slot.result.rarity, G.GlowFrom)
	local function reveal()
		slot.back.Visible = false
		slot.face.Visible = true
		if glows then
			slot.halo.ImageTransparency = G.HaloTransparency
		end
	end
	if instant then
		reveal()
		slot.body.Size = UDim2.fromScale(1, 1)
		return
	end
	local half = G.FlipSeconds / 2
	local shut = TweenService:Create(
		slot.body,
		TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = UDim2.fromScale(0, 1) }
	)
	shut.Completed:Connect(function()
		if not self.alive then
			return
		end
		reveal()
		TweenService:Create(
			slot.body,
			TweenInfo.new(half, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(1, 1) }
		):Play()
	end)
	shut:Play()
	UISound.play("ReelTick")
end

--- Flip the cards one after another, rarest last.
function Grid.start(self: any)
	if self.flipping or not self.alive then
		return
	end
	self.flipping = true
	task.spawn(function()
		task.wait(G.StartDelaySeconds)
		for index, slot in self.slots do
			if not self.alive or not self.flipping then
				return
			end
			self:flip(slot)
			self.flipped = index
			if index == #self.slots then
				task.wait(G.FlipSeconds)
				if self.alive and self.flipping then
					self:finish()
				end
				return
			end
			task.wait(G.FlipEverySeconds)
		end
	end)
end

--- Flip every card still face down at once.
function Grid.skip(self: any)
	if not self.alive or not self.flipping then
		return
	end
	for _, slot in self.slots do
		self:flip(slot, true)
	end
	self.flipped = #self.slots
	self:finish()
end

-- Every card is up: the best one's moment, the choice and the buttons.
function Grid.finish(self: any)
	if not self.flipping then
		return
	end
	self.flipping = false
	self.flipped = #self.slots
	local best: Slot? = self.slots[#self.slots]
	if best then
		local rarity = best.result.rarity
		UIAnim.bounce(best.button)
		CaseOpeningFx.sting(rarity)
		if CaseOpeningFx.atLeast(rarity, C.ConfettiFrom) then
			local parent = self.root.Parent
			if parent and parent:IsA("GuiObject") then
				local p = self.root.Position
				local at = best.button.Position
				local origin = Vector2.new(
					p.X.Offset
						- self.natural.X / 2
						+ self.cards.Position.X.Offset
						+ at.X.Offset
						+ G.CardWidthPx / 2,
					p.Y.Offset - self.natural.Y / 2 + at.Y.Offset + G.CardHeightPx / 2
				)
				local amount = if CaseOpeningFx.isBig(rarity)
					then C.Card.BigConfettiScale
					else C.Card.ConfettiScale
				UIAnim.confetti(parent, origin, CaseOpeningFx.palette(rarity), amount)
			end
		end
	end
	for _, slot in self.slots do
		slot.body.Size = UDim2.fromScale(1, 1)
		slot.button.Active = true
		slot.button.Selectable = true
	end
	HudParts.setEnabled(self.done, true)
	HudParts.setEnabled(self.againButton, true)
	if best then
		self:choose(best)
	end
	self.opts.onFlipped()
end

--- Whether the cards are still turning over.
function Grid.isFlipping(self: any): boolean
	return self.flipping
end

-- Choose a card: a gold outline; the Equip button follows it.
function Grid.choose(self: any, slot: Slot)
	local old: Slot? = self.chosen
	if old and old ~= slot then
		old.faceEdge.Color = INK
		old.faceEdge.Thickness = G.StrokePx
	end
	self.chosen = slot
	slot.faceEdge.Color = GOLD
	slot.faceEdge.Thickness = G.ChosenStrokePx
	self:refreshEquip()
end

--- The equipped cue (the checks on its cards, and the Equip button).
function Grid.setEquipped(self: any, cueId: string?)
	self.equipped = cueId
	for _, slot in self.slots do
		slot.check.Visible = cueId ~= nil and slot.result.cue == cueId
	end
	self:refreshEquip()
end

function Grid.refreshEquip(self: any)
	local W = words()
	local chosen: Slot? = self.chosen
	local equipped = chosen ~= nil and chosen.result.cue == self.equipped
	HudParts.setText(self.equip, if equipped then W.Equipped else W.Equip)
	HudParts.setButtonIcon(self.equip, if equipped then "Check" else nil)
	HudParts.setTone(self.equip, if equipped then "White" else "Blue")
	local enabled = chosen ~= nil and not equipped and not self.flipping
	-- Equipped keeps its full look (a state, not a button switched off).
	HudParts.setEnabled(self.equip, enabled, if equipped then false else not enabled)
end

function Grid.setEquipBusy(self: any, busy: boolean)
	if busy then
		HudParts.setEnabled(self.equip, false, false)
	else
		self:refreshEquip()
	end
end

--- Show or hide Open 10 again (while ten cases of this type remain, with Fast Open).
function Grid.setAgain(self: any, available: boolean)
	if self.again == available then
		return
	end
	self.again = available
	local width = self.natural and self.natural.X
	self:layout()
	if width ~= self.natural.X and self.onResize then
		self.onResize()
	end
end

--- The button a gamepad lands on once every card is up: the chosen card.
function Grid.focusButton(self: any): GuiObject
	local chosen: Slot? = self.chosen
	if chosen and not self.flipping then
		return chosen.button
	end
	return self.done
end

function Grid.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	self.flipping = false
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	for _, slot in self.slots do
		slot.dressing.destroy()
	end
	self.root:Destroy()
end

return Grid
