--!strict
-- QueueMenu: the card everyone in a table's queue box sees while the table waits (designer,
-- 2026-09-25). It shows who hosts, how many are in, the difficulty and abilities the host
-- picked, and why the game cannot start yet. Only the host can change anything: the
-- difficulty, the abilities toggle (a placeholder until abilities exist), and Start, which
-- offers Play solo or Play against PC (a placeholder until bots exist) to a host alone.
-- Everyone gets Leave. It shows only what the table's snapshot says; every press is a
-- request the server checks (MatchEngine.action).
--
-- Built from the UI kit (HudParts): a white card with a crown by the host's name, three
-- difficulty tiles with aim-line pictures, and candy buttons. It pops in when you step into
-- a box and out when you leave; Start breathes once it can be pressed.
--
-- Gamepad: selection is never taken while the player can walk (the stick would stop moving
-- them). Y focuses the card (QueueMenu.focus), B leaves it again (Main).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Engine = require(Shared:WaitForChild("Rules"):WaitForChild("MatchEngine"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match.Queue
local M = Config.Multiplayer
local S = M.Style
local K = Config.UI.Kit
local tone = HudParts.tone
local QueueMenu = {}
QueueMenu.__index = QueueMenu

-- A row of the card: a frame of fixed height that the list lays out top to bottom.
local function row(parent: Instance, name: string, height: number, order: number): Frame
	local object = HudParts.frame(parent, name)
	object.Size = UDim2.new(1, 0, 0, height)
	object.LayoutOrder = order
	return object
end

-- A line of small dark text across the card (HudParts.note); `lines` rows at most, the box
-- growing to fit.
local function line(
	parent: Instance,
	name: string,
	size: number,
	order: number,
	lines: number?
): TextLabel
	local object = HudParts.note(parent, name, size, "")
	object.Size = UDim2.new(1, 0, 0, size + S.QueueMenuLineGap)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.LayoutOrder = order
	if (lines or 1) > 1 then
		-- A sentence keeps its size and the box grows to its lines (a translation may be
		-- longer; docs/UI_STYLE.md section 3).
		object.TextScaled = false
		object.TextWrapped = true
		object.AutomaticSize = Enum.AutomaticSize.Y
	else
		object.TextWrapped = false
	end
	return object
end

local function button(
	parent: Instance,
	name: string,
	text: string,
	order: number,
	look: string,
	icon: string?,
	action: () -> ()
): TextButton
	local object = HudParts.candy(parent, text, action, look, icon)
	object.Name = name
	object.LayoutOrder = order
	object.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	return object
end

function QueueMenu.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, QueueMenu)
	self.onAction = onAction
	self.snapshot = nil
	-- No LocalPlayer only in an Edit-mode preview of the screens.
	self.localUserId = if Players.LocalPlayer then Players.LocalPlayer.UserId else 0
	self.soloOpen = false -- the host pressed Start alone: Play solo / Play against PC
	self.sentAt = -math.huge -- a Start or Play solo on its way to the server
	self.wanted = nil -- the host's last pick, shown until the server's snapshot agrees
	self.now = 0
	self.open = false
	self.pulse = nil -- Start breathing while it can be pressed

	-- The holder is fitted to the screen (its UIScale); the card inside pops in and out.
	local root = HudParts.frame(screen, "QueueMenu")
	root.AnchorPoint = Vector2.new(1, 0)
	root.Size = UDim2.fromOffset(S.QueueMenuWidth, 0)
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	local card = HudParts.card(root, "Card")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	self.card = card
	local content = HudParts.frame(card, "Content")
	content.Position = UDim2.fromOffset(S.QueueMenuPadding, S.QueueMenuPadding)
	content.Size = UDim2.new(1, -S.QueueMenuPadding * 2, 1, -S.QueueMenuPadding * 2)
	self.content = content
	-- Two columns: stacked one over the other on a tall screen, side by side on a phone on its
	-- side, so the card is big enough to read and still fits the screen (designer, 2026-09-26).
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.HeaderGap)
	list.Parent = content
	self.list = list
	self.wide = false
	local function column(name: string, order: number): Frame
		local object = HudParts.frame(content, name)
		object.Size = UDim2.fromScale(1, 0)
		object.AutomaticSize = Enum.AutomaticSize.Y
		object.LayoutOrder = order
		local rows = Instance.new("UIListLayout")
		rows.SortOrder = Enum.SortOrder.LayoutOrder
		rows.Padding = UDim.new(0, S.HeaderGap)
		rows.Parent = object
		return object
	end
	-- The table and its settings on the left, what to do about them on the right.
	local left = column("Settings", 1)
	local right = column("Actions", 2)
	self.columns = { left, right }

	-- Who hosts (a crown by their name), and how many are in.
	local host = row(left, "Host", S.QueueHostRowHeight, 1)
	local crown = HudParts.icon(host, "Crown")
	crown.Size = UDim2.fromOffset(S.QueueHostRowHeight, S.QueueHostRowHeight)
	local nameLeft = S.QueueHostRowHeight + 6
	local countWidth = S.QueueCountWidth
	self.hostTitle = HudParts.note(host, "HostTitle", K.Text.Min, Copy.HostTitle)
	self.hostTitle.TextXAlignment = Enum.TextXAlignment.Left
	self.hostTitle.Position = UDim2.fromOffset(nameLeft, 0)
	self.hostTitle.Size = UDim2.new(1, -nameLeft - countWidth - 6, 0, K.Text.Min + 1)
	self.hostName = HudParts.text(host, "HostName", S.QueueHostSize, "")
	self.hostName.AutoLocalize = false -- player names are never translated
	self.hostName.TextScaled = false
	self.hostName.TextWrapped = false
	self.hostName.TextTruncate = Enum.TextTruncate.AtEnd
	self.hostName.TextXAlignment = Enum.TextXAlignment.Left
	self.hostName.Position = UDim2.fromOffset(nameLeft, K.Text.Min)
	self.hostName.Size =
		UDim2.new(1, -nameLeft - countWidth - 6, 0, S.QueueHostRowHeight - K.Text.Min)
	local count = HudParts.pill(host, "Count")
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.fromScale(1, 0.5)
	count.Size = UDim2.fromOffset(countWidth, S.QueuePillHeight)
	local people = HudParts.icon(count, "People")
	people.Position = UDim2.fromOffset(4, 2)
	people.Size = UDim2.fromOffset(S.QueuePillHeight - 4, S.QueuePillHeight - 4)
	self.players = HudParts.text(count, "Players", K.Text.Body, "")
	self.players.AutoLocalize = false -- only numbers
	self.players.Position = UDim2.fromOffset(S.QueuePillHeight, 1)
	self.players.Size = UDim2.new(1, -S.QueuePillHeight - 6, 1, -2)

	-- Four or six split into the box's halves: green with a check once they are even.
	self.split = HudParts.pill(left, "TeamSplit")
	self.split.Size = UDim2.new(1, 0, 0, S.QueuePillHeight)
	self.split.LayoutOrder = 2
	self.splitCheck = HudParts.icon(self.split, "Check")
	self.splitCheck.Position = UDim2.fromOffset(6, 2)
	self.splitCheck.Size = UDim2.fromOffset(S.QueuePillHeight - 4, S.QueuePillHeight - 4)
	self.splitText = HudParts.text(self.split, "Text", K.Text.Body, "")
	self.splitText.Position = UDim2.fromOffset(S.QueuePillHeight + 4, 1)
	self.splitText.Size = UDim2.new(1, -S.QueuePillHeight * 2 - 8, 1, -2)

	-- Difficulty: three tiles, each a picture of the lines you get, the chosen one blue.
	self.levelTitle = line(left, "DifficultyTitle", K.Text.Min, 3)
	self.levelTitle.Text = Copy.DifficultyTitle
	local levels = row(left, "Levels", S.QueueLevelHeight, 4)
	local levelList = Instance.new("UIListLayout")
	levelList.FillDirection = Enum.FillDirection.Horizontal
	levelList.SortOrder = Enum.SortOrder.LayoutOrder
	levelList.Padding = UDim.new(0, S.HeaderGap)
	levelList.Parent = levels
	self.levels = {}
	local order = Config.Difficulty.Order
	for i, level in order do
		local b = HudParts.tile(levels, Copy.Levels[level], function()
			self:choose("SetDifficulty", level)
		end, "White", level)
		b.Name = level
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #order, -S.HeaderGap * (#order - 1) / #order, 1, 0)
		-- A long name shrinks inside its tile rather than spilling over the next one.
		HudParts.setButtonTextSize(b, K.Text.Min, S.QueueTileTextFloor)
		self.levels[level] = b
	end
	self.levelInfo = line(left, "LevelInfo", K.Text.Min, 5, 2)

	-- Abilities: an ON/OFF toggle.
	local abilities = row(right, "Abilities", S.ButtonHeight, 1)
	local bolt = HudParts.icon(abilities, "Lightning")
	bolt.AnchorPoint = Vector2.new(0, 0.5)
	bolt.Position = UDim2.fromScale(0, 0.5)
	bolt.Size = UDim2.fromOffset(S.QueueHostRowHeight - 4, S.QueueHostRowHeight - 4)
	local abilitiesTitle = HudParts.text(abilities, "Title", K.Text.Body, Copy.AbilitiesTitle)
	abilitiesTitle.TextXAlignment = Enum.TextXAlignment.Left
	abilitiesTitle.Position = UDim2.fromOffset(S.QueueHostRowHeight + 2, 0)
	abilitiesTitle.Size = UDim2.new(1, -S.QueueHostRowHeight - S.QueueToggleWidth - 8, 1, 0)
	self.abilities = HudParts.candy(abilities, Copy.On, function()
		local shown = self:shown()
		if shown then
			self:choose("SetAbilities", not shown.abilities)
		end
	end, "Green")
	self.abilities.Name = "Toggle"
	self.abilities.AnchorPoint = Vector2.new(1, 0)
	self.abilities.Position = UDim2.fromScale(1, 0)
	self.abilities.Size = UDim2.new(0, S.QueueToggleWidth, 1, 0)

	-- Why the game cannot start, or whose turn it is to start it.
	self.status = line(right, "Status", K.Text.Min, 2, 2)

	-- The host's Start, or, alone, the two ways to play by themselves: against the PC first.
	self.start = button(right, "Start", Copy.Start, 3, "Green", "Play", function()
		self:pressStart()
	end)
	self.start.Size = UDim2.new(1, 0, 0, S.QueueStartHeight)
	-- Bots come before release (Roadmap 2.4); until then this button does nothing.
	self.pc = button(right, "PlayPC", Copy.PlayPC, 4, "Blue", "Robot", function() end)
	self.solo = button(right, "PlaySolo", Copy.PlaySolo, 5, "Green", "Person", function()
		if self:canSend() and self:alone() then
			self.sentAt = self.now
			self.onAction("StartSolo", nil)
		end
	end)
	self.back = button(right, "Back", Copy.Back, 6, "White", nil, function()
		self.soloOpen = false
		self:focus()
	end)
	self.leave = button(right, "Leave", Copy.Leave, 7, "Red", "Door", function()
		self.onAction("LeaveQueue", nil)
	end)
	self.hint = line(right, "GamepadHint", K.Text.Min, 8)
	self.hint.Text = Copy.GamepadHint
	self.hint.TextXAlignment = Enum.TextXAlignment.Center
	return self
