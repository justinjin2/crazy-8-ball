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
-- Once the host requests, the card folds up to the game, "Requested!" and a red Cancel (the
-- waiting line and Play against PC and Play solo slide away) and unfolds again if nobody
-- came within Queue.RequestSeconds (designer, 2026-09-27). Cancel takes the request back:
-- everyone's popup closes and the card unfolds at once; the host may ask again after
-- Queue.RerequestSeconds.
--
-- The global queue (designer, 2026-09-28): Join Global Queue, the 4th choice, searches every
-- server for a side of similar rank (1v1 alone; 2v2 needs 2 on the pad, 3v3 needs 3, and the
-- first whole side by arrival goes). The card folds like a request, to "Searching
-- worldwide..." with the time on the button and the red Cancel; "Match found!" and the
-- teleport screen follow. Stepping off the pad cancels too.
--
-- The Ults: On / Off toggle under Join Global Queue and its "search with ults on?" offer
-- were removed (designer, 2026-10-02): every search plays with ults on.
--
-- Difficulty (designer, 2026-09-30): Classic, Difficult and Challenger side by side under the
-- title, the picked one lit, while the pad waits and no search runs. Difficult and Challenger
-- unlock at Gold I (designer, 2026-10-02; Config.Ranks.Unlocks, Ranks.canHost): below it they
-- are greyed with "Requires Gold I+" under them (a padlock on the button crowded the word). The server takes SetDifficulty
-- from the host only, before the game, only at a rank that may host it, and resets it after
-- every game; the money multiplier stays off.
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
local Ranks = require(Shared:WaitForChild("Progression"):WaitForChild("Ranks"))
local HudParts = require(script.Parent.HudParts)
local UIAnim = require(script.Parent.UIAnim)
local Copy = Strings.Match.Queue
local M = Config.Multiplayer
local S = M.Style
local QueueMenu = {}
QueueMenu.__index = QueueMenu

