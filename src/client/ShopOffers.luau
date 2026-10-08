--!strict
-- ShopOffers: the Starter Pack and VIP side by side under the restock (the designer's pick A on
-- the mock page, 2026-10-08; in the Blocks group). The Starter Pack's red card: its title, the
-- pack's picture, what is in it (the Starter Cue, the Starter Lucky Block, $25,000, an hour of 2x
-- money; where paid random items are restricted no block and $40,000), the time left in its
-- first 7 days, the gift square and the green Robux price. VIP's gold card: its title between two
-- crowns, the crown picture, its six perks and the green Robux price (half price, the full one
-- struck through, with the time left, while the welcome or comeback offer is open). The Starter
-- Pack shows until it is bought or its week ends; VIP shows beside it, or alone while its offer
-- is open, and never to a VIP; with neither there is no section. One card alone sits in the
-- middle. Robux through StoreRequest "Buy" (StarterPack, VipOffer, or the Vip pass). Sizes in
-- Config.UI.ShopBlocks.Offers, words in Strings.Menus.Shop.Blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local HudParts = require(script.Parent.HudParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local O = B.Offers
local K = Config.UI.Kit
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local LIST: { [string]: any } = Config.Products.List :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Blocks
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- StarterPack, VipOffer or Vip
	gift: (key: string) -> (), -- the Starter Pack's gift square
}

type Line = { strip: Frame, corner: UICorner, icon: ImageLabel, words: TextLabel }
type Card = {
	which: string,
	frame: Frame,
	corner: UICorner,
	edge: UIStroke,
	title: TextLabel,
	crowns: { ImageLabel },
	art: ShopCards.Art,
	lines: { Line },
	timer: Frame,
	timerWords: TextLabel,
	green: TextButton,
	gift: TextButton?,
	shown: { [string]: any },
}

local ShopOffers = {}
ShopOffers.__index = ShopOffers

-- A card with its colours (Offers.Starter or Offers.Vip) top to bottom and its edge.
local function buildCard(parent: Instance, which: string, look: any): (Frame, UICorner, UIStroke)
	local frame = HudParts.frame(parent, "Offer" .. which)
	frame.BackgroundTransparency = 0
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.ZIndex = 3
	local corner = HudParts.corner(frame, 0)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(rgb(look.Top), rgb(look.Bottom))
	gradient.Parent = frame
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = rgb(look.Edge)
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = frame
	return frame, corner, edge
end

-- One content row: a see-through white strip with its icon and words.
local function line(parent: Instance, index: number, image: string, look: any): Line
	local strip = HudParts.frame(parent, "Line" .. index)
	strip.BackgroundTransparency = look.RowTransparency
	strip.BackgroundColor3 = rgb(look.Row)
	strip.AnchorPoint = Vector2.new(0.5, 0.5)
	strip.ZIndex = 4
	local corner = HudParts.corner(strip, 0)
	local icon = ShopCards.image(strip, "Icon", image, 5)
	local words = ShopCards.label(strip, "Words", "", nil, 5)
	words.AnchorPoint = Vector2.new(0, 0.5)
	words.TextXAlignment = Enum.TextXAlignment.Left
	return { strip = strip, corner = corner, icon = icon, words = words }
end

--- Build the offers (closed) into `parent` (the Shop's Blocks group).
function ShopOffers.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopOffers)
	self.actions = actions
	self.k = 1
	self.show = { Starter = false, Vip = false } -- which cards the state shows
	self.vipKey = "Vip" -- the product the VIP button buys (VipOffer while its offer is open)
	local root = HudParts.frame(parent, "Offers")
	root.ZIndex = 2
	self.root = root

	-- The Starter Pack.
	local S = O.Starter
	local frame, corner, edge = buildCard(root, "Starter", S)
	local title = ShopCards.label(frame, "Title", COPY.StarterTitle, nil, 6)
	local art = ShopCards.art(frame, "Art", K.Icons.StarterPack, Color3.new(1, 1, 1), 4)
	local lines: { Line } = {
		line(frame, 1, K.Icons.Cue, S),
		line(frame, 2, KINDS.Starter and KINDS.Starter.Icon or "", S),
		line(frame, 3, K.Icons.CashSingle, S),
		line(frame, 4, K.Icons.Stopwatch, S),
	}
	lines[1].words.Text = COPY.StarterCue
	lines[2].words.Text = COPY.StarterBlock
	lines[4].words.Text = COPY.StarterBoost
	local timer, timerWords = ShopCards.pill(frame, "Timer", "", rgb(S.TimerColor), 6)
	timerWords.TextColor3 = rgb(K.Numbers.Money)
	local green = ShopCards.robuxButton(frame, "Robux", function()
		self.actions.robux("StarterPack")
	end)
	local gift = ShopCards.giftButton(green, function()
		self.actions.gift("StarterPack")
	end)
	self.starter = {
		which = "Starter",
		frame = frame,
		corner = corner,
		edge = edge,
		title = title,
		crowns = {},
		art = art,
		lines = lines,
		timer = timer,
		timerWords = timerWords,
		green = green,
		gift = gift,
		shown = {},
	} :: Card

	-- VIP.
	local V = O.Vip
	frame, corner, edge = buildCard(root, "Vip", V)
	title = ShopCards.label(frame, "Title", COPY.VipTitle, nil, 6)
	local crowns: { ImageLabel } = {}
	for _, side in { "Left", "Right" } do
		local crown = HudParts.icon(frame, "Crown", "Crown" .. side)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.ZIndex = 6
		table.insert(crowns, crown)
	end
	art = ShopCards.art(frame, "Art", K.Icons.Vip, Color3.new(1, 1, 1), 4)
	lines = {}
	for index, perk in COPY.VipPerks do
		local made = line(frame, index, K.Icons.Check, V)
		made.words.Text = perk
		table.insert(lines, made)
	end
	timer, timerWords = ShopCards.pill(frame, "Timer", "", rgb(V.TimerColor), 6)
	timerWords.TextColor3 = rgb(K.Numbers.Money)
	green = ShopCards.robuxButton(frame, "Robux", function()
		self.actions.robux(self.vipKey)
	end)
	self.vipCard = {
		which = "Vip",
		frame = frame,
		corner = corner,
		edge = edge,
		title = title,
		crowns = crowns,
		art = art,
		lines = lines,
		timer = timer,
		timerWords = timerWords,
		green = green,
		gift = nil,
		shown = {},
	} :: Card
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- Whether the section shows at all (the state shows at least one card).
function ShopOffers.visible(self: any): boolean
	return self.show.Starter or self.show.Vip