end

-- The table's settings as shown: the host's own pick at once, until the server's
-- snapshot agrees or it has had its time to answer.
function QueueMenu.shown(self: any): any
	local snapshot = self.snapshot
	if not snapshot then
		return nil
	end
	local settings = table.clone(snapshot.settings or {})
	local wanted = self.wanted
	if wanted and self.now - wanted.at < M.ActionRetrySeconds then
		settings[wanted.key] = wanted.value
	end
	return settings
end

function QueueMenu.isHost(self: any): boolean
	return self.snapshot ~= nil and self.snapshot.hostId == self.localUserId
end

function QueueMenu.count(self: any): number
	local n = 0
	for _, seat in self.snapshot.seats do
		if seat.connected ~= false then
			n += 1
		end
	end
	return n
end

function QueueMenu.alone(self: any): boolean
	return self.snapshot ~= nil and self:isHost() and self:count() == 1
end

function QueueMenu.canSend(self: any): boolean
	return self.now - self.sentAt >= M.ActionRetrySeconds
end

function QueueMenu.choose(self: any, kind: string, value: any)
	if not self:isHost() then
		return
	end
	self.wanted = {
		key = if kind == "SetDifficulty" then "difficulty" else "abilities",
		value = value,
		at = self.now,
	}
	self.onAction(kind, value)
