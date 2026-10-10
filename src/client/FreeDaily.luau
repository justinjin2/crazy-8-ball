--!strict
-- FreeDaily: the Free Reward menu's Daily section (the designer's pick "daily A", 2026-10-08),
-- under "- DAILY -": a pale panel with its navy pill ("FIRST WEEK" or "DAILY STREAK" and the
-- time to the next day), the row's six day tiles (3 x 2, each in its own colours: "DAY 1", the
-- reward's pictures, "$10,000", its status button) and day 7 tall at the right as the row's
-- big prize (its best block over gold rays, the tilted rainbow "RARE!", what comes with it; the
-- first week's day 7 shows its cue from day 1 instead: economy v6's Chroma Cue on its own big
-- card (its rarity's frame, name and bar), as the goal to come back for, with a tilted orange "7 IN A ROW!" while
-- the first week's days are still in a row; a missed day turns day 7 into
-- Config.Daily.FirstWeekMissed, an Epic block, 2026-10-10). Each tile shows its day's one
-- reward; VIP's daily part shows once, on a gold line under the row (a VIP's bonus, else what
-- VIP would add).
-- A claimed day turns grey under a big check; today's wears a thick pale-gold edge and its
-- green Claim! breathes; until a match is finished today it reads "Play a match"
-- (Config.Daily.NeedsMatch); once today is claimed the next day reads "Tomorrow". A tile with a
-- lucky block wears the sky-blue dice opening that block's Odds & Details (Claim All buys them:
-- a paid random item, Roblox's rule). Under the tiles: the first week's line ("Claim 7 days in
-- a row to win the Chroma Cue!", or what day 7 is after a missed day), the later weeks' (the
-- week's free miss) or "Finish one match today", VIP's gold line, and
-- Claim All, the green Robux button that claims every day still ahead in this row at once
-- (RewardState.claimAll; hidden where paid random items are restricted or nothing is left).
-- The server decides everything; this draws its RewardState. Sizes in
-- Config.UI.FreeReward.Daily, words in Strings.FreeReward.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local CueThumb = require(script.Parent.CueThumb)
local InventoryCard = require(script.Parent.InventoryCard)
local FreeParts = require(script.Parent.FreeParts)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local RewardsParts = require(script.Parent.RewardsParts)
local ShopCards = require(script.Parent.ShopCards)
local Stage = require(script.Parent.Stage)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local B = Config.UI.ShopBlocks
local P = B.Panel
local F = Config.UI.FreeReward
local D = F.Daily
local FIRST_DAYS = #Config.Daily.FirstWeek
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
	cue: InventoryCard.Card?, -- day 7's cue card in the art's place when it gives one
	amount: TextLabel?, -- a tile's money, over its pictures' foot
	line: TextLabel?, -- day 7's extras ("+2 Ability Spins")
	extras: { string }, -- what its line says, one entry each
	check: ImageLabel,
	status: TextButton,
	odds: ShopCards.Badge,
	kind: string?, -- the block its dice shows
	mode: string, -- what its status shows now
	look: string, -- "Day", "Claimed" or "Today": its colours and edge now
}

