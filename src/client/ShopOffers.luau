--!strict
-- ShopOffers: the Starter Pack and VIP side by side under the restock, two wide cards (the
-- designer, 2026-10-08: "put VIP and starter side by side ... this should actually be used
-- mainly as the reference so it can fit on one page without scrolling", their second
-- reference). Each card's hero picture at its top left shows what you get: the Starter Lucky
-- Block with the Starter Cue behind it and money in front; VIP's crown alone. Beside it,
-- left-aligned, the title (the Starter Pack's letters blue to purple to pink, VIP's gold, both
-- straight), the big line ("+$25,000", "x1 -> x2 MONEY") and what the Starter Pack holds.
-- Under them the Starter Lucky Block's odds as small rarity bars (the Cues menu's, RarityBar;
-- hidden where the names would not fit, the dice has them) or VIP's six perks with their icons
-- in a pale inset panel, two columns of three (the designer, 2026-10-08: "organize it better
-- with showing the tiers and benefits"), then the buy row: the time left at the left (over the
-- row when it would not fit beside it), the gift square and the green Robux price at the right.
-- Both cards are as tall as the taller one needs (a phone's 12 px words make them taller).
-- Where paid random items are restricted the Starter Pack has no block (more money instead)
-- and VIP's daily block is money.
--
-- The Starter Pack shows until it is bought or its first week ends; VIP shows until it is
-- owned (the designer, 2026-10-08: VIP lives only here now, so it can always be bought), half
-- price with its time left while its offer is open. With neither there is no section. Both
-- packs hold a lucky block (the Starter Lucky Block; VIP's Rare block every day), so each hero
-- has the sky-blue dice opening that block's Odds & Details (Roblox's paid-random-items rule;
-- OddsDetails), hidden where paid random items are restricted. Robux through StoreRequest "Buy"
-- (StarterPack, VipOffer, or the Vip pass). Sizes in Config.UI.ShopBlocks.Pair, words in
-- Strings.Menus.Shop.Blocks.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Progression = Shared:WaitForChild("Progression")
local BlockOdds = require(Progression:WaitForChild("BlockOdds"))
local Format = require(Progression:WaitForChild("Format"))
local ArchTitle = require(script.Parent.ArchTitle)
local CueThumb = require(script.Parent.CueThumb)
local HudParts = require(script.Parent.HudParts)
local RarityBar = require(script.Parent.RarityBar)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local P = B.Pair
local K = Config.UI.Kit
local MIN_TEXT = Config.UI.GrandOpeningCard.Layout.MinTextPx
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local LIST: { [string]: any } = Config.Products.List :: any
local ICONS: { [string]: string } = K.Icons :: any
local COPY: { [string]: any } = (Strings.Menus.Shop :: any).Blocks
local RARITIES: { [string]: string } = Strings.Items.Rarities :: any
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	robux: (key: string) -> (), -- StarterPack, VipOffer or Vip
	gift: (key: string) -> (), -- the Starter Pack's gift square
	odds: (kind: string) -> (), -- a card's dice: its lucky block's Odds & Details (OddsDetails)
}

-- A hero picture: its main piece with the glow, rays and twinkles (ShopCards.Art), and for the
-- Starter Pack the Starter Cue behind the block and the money in front.
type Hero = {
	art: ShopCards.Art,
	cue: Frame?,
	cash: ImageLabel?,
}

-- One of VIP's perks on its wide card: its icon and words.
type Perk = { icon: ImageLabel, words: TextLabel }

-- A wide card (the Blocks tab's pair).
type Wide = {
	which: string, -- "Starter" or "Vip"
	frame: Frame,
	corner: UICorner,
	edge: UIStroke,
	hero: Hero,
	title: Frame, -- holds the title's letters (ArchTitle, built again when its size changes)
	titleText: string,
	titleStyle: string, -- a Config.UI.Kit.ArchTitle key
	titleUnits: number, -- its letters' size, or smaller to fit
	titleTints: { [number]: Color3 }?,
	big: { GuiObject }, -- the big row's pieces, left to right (words, and VIP's arrow)
	line: TextLabel?, -- what the Starter Pack holds
	pills: { RarityBar.Bar }, -- the Starter Lucky Block's odds
	perks: { Perk }, -- VIP's
	perkBox: Frame?, -- the pale inset panel VIP's perks sit in
	timer: TextLabel,
	green: TextButton,
	gift: TextButton?,
	odds: ShopCards.Badge,
	shown: { [string]: any },
}

