--!strict
-- FreeHeroes: the Free Reward menu's first-visit heroes (designer, 2026-10-08: "i really want
-- to emphasize more of joining the group and favoriting first ... each favorite and group join
-- like its separate frame/hero, and then invite below the 2"; their reference: a big block
-- over its glow, a gold title, what it gives and a big green button). Two wide cards side by
-- side at the top of the page until both are claimed (FreeSocial's welcome; after that the
-- Group section is the small Lucky 8 card at the bottom of the page): join the group (its
-- blocks and the match money while a member) and favorite the game (the Lucky 8 Block and
-- money). Each picture shows its reward's best block (as many as it gives, up to three) with
-- the group's busts or the favorite star, and the money when it gives some; the sky-blue dice
-- on the picture opens that block's Odds & Details. Beside it the title, the reward's blocks
-- and a line (the money, the match money while a member); under them the button: Join (Claim!
-- for a member) or Favorite, then Claimed. Both cards are as tall as the taller needs (a
-- phone's 12 px words make them taller), laid out as the Shop's Starter Pack and VIP
-- (ShopOffers). Sizes in Config.UI.FreeReward.Social.Heroes, words in Strings.FreeReward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopParts = require(script.Parent.ShopParts)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local H = Config.UI.FreeReward.Social.Heroes
local K = Config.UI.Kit
local MIN_TEXT = Config.UI.GrandOpeningCard.Layout.MinTextPx
local TOUCH = Config.UI.Menu.Frame.TouchMinPx
local ICONS: { [string]: string } = K.Icons :: any
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round

export type Actions = {
	join: (button: GuiObject) -> (), -- FreeSocial.join: Roblox's join prompt, then the claim
	favorite: (button: GuiObject) -> (), -- FreeSocial.favorite: the favorite prompt, the claim
	odds: (kind: string) -> (), -- a block's Odds & Details (the menu's OddsDetails)
}

type Hero = {
	key: string, -- "Group" or "Favorite"
	frame: Frame,
	corner: UICorner,
	edge: UIStroke,
	art: ShopCards.Art, -- its picture: the block in front
	copies: { ImageLabel }, -- the copies behind it
	badge: ImageLabel, -- the group's busts or the star
	cash: ImageLabel,
	odds: ShopCards.Badge,
	title: TextLabel,
	reward: TextLabel,
	line: TextLabel,
	button: TextButton,
	kind: string, -- the block its picture and dice show
	count: number, -- how many of it the picture shows
	look: string?, -- the button's look now
}

-- Where a card's pieces go at one size (pixels), worked out before the pair's height is known.
type Plan = {
	pad: number,
	art: number,
	colX: number,
	colW: number,
	rowGap: number,
	gap: number,
	titlePx: number,
	titleH: number,
	rewardPx: number,
	rewardH: number,
	linePx: number,
	lineH: number,
	textH: number,
	topH: number,
	buttonH: number,
	buttonTextPx: number,
	need: number,
}

local FreeHeroes = {}
FreeHeroes.__index = FreeHeroes

