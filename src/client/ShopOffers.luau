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
-- middle. Both packs hold a random lucky block (the Starter Lucky Block; VIP's Rare block every
-- day), so each card has the sky-blue dice at its top right opening that block's Odds &
-- Details (Roblox's paid-random-items rule; OddsDetails), hidden where paid random items are
-- restricted (the block is money there). Robux through StoreRequest "Buy" (StarterPack, VipOffer, or the Vip pass). Sizes in
-- Config.UI.ShopBlocks.Offers, words in Strings.Menus.Shop.Blocks. The Passes tab shows the same
-- VIP card (ShopOffers.vipCard, layoutCard, refreshVip), there for a VIP too ("Owned").
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
local UISound = require(script.Parent.UISound)

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
	odds: (kind: string) -> (), -- a card's dice: its lucky block's Odds & Details (OddsDetails)
}

type Line = ShopCards.Row
export type Card = {
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
	odds: ShopCards.Badge?, -- the sky-blue dice: the card's lucky block's Odds & Details
	shown: { [string]: any },
}

local ShopOffers = {}
ShopOffers.__index = ShopOffers

-- One of a card's lines.
local function line(parent: Instance, index: number, image: string, look: any): Line
	return ShopCards.row(parent, "Line" .. index, image, look, 4)
end

-- Give card `c` the sky-blue dice for the lucky block `kind` it holds: a press opens that
-- block's Odds & Details (`onOdds`, the Shop's OddsDetails).
local function withOdds(c: Card, kind: string, onOdds: (string) -> ())
	local badge = ShopCards.oddsBadge(c.frame, "OddsBadge", 8)
	badge.hit.Activated:Connect(function()
		UISound.play("Click")
		onOdds(kind)
	end)
	c.odds = badge
end

-- Show or hide a card's dice (hidden where its block is money instead).
local function showOdds(c: Card, on: boolean)
	local odds = c.odds
	if odds and odds.badge.Visible ~= on then
		odds.badge.Visible = on
	end
end

-- VIP's daily lucky block kind (Config.Daily.VipBlocks: one kind).
local function vipBlock(): string
	local kinds: { string } = {}
	for kind in Config.Daily.VipBlocks :: { [string]: number } do
		table.insert(kinds, kind)
	end
	table.sort(kinds)
	return kinds[1] or "Rare"
end

--- A VIP card (closed) in `parent` named `name`: its title between two crowns, the crown
--- picture, the six perks, the offer's timer and the green button (`onBuy`).
function ShopOffers.vipCard(
	parent: Instance,
	name: string,
	onBuy: () -> (),
	onOdds: (string) -> ()
): Card
	local V = O.Vip
	local box = ShopCards.gradientCard(parent, name, V, 3)
	local frame = box.frame
	local title = ShopCards.label(frame, "Title", COPY.VipTitle, nil, 6)
	local crowns: { ImageLabel } = {}
	for _, side in { "Left", "Right" } do
		local crown = HudParts.icon(frame, "Crown", "Crown" .. side)
		crown.AnchorPoint = Vector2.new(0.5, 0.5)
		crown.ZIndex = 6
		table.insert(crowns, crown)
	end
	local art = ShopCards.art(frame, "Art", K.Icons.Vip, Color3.new(1, 1, 1), 4)
	local lines: { Line } = {}
	for index, perk in COPY.VipPerks do
		local made = line(frame, index, K.Icons.Check, V)
		made.words.Text = perk
		table.insert(lines, made)
	end
	local timer, timerWords = ShopCards.pill(frame, "Timer", "", rgb(V.TimerColor), 6)
	timerWords.TextColor3 = rgb(K.Numbers.Money)
	local green = ShopCards.robuxButton(frame, "Robux", onBuy)
	local c: Card = {
		which = "Vip",
		frame = frame,
		corner = box.corner,
		edge = box.edge,
		title = title,
		crowns = crowns,
		art = art,
		lines = lines,
		timer = timer,
		timerWords = timerWords,
		green = green,
		gift = nil,
		odds = nil,
		shown = {},
	}
	withOdds(c, vipBlock(), onOdds)
	return c
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
	local box = ShopCards.gradientCard(root, "OfferStarter", S, 3)
	local frame = box.frame
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
		corner = box.corner,
		edge = box.edge,
		title = title,
		crowns = {},
		art = art,
		lines = lines,
		timer = timer,
		timerWords = timerWords,
		green = green,
		gift = gift,
		odds = nil,
		shown = {},
	} :: Card
	withOdds(self.starter, Config.Shop.StarterBlock, actions.odds)

	-- VIP.
	self.vipCard = ShopOffers.vipCard(root, "OfferVip", function()
		self.actions.robux(self.vipKey)
	end, actions.odds)
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

