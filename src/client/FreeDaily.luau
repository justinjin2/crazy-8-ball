--!strict
-- FreeDaily: the Free Reward menu's Daily section (the designer's pick "daily A", 2026-10-08),
-- under "- DAILY -": a pale panel with its navy pill ("FIRST WEEK" or "DAILY STREAK" and the
-- time to the next day), the row's six day tiles (3 x 2, each in its own colours: "DAY 1", the
-- reward's pictures, "$10,000", its status button) and day 7 tall at the right as the row's
-- big prize (its best block over gold rays, the tilted rainbow "OP!", what comes with it).
-- A claimed day turns grey under a big check; today's wears a thick pale-gold edge and its
-- green Claim! breathes; until a match is finished today it reads "Play a match"
-- (Config.Daily.NeedsMatch); once today is claimed the next day reads "Tomorrow". A tile with a
-- lucky block wears the sky-blue "i" with that block's odds (Claim All buys them: a paid random
-- item, Roblox's rule). Under the tiles: the first week's line ("First week: any 7 days within
-- 14 · 12 days left"), the later weeks' (the week's free miss) or "Finish one match today", and
-- Claim All, the green Robux button that claims every day still ahead in this row at once
-- (RewardState.claimAll; hidden where paid random items are restricted or nothing is left).
-- The server decides everything; this draws its RewardState. Sizes in
-- Config.UI.FreeReward.Daily, words in Strings.FreeReward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local ShopOdds = require(script.Parent.ShopOdds)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)

local B = Config.UI.ShopBlocks
local P = B.Panel
local F = Config.UI.FreeReward
local D = F.Daily
local KINDS: { [string]: any } = Config.LuckyBlocks.Kinds :: any
local NAMES: { [string]: string } = Strings.LuckyBlocks.Names :: any
local FIRST_DAYS = #Config.Daily.FirstWeek
local WINDOW = Config.Daily.FirstWeekWindow
local W = Strings.FreeReward
local rgb, round = ShopCards.rgb, ShopCards.round

-- One day: a tile (days 1-6) or the big prize (day 7, `hero`).
type Day = {
	day: number,
	hero: boolean,
	box: ShopCards.Box,
	gradient: UIGradient,
	label: TextLabel, -- "DAY 1"
	pictures: FreeParts.Pictures?, -- a tile's pictures
	art: ShopCards.Art?, -- day 7's block
	amount: TextLabel?, -- a tile's money, over its pictures' foot
	line: TextLabel?, -- day 7's extras ("+2 Ability Spins")
	extras: { string }, -- what its line says, one entry each
	check: ImageLabel,
	status: TextButton,
	odds: ShopCards.Badge,
	kind: string?, -- the block its "i" shows
	mode: string, -- what its status shows now
	look: string, -- "Day", "Claimed" or "Today": its colours and edge now
}

export type Ctx = {
	claim: (action: string, arg: any, key: string, button: GuiObject) -> (),
	busy: (key: string) -> boolean,
	buy: (product: string) -> (),
}

local FreeDaily = {}
FreeDaily.__index = FreeDaily

