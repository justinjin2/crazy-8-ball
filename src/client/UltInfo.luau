--!strict
-- UltInfo: what your ability does, from the ability bar in a match (designer, 2026-10-12, a
-- tester: "make it so you can hover over your ability on the bottom and see what it does").
-- A small white disc at the bar's right end shows the equipped ability's icon with a blue "i"
-- on its corner (the controller's RB / R1 picture while a controller is in use). Hovering the
-- bar or the disc with a mouse, tapping the disc, clicking it or pressing RB opens a card over
-- the bar: the icon, the ability's name in its rarity's colour and its description (the same
-- words as the Abilities screen). A tap, click or RB pins it until pressed again or
-- Config.UI.Ults.Info.PinSeconds pass; it closes when the bar goes or the cue is pulled.
--
-- UltHud owns it: the disc sits in the bar's fading canvas (so it slides and fades with the
-- bar), the press area and the card in the bar's holder. Pixels from Config.UI.Ults.Info
-- (pairs: a phone's, then a computer's).
local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Catalog = require(Shared:WaitForChild("Ults"):WaitForChild("Catalog"))
local HudParts = require(script.Parent.HudParts)
local PadMode = require(script.Parent.PadMode)
local UIAnim = require(script.Parent.UIAnim)

local I = Config.UI.Ults.Info
local K = Config.UI.Kit
local tone = HudParts.tone
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local ACTION = "8ballUltInfo"

local UltInfo = {}
UltInfo.__index = UltInfo

local function pick(pair: { number }, short: boolean): number
	return if short then pair[1] else pair[2]
end

local function rarityColor(ultId: string): Color3
	local rarity = Catalog.rarity(ultId) or "Default"
	return HudParts.color(K.Rarity[rarity] or K.Rarity.Default)
end

-- A touch is the input in use (a phone's tap also fires the mouse's enter and leave).
local function touching(): boolean
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

