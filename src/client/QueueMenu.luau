--!strict
-- QueueMenu: the host's card, floating over the middle of their table while it waits
-- (designer, 2026-09-27: one card, on the table; everyone else, guests on the pad included,
-- sees the table's sign there instead, TableSign). Two views:
--   - Settings: who hosts and how many are on the pad of how many it holds, the three
--     difficulty tiles (each with the money it pays), the abilities toggle (a placeholder
--     until abilities exist) and Start. There is no Leave: walking off the pad leaves.
--   - Waiting, once Start is pressed on a pad that is not full (the table is "ready"): the
--     settings shown, not changed, "Waiting for players..." (or "Starting in 3" once the pad
--     fills; the server starts it, MatchEngine.startsAt), Back to the settings, and alone on
--     a 1v1 table "Waiting for opponent..." with Request opponent (everyone free in the
--     server gets a popup to join, OpponentPrompt), Play against PC (a placeholder until bots
--     exist) and Play solo.
-- It shows only what the table's snapshot says; every press is a request the server checks
-- (MatchEngine.action).
--
-- Built from the UI kit (HudParts). It pops in when you step onto an empty pad (Main shows
-- it the moment you do, before the server has seated you) and out when you leave; Start
-- breathes. It is a screen card placed each frame where the table is on screen, kept on
-- screen and clear of the touch jump button, so touch targets and gamepad selection work the
-- same everywhere.
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
local Placement = require(Shared:WaitForChild("Placement"))
local Engine = require(Shared:WaitForChild("Rules"):WaitForChild("MatchEngine"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match.Queue
local M = Config.Multiplayer
local S = M.Style
local K = Config.UI.Kit
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
	height: number,
	action: () -> ()
): TextButton
	local object = HudParts.candy(parent, text, action, look, icon)
	object.Name = name
	object.LayoutOrder = order
	object.Size = UDim2.new(1, 0, 0, height)
	return object
end

function QueueMenu.new(screen: ScreenGui, onAction: (string, any?) -> ()): any
	local self: any = setmetatable({}, QueueMenu)
	self.onAction = onAction
	self.snapshot = nil
	-- No LocalPlayer only in an Edit-mode preview of the screens.
	self.localUserId = if Players.LocalPlayer then Players.LocalPlayer.UserId else 0
	self.sentAt = -math.huge -- a Start or Play solo on its way to the server
	self.requestedAt = -math.huge -- this host's last Request opponent, before the server's answer
	self.wanted = nil -- the host's last pick, shown until the server's snapshot agrees
	self.now = 0
	self.open = false
	self.pulse = nil -- Start breathing while it can be pressed

	-- The holder is fitted to the screen (its UIScale); the card inside pops in and out.
	local root = HudParts.frame(screen, "QueueMenu")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
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
	-- One column of rows, kept short so it fits a phone on its side at a readable size.
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.QueueRowGap)
	list.Parent = content
	self.list = list

	-- Who hosts (a crown by their name), and how many are in.
	local host = row(content, "Host", S.QueueHostRowHeight, 1)
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

	-- Settings. Difficulty: three tiles, each a picture of the lines you get over its name and
	-- the money it pays (designer, 2026-09-27: inside the tile), the chosen one blue.
	local levels = row(content, "Levels", S.QueueLevelHeight, 2)
	local levelList = Instance.new("UIListLayout")
	levelList.FillDirection = Enum.FillDirection.Horizontal
	levelList.SortOrder = Enum.SortOrder.LayoutOrder
	levelList.Padding = UDim.new(0, S.HeaderGap)
	levelList.Parent = levels
	self.levelRow = levels
	self.levels = {}
	local order = Config.Difficulty.Order
	for i, level in order do
		local money =
			Copy.MoneyMultiplier:format(tostring(Config.Difficulty.MoneyMultiplier[level]))
		local b = HudParts.tile(levels, Copy.Levels[level], function()
			self:choose("SetDifficulty", level)
		end, "White", level, "Money", money)
		b.Name = level
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / #order, -S.HeaderGap * (#order - 1) / #order, 1, 0)
		-- A long name shrinks inside its tile rather than spilling over the next one.
		HudParts.setButtonTextSize(b, K.Text.Min, S.QueueTileTextFloor)
		self.levels[level] = b
	end
	self.levelInfo = line(content, "LevelInfo", K.Text.Min, 3)

	-- Abilities: an ON/OFF toggle.
	local abilities = row(content, "Abilities", S.QueueAbilitiesHeight, 4)
	self.abilitiesRow = abilities
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

	-- Start takes the whole last row (designer, 2026-09-27: no Leave; walk off to leave).
	self.start = button(
		content,
		"Start",
		Copy.Start,
		5,
		"Green",
		"Play",
		S.QueueStartHeight,
		function()
			self:pressStart()
		end
	)

	-- Waiting. The settings as the sign shows them: the difficulty's picture and name, and
	-- abilities ON or OFF.
	local summary = row(content, "Summary", S.QueueSummaryHeight, 6)
	self.summary = summary
	local iconSize = S.QueueSummaryHeight
	self.summaryLevel = HudParts.icon(summary, "Classic", "LevelIcon")
	self.summaryLevel.Size = UDim2.fromOffset(iconSize, iconSize)
	self.summaryName = HudParts.text(summary, "Level", K.Text.Body, "")
	self.summaryName.TextXAlignment = Enum.TextXAlignment.Left
	self.summaryName.Position = UDim2.fromOffset(iconSize + 4, 0)
	self.summaryName.Size = UDim2.new(1, -iconSize * 2 - S.QueueToggleWidth - 12, 1, 0)
	local summaryBolt = HudParts.icon(summary, "Lightning")
	summaryBolt.AnchorPoint = Vector2.new(1, 0.5)
	summaryBolt.Position = UDim2.new(1, -S.QueueToggleWidth - 4, 0.5, 0)
	summaryBolt.Size = UDim2.fromOffset(iconSize - 4, iconSize - 4)
	self.summaryAbilities = HudParts.pill(summary, "Abilities")
	self.summaryAbilities.AnchorPoint = Vector2.new(1, 0.5)
	self.summaryAbilities.Position = UDim2.fromScale(1, 0.5)
	self.summaryAbilities.Size = UDim2.fromOffset(S.QueueToggleWidth, S.QueuePillHeight)
	self.summaryAbilitiesText = HudParts.text(self.summaryAbilities, "Text", K.Text.Min, "")
	self.summaryAbilitiesText.Position = UDim2.fromOffset(4, 1)
	self.summaryAbilitiesText.Size = UDim2.new(1, -8, 1, -2)

	-- Waiting for players, or starting in 3.
	self.status = HudParts.text(content, "Status", K.Text.Heading, "")
	self.status.TextWrapped = false
	self.status.Size = UDim2.new(1, 0, 0, K.Text.Heading + S.QueueMenuLineGap)
	self.status.LayoutOrder = 7

	-- Alone on a 1v1 table: ask the server for an opponent, or play by yourself, against the
	-- PC or solo. Bots come before release (Roadmap 2.4); until then Play against PC does
	-- nothing.
	self.request = button(
		content,
		"RequestOpponent",
		Copy.RequestOpponent,
		8,
		"Yellow",
		"People",
		S.ButtonHeight,
		function()
			if self:canRequest() then
				self.requestedAt = self.now
				self.onAction("RequestOpponent", nil)
			end
		end
	)
	self.pc = button(
		content,
		"PlayPC",
		Copy.PlayPC,
		9,
		"Blue",
		"Robot",
		S.ButtonHeight,
		function() end
	)
	self.solo = button(
		content,
		"PlaySolo",
		Copy.PlaySolo,
		10,
		"Green",
		"Person",
		S.ButtonHeight,
		function()
			if self:canSend() and self:alone() then
				self.sentAt = self.now
				self.onAction("StartSolo", nil)
			end
		end
	)
	-- Back to the settings.
	self.back = button(
		content,
		"Back",
		Copy.Back,
		11,
		"White",
		"Sliders",
		S.ButtonHeight,
		function()
			if self:isHost() then
				self.wanted = { key = "ready", value = false, at = self.now }
				self.onAction("Unready", nil)
				self:refocusLater()
			end
		end
	)

	self.hint = line(content, "GamepadHint", K.Text.Min, 12)
	self.hint.Text = Copy.GamepadHint
	self.hint.TextXAlignment = Enum.TextXAlignment.Center
	return self
end

-- The table's settings as shown, `ready` among them: the host's own pick at once, until the
-- server's snapshot agrees or it has had its time to answer.
function QueueMenu.shown(self: any): any
	local snapshot = self.snapshot
	if not snapshot then
		return nil
	end
	local settings = table.clone(snapshot.settings or {})
	settings.ready = snapshot.ready == true
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

--- The host alone on a 1v1 table: waiting offers Play solo and Play against PC. The team
--- tables are kept for team games (designer, 2026-09-26).
function QueueMenu.alone(self: any): boolean
	return self.snapshot ~= nil
		and self:isHost()
		and self:count() == 1
		and self.snapshot.teamSize == 1
end

function QueueMenu.canSend(self: any): boolean
	return self.now - self.sentAt >= M.ActionRetrySeconds
end

--- Whether Request opponent may be pressed: alone, and not asked within the cooldown (the
--- server's record or this card's own press, whichever is later).
function QueueMenu.canRequest(self: any): boolean
	local last =
		math.max(self.requestedAt, self.snapshot and self.snapshot.requestedAt or -math.huge)
	return self:alone() and self.now - last >= M.Queue.RequestCooldownSeconds
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

-- The view is about to change under a gamepad's selection: let go now and put it on the new
-- view's first button once that is laid out. A touch or mouse press takes no selection.
function QueueMenu.refocusLater(self: any)
	if GuiService.SelectedObject then
		GuiService.SelectedObject = nil
		self.refocus = true
	end
end

-- Start: a full pad starts at once (the card goes while the server answers); otherwise the
-- card turns to waiting and the server starts the game once the pad fills.
function QueueMenu.pressStart(self: any)
	if not self:isHost() or not self:canSend() then
		return
	end
	if Engine.startState(self.snapshot.seats, self.snapshot.teamSize) then
		self.sentAt = self.now -- hidden until the server answers
	else
		self.wanted = { key = "ready", value = true, at = self.now }
		self:refocusLater()
	end
	self.onAction("Start", nil)
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
--- that table waits and the player hosts it.
function QueueMenu.setSnapshot(self: any, snapshot: any?, userId: number)
	if snapshot and snapshot.phase ~= "Waiting" then
		snapshot = nil
	end
	local old = self.snapshot
	self.snapshot = snapshot
	self.localUserId = userId
	if not snapshot or not old or old.epoch ~= snapshot.epoch or old.id ~= snapshot.id then
		self.wanted, self.sentAt, self.requestedAt = nil, -math.huge, -math.huge
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
	for _, object in { self.start, self.request, self.solo, self.back, self.levels.Classic } do
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

-- Roblox's jump button on a touch screen, if it is showing: the card keeps out of its way.
local function jumpButton(): GuiObject?
	local player = Players.LocalPlayer
	local gui = player and player:FindFirstChildOfClass("PlayerGui")
	local touch = gui and gui:FindFirstChild("TouchGui")
	local jump = touch and touch:FindFirstChild("JumpButton", true)
	if jump and jump:IsA("GuiObject") and jump.Visible and jump.AbsoluteSize.X > 0 then
		return jump
	end
	return nil
end

-- Float the card over the middle of the table (Config.UI.Sign.LiftStuds, the sign's spot):
-- centred where that point is on screen, shrunk to fit short screens, and kept inside the
-- screen's margins and out of the touch jump button's corner.
function QueueMenu.layout(self: any)
	local screen: any = self.root.Parent
	local camera = workspace.CurrentCamera
	local placement = self.snapshot and Placement.forTable(self.snapshot.id)
	if not screen or not camera or not placement then
		return
	end
	local size: Vector2 = screen.AbsoluteSize
	local margin = S.HeaderMargin
	local natural = self.list.AbsoluteContentSize.Y / self.scale.Scale + 2 * S.QueueMenuPadding
	self.root.Size = UDim2.fromOffset(S.QueueMenuWidth, natural)
	local scale = math.clamp((size.Y - 2 * margin) / math.max(natural, 1), S.QueueMenuMinScale, 1)
	self.scale.Scale = scale
	local halfW, halfH = S.QueueMenuWidth * scale / 2, natural * scale / 2

	local world = Vector3.new(Placement.overTable(placement, Config.UI.Sign.LiftStuds))
	local point, _ = camera:WorldToScreenPoint(world)
	local x, y = point.X - screen.AbsolutePosition.X, point.Y - screen.AbsolutePosition.Y
	if point.Z <= 0 then
		-- Behind the camera: hold it in the middle rather than mirrored.
		x, y = size.X / 2, size.Y / 2
	end
	local right = size.X - margin
	local jump = jumpButton()
	if jump then
		-- Keep left of the jump button when the card would reach down beside it.
		local jumpTop = jump.AbsolutePosition.Y - screen.AbsolutePosition.Y
		local jumpLeft = jump.AbsolutePosition.X - screen.AbsolutePosition.X
		if math.clamp(y, margin + halfH, size.Y - margin - halfH) + halfH > jumpTop then
			right = math.min(right, jumpLeft - margin)
		end
	end
	x = math.clamp(x, margin + halfW, math.max(margin + halfW, right - halfW))
	y = math.clamp(y, margin + halfH, math.max(margin + halfH, size.Y - margin - halfH))
	self.root.Position = UDim2.fromOffset(math.floor(x + 0.5), math.floor(y + 0.5))
end

--- Redraw from the snapshot. Called every frame while seated; only writes what changed
--- matters to Roblox, and nothing here is expensive.
function QueueMenu.update(self: any, now: number)
	self.now = now
	local snapshot = self.snapshot
	local host = snapshot ~= nil and self:isHost()
	self:setOpen(host)
	if not host then
		return
	end
	local count = self:count()
	local settings = self:shown()
	local hostName = ""
	for _, seat in snapshot.seats do
		if seat.connected ~= false and seat.userId == snapshot.hostId then
			hostName = seat.displayName or seat.name
		end
	end
	self.hostName.Text = hostName
	self.players.Text = Copy.PlayerCount:format(count, snapshot.teamSize * 2)
	local ready = settings.ready == true
	local sending = not self:canSend()

	-- Settings.
	self.levelRow.Visible = not ready
	self.levelInfo.Visible = not ready
	self.abilitiesRow.Visible = not ready
	self.start.Visible = not ready and not sending
	for level, b in self.levels do
		HudParts.setTone(b, if settings.difficulty == level then "Blue" else "White")
	end
	self.levelInfo.Text = Copy.LevelInfo[settings.difficulty] or ""
	HudParts.setText(self.abilities, if settings.abilities then Copy.On else Copy.Off)
	HudParts.setTone(self.abilities, if settings.abilities then "Green" else "Grey")
	-- Start breathes while it is there to be pressed.
	local breathe = self.start.Visible
	if breathe and not self.pulse then
		self.pulse = UIAnim.pulse(self.start)
	elseif not breathe and self.pulse then
		self.pulse.stop()
		self.pulse = nil
	end

	-- Waiting.
	local solo = ready and self:alone()
	self.summary.Visible = ready
	self.status.Visible = ready
	self.back.Visible = ready and not sending
	self.request.Visible = solo and not sending
	self.pc.Visible = solo and not sending
	self.solo.Visible = solo and not sending
	local canRequest = self:canRequest()
	HudParts.setEnabled(self.request, canRequest)
	HudParts.setText(self.request, if canRequest then Copy.RequestOpponent else Copy.Requested)
	HudParts.setIcon(self.summaryLevel, settings.difficulty)
	self.summaryName.Text = Copy.Levels[settings.difficulty] or ""
	self.summaryAbilitiesText.Text = if settings.abilities then Copy.On else Copy.Off
	self.summaryAbilities.BackgroundColor3 =
		HudParts.tone(if settings.abilities then "Green" else "Grey")
	self.status.Text = if snapshot.startsAt
		then Copy.StartingIn:format(math.max(1, math.ceil(snapshot.startsAt - now)))
		elseif snapshot.teamSize == 1 then Copy.WaitingForOpponent
		else Copy.WaitingForPlayers

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
	elseif self.refocus then
		self.refocus = false
		self:focus()
	end
	self:layout()
end

return QueueMenu
