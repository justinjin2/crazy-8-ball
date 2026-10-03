--!strict
-- RewardPopups: the rewards that pop up instead of living in a menu (GUI lane, designer
-- 2026-10-03, C9). The server gives them by itself and says so on RewardGiven:
-- - "Daily": today's login claim, given on join. The card: "DAY 3 LOGIN REWARD!" (shaking),
--   what was given (pictures and words), the week's seven days (claimed ones checked, today's
--   gold), the 28-day track ("Day 10 of 28" with its bar and the next prize), and the streak
--   freeze's state. Collect flies it to the money HUD and the column.
-- - "Playtime": a playtime gift reached: "THANKS FOR PLAYING!", what it gave, "for playing 30
--   minutes", Collect.
-- Both wait their turn in the Popups queue (never in a match, during the tutorial or over a
-- menu). The reward is already in the save: Collect only plays the flight. Case Drops in a
-- reward play their own 8-ball reveal after (MagicBall, also queued). A or Enter presses
-- Collect; B and Escape close the card too. Sizes in Config.UI.RewardPopups.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local Popups = require(script.Parent.Popups)
local RewardsFlyer = require(script.Parent.RewardsFlyer)
local RewardsParts = require(script.Parent.RewardsParts)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local P = Config.UI.RewardPopups
local K = Config.UI.Kit
local W = Strings.RewardPopups
local ACTION = "8ballRewardPopupClose"
local PRIORITY = Enum.ContextActionPriority.High.Value + 30

local RewardPopups = {}

local count = 0
-- Studio checks only (GuiQA "rewardPopup" with a size): lay the next card out as if the screen
-- were this size, in a frame of that size at the top left.
local qaSize: Vector2? = nil

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function whole(x: any): number
	return if type(x) == "number" and x == x and x > 0 and x < math.huge then math.floor(x) else 0
end

-- The words of a reward with its Case Drops: "$5,000 + 1 Case Drop".
function RewardPopups.words(value: any): string
	local reward = RewardsParts.reward(value)
	local drops = whole(if type(value) == "table" then value.drops else 0)
	local text = RewardsParts.words(reward)
	if drops > 0 then
		local dropWords = if drops == 1 then W.Drop else W.Drops:format(drops)
		text = if text == "" then dropWords else W.Plus:format(text, dropWords)
	end
	return text
end

-- The reward's pictures as icon keys and counts: the cash, each case, the spins, the drops.
local function pictures(value: any): { { key: string, label: string } }
	local reward = RewardsParts.reward(value)
	local list = {}
	for _, picture in RewardsParts.pictures(reward) do
		local label = picture.label
			or (
				if picture.count > 1
					then Strings.Menus.Rewards.CaseCount:format(picture.count)
					else ""
			)
		table.insert(list, { key = picture.key, label = label })
	end
	local drops = whole(if type(value) == "table" then value.drops else 0)
	if drops > 0 then
		table.insert(list, {
			key = "MagicBall",
			label = if drops > 1 then Strings.Menus.Rewards.CaseCount:format(drops) else "",
		})
	end
	return list
end

