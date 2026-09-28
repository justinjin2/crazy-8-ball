--!strict
-- CaseOpeningCard: the prize card after the reel (CaseOpening; docs/prompts/ECONOMY_UI_PROMPT.md
-- section 11). A white kit card that pops in (UIAnim.popIn) with a glow round it in the prize's
-- colour: the cue's thumbnail on a tile dressed in its rarity (CueThumb.dress: Mythic's shimmer
-- over deep space, Secret's red glow), its name, a rarity pill and "NEW!" or "Duplicate", the
-- copies in existence ("1,284 exist", ReplicatedStorage.CueCounts; hidden until known), and a
-- row of buttons: Equip, Sell (duplicates only), and Open next (while cases of that type remain)
-- or Done; a red X in the corner. On the result screen (the first win's case) the row is Equip
-- and Continue, with no X.
--
-- The moment grows with the rarity (Config.UI.CaseOpening): the reveal sting by tier, turning
-- rays behind the card from RaysFrom (Epic) up, confetti from ConfettiFrom (Legendary) up, and
-- for Mythic and Secret (BigFrom) a thicker edge that shimmers through the pastels or breathes
-- red, more confetti and a bigger glow. Built in natural pixels inside a CaseOpeningFx stage.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local ProgressionRules = Shared:WaitForChild("Progression")
local Format = require(ProgressionRules:WaitForChild("Format"))
local CaseOpeningFx = require(script.Parent.CaseOpeningFx)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local C = Config.UI.CaseOpening
local D = C.Card
local K = Config.UI.Kit
local INK = HudParts.tone("Ink")
local WHITE = Color3.new(1, 1, 1)

export type Info = {
	caseId: string,
	cue: string,
	rarity: string,
	new: boolean,
	duplicate: boolean,
	count: number?, -- copies owned once it was added (the server's answer), if known
}

export type Options = {
	reveal: boolean?, -- the result screen's reveal: Equip and Continue, no X
	onEquip: () -> (),
	onSell: (() -> ())?,
	onNext: (() -> ())?,
	onDone: () -> (),
}

local Card = {}
Card.__index = Card

local function words(): any
	return Strings.CaseOpening
end

-- A pill with white outlined words (the rarity, NEW!, Duplicate), sized to its words.
local function pill(parent: Instance, name: string, text: string, fill: Color3): (Frame, TextLabel)
	local frame = HudParts.pill(parent, name, fill)
	frame.ZIndex = 2
	local label = HudParts.text(frame, "Words", D.PillTextPx, text)
	label.TextWrapped = false
	label.ZIndex = 3
	return frame, label
end

--- Build the card (hidden) in `parent` (a stage) for one opened cue. Place its `root` (anchored
--- at its middle), then show() it.
function Card.new(parent: Instance, info: Info, opts: Options): any
	local self: any = setmetatable({}, Card)
	self.info = info
	self.opts = opts
	self.alive = true
	self.loop = nil :: RBXScriptConnection?
	self.raysSpin = nil :: UIAnim.Handle?
	self.connections = {} :: { RBXScriptConnection }
	self.big = CaseOpeningFx.isBig(info.rarity)
	self.hasRays = CaseOpeningFx.atLeast(info.rarity, C.RaysFrom)
	self.born = os.clock()
	local W = words()
	local colour = CaseOpeningFx.color(info.rarity)

	local root = HudParts.frame(parent, "PrizeCard")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Visible = false
	root.ZIndex = 5
	self.root = root

	-- Behind the card: the turning rays (Epic and up) and the glow in the prize's colour.
	local rays = CaseOpeningFx.rays(root, "Rays")
	rays.ImageColor3 = if info.rarity == "Mythic" then WHITE else colour
	rays.ZIndex = 0
	if info.rarity == "Mythic" then
		local tint = Instance.new("UIGradient")
		tint.Color = CaseOpeningFx.shimmer()
		tint.Parent = rays
		self.raysTint = tint
	end
	self.rays = rays
	local halo = CaseOpeningFx.halo(root, "Halo")
	halo.ImageColor3 = colour
	halo.ZIndex = 1
	self.halo = halo

	local body = HudParts.card(root, "Body", D.CornerPx)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 2
	self.body = body
	local fill = body:FindFirstChild("Fill")
	local edge = fill and fill:FindFirstChild("Edge")
	self.edge = if edge and edge:IsA("UIStroke") then edge else nil
	if self.big and self.edge then
		-- Mythic and Secret: a thicker edge in their colour (animated in step).
		self.edge.Thickness = D.BigStrokePx
		self.edge.Color = colour
		if info.rarity == "Mythic" then
			self.edge.Color = WHITE
			local sheen = Instance.new("UIGradient")
			sheen.Color = CaseOpeningFx.shimmer()
			sheen.Parent = self.edge
			self.edgeSheen = sheen
		end
	end

	-- The thumbnail on its rarity tile.
	local art = HudParts.frame(body, "Art")
	art.AnchorPoint = Vector2.new(0.5, 0)
	art.ZIndex = 2
	self.art = art
	local tile = HudParts.frame(art, "Tile")
	tile.Size = UDim2.fromScale(1, 1)
	tile.BackgroundTransparency = 0
	tile.BackgroundColor3 = WHITE
	tile.ZIndex = 0
	HudParts.corner(tile, D.ArtCornerPx)
	local tileEdge = Instance.new("UIStroke")
	tileEdge.Color = INK
	tileEdge.Thickness = D.ArtStrokePx
	tileEdge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	tileEdge.Parent = tile
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Color = ColorSequence.new(WHITE, HudParts.color(K.PanelFade))
	fade.Parent = tile
	self.dressing = CueThumb.dress(tile, info.rarity)
	local thumb = CueThumb.new(art, info.cue)
	thumb.AnchorPoint = Vector2.new(0.5, 0.5)
	thumb.Position = UDim2.fromScale(0.5, 0.5)
	thumb.Size = UDim2.fromScale(D.ThumbShare, D.ThumbShare)
	thumb.ZIndex = 2

	-- The name, the pills, the count in existence.
	local name = HudParts.text(body, "Name", D.NamePx, CueThumb.cueName(info.cue))
	name.TextWrapped = false
	name.ZIndex = 2
	self.name = name
	local pills = HudParts.frame(body, "Pills")
	pills.ZIndex = 2
	self.pills = pills
	local rarityFill = colour
	if info.rarity == "Secret" then
		rarityFill = CueThumb.rarityColor("Secret")
	elseif info.rarity == "Mythic" then
		rarityFill = WHITE
	end
	local rarityPill, rarityWords =
		pill(pills, "Rarity", CueThumb.rarityName(info.rarity), rarityFill)
	if info.rarity == "Secret" then
		rarityWords.TextColor3 = HudParts.color(K.SecretGlow)
	elseif info.rarity == "Mythic" then
		local sheen = Instance.new("UIGradient")
		sheen.Color = CaseOpeningFx.shimmer()
		sheen.Parent = rarityPill
		self.pillSheen = sheen
	end
	self.rarityPill, self.rarityWords = rarityPill, rarityWords
	local count = info.count
	local stateText = W.New
	local stateTone = "Gold"
	if not info.new then
		stateTone = "Grey"
		stateText = if count and count > 1
			then string.format(W.DuplicateCount, Format.commas(count))
			else W.Duplicate
	end
	local statePill, stateWords = pill(pills, "State", stateText, HudParts.tone(stateTone))
	self.statePill, self.stateWords = statePill, stateWords
	local exist = HudParts.note(body, "Exist", D.ExistPx, "")
	exist.TextWrapped = false
	exist.ZIndex = 2
	self.exist = exist

	-- The buttons.
	local row = HudParts.frame(body, "Buttons")
	row.ZIndex = 3
	self.row = row
	local reveal = opts.reveal == true
	self.reveal = reveal
	self.equip = HudParts.candy(row, W.Equip, function()
		UISound.play("Click")
		opts.onEquip()
	end, "Blue")
	self.equip.Name = "Equip"
	self.sell = nil :: TextButton?
	if not reveal and info.duplicate and opts.onSell then
		local onSell = opts.onSell
		local sell = HudParts.candy(row, W.Sell, function()
			UISound.play("Click")
			onSell()
		end, "Red", "Sell")
		sell.Name = "Sell"
		self.sell = sell
	end
	self.next = HudParts.candy(row, if reveal then W.Continue else W.Done, function()
		UISound.play("Click")
		if self.nextCount and self.nextCount > 0 and opts.onNext then
			opts.onNext()
		else
			opts.onDone()
		end
	end, "Green")
	self.next.Name = "Next"
	self.nextCount = nil :: number?
	self.closeButton = nil :: TextButton?
	if not reveal then
		local close = HudParts.candy(body, "", function()
			UISound.play("Click")
			opts.onDone()
		end, "Red", "X")
		close.Name = "Close"
		close.AnchorPoint = Vector2.new(0.5, 0.5)
		close.ZIndex = 4
		HudParts.setMinHit(close, D.TouchMinPx)
		self.closeButton = close
	end

	self:refreshExist()
	local counts = ReplicatedStorage:FindFirstChild("CueCounts")
	if counts then
		table.insert(
			self.connections,
			counts:GetAttributeChangedSignal(info.cue):Connect(function()
				self:refreshExist()
			end)
		)
	else
		-- The counts folder arrives with the first read: watch for it.
		table.insert(
			self.connections,
			ReplicatedStorage.ChildAdded:Connect(function(child)
				if child.Name == "CueCounts" and self.alive then
					self:refreshExist()
					table.insert(
						self.connections,
						child:GetAttributeChangedSignal(info.cue):Connect(function()
							self:refreshExist()
						end)
					)
				end
			end)
		)
	end
	self:layout()
	return self
end

-- The buttons share the row by what their words need ("Open next (4)" with its chest is
-- wider than "Equip"): each gets its words' width and an equal share of what is left, or all
-- shrink together when the row is short (the words then shrink to fit, never below the kit's
-- minimum). Run again whenever a button's words change.
function Card.layoutButtons(self: any)
	local inner = D.WidthPx - 2 * D.PadPx
	local buttons = { self.equip }
	if self.sell then
		table.insert(buttons, self.sell)
	end
	table.insert(buttons, self.next)
	local room = inner - D.ButtonGapPx * (#buttons - 1)
	local wants = {}
	local total = 0
	for i, button in buttons do
		HudParts.setButtonTextSize(button, D.ButtonTextPx)
		wants[i] = HudParts.candyWidth(button, D.ButtonPx, D.ButtonTextPx)
		total += wants[i]
	end
	local extra = math.max(0, room - total) / #buttons
	local squeeze = if total > room then room / total else 1
	local x = 0
	for i, button in buttons do
		local width = math.floor(wants[i] * squeeze + extra)
		if i == #buttons then
			width = math.floor(inner - x) -- the last one ends flush with the row
		end
		button.Position = UDim2.fromOffset(x, 0)
		button.Size = UDim2.fromOffset(width, D.ButtonPx)
		x += width + D.ButtonGapPx
	end
end

--- The card's size (natural pixels).
function Card.size(self: any): Vector2
	return self.natural
end

-- Lay the card out at its natural size (its height follows what it shows).
function Card.layout(self: any)
	local w = D.WidthPx
	local pad, gap = D.PadPx, D.GapPx
	local inner = w - 2 * pad
	local y = pad
	self.art.Size = UDim2.fromOffset(D.ArtPx, D.ArtPx)
	self.art.Position = UDim2.fromOffset(w / 2, y)
	self.artMiddle = y + D.ArtPx / 2
	y += D.ArtPx + gap
	self.name.Position = UDim2.fromOffset(pad, y)
	self.name.Size = UDim2.fromOffset(inner, D.NameHeightPx)
	y += D.NameHeightPx + gap
	-- The pills side by side, centred, each as wide as its words.
	local widths = {}
	local total = 0
	for i, label in { self.rarityWords, self.stateWords } do
		local width = math.ceil(CaseOpeningFx.textWidth(label.Text, D.PillTextPx)) + 2 * D.PillPadPx
		widths[i] = width
		total += width
	end
	total += D.PillGapPx
	local scaleDown = math.min(1, inner / total)
	local x = math.floor((inner - total * scaleDown) / 2)
	for i, frame in { self.rarityPill, self.statePill } do
		local width = math.floor(widths[i] * scaleDown)
		frame.Position = UDim2.fromOffset(x, 0)
		frame.Size = UDim2.fromOffset(width, D.PillPx)
		local label = frame:FindFirstChild("Words") :: TextLabel
		label.Position = UDim2.fromOffset(4, 0)
		label.Size = UDim2.fromOffset(math.max(1, width - 8), D.PillPx)
		x += width + math.floor(D.PillGapPx * scaleDown)
	end
	self.pills.Position = UDim2.fromOffset(pad, y)
	self.pills.Size = UDim2.fromOffset(inner, D.PillPx)
	y += D.PillPx + gap
	self.exist.Visible = self.exist.Text ~= ""
	if self.exist.Visible then
		self.exist.Position = UDim2.fromOffset(pad, y)
		self.exist.Size = UDim2.fromOffset(inner, D.ExistHeightPx)
		y += D.ExistHeightPx + gap
	end
	y += D.ButtonsAbovePx
	self.row.Position = UDim2.fromOffset(pad, y)
	self.row.Size = UDim2.fromOffset(inner, D.ButtonPx)
	self:layoutButtons()
	y += D.ButtonPx + pad
	local close: TextButton? = self.closeButton
	if close then
		close.Position = UDim2.fromOffset(w - D.CloseInsetPx, D.CloseInsetPx)
		close.Size = UDim2.fromOffset(D.ClosePx, D.ClosePx)
	end
	self.natural = Vector2.new(w, y)
	self.root.Size = UDim2.fromOffset(w, y)
	-- The rays turn about the thumbnail; the glow hugs the card.
	local raySize = D.ArtPx * D.RaysShare
	self.rays.Position = UDim2.fromOffset(w / 2, self.artMiddle)
	self.rays.Size = UDim2.fromOffset(raySize, raySize)
	local spread = if self.big then D.BigHaloSpreadPx else D.HaloSpreadPx
	CaseOpeningFx.placeHalo(self.halo, Vector2.zero, self.natural, spread)
end

-- "1,284 exist" from the counts attribute; hidden while it is not known.
function Card.refreshExist(self: any)
	if not self.alive then
		return
	end
	local n = CaseOpeningFx.existCount(self.info.cue)
	local text = if n and n >= 1
		then string.format(if n == 1 then words().ExistOne else words().Exist, Format.commas(n))
		else ""
	if self.exist.Text ~= text then
		local had = self.exist.Text ~= ""
		self.exist.Text = text
		if had ~= (text ~= "") and self.natural then
			self:layout()
		end
	end
end

--- Pop the card in: the sting by rarity, rays from Epic, confetti from Legendary (into
--- `confettiParent`, the stage, at `origin`: the card's thumbnail in the stage's pixels), and
--- the glow, shimmer or breath running until it is destroyed.
function Card.show(self: any, confettiParent: GuiObject?, origin: Vector2?)
	if not self.alive then
		return
	end
	local rarity = self.info.rarity
	UIAnim.popIn(self.root)
	CaseOpeningFx.sting(rarity)
	if self.hasRays then
		self.raysSpin = UIAnim.spin(self.rays, D.RaysDegreesPerSecond)
	end
	if confettiParent and origin and CaseOpeningFx.atLeast(rarity, C.ConfettiFrom) then
		local amount = if self.big then D.BigConfettiScale else D.ConfettiScale
		task.delay(D.ConfettiDelaySeconds, function()
			if self.alive then
				UIAnim.confetti(confettiParent, origin, CaseOpeningFx.palette(rarity), amount)
			end
		end)
	end
	self.born = os.clock()
	self.loop = RunService.RenderStepped:Connect(function()
		self:step()
	end)
end

-- Fade the rays and glow in, and keep the big rarities' edge moving.
function Card.step(self: any)
	if not self.alive then
		return
	end
	local rarity = self.info.rarity
	local t = os.clock() - self.born
	local shown = math.clamp(t / D.GlowInSeconds, 0, 1)
	local breath = 1
	if rarity == "Secret" then
		breath = 1 - D.SecretBreathDepth * (1 - CaseOpeningFx.breath(t, D.BreathSeconds))
	end
	local haloTransparency = if self.big then D.BigHaloTransparency else D.HaloTransparency
	self.halo.ImageColor3 = CaseOpeningFx.glowAt(rarity, t)
	self.halo.ImageTransparency = 1 - (1 - haloTransparency) * shown * breath
	if self.hasRays then
		self.rays.ImageTransparency = 1 - (1 - D.RaysTransparency) * shown * breath
	end
	local turn = (t * D.ShimmerDegreesPerSecond) % 360
	if self.edgeSheen then
		self.edgeSheen.Rotation = turn
	end
	if self.pillSheen then
		self.pillSheen.Rotation = turn
	end
	if self.raysTint then
		self.raysTint.Rotation = -turn
	end
	if rarity == "Secret" and self.edge then
		self.edge.Transparency = D.SecretEdgeDim * (1 - breath)
	end
end

--- The Equip button: "Equip", "Equipped" (a check, not pressable) or busy while it asks.
function Card.setEquipped(self: any, equipped: boolean)
	local W = words()
	HudParts.setText(self.equip, if equipped then W.Equipped else W.Equip)
	HudParts.setButtonIcon(self.equip, if equipped then "Check" else nil)
	HudParts.setTone(self.equip, if equipped then "White" else "Blue")
	HudParts.setEnabled(self.equip, not equipped, false)
	self:layoutButtons()
end

function Card.setEquipBusy(self: any, busy: boolean)
	HudParts.setEnabled(self.equip, not busy, false)
end

--- The Sell button: "Sell $600" (its price, from the catalog: the server pays what it pays),
--- busy while it asks, or "Sold!" once sold.
function Card.setSell(self: any, state: string, price: number?)
	local sell: TextButton? = self.sell
	if not sell then
		return
	end
	local W = words()
	if state == "Sold" then
		HudParts.setText(sell, W.Sold)
		HudParts.setButtonIcon(sell, "Check")
		HudParts.setEnabled(sell, false)
	elseif state == "Busy" then
		HudParts.setEnabled(sell, false, false)
	else
		HudParts.setText(sell, string.format(W.Sell, Format.money(price or 0)))
		HudParts.setEnabled(sell, true)
	end
	self:layoutButtons()
end

--- Open next (with how many cases of this type are left) or Done / Continue.
function Card.setNext(self: any, remaining: number?)
	if self.reveal then
		return
	end
	local W = words()
	self.nextCount = remaining
	if remaining and remaining > 0 then
		HudParts.setText(self.next, string.format(W.OpenNextCount, Format.commas(remaining)))
		HudParts.setButtonIcon(self.next, "Case" .. self.info.caseId)
	else
		HudParts.setText(self.next, W.Done)
		HudParts.setButtonIcon(self.next, nil)
	end
	self:layoutButtons()
end

--- The button a gamepad lands on: Equip on the result screen, else Open next / Done.
function Card.focusButton(self: any): GuiObject
	if self.reveal then
		local equip: TextButton = self.equip
		return if equip.Selectable then equip else self.next
	end
	return self.next
end

--- Where a sale's cash chip starts: the Sell button's middle (absolute pixels), or the card's.
function Card.sellPoint(self: any): Vector2
	local from: GuiObject = self.sell or self.root
	return from.AbsolutePosition + from.AbsoluteSize / 2
end

--- The thumbnail's middle in the card's parent's pixels (for the confetti).
function Card.artCentre(self: any): Vector2
	local position = self.root.Position
	return Vector2.new(
		position.X.Offset,
		position.Y.Offset - self.natural.Y / 2 + (self.artMiddle or 0)
	)
end

function Card.destroy(self: any)
	if not self.alive then
		return
	end
	self.alive = false
	if self.loop then
		self.loop:Disconnect()
		self.loop = nil
	end
	if self.raysSpin then
		self.raysSpin.stop()
		self.raysSpin = nil
	end
	for _, connection in self.connections do
		connection:Disconnect()
	end
	table.clear(self.connections)
	self.dressing.destroy()
	self.root:Destroy()
end

return Card
