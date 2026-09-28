--!strict
-- RewardsDaily: the Rewards menu's Daily tab (docs/prompts/ECONOMY_UI_PROMPT.md section 11,
-- ECONOMY 10), drawn from the RewardState's `days`, `login`, `weeks` and `resetsAt`:
--   * the week's seven day tiles, Config.UI.Rewards.Columns to a row (days 1-4, then 5, 6
--     and day 7 spanning the rest of its row as the week's big prize, over faint gold rays),
--     each with "Day 1", the reward's picture ("x2" for several) and its words;
--   * claimed days faded with a green check, the days still to come a little dimmer, and
--     today's tile with a gold edge and a soft gold glow, its green Claim button breathing
--     while it can be claimed;
--   * a line under them: "Week 1 of 4: a Legendary Case on day 28", and once today is claimed
--     "Next reward in 5:12:03" (to the next UTC midnight, the server's resetsAt).
-- The server decides everything (a missed day starts again at day 1); this only draws its
-- state. Claim calls ctx.claim("ClaimDaily", nil, "Daily", button) (RewardsMenu).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local HudParts = require(script.Parent.HudParts)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)

local R = Config.UI.Rewards
local K = Config.UI.Kit
local W = Strings.Menus.Rewards
local span = RewardsParts.span
local round = RewardsParts.round

type Tile = {
	root: Frame,
	glow: ImageLabel,
	card: RewardsParts.Card,
	rays: ImageLabel,
	day: TextLabel,
	pictures: RewardsParts.Pictures,
	words: TextLabel,
	check: ImageLabel,
	claim: TextButton,
	-- What it shows now.
	claimable: boolean, -- today's, not claimed yet: the Claim button
	today: boolean,
	claimed: boolean,
	big: boolean, -- the last day: spans the rest of its row, rays behind its prize
}

local RewardsDaily = {}
RewardsDaily.__index = RewardsDaily

--- The Daily tab in `page` (a MenuFrame page). `ctx` is RewardsMenu's: claim(action, arg,
--- key, button) and busy(key).
function RewardsDaily.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, RewardsDaily)
	self.page = page
	self.ctx = ctx
	self.tiles = {} :: { Tile }
	self.state = nil :: any
	self.geo = nil :: any
	self.active = false -- the menu is open on this tab: today's Claim breathes
	self.pulse = nil :: UIAnim.Handle?
	self.pulsing = nil :: TextButton?
	self.footer = RewardsParts.footer(page, "Footer", 3)
	self.footerH = 0
	self.dayCount = 0
	return self
end

-- One day's tile (made once, reused as the state changes).
function RewardsDaily.tile(self: any, index: number): Tile
	local found = self.tiles[index]
	if found then
		return found
	end
	local root = HudParts.frame(self.page, "Day" .. index)
	root.ZIndex = 3
	root.LayoutOrder = index
	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = K.ShadowImage
	glow.ImageColor3 = HudParts.tone("Gold")
	glow.ImageTransparency = R.GlowTransparency
	glow.ScaleType = Enum.ScaleType.Slice
	local s = K.ShadowSlice
	glow.SliceCenter = Rect.new(s[1], s[2], s[3], s[4])
	glow.Position = UDim2.fromOffset(-R.GlowSpreadPx, -R.GlowSpreadPx)
	glow.Size = UDim2.new(1, 2 * R.GlowSpreadPx, 1, 2 * R.GlowSpreadPx)
	glow.ZIndex = 3
	glow.Visible = false
	glow.Parent = root
	local card = RewardsParts.card(root, "Card", 4)
	local rays = HudParts.icon(root, "Case", "Rays")
	rays.Image = K.Art.Rays
	rays.ImageColor3 = HudParts.tone("Gold")
	rays.ImageTransparency = R.RaysTransparency
	rays.AnchorPoint = Vector2.new(0.5, 0.5)
	rays.ZIndex = 5
	rays.Visible = false
	local day = HudParts.text(root, "DayWords", R.DayTextPx[2], "")
	day.TextWrapped = false
	day.ZIndex = 7
	local pictures = RewardsParts.newPictures(root, "Reward", 6)
	local words = HudParts.note(root, "Words", R.WordsTextPx[2], "")
	words.TextWrapped = true
	words.ZIndex = 7
	local check = HudParts.icon(root, "Check", "Check")
	check.AnchorPoint = Vector2.new(1, 0)
	check.ZIndex = 16
	check.Visible = false
	local tile: Tile
	local claim = HudParts.candy(root, W.Claim, function()
		if tile.claimable then
			self.ctx.claim("ClaimDaily", nil, "Daily", tile.claim)
		end
	end, "Green")
	claim.Name = "Claim"
	claim.ZIndex = 17
	claim.Visible = false
	HudParts.setMinHit(claim, R.TouchPx)
	tile = {
		root = root,
		glow = glow,
		card = card,
		rays = rays,
		day = day,
		pictures = pictures,
		words = words,
		check = check,
		claim = claim,
		claimable = false,
		today = false,
		claimed = false,
		big = false,
	}
	self.tiles[index] = tile
	return tile
