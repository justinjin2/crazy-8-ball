--!strict
-- QueueMenu: the card everyone in a table's queue box sees while the table waits (designer,
-- 2026-09-25). It shows who hosts, how many are in, the difficulty and abilities the host
-- picked, and why the game cannot start yet. Only the host can change anything: the
-- difficulty, the abilities toggle (a placeholder until abilities exist), and Start, which
-- offers Play solo or Play against PC (a placeholder until bots exist) to a host alone.
-- Everyone gets Leave. It shows only what the table's snapshot says; every press is a
-- request the server checks (MatchEngine.action).
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
local Copy = Strings.Match.Queue
local M = Config.Multiplayer
local S = M.Style
local color = HudParts.color
local label = HudParts.label
local button = HudParts.button
local QueueMenu = {}
QueueMenu.__index = QueueMenu

-- A row of the card: a frame of fixed height that the list lays out top to bottom.
local function row(parent: Instance, name: string, height: number, order: number): Frame
	local object = HudParts.frame(parent, name)
	object.Size = UDim2.new(1, 0, 0, height)
	object.LayoutOrder = order
	return object
end

local function line(parent: Instance, name: string, size: number, order: number): TextLabel
	local object = label(parent, name, size, "")
	object.Size = UDim2.new(1, 0, 0, size + S.QueueMenuLineGap)
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.LayoutOrder = order
	return object
end

