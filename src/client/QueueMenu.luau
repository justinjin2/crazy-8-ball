--!strict
-- QueueMenu: the host's card while their table waits (designer, 2026-09-27: no settings and
-- no Start, just play). It says what the game is ("Classic 1v1"), how many are on the pad
-- of how many it holds, and "Waiting for opponent..." (or players), or "Starting in 3" once
-- the pad is full: the server starts it by itself (MatchEngine.startsAt). While the pad has
-- room the host may Request opponent (Request players on the team tables): everyone free in
-- the server gets a popup to join (OpponentPrompt). Alone on a 1v1 table there are also Play
-- against PC (a placeholder until bots exist) and Play solo. Guests on the pad see the sign
-- over it instead (TableSign). Walking off the pad leaves.
--
-- Once the host requests, the card folds up to the game and "Requested!" (the waiting line
-- and Play against PC and Play solo slide away) and unfolds again if nobody came within
-- Queue.RequestSeconds (designer, 2026-09-27).
--
-- Every press is a request the server checks (MatchEngine.action). Built from the UI kit
-- (HudParts): it pops in the moment you step onto an empty pad (Main shows it before the
-- server has seated you). It keeps small: tucked into the top right corner on a phone-sized
-- screen, clear of the touch jump button, and on the right, halfway down, on a big one.
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
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match.Queue
local M = Config.Multiplayer
local S = M.Style
local K = Config.UI.Kit
local QueueMenu = {}
QueueMenu.__index = QueueMenu

-- A part of the card that folds away: a CanvasGroup whose height and fade follow `amount`
-- (0 folded, 1 open), clipping the rows inside as it closes.
local function fold(parent: Instance, name: string, order: number): any
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.LayoutOrder = order
	group.Size = UDim2.fromScale(1, 0)
	group.Parent = parent
	local inner = HudParts.frame(group, "Inner")
	inner.Size = UDim2.fromScale(1, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.QueueRowGap)
	list.Parent = inner
	-- Room above and below for the buttons' outlines and lips, which the group would clip.
	local edge = Instance.new("UIPadding")
	edge.PaddingTop = UDim.new(0, S.QueueFoldEdgePx)
	edge.PaddingBottom = UDim.new(0, S.QueueFoldEdgePx)
	edge.Parent = inner
	return { group = group, inner = inner, list = list, amount = 0 }
end

local function button(
	parent: Instance,
	name: string,
	text: string,
	order: number,
	look: string,
	icon: string,
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
	self.sentAt = -math.huge -- a Play solo on its way to the server
	self.requestedAt = -math.huge -- this host's last request, before the server's answer
	self.now = 0
	self.open = false
	self.snap = true -- the folds jump to where they belong the next frame (on opening)

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
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.QueueRowGap)
	list.Parent = content
	self.list = list

	-- The game: the difficulty's picture and "Classic 1v1", and how many are in.
	local title = HudParts.frame(content, "Title")
	title.Size = UDim2.new(1, 0, 0, S.QueueTitleHeight)
	title.LayoutOrder = 1
	local iconSize = S.QueueTitleHeight
	self.level = HudParts.icon(title, Config.Difficulty.Default, "LevelIcon")
	self.level.Size = UDim2.fromOffset(iconSize, iconSize)
	self.game = HudParts.text(title, "Game", K.Text.Heading, "")
	self.game.TextWrapped = false
	self.game.TextXAlignment = Enum.TextXAlignment.Left
	self.game.Position = UDim2.fromOffset(iconSize + 6, 0)
	self.game.Size = UDim2.new(1, -iconSize - S.QueueCountWidth - 12, 1, 0)
	local count = HudParts.pill(title, "Count")
	count.AnchorPoint = Vector2.new(1, 0.5)
	count.Position = UDim2.fromScale(1, 0.5)
	count.Size = UDim2.fromOffset(S.QueueCountWidth, S.QueuePillHeight)
	local people = HudParts.icon(count, "People")
	people.Position = UDim2.fromOffset(4, 2)
	people.Size = UDim2.fromOffset(S.QueuePillHeight - 4, S.QueuePillHeight - 4)
	self.players = HudParts.text(count, "Players", K.Text.Body, "")
	self.players.AutoLocalize = false -- only numbers
	self.players.Position = UDim2.fromOffset(S.QueuePillHeight, 1)
	self.players.Size = UDim2.new(1, -S.QueuePillHeight - 6, 1, -2)

	-- Waiting for an opponent or players, or starting in 3.
	self.statusFold = fold(content, "StatusFold", 2)
	self.status = HudParts.note(self.statusFold.inner, "Status", K.Text.Body, "")
	self.status.TextWrapped = false
	self.status.Size = UDim2.new(1, 0, 0, K.Text.Body + S.QueueMenuLineGap)

	-- Ask the server for players, and alone on a 1v1 table play by yourself: against the PC
	-- (bots come before release, Roadmap 2.4; until then it does nothing) or solo.
	self.request = button(
		content,
		"Request",
		Copy.RequestOpponent,
		3,
		"Yellow",
		"People",
		function()
			if self:canRequest() then
				self.requestedAt = self.now
				self.onAction("RequestOpponent", nil)
			end
		end
	)
	self.more = fold(content, "More", 4)
	self.pc = button(self.more.inner, "PlayPC", Copy.PlayPC, 1, "Blue", "Robot", function() end)
	self.solo = button(self.more.inner, "PlaySolo", Copy.PlaySolo, 2, "Green", "Person", function()
		if self:canSend() and self:alone() then
			self.sentAt = self.now
			self.onAction("StartSolo", nil)
		end
	end)

	self.hint = HudParts.note(content, "GamepadHint", K.Text.Min, Copy.GamepadHint)
	self.hint.TextWrapped = false
	self.hint.Size = UDim2.new(1, 0, 0, K.Text.Min + S.QueueMenuLineGap)
	self.hint.LayoutOrder = 6
	return self
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

