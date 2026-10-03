--!strict
-- PlayerList: our player list, top right (GUI lane, designer 2026-10-03, C7, D9, D10, D11).
-- Roblox's own list is switched off. A header ("Players (12)") opens and closes it (open on a
-- computer, closed on a phone at first). Three tabs:
-- - Players: everyone here, you first, then by rank: the rank badge, the username (never
--   translated) with their country flag if they turned it on (the CountryFlag attribute,
--   Settings), wins vs players and money. Disguised and tutorial bots are listed like people
--   (their rank and money, a fixed believable wins count for their tier, never a flag);
--   pressing one does nothing. PC robots are not listed. Pressing a real player opens a small
--   card beside the list: Trade (a trade invite, TradeRequest "Invite"), Add friend and View
--   profile (Roblox's own prompts).
-- - Top Wins and Top Rank: the global boards (Leaderboards remote), top 50, and your place
--   (or "Not on the board yet").
-- Hidden in a match and under the popups (Progression). Gamepad: the D-pad's left in the hub
-- focuses the list (Progression.padRoute); B leaves it. Sizes in Config.UI.PlayerList.
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Strings = require(Shared:WaitForChild("Strings"))
local Format = require(Shared:WaitForChild("Progression"):WaitForChild("Format"))
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local View = require(Shared:WaitForChild("Progression"):WaitForChild("PlayerListView"))
local HudParts = require(script.Parent.HudParts)
local ItemState = require(script.Parent.ItemState)
local People = require(script.Parent.People)
local RankBadge = require(script.Parent.RankBadge)
local UIAnim = require(script.Parent.UIAnim)
local UISound = require(script.Parent.UISound)

local P = Config.UI.PlayerList
local K = Config.UI.Kit
local S = Config.Multiplayer.Style
local W = Strings.PlayerList
local TABS = { "Players", "Wins", "Rank" }

local PlayerList = {}
PlayerList.__index = PlayerList

type RowView = {
	button: TextButton,
	badge: ImageLabel,
	name: TextLabel,
	sub: TextLabel,
	money: TextLabel,
}

local function round(n: number): number
	return math.floor(n + 0.5)
end

local function num(x: any): number
	return if type(x) == "number" and x == x then x else 0
end

--- Build the list into the player's GUI (hidden until setVisible).
function PlayerList.new(screen: ScreenGui): any
	local self: any = setmetatable({}, PlayerList)
	self.screen = screen
	self.tab = "Players"
	self.wanted = false
	self.showing = false
	self.rows = {} :: { RowView }
	self.boards = {} :: { [string]: any }
	self.data = {} :: { any }
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)

	local gui = Instance.new("ScreenGui")
	gui.Name = "PlayerList"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = screen.DisplayOrder + 1
	gui.Enabled = false
	gui.Parent = screen.Parent
	self.gui = gui
	local short = screen.AbsoluteSize.Y > 0 and screen.AbsoluteSize.Y < S.ShortHeight
	self.open = not short

	local panel = HudParts.card(gui, "Panel", 14)
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.ClipsDescendants = true
	self.panel = panel
	local header = Instance.new("TextButton")
	header.Name = "Header"
	header.Text = ""
	header.BackgroundTransparency = 1
	header.AutoButtonColor = false
	header.ZIndex = 4
	header.Parent = panel
	self.header = header
	local headerText = HudParts.text(header, "Words", P.TextPx + 2, "")
	headerText.AutoLocalize = false
	headerText.TextXAlignment = Enum.TextXAlignment.Left
	headerText.Position = UDim2.fromOffset(12, 0)
	headerText.Size = UDim2.new(1, -44, 1, 0)
	headerText.ZIndex = 5
	self.headerText = headerText
	local chevron = HudParts.icon(header, "ChevronDown", "Chevron")
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -10, 0.5, 0)
	chevron.Size = UDim2.fromOffset(22, 22)
	chevron.ZIndex = 5
	self.chevron = chevron
	header.Activated:Connect(function()
		UISound.play("Click")
		self.open = not self.open
		self:layout()
	end)

	-- The tabs.
	local tabs = HudParts.frame(panel, "Tabs")
	tabs.ZIndex = 4
	self.tabsFrame = tabs
	self.tabButtons = {}
	for index, key in TABS do
		local button = HudParts.candy(tabs, W.Tabs[key], function()
			self.tab = key
			self:refresh()
			self:layout()
		end, "White")
		button.Name = key
		button.LayoutOrder = index
		self.tabButtons[key] = button
	end

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Rows"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.CanvasSize = UDim2.new()
	scroll.ZIndex = 3
	scroll.Parent = panel
	self.scroll = scroll
	local footer = HudParts.note(panel, "Footer", P.ShortTextPx, "")
	footer.ZIndex = 4
	self.footer = footer

	-- The popout card beside the list (a real player's buttons).
	local pop = HudParts.popupCard(gui, "Popout", 14)
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

	-- Data in: players, bots, attributes, the boards.
	local function soon()
		self:queueRefresh()
	end
	Players.PlayerAdded:Connect(soon)
	Players.PlayerRemoving:Connect(soon)
	People.botAdded:Connect(soon)
	People.botRemoved:Connect(soon)
	task.spawn(function()
		local ok, remote = pcall(Net.get, "Leaderboards")
		if ok and remote then
			(remote :: RemoteEvent).OnClientEvent:Connect(function(payload: any)
				if type(payload) == "table" and type(payload.boards) == "table" then
					self.boards = payload.boards
					if self.tab ~= "Players" then
						self:queueRefresh()
					end
				end
			end)
		end
	end)
	-- Ranks, money and wins change often: a quiet refresh every second while open.
	task.spawn(function()
		while true do
			task.wait(1)
			if self.showing and self.open and self.tab == "Players" then
				self:refresh()
			end
		end
	end)
	screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:layout()
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
	HudParts.corner(button, 8)
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
	local sub = HudParts.note(button, "Sub", P.ShortTextPx - 2, "")
	sub.AutoLocalize = false
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = HudParts.color(K.Numbers.Count)
	sub.ZIndex = 4
	local money = HudParts.text(button, "Money", P.ShortTextPx, "", HudParts.color(K.Numbers.Money))
	money.AutoLocalize = false
	money.TextXAlignment = Enum.TextXAlignment.Right
	money.TextWrapped = false
	money.ZIndex = 4
	local made: RowView = { button = button, badge = badge, name = name, sub = sub, money = money }
	self.rows[index] = made
	button.MouseEnter:Connect(function()
		button.BackgroundTransparency = 0.6
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundTransparency = 1
	end)
	button.Activated:Connect(function()
		self:pressRow(index)
	end)
	return made
end

--- Read the list (or the board) again and redraw the rows.
function PlayerList.refresh(self: any)
	local me = Players.LocalPlayer
	local people = everyone()
	self.headerText.Text = W.Header:format(#people)
	local data: { any } = {}
	local footer = ""
	if self.tab == "Players" then
		data = people
	else
		local board = self.boards[self.tab]
		local place: number? = nil
		for i, entry in (if type(board) == "table" then board else {}) do
			if type(entry) == "table" then
				local value = num(entry.value)
				local isMe = me ~= nil and entry.userId == me.UserId
				if isMe then
					place = i
				end
				table.insert(data, {
					place = i,
					name = tostring(entry.name),
					value = value,
					you = isMe,
				})
			end
		end
		footer = if type(board) ~= "table"
			then W.Loading
			elseif place then W.YourPlace:format(place)
			else W.NotPlaced
	end
	self.data = data
	self.footer.Text = footer
	for index, row in data do
		local v = rowView(self, index)
		v.button.Visible = true
		if self.tab == "Players" then
			v.badge.Visible = true
			v.badge.Image = if row.rankIndex > 0
				then RankBadge.image(row.tier, row.division)
				else RankBadge.image("Unranked", 0)
			local flag = if row.flag ~= "" then " " .. row.flag else ""
			v.name.Text = (if row.you then W.You .. ": " else "") .. row.name .. flag
			v.sub.Text = W.Wins:format(Format.commas(row.wins))
			v.money.Text = Format.money(row.money)
		else
			v.badge.Visible = false
			v.name.Text = ("#%d  %s"):format(row.place, row.name)
			v.sub.Text = if self.tab == "Rank"
				then Ranks.name(Ranks.fromXp(row.value, true))
				else W.Wins:format(Format.commas(row.value))
			v.money.Text = ""
		end
		v.name.TextColor3 = if row.you then HudParts.tone("Blue") else HudParts.tone("Ink")
	end
	for index = #data + 1, #self.rows do
		self.rows[index].button.Visible = false
	end
end

function PlayerList.layout(self: any)
	local size = self.screen.AbsoluteSize
	if size.X <= 0 then
		return
	end
	local short = size.Y < S.ShortHeight
	local width = if short then P.ShortWidthPx else P.WidthPx
	local rowH = if short then P.ShortRowPx else P.RowPx
	local headerH = P.HeaderPx
	self.panel.Position = UDim2.new(1, -P.RightPx, 0, P.TopGapPx)
	self.header.Size = UDim2.new(1, 0, 0, headerH)
	self.chevron.Rotation = if self.open then 180 else 0
	local tabsH = if self.open then 34 else 0
	self.tabsFrame.Visible = self.open
	self.tabsFrame.Position = UDim2.fromOffset(6, headerH)
	self.tabsFrame.Size = UDim2.new(1, -12, 0, tabsH)
	local tabW = math.floor((width - 12 - 2 * 4) / #TABS)
	for index, key in TABS do
		local b = self.tabButtons[key]
		b.Size = UDim2.fromOffset(tabW, tabsH - 4)
		b.Position = UDim2.fromOffset((index - 1) * (tabW + 4), 2)
		HudParts.setButtonTextSize(b, if short then 11 else 13)
		HudParts.setTone(b, if key == self.tab then "Blue" else "White")
	end
	local count = #self.data
	local footerH = if self.open and self.tab ~= "Players" then P.ShortTextPx + 10 else 0
	local maxList = math.max(
		rowH * 2,
		math.floor(size.Y * (if short then P.ShortMaxHeightShare else P.MaxHeightShare))
			- headerH
			- tabsH
			- footerH
	)
	local listH = if self.open then math.min(maxList, count * rowH + 4) else 0
	self.scroll.Visible = self.open
	self.scroll.Position = UDim2.fromOffset(4, headerH + tabsH)
	self.scroll.Size = UDim2.new(1, -8, 0, listH)
	self.scroll.CanvasSize = UDim2.fromOffset(0, count * rowH + 4)
	self.footer.Visible = footerH > 0
	self.footer.Position = UDim2.fromOffset(8, headerH + tabsH + listH + 2)
	self.footer.Size = UDim2.new(1, -16, 0, footerH - 4)
	HudParts.setTextSize(self.footer, P.ShortTextPx)
	self.panel.Size = UDim2.fromOffset(width, headerH + tabsH + listH + footerH + 4)
	local textPx = if short then P.ShortTextPx else P.TextPx
	local badgePx = math.min(P.BadgePx, rowH - 6)
	for index, v in self.rows do
		local y = (index - 1) * rowH
		v.button.Position = UDim2.fromOffset(0, y)
		v.button.Size = UDim2.new(1, -8, 0, rowH - 2)
		v.badge.Size = UDim2.fromOffset(badgePx, badgePx)
		v.badge.Position = UDim2.fromOffset(4, round((rowH - 2 - badgePx) / 2))
		local x = if v.badge.Visible then badgePx + 10 else 8
		HudParts.setTextSize(v.name, textPx)
		v.name.Position = UDim2.fromOffset(x, 1)
		v.name.Size = UDim2.new(0.66, -x, 0, textPx + 4)
		HudParts.setTextSize(v.sub, textPx - 3)
		v.sub.Position = UDim2.fromOffset(x, textPx + 3)
		v.sub.Size = UDim2.new(0.66, -x, 0, textPx)
		HudParts.setTextSize(v.money, textPx)
		v.money.Position = UDim2.fromScale(0.66, 0)
		v.money.Size = UDim2.new(0.34, -6, 1, 0)
	end
	if self.popout.Visible then
		self.popout.Position = UDim2.new(1, -P.RightPx - width - 8, 0, P.TopGapPx)
	end
end

-- A row was pressed: a real player (not you) opens the popout; a bot or you, nothing.
function PlayerList.pressRow(self: any, index: number)
	if self.tab ~= "Players" then
		return
	end
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
			self.footer.Visible = true
			self.footer.Text = if ok then W.TradeSent else tostring(reply and reply.reason or "")
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
	self.gui.Enabled = visible
	if not visible then
		self.popout.Visible = false
	else
		self:refresh()
		self:layout()
	end
end

--- The D-pad's left: open the list and put the selection on its first row.
function PlayerList.focus(self: any)
	if not self.showing then
		return
	end
	if not self.open then
		self.open = true
		self:refresh()
		self:layout()
	end
	local first = self.rows[1]
	GuiService.SelectedObject = if first and first.button.Visible then first.button else self.header
end

return PlayerList