-- A button that also knows whether it may be pressed: a dimmed one stays on screen (the
-- others in the box see the host's choices) but does nothing and cannot be selected.
local function setEnabled(object: TextButton, enabled: boolean)
	object.Active = enabled
	object.Selectable = enabled
	object.AutoButtonColor = false
	object.TextTransparency = if enabled then 0 else S.QueueDisabledText
end

function QueueMenu.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, QueueMenu)
	self.onAction = onAction
	self.snapshot = nil
	self.localUserId = Players.LocalPlayer.UserId
	self.soloOpen = false -- the host pressed Start alone: Play solo / Play against PC
	self.sentAt = -math.huge -- a Start or Play solo on its way to the server
	self.noticeUntil = -math.huge -- "Coming soon" after Play against PC
	self.wanted = nil -- the host's last pick, shown until the server's snapshot agrees
	self.now = 0

	local root = HudParts.panel(screen, "QueueMenu")
	root.AnchorPoint = Vector2.new(1, 0)
	root.Size = UDim2.fromOffset(S.QueueMenuWidth, 0)
	root.AutomaticSize = Enum.AutomaticSize.Y
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	local padding = Instance.new("UIPadding")
	local pad = UDim.new(0, S.QueueMenuPadding)
	padding.PaddingTop, padding.PaddingBottom, padding.PaddingLeft, padding.PaddingRight =
		pad, pad, pad, pad
	padding.Parent = root
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.HeaderGap)
	list.Parent = root
	self.list = list

	-- Who hosts, and who is in.
	self.hostTitle = line(root, "HostTitle", S.NameSize, 1)
	self.hostTitle.Text = Copy.HostTitle
	self.hostTitle.TextColor3 = color(S.Muted)
	self.hostName = line(root, "HostName", S.QueueHostSize, 2)
	self.hostName.Font = Enum.Font.GothamBold
	self.players = line(root, "Players", S.StatusSize, 3)
	self.split = line(root, "TeamSplit", S.StatusSize, 4)
	self.split.Font = Enum.Font.GothamBold

	-- Difficulty: three segments, the chosen one lit.
	self.levelTitle = line(root, "DifficultyTitle", S.NameSize, 5)
	self.levelTitle.Text = Copy.DifficultyTitle
	self.levelTitle.TextColor3 = color(S.Muted)
	local levels = row(root, "Levels", S.QueueLevelHeight, 6)
	local levelList = Instance.new("UIListLayout")
	levelList.FillDirection = Enum.FillDirection.Horizontal
	levelList.SortOrder = Enum.SortOrder.LayoutOrder
	levelList.Padding = UDim.new(0, S.HeaderGap / 2)
	levelList.Parent = levels
	self.levels = {}
	local order = Config.Difficulty.Order
	for i, level in order do
		local b = button(levels, Copy.Levels[level], function()
			self:choose("SetDifficulty", level)
		end)
		b.Name = level
		b.LayoutOrder = i
		b.TextSize = S.NameSize + 1
		b.Size = UDim2.new(1 / #order, -S.HeaderGap / 2, 1, 0)
		self.levels[level] = b
	end
	self.levelInfo = line(root, "LevelInfo", S.NameSize, 7)
	self.levelInfo.TextColor3 = color(S.Muted)

	-- Abilities: an ON/OFF toggle, and a note that they are not in the game yet.
	local abilities = row(root, "Abilities", S.QueueLevelHeight, 8)
	local abilitiesTitle = label(abilities, "Title", S.NameSize, Copy.AbilitiesTitle)
	abilitiesTitle.TextColor3 = color(S.Muted)
	abilitiesTitle.TextXAlignment = Enum.TextXAlignment.Left
	abilitiesTitle.Size = UDim2.fromScale(0.6, 1)
	self.abilities = button(abilities, Copy.On, function()
		local shown = self:shown()
		if shown then
			self:choose("SetAbilities", not shown.abilities)
		end
	end)
	self.abilities.Name = "Toggle"
	self.abilities.AnchorPoint = Vector2.new(1, 0)
	self.abilities.Position = UDim2.fromScale(1, 0)
	self.abilities.Size = UDim2.new(0, S.QueueToggleWidth, 1, 0)
	self.abilitiesNote = line(root, "AbilitiesNote", S.NameSize, 9)
	self.abilitiesNote.Text = Copy.AbilitiesNote
	self.abilitiesNote.TextColor3 = color(S.Muted)

	-- Why the game cannot start, whose turn it is to start it, or "Coming soon".
	self.status = line(root, "Status", S.NameSize, 10)
	self.status.TextWrapped = true
	self.status.TextTruncate = Enum.TextTruncate.None
	self.status.Size = UDim2.new(1, 0, 0, (S.NameSize + S.QueueMenuLineGap) * 2)

	-- The host's Start, or, alone, the two ways to play by themselves.
	self.start = button(root, Copy.Start, function()
		self:pressStart()
	end)
	self.start.Name = "Start"
	self.start.LayoutOrder = 11
	self.start.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	self.solo = button(root, Copy.PlaySolo, function()
		if self:canSend() and self:alone() then
			self.sentAt = self.now
			self.onAction("StartSolo", nil)
		end
	end)
	self.solo.Name = "PlaySolo"
	self.solo.LayoutOrder = 12
	self.solo.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	self.pc = button(root, Copy.PlayPC, function()
		self.noticeUntil = self.now + S.QueueNoticeSeconds
	end)
	self.pc.Name = "PlayPC"
	self.pc.LayoutOrder = 13
	self.pc.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	local soon = label(self.pc, "Soon", S.NameSize - 2, Copy.Soon)
	soon.Font = Enum.Font.GothamBold
	soon.BackgroundTransparency = 0
	soon.BackgroundColor3 = color(S.Gold)
	soon.TextColor3 = color(S.Panel)
	soon.AnchorPoint = Vector2.new(1, 0.5)
	soon.Position = UDim2.new(1, -S.HeaderGap, 0.5, 0)
	soon.Size = UDim2.fromOffset(S.QueueSoonWidth, S.NameSize + 4)
	HudParts.corner(soon, S.Radius / 3)
	self.back = button(root, Copy.Back, function()
		self.soloOpen = false
		self:focus()
	end)
	self.back.Name = "Back"
	self.back.LayoutOrder = 14
	self.back.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	self.leave = button(root, Copy.Leave, function()
		self.onAction("LeaveQueue", nil)
	end)
	self.leave.Name = "Leave"
	self.leave.LayoutOrder = 15
	self.leave.Size = UDim2.new(1, 0, 0, S.ButtonHeight)
	self.leave.BackgroundColor3 = color(S.Panel)
	self.hint = line(root, "GamepadHint", S.NameSize, 16)
	self.hint.Text = Copy.GamepadHint
	self.hint.TextColor3 = color(S.Muted)
	self.hint.TextXAlignment = Enum.TextXAlignment.Center

	self.solo.BackgroundColor3 = color(S.Active)
	self.solo.TextColor3 = color(S.Panel)
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
		self.root.Visible = false
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

-- Keep the card on screen: under the top bar on the right, shrunk to fit short screens, and
-- on touch screens moved left of the jump button rather than squeezed above it.
function QueueMenu.layout(self: any)
	local screen: any = self.root.Parent
	if not screen then
		return
	end
	local size: Vector2 = screen.AbsoluteSize
	local margin = S.HeaderMargin
	local right = if UserInputService.TouchEnabled then S.QueueTouchRight else margin
	local natural = (self.list.AbsoluteContentSize.Y + 2 * S.QueueMenuPadding) / self.scale.Scale
	local room = math.max(1, size.Y - 2 * margin)
	self.scale.Scale = math.clamp(room / math.max(natural, 1), S.QueueMenuMinScale, 1)
	self.root.Position = UDim2.new(1, -right, 0, margin)
end

--- Redraw from the snapshot. Called every frame while seated; only writes what changed
--- matters to Roblox, and nothing here is expensive.
function QueueMenu.update(self: any, now: number)
	self.now = now
	local snapshot = self.snapshot
	self.root.Visible = snapshot ~= nil
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
	self.players.Text = Copy.Players:format(count, M.Queue.Capacity)
	local halves = count == 4 or count == 6
	self.split.Visible = halves
	self.split.Text = Copy.TeamSplit:format(inHalf[1], inHalf[2])
	self.split.TextColor3 = color(if ok then S.Green else S.Muted)

	for level, b in self.levels do
		local chosen = settings.difficulty == level
		setEnabled(b, host)
		b.BackgroundColor3 = color(if chosen then S.Selected else S.PanelTop)
		if chosen then
			b.TextTransparency = 0
		end
	end
	self.levelInfo.Text = Copy.LevelInfo[settings.difficulty] or ""
	setEnabled(self.abilities, host)
	self.abilities.Text = if settings.abilities then Copy.On else Copy.Off
	self.abilities.BackgroundColor3 = color(if settings.abilities then S.Active else S.PanelTop)
	self.abilities.TextColor3 = color(if settings.abilities then S.Panel else S.Text)

	local sending = not self:canSend()
	local solo = host and self.soloOpen
	self.start.Visible = host and not solo and not sending
	self.solo.Visible = solo and not sending
	self.pc.Visible = solo and not sending
	self.back.Visible = solo and not sending
	local startable = count == 1 or ok
	setEnabled(self.start, startable)
	self.start.BackgroundColor3 = color(if startable then S.Active else S.Disabled)
	self.start.TextColor3 = color(if startable then S.Panel else S.Text)

	local notice = now < self.noticeUntil
	self.status.TextColor3 = color(if notice then S.Gold else S.Muted)
	self.status.Text = if notice
		then Copy.ComingSoon
		elseif not host then Copy.WaitingForHost:format(hostName)
		elseif solo then Copy.SoloHint
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