--- Built into UltHud's `content` (the disc, in the fading canvas) and `holder` (the press
--- area and the card). Lay it out with layout() before showing it.
function UltInfo.new(holder: Frame, content: Frame): any
	local self: any = setmetatable({}, UltInfo)
	self.ult = ""
	self.hoverBar = false
	self.hoverDisc = false
	self.pinnedUntil = 0 -- os.clock(): a tap, click or RB keeps it open until then
	self.open = false
	self.shown = false -- the bar shows the disc (UltHud's "bar" piece is up)
	self.bound = false
	self.short = false

	-- The disc: white with an ink outline, the ability's icon in it, the "i" on its corner.
	local disc = HudParts.pill(content, "UltInfo")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.ZIndex = 6
	self.disc = disc
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.ScaleType = Enum.ScaleType.Fit
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromScale(I.IconShare, I.IconShare)
	icon.ZIndex = 7
	icon.Parent = disc
	self.icon = icon
	local badge = HudParts.pill(disc, "Badge", tone("Blue"))
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(I.BadgeAt[1], I.BadgeAt[2])
	badge.ZIndex = 8
	self.badge = badge
	local letter = HudParts.text(badge, "Letter", 14, I.BadgeLetter)
	letter.AutoLocalize = false -- a symbol, not a word
	letter.Size = UDim2.fromScale(1, 1)
	letter.ZIndex = 9
	self.letter = letter
	local glyph = Instance.new("ImageLabel")
	glyph.Name = "Glyph"
	glyph.BackgroundTransparency = 1
	glyph.ScaleType = Enum.ScaleType.Fit
	glyph.AnchorPoint = Vector2.new(0.5, 0.5)
	glyph.Position = UDim2.fromScale(0.5, 0.5)
	glyph.Size = UDim2.fromScale(K.PadBack.GlyphShare, K.PadBack.GlyphShare)
	glyph.Visible = false
	glyph.ZIndex = 9
	glyph.Parent = badge
	self.glyph = glyph

	-- The press area over the disc (at least TouchPx square), above the bar's own.
	local hit = Instance.new("TextButton")
	hit.Name = "InfoPress"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.AutoButtonColor = false
	hit.Selectable = false
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Visible = false
	hit.ZIndex = 6
	hit.Parent = holder
	hit.Activated:Connect(function()
		self:toggle()
	end)
	hit.MouseEnter:Connect(function()
		self.hoverDisc = not touching()
	end)
	hit.MouseLeave:Connect(function()
		self.hoverDisc = false
	end)
	self.hit = hit
	-- Hovering the bar itself opens it too (a mouse only).
	holder.MouseEnter:Connect(function()
		self.hoverBar = not touching()
	end)
	holder.MouseLeave:Connect(function()
		self.hoverBar = false
	end)

	-- The card over the bar: icon and name on one line, the description under them.
	local card = HudParts.pill(holder, "UltInfoCard")
	card.AnchorPoint = Vector2.new(0.5, 1)
	card.Visible = false
	card.ZIndex = 8
	-- A card, not a pill: its corners only a little round. The pill's own round ends are set
	-- here (a second UICorner is ignored), so the words stay inside (designer, 2026-10-13).
	local round = card:FindFirstChildOfClass("UICorner") :: UICorner
	round.CornerRadius = UDim.new(0, I.CardCornerPx)
	self.card = card
	local cardIcon = Instance.new("ImageLabel")
	cardIcon.Name = "Icon"
	cardIcon.BackgroundTransparency = 1
	cardIcon.ScaleType = Enum.ScaleType.Fit
	cardIcon.ZIndex = 9
	cardIcon.Parent = card
	self.cardIcon = cardIcon
	-- Kept TextScaled (TextWrapped left on): a long name shrinks to its line, never past it.
	local name = HudParts.text(card, "Name", 20, "")
	name.AutoLocalize = false -- the ability's name, from Strings
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 9
	self.name = name
	local body = HudParts.note(card, "Description", 15, "")
	body.AutoLocalize = false -- from Strings
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.TextYAlignment = Enum.TextYAlignment.Top
	body.ZIndex = 9
	self.body = body

	PadMode.Changed:Connect(function()
		self:refreshBadge()
	end)
	self:refreshBadge()
	return self
end

-- The corner's "i", or the controller's RB picture while a controller is in use.
function UltInfo.refreshBadge(self: any)
	local image = if PadMode.active()
		then PadMode.glyph((Enum.KeyCode :: any)[I.GamepadKey])
		else ""
	self.glyph.Image = image
	self.glyph.Visible = image ~= ""
	self.letter.Visible = image == ""
	self.badge.BackgroundColor3 = if image ~= "" then tone("Ink") else tone("Blue")
end

--- Lay out for the bar's sizes `s` and geometry `g` (UltBar), on a phone or not, with the
--- screen `screenWidth` wide. Returns how far the disc reaches past the bar's right end.
function UltInfo.layout(self: any, s: any, g: any, short: boolean, screenWidth: number): number
	self.short = short
	self.geo, self.sizes = g, s
	self.screenWidth = screenWidth
	local size = pick(I.DiscPx, short)
	local gap = pick(I.GapPx, short)
	local centre = Vector2.new(s.width + gap + size / 2, g.pillTop + s.pill / 2)
	self.disc.Size = UDim2.fromOffset(size, size)
	self.disc.Position = UDim2.fromOffset(centre.X, centre.Y)
	local badge = math.floor(size * I.BadgeShare)
	self.badge.Size = UDim2.fromOffset(badge, badge)
	HudParts.setTextSize(self.letter, math.floor(badge * 0.8), 8)
	local hitPx = math.max(size, I.TouchPx)
	self.hit.Size = UDim2.fromOffset(hitPx, hitPx)
	self.hit.Position = UDim2.fromOffset(centre.X, centre.Y)
	self:layoutCard()
	return gap + size + math.ceil(badge * (I.BadgeAt[1] - 0.5))
end

-- The card's size for the ability shown, standing over the bar's top (or the prompt's).
function UltInfo.layoutCard(self: any)
	local s, g = self.sizes, self.geo
	if not s or not g then
		return
	end
	local short = self.short
	local width = math.floor(
		math.min(pick(I.CardWidthPx, short), (self.screenWidth or 0) * I.CardMaxWidthShare)
	)
	local pad = pick(I.CardPadPx, short)
	local namePx = pick(I.NamePx, short)
	local bodyPx = pick(I.BodyPx, short)
	local iconPx = math.floor(namePx * I.CardIconShare)
	local rowH = math.max(iconPx, namePx + 4)
	self.cardIcon.Size = UDim2.fromOffset(iconPx, iconPx)
	self.cardIcon.Position = UDim2.fromOffset(pad, pad + (rowH - iconPx) / 2)
	HudParts.setTextSize(self.name, namePx)
	local nameLeft = pad + (if self.cardIcon.Image ~= "" then iconPx + I.CardGapPx else 0)
	self.name.Position = UDim2.fromOffset(nameLeft, pad)
	self.name.Size = UDim2.fromOffset(math.max(1, width - nameLeft - pad), rowH)
	HudParts.setTextSize(self.body, bodyPx)
	local textWidth = math.max(1, width - pad * 2)
	local bodyH = math.ceil(
		TextService:GetTextSize(self.body.Text, bodyPx, FONT, Vector2.new(textWidth, 1000)).Y
	) + 2
	self.body.Position = UDim2.fromOffset(pad, pad + rowH + I.CardGapPx)
	self.body.Size = UDim2.fromOffset(textWidth, bodyH)
	self.card.Size = UDim2.fromOffset(width, pad * 2 + rowH + I.CardGapPx + bodyH)
	local top = math.min(0, g.promptTop) - pick(I.CardAbovePx, short)
	self.card.Position = UDim2.fromOffset(s.width / 2, top)
end

-- Fills the disc and the card for ability `id`.
function UltInfo.setUlt(self: any, id: string)
	if id == self.ult then
		return
	end
	self.ult = id
	local image = Catalog.icon(id)
	self.icon.Image = image
	self.cardIcon.Image = image
	self.cardIcon.Visible = image ~= ""
	self.name.Text = string.upper(Catalog.name(id))
	self.name.TextColor3 = rarityColor(id)
	self.body.Text = Catalog.description(id)
	self:layoutCard()
end

--- A tap, click or RB: pin the card open (a mouse's hover has it open already: the click
--- keeps it), or close a pinned one.
function UltInfo.toggle(self: any)
	if not self.shown then
		return
	end
	if os.clock() < self.pinnedUntil then
		self.pinnedUntil = 0
		self.hoverBar, self.hoverDisc = false, false
	else
		self.pinnedUntil = os.clock() + I.PinSeconds
	end
end

-- RB while the disc shows.
function UltInfo.bind(self: any, on: boolean)
	if on == self.bound then
		return
	end
	self.bound = on
	if on then
		ContextActionService:BindActionAtPriority(
			ACTION,
			function(_name: string, state: Enum.UserInputState, _object: InputObject)
				if state == Enum.UserInputState.Begin then
					self:toggle()
				end
				return Enum.ContextActionResult.Sink
			end,
			false,
			Enum.ContextActionPriority.High.Value + 1,
			(Enum.KeyCode :: any)[I.GamepadKey]
		)
	else
		ContextActionService:UnbindAction(ACTION)
	end
end

--- Every frame (UltHud.update): `shown` while the bar piece is up and slid in, `pulling`
--- while the cue is drawn back.
function UltInfo.update(self: any, shown: boolean, pulling: boolean)
	local player = Players.LocalPlayer
	local equipped = player and player:GetAttribute("UltEquipped")
	local id = if type(equipped) == "string" and equipped ~= ""
		then equipped
		else Config.Ults.Default
	self:setUlt(id)
	self.shown = shown
	self.hit.Visible = shown and not pulling
	self:bind(shown and not pulling)
	if not shown or pulling then
		self.pinnedUntil = 0
		self.hoverBar, self.hoverDisc = false, false
	end
	local open = shown
		and not pulling
		and (self.hoverBar or self.hoverDisc or os.clock() < self.pinnedUntil)
	if open ~= self.open then
		self.open = open
		if open then
			self:layoutCard()
			UIAnim.popIn(self.card)
		else
			self.card.Visible = false
		end
	end
end

function UltInfo.destroy(self: any)
	self:bind(false)
end

return UltInfo
