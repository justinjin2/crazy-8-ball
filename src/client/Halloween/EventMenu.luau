--!strict
-- EventMenu: the Halloween event's menu (mock A, ~/Desktop/8ball-refs/halloween/mocks/v4/A.png;
-- designer 2026-10-29). The lively frame (MenuFrame: the panel unrolls, the header, the red X,
-- the 8-ball flair) with the player's Candy and "ENDS IN 5d 15h" pills in its header, then:
--   * four pink UNIQUE cue cards in Config.Halloween.Cues.List's order, easiest first (the
--     Pitchfork, the Witch's Broom, the Jack-o'-Lantern, the Halloween Sword; designer
--     2026-10-29), each with the Cues inventory's faint 8-balls drifting up-left, the cue's
--     picture (its skin Thumb through CueThumb) with its own effects playing over it in 2D
--     (Halloween/CardFx, richer up the ladder), a big green Robux button (the purple gift square inside its left end; it
--     shines) over a smaller orange Candy button (a first press says BUY?, a second buys:
--     State.send({ buy = cue }), the answer comes as the bought moment). An owned cue's card
--     says OWNED. (With the Pumpkin King's drop switched on, a drop cue not on sale gets the
--     PUMPKIN KING DROP ribbon instead of buttons.) Each card's pink edge lies inside its box,
--     so the scroller never cuts it (designer, 2026-10-29);
--   * TODAY'S QUESTS: today's board only, four rows (icon, line, bar, count, Candy chip or a
--     bouncing CLAIM), "New quests in 14:28";
--   * GET CANDY: the two packs, green Robux buttons with their gift squares.
-- Placed in Config.UI.Halloween.Menu.Layout's units (HwMenuMath): a computer shows it all, a
-- phone the cue row whole with the quests' header peeking. Built once, redrawn from
-- Halloween/State's view; one 1 s clock while open, and one per-frame loop for the cards'
-- 8-balls and effects (only while open, only for cards on screen).
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared.Progression.Format)
local HwMenuMath = require(Shared:WaitForChild("HwMenuMath"))
local CardMath = require(Shared:WaitForChild("CardMath"))
local Clock = require(Shared.Halloween.Clock)
local Event = require(Shared.Halloween.Event)
local CueThumb = require(script.Parent.Parent.CueThumb)
local GuiQA = require(script.Parent.Parent.GuiQA)
local HudParts = require(script.Parent.Parent.HudParts)
local ItemState = require(script.Parent.Parent.ItemState)
local MenuFrame = require(script.Parent.Parent.MenuFrame)
local Menus = require(script.Parent.Parent.Menus)
local PadMode = require(script.Parent.Parent.PadMode)
local Quality = require(script.Parent.Parent.Quality)
local ShopCards = require(script.Parent.Parent.ShopCards)
local ShopGift = require(script.Parent.Parent.ShopGift)
local ShopParts = require(script.Parent.Parent.ShopParts)
local UIAnim = require(script.Parent.Parent.UIAnim)
local UISound = require(script.Parent.Parent.UISound)
local CardFx = require(script.Parent.CardFx)
local State = require(script.Parent.State)

local NAME = "Halloween"
local H = Config.Halloween
local M = Config.UI.Halloween.Menu
local L = M.Layout
local ART = Config.UI.Halloween.Art
local QICONS: { [string]: string } = Config.UI.Halloween.QuestIcons :: any
local LOOK = Config.UI.CueCard.Looks.Unique
local CC = Config.UI.CueCard
local K = Config.UI.Kit
local W = Strings.Halloween
local CUE_SHORT: { [string]: string } = W.CueShort :: any
local CARD_FX = Config.UI.Halloween.CardFx
local FAILED: { [string]: string } = W.BuyFailed :: any
local SHOP_COPY: { [string]: any } = Strings.Menus.Shop :: any
local FONT: Enum.Font = (Enum.Font :: any)[K.Font]
local SHORT_SCREEN: number = (Config.UI.Menu.Lively.Frame :: any).ShortScreenPx
	or Config.UI.Menu.Frame.ShortScreenPx

local EventMenu = {}

local function rgb(t: { number }): Color3
	return Color3.fromRGB(t[1], t[2], t[3])
end

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function textWidth(text: string, px: number): number
	return TextService:GetTextSize(text, px, FONT, Vector2.new(4000, 400)).X
end

-- A plain picture under `parent`.
local function picture(parent: Instance, name: string, image: string): ImageLabel
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.ScaleType = Enum.ScaleType.Fit
	label.Image = image
	label.Parent = parent
	return label
end

-- A Kit icon or a raw image id ("rbxassetid://...").
local function imageOf(key: string): string
	if string.sub(key, 1, 13) == "rbxassetid://" then
		return key
	end
	return (K.Icons :: any)[key] or ""
end

-- A rounded box with the ink edge, filled with `tint`.
local function panel(parent: Instance, name: string, tint: Color3): (Frame, UICorner)
	local f = HudParts.frame(parent, name)
	f.BackgroundTransparency = 0
	f.BackgroundColor3 = tint
	local corner = HudParts.corner(f, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HudParts.tone("Ink")
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = f
	return f, corner
end

local function gradientOf(colors: { { number } }): ColorSequence
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), rgb(c)))
	end
	return ColorSequence.new(keys)
end

-- The Unique look's fill (top to bottom).
local function fillSequence(): ColorSequence
	local keys = {}
	for i, c in LOOK.Fill do
		table.insert(keys, ColorSequenceKeypoint.new(LOOK.FillAt[i], Color3.fromHex(c)))
	end
	return ColorSequence.new(keys)
end

-- Paint a candy button orange (the Kit has no orange tone) with the candy icon.
local function makeOrange(button: TextButton)
	local parts = HudParts.candyParts(button)
	if parts == nil then
		return
	end
	local c = M.CandyButton
	local lip = 1 - K.ButtonLipShare
	parts.gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, rgb(c.Top)),
		ColorSequenceKeypoint.new(0.42, rgb(c.Mid)),
		ColorSequenceKeypoint.new(lip - 0.001, rgb(c.Mid)),
		ColorSequenceKeypoint.new(lip, rgb(c.Lip)),
		ColorSequenceKeypoint.new(1, rgb(c.Lip)),
	})
	parts.icon.Image = H.CandyIcon
end

-- A green Robux button with its purple gift square inside its left end (mock A); the words
-- keep clear of the square (a UIPadding on the label).
type RobuxPair = { green: TextButton, gift: TextButton, pad: UIPadding }

local function robuxPair(parent: Instance, onBuy: () -> (), onGift: () -> ()): RobuxPair
	local green = ShopCards.robuxButton(parent, "Robux", onBuy)
	green.AnchorPoint = Vector2.zero
	local gift = ShopCards.giftButton(green, onGift)
	gift.AnchorPoint = Vector2.new(0, 0.5)
	gift.ZIndex = 12 -- over the green's own parts
	HudParts.setMinHit(gift, Config.UI.Menu.Frame.TouchMinPx)
	local pad = Instance.new("UIPadding")
	local parts = HudParts.candyParts(green)
	if parts then
		pad.Parent = parts.label
	end
	return { green = green, gift = gift, pad = pad }
end