-- Left-aligned kit words (white, or `tint`, the ink outline), wrapping, from their top left.
local function words(parent: Instance, name: string, tint: Color3?): TextLabel
	local label = ShopCards.label(parent, name, "", tint, 6)
	label.AnchorPoint = Vector2.new(0, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	return label
end

-- Give `object` its place in a picture by Config shares: centre x, centre y, size.
local function share(object: GuiObject, at: { number })
	object.AnchorPoint = Vector2.new(0.5, 0.5)
	object.Position = UDim2.fromScale(at[1], at[2])
	object.Size = UDim2.fromScale(at[3], at[3])
end

-- One card: its picture (the reward's block, its copies, the busts or star, the money), the
-- dice, the title, the reward, the line and the button (`onPress`).
local function hero(
	parent: Instance,
	key: string,
	look: any,
	onPress: (TextButton) -> (),
	onOdds: (string) -> ()
): Hero
	local box = ShopCards.gradientCard(parent, "GroupHero" .. key, look, 3)
	local frame = box.frame
	local kind = if key == "Group" then H.GroupBlock else H.FavoriteBlock
	local art = ShopCards.art(frame, "Art", FreeParts.blockImage(kind), rgb(look.GlowTint), 4)
	art.picture.ZIndex = 6
	local copies: { ImageLabel } = {}
	for index = 1, #H.Copies - 1 do
		local copy = ShopCards.image(art.holder, "Copy" .. index, FreeParts.blockImage(kind), 5)
		copy.Visible = false
		table.insert(copies, copy)
	end
	local badge = HudParts.icon(art.holder, if key == "Group" then "Group" else "Star", "Badge")
	badge.ZIndex = 7
	share(badge, H.Badge)
	local cash = ShopCards.image(art.holder, "Cash", ICONS.CashStack, 7)
	cash.Visible = false
	share(cash, H.Cash)
	for _, twinkle in art.twinkles do
		twinkle.ZIndex = 8
	end
	local odds = ShopCards.oddsBadge(frame, "OddsBadge", 8)
	local title = words(frame, "Title", rgb(K.Numbers.Money))
	title.Text = if key == "Group" then W.GroupRow else W.FavoriteRow
	local reward = words(frame, "Reward", nil)
	local line = HudParts.note(frame, "Line", MIN_TEXT, "")
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextYAlignment = Enum.TextYAlignment.Top
	line.ZIndex = 6
	local made: Hero = {
		key = key,
		frame = frame,
		corner = box.corner,
		edge = box.edge,
		art = art,
		copies = copies,
		badge = badge,
		cash = cash,
		odds = odds,
		title = title,
		reward = reward,
		line = line,
		button = nil :: any,
		kind = kind,
		count = 0,
		look = nil,
	}
	made.button = HudParts.candy(frame, "", function()
		onPress(made.button)
	end, "Green")
	made.button.Name = "Button"
	made.button.AnchorPoint = Vector2.new(0.5, 0.5)
	made.button.ZIndex = 6
	odds.hit.Activated:Connect(function()
		UISound.play("Click")
		onOdds(made.kind)
	end)
	return made
end

--- Build both cards (closed) into `parent` (FreeSocial's section).
function FreeHeroes.new(parent: Instance, actions: Actions): any
	local self: any = setmetatable({}, FreeHeroes)
	local root = HudParts.frame(parent, "Heroes")
	root.ZIndex = 2
	self.root = root
	self.cards = {
		hero(root, "Group", H.Group, actions.join, actions.odds),
		hero(root, "Favorite", H.Favorite, actions.favorite, actions.odds),
	} :: { Hero }
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

-- How a card's pieces go at the scale `k`, `cardW` pixels wide.
local function plan(c: Hero, k: number, cardW: number): Plan
	local pad = round(H.PadUnits * k)
	local art = round(H.ArtUnits * k)
	local colX = pad + art + round(H.TextGapUnits * k)
	local colW = math.max(1, cardW - colX - pad)
	local rowGap = math.max(B.TextGapPx, round(H.RowGapUnits * k))
	local gap = math.max(B.TextGapPx, round(H.SectionGapUnits * k))
	-- The title on one line, smaller to fit; the reward and the line wrap.
	local titlePx = ShopCards.textPx(H.TitleUnits, k)
	local titleW = ShopCards.measure(c.title.Text, titlePx)
	if titleW > colW then
		titlePx = math.max(MIN_TEXT, math.floor(titlePx * colW / titleW))
	end
	local titleH = titlePx + B.TextBoxPx
	local rewardPx = ShopCards.textPx(H.RewardUnits, k)
	local rewardH = ShopParts.wrapHeight(c.reward.Text, rewardPx, colW, H.RewardMaxRows)
	local linePx = ShopCards.textPx(H.LineUnits, k)
	local lineH = if c.line.Text ~= ""
		then ShopParts.wrapHeight(c.line.Text, linePx, colW, H.LineMaxRows)
		else 0
	local textH = titleH + rowGap + rewardH + (if lineH > 0 then rowGap + lineH else 0)
	local topH = math.max(art, textH)
	local buttonH = ShopCards.buttonPx(H.ButtonUnits, k)
	return {
		pad = pad,
		art = art,
		colX = colX,
		colW = colW,
		rowGap = rowGap,
		gap = gap,
		titlePx = titlePx,
		titleH = titleH,
		rewardPx = rewardPx,
		rewardH = rewardH,
		linePx = linePx,
		lineH = lineH,
		textH = textH,
		topH = topH,
		buttonH = buttonH,
		buttonTextPx = ShopCards.textPx(H.ButtonTextUnits, k),
		need = pad + topH + gap + buttonH + pad,
	}
end

-- Place card `c`'s pieces by its plan `p`, the card `cardW` x `cardH` pixels.
local function place(c: Hero, p: Plan, k: number, cardW: number, cardH: number)
	c.corner.CornerRadius = UDim.new(0, round(H.CornerUnits * k))
	c.edge.Thickness = math.max(B.MinStrokePx, H.EdgeUnits * k)
	-- The picture and the words beside it, centred on each other; the dice on its corner.
	local artTop = p.pad + (p.topH - p.art) / 2
	local artX, artY = p.pad + p.art / 2, artTop + p.art / 2
	ShopCards.layoutArt(c.art, k, artX / k, artY / k, H.ArtUnits, H.Glow, H.Rays)
	local A = H.OddsBadge
	local dice = math.max(MIN_TEXT + B.BadgePadPx, round(A[3] * k))
	local edge = dice / 2 + B.TextGapPx -- never past the card's edge
	local diceX, diceY = math.max(edge, p.pad + A[1] * k), math.max(edge, artTop + A[2] * k)
	ShopCards.putPx(c.odds.badge, diceX, diceY, dice, dice)
	local y = p.pad + (p.topH - p.textH) / 2
	c.title.Position = UDim2.fromOffset(p.colX, round(y))
	c.title.Size = UDim2.fromOffset(p.colW, p.titleH)
	HudParts.setTextSize(c.title, p.titlePx)
	y += p.titleH + p.rowGap
	c.reward.Position = UDim2.fromOffset(p.colX, round(y))
	c.reward.Size = UDim2.fromOffset(p.colW, p.rewardH)
	HudParts.setTextSize(c.reward, p.rewardPx)
	y += p.rewardH + p.rowGap
	c.line.Visible = p.lineH > 0
	c.line.Position = UDim2.fromOffset(p.colX, round(y))
	c.line.Size = UDim2.fromOffset(p.colW, math.max(1, p.lineH))
	HudParts.setTextSize(c.line, p.linePx)
	-- The button across the card's foot.
	local button = c.button
	button.Position = UDim2.fromOffset(round(cardW / 2), round(cardH - p.pad - p.buttonH / 2))
	button.Size = UDim2.fromOffset(cardW - 2 * p.pad, p.buttonH)
	HudParts.setButtonTextSize(button, p.buttonTextPx)
	HudParts.setMinHit(button, TOUCH)
end

--- The cards' height at the scale `k` (the taller one's).
function FreeHeroes.height(self: any, k: number): number
	local cardW = round(H.CardUnits[1] * k)
	local height = round(H.CardUnits[2] * k)
	for _, c in self.cards :: { Hero } do
		height = math.max(height, plan(c, k, cardW).need)
	end
	return height
end

--- Lay both cards out side by side across the page at the scale `k` (the root `pageW` pixels
--- wide, at `y` in its parent); returns their height.
function FreeHeroes.layout(self: any, pageW: number, k: number, y: number): number
	local cardW = round(H.CardUnits[1] * k)
	local gap = round(H.GapUnits * k)
	local plans: { Plan } = {}
	local height = round(H.CardUnits[2] * k)
	for index, c in self.cards :: { Hero } do
		plans[index] = plan(c, k, cardW)
		height = math.max(height, plans[index].need)
	end
	self.root.Position = UDim2.fromOffset(0, y)
	self.root.Size = UDim2.fromOffset(pageW, height)
	local left = (pageW - 2 * cardW - gap) / 2
	for index, c in self.cards :: { Hero } do
		local x = left + (index - 1) * (cardW + gap) + cardW / 2
		ShopCards.putPx(c.frame, x, height / 2, cardW, height)
		place(c, plans[index], k, cardW, height)
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

-- The picture: `count` of block `kind` (the last copy in front), the money when it gives some.
local function setPicture(c: Hero, kind: string, count: number, money: boolean)
	c.cash.Visible = money
	if c.kind == kind and c.count == count then
		return
	end
	c.kind, c.count = kind, count
	local image = FreeParts.blockImage(kind)
	local spots = H.Copies[math.clamp(count, 1, #H.Copies)]
	c.art.picture.Image = image
	share(c.art.picture, spots[#spots])
	for index, copy in c.copies do
		local at = spots[index]
		copy.Visible = index < #spots and at ~= nil
		if copy.Visible then
			copy.Image = image
			share(copy, at)
		end
	end
end

-- The button's look: "Claimed" (grey, the check), or green with its words and icon (off
-- while `busy`). Changed only when it changes.
local function setButton(c: Hero, done: boolean, text: string, icon: string?, busy: boolean)
	local look = if done then "Claimed" else text .. "|" .. (icon or "") .. "|" .. tostring(busy)
	if c.look == look then
		return
	end
	c.look = look
	if done then
		HudParts.setTone(c.button, "Grey")
		HudParts.setButtonIcon(c.button, "Check")
		HudParts.setText(c.button, W.Claimed)
		HudParts.setEnabled(c.button, false, false)
		return
	end
	HudParts.setTone(c.button, "Green")
	HudParts.setButtonIcon(c.button, icon)
	HudParts.setText(c.button, text)
	HudParts.setEnabled(c.button, not busy)
end

--- Draw a RewardState's group and favorite. `busy(key)` says a claim is on its way;
--- `favoriting` that Roblox's favorite prompt is up. Returns true when the words changed (the
--- cards are laid out again).
function FreeHeroes.refresh(
	self: any,
	state: any,
	busy: (string) -> boolean,
	favoriting: boolean
): boolean
	if type(state) ~= "table" then
		return false
	end
	local changed = false
	for _, c in self.cards :: { Hero } do
		local view = if c.key == "Group" then state.group else state.favorite
		view = if type(view) == "table" then view else {}
		local reward = RewardsParts.reward(view.reward)
		-- The big words: the blocks (or the money when it gives none); the line: the money
		-- beside blocks and the group's match money.
		local best = RewardsParts.bestBlock(reward)
		local blocksOnly = table.clone(reward)
		blocksOnly.money = 0
		local big = if #reward.blocks > 0
			then RewardsParts.words(blocksOnly)
			else Format.money(reward.money)
		local parts: { string } = {}
		if #reward.blocks > 0 and reward.money > 0 then
			table.insert(parts, W.HeroMoney:format(Format.money(reward.money)))
		end
		local boost = round((tonumber(view.boost) or 0) * 100)
		if c.key == "Group" and boost > 0 then
			table.insert(parts, W.HeroBoost:format(boost))
		end
		local line = table.concat(parts, "\n")
		if c.reward.Text ~= big or c.line.Text ~= line then
			changed = true
		end
		setText(c.reward, big)
		setText(c.line, line)
		local kind = if best then best.kind else c.kind
		setPicture(c, kind, if best then math.min(best.count, #H.Copies) else 1, reward.money > 0)
		local done = view.claimed == true
		if c.key == "Group" then
			local member = view.member == true
			local words = if member then W.Claim else W.Join
			setButton(c, done, words, if member then nil else "Group", busy("Group"))
		else
			setButton(c, done, W.Favorite, "Star", busy("Favorite") or favoriting)
		end
	end
	return changed
end

--- The button a gamepad lands on: the first card's that can be pressed.
function FreeHeroes.primary(self: any): GuiObject?
	for _, c in self.cards :: { Hero } do
		if c.button.Visible and c.button.Active and c.look ~= "Claimed" then
			return c.button
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register both cards with the menu's `stage` (ids "GroupHero1", "GroupHero2" in
--- Config.UI.FreeReward.Open); on landing each starts its picture's loops, its button's shine
--- and its badge rocking, held by `keep` until the menu closes.
function FreeHeroes.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	for index, c in self.cards :: { Hero } do
		stage:add("GroupHero" .. index, c.frame, function()
			local R = H.BadgeRock
			keep(ShopCards.all({
				ShopCards.artLoops(c.art),
				ShopCards.buttonShine(
					c.button,
					B.ButtonShineEvery,
					(index - 1) * B.ShineStaggerSeconds
				),
				UIAnim.turn(c.badge, 0, if index == 1 then R[1] else -R[1], R[2]),
			}))
		end)
	end
end

return FreeHeroes