--- The host alone on a 1v1 table: Play solo and Play against PC are offered. The team tables
--- are kept for team games (designer, 2026-09-26).
function QueueMenu.alone(self: any): boolean
	return self.snapshot ~= nil
		and self:isHost()
		and self:count() == 1
		and self.snapshot.teamSize == 1
end

function QueueMenu.canSend(self: any): boolean
	return self.now - self.sentAt >= M.ActionRetrySeconds
end

--- Whether a request may be sent: the pad has room, and no request within the cooldown (the
--- server's record or this card's own press, whichever is later).
function QueueMenu.canRequest(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot or not self:isHost() or self:count() >= snapshot.teamSize * 2 then
		return false
	end
	local last = math.max(self.requestedAt, snapshot.requestedAt or -math.huge)
	return self.now - last >= M.Queue.RequestSeconds
end

-- Show or hide the card, popping it in or out.
function QueueMenu.setOpen(self: any, open: boolean)
	if open == self.open then
		return
	end
	self.open = open
	if open then
		self.snap = true
		self.root.Visible = true
		self.card.Visible = false
		UIAnim.popIn(self.card)
	else
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
		self.sentAt, self.requestedAt = -math.huge, -math.huge
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

-- Whether a control can be seen and pressed: shown, and not inside a folded-away part.
function QueueMenu.usable(self: any, object: GuiObject): boolean
	local node: Instance? = object
	while node and node ~= self.root do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return object.Selectable
end

--- Put the gamepad on the card: the first control there is to press.
function QueueMenu.focus(self: any)
	if not self.root.Visible then
		return
	end
	for _, object in { self.request, self.solo, self.pc } do
		if self:usable(object) then
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

-- Size the card to its rows and place it (designer, 2026-09-27: keep it out of the way). A
-- screen at least QueueWideMinHeight tall (PC, console, tablet) has it on the right, halfway
-- down, at full size. A phone-sized one has it tucked into the top right corner at
-- QueueCornerScale, shrunk further if it is short; on a touch screen it keeps clear of the
-- jump button, flush right when it fits above it, else just left of it.
function QueueMenu.layout(self: any)
	local screen: any = self.root.Parent
	if not screen then
		return
	end
	local size: Vector2 = screen.AbsoluteSize
	local margin = S.HeaderMargin
	local natural = self.list.AbsoluteContentSize.Y / self.scale.Scale + 2 * S.QueueMenuPadding
	self.root.Size = UDim2.fromOffset(S.QueueMenuWidth, natural)
	local function fit(room: number, most: number): number
		return math.clamp(room / math.max(natural, 1), S.QueueMenuMinScale, most)
	end
	if size.Y >= S.QueueWideMinHeight then
		self.scale.Scale = fit(size.Y - 2 * margin, 1)
		self.root.AnchorPoint = Vector2.new(1, 0.5)
		self.root.Position = UDim2.new(1, -margin, 0.5, 0)
		return
	end
	local most = S.QueueCornerScale
	local right, scale = margin, fit(size.Y - 2 * margin, most)
	local jump = jumpButton()
	if jump then
		local jumpTop = jump.AbsolutePosition.Y - screen.AbsolutePosition.Y
		local jumpLeft = jump.AbsolutePosition.X - screen.AbsolutePosition.X
		local above = fit(jumpTop - 2 * margin, most)
		if above < scale then
			right = size.X - jumpLeft + margin
		else
			scale = above
		end
	elseif UserInputService.TouchEnabled then
		right = S.QueueTouchRight
	end
	self.scale.Scale = scale
	self.root.AnchorPoint = Vector2.new(1, 0)
	self.root.Position = UDim2.new(1, -right, 0, margin)
end

-- Ease a fold toward open (1) or folded (0) over about Style.QueueFoldSeconds; `snap` jumps.
-- `scale` is the card's UIScale: the rows' measured height includes it, their offsets do not.
local function ease(part: any, open: boolean, dt: number, snap: boolean, scale: number)
	local goal = if open then 1 else 0
	if snap then
		part.amount = goal
	else
		part.amount += (goal - part.amount) * (1 - math.exp(-dt * 4 / S.QueueFoldSeconds))
		if math.abs(goal - part.amount) < 0.01 then
			part.amount = goal
		end
	end
	local amount = part.amount
	local height = part.inner.AbsoluteSize.Y / math.max(scale, 0.01)
	part.group.Visible = amount > 0
	part.group.GroupTransparency = 1 - amount
	part.group.Size = UDim2.new(1, 0, 0, height * amount)
end

--- Redraw from the snapshot. Called every frame while seated; only writes what changed
--- matters to Roblox, and nothing here is expensive.
function QueueMenu.update(self: any, now: number)
	local dt = math.clamp(now - self.now, 0, 0.1)
	self.now = now
	local snapshot = self.snapshot
	local host = snapshot ~= nil and self:isHost()
	self:setOpen(host)
	if not host then
		return
	end
	local count = self:count()
	local teamSize = snapshot.teamSize
	local capacity = teamSize * 2
	local difficulty = snapshot.settings and snapshot.settings.difficulty
		or Config.Difficulty.Default
	HudParts.setIcon(self.level, difficulty)
	self.game.Text = Copy.GameTitle:format(
		Copy.Levels[difficulty] or "",
		Strings.Match.Mode:format(teamSize, teamSize)
	)
	self.players.Text = Copy.PlayerCount:format(count, capacity)
	self.status.Text = if snapshot.startsAt
		then Copy.StartingIn:format(math.max(1, math.ceil(snapshot.startsAt - now)))
		elseif teamSize == 1 then Copy.WaitingForOpponent
		else Copy.WaitingForPlayers

	-- Folded while a request stands and the pad still has room: just the game and Requested!
	local sending = not self:canSend()
	local room = count < capacity
	local canRequest = self:canRequest()
	local folded = room and not canRequest
	self.request.Visible = room and not sending
	HudParts.setEnabled(self.request, canRequest)
	HudParts.setText(
		self.request,
		if not canRequest
			then Copy.Requested
			elseif teamSize == 1 then Copy.RequestOpponent
			else Copy.RequestPlayers
	)
	local alone = self:alone()
	self.pc.Visible = alone and not sending
	self.solo.Visible = alone and not sending
	local scale = self.scale.Scale
	ease(self.statusFold, not folded, dt, self.snap, scale)
	ease(self.more, alone and not folded and not sending, dt, self.snap, scale)
	self.snap = false

	local gamepad = UserInputService:GetLastInputType() == Enum.UserInputType.Gamepad1
	self.hint.Visible = gamepad and not self:focused() and self.request.Visible
	-- A selection left on a control that just hid, folded away or dimmed would keep the stick
	-- off the character: move it to what is there now, or let go.
	local selected = GuiService.SelectedObject
	if
		selected
		and selected:IsDescendantOf(self.root)
		and not self:usable(selected :: GuiObject)
	then
		GuiService.SelectedObject = nil
		self:focus()
	end
	self:layout()
end

return QueueMenu