end

--- Draw a RewardState (nil before the first: nothing).
function RewardsDaily.set(self: any, state: any)
	self.state = state
	local days = if type(state) == "table" and type(state.days) == "table" then state.days else {}
	local login = if type(state) == "table" and type(state.login) == "table"
		then state.login
		else {}
	local canClaim = login.canClaim == true
	local busy = self.ctx.busy("Daily")
	local count = #days
	self.dayCount = count
	for index, entry in days do
		local tile = self:tile(index)
		local info: any = if type(entry) == "table" then entry else {}
		local reward = RewardsParts.reward(info.reward)
		local dayNumber = if type(info.day) == "number" then info.day else index
		tile.today = info.today == true
		tile.claimed = info.claimed == true
		tile.claimable = tile.today and canClaim and not tile.claimed
		tile.big = index == count and count > 1
		tile.root.Visible = true
		tile.day.Text = W.Day:format(dayNumber)
		tile.day.TextColor3 =
			HudParts.tone(if tile.today and not tile.claimed then "Gold" else "White")
		tile.words.Text = RewardsParts.words(reward)
		RewardsParts.setPictures(tile.pictures, reward)
		local fade = if tile.claimed then R.ClaimedFade elseif not tile.today then R.LaterFade else 0
		RewardsParts.fadePictures(tile.pictures, fade)
		HudParts.setTextTransparency(tile.day, fade)
		tile.words.TextTransparency = fade
		tile.check.Visible = tile.claimed
		tile.glow.Visible = tile.today and not tile.claimed
		-- Today's tile sits under its neighbours, so its glow shows in the gaps, never over them.
		tile.root.ZIndex = if tile.glow.Visible then 2 else 3
		tile.rays.Visible = tile.big
		RewardsParts.setEdge(
			tile.card,
			if tile.today and not tile.claimed then "Gold" else nil,
			if tile.today and not tile.claimed then R.TodayStrokePx else nil
		)
		tile.claim.Visible = tile.claimable
		HudParts.setEnabled(tile.claim, tile.claimable and not busy)
	end
	for index = count + 1, #self.tiles do
		self.tiles[index].root.Visible = false
		self.tiles[index].claimable = false
	end
	self:refreshFooter()
	self:refreshPulse()
	if self.geo then
		self:layout(self.geo)
	end
end

-- The line under the tiles: the week and its prize; the countdown once today is claimed.
function RewardsDaily.refreshFooter(self: any): boolean
	local state = self.state
	local login = if type(state) == "table" and type(state.login) == "table"
		then state.login
		else {}
	local left, right = "", ""
	if type(state) == "table" then
		local weeks = RewardsParts.whole(state.weeks)
		local week = math.max(1, RewardsParts.whole(login.week))
		if weeks > 0 then
			left = W.WeekLine:format(week, weeks, RewardsParts.bonusWords(), weeks * self.dayCount)
		end
		if login.claimedToday == true and type(state.resetsAt) == "number" then
			local now = workspace:GetServerTimeNow()
			right = W.NextIn:format(RewardsParts.clock(state.resetsAt - now))
		end
	end
	local footer: RewardsParts.Footer = self.footer
	local changed = #footer.left.Text ~= #left or #footer.right.Text ~= #right
	footer.left.Text = left
	footer.right.Text = right
	return changed
end

-- Today's Claim breathes while the menu is open on this tab.
function RewardsDaily.refreshPulse(self: any)
	local target: TextButton? = nil
	if self.active then
		for _, tile in self.tiles do
			if tile.claimable and tile.root.Visible then
				target = tile.claim
			end
		end
	end
	if target == self.pulsing then
		return
	end
	if self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end
	self.pulsing = target
	if target then
		self.pulse = UIAnim.pulse(target)
	end
end

--- The menu is open on this tab (true) or not: loops run only while it is.
function RewardsDaily.setActive(self: any, on: boolean)
	self.active = on
	self:refreshPulse()
end

