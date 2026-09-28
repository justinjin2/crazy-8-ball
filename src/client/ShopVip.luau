--!strict
-- ShopVip: the Shop's VIP tab (ECONOMY 11.2 to 11.5; docs/prompts/ECONOMY_UI_PROMPT.md sections
-- 11 and 12). Every item buys through StoreRequest "Buy" with its Config.Products key; the
-- server shows Roblox's purchase dialog itself. Buy always shows the Robux price (live, else
-- Config's); while a product's Id is 0 (the state's products[key].available) a gold "Coming
-- soon" tag ("Soon" where it would not fit) marks it and Buy only says so. Owned things show a
-- green "Owned".
--   * VIP (the pass, 599): the crown, "VIP" in the house rainbow, its perks as short lines with
--     icons (2x money in matches, +50% XP, the VIP Cue, the [VIP] chat tag) and "Same case odds
--     as everyone" (VIP never changes odds). While the welcome offer's window is open
--     (offers.VipOffer: 24 h from the first join, then one comeback window) the card sells the
--     offer instead: a gold "Welcome offer: 23:59:12" pill (never "LAST CHANCE"), the pass's
--     price struck through and the offer's price on Buy.
--   * The Starter Pack while its window is open (offers.StarterPack; "Owned" until its window
--     ends once bought): the Starter Cue and $3,000, with its countdown.
--   * Money Party: 2x money for everyone here for 15 minutes; while one runs, "Party on! 12:34
--     left" (ShopState.party, else the workspace attributes); "Full for now" at an hour queued.
--   * Fast Open (the pass): open 10 cases at once, no reel.
-- Layout: the VIP card on the left and the others as rows on the right; on a narrow page they
-- stack and scroll.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local Catalog = require(Progression:WaitForChild("Catalog"))
local Format = require(Progression:WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local ShopParts = require(script.Parent.ShopParts)
local UISound = require(script.Parent.UISound)

local V = Config.UI.Shop.Vip
local COPY: { [string]: any } = Strings.Menus.Shop :: any
local span = ShopParts.span
local round = ShopParts.round

-- The row items, top to bottom, and what each one buys.
local ROWS = { "StarterPack", "MoneyParty", "FastOpen" }

type Perk = { icon: ImageLabel, words: TextLabel }

type Row = {
	key: string,
	root: Frame,
	fill: Frame,
	icon: ImageLabel,
	name: TextLabel,
	line: TextLabel,
	timer: TextLabel, -- a countdown (the Starter Pack's window, the running party), or hidden
	buy: TextButton,
	status: ShopParts.Pill, -- "Owned"
	soon: ShopParts.Pill, -- "Coming soon" on Buy while the product is not made yet
	endsAt: number?, -- what the timer counts to
	timerWords: string?, -- its sentence ("Ends in %s")
	timerName: string?, -- a name in it (the Money Party's buyer)
}

local ShopVip = {}
ShopVip.__index = ShopVip

-- The house rainbow across a label (VIP's colour, UI_STYLE 4).
local function rainbow(parent: Instance)
	local colours = Catalog.rainbow()
	local keys = {}
	for i, c in colours do
		table.insert(
			keys,
			ColorSequenceKeypoint.new((i - 1) / (#colours - 1), Color3.fromRGB(c[1], c[2], c[3]))
		)
	end
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(keys)
	gradient.Parent = parent
end

-- A multiplier's number for "%sx": "2" for a whole one, "1.5" or "1.25" for a tuned fraction
-- (Format.commas would cut 1.5 down to 1).
local function times(n: number): string
	if n == math.floor(n) then
		return Format.commas(n)
	end
	-- Two decimals at most, without trailing zeros.
	local text = ("%.2f"):format(n):gsub("%.?0+$", "")
	return text
end

--- The VIP page inside `page`. `shop` is the ShopMenu.
function ShopVip.new(shop: any, page: Frame): any
	local self: any = setmetatable({}, ShopVip)
	self.shop = shop
	self.page = page
	local scroll = ShopParts.scroller(page, "Vip")
	self.root = scroll
	self.scroll = scroll
	self.buyKey = "Vip" -- what the VIP card's Buy buys now: the pass or the welcome offer
	self.offerEnds = nil :: number?
	self.offerWords = COPY.WelcomeOffer

	-- The VIP card.
	local card, fill = ShopParts.card(scroll, "VipCard")
	self.card, self.cardFill = card, fill
	local crown = HudParts.icon(card, "Vip", "Crown")
	crown.ZIndex = 3
	self.crown = crown
	local title = HudParts.text(card, "Title", V.TitleTextPx[2], COPY.Vip)
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 3
	rainbow(title)
	self.title = title
	local offer = ShopParts.pill(card, "Offer", "Gold")
	offer.root.Visible = false
	self.offer = offer
	local boost = Config.Economy.VipBoost
	local xp = Config.Ranks.Boosts.Vip
	local perkLines: { { icon: string, text: string } } = {
		{ icon = "CashStack", text = COPY.VipMoney:format(times(1 + boost)) },
		{ icon = "Lightning", text = COPY.VipXp:format(round(xp * 100)) },
		{ icon = "Cue", text = COPY.VipCue:format(CueThumb.cueName(Config.Shop.VipCue)) },
		{ icon = "ChatTag", text = COPY.VipTag },
		{ icon = "Odds", text = COPY.VipOdds },
	}
	self.perks = {} :: { Perk }
	for index, perk in perkLines do
		local icon = HudParts.icon(card, perk.icon, "PerkIcon" .. index)
		icon.ZIndex = 3
		local words = ShopParts.line(card, "Perk" .. index)
		words.Text = perk.text
		table.insert(self.perks, { icon = icon, words = words })
	end
	local price = ShopParts.price(card, "Price")
	self.price = price
	local buy = ShopParts.button(card, "Buy", function()
		UISound.play("Click")
		shop:buyProduct(self.buyKey)
	end)
	self.buy = buy
	local status = ShopParts.pill(card, "Status", "Green")
	status.root.Visible = false
	self.status = status
	local soon = ShopParts.pill(card, "Soon", "Gold")
	soon.root.Visible = false
	self.soon = soon

	-- The rows.
	self.rows = {} :: { Row }
	self.shown = {} :: { Row }
	for _, key in ROWS do
		table.insert(self.rows, self:buildRow(key))
	end
	return self
end

function ShopVip.buildRow(self: any, key: string): Row
	local shop = self.shop
	local root, fill = ShopParts.card(self.scroll, key)
	local icon = HudParts.icon(root, key, "Icon")
	icon.ZIndex = 3
	local name = ShopParts.name(root, "Name")
	local line = ShopParts.line(root, "Line")
	local timer = ShopParts.line(root, "Timer")
	timer.TextColor3 = HudParts.color(V.TimerColor)
	timer.Visible = false
	if key == "StarterPack" then
		name.Text = COPY.StarterPack
		line.Text = COPY.StarterLine:format(
			CueThumb.cueName(Config.Shop.StarterCue),
			Format.money(Config.Shop.StarterMoney)
		)
	elseif key == "MoneyParty" then
		name.Text = COPY.MoneyParty
		line.Text = COPY.PartyLine:format(
			times(1 + Config.Economy.PartyBoost),
			round(Config.Shop.PartySeconds / 60)
		)
	else
		name.Text = COPY.FastOpen
		line.Text = COPY.FastOpenLine:format(Config.Cases.FastOpenCount)
	end
	local buy = ShopParts.button(root, "Buy", function()
		UISound.play("Click")
		shop:buyProduct(key)
	end)
	local status = ShopParts.pill(root, "Status", "Green")
	status.root.Visible = false
	local soon = ShopParts.pill(root, "Soon", "Gold")
	soon.root.Visible = false
	return {
		key = key,
		root = root,
		fill = fill,
		icon = icon,
		name = name,
		line = line,
		timer = timer,
		buy = buy,
		status = status,
		soon = soon,
		endsAt = nil,
		timerWords = nil,
		timerName = nil,
	}
end

-- A product's Buy: its Robux price (green; pressing one not made yet only says "Coming
-- soon"), or "Full for now" (the Money Party's hour is queued); faded while its request is on
-- its way. True when the product is not made yet (its card shows the "Coming soon" tag).
local function paintBuy(shop: any, button: TextButton, key: string, product: any): boolean
	local busy = shop:isBusy(shop.productKey(key))
	local available = type(product) == "table" and product.available == true
	if available and product.canBuy == false and product.reason == "PartyFull" then
		ShopParts.setButton(button, COPY.PartyFull, "Grey", false)
	else
		local price = ShopParts.robux(ShopParts.robuxOf(product, key))
		ShopParts.setButton(button, price, "Green", not busy)
	end
	return not available
end

-- The party running now and who bought it, from the state or the workspace's attributes.
local function partyEnds(state: any, now: number): (number?, string?)
	local party = if type(state) == "table" then state.party else nil
	local ends = if type(party) == "table" then party.endsAt else nil
	local buyer = if type(party) == "table" then party.buyer else nil
	if type(ends) ~= "number" then
		ends = workspace:GetAttribute("MoneyPartyEndsAt")
		buyer = workspace:GetAttribute("MoneyPartyBuyer")
	end
	if type(ends) == "number" and ends > now then
		return ends, if type(buyer) == "string" and buyer ~= "" then buyer else nil
	end
	return nil, nil
end

--- Redraw from the shop's state.
function ShopVip.refresh(self: any, state: any)
	local shop = self.shop
	local now = ShopParts.now()
	local products = if type(state) == "table" and type(state.products) == "table"
		then state.products
		else {}
	local offers = if type(state) == "table" and type(state.offers) == "table"
		then state.offers
		else {}
	local vip = type(state) == "table" and state.vip == true

	-- The VIP card: owned, the welcome offer, or the pass.
	local offer = offers.VipOffer
	local offerOpen = not vip
		and type(offer) == "table"
		and offer.open == true
		and type(offer.endsAt) == "number"
		and offer.endsAt > now
	self.offer.root.Visible = offerOpen
	self.offerEnds = if offerOpen then offer.endsAt else nil
	self.offerWords = if offerOpen and offer.kind == "Comeback"
		then COPY.WelcomeBack
		else COPY.WelcomeOffer
	self.buyKey = if offerOpen then "VipOffer" else "Vip"
	local pass = products.Vip
	local chosen = products[self.buyKey]
	if vip then
		self.buy.Visible = false
		self.soon.root.Visible = false
		self.status.root.Visible = true
		self.status.label.Text = COPY.OwnedWord
		ShopParts.setPrice(self.price, "", nil, false)
		self.price.root.Visible = false
	else
		self.buy.Visible = true
		self.status.root.Visible = false
		self.soon.root.Visible = paintBuy(shop, self.buy, self.buyKey, chosen)
		-- The pass's price struck through beside the offer's on Buy (both live: ECONOMY 11.3).
		local old = if offerOpen then ShopParts.robux(ShopParts.robuxOf(pass, "Vip")) else nil
		ShopParts.setPrice(self.price, "", old, false)
		self.price.root.Visible = old ~= nil
	end

	-- The rows.
	table.clear(self.shown)
	for _, row in self.rows :: { Row } do
		local product = products[row.key]
		local show = true
		local owned = type(product) == "table" and product.owned == true
		row.endsAt = nil
		row.timerWords = nil
		row.timerName = nil
		if row.key == "StarterPack" then
			local window = offers.StarterPack
			local open = type(window) == "table" and window.open == true
			local ends = if type(window) == "table" and type(window.endsAt) == "number"
				then window.endsAt
				else 0
			local bought = type(state) == "table" and state.starterBought == true
			-- Shown while its window is open, and as Owned until that window would have ended.
			show = open or (bought and ends > now)
			owned = owned or bought
			if open and not owned then
				row.endsAt = ends
				row.timerWords = COPY.EndsIn
			end
		elseif row.key == "MoneyParty" then
			local ends, buyer = partyEnds(state, now)
			if ends then
				row.endsAt = ends
				row.timerWords = if buyer then COPY.PartyOnBy else COPY.PartyOn
				row.timerName = buyer
			end
			owned = false -- bought again and again
		end
		row.root.Visible = show
		if show then
			table.insert(self.shown, row)
		end
		row.timer.Visible = row.endsAt ~= nil
		if owned then
			row.buy.Visible = false
			row.soon.root.Visible = false
			row.status.root.Visible = true
			row.status.label.Text = COPY.OwnedWord
		else
			row.buy.Visible = true
			row.status.root.Visible = false
			row.soon.root.Visible = paintBuy(shop, row.buy, row.key, product)
		end
	end
	self:tick(now)
end

--- The countdowns. True when one just ran out here (the menu redraws).
function ShopVip.tick(self: any, now: number): boolean
	local crossed = false
	local ends = self.offerEnds
	if ends then
		local text = self.offerWords:format(ShopParts.timeLeft(ends - now))
		-- The pill is sized round its words: a longer countdown lays the card out again.
		crossed = crossed or now >= ends or #text ~= #self.offer.label.Text
		self.offer.label.Text = text
	end
	for _, row in self.shown :: { Row } do
		local rowEnds, words = row.endsAt, row.timerWords
		if rowEnds and words then
			local left = ShopParts.timeLeft(rowEnds - now)
			row.timer.Text = if row.timerName
				then words:format(left, row.timerName)
				else words:format(left)
			crossed = crossed or now >= rowEnds
		end
	end
	return crossed
end

-- Each perk's height on a card `w` wide: its words wrapped (a long translation takes two
-- lines) plus the gap under it. Returns the list and their sum.
function ShopVip.perkHeights(self: any, s: ShopParts.Sizes, w: number): ({ number }, number)
	local iconSize = s.line + span(V.PerkIconExtraPx, s.t)
	local width = math.max(1, w - 2 * s.pad - iconSize - s.gap)
	local gapH = span(V.PerkGapPx, s.t)
	local list: { number } = {}
	local total = 0
	for index, perk in self.perks :: { Perk } do
		local height = ShopParts.wrapHeight(perk.words.Text, s.line, width, 2) - 4 + gapH
		list[index] = height
		total += height
	end
	return list, total
end

-- The VIP card's height on a card `w` wide (its needs, before any extra room), and whether
-- the offer's pill goes under the title (no room beside it).
function ShopVip.cardNeed(self: any, s: ShopParts.Sizes, w: number): (number, boolean)
	local headerH = span(V.HeaderPx, s.t)
	local offerBelow = false
	if self.offer.root.Visible then
		local titleW = ShopParts.textWidth(self.title.Text, span(V.TitleTextPx, s.t)) + 8
		local pillW = ShopParts.textWidth(self.offer.label.Text, s.pillText)
			+ 2 * Config.UI.Shop.PillPadPx
		offerBelow = headerH + titleW + pillW + 3 * s.gap > w - 2 * s.pad
	end
	local _, perks = self:perkHeights(s, w)
	local need = s.pad
		+ headerH
		+ (if offerBelow then s.pill + s.lineGap else 0)
		+ s.lineGap
		+ perks
		+ s.gap
		+ self:soonRoom(s)
		+ s.button
		+ s.pad
	return need, offerBelow
end

-- Extra room over Buy for the top half of its "Coming soon" sticker (0 without one).
function ShopVip.soonRoom(self: any, s: ShopParts.Sizes): number
	if not self.soon.root.Visible then
		return 0
	end
	return math.max(0, math.ceil(s.pill / 2) + 2 - s.gap)
end

-- The width of a row's words in a row `w` wide (the icon's slot at the left, Buy at the right).
local function rowTextWidth(s: ShopParts.Sizes, w: number): number
	return math.max(
		1,
		w - 2 * s.pad - span(V.RowIconPx, s.t) - 2 * s.gap - span(V.RowButtonPx, s.t)
	)
end

-- A row's height in a row `w` wide: its name, its line wrapped, and its timer while one runs.
local function rowNeed(row: Row, s: ShopParts.Sizes, w: number): number
	local tw = rowTextWidth(s, w)
	local lineH = ShopParts.wrapHeight(row.line.Text, s.line, tw, 3)
	local timerH = if row.timer.Visible
		then ShopParts.wrapHeight(row.timer.Text, s.line, tw, 2)
		else 0
	local need = math.max(s.button, s.name + 6 + lineH + timerH) + 2 * s.pad
	if row.soon.root.Visible then
		-- Room over Buy for the half of the "Coming soon" sticker that sits above it.
		need = math.max(need, s.pad + math.ceil(s.pill / 2) + s.button + s.pad)
	end
	return need
end

--- Lay the page out for this size at these sizes.
function ShopVip.layout(self: any, s: ShopParts.Sizes, size: Vector2)
	local t = s.t
	local inner = ShopParts.inner(size, s)
	local gap = s.gap
	local x0, y0 = s.scrollPad, s.scrollPad
	local rows: { Row } = self.shown
	local n = #rows
	local side = inner.X >= V.SideBySideMinPx and n > 0
	local cardW = if side
		then math.clamp(
			round(inner.X * V.CardShare),
			V.CardMinPx,
			math.max(V.CardMinPx, inner.X - V.RowMinPx - gap)
		)
		else math.min(inner.X, V.CardMaxPx)
	local rowsW = if side then inner.X - cardW - gap else math.min(inner.X, V.RowMaxWidthPx)
	local cardNeed, offerBelow = self:cardNeed(s, cardW)
	local needs: { number } = {}
	local needTotal = math.max(0, n - 1) * gap
	for index, row in rows do
		needs[index] = rowNeed(row, s, rowsW)
		needTotal += needs[index]
	end
	local canvas: number
	if side then
		-- Both columns as tall as the page allows (the card never under its needs), centred;
		-- the rows share the room left over, each up to RowMaxPx.
		local cardH = math.clamp(inner.Y, cardNeed, math.max(cardNeed, V.CardMaxHeightPx))
		local share = if n > 0 then math.max(0, math.floor((cardH - needTotal) / n)) else 0
		local heights: { number } = {}
		local rowsH = math.max(0, n - 1) * gap
		for index, need in needs do
			heights[index] = need + math.min(share, math.max(0, span(V.RowMaxPx, t) - need))
			rowsH += heights[index]
		end
		local height = math.max(cardH, rowsH)
		local top = y0 + math.max(0, math.floor((inner.Y - height) / 2))
		local left = x0 + math.max(0, math.floor((inner.X - cardW - gap - rowsW) / 2))
		self:layoutCard(s, left, top + math.floor((height - cardH) / 2), cardW, cardH, offerBelow)
		local ry = top + math.floor((height - rowsH) / 2)
		for index, row in rows do
			self:layoutRow(row, s, left + cardW + gap, ry, rowsW, heights[index])
			ry += heights[index] + gap
		end
		canvas = top + height + s.scrollPad
	else
		-- Stacked: the card, then the rows, each centred.
		local left = x0 + math.floor((inner.X - cardW) / 2)
		self:layoutCard(s, left, y0, cardW, cardNeed, offerBelow)
		local at = y0 + cardNeed + gap
		local rowLeft = x0 + math.floor((inner.X - rowsW) / 2)
		for index, row in rows do
			self:layoutRow(row, s, rowLeft, at, rowsW, needs[index])
			at += needs[index] + gap
		end
		canvas = at - gap + s.scrollPad
	end
	ShopParts.setCanvas(self.scroll, canvas)
end

function ShopVip.layoutCard(
	self: any,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number,
	offerBelow: boolean
)
	local t = s.t
	local pad = s.pad
	local iw = w - 2 * pad
	self.card.Position = UDim2.fromOffset(x, y)
	self.card.Size = UDim2.fromOffset(w, h)
	local headerH = span(V.HeaderPx, t)
	local heights = self:perkHeights(s, w)
	local need = self:cardNeed(s, w)
	-- Extra room spreads between the perks (a little each), the rest above and below.
	local extra = math.max(0, h - need)
	local perkExtra = math.min(math.floor(extra / (#self.perks + 1)), span(V.PerkGapPx, t) * 2)
	local used = need + perkExtra * #self.perks
	local at = pad + math.max(0, math.floor((h - used) / 2))

	-- The crown, "VIP", and the offer's pill (beside the title, or under it).
	self.crown.Size = UDim2.fromOffset(headerH, headerH)
	self.crown.Position = UDim2.fromOffset(pad, at)
	local titleSize = math.max(Config.UI.Kit.Text.Min, span(V.TitleTextPx, t))
	HudParts.setTextSize(self.title, titleSize)
	local titleX = pad + headerH + s.gap
	local titleW = math.ceil(ShopParts.textWidth(self.title.Text, titleSize)) + 8
	self.title.Position = UDim2.fromOffset(titleX, at)
	self.title.Size = UDim2.fromOffset(math.max(1, math.min(titleW, w - titleX - pad)), headerH)
	if self.offer.root.Visible then
		if offerBelow then
			ShopParts.setPill(self.offer, self.offer.label.Text, s.pill, s.pillText, iw)
			self.offer.root.AnchorPoint = Vector2.new(0, 0)
			self.offer.root.Position = UDim2.fromOffset(pad, at + headerH + s.lineGap)
		else
			local room = w - pad - (titleX + titleW + s.gap)
			ShopParts.setPill(self.offer, self.offer.label.Text, s.pill, s.pillText, room)
			self.offer.root.AnchorPoint = Vector2.new(1, 0.5)
			self.offer.root.Position = UDim2.fromOffset(w - pad, at + round(headerH / 2))
		end
	end
	at += headerH + (if offerBelow then s.pill + s.lineGap else 0) + s.lineGap

	-- The perks: an icon and a short line each (wrapped when long).
	local iconSize = s.line + span(V.PerkIconExtraPx, t)
	for index, perk in self.perks :: { Perk } do
		local perkH = heights[index] + perkExtra
		local lineBox = heights[index] - span(V.PerkGapPx, t) + 4
		perk.icon.Size = UDim2.fromOffset(iconSize, iconSize)
		perk.icon.Position = UDim2.fromOffset(pad, at + round((lineBox - iconSize) / 2))
		HudParts.setTextSize(perk.words, s.line)
		perk.words.Position = UDim2.fromOffset(pad + iconSize + s.gap, at)
		perk.words.Size = UDim2.fromOffset(math.max(1, iw - iconSize - s.gap), lineBox)
		at += perkH
	end
	at += s.gap + self:soonRoom(s)

	-- The bottom: the struck price at the left (an offer), Buy (or Owned) at the right.
	local buttonW = iw
	if self.price.root.Visible then
		local priceW =
			ShopParts.layoutPrice(self.price, s.button, s.price, s.price, round(iw * 0.4))
		self.price.root.Position = UDim2.fromOffset(pad, at)
		buttonW = iw - priceW - s.gap
	end
	HudParts.setButtonTextSize(self.buy, s.buttonText)
	self.buy.Position = UDim2.fromOffset(w - pad - buttonW, at)
	self.buy.Size = UDim2.fromOffset(buttonW, s.button)
	-- "Coming soon" as a sticker on Buy's top right edge, sized to its words.
	if self.soon.root.Visible then
		local room = buttonW + round(pad / 2)
		local words = ShopParts.soonText(room, s.pillText)
		ShopParts.setPill(self.soon, words, s.pill, s.pillText, room)
		self.soon.root.AnchorPoint = Vector2.new(1, 0.5)
		self.soon.root.Position = UDim2.fromOffset(w - round(pad / 2), at)
	end
	ShopParts.setPill(self.status, self.status.label.Text, s.button - 8, s.buttonText, iw)
	self.status.root.AnchorPoint = Vector2.new(0.5, 0.5)
	self.status.root.Position = UDim2.fromOffset(round(w / 2), at + round(s.button / 2))
end

function ShopVip.layoutRow(
	_self: any,
	row: Row,
	s: ShopParts.Sizes,
	x: number,
	y: number,
	w: number,
	h: number
)
	local t = s.t
	local pad, gap = s.pad, s.gap
	row.root.Position = UDim2.fromOffset(x, y)
	row.root.Size = UDim2.fromOffset(w, h)
	local slot = span(V.RowIconPx, t)
	local iconSize = math.min(h - 2 * pad, slot)
	row.icon.Size = UDim2.fromOffset(iconSize, iconSize)
	row.icon.Position =
		UDim2.fromOffset(pad + round((slot - iconSize) / 2), round((h - iconSize) / 2))
	local bw = span(V.RowButtonPx, t)
	HudParts.setButtonTextSize(row.buy, s.buttonText)
	local by = round((h - s.button) / 2)
	if row.soon.root.Visible then
		-- "Coming soon" as a sticker centred on Buy's top edge, kept inside the row.
		by = math.max(by, math.ceil(s.pill / 2) + round(pad / 2))
		local room = bw + pad
		local words = ShopParts.soonText(room, s.pillText)
		ShopParts.setPill(row.soon, words, s.pill, s.pillText, room)
		row.soon.root.AnchorPoint = Vector2.new(0.5, 0.5)
		row.soon.root.Position = UDim2.fromOffset(w - pad - round(bw / 2), by)
	end
	row.buy.Position = UDim2.fromOffset(w - pad - bw, by)
	row.buy.Size = UDim2.fromOffset(bw, s.button)
	ShopParts.setPill(row.status, row.status.label.Text, s.button - 8, s.buttonText, bw)
	row.status.root.AnchorPoint = Vector2.new(0.5, 0.5)
	row.status.root.Position = UDim2.fromOffset(w - pad - round(bw / 2), round(h / 2))
	local tx = pad + slot + gap
	local tw = rowTextWidth(s, w)
	local nameH = s.name + 6
	local lineH = ShopParts.wrapHeight(row.line.Text, s.line, tw, 3)
	local timerH = if row.timer.Visible
		then ShopParts.wrapHeight(row.timer.Text, s.line, tw, 2)
		else 0
	local at = round((h - (nameH + lineH + timerH)) / 2)
	HudParts.setTextSize(row.name, s.name)
	row.name.Position = UDim2.fromOffset(tx, at)
	row.name.Size = UDim2.fromOffset(tw, nameH)
	at += nameH
	HudParts.setTextSize(row.line, s.line)
	row.line.Position = UDim2.fromOffset(tx, at)
	row.line.Size = UDim2.fromOffset(tw, lineH)
	at += lineH
	HudParts.setTextSize(row.timer, s.line)
	row.timer.Position = UDim2.fromOffset(tx, at)
	row.timer.Size = UDim2.fromOffset(tw, math.max(1, timerH))
end

--- The first button a gamepad lands on in this page.
function ShopVip.first(self: any): GuiObject?
	local list: { GuiObject? } = { self.buy }
	for _, row in self.shown :: { Row } do
		table.insert(list, row.buy)
	end
	return ShopParts.firstSelectable(list)
end

return ShopVip