-- Where a wide card's pieces go at one size (pixels), worked out before the pair's height is
-- known (both cards are as tall as the taller one needs).
type Plan = {
	pad: number,
	hero: number,
	colX: number, -- the words beside the hero: their left edge and width
	colW: number,
	innerW: number,
	rowGap: number,
	gap: number,
	titleH: number,
	bigPx: number,
	bigH: number,
	linePx: number,
	lineH: number,
	textH: number,
	topH: number, -- the hero's row: the hero or the words beside it, the taller
	pillsOn: boolean,
	pillPx: number,
	pillW: number,
	pillH: number,
	perkCols: number,
	perkPx: number,
	perkIcon: number,
	perkRowH: number,
	perkPad: number, -- the perks' panel's inner room
	belowH: number, -- the odds or the perks
	timerPx: number,
	timerH: number,
	timerOver: boolean, -- the time left over the buy row (it would not fit beside it)
	buyH: number,
	buyTextPx: number,
	greenW: number,
	giftPx: number,
	giftGap: number,
	need: number, -- the card's height for all of it
}

local ShopOffers = {}
ShopOffers.__index = ShopOffers

--------------------------------------------------------------------------------------------
-- Pieces
--------------------------------------------------------------------------------------------

-- Show or hide a dice (hidden where its block is money instead).
local function showOdds(odds: ShopCards.Badge?, on: boolean)
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

-- Give `object` its place in a hero by Config shares: centre x, centre y, size (of its side).
local function share(object: GuiObject, at: { number })
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromScale(at[1], at[2])
	object.Size = UDim2.fromScale(at[3], at[3])
end

-- A picture by a Pair key: a Kit.Icons key, or "Block:<kind>" for that lucky block's.
local function iconOf(key: string): string
	local kind = string.match(key, "^Block:(.+)$")
	if kind then
		local row = KINDS[kind]
		return if row then row.Icon else ""
	end
	return ICONS[key] or ""
end