end

function QueueMenu.pressStart(self: any)
	if not self:isHost() or not self:canSend() then
		return
	end
	if self:alone() then
		self.soloOpen = true
		GuiService.SelectedObject = if GuiService.SelectedObject then self.solo else nil
		return
	end
	if Engine.startState(self.snapshot.seats) then
		self.sentAt = self.now -- hidden until the server answers
		self.onAction("Start", nil)
	end
end

-- Show or hide the card, popping it in or out.
function QueueMenu.setOpen(self: any, open: boolean)
	if open == self.open then
		return
	end
	self.open = open
	if open then
		self.root.Visible = true
		self.card.Visible = false
		UIAnim.popIn(self.card)
	else
		if self.pulse then
			self.pulse.stop()
			self.pulse = nil
		end
		UIAnim.popOut(self.card, function()
			if not self.open then
				self.root.Visible = false
			end
		end)
	end
end

--- The table snapshot the local player is seated at, or nil. The card shows only while
--- that table waits for its host.
function QueueMenu.setSnapshot(self: any, snapshot: any?, userId: number)
	if snapshot and snapshot.phase ~= "Waiting" then
		snapshot = nil
	end
	local old = self.snapshot
	self.snapshot = snapshot
	self.localUserId = userId
	if not snapshot or not old or old.epoch ~= snapshot.epoch then
		self.soloOpen, self.wanted, self.sentAt = false, nil, -math.huge
	end
	if not snapshot then
		self:blur()
		self:setOpen(false)
	end