-- A part of the card that folds away: a CanvasGroup whose height and fade follow `amount`
-- (0 folded, 1 open), clipping the rows inside as it closes. It reaches QueueFoldSidePx past
-- the card's column on both sides (the column centres it) and pads its rows back in, so a
-- button's outline, and its grow and gold outline when hovered or selected, is never cut.
local function fold(parent: Instance, name: string, order: number): any
	local group = Instance.new("CanvasGroup")
	group.Name = name
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.LayoutOrder = order
	group.Size = UDim2.new(1, 2 * S.QueueFoldSidePx, 0, 0)
	group.Parent = parent
	local inner = HudParts.frame(group, "Inner")
	inner.Size = UDim2.fromScale(1, 0)
	inner.AutomaticSize = Enum.AutomaticSize.Y
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, S.QueueRowGap)
	list.Parent = inner
	local edge = Instance.new("UIPadding")
	edge.PaddingTop = UDim.new(0, S.QueueFoldEdgePx)
	edge.PaddingBottom = UDim.new(0, S.QueueFoldEdgePx)
	edge.PaddingLeft = UDim.new(0, S.QueueFoldSidePx)
	edge.PaddingRight = UDim.new(0, S.QueueFoldSidePx)
	edge.Parent = inner
	return { group = group, inner = inner, list = list, amount = 0 }
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
	object.Size = UDim2.new(1, 0, 0, S.QueueButtonHeight)
	HudParts.setButtonTextSize(object, S.QueueText.Button)
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
	self.cancelledAt = -math.huge -- this host's last Cancel: older requests no longer stand
	self.searchAt = -math.huge -- this host's last Join Global Queue, before the server's answer
	self.searchCancelledAt = -math.huge -- and their last Cancel of it
	self.levelSent = nil :: { value: string, at: number }? -- a difficulty on its way
	self.now = 0
	self.open = false
	self.away = false -- the host stepped off the pad; the server lets them go shortly
	self.snap = true -- the folds jump to where they belong the next frame (on opening)

	-- The holder is fitted to the screen (its UIScale); the card inside pops in and out.
	local root = HudParts.frame(screen, "QueueMenu")
	root.AnchorPoint = Vector2.new(1, 0)
	root.Size = UDim2.fromOffset(S.QueueMenuWidth, 0)
	root.Visible = false
	self.root = root
	self.scale = Instance.new("UIScale")
	self.scale.Parent = root
	-- A menu card: the title row ("Classic 1v1" and the count) is its header band, the choices
	-- sit on the sheet under it.
	local card = HudParts.menuCard(root, "Card")
	HudParts.setSheetTop(
		card,
		S.QueueMenuPadding + S.QueueTitleHeight + math.floor(S.QueueRowGap / 2)
	)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.5)
	card.Size = UDim2.fromScale(1, 1)
	self.card = card
	local content = HudParts.frame(card, "Content")
	content.Position = UDim2.fromOffset(S.QueueMenuPadding, S.QueueMenuPadding)
	content.Size = UDim2.new(1, -S.QueueMenuPadding * 2, 1, -S.QueueMenuPadding * 2)
	-- The rows are stacked by QueueMenu.stack (not a UIListLayout), so a button fold's room
	-- for its outlines overlaps the gaps round it and every button is QueueRowGap from the next.
	self.content = content

	-- The game: the difficulty's picture and "Classic 1v1", and how many are in.
	local title = HudParts.frame(content, "Title")
	title.Size = UDim2.new(1, 0, 0, S.QueueTitleHeight)
	title.LayoutOrder = 1
	local iconSize = S.QueueTitleHeight
	self.level = HudParts.icon(title, Config.Difficulty.Default, "LevelIcon")
	self.level.Size = UDim2.fromOffset(iconSize, iconSize)
	self.game = HudParts.text(title, "Game", S.QueueText.Title, "")
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
	self.players = HudParts.text(count, "Players", S.QueueText.Count, "")
	self.players.AutoLocalize = false -- only numbers
	self.players.Position = UDim2.fromOffset(S.QueuePillHeight, 1)
	self.players.Size = UDim2.new(1, -S.QueuePillHeight - 6, 1, -2)

	-- The difficulty picker (TEMPORARY): one button per level, side by side.
	local levels = HudParts.frame(content, "Levels")
	levels.Size = UDim2.new(1, 0, 0, S.QueueLevelHeight)
	self.levelRow = levels
	self.levelButtons = {} :: { [string]: TextButton }
	self.levelLocks = {} :: { [string]: TextLabel } -- "Requires Gold I+" under a locked level
	local order = Config.Difficulty.Order
	local gap = S.QueueRowGap
	for i, level in order do
		local b = button(levels, level, Copy.Levels[level] or level, i, "White", nil, function()
			if self:canSetLevel() and self:pickedLevel() ~= level then
				self.levelSent = { value = level, at = self.now }
				self.onAction("SetDifficulty", level)
			end
		end)
		local share = 1 / #order
		b.Position = UDim2.new(share * (i - 1), math.floor(gap * (i - 1) / #order), 0, 0)
		b.Size = UDim2.new(share, -math.ceil(gap * (#order - 1) / #order), 0, S.QueueLevelHeight)
		HudParts.setMinHit(b, 44)
		HudParts.setButtonTextSize(b, S.QueueText.Level)
		self.levelButtons[level] = b
		local need = Ranks.unlockName(level)
		if need then
			local lock = HudParts.note(
				levels,
				level .. "Lock",
				S.QueueText.Small,
				Copy.LevelLocked:format(need)
			)
			lock.TextWrapped = false
			lock.Position =
				UDim2.new(b.Position.X.Scale, b.Position.X.Offset, 0, S.QueueLevelHeight + 2)
			lock.Size = UDim2.new(b.Size.X.Scale, b.Size.X.Offset, 0, S.QueueText.Small + 2)
			lock.Visible = false
			self.levelLocks[level] = lock
		end
	end

	-- Waiting for an opponent or players, or starting in 3.
	self.statusFold = fold(content, "StatusFold", 2)
	self.status = HudParts.note(self.statusFold.inner, "Status", S.QueueText.Status, "")
	self.status.RichText = true -- the waiting dots (dots)
	self.status.TextWrapped = false
	self.status.Size = UDim2.new(1, 0, 0, S.QueueText.Status + S.QueueMenuLineGap)

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
	-- The global queue: every server, by rank (designer, 2026-09-28).
	self.global = button(
		content,
		"GlobalQueue",
		Copy.GlobalQueue,
		4,
		"Green", -- designer, 2026-10-02 (was blue)
		"Lightning",
		function()
			if self:canSearch() then
				self.searchAt = self.now
				self.onAction("GlobalSearch", nil)
			end
		end
	)
	-- On 2v2 and 3v3, why it is greyed: a whole side must be on the pad.
	self.needs = HudParts.note(content, "GlobalNeeds", S.QueueText.Small, "")
	self.needs.TextWrapped = false
	self.needs.Size = UDim2.new(1, 0, 0, S.QueueText.Small + S.QueueMenuLineGap)
	self.needs.LayoutOrder = 6
	-- While a request or a search stands: take it back, and the card unfolds at once.
	-- No icon: the kit's red X vanished on the red candy.
	self.cancel = button(content, "CancelRequest", Copy.CancelRequest, 8, "Red", nil, function()
		if self:searching() then
			if not self:found() then
				self.searchCancelledAt = self.now
				self.onAction("CancelSearch", nil)
			end
		elseif self:requestStands() then
			self.cancelledAt = self.now
			self.onAction("CancelRequest", nil)
		end
	end)
	self.more = fold(content, "More", 9)
	self.pc = button(self.more.inner, "PlayPC", Copy.PlayPC, 1, "Blue", "Robot", function() end)
	self.solo = button(self.more.inner, "PlaySolo", Copy.PlaySolo, 2, "Green", "Person", function()
		if self:canSend() and self:alone() then
			self.sentAt = self.now
			self.onAction("StartSolo", nil)
		end
	end)

	self.hint = HudParts.note(content, "GamepadHint", S.QueueText.Small, Copy.GamepadHint)
	self.hint.TextWrapped = false
	self.hint.Size = UDim2.new(1, 0, 0, S.QueueText.Small + S.QueueMenuLineGap)
	self.hint.LayoutOrder = 10
	-- Top to bottom. `overlap`: a fold of buttons, whose outline room sits over the gaps.
	self.rows = {
		{ object = title } :: any,
		{ object = levels },
		{ fold = self.statusFold },
		{ object = self.request },
		{ object = self.global },
		{ object = self.needs },
		{ object = self.cancel },
		{ fold = self.more, overlap = true },
		{ object = self.hint },
	}
	return self
end

--- Stack the card's shown rows from the top, QueueRowGap apart, centred across; answers the
--- height they take (unscaled). A fold counts by how open it is. A fold of buttons keeps its
--- QueueFoldEdgePx of room above and below them for their outlines, but that room lies over
--- the gaps either side instead of adding to them (designer, 2026-09-28: evenly spaced).
function QueueMenu.stack(self: any): number
	local y = 0
	local first = true
	for _, row in self.rows do
		local fold = row.fold
		local object: GuiObject = if fold then fold.group else row.object
		if not object.Visible then
			continue
		end
		local amount = if fold then fold.amount else 1
		local height = object.Size.Y.Offset
		local edge = if row.overlap then S.QueueFoldEdgePx * amount else 0
		if height - 2 * edge <= 0.5 then
			continue
		end
		if not first then
			y += S.QueueRowGap * math.min(1, amount)
		end
		object.AnchorPoint = Vector2.new(0.5, 0)
		object.Position = UDim2.new(0.5, 0, 0, y - edge)
		y += height - 2 * edge
		first = false
	end
	return y
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

--- Whether this host's request stands: the pad has room and a request (the server's record
--- or this card's own press, whichever is later) is under Queue.RequestSeconds old and was
--- not cancelled since.
function QueueMenu.requestStands(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot or not self:isHost() or self:count() >= snapshot.teamSize * 2 then
		return false
	end
	local server = snapshot.requestedAt or -math.huge
	local last = math.max(self.requestedAt, server)
	return last > self.cancelledAt and self.now - last < M.Queue.RequestSeconds
end

--- Whether this pad's global search is on: the server's record, or this card's own press
--- still on its way (and not cancelled since).
function QueueMenu.searching(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot then
		return false
	end
	local cancelling = self.searchCancelledAt > self.searchAt
		and self.now - self.searchCancelledAt < M.ActionRetrySeconds
	if snapshot.search then
		-- A Cancel on its way hides it, unless the search already found its match.
		return snapshot.search.found == true or not cancelling
	end
	return self.searchAt > self.searchCancelledAt
		and self.now - self.searchAt < M.ActionRetrySeconds
end

--- Whether the search found a match (its players are on their way).
function QueueMenu.found(self: any): boolean
	local snapshot = self.snapshot
	return snapshot ~= nil and snapshot.search ~= nil and snapshot.search.found == true
end

--- The difficulty the picker shows: one on its way to the server, else the table's.
function QueueMenu.pickedLevel(self: any): string
	local sent = self.levelSent
	if sent and self.now - sent.at < M.ActionRetrySeconds then
		return sent.value
	end
	local settings = self.snapshot and self.snapshot.settings
	return settings and settings.difficulty or Config.Difficulty.Default
end

--- Whether this player's rank may host `level` (Ranks.canHost on the server-set RankIndex;
--- the server checks the same).
function QueueMenu.mayHost(_self: any, level: string): boolean
	local player = Players.LocalPlayer
	local index = player and player:GetAttribute("RankIndex")
	return Ranks.canHost({ index = if type(index) == "number" then index else 0 } :: any, level)
end

--- Whether the picker may be pressed: the host, the pad waiting with no search on and the
--- game not about to start (the server checks the host and the phase).
function QueueMenu.canSetLevel(self: any): boolean
	local snapshot = self.snapshot
	return snapshot ~= nil
		and self:isHost()
		and snapshot.phase == "Waiting"
		and snapshot.startsAt == nil
		and not self:searching()
end

--- Whether Join Global Queue may be pressed: the host, a whole side on the pad with room
--- left, no search on (MatchEngine.canSearch).
function QueueMenu.canSearch(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot or not self:isHost() or self:searching() then
		return false
	end
	local count = self:count()
	return count >= snapshot.teamSize and count < snapshot.teamSize * 2
end

--- Whether a request may be sent: the pad has room, none stands, and none was sent within
--- Queue.RerequestSeconds (after a Cancel), as the server checks.
function QueueMenu.canRequest(self: any): boolean
	local snapshot = self.snapshot
	if not snapshot or not self:isHost() or self:count() >= snapshot.teamSize * 2 then
		return false
	end
	return not self:requestStands() and self.now - self.requestedAt >= M.Queue.RerequestSeconds
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
		self.sentAt, self.requestedAt, self.cancelledAt = -math.huge, -math.huge, -math.huge
		self.searchAt, self.searchCancelledAt = -math.huge, -math.huge
		self.levelSent = nil
	end
	if not snapshot then
		self:blur()
		self:setOpen(false)
	end
end

--- The host has stepped off the pad (Main): hide the card now rather than after the server's
--- exit grace; stepping back on in time shows it again.
function QueueMenu.setAway(self: any, away: boolean)
	if away == self.away then
		return
	end
	self.away = away
	if away then
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
	for _, object in
		{
			self.request,
			self.levelButtons[Config.Difficulty.Default],
			self.global,
			self.cancel,
			self.solo,
			self.pc,
		}
	do
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
-- down (raised above a tablet's jump button), at QueueWideScale. A phone-sized one has it in the very top right corner at
-- QueueCornerScale, shrunk to end above the touch jump button when that shows (and only if
-- it cannot, just left of it).
function QueueMenu.layout(self: any)
	local screen: any = self.root.Parent
	if not screen then
		return
	end
	local size: Vector2 = screen.AbsoluteSize
	local margin = S.HeaderMargin
	local natural = self:stack() + 2 * S.QueueMenuPadding
	self.root.Size = UDim2.fromOffset(S.QueueMenuWidth, natural)
	local function fit(room: number, most: number): number
		return math.clamp(room / math.max(natural, 1), S.QueueMenuMinScale, most)
	end
	local jump = jumpButton()
	if size.Y >= S.QueueWideMinHeight then
		-- Halfway down, raised to end above a touch jump button (a tablet), and shrunk only if
		-- it cannot fit above it at all.
		local scale = fit(size.Y - 2 * margin, S.QueueWideScale)
		local centre = size.Y / 2
		if jump then
			local jumpTop = jump.AbsolutePosition.Y - screen.AbsolutePosition.Y
			scale = math.min(scale, fit(jumpTop - 2 * margin, S.QueueWideScale))
			centre = math.min(centre, jumpTop - margin - natural * scale / 2)
		end
		self.scale.Scale = scale
		self.root.AnchorPoint = Vector2.new(1, 0.5)
		self.root.Position = UDim2.new(1, -margin, 0, centre)
		return
	end
	-- The corner: flush right, and up beside Roblox's top bar, whose right side is free.
	local top = margin - GuiService:GetGuiInset().Y
	local most = S.QueueCornerScale
	local right, scale = margin, fit(size.Y - top - margin, most)
	if jump then
		-- Shrink to end above the jump button; only if it cannot, step left of it instead.
		local jumpTop = jump.AbsolutePosition.Y - screen.AbsolutePosition.Y
		local jumpLeft = jump.AbsolutePosition.X - screen.AbsolutePosition.X
		local above = (jumpTop - margin - top) / math.max(natural, 1)
		if above >= S.QueueMenuMinScale then
			scale = math.min(scale, above)
		elseif top + natural * scale > jumpTop - margin then
			right = size.X - jumpLeft + margin
		end
	end
	self.scale.Scale = scale
	self.root.AnchorPoint = Vector2.new(1, 0)
	self.root.Position = UDim2.new(1, -right, 0, top)
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
	part.group.Size = UDim2.new(1, 2 * S.QueueFoldSidePx, 0, height * amount)
end

-- "..." that lights up one dot at a time, then starts over, so the wait looks alive
-- (designer, 2026-09-27). The unlit dots are drawn clear, so the words never shift.
local function dots(now: number): string
	local lit = math.floor(now / S.QueueDotSeconds) % 4
	return string.rep(".", lit)
		.. '<font transparency="1">'
		.. string.rep(".", 3 - lit)
		.. "</font>"
end

--- Redraw from the snapshot. Called every frame while seated; only writes what changed
--- matters to Roblox, and nothing here is expensive.
function QueueMenu.update(self: any, now: number)
	local dt = math.clamp(now - self.now, 0, 0.1)
	self.now = now
	local snapshot = self.snapshot
	local host = snapshot ~= nil and self:isHost() and not self.away
	self:setOpen(host)
	if not host then
		return
	end
	local count = self:count()
	local teamSize = snapshot.teamSize
	local capacity = teamSize * 2
	local difficulty = self:pickedLevel()
	-- The picker: the picked level lit, all of them hidden while a search runs.
	self.levelRow.Visible = not self:searching()
	local canLevel = self:canSetLevel()
	local anyLocked = false
	for level, b in self.levelButtons do
		local locked = not self:mayHost(level)
		anyLocked = anyLocked or locked
		HudParts.setTone(
			b,
			if locked then "Grey" elseif level == difficulty then S.QueueLevelPickedTone else "White"
		)
		HudParts.setEnabled(b, canLevel and not locked, locked or not canLevel)
		local lock = self.levelLocks[level]
		if lock then
			lock.Visible = locked
		end
	end
	-- Room under the row for "Requires Gold I+" while a level is locked.
	local rowHeight = S.QueueLevelHeight + (if anyLocked then S.QueueText.Small + 4 else 0)
	if self.levelRow.Size.Y.Offset ~= rowHeight then
		self.levelRow.Size = UDim2.new(1, 0, 0, rowHeight)
	end
	HudParts.setIcon(self.level, difficulty)
	self.game.Text = Copy.GameTitle:format(
		Copy.Levels[difficulty] or "",
		Strings.Match.Mode:format(teamSize, teamSize)
	)
	self.players.Text = Copy.PlayerCount:format(count, capacity)
	local searching = self:searching()
	local found = self:found()
	self.status.Text = if snapshot.startsAt
		then Copy.StartingIn:format(math.max(1, math.ceil(snapshot.startsAt - now)))
		elseif found then Copy.MatchFound
		elseif searching then Copy.SearchingWorld .. dots(now)
		elseif teamSize == 1 then Copy.WaitingForOpponent .. dots(now)
		else Copy.WaitingForPlayers .. dots(now)

	-- Folded while a request or a search stands and the pad still has room: just the game,
	-- Requested! (or the search's time) and Cancel.
	local sending = not self:canSend()
	local room = count < capacity
	local stands = self:requestStands()
	local folded = room and (stands or searching)
	self.request.Visible = room and not sending and not searching
	HudParts.setEnabled(self.request, self:canRequest())
	-- Join Global Queue, or the search's time while it looks.
	self.global.Visible = room and not sending and not stands
	HudParts.setEnabled(self.global, self:canSearch())
	local since = if snapshot.search then snapshot.search.at else self.searchAt
	local waited = math.max(0, math.floor(now - since))
	HudParts.setText(
		self.global,
		if found
			then Copy.MatchFound
			elseif searching then Copy.SearchTime:format(waited // 60, waited % 60)
			else Copy.GlobalQueue
	)
	self.needs.Visible = room and teamSize > 1 and count < teamSize and not searching
	if self.needs.Visible then
		self.needs.Text = Copy.GlobalNeeds:format(teamSize)
	end
	HudParts.setText(
		self.request,
		if stands
			then Copy.Requested
			elseif teamSize == 1 then Copy.RequestOpponent
			else Copy.RequestPlayers
	)
	self.cancel.Visible = folded and not sending and not found
	local alone = self:alone()
	self.pc.Visible = alone and not sending
	self.solo.Visible = alone and not sending
	local scale = self.scale.Scale
	-- The waiting line folds away for a request; a search keeps it, saying it searches.
	ease(self.statusFold, not folded or searching, dt, self.snap, scale)
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
