--!strict
-- PlayerList: our player list, flush in the top-right corner of Roblox's top bar row, where
-- Roblox's own list sits (GUI lane, designer 2026-10-03, C7, D9, D10, D11; restyled
-- 2026-10-07). Roblox's own list is switched off.
--
-- The Shop's lively card: the pale blue header band with its 8-balls scrolling ("Players (12)"
-- and a chevron; pressing it opens and folds the list) over the white sheet with the still
-- dots. It starts folded, and opens again on a join if the player left it open. One
-- list, no tabs (the global boards are the lobby signs): a "Wins" and "Money" titles row, then
-- everyone here, you first, then by rank: the rank badge, the username (never translated) with
-- their country flag if they turned it on (the CountryFlag attribute, Settings), wins vs
-- players and money. Disguised and tutorial bots are listed like people (their rank and money,
-- a fixed believable wins count for their tier, never a flag); pressing one does nothing. PC
-- robots are not listed. Pressing a real player opens a small card beside the list: Trade (a
-- trade invite, TradeRequest "Invite"), Add friend and View profile (Roblox's own prompts).
--
-- It stays clear of the Settings gear (`avoid`). Not shown on a phone for now (the HUD screen
-- under Multiplayer.Style.ShortHeight; designer 2026-10-07: it took too much of the screen).
-- Hidden in a match and under the popups (Progression). Gamepad: the D-pad's left in the hub
-- focuses the list (Progression.padRoute); B leaves it. Sizes in Config.UI.PlayerList.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local View = require(Shared:WaitForChild("Progression"):WaitForChild("PlayerListView"))
local GuiQA = require(script.Parent.GuiQA)
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local People = require(script.Parent.People)
local RankBadge = require(script.Parent.RankBadge)
local SettingsState = require(script.Parent.SettingsState)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local P = Config.UI.PlayerList
local R = Config.UI.Progress.RankHud -- the header matches the rank HUD's pill
local K = Config.UI.Kit
local S = Config.Multiplayer.Style
local W = Strings.PlayerList

local PlayerList = {}
PlayerList.__index = PlayerList

type RowView = {
	button: TextButton,
	badge: ImageLabel,
	name: TextLabel,
	flag: TextLabel,
	wins: TextLabel,
	money: TextLabel,
}

export type Options = {
	-- HUD pieces in the top row the list keeps clear of (the Settings gear and its word).
	avoid: { GuiObject }?,
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function num(x: any): number
	return if type(x) == "number" and x == x then x else 0
end

--- Build the list into the player's GUI (hidden until setVisible).
function PlayerList.new(screen: ScreenGui, opts: Options?): any
	local self: any = setmetatable({}, PlayerList)
	self.screen = screen
	self.avoid = if opts and opts.avoid then opts.avoid else {}
	self.showing = false
	self.rows = {} :: { RowView }
	self.data = {} :: { any }
	self.sizeTween = nil :: Tween?
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	-- Folded at first on every screen (designer 2026-10-07: less on screen); left open, it
	-- opens again on the next join (the hidden ListOpen setting).
	self.open = false
	self.touched = false -- the player opened or folded it this session
	local function fromSave()
		if self.touched or not SettingsState.loaded() then
			return
		end
		local saved = SettingsState.get("ListOpen")
		if saved ~= self.open then
			self.open = saved
			self:refresh()
			self:layout()
		end
		self.touched = true -- the save is read once; from now on the player's presses rule
	end
	SettingsState.Changed:Connect(fromSave)
	task.defer(fromSave)

	-- The free part of Roblox's top bar row: the list's header sits in it, at its right end.
	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerList"
	gui.ResetOnSpawn = false
	gui.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + 1
	gui.Enabled = false
	gui.Parent = screen.Parent
	self.gui = gui

	local panel = HudParts.menuCard(gui, "Panel", P.CornerPx)
	panel.AnchorPoint = Vector2.new(1, 0)
	self.panel = panel
	self.band = HudParts.livelyCard(panel)
	local sheet = (panel:FindFirstChild("Fill") :: Frame):FindFirstChild("Sheet") :: Frame
	local sheetCorner = sheet:FindFirstChildOfClass("UICorner")
	if sheetCorner then
		sheetCorner.CornerRadius = UDim.new(0, P.SheetCornerPx)
	end
	self.sheet = sheet

	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Text = ""
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.ZIndex = 4
	header.Parent = panel
	self.header = header
	local headerText = HudParts.text(header, "Words", R.NameTextPx, "")
	headerText.AutoLocalize = false
	headerText.TextWrapped = false
	headerText.TextXAlignment = Enum.TextXAlignment.Left
	headerText.ZIndex = 5
	self.headerText = headerText
	local chevron = HudParts.icon(header, "ChevronDown", "Chevron")
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.ZIndex = 5
	self.chevron = chevron
	header.Activated:Connect(function()
		UISound.play("Click")
		self.open = not self.open
		self.touched = true
		SettingsState.set("ListOpen", self.open)
		if not self.open then
			self.popout.Visible = false
		end
		self:refresh()
		self:layout(true)
	end)

	-- Under the header: the titles and the rows, clipped while the list opens or folds (the
	-- card itself is not clipped, so its ink outline and shadow stay whole).
	local body = HudParts.frame(panel, "Body")
	body.ClipsDescendants = true
	body.ZIndex = 3
	self.body = body
	-- The column titles, on the sheet's top.
	local columns = HudParts.frame(body, "Columns")
	columns.ZIndex = 4
	self.columns = columns
	local winsTitle = HudParts.note(columns, "Wins", P.ColumnsTextPx, W.WinsColumn)
	winsTitle.TextXAlignment = Enum.TextXAlignment.Right
	winsTitle.TextColor3 = HudParts.color(K.Numbers.Count)
	winsTitle.ZIndex = 4
	self.winsTitle = winsTitle
	local moneyTitle = HudParts.note(columns, "Money", P.ColumnsTextPx, W.MoneyColumn)
	moneyTitle.TextXAlignment = Enum.TextXAlignment.Right
	moneyTitle.TextColor3 = HudParts.color(K.Numbers.Count)
	moneyTitle.ZIndex = 4
	self.moneyTitle = moneyTitle

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 3
	scroll.Parent = body
	self.scroll = scroll
	-- A trade invite's answer, under the rows for a moment.
	local footer = HudParts.note(body, "Footer", P.ShortTextPx, "")
	footer.ZIndex = 4
	footer.Visible = false
	self.footer = footer

	-- The popout card beside the list (a real player's buttons).
	local pop = HudParts.card(gui, "Popout", 14)
	pop.AnchorPoint = Vector2.new(1, 0)
	pop.Visible = false
	self.popout = pop
	local popName = HudParts.text(pop, "Name", P.TextPx + 2, "")
	popName.AutoLocalize = false
	popName.Position = UDim2.fromOffset(8, 6)
	popName.Size = UDim2.new(1, -16, 0, P.TextPx + 8)
	popName.ZIndex = 4
	self.popName = popName
	self.popButtons = {}
	for index, key in { "Trade", "AddFriend", "Profile" } do
		local tone = if key == "Trade"
			then "Green"
			elseif key == "AddFriend" then "Blue"
			else "White"
		local button = HudParts.candy(pop, W[key], function()
			UISound.play("Click")
			self:popAction(key)
		end, tone)
		button.Name = key
		button.Size = UDim2.new(1, -16, 0, P.PopoutButtonPx)
		button.Position = UDim2.fromOffset(8, P.TextPx + 14 + (index - 1) * (P.PopoutButtonPx + 6))
		button.ZIndex = 5
		table.insert(self.popButtons, button)
	end
	pop.Size = UDim2.fromOffset(P.PopoutWidthPx, P.TextPx + 22 + 3 * (P.PopoutButtonPx + 6))

	-- Data in: players and bots.
	local function soon()
		self:queueRefresh()
	end
	Players.PlayerAdded:Connect(soon)
	Players.PlayerRemoving:Connect(soon)
	People.botAdded:Connect(soon)
	People.botRemoved:Connect(soon)
	-- Ranks, money and wins change often: a quiet refresh every second while open.
	task.spawn(function()
		while true do
			task.wait(1)
			if self.showing and self.open then
				self:refresh()
			end
		end
	end)
	local function relayout()
		self:layout()
	end
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	for _, object in self.avoid do
		object:GetPropertyChangedSignal("AbsolutePosition"):Connect(relayout)
		object:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)
	end
	-- Studio checks: open or fold it ("playerList", true/false) and pad it with `count` fake
	-- people ("playerListFake", count) to see a long list.
	GuiQA.add("playerList", function(open: boolean)
		self.open = open
		self:refresh()
		self:layout(true)
		return self.open
	end)
	GuiQA.add("playerListFake", function(count: number)
		self.fake = count
		self:refresh()
		self:layout()
		return #self.data
	end)
	self:refresh()
	self:layout()
	return self
end

function PlayerList.queueRefresh(self: any)
	if self.refreshQueued then
		return
	end
	self.refreshQueued = true
	task.defer(function()
		self.refreshQueued = false
		self:refresh()
		self:layout()
	end)
end

-- Everyone listed now, in order (you first, then by rank).
local function everyone(): { any }
	local me = Players.LocalPlayer
	local rows: { any } = {}
	for _, person in People.everyone() do
		local bot = typeof(person) ~= "Instance"
		local kind = person:GetAttribute("BotKind")
		if bot and kind == "Pc" then
			continue
		end
		local tier = person:GetAttribute("RankTier")
		local division = person:GetAttribute("RankDivision")
		local index = person:GetAttribute("RankIndex")
		local wins = if bot
			then View.botWins(if type(tier) == "string" then tier else "Bronze", person.UserId)
			else num(person:GetAttribute("WinsVsPlayers"))
		table.insert(rows, {
			id = person.UserId,
			name = if bot then (person:GetAttribute("DisplayName") or person.Name) else person.Name,
			rankIndex = num(index),
			wins = wins,
			you = person == me,
			bot = bot,
			tier = if type(tier) == "string" then tier else "Unranked",
			division = num(division),
			money = num(person:GetAttribute("Money")),
			flag = if bot then "" else View.flag(person:GetAttribute("CountryFlag")),
			player = if bot then nil else person,
		})
	end
	View.sort(rows :: any)
	return rows
end

local function rowView(self: any, index: number): RowView
	local found = self.rows[index]
	if found then
		return found
	end
	local button = Instance.new("TextButton")
	button.Name = "Row" .. index
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = HudParts.tone("White")
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.ZIndex = 3
	button.Parent = self.scroll
	HudParts.corner(button, P.RowCornerPx)
	local edge = Instance.new("UIStroke")
	edge.Name = "Edge"
	edge.Color = HudParts.color(P.RowEdge)
	edge.Thickness = P.RowStrokePx
	edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	edge.Parent = button
	local badge = Instance.new("ImageLabel")
	badge.Name = "Badge"
	badge.BackgroundTransparency = 1
	badge.ScaleType = Enum.ScaleType.Fit
	badge.ZIndex = 4
	badge.Parent = button
	local name = HudParts.note(button, "Name", P.TextPx, "")
	name.AutoLocalize = false
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextTruncate = Enum.TextTruncate.AtEnd
	name.TextWrapped = false
	name.ZIndex = 4
	-- The flag right after the name, never cut: a long name is shortened ("...") instead.
	local flag = Instance.new("TextLabel")
	flag.Name = "Flag"
	flag.BackgroundTransparency = 1
	flag.AutoLocalize = false
	flag.Font = name.Font
	flag.TextXAlignment = Enum.TextXAlignment.Left
	flag.ZIndex = 4
	flag.Parent = button
	local wins = HudParts.note(button, "Wins", P.TextPx, "")
	wins.AutoLocalize = false
	wins.TextXAlignment = Enum.TextXAlignment.Right
	wins.TextWrapped = false
	wins.ZIndex = 4
	local money = HudParts.text(button, "Money", P.TextPx, "", HudParts.color(K.Numbers.Money))
	money.AutoLocalize = false
	money.TextXAlignment = Enum.TextXAlignment.Right
	money.TextWrapped = false
	money.ZIndex = 4
	local made: RowView =
		{ button = button, badge = badge, name = name, flag = flag, wins = wins, money = money }
	self.rows[index] = made
	button.MouseEnter:Connect(function()
		self:shadeRow(index, true)
	end)
	button.MouseLeave:Connect(function()
		self:shadeRow(index, false)
	end)
	button.Activated:Connect(function()
		self:pressRow(index)
	end)
	return made
end

-- A row's box: white with a pale edge, pale blue for your own row, tinted under the mouse.
function PlayerList.shadeRow(self: any, index: number, hovered: boolean)
	local v = self.rows[index]
	local row = self.data[index]
	if not v then
		return
	end
	if row and row.you then
		v.button.BackgroundColor3 = HudParts.tone("Blue")
		v.button.BackgroundTransparency = if hovered
			then P.YouTransparency - 0.1
			else P.YouTransparency
	else
		v.button.BackgroundColor3 = if hovered
			then HudParts.color(P.RowHover)
			else HudParts.tone("White")
		v.button.BackgroundTransparency = 0
	end
end

-- Put a row's name and flag: the name as wide as its words (shortened when the room runs
-- out), the flag just after it.
function PlayerList.placeName(self: any, v: RowView)
	local geo = self.nameGeo
	if not geo then
		return
	end
	local px = geo.textPx
	local flagW = if v.flag.Text ~= ""
		then TextService:GetTextSize(v.flag.Text, px, v.flag.Font, Vector2.new(200, 100)).X + 4
		else 0
	local wide = TextService:GetTextSize(v.name.Text, px, v.name.Font, Vector2.new(1000, 100)).X
	local nameW = math.max(0, math.min(math.ceil(wide) + 2, geo.room - flagW))
	-- A fixed size (not scaled down to fit), so a long name ends in "..." at the row's size.
	v.name.TextScaled = false
	v.name.TextSize = px
	v.name.Position = UDim2.fromOffset(geo.x, 0)
	v.name.Size = UDim2.new(0, nameW, 1, 0)
	v.flag.TextSize = px
	v.flag.Position = UDim2.fromOffset(geo.x + nameW + 4, 0)
	v.flag.Size = UDim2.new(0, flagW, 1, 0)
end

--- Read the list again and redraw the rows.
function PlayerList.refresh(self: any)
	local people = everyone()
	for index = 1, self.fake or 0 do
		table.insert(people, {
			id = -index,
			-- Every other one as long as a username gets (20), in the widest letters or a
			-- typical mix, flagged.
			name = if index % 4 == 1
				then string.sub(string.rep("W", 18) .. index, 1, 20)
				elseif index % 4 == 3 then "TheRealPoolMaster209"
				else "Player" .. index,
			rankIndex = index,
			wins = index * 37,
			bot = true,
			tier = "Gold",
			division = 1 + index % 3,
			money = index * 123456,
			flag = if index % 2 == 1 then View.flag("US") else "",
		})
	end
	self.headerText.Text = W.Header:format(#people)
	self.data = people
	for index, row in people do
		local v = rowView(self, index)
		v.button.Visible = true
		v.badge.Image = if row.rankIndex > 0
			then RankBadge.image(row.tier, row.division)
			else RankBadge.image("Unranked", 0)
		v.name.Text = row.name
		v.flag.Text = row.flag
		self:placeName(v)
		v.name.TextColor3 = if row.you then HudParts.tone("Blue") else HudParts.tone("Ink")
		v.wins.Text = Format.commas(row.wins)
		v.money.Text = Format.moneyShort(row.money)
		self:shadeRow(index, false)
	end
	for index = #people + 1, #self.rows do
		self.rows[index].button.Visible = false
	end
end

-- The list's width: its full width, or narrower to keep clear of the gear on a narrow phone.
function PlayerList.fitWidth(self: any, full: number, right: number): number
	local limit = -math.huge
	for _, object in self.avoid do
		if object.AbsoluteSize.X > 0 then
			limit = math.max(limit, object.AbsolutePosition.X + object.AbsoluteSize.X)
		end
	end
	if limit == -math.huge then
		return full
	end
	return math.clamp(right - (limit + P.AvoidGapPx), P.MinWidthPx, full)
end

--- Place everything. `animate` tweens the panel open or folded (the header was pressed).
function PlayerList.layout(self: any, animate: boolean?)
	local size = self.screen.AbsoluteSize
	if size.Y > 0 then
		self.phone = size.Y < S.ShortHeight
		self.gui.Enabled = self.showing and not self.phone
	end
	local area = self.gui.AbsoluteSize
	if size.X <= 0 or area.X <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local function pick(computer: number, phone: number): number
		return if short then phone else computer
	end
	local headerH = pick(P.HeaderPx, P.ShortHeaderPx)
	local rowH = pick(P.RowPx, P.ShortRowPx)
	local columnsH = pick(P.ColumnsPx, P.ShortColumnsPx)
	local textPx = pick(P.TextPx, P.ShortTextPx)
	local badgePx = pick(P.BadgePx, P.ShortBadgePx)
	local winsW = pick(P.WinsColumnPx, P.ShortWinsColumnPx)
	local moneyW = pick(P.MoneyColumnPx, P.ShortMoneyColumnPx)
	local inset = K.SheetInsetPx

	-- The header in the top row, centred on Roblox's buttons and the rank HUD, at its right end.
	local origin = self.gui.AbsolutePosition
	local right = origin.X + area.X - P.RightPx
	local width = self:fitWidth(pick(P.WidthPx, P.ShortWidthPx), right)
	local top = if short
		then math.max(0, round((area.Y - headerH) / 2))
		else R.RowButtonTopPx + round((R.PillHeightPx - headerH) / 2)
	self.panel.Position = UDim2.new(1, -P.RightPx, 0, top)

	self.header.Size = UDim2.new(1, 0, 0, headerH)
	local chevronPx = pick(P.ChevronPx, P.ShortChevronPx)
	self.chevron.Size = UDim2.fromOffset(chevronPx, chevronPx)
	self.chevron.Position = UDim2.new(1, -10, 0.5, 0)
	self.chevron.Rotation = if self.open then 180 else 0
	HudParts.setTextSize(self.headerText, pick(R.NameTextPx, P.ShortTitlePx))
	self.headerText.Position = UDim2.fromOffset(P.TitleLeftPx, 0)
	self.headerText.Size = UDim2.new(1, -(chevronPx + P.TitleLeftPx * 2 + 4), 1, 0)

	-- The columns: the badge and name, then Wins and Money, right-aligned.
	local rowW = width - inset * 2 - 4
	-- In a box's own pixels (each box is 2 px in from the scroller and 4 px narrower).
	local moneyX = rowW - 4 - moneyW - 8
	local winsX = moneyX - winsW - 4
	self.body.Position = UDim2.fromOffset(0, headerH)
	self.body.Size = UDim2.new(1, 0, 1, -headerH)
	self.columns.Position = UDim2.fromOffset(inset + 2, 1)
	self.columns.Size = UDim2.fromOffset(rowW, columnsH)
	local columnsText = pick(P.ColumnsTextPx, P.ShortColumnsTextPx)
	HudParts.setTextSize(self.winsTitle, columnsText, columnsText)
	self.winsTitle.Position = UDim2.fromOffset(winsX + 2, 0)
	self.winsTitle.Size = UDim2.fromOffset(winsW, columnsH)
	HudParts.setTextSize(self.moneyTitle, columnsText, columnsText)
	self.moneyTitle.Position = UDim2.fromOffset(moneyX + 2, 0)
	self.moneyTitle.Size = UDim2.fromOffset(moneyW, columnsH)

	local count = #self.data
	local footerH = if self.footer.Visible then P.ShortTextPx + 8 else 0
	local listTop = headerH + 1 + columnsH
	local maxList = math.max(
		rowH * 2,
		math.min(
			round(rowH * pick(P.MaxRows, P.ShortMaxRows)),
			math.floor(size.Y * P.MaxHeightShare) - listTop - footerH
		)
	)
	local listH = math.min(maxList, count * rowH + 4)
	self.scroll.Position = UDim2.fromOffset(inset + 2, listTop - headerH)
	self.scroll.Size = UDim2.fromOffset(rowW + 4, listH)
	self.scroll.CanvasSize = UDim2.fromOffset(0, count * rowH + 4)
	self.footer.Position = UDim2.fromOffset(inset + 6, listTop - headerH + listH + 2)
	self.footer.Size = UDim2.fromOffset(rowW - 8, math.max(0, footerH - 4))
	HudParts.setTextSize(self.footer, P.ShortTextPx)

	local boxH = rowH - P.RowGapPx
	local b = math.min(badgePx, boxH - 2)
	-- The name's room: from after the badge to before the Wins column.
	self.nameGeo = { x = b + 10, room = winsX - b - 14, textPx = textPx }
	for index, v in self.rows do
		-- Inset a little so each box's edge shows whole inside the scroller.
		v.button.Position = UDim2.fromOffset(2, 2 + (index - 1) * rowH)
		v.button.Size = UDim2.fromOffset(rowW - 4, rowH - P.RowGapPx)
		v.badge.Size = UDim2.fromOffset(b, b)
		v.badge.Position = UDim2.fromOffset(5, round((boxH - b) / 2))
		HudParts.setTextSize(v.name, textPx)
		self:placeName(v)
		HudParts.setTextSize(v.wins, textPx)
		v.wins.Position = UDim2.fromOffset(winsX, 0)
		v.wins.Size = UDim2.new(0, winsW, 1, 0)
		HudParts.setTextSize(v.money, textPx)
		v.money.Position = UDim2.fromOffset(moneyX, 0)
		v.money.Size = UDim2.new(0, moneyW, 1, 0)
	end

	-- Open: the header, the titles and the rows on the sheet; folded: the header band alone.
	local openH = listTop + listH + footerH + inset
	local height = if self.open then openH else headerH
	HudParts.setSheetTop(self.panel, headerH)
	-- The header's 8-balls fill the whole card (its own round corners clip them), so the folded
	-- header is the band alone; the sheet covers the rest when open.
	self.band.Size = UDim2.fromScale(1, 1)
	local target = UDim2.fromOffset(width, height)
	if self.sizeTween then
		self.sizeTween:Cancel()
		self.sizeTween = nil
	end
	local function settle()
		self.sheet.Visible = self.open
		self.body.Visible = self.open
	end
	if animate and self.panel.Size ~= target and not UIAnim.reduced() then
		self.sheet.Visible, self.body.Visible = true, true
		local tween = TweenService:Create(
			self.panel,
			TweenInfo.new(P.ToggleSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = target }
		)
		self.sizeTween = tween
		tween.Completed:Connect(function(state)
			if state == Enum.PlaybackState.Completed then
				settle()
			end
		end)
		tween:Play()
	else
		self.panel.Size = target
		settle()
	end
	if self.popout.Visible then
		self.popout.Position = UDim2.new(1, -P.RightPx - width - P.PopoutGapPx, 0, top)
	end
end

-- A row was pressed: a real player (not you) opens the popout; a bot or you, nothing.
function PlayerList.pressRow(self: any, index: number)
	local row = self.data[index]
	if not row or row.bot or row.you or not row.player then
		self.popout.Visible = false
		return
	end
	UISound.play("Click")
	self.popPlayer = row.player
	self.popName.Text = row.name
	self.popout.Visible = true
	self:layout()
	UIAnim.popIn(self.popout)
	if string.sub(UserInputService:GetLastInputType().Name, 1, 7) == "Gamepad" then
		GuiService.SelectedObject = self.popButtons[1]
	end
end

function PlayerList.popAction(self: any, key: string)
	local player: Player? = self.popPlayer
	self.popout.Visible = false
	if not player or player.Parent ~= Players then
		return
	end
	if key == "Trade" then
		task.spawn(function()
			local reply = ItemState.request("TradeRequest", "Invite", player.UserId)
			local ok = type(reply) == "table" and reply.ok == true
			self.footer.Text = if ok then W.TradeSent else tostring(reply and reply.reason or "")
			self.footer.Visible = true
			self:layout()
			local token = {}
			self.footerToken = token
			task.delay(P.FooterSeconds, function()
				if self.footerToken == token then
					self.footer.Visible = false
					self:layout()
				end
			end)
		end)
	elseif key == "AddFriend" then
		pcall(function()
			StarterGui:SetCore("PromptSendFriendRequest", player)
		end)
	else
		pcall(function()
			GuiService:InspectPlayerFromUserId(player.UserId)
		end)
	end
end

--- Show or hide it (Progression: hidden in a match and under the popups).
function PlayerList.setVisible(self: any, visible: boolean)
	if self.showing == visible then
		return
	end
	self.showing = visible
	self.gui.Enabled = visible and not self.phone
	if not visible then
		self.popout.Visible = false
	else
		self:refresh()
		self:layout()
	end
end

--- The D-pad's left: open the list and put the selection on its first row. False when the
--- list is not on screen (a phone).
function PlayerList.focus(self: any): boolean
	if not self.showing or self.phone then
		return false
	end
	if not self.open then
		self.open = true
		self.touched = true
		SettingsState.set("ListOpen", true)
		self:refresh()
		self:layout(true)
	end
	local first = self.rows[1]
	GuiService.SelectedObject = if first and first.button.Visible then first.button else self.header
	return true
end

return PlayerList