local function placeRobux(pair: RobuxPair, x: number, y: number, w: number, h: number, px: number)
	pair.green.Position = UDim2.fromOffset(x, y)
	pair.green.Size = UDim2.fromOffset(w, h)
	HudParts.setButtonTextSize(pair.green, px, L.MinTextPx)
	local face = h - round(h * K.ButtonLipShare)
	local inset = math.max(3, round(face * 0.12))
	local side = math.max(8, face - 2 * inset)
	pair.gift.Position = UDim2.fromOffset(inset + 1, round(face / 2))
	pair.gift.Size = UDim2.fromOffset(side, side)
	pair.pad.PaddingLeft = UDim.new(0, side + inset)
end

type Card = {
	index: number,
	cue: string,
	candy: number?, -- its Candy price (nil: the King's drop, no buttons)
	product: string?, -- its Config.Products key
	root: Frame,
	glow: ImageLabel?,
	fill: Frame,
	fillRound: UICorner,
	balls: ImageLabel,
	ballsRound: UICorner,
	edge: UIStroke,
	inner: Frame,
	innerRound: UICorner,
	innerStroke: UIStroke,
	art: Frame,
	thumb: Frame,
	fx: CardFx.Fx?, -- its cue's live effects (none: no CardFx row)
	ballsPhase: number, -- where its 8-balls' drift starts (0..1)
	landed: boolean, -- its reveal is over: its effects may play
	name: TextLabel,
	tag: Frame,
	tagRing: UIStroke,
	tagWord: TextLabel,
	robux: RobuxPair?,
	buy: TextButton?, -- the orange Candy button
	ribbon: Frame?,
	ribbonRound: UICorner?,
	ribbonRim: UIStroke?,
	pumpkin: ImageLabel?,
	crown: ImageLabel?,
	ribbonText: TextLabel?,
	owned: Frame,
	ownedIcon: ImageLabel,
	ownedText: TextLabel,
	isOwned: boolean,
	confirmUntil: number, -- os.clock: the Candy button says BUY? until then
	waitUntil: number, -- os.clock: a buy was sent; waiting for the answer until then
	land: () -> (), -- its idle loops (Stage onLand)
}

type Row = {
	frame: Frame,
	icon: ImageLabel,
	text: TextLabel,
	barBack: Frame,
	bar: Frame,
	count: TextLabel,
	chip: Frame,
	chipIcon: ImageLabel,
	chipText: TextLabel,
	claim: TextButton,
	key: string?,
}

type Pack = {
	key: string,
	tile: Frame,
	art: ImageLabel,
	amount: TextLabel,
	robux: RobuxPair,
}

--- Build the menu (closed) and register it with Menus.
function EventMenu.new(screen: ScreenGui, deps: any): Menus.Handle
	local _ = deps
	local frame = MenuFrame.new(screen, { name = NAME, title = W.Title, money = false })
	-- The header's jack-o'-lantern.
	local headerArt = if ART.Header ~= "" then ART.Header else H.CandyIcon
	if headerArt ~= "" and frame.icon then
		frame.icon.Image = headerArt
		frame.icon.Visible = true
	end
	local page = frame:page()
	local geo: MenuFrame.Geo? = nil
	local plan: HwMenuMath.Plan = HwMenuMath.plan(1, 1, true)
	local claiming: { [string]: boolean } = {}
	local idles: { UIAnim.Handle } = {}
	local busy: { [string]: boolean } = {}
	-- Studio checks: the last request this menu sent (GuiQA "hwMenuLast").
	local lastSent: { [string]: any }? = nil
	-- Studio checks: draw every cue as not owned (GuiQA "hwMenuUnowned"; the designer owns them).
	local previewUnowned = false

	local function send(msg: { [string]: any })
		lastSent = msg
		State.send(msg)
	end

	-- The header's pills: the Candy balance and the event's end (placed by layoutHeader).
	local candyPill = HudParts.pill(frame.header, "HwCandy", rgb(M.CandyPillTint))
	candyPill.ZIndex = 3
	local candyIcon = picture(candyPill, "Icon", H.CandyIcon)
	candyIcon.AnchorPoint = Vector2.new(0, 0.5)
	candyIcon.ZIndex = 4
	local candyText = HudParts.text(candyPill, "Count", 16, "0")
	candyText.AutoLocalize = false
	candyText.TextWrapped = false
	candyText.ZIndex = 4
	local endsPill = HudParts.pill(frame.header, "HwEnds", HudParts.tone("Purple"))
	endsPill.ZIndex = 3
	local endsText = HudParts.text(endsPill, "Time", 16, "")
	endsText.AutoLocalize = false
	endsText.TextWrapped = false
	endsText.Size = UDim2.fromScale(1, 1)
	endsText.ZIndex = 4

	-- The page's scroller (a phone scrolls past the cue row).
	local scroll = ShopParts.scroller(page, "Body")
	scroll.ZIndex = 2

	--------------------------------------------------------------------------------------------
	-- Buying
	--------------------------------------------------------------------------------------------

	local function products(): { [string]: any }
		local shop = ItemState.shop()
		return if type(shop) == "table" and type(shop.products) == "table"
			then shop.products
			else {}
	end

	-- Whether Robux product `key` is on sale (made on Roblox); if not, "Coming soon".
	local function productReady(key: string): boolean
		local product = products()[key]
		if type(product) ~= "table" or product.available ~= true then
			frame:notice(SHOP_COPY.ComingSoon, "Ink")
			return false
		end
		return true
	end

	local function buyProduct(key: string)
		if busy[key] or not productReady(key) then
			return
		end
		busy[key] = true
		lastSent = { store = "Buy", key = key }
		task.spawn(function()
			local reply = ItemState.request("StoreRequest", "Buy", key)
			busy[key] = false
			if not reply.ok then
				frame:notice(MenuFrame.reason(reply), "Red")
			end
		end)
	end

	-- The Gift Player popup (the Shop's), made on the first gift press; this menu is its host.
	local giftHost: any = { geo = nil }
	function giftHost.isBusy(_self: any, key: string): boolean
		return busy[key] == true
	end
	function giftHost.sendGift(_self: any, key: string, userId: number, _name: string)
		if busy.Gift then
			return
		end
		busy.Gift = true
		lastSent = { store = "Gift", key = key, userId = userId }
		task.spawn(function()
			local reply = ItemState.request("StoreRequest", "Gift", key, userId)
			busy.Gift = false
			if not reply.ok then
				frame:notice(MenuFrame.reason(reply), "Red")
			end
		end)
	end
	local giftPopup: any = nil
	local function openGift(key: string)
		if not productReady(key) then
			return
		end
		UISound.play("Click")
		if giftPopup == nil then
			giftPopup = ShopGift.new(giftHost, frame)
		end
		giftPopup:open(key)
	end

	--------------------------------------------------------------------------------------------
	-- The cue cards
	--------------------------------------------------------------------------------------------

	local cards: { Card } = {}
	local entries: { { cue: string, candy: number?, product: string? } } = {}
	for _, row in H.Cues.List do
		table.insert(entries, { cue = row.Cue, candy = row.Candy, product = row.Product })
	end
	-- The Pumpkin King's drop, unless its cue is already on sale (the Jack-o'-Lantern since
	-- 2026-10-29): one card a cue.
	local onSale = false
	for _, entry in entries do
		onSale = onSale or entry.cue == H.KingDrop.Cue
	end
	if H.KingDrop.Enabled and not onSale then
		table.insert(entries, { cue = H.KingDrop.Cue, candy = nil, product = nil })
	end
	local draw: () -> () = function() end

	local function pressCandy(card: Card)
		local price = card.candy
		if price == nil or card.isOwned then
			return
		end
		local now = os.clock()
		if card.waitUntil > now then
			return
		end
		local have = State.candy()
		if have < price then
			card.confirmUntil = 0
			frame:notice(W.NeedCandy:format(Format.commas(price - have)), "Red")
			draw()
			return
		end
		if card.confirmUntil > now then
			card.confirmUntil = 0
			card.waitUntil = now + M.WaitSeconds
			UISound.play("Claim")
			send({ buy = card.cue })
		else
			card.confirmUntil = now + M.ConfirmSeconds
			task.delay(M.ConfirmSeconds + 0.05, function()
				if frame:isOpen() then
					draw()
				end
			end)
		end
		draw()
	end

	for index, entry in entries do
		local root = HudParts.frame(scroll, "HwCard" .. index)
		root.ZIndex = 3
		local glow: ImageLabel? = nil
		if entry.cue == M.GlowCue then
			root.ZIndex = 2 -- under its neighbours, so its glow shows only in the gaps
			-- A halo past the card's edge (the Inventory's EdgeGlow: the soft glow 9-sliced).
			local g = picture(root, "Glow", K.Art.SoftGlow)
			g.ScaleType = Enum.ScaleType.Slice
			g.SliceCenter = Rect.new(127, 127, 129, 129)
			g.ImageColor3 = rgb(M.GlowTint)
			g.ImageTransparency = M.GlowLow
			g.ZIndex = 1
			glow = g
		end
		local fill = HudParts.frame(root, "Fill")
		fill.BackgroundTransparency = 0
		fill.BackgroundColor3 = Color3.new(1, 1, 1)
		fill.Size = UDim2.fromScale(1, 1)
		fill.ZIndex = 2
		local fillRound = HudParts.corner(fill, 12)
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Color = fillSequence()
		gradient.Parent = fill
		local edge = Instance.new("UIStroke")
		edge.Color = Color3.fromHex(LOOK.Edge)
		edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		edge.LineJoinMode = Enum.LineJoinMode.Round
		edge.Parent = fill
		local balls = picture(fill, "Balls", CC.Images.Balls)
		balls.ScaleType = Enum.ScaleType.Stretch
		balls.ImageColor3 = Color3.fromHex(LOOK.Balls)
		balls.ImageTransparency = CC.Motion.Balls.Transparency
		balls.Size = UDim2.fromScale(1, 1)
		balls.ZIndex = 2
		local ballsRound = HudParts.corner(balls, 12)
		local inner = HudParts.frame(root, "Inner")
		inner.ZIndex = 3
		local innerRound = HudParts.corner(inner, 10)
		local innerStroke = Instance.new("UIStroke")
		innerStroke.Color = Color3.new(1, 1, 1)
		innerStroke.Transparency = CC.Layout.InnerTransparency
		innerStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		innerStroke.Parent = inner
		local art = HudParts.frame(root, "Art")
		art.ZIndex = 4
		local thumb = CueThumb.new(art, entry.cue)
		thumb.AnchorPoint = Vector2.new(0.5, 0.5)
		thumb.Position = UDim2.fromScale(0.5, 0.5)
		-- Its own effects behind and over the picture (built hidden; the menu's loop plays them).
		local fx = CardFx.new(art, entry.cue, thumb)
		local name = HudParts.text(root, "Name", 18, CueThumb.cueName(entry.cue))
		name.TextWrapped = false
		name.ZIndex = 6
		local tag = HudParts.frame(root, "Tag")
		tag.BackgroundTransparency = 0
		tag.BackgroundColor3 = Color3.new(1, 1, 1)
		tag.ZIndex = 6
		HudParts.corner(tag, 999)
		local tagGradient = Instance.new("UIGradient")
		tagGradient.Rotation = 90
		tagGradient.Color =
			ColorSequence.new(Color3.fromHex(LOOK.Bar[1]), Color3.fromHex(LOOK.Bar[2]))
		tagGradient.Parent = tag
		local tagRing = Instance.new("UIStroke")
		tagRing.Color = HudParts.tone("Ink")
		tagRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		tagRing.Parent = tag
		local tagWord = HudParts.text(tag, "Word", 16, string.upper(CueThumb.rarityName("Unique")))
		tagWord.TextWrapped = false
		tagWord.Size = UDim2.fromScale(1, 1)
		tagWord.ZIndex = 7
		local owned = HudParts.pill(root, "Owned", HudParts.tone("Green"))
		owned.ZIndex = 7
		owned.Visible = false
		local ownedIcon = HudParts.icon(owned, "Check", "Icon")
		ownedIcon.AnchorPoint = Vector2.new(0, 0.5)
		ownedIcon.ZIndex = 8
		local ownedText = HudParts.text(owned, "Words", 18, W.Owned)
		ownedText.TextWrapped = false
		ownedText.ZIndex = 8
		local card: Card = {
			index = index,
			cue = entry.cue,
			candy = entry.candy,
			product = entry.product,
			root = root,
			glow = glow,
			fill = fill,
			fillRound = fillRound,
			balls = balls,
			ballsRound = ballsRound,
			edge = edge,
			inner = inner,
			innerRound = innerRound,
			innerStroke = innerStroke,
			art = art,
			thumb = thumb,
			fx = fx,
			ballsPhase = (index * 0.31) % 1,
			landed = false,
			name = name,
			tag = tag,
			tagRing = tagRing,
			tagWord = tagWord,
			robux = nil,
			buy = nil,
			ribbon = nil,
			ribbonRound = nil,
			ribbonRim = nil,
			pumpkin = nil,
			crown = nil,
			ribbonText = nil,
			owned = owned,
			ownedIcon = ownedIcon,
			ownedText = ownedText,
			isOwned = false,
			confirmUntil = 0,
			waitUntil = 0,
			land = function() end,
		}
		local product = entry.product
		if entry.candy ~= nil and product ~= nil then
			card.robux = robuxPair(root, function()
				buyProduct(product)
			end, function()
				openGift(product)
			end)
			local buy = HudParts.candy(root, "", function()
				UISound.play("Click")
				pressCandy(card)
			end, "Yellow", "Star")
			buy.Name = "Candy"
			buy.ZIndex = 4 -- under the Robux button where their touch areas meet
			makeOrange(buy)
			HudParts.setMinHit(buy, Config.UI.Menu.Frame.TouchMinPx)
			card.buy = buy
		else
			-- The Pumpkin King's drop: the ribbon with the crowned pumpkin.
			local ribbon = HudParts.frame(root, "Ribbon")
			ribbon.BackgroundTransparency = 0
			ribbon.BackgroundColor3 = Color3.new(1, 1, 1)
			ribbon.ZIndex = 7
			card.ribbonRound = HudParts.corner(ribbon, 12)
			local ribbonGradient = Instance.new("UIGradient")
			ribbonGradient.Rotation = 90
			ribbonGradient.Color = gradientOf(M.RibbonFill)
			ribbonGradient.Parent = ribbon
			local rim = Instance.new("UIStroke")
			rim.Color = rgb(M.RibbonRim)
			rim.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			rim.Parent = ribbon
			local pumpkin = picture(ribbon, "Pumpkin", headerArt)
			pumpkin.AnchorPoint = Vector2.new(0.5, 0.5)
			pumpkin.ZIndex = 8
			local crown = HudParts.icon(pumpkin, "Crown", "Crown")
			crown.AnchorPoint = Vector2.new(0.5, 1)
			crown.Position = UDim2.fromScale(0.5, 0.22)
			crown.Size = UDim2.fromScale(0.62, 0.42)
			crown.ZIndex = 9
			local words = HudParts.text(
				ribbon,
				"Words",
				18,
				W.KingRibbon:format(HwMenuMath.chanceWords(H.KingDrop.Chance)),
				rgb(M.RibbonText)
			)
			words.ZIndex = 8
			card.ribbon, card.ribbonRim, card.pumpkin, card.crown, card.ribbonText =
				ribbon, rim, pumpkin, crown, words
		end
		-- Its idle loops once it has landed (the frame stops them on close): the Robux button
		-- shines; the hero's glow pulses; the ribbon's pumpkin breathes. Calmer with Lower
		-- effects, still with Reduce Motion.
		card.land = function()
			card.landed = true -- its 8-balls and effects move from now (the menu's loop)
			local slower = if Quality.isLow() then M.LowerSlower else 1
			local pair = card.robux
			if pair then
				frame:idle(
					ShopCards.buttonShine(
						pair.green,
						M.ShineEvery,
						(card.index - 1) * M.ShineStaggerSeconds
					)
				)
			end
			if UIAnim.reduced() then
				return
			end
			local g = card.glow
			if g then
				frame:idle(UIAnim.glowPulse(g, M.GlowLow, M.GlowHigh, M.GlowSeconds * slower))
			end
			local p = card.pumpkin
			if p then
				local deep = if slower > 1 then (M.BreatheScale - 1) / 2 else M.BreatheScale - 1
				frame:idle(UIAnim.pulse(p, 1 + deep, M.BreatheSeconds * slower))
			end
		end
		table.insert(cards, card)
	end

	--------------------------------------------------------------------------------------------
	-- TODAY'S QUESTS
	--------------------------------------------------------------------------------------------

	local questBox, questRound = panel(scroll, "HwQuests", HudParts.tone("White"))
	questBox.ZIndex = 3
	local questTitle = HudParts.text(questBox, "Title", 22, W.QuestsTitle)
	questTitle.TextXAlignment = Enum.TextXAlignment.Left
	questTitle.TextWrapped = false
	questTitle.ZIndex = 4
	local questTimer = HudParts.note(questBox, "Timer", 14, "")
	questTimer.AutoLocalize = false
	questTimer.TextXAlignment = Enum.TextXAlignment.Right
	questTimer.TextWrapped = false
	questTimer.ZIndex = 4
	local rows: { Row } = {}
	for slot = 1, 4 do
		local f = panel(questBox, "Row" .. slot, rgb(M.RowTint))
		f.ZIndex = 4
		local icon = picture(f, "Icon", "")
		icon.ZIndex = 5
		local text = HudParts.note(f, "Text", 16, "")
		text.TextXAlignment = Enum.TextXAlignment.Left
		text.TextWrapped = false
		text.ZIndex = 5
		local back = HudParts.frame(f, "BarBack")
		back.BackgroundTransparency = 0
		back.BackgroundColor3 = rgb(M.BarBack)
		HudParts.corner(back, 999)
		back.ZIndex = 5
		local bar = HudParts.frame(back, "Bar")
		bar.BackgroundTransparency = 0
		bar.BackgroundColor3 = rgb(M.BarFill)
		HudParts.corner(bar, 999)
		bar.ZIndex = 6
		local count = HudParts.note(f, "Count", 14, "")
		count.AutoLocalize = false
		count.TextWrapped = false
		count.ZIndex = 5
		local chip = HudParts.pill(f, "Chip", rgb(M.CandyButton.Mid))
		chip.ZIndex = 5
		local chipIcon = picture(chip, "Icon", H.CandyIcon)
		chipIcon.ZIndex = 6
		local chipText = HudParts.text(chip, "Text", 16, "")
		chipText.AutoLocalize = false
		chipText.TextWrapped = false
		chipText.ZIndex = 6
		local row: Row = {
			frame = f,
			icon = icon,
			text = text,
			barBack = back,
			bar = bar,
			count = count,
			chip = chip,
			chipIcon = chipIcon,
			chipText = chipText,
			claim = nil :: any,
			key = nil,
		}
		row.claim = HudParts.candy(f, W.Claim, function()
			local key = row.key
			if key == nil or claiming[key] then
				return
			end
			claiming[key] = true
			UISound.play("Claim")
			UIAnim.glowBurst(row.chip, HudParts.tone("Gold"), 0.5)
			-- The claimed Candy flies out of this button (CandyToast).
			EventMenu.lastClaim = {
				at = os.clock(),
				from = row.claim.AbsolutePosition + row.claim.AbsoluteSize / 2,
			}
			send({ claim = key })
			task.delay(3, function()
				claiming[key] = nil
			end)
			draw()
			-- A controller's selection moves on from the CLAIM that just hid: to the next waiting
			-- CLAIM, else the X, so nothing hidden stays selected.
			if GuiService.SelectedObject == row.claim and not row.claim.Visible then
				local nextClaim: GuiObject? = nil
				for _, other in rows do
					if other.claim.Visible and other.claim.Parent ~= nil then
						nextClaim = other.claim
						break
					end
				end
				if nextClaim then
					GuiService.SelectedObject = nextClaim
				else
					frame:focus()
				end
			end
		end, "Green", nil)
		row.claim.Name = "Claim"
		row.claim.ZIndex = 6
		row.claim.Visible = false
		table.insert(rows, row)
	end
	local questsSoon = HudParts.note(questBox, "Soon", 16, W.QuestsSoon)
	questsSoon.ZIndex = 5
	questsSoon.Visible = false

	--------------------------------------------------------------------------------------------
	-- GET CANDY
	--------------------------------------------------------------------------------------------

	local packBox, packRound = panel(scroll, "HwPacks", HudParts.tone("White"))
	packBox.ZIndex = 3
	local packTitle = HudParts.text(packBox, "Title", 22, W.GetCandy)
	packTitle.TextXAlignment = Enum.TextXAlignment.Left
	packTitle.TextWrapped = false
	packTitle.ZIndex = 4
	local packs: { Pack } = {}
	for i, key in H.Packs.Keys do
		local tile = panel(packBox, "Pack" .. i, rgb(M.TileTint))
		tile.ZIndex = 4
		local art = picture(tile, "Art", if ART.CandyPile ~= "" then ART.CandyPile else H.CandyIcon)
		art.AnchorPoint = Vector2.new(0.5, 0.5)
		art.ZIndex = 5
		local amount = HudParts.text(
			tile,
			"Amount",
			20,
			Format.commas(HwMenuMath.packCandy(key)),
			rgb(M.AmountTint)
		)
		amount.AutoLocalize = false
		amount.TextWrapped = false
		amount.ZIndex = 6
		local pair = robuxPair(tile, function()
			send({ pack = key }) -- the HwMenu PackPrompt step (CandyService logs it)
			buyProduct(key)
		end, function()
			openGift(key)
		end)
		pair.green.ZIndex = 6
		table.insert(packs, { key = key, tile = tile, art = art, amount = amount, robux = pair })
	end

	--------------------------------------------------------------------------------------------
	-- Stage (literal ids only: tests/halloween_menu_stage_test)
	--------------------------------------------------------------------------------------------

	local stage = frame.stage
	if stage then
		stage:add("HwCandy", candyPill)
		stage:add("HwEnds", endsPill)
		if cards[1] then
			stage:add("HwCard1", cards[1].root, cards[1].land)
		end
		if cards[2] then
			stage:add("HwCard2", cards[2].root, cards[2].land)
		end
		if cards[3] then
			stage:add("HwCard3", cards[3].root, cards[3].land)
		end
		if cards[4] then
			stage:add("HwCard4", cards[4].root, cards[4].land)
		end
		stage:add("HwQuests", questBox)
		stage:add("HwPacks", packBox, function()
			for i, pack in packs do
				frame:idle(
					ShopCards.buttonShine(
						pack.robux.green,
						M.ShineEvery,
						(#cards + i - 1) * M.ShineStaggerSeconds
					)
				)
			end
		end)
	end

	--------------------------------------------------------------------------------------------
	-- Layout
	--------------------------------------------------------------------------------------------

	-- A phone-sized screen, as MenuFrame decides it (the room under Roblox's top bar).
	local function isPhone(): boolean
		local size: Vector2 = frame.root.AbsoluteSize
		local _, _, barBottom = frame:topbar(size)
		return size.Y - barBottom < SHORT_SCREEN
	end

	-- The header's pills right to left from the X, the title shrunk to the room left.
	local function layoutHeader()
		local g = geo
		if g == nil then
			return
		end
		local hw, hh = frame.header.Size.X.Offset, frame.header.Size.Y.Offset
		local closeW = frame.closeButton.Size.X.Offset
		local gap = g.gap
		local ph = math.min(hh, math.max(L.MinTextPx + 8, round(hh * M.PillOfHeader)))
		local tp = math.max(L.MinTextPx, round(ph * M.PillTextShare))
		local y = round((hh - ph) / 2)
		local right = hw - closeW - gap
		HudParts.setTextSize(endsText, tp, L.MinTextPx)
		local endsW = math.ceil(textWidth(endsText.Text, tp)) + 2 * M.PillPadPx
		endsPill.Position = UDim2.fromOffset(right - endsW, y)
		endsPill.Size = UDim2.fromOffset(endsW, ph)
		right -= endsW + gap
		local iconPx = round(ph * M.PillIconShare)
		local over = round(iconPx * 0.3) -- the candy pokes out past the pill's left end
		HudParts.setTextSize(candyText, tp, L.MinTextPx)
		local countW = math.ceil(textWidth(candyText.Text, tp))
		local candyW = iconPx - over + 4 + countW + M.PillPadPx
		candyPill.Position = UDim2.fromOffset(right - candyW, y)
		candyPill.Size = UDim2.fromOffset(candyW, ph)
		candyIcon.Position = UDim2.new(0, -over, 0.5, 0)
		candyIcon.Size = UDim2.fromOffset(iconPx, iconPx)
		candyText.Position = UDim2.fromOffset(iconPx - over + 4, 0)
		candyText.Size = UDim2.fromOffset(countW + 2, ph)
		right -= candyW + over + gap
		-- The title gives up room first (its words shrink to fit, never under the kit minimum).
		local title: TextLabel = frame.title
		local titleX = title.Position.X.Offset
		local natural = math.ceil(textWidth(W.Title, g.title)) + 8
		title.Size = UDim2.fromOffset(math.max(1, math.min(natural, right - titleX)), hh)
	end

	local function layoutCard(card: Card, x: number, w: number)
		local C = HwMenuMath.card(plan.short)
		local k = plan.k
		local function y(units: number): number
			return round(units * k)
		end
		local function tp(units: number): number
			return HwMenuMath.textPx(units, k)
		end
		local h = y(C.HeightUnits)
		card.root.Position = UDim2.fromOffset(x, 0)
		card.root.Size = UDim2.fromOffset(w, h)
		local cornerPx = y(L.CornerUnits)
		local edgePx = math.max(2, y(L.EdgeUnits))
		local innerPx = math.max(1, y(L.InnerUnits))
		-- The pink edge is drawn outward from the fill, so the fill is inset by its thickness:
		-- the edge lies inside the card's box and the scroller's edges never cut it (the
		-- designer's screenshot, 2026-10-29: the first card's left and the row's top were cut).
		card.fill.Position = UDim2.fromOffset(edgePx, edgePx)
		card.fill.Size = UDim2.new(1, -2 * edgePx, 1, -2 * edgePx)
		card.fillRound.CornerRadius = UDim.new(0, math.max(0, cornerPx - edgePx))
		card.ballsRound.CornerRadius = UDim.new(0, math.max(0, cornerPx - edgePx))
		card.edge.Thickness = edgePx
		local innerAt = edgePx + innerPx + 1
		card.inner.Position = UDim2.fromOffset(innerAt, innerAt)
		card.inner.Size = UDim2.new(1, -2 * innerAt, 1, -2 * innerAt)
		card.innerRound.CornerRadius = UDim.new(0, math.max(0, cornerPx - innerAt))
		card.innerStroke.Thickness = innerPx
		local glow = card.glow
		if glow then
			local reach = math.max(4, y(L.GlowUnits))
			glow.Position = UDim2.fromOffset(-reach, -reach)
			glow.Size = UDim2.new(1, 2 * reach, 1, 2 * reach)
			glow.SliceScale = 2 * reach / 128
		end
		-- The 8-balls: a window of the tile sheet, one period TileWidths card widths across (the
		-- Cues inventory's; the menu's loop drifts it up-left).
		local sx, sy, offset =
			CardMath.ballsWindow(0, w - 2 * edgePx, h - 2 * edgePx, card.ballsPhase)
		card.balls.ImageRectSize = Vector2.new(sx, sy)
		card.balls.ImageRectOffset = Vector2.new(offset, offset)
		-- The picture, the name over its foot, the UNIQUE pill.
		local pad = round(L.CardPadUnits * plan.kx)
		local artH = y(C.ArtUnits)
		card.art.Position = UDim2.fromOffset(pad, y(C.ArtTopUnits))
		card.art.Size = UDim2.fromOffset(w - 2 * pad, artH)
		local side = math.min(w - 2 * pad, artH)
		card.thumb.Size = UDim2.fromOffset(side, side)
		local fx = card.fx
		if fx then
			CardFx.layout(fx, side)
		end
		local namePx = tp(C.NameTextUnits)
		local nameW = w - 2 * pad
		local full = CueThumb.cueName(card.cue)
		local words = if textWidth(full, namePx) <= nameW then full else CUE_SHORT[card.cue] or full
		card.name.Text = words
		card.name.Position = UDim2.fromOffset(pad, y(C.NameTopUnits))
		card.name.Size = UDim2.fromOffset(nameW, y(C.NameUnits))
		HudParts.setTextSize(card.name, namePx, L.MinTextPx)
		local tagH = math.max(L.MinTextPx + 4, y(C.TagUnits))
		card.tag.Position = UDim2.fromOffset(pad + 2, y(C.TagTopUnits))
		card.tag.Size = UDim2.fromOffset(w - 2 * pad - 4, tagH)
		card.tagRing.Thickness = math.max(1, y(2))
		HudParts.setTextSize(card.tagWord, math.min(tagH - 2, tp(C.TagTextUnits)), L.MinTextPx)
		-- The buttons (or the ribbon), and OWNED in their place.
		local bw = w - 2 * pad
		local pair = card.robux
		if pair then
			placeRobux(pair, pad, y(C.RobuxTopUnits), bw, y(C.RobuxUnits), tp(C.RobuxTextUnits))
		end
		local buy = card.buy
		if buy then
			buy.Position = UDim2.fromOffset(pad + 2, y(C.CandyTopUnits))
			buy.Size = UDim2.fromOffset(bw - 4, y(C.CandyUnits))
			HudParts.setButtonTextSize(buy, tp(C.CandyTextUnits), L.MinTextPx)
		end
		local ribbon = card.ribbon
		if ribbon then
			local rh = y(C.RibbonUnits)
			ribbon.Position = UDim2.fromOffset(pad, y(C.RibbonTopUnits))
			ribbon.Size = UDim2.fromOffset(bw, rh)
			local ribbonRound = card.ribbonRound
			if ribbonRound then
				ribbonRound.CornerRadius = UDim.new(0, math.max(4, round(rh * 0.2)))
			end
			local rim = card.ribbonRim
			if rim then
				rim.Thickness = math.max(2, y(4))
			end
			local pumpkinPx = math.min(round(rh * 0.78), round(bw * 0.38))
			local pumpkin = card.pumpkin
			if pumpkin then
				pumpkin.Position = UDim2.fromOffset(round(pumpkinPx * 0.55) + 2, round(rh * 0.56))
				pumpkin.Size = UDim2.fromOffset(pumpkinPx, pumpkinPx)
			end
			local text = card.ribbonText
			if text then
				local left = round(pumpkinPx * 1.1) + 4
				text.Position = UDim2.fromOffset(left, 2)
				text.Size = UDim2.fromOffset(math.max(1, bw - left - 4), rh - 4)
				HudParts.setTextSize(text, tp(C.RibbonTextUnits), L.MinTextPx)
			end
		end
		-- OWNED in the middle of where the buttons (or the ribbon) were.
		local oh = y(C.RobuxUnits)
		local areaTop = if ribbon then C.RibbonTopUnits else C.RobuxTopUnits
		local areaBottom = if ribbon
			then C.RibbonTopUnits + C.RibbonUnits
			else C.CandyTopUnits + C.CandyUnits
		local oy = round((areaTop + areaBottom) / 2 * k - oh / 2)
		card.owned.Position = UDim2.fromOffset(pad, oy)
		card.owned.Size = UDim2.fromOffset(bw, oh)
		local ownedPx = tp(C.RobuxTextUnits)
		local iconPx = round(oh * 0.62)
		local ownedW = math.ceil(textWidth(W.Owned, ownedPx))
		local startX = math.max(4, round((bw - iconPx - 6 - ownedW) / 2))
		card.ownedIcon.Position = UDim2.new(0, startX, 0.5, 0)
		card.ownedIcon.Size = UDim2.fromOffset(iconPx, iconPx)
		card.ownedText.Position = UDim2.fromOffset(startX + iconPx + 6, 0)
		card.ownedText.Size = UDim2.fromOffset(math.max(1, bw - startX - iconPx - 10), oh)
		HudParts.setTextSize(card.ownedText, ownedPx, L.MinTextPx)
	end

	local function layout()
		local g = geo
		if g == nil then
			return
		end
		local barPx = scroll.ScrollBarThickness
		local width = g.content.X - barPx
		plan = HwMenuMath.plan(width, g.content.Y, g.phone == true)
		local k, kx = plan.k, plan.kx
		local function X(units: number): number
			return plan.x0 + round(units * kx)
		end
		local function y(units: number): number
			return round(units * k)
		end
		local function tp(units: number): number
			return HwMenuMath.textPx(units, k)
		end
		scroll.Size = UDim2.fromOffset(g.content.X, g.content.Y)
		layoutHeader()
		-- The cue row: four cards across the whole width.
		local cardW = (L.WidthUnits - 3 * L.CardGapUnits) / 4
		for i, card in cards do
			local left = X((i - 1) * (cardW + L.CardGapUnits))
			local right = X((i - 1) * (cardW + L.CardGapUnits) + cardW)
			layoutCard(card, left, right - left)
		end
		local top = y(HwMenuMath.rowUnits(plan.short) + L.SectionGapUnits)
		local boxH = y(HwMenuMath.boxUnits())
		local cornerPx = y(L.CornerUnits)
		local boxPad = round(L.BoxPadUnits * kx)
		local titleH = y(L.BoxTitleUnits)
		-- TODAY'S QUESTS.
		local qx, qw = X(0), X(L.QuestsWidthUnits) - X(0)
		questBox.Position = UDim2.fromOffset(qx, top)
		questBox.Size = UDim2.fromOffset(qw, boxH)
		questRound.CornerRadius = UDim.new(0, cornerPx)
		local titlePx = tp(L.BoxTitleTextUnits)
		local timerPx = tp(L.TimerTextUnits)
		local timerW = math.ceil(textWidth(W.NewQuestsIn:format("00:00:00"), timerPx)) + 4
		questTitle.Position = UDim2.fromOffset(boxPad, 0)
		questTitle.Size = UDim2.fromOffset(math.max(1, qw - 3 * boxPad - timerW), titleH)
		HudParts.setTextSize(questTitle, titlePx, L.MinTextPx)
		questTimer.Position = UDim2.fromOffset(qw - boxPad - timerW, 0)
		questTimer.Size = UDim2.fromOffset(timerW, titleH)
		HudParts.setTextSize(questTimer, timerPx, L.MinTextPx)
		local rowH = y(L.RowUnits)
		local rowGap = y(L.RowGapUnits)
		local rw = qw - 2 * boxPad
		local chipW = round(L.ChipWidthUnits * kx)
		local chipH = y(L.ChipUnits)
		local rowTextPx = tp(L.RowTextUnits)
		local countPx = tp(L.RowCountTextUnits)
		local countW = math.ceil(textWidth("100/100", countPx)) + 4
		local iconPx = y(L.RowIconUnits)
		for slot, row in rows do
			row.frame.Position = UDim2.fromOffset(boxPad, titleH + (slot - 1) * (rowH + rowGap))
			row.frame.Size = UDim2.fromOffset(rw, rowH)
			row.icon.Size = UDim2.fromOffset(iconPx, iconPx)
			row.icon.Position =
				UDim2.fromOffset(round((rowH - iconPx) / 2), round((rowH - iconPx) / 2))
			local left = rowH + 2
			local chipX = rw - chipW - round(8 * kx)
			local barRight = chipX - countW - round(10 * kx)
			row.text.Position = UDim2.fromOffset(left, 0)
			row.text.Size = UDim2.fromOffset(math.max(1, chipX - left - 6), round(rowH * 0.56))
			HudParts.setTextSize(row.text, rowTextPx, L.MinTextPx)
			local barH = math.max(4, y(L.RowBarUnits))
			row.barBack.Position = UDim2.fromOffset(left, round(rowH * 0.62))
			row.barBack.Size = UDim2.fromOffset(math.max(1, barRight - left), barH)
			row.count.Position =
				UDim2.fromOffset(barRight + 4, round(rowH * 0.62 + barH / 2 - countPx * 0.7))
			row.count.Size = UDim2.fromOffset(countW, round(countPx * 1.4))
			HudParts.setTextSize(row.count, countPx, L.MinTextPx)
			row.chip.Position = UDim2.fromOffset(chipX, round((rowH - chipH) / 2))
			row.chip.Size = UDim2.fromOffset(chipW, chipH)
			local chipIconPx = round(chipH * 0.8)
			row.chipIcon.Size = UDim2.fromOffset(chipIconPx, chipIconPx)
			row.chipIcon.Position =
				UDim2.fromOffset(round(chipH * 0.25), round((chipH - chipIconPx) / 2))
			HudParts.setTextSize(row.chipText, tp(L.ChipTextUnits), L.MinTextPx)
			local claimH = math.min(rowH - 2, round(chipH * 1.1))
			row.claim.Position = UDim2.fromOffset(chipX, round((rowH - claimH) / 2))
			row.claim.Size = UDim2.fromOffset(chipW, claimH)
			HudParts.setButtonTextSize(row.claim, tp(L.ChipTextUnits), L.MinTextPx)
		end
		questsSoon.Position = UDim2.fromOffset(boxPad, titleH)
		questsSoon.Size = UDim2.fromOffset(rw, rowH)
		HudParts.setTextSize(questsSoon, rowTextPx, L.MinTextPx)
		-- GET CANDY.
		local px0 = X(L.QuestsWidthUnits + L.BoxGapUnits)
		local pw = X(L.WidthUnits) - px0
		packBox.Position = UDim2.fromOffset(px0, top)
		packBox.Size = UDim2.fromOffset(pw, boxH)
		packRound.CornerRadius = UDim.new(0, cornerPx)
		packTitle.Position = UDim2.fromOffset(boxPad, 0)
		packTitle.Size = UDim2.fromOffset(math.max(1, pw - 2 * boxPad), titleH)
		HudParts.setTextSize(packTitle, titlePx, L.MinTextPx)
		local tileGap = round(L.TileGapUnits * kx)
		local tileW = math.floor((pw - 2 * boxPad - tileGap) / 2)
		local tileH = boxH - titleH - boxPad
		for i, pack in packs do
			pack.tile.Position = UDim2.fromOffset(boxPad + (i - 1) * (tileW + tileGap), titleH)
			pack.tile.Size = UDim2.fromOffset(tileW, tileH)
			local artBox = y(L.TileArtUnits)
			local share = M.PackArtShare[i] or 1
			local artPx = round(math.min(artBox, tileW - 8) * share)
			pack.art.Position = UDim2.fromOffset(round(tileW / 2), 4 + round(artBox / 2))
			pack.art.Size = UDim2.fromOffset(artPx, artPx)
			local amountH = y(L.TileAmountUnits)
			pack.amount.Position = UDim2.fromOffset(4, 4 + artBox)
			pack.amount.Size = UDim2.fromOffset(tileW - 8, amountH)
			HudParts.setTextSize(pack.amount, tp(L.TileAmountTextUnits), L.MinTextPx)
			local bh = y(L.TileButtonUnits)
			local inset = round(10 * kx)
			placeRobux(
				pack.robux,
				inset,
				tileH - bh - inset,
				tileW - 2 * inset,
				bh,
				tp(L.TileButtonTextUnits)
			)
		end
		scroll.CanvasSize = UDim2.fromOffset(0, top + boxH + (if plan.whole then 0 else 4))
		giftHost.geo = g
		if giftPopup and giftPopup:isOpen() then
			giftPopup:layout(g)
		end
	end

	--------------------------------------------------------------------------------------------
	-- Drawing
	--------------------------------------------------------------------------------------------

	local function ownedCue(view: any, list: { [string]: any }, card: Card): boolean
		if previewUnowned then
			return false
		end
		if
			type(view) == "table"
			and type(view.owned) == "table"
			and view.owned[card.cue] == true
		then
			return true
		end
		local key = card.product
		local product = if key then list[key] else nil
		if type(product) == "table" and product.owned == true then
			return true
		end
		return ItemState.cueCount(card.cue) > 0
	end

	local function paintCard(card: Card, view: any, list: { [string]: any }, cuesOn: boolean)
		local owned = ownedCue(view, list, card)
		card.isOwned = owned
		card.owned.Visible = owned
		local ribbon = card.ribbon
		if ribbon then
			ribbon.Visible = not owned
		end
		local pair, buy = card.robux, card.buy
		local key, price = card.product, card.candy
		if pair == nil or buy == nil or key == nil or price == nil then
			return
		end
		local shown = cuesOn and not owned
		pair.green.Visible = shown
		buy.Visible = shown
		if not shown then
			return
		end
		ShopCards.setButtonWords(pair.green, ShopCards.robuxText(ShopParts.robuxOf(list[key], key)))
		local now = os.clock()
		local waiting = card.waitUntil > now
		HudParts.setText(
			buy,
			if card.confirmUntil > now and not waiting then W.BuyConfirm else Format.commas(price)
		)
		HudParts.setEnabled(buy, not waiting, waiting)
	end

	local function paintQuests(view: any, now: number)
		local today = HwMenuMath.today(view, now)
		local at, final = HwMenuMath.nextQuestsAt(today)
		questTimer.Text = (if final then W.QuestsEndIn else W.NewQuestsIn):format(
			Event.clock(at - now)
		)
		local on = type(view) == "table" and type(view.on) == "table" and view.on.quests == true
		local board = if on and type(view.boards) == "table" then view.boards[today] else nil
		local quests = if type(board) == "table" and type(board.quests) == "table"
			then board.quests
			else {}
		questsSoon.Visible = #quests == 0
		for slot, row in rows do
			local q = quests[slot]
			row.frame.Visible = q ~= nil
			row.key = if q then q.key else nil
			if q then
				row.icon.Image = if q.icon == "Candy"
					then H.CandyIcon
					else imageOf(QICONS[q.icon] or "Star")
				row.text.Text = HwMenuMath.questText(q.kind, q.need)
				local have = math.min(q.have, q.need)
				row.bar.Size = UDim2.fromScale(if q.need > 0 then have / q.need else 0, 1)
				row.count.Text = HwMenuMath.questCount(q.kind, q.have, q.need)
				local claimable = have >= q.need and not q.claimed and not claiming[q.key]
				row.claim.Visible = claimable
				row.chip.Visible = not claimable
				row.chipText.Text = if q.claimed then W.Claimed else W.Reward:format(q.reward)
				-- CLAIMED takes the whole chip.
				row.chipIcon.Visible = not q.claimed
				row.chipText.Size = UDim2.fromScale(if q.claimed then 0.92 else 0.62, 1)
				row.chipText.Position = UDim2.fromScale(if q.claimed then 0.04 else 0.34, 0)
				row.chip.BackgroundColor3 = if q.claimed
					then HudParts.tone("Green")
					else rgb(M.CandyButton.Mid)
			end
		end
	end

	local function paintPacks(view: any, list: { [string]: any })
		local on = not (
			type(view) == "table"
			and type(view.on) == "table"
			and view.on.packs == false
		)
		packBox.Visible = on and H.Packs.Enabled == true
		for _, pack in packs do
			ShopCards.setButtonWords(
				pack.robux.green,
				ShopCards.robuxText(ShopParts.robuxOf(list[pack.key], pack.key))
			)
		end
	end

	draw = function()
		local view = State.view()
		local now = Clock.now()
		local candyWords = Format.commas(State.candy())
		local endsWords = W.EndsIn:format(Event.short(Event.endsIn(now)))
		if candyText.Text ~= candyWords or endsText.Text ~= endsWords then
			candyText.Text = candyWords
			endsText.Text = endsWords
			layoutHeader()
		end
		local list = products()
		local cuesOn = H.Cues.Enabled == true
			and not (type(view) == "table" and type(view.on) == "table" and view.on.cues == false)
		for _, card in cards do
			paintCard(card, view, list, cuesOn)
		end
		paintQuests(view, now)
		paintPacks(view, list)
	end
	EventMenu.redraw = draw

	-- A Candy buy's answer (contract section 3): { cue, ok, reason? }.
	local function bought(answer: any)
		local cue = answer.cue
		for _, card in cards do
			if card.cue == cue then
				card.waitUntil = 0
				card.confirmUntil = 0
			end
		end
		if answer.ok == true then
			frame:notice(W.BoughtCue:format(CueThumb.cueName(tostring(cue))), "Green")
		else
			local reason = if type(answer.reason) == "string" then answer.reason else ""
			frame:notice(FAILED[reason] or FAILED.Default, "Red")
		end
		if frame:isOpen() then
			draw()
		end
	end
	State.Moment:Connect(function(msg: any)
		if type(msg) == "table" and type(msg.bought) == "table" then
			bought(msg.bought)
		end
	end)

	-- The Candy pill's middle while the menu is open (where a claim's Candy lands), and its bump.
	EventMenu.candyTarget = function(): Vector2?
		if not frame:isOpen() or not candyPill.Visible then
			return nil
		end
		return candyPill.AbsolutePosition + candyPill.AbsoluteSize / 2
	end
	EventMenu.bumpCandy = function()
		UIAnim.bounce(candyPill)
	end

	frame.onLayout = function(g: MenuFrame.Geo)
		geo = g
		layout()
		draw()
	end
	-- A phone: the cue row whole with the quests' header peeking; a computer: all of it.
	frame.fitHeight = function(width: number): number
		return HwMenuMath.fitHeight(width - scroll.ScrollBarThickness, isPhone())
	end
	-- The 1 s redraw loop: each open starts one and bumps the generation, so a loop left from a
	-- close and quick reopen stops on its next wake (never two loops).
	local tickGen = 0
	frame.onOpen = function()
		send({ seen = true })
		scroll.CanvasPosition = Vector2.zero
		layout()
		draw()
		tickGen += 1
		local gen = tickGen
		task.spawn(function()
			local warned = false -- a failing redraw warns once; the loop goes on
			while gen == tickGen do
				local ok, err = pcall(function(): any
					draw()
					return nil
				end)
				if not ok and not warned then
					warned = true
					warn("[8ball] Halloween menu: " .. tostring(err))
				end
				task.wait(1)
			end
		end)
		-- Waiting CLAIMs bounce (not with Reduce Motion).
		for _, row in rows do
			table.insert(
				idles,
				UIAnim.loop(row.claim, function(clock: number)
					if
						row.claim.Visible
						and not UIAnim.reduced()
						and clock % M.ClaimBounceSeconds < 0.05
					then
						UIAnim.bounce(row.claim)
					end
				end)
			)
		end
		-- The cards' 8-balls drift up-left (the Cues inventory's) and their effects play: one loop
		-- for all four, only while the menu is open (stopped on close), a card once it has landed
		-- and while it is on screen. Lower effects: at most LowFps steps a second.
		local lastStep = -math.huge
		table.insert(
			idles,
			UIAnim.loop(scroll, function(clock: number)
				local low = Quality.isLow()
				if low and clock - lastStep < 1 / CARD_FX.LowFps then
					return
				end
				lastStep = clock
				local reduced = UIAnim.reduced()
				local top = scroll.AbsolutePosition.Y
				local bottom = top + scroll.AbsoluteSize.Y
				for _, card in cards do
					local at = card.root.AbsolutePosition.Y
					local seen = card.landed and at < bottom and at + card.root.AbsoluteSize.Y > top
					if seen then
						local size = card.fill.AbsoluteSize
						local sx, sy, offset = CardMath.ballsWindow(
							if reduced then 0 else clock,
							size.X,
							size.Y,
							card.ballsPhase
						)
						card.balls.ImageRectSize = Vector2.new(sx, sy)
						card.balls.ImageRectOffset = Vector2.new(offset, offset)
					end
					local fx = card.fx
					if fx then
						if seen then
							CardFx.step(fx, clock, low, reduced)
						else
							CardFx.hide(fx)
						end
					end
				end
			end)
		)
		-- A controller lands on the first waiting CLAIM once the panel has unrolled (the content
		-- is hidden until then, so nothing in it can be selected before).
		task.delay(Config.UI.Halloween.Open.OpenSeconds, function()
			if not frame:isOpen() or not PadMode.active() then
				return
			end
			for _, row in rows do
				if row.claim.Visible and row.claim.Parent ~= nil then
					GuiService.SelectedObject = row.claim
					return
				end
			end
		end)
	end
	frame.onClose = function()
		tickGen += 1
		for _, handle in idles do
			handle.stop()
		end
		table.clear(idles)
		for _, card in cards do
			card.confirmUntil = 0
			card.landed = false -- its effects wait for its next landing
			local fx = card.fx
			if fx then
				CardFx.hide(fx)
			end
		end
		if giftPopup then
			giftPopup:close()
		end
	end
	State.Changed:Connect(function()
		if frame:isOpen() then
			draw()
		end
	end)
	ItemState.Changed.Shop:Connect(function()
		if frame:isOpen() then
			draw()
		end
	end)

	-- Studio only: GuiQA:Invoke("hwMenuLast") gives the last request this menu sent;
	-- GuiQA:Invoke("hwBought", cue, ok, reason?) plays a Candy buy's answer.
	GuiQA.add("hwMenuLast", function(): any
		return lastSent
	end)
	GuiQA.add("hwMenuUnowned", function(on: boolean?): boolean
		previewUnowned = on ~= false
		draw()
		return previewUnowned
	end)
	GuiQA.add("hwBought", function(cue: string, ok: boolean?, reason: string?): boolean
		bought({ cue = cue, ok = ok == true, reason = reason })
		return true
	end)

	local handle: Menus.Handle = {
		open = function()
			frame:open()
		end,
		close = function()
			frame:close()
		end,
		isOpen = function(): boolean
			return frame:isOpen()
		end,
		root = frame.root,
	}
	Menus.register(NAME, handle)
	return handle
end

-- Redraws the open menu (set by new).
function EventMenu.redraw() end

-- Set by new: the Candy pill's middle while the menu is open (nil otherwise), and its bounce.
function EventMenu.candyTarget(): Vector2?
	return nil
end
function EventMenu.bumpCandy() end

-- The last CLAIM press: when (os.clock) and where (its middle, absolute pixels).
EventMenu.lastClaim = nil :: { at: number, from: Vector2 }?

return EventMenu