end

--- Whether a gamepad is on the card now.
function QueueMenu.focused(self: any): boolean
	local selected = GuiService.SelectedObject
	return selected ~= nil and selected:IsDescendantOf(self.root)
end

--- Put the gamepad on the card: the first control there is to press.
function QueueMenu.focus(self: any)
	if not self.root.Visible then
		return
	end
	for _, object in { self.start, self.solo, self.levels.Classic, self.leave } do
		if object.Visible and object.Selectable then
			GuiService.SelectedObject = object
			return
		end
	end
end

--- Take the gamepad off the card, so the stick walks again.
function QueueMenu.blur(self: any)
	if self:focused() then
		GuiService.SelectedObject = nil
	end
end

-- Keep the card on screen, under the top bar on the right. On a short screen (a phone on its
-- side) its two columns sit side by side, so it is wide and short: big enough to read, clear
-- of the jump button below it. On a tall touch screen it stays left of the jump button.
function QueueMenu.layout(self: any)
	local screen: any = self.root.Parent
	if not screen then
		return
	end
	local size: Vector2 = screen.AbsoluteSize
	local margin = S.HeaderMargin
	local wide = size.Y < S.ShortHeight
	if wide ~= self.wide then
		self.wide = wide
		self.list.FillDirection = if wide
			then Enum.FillDirection.Horizontal
			else Enum.FillDirection.Vertical
		for _, column in self.columns do
			column.Size = if wide
				then UDim2.fromOffset(S.QueueWideColumn, 0)
				else UDim2.fromScale(1, 0)
		end
	end
	local width = if wide
		then S.QueueWideColumn * 2 + S.HeaderGap + 2 * S.QueueMenuPadding
		else S.QueueMenuWidth
	local right = if UserInputService.TouchEnabled and not wide then S.QueueTouchRight else margin
	local natural = self.list.AbsoluteContentSize.Y / self.scale.Scale + 2 * S.QueueMenuPadding
	self.root.Size = UDim2.fromOffset(width, natural)
	local room = math.max(1, size.Y - 2 * margin)
	self.scale.Scale = math.clamp(room / math.max(natural, 1), S.QueueMenuMinScale, 1)
	self.root.Position = UDim2.new(1, -right, 0, margin)