--- Lay one card out in its own units (Offers.CardUnits) at the scale `k`.
function ShopOffers.layoutCard(c: Card, k: number)
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
	if c.odds then
		local A = O.OddsBadge
		ShopCards.layoutBadge(c.odds, k, cw - A[1], A[2], A[3])
	end
	local rows = if c.which == "Starter" then O.StarterRows else O.VipRows
	local rowH = if c.which == "Starter" then O.StarterRowUnits else O.VipRowUnits
	local rowW = cw - 2 * O.RowLeft
	local at = 0
	for _, l in c.lines do
		if l.strip.Visible then
			at += 1
			ShopCards.layoutRow(l, k, cw / 2, rows[at] or rows[#rows], rowW, rowH, O)
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
		ShopOffers.layoutCard(c, k)
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
	showOdds(s, not restricted)
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

	self.vipKey = ShopOffers.refreshVip(self.vipCard, state)
	return changed
end

--- Draw a VIP card from the shop state: half price (the full price struck through) with the
--- time left while its offer is open; the daily block's line where paid random items are
--- restricted; "Owned" for a VIP (the Passes tab). Returns the product its button buys.
function ShopOffers.refreshVip(v: Card, state: any): string
	local offers = if type(state.offers) == "table" then state.offers else {}
	local products = if type(state.products) == "table" then state.products else {}
	local vipOffer = if type(offers.VipOffer) == "table" then offers.VipOffer else {}
	local owned = state.vip == true
	local offerOn = vipOffer.open == true and not owned
	local restricted = state.restricted == true
	setText(v.lines[3].words, if restricted then COPY.VipPerkRestricted else COPY.VipPerks[3])
	showOdds(v, not restricted)
	local offerEnds = if type(vipOffer.endsAt) == "number"
		then vipOffer.endsAt - ShopParts.now()
		else 0
	v.timer.Visible = offerOn and offerEnds > 0
	if v.timer.Visible then
		setText(v.timerWords, string.format(COPY.EndsIn, ShopCards.timeLeft(offerEnds)))
	end
	local words = if owned
		then COPY.Owned
		elseif offerOn then ShopCards.robuxText(
			robuxOf(products, "VipOffer"),
			robuxOf(products, "Vip")
		)
		else ShopCards.robuxText(robuxOf(products, "Vip"))
	if v.shown.words ~= words then
		v.shown.words = words
		ShopCards.setButtonWords(v.green, words)
	end
	if v.shown.owned ~= owned then
		v.shown.owned = owned
		HudParts.setButtonIcon(v.green, if owned then "Check" else nil)
		HudParts.setEnabled(v.green, not owned)
	end
	return if offerOn then "VipOffer" else "Vip"
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- A card's idle loops: its picture's, its Robux button's shine (from `delay` seconds) and its
--- crowns rocking (the Passes tab's VIP card too).
function ShopOffers.cardLoops(c: Card, delay: number): UIAnim.Handle
	local list = {
		ShopCards.artLoops(c.art),
		ShopCards.buttonShine(c.green, B.ButtonShineEvery, delay),
	}
	local R = B.Restock.CrownRock
	for side, crown in c.crowns do
		table.insert(list, UIAnim.turn(crown, 0, if side == 1 then R[1] else -R[1], R[2]))
	end
	return ShopCards.all(list)
end

--- Register both cards with the Shop's `stage` (ids in Config.UI.Shop.Open); `keep(handle)`
--- holds their idle loops until the Shop closes.
function ShopOffers.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	for index, c in { self.starter, self.vipCard } do
		stage:add("Offer" .. c.which, c.frame, function()
			keep(ShopOffers.cardLoops(c, (index - 1) * B.ShineStaggerSeconds))
		end)
	end
end

return ShopOffers