--- Whether today can be claimed (the tab's red dot).
function RewardsDaily.claimable(self: any): boolean
	for _, tile in self.tiles do
		if tile.claimable and tile.root.Visible then
			return true
		end
	end
	return false
end

--- Where a gamepad lands on this tab: today's Claim, while it can be pressed.
function RewardsDaily.primary(self: any): GuiObject?
	for _, tile in self.tiles do
		if tile.claimable and tile.root.Visible and tile.claim.Selectable then
			return tile.claim
		end
	end
	return nil
end

--- Every TickSeconds while open: the countdown.
function RewardsDaily.tick(self: any, _now: number)
	if self:refreshFooter() and self.geo then
		self:layout(self.geo)
	end
end

-- Lay one tile out in w x h pixels.
local function layoutTile(tile: Tile, w: number, h: number, t: number)
	local pad = math.max(4, round(h * R.TilePadShare))
	local inner = math.max(1, w - 2 * pad)
	local dayPx = span(R.DayTextPx, t)
	local dayH = dayPx + 4
	local wordsPx = span(R.WordsTextPx, t)
	local wordsH = wordsPx + 6
	-- Words too wide for one line (a long translation) get a second one.
	if RewardsParts.textWidth(tile.words.Text, wordsPx) + 6 > inner then
		wordsH = 2 * wordsPx + 8
	end
	HudParts.setTextSize(tile.day, dayPx)
	HudParts.setTextSize(tile.words, wordsPx)
	local y = pad
	tile.day.Position = UDim2.fromOffset(pad, y)
	tile.day.Size = UDim2.fromOffset(inner, dayH)
	y += dayH
	local bottom = h - pad
	if tile.claimable then
		local claimH = math.clamp(round(h * R.ClaimShare), R.ClaimPx[1], R.ClaimPx[2])
		tile.claim.Position = UDim2.fromOffset(pad, bottom - claimH)
		tile.claim.Size = UDim2.fromOffset(inner, claimH)
		HudParts.setButtonTextSize(
			tile.claim,
			math.max(K.Text.Min, math.min(K.Text.Button, claimH - 12))
		)
		bottom -= claimH + 2
	end
	tile.words.Position = UDim2.fromOffset(pad, bottom - wordsH)
	tile.words.Size = UDim2.fromOffset(inner, wordsH)
	bottom -= wordsH
	local room = math.max(1, bottom - y - 2)
	local width = RewardsParts.layoutPictures(tile.pictures, room, inner, span(R.CountTextPx, t))
	local middle = round((y + bottom) / 2)
	tile.pictures.root.Position = UDim2.fromOffset(round(w / 2), middle)
	local raysPx = math.min(h - 2 * pad, math.max(room, width) * 2)
	tile.rays.Size = UDim2.fromOffset(raysPx, raysPx)
	tile.rays.Position = UDim2.fromOffset(round(w / 2), middle)
	local checkPx = math.min(R.CheckMaxPx, round(h * R.CheckShare))
	tile.check.Size = UDim2.fromOffset(checkPx, checkPx)
	tile.check.Position = UDim2.fromOffset(w - round(pad / 2), round(pad / 2))
end

--- Size and place everything from the menu's layout (MenuFrame's onLayout geo).
function RewardsDaily.layout(self: any, geo: any)
	self.geo = geo
	local width, height = geo.content.X, geo.content.Y
	local t = geo.t
	local footerH = RewardsParts.layoutFooter(self.footer, width, height, span(R.FooterTextPx, t))
	self.footerH = footerH
	local gap = span(R.TileGapPx, t)
	local gridH = height - (if footerH > 0 then footerH + gap else 0)
	local shown: { Tile } = {}
	for _, tile in self.tiles do
		if tile.root.Visible then
			table.insert(shown, tile)
		end
	end
	local n = #shown
	if n == 0 then
		return
	end
	local cols = math.min(R.Columns, n)
	local rows = math.ceil(n / cols)
	local cellW = (width - gap * (cols - 1)) / cols
	local rowH = math.min((gridH - gap * (rows - 1)) / rows, span(R.TileMaxPx, t))
	rowH = math.max(1, math.floor(rowH))
	local top = math.max(0, round((gridH - (rows * rowH + (rows - 1) * gap)) / 2))
	for index, tile in shown do
		local row = (index - 1) // cols
		local col = (index - 1) % cols
		local cells = if index == n then cols - col else 1
		local x = round(col * (cellW + gap))
		local w = round(cellW * cells + gap * (cells - 1))
		local y = top + row * (rowH + gap)
		tile.root.Position = UDim2.fromOffset(x, y)
		tile.root.Size = UDim2.fromOffset(w, rowH)
		layoutTile(tile, w, rowH, t)
	end
end

return RewardsDaily