-- The day's colours (Config.UI.FreeReward.Daily.Looks), a claimed day's grey.
local function lookOf(day: number, claimed: boolean): any
	if claimed then
		return D.ClaimedLook
	end
	local looks: { any } = D.Looks
	return looks[(day - 1) % #looks + 1]
end

--- Build the section (closed) into `parent` (the menu's Daily group).
function FreeDaily.new(parent: Instance, ctx: Ctx): any
	local self: any = setmetatable({}, FreeDaily)
	self.ctx = ctx
	self.k = 1
	self.state = nil :: any
	self.pulse = nil :: UIAnim.Handle?
	self.pulsing = nil :: TextButton?
	self.oddsOn = nil :: Day? -- the day whose "i" the pop-up shows
	self.footerWide = false -- the footer spans the panel (no Claim All beside it)
	local root = HudParts.frame(parent, "DailySection")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "DailyPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "DailyTitle", W.FirstWeekTitle, true)
	self.title.sample = D.TimeSample

	-- One odds pop-up for every day's "i", beside the badge that opened it.
	self.popup = ShopOdds.new(root, function(w: number, h: number): Vector2
		local margin = B.PopupMarginPx
		local on: Day? = self.oddsOn
		if on == nil then
			return Vector2.new(margin, margin)
		end
		local badge = on.odds.badge
		local at = badge.AbsolutePosition - root.AbsolutePosition
		local x = at.X + badge.AbsoluteSize.X + margin
		if x + w > root.AbsoluteSize.X - margin then
			x = at.X - w - margin
		end
		local y = math.clamp(at.Y, margin, math.max(margin, root.AbsoluteSize.Y - h - margin))
		return Vector2.new(math.max(margin, x), y)
	end)

	self.days = {} :: { Day }
	for day = 1, FIRST_DAYS do
		local hero = day == FIRST_DAYS
		local look = lookOf(day, false)
		local box = ShopCards.gradientCard(card, "DailyDay" .. day, look, 3)
		local gradient = box.frame:FindFirstChildOfClass("UIGradient") :: UIGradient
		local label = ShopCards.label(box.frame, "Day", W.Day:format(day), nil, 6)
		local made: Day = {
			day = day,
			hero = hero,
			box = box,
			gradient = gradient,
			label = label,
			pictures = nil,
			art = nil,
			amount = nil,
			line = nil,
			extras = {},
			check = nil :: any,
			status = nil :: any,
			odds = nil :: any,
			kind = nil,
			mode = "",
			look = "Day",
		}
		if hero then
			made.art = ShopCards.art(box.frame, "Art", "", rgb(D.HeroGlowTint), 4)
			local line = HudParts.text(box.frame, "Line", ShopCards.textPx(D.Hero.LineUnits, 1), "")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.ZIndex = 6
			made.line = line
			-- The tilted rainbow "OP!": the holder keeps the tilt, the words inside shake.
			local op = HudParts.frame(box.frame, "Op")
			op.AnchorPoint = Vector2.new(0.5, 0.5)
			op.Rotation = D.Hero.OpDegrees
			op.ZIndex = 8
			local words = ShopCards.label(op, "Words", W.Op, Color3.new(1, 1, 1), 9)
			words.Position = UDim2.fromScale(0.5, 0.5)
			words.Size = UDim2.fromScale(1, 1)
			self.op, self.opWords = op, words
		else
			made.pictures = FreeParts.pictures(box.frame, "Pictures", 4)
			local amount =
				ShopCards.label(box.frame, "Amount", "", rgb(Config.UI.Kit.Numbers.Money), 8)
			amount.AutoLocalize = false -- "$10,000"
			made.amount = amount
		end
		local check = HudParts.icon(box.frame, "Check", "Check")
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.ZIndex = 9
		check.Visible = false
		made.check = check
		made.status = FreeParts.status(box.frame, "Status", function()
			if made.mode == "Claim" then
				ctx.claim("ClaimDaily", nil, "Daily", made.status)
			end
		end)
		made.odds = ShopCards.oddsBadge(box.frame, "OddsBadge", 10)
		made.odds.badge.Visible = false
		self.popup:attach(made.odds.hit, function(): { ShopOdds.Outcome }
			self.oddsOn = made
			local kind = made.kind or ""
			self.popup.heading.Text = NAMES[kind] or kind
			local row = KINDS[kind]
			return if row and row.Odds then ShopOdds.blockOutcomes(row.Odds) else {}
		end)
		table.insert(self.days, made)
	end

	-- Under the tiles: the week's line and Claim All.
	local footer = HudParts.note(card, "Footer", ShopCards.textPx(D.Footer.TextUnits, 1), "")
	footer.AnchorPoint = Vector2.new(0.5, 0.5)
	footer.ZIndex = 4
	self.footer = footer
	local claimAll = ShopCards.robuxButton(card, "ClaimAll", function()
		local offer = self:offer()
		if offer then
			ctx.buy(offer.product)
		end
	end)
	claimAll.Visible = false
	self.claimAll = claimAll
	return self
end

--------------------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------------------

--- The section's height at the scale `k` (its title pill's top half, then the panel).
function FreeDaily.heightFor(k: number): number
	return round((B.TitlePill.HeightUnits / 2 + D.Units[2]) * k)
end

-- A day's name ("DAY 1") at `y` units, never closer to the top than TilePadPx; returns the
-- pixel its words end at.
local function layoutName(
	d: Day,
	k: number,
	w: number,
	y: number,
	units: number,
	side: number
): number
	local px = ShopCards.textPx(units, k)
	local at = math.max(y * k, F.TilePadPx + px / 2)
	ShopCards.putPx(d.label, w / 2 * k, at, (w - 2 * side) * k, px + B.TextBoxPx)
	HudParts.setTextSize(d.label, px)
	return at + px / 2
end

-- Lay a tile (days 1-6) out in its own units. On a phone the words keep their smallest size
-- while the units shrink, so the status keeps to the foot, the money sits clear over it and
-- the pictures shrink into the room left under the day's name (as FreeParts.statusAt).
local function layoutTile(d: Day, k: number)
	local T = D.Tile
	local w, h = T.Units[1], T.Units[2]
	local side = (w - 2 * T.SideUnits) * k
	ShopCards.sizeBox(
		d.box,
		k,
		T.CornerUnits,
		if d.look == "Today" then D.TodayEdgeUnits else T.EdgeUnits
	)
	local nameEnd = layoutName(d, k, w, T.DayY, T.DayUnits, T.SideUnits)
	local statusY, statusH, statusText = FreeParts.statusAt(
		k,
		T.StatusY,
		T.StatusUnits,
		T.StatusTextUnits,
		round(h * k) - F.TilePadPx
	)
	FreeParts.placeStatus(d.status, w / 2 * k, statusY, side, statusH, statusText)
	local statusTop = statusY - statusH / 2
	local amount = d.amount :: TextLabel
	local amountPx = ShopCards.textPx(T.AmountUnits, k)
	local amountY = ShopCards.above(T.AmountY, T.AmountUnits, amountPx, 1, statusTop, k)
	ShopCards.putPx(amount, w / 2 * k, amountY, side, amountPx + B.TextBoxPx)
	HudParts.setTextSize(amount, amountPx)
	-- The pictures: their foot behind the money (the mock's "$10,000" over the cash), or with
	-- no money down to the status.
	local S = T.Pictures
	local bottom = if amount.Visible then amountY + amountPx / 2 else statusTop - B.TextGapPx
	local y, size = FreeParts.fit(k, S[1], S[2], nameEnd + B.TextGapPx, bottom)
	FreeParts.layoutPictures(d.pictures :: FreeParts.Pictures, k, w / 2, y / k, size / k, S[3])
	local check = size * T.CheckUnits / S[2]
	ShopCards.putPx(d.check, w / 2 * k, y, check, check)
	local O = T.OddsBadge
	ShopCards.layoutBadge(d.odds, k, w - O[1], O[2], O[3])
end

-- Lay day 7 out in its own units, stacked from its edges on a phone as a tile: the status at
-- the foot, what comes with the block over it (as many lines as it takes: a VIP's extras are
-- longer), the block shrinking into the room left under the day's name.
local function layoutHero(self: any, d: Day, k: number)
	local H = D.Hero
	local w, h = H.Box[3], H.Box[4]
	local side = (w - 2 * H.SideUnits) * k
	ShopCards.sizeBox(
		d.box,
		k,
		P.InnerCornerUnits,
		if d.look == "Today" then D.TodayEdgeUnits else H.EdgeUnits
	)
	local nameEnd = layoutName(d, k, w, H.DayY, H.DayUnits, H.SideUnits)
	local statusY, statusH, statusText = FreeParts.statusAt(
		k,
		H.StatusY,
		H.StatusUnits,
		H.StatusTextUnits,
		round(h * k) - F.TilePadPx
	)
	FreeParts.placeStatus(d.status, w / 2 * k, statusY, side, statusH, statusText)
	local line = d.line :: TextLabel
	local linePx = ShopCards.textPx(H.LineUnits, k)
	local words, lineH = FreeParts.wordsFit(d.extras, linePx, side)
	if line.Text ~= words then
		line.Text = words
	end
	local lineY = math.min(H.LineY * k, statusY - statusH / 2 - B.TextGapPx - lineH / 2)
	ShopCards.putPx(line, w / 2 * k, lineY, side, lineH)
	HudParts.setTextSize(line, linePx)
	-- The block, its glow and rays shrink together; its "i" keeps to its lower right.
	local y, size = FreeParts.fit(k, H.Art[1], H.Art[2], nameEnd + B.TextGapPx, lineY - lineH / 2)
	local share = size / (H.Art[2] * k)
	ShopCards.layoutArt(
		d.art :: ShopCards.Art,
		k,
		w / 2,
		y / k,
		H.Art[2] * share,
		H.Glow * share,
		H.Rays * share
	)
	local check = size * 0.6
	ShopCards.putPx(d.check, w / 2 * k, y, check, check)
	local O = H.OddsBadge
	ShopCards.layoutBadge(
		d.odds,
		k,
		w / 2 + (O[1] - w / 2) * share,
		y / k + (O[2] - H.Art[1]) * share,
		O[3]
	)
	local Op = H.Op
	ShopCards.put(self.op, k, Op[1], Op[2], Op[3], Op[4])
	HudParts.setTextSize(self.opWords, ShopCards.textPx(Op[5], k))
end

--- Lay the section out across `width` pixels at the scale `k`, its top `y` pixels down its
--- group; returns its height.
function FreeDaily.layout(self: any, width: number, k: number, y: number): number
	self.k = k
	local Wd, Hd = D.Units[1], D.Units[2]
	local top = B.TitlePill.HeightUnits / 2
	local cardW = round(Wd * k)
	local height = FreeDaily.heightFor(k)
	self.root.Position = UDim2.fromOffset(math.floor((width - cardW) / 2), y)
	self.root.Size = UDim2.fromOffset(cardW, height)
	ShopCards.put(self.panel.frame, k, Wd / 2, top + Hd / 2, Wd, Hd)
	ShopCards.sizeBox(self.panel, k, P.CornerUnits, P.EdgeUnits)
	ShopCards.layoutTitlePill(self.title, k, Wd / 2, top)
	local G, T = D.Grid, D.Tile
	local tw, th = T.Units[1], T.Units[2]
	for _, d in self.days :: { Day } do
		if d.hero then
			local H = D.Hero.Box
			ShopCards.put(d.box.frame, k, H[1] + H[3] / 2, H[2] + H[4] / 2, H[3], H[4])
			layoutHero(self, d, k)
		else
			local column, row = (d.day - 1) % G.Columns, (d.day - 1) // G.Columns
			local x = G.Left + column * (tw + G.GapUnits[1]) + tw / 2
			local cy = G.Top + row * (th + G.GapUnits[2]) + th / 2
			ShopCards.put(d.box.frame, k, x, cy, tw, th)
			layoutTile(d, k)
		end
	end
	self:layoutFooter()
	return height
end

-- The footer under the tiles beside Claim All, or across the panel without it.
function FreeDaily.layoutFooter(self: any)
	local k = self.k
	local Fo, C = D.Footer, D.ClaimAll
	local wide = not self.claimAll.Visible
	self.footerWide = wide
	local x = if wide then D.Units[1] / 2 else Fo.X
	local w = if wide then D.Units[1] - 2 * D.Grid.Left else Fo.WidthUnits
	ShopCards.line(self.footer, k, x, Fo.Y, w, ShopCards.textPx(Fo.TextUnits, k))
	local button = self.claimAll
	button.Position = UDim2.fromOffset(round(C.X * k), round(C.Y * k))
	button.Size = UDim2.fromOffset(round(C.WidthUnits * k), ShopCards.buttonPx(C.HeightUnits, k))
	HudParts.setButtonTextSize(button, ShopCards.textPx(C.TextUnits, k))
	HudParts.setMinHit(button, Config.UI.Menu.Frame.TouchMinPx)
end

--------------------------------------------------------------------------------------------
-- What the server says
--------------------------------------------------------------------------------------------

local function setText(label: TextLabel, text: string)
	if label.Text ~= text then
		label.Text = text
	end
end

-- The Claim All offer when it can be bought (RewardState.claimAll), else nil.
function FreeDaily.offer(self: any): any
	local state = self.state
	local offer = if type(state) == "table" then state.claimAll else nil
	if type(offer) == "table" and offer.available == true and type(offer.product) == "string" then
		return offer
	end
	return nil
end

-- Put a day's colours, edge and pictures' fade for `look`.
local function setLook(d: Day, look: string, k: number)
	if d.look == look then
		return
	end
	d.look = look
	local colours = lookOf(d.day, look == "Claimed")
	d.gradient.Color = ColorSequence.new(rgb(colours.Top), rgb(colours.Bottom))
	d.box.edge.Color = if look == "Today" then rgb(D.TodayEdge) else rgb(colours.Edge)
	local units = if look == "Today"
		then D.TodayEdgeUnits
		elseif d.hero then D.Hero.EdgeUnits
		else D.Tile.EdgeUnits
	d.box.edge.Thickness = math.max(B.MinEdgePx, units * k)
	local tint = FreeParts.claimedTint(look == "Claimed")
	if d.pictures then
		FreeParts.tintPictures(d.pictures, tint)
	end
	if d.art then
		d.art.picture.ImageColor3 = tint
	end
end

--- Draw a RewardState (nil before the first: the tiles wait, showing nothing claimable).
function FreeDaily.refresh(self: any, state: any)
	self.state = state
	if type(state) ~= "table" then
		return
	end
	local days = if type(state.days) == "table" then state.days else {}
	local login = if type(state.login) == "table" then state.login else {}
	local k = self.k
	local title = self.title
	local word = if login.firstWeek == true then W.FirstWeekTitle else W.StreakTitle
	if title.word.Text ~= word then
		title.word.Text = word
		ShopCards.layoutTitlePill(title, k, D.Units[1] / 2, B.TitlePill.HeightUnits / 2)
	end
	local busy = self.ctx.busy("Daily")
	local claimable: TextButton? = nil
	local loginDay = RewardsParts.whole(login.day)
	for _, d in self.days :: { Day } do
		local view = days[d.day]
		local reward = RewardsParts.reward(if type(view) == "table" then view.reward else nil)
		local claimed = type(view) == "table" and view.claimed == true
		local today = type(view) == "table" and view.today == true
		d.box.frame.Visible = type(view) == "table"
		-- Pictures: a tile's row of them and its money, day 7's best block and its extras.
		local best = FreeParts.bestBlock(reward)
		d.kind = best
		if d.pictures and d.amount then
			FreeParts.setPictures(d.pictures, reward)
			setText(d.amount, if reward.money > 0 then Format.money(reward.money) else "")
			-- A claimed day shows its check, not its money (the mock).
			d.amount.Visible = reward.money > 0 and not claimed
		elseif d.art and d.line then
			local image = if best then FreeParts.blockImage(best) else Config.UI.Kit.Icons.CashStack
			ShopCards.setArt(d.art, image or "", rgb(D.HeroGlowTint))
			d.extras = FreeParts.extras(reward, best)
		end
		local odds = d.odds
		local showOdds = best ~= nil
		if odds.badge.Visible ~= showOdds then
			odds.badge.Visible = showOdds
			if not showOdds and self.oddsOn == d then
				self.popup:close()
			end
		end
		d.check.Visible = claimed
		setLook(d, if claimed then "Claimed" elseif today then "Today" else "Day", k)
		local mode = "Locked"
		if claimed then
			mode = "Claimed"
		elseif today then
			mode = if login.canClaim == true
				then "Claim"
				elseif login.needsMatch == true then "Play"
				else "Locked"
		elseif login.claimedToday == true and d.day == loginDay + 1 then
			mode = "Tomorrow"
		end
		d.mode = mode
		FreeParts.setStatus(d.status, mode, nil, busy)
		-- Its pieces again: the room they share depends on what it shows.
		if d.hero then
			layoutHero(self, d, k)
		else
			layoutTile(d, k)
		end
		if mode == "Claim" and not busy then
			claimable = d.status
		end
	end
	self:setPulse(claimable)
	-- The footer: the match today's claim waits for, the first week's days, or the free miss.
	local text: string
	local left = RewardsParts.whole(login.firstWeekLeft)
	if login.needsMatch == true then
		text = W.NeedMatch:format(math.max(1, loginDay))
	elseif login.firstWeek == true and RewardsParts.whole(login.firstWeekDays) >= FIRST_DAYS then
		text = W.FirstWeekDone
	elseif login.firstWeek == true or left > 0 then
		text = if left <= 1
			then W.FirstWeekLast:format(FIRST_DAYS, WINDOW)
			else W.FirstWeekLine:format(FIRST_DAYS, WINDOW, left)
	elseif login.frozen == true and login.claimedToday ~= true then
		text = W.Frozen
	else
		text = if login.freezeReady == true then W.StreakLine else W.StreakLineUsed
	end
	setText(self.footer, text)
	-- Claim All: the live price when the shop has it, else Config's.
	local offer = self:offer()
	local button = self.claimAll
	local show = offer ~= nil
	if offer then
		local shop = ItemState.shop()
		local products = if type(shop) == "table" and type(shop.products) == "table"
			then shop.products
			else {}
		local product = products[offer.product]
		local robux = if type(product) == "table" and type(product.robux) == "number"
			then product.robux
			else RewardsParts.whole(offer.robux)
		ShopCards.setButtonWords(button, W.ClaimAll:format(ShopCards.robuxText(robux)))
		HudParts.setEnabled(button, not self.ctx.busy("ClaimAll"))
	end
	if button.Visible ~= show then
		button.Visible = show
		self:layoutFooter()
	end
	self:tick(workspace:GetServerTimeNow())
end

--- Every TickSeconds while open: the pill's time to the next day.
function FreeDaily.tick(self: any, now: number)
	local state = self.state
	local resetsAt = if type(state) == "table" and type(state.resetsAt) == "number"
		then state.resetsAt
		else nil
	local title = self.title
	local x, y = D.Units[1] / 2, B.TitlePill.HeightUnits / 2
	ShopCards.showTitleTime(title, resetsAt ~= nil, x, y)
	if resetsAt and title.time then
		setText(title.time, ShopCards.timeLeft(math.max(0, resetsAt - now)))
	end
end

-- Today's Claim! breathes while it can be pressed and the menu is open.
function FreeDaily.setPulse(self: any, button: TextButton?)
	if not self.open then
		button = nil
	end
	if self.pulsing == button then
		return
	end
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pulsing = button
	if button then
		self.pulse = FreeParts.pulse(button)
	end
end

--- Whether something here can be claimed now (the Daily jump button's "!").
function FreeDaily.claimable(self: any): boolean
	local state = self.state
	local login = if type(state) == "table" then state.login else nil
	return type(login) == "table" and login.canClaim == true
end

--- The button a gamepad lands on: today's Claim! (never Claim All: it buys).
function FreeDaily.primary(self: any): GuiObject?
	for _, d in self.days :: { Day } do
		if d.mode == "Claim" and d.status.Selectable then
			return d.status
		end
	end
	return nil
end

--------------------------------------------------------------------------------------------
-- Stage
--------------------------------------------------------------------------------------------

--- Register every piece with the menu's `stage` (ids in Config.UI.FreeReward.Open); `keep`
--- holds a piece's idle loops (started as it lands) until the menu closes.
function FreeDaily.register(self: any, stage: Stage.Stage, keep: (UIAnim.Handle) -> ())
	stage:add("DailyPanel", self.panel.frame)
	stage:add("DailyTitle", self.title.pill)
	for _, d in self.days :: { Day } do
		if d.hero then
			stage:add("DailyDay7", d.box.frame, function()
				keep(ShopCards.artLoops(d.art :: ShopCards.Art))
			end)
		else
			stage:add("DailyDay" .. d.day, d.box.frame)
		end
	end
	stage:add("DailyOp", self.op, function()
		keep(ShopCards.all({ UIAnim.rainbow(self.opWords), UIAnim.shake(self.opWords, "Text") }))
	end)
	stage:add("DailyClaimAll", self.claimAll, function()
		keep(ShopCards.buttonShine(self.claimAll, B.ButtonShineEvery, 0))
	end)
	stage:add("DailyFooter", self.footer)
end

--- The menu opened (`open` true) or closed: the breathing Claim! and the odds pop-up.
function FreeDaily.setOpen(self: any, open: boolean)
	self.open = open
	if not open then
		self:setPulse(nil)
		self.popup:close()
	elseif self.state then
		self:refresh(self.state)
	end
end

return FreeDaily