end

--- The section's height at the scale `k` (0 with no card).
function ShopOffers.heightFor(self: any, k: number): number
	return if self:visible() then round(O.CardUnits[2] * k) else 0
end

-- Lay one card out in its own units.
local function layoutCard(c: Card, k: number)
	local cw = O.CardUnits[1]
	c.corner.CornerRadius = UDim.new(0, round(O.CornerUnits * k))
	c.edge.Thickness = math.max(B.MinStrokePx, O.EdgeUnits * k)
	local titlePx = ShopCards.textPx(O.TitleUnits, k)
	ShopCards.line(c.title, k, cw / 2, O.TitleY, cw - 2 * O.TitleSideUnits, titlePx)
	if #c.crowns > 0 then
		local V = O.Vip
		local half = ShopCards.measure(c.title.Text, titlePx) / 2 / k
		local u = V.CrownUnits
		local away = half + u * V.CrownGapShare
		local y = O.TitleY - V.CrownRaiseUnits
		ShopCards.put(c.crowns[1], k, cw / 2 - away, y, u, u)
		ShopCards.put(c.crowns[2], k, cw / 2 + away, y, u, u)
	end
	ShopCards.layoutArt(c.art, k, O.Art[1], O.Art[2], O.Art[3], O.Glow, O.Rays)
	local rows = if c.which == "Starter" then O.StarterRows else O.VipRows
	local rowH = if c.which == "Starter" then O.StarterRowUnits else O.VipRowUnits
	local rowW = cw - 2 * O.RowLeft
	local textPx = ShopCards.textPx(O.RowTextUnits, k)
	local iconU = O.RowIconUnits
	local wordsLeft = O.RowIconLeftUnits + iconU + O.RowWordsGapUnits
	local wordsW = rowW - wordsLeft - O.RowWordsRightUnits
	local at = 0
	for _, l in c.lines do
		if l.strip.Visible then
			at += 1
			local y = rows[at] or rows[#rows]
			ShopCards.put(l.strip, k, cw / 2, y, rowW, rowH)
			l.corner.CornerRadius = UDim.new(0, round(O.RowCornerUnits * k))
			ShopCards.put(l.icon, k, O.RowIconLeftUnits + iconU / 2, rowH / 2, iconU, iconU)
			l.words.Position = UDim2.fromOffset(round(wordsLeft * k), round(rowH / 2 * k))
			l.words.Size = UDim2.fromOffset(round(wordsW * k), textPx + B.TextBoxPx)
			HudParts.setTextSize(l.words, textPx)
		end
	end
	-- The timer over the buy row: on a small screen its words keep the smallest text size, so
	-- it moves up to make room.
	local buyTop = round(O.BuyY * k) - ShopCards.buttonPx(O.BuyUnits, k) / 2
	local timerPx = ShopCards.textPx(O.TimerTextUnits, k)
	local timerY, timerH =
		ShopCards.above(O.TimerY, O.TimerUnits[2], timerPx, B.PillPadPx, buyTop, k)
	ShopCards.putPx(c.timer, cw / 2 * k, timerY, O.TimerUnits[1] * k, timerH)
	HudParts.setTextSize(c.timerWords, timerPx)
	local stroke = ShopCards.strokeOf(c.timer)
	if stroke then
		stroke.Thickness = ShopCards.strokePx(k)
	end
	ShopCards.layoutRobuxRow(
		c.green,
		c.gift,
		k,
		cw / 2,
		O.BuyY,
		cw - 2 * O.RowLeft,
		O.BuyUnits,
		O.GiftUnits,
		O.GiftGapUnits,
		O.BuyTextUnits
	)
end

--- Lay the cards out across `width` pixels at the scale `k`, the section's top `y` pixels down
--- the page; returns its height (0 with no card).
function ShopOffers.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local W = Config.UI.GrandOpeningCard.Layout.Card[1]
	local cw, ch = O.CardUnits[1], O.CardUnits[2]
	local pageW = round(W * k)
	local height = self:heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - pageW) / 2), y)
	self.root.Size = UDim2.fromOffset(pageW, height)
	self.root.Visible = height > 0
	local cards: { Card } = {}
	for _, c in { self.starter, self.vipCard } do
		c.frame.Visible = self.show[c.which] == true
		if c.frame.Visible then
			table.insert(cards, c)
		end
	end
	-- Two side by side across the page; one alone in the middle.
	local total = #cards * cw + math.max(0, #cards - 1) * O.GapUnits
	local left = (W - total) / 2
	for index, c in cards do
		ShopCards.put(c.frame, k, left + (index - 1) * (cw + O.GapUnits) + cw / 2, ch / 2, cw, ch)
		layoutCard(c, k)
	end
	return height
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- The product's live price, else Config's.
local function robuxOf(products: any, key: string): number
	local product = products[key]
	if type(product) == "table" and type(product.robux) == "number" then
		return product.robux
	end
	return if LIST[key] then LIST[key].Robux else 0