end

--- Redraw from the snapshot. Called every frame while seated; only writes what changed
--- matters to Roblox, and nothing here is expensive.
function QueueMenu.update(self: any, now: number)
	self.now = now
	local snapshot = self.snapshot
	self:setOpen(snapshot ~= nil)
	if not snapshot then
		return
	end
	local host = self:isHost()
	local count = self:count()
	local settings = self:shown()
	local hostName = ""
	local inHalf = { 0, 0 }
	for _, seat in snapshot.seats do
		if seat.connected ~= false then
			if seat.userId == snapshot.hostId then
				hostName = seat.displayName or seat.name
			end
			if seat.side == 1 or seat.side == 2 then
				inHalf[seat.side] += 1
			end
		end
	end
	if count ~= 1 then
		self.soloOpen = false
	end
	local ok, reason = Engine.startState(snapshot.seats)
	self.hostName.Text = hostName
	self.players.Text = Copy.PlayerCount:format(count, M.Queue.Capacity)
	local halves = count == 4 or count == 6
	self.split.Visible = halves
	self.splitText.Text = Copy.TeamSplit:format(inHalf[1], inHalf[2])
	self.split.BackgroundColor3 = if ok then tone("Green") else tone("Grey")
	self.splitCheck.Visible = ok == true

	for level, b in self.levels do
		local chosen = settings.difficulty == level
		HudParts.setTone(b, if chosen then "Blue" else "White")
		-- A guest sees the host's choice at full strength and the others faded.
		HudParts.setEnabled(b, host, not host and not chosen)
	end
	self.levelInfo.Text = Copy.LevelInfo[settings.difficulty] or ""
	HudParts.setEnabled(self.abilities, host, false)
	HudParts.setText(self.abilities, if settings.abilities then Copy.On else Copy.Off)
	HudParts.setTone(self.abilities, if settings.abilities then "Green" else "Grey")

	local sending = not self:canSend()
	local solo = host and self.soloOpen
	self.start.Visible = host and not solo and not sending
	self.solo.Visible = solo and not sending
	self.pc.Visible = solo and not sending
	self.back.Visible = solo and not sending
	local startable = count == 1 or ok
	HudParts.setEnabled(self.start, startable)
	HudParts.setTone(self.start, if startable then "Green" else "Grey")
	-- Start breathes while it is there to be pressed.
	local breathe = self.start.Visible and startable
	if breathe and not self.pulse then
		self.pulse = UIAnim.pulse(self.start)
	elseif not breathe and self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end

	self.status.Text = if not host
		then Copy.WaitingForHost:format(hostName)
		elseif solo then ""
		elseif count == 1 then Copy.AloneHint
		elseif reason then Copy.Reasons[reason] or ""
		else ""
	self.status.Visible = self.status.Text ~= ""

	local gamepad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	self.hint.Visible = gamepad and not self:focused()
	-- A selection left on a control that just hid or dimmed would keep the stick off the
	-- character: move it to what is there now, or let go.
	local selected = GuiService.SelectedObject
	if
		selected
		and selected:IsDescendantOf(self.root)
		and not ((selected :: GuiObject).Visible and (selected :: GuiObject).Selectable)
	then
		GuiService.SelectedObject = nil
		self:focus()
	end
	self:layout()
end

return QueueMenu
