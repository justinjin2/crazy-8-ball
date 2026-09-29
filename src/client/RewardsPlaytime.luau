--!strict
-- RewardsPlaytime: the Rewards menu's Playtime tab (docs/prompts/ECONOMY_UI_PROMPT.md section
-- 11, ECONOMY 10): one row per gift of the RewardState's `playtime` (10 min $100, 30 min a
-- Standard Case, 60 min 2 Standard Cases and the day's last gift's ult spin: "2 Standard Cases
-- + 1 Ult Spin"), each with the prize's pictures and words (on two lines when one is too
-- narrow), the time played of the time needed ("4:12 / 10:00") over a progress bar, and a
-- button: the time still to play (a stopwatch), a green Claim that breathes once it is due, or
-- a grey Claimed.
-- A line under them: "Played today: 24:13" and "New gifts in 5:12:03".
--
-- The time is the server's (`playSeconds` at `sentAt`), ticked on here between two states and
-- never past the UTC day's end; every new state replaces the estimate. The server counts
-- playtime every Config.Daily.PlaytimeTickSeconds and re-sends the state when a gift becomes
-- due, and it credits the seconds since its last count before it answers a claim, so a gift
-- shows Claim once the estimate passes its time (plus ReadyMarginSeconds; the estimate never
-- runs ahead of the server's clock). The server still decides: a refused claim says why.
-- Claim calls ctx.claim("ClaimPlaytime", index, "Gift<index>", button) (RewardsMenu).
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
local clock = RewardsParts.clock

type Row = {
	root: Frame,
	card: RewardsParts.Card,
	pictures: RewardsParts.Pictures,
	title: TextLabel,
	time: TextLabel,
	bar: RewardsParts.Bar,
	button: TextButton,
	-- From the state.
	index: number,
	need: number, -- seconds of play the gift needs
	serverReady: boolean,
	claimed: boolean,
	-- What it shows now: "Wait", "Claim" or "Claimed".
	mode: string,
}

local RewardsPlaytime = {}
RewardsPlaytime.__index = RewardsPlaytime

--- The Playtime tab in `page` (a MenuFrame page). `ctx` is RewardsMenu's: claim(action, arg,
--- key, button) and busy(key).
function RewardsPlaytime.new(page: Frame, ctx: any): any
	local self: any = setmetatable({}, RewardsPlaytime)
	self.page = page
	self.ctx = ctx
	self.rows = {} :: { Row }
	self.state = nil :: any
	self.geo = nil :: any
	self.active = false
	self.pulses = {} :: { [TextButton]: UIAnim.Handle }
	self.footer = RewardsParts.footer(page, "Footer", 3)
	self.footerH = 0
	return self
end

-- One gift's row (made once, reused).
function RewardsPlaytime.row(self: any, index: number): Row
	local found = self.rows[index]
	if found then
		return found
	end
	local root = HudParts.frame(self.page, "Gift" .. index)
	root.ZIndex = 3
	local card = RewardsParts.card(root, "Card", 4)
	local pictures = RewardsParts.newPictures(root, "Reward", 6)
	local title = HudParts.text(root, "Prize", R.GiftTitlePx[2], "")
	title.TextWrapped = false
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 7
	local time = HudParts.note(root, "Time", R.GiftTimePx[2], "")
	time.AutoLocalize = false -- two clocks
	time.TextWrapped = false
	time.TextXAlignment = Enum.TextXAlignment.Right
	time.ZIndex = 7
	local bar = RewardsParts.bar(root, "Bar", 7)
	local row: Row
	local button = HudParts.candy(root, W.Claim, function()
		if row.mode == "Claim" then
			self.ctx.claim("ClaimPlaytime", row.index, "Gift" .. row.index, row.button)
		end
	end, "Green")
	button.Name = "Claim"
	button.ZIndex = 8
	HudParts.setMinHit(button, R.TouchPx)
	row = {
		root = root,
		card = card,
		pictures = pictures,
		title = title,
		time = time,
		bar = bar,
		button = button,
		index = index,
		need = 0,
		serverReady = false,
		claimed = false,
		mode = "",
	}
	self.rows[index] = row
	return row
end