-- Each letter of `text` its own colour, blended first to last through `colors`.
local function blend(text: string, colors: { { number } }): { [number]: Color3 }
	local tints: { [number]: Color3 } = {}
	local count = utf8.len(text) or 1
	local steps = #colors - 1
	for i = 1, count do
		local at = if count > 1 then (i - 1) / (count - 1) * steps else 0
		local from = math.clamp(math.floor(at), 0, math.max(0, steps - 1))
		local a = rgb(colors[from + 1])
		local b = rgb(colors[math.min(#colors, from + 2)])
		tints[i] = a:Lerp(b, at - from)
	end
	return tints
end

-- The Starter Pack's hero in `parent`: the Starter Lucky Block, the Starter Cue behind it and
-- money in front, on a gold glow.
local function starterHero(parent: Instance, z: number): Hero
	local block = KINDS[Config.Shop.StarterBlock]
	local art =
		ShopCards.art(parent, "Hero", if block then block.Icon else "", rgb(P.Starter.GlowTint), z)
	share(art.picture, P.StarterBlock)
	art.picture.ZIndex = z + 2
	local cue = CueThumb.new(art.holder, Config.Shop.StarterCue)
	cue.Name = "Cue"
	cue.ZIndex = z + 1
	share(cue, P.StarterCue)
	local cash = ShopCards.image(art.holder, "Cash", ICONS.CashStack, z + 3)
	share(cash, P.StarterCash)
	for _, twinkle in art.twinkles do
		twinkle.ZIndex = z + 4
	end
	return { art = art, cue = cue, cash = cash }
end

-- VIP's hero in `parent`: the crown alone in the middle of its gold glow.
local function vipHero(parent: Instance, z: number): Hero
	local art = ShopCards.art(parent, "Hero", ICONS.Vip, rgb(P.Vip.GlowTint), z)
	share(art.picture, P.VipCrown)
	art.picture.ZIndex = z + 2
	for _, twinkle in art.twinkles do
		twinkle.ZIndex = z + 4
	end
	return { art = art, cue = nil, cash = nil }
end

--------------------------------------------------------------------------------------------
-- The wide cards (the Blocks tab)
--------------------------------------------------------------------------------------------

-- The parts both wide cards have: the card in `look`'s colours, its hero (`makeHero`), the
-- title's holder, the time left, the green button (`onBuy`) and the dice (`onOdds`).
local function wide(
	parent: Instance,
	which: string,
	look: ShopCards.Look,
	makeHero: (Frame) -> Hero,
	onBuy: () -> (),
	onOdds: () -> ()
): Wide
	local box = ShopCards.gradientCard(parent, "Offer" .. which, look, 3)
	local frame = box.frame
	local title = HudParts.frame(frame, "Title")
	title.ZIndex = 6
	local timer = HudParts.text(frame, "Timer", MIN_TEXT, "", rgb(K.Numbers.Count))
	timer.TextWrapped = false
	timer.ZIndex = 6
	local odds = ShopCards.oddsBadge(frame, "OddsBadge", 8)
	odds.hit.Activated:Connect(function()
		UISound.play("Click")
		onOdds()
	end)
	return {
		which = which,
		frame = frame,
		corner = box.corner,
		edge = box.edge,
		hero = makeHero(frame),
		title = title,
		titleText = "",
		titleStyle = "Gold",
		titleUnits = P.TitleUnits,
		titleTints = nil,
		big = {},
		line = nil,
		pills = {},
		perks = {},
		timer = timer,
		green = ShopCards.robuxButton(frame, "Robux", onBuy),
		gift = nil,
		odds = odds,
		shown = {},
	}
end

-- One of the big row's words, from its left edge.
local function bigWord(c: Wide, name: string, text: string, tint: Color3?): TextLabel
	local made = ShopCards.label(c.frame, name, text, tint, 6)
	made.AnchorPoint = Vector2.new(0, 0.5)
	return made
end

-- The Starter Pack's wide card: its hero, title, the money ("+$25,000"), what it holds, the
-- Starter Lucky Block's odds, the time left, the gift square and the price.
local function starterCard(self: any, parent: Instance): Wide
	local c = wide(parent, "Starter", P.Starter, function(frame)
		return starterHero(frame, 4)
	end, function()
		self.actions.robux("StarterPack")
	end, function()
		self.actions.odds(Config.Shop.StarterBlock)
	end)
	c.titleText = COPY.StarterName
	c.titleStyle = "Starter"
	c.titleTints = blend(COPY.StarterName, P.Starter.TitleColors)
	c.big = { bigWord(c, "Money", "", rgb(K.Numbers.Money)) }
	local holds = HudParts.note(c.frame, "Line", MIN_TEXT, COPY.StarterLine)
	holds.TextXAlignment = Enum.TextXAlignment.Left
	holds.TextYAlignment = Enum.TextYAlignment.Top
	holds.ZIndex = 6
	c.line = holds
	local block = KINDS[Config.Shop.StarterBlock]
	local oddsId = if block and type(block.Odds) == "string"
		then block.Odds
		else Config.Shop.StarterBlock
	for index, entry in BlockOdds.odds(oddsId) do
		local bar = RarityBar.new(c.frame, "Odds" .. index, 6)
		RarityBar.paint(
			bar,
			entry.rarity,
			RARITIES[entry.rarity] or entry.rarity,
			entry.display,
			true
		)
		table.insert(c.pills, bar)
	end
	c.gift = ShopCards.giftButton(c.green, function()
		self.actions.gift("StarterPack")
	end)
	return c
end

-- VIP's wide card: its hero, the straight gold title, "x1 -> x2 MONEY", the perks in their
-- panel, the offer's time left and the price.
local function vipWide(self: any, parent: Instance): Wide
	local c = wide(parent, "Vip", P.Vip, function(frame)
		return vipHero(frame, 4)
	end, function()
		self.actions.robux(self.vipKey)
	end, function()
		self.actions.odds(vipBlock())
	end)
	c.titleText = COPY.VipTitle
	c.titleStyle = "VipStraight"
	c.titleUnits = P.VipTitleUnits
	local arrow = HudParts.icon(c.frame, "Arrow", "Arrow")
	arrow.ZIndex = 6
	c.big = {
		bigWord(c, "X1", COPY.VipX1),
		arrow,
		bigWord(c, "X2", COPY.VipX2, rgb(P.Vip.TwoXColor)),
		bigWord(c, "Money", COPY.VipMoney),
	}
	local box = HudParts.frame(c.frame, "Perks")
	box.BackgroundColor3 = rgb(P.Vip.PerkBox)
	box.BackgroundTransparency = P.Vip.PerkBoxTransparency
	box.ZIndex = 5
	HudParts.corner(box, 0)
	local rim = Instance.new("UIStroke")
	rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	rim.Color = rgb(P.Vip.PerkBoxEdge)
	rim.Parent = box
	c.perkBox = box
	for index, text in COPY.VipPerksWide do
		local icon = ShopCards.image(box, "PerkIcon" .. index, iconOf(P.VipPerkIcons[index]), 6)
		local words = HudParts.note(box, "Perk" .. index, MIN_TEXT, text)
		words.TextXAlignment = Enum.TextXAlignment.Left
		words.TextWrapped = false
		words.AnchorPoint = Vector2.new(0, 0.5)
		words.ZIndex = 6
		table.insert(c.perks, { icon = icon, words = words })
	end
	return c
end

--- Build the offers (closed) into `parent` (the Shop's Blocks group).
function ShopOffers.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, ShopOffers)
	self.actions = actions
	self.k = 1
	self.show = { Starter = false, Vip = false } -- which cards the state shows
	self.vipKey = "Vip" -- the product the VIP button buys (VipOffer while its offer is open)
	self.fake = nil -- Studio only: a patch over the shop state (ShopMenu's GuiQA "offers")
	local root = HudParts.frame(parent, "Offers")
	root.ZIndex = 2
	self.root = root
	self.starter = starterCard(self, root)
	self.vip = vipWide(self, root)
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- The title's letters at `px` (ArchTitle), smaller when their ink would be wider than `maxW`;
-- built again only when either changes. Returns the size used.
local function titleAt(c: Wide, px: number, maxW: number): number
	local key = string.format("%s|%d|%d", c.titleText, px, maxW)
	if c.shown.titleKey == key then
		return c.shown.titlePx
	end
	c.shown.titleKey = key
	local size = px
	for _ = 1, 3 do
		for _, child in c.title:GetChildren() do
			child:Destroy()
		end
		local made = ArchTitle.new(c.title, c.titleText, c.titleStyle, size, c.titleTints)
		-- Its ink starts at the holder's left edge, as the words under it do.
		made.root.AnchorPoint = Vector2.new(0, 0.5)
		made.root.Position = UDim2.new(0, -math.floor(made.inset), 0.5, 0)
		local ink = made.width - 2 * made.inset
		if ink <= maxW or size <= MIN_TEXT then
			break
		end
		size = math.max(MIN_TEXT, math.floor(size * maxW / ink))
	end
	c.shown.titlePx = size
	return size
end

-- A big row piece's width at `px`: a word's, or the arrow's.
local function pieceWidth(piece: GuiObject, px: number): number
	if piece:IsA("TextLabel") then
		return ShopCards.measure((piece :: TextLabel).Text, px)
	end
	return round(px * P.ArrowShare)
end

-- How wide the big row is at `px`: its pieces and the room between them.
local function bigWidth(c: Wide, px: number): number
	local total = 0
	for index, piece in c.big do
		total += pieceWidth(piece, px) + (if index > 1 then round(px * P.BigGapShare) else 0)
	end
	return total
end

-- Where card `c`'s pieces go at the scale `k`, `cardW` pixels wide.
local function plan(c: Wide, k: number, cardW: number): Plan
	local pad = round(P.PadUnits * k)
	local hero = round(P.HeroUnits * k)
	local colX = pad + hero + round(P.TextGapUnits * k)
	local colW = math.max(1, cardW - colX - pad)
	local innerW = math.max(1, cardW - 2 * pad)
	local rowGap = math.max(B.TextGapPx, round(P.RowGapUnits * k))
	local gap = math.max(B.TextGapPx, round(P.SectionGapUnits * k))

	-- Beside the hero: the title, the big row and what the Starter Pack holds, each as big as
	-- its units or smaller to fit the column.
	local titleH = round(titleAt(c, ShopCards.textPx(c.titleUnits, k), colW) * P.TitleLineShare)
	local bigPx = ShopCards.textPx(P.BigUnits, k)
	local bigW = bigWidth(c, bigPx)
	if bigW > colW then
		bigPx = math.max(MIN_TEXT, math.floor(bigPx * colW / bigW))
	end
	local bigH = bigPx + B.TextBoxPx
	local textH = titleH + rowGap + bigH
	local linePx, lineH = 0, 0
	local holds = c.line
	if holds then
		linePx = ShopCards.textPx(P.LineUnits, k)
		lineH = ShopParts.wrapHeight(holds.Text, linePx, colW, P.LineMaxRows)
		textH += rowGap + lineH
	end

	-- Under them: the Starter Lucky Block's odds while every bar holds its words, or VIP's
	-- perks in two columns (one when the longest would shrink too much in half the card).
	local count = #c.pills
	local pillsOn = count > 0 and c.shown.restricted ~= true
	local pillPx = ShopCards.textPx(P.PillTextUnits, k)
	local pillW =
		math.floor((innerW - (count - 1) * round(P.PillGapUnits * k)) / math.max(1, count))
	local pillH = math.max(round(P.PillUnits * k), 2 * pillPx + 2 * B.PillPadPx + B.TextBoxPx)
	for _, bar in c.pills do
		if not RarityBar.stackedFits(bar, pillW, pillPx) then
			pillsOn = false
		end
	end
	local perkCols, perkPx, perkIcon, perkRowH = 0, 0, 0, 0
	local perkPad = if c.perkBox then math.max(B.TextGapPx, round(P.PerkBoxPadUnits * k)) else 0
	if #c.perks > 0 then
		perkIcon = math.max(MIN_TEXT + B.TextGapPx, round(P.PerkIconUnits * k))
		local beside = perkIcon + round(P.PerkGapUnits * k) -- the icon and the room after it
		local nominal = ShopCards.textPx(P.PerkTextUnits, k)
		local widest = 1
		for _, perk in c.perks do
			widest = math.max(widest, ShopCards.measure(perk.words.Text, nominal))
		end
		local boxW = innerW - 2 * perkPad
		local half = (boxW - round(P.PerkColumnGapUnits * k)) / 2 - beside
		local halfPx = math.min(nominal, math.floor(nominal * half / widest))
		if halfPx >= math.max(MIN_TEXT, nominal * P.PerkShrinkMin) then
			perkCols, perkPx = 2, halfPx
		else
			local whole = boxW - beside
			perkCols = 1
			perkPx = math.max(MIN_TEXT, math.min(nominal, math.floor(nominal * whole / widest)))
		end
		perkRowH = math.max(round(P.PerkRowUnits * k), perkPx + B.TextBoxPx, perkIcon + B.TextGapPx)
	end
	local belowH = if pillsOn
		then pillH
		elseif perkCols > 0 then math.ceil(#c.perks / perkCols) * perkRowH + 2 * perkPad
		else 0

	-- The buy row: the gift square and the green button at the right, the time left beside
	-- them, or over them when its widest time would not fit there.
	local buyH = ShopCards.buttonPx(P.BuyUnits, k)
	local giftPx = if c.gift then math.max(B.MinGiftPx, round(P.GiftUnits * k)) else 0
	local giftGap = if c.gift then round(P.GiftGapUnits * k) else 0
	local greenW = math.min(round(P.BuyWidthUnits * k), innerW - giftPx - giftGap)
	local timerPx = ShopCards.textPx(P.TimerTextUnits, k)
	local timerH = timerPx + B.TextBoxPx
	local widest = ShopCards.measure(string.format(COPY.EndsIn, P.TimerSample), timerPx)
	local timerOver = c.timer.Visible and widest > innerW - giftPx - giftGap - greenW - gap
	local topH = math.max(hero, textH)
	local need = pad
		+ topH
		+ (if belowH > 0 then gap + belowH else 0)
		+ gap
		+ (if timerOver then timerH + rowGap else 0)
		+ buyH
		+ pad
	return {
		pad = pad,
		hero = hero,
		colX = colX,
		colW = colW,
		innerW = innerW,
		rowGap = rowGap,
		gap = gap,
		titleH = titleH,
		bigPx = bigPx,
		bigH = bigH,
		linePx = linePx,
		lineH = lineH,
		textH = textH,
		topH = topH,
		pillsOn = pillsOn,
		pillPx = pillPx,
		pillW = pillW,
		pillH = pillH,
		perkCols = perkCols,
		perkPx = perkPx,
		perkIcon = perkIcon,
		perkRowH = perkRowH,
		perkPad = perkPad,
		belowH = belowH,
		timerPx = timerPx,
		timerH = timerH,
		timerOver = timerOver,
		buyH = buyH,
		buyTextPx = ShopCards.textPx(P.BuyTextUnits, k),
		greenW = greenW,
		giftPx = giftPx,
		giftGap = giftGap,
		need = need,
	}
end

-- Place card `c`'s pieces by its plan `p`, the card `cardW` x `cardH` pixels.
local function place(c: Wide, p: Plan, k: number, cardW: number, cardH: number)
	c.corner.CornerRadius = UDim.new(0, round(P.CornerUnits * k))
	c.edge.Thickness = math.max(B.MinStrokePx, P.EdgeUnits * k)

	-- The hero and the words beside it, centred on each other; the dice on the hero's corner.
	local heroTop = p.pad + (p.topH - p.hero) / 2
	local heroX, heroY = p.pad + p.hero / 2, heroTop + p.hero / 2
	ShopCards.layoutArt(c.hero.art, k, heroX / k, heroY / k, P.HeroUnits, P.Glow, P.Rays)
	local A = P.OddsBadge
	local dice = math.max(MIN_TEXT + B.BadgePadPx, round(A[3] * k))
	local edge = dice / 2 + B.TextGapPx -- never past the card's edge
	local diceX = math.max(edge, p.pad + A[1] * k)
	ShopCards.putPx(c.odds.badge, diceX, math.max(edge, heroTop + A[2] * k), dice, dice)

	local y = p.pad + (p.topH - p.textH) / 2
	c.title.Position = UDim2.fromOffset(p.colX, round(y))
	c.title.Size = UDim2.fromOffset(p.colW, p.titleH)
	y += p.titleH + p.rowGap
	local x = p.colX
	for index, piece in c.big do
		local w = pieceWidth(piece, p.bigPx)
		x += if index > 1 then round(p.bigPx * P.BigGapShare) else 0
		piece.AnchorPoint = Vector2.new(0, 0.5)
		piece.Position = UDim2.fromOffset(round(x), round(y + p.bigH / 2))
		if piece:IsA("TextLabel") then
			piece.Size = UDim2.fromOffset(w, p.bigH)
			HudParts.setTextSize(piece :: TextLabel, p.bigPx)
		else
			piece.Size = UDim2.fromOffset(w, w)
		end
		x += w
	end
	y += p.bigH + p.rowGap
	local holds = c.line
	if holds then
		holds.Position = UDim2.fromOffset(p.colX, round(y))
		holds.Size = UDim2.fromOffset(p.colW, p.lineH)
		HudParts.setTextSize(holds, p.linePx)
	end

	-- The buy row at the foot; the odds or the perks in the middle of the room left above it.
	local buyY = cardH - p.pad - p.buyH / 2
	local top = p.pad + p.topH + p.gap
	local bottom = cardH - p.pad - p.buyH - p.gap - (if p.timerOver then p.timerH + p.rowGap else 0)
	local midTop = round(top + math.max(0, (bottom - top - p.belowH) / 2))
	local count = #c.pills
	local pillGap = round(P.PillGapUnits * k)
	local pillsLeft = p.pad + (p.innerW - count * p.pillW - (count - 1) * pillGap) / 2
	for index, bar in c.pills do
		bar.frame.Visible = p.pillsOn
		if p.pillsOn then
			local left = round(pillsLeft + (index - 1) * (p.pillW + pillGap))
			RarityBar.layoutStacked(bar, left, midTop, p.pillW, p.pillH, p.pillPx)
		end
	end
	local box = c.perkBox
	if box and p.perkCols > 0 then
		-- The panel across the card; the perks inside it, measured from its corner.
		box.Position = UDim2.fromOffset(p.pad, midTop)
		box.Size = UDim2.fromOffset(p.innerW, p.belowH)
		local corner = box:FindFirstChildOfClass("UICorner")
		if corner then
			corner.CornerRadius = UDim.new(0, round(P.PerkBoxCornerUnits * k))
		end
		local rim = box:FindFirstChildOfClass("UIStroke")
		if rim then
			rim.Thickness = math.max(1, P.PerkBoxEdgeUnits * k)
		end
		local inner = p.innerW - 2 * p.perkPad
		local columnGap = round(P.PerkColumnGapUnits * k)
		local columnW = (inner - (p.perkCols - 1) * columnGap) / p.perkCols
		local beside = p.perkIcon + round(P.PerkGapUnits * k)
		for index, perk in c.perks do
			local left = p.perkPad + ((index - 1) % p.perkCols) * (columnW + columnGap)
			local rowY = p.perkPad + ((index - 1) // p.perkCols + 0.5) * p.perkRowH
			ShopCards.putPx(perk.icon, left + p.perkIcon / 2, rowY, p.perkIcon, p.perkIcon)
			perk.words.Position = UDim2.fromOffset(round(left + beside), round(rowY))
			perk.words.Size =
				UDim2.fromOffset(math.max(1, round(columnW - beside)), p.perkPx + B.TextBoxPx)
			HudParts.setTextSize(perk.words, p.perkPx)
		end
	end

	-- The green button at the right with the time left beside it, or the row in the middle.
	local timer = c.timer
	local rowW = p.giftPx + p.giftGap + p.greenW
	local right = if timer.Visible and not p.timerOver then cardW - p.pad else (cardW + rowW) / 2
	local green = c.green
	green.AnchorPoint = Vector2.new(0.5, 0.5)
	green.Position = UDim2.fromOffset(round(right - p.greenW / 2), round(buyY))
	green.Size = UDim2.fromOffset(p.greenW, p.buyH)
	HudParts.setButtonTextSize(green, p.buyTextPx)
	HudParts.setMinHit(green, TOUCH)
	local gift = c.gift
	if gift then
		gift.Position = UDim2.new(0, -p.giftGap, 0.5, 0)
		gift.Size = UDim2.fromOffset(p.giftPx, p.giftPx)
		HudParts.setMinHit(gift, TOUCH)
	end
	HudParts.setTextSize(timer, p.timerPx)
	if p.timerOver then
		timer.AnchorPoint = Vector2.new(0.5, 0.5)
		timer.TextXAlignment = Enum.TextXAlignment.Center
		local timerY = buyY - p.buyH / 2 - p.rowGap - p.timerH / 2
		timer.Position = UDim2.fromOffset(round(cardW / 2), round(timerY))
		timer.Size = UDim2.fromOffset(p.innerW, p.timerH)
	else
		timer.AnchorPoint = Vector2.new(0, 0.5)
		timer.TextXAlignment = Enum.TextXAlignment.Left
		timer.Position = UDim2.fromOffset(p.pad, round(buyY))
		timer.Size = UDim2.fromOffset(math.max(1, p.innerW - rowW - p.gap), p.timerH)
	end
end

--- Lay the cards out across `width` pixels at the scale `k`, the section's top `y` pixels down
--- the page; returns its height (0 with no card).
function ShopOffers.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local pageW = round(Config.UI.GrandOpeningCard.Layout.Card[1] * k)
	local cardW = round(P.CardUnits[1] * k)
	local gap = round(P.GapUnits * k)
	local cards: { Wide } = {}
	for _, c in { self.starter, self.vip } :: { Wide } do
		c.frame.Visible = self.show[c.which] == true
		if c.frame.Visible then
			table.insert(cards, c)
		end
	end
	-- Both as tall as the taller one needs; two side by side across the page, one alone in the
	-- middle.
	local height = if #cards > 0 then round(P.CardUnits[2] * k) else 0
	local plans: { Plan } = {}
	for index, c in cards do
		plans[index] = plan(c, k, cardW)
		height = math.max(height, plans[index].need)
	end
	local left = (pageW - #cards * cardW - math.max(0, #cards - 1) * gap) / 2
	for index, c in cards do
		local x = left + (index - 1) * (cardW + gap) + cardW / 2
		ShopCards.putPx(c.frame, x, height / 2, cardW, height)
		place(c, plans[index], k, cardW, height)
	end
	self.root.Position = UDim2.fromOffset(math.floor((width - pageW) / 2), y)
	self.root.Size = UDim2.fromOffset(pageW, height)
	self.root.Visible = height > 0
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

-- VIP's button words: "Owned" for a VIP, half price (the full one struck through) while its
-- offer is open, else the full price.
local function vipWords(products: any, owned: boolean, offerOn: boolean): string
	if owned then
		return COPY.Owned
	elseif offerOn then
		return ShopCards.robuxText(robuxOf(products, "VipOffer"), robuxOf(products, "Vip"))
	end
	return ShopCards.robuxText(robuxOf(products, "Vip"))
end

-- A button's words and, for VIP, its owned look, only when they change.
local function setButton(green: TextButton, shown: { [string]: any }, words: string, owned: boolean)
	if shown.words ~= words then
		shown.words = words
		ShopCards.setButtonWords(green, words)
	end
	if shown.owned ~= owned then
		shown.owned = owned
		HudParts.setButtonIcon(green, if owned then "Check" else nil)
		HudParts.setEnabled(green, not owned)
	end
end

-- A wide card's time left until `endsAt` while `on`. True when it came or went (the buy row
-- moves).
local function timerTo(c: Wide, on: boolean, endsAt: any, now: number): boolean
	local left = if type(endsAt) == "number" then endsAt - now else 0
	local show = on and left > 0
	setText(c.timer, if show then string.format(COPY.EndsIn, ShopCards.timeLeft(left)) else "")
	if c.timer.Visible ~= show then
		c.timer.Visible = show
		return true
	end
	return false
end

--- Draw the shop state. Returns true when the cards must be laid out again (a card came or
--- went, a timer, a restricted region's words).
function ShopOffers.refresh(self: any, state: any): boolean
	if type(state) ~= "table" then
		return false
	end
	if type(self.fake) == "table" then
		state = table.clone(state)
		for key, value in self.fake do
			state[key] = value
		end
	end
	local offers = if type(state.offers) == "table" then state.offers else {}
	local products = if type(state.products) == "table" then state.products else {}
	local restricted = state.restricted == true
	local owned = state.vip == true
	local starter = if type(offers.StarterPack) == "table" then offers.StarterPack else {}
	local vipOffer = if type(offers.VipOffer) == "table" then offers.VipOffer else {}
	local starterOn = starter.open == true and state.starterBought ~= true
	local offerOn = vipOffer.open == true and not owned
	local vipOn = not owned -- VIP lives only here: shown until it is owned
	local changed = self.show.Starter ~= starterOn or self.show.Vip ~= vipOn
	self.show.Starter, self.show.Vip = starterOn, vipOn
	local now = ShopParts.now()

	-- The Starter Pack: where paid random items are restricted, no block and more money.
	local s: Wide = self.starter
	if s.shown.restricted ~= restricted then
		s.shown.restricted = restricted
		s.hero.art.picture.Visible = not restricted
		showOdds(s.odds, not restricted)
		local holds = s.line
		if holds then
			holds.Text = if restricted then COPY.StarterLineRestricted else COPY.StarterLine
		end
		local money = s.big[1] :: TextLabel
		money.Text = string.format(
			COPY.StarterPlus,
			Format.money(
				if restricted then Config.Shop.StarterRestrictedMoney else Config.Shop.StarterMoney
			)
		)
		changed = true
	end
	changed = timerTo(s, starterOn, starter.endsAt, now) or changed
	setButton(s.green, s.shown, ShopCards.robuxText(robuxOf(products, "StarterPack")), false)

	-- VIP: its daily block is money where paid random items are restricted.
	local v: Wide = self.vip
	if v.shown.restricted ~= restricted then
		v.shown.restricted = restricted
		showOdds(v.odds, not restricted)
		local first = v.perks[1]
		if first then
			first.words.Text = if restricted
				then COPY.VipPerkWideRestricted
				else COPY.VipPerksWide[1]
			first.icon.Image =
				iconOf(if restricted then P.VipPerkIconRestricted else P.VipPerkIcons[1])
		end
		changed = true
	end
	changed = timerTo(v, offerOn, vipOffer.endsAt, now) or changed
	setButton(v.green, v.shown, vipWords(products, owned, offerOn), owned)
	self.vipKey = if offerOn then "VipOffer" else "Vip"
	return changed
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

-- A wide card's idle loops: its hero's (the glow breathes, the rays turn, the twinkles pop),
-- its Robux button's shine (from `delay` seconds) and VIP's crown rocking.
local function wideLoops(c: Wide, delay: number): UIAnim.Handle
	local list = {
		ShopCards.artLoops(c.hero.art),
		ShopCards.buttonShine(c.green, B.ButtonShineEvery, delay),
	}
	if c.which == "Vip" then
		local R = P.Vip.CrownRock
		table.insert(list, UIAnim.turn(c.hero.art.picture, 0, R[1], R[2]))
	end
	return ShopCards.all(list)
end

--- Register both wide cards with the Shop's `stage` (ids in Config.UI.Shop.Open);
--- `keep(handle)` holds their idle loops until the Shop closes.
function ShopOffers.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	for index, c in { self.starter, self.vip } :: { Wide } do
		stage:add("Offer" .. c.which, c.frame, function()
			keep(wideLoops(c, (index - 1) * B.ShineStaggerSeconds))
		end)
	end
end

return ShopOffers