end

--- Draw the shop state. Returns true when which cards show changed (the page lays out again).
function ShopOffers.refresh(self: any, state: any): boolean
	if type(state) ~= "table" then
		return false
	end
	local offers = if type(state.offers) == "table" then state.offers else {}
	local products = if type(state.products) == "table" then state.products else {}
	local restricted = state.restricted == true
	local starter = if type(offers.StarterPack) == "table" then offers.StarterPack else {}
	local vipOffer = if type(offers.VipOffer) == "table" then offers.VipOffer else {}
	local starterOn = starter.open == true and state.starterBought ~= true
	local offerOn = vipOffer.open == true and state.vip ~= true
	local vipOn = state.vip ~= true and (starterOn or offerOn)
	local changed = self.show.Starter ~= starterOn or self.show.Vip ~= vipOn
	self.show.Starter, self.show.Vip = starterOn, vipOn
	local now = ShopParts.now()

	-- The Starter Pack: where paid random items are restricted, no block and more money.
	local s = self.starter
	local blockLine = s.lines[2]
	if blockLine.strip.Visible == restricted then
		blockLine.strip.Visible = not restricted
		changed = true
	end
	setText(
		s.lines[3].words,
		Format.money(
			if restricted then Config.Shop.StarterRestrictedMoney else Config.Shop.StarterMoney
		)
	)
	local starterEnds = if type(starter.endsAt) == "number" then starter.endsAt - now else 0
	s.timer.Visible = starterOn and starterEnds > 0
	if s.timer.Visible then
		setText(s.timerWords, string.format(COPY.EndsIn, ShopCards.timeLeft(starterEnds)))
	end
	local starterWords = ShopCards.robuxText(robuxOf(products, "StarterPack"))
	if s.shown.words ~= starterWords then
		s.shown.words = starterWords
		ShopCards.setButtonWords(s.green, starterWords)
	end

	-- VIP: half price (the full price struck through) while its offer is open.
	local v = self.vipCard
	self.vipKey = if offerOn then "VipOffer" else "Vip"
	setText(v.lines[3].words, if restricted then COPY.VipPerkRestricted else COPY.VipPerks[3])
	local offerEnds = if type(vipOffer.endsAt) == "number" then vipOffer.endsAt - now else 0
	v.timer.Visible = offerOn and offerEnds > 0
	if v.timer.Visible then
		setText(v.timerWords, string.format(COPY.EndsIn, ShopCards.timeLeft(offerEnds)))
	end
	local vipWords = if offerOn
		then ShopCards.robuxText(robuxOf(products, "VipOffer"), robuxOf(products, "Vip"))
		else ShopCards.robuxText(robuxOf(products, "Vip"))
	if v.shown.words ~= vipWords then
		v.shown.words = vipWords
		ShopCards.setButtonWords(v.green, vipWords)
	end
	return changed
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register both cards with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds their idle loops until the Shop closes.
function ShopOffers.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	for index, c in { self.starter, self.vipCard } do
		stage:add("Offer" .. c.which, c.frame, function()
			local list = {
				ShopCards.artLoops(c.art),
				ShopCards.buttonShine(
					c.green,
					B.ButtonShineEvery,
					(index - 1) * B.ShineStaggerSeconds
				),
			}
			for side, crown in c.crowns do
				local R = B.Restock.CrownRock
				table.insert(list, UIAnim.turn(crown, 0, if side == 1 then R[1] else -R[1], R[2]))
			end
			keep(ShopCards.all(list))
		end)
	end
end

function ShopOffers.closed(_self: any) end

return ShopOffers