export type Ctx = {
	claim: (action: string, arg: any, key: string, button: GuiObject) -> (),
	busy: (key: string) -> boolean,
	buy: (product: string) -> (),
	odds: (kind: string) -> (), -- a dice: that lucky block's Odds & Details (OddsDetails)
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
	self.footerWide = false -- the footer spans the panel (no Claim All beside it)
	local root = HudParts.frame(parent, "DailySection")
	root.ZIndex = 2
	self.root = root
	local panel = ShopCards.panel(root, "DailyPanel")
	self.panel = panel
	local card = panel.frame
	self.title = ShopCards.titlePill(root, "DailyTitle", W.FirstWeekTitle, true)
	self.title.sample = D.TimeSample

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
			cue = nil,
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
			local art = ShopCards.art(box.frame, "Art", "", rgb(D.HeroGlowTint), 4)
			made.art = art
			-- The cue's own card in the block's place (its rarity's frame, name and bar, as in
			-- Cues and the Index; designer, 2026-10-10: "a lot bigger and noticeable"), over the
			-- same glow and rays, filling the room between "DAY 7" and the status.
			local cue = InventoryCard.new(box.frame, { name = "CueCard", onPress = function() end })
			cue.button.Interactable = false
			cue.button.Selectable = false
			cue.button.ZIndex = 5
			cue.button.Visible = false
			made.cue = cue
			local line = HudParts.text(box.frame, "Line", ShopCards.textPx(D.Hero.LineUnits, 1), "")
			line.AnchorPoint = Vector2.new(0.5, 0.5)
			line.RichText = true -- the cue's rarity in its colour
			line.ZIndex = 6
			made.line = line
			-- The tilted rainbow "RARE!": the holder keeps the tilt, the words inside shake.
			local op = HudParts.frame(box.frame, "Op")
			op.AnchorPoint = Vector2.new(0.5, 0.5)
			op.Rotation = D.Hero.OpDegrees
			op.ZIndex = 8
			local words = ShopCards.label(op, "Words", W.Op, Color3.new(1, 1, 1), 9)
			words.Position = UDim2.fromScale(0.5, 0.5)
			words.Size = UDim2.fromScale(1, 1)
			self.op, self.opWords = op, words
			-- The first week's "7 IN A ROW!" (shown while its days are in a row).
			local rowTag =
				ShopCards.tag(box.frame, "RowTag", W.InRowTag, rgb(D.Hero.RowTagColor), 8)
			rowTag.holder.Visible = false
			self.rowTag = rowTag
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
		-- The day's dice: its best block's Odds & Details (the menu's OddsDetails).
		made.odds = ShopCards.oddsBadge(box.frame, "OddsBadge", 10)
		made.odds.badge.Visible = false
		made.odds.hit.Activated:Connect(function()
			local kind = made.kind
			if kind then
				UISound.play("Click")
				ctx.odds(kind)
			end
		end)
		table.insert(self.days, made)
	end

	-- Under the tiles: the week's line and Claim All.
	local footer = HudParts.note(card, "Footer", ShopCards.textPx(D.Footer.TextUnits, 1), "")
	footer.AnchorPoint = Vector2.new(0.5, 0.5)
	footer.ZIndex = 4
	self.footer = footer
	-- VIP's daily part, once for the whole row (not on every tile).
	local vipLine = HudParts.note(card, "Vip", ShopCards.textPx(D.VipLine.TextUnits, 1), "")
	vipLine.AnchorPoint = Vector2.new(0.5, 0.5)
	vipLine.TextColor3 = rgb(D.VipColor)
	vipLine.ZIndex = 4
	self.vipLine = vipLine
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
	-- The block, its glow and rays shrink together; its dice keeps to its lower right. A cue's
	-- card takes all the room between the day's name and the line (or the status, with no
	-- line), at the card's own shape.
	local cue = d.cue
	local y, size
	if cue and cue.button.Visible then
		local top = nameEnd + B.TextGapPx
		local bottom = if words == ""
			then statusY - statusH / 2 - B.TextGapPx
			else lineY - lineH / 2 - B.TextGapPx
		local units: { number } = Config.UI.CueCard.Units :: any
		local cardW = math.min(side, math.max(1, bottom - top) * units[1] / units[2])
		size = cardW * units[2] / units[1]
		y = (top + bottom) / 2
		ShopCards.putPx(cue.button, w / 2 * k, y, cardW, size)
	else
		y, size = FreeParts.fit(k, H.Art[1], H.Art[2], nameEnd + B.TextGapPx, lineY - lineH / 2)
	end
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
	local R = H.RowTag
	ShopCards.layoutTag(self.rowTag, k, R[1], R[2], R[3], R[4], R[5])
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
	ShopCards.line(self.vipLine, k, x, D.VipLine.Y, w, ShopCards.textPx(D.VipLine.TextUnits, k))
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
			-- A cue (the first week's day 7) shows in the block's place, glowing its colour.
			local cueId = if reward.cues then reward.cues[1] else nil
			if d.cue then
				d.cue.button.Visible = cueId ~= nil
				if cueId then
					InventoryCard.set(d.cue, { cueId = cueId, bare = true })
				end
			end
			d.art.picture.Visible = cueId == nil
			if cueId then
				ShopCards.setArt(d.art, "", CueThumb.cueColor(cueId))
				d.kind = nil
			else
				local image = if best
					then FreeParts.blockImage(best)
					else Config.UI.Kit.Icons.CashStack
				ShopCards.setArt(d.art, image or "", rgb(D.HeroGlowTint))
			end
			-- The card says the cue's name and rarity, so the line keeps only what comes with it.
			local rest: any = table.clone(reward)
			rest.cues = nil
			d.extras = FreeParts.extras(rest, if cueId then nil else best)
		end
		local odds = d.odds
		local showOdds = d.kind ~= nil
		if odds.badge.Visible ~= showOdds then
			odds.badge.Visible = showOdds
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
	-- The first week's "7 IN A ROW!" on day 7 while its days are still in a row.
	local inRow = login.firstWeek == true and login.firstInRow == true
	self.rowTag.holder.Visible = inRow and RewardsParts.whole(login.firstWeekDays) < FIRST_DAYS
	-- The footer: the match today's claim waits for, the first week's days, or the free miss.
	local text: string
	local left = RewardsParts.whole(login.firstWeekLeft)
	local last = days[FIRST_DAYS]
	local prize = RewardsParts.reward(if type(last) == "table" then last.reward else nil)
	if login.needsMatch == true then
		text = W.NeedMatch:format(math.max(1, loginDay))
	elseif login.firstWeek == true and RewardsParts.whole(login.firstWeekDays) >= FIRST_DAYS then
		text = W.FirstWeekDone
	elseif login.firstWeek == true or left > 0 then
		-- Day 7's prize for 7 days in a row, or what it is after a missed day.
		local cueId = if prize.cues then prize.cues[1] else nil
		if inRow then
			text = if cueId
				then W.InRowCue:format(CueThumb.cueName(cueId))
				else W.InRowLine:format(RewardsParts.summary(prize))
		else
			text = if left <= 1
				then W.MissedLast:format(RewardsParts.summary(prize))
				else W.MissedLine:format(RewardsParts.summary(prize), left)
		end
	elseif login.frozen == true and login.claimedToday ~= true then
		text = W.Frozen
	else
		text = if login.freezeReady == true then W.StreakLine else W.StreakLineUsed
	end
	setText(self.footer, text)
	-- VIP's daily part, once: a VIP's bonus, or what VIP would add.
	local vipPart = RewardsParts.reward(login.vipPart)
	local vipText = if login.vip == true
		then W.VipLine:format(RewardsParts.gains(vipPart))
		else W.VipPitch:format(RewardsParts.summary(vipPart))
	local none = vipPart.money <= 0 and #vipPart.blocks == 0 and vipPart.spins <= 0
	setText(self.vipLine, if none then "" else vipText)
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
	stage:add("DailyVip", self.vipLine)
	stage:add("DailyRowTag", self.rowTag.holder)
end

--- The menu opened (`open` true) or closed: the breathing Claim!.
function FreeDaily.setOpen(self: any, open: boolean)
	self.open = open
	if not open then
		self:setPulse(nil)
	elseif self.state then
		self:refresh(self.state)
	end
end

return FreeDaily