-- Seconds played today by `now` (the server's clock): the state's count ticked on, never past
-- the UTC day's end.
function RewardsPlaytime.played(self: any, now: number): number
	local state = self.state
	if type(state) ~= "table" then
		return 0
	end
	local base = RewardsParts.whole(state.playSeconds)
	local sentAt = if type(state.sentAt) == "number" then state.sentAt else now
	local resetsAt = if type(state.resetsAt) == "number" then state.resetsAt else math.huge
	local elapsed = math.clamp(now - sentAt, 0, math.max(0, resetsAt - sentAt))
	return base + elapsed
end

--- Draw a RewardState (nil before the first: nothing).
function RewardsPlaytime.set(self: any, state: any)
	self.state = state
	local gifts = if type(state) == "table" and type(state.playtime) == "table"
		then state.playtime
		else {}
	for index, entry in gifts do
		local row = self:row(index)
		local info: any = if type(entry) == "table" then entry else {}
		row.index = if type(info.index) == "number" then info.index else index
		row.need = RewardsParts.whole(info.minutes) * 60
		row.serverReady = info.ready == true
		row.claimed = info.claimed == true
		row.mode = "" -- redraw the button
		local reward = RewardsParts.reward(info.reward)
		row.title.Text = RewardsParts.words(reward)
		RewardsParts.setPictures(row.pictures, reward)
		row.root.Visible = true
	end
	for index = #gifts + 1, #self.rows do
		self.rows[index].root.Visible = false
	end
	self:tick(workspace:GetServerTimeNow())
	if self.geo then
		self:layout(self.geo)
	end
end

-- A row's button: the time left, Claim or Claimed.
local function showButton(self: any, row: Row, mode: string, left: number)
	local busy = self.ctx.busy("Gift" .. row.index)
	if mode == "Wait" then
		HudParts.setText(row.button, clock(left))
		if row.mode ~= "Wait" then
			HudParts.setTone(row.button, "White")
			HudParts.setButtonIcon(row.button, "Stopwatch")
			HudParts.setEnabled(row.button, false, false)
		end
	elseif mode == "Claim" then
		if row.mode ~= "Claim" then
			HudParts.setText(row.button, W.Claim)
			HudParts.setTone(row.button, "Green")
			HudParts.setButtonIcon(row.button, nil)
		end
		HudParts.setEnabled(row.button, not busy)
	else
		if row.mode ~= "Claimed" then
			HudParts.setText(row.button, W.Claimed)
			HudParts.setTone(row.button, "Grey")
			HudParts.setButtonIcon(row.button, "Check")
			HudParts.setEnabled(row.button, false, false)
		end
	end
	row.mode = mode
end

--- Every TickSeconds while open (and on every state): the clocks, bars and buttons.
function RewardsPlaytime.tick(self: any, now: number)
	local state = self.state
	if type(state) ~= "table" then
		return
	end
	local played = self:played(now)
	for _, row in self.rows do
		if row.root.Visible then
			local due = row.need > 0 and played >= row.need + R.ReadyMarginSeconds
			local mode = if row.claimed
				then "Claimed"
				elseif row.serverReady or due then "Claim"
				else "Wait"
			local shown = if row.claimed then row.need else math.min(played, row.need)
			row.time.Text = W.GiftTime:format(clock(shown), clock(row.need))
			local progress = if row.need <= 0 then 1 else shown / row.need
			RewardsParts.setBar(row.bar, progress, if mode == "Wait" then "Blue" else "Green")
			showButton(self, row, mode, row.need - played)
		end
	end
	local footer: RewardsParts.Footer = self.footer
	local left = W.PlayedToday:format(clock(played))
	local resetsAt = if type(state.resetsAt) == "number" then state.resetsAt else now
	local right = W.GiftsReset:format(clock(resetsAt - now))
	local changed = #footer.left.Text ~= #left or #footer.right.Text ~= #right
	footer.left.Text = left
	footer.right.Text = right
	self:refreshPulses()
	if changed and self.geo then
		self:layout(self.geo)
	end
end

-- Every due gift's Claim breathes while the menu is open on this tab.
function RewardsPlaytime.refreshPulses(self: any)
	local want: { [TextButton]: boolean } = {}
	if self.active then
		for _, row in self.rows do
			if row.root.Visible and row.mode == "Claim" then
				want[row.button] = true
			end
		end
	end
	for button, handle in self.pulses do
		if not want[button] then
			handle.stop()
			self.pulses[button] = nil
		end
	end
	for button in want do
		if not self.pulses[button] then
			self.pulses[button] = UIAnim.pulse(button)
		end
	end
end

--- The menu is open on this tab (true) or not: loops run only while it is.
function RewardsPlaytime.setActive(self: any, on: boolean)
	self.active = on
	self:refreshPulses()
end

--- Whether a gift can be claimed now (the tab's red dot).
function RewardsPlaytime.claimable(self: any): boolean
	for _, row in self.rows do
		if row.root.Visible and row.mode == "Claim" then
			return true
		end
	end
	return false
end

--- Where a gamepad lands on this tab: the first gift's Claim that can be pressed.
function RewardsPlaytime.primary(self: any): GuiObject?
	for _, row in self.rows do
		if row.root.Visible and row.mode == "Claim" and row.button.Selectable then
			return row.button
		end
	end
	return nil
end

-- Lay one row out in w x h pixels.
local function layoutRow(row: Row, w: number, h: number, t: number, buttonText: number)
	local pad = span(R.GiftPadPx, t)
	local picPx = math.max(1, h - 2 * pad)
	RewardsParts.layoutPictures(row.pictures, picPx, picPx, span(R.CountTextPx, t))
	row.pictures.root.Position = UDim2.fromOffset(pad + round(picPx / 2), round(h / 2))
	local x = pad + picPx + pad
	local buttonW = span(R.GiftButtonWidthPx, t)
	local buttonH = math.min(h - 2 * pad, span(R.GiftButtonPx, t))
	row.button.Position = UDim2.fromOffset(w - pad - buttonW, round((h - buttonH) / 2))
	row.button.Size = UDim2.fromOffset(buttonW, buttonH)
	HudParts.setButtonTextSize(row.button, buttonText)
	local textW = math.max(1, w - x - buttonW - 2 * pad)
	local titlePx = span(R.GiftTitlePx, t)
	local timePx = span(R.GiftTimePx, t)
	local titleH = titlePx + 6
	local barH = span(R.BarPx, t)
	HudParts.setTextSize(row.title, titlePx)
	HudParts.setTextSize(row.time, timePx)
	-- The time takes what its widest value needs ("60:00 / 60:00"); the prize the rest, on a
	-- second line when one is too narrow for it and the row has the height (the last gift's
	-- "2 Standard Cases + 1 Ult Spin" on a phone); the time stays level with its last line.
	local widest = W.GiftTime:format(clock(row.need), clock(row.need))
	local timeW = math.min(round(textW / 2), math.ceil(RewardsParts.textWidth(widest, timePx)) + 8)
	local titleW = math.max(1, textW - timeW - 6)
	local twoH = 2 * titlePx + 8
	local wraps = RewardsParts.textWidth(row.title.Text, titlePx) + 6 > titleW
		and twoH + 4 + barH <= h - 2 * pad
	row.title.TextWrapped = wraps
	local blockH = if wraps then twoH else titleH
	local top = round((h - (blockH + 4 + barH)) / 2)
	row.title.Position = UDim2.fromOffset(x, top)
	row.title.Size = UDim2.fromOffset(titleW, blockH)
	row.time.Position = UDim2.fromOffset(x + textW - timeW, top + blockH - titleH)
	row.time.Size = UDim2.fromOffset(timeW, titleH)
	row.bar.root.Position = UDim2.fromOffset(x, top + blockH + 4)
	row.bar.root.Size = UDim2.fromOffset(textW, barH)
end

--- Size and place everything from the menu's layout (MenuFrame's onLayout geo).
function RewardsPlaytime.layout(self: any, geo: any)
	self.geo = geo
	local width, height = geo.content.X, geo.content.Y
	local t = geo.t
	local footerH = RewardsParts.layoutFooter(self.footer, width, height, span(R.FooterTextPx, t))
	self.footerH = footerH
	local gap = span(R.GiftGapPx, t)
	local room = height - (if footerH > 0 then footerH + gap else 0)
	local shown: { Row } = {}
	for _, row in self.rows do
		if row.root.Visible then
			table.insert(shown, row)
		end
	end
	local n = #shown
	if n == 0 then
		return
	end
	local rowH = math.min((room - gap * (n - 1)) / n, span(R.GiftRowMaxPx, t))
	rowH = math.max(1, math.floor(rowH))
	local top = math.max(0, round((room - (n * rowH + (n - 1) * gap)) / 2))
	for index, row in shown do
		row.root.Position = UDim2.fromOffset(0, top + (index - 1) * (rowH + gap))
		row.root.Size = UDim2.fromOffset(width, rowH)
		layoutRow(row, width, rowH, t, math.max(K.Text.Min, geo.button))
	end
end

return RewardsPlaytime