-- The card: a ScreenGui over the HUD, a popup card with a shaking title, `build(body, geo)`
-- filling the middle, and Collect at the bottom. Calls `done` once closed.
local function card(
	screen: ScreenGui,
	deps: any,
	opts: { title: string, height: { number }, reward: any, build: (Frame, any) -> () },
	done: () -> ()
)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RewardPopup"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + P.DisplayOrderAbove
	gui.Parent = screen.Parent
	local size = gui.AbsoluteSize
	local holder: Instance = gui
	local fake = qaSize
	if fake then
		qaSize = nil
		size = fake
		local frame = HudParts.frame(gui, "QaScreen")
		frame.Size = UDim2.fromOffset(fake.X, fake.Y)
		frame.BackgroundTransparency = 0.6
		holder = frame
	end
	local t = math.clamp((size.Y - 360) / (1080 - 360), 0, 1)
	local function span(pair: { number }): number
		return round(pair[1] + (pair[2] - pair[1]) * t)
	end
	local w = math.min(span(P.WidthPx), size.X - 32)
	local h = math.min(span(opts.height), size.Y - 24)
	local root = HudParts.popupCard(holder, "Card")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(w, h)
	root.Visible = false
	local pad = round(10 + 6 * t)
	local titlePx = math.max(K.Text.Min, span(P.TitlePx))
	local title = HudParts.text(
		root,
		"Title",
		titlePx,
		opts.title,
		HudParts.color(Config.UI.Shop.Page.HeaderColor)
	)
	title.TextWrapped = false
	title.Position = UDim2.fromOffset(pad, pad)
	title.Size = UDim2.fromOffset(w - 2 * pad, titlePx + 6)
	title.ZIndex = 4
	local shake = UIAnim.shake(title, "Text")
	local sparkle = UIAnim.sparkle(root, HudParts.color(K.Numbers.Money))

	local buttonH = math.max(44, span(P.ButtonPx))
	local body = HudParts.frame(root, "Body")
	body.Position = UDim2.fromOffset(pad, pad + titlePx + 10)
	body.Size = UDim2.fromOffset(w - 2 * pad, h - 2 * pad - titlePx - 10 - buttonH - 8)
	body.ZIndex = 3
	local geo = {
		t = t,
		span = span,
		width = body.Size.X.Offset,
		height = body.Size.Y.Offset,
	}
	opts.build(body, geo)

	local closed = false
	local close: (fly: boolean) -> ()
	local collect = HudParts.candy(root, W.Collect, function()
		UISound.play("Click")
		close(true)
	end, "Green")
	collect.AnchorPoint = Vector2.new(0.5, 1)
	collect.Size = UDim2.fromOffset(math.min(w - 2 * pad, P.ButtonWidthPx), buttonH)
	collect.Position = UDim2.new(0.5, 0, 1, -pad)
	collect.ZIndex = 5
	HudParts.setButtonTextSize(collect, math.max(K.Text.Min, span({ 18, 24 })))
	local pulse = UIAnim.pulse(collect)

	local escape = UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.Escape then
			close(true)
		end
	end)
	ContextActionService:BindActionAtPriority(ACTION, function(_n, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			close(true)
		end
		return Enum.ContextActionResult.Sink
	end, false, PRIORITY, Enum.KeyCode.ButtonB)

	close = function(fly: boolean)
		if closed then
			return
		end
		closed = true
		escape:Disconnect()
		ContextActionService:UnbindAction(ACTION)
		shake.stop()
		sparkle.stop()
		pulse.stop()
		if fly and deps.rewardsFlyer then
			local from = collect.AbsolutePosition + collect.AbsoluteSize / 2
			deps.rewardsFlyer:reward(opts.reward, from)
		end
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		UIAnim.popOut(root, function()
			gui:Destroy()
			done()
		end)
	end

	UIAnim.popIn(root)
	UIAnim.glowBurst(root, HudParts.color(K.Numbers.Money), 0.3)
	UISound.play("Claim")
	local lastInput = UserInputService:GetLastInputType().Name
	if string.sub(lastInput, 1, 7) == "Gamepad" then
		GuiService.SelectedObject = collect
	end
end

-- The reward row: its pictures side by side over its words, centred in `parent` from `y`.
-- Returns the height used.
local function rewardRow(parent: Frame, geo: any, value: any, y: number): number
	local px = geo.span(P.PicturePx)
	local amountPx = math.max(K.Text.Min, geo.span(P.AmountPx))
	local list = pictures(value)
	local n = math.max(1, #list)
	local each = math.min(px, math.floor(geo.width / n))
	local row = HudParts.frame(parent, "Pictures")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, y)
	row.Size = UDim2.fromOffset(each * n, each)
	row.ZIndex = 3
	for index, picture in list do
		local image = HudParts.icon(row, picture.key, "Picture" .. index)
		image.Position = UDim2.fromOffset((index - 1) * each, 0)
		image.Size = UDim2.fromOffset(each, each)
		image.ZIndex = 4
		if picture.label ~= "" then
			local label = HudParts.text(
				image,
				"Count",
				math.max(K.Text.Min, round(each * 0.28)),
				picture.label
			)
			label.AutoLocalize = false
			label.TextWrapped = false
			label.AnchorPoint = Vector2.new(1, 1)
			label.Position = UDim2.fromScale(1, 1)
			label.Size = UDim2.fromScale(1, 0.4)
			label.TextXAlignment = Enum.TextXAlignment.Right
			label.ZIndex = 5
		end
		UIAnim.slam(image)
	end
	local words = HudParts.text(
		parent,
		"Amount",
		amountPx,
		RewardPopups.words(value),
		HudParts.color(K.Numbers.Money)
	)
	words.AutoLocalize = false
	words.TextWrapped = false
	words.Position = UDim2.fromOffset(0, y + each + 2)
	words.Size = UDim2.fromOffset(geo.width, amountPx + 6)
	words.ZIndex = 4
	return each + 2 + amountPx + 6
end

-- One small line of text across the body at `y` (ink with no outline, or `tint` in the kit's
-- outlined style); returns its height.
local function line(
	parent: Frame,
	geo: any,
	name: string,
	text: string,
	y: number,
	tint: Color3?
): number
	local px = math.max(K.Text.Min, geo.span(P.LinePx))
	local label = if tint
		then HudParts.text(parent, name, px, text, tint)
		else HudParts.note(parent, name, px, text)
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(0, y)
	label.Size = UDim2.fromOffset(geo.width, px + 6)
	label.ZIndex = 4
	return px + 6
end

-- The daily login card's middle: the reward, the week's days, the track and the freeze.
local function buildDaily(body: Frame, geo: any, value: any, state: any)
	local y = rewardRow(body, geo, value, 0) + 6
	local login = if type(state) == "table" and type(state.login) == "table"
		then state.login
		else {}
	local days = if type(state) == "table" and type(state.days) == "table" then state.days else {}
	-- The week's seven days.
	local dayPx = geo.span(P.DayPx)
	local gap = 4
	local n = math.max(1, #days)
	dayPx = math.min(dayPx, math.floor((geo.width - (n - 1) * gap) / n))
	local strip = HudParts.frame(body, "Days")
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, y)
	strip.Size = UDim2.fromOffset(n * dayPx + (n - 1) * gap, dayPx)
	strip.ZIndex = 3
	local textPx = math.max(10, geo.span(P.DayTextPx))
	for index, day in days do
		if type(day) ~= "table" then
			continue
		end
		local tile = HudParts.frame(strip, "Day" .. index)
		tile.Position = UDim2.fromOffset((index - 1) * (dayPx + gap), 0)
		tile.Size = UDim2.fromOffset(dayPx, dayPx)
		tile.BackgroundTransparency = 0
		tile.BackgroundColor3 = if day.today
			then HudParts.tone("Gold")
			elseif day.claimed then HudParts.tone("Green")
			else HudParts.tone("Grey")
		tile.ZIndex = 4
		HudParts.corner(tile, 8)
		local words = HudParts.text(tile, "Words", textPx, W.DayTile:format(day.day))
		words.AutoLocalize = false
		words.TextWrapped = false
		words.Size = UDim2.new(1, 0, 0, textPx + 4)
		words.Position = UDim2.fromOffset(0, 1)
		words.ZIndex = 5
		if day.claimed then
			local check = HudParts.icon(tile, "Check", "Check")
			check.AnchorPoint = Vector2.new(0.5, 1)
			check.Position = UDim2.new(0.5, 0, 1, -1)
			check.Size = UDim2.fromOffset(round(dayPx * 0.55), round(dayPx * 0.55))
			check.ZIndex = 5
		end
		if day.today then
			UIAnim.glowBurst(tile, HudParts.tone("Gold"), 0.6)
		end
	end
	y += dayPx + 8
	-- The 28-day track.
	local trackDays = whole(if type(state) == "table" then state.trackDays else 0)
	local place = whole(if type(state) == "table" then state.trackPlace else 0)
	if trackDays > 0 then
		y += line(
			body,
			geo,
			"Track",
			W.Track:format(place, trackDays),
			y,
			HudParts.color(K.Numbers.Count)
		)
		local bar = RewardsParts.bar(body, "TrackBar", 4)
		bar.root.Position = UDim2.fromOffset(round(geo.width * 0.1), y)
		bar.root.Size = UDim2.fromOffset(round(geo.width * 0.8), P.TrackBarPx)
		RewardsParts.setBar(bar, place / trackDays, "Gold")
		y += P.TrackBarPx + 4
		for _, row in (if type(state.track) == "table" then state.track else {}) do
			if type(row) == "table" and row.reached ~= true then
				y += line(
					body,
					geo,
					"TrackNext",
					W.TrackNext:format(row.day, RewardPopups.words(row.reward)),
					y
				)
				break
			end
		end
	end
	-- The streak freeze.
	local freeze = if login.frozen == true
		then W.FreezeUsed
		elseif login.freezeReady == true then W.FreezeReady
		else W.FreezeGone
	line(body, geo, "Freeze", freeze, y)
end

local function showDaily(screen: ScreenGui, deps: any, payload: any, done: () -> ())
	-- The RewardState with today's claim in it may land a moment after RewardGiven.
	local deadline = os.clock() + P.StateWaitSeconds
	local state = ItemState.rewards()
	while os.clock() < deadline do
		local login = if type(state) == "table" then state.login else nil
		if type(login) == "table" and login.claimedToday == true then
			break
		end
		task.wait(0.1)
		state = ItemState.rewards()
	end
	local login = if type(state) == "table" and type(state.login) == "table"
		then state.login
		else {}
	local day = whole(login.day)
	card(screen, deps, {
		title = W.DailyTitle:format(math.max(1, day)),
		height = P.HeightPx,
		reward = payload.reward,
		build = function(body: Frame, geo: any)
			buildDaily(body, geo, payload.reward, state)
		end,
	}, done)
end

local function showPlaytime(screen: ScreenGui, deps: any, payload: any, done: () -> ())
	card(screen, deps, {
		title = W.PlaytimeTitle,
		height = P.PlaytimeHeightPx,
		reward = payload.reward,
		build = function(body: Frame, geo: any)
			local y = rewardRow(body, geo, payload.reward, 0) + 8
			line(body, geo, "Line", W.PlaytimeLine:format(Format.commas(whole(payload.minutes))), y)
		end,
	}, done)
end

--- Queue the popup for a RewardGiven payload.
function RewardPopups.push(screen: ScreenGui, deps: any, payload: any)
	if type(payload) ~= "table" or type(payload.reward) ~= "table" then
		return
	end
	count += 1
	local kind = payload.kind
	if kind == "Daily" then
		Popups.push({
			id = "DailyLogin",
			show = function(done)
				showDaily(screen, deps, payload, done)
			end,
		})
	elseif kind == "Playtime" then
		Popups.push({
			id = "Playtime" .. tostring(payload.index) .. "_" .. count,
			show = function(done)
				showPlaytime(screen, deps, payload, done)
			end,
		})
	end
end

--- Listen for RewardGiven. `deps`: Progression's shared table (money, flyer, column);
--- `screen` the HUD's ScreenGui.
function RewardPopups.start(screen: ScreenGui, deps: any)
	deps.rewardsFlyer = deps.rewardsFlyer or RewardsFlyer.new(screen, deps)
	Net.get("RewardGiven").OnClientEvent:Connect(function(payload: any)
		RewardPopups.push(screen, deps, payload)
	end)
	GuiQA.add("rewardPopup", function(kind: string?, width: number?, height: number?)
		if width and height then
			qaSize = Vector2.new(width, height)
		end
		local reward = { money = 5000, cases = {}, drops = 1, spins = 0, lucky = 0 }
		RewardPopups.push(
			screen,
			deps,
			{ kind = kind or "Daily", reward = reward, index = 2, minutes = 30 }
		)
		return true
	end)
end

return RewardPopups
